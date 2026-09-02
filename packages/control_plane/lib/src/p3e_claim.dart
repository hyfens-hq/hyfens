import 'dart:convert';
import 'dart:math';

import 'encoding.dart';
import 'p3e_halt.dart';
import 'p3e_schedule.dart';

const int supportedP3e5LeasePolicyVersion = 1;
const int supportedP3e5RetryPolicyVersion = 1;
const int supportedP3e5ResourcePolicyVersion = 1;

enum P3e5AutomaticHaltRecoveryOutcome {
  applicationFoundAndValid,
  applicationNotFoundRetryable,
  applicationStale,
  applicationConflict,
  applicationCorrupt,
  securityRejected,
}

extension P3e5AutomaticHaltRecoveryOutcomeWire
    on P3e5AutomaticHaltRecoveryOutcome {
  String get wireName => switch (this) {
    P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid =>
      'APPLICATION_FOUND_AND_VALID',
    P3e5AutomaticHaltRecoveryOutcome.applicationNotFoundRetryable =>
      'APPLICATION_NOT_FOUND_RETRYABLE',
    P3e5AutomaticHaltRecoveryOutcome.applicationStale => 'APPLICATION_STALE',
    P3e5AutomaticHaltRecoveryOutcome.applicationConflict =>
      'APPLICATION_CONFLICT',
    P3e5AutomaticHaltRecoveryOutcome.applicationCorrupt =>
      'APPLICATION_CORRUPT',
    P3e5AutomaticHaltRecoveryOutcome.securityRejected => 'SECURITY_REJECTED',
  };
}

/// Explicit, caller-supplied bounds for one auto-halt recovery invocation.
/// There are intentionally no production defaults: the owner of a worker
/// must choose and audit the limits at construction time.
final class P3e5AutomaticHaltRecoveryLimits {
  const P3e5AutomaticHaltRecoveryLimits({
    required this.maximumRecoveryAttempts,
    required this.maximumApplicationRecords,
    required this.maximumLinkageRecords,
  });

  final int maximumRecoveryAttempts;
  final int maximumApplicationRecords;
  final int maximumLinkageRecords;

  void validate() {
    if (maximumRecoveryAttempts <= 0 ||
        maximumApplicationRecords <= 0 ||
        maximumLinkageRecords <= 0) {
      throw const FormatException('Automatic-halt recovery limits are invalid');
    }
  }
}

enum P3e5RetryClass { transient, stale, permanent, security }

extension P3e5RetryClassWire on P3e5RetryClass {
  String get wireName => name.toUpperCase();
}

enum P3e5JitterMode { none, boundedDeterministic }

final class P3e5LeasePolicy {
  const P3e5LeasePolicy({required this.version, required this.duration});

  final int version;
  final Duration duration;

  void validate() {
    if (version != supportedP3e5LeasePolicyVersion ||
        duration <= Duration.zero) {
      throw const FormatException('Unsupported or invalid lease policy');
    }
  }
}

final class P3e5RetryPolicy {
  const P3e5RetryPolicy({
    required this.version,
    required this.initialDelay,
    required this.maximumDelay,
    required this.maximumAttempts,
    required this.jitterMode,
    required this.jitterBound,
  });

  final int version;
  final Duration initialDelay;
  final Duration maximumDelay;
  final int maximumAttempts;
  final P3e5JitterMode jitterMode;
  final Duration jitterBound;

  void validate() {
    if (version != supportedP3e5RetryPolicyVersion ||
        initialDelay < Duration.zero ||
        maximumDelay < initialDelay ||
        maximumAttempts <= 0 ||
        jitterBound < Duration.zero ||
        jitterBound > maximumDelay ||
        (jitterMode == P3e5JitterMode.none && jitterBound != Duration.zero)) {
      throw const FormatException('Unsupported or invalid retry policy');
    }
  }

  Duration delayFor(String workId, int attemptNumber) {
    validate();
    if (attemptNumber <= 0) {
      throw const FormatException('Invalid retry attempt number');
    }
    var delayMicros = initialDelay.inMicroseconds;
    for (var index = 1; index < attemptNumber; index++) {
      delayMicros = min(delayMicros * 2, maximumDelay.inMicroseconds);
    }
    if (jitterMode == P3e5JitterMode.boundedDeterministic &&
        jitterBound > Duration.zero) {
      final seed = sha256Hex(
        utf8.encode('hyfens.p3e5.retry.v1$workId:$attemptNumber:$version'),
      );
      final sample = int.parse(seed.substring(0, 12), radix: 16);
      delayMicros += sample % (jitterBound.inMicroseconds + 1);
    }
    return Duration(
      microseconds: min(delayMicros, maximumDelay.inMicroseconds),
    );
  }
}

final class P3e5ClaimResourcePolicy {
  const P3e5ClaimResourcePolicy({
    required this.version,
    required this.claimBatchSize,
    required this.pendingConsiderationLimit,
    required this.maximumActiveLeasesPerTenant,
    required this.recoveryScanBatch,
  });

