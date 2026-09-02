import 'dart:convert';

import 'encoding.dart';
import 'p3e_auto_halt.dart';

const int p3e5ScheduleSchemaVersion = 1;
const int supportedP3e5LogicalKeyVersion = 2;
const int supportedP3e5TriggerPolicyVersion = 1;
const int supportedP3e5SchedulePolicyVersion = 1;
const int supportedP3e5EvaluationPolicyVersion = 1;
const int supportedP3e5ThresholdSetVersion = 1;
const int supportedP3e5AggregationVersion = 1;
const int supportedP3e5WindowPolicyVersion = 1;
const int supportedP3e5PrivacyPolicyVersion = 1;

final class P3e5ScheduleLimits {
  const P3e5ScheduleLimits({
    this.maximumReasonLength = 512,
    this.maximumLogicalKeyBytes = 16 * 1024,
    this.maximumWorkBytes = 64 * 1024,
    this.maximumAttemptBytes = 32 * 1024,
    this.maximumSafeErrorCodeLength = 128,
    this.maximumPageSize = 200,
  });

  final int maximumReasonLength;
  final int maximumLogicalKeyBytes;
  final int maximumWorkBytes;
  final int maximumAttemptBytes;
  final int maximumSafeErrorCodeLength;
  final int maximumPageSize;

  void validate() {
    if (maximumReasonLength <= 0 ||
        maximumLogicalKeyBytes <= 0 ||
        maximumWorkBytes <= 0 ||
        maximumAttemptBytes <= 0 ||
        maximumSafeErrorCodeLength <= 0 ||
        maximumPageSize <= 0) {
      throw const FormatException('P3E5 schedule limits are invalid');
    }
  }
}

enum EvaluationReadinessPhase { closed, sealed }

extension EvaluationReadinessPhaseWire on EvaluationReadinessPhase {
  String get wireName => name.toUpperCase();
}

EvaluationReadinessPhase parseEvaluationReadinessPhase(Object? value) =>
    switch (value) {
      'CLOSED' => EvaluationReadinessPhase.closed,
      'SEALED' => EvaluationReadinessPhase.sealed,
      _ => throw const FormatException(
        'Unsupported scheduled-evaluation readiness phase',
      ),
    };

enum ScheduledEvaluationWorkStatus {
  pending,
  leased,
  evaluating,
  evaluated,
  haltApplying,
  retryWait,
  completed,
  stale,
  failedPermanent,
  cancelled,
}

extension ScheduledEvaluationWorkStatusWire on ScheduledEvaluationWorkStatus {
  String get wireName => switch (this) {
    ScheduledEvaluationWorkStatus.haltApplying => 'HALT_APPLYING',
    ScheduledEvaluationWorkStatus.retryWait => 'RETRY_WAIT',
    ScheduledEvaluationWorkStatus.failedPermanent => 'FAILED_PERMANENT',
    _ => name.toUpperCase(),
  };

  bool get isTerminal => switch (this) {
    ScheduledEvaluationWorkStatus.completed ||
    ScheduledEvaluationWorkStatus.stale ||
    ScheduledEvaluationWorkStatus.cancelled => true,
    _ => false,
  };
}

ScheduledEvaluationWorkStatus parseScheduledEvaluationWorkStatus(
  Object? value,
) {
  for (final status in ScheduledEvaluationWorkStatus.values) {
    if (status.wireName == value) return status;
  }
  throw const FormatException('Unsupported scheduled-evaluation work status');
}

bool isValidScheduledEvaluationTransition(
  ScheduledEvaluationWorkStatus from,
  ScheduledEvaluationWorkStatus to,
) {
  if (from.isTerminal || from == to) return false;
  if (to == ScheduledEvaluationWorkStatus.stale ||
      to == ScheduledEvaluationWorkStatus.failedPermanent) {
    return true;
  }
  if ((from == ScheduledEvaluationWorkStatus.pending ||
          from == ScheduledEvaluationWorkStatus.retryWait) &&
      to == ScheduledEvaluationWorkStatus.cancelled) {
    return true;
  }
  return switch ((from, to)) {
    (
      ScheduledEvaluationWorkStatus.pending,
      ScheduledEvaluationWorkStatus.leased,
    ) =>
      true,
    (
      ScheduledEvaluationWorkStatus.retryWait,
      ScheduledEvaluationWorkStatus.leased,
    ) =>
      true,
    (
      ScheduledEvaluationWorkStatus.leased,
      ScheduledEvaluationWorkStatus.evaluating,
    ) =>
      true,
    (
      ScheduledEvaluationWorkStatus.evaluating,
      ScheduledEvaluationWorkStatus.evaluated,
    ) =>
      true,
    (
      ScheduledEvaluationWorkStatus.evaluated,
      ScheduledEvaluationWorkStatus.haltApplying,
    ) =>
      true,
    (
      ScheduledEvaluationWorkStatus.evaluated,
      ScheduledEvaluationWorkStatus.completed,
    ) =>
      true,
    (
      ScheduledEvaluationWorkStatus.haltApplying,
      ScheduledEvaluationWorkStatus.completed,
    ) =>
      true,
    (
      ScheduledEvaluationWorkStatus.failedPermanent,
      ScheduledEvaluationWorkStatus.retryWait,
    ) =>
      true,
    (_, ScheduledEvaluationWorkStatus.retryWait) => true,
    _ => false,
  };
}

void validateScheduledEvaluationTransition(
  ScheduledEvaluationWorkStatus from,
  ScheduledEvaluationWorkStatus to,
) {
  if (!isValidScheduledEvaluationTransition(from, to)) {
    throw const FormatException(
      'Invalid scheduled-evaluation state transition',
    );
  }
}

final class EvaluationSchedule {
  EvaluationSchedule({
    required String scheduleId,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String rolloutId,
    required String currentScheduleRevision,
    required DateTime createdAt,
    required String createdBy,
  }) : scheduleId = _id(scheduleId, 'schedule ID'),
       organizationId = _id(organizationId, 'organization ID'),
       applicationId = _id(applicationId, 'application ID'),
       environmentId = _id(environmentId, 'environment ID'),
       rolloutId = _id(rolloutId, 'rollout ID'),
       currentScheduleRevision = _id(
         currentScheduleRevision,
         'current schedule revision ID',
       ),
       createdBy = _string(createdBy, 'schedule actor', maxLength: 128),
       createdAt = _utc(createdAt, 'schedule creation timestamp');

  final String scheduleId;
  final String organizationId;
  final String applicationId;
  final String environmentId;
  final String rolloutId;
  final String currentScheduleRevision;
  final DateTime createdAt;
  final String createdBy;

