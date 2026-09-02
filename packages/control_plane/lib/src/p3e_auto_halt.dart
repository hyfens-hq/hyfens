import 'dart:convert';

import 'encoding.dart';

const int automaticHaltEntityVersion = 1;
const int supportedAutomaticHaltPolicyVersion = 1;

enum AutomaticHaltEligibleSource { scheduledOnly }

enum AutomaticHaltEligibleReadiness { sealedOnly }

enum AutomaticHaltEligibleReasonClass { patchSafetyOnly }

/// Immutable, tenant-scoped policy identity for the P3E5-4A foundation.
///
/// Durations are mandatory inputs. This model deliberately supplies no
/// production freshness or resource defaults.
final class AutomaticHaltPolicy {
  AutomaticHaltPolicy({
    required String policyId,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    this.automaticHaltPolicyVersion = supportedAutomaticHaltPolicyVersion,
    this.eligibleSource = AutomaticHaltEligibleSource.scheduledOnly,
    this.eligibleReadiness = AutomaticHaltEligibleReadiness.sealedOnly,
    this.eligibleReasonClass = AutomaticHaltEligibleReasonClass.patchSafetyOnly,
    required this.maximumAggregateAgeFromLateCutoff,
    required this.maximumDecisionAgeFromEvaluation,
    required String resourcePolicyReference,
    required String approvalReference,
    required DateTime createdAt,
    required String createdBy,
  }) : policyId = _id(policyId, 'automatic-halt policy ID'),
       organizationId = _id(organizationId, 'organization ID'),
       applicationId = _id(applicationId, 'application ID'),
       environmentId = _id(environmentId, 'environment ID'),
       resourcePolicyReference = _bounded(
         resourcePolicyReference,
         'resource policy reference',
       ),
       approvalReference = _bounded(approvalReference, 'approval reference'),
       createdAt = _utc(createdAt, 'policy creation timestamp'),
       createdBy = _bounded(createdBy, 'policy actor', maximum: 128) {
    if (automaticHaltPolicyVersion != supportedAutomaticHaltPolicyVersion) {
      throw const FormatException('Unsupported automatic-halt policy version');
    }
    if (eligibleSource != AutomaticHaltEligibleSource.scheduledOnly ||
        eligibleReadiness != AutomaticHaltEligibleReadiness.sealedOnly ||
        eligibleReasonClass !=
            AutomaticHaltEligibleReasonClass.patchSafetyOnly) {
      throw const FormatException('Unsupported automatic-halt eligibility');
    }
    if (maximumAggregateAgeFromLateCutoff <= Duration.zero ||
        maximumDecisionAgeFromEvaluation <= Duration.zero) {
      throw const FormatException(
        'Automatic-halt freshness durations must be positive',
      );
    }
  }

  final String policyId;
  final String organizationId;
  final String applicationId;
  final String environmentId;
  final int automaticHaltPolicyVersion;
  final AutomaticHaltEligibleSource eligibleSource;
  final AutomaticHaltEligibleReadiness eligibleReadiness;
  final AutomaticHaltEligibleReasonClass eligibleReasonClass;
  final Duration maximumAggregateAgeFromLateCutoff;
  final Duration maximumDecisionAgeFromEvaluation;
  final String resourcePolicyReference;
  final String approvalReference;
  final DateTime createdAt;
  final String createdBy;

  Map<String, Object?> get semanticJson => <String, Object?>{
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'automaticHaltPolicyVersion': automaticHaltPolicyVersion,
    'eligibleSource': 'SCHEDULED_ONLY',
    'eligibleReadiness': 'SEALED_ONLY',
    'eligibleReasonClass': 'PATCH_SAFETY_ONLY',
    'maximumAggregateAgeFromLateCutoffMicros':
        maximumAggregateAgeFromLateCutoff.inMicroseconds,
    'maximumDecisionAgeFromEvaluationMicros':
        maximumDecisionAgeFromEvaluation.inMicroseconds,
    'resourcePolicyReference': resourcePolicyReference,
    'approvalReference': approvalReference,
  };

