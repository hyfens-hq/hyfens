import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  final baseNow = DateTime.utc(2026, 8, 24, 10);

  test('explicit policies are bounded and retry jitter is deterministic', () {
    const retry = P3e5RetryPolicy(
      version: 1,
      initialDelay: Duration(seconds: 2),
      maximumDelay: Duration(seconds: 30),
      maximumAttempts: 3,
      jitterMode: P3e5JitterMode.boundedDeterministic,
      jitterBound: Duration(seconds: 1),
    );
    retry.validate();
    expect(retry.delayFor('work_1', 2), retry.delayFor('work_1', 2));
    expect(
      retry.delayFor('work_1', 2),
      lessThanOrEqualTo(const Duration(seconds: 5)),
    );
    expect(
      () => const P3e5ClaimResourcePolicy(
        version: 1,
        claimBatchSize: 0,
        pendingConsiderationLimit: 1,
        maximumActiveLeasesPerTenant: 1,
        recoveryScanBatch: 1,
      ).validate(const P3e5ScheduleLimits()),
      throwsFormatException,
    );
    expect(P3e5PreparedLease('a' * 40).tokenDigest, startsWith('sha256:'));
    expect(() => P3e5PreparedLease('short'), throwsFormatException);
  });

  test(
    'File claim fences tokens, retries, reclaims, cancels, and restarts',
    () async {
      var now = baseNow;
      final root = await Directory.systemTemp.createTemp('hyfens-p3e5-claim-');
      addTearDown(() => root.delete(recursive: true));
      var store = FileP3e5ScheduleStore(root, clock: () => now);
      await store.initialize();
      await _seed(store, now);
      final first = await store.claimDue(_request('owner_1', 'a'));
      expect(first, hasLength(1));
      expect(first.single.work.status, ScheduledEvaluationWorkStatus.leased);
      expect(first.single.work.workVersion, 1);
      expect(first.single.work.attemptCount, 1);
      expect(
        first.single.work.leaseTokenDigest,
        isNot(first.single.rawLeaseToken),
      );
      expect(
        (await store.listAttempts(
          'org_1',
          first.single.work.workId,
        )).single.outcome,
        'LEASED',
      );
      expect(await store.claimDue(_request('owner_2', 'b')), isEmpty);

      final lease = _lease(first.single, owner: 'owner_1');
      await expectLater(
        store.failClaim(
          lease: _lease(first.single, owner: 'wrong_owner'),
          failure: P3e5RetryFailure(
            classification: P3e5RetryClass.transient,
            safeCode: 'TEMPORARY',
          ),
          retryPolicy: _retry,
        ),
        throwsA(isA<StorageConflict>()),
      );
      final waiting = await store.failClaim(
        lease: lease,
        failure: P3e5RetryFailure(
          classification: P3e5RetryClass.transient,
          safeCode: 'TEMPORARY',
        ),
        retryPolicy: _retry,
      );
      expect(waiting.work.status, ScheduledEvaluationWorkStatus.retryWait);
      expect(await store.claimDue(_request('owner_2', 'c')), isEmpty);
      now = now.add(const Duration(seconds: 5));
      final second = await store.claimDue(_request('owner_2', 'd'));
      expect(second, hasLength(1));
      expect(second.single.work.attemptCount, 2);
      expect(
        store.failClaim(
          lease: lease,
          failure: P3e5RetryFailure(
            classification: P3e5RetryClass.transient,
            safeCode: 'REPLAY',
          ),
          retryPolicy: _retry,
        ),
        throwsA(isA<StorageConflict>()),
      );

      now = now.add(const Duration(seconds: 6));
      final reclaimed = await store.claimDue(_request('owner_3', 'e'));
      expect(reclaimed.single.reclaimed, isTrue);
      expect(reclaimed.single.work.attemptCount, 3);
      expect(
        reclaimed.single.rawLeaseToken,
        isNot(second.single.rawLeaseToken),
      );
      expect(
        await store.listAttempts('org_1', reclaimed.single.work.workId),
        hasLength(3),
      );
      await store.close();

      store = FileP3e5ScheduleStore(root, clock: () => now);
      await store.initialize();
      addTearDown(store.close);
      final restored = await store.readWork(
        'org_1',
        reclaimed.single.work.workId,
      );
      expect(restored?.workVersion, reclaimed.single.work.workVersion);
      expect(
        restored?.leaseTokenDigest,
        reclaimed.single.work.leaseTokenDigest,
      );

      final cancelKey = _key(window: 'cancel');
      final cancelWork = ScheduledEvaluationWork.pending(
        logicalKey: cancelKey,
        serverNow: now,
      );
      await store.putWork(cancelWork);
      final cancelled = await store.cancelWork(
        scope: _scope,
        workId: cancelWork.workId,
        expectedWorkVersion: 0,
      );
      expect(cancelled.work.status, ScheduledEvaluationWorkStatus.cancelled);
      expect(
        store.cancelWork(
          scope: _scope,
          workId: reclaimed.single.work.workId,
          expectedWorkVersion: reclaimed.single.work.workVersion,
        ),
        throwsFormatException,
      );
    },
  );

  test('claim service is least-privilege and redacts the raw token', () async {
    final root = await Directory.systemTemp.createTemp('hyfens-p3e5-service-');
    addTearDown(() => root.delete(recursive: true));
    final control = FileControlPlaneStore(Directory('${root.path}/control'));
    final schedules = FileP3e5ScheduleStore(
      Directory('${root.path}/schedules'),
      clock: () => baseNow,
    );
    await control.initialize();
    await schedules.initialize();
    addTearDown(schedules.close);
    final target = RolloutTarget(
      organizationId: 'org_1',
      applicationId: 'app_1',
      environmentId: 'env_1',
      platformId: 'platform_1',
      releaseId: 'release_1',
      runtimeReleaseId: 'runtime-release-1',
      patchId: 'patch_1',
      runtimePatchId: 'runtime-patch-1',
      artifactId: 'artifact_1',
      sha256: _digest('artifact'),
      sequence: 1,
    );
    final rollout = RolloutRecord(
      id: 'rollout_1',
      organizationId: 'org_1',
      currentRevision: 1,
      state: RolloutState.canary,
      createdAt: baseNow,
    );
    final rolloutRevision = RolloutRevision(
      id: 'rollout_revision_1',
      rolloutId: rollout.id,
      organizationId: rollout.organizationId,
      revision: 1,
      previousRevision: null,
      state: rollout.state,
      target: target,
      policy: RolloutPolicy(
        cohortKind: RolloutCohortKind.percentage,
        percentageBasisPoints: 100,
        salt: 'TEST_ONLY',
      ),
      actorId: 'actor_1',
      reason: 'TEST VECTOR ONLY',
      pausedFromState: null,
      createdAt: baseNow,
    );
    await control.createJson('rollouts', rollout.id, rollout.toJson());
    await control.createJson(
      'rollout_revisions',
      rolloutRevision.id,
      rolloutRevision.toJson(),
    );
    final credential = CredentialService().issue(
      id: 'scheduler_1',
      organizationId: 'org_1',
      kind: CredentialKind.scheduler,
      scopes: const {'health:work:claim'},
      applicationId: 'app_1',
      environmentId: 'env_1',
      expiresAt: baseNow.add(const Duration(hours: 1)),
    );
    await control.createJson(
      'credentials',
      credential.record.tokenHash,
      credential.record.toJson(),
    );
    await _seed(
      schedules,
      baseNow,
      targetDigest: sha256Digest(canonicalJson(target.toJson()).codeUnits),
    );
    final service = P3e5ClaimService(
      controlStore: control,
      scheduleStore: schedules,
      clock: () => baseNow,
    );
    final claims = await service.claimDue(
      token: credential.token,
      scope: _scope,
      leaseOwner: 'executor_1',
      leasePolicy: const P3e5LeasePolicy(
        version: 1,
        duration: Duration(seconds: 5),
      ),
      retryPolicy: _retry,
      resourcePolicy: const P3e5ClaimResourcePolicy(
        version: 1,
        claimBatchSize: 1,
        pendingConsiderationLimit: 4,
        maximumActiveLeasesPerTenant: 1,
        recoveryScanBatch: 4,
      ),
    );
    expect(claims, hasLength(1));
    expect(credential.record.scopes, isNot(contains('health:evaluate')));
    expect(credential.record.scopes, isNot(contains('rollout:halt')));
    final auditText = (await control.readAuditChain()).toString();
    expect(auditText, contains('health.work_claimed'));
    expect(auditText, isNot(contains(claims.single.rawLeaseToken)));
    expect(
      service.claimDue(
        token: credential.token,
        scope: const P3e5ClaimScope(
          organizationId: 'org_1',
          applicationId: 'app_other',
          environmentId: 'env_1',
        ),
        leaseOwner: 'executor_1',
        leasePolicy: const P3e5LeasePolicy(
          version: 1,
          duration: Duration(seconds: 5),
        ),
        retryPolicy: _retry,
        resourcePolicy: const P3e5ClaimResourcePolicy(
          version: 1,
          claimBatchSize: 1,
          pendingConsiderationLimit: 1,
          maximumActiveLeasesPerTenant: 1,
          recoveryScanBatch: 1,
        ),
      ),
      throwsA(isA<ControlPlaneException>()),
    );
  });

  test(
    'File claim journal recovers a crash after attempt persistence',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-p3e5-journal-',
      );
      addTearDown(() => root.delete(recursive: true));
      var injected = false;
      final crashing = FileP3e5ScheduleStore(
        root,
        clock: () => baseNow,
        claimFailure: (point) {
          if (!injected &&
              point == P3e5FileClaimFailurePoint.afterAttemptWrite) {
            injected = true;
            throw StateError('TEST ONLY simulated crash');
          }
        },
      );
      await crashing.initialize();
      await _seed(crashing, baseNow);
      await expectLater(
        crashing.claimDue(_request('owner_1', 'j')),
        throwsA(isA<StateError>()),
      );
      await crashing.close();
      final recovered = FileP3e5ScheduleStore(root, clock: () => baseNow);
      await recovered.initialize();
      addTearDown(recovered.close);
      final work = (await recovered.listWork('org_1')).single;
      expect(work.status, ScheduledEvaluationWorkStatus.leased);
      expect(work.workVersion, 1);
      expect(await recovered.listAttempts('org_1', work.workId), hasLength(1));
      expect(await recovered.claimDue(_request('owner_2', 'k')), isEmpty);
    },
  );

  test(
    'retry exhaustion and manual retry retain immutable work identity',
    () async {
      var now = baseNow;
      final root = await Directory.systemTemp.createTemp('hyfens-p3e5-retry-');
      addTearDown(() => root.delete(recursive: true));
      final store = FileP3e5ScheduleStore(root, clock: () => now);
      await store.initialize();
      addTearDown(store.close);
      await _seed(store, now);
      final claim = (await store.claimDue(_request('owner_1', 'w'))).single;
      const exhaustedPolicy = P3e5RetryPolicy(
        version: 1,
        initialDelay: Duration(seconds: 2),
        maximumDelay: Duration(seconds: 2),
        maximumAttempts: 1,
        jitterMode: P3e5JitterMode.none,
        jitterBound: Duration.zero,
      );
      final failed = await store.failClaim(
        lease: _lease(claim, owner: 'owner_1'),
        failure: P3e5RetryFailure(
          classification: P3e5RetryClass.transient,
          safeCode: 'RETRY_EXHAUSTED',
        ),
        retryPolicy: exhaustedPolicy,
      );
      expect(failed.work.status, ScheduledEvaluationWorkStatus.failedPermanent);
      final retry = await store.manualRetry(
        scope: _scope,
        workId: failed.work.workId,
        expectedWorkVersion: failed.work.workVersion,
        retryPolicy: _retry,
      );
      expect(retry.work.status, ScheduledEvaluationWorkStatus.retryWait);
      expect(retry.work.logicalKey.digest, claim.work.logicalKey.digest);
      expect(await store.claimDue(_request('owner_2', 'x')), isEmpty);
      now = now.add(const Duration(seconds: 5));
      final reclaimed = await store.claimDue(_request('owner_2', 'y'));
      expect(reclaimed, hasLength(1));
      expect(reclaimed.single.work.attemptCount, 2);
    },
  );

  final postgresUrl = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  test(
    'PostgreSQL two-instance claim has one lease and fences replay after expiry',
    () async {
      final bootstrap = PostgresControlPlaneStore(postgresUrl!);
      await bootstrap.initialize();
      await bootstrap.close();
      final left = PostgresP3e5ScheduleStore(postgresUrl);
      final right = PostgresP3e5ScheduleStore(postgresUrl);
      await Future.wait([left.initialize(), right.initialize()]);
      addTearDown(left.close);
      addTearDown(right.close);
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      await _seed(left, now, suffix: suffix);
      final scope = P3e5ClaimScope(
        organizationId: 'org_$suffix',
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
      );
      final claims = await Future.wait([
        left.claimDue(
          _request(
            'left',
            'l',
            scope: scope,
            lease: const Duration(milliseconds: 50),
          ),
        ),
        right.claimDue(
          _request(
            'right',
            'r',
            scope: scope,
            lease: const Duration(milliseconds: 50),
          ),
        ),
      ]);
      expect(claims.expand((items) => items), hasLength(1));
      final winner = claims.expand((items) => items).single;
      expect(
        await left.listAttempts(scope.organizationId, winner.work.workId),
        hasLength(1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final reclaimed = await right.claimDue(
        _request(
          'new_owner',
          'n',
          scope: scope,
          lease: const Duration(milliseconds: 50),
        ),
      );
      expect(reclaimed, hasLength(1));
      expect(reclaimed.single.reclaimed, isTrue);
      expect(
        left.failClaim(
          lease: P3e5LeaseMutation(
            scope: scope,
            workId: winner.work.workId,
            expectedWorkVersion: winner.work.workVersion,
            leaseOwner: winner.work.leaseOwner!,
            rawLeaseToken: winner.rawLeaseToken,
          ),
          failure: P3e5RetryFailure(
            classification: P3e5RetryClass.transient,
            safeCode: 'OLD_TOKEN',
          ),
          retryPolicy: _retry,
        ),
        throwsA(isA<StorageConflict>()),
      );
    },
    skip: postgresUrl == null
        ? 'PostgreSQL P3E5 claim integration requires HYFENS_TEST_POSTGRES_URL'
        : false,
  );

  test(
    'PostgreSQL claim failure seams distinguish rollback from lost response',
    () async {
      final suffix =
          'crash_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      final now = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      final before = PostgresP3e5ScheduleStore(
        postgresUrl!,
        claimFailure: (point) {
          if (point == P3e5PostgresClaimFailurePoint.beforeCommit) {
            throw StateError('TEST ONLY before commit');
          }
        },
      );
      final verifier = PostgresP3e5ScheduleStore(postgresUrl);
      await Future.wait([before.initialize(), verifier.initialize()]);
      addTearDown(before.close);
      addTearDown(verifier.close);
      await _seed(before, now, suffix: suffix);
      final scope = P3e5ClaimScope(
        organizationId: 'org_$suffix',
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
      );
      await expectLater(
        before.claimDue(_request('before', 's', scope: scope)),
        throwsA(isA<StateError>()),
      );
      expect(
        await verifier.claimDue(_request('verifier', 't', scope: scope)),
        hasLength(1),
      );

      final lostSuffix = '${suffix}_lost';
      var afterCommit = true;
      final lost = PostgresP3e5ScheduleStore(
        postgresUrl,
        claimFailure: (point) {
          if (afterCommit &&
              point == P3e5PostgresClaimFailurePoint.afterCommit) {
            afterCommit = false;
            throw StateError('TEST ONLY lost response');
          }
        },
      );
      await lost.initialize();
      addTearDown(lost.close);
      await _seed(lost, now, suffix: lostSuffix);
      final lostScope = P3e5ClaimScope(
        organizationId: 'org_$lostSuffix',
        applicationId: 'app_$lostSuffix',
        environmentId: 'env_$lostSuffix',
      );
      await expectLater(
        lost.claimDue(_request('lost', 'u', scope: lostScope)),
        throwsA(isA<StateError>()),
      );
      final persisted = (await verifier.listWork(lostScope.organizationId))
          .single;
      expect(persisted.status, ScheduledEvaluationWorkStatus.leased);
      expect(persisted.attemptCount, 1);
      expect(
        await verifier.claimDue(_request('other', 'v', scope: lostScope)),
        isEmpty,
      );
    },
    skip: postgresUrl == null
        ? 'PostgreSQL P3E5 failure injection requires HYFENS_TEST_POSTGRES_URL'
        : false,
  );
}

