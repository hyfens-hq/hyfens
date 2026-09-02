import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late HealthAggregate aggregate;
  late HealthAggregateRecord aggregateRecord;
  late HealthAggregateRevision revision;
  late HealthEvaluation evaluation;
  late RolloutDecisionRecord decision;
  late AggregationCursor cursor;

  setUp(() {
    aggregate = _aggregate();
    revision = HealthAggregateRevision(
      aggregateRevisionId: 'revision_p3e',
      aggregateId: 'aggregate_p3e',
      parentAggregateRevisionId: null,
      identity: aggregate.identity,
      window: aggregate.window,
      aggregationVersion: aggregate.identity.aggregationVersion,
      inputCount: aggregate.inputCount,
      inputDigest: aggregate.inputDigest,
      recomputationReason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
      recomputability: P3eRecomputability.rawRecomputable,
      createdAt: DateTime.utc(2026, 8, 24, 14),
    );
    aggregateRecord = HealthAggregateRecord(
      aggregateId: 'aggregate_p3e',
      revisionId: revision.aggregateRevisionId,
      aggregate: aggregate,
      recomputability: revision.recomputability,
      createdAt: DateTime.utc(2026, 8, 24, 14),
    );
    evaluation = HealthEvaluation(
      evaluationId: 'evaluation_p3e',
      organizationId: aggregate.identity.organizationId,
      aggregateRevisionId: revision.aggregateRevisionId,
      rolloutId: aggregate.identity.rolloutId,
      rolloutRevision: aggregate.identity.rolloutRevision,
      evaluationVersion: 1,
      policyVersion: aggregate.policyVersion,
      thresholdSetVersion: 1,
      windowPolicyVersion: aggregate.window.windowPolicyVersion,
      privacyPolicyVersion: 1,
      aggregateInputDigest: revision.inputDigest,
      decision: 'CONTINUE',
      reasonClass: 'PATCH_SAFETY',
      reasonCodes: const <String>['TEST_VECTOR'],
      coverageState: aggregate.coverage.state.wireName,
      freshnessState: aggregate.freshnessState.wireName,
      sampleState: aggregate.samples.allPassed ? 'PASSED' : 'INSUFFICIENT',
      createdAt: DateTime.utc(2026, 8, 24, 14, 1),
      auditReference: 'audit_p3e',
    );
    decision = RolloutDecisionRecord(
      decisionId: 'decision_p3e',
      organizationId: aggregate.identity.organizationId,
      rolloutId: aggregate.identity.rolloutId,
      expectedRolloutRevision: aggregate.identity.rolloutRevision,
      evaluationId: evaluation.evaluationId,
      aggregateRevisionId: revision.aggregateRevisionId,
      decision: evaluation.decision,
      reason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
      actorIdentity: 'test-actor',
      idempotencyKey: 'decision-key-p3e',
      createdAt: DateTime.utc(2026, 8, 24, 14, 2),
      previousDecisionId: null,
      resultingTransitionReference: null,
    );
    cursor = AggregationCursor(
      cursorId: 'cursor_p3e',
      organizationId: aggregate.identity.organizationId,
      aggregateId: aggregateRecord.aggregateId,
      identity: aggregate.identity,
      canonicalInputPosition: 'event:restart-p3e',
      inputDigest: aggregate.inputDigest,
      aggregationVersion: aggregate.identity.aggregationVersion,
      createdAt: DateTime.utc(2026, 8, 24, 14, 3),
    );
  });

  test('aggregate codec round-trips and rejects malformed versions/enums', () {
    final decoded = HealthAggregate.fromJson(aggregate.toJson());
    expect(decoded, equals(aggregate));
    expect(
      () => HealthAggregate.fromJson(<String, Object?>{
        ...aggregate.toJson(),
        'privacyState': 'FUTURE_STATE',
      }),
      throwsFormatException,
    );
    final badMetric = <String, Object?>{
      ...aggregate.toJson(),
      'metrics': <String, Object?>{
        for (final entry in aggregate.metrics.entries)
          entry.key.wireName: <String, Object?>{
            ...entry.value.toJson(),
            'status': 'FUTURE_STATUS',
          },
      },
    };
    expect(() => HealthAggregate.fromJson(badMetric), throwsFormatException);
    expect(
      () => HealthAggregateRecord.fromJson({
        ...aggregateRecord.toJson(),
        'entityVersion': 99,
      }),
      throwsFormatException,
    );
    expect(
      () => HealthEvaluation.fromJson({
        ...evaluation.toJson(),
        'evaluationVersion': 99,
      }),
      throwsFormatException,
    );
    expect(
      () =>
          AggregationCursor.fromJson({...cursor.toJson(), 'entityVersion': 99}),
      throwsFormatException,
    );
  });

  test(
    'File adapter persists lineage, evidence, cursor, and restart state',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hyfens-p3e-file-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileP3ePersistenceStore(directory);
      await store.initialize();
      await store.putAggregateRevision(aggregateRecord, revision);
      await store.putEvaluation(evaluation);
      await store.putDecision(decision);
      await store.putCursor(cursor);
      expect(
        (await store.readAggregate(
          aggregate.identity.organizationId,
          aggregateRecord.aggregateId,
        ))?.canonicalSerialization,
        aggregateRecord.canonicalSerialization,
      );
      expect(
        (await store.readAggregateRevision(
          aggregate.identity.organizationId,
          revision.aggregateRevisionId,
        ))?.canonicalSerialization,
        revision.canonicalSerialization,
      );
      expect(
        (await store.readEvaluation(
          aggregate.identity.organizationId,
          evaluation.evaluationId,
        ))?.canonicalSerialization,
        evaluation.canonicalSerialization,
      );
      expect(
        (await store.readDecision(
          aggregate.identity.organizationId,
          decision.decisionId,
        ))?.canonicalSerialization,
        decision.canonicalSerialization,
      );
      final clean = await store.reconcile(aggregate.identity.organizationId);
      expect(clean.clean, isTrue);
      await store.close();

      final reopened = FileP3ePersistenceStore(directory);
      await reopened.initialize();
      addTearDown(reopened.close);
      expect(
        (await reopened.readAggregate(
          aggregate.identity.organizationId,
          aggregateRecord.aggregateId,
        ))?.aggregateDigest,
        aggregateRecord.aggregateDigest,
      );
      expect(
        await reopened.readCursor(
          aggregate.identity.organizationId,
          cursor.cursorId,
        ),
        isNotNull,
      );
      await reopened.deleteCursor(
        aggregate.identity.organizationId,
        cursor.cursorId,
      );
      expect(
        await reopened.readCursor(
          aggregate.identity.organizationId,
          cursor.cursorId,
        ),
        isNull,
      );
      expect(
        await reopened.readAggregate('org_other', aggregateRecord.aggregateId),
        isNull,
      );
      expect(
        await reopened.listAggregates(aggregate.identity.organizationId),
        hasLength(1),
      );
      expect(await reopened.listAggregates('org_other'), isEmpty);

      final backup = await Directory.systemTemp.createTemp(
        'hyfens-p3e-backup-',
      );
      addTearDown(() => backup.delete(recursive: true));
      await _copyDirectory(directory, backup);
      final restored = FileP3ePersistenceStore(backup);
      await restored.initialize();
      addTearDown(restored.close);
      expect(
        (await restored.readAggregate(
          aggregate.identity.organizationId,
          aggregateRecord.aggregateId,
        ))?.aggregateDigest,
        aggregateRecord.aggregateDigest,
      );
      expect(
        (await restored.readEvaluation(
          aggregate.identity.organizationId,
          evaluation.evaluationId,
        ))?.aggregateInputDigest,
        evaluation.aggregateInputDigest,
      );
    },
  );

  test('File adapter is idempotent and rejects immutable mutation', () async {
    final directory = await Directory.systemTemp.createTemp('hyfens-p3e-idem-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileP3ePersistenceStore(directory);
    await store.initialize();
    await store.putAggregateRevision(aggregateRecord, revision);
    await store.putAggregateRevision(aggregateRecord, revision);
    final mutated = HealthAggregateRecord(
      aggregateId: aggregateRecord.aggregateId,
      revisionId: aggregateRecord.revisionId,
      aggregate: aggregate,
      recomputability: P3eRecomputability.rawExpired,
      createdAt: aggregateRecord.createdAt,
    );
    final mutatedRevision = HealthAggregateRevision(
      aggregateRevisionId: revision.aggregateRevisionId,
      aggregateId: revision.aggregateId,
      parentAggregateRevisionId: revision.parentAggregateRevisionId,
      identity: revision.identity,
      window: revision.window,
      aggregationVersion: revision.aggregationVersion,
      inputCount: revision.inputCount,
      inputDigest: revision.inputDigest,
      recomputationReason: revision.recomputationReason,
      recomputability: P3eRecomputability.rawExpired,
      createdAt: revision.createdAt,
    );
    await expectLater(
      store.putAggregateRevision(mutated, mutatedRevision),
      throwsA(isA<StorageConflict>()),
    );

    final files = (await directory.list(recursive: true).toList())
        .whereType<File>();
    File? aggregateFile;
    for (final file in files) {
      final body = await file.readAsString();
      if (body.contains('"aggregateId":"aggregate_p3e"')) {
        aggregateFile = file;
        break;
      }
    }
    expect(aggregateFile, isNotNull);
    final corrupted = (await aggregateFile!.readAsString()).replaceFirst(
      RegExp(r'"aggregateDigest":"sha256:[0-9a-f]{64}"'),
      '"aggregateDigest":"sha256:${'0' * 64}"',
    );
    await aggregateFile.writeAsString(corrupted, flush: true);
    await expectLater(
      store.readAggregate(
        aggregate.identity.organizationId,
        aggregateRecord.aggregateId,
      ),
      throwsA(isA<StorageDigestMismatch>()),
    );
  });

  test('persistence resource bounds reject oversized records', () async {
    final directory = await Directory.systemTemp.createTemp(
      'hyfens-p3e-limit-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileP3ePersistenceStore(
      directory,
      limits: const P3ePersistenceLimits(
        maximumRecordBytes: 128,
        maximumLineageDepth: 2,
        maximumReconciliationBatch: 2,
      ),
    );
    await store.initialize();
    await expectLater(
      store.putAggregateRevision(aggregateRecord, revision),
      throwsFormatException,
    );
  });

  test(
    'reference writes fail closed and reconciliation reports missing lineage',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hyfens-p3e-ref-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileP3ePersistenceStore(directory);
      await store.initialize();
      await expectLater(
        store.putEvaluation(evaluation),
        throwsA(isA<StorageConflict>()),
      );
      await store.putAggregateRevision(aggregateRecord, revision);
      await store.putEvaluation(evaluation);
      final mismatchedDecision = RolloutDecisionRecord(
        decisionId: 'decision_bad',
        organizationId: decision.organizationId,
        rolloutId: decision.rolloutId,
        expectedRolloutRevision: decision.expectedRolloutRevision,
        evaluationId: 'evaluation_missing',
        aggregateRevisionId: decision.aggregateRevisionId,
        decision: decision.decision,
        reason: decision.reason,
        actorIdentity: decision.actorIdentity,
        idempotencyKey: 'decision-bad-key',
        createdAt: decision.createdAt,
      );
      await expectLater(
        store.putDecision(mismatchedDecision),
        throwsA(isA<StorageConflict>()),
      );
      final orphanRevision = HealthAggregateRevision(
        aggregateRevisionId: 'revision_orphan',
        aggregateId: 'aggregate_orphan',
        parentAggregateRevisionId: 'revision_missing',
        identity: aggregate.identity,
        window: aggregate.window,
        aggregationVersion: aggregate.identity.aggregationVersion,
        inputCount: aggregate.inputCount,
        inputDigest: aggregate.inputDigest,
        recomputationReason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
        recomputability: P3eRecomputability.rawRecomputable,
        createdAt: revision.createdAt,
      );
      final orphanAggregate = HealthAggregateRecord(
        aggregateId: orphanRevision.aggregateId,
        revisionId: orphanRevision.aggregateRevisionId,
        aggregate: aggregate,
        recomputability: orphanRevision.recomputability,
        createdAt: revision.createdAt,
      );
      await store.putAggregateRevision(orphanAggregate, orphanRevision);
      final report = await store.reconcile(aggregate.identity.organizationId);
      expect(report.clean, isFalse);
      expect(
        report.issues.map((issue) => issue.code),
        contains('MISSING_PARENT'),
      );
    },
  );

  final postgresUrl = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  if (postgresUrl == null || postgresUrl.isEmpty) {
    test(
      'PostgreSQL P3E-2 adapter requires HYFENS_TEST_POSTGRES_URL',
      () {},
      skip: 'PostgreSQL integration environment is not configured',
    );
    return;
  }

  test(
    'PostgreSQL adapter persists through restart and preserves tenant scope',
    () async {
      final first = PostgresP3ePersistenceStore(postgresUrl);
      await first.initialize();
      addTearDown(first.close);
      await first.putAggregateRevision(aggregateRecord, revision);
      await first.putEvaluation(evaluation);
      await first.putDecision(decision);
      await first.close();
      final reopened = PostgresP3ePersistenceStore(postgresUrl);
      await reopened.initialize();
      addTearDown(reopened.close);
      expect(
        (await reopened.readAggregate(
          aggregate.identity.organizationId,
          aggregateRecord.aggregateId,
        ))?.canonicalSerialization,
        aggregateRecord.canonicalSerialization,
      );
      expect(
        await reopened.readAggregate('org_other', aggregateRecord.aggregateId),
        isNull,
      );
      expect(
        (await reopened.reconcile(aggregate.identity.organizationId)).clean,
        isTrue,
      );
    },
  );

  test(
    'two PostgreSQL instances acknowledge equal writes and reject mutation',
    () async {
      final first = PostgresP3ePersistenceStore(postgresUrl);
      final second = PostgresP3ePersistenceStore(postgresUrl);
      await Future.wait(<Future<void>>[
        first.initialize(),
        second.initialize(),
      ]);
      addTearDown(first.close);
      addTearDown(second.close);
      final equal = await Future.wait(<Future<Object?>>[
        first
            .putAggregateRevision(aggregateRecord, revision)
            .then<Object?>((_) => null)
            .catchError((Object error) => error),
        second
            .putAggregateRevision(aggregateRecord, revision)
            .then<Object?>((_) => null)
            .catchError((Object error) => error),
      ]);
      expect(equal.whereType<Object>(), isEmpty);
      final mutated = HealthAggregateRecord(
        aggregateId: aggregateRecord.aggregateId,
        revisionId: aggregateRecord.revisionId,
        aggregate: aggregate,
        recomputability: P3eRecomputability.rawDeletedByPolicy,
        createdAt: aggregateRecord.createdAt,
      );
      final mutatedRevision = HealthAggregateRevision(
        aggregateRevisionId: revision.aggregateRevisionId,
        aggregateId: revision.aggregateId,
        parentAggregateRevisionId: revision.parentAggregateRevisionId,
        identity: revision.identity,
        window: revision.window,
        aggregationVersion: revision.aggregationVersion,
        inputCount: revision.inputCount,
        inputDigest: revision.inputDigest,
        recomputationReason: revision.recomputationReason,
        recomputability: P3eRecomputability.rawDeletedByPolicy,
        createdAt: revision.createdAt,
      );
      await expectLater(
        first.putAggregateRevision(mutated, mutatedRevision),
        throwsA(isA<StorageConflict>()),
      );
    },
  );
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final target = p.join(destination.path, p.basename(entity.path));
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(target));
    } else if (entity is File) {
      await entity.copy(target);
    }
  }
}

