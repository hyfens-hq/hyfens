import 'dart:convert';
import 'dart:typed_data';

import 'package:postgres/postgres.dart';

import 'encoding.dart';
import 'errors.dart';
import 'p3e_persistence.dart';
import 'p3e_schedule_persistence.dart';
import 'persistence.dart';
import 'postgres_faults.dart';

/// Versioned schema statements kept in code so a packaged binary does not
/// depend on its current working directory. The matching SQL file is shipped
/// for operators and migration review.
const int postgresSchemaVersion = 8;

const List<String> postgresMigration001 = <String>[
  '''CREATE TABLE IF NOT EXISTS control_plane_schema_migrations (
  version integer PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_records (
  collection text NOT NULL,
  record_id text NOT NULL,
  organization_id text,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (collection, record_id)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_records_tenant_idx
  ON control_plane_records (organization_id, collection, record_id)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_artifacts (
  digest text PRIMARY KEY,
  artifact_bytes bytea NOT NULL,
  size_bytes bigint NOT NULL CHECK (size_bytes >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_audit_chain (
  sequence bigserial PRIMARY KEY,
  audit_id text NOT NULL UNIQUE,
  organization_id text,
  previous_digest text,
  record_digest text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
)''',
];

const List<String> postgresMigration002 = <String>[
  '''CREATE TABLE IF NOT EXISTS control_plane_observations (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  environment_id text NOT NULL,
  event_id text NOT NULL,
  event_type text NOT NULL,
  release_id text NOT NULL,
  patch_id text,
  sequence bigint,
  rollout_id text,
  rollout_revision bigint,
  received_at timestamptz NOT NULL,
  body jsonb NOT NULL,
  PRIMARY KEY (organization_id, application_id, environment_id, event_id)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_observations_scope_idx
  ON control_plane_observations
    (organization_id, application_id, environment_id, received_at)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_observations_event_type_idx
  ON control_plane_observations
    (organization_id, application_id, environment_id, event_type, received_at)''',
];

const List<String> postgresMigration003 = p3ePostgresMigration003;
const List<String> postgresMigration004 = p3ePostgresMigration004;
const List<String> postgresMigration005 = p3e5PostgresMigration005;
const List<String> postgresMigration006 = p3e5PostgresMigration006;
const List<String> postgresMigration007 = p3e5PostgresMigration007;

/// P3E5-5B append-only reconciliation findings/repairs plus versioned
/// lifecycle/cursor projections.
const List<String> postgresMigration008 = <String>[
  '''CREATE TABLE IF NOT EXISTS control_plane_reconciliation_findings (
  organization_id text NOT NULL,
  application_id text,
  environment_id text,
  finding_id text NOT NULL,
  body jsonb NOT NULL,
  body_digest text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, finding_id),
  CHECK (jsonb_typeof(body) = 'object')
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_reconciliation_findings_scope_idx
  ON control_plane_reconciliation_findings
    (organization_id, application_id, environment_id, finding_id)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_reconciliation_repairs (
  organization_id text NOT NULL,
  application_id text,
  environment_id text,
  repair_id text NOT NULL,
  finding_id text NOT NULL,
  body jsonb NOT NULL,
  body_digest text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, repair_id),
  CHECK (jsonb_typeof(body) = 'object')
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_reconciliation_repairs_scope_idx
  ON control_plane_reconciliation_repairs
    (organization_id, application_id, environment_id, repair_id)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_reconciliation_lifecycle (
  organization_id text NOT NULL,
  application_id text,
  environment_id text,
  finding_id text NOT NULL,
  version bigint NOT NULL CHECK (version >= 0),
  body jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, finding_id),
  CHECK (jsonb_typeof(body) = 'object')
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_reconciliation_lifecycle_scope_idx
  ON control_plane_reconciliation_lifecycle
    (organization_id, application_id, environment_id, finding_id)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_reconciliation_cursors (
  organization_id text NOT NULL,
  application_id text,
  environment_id text,
  scope_digest text NOT NULL,
  version bigint NOT NULL CHECK (version >= 0),
  body jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, scope_digest),
  CHECK (jsonb_typeof(body) = 'object')
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_reconciliation_cursors_scope_idx
  ON control_plane_reconciliation_cursors
    (organization_id, application_id, environment_id, scope_digest)''',
];