  final int version;
  final int claimBatchSize;
  final int pendingConsiderationLimit;
  final int maximumActiveLeasesPerTenant;
  final int recoveryScanBatch;

  void validate(P3e5ScheduleLimits limits) {
    if (version != supportedP3e5ResourcePolicyVersion ||
        claimBatchSize <= 0 ||
        pendingConsiderationLimit < claimBatchSize ||
        maximumActiveLeasesPerTenant <= 0 ||
        recoveryScanBatch <= 0 ||
        claimBatchSize > limits.maximumPageSize ||
        pendingConsiderationLimit > limits.maximumPageSize ||
        recoveryScanBatch > limits.maximumPageSize) {
      throw const FormatException(
        'Unsupported or invalid claim resource policy',
      );
    }
  }
}

final class P3e5ClaimScope {
  const P3e5ClaimScope({
    required this.organizationId,
    required this.applicationId,
    required this.environmentId,
  });

  final String organizationId;
  final String applicationId;
  final String environmentId;

  bool contains(ScheduledEvaluationWork work) =>
      work.logicalKey.organizationId == organizationId &&
      work.logicalKey.applicationId == applicationId &&
      work.logicalKey.environmentId == environmentId;
}

final class P3e5PreparedLease {
  P3e5PreparedLease(String rawToken)
    : rawToken = _requireToken(rawToken),
      tokenDigest = sha256Digest(utf8.encode(rawToken));

  final String rawToken;
  final String tokenDigest;
}

final class P3e5ClaimRequest {
  P3e5ClaimRequest({
    required this.scope,
    required String leaseOwner,
    required this.leasePolicy,
    required this.resourcePolicy,
    required List<P3e5PreparedLease> preparedLeases,
  }) : leaseOwner = _bounded(leaseOwner, 'lease owner', 128),
       preparedLeases = List.unmodifiable(preparedLeases) {
    leasePolicy.validate();
    resourcePolicy.validate(const P3e5ScheduleLimits());
    if (this.preparedLeases.length < resourcePolicy.claimBatchSize) {
      throw const FormatException('Insufficient prepared lease tokens');
    }
    final digests = this.preparedLeases.map((item) => item.tokenDigest).toSet();
    if (digests.length != this.preparedLeases.length) {
      throw const FormatException('Duplicate prepared lease token');
    }
  }

  final P3e5ClaimScope scope;
  final String leaseOwner;
  final P3e5LeasePolicy leasePolicy;
  final P3e5ClaimResourcePolicy resourcePolicy;
  final List<P3e5PreparedLease> preparedLeases;
}

final class P3e5ClaimedWork {
  const P3e5ClaimedWork({
    required this.work,
    required this.rawLeaseToken,
    required this.reclaimed,
  });

  final ScheduledEvaluationWork work;
  final String rawLeaseToken;
  final bool reclaimed;
}

final class P3e5AutomaticHaltReclaimRequest {
  P3e5AutomaticHaltReclaimRequest({
    required this.scope,
    required String workId,
    required this.expectedWorkVersion,
    required String leaseOwner,
    required String rawLeaseToken,
    required this.leasePolicy,
  }) : workId = _bounded(workId, 'work ID', 160),
       leaseOwner = _bounded(leaseOwner, 'lease owner', 128),
       rawLeaseToken = _requireToken(rawLeaseToken) {
    if (expectedWorkVersion < 0) {
      throw const FormatException('Invalid automatic-halt recovery version');
    }
    leasePolicy.validate();
  }

  final P3e5ClaimScope scope;
  final String workId;
  final int expectedWorkVersion;
  final String leaseOwner;
  final String rawLeaseToken;
  final P3e5LeasePolicy leasePolicy;

  String get tokenDigest => sha256Digest(utf8.encode(rawLeaseToken));
}

final class P3e5AutomaticHaltRecoveryResult {
  const P3e5AutomaticHaltRecoveryResult({
    required this.outcome,
    required this.work,
    required this.application,
    required this.reclaimed,
    required this.attempts,
  });

  final P3e5AutomaticHaltRecoveryOutcome outcome;
  final ScheduledEvaluationWork? work;
  final HealthHaltApplication? application;
  final bool reclaimed;
  final int attempts;
}

final class P3e5LeaseMutation {
  P3e5LeaseMutation({
    required this.scope,
    required String workId,
    required this.expectedWorkVersion,
    required String leaseOwner,
    required String rawLeaseToken,
  }) : workId = _bounded(workId, 'work ID', 160),
       leaseOwner = _bounded(leaseOwner, 'lease owner', 128),
       rawLeaseToken = _requireToken(rawLeaseToken);

  final P3e5ClaimScope scope;
  final String workId;
  final int expectedWorkVersion;
  final String leaseOwner;
  final String rawLeaseToken;
  String get tokenDigest => sha256Digest(utf8.encode(rawLeaseToken));
}

final class P3e5RetryFailure {
  P3e5RetryFailure({required this.classification, required String safeCode})
    : safeCode = _bounded(safeCode, 'safe error code', 128);

  final P3e5RetryClass classification;
  final String safeCode;
}