  EvaluationSchedule withCurrentRevision(String revisionId) =>
      EvaluationSchedule(
        scheduleId: scheduleId,
        organizationId: organizationId,
        applicationId: applicationId,
        environmentId: environmentId,
        rolloutId: rolloutId,
        currentScheduleRevision: revisionId,
        createdAt: createdAt,
        createdBy: createdBy,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': p3e5ScheduleSchemaVersion,
    'scheduleId': scheduleId,
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'rolloutId': rolloutId,
    'currentScheduleRevision': currentScheduleRevision,
    'createdAt': createdAt.toIso8601String(),
    'createdBy': createdBy,
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static EvaluationSchedule fromJson(Object? value) {
    final map = _object(value, 'evaluation schedule');
    _exact(map, const {
      'entityVersion',
      'scheduleId',
      'organizationId',
      'applicationId',
      'environmentId',
      'rolloutId',
      'currentScheduleRevision',
      'createdAt',
      'createdBy',
    }, 'evaluation schedule');
    _version(map['entityVersion'], 'evaluation schedule');
    return EvaluationSchedule(
      scheduleId: _string(map['scheduleId'], 'schedule ID'),
      organizationId: _string(map['organizationId'], 'organization ID'),
      applicationId: _string(map['applicationId'], 'application ID'),
      environmentId: _string(map['environmentId'], 'environment ID'),
      rolloutId: _string(map['rolloutId'], 'rollout ID'),
      currentScheduleRevision: _string(
        map['currentScheduleRevision'],
        'current schedule revision ID',
      ),
      createdAt: _timestamp(map['createdAt'], 'schedule creation timestamp'),
      createdBy: _string(map['createdBy'], 'schedule actor'),
    );
  }
}

final class EvaluationScheduleRevision {
  EvaluationScheduleRevision({
    required String scheduleRevisionId,
    required String scheduleId,
    required this.scheduleGeneration,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String rolloutId,
    this.logicalKeyVersion = 1,
    this.scheduledEvaluationEnabled = false,
    this.automaticHaltEnabled = false,
    required this.readinessPhase,
    String? automaticHaltPolicyId,
    this.automaticHaltPolicyVersion,
    String? automaticHaltPolicyDigest,
    this.automaticHaltEligibleSource,
    this.automaticHaltEligibleReadiness,
    this.automaticHaltEligibleReasonClass,
    required this.triggerPolicyVersion,
    required this.schedulePolicyVersion,
    required this.evaluationPolicyVersion,
    required String evaluationPolicyDigest,
    required this.thresholdSetVersion,
    required String thresholdSetDigest,
    required this.aggregationVersion,
    required this.windowPolicyVersion,
    required this.privacyPolicyVersion,
    required String retryPolicyReference,
    required String resourcePolicyReference,
    required String? supersedesScheduleRevisionId,
    required DateTime createdAt,
    required String createdBy,
    required String reason,
    P3e5ScheduleLimits limits = const P3e5ScheduleLimits(),
  }) : scheduleRevisionId = _id(scheduleRevisionId, 'schedule revision ID'),
       scheduleId = _id(scheduleId, 'schedule ID'),
       organizationId = _id(organizationId, 'organization ID'),
       applicationId = _id(applicationId, 'application ID'),
       environmentId = _id(environmentId, 'environment ID'),
       rolloutId = _id(rolloutId, 'rollout ID'),
       automaticHaltPolicyId = automaticHaltPolicyId == null
           ? null
           : _id(automaticHaltPolicyId, 'automatic-halt policy ID'),
       automaticHaltPolicyDigest = automaticHaltPolicyDigest == null
           ? null
           : requireSha256Digest(automaticHaltPolicyDigest),
       evaluationPolicyDigest = requireSha256Digest(evaluationPolicyDigest),
       thresholdSetDigest = requireSha256Digest(thresholdSetDigest),
       retryPolicyReference = _string(
         retryPolicyReference,
         'retry policy reference',
       ),
       resourcePolicyReference = _string(
         resourcePolicyReference,
         'resource policy reference',
       ),
       supersedesScheduleRevisionId = supersedesScheduleRevisionId == null
           ? null
           : _id(
               supersedesScheduleRevisionId,
               'superseded schedule revision ID',
             ),
       createdAt = _utc(createdAt, 'schedule revision timestamp'),
       createdBy = _string(
         createdBy,
         'schedule revision actor',
         maxLength: 128,
       ),
       reason = _string(
         reason,
         'schedule revision reason',
         maxLength: limits.maximumReasonLength,
       ) {
    limits.validate();
    if (logicalKeyVersion != 1 &&
        logicalKeyVersion != supportedP3e5LogicalKeyVersion) {
      throw const FormatException('Unsupported schedule work-meaning version');
    }
    final automaticFields = <Object?>[
      this.automaticHaltPolicyId,
      automaticHaltPolicyVersion,
      this.automaticHaltPolicyDigest,
      automaticHaltEligibleSource,
      automaticHaltEligibleReadiness,
      automaticHaltEligibleReasonClass,
    ];
    if (logicalKeyVersion == 1) {
      if (automaticFields.any((value) => value != null)) {
        throw const FormatException(
          'Historical schedule revision cannot contain v2 semantics',
        );
      }
    } else if (automaticFields.any((value) => value == null) ||
        automaticHaltPolicyVersion != supportedAutomaticHaltPolicyVersion ||
        readinessPhase != EvaluationReadinessPhase.sealed ||
        automaticHaltEligibleSource !=
            AutomaticHaltEligibleSource.scheduledOnly ||
        automaticHaltEligibleReadiness !=
            AutomaticHaltEligibleReadiness.sealedOnly ||
        automaticHaltEligibleReasonClass !=
            AutomaticHaltEligibleReasonClass.patchSafetyOnly) {
      throw const FormatException(
        'Schedule revision v2 automatic-halt semantics are invalid',
      );
    }
    if (scheduleGeneration <= 0 ||
        (scheduleGeneration == 1 &&
            this.supersedesScheduleRevisionId != null) ||
        (scheduleGeneration > 1 && this.supersedesScheduleRevisionId == null)) {
      throw const FormatException('Invalid schedule revision generation');
    }
    _supportedVersion(
      triggerPolicyVersion,
      supportedP3e5TriggerPolicyVersion,
      'trigger policy',
    );
    _supportedVersion(
      schedulePolicyVersion,
      supportedP3e5SchedulePolicyVersion,
      'schedule policy',
    );
    _supportedVersion(
      evaluationPolicyVersion,
      supportedP3e5EvaluationPolicyVersion,
      'evaluation policy',
    );
    _supportedVersion(
      thresholdSetVersion,
      supportedP3e5ThresholdSetVersion,
      'threshold set',
    );
    _supportedVersion(
      aggregationVersion,
      supportedP3e5AggregationVersion,
      'aggregation',
    );
    _supportedVersion(
      windowPolicyVersion,
      supportedP3e5WindowPolicyVersion,
      'window policy',
    );
    _supportedVersion(
      privacyPolicyVersion,
      supportedP3e5PrivacyPolicyVersion,
      'privacy policy',
    );
  }

