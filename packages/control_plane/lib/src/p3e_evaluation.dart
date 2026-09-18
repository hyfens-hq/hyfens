import 'dart:convert';

import 'aggregation.dart';
import 'encoding.dart';
import 'p3e_persistence.dart';

const int supportedManualEvaluationVersion = 1;

final RegExp _manualEvaluationIdempotencyPattern = RegExp(
  r'^[A-Za-z0-9._:-]{1,200}$',
);

String _evaluationString(Object? value, String label, {int maxLength = 256}) {
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('Invalid $label');
  }
  return value;
}

String _evaluationId(Object? value, String label) =>
    requireOpaqueId(_evaluationString(value, label), label);

int _evaluationInt(Object? value, String label, {bool positive = false}) {
  if (value is! int || value < 0 || (positive && value == 0)) {
    throw FormatException('Invalid $label');
  }
  return value;
}

bool _evaluationBool(Object? value, String label) {
  if (value is! bool) throw FormatException('Invalid $label');
  return value;
}

Map<String, Object?> _evaluationObject(Object? value, String label) {
  if (value is! Map) throw FormatException('Invalid $label object');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('Invalid $label key');
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _evaluationExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String label,
) {
  if (value.length != expected.length ||
      value.keys.any((key) => !expected.contains(key))) {
    throw FormatException('Invalid $label fields');
  }
}

int? _optionalThreshold(Object? value, String label) {
  if (value == null) return null;
  final threshold = _evaluationInt(value, label);
  if (threshold > 10000) throw FormatException('Invalid $label');
  return threshold;
}

/// One explicit evaluator policy. Every field is supplied by the caller; the
/// implementation does not contain production thresholds or fixture defaults.
final class ManualEvaluationPolicy {
  ManualEvaluationPolicy({
    required this.evaluationVersion,
    required this.policyVersion,
    required this.thresholdSetVersion,
    required this.windowPolicyVersion,
    required this.privacyPolicyVersion,
    required String thresholdSetDigest,
    required this.minimumSamples,
    required this.requireFreshness,
    required this.allowNonRecomputable,
    required this.maximumQuarantineRateBasisPoints,
    required this.maximumRejectedRateBasisPoints,
    required this.maximumLateRateBasisPoints,
    required this.haltActivationFailureRateBasisPoints,
    required this.haltAdmissionRejectionRateBasisPoints,
    required this.haltRuntimeFaultRateBasisPoints,
    required this.haltRollbackFallbackRateBasisPoints,
  }) : thresholdSetDigest = requireSha256Digest(thresholdSetDigest) {
    validate();
  }

  final int evaluationVersion;
  final int policyVersion;
  final int thresholdSetVersion;
  final int windowPolicyVersion;
  final int privacyPolicyVersion;
  final String thresholdSetDigest;
  final AggregationMinimumSamples minimumSamples;
  final bool requireFreshness;
  final bool allowNonRecomputable;
  final int maximumQuarantineRateBasisPoints;
  final int maximumRejectedRateBasisPoints;
  final int maximumLateRateBasisPoints;
  final int? haltActivationFailureRateBasisPoints;
  final int? haltAdmissionRejectionRateBasisPoints;
  final int? haltRuntimeFaultRateBasisPoints;
  final int? haltRollbackFallbackRateBasisPoints;

