import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late HealthAggregate aggregate;
  late HealthAggregateRecord record;
  late HealthAggregateRevision revision;

  setUp(() {
    aggregate = _aggregate();
    revision = _revision(aggregate);
    record = HealthAggregateRecord(
      aggregateId: 'aggregate_eval',
      revisionId: revision.aggregateRevisionId,
      aggregate: aggregate,
      recomputability: P3eRecomputability.rawRecomputable,
      createdAt: DateTime.utc(2026, 8, 24, 14),
    );
  });

  test('healthy complete evidence evaluates deterministically to CONTINUE', () {
    final request = _request(aggregate, revision);
    const evaluator = ManualP3eEvaluator();
    final first = evaluator.evaluate(
      aggregate: record,
      revision: revision,
      request: request,
    );
    final second = evaluator.evaluate(
      aggregate: record,
      revision: revision,
      request: request,
    );
    expect(first.decision, 'CONTINUE');
    expect(first.reasonClass, 'PATCH_SAFETY');
    expect(first.reasonCodes, contains('HEALTHY_COMPLETE_EVIDENCE'));
    expect(first.coverageState, 'SUFFICIENT');
    expect(first.sampleState, 'PASSED');
    expect(first.reasonCodes, second.reasonCodes);
    expect(
      evaluator.evaluationInputDigest(
        aggregate: record,
        revision: revision,
        request: request,
      ),
      evaluator.evaluationInputDigest(
        aggregate: record,
        revision: revision,
        request: request,
      ),
    );
  });

  test('explicit activation threshold yields HALT_NEW_OFFERS evidence', () {
    final failed = _aggregate(includeActivationFailure: true);
    final failedRevision = _revision(failed);
    final failedRecord = HealthAggregateRecord(
      aggregateId: 'aggregate_eval',
      revisionId: failedRevision.aggregateRevisionId,
      aggregate: failed,
      recomputability: P3eRecomputability.rawRecomputable,
      createdAt: DateTime.utc(2026, 8, 24, 14),
    );
    final request = _request(
      failed,
      failedRevision,
      haltActivationFailureRateBasisPoints: 4000,
    );
    final outcome = const ManualP3eEvaluator().evaluate(
      aggregate: failedRecord,
      revision: failedRevision,
      request: request,
    );
    expect(outcome.decision, 'HALT_NEW_OFFERS');
    expect(outcome.reasonClass, 'PATCH_SAFETY');
    expect(outcome.reasonCodes, contains('ACTIVATION_FAILURE_RATE_EXCEEDED'));
  });

  test('patch-safety signal without explicit threshold is manual review', () {
    final failed = _aggregate(includeActivationFailure: true);
    final failedRevision = _revision(failed);
    final failedRecord = HealthAggregateRecord(
      aggregateId: 'aggregate_eval',
      revisionId: failedRevision.aggregateRevisionId,
      aggregate: failed,
      recomputability: P3eRecomputability.rawRecomputable,
      createdAt: DateTime.utc(2026, 8, 24, 14),
    );
    final outcome = const ManualP3eEvaluator().evaluate(
      aggregate: failedRecord,
      revision: failedRevision,
      request: _request(failed, failedRevision),
    );
    expect(outcome.decision, 'MANUAL_REVIEW');
    expect(outcome.reasonClass, 'OPERATOR_POLICY');
    expect(
      outcome.reasonCodes,
      contains('ACTIVATION_FAILURE_RATE_THRESHOLD_REQUIRED'),
    );
  });

  test('privacy suppression precedes health thresholds', () {
    final suppressed = _copyAggregate(
      aggregate,
      privacyState: AggregatePrivacyState.smallCohortSuppressed,
    );
    final suppressedRevision = _revision(suppressed);
    final outcome = const ManualP3eEvaluator().evaluate(
      aggregate: HealthAggregateRecord(
        aggregateId: 'aggregate_eval',
        revisionId: suppressedRevision.aggregateRevisionId,
        aggregate: suppressed,
        recomputability: P3eRecomputability.rawRecomputable,
        createdAt: DateTime.utc(2026, 8, 24, 14),
      ),
      revision: suppressedRevision,
      request: _request(suppressed, suppressedRevision),
    );
    expect(outcome.decision, 'INSUFFICIENT_DATA');
    expect(outcome.reasonClass, 'DATA_QUALITY');
    expect(outcome.reasonCodes, contains('PRIVACY_SUPPRESSED'));
  });

  test('observation outage is HOLD, not patch safety', () {
    final outage = _aggregate(observationOutage: true);
    final outageRevision = _revision(outage);
    final outcome = const ManualP3eEvaluator().evaluate(
      aggregate: HealthAggregateRecord(
        aggregateId: 'aggregate_eval',
        revisionId: outageRevision.aggregateRevisionId,
        aggregate: outage,
        recomputability: P3eRecomputability.rawRecomputable,
        createdAt: DateTime.utc(2026, 8, 24, 14),
      ),
      revision: outageRevision,
      request: _request(outage, outageRevision),
    );
    expect(outcome.decision, 'HOLD');
    expect(outcome.reasonClass, 'OBSERVATION_HEALTH');
    expect(outcome.reasonCodes, contains('OBSERVATION_OUTAGE'));
  });

  test('non-recomputable evidence requires explicit policy permission', () {
    final request = _request(aggregate, revision);
    final denied = HealthAggregateRecord(
      aggregateId: record.aggregateId,
      revisionId: record.revisionId,
      aggregate: aggregate,
      recomputability: P3eRecomputability.rawExpired,
      createdAt: record.createdAt,
    );
    expect(
      () => const ManualP3eEvaluator().evaluate(
        aggregate: denied,
        revision: revision,
        request: request,
      ),
      throwsFormatException,
    );
    final allowedRequest = _request(
      aggregate,
      revision,
      allowNonRecomputable: true,
    );
    final outcome = const ManualP3eEvaluator().evaluate(
      aggregate: denied,
      revision: revision,
      request: allowedRequest,
    );
    expect(outcome.decision, 'MANUAL_REVIEW');
    expect(outcome.reasonCodes, contains('NON_RECOMPUTABLE_EVIDENCE'));
  });

  test(
    'unknown policy versions, digest mismatch, and scope mutation fail closed',
    () {
      final request = _request(aggregate, revision);
      expect(
        () => ManualEvaluationPolicy.fromJson({
          ...request.policy.toJson(),
          'evaluationVersion': 99,
        }),
        throwsFormatException,
      );
      expect(
        () => ManualEvaluationRequest(
          organizationId: request.organizationId,
          applicationId: request.applicationId,
          environmentId: request.environmentId,
          platformId: request.platformId,
          rolloutId: request.rolloutId,
          rolloutRevision: request.rolloutRevision,
          aggregationVersion: request.aggregationVersion,
          aggregateId: request.aggregateId,
          aggregateRevisionId: request.aggregateRevisionId,
          releaseId: request.releaseId,
          patchId: request.patchId,
          sequence: request.sequence,
          windowId: request.windowId,
          aggregateInputDigest: request.aggregateInputDigest,
          aggregatePolicyDigest: request.aggregatePolicyDigest,
          policyDigest: _digest('wrong-policy'),
          policy: request.policy,
        ),
        throwsFormatException,
      );
      final wrongScope = ManualEvaluationRequest(
        organizationId: request.organizationId,
        applicationId: request.applicationId,
        environmentId: request.environmentId,
        platformId: request.platformId,
        rolloutId: request.rolloutId,
        rolloutRevision: request.rolloutRevision,
        aggregationVersion: request.aggregationVersion,
        aggregateId: request.aggregateId,
        aggregateRevisionId: request.aggregateRevisionId,
        releaseId: request.releaseId,
        patchId: request.patchId,
        sequence: request.sequence,
        windowId: request.windowId,
        aggregateInputDigest: _digest('wrong-input'),
        aggregatePolicyDigest: request.aggregatePolicyDigest,
        policyDigest: request.policyDigest,
        policy: request.policy,
      );
      expect(
        () => const ManualP3eEvaluator().evaluate(
          aggregate: record,
          revision: revision,
          request: wrongScope,
        ),
        throwsFormatException,
      );
    },
  );
}

