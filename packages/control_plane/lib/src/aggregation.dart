import 'dart:convert';

import 'encoding.dart';
import 'observation.dart';

const int supportedAggregationVersion = 1;
const int supportedAggregationPolicyVersion = 1;
const int supportedWindowPolicyVersion = 1;
const int supportedObservationSchemaVersion = observationSchemaVersion;

enum AggregationWindowPhase { open, closed, sealed }

extension AggregationWindowPhaseWire on AggregationWindowPhase {
  String get wireName => switch (this) {
    AggregationWindowPhase.open => 'OPEN',
    AggregationWindowPhase.closed => 'CLOSED',
    AggregationWindowPhase.sealed => 'SEALED',
  };
}

enum AggregationRecordPlacement { primary, late, outside }

enum AggregatePrivacyState { normal, smallCohortSuppressed, insufficientData }

extension AggregatePrivacyStateWire on AggregatePrivacyState {
  String get wireName => switch (this) {
    AggregatePrivacyState.normal => 'NORMAL',
    AggregatePrivacyState.smallCohortSuppressed => 'SMALL_COHORT_SUPPRESSED',
    AggregatePrivacyState.insufficientData => 'INSUFFICIENT_DATA',
  };
}

enum AggregateFreshnessState { fresh, stale, unknown }

extension AggregateFreshnessStateWire on AggregateFreshnessState {
  String get wireName => switch (this) {
    AggregateFreshnessState.fresh => 'FRESH',
    AggregateFreshnessState.stale => 'STALE',
    AggregateFreshnessState.unknown => 'UNKNOWN',
  };
}

enum AggregateCoverageState { sufficient, insufficient, notEvaluable }

extension AggregateCoverageStateWire on AggregateCoverageState {
  String get wireName => switch (this) {
    AggregateCoverageState.sufficient => 'SUFFICIENT',
    AggregateCoverageState.insufficient => 'INSUFFICIENT',
    AggregateCoverageState.notEvaluable => 'NOT_EVALUABLE',
  };
}

enum AggregateMetricStatus { evaluable, notEvaluable }

extension AggregateMetricStatusWire on AggregateMetricStatus {
  String get wireName => switch (this) {
    AggregateMetricStatus.evaluable => 'EVALUABLE',
    AggregateMetricStatus.notEvaluable => 'NOT_EVALUABLE',
  };
}

enum AggregateMissingDataReason {
  noEvidence,
  incompleteLifecycle,
  staleEvidence,
  observationOutage,
  materialQuarantine,
  missingRestartEvidence,
}

extension AggregateMissingDataReasonWire on AggregateMissingDataReason {
  String get wireName => switch (this) {
    AggregateMissingDataReason.noEvidence => 'NO_EVIDENCE',
    AggregateMissingDataReason.incompleteLifecycle => 'INCOMPLETE_LIFECYCLE',
    AggregateMissingDataReason.staleEvidence => 'STALE_EVIDENCE',
    AggregateMissingDataReason.observationOutage => 'OBSERVATION_OUTAGE',
    AggregateMissingDataReason.materialQuarantine => 'MATERIAL_QUARANTINE',
    AggregateMissingDataReason.missingRestartEvidence =>
      'MISSING_RESTART_EVIDENCE',
  };
}

enum AggregateMetricName {
  downloadSuccess,
  admissionSuccess,
  activationSuccess,
  healthyConfirmation,
  runtimeFaultRate,
  rollbackFallbackRate,
  restartSurvival,
  freshness,
  quarantineRate,
}

extension AggregateMetricNameWire on AggregateMetricName {
  String get wireName => switch (this) {
    AggregateMetricName.downloadSuccess => 'download_success',
    AggregateMetricName.admissionSuccess => 'admission_success',
    AggregateMetricName.activationSuccess => 'activation_success',
    AggregateMetricName.healthyConfirmation => 'healthy_confirmation',
    AggregateMetricName.runtimeFaultRate => 'runtime_fault_rate',
    AggregateMetricName.rollbackFallbackRate => 'rollback_fallback_rate',
    AggregateMetricName.restartSurvival => 'restart_survival',
    AggregateMetricName.freshness => 'freshness',
    AggregateMetricName.quarantineRate => 'quarantine_rate',
  };
}

enum MetricDenominatorSource { activationSucceeded, healthyConfirmed }

extension MetricDenominatorSourceWire on MetricDenominatorSource {
  String get wireName => switch (this) {
    MetricDenominatorSource.activationSucceeded => 'activation_succeeded',
    MetricDenominatorSource.healthyConfirmed => 'healthy_confirmed',
  };
}

enum ObservationCategory {
  delivery,
  admission,
  activation,
  postActivationHealth,
  rollbackFallback,
  restartSurvival,
  storeBoundExclusion,
}

extension ObservationCategoryWire on ObservationCategory {
  String get wireName => switch (this) {
    ObservationCategory.delivery => 'DELIVERY',
    ObservationCategory.admission => 'ADMISSION',
    ObservationCategory.activation => 'ACTIVATION',
    ObservationCategory.postActivationHealth => 'POST_ACTIVATION_HEALTH',
    ObservationCategory.rollbackFallback => 'ROLLBACK_FALLBACK',
    ObservationCategory.restartSurvival => 'RESTART_SURVIVAL',
    ObservationCategory.storeBoundExclusion => 'STORE_BOUND_EXCLUSION',
  };
}

ObservationCategory categoryForObservation(ObservationEventType type) =>
    switch (type) {
      ObservationEventType.lookup_attempt ||
      ObservationEventType.candidate_offered ||
      ObservationEventType.download_succeeded ||
      ObservationEventType.download_failed => ObservationCategory.delivery,
      ObservationEventType.admission_verified ||
      ObservationEventType.admission_rejected => ObservationCategory.admission,
      ObservationEventType.activation_started ||
      ObservationEventType.activation_succeeded ||
      ObservationEventType.activation_failed => ObservationCategory.activation,
      ObservationEventType.healthy_confirmed ||
      ObservationEventType.runtime_fault =>
        ObservationCategory.postActivationHealth,
      ObservationEventType.rollback || ObservationEventType.fallback_to_aot =>
        ObservationCategory.rollbackFallback,
      ObservationEventType.restart_survived =>
        ObservationCategory.restartSurvival,
      ObservationEventType.store_release_required =>
        ObservationCategory.storeBoundExclusion,
    };

/// The exact immutable scope for one aggregate computation.
final class AggregateIdentity {
  AggregateIdentity({
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String platformId,
    required String releaseId,
    required String patchId,
    required this.sequence,
    required String rolloutId,
    required this.rolloutRevision,
    required String windowId,
    required DateTime windowStart,
    required DateTime windowEnd,
    required DateTime lateCutoff,
    required this.observationSchemaVersion,
    required this.aggregationVersion,
  }) : organizationId = _aggregateId(organizationId, 'organization ID'),
       applicationId = _aggregateId(applicationId, 'application ID'),
       environmentId = _aggregateId(environmentId, 'environment ID'),
       platformId = _aggregateId(platformId, 'platform ID'),
       releaseId = _aggregateId(releaseId, 'release ID'),
       patchId = _aggregateId(patchId, 'patch ID'),
       rolloutId = _aggregateId(rolloutId, 'rollout ID'),
       windowId = _aggregateId(windowId, 'window ID'),
       windowStart = windowStart.toUtc(),
       windowEnd = windowEnd.toUtc(),
       lateCutoff = lateCutoff.toUtc() {
    if (sequence <= 0) {
      throw const FormatException('Aggregate sequence must be positive');
    }
    if (rolloutRevision <= 0) {
      throw const FormatException(
        'Aggregate rollout revision must be positive',
      );
    }
    if (observationSchemaVersion != supportedObservationSchemaVersion) {
      throw const FormatException('Unsupported observation schema version');
    }
    if (aggregationVersion != supportedAggregationVersion) {
      throw const FormatException('Unsupported aggregation version');
    }
    if (windowStart.isAfter(windowEnd) || lateCutoff.isBefore(windowEnd)) {
      throw const FormatException(
        'Aggregate identity window times are invalid',
      );
    }
  }

