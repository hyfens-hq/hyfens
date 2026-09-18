import 'dart:convert';
import 'dart:math';

import 'auth.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'p3e_auto_halt.dart';
import 'p3e_schedule.dart';
import 'p3e_schedule_persistence.dart';
import 'persistence.dart';
import 'rollout.dart';

final class ScheduleRevisionConfiguration {
  const ScheduleRevisionConfiguration({
    this.logicalKeyVersion = 1,
    this.scheduledEvaluationEnabled = false,
    this.automaticHaltEnabled = false,
    required this.readinessPhase,
    this.automaticHaltPolicyId,
    this.automaticHaltPolicyVersion,
    this.automaticHaltPolicyDigest,
    this.automaticHaltEligibleSource,
    this.automaticHaltEligibleReadiness,
    this.automaticHaltEligibleReasonClass,
    this.triggerPolicyVersion = supportedP3e5TriggerPolicyVersion,
    this.schedulePolicyVersion = supportedP3e5SchedulePolicyVersion,
    this.evaluationPolicyVersion = supportedP3e5EvaluationPolicyVersion,
    required this.evaluationPolicyDigest,
    this.thresholdSetVersion = supportedP3e5ThresholdSetVersion,
    required this.thresholdSetDigest,
    this.aggregationVersion = supportedP3e5AggregationVersion,
    this.windowPolicyVersion = supportedP3e5WindowPolicyVersion,
    this.privacyPolicyVersion = supportedP3e5PrivacyPolicyVersion,
    required this.retryPolicyReference,
    required this.resourcePolicyReference,
    required this.reason,
  });

  final int logicalKeyVersion;
  final bool scheduledEvaluationEnabled;
  final bool automaticHaltEnabled;
  final EvaluationReadinessPhase readinessPhase;
  final String? automaticHaltPolicyId;
  final int? automaticHaltPolicyVersion;
  final String? automaticHaltPolicyDigest;
  final AutomaticHaltEligibleSource? automaticHaltEligibleSource;
  final AutomaticHaltEligibleReadiness? automaticHaltEligibleReadiness;
  final AutomaticHaltEligibleReasonClass? automaticHaltEligibleReasonClass;
  final int triggerPolicyVersion;
  final int schedulePolicyVersion;
  final int evaluationPolicyVersion;
  final String evaluationPolicyDigest;
  final int thresholdSetVersion;
  final String thresholdSetDigest;
  final int aggregationVersion;
  final int windowPolicyVersion;
  final int privacyPolicyVersion;
  final String retryPolicyReference;
  final String resourcePolicyReference;
  final String reason;
}

final class AutomaticHaltPolicyConfiguration {
  const AutomaticHaltPolicyConfiguration({
    required this.maximumAggregateAgeFromLateCutoff,
    required this.maximumDecisionAgeFromEvaluation,
    required this.resourcePolicyReference,
    required this.approvalReference,
  });

  final Duration maximumAggregateAgeFromLateCutoff;
  final Duration maximumDecisionAgeFromEvaluation;
  final String resourcePolicyReference;
  final String approvalReference;
}

