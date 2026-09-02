import 'dart:math';

import 'errors.dart';
import 'p3e_auto_halt_application.dart';
import 'p3e_claim.dart';
import 'p3e_halt.dart';
import 'p3e_persistence.dart';
import 'p3e_schedule.dart';
import 'p3e_schedule_persistence.dart';
import 'persistence.dart';
import 'service.dart';

/// Auto-halt recovery is deliberately separate from generic scheduled
/// claiming. It can acquire a fresh lease for one expired `HALT_APPLYING`
/// work item, but it cannot write a rollout or bypass the existing P3E-4/P3A
/// application adapter.
final class P3e5AutomaticHaltRecoveryService {
  P3e5AutomaticHaltRecoveryService({
    required this.controlStore,
    required this.scheduleStore,
    required this.p3eStore,
    required this.controlService,
    required this.leasePolicy,
    required this.limits,
    required String recoveryOwner,
    DateTime Function()? clock,
    Random? random,
    Future<void> Function(P3e5AutomaticHaltApplicationFailurePoint point)?
    applicationFailure,
  }) : recoveryOwner = _boundedOwner(recoveryOwner),
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure(),
       _application = P3e5AutomaticHaltApplicationService(
         controlStore: controlStore,
         scheduleStore: scheduleStore,
         p3eStore: p3eStore,
         controlService: controlService,
         clock: clock,
         failure: applicationFailure,
       ) {
    leasePolicy.validate();
    limits.validate();
  }

  final ControlPlaneStore controlStore;
  final P3e5ScheduleStore scheduleStore;
  final P3ePersistenceStore p3eStore;
  final ControlPlaneService controlService;
  final P3e5LeasePolicy leasePolicy;
  final P3e5AutomaticHaltRecoveryLimits limits;
  final String recoveryOwner;
  final DateTime Function() _clock;
  final Random _random;
  final P3e5AutomaticHaltApplicationService _application;

