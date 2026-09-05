import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

const _digest =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  final postgresUrl = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  final now = DateTime.utc(2026, 8, 24, 12);

  test(
    'authoritative detector and evaluation-link CAS repair use real stores',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-concrete-link-',
      );
      final p3eRoot = Directory('${root.path}/p3e');
      final scheduleRoot = Directory('${root.path}/schedule');
      final repairRoot = Directory('${root.path}/reconciliation');
      addTearDown(() => root.delete(recursive: true));
      final p3e = FileP3ePersistenceStore(p3eRoot);
      final schedules = FileP3e5ScheduleStore(scheduleRoot, clock: () => now);
      final repairs = FileReconciliationStore(repairRoot);
      await p3e.initialize();
      await schedules.initialize();
      await repairs.initialize();
      addTearDown(() async {
        await repairs.close();
        await schedules.close();
        await p3e.close();
      });

      final aggregate = _aggregate();
      final revision = HealthAggregateRevision(
        aggregateRevisionId: 'revision_concrete',
        aggregateId: 'aggregate_concrete',
        parentAggregateRevisionId: null,
        identity: aggregate.identity,
        window: aggregate.window,
        aggregationVersion: aggregate.identity.aggregationVersion,
        inputCount: aggregate.inputCount,
        inputDigest: aggregate.inputDigest,
        recomputationReason: 'TEST VECTOR ONLY',
        recomputability: P3eRecomputability.rawRecomputable,
        createdAt: now,
      );
      final aggregateRecord = HealthAggregateRecord(
        aggregateId: revision.aggregateId,
        revisionId: revision.aggregateRevisionId,
        aggregate: aggregate,
        recomputability: revision.recomputability,
        createdAt: now,
      );
      final evaluation = HealthEvaluation(
        evaluationId: 'evaluation_concrete',
        organizationId: 'org',
        aggregateRevisionId: revision.aggregateRevisionId,
        rolloutId: 'rollout',
        rolloutRevision: 1,
        evaluationVersion: 1,
        policyVersion: aggregate.policyVersion,
        thresholdSetVersion: 1,
        windowPolicyVersion: 1,
        privacyPolicyVersion: 1,
        aggregateInputDigest: revision.inputDigest,
        decision: 'CONTINUE',
        reasonClass: 'PATCH_SAFETY',
        reasonCodes: const <String>['CONCRETE_TEST'],
        coverageState: aggregate.coverage.state.wireName,
        freshnessState: aggregate.freshnessState.wireName,
        sampleState: 'PASSED',
        createdAt: now,
        auditReference: null,
      );
      final decision = RolloutDecisionRecord(
        decisionId: 'decision_concrete',
        organizationId: 'org',
        rolloutId: 'rollout',
        expectedRolloutRevision: 1,
        evaluationId: evaluation.evaluationId,
        aggregateRevisionId: revision.aggregateRevisionId,
        decision: evaluation.decision,
        reason: 'TEST VECTOR ONLY',
        actorIdentity: 'test-actor',
        idempotencyKey: 'decision-concrete',
        createdAt: now,
      );
      await p3e.putAggregateRevision(aggregateRecord, revision);
      await p3e.putEvaluation(evaluation);
      await p3e.putDecision(decision);

      final schedule = _schedule(now);
      final scheduleRevision = _scheduleRevision(now);
      await schedules.createSchedule(schedule, scheduleRevision);
      final key = _key(scheduleRevision: scheduleRevision.scheduleRevisionId);
      final token = 'concrete-link-token-012345678901234567890123';
      await schedules.putWork(
        _work(
          key: key,
          status: ScheduledEvaluationWorkStatus.evaluating,
          workVersion: 1,
          token: token,
          aggregateId: aggregateRecord.aggregateId,
          aggregateRevisionId: revision.aggregateRevisionId,
          updatedAt: now,
        ),
      );

      final invocation = _invocation(now);
      final source = AuthoritativeReconciliationCandidateSource(
        p3eStore: p3e,
        scheduleStore: schedules,
      );
      final candidates = await source.discover(invocation);
      final link = candidates.where(
        (candidate) =>
            candidate.finding.code ==
            ReconciliationTaxonomyCode.workEvaluationLinkMissing,
      );
      expect(link, hasLength(1));
      expect(link.single.precondition, isNotNull);

      final executor = AuthoritativeReconciliationRepairExecutor(
        p3eStore: p3e,
        scheduleStore: schedules,
        retryPolicy: _retryPolicy,
        leaseTokenProvider: (_) async => token,
      );
      final result = await BoundedReconciliationService(
        store: repairs,
        source: _StaticSource(link.toList(growable: false)),
        executor: executor,
        audit: _MemoryAudit(),
        clock: () => now,
      ).runStartup(invocation: invocation, perTenantCap: 5, globalCap: 5);
      expect(result.repairsApplied, 1);
      final updated = await schedules.readWork('org', key.workId);
      expect(updated?.status, ScheduledEvaluationWorkStatus.evaluated);
      expect(updated?.evaluationId, evaluation.evaluationId);
      expect(updated?.decisionId, decision.decisionId);
      expect(updated?.workVersion, 2);
      await repairs.close();
      await schedules.close();
      await p3e.close();
      final reopenedP3e = FileP3ePersistenceStore(p3eRoot);
      final reopenedSchedules = FileP3e5ScheduleStore(
        scheduleRoot,
        clock: () => now,
      );
      await reopenedP3e.initialize();
      await reopenedSchedules.initialize();
      final persisted = await reopenedSchedules.readWork('org', key.workId);
      expect(persisted?.status, ScheduledEvaluationWorkStatus.evaluated);
      expect(persisted?.workVersion, 2);
      final afterRestart = await AuthoritativeReconciliationCandidateSource(
        p3eStore: reopenedP3e,
        scheduleStore: reopenedSchedules,
      ).discover(invocation);
      expect(
        afterRestart.where(
          (candidate) =>
              candidate.finding.entityId == key.workId &&
              candidate.finding.code ==
                  ReconciliationTaxonomyCode.workEvaluationLinkMissing,
        ),
        isEmpty,
      );
      await reopenedSchedules.close();
      await reopenedP3e.close();
    },
  );

  test('stale active work uses the existing mark-stale lease CAS', () async {
    final root = await Directory.systemTemp.createTemp(
      'hyfens-concrete-stale-',
    );
    final p3eRoot = Directory('${root.path}/p3e');
    final scheduleRoot = Directory('${root.path}/schedule');
    final repairRoot = Directory('${root.path}/reconciliation');
    final failedRepairRoot = Directory('${root.path}/reconciliation-failed');
    final controlRoot = Directory('${root.path}/control');
    addTearDown(() => root.delete(recursive: true));
    final p3e = FileP3ePersistenceStore(p3eRoot);
    final schedules = FileP3e5ScheduleStore(scheduleRoot, clock: () => now);
    final repairs = FileReconciliationStore(repairRoot);
    final failedRepairs = FileReconciliationStore(failedRepairRoot);
    final control = FileControlPlaneStore(controlRoot);
    await p3e.initialize();
    await schedules.initialize();
    await repairs.initialize();
    await failedRepairs.initialize();
    await control.initialize();
    addTearDown(() async {
      await control.close();
      await failedRepairs.close();
      await repairs.close();
      await schedules.close();
      await p3e.close();
    });
    final schedule = _schedule(now, logicalKeyVersion: 2);
    final revision1 = _scheduleRevision(now, logicalKeyVersion: 2);
    final revision2 = _scheduleRevision(
      now.add(const Duration(minutes: 1)),
      logicalKeyVersion: 2,
      generation: 2,
      scheduleRevisionId: 'schedule_revision_2',
      supersedes: revision1.scheduleRevisionId,
    );
    await schedules.createSchedule(schedule, revision1);
    await schedules.reviseSchedule(
      schedule: schedule.withCurrentRevision(revision2.scheduleRevisionId),
      expectedCurrentRevisionId: revision1.scheduleRevisionId,
      revision: revision2,
    );
    final key = _key(
      scheduleRevision: revision1.scheduleRevisionId,
      logicalKeyVersion: 2,
    );
    final token = 'concrete-stale-token-012345678901234567890123';
    final intent = AutomaticHaltIntent(
      workId: key.workId,
      attemptId: deriveAttemptId(key.workId, 1),
      evaluationId: 'evaluation_stale',
      decisionId: 'decision_stale',
      scheduleRevisionId: key.scheduleRevisionId,
      automaticHaltPolicyVersion: 1,
      automaticHaltPolicyDigest: _digest,
      expectedRolloutRevision: key.rolloutRevision,
      targetBindingDigest: key.targetBindingDigest,
      authorizedPrincipalId: 'principal_stale',
      authorizedAt: now,
    );
    await schedules.putWork(
      _work(
        key: key,
        status: ScheduledEvaluationWorkStatus.haltApplying,
        workVersion: 4,
        token: token,
        aggregateId: 'aggregate_stale',
        aggregateRevisionId: 'revision_stale',
        evaluationId: intent.evaluationId,
        decisionId: intent.decisionId,
        intent: intent,
        updatedAt: now,
      ),
    );
    final invocation = _invocation(now.add(const Duration(minutes: 2)));
    final source = AuthoritativeReconciliationCandidateSource(
      p3eStore: p3e,
      scheduleStore: schedules,
    );
    final candidates = await source.discover(invocation);
    final stale = candidates.where(
      (candidate) =>
          candidate.finding.code == ReconciliationTaxonomyCode.staleActiveWork,
    );
    expect(stale, hasLength(1));
    final staleCandidates = stale.toList(growable: false);
    final executor = AuthoritativeReconciliationRepairExecutor(
      p3eStore: p3e,
      scheduleStore: schedules,
      retryPolicy: _retryPolicy,
      leaseTokenProvider: (_) async => token,
    );
    final principal = ReconciliationPrincipal(
      principalId: 'principal',
      scope: invocation.scope,
      actorId: 'operator',
      issuedAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
    );
    final auditRejected =
        await BoundedReconciliationService(
          store: failedRepairs,
          source: _StaticSource(staleCandidates),
          executor: executor,
          audit: _FailingRepairAudit(),
          clock: () => invocation.startedAt,
        ).runAdministrator(
          invocation: invocation,
          principal: principal,
          now: invocation.startedAt,
          perTenantCap: 5,
          globalCap: 5,
        );
    expect(auditRejected.repairsFailed, 1);
    final beforeRepair = await schedules.readWork('org', key.workId);
    expect(beforeRepair?.status, ScheduledEvaluationWorkStatus.haltApplying);
    expect(beforeRepair?.workVersion, 4);
    final result =
        await BoundedReconciliationService(
          store: repairs,
          source: _StaticSource(staleCandidates),
          executor: executor,
          audit: ControlPlaneReconciliationAuditSink(control),
          clock: () => invocation.startedAt,
        ).runAdministrator(
          invocation: invocation,
          principal: principal,
          now: invocation.startedAt,
          perTenantCap: 5,
          globalCap: 5,
        );
    expect(result.repairsApplied, 1);
    final updated = await schedules.readWork('org', key.workId);
    expect(updated?.status, ScheduledEvaluationWorkStatus.stale);
    expect(updated?.automaticHaltIntent, isNull);
    expect(updated?.workVersion, 5);
    expect(await control.readAuditChain(), isNotEmpty);
  });

  test(
    'retry exhaustion uses the existing permanent-failure lease CAS',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-concrete-retry- exhausted-'.replaceAll(' ', ''),
      );
      final p3e = FileP3ePersistenceStore(Directory('${root.path}/p3e'));
      final schedules = FileP3e5ScheduleStore(
        Directory('${root.path}/schedule'),
        clock: () => now,
      );
      final repairs = FileReconciliationStore(
        Directory('${root.path}/reconciliation'),
      );
      addTearDown(() => root.delete(recursive: true));
      await p3e.initialize();
      await schedules.initialize();
      await repairs.initialize();
      addTearDown(() async {
        await repairs.close();
        await schedules.close();
        await p3e.close();
      });
      final scheduleRevision = _scheduleRevision(now);
      await schedules.createSchedule(_schedule(now), scheduleRevision);
      final key = _key(scheduleRevision: scheduleRevision.scheduleRevisionId);
      final token = 'concrete-retry-token-012345678901234567890123';
      await schedules.putWork(
        _work(
          key: key,
          status: ScheduledEvaluationWorkStatus.evaluating,
          workVersion: 3,
          token: token,
          aggregateId: 'aggregate_retry',
          aggregateRevisionId: 'revision_retry',
          attemptCount: _retryPolicy.maximumAttempts,
          updatedAt: now,
        ),
      );
      final invocation = _invocation(now.add(const Duration(minutes: 1)));
      final source = AuthoritativeReconciliationCandidateSource(
        p3eStore: p3e,
        scheduleStore: schedules,
        retryPolicy: _retryPolicy,
      );
      final candidates = await source.discover(invocation);
      final retry = candidates.where(
        (candidate) =>
            candidate.finding.code == ReconciliationTaxonomyCode.retryExhausted,
      );
      expect(retry, hasLength(1));
      expect(
        retry.single.precondition?.action,
        ReconciliationRepairAction.markFailedPermanent,
      );
      final executor = AuthoritativeReconciliationRepairExecutor(
        p3eStore: p3e,
        scheduleStore: schedules,
        retryPolicy: _retryPolicy,
        leaseTokenProvider: (_) async => token,
      );
      final result = await BoundedReconciliationService(
        store: repairs,
        source: _StaticSource(retry.toList(growable: false)),
        executor: executor,
        audit: _MemoryAudit(),
        clock: () => invocation.startedAt,
      ).runStartup(invocation: invocation, perTenantCap: 5, globalCap: 5);
      expect(result.repairsApplied, 1);
      final updated = await schedules.readWork('org', key.workId);
      expect(updated?.status, ScheduledEvaluationWorkStatus.failedPermanent);
      expect(updated?.workVersion, 4);
    },
  );

  test('existing halt application completion reuses the fenced CAS after a lost response', () async {
    final root = await Directory.systemTemp.createTemp(
      'hyfens-concrete-completion-',
    );
    final p3eRoot = Directory('${root.path}/p3e');
    final scheduleRoot = Directory('${root.path}/schedule');
    final controlRoot = Directory('${root.path}/control');
    addTearDown(() => root.delete(recursive: true));
    final p3e = FileP3ePersistenceStore(p3eRoot);
    final schedules = FileP3e5ScheduleStore(
      scheduleRoot,
      clock: () => now,
      automaticHaltCompletionFailure: (point) {
        if (point == P3e5AutomaticHaltCompletionFailurePoint.afterCommit) {
          throw const StorageUnavailable('completion response lost');
        }
      },
    );
    final control = FileControlPlaneStore(controlRoot);
    await p3e.initialize();
    await schedules.initialize();
    await control.initialize();
    addTearDown(() async {
      await control.close();
      await schedules.close();
      await p3e.close();
    });
    final evidence = _evidence();
    await p3e.putAggregateRevision(evidence.aggregateRecord, evidence.revision);
    await p3e.putEvaluation(evidence.evaluation);
    await p3e.putDecision(evidence.decision);
    final schedule = _schedule(now, logicalKeyVersion: 2);
    final scheduleRevision = _scheduleRevision(now, logicalKeyVersion: 2);
    await schedules.createSchedule(schedule, scheduleRevision);
    final target = RolloutTarget(
      organizationId: 'org',
      applicationId: 'app',
      environmentId: 'env',
      platformId: 'android',
      releaseId: 'release',
      runtimeReleaseId: 'runtime-release',
      patchId: 'patch',
      runtimePatchId: 'runtime-patch',
      artifactId: 'artifact',
      sha256: _digest,
      sequence: 1,
    );
    final targetDigest = sha256Digest(
      utf8.encode(canonicalJson(target.toJson())),
    );
    await control.createJson(
      'rollouts',
      'rollout',
      RolloutRecord(
        id: 'rollout',
        organizationId: 'org',
        currentRevision: 2,
        state: RolloutState.halted,
        createdAt: now,
      ).toJson(),
    );
    await control.createJson(
      'rollout_revisions',
      'halted_revision_concrete',
      RolloutRevision(
        id: 'halted_revision_concrete',
        rolloutId: 'rollout',
        organizationId: 'org',
        revision: 2,
        previousRevision: 1,
        state: RolloutState.halted,
        target: target,
        policy: RolloutPolicy(
          cohortKind: RolloutCohortKind.percentage,
          percentageBasisPoints: 10000,
          salt: 'salt',
        ),
        actorId: 'actor',
        reason: 'P3E4 health halt decision decision_concrete: TEST VECTOR ONLY',
        pausedFromState: null,
        createdAt: now,
      ).toJson(),
    );
    final key = _key(
      logicalKeyVersion: 2,
      scheduleRevision: scheduleRevision.scheduleRevisionId,
      targetBindingDigest: targetDigest,
    );
    final token = 'completion-token-012345678901234567890123';
    final intent = AutomaticHaltIntent(
      workId: key.workId,
      attemptId: deriveAttemptId(key.workId, 1),
      evaluationId: evidence.evaluation.evaluationId,
      decisionId: evidence.decision.decisionId,
      scheduleRevisionId: key.scheduleRevisionId,
      automaticHaltPolicyVersion: 1,
      automaticHaltPolicyDigest: _digest,
      expectedRolloutRevision: 1,
      targetBindingDigest: key.targetBindingDigest,
      authorizedPrincipalId: 'principal_completion',
      authorizedAt: now,
    );
    final application = HealthHaltApplication(
      applicationId: 'halt_application_concrete',
      organizationId: 'org',
      decisionId: evidence.decision.decisionId,
      evaluationId: evidence.evaluation.evaluationId,
      aggregateRevisionId: evidence.revision.aggregateRevisionId,
      rolloutId: 'rollout',
      expectedRolloutRevision: 1,
      result: 'APPLIED',
      reason: 'TEST VECTOR ONLY',
      actorIdentity: intent.authorizedPrincipalId,
      idempotencyKey: key.haltIdempotencyKey,
      previousRolloutRevision: 1,
      resultingRolloutRevision: 2,
      resultingTransitionReference: 'halted_revision_concrete',
      createdAt: now,
    );
    await p3e.putHaltApplication(application);
    await schedules.putWork(
      _work(
        key: key,
        status: ScheduledEvaluationWorkStatus.haltApplying,
        workVersion: 4,
        token: token,
        aggregateId: evidence.aggregateRecord.aggregateId,
        aggregateRevisionId: evidence.revision.aggregateRevisionId,
        evaluationId: evidence.evaluation.evaluationId,
        decisionId: evidence.decision.decisionId,
        intent: intent,
        updatedAt: now,
      ),
    );
    final scope = ReconciliationScope(
      organizationId: 'org',
      applicationId: 'app',
      environmentId: 'env',
    );
    final finding = ReconciliationFinding.create(
      scope: scope,
      code: ReconciliationTaxonomyCode.workHaltApplicationLinkMissing,
      entityType: 'work',
      entityId: key.workId,
      sourceDigests: <String, String>{
        'work': sha256Digest(
          utf8.encode(
            canonicalJson(
              (await schedules.readWork('org', key.workId))!.toJson(),
            ),
          ),
        ),
        'halt_application': sha256Digest(
          utf8.encode(canonicalJson(application.toJson())),
        ),
      },
      observedVersions: const <String, int>{'work': 4},
      firstObservedAt: now,
      lastObservedAt: now,
      safeDetailCode: 'WORK_HALT_APPLICATION_LINK_RECOVERABLE',
    );
    final precondition = ReconciliationPrecondition(
      scope: scope,
      findingId: finding.findingId,
      entityId: key.workId,
      expectedWorkVersion: 4,
      expectedScheduleRevision: key.scheduleRevisionId,
      currentRolloutRevision: '1',
      sourceDigests: finding.sourceDigests,
      targetBinding: <String, String>{
        'work_id': key.workId,
        'halt_application_id': application.applicationId,
        'evaluation_id': application.evaluationId,
        'decision_id': application.decisionId,
        'resulting_transition_reference':
            application.resultingTransitionReference!,
      },
      taxonomyCode: finding.code,
      action: ReconciliationRepairAction.linkExistingHaltApplication,
    );
    final executor = AuthoritativeReconciliationRepairExecutor(
      p3eStore: p3e,
      scheduleStore: schedules,
      retryPolicy: _retryPolicy,
      controlStore: control,
      leaseTokenProvider: (_) async => token,
    );
    final result = await executor.execute(
      ReconciliationRepairContext(
        invocation: _invocation(now),
        finding: finding,
        precondition: precondition,
      ),
    );
    expect(result.result, ReconciliationRepairResult.replayed);
    expect(result.postconditionVerified, isTrue);
    final updated = await schedules.readWork('org', key.workId);
    expect(updated?.status, ScheduledEvaluationWorkStatus.completed);
    expect(updated?.haltApplicationId, application.applicationId);
    expect(updated?.workVersion, 5);
  });

  test(
    'real detector load preserves tenant isolation and fairness caps',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-concrete-fairness-',
      );
      final p3eRoot = Directory('${root.path}/p3e');
      final scheduleRoot = Directory('${root.path}/schedule');
      final repairRoot = Directory('${root.path}/reconciliation');
      addTearDown(() => root.delete(recursive: true));
      final p3e = FileP3ePersistenceStore(p3eRoot);
      final schedules = FileP3e5ScheduleStore(scheduleRoot, clock: () => now);
      final repairs = FileReconciliationStore(repairRoot);
      await p3e.initialize();
      await schedules.initialize();
      await repairs.initialize();
      addTearDown(() async {
        await repairs.close();
        await schedules.close();
        await p3e.close();
      });
      final tokens = <String, String>{};
      for (final applicationId in const <String>['app_a', 'app_b']) {
        final scheduleId = 'schedule_$applicationId';
        final revision1Id = '${scheduleId}_revision_1';
        final revision2Id = '${scheduleId}_revision_2';
        final schedule = _schedule(
          now,
          applicationId: applicationId,
          scheduleId: scheduleId,
          revisionId: revision1Id,
          logicalKeyVersion: 2,
        );
        final revision1 = _scheduleRevision(
          now,
          applicationId: applicationId,
          scheduleId: scheduleId,
          scheduleRevisionId: revision1Id,
          logicalKeyVersion: 2,
        );
        final revision2 = _scheduleRevision(
          now.add(const Duration(minutes: 1)),
          applicationId: applicationId,
          scheduleId: scheduleId,
          scheduleRevisionId: revision2Id,
          logicalKeyVersion: 2,
          generation: 2,
          supersedes: revision1Id,
        );
        await schedules.createSchedule(schedule, revision1);
        await schedules.reviseSchedule(
          schedule: schedule.withCurrentRevision(revision2Id),
          expectedCurrentRevisionId: revision1Id,
          revision: revision2,
        );
        final key = _key(
          applicationId: applicationId,
          scheduleId: scheduleId,
          scheduleRevision: revision1Id,
          logicalKeyVersion: 2,
        );
        final token = 'fairness-$applicationId-token-012345678901234567';
        tokens[applicationId] = token;
        final intent = AutomaticHaltIntent(
          workId: key.workId,
          attemptId: deriveAttemptId(key.workId, 1),
          evaluationId: 'evaluation_$applicationId',
          decisionId: 'decision_$applicationId',
          scheduleRevisionId: key.scheduleRevisionId,
          automaticHaltPolicyVersion: 1,
          automaticHaltPolicyDigest: _digest,
          expectedRolloutRevision: 1,
          targetBindingDigest: key.targetBindingDigest,
          authorizedPrincipalId: 'principal_$applicationId',
          authorizedAt: now,
        );
        await schedules.putWork(
          _work(
            key: key,
            status: ScheduledEvaluationWorkStatus.haltApplying,
            workVersion: 1,
            token: token,
            aggregateId: 'aggregate_$applicationId',
            aggregateRevisionId: 'revision_$applicationId',
            evaluationId: intent.evaluationId,
            decisionId: intent.decisionId,
            intent: intent,
            updatedAt: now,
          ),
        );
      }
      final source = AuthoritativeReconciliationCandidateSource(
        p3eStore: p3e,
        scheduleStore: schedules,
      );
      final narrow = await source.discover(
        _invocation(
          now.add(const Duration(minutes: 2)),
          applicationId: 'app_a',
        ),
      );
      expect(
        narrow.every(
          (candidate) => candidate.finding.scope.applicationId == 'app_a',
        ),
        isTrue,
      );
      final invocation = _invocation(
        now.add(const Duration(minutes: 2)),
        applicationId: null,
        environmentId: null,
      );
      final candidates = await source.discover(invocation);
      final stale = candidates
          .where(
            (candidate) =>
                candidate.finding.code ==
                ReconciliationTaxonomyCode.staleActiveWork,
          )
          .toList(growable: false);
      expect(stale, hasLength(2));
      final executor = AuthoritativeReconciliationRepairExecutor(
        p3eStore: p3e,
        scheduleStore: schedules,
        retryPolicy: _retryPolicy,
        leaseTokenProvider: (context) async =>
            tokens[context.finding.scope.applicationId],
      );
      final result = await BoundedReconciliationService(
        store: repairs,
        source: _StaticSource(stale),
        executor: executor,
        audit: _MemoryAudit(),
        clock: () => invocation.startedAt,
      ).runStartup(invocation: invocation, perTenantCap: 1, globalCap: 2);
      expect(result.repairsApplied, 2);
      expect(result.backlog, isFalse);
      for (final candidate in stale) {
        expect(
          (await schedules.readWork('org', candidate.finding.entityId))?.status,
          ScheduledEvaluationWorkStatus.stale,
        );
      }
    },
  );

  test('frozen taxonomy remains exact and unbound actions fail closed', () {
    expect(reconciliationTaxonomy, hasLength(19));
    expect(
      reconciliationTaxonomy.keys,
      containsAll(ReconciliationTaxonomyCode.values),
    );
    expect(
      reconciliationTaxonomy.keys.map((code) => code.wireName).toSet(),
      equals(<String>{
        'WORK_EVALUATION_LINK_MISSING',
        'WORK_DECISION_LINK_MISSING',
        'WORK_HALT_APPLICATION_LINK_MISSING',
        'HALT_APPLICATION_ROLLOUT_MISMATCH',
        'ROLLOUT_APPLICATION_REFERENCE_MISSING',
        'SCHEDULE_WORK_VERSION_MISMATCH',
        'WORK_LOGICAL_KEY_MISMATCH',
        'AUDIT_REFERENCE_MISSING',
        'AUDIT_CHAIN_INVALID',
        'EVALUATION_AGGREGATE_MISMATCH',
        'DECISION_EVALUATION_MISMATCH',
        'TARGET_BINDING_MISMATCH',
        'TENANT_SCOPE_MISMATCH',
        'UNKNOWN_VERSION',
        'ORPHAN_WORK',
        'ORPHAN_APPLICATION',
        'STALE_ACTIVE_WORK',
        'EXPIRED_LEASE',
        'RETRY_EXHAUSTED',
      }),
    );
    expect(
      reconciliationMetadataFor(
        ReconciliationTaxonomyCode.workDecisionLinkMissing,
      ).automaticAction,
      ReconciliationRepairAction.linkExistingDecision,
    );
    expect(
      reconciliationMetadataFor(ReconciliationTaxonomyCode.orphanWork)
          .repairability,
      ReconciliationRepairability.reportOnlyImmutableDivergence,
    );
    expect(
      reconciliationRepairBindingDispositions.keys.toSet(),
      equals(ReconciliationRepairAction.values.toSet()),
    );
    expect(
      reconciliationRepairBindingFor(
        ReconciliationRepairAction.linkExistingDecision,
      ),
      ReconciliationRepairBindingDisposition.modelUnreachable,
    );
    expect(
      reconciliationRepairBindingFor(
        ReconciliationRepairAction.completeWorkFromExistingApplication,
      ),
      ReconciliationRepairBindingDisposition.coveredByExistingOperation,
    );
    expect(
      reconciliationRepairBindingFor(
        ReconciliationRepairAction.rebuildDerivedProjection,
      ),
      ReconciliationRepairBindingDisposition.notApplicable,
    );
  });

  test(
    'non-executable action dispositions never reach a mutation seam',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-action-disposition-',
      );
      addTearDown(() => root.delete(recursive: true));
      final p3e = FileP3ePersistenceStore(Directory('${root.path}/p3e'));
      final schedules = FileP3e5ScheduleStore(
        Directory('${root.path}/schedule'),
      );
      final executor = AuthoritativeReconciliationRepairExecutor(
        p3eStore: p3e,
        scheduleStore: schedules,
        retryPolicy: _retryPolicy,
        leaseTokenProvider: (_) async => null,
      );
      final invocation = _invocation(now);
      final cases = <(ReconciliationRepairAction, ReconciliationTaxonomyCode)>[
        (
          ReconciliationRepairAction.linkExistingDecision,
          ReconciliationTaxonomyCode.workDecisionLinkMissing,
        ),
        (
          ReconciliationRepairAction.completeWorkFromExistingApplication,
          ReconciliationTaxonomyCode.staleActiveWork,
        ),
        (
          ReconciliationRepairAction.rebuildDerivedProjection,
          ReconciliationTaxonomyCode.workEvaluationLinkMissing,
        ),
        (
          ReconciliationRepairAction.reportOnly,
          ReconciliationTaxonomyCode.orphanWork,
        ),
      ];
      for (final (action, code) in cases) {
        final finding = ReconciliationFinding.create(
          scope: invocation.scope,
          code: code,
          entityType: 'work',
          entityId: 'entity-${action.wireName}',
          sourceDigests: const <String, String>{'work': _digest},
          observedVersions: const <String, int>{'work': 1},
          firstObservedAt: now,
          lastObservedAt: now,
          safeDetailCode: 'TEST_DISPOSITION',
        );
        final precondition = ReconciliationPrecondition(
          scope: finding.scope,
          findingId: finding.findingId,
          entityId: finding.entityId,
          expectedWorkVersion: 1,
          expectedScheduleRevision: 'schedule_revision_1',
          currentRolloutRevision: '1',
          sourceDigests: finding.sourceDigests,
          targetBinding: const <String, String>{'target': 'none'},
          taxonomyCode: finding.code,
          action: action,
        );
        final result = await executor.execute(
          ReconciliationRepairContext(
            invocation: invocation,
            finding: finding,
            precondition: precondition,
          ),
        );
        expect(result.result, ReconciliationRepairResult.failed);
        expect(
          result.safeErrorCode,
          action == ReconciliationRepairAction.reportOnly
              ? 'ACTION_REPORT_ONLY'
              : 'ACTION_NOT_EXECUTABLE',
        );
      }
    },
  );

  test('ScheduledEvaluationWork rejects partial evaluation/decision links', () {
    final partialKey = _key();
    expect(
      () => _work(
        key: partialKey,
        status: ScheduledEvaluationWorkStatus.evaluated,
        workVersion: 1,
        token: 'partial-link-token-012345678901234567890123',
        aggregateId: 'aggregate_partial',
        aggregateRevisionId: 'revision_partial',
        evaluationId: 'evaluation_partial',
        updatedAt: now,
      ),
      throwsA(isA<FormatException>()),
    );
    final encodedEvaluating = _work(
      key: partialKey,
      status: ScheduledEvaluationWorkStatus.evaluating,
      workVersion: 1,
      token: 'partial-link-token-012345678901234567890123',
      aggregateId: 'aggregate_partial',
      aggregateRevisionId: 'revision_partial',
      updatedAt: now,
    ).toJson();
    encodedEvaluating['status'] = 'EVALUATED';
    encodedEvaluating['evaluationId'] = 'evaluation_partial';
    expect(
      () => ScheduledEvaluationWork.fromJson(encodedEvaluating),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'concrete reconciliation adapters retain the P3A/P3E-4 boundary',
    () async {
      final source = await File('lib/src/reconciliation_adapters.dart')
          .readAsString();
      expect(source, isNot(contains("import 'service.dart'")));
      expect(
        source,
        isNot(contains("import 'p3e_auto_halt_application.dart'")),
      );
      expect(source, isNot(contains("import 'p3e_auto_halt_recovery.dart'")));
      expect(source, isNot(contains('commitRolloutTransition(')));
      expect(source, isNot(contains('AutomaticHaltApplicationService')));
    },
  );

  test('rollout, target-binding, and audit detectors read existing control-plane state', () async {
    final root = await Directory.systemTemp.createTemp(
      'hyfens-concrete-rollout-',
    );
    final p3eRoot = Directory('${root.path}/p3e');
    final controlRoot = Directory('${root.path}/control');
    addTearDown(() => root.delete(recursive: true));
    final p3e = FileP3ePersistenceStore(p3eRoot);
    final schedules = FileP3e5ScheduleStore(Directory('${root.path}/schedule'));
    final control = FileControlPlaneStore(controlRoot);
    await p3e.initialize();
    await schedules.initialize();
    await control.initialize();
    addTearDown(() async {
      await control.close();
      await schedules.close();
      await p3e.close();
    });
    final evidence = _evidence();
    await p3e.putAggregateRevision(evidence.aggregateRecord, evidence.revision);
    final evaluation = HealthEvaluation(
      evaluationId: evidence.evaluation.evaluationId,
      organizationId: evidence.evaluation.organizationId,
      aggregateRevisionId: evidence.evaluation.aggregateRevisionId,
      rolloutId: evidence.evaluation.rolloutId,
      rolloutRevision: evidence.evaluation.rolloutRevision,
      evaluationVersion: evidence.evaluation.evaluationVersion,
      policyVersion: evidence.evaluation.policyVersion,
      thresholdSetVersion: evidence.evaluation.thresholdSetVersion,
      windowPolicyVersion: evidence.evaluation.windowPolicyVersion,
      privacyPolicyVersion: evidence.evaluation.privacyPolicyVersion,
      aggregateInputDigest: evidence.evaluation.aggregateInputDigest,
      decision: evidence.evaluation.decision,
      reasonClass: evidence.evaluation.reasonClass,
      reasonCodes: evidence.evaluation.reasonCodes,
      coverageState: evidence.evaluation.coverageState,
      freshnessState: evidence.evaluation.freshnessState,
      sampleState: evidence.evaluation.sampleState,
      createdAt: evidence.evaluation.createdAt,
      auditReference: 'missing-audit-reference',
      targetBindingDigest: _digest,
    );
    final decision = RolloutDecisionRecord(
      decisionId: evidence.decision.decisionId,
      organizationId: evidence.decision.organizationId,
      rolloutId: evidence.decision.rolloutId,
      expectedRolloutRevision: evidence.decision.expectedRolloutRevision,
      evaluationId: evaluation.evaluationId,
      aggregateRevisionId: evaluation.aggregateRevisionId,
      decision: evaluation.decision,
      reason: evidence.decision.reason,
      actorIdentity: evidence.decision.actorIdentity,
      idempotencyKey: evidence.decision.idempotencyKey,
      createdAt: evidence.decision.createdAt,
    );
    await p3e.putEvaluation(evaluation);
    await p3e.putDecision(decision);
    final target = RolloutTarget(
      organizationId: 'org',
      applicationId: 'app',
      environmentId: 'env',
      platformId: 'android',
      releaseId: 'release',
      runtimeReleaseId: 'runtime-release',
      patchId: 'patch',
      runtimePatchId: 'runtime-patch',
      artifactId: 'artifact',
      sha256: _digest,
      sequence: 1,
    );
    final rolloutRevision = RolloutRevision(
      id: 'rollout_revision_1',
      rolloutId: 'rollout',
      organizationId: 'org',
      revision: 1,
      previousRevision: null,
      state: RolloutState.canary,
      target: target,
      policy: RolloutPolicy(
        cohortKind: RolloutCohortKind.percentage,
        percentageBasisPoints: 10000,
        salt: 'salt',
      ),
      actorId: 'actor',
      reason: 'TEST VECTOR ONLY',
      pausedFromState: null,
      createdAt: now,
    );
    await control.createJson(
      'rollouts',
      'rollout',
      RolloutRecord(
        id: 'rollout',
        organizationId: 'org',
        currentRevision: 1,
        state: RolloutState.canary,
        createdAt: now,
      ).toJson(),
    );
    await control.createJson(
      'rollout_revisions',
      rolloutRevision.id,
      rolloutRevision.toJson(),
    );
    await control.appendAudit('audit-concrete', <String, Object?>{
      'id': 'audit-concrete',
      'organizationId': 'org',
      'createdAt': now.toIso8601String(),
    });
    final chainFile = File(
      '${controlRoot.path}/audit_chain/audit-concrete.json',
    );
    final chain =
        jsonDecode(await chainFile.readAsString()) as Map<String, Object?>;
    chain['recordDigest'] = _digest;
    await chainFile.writeAsString('${canonicalJson(chain)}\n', flush: true);
    await File('${controlRoot.path}/rollouts/malformed.json')
        .writeAsString('{"id":"malformed","schemaVersion":99}\n', flush: true);

    final source = AuthoritativeReconciliationCandidateSource(
      p3eStore: p3e,
      scheduleStore: schedules,
      controlStore: control,
    );
    final candidates = await source.discover(_invocation(now));
    final codes = candidates.map((candidate) => candidate.finding.code).toSet();
    expect(codes, contains(ReconciliationTaxonomyCode.targetBindingMismatch));
    expect(codes, contains(ReconciliationTaxonomyCode.auditReferenceMissing));
    expect(codes, contains(ReconciliationTaxonomyCode.auditChainInvalid));
    expect(codes, contains(ReconciliationTaxonomyCode.unknownVersion));
    expect(
      candidates.where(
        (candidate) =>
            candidate.finding.repairability ==
            ReconciliationRepairability.reportOnlyImmutableDivergence,
      ),
      isNotEmpty,
    );
  });

  test(
    'two PostgreSQL reconcilers mutate one real work projection once',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final organizationId = 'org_$suffix';
      final scheduleId = 'schedule_$suffix';
      final revisionId = 'schedule_revision_${suffix}_1';
      final revision2Id = 'schedule_revision_${suffix}_2';
      final key = _key(
        organizationId: organizationId,
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
        scheduleId: scheduleId,
        scheduleRevision: revisionId,
        rolloutId: 'rollout_$suffix',
        logicalKeyVersion: 2,
      );
      final token = 'postgres-race-token-012345678901234567890123';
      final first = PostgresP3e5ScheduleStore(postgresUrl!);
      final second = PostgresP3e5ScheduleStore(postgresUrl);
      final p3e = PostgresP3ePersistenceStore(postgresUrl);
      final reconciliationA = PostgresReconciliationStore(postgresUrl);
      final reconciliationB = PostgresReconciliationStore(postgresUrl);
      await Future.wait(<Future<void>>[
        first.initialize(),
        second.initialize(),
        p3e.initialize(),
        reconciliationA.initialize(),
        reconciliationB.initialize(),
      ]);
      addTearDown(() async {
        await reconciliationA.close();
        await reconciliationB.close();
        await p3e.close();
        await first.close();
        await second.close();
      });
      final schedule = _schedule(
        now,
        organizationId: organizationId,
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
        scheduleId: scheduleId,
        revisionId: revisionId,
        rolloutId: 'rollout_$suffix',
        logicalKeyVersion: 2,
      );
      final revision1 = _scheduleRevision(
        now,
        organizationId: organizationId,
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
        scheduleId: scheduleId,
        scheduleRevisionId: revisionId,
        rolloutId: 'rollout_$suffix',
        logicalKeyVersion: 2,
      );
      final revision2 = _scheduleRevision(
        now.add(const Duration(minutes: 1)),
        organizationId: organizationId,
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
        scheduleId: scheduleId,
        scheduleRevisionId: revision2Id,
        rolloutId: 'rollout_$suffix',
        logicalKeyVersion: 2,
        generation: 2,
        supersedes: revisionId,
      );
      await first.createSchedule(schedule, revision1);
      await first.reviseSchedule(
        schedule: schedule.withCurrentRevision(revision2Id),
        expectedCurrentRevisionId: revisionId,
        revision: revision2,
      );
      final intent = AutomaticHaltIntent(
        workId: key.workId,
        attemptId: deriveAttemptId(key.workId, 1),
        evaluationId: 'evaluation_$suffix',
        decisionId: 'decision_$suffix',
        scheduleRevisionId: revisionId,
        automaticHaltPolicyVersion: 1,
        automaticHaltPolicyDigest: _digest,
        expectedRolloutRevision: key.rolloutRevision,
        targetBindingDigest: key.targetBindingDigest,
        authorizedPrincipalId: 'principal_$suffix',
        authorizedAt: now,
      );
      await first.putWork(
        _work(
          key: key,
          status: ScheduledEvaluationWorkStatus.haltApplying,
          workVersion: 4,
          token: token,
          aggregateId: 'aggregate_$suffix',
          aggregateRevisionId: 'revision_$suffix',
          evaluationId: intent.evaluationId,
          decisionId: intent.decisionId,
          intent: intent,
          updatedAt: now,
        ),
      );
      final invocation = _invocation(
        now.add(const Duration(minutes: 2)),
        organizationId: organizationId,
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
      );
      final source = AuthoritativeReconciliationCandidateSource(
        p3eStore: p3e,
        scheduleStore: first,
      );
      final candidates = await source.discover(invocation);
      final stale = candidates
          .where(
            (candidate) =>
                candidate.finding.code ==
                ReconciliationTaxonomyCode.staleActiveWork,
          )
          .toList(growable: false);
      expect(stale, hasLength(1));
      final executorA = AuthoritativeReconciliationRepairExecutor(
        p3eStore: p3e,
        scheduleStore: first,
        retryPolicy: _retryPolicy,
        leaseTokenProvider: (_) async => token,
      );
      final executorB = AuthoritativeReconciliationRepairExecutor(
        p3eStore: p3e,
        scheduleStore: second,
        retryPolicy: _retryPolicy,
        leaseTokenProvider: (_) async => token,
      );
      final results = await Future.wait(<Future<ReconciliationRunResult>>[
        BoundedReconciliationService(
          store: reconciliationA,
          source: _StaticSource(stale),
          executor: executorA,
          audit: _MemoryAudit(),
          clock: () => invocation.startedAt,
        ).runStartup(invocation: invocation, perTenantCap: 5, globalCap: 5),
        BoundedReconciliationService(
          store: reconciliationB,
          source: _StaticSource(stale),
          executor: executorB,
          audit: _MemoryAudit(),
          clock: () => invocation.startedAt,
        ).runStartup(invocation: invocation, perTenantCap: 5, globalCap: 5),
      ]);
      expect(results, hasLength(2));
      expect(
        results.map((result) => result.repairsApplied).reduce((a, b) => a + b),
        1,
      );
      final updated = await first.readWork(organizationId, key.workId);
      expect(updated?.status, ScheduledEvaluationWorkStatus.stale);
      expect(updated?.workVersion, 5);
      expect(
        await reconciliationA.listRepairAttempts(invocation.scope),
        hasLength(1),
      );
      expect(
        await reconciliationB.listRepairAttempts(invocation.scope),
        hasLength(1),
      );
      final staleReplay = await executorA.execute(
        ReconciliationRepairContext(
          invocation: invocation,
          finding: stale.single.finding,
          precondition: stale.single.precondition!,
        ),
      );
      expect(staleReplay.result, ReconciliationRepairResult.conflict);
      expect(
        (await first.readWork(organizationId, key.workId))?.workVersion,
        5,
      );
    },
    skip: postgresUrl == null || postgresUrl.isEmpty
        ? 'PostgreSQL concrete race requires HYFENS_TEST_POSTGRES_URL'
        : false,
  );

  test(
    'PostgreSQL malformed reconciliation rows fail closed before repair',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final scope = ReconciliationScope(
        organizationId: 'org_$suffix',
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
      );
      final store = PostgresReconciliationStore(postgresUrl!);
      final pool = Pool.withUrl(postgresUrl);
      await store.initialize();
      addTearDown(() async {
        await store.close();
        await pool.close();
      });
      final unknown = _reconciliationFinding(scope, 'unknown_$suffix');
      await store.putFinding(unknown);
      await _updateReconciliationRow(
        pool,
        table: 'control_plane_reconciliation_findings',
        idColumn: 'finding_id',
        scope: scope,
        id: unknown.findingId,
        body: <String, Object?>{'schemaVersion': 99},
        digest: _digest,
      );
      await expectLater(
        store.readFinding(scope, unknown.findingId),
        throwsA(isA<FormatException>()),
      );

      final invalid = _reconciliationFinding(scope, 'invalid_$suffix');
      await store.putFinding(invalid);
      await _updateReconciliationRow(
        pool,
        table: 'control_plane_reconciliation_findings',
        idColumn: 'finding_id',
        scope: scope,
        id: invalid.findingId,
        body: <String, Object?>{'schemaVersion': 1},
        digest: _digest,
      );
      await expectLater(
        store.readFinding(scope, invalid.findingId),
        throwsA(isA<FormatException>()),
      );

      final scopeMismatch = _reconciliationFinding(scope, 'scope_$suffix');
      await store.putFinding(scopeMismatch);
      final mismatchedBody = <String, Object?>{
        ...scopeMismatch.toJson(),
        'scope': <String, Object?>{
          'organizationId': 'org_other_$suffix',
          'applicationId': scope.applicationId,
          'environmentId': scope.environmentId,
        },
      };
      await _updateReconciliationRow(
        pool,
        table: 'control_plane_reconciliation_findings',
        idColumn: 'finding_id',
        scope: scope,
        id: scopeMismatch.findingId,
        body: mismatchedBody,
      );
      await expectLater(
        store.readFinding(scope, scopeMismatch.findingId),
        throwsA(isA<FormatException>()),
      );

      final digestMismatch = _reconciliationFinding(scope, 'digest_$suffix');
      await store.putFinding(digestMismatch);
      await _updateReconciliationRow(
        pool,
        table: 'control_plane_reconciliation_findings',
        idColumn: 'finding_id',
        scope: scope,
        id: digestMismatch.findingId,
        body: <String, Object?>{
          ...digestMismatch.toJson(),
          'safeDetailCode': 'CHANGED_AFTER_WRITE',
        },
        digest: _digest,
      );
      await expectLater(
        store.readFinding(scope, digestMismatch.findingId),
        throwsA(isA<FormatException>()),
      );

      final repairFinding = _reconciliationFinding(scope, 'repair_$suffix');
      await store.putFinding(repairFinding);
      final repairPrecondition = ReconciliationPrecondition(
        scope: scope,
        findingId: repairFinding.findingId,
        entityId: repairFinding.entityId,
        expectedWorkVersion: 1,
        expectedScheduleRevision: 'schedule_revision_1',
        currentRolloutRevision: '1',
        sourceDigests: repairFinding.sourceDigests,
        targetBinding: const <String, String>{'work_id': 'work_1'},
        taxonomyCode: repairFinding.code,
        action: ReconciliationRepairAction.linkExistingEvaluation,
      );
      final attempt = ReconciliationRepairAttempt.create(
        finding: repairFinding,
        precondition: repairPrecondition,
        actorId: 'operator',
        result: ReconciliationRepairResult.applied,
        createdAt: now,
      );
      await store.putRepairAttempt(attempt);
      final conflicting = ReconciliationRepairAttempt.create(
        finding: repairFinding,
        precondition: repairPrecondition,
        actorId: 'operator',
        result: ReconciliationRepairResult.failed,
        safeErrorCode: 'CONFLICTING_BODY',
        createdAt: now,
      );
      await expectLater(
        store.putRepairAttempt(conflicting),
        throwsA(isA<StorageConflict>()),
      );

      final lifecycle = ReconciliationFindingLifecycle(
        scope: scope,
        findingId: repairFinding.findingId,
        status: ReconciliationFindingStatus.open,
        version: 1,
        latestRepairId: null,
        updatedAt: now,
      );
      await store.updateFindingLifecycle(
        lifecycle: lifecycle,
        expectedVersion: 0,
      );
      await _updateReconciliationRow(
        pool,
        table: 'control_plane_reconciliation_lifecycle',
        idColumn: 'finding_id',
        scope: scope,
        id: repairFinding.findingId,
        body: <String, Object?>{...lifecycle.toJson(), 'version': -1},
        hasDigest: false,
      );
      await expectLater(
        store.readFindingLifecycle(scope, repairFinding.findingId),
        throwsA(isA<FormatException>()),
      );

      final cursor = ReconciliationCursor(
        scope: scope,
        position: repairFinding.findingId,
        oldestUnresolvedAge: Duration.zero,
        perTenantCap: 1,
        globalCap: 1,
      );
      await store.saveCursor(
        cursor: ReconciliationCursorState(
          scope: scope,
          cursor: cursor,
          version: 1,
          updatedAt: now,
        ),
        expectedVersion: 0,
      );
      final cursorState = ReconciliationCursorState(
        scope: scope,
        cursor: cursor,
        version: 1,
        updatedAt: now,
      );
      await _updateReconciliationRow(
        pool,
        table: 'control_plane_reconciliation_cursors',
        idColumn: 'scope_digest',
        scope: scope,
        id: sha256Digest(utf8.encode(scope.canonicalSerialization)),
        body: <String, Object?>{...cursorState.toJson(), 'version': -1},
        hasDigest: false,
      );
      await expectLater(
        store.readCursor(scope),
        throwsA(isA<FormatException>()),
      );
    },
    skip: postgresUrl == null || postgresUrl.isEmpty
        ? 'PostgreSQL malformed-row test requires HYFENS_TEST_POSTGRES_URL'
        : false,
  );

  test(
    'PostgreSQL disconnects recover append-only, audit, lifecycle, and cursor state',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final url = postgresUrl!;
      final scope = ReconciliationScope(
        organizationId: 'disconnect_org_$suffix',
        applicationId: 'disconnect_app_$suffix',
        environmentId: 'disconnect_env_$suffix',
      );
      PostgresDisconnectInjector once(PostgresDisconnectPoint point) {
        var used = false;
        return (candidate) {
          if (!used && candidate == point) {
            used = true;
            return true;
          }
          return false;
        };
      }

      final finding = _reconciliationFinding(scope, 'finding_$suffix');
      final losingFinding = PostgresReconciliationStore(
        url,
        disconnectInjector: once(PostgresDisconnectPoint.findingCommitAfter),
      );
      await losingFinding.initialize();
      await expectLater(
        losingFinding.putFinding(finding),
        throwsA(isA<StorageUnavailable>()),
      );
      await losingFinding.close();
      final findingRecovery = PostgresReconciliationStore(url);
      await findingRecovery.initialize();
      addTearDown(findingRecovery.close);
      expect(
        await findingRecovery.readFinding(scope, finding.findingId),
        isNotNull,
      );

      final findingBefore = _reconciliationFinding(
        scope,
        'finding-before-$suffix',
      );
      final losingFindingBefore = PostgresReconciliationStore(
        url,
        disconnectInjector: once(PostgresDisconnectPoint.findingCommitBefore),
      );
      await losingFindingBefore.initialize();
      await expectLater(
        losingFindingBefore.putFinding(findingBefore),
        throwsA(isA<StorageUnavailable>()),
      );
      await losingFindingBefore.close();
      expect(
        await findingRecovery.readFinding(scope, findingBefore.findingId),
        isNull,
      );

      final precondition = ReconciliationPrecondition(
        scope: scope,
        findingId: finding.findingId,
        entityId: finding.entityId,
        expectedWorkVersion: 1,
        expectedScheduleRevision: 'schedule_revision_1',
        currentRolloutRevision: '1',
        sourceDigests: finding.sourceDigests,
        targetBinding: const <String, String>{'work_id': 'work_disconnect'},
        taxonomyCode: finding.code,
        action: ReconciliationRepairAction.linkExistingEvaluation,
      );
      final attempt = ReconciliationRepairAttempt.create(
        finding: finding,
        precondition: precondition,
        actorId: 'disconnect-test',
        result: ReconciliationRepairResult.applied,
        createdAt: now,
      );
      final losingAttempt = PostgresReconciliationStore(
        url,
        disconnectInjector: once(
          PostgresDisconnectPoint.repairAttemptCommitAfter,
        ),
      );
      await losingAttempt.initialize();
      await expectLater(
        losingAttempt.putRepairAttempt(attempt),
        throwsA(isA<StorageUnavailable>()),
      );
      await losingAttempt.close();
      final attemptRecovery = PostgresReconciliationStore(url);
      await attemptRecovery.initialize();
      addTearDown(attemptRecovery.close);
      expect(
        await attemptRecovery.readRepairAttempt(scope, attempt.repairId),
        isNotNull,
      );
      expect(
        await attemptRecovery.putRepairAttempt(attempt),
        ReconciliationRecordWriteResult.replayed,
      );

      final findingBeforeAttempt = _reconciliationFinding(
        scope,
        'finding-before-attempt-$suffix',
      );
      await findingRecovery.putFinding(findingBeforeAttempt);
      final preconditionBeforeAttempt = ReconciliationPrecondition(
        scope: scope,
        findingId: findingBeforeAttempt.findingId,
        entityId: findingBeforeAttempt.entityId,
        expectedWorkVersion: 1,
        expectedScheduleRevision: 'schedule_revision_1',
        currentRolloutRevision: '1',
        sourceDigests: findingBeforeAttempt.sourceDigests,
        targetBinding: const <String, String>{'work_id': 'work_before_attempt'},
        taxonomyCode: findingBeforeAttempt.code,
        action: ReconciliationRepairAction.linkExistingEvaluation,
      );
      final attemptBefore = ReconciliationRepairAttempt.create(
        finding: findingBeforeAttempt,
        precondition: preconditionBeforeAttempt,
        actorId: 'disconnect-test',
        result: ReconciliationRepairResult.applied,
        createdAt: now,
      );
      final losingAttemptBefore = PostgresReconciliationStore(
        url,
        disconnectInjector: once(
          PostgresDisconnectPoint.repairAttemptCommitBefore,
        ),
      );
      await losingAttemptBefore.initialize();
      await expectLater(
        losingAttemptBefore.putRepairAttempt(attemptBefore),
        throwsA(isA<StorageUnavailable>()),
      );
      await losingAttemptBefore.close();
      expect(
        await findingRecovery.readRepairAttempt(scope, attemptBefore.repairId),
        isNull,
      );

      final lifecycle = ReconciliationFindingLifecycle(
        scope: scope,
        findingId: finding.findingId,
        status: ReconciliationFindingStatus.open,
        version: 1,
        latestRepairId: null,
        updatedAt: now,
      );
      final losingLifecycle = PostgresReconciliationStore(
        url,
        disconnectInjector: once(PostgresDisconnectPoint.lifecycleCommitAfter),
      );
      await losingLifecycle.initialize();
      await expectLater(
        losingLifecycle.updateFindingLifecycle(
          lifecycle: lifecycle,
          expectedVersion: 0,
        ),
        throwsA(isA<StorageUnavailable>()),
      );
      await losingLifecycle.close();
      final lifecycleRecovery = PostgresReconciliationStore(url);
      await lifecycleRecovery.initialize();
      addTearDown(lifecycleRecovery.close);
      expect(
        (await lifecycleRecovery.readFindingLifecycle(
          scope,
          finding.findingId,
        ))?.version,
        1,
      );

      final findingBeforeLifecycle = _reconciliationFinding(
        scope,
        'finding-before-lifecycle-$suffix',
      );
      await findingRecovery.putFinding(findingBeforeLifecycle);
      final losingLifecycleBefore = PostgresReconciliationStore(
        url,
        disconnectInjector: once(PostgresDisconnectPoint.lifecycleCommitBefore),
      );
      await losingLifecycleBefore.initialize();
      await expectLater(
        losingLifecycleBefore.updateFindingLifecycle(
          lifecycle: ReconciliationFindingLifecycle(
            scope: scope,
            findingId: findingBeforeLifecycle.findingId,
            status: ReconciliationFindingStatus.open,
            version: 1,
            latestRepairId: null,
            updatedAt: now,
          ),
          expectedVersion: 0,
        ),
        throwsA(isA<StorageUnavailable>()),
      );
      await losingLifecycleBefore.close();
      expect(
        await findingRecovery.readFindingLifecycle(
          scope,
          findingBeforeLifecycle.findingId,
        ),
        isNull,
      );

      final cursor = ReconciliationCursor(
        scope: scope,
        position: finding.findingId,
        oldestUnresolvedAge: Duration.zero,
        perTenantCap: 1,
        globalCap: 1,
      );
      final cursorState = ReconciliationCursorState(
        scope: scope,
        cursor: cursor,
        version: 1,
        updatedAt: now,
      );
      final losingCursor = PostgresReconciliationStore(
        url,
        disconnectInjector: once(PostgresDisconnectPoint.cursorCommitAfter),
      );
      await losingCursor.initialize();
      await expectLater(
        losingCursor.saveCursor(cursor: cursorState, expectedVersion: 0),
        throwsA(isA<StorageUnavailable>()),
      );
      await losingCursor.close();
      final cursorRecovery = PostgresReconciliationStore(url);
      await cursorRecovery.initialize();
      addTearDown(cursorRecovery.close);
      expect((await cursorRecovery.readCursor(scope))?.version, 1);

      final cursorBeforeScope = ReconciliationScope(
        organizationId: '${scope.organizationId}_before_cursor',
        applicationId: scope.applicationId,
        environmentId: scope.environmentId,
      );
      final cursorBefore = ReconciliationCursor(
        scope: cursorBeforeScope,
        position: 'before-cursor',
        oldestUnresolvedAge: Duration.zero,
        perTenantCap: 1,
        globalCap: 1,
      );
      final losingCursorBefore = PostgresReconciliationStore(
        url,
        disconnectInjector: once(PostgresDisconnectPoint.cursorCommitBefore),
      );
      await losingCursorBefore.initialize();
      await expectLater(
        losingCursorBefore.saveCursor(
          cursor: ReconciliationCursorState(
            scope: cursorBeforeScope,
            cursor: cursorBefore,
            version: 1,
            updatedAt: now,
          ),
          expectedVersion: 0,
        ),
        throwsA(isA<StorageUnavailable>()),
      );
      await losingCursorBefore.close();
      expect(await cursorRecovery.readCursor(cursorBeforeScope), isNull);

      final auditId = 'audit_disconnect_$suffix';
      final auditBody = <String, Object?>{
        'id': auditId,
        'organizationId': scope.organizationId,
        'createdAt': now.toIso8601String(),
      };
      final losingAuditBefore = PostgresControlPlaneStore(
        url,
        disconnectInjector: once(PostgresDisconnectPoint.auditCommitBefore),
      );
      await losingAuditBefore.initialize();
      await expectLater(
        losingAuditBefore.appendAudit(auditId, auditBody),
        throwsA(isA<StorageUnavailable>()),
      );
      await losingAuditBefore.close();

      final losingAuditAfter = PostgresControlPlaneStore(
        url,
        disconnectInjector: once(PostgresDisconnectPoint.auditCommitAfter),
      );
      await losingAuditAfter.initialize();
      await expectLater(
        losingAuditAfter.appendAudit(auditId, auditBody),
        throwsA(isA<StorageUnavailable>()),
      );
      await losingAuditAfter.close();
      final auditRecovery = PostgresControlPlaneStore(url);
      await auditRecovery.initialize();
      addTearDown(auditRecovery.close);
      await auditRecovery.appendAudit(auditId, auditBody);
      final chain = await auditRecovery.readAuditChain();
      expect(chain.where((item) => item['auditId'] == auditId), hasLength(1));

      final losingAuditRead = PostgresControlPlaneStore(
        url,
        disconnectInjector: once(PostgresDisconnectPoint.auditReadBefore),
      );
      await losingAuditRead.initialize();
      await expectLater(
        losingAuditRead.readAuditChain(),
        throwsA(isA<StorageUnavailable>()),
      );
      await losingAuditRead.close();
      final verifiedChain = await auditRecovery.readAuditChain();
      expect(
        verifiedChain.where((item) => item['auditId'] == auditId),
        hasLength(1),
      );

      final auditFinding = _reconciliationFinding(
        scope,
        'audit-finding-$suffix',
      );
      final auditPrecondition = ReconciliationPrecondition(
        scope: scope,
        findingId: auditFinding.findingId,
        entityId: auditFinding.entityId,
        expectedWorkVersion: 1,
        expectedScheduleRevision: 'schedule_revision_1',
        currentRolloutRevision: '1',
        sourceDigests: auditFinding.sourceDigests,
        targetBinding: const <String, String>{'work_id': 'audit-work'},
        taxonomyCode: auditFinding.code,
        action: ReconciliationRepairAction.linkExistingEvaluation,
      );
      await findingRecovery.putFinding(auditFinding);
      var auditBeforeCalls = 0;
      final auditFault = PostgresControlPlaneStore(
        url,
        disconnectInjector: (point) {
          if (point != PostgresDisconnectPoint.auditCommitBefore) {
            return false;
          }
          auditBeforeCalls++;
          return auditBeforeCalls == 2;
        },
      );
      await auditFault.initialize();
      final auditInvocation = _invocation(
        now,
        organizationId: scope.organizationId,
        applicationId: scope.applicationId,
        environmentId: scope.environmentId,
      );
      final auditPrincipal = ReconciliationPrincipal(
        principalId: auditInvocation.principalId,
        scope: auditInvocation.scope,
        actorId: auditInvocation.actorId,
        issuedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      final countingExecutor = _CountingExecutor();
      final auditResult =
          await BoundedReconciliationService(
            store: findingRecovery,
            source: _StaticSource(<ReconciliationCandidate>[
              ReconciliationCandidate(
                finding: auditFinding,
                precondition: auditPrecondition,
              ),
            ]),
            executor: countingExecutor,
            audit: ControlPlaneReconciliationAuditSink(auditFault),
            clock: () => now,
          ).runAdministrator(
            invocation: auditInvocation,
            principal: auditPrincipal,
            now: now,
            perTenantCap: 1,
            globalCap: 1,
          );
      expect(auditResult.repairsFailed, 1);
      expect(countingExecutor.calls, 0);
      expect(
        (await findingRecovery.readRepairAttempt(
          scope,
          ReconciliationRepairAttempt.deriveRepairId(
            auditFinding.findingId,
            auditPrecondition.action,
          ),
        ))?.safeErrorCode,
        'AUDIT_UNAVAILABLE',
      );
      await auditFault.close();
    },
    skip: postgresUrl == null || postgresUrl.isEmpty
        ? 'PostgreSQL disconnect evidence requires HYFENS_TEST_POSTGRES_URL'
        : false,
  );

  test(
    'PostgreSQL projection disconnect converges through explicit reconnect',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final url = postgresUrl!;
      final organizationId = 'projection_org_$suffix';
      final applicationId = 'projection_app_$suffix';
      final environmentId = 'projection_env_$suffix';
      final scheduleId = 'projection_schedule_$suffix';
      final revisionId = 'projection_revision_$suffix';
      final key = _key(
        organizationId: organizationId,
        applicationId: applicationId,
        environmentId: environmentId,
        scheduleId: scheduleId,
        scheduleRevision: revisionId,
        rolloutId: 'projection_rollout_$suffix',
        logicalKeyVersion: 2,
      );
      final token = 'projection-token-012345678901234567890123';
      final setup = PostgresP3e5ScheduleStore(url);
      await setup.initialize();
      addTearDown(setup.close);
      await setup.createSchedule(
        _schedule(
          now,
          organizationId: organizationId,
          applicationId: applicationId,
          environmentId: environmentId,
          scheduleId: scheduleId,
          revisionId: revisionId,
          rolloutId: key.rolloutId,
          logicalKeyVersion: 2,
        ),
        _scheduleRevision(
          now,
          organizationId: organizationId,
          applicationId: applicationId,
          environmentId: environmentId,
          scheduleId: scheduleId,
          scheduleRevisionId: revisionId,
          rolloutId: key.rolloutId,
          logicalKeyVersion: 2,
        ),
      );
      final intent = AutomaticHaltIntent(
        workId: key.workId,
        attemptId: deriveAttemptId(key.workId, 1),
        evaluationId: 'projection_evaluation_$suffix',
        decisionId: 'projection_decision_$suffix',
        scheduleRevisionId: revisionId,
        automaticHaltPolicyVersion: 1,
        automaticHaltPolicyDigest: _digest,
        expectedRolloutRevision: key.rolloutRevision,
        targetBindingDigest: key.targetBindingDigest,
        authorizedPrincipalId: 'projection-principal-$suffix',
        authorizedAt: now,
      );
      await setup.putWork(
        _work(
          key: key,
          status: ScheduledEvaluationWorkStatus.haltApplying,
          workVersion: 4,
          token: token,
          aggregateId: 'projection_aggregate_$suffix',
          aggregateRevisionId: 'projection_aggregate_revision_$suffix',
          evaluationId: intent.evaluationId,
          decisionId: intent.decisionId,
          intent: intent,
          updatedAt: now,
        ),
      );
      final lease = P3e5LeaseMutation(
        scope: P3e5ClaimScope(
          organizationId: organizationId,
          applicationId: applicationId,
          environmentId: environmentId,
        ),
        workId: key.workId,
        expectedWorkVersion: 4,
        leaseOwner: 'owner',
        rawLeaseToken: token,
      );
      PostgresDisconnectInjector once(PostgresDisconnectPoint point) {
        var used = false;
        return (candidate) {
          if (!used && candidate == point) {
            used = true;
            return true;
          }
          return false;
        };
      }

      final before = PostgresP3e5ScheduleStore(
        url,
        disconnectInjector: once(
          PostgresDisconnectPoint.projectionCommitBefore,
        ),
      );
      await before.initialize();
      await expectLater(
        before.markAutomaticHaltStale(lease),
        throwsA(isA<StorageUnavailable>()),
      );
      await before.close();
      expect(
        (await setup.readWork(organizationId, key.workId))?.workVersion,
        4,
      );

      final after = PostgresP3e5ScheduleStore(
        url,
        disconnectInjector: once(PostgresDisconnectPoint.projectionCommitAfter),
      );
      await after.initialize();
      await expectLater(
        after.markAutomaticHaltStale(lease),
        throwsA(isA<StorageUnavailable>()),
      );
      await after.close();
      final recovered = PostgresP3e5ScheduleStore(url);
      await recovered.initialize();
      addTearDown(recovered.close);
      final committed = await recovered.readWork(organizationId, key.workId);
      expect(committed?.status, ScheduledEvaluationWorkStatus.stale);
      expect(committed?.workVersion, 5);
      await expectLater(
        recovered.markAutomaticHaltStale(lease),
        throwsA(isA<StorageConflict>()),
      );

      final postconditionRead = PostgresP3e5ScheduleStore(
        url,
        disconnectInjector: once(
          PostgresDisconnectPoint.postconditionReadBefore,
        ),
      );
      await postconditionRead.initialize();
      await expectLater(
        postconditionRead.readWork(organizationId, key.workId),
        throwsA(isA<StorageUnavailable>()),
      );
      await postconditionRead.close();
      expect(
        (await recovered.readWork(organizationId, key.workId))?.workVersion,
        5,
      );

      final otherOrganization = 'projection_other_org_$suffix';
      final otherKey = _key(
        organizationId: otherOrganization,
        applicationId: 'projection_other_app_$suffix',
        environmentId: 'projection_other_env_$suffix',
        scheduleId: 'projection_other_schedule_$suffix',
        scheduleRevision: 'projection_other_revision_$suffix',
        rolloutId: 'projection_other_rollout_$suffix',
        logicalKeyVersion: 2,
      );
      await setup.createSchedule(
        _schedule(
          now,
          organizationId: otherOrganization,
          applicationId: otherKey.applicationId,
          environmentId: otherKey.environmentId,
          scheduleId: otherKey.scheduleId,
          revisionId: otherKey.scheduleRevisionId,
          rolloutId: otherKey.rolloutId,
          logicalKeyVersion: 2,
        ),
        _scheduleRevision(
          now,
          organizationId: otherOrganization,
          applicationId: otherKey.applicationId,
          environmentId: otherKey.environmentId,
          scheduleId: otherKey.scheduleId,
          scheduleRevisionId: otherKey.scheduleRevisionId,
          rolloutId: otherKey.rolloutId,
          logicalKeyVersion: 2,
        ),
      );
      await setup.putWork(
        ScheduledEvaluationWork.pending(logicalKey: otherKey, serverNow: now),
      );
      expect(await recovered.listWork(otherOrganization), hasLength(1));
      expect(await recovered.listWork(organizationId), hasLength(1));

      final disconnectingReconciler = PostgresP3e5ScheduleStore(
        url,
        disconnectInjector: once(PostgresDisconnectPoint.projectionCommitAfter),
      );
      await disconnectingReconciler.initialize();
      final staleLease = P3e5LeaseMutation(
        scope: lease.scope,
        workId: lease.workId,
        expectedWorkVersion: 5,
        leaseOwner: lease.leaseOwner,
        rawLeaseToken: token,
      );
      await expectLater(
        disconnectingReconciler.markAutomaticHaltStale(staleLease),
        throwsA(isA<StorageConflict>()),
      );
      await disconnectingReconciler.close();
    },
    skip: postgresUrl == null || postgresUrl.isEmpty
        ? 'PostgreSQL projection disconnect evidence requires HYFENS_TEST_POSTGRES_URL'
        : false,
  );

  test(
    'PostgreSQL startup outage fails boundedly and later reconnect works',
    () async {
      final uri = Uri.parse(postgresUrl!);
      final outageUrl = uri
          .replace(
            port: uri.port + 10000,
            queryParameters: <String, String>{
              ...uri.queryParameters,
              'connect_timeout': '1',
            },
          )
          .toString();
      final unavailable = PostgresReconciliationStore(outageUrl);
      final stopwatch = Stopwatch()..start();
      await expectLater(
        unavailable.initialize().timeout(const Duration(seconds: 3)),
        throwsA(anything),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
      await unavailable.close();

      final recovered = PostgresReconciliationStore(postgresUrl);
      await recovered.initialize();
      await recovered.close();
    },
    skip: postgresUrl == null || postgresUrl.isEmpty
        ? 'PostgreSQL outage evidence requires HYFENS_TEST_POSTGRES_URL'
        : false,
  );
}