  String get digest => sha256Digest(utf8.encode(canonicalJson(semanticJson)));

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': automaticHaltEntityVersion,
    'policyId': policyId,
    ...semanticJson,
    'automaticHaltPolicyDigest': digest,
    'createdAt': createdAt.toIso8601String(),
    'createdBy': createdBy,
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static AutomaticHaltPolicy fromJson(Object? value) {
    final map = _object(value, 'automatic-halt policy');
    _exact(map, const <String>{
      'entityVersion',
      'policyId',
      'organizationId',
      'applicationId',
      'environmentId',
      'automaticHaltPolicyVersion',
      'eligibleSource',
      'eligibleReadiness',
      'eligibleReasonClass',
      'maximumAggregateAgeFromLateCutoffMicros',
      'maximumDecisionAgeFromEvaluationMicros',
      'resourcePolicyReference',
      'approvalReference',
      'automaticHaltPolicyDigest',
      'createdAt',
      'createdBy',
    }, 'automatic-halt policy');
    if (map['entityVersion'] != automaticHaltEntityVersion ||
        map['eligibleSource'] != 'SCHEDULED_ONLY' ||
        map['eligibleReadiness'] != 'SEALED_ONLY' ||
        map['eligibleReasonClass'] != 'PATCH_SAFETY_ONLY') {
      throw const FormatException('Unsupported automatic-halt policy');
    }
    final policy = AutomaticHaltPolicy(
      policyId: _string(map['policyId'], 'automatic-halt policy ID'),
      organizationId: _string(map['organizationId'], 'organization ID'),
      applicationId: _string(map['applicationId'], 'application ID'),
      environmentId: _string(map['environmentId'], 'environment ID'),
      automaticHaltPolicyVersion: _integer(
        map['automaticHaltPolicyVersion'],
        'automatic-halt policy version',
      ),
      maximumAggregateAgeFromLateCutoff: Duration(
        microseconds: _positiveInteger(
          map['maximumAggregateAgeFromLateCutoffMicros'],
          'maximum aggregate age',
        ),
      ),
      maximumDecisionAgeFromEvaluation: Duration(
        microseconds: _positiveInteger(
          map['maximumDecisionAgeFromEvaluationMicros'],
          'maximum decision age',
        ),
      ),
      resourcePolicyReference: _string(
        map['resourcePolicyReference'],
        'resource policy reference',
      ),
      approvalReference: _string(
        map['approvalReference'],
        'approval reference',
      ),
      createdAt: _timestamp(map['createdAt'], 'policy creation timestamp'),
      createdBy: _string(map['createdBy'], 'policy actor'),
    );
    if (map['automaticHaltPolicyDigest'] != policy.digest) {
      throw const FormatException('Automatic-halt policy digest mismatch');
    }
    return policy;
  }
}

/// Immutable environment state revision. Policy approval and production
/// enablement are deliberately independent and both default off.
final class AutomaticHaltEnvironmentState {
  AutomaticHaltEnvironmentState({
    required String stateId,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required this.generation,
    required String? supersedesStateId,
    required String policyId,
    required String automaticHaltPolicyDigest,
    required this.policyApproved,
    required this.productionEnabled,
    required String? productionEnableReference,
    required DateTime createdAt,
    required String createdBy,
  }) : stateId = _id(stateId, 'automatic-halt state ID'),
       organizationId = _id(organizationId, 'organization ID'),
       applicationId = _id(applicationId, 'application ID'),
       environmentId = _id(environmentId, 'environment ID'),
       supersedesStateId = supersedesStateId == null
           ? null
           : _id(supersedesStateId, 'superseded automatic-halt state ID'),
       policyId = _id(policyId, 'automatic-halt policy ID'),
       automaticHaltPolicyDigest = _digest(
         automaticHaltPolicyDigest,
         'automatic-halt policy digest',
       ),
       productionEnableReference = productionEnableReference == null
           ? null
           : _bounded(productionEnableReference, 'production enable reference'),
       createdAt = _utc(createdAt, 'automatic-halt state timestamp'),
       createdBy = _bounded(
         createdBy,
         'automatic-halt state actor',
         maximum: 128,
       ) {
    if (generation <= 0 ||
        (generation == 1 && this.supersedesStateId != null) ||
        (generation > 1 && this.supersedesStateId == null)) {
      throw const FormatException('Invalid automatic-halt state generation');
    }
    if (productionEnabled &&
        (!policyApproved || this.productionEnableReference == null)) {
      throw const FormatException(
        'Production automatic halt requires policy approval and enable reference',
      );
    }
    if (!productionEnabled && this.productionEnableReference != null) {
      throw const FormatException(
        'Disabled production automatic halt cannot have an enable reference',
      );
    }
  }

  factory AutomaticHaltEnvironmentState.foundation({
    required String stateId,
    required AutomaticHaltPolicy policy,
    required DateTime createdAt,
    required String createdBy,
  }) => AutomaticHaltEnvironmentState(
    stateId: stateId,
    organizationId: policy.organizationId,
    applicationId: policy.applicationId,
    environmentId: policy.environmentId,
    generation: 1,
    supersedesStateId: null,
    policyId: policy.policyId,
    automaticHaltPolicyDigest: policy.digest,
    policyApproved: false,
    productionEnabled: false,
    productionEnableReference: null,
    createdAt: createdAt,
    createdBy: createdBy,
  );

