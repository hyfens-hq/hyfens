import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'encoding.dart';
import 'errors.dart';
import 'observation.dart';

abstract interface class ArtifactStore {
  Future<void> putArtifact(String digest, List<int> bytes);

  Future<List<int>?> readArtifact(String digest);
}

/// Optional dependency probe used by hosted readiness checks.
abstract interface class ArtifactStoreReadiness {
  Future<void> checkReadiness();
}

/// Optional inventory seam used by the bounded reconciliation procedure.
/// Implementations return raw content-addressed object keys without mutating
/// metadata or regenerating signed artifacts.
abstract interface class ArtifactInventory {
  Future<Set<String>> listArtifactKeys();
}

final class ObservationWriteResult {
  const ObservationWriteResult({required this.created, required this.value});

  final bool created;
  final Map<String, Object?> value;
}

final class RolloutTransitionCommitResult {
  const RolloutTransitionCommitResult({required this.applied});

  final bool applied;
}

/// Storage operations whose correctness depends on a durable unique key.
/// Implementations must compare an existing event's canonical body before
/// acknowledging a retry; they must never silently overwrite an observation.
abstract interface class ObservationStore {
  Future<ObservationWriteResult> createObservation(
    String organizationId,
    String applicationId,
    String environmentId,
    String eventId,
    Map<String, Object?> value,
  );

  Future<List<Map<String, Object?>>> listObservations({
    String? organizationId,
    String? applicationId,
    String? environmentId,
  });

  Future<int> deleteObservations({
    required String organizationId,
    String? applicationId,
    String? environmentId,
    required DateTime olderThan,
  });
}

/// The one rollout write that must be serialized across control-plane
/// processes. PostgreSQL implements this as a transaction with a row lock;
/// the file store provides the equivalent single-node queue.
abstract interface class RolloutTransitionStore {
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
  });
}

abstract interface class ControlPlaneStore
    implements ArtifactStore, ObservationStore, RolloutTransitionStore {
  Future<void> initialize();

  Future<void> close();

  Future<void> checkReadiness();

  Future<Map<String, Object?>?> readJson(String collection, String id);

  Future<List<Map<String, Object?>>> listJson(String collection);

  Future<void> createJson(
    String collection,
    String id,
    Map<String, Object?> value,
  );

  Future<void> replaceJson(
    String collection,
    String id,
    Map<String, Object?> value,
  );

  /// Touches an active human session only when its secret hash still matches.
  ///
  /// The operation is authoritative at the persistence seam: a concurrent
  /// revocation makes it return null instead of overwriting the revoked
  /// record. The returned map is the record written by the operation.
  Future<Map<String, Object?>?> touchSessionIfActive({
    required String id,
    required String expectedSecretHash,
    required DateTime now,
  });

  /// Revokes a human session when it is still active.
  ///
  /// A false result includes a missing, mismatched, or already revoked record,
  /// making repeated logout calls idempotent.
  Future<bool> revokeSessionIfActive({
    required String id,
    required String expectedSecretHash,
    required DateTime revokedAt,
  });

  Future<void> createIdempotency(
    String scope,
    String key,
    Map<String, Object?> value,
  );

  Future<Map<String, Object?>?> readIdempotency(String scope, String key);

  Future<void> appendAudit(String id, Map<String, Object?> value);

  Future<List<Map<String, Object?>>> readAuditChain();
}