  final String organizationId;
  final String applicationId;
  final String environmentId;
  final String platformId;
  final String releaseId;
  final String patchId;
  final int sequence;
  final String rolloutId;
  final int rolloutRevision;
  final String windowId;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime lateCutoff;
  final int observationSchemaVersion;
  final int aggregationVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'platformId': platformId,
    'releaseId': releaseId,
    'patchId': patchId,
    'sequence': sequence,
    'rolloutId': rolloutId,
    'rolloutRevision': rolloutRevision,
    'windowId': windowId,
    'windowStart': windowStart.toUtc().toIso8601String(),
    'windowEnd': windowEnd.toUtc().toIso8601String(),
    'lateCutoff': lateCutoff.toUtc().toIso8601String(),
    'observationSchemaVersion': observationSchemaVersion,
    'aggregationVersion': aggregationVersion,
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static AggregateIdentity fromJson(Object? value) =>
      _aggregateIdentityFromJson(value);

  @override
  bool operator ==(Object other) =>
      other is AggregateIdentity &&
      canonicalSerialization == other.canonicalSerialization;

  @override
  int get hashCode => canonicalSerialization.hashCode;
}

/// An immutable server-clock window. `phaseAt` is pure and takes its server
/// reference explicitly; no device/client timestamp can change it.
final class ObservationWindow {
  ObservationWindow({
    required String windowId,
    required DateTime serverStart,
    required DateTime serverEnd,
    required DateTime lateCutoff,
    required this.minimumDuration,
    required this.maximumDuration,
    required this.windowPolicyVersion,
  }) : windowId = _aggregateId(windowId, 'window ID'),
       serverStart = serverStart.toUtc(),
       serverEnd = serverEnd.toUtc(),
       lateCutoff = lateCutoff.toUtc() {
    if (windowPolicyVersion != supportedWindowPolicyVersion) {
      throw const FormatException('Unsupported window policy version');
    }
    if (minimumDuration <= Duration.zero || maximumDuration <= Duration.zero) {
      throw const FormatException('Window duration bounds must be positive');
    }
    if (maximumDuration < minimumDuration) {
      throw const FormatException('Window maximum duration is below minimum');
    }
    if (!serverEnd.isAfter(serverStart)) {
      throw const FormatException('Window end must be after start');
    }
    if (lateCutoff.isBefore(serverEnd)) {
      throw const FormatException('Window late cutoff must not precede end');
    }
    final duration = serverEnd.difference(serverStart);
    if (duration < minimumDuration || duration > maximumDuration) {
      throw const FormatException('Window duration is outside policy bounds');
    }
  }

  final String windowId;
  final DateTime serverStart;
  final DateTime serverEnd;
  final DateTime lateCutoff;
  final Duration minimumDuration;
  final Duration maximumDuration;
  final int windowPolicyVersion;

  AggregationWindowPhase phaseAt(DateTime serverNow) {
    final now = serverNow.toUtc();
    if (now.isBefore(serverEnd)) return AggregationWindowPhase.open;
    if (now.isBefore(lateCutoff)) return AggregationWindowPhase.closed;
    return AggregationWindowPhase.sealed;
  }

  AggregationRecordPlacement placementAt(DateTime receivedAt) {
    final receipt = receivedAt.toUtc();
    if (receipt.isBefore(serverStart) || receipt.isAfter(lateCutoff)) {
      return AggregationRecordPlacement.outside;
    }
    if (receipt.isBefore(serverEnd)) {
      return AggregationRecordPlacement.primary;
    }
    return AggregationRecordPlacement.late;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'windowId': windowId,
    'serverStart': serverStart.toUtc().toIso8601String(),
    'serverEnd': serverEnd.toUtc().toIso8601String(),
    'lateCutoff': lateCutoff.toUtc().toIso8601String(),
    'minimumDurationMicros': minimumDuration.inMicroseconds,
    'maximumDurationMicros': maximumDuration.inMicroseconds,
    'windowPolicyVersion': windowPolicyVersion,
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static ObservationWindow fromJson(Object? value) =>
      _observationWindowFromJson(value);
}

final class AggregationMinimumSamples {
  const AggregationMinimumSamples({
    required this.minimumEligibleObserved,
    required this.minimumOffers,
    required this.minimumActivated,
    required this.minimumHealthyConfirmations,
    required this.minimumCoverageBasisPoints,
  });

  final int minimumEligibleObserved;
  final int minimumOffers;
  final int minimumActivated;
  final int minimumHealthyConfirmations;
  final int minimumCoverageBasisPoints;

  void validate() {
    if (minimumEligibleObserved < 0 ||
        minimumOffers < 0 ||
        minimumActivated < 0 ||
        minimumHealthyConfirmations < 0 ||
        minimumCoverageBasisPoints < 0 ||
        minimumCoverageBasisPoints > 10000) {
      throw const FormatException('Minimum sample policy is invalid');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'minimumEligibleObserved': minimumEligibleObserved,
    'minimumOffers': minimumOffers,
    'minimumActivated': minimumActivated,
    'minimumHealthyConfirmations': minimumHealthyConfirmations,
    'minimumCoverageBasisPoints': minimumCoverageBasisPoints,
  };
}

final class AggregationLimits {
  const AggregationLimits({
    required this.maximumRecords,
    required this.maximumCanonicalBytes,
    required this.maximumQuarantineReasonCardinality,
    required this.maximumDiagnosticCodeCardinality,
  });

  final int maximumRecords;
  final int maximumCanonicalBytes;
  final int maximumQuarantineReasonCardinality;
  final int maximumDiagnosticCodeCardinality;

  void validate() {
    if (maximumRecords <= 0 ||
        maximumCanonicalBytes <= 0 ||
        maximumQuarantineReasonCardinality <= 0 ||
        maximumDiagnosticCodeCardinality <= 0) {
      throw const FormatException('Aggregation resource limits are invalid');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'maximumRecords': maximumRecords,
    'maximumCanonicalBytes': maximumCanonicalBytes,
    'maximumQuarantineReasonCardinality': maximumQuarantineReasonCardinality,
    'maximumDiagnosticCodeCardinality': maximumDiagnosticCodeCardinality,
  };
}

final class MetricDenominatorPolicy {
  const MetricDenominatorPolicy({
    required this.runtimeFaults,
    required this.rollbackFallback,
    required this.restartSurvival,
  });

  final MetricDenominatorSource runtimeFaults;
  final MetricDenominatorSource rollbackFallback;
  final MetricDenominatorSource restartSurvival;

  Map<String, Object?> toJson() => <String, Object?>{
    'runtimeFaults': runtimeFaults.wireName,
    'rollbackFallback': rollbackFallback.wireName,
    'restartSurvival': restartSurvival.wireName,
  };
}

/// Policy is intentionally fully supplied by the caller. No production
/// threshold, privacy minimum, freshness age, or window value is selected here.
final class AggregationPolicy {
  AggregationPolicy({
    required this.version,
    required this.minimumSamples,
    required this.smallCohortMinimum,
    required this.materialQuarantineMinimum,
    required this.limits,
    required this.denominatorPolicy,
    Iterable<ObservationEventType> expectedEventTypes =
        const <ObservationEventType>{},
    this.expectedEligibleInstallations,
    DateTime? freshnessReference,
    this.freshnessMaximumAge,
  }) : expectedEventTypes = Set.unmodifiable(expectedEventTypes.toSet()),
       freshnessReference = freshnessReference?.toUtc() {
    validate();
  }

  final int version;
  final AggregationMinimumSamples minimumSamples;
  final int smallCohortMinimum;
  final int materialQuarantineMinimum;
  final AggregationLimits limits;
  final MetricDenominatorPolicy denominatorPolicy;
  final Set<ObservationEventType> expectedEventTypes;
  final int? expectedEligibleInstallations;
  final DateTime? freshnessReference;
  final Duration? freshnessMaximumAge;