final P3e5RetryPolicy _retryPolicy = const P3e5RetryPolicy(
  version: 1,
  initialDelay: Duration(seconds: 1),
  maximumDelay: Duration(minutes: 1),
  maximumAttempts: 3,
  jitterMode: P3e5JitterMode.none,
  jitterBound: Duration.zero,
);

final class _MemoryAudit implements ReconciliationAuditSink {
  final List<ReconciliationAuditEvent> events = <ReconciliationAuditEvent>[];

  @override
  Future<void> append(ReconciliationAuditEvent event) async {
    events.add(event);
  }
}

final class _CountingExecutor implements ReconciliationRepairExecutor {
  int calls = 0;

  @override
  Future<ReconciliationRepairExecution> execute(
    ReconciliationRepairContext context,
  ) async {
    calls++;
    return const ReconciliationRepairExecution(
      result: ReconciliationRepairResult.applied,
      postconditionVerified: true,
    );
  }
}

final class _FailingRepairAudit implements ReconciliationAuditSink {
  @override
  Future<void> append(ReconciliationAuditEvent event) async {
    if (event.eventType == ReconciliationAuditEventType.repairRequested) {
      throw const StorageUnavailable('pre-repair audit unavailable');
    }
  }
}

final class _StaticSource implements ReconciliationCandidateSource {
  const _StaticSource(this.candidates);