/// Single-node filesystem storage. Metadata and bytes use separate namespaces;
/// artifact paths are content addressed and never selected from a caller's
/// arbitrary filesystem path.
final class FileControlPlaneStore
    implements ControlPlaneStore, ArtifactInventory {
  FileControlPlaneStore(this.root);

  final Directory root;
  Future<void> _sessionOperationTail = Future<void>.value();

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_.:-]{1,256}$');

  Future<void> initialize() async {
    await root.create(recursive: true);
    for (final name in const <String>[
      'organizations',
      'applications',
      'environments',
      'releases',
      'patches',
      'artifacts',
      'rollouts',
      'rollout_revisions',
      'credentials',
      'users',
      'sessions',
      'auth_bootstrap_consumptions',
      'audit',
      'audit_chain',
      'idempotency',
      'observations',
      'waitlist',
      'newsletter',
    ]) {
      await Directory(p.join(root.path, name)).create(recursive: true);
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> checkReadiness() async {
    await listJson('__readiness_probe__');
  }

  @override
  Future<Map<String, Object?>?> readJson(String collection, String id) async {
    final file = _jsonFile(collection, id);
    if (!await file.exists()) return null;
    return decodeObject(await file.readAsString());
  }

  @override
  Future<List<Map<String, Object?>>> listJson(String collection) async {
    final directory = Directory(p.join(root.path, _safeCollection(collection)));
    if (!await directory.exists()) return const <Map<String, Object?>>[];
    final entries = await directory.list(followLinks: false).toList();
    final files = entries.whereType<File>().toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    final result = <Map<String, Object?>>[];
    for (final file in files) {
      if (!file.path.endsWith('.json')) continue;
      result.add(decodeObject(await file.readAsString()));
    }
    return List.unmodifiable(result);
  }

  @override
  Future<void> createJson(
    String collection,
    String id,
    Map<String, Object?> value,
  ) async {
    final file = _jsonFile(collection, id);
    if (await file.exists()) {
      final existing = await file.readAsString();
      final incoming = canonicalJson(value);
      if (existing == '$incoming\n' || existing == incoming) return;
      throw const StorageConflict('Immutable record already exists');
    }
    await _writeAtomic(file, utf8.encode('${canonicalJson(value)}\n'));
  }

  @override
  Future<void> replaceJson(
    String collection,
    String id,
    Map<String, Object?> value,
  ) async {
    final file = _jsonFile(collection, id);
    if (!await file.exists())
      throw const StorageConflict('Record does not exist');
    await _writeAtomic(file, utf8.encode('${canonicalJson(value)}\n'));
  }

  @override
  Future<Map<String, Object?>?> touchSessionIfActive({
    required String id,
    required String expectedSecretHash,
    required DateTime now,
  }) => _sessionOperation(() async {
    final current = await readJson('sessions', id);
    if (current == null ||
        current['secretHash'] != expectedSecretHash ||
        current['revokedAt'] != null) {
      return null;
    }
    final expiresAt = current['expiresAt'];
    final expires = expiresAt is String
        ? DateTime.tryParse(expiresAt)?.toUtc()
        : null;
    final normalizedNow = now.toUtc();
    if (expires == null || !expires.isAfter(normalizedNow)) return null;
    final updated = <String, Object?>{
      ...current,
      'lastUsedAt': normalizedNow.toIso8601String(),
    };
    await replaceJson('sessions', id, updated);
    return updated;
  });

  @override
  Future<bool> revokeSessionIfActive({
    required String id,
    required String expectedSecretHash,
    required DateTime revokedAt,
  }) => _sessionOperation(() async {
    final current = await readJson('sessions', id);
    if (current == null ||
        current['secretHash'] != expectedSecretHash ||
        current['revokedAt'] != null) {
      return false;
    }
    final updated = <String, Object?>{
      ...current,
      'revokedAt': revokedAt.toUtc().toIso8601String(),
    };
    await replaceJson('sessions', id, updated);
    return true;
  });

  @override
  Future<void> putArtifact(String digest, List<int> bytes) async {
    final normalized = requireSha256Digest(digest);
    final hex = normalized.substring(7);
    final actual = sha256Digest(bytes);
    if (actual != normalized) throw StorageDigestMismatch(normalized, actual);
    final file = File(p.join(root.path, 'artifacts', hex, 'bytes'));
    if (await file.exists()) {
      final existing = await file.readAsBytes();
      if (_sameBytes(existing, bytes)) return;
      throw const StorageConflict('Content-addressed artifact was changed');
    }
    await _writeAtomic(file, bytes);
  }

  @override
  Future<Set<String>> listArtifactKeys() async {
    final directory = Directory(p.join(root.path, 'artifacts'));
    if (!await directory.exists()) return const <String>{};
    final entries = await directory.list(followLinks: false).toList();
    final keys = <String>{};
    for (final entry in entries.whereType<Directory>()) {
      final name = p.basename(entry.path);
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(name) &&
          await File(p.join(entry.path, 'bytes')).exists()) {
        keys.add(name);
      }
    }
    return Set.unmodifiable(keys);
  }

  @override
  Future<List<int>?> readArtifact(String digest) async {
    final normalized = requireSha256Digest(digest);
    final file = File(
      p.join(root.path, 'artifacts', normalized.substring(7), 'bytes'),
    );
    if (!await file.exists()) return null;
    return file.readAsBytes();
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
  Future<void> appendAudit(String id, Map<String, Object?> value) =>
      _appendAudit(id, value);

  @override
  Future<List<Map<String, Object?>>> readAuditChain() =>
      listJson('audit_chain');

  @override
  Future<ObservationWriteResult> createObservation(
    String organizationId,
    String applicationId,
    String environmentId,
    String eventId,
    Map<String, Object?> value,
  ) async {
    final id = observationStorageId(
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
      eventId: eventId,
    );
    final existing = await readJson('observations', id);
    if (existing != null) {
      return ObservationWriteResult(created: false, value: existing);
    }
    await createJson('observations', id, value);
    return ObservationWriteResult(created: true, value: value);
  }

  @override
  Future<List<Map<String, Object?>>> listObservations({
    String? organizationId,
    String? applicationId,
    String? environmentId,
  }) async {
    final values = await listJson('observations');
    return List.unmodifiable(
      values.where((value) {
        final event = value['event'];
        if (event is! Map) return false;
        return (organizationId == null ||
                event['organizationId'] == organizationId) &&
            (applicationId == null ||
                event['applicationId'] == applicationId) &&
            (environmentId == null || event['environmentId'] == environmentId);
      }),
    );
  }

  @override
  Future<int> deleteObservations({
    required String organizationId,
    String? applicationId,
    String? environmentId,
    required DateTime olderThan,
  }) async {
    final directory = Directory(p.join(root.path, 'observations'));
    if (!await directory.exists()) return 0;
    var deleted = 0;
    final entries = await directory.list(followLinks: false).toList();
    for (final entry in entries.whereType<File>()) {
      if (!entry.path.endsWith('.json')) continue;
      final value = decodeObject(await entry.readAsString());
      final event = value['event'];
      final receivedAt = value['receivedAt'];
      if (event is! Map || receivedAt is! String) continue;
      if (event['organizationId'] != organizationId ||
          (applicationId != null && event['applicationId'] != applicationId) ||
          (environmentId != null && event['environmentId'] != environmentId)) {
        continue;
      }
      final received = DateTime.tryParse(receivedAt);
      if (received == null || !received.isBefore(olderThan.toUtc())) continue;
      await entry.delete();
      deleted++;
    }
    return deleted;
  }

  Future<void> _commitRolloutTransitionFile({
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
    final existing = await readIdempotency(idempotencyScope, idempotencyKey);
    if (existing != null) {
      if (existing['requestDigest'] != requestDigest) {
        throw const StorageIdempotencyConflict(
          'Idempotency key was already used for a different request',
        );
      }
      return;
    }
    final current = await readJson('rollouts', rolloutId);
    if (current == null) throw const StorageConflict('Rollout does not exist');
    final currentRevision = current['currentRevision'];
    if (currentRevision is! int || currentRevision != expectedRevision) {
      throw StoragePreconditionFailed(
        'Rollout revision is stale',
        currentRevision: currentRevision is int ? currentRevision : -1,
      );
    }
    await createJson('rollout_revisions', revision['id']! as String, revision);
    await replaceJson('rollouts', rolloutId, rollout);
    await createIdempotency(idempotencyScope, idempotencyKey, <String, Object?>{
      'requestDigest': requestDigest,
      'result': idempotencyResult,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    await appendAudit(audit['id']! as String, audit);
  }

  Future<void> _rolloutTransitionTail = Future<void>.value();

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
  }) {
    final completer = _rolloutTransitionTail.then((_) async {
      final before = await readIdempotency(idempotencyScope, idempotencyKey);
      if (before != null && before['requestDigest'] == requestDigest) {
        return const RolloutTransitionCommitResult(applied: false);
      }
      await _commitRolloutTransitionFile(
        rolloutId: rolloutId,
        expectedRevision: expectedRevision,
        rollout: rollout,
        revision: revision,
        audit: audit,
        idempotencyScope: idempotencyScope,
        idempotencyKey: idempotencyKey,
        requestDigest: requestDigest,
        idempotencyResult: idempotencyResult,
      );
      return const RolloutTransitionCommitResult(applied: true);
    });
    _rolloutTransitionTail = completer.then<void>((_) {}).catchError((_) {});
    return completer;
  }

  Future<void> _appendAudit(String id, Map<String, Object?> value) async {
    final chain = (await listJson('audit_chain')).toList();
    chain.sort(
      (left, right) =>
          (left['sequence']! as int).compareTo(right['sequence']! as int),
    );
    final previous = chain.isEmpty
        ? null
        : chain.last['recordDigest'] as String?;
    final recordDigest = sha256Digest(utf8.encode(canonicalJson(value)));
    await createJson('audit_chain', id, <String, Object?>{
      'sequence': chain.length + 1,
      'auditId': id,
      'organizationId': value['organizationId'],
      'previousDigest': previous,
      'recordDigest': recordDigest,
      'body': value,
    });
    await createJson('audit', id, value);
  }

  Future<T> _sessionOperation<T>(Future<T> Function() action) {
    final result = _sessionOperationTail.then((_) => action());
    _sessionOperationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  File _jsonFile(String collection, String id) =>
      File(p.join(root.path, _safeCollection(collection), '${_safe(id)}.json'));

  String _safeCollection(String value) {
    if (!_safeId.hasMatch(value) || value.contains('..')) {
      throw const FormatException('Invalid storage collection');
    }
    return value;
  }

  String _safe(String value) {
    if (!_safeId.hasMatch(value) || value.contains('..')) {
      throw const FormatException('Invalid storage identifier');
    }
    return value;
  }

  String _idempotencyId(String scope, String key) =>
      '${sha256Hex(utf8.encode(scope))}-${sha256Hex(utf8.encode(key))}';

  Future<void> _writeAtomic(File destination, List<int> bytes) async {
    await destination.parent.create(recursive: true);
    final temporary = File(
      '${destination.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
