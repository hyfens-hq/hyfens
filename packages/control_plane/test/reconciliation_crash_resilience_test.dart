import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _worker = 'test/fixtures/reconciliation_crash_worker.dart';
const _digest =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _scope = ReconciliationScope(
  organizationId: 'crash_org',
  applicationId: 'crash_app',
  environmentId: 'crash_env',
);

void main() {
  final postgresUrl = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  final postgresUnavailable = postgresUrl == null || postgresUrl.isEmpty;
  final postgresSkip = postgresUnavailable
      ? 'HYFENS_TEST_POSTGRES_URL is not configured'
      : false;

  test(
    'PROCESS_KILL and CRASH_RESTART converge before and after CAS',
    () async {
      await _runKilledFileScenario('idle', 'IDLE', expectMutation: 0);
      await _runKilledFileScenario(
        'ownership-before-callback',
        'OWNERSHIP_ACQUIRED',
        expectMutation: 0,
      );
      await _runKilledFileScenario(
        'before-cas',
        'BEFORE_CAS',
        expectMutation: 0,
      );
      await _runKilledFileScenario(
        'after-cas',
        'AFTER_CAS',
        expectMutation: 1,
        expectCommittedBeforeRestart: true,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'audit-boundary process loss preserves ordering and converges',
    () async {
      for (final scenario in const <String, String>{
        'audit-before-request': 'AUDIT_BEFORE_REQUEST',
        'audit-after-request': 'AUDIT_AFTER_REQUEST',
        'audit-after-mutation': 'AUDIT_AFTER_MUTATION',
      }.entries) {
        final root = await Directory.systemTemp.createTemp(
          'hyfens-crash-audit-${scenario.key}-',
        );
        try {
          final child = await _spawn(root, scenario.key, hold: true);
          await _waitForMarker(child, scenario.value);
          await _kill(child);
          if (scenario.key == 'audit-after-mutation') {
            expect(_projection(root)['mutations'], 1);
          } else {
            expect(_projection(root)['mutations'], 0);
          }
          await _runRestart(root);
          await _expectRecovered(root);
        } finally {
          if (await root.exists()) await root.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('callback completion and File restart do not replay a repair', () async {
    final root = await Directory.systemTemp.createTemp(
      'hyfens-crash-callback-',
    );
    try {
      final child = await _spawn(root, 'callback-complete', hold: true);
      await _waitForMarker(child, 'CALLBACK_COMPLETE_SUCCESS');
      await _release(child);
      expect(await child.exitCode.timeout(const Duration(seconds: 10)), 0);
      await _expectRecovered(root);
      final store = FileReconciliationStore(
        Directory(p.join(root.path, 'reconciliation')),
      );
      await store.initialize();
      await store.checkReadiness();
      await store.close();
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('malformed projection fails closed after restart', () async {
    final root = await Directory.systemTemp.createTemp(
      'hyfens-crash-malformed-',
    );
    try {
      final first = await _spawn(root, 'restart');
      await _waitForMarker(first, 'RESTART_COMPLETE_SUCCESS');
      expect(await first.exitCode.timeout(const Duration(seconds: 10)), 0);
      await File(p.join(root.path, 'projection.json'))
          .writeAsString('{not-json', flush: true);
      final second = await _spawn(root, 'restart');
      // The runner completes the bounded pass successfully because the
      // malformed executor input is converted into a durable failed attempt;
      // the projection itself remains untouched and the process does not
      // crash or spin.
      await _waitForMarker(second, 'RESTART_COMPLETE_SUCCESS');
      expect(await second.exitCode.timeout(const Duration(seconds: 10)), 0);
      expect(
        await File(p.join(root.path, 'projection.json')).readAsString(),
        '{not-json',
      );
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('audit tamper remains invalid and fails closed after restart', () async {
    final root = await Directory.systemTemp.createTemp(
      'hyfens-crash-audit-tamper-',
    );
    try {
      final first = await _spawn(root, 'restart');
      await _waitForMarker(first, 'RESTART_COMPLETE_SUCCESS');
      expect(await first.exitCode.timeout(const Duration(seconds: 10)), 0);
      await _tamperAuditChain(root);
      final before = await _auditEntries(root);
      final second = await _spawn(root, 'restart');
      await _waitForMarker(second, 'RESTART_COMPLETE_FAILURE');
      expect(await second.exitCode.timeout(const Duration(seconds: 10)), 0);
      final after = await _auditEntries(root);
      expect(verifyAuditChain(after).valid, isFalse);
      expect(after.length, before.length);
      expect(_projection(root)['mutations'], 1);
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'PROCESS_KILL_HANDOFF releases PostgreSQL ownership for the next process',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-crash-pg-kill-',
      );
      try {
        final first = await _spawn(root, 'postgres-owner', hold: true);
        await _waitForMarker(first, 'CALLBACK_ENTERED');
        await _kill(first);
        final second = await _spawn(root, 'postgres-run');
        await _waitForMarker(second, 'OUTCOME_SUCCESS');
        expect(await second.exitCode.timeout(const Duration(seconds: 15)), 0);
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
    skip: postgresUnavailable || Platform.isWindows
        ? 'PostgreSQL process harness is unavailable'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'POSTGRESQL_SESSION_KILL releases dedicated ownership and bounds failure',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-crash-pg-session-',
      );
      try {
        final first = await _spawn(root, 'postgres-owner', hold: true);
        await _waitForMarker(first, 'CALLBACK_ENTERED');
        final pid = await _waitForAdvisoryPid(postgresUrl!);
        expect(await _terminateBackend(postgresUrl, pid), isTrue);
        await _release(first);
        await _waitForMarker(first, 'OUTCOME_FAILURE');
        expect(await first.exitCode.timeout(const Duration(seconds: 15)), 0);
        final second = await _spawn(root, 'postgres-run');
        await _waitForMarker(second, 'OUTCOME_SUCCESS');
        expect(await second.exitCode.timeout(const Duration(seconds: 15)), 0);
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
    skip: postgresUnavailable || Platform.isWindows
        ? 'PostgreSQL process harness is unavailable'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'POSTGRESQL_DISCONNECT converges after persistence session loss',
    () async {
      await _runPersistenceDisconnect(
        postgresUrl!,
        PostgresDisconnectPoint.findingCommitBefore,
      );
      await _runPersistenceDisconnect(
        postgresUrl,
        PostgresDisconnectPoint.repairAttemptCommitAfter,
      );
    },
    skip: postgresSkip,
  );

  test('TENANT_ISOLATION and TENANT_FAIRNESS survive File restart', () async {
    final root = await Directory.systemTemp.createTemp('hyfens-crash-tenants-');
    final store = FileReconciliationStore(
      Directory(p.join(root.path, 'reconciliation')),
    );
    final executor = _TenantExecutor();
    try {
      await store.initialize();
      final first = await _tenantService(store, executor).runStartup(
        invocation: _tenantInvocation(),
        perTenantCap: 1,
        globalCap: 2,
      );
      expect(first.findingsRecorded, 2);
      expect(executor.calls, 2);
      await store.close();

      final reopened = FileReconciliationStore(
        Directory(p.join(root.path, 'reconciliation')),
      );
      await reopened.initialize();
      final second = await _tenantService(reopened, executor).runStartup(
        invocation: _tenantInvocation(),
        perTenantCap: 1,
        globalCap: 2,
      );
      expect(second.repairsReplayed, 2);
      expect(executor.calls, 2);
      expect(
        await reopened.listFindings(_tenantScope('tenant_a')),
        hasLength(1),
      );
      expect(
        await reopened.listFindings(_tenantScope('tenant_b')),
        hasLength(1),
      );
      expect(
        await reopened.listFindings(
          ReconciliationScope(
            organizationId: _scope.organizationId,
            applicationId: 'tenant_c',
          ),
        ),
        isEmpty,
      );
      await reopened.close();
    } finally {
      await store.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('CRASH_RESTART metrics and diagnostics remain process-local', () async {
    final first = ReconciliationPeriodicRunner(
      config: const ReconciliationPeriodicConfig(enabled: true),
      invokeBoundedReconciliation: () async {},
    );
    expect(await first.runTick(), ReconciliationPeriodicRunOutcome.success);
    expect(first.metrics.runsTotal, 1);
    expect(first.statusJson()['lastRunOutcome'], 'SUCCESS');

    final restarted = ReconciliationPeriodicRunner(
      config: first.config,
      invokeBoundedReconciliation: () async {},
    );
    expect(restarted.metrics.runsTotal, 0);
    expect(restarted.statusJson()['started'], isFalse);
    expect(restarted.statusJson()['running'], isFalse);
    expect(restarted.statusJson()['lockOwned'], isFalse);
    expect(restarted.statusJson()['lastRunOutcome'], isNull);
  });
}

Future<void> _runKilledFileScenario(
  String mode,
  String marker, {
  required int expectMutation,
  bool expectCommittedBeforeRestart = false,
}) async {
  final root = await Directory.systemTemp.createTemp('hyfens-crash-$mode-');
  try {
    final child = await _spawn(root, mode, hold: true);
    await _waitForMarker(child, marker);
    await _kill(child);
    expect(_projection(root)['mutations'], expectMutation);
    if (expectMutation == 0) {
      final store = FileReconciliationStore(
        Directory(p.join(root.path, 'reconciliation')),
      );
      await store.initialize();
      expect(
        await store.readFinding(_scope, _finding().findingId),
        mode == 'before-cas' ? isNotNull : isNull,
      );
      await store.close();
    }
    if (expectCommittedBeforeRestart) {
      expect(_projection(root)['version'], 2);
    }
    await _runRestart(root);
    await _expectRecovered(root);
  } finally {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<void> _runRestart(Directory root) async {
  final child = await _spawn(root, 'restart');
  await _waitForMarker(child, 'RESTART_COMPLETE_SUCCESS');
  expect(await child.exitCode.timeout(const Duration(seconds: 10)), 0);
}

Future<_CrashChild> _spawn(
  Directory root,
  String mode, {
  bool hold = false,
}) async {
  final marker = File(p.join(root.path, '$mode.marker'));
  final release = File(p.join(root.path, '$mode.release'));
  if (await marker.exists()) await marker.delete();
  if (await release.exists()) await release.delete();
  final environment = <String, String>{
    ...Platform.environment,
    'HYFENS_CRASH_ROOT': root.path,
    'HYFENS_CRASH_MARKER': marker.path,
    'HYFENS_CRASH_MODE': mode,
    if (hold) 'HYFENS_CRASH_RELEASE': release.path,
  };
  final process = await Process.start(
    Platform.resolvedExecutable,
    <String>[p.join(Directory.current.path, _worker)],
    workingDirectory: Directory.current.path,
    environment: environment,
  );
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  final child = _CrashChild(process, marker, release, stdout, stderr);
  child.exitCode.then((_) => child.exited = true);
  return child;
}

Future<void> _waitForMarker(
  _CrashChild child,
  String expected, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    // A worker writes its terminal marker immediately before exiting. Check
    // the marker first so the exit notification cannot win that race.
    if (await child.marker.exists()) {
      final value = await child.marker.readAsString();
      if (value.split('\n').contains(expected)) {
        return;
      }
    }
    if (child.exited) {
      final output = await Future.wait(<Future<String>>[
        child.stdout,
        child.stderr,
      ]);
      final exitCode = await child.exitCode;
      fail(
        'Child exited before $expected; exitCode=$exitCode '
        'executable=${Platform.resolvedExecutable} '
        'cwd=${Directory.current.path} '
        'stdout=${output[0]} stderr=${output[1]}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  final output = await Future.wait(<Future<String>>[
    child.stdout,
    child.stderr,
  ]);
  fail(
    'Timed out waiting for $expected; stdout=${output[0]} stderr=${output[1]}',
  );
}

Future<void> _release(_CrashChild child) async {
  await child.release.writeAsString('release\n', flush: true);
}

Future<void> _kill(_CrashChild child) async {
  expect(child.process.kill(ProcessSignal.sigkill), isTrue);
  await child.exitCode.timeout(const Duration(seconds: 10));
  // Drain both pipes before spawning the recovery process. On macOS the Dart
  // VM can report the child exit before its stdio handles are fully closed;
  // leaving those futures pending makes rapid crash/restart sequences
  // intermittently produce an exited-zero worker with no startup marker.
  await Future.wait(<Future<String>>[child.stdout, child.stderr])
      .timeout(const Duration(seconds: 10));
}

Map<String, int> _projection(Directory root) {
  final file = File(p.join(root.path, 'projection.json'));
  if (!file.existsSync())
    return const <String, int>{'version': 1, 'mutations': 0};
  final value = jsonDecode(file.readAsStringSync());
  if (value is! Map || value['version'] is! int || value['mutations'] is! int) {
    throw const FormatException('Malformed test projection');
  }
  return <String, int>{
    'version': value['version'] as int,
    'mutations': value['mutations'] as int,
  };
}

Future<void> _expectRecovered(Directory root) async {
  expect(_projection(root), <String, int>{'version': 2, 'mutations': 1});
  final store = FileReconciliationStore(
    Directory(p.join(root.path, 'reconciliation')),
  );
  await store.initialize();
  try {
    final finding = _finding();
    final attempt = await store.readRepairAttempt(
      _scope,
      ReconciliationRepairAttempt.deriveRepairId(
        finding.findingId,
        ReconciliationRepairAction.linkExistingEvaluation,
      ),
    );
    expect(attempt, isNotNull);
    expect(attempt!.result, ReconciliationRepairResult.applied);
    final lifecycle = await store.readFindingLifecycle(
      _scope,
      finding.findingId,
    );
    expect(lifecycle?.status, ReconciliationFindingStatus.repaired);
    expect(lifecycle?.version, 1);
    final cursor = await store.readCursor(_scope);
    expect(cursor?.version, 1);
    expect(cursor?.cursor.position, finding.findingId);
  } finally {
    await store.close();
  }
  final chain = await _auditEntries(root);
  expect(verifyAuditChain(chain).valid, isTrue);
}

Future<List<Map<String, Object?>>> _auditEntries(Directory root) async {
  final store = FileControlPlaneStore(Directory(p.join(root.path, 'control')));
  await store.initialize();
  try {
    return await store.readAuditChain();
  } finally {
    await store.close();
  }
}

Future<void> _tamperAuditChain(Directory root) async {
  final directory = Directory(p.join(root.path, 'control', 'audit_chain'));
  final files =
      (await directory.list().where((entry) => entry is File).toList())
          .whereType<File>()
          .toList();
  expect(files, isNotEmpty);
  final value = jsonDecode(await files.first.readAsString());
  expect(value, isA<Map>());
  final map = (value as Map).cast<String, Object?>();
  final body = (map['body'] as Map).cast<String, Object?>();
  body['tampered'] = true;
  map['body'] = body;
  await files.first.writeAsString(jsonEncode(map), flush: true);
}

Future<String> _psql(String url, String sql) async {
  final result = await Process.run('psql', <String>[
    url,
    '-At',
    '-v',
    'ON_ERROR_STOP=1',
    '-c',
    sql,
  ]);
  if (result.exitCode != 0) {
    throw StateError('PostgreSQL command failed: ${result.stderr}');
  }
  return '${result.stdout}'.trim();
}

Future<int> _waitForAdvisoryPid(String url) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final value = await _psql(
      url,
      'SELECT pid FROM pg_locks WHERE locktype = \'advisory\' '
      'AND granted AND classid = 0 AND objid = $reconciliationPeriodicAdvisoryLockKey '
      'ORDER BY pid LIMIT 1',
    );
    if (value.isNotEmpty) return int.parse(value.split('\n').first);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for periodic advisory owner');
}

Future<bool> _terminateBackend(String url, int backendPid) async {
  final value = await _psql(url, 'SELECT pg_terminate_backend($backendPid)');
  return value == 't';
}

Future<void> _runPersistenceDisconnect(
  String url,
  PostgresDisconnectPoint point,
) async {
  final temporary = await Directory.systemTemp.createTemp(
    'hyfens-pg-disconnect-${point.name}-',
  );
  final projection = _TestProjection(
    File(p.join(temporary.path, 'projection')),
  );
  await _psql(
    url,
    'DELETE FROM control_plane_reconciliation_cursors '
    'WHERE organization_id = \'crash_org\'; '
    'DELETE FROM control_plane_reconciliation_lifecycle '
    'WHERE organization_id = \'crash_org\'; '
    'DELETE FROM control_plane_reconciliation_repairs '
    'WHERE organization_id = \'crash_org\'; '
    'DELETE FROM control_plane_reconciliation_findings '
    'WHERE organization_id = \'crash_org\';',
  );
  final first = PostgresReconciliationStore(
    url,
    disconnectInjector: (candidate) => candidate == point,
  );
  await first.initialize();
  final firstRunner = _postgresRunner(first, projection);
  expect(await firstRunner.runTick(), ReconciliationPeriodicRunOutcome.failure);
  await firstRunner.stop();
  await first.close();

  final second = PostgresReconciliationStore(url);
  await second.initialize();
  final secondRunner = _postgresRunner(second, projection);
  expect(
    await secondRunner.runTick(),
    ReconciliationPeriodicRunOutcome.success,
  );
  await secondRunner.stop();
  expect(projection.mutations, 1);
  final finding = _finding();
  final attempt = await second.readRepairAttempt(
    _scope,
    ReconciliationRepairAttempt.deriveRepairId(
      finding.findingId,
      ReconciliationRepairAction.linkExistingEvaluation,
    ),
  );
  expect(attempt, isNotNull);
  final lifecycle = await second.readFindingLifecycle(
    _scope,
    finding.findingId,
  );
  expect(lifecycle?.status, ReconciliationFindingStatus.repaired);
  expect((await second.readCursor(_scope))?.version, 1);
  await second.close();
  await temporary.delete(recursive: true);
}

ReconciliationPeriodicRunner _postgresRunner(
  PostgresReconciliationStore store,
  _TestProjection projection,
) {
  final service = BoundedReconciliationService(
    store: store,
    source: _TestSource(),
    executor: _TestExecutor(projection),
    audit: _TestAudit(),
    clock: () => DateTime.utc(2026, 8, 24, 10),
  );
  return ReconciliationPeriodicRunner(
    config: const ReconciliationPeriodicConfig(enabled: true),
    ownership: PostgresReconciliationPeriodicOwnership(store),
    invokeBoundedReconciliation: () => service.runStartup(
      invocation: _invocation(ReconciliationStorageMode.postgres),
      perTenantCap: 2,
      globalCap: 2,
    ),
  );
}

ReconciliationInvocation _invocation(ReconciliationStorageMode storageMode) =>
    ReconciliationInvocation.create(
      scope: _scope,
      actorId: 'crash-test',
      principalId: 'crash-principal',
      storageMode: storageMode,
      policy: ReconciliationPolicy(
        policyVersion: 1,
        maximumRecordsScanned: 10,
        maximumTenantsScanned: 2,
        maximumLinkageDepth: 2,
        maximumFindings: 2,
        maximumRepairs: 1,
        maximumConcurrentRepairs: 1,
        maximumRetryAttempts: 1,
        lookbackHorizon: const Duration(hours: 1),
        maximumDiagnosticHistory: 2,
        maximumAuditLookupDepth: 2,
        fairnessPolicyVersion: 1,
      ),
      startedAt: DateTime.utc(2026, 8, 24, 10),
    );

ReconciliationFinding _finding() => ReconciliationFinding.create(
  scope: _scope,
  code: ReconciliationTaxonomyCode.workEvaluationLinkMissing,
  entityType: 'work',
  entityId: 'crash-work',
  sourceDigests: const <String, String>{'evaluation': _digest},
  observedVersions: const <String, int>{'work': 1},
  firstObservedAt: DateTime.utc(2026, 8, 24, 8),
  lastObservedAt: DateTime.utc(2026, 8, 24, 8, 1),
  status: ReconciliationFindingStatus.open,
  safeDetailCode: 'LINK_MISSING',
);

final class _CrashChild {
  _CrashChild(
    this.process,
    this.marker,
    this.release,
    this.stdout,
    this.stderr,
  );

  final Process process;
  final File marker;
  final File release;
  final Future<String> stdout;
  final Future<String> stderr;
  bool exited = false;
  late final Future<int> exitCode = process.exitCode;
}

final class _TestSource implements ReconciliationCandidateSource {
  @override
  Future<List<ReconciliationCandidate>> discover(
    ReconciliationInvocation invocation,
  ) async {
    final finding = _finding();
    return <ReconciliationCandidate>[
      ReconciliationCandidate(
        finding: finding,
        precondition: ReconciliationPrecondition(
          scope: _scope,
          findingId: finding.findingId,
          entityId: finding.entityId,
          expectedWorkVersion: 1,
          expectedScheduleRevision: 'schedule-rev-1',
          currentRolloutRevision: 'rollout-rev-1',
          sourceDigests: finding.sourceDigests,
          targetBinding: const <String, String>{'work': 'crash-work'},
          taxonomyCode: finding.code,
          action: ReconciliationRepairAction.linkExistingEvaluation,
        ),
      ),
    ];
  }
}

final class _TestProjection {
  _TestProjection(this.file);

  final File file;
  int mutations = 0;

  Future<void> apply() async {
    if (mutations > 0) return;
    mutations++;
    await file.writeAsString('$mutations\n', flush: true);
  }
}

final class _TestExecutor implements ReconciliationRepairExecutor {
  _TestExecutor(this.projection);

  final _TestProjection projection;

  @override
  Future<ReconciliationRepairExecution> execute(
    ReconciliationRepairContext context,
  ) async {
    await projection.apply();
    return const ReconciliationRepairExecution(
      result: ReconciliationRepairResult.applied,
      postconditionVerified: true,
    );
  }
}

final class _TestAudit implements ReconciliationAuditSink {
  @override
  Future<void> append(ReconciliationAuditEvent event) async {}
}

ReconciliationScope _tenantScope(String application) => ReconciliationScope(
  organizationId: _scope.organizationId,
  applicationId: application,
  environmentId: 'env',
);

ReconciliationInvocation _tenantInvocation() => ReconciliationInvocation.create(
  scope: ReconciliationScope(organizationId: _scope.organizationId),
  actorId: 'tenant-crash-test',
  principalId: 'tenant-crash-principal',
  storageMode: ReconciliationStorageMode.file,
  policy: ReconciliationPolicy(
    policyVersion: 1,
    maximumRecordsScanned: 10,
    maximumTenantsScanned: 2,
    maximumLinkageDepth: 2,
    maximumFindings: 2,
    maximumRepairs: 2,
    maximumConcurrentRepairs: 1,
    maximumRetryAttempts: 1,
    lookbackHorizon: const Duration(hours: 1),
    maximumDiagnosticHistory: 2,
    maximumAuditLookupDepth: 2,
    fairnessPolicyVersion: 1,
  ),
  startedAt: DateTime.utc(2026, 8, 24, 10),
);

BoundedReconciliationService _tenantService(
  ReconciliationPersistenceStore store,
  _TenantExecutor executor,
) => BoundedReconciliationService(
  store: store,
  source: _TenantSource(),
  executor: executor,
  audit: _TestAudit(),
  clock: () => DateTime.utc(2026, 8, 24, 10),
);

final class _TenantSource implements ReconciliationCandidateSource {
  @override
  Future<List<ReconciliationCandidate>> discover(
    ReconciliationInvocation invocation,
  ) async => <ReconciliationCandidate>[
    for (final application in const <String>['tenant_a', 'tenant_b'])
      _tenantCandidate(_tenantScope(application), application),
  ];
}

ReconciliationCandidate _tenantCandidate(
  ReconciliationScope scope,
  String tenant,
) {
  final finding = ReconciliationFinding.create(
    scope: scope,
    code: ReconciliationTaxonomyCode.workEvaluationLinkMissing,
    entityType: 'work',
    entityId: '${tenant}_work',
    sourceDigests: const <String, String>{'evaluation': _digest},
    observedVersions: const <String, int>{'work': 1},
    firstObservedAt: DateTime.utc(2026, 8, 24, 8),
    lastObservedAt: DateTime.utc(2026, 8, 24, 8, 1),
    status: ReconciliationFindingStatus.open,
    safeDetailCode: 'LINK_MISSING',
  );
  return ReconciliationCandidate(
    finding: finding,
    precondition: ReconciliationPrecondition(
      scope: scope,
      findingId: finding.findingId,
      entityId: finding.entityId,
      expectedWorkVersion: 1,
      expectedScheduleRevision: 'schedule-rev-1',
      currentRolloutRevision: 'rollout-rev-1',
      sourceDigests: finding.sourceDigests,
      targetBinding: <String, String>{'work': finding.entityId},
      taxonomyCode: finding.code,
      action: ReconciliationRepairAction.linkExistingEvaluation,
    ),
  );
}

final class _TenantExecutor implements ReconciliationRepairExecutor {
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
