import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  for (final decision in const <String>[
    'CONTINUE',
    'HOLD',
    'INSUFFICIENT_DATA',
    'MANUAL_REVIEW',
    'HALT_NEW_OFFERS',
  ]) {
    test(
      'explicit executor persists and maps $decision without rollout mutation',
      () async {
        final fixture = await _ExecutorFixture.create(decision: decision);
        addTearDown(fixture.close);

        final result = await fixture.invoke();

        expect(result.outcomes, hasLength(1));
        final outcome = result.outcomes.single;
        expect(outcome.decision.decision, decision);
        expect(
          outcome.work.status,
          decision == 'HALT_NEW_OFFERS'
              ? ScheduledEvaluationWorkStatus.evaluated
              : ScheduledEvaluationWorkStatus.completed,
        );
        expect(outcome.work.aggregateId, fixture.aggregateId);
        expect(outcome.work.aggregateRevisionId, fixture.aggregateRevisionId);
        expect(outcome.work.evaluationId, isNotNull);
        expect(outcome.work.decisionId, isNotNull);
        final rollout = RolloutRecord.fromJson(
          (await fixture.controlStore.readJson('rollouts', fixture.rolloutId))!,
        );
        expect(rollout.currentRevision, 1);
        expect(rollout.state, RolloutState.canary);
      },
    );
  }

  test('scheduler scope is exact and rollout:halt is unnecessary', () async {
    final fixture = await _ExecutorFixture.create(decision: 'CONTINUE');
    addTearDown(fixture.close);
    expect(fixture.credential.record.scopes, evaluationOnlySchedulerScopes);

    final wrong = fixture.tenant(
      scope: P3e5ClaimScope(
        organizationId: fixture.organizationId,
        applicationId: fixture.applicationId,
        environmentId: 'env_wrong',
      ),
    );
    await expectLater(
      fixture.executor().invoke(
        tenants: [wrong],
        resourcePolicy: _executorPolicy,
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'NOT_FOUND',
        ),
      ),
    );
  });

  test(
    'executor audit is bounded and redacts credentials and lease material',
    () async {
      final fixture = await _ExecutorFixture.create(decision: 'CONTINUE');
      addTearDown(fixture.close);
      await fixture.invoke();

      final audit = (await fixture.controlStore.readAuditChain()).toString();
      expect(audit, contains('health.executor_invoked'));
      expect(audit, contains('health.evaluation_started'));
      expect(audit, contains('health.evaluation_completed'));
      expect(audit, isNot(contains(fixture.credential.token)));
      expect(audit, isNot(contains('rawLeaseToken')));
      expect(audit, contains('leaseTokenDigest'));
    },
  );

  for (final point in const <P3e5ExecutorFailurePoint>[
    P3e5ExecutorFailurePoint.afterEvaluating,
    P3e5ExecutorFailurePoint.afterEvaluationCommit,
    P3e5ExecutorFailurePoint.afterEvaluated,
    P3e5ExecutorFailurePoint.beforeResponse,
  ]) {
    test('recovers idempotently after ${point.name}', () async {
      final fixture = await _ExecutorFixture.create(decision: 'CONTINUE');
      addTearDown(fixture.close);
      var injected = false;
      final crashing = fixture.executor(
        failure: (actual) {
          if (!injected && actual == point) {
            injected = true;
            throw StateError('TEST ONLY ${point.name}');
          }
        },
      );
      await expectLater(
        crashing.invoke(
          tenants: [fixture.tenant()],
          resourcePolicy: _executorPolicy,
        ),
        throwsA(isA<StateError>()),
      );

      fixture.now = fixture.now.add(const Duration(seconds: 6));
      final recovered = await fixture.invoke();
      if (point == P3e5ExecutorFailurePoint.beforeResponse) {
        expect(recovered.outcomes, isEmpty);
      } else {
        expect(recovered.outcomes, hasLength(1));
        expect(
          recovered.outcomes.single.work.status,
          ScheduledEvaluationWorkStatus.completed,
        );
        expect(
          recovered.outcomes.single.reusedEvaluation,
          point != P3e5ExecutorFailurePoint.afterEvaluating,
        );
      }
      expect(
        await fixture.p3eStore.listEvaluations(fixture.organizationId),
        hasLength(1),
      );
      expect(
        await fixture.p3eStore.listDecisions(fixture.organizationId),
        hasLength(1),
      );
    });
  }

  test(
    'lease expiry during evaluation fences stale completion and recovers',
    () async {
      final fixture = await _ExecutorFixture.create(decision: 'CONTINUE');
      addTearDown(fixture.close);
      var injected = false;
      final expiring = fixture.executor(
        failure: (point) {
          if (!injected &&
              point == P3e5ExecutorFailurePoint.afterEvaluationCommit) {
            injected = true;
            fixture.now = fixture.now.add(const Duration(seconds: 6));
          }
        },
      );
      await expectLater(
        expiring.invoke(
          tenants: [fixture.tenant()],
          resourcePolicy: _executorPolicy,
        ),
        throwsA(isA<StorageConflict>()),
      );
      expect(
        await fixture.p3eStore.listEvaluations(fixture.organizationId),
        hasLength(1),
      );

      final recovered = await fixture.invoke();
      expect(recovered.outcomes, hasLength(1));
      expect(recovered.outcomes.single.reusedEvaluation, isTrue);
      expect(
        recovered.outcomes.single.work.status,
        ScheduledEvaluationWorkStatus.completed,
      );
    },
  );

  test(
    'resource policy and fairness cursor fail closed deterministically',
    () async {
      final fixture = await _ExecutorFixture.create(decision: 'CONTINUE');
      addTearDown(fixture.close);
      expect(
        () => const P3e5ExecutorResourcePolicy(
          version: 99,
          claimBatchSize: 1,
          maximumWorksPerInvocation: 1,
          maximumEvaluationDurationBudget: Duration(seconds: 1),
          maximumAggregateRecordsPerWork: 1,
          maximumRetriesProcessedPerInvocation: 1,
          maximumTenantScopes: 1,
          crossTenantFairness: P3e5CrossTenantFairness.roundRobinCursor,
        ).validate(const P3e5ScheduleLimits()),
        throwsFormatException,
      );
      await expectLater(
        fixture.executor().invoke(
          tenants: [fixture.tenant()],
          resourcePolicy: _executorPolicy,
          fairnessCursor: 'unknown/scope/cursor',
        ),
        throwsFormatException,
      );
      expect(
        P3e5FairnessCursor.order(const [
          'tenant/c',
          'tenant/a',
          'tenant/b',
        ], null),
        const ['tenant/a', 'tenant/b', 'tenant/c'],
      );
      expect(
        P3e5FairnessCursor.order(const [
          'tenant/c',
          'tenant/a',
          'tenant/b',
        ], 'tenant/a'),
        const ['tenant/b', 'tenant/c', 'tenant/a'],
      );
      expect(
        () => P3e5FairnessCursor.order(const ['tenant/a', 'tenant/a'], null),
        throwsFormatException,
      );

      final remaining = <String, int>{'tenant/a': 10, 'tenant/b': 1};
      String? cursor;
      final selected = <String>[];
      for (var invocation = 0; invocation < 2; invocation++) {
        final order = P3e5FairnessCursor.order(remaining.keys, cursor);
        final tenant = order.firstWhere((key) => remaining[key]! > 0);
        remaining[tenant] = remaining[tenant]! - 1;
        selected.add(tenant);
        cursor = tenant;
      }
      expect(selected, const ['tenant/a', 'tenant/b']);
    },
  );

  test(
    'missing aggregate evidence fails permanently without host crash',
    () async {
      final fixture = await _ExecutorFixture.create(
        decision: 'CONTINUE',
        seedAggregate: false,
      );
      addTearDown(fixture.close);

      final result = await fixture.invoke();

      expect(result.outcomes, isEmpty);
      final work = (await fixture.scheduleStore.listWork(
        fixture.organizationId,
      )).single;
      expect(work.status, ScheduledEvaluationWorkStatus.failedPermanent);
      expect(work.lastErrorCode, 'HEALTH_AGGREGATE_NOT_FOUND');
      expect(
        await fixture.p3eStore.listEvaluations(fixture.organizationId),
        isEmpty,
      );
    },
  );

  test(
    'premature window readiness is rejected before evaluator invocation',
    () async {
      final fixture = await _ExecutorFixture.create(
        decision: 'CONTINUE',
        windowReady: false,
      );
      addTearDown(fixture.close);

      final result = await fixture.invoke();

      expect(result.outcomes, isEmpty);
      final work = (await fixture.scheduleStore.listWork(
        fixture.organizationId,
      )).single;
      expect(work.status, ScheduledEvaluationWorkStatus.failedPermanent);
      expect(work.lastErrorCode, 'HEALTH_EXECUTOR_WINDOW_NOT_READY');
      expect(
        await fixture.p3eStore.listEvaluations(fixture.organizationId),
        isEmpty,
      );
    },
  );

  test('stale rollout binding is classified STALE before evaluation', () async {
    final fixture = await _ExecutorFixture.create(
      decision: 'CONTINUE',
      staleRollout: true,
    );
    addTearDown(fixture.close);

    expect((await fixture.invoke()).outcomes, isEmpty);
    final work = (await fixture.scheduleStore.listWork(fixture.organizationId))
        .single;
    expect(work.status, ScheduledEvaluationWorkStatus.stale);
    expect(work.lastErrorClass, P3e5RetryClass.stale.wireName);
    expect(
      await fixture.p3eStore.listEvaluations(fixture.organizationId),
      isEmpty,
    );
  });

  test(
    'aggregate load bound enters bounded retry without evaluation',
    () async {
      final fixture = await _ExecutorFixture.create(decision: 'CONTINUE');
      addTearDown(fixture.close);
      final aggregate = (await fixture.p3eStore.readAggregate(
        fixture.organizationId,
        fixture.aggregateId,
      ))!;
      final revision = (await fixture.p3eStore.readAggregateRevision(
        fixture.organizationId,
        fixture.aggregateRevisionId,
      ))!;
      await fixture.p3eStore.putAggregateRevision(
        HealthAggregateRecord(
          aggregateId: 'aggregate_extra',
          revisionId: 'aggregate_revision_extra',
          aggregate: aggregate.aggregate,
          recomputability: aggregate.recomputability,
          createdAt: fixture.now,
        ),
        HealthAggregateRevision(
          aggregateRevisionId: 'aggregate_revision_extra',
          aggregateId: 'aggregate_extra',
          parentAggregateRevisionId: null,
          identity: revision.identity,
          window: revision.window,
          aggregationVersion: revision.aggregationVersion,
          inputCount: revision.inputCount,
          inputDigest: revision.inputDigest,
          recomputationReason: 'TEST VECTOR ONLY',
          recomputability: revision.recomputability,
          createdAt: fixture.now,
        ),
      );
      const constrained = P3e5ExecutorResourcePolicy(
        version: 1,
        claimBatchSize: 1,
        maximumWorksPerInvocation: 1,
        maximumEvaluationDurationBudget: Duration(seconds: 10),
        maximumAggregateRecordsPerWork: 1,
        maximumRetriesProcessedPerInvocation: 1,
        maximumTenantScopes: 1,
        crossTenantFairness: P3e5CrossTenantFairness.roundRobinCursor,
      );

      final result = await fixture.executor().invoke(
        tenants: [fixture.tenant()],
        resourcePolicy: constrained,
      );

      expect(result.outcomes, isEmpty);
      final work = (await fixture.scheduleStore.listWork(
        fixture.organizationId,
      )).single;
      expect(work.status, ScheduledEvaluationWorkStatus.retryWait);
      expect(work.lastErrorCode, 'HEALTH_EXECUTOR_RESOURCE_LIMIT');
      expect(
        await fixture.p3eStore.listEvaluations(fixture.organizationId),
        isEmpty,
      );
    },
  );

  test('execution transitions fence wrong owners and expired tokens', () async {
    final fixture = await _ExecutorFixture.create(decision: 'CONTINUE');
    addTearDown(fixture.close);
    final scope = fixture.tenant().scope;
    final first = (await fixture.scheduleStore.claimDue(
      P3e5ClaimRequest(
        scope: scope,
        leaseOwner: 'owner_first',
        leasePolicy: _leasePolicy,
        resourcePolicy: _claimPolicy,
        preparedLeases: [P3e5PreparedLease('a' * 40)],
      ),
    )).single;
    P3e5LeaseMutation lease(String owner, String token, int version) =>
        P3e5LeaseMutation(
          scope: scope,
          workId: first.work.workId,
          expectedWorkVersion: version,
          leaseOwner: owner,
          rawLeaseToken: token,
        );
    await expectLater(
      fixture.scheduleStore.advanceExecution(
        P3e5ExecutionAdvance(
          lease: lease(
            'owner_wrong',
            first.rawLeaseToken,
            first.work.workVersion,
          ),
          expectedStatus: ScheduledEvaluationWorkStatus.leased,
          nextStatus: ScheduledEvaluationWorkStatus.evaluating,
          aggregateId: fixture.aggregateId,
          aggregateRevisionId: fixture.aggregateRevisionId,
        ),
      ),
      throwsA(isA<StorageConflict>()),
    );
    final evaluating = await fixture.scheduleStore.advanceExecution(
      P3e5ExecutionAdvance(
        lease: lease(
          'owner_first',
          first.rawLeaseToken,
          first.work.workVersion,
        ),
        expectedStatus: ScheduledEvaluationWorkStatus.leased,
        nextStatus: ScheduledEvaluationWorkStatus.evaluating,
        aggregateId: fixture.aggregateId,
        aggregateRevisionId: fixture.aggregateRevisionId,
      ),
    );
    fixture.now = fixture.now.add(const Duration(seconds: 6));
    final recovered = (await fixture.scheduleStore.claimDue(
      P3e5ClaimRequest(
        scope: scope,
        leaseOwner: 'owner_second',
        leasePolicy: _leasePolicy,
        resourcePolicy: _claimPolicy,
        preparedLeases: [P3e5PreparedLease('b' * 40)],
      ),
    )).single;
    expect(recovered.work.status, ScheduledEvaluationWorkStatus.evaluating);
    await expectLater(
      fixture.scheduleStore.advanceExecution(
        P3e5ExecutionAdvance(
          lease: lease(
            'owner_first',
            first.rawLeaseToken,
            evaluating.work.workVersion,
          ),
          expectedStatus: ScheduledEvaluationWorkStatus.evaluating,
          nextStatus: ScheduledEvaluationWorkStatus.evaluated,
          evaluationId: 'evaluation_old',
          decisionId: 'decision_old',
        ),
      ),
      throwsA(isA<StorageConflict>()),
    );
  });

  final postgresUrl = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  test(
    'two PostgreSQL executor instances produce one evaluation and decision',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final fixture = await _ExecutorFixture.create(
        decision: 'CONTINUE',
        postgresUrl: postgresUrl,
        suffix: suffix,
      );
      addTearDown(fixture.close);
      final rightControl = PostgresControlPlaneStore(postgresUrl!);
      final rightP3e = PostgresP3ePersistenceStore(postgresUrl);
      final rightSchedules = PostgresP3e5ScheduleStore(postgresUrl);
      final rightService = ControlPlaneService(
        store: rightControl,
        p3eStore: rightP3e,
        clock: () => fixture.now,
      );
      await Future.wait([
        rightService.initialize(),
        rightSchedules.initialize(),
      ]);
      addTearDown(() async {
        await rightSchedules.close();
        await rightP3e.close();
        await rightControl.close();
      });
      final rightExecutor = P3e5ExplicitExecutorService(
        controlStore: rightControl,
        scheduleStore: rightSchedules,
        p3eStore: rightP3e,
        controlService: rightService,
        clock: () => fixture.now,
      );

      final results = await Future.wait([
        fixture.executor().invoke(
          tenants: [fixture.tenant(owner: 'executor_left')],
          resourcePolicy: _executorPolicy,
        ),
        rightExecutor.invoke(
          tenants: [fixture.tenant(owner: 'executor_right')],
          resourcePolicy: _executorPolicy,
        ),
      ]);

      expect(results.expand((result) => result.outcomes), hasLength(1));
      expect(
        await fixture.p3eStore.listEvaluations(fixture.organizationId),
        hasLength(1),
      );
      expect(
        await fixture.p3eStore.listDecisions(fixture.organizationId),
        hasLength(1),
      );
    },
    skip: postgresUrl == null
        ? 'PostgreSQL executor integration requires HYFENS_TEST_POSTGRES_URL'
        : false,
  );
}