/// Deterministic fault points used by bounded integration evidence. The
/// callback is null in normal production construction and does not alter the
/// transaction or rollout authority semantics.
enum PostgresRolloutTransitionFailurePoint { beforeCommit, afterCommit }

/// PostgreSQL-backed implementation of [ControlPlaneStore].
///
/// Domain records remain canonical JSON at this seam so the existing service
/// semantics are preserved. Tenant ownership is persisted in a separate
/// indexed column and is never inferred from a caller-controlled query. Unique
/// keys and transactional migrations provide cross-process idempotency and
/// startup safety that a single-process file queue cannot provide.
final class PostgresControlPlaneStore
    implements ControlPlaneStore, ArtifactInventory, ConditionalJsonStore {
  PostgresControlPlaneStore(
    String connectionString, {
    ArtifactStore? artifacts,
    this.rolloutTransitionFailure,
    this.disconnectInjector,
  }) : _pool = Pool.withUrl(connectionString),
       _artifacts = artifacts;

  PostgresControlPlaneStore.withPool(
    Pool pool, {
    ArtifactStore? artifacts,
    this.rolloutTransitionFailure,
    this.disconnectInjector,
  }) : _pool = pool,
       _artifacts = artifacts;

  final Pool _pool;
  final ArtifactStore? _artifacts;
  final void Function(PostgresRolloutTransitionFailurePoint point)?
  rolloutTransitionFailure;

  /// Test-only fault injection. Production callers leave this null.
  final PostgresDisconnectInjector? disconnectInjector;
  bool _initialized = false;

  Future<void> _disconnectIfRequested(PostgresDisconnectPoint point) async {
    if (disconnectInjector?.call(point) != true) return;
    await _pool.close(force: true);
    throw StorageUnavailable(
      'Injected PostgreSQL connection loss at ${point.name}',
    );
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _pool.runTx((session) async {
      // Multiple control-plane instances may initialize against the same
      // database at once during a rolling start. Serialize the migration DDL
      // before any CREATE TYPE/CREATE TABLE work so PostgreSQL's catalog
      // preparation cannot race between sessions.
      await session.execute('SELECT pg_advisory_xact_lock(7812450)');
      await session.execute(postgresMigration001[0]);
      final versionRows = await session.execute(
        'SELECT COALESCE(MAX(version), 0) AS version '
        'FROM control_plane_schema_migrations',
      );
      var currentVersion = int.parse(
        '${versionRows.first.toColumnMap()['version']}',
      );
      if (currentVersion > postgresSchemaVersion) {
        throw StorageConflict(
          'Unsupported control-plane schema version: $currentVersion',
        );
      }
      if (currentVersion < 1) {
        for (final statement in postgresMigration001.skip(1)) {
          await session.execute(statement);
        }
        await session.execute(
          Sql.named(
            'INSERT INTO control_plane_schema_migrations(version) '
            'VALUES (@version:int4) ON CONFLICT (version) DO NOTHING',
          ),
          parameters: const <String, Object?>{'version': 1},
        );
        currentVersion = 1;
      }
      if (currentVersion < 2) {
        for (final statement in postgresMigration002) {
          await session.execute(statement);
        }
        await session.execute(
          Sql.named(
            'INSERT INTO control_plane_schema_migrations(version) '
            'VALUES (@version:int4) ON CONFLICT (version) DO NOTHING',
          ),
          parameters: const <String, Object?>{'version': 2},
        );
        currentVersion = 2;
      }
      if (currentVersion < 3) {
        for (final statement in postgresMigration003) {
          await session.execute(statement);
        }
        await session.execute(
          Sql.named(
            'INSERT INTO control_plane_schema_migrations(version) '
            'VALUES (@version:int4) ON CONFLICT (version) DO NOTHING',
          ),
          parameters: const <String, Object?>{'version': 3},
        );
        currentVersion = 3;
      }
      if (currentVersion < 4) {
        for (final statement in postgresMigration004) {
          await session.execute(statement);
        }
        await session.execute(
          Sql.named(
            'INSERT INTO control_plane_schema_migrations(version) '
            'VALUES (@version:int4) ON CONFLICT (version) DO NOTHING',
          ),
          parameters: const <String, Object?>{'version': 4},
        );
        currentVersion = 4;
      }
      if (currentVersion < 5) {
        for (final statement in postgresMigration005) {
          await session.execute(statement);
        }
        await session.execute(
          Sql.named(
            'INSERT INTO control_plane_schema_migrations(version) '
            'VALUES (@version:int4) ON CONFLICT (version) DO NOTHING',
          ),
          parameters: const <String, Object?>{'version': 5},
        );
        currentVersion = 5;
      }
      if (currentVersion < 6) {
        for (final statement in postgresMigration006) {
          await session.execute(statement);
        }
        await session.execute(
          Sql.named(
            'INSERT INTO control_plane_schema_migrations(version) '
            'VALUES (@version:int4) ON CONFLICT (version) DO NOTHING',
          ),
          parameters: const <String, Object?>{'version': 6},
        );
        currentVersion = 6;
      }
      if (currentVersion < 7) {
        for (final statement in postgresMigration007) {
          await session.execute(statement);
        }
        await session.execute(
          Sql.named(
            'INSERT INTO control_plane_schema_migrations(version) '
            'VALUES (@version:int4) ON CONFLICT (version) DO NOTHING',
          ),
          parameters: const <String, Object?>{'version': 7},
        );
        currentVersion = 7;
      }
      if (currentVersion < 8) {
        for (final statement in postgresMigration008) {
          await session.execute(statement);
        }
        await session.execute(
          Sql.named(
            'INSERT INTO control_plane_schema_migrations(version) '
            'VALUES (@version:int4) ON CONFLICT (version) DO NOTHING',
          ),
          parameters: const <String, Object?>{'version': 8},
        );
      }
    });
    _initialized = true;
  }

  @override
  Future<void> close() => _pool.close();

  @override
  Future<void> checkReadiness() async {
    await _pool.execute('SELECT 1');
    final readiness = _artifacts;
    if (readiness case final ArtifactStoreReadiness probe) {
      await probe.checkReadiness();
    }
  }

  @override
  Future<Map<String, Object?>?> readJson(String collection, String id) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT body::text AS body_json FROM control_plane_records '
        'WHERE collection = @collection:text AND record_id = @id:text',
      ),
      parameters: <String, Object?>{'collection': collection, 'id': id},
    );
    if (result.isEmpty) return null;
    return _decodeBody(result.first.toColumnMap()['body_json']);
  }

  @override
  Future<List<Map<String, Object?>>> listJson(String collection) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT body::text AS body_json FROM control_plane_records '
        'WHERE collection = @collection:text ORDER BY record_id',
      ),
      parameters: <String, Object?>{'collection': collection},
    );
    return List.unmodifiable(
      result.map((row) => _decodeBody(row.toColumnMap()['body_json'])),
    );
  }

  @override
  Future<void> createJson(
    String collection,
    String id,
    Map<String, Object?> value,
  ) async {
    final canonical = canonicalJson(value);
    await _pool.execute(
      Sql.named(
        'INSERT INTO control_plane_records '
        '(collection, record_id, organization_id, body) '
        'VALUES (@collection:text, @id:text, @organization:text, @body:jsonb) '
        'ON CONFLICT (collection, record_id) DO NOTHING',
      ),
      parameters: <String, Object?>{
        'collection': collection,
        'id': id,
        'organization': value['organizationId'],
        'body': value,
      },
    );
    final existing = await readJson(collection, id);
    if (existing == null || canonicalJson(existing) != canonical) {
      if (existing == null) {
        throw const StorageConflict('Record insert did not persist');
      }
      throw const StorageConflict('Immutable record already exists');
    }
  }

  @override
  Future<void> replaceJson(
    String collection,
    String id,
    Map<String, Object?> value,
  ) async {
    final result = await _pool.execute(
      Sql.named(
        'UPDATE control_plane_records SET organization_id = @organization:text, '
        'body = @body:jsonb, updated_at = now() '
        'WHERE collection = @collection:text AND record_id = @id:text',
      ),
      parameters: <String, Object?>{
        'collection': collection,
        'id': id,
        'organization': value['organizationId'],
        'body': value,
      },
    );
    if (result.affectedRows != 1) {
      throw const StorageConflict('Record does not exist');
    }
  }

  @override
  Future<void> replaceJsonBatch(
    String collection,
    Map<String, Map<String, Object?>> values,
  ) async {
    if (values.isEmpty) return;
    final entries = values.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    await _pool.runTx((session) async {
      for (final entry in entries) {
        final result = await session.execute(
          Sql.named(
            'SELECT record_id FROM control_plane_records '
            'WHERE collection = @collection:text AND record_id = @id:text '
            'FOR UPDATE',
          ),
          parameters: <String, Object?>{
            'collection': collection,
            'id': entry.key,
          },
        );
        if (result.isEmpty) {
          throw const StorageConflict('Record does not exist');
        }
      }
      for (final entry in entries) {
        final result = await session.execute(
          Sql.named(
            'UPDATE control_plane_records SET organization_id = @organization:text, '
            'body = @body:jsonb, updated_at = now() '
            'WHERE collection = @collection:text AND record_id = @id:text',
          ),
          parameters: <String, Object?>{
            'collection': collection,
            'id': entry.key,
            'organization': entry.value['organizationId'],
            'body': entry.value,
          },
        );
        if (result.affectedRows != 1) {
          throw const StorageConflict('Record does not exist');
        }
      }
    });
  }

  @override
  Future<bool> replaceJsonIfCurrent({
    required String collection,
    required String id,
    required Map<String, Object?> expected,
    required Map<String, Object?> replacement,
  }) async {
    return replaceJsonBatchIfCurrent(
      collection: collection,
      expected: <String, Map<String, Object?>>{id: expected},
      replacements: <String, Map<String, Object?>>{id: replacement},
    );
  }

  @override
  Future<bool> replaceJsonBatchIfCurrent({
    required String collection,
    required Map<String, Map<String, Object?>> expected,
    required Map<String, Map<String, Object?>> replacements,
  }) async {
    if (expected.isEmpty || expected.length != replacements.length) {
      throw const StorageConflict('Conditional replacement set is invalid');
    }
    final expectedKeys = expected.keys.toSet();
    if (!expectedKeys.containsAll(replacements.keys) ||
        !replacements.keys.toSet().containsAll(expectedKeys)) {
      throw const StorageConflict('Conditional replacement set is invalid');
    }
    final entries = expected.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return _pool.runTx((session) async {
      for (final entry in entries) {
        final result = await session.execute(
          Sql.named(
            'SELECT record_id FROM control_plane_records '
            'WHERE collection = @collection:text AND record_id = @id:text '
            'AND body = @body:jsonb FOR UPDATE',
          ),
          parameters: <String, Object?>{
            'collection': collection,
            'id': entry.key,
            'body': entry.value,
          },
        );
        if (result.isEmpty) return false;
      }
      for (final entry in entries) {
        final result = await session.execute(
          Sql.named(
            'UPDATE control_plane_records SET organization_id = @organization:text, '
            'body = @body:jsonb, updated_at = now() '
            'WHERE collection = @collection:text AND record_id = @id:text',
          ),
          parameters: <String, Object?>{
            'collection': collection,
            'id': entry.key,
            'organization': replacements[entry.key]!['organizationId'],
            'body': replacements[entry.key],
          },
        );
        if (result.affectedRows != 1) {
          throw const StorageConflict('Record does not exist');
        }
      }
      return true;
    });
  }

  @override
  Future<Map<String, Object?>?> touchSessionIfActive({
    required String id,
    required String expectedSecretHash,
    required DateTime now,
  }) async {
    final result = await _pool.runTx(
      (session) => session.execute(
        Sql.named(
          'UPDATE control_plane_records '
          'SET body = jsonb_set(body, \'{lastUsedAt}\', '
          'to_jsonb(@last_used_at:text), true), updated_at = now() '
          'WHERE collection = \'sessions\' AND record_id = @id:text '
          'AND body->>\'secretHash\' = @secret_hash:text '
          'AND body->>\'revokedAt\' IS NULL '
          'AND (body->>\'expiresAt\')::timestamptz > @now:timestamptz '
          'RETURNING body::text AS body_json',
        ),
        parameters: <String, Object?>{
          'id': id,
          'secret_hash': expectedSecretHash,
          'last_used_at': now.toUtc().toIso8601String(),
          'now': now.toUtc(),
        },
      ),
    );
    if (result.isEmpty) return null;
    return _decodeBody(result.first.toColumnMap()['body_json']);
  }

  @override
  Future<bool> revokeSessionIfActive({
    required String id,
    required String expectedSecretHash,
    required DateTime revokedAt,
  }) async {
    final result = await _pool.runTx(
      (session) => session.execute(
        Sql.named(
          'UPDATE control_plane_records '
          'SET body = jsonb_set(body, \'{revokedAt}\', '
          'to_jsonb(@revoked_at:text), true), updated_at = now() '
          'WHERE collection = \'sessions\' AND record_id = @id:text '
          'AND body->>\'secretHash\' = @secret_hash:text '
          'AND body->>\'revokedAt\' IS NULL '
          'RETURNING record_id',
        ),
        parameters: <String, Object?>{
          'id': id,
          'secret_hash': expectedSecretHash,
          'revoked_at': revokedAt.toUtc().toIso8601String(),
        },
      ),
    );
    return result.isNotEmpty;
  }

  @override
  Future<void> putArtifact(String digest, List<int> bytes) async {
    final artifacts = _artifacts;
    if (artifacts != null) {
      await artifacts.putArtifact(digest, bytes);
      return;
    }
    final normalized = requireSha256Digest(digest);
    final actual = sha256Digest(bytes);
    if (actual != normalized) throw StorageDigestMismatch(normalized, actual);
    await _pool.execute(
      Sql.named(
        'INSERT INTO control_plane_artifacts(digest, artifact_bytes, size_bytes) '
        'VALUES (@digest:text, @bytes:bytea, @size:int8) '
        'ON CONFLICT (digest) DO NOTHING',
      ),
      parameters: <String, Object?>{
        'digest': normalized,
        'bytes': Uint8List.fromList(bytes),
        'size': bytes.length,
      },
    );
    final existing = await readArtifact(normalized);
    if (existing == null || !_sameBytes(existing, bytes)) {
      throw const StorageConflict('Content-addressed artifact was changed');
    }
  }

  @override
  Future<List<int>?> readArtifact(String digest) async {
    final artifacts = _artifacts;
    if (artifacts != null) return artifacts.readArtifact(digest);
    final normalized = requireSha256Digest(digest);
    final result = await _pool.execute(
      Sql.named(
        'SELECT artifact_bytes FROM control_plane_artifacts '
        'WHERE digest = @digest:text',
      ),
      parameters: <String, Object?>{'digest': normalized},
    );
    if (result.isEmpty) return null;
    final value = result.first.toColumnMap()['artifact_bytes'];
    if (value is Uint8List) return List<int>.from(value);
    if (value is List<int>) return List<int>.from(value);
    throw const StorageConflict('Stored artifact has an invalid byte value');
  }

  @override
  Future<Set<String>> listArtifactKeys() async {
    final artifacts = _artifacts;
    if (artifacts != null) {
      if (artifacts case final ArtifactInventory inventory) {
        return inventory.listArtifactKeys();
      }
      throw const StorageUnavailable(
        'Artifact inventory is unavailable for the configured object store',
      );
    }
    final result = await _pool.execute(
      'SELECT digest FROM control_plane_artifacts ORDER BY digest',
    );
    return Set.unmodifiable(
      result
          .map((row) => row.toColumnMap()['digest']! as String)
          .map(
            (digest) =>
                digest.startsWith('sha256:') ? digest.substring(7) : digest,
          ),
    );
  }

  @override
  Future<void> createIdempotency(
    String scope,
    String key,
    Map<String, Object?> value,
  ) => createJson('idempotency', _idempotencyId(scope, key), value);

  @override
  Future<Map<String, Object?>?> readIdempotency(String scope, String key) =>
      readJson('idempotency', _idempotencyId(scope, key));

  @override
  Future<void> appendAudit(String id, Map<String, Object?> value) async {
    final body = canonicalJson(value);
    final digest = sha256Digest(<int>[...utf8.encode(body)]);
    await _disconnectIfRequested(PostgresDisconnectPoint.auditCommitBefore);
    await _pool.runTx((session) async {
      // Serialize only the short chain-link operation across service
      // processes; resource writes remain independently concurrent.
      await session.execute('SELECT pg_advisory_xact_lock(7812451)');
      final previous = await session.execute(
        'SELECT record_digest FROM control_plane_audit_chain '
        'ORDER BY sequence DESC LIMIT 1',
      );
      final previousDigest = previous.isEmpty
          ? null
          : previous.first.toColumnMap()['record_digest'] as String?;
      final nextSequence = await session.execute(
        'SELECT COALESCE(MAX(sequence), 0) + 1 AS next_sequence '
        'FROM control_plane_audit_chain',
      );
      await session.execute(
        Sql.named(
          'INSERT INTO control_plane_audit_chain '
          '(sequence, audit_id, organization_id, previous_digest, record_digest, body) '
          'VALUES (@sequence:int8, @id:text, @organization:text, @previous:text, '
          '@digest:text, @body:jsonb) '
          'ON CONFLICT (audit_id) DO NOTHING',
        ),
        parameters: <String, Object?>{
          'sequence': nextSequence.first.toColumnMap()['next_sequence'],
          'id': id,
          'organization': value['organizationId'],
          'previous': previousDigest,
          'digest': digest,
          'body': value,
        },
      );
    });
    await _disconnectIfRequested(PostgresDisconnectPoint.auditCommitAfter);
    await createJson('audit', id, value);
  }

  @override
  Future<ObservationWriteResult> createObservation(
    String organizationId,
    String applicationId,
    String environmentId,
    String eventId,
    Map<String, Object?> value,
  ) async {
    final event = value['event'];
    final receivedAt = value['receivedAt'];
    if (event is! Map || receivedAt is! String) {
      throw const StorageConflict('Observation record is malformed');
    }
    final eventMap = event.map<String, Object?>(
      (key, item) => MapEntry('$key', item),
    );
    final body = <String, Object?>{
      'event': eventMap,
      'receivedAt': receivedAt,
      'disposition': value['disposition'],
    };
    final result = await _pool.runTx((session) async {
      final inserted = await session.execute(
        Sql.named(
          'INSERT INTO control_plane_observations '
          '(organization_id, application_id, environment_id, event_id, '
          'event_type, release_id, patch_id, sequence, rollout_id, '
          'rollout_revision, received_at, body) '
          'VALUES (@organization:text, @application:text, @environment:text, '
          '@event:text, @eventType:text, @release:text, @patch:text, '
          '@sequence:int8, @rollout:text, @rolloutRevision:int8, '
          '@received:timestamptz, @body:jsonb) '
          'ON CONFLICT (organization_id, application_id, environment_id, event_id) '
          'DO NOTHING',
        ),
        parameters: <String, Object?>{
          'organization': organizationId,
          'application': applicationId,
          'environment': environmentId,
          'event': eventId,
          'eventType': eventMap['eventType'],
          'release': eventMap['releaseId'],
          'patch': eventMap['patchId'],
          'sequence': eventMap['sequence'],
          'rollout': eventMap['rolloutId'],
          'rolloutRevision': eventMap['rolloutRevision'],
          'received': DateTime.parse(receivedAt).toUtc(),
          'body': body,
        },
      );
      final stored = await session.execute(
        Sql.named(
          'SELECT body::text AS body_json FROM control_plane_observations '
          'WHERE organization_id = @organization:text '
          'AND application_id = @application:text '
          'AND environment_id = @environment:text AND event_id = @event:text',
        ),
        parameters: <String, Object?>{
          'organization': organizationId,
          'application': applicationId,
          'environment': environmentId,
          'event': eventId,
        },
      );
      if (stored.isEmpty) {
        throw const StorageConflict('Observation insert did not persist');
      }
      return ObservationWriteResult(
        created: inserted.affectedRows == 1,
        value: _decodeBody(stored.first.toColumnMap()['body_json']),
      );
    });
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> listObservations({
    String? organizationId,
    String? applicationId,
    String? environmentId,
  }) async {
    final clauses = <String>[];
    final parameters = <String, Object?>{};
    if (organizationId != null) {
      clauses.add('organization_id = @organization:text');
      parameters['organization'] = organizationId;
    }
    if (applicationId != null) {
      clauses.add('application_id = @application:text');
      parameters['application'] = applicationId;
    }
    if (environmentId != null) {
      clauses.add('environment_id = @environment:text');
      parameters['environment'] = environmentId;
    }
    final result = await _pool.execute(
      Sql.named(
        'SELECT body::text AS body_json FROM control_plane_observations '
        '${clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')} '} '
        'ORDER BY received_at, event_id',
      ),
      parameters: parameters,
    );
    return List.unmodifiable(
      result.map((row) => _decodeBody(row.toColumnMap()['body_json'])),
    );
  }

  @override
  Future<int> deleteObservations({
    required String organizationId,
    String? applicationId,
    String? environmentId,
    required DateTime olderThan,
  }) async {
    final conditions = <String>['organization_id = @organization:text'];
    final parameters = <String, Object?>{
      'organization': organizationId,
      'older': olderThan.toUtc(),
    };
    if (applicationId != null) {
      conditions.add('application_id = @application:text');
      parameters['application'] = applicationId;
    }
    if (environmentId != null) {
      conditions.add('environment_id = @environment:text');
      parameters['environment'] = environmentId;
    }
    conditions.add('received_at < @older:timestamptz');
    final result = await _pool.execute(
      Sql.named(
        'DELETE FROM control_plane_observations WHERE ${conditions.join(' AND ')}',
      ),
      parameters: parameters,
    );
    return result.affectedRows;
  }

  @override
  Future<RolloutTransitionCommitResult> commitRolloutTransition({
    required String rolloutId,
    required int expectedRevision,
    required Map<String, Object?> rollout,
    required Map<String, Object?> revision,
    required Map<String, Object?> audit,
    required String idempotencyScope,
    required String idempotencyKey,
    required String requestDigest,
    required Map<String, Object?> idempotencyResult,
  }) async {
    final result = await _pool.runTx((session) async {
      // Lock ordering is fixed: the audit chain lock is acquired before the
      // rollout row lock so concurrent transitions cannot deadlock.
      await session.execute('SELECT pg_advisory_xact_lock(7812451)');
      final idempotencyId = _idempotencyId(idempotencyScope, idempotencyKey);
      final existingRows = await session.execute(
        Sql.named(
          'SELECT body::text AS body_json FROM control_plane_records '
          'WHERE collection = @collection:text AND record_id = @id:text',
        ),
        parameters: <String, Object?>{
          'collection': 'idempotency',
          'id': idempotencyId,
        },
      );
      if (existingRows.isNotEmpty) {
        final existing = _decodeBody(
          existingRows.first.toColumnMap()['body_json'],
        );
        if (existing['requestDigest'] != requestDigest) {
          throw const StorageIdempotencyConflict(
            'Idempotency key was already used for a different request',
          );
        }
        return const RolloutTransitionCommitResult(applied: false);
      }
      final currentRows = await session.execute(
        Sql.named(
          'SELECT body::text AS body_json FROM control_plane_records '
          'WHERE collection = @collection:text AND record_id = @id:text '
          'FOR UPDATE',
        ),
        parameters: <String, Object?>{
          'collection': 'rollouts',
          'id': rolloutId,
        },
      );
      if (currentRows.isEmpty) {
        throw const StorageConflict('Rollout does not exist');
      }
      final current = _decodeBody(currentRows.first.toColumnMap()['body_json']);
      final currentRevision = current['currentRevision'];
      if (currentRevision is! int || currentRevision != expectedRevision) {
        throw StoragePreconditionFailed(
          'Rollout revision is stale',
          currentRevision: currentRevision is int ? currentRevision : -1,
        );
      }
      await session.execute(
        Sql.named(
          'INSERT INTO control_plane_records '
          '(collection, record_id, organization_id, body) '
          'VALUES (@collection:text, @id:text, @organization:text, @body:jsonb)',
        ),
        parameters: <String, Object?>{
          'collection': 'rollout_revisions',
          'id': revision['id'],
          'organization': revision['organizationId'],
          'body': revision,
        },
      );
      final updated = await session.execute(
        Sql.named(
          'UPDATE control_plane_records SET organization_id = @organization:text, '
          'body = @body:jsonb, updated_at = now() '
          'WHERE collection = @collection:text AND record_id = @id:text',
        ),
        parameters: <String, Object?>{
          'collection': 'rollouts',
          'id': rolloutId,
          'organization': rollout['organizationId'],
          'body': rollout,
        },
      );
      if (updated.affectedRows != 1) {
        throw const StorageConflict('Rollout update did not persist');
      }
      await session.execute(
        Sql.named(
          'INSERT INTO control_plane_records '
          '(collection, record_id, organization_id, body) '
          'VALUES (@collection:text, @id:text, @organization:text, @body:jsonb)',
        ),
        parameters: <String, Object?>{
          'collection': 'idempotency',
          'id': idempotencyId,
          'organization': audit['organizationId'],
          'body': <String, Object?>{
            'requestDigest': requestDigest,
            'result': idempotencyResult,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        },
      );
      final previous = await session.execute(
        'SELECT record_digest FROM control_plane_audit_chain '
        'ORDER BY sequence DESC LIMIT 1',
      );
      final previousDigest = previous.isEmpty
          ? null
          : previous.first.toColumnMap()['record_digest'] as String?;
      final nextSequence = await session.execute(
        'SELECT COALESCE(MAX(sequence), 0) + 1 AS next_sequence '
        'FROM control_plane_audit_chain',
      );
      final auditDigest = sha256Digest(utf8.encode(canonicalJson(audit)));
      await session.execute(
        Sql.named(
          'INSERT INTO control_plane_audit_chain '
          '(sequence, audit_id, organization_id, previous_digest, record_digest, body) '
          'VALUES (@sequence:int8, @id:text, @organization:text, @previous:text, '
          '@digest:text, @body:jsonb)',
        ),
        parameters: <String, Object?>{
          'sequence': nextSequence.first.toColumnMap()['next_sequence'],
          'id': audit['id'],
          'organization': audit['organizationId'],
          'previous': previousDigest,
          'digest': auditDigest,
          'body': audit,
        },
      );
      await session.execute(
        Sql.named(
          'INSERT INTO control_plane_records '
          '(collection, record_id, organization_id, body) '
          'VALUES (@collection:text, @id:text, @organization:text, @body:jsonb)',
        ),
        parameters: <String, Object?>{
          'collection': 'audit',
          'id': audit['id'],
          'organization': audit['organizationId'],
          'body': audit,
        },
      );
      rolloutTransitionFailure?.call(
        PostgresRolloutTransitionFailurePoint.beforeCommit,
      );
      return const RolloutTransitionCommitResult(applied: true);
    });
    rolloutTransitionFailure?.call(
      PostgresRolloutTransitionFailurePoint.afterCommit,
    );
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> readAuditChain() async {
    await _disconnectIfRequested(PostgresDisconnectPoint.auditReadBefore);
    final result = await _pool.execute(
      'SELECT sequence, audit_id, organization_id, previous_digest, '
      'record_digest, body::text AS body_json '
      'FROM control_plane_audit_chain ORDER BY sequence',
    );
    return List.unmodifiable(
      result.map((row) {
        final columns = row.toColumnMap();
        return <String, Object?>{
          'sequence': columns['sequence'] is int
              ? columns['sequence']
              : int.parse('${columns['sequence']}'),
          'auditId': columns['audit_id'],
          'organizationId': columns['organization_id'],
          'previousDigest': columns['previous_digest'],
          'recordDigest': columns['record_digest'],
          'body': _decodeBody(columns['body_json']),
        };
      }),
    );
  }

  String _idempotencyId(String scope, String key) =>
      '${sha256Hex(utf8.encode(scope))}-${sha256Hex(utf8.encode(key))}';

  Map<String, Object?> _decodeBody(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! Map) throw const StorageConflict('Stored JSON is invalid');
    return decoded.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