  void validate() {
    if (evaluationVersion != supportedManualEvaluationVersion ||
        policyVersion != supportedAggregationPolicyVersion ||
        thresholdSetVersion != supportedP3eThresholdSetVersion ||
        windowPolicyVersion != supportedWindowPolicyVersion ||
        privacyPolicyVersion != supportedP3ePrivacyPolicyVersion) {
      throw const FormatException(
        'Unsupported manual evaluation policy version',
      );
    }
    minimumSamples.validate();
    for (final value in <int>[
      maximumQuarantineRateBasisPoints,
      maximumRejectedRateBasisPoints,
      maximumLateRateBasisPoints,
    ]) {
      if (value < 0 || value > 10000) {
        throw const FormatException(
          'Manual evaluation quality limit is invalid',
        );
      }
    }
    for (final value in <int?>[
      haltActivationFailureRateBasisPoints,
      haltAdmissionRejectionRateBasisPoints,
      haltRuntimeFaultRateBasisPoints,
      haltRollbackFallbackRateBasisPoints,
    ]) {
      if (value != null && (value < 0 || value > 10000)) {
        throw const FormatException('Manual evaluation threshold is invalid');
      }
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'evaluationVersion': evaluationVersion,
    'policyVersion': policyVersion,
    'thresholdSetVersion': thresholdSetVersion,
    'windowPolicyVersion': windowPolicyVersion,
    'privacyPolicyVersion': privacyPolicyVersion,
    'thresholdSetDigest': thresholdSetDigest,
    'minimumSamples': minimumSamples.toJson(),
    'requireFreshness': requireFreshness,
    'allowNonRecomputable': allowNonRecomputable,
    'maximumQuarantineRateBasisPoints': maximumQuarantineRateBasisPoints,
    'maximumRejectedRateBasisPoints': maximumRejectedRateBasisPoints,
    'maximumLateRateBasisPoints': maximumLateRateBasisPoints,
    'haltActivationFailureRateBasisPoints':
        haltActivationFailureRateBasisPoints,
    'haltAdmissionRejectionRateBasisPoints':
        haltAdmissionRejectionRateBasisPoints,
    'haltRuntimeFaultRateBasisPoints': haltRuntimeFaultRateBasisPoints,
    'haltRollbackFallbackRateBasisPoints': haltRollbackFallbackRateBasisPoints,
  };

  String get policyDigest => sha256Digest(utf8.encode(canonicalJson(toJson())));

  static ManualEvaluationPolicy fromJson(Object? value) {
    final map = _evaluationObject(value, 'manual evaluation policy');
    _evaluationExactKeys(map, const {
      'evaluationVersion',
      'policyVersion',
      'thresholdSetVersion',
      'windowPolicyVersion',
      'privacyPolicyVersion',
      'thresholdSetDigest',
      'minimumSamples',
      'requireFreshness',
      'allowNonRecomputable',
      'maximumQuarantineRateBasisPoints',
      'maximumRejectedRateBasisPoints',
      'maximumLateRateBasisPoints',
      'haltActivationFailureRateBasisPoints',
      'haltAdmissionRejectionRateBasisPoints',
      'haltRuntimeFaultRateBasisPoints',
      'haltRollbackFallbackRateBasisPoints',
    }, 'manual evaluation policy');
    final samples = _evaluationObject(map['minimumSamples'], 'minimum samples');
    _evaluationExactKeys(samples, const {
      'minimumEligibleObserved',
      'minimumOffers',
      'minimumActivated',
      'minimumHealthyConfirmations',
      'minimumCoverageBasisPoints',
    }, 'minimum samples');
    return ManualEvaluationPolicy(
      evaluationVersion: _evaluationInt(
        map['evaluationVersion'],
        'evaluation version',
        positive: true,
      ),
      policyVersion: _evaluationInt(
        map['policyVersion'],
        'policy version',
        positive: true,
      ),
      thresholdSetVersion: _evaluationInt(
        map['thresholdSetVersion'],
        'threshold set version',
        positive: true,
      ),
      windowPolicyVersion: _evaluationInt(
        map['windowPolicyVersion'],
        'window policy version',
        positive: true,
      ),
      privacyPolicyVersion: _evaluationInt(
        map['privacyPolicyVersion'],
        'privacy policy version',
        positive: true,
      ),
      thresholdSetDigest: _evaluationString(
        map['thresholdSetDigest'],
        'threshold set digest',
      ),
      minimumSamples: AggregationMinimumSamples(
        minimumEligibleObserved: _evaluationInt(
          samples['minimumEligibleObserved'],
          'minimum eligible observed',
        ),
        minimumOffers: _evaluationInt(
          samples['minimumOffers'],
          'minimum offers',
        ),
        minimumActivated: _evaluationInt(
          samples['minimumActivated'],
          'minimum activated',
        ),
        minimumHealthyConfirmations: _evaluationInt(
          samples['minimumHealthyConfirmations'],
          'minimum healthy confirmations',
        ),
        minimumCoverageBasisPoints: _evaluationInt(
          samples['minimumCoverageBasisPoints'],
          'minimum coverage basis points',
        ),
      ),
      requireFreshness: _evaluationBool(
        map['requireFreshness'],
        'require freshness',
      ),
      allowNonRecomputable: _evaluationBool(
        map['allowNonRecomputable'],
        'allow non-recomputable',
      ),
      maximumQuarantineRateBasisPoints: _evaluationInt(
        map['maximumQuarantineRateBasisPoints'],
        'maximum quarantine rate',
      ),
      maximumRejectedRateBasisPoints: _evaluationInt(
        map['maximumRejectedRateBasisPoints'],
        'maximum rejected rate',
      ),
      maximumLateRateBasisPoints: _evaluationInt(
        map['maximumLateRateBasisPoints'],
        'maximum late rate',
      ),
      haltActivationFailureRateBasisPoints: _optionalThreshold(
        map['haltActivationFailureRateBasisPoints'],
        'activation-failure threshold',
      ),
      haltAdmissionRejectionRateBasisPoints: _optionalThreshold(
        map['haltAdmissionRejectionRateBasisPoints'],
        'admission-rejection threshold',
      ),
      haltRuntimeFaultRateBasisPoints: _optionalThreshold(
        map['haltRuntimeFaultRateBasisPoints'],
        'runtime-fault threshold',
      ),
      haltRollbackFallbackRateBasisPoints: _optionalThreshold(
        map['haltRollbackFallbackRateBasisPoints'],
        'rollback/fallback threshold',
      ),
    );
  }
}

/// Exact aggregate/revision/policy references accepted by the manual API.
/// Counters and metrics are deliberately absent; they are loaded from P3E-2.
final class ManualEvaluationRequest {
  ManualEvaluationRequest({
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String platformId,
    required String rolloutId,
    required this.rolloutRevision,
    required this.aggregationVersion,
    required String aggregateId,
    required String aggregateRevisionId,
    required String releaseId,
    required String patchId,
    required this.sequence,
    required String windowId,
    required String aggregateInputDigest,
    required String aggregatePolicyDigest,
    required String policyDigest,
    required this.policy,
  }) : organizationId = _evaluationId(organizationId, 'organization ID'),
       applicationId = _evaluationId(applicationId, 'application ID'),
       environmentId = _evaluationId(environmentId, 'environment ID'),
       platformId = _evaluationId(platformId, 'platform ID'),
       rolloutId = _evaluationId(rolloutId, 'rollout ID'),
       aggregateId = _evaluationId(aggregateId, 'aggregate ID'),
       aggregateRevisionId = _evaluationId(
         aggregateRevisionId,
         'aggregate revision ID',
       ),
       releaseId = _evaluationId(releaseId, 'release ID'),
       patchId = _evaluationId(patchId, 'patch ID'),
       windowId = _evaluationId(windowId, 'window ID'),
       aggregateInputDigest = requireSha256Digest(aggregateInputDigest),
       aggregatePolicyDigest = requireSha256Digest(aggregatePolicyDigest),
       policyDigest = requireSha256Digest(policyDigest) {
    if (rolloutRevision <= 0 || sequence <= 0 || aggregationVersion <= 0) {
      throw const FormatException('Manual evaluation identity is invalid');
    }
    if (policy.policyDigest != policyDigest) {
      throw const FormatException('Manual evaluation policy digest mismatch');
    }
  }