const _executorPolicy = P3e5ExecutorResourcePolicy(
  version: 1,
  claimBatchSize: 1,
  maximumWorksPerInvocation: 1,
  maximumEvaluationDurationBudget: Duration(seconds: 10),
  maximumAggregateRecordsPerWork: 8,
  maximumRetriesProcessedPerInvocation: 1,
  maximumTenantScopes: 4,
  crossTenantFairness: P3e5CrossTenantFairness.roundRobinCursor,
);

const _leasePolicy = P3e5LeasePolicy(
  version: 1,
  duration: Duration(seconds: 5),
);

const _retryPolicy = P3e5RetryPolicy(
  version: 1,
  initialDelay: Duration(seconds: 1),
  maximumDelay: Duration(seconds: 4),
  maximumAttempts: 4,
  jitterMode: P3e5JitterMode.none,
  jitterBound: Duration.zero,
);

const _claimPolicy = P3e5ClaimResourcePolicy(
  version: 1,
  claimBatchSize: 1,
  pendingConsiderationLimit: 8,
  maximumActiveLeasesPerTenant: 1,
  recoveryScanBatch: 8,
);

final class _ExecutorFixture {
  _ExecutorFixture._({
    required this.root,
    required this.controlStore,
    required this.p3eStore,
    required this.scheduleStore,
    required this.service,
    required this.credential,
    required this.policy,
    required this.organizationId,
    required this.applicationId,
    required this.environmentId,
    required this.rolloutId,
    required this.aggregateId,
    required this.aggregateRevisionId,
    required this.clock,
  });