const _scope = P3e5ClaimScope(
  organizationId: 'org_1',
  applicationId: 'app_1',
  environmentId: 'env_1',
);

const _retry = P3e5RetryPolicy(
  version: 1,
  initialDelay: Duration(seconds: 2),
  maximumDelay: Duration(seconds: 8),
  maximumAttempts: 4,
  jitterMode: P3e5JitterMode.none,
  jitterBound: Duration.zero,
);

P3e5ClaimRequest _request(
  String owner,
  String tokenSeed, {
  P3e5ClaimScope scope = _scope,
  Duration lease = const Duration(seconds: 5),
}) => P3e5ClaimRequest(
  scope: scope,
  leaseOwner: owner,
  leasePolicy: P3e5LeasePolicy(version: 1, duration: lease),
  resourcePolicy: const P3e5ClaimResourcePolicy(
    version: 1,
    claimBatchSize: 1,
    pendingConsiderationLimit: 8,
    maximumActiveLeasesPerTenant: 1,
    recoveryScanBatch: 8,
  ),
  preparedLeases: [P3e5PreparedLease(tokenSeed * 40)],
);

P3e5LeaseMutation _lease(P3e5ClaimedWork claim, {required String owner}) =>
    P3e5LeaseMutation(
      scope: _scope,
      workId: claim.work.workId,
      expectedWorkVersion: claim.work.workVersion,
      leaseOwner: owner,
      rawLeaseToken: claim.rawLeaseToken,
    );

