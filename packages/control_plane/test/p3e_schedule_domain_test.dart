import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 24, 18);

  group('P3E5 schedule domain', () {
    test('safe defaults and codecs preserve immutable schedule semantics', () {
      final schedule = _schedule(now);
      final revision = _revision(now: now);
      expect(revision.scheduledEvaluationEnabled, isFalse);
      expect(revision.automaticHaltEnabled, isFalse);
      expect(
        EvaluationSchedule.fromJson(schedule.toJson()).canonicalSerialization,
        schedule.canonicalSerialization,
      );
      expect(
        EvaluationScheduleRevision.fromJson(revision.toJson())
            .canonicalSerialization,
        revision.canonicalSerialization,
      );
      expect(
        () => EvaluationScheduleRevision.fromJson(<String, Object?>{
          ...revision.toJson(),
          'readinessPhase': 'OPEN',
        }),
        throwsFormatException,
      );
      expect(
        () => EvaluationScheduleRevision.fromJson(<String, Object?>{
          ...revision.toJson(),
          'evaluationPolicyVersion': 99,
        }),
        throwsFormatException,
      );
      expect(
        () => EvaluationScheduleRevision(
          scheduleRevisionId: 'schedule_revision_2',
          scheduleId: schedule.scheduleId,
          scheduleGeneration: 2,
          organizationId: schedule.organizationId,
          applicationId: schedule.applicationId,
          environmentId: schedule.environmentId,
          rolloutId: schedule.rolloutId,
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
          reason: 'invalid missing parent',
        ),
        throwsFormatException,
      );
    });

    test('logical identity is deterministic and changes with semantics', () {
      final key = _key();
      final equal = LogicalEvaluationKey.fromJson(key.toJson());
      final changed = _key(windowId: 'window_2');
      expect(equal.workId, key.workId);
      expect(equal.digest, key.digest);
      expect(
        equal.evaluationIdempotencyKey,
        'scheduled-evaluation:${key.workId}',
      );
      expect(equal.haltIdempotencyKey, 'scheduled-halt:${key.workId}');
      expect(changed.workId, isNot(key.workId));
      expect(
        _key(readiness: EvaluationReadinessPhase.closed).workId,
        isNot(key.workId),
      );
      expect(
        _key(scheduleRevisionId: 'schedule_revision_2').workId,
        isNot(key.workId),
      );
      expect(
        () => LogicalEvaluationKey.fromJson(<String, Object?>{
          ...key.toJson(),
          'logicalKeyVersion': 3,
        }),
        throwsFormatException,
      );
    });

    test(
      'work codec rejects unknown state, digest mutation, and bad leases',
      () {
        final work = ScheduledEvaluationWork.pending(
          logicalKey: _key(),
          serverNow: now,
        );
        expect(
          ScheduledEvaluationWork.fromJson(work.toJson())
              .canonicalSerialization,
          work.canonicalSerialization,
        );
        expect(
          () => ScheduledEvaluationWork.fromJson(<String, Object?>{
            ...work.toJson(),
            'status': 'RUNNING',
          }),
          throwsFormatException,
        );
        expect(
          () => ScheduledEvaluationWork.fromJson(<String, Object?>{
            ...work.toJson(),
            'logicalKeyDigest': _digest('x'),
          }),
          throwsFormatException,
        );
        expect(
          () => ScheduledEvaluationWork.fromJson(<String, Object?>{
            ...work.toJson(),
            'leaseOwner': 'worker_1',
          }),
          throwsFormatException,
        );
      },
    );

    test('transition validator implements only approved transitions', () {
      expect(
        isValidScheduledEvaluationTransition(
          ScheduledEvaluationWorkStatus.pending,
          ScheduledEvaluationWorkStatus.leased,
        ),
        isTrue,
      );
      expect(
        isValidScheduledEvaluationTransition(
          ScheduledEvaluationWorkStatus.evaluated,
          ScheduledEvaluationWorkStatus.haltApplying,
        ),
        isTrue,
      );
      expect(
        isValidScheduledEvaluationTransition(
          ScheduledEvaluationWorkStatus.failedPermanent,
          ScheduledEvaluationWorkStatus.retryWait,
        ),
        isTrue,
      );
      expect(
        isValidScheduledEvaluationTransition(
          ScheduledEvaluationWorkStatus.completed,
          ScheduledEvaluationWorkStatus.retryWait,
        ),
        isFalse,
      );
      expect(
        isValidScheduledEvaluationTransition(
          ScheduledEvaluationWorkStatus.pending,
          ScheduledEvaluationWorkStatus.evaluating,
        ),
        isFalse,
      );
      expect(
        () => validateScheduledEvaluationTransition(
          ScheduledEvaluationWorkStatus.cancelled,
          ScheduledEvaluationWorkStatus.pending,
        ),
        throwsFormatException,
      );
    });

    test(
      'attempt identity, ordering fields, and encoded bounds fail closed',
      () {
        final workId = _key().workId;
        final attempt = ScheduledEvaluationAttempt(
          attemptId: deriveAttemptId(workId, 1),
          workId: workId,
          attemptNumber: 1,
          leaseOwner: 'worker_1',
          leaseTokenDigest: _digest('l'),
          startedAt: now,
          finishedAt: now.add(const Duration(seconds: 1)),
          outcome: 'TEST_ONLY',
          errorClass: null,
          safeErrorCode: null,
          evaluationId: null,
          decisionId: null,
          haltApplicationId: null,
          actorIdentity: 'scheduler_1',
        );
        expect(
          ScheduledEvaluationAttempt.fromJson(attempt.toJson())
              .canonicalSerialization,
          attempt.canonicalSerialization,
        );
        expect(
          () => ScheduledEvaluationAttempt(
            attemptId: deriveAttemptId(workId, 2),
            workId: workId,
            attemptNumber: 1,
            leaseOwner: null,
            leaseTokenDigest: null,
            startedAt: now,
            finishedAt: null,
            outcome: 'TEST_ONLY',
            errorClass: null,
            safeErrorCode: null,
            evaluationId: null,
            decisionId: null,
            haltApplicationId: null,
            actorIdentity: 'scheduler_1',
          ),
          throwsFormatException,
        );
        expect(
          () => ScheduledEvaluationAttempt(
            attemptId: deriveAttemptId(workId, 1),
            workId: workId,
            attemptNumber: 1,
            leaseOwner: null,
            leaseTokenDigest: null,
            startedAt: now,
            finishedAt: null,
            outcome: 'TEST_ONLY',
            errorClass: null,
            safeErrorCode: 'x' * 129,
            evaluationId: null,
            decisionId: null,
            haltApplicationId: null,
            actorIdentity: 'scheduler_1',
          ),
          throwsFormatException,
        );
      },
    );

    test('scope binding rejects mixed tenant and revision semantics', () {
      final schedule = _schedule(now);
      final revision = _revision(now: now);
      validateScheduleRevisionBinding(schedule, revision);
      expect(
        () => validateScheduleRevisionBinding(
          schedule,
          _revision(now: now, organizationId: 'org_other'),
        ),
        throwsFormatException,
      );
      final work = ScheduledEvaluationWork.pending(
        logicalKey: _key(),
        serverNow: now,
      );
      validateWorkBinding(work, schedule, revision);
      expect(
        () => validateWorkBinding(
          ScheduledEvaluationWork.pending(
            logicalKey: _key(windowId: 'window_2'),
            serverNow: now,
          ),
          schedule,
          _revision(now: now, evaluationDigest: _digest('z')),
        ),
        throwsFormatException,
      );
    });
  });
}