  final String scheduleRevisionId;
  final String scheduleId;
  final int scheduleGeneration;
  final String organizationId;
  final String applicationId;
  final String environmentId;
  final String rolloutId;
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
  final String? supersedesScheduleRevisionId;
  final DateTime createdAt;
  final String createdBy;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': p3e5ScheduleSchemaVersion,
    'scheduleRevisionId': scheduleRevisionId,
    'scheduleId': scheduleId,
    'scheduleGeneration': scheduleGeneration,
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'rolloutId': rolloutId,
    if (logicalKeyVersion == 2) ...<String, Object?>{
      'logicalKeyVersion': logicalKeyVersion,
      'automaticHaltPolicyId': automaticHaltPolicyId,
      'automaticHaltPolicyVersion': automaticHaltPolicyVersion,
      'automaticHaltPolicyDigest': automaticHaltPolicyDigest,
      'automaticHaltEligibleSource': 'SCHEDULED_ONLY',
      'automaticHaltEligibleReadiness': 'SEALED_ONLY',
      'automaticHaltEligibleReasonClass': 'PATCH_SAFETY_ONLY',
    },
    'scheduledEvaluationEnabled': scheduledEvaluationEnabled,
    'automaticHaltEnabled': automaticHaltEnabled,
    'readinessPhase': readinessPhase.wireName,
    'triggerPolicyVersion': triggerPolicyVersion,
    'schedulePolicyVersion': schedulePolicyVersion,
    'evaluationPolicyVersion': evaluationPolicyVersion,
    'evaluationPolicyDigest': evaluationPolicyDigest,
    'thresholdSetVersion': thresholdSetVersion,
    'thresholdSetDigest': thresholdSetDigest,
    'aggregationVersion': aggregationVersion,
    'windowPolicyVersion': windowPolicyVersion,
    'privacyPolicyVersion': privacyPolicyVersion,
    'retryPolicyReference': retryPolicyReference,
    'resourcePolicyReference': resourcePolicyReference,
    'supersedesScheduleRevisionId': supersedesScheduleRevisionId,
    'createdAt': createdAt.toIso8601String(),
    'createdBy': createdBy,
    'reason': reason,
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static EvaluationScheduleRevision fromJson(Object? value) {
    final map = _object(value, 'evaluation schedule revision');
    final logicalKeyVersion = map.containsKey('logicalKeyVersion')
        ? _int(map['logicalKeyVersion'], 'logical key version')
        : 1;
    final fields = <String>{
      'entityVersion',
      'scheduleRevisionId',
      'scheduleId',
      'scheduleGeneration',
      'organizationId',
      'applicationId',
      'environmentId',
      'rolloutId',
      'scheduledEvaluationEnabled',
      'automaticHaltEnabled',
      'readinessPhase',
      'triggerPolicyVersion',
      'schedulePolicyVersion',
      'evaluationPolicyVersion',
      'evaluationPolicyDigest',
      'thresholdSetVersion',
      'thresholdSetDigest',
      'aggregationVersion',
      'windowPolicyVersion',
      'privacyPolicyVersion',
      'retryPolicyReference',
      'resourcePolicyReference',
      'supersedesScheduleRevisionId',
      'createdAt',
      'createdBy',
      'reason',
      if (logicalKeyVersion == 2) ...<String>{
        'logicalKeyVersion',
        'automaticHaltPolicyId',
        'automaticHaltPolicyVersion',
        'automaticHaltPolicyDigest',
        'automaticHaltEligibleSource',
        'automaticHaltEligibleReadiness',
        'automaticHaltEligibleReasonClass',
      },
    };
    _exact(map, fields, 'evaluation schedule revision');
    _version(map['entityVersion'], 'evaluation schedule revision');
    if (logicalKeyVersion == 2 &&
        (map['automaticHaltEligibleSource'] != 'SCHEDULED_ONLY' ||
            map['automaticHaltEligibleReadiness'] != 'SEALED_ONLY' ||
            map['automaticHaltEligibleReasonClass'] != 'PATCH_SAFETY_ONLY')) {
      throw const FormatException(
        'Unsupported schedule automatic-halt semantics',
      );
    }
    return EvaluationScheduleRevision(
      scheduleRevisionId: _string(
        map['scheduleRevisionId'],
        'schedule revision ID',
      ),
      scheduleId: _string(map['scheduleId'], 'schedule ID'),
      scheduleGeneration: _int(
        map['scheduleGeneration'],
        'schedule generation',
      ),
      organizationId: _string(map['organizationId'], 'organization ID'),
      applicationId: _string(map['applicationId'], 'application ID'),
      environmentId: _string(map['environmentId'], 'environment ID'),
      rolloutId: _string(map['rolloutId'], 'rollout ID'),
      logicalKeyVersion: logicalKeyVersion,
      scheduledEvaluationEnabled: _bool(
        map['scheduledEvaluationEnabled'],
        'scheduled evaluation enabled',
      ),
      automaticHaltEnabled: _bool(
        map['automaticHaltEnabled'],
        'automatic halt enabled',
      ),
      readinessPhase: parseEvaluationReadinessPhase(map['readinessPhase']),
      automaticHaltPolicyId: logicalKeyVersion == 2
          ? _string(map['automaticHaltPolicyId'], 'automatic-halt policy ID')
          : null,
      automaticHaltPolicyVersion: logicalKeyVersion == 2
          ? _int(
              map['automaticHaltPolicyVersion'],
              'automatic-halt policy version',
            )
          : null,
      automaticHaltPolicyDigest: logicalKeyVersion == 2
          ? _string(
              map['automaticHaltPolicyDigest'],
              'automatic-halt policy digest',
            )
          : null,
      automaticHaltEligibleSource: logicalKeyVersion == 2
          ? AutomaticHaltEligibleSource.scheduledOnly
          : null,
      automaticHaltEligibleReadiness: logicalKeyVersion == 2
          ? AutomaticHaltEligibleReadiness.sealedOnly
          : null,
      automaticHaltEligibleReasonClass: logicalKeyVersion == 2
          ? AutomaticHaltEligibleReasonClass.patchSafetyOnly
          : null,
      triggerPolicyVersion: _int(
        map['triggerPolicyVersion'],
        'trigger policy version',
      ),
      schedulePolicyVersion: _int(
        map['schedulePolicyVersion'],
        'schedule policy version',
      ),
      evaluationPolicyVersion: _int(
        map['evaluationPolicyVersion'],
        'evaluation policy version',
      ),
      evaluationPolicyDigest: _string(
        map['evaluationPolicyDigest'],
        'evaluation policy digest',
      ),
      thresholdSetVersion: _int(
        map['thresholdSetVersion'],
        'threshold set version',
      ),
      thresholdSetDigest: _string(
        map['thresholdSetDigest'],
        'threshold set digest',
      ),
      aggregationVersion: _int(
        map['aggregationVersion'],
        'aggregation version',
      ),
      windowPolicyVersion: _int(
        map['windowPolicyVersion'],
        'window policy version',
      ),
      privacyPolicyVersion: _int(
        map['privacyPolicyVersion'],
        'privacy policy version',
      ),
      retryPolicyReference: _string(
        map['retryPolicyReference'],
        'retry policy reference',
      ),
      resourcePolicyReference: _string(
        map['resourcePolicyReference'],
        'resource policy reference',
      ),
      supersedesScheduleRevisionId: _optionalString(
        map['supersedesScheduleRevisionId'],
        'superseded schedule revision ID',
      ),
      createdAt: _timestamp(map['createdAt'], 'schedule revision timestamp'),
      createdBy: _string(map['createdBy'], 'schedule revision actor'),
      reason: _string(map['reason'], 'schedule revision reason'),
    );
  }
}

final class LogicalEvaluationKey {
  LogicalEvaluationKey({
    this.logicalKeyVersion = 1,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String platformId,
    required String rolloutId,
    required this.rolloutRevision,
    required String releaseId,
    required String patchId,
    required this.sequence,
    required String targetBindingDigest,
    required String windowId,
    required this.readinessPhase,
    required this.observationSchemaVersion,
    required this.aggregationVersion,
    required String aggregatePolicyDigest,
    required this.evaluationPolicyVersion,
    required String evaluationPolicyDigest,
    required this.thresholdSetVersion,
    required String thresholdSetDigest,
    required this.windowPolicyVersion,
    required this.privacyPolicyVersion,
    required String scheduleId,
    required String scheduleRevisionId,
    required this.scheduleGeneration,
    String? automaticHaltPolicyId,
    this.automaticHaltPolicyVersion,
    String? automaticHaltPolicyDigest,
    this.automaticHaltEnabled,
    this.automaticHaltEligibleSource,
    this.automaticHaltEligibleReadiness,
    this.automaticHaltEligibleReasonClass,
    P3e5ScheduleLimits limits = const P3e5ScheduleLimits(),
  }) : organizationId = _id(organizationId, 'organization ID'),
       applicationId = _id(applicationId, 'application ID'),
       environmentId = _id(environmentId, 'environment ID'),
       platformId = _id(platformId, 'platform ID'),
       rolloutId = _id(rolloutId, 'rollout ID'),
       releaseId = _id(releaseId, 'release ID'),
       patchId = _id(patchId, 'patch ID'),
       targetBindingDigest = requireSha256Digest(targetBindingDigest),
       windowId = _id(windowId, 'window ID'),
       aggregatePolicyDigest = requireSha256Digest(aggregatePolicyDigest),
       evaluationPolicyDigest = requireSha256Digest(evaluationPolicyDigest),
       thresholdSetDigest = requireSha256Digest(thresholdSetDigest),
       scheduleId = _id(scheduleId, 'schedule ID'),
       scheduleRevisionId = _id(scheduleRevisionId, 'schedule revision ID'),
       automaticHaltPolicyId = automaticHaltPolicyId == null
           ? null
           : _id(automaticHaltPolicyId, 'automatic-halt policy ID'),
       automaticHaltPolicyDigest = automaticHaltPolicyDigest == null
           ? null
           : requireSha256Digest(automaticHaltPolicyDigest) {
    limits.validate();
    if (logicalKeyVersion != 1 &&
        logicalKeyVersion != supportedP3e5LogicalKeyVersion) {
      throw const FormatException('Unsupported logical key version');
    }
    final automaticFields = <Object?>[
      this.automaticHaltPolicyId,
      automaticHaltPolicyVersion,
      this.automaticHaltPolicyDigest,
      automaticHaltEnabled,
      automaticHaltEligibleSource,
      automaticHaltEligibleReadiness,
      automaticHaltEligibleReasonClass,
    ];
    if (logicalKeyVersion == 1) {
      if (automaticFields.any((value) => value != null)) {
        throw const FormatException(
          'Historical logical key cannot contain automatic-halt semantics',
        );
      }
    } else {
      if (automaticFields.any((value) => value == null) ||
          automaticHaltPolicyVersion != supportedAutomaticHaltPolicyVersion ||
          readinessPhase != EvaluationReadinessPhase.sealed ||
          automaticHaltEligibleSource !=
              AutomaticHaltEligibleSource.scheduledOnly ||
          automaticHaltEligibleReadiness !=
              AutomaticHaltEligibleReadiness.sealedOnly ||
          automaticHaltEligibleReasonClass !=
              AutomaticHaltEligibleReasonClass.patchSafetyOnly) {
        throw const FormatException(
          'Logical key v2 automatic-halt semantics are invalid',
        );
      }
    }
    if (rolloutRevision <= 0 ||
        sequence <= 0 ||
        observationSchemaVersion <= 0 ||
        scheduleGeneration <= 0) {
      throw const FormatException('Invalid logical evaluation key sequence');
    }
    _supportedVersion(
      aggregationVersion,
      supportedP3e5AggregationVersion,
      'aggregation',
    );
    _supportedVersion(
      evaluationPolicyVersion,
      supportedP3e5EvaluationPolicyVersion,
      'evaluation policy',
    );
    _supportedVersion(
      thresholdSetVersion,
      supportedP3e5ThresholdSetVersion,
      'threshold set',
    );
    _supportedVersion(
      windowPolicyVersion,
      supportedP3e5WindowPolicyVersion,
      'window policy',
    );
    _supportedVersion(
      privacyPolicyVersion,
      supportedP3e5PrivacyPolicyVersion,
      'privacy policy',
    );
    _checkBytes(toJson(), limits.maximumLogicalKeyBytes, 'Logical key');
  }