  final List<ReconciliationCandidate> candidates;

  @override
  Future<List<ReconciliationCandidate>> discover(
    ReconciliationInvocation invocation,
  ) async => candidates;
}

ReconciliationPolicy _policy() => ReconciliationPolicy(
  policyVersion: 1,
  maximumRecordsScanned: 100,
  maximumTenantsScanned: 10,
  maximumLinkageDepth: 4,
  maximumFindings: 20,
  maximumRepairs: 20,
  maximumConcurrentRepairs: 2,
  maximumRetryAttempts: 3,
  lookbackHorizon: const Duration(hours: 1),
  maximumDiagnosticHistory: 5,
  maximumAuditLookupDepth: 5,
  fairnessPolicyVersion: 1,
);

ReconciliationInvocation _invocation(
  DateTime startedAt, {
  String organizationId = 'org',
  String? applicationId = 'app',
  String? environmentId = 'env',
}) => ReconciliationInvocation.create(
  scope: ReconciliationScope(
    organizationId: organizationId,
    applicationId: applicationId,
    environmentId: environmentId,
  ),
  actorId: 'operator',
  principalId: 'principal',
  storageMode: ReconciliationStorageMode.file,
  policy: _policy(),
  startedAt: startedAt,
);

ReconciliationFinding _reconciliationFinding(
  ReconciliationScope scope,
  String entityId,
) => ReconciliationFinding.create(
  scope: scope,
  code: ReconciliationTaxonomyCode.workEvaluationLinkMissing,
  entityType: 'work',
  entityId: entityId,
  sourceDigests: const <String, String>{'work': _digest},
  observedVersions: const <String, int>{'work': 1},
  firstObservedAt: DateTime.utc(2026, 8, 24, 12),
  lastObservedAt: DateTime.utc(2026, 8, 24, 12),
  safeDetailCode: 'LINK_MISSING',
);

