import 'audit.dart';
import 'errors.dart';
import 'persistence.dart';
import 'reconciliation_domain.dart';
import 'reconciliation_periodic.dart';
import 'reconciliation_persistence.dart';

typedef ReconciliationDiagnosticsAuthorizer = Future<void> Function({
  required String token,
  required ReconciliationScope scope,
});

enum ReconciliationReadinessCode {
  ready,
  reconciliationStoreUnavailable,
  schemaIncompatible,
  auditInvalid,
  auditStoreUnavailable,
  authoritativeStoreUnavailable,
}

extension ReconciliationReadinessCodeWire on ReconciliationReadinessCode {
  String get wireName => switch (this) {
    ReconciliationReadinessCode.ready => 'READY',
    ReconciliationReadinessCode.reconciliationStoreUnavailable =>
      'RECONCILIATION_STORE_UNAVAILABLE',
    ReconciliationReadinessCode.schemaIncompatible => 'SCHEMA_INCOMPATIBLE',
    ReconciliationReadinessCode.auditInvalid => 'AUDIT_INVALID',
    ReconciliationReadinessCode.auditStoreUnavailable =>
      'AUDIT_STORE_UNAVAILABLE',
    ReconciliationReadinessCode.authoritativeStoreUnavailable =>
      'AUTHORITATIVE_STORE_UNAVAILABLE',
  };
}

final class ReconciliationReadinessResult {
  const ReconciliationReadinessResult({
    required this.ready,
    required this.code,
  });

  final bool ready;
  final ReconciliationReadinessCode code;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': ready ? 'ready' : 'not_ready',
    'code': code.wireName,
  };
}

/// Bounded process-local reconciliation measurements.
///
/// These counters are observational and reset on process restart. They never
/// act as an audit record and never invoke a reconciler or mutation seam.
final class ReconciliationObservabilityMetrics {
  ReconciliationObservabilityMetrics({
    required String backend,
    ReconciliationPeriodicMetrics? periodicMetrics,
  }) : backend = _backend(backend),
       findingClassCounts = <String, int>{
         for (final code in ReconciliationTaxonomyCode.values) code.wireName: 0,
       },
       findingStatusCounts = <String, int>{
         for (final status in ReconciliationFindingStatus.values)
           status.wireName: 0,
       },
       repairOutcomeCounts = <String, int>{
         for (final result in ReconciliationRepairResult.values)
           result.wireName: 0,
       },
       executionModeCounts = <String, int>{
         for (final mode in ReconciliationExecutionMode.values) mode.name: 0,
       },
       periodic = periodicMetrics ?? ReconciliationPeriodicMetrics();

  final String backend;
  final Map<String, int> findingClassCounts;
  final Map<String, int> findingStatusCounts;
  final Map<String, int> repairOutcomeCounts;
  final Map<String, int> executionModeCounts;
  final ReconciliationPeriodicMetrics periodic;

  int findingsTotal = 0;
  int findingsReportOnly = 0;
  int repairAttemptsTotal = 0;
  int repairApplied = 0;
  int repairReplayed = 0;
  int repairFailed = 0;
  int repairConflicted = 0;
  int storeErrors = 0;
  int auditInvalid = 0;
  int schemaIncompatible = 0;
  int malformedRecords = 0;
  int backlogCount = 0;
  int cursorLagSeconds = 0;
  DateTime? lastBoundedRunStartedAt;
  DateTime? lastBoundedRunCompletedAt;
  ReconciliationExecutionMode? lastBoundedRunMode;
  int lastFindingsSeen = 0;
  int lastRepairsAttempted = 0;
  int lastRepairsApplied = 0;
  int lastReplays = 0;
  int lastReportOnly = 0;
  int lastFailures = 0;