  final int logicalKeyVersion;
  final String organizationId;
  final String applicationId;
  final String environmentId;
  final String platformId;
  final String rolloutId;
  final int rolloutRevision;
  final String releaseId;
  final String patchId;
  final int sequence;
  final String targetBindingDigest;
  final String windowId;
  final EvaluationReadinessPhase readinessPhase;
  final int observationSchemaVersion;
  final int aggregationVersion;
  final String aggregatePolicyDigest;
  final int evaluationPolicyVersion;
  final String evaluationPolicyDigest;
  final int thresholdSetVersion;
  final String thresholdSetDigest;
  final int windowPolicyVersion;
  final int privacyPolicyVersion;
  final String scheduleId;
  final String scheduleRevisionId;
  final int scheduleGeneration;
  final String? automaticHaltPolicyId;
  final int? automaticHaltPolicyVersion;
  final String? automaticHaltPolicyDigest;
  final bool? automaticHaltEnabled;
  final AutomaticHaltEligibleSource? automaticHaltEligibleSource;
  final AutomaticHaltEligibleReadiness? automaticHaltEligibleReadiness;
  final AutomaticHaltEligibleReasonClass? automaticHaltEligibleReasonClass;

  Map<String, Object?> toJson() => <String, Object?>{
    'logicalKeyVersion': logicalKeyVersion,
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'platformId': platformId,
    'rolloutId': rolloutId,
    'rolloutRevision': rolloutRevision,
    'releaseId': releaseId,
    'patchId': patchId,
    'sequence': sequence,
    'targetBindingDigest': targetBindingDigest,
    'windowId': windowId,
    'readinessPhase': readinessPhase.wireName,
    'observationSchemaVersion': observationSchemaVersion,
    'aggregationVersion': aggregationVersion,
    'aggregatePolicyDigest': aggregatePolicyDigest,
    'evaluationPolicyVersion': evaluationPolicyVersion,
    'evaluationPolicyDigest': evaluationPolicyDigest,
    'thresholdSetVersion': thresholdSetVersion,
    'thresholdSetDigest': thresholdSetDigest,
    'windowPolicyVersion': windowPolicyVersion,
    'privacyPolicyVersion': privacyPolicyVersion,
    'scheduleId': scheduleId,
    'scheduleRevisionId': scheduleRevisionId,
    'scheduleGeneration': scheduleGeneration,
    if (logicalKeyVersion == 2) ...<String, Object?>{
      'automaticHaltPolicyId': automaticHaltPolicyId,
      'automaticHaltPolicyVersion': automaticHaltPolicyVersion,
      'automaticHaltPolicyDigest': automaticHaltPolicyDigest,
      'automaticHaltEnabled': automaticHaltEnabled,
      'automaticHaltEligibleSource': 'SCHEDULED_ONLY',
      'automaticHaltEligibleReadiness': 'SEALED_ONLY',
      'automaticHaltEligibleReasonClass': 'PATCH_SAFETY_ONLY',
    },
  };