  final String organizationId;
  final String applicationId;
  final String environmentId;
  final String platformId;
  final String rolloutId;
  final int rolloutRevision;
  final int aggregationVersion;
  final String aggregateId;
  final String aggregateRevisionId;
  final String releaseId;
  final String patchId;
  final int sequence;
  final String windowId;
  final String aggregateInputDigest;
  final String aggregatePolicyDigest;
  final String policyDigest;
  final ManualEvaluationPolicy policy;

  Map<String, Object?> toJson() => <String, Object?>{
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'platformId': platformId,
    'rolloutId': rolloutId,
    'rolloutRevision': rolloutRevision,
    'aggregationVersion': aggregationVersion,
    'aggregateId': aggregateId,
    'aggregateRevisionId': aggregateRevisionId,
    'releaseId': releaseId,
    'patchId': patchId,
    'sequence': sequence,
    'windowId': windowId,
    'aggregateInputDigest': aggregateInputDigest,
    'aggregatePolicyDigest': aggregatePolicyDigest,
    'policyDigest': policyDigest,
    'policy': policy.toJson(),
  };

  String get canonicalSerialization => canonicalJson(toJson());

  String get requestDigest => sha256Digest(utf8.encode(canonicalSerialization));

  static ManualEvaluationRequest fromApiJson(
    Object? value, {
    required String rolloutId,
  }) {
    final map = _evaluationObject(value, 'manual evaluation request');
    _evaluationExactKeys(map, const {
      'organization_id',
      'application_id',
      'environment_id',
      'platform_id',
      'rollout_revision',
      'aggregation_version',
      'aggregate_id',
      'aggregate_revision_id',
      'release_id',
      'patch_id',
      'sequence',
      'window_id',
      'aggregate_input_digest',
      'aggregate_policy_digest',
      'policy_digest',
      'policy',
    }, 'manual evaluation request');
    return ManualEvaluationRequest(
      organizationId: _evaluationString(
        map['organization_id'],
        'organization ID',
      ),
      applicationId: _evaluationString(map['application_id'], 'application ID'),
      environmentId: _evaluationString(map['environment_id'], 'environment ID'),
      platformId: _evaluationString(map['platform_id'], 'platform ID'),
      rolloutId: rolloutId,
      rolloutRevision: _evaluationInt(
        map['rollout_revision'],
        'rollout revision',
        positive: true,
      ),
      aggregationVersion: _evaluationInt(
        map['aggregation_version'],
        'aggregation version',
        positive: true,
      ),
      aggregateId: _evaluationString(map['aggregate_id'], 'aggregate ID'),
      aggregateRevisionId: _evaluationString(
        map['aggregate_revision_id'],
        'aggregate revision ID',
      ),
      releaseId: _evaluationString(map['release_id'], 'release ID'),
      patchId: _evaluationString(map['patch_id'], 'patch ID'),
      sequence: _evaluationInt(map['sequence'], 'sequence', positive: true),
      windowId: _evaluationString(map['window_id'], 'window ID'),
      aggregateInputDigest: _evaluationString(
        map['aggregate_input_digest'],
        'aggregate input digest',
      ),
      aggregatePolicyDigest: _evaluationString(
        map['aggregate_policy_digest'],
        'aggregate policy digest',
      ),
      policyDigest: _evaluationString(map['policy_digest'], 'policy digest'),
      policy: ManualEvaluationPolicy.fromJson(map['policy']),
    );
  }
}

final class ManualEvaluationDecision {
  const ManualEvaluationDecision({
    required this.decision,
    required this.reasonClass,
    required this.reasonCodes,
    required this.coverageState,
    required this.freshnessState,
    required this.sampleState,
  });

