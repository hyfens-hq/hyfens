import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 24, 21);

  test('automatic-halt intent is canonical, bounded, and semantic', () {
    final intent = _intent(now);
    final replay = AutomaticHaltIntent.fromJson(intent.toJson());
    expect(replay.canonicalSerialization, intent.canonicalSerialization);
    expect(replay.intentDigest, intent.intentDigest);
    expect(
      _intent(now.add(const Duration(seconds: 1))).intentDigest,
      intent.intentDigest,
    );
    expect(
      _intent(now, principalId: 'principal_other').intentDigest,
      isNot(intent.intentDigest),
    );
    expect(
      () => AutomaticHaltIntent.fromJson(<String, Object?>{
        ...intent.toJson(),
        'intentDigest': _digest('tampered'),
      }),
      throwsFormatException,
    );
    expect(intent.toString(), isNot(contains('lease')));
  });

  test(
    'File applicability requires exact evidence and persists one intent only',
    () async {
      final fixture = await _Fixture.file(now);
      addTearDown(fixture.close);
      final initialRolloutRevisions = await fixture.control.listJson(
        'rollout_revisions',
      );
      final first = await fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      );
      expect(first.changed, isTrue);
      expect(first.work.status, ScheduledEvaluationWorkStatus.haltApplying);
      expect(first.work.automaticHaltIntent?.decisionId, 'decision_1');
      final replay = await fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      );
      expect(replay.changed, isFalse);
      expect(
        replay.work.automaticHaltIntent?.intentDigest,
        first.work.automaticHaltIntent?.intentDigest,
      );
      expect(
        await fixture.control.listJson('rollout_revisions'),
        hasLength(initialRolloutRevisions.length),
      );
      final rollout = RolloutRecord.fromJson(
        (await fixture.control.readJson('rollouts', 'rollout_1'))!,
      );
      expect(rollout.state, RolloutState.canary);
      final audit = (await fixture.control.readAuditChain()).toString();
      expect(audit, contains('health.auto_halt_intent_created'));
      expect(audit, contains('health.auto_halt_intent_replayed'));
      expect(audit, isNot(contains(_leaseToken)));
      expect(audit, isNot(contains(fixture.principal.token)));
      await fixture.schedules.close();
      final reopened = FileP3e5ScheduleStore(
        Directory('${fixture.root.path}/schedules'),
        clock: () => now,
      );
      await reopened.initialize();
      expect(
        (await reopened.readWork(
          'org_1',
          fixture.workId,
        ))?.automaticHaltIntent?.intentDigest,
        first.work.automaticHaltIntent?.intentDigest,
      );
      await reopened.close();
    },
  );

  test('default-off or historical work cannot enter HALT_APPLYING', () async {
    final fixture = await _Fixture.file(now, productionEnabled: false);
    addTearDown(fixture.close);
    await expectLater(
      fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'HEALTH_AUTO_HALT_STALE',
        ),
      ),
    );
    expect(
      (await fixture.schedules.readWork('org_1', fixture.workId))?.status,
      ScheduledEvaluationWorkStatus.evaluated,
    );
  });

  test(
    'decision, reason, rollout-state, and freshness gates fail closed',
    () async {
      for (final fixture in <_Fixture>[
        await _Fixture.file(now, decisionValue: 'CONTINUE'),
        await _Fixture.file(now, reasonClass: 'DELIVERY_HEALTH'),
        await _Fixture.file(now, rolloutState: RolloutState.paused),
        await _Fixture.file(now, clockAdvance: const Duration(hours: 3)),
      ]) {
        addTearDown(fixture.close);
        await expectLater(
          fixture.service.applyIntent(
            token: fixture.principal.token,
            lease: fixture.lease,
          ),
          throwsA(isA<ControlPlaneException>()),
        );
        expect(
          (await fixture.schedules.readWork('org_1', fixture.workId))?.status,
          ScheduledEvaluationWorkStatus.evaluated,
        );
      }
    },
  );

  test('a successor decision makes the scheduled decision stale', () async {
    final fixture = await _Fixture.file(now);
    addTearDown(fixture.close);
    final current = await fixture.p3e.readDecision('org_1', 'decision_1');
    await fixture.p3e.putDecision(
      RolloutDecisionRecord(
        decisionId: 'decision_successor',
        organizationId: current!.organizationId,
        rolloutId: current.rolloutId,
        expectedRolloutRevision: current.expectedRolloutRevision,
        evaluationId: current.evaluationId,
        aggregateRevisionId: current.aggregateRevisionId,
        decision: current.decision,
        reason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY:successor',
        actorIdentity: 'scheduler_2',
        idempotencyKey: '${current.idempotencyKey}:successor',
        createdAt: now.subtract(const Duration(minutes: 1)),
        previousDecisionId: current.decisionId,
      ),
    );
    await expectLater(
      fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'HEALTH_AUTO_HALT_STALE',
        ),
      ),
    );
  });

  test(
    'revoked principal and expired lease are independent rejections',
    () async {
      final revoked = await _Fixture.file(now, principalRevoked: true);
      addTearDown(revoked.close);
      await expectLater(
        revoked.service.applyIntent(
          token: revoked.principal.token,
          lease: revoked.lease,
        ),
        throwsA(isA<ControlPlaneException>()),
      );

      final expired = await _Fixture.file(now, leaseExpired: true);
      addTearDown(expired.close);
      await expectLater(
        expired.service.applyIntent(
          token: expired.principal.token,
          lease: expired.lease,
        ),
        throwsA(isA<StorageConflict>()),
      );
    },
  );

  test('wrong lease token cannot be replaced by principal authority', () async {
    final fixture = await _Fixture.file(now);
    addTearDown(fixture.close);
    final wrongLease = P3e5LeaseMutation(
      scope: fixture.lease.scope,
      workId: fixture.lease.workId,
      expectedWorkVersion: fixture.lease.expectedWorkVersion,
      leaseOwner: fixture.lease.leaseOwner,
      rawLeaseToken: 'wrong_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ',
    );
    await expectLater(
      fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: wrongLease,
      ),
      throwsA(isA<StorageConflict>()),
    );
  });

  test('generic executor cannot enter HALT_APPLYING without intent', () async {
    final fixture = await _Fixture.file(now);
    addTearDown(fixture.close);
    expect(
      () => P3e5ExecutionAdvance(
        lease: fixture.lease,
        expectedStatus: ScheduledEvaluationWorkStatus.evaluated,
        nextStatus: ScheduledEvaluationWorkStatus.haltApplying,
      ),
      throwsFormatException,
    );
    expect(
      (await fixture.schedules.readWork('org_1', fixture.workId))?.status,
      ScheduledEvaluationWorkStatus.evaluated,
    );
  });

  test(
    'automatic application reuses P3E-4/P3A and fences completion',
    () async {
      final fixture = await _Fixture.file(now);
      addTearDown(fixture.close);
      await fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      );
      final controlService = ControlPlaneService(
        store: fixture.control,
        p3eStore: fixture.p3e,
        clock: () => now,
      );
      final applicationService = P3e5AutomaticHaltApplicationService(
        controlStore: fixture.control,
        scheduleStore: fixture.schedules,
        p3eStore: fixture.p3e,
        controlService: controlService,
        clock: () => now,
      );

      final result = await applicationService.apply(
        token: fixture.principal.token,
        lease: P3e5LeaseMutation(
          scope: fixture.lease.scope,
          workId: fixture.lease.workId,
          expectedWorkVersion: 4,
          leaseOwner: fixture.lease.leaseOwner,
          rawLeaseToken: fixture.lease.rawLeaseToken,
        ),
      );

      expect(result.application.result, 'APPLIED');
      expect(
        result.application.idempotencyKey,
        'scheduled-halt:${fixture.workId}',
      );
      expect(result.work.status, ScheduledEvaluationWorkStatus.completed);
      expect(result.work.haltApplicationId, result.application.applicationId);
      expect(result.work.automaticHaltIntent, isNotNull);
      expect(
        (await fixture.schedules.readWork('org_1', fixture.workId))?.status,
        ScheduledEvaluationWorkStatus.completed,
      );
      final rollout = RolloutRecord.fromJson(
        (await fixture.control.readJson('rollouts', 'rollout_1'))!,
      );
      expect(rollout.state, RolloutState.halted);
      expect(rollout.currentRevision, 2);
      expect(await fixture.p3e.listHaltApplications('org_1'), hasLength(1));
      final audit = (await fixture.control.readAuditChain()).toString();
      expect(audit, contains('health.auto_halt_requested'));
      expect(audit, contains('health.auto_halt_applied'));
      expect(audit, isNot(contains(fixture.principal.token)));
      expect(audit, isNot(contains(_leaseToken)));
    },
  );

  test('generic execution advance cannot complete HALT_APPLYING', () async {
    final fixture = await _Fixture.file(now);
    addTearDown(fixture.close);
    await fixture.service.applyIntent(
      token: fixture.principal.token,
      lease: fixture.lease,
    );
    expect(
      () => P3e5ExecutionAdvance(
        lease: P3e5LeaseMutation(
          scope: fixture.lease.scope,
          workId: fixture.lease.workId,
          expectedWorkVersion: 4,
          leaseOwner: fixture.lease.leaseOwner,
          rawLeaseToken: fixture.lease.rawLeaseToken,
        ),
        expectedStatus: ScheduledEvaluationWorkStatus.haltApplying,
        nextStatus: ScheduledEvaluationWorkStatus.completed,
      ),
      throwsFormatException,
    );
  });

  test(
    'lost P3E-4 response is recovered by the same scheduled idempotency key',
    () async {
      final fixture = await _Fixture.file(now);
      addTearDown(fixture.close);
      await fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      );
      final crashing = P3e5AutomaticHaltApplicationService(
        controlStore: fixture.control,
        scheduleStore: fixture.schedules,
        p3eStore: fixture.p3e,
        controlService: ControlPlaneService(
          store: fixture.control,
          p3eStore: fixture.p3e,
          clock: () => now,
        ),
        clock: () => now,
        failure: (point) async {
          if (point == P3e5AutomaticHaltApplicationFailurePoint.afterP3e4) {
            throw StateError('lost P3E-4 response');
          }
        },
      );
      final applyingLease = P3e5LeaseMutation(
        scope: fixture.lease.scope,
        workId: fixture.lease.workId,
        expectedWorkVersion: 4,
        leaseOwner: fixture.lease.leaseOwner,
        rawLeaseToken: fixture.lease.rawLeaseToken,
      );
      await expectLater(
        crashing.apply(token: fixture.principal.token, lease: applyingLease),
        throwsStateError,
      );
      expect(
        (await fixture.schedules.readWork('org_1', fixture.workId))?.status,
        ScheduledEvaluationWorkStatus.haltApplying,
      );
      expect(await fixture.p3e.listHaltApplications('org_1'), hasLength(1));
      final replay = P3e5AutomaticHaltApplicationService(
        controlStore: fixture.control,
        scheduleStore: fixture.schedules,
        p3eStore: fixture.p3e,
        controlService: ControlPlaneService(
          store: fixture.control,
          p3eStore: fixture.p3e,
          clock: () => now,
        ),
        clock: () => now,
      );
      final recovered = await replay.apply(
        token: fixture.principal.token,
        lease: applyingLease,
      );
      expect(recovered.recovered, isTrue);
      expect(recovered.application.result, 'APPLIED');
      expect(recovered.work.status, ScheduledEvaluationWorkStatus.completed);
      expect(await fixture.p3e.listHaltApplications('org_1'), hasLength(1));
      expect(
        (await fixture.control.readJson('rollouts', 'rollout_1'))!['state'],
        'HALTED',
      );
    },
  );

  test(
    'crash before P3E-4 leaves one retryable HALT_APPLYING work item',
    () async {
      final fixture = await _Fixture.file(now);
      addTearDown(fixture.close);
      await fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      );
      final crashing = P3e5AutomaticHaltApplicationService(
        controlStore: fixture.control,
        scheduleStore: fixture.schedules,
        p3eStore: fixture.p3e,
        controlService: ControlPlaneService(
          store: fixture.control,
          p3eStore: fixture.p3e,
        ),
        clock: () => now,
        failure: (point) async {
          if (point == P3e5AutomaticHaltApplicationFailurePoint.beforeP3e4) {
            throw StateError('injected before P3E-4');
          }
        },
      );
      final applyingLease = P3e5LeaseMutation(
        scope: fixture.lease.scope,
        workId: fixture.lease.workId,
        expectedWorkVersion: 4,
        leaseOwner: fixture.lease.leaseOwner,
        rawLeaseToken: fixture.lease.rawLeaseToken,
      );
      await expectLater(
        crashing.apply(token: fixture.principal.token, lease: applyingLease),
        throwsStateError,
      );
      expect(await fixture.p3e.listHaltApplications('org_1'), isEmpty);
      expect(
        (await fixture.schedules.readWork('org_1', fixture.workId))?.status,
        ScheduledEvaluationWorkStatus.haltApplying,
      );
    },
  );

  test('currentness changes after intent fail closed without P3E-4', () async {
    final fixture = await _Fixture.file(now);
    addTearDown(fixture.close);
    await fixture.service.applyIntent(
      token: fixture.principal.token,
      lease: fixture.lease,
    );
    final rollout = RolloutRecord.fromJson(
      (await fixture.control.readJson('rollouts', 'rollout_1'))!,
    );
    await fixture.control.replaceJson(
      'rollouts',
      rollout.id,
      rollout.copyWith(state: RolloutState.paused).toJson(),
    );
    final applicationService = P3e5AutomaticHaltApplicationService(
      controlStore: fixture.control,
      scheduleStore: fixture.schedules,
      p3eStore: fixture.p3e,
      controlService: ControlPlaneService(
        store: fixture.control,
        p3eStore: fixture.p3e,
      ),
      clock: () => now,
    );
    final applyingLease = P3e5LeaseMutation(
      scope: fixture.lease.scope,
      workId: fixture.lease.workId,
      expectedWorkVersion: 4,
      leaseOwner: fixture.lease.leaseOwner,
      rawLeaseToken: fixture.lease.rawLeaseToken,
    );
    await expectLater(
      applicationService.apply(
        token: fixture.principal.token,
        lease: applyingLease,
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'HEALTH_AUTO_HALT_STALE',
        ),
      ),
    );
    expect(await fixture.p3e.listHaltApplications('org_1'), isEmpty);
    expect(
      (await fixture.schedules.readWork('org_1', fixture.workId))?.status,
      ScheduledEvaluationWorkStatus.haltApplying,
    );
  });

  test(
    'crash before File intent commit leaves EVALUATED and retryable',
    () async {
      final fixture = await _Fixture.file(now, failBeforeCommit: true);
      addTearDown(fixture.close);
      await expectLater(
        fixture.service.applyIntent(
          token: fixture.principal.token,
          lease: fixture.lease,
        ),
        throwsStateError,
      );
      final work = await fixture.schedules.readWork('org_1', fixture.workId);
      expect(work?.status, ScheduledEvaluationWorkStatus.evaluated);
      expect(work?.automaticHaltIntent, isNull);
    },
  );

  test(
    'rollout change immediately before commit is rejected as stale',
    () async {
      final fixture = await _Fixture.file(now);
      addTearDown(fixture.close);
      final service = P3e5AutomaticHaltApplicabilityService(
        controlStore: fixture.control,
        scheduleStore: fixture.schedules,
        p3eStore: fixture.p3e,
        clock: () => now,
        random: Random(643),
        failure: (_) async {
          final rollout = RolloutRecord.fromJson(
            (await fixture.control.readJson('rollouts', 'rollout_1'))!,
          );
          await fixture.control.replaceJson(
            'rollouts',
            rollout.id,
            rollout.copyWith(state: RolloutState.paused).toJson(),
          );
        },
      );
      await expectLater(
        service.applyIntent(
          token: fixture.principal.token,
          lease: fixture.lease,
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'HEALTH_AUTO_HALT_STALE',
          ),
        ),
      );
      final work = await fixture.schedules.readWork('org_1', fixture.workId);
      expect(work?.status, ScheduledEvaluationWorkStatus.evaluated);
      expect(work?.automaticHaltIntent, isNull);
    },
  );

  test('lost response after File commit discovers the same intent', () async {
    final fixture = await _Fixture.file(now, failAfterCommit: true);
    addTearDown(fixture.close);
    await expectLater(
      fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      ),
      throwsStateError,
    );
    final persisted = await fixture.schedules.readWork('org_1', fixture.workId);
    expect(persisted?.status, ScheduledEvaluationWorkStatus.haltApplying);
    expect(persisted?.automaticHaltIntent, isNotNull);
    final replay = await fixture.service.applyIntent(
      token: fixture.principal.token,
      lease: fixture.lease,
    );
    expect(replay.changed, isFalse);
    expect(
      replay.work.automaticHaltIntent?.intentDigest,
      persisted?.automaticHaltIntent?.intentDigest,
    );
  });

  test(
    'lost response after File completion is replayed from terminal evidence',
    () async {
      final fixture = await _Fixture.file(now, failCompletionAfterCommit: true);
      addTearDown(fixture.close);
      await fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      );
      final applicationService = P3e5AutomaticHaltApplicationService(
        controlStore: fixture.control,
        scheduleStore: fixture.schedules,
        p3eStore: fixture.p3e,
        controlService: ControlPlaneService(
          store: fixture.control,
          p3eStore: fixture.p3e,
          clock: () => now,
        ),
        clock: () => now,
      );
      final applyingLease = P3e5LeaseMutation(
        scope: fixture.lease.scope,
        workId: fixture.lease.workId,
        expectedWorkVersion: 4,
        leaseOwner: fixture.lease.leaseOwner,
        rawLeaseToken: fixture.lease.rawLeaseToken,
      );
      await expectLater(
        applicationService.apply(
          token: fixture.principal.token,
          lease: applyingLease,
        ),
        throwsStateError,
      );
      final persisted = await fixture.schedules.readWork(
        'org_1',
        fixture.workId,
      );
      expect(persisted?.status, ScheduledEvaluationWorkStatus.completed);
      expect(persisted?.haltApplicationId, isNotNull);

      final replay = await applicationService.apply(
        token: fixture.principal.token,
        lease: applyingLease,
      );
      expect(replay.recovered, isTrue);
      expect(replay.work.status, ScheduledEvaluationWorkStatus.completed);
      expect(replay.application.applicationId, persisted?.haltApplicationId);
      expect(await fixture.p3e.listHaltApplications('org_1'), hasLength(1));
    },
  );

  test(
    'lease expiry after P3A commit fails closed without a second halt',
    () async {
      final fixture = await _Fixture.file(
        now,
        principalLifetime: const Duration(days: 3),
      );
      addTearDown(fixture.close);
      await fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      );
      final crashing = P3e5AutomaticHaltApplicationService(
        controlStore: fixture.control,
        scheduleStore: fixture.schedules,
        p3eStore: fixture.p3e,
        controlService: ControlPlaneService(
          store: fixture.control,
          p3eStore: fixture.p3e,
          clock: () => now,
        ),
        clock: () => now,
        failure: (point) async {
          if (point == P3e5AutomaticHaltApplicationFailurePoint.afterP3e4) {
            throw StateError('lost response after P3A commit');
          }
        },
      );
      final applyingLease = P3e5LeaseMutation(
        scope: fixture.lease.scope,
        workId: fixture.lease.workId,
        expectedWorkVersion: 4,
        leaseOwner: fixture.lease.leaseOwner,
        rawLeaseToken: fixture.lease.rawLeaseToken,
      );
      await expectLater(
        crashing.apply(token: fixture.principal.token, lease: applyingLease),
        throwsStateError,
      );
      final expired = P3e5AutomaticHaltApplicationService(
        controlStore: fixture.control,
        scheduleStore: fixture.schedules,
        p3eStore: fixture.p3e,
        controlService: ControlPlaneService(
          store: fixture.control,
          p3eStore: fixture.p3e,
          clock: () => now.add(const Duration(days: 1, hours: 1)),
        ),
        clock: () => now.add(const Duration(days: 1, hours: 1)),
      );
      await expectLater(
        expired.apply(token: fixture.principal.token, lease: applyingLease),
        throwsA(isA<StorageConflict>()),
      );
      expect(await fixture.p3e.listHaltApplications('org_1'), hasLength(1));
      expect(
        (await fixture.schedules.readWork('org_1', fixture.workId))?.status,
        ScheduledEvaluationWorkStatus.haltApplying,
      );
    },
  );

  test('expired HALT_APPLYING work is reclaimed and completed through one P3E4/P3A application', () async {
    final fixture = await _Fixture.file(
      now,
      principalLifetime: const Duration(days: 3),
      leaseDuration: const Duration(minutes: 5),
    );
    addTearDown(fixture.close);
    await fixture.service.applyIntent(
      token: fixture.principal.token,
      lease: fixture.lease,
    );
    fixture.advanceClock(now.add(const Duration(minutes: 10)));
    final recovery = P3e5AutomaticHaltRecoveryService(
      controlStore: fixture.control,
      scheduleStore: fixture.schedules,
      p3eStore: fixture.p3e,
      controlService: ControlPlaneService(
        store: fixture.control,
        p3eStore: fixture.p3e,
        clock: () => now.add(const Duration(minutes: 10)),
      ),
      leasePolicy: const P3e5LeasePolicy(
        version: 1,
        duration: Duration(minutes: 5),
      ),
      limits: const P3e5AutomaticHaltRecoveryLimits(
        maximumRecoveryAttempts: 2,
        maximumApplicationRecords: 8,
        maximumLinkageRecords: 8,
      ),
      recoveryOwner: 'recovery_1',
      clock: () => now.add(const Duration(minutes: 10)),
      random: Random(643),
    );

    final result = await recovery.recover(
      token: fixture.principal.token,
      scope: fixture.lease.scope,
      workId: fixture.workId,
    );

    expect(
      result.outcome,
      P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid,
    );
    expect(result.work!.status, ScheduledEvaluationWorkStatus.completed);
    expect(result.reclaimed, isTrue);
    expect(await fixture.p3e.listHaltApplications('org_1'), hasLength(1));
    expect(
      (await fixture.schedules.readWork('org_1', fixture.workId))?.workVersion,
      6,
    );
  });

  test(
    'recovery checks immutable application evidence before retrying P3E4',
    () async {
      final fixture = await _Fixture.file(
        now,
        principalLifetime: const Duration(days: 3),
        leaseDuration: const Duration(minutes: 5),
      );
      addTearDown(fixture.close);
      await fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      );
      final crashingApplication = P3e5AutomaticHaltApplicationService(
        controlStore: fixture.control,
        scheduleStore: fixture.schedules,
        p3eStore: fixture.p3e,
        controlService: ControlPlaneService(
          store: fixture.control,
          p3eStore: fixture.p3e,
          clock: () => now,
        ),
        clock: () => now,
        failure: (point) async {
          if (point == P3e5AutomaticHaltApplicationFailurePoint.afterP3e4) {
            throw StateError('lost P3E-4 response');
          }
        },
      );
      await expectLater(
        crashingApplication.apply(
          token: fixture.principal.token,
          lease: P3e5LeaseMutation(
            scope: fixture.lease.scope,
            workId: fixture.workId,
            expectedWorkVersion: 4,
            leaseOwner: fixture.lease.leaseOwner,
            rawLeaseToken: fixture.lease.rawLeaseToken,
          ),
        ),
        throwsStateError,
      );
      fixture.advanceClock(now.add(const Duration(minutes: 10)));
      var p3e4Calls = 0;
      final recovery = P3e5AutomaticHaltRecoveryService(
        controlStore: fixture.control,
        scheduleStore: fixture.schedules,
        p3eStore: fixture.p3e,
        controlService: ControlPlaneService(
          store: fixture.control,
          p3eStore: fixture.p3e,
        ),
        leasePolicy: const P3e5LeasePolicy(
          version: 1,
          duration: Duration(hours: 1),
        ),
        limits: const P3e5AutomaticHaltRecoveryLimits(
          maximumRecoveryAttempts: 2,
          maximumApplicationRecords: 8,
          maximumLinkageRecords: 8,
        ),
        recoveryOwner: 'recovery_2',
        clock: () => now.add(const Duration(minutes: 10)),
        applicationFailure: (point) async {
          if (point == P3e5AutomaticHaltApplicationFailurePoint.beforeP3e4) {
            p3e4Calls++;
          }
        },
      );

      final result = await recovery.recover(
        token: fixture.principal.token,
        scope: fixture.lease.scope,
        workId: fixture.workId,
      );

      expect(
        result.outcome,
        P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid,
      );
      expect(p3e4Calls, 0);
      expect(await fixture.p3e.listHaltApplications('org_1'), hasLength(1));
      expect(result.work!.status, ScheduledEvaluationWorkStatus.completed);
    },
  );

  test(
    'generic scheduled claiming does not reclaim expired HALT_APPLYING work',
    () async {
      final fixture = await _Fixture.file(
        now,
        principalLifetime: const Duration(days: 3),
      );
      addTearDown(fixture.close);
      await fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      );
      fixture.advanceClock(now.add(const Duration(days: 2)));
      final claims = await fixture.schedules.claimDue(
        P3e5ClaimRequest(
          scope: fixture.lease.scope,
          leaseOwner: 'generic-scheduler',
          leasePolicy: const P3e5LeasePolicy(
            version: 1,
            duration: Duration(minutes: 5),
          ),
          resourcePolicy: const P3e5ClaimResourcePolicy(
            version: 1,
            claimBatchSize: 1,
            pendingConsiderationLimit: 1,
            maximumActiveLeasesPerTenant: 10,
            recoveryScanBatch: 1,
          ),
          preparedLeases: <P3e5PreparedLease>[
            P3e5PreparedLease(
              'generic_recovery_0123456789abcdefghijklmnopqrstuvwxyz',
            ),
          ],
        ),
      );
      expect(claims, isEmpty);
      expect(
        (await fixture.schedules.readWork('org_1', fixture.workId))?.status,
        ScheduledEvaluationWorkStatus.haltApplying,
      );
    },
  );

  test('active lease is retryable and does not mutate work', () async {
    final fixture = await _Fixture.file(now);
    addTearDown(fixture.close);
    await fixture.service.applyIntent(
      token: fixture.principal.token,
      lease: fixture.lease,
    );
    final recovery = P3e5AutomaticHaltRecoveryService(
      controlStore: fixture.control,
      scheduleStore: fixture.schedules,
      p3eStore: fixture.p3e,
      controlService: ControlPlaneService(
        store: fixture.control,
        p3eStore: fixture.p3e,
      ),
      leasePolicy: const P3e5LeasePolicy(
        version: 1,
        duration: Duration(minutes: 5),
      ),
      limits: const P3e5AutomaticHaltRecoveryLimits(
        maximumRecoveryAttempts: 2,
        maximumApplicationRecords: 8,
        maximumLinkageRecords: 8,
      ),
      recoveryOwner: 'recovery_active',
      clock: () => now,
    );
    final result = await recovery.recover(
      token: fixture.principal.token,
      scope: fixture.lease.scope,
      workId: fixture.workId,
    );
    expect(
      result.outcome,
      P3e5AutomaticHaltRecoveryOutcome.applicationNotFoundRetryable,
    );
    expect(result.reclaimed, isFalse);
    expect(
      (await fixture.schedules.readWork('org_1', fixture.workId))?.workVersion,
      4,
    );
  });

  test(
    'stale rollout is rejected after reclaim without creating an application',
    () async {
      final fixture = await _Fixture.file(
        now,
        principalLifetime: const Duration(days: 3),
        leaseDuration: const Duration(minutes: 5),
      );
      addTearDown(fixture.close);
      await fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      );
      final rollout = RolloutRecord.fromJson(
        (await fixture.control.readJson('rollouts', 'rollout_1'))!,
      );
      await fixture.control.replaceJson(
        'rollouts',
        rollout.id,
        rollout.copyWith(state: RolloutState.paused).toJson(),
      );
      fixture.advanceClock(now.add(const Duration(minutes: 10)));
      final recovery = _recovery(fixture, now.add(const Duration(minutes: 10)));
      final result = await recovery.recover(
        token: fixture.principal.token,
        scope: fixture.lease.scope,
        workId: fixture.workId,
      );
      expect(result.outcome, P3e5AutomaticHaltRecoveryOutcome.applicationStale);
      expect(await fixture.p3e.listHaltApplications('org_1'), isEmpty);
      expect(result.work!.status, ScheduledEvaluationWorkStatus.stale);
    },
  );

  test(
    'malformed immutable application evidence fails closed before reclaim',
    () async {
      final fixture = await _Fixture.file(
        now,
        principalLifetime: const Duration(days: 3),
        leaseDuration: const Duration(minutes: 5),
      );
      addTearDown(fixture.close);
      await fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      );
      final work = (await fixture.schedules.readWork('org_1', fixture.workId))!;
      await fixture.p3e.putHaltApplication(
        HealthHaltApplication(
          applicationId: 'malformed_application',
          organizationId: 'org_1',
          decisionId: work.decisionId!,
          evaluationId: work.evaluationId!,
          aggregateRevisionId: work.aggregateRevisionId!,
          rolloutId: work.logicalKey.rolloutId,
          expectedRolloutRevision: 1,
          result: 'APPLIED',
          reason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY:malformed',
          actorIdentity: 'wrong_principal',
          idempotencyKey: work.logicalKey.haltIdempotencyKey,
          previousRolloutRevision: 1,
          resultingRolloutRevision: 2,
          resultingTransitionReference: 'rollout_revision_2',
          createdAt: now,
        ),
      );
      fixture.advanceClock(now.add(const Duration(minutes: 10)));
      final result =
          await _recovery(
            fixture,
            now.add(const Duration(minutes: 10)),
          ).recover(
            token: fixture.principal.token,
            scope: fixture.lease.scope,
            workId: fixture.workId,
          );
      expect(
        result.outcome,
        P3e5AutomaticHaltRecoveryOutcome.applicationCorrupt,
      );
      expect(
        (await fixture.schedules.readWork(
          'org_1',
          fixture.workId,
        ))?.workVersion,
        4,
      );
    },
  );

  test('old lease cannot complete after recovery reclaims the fence', () async {
    final fixture = await _Fixture.file(
      now,
      principalLifetime: const Duration(days: 3),
      leaseDuration: const Duration(minutes: 5),
    );
    addTearDown(fixture.close);
    await fixture.service.applyIntent(
      token: fixture.principal.token,
      lease: fixture.lease,
    );
    fixture.advanceClock(now.add(const Duration(minutes: 10)));
    final result =
        await _recovery(fixture, now.add(const Duration(minutes: 10))).recover(
          token: fixture.principal.token,
          scope: fixture.lease.scope,
          workId: fixture.workId,
        );
    final application = result.application!;
    await expectLater(
      fixture.schedules.completeAutomaticHalt(
        P3e5AutomaticHaltCompletion(
          lease: P3e5LeaseMutation(
            scope: fixture.lease.scope,
            workId: fixture.workId,
            expectedWorkVersion: 4,
            leaseOwner: fixture.lease.leaseOwner,
            rawLeaseToken: fixture.lease.rawLeaseToken,
          ),
          intentDigest: result.work!.automaticHaltIntent!.intentDigest,
          haltApplicationId: application.applicationId,
          idempotencyKey: application.idempotencyKey,
          evaluationId: application.evaluationId,
          decisionId: application.decisionId,
          previousRolloutRevision: application.previousRolloutRevision!,
          resultingRolloutRevision: application.resultingRolloutRevision!,
          resultingTransitionReference:
              application.resultingTransitionReference!,
          result: application.result,
        ),
      ),
      throwsA(isA<StorageConflict>()),
    );
  });

  test(
    'lost File reclaim response is recovered without a second halt',
    () async {
      final fixture = await _Fixture.file(
        now,
        principalLifetime: const Duration(days: 3),
        leaseDuration: const Duration(minutes: 5),
        failReclaimAfterCommit: true,
      );
      addTearDown(fixture.close);
      await fixture.service.applyIntent(
        token: fixture.principal.token,
        lease: fixture.lease,
      );
      fixture.advanceClock(now.add(const Duration(minutes: 10)));
      final first =
          await _recovery(
            fixture,
            now.add(const Duration(minutes: 10)),
          ).recover(
            token: fixture.principal.token,
            scope: fixture.lease.scope,
            workId: fixture.workId,
          );
      expect(
        first.outcome,
        P3e5AutomaticHaltRecoveryOutcome.applicationConflict,
      );
      expect(await fixture.p3e.listHaltApplications('org_1'), isEmpty);
      expect(
        (await fixture.schedules.readWork(
          'org_1',
          fixture.workId,
        ))?.workVersion,
        5,
      );

      fixture.advanceClock(now.add(const Duration(minutes: 20)));
      final second =
          await _recovery(
            fixture,
            now.add(const Duration(minutes: 20)),
          ).recover(
            token: fixture.principal.token,
            scope: fixture.lease.scope,
            workId: fixture.workId,
          );
      expect(
        second.outcome,
        P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid,
      );
      expect(await fixture.p3e.listHaltApplications('org_1'), hasLength(1));
      expect(second.work!.status, ScheduledEvaluationWorkStatus.completed);
    },
  );

  test('File restart reloads expired HALT_APPLYING before recovery', () async {
    final fixture = await _Fixture.file(
      now,
      principalLifetime: const Duration(days: 3),
      leaseDuration: const Duration(minutes: 5),
    );
    addTearDown(fixture.close);
    await fixture.service.applyIntent(
      token: fixture.principal.token,
      lease: fixture.lease,
    );
    await fixture.schedules.close();
    final reopened = FileP3e5ScheduleStore(
      Directory('${fixture.root.path}/schedules'),
      clock: () => now.add(const Duration(minutes: 10)),
    );
    await reopened.initialize();
    addTearDown(reopened.close);
    final result =
        await _recovery(
          fixture,
          now.add(const Duration(minutes: 10)),
          scheduleStore: reopened,
        ).recover(
          token: fixture.principal.token,
          scope: fixture.lease.scope,
          workId: fixture.workId,
        );
    expect(
      result.outcome,
      P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid,
    );
    expect(result.work!.status, ScheduledEvaluationWorkStatus.completed);
    expect(await fixture.p3e.listHaltApplications('org_1'), hasLength(1));
  });

  test('expired Auto-Halt Principal is rejected before reclaim', () async {
    final fixture = await _Fixture.file(
      now,
      principalLifetime: const Duration(minutes: 5),
      leaseDuration: const Duration(minutes: 5),
    );
    addTearDown(fixture.close);
    await fixture.service.applyIntent(
      token: fixture.principal.token,
      lease: fixture.lease,
    );
    fixture.advanceClock(now.add(const Duration(minutes: 10)));
    final result =
        await _recovery(fixture, now.add(const Duration(minutes: 10))).recover(
          token: fixture.principal.token,
          scope: fixture.lease.scope,
          workId: fixture.workId,
        );
    expect(result.outcome, P3e5AutomaticHaltRecoveryOutcome.securityRejected);
    expect(
      (await fixture.schedules.readWork('org_1', fixture.workId))?.workVersion,
      4,
    );
  });

  test('recovery record bound rejects an oversized evidence set', () async {
    final fixture = await _Fixture.file(
      now,
      principalLifetime: const Duration(days: 3),
      leaseDuration: const Duration(minutes: 5),
    );
    addTearDown(fixture.close);
    await fixture.service.applyIntent(
      token: fixture.principal.token,
      lease: fixture.lease,
    );
    final work = (await fixture.schedules.readWork('org_1', fixture.workId))!;
    for (var index = 0; index < 9; index++) {
      await fixture.p3e.putHaltApplication(
        HealthHaltApplication(
          applicationId: 'bound_application_$index',
          organizationId: 'org_1',
          decisionId: work.decisionId!,
          evaluationId: work.evaluationId!,
          aggregateRevisionId: work.aggregateRevisionId!,
          rolloutId: work.logicalKey.rolloutId,
          expectedRolloutRevision: 1,
          result: 'APPLIED',
          reason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY:bound',
          actorIdentity: 'principal_auto_halt',
          idempotencyKey: 'scheduled-halt:bound_$index',
          previousRolloutRevision: 1,
          resultingRolloutRevision: 2,
          resultingTransitionReference: 'rollout_revision_2',
          createdAt: now,
        ),
      );
    }
    fixture.advanceClock(now.add(const Duration(minutes: 10)));
    final result =
        await _recovery(
          fixture,
          now.add(const Duration(minutes: 10)),
          limits: const P3e5AutomaticHaltRecoveryLimits(
            maximumRecoveryAttempts: 2,
            maximumApplicationRecords: 8,
            maximumLinkageRecords: 8,
          ),
        ).recover(
          token: fixture.principal.token,
          scope: fixture.lease.scope,
          workId: fixture.workId,
        );
    expect(
      result.outcome,
      P3e5AutomaticHaltRecoveryOutcome.applicationConflict,
    );
    expect(
      (await fixture.schedules.readWork('org_1', fixture.workId))?.workVersion,
      4,
    );
  });

  test('cross-tenant recovery cannot inspect or reclaim work', () async {
    final fixture = await _Fixture.file(now);
    addTearDown(fixture.close);
    await fixture.service.applyIntent(
      token: fixture.principal.token,
      lease: fixture.lease,
    );
    final result = await _recovery(fixture, now).recover(
      token: fixture.principal.token,
      scope: const P3e5ClaimScope(
        organizationId: 'org_other',
        applicationId: 'app_other',
        environmentId: 'env_other',
      ),
      workId: fixture.workId,
    );
    expect(result.outcome, P3e5AutomaticHaltRecoveryOutcome.securityRejected);
    expect(
      (await fixture.schedules.readWork('org_1', fixture.workId))?.workVersion,
      4,
    );
  });

  final postgresUrl = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  test(
    'two PostgreSQL recovery claimants converge on one fresh auto-halt lease',
    () async {
      final pgNow = DateTime.now().toUtc();
      final source = await _Fixture.file(
        pgNow,
        leaseDuration: const Duration(microseconds: 1),
      );
      addTearDown(source.close);
      await source.service.applyIntent(
        token: source.principal.token,
        lease: source.lease,
      );
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final organizationId = 'org_p3e5d_$suffix';
      final left = PostgresP3e5ScheduleStore(postgresUrl!);
      final right = PostgresP3e5ScheduleStore(postgresUrl);
      final control = PostgresControlPlaneStore(postgresUrl);
      final p3e = PostgresP3ePersistenceStore(postgresUrl);
      await Future.wait(<Future<void>>[
        left.initialize(),
        right.initialize(),
        control.initialize(),
        p3e.initialize(),
      ]);
      addTearDown(() async {
        await left.close();
        await right.close();
        await p3e.close();
        await control.close();
      });
      await _copyFixtureToPostgres(
        source,
        control,
        p3e,
        left,
        organizationId,
        suffix,
      );
      final work = (await left.listWork(organizationId)).single;
      final scope = P3e5ClaimScope(
        organizationId: organizationId,
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
      );
      final request = (String owner, String token) =>
          P3e5AutomaticHaltReclaimRequest(
            scope: scope,
            workId: work.workId,
            expectedWorkVersion: work.workVersion,
            leaseOwner: owner,
            rawLeaseToken: token,
            leasePolicy: const P3e5LeasePolicy(
              version: 1,
              duration: Duration(minutes: 5),
            ),
          );
      Future<P3e5ClaimedWork?> attempt(
        P3e5ScheduleStore store,
        P3e5AutomaticHaltReclaimRequest reclaim,
      ) async {
        try {
          return await store.reclaimAutomaticHalt(reclaim);
        } on StorageConflict {
          return null;
        }
      }

      final results = await Future.wait(<Future<P3e5ClaimedWork?>>[
        attempt(
          left,
          request(
            'recovery_left',
            'recovery_left_0123456789abcdefghijklmnopqrstuvwxyz',
          ),
        ),
        attempt(
          right,
          request(
            'recovery_right',
            'recovery_right_0123456789abcdefghijklmnopqrstuvwxyz',
          ),
        ),
      ]);
      expect(results.whereType<P3e5ClaimedWork>(), hasLength(1));
      expect(results.where((item) => item == null), hasLength(1));
      final persisted = await right.readWork(organizationId, work.workId);
      expect(persisted?.status, ScheduledEvaluationWorkStatus.haltApplying);
      expect(persisted?.workVersion, work.workVersion + 1);
      expect(persisted?.leaseOwner, anyOf('recovery_left', 'recovery_right'));
    },
    skip: postgresUrl == null
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );

  test(
    'two PostgreSQL instances converge on one fenced intent work version',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final bootstrap = PostgresControlPlaneStore(postgresUrl!);
      await bootstrap.initialize();
      await bootstrap.close();
      final left = PostgresP3e5ScheduleStore(postgresUrl);
      final right = PostgresP3e5ScheduleStore(postgresUrl);
      await Future.wait(<Future<void>>[left.initialize(), right.initialize()]);
      addTearDown(left.close);
      addTearDown(right.close);
      final scope = P3e5ClaimScope(
        organizationId: 'org_$suffix',
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
      );
      final policy = AutomaticHaltPolicy(
        policyId: 'policy_$suffix',
        organizationId: scope.organizationId,
        applicationId: scope.applicationId,
        environmentId: scope.environmentId,
        maximumAggregateAgeFromLateCutoff: const Duration(minutes: 10),
        maximumDecisionAgeFromEvaluation: const Duration(minutes: 10),
        resourcePolicyReference:
            'TEST VECTOR ONLY — NOT PRODUCTION POLICY:resource',
        approvalReference: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY:approval',
        createdAt: now,
        createdBy: 'actor_1',
      );
      final scheduleId = 'schedule_$suffix';
      final revisionId = 'revision_$suffix';
      final schedule = EvaluationSchedule(
        scheduleId: scheduleId,
        organizationId: scope.organizationId,
        applicationId: scope.applicationId,
        environmentId: scope.environmentId,
        rolloutId: 'rollout_$suffix',
        currentScheduleRevision: revisionId,
        createdAt: now,
        createdBy: 'actor_1',
      );
      final revision = EvaluationScheduleRevision(
        scheduleRevisionId: revisionId,
        scheduleId: scheduleId,
        scheduleGeneration: 1,
        organizationId: scope.organizationId,
        applicationId: scope.applicationId,
        environmentId: scope.environmentId,
        rolloutId: schedule.rolloutId,
        logicalKeyVersion: 2,
        scheduledEvaluationEnabled: true,
        automaticHaltEnabled: true,
        readinessPhase: EvaluationReadinessPhase.sealed,
        automaticHaltPolicyId: policy.policyId,
        automaticHaltPolicyVersion: 1,
        automaticHaltPolicyDigest: policy.digest,
        automaticHaltEligibleSource: AutomaticHaltEligibleSource.scheduledOnly,
        automaticHaltEligibleReadiness:
            AutomaticHaltEligibleReadiness.sealedOnly,
        automaticHaltEligibleReasonClass:
            AutomaticHaltEligibleReasonClass.patchSafetyOnly,
        triggerPolicyVersion: 1,
        schedulePolicyVersion: 1,
        evaluationPolicyVersion: 1,
        evaluationPolicyDigest: _digest('evaluation-$suffix'),
        thresholdSetVersion: 1,
        thresholdSetDigest: _digest('threshold-$suffix'),
        aggregationVersion: 1,
        windowPolicyVersion: 1,
        privacyPolicyVersion: 1,
        retryPolicyReference: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY:retry',
        resourcePolicyReference:
            'TEST VECTOR ONLY — NOT PRODUCTION POLICY:resource',
        supersedesScheduleRevisionId: null,
        createdAt: now,
        createdBy: 'actor_1',
        reason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
      );
      await left.createSchedule(schedule, revision);
      final key = LogicalEvaluationKey(
        logicalKeyVersion: 2,
        organizationId: scope.organizationId,
        applicationId: scope.applicationId,
        environmentId: scope.environmentId,
        platformId: 'android',
        rolloutId: schedule.rolloutId,
        rolloutRevision: 1,
        releaseId: 'release_$suffix',
        patchId: 'patch_$suffix',
        sequence: 1,
        targetBindingDigest: _digest('target-$suffix'),
        windowId: 'window_$suffix',
        readinessPhase: EvaluationReadinessPhase.sealed,
        observationSchemaVersion: 1,
        aggregationVersion: 1,
        aggregatePolicyDigest: _digest('aggregate-$suffix'),
        evaluationPolicyVersion: 1,
        evaluationPolicyDigest: revision.evaluationPolicyDigest,
        thresholdSetVersion: 1,
        thresholdSetDigest: revision.thresholdSetDigest,
        windowPolicyVersion: 1,
        privacyPolicyVersion: 1,
        scheduleId: scheduleId,
        scheduleRevisionId: revisionId,
        scheduleGeneration: 1,
        automaticHaltPolicyId: policy.policyId,
        automaticHaltPolicyVersion: 1,
        automaticHaltPolicyDigest: policy.digest,
        automaticHaltEnabled: true,
        automaticHaltEligibleSource: AutomaticHaltEligibleSource.scheduledOnly,
        automaticHaltEligibleReadiness:
            AutomaticHaltEligibleReadiness.sealedOnly,
        automaticHaltEligibleReasonClass:
            AutomaticHaltEligibleReasonClass.patchSafetyOnly,
      );
      final rawLeaseToken = '${_leaseToken}_$suffix';
      final work = ScheduledEvaluationWork(
        workId: key.workId,
        logicalKey: key,
        status: ScheduledEvaluationWorkStatus.evaluated,
        workVersion: 3,
        attemptCount: 1,
        notBefore: now.subtract(const Duration(days: 2)),
        leaseOwner: 'executor_$suffix',
        leaseTokenDigest: sha256Digest(rawLeaseToken.codeUnits),
        leaseAcquiredAt: now.subtract(const Duration(days: 2)),
        leaseExpiresAt: now.add(const Duration(days: 1)),
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 2)),
        lastAttemptAt: now.subtract(const Duration(days: 2)),
        lastErrorClass: null,
        lastErrorCode: null,
        aggregateId: 'aggregate_$suffix',
        aggregateRevisionId: 'aggregate_revision_$suffix',
        evaluationId: 'evaluation_$suffix',
        decisionId: 'decision_$suffix',
        haltApplicationId: null,
      );
      await left.putWork(work);
      final principal = CredentialService(random: Random(642)).issue(
        id: 'principal_$suffix',
        organizationId: scope.organizationId,
        kind: CredentialKind.autoHalt,
        scopes: autoHaltScopes,
        applicationId: scope.applicationId,
        environmentId: scope.environmentId,
        expiresAt: now.add(const Duration(days: 1)),
      );
      final lease = P3e5LeaseMutation(
        scope: scope,
        workId: work.workId,
        expectedWorkVersion: work.workVersion,
        leaseOwner: work.leaseOwner!,
        rawLeaseToken: rawLeaseToken,
      );
      final intent = AutomaticHaltIntent(
        workId: work.workId,
        attemptId: deriveAttemptId(work.workId, 1),
        evaluationId: work.evaluationId!,
        decisionId: work.decisionId!,
        scheduleRevisionId: revisionId,
        automaticHaltPolicyVersion: 1,
        automaticHaltPolicyDigest: policy.digest,
        expectedRolloutRevision: 1,
        targetBindingDigest: key.targetBindingDigest,
        authorizedPrincipalId: principal.record.id,
        authorizedAt: now,
      );
      final advance = P3e5AutomaticHaltIntentAdvance(
        authority: AutomaticHaltAuthority(
          lease: lease,
          principal: principal.record,
          authoritativeNow: now,
        ),
        intent: intent,
      );
      final results = await Future.wait(
        <P3e5ScheduleStore>[left, right].map(
          (store) => store.applyAutomaticHaltIntent(
            advance,
            validateCurrent: (_, _) async {},
          ),
        ),
      );
      expect(results.where((result) => result.changed), hasLength(1));
      expect(results.where((result) => !result.changed), hasLength(1));
      final persisted = await right.readWork(scope.organizationId, work.workId);
      expect(persisted?.status, ScheduledEvaluationWorkStatus.haltApplying);
      expect(persisted?.workVersion, 4);
      expect(persisted?.automaticHaltIntent?.intentDigest, intent.intentDigest);
      final reopened = PostgresP3e5ScheduleStore(postgresUrl);
      await reopened.initialize();
      expect(
        (await reopened.readWork(
          scope.organizationId,
          work.workId,
        ))?.automaticHaltIntent?.intentDigest,
        intent.intentDigest,
      );
      await reopened.close();
    },
    skip: postgresUrl == null
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );

  test(
    'two PostgreSQL recovery services converge on one application after a lost claimant response',
    () async {
      final pgNow = DateTime.now().toUtc();
      final source = await _Fixture.file(
        pgNow,
        leaseDuration: const Duration(microseconds: 1),
      );
      addTearDown(source.close);
      await source.service.applyIntent(
        token: source.principal.token,
        lease: source.lease,
      );
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final organizationId = 'org_p3e5d_recovery_$suffix';
      final leftControl = PostgresControlPlaneStore(postgresUrl!);
      final rightControl = PostgresControlPlaneStore(postgresUrl);
      final leftP3e = PostgresP3ePersistenceStore(postgresUrl);
      final rightP3e = PostgresP3ePersistenceStore(postgresUrl);
      final leftSchedule = PostgresP3e5ScheduleStore(postgresUrl);
      final rightSchedule = PostgresP3e5ScheduleStore(postgresUrl);
      await Future.wait(<Future<void>>[
        leftControl.initialize(),
        rightControl.initialize(),
        leftP3e.initialize(),
        rightP3e.initialize(),
        leftSchedule.initialize(),
        rightSchedule.initialize(),
      ]);
      addTearDown(() async {
        await leftSchedule.close();
        await rightSchedule.close();
        await leftP3e.close();
        await rightP3e.close();
        await leftControl.close();
        await rightControl.close();
      });
      final credential = await _copyFixtureToPostgres(
        source,
        leftControl,
        leftP3e,
        leftSchedule,
        organizationId,
        suffix,
      );
      final scope = P3e5ClaimScope(
        organizationId: organizationId,
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final commonLimits = const P3e5AutomaticHaltRecoveryLimits(
        maximumRecoveryAttempts: 3,
        maximumApplicationRecords: 8,
        maximumLinkageRecords: 8,
      );
      final left = P3e5AutomaticHaltRecoveryService(
        controlStore: leftControl,
        scheduleStore: leftSchedule,
        p3eStore: leftP3e,
        controlService: ControlPlaneService(
          store: leftControl,
          p3eStore: leftP3e,
        ),
        leasePolicy: const P3e5LeasePolicy(
          version: 1,
          duration: Duration(seconds: 2),
        ),
        limits: commonLimits,
        recoveryOwner: 'pg_recovery_left',
        clock: () => DateTime.now().toUtc(),
        random: Random(645),
        applicationFailure: (point) async {
          if (point == P3e5AutomaticHaltApplicationFailurePoint.afterP3e4) {
            throw StateError('lost PostgreSQL P3E-4 response');
          }
        },
      );
      final leftResult = await left.recover(
        token: credential.token,
        scope: scope,
        workId: (await leftSchedule.listWork(organizationId)).single.workId,
      );
      expect(
        leftResult.outcome,
        P3e5AutomaticHaltRecoveryOutcome.applicationConflict,
      );
      expect(await leftP3e.listHaltApplications(organizationId), hasLength(1));
      await Future<void>.delayed(const Duration(seconds: 3));

      final right = P3e5AutomaticHaltRecoveryService(
        controlStore: rightControl,
        scheduleStore: rightSchedule,
        p3eStore: rightP3e,
        controlService: ControlPlaneService(
          store: rightControl,
          p3eStore: rightP3e,
        ),
        leasePolicy: const P3e5LeasePolicy(
          version: 1,
          duration: Duration(minutes: 5),
        ),
        limits: commonLimits,
        recoveryOwner: 'pg_recovery_right',
        clock: () => DateTime.now().toUtc(),
        random: Random(646),
      );
      final rightResult = await right.recover(
        token: credential.token,
        scope: scope,
        workId: (await rightSchedule.listWork(organizationId)).single.workId,
      );
      expect(
        rightResult.outcome,
        P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid,
      );
      expect(rightResult.application, isNotNull);
      expect(await rightP3e.listHaltApplications(organizationId), hasLength(1));
      expect(
        (await rightSchedule.listWork(organizationId)).single.status,
        ScheduledEvaluationWorkStatus.completed,
      );
    },
    skip: postgresUrl == null
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );

  test(
    'two PostgreSQL application callers converge on one halt and completion',
    () async {
      final pgNow = DateTime.now().toUtc();
      final source = await _Fixture.file(pgNow);
      addTearDown(source.close);
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final organizationId = 'org_p3e5c_$suffix';
      final leftControl = PostgresControlPlaneStore(postgresUrl!);
      final rightControl = PostgresControlPlaneStore(postgresUrl);
      final leftP3e = PostgresP3ePersistenceStore(postgresUrl);
      final rightP3e = PostgresP3ePersistenceStore(postgresUrl);
      final leftSchedule = PostgresP3e5ScheduleStore(postgresUrl);
      final rightSchedule = PostgresP3e5ScheduleStore(postgresUrl);
      await Future.wait(<Future<void>>[
        leftControl.initialize(),
        rightControl.initialize(),
        leftP3e.initialize(),
        rightP3e.initialize(),
        leftSchedule.initialize(),
        rightSchedule.initialize(),
      ]);
      addTearDown(() async {
        await leftSchedule.close();
        await rightSchedule.close();
        await leftP3e.close();
        await rightP3e.close();
        await leftControl.close();
        await rightControl.close();
      });
      final copiedCredential = await _copyFixtureToPostgres(
        source,
        leftControl,
        leftP3e,
        leftSchedule,
        organizationId,
        suffix,
      );
      final applicationId = 'app_$suffix';
      final environmentId = 'env_$suffix';
      final copiedWork = (await leftSchedule.listWork(organizationId)).single;
      final applicability = P3e5AutomaticHaltApplicabilityService(
        controlStore: leftControl,
        scheduleStore: leftSchedule,
        p3eStore: leftP3e,
        clock: () => pgNow,
      );
      final evaluatedLease = P3e5LeaseMutation(
        scope: P3e5ClaimScope(
          organizationId: organizationId,
          applicationId: applicationId,
          environmentId: environmentId,
        ),
        workId: copiedWork.workId,
        expectedWorkVersion: copiedWork.workVersion,
        leaseOwner: copiedWork.leaseOwner!,
        rawLeaseToken: _leaseToken,
      );
      await applicability.applyIntent(
        token: copiedCredential.token,
        lease: evaluatedLease,
      );
      final applyingWork = (await leftSchedule.readWork(
        organizationId,
        copiedWork.workId,
      ))!;
      final applyingLease = P3e5LeaseMutation(
        scope: evaluatedLease.scope,
        workId: applyingWork.workId,
        expectedWorkVersion: applyingWork.workVersion,
        leaseOwner: applyingWork.leaseOwner!,
        rawLeaseToken: _leaseToken,
      );
      final leftApplication = P3e5AutomaticHaltApplicationService(
        controlStore: leftControl,
        scheduleStore: leftSchedule,
        p3eStore: leftP3e,
        controlService: ControlPlaneService(
          store: leftControl,
          p3eStore: leftP3e,
        ),
        clock: () => pgNow,
      );
      final rightApplication = P3e5AutomaticHaltApplicationService(
        controlStore: rightControl,
        scheduleStore: rightSchedule,
        p3eStore: rightP3e,
        controlService: ControlPlaneService(
          store: rightControl,
          p3eStore: rightP3e,
        ),
        clock: () => pgNow,
      );
      final outcomes = await Future.wait(
        <Future<P3e5AutomaticHaltApplicationResult>>[
          leftApplication.apply(
            token: copiedCredential.token,
            lease: applyingLease,
          ),
          rightApplication.apply(
            token: copiedCredential.token,
            lease: applyingLease,
          ),
        ],
      );
      expect(
        outcomes.map((item) => item.application.result),
        everyElement(isIn(<String>{'APPLIED', 'ALREADY_APPLIED'})),
      );
      expect(
        outcomes.map((item) => item.application.applicationId).toSet(),
        hasLength(1),
      );
      expect(
        (await rightSchedule.readWork(
          organizationId,
          copiedWork.workId,
        ))?.status,
        ScheduledEvaluationWorkStatus.completed,
      );
      expect(await rightP3e.listHaltApplications(organizationId), hasLength(1));
      final rollout = RolloutRecord.fromJson(
        (await rightControl.readJson('rollouts', 'rollout_$suffix'))!,
      );
      expect(rollout.state, RolloutState.halted);
      expect(rollout.currentRevision, 2);
    },
    skip: postgresUrl == null
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );

  test(
    'Task 67 audit outage and post-commit divergence remain fail-closed',
    () async {
      final beforeP3e4 = await _Fixture.file(
        now,
        principalLifetime: const Duration(days: 7),
        leaseDuration: const Duration(microseconds: 1),
        controlDecorator: (delegate) => _AuditFaultControlStore(
          delegate,
          failBefore: (record) =>
              record['action'] == 'health.auto_halt_requested',
        ),
      );
      addTearDown(beforeP3e4.close);
      await beforeP3e4.service.applyIntent(
        token: beforeP3e4.principal.token,
        lease: beforeP3e4.lease,
      );
      final beforeP3e4Application = _application(beforeP3e4);
      await expectLater(
        beforeP3e4Application.apply(
          token: beforeP3e4.principal.token,
          lease: _leaseAt(beforeP3e4, 4),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await beforeP3e4.p3e.listHaltApplications('org_1'), isEmpty);
      beforeP3e4.advanceClock(now.add(const Duration(seconds: 1)));
      final beforeP3e4Recovered =
          await _recovery(
            beforeP3e4,
            now.add(const Duration(seconds: 1)),
          ).recover(
            token: beforeP3e4.principal.token,
            scope: beforeP3e4.lease.scope,
            workId: beforeP3e4.workId,
          );
      expect(
        beforeP3e4Recovered.outcome,
        P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid,
      );

      final afterP3a = await _Fixture.file(
        now,
        principalLifetime: const Duration(days: 7),
        leaseDuration: const Duration(microseconds: 1),
        controlDecorator: (delegate) => _AuditFaultControlStore(
          delegate,
          failAfter: (record) => record['action'] == 'health.auto_halt_applied',
        ),
      );
      addTearDown(afterP3a.close);
      await afterP3a.service.applyIntent(
        token: afterP3a.principal.token,
        lease: afterP3a.lease,
      );
      await expectLater(
        _application(
          afterP3a,
        ).apply(token: afterP3a.principal.token, lease: _leaseAt(afterP3a, 4)),
        throwsA(isA<StateError>()),
      );
      expect(await afterP3a.p3e.listHaltApplications('org_1'), hasLength(1));
      expect(
        (await afterP3a.control.readJson('rollouts', 'rollout_1'))!['state'],
        'HALTED',
      );
      afterP3a.advanceClock(now.add(const Duration(seconds: 1)));
      final afterP3aRecovered =
          await _recovery(
            afterP3a,
            now.add(const Duration(seconds: 1)),
          ).recover(
            token: afterP3a.principal.token,
            scope: afterP3a.lease.scope,
            workId: afterP3a.workId,
          );
      expect(
        afterP3aRecovered.outcome,
        P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid,
      );
      expect(await afterP3a.p3e.listHaltApplications('org_1'), hasLength(1));

      final missingAudit = await _Fixture.file(
        now,
        principalLifetime: const Duration(days: 7),
        controlDecorator: (delegate) => _AuditFaultControlStore(
          delegate,
          drop: (record) => record['action'] == 'health.auto_halt_applied',
        ),
      );
      addTearDown(missingAudit.close);
      await missingAudit.service.applyIntent(
        token: missingAudit.principal.token,
        lease: missingAudit.lease,
      );
      final applied = await _application(missingAudit).apply(
        token: missingAudit.principal.token,
        lease: _leaseAt(missingAudit, 4),
      );
      expect(applied.work.status, ScheduledEvaluationWorkStatus.completed);
      expect(
        await missingAudit.p3e.listHaltApplications('org_1'),
        hasLength(1),
      );
      expect(
        (await missingAudit.control.readJson(
          'rollouts',
          'rollout_1',
        ))!['state'],
        'HALTED',
      );
      final audit = await missingAudit.control.readAuditChain();
      expect(audit.toString(), isNot(contains(missingAudit.principal.token)));
      expect(audit.toString(), isNot(contains(_leaseToken)));
      expect(verifyAuditChain(audit).valid, isTrue);
      final firstAudit = audit.first;
      final firstBody = Map<String, Object?>.from(
        (firstAudit['body']! as Map).cast<String, Object?>(),
      );
      await expectLater(
        missingAudit.control.appendAudit(
          firstAudit['auditId']! as String,
          firstBody,
        ),
        throwsA(isA<StorageConflict>()),
      );
      expect(
        (await missingAudit.control.readAuditChain()),
        hasLength(audit.length),
      );
      await missingAudit.control.replaceJson(
        'audit_chain',
        firstAudit['auditId']! as String,
        <String, Object?>{
          ...firstAudit,
          'body': <String, Object?>{...firstBody, 'action': 'tampered'},
        },
      );
      expect(
        verifyAuditChain(await missingAudit.control.readAuditChain()).valid,
        isFalse,
      );
    },
  );

  test(
    'Task 67 measures bounded File critical path and contention envelope',
    () async {
      final samples = <int>[];
      for (var index = 0; index < 8; index++) {
        final fixture = await _Fixture.file(
          now.add(Duration(seconds: index)),
          leaseDuration: const Duration(seconds: 2),
        );
        try {
          final started = Stopwatch()..start();
          await fixture.service.applyIntent(
            token: fixture.principal.token,
            lease: fixture.lease,
          );
          await _application(
            fixture,
          ).apply(token: fixture.principal.token, lease: _leaseAt(fixture, 4));
          samples.add(started.elapsedMicroseconds);
        } finally {
          await fixture.close();
        }
      }
      final contended = await _Fixture.file(
        now,
        leaseDuration: const Duration(microseconds: 1),
      );
      addTearDown(contended.close);
      await contended.service.applyIntent(
        token: contended.principal.token,
        lease: contended.lease,
      );
      contended.advanceClock(now.add(const Duration(seconds: 1)));
      final contentionStarted = Stopwatch()..start();
      final outcomes = await Future.wait(
        List<Future<P3e5AutomaticHaltRecoveryResult>>.generate(
          8,
          (_) =>
              _recovery(contended, now.add(const Duration(seconds: 1))).recover(
                token: contended.principal.token,
                scope: contended.lease.scope,
                workId: contended.workId,
              ),
        ),
      );
      final contentionMicros = contentionStarted.elapsedMicroseconds;
      final sorted = [...samples]..sort();
      final p95 = sorted[(sorted.length * 95 + 99) ~/ 100 - 1];
      expect(sorted.first, greaterThan(0));
      expect(p95, lessThan(2000000));
      expect(
        outcomes,
        everyElement(
          predicate<P3e5AutomaticHaltRecoveryResult>(
            (result) =>
                result.outcome ==
                    P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid ||
                result.outcome ==
                    P3e5AutomaticHaltRecoveryOutcome
                        .applicationNotFoundRetryable ||
                result.outcome ==
                    P3e5AutomaticHaltRecoveryOutcome.applicationConflict,
          ),
        ),
      );
      expect(await contended.p3e.listHaltApplications('org_1'), hasLength(1));
      print(
        'P3E5_4E_TEST_ENVELOPE samples_us=$samples '
        'min_us=${sorted.first} median_us=${sorted[sorted.length ~/ 2]} '
        'p95_us=$p95 max_us=${sorted.last} '
        'contention_callers=8 contention_us=$contentionMicros',
      );
    },
  );

  test(
    'Task 67 provider-like PostgreSQL close/reopen preserves one halt',
    () async {
      final pgNow = DateTime.now().toUtc();
      final source = await _Fixture.file(
        pgNow,
        principalLifetime: const Duration(days: 7),
        leaseDuration: const Duration(microseconds: 1),
      );
      addTearDown(source.close);
      await source.service.applyIntent(
        token: source.principal.token,
        lease: source.lease,
      );
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final organizationId = 'org_p3e5e_$suffix';
      final control = PostgresControlPlaneStore(postgresUrl!);
      final p3e = PostgresP3ePersistenceStore(postgresUrl);
      final disconnected = PostgresP3e5ScheduleStore(postgresUrl);
      await Future.wait(<Future<void>>[
        control.initialize(),
        p3e.initialize(),
        disconnected.initialize(),
      ]);
      addTearDown(() async {
        await disconnected.close();
        await p3e.close();
        await control.close();
      });
      final credential = await _copyFixtureToPostgres(
        source,
        control,
        p3e,
        disconnected,
        organizationId,
        suffix,
      );
      final scope = P3e5ClaimScope(
        organizationId: organizationId,
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
      );
      final workId = (await disconnected.listWork(organizationId))
          .single
          .workId;

      await disconnected.close();
      final reconnected = PostgresP3e5ScheduleStore(postgresUrl);
      await reconnected.initialize();
      addTearDown(reconnected.close);
      expect((await reconnected.readWork(organizationId, workId)), isNotNull);

      var lostReclaimResponse = true;
      final reclaiming = PostgresP3e5ScheduleStore(
        postgresUrl,
        automaticHaltReclaimFailure: (point) {
          if (point == P3e5AutomaticHaltReclaimFailurePoint.afterCommit &&
              lostReclaimResponse) {
            lostReclaimResponse = false;
            throw StateError('TEST VECTOR ONLY provider-like disconnect');
          }
        },
      );
      await reclaiming.initialize();
      addTearDown(reclaiming.close);
      final recovery = P3e5AutomaticHaltRecoveryService(
        controlStore: control,
        scheduleStore: reclaiming,
        p3eStore: p3e,
        controlService: ControlPlaneService(store: control, p3eStore: p3e),
        leasePolicy: const P3e5LeasePolicy(
          version: 1,
          duration: Duration(milliseconds: 50),
        ),
        limits: const P3e5AutomaticHaltRecoveryLimits(
          maximumRecoveryAttempts: 1,
          maximumApplicationRecords: 8,
          maximumLinkageRecords: 8,
        ),
        recoveryOwner: 'provider_like_left',
        clock: () => DateTime.now().toUtc(),
        random: Random(647),
      );
      final lost = await recovery.recover(
        token: credential.token,
        scope: scope,
        workId: workId,
      );
      expect(
        lost.outcome,
        P3e5AutomaticHaltRecoveryOutcome.applicationConflict,
      );
      await reclaiming.close();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final rightSchedule = PostgresP3e5ScheduleStore(postgresUrl);
      await rightSchedule.initialize();
      addTearDown(rightSchedule.close);
      final recovered = P3e5AutomaticHaltRecoveryService(
        controlStore: control,
        scheduleStore: rightSchedule,
        p3eStore: p3e,
        controlService: ControlPlaneService(store: control, p3eStore: p3e),
        leasePolicy: const P3e5LeasePolicy(
          version: 1,
          duration: Duration(seconds: 5),
        ),
        limits: const P3e5AutomaticHaltRecoveryLimits(
          maximumRecoveryAttempts: 2,
          maximumApplicationRecords: 8,
          maximumLinkageRecords: 8,
        ),
        recoveryOwner: 'provider_like_right',
        clock: () => DateTime.now().toUtc(),
        random: Random(648),
      );
      final result = await recovered.recover(
        token: credential.token,
        scope: scope,
        workId: workId,
      );
      expect(
        result.outcome,
        P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid,
      );
      expect(await p3e.listHaltApplications(organizationId), hasLength(1));
      expect(
        (await rightSchedule.readWork(organizationId, workId))?.status,
        ScheduledEvaluationWorkStatus.completed,
      );
      final rollout = RolloutRecord.fromJson(
        (await control.readJson('rollouts', 'rollout_$suffix'))!,
      );
      expect(rollout.state, RolloutState.halted);
      expect(rollout.currentRevision, 2);
    },
    skip: postgresUrl == null
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );

  test(
    'Task 67 PostgreSQL bounded recovery race envelope has one semantic halt',
    () async {
      final pgNow = DateTime.now().toUtc();
      final source = await _Fixture.file(
        pgNow,
        principalLifetime: const Duration(days: 7),
        leaseDuration: const Duration(microseconds: 1),
      );
      addTearDown(source.close);
      await source.service.applyIntent(
        token: source.principal.token,
        lease: source.lease,
      );
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final organizationId = 'org_p3e5e_storm_$suffix';
      final bootstrapControl = PostgresControlPlaneStore(postgresUrl!);
      final bootstrapP3e = PostgresP3ePersistenceStore(postgresUrl);
      final bootstrapSchedule = PostgresP3e5ScheduleStore(postgresUrl);
      await Future.wait(<Future<void>>[
        bootstrapControl.initialize(),
        bootstrapP3e.initialize(),
        bootstrapSchedule.initialize(),
      ]);
      final credential = await _copyFixtureToPostgres(
        source,
        bootstrapControl,
        bootstrapP3e,
        bootstrapSchedule,
        organizationId,
        suffix,
      );
      final workId = (await bootstrapSchedule.listWork(organizationId))
          .single
          .workId;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await bootstrapSchedule.close();
      await bootstrapP3e.close();
      await bootstrapControl.close();

      final stores =
          <
            (
              PostgresControlPlaneStore,
              PostgresP3ePersistenceStore,
              PostgresP3e5ScheduleStore,
            )
          >[];
      final scope = P3e5ClaimScope(
        organizationId: organizationId,
        applicationId: 'app_$suffix',
        environmentId: 'env_$suffix',
      );
      final started = Stopwatch()..start();
      final futures = <Future<P3e5AutomaticHaltRecoveryResult>>[];
      for (var index = 0; index < 8; index++) {
        final control = PostgresControlPlaneStore(postgresUrl);
        final p3e = PostgresP3ePersistenceStore(postgresUrl);
        final schedule = PostgresP3e5ScheduleStore(postgresUrl);
        stores.add((control, p3e, schedule));
        await Future.wait(<Future<void>>[
          control.initialize(),
          p3e.initialize(),
          schedule.initialize(),
        ]);
        final service = P3e5AutomaticHaltRecoveryService(
          controlStore: control,
          scheduleStore: schedule,
          p3eStore: p3e,
          controlService: ControlPlaneService(store: control, p3eStore: p3e),
          leasePolicy: const P3e5LeasePolicy(
            version: 1,
            duration: Duration(seconds: 2),
          ),
          limits: const P3e5AutomaticHaltRecoveryLimits(
            maximumRecoveryAttempts: 5,
            maximumApplicationRecords: 8,
            maximumLinkageRecords: 8,
          ),
          recoveryOwner: 'storm_$index',
          clock: () => DateTime.now().toUtc(),
          random: Random(649 + index),
        );
        futures.add(
          service.recover(
            token: credential.token,
            scope: scope,
            workId: workId,
          ),
        );
      }
      final results = await Future.wait(futures);
      final elapsed = started.elapsedMicroseconds;
      for (final store in stores) {
        await store.$3.close();
        await store.$2.close();
        await store.$1.close();
      }
      expect(
        results,
        everyElement(
          predicate<P3e5AutomaticHaltRecoveryResult>(
            (result) =>
                result.outcome ==
                    P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid ||
                result.outcome ==
                    P3e5AutomaticHaltRecoveryOutcome.applicationConflict ||
                result.outcome ==
                    P3e5AutomaticHaltRecoveryOutcome
                        .applicationNotFoundRetryable,
          ),
        ),
      );
      final verifyControl = PostgresControlPlaneStore(postgresUrl);
      final verifyP3e = PostgresP3ePersistenceStore(postgresUrl);
      final verifySchedule = PostgresP3e5ScheduleStore(postgresUrl);
      await Future.wait(<Future<void>>[
        verifyControl.initialize(),
        verifyP3e.initialize(),
        verifySchedule.initialize(),
      ]);
      addTearDown(() async {
        await verifySchedule.close();
        await verifyP3e.close();
        await verifyControl.close();
      });
      expect(
        await verifyP3e.listHaltApplications(organizationId),
        hasLength(1),
      );
      expect(
        (await verifySchedule.readWork(organizationId, workId))?.status,
        ScheduledEvaluationWorkStatus.completed,
      );
      print(
        'P3E5_4E_PG_ENVELOPE callers=8 elapsed_us=$elapsed '
        'outcomes=${results.map((result) => result.outcome.wireName).toList()}',
      );
    },
    skip: postgresUrl == null
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );

  test(
    'Task 67 exact PostgreSQL claim boundary faults are independently recoverable',
    () async {
      final state = await _task67PostgresFixture(
        postgresUrl!,
        now: DateTime.now().toUtc(),
        pendingWork: true,
        claimFailure: (point) {
          if (point == P3e5PostgresClaimFailurePoint.beforeCommit) {
            throw StateError('TEST VECTOR ONLY PostgreSQL disconnect A1');
          }
        },
      );
      addTearDown(state.close);
      final request = _task67ClaimRequest(
        state.scope,
        owner: 'claim_before_commit',
        token: 'claim_before_commit_0123456789abcdefghijklmnopqrstuvwxyz',
        leaseDuration: const Duration(seconds: 5),
      );
      await expectLater(
        state.schedules.claimDue(request),
        throwsA(isA<StateError>()),
      );
      await state.close();

      final reconnected = PostgresP3e5ScheduleStore(postgresUrl);
      await reconnected.initialize();
      addTearDown(reconnected.close);
      final beforeRetry = await reconnected.readWork(
        state.organizationId,
        state.workId,
      );
      expect(beforeRetry?.status, ScheduledEvaluationWorkStatus.pending);
      expect(beforeRetry?.workVersion, 0);
      expect(beforeRetry?.attemptCount, 0);
      expect(beforeRetry?.leaseOwner, isNull);
      expect(
        await reconnected.listAttempts(state.organizationId, state.workId),
        isEmpty,
      );

      final retry = (await reconnected.claimDue(
        _task67ClaimRequest(
          state.scope,
          owner: 'claim_before_commit_retry',
          token:
              'claim_before_commit_retry_0123456789abcdefghijklmnopqrstuvwxyz',
          leaseDuration: const Duration(seconds: 5),
        ),
      )).single;
      expect(retry.work.status, ScheduledEvaluationWorkStatus.leased);
      expect(retry.work.workVersion, 1);
      expect(retry.work.attemptCount, 1);
      expect(retry.work.leaseOwner, 'claim_before_commit_retry');
      expect(
        await reconnected.listAttempts(state.organizationId, state.workId),
        hasLength(1),
      );
    },
    skip: postgresUrl == null
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );

  test(
    'Task 67 exact PostgreSQL post-claim response loss preserves one lease',
    () async {
      var injected = true;
      final state = await _task67PostgresFixture(
        postgresUrl!,
        now: DateTime.now().toUtc(),
        pendingWork: true,
        claimFailure: (point) {
          if (point == P3e5PostgresClaimFailurePoint.afterCommit && injected) {
            injected = false;
            throw StateError('TEST VECTOR ONLY PostgreSQL disconnect A2');
          }
        },
      );
      addTearDown(state.close);
      await expectLater(
        state.schedules.claimDue(
          _task67ClaimRequest(
            state.scope,
            owner: 'claim_after_commit',
            token: 'claim_after_commit_0123456789abcdefghijklmnopqrstuvwxyz',
            leaseDuration: const Duration(seconds: 2),
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        await state.schedules.claimDue(
          _task67ClaimRequest(
            state.scope,
            owner: 'claim_after_commit_retry',
            token:
                'claim_after_commit_retry_0123456789abcdefghijklmnopqrstuvwxyz',
            leaseDuration: const Duration(seconds: 5),
          ),
        ),
        isEmpty,
      );
      await state.close();

      final reconnected = PostgresP3e5ScheduleStore(postgresUrl);
      await reconnected.initialize();
      addTearDown(reconnected.close);
      final committed = await reconnected.readWork(
        state.organizationId,
        state.workId,
      );
      expect(committed?.status, ScheduledEvaluationWorkStatus.leased);
      expect(committed?.workVersion, 1);
      expect(committed?.attemptCount, 1);
      expect(committed?.leaseOwner, 'claim_after_commit');
      expect(
        await reconnected.listAttempts(state.organizationId, state.workId),
        hasLength(1),
      );

      await Future<void>.delayed(const Duration(seconds: 2, milliseconds: 200));
      final reclaimed = (await reconnected.claimDue(
        _task67ClaimRequest(
          state.scope,
          owner: 'claim_after_commit_recovery',
          token: 'claim_after_commit_recovery_0123456789abcdefghijklmnopqrstuvwxyz',
          leaseDuration: const Duration(seconds: 5),
        ),
      )).single;
      expect(reclaimed.reclaimed, isTrue);
      expect(reclaimed.work.status, ScheduledEvaluationWorkStatus.leased);
      expect(reclaimed.work.workVersion, 2);
      expect(reclaimed.work.attemptCount, 2);
      expect(reclaimed.work.leaseOwner, 'claim_after_commit_recovery');
      expect(
        await reconnected.listAttempts(state.organizationId, state.workId),
        hasLength(2),
      );
    },
    skip: postgresUrl == null
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );

  test(
    'Task 67 exact PostgreSQL pre-P3A response fault distinguishes rollback',
    () async {
      final now = DateTime.now().toUtc();
      final state = await _task67PostgresFixture(
        postgresUrl!,
        now: now,
        transitionFailure: (point) {
          if (point == PostgresRolloutTransitionFailurePoint.beforeCommit) {
            throw StateError('TEST VECTOR ONLY PostgreSQL disconnect A3');
          }
        },
      );
      addTearDown(state.close);
      final evaluated = await state.schedules.readWork(
        state.organizationId,
        state.workId,
      );
      final rolloutId = evaluated!.logicalKey.rolloutId;
      final intentLease = _task67Lease(state, evaluated);
      final intent = await P3e5AutomaticHaltApplicabilityService(
        controlStore: state.control,
        scheduleStore: state.schedules,
        p3eStore: state.p3e,
        clock: () => now,
      ).applyIntent(token: state.autoHalt.token, lease: intentLease);
      final applicationLease = _task67Lease(state, intent.work);
      final failingApplication = P3e5AutomaticHaltApplicationService(
        controlStore: state.control,
        scheduleStore: state.schedules,
        p3eStore: state.p3e,
        controlService: ControlPlaneService(
          store: state.control,
          p3eStore: state.p3e,
          clock: () => now,
        ),
        clock: () => now,
      );
      await expectLater(
        failingApplication.apply(
          token: state.autoHalt.token,
          lease: applicationLease,
        ),
        throwsA(isA<StateError>()),
      );
      await state.close();

      final retryControl = PostgresControlPlaneStore(postgresUrl);
      final retryP3e = PostgresP3ePersistenceStore(postgresUrl);
      final retrySchedule = PostgresP3e5ScheduleStore(postgresUrl);
      await Future.wait(<Future<void>>[
        retryControl.initialize(),
        retryP3e.initialize(),
        retrySchedule.initialize(),
      ]);
      addTearDown(() async {
        await retrySchedule.close();
        await retryP3e.close();
        await retryControl.close();
      });
      expect(
        (await retryControl.listJson('rollout_revisions'))
            .where((raw) => raw['rolloutId'] == rolloutId),
        hasLength(1),
      );
      expect(
        await retryP3e.listHaltApplications(state.organizationId),
        isEmpty,
      );
      final retryApplication = P3e5AutomaticHaltApplicationService(
        controlStore: retryControl,
        scheduleStore: retrySchedule,
        p3eStore: retryP3e,
        controlService: ControlPlaneService(
          store: retryControl,
          p3eStore: retryP3e,
          clock: () => now,
        ),
        clock: () => now,
      );
      await retryApplication.apply(
        token: state.autoHalt.token,
        lease: applicationLease,
      );
      expect(
        (await retryControl.listJson('rollout_revisions'))
            .where((raw) => raw['rolloutId'] == rolloutId),
        hasLength(2),
      );
      expect(
        await retryP3e.listHaltApplications(state.organizationId),
        hasLength(1),
      );
      expect(
        (await retrySchedule.readWork(
          state.organizationId,
          state.workId,
        ))?.status,
        ScheduledEvaluationWorkStatus.completed,
      );
    },
    skip: postgresUrl == null
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );

  test(
    'Task 67 exact PostgreSQL post-P3A response fault recovers one halt',
    () async {
      final now = DateTime.now().toUtc();
      var injected = true;
      final state = await _task67PostgresFixture(
        postgresUrl!,
        now: now,
        transitionFailure: (point) {
          if (point == PostgresRolloutTransitionFailurePoint.afterCommit &&
              injected) {
            injected = false;
            throw StateError('TEST VECTOR ONLY PostgreSQL disconnect A4');
          }
        },
      );
      addTearDown(state.close);
      final evaluated = await state.schedules.readWork(
        state.organizationId,
        state.workId,
      );
      final rolloutId = evaluated!.logicalKey.rolloutId;
      final intentLease = _task67Lease(state, evaluated);
      final intent = await P3e5AutomaticHaltApplicabilityService(
        controlStore: state.control,
        scheduleStore: state.schedules,
        p3eStore: state.p3e,
        clock: () => now,
      ).applyIntent(token: state.autoHalt.token, lease: intentLease);
      final applicationLease = _task67Lease(state, intent.work);
      final failingApplication = P3e5AutomaticHaltApplicationService(
        controlStore: state.control,
        scheduleStore: state.schedules,
        p3eStore: state.p3e,
        controlService: ControlPlaneService(
          store: state.control,
          p3eStore: state.p3e,
          clock: () => now,
        ),
        clock: () => now,
      );
      await expectLater(
        failingApplication.apply(
          token: state.autoHalt.token,
          lease: applicationLease,
        ),
        throwsA(isA<StateError>()),
      );
      await state.close();

      final retryControl = PostgresControlPlaneStore(postgresUrl);
      final retryP3e = PostgresP3ePersistenceStore(postgresUrl);
      final retrySchedule = PostgresP3e5ScheduleStore(postgresUrl);
      await Future.wait(<Future<void>>[
        retryControl.initialize(),
        retryP3e.initialize(),
        retrySchedule.initialize(),
      ]);
      addTearDown(() async {
        await retrySchedule.close();
        await retryP3e.close();
        await retryControl.close();
      });
      final afterCommit = (await retryControl.listJson('rollout_revisions'))
          .where((raw) => raw['rolloutId'] == rolloutId)
          .toList(growable: false);
      expect(afterCommit, hasLength(2));
      expect(
        RolloutRevision.fromJson(afterCommit.last).state,
        RolloutState.halted,
      );
      expect(
        await retryP3e.listHaltApplications(state.organizationId),
        isEmpty,
      );
      await P3e5AutomaticHaltApplicationService(
        controlStore: retryControl,
        scheduleStore: retrySchedule,
        p3eStore: retryP3e,
        controlService: ControlPlaneService(
          store: retryControl,
          p3eStore: retryP3e,
          clock: () => now,
        ),
        clock: () => now,
      ).apply(token: state.autoHalt.token, lease: applicationLease);
      expect(
        (await retryControl.listJson('rollout_revisions'))
            .where((raw) => raw['rolloutId'] == rolloutId),
        hasLength(2),
      );
      expect(
        await retryP3e.listHaltApplications(state.organizationId),
        hasLength(1),
      );
      expect(
        (await retrySchedule.readWork(
          state.organizationId,
          state.workId,
        ))?.status,
        ScheduledEvaluationWorkStatus.completed,
      );
    },
    skip: postgresUrl == null
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );

  test(
    'Task 67 single-call P3E5-3 to P3E5-4 rehearsal preserves two authorities',
    () async {
      const decisions = <String>[
        'CONTINUE',
        'HOLD',
        'INSUFFICIENT_DATA',
        'MANUAL_REVIEW',
        'HALT_NEW_OFFERS',
      ];
      for (var index = 0; index < decisions.length; index++) {
        final decision = decisions[index];
        final fixture = await _Fixture.file(
          _task67ReferenceNow,
          decisionValue: decision,
          leaseExpired: true,
          evaluationPolicyDigest: _task67EvaluationPolicy().policyDigest,
        );
        addTearDown(fixture.close);
        final scheduler = await _task67Scheduler(fixture, index);
        final integration = P3e5AutomaticHaltIntegrationService(
          controlStore: fixture.control,
          scheduleStore: fixture.schedules,
          p3eStore: fixture.p3e,
          controlService: ControlPlaneService(
            store: fixture.control,
            p3eStore: fixture.p3e,
            clock: () => _task67ReferenceNow,
          ),
          clock: () => _task67ReferenceNow,
          random: Random(670 + index),
        );
        final result = await integration.invoke(
          evaluationTenant: _task67Tenant(fixture, scheduler.token),
          autoHaltToken: fixture.principal.token,
          resourcePolicy: _task67ExecutorResourcePolicy,
          requestId: 'task67-rehearsal-$index',
        );
        expect(result.execution.outcomes, hasLength(1));
        expect(result.execution.outcomes.single.decision.decision, decision);
        expect(
          result.applications,
          hasLength(decision == 'HALT_NEW_OFFERS' ? 1 : 0),
        );
        expect(
          await fixture.p3e.listHaltApplications('org_1'),
          hasLength(decision == 'HALT_NEW_OFFERS' ? 1 : 0),
        );
        final rollout = RolloutRecord.fromJson(
          (await fixture.control.readJson('rollouts', 'rollout_1'))!,
        );
        expect(rollout.currentRevision, decision == 'HALT_NEW_OFFERS' ? 2 : 1);
        expect(
          rollout.state,
          decision == 'HALT_NEW_OFFERS'
              ? RolloutState.halted
              : RolloutState.canary,
        );
        expect(
          (await fixture.schedules.readWork('org_1', fixture.workId))?.status,
          ScheduledEvaluationWorkStatus.completed,
        );
      }
    },
  );

  test(
    'Task 67 authority separation rejects missing or wrong-scope principals',
    () async {
      final evaluationOnly = await _Fixture.file(
        _task67ReferenceNow,
        pendingWork: true,
        evaluationPolicyDigest: _task67EvaluationPolicy().policyDigest,
      );
      addTearDown(evaluationOnly.close);
      final evaluationResult =
          await P3e5ExplicitExecutorService(
            controlStore: evaluationOnly.control,
            scheduleStore: evaluationOnly.schedules,
            p3eStore: evaluationOnly.p3e,
            controlService: ControlPlaneService(
              store: evaluationOnly.control,
              p3eStore: evaluationOnly.p3e,
              clock: () => _task67ReferenceNow,
            ),
            clock: () => _task67ReferenceNow,
          ).invoke(
            tenants: <P3e5TenantExecutionInput>[
              _task67Tenant(evaluationOnly, evaluationOnly.scheduler!.token),
            ],
            resourcePolicy: _task67ExecutorResourcePolicy,
          );
      expect(evaluationResult.outcomes, hasLength(1));
      expect(await evaluationOnly.p3e.listHaltApplications('org_1'), isEmpty);
      expect(
        RolloutRecord.fromJson(
          (await evaluationOnly.control.readJson('rollouts', 'rollout_1'))!,
        ).currentRevision,
        1,
      );

      final missingEvaluator = await _Fixture.file(
        _task67ReferenceNow,
        pendingWork: true,
      );
      addTearDown(missingEvaluator.close);
      final before = await missingEvaluator.schedules.readWork(
        'org_1',
        missingEvaluator.workId,
      );
      await expectLater(
        P3e5AutomaticHaltIntegrationService(
          controlStore: missingEvaluator.control,
          scheduleStore: missingEvaluator.schedules,
          p3eStore: missingEvaluator.p3e,
          controlService: ControlPlaneService(
            store: missingEvaluator.control,
            p3eStore: missingEvaluator.p3e,
            clock: () => _task67ReferenceNow,
          ),
          clock: () => _task67ReferenceNow,
        ).invoke(
          evaluationTenant: _task67Tenant(
            missingEvaluator,
            missingEvaluator.principal.token,
          ),
          autoHaltToken: missingEvaluator.principal.token,
          resourcePolicy: _task67ExecutorResourcePolicy,
        ),
        throwsA(isA<ControlPlaneException>()),
      );
      expect(
        await missingEvaluator.schedules.readWork(
          'org_1',
          missingEvaluator.workId,
        ),
        predicate<ScheduledEvaluationWork>(
          (work) =>
              work.status == ScheduledEvaluationWorkStatus.pending &&
              work.workVersion == before!.workVersion,
        ),
      );

      final wrongScope = await _Fixture.file(
        _task67ReferenceNow,
        pendingWork: true,
      );
      addTearDown(wrongScope.close);
      final wrongCredential = CredentialService(random: Random(679)).issue(
        id: 'wrong_auto_halt',
        organizationId: 'org_1',
        kind: CredentialKind.autoHalt,
        scopes: autoHaltScopes,
        applicationId: 'app_wrong',
        environmentId: 'env_wrong',
        expiresAt: _task67ReferenceNow.add(const Duration(days: 1)),
      );
      await wrongScope.control.createJson(
        'credentials',
        wrongCredential.record.tokenHash,
        wrongCredential.record.toJson(),
      );
      final scheduler = await _task67Scheduler(wrongScope, 679);
      await expectLater(
        P3e5AutomaticHaltIntegrationService(
          controlStore: wrongScope.control,
          scheduleStore: wrongScope.schedules,
          p3eStore: wrongScope.p3e,
          controlService: ControlPlaneService(
            store: wrongScope.control,
            p3eStore: wrongScope.p3e,
            clock: () => _task67ReferenceNow,
          ),
          clock: () => _task67ReferenceNow,
        ).invoke(
          evaluationTenant: _task67Tenant(wrongScope, scheduler.token),
          autoHaltToken: wrongCredential.token,
          resourcePolicy: _task67ExecutorResourcePolicy,
        ),
        throwsA(isA<ControlPlaneException>()),
      );
      expect(
        (await wrongScope.schedules.readWork(
          'org_1',
          wrongScope.workId,
        ))?.status,
        ScheduledEvaluationWorkStatus.pending,
      );
    },
  );
}

const _task67ClaimPolicy = P3e5ClaimResourcePolicy(
  version: 1,
  claimBatchSize: 1,
  pendingConsiderationLimit: 8,
  maximumActiveLeasesPerTenant: 1,
  recoveryScanBatch: 8,
);

const _task67ExecutorResourcePolicy = P3e5ExecutorResourcePolicy(
  version: 1,
  claimBatchSize: 1,
  maximumWorksPerInvocation: 1,
  maximumEvaluationDurationBudget: Duration(seconds: 5),
  maximumAggregateRecordsPerWork: 8,
  maximumRetriesProcessedPerInvocation: 2,
  maximumTenantScopes: 1,
  crossTenantFairness: P3e5CrossTenantFairness.roundRobinCursor,
);

const _task67LeasePolicy = P3e5LeasePolicy(
  version: 1,
  duration: Duration(seconds: 5),
);

const _task67RetryPolicy = P3e5RetryPolicy(
  version: 1,
  initialDelay: Duration(seconds: 1),
  maximumDelay: Duration(seconds: 4),
  maximumAttempts: 4,
  jitterMode: P3e5JitterMode.none,
  jitterBound: Duration.zero,
);

P3e5ClaimRequest _task67ClaimRequest(
  P3e5ClaimScope scope, {
  required String owner,
  required String token,
  required Duration leaseDuration,
}) => P3e5ClaimRequest(
  scope: scope,
  leaseOwner: owner,
  leasePolicy: P3e5LeasePolicy(version: 1, duration: leaseDuration),
  resourcePolicy: _task67ClaimPolicy,
  preparedLeases: <P3e5PreparedLease>[P3e5PreparedLease(token)],
);

P3e5TenantExecutionInput _task67Tenant(_Fixture fixture, String token) =>
    P3e5TenantExecutionInput(
      token: token,
      scope: fixture.lease.scope,
      leaseOwner: 'task67-evaluator',
      leasePolicy: _task67LeasePolicy,
      retryPolicy: _task67RetryPolicy,
      claimResourcePolicy: _task67ClaimPolicy,
      evaluationPolicy: _task67EvaluationPolicy(),
    );

ManualEvaluationPolicy _task67EvaluationPolicy() => ManualEvaluationPolicy(
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
  maximumQuarantineRateBasisPoints: 10000,
  maximumRejectedRateBasisPoints: 10000,
  maximumLateRateBasisPoints: 10000,
  haltActivationFailureRateBasisPoints: 5000,
  haltAdmissionRejectionRateBasisPoints: null,
  haltRuntimeFaultRateBasisPoints: null,
  haltRollbackFallbackRateBasisPoints: null,
);

Future<IssuedCredential> _task67Scheduler(_Fixture fixture, int suffix) async {
  final issued = CredentialService(random: Random(680 + suffix)).issue(
    id: 'scheduler_task67_$suffix',
    organizationId: 'org_1',
    kind: CredentialKind.scheduler,
    scopes: evaluationOnlySchedulerScopes,
    applicationId: 'app_1',
    environmentId: 'env_1',
    expiresAt: _task67ReferenceNow.add(const Duration(days: 1)),
  );
  await fixture.control.createJson(
    'credentials',
    issued.record.tokenHash,
    issued.record.toJson(),
  );
  return issued;
}

P3e5LeaseMutation _task67Lease(
  _Task67PostgresFixture state,
  ScheduledEvaluationWork work,
) => P3e5LeaseMutation(
  scope: state.scope,
  workId: work.workId,
  expectedWorkVersion: work.workVersion,
  leaseOwner: work.leaseOwner ?? 'executor_1',
  rawLeaseToken: _leaseToken,
);

final class _Task67PostgresFixture {
  _Task67PostgresFixture({
    required this.source,
    required this.control,
    required this.p3e,
    required this.schedules,
    required this.autoHalt,
    required this.organizationId,
    required this.scope,
    required this.workId,
  });

  final _Fixture source;
  final PostgresControlPlaneStore control;
  final PostgresP3ePersistenceStore p3e;
  final PostgresP3e5ScheduleStore schedules;
  final IssuedCredential autoHalt;
  final String organizationId;
  final P3e5ClaimScope scope;
  final String workId;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await schedules.close();
    await p3e.close();
    await control.close();
    await source.close();
  }
}

Future<_Task67PostgresFixture> _task67PostgresFixture(
  String postgresUrl, {
  required DateTime now,
  bool pendingWork = false,
  void Function(P3e5PostgresClaimFailurePoint point)? claimFailure,
  void Function(PostgresRolloutTransitionFailurePoint point)? transitionFailure,
}) async {
  final source = await _Fixture.file(
    now,
    pendingWork: pendingWork,
    principalLifetime: const Duration(days: 7),
    leaseDuration: const Duration(days: 1),
  );
  final control = PostgresControlPlaneStore(
    postgresUrl,
    rolloutTransitionFailure: transitionFailure,
  );
  final p3e = PostgresP3ePersistenceStore(postgresUrl);
  final schedules = PostgresP3e5ScheduleStore(
    postgresUrl,
    claimFailure: claimFailure,
  );
  await Future.wait(<Future<void>>[
    control.initialize(),
    p3e.initialize(),
    schedules.initialize(),
  ]);
  final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final organizationId = 'org_task67_$suffix';
  final autoHalt = await _copyFixtureToPostgres(
    source,
    control,
    p3e,
    schedules,
    organizationId,
    suffix,
  );
  final work = (await schedules.listWork(organizationId)).single;
  return _Task67PostgresFixture(
    source: source,
    control: control,
    p3e: p3e,
    schedules: schedules,
    autoHalt: autoHalt,
    organizationId: organizationId,
    scope: P3e5ClaimScope(
      organizationId: organizationId,
      applicationId: work.logicalKey.applicationId,
      environmentId: work.logicalKey.environmentId,
    ),
    workId: work.workId,
  );
}

AutomaticHaltIntent _intent(
  DateTime now, {
  String principalId = 'principal_auto_halt',
}) => AutomaticHaltIntent(
  workId: 'work_1',
  attemptId: 'attempt_1',
  evaluationId: 'evaluation_1',
  decisionId: 'decision_1',
  scheduleRevisionId: 'schedule_revision_1',
  automaticHaltPolicyVersion: 1,
  automaticHaltPolicyDigest: _digest('policy'),
  expectedRolloutRevision: 1,
  targetBindingDigest: _digest('target'),
  authorizedPrincipalId: principalId,
  authorizedAt: now,
);

String _digest(String value) => sha256Digest(value.codeUnits);

const _leaseToken =
    'lease_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

final _task67ReferenceNow = DateTime.utc(2026, 8, 24, 21);

P3e5AutomaticHaltRecoveryService _recovery(
  _Fixture fixture,
  DateTime recoveryNow, {
  P3e5ScheduleStore? scheduleStore,
  P3e5AutomaticHaltRecoveryLimits limits =
      const P3e5AutomaticHaltRecoveryLimits(
        maximumRecoveryAttempts: 2,
        maximumApplicationRecords: 8,
        maximumLinkageRecords: 8,
      ),
}) => P3e5AutomaticHaltRecoveryService(
  controlStore: fixture.control,
  scheduleStore: scheduleStore ?? fixture.schedules,
  p3eStore: fixture.p3e,
  controlService: ControlPlaneService(
    store: fixture.control,
    p3eStore: fixture.p3e,
    clock: () => recoveryNow,
  ),
  leasePolicy: const P3e5LeasePolicy(
    version: 1,
    duration: Duration(minutes: 5),
  ),
  limits: limits,
  recoveryOwner: 'recovery_helper',
  clock: () => recoveryNow,
  random: Random(644),
);

P3e5AutomaticHaltApplicationService _application(
  _Fixture fixture, {
  DateTime Function()? clock,
}) => P3e5AutomaticHaltApplicationService(
  controlStore: fixture.control,
  scheduleStore: fixture.schedules,
  p3eStore: fixture.p3e,
  controlService: ControlPlaneService(
    store: fixture.control,
    p3eStore: fixture.p3e,
    clock: clock ?? (() => _task67ReferenceNow),
  ),
  clock: clock ?? (() => _task67ReferenceNow),
);

P3e5LeaseMutation _leaseAt(_Fixture fixture, int expectedWorkVersion) =>
    P3e5LeaseMutation(
      scope: fixture.lease.scope,
      workId: fixture.workId,
      expectedWorkVersion: expectedWorkVersion,
      leaseOwner: fixture.lease.leaseOwner,
      rawLeaseToken: fixture.lease.rawLeaseToken,
    );

final class _AuditFaultControlStore implements ControlPlaneStore {
  _AuditFaultControlStore(
    this.delegate, {
    this.failBefore,
    this.failAfter,
    this.drop,
  });

  final ControlPlaneStore delegate;
  final bool Function(Map<String, Object?> record)? failBefore;
  final bool Function(Map<String, Object?> record)? failAfter;
  final bool Function(Map<String, Object?> record)? drop;
  bool _failed = false;

  @override
  Future<void> initialize() => delegate.initialize();

  @override
  Future<void> close() => delegate.close();

  @override
  Future<void> checkReadiness() => delegate.checkReadiness();

  @override
  Future<Map<String, Object?>?> readJson(String collection, String id) =>
      delegate.readJson(collection, id);

  @override
  Future<List<Map<String, Object?>>> listJson(String collection) =>
      delegate.listJson(collection);

  @override
  Future<void> createJson(
    String collection,
    String id,
    Map<String, Object?> value,
  ) => delegate.createJson(collection, id, value);

  @override
  Future<void> replaceJson(
    String collection,
    String id,
    Map<String, Object?> value,
  ) => delegate.replaceJson(collection, id, value);

  @override
  Future<void> replaceJsonBatch(
    String collection,
    Map<String, Map<String, Object?>> values,
  ) => delegate.replaceJsonBatch(collection, values);

  @override
  Future<Map<String, Object?>?> touchSessionIfActive({
    required String id,
    required String expectedSecretHash,
    required DateTime now,
  }) => delegate.touchSessionIfActive(
    id: id,
    expectedSecretHash: expectedSecretHash,
    now: now,
  );

  @override
  Future<bool> revokeSessionIfActive({
    required String id,
    required String expectedSecretHash,
    required DateTime revokedAt,
  }) => delegate.revokeSessionIfActive(
    id: id,
    expectedSecretHash: expectedSecretHash,
    revokedAt: revokedAt,
  );

  @override
  Future<void> createIdempotency(
    String scope,
    String key,
    Map<String, Object?> value,
  ) => delegate.createIdempotency(scope, key, value);

  @override
  Future<Map<String, Object?>?> readIdempotency(String scope, String key) =>
      delegate.readIdempotency(scope, key);

  @override
  Future<void> appendAudit(String id, Map<String, Object?> value) async {
    final action = value['action'];
    final record = <String, Object?>{
      ...value,
      if (action is! String) 'action': '<unknown>',
    };
    if (!_failed && failBefore?.call(record) == true) {
      _failed = true;
      throw StateError('TEST VECTOR ONLY audit unavailable');
    }
    if (drop?.call(record) == true) return;
    await delegate.appendAudit(id, value);
    if (!_failed && failAfter?.call(record) == true) {
      _failed = true;
      throw StateError('TEST VECTOR ONLY audit response lost');
    }
  }

  @override
  Future<List<Map<String, Object?>>> readAuditChain() =>
      delegate.readAuditChain();

  @override
  Future<void> putArtifact(String digest, List<int> bytes) =>
      delegate.putArtifact(digest, bytes);

  @override
  Future<List<int>?> readArtifact(String digest) =>
      delegate.readArtifact(digest);

  @override
  Future<ObservationWriteResult> createObservation(
    String organizationId,
    String applicationId,
    String environmentId,
    String eventId,
    Map<String, Object?> value,
  ) => delegate.createObservation(
    organizationId,
    applicationId,
    environmentId,
    eventId,
    value,
  );

  @override
  Future<List<Map<String, Object?>>> listObservations({
    String? organizationId,
    String? applicationId,
    String? environmentId,
  }) => delegate.listObservations(
    organizationId: organizationId,
    applicationId: applicationId,
    environmentId: environmentId,
  );

  @override
  Future<int> deleteObservations({
    required String organizationId,
    String? applicationId,
    String? environmentId,
    required DateTime olderThan,
  }) => delegate.deleteObservations(
    organizationId: organizationId,
    applicationId: applicationId,
    environmentId: environmentId,
    olderThan: olderThan,
  );

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
  }) => delegate.commitRolloutTransition(
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
}

final class _Fixture {
  _Fixture._({
    required this.root,
    required this.control,
    required this.p3e,
    required this.schedules,
    required this.service,
    required this.principal,
    required this.scheduler,
    required this.lease,
    required this.workId,
    required this.advanceClock,
  });

  final Directory root;
  final ControlPlaneStore control;
  final P3ePersistenceStore p3e;
  final P3e5ScheduleStore schedules;
  final P3e5AutomaticHaltApplicabilityService service;
  final IssuedCredential principal;
  final IssuedCredential? scheduler;
  final P3e5LeaseMutation lease;
  final String workId;
  final void Function(DateTime value) advanceClock;

  static Future<_Fixture> file(
    DateTime now, {
    bool productionEnabled = true,
    bool principalRevoked = false,
    bool leaseExpired = false,
    bool failBeforeCommit = false,
    bool failAfterCommit = false,
    bool failCompletionAfterCommit = false,
    bool failReclaimAfterCommit = false,
    Duration principalLifetime = const Duration(days: 1),
    Duration leaseDuration = const Duration(days: 1),
    String decisionValue = 'HALT_NEW_OFFERS',
    String reasonClass = 'PATCH_SAFETY',
    RolloutState rolloutState = RolloutState.canary,
    Duration clockAdvance = Duration.zero,
    String? evaluationPolicyDigest,
    bool pendingWork = false,
    ControlPlaneStore Function(ControlPlaneStore delegate)? controlDecorator,
  }) async {
    final authoritativeNow = now.add(clockAdvance);
    var currentNow = authoritativeNow;
    final resolvedEvaluationPolicyDigest =
        evaluationPolicyDigest ?? _digest('evaluation-policy');
    var failReclaimOnce = failReclaimAfterCommit;
    final root = await Directory.systemTemp.createTemp('hyfens-p3e5-4b-');
    final baseControl = FileControlPlaneStore(
      Directory('${root.path}/control'),
    );
    final control = controlDecorator?.call(baseControl) ?? baseControl;
    final p3e = FileP3ePersistenceStore(Directory('${root.path}/p3e'));
    final schedules = FileP3e5ScheduleStore(
      Directory('${root.path}/schedules'),
      clock: () => currentNow,
      automaticHaltFailure: failAfterCommit
          ? (point) {
              if (point == P3e5AutomaticHaltFailurePoint.afterCommit) {
                throw StateError('injected after commit');
              }
            }
          : null,
      automaticHaltCompletionFailure: failCompletionAfterCommit
          ? (point) {
              if (point ==
                  P3e5AutomaticHaltCompletionFailurePoint.afterCommit) {
                throw StateError('injected completion after commit');
              }
            }
          : null,
      automaticHaltReclaimFailure: failReclaimAfterCommit
          ? (point) {
              if (point == P3e5AutomaticHaltReclaimFailurePoint.afterCommit &&
                  failReclaimOnce) {
                failReclaimOnce = false;
                throw StateError('lost automatic-halt reclaim response');
              }
            }
          : null,
    );
    await control.initialize();
    await p3e.initialize();
    await schedules.initialize();
    final credentials = CredentialService(random: Random(640));
    final issued = credentials.issue(
      id: 'principal_auto_halt',
      organizationId: 'org_1',
      kind: CredentialKind.autoHalt,
      scopes: autoHaltScopes,
      applicationId: 'app_1',
      environmentId: 'env_1',
      expiresAt: now.add(principalLifetime),
    );
    final storedPrincipal = principalRevoked
        ? issued.record.copyWith(revoked: true)
        : issued.record;
    await control.createJson(
      'credentials',
      storedPrincipal.tokenHash,
      storedPrincipal.toJson(),
    );
    IssuedCredential? scheduler;
    if (pendingWork) {
      final issuedScheduler = credentials.issue(
        id: 'scheduler_1',
        organizationId: 'org_1',
        kind: CredentialKind.scheduler,
        scopes: evaluationOnlySchedulerScopes,
        applicationId: 'app_1',
        environmentId: 'env_1',
        expiresAt: now.add(principalLifetime),
      );
      scheduler = issuedScheduler;
      await control.createJson(
        'credentials',
        issuedScheduler.record.tokenHash,
        issuedScheduler.record.toJson(),
      );
    }
    await control.createJson(
      'applications',
      'app_1',
      ApplicationRecord(
        id: 'app_1',
        organizationId: 'org_1',
        runtimeApplicationId: 'runtime.app',
        createdAt: now,
      ).toJson(),
    );
    await control.createJson(
      'environments',
      'env_1',
      EnvironmentRecord(
        id: 'env_1',
        organizationId: 'org_1',
        applicationId: 'app_1',
        name: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
        version: 0,
        promotedReleaseId: null,
        createdAt: now,
      ).toJson(),
    );
    final target = RolloutTarget(
      organizationId: 'org_1',
      applicationId: 'app_1',
      environmentId: 'env_1',
      platformId: 'android',
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
      state: rolloutState,
      createdAt: now,
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
        salt: 'TEST_VECTOR_ONLY',
      ),
      actorId: 'actor_1',
      reason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
      pausedFromState: rolloutState == RolloutState.paused
          ? RolloutState.canary
          : null,
      createdAt: now,
    );
    await control.createJson('rollouts', rollout.id, rollout.toJson());
    await control.createJson(
      'rollout_revisions',
      rolloutRevision.id,
      rolloutRevision.toJson(),
    );
    final policy = AutomaticHaltPolicy(
      policyId: 'auto_halt_policy_1',
      organizationId: 'org_1',
      applicationId: 'app_1',
      environmentId: 'env_1',
      maximumAggregateAgeFromLateCutoff: const Duration(hours: 2),
      maximumDecisionAgeFromEvaluation: const Duration(hours: 1),
      resourcePolicyReference:
          'TEST VECTOR ONLY — NOT PRODUCTION POLICY:resource',
      approvalReference: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY:approval',
      createdAt: now.subtract(const Duration(minutes: 5)),
      createdBy: 'actor_1',
    );
    final state = AutomaticHaltEnvironmentState(
      stateId: 'auto_halt_state_1',
      organizationId: 'org_1',
      applicationId: 'app_1',
      environmentId: 'env_1',
      generation: 1,
      supersedesStateId: null,
      policyId: policy.policyId,
      automaticHaltPolicyDigest: policy.digest,
      policyApproved: true,
      productionEnabled: productionEnabled,
      productionEnableReference: productionEnabled
          ? 'TEST VECTOR ONLY — NOT PRODUCTION POLICY:enable'
          : null,
      createdAt: now.subtract(const Duration(minutes: 4)),
      createdBy: 'actor_1',
    );
    await schedules.putAutomaticHaltFoundation(policy, state);
    final aggregate = _aggregate(now);
    final aggregateRecord = HealthAggregateRecord(
      aggregateId: 'aggregate_1',
      revisionId: 'aggregate_revision_1',
      aggregate: aggregate,
      recomputability: P3eRecomputability.rawRecomputable,
      createdAt: now.subtract(const Duration(minutes: 3)),
    );
    final aggregateRevision = HealthAggregateRevision(
      aggregateRevisionId: 'aggregate_revision_1',
      aggregateId: 'aggregate_1',
      parentAggregateRevisionId: null,
      identity: aggregate.identity,
      window: aggregate.window,
      aggregationVersion: 1,
      inputCount: aggregate.inputCount,
      inputDigest: aggregate.inputDigest,
      recomputationReason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
      recomputability: P3eRecomputability.rawRecomputable,
      createdAt: now.subtract(const Duration(minutes: 3)),
    );
    await p3e.putAggregateRevision(aggregateRecord, aggregateRevision);
    final targetDigest = sha256Digest(canonicalJson(target.toJson()).codeUnits);
    final schedule = EvaluationSchedule(
      scheduleId: 'schedule_1',
      organizationId: 'org_1',
      applicationId: 'app_1',
      environmentId: 'env_1',
      rolloutId: 'rollout_1',
      currentScheduleRevision: 'schedule_revision_1',
      createdAt: now.subtract(const Duration(minutes: 10)),
      createdBy: 'actor_1',
    );
    final scheduleRevision = EvaluationScheduleRevision(
      scheduleRevisionId: 'schedule_revision_1',
      scheduleId: schedule.scheduleId,
      scheduleGeneration: 1,
      organizationId: 'org_1',
      applicationId: 'app_1',
      environmentId: 'env_1',
      rolloutId: 'rollout_1',
      logicalKeyVersion: 2,
      scheduledEvaluationEnabled: true,
      automaticHaltEnabled: true,
      readinessPhase: EvaluationReadinessPhase.sealed,
      automaticHaltPolicyId: policy.policyId,
      automaticHaltPolicyVersion: 1,
      automaticHaltPolicyDigest: policy.digest,
      automaticHaltEligibleSource: AutomaticHaltEligibleSource.scheduledOnly,
      automaticHaltEligibleReadiness: AutomaticHaltEligibleReadiness.sealedOnly,
      automaticHaltEligibleReasonClass:
          AutomaticHaltEligibleReasonClass.patchSafetyOnly,
      triggerPolicyVersion: 1,
      schedulePolicyVersion: 1,
      evaluationPolicyVersion: 1,
      evaluationPolicyDigest: resolvedEvaluationPolicyDigest,
      thresholdSetVersion: 1,
      thresholdSetDigest: _digest('threshold'),
      aggregationVersion: 1,
      windowPolicyVersion: 1,
      privacyPolicyVersion: 1,
      retryPolicyReference: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY:retry',
      resourcePolicyReference:
          'TEST VECTOR ONLY — NOT PRODUCTION POLICY:resource',
      supersedesScheduleRevisionId: null,
      createdAt: now.subtract(const Duration(minutes: 9)),
      createdBy: 'actor_1',
      reason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
    );
    await schedules.createSchedule(schedule, scheduleRevision);
    final key = LogicalEvaluationKey(
      logicalKeyVersion: 2,
      organizationId: 'org_1',
      applicationId: 'app_1',
      environmentId: 'env_1',
      platformId: 'android',
      rolloutId: 'rollout_1',
      rolloutRevision: 1,
      releaseId: 'release_1',
      patchId: 'patch_1',
      sequence: 1,
      targetBindingDigest: targetDigest,
      windowId: aggregate.identity.windowId,
      readinessPhase: EvaluationReadinessPhase.sealed,
      observationSchemaVersion: 1,
      aggregationVersion: 1,
      aggregatePolicyDigest: aggregate.policyDigest,
      evaluationPolicyVersion: 1,
      evaluationPolicyDigest: scheduleRevision.evaluationPolicyDigest,
      thresholdSetVersion: 1,
      thresholdSetDigest: scheduleRevision.thresholdSetDigest,
      windowPolicyVersion: 1,
      privacyPolicyVersion: 1,
      scheduleId: schedule.scheduleId,
      scheduleRevisionId: scheduleRevision.scheduleRevisionId,
      scheduleGeneration: 1,
      automaticHaltPolicyId: policy.policyId,
      automaticHaltPolicyVersion: 1,
      automaticHaltPolicyDigest: policy.digest,
      automaticHaltEnabled: true,
      automaticHaltEligibleSource: AutomaticHaltEligibleSource.scheduledOnly,
      automaticHaltEligibleReadiness: AutomaticHaltEligibleReadiness.sealedOnly,
      automaticHaltEligibleReasonClass:
          AutomaticHaltEligibleReasonClass.patchSafetyOnly,
    );
    final evaluation = HealthEvaluation(
      evaluationId: 'evaluation_1',
      organizationId: 'org_1',
      aggregateRevisionId: aggregateRevision.aggregateRevisionId,
      rolloutId: 'rollout_1',
      rolloutRevision: 1,
      evaluationVersion: 1,
      policyVersion: 1,
      thresholdSetVersion: 1,
      windowPolicyVersion: 1,
      privacyPolicyVersion: 1,
      aggregateInputDigest: aggregate.inputDigest,
      decision: decisionValue,
      reasonClass: reasonClass,
      reasonCodes: const <String>['ACTIVATION_FAILURE_RATE'],
      coverageState: 'SUFFICIENT',
      freshnessState: 'FRESH',
      sampleState: 'PASSED',
      createdAt: now.subtract(const Duration(minutes: 2)),
      auditReference: 'audit_evaluation_1',
      evaluationInputDigest: _digest('evaluation-input'),
      targetBindingDigest: targetDigest,
    );
    final decision = RolloutDecisionRecord(
      decisionId: 'decision_1',
      organizationId: 'org_1',
      rolloutId: 'rollout_1',
      expectedRolloutRevision: 1,
      evaluationId: evaluation.evaluationId,
      aggregateRevisionId: aggregateRevision.aggregateRevisionId,
      decision: decisionValue,
      reason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
      actorIdentity: 'scheduler_1',
      idempotencyKey: key.evaluationIdempotencyKey,
      createdAt: now.subtract(const Duration(minutes: 2)),
    );
    await p3e.putEvaluation(evaluation);
    await p3e.putDecision(decision);
    final leaseAcquired = now.subtract(const Duration(minutes: 1));
    final leaseExpires = leaseExpired
        ? now.subtract(const Duration(seconds: 1))
        : now.add(leaseDuration);
    final work = ScheduledEvaluationWork(
      workId: key.workId,
      logicalKey: key,
      status: pendingWork
          ? ScheduledEvaluationWorkStatus.pending
          : ScheduledEvaluationWorkStatus.evaluated,
      workVersion: pendingWork ? 0 : 3,
      attemptCount: pendingWork ? 0 : 1,
      notBefore: now.subtract(const Duration(minutes: 10)),
      leaseOwner: pendingWork ? null : 'executor_1',
      leaseTokenDigest: pendingWork
          ? null
          : sha256Digest(_leaseToken.codeUnits),
      leaseAcquiredAt: pendingWork
          ? null
          : leaseExpired
          ? now.subtract(const Duration(minutes: 2))
          : leaseAcquired,
      leaseExpiresAt: pendingWork ? null : leaseExpires,
      createdAt: now.subtract(const Duration(minutes: 10)),
      updatedAt: pendingWork ? now : leaseAcquired,
      lastAttemptAt: pendingWork ? null : leaseAcquired,
      lastErrorClass: null,
      lastErrorCode: null,
      aggregateId: pendingWork ? null : aggregateRecord.aggregateId,
      aggregateRevisionId: pendingWork
          ? null
          : aggregateRevision.aggregateRevisionId,
      evaluationId: pendingWork ? null : evaluation.evaluationId,
      decisionId: pendingWork ? null : decision.decisionId,
      haltApplicationId: null,
    );
    await schedules.putWork(work);
    final lease = P3e5LeaseMutation(
      scope: const P3e5ClaimScope(
        organizationId: 'org_1',
        applicationId: 'app_1',
        environmentId: 'env_1',
      ),
      workId: work.workId,
      expectedWorkVersion: work.workVersion,
      leaseOwner: 'executor_1',
      rawLeaseToken: _leaseToken,
    );
    final service = P3e5AutomaticHaltApplicabilityService(
      controlStore: control,
      scheduleStore: schedules,
      p3eStore: p3e,
      clock: () => currentNow,
      random: Random(641),
      failure: failBeforeCommit
          ? (_) async => throw StateError('injected before commit')
          : null,
    );
    return _Fixture._(
      root: root,
      control: control,
      p3e: p3e,
      schedules: schedules,
      service: service,
      principal: issued,
      scheduler: scheduler,
      lease: lease,
      workId: work.workId,
      advanceClock: (value) => currentNow = value.toUtc(),
    );
  }

  Future<void> close() async {
    await schedules.close();
    await p3e.close();
    await control.close();
    await root.delete(recursive: true);
  }
}