  void recordRun(
    ReconciliationRunResult result,
    ReconciliationExecutionMode mode,
  ) {
    final completedAt = DateTime.now().toUtc();
    executionModeCounts[mode.name] = (executionModeCounts[mode.name] ?? 0) + 1;
    for (final entry in result.findingsByCode.entries) {
      findingClassCounts[entry.key.wireName] =
          (findingClassCounts[entry.key.wireName] ?? 0) + entry.value;
      findingsTotal += entry.value;
      if (reconciliationMetadataFor(entry.key).repairability ==
          ReconciliationRepairability.reportOnlyImmutableDivergence) {
        findingsReportOnly += entry.value;
      }
    }
    for (final entry in result.findingsByStatus.entries) {
      findingStatusCounts[entry.key.wireName] =
          (findingStatusCounts[entry.key.wireName] ?? 0) + entry.value;
    }
    repairAttemptsTotal += result.repairsAttempted;
    repairApplied += result.repairsApplied;
    repairReplayed += result.repairsReplayed;
    repairFailed += result.repairsFailed;
    repairConflicted += result.repairsConflicted;
    repairOutcomeCounts[ReconciliationRepairResult.applied.wireName] =
        repairApplied;
    repairOutcomeCounts[ReconciliationRepairResult.replayed.wireName] =
        repairReplayed;
    repairOutcomeCounts[ReconciliationRepairResult.failed.wireName] =
        repairFailed;
    repairOutcomeCounts[ReconciliationRepairResult.conflict.wireName] =
        repairConflicted;
    backlogCount = result.backlogCount;
    cursorLagSeconds = result.cursor.oldestUnresolvedAge.inSeconds;
    lastBoundedRunStartedAt = result.invocation.startedAt;
    lastBoundedRunCompletedAt = completedAt;
    lastBoundedRunMode = mode;
    lastFindingsSeen = result.findingsByCode.values.fold(
      0,
      (sum, count) => sum + count,
    );
    lastRepairsAttempted = result.repairsAttempted;
    lastRepairsApplied = result.repairsApplied;
    lastReplays = result.repairsReplayed;
    lastReportOnly = result.findingsByCode.entries
        .where(
          (entry) =>
              reconciliationMetadataFor(entry.key).repairability ==
              ReconciliationRepairability.reportOnlyImmutableDivergence,
        )
        .fold(0, (sum, entry) => sum + entry.value);
    lastFailures = result.repairsFailed;
  }

  void recordStoreError() => storeErrors++;

  void recordAuditInvalid() {
    auditInvalid++;
  }

  void recordSchemaIncompatible() {
    schemaIncompatible++;
  }

  void recordMalformedRecord() {
    malformedRecords++;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'backend': backend,
    'counters': <String, int>{
      'reconciliation_findings_total': findingsTotal,
      'reconciliation_findings_report_only_total': findingsReportOnly,
      'reconciliation_repair_attempts_total': repairAttemptsTotal,
      'reconciliation_repair_outcomes_total':
          repairApplied + repairReplayed + repairFailed,
      'reconciliation_store_errors_total': storeErrors,
      'reconciliation_audit_invalid_total': auditInvalid,
      'reconciliation_schema_incompatible': schemaIncompatible,
      'reconciliation_malformed_records_total': malformedRecords,
      'reconciliation_backlog_count': backlogCount,
      'reconciliation_cursor_lag': cursorLagSeconds,
    },
    'findingClasses': Map<String, int>.from(findingClassCounts),
    'findingStatuses': Map<String, int>.from(findingStatusCounts),
    'repairOutcomes': <String, int>{
      ...Map<String, int>.from(repairOutcomeCounts),
      'APPLIED': repairApplied,
      'REPLAYED': repairReplayed,
      'FAILED': repairFailed,
      'CONFLICT': repairConflicted,
    },
    'executionModes': Map<String, int>.from(executionModeCounts),
    'periodic': periodic.toJson(),
    'lastBoundedRun': <String, Object?>{
      'mode': lastBoundedRunMode?.name,
      'startedAt': lastBoundedRunStartedAt?.toIso8601String(),
      'completedAt': lastBoundedRunCompletedAt?.toIso8601String(),
      'findingsSeen': lastFindingsSeen,
      'repairsAttempted': lastRepairsAttempted,
      'repairsApplied': lastRepairsApplied,
      'replays': lastReplays,
      'reportOnly': lastReportOnly,
      'failures': lastFailures,
    },
  };

  static String _backend(String value) {
    if (value != 'file' && value != 'postgresql') {
      throw ArgumentError.value(value, 'backend');
    }
    return value;
  }
}

/// Non-authoritative reconciliation health and exact-scope diagnostics.
///
/// The authorizer is deliberately supplied by the host. This package does
/// not mint, widen, or infer a reconciliation principal from a bearer token.
final class ReconciliationObservability {
  ReconciliationObservability({
    required this.store,
    required this.authorizeDiagnostics,
    required String backend,
    this.auditStore,
    this.authoritativeReadiness,
    this.periodicRunner,
    ReconciliationObservabilityMetrics? metrics,
    this.maximumDiagnosticPageSize = 100,
    this.maximumDiagnosticScan = 256,
  }) : metrics =
           metrics ??
           ReconciliationObservabilityMetrics(
             backend: backend,
             periodicMetrics: periodicRunner?.metrics,
           ) {
    if (maximumDiagnosticPageSize <= 0 || maximumDiagnosticPageSize > 1000) {
      throw ArgumentError.value(
        maximumDiagnosticPageSize,
        'maximumDiagnosticPageSize',
      );
    }
    if (maximumDiagnosticScan < maximumDiagnosticPageSize ||
        maximumDiagnosticScan > 4096) {
      throw ArgumentError.value(maximumDiagnosticScan, 'maximumDiagnosticScan');
    }
  }