  final Directory? root;
  final ControlPlaneStore controlStore;
  final P3ePersistenceStore p3eStore;
  final P3e5ScheduleStore scheduleStore;
  final ControlPlaneService service;
  final IssuedCredential credential;
  final ManualEvaluationPolicy policy;
  final String organizationId;
  final String applicationId;
  final String environmentId;
  final String rolloutId;
  final String aggregateId;
  final String aggregateRevisionId;
  final _TestClock clock;

  DateTime get now => clock.value;
  set now(DateTime value) => clock.value = value;

  static Future<_ExecutorFixture> create({
    required String decision,
    String? postgresUrl,
    String suffix = 'executor',
    bool seedAggregate = true,
    bool windowReady = true,
    bool staleRollout = false,
  }) async {
    final clock = _TestClock(DateTime.utc(2026, 8, 24));
    final root = postgresUrl == null
        ? await Directory.systemTemp.createTemp('hyfens-p3e5-executor-')
        : null;
    final ControlPlaneStore control = postgresUrl == null
        ? FileControlPlaneStore(Directory('${root!.path}/control'))
        : PostgresControlPlaneStore(postgresUrl);
    final P3ePersistenceStore p3e = postgresUrl == null
        ? FileP3ePersistenceStore(Directory('${root!.path}/p3e'))
        : PostgresP3ePersistenceStore(postgresUrl);
    final P3e5ScheduleStore schedules = postgresUrl == null
        ? FileP3e5ScheduleStore(
            Directory('${root!.path}/schedules'),
            clock: clock.call,
          )
        : PostgresP3e5ScheduleStore(postgresUrl);
    final service = ControlPlaneService(
      store: control,
      p3eStore: p3e,
      clock: clock.call,
    );
    final bootstrap = await service.bootstrap(
      organizationName: 'Executor test',
      runtimeApplicationId: 'dev.hyfens.executor',
      platformId: 'android',
      environmentName: 'test',
    );
    final policy = _policy(decision);
    final credential = CredentialService().issue(
      id: 'scheduler_$suffix',
      organizationId: bootstrap.organization.id,
      kind: CredentialKind.scheduler,
      scopes: evaluationOnlySchedulerScopes,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      expiresAt: clock.value.add(const Duration(hours: 1)),
    );
    await control.createJson(
      'credentials',
      credential.record.tokenHash,
      credential.record.toJson(),
    );
    final rolloutId = 'rollout_$suffix';
    final target = RolloutTarget(
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      platformId: 'android',
      releaseId: 'release_$suffix',
      runtimeReleaseId: 'runtime-release-$suffix',
      patchId: 'patch_$suffix',
      runtimePatchId: 'runtime-patch-$suffix',
      artifactId: 'artifact_$suffix',
      sha256: _digest('artifact'),
      sequence: 1,
    );
    final rollout = RolloutRecord(
      id: rolloutId,
      organizationId: bootstrap.organization.id,
      currentRevision: staleRollout ? 2 : 1,
      state: RolloutState.canary,
      createdAt: clock.value,
    );
    final rolloutRevision = RolloutRevision(
      id: 'rollout_revision_$suffix',
      rolloutId: rolloutId,
      organizationId: bootstrap.organization.id,
      revision: 1,
      previousRevision: null,
      state: RolloutState.canary,
      target: target,
      policy: RolloutPolicy(
        cohortKind: RolloutCohortKind.percentage,
        percentageBasisPoints: 100,
        salt: 'TEST_ONLY',
      ),
      actorId: bootstrap.controlCredential.record.id,
      reason: 'TEST VECTOR ONLY',
      pausedFromState: null,
      createdAt: clock.value,
    );
    await control.createJson('rollouts', rolloutId, rollout.toJson());
    await control.createJson(
      'rollout_revisions',
      rolloutRevision.id,
      rolloutRevision.toJson(),
    );
    await schedules.initialize();
    final schedule = EvaluationSchedule(
      scheduleId: 'schedule_$suffix',
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      rolloutId: rolloutId,
      currentScheduleRevision: 'schedule_revision_$suffix',
      createdAt: clock.value,
      createdBy: bootstrap.controlCredential.record.id,
    );
    final scheduleRevision = EvaluationScheduleRevision(
      scheduleRevisionId: 'schedule_revision_$suffix',
      scheduleId: schedule.scheduleId,
      scheduleGeneration: 1,
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      rolloutId: rolloutId,
      scheduledEvaluationEnabled: true,
      readinessPhase: EvaluationReadinessPhase.sealed,
      triggerPolicyVersion: 1,
      schedulePolicyVersion: 1,
      evaluationPolicyVersion: policy.evaluationVersion,
      evaluationPolicyDigest: policy.policyDigest,
      thresholdSetVersion: policy.thresholdSetVersion,
      thresholdSetDigest: policy.thresholdSetDigest,
      aggregationVersion: 1,
      windowPolicyVersion: policy.windowPolicyVersion,
      privacyPolicyVersion: policy.privacyPolicyVersion,
      retryPolicyReference: 'retry_v1',
      resourcePolicyReference: 'resource_v1',
      supersedesScheduleRevisionId: null,
      createdAt: clock.value,
      createdBy: bootstrap.controlCredential.record.id,
      reason: 'TEST VECTOR ONLY',
    );
    await schedules.createSchedule(schedule, scheduleRevision);
    final aggregate = _aggregate(
      decision: decision,
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      suffix: suffix,
      windowReady: windowReady,
    );
    final aggregateId = 'aggregate_$suffix';
    final aggregateRevisionId = 'aggregate_revision_$suffix';
    final revision = HealthAggregateRevision(
      aggregateRevisionId: aggregateRevisionId,
      aggregateId: aggregateId,
      parentAggregateRevisionId: null,
      identity: aggregate.identity,
      window: aggregate.window,
      aggregationVersion: 1,
      inputCount: aggregate.inputCount,
      inputDigest: aggregate.inputDigest,
      recomputationReason: 'TEST VECTOR ONLY',
      recomputability: P3eRecomputability.rawRecomputable,
      createdAt: clock.value,
    );
    if (seedAggregate) {
      await p3e.putAggregateRevision(
        HealthAggregateRecord(
          aggregateId: aggregateId,
          revisionId: aggregateRevisionId,
          aggregate: aggregate,
          recomputability: P3eRecomputability.rawRecomputable,
          createdAt: clock.value,
        ),
        revision,
      );
    }
    final key = LogicalEvaluationKey(
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      platformId: 'android',
      rolloutId: rolloutId,
      rolloutRevision: 1,
      releaseId: target.releaseId,
      patchId: target.patchId,
      sequence: target.sequence,
      targetBindingDigest: sha256Digest(
        canonicalJson(target.toJson()).codeUnits,
      ),
      windowId: aggregate.identity.windowId,
      readinessPhase: EvaluationReadinessPhase.sealed,
      observationSchemaVersion: 1,
      aggregationVersion: 1,
      aggregatePolicyDigest: aggregate.policyDigest,
      evaluationPolicyVersion: policy.evaluationVersion,
      evaluationPolicyDigest: policy.policyDigest,
      thresholdSetVersion: policy.thresholdSetVersion,
      thresholdSetDigest: policy.thresholdSetDigest,
      windowPolicyVersion: policy.windowPolicyVersion,
      privacyPolicyVersion: policy.privacyPolicyVersion,
      scheduleId: schedule.scheduleId,
      scheduleRevisionId: scheduleRevision.scheduleRevisionId,
      scheduleGeneration: 1,
    );
    await schedules.putWork(
      ScheduledEvaluationWork.pending(logicalKey: key, serverNow: clock.value),
    );
    return _ExecutorFixture._(
      root: root,
      controlStore: control,
      p3eStore: p3e,
      scheduleStore: schedules,
      service: service,
      credential: credential,
      policy: policy,
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      rolloutId: rolloutId,
      aggregateId: aggregateId,
      aggregateRevisionId: aggregateRevisionId,
      clock: clock,
    );
  }

