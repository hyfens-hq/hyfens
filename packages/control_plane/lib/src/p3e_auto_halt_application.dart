import 'dart:convert';

import 'auth.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'p3e_auto_halt.dart';
import 'p3e_auto_halt_applicability.dart';
import 'p3e_auto_halt_authority.dart';
import 'p3e_claim.dart';
import 'p3e_halt.dart';
import 'p3e_persistence.dart';
import 'p3e_schedule.dart';
import 'p3e_schedule_persistence.dart';
import 'persistence.dart';
import 'rollout.dart';
import 'service.dart';

enum P3e5AutomaticHaltApplicationFailurePoint {
  beforeP3e4,
  afterP3e4,
  beforeCompletion,
}

final class P3e5AutomaticHaltApplicationResult {
  const P3e5AutomaticHaltApplicationResult({
    required this.work,
    required this.application,
    required this.workChanged,
    required this.recovered,
  });

  final ScheduledEvaluationWork work;
  final HealthHaltApplication application;
  final bool workChanged;
  final bool recovered;
}

final class P3e5AutomaticHaltApplicationEvidence {
  const P3e5AutomaticHaltApplicationEvidence({
    required this.work,
    required this.application,
  });

  final ScheduledEvaluationWork work;
  final HealthHaltApplication? application;
}