  void validate() {
    if (version != supportedAggregationPolicyVersion) {
      throw const FormatException('Unsupported aggregation policy version');
    }
    minimumSamples.validate();
    limits.validate();
    if (smallCohortMinimum < 0 || materialQuarantineMinimum < 0) {
      throw const FormatException('Aggregation privacy policy is invalid');
    }
    if (expectedEligibleInstallations != null &&
        expectedEligibleInstallations! <= 0) {
      throw const FormatException(
        'Expected eligible installations are invalid',
      );
    }
    if ((freshnessReference == null) != (freshnessMaximumAge == null)) {
      throw const FormatException('Freshness reference and age are paired');
    }
    if (freshnessMaximumAge != null && freshnessMaximumAge! <= Duration.zero) {
      throw const FormatException('Freshness maximum age must be positive');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'minimumSamples': minimumSamples.toJson(),
    'smallCohortMinimum': smallCohortMinimum,
    'materialQuarantineMinimum': materialQuarantineMinimum,
    'limits': limits.toJson(),
    'denominatorPolicy': denominatorPolicy.toJson(),
    'expectedEventTypes':
        expectedEventTypes.map((type) => type.wireName).toList(growable: false)
          ..sort(),
    'expectedEligibleInstallations': expectedEligibleInstallations,
    'freshnessReference': freshnessReference?.toIso8601String(),
    'freshnessMaximumAgeMicros': freshnessMaximumAge?.inMicroseconds,
  };
}

/// Counts supplied externally by bounded P3D rejection/security evidence. These
/// values never enter a health numerator or denominator.
final class AggregationExternalQuality {
  const AggregationExternalQuality({
    this.rejected = 0,
    this.securityRejected = 0,
    this.observationOutage = false,
  });

  final int rejected;
  final int securityRejected;
  final bool observationOutage;

  void validate() {
    if (rejected < 0 || securityRejected < 0) {
      throw const FormatException('External quality counters are invalid');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'rejected': rejected,
    'securityRejected': securityRejected,
    'observationOutage': observationOutage,
  };
}

final class AggregateCounters {
  const AggregateCounters({
    required this.eligibleInstallationsObserved,
    required this.lookupAttempts,
    required this.candidateOffers,
    required this.downloadSucceeded,
    required this.downloadFailed,
    required this.admissionVerified,
    required this.admissionRejected,
    required this.activationStarted,
    required this.activationSucceeded,
    required this.activationFailed,
    required this.healthyConfirmed,
    required this.runtimeFaults,
    required this.rollbacks,
    required this.fallbacksToAot,
    required this.restartSurvived,
    required this.staleOrReplayRejects,
    required this.lateEvents,
    required this.quarantinedEvents,
    required this.missingExpectedEvents,
  });

  final int eligibleInstallationsObserved;
  final int lookupAttempts;
  final int candidateOffers;
  final int downloadSucceeded;
  final int downloadFailed;
  final int admissionVerified;
  final int admissionRejected;
  final int activationStarted;
  final int activationSucceeded;
  final int activationFailed;
  final int healthyConfirmed;
  final int runtimeFaults;
  final int rollbacks;
  final int fallbacksToAot;
  final int restartSurvived;
  final int staleOrReplayRejects;
  final int lateEvents;
  final int quarantinedEvents;
  final int missingExpectedEvents;

  Map<String, Object?> toJson() => <String, Object?>{
    'eligibleInstallationsObserved': eligibleInstallationsObserved,
    'lookupAttempts': lookupAttempts,
    'candidateOffers': candidateOffers,
    'downloadSucceeded': downloadSucceeded,
    'downloadFailed': downloadFailed,
    'admissionVerified': admissionVerified,
    'admissionRejected': admissionRejected,
    'activationStarted': activationStarted,
    'activationSucceeded': activationSucceeded,
    'activationFailed': activationFailed,
    'healthyConfirmed': healthyConfirmed,
    'runtimeFaults': runtimeFaults,
    'rollbacks': rollbacks,
    'fallbacksToAot': fallbacksToAot,
    'restartSurvived': restartSurvived,
    'staleOrReplayRejects': staleOrReplayRejects,
    'lateEvents': lateEvents,
    'quarantinedEvents': quarantinedEvents,
    'missingExpectedEvents': missingExpectedEvents,
  };
}

final class AggregateQualityCounters {
  const AggregateQualityCounters({
    required this.accepted,
    required this.duplicate,
    required this.duplicateMutations,
    required this.excessContributions,
    required this.late,
    required this.quarantined,
    required this.rejected,
    required this.securityRejected,
    required this.identityMismatch,
    required this.scopeMismatch,
    required this.impossibleSequence,
    required this.clockInvalid,
    required this.schemaUnsupported,
    required this.securitySuspicion,
    required this.otherQuarantine,
    required this.outOfWindow,
  });

  final int accepted;
  final int duplicate;
  final int duplicateMutations;
  final int excessContributions;
  final int late;
  final int quarantined;
  final int rejected;
  final int securityRejected;
  final int identityMismatch;
  final int scopeMismatch;
  final int impossibleSequence;
  final int clockInvalid;
  final int schemaUnsupported;
  final int securitySuspicion;
  final int otherQuarantine;
  final int outOfWindow;

  Map<String, Object?> toJson() => <String, Object?>{
    'accepted': accepted,
    'duplicate': duplicate,
    'duplicateMutations': duplicateMutations,
    'excessContributions': excessContributions,
    'late': late,
    'quarantined': quarantined,
    'rejected': rejected,
    'securityRejected': securityRejected,
    'identityMismatch': identityMismatch,
    'scopeMismatch': scopeMismatch,
    'impossibleSequence': impossibleSequence,
    'clockInvalid': clockInvalid,
    'schemaUnsupported': schemaUnsupported,
    'securitySuspicion': securitySuspicion,
    'otherQuarantine': otherQuarantine,
    'outOfWindow': outOfWindow,
  };
}

final class AggregateMetric {
  const AggregateMetric.evaluable({
    required this.numerator,
    required this.denominator,
  }) : status = AggregateMetricStatus.evaluable,
       notEvaluableReason = null;

  const AggregateMetric.notEvaluable({required this.notEvaluableReason})
    : numerator = 0,
      denominator = 0,
      status = AggregateMetricStatus.notEvaluable;

  final int numerator;
  final int denominator;
  final AggregateMetricStatus status;
  final String? notEvaluableReason;

  Map<String, Object?> toJson() => <String, Object?>{
    'numerator': numerator,
    'denominator': denominator,
    'status': status.wireName,
    'notEvaluableReason': notEvaluableReason,
  };
}

final class AggregateCoverage {
  const AggregateCoverage({
    required this.observedInstallations,
    required this.expectedInstallations,
    required this.observedBasisPoints,
    required this.minimumBasisPoints,
    required this.state,
  });

  final int observedInstallations;
  final int? expectedInstallations;
  final int? observedBasisPoints;
  final int minimumBasisPoints;
  final AggregateCoverageState state;

  Map<String, Object?> toJson() => <String, Object?>{
    'observedInstallations': observedInstallations,
    'expectedInstallations': expectedInstallations,
    'observedBasisPoints': observedBasisPoints,
    'minimumBasisPoints': minimumBasisPoints,
    'state': state.wireName,
  };
}

final class AggregateSampleCheck {
  const AggregateSampleCheck({
    required this.observed,
    required this.required,
    required this.passed,
  });

  final int observed;
  final int required;
  final bool passed;

  Map<String, Object?> toJson() => <String, Object?>{
    'observed': observed,
    'required': required,
    'passed': passed,
  };
}

final class AggregateSampleStatus {
  const AggregateSampleStatus({
    required this.eligible,
    required this.offers,
    required this.activated,
    required this.healthy,
    required this.coveragePassed,
    required this.allPassed,
  });

  final AggregateSampleCheck eligible;
  final AggregateSampleCheck offers;
  final AggregateSampleCheck activated;
  final AggregateSampleCheck healthy;
  final bool coveragePassed;
  final bool allPassed;

  Map<String, Object?> toJson() => <String, Object?>{
    'eligible': eligible.toJson(),
    'offers': offers.toJson(),
    'activated': activated.toJson(),
    'healthy': healthy.toJson(),
    'coveragePassed': coveragePassed,
    'allPassed': allPassed,
  };
}

/// Immutable aggregate output. It contains no installation bucket values.
final class HealthAggregate {
  HealthAggregate({
    required this.identity,
    required this.window,
    required this.inputCount,
    required this.acceptedInputCount,
    required this.inputDigest,
    required this.policyVersion,
    required this.policyDigest,
    required this.externalQualityDigest,
    required this.counters,
    required this.quality,
    required Map<AggregateMetricName, AggregateMetric> metrics,
    required this.coverage,
    required this.samples,
    required this.privacyState,
    required this.freshnessState,
    required Iterable<AggregateMissingDataReason> missingData,
    required this.latestPrimaryReceivedAt,
  }) : metrics = Map.unmodifiable(metrics),
       missingData = List.unmodifiable(
         missingData.toList()..sort(_compareMissing),
       ) {
    if (inputCount < 0 ||
        acceptedInputCount < 0 ||
        acceptedInputCount > inputCount) {
      throw const FormatException('Aggregate input counts are invalid');
    }
    if (inputDigest.isEmpty) {
      throw const FormatException('Aggregate input digest is required');
    }
    requireSha256Digest(inputDigest);
    requireSha256Digest(policyDigest);
    requireSha256Digest(externalQualityDigest);
    if (policyVersion != supportedAggregationPolicyVersion) {
      throw const FormatException('Unsupported aggregate policy version');
    }
  }