Future<void> _updateReconciliationRow(
  Pool pool, {
  required String table,
  required String idColumn,
  required ReconciliationScope scope,
  required String id,
  required Map<String, Object?> body,
  String? digest,
  bool hasDigest = true,
}) async {
  final canonical = canonicalJson(body);
  final digestSql = hasDigest ? ', body_digest = @digest:text' : '';
  await pool.execute(
    Sql.named(
      'UPDATE $table SET body = @body:jsonb$digestSql '
      'WHERE organization_id = @organization:text '
      'AND $idColumn = @id:text',
    ),
    parameters: <String, Object?>{
      'body': body,
      if (hasDigest) 'digest': digest ?? sha256Digest(utf8.encode(canonical)),
      'organization': scope.organizationId,
      'id': id,
    },
  );
}

EvaluationSchedule _schedule(
  DateTime createdAt, {
  String organizationId = 'org',
  String applicationId = 'app',
  String environmentId = 'env',
  String scheduleId = 'schedule',
  String revisionId = 'schedule_revision_1',
  String rolloutId = 'rollout',
  int logicalKeyVersion = 1,
}) => EvaluationSchedule(
  scheduleId: scheduleId,
  organizationId: organizationId,
  applicationId: applicationId,
  environmentId: environmentId,
  rolloutId: rolloutId,
  currentScheduleRevision: revisionId,
  createdAt: createdAt,
  createdBy: 'operator',
);