  String get canonicalSerialization => canonicalJson(toJson());
  String get digest => sha256Digest(utf8.encode(canonicalSerialization));
  String get workId =>
      'work_${sha256Hex(utf8.encode('hyfens.p3e5.work.v$logicalKeyVersion$canonicalSerialization'))}';
  String get evaluationIdempotencyKey => 'scheduled-evaluation:$workId';
  String get haltIdempotencyKey => 'scheduled-halt:$workId';

  bool get isAutomaticHaltFoundationCandidate =>
      logicalKeyVersion == 2 &&
      automaticHaltEnabled == true &&
      readinessPhase == EvaluationReadinessPhase.sealed &&
      automaticHaltEligibleSource ==
          AutomaticHaltEligibleSource.scheduledOnly &&
      automaticHaltEligibleReadiness ==
          AutomaticHaltEligibleReadiness.sealedOnly &&
      automaticHaltEligibleReasonClass ==
          AutomaticHaltEligibleReasonClass.patchSafetyOnly;

  static LogicalEvaluationKey fromJson(Object? value) {
    final map = _object(value, 'logical evaluation key');
    final logicalKeyVersion = _int(
      map['logicalKeyVersion'],
      'logical key version',
    );
    final fields = <String>{
      'logicalKeyVersion',
      'organizationId',
      'applicationId',
      'environmentId',
      'platformId',
      'rolloutId',
      'rolloutRevision',
      'releaseId',
      'patchId',
      'sequence',
      'targetBindingDigest',
      'windowId',
      'readinessPhase',
      'observationSchemaVersion',
      'aggregationVersion',
      'aggregatePolicyDigest',
      'evaluationPolicyVersion',
      'evaluationPolicyDigest',
      'thresholdSetVersion',
      'thresholdSetDigest',
      'windowPolicyVersion',
      'privacyPolicyVersion',
      'scheduleId',
      'scheduleRevisionId',
      'scheduleGeneration',
      if (logicalKeyVersion == 2) ...<String>{
        'automaticHaltPolicyVersion',
        'automaticHaltPolicyId',
        'automaticHaltPolicyDigest',
        'automaticHaltEnabled',
        'automaticHaltEligibleSource',
        'automaticHaltEligibleReadiness',
        'automaticHaltEligibleReasonClass',
      },
    };
    _exact(map, fields, 'logical evaluation key');
    if (logicalKeyVersion == 2 &&
        (map['automaticHaltEligibleSource'] != 'SCHEDULED_ONLY' ||
            map['automaticHaltEligibleReadiness'] != 'SEALED_ONLY' ||
            map['automaticHaltEligibleReasonClass'] != 'PATCH_SAFETY_ONLY')) {
      throw const FormatException(
        'Unsupported logical key automatic-halt semantics',
      );
    }
    return LogicalEvaluationKey(
      logicalKeyVersion: logicalKeyVersion,
      organizationId: _string(map['organizationId'], 'organization ID'),
      applicationId: _string(map['applicationId'], 'application ID'),
      environmentId: _string(map['environmentId'], 'environment ID'),
      platformId: _string(map['platformId'], 'platform ID'),
      rolloutId: _string(map['rolloutId'], 'rollout ID'),
      rolloutRevision: _int(map['rolloutRevision'], 'rollout revision'),
      releaseId: _string(map['releaseId'], 'release ID'),
      patchId: _string(map['patchId'], 'patch ID'),
      sequence: _int(map['sequence'], 'patch sequence'),
      targetBindingDigest: _string(
        map['targetBindingDigest'],
        'target binding digest',
      ),
      windowId: _string(map['windowId'], 'window ID'),
      readinessPhase: parseEvaluationReadinessPhase(map['readinessPhase']),
      observationSchemaVersion: _int(
        map['observationSchemaVersion'],
        'observation schema version',
      ),
      aggregationVersion: _int(
        map['aggregationVersion'],
        'aggregation version',
      ),
      aggregatePolicyDigest: _string(
        map['aggregatePolicyDigest'],
        'aggregate policy digest',
      ),
      evaluationPolicyVersion: _int(
        map['evaluationPolicyVersion'],
        'evaluation policy version',
      ),
      evaluationPolicyDigest: _string(
        map['evaluationPolicyDigest'],
        'evaluation policy digest',
      ),
      thresholdSetVersion: _int(
        map['thresholdSetVersion'],
        'threshold set version',
      ),
      thresholdSetDigest: _string(
        map['thresholdSetDigest'],
        'threshold set digest',
      ),
      windowPolicyVersion: _int(
        map['windowPolicyVersion'],
        'window policy version',
      ),
      privacyPolicyVersion: _int(
        map['privacyPolicyVersion'],
        'privacy policy version',
      ),
      scheduleId: _string(map['scheduleId'], 'schedule ID'),
      scheduleRevisionId: _string(
        map['scheduleRevisionId'],
        'schedule revision ID',
      ),
      scheduleGeneration: _int(
        map['scheduleGeneration'],
        'schedule generation',
      ),
      automaticHaltPolicyVersion: logicalKeyVersion == 2
          ? _int(
              map['automaticHaltPolicyVersion'],
              'automatic-halt policy version',
            )
          : null,
      automaticHaltPolicyId: logicalKeyVersion == 2
          ? _string(map['automaticHaltPolicyId'], 'automatic-halt policy ID')
          : null,
      automaticHaltPolicyDigest: logicalKeyVersion == 2
          ? _string(
              map['automaticHaltPolicyDigest'],
              'automatic-halt policy digest',
            )
          : null,
      automaticHaltEnabled: logicalKeyVersion == 2
          ? _bool(map['automaticHaltEnabled'], 'automatic halt enabled')
          : null,
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
  }
}

final class ScheduledEvaluationWork {
  ScheduledEvaluationWork({
    required String workId,
    required this.logicalKey,
    required this.status,
    required this.workVersion,
    required this.attemptCount,
    required this.notBefore,
    required String? leaseOwner,
    required String? leaseTokenDigest,
    required this.leaseAcquiredAt,
    required this.leaseExpiresAt,
    required this.createdAt,
    required this.updatedAt,
    required this.lastAttemptAt,
    required String? lastErrorClass,
    required String? lastErrorCode,
    String? aggregateId,
    String? aggregateRevisionId,
    required String? evaluationId,
    required String? decisionId,
    required String? haltApplicationId,
    AutomaticHaltIntent? automaticHaltIntent,
    P3e5ScheduleLimits limits = const P3e5ScheduleLimits(),
  }) : workId = _id(workId, 'work ID'),
       leaseOwner = _optionalBounded(leaseOwner, 'lease owner', 128),
       leaseTokenDigest = leaseTokenDigest == null
           ? null
           : requireSha256Digest(leaseTokenDigest),
       lastErrorClass = _optionalBounded(lastErrorClass, 'error class', 64),
       lastErrorCode = _optionalBounded(
         lastErrorCode,
         'safe error code',
         limits.maximumSafeErrorCodeLength,
       ),
       aggregateId = _optionalId(aggregateId, 'aggregate ID'),
       aggregateRevisionId = _optionalId(
         aggregateRevisionId,
         'aggregate revision ID',
       ),
       evaluationId = _optionalId(evaluationId, 'evaluation ID'),
       decisionId = _optionalId(decisionId, 'decision ID'),
       haltApplicationId = _optionalId(
         haltApplicationId,
         'halt application ID',
       ),
       automaticHaltIntent = automaticHaltIntent {
    limits.validate();
    if (this.workId != logicalKey.workId ||
        workVersion < 0 ||
        attemptCount < 0) {
      throw const FormatException('Invalid scheduled-evaluation work identity');
    }
    final leaseValues = <Object?>[
      this.leaseOwner,
      this.leaseTokenDigest,
      leaseAcquiredAt,
      leaseExpiresAt,
    ];
    final hasLease = leaseValues.every((value) => value != null);
    if (!(hasLease || leaseValues.every((value) => value == null))) {
      throw const FormatException('Lease fields are inconsistent');
    }
    if (hasLease &&
        !leaseExpiresAt!.toUtc().isAfter(leaseAcquiredAt!.toUtc())) {
      throw const FormatException('Lease expiry is invalid');
    }
    final leaseBearing =
        status == ScheduledEvaluationWorkStatus.leased ||
        status == ScheduledEvaluationWorkStatus.evaluating ||
        status == ScheduledEvaluationWorkStatus.evaluated ||
        status == ScheduledEvaluationWorkStatus.haltApplying;
    if (leaseBearing != hasLease || (hasLease && attemptCount <= 0)) {
      throw const FormatException('Lease state is inconsistent');
    }
    if (this.lastErrorClass != null &&
        !const <String>{
          'TRANSIENT',
          'STALE',
          'PERMANENT',
          'SECURITY',
        }.contains(this.lastErrorClass)) {
      throw const FormatException('Unsupported retry error class');
    }
    if (updatedAt.toUtc().isBefore(createdAt.toUtc()) ||
        (lastAttemptAt != null &&
            lastAttemptAt!.toUtc().isBefore(createdAt.toUtc()))) {
      throw const FormatException('Work timestamps are invalid');
    }
    if (attemptCount == 0 && lastAttemptAt != null) {
      throw const FormatException('Work attempt projection is invalid');
    }
    if ((this.aggregateId == null) != (this.aggregateRevisionId == null)) {
      throw const FormatException('Work aggregate link is inconsistent');
    }
    if ((this.evaluationId == null) != (this.decisionId == null)) {
      throw const FormatException('Work evaluation link is inconsistent');
    }
    final requiresAggregate =
        status == ScheduledEvaluationWorkStatus.evaluating ||
        status == ScheduledEvaluationWorkStatus.evaluated ||
        status == ScheduledEvaluationWorkStatus.haltApplying ||
        status == ScheduledEvaluationWorkStatus.completed;
    final requiresEvaluation =
        status == ScheduledEvaluationWorkStatus.evaluated ||
        status == ScheduledEvaluationWorkStatus.haltApplying ||
        status == ScheduledEvaluationWorkStatus.completed;
    if ((requiresAggregate && this.aggregateId == null) ||
        (requiresEvaluation && this.evaluationId == null)) {
      throw const FormatException('Work execution evidence is incomplete');
    }
    if ((status == ScheduledEvaluationWorkStatus.haltApplying &&
            this.automaticHaltIntent == null) ||
        (this.automaticHaltIntent != null &&
            status != ScheduledEvaluationWorkStatus.haltApplying &&
            status != ScheduledEvaluationWorkStatus.completed) ||
        (this.automaticHaltIntent != null &&
            (this.automaticHaltIntent!.workId != this.workId ||
                this.automaticHaltIntent!.attemptId !=
                    deriveAttemptId(this.workId, attemptCount) ||
                this.automaticHaltIntent!.evaluationId != this.evaluationId ||
                this.automaticHaltIntent!.decisionId != this.decisionId ||
                this.automaticHaltIntent!.scheduleRevisionId !=
                    logicalKey.scheduleRevisionId ||
                this.automaticHaltIntent!.automaticHaltPolicyVersion !=
                    logicalKey.automaticHaltPolicyVersion ||
                this.automaticHaltIntent!.automaticHaltPolicyDigest !=
                    logicalKey.automaticHaltPolicyDigest ||
                this.automaticHaltIntent!.expectedRolloutRevision !=
                    logicalKey.rolloutRevision ||
                this.automaticHaltIntent!.targetBindingDigest !=
                    logicalKey.targetBindingDigest))) {
      throw const FormatException('Automatic-halt intent binding is invalid');
    }
    _checkBytes(toJson(), limits.maximumWorkBytes, 'Work record');
  }