ManualEvaluationRequest _request(
  HealthAggregate aggregate,
  HealthAggregateRevision revision, {
  bool allowNonRecomputable = false,
  int? haltActivationFailureRateBasisPoints,
}) {
  final policy = ManualEvaluationPolicy(
    evaluationVersion: 1,
    policyVersion: 1,
    thresholdSetVersion: 1,
    windowPolicyVersion: 1,
    privacyPolicyVersion: 1,
    thresholdSetDigest: _digest('threshold-test-vector'),
    minimumSamples: const AggregationMinimumSamples(
      minimumEligibleObserved: 1,
      minimumOffers: 1,
      minimumActivated: 1,
      minimumHealthyConfirmations: 1,
      minimumCoverageBasisPoints: 5000,
    ),
    requireFreshness: true,
    allowNonRecomputable: allowNonRecomputable,
    maximumQuarantineRateBasisPoints: 10000,
    maximumRejectedRateBasisPoints: 10000,
    maximumLateRateBasisPoints: 10000,
    haltActivationFailureRateBasisPoints: haltActivationFailureRateBasisPoints,
    haltAdmissionRejectionRateBasisPoints: null,
    haltRuntimeFaultRateBasisPoints: null,
    haltRollbackFallbackRateBasisPoints: null,
  );
  return ManualEvaluationRequest(
    organizationId: aggregate.identity.organizationId,
    applicationId: aggregate.identity.applicationId,
    environmentId: aggregate.identity.environmentId,
    platformId: aggregate.identity.platformId,
    rolloutId: aggregate.identity.rolloutId,
    rolloutRevision: aggregate.identity.rolloutRevision,
    aggregationVersion: aggregate.identity.aggregationVersion,
    aggregateId: 'aggregate_eval',
    aggregateRevisionId: revision.aggregateRevisionId,
    releaseId: aggregate.identity.releaseId,
    patchId: aggregate.identity.patchId,
    sequence: aggregate.identity.sequence,
    windowId: aggregate.identity.windowId,
    aggregateInputDigest: revision.inputDigest,
    aggregatePolicyDigest: aggregate.policyDigest,
    policyDigest: policy.policyDigest,
    policy: policy,
  );
}