EvaluationScheduleRevision _scheduleRevision(
  DateTime createdAt, {
  String organizationId = 'org',
  String applicationId = 'app',
  String environmentId = 'env',
  String scheduleId = 'schedule',
  String scheduleRevisionId = 'schedule_revision_1',
  String rolloutId = 'rollout',
  int logicalKeyVersion = 1,
  int generation = 1,
  String? supersedes,
}) => EvaluationScheduleRevision(
  scheduleRevisionId: scheduleRevisionId,
  scheduleId: scheduleId,
  scheduleGeneration: generation,
  organizationId: organizationId,
  applicationId: applicationId,
  environmentId: environmentId,
  rolloutId: rolloutId,
  logicalKeyVersion: logicalKeyVersion,
  scheduledEvaluationEnabled: true,
  automaticHaltEnabled: logicalKeyVersion == 2,
  readinessPhase: EvaluationReadinessPhase.sealed,
  automaticHaltPolicyId: logicalKeyVersion == 2 ? 'policy' : null,
  automaticHaltPolicyVersion: logicalKeyVersion == 2 ? 1 : null,
  automaticHaltPolicyDigest: logicalKeyVersion == 2 ? _digest : null,
  automaticHaltEligibleSource: logicalKeyVersion == 2
      ? AutomaticHaltEligibleSource.scheduledOnly
      : null,
  automaticHaltEligibleReadiness: logicalKeyVersion == 2
      ? AutomaticHaltEligibleReadiness.sealedOnly
      : null,
  automaticHaltEligibleReasonClass: logicalKeyVersion == 2
      ? AutomaticHaltEligibleReasonClass.patchSafetyOnly
      : null,
  triggerPolicyVersion: 1,
  schedulePolicyVersion: 1,
  evaluationPolicyVersion: 1,
  evaluationPolicyDigest: _digest,
  thresholdSetVersion: 1,
  thresholdSetDigest: _digest,
  aggregationVersion: 1,
  windowPolicyVersion: 1,
  privacyPolicyVersion: 1,
  retryPolicyReference: 'retry_v1',
  resourcePolicyReference: 'resource_v1',
  supersedesScheduleRevisionId: supersedes,
  createdAt: createdAt,
  createdBy: 'operator',
  reason: 'TEST VECTOR ONLY',
);

