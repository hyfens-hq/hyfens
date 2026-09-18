import 'dart:convert';

import 'audit.dart';
import 'encoding.dart';
import 'errors.dart';
import 'p3e_claim.dart';
import 'p3e_halt.dart';
import 'p3e_persistence.dart';
import 'p3e_schedule.dart';
import 'p3e_schedule_persistence.dart';
import 'persistence.dart';
import 'reconciliation_domain.dart';
import 'reconciliation_persistence.dart';
import 'rollout.dart';

/// Reads the existing P3E and scheduled-evaluation stores and translates only
/// observed divergences into the frozen P3E5-5A taxonomy. This class has no
/// writer, rollout authority, or P3E-4 authority.
final class AuthoritativeReconciliationCandidateSource
    implements ReconciliationCandidateSource {
  AuthoritativeReconciliationCandidateSource({
    required this.p3eStore,
    required this.scheduleStore,
    this.controlStore,
    this.retryPolicy,
  });

  final P3ePersistenceStore p3eStore;
  final P3e5ScheduleStore scheduleStore;
  final ControlPlaneStore? controlStore;
  final P3e5RetryPolicy? retryPolicy;

  @override
  Future<List<ReconciliationCandidate>> discover(
    ReconciliationInvocation invocation,
  ) async {
    final findings = <ReconciliationCandidate>[];
    final seen = <String, ReconciliationCandidate>{};
    void add(ReconciliationCandidate candidate) {
      final previous = seen[candidate.finding.findingId];
      if (previous == null) {
        seen[candidate.finding.findingId] = candidate;
      } else if (previous.finding.canonicalSerialization !=
          candidate.finding.canonicalSerialization) {
        throw const StorageConflict(
          'Authoritative reconciliation detectors disagree',
        );
      }
    }

    final context = await _readContext(invocation);
    for (final candidate in _scheduleFindings(invocation, context)) {
      add(candidate);
    }
    for (final candidate in _p3eFindings(invocation, context)) {
      add(candidate);
    }
    for (final candidate in _rolloutFindings(invocation, context)) {
      add(candidate);
    }
    for (final candidate in _auditFindings(invocation, context)) {
      add(candidate);
    }
    findings.addAll(seen.values);
    findings.sort(
      (left, right) =>
          left.finding.findingId.compareTo(right.finding.findingId),
    );
    return List.unmodifiable(findings);
  }

  Future<_AuthoritativeContext> _readContext(
    ReconciliationInvocation invocation,
  ) async {
    final organizationId = invocation.scope.organizationId;
    final schedules = await scheduleStore.listSchedules(organizationId);
    final work = await scheduleStore.listWork(organizationId);
    final consistency = await scheduleStore.validateConsistency(organizationId);
    final aggregates = await p3eStore.listAggregates(organizationId);
    final revisions = await p3eStore.listAggregateRevisions(organizationId);
    final evaluations = await p3eStore.listEvaluations(organizationId);
    final decisions = await p3eStore.listDecisions(organizationId);
    final applications = await p3eStore.listHaltApplications(organizationId);
    final report = await p3eStore.reconcile(organizationId);
    final rollouts = <RolloutRecord>[];
    final rolloutRevisions = <RolloutRevision>[];
    final malformedRollouts = <_MalformedAuthoritativeRecord>[];
    final auditChain = controlStore == null
        ? const <Map<String, Object?>>[]
        : await controlStore!.readAuditChain();
    if (controlStore != null) {
      for (final raw in await controlStore!.listJson('rollouts')) {
        try {
          rollouts.add(RolloutRecord.fromJson(raw));
        } on Object catch (error) {
          malformedRollouts.add(
            _MalformedAuthoritativeRecord(
              entityType: 'rollout',
              entityId: _rawEntityId(raw, 'rollout'),
              raw: raw,
              error: error,
            ),
          );
        }
      }
      for (final raw in await controlStore!.listJson('rollout_revisions')) {
        try {
          rolloutRevisions.add(RolloutRevision.fromJson(raw));
        } on Object catch (error) {
          malformedRollouts.add(
            _MalformedAuthoritativeRecord(
              entityType: 'rollout_revision',
              entityId: _rawEntityId(raw, 'rollout_revision'),
              raw: raw,
              error: error,
            ),
          );
        }
      }
    }
    return _AuthoritativeContext(
      schedules: schedules,
      work: work,
      consistency: consistency,
      aggregates: aggregates,
      revisions: revisions,
      evaluations: evaluations,
      decisions: decisions,
      applications: applications,
      report: report,
      rollouts: rollouts,
      rolloutRevisions: rolloutRevisions,
      malformedRollouts: malformedRollouts,
      auditChain: auditChain,
    );
  }

  Iterable<ReconciliationCandidate> _scheduleFindings(
    ReconciliationInvocation invocation,
    _AuthoritativeContext context,
  ) sync* {
    final schedulesById = <String, EvaluationSchedule>{
      for (final schedule in context.schedules) schedule.scheduleId: schedule,
    };
    for (final issue in context.consistency) {
      final work = context.work.where((item) => item.workId == issue.entityId);
      final schedule = context.schedules.where(
        (item) => item.scheduleId == issue.entityId,
      );
      final record = work.isNotEmpty ? work.single : null;
      final scheduleRecord = schedule.isNotEmpty ? schedule.single : null;
      if (record == null &&
          scheduleRecord == null &&
          invocation.scope.applicationId != null) {
        // A narrow application/environment invocation must not attribute an
        // attempt-only or otherwise unbound issue to the requested tenant.
        continue;
      }
      final scope = _scopeFor(
        invocation.scope,
        record?.logicalKey.organizationId ??
            scheduleRecord?.organizationId ??
            invocation.scope.organizationId,
        record?.logicalKey.applicationId ?? scheduleRecord?.applicationId,
        record?.logicalKey.environmentId ?? scheduleRecord?.environmentId,
      );
      if (!_within(invocation.scope, scope)) continue;
      final code = switch (issue.code) {
        'INVALID_CURRENT_REVISION' =>
          ReconciliationTaxonomyCode.scheduleWorkVersionMismatch,
        'SCOPE_MISMATCH' => ReconciliationTaxonomyCode.tenantScopeMismatch,
        'MISSING_SCHEDULE_REVISION' => ReconciliationTaxonomyCode.orphanWork,
        'BINDING_MISMATCH' => ReconciliationTaxonomyCode.workLogicalKeyMismatch,
        'WORK_MISMATCH' => ReconciliationTaxonomyCode.orphanWork,
        _ => ReconciliationTaxonomyCode.unknownVersion,
      };
      final source = <String, String>{
        'schedule': _digestOf(
          record?.logicalKey.toJson() ?? scheduleRecord?.toJson() ?? issue.code,
        ),
        'consistency': _digestOf(<String, Object?>{
          'entityType': issue.entityType,
          'entityId': issue.entityId,
          'code': issue.code,
        }),
      };
      final observed = <String, int>{
        if (record != null) 'work': record.workVersion,
        if (scheduleRecord != null)
          'schedule': _scheduleVersion(scheduleRecord, schedulesById),
      };
      yield _candidate(
        invocation: invocation,
        scope: scope,
        code: code,
        entityType: issue.entityType,
        entityId: issue.entityId,
        sourceDigests: source,
        observedVersions: observed,
        observedAt: record?.updatedAt ?? invocation.startedAt,
        safeDetailCode: 'SCHEDULE_${issue.code}',
      );
    }

    final evaluationById = <String, HealthEvaluation>{
      for (final evaluation in context.evaluations)
        evaluation.evaluationId: evaluation,
    };
    final decisionById = <String, RolloutDecisionRecord>{
      for (final decision in context.decisions) decision.decisionId: decision,
    };
    final applicationById = <String, HealthHaltApplication>{
      for (final application in context.applications)
        application.applicationId: application,
    };
    for (final work in context.work) {
      final scope = _scopeFor(
        invocation.scope,
        work.logicalKey.organizationId,
        work.logicalKey.applicationId,
        work.logicalKey.environmentId,
      );
      if (!_within(invocation.scope, scope)) continue;
      final evaluation = work.evaluationId == null
          ? null
          : evaluationById[work.evaluationId];
      final decision = work.decisionId == null
          ? null
          : decisionById[work.decisionId];
      if (work.status.index >= ScheduledEvaluationWorkStatus.evaluated.index &&
          work.evaluationId == null) {
        yield _candidate(
          invocation: invocation,
          scope: scope,
          code: ReconciliationTaxonomyCode.workEvaluationLinkMissing,
          entityType: 'work',
          entityId: work.workId,
          sourceDigests: <String, String>{'work': _digestOf(work.toJson())},
          observedVersions: <String, int>{'work': work.workVersion},
          observedAt: work.updatedAt,
          safeDetailCode: 'WORK_EVALUATION_LINK_MISSING',
          precondition: null,
        );
      }
      if (work.status.index >= ScheduledEvaluationWorkStatus.evaluated.index &&
          work.decisionId == null) {
        yield _candidate(
          invocation: invocation,
          scope: scope,
          code: ReconciliationTaxonomyCode.workDecisionLinkMissing,
          entityType: 'work',
          entityId: work.workId,
          sourceDigests: <String, String>{'work': _digestOf(work.toJson())},
          observedVersions: <String, int>{'work': work.workVersion},
          observedAt: work.updatedAt,
          safeDetailCode: 'WORK_DECISION_LINK_MISSING',
        );
      }
      if (work.status == ScheduledEvaluationWorkStatus.evaluating &&
          work.aggregateRevisionId != null &&
          work.evaluationId == null) {
        final matchingEvaluations = context.evaluations.where(
          (item) =>
              item.organizationId == scope.organizationId &&
              item.aggregateRevisionId == work.aggregateRevisionId &&
              item.rolloutId == work.logicalKey.rolloutId &&
              item.rolloutRevision == work.logicalKey.rolloutRevision &&
              (item.targetBindingDigest == null ||
                  item.targetBindingDigest ==
                      work.logicalKey.targetBindingDigest),
        );
        final matching = matchingEvaluations
            .where(
              (item) => context.decisions.any(
                (decision) =>
                    decision.organizationId == scope.organizationId &&
                    decision.evaluationId == item.evaluationId &&
                    decision.aggregateRevisionId == item.aggregateRevisionId &&
                    decision.rolloutId == item.rolloutId &&
                    decision.expectedRolloutRevision == item.rolloutRevision,
              ),
            )
            .toList(growable: false);
        if (matching.length == 1) {
          final selected = matching.single;
          final selectedDecision = context.decisions
              .where((item) => item.evaluationId == selected.evaluationId)
              .single;
          final source = <String, String>{
            'work': _digestOf(work.toJson()),
            'evaluation': _digestOf(selected.toJson()),
            'decision': _digestOf(selectedDecision.toJson()),
          };
          yield _candidate(
            invocation: invocation,
            scope: scope,
            code: ReconciliationTaxonomyCode.workEvaluationLinkMissing,
            entityType: 'work',
            entityId: work.workId,
            sourceDigests: source,
            observedVersions: <String, int>{'work': work.workVersion},
            observedAt: work.updatedAt,
            safeDetailCode: 'WORK_EVALUATION_LINK_RECOVERABLE',
            precondition: ReconciliationPrecondition(
              scope: scope,
              findingId: 'pending-finding',
              entityId: work.workId,
              expectedWorkVersion: work.workVersion,
              expectedScheduleRevision: work.logicalKey.scheduleRevisionId,
              currentRolloutRevision: work.logicalKey.rolloutRevision
                  .toString(),
              sourceDigests: source,
              targetBinding: <String, String>{
                'work_id': work.workId,
                'aggregate_id': work.aggregateId!,
                'aggregate_revision_id': work.aggregateRevisionId!,
                'evaluation_id': selected.evaluationId,
                'decision_id': selectedDecision.decisionId,
              },
              taxonomyCode:
                  ReconciliationTaxonomyCode.workEvaluationLinkMissing,
              action: ReconciliationRepairAction.linkExistingEvaluation,
            ),
          );
        }
      }
      if (work.status == ScheduledEvaluationWorkStatus.haltApplying &&
          work.automaticHaltIntent != null &&
          work.haltApplicationId == null) {
        final intent = work.automaticHaltIntent!;
        final application = context.applications.where(
          (item) =>
              item.organizationId == scope.organizationId &&
              item.decisionId == intent.decisionId &&
              item.evaluationId == intent.evaluationId &&
              item.aggregateRevisionId == work.aggregateRevisionId &&
              item.rolloutId == work.logicalKey.rolloutId &&
              item.expectedRolloutRevision == intent.expectedRolloutRevision &&
              item.idempotencyKey == work.logicalKey.haltIdempotencyKey &&
              item.applied &&
              item.previousRolloutRevision == intent.expectedRolloutRevision &&
              item.resultingRolloutRevision ==
                  intent.expectedRolloutRevision + 1 &&
              item.resultingTransitionReference != null,
        );
        if (application.length == 1) {
          final selected = application.single;
          final source = <String, String>{
            'work': _digestOf(work.toJson()),
            'haltApplication': _digestOf(selected.toJson()),
          };
          yield _candidate(
            invocation: invocation,
            scope: scope,
            code: ReconciliationTaxonomyCode.workHaltApplicationLinkMissing,
            entityType: 'work',
            entityId: work.workId,
            sourceDigests: source,
            observedVersions: <String, int>{'work': work.workVersion},
            observedAt: work.updatedAt,
            safeDetailCode: 'WORK_HALT_APPLICATION_LINK_RECOVERABLE',
            precondition: ReconciliationPrecondition(
              scope: scope,
              findingId: '',
              entityId: work.workId,
              expectedWorkVersion: work.workVersion,
              expectedScheduleRevision: work.logicalKey.scheduleRevisionId,
              currentRolloutRevision: work.logicalKey.rolloutRevision
                  .toString(),
              sourceDigests: source,
              targetBinding: <String, String>{
                'work_id': work.workId,
                'halt_application_id': selected.applicationId,
                'evaluation_id': selected.evaluationId,
                'decision_id': selected.decisionId,
                'resulting_transition_reference':
                    selected.resultingTransitionReference!,
              },
              taxonomyCode:
                  ReconciliationTaxonomyCode.workHaltApplicationLinkMissing,
              action: ReconciliationRepairAction.linkExistingHaltApplication,
            ),
          );
        }
      }
      if (_isActiveLease(work.status) &&
          work.leaseExpiresAt != null &&
          !work.leaseExpiresAt!.isAfter(invocation.startedAt)) {
        yield _candidate(
          invocation: invocation,
          scope: scope,
          code: ReconciliationTaxonomyCode.expiredLease,
          entityType: 'work',
          entityId: work.workId,
          sourceDigests: <String, String>{'work': _digestOf(work.toJson())},
          observedVersions: <String, int>{'work': work.workVersion},
          observedAt: work.updatedAt,
          safeDetailCode: 'EXPIRED_LEASE',
        );
      }
      if (_isActiveLease(work.status) &&
          work.status != ScheduledEvaluationWorkStatus.haltApplying &&
          retryPolicy != null &&
          work.attemptCount >= retryPolicy!.maximumAttempts) {
        final source = <String, String>{'work': _digestOf(work.toJson())};
        yield _candidate(
          invocation: invocation,
          scope: scope,
          code: ReconciliationTaxonomyCode.retryExhausted,
          entityType: 'work',
          entityId: work.workId,
          sourceDigests: source,
          observedVersions: <String, int>{'work': work.workVersion},
          observedAt: work.updatedAt,
          safeDetailCode: 'RETRY_EXHAUSTED',
          precondition: ReconciliationPrecondition(
            scope: scope,
            findingId: 'pending-finding',
            entityId: work.workId,
            expectedWorkVersion: work.workVersion,
            expectedScheduleRevision: work.logicalKey.scheduleRevisionId,
            currentRolloutRevision: work.logicalKey.rolloutRevision.toString(),
            sourceDigests: source,
            targetBinding: <String, String>{
              'work_id': work.workId,
              'status': work.status.wireName,
            },
            taxonomyCode: ReconciliationTaxonomyCode.retryExhausted,
            action: ReconciliationRepairAction.markFailedPermanent,
          ),
        );
      }
      final schedule = schedulesById[work.logicalKey.scheduleId];
      if (work.status == ScheduledEvaluationWorkStatus.haltApplying &&
          work.leaseExpiresAt != null &&
          schedule != null &&
          schedule.currentScheduleRevision !=
              work.logicalKey.scheduleRevisionId) {
        final source = <String, String>{
          'work': _digestOf(work.toJson()),
          'schedule': _digestOf(schedule.toJson()),
        };
        yield _candidate(
          invocation: invocation,
          scope: scope,
          code: ReconciliationTaxonomyCode.staleActiveWork,
          entityType: 'work',
          entityId: work.workId,
          sourceDigests: source,
          observedVersions: <String, int>{'work': work.workVersion},
          observedAt: work.updatedAt,
          safeDetailCode: 'STALE_ACTIVE_WORK',
          precondition: ReconciliationPrecondition(
            scope: scope,
            findingId: 'pending-finding',
            entityId: work.workId,
            expectedWorkVersion: work.workVersion,
            expectedScheduleRevision: work.logicalKey.scheduleRevisionId,
            currentRolloutRevision: work.logicalKey.rolloutRevision.toString(),
            sourceDigests: source,
            targetBinding: <String, String>{
              'work_id': work.workId,
              'status': work.status.wireName,
              'schedule_revision_id': work.logicalKey.scheduleRevisionId,
            },
            taxonomyCode: ReconciliationTaxonomyCode.staleActiveWork,
            action: ReconciliationRepairAction.markStale,
          ),
        );
      }
      if (work.logicalKey.organizationId != scope.organizationId ||
          work.logicalKey.applicationId != scope.applicationId ||
          work.logicalKey.environmentId != scope.environmentId) {
        yield _candidate(
          invocation: invocation,
          scope: scope,
          code: ReconciliationTaxonomyCode.tenantScopeMismatch,
          entityType: 'work',
          entityId: work.workId,
          sourceDigests: <String, String>{'work': _digestOf(work.toJson())},
          observedVersions: <String, int>{'work': work.workVersion},
          observedAt: work.updatedAt,
          safeDetailCode: 'WORK_TENANT_SCOPE_MISMATCH',
        );
      }
      if (evaluation != null &&
          evaluation.targetBindingDigest != null &&
          evaluation.targetBindingDigest !=
              work.logicalKey.targetBindingDigest) {
        yield _candidate(
          invocation: invocation,
          scope: scope,
          code: ReconciliationTaxonomyCode.targetBindingMismatch,
          entityType: 'work',
          entityId: work.workId,
          sourceDigests: <String, String>{
            'work': _digestOf(work.toJson()),
            'evaluation': _digestOf(evaluation.toJson()),
          },
          observedVersions: <String, int>{'work': work.workVersion},
          observedAt: work.updatedAt,
          safeDetailCode: 'WORK_TARGET_BINDING_MISMATCH',
        );
      }
      if (decision != null &&
          evaluation != null &&
          decision.evaluationId != evaluation.evaluationId) {
        yield _candidate(
          invocation: invocation,
          scope: scope,
          code: ReconciliationTaxonomyCode.workDecisionLinkMissing,
          entityType: 'work',
          entityId: work.workId,
          sourceDigests: <String, String>{
            'work': _digestOf(work.toJson()),
            'decision': _digestOf(decision.toJson()),
          },
          observedVersions: <String, int>{'work': work.workVersion},
          observedAt: work.updatedAt,
          safeDetailCode: 'WORK_DECISION_LINK_MISMATCH',
        );
      }
      final applicationId = work.haltApplicationId;
      if (applicationId != null && applicationById[applicationId] == null) {
        yield _candidate(
          invocation: invocation,
          scope: scope,
          code: ReconciliationTaxonomyCode.orphanApplication,
          entityType: 'halt_application',
          entityId: applicationId,
          sourceDigests: <String, String>{'work': _digestOf(work.toJson())},
          observedVersions: <String, int>{'work': work.workVersion},
          observedAt: work.updatedAt,
          safeDetailCode: 'HALT_APPLICATION_REFERENCE_MISSING',
        );
      }
    }
  }

  Iterable<ReconciliationCandidate> _p3eFindings(
    ReconciliationInvocation invocation,
    _AuthoritativeContext context,
  ) sync* {
    final aggregateById = <String, HealthAggregateRecord>{
      for (final aggregate in context.aggregates)
        aggregate.aggregateId: aggregate,
    };
    final revisionById = <String, HealthAggregateRevision>{
      for (final revision in context.revisions)
        revision.aggregateRevisionId: revision,
    };
    final evaluationById = <String, HealthEvaluation>{
      for (final evaluation in context.evaluations)
        evaluation.evaluationId: evaluation,
    };
    final decisionById = <String, RolloutDecisionRecord>{
      for (final decision in context.decisions) decision.decisionId: decision,
    };
    ReconciliationScope scopeForIssue(P3eReconciliationIssue issue) {
      final applicationId = switch (issue.entityType) {
        'aggregate' =>
          aggregateById[issue.entityId]?.aggregate.identity.applicationId,
        'revision' => revisionById[issue.entityId]?.identity.applicationId,
        'evaluation' =>
          revisionById[evaluationById[issue.entityId]?.aggregateRevisionId]
              ?.identity
              .applicationId,
        'decision' =>
          revisionById[evaluationById[decisionById[issue.entityId]
                      ?.evaluationId]
                  ?.aggregateRevisionId]
              ?.identity
              .applicationId,
        'halt_application' =>
          revisionById[evaluationById[decisionById[issue.entityId]
                      ?.evaluationId]
                  ?.aggregateRevisionId]
              ?.identity
              .applicationId,
        'cursor' =>
          aggregateById[issue.entityId]?.aggregate.identity.applicationId,
        _ => null,
      };
      final environmentId = switch (issue.entityType) {
        'aggregate' =>
          aggregateById[issue.entityId]?.aggregate.identity.environmentId,
        'revision' => revisionById[issue.entityId]?.identity.environmentId,
        'evaluation' =>
          revisionById[evaluationById[issue.entityId]?.aggregateRevisionId]
              ?.identity
              .environmentId,
        'decision' =>
          revisionById[evaluationById[decisionById[issue.entityId]
                      ?.evaluationId]
                  ?.aggregateRevisionId]
              ?.identity
              .environmentId,
        'halt_application' =>
          revisionById[evaluationById[decisionById[issue.entityId]
                      ?.evaluationId]
                  ?.aggregateRevisionId]
              ?.identity
              .environmentId,
        'cursor' =>
          aggregateById[issue.entityId]?.aggregate.identity.environmentId,
        _ => null,
      };
      return _scopeFor(
        invocation.scope,
        invocation.scope.organizationId,
        applicationId,
        environmentId,
      );
    }

    for (final issue in context.report.issues) {
      if (invocation.scope.applicationId != null &&
          switch (issue.entityType) {
            'aggregate' => aggregateById[issue.entityId] == null,
            'revision' => revisionById[issue.entityId] == null,
            'evaluation' => evaluationById[issue.entityId] == null,
            'decision' => decisionById[issue.entityId] == null,
            'halt_application' => context.applications.every(
              (application) => application.applicationId != issue.entityId,
            ),
            'cursor' => aggregateById[issue.entityId] == null,
            _ => true,
          }) {
        continue;
      }
      final issueScope = scopeForIssue(issue);
      if (!_within(invocation.scope, issueScope)) continue;
      final code = switch (issue.entityType) {
        'aggregate' ||
        'revision' ||
        'evaluation' ||
        'cursor' => ReconciliationTaxonomyCode.evaluationAggregateMismatch,
        'decision' => ReconciliationTaxonomyCode.decisionEvaluationMismatch,
        'halt_application' =>
          ReconciliationTaxonomyCode.haltApplicationRolloutMismatch,
        _ => ReconciliationTaxonomyCode.unknownVersion,
      };
      yield _candidate(
        invocation: invocation,
        scope: issueScope,
        code: code,
        entityType: issue.entityType,
        entityId: issue.entityId,
        sourceDigests: <String, String>{'p3e': _digestOf(issue.toJson())},
        observedVersions: const <String, int>{},
        observedAt: invocation.startedAt,
        safeDetailCode: 'P3E_${issue.code}',
      );
    }
    for (final aggregate in context.aggregates) {
      if (aggregate.organizationId != invocation.scope.organizationId) {
        yield _candidate(
          invocation: invocation,
          scope: invocation.scope,
          code: ReconciliationTaxonomyCode.tenantScopeMismatch,
          entityType: 'aggregate',
          entityId: aggregate.aggregateId,
          sourceDigests: <String, String>{
            'aggregate': _digestOf(aggregate.toJson()),
          },
          observedVersions: const <String, int>{},
          observedAt: aggregate.createdAt,
          safeDetailCode: 'P3E_AGGREGATE_TENANT_MISMATCH',
        );
      }
    }
  }

  Iterable<ReconciliationCandidate> _rolloutFindings(
    ReconciliationInvocation invocation,
    _AuthoritativeContext context,
  ) sync* {
    // A rollout/application detector is only authoritative when the existing
    // control-plane rollout store is supplied. Absence of that store is an
    // integration boundary, not evidence that a rollout revision is missing.
    if (controlStore == null) return;
    final revisionsByKey = <String, RolloutRevision>{
      for (final revision in context.rolloutRevisions)
        '${revision.rolloutId}:${revision.revision}': revision,
    };
    final aggregateRevisionById = <String, HealthAggregateRevision>{
      for (final revision in context.revisions)
        revision.aggregateRevisionId: revision,
    };
    for (final malformed in context.malformedRollouts) {
      yield _candidate(
        invocation: invocation,
        scope: invocation.scope,
        code: ReconciliationTaxonomyCode.unknownVersion,
        entityType: malformed.entityType,
        entityId: malformed.entityId,
        sourceDigests: <String, String>{'rollout': _digestOf(malformed.raw)},
        observedVersions: const <String, int>{},
        observedAt: invocation.startedAt,
        safeDetailCode: 'ROLLOUT_RECORD_MALFORMED',
      );
    }
    for (final rollout in context.rollouts) {
      if (rollout.organizationId != invocation.scope.organizationId) {
        yield _candidate(
          invocation: invocation,
          scope: invocation.scope,
          code: ReconciliationTaxonomyCode.tenantScopeMismatch,
          entityType: 'rollout',
          entityId: rollout.id,
          sourceDigests: <String, String>{
            'rollout': _digestOf(rollout.toJson()),
          },
          observedVersions: <String, int>{'rollout': rollout.currentRevision},
          observedAt: rollout.createdAt,
          safeDetailCode: 'ROLLOUT_TENANT_SCOPE_MISMATCH',
        );
      }
    }
    for (final evaluation in context.evaluations) {
      final aggregateRevision =
          aggregateRevisionById[evaluation.aggregateRevisionId];
      if (aggregateRevision == null && invocation.scope.applicationId != null) {
        continue;
      }
      final scope = _scopeFor(
        invocation.scope,
        evaluation.organizationId,
        aggregateRevision?.identity.applicationId ??
            _applicationFor(invocation.scope),
        aggregateRevision?.identity.environmentId ??
            _environmentFor(invocation.scope),
      );
      if (!_within(invocation.scope, scope)) continue;
      final revision =
          revisionsByKey['${evaluation.rolloutId}:${evaluation.rolloutRevision}'];
      if (revision == null) {
        yield _candidate(
          invocation: invocation,
          scope: scope,
          code: ReconciliationTaxonomyCode.rolloutApplicationReferenceMissing,
          entityType: 'evaluation',
          entityId: evaluation.evaluationId,
          sourceDigests: <String, String>{
            'evaluation': _digestOf(evaluation.toJson()),
          },
          observedVersions: <String, int>{
            'rollout': evaluation.rolloutRevision,
          },
          observedAt: evaluation.createdAt,
          safeDetailCode: 'ROLLOUT_REVISION_MISSING',
        );
      } else {
        final targetDigest = _digestOf(revision.target.toJson());
        if (evaluation.targetBindingDigest != null &&
            evaluation.targetBindingDigest != targetDigest) {
          yield _candidate(
            invocation: invocation,
            scope: scope,
            code: ReconciliationTaxonomyCode.targetBindingMismatch,
            entityType: 'evaluation',
            entityId: evaluation.evaluationId,
            sourceDigests: <String, String>{
              'evaluation': _digestOf(evaluation.toJson()),
              'rollout': _digestOf(revision.toJson()),
            },
            observedVersions: <String, int>{'rollout': revision.revision},
            observedAt: evaluation.createdAt,
            safeDetailCode: 'ROLLOUT_TARGET_BINDING_MISMATCH',
          );
        }
      }
      if (evaluation.auditReference != null &&
          !context.auditIds.contains(evaluation.auditReference)) {
        yield _candidate(
          invocation: invocation,
          scope: scope,
          code: ReconciliationTaxonomyCode.auditReferenceMissing,
          entityType: 'evaluation',
          entityId: evaluation.evaluationId,
          sourceDigests: <String, String>{
            'evaluation': _digestOf(evaluation.toJson()),
            'audit': _digestOf(context.auditIds.toList()..sort()),
          },
          observedVersions: const <String, int>{},
          observedAt: evaluation.createdAt,
          safeDetailCode: 'EVALUATION_AUDIT_REFERENCE_MISSING',
        );
      }
    }
    for (final application in context.applications) {
      final decision = context.decisions.where(
        (item) => item.decisionId == application.decisionId,
      );
      final evaluation = decision.isEmpty
          ? null
          : context.evaluations.where(
              (item) => item.evaluationId == decision.single.evaluationId,
            );
      final aggregateRevision = evaluation == null || evaluation.isEmpty
          ? null
          : aggregateRevisionById[evaluation.single.aggregateRevisionId];
      if (aggregateRevision == null && invocation.scope.applicationId != null) {
        continue;
      }
      final revision =
          revisionsByKey['${application.rolloutId}:${application.resultingRolloutRevision}'];
      if (application.applied &&
          (revision == null ||
              revision.state != RolloutState.halted ||
              revision.organizationId != application.organizationId)) {
        yield _candidate(
          invocation: invocation,
          scope: _scopeFor(
            invocation.scope,
            application.organizationId,
            aggregateRevision?.identity.applicationId ??
                _applicationFor(invocation.scope),
            aggregateRevision?.identity.environmentId ??
                _environmentFor(invocation.scope),
          ),
          code: ReconciliationTaxonomyCode.haltApplicationRolloutMismatch,
          entityType: 'halt_application',
          entityId: application.applicationId,
          sourceDigests: <String, String>{
            'haltApplication': _digestOf(application.toJson()),
            'rollout': _digestOf(revision?.toJson() ?? application.rolloutId),
          },
          observedVersions: <String, int>{
            if (application.resultingRolloutRevision != null)
              'rollout': application.resultingRolloutRevision!,
          },
          observedAt: application.createdAt,
          safeDetailCode: 'HALT_ROLLOUT_REFERENCE_INVALID',
        );
      }
    }
  }

  Iterable<ReconciliationCandidate> _auditFindings(
    ReconciliationInvocation invocation,
    _AuthoritativeContext context,
  ) sync* {
    if (!context.auditVerification.valid) {
      yield _candidate(
        invocation: invocation,
        scope: invocation.scope,
        code: ReconciliationTaxonomyCode.auditChainInvalid,
        entityType: 'audit_chain',
        entityId: 'chain',
        sourceDigests: <String, String>{'audit': _digestOf(context.auditChain)},
        observedVersions: const <String, int>{},
        observedAt: invocation.startedAt,
        safeDetailCode: 'AUDIT_CHAIN_INVALID',
      );
    }
  }

  ReconciliationCandidate _candidate({
    required ReconciliationInvocation invocation,
    required ReconciliationScope scope,
    required ReconciliationTaxonomyCode code,
    required String entityType,
    required String entityId,
    required Map<String, String> sourceDigests,
    required Map<String, int> observedVersions,
    required DateTime observedAt,
    required String safeDetailCode,
    ReconciliationPrecondition? precondition,
  }) {
    final finding = ReconciliationFinding.create(
      scope: scope,
      code: code,
      entityType: entityType,
      entityId: entityId,
      sourceDigests: sourceDigests,
      observedVersions: observedVersions,
      firstObservedAt: observedAt.toUtc(),
      lastObservedAt: observedAt.toUtc(),
      safeDetailCode: safeDetailCode,
    );
    final normalized = precondition == null
        ? null
        : ReconciliationPrecondition(
            scope: precondition.scope,
            findingId: finding.findingId,
            entityId: precondition.entityId,
            expectedWorkVersion: precondition.expectedWorkVersion,
            expectedScheduleRevision: precondition.expectedScheduleRevision,
            currentRolloutRevision: precondition.currentRolloutRevision,
            sourceDigests: precondition.sourceDigests,
            targetBinding: precondition.targetBinding,
            taxonomyCode: precondition.taxonomyCode,
            action: precondition.action,
          );
    return ReconciliationCandidate(finding: finding, precondition: normalized);
  }

  ReconciliationScope _scopeFor(
    ReconciliationScope requested,
    String organizationId,
    String? applicationId,
    String? environmentId,
  ) => ReconciliationScope(
    organizationId: organizationId,
    applicationId: applicationId ?? requested.applicationId,
    environmentId: environmentId ?? requested.environmentId,
  );

  bool _within(ReconciliationScope requested, ReconciliationScope actual) {
    try {
      requested.requireContains(actual);
      return true;
    } on FormatException {
      return false;
    }
  }

  String? _applicationFor(ReconciliationScope scope) => scope.applicationId;

  String? _environmentFor(ReconciliationScope scope) => scope.environmentId;

  int _scheduleVersion(
    EvaluationSchedule schedule,
    Map<String, EvaluationSchedule> schedules,
  ) =>
      schedules[schedule.scheduleId]?.currentScheduleRevision ==
          schedule.currentScheduleRevision
      ? 1
      : 0;

  bool _isActiveLease(ScheduledEvaluationWorkStatus status) =>
      status == ScheduledEvaluationWorkStatus.leased ||
      status == ScheduledEvaluationWorkStatus.evaluating ||
      status == ScheduledEvaluationWorkStatus.evaluated ||
      status == ScheduledEvaluationWorkStatus.haltApplying;

  String _rawEntityId(Map<String, Object?> raw, String fallback) {
    final value = raw['id'] ?? raw['rolloutId'] ?? raw['scheduleId'];
    return value is String && value.isNotEmpty ? value : fallback;
  }
}