  factory ScheduledEvaluationWork.pending({
    required LogicalEvaluationKey logicalKey,
    required DateTime serverNow,
  }) => ScheduledEvaluationWork(
    workId: logicalKey.workId,
    logicalKey: logicalKey,
    status: ScheduledEvaluationWorkStatus.pending,
    workVersion: 0,
    attemptCount: 0,
    notBefore: serverNow.toUtc(),
    leaseOwner: null,
    leaseTokenDigest: null,
    leaseAcquiredAt: null,
    leaseExpiresAt: null,
    createdAt: serverNow.toUtc(),
    updatedAt: serverNow.toUtc(),
    lastAttemptAt: null,
    lastErrorClass: null,
    lastErrorCode: null,
    aggregateId: null,
    aggregateRevisionId: null,
    evaluationId: null,
    decisionId: null,
    haltApplicationId: null,
    automaticHaltIntent: null,
  );

  final String workId;
  final LogicalEvaluationKey logicalKey;
  final ScheduledEvaluationWorkStatus status;
  final int workVersion;
  final int attemptCount;
  final DateTime notBefore;
  final String? leaseOwner;
  final String? leaseTokenDigest;
  final DateTime? leaseAcquiredAt;
  final DateTime? leaseExpiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAttemptAt;
  final String? lastErrorClass;
  final String? lastErrorCode;
  final String? aggregateId;
  final String? aggregateRevisionId;
  final String? evaluationId;
  final String? decisionId;
  final String? haltApplicationId;
  final AutomaticHaltIntent? automaticHaltIntent;

