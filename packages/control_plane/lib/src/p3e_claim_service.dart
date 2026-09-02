import 'dart:convert';
import 'dart:math';

import 'auth.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'p3e_claim.dart';
import 'p3e_schedule.dart';
import 'p3e_schedule_persistence.dart';
import 'persistence.dart';
import 'rollout.dart';

/// Explicit request/response claim boundary. It never evaluates health,
/// invokes halt, or schedules itself.
final class P3e5ClaimService {
  P3e5ClaimService({
    required this.controlStore,
    required this.scheduleStore,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure();

  final ControlPlaneStore controlStore;
  final P3e5ScheduleStore scheduleStore;
  final DateTime Function() _clock;
  final Random _random;

  Future<List<P3e5ClaimedWork>> claimDue({
    required String token,
    required P3e5ClaimScope scope,
    required String leaseOwner,
    required P3e5LeasePolicy leasePolicy,
    required P3e5RetryPolicy retryPolicy,
    required P3e5ClaimResourcePolicy resourcePolicy,
    String? requestId,
  }) async {
    final actor = await _authorize(token, scope);
    retryPolicy.validate();
    final prepared = List.generate(
      resourcePolicy.claimBatchSize,
      (_) => P3e5PreparedLease(generateP3e5LeaseToken(_random)),
      growable: false,
    );
    final claimed = await scheduleStore.claimDue(
      P3e5ClaimRequest(
        scope: scope,
        leaseOwner: leaseOwner,
        leasePolicy: leasePolicy,
        resourcePolicy: resourcePolicy,
        preparedLeases: prepared,
      ),
    );
    final accepted = <P3e5ClaimedWork>[];
    for (final claim in claimed) {
      if (!await _currentRolloutBinding(claim.work)) {
        await scheduleStore.failClaim(
          lease: P3e5LeaseMutation(
            scope: scope,
            workId: claim.work.workId,
            expectedWorkVersion: claim.work.workVersion,
            leaseOwner: leaseOwner,
            rawLeaseToken: claim.rawLeaseToken,
          ),
          failure: P3e5RetryFailure(
            classification: P3e5RetryClass.stale,
            safeCode: 'STALE_ROLLOUT_BINDING',
          ),
          retryPolicy: retryPolicy,
        );
        await _audit(actor, requestId, 'health.work_stale', claim.work, const {
          'safeErrorCode': 'STALE_ROLLOUT_BINDING',
        });
        continue;
      }
      accepted.add(claim);
      await _audit(
        actor,
        requestId,
        claim.reclaimed ? 'health.work_reclaimed' : 'health.work_claimed',
        claim.work,
        <String, Object?>{
          'workVersion': claim.work.workVersion,
          'attemptNumber': claim.work.attemptCount,
          'leaseOwner': claim.work.leaseOwner,
          'leaseTokenDigest': claim.work.leaseTokenDigest,
        },
      );
    }
    return List.unmodifiable(accepted);
  }

  Future<ScheduledEvaluationWork> failClaim({
    required String token,
    required P3e5ClaimScope scope,
    required P3e5LeaseMutation lease,
    required P3e5RetryFailure failure,
    required P3e5RetryPolicy retryPolicy,
    String? requestId,
  }) async {
    final actor = await _authorize(token, scope);
    if (lease.scope.organizationId != scope.organizationId ||
        lease.scope.applicationId != scope.applicationId ||
        lease.scope.environmentId != scope.environmentId) {
      await _securityAudit(actor, requestId, lease.workId);
      throw const ControlPlaneException(
        'HEALTH_WORK_NOT_FOUND',
        'Scheduled work was not found',
        statusCode: 404,
      );
    }
    try {
      final result = await scheduleStore.failClaim(
        lease: lease,
        failure: failure,
        retryPolicy: retryPolicy,
      );
      final action =
          result.work.status == ScheduledEvaluationWorkStatus.retryWait
          ? 'health.work_retry_wait'
          : result.work.status == ScheduledEvaluationWorkStatus.stale
          ? 'health.work_stale'
          : 'health.work_retry_exhausted';
      await _audit(actor, requestId, action, result.work, <String, Object?>{
        'workVersion': result.work.workVersion,
        'errorClass': failure.classification.wireName,
        'safeErrorCode': failure.safeCode,
      });
      return result.work;
    } on StorageConflict {
      await _securityAudit(actor, requestId, lease.workId);
      throw const ControlPlaneException(
        'HEALTH_WORK_LEASE_CONFLICT',
        'Lease ownership could not be verified',
        statusCode: 409,
      );
    }
  }

  Future<ScheduledEvaluationWork> cancel({
    required String token,
    required P3e5ClaimScope scope,
    required String workId,
    required int expectedWorkVersion,
    String? requestId,
  }) async {
    final actor = await _authorize(token, scope);
    final result = await scheduleStore.cancelWork(
      scope: scope,
      workId: workId,
      expectedWorkVersion: expectedWorkVersion,
    );
    await _audit(actor, requestId, 'health.work_cancelled', result.work, {
      'workVersion': result.work.workVersion,
    });
    return result.work;
  }

  Future<ScheduledEvaluationWork> manualRetry({
    required String token,
    required P3e5ClaimScope scope,
    required String workId,
    required int expectedWorkVersion,
    required P3e5RetryPolicy retryPolicy,
    String? requestId,
  }) async {
    final actor = await _authorize(token, scope);
    final result = await scheduleStore.manualRetry(
      scope: scope,
      workId: workId,
      expectedWorkVersion: expectedWorkVersion,
      retryPolicy: retryPolicy,
    );
    await _audit(actor, requestId, 'health.work_manual_retry', result.work, {
      'workVersion': result.work.workVersion,
      'retryPolicyVersion': retryPolicy.version,
    });
    return result.work;
  }

  Future<CredentialRecord> _authorize(String token, P3e5ClaimScope scope) =>
      CredentialService.authorize(
        token: token,
        requiredScope: 'health:work:claim',
        read: (hash) async {
          final raw = await controlStore.readJson('credentials', hash);
          return raw == null ? null : CredentialRecord.fromJson(raw);
        },
        organizationId: scope.organizationId,
        applicationId: scope.applicationId,
        environmentId: scope.environmentId,
        kind: CredentialKind.scheduler,
        now: _clock().toUtc(),
      );

  Future<bool> _currentRolloutBinding(ScheduledEvaluationWork work) async {
    final raw = await controlStore.readJson(
      'rollouts',
      work.logicalKey.rolloutId,
    );
    if (raw == null) return false;
    final rollout = RolloutRecord.fromJson(raw);
    if (rollout.organizationId != work.logicalKey.organizationId ||
        rollout.currentRevision != work.logicalKey.rolloutRevision ||
        !rollout.state.servesCandidate)
      return false;
    final revisions = await controlStore.listJson('rollout_revisions');
    final matches = revisions
        .where(
          (raw) =>
              raw['rolloutId'] == rollout.id &&
              raw['revision'] == rollout.currentRevision,
        )
        .map(RolloutRevision.fromJson)
        .toList(growable: false);
    if (matches.length != 1) return false;
    final target = matches.single.target;
    return target.organizationId == work.logicalKey.organizationId &&
        target.applicationId == work.logicalKey.applicationId &&
        target.environmentId == work.logicalKey.environmentId &&
        target.platformId == work.logicalKey.platformId &&
        target.releaseId == work.logicalKey.releaseId &&
        target.patchId == work.logicalKey.patchId &&
        target.sequence == work.logicalKey.sequence &&
        sha256Digest(utf8.encode(canonicalJson(target.toJson()))) ==
            work.logicalKey.targetBindingDigest;
  }

  Future<void> _securityAudit(
    CredentialRecord actor,
    String? requestId,
    String workId,
  ) => _appendAudit(
    actor,
    requestId,
    'health.work_claim_rejected_security',
    workId,
    const {},
  );

  Future<void> _audit(
    CredentialRecord actor,
    String? requestId,
    String action,
    ScheduledEvaluationWork work,
    Map<String, Object?> metadata,
  ) => _appendAudit(actor, requestId, action, work.workId, <String, Object?>{
    'applicationId': work.logicalKey.applicationId,
    'environmentId': work.logicalKey.environmentId,
    'scheduleId': work.logicalKey.scheduleId,
    ...metadata,
  });

  Future<void> _appendAudit(
    CredentialRecord actor,
    String? requestId,
    String action,
    String resourceId,
    Map<String, Object?> metadata,
  ) async {
    final safe = <String, Object?>{
      for (final entry in metadata.entries)
        if (!entry.key.toLowerCase().contains('raw') &&
            !entry.key.toLowerCase().contains('secret') &&
            entry.key != 'leaseToken')
          entry.key: entry.value,
    };
    final id = _id('audit');
    final record = AuditRecord(
      id: id,
      requestId: requestId ?? _id('request'),
      organizationId: actor.organizationId,
      actorId: actor.id,
      action: action,
      resourceType: 'scheduled_evaluation_work',
      resourceId: resourceId,
      result: 'SUCCESS',
      metadata: safe,
      createdAt: _clock().toUtc(),
    );
    await controlStore.appendAudit(id, record.toJson());
  }

  String _id(String prefix) {
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return '${prefix}_${bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