Future<void> _seed(
  P3e5ScheduleStore store,
  DateTime now, {
  String suffix = '1',
  String? targetDigest,
}) async {
  final schedule = EvaluationSchedule(
    scheduleId: 'schedule_$suffix',
    organizationId: 'org_$suffix',
    applicationId: 'app_$suffix',
    environmentId: 'env_$suffix',
    rolloutId: 'rollout_$suffix',
    currentScheduleRevision: 'schedule_revision_${suffix}_1',
    createdAt: now,
    createdBy: 'actor_1',
  );
  final revision = EvaluationScheduleRevision(
    scheduleRevisionId: 'schedule_revision_${suffix}_1',
    scheduleId: schedule.scheduleId,
    scheduleGeneration: 1,
    organizationId: schedule.organizationId,
    applicationId: schedule.applicationId,
    environmentId: schedule.environmentId,
    rolloutId: schedule.rolloutId,
    scheduledEvaluationEnabled: true,
    readinessPhase: EvaluationReadinessPhase.sealed,
    triggerPolicyVersion: 1,
    schedulePolicyVersion: 1,
    evaluationPolicyVersion: 1,
    evaluationPolicyDigest: _digest('e'),
    thresholdSetVersion: 1,
    thresholdSetDigest: _digest('t'),
    aggregationVersion: 1,
    windowPolicyVersion: 1,
    privacyPolicyVersion: 1,
    retryPolicyReference: 'retry_v1',
    resourcePolicyReference: 'resource_v1',
    supersedesScheduleRevisionId: null,
    createdAt: now,
    createdBy: 'actor_1',
    reason: 'TEST VECTOR ONLY',
  );
  await store.createSchedule(schedule, revision);
  await store.putWork(
    ScheduledEvaluationWork.pending(
      logicalKey: _key(suffix: suffix, targetDigest: targetDigest),
      serverNow: now,
    ),
  );
}

LogicalEvaluationKey _key({
  String suffix = '1',
  String window = 'window',
  String? targetDigest,
}) => LogicalEvaluationKey(
  organizationId: 'org_$suffix',
  applicationId: 'app_$suffix',
  environmentId: 'env_$suffix',
  platformId: 'platform_$suffix',
  rolloutId: 'rollout_$suffix',
  rolloutRevision: 1,
  releaseId: 'release_$suffix',
  patchId: 'patch_$suffix',
  sequence: 1,
  targetBindingDigest: targetDigest ?? _digest('b'),
  windowId: '${window}_$suffix',
  readinessPhase: EvaluationReadinessPhase.sealed,
  observationSchemaVersion: 1,
  aggregationVersion: 1,
  aggregatePolicyDigest: _digest('a'),
  evaluationPolicyVersion: 1,
  evaluationPolicyDigest: _digest('e'),
  thresholdSetVersion: 1,
  thresholdSetDigest: _digest('t'),
  windowPolicyVersion: 1,
  privacyPolicyVersion: 1,
  scheduleId: 'schedule_$suffix',
  scheduleRevisionId: 'schedule_revision_${suffix}_1',
  scheduleGeneration: 1,
);

String _digest(String value) => sha256Digest(value.codeUnits);