/// The one authorized P3E5-4C adapter. It has no rollout write path: all
/// delivery-eligibility mutation is delegated to ControlPlaneService's shared
/// P3E-4 application core and its existing P3A expected-revision CAS.
final class P3e5AutomaticHaltApplicationService {
  P3e5AutomaticHaltApplicationService({
    required this.controlStore,
    required this.scheduleStore,
    required this.p3eStore,
    required this.controlService,
    DateTime Function()? clock,
    this.failure,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _applicability = P3e5AutomaticHaltApplicabilityService(
         controlStore: controlStore,
         scheduleStore: scheduleStore,
         p3eStore: p3eStore,
         clock: clock,
       );

  final ControlPlaneStore controlStore;
  final P3e5ScheduleStore scheduleStore;
  final P3ePersistenceStore p3eStore;
  final ControlPlaneService controlService;
  final DateTime Function() _clock;
  final Future<void> Function(P3e5AutomaticHaltApplicationFailurePoint point)?
  failure;
  final P3e5AutomaticHaltApplicabilityService _applicability;

  Future<P3e5AutomaticHaltApplicationResult> apply({
    required String token,
    required P3e5LeaseMutation lease,
    String? requestId,
  }) async {
    final now = _clock().toUtc();
    final principal = await _authorize(token, lease.scope, now);
    final authority = AutomaticHaltAuthority(
      lease: lease,
      principal: principal,
      authoritativeNow: now,
    );
    try {
      var work = await _readWork(lease);
      if (work.status == ScheduledEvaluationWorkStatus.completed) {
        final application = await _completedApplication(work, lease.scope);
        await _audit(
          principal,
          requestId,
          'health.auto_halt_recovered',
          work.workId,
          <String, Object?>{'applicationId': application.applicationId},
        );
        return P3e5AutomaticHaltApplicationResult(
          work: work,
          application: application,
          workChanged: false,
          recovered: true,
        );
      }
      if (work.status != ScheduledEvaluationWorkStatus.haltApplying ||
          work.automaticHaltIntent == null) {
        throw _stale('Automatic-halt work is not applying');
      }
      final intent = work.automaticHaltIntent!;
      if (intent.authorizedPrincipalId != principal.id) {
        throw _security('Automatic-halt principal does not match intent');
      }
      authority.validateAt(now);
      _validateLease(work, lease, now);

      final existing = await _findApplication(
        lease.scope.organizationId,
        work.logicalKey.haltIdempotencyKey,
      );
      late final HealthHaltApplication application;
      late final bool recovered;
      P3e5AutomaticHaltCurrentEvidence? evidence;
      if (existing != null) {
        if (!existing.applied) {
          throw _security('Existing automatic-halt application is not applied');
        }
        _verifyApplicationLink(work, intent, existing);
        await _verifyP3aHalt(work, existing, lease.scope.organizationId);
        application = existing;
        recovered = true;
        await _audit(
          principal,
          requestId,
          'health.auto_halt_recovered',
          work.workId,
          <String, Object?>{
            'applicationId': application.applicationId,
            'result': application.result,
          },
        );
      } else {
        evidence = await _applicability.validateIntent(
          token: token,
          lease: lease,
          allowCommittedHaltRecovery: true,
        );
        if (evidence.principal?.id != principal.id ||
            evidence.work.workVersion != work.workVersion) {
          throw _security('Automatic-halt currentness changed before P3E-4');
        }
        await _audit(
          principal,
          requestId,
          'health.auto_halt_requested',
          work.workId,
          <String, Object?>{
            'decisionId': intent.decisionId,
            'intentDigest': intent.intentDigest,
          },
        );
        await failure?.call(
          P3e5AutomaticHaltApplicationFailurePoint.beforeP3e4,
        );
        application = await controlService.applyAutomaticHealthHalt(
          token: token,
          lease: lease,
          work: work,
          intent: intent,
          evidence: evidence,
          requestId: requestId,
        );
        recovered = application.result == 'ALREADY_APPLIED';
        await failure?.call(P3e5AutomaticHaltApplicationFailurePoint.afterP3e4);
        _verifyApplicationLink(work, intent, application);
        await _verifyP3aHalt(work, application, lease.scope.organizationId);
        await _audit(
          principal,
          requestId,
          recovered
              ? 'health.auto_halt_already_applied'
              : 'health.auto_halt_applied',
          work.workId,
          <String, Object?>{
            'applicationId': application.applicationId,
            'result': application.result,
          },
        );
      }

      await failure?.call(
        P3e5AutomaticHaltApplicationFailurePoint.beforeCompletion,
      );
      final completion = P3e5AutomaticHaltCompletion(
        lease: lease,
        intentDigest: intent.intentDigest,
        haltApplicationId: application.applicationId,
        idempotencyKey: application.idempotencyKey,
        evaluationId: application.evaluationId,
        decisionId: application.decisionId,
        previousRolloutRevision: application.previousRolloutRevision!,
        resultingRolloutRevision: application.resultingRolloutRevision!,
        resultingTransitionReference: application.resultingTransitionReference!,
        result: application.result,
      );
      late final P3e5WorkMutationResult completed;
      try {
        completed = await scheduleStore.completeAutomaticHalt(completion);
      } on StorageConflict {
        final current = await scheduleStore.readWork(
          lease.scope.organizationId,
          lease.workId,
        );
        if (current?.status != ScheduledEvaluationWorkStatus.completed ||
            current?.haltApplicationId != application.applicationId) {
          rethrow;
        }
        work = current!;
        return P3e5AutomaticHaltApplicationResult(
          work: work,
          application: application,
          workChanged: false,
          recovered: true,
        );
      }
      work = completed.work;
      return P3e5AutomaticHaltApplicationResult(
        work: work,
        application: application,
        workChanged: completed.changed,
        recovered: recovered,
      );
    } on Object catch (error) {
      try {
        await _audit(
          principal,
          requestId,
          _failureAction(error),
          lease.workId,
          <String, Object?>{'code': _safeCode(error)},
        );
      } on Object {
        // The automatic path remains fail-closed when its optional audit
        // append is unavailable.
      }
      rethrow;
    }
  }

  /// Performs the evidence-first lookup used by recovery. It authorizes the
  /// exact Auto-Halt Principal and verifies a found application against the
  /// current work intent and P3A revision before a caller may retry.
  Future<P3e5AutomaticHaltApplicationEvidence> inspectExistingApplication({
    required String token,
    required P3e5ClaimScope scope,
    required String workId,
    required int maximumApplicationRecords,
    required int maximumLinkageRecords,
  }) async {
    if (maximumApplicationRecords <= 0 || maximumLinkageRecords <= 0) {
      throw const FormatException('Application evidence limit is invalid');
    }
    final principal = await _authorize(token, scope, _clock().toUtc());
    final work = await scheduleStore.readWork(scope.organizationId, workId);
    if (work == null || !scope.contains(work)) {
      throw const StorageConflict('Scheduled work was not found');
    }
    final applications = await p3eStore.listHaltApplications(
      scope.organizationId,
    );
    if (applications.length > maximumApplicationRecords) {
      throw _conflict('Automatic-halt evidence exceeds recovery bound');
    }
    final rolloutRevisions = (await controlStore.listJson('rollout_revisions'))
        .where(
          (value) =>
              value['organizationId'] == scope.organizationId &&
              value['rolloutId'] == work.logicalKey.rolloutId,
        )
        .toList(growable: false);
    if (rolloutRevisions.length > maximumLinkageRecords) {
      throw _conflict('Automatic-halt linkage exceeds recovery bound');
    }
    final matching = applications
        .where(
          (application) =>
              application.idempotencyKey == work.logicalKey.haltIdempotencyKey,
        )
        .toList(growable: false);
    if (matching.length > 1) {
      throw _corrupt('Duplicate automatic-halt application evidence exists');
    }
    final application = matching.isEmpty ? null : matching.single;
    if (application == null) {
      return P3e5AutomaticHaltApplicationEvidence(
        work: work,
        application: null,
      );
    }
    final intent = work.automaticHaltIntent;
    if (intent == null || !application.applied) {
      throw _corrupt('Automatic-halt application evidence is incomplete');
    }
    if (application.organizationId != principal.organizationId) {
      throw _security('Automatic-halt application scope is invalid');
    }
    try {
      _verifyApplicationLink(work, intent, application);
      await _verifyP3aHalt(work, application, scope.organizationId);
    } on ControlPlaneException catch (error) {
      throw _corrupt(error.message);
    }
    return P3e5AutomaticHaltApplicationEvidence(
      work: work,
      application: application,
    );
  }

  Future<ScheduledEvaluationWork> _readWork(P3e5LeaseMutation lease) async {
    final work = await scheduleStore.readWork(
      lease.scope.organizationId,
      lease.workId,
    );
    if (work == null || !lease.scope.contains(work)) {
      throw const StorageConflict('Scheduled work was not found');
    }
    return work;
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

  Future<HealthHaltApplication?> _findApplication(
    String organizationId,
    String idempotencyKey, {
    int? maximumRecords,
  }) async {
    final applications = await p3eStore.listHaltApplications(organizationId);
    if (maximumRecords != null && applications.length > maximumRecords) {
      throw _conflict('Automatic-halt evidence exceeds recovery bound');
    }
    final matching = applications
        .where((application) => application.idempotencyKey == idempotencyKey)
        .toList(growable: false);
    if (matching.length > 1) {
      throw _security('Duplicate automatic-halt application evidence exists');
    }
    return matching.isEmpty ? null : matching.single;
  }

  Future<HealthHaltApplication> _completedApplication(
    ScheduledEvaluationWork work,
    P3e5ClaimScope scope,
  ) async {
    final applicationId = work.haltApplicationId;
    if (applicationId == null) {
      throw _security('Completed automatic-halt work has no application link');
    }
    final application = await p3eStore.readHaltApplication(
      scope.organizationId,
      applicationId,
    );
    if (application == null || !application.applied) {
      throw _security(
        'Completed automatic-halt application evidence is invalid',
      );
    }
    final intent = work.automaticHaltIntent;
    if (intent == null) {
      throw _security('Completed automatic-halt work has no intent');
    }
    _verifyApplicationLink(work, intent, application);
    await _verifyP3aHalt(work, application, scope.organizationId);
    return application;
  }

  void _validateLease(
    ScheduledEvaluationWork work,
    P3e5LeaseMutation lease,
    DateTime now,
  ) {
    if (work.workVersion != lease.expectedWorkVersion ||
        work.status != ScheduledEvaluationWorkStatus.haltApplying ||
        !lease.scope.contains(work) ||
        work.leaseOwner != lease.leaseOwner ||
        work.leaseTokenDigest != lease.tokenDigest ||
        work.leaseExpiresAt == null ||
        !work.leaseExpiresAt!.isAfter(now)) {
      throw const StorageConflict('Lease ownership is invalid or expired');
    }
  }

  void _verifyApplicationLink(
    ScheduledEvaluationWork work,
    AutomaticHaltIntent intent,
    HealthHaltApplication application,
  ) {
    if (application.organizationId != work.logicalKey.organizationId ||
        application.actorIdentity != intent.authorizedPrincipalId ||
        application.decisionId != intent.decisionId ||
        application.evaluationId != intent.evaluationId ||
        application.aggregateRevisionId != work.aggregateRevisionId ||
        application.rolloutId != work.logicalKey.rolloutId ||
        application.expectedRolloutRevision != intent.expectedRolloutRevision ||
        application.idempotencyKey != work.logicalKey.haltIdempotencyKey ||
        application.previousRolloutRevision != intent.expectedRolloutRevision ||
        application.resultingRolloutRevision !=
            intent.expectedRolloutRevision + 1 ||
        application.resultingTransitionReference == null ||
        !application.applied) {
      throw _security('Automatic-halt application linkage is invalid');
    }
  }

  Future<void> _verifyP3aHalt(
    ScheduledEvaluationWork work,
    HealthHaltApplication application,
    String organizationId,
  ) async {
    final rolloutRaw = await controlStore.readJson(
      'rollouts',
      work.logicalKey.rolloutId,
    );
    if (rolloutRaw == null) throw _security('Rollout history is missing');
    final rollout = RolloutRecord.fromJson(rolloutRaw);
    final revisions = (await controlStore.listJson('rollout_revisions'))
        .where(
          (value) =>
              value['rolloutId'] == rollout.id &&
              value['revision'] == application.resultingRolloutRevision,
        )
        .map(RolloutRevision.fromJson)
        .toList(growable: false);
    if (rollout.organizationId != organizationId ||
        rollout.currentRevision != application.resultingRolloutRevision ||
        revisions.length != 1) {
      throw _security('Automatic-halt P3A revision is not current');
    }
    final revision = revisions.single;
    final marker = 'P3E4 health halt decision ${application.decisionId}:';
    final targetDigest = sha256Digest(
      utf8.encode(canonicalJson(revision.target.toJson())),
    );
    if (revision.state != RolloutState.halted ||
        revision.previousRevision != application.previousRolloutRevision ||
        revision.id != application.resultingTransitionReference ||
        !revision.reason.startsWith(marker) ||
        targetDigest != work.logicalKey.targetBindingDigest) {
      throw _security('Automatic-halt P3A revision linkage is invalid');
    }
  }

  Future<void> _audit(
    CredentialRecord principal,
    String? requestId,
    String action,
    String workId,
    Map<String, Object?> metadata,
  ) async {
    final record = AuditRecord(
      id: 'audit_${sha256Hex(utf8.encode('$workId:$action:${_clock().microsecondsSinceEpoch}')).substring(0, 32)}',
      requestId: requestId ?? 'request_$workId',
      organizationId: principal.organizationId,
      actorId: principal.id,
      action: action,
      resourceType: 'scheduled-evaluation-work',
      resourceId: workId,
      result: action.contains('stale') || action.contains('security')
          ? 'REJECTED'
          : 'SUCCESS',
      metadata: metadata,
      createdAt: _clock().toUtc(),
    );
    await controlStore.appendAudit(record.id, record.toJson());
  }
}

ControlPlaneException _stale(String message) =>
    ControlPlaneException('HEALTH_AUTO_HALT_STALE', message, statusCode: 409);

ControlPlaneException _conflict(String message) => ControlPlaneException(
  'HEALTH_AUTO_HALT_CONFLICT',
  message,
  statusCode: 409,
);

ControlPlaneException _corrupt(String message) => ControlPlaneException(
  'HEALTH_AUTO_HALT_APPLICATION_CORRUPT',
  message,
  statusCode: 422,
);

ControlPlaneException _security(String message) => ControlPlaneException(
  'HEALTH_AUTO_HALT_SECURITY_REJECTED',
  message,
  statusCode: 422,
);

String _failureAction(Object error) {
  if (error is ControlPlaneException && error.code.contains('SECURITY')) {
    return 'health.auto_halt_security_rejected';
  }
  if (error is ControlPlaneException && error.code.contains('STALE')) {
    return 'health.auto_halt_stale';
  }
  return 'health.auto_halt_failed';
}

String _safeCode(Object error) {
  if (error is ControlPlaneException) return error.code;
  if (error is StorageConflict) return 'HEALTH_AUTO_HALT_CONFLICT';
  return 'HEALTH_AUTO_HALT_FAILED';
}