  final String decision;
  final String reasonClass;
  final List<String> reasonCodes;
  final String coverageState;
  final String freshnessState;
  final String sampleState;
}

final class ManualEvaluationSnapshot {
  const ManualEvaluationSnapshot({
    required this.evaluation,
    required this.decision,
    this.idempotentReplay = false,
  });

  final HealthEvaluation evaluation;
  final RolloutDecisionRecord decision;
  final bool idempotentReplay;

  Map<String, Object?> toJson() => <String, Object?>{
    'evaluation': evaluation.toJson(),
    'decision': decision.toJson(),
    'idempotentReplay': idempotentReplay,
  };
}

final class ManualEvaluationPage {
  const ManualEvaluationPage({required this.items, required this.nextCursor});

  final List<ManualEvaluationSnapshot> items;
  final String? nextCursor;

  Map<String, Object?> toJson() => <String, Object?>{
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'nextCursor': nextCursor,
  };
}

/// Pure deterministic P3E-3 evaluator. It reads no clocks, stores no state,
/// and has no authority to mutate a rollout or runtime trust state.
final class ManualP3eEvaluator {
  const ManualP3eEvaluator();

  String evaluationInputDigest({
    required HealthAggregateRecord aggregate,
    required HealthAggregateRevision revision,
    required ManualEvaluationRequest request,
  }) {
    return sha256Digest(
      utf8.encode(
        canonicalJson(<String, Object?>{
          'aggregateId': aggregate.aggregateId,
          'aggregateRevisionId': revision.aggregateRevisionId,
          'aggregateDigest': aggregate.aggregateDigest,
          'aggregateIdentity': revision.identity.toJson(),
          'window': revision.window.toJson(),
          'inputDigest': revision.inputDigest,
          'aggregatePolicyDigest': aggregate.aggregate.policyDigest,
          'manualPolicyDigest': request.policyDigest,
          'thresholdSetDigest': request.policy.thresholdSetDigest,
          'evaluationVersion': request.policy.evaluationVersion,
          'policyVersion': request.policy.policyVersion,
          'thresholdSetVersion': request.policy.thresholdSetVersion,
          'windowPolicyVersion': request.policy.windowPolicyVersion,
          'privacyPolicyVersion': request.policy.privacyPolicyVersion,
          'quality': aggregate.aggregate.quality.toJson(),
          'privacyState': aggregate.aggregate.privacyState.wireName,
          'freshnessState': aggregate.aggregate.freshnessState.wireName,
          'coverageState': aggregate.aggregate.coverage.state.wireName,
          'recomputability': aggregate.recomputability.wireName,
        }),
      ),
    );
  }