HealthAggregate _aggregate({String organizationId = 'org_p3e'}) {
  final start = DateTime.utc(2026, 8, 24, 12);
  final window = ObservationWindow(
    windowId: 'window_p3e',
    serverStart: start,
    serverEnd: start.add(const Duration(hours: 1)),
    lateCutoff: start.add(const Duration(hours: 2)),
    minimumDuration: const Duration(hours: 1),
    maximumDuration: const Duration(hours: 3),
    windowPolicyVersion: 1,
  );
  final identity = AggregateIdentity(
    organizationId: organizationId,
    applicationId: 'app_p3e',
    environmentId: 'env_p3e',
    platformId: 'android',
    releaseId: 'release_p3e',
    patchId: 'patch_p3e',
    sequence: 1,
    rolloutId: 'rollout_p3e',
    rolloutRevision: 1,
    windowId: window.windowId,
    windowStart: window.serverStart,
    windowEnd: window.serverEnd,
    lateCutoff: window.lateCutoff,
    observationSchemaVersion: 1,
    aggregationVersion: 1,
  );
  final policy = AggregationPolicy(
    version: 1,
    minimumSamples: const AggregationMinimumSamples(
      minimumEligibleObserved: 1,
      minimumOffers: 1,
      minimumActivated: 1,
      minimumHealthyConfirmations: 1,
      minimumCoverageBasisPoints: 10000,
    ),
    smallCohortMinimum: 1,
    materialQuarantineMinimum: 1,
    limits: const AggregationLimits(
      maximumRecords: 100,
      maximumCanonicalBytes: 1024 * 1024,
      maximumQuarantineReasonCardinality: 7,
      maximumDiagnosticCodeCardinality: 32,
    ),
    denominatorPolicy: const MetricDenominatorPolicy(
      runtimeFaults: MetricDenominatorSource.activationSucceeded,
      rollbackFallback: MetricDenominatorSource.activationSucceeded,
      restartSurvival: MetricDenominatorSource.activationSucceeded,
    ),
    expectedEligibleInstallations: 1,
    freshnessReference: start.add(const Duration(hours: 1, minutes: 30)),
    freshnessMaximumAge: const Duration(hours: 2),
  );
  ObservationRecord record(String id, ObservationEventType type) {
    final receipt = start.add(const Duration(minutes: 5));
    return ObservationRecord(
      event: ObservationEvent(
        schemaVersion: 1,
        eventId: id,
        clientTimestamp: receipt,
        organizationId: identity.organizationId,
        applicationId: identity.applicationId,
        environmentId: identity.environmentId,
        platform: identity.platformId,
        releaseId: identity.releaseId,
        patchId: identity.patchId,
        sequence: identity.sequence,
        rolloutId: identity.rolloutId,
        rolloutRevision: identity.rolloutRevision,
        installationBucket: 'bucket:1',
        eventType: type,
        runtimeVersion: 'runtime-p3e',
        patchFormatVersion: 1,
        diagnosticCode: null,
      ),
      receivedAt: receipt,
      disposition: ObservationDisposition.accepted,
    );
  }

  final aggregate = const DeterministicAggregator().aggregate(
    identity: identity,
    window: window,
    policy: policy,
    records: <ObservationRecord>[
      record('lookup-p3e', ObservationEventType.lookup_attempt),
      record('offer-p3e', ObservationEventType.candidate_offered),
      record('download-p3e', ObservationEventType.download_succeeded),
      record('admit-p3e', ObservationEventType.admission_verified),
      record('activation-p3e', ObservationEventType.activation_succeeded),
      record('healthy-p3e', ObservationEventType.healthy_confirmed),
      record('restart-p3e', ObservationEventType.restart_survived),
    ],
  );
  return aggregate;
}