EvaluationSchedule _schedule(DateTime now) => EvaluationSchedule(
  scheduleId: 'schedule_1',
  organizationId: 'org_1',
  applicationId: 'app_1',
  environmentId: 'env_1',
  rolloutId: 'rollout_1',
  currentScheduleRevision: 'schedule_revision_1',
  createdAt: now,
  createdBy: 'actor_1',
);

EvaluationScheduleRevision _revision({
  required DateTime now,
  String organizationId = 'org_1',
  String evaluationDigest = '',
}) => EvaluationScheduleRevision(
  scheduleRevisionId: 'schedule_revision_1',
  scheduleId: 'schedule_1',
  scheduleGeneration: 1,
  organizationId: organizationId,
  applicationId: 'app_1',
  environmentId: 'env_1',
  rolloutId: 'rollout_1',
  readinessPhase: EvaluationReadinessPhase.sealed,
  triggerPolicyVersion: 1,
  schedulePolicyVersion: 1,
  evaluationPolicyVersion: 1,
  evaluationPolicyDigest: evaluationDigest.isEmpty
      ? _digest('e')
      : evaluationDigest,
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

LogicalEvaluationKey _key({
  String windowId = 'window_1',
  String scheduleRevisionId = 'schedule_revision_1',
  EvaluationReadinessPhase readiness = EvaluationReadinessPhase.sealed,
}) => LogicalEvaluationKey(
  organizationId: 'org_1',
  applicationId: 'app_1',
  environmentId: 'env_1',
  platformId: 'platform_1',
  rolloutId: 'rollout_1',
  rolloutRevision: 1,
  releaseId: 'release_1',
  patchId: 'patch_1',
  sequence: 1,
  targetBindingDigest: _digest('b'),
  windowId: windowId,
  readinessPhase: readiness,
  observationSchemaVersion: 1,
  aggregationVersion: 1,
  aggregatePolicyDigest: _digest('a'),
  evaluationPolicyVersion: 1,
  evaluationPolicyDigest: _digest('e'),
  thresholdSetVersion: 1,
  thresholdSetDigest: _digest('t'),
  windowPolicyVersion: 1,
  privacyPolicyVersion: 1,
  scheduleId: 'schedule_1',
  scheduleRevisionId: scheduleRevisionId,
  scheduleGeneration: 1,
);

String _digest(String value) => sha256Digest(value.codeUnits);