final class P3e5WorkMutationResult {
  const P3e5WorkMutationResult(this.work, {required this.changed});
  final ScheduledEvaluationWork work;
  final bool changed;
}

/// Narrow proof presented to the schedule store after the existing P3E-4/P3A
/// path has produced an immutable, applied halt result. The schedule store
/// does not receive a rollout writer or raw health evidence; it only verifies
/// this bounded linkage against the current fenced work record.
final class P3e5AutomaticHaltCompletion {
  P3e5AutomaticHaltCompletion({
    required this.lease,
    required String intentDigest,
    required String haltApplicationId,
    required String idempotencyKey,
    required String evaluationId,
    required String decisionId,
    required this.previousRolloutRevision,
    required this.resultingRolloutRevision,
    required String resultingTransitionReference,
    required String result,
  }) : intentDigest = requireSha256Digest(intentDigest),
       haltApplicationId = requireNonEmpty(
         haltApplicationId,
         'halt application ID',
         maxLength: 128,
       ),
       idempotencyKey = requireNonEmpty(
         idempotencyKey,
         'halt application idempotency key',
         maxLength: 200,
       ),
       evaluationId = requireOpaqueId(evaluationId, 'evaluation ID'),
       decisionId = requireOpaqueId(decisionId, 'decision ID'),
       resultingTransitionReference = requireNonEmpty(
         resultingTransitionReference,
         'resulting transition reference',
         maxLength: 256,
       ),
       result = _automaticHaltCompletionResult(result) {
    if (previousRolloutRevision <= 0 || resultingRolloutRevision <= 0) {
      throw const FormatException('Automatic-halt rollout linkage is invalid');
    }
  }

  final P3e5LeaseMutation lease;
  final String intentDigest;
  final String haltApplicationId;
  final String idempotencyKey;
  final String evaluationId;
  final String decisionId;
  final int previousRolloutRevision;
  final int resultingRolloutRevision;
  final String resultingTransitionReference;
  final String result;
}

String _automaticHaltCompletionResult(String value) {
  if (value != 'APPLIED' && value != 'ALREADY_APPLIED') {
    throw const FormatException(
      'Automatic-halt completion requires an applied halt result',
    );
  }
  return value;
}

final class P3e5ExecutionAdvance {
  P3e5ExecutionAdvance({
    required this.lease,
    required this.expectedStatus,
    required this.nextStatus,
    this.aggregateId,
    this.aggregateRevisionId,
    this.evaluationId,
    this.decisionId,
  }) {
    validateScheduledEvaluationTransition(expectedStatus, nextStatus);
    if (nextStatus == ScheduledEvaluationWorkStatus.haltApplying) {
      throw const FormatException(
        'HALT_APPLYING requires the automatic-halt intent transition',
      );
    }
    if (expectedStatus == ScheduledEvaluationWorkStatus.haltApplying &&
        nextStatus == ScheduledEvaluationWorkStatus.completed) {
      throw const FormatException(
        'HALT_APPLYING completion requires verified halt application evidence',
      );
    }
    if (nextStatus == ScheduledEvaluationWorkStatus.evaluating &&
        (aggregateId == null || aggregateRevisionId == null)) {
      throw const FormatException('Evaluation aggregate link is required');
    }
    if ((aggregateId == null) != (aggregateRevisionId == null) ||
        (nextStatus == ScheduledEvaluationWorkStatus.evaluated &&
            (evaluationId == null || decisionId == null))) {
      throw const FormatException('Execution evidence link is inconsistent');
    }
  }

  final P3e5LeaseMutation lease;
  final ScheduledEvaluationWorkStatus expectedStatus;
  final ScheduledEvaluationWorkStatus nextStatus;
  final String? aggregateId;
  final String? aggregateRevisionId;
  final String? evaluationId;
  final String? decisionId;
}

String generateP3e5LeaseToken(Random random) {
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

ScheduledEvaluationAttempt claimedAttempt(
  ScheduledEvaluationWork work, {
  required String actorIdentity,
}) => ScheduledEvaluationAttempt(
  attemptId: deriveAttemptId(work.workId, work.attemptCount),
  workId: work.workId,
  attemptNumber: work.attemptCount,
  leaseOwner: work.leaseOwner,
  leaseTokenDigest: work.leaseTokenDigest,
  startedAt: work.leaseAcquiredAt!,
  finishedAt: null,
  outcome: work.status == ScheduledEvaluationWorkStatus.leased
      ? 'LEASED'
      : 'RECOVERED_${work.status.wireName}',
  errorClass: null,
  safeErrorCode: null,
  evaluationId: null,
  decisionId: null,
  haltApplicationId: null,
  actorIdentity: actorIdentity,
);

String _requireToken(String value) {
  final token = _bounded(value, 'lease token', 256);
  if (token.length < 32)
    throw const FormatException('Lease token is too short');
  return token;
}

String _bounded(String value, String label, int maximum) {
  if (value.isEmpty ||
      value.length > maximum ||
      value.contains(RegExp(r'[\x00-\x1f]'))) {
    throw FormatException('Invalid $label');
  }
  return value;
}
