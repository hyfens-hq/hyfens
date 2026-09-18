import 'dart:io';
import 'dart:math';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  final connectionString = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  if (connectionString == null || connectionString.isEmpty) {
    test(
      'PostgreSQL adapter requires HYFENS_TEST_POSTGRES_URL',
      () {},
      skip: 'PostgreSQL integration environment is not configured',
    );
    return;
  }

  late PostgresControlPlaneStore store;
  final runId = DateTime.now().microsecondsSinceEpoch.toString();
  setUp(() async {
    store = PostgresControlPlaneStore(connectionString);
    await store.initialize();
  });
  tearDown(() => store.close());

  test('migration is repeatable and records survive a new store', () async {
    await store.initialize();
    final id = 'org_pg_$runId';
    await store.createJson('organizations', id, <String, Object?>{
      'id': id,
      'name': 'Postgres organization',
      'organizationId': id,
    });
    await store.close();
    final reopened = PostgresControlPlaneStore(connectionString);
    await reopened.initialize();
    addTearDown(reopened.close);
    expect(
      await reopened.readJson('organizations', id),
      containsPair('name', 'Postgres organization'),
    );
  });

  test('concurrent startup migration is safe', () async {
    final other = PostgresControlPlaneStore(connectionString);
    addTearDown(other.close);
    await Future.wait(<Future<void>>[store.initialize(), other.initialize()]);
  });

  test('content addressing, idempotency, and audit are durable', () async {
    final random = Random(7);
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final digest = sha256Digest(bytes);
    await store.putArtifact(digest, bytes);
    expect(await store.readArtifact(digest), bytes);
    await store.putArtifact(digest, bytes);
    await store.createIdempotency(
      'release',
      'same-key-$runId',
      <String, Object?>{
        'requestDigest': 'sha256:test',
        'result': <String, Object?>{'releaseId': 'rel_pg'},
      },
    );
    expect(
      await store.readIdempotency('release', 'same-key-$runId'),
      containsPair('requestDigest', 'sha256:test'),
    );
    final auditId = 'audit_pg_$runId';
    await store.appendAudit(auditId, <String, Object?>{
      'id': auditId,
      'organizationId': 'org_pg_$runId',
      'action': 'test',
    });
    expect(
      await store.readJson('audit', auditId),
      containsPair('action', 'test'),
    );
  });

  test('human session touch and revoke are conditional', () async {
    final sessionId = 'ses_pg_$runId';
    final createdAt = DateTime.utc(2026, 8, 30, 10);
    final expiresAt = createdAt.add(const Duration(days: 1));
    await store.createJson('sessions', sessionId, <String, Object?>{
      'id': sessionId,
      'userId': 'usr_pg_$runId',
      'secretHash': 'hash-$runId',
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'lastUsedAt': createdAt.toIso8601String(),
      'revokedAt': null,
    });

    final touched = await store.touchSessionIfActive(
      id: sessionId,
      expectedSecretHash: 'hash-$runId',
      now: createdAt.add(const Duration(minutes: 1)),
    );
    expect(touched?['lastUsedAt'], '2026-08-30T10:01:00.000Z');
    expect(
      await store.touchSessionIfActive(
        id: sessionId,
        expectedSecretHash: 'wrong-hash',
        now: createdAt,
      ),
      isNull,
    );
    expect(
      await store.revokeSessionIfActive(
        id: sessionId,
        expectedSecretHash: 'hash-$runId',
        revokedAt: createdAt.add(const Duration(minutes: 2)),
      ),
      isTrue,
    );
    expect(
      await store.revokeSessionIfActive(
        id: sessionId,
        expectedSecretHash: 'hash-$runId',
        revokedAt: createdAt.add(const Duration(minutes: 3)),
      ),
      isFalse,
    );
    expect(
      await store.touchSessionIfActive(
        id: sessionId,
        expectedSecretHash: 'hash-$runId',
        now: createdAt.add(const Duration(minutes: 4)),
      ),
      isNull,
    );
  });

  test('concurrent session refresh and logout preserve revocation', () async {
    final sessionId = 'ses_pg_race_$runId';
    final createdAt = DateTime.utc(2026, 8, 30, 10);
    await store.createJson('sessions', sessionId, <String, Object?>{
      'id': sessionId,
      'userId': 'usr_pg_$runId',
      'secretHash': 'race-hash-$runId',
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': createdAt.add(const Duration(days: 1)).toIso8601String(),
      'lastUsedAt': createdAt.toIso8601String(),
      'revokedAt': null,
    });
    final refreshStore = PostgresControlPlaneStore(connectionString);
    final logoutStore = PostgresControlPlaneStore(connectionString);
    await Future.wait(<Future<void>>[
      refreshStore.initialize(),
      logoutStore.initialize(),
    ]);
    addTearDown(() async {
      await refreshStore.close();
      await logoutStore.close();
    });

    await Future.wait(<Future<Object?>>[
      refreshStore.touchSessionIfActive(
        id: sessionId,
        expectedSecretHash: 'race-hash-$runId',
        now: createdAt.add(const Duration(minutes: 1)),
      ),
      logoutStore.revokeSessionIfActive(
        id: sessionId,
        expectedSecretHash: 'race-hash-$runId',
        revokedAt: createdAt.add(const Duration(minutes: 2)),
      ),
    ]);

    final persisted = await store.readJson('sessions', sessionId);
    expect(persisted?['revokedAt'], isNotNull);
    expect(
      await store.touchSessionIfActive(
        id: sessionId,
        expectedSecretHash: 'race-hash-$runId',
        now: createdAt.add(const Duration(minutes: 3)),
      ),
      isNull,
    );
  });

  test('immutable records reject a different concurrent value', () async {
    final id = 'org_race_$runId';
    await Future.wait(
      <Future<void>>[
        store.createJson('organizations', id, <String, Object?>{
          'id': id,
          'organizationId': id,
          'name': 'first',
        }),
        store.createJson('organizations', id, <String, Object?>{
          'id': id,
          'organizationId': id,
          'name': 'second',
        }),
      ].map((future) async {
        try {
          await future;
        } on StorageConflict {
          // One writer must lose the immutable-record race.
        }
      }),
    );
    final value = await store.readJson('organizations', id);
    expect(value?['name'], anyOf('first', 'second'));
  });

  test('observation uniqueness and retention are durable', () async {
    final event = ObservationEvent(
      schemaVersion: 1,
      eventId: 'pg-observation-$runId',
      clientTimestamp: DateTime.now().toUtc(),
      organizationId: 'org_pg_$runId',
      applicationId: 'app_pg_$runId',
      environmentId: 'env_pg_$runId',
      platform: 'android',
      releaseId: 'rel_pg_$runId',
      patchId: null,
      sequence: null,
      rolloutId: null,
      rolloutRevision: null,
      installationBucket: 'bucket:1',
      eventType: ObservationEventType.lookup_attempt,
      runtimeVersion: 'runtime-1',
      patchFormatVersion: 1,
      diagnosticCode: null,
    );
    final record = ObservationRecord(
      event: event,
      receivedAt: DateTime.now().toUtc(),
      disposition: ObservationDisposition.accepted,
    );
    final first = await store.createObservation(
      event.organizationId,
      event.applicationId,
      event.environmentId,
      event.eventId,
      record.toJson(),
    );
    final retry = await store.createObservation(
      event.organizationId,
      event.applicationId,
      event.environmentId,
      event.eventId,
      record.toJson(),
    );
    expect(first.created, isTrue);
    expect(retry.created, isFalse);
    expect(
      await store.listObservations(
        organizationId: event.organizationId,
        applicationId: event.applicationId,
        environmentId: event.environmentId,
      ),
      hasLength(1),
    );
    expect(
      await store.deleteObservations(
        organizationId: event.organizationId,
        olderThan: DateTime.now().toUtc().add(const Duration(seconds: 1)),
      ),
      1,
    );
  });

  test('cross-process rollout CAS permits one stale writer', () async {
    final other = PostgresControlPlaneStore(connectionString);
    addTearDown(other.close);
    await other.initialize();
    final rolloutId = 'rollout_pg_$runId';
    await store.createJson('rollouts', rolloutId, <String, Object?>{
      'id': rolloutId,
      'organizationId': 'org_pg_$runId',
      'currentRevision': 1,
      'state': 'DRAFT',
    });
    Map<String, Object?> transition(String suffix) => <String, Object?>{
      'id': 'revision_pg_${runId}_$suffix',
      'rolloutId': rolloutId,
      'organizationId': 'org_pg_$runId',
      'revision': 2,
    };
    Map<String, Object?> updated() => <String, Object?>{
      'id': rolloutId,
      'organizationId': 'org_pg_$runId',
      'currentRevision': 2,
      'state': 'READY',
    };
    Map<String, Object?> audit(String suffix) => <String, Object?>{
      'id': 'audit_pg_${runId}_$suffix',
      'organizationId': 'org_pg_$runId',
      'action': 'rollout.ready',
    };
    final outcomes = await Future.wait(<Future<Object?>>[
      store
          .commitRolloutTransition(
            rolloutId: rolloutId,
            expectedRevision: 1,
            rollout: updated(),
            revision: transition('a'),
            audit: audit('a'),
            idempotencyScope: 'rollout-transition',
            idempotencyKey: 'pg-cas-a-$runId',
            requestDigest: 'sha256:${'a' * 64}',
            idempotencyResult: <String, Object?>{'rolloutId': rolloutId},
          )
          .then<Object?>((value) => value)
          .catchError((Object error) => error),
      other
          .commitRolloutTransition(
            rolloutId: rolloutId,
            expectedRevision: 1,
            rollout: updated(),
            revision: transition('b'),
            audit: audit('b'),
            idempotencyScope: 'rollout-transition',
            idempotencyKey: 'pg-cas-b-$runId',
            requestDigest: 'sha256:${'b' * 64}',
            idempotencyResult: <String, Object?>{'rolloutId': rolloutId},
          )
          .then<Object?>((value) => value)
          .catchError((Object error) => error),
    ]);
    final applied = outcomes.whereType<RolloutTransitionCommitResult>();
    final failures = outcomes.whereType<StoragePreconditionFailed>();
    expect(applied, hasLength(1));
    expect(failures, hasLength(1));
    expect(
      (await store.listJson('rollout_revisions'))
          .where((value) => value['rolloutId'] == rolloutId),
      hasLength(1),
    );
    expect(
      (await store.listJson('audit')).where(
        (value) => value['id'].toString().startsWith('audit_pg_${runId}_'),
      ),
      hasLength(1),
    );
  });
}
