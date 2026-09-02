import 'dart:convert';
import 'dart:math';

import 'aggregation.dart';
import 'auth.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'p3e_claim.dart';
import 'p3e_claim_service.dart';
import 'p3e_evaluation.dart';
import 'p3e_persistence.dart';
import 'p3e_schedule.dart';
import 'p3e_schedule_persistence.dart';
import 'persistence.dart';
import 'rollout.dart';
import 'service.dart';

const int supportedP3e5ExecutorPolicyVersion = 1;

enum P3e5CrossTenantFairness { roundRobinCursor }

final class P3e5FairnessCursor {
  const P3e5FairnessCursor._();

  static List<String> order(Iterable<String> scopeKeys, String? cursor) {
    final ordered = scopeKeys.toSet().toList()..sort();
    if (ordered.length != scopeKeys.length) {
      throw const FormatException('Duplicate executor tenant scope');
    }
    if (cursor == null) return List.unmodifiable(ordered);
    final index = ordered.indexOf(cursor);
    if (index < 0) throw const FormatException('Unknown fairness cursor');
    return List.unmodifiable(<String>[
      ...ordered.skip(index + 1),
      ...ordered.take(index + 1),
    ]);
  }
}

enum P3e5ExecutorFailurePoint {
  afterEvaluating,
  afterEvaluationCommit,
  afterEvaluated,
  beforeResponse,
}

final class P3e5ExecutorResourcePolicy {
  const P3e5ExecutorResourcePolicy({
    required this.version,
    required this.claimBatchSize,
    required this.maximumWorksPerInvocation,
    required this.maximumEvaluationDurationBudget,
    required this.maximumAggregateRecordsPerWork,
    required this.maximumRetriesProcessedPerInvocation,
    required this.maximumTenantScopes,
    required this.crossTenantFairness,
  });

  final int version;
  final int claimBatchSize;
  final int maximumWorksPerInvocation;
  final Duration maximumEvaluationDurationBudget;
  final int maximumAggregateRecordsPerWork;
  final int maximumRetriesProcessedPerInvocation;
  final int maximumTenantScopes;
  final P3e5CrossTenantFairness crossTenantFairness;

  void validate(P3e5ScheduleLimits limits) {
    if (version != supportedP3e5ExecutorPolicyVersion ||
        claimBatchSize <= 0 ||
        maximumWorksPerInvocation <= 0 ||
        maximumEvaluationDurationBudget <= Duration.zero ||
        maximumAggregateRecordsPerWork <= 0 ||
        maximumRetriesProcessedPerInvocation < maximumWorksPerInvocation ||
        maximumTenantScopes <= 0 ||
        claimBatchSize > limits.maximumPageSize ||
        maximumWorksPerInvocation > limits.maximumPageSize ||
        maximumAggregateRecordsPerWork > limits.maximumPageSize ||
        maximumTenantScopes > limits.maximumPageSize) {
      throw const FormatException('Unsupported or invalid executor policy');
    }
  }
}

final class P3e5TenantExecutionInput {
  const P3e5TenantExecutionInput({
    required this.token,
    required this.scope,
    required this.leaseOwner,
    required this.leasePolicy,
    required this.retryPolicy,
    required this.claimResourcePolicy,
    required this.evaluationPolicy,
  });

  final String token;
  final P3e5ClaimScope scope;
  final String leaseOwner;
  final P3e5LeasePolicy leasePolicy;
  final P3e5RetryPolicy retryPolicy;
  final P3e5ClaimResourcePolicy claimResourcePolicy;
  final ManualEvaluationPolicy evaluationPolicy;

  String get scopeKey =>
      '${scope.organizationId}/${scope.applicationId}/${scope.environmentId}';
}

final class P3e5ExecutionOutcome {
  const P3e5ExecutionOutcome({
    required this.work,
    required this.evaluation,
    required this.decision,
    required this.reusedEvaluation,
    required this.haltLease,
  });

  final ScheduledEvaluationWork work;
  final HealthEvaluation evaluation;
  final RolloutDecisionRecord decision;
  final bool reusedEvaluation;

