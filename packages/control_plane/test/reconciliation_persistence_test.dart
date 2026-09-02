import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

const _digest =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

ReconciliationPolicy _policy({int maximumTenants = 4}) => ReconciliationPolicy(
  policyVersion: 1,
  maximumRecordsScanned: 20,
  maximumTenantsScanned: maximumTenants,
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

ReconciliationScope _scope({
  String application = 'app',
  String environment = 'env',
}) => ReconciliationScope(
  organizationId: 'org',
  applicationId: application,
  environmentId: environment,
);

ReconciliationFinding _finding(
  ReconciliationScope scope, {
  ReconciliationFindingStatus status = ReconciliationFindingStatus.open,
  ReconciliationTaxonomyCode code =
      ReconciliationTaxonomyCode.workEvaluationLinkMissing,
  String entityId = 'work-1',
}) => ReconciliationFinding.create(
  scope: scope,
  code: code,
  entityType: 'work',
  entityId: entityId,
  sourceDigests: const <String, String>{'evaluation': _digest},
  observedVersions: const <String, int>{'work': 1},
  firstObservedAt: DateTime.utc(2026, 8, 24, 8),
  lastObservedAt: DateTime.utc(2026, 8, 24, 8, 1),
  status: status,
  safeDetailCode: 'LINK_MISSING',
);

ReconciliationPrecondition _precondition(ReconciliationFinding finding) =>
    ReconciliationPrecondition(
      scope: finding.scope,
      findingId: finding.findingId,
      entityId: finding.entityId,
      expectedWorkVersion: 1,
      expectedScheduleRevision: 'schedule-rev-1',
      currentRolloutRevision: 'rollout-rev-1',
      sourceDigests: finding.sourceDigests,
      targetBinding: const <String, String>{'work': 'work-1'},
      taxonomyCode: finding.code,
      action: ReconciliationRepairAction.linkExistingEvaluation,
    );

ReconciliationInvocation _invocation({
  required ReconciliationScope scope,
  ReconciliationCursor? cursor,
}) => ReconciliationInvocation.create(
  scope: scope,
  actorId: 'operator',
  principalId: 'principal-1',
  storageMode: ReconciliationStorageMode.file,
  policy: _policy(),
  startedAt: DateTime.utc(2026, 8, 24, 9),
  cursor: cursor,
);

final class _MemoryAudit implements ReconciliationAuditSink {
  final List<ReconciliationAuditEvent> events = <ReconciliationAuditEvent>[];
  bool fail = false;
  bool failAfterFirst = false;

  @override
  Future<void> append(ReconciliationAuditEvent event) async {
    if (fail || (failAfterFirst && events.isNotEmpty)) {
      throw const StorageUnavailable('audit unavailable');
    }
    events.add(event);
  }
}

final class _StaticSource implements ReconciliationCandidateSource {
  _StaticSource(this.candidates);

  final List<ReconciliationCandidate> candidates;

  @override
  Future<List<ReconciliationCandidate>> discover(
    ReconciliationInvocation invocation,
  ) async => candidates;
}

final class _ApplyingExecutor implements ReconciliationRepairExecutor {
  int calls = 0;

  @override
  Future<ReconciliationRepairExecution> execute(
    ReconciliationRepairContext context,
  ) async {
    calls++;
    return const ReconciliationRepairExecution(
      result: ReconciliationRepairResult.applied,
      postconditionVerified: true,
    );
  }
}

void main() {
  late Directory temporary;
  late FileReconciliationStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('hyfens-reconcile-');
    store = FileReconciliationStore(temporary);
    await store.initialize();
  });

  tearDown(() async {
    await store.close();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'File persistence is restart durable and canonical idempotent',
    () async {
      final scope = _scope();
      final finding = _finding(scope);
      expect(
        await store.putFinding(finding),
        ReconciliationRecordWriteResult.created,
      );
      expect(
        await store.putFinding(finding),
        ReconciliationRecordWriteResult.replayed,
      );
      expect(await store.readFinding(scope, finding.findingId), isNotNull);
      final changed = _finding(
        scope,
        status: ReconciliationFindingStatus.reportOnly,
      );
      await expectLater(
        store.putFinding(changed),
        throwsA(isA<StorageConflict>()),
      );

      final precondition = _precondition(finding);
      final attempt = ReconciliationRepairAttempt.create(
        finding: finding,
        precondition: precondition,
        actorId: 'operator',
        result: ReconciliationRepairResult.applied,
        createdAt: DateTime.utc(2026, 8, 24, 9),
      );
      expect(
        await store.putRepairAttempt(attempt),
        ReconciliationRecordWriteResult.created,
      );
      expect(
        await store.putRepairAttempt(attempt),
        ReconciliationRecordWriteResult.replayed,
      );
      await store.close();
      store = FileReconciliationStore(temporary);
      await store.initialize();
      expect(await store.readRepairAttempt(scope, attempt.repairId), isNotNull);
    },
  );

  test('lifecycle and cursor state use compare-and-set versions', () async {
    final scope = _scope();
    final finding = _finding(scope);
    await store.putFinding(finding);
    final lifecycle = ReconciliationFindingLifecycle(
      scope: scope,
      findingId: finding.findingId,
      status: ReconciliationFindingStatus.open,
      version: 1,
      latestRepairId: null,
      updatedAt: DateTime.utc(2026, 8, 24, 9),
    );
    await store.updateFindingLifecycle(
      lifecycle: lifecycle,
      expectedVersion: 0,
    );
    await expectLater(
      store.updateFindingLifecycle(lifecycle: lifecycle, expectedVersion: 0),
      throwsA(isA<StoragePreconditionFailed>()),
    );
    final cursor = ReconciliationCursor(
      scope: scope,
      position: finding.findingId,
      oldestUnresolvedAge: Duration.zero,
      perTenantCap: 1,
      globalCap: 1,
    );
    await store.saveCursor(
      cursor: ReconciliationCursorState(
        scope: scope,
        cursor: cursor,
        version: 1,
        updatedAt: DateTime.utc(2026, 8, 24, 9),
      ),
      expectedVersion: 0,
    );
    await expectLater(
      store.saveCursor(
        cursor: ReconciliationCursorState(
          scope: scope,
          cursor: cursor,
          version: 1,
          updatedAt: DateTime.utc(2026, 8, 24, 9),
        ),
        expectedVersion: 0,
      ),
      throwsA(isA<StoragePreconditionFailed>()),
    );
  });

  test('malformed persisted records fail closed', () async {
    final scope = _scope();
    final finding = _finding(scope);
    await store.putFinding(finding);
    final files = await temporary
        .list(recursive: true, followLinks: false)
        .where((entry) => entry is File && entry.path.endsWith('record.json'))
        .toList();
    final file = files.whereType<File>().single;
    await file.writeAsString(
      '${jsonEncode(<String, Object?>{'schemaVersion': 99})}\n',
      flush: true,
    );
    await expectLater(
      store.readFinding(scope, finding.findingId),
      throwsA(isA<FormatException>()),
    );
  });

  test('foreign scopes cannot discover records', () async {
    final scope = _scope();
    final foreign = _scope(application: 'other', environment: 'other_env');
    final finding = _finding(scope);
    await store.putFinding(finding);
    expect(await store.listFindings(foreign), isEmpty);
    expect(await store.readFinding(foreign, finding.findingId), isNull);
  });

  test(
    'bounded startup execution persists findings, repairs, and cursor',
    () async {
      final scope = ReconciliationScope(organizationId: 'org');
      final candidateScope = _scope();
      final finding = _finding(candidateScope);
      final audit = _MemoryAudit();
      final executor = _ApplyingExecutor();
      final service = BoundedReconciliationService(
        store: store,
        source: _StaticSource(<ReconciliationCandidate>[
          ReconciliationCandidate(
            finding: finding,
            precondition: _precondition(finding),
          ),
        ]),
        executor: executor,
        audit: audit,
        clock: () => DateTime.utc(2026, 8, 24, 9),
      );
      final result = await service.runStartup(
        invocation: _invocation(scope: scope),
        perTenantCap: 1,
        globalCap: 1,
      );
      expect(result.findingsRecorded, 1);
      expect(result.repairsApplied, 1);
      expect(executor.calls, 1);
      expect(result.backlog, isFalse);
      expect(await store.readCursor(scope), isNotNull);
      expect(
        audit.events.map((event) => event.eventType),
        contains(ReconciliationAuditEventType.repairRequested),
      );
    },
  );

  test('administrator invocation requires exact principal scope', () async {
    final scope = _scope();
    final principal = ReconciliationPrincipal(
      principalId: 'principal-1',
      scope: scope,
      actorId: 'operator',
      issuedAt: DateTime.utc(2026, 8, 24, 8),
      expiresAt: DateTime.utc(2026, 8, 24, 10),
    );
    final audit = _MemoryAudit();
    final service = BoundedReconciliationService(
      store: store,
      source: _StaticSource(const <ReconciliationCandidate>[]),
      executor: _ApplyingExecutor(),
      audit: audit,
      clock: () => DateTime.utc(2026, 8, 24, 9),
    );
    final invocation = _invocation(scope: scope);
    await service.runAdministrator(
      invocation: invocation,
      principal: principal,
      now: DateTime.utc(2026, 8, 24, 9),
      perTenantCap: 1,
      globalCap: 1,
    );
    await expectLater(
      service.runAdministrator(
        invocation: _invocation(
          scope: ReconciliationScope(organizationId: 'org'),
        ),
        principal: principal,
        now: DateTime.utc(2026, 8, 24, 9),
        perTenantCap: 1,
        globalCap: 1,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'composite detectors deduplicate equal findings and reject divergence',
    () async {
      final scope = _scope();
      final finding = _finding(scope);
      final source = CompositeReconciliationCandidateSource(
        <ReconciliationDetector>[
          (_) async => <ReconciliationCandidate>[
            ReconciliationCandidate(finding: finding),
          ],
          (_) async => <ReconciliationCandidate>[
            ReconciliationCandidate(finding: finding),
          ],
        ],
      );
      expect(await source.discover(_invocation(scope: scope)), hasLength(1));
      final changed = _finding(
        scope,
        status: ReconciliationFindingStatus.reportOnly,
      );
      final conflicting = CompositeReconciliationCandidateSource(
        <ReconciliationDetector>[
          (_) async => <ReconciliationCandidate>[
            ReconciliationCandidate(finding: finding),
          ],
          (_) async => <ReconciliationCandidate>[
            ReconciliationCandidate(finding: changed),
          ],
        ],
      );
      await expectLater(
        conflicting.discover(_invocation(scope: scope)),
        throwsA(isA<StorageConflict>()),
      );
    },
  );

  test('report-only findings never invoke a repair executor', () async {
    final scope = _scope();
    final audit = _MemoryAudit();
    final executor = _ApplyingExecutor();
    final service = BoundedReconciliationService(
      store: store,
      source: _StaticSource(<ReconciliationCandidate>[
        ReconciliationCandidate(
          finding: _finding(scope, code: ReconciliationTaxonomyCode.orphanWork),
        ),
      ]),
      executor: executor,
      audit: audit,
      clock: () => DateTime.utc(2026, 8, 24, 9),
    );
    final result = await service.runStartup(
      invocation: _invocation(scope: scope),
      perTenantCap: 1,
      globalCap: 1,
    );
    expect(result.repairsAttempted, 0);
    expect(executor.calls, 0);
    expect(await store.listRepairAttempts(scope), isEmpty);
  });

  test(
    'audit outage before repair fails closed and records a safe result',
    () async {
      final scope = _scope();
      final audit = _MemoryAudit()..failAfterFirst = true;
      final executor = _ApplyingExecutor();
      final finding = _finding(scope);
      final service = BoundedReconciliationService(
        store: store,
        source: _StaticSource(<ReconciliationCandidate>[
          ReconciliationCandidate(
            finding: finding,
            precondition: _precondition(finding),
          ),
        ]),
        executor: executor,
        audit: audit,
        clock: () => DateTime.utc(2026, 8, 24, 9),
      );
      final result = await service.runStartup(
        invocation: _invocation(scope: scope),
        perTenantCap: 1,
        globalCap: 1,
      );
      expect(result.repairsFailed, 1);
      expect(executor.calls, 0);
      final attempts = await store.listRepairAttempts(scope);
      expect(attempts.single.safeErrorCode, 'AUDIT_UNAVAILABLE');
    },
  );

  test(
    'existing repair identity is replayed without a second mutation',
    () async {
      final scope = _scope();
      final audit = _MemoryAudit();
      final executor = _ApplyingExecutor();
      final finding = _finding(scope);
      final service = BoundedReconciliationService(
        store: store,
        source: _StaticSource(<ReconciliationCandidate>[
          ReconciliationCandidate(
            finding: finding,
            precondition: _precondition(finding),
          ),
        ]),
        executor: executor,
        audit: audit,
        clock: () => DateTime.utc(2026, 8, 24, 9),
      );
      await service.runStartup(
        invocation: _invocation(scope: scope),
        perTenantCap: 1,
        globalCap: 1,
      );
      final replay = await service.runStartup(
        invocation: _invocation(scope: scope),
        perTenantCap: 1,
        globalCap: 1,
      );
      expect(executor.calls, 1);
      expect(replay.repairsReplayed, greaterThanOrEqualTo(1));
    },
  );

  test('fairness caps bound tenants and persist backlog cursor', () async {
    final scope = ReconciliationScope(organizationId: 'org');
    final candidates = <ReconciliationCandidate>[
      for (final entry in <String>['a', 'b', 'c'])
        ReconciliationCandidate(
          finding: _finding(
            _scope(application: 'app_$entry', environment: 'env_$entry'),
            entityId: 'work_$entry',
          ),
        ),
    ];
    final audit = _MemoryAudit();
    final service = BoundedReconciliationService(
      store: store,
      source: _StaticSource(candidates),
      executor: _ApplyingExecutor(),
      audit: audit,
      clock: () => DateTime.utc(2026, 8, 24, 9),
    );
    final result = await service.runStartup(
      invocation: _invocation(scope: scope),
      perTenantCap: 1,
      globalCap: 2,
    );
    expect(result.findingsRecorded, 2);
    expect(result.backlog, isTrue);
    expect(result.cursor.position, isNotNull);
  });

  test(
    'existing audit-chain tampering blocks reconciliation audit append',
    () async {
      final auditRoot = await Directory.systemTemp.createTemp('hyfens-audit-');
      final control = FileControlPlaneStore(auditRoot);
      await control.initialize();
      addTearDown(() async {
        await control.close();
        if (await auditRoot.exists()) await auditRoot.delete(recursive: true);
      });
      final event = ReconciliationAuditEvent(
        eventType: ReconciliationAuditEventType.findingRecorded,
        scope: _scope(),
        actorId: 'operator',
        resourceId: 'finding-1',
        taxonomyCode: ReconciliationTaxonomyCode.orphanWork,
        createdAt: DateTime.utc(2026, 8, 24, 9),
      );
      final sink = ControlPlaneReconciliationAuditSink(control);
      await sink.append(event);
      final chainEntries = await control.readAuditChain();
      expect(chainEntries.single['organizationId'], 'org');
      final chainFile = File(
        '${auditRoot.path}/audit_chain/${event.digest}.json',
      );
      final chain =
          jsonDecode(await chainFile.readAsString()) as Map<String, Object?>;
      chain['recordDigest'] = _digest;
      await chainFile.writeAsString('${canonicalJson(chain)}\n', flush: true);
      await expectLater(sink.append(event), throwsA(isA<StorageConflict>()));
    },
  );

  test('File store rejects a second writer for the same root', () async {
    final second = FileReconciliationStore(temporary);
    await expectLater(second.initialize(), throwsA(isA<StorageConflict>()));
    await second.close();
  });

  final postgresUrl = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  test(
    'PostgreSQL persistence migrates, replays, and converges concurrent writers',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final scope = ReconciliationScope(
        organizationId: 'pg_$suffix',
        applicationId: 'app',
        environmentId: 'env',
      );
      final first = PostgresReconciliationStore(postgresUrl!);
      final second = PostgresReconciliationStore(postgresUrl);
      addTearDown(first.close);
      addTearDown(second.close);
      await Future.wait(<Future<void>>[
        first.initialize(),
        second.initialize(),
      ]);
      final finding = _finding(scope);
      final results = await Future.wait(
        <Future<ReconciliationRecordWriteResult>>[
          first.putFinding(finding),
          second.putFinding(finding),
        ],
      );
      expect(
        results.where(
          (value) => value == ReconciliationRecordWriteResult.created,
        ),
        hasLength(1),
      );
      expect(
        results.where(
          (value) => value == ReconciliationRecordWriteResult.replayed,
        ),
        hasLength(1),
      );
      expect(await first.readFinding(scope, finding.findingId), isNotNull);
      await first.close();
      final reopened = PostgresReconciliationStore(postgresUrl);
      addTearDown(reopened.close);
      await reopened.initialize();
      expect(await reopened.readFinding(scope, finding.findingId), isNotNull);
      final attempt = ReconciliationRepairAttempt.create(
        finding: finding,
        precondition: _precondition(finding),
        actorId: 'operator',
        result: ReconciliationRepairResult.applied,
        createdAt: DateTime.utc(2026, 8, 24, 9),
      );
      expect(
        await reopened.putRepairAttempt(attempt),
        ReconciliationRecordWriteResult.created,
      );
      expect(
        await second.readRepairAttempt(scope, attempt.repairId),
        isNotNull,
      );
      await reopened.updateFindingLifecycle(
        lifecycle: ReconciliationFindingLifecycle(
          scope: scope,
          findingId: finding.findingId,
          status: ReconciliationFindingStatus.repaired,
          version: 1,
          latestRepairId: attempt.repairId,
          updatedAt: DateTime.utc(2026, 8, 24, 9),
        ),
        expectedVersion: 0,
      );
      expect(
        await second.readFindingLifecycle(scope, finding.findingId),
        isNotNull,
      );
    },
    skip: postgresUrl == null || postgresUrl.isEmpty
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );
}