  ManualEvaluationDecision evaluate({
    required HealthAggregateRecord aggregate,
    required HealthAggregateRevision revision,
    required ManualEvaluationRequest request,
  }) {
    request.policy.validate();
    _validateEvidence(aggregate, revision, request);
    final health = aggregate.aggregate;
    final coverageState = _coverageState(health, request.policy);
    final minimumSamplesPass = _minimumSamplesPass(health, request.policy);
    final freshnessState = health.freshnessState.wireName;
    final sampleState =
        health.coverage.state == AggregateCoverageState.notEvaluable
        ? 'NOT_EVALUABLE'
        : minimumSamplesPass
        ? 'PASSED'
        : 'INSUFFICIENT';

    if (health.privacyState != AggregatePrivacyState.normal) {
      return _result(
        'INSUFFICIENT_DATA',
        'DATA_QUALITY',
        const <String>['PRIVACY_SUPPRESSED'],
        coverageState,
        freshnessState,
        sampleState,
      );
    }
    if (aggregate.recomputability != P3eRecomputability.rawRecomputable) {
      if (!request.policy.allowNonRecomputable) {
        throw const FormatException(
          'Policy does not permit non-recomputable aggregate evidence',
        );
      }
      return _result(
        'MANUAL_REVIEW',
        'DATA_QUALITY',
        const <String>['NON_RECOMPUTABLE_EVIDENCE'],
        coverageState,
        freshnessState,
        sampleState,
      );
    }
    if (coverageState != AggregateCoverageState.sufficient.wireName ||
        !minimumSamplesPass) {
      return _result(
        'INSUFFICIENT_DATA',
        'DATA_QUALITY',
        const <String>['MINIMUM_SAMPLE_OR_COVERAGE'],
        coverageState,
        freshnessState,
        sampleState,
      );
    }
    if (request.policy.requireFreshness &&
        health.freshnessState != AggregateFreshnessState.fresh) {
      return _result(
        'INSUFFICIENT_DATA',
        'OBSERVATION_HEALTH',
        const <String>['STALE_OR_UNKNOWN_FRESHNESS'],
        coverageState,
        freshnessState,
        sampleState,
      );
    }

    final qualityDecision = _qualityDecision(
      health,
      request.policy,
      coverageState,
      freshnessState,
      sampleState,
    );
    if (qualityDecision != null) return qualityDecision;

    final missingDecision = _missingDataDecision(
      health,
      coverageState,
      freshnessState,
      sampleState,
    );
    if (missingDecision != null) return missingDecision;

    final deliveryDecision = _deliveryDecision(
      health,
      coverageState,
      freshnessState,
      sampleState,
    );
    if (deliveryDecision != null) return deliveryDecision;

    final patchSafety = _patchSafetyDecision(
      health,
      request.policy,
      coverageState,
      freshnessState,
      sampleState,
    );
    if (patchSafety != null) return patchSafety;

    return _result(
      'CONTINUE',
      'PATCH_SAFETY',
      const <String>['HEALTHY_COMPLETE_EVIDENCE'],
      coverageState,
      freshnessState,
      sampleState,
    );
  }

