import 'dart:convert';
import 'dart:math';

import 'auth.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'p3e_auto_halt.dart';
import 'p3e_auto_halt_authority.dart';
import 'p3e_claim.dart';
import 'p3e_persistence.dart';
import 'p3e_schedule.dart';
import 'p3e_schedule_persistence.dart';
import 'persistence.dart';
import 'rollout.dart';

enum P3e5AutomaticHaltApplicabilityFailurePoint { beforeIntentCommit }

/// Bounded P3E5-4B gate. It validates and persists intent only; this type has
/// no P3E-4 service, rollout transition store, or P3A mutation dependency.
final class P3e5AutomaticHaltApplicabilityService {
  P3e5AutomaticHaltApplicabilityService({
    required this.controlStore,
    required this.scheduleStore,
    required this.p3eStore,
    DateTime Function()? clock,
    Random? random,
    this.failure,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure();

  final ControlPlaneStore controlStore;
  final P3e5ScheduleStore scheduleStore;
  final P3ePersistenceStore p3eStore;
  final DateTime Function() _clock;
  final Random _random;
  final Future<void> Function(P3e5AutomaticHaltApplicabilityFailurePoint point)?
  failure;

  Future<P3e5WorkMutationResult> applyIntent({
    required String token,
    required P3e5LeaseMutation lease,
    String? requestId,
  }) async {
    final initialNow = _clock().toUtc();
    final principal = await _authorize(token, lease.scope, initialNow);
    final authority = AutomaticHaltAuthority(
      lease: lease,
      principal: principal,
      authoritativeNow: initialNow,
    );
    final work = await scheduleStore.readWork(
      lease.scope.organizationId,
      lease.workId,
    );
    if (work == null || !lease.scope.contains(work)) {
      throw const StorageConflict('Scheduled work was not found');
    }
    if (work.status == ScheduledEvaluationWorkStatus.haltApplying) {
      final existingIntent = work.automaticHaltIntent;
      if (existingIntent == null ||
          existingIntent.authorizedPrincipalId != principal.id) {
        throw _security('Persisted automatic-halt intent is invalid');
      }
      final replay = await scheduleStore.applyAutomaticHaltIntent(
        P3e5AutomaticHaltIntentAdvance(
          authority: authority,
          intent: existingIntent,
        ),
        validateCurrent: (_, _) async {},
      );
      await _audit(
        principal,
        requestId,
        'health.auto_halt_intent_replayed',
        work.workId,
        <String, Object?>{
          'intentDigest': existingIntent.intentDigest,
          'decisionId': existingIntent.decisionId,
          'workVersion': replay.work.workVersion,
        },
      );
      return replay;
    }
    late final P3e5AutomaticHaltCurrentEvidence evidence;
    try {
      evidence = await _validateCurrent(work, initialNow);
    } on Object catch (error) {
      await _audit(
        principal,
        requestId,
        _auditFailureAction(error),
        work.workId,
        <String, Object?>{'code': _safeCode(error)},
      );
      rethrow;
    }
    final intent = AutomaticHaltIntent(
      workId: work.workId,
      attemptId: deriveAttemptId(work.workId, work.attemptCount),
      evaluationId: evidence.evaluation.evaluationId,
      decisionId: evidence.decision.decisionId,
      scheduleRevisionId: work.logicalKey.scheduleRevisionId,
      automaticHaltPolicyVersion: evidence.policy.automaticHaltPolicyVersion,
      automaticHaltPolicyDigest: evidence.policy.digest,
      expectedRolloutRevision: evidence.rolloutRevision.revision,
      targetBindingDigest: work.logicalKey.targetBindingDigest,
      authorizedPrincipalId: principal.id,
      authorizedAt: work.automaticHaltIntent?.authorizedAt ?? initialNow,
    );
    try {
      final result = await scheduleStore.applyAutomaticHaltIntent(
        P3e5AutomaticHaltIntentAdvance(authority: authority, intent: intent),
        validateCurrent: (authoritativeNow, current) async {
          final currentPrincipal = await _authorize(
            token,
            lease.scope,
            authoritativeNow,
          );
          if (currentPrincipal.id != principal.id) {
            throw const ControlPlaneException(
              'HEALTH_AUTO_HALT_SECURITY_REJECTED',
              'Automatic-halt principal changed',
              statusCode: 403,
            );
          }
          authority.validateAt(authoritativeNow);
          if (current.workVersion != lease.expectedWorkVersion) {
            throw const StorageConflict('Scheduled work version conflict');
          }
          await failure?.call(
            P3e5AutomaticHaltApplicabilityFailurePoint.beforeIntentCommit,
          );
          await _validateCurrent(current, authoritativeNow);
        },
      );
      await _audit(
        principal,
        requestId,
        result.changed
            ? 'health.auto_halt_intent_created'
            : 'health.auto_halt_intent_replayed',
        work.workId,
        <String, Object?>{
          'intentDigest': intent.intentDigest,
          'decisionId': intent.decisionId,
          'workVersion': result.work.workVersion,
        },
      );
      return result;
    } on Object catch (error) {
      await _audit(
        principal,
        requestId,
        _auditFailureAction(error),
        work.workId,
        <String, Object?>{'code': _safeCode(error)},
      );
      rethrow;
    }
  }

  /// Reloads and validates a committed `HALT_APPLYING` intent immediately
  /// before the narrow P3E-4 application adapter invokes the shared halt core.
  /// This method is read-only: it never changes scheduled work or rollout
  /// state.
  Future<P3e5AutomaticHaltCurrentEvidence> validateIntent({
    required String token,
    required P3e5LeaseMutation lease,
    bool allowCommittedHaltRecovery = false,
  }) async {
    final now = _clock().toUtc();
    final principal = await _authorize(token, lease.scope, now);
    final authority = AutomaticHaltAuthority(
      lease: lease,
      principal: principal,
      authoritativeNow: now,
    );
    final work = await scheduleStore.readWork(
      lease.scope.organizationId,
      lease.workId,
    );
    if (work == null || !lease.scope.contains(work)) {
      throw const StorageConflict('Scheduled work was not found');
    }
    authority.validateAt(now);
    if (work.status != ScheduledEvaluationWorkStatus.haltApplying ||
        work.automaticHaltIntent == null ||
        work.automaticHaltIntent!.authorizedPrincipalId != principal.id ||
        work.workVersion != lease.expectedWorkVersion ||
        work.leaseOwner != lease.leaseOwner ||
        work.leaseTokenDigest != lease.tokenDigest ||
        work.leaseExpiresAt == null ||
        !work.leaseExpiresAt!.isAfter(now)) {
      throw const StorageConflict(
        'Automatic-halt work lease or intent is no longer current',
      );
    }
    final evidence = await _validateCurrent(
      work,
      now,
      allowCommittedHaltRecovery: allowCommittedHaltRecovery,
    );
    final intent = work.automaticHaltIntent!;
    if (intent.evaluationId != evidence.evaluation.evaluationId ||
        intent.decisionId != evidence.decision.decisionId ||
        intent.expectedRolloutRevision != evidence.rolloutRevision.revision ||
        intent.targetBindingDigest != work.logicalKey.targetBindingDigest ||
        intent.automaticHaltPolicyVersion !=
            evidence.policy.automaticHaltPolicyVersion ||
        intent.automaticHaltPolicyDigest != evidence.policy.digest) {
      throw _security('Automatic-halt intent binding is stale');
    }
    return evidence.withPrincipal(principal);
  }

  Future<P3e5AutomaticHaltCurrentEvidence> _validateCurrent(
    ScheduledEvaluationWork work,
    DateTime authoritativeNow, {
    bool allowCommittedHaltRecovery = false,
  }) async {
    final now = authoritativeNow.toUtc();
    final key = work.logicalKey;
    if ((work.status != ScheduledEvaluationWorkStatus.evaluated &&
            work.status != ScheduledEvaluationWorkStatus.haltApplying) ||
        key.logicalKeyVersion != 2 ||
        !key.isAutomaticHaltFoundationCandidate ||
        work.evaluationId == null ||
        work.decisionId == null ||
        work.aggregateId == null ||
        work.aggregateRevisionId == null) {
      throw const ControlPlaneException(
        'HEALTH_AUTO_HALT_INELIGIBLE',
        'Scheduled work is not an automatic-halt candidate',
        statusCode: 422,
      );
    }

    final schedule = await scheduleStore.readSchedule(
      key.organizationId,
      key.scheduleId,
    );
    final revision = await scheduleStore.readRevision(
      key.organizationId,
      key.scheduleRevisionId,
    );
    if (schedule == null ||
        revision == null ||
        schedule.currentScheduleRevision != key.scheduleRevisionId ||
        revision.scheduleGeneration != key.scheduleGeneration ||
        !revision.scheduledEvaluationEnabled ||
        !revision.automaticHaltEnabled) {
      throw _stale('Scheduled automatic-halt binding is stale');
    }
    try {
      validateWorkBinding(work, schedule, revision);
    } on FormatException {
      throw _stale('Scheduled work binding is stale');
    }

    final policy = await scheduleStore.readAutomaticHaltPolicy(
      key.organizationId,
      key.automaticHaltPolicyId!,
    );
    final state = await scheduleStore.readCurrentAutomaticHaltState(
      key.organizationId,
      key.applicationId,
      key.environmentId,
    );
    if (policy == null ||
        state == null ||
        policy.policyId != state.policyId ||
        policy.digest != state.automaticHaltPolicyDigest ||
        policy.automaticHaltPolicyVersion != key.automaticHaltPolicyVersion ||
        policy.digest != key.automaticHaltPolicyDigest ||
        !state.policyApproved ||
        !state.productionEnabled) {
      throw _stale('Automatic-halt policy or enablement is stale');
    }

    final application = await controlStore.readJson(
      'applications',
      key.applicationId,
    );
    final environment = await controlStore.readJson(
      'environments',
      key.environmentId,
    );
    if (application == null ||
        environment == null ||
        application['organizationId'] != key.organizationId ||
        environment['organizationId'] != key.organizationId ||
        environment['applicationId'] != key.applicationId) {
      throw _security('Automatic-halt target scope is invalid');
    }

    final rolloutRaw = await controlStore.readJson('rollouts', key.rolloutId);
    if (rolloutRaw == null) throw _stale('Rollout is stale');
    final rollout = RolloutRecord.fromJson(rolloutRaw);
    final rolloutRevisions = (await controlStore.listJson('rollout_revisions'))
        .where((value) => value['rolloutId'] == rollout.id)
        .map(RolloutRevision.fromJson)
        .toList(growable: false);
    final currentRevisions = rolloutRevisions
        .where((revision) => revision.revision == rollout.currentRevision)
        .toList(growable: false);
    final currentRevision = currentRevisions.length == 1
        ? currentRevisions.single
        : null;
    final committedHalt =
        allowCommittedHaltRecovery &&
        currentRevision != null &&
        rollout.currentRevision == key.rolloutRevision + 1 &&
        rollout.state == RolloutState.halted &&
        currentRevision.previousRevision == key.rolloutRevision &&
        currentRevision.reason.startsWith(
          'P3E4 health halt decision ${work.automaticHaltIntent?.decisionId}:',
        );
    final eligibleCurrentState = const <RolloutState>{
      RolloutState.internal,
      RolloutState.canary,
      RolloutState.expanding,
    }.contains(rollout.state);
    final selectedRevisions = committedHalt
        ? rolloutRevisions
              .where((revision) => revision.revision == key.rolloutRevision)
              .toList(growable: false)
        : currentRevisions;
    if (rollout.organizationId != key.organizationId ||
        selectedRevisions.length != 1 ||
        (!eligibleCurrentState && !committedHalt) ||
        (!committedHalt && rollout.currentRevision != key.rolloutRevision)) {
      throw _stale('Rollout revision or state is ineligible');
    }
    final rolloutRevision = selectedRevisions.single;
    final target = rolloutRevision.target;
    if ((!committedHalt && rolloutRevision.state != rollout.state) ||
        target.organizationId != key.organizationId ||
        target.applicationId != key.applicationId ||
        target.environmentId != key.environmentId ||
        target.platformId != key.platformId ||
        target.releaseId != key.releaseId ||
        target.patchId != key.patchId ||
        target.sequence != key.sequence ||
        sha256Digest(utf8.encode(canonicalJson(target.toJson()))) !=
            key.targetBindingDigest) {
      throw _stale('Rollout target binding is stale');
    }

    final aggregate = await p3eStore.readAggregate(
      key.organizationId,
      work.aggregateId!,
    );
    final aggregateRevision = await p3eStore.readAggregateRevision(
      key.organizationId,
      work.aggregateRevisionId!,
    );
    final evaluation = await p3eStore.readEvaluation(
      key.organizationId,
      work.evaluationId!,
    );
    final decision = await p3eStore.readDecision(
      key.organizationId,
      work.decisionId!,
    );
    if (aggregate == null ||
        aggregateRevision == null ||
        evaluation == null ||
        decision == null) {
      throw _security('Automatic-halt evidence is missing');
    }
    try {
      validateP3eAggregateLineage(aggregate, aggregateRevision);
    } on Object {
      throw _security('Automatic-halt aggregate evidence is invalid');
    }
    final identity = aggregateRevision.identity;
    if (identity.organizationId != key.organizationId ||
        identity.applicationId != key.applicationId ||
        identity.environmentId != key.environmentId ||
        identity.platformId != key.platformId ||
        identity.rolloutId != key.rolloutId ||
        identity.rolloutRevision != key.rolloutRevision ||
        identity.releaseId != key.releaseId ||
        identity.patchId != key.patchId ||
        identity.sequence != key.sequence ||
        identity.windowId != key.windowId ||
        identity.observationSchemaVersion != key.observationSchemaVersion ||
        identity.aggregationVersion != key.aggregationVersion ||
        aggregate.aggregate.policyDigest != key.aggregatePolicyDigest ||
        evaluation.organizationId != key.organizationId ||
        evaluation.aggregateRevisionId !=
            aggregateRevision.aggregateRevisionId ||
        evaluation.rolloutId != key.rolloutId ||
        evaluation.rolloutRevision != key.rolloutRevision ||
        evaluation.evaluationVersion != key.evaluationPolicyVersion ||
        evaluation.policyVersion != aggregate.aggregate.policyVersion ||
        evaluation.thresholdSetVersion != key.thresholdSetVersion ||
        evaluation.windowPolicyVersion != key.windowPolicyVersion ||
        evaluation.privacyPolicyVersion != key.privacyPolicyVersion ||
        evaluation.aggregateInputDigest != aggregateRevision.inputDigest ||
        evaluation.evaluationInputDigest == null ||
        evaluation.targetBindingDigest != key.targetBindingDigest ||
        evaluation.decision != 'HALT_NEW_OFFERS' ||
        evaluation.reasonClass != 'PATCH_SAFETY' ||
        decision.organizationId != key.organizationId ||
        decision.rolloutId != key.rolloutId ||
        decision.expectedRolloutRevision != key.rolloutRevision ||
        decision.evaluationId != evaluation.evaluationId ||
        decision.aggregateRevisionId != aggregateRevision.aggregateRevisionId ||
        decision.decision != 'HALT_NEW_OFFERS' ||
        decision.idempotencyKey != key.evaluationIdempotencyKey ||
        decision.resultingTransitionReference != null) {
      throw _security('Automatic-halt evidence binding is invalid');
    }
    final decisions = await p3eStore.listDecisions(key.organizationId);
    if (decisions.any(
          (candidate) =>
              candidate.previousDecisionId == decision.decisionId ||
              (candidate.decisionId != decision.decisionId &&
                  candidate.idempotencyKey == decision.idempotencyKey),
        ) ||
        (await p3eStore.listAggregateRevisions(key.organizationId)).any(
          (candidate) =>
              candidate.parentAggregateRevisionId ==
              aggregateRevision.aggregateRevisionId,
        )) {
      throw _stale('Automatic-halt evidence was superseded');
    }
    if (evaluation.createdAt.isAfter(now) ||
        decision.createdAt.isBefore(evaluation.createdAt) ||
        decision.createdAt.isAfter(now)) {
      throw _security('Automatic-halt evidence timestamps are invalid');
    }
    if (now.isBefore(aggregateRevision.window.lateCutoff)) {
      throw _stale('Automatic-halt aggregate is not sealed');
    }
    final report = await p3eStore.reconcile(key.organizationId);
    final relevantIds = <String>{
      aggregate.aggregateId,
      aggregateRevision.aggregateRevisionId,
      evaluation.evaluationId,
      decision.decisionId,
    };
    if (report.issues.any((issue) => relevantIds.contains(issue.entityId))) {
      throw _security('Automatic-halt evidence failed reconciliation');
    }
    if (now.isAfter(
          aggregateRevision.window.lateCutoff.add(
            policy.maximumAggregateAgeFromLateCutoff,
          ),
        ) ||
        now.isAfter(
          evaluation.createdAt.add(policy.maximumDecisionAgeFromEvaluation),
        )) {
      throw _stale('Automatic-halt evidence is no longer fresh');
    }
    return P3e5AutomaticHaltCurrentEvidence(
      work: work,
      policy: policy,
      rolloutRevision: rolloutRevision,
      aggregate: aggregate,
      aggregateRevision: aggregateRevision,
      evaluation: evaluation,
      decision: decision,
    );
  }

  Future<CredentialRecord> _authorize(
    String token,
    P3e5ClaimScope scope,
    DateTime now,
  ) => CredentialService.authorize(
    token: token,
    requiredScope: 'health:work:apply-halt',
    read: (hash) async {
      final raw = await controlStore.readJson('credentials', hash);
      return raw == null ? null : CredentialRecord.fromJson(raw);
    },
    organizationId: scope.organizationId,
    applicationId: scope.applicationId,
    environmentId: scope.environmentId,
    kind: CredentialKind.autoHalt,
    now: now,
  );

  Future<void> _audit(
    CredentialRecord actor,
    String? requestId,
    String action,
    String workId,
    Map<String, Object?> metadata,
  ) async {
    final id = _id('audit');
    final record = AuditRecord(
      id: id,
      requestId: requestId ?? _id('request'),
      organizationId: actor.organizationId,
      actorId: actor.id,
      action: action,
      resourceType: 'scheduled-evaluation-work',
      resourceId: workId,
      result: action.contains('rejected') || action.contains('stale')
          ? 'REJECTED'
          : 'SUCCESS',
      metadata: metadata,
      createdAt: _clock().toUtc(),
    );
    await controlStore.appendAudit(id, record.toJson());
  }

  String _id(String prefix) {
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return '${prefix}_${bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';
  }
}

final class P3e5AutomaticHaltCurrentEvidence {
  const P3e5AutomaticHaltCurrentEvidence({
    required this.work,
    required this.policy,
    required this.rolloutRevision,
    required this.aggregate,
    required this.aggregateRevision,
    required this.evaluation,
    required this.decision,
    this.principal,
  });

  final ScheduledEvaluationWork work;
  final AutomaticHaltPolicy policy;
  final RolloutRevision rolloutRevision;
  final HealthAggregateRecord aggregate;
  final HealthAggregateRevision aggregateRevision;
  final HealthEvaluation evaluation;
  final RolloutDecisionRecord decision;
  final CredentialRecord? principal;

  P3e5AutomaticHaltCurrentEvidence withPrincipal(CredentialRecord value) =>
      P3e5AutomaticHaltCurrentEvidence(
        work: work,
        policy: policy,
        rolloutRevision: rolloutRevision,
        aggregate: aggregate,
        aggregateRevision: aggregateRevision,
        evaluation: evaluation,
        decision: decision,
        principal: value,
      );
}

ControlPlaneException _stale(String message) =>
    ControlPlaneException('HEALTH_AUTO_HALT_STALE', message, statusCode: 409);

ControlPlaneException _security(String message) => ControlPlaneException(
  'HEALTH_AUTO_HALT_SECURITY_REJECTED',
  message,
  statusCode: 422,
);

String _auditFailureAction(Object error) {
  if (error is ControlPlaneException && error.code.contains('STALE')) {
    return 'health.auto_halt_stale';
  }
  if (error is ControlPlaneException && error.code.contains('SECURITY')) {
    return 'health.auto_halt_security_rejected';
  }
  return 'health.auto_halt_ineligible';
}

String _safeCode(Object error) {
  if (error is ControlPlaneException) return error.code;
  if (error is StorageConflict) return 'HEALTH_AUTO_HALT_CONFLICT';
  return 'HEALTH_AUTO_HALT_REJECTED';
}