/// Explicit administration/materialization boundary for P3E5-1. It creates no
/// timers, workers, claims, leases, retries, evaluations, or rollout changes.
final class P3e5ScheduleService {
  P3e5ScheduleService({
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

  Future<void> initialize() async {
    await controlStore.initialize();
    await scheduleStore.initialize();
  }

  Future<AutomaticHaltPolicy> registerAutomaticHaltPolicy({
    required String token,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required AutomaticHaltPolicyConfiguration configuration,
    String? requestId,
  }) async {
    final actor = await _authorize(
      token,
      'health:schedule',
      CredentialKind.control,
      organizationId,
      applicationId,
      environmentId,
    );
    await _requireApplicationEnvironment(
      organizationId,
      applicationId,
      environmentId,
    );
    final current = await scheduleStore.readCurrentAutomaticHaltState(
      organizationId,
      applicationId,
      environmentId,
    );
    final now = _now();
    final policy = AutomaticHaltPolicy(
      policyId: _id('auto_halt_policy'),
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
      maximumAggregateAgeFromLateCutoff:
          configuration.maximumAggregateAgeFromLateCutoff,
      maximumDecisionAgeFromEvaluation:
          configuration.maximumDecisionAgeFromEvaluation,
      resourcePolicyReference: configuration.resourcePolicyReference,
      approvalReference: configuration.approvalReference,
      createdAt: now,
      createdBy: actor.id,
    );
    final state = AutomaticHaltEnvironmentState(
      stateId: _id('auto_halt_state'),
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
      generation: (current?.generation ?? 0) + 1,
      supersedesStateId: current?.stateId,
      policyId: policy.policyId,
      automaticHaltPolicyDigest: policy.digest,
      policyApproved: false,
      productionEnabled: false,
      productionEnableReference: null,
      createdAt: now,
      createdBy: actor.id,
    );
    try {
      await scheduleStore.putAutomaticHaltFoundation(policy, state);
    } on StorageConflict {
      await _audit(
        actor,
        requestId ?? _id('request'),
        'health.auto_halt_policy_rejected',
        'automatic_halt_policy',
        policy.policyId,
        <String, Object?>{
          'applicationId': applicationId,
          'environmentId': environmentId,
          'safeCode': 'IMMUTABLE_POLICY_CONFLICT',
        },
      );
      throw const ControlPlaneException(
        'HEALTH_AUTO_HALT_POLICY_CONFLICT',
        'Automatic-halt policy conflicts with persisted state',
        statusCode: 409,
      );
    }
    await _audit(
      actor,
      requestId ?? _id('request'),
      current == null
          ? 'health.auto_halt_policy_created'
          : 'health.auto_halt_policy_revised',
      'automatic_halt_policy',
      policy.policyId,
      <String, Object?>{
        'applicationId': applicationId,
        'environmentId': environmentId,
        'automaticHaltPolicyVersion': policy.automaticHaltPolicyVersion,
        'automaticHaltPolicyDigest': policy.digest,
        'stateId': state.stateId,
        'stateGeneration': state.generation,
        'policyApproved': false,
        'productionEnabled': false,
      },
    );
    return policy;
  }

  Future<AutomaticHaltPolicy?> readAutomaticHaltPolicy({
    required String token,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String policyId,
  }) async {
    await _authorize(
      token,
      'health:schedule',
      CredentialKind.control,
      organizationId,
      applicationId,
      environmentId,
    );
    final policy = await scheduleStore.readAutomaticHaltPolicy(
      organizationId,
      policyId,
    );
    if (policy == null ||
        policy.applicationId != applicationId ||
        policy.environmentId != environmentId) {
      return null;
    }
    return policy;
  }

  Future<EvaluationSchedule> createSchedule({
    required String token,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String rolloutId,
    required int rolloutRevision,
    required ScheduleRevisionConfiguration configuration,
    String? requestId,
  }) async {
    final actor = await _authorize(
      token,
      'health:schedule',
      CredentialKind.control,
      organizationId,
      applicationId,
      environmentId,
    );
    _requireScopes(actor, const <String>{'rollout:read'});
    await _validateAutomaticHaltConfiguration(
      organizationId,
      applicationId,
      environmentId,
      configuration,
    );
    await _trustedRolloutRevision(
      organizationId,
      applicationId,
      environmentId,
      rolloutId,
      rolloutRevision,
      requireCurrent: true,
    );
    final now = _now();
    final scheduleId = _id('schedule');
    final revisionId = _id('schedule_revision');
    final schedule = EvaluationSchedule(
      scheduleId: scheduleId,
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
      rolloutId: rolloutId,
      currentScheduleRevision: revisionId,
      createdAt: now,
      createdBy: actor.id,
    );
    final revision = _revision(
      schedule: schedule,
      revisionId: revisionId,
      generation: 1,
      supersedes: null,
      actor: actor,
      configuration: configuration,
      now: now,
    );
    await scheduleStore.createSchedule(schedule, revision);
    await _audit(
      actor,
      requestId ?? _id('request'),
      'health.schedule_created',
      'evaluation_schedule',
      schedule.scheduleId,
      <String, Object?>{
        'applicationId': applicationId,
        'environmentId': environmentId,
        'rolloutId': rolloutId,
        'scheduleRevisionId': revision.scheduleRevisionId,
        'scheduleGeneration': revision.scheduleGeneration,
        'scheduledEvaluationEnabled': revision.scheduledEvaluationEnabled,
        'automaticHaltEnabled': revision.automaticHaltEnabled,
      },
    );
    return schedule;
  }

  Future<EvaluationSchedule> reviseSchedule({
    required String token,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String scheduleId,
    required String expectedCurrentRevisionId,
    required ScheduleRevisionConfiguration configuration,
    String? requestId,
  }) async {
    final actor = await _authorize(
      token,
      'health:schedule',
      CredentialKind.control,
      organizationId,
      applicationId,
      environmentId,
    );
    _requireScopes(actor, const <String>{'rollout:read'});
    await _validateAutomaticHaltConfiguration(
      organizationId,
      applicationId,
      environmentId,
      configuration,
    );
    final currentSchedule = await scheduleStore.readSchedule(
      organizationId,
      scheduleId,
    );
    if (currentSchedule == null ||
        currentSchedule.applicationId != applicationId ||
        currentSchedule.environmentId != environmentId) {
      throw _notFound();
    }
    final currentRevision = await scheduleStore.readRevision(
      organizationId,
      currentSchedule.currentScheduleRevision,
    );
    if (currentRevision == null) {
      throw const ControlPlaneException(
        'HEALTH_SCHEDULE_STORAGE_CORRUPT',
        'Schedule current revision is missing',
        statusCode: 500,
      );
    }
    await _trustedRolloutRevision(
      organizationId,
      applicationId,
      environmentId,
      currentSchedule.rolloutId,
      (await _rollout(currentSchedule.rolloutId)).currentRevision,
      requireCurrent: true,
    );
    final now = _now();
    final revisionId = _id('schedule_revision');
    final updated = currentSchedule.withCurrentRevision(revisionId);
    final revision = _revision(
      schedule: updated,
      revisionId: revisionId,
      generation: currentRevision.scheduleGeneration + 1,
      supersedes: currentRevision.scheduleRevisionId,
      actor: actor,
      configuration: configuration,
      now: now,
    );
    try {
      await scheduleStore.reviseSchedule(
        schedule: updated,
        expectedCurrentRevisionId: expectedCurrentRevisionId,
        revision: revision,
      );
    } on StoragePreconditionFailed catch (error) {
      throw ControlPlaneException(
        'HEALTH_SCHEDULE_CONFLICT',
        'Schedule revision does not match the current revision',
        statusCode: 409,
        details: <String, Object?>{'currentGeneration': error.currentRevision},
      );
    }
    await _audit(
      actor,
      requestId ?? _id('request'),
      'health.schedule_updated',
      'evaluation_schedule',
      scheduleId,
      <String, Object?>{
        'applicationId': applicationId,
        'environmentId': environmentId,
        'rolloutId': currentSchedule.rolloutId,
        'scheduleRevisionId': revision.scheduleRevisionId,
        'scheduleGeneration': revision.scheduleGeneration,
        'supersedesScheduleRevisionId': revision.supersedesScheduleRevisionId,
      },
    );
    return updated;
  }

  Future<ScheduledEvaluationWork> materializeWork({
    required String token,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String scheduleId,
    required String scheduleRevisionId,
    required int rolloutRevision,
    required String windowId,
    required int observationSchemaVersion,
    required String aggregatePolicyDigest,
    String? requestId,
  }) async {
    final actor = await _authorize(
      token,
      'health:work:claim',
      CredentialKind.scheduler,
      organizationId,
      applicationId,
      environmentId,
    );
    _requireScopes(actor, const <String>{
      'health:evaluate',
      'observation:read',
      'rollout:read',
    });
    final schedule = await scheduleStore.readSchedule(
      organizationId,
      scheduleId,
    );
    final revision = await scheduleStore.readRevision(
      organizationId,
      scheduleRevisionId,
    );
    if (schedule == null ||
        revision == null ||
        schedule.applicationId != applicationId ||
        schedule.environmentId != environmentId ||
        schedule.currentScheduleRevision != scheduleRevisionId) {
      throw _notFound();
    }
    if (!revision.scheduledEvaluationEnabled) {
      throw const ControlPlaneException(
        'HEALTH_SCHEDULE_DISABLED',
        'Scheduled evaluation is disabled for this revision',
        statusCode: 409,
      );
    }
    final trusted = await _trustedRolloutRevision(
      organizationId,
      applicationId,
      environmentId,
      schedule.rolloutId,
      rolloutRevision,
      requireCurrent: false,
    );
    final key = LogicalEvaluationKey(
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
      platformId: trusted.target.platformId,
      rolloutId: schedule.rolloutId,
      rolloutRevision: rolloutRevision,
      releaseId: trusted.target.releaseId,
      patchId: trusted.target.patchId,
      sequence: trusted.target.sequence,
      targetBindingDigest: sha256Digest(
        utf8.encode(canonicalJson(trusted.target.toJson())),
      ),
      windowId: windowId,
      readinessPhase: revision.readinessPhase,
      observationSchemaVersion: observationSchemaVersion,
      aggregationVersion: revision.aggregationVersion,
      aggregatePolicyDigest: aggregatePolicyDigest,
      evaluationPolicyVersion: revision.evaluationPolicyVersion,
      evaluationPolicyDigest: revision.evaluationPolicyDigest,
      thresholdSetVersion: revision.thresholdSetVersion,
      thresholdSetDigest: revision.thresholdSetDigest,
      windowPolicyVersion: revision.windowPolicyVersion,
      privacyPolicyVersion: revision.privacyPolicyVersion,
      scheduleId: schedule.scheduleId,
      scheduleRevisionId: revision.scheduleRevisionId,
      scheduleGeneration: revision.scheduleGeneration,
      automaticHaltPolicyId: revision.automaticHaltPolicyId,
      automaticHaltPolicyVersion: revision.automaticHaltPolicyVersion,
      automaticHaltPolicyDigest: revision.automaticHaltPolicyDigest,
      automaticHaltEnabled: revision.logicalKeyVersion == 2
          ? revision.automaticHaltEnabled
          : null,
      automaticHaltEligibleSource: revision.automaticHaltEligibleSource,
      automaticHaltEligibleReadiness: revision.automaticHaltEligibleReadiness,
      automaticHaltEligibleReasonClass:
          revision.automaticHaltEligibleReasonClass,
      logicalKeyVersion: revision.logicalKeyVersion,
    );
    final existing = await scheduleStore.readWork(organizationId, key.workId);
    if (existing != null) {
      if (existing.logicalKey.canonicalSerialization !=
          key.canonicalSerialization) {
        throw const ControlPlaneException(
          'HEALTH_WORK_CONFLICT',
          'Deterministic work identity conflicts with persisted content',
          statusCode: 409,
        );
      }
      return existing;
    }
    final work = ScheduledEvaluationWork.pending(
      logicalKey: key,
      serverNow: _now(),
    );
    try {
      await scheduleStore.putWork(work);
    } on StorageConflict {
      final raced = await scheduleStore.readWork(organizationId, work.workId);
      if (raced == null ||
          raced.logicalKey.canonicalSerialization !=
              key.canonicalSerialization) {
        throw const ControlPlaneException(
          'HEALTH_WORK_CONFLICT',
          'Deterministic work identity conflicts with persisted content',
          statusCode: 409,
        );
      }
      return raced;
    }
    await _audit(
      actor,
      requestId ?? _id('request'),
      'health.work_materialized',
      'scheduled_evaluation_work',
      work.workId,
      <String, Object?>{
        'applicationId': applicationId,
        'environmentId': environmentId,
        'rolloutId': schedule.rolloutId,
        'rolloutRevision': rolloutRevision,
        'scheduleId': scheduleId,
        'scheduleRevisionId': scheduleRevisionId,
        'logicalKeyDigest': key.digest,
      },
    );
    return work;
  }

  Future<EvaluationSchedule?> readSchedule({
    required String token,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String scheduleId,
  }) async {
    await _authorize(
      token,
      'health:schedule',
      CredentialKind.control,
      organizationId,
      applicationId,
      environmentId,
    );
    final schedule = await scheduleStore.readSchedule(
      organizationId,
      scheduleId,
    );
    if (schedule == null ||
        schedule.applicationId != applicationId ||
        schedule.environmentId != environmentId) {
      return null;
    }
    return schedule;
  }

  EvaluationScheduleRevision _revision({
    required EvaluationSchedule schedule,
    required String revisionId,
    required int generation,
    required String? supersedes,
    required CredentialRecord actor,
    required ScheduleRevisionConfiguration configuration,
    required DateTime now,
  }) => EvaluationScheduleRevision(
    scheduleRevisionId: revisionId,
    scheduleId: schedule.scheduleId,
    scheduleGeneration: generation,
    organizationId: schedule.organizationId,
    applicationId: schedule.applicationId,
    environmentId: schedule.environmentId,
    rolloutId: schedule.rolloutId,
    logicalKeyVersion: configuration.logicalKeyVersion,
    scheduledEvaluationEnabled: configuration.scheduledEvaluationEnabled,
    automaticHaltEnabled: configuration.automaticHaltEnabled,
    readinessPhase: configuration.readinessPhase,
    automaticHaltPolicyId: configuration.automaticHaltPolicyId,
    automaticHaltPolicyVersion: configuration.automaticHaltPolicyVersion,
    automaticHaltPolicyDigest: configuration.automaticHaltPolicyDigest,
    automaticHaltEligibleSource: configuration.automaticHaltEligibleSource,
    automaticHaltEligibleReadiness:
        configuration.automaticHaltEligibleReadiness,
    automaticHaltEligibleReasonClass:
        configuration.automaticHaltEligibleReasonClass,
    triggerPolicyVersion: configuration.triggerPolicyVersion,
    schedulePolicyVersion: configuration.schedulePolicyVersion,
    evaluationPolicyVersion: configuration.evaluationPolicyVersion,
    evaluationPolicyDigest: configuration.evaluationPolicyDigest,
    thresholdSetVersion: configuration.thresholdSetVersion,
    thresholdSetDigest: configuration.thresholdSetDigest,
    aggregationVersion: configuration.aggregationVersion,
    windowPolicyVersion: configuration.windowPolicyVersion,
    privacyPolicyVersion: configuration.privacyPolicyVersion,
    retryPolicyReference: configuration.retryPolicyReference,
    resourcePolicyReference: configuration.resourcePolicyReference,
    supersedesScheduleRevisionId: supersedes,
    createdAt: now,
    createdBy: actor.id,
    reason: configuration.reason,
  );

  Future<CredentialRecord> _authorize(
    String token,
    String scope,
    CredentialKind kind,
    String organizationId,
    String applicationId,
    String environmentId,
  ) => CredentialService.authorize(
    token: token,
    requiredScope: scope,
    read: (hash) async {
      final raw = await controlStore.readJson('credentials', hash);
      return raw == null ? null : CredentialRecord.fromJson(raw);
    },
    organizationId: organizationId,
    applicationId: applicationId,
    environmentId: environmentId,
    kind: kind,
    now: _now(),
  );

  void _requireScopes(CredentialRecord actor, Set<String> required) {
    if (!actor.scopes.containsAll(required)) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'Credential does not have the required scheduler scopes',
        statusCode: 403,
      );
    }
  }