Future<IssuedCredential> _copyFixtureToPostgres(
  _Fixture source,
  PostgresControlPlaneStore control,
  PostgresP3ePersistenceStore p3e,
  PostgresP3e5ScheduleStore schedules,
  String organizationId,
  String suffix,
) async {
  final sourceRolloutRevision = (await source.control.listJson(
    'rollout_revisions',
  )).single;
  final transformedTarget = RolloutTarget.fromJson(
    _replaceFixtureValue(
      sourceRolloutRevision['target'],
      organizationId,
      suffix,
    ),
  );
  final targetBindingDigest = sha256Digest(
    utf8.encode(canonicalJson(transformedTarget.toJson())),
  );
  for (final collection in const <String>[
    'organizations',
    'applications',
    'environments',
    'rollouts',
    'rollout_revisions',
    'credentials',
  ]) {
    for (final raw in await source.control.listJson(collection)) {
      if (collection == 'credentials') continue;
      final body = _replaceFixtureIds(raw, organizationId, suffix);
      final id = body['id']! as String;
      await control.createJson(collection, id, body);
    }
  }

  for (final aggregate in await source.p3e.listAggregates('org_1')) {
    final aggregateBody = _replaceFixtureIds(
      aggregate.toJson(),
      organizationId,
      suffix,
    );
    final transformedAggregate = HealthAggregate.fromJson(
      aggregateBody['aggregate'],
    );
    aggregateBody['aggregateDigest'] = sha256Digest(
      utf8.encode(transformedAggregate.canonicalSerialization),
    );
    final revision = await source.p3e.readAggregateRevision(
      'org_1',
      aggregate.revisionId,
    );
    if (revision == null)
      throw StateError('Fixture aggregate revision missing');
    final revisionBody = _replaceFixtureIds(
      revision.toJson(),
      organizationId,
      suffix,
    );
    await p3e.putAggregateRevision(
      HealthAggregateRecord.fromJson(aggregateBody),
      HealthAggregateRevision.fromJson(revisionBody),
    );
  }
  for (final evaluation in await source.p3e.listEvaluations('org_1')) {
    final body = _replaceFixtureIds(
      evaluation.toJson(),
      organizationId,
      suffix,
    );
    body['targetBindingDigest'] = targetBindingDigest;
    await p3e.putEvaluation(HealthEvaluation.fromJson(body));
  }

  final sourcePolicy = (await source.schedules.listAutomaticHaltPolicies(
    'org_1',
  )).single;
  final policyBody = _replaceFixtureIds(
    sourcePolicy.toJson(),
    organizationId,
    suffix,
  );
  policyBody['automaticHaltPolicyDigest'] = _policyDigest(policyBody);
  final policy = AutomaticHaltPolicy.fromJson(policyBody);

  final sourceSchedule = (await source.schedules.listSchedules('org_1')).single;
  final sourceScheduleRevision = (await source.schedules.listRevisions(
    'org_1',
    sourceSchedule.scheduleId,
  )).single;
  final scheduleRevisionBody = _replaceFixtureIds(
    sourceScheduleRevision.toJson(),
    organizationId,
    suffix,
  );
  scheduleRevisionBody['automaticHaltPolicyId'] = policy.policyId;
  scheduleRevisionBody['automaticHaltPolicyDigest'] = policy.digest;
  await schedules.createSchedule(
    EvaluationSchedule.fromJson(
      _replaceFixtureIds(sourceSchedule.toJson(), organizationId, suffix),
    ),
    EvaluationScheduleRevision.fromJson(scheduleRevisionBody),
  );
  final sourceState = await source.schedules.readCurrentAutomaticHaltState(
    'org_1',
    'app_1',
    'env_1',
  );
  if (sourceState == null)
    throw StateError('Fixture automatic-halt state missing');
  final stateBody = _replaceFixtureIds(
    sourceState.toJson(),
    organizationId,
    suffix,
  );
  stateBody['policyId'] = policy.policyId;
  stateBody['automaticHaltPolicyDigest'] = policy.digest;
  await schedules.putAutomaticHaltFoundation(
    policy,
    AutomaticHaltEnvironmentState.fromJson(stateBody),
  );

  final sourceWork = (await source.schedules.listWork('org_1')).single;
  final workBody = _replaceFixtureIds(
    sourceWork.toJson(),
    organizationId,
    suffix,
  );
  final logicalKeyBody = workBody['logicalKey']! as Map<String, Object?>;
  logicalKeyBody['automaticHaltPolicyId'] = policy.policyId;
  logicalKeyBody['automaticHaltPolicyDigest'] = policy.digest;
  logicalKeyBody['targetBindingDigest'] = targetBindingDigest;
  final key = LogicalEvaluationKey.fromJson(workBody['logicalKey']);
  workBody['workId'] = key.workId;
  workBody['logicalKeyDigest'] = key.digest;
  if (sourceWork.automaticHaltIntent != null) {
    final intent = AutomaticHaltIntent(
      workId: key.workId,
      attemptId: deriveAttemptId(key.workId, sourceWork.attemptCount),
      evaluationId: workBody['evaluationId']! as String,
      decisionId: workBody['decisionId']! as String,
      scheduleRevisionId: key.scheduleRevisionId,
      automaticHaltPolicyVersion: key.automaticHaltPolicyVersion!,
      automaticHaltPolicyDigest: key.automaticHaltPolicyDigest!,
      expectedRolloutRevision: key.rolloutRevision,
      targetBindingDigest: key.targetBindingDigest,
      authorizedPrincipalId: 'principal_auto_halt_$suffix',
      authorizedAt: sourceWork.automaticHaltIntent!.authorizedAt,
    );
    workBody['status'] = ScheduledEvaluationWorkStatus.haltApplying.wireName;
    workBody['workVersion'] = 4;
    workBody['automaticHaltIntent'] = intent.toJson();
  }
  await schedules.putWork(ScheduledEvaluationWork.fromJson(workBody));

  for (final decision in await source.p3e.listDecisions('org_1')) {
    final body = _replaceFixtureIds(decision.toJson(), organizationId, suffix);
    body['idempotencyKey'] = key.evaluationIdempotencyKey;
    await p3e.putDecision(RolloutDecisionRecord.fromJson(body));
  }
  final credentials = CredentialService(random: Random.secure());
  final issued = credentials.issue(
    id: 'principal_auto_halt_$suffix',
    organizationId: organizationId,
    kind: CredentialKind.autoHalt,
    scopes: autoHaltScopes,
    applicationId: 'app_$suffix',
    environmentId: 'env_$suffix',
    expiresAt: DateTime.utc(2026, 8, 25),
  );
  await control.createJson(
    'credentials',
    issued.record.tokenHash,
    issued.record.toJson(),
  );
  return issued;
}