  final AggregateIdentity identity;
  final ObservationWindow window;
  final int inputCount;
  final int acceptedInputCount;
  final String inputDigest;
  final int policyVersion;
  final String policyDigest;
  final String externalQualityDigest;
  final AggregateCounters counters;
  final AggregateQualityCounters quality;
  final Map<AggregateMetricName, AggregateMetric> metrics;
  final AggregateCoverage coverage;
  final AggregateSampleStatus samples;
  final AggregatePrivacyState privacyState;
  final AggregateFreshnessState freshnessState;
  final List<AggregateMissingDataReason> missingData;
  final DateTime? latestPrimaryReceivedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'identity': identity.toJson(),
    'window': window.toJson(),
    'inputCount': inputCount,
    'acceptedInputCount': acceptedInputCount,
    'inputDigest': inputDigest,
    'policyVersion': policyVersion,
    'policyDigest': policyDigest,
    'externalQualityDigest': externalQualityDigest,
    'counters': counters.toJson(),
    'quality': quality.toJson(),
    'metrics': <String, Object?>{
      for (final entry in metrics.entries)
        entry.key.wireName: entry.value.toJson(),
    },
    'coverage': coverage.toJson(),
    'samples': samples.toJson(),
    'privacyState': privacyState.wireName,
    'freshnessState': freshnessState.wireName,
    'missingData': missingData.map((reason) => reason.wireName).toList(),
    'latestPrimaryReceivedAt': latestPrimaryReceivedAt
        ?.toUtc()
        .toIso8601String(),
  };

  /// Decodes only the exact canonical aggregate shape emitted by [toJson].
  ///
  /// Persistence adapters use this boundary to reject unknown versions,
  /// enums, fields, and malformed metric pairs before evidence can be used by
  /// a future evaluator. It intentionally does not perform any rollout or
  /// runtime action.
  static HealthAggregate fromJson(Object? value) {
    final map = _aggregateObject(value, 'health aggregate');
    _aggregateExactKeys(map, const {
      'identity',
      'window',
      'inputCount',
      'acceptedInputCount',
      'inputDigest',
      'policyVersion',
      'policyDigest',
      'externalQualityDigest',
      'counters',
      'quality',
      'metrics',
      'coverage',
      'samples',
      'privacyState',
      'freshnessState',
      'missingData',
      'latestPrimaryReceivedAt',
    }, 'health aggregate');
    final latest = map['latestPrimaryReceivedAt'];
    final policyVersion = _aggregatePositiveInt(
      map['policyVersion'],
      'policy version',
    );
    if (policyVersion != supportedAggregationPolicyVersion) {
      throw const FormatException('Unsupported aggregate policy version');
    }
    return HealthAggregate(
      identity: _aggregateIdentityFromJson(map['identity']),
      window: _observationWindowFromJson(map['window']),
      inputCount: _aggregateInt(map['inputCount'], 'input count'),
      acceptedInputCount: _aggregateInt(
        map['acceptedInputCount'],
        'accepted input count',
      ),
      inputDigest: requireSha256Digest(
        _aggregateString(map['inputDigest'], 'input digest'),
      ),
      policyVersion: policyVersion,
      policyDigest: requireSha256Digest(
        _aggregateString(map['policyDigest'], 'policy digest'),
      ),
      externalQualityDigest: requireSha256Digest(
        _aggregateString(
          map['externalQualityDigest'],
          'external-quality digest',
        ),
      ),
      counters: _aggregateCountersFromJson(map['counters']),
      quality: _aggregateQualityFromJson(map['quality']),
      metrics: _aggregateMetricsFromJson(map['metrics']),
      coverage: _aggregateCoverageFromJson(map['coverage']),
      samples: _aggregateSamplesFromJson(map['samples']),
      privacyState: _aggregatePrivacyState(map['privacyState']),
      freshnessState: _aggregateFreshnessState(map['freshnessState']),
      missingData: _aggregateMissingData(map['missingData']),
      latestPrimaryReceivedAt: latest == null
          ? null
          : _aggregateTimestamp(latest, 'latest primary receipt'),
    );
  }

  String get canonicalSerialization => canonicalJson(toJson());

  @override
  bool operator ==(Object other) =>
      other is HealthAggregate &&
      canonicalSerialization == other.canonicalSerialization;