  ManualEvaluationDecision? _qualityDecision(
    HealthAggregate health,
    ManualEvaluationPolicy policy,
    String coverageState,
    String freshnessState,
    String sampleState,
  ) {
    final inputCount = health.inputCount;
    final quarantineRate = _rate(health.quality.quarantined, inputCount);
    final rejectedRate = _rate(health.quality.rejected, inputCount);
    final lateRate = _rate(health.counters.lateEvents, inputCount);
    if ((quarantineRate != null &&
            quarantineRate > policy.maximumQuarantineRateBasisPoints) ||
        (rejectedRate != null &&
            rejectedRate > policy.maximumRejectedRateBasisPoints) ||
        (lateRate != null && lateRate > policy.maximumLateRateBasisPoints)) {
      return _result(
        'MANUAL_REVIEW',
        'DATA_QUALITY',
        <String>[
          if (quarantineRate != null &&
              quarantineRate > policy.maximumQuarantineRateBasisPoints)
            'QUARANTINE_RATE_EXCEEDED',
          if (rejectedRate != null &&
              rejectedRate > policy.maximumRejectedRateBasisPoints)
            'REJECTED_RATE_EXCEEDED',
          if (lateRate != null && lateRate > policy.maximumLateRateBasisPoints)
            'LATE_RATE_EXCEEDED',
        ],
        coverageState,
        freshnessState,
        sampleState,
      );
    }
    return null;
  }

  String _coverageState(HealthAggregate health, ManualEvaluationPolicy policy) {
    if (health.coverage.state == AggregateCoverageState.notEvaluable ||
        health.coverage.observedBasisPoints == null) {
      return AggregateCoverageState.notEvaluable.wireName;
    }
    if (health.coverage.state != AggregateCoverageState.sufficient ||
        health.coverage.observedBasisPoints! <
            policy.minimumSamples.minimumCoverageBasisPoints) {
      return AggregateCoverageState.insufficient.wireName;
    }
    return AggregateCoverageState.sufficient.wireName;
  }