  Future<RolloutRecord> _rollout(String rolloutId) async {
    final raw = await controlStore.readJson('rollouts', rolloutId);
    if (raw == null) throw _notFound();
    return RolloutRecord.fromJson(raw);
  }

  Future<void> _requireApplicationEnvironment(
    String organizationId,
    String applicationId,
    String environmentId,
  ) async {
    final rawApplication = await controlStore.readJson(
      'applications',
      applicationId,
    );
    final rawEnvironment = await controlStore.readJson(
      'environments',
      environmentId,
    );
    if (rawApplication == null || rawEnvironment == null) throw _notFound();
    final application = ApplicationRecord.fromJson(rawApplication);
    final environment = EnvironmentRecord.fromJson(rawEnvironment);
    if (application.organizationId != organizationId ||
        environment.organizationId != organizationId ||
        environment.applicationId != applicationId) {
      throw _notFound();
    }
  }

  Future<void> _validateAutomaticHaltConfiguration(
    String organizationId,
    String applicationId,
    String environmentId,
    ScheduleRevisionConfiguration configuration,
  ) async {
    if (configuration.logicalKeyVersion == 1) return;
    if (configuration.logicalKeyVersion != supportedP3e5LogicalKeyVersion ||
        configuration.automaticHaltPolicyId == null ||
        configuration.automaticHaltPolicyVersion == null ||
        configuration.automaticHaltPolicyDigest == null ||
        configuration.automaticHaltPolicyVersion !=
            supportedAutomaticHaltPolicyVersion ||
        configuration.readinessPhase != EvaluationReadinessPhase.sealed ||
        configuration.automaticHaltEligibleSource !=
            AutomaticHaltEligibleSource.scheduledOnly ||
        configuration.automaticHaltEligibleReadiness !=
            AutomaticHaltEligibleReadiness.sealedOnly ||
        configuration.automaticHaltEligibleReasonClass !=
            AutomaticHaltEligibleReasonClass.patchSafetyOnly) {
      throw const ControlPlaneException(
        'HEALTH_AUTO_HALT_POLICY_INVALID',
        'Automatic-halt policy binding is invalid',
      );
    }
    final policy = await scheduleStore.readAutomaticHaltPolicy(
      organizationId,
      configuration.automaticHaltPolicyId!,
    );
    final current = await scheduleStore.readCurrentAutomaticHaltState(
      organizationId,
      applicationId,
      environmentId,
    );
    if (policy == null ||
        policy.applicationId != applicationId ||
        policy.environmentId != environmentId ||
        policy.automaticHaltPolicyVersion !=
            configuration.automaticHaltPolicyVersion ||
        policy.digest != configuration.automaticHaltPolicyDigest ||
        current == null ||
        current.policyId != policy.policyId ||
        current.automaticHaltPolicyDigest != policy.digest) {
      throw const ControlPlaneException(
        'HEALTH_AUTO_HALT_POLICY_STALE',
        'Automatic-halt policy is missing, foreign, or no longer current',
        statusCode: 409,
      );
    }
  }