  /// The still-valid evaluation lease is returned only when the decision is
  /// `HALT_NEW_OFFERS`. It is an in-process composition seam for the reviewed
  /// P3E5-3 → P3E5-4 coordinator; callers must not serialize or audit the raw
  /// token.
  final P3e5LeaseMutation? haltLease;
}

final class P3e5ExecutorInvocationResult {
  const P3e5ExecutorInvocationResult({
    required this.outcomes,
    required this.nextFairnessCursor,
    required this.scopesConsidered,
  });

  final List<P3e5ExecutionOutcome> outcomes;
  final String? nextFairnessCursor;
  final int scopesConsidered;
}

/// Explicit, bounded orchestration over P3E5-2 claims and the existing P3E-3
/// evaluator. It owns no timer, queue, halt authority, or runtime trust.
final class P3e5ExplicitExecutorService {
  P3e5ExplicitExecutorService({
    required this.controlStore,
    required this.scheduleStore,
    required this.p3eStore,
    required this.controlService,
    DateTime Function()? clock,
    Random? random,
    this.failure,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure(),
       _claimService = P3e5ClaimService(
         controlStore: controlStore,
         scheduleStore: scheduleStore,
         clock: clock,
         random: random,
       );

  final ControlPlaneStore controlStore;
  final P3e5ScheduleStore scheduleStore;
  final P3ePersistenceStore p3eStore;
  final ControlPlaneService controlService;
  final DateTime Function() _clock;
  final Random _random;
  final P3e5ClaimService _claimService;
  final void Function(P3e5ExecutorFailurePoint point)? failure;

  Future<P3e5ExecutorInvocationResult> invoke({
    required List<P3e5TenantExecutionInput> tenants,
    required P3e5ExecutorResourcePolicy resourcePolicy,
    String? fairnessCursor,
    String? requestId,
  }) async {
    resourcePolicy.validate(const P3e5ScheduleLimits());
    if (tenants.isEmpty ||
        tenants.length > resourcePolicy.maximumTenantScopes) {
      throw const FormatException('Executor tenant scope count is invalid');
    }
    final byScope = <String, P3e5TenantExecutionInput>{
      for (final tenant in tenants) tenant.scopeKey: tenant,
    };
    final orderedKeys = P3e5FairnessCursor.order(
      tenants.map((tenant) => tenant.scopeKey),
      null,
    );
    if (byScope.length != tenants.length) {
      throw const FormatException('Duplicate executor tenant scope');
    }
    final ordered = orderedKeys.map((key) => byScope[key]!).toList();
    for (final tenant in ordered) {
      await _authorize(tenant);
      tenant.leasePolicy.validate();
      tenant.retryPolicy.validate();
      tenant.claimResourcePolicy.validate(const P3e5ScheduleLimits());
      tenant.evaluationPolicy.validate();
    }
    final rotated = P3e5FairnessCursor.order(
      orderedKeys,
      fairnessCursor,
    ).map((key) => byScope[key]!).toList();
    final stopwatch = Stopwatch()..start();
    final outcomes = <P3e5ExecutionOutcome>[];
    final perTenant = <String, int>{};
    var scopesConsidered = 0;
    String? nextCursor = fairnessCursor;
    var progress = true;
    while (outcomes.length < resourcePolicy.maximumWorksPerInvocation &&
        progress) {
      progress = false;
      for (final tenant in rotated) {
        if (outcomes.length >= resourcePolicy.maximumWorksPerInvocation ||
            stopwatch.elapsed >=
                resourcePolicy.maximumEvaluationDurationBudget) {
          break;
        }
        nextCursor = tenant.scopeKey;
        scopesConsidered++;
        final used = perTenant[tenant.scopeKey] ?? 0;
        if (used >= resourcePolicy.claimBatchSize) continue;
        final claimPolicy = P3e5ClaimResourcePolicy(
          version: tenant.claimResourcePolicy.version,
          claimBatchSize: 1,
          pendingConsiderationLimit:
              tenant.claimResourcePolicy.pendingConsiderationLimit,
          maximumActiveLeasesPerTenant:
              tenant.claimResourcePolicy.maximumActiveLeasesPerTenant,
          recoveryScanBatch: tenant.claimResourcePolicy.recoveryScanBatch,
        );
        final claims = await _claimService.claimDue(
          token: tenant.token,
          scope: tenant.scope,
          leaseOwner: tenant.leaseOwner,
          leasePolicy: tenant.leasePolicy,
          retryPolicy: tenant.retryPolicy,
          resourcePolicy: claimPolicy,
          requestId: requestId,
        );
        if (claims.isEmpty) continue;
        progress = true;
        perTenant[tenant.scopeKey] = used + 1;
        final outcome = await _executeClaim(
          tenant,
          claims.single,
          resourcePolicy,
          requestId,
        );
        if (outcome != null) outcomes.add(outcome);
      }
    }
    failure?.call(P3e5ExecutorFailurePoint.beforeResponse);
    for (final tenant in ordered) {
      await _auditInvocation(
        tenant,
        requestId,
        perTenant[tenant.scopeKey] ?? 0,
        scopesConsidered,
      );
    }
    return P3e5ExecutorInvocationResult(
      outcomes: List.unmodifiable(outcomes),
      nextFairnessCursor: nextCursor,
      scopesConsidered: scopesConsidered,
    );
  }

  Future<P3e5ExecutionOutcome?> _executeClaim(
    P3e5TenantExecutionInput tenant,
    P3e5ClaimedWork claim,
    P3e5ExecutorResourcePolicy resourcePolicy,
    String? requestId,
  ) async {
    var work = claim.work;
    var lease = _lease(tenant, claim, work.workVersion);
    try {
      await _revalidate(work, tenant.evaluationPolicy);
      late final HealthAggregateRecord aggregate;
      late final HealthAggregateRevision revision;
      if (work.status == ScheduledEvaluationWorkStatus.leased) {
        (aggregate, revision) = await _selectAggregate(
          work,
          resourcePolicy.maximumAggregateRecordsPerWork,
        );
        work = (await scheduleStore.advanceExecution(
          P3e5ExecutionAdvance(
            lease: lease,
            expectedStatus: ScheduledEvaluationWorkStatus.leased,
            nextStatus: ScheduledEvaluationWorkStatus.evaluating,
            aggregateId: aggregate.aggregateId,
            aggregateRevisionId: revision.aggregateRevisionId,
          ),
        )).work;
        lease = _lease(tenant, claim, work.workVersion);
        await _auditWork(tenant, requestId, 'health.evaluation_started', work);
        failure?.call(P3e5ExecutorFailurePoint.afterEvaluating);
      } else {
        final linked = await _linkedAggregate(work);
        aggregate = linked.$1;
        revision = linked.$2;
      }
      _validateWindowReadiness(work, aggregate);

      if (work.status == ScheduledEvaluationWorkStatus.evaluated) {
        return await _completeRecovered(tenant, work, lease, requestId);
      }
      if (work.status != ScheduledEvaluationWorkStatus.evaluating) {
        throw const FormatException('Unsupported executor recovery state');
      }

      final request = _evaluationRequest(
        work,
        aggregate,
        revision,
        tenant.evaluationPolicy,
      );
      final snapshot = await controlService.evaluateHealth(
        token: tenant.token,
        rolloutId: work.logicalKey.rolloutId,
        organizationId: work.logicalKey.organizationId,
        request: request,
        idempotencyKey: work.logicalKey.evaluationIdempotencyKey,
        requestId: requestId,
      );
      failure?.call(P3e5ExecutorFailurePoint.afterEvaluationCommit);
      work = (await scheduleStore.advanceExecution(
        P3e5ExecutionAdvance(
          lease: lease,
          expectedStatus: ScheduledEvaluationWorkStatus.evaluating,
          nextStatus: ScheduledEvaluationWorkStatus.evaluated,
          evaluationId: snapshot.evaluation.evaluationId,
          decisionId: snapshot.decision.decisionId,
        ),
      )).work;
      lease = _lease(tenant, claim, work.workVersion);
      await _auditWork(
        tenant,
        requestId,
        snapshot.idempotentReplay
            ? 'health.evaluation_reused'
            : 'health.evaluation_completed',
        work,
      );
      failure?.call(P3e5ExecutorFailurePoint.afterEvaluated);
      if (snapshot.decision.decision == 'HALT_NEW_OFFERS') {
        await _auditWork(
          tenant,
          requestId,
          'health.evaluation_halt_ready',
          work,
        );
        return P3e5ExecutionOutcome(
          work: work,
          evaluation: snapshot.evaluation,
          decision: snapshot.decision,
          reusedEvaluation: snapshot.idempotentReplay,
          haltLease: lease,
        );
      }
      work = (await scheduleStore.advanceExecution(
        P3e5ExecutionAdvance(
          lease: lease,
          expectedStatus: ScheduledEvaluationWorkStatus.evaluated,
          nextStatus: ScheduledEvaluationWorkStatus.completed,
        ),
      )).work;
      return P3e5ExecutionOutcome(
        work: work,
        evaluation: snapshot.evaluation,
        decision: snapshot.decision,
        reusedEvaluation: snapshot.idempotentReplay,
        haltLease: null,
      );
    } on ControlPlaneException catch (error) {
      await _handleFailure(tenant, claim, work, error, requestId);
      return null;
    } on StorageConflict {
      rethrow;
    } on FormatException catch (error) {
      await _handleFailure(
        tenant,
        claim,
        work,
        ControlPlaneException(
          'HEALTH_EXECUTOR_EVIDENCE_INVALID',
          error.message,
          statusCode: 422,
        ),
        requestId,
      );
      return null;
    }
  }

  Future<P3e5ExecutionOutcome> _completeRecovered(
    P3e5TenantExecutionInput tenant,
    ScheduledEvaluationWork work,
    P3e5LeaseMutation lease,
    String? requestId,
  ) async {
    final evaluation = await p3eStore.readEvaluation(
      tenant.scope.organizationId,
      work.evaluationId!,
    );
    final decision = await p3eStore.readDecision(
      tenant.scope.organizationId,
      work.decisionId!,
    );
    if (evaluation == null || decision == null) {
      throw const FormatException('Linked evaluation evidence is missing');
    }
    final key = work.logicalKey;
    if (evaluation.organizationId != key.organizationId ||
        evaluation.rolloutId != key.rolloutId ||
        evaluation.rolloutRevision != key.rolloutRevision ||
        evaluation.aggregateRevisionId != work.aggregateRevisionId ||
        evaluation.targetBindingDigest != key.targetBindingDigest ||
        evaluation.decision != decision.decision ||
        decision.organizationId != key.organizationId ||
        decision.rolloutId != key.rolloutId ||
        decision.expectedRolloutRevision != key.rolloutRevision ||
        decision.evaluationId != evaluation.evaluationId ||
        decision.aggregateRevisionId != work.aggregateRevisionId ||
        decision.idempotencyKey != key.evaluationIdempotencyKey ||
        decision.resultingTransitionReference != null) {
      throw const FormatException('Linked evaluation evidence is invalid');
    }
    if (decision.decision != 'HALT_NEW_OFFERS') {
      work = (await scheduleStore.advanceExecution(
        P3e5ExecutionAdvance(
          lease: lease,
          expectedStatus: ScheduledEvaluationWorkStatus.evaluated,
          nextStatus: ScheduledEvaluationWorkStatus.completed,
        ),
      )).work;
    } else {
      await _auditWork(tenant, requestId, 'health.evaluation_halt_ready', work);
    }
    return P3e5ExecutionOutcome(
      work: work,
      evaluation: evaluation,
      decision: decision,
      reusedEvaluation: true,
      haltLease: decision.decision == 'HALT_NEW_OFFERS' ? lease : null,
    );
  }

  Future<void> _handleFailure(
    P3e5TenantExecutionInput tenant,
    P3e5ClaimedWork claim,
    ScheduledEvaluationWork work,
    ControlPlaneException error,
    String? requestId,
  ) async {
    final classification = error.code.contains('STALE')
        ? P3e5RetryClass.stale
        : error.statusCode >= 500
        ? P3e5RetryClass.transient
        : error.statusCode == 401 || error.statusCode == 403
        ? P3e5RetryClass.security
        : P3e5RetryClass.permanent;
    await _claimService.failClaim(
      token: tenant.token,
      scope: tenant.scope,
      lease: _lease(tenant, claim, work.workVersion),
      failure: P3e5RetryFailure(
        classification: classification,
        safeCode: error.code,
      ),
      retryPolicy: tenant.retryPolicy,
      requestId: requestId,
    );
  }

  Future<(HealthAggregateRecord, HealthAggregateRevision)> _selectAggregate(
    ScheduledEvaluationWork work,
    int maximumLoad,
  ) async {
    final values = await p3eStore.listAggregates(
      work.logicalKey.organizationId,
    );
    if (values.length > maximumLoad) {
      throw const ControlPlaneException(
        'HEALTH_EXECUTOR_RESOURCE_LIMIT',
        'Aggregate load exceeds the explicit executor policy',
        statusCode: 503,
      );
    }
    final matches = values
        .where((item) => _aggregateMatches(work, item))
        .toList();
    if (matches.length != 1) {
      throw const ControlPlaneException(
        'HEALTH_AGGREGATE_NOT_FOUND',
        'Exactly one bound aggregate is required',
        statusCode: 422,
      );
    }
    final aggregate = matches.single;
    final revision = await p3eStore.readAggregateRevision(
      work.logicalKey.organizationId,
      aggregate.revisionId,
    );
    if (revision == null || revision.aggregateId != aggregate.aggregateId) {
      throw const ControlPlaneException(
        'HEALTH_AGGREGATE_NOT_FOUND',
        'Bound aggregate revision is missing',
        statusCode: 422,
      );
    }
    return (aggregate, revision);
  }

  Future<(HealthAggregateRecord, HealthAggregateRevision)> _linkedAggregate(
    ScheduledEvaluationWork work,
  ) async {
    if (work.aggregateId == null || work.aggregateRevisionId == null) {
      throw const FormatException('Work has no persisted aggregate link');
    }
    final aggregate = await p3eStore.readAggregate(
      work.logicalKey.organizationId,
      work.aggregateId!,
    );
    final revision = await p3eStore.readAggregateRevision(
      work.logicalKey.organizationId,
      work.aggregateRevisionId!,
    );
    if (aggregate == null ||
        revision == null ||
        revision.aggregateId != aggregate.aggregateId ||
        revision.aggregateRevisionId != aggregate.revisionId ||
        revision.identity.canonicalSerialization !=
            aggregate.aggregate.identity.canonicalSerialization ||
        !_aggregateMatches(work, aggregate)) {
      throw const FormatException('Persisted aggregate link is invalid');
    }
    return (aggregate, revision);
  }

  bool _aggregateMatches(
    ScheduledEvaluationWork work,
    HealthAggregateRecord aggregate,
  ) {
    final key = work.logicalKey;
    final identity = aggregate.aggregate.identity;
    return identity.organizationId == key.organizationId &&
        identity.applicationId == key.applicationId &&
        identity.environmentId == key.environmentId &&
        identity.platformId == key.platformId &&
        identity.rolloutId == key.rolloutId &&
        identity.rolloutRevision == key.rolloutRevision &&
        identity.releaseId == key.releaseId &&
        identity.patchId == key.patchId &&
        identity.sequence == key.sequence &&
        identity.windowId == key.windowId &&
        identity.aggregationVersion == key.aggregationVersion &&
        aggregate.aggregate.policyDigest == key.aggregatePolicyDigest;
  }

  void _validateWindowReadiness(
    ScheduledEvaluationWork work,
    HealthAggregateRecord aggregate,
  ) {
    final authoritativeClaimTime = work.leaseAcquiredAt;
    if (authoritativeClaimTime == null) {
      throw const FormatException(
        'Executor work has no authoritative claim time',
      );
    }
    final phase = aggregate.aggregate.window.phaseAt(authoritativeClaimTime);
    final ready = switch (work.logicalKey.readinessPhase) {
      EvaluationReadinessPhase.closed =>
        phase == AggregationWindowPhase.closed ||
            phase == AggregationWindowPhase.sealed,
      EvaluationReadinessPhase.sealed => phase == AggregationWindowPhase.sealed,
    };
    final earliest = switch (work.logicalKey.readinessPhase) {
      EvaluationReadinessPhase.closed => aggregate.aggregate.window.serverEnd,
      EvaluationReadinessPhase.sealed => aggregate.aggregate.window.lateCutoff,
    };
    if (!ready || work.notBefore.isBefore(earliest)) {
      throw const ControlPlaneException(
        'HEALTH_EXECUTOR_WINDOW_NOT_READY',
        'Scheduled aggregate window is not ready',
        statusCode: 409,
      );
    }
  }

  ManualEvaluationRequest _evaluationRequest(
    ScheduledEvaluationWork work,
    HealthAggregateRecord aggregate,
    HealthAggregateRevision revision,
    ManualEvaluationPolicy policy,
  ) => ManualEvaluationRequest(
    organizationId: work.logicalKey.organizationId,
    applicationId: work.logicalKey.applicationId,
    environmentId: work.logicalKey.environmentId,
    platformId: work.logicalKey.platformId,
    rolloutId: work.logicalKey.rolloutId,
    rolloutRevision: work.logicalKey.rolloutRevision,
    aggregationVersion: work.logicalKey.aggregationVersion,
    aggregateId: aggregate.aggregateId,
    aggregateRevisionId: revision.aggregateRevisionId,
    releaseId: work.logicalKey.releaseId,
    patchId: work.logicalKey.patchId,
    sequence: work.logicalKey.sequence,
    windowId: work.logicalKey.windowId,
    aggregateInputDigest: revision.inputDigest,
    aggregatePolicyDigest: work.logicalKey.aggregatePolicyDigest,
    policyDigest: work.logicalKey.evaluationPolicyDigest,
    policy: policy,
  );

  Future<void> _revalidate(
    ScheduledEvaluationWork work,
    ManualEvaluationPolicy policy,
  ) async {
    final key = work.logicalKey;
    final schedule = await scheduleStore.readSchedule(
      key.organizationId,
      key.scheduleId,
    );
    final revision = await scheduleStore.readRevision(
      key.organizationId,
      key.scheduleRevisionId,
    );
    if (schedule == null ||
        revision == null ||
        schedule.currentScheduleRevision != key.scheduleRevisionId ||
        !revision.scheduledEvaluationEnabled ||
        revision.scheduleGeneration != key.scheduleGeneration ||
        revision.readinessPhase != key.readinessPhase ||
        revision.evaluationPolicyVersion != key.evaluationPolicyVersion ||
        revision.evaluationPolicyDigest != key.evaluationPolicyDigest ||
        revision.thresholdSetVersion != key.thresholdSetVersion ||
        revision.thresholdSetDigest != key.thresholdSetDigest ||
        revision.windowPolicyVersion != key.windowPolicyVersion ||
        revision.privacyPolicyVersion != key.privacyPolicyVersion ||
        policy.evaluationVersion != key.evaluationPolicyVersion ||
        policy.policyDigest != key.evaluationPolicyDigest ||
        policy.thresholdSetVersion != key.thresholdSetVersion ||
        policy.thresholdSetDigest != key.thresholdSetDigest ||
        policy.windowPolicyVersion != key.windowPolicyVersion ||
        policy.privacyPolicyVersion != key.privacyPolicyVersion) {
      throw const ControlPlaneException(
        'HEALTH_EXECUTOR_STALE',
        'Scheduled evaluation binding is stale',
        statusCode: 409,
      );
    }
    final rolloutRaw = await controlStore.readJson('rollouts', key.rolloutId);
    if (rolloutRaw == null) {
      throw const ControlPlaneException(
        'HEALTH_EXECUTOR_STALE',
        'Scheduled rollout is stale',
        statusCode: 409,
      );
    }
    final rollout = RolloutRecord.fromJson(rolloutRaw);
    final revisions = (await controlStore.listJson('rollout_revisions'))
        .where(
          (raw) =>
              raw['rolloutId'] == rollout.id &&
              raw['revision'] == rollout.currentRevision,
        )
        .map(RolloutRevision.fromJson)
        .toList(growable: false);
    if (rollout.organizationId != key.organizationId ||
        rollout.currentRevision != key.rolloutRevision ||
        !rollout.state.servesCandidate ||
        revisions.length != 1) {
      throw const ControlPlaneException(
        'HEALTH_EXECUTOR_STALE',
        'Scheduled rollout revision is stale',
        statusCode: 409,
      );
    }
    final target = revisions.single.target;
    if (target.applicationId != key.applicationId ||
        target.environmentId != key.environmentId ||
        target.platformId != key.platformId ||
        target.releaseId != key.releaseId ||
        target.patchId != key.patchId ||
        target.sequence != key.sequence ||
        sha256Digest(utf8.encode(canonicalJson(target.toJson()))) !=
            key.targetBindingDigest) {
      throw const ControlPlaneException(
        'HEALTH_EXECUTOR_STALE',
        'Scheduled rollout target is stale',
        statusCode: 409,
      );
    }
  }

  Future<CredentialRecord> _authorize(P3e5TenantExecutionInput tenant) async {
    final actor = await CredentialService.authorize(
      token: tenant.token,
      requiredScope: 'health:work:claim',
      read: (hash) async {
        final raw = await controlStore.readJson('credentials', hash);
        return raw == null ? null : CredentialRecord.fromJson(raw);
      },
      organizationId: tenant.scope.organizationId,
      applicationId: tenant.scope.applicationId,
      environmentId: tenant.scope.environmentId,
      kind: CredentialKind.scheduler,
      now: _clock().toUtc(),
    );
    if (!actor.scopes.containsAll(const {
      'health:evaluate',
      'observation:read',
      'rollout:read',
    })) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'Executor credential lacks required read/evaluate scopes',
        statusCode: 403,
      );
    }
    return actor;
  }