LogicalEvaluationKey _key({
  String organizationId = 'org',
  String applicationId = 'app',
  String environmentId = 'env',
  String platformId = 'android',
  String rolloutId = 'rollout',
  String scheduleId = 'schedule',
  String scheduleRevision = 'schedule_revision_1',
  int logicalKeyVersion = 1,
  String targetBindingDigest = _digest,
}) => LogicalEvaluationKey(
  logicalKeyVersion: logicalKeyVersion,
  organizationId: organizationId,
  applicationId: applicationId,
  environmentId: environmentId,
  platformId: platformId,
  rolloutId: rolloutId,
  rolloutRevision: 1,
  releaseId: 'release',
  patchId: 'patch',
  sequence: 1,
  targetBindingDigest: targetBindingDigest,
  windowId: 'window',
  readinessPhase: EvaluationReadinessPhase.sealed,
  observationSchemaVersion: 1,
  aggregationVersion: 1,
  aggregatePolicyDigest: _digest,
  evaluationPolicyVersion: 1,
  evaluationPolicyDigest: _digest,
  thresholdSetVersion: 1,
  thresholdSetDigest: _digest,
  windowPolicyVersion: 1,
  privacyPolicyVersion: 1,
  scheduleId: scheduleId,
  scheduleRevisionId: scheduleRevision,
  scheduleGeneration: 1,
  automaticHaltPolicyId: logicalKeyVersion == 2 ? 'policy' : null,
  automaticHaltPolicyVersion: logicalKeyVersion == 2 ? 1 : null,
  automaticHaltPolicyDigest: logicalKeyVersion == 2 ? _digest : null,
  automaticHaltEnabled: logicalKeyVersion == 2 ? true : null,
  automaticHaltEligibleSource: logicalKeyVersion == 2
      ? AutomaticHaltEligibleSource.scheduledOnly
      : null,
  automaticHaltEligibleReadiness: logicalKeyVersion == 2
      ? AutomaticHaltEligibleReadiness.sealedOnly
      : null,
  automaticHaltEligibleReasonClass: logicalKeyVersion == 2
      ? AutomaticHaltEligibleReasonClass.patchSafetyOnly
      : null,
);