  P3e5TenantExecutionInput tenant({
    P3e5ClaimScope? scope,
    String owner = 'executor_instance',
  }) => P3e5TenantExecutionInput(
    token: credential.token,
    scope:
        scope ??
        P3e5ClaimScope(
          organizationId: organizationId,
          applicationId: applicationId,
          environmentId: environmentId,
        ),
    leaseOwner: owner,
    leasePolicy: _leasePolicy,
    retryPolicy: _retryPolicy,
    claimResourcePolicy: _claimPolicy,
    evaluationPolicy: policy,
  );

  P3e5ExplicitExecutorService executor({
    void Function(P3e5ExecutorFailurePoint point)? failure,
  }) => P3e5ExplicitExecutorService(
    controlStore: controlStore,
    scheduleStore: scheduleStore,
    p3eStore: p3eStore,
    controlService: service,
    clock: () => now,
    failure: failure,
  );

  Future<P3e5ExecutorInvocationResult> invoke() =>
      executor().invoke(tenants: [tenant()], resourcePolicy: _executorPolicy);

  Future<void> close() async {
    await scheduleStore.close();
    await p3eStore.close();
    await controlStore.close();
    await root?.delete(recursive: true);
  }
}

ManualEvaluationPolicy _policy(String decision) => ManualEvaluationPolicy(
  evaluationVersion: 1,
  policyVersion: 1,
  thresholdSetVersion: 1,
  windowPolicyVersion: 1,
  privacyPolicyVersion: 1,
  thresholdSetDigest: _digest('threshold'),
  minimumSamples: const AggregationMinimumSamples(
    minimumEligibleObserved: 1,
    minimumOffers: 1,
    minimumActivated: 1,
    minimumHealthyConfirmations: 1,
    minimumCoverageBasisPoints: 10000,
  ),
  requireFreshness: true,
  allowNonRecomputable: false,
  maximumQuarantineRateBasisPoints: decision == 'MANUAL_REVIEW' ? 0 : 10000,
  maximumRejectedRateBasisPoints: 10000,
  maximumLateRateBasisPoints: 10000,
  haltActivationFailureRateBasisPoints: decision == 'HALT_NEW_OFFERS'
      ? 5000
      : null,
  haltAdmissionRejectionRateBasisPoints: null,
  haltRuntimeFaultRateBasisPoints: null,
  haltRollbackFallbackRateBasisPoints: null,
);