  final String stateId;
  final String organizationId;
  final String applicationId;
  final String environmentId;
  final int generation;
  final String? supersedesStateId;
  final String policyId;
  final String automaticHaltPolicyDigest;
  final bool policyApproved;
  final bool productionEnabled;
  final String? productionEnableReference;
  final DateTime createdAt;
  final String createdBy;

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': automaticHaltEntityVersion,
    'stateId': stateId,
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'generation': generation,
    'supersedesStateId': supersedesStateId,
    'policyId': policyId,
    'automaticHaltPolicyDigest': automaticHaltPolicyDigest,
    'policyApproved': policyApproved,
    'productionEnabled': productionEnabled,
    'productionEnableReference': productionEnableReference,
    'createdAt': createdAt.toIso8601String(),
    'createdBy': createdBy,
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static AutomaticHaltEnvironmentState fromJson(Object? value) {
    final map = _object(value, 'automatic-halt environment state');
    _exact(map, const <String>{
      'entityVersion',
      'stateId',
      'organizationId',
      'applicationId',
      'environmentId',
      'generation',
      'supersedesStateId',
      'policyId',
      'automaticHaltPolicyDigest',
      'policyApproved',
      'productionEnabled',
      'productionEnableReference',
      'createdAt',
      'createdBy',
    }, 'automatic-halt environment state');
    if (map['entityVersion'] != automaticHaltEntityVersion) {
      throw const FormatException(
        'Unsupported automatic-halt environment state version',
      );
    }
    return AutomaticHaltEnvironmentState(
      stateId: _string(map['stateId'], 'automatic-halt state ID'),
      organizationId: _string(map['organizationId'], 'organization ID'),
      applicationId: _string(map['applicationId'], 'application ID'),
      environmentId: _string(map['environmentId'], 'environment ID'),
      generation: _integer(map['generation'], 'state generation'),
      supersedesStateId: _optionalString(
        map['supersedesStateId'],
        'superseded automatic-halt state ID',
      ),
      policyId: _string(map['policyId'], 'automatic-halt policy ID'),
      automaticHaltPolicyDigest: _string(
        map['automaticHaltPolicyDigest'],
        'automatic-halt policy digest',
      ),
      policyApproved: _boolean(map['policyApproved'], 'policy approved'),
      productionEnabled: _boolean(
        map['productionEnabled'],
        'production enabled',
      ),
      productionEnableReference: _optionalString(
        map['productionEnableReference'],
        'production enable reference',
      ),
      createdAt: _timestamp(map['createdAt'], 'state timestamp'),
      createdBy: _string(map['createdBy'], 'state actor'),
    );
  }
}

/// Immutable evidence that one exact scheduled decision passed the bounded
/// P3E5-4B applicability gate. This record is intent only: it grants no
/// rollout authority and is never a runtime trust input.
final class AutomaticHaltIntent {
  AutomaticHaltIntent({
    required String workId,
    required String attemptId,
    required String evaluationId,
    required String decisionId,
    required String scheduleRevisionId,
    required this.automaticHaltPolicyVersion,
    required String automaticHaltPolicyDigest,
    required this.expectedRolloutRevision,
    required String targetBindingDigest,
    required String authorizedPrincipalId,
    required DateTime authorizedAt,
  }) : workId = _id(workId, 'work ID'),
       attemptId = _id(attemptId, 'attempt ID'),
       evaluationId = _id(evaluationId, 'evaluation ID'),
       decisionId = _id(decisionId, 'decision ID'),
       scheduleRevisionId = _id(scheduleRevisionId, 'schedule revision ID'),
       automaticHaltPolicyDigest = _digest(
         automaticHaltPolicyDigest,
         'automatic-halt policy digest',
       ),
       targetBindingDigest = _digest(
         targetBindingDigest,
         'target binding digest',
       ),
       authorizedPrincipalId = _id(
         authorizedPrincipalId,
         'authorized principal ID',
       ),
       authorizedAt = _utc(authorizedAt, 'authorization timestamp') {
    if (automaticHaltPolicyVersion != supportedAutomaticHaltPolicyVersion ||
        expectedRolloutRevision <= 0) {
      throw const FormatException('Invalid automatic-halt intent version');
    }
  }

  final String workId;
  final String attemptId;
  final String evaluationId;
  final String decisionId;
  final String scheduleRevisionId;
  final int automaticHaltPolicyVersion;
  final String automaticHaltPolicyDigest;
  final int expectedRolloutRevision;
  final String targetBindingDigest;
  final String authorizedPrincipalId;
  final DateTime authorizedAt;