HealthAggregateRevision _revision(HealthAggregate aggregate) =>
    HealthAggregateRevision(
      aggregateRevisionId: 'revision_eval',
      aggregateId: 'aggregate_eval',
      parentAggregateRevisionId: null,
      identity: aggregate.identity,
      window: aggregate.window,
      aggregationVersion: aggregate.identity.aggregationVersion,
      inputCount: aggregate.inputCount,
      inputDigest: aggregate.inputDigest,
      recomputationReason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
      recomputability: P3eRecomputability.rawRecomputable,
      createdAt: DateTime.utc(2026, 8, 24, 14),
    );

HealthAggregate _aggregate({
  bool includeActivationFailure = false,
  bool observationOutage = false,
}) {
  final start = DateTime.utc(2026, 8, 24, 12);
  final window = ObservationWindow(
    windowId: 'window_eval',
    serverStart: start,
    serverEnd: start.add(const Duration(hours: 1)),
    lateCutoff: start.add(const Duration(hours: 2)),
    minimumDuration: const Duration(hours: 1),
    maximumDuration: const Duration(hours: 3),
    windowPolicyVersion: 1,
  );
  final identity = AggregateIdentity(
    organizationId: 'org_eval',
    applicationId: 'app_eval',
    environmentId: 'env_eval',
    platformId: 'android',
    releaseId: 'release_eval',
    patchId: 'patch_eval',
    sequence: 1,
    rolloutId: 'rollout_eval',
    rolloutRevision: 1,
    windowId: window.windowId,
    windowStart: window.serverStart,
    windowEnd: window.serverEnd,
    lateCutoff: window.lateCutoff,
    observationSchemaVersion: 1,
    aggregationVersion: 1,
  );
  final policy = AggregationPolicy(
    version: 1,
    minimumSamples: const AggregationMinimumSamples(
      minimumEligibleObserved: 1,
      minimumOffers: 1,
      minimumActivated: 1,
      minimumHealthyConfirmations: 1,
      minimumCoverageBasisPoints: 5000,
    ),
    smallCohortMinimum: 1,
    materialQuarantineMinimum: 10,
    limits: const AggregationLimits(
      maximumRecords: 200,
      maximumCanonicalBytes: 1024 * 1024,
      maximumQuarantineReasonCardinality: 7,
      maximumDiagnosticCodeCardinality: 32,
    ),
    denominatorPolicy: const MetricDenominatorPolicy(
      runtimeFaults: MetricDenominatorSource.activationSucceeded,
      rollbackFallback: MetricDenominatorSource.activationSucceeded,
      restartSurvival: MetricDenominatorSource.activationSucceeded,
    ),
    expectedEligibleInstallations: includeActivationFailure ? 2 : 1,
    freshnessReference: start.add(const Duration(hours: 1, minutes: 30)),
    freshnessMaximumAge: const Duration(hours: 2),
  );
  final records = <ObservationRecord>[];
  void add(String bucket, String suffix, ObservationEventType type) {
    final receipt = start.add(const Duration(minutes: 5));
    records.add(
      ObservationRecord(
        event: ObservationEvent(
          schemaVersion: 1,
          eventId: '$bucket-$suffix',
          clientTimestamp: receipt,
          organizationId: identity.organizationId,
          applicationId: identity.applicationId,
          environmentId: identity.environmentId,
          platform: identity.platformId,
          releaseId: identity.releaseId,
          patchId: identity.patchId,
          sequence: identity.sequence,
          rolloutId: identity.rolloutId,
          rolloutRevision: identity.rolloutRevision,
          installationBucket: bucket,
          eventType: type,
          runtimeVersion: 'runtime-eval',
          patchFormatVersion: 1,
          diagnosticCode: null,
        ),
        receivedAt: receipt,
        disposition: ObservationDisposition.accepted,
      ),
    );
  }

  void healthy(String bucket) {
    for (final type in <ObservationEventType>[
      ObservationEventType.lookup_attempt,
      ObservationEventType.candidate_offered,
      ObservationEventType.download_succeeded,
      ObservationEventType.admission_verified,
      ObservationEventType.activation_started,
      ObservationEventType.activation_succeeded,
      ObservationEventType.healthy_confirmed,
      ObservationEventType.restart_survived,
    ]) {
      add(bucket, type.wireName, type);
    }
  }

  healthy('bucket:1');
  if (includeActivationFailure) {
    for (final type in <ObservationEventType>[
      ObservationEventType.lookup_attempt,
      ObservationEventType.candidate_offered,
      ObservationEventType.download_succeeded,
      ObservationEventType.admission_verified,
      ObservationEventType.activation_started,
      ObservationEventType.activation_failed,
    ]) {
      add('bucket:2', type.wireName, type);
    }
  }
  return const DeterministicAggregator().aggregate(
    identity: identity,
    window: window,
    policy: policy,
    records: records,
    externalQuality: AggregationExternalQuality(
      observationOutage: observationOutage,
    ),
  );
}

HealthAggregate _copyAggregate(
  HealthAggregate value, {
  AggregatePrivacyState? privacyState,
  AggregateQualityCounters? quality,
}) => HealthAggregate(
  identity: value.identity,
  window: value.window,
  inputCount: value.inputCount,
  acceptedInputCount: value.acceptedInputCount,
  inputDigest: value.inputDigest,
  policyVersion: value.policyVersion,
  policyDigest: value.policyDigest,
  externalQualityDigest: value.externalQualityDigest,
  counters: value.counters,
  quality: quality ?? value.quality,
  metrics: value.metrics,
  coverage: value.coverage,
  samples: value.samples,
  privacyState: privacyState ?? value.privacyState,
  freshnessState: value.freshnessState,
  missingData: value.missingData,
  latestPrimaryReceivedAt: value.latestPrimaryReceivedAt,
);

String _digest(String value) =>
    'sha256:${sha256.convert(utf8.encode(value)).toString()}';