HealthAggregate _aggregate({
  required String decision,
  required String organizationId,
  required String applicationId,
  required String environmentId,
  String suffix = 'executor',
  bool windowReady = true,
}) {
  final start = windowReady
      ? DateTime.utc(2026, 8, 23, 20)
      : DateTime.utc(2026, 8, 24, 8);
  final window = ObservationWindow(
    windowId: 'window_executor',
    serverStart: start,
    serverEnd: start.add(const Duration(hours: 1)),
    lateCutoff: start.add(const Duration(hours: 2)),
    minimumDuration: const Duration(hours: 1),
    maximumDuration: const Duration(hours: 3),
    windowPolicyVersion: 1,
  );
  final halt = decision == 'HALT_NEW_OFFERS';
  return HealthAggregate(
    identity: AggregateIdentity(
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
      platformId: 'android',
      releaseId: 'release_$suffix',
      patchId: 'patch_$suffix',
      sequence: 1,
      rolloutId: 'rollout_$suffix',
      rolloutRevision: 1,
      windowId: window.windowId,
      windowStart: window.serverStart,
      windowEnd: window.serverEnd,
      lateCutoff: window.lateCutoff,
      observationSchemaVersion: 1,
      aggregationVersion: 1,
    ),
    window: window,
    inputCount: halt ? 2 : 1,
    acceptedInputCount: halt ? 2 : 1,
    inputDigest: _digest('aggregate-input-$decision'),
    policyVersion: 1,
    policyDigest: _digest('aggregate-policy'),
    externalQualityDigest: _digest('aggregate-quality-$decision'),
    counters: AggregateCounters(
      eligibleInstallationsObserved: halt ? 2 : 1,
      lookupAttempts: halt ? 2 : 1,
      candidateOffers: halt ? 2 : 1,
      downloadSucceeded: halt ? 2 : 1,
      downloadFailed: 0,
      admissionVerified: halt ? 2 : 1,
      admissionRejected: 0,
      activationStarted: halt ? 2 : 1,
      activationSucceeded: halt ? 1 : 1,
      activationFailed: halt ? 1 : 0,
      healthyConfirmed: halt ? 1 : 1,
      runtimeFaults: 0,
      rollbacks: 0,
      fallbacksToAot: 0,
      restartSurvived: halt ? 1 : 1,
      staleOrReplayRejects: 0,
      lateEvents: 0,
      quarantinedEvents: decision == 'MANUAL_REVIEW' ? 1 : 0,
      missingExpectedEvents: 0,
    ),
    quality: AggregateQualityCounters(
      accepted: halt ? 2 : 1,
      duplicate: 0,
      duplicateMutations: 0,
      excessContributions: 0,
      late: 0,
      quarantined: decision == 'MANUAL_REVIEW' ? 1 : 0,
      rejected: 0,
      securityRejected: 0,
      identityMismatch: 0,
      scopeMismatch: 0,
      impossibleSequence: 0,
      clockInvalid: 0,
      schemaUnsupported: 0,
      securitySuspicion: 0,
      otherQuarantine: 0,
      outOfWindow: 0,
    ),
    metrics: <AggregateMetricName, AggregateMetric>{
      for (final name in AggregateMetricName.values)
        name:
            name == AggregateMetricName.runtimeFaultRate ||
                name == AggregateMetricName.rollbackFallbackRate ||
                name == AggregateMetricName.quarantineRate
            ? const AggregateMetric.evaluable(numerator: 0, denominator: 1)
            : const AggregateMetric.evaluable(numerator: 1, denominator: 1),
    },
    coverage: const AggregateCoverage(
      observedInstallations: 1,
      expectedInstallations: 1,
      observedBasisPoints: 10000,
      minimumBasisPoints: 10000,
      state: AggregateCoverageState.sufficient,
    ),
    samples: const AggregateSampleStatus(
      eligible: AggregateSampleCheck(observed: 1, required: 1, passed: true),
      offers: AggregateSampleCheck(observed: 1, required: 1, passed: true),
      activated: AggregateSampleCheck(observed: 1, required: 1, passed: true),
      healthy: AggregateSampleCheck(observed: 1, required: 1, passed: true),
      coveragePassed: true,
      allPassed: true,
    ),
    privacyState: decision == 'INSUFFICIENT_DATA'
        ? AggregatePrivacyState.smallCohortSuppressed
        : AggregatePrivacyState.normal,
    freshnessState: AggregateFreshnessState.fresh,
    missingData: decision == 'HOLD'
        ? const <AggregateMissingDataReason>[
            AggregateMissingDataReason.observationOutage,
          ]
        : const <AggregateMissingDataReason>[],
    latestPrimaryReceivedAt: start.add(const Duration(minutes: 5)),
  );
}

String _digest(String value) => sha256Digest(value.codeUnits);

final class _TestClock {
  _TestClock(this.value);

  DateTime value;

  DateTime call() => value;
}