  P3e5LeaseMutation _lease(
    P3e5TenantExecutionInput tenant,
    P3e5ClaimedWork claim,
    int version,
  ) => P3e5LeaseMutation(
    scope: tenant.scope,
    workId: claim.work.workId,
    expectedWorkVersion: version,
    leaseOwner: tenant.leaseOwner,
    rawLeaseToken: claim.rawLeaseToken,
  );

  Future<void> _auditInvocation(
    P3e5TenantExecutionInput tenant,
    String? requestId,
    int outcomes,
    int considered,
  ) async {
    final actor = await _authorize(tenant);
    final id = _id('audit');
    await controlStore.appendAudit(
      id,
      AuditRecord(
        id: id,
        requestId: requestId ?? _id('request'),
        organizationId: actor.organizationId,
        actorId: actor.id,
        action: 'health.executor_invoked',
        resourceType: 'scheduled_evaluation_executor',
        resourceId: tenant.scopeKey.replaceAll('/', ':'),
        result: 'SUCCESS',
        metadata: <String, Object?>{
          'outcomeCount': outcomes,
          'scopesConsidered': considered,
        },
        createdAt: _clock().toUtc(),
      ).toJson(),
    );
  }

  Future<void> _auditWork(
    P3e5TenantExecutionInput tenant,
    String? requestId,
    String action,
    ScheduledEvaluationWork work,
  ) async {
    final actor = await _authorize(tenant);
    final id = _id('audit');
    await controlStore.appendAudit(
      id,
      AuditRecord(
        id: id,
        requestId: requestId ?? _id('request'),
        organizationId: actor.organizationId,
        actorId: actor.id,
        action: action,
        resourceType: 'scheduled_evaluation_work',
        resourceId: work.workId,
        result: 'SUCCESS',
        metadata: <String, Object?>{
          'workVersion': work.workVersion,
          'attemptNumber': work.attemptCount,
          if (work.evaluationId != null) 'evaluationId': work.evaluationId,
          if (work.decisionId != null) 'decisionId': work.decisionId,
        },
        createdAt: _clock().toUtc(),
      ).toJson(),
    );
  }

  String _id(String prefix) {
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return '${prefix}_${bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
