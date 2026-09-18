import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

const _digest =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late Directory root;
  late FileReconciliationStore reconciliationStore;
  late ReconciliationScope expectedScope;
  late ReconciliationFinding finding;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hyfens-observability-');
    reconciliationStore = FileReconciliationStore(root);
    await reconciliationStore.initialize();
    expectedScope = ReconciliationScope(
      organizationId: 'org_observability',
      applicationId: 'app_observability',
      environmentId: 'env_observability',
    );
    finding = ReconciliationFinding.create(
      scope: expectedScope,
      code: ReconciliationTaxonomyCode.workEvaluationLinkMissing,
      entityType: 'work',
      entityId: 'work_observability',
      sourceDigests: const <String, String>{'evaluation': _digest},
      observedVersions: const <String, int>{'work': 4},
      firstObservedAt: DateTime.utc(2026, 8, 24, 10),
      lastObservedAt: DateTime.utc(2026, 8, 24, 10, 1),
      safeDetailCode: 'LINK_MISSING',
    );
    await reconciliationStore.putFinding(finding);
  });

  tearDown(() async {
    await reconciliationStore.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  ReconciliationObservability observability({
    ControlPlaneStore? auditStore,
    Future<bool> Function()? authoritativeReadiness,
  }) => ReconciliationObservability(
    store: reconciliationStore,
    backend: 'file',
    auditStore: auditStore,
    authoritativeReadiness: authoritativeReadiness,
    authorizeDiagnostics: ({required token, required scope}) async {
      if (token != 'diagnostics-token' ||
          scope.canonicalSerialization !=
              expectedScope.canonicalSerialization) {
        throw const ControlPlaneException(
          'NOT_FOUND',
          'Resource was not found',
          statusCode: 404,
        );
      }
    },
  );

  test('metrics are bounded and observing a run is non-authoritative', () {
    final metrics = ReconciliationObservabilityMetrics(backend: 'file');
    final cursor = ReconciliationCursor(
      scope: expectedScope,
      position: finding.findingId,
      oldestUnresolvedAge: const Duration(seconds: 7),
      perTenantCap: 2,
      globalCap: 4,
    );
    final invocation = ReconciliationInvocation.create(
      scope: expectedScope,
      actorId: 'operator',
      principalId: 'principal_observability',
      storageMode: ReconciliationStorageMode.file,
      policy: _policy(),
      startedAt: DateTime.utc(2026, 8, 24, 10, 2),
    );
    metrics.recordRun(
      ReconciliationRunResult(
        invocation: invocation,
        findingsRecorded: 1,
        repairsAttempted: 3,
        repairsApplied: 1,
        repairsReplayed: 1,
        repairsFailed: 1,
        repairsConflicted: 1,
        backlog: true,
        backlogCount: 3,
        findingsByCode: const <ReconciliationTaxonomyCode, int>{
          ReconciliationTaxonomyCode.workEvaluationLinkMissing: 1,
        },
        findingsByStatus: const <ReconciliationFindingStatus, int>{
          ReconciliationFindingStatus.open: 1,
        },
        cursor: cursor,
        auditReferenceMissing: false,
      ),
      ReconciliationExecutionMode.administrator,
    );
    final json = metrics.toJson();
    final counters = json['counters']! as Map<String, Object?>;
    expect(counters['reconciliation_findings_total'], 1);
    expect(counters['reconciliation_repair_attempts_total'], 3);
    expect(counters['reconciliation_repair_outcomes_total'], 3);
    expect(counters['reconciliation_backlog_count'], 3);
    expect((json['repairOutcomes']! as Map<String, Object?>)['CONFLICT'], 1);
    expect(json['backend'], 'file');
    expect(
      (json['findingClasses']! as Map<String, Object?>).keys,
      everyElement(
        isIn(ReconciliationTaxonomyCode.values.map((code) => code.wireName)),
      ),
    );
    expect(jsonEncode(json), isNot(contains(expectedScope.organizationId)));
    expect(jsonEncode(json), isNot(contains(finding.findingId)));
  });

  test(
    'diagnostics are exact-scope, bounded, redacted, and read-only',
    () async {
      final precondition = ReconciliationPrecondition(
        scope: expectedScope,
        findingId: finding.findingId,
        entityId: finding.entityId,
        expectedWorkVersion: 4,
        expectedScheduleRevision: 'schedule_observability',
        currentRolloutRevision: 'rollout_observability',
        sourceDigests: finding.sourceDigests,
        targetBinding: const <String, String>{'work': 'work_observability'},
        taxonomyCode: finding.code,
        action: ReconciliationRepairAction.linkExistingEvaluation,
      );
      final attempt = ReconciliationRepairAttempt.create(
        finding: finding,
        precondition: precondition,
        actorId: 'operator',
        result: ReconciliationRepairResult.applied,
        createdAt: DateTime.utc(2026, 8, 24, 10, 2),
      );
      await reconciliationStore.putRepairAttempt(attempt);
      await reconciliationStore.updateFindingLifecycle(
        lifecycle: ReconciliationFindingLifecycle(
          scope: expectedScope,
          findingId: finding.findingId,
          status: ReconciliationFindingStatus.repaired,
          version: 1,
          latestRepairId: attempt.repairId,
          updatedAt: DateTime.utc(2026, 8, 24, 10, 3),
        ),
        expectedVersion: 0,
      );
      final cursor = ReconciliationCursor(
        scope: expectedScope,
        position: finding.findingId,
        oldestUnresolvedAge: Duration.zero,
        perTenantCap: 2,
        globalCap: 4,
      );
      await reconciliationStore.saveCursor(
        cursor: ReconciliationCursorState(
          scope: expectedScope,
          cursor: cursor,
          version: 1,
          updatedAt: DateTime.utc(2026, 8, 24, 10, 4),
        ),
        expectedVersion: 0,
      );
      final before = await reconciliationStore.readCursor(expectedScope);
      final adapter = observability();
      final result = await adapter.diagnostics(
        token: 'diagnostics-token',
        scope: expectedScope,
        limit: 1,
        code: finding.code,
        status: ReconciliationFindingStatus.repaired,
        outcome: ReconciliationRepairResult.applied,
      );
      final after = await reconciliationStore.readCursor(expectedScope);
      expect(after?.canonicalSerialization, before?.canonicalSerialization);
      expect(result['truncated'], isFalse);
      final listed = result['findings']! as List<Object?>;
      expect(listed, hasLength(1));
      final summary = listed.single as Map<String, Object?>;
      expect(summary['actionDisposition'], 'BOUND');
      expect(summary['status'], 'REPAIRED');
      expect(summary['reportOnly'], isFalse);
      expect(summary['repairAttempts'], containsPair('count', 1));
      expect(jsonEncode(result), isNot(contains('connectionString')));
      expect(jsonEncode(result), isNot(contains('raw malformed payload')));
    },
  );

  test(
    'readiness fails safely on store outage and recovers explicitly',
    () async {
      final adapter = observability();
      expect(
        (await adapter.checkReadiness()).code,
        ReconciliationReadinessCode.ready,
      );
      await reconciliationStore.close();
      final unavailable = await adapter.checkReadiness();
      expect(unavailable.ready, isFalse);
      expect(
        unavailable.code,
        ReconciliationReadinessCode.reconciliationStoreUnavailable,
      );
      await reconciliationStore.initialize();
      final recovered = await adapter.checkReadiness();
      expect(recovered.ready, isTrue);
      expect(recovered.code, ReconciliationReadinessCode.ready);
    },
  );

  test(
    'malformed persisted finding returns bounded diagnostic classification',
    () async {
      final findingsRoot = Directory('${root.path}/reconciliation/findings');
      File? record;
      await for (final entity in findingsRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && entity.path.endsWith('/record.json')) {
          record = entity;
          break;
        }
      }
      expect(record, isNotNull);
      await record!.writeAsString('{}\n', flush: true);

      final result = await observability().diagnostics(
        token: 'diagnostics-token',
        scope: expectedScope,
      );
      expect(result['status'], 'DEGRADED');
      expect(result['code'], 'MALFORMED_RECORD');
      expect(result['findings'], isEmpty);
    },
  );

  test(
    'invalid audit chain makes readiness fail closed without repair',
    () async {
      final auditRoot = await Directory.systemTemp.createTemp(
        'hyfens-observability-audit-',
      );
      final auditStore = FileControlPlaneStore(auditRoot);
      await auditStore.initialize();
      addTearDown(() async {
        await auditStore.close();
        if (await auditRoot.exists()) await auditRoot.delete(recursive: true);
      });
      await auditStore.appendAudit('audit-observability', <String, Object?>{
        'organizationId': expectedScope.organizationId,
        'event': 'test',
      });
      final chainFile = File(
        '${auditRoot.path}/audit_chain/audit-observability.json',
      );
      final chain =
          jsonDecode(await chainFile.readAsString()) as Map<String, Object?>;
      chain['recordDigest'] = _digest;
      await chainFile.writeAsString('${canonicalJson(chain)}\n', flush: true);
      final result = await observability(auditStore: auditStore)
          .checkReadiness();
      expect(result.ready, isFalse);
      expect(result.code, ReconciliationReadinessCode.auditInvalid);
    },
  );

  test('authoritative readiness is read-only and bounded', () async {
    var calls = 0;
    final adapter = observability(
      authoritativeReadiness: () async {
        calls++;
        return false;
      },
    );
    final result = await adapter.checkReadiness();
    expect(
      result.code,
      ReconciliationReadinessCode.authoritativeStoreUnavailable,
    );
    expect(calls, 1);
    expect(
      await reconciliationStore.readFinding(expectedScope, finding.findingId),
      isNotNull,
    );
  });

  test(
    'bounded reconciliation reports one run without changing authority',
    () async {
      final adapter = observability();
      final invocation = ReconciliationInvocation.create(
        scope: expectedScope,
        actorId: 'operator',
        principalId: 'principal_observability',
        storageMode: ReconciliationStorageMode.file,
        policy: _policy(),
        startedAt: DateTime.utc(2026, 8, 24, 10, 5),
      );
      final run = BoundedReconciliationService(
        store: reconciliationStore,
        source: _StaticSource(<ReconciliationCandidate>[
          ReconciliationCandidate(
            finding: ReconciliationFinding.create(
              scope: expectedScope,
              code: ReconciliationTaxonomyCode.orphanWork,
              entityType: 'work',
              entityId: 'work_report_only',
              sourceDigests: const <String, String>{'schedule': _digest},
              observedVersions: const <String, int>{'work': 1},
              firstObservedAt: DateTime.utc(2026, 8, 24, 10, 5),
              lastObservedAt: DateTime.utc(2026, 8, 24, 10, 5),
              safeDetailCode: 'ORPHAN_WORK',
            ),
          ),
        ]),
        executor: _NeverCalledExecutor(),
        audit: _NoopAudit(),
        runObserver: adapter.observeRun,
        clock: () => DateTime.utc(2026, 8, 24, 10, 5),
      );
      final result = await run.runStartup(
        invocation: invocation,
        perTenantCap: 2,
        globalCap: 2,
      );
      expect(result.repairsAttempted, 0);
      expect(adapter.metrics.findingsTotal, 1);
      expect(
        adapter.metrics.lastBoundedRunMode,
        ReconciliationExecutionMode.startup,
      );
      expect(
        await reconciliationStore.readFinding(expectedScope, finding.findingId),
        isNotNull,
      );

      final periodicRunner = ReconciliationPeriodicRunner(
        config: const ReconciliationPeriodicConfig(enabled: true),
        metrics: adapter.metrics.periodic,
        invokeBoundedReconciliation: () async {
          final periodicInvocation = ReconciliationInvocation.create(
            scope: expectedScope,
            actorId: 'periodic-runner',
            principalId: 'principal_periodic',
            storageMode: ReconciliationStorageMode.file,
            policy: _policy(),
            startedAt: DateTime.utc(2026, 8, 24, 10, 6),
          );
          final periodicResult = await run.runStartup(
            invocation: periodicInvocation,
            perTenantCap: 2,
            globalCap: 2,
          );
          expect(periodicResult.repairsAttempted, 0);
        },
      );
      expect(
        await periodicRunner.runTick(),
        ReconciliationPeriodicRunOutcome.success,
      );
      expect(adapter.metrics.periodic.runsTotal, 1);
      expect(
        adapter.metrics.periodic.lastRunOutcome,
        ReconciliationPeriodicRunOutcome.success,
      );
    },
  );

  final postgresUrl = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  test(
    'PostgreSQL readiness reports disconnect and explicit recreation',
    () async {
      final postgres = PostgresReconciliationStore(postgresUrl!);
      await postgres.initialize();
      addTearDown(postgres.close);
      final adapter = ReconciliationObservability(
        store: postgres,
        backend: 'postgresql',
        authorizeDiagnostics: ({required token, required scope}) async {},
      );
      expect((await adapter.checkReadiness()).ready, isTrue);
      await postgres.close();
      expect((await adapter.checkReadiness()).ready, isFalse);
      final recoveredStore = PostgresReconciliationStore(postgresUrl);
      addTearDown(recoveredStore.close);
      await recoveredStore.initialize();
      final recovered = ReconciliationObservability(
        store: recoveredStore,
        backend: 'postgresql',
        authorizeDiagnostics: ({required token, required scope}) async {},
      );
      expect((await recovered.checkReadiness()).ready, isTrue);
    },
    skip: postgresUrl == null || postgresUrl.isEmpty
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );

  test(
    'PostgreSQL diagnostics preserve File parity and exact scope',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final postgres = PostgresReconciliationStore(postgresUrl!);
      await postgres.initialize();
      addTearDown(postgres.close);
      final postgresScope = ReconciliationScope(
        organizationId: 'org_pg_$suffix',
        applicationId: 'app_pg',
        environmentId: 'env_pg',
      );
      final postgresFinding = ReconciliationFinding.create(
        scope: postgresScope,
        code: ReconciliationTaxonomyCode.orphanWork,
        entityType: 'work',
        entityId: 'work_pg_observability',
        sourceDigests: const <String, String>{'schedule': _digest},
        observedVersions: const <String, int>{'work': 1},
        firstObservedAt: DateTime.utc(2026, 8, 24, 11),
        lastObservedAt: DateTime.utc(2026, 8, 24, 11, 1),
        safeDetailCode: 'ORPHAN_WORK',
      );
      await postgres.putFinding(postgresFinding);
      final cursor = ReconciliationCursor(
        scope: postgresScope,
        position: postgresFinding.findingId,
        oldestUnresolvedAge: const Duration(seconds: 3),
        perTenantCap: 1,
        globalCap: 1,
      );
      await postgres.saveCursor(
        cursor: ReconciliationCursorState(
          scope: postgresScope,
          cursor: cursor,
          version: 1,
          updatedAt: DateTime.utc(2026, 8, 24, 11, 2),
        ),
        expectedVersion: 0,
      );
      final adapter = ReconciliationObservability(
        store: postgres,
        backend: 'postgresql',
        authorizeDiagnostics: ({required token, required scope}) async {
          if (scope.canonicalSerialization !=
              postgresScope.canonicalSerialization) {
            throw const ControlPlaneException(
              'NOT_FOUND',
              'Resource was not found',
              statusCode: 404,
            );
          }
        },
      );
      final result = await adapter.diagnostics(
        token: 'diagnostics-token',
        scope: postgresScope,
        limit: 1,
      );
      expect(result['summary'], containsPair('findings', 1));
      expect(result['cursor'], containsPair('present', true));
      final listed = result['findings']! as List<Object?>;
      expect(
        (listed.single as Map<String, Object?>)['actionDisposition'],
        'REPORT_ONLY',
      );
    },
    skip: postgresUrl == null || postgresUrl.isEmpty
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );
}

ReconciliationPolicy _policy() => ReconciliationPolicy(
  policyVersion: 1,
  maximumRecordsScanned: 20,
  maximumTenantsScanned: 2,
  maximumLinkageDepth: 4,
  maximumFindings: 10,
  maximumRepairs: 5,
  maximumConcurrentRepairs: 1,
  maximumRetryAttempts: 2,
  lookbackHorizon: const Duration(hours: 1),
  maximumDiagnosticHistory: 5,
  maximumAuditLookupDepth: 5,
  fairnessPolicyVersion: 1,
);

final class _StaticSource implements ReconciliationCandidateSource {
  _StaticSource(this.candidates);

  final List<ReconciliationCandidate> candidates;

  @override
  Future<List<ReconciliationCandidate>> discover(
    ReconciliationInvocation invocation,
  ) async => candidates;
}

final class _NoopAudit implements ReconciliationAuditSink {
  @override
  Future<void> append(ReconciliationAuditEvent event) async {}
}

final class _NeverCalledExecutor implements ReconciliationRepairExecutor {
  @override
  Future<ReconciliationRepairExecution> execute(
    ReconciliationRepairContext context,
  ) async {
    throw StateError('Report-only finding must not invoke an executor');
  }
}