Map<String, Object?> _replaceFixtureIds(
  Map<String, Object?> value,
  String organizationId,
  String suffix,
) =>
    _replaceFixtureValue(value, organizationId, suffix) as Map<String, Object?>;

String _policyDigest(Map<String, Object?> body) => sha256Digest(
  utf8.encode(
    canonicalJson(<String, Object?>{
      'organizationId': body['organizationId'],
      'applicationId': body['applicationId'],
      'environmentId': body['environmentId'],
      'automaticHaltPolicyVersion': body['automaticHaltPolicyVersion'],
      'eligibleSource': body['eligibleSource'],
      'eligibleReadiness': body['eligibleReadiness'],
      'eligibleReasonClass': body['eligibleReasonClass'],
      'maximumAggregateAgeFromLateCutoffMicros':
          body['maximumAggregateAgeFromLateCutoffMicros'],
      'maximumDecisionAgeFromEvaluationMicros':
          body['maximumDecisionAgeFromEvaluationMicros'],
      'resourcePolicyReference': body['resourcePolicyReference'],
      'approvalReference': body['approvalReference'],
    }),
  ),
);

Object? _replaceFixtureValue(
  Object? value,
  String organizationId,
  String suffix,
) {
  final replacements = <String, String>{
    'org_1': organizationId,
    'app_1': 'app_$suffix',
    'env_1': 'env_$suffix',
    'rollout_1': 'rollout_$suffix',
    'rollout_revision_1': 'rollout_revision_$suffix',
    'schedule_1': 'schedule_$suffix',
    'schedule_revision_1': 'schedule_revision_$suffix',
    'auto_halt_policy_1': 'auto_halt_policy_$suffix',
    'auto_halt_state_1': 'auto_halt_state_$suffix',
    'aggregate_1': 'aggregate_$suffix',
    'aggregate_revision_1': 'aggregate_revision_$suffix',
    'evaluation_1': 'evaluation_$suffix',
    'decision_1': 'decision_$suffix',
  };
  if (value is String) return replacements[value] ?? value;
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _replaceFixtureValue(
          entry.value,
          organizationId,
          suffix,
        ),
    };
  }
  if (value is List) {
    return value
        .map((item) => _replaceFixtureValue(item, organizationId, suffix))
        .toList(growable: false);
  }
  return value;
}