typedef ReconciliationLeaseTokenProvider = Future<String?> Function(
  ReconciliationRepairContext context,
);

/// Uses only existing lease/CAS methods on P3E5 schedule persistence. No
/// rollout transition or P3E-4 application service is reachable from this
/// adapter.
final class AuthoritativeReconciliationRepairExecutor
    implements ReconciliationRepairExecutor {
  AuthoritativeReconciliationRepairExecutor({
    required this.p3eStore,
    required this.scheduleStore,
    required this.leaseTokenProvider,
    required this.retryPolicy,
    this.controlStore,
  }) {
    retryPolicy.validate();
  }

  final P3ePersistenceStore p3eStore;
  final P3e5ScheduleStore scheduleStore;
  final ReconciliationLeaseTokenProvider leaseTokenProvider;
  final P3e5RetryPolicy retryPolicy;
  final ControlPlaneStore? controlStore;

  @override
  Future<ReconciliationRepairExecution> execute(
    ReconciliationRepairContext context,
  ) async {
    return switch (context.precondition.action) {
      ReconciliationRepairAction.linkExistingEvaluation =>
        _linkExistingEvaluation(context),
      ReconciliationRepairAction.linkExistingHaltApplication =>
        _completeExistingHalt(context),
      ReconciliationRepairAction.markStale => _markStale(context),
      ReconciliationRepairAction.markFailedPermanent => _markFailedPermanent(
        context,
      ),
      _ => Future<ReconciliationRepairExecution>.value(
        ReconciliationRepairExecution(
          result: ReconciliationRepairResult.failed,
          safeErrorCode:
              reconciliationRepairBindingFor(context.precondition.action) ==
                  ReconciliationRepairBindingDisposition.reportOnly
              ? 'ACTION_REPORT_ONLY'
              : 'ACTION_NOT_EXECUTABLE',
        ),
      ),
    };
  }

  Future<ReconciliationRepairExecution> _linkExistingEvaluation(
    ReconciliationRepairContext context,
  ) async {
    final current = await _readCurrent(context);
    if (current == null) return _failed('WORK_NOT_FOUND');
    if (!_freshWorkPrecondition(current, context)) {
      return _failed(
        'PRECONDITION_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    if (current.status == ScheduledEvaluationWorkStatus.evaluated &&
        current.evaluationId ==
            context.precondition.targetBinding['evaluation_id'] &&
        current.decisionId ==
            context.precondition.targetBinding['decision_id']) {
      return const ReconciliationRepairExecution(
        result: ReconciliationRepairResult.replayed,
        postconditionVerified: true,
      );
    }
    if (current.status != ScheduledEvaluationWorkStatus.evaluating ||
        current.workVersion != context.precondition.expectedWorkVersion) {
      return _failed(
        'PRECONDITION_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    final aggregateId = context.precondition.targetBinding['aggregate_id'];
    final aggregateRevisionId =
        context.precondition.targetBinding['aggregate_revision_id'];
    final evaluationId = context.precondition.targetBinding['evaluation_id'];
    final decisionId = context.precondition.targetBinding['decision_id'];
    if (aggregateId == null ||
        aggregateRevisionId == null ||
        evaluationId == null ||
        decisionId == null ||
        current.aggregateId != aggregateId ||
        current.aggregateRevisionId != aggregateRevisionId) {
      return _failed('LINK_TARGET_INVALID');
    }
    final evaluation = await p3eStore.readEvaluation(
      current.logicalKey.organizationId,
      evaluationId,
    );
    final decision = await p3eStore.readDecision(
      current.logicalKey.organizationId,
      decisionId,
    );
    final revision = await p3eStore.readAggregateRevision(
      current.logicalKey.organizationId,
      aggregateRevisionId,
    );
    if (evaluation == null ||
        decision == null ||
        revision == null ||
        evaluation.aggregateRevisionId != aggregateRevisionId ||
        evaluation.rolloutId != current.logicalKey.rolloutId ||
        evaluation.rolloutRevision != current.logicalKey.rolloutRevision ||
        decision.evaluationId != evaluation.evaluationId ||
        decision.aggregateRevisionId != evaluation.aggregateRevisionId ||
        decision.rolloutId != evaluation.rolloutId ||
        decision.expectedRolloutRevision != evaluation.rolloutRevision) {
      return _failed('IMMUTABLE_EVIDENCE_INVALID');
    }
    final aggregate = await p3eStore.readAggregate(
      current.logicalKey.organizationId,
      aggregateId,
    );
    if (aggregate == null) return _failed('AGGREGATE_NOT_FOUND');
    try {
      validateP3eAggregateLineage(aggregate, revision);
    } on Object {
      return _failed('IMMUTABLE_EVIDENCE_INVALID');
    }
    final lease = await _lease(context, current);
    if (lease == null) return _failed('LEASE_TOKEN_UNAVAILABLE');
    try {
      await scheduleStore.advanceExecution(
        P3e5ExecutionAdvance(
          lease: lease,
          expectedStatus: ScheduledEvaluationWorkStatus.evaluating,
          nextStatus: ScheduledEvaluationWorkStatus.evaluated,
          aggregateId: aggregateId,
          aggregateRevisionId: aggregateRevisionId,
          evaluationId: evaluationId,
          decisionId: decisionId,
        ),
      );
    } on Object {
      final afterFailure = await _readCurrent(context);
      if (_hasEvaluationLinks(afterFailure, context)) {
        return const ReconciliationRepairExecution(
          result: ReconciliationRepairResult.replayed,
          postconditionVerified: true,
        );
      }
      return _failed(
        'PROJECTION_CAS_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    final updated = await _readCurrent(context);
    if (!_hasEvaluationLinks(updated, context)) {
      return _failed('POSTCONDITION_UNVERIFIED');
    }
    return const ReconciliationRepairExecution(
      result: ReconciliationRepairResult.applied,
      postconditionVerified: true,
    );
  }

  Future<ReconciliationRepairExecution> _completeExistingHalt(
    ReconciliationRepairContext context,
  ) async {
    final current = await _readCurrent(context);
    if (current == null) return _failed('WORK_NOT_FOUND');
    if (!_freshWorkPrecondition(current, context)) {
      return _failed(
        'PRECONDITION_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    final applicationId =
        context.precondition.targetBinding['halt_application_id'];
    if (applicationId == null) {
      return _failed(
        'PRECONDITION_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    final application = await p3eStore.readHaltApplication(
      current.logicalKey.organizationId,
      applicationId,
    );
    if (current.status == ScheduledEvaluationWorkStatus.completed &&
        current.haltApplicationId == applicationId) {
      if (application == null ||
          !application.applied ||
          !await _validHaltRolloutReference(current, application)) {
        return _failed('HALT_ROLLOUT_REFERENCE_INVALID');
      }
      return const ReconciliationRepairExecution(
        result: ReconciliationRepairResult.replayed,
        postconditionVerified: true,
      );
    }
    if (current.status != ScheduledEvaluationWorkStatus.haltApplying ||
        current.automaticHaltIntent == null ||
        current.workVersion != context.precondition.expectedWorkVersion) {
      return _failed(
        'PRECONDITION_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    final intent = current.automaticHaltIntent!;
    if (application == null ||
        application.organizationId != current.logicalKey.organizationId ||
        application.decisionId != intent.decisionId ||
        application.evaluationId != intent.evaluationId ||
        application.aggregateRevisionId != current.aggregateRevisionId ||
        application.rolloutId != current.logicalKey.rolloutId ||
        application.expectedRolloutRevision != intent.expectedRolloutRevision ||
        application.idempotencyKey != current.logicalKey.haltIdempotencyKey ||
        !application.applied ||
        application.previousRolloutRevision != intent.expectedRolloutRevision ||
        application.resultingRolloutRevision !=
            intent.expectedRolloutRevision + 1 ||
        application.resultingTransitionReference == null) {
      return _failed('HALT_APPLICATION_INVALID');
    }
    if (!await _validHaltRolloutReference(current, application)) {
      return _failed('HALT_ROLLOUT_REFERENCE_INVALID');
    }
    final lease = await _lease(context, current);
    if (lease == null) return _failed('LEASE_TOKEN_UNAVAILABLE');
    final completion = P3e5AutomaticHaltCompletion(
      lease: lease,
      intentDigest: intent.intentDigest,
      haltApplicationId: application.applicationId,
      idempotencyKey: application.idempotencyKey,
      evaluationId: application.evaluationId,
      decisionId: application.decisionId,
      previousRolloutRevision: application.previousRolloutRevision!,
      resultingRolloutRevision: application.resultingRolloutRevision!,
      resultingTransitionReference: application.resultingTransitionReference!,
      result: application.result,
    );
    try {
      await scheduleStore.completeAutomaticHalt(completion);
    } on Object {
      final afterFailure = await _readCurrent(context);
      if (afterFailure?.status == ScheduledEvaluationWorkStatus.completed &&
          afterFailure?.haltApplicationId == application.applicationId) {
        return const ReconciliationRepairExecution(
          result: ReconciliationRepairResult.replayed,
          postconditionVerified: true,
        );
      }
      return _failed(
        'PROJECTION_CAS_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    final updated = await _readCurrent(context);
    if (updated?.status != ScheduledEvaluationWorkStatus.completed ||
        updated?.haltApplicationId != application.applicationId) {
      return _failed('POSTCONDITION_UNVERIFIED');
    }
    return const ReconciliationRepairExecution(
      result: ReconciliationRepairResult.applied,
      postconditionVerified: true,
    );
  }

  Future<ReconciliationRepairExecution> _markStale(
    ReconciliationRepairContext context,
  ) async {
    final current = await _readCurrent(context);
    if (current == null) return _failed('WORK_NOT_FOUND');
    if (!_freshWorkPrecondition(current, context)) {
      return _failed(
        'PRECONDITION_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    if (current.status == ScheduledEvaluationWorkStatus.stale) {
      if (context.precondition.expectedWorkVersion != null &&
          current.workVersion !=
              context.precondition.expectedWorkVersion! + 1) {
        return _failed(
          'PRECONDITION_CONFLICT',
          result: ReconciliationRepairResult.conflict,
        );
      }
      return const ReconciliationRepairExecution(
        result: ReconciliationRepairResult.replayed,
        postconditionVerified: true,
      );
    }
    if (current.status != ScheduledEvaluationWorkStatus.haltApplying ||
        current.workVersion != context.precondition.expectedWorkVersion) {
      return _failed(
        'PRECONDITION_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    final lease = await _lease(context, current);
    if (lease == null) return _failed('LEASE_TOKEN_UNAVAILABLE');
    try {
      await scheduleStore.markAutomaticHaltStale(lease);
    } on Object {
      final afterFailure = await _readCurrent(context);
      if (afterFailure?.status == ScheduledEvaluationWorkStatus.stale) {
        return const ReconciliationRepairExecution(
          result: ReconciliationRepairResult.replayed,
          postconditionVerified: true,
        );
      }
      return _failed(
        'PROJECTION_CAS_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    final updated = await _readCurrent(context);
    if (updated?.status != ScheduledEvaluationWorkStatus.stale ||
        updated!.workVersion != context.precondition.expectedWorkVersion! + 1) {
      return _failed('POSTCONDITION_UNVERIFIED');
    }
    return const ReconciliationRepairExecution(
      result: ReconciliationRepairResult.applied,
      postconditionVerified: true,
    );
  }

  Future<ReconciliationRepairExecution> _markFailedPermanent(
    ReconciliationRepairContext context,
  ) async {
    final current = await _readCurrent(context);
    if (current == null) return _failed('WORK_NOT_FOUND');
    if (!_freshWorkPrecondition(current, context)) {
      return _failed(
        'PRECONDITION_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    if (current.status == ScheduledEvaluationWorkStatus.failedPermanent) {
      return const ReconciliationRepairExecution(
        result: ReconciliationRepairResult.replayed,
        postconditionVerified: true,
      );
    }
    if (!_isFailClaimState(current.status) ||
        current.workVersion != context.precondition.expectedWorkVersion) {
      return _failed(
        'PRECONDITION_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    final lease = await _lease(context, current);
    if (lease == null) return _failed('LEASE_TOKEN_UNAVAILABLE');
    try {
      await scheduleStore.failClaim(
        lease: lease,
        failure: P3e5RetryFailure(
          classification: P3e5RetryClass.permanent,
          safeCode: 'RETRY_EXHAUSTED',
        ),
        retryPolicy: retryPolicy,
      );
    } on Object {
      final afterFailure = await _readCurrent(context);
      if (afterFailure?.status ==
          ScheduledEvaluationWorkStatus.failedPermanent) {
        return const ReconciliationRepairExecution(
          result: ReconciliationRepairResult.replayed,
          postconditionVerified: true,
        );
      }
      return _failed(
        'PROJECTION_CAS_CONFLICT',
        result: ReconciliationRepairResult.conflict,
      );
    }
    final updated = await _readCurrent(context);
    if (updated?.status != ScheduledEvaluationWorkStatus.failedPermanent) {
      return _failed('POSTCONDITION_UNVERIFIED');
    }
    return const ReconciliationRepairExecution(
      result: ReconciliationRepairResult.applied,
      postconditionVerified: true,
    );
  }

  Future<P3e5LeaseMutation?> _lease(
    ReconciliationRepairContext context,
    ScheduledEvaluationWork work,
  ) async {
    if (work.leaseOwner == null || work.leaseExpiresAt == null) return null;
    final token = await leaseTokenProvider(context);
    if (token == null) return null;
    return P3e5LeaseMutation(
      scope: P3e5ClaimScope(
        organizationId: work.logicalKey.organizationId,
        applicationId: work.logicalKey.applicationId,
        environmentId: work.logicalKey.environmentId,
      ),
      workId: work.workId,
      expectedWorkVersion: work.workVersion,
      leaseOwner: work.leaseOwner!,
      rawLeaseToken: token,
    );
  }

  Future<ScheduledEvaluationWork?> _readCurrent(
    ReconciliationRepairContext context,
  ) async {
    final work = await scheduleStore.readWork(
      context.finding.scope.organizationId,
      context.finding.entityId,
    );
    if (work == null ||
        work.logicalKey.organizationId !=
            context.finding.scope.organizationId ||
        (context.finding.scope.applicationId != null &&
            work.logicalKey.applicationId !=
                context.finding.scope.applicationId) ||
        (context.finding.scope.environmentId != null &&
            work.logicalKey.environmentId !=
                context.finding.scope.environmentId)) {
      return null;
    }
    return work;
  }

  bool _hasEvaluationLinks(
    ScheduledEvaluationWork? work,
    ReconciliationRepairContext context,
  ) =>
      work?.status == ScheduledEvaluationWorkStatus.evaluated &&
      work?.evaluationId ==
          context.precondition.targetBinding['evaluation_id'] &&
      work?.decisionId == context.precondition.targetBinding['decision_id'] &&
      work?.aggregateId == context.precondition.targetBinding['aggregate_id'] &&
      work?.aggregateRevisionId ==
          context.precondition.targetBinding['aggregate_revision_id'];

  bool _freshWorkPrecondition(
    ScheduledEvaluationWork work,
    ReconciliationRepairContext context,
  ) {
    final expectedDigest = context.precondition.sourceDigests['work'];
    return expectedDigest != null && expectedDigest == _digestOf(work.toJson());
  }

  bool _isFailClaimState(ScheduledEvaluationWorkStatus status) =>
      status == ScheduledEvaluationWorkStatus.leased ||
      status == ScheduledEvaluationWorkStatus.evaluating ||
      status == ScheduledEvaluationWorkStatus.evaluated;

  Future<bool> _validHaltRolloutReference(
    ScheduledEvaluationWork work,
    HealthHaltApplication application,
  ) async {
    final store = controlStore;
    if (store == null) return true;
    try {
      final rawRollout = await store.readJson(
        'rollouts',
        work.logicalKey.rolloutId,
      );
      if (rawRollout == null) return false;
      final rollout = RolloutRecord.fromJson(rawRollout);
      final revisions = (await store.listJson('rollout_revisions'))
          .where(
            (raw) =>
                raw['rolloutId'] == rollout.id &&
                raw['revision'] == application.resultingRolloutRevision,
          )
          .map(RolloutRevision.fromJson)
          .toList(growable: false);
      if (rollout.organizationId != work.logicalKey.organizationId ||
          rollout.currentRevision != application.resultingRolloutRevision ||
          revisions.length != 1) {
        return false;
      }
      final revision = revisions.single;
      final targetDigest = _digestOf(revision.target.toJson());
      final marker = 'P3E4 health halt decision ${application.decisionId}:';
      return revision.state == RolloutState.halted &&
          revision.organizationId == application.organizationId &&
          revision.previousRevision == application.previousRolloutRevision &&
          revision.id == application.resultingTransitionReference &&
          revision.reason.startsWith(marker) &&
          targetDigest == work.logicalKey.targetBindingDigest;
    } on Object {
      return false;
    }
  }

  ReconciliationRepairExecution _failed(
    String code, {
    ReconciliationRepairResult result = ReconciliationRepairResult.failed,
  }) => ReconciliationRepairExecution(result: result, safeErrorCode: code);
}

final class _AuthoritativeContext {
  _AuthoritativeContext({
    required this.schedules,
    required this.work,
    required this.consistency,
    required this.aggregates,
    required this.revisions,
    required this.evaluations,
    required this.decisions,
    required this.applications,
    required this.report,
    required this.rollouts,
    required this.rolloutRevisions,
    required this.malformedRollouts,
    required this.auditChain,
  });

  final List<EvaluationSchedule> schedules;
  final List<ScheduledEvaluationWork> work;
  final List<P3e5ConsistencyIssue> consistency;
  final List<HealthAggregateRecord> aggregates;
  final List<HealthAggregateRevision> revisions;
  final List<HealthEvaluation> evaluations;
  final List<RolloutDecisionRecord> decisions;
  final List<HealthHaltApplication> applications;
  final P3eReconciliationReport report;
  final List<RolloutRecord> rollouts;
  final List<RolloutRevision> rolloutRevisions;
  final List<_MalformedAuthoritativeRecord> malformedRollouts;
  final List<Map<String, Object?>> auditChain;

  AuditChainVerification get auditVerification => verifyAuditChain(auditChain);

  Set<String> get auditIds =>
      auditChain.map((entry) => entry['auditId']).whereType<String>().toSet();
}

final class _MalformedAuthoritativeRecord {
  const _MalformedAuthoritativeRecord({
    required this.entityType,
    required this.entityId,
    required this.raw,
    required this.error,
  });

  final String entityType;
  final String entityId;
  final Map<String, Object?> raw;
  final Object error;
}

String _digestOf(Object value) =>
    sha256Digest(utf8.encode(canonicalJson(value)));