ScheduledEvaluationWork _work({
  required LogicalEvaluationKey key,
  required ScheduledEvaluationWorkStatus status,
  required int workVersion,
  required String token,
  required String aggregateId,
  required String aggregateRevisionId,
  String? evaluationId,
  String? decisionId,
  AutomaticHaltIntent? intent,
  int attemptCount = 1,
  required DateTime updatedAt,
}) => ScheduledEvaluationWork(
  workId: key.workId,
  logicalKey: key,
  status: status,
  workVersion: workVersion,
  attemptCount: attemptCount,
  notBefore: updatedAt,
  leaseOwner: 'owner',
  leaseTokenDigest: sha256Digest(utf8.encode(token)),
  leaseAcquiredAt: updatedAt,
  leaseExpiresAt: updatedAt.add(const Duration(hours: 24)),
  createdAt: updatedAt,
  updatedAt: updatedAt,
  lastAttemptAt: updatedAt,
  lastErrorClass: null,
  lastErrorCode: null,
  aggregateId: aggregateId,
  aggregateRevisionId: aggregateRevisionId,
  evaluationId: evaluationId,
  decisionId: decisionId,
  haltApplicationId: null,
  automaticHaltIntent: intent,
);

final class _EvidenceFixture {
  const _EvidenceFixture({
    required this.aggregateRecord,
    required this.revision,
    required this.evaluation,
    required this.decision,
  });