  final ReconciliationPersistenceStore store;
  final ReconciliationDiagnosticsAuthorizer authorizeDiagnostics;
  final ControlPlaneStore? auditStore;
  final Future<bool> Function()? authoritativeReadiness;
  final ReconciliationPeriodicRunner? periodicRunner;
  final ReconciliationObservabilityMetrics metrics;
  final int maximumDiagnosticPageSize;
  final int maximumDiagnosticScan;

  /// Adapter for `BoundedReconciliationService.runObserver`. The observer is
  /// intentionally side-effect-free with respect to reconciliation authority.
  void observeRun(
    ReconciliationRunResult result,
    ReconciliationExecutionMode mode,
  ) => metrics.recordRun(result, mode);

  Future<ReconciliationReadinessResult> checkReadiness() async {
    try {
      await store.checkReadiness();
    } on StorageConflict {
      metrics.recordSchemaIncompatible();
      return const ReconciliationReadinessResult(
        ready: false,
        code: ReconciliationReadinessCode.schemaIncompatible,
      );
    } on FormatException {
      metrics.recordSchemaIncompatible();
      return const ReconciliationReadinessResult(
        ready: false,
        code: ReconciliationReadinessCode.schemaIncompatible,
      );
    } on Object {
      metrics.recordStoreError();
      return const ReconciliationReadinessResult(
        ready: false,
        code: ReconciliationReadinessCode.reconciliationStoreUnavailable,
      );
    }
    if (auditStore != null) {
      try {
        final verification = verifyAuditChain(
          await auditStore!.readAuditChain(),
        );
        if (!verification.valid) {
          metrics.recordAuditInvalid();
          return const ReconciliationReadinessResult(
            ready: false,
            code: ReconciliationReadinessCode.auditInvalid,
          );
        }
      } on Object {
        metrics.recordStoreError();
        return const ReconciliationReadinessResult(
          ready: false,
          code: ReconciliationReadinessCode.auditStoreUnavailable,
        );
      }
    }
    if (authoritativeReadiness != null) {
      try {
        if (!await authoritativeReadiness!()) {
          return const ReconciliationReadinessResult(
            ready: false,
            code: ReconciliationReadinessCode.authoritativeStoreUnavailable,
          );
        }
      } on Object {
        metrics.recordStoreError();
        return const ReconciliationReadinessResult(
          ready: false,
          code: ReconciliationReadinessCode.authoritativeStoreUnavailable,
        );
      }
    }
    return const ReconciliationReadinessResult(
      ready: true,
      code: ReconciliationReadinessCode.ready,
    );
  }