  @override
  int get hashCode => canonicalSerialization.hashCode;
}

Map<String, Object?> _aggregateObject(Object? value, String label) {
  if (value is! Map) throw FormatException('Invalid $label object');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('Invalid $label key');
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _aggregateExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String label,
) {
  if (value.length != expected.length ||
      value.keys.any((key) => !expected.contains(key))) {
    throw FormatException('Invalid $label fields');
  }
}

String _aggregateString(Object? value, String label) {
  if (value is! String || value.isEmpty) {
    throw FormatException('Invalid $label');
  }
  return value;
}

int _aggregateInt(Object? value, String label) {
  if (value is! int || value < 0) throw FormatException('Invalid $label');
  return value;
}

bool _aggregateBool(Object? value, String label) {
  if (value is! bool) throw FormatException('Invalid $label');
  return value;
}

DateTime _aggregateTimestamp(Object? value, String label) {
  final text = _aggregateString(value, label);
  try {
    return DateTime.parse(text).toUtc();
  } on FormatException {
    throw FormatException('Invalid $label');
  }
}

AggregateIdentity _aggregateIdentityFromJson(Object? value) {
  final map = _aggregateObject(value, 'aggregate identity');
  _aggregateExactKeys(map, const {
    'organizationId',
    'applicationId',
    'environmentId',
    'platformId',
    'releaseId',
    'patchId',
    'sequence',
    'rolloutId',
    'rolloutRevision',
    'windowId',
    'windowStart',
    'windowEnd',
    'lateCutoff',
    'observationSchemaVersion',
    'aggregationVersion',
  }, 'aggregate identity');
  return AggregateIdentity(
    organizationId: _aggregateString(map['organizationId'], 'organization ID'),
    applicationId: _aggregateString(map['applicationId'], 'application ID'),
    environmentId: _aggregateString(map['environmentId'], 'environment ID'),
    platformId: _aggregateString(map['platformId'], 'platform ID'),
    releaseId: _aggregateString(map['releaseId'], 'release ID'),
    patchId: _aggregateString(map['patchId'], 'patch ID'),
    sequence: _aggregatePositiveInt(map['sequence'], 'sequence'),
    rolloutId: _aggregateString(map['rolloutId'], 'rollout ID'),
    rolloutRevision: _aggregatePositiveInt(
      map['rolloutRevision'],
      'rollout revision',
    ),
    windowId: _aggregateString(map['windowId'], 'window ID'),
    windowStart: _aggregateTimestamp(map['windowStart'], 'window start'),
    windowEnd: _aggregateTimestamp(map['windowEnd'], 'window end'),
    lateCutoff: _aggregateTimestamp(map['lateCutoff'], 'late cutoff'),
    observationSchemaVersion: _aggregatePositiveInt(
      map['observationSchemaVersion'],
      'observation schema version',
    ),
    aggregationVersion: _aggregatePositiveInt(
      map['aggregationVersion'],
      'aggregation version',
    ),
  );
}

int _aggregatePositiveInt(Object? value, String label) {
  final parsed = _aggregateInt(value, label);
  if (parsed <= 0) throw FormatException('Invalid $label');
  return parsed;
}

ObservationWindow _observationWindowFromJson(Object? value) {
  final map = _aggregateObject(value, 'observation window');
  _aggregateExactKeys(map, const {
    'windowId',
    'serverStart',
    'serverEnd',
    'lateCutoff',
    'minimumDurationMicros',
    'maximumDurationMicros',
    'windowPolicyVersion',
  }, 'observation window');
  return ObservationWindow(
    windowId: _aggregateString(map['windowId'], 'window ID'),
    serverStart: _aggregateTimestamp(map['serverStart'], 'server start'),
    serverEnd: _aggregateTimestamp(map['serverEnd'], 'server end'),
    lateCutoff: _aggregateTimestamp(map['lateCutoff'], 'late cutoff'),
    minimumDuration: Duration(
      microseconds: _aggregatePositiveInt(
        map['minimumDurationMicros'],
        'minimum duration',
      ),
    ),
    maximumDuration: Duration(
      microseconds: _aggregatePositiveInt(
        map['maximumDurationMicros'],
        'maximum duration',
      ),
    ),
    windowPolicyVersion: _aggregatePositiveInt(
      map['windowPolicyVersion'],
      'window policy version',
    ),
  );
}

AggregateCounters _aggregateCountersFromJson(Object? value) {
  final map = _aggregateObject(value, 'aggregate counters');
  const keys = {
    'eligibleInstallationsObserved',
    'lookupAttempts',
    'candidateOffers',
    'downloadSucceeded',
    'downloadFailed',
    'admissionVerified',
    'admissionRejected',
    'activationStarted',
    'activationSucceeded',
    'activationFailed',
    'healthyConfirmed',
    'runtimeFaults',
    'rollbacks',
    'fallbacksToAot',
    'restartSurvived',
    'staleOrReplayRejects',
    'lateEvents',
    'quarantinedEvents',
    'missingExpectedEvents',
  };
  _aggregateExactKeys(map, keys, 'aggregate counters');
  int get(String key) => _aggregateInt(map[key], key);
  return AggregateCounters(
    eligibleInstallationsObserved: get('eligibleInstallationsObserved'),
    lookupAttempts: get('lookupAttempts'),
    candidateOffers: get('candidateOffers'),
    downloadSucceeded: get('downloadSucceeded'),
    downloadFailed: get('downloadFailed'),
    admissionVerified: get('admissionVerified'),
    admissionRejected: get('admissionRejected'),
    activationStarted: get('activationStarted'),
    activationSucceeded: get('activationSucceeded'),
    activationFailed: get('activationFailed'),
    healthyConfirmed: get('healthyConfirmed'),
    runtimeFaults: get('runtimeFaults'),
    rollbacks: get('rollbacks'),
    fallbacksToAot: get('fallbacksToAot'),
    restartSurvived: get('restartSurvived'),
    staleOrReplayRejects: get('staleOrReplayRejects'),
    lateEvents: get('lateEvents'),
    quarantinedEvents: get('quarantinedEvents'),
    missingExpectedEvents: get('missingExpectedEvents'),
  );
}

AggregateQualityCounters _aggregateQualityFromJson(Object? value) {
  final map = _aggregateObject(value, 'aggregate quality');
  const keys = {
    'accepted',
    'duplicate',
    'duplicateMutations',
    'excessContributions',
    'late',
    'quarantined',
    'rejected',
    'securityRejected',
    'identityMismatch',
    'scopeMismatch',
    'impossibleSequence',
    'clockInvalid',
    'schemaUnsupported',
    'securitySuspicion',
    'otherQuarantine',
    'outOfWindow',
  };
  _aggregateExactKeys(map, keys, 'aggregate quality');
  int get(String key) => _aggregateInt(map[key], key);
  return AggregateQualityCounters(
    accepted: get('accepted'),
    duplicate: get('duplicate'),
    duplicateMutations: get('duplicateMutations'),
    excessContributions: get('excessContributions'),
    late: get('late'),
    quarantined: get('quarantined'),
    rejected: get('rejected'),
    securityRejected: get('securityRejected'),
    identityMismatch: get('identityMismatch'),
    scopeMismatch: get('scopeMismatch'),
    impossibleSequence: get('impossibleSequence'),
    clockInvalid: get('clockInvalid'),
    schemaUnsupported: get('schemaUnsupported'),
    securitySuspicion: get('securitySuspicion'),
    otherQuarantine: get('otherQuarantine'),
    outOfWindow: get('outOfWindow'),
  );
}

Map<AggregateMetricName, AggregateMetric> _aggregateMetricsFromJson(
  Object? value,
) {
  final map = _aggregateObject(value, 'aggregate metrics');
  final expected = AggregateMetricName.values
      .map((name) => name.wireName)
      .toSet();
  _aggregateExactKeys(map, expected, 'aggregate metrics');
  return <AggregateMetricName, AggregateMetric>{
    for (final name in AggregateMetricName.values)
      name: _aggregateMetricFromJson(map[name.wireName]),
  };
}

AggregateMetric _aggregateMetricFromJson(Object? value) {
  final map = _aggregateObject(value, 'aggregate metric');
  _aggregateExactKeys(map, const {
    'numerator',
    'denominator',
    'status',
    'notEvaluableReason',
  }, 'aggregate metric');
  final numerator = _aggregateInt(map['numerator'], 'metric numerator');
  final denominator = _aggregateInt(map['denominator'], 'metric denominator');
  final status = map['status'];
  if (status == AggregateMetricStatus.evaluable.wireName) {
    if (map['notEvaluableReason'] != null) {
      throw const FormatException('Evaluable metric has a reason');
    }
    return AggregateMetric.evaluable(
      numerator: numerator,
      denominator: denominator,
    );
  }
  if (status == AggregateMetricStatus.notEvaluable.wireName &&
      numerator == 0 &&
      denominator == 0) {
    return AggregateMetric.notEvaluable(
      notEvaluableReason: _aggregateString(
        map['notEvaluableReason'],
        'not-evaluable reason',
      ),
    );
  }
  throw const FormatException('Invalid aggregate metric status');
}

AggregateCoverage _aggregateCoverageFromJson(Object? value) {
  final map = _aggregateObject(value, 'aggregate coverage');
  _aggregateExactKeys(map, const {
    'observedInstallations',
    'expectedInstallations',
    'observedBasisPoints',
    'minimumBasisPoints',
    'state',
  }, 'aggregate coverage');
  final expected = map['expectedInstallations'];
  final observedBasis = map['observedBasisPoints'];
  return AggregateCoverage(
    observedInstallations: _aggregateInt(
      map['observedInstallations'],
      'observed installations',
    ),
    expectedInstallations: expected == null
        ? null
        : _aggregatePositiveInt(expected, 'expected installations'),
    observedBasisPoints: observedBasis == null
        ? null
        : _aggregateInt(observedBasis, 'observed basis points'),
    minimumBasisPoints: _aggregateInt(
      map['minimumBasisPoints'],
      'minimum basis points',
    ),
    state: _aggregateCoverageState(map['state']),
  );
}

AggregateCoverageState _aggregateCoverageState(Object? value) =>
    switch (value) {
      'SUFFICIENT' => AggregateCoverageState.sufficient,
      'INSUFFICIENT' => AggregateCoverageState.insufficient,
      'NOT_EVALUABLE' => AggregateCoverageState.notEvaluable,
      _ => throw const FormatException('Unsupported aggregate coverage state'),
    };

AggregateSampleStatus _aggregateSamplesFromJson(Object? value) {
  final map = _aggregateObject(value, 'aggregate samples');
  _aggregateExactKeys(map, const {
    'eligible',
    'offers',
    'activated',
    'healthy',
    'coveragePassed',
    'allPassed',
  }, 'aggregate samples');
  return AggregateSampleStatus(
    eligible: _aggregateSampleCheck(map['eligible']),
    offers: _aggregateSampleCheck(map['offers']),
    activated: _aggregateSampleCheck(map['activated']),
    healthy: _aggregateSampleCheck(map['healthy']),
    coveragePassed: _aggregateBool(map['coveragePassed'], 'coverage passed'),
    allPassed: _aggregateBool(map['allPassed'], 'all samples passed'),
  );
}

AggregateSampleCheck _aggregateSampleCheck(Object? value) {
  final map = _aggregateObject(value, 'aggregate sample check');
  _aggregateExactKeys(map, const {'observed', 'required', 'passed'}, 'sample');
  return AggregateSampleCheck(
    observed: _aggregateInt(map['observed'], 'sample observed'),
    required: _aggregateInt(map['required'], 'sample required'),
    passed: _aggregateBool(map['passed'], 'sample passed'),
  );
}

AggregatePrivacyState _aggregatePrivacyState(Object? value) => switch (value) {
  'NORMAL' => AggregatePrivacyState.normal,
  'SMALL_COHORT_SUPPRESSED' => AggregatePrivacyState.smallCohortSuppressed,
  'INSUFFICIENT_DATA' => AggregatePrivacyState.insufficientData,
  _ => throw const FormatException('Unsupported aggregate privacy state'),
};

AggregateFreshnessState _aggregateFreshnessState(Object? value) =>
    switch (value) {
      'FRESH' => AggregateFreshnessState.fresh,
      'STALE' => AggregateFreshnessState.stale,
      'UNKNOWN' => AggregateFreshnessState.unknown,
      _ => throw const FormatException('Unsupported aggregate freshness state'),
    };

List<AggregateMissingDataReason> _aggregateMissingData(Object? value) {
  if (value is! List)
    throw const FormatException('Invalid aggregate missing data');
  return value
      .map(
        (item) => switch (item) {
          'NO_EVIDENCE' => AggregateMissingDataReason.noEvidence,
          'INCOMPLETE_LIFECYCLE' =>
            AggregateMissingDataReason.incompleteLifecycle,
          'STALE_EVIDENCE' => AggregateMissingDataReason.staleEvidence,
          'OBSERVATION_OUTAGE' => AggregateMissingDataReason.observationOutage,
          'MATERIAL_QUARANTINE' =>
            AggregateMissingDataReason.materialQuarantine,
          'MISSING_RESTART_EVIDENCE' =>
            AggregateMissingDataReason.missingRestartEvidence,
          _ => throw const FormatException('Unsupported missing-data reason'),
        },
      )
      .toList(growable: false);
}

/// Pure P3E-1 aggregation core. It never mutates rollout state and has no
/// persistence, HTTP, scheduler, or runtime-trust dependency.
final class DeterministicAggregator {
  const DeterministicAggregator();