  ScheduledEvaluationWork withOperationalState({
    required ScheduledEvaluationWorkStatus status,
    required int workVersion,
    required int attemptCount,
    required DateTime notBefore,
    required String? leaseOwner,
    required String? leaseTokenDigest,
    required DateTime? leaseAcquiredAt,
    required DateTime? leaseExpiresAt,
    required DateTime updatedAt,
    required DateTime? lastAttemptAt,
    required String? lastErrorClass,
    required String? lastErrorCode,
    String? linkedAggregateId,
    String? linkedAggregateRevisionId,
    String? linkedEvaluationId,
    String? linkedDecisionId,
    String? linkedHaltApplicationId,
    AutomaticHaltIntent? linkedAutomaticHaltIntent,
    bool clearAutomaticHaltIntent = false,
  }) => ScheduledEvaluationWork(
    workId: workId,
    logicalKey: logicalKey,
    status: status,
    workVersion: workVersion,
    attemptCount: attemptCount,
    notBefore: notBefore,
    leaseOwner: leaseOwner,
    leaseTokenDigest: leaseTokenDigest,
    leaseAcquiredAt: leaseAcquiredAt,
    leaseExpiresAt: leaseExpiresAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
    lastAttemptAt: lastAttemptAt,
    lastErrorClass: lastErrorClass,
    lastErrorCode: lastErrorCode,
    aggregateId: linkedAggregateId ?? aggregateId,
    aggregateRevisionId: linkedAggregateRevisionId ?? aggregateRevisionId,
    evaluationId: linkedEvaluationId ?? evaluationId,
    decisionId: linkedDecisionId ?? decisionId,
    haltApplicationId: linkedHaltApplicationId ?? haltApplicationId,
    automaticHaltIntent: clearAutomaticHaltIntent
        ? null
        : linkedAutomaticHaltIntent ?? automaticHaltIntent,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': p3e5ScheduleSchemaVersion,
    'workId': workId,
    'logicalKey': logicalKey.toJson(),
    'logicalKeyDigest': logicalKey.digest,
    'status': status.wireName,
    'workVersion': workVersion,
    'attemptCount': attemptCount,
    'notBefore': notBefore.toUtc().toIso8601String(),
    'leaseOwner': leaseOwner,
    'leaseTokenDigest': leaseTokenDigest,
    'leaseAcquiredAt': leaseAcquiredAt?.toUtc().toIso8601String(),
    'leaseExpiresAt': leaseExpiresAt?.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'lastAttemptAt': lastAttemptAt?.toUtc().toIso8601String(),
    'lastErrorClass': lastErrorClass,
    'lastErrorCode': lastErrorCode,
    'aggregateId': aggregateId,
    'aggregateRevisionId': aggregateRevisionId,
    'evaluationId': evaluationId,
    'decisionId': decisionId,
    'haltApplicationId': haltApplicationId,
    'automaticHaltIntent': automaticHaltIntent?.toJson(),
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static ScheduledEvaluationWork fromJson(Object? value) {
    final map = _object(value, 'scheduled evaluation work');
    final normalized = <String, Object?>{
      ...map,
      'aggregateId': map['aggregateId'],
      'aggregateRevisionId': map['aggregateRevisionId'],
      'automaticHaltIntent': map['automaticHaltIntent'],
    };
    _exact(normalized, const {
      'entityVersion',
      'workId',
      'logicalKey',
      'logicalKeyDigest',
      'status',
      'workVersion',
      'attemptCount',
      'notBefore',
      'leaseOwner',
      'leaseTokenDigest',
      'leaseAcquiredAt',
      'leaseExpiresAt',
      'createdAt',
      'updatedAt',
      'lastAttemptAt',
      'lastErrorClass',
      'lastErrorCode',
      'aggregateId',
      'aggregateRevisionId',
      'evaluationId',
      'decisionId',
      'haltApplicationId',
      'automaticHaltIntent',
    }, 'scheduled evaluation work');
    _version(normalized['entityVersion'], 'scheduled evaluation work');
    final key = LogicalEvaluationKey.fromJson(normalized['logicalKey']);
    if (normalized['logicalKeyDigest'] != key.digest) {
      throw const FormatException('Logical evaluation key digest mismatch');
    }
    return ScheduledEvaluationWork(
      workId: _string(normalized['workId'], 'work ID'),
      logicalKey: key,
      status: parseScheduledEvaluationWorkStatus(normalized['status']),
      workVersion: _int(normalized['workVersion'], 'work version'),
      attemptCount: _int(normalized['attemptCount'], 'attempt count'),
      notBefore: _timestamp(normalized['notBefore'], 'not-before timestamp'),
      leaseOwner: _optionalString(normalized['leaseOwner'], 'lease owner'),
      leaseTokenDigest: _optionalString(
        normalized['leaseTokenDigest'],
        'lease token digest',
      ),
      leaseAcquiredAt: _optionalTimestamp(
        normalized['leaseAcquiredAt'],
        'lease acquisition timestamp',
      ),
      leaseExpiresAt: _optionalTimestamp(
        normalized['leaseExpiresAt'],
        'lease expiry timestamp',
      ),
      createdAt: _timestamp(normalized['createdAt'], 'work creation timestamp'),
      updatedAt: _timestamp(normalized['updatedAt'], 'work update timestamp'),
      lastAttemptAt: _optionalTimestamp(
        normalized['lastAttemptAt'],
        'last attempt timestamp',
      ),
      lastErrorClass: _optionalString(
        normalized['lastErrorClass'],
        'error class',
      ),
      lastErrorCode: _optionalString(
        normalized['lastErrorCode'],
        'safe error code',
      ),
      aggregateId: _optionalString(normalized['aggregateId'], 'aggregate ID'),
      aggregateRevisionId: _optionalString(
        normalized['aggregateRevisionId'],
        'aggregate revision ID',
      ),
      evaluationId: _optionalString(
        normalized['evaluationId'],
        'evaluation ID',
      ),
      decisionId: _optionalString(normalized['decisionId'], 'decision ID'),
      haltApplicationId: _optionalString(
        normalized['haltApplicationId'],
        'halt application ID',
      ),
      automaticHaltIntent: normalized['automaticHaltIntent'] == null
          ? null
          : AutomaticHaltIntent.fromJson(normalized['automaticHaltIntent']),
    );
  }
}

final class ScheduledEvaluationAttempt {
  ScheduledEvaluationAttempt({
    required String attemptId,
    required String workId,
    required this.attemptNumber,
    required String? leaseOwner,
    required String? leaseTokenDigest,
    required this.startedAt,
    required this.finishedAt,
    required String outcome,
    required String? errorClass,
    required String? safeErrorCode,
    required String? evaluationId,
    required String? decisionId,
    required String? haltApplicationId,
    required String actorIdentity,
    P3e5ScheduleLimits limits = const P3e5ScheduleLimits(),
  }) : attemptId = _id(attemptId, 'attempt ID'),
       workId = _id(workId, 'work ID'),
       leaseOwner = _optionalBounded(leaseOwner, 'lease owner', 128),
       leaseTokenDigest = leaseTokenDigest == null
           ? null
           : requireSha256Digest(leaseTokenDigest),
       outcome = _string(outcome, 'attempt outcome', maxLength: 64),
       errorClass = _optionalBounded(errorClass, 'error class', 64),
       safeErrorCode = _optionalBounded(
         safeErrorCode,
         'safe error code',
         limits.maximumSafeErrorCodeLength,
       ),
       evaluationId = _optionalId(evaluationId, 'evaluation ID'),
       decisionId = _optionalId(decisionId, 'decision ID'),
       haltApplicationId = _optionalId(
         haltApplicationId,
         'halt application ID',
       ),
       actorIdentity = _string(
         actorIdentity,
         'attempt actor identity',
         maxLength: 128,
       ) {
    limits.validate();
    if (attemptNumber <= 0 ||
        attemptId != deriveAttemptId(workId, attemptNumber)) {
      throw const FormatException(
        'Invalid scheduled-evaluation attempt identity',
      );
    }
    if (finishedAt != null && finishedAt!.toUtc().isBefore(startedAt.toUtc())) {
      throw const FormatException('Attempt timestamps are invalid');
    }
    _checkBytes(toJson(), limits.maximumAttemptBytes, 'Attempt record');
  }