  Future<RolloutRevision> _trustedRolloutRevision(
    String organizationId,
    String applicationId,
    String environmentId,
    String rolloutId,
    int revision, {
    required bool requireCurrent,
  }) async {
    final rollout = await _rollout(rolloutId);
    if (rollout.organizationId != organizationId ||
        (requireCurrent && rollout.currentRevision != revision)) {
      throw _notFound();
    }
    final matches = (await controlStore.listJson('rollout_revisions'))
        .where(
          (raw) => raw['rolloutId'] == rolloutId && raw['revision'] == revision,
        )
        .map(RolloutRevision.fromJson)
        .toList(growable: false);
    if (matches.length != 1) {
      throw const ControlPlaneException(
        'HEALTH_SCHEDULE_TARGET_INVALID',
        'Trusted rollout revision is missing or duplicated',
        statusCode: 409,
      );
    }
    final trusted = matches.single;
    if (trusted.organizationId != organizationId ||
        trusted.target.organizationId != organizationId ||
        trusted.target.applicationId != applicationId ||
        trusted.target.environmentId != environmentId ||
        trusted.target.releaseId.isEmpty ||
        trusted.target.patchId.isEmpty ||
        trusted.target.sequence <= 0) {
      throw _notFound();
    }
    return trusted;
  }

  Future<void> _audit(
    CredentialRecord actor,
    String requestId,
    String action,
    String resourceType,
    String resourceId,
    Map<String, Object?> metadata,
  ) async {
    final safe = <String, Object?>{
      for (final entry in metadata.entries)
        if (!entry.key.toLowerCase().contains('token') &&
            !entry.key.toLowerCase().contains('secret') &&
            !entry.key.toLowerCase().contains('private'))
          entry.key: entry.value,
    };
    final audit = AuditRecord(
      id: _id('audit'),
      requestId: requestId,
      organizationId: actor.organizationId,
      actorId: actor.id,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      result: 'SUCCESS',
      metadata: safe,
      createdAt: _now(),
    );
    await controlStore.appendAudit(audit.id, audit.toJson());
  }

  DateTime _now() => _clock().toUtc();

  String _id(String prefix) {
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return '${prefix}_${bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';
  }

  ControlPlaneException _notFound() => const ControlPlaneException(
    'HEALTH_SCHEDULE_NOT_FOUND',
    'Resource was not found',
    statusCode: 404,
  );
}