  HealthAggregate aggregate({
    required AggregateIdentity identity,
    required ObservationWindow window,
    required AggregationPolicy policy,
    required Iterable<ObservationRecord> records,
    AggregationExternalQuality externalQuality =
        const AggregationExternalQuality(),
  }) {
    policy.validate();
    externalQuality.validate();
    if (identity.windowId != window.windowId ||
        identity.windowStart != window.serverStart ||
        identity.windowEnd != window.serverEnd ||
        identity.lateCutoff != window.lateCutoff ||
        identity.observationSchemaVersion != observationSchemaVersion) {
      throw const FormatException('Aggregate identity and window do not match');
    }
    final envelopes = <_RecordEnvelope>[];
    var canonicalBytes = 2;
    var count = 0;
    final diagnosticCodes = <String>{};
    for (final record in records) {
      count++;
      if (count > policy.limits.maximumRecords) {
        throw const FormatException('Aggregation input exceeds record limit');
      }
      _validateEventScope(record.event, identity);
      final eventBody = canonicalJson(record.event.toJson());
      final recordBody = canonicalJson(record.toJson());
      canonicalBytes += utf8.encode(recordBody).length + 1;
      if (canonicalBytes > policy.limits.maximumCanonicalBytes) {
        throw const FormatException('Aggregation input exceeds byte limit');
      }
      final code = record.event.diagnosticCode;
      if (code != null) diagnosticCodes.add(code);
      envelopes.add(
        _RecordEnvelope(
          record: record,
          eventBody: eventBody,
          recordBody: recordBody,
        ),
      );
    }
    if (diagnosticCodes.length >
        policy.limits.maximumDiagnosticCodeCardinality) {
      throw const FormatException(
        'Aggregation diagnostic-code cardinality exceeds limit',
      );
    }
    envelopes.sort(_compareEnvelopes);

    final uniqueById = <String, _RecordEnvelope>{};
    final taintedIds = <String>{};
    var duplicateCount = 0;
    var duplicateMutations = 0;
    for (final envelope in envelopes) {
      final eventId = envelope.record.event.eventId;
      final previous = uniqueById[eventId];
      if (previous == null) {
        uniqueById[eventId] = envelope;
      } else if (previous.eventBody == envelope.eventBody) {
        duplicateCount++;
      } else {
        taintedIds.add(eventId);
        duplicateMutations++;
      }
    }
    final unique =
        uniqueById.entries
            .where((entry) => !taintedIds.contains(entry.key))
            .map((entry) => entry.value)
            .toList()
          ..sort(_compareEnvelopes);

    final qualityBuilder = _QualityBuilder(
      rejected: externalQuality.rejected,
      securityRejected: externalQuality.securityRejected + duplicateMutations,
      duplicate: duplicateCount,
      duplicateMutations: duplicateMutations,
    );
    final contributionKeys = <String>{};
    final eligibleBuckets = <String>{};
    final observedByBucket = <String, Set<ObservationEventType>>{};
    final countersBuilder = _CounterBuilder()
      ..staleOrReplayRejects = duplicateMutations;
    final primaryRecords = <_RecordEnvelope>[];
    final digestRecords = <_RecordEnvelope>[];
    var acceptedInputCount = 0;
    for (final envelope in unique) {
      final record = envelope.record;
      if (record.disposition == ObservationDisposition.accepted) {
        qualityBuilder.accepted++;
      }
      if (record.disposition == ObservationDisposition.quarantined) {
        if (window.placementAt(record.receivedAt) ==
            AggregationRecordPlacement.primary) {
          digestRecords.add(envelope);
        }
        qualityBuilder.addQuarantine(_quarantineReason(record.event));
        continue;
      }
      final placement = window.placementAt(record.receivedAt);
      if (record.disposition == ObservationDisposition.late ||
          placement == AggregationRecordPlacement.late) {
        qualityBuilder.late++;
        countersBuilder.lateEvents++;
        continue;
      }
      if (placement == AggregationRecordPlacement.outside) {
        qualityBuilder.outOfWindow++;
        countersBuilder.staleOrReplayRejects++;
        continue;
      }
      digestRecords.add(envelope);
      acceptedInputCount++;
      primaryRecords.add(envelope);
    }

    DateTime? latestPrimaryReceipt;
    for (final envelope in primaryRecords) {
      final event = envelope.record.event;
      final key = _contributionKey(event);
      if (!contributionKeys.add(key)) {
        qualityBuilder.excessContributions++;
        continue;
      }
      final type = event.eventType;
      observedByBucket
          .putIfAbsent(event.installationBucket, () => <ObservationEventType>{})
          .add(type);
      if (type == ObservationEventType.lookup_attempt ||
          type == ObservationEventType.candidate_offered) {
        eligibleBuckets.add(event.installationBucket);
      }
      final receipt = envelope.record.receivedAt.toUtc();
      if (latestPrimaryReceipt == null ||
          receipt.isAfter(latestPrimaryReceipt)) {
        latestPrimaryReceipt = receipt;
      }
      countersBuilder.add(type);
    }
    final missingExpectedEvents = _missingExpectedEvents(
      eligibleBuckets,
      observedByBucket,
      policy.expectedEventTypes,
    );
    countersBuilder.missingExpectedEvents = missingExpectedEvents;
    final quality = qualityBuilder.build(
      maximumQuarantineReasonCardinality:
          policy.limits.maximumQuarantineReasonCardinality,
    );
    final counters = countersBuilder.build(
      eligibleInstallationsObserved: eligibleBuckets.length,
      quarantinedEvents: quality.quarantined,
    );
    final inputDigest = sha256Digest(
      utf8.encode(
        canonicalJson(
          digestRecords.map((entry) => entry.record.toJson()).toList(),
        ),
      ),
    );
    final coverage = _coverage(
      observedInstallations: counters.eligibleInstallationsObserved,
      expectedInstallations: policy.expectedEligibleInstallations,
      minimumBasisPoints: policy.minimumSamples.minimumCoverageBasisPoints,
    );
    final samples = _sampleStatus(counters, coverage, policy.minimumSamples);
    final freshness = _freshness(latestPrimaryReceipt, policy);
    final missingData = _missingData(
      acceptedInputCount: acceptedInputCount,
      primaryCount: primaryRecords.length,
      lateCount: quality.late,
      quality: quality,
      missingExpectedEvents: missingExpectedEvents,
      expectedEventTypes: policy.expectedEventTypes,
      freshness: freshness,
      externalQuality: externalQuality,
      materialQuarantineMinimum: policy.materialQuarantineMinimum,
    );
    final privacyState = _privacyState(
      eligibleInstallationsObserved: counters.eligibleInstallationsObserved,
      smallCohortMinimum: policy.smallCohortMinimum,
    );

    return HealthAggregate(
      identity: identity,
      window: window,
      inputCount: digestRecords.length,
      acceptedInputCount: acceptedInputCount,
      inputDigest: inputDigest,
      policyVersion: policy.version,
      policyDigest: sha256Digest(utf8.encode(canonicalJson(policy.toJson()))),
      externalQualityDigest: sha256Digest(
        utf8.encode(canonicalJson(externalQuality.toJson())),
      ),
      counters: counters,
      quality: quality,
      metrics: _metrics(
        counters: counters,
        quality: quality,
        freshness: freshness,
        denominatorPolicy: policy.denominatorPolicy,
      ),
      coverage: coverage,
      samples: samples,
      privacyState: privacyState,
      freshnessState: freshness,
      missingData: missingData,
      latestPrimaryReceivedAt: latestPrimaryReceipt,
    );
  }
}

final class _RecordEnvelope {
  const _RecordEnvelope({
    required this.record,
    required this.eventBody,
    required this.recordBody,
  });