  final HealthAggregateRecord aggregateRecord;
  final HealthAggregateRevision revision;
  final HealthEvaluation evaluation;
  final RolloutDecisionRecord decision;
}

_EvidenceFixture _evidence() {
  final aggregate = _aggregate();
  final revision = HealthAggregateRevision(
    aggregateRevisionId: 'revision_concrete',
    aggregateId: 'aggregate_concrete',
    parentAggregateRevisionId: null,
    identity: aggregate.identity,
    window: aggregate.window,
    aggregationVersion: aggregate.identity.aggregationVersion,
    inputCount: aggregate.inputCount,
    inputDigest: aggregate.inputDigest,
    recomputationReason: 'TEST VECTOR ONLY',
    recomputability: P3eRecomputability.rawRecomputable,
    createdAt: DateTime.utc(2026, 8, 24, 12),
  );
  final aggregateRecord = HealthAggregateRecord(
    aggregateId: revision.aggregateId,
    revisionId: revision.aggregateRevisionId,
    aggregate: aggregate,
    recomputability: revision.recomputability,
    createdAt: revision.createdAt,
  );
  final evaluation = HealthEvaluation(
    evaluationId: 'evaluation_concrete',
    organizationId: 'org',
    aggregateRevisionId: revision.aggregateRevisionId,
    rolloutId: 'rollout',
    rolloutRevision: 1,
    evaluationVersion: 1,
    policyVersion: aggregate.policyVersion,
    thresholdSetVersion: 1,
    windowPolicyVersion: 1,
    privacyPolicyVersion: 1,
    aggregateInputDigest: revision.inputDigest,
    decision: 'CONTINUE',
    reasonClass: 'PATCH_SAFETY',
    reasonCodes: const <String>['CONCRETE_TEST'],
    coverageState: aggregate.coverage.state.wireName,
    freshnessState: aggregate.freshnessState.wireName,
    sampleState: 'PASSED',
    createdAt: revision.createdAt,
    auditReference: null,
  );
  final decision = RolloutDecisionRecord(
    decisionId: 'decision_concrete',
    organizationId: 'org',
    rolloutId: 'rollout',
    expectedRolloutRevision: 1,
    evaluationId: evaluation.evaluationId,
    aggregateRevisionId: revision.aggregateRevisionId,
    decision: evaluation.decision,
    reason: 'TEST VECTOR ONLY',
    actorIdentity: 'test-actor',
    idempotencyKey: 'decision-concrete',
    createdAt: revision.createdAt,
  );
  return _EvidenceFixture(
    aggregateRecord: aggregateRecord,
    revision: revision,
    evaluation: evaluation,
    decision: decision,
  );
}

HealthAggregate _aggregate() {
  final start = DateTime.utc(2026, 8, 24, 18);
  final window = ObservationWindow(
    windowId: 'window',
    serverStart: start,
    serverEnd: start.add(const Duration(hours: 1)),
    lateCutoff: start.add(const Duration(hours: 2)),
    minimumDuration: const Duration(hours: 1),
    maximumDuration: const Duration(hours: 3),
    windowPolicyVersion: 1,
  );
  final identity = AggregateIdentity(
    organizationId: 'org',
    applicationId: 'app',
    environmentId: 'env',
    platformId: 'android',
    releaseId: 'release',
    patchId: 'patch',
    sequence: 1,
    rolloutId: 'rollout',
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
      maximumRecords: 50,
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
  ObservationRecord event(String id, ObservationEventType type) {
    final timestamp = start.add(const Duration(minutes: 5));
    return ObservationRecord(
      event: ObservationEvent(
        schemaVersion: 1,
        eventId: id,
        clientTimestamp: timestamp,
        organizationId: 'org',
        applicationId: 'app',
        environmentId: 'env',
        platform: 'android',
        releaseId: 'release',
        patchId: 'patch',
        sequence: 1,
        rolloutId: 'rollout',
        rolloutRevision: 1,
        installationBucket: 'bucket:1',
        eventType: type,
        runtimeVersion: 'runtime',
        patchFormatVersion: 1,
        diagnosticCode: null,
      ),
      receivedAt: timestamp,
      disposition: ObservationDisposition.accepted,
    );
  }

  return const DeterministicAggregator().aggregate(
    identity: identity,
    window: window,
    policy: policy,
    records: <ObservationRecord>[
      event('lookup', ObservationEventType.lookup_attempt),
      event('offer', ObservationEventType.candidate_offered),
      event('download', ObservationEventType.download_succeeded),
      event('admit', ObservationEventType.admission_verified),
      event('activation', ObservationEventType.activation_succeeded),
      event('healthy', ObservationEventType.healthy_confirmed),
      event('restart', ObservationEventType.restart_survived),
    ],
  );
}
