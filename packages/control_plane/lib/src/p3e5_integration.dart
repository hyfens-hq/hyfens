import 'dart:math';

import 'auth.dart';
import 'domain.dart';
import 'errors.dart';
import 'p3e_auto_halt_applicability.dart';
import 'p3e_auto_halt_application.dart';
import 'p3e_claim.dart';
import 'p3e_executor.dart';
import 'p3e_persistence.dart';
import 'p3e_schedule_persistence.dart';
import 'persistence.dart';
import 'service.dart';

/// Result of one explicit, bounded P3E5-3 → P3E5-4 integration invocation.
/// The result contains no scheduler, timer, queue, or rollout writer.
final class P3e5AutomaticHaltIntegrationResult {
  const P3e5AutomaticHaltIntegrationResult({
    required this.execution,
    required this.applications,
  });

  final P3e5ExecutorInvocationResult execution;
  final List<P3e5AutomaticHaltApplicationResult> applications;
}

/// Reviewed composition seam for one explicit scheduled-work invocation.
///
/// The evaluation principal and Auto-Halt Principal are independently
/// authorized before the existing executor is called. Evaluation remains the
/// only operation available to the scheduler credential; rollout mutation is
/// still delegated to [P3e5AutomaticHaltApplicationService], which reuses the
/// existing P3E-4 validation and P3A CAS path.
final class P3e5AutomaticHaltIntegrationService {
  P3e5AutomaticHaltIntegrationService({
    required this.controlStore,
    required this.scheduleStore,
    required this.p3eStore,
    required this.controlService,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure();

  final ControlPlaneStore controlStore;
  final P3e5ScheduleStore scheduleStore;
  final P3ePersistenceStore p3eStore;
  final ControlPlaneService controlService;
  final DateTime Function() _clock;
  final Random _random;

  /// Runs one explicit evaluator invocation and applies only eligible
  /// `HALT_NEW_OFFERS` outcomes through the existing two-authority path.
  ///
  /// Both credentials are required up front. No work is claimed or evaluated
  /// when either exact-scope principal is missing or invalid.
  Future<P3e5AutomaticHaltIntegrationResult> invoke({
    required P3e5TenantExecutionInput evaluationTenant,
    required String autoHaltToken,
    required P3e5ExecutorResourcePolicy resourcePolicy,
    String? requestId,
    String? fairnessCursor,
  }) async {
    await _authorizeEvaluation(evaluationTenant);
    await _authorizeAutoHalt(autoHaltToken, evaluationTenant.scope);

    final executor = P3e5ExplicitExecutorService(
      controlStore: controlStore,
      scheduleStore: scheduleStore,
      p3eStore: p3eStore,
      controlService: controlService,
      clock: _clock,
      random: _random,
    );
    final execution = await executor.invoke(
      tenants: <P3e5TenantExecutionInput>[evaluationTenant],
      resourcePolicy: resourcePolicy,
      fairnessCursor: fairnessCursor,
      requestId: requestId,
    );
    final applications = <P3e5AutomaticHaltApplicationResult>[];
    final applicability = P3e5AutomaticHaltApplicabilityService(
      controlStore: controlStore,
      scheduleStore: scheduleStore,
      p3eStore: p3eStore,
      clock: _clock,
      random: _random,
    );
    final application = P3e5AutomaticHaltApplicationService(
      controlStore: controlStore,
      scheduleStore: scheduleStore,
      p3eStore: p3eStore,
      controlService: controlService,
      clock: _clock,
    );

    for (final outcome in execution.outcomes) {
      if (outcome.decision.decision != 'HALT_NEW_OFFERS') continue;
      final evaluationLease = outcome.haltLease;
      if (evaluationLease == null) {
        throw const FormatException(
          'HALT_NEW_OFFERS outcome has no current evaluation lease',
        );
      }
      final intent = await applicability.applyIntent(
        token: autoHaltToken,
        lease: evaluationLease,
        requestId: requestId,
      );
      final haltLease = P3e5LeaseMutation(
        scope: evaluationLease.scope,
        workId: evaluationLease.workId,
        expectedWorkVersion: intent.work.workVersion,
        leaseOwner: evaluationLease.leaseOwner,
        rawLeaseToken: evaluationLease.rawLeaseToken,
      );
      applications.add(
        await application.apply(
          token: autoHaltToken,
          lease: haltLease,
          requestId: requestId,
        ),
      );
    }

    return P3e5AutomaticHaltIntegrationResult(
      execution: execution,
      applications: List.unmodifiable(applications),
    );
  }

  Future<CredentialRecord> _authorizeEvaluation(
    P3e5TenantExecutionInput tenant,
  ) async {
    final principal = await CredentialService.authorize(
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
    if (principal.scopes.length != evaluationOnlySchedulerScopes.length ||
        !principal.scopes.containsAll(evaluationOnlySchedulerScopes)) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'Evaluation principal does not have the exact scheduler profile',
        statusCode: 403,
      );
    }
    return principal;
  }

  Future<CredentialRecord> _authorizeAutoHalt(
    String token,
    P3e5ClaimScope scope,
  ) async {
    final principal = await CredentialService.authorize(
      token: token,
      requiredScope: 'health:work:apply-halt',
      read: (hash) async {
        final raw = await controlStore.readJson('credentials', hash);
        return raw == null ? null : CredentialRecord.fromJson(raw);
      },
      organizationId: scope.organizationId,
      applicationId: scope.applicationId,
      environmentId: scope.environmentId,
      kind: CredentialKind.autoHalt,
      now: _clock().toUtc(),
    );
    if (principal.scopes.length != autoHaltScopes.length ||
        !principal.scopes.containsAll(autoHaltScopes)) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'Auto-Halt Principal does not have the exact halt profile',
        statusCode: 403,
      );
    }
    return principal;
  }
}
