import 'dart:convert';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late AggregateIdentity identity;
  late ObservationWindow window;
  late AggregationPolicy policy;
  late DateTime start;
  const aggregator = DeterministicAggregator();

  setUp(() {
    start = DateTime.utc(2026, 8, 24, 12);
    window = ObservationWindow(
      windowId: 'window_test',
      serverStart: start,
      serverEnd: start.add(const Duration(hours: 1)),
      lateCutoff: start.add(const Duration(hours: 2)),
      minimumDuration: const Duration(hours: 1),
      maximumDuration: const Duration(hours: 3),
      windowPolicyVersion: 1,
    );
    identity = AggregateIdentity(
      organizationId: 'org_test',
      applicationId: 'app_test',
      environmentId: 'env_test',
      platformId: 'android',
      releaseId: 'release_test',
      patchId: 'patch_test',
      sequence: 1,
      rolloutId: 'rollout_test',
      rolloutRevision: 1,
      windowId: window.windowId,
      windowStart: window.serverStart,
      windowEnd: window.serverEnd,
      lateCutoff: window.lateCutoff,
      observationSchemaVersion: 1,
      aggregationVersion: 1,
    );
    policy = AggregationPolicy(
      version: 1,
      minimumSamples: const AggregationMinimumSamples(
        minimumEligibleObserved: 1,
        minimumOffers: 1,
        minimumActivated: 1,
        minimumHealthyConfirmations: 1,
        minimumCoverageBasisPoints: 10000,
      ),
      smallCohortMinimum: 1,
      materialQuarantineMinimum: 1,
      limits: const AggregationLimits(
        maximumRecords: 100,
        maximumCanonicalBytes: 1024 * 1024,
        maximumQuarantineReasonCardinality: 7,
        maximumDiagnosticCodeCardinality: 32,
      ),
      denominatorPolicy: const MetricDenominatorPolicy(
        runtimeFaults: MetricDenominatorSource.activationSucceeded,
        rollbackFallback: MetricDenominatorSource.activationSucceeded,
        restartSurvival: MetricDenominatorSource.activationSucceeded,
      ),
      expectedEligibleInstallations: 1,
      freshnessReference: start.add(const Duration(hours: 1, minutes: 30)),
      freshnessMaximumAge: const Duration(hours: 2),
    );
  });

  ObservationRecord record(
    String id,
    ObservationEventType type, {
    String bucket = 'bucket:1',
    DateTime? receivedAt,
    ObservationDisposition disposition = ObservationDisposition.accepted,
    String? diagnosticCode,
  }) {
    final receipt = receivedAt ?? start.add(const Duration(minutes: 5));
    return ObservationRecord(
      event: ObservationEvent(
        schemaVersion: 1,
        eventId: id,
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
        runtimeVersion: 'runtime-1',
        patchFormatVersion: 1,
        diagnosticCode: diagnosticCode,
      ),
      receivedAt: receipt,
      disposition: disposition,
    );
  }

  List<ObservationRecord> healthyRecords({String bucket = 'bucket:1'}) =>
      <ObservationRecord>[
        record(
          'lookup-$bucket',
          ObservationEventType.lookup_attempt,
          bucket: bucket,
        ),
        record(
          'offer-$bucket',
          ObservationEventType.candidate_offered,
          bucket: bucket,
        ),
        record(
          'download-$bucket',
          ObservationEventType.download_succeeded,
          bucket: bucket,
        ),
        record(
          'admit-$bucket',
          ObservationEventType.admission_verified,
          bucket: bucket,
        ),
        record(
          'activation-start-$bucket',
          ObservationEventType.activation_started,
          bucket: bucket,
        ),
        record(
          'activation-success-$bucket',
          ObservationEventType.activation_succeeded,
          bucket: bucket,
        ),
        record(
          'healthy-$bucket',
          ObservationEventType.healthy_confirmed,
          bucket: bucket,
        ),
        record(
          'restart-$bucket',
          ObservationEventType.restart_survived,
          bucket: bucket,
        ),
      ];

  test('identity and window canonicalization is exact and UTC normalized', () {
    final equivalent = AggregateIdentity(
      organizationId: identity.organizationId,
      applicationId: identity.applicationId,
      environmentId: identity.environmentId,
      platformId: identity.platformId,
      releaseId: identity.releaseId,
      patchId: identity.patchId,
      sequence: identity.sequence,
      rolloutId: identity.rolloutId,
      rolloutRevision: identity.rolloutRevision,
      windowId: identity.windowId,
      windowStart: identity.windowStart.toLocal(),
      windowEnd: identity.windowEnd.toLocal(),
      lateCutoff: identity.lateCutoff.toLocal(),
      observationSchemaVersion: 1,
      aggregationVersion: 1,
    );
    expect(equivalent, equals(identity));
    expect(identity.canonicalSerialization, contains('"aggregationVersion":1'));
    expect(window.phaseAt(start), AggregationWindowPhase.open);
    expect(window.phaseAt(window.serverEnd), AggregationWindowPhase.closed);
    expect(window.phaseAt(window.lateCutoff), AggregationWindowPhase.sealed);
    expect(
      window.placementAt(window.serverEnd),
      AggregationRecordPlacement.late,
    );
  });

  test('rejects invalid versions and window configurations', () {
    expect(
      () => ObservationWindow(
        windowId: 'window_invalid',
        serverStart: start,
        serverEnd: start,
        lateCutoff: start,
        minimumDuration: const Duration(hours: 1),
        maximumDuration: const Duration(hours: 2),
        windowPolicyVersion: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => ObservationWindow(
        windowId: 'window_invalid',
        serverStart: start,
        serverEnd: start.add(const Duration(hours: 1)),
        lateCutoff: start,
        minimumDuration: const Duration(hours: 1),
        maximumDuration: const Duration(hours: 2),
        windowPolicyVersion: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => AggregateIdentity(
        organizationId: identity.organizationId,
        applicationId: identity.applicationId,
        environmentId: identity.environmentId,
        platformId: identity.platformId,
        releaseId: identity.releaseId,
        patchId: identity.patchId,
        sequence: identity.sequence,
        rolloutId: identity.rolloutId,
        rolloutRevision: identity.rolloutRevision,
        windowId: identity.windowId,
        windowStart: identity.windowStart,
        windowEnd: identity.windowEnd,
        lateCutoff: identity.lateCutoff,
        observationSchemaVersion: 1,
        aggregationVersion: 2,
      ),
      throwsFormatException,
    );
    expect(
      () => AggregationPolicy(
        version: 2,
        minimumSamples: policy.minimumSamples,
        smallCohortMinimum: policy.smallCohortMinimum,
        materialQuarantineMinimum: policy.materialQuarantineMinimum,
        limits: policy.limits,
        denominatorPolicy: policy.denominatorPolicy,
      ),
      throwsFormatException,
    );
  });

  test('healthy complete simulation vector is deterministic and evaluable', () {
    final result = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: healthyRecords(),
    );
    expect(result.counters.eligibleInstallationsObserved, 1);
    expect(result.counters.candidateOffers, 1);
    expect(result.counters.downloadSucceeded, 1);
    expect(result.counters.admissionVerified, 1);
    expect(result.counters.activationSucceeded, 1);
    expect(result.counters.healthyConfirmed, 1);
    expect(result.counters.restartSurvived, 1);
    expect(result.samples.allPassed, isTrue);
    expect(result.coverage.state, AggregateCoverageState.sufficient);
    expect(result.privacyState, AggregatePrivacyState.normal);
    expect(result.freshnessState, AggregateFreshnessState.fresh);
    expect(result.missingData, isEmpty);
    expect(result.metrics[AggregateMetricName.activationSuccess]!.numerator, 1);
    expect(
      result.metrics[AggregateMetricName.activationSuccess]!.denominator,
      1,
    );
    expect(
      result.metrics[AggregateMetricName.runtimeFaultRate]!.status,
      AggregateMetricStatus.evaluable,
    );
    expect(result.toJson().toString(), isNot(contains('bucket:1')));
  });

  test('all P3D event types map to exactly one stable category', () {
    final categories = <ObservationEventType, ObservationCategory>{
      for (final type in ObservationEventType.values)
        type: categoryForObservation(type),
    };
    expect(categories.length, ObservationEventType.values.length);
    expect(
      categories[ObservationEventType.lookup_attempt],
      ObservationCategory.delivery,
    );
    expect(
      categories[ObservationEventType.admission_rejected],
      ObservationCategory.admission,
    );
    expect(
      categories[ObservationEventType.activation_failed],
      ObservationCategory.activation,
    );
    expect(
      categories[ObservationEventType.runtime_fault],
      ObservationCategory.postActivationHealth,
    );
    expect(
      categories[ObservationEventType.fallback_to_aot],
      ObservationCategory.rollbackFallback,
    );
    expect(
      categories[ObservationEventType.restart_survived],
      ObservationCategory.restartSurvival,
    );
    expect(
      categories[ObservationEventType.store_release_required],
      ObservationCategory.storeBoundExclusion,
    );
  });

  test(
    'exact retries deduplicate and mutated IDs are security context only',
    () {
      final first = record('same-id', ObservationEventType.candidate_offered);
      final exactRetry = record(
        'same-id',
        ObservationEventType.candidate_offered,
      );
      final mutated = record('same-id', ObservationEventType.download_failed);
      final duplicateOnly = aggregator.aggregate(
        identity: identity,
        window: window,
        policy: policy,
        records: <ObservationRecord>[first, exactRetry],
      );
      expect(duplicateOnly.inputCount, 1);
      expect(duplicateOnly.quality.duplicate, 1);
      expect(duplicateOnly.counters.candidateOffers, 1);
      expect(
        duplicateOnly.inputDigest,
        equals(
          aggregator
              .aggregate(
                identity: identity,
                window: window,
                policy: policy,
                records: <ObservationRecord>[first],
              )
              .inputDigest,
        ),
      );
      final mutatedResult = aggregator.aggregate(
        identity: identity,
        window: window,
        policy: policy,
        records: <ObservationRecord>[first, mutated],
      );
      expect(mutatedResult.inputCount, 0);
      expect(mutatedResult.counters.candidateOffers, 0);
      expect(mutatedResult.quality.duplicateMutations, 1);
      expect(mutatedResult.quality.securityRejected, 1);
    },
  );

  test(
    'per-installation contribution cap prevents noisy buckets dominating',
    () {
      final records = <ObservationRecord>[
        record('lookup-a', ObservationEventType.lookup_attempt),
        record('lookup-b', ObservationEventType.lookup_attempt),
        record('lookup-c', ObservationEventType.lookup_attempt),
        record('offer-a', ObservationEventType.candidate_offered),
        record('offer-b', ObservationEventType.candidate_offered),
      ];
      final result = aggregator.aggregate(
        identity: identity,
        window: window,
        policy: policy,
        records: records,
      );
      expect(result.counters.lookupAttempts, 1);
      expect(result.counters.candidateOffers, 1);
      expect(result.quality.excessContributions, 3);
    },
  );

  test('input permutation does not change canonical aggregate output', () {
    final records = healthyRecords();
    final reversed = records.reversed.toList();
    final original = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: records,
    );
    final permuted = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: reversed,
    );
    expect(permuted, equals(original));
    expect(permuted.canonicalSerialization, original.canonicalSerialization);
  });

  test('late records remain visible without changing primary counters', () {
    final base = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: healthyRecords(),
    );
    final late = record(
      'late-failure',
      ObservationEventType.activation_failed,
      receivedAt: window.serverEnd.add(const Duration(minutes: 10)),
      disposition: ObservationDisposition.late,
    );
    final withLate = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: <ObservationRecord>[...healthyRecords(), late],
    );
    expect(withLate.counters.activationFailed, base.counters.activationFailed);
    expect(withLate.counters.lateEvents, 1);
    expect(withLate.quality.late, 1);
    expect(withLate.inputCount, base.inputCount);
    expect(withLate.inputDigest, base.inputDigest);
    expect(withLate.missingData, isEmpty);
  });

  test('quarantine rows are excluded and reason counters remain visible', () {
    final result = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: <ObservationRecord>[
        record(
          'quarantined-sequence',
          ObservationEventType.healthy_confirmed,
          disposition: ObservationDisposition.quarantined,
          diagnosticCode: 'EVENT_SEQUENCE_QUARANTINED',
        ),
        record(
          'quarantined-clock',
          ObservationEventType.lookup_attempt,
          disposition: ObservationDisposition.quarantined,
          diagnosticCode: 'EVENT_CLOCK_INVALID',
        ),
      ],
    );
    expect(result.counters.quarantinedEvents, 2);
    expect(result.counters.activationSucceeded, 0);
    expect(result.quality.impossibleSequence, 1);
    expect(result.quality.clockInvalid, 1);
    expect(result.missingData, contains(AggregateMissingDataReason.noEvidence));
    expect(
      result.missingData,
      contains(AggregateMissingDataReason.materialQuarantine),
    );
  });

  test(
    'external rejection and observation outage never become health events',
    () {
      final result = aggregator.aggregate(
        identity: identity,
        window: window,
        policy: policy,
        records: const <ObservationRecord>[],
        externalQuality: const AggregationExternalQuality(
          rejected: 4,
          securityRejected: 2,
          observationOutage: true,
        ),
      );
      expect(result.quality.rejected, 4);
      expect(result.quality.securityRejected, 2);
      expect(result.counters.candidateOffers, 0);
      expect(
        result.missingData,
        contains(AggregateMissingDataReason.observationOutage),
      );
      expect(
        result.metrics[AggregateMetricName.activationSuccess]!.status,
        AggregateMetricStatus.notEvaluable,
      );
    },
  );

  test('activation-failure, runtime-fault, and delivery-outage vectors stay distinct', () {
    final activationFailure = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: <ObservationRecord>[
        record('offer', ObservationEventType.candidate_offered),
        record('activation-start', ObservationEventType.activation_started),
        record('activation-fail', ObservationEventType.activation_failed),
      ],
    );
    expect(activationFailure.counters.activationFailed, 1);
    expect(
      activationFailure
          .metrics[AggregateMetricName.activationSuccess]!
          .numerator,
      0,
    );
    expect(
      activationFailure
          .metrics[AggregateMetricName.activationSuccess]!
          .denominator,
      1,
    );

    final runtimeFault = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: <ObservationRecord>[
        record('activation-success', ObservationEventType.activation_succeeded),
        record(
          'fault-a',
          ObservationEventType.runtime_fault,
          diagnosticCode: 'RUNTIME_FAULT',
        ),
        record(
          'fault-b',
          ObservationEventType.runtime_fault,
          diagnosticCode: 'RUNTIME_FAULT',
        ),
      ],
    );
    expect(runtimeFault.counters.runtimeFaults, 1);
    expect(runtimeFault.quality.excessContributions, 1);
    expect(
      runtimeFault.metrics[AggregateMetricName.runtimeFaultRate]!.denominator,
      1,
    );

    final deliveryOutage = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: <ObservationRecord>[
        record('offer', ObservationEventType.candidate_offered),
        record('download-fail', ObservationEventType.download_failed),
      ],
    );
    expect(deliveryOutage.counters.downloadFailed, 1);
    expect(deliveryOutage.counters.activationFailed, 0);
    expect(
      deliveryOutage.metrics[AggregateMetricName.downloadSuccess]!.numerator,
      0,
    );
  });

  test('expected lifecycle and restart gaps are explicit missing data', () {
    final lifecyclePolicy = AggregationPolicy(
      version: 1,
      minimumSamples: policy.minimumSamples,
      smallCohortMinimum: policy.smallCohortMinimum,
      materialQuarantineMinimum: policy.materialQuarantineMinimum,
      limits: policy.limits,
      denominatorPolicy: policy.denominatorPolicy,
      expectedEventTypes: const <ObservationEventType>{
        ObservationEventType.candidate_offered,
        ObservationEventType.activation_succeeded,
        ObservationEventType.restart_survived,
      },
      expectedEligibleInstallations: 1,
    );
    final result = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: lifecyclePolicy,
      records: <ObservationRecord>[
        record('offer', ObservationEventType.candidate_offered),
      ],
    );
    expect(result.counters.missingExpectedEvents, 2);
    expect(
      result.missingData,
      contains(AggregateMissingDataReason.incompleteLifecycle),
    );
    expect(
      result.missingData,
      contains(AggregateMissingDataReason.missingRestartEvidence),
    );
  });

  test(
    'small cohorts are suppressed without exposing installation buckets',
    () {
      final smallPolicy = AggregationPolicy(
        version: 1,
        minimumSamples: policy.minimumSamples,
        smallCohortMinimum: 2,
        materialQuarantineMinimum: policy.materialQuarantineMinimum,
        limits: policy.limits,
        denominatorPolicy: policy.denominatorPolicy,
        expectedEligibleInstallations: 1,
      );
      final result = aggregator.aggregate(
        identity: identity,
        window: window,
        policy: smallPolicy,
        records: <ObservationRecord>[
          record('offer', ObservationEventType.candidate_offered),
        ],
      );
      expect(result.privacyState, AggregatePrivacyState.smallCohortSuppressed);
      expect(result.canonicalSerialization, isNot(contains('bucket:1')));
    },
  );

  test('unresolved denominators are explicitly NOT_EVALUABLE', () {
    final result = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: <ObservationRecord>[
        record('offer', ObservationEventType.candidate_offered),
      ],
    );
    expect(
      result.metrics[AggregateMetricName.activationSuccess]!.status,
      AggregateMetricStatus.notEvaluable,
    );
    expect(
      result.metrics[AggregateMetricName.restartSurvival]!.status,
      AggregateMetricStatus.notEvaluable,
    );
  });

  test('mixed release or rollout scope fails closed', () {
    final mismatched = ObservationRecord(
      event: ObservationEvent(
        schemaVersion: 1,
        eventId: 'foreign-event',
        clientTimestamp: start,
        organizationId: identity.organizationId,
        applicationId: identity.applicationId,
        environmentId: identity.environmentId,
        platform: identity.platformId,
        releaseId: 'other_release',
        patchId: identity.patchId,
        sequence: identity.sequence,
        rolloutId: identity.rolloutId,
        rolloutRevision: identity.rolloutRevision,
        installationBucket: 'bucket:1',
        eventType: ObservationEventType.candidate_offered,
        runtimeVersion: 'runtime-1',
        patchFormatVersion: 1,
        diagnosticCode: null,
      ),
      receivedAt: start,
      disposition: ObservationDisposition.accepted,
    );
    expect(
      () => aggregator.aggregate(
        identity: identity,
        window: window,
        policy: policy,
        records: <ObservationRecord>[mismatched],
      ),
      throwsFormatException,
    );
  });

  test('malformed observations and resource limits fail closed', () {
    expect(
      () => ObservationEvent.fromJson(<String, Object?>{
        'schemaVersion': 1,
        'eventId': 'bad-event',
        'clientTimestamp': start.toIso8601String(),
        'organizationId': identity.organizationId,
        'applicationId': identity.applicationId,
        'environmentId': identity.environmentId,
        'platform': identity.platformId,
        'releaseId': identity.releaseId,
        'patchId': identity.patchId,
        'sequence': identity.sequence,
        'rolloutId': identity.rolloutId,
        'rolloutRevision': identity.rolloutRevision,
        'installationBucket': 'bucket:1',
        'eventType': 'not_a_real_event',
        'runtimeVersion': 'runtime-1',
        'patchFormatVersion': 1,
        'diagnosticCode': null,
        'safeMetadata': <String, Object?>{},
      }),
      throwsFormatException,
    );
    final boundedPolicy = AggregationPolicy(
      version: 1,
      minimumSamples: policy.minimumSamples,
      smallCohortMinimum: policy.smallCohortMinimum,
      materialQuarantineMinimum: policy.materialQuarantineMinimum,
      limits: const AggregationLimits(
        maximumRecords: 1,
        maximumCanonicalBytes: 100000,
        maximumQuarantineReasonCardinality: 7,
        maximumDiagnosticCodeCardinality: 32,
      ),
      denominatorPolicy: policy.denominatorPolicy,
    );
    expect(
      () => aggregator.aggregate(
        identity: identity,
        window: window,
        policy: boundedPolicy,
        records: <ObservationRecord>[
          record('one', ObservationEventType.candidate_offered),
          record('two', ObservationEventType.download_failed),
        ],
      ),
      throwsFormatException,
    );
  });

  test('quarantine and diagnostic cardinality bounds are enforced', () {
    final reasonBoundPolicy = AggregationPolicy(
      version: 1,
      minimumSamples: policy.minimumSamples,
      smallCohortMinimum: policy.smallCohortMinimum,
      materialQuarantineMinimum: policy.materialQuarantineMinimum,
      limits: const AggregationLimits(
        maximumRecords: 10,
        maximumCanonicalBytes: 100000,
        maximumQuarantineReasonCardinality: 1,
        maximumDiagnosticCodeCardinality: 32,
      ),
      denominatorPolicy: policy.denominatorPolicy,
    );
    expect(
      () => aggregator.aggregate(
        identity: identity,
        window: window,
        policy: reasonBoundPolicy,
        records: <ObservationRecord>[
          record(
            'sequence',
            ObservationEventType.lookup_attempt,
            disposition: ObservationDisposition.quarantined,
            diagnosticCode: 'EVENT_SEQUENCE_QUARANTINED',
          ),
          record(
            'clock',
            ObservationEventType.lookup_attempt,
            disposition: ObservationDisposition.quarantined,
            diagnosticCode: 'EVENT_CLOCK_INVALID',
          ),
        ],
      ),
      throwsFormatException,
    );

    final diagnosticBoundPolicy = AggregationPolicy(
      version: 1,
      minimumSamples: policy.minimumSamples,
      smallCohortMinimum: policy.smallCohortMinimum,
      materialQuarantineMinimum: policy.materialQuarantineMinimum,
      limits: const AggregationLimits(
        maximumRecords: 10,
        maximumCanonicalBytes: 100000,
        maximumQuarantineReasonCardinality: 7,
        maximumDiagnosticCodeCardinality: 1,
      ),
      denominatorPolicy: policy.denominatorPolicy,
    );
    expect(
      () => aggregator.aggregate(
        identity: identity,
        window: window,
        policy: diagnosticBoundPolicy,
        records: <ObservationRecord>[
          record(
            'diagnostic-one',
            ObservationEventType.runtime_fault,
            diagnosticCode: 'FAULT_ONE',
          ),
          record(
            'diagnostic-two',
            ObservationEventType.runtime_fault,
            diagnosticCode: 'FAULT_TWO',
          ),
        ],
      ),
      throwsFormatException,
    );
  });

  test('stale-evaluation and concurrent-control vectors cannot mutate rollout state', () {
    final first = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: healthyRecords(),
    );
    final second = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: healthyRecords(),
    );
    expect(second, equals(first));
    expect(identity.rolloutRevision, 1);
    expect(identity.rolloutId, 'rollout_test');
  });

  test('canonical result remains stable across JSON encoding', () {
    final result = aggregator.aggregate(
      identity: identity,
      window: window,
      policy: policy,
      records: healthyRecords(),
    );
    final encoded = canonicalJson(jsonDecode(result.canonicalSerialization));
    expect(encoded, result.canonicalSerialization);
  });
}