  Future<Map<String, Object?>> diagnostics({
    required String token,
    required ReconciliationScope scope,
    int limit = 50,
    String? cursor,
    ReconciliationTaxonomyCode? code,
    ReconciliationFindingStatus? status,
    ReconciliationRepairResult? outcome,
    bool? reportOnly,
    DateTime? since,
    DateTime? until,
  }) async {
    await authorizeDiagnostics(token: token, scope: scope);
    _validatePage(limit, cursor: cursor);
    final normalizedSince = since?.toUtc();
    final normalizedUntil = until?.toUtc();
    if (normalizedSince != null &&
        normalizedUntil != null &&
        normalizedSince.isAfter(normalizedUntil)) {
      throw const ControlPlaneException(
        'INVALID_TIME_WINDOW',
        'Diagnostic time window is invalid',
      );
    }
    late final List<ReconciliationFinding> findings;
    late final List<ReconciliationRepairAttempt> attempts;
    try {
      findings = await store.listFindings(scope, limit: maximumDiagnosticScan);
      attempts = await store.listRepairAttempts(
        scope,
        limit: maximumDiagnosticScan,
      );
    } on FormatException {
      metrics.recordMalformedRecord();
      return _malformedDiagnostics(scope);
    }
    try {
      final attemptsByFinding = <String, List<ReconciliationRepairAttempt>>{};
      for (final attempt in attempts) {
        attemptsByFinding
            .putIfAbsent(
              attempt.findingId,
              () => <ReconciliationRepairAttempt>[],
            )
            .add(attempt);
      }
      final filtered = <ReconciliationFinding>[];
      for (final finding in findings) {
        if (cursor != null && finding.findingId.compareTo(cursor) <= 0) {
          continue;
        }
        if (code != null && finding.code != code) continue;
        final lifecycle = await store.readFindingLifecycle(
          scope,
          finding.findingId,
        );
        final effectiveStatus = lifecycle?.status ?? finding.status;
        if (status != null && effectiveStatus != status) continue;
        if (normalizedSince != null &&
            finding.lastObservedAt.isBefore(normalizedSince)) {
          continue;
        }
        if (normalizedUntil != null &&
            finding.firstObservedAt.isAfter(normalizedUntil)) {
          continue;
        }
        final disposition = _disposition(finding);
        final isReportOnly =
            finding.repairability ==
                ReconciliationRepairability.reportOnlyImmutableDivergence ||
            disposition == ReconciliationRepairBindingDisposition.reportOnly ||
            disposition == ReconciliationRepairBindingDisposition.notApplicable;
        if (reportOnly != null && isReportOnly != reportOnly) continue;
        final findingAttempts =
            attemptsByFinding[finding.findingId] ??
            const <ReconciliationRepairAttempt>[];
        if (outcome != null &&
            !findingAttempts.any((attempt) => attempt.result == outcome)) {
          continue;
        }
        filtered.add(finding);
      }
      final hasMore =
          filtered.length > limit || findings.length >= maximumDiagnosticScan;
      final visible = filtered.take(limit).toList(growable: false);
      final nextCursor = hasMore && visible.isNotEmpty
          ? visible.last.findingId
          : null;
      final summaries = <Map<String, Object?>>[];
      for (final finding in visible) {
        summaries.add(
          await _findingSummary(
            scope,
            finding,
            attemptsByFinding[finding.findingId] ??
                const <ReconciliationRepairAttempt>[],
          ),
        );
      }
      return <String, Object?>{
        'schemaVersion': 1,
        'scope': scope.toJson(),
        'findings': summaries,
        'nextCursor': nextCursor,
        'truncated': hasMore,
        'summary': await _scopeSummary(scope, findings, attempts),
        'cursor': await _cursorSummary(scope),
        'audit': await _auditSummary(),
        if (periodicRunner != null) 'periodic': periodicRunner!.statusJson(),
      };
    } on FormatException {
      metrics.recordMalformedRecord();
      return _malformedDiagnostics(scope);
    }
  }