  Future<P3e5AutomaticHaltRecoveryResult> recover({
    required String token,
    required P3e5ClaimScope scope,
    required String workId,
    String? requestId,
  }) async {
    var reclaimed = false;
    for (
      var attempt = 1;
      attempt <= limits.maximumRecoveryAttempts;
      attempt++
    ) {
      late final P3e5AutomaticHaltApplicationEvidence evidence;
      try {
        evidence = await _application.inspectExistingApplication(
          token: token,
          scope: scope,
          workId: workId,
          maximumApplicationRecords: limits.maximumApplicationRecords,
          maximumLinkageRecords: limits.maximumLinkageRecords,
        );
      } on Object catch (error) {
        return _classified(error, attempts: attempt, reclaimed: reclaimed);
      }

      final work = evidence.work;
      final application = evidence.application;
      if (application != null &&
          work.status == ScheduledEvaluationWorkStatus.completed) {
        return P3e5AutomaticHaltRecoveryResult(
          outcome: P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid,
          work: work,
          application: application,
          reclaimed: reclaimed,
          attempts: attempt,
        );
      }
      if (application == null &&
          work.status == ScheduledEvaluationWorkStatus.completed) {
        return P3e5AutomaticHaltRecoveryResult(
          outcome: P3e5AutomaticHaltRecoveryOutcome.applicationCorrupt,
          work: work,
          application: null,
          reclaimed: reclaimed,
          attempts: attempt,
        );
      }
      if (work.status != ScheduledEvaluationWorkStatus.haltApplying ||
          work.automaticHaltIntent == null) {
        return P3e5AutomaticHaltRecoveryResult(
          outcome: work.status.isTerminal
              ? P3e5AutomaticHaltRecoveryOutcome.applicationStale
              : P3e5AutomaticHaltRecoveryOutcome.applicationNotFoundRetryable,
          work: work,
          application: application,
          reclaimed: reclaimed,
          attempts: attempt,
        );
      }

      final now = _clock().toUtc();
      if (work.leaseExpiresAt == null || work.leaseExpiresAt!.isAfter(now)) {
        if (attempt < limits.maximumRecoveryAttempts) {
          // Give a competing claimant a bounded opportunity to persist the
          // immutable application or completion before declaring retryable.
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        return P3e5AutomaticHaltRecoveryResult(
          outcome:
              P3e5AutomaticHaltRecoveryOutcome.applicationNotFoundRetryable,
          work: work,
          application: application,
          reclaimed: reclaimed,
          attempts: attempt,
        );
      }

      final rawLeaseToken = generateP3e5LeaseToken(_random);
      final leaseOwner = '$recoveryOwner:$attempt';
      late final P3e5ClaimedWork claimed;
      try {
        claimed = await scheduleStore.reclaimAutomaticHalt(
          P3e5AutomaticHaltReclaimRequest(
            scope: scope,
            workId: work.workId,
            expectedWorkVersion: work.workVersion,
            leaseOwner: leaseOwner,
            rawLeaseToken: rawLeaseToken,
            leasePolicy: leasePolicy,
          ),
        );
      } on StorageConflict {
        // Another recovery claimant may have won the fence. Reload immutable
        // evidence before making any retry decision; never mint a second
        // semantic application from the old observation.
        if (attempt == limits.maximumRecoveryAttempts) {
          return P3e5AutomaticHaltRecoveryResult(
            outcome: P3e5AutomaticHaltRecoveryOutcome.applicationConflict,
            work: await scheduleStore.readWork(scope.organizationId, workId),
            application: null,
            reclaimed: reclaimed,
            attempts: attempt,
          );
        }
        continue;
      } on Object catch (error) {
        return _classified(
          error,
          work: work,
          application: application,
          attempts: attempt,
          reclaimed: reclaimed,
        );
      }
      reclaimed = true;

      final lease = P3e5LeaseMutation(
        scope: scope,
        workId: claimed.work.workId,
        expectedWorkVersion: claimed.work.workVersion,
        leaseOwner: leaseOwner,
        rawLeaseToken: rawLeaseToken,
      );
      try {
        final applied = await _application.apply(
          token: token,
          lease: lease,
          requestId: requestId,
        );
        return P3e5AutomaticHaltRecoveryResult(
          outcome: P3e5AutomaticHaltRecoveryOutcome.applicationFoundAndValid,
          work: applied.work,
          application: applied.application,
          reclaimed: true,
          attempts: attempt,
        );
      } on ControlPlaneException catch (error) {
        if (error.code.contains('STALE') || error.code.contains('INELIGIBLE')) {
          try {
            final stale = await scheduleStore.markAutomaticHaltStale(lease);
            return P3e5AutomaticHaltRecoveryResult(
              outcome: P3e5AutomaticHaltRecoveryOutcome.applicationStale,
              work: stale.work,
              application: null,
              reclaimed: true,
              attempts: attempt,
            );
          } on StorageConflict {
            if (attempt < limits.maximumRecoveryAttempts) continue;
          }
        }
        return _classified(
          error,
          work: claimed.work,
          application: application,
          attempts: attempt,
          reclaimed: reclaimed,
        );
      } on StorageConflict {
        // A response can be lost after P3E4/P3A or completion. The next
        // bounded pass re-reads application evidence first.
        if (attempt == limits.maximumRecoveryAttempts) {
          return P3e5AutomaticHaltRecoveryResult(
            outcome: P3e5AutomaticHaltRecoveryOutcome.applicationConflict,
            work: await scheduleStore.readWork(scope.organizationId, workId),
            application: null,
            reclaimed: reclaimed,
            attempts: attempt,
          );
        }
      } on Object catch (error) {
        return _classified(
          error,
          work: claimed.work,
          application: application,
          attempts: attempt,
          reclaimed: reclaimed,
        );
      }
    }
    return P3e5AutomaticHaltRecoveryResult(
      outcome: P3e5AutomaticHaltRecoveryOutcome.applicationConflict,
      work: await scheduleStore.readWork(scope.organizationId, workId),
      application: null,
      reclaimed: reclaimed,
      attempts: limits.maximumRecoveryAttempts,
    );
  }

  P3e5AutomaticHaltRecoveryResult _classified(
    Object error, {
    ScheduledEvaluationWork? work,
    HealthHaltApplication? application,
    required int attempts,
    required bool reclaimed,
  }) {
    final P3e5AutomaticHaltRecoveryOutcome outcome;
    if (error is ControlPlaneException) {
      final code = error.code;
      outcome = code.contains('APPLICATION_CORRUPT')
          ? P3e5AutomaticHaltRecoveryOutcome.applicationCorrupt
          : code.contains('SECURITY') ||
                code == 'UNAUTHORIZED' ||
                code == 'FORBIDDEN' ||
                code == 'NOT_FOUND'
          ? P3e5AutomaticHaltRecoveryOutcome.securityRejected
          : code.contains('STALE') || code.contains('INELIGIBLE')
          ? P3e5AutomaticHaltRecoveryOutcome.applicationStale
          : P3e5AutomaticHaltRecoveryOutcome.applicationConflict;
    } else if (error is StorageConflict) {
      outcome = P3e5AutomaticHaltRecoveryOutcome.applicationConflict;
    } else if (error is FormatException) {
      outcome = P3e5AutomaticHaltRecoveryOutcome.applicationCorrupt;
    } else {
      outcome = P3e5AutomaticHaltRecoveryOutcome.applicationConflict;
    }
    return P3e5AutomaticHaltRecoveryResult(
      outcome: outcome,
      work: work,
      application: application,
      reclaimed: reclaimed,
      attempts: attempts,
    );
  }
}

String _boundedOwner(String value) {
  if (value.isEmpty ||
      value.length > 96 ||
      value.contains(RegExp(r'[\x00-\x1f]'))) {
    throw const FormatException('Invalid automatic-halt recovery owner');
  }
  return value;
}