HealthAggregate _aggregate(DateTime now) {
  final start = now.subtract(const Duration(minutes: 30));
  final window = ObservationWindow(
    windowId: 'window_1',
    serverStart: start.subtract(const Duration(hours: 1)),
    serverEnd: start.subtract(const Duration(minutes: 30)),
    lateCutoff: start,
    minimumDuration: const Duration(minutes: 30),
    maximumDuration: const Duration(hours: 1),
    windowPolicyVersion: 1,
  );
  return HealthAggregate(
    identity: AggregateIdentity(
      organizationId: 'org_1',
      applicationId: 'app_1',
      environmentId: 'env_1',
      platformId: 'android',
      releaseId: 'release_1',
      patchId: 'patch_1',
      sequence: 1,
      rolloutId: 'rollout_1',
      rolloutRevision: 1,
      windowId: window.windowId,
      windowStart: window.serverStart,
      windowEnd: window.serverEnd,
      lateCutoff: window.lateCutoff,
      observationSchemaVersion: 1,
      aggregationVersion: 1,
    ),
    window: window,
    inputCount: 2,
    acceptedInputCount: 2,
    inputDigest: _digest('aggregate-input'),
    policyVersion: 1,
    policyDigest: _digest('aggregate-policy'),
    externalQualityDigest: _digest('aggregate-quality'),
    counters: const AggregateCounters(
      eligibleInstallationsObserved: 2,
      lookupAttempts: 2,
      candidateOffers: 2,
      downloadSucceeded: 2,
      downloadFailed: 0,
      admissionVerified: 2,
      admissionRejected: 0,
      activationStarted: 2,
      activationSucceeded: 1,
      activationFailed: 1,
      healthyConfirmed: 1,
      runtimeFaults: 0,
      rollbacks: 0,
      fallbacksToAot: 0,
      restartSurvived: 1,
      staleOrReplayRejects: 0,
      lateEvents: 0,
      quarantinedEvents: 0,
      missingExpectedEvents: 0,
    ),
    quality: const AggregateQualityCounters(
      accepted: 2,
      duplicate: 0,
      duplicateMutations: 0,
      excessContributions: 0,
      late: 0,
      quarantined: 0,
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
        name: const AggregateMetric.evaluable(numerator: 1, denominator: 2),
    },
    coverage: const AggregateCoverage(
      observedInstallations: 2,
      expectedInstallations: 2,
      observedBasisPoints: 10000,
      minimumBasisPoints: 10000,
      state: AggregateCoverageState.sufficient,
    ),
    samples: const AggregateSampleStatus(
      eligible: AggregateSampleCheck(observed: 2, required: 1, passed: true),
      offers: AggregateSampleCheck(observed: 2, required: 1, passed: true),
      activated: AggregateSampleCheck(observed: 2, required: 1, passed: true),
      healthy: AggregateSampleCheck(observed: 1, required: 1, passed: true),
      coveragePassed: true,
      allPassed: true,
    ),
    privacyState: AggregatePrivacyState.normal,
    freshnessState: AggregateFreshnessState.fresh,
    missingData: const <AggregateMissingDataReason>[],
    latestPrimaryReceivedAt: window.serverEnd,
  );
}