  bool _minimumSamplesPass(
    HealthAggregate health,
    ManualEvaluationPolicy policy,
  ) {
    final minimum = policy.minimumSamples;
    final counters = health.counters;
    return counters.eligibleInstallationsObserved >=
            minimum.minimumEligibleObserved &&
        counters.candidateOffers >= minimum.minimumOffers &&
        counters.activationSucceeded >= minimum.minimumActivated &&
        counters.healthyConfirmed >= minimum.minimumHealthyConfirmations &&
        health.coverage.observedBasisPoints != null &&
        health.coverage.observedBasisPoints! >=
            minimum.minimumCoverageBasisPoints;
  }

  ManualEvaluationDecision? _missingDataDecision(
    HealthAggregate health,
    String coverageState,
    String freshnessState,
    String sampleState,
  ) {
    final reasons = health.missingData;
    if (reasons.contains(AggregateMissingDataReason.observationOutage)) {
      return _result(
        'HOLD',
        'OBSERVATION_HEALTH',
        const <String>['OBSERVATION_OUTAGE'],
        coverageState,
        freshnessState,
        sampleState,
      );
    }
    if (reasons.contains(AggregateMissingDataReason.materialQuarantine)) {
      return _result(
        'MANUAL_REVIEW',
        'DATA_QUALITY',
        const <String>['MATERIAL_QUARANTINE'],
        coverageState,
        freshnessState,
        sampleState,
      );
    }
    if (reasons.isNotEmpty) {
      return _result(
        'INSUFFICIENT_DATA',
        'OBSERVATION_HEALTH',
        reasons.map((reason) => reason.wireName).toList(growable: false),
        coverageState,
        freshnessState,
        sampleState,
      );
    }
    return null;
  }

  ManualEvaluationDecision? _deliveryDecision(
    HealthAggregate health,
    String coverageState,
    String freshnessState,
    String sampleState,
  ) {
    final counters = health.counters;
    if (counters.candidateOffers > 0 &&
        counters.downloadSucceeded == 0 &&
        counters.downloadFailed > 0 &&
        counters.activationStarted == 0) {
      return _result(
        'HOLD',
        'DELIVERY_HEALTH',
        const <String>['DELIVERY_OUTAGE'],
        coverageState,
        freshnessState,
        sampleState,
      );
    }
    return null;
  }

  ManualEvaluationDecision? _patchSafetyDecision(
    HealthAggregate health,
    ManualEvaluationPolicy policy,
    String coverageState,
    String freshnessState,
    String sampleState,
  ) {
    final checks = <_ThresholdCheck>[
      _ThresholdCheck(
        code: 'ACTIVATION_FAILURE_RATE',
        numerator: health.counters.activationFailed,
        denominator: health.counters.activationStarted,
        threshold: policy.haltActivationFailureRateBasisPoints,
      ),
      _ThresholdCheck(
        code: 'ADMISSION_REJECTION_RATE',
        numerator: health.counters.admissionRejected,
        denominator:
            health.counters.admissionRejected +
            health.counters.admissionVerified,
        threshold: policy.haltAdmissionRejectionRateBasisPoints,
      ),
      _ThresholdCheck(
        code: 'RUNTIME_FAULT_RATE',
        metric: health.metrics[AggregateMetricName.runtimeFaultRate],
        threshold: policy.haltRuntimeFaultRateBasisPoints,
      ),
      _ThresholdCheck(
        code: 'ROLLBACK_FALLBACK_RATE',
        metric: health.metrics[AggregateMetricName.rollbackFallbackRate],
        threshold: policy.haltRollbackFallbackRateBasisPoints,
      ),
    ];
    final missingThresholdSignals = <String>[];
    for (final check in checks) {
      final signal = check.rate;
      if (signal == null || signal == 0) continue;
      if (check.threshold == null) {
        missingThresholdSignals.add('${check.code}_THRESHOLD_REQUIRED');
      } else if (signal >= check.threshold!) {
        return _result(
          'HALT_NEW_OFFERS',
          'PATCH_SAFETY',
          <String>['${check.code}_EXCEEDED'],
          coverageState,
          freshnessState,
          sampleState,
        );
      }
    }
    if (missingThresholdSignals.isNotEmpty) {
      return _result(
        'MANUAL_REVIEW',
        'OPERATOR_POLICY',
        missingThresholdSignals,
        coverageState,
        freshnessState,
        sampleState,
      );
    }
    return null;
  }

