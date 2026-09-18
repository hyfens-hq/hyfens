import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:path/path.dart' as p;

const _digest =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _scope = ReconciliationScope(
  organizationId: 'crash_org',
  applicationId: 'crash_app',
  environmentId: 'crash_env',
);
const _releasePoll = Duration(milliseconds: 20);

Future<void> main() async {
  final environment = Platform.environment;
  final rootPath = _required(environment, 'HYFENS_CRASH_ROOT');
  final markerPath = _required(environment, 'HYFENS_CRASH_MARKER');
  final mode = _required(environment, 'HYFENS_CRASH_MODE');
  final releasePath = environment['HYFENS_CRASH_RELEASE'];
  final root = Directory(rootPath);
  await root.create(recursive: true);
  final marker = File(markerPath);
  final control = _CrashControl(
    marker,
    releasePath == null ? null : File(releasePath),
  );

  if (mode == 'postgres-owner' || mode == 'postgres-run') {
    await _runPostgres(
      environment: environment,
      control: control,
      holdCallback: mode == 'postgres-owner',
    );
    return;
  }

  final reconciliationRoot = Directory(p.join(root.path, 'reconciliation'));
  final controlRoot = Directory(p.join(root.path, 'control'));
  final store = FileReconciliationStore(reconciliationRoot);
  final controlStore = FileControlPlaneStore(controlRoot);
  await store.initialize();
  await controlStore.initialize();
  final projection = _CrashProjection(
    File(p.join(root.path, 'projection.json')),
  );
  final audit = _CrashAuditSink(
    ControlPlaneReconciliationAuditSink(controlStore),
    control,
    mode,
  );
  final source = _CrashCandidateSource();
  final executor = _CrashExecutor(projection, control, mode);
  final service = BoundedReconciliationService(
    store: store,
    source: source,
    executor: executor,
    audit: audit,
    clock: () => DateTime.utc(2026, 8, 24, 10),
  );
  final owner = _CrashOwnership(control, mode);
  final runner = ReconciliationPeriodicRunner(
    config: const ReconciliationPeriodicConfig(
      enabled: true,
      interval: Duration(seconds: 5),
      jitter: Duration.zero,
      startupDelay: Duration(seconds: 5),
      maximumBackoff: Duration(seconds: 20),
      shutdownTimeout: Duration(seconds: 1),
    ),
    ownership: owner,
    invokeBoundedReconciliation: () async {
      try {
        await service.runStartup(
          invocation: _invocation(),
          perTenantCap: 2,
          globalCap: 2,
        );
      } on Object catch (error, stackTrace) {
        stderr.writeln('crash-worker reconciliation error: $error');
        stderr.writeln(stackTrace);
        rethrow;
      }
    },
  );

  try {
    await control.mark('READY');
    switch (mode) {
      case 'idle':
        await control.mark('IDLE');
        await control.waitForRelease();
      case 'ownership-before-callback':
      case 'before-cas':
      case 'after-cas':
      case 'audit-before-request':
      case 'audit-after-request':
      case 'audit-after-mutation':
        final outcome = await runner.runTick();
        await control.mark('OUTCOME_${outcome.wireName}');
      case 'callback-complete':
        final outcome = await runner.runTick();
        await control.mark('CALLBACK_COMPLETE_${outcome.wireName}');
        await control.waitForRelease();
      case 'restart':
        final outcome = await runner.runTick();
        await control.mark('RESTART_COMPLETE_${outcome.wireName}');
      default:
        throw ArgumentError('Unsupported crash worker mode: $mode');
    }
  } finally {
    await runner.stop();
    await controlStore.close();
    await store.close();
  }
}

Future<void> _runPostgres({
  required Map<String, String> environment,
  required _CrashControl control,
  required bool holdCallback,
}) async {
  final url = _required(environment, 'HYFENS_TEST_POSTGRES_URL');
  final store = PostgresReconciliationStore(url);
  await store.initialize();
  final runner = ReconciliationPeriodicRunner(
    config: const ReconciliationPeriodicConfig(
      enabled: true,
      interval: Duration(seconds: 5),
      jitter: Duration.zero,
      startupDelay: Duration(seconds: 5),
      maximumBackoff: Duration(seconds: 20),
      shutdownTimeout: Duration(seconds: 1),
    ),
    ownership: PostgresReconciliationPeriodicOwnership(store),
    invokeBoundedReconciliation: () async {
      await control.mark('CALLBACK_ENTERED');
      if (holdCallback) await control.waitForRelease();
      await store.checkReadiness();
    },
  );
  try {
    await control.mark('READY');
    final outcome = await runner.runTick();
    await control.mark('OUTCOME_${outcome.wireName}');
  } finally {
    await runner.stop();
    await store.close();
  }
}

String _required(Map<String, String> values, String key) {
  final value = values[key];
  if (value == null || value.isEmpty) throw ArgumentError('Missing $key');
  return value;
}