  final ObservationRecord record;
  final String eventBody;
  final String recordBody;
}

int _compareEnvelopes(_RecordEnvelope left, _RecordEnvelope right) {
  final received = left.record.receivedAt.toUtc().compareTo(
    right.record.receivedAt.toUtc(),
  );
  if (received != 0) return received;
  final eventId = left.record.event.eventId.compareTo(
    right.record.event.eventId,
  );
  if (eventId != 0) return eventId;
  return left.eventBody.compareTo(right.eventBody);
}

String _contributionKey(ObservationEvent event) => <String>[
  event.installationBucket,
  event.eventType.wireName,
  event.eventType.wireName,
].join('\u0000');

String _aggregateId(String value, String field) {
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.:-]{0,127}$').hasMatch(value)) {
    throw FormatException('Invalid aggregate $field');
  }
  return value;
}

void _validateEventScope(ObservationEvent event, AggregateIdentity identity) {
  if (event.schemaVersion != identity.observationSchemaVersion ||
      event.organizationId != identity.organizationId ||
      event.applicationId != identity.applicationId ||
      event.environmentId != identity.environmentId ||
      event.platform != identity.platformId ||
      event.releaseId != identity.releaseId ||
      event.patchId != identity.patchId ||
      event.sequence != identity.sequence ||
      event.rolloutId != identity.rolloutId ||
      event.rolloutRevision != identity.rolloutRevision) {
    throw const FormatException(
      'Observation event does not match aggregate scope',
    );
  }
}

enum _QuarantineReason {
  identityMismatch,
  scopeMismatch,
  impossibleSequence,
  clockInvalid,
  schemaUnsupported,
  securitySuspicion,
  otherQuarantine,
}

_QuarantineReason _quarantineReason(ObservationEvent event) {
  final code = event.diagnosticCode ?? '';
  if (code.contains('IDENTITY')) return _QuarantineReason.identityMismatch;
  if (code.contains('SCOPE')) return _QuarantineReason.scopeMismatch;
  if (code.contains('SEQUENCE')) return _QuarantineReason.impossibleSequence;
  if (code.contains('CLOCK')) return _QuarantineReason.clockInvalid;
  if (code.contains('SCHEMA')) return _QuarantineReason.schemaUnsupported;
  if (code.contains('SECURITY') || code.contains('POISON')) {
    return _QuarantineReason.securitySuspicion;
  }
  return _QuarantineReason.otherQuarantine;
}

int _missingExpectedEvents(
  Set<String> eligibleBuckets,
  Map<String, Set<ObservationEventType>> observedByBucket,
  Set<ObservationEventType> expected,
) {
  if (expected.isEmpty) return 0;
  var missing = 0;
  for (final bucket in eligibleBuckets) {
    final observed = observedByBucket[bucket] ?? const <ObservationEventType>{};
    for (final type in expected) {
      if (!observed.contains(type)) missing++;
    }
  }
  return missing;
}

final class _CounterBuilder {
  int lookupAttempts = 0;
  int candidateOffers = 0;
  int downloadSucceeded = 0;
  int downloadFailed = 0;
  int admissionVerified = 0;
  int admissionRejected = 0;
  int activationStarted = 0;
  int activationSucceeded = 0;
  int activationFailed = 0;
  int healthyConfirmed = 0;
  int runtimeFaults = 0;
  int rollbacks = 0;
  int fallbacksToAot = 0;
  int restartSurvived = 0;
  int staleOrReplayRejects = 0;
  int lateEvents = 0;
  int missingExpectedEvents = 0;

  void add(ObservationEventType type) {
    switch (type) {
      case ObservationEventType.lookup_attempt:
        lookupAttempts++;
      case ObservationEventType.candidate_offered:
        candidateOffers++;
      case ObservationEventType.download_succeeded:
        downloadSucceeded++;
      case ObservationEventType.download_failed:
        downloadFailed++;
      case ObservationEventType.admission_verified:
        admissionVerified++;
      case ObservationEventType.admission_rejected:
        admissionRejected++;
      case ObservationEventType.activation_started:
        activationStarted++;
      case ObservationEventType.activation_succeeded:
        activationSucceeded++;
      case ObservationEventType.activation_failed:
        activationFailed++;
      case ObservationEventType.healthy_confirmed:
        healthyConfirmed++;
      case ObservationEventType.runtime_fault:
        runtimeFaults++;
      case ObservationEventType.rollback:
        rollbacks++;
      case ObservationEventType.fallback_to_aot:
        fallbacksToAot++;
      case ObservationEventType.restart_survived:
        restartSurvived++;
      case ObservationEventType.store_release_required:
        break;
    }
  }

  AggregateCounters build({
    required int eligibleInstallationsObserved,
    required int quarantinedEvents,
  }) => AggregateCounters(
    eligibleInstallationsObserved: eligibleInstallationsObserved,
    lookupAttempts: lookupAttempts,
    candidateOffers: candidateOffers,
    downloadSucceeded: downloadSucceeded,
    downloadFailed: downloadFailed,
    admissionVerified: admissionVerified,
    admissionRejected: admissionRejected,
    activationStarted: activationStarted,
    activationSucceeded: activationSucceeded,
    activationFailed: activationFailed,
    healthyConfirmed: healthyConfirmed,
    runtimeFaults: runtimeFaults,
    rollbacks: rollbacks,
    fallbacksToAot: fallbacksToAot,
    restartSurvived: restartSurvived,
    staleOrReplayRejects: staleOrReplayRejects,
    lateEvents: lateEvents,
    quarantinedEvents: quarantinedEvents,
    missingExpectedEvents: missingExpectedEvents,
  );
}

final class _QualityBuilder {
  _QualityBuilder({
    required this.rejected,
    required this.securityRejected,
    required this.duplicate,
    required this.duplicateMutations,
  });

  int accepted = 0;
  int duplicate;
  int duplicateMutations;
  int excessContributions = 0;
  int late = 0;
  int quarantined = 0;
  int rejected;
  int securityRejected;
  int identityMismatch = 0;
  int scopeMismatch = 0;
  int impossibleSequence = 0;
  int clockInvalid = 0;
  int schemaUnsupported = 0;
  int securitySuspicion = 0;
  int otherQuarantine = 0;
  int outOfWindow = 0;

  void addQuarantine(_QuarantineReason reason) {
    quarantined++;
    switch (reason) {
      case _QuarantineReason.identityMismatch:
        identityMismatch++;
      case _QuarantineReason.scopeMismatch:
        scopeMismatch++;
      case _QuarantineReason.impossibleSequence:
        impossibleSequence++;
      case _QuarantineReason.clockInvalid:
        clockInvalid++;
      case _QuarantineReason.schemaUnsupported:
        schemaUnsupported++;
      case _QuarantineReason.securitySuspicion:
        securitySuspicion++;
      case _QuarantineReason.otherQuarantine:
        otherQuarantine++;
    }
  }