  ManualEvaluationDecision _result(
    String decision,
    String reasonClass,
    Iterable<String> reasonCodes,
    String coverageState,
    String freshnessState,
    String sampleState,
  ) => ManualEvaluationDecision(
    decision: decision,
    reasonClass: reasonClass,
    reasonCodes: reasonCodes.toSet().toList()..sort(),
    coverageState: coverageState,
    freshnessState: freshnessState,
    sampleState: sampleState,
  );

  void _validateEvidence(
    HealthAggregateRecord aggregate,
    HealthAggregateRevision revision,
    ManualEvaluationRequest request,
  ) {
    if (aggregate.organizationId != request.organizationId ||
        revision.identity.organizationId != request.organizationId ||
        aggregate.aggregateId != request.aggregateId ||
        revision.aggregateId != request.aggregateId ||
        revision.aggregateRevisionId != request.aggregateRevisionId ||
        aggregate.revisionId != revision.aggregateRevisionId ||
        revision.identity.applicationId != request.applicationId ||
        revision.identity.environmentId != request.environmentId ||
        revision.identity.platformId != request.platformId ||
        revision.identity.rolloutId != request.rolloutId ||
        revision.identity.rolloutRevision != request.rolloutRevision ||
        revision.aggregationVersion != request.aggregationVersion ||
        revision.identity.aggregationVersion != request.aggregationVersion ||
        revision.identity.releaseId != request.releaseId ||
        revision.identity.patchId != request.patchId ||
        revision.identity.sequence != request.sequence ||
        revision.identity.windowId != request.windowId ||
        revision.inputDigest != request.aggregateInputDigest ||
        aggregate.aggregate.policyDigest != request.aggregatePolicyDigest ||
        aggregate.aggregate.inputDigest != revision.inputDigest ||
        aggregate.aggregate.identity.canonicalSerialization !=
            revision.identity.canonicalSerialization ||
        aggregate.aggregate.window.canonicalSerialization !=
            revision.window.canonicalSerialization) {
      throw const FormatException('Manual evaluation evidence scope mismatch');
    }
  }

  static int? _rate(int numerator, int denominator) {
    if (denominator <= 0) return null;
    return (numerator * 10000) ~/ denominator;
  }
}

final class _ThresholdCheck {
  _ThresholdCheck({
    required this.code,
    this.numerator,
    this.denominator,
    this.metric,
    required this.threshold,
  });

  final String code;
  final int? numerator;
  final int? denominator;
  final AggregateMetric? metric;
  final int? threshold;

  int? get rate {
    if (metric != null) {
      if (metric!.status != AggregateMetricStatus.evaluable ||
          metric!.denominator <= 0) {
        return null;
      }
      return (metric!.numerator * 10000) ~/ metric!.denominator;
    }
    if (numerator == null || denominator == null || denominator! <= 0) {
      return null;
    }
    return (numerator! * 10000) ~/ denominator!;
  }
}

void validateManualEvaluationIdempotencyKey(String value) {
  if (!_manualEvaluationIdempotencyPattern.hasMatch(value)) {
    throw const FormatException('Invalid manual evaluation idempotency key');
  }
}

String manualEvaluationId({
  required String organizationId,
  required String rolloutId,
  required String idempotencyKey,
}) =>
    'eval_${sha256Digest(utf8.encode('$organizationId|$rolloutId|$idempotencyKey')).substring(7)}';

String manualDecisionId(String evaluationId) =>
    'decision_${sha256Digest(utf8.encode(evaluationId)).substring(7)}';

String manualAuditReference(String evaluationId) =>
    'audit:health-evaluation:$evaluationId';