  final String attemptId;
  final String workId;
  final int attemptNumber;
  final String? leaseOwner;
  final String? leaseTokenDigest;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String outcome;
  final String? errorClass;
  final String? safeErrorCode;
  final String? evaluationId;
  final String? decisionId;
  final String? haltApplicationId;
  final String actorIdentity;

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': p3e5ScheduleSchemaVersion,
    'attemptId': attemptId,
    'workId': workId,
    'attemptNumber': attemptNumber,
    'leaseOwner': leaseOwner,
    'leaseTokenDigest': leaseTokenDigest,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt?.toUtc().toIso8601String(),
    'outcome': outcome,
    'errorClass': errorClass,
    'safeErrorCode': safeErrorCode,
    'evaluationId': evaluationId,
    'decisionId': decisionId,
    'haltApplicationId': haltApplicationId,
    'actorIdentity': actorIdentity,
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static ScheduledEvaluationAttempt fromJson(Object? value) {
    final map = _object(value, 'scheduled evaluation attempt');
    _exact(map, const {
      'entityVersion',
      'attemptId',
      'workId',
      'attemptNumber',
      'leaseOwner',
      'leaseTokenDigest',
      'startedAt',
      'finishedAt',
      'outcome',
      'errorClass',
      'safeErrorCode',
      'evaluationId',
      'decisionId',
      'haltApplicationId',
      'actorIdentity',
    }, 'scheduled evaluation attempt');
    _version(map['entityVersion'], 'scheduled evaluation attempt');
    return ScheduledEvaluationAttempt(
      attemptId: _string(map['attemptId'], 'attempt ID'),
      workId: _string(map['workId'], 'work ID'),
      attemptNumber: _int(map['attemptNumber'], 'attempt number'),
      leaseOwner: _optionalString(map['leaseOwner'], 'lease owner'),
      leaseTokenDigest: _optionalString(
        map['leaseTokenDigest'],
        'lease token digest',
      ),
      startedAt: _timestamp(map['startedAt'], 'attempt start timestamp'),
      finishedAt: _optionalTimestamp(
        map['finishedAt'],
        'attempt finish timestamp',
      ),
      outcome: _string(map['outcome'], 'attempt outcome'),
      errorClass: _optionalString(map['errorClass'], 'error class'),
      safeErrorCode: _optionalString(map['safeErrorCode'], 'safe error code'),
      evaluationId: _optionalString(map['evaluationId'], 'evaluation ID'),
      decisionId: _optionalString(map['decisionId'], 'decision ID'),
      haltApplicationId: _optionalString(
        map['haltApplicationId'],
        'halt application ID',
      ),
      actorIdentity: _string(map['actorIdentity'], 'attempt actor identity'),
    );
  }
}

String deriveAttemptId(String workId, int attemptNumber) {
  _id(workId, 'work ID');
  if (attemptNumber <= 0) throw const FormatException('Invalid attempt number');
  return 'attempt_${sha256Hex(utf8.encode('hyfens.p3e5.attempt.v1$workId$attemptNumber'))}';
}

void validateScheduleRevisionBinding(
  EvaluationSchedule schedule,
  EvaluationScheduleRevision revision,
) {
  if (schedule.scheduleId != revision.scheduleId ||
      schedule.organizationId != revision.organizationId ||
      schedule.applicationId != revision.applicationId ||
      schedule.environmentId != revision.environmentId ||
      schedule.rolloutId != revision.rolloutId) {
    throw const FormatException('Schedule revision scope binding is invalid');
  }
}

void validateWorkBinding(
  ScheduledEvaluationWork work,
  EvaluationSchedule schedule,
  EvaluationScheduleRevision revision,
) {
  validateScheduleRevisionBinding(schedule, revision);
  final key = work.logicalKey;
  if (key.scheduleId != schedule.scheduleId ||
      key.scheduleRevisionId != revision.scheduleRevisionId ||
      key.scheduleGeneration != revision.scheduleGeneration ||
      key.logicalKeyVersion != revision.logicalKeyVersion ||
      key.organizationId != schedule.organizationId ||
      key.applicationId != schedule.applicationId ||
      key.environmentId != schedule.environmentId ||
      key.rolloutId != schedule.rolloutId ||
      key.readinessPhase != revision.readinessPhase ||
      key.aggregationVersion != revision.aggregationVersion ||
      key.evaluationPolicyVersion != revision.evaluationPolicyVersion ||
      key.evaluationPolicyDigest != revision.evaluationPolicyDigest ||
      key.thresholdSetVersion != revision.thresholdSetVersion ||
      key.thresholdSetDigest != revision.thresholdSetDigest ||
      key.windowPolicyVersion != revision.windowPolicyVersion ||
      key.privacyPolicyVersion != revision.privacyPolicyVersion) {
    throw const FormatException('Scheduled work scope binding is invalid');
  }
  if (key.logicalKeyVersion == 2 &&
      (key.automaticHaltPolicyId != revision.automaticHaltPolicyId ||
          key.automaticHaltPolicyVersion !=
              revision.automaticHaltPolicyVersion ||
          key.automaticHaltPolicyDigest != revision.automaticHaltPolicyDigest ||
          key.automaticHaltEnabled != revision.automaticHaltEnabled ||
          key.automaticHaltEligibleSource !=
              revision.automaticHaltEligibleSource ||
          key.automaticHaltEligibleReadiness !=
              revision.automaticHaltEligibleReadiness ||
          key.automaticHaltEligibleReasonClass !=
              revision.automaticHaltEligibleReasonClass)) {
    throw const FormatException('Scheduled work policy binding is invalid');
  }
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map) throw FormatException('Invalid $label object');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('Invalid $label key');
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _exact(Map<String, Object?> value, Set<String> keys, String label) {
  if (value.length != keys.length ||
      value.keys.any((key) => !keys.contains(key))) {
    throw FormatException('Invalid $label fields');
  }
}

void _version(Object? value, String label) {
  if (value != p3e5ScheduleSchemaVersion) {
    throw FormatException('Unsupported $label entity version');
  }
}

void _supportedVersion(int value, int supported, String label) {
  if (value != supported) throw FormatException('Unsupported $label version');
}

String _string(Object? value, String label, {int maxLength = 256}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      value.contains(RegExp(r'[\u0000\r\n]'))) {
    throw FormatException('Invalid $label');
  }
  return value;
}

String? _optionalString(Object? value, String label) =>
    value == null ? null : _string(value, label);

String _id(String value, String label) {
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.:-]{0,127}$').hasMatch(value)) {
    throw FormatException('Invalid $label');
  }
  return value;
}

String? _optionalId(String? value, String label) =>
    value == null ? null : _id(value, label);

String? _optionalBounded(String? value, String label, int maxLength) =>
    value == null ? null : _string(value, label, maxLength: maxLength);

int _int(Object? value, String label) {
  if (value is! int) throw FormatException('Invalid $label');
  return value;
}

bool _bool(Object? value, String label) {
  if (value is! bool) throw FormatException('Invalid $label');
  return value;
}

DateTime _timestamp(Object? value, String label) {
  if (value is! String) throw FormatException('Invalid $label');
  try {
    final parsed = DateTime.parse(value);
    if (!value.endsWith('Z')) throw FormatException('Invalid $label');
    return parsed.toUtc();
  } on FormatException {
    throw FormatException('Invalid $label');
  }
}

DateTime? _optionalTimestamp(Object? value, String label) =>
    value == null ? null : _timestamp(value, label);

DateTime _utc(DateTime value, String label) {
  if (!value.isUtc) throw FormatException('$label must be UTC');
  return value;
}

void _checkBytes(Map<String, Object?> value, int maximum, String label) {
  if (utf8.encode(canonicalJson(value)).length > maximum) {
    throw FormatException('$label exceeds encoded byte limit');
  }
}