  AggregateQualityCounters build({
    required int maximumQuarantineReasonCardinality,
  }) {
    final reasonCardinality = <int>[
      if (identityMismatch > 0) identityMismatch,
      if (scopeMismatch > 0) scopeMismatch,
      if (impossibleSequence > 0) impossibleSequence,
      if (clockInvalid > 0) clockInvalid,
      if (schemaUnsupported > 0) schemaUnsupported,
      if (securitySuspicion > 0) securitySuspicion,
      if (otherQuarantine > 0) otherQuarantine,
    ].length;
    if (reasonCardinality > maximumQuarantineReasonCardinality) {
      throw const FormatException(
        'Aggregation quarantine-reason cardinality exceeds limit',
      );
    }
    return AggregateQualityCounters(
      accepted: accepted,
      duplicate: duplicate,
      duplicateMutations: duplicateMutations,
      excessContributions: excessContributions,
      late: late,
      quarantined: quarantined,
      rejected: rejected,
      securityRejected: securityRejected,
      identityMismatch: identityMismatch,
      scopeMismatch: scopeMismatch,
      impossibleSequence: impossibleSequence,
      clockInvalid: clockInvalid,
      schemaUnsupported: schemaUnsupported,
      securitySuspicion: securitySuspicion,
      otherQuarantine: otherQuarantine,
      outOfWindow: outOfWindow,
    );
  }
}

AggregateCoverage _coverage({
  required int observedInstallations,
  required int? expectedInstallations,
  required int minimumBasisPoints,
}) {
  if (expectedInstallations == null) {
    return AggregateCoverage(
      observedInstallations: observedInstallations,
      expectedInstallations: null,
      observedBasisPoints: null,
      minimumBasisPoints: minimumBasisPoints,
      state: AggregateCoverageState.notEvaluable,
    );
  }
  final basisPoints =
      ((BigInt.from(observedInstallations) * BigInt.from(10000)) ~/
              BigInt.from(expectedInstallations))
          .toInt()
          .clamp(0, 10000);
  return AggregateCoverage(
    observedInstallations: observedInstallations,
    expectedInstallations: expectedInstallations,
    observedBasisPoints: basisPoints,
    minimumBasisPoints: minimumBasisPoints,
    state: basisPoints >= minimumBasisPoints
        ? AggregateCoverageState.sufficient
        : AggregateCoverageState.insufficient,
  );
}

AggregateSampleStatus _sampleStatus(
  AggregateCounters counters,
  AggregateCoverage coverage,
  AggregationMinimumSamples minimum,
) {
  final eligible = AggregateSampleCheck(
    observed: counters.eligibleInstallationsObserved,
    required: minimum.minimumEligibleObserved,
    passed:
        counters.eligibleInstallationsObserved >=
        minimum.minimumEligibleObserved,
  );
  final offers = AggregateSampleCheck(
    observed: counters.candidateOffers,
    required: minimum.minimumOffers,
    passed: counters.candidateOffers >= minimum.minimumOffers,
  );
  final activated = AggregateSampleCheck(
    observed: counters.activationSucceeded,
    required: minimum.minimumActivated,
    passed: counters.activationSucceeded >= minimum.minimumActivated,
  );
  final healthy = AggregateSampleCheck(
    observed: counters.healthyConfirmed,
    required: minimum.minimumHealthyConfirmations,
    passed: counters.healthyConfirmed >= minimum.minimumHealthyConfirmations,
  );
  final coveragePassed = coverage.state == AggregateCoverageState.sufficient;
  return AggregateSampleStatus(
    eligible: eligible,
    offers: offers,
    activated: activated,
    healthy: healthy,
    coveragePassed: coveragePassed,
    allPassed:
        eligible.passed &&
        offers.passed &&
        activated.passed &&
        healthy.passed &&
        coveragePassed,
  );
}

AggregateFreshnessState _freshness(
  DateTime? latestPrimaryReceipt,
  AggregationPolicy policy,
) {
  if (policy.freshnessReference == null || latestPrimaryReceipt == null) {
    return AggregateFreshnessState.unknown;
  }
  final age = policy.freshnessReference!.difference(latestPrimaryReceipt);
  if (age < Duration.zero || age > policy.freshnessMaximumAge!) {
    return AggregateFreshnessState.stale;
  }
  return AggregateFreshnessState.fresh;
}

Set<AggregateMissingDataReason> _missingData({
  required int acceptedInputCount,
  required int primaryCount,
  required int lateCount,
  required AggregateQualityCounters quality,
  required int missingExpectedEvents,
  required Set<ObservationEventType> expectedEventTypes,
  required AggregateFreshnessState freshness,
  required AggregationExternalQuality externalQuality,
  required int materialQuarantineMinimum,
}) {
  final reasons = <AggregateMissingDataReason>{};
  if (externalQuality.observationOutage) {
    reasons.add(AggregateMissingDataReason.observationOutage);
  }
  if (acceptedInputCount == 0 || primaryCount == 0) {
    reasons.add(AggregateMissingDataReason.noEvidence);
  }
  if (missingExpectedEvents > 0 && expectedEventTypes.isNotEmpty) {
    reasons.add(AggregateMissingDataReason.incompleteLifecycle);
    if (expectedEventTypes.contains(ObservationEventType.restart_survived)) {
      reasons.add(AggregateMissingDataReason.missingRestartEvidence);
    }
  }
  if (freshness == AggregateFreshnessState.stale ||
      (primaryCount == 0 && lateCount > 0)) {
    reasons.add(AggregateMissingDataReason.staleEvidence);
  }
  if (quality.quarantined >= materialQuarantineMinimum &&
      materialQuarantineMinimum > 0) {
    reasons.add(AggregateMissingDataReason.materialQuarantine);
  }
  return reasons;
}

AggregatePrivacyState _privacyState({
  required int eligibleInstallationsObserved,
  required int smallCohortMinimum,
}) {
  if (eligibleInstallationsObserved == 0) {
    return AggregatePrivacyState.insufficientData;
  }
  if (eligibleInstallationsObserved < smallCohortMinimum) {
    return AggregatePrivacyState.smallCohortSuppressed;
  }
  return AggregatePrivacyState.normal;
}

Map<AggregateMetricName, AggregateMetric> _metrics({
  required AggregateCounters counters,
  required AggregateQualityCounters quality,
  required AggregateFreshnessState freshness,
  required MetricDenominatorPolicy denominatorPolicy,
}) => <AggregateMetricName, AggregateMetric>{
  AggregateMetricName.downloadSuccess: _pair(
    counters.downloadSucceeded,
    counters.downloadSucceeded + counters.downloadFailed,
    'no download outcomes',
  ),
  AggregateMetricName.admissionSuccess: _pair(
    counters.admissionVerified,
    counters.admissionVerified + counters.admissionRejected,
    'no admission outcomes',
  ),
  AggregateMetricName.activationSuccess: _pair(
    counters.activationSucceeded,
    counters.activationSucceeded + counters.activationFailed,
    'no activation outcomes',
  ),
  AggregateMetricName.healthyConfirmation: _pair(
    counters.healthyConfirmed,
    counters.activationSucceeded,
    'no successful activations',
  ),
  AggregateMetricName.runtimeFaultRate: _pair(
    counters.runtimeFaults,
    _denominator(counters, denominatorPolicy.runtimeFaults),
    'runtime-fault denominator is empty',
  ),
  AggregateMetricName.rollbackFallbackRate: _pair(
    counters.rollbacks + counters.fallbacksToAot,
    _denominator(counters, denominatorPolicy.rollbackFallback),
    'rollback/fallback denominator is empty',
  ),
  AggregateMetricName.restartSurvival: _pair(
    counters.restartSurvived,
    _denominator(counters, denominatorPolicy.restartSurvival),
    'restart-survival denominator is empty',
  ),
  AggregateMetricName.freshness: freshness == AggregateFreshnessState.unknown
      ? const AggregateMetric.notEvaluable(
          notEvaluableReason: 'freshness policy input is absent',
        )
      : AggregateMetric.evaluable(
          numerator: freshness == AggregateFreshnessState.fresh ? 1 : 0,
          denominator: 1,
        ),
  AggregateMetricName.quarantineRate: _pair(
    quality.quarantined,
    quality.accepted + quality.late + quality.quarantined + quality.outOfWindow,
    'no unique observation records',
  ),
};

int _denominator(AggregateCounters counters, MetricDenominatorSource source) =>
    switch (source) {
      MetricDenominatorSource.activationSucceeded =>
        counters.activationSucceeded,
      MetricDenominatorSource.healthyConfirmed => counters.healthyConfirmed,
    };

AggregateMetric _pair(int numerator, int denominator, String reason) {
  if (denominator <= 0) {
    return AggregateMetric.notEvaluable(notEvaluableReason: reason);
  }
  return AggregateMetric.evaluable(
    numerator: numerator,
    denominator: denominator,
  );
}

int _compareMissing(
  AggregateMissingDataReason left,
  AggregateMissingDataReason right,
) => left.wireName.compareTo(right.wireName);