  Future<Map<String, Object?>> finding({
    required String token,
    required ReconciliationScope scope,
    required String findingId,
  }) async {
    await authorizeDiagnostics(token: token, scope: scope);
    late final ReconciliationFinding? loadedFinding;
    try {
      loadedFinding = await store.readFinding(scope, findingId);
    } on FormatException {
      metrics.recordMalformedRecord();
      return _malformedDiagnostics(scope, findingId: findingId);
    }
    if (loadedFinding == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final finding = loadedFinding;
    try {
      final attempts = (await store.listRepairAttempts(
        scope,
        limit: maximumDiagnosticScan,
      )).where((attempt) => attempt.findingId == finding.findingId);
      return <String, Object?>{
        'schemaVersion': 1,
        'scope': scope.toJson(),
        'finding': await _findingSummary(scope, finding, attempts),
        'cursor': await _cursorSummary(scope),
        'audit': await _auditSummary(),
        if (periodicRunner != null) 'periodic': periodicRunner!.statusJson(),
      };
    } on FormatException {
      metrics.recordMalformedRecord();
      return _malformedDiagnostics(scope, findingId: findingId);
    }
  }

  ReconciliationRepairBindingDisposition _disposition(
    ReconciliationFinding finding,
  ) {
    final action = finding.metadata.automaticAction;
    if (action == null) {
      return ReconciliationRepairBindingDisposition.reportOnly;
    }
    return reconciliationRepairBindingFor(action);
  }

  Future<Map<String, Object?>> _findingSummary(
    ReconciliationScope scope,
    ReconciliationFinding finding,
    Iterable<ReconciliationRepairAttempt> attempts,
  ) async {
    final lifecycle = await store.readFindingLifecycle(
      scope,
      finding.findingId,
    );
    final orderedAttempts = attempts.toList()
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    final disposition = _disposition(finding);
    final isReportOnly =
        finding.repairability ==
            ReconciliationRepairability.reportOnlyImmutableDivergence ||
        disposition == ReconciliationRepairBindingDisposition.reportOnly ||
        disposition == ReconciliationRepairBindingDisposition.notApplicable;
    return <String, Object?>{
      'findingId': finding.findingId,
      'code': finding.code.wireName,
      'severity': finding.severity.wireName,
      'repairability': finding.repairability.wireName,
      'actionDisposition': disposition.wireName,
      'reportOnly': isReportOnly,
      'entityType': finding.entityType,
      'entityId': finding.entityId,
      'sourceDigests': finding.sourceDigests,
      'observedVersions': finding.observedVersions,
      'firstObservedAt': finding.firstObservedAt.toIso8601String(),
      'lastObservedAt': finding.lastObservedAt.toIso8601String(),
      'safeDetailCode': finding.safeDetailCode,
      'status': (lifecycle?.status ?? finding.status).wireName,
      'lifecycleVersion': lifecycle?.version ?? 0,
      'repairAttempts': <String, Object?>{
        'count': orderedAttempts.length,
        'lastOutcome': orderedAttempts.isEmpty
            ? null
            : orderedAttempts.last.result.wireName,
        'lastErrorCode': orderedAttempts.isEmpty
            ? null
            : orderedAttempts.last.safeErrorCode,
      },
    };
  }

  Future<Map<String, Object?>> _scopeSummary(
    ReconciliationScope scope,
    List<ReconciliationFinding> findings,
    List<ReconciliationRepairAttempt> attempts,
  ) async {
    final statuses = <String, int>{
      for (final status in ReconciliationFindingStatus.values)
        status.wireName: 0,
    };
    final classes = <String, int>{
      for (final code in ReconciliationTaxonomyCode.values) code.wireName: 0,
    };
    for (final finding in findings) {
      final lifecycle = await store.readFindingLifecycle(
        scope,
        finding.findingId,
      );
      final effective = lifecycle?.status ?? finding.status;
      statuses[effective.wireName] = (statuses[effective.wireName] ?? 0) + 1;
      classes[finding.code.wireName] =
          (classes[finding.code.wireName] ?? 0) + 1;
    }
    return <String, Object?>{
      'findings': findings.length,
      'statuses': statuses,
      'classes': classes,
      'repairAttempts': attempts.length,
    };
  }

  Future<Map<String, Object?>> _cursorSummary(ReconciliationScope scope) async {
    final cursor = await store.readCursor(scope);
    if (cursor == null) {
      return const <String, Object?>{'present': false};
    }
    return <String, Object?>{
      'present': true,
      'version': cursor.version,
      'oldestUnresolvedAgeSeconds': cursor.cursor.oldestUnresolvedAge.inSeconds,
      'perTenantCap': cursor.cursor.perTenantCap,
      'globalCap': cursor.cursor.globalCap,
      'updatedAt': cursor.updatedAt.toIso8601String(),
    };
  }

  Future<Map<String, Object?>> _auditSummary() async {
    final source = auditStore;
    if (source == null) {
      return const <String, Object?>{'status': 'NOT_CONFIGURED'};
    }
    try {
      final verification = verifyAuditChain(await source.readAuditChain());
      return <String, Object?>{
        'status': verification.valid ? 'VALID' : 'INVALID',
        'valid': verification.valid,
        'entries': verification.entries,
        if (!verification.valid) 'code': 'AUDIT_INVALID',
      };
    } on Object {
      metrics.recordStoreError();
      return const <String, Object?>{
        'status': 'UNAVAILABLE',
        'code': 'AUDIT_STORE_UNAVAILABLE',
      };
    }
  }

  Map<String, Object?> _malformedDiagnostics(
    ReconciliationScope scope, {
    String? findingId,
  }) => <String, Object?>{
    'schemaVersion': 1,
    'scope': scope.toJson(),
    if (findingId != null) 'findingId': findingId,
    'status': 'DEGRADED',
    'code': 'MALFORMED_RECORD',
    'findings': const <Object?>[],
  };

  void _validatePage(int limit, {required String? cursor}) {
    if (limit <= 0 || limit > maximumDiagnosticPageSize) {
      throw const ControlPlaneException(
        'INVALID_PAGE_SIZE',
        'Diagnostic page size is outside the supported bound',
      );
    }
    if (cursor != null &&
        (cursor.isEmpty || cursor.length > maximumReconciliationIdLength)) {
      throw const ControlPlaneException(
        'INVALID_CURSOR',
        'Diagnostic cursor is invalid',
      );
    }
  }
}