  Map<String, Object?> get semanticJson => <String, Object?>{
    'workId': workId,
    'attemptId': attemptId,
    'evaluationId': evaluationId,
    'decisionId': decisionId,
    'scheduleRevisionId': scheduleRevisionId,
    'automaticHaltPolicyVersion': automaticHaltPolicyVersion,
    'automaticHaltPolicyDigest': automaticHaltPolicyDigest,
    'expectedRolloutRevision': expectedRolloutRevision,
    'targetBindingDigest': targetBindingDigest,
    'authorizedPrincipalId': authorizedPrincipalId,
  };

  String get intentDigest =>
      sha256Digest(utf8.encode(canonicalJson(semanticJson)));

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': automaticHaltEntityVersion,
    ...semanticJson,
    'authorizedAt': authorizedAt.toIso8601String(),
    'intentDigest': intentDigest,
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static AutomaticHaltIntent fromJson(Object? value) {
    final map = _object(value, 'automatic-halt intent');
    _exact(map, const <String>{
      'entityVersion',
      'workId',
      'attemptId',
      'evaluationId',
      'decisionId',
      'scheduleRevisionId',
      'automaticHaltPolicyVersion',
      'automaticHaltPolicyDigest',
      'expectedRolloutRevision',
      'targetBindingDigest',
      'authorizedPrincipalId',
      'authorizedAt',
      'intentDigest',
    }, 'automatic-halt intent');
    if (map['entityVersion'] != automaticHaltEntityVersion) {
      throw const FormatException('Unsupported automatic-halt intent version');
    }
    final intent = AutomaticHaltIntent(
      workId: _string(map['workId'], 'work ID'),
      attemptId: _string(map['attemptId'], 'attempt ID'),
      evaluationId: _string(map['evaluationId'], 'evaluation ID'),
      decisionId: _string(map['decisionId'], 'decision ID'),
      scheduleRevisionId: _string(
        map['scheduleRevisionId'],
        'schedule revision ID',
      ),
      automaticHaltPolicyVersion: _positiveInteger(
        map['automaticHaltPolicyVersion'],
        'automatic-halt policy version',
      ),
      automaticHaltPolicyDigest: _string(
        map['automaticHaltPolicyDigest'],
        'automatic-halt policy digest',
      ),
      expectedRolloutRevision: _positiveInteger(
        map['expectedRolloutRevision'],
        'expected rollout revision',
      ),
      targetBindingDigest: _string(
        map['targetBindingDigest'],
        'target binding digest',
      ),
      authorizedPrincipalId: _string(
        map['authorizedPrincipalId'],
        'authorized principal ID',
      ),
      authorizedAt: _timestamp(map['authorizedAt'], 'authorization timestamp'),
    );
    if (map['intentDigest'] != intent.intentDigest) {
      throw const FormatException('Automatic-halt intent digest mismatch');
    }
    return intent;
  }

  @override
  String toString() => 'AutomaticHaltIntent($intentDigest)';
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

String _string(Object? value, String label) {
  if (value is! String) throw FormatException('Invalid $label');
  return _bounded(value, label);
}

String? _optionalString(Object? value, String label) =>
    value == null ? null : _string(value, label);

String _bounded(String value, String label, {int maximum = 512}) {
  if (value.isEmpty ||
      value.length > maximum ||
      value.contains(RegExp(r'[\u0000\r\n]'))) {
    throw FormatException('Invalid $label');
  }
  return value;
}

String _id(String value, String label) {
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.:-]{0,127}$').hasMatch(value)) {
    throw FormatException('Invalid $label');
  }
  return value;
}

String _digest(String value, String label) {
  try {
    return requireSha256Digest(value);
  } on FormatException {
    throw FormatException('Invalid $label');
  }
}

int _integer(Object? value, String label) {
  if (value is! int) throw FormatException('Invalid $label');
  return value;
}

int _positiveInteger(Object? value, String label) {
  final parsed = _integer(value, label);
  if (parsed <= 0) throw FormatException('Invalid $label');
  return parsed;
}

bool _boolean(Object? value, String label) {
  if (value is! bool) throw FormatException('Invalid $label');
  return value;
}

DateTime _utc(DateTime value, String label) {
  if (!value.isUtc) throw FormatException('$label must be UTC');
  return value;
}

DateTime _timestamp(Object? value, String label) {
  if (value is! String || !value.endsWith('Z')) {
    throw FormatException('Invalid $label');
  }
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw FormatException('Invalid $label');
  }
}