ReconciliationInvocation _invocation() => ReconciliationInvocation.create(
  scope: _scope,
  actorId: 'crash-worker',
  principalId: 'crash-principal',
  storageMode: ReconciliationStorageMode.file,
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
  startedAt: DateTime.now().toUtc(),
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

ReconciliationPrecondition _precondition(ReconciliationFinding finding) =>
    ReconciliationPrecondition(
      scope: finding.scope,
      findingId: finding.findingId,
      entityId: finding.entityId,
      expectedWorkVersion: 1,
      expectedScheduleRevision: 'schedule-rev-1',
      currentRolloutRevision: 'rollout-rev-1',
      sourceDigests: finding.sourceDigests,
      targetBinding: const <String, String>{'work': 'crash-work'},
      taxonomyCode: finding.code,
      action: ReconciliationRepairAction.linkExistingEvaluation,
    );

final class _CrashControl {
  _CrashControl(this.marker, this.release);

  final File marker;
  final File? release;

  Future<void> mark(String value) async {
    await marker.writeAsString('$value\n', mode: FileMode.append, flush: true);
  }

  Future<void> waitForRelease() async {
    final release = this.release;
    if (release == null) return;
    while (!await release.exists()) {
      await Future<void>.delayed(_releasePoll);
    }
  }
}

final class _CrashOwnership implements ReconciliationPeriodicOwnership {
  _CrashOwnership(this.control, this.mode);

  final _CrashControl control;
  final String mode;

  @override
  Future<bool> runIfOwned(Future<void> Function() action) async {
    if (mode == 'idle' || mode == 'ownership-before-callback') {
      await control.mark('OWNERSHIP_ACQUIRED');
      await control.waitForRelease();
    }
    await action();
    return true;
  }
}

final class _CrashCandidateSource implements ReconciliationCandidateSource {
  @override
  Future<List<ReconciliationCandidate>> discover(
    ReconciliationInvocation invocation,
  ) async {
    final finding = _finding();
    return <ReconciliationCandidate>[
      ReconciliationCandidate(
        finding: finding,
        precondition: _precondition(finding),
      ),
    ];
  }
}

final class _CrashProjection {
  _CrashProjection(this.file);

  final File file;

  Future<Map<String, int>> read() async {
    if (!await file.exists())
      return const <String, int>{'version': 1, 'mutations': 0};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map ||
        decoded['version'] is! int ||
        decoded['mutations'] is! int) {
      throw const FormatException('Malformed crash projection');
    }
    return <String, int>{
      'version': decoded['version'] as int,
      'mutations': decoded['mutations'] as int,
    };
  }

  Future<bool> applyIfNeeded(int expectedVersion) async {
    final current = await read();
    final version = current['version']!;
    if (version == expectedVersion) {
      final next = <String, int>{
        'version': version + 1,
        'mutations': current['mutations']! + 1,
      };
      final temporary = File('${file.path}.tmp-$pid');
      await temporary.writeAsString(jsonEncode(next), flush: true);
      await temporary.rename(file.path);
      return true;
    }
    if (version == expectedVersion + 1) return false;
    throw const StorageConflict('Crash projection CAS precondition failed');
  }
}

final class _CrashExecutor implements ReconciliationRepairExecutor {
  _CrashExecutor(this.projection, this.control, this.mode);

  final _CrashProjection projection;
  final _CrashControl control;
  final String mode;

  @override
  Future<ReconciliationRepairExecution> execute(
    ReconciliationRepairContext context,
  ) async {
    if (mode == 'before-cas') {
      await control.mark('BEFORE_CAS');
      await control.waitForRelease();
    }
    final expectedVersion = context.precondition.expectedWorkVersion;
    if (expectedVersion == null) {
      throw const FormatException('Crash test precondition lacks work version');
    }
    final changed = await projection.applyIfNeeded(expectedVersion);
    if (mode == 'after-cas') {
      await control.mark('AFTER_CAS');
      await control.waitForRelease();
    }
    return ReconciliationRepairExecution(
      result: ReconciliationRepairResult.applied,
      postconditionVerified: true,
      safeErrorCode: changed ? null : 'IDEMPOTENT_REPLAY',
    );
  }
}

final class _CrashAuditSink implements ReconciliationAuditSink {
  _CrashAuditSink(this.delegate, this.control, this.mode);

  final ReconciliationAuditSink delegate;
  final _CrashControl control;
  final String mode;

  @override
  Future<void> append(ReconciliationAuditEvent event) async {
    final isRepairRequest =
        event.eventType == ReconciliationAuditEventType.repairRequested;
    final isTerminal =
        event.eventType == ReconciliationAuditEventType.findingRecorded &&
        event.resourceId != _finding().findingId;
    if (mode == 'audit-before-request' && isRepairRequest) {
      await control.mark('AUDIT_BEFORE_REQUEST');
      await control.waitForRelease();
    }
    if (mode == 'audit-after-mutation' && isTerminal) {
      await control.mark('AUDIT_AFTER_MUTATION');
      await control.waitForRelease();
    }
    await delegate.append(event);
    if (mode == 'audit-after-request' && isRepairRequest) {
      await control.mark('AUDIT_AFTER_REQUEST');
      await control.waitForRelease();
    }
  }
}
