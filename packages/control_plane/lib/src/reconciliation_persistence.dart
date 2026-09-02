import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

import 'audit.dart';
import 'encoding.dart';
import 'errors.dart';
import 'persistence.dart';
import 'postgres_faults.dart';
import 'postgres_store.dart';
import 'reconciliation_domain.dart';
import 'reconciliation_execution.dart';

/// Version of the P3E5-5B persistence envelope. This is deliberately
/// independent from the frozen 5A domain wire version.
const int reconciliationPersistenceSchemaVersion = 1;

const int reconciliationPostgresSchemaVersion = 8;

/// Session-scoped advisory lock key for the one global periodic pass. This is
/// intentionally distinct from migration locks and is coordination only.
const int reconciliationPeriodicAdvisoryLockKey = 7812451;

/// PostgreSQL objects introduced by P3E5-5B. The executable migration is
/// owned by the PostgreSQL store so fresh bootstrap and normal control-plane
/// startup use exactly the same SQL.
const List<String> reconciliationPostgresMigration008 = postgresMigration008;

enum ReconciliationRecordWriteResult { created, replayed }

final class ReconciliationFindingLifecycle {
  ReconciliationFindingLifecycle({
    this.schemaVersion = reconciliationPersistenceSchemaVersion,
    required this.scope,
    required String findingId,
    required this.status,
    required this.version,
    required String? latestRepairId,
    required DateTime updatedAt,
  }) : findingId = _reconciliationId(findingId, 'finding ID'),
       latestRepairId = latestRepairId == null
           ? null
           : _reconciliationId(latestRepairId, 'repair ID'),
       updatedAt = _reconciliationUtc(updatedAt, 'lifecycle update time') {
    if (schemaVersion != reconciliationPersistenceSchemaVersion) {
      throw const FormatException('Unsupported lifecycle schema version');
    }
    if (version < 0)
      throw const FormatException('Lifecycle version is invalid');
  }

  final int schemaVersion;
  final ReconciliationScope scope;
  final String findingId;
  final ReconciliationFindingStatus status;
  final int version;
  final String? latestRepairId;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'scope': scope.toJson(),
    'findingId': findingId,
    'status': status.wireName,
    'version': version,
    'latestRepairId': latestRepairId,
    'updatedAt': updatedAt.toIso8601String(),
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static ReconciliationFindingLifecycle fromJson(Object? value) {
    final map = _reconciliationObject(value, 'finding lifecycle');
    _reconciliationExactKeys(map, const <String>{
      'schemaVersion',
      'scope',
      'findingId',
      'status',
      'version',
      'latestRepairId',
      'updatedAt',
    }, 'finding lifecycle');
    return ReconciliationFindingLifecycle(
      schemaVersion: _reconciliationInt(map['schemaVersion'], 'schema version'),
      scope: ReconciliationScope.fromJson(map['scope']),
      findingId: _reconciliationString(map['findingId'], 'finding ID'),
      status: parseReconciliationFindingStatus(map['status']),
      version: _reconciliationInt(map['version'], 'lifecycle version'),
      latestRepairId: map['latestRepairId'] as String?,
      updatedAt: _reconciliationTimestamp(map['updatedAt'], 'updatedAt'),
    );
  }
}

final class ReconciliationCursorState {
  ReconciliationCursorState({
    this.schemaVersion = reconciliationPersistenceSchemaVersion,
    required this.scope,
    required this.cursor,
    required this.version,
    required DateTime updatedAt,
  }) : updatedAt = _reconciliationUtc(updatedAt, 'cursor update time') {
    if (schemaVersion != reconciliationPersistenceSchemaVersion) {
      throw const FormatException('Unsupported cursor state schema version');
    }
    if (cursor.scope.canonicalSerialization != scope.canonicalSerialization) {
      throw const FormatException('Cursor state scope does not match cursor');
    }
    if (version < 0)
      throw const FormatException('Cursor state version is invalid');
  }

  final int schemaVersion;
  final ReconciliationScope scope;
  final ReconciliationCursor cursor;
  final int version;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'scope': scope.toJson(),
    'cursor': cursor.toJson(),
    'version': version,
    'updatedAt': updatedAt.toIso8601String(),
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static ReconciliationCursorState fromJson(Object? value) {
    final map = _reconciliationObject(value, 'cursor state');
    _reconciliationExactKeys(map, const <String>{
      'schemaVersion',
      'scope',
      'cursor',
      'version',
      'updatedAt',
    }, 'cursor state');
    return ReconciliationCursorState(
      schemaVersion: _reconciliationInt(map['schemaVersion'], 'schema version'),
      scope: ReconciliationScope.fromJson(map['scope']),
      cursor: ReconciliationCursor.fromJson(map['cursor']),
      version: _reconciliationInt(map['version'], 'cursor state version'),
      updatedAt: _reconciliationTimestamp(map['updatedAt'], 'updatedAt'),
    );
  }
}

/// The persistence seam intentionally takes exact scope for every read. There
/// is no global list operation that could accidentally disclose another
/// tenant's findings.
abstract interface class ReconciliationPersistenceStore {
  Future<void> initialize();
  Future<void> close();

  /// Read-only dependency/schema probe. Implementations must not run a
  /// migration, reconcile, advance a cursor, or change a finding lifecycle.
  Future<void> checkReadiness();

  Future<ReconciliationRecordWriteResult> putFinding(
    ReconciliationFinding finding,
  );

  Future<ReconciliationFinding?> readFinding(
    ReconciliationScope scope,
    String findingId,
  );

  Future<List<ReconciliationFinding>> listFindings(
    ReconciliationScope scope, {
    int? limit,
  });

  Future<ReconciliationRecordWriteResult> putRepairAttempt(
    ReconciliationRepairAttempt attempt,
  );

  Future<ReconciliationRepairAttempt?> readRepairAttempt(
    ReconciliationScope scope,
    String repairId,
  );

  Future<List<ReconciliationRepairAttempt>> listRepairAttempts(
    ReconciliationScope scope, {
    int? limit,
  });

  Future<ReconciliationFindingLifecycle?> readFindingLifecycle(
    ReconciliationScope scope,
    String findingId,
  );

  Future<ReconciliationFindingLifecycle> updateFindingLifecycle({
    required ReconciliationFindingLifecycle lifecycle,
    required int expectedVersion,
  });

  Future<ReconciliationCursorState?> readCursor(ReconciliationScope scope);

  Future<ReconciliationCursorState> saveCursor({
    required ReconciliationCursorState cursor,
    required int expectedVersion,
  });
}

abstract interface class ReconciliationAuditSink {
  Future<void> append(ReconciliationAuditEvent event);
}

/// Adapter to the existing append-only audit chain. The event digest is the
/// durable idempotency key; no reconciliation code can rewrite the chain.
final class ControlPlaneReconciliationAuditSink
    implements ReconciliationAuditSink {
  ControlPlaneReconciliationAuditSink(this.store);

  final ControlPlaneStore store;

  @override
  Future<void> append(ReconciliationAuditEvent event) async {
    final chain = await store.readAuditChain();
    final verification = verifyAuditChain(chain);
    if (!verification.valid) {
      throw StorageConflict(
        'Audit chain is invalid: ${verification.failure ?? 'unknown'}',
      );
    }
    // The frozen reconciliation event keeps its exact scope under `scope`.
    // Existing audit stores index the tenant from the top-level record, so
    // add only that storage envelope without changing the 5A event wire body.
    final body = <String, Object?>{
      'organizationId': event.scope.organizationId,
      ...event.toJson(),
    };
    for (final entry in chain) {
      if (entry['auditId'] != event.digest) continue;
      final existingBody = entry['body'];
      if (existingBody is Map &&
          canonicalJson(existingBody) == canonicalJson(body)) {
        return;
      }
      throw const StorageConflict('Immutable audit event conflict');
    }
    await store.appendAudit(event.digest, body);
  }
}

final class ReconciliationCandidate {
  ReconciliationCandidate({
    required this.finding,
    this.precondition,
    this.reloadPrecondition,
  }) {
    if (precondition != null) precondition!.validateAgainst(finding);
  }

  final ReconciliationFinding finding;
  final ReconciliationPrecondition? precondition;
  final Future<ReconciliationPrecondition> Function()? reloadPrecondition;
}

final class ReconciliationRepairContext {
  const ReconciliationRepairContext({
    required this.invocation,
    required this.finding,
    required this.precondition,
  });

  final ReconciliationInvocation invocation;
  final ReconciliationFinding finding;
  final ReconciliationPrecondition precondition;
}

final class ReconciliationRepairExecution {
  const ReconciliationRepairExecution({
    required this.result,
    this.safeErrorCode,
    this.postconditionVerified = false,
  });

  final ReconciliationRepairResult result;
  final String? safeErrorCode;

  /// The injected existing CAS adapter must re-read its target and set this
  /// only after the expected projection state is observed. The reconciliation
  /// service will not treat an `APPLIED` response as successful otherwise.
  final bool postconditionVerified;
}

abstract interface class ReconciliationCandidateSource {
  Future<List<ReconciliationCandidate>> discover(
    ReconciliationInvocation invocation,
  );
}

typedef ReconciliationDetector = Future<List<ReconciliationCandidate>> Function(
  ReconciliationInvocation invocation,
);

/// Composes bounded detectors backed by authoritative stores. Detectors are
/// called in declaration order and must apply the invocation policy while
/// reading; the service applies a second global/per-tenant bound before any
/// repair. Duplicate identities are accepted only when their canonical
/// finding bodies agree.
final class CompositeReconciliationCandidateSource
    implements ReconciliationCandidateSource {
  CompositeReconciliationCandidateSource(
    Iterable<ReconciliationDetector> detectors,
  ) : detectors = List.unmodifiable(detectors);

  final List<ReconciliationDetector> detectors;

  @override
  Future<List<ReconciliationCandidate>> discover(
    ReconciliationInvocation invocation,
  ) async {
    final byId = <String, ReconciliationCandidate>{};
    for (final detector in detectors) {
      for (final candidate in await detector(invocation)) {
        final previous = byId[candidate.finding.findingId];
        if (previous == null) {
          byId[candidate.finding.findingId] = candidate;
          continue;
        }
        if (previous.finding.canonicalSerialization !=
            candidate.finding.canonicalSerialization) {
          throw const StorageConflict(
            'Reconciliation detectors disagree on finding identity',
          );
        }
      }
    }
    final result = byId.values.toList()
      ..sort(
        (left, right) =>
            left.finding.findingId.compareTo(right.finding.findingId),
      );
    return List.unmodifiable(result);
  }
}

abstract interface class ReconciliationRepairExecutor {
  Future<ReconciliationRepairExecution> execute(
    ReconciliationRepairContext context,
  );
}

enum ReconciliationExecutionMode { startup, administrator }

typedef ReconciliationRunObserver = void Function(
  ReconciliationRunResult result,
  ReconciliationExecutionMode mode,
);

final class ReconciliationRunResult {
  const ReconciliationRunResult({
    required this.invocation,
    required this.findingsRecorded,
    required this.repairsAttempted,
    required this.repairsApplied,
    required this.repairsReplayed,
    required this.repairsFailed,
    required this.repairsConflicted,
    required this.backlog,
    required this.backlogCount,
    required this.findingsByCode,
    required this.findingsByStatus,
    required this.cursor,
    required this.auditReferenceMissing,
  });

  final ReconciliationInvocation invocation;
  final int findingsRecorded;
  final int repairsAttempted;
  final int repairsApplied;
  final int repairsReplayed;
  final int repairsFailed;
  final int repairsConflicted;
  final bool backlog;
  final int backlogCount;
  final Map<ReconciliationTaxonomyCode, int> findingsByCode;
  final Map<ReconciliationFindingStatus, int> findingsByStatus;
  final ReconciliationCursor cursor;
  final bool auditReferenceMissing;
}

/// Executes only a single bounded invocation. The service has no timer,
/// queue, worker, rollout writer, or halt adapter. All authority to mutate a
/// projection is supplied by the injected executor and is expected to be an
/// existing typed CAS seam.
final class BoundedReconciliationService {
  BoundedReconciliationService({
    required this.store,
    required this.source,
    required this.executor,
    required this.audit,
    this.runObserver,
    ReconciliationExecutionGate? executionGate,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _executionGate = executionGate ?? ReconciliationExecutionGate();

  final ReconciliationPersistenceStore store;
  final ReconciliationCandidateSource source;
  final ReconciliationRepairExecutor executor;
  final ReconciliationAuditSink audit;
  final ReconciliationRunObserver? runObserver;
  final DateTime Function() _clock;
  final ReconciliationExecutionGate _executionGate;

  Future<ReconciliationRunResult> runStartup({
    required ReconciliationInvocation invocation,
    required int perTenantCap,
    required int globalCap,
  }) async {
    final result = await _executionGate.run(
      () => _run(
        invocation: invocation,
        perTenantCap: perTenantCap,
        globalCap: globalCap,
      ),
    );
    _observe(result, ReconciliationExecutionMode.startup);
    return result;
  }

  Future<ReconciliationRunResult> runAdministrator({
    required ReconciliationInvocation invocation,
    required ReconciliationPrincipal principal,
    required DateTime now,
    required int perTenantCap,
    required int globalCap,
  }) async {
    principal.authorizeInvocation(invocation, now: now);
    if (invocation.scope.applicationId == null ||
        invocation.scope.environmentId == null) {
      throw const FormatException(
        'Administrator reconciliation requires exact application/environment scope',
      );
    }
    final result = await _executionGate.run(
      () => _run(
        invocation: invocation,
        perTenantCap: perTenantCap,
        globalCap: globalCap,
      ),
    );
    _observe(result, ReconciliationExecutionMode.administrator);
    return result;
  }

  void _observe(
    ReconciliationRunResult result,
    ReconciliationExecutionMode mode,
  ) {
    // Observability is strictly non-authoritative. A broken process-local
    // observer must never turn a committed reconciliation result into a
    // failed mutation response.
    try {
      runObserver?.call(result, mode);
    } on Object {
      // Intentionally ignored; the durable reconciliation result is already
      // authoritative and remains available through persistence reads.
    }
  }

  Future<ReconciliationRunResult> _run({
    required ReconciliationInvocation invocation,
    required int perTenantCap,
    required int globalCap,
  }) async {
    _validateRunBounds(invocation.policy, perTenantCap, globalCap);
    final discovered = (await source.discover(invocation)).toList()
      ..sort(
        (left, right) =>
            left.finding.findingId.compareTo(right.finding.findingId),
      );
    final cursor = invocation.cursor;
    if (cursor != null) invocation.scope.requireContains(cursor.scope);
    final position = cursor?.position;
    final candidates = discovered.where((candidate) {
      if (position == null) return true;
      return candidate.finding.findingId.compareTo(position) > 0;
    }).toList();
    final selected = <ReconciliationCandidate>[];
    final tenantCounts = <String, int>{};
    var recordsScanned = 0;
    for (final candidate in candidates) {
      if (recordsScanned >= invocation.maximumRecords) break;
      recordsScanned++;
      candidate.finding.requireWithin(invocation.scope);
      final tenant = candidate.finding.scope.canonicalSerialization;
      final count = tenantCounts[tenant] ?? 0;
      if (count >= perTenantCap) continue;
      if (count == 0 && tenantCounts.length >= invocation.maximumTenants) {
        break;
      }
      if (selected.length >= globalCap ||
          selected.length >= invocation.maximumFindings) {
        break;
      }
      tenantCounts[tenant] = count + 1;
      selected.add(candidate);
    }
    final backlog =
        candidates.length > selected.length ||
        recordsScanned < candidates.length;
    var findingsRecorded = 0;
    var repairsAttempted = 0;
    var repairsApplied = 0;
    var repairsReplayed = 0;
    var repairsFailed = 0;
    var repairsConflicted = 0;
    var auditReferenceMissing = false;
    final findingsByCode = <ReconciliationTaxonomyCode, int>{};
    final findingsByStatus = <ReconciliationFindingStatus, int>{};
    var lastPosition = position;
    for (final candidate in selected) {
      final finding = candidate.finding;
      findingsByCode[finding.code] = (findingsByCode[finding.code] ?? 0) + 1;
      findingsByStatus[finding.status] =
          (findingsByStatus[finding.status] ?? 0) + 1;
      final findingResult = await store.putFinding(finding);
      if (findingResult == ReconciliationRecordWriteResult.created) {
        findingsRecorded++;
      }
      lastPosition = finding.findingId;
      await _appendFindingAudit(finding);
      final action = finding.metadata.automaticAction;
      if (action == null ||
          finding.repairability ==
              ReconciliationRepairability.reportOnlyImmutableDivergence) {
        continue;
      }
      if (repairsAttempted >= invocation.maximumRepairs) break;
      var precondition = candidate.precondition;
      if (candidate.reloadPrecondition != null) {
        precondition = await candidate.reloadPrecondition!();
      }
      if (precondition == null) {
        repairsFailed++;
        continue;
      }
      precondition.validateAgainst(finding);
      final existingAttempt = await store.readRepairAttempt(
        finding.scope,
        ReconciliationRepairAttempt.deriveRepairId(
          finding.findingId,
          precondition.action,
        ),
      );
      if (existingAttempt != null) {
        repairsReplayed++;
        await _ensureLifecycleForAttempt(finding, existingAttempt);
        continue;
      }
      final requestedAudit = ReconciliationAuditEvent(
        eventType: ReconciliationAuditEventType.repairRequested,
        scope: finding.scope,
        actorId: invocation.actorId,
        resourceId: ReconciliationRepairAttempt.deriveRepairId(
          finding.findingId,
          precondition.action,
        ),
        taxonomyCode: finding.code,
        action: precondition.action,
        result: ReconciliationRepairResult.requested,
        createdAt: _clock().toUtc(),
      );
      try {
        await audit.append(requestedAudit);
      } on Object {
        repairsFailed++;
        await _putFailedAttempt(
          invocation,
          finding,
          precondition,
          safeErrorCode: 'AUDIT_UNAVAILABLE',
        );
        continue;
      }
      repairsAttempted++;
      late final ReconciliationRepairExecution execution;
      try {
        execution = await executor.execute(
          ReconciliationRepairContext(
            invocation: invocation,
            finding: finding,
            precondition: precondition,
          ),
        );
      } on StorageConflict {
        execution = const ReconciliationRepairExecution(
          result: ReconciliationRepairResult.conflict,
          safeErrorCode: 'PROJECTION_CAS_CONFLICT',
        );
      } on FormatException {
        execution = const ReconciliationRepairExecution(
          result: ReconciliationRepairResult.failed,
          safeErrorCode: 'REPAIR_INPUT_INVALID',
        );
      } on Object {
        execution = const ReconciliationRepairExecution(
          result: ReconciliationRepairResult.failed,
          safeErrorCode: 'REPAIR_EXECUTOR_FAILURE',
        );
      }
      final safeExecution =
          execution.result == ReconciliationRepairResult.applied &&
              !execution.postconditionVerified
          ? const ReconciliationRepairExecution(
              result: ReconciliationRepairResult.failed,
              safeErrorCode: 'POSTCONDITION_UNVERIFIED',
            )
          : execution;
      final attempt = ReconciliationRepairAttempt.create(
        finding: finding,
        precondition: precondition,
        actorId: invocation.actorId,
        result: safeExecution.result,
        safeErrorCode: safeExecution.safeErrorCode,
        createdAt: _clock().toUtc(),
      );
      ReconciliationRecordWriteResult? attemptResult;
      try {
        attemptResult = await store.putRepairAttempt(attempt);
      } on StorageConflict {
        // Two reconcilers can pass the pre-repair audit before either writes
        // its immutable attempt. Re-read the canonical row and treat an
        // equal body as replay; a different body is a deterministic conflict
        // and must not trigger another projection mutation.
        final existing = await store.readRepairAttempt(
          finding.scope,
          attempt.repairId,
        );
        if (existing == null) rethrow;
        if (existing.canonicalSerialization == attempt.canonicalSerialization) {
          repairsReplayed++;
        } else {
          repairsFailed++;
          repairsConflicted++;
        }
        continue;
      }
      if (attemptResult == ReconciliationRecordWriteResult.replayed) {
        repairsReplayed++;
      }
      switch (safeExecution.result) {
        case ReconciliationRepairResult.applied:
          repairsApplied++;
        case ReconciliationRepairResult.replayed:
          repairsReplayed++;
        case ReconciliationRepairResult.failed ||
            ReconciliationRepairResult.conflict:
          repairsFailed++;
          if (safeExecution.result == ReconciliationRepairResult.conflict) {
            repairsConflicted++;
          }
        case ReconciliationRepairResult.requested ||
            ReconciliationRepairResult.reportOnly:
          throw const FormatException(
            'Repair executor returned a non-terminal result',
          );
      }
      final lifecycle = ReconciliationFindingLifecycle(
        scope: finding.scope,
        findingId: finding.findingId,
        status: safeExecution.result == ReconciliationRepairResult.applied
            ? ReconciliationFindingStatus.repaired
            : ReconciliationFindingStatus.failed,
        version:
            (await store.readFindingLifecycle(
              finding.scope,
              finding.findingId,
            ))?.version ??
            0,
        latestRepairId: attempt.repairId,
        updatedAt: _clock().toUtc(),
      );
      final existingLifecycle = await store.readFindingLifecycle(
        finding.scope,
        finding.findingId,
      );
      try {
        await store.updateFindingLifecycle(
          lifecycle: ReconciliationFindingLifecycle(
            scope: lifecycle.scope,
            findingId: lifecycle.findingId,
            status: lifecycle.status,
            version: existingLifecycle?.version == null
                ? 1
                : existingLifecycle!.version + 1,
            latestRepairId: lifecycle.latestRepairId,
            updatedAt: lifecycle.updatedAt,
          ),
          expectedVersion: existingLifecycle?.version ?? 0,
        );
      } on StoragePreconditionFailed {
        // A concurrent repair owns the lifecycle projection; the immutable
        // attempt remains the source of truth and can be replayed safely.
        repairsReplayed++;
      }
      try {
        await audit.append(
          ReconciliationAuditEvent(
            eventType:
                safeExecution.result == ReconciliationRepairResult.applied
                ? ReconciliationAuditEventType.findingRecorded
                : ReconciliationAuditEventType.repairRejected,
            scope: finding.scope,
            actorId: invocation.actorId,
            resourceId: attempt.repairId,
            taxonomyCode: finding.code,
            action: attempt.action,
            result: safeExecution.result == ReconciliationRepairResult.applied
                ? null
                : safeExecution.result,
            safeErrorCode: safeExecution.safeErrorCode,
            createdAt: _clock().toUtc(),
          ),
        );
      } on Object {
        auditReferenceMissing = true;
      }
    }
    final nextCursor = ReconciliationCursor(
      scope: invocation.scope,
      position: lastPosition,
      oldestUnresolvedAge: _oldestUnresolvedAge(selected),
      perTenantCap: perTenantCap,
      globalCap: globalCap,
    );
    final existingCursor = await store.readCursor(invocation.scope);
    final nextCursorState = ReconciliationCursorState(
      scope: invocation.scope,
      cursor: nextCursor,
      version: (existingCursor?.version ?? 0) + 1,
      updatedAt: _clock().toUtc(),
    );
    try {
      await store.saveCursor(
        cursor: nextCursorState,
        expectedVersion: existingCursor?.version ?? 0,
      );
    } on StoragePreconditionFailed {
      // Cursor advancement is a progress projection. A concurrent bounded
      // invocation may win the CAS after this run has already recorded its
      // immutable finding/attempt; the winner remains authoritative.
    } on Object {
      // PostgreSQL can discover a concurrent insert as a unique-key error
      // before the loser observes the row under SELECT ... FOR UPDATE. Only
      // suppress that race when the persisted winner has the same cursor
      // position; unrelated storage failures remain visible.
      final winner = await store.readCursor(invocation.scope);
      if (winner == null ||
          winner.cursor.position != nextCursor.position ||
          winner.version < nextCursorState.version) {
        rethrow;
      }
    }
    return ReconciliationRunResult(
      invocation: invocation,
      findingsRecorded: findingsRecorded,
      repairsAttempted: repairsAttempted,
      repairsApplied: repairsApplied,
      repairsReplayed: repairsReplayed,
      repairsFailed: repairsFailed,
      repairsConflicted: repairsConflicted,
      backlog: backlog,
      backlogCount: candidates.length - selected.length,
      findingsByCode: Map.unmodifiable(findingsByCode),
      findingsByStatus: Map.unmodifiable(findingsByStatus),
      cursor: nextCursor,
      auditReferenceMissing: auditReferenceMissing,
    );
  }

  Future<void> _appendFindingAudit(ReconciliationFinding finding) =>
      audit.append(
        ReconciliationAuditEvent(
          eventType: ReconciliationAuditEventType.findingRecorded,
          scope: finding.scope,
          actorId: 'reconciliation',
          resourceId: finding.findingId,
          taxonomyCode: finding.code,
          createdAt: _clock().toUtc(),
        ),
      );

  /// Rebuilds the lifecycle projection when a process dies after the
  /// immutable repair attempt commits but before lifecycle bookkeeping. The
  /// attempt is the source of truth; this path never executes the repair
  /// executor again and advances the lifecycle with its existing CAS.
  Future<void> _ensureLifecycleForAttempt(
    ReconciliationFinding finding,
    ReconciliationRepairAttempt attempt,
  ) async {
    final status = switch (attempt.result) {
      ReconciliationRepairResult.applied ||
      ReconciliationRepairResult.replayed =>
        ReconciliationFindingStatus.repaired,
      ReconciliationRepairResult.failed ||
      ReconciliationRepairResult.conflict => ReconciliationFindingStatus.failed,
      ReconciliationRepairResult.requested ||
      ReconciliationRepairResult.reportOnly => throw const FormatException(
        'Persisted repair attempt is non-terminal',
      ),
    };
    final existing = await store.readFindingLifecycle(
      finding.scope,
      finding.findingId,
    );
    if (existing != null &&
        existing.latestRepairId == attempt.repairId &&
        existing.status == status) {
      return;
    }
    if (existing?.status == ReconciliationFindingStatus.repaired &&
        status == ReconciliationFindingStatus.failed) {
      return;
    }
    final lifecycle = ReconciliationFindingLifecycle(
      scope: finding.scope,
      findingId: finding.findingId,
      status: status,
      version: (existing?.version ?? 0) + 1,
      latestRepairId: attempt.repairId,
      updatedAt: _clock().toUtc(),
    );
    try {
      await store.updateFindingLifecycle(
        lifecycle: lifecycle,
        expectedVersion: existing?.version ?? 0,
      );
    } on StoragePreconditionFailed {
      final winner = await store.readFindingLifecycle(
        finding.scope,
        finding.findingId,
      );
      if (winner == null ||
          winner.latestRepairId != attempt.repairId ||
          winner.status != status) {
        rethrow;
      }
    }
  }

  Future<void> _putFailedAttempt(
    ReconciliationInvocation invocation,
    ReconciliationFinding finding,
    ReconciliationPrecondition precondition, {
    required String safeErrorCode,
  }) async {
    final attempt = ReconciliationRepairAttempt.create(
      finding: finding,
      precondition: precondition,
      actorId: invocation.actorId,
      result: ReconciliationRepairResult.failed,
      safeErrorCode: safeErrorCode,
      createdAt: _clock().toUtc(),
    );
    await store.putRepairAttempt(attempt);
  }

  Duration _oldestUnresolvedAge(List<ReconciliationCandidate> selected) {
    if (selected.isEmpty) return Duration.zero;
    final now = _clock().toUtc();
    final oldest = selected
        .map((candidate) => candidate.finding.firstObservedAt)
        .reduce((left, right) => left.isBefore(right) ? left : right);
    final age = now.difference(oldest);
    return age.isNegative ? Duration.zero : age;
  }
}

void _validateRunBounds(
  ReconciliationPolicy policy,
  int perTenantCap,
  int globalCap,
) {
  if (perTenantCap <= 0 || globalCap <= 0 || perTenantCap > globalCap) {
    throw const FormatException('Reconciliation fairness bounds are invalid');
  }
  if (globalCap > policy.maximumFindings) {
    throw const FormatException(
      'Reconciliation fairness cap exceeds policy maximum findings',
    );
  }
}

String _reconciliationString(Object? value, String label, {int max = 512}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > max ||
      value.contains(RegExp(r'[\u0000\r\n]'))) {
    throw FormatException('Invalid $label');
  }
  return value;
}

String _reconciliationId(Object? value, String label) =>
    _reconciliationString(value, label, max: maximumReconciliationIdLength);

int _reconciliationInt(Object? value, String label) {
  if (value is! int || value < 0 || value > 0x7fffffff) {
    throw FormatException('Invalid $label');
  }
  return value;
}

DateTime _reconciliationUtc(DateTime value, String label) {
  if (!value.isUtc) throw FormatException('$label must be UTC');
  return value;
}

DateTime _reconciliationTimestamp(Object? value, String label) {
  if (value is! String) throw FormatException('Invalid $label');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) throw FormatException('Invalid $label');
  return parsed;
}

Map<String, Object?> _reconciliationObject(Object? value, String label) {
  if (value is! Map) throw FormatException('Invalid $label');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('Invalid $label key');
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _reconciliationExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String label,
) {
  if (value.length != expected.length ||
      value.keys.any((key) => !expected.contains(key))) {
    throw FormatException('Invalid $label fields');
  }
}

String _reconciliationScopeDigest(ReconciliationScope scope) =>
    sha256Digest(utf8.encode(scope.canonicalSerialization));

String _reconciliationScopeSegment(String? value) =>
    sha256Hex(utf8.encode(value ?? '_'));

String _reconciliationFileCanonical(Map<String, Object?> value, String label) {
  final encoded = canonicalJson(value);
  final bytes = utf8.encode(encoded);
  final limit = switch (label) {
    'finding' => maximumReconciliationFindingBytes,
    'repair attempt' => maximumReconciliationRepairAttemptBytes,
    'lifecycle' => maximumReconciliationFindingBytes,
    'cursor state' => maximumReconciliationCursorBytes,
    _ => maximumReconciliationFindingBytes,
  };
  if (bytes.length > limit)
    throw FormatException('$label exceeds resource limit');
  return encoded;
}

Map<String, Object?> _decodeReconciliationFile(String source, String label) {
  final withoutNewline = source.endsWith('\n')
      ? source.substring(0, source.length - 1)
      : source;
  final value = _reconciliationObject(jsonDecode(withoutNewline), label);
  if (canonicalJson(value) != withoutNewline) {
    throw FormatException('$label is not canonical JSON');
  }
  return value;
}

final class FileReconciliationStore implements ReconciliationPersistenceStore {
  FileReconciliationStore(this.root);

  final Directory root;
  RandomAccessFile? _guard;
  Future<void> _tail = Future<void>.value();
  static final Set<String> _activeRoots = <String>{};

  String get _rootKey => p.normalize(p.absolute(root.path));
  Directory get _base => Directory(p.join(root.path, 'reconciliation'));

  @override
  Future<void> initialize() async {
    if (_guard != null) return;
    await _base.create(recursive: true);
    if (!_activeRoots.add(_rootKey)) {
      throw const StorageConflict(
        'File reconciliation persistence allows one process/writer only',
      );
    }
    try {
      final lock = File(p.join(_base.path, '.writer.lock'));
      final guard = await lock.open(mode: FileMode.append);
      await guard.lock(FileLock.exclusive);
      _guard = guard;
      for (final name in const <String>[
        'findings',
        'repairs',
        'lifecycle',
        'cursors',
      ]) {
        await Directory(p.join(_base.path, name)).create(recursive: true);
      }
    } on Object {
      _activeRoots.remove(_rootKey);
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    final guard = _guard;
    _guard = null;
    _activeRoots.remove(_rootKey);
    if (guard != null) {
      await guard.unlock();
      await guard.close();
    }
  }

  @override
  Future<void> checkReadiness() async {
    if (_guard == null || !await _base.exists()) {
      throw const StorageUnavailable(
        'File reconciliation persistence is not initialized',
      );
    }
    for (final name in const <String>[
      'findings',
      'repairs',
      'lifecycle',
      'cursors',
    ]) {
      if (!await Directory(p.join(_base.path, name)).exists()) {
        throw const StorageUnavailable(
          'File reconciliation persistence is incomplete',
        );
      }
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}).catchError((_) {});
    return next;
  }

  Directory _scopeDirectory(String collection, ReconciliationScope scope) =>
      Directory(
        p.join(
          _base.path,
          collection,
          _reconciliationScopeSegment(scope.organizationId),
          _reconciliationScopeSegment(scope.applicationId),
          _reconciliationScopeSegment(scope.environmentId),
        ),
      );

  File _recordFile(String collection, ReconciliationScope scope, String id) =>
      File(
        p.join(
          _scopeDirectory(collection, scope).path,
          sha256Hex(utf8.encode(id)),
          'record.json',
        ),
      );

  File _cursorFile(ReconciliationScope scope) => File(
    p.join(
      _base.path,
      'cursors',
      _reconciliationScopeSegment(scope.organizationId),
      '${sha256Hex(utf8.encode(scope.canonicalSerialization))}.json',
    ),
  );

  Future<Map<String, Object?>?> _readFile(File file, String label) async {
    if (!await file.exists()) return null;
    return _decodeReconciliationFile(await file.readAsString(), label);
  }

  Future<void> _writeAtomic(
    File file,
    Map<String, Object?> value,
    String label,
  ) async {
    final canonical = _reconciliationFileCanonical(value, label);
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString('$canonical\n', flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<ReconciliationRecordWriteResult> putFinding(
    ReconciliationFinding finding,
  ) => _serialized(() async {
    final file = _recordFile('findings', finding.scope, finding.findingId);
    final existing = await _readFile(file, 'finding');
    final incoming = finding.toJson();
    if (existing != null) {
      if (canonicalJson(existing) == canonicalJson(incoming)) {
        return ReconciliationRecordWriteResult.replayed;
      }
      throw const StorageConflict('Immutable reconciliation finding conflict');
    }
    await _writeAtomic(file, incoming, 'finding');
    return ReconciliationRecordWriteResult.created;
  });

  @override
  Future<ReconciliationFinding?> readFinding(
    ReconciliationScope scope,
    String findingId,
  ) async {
    final value = await _readFile(
      _recordFile(
        'findings',
        scope,
        _reconciliationId(findingId, 'finding ID'),
      ),
      'finding',
    );
    if (value == null) return null;
    final finding = ReconciliationFinding.fromJson(value);
    scope.requireContains(finding.scope);
    if (finding.scope.canonicalSerialization != scope.canonicalSerialization) {
      throw const FormatException(
        'Finding scope does not match requested scope',
      );
    }
    return finding;
  }

  @override
  Future<List<ReconciliationFinding>> listFindings(
    ReconciliationScope scope, {
    int? limit,
  }) async {
    final directory = _scopeDirectory('findings', scope);
    if (!await directory.exists()) return const <ReconciliationFinding>[];
    final records =
        (await directory.list(followLinks: false).toList())
            .whereType<Directory>()
            .map((directory) => File(p.join(directory.path, 'record.json')))
            .where((file) => file.path.endsWith('record.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final result = <ReconciliationFinding>[];
    for (final file in records) {
      if (limit != null && result.length >= limit) break;
      final value = await _readFile(file, 'finding');
      if (value == null) continue;
      final finding = ReconciliationFinding.fromJson(value);
      if (finding.scope.canonicalSerialization !=
          scope.canonicalSerialization) {
        throw const FormatException('Finding scope mismatch in storage');
      }
      result.add(finding);
    }
    result.sort((left, right) => left.findingId.compareTo(right.findingId));
    return List.unmodifiable(result);
  }

  @override
  Future<ReconciliationRecordWriteResult> putRepairAttempt(
    ReconciliationRepairAttempt attempt,
  ) => _serialized(() async {
    final finding = await _readFile(
      _recordFile('findings', attempt.scope, attempt.findingId),
      'finding',
    );
    if (finding == null) {
      throw const StorageConflict('Repair attempt references missing finding');
    }
    final file = _recordFile('repairs', attempt.scope, attempt.repairId);
    final existing = await _readFile(file, 'repair attempt');
    final incoming = attempt.toJson();
    if (existing != null) {
      if (canonicalJson(existing) == canonicalJson(incoming)) {
        return ReconciliationRecordWriteResult.replayed;
      }
      throw const StorageConflict(
        'Immutable reconciliation repair-attempt conflict',
      );
    }
    await _writeAtomic(file, incoming, 'repair attempt');
    return ReconciliationRecordWriteResult.created;
  });

  @override
  Future<ReconciliationRepairAttempt?> readRepairAttempt(
    ReconciliationScope scope,
    String repairId,
  ) async {
    final value = await _readFile(
      _recordFile('repairs', scope, _reconciliationId(repairId, 'repair ID')),
      'repair attempt',
    );
    if (value == null) return null;
    final attempt = ReconciliationRepairAttempt.fromJson(value);
    if (attempt.scope.canonicalSerialization != scope.canonicalSerialization) {
      throw const FormatException(
        'Repair scope does not match requested scope',
      );
    }
    return attempt;
  }

  @override
  Future<List<ReconciliationRepairAttempt>> listRepairAttempts(
    ReconciliationScope scope, {
    int? limit,
  }) async {
    final directory = _scopeDirectory('repairs', scope);
    if (!await directory.exists()) return const <ReconciliationRepairAttempt>[];
    final records =
        (await directory.list(followLinks: false).toList())
            .whereType<Directory>()
            .map((directory) => File(p.join(directory.path, 'record.json')))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final result = <ReconciliationRepairAttempt>[];
    for (final file in records) {
      if (limit != null && result.length >= limit) break;
      final value = await _readFile(file, 'repair attempt');
      if (value == null) continue;
      final attempt = ReconciliationRepairAttempt.fromJson(value);
      if (attempt.scope.canonicalSerialization !=
          scope.canonicalSerialization) {
        throw const FormatException('Repair scope mismatch in storage');
      }
      result.add(attempt);
    }
    result.sort((left, right) => left.repairId.compareTo(right.repairId));
    return List.unmodifiable(result);
  }

  @override
  Future<ReconciliationFindingLifecycle?> readFindingLifecycle(
    ReconciliationScope scope,
    String findingId,
  ) async {
    final value = await _readFile(
      _recordFile(
        'lifecycle',
        scope,
        _reconciliationId(findingId, 'finding ID'),
      ),
      'lifecycle',
    );
    if (value == null) return null;
    final lifecycle = ReconciliationFindingLifecycle.fromJson(value);
    if (lifecycle.scope.canonicalSerialization !=
        scope.canonicalSerialization) {
      throw const FormatException(
        'Lifecycle scope does not match requested scope',
      );
    }
    return lifecycle;
  }

  @override
  Future<ReconciliationFindingLifecycle> updateFindingLifecycle({
    required ReconciliationFindingLifecycle lifecycle,
    required int expectedVersion,
  }) => _serialized(() async {
    final finding = await _readFile(
      _recordFile('findings', lifecycle.scope, lifecycle.findingId),
      'finding',
    );
    if (finding == null) {
      throw const StorageConflict('Lifecycle references missing finding');
    }
    final file = _recordFile('lifecycle', lifecycle.scope, lifecycle.findingId);
    final existing = await _readFile(file, 'lifecycle');
    final current = existing == null
        ? null
        : ReconciliationFindingLifecycle.fromJson(existing);
    final currentVersion = current?.version ?? 0;
    if (currentVersion != expectedVersion ||
        lifecycle.version != expectedVersion + 1) {
      throw StoragePreconditionFailed(
        'Reconciliation lifecycle version is stale',
        currentRevision: currentVersion,
      );
    }
    await _writeAtomic(file, lifecycle.toJson(), 'lifecycle');
    return lifecycle;
  });

  @override
  Future<ReconciliationCursorState?> readCursor(
    ReconciliationScope scope,
  ) async {
    final value = await _readFile(_cursorFile(scope), 'cursor state');
    if (value == null) return null;
    final cursor = ReconciliationCursorState.fromJson(value);
    if (cursor.scope.canonicalSerialization != scope.canonicalSerialization) {
      throw const FormatException(
        'Cursor scope does not match requested scope',
      );
    }
    return cursor;
  }

  @override
  Future<ReconciliationCursorState> saveCursor({
    required ReconciliationCursorState cursor,
    required int expectedVersion,
  }) => _serialized(() async {
    final file = _cursorFile(cursor.scope);
    final existing = await _readFile(file, 'cursor state');
    final current = existing == null
        ? null
        : ReconciliationCursorState.fromJson(existing);
    final currentVersion = current?.version ?? 0;
    if (currentVersion != expectedVersion ||
        cursor.version != expectedVersion + 1) {
      throw StoragePreconditionFailed(
        'Reconciliation cursor version is stale',
        currentRevision: currentVersion,
      );
    }
    await _writeAtomic(file, cursor.toJson(), 'cursor state');
    return cursor;
  });
}

/// PostgreSQL-backed append-only reconciliation persistence. Every read is
/// tenant-scoped; immutable writes compare canonical bodies inside a row-lock
/// transaction so two instances converge on one semantic record.
final class PostgresReconciliationStore
    implements ReconciliationPersistenceStore {
  /// Creates a store with an isolated pool for the session-scoped periodic
  /// advisory lock. The isolated pool prevents a one-connection persistence
  /// pool from deadlocking while the bounded pass performs its own reads and
  /// writes under that lock.
  PostgresReconciliationStore(
    String connectionString, {
    this.disconnectInjector,
    Pool? periodicOwnershipPool,
  }) : _pool = Pool.withUrl(connectionString),
       _periodicOwnershipPool =
           periodicOwnershipPool ?? Pool.withUrl(connectionString);

  PostgresReconciliationStore.withPool(
    Pool pool, {
    this.disconnectInjector,
    Pool? periodicOwnershipPool,
  }) : _pool = pool,
       _periodicOwnershipPool = periodicOwnershipPool ?? pool;

  final Pool _pool;
  // Advisory-lock ownership must use a separate pool from the persistence
  // action. The lock is held for the complete bounded pass, while the pass
  // legitimately acquires its own persistence sessions. Reusing a pool with
  // one connection would deadlock the service under its own ownership lock.
  final Pool _periodicOwnershipPool;

  /// Test-only fault injection. Production callers leave this null.
  final PostgresDisconnectInjector? disconnectInjector;
  bool _initialized = false;

  Future<void> _disconnectIfRequested(PostgresDisconnectPoint point) async {
    if (disconnectInjector?.call(point) != true) return;
    await _pool.close(force: true);
    throw StorageUnavailable(
      'Injected PostgreSQL connection loss at ${point.name}',
    );
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _pool.runTx((session) async {
      await session.execute('SELECT pg_advisory_xact_lock(7812450)');
      await _applyMigrations(session);
    });
    _initialized = true;
  }

  @override
  Future<void> checkReadiness() async {
    if (!_initialized) {
      throw const StorageUnavailable(
        'PostgreSQL reconciliation persistence is not initialized',
      );
    }
    final rows = await _pool.execute(
      'SELECT COALESCE(MAX(version), 0) AS version '
      'FROM control_plane_schema_migrations',
    );
    final version = int.parse('${rows.first.toColumnMap()['version']}');
    if (version != reconciliationPostgresSchemaVersion) {
      throw StorageConflict(
        'Unsupported control-plane schema version: $version',
      );
    }
  }

  Future<void> _applyMigrations(Session session) async {
    await session.execute(postgresMigration001[0]);
    final rows = await session.execute(
      'SELECT COALESCE(MAX(version), 0) AS version '
      'FROM control_plane_schema_migrations',
    );
    var version = int.parse('${rows.first.toColumnMap()['version']}');
    if (version > reconciliationPostgresSchemaVersion) {
      throw StorageConflict(
        'Unsupported control-plane schema version: $version',
      );
    }
    final migrations = <int, List<String>>{
      1: postgresMigration001.skip(1).toList(growable: false),
      2: postgresMigration002,
      3: postgresMigration003,
      4: postgresMigration004,
      5: postgresMigration005,
      6: postgresMigration006,
      7: postgresMigration007,
      8: reconciliationPostgresMigration008,
    };
    for (
      var next = version + 1;
      next <= reconciliationPostgresSchemaVersion;
      next++
    ) {
      for (final statement in migrations[next]!) {
        await session.execute(statement);
      }
      await session.execute(
        Sql.named(
          'INSERT INTO control_plane_schema_migrations(version) '
          'VALUES (@version:int4) ON CONFLICT (version) DO NOTHING',
        ),
        parameters: <String, Object?>{'version': next},
      );
      version = next;
    }
  }

  @override
  Future<void> close() async {
    await _pool.close();
    if (!identical(_periodicOwnershipPool, _pool)) {
      await _periodicOwnershipPool.close();
    }
  }

  /// Runs [action] while holding the one global periodic-runner advisory lock.
  /// The lock is session-scoped and therefore releases automatically on
  /// connection loss. A failed acquisition returns `false` immediately.
  Future<bool> runIfPeriodicOwner(Future<void> Function() action) async {
    if (!_initialized) {
      throw const StorageUnavailable(
        'PostgreSQL reconciliation persistence is not initialized',
      );
    }
    var callbackFailed = false;
    try {
      return await _periodicOwnershipPool.withConnection((session) async {
        final rows = await session.execute(
          Sql.named('SELECT pg_try_advisory_lock(@key:bigint) AS acquired'),
          parameters: <String, Object?>{
            'key': reconciliationPeriodicAdvisoryLockKey,
          },
        );
        final acquired =
            rows.isNotEmpty && rows.first.toColumnMap()['acquired'] == true;
        if (!acquired) return false;
        try {
          try {
            await action();
          } catch (_) {
            callbackFailed = true;
            rethrow;
          }
          await session.execute('SELECT 1');
          return true;
        } finally {
          try {
            await session.execute(
              Sql.named('SELECT pg_advisory_unlock(@key:bigint)'),
              parameters: <String, Object?>{
                'key': reconciliationPeriodicAdvisoryLockKey,
              },
            );
          } on Object {
            // A lost session already releases the session-scoped lock.
          }
        }
      });
    } on StorageUnavailable {
      rethrow;
    } on Object {
      if (callbackFailed) rethrow;
      throw const StorageUnavailable(
        'Periodic reconciliation ownership store is unavailable',
      );
    }
  }

  Map<String, Object?> _scopeParameters(ReconciliationScope scope) =>
      <String, Object?>{
        'organization': scope.organizationId,
        'application': scope.applicationId,
        'environment': scope.environmentId,
      };

  String _scopeWhere({String prefix = ''}) =>
      '${prefix}organization_id = @organization:text AND '
      '${prefix}application_id IS NOT DISTINCT FROM @application:text AND '
      '${prefix}environment_id IS NOT DISTINCT FROM @environment:text';

  Map<String, Object?> _decodeBody(
    Object? raw,
    String label, {
    String? expectedDigest,
  }) {
    final source = raw is String ? raw : jsonEncode(raw);
    final value = _reconciliationObject(jsonDecode(source), label);
    if (expectedDigest != null &&
        sha256Digest(utf8.encode(canonicalJson(value))) != expectedDigest) {
      throw const FormatException('Persisted reconciliation digest mismatch');
    }
    return value;
  }

  Future<List<ResultRow>> _selectById({
    required Session session,
    required String table,
    required ReconciliationScope scope,
    required String idColumn,
    required String id,
    bool forUpdate = false,
    bool includeVersion = false,
    bool includeDigest = true,
  }) => session.execute(
    Sql.named(
      'SELECT body::text AS body_json '
      '${includeDigest ? ', body_digest ' : ''}'
      '${includeVersion ? ', version ' : ''}'
      'FROM $table WHERE ${_scopeWhere()} AND $idColumn = @id:text '
      '${forUpdate ? 'FOR UPDATE' : ''}',
    ),
    parameters: <String, Object?>{..._scopeParameters(scope), 'id': id},
  );

  @override
  Future<ReconciliationRecordWriteResult> putFinding(
    ReconciliationFinding finding,
  ) async {
    await _disconnectIfRequested(PostgresDisconnectPoint.findingCommitBefore);
    final body = finding.toJson();
    final canonical = canonicalJson(body);
    final digest = sha256Digest(utf8.encode(canonical));
    final result = await _pool.runTx((session) async {
      final rows = await _selectById(
        session: session,
        table: 'control_plane_reconciliation_findings',
        scope: finding.scope,
        idColumn: 'finding_id',
        id: finding.findingId,
        forUpdate: true,
      );
      if (rows.isNotEmpty) {
        final existing = _decodeBody(
          rows.first.toColumnMap()['body_json'],
          'finding',
          expectedDigest: '${rows.first.toColumnMap()['body_digest']}',
        );
        if (canonicalJson(existing) == canonical) {
          return ReconciliationRecordWriteResult.replayed;
        }
        throw const StorageConflict(
          'Immutable reconciliation finding conflict',
        );
      }
      final inserted = await session.execute(
        Sql.named(
          'INSERT INTO control_plane_reconciliation_findings '
          '(organization_id, application_id, environment_id, finding_id, body, body_digest) '
          'VALUES (@organization:text, @application:text, @environment:text, '
          '@finding:text, @body:jsonb, @digest:text) '
          'ON CONFLICT (organization_id, finding_id) DO NOTHING',
        ),
        parameters: <String, Object?>{
          ..._scopeParameters(finding.scope),
          'finding': finding.findingId,
          'body': body,
          'digest': digest,
        },
      );
      if (inserted.affectedRows == 1) {
        return ReconciliationRecordWriteResult.created;
      }
      final raced = await _selectById(
        session: session,
        table: 'control_plane_reconciliation_findings',
        scope: finding.scope,
        idColumn: 'finding_id',
        id: finding.findingId,
        forUpdate: true,
      );
      if (raced.isNotEmpty &&
          canonicalJson(
                _decodeBody(
                  raced.first.toColumnMap()['body_json'],
                  'finding',
                  expectedDigest: '${raced.first.toColumnMap()['body_digest']}',
                ),
              ) ==
              canonical) {
        return ReconciliationRecordWriteResult.replayed;
      }
      throw const StorageConflict('Immutable reconciliation finding conflict');
    });
    await _disconnectIfRequested(PostgresDisconnectPoint.findingCommitAfter);
    return result;
  }

  @override
  Future<ReconciliationFinding?> readFinding(
    ReconciliationScope scope,
    String findingId,
  ) async {
    final rows = await _selectById(
      session: _pool,
      table: 'control_plane_reconciliation_findings',
      scope: scope,
      idColumn: 'finding_id',
      id: _reconciliationId(findingId, 'finding ID'),
    );
    if (rows.isEmpty) return null;
    final columns = rows.first.toColumnMap();
    final finding = ReconciliationFinding.fromJson(
      _decodeBody(
        columns['body_json'],
        'finding',
        expectedDigest: '${columns['body_digest']}',
      ),
    );
    if (finding.scope.canonicalSerialization != scope.canonicalSerialization) {
      throw const FormatException(
        'Finding scope does not match requested scope',
      );
    }
    return finding;
  }

  @override
  Future<List<ReconciliationFinding>> listFindings(
    ReconciliationScope scope, {
    int? limit,
  }) async {
    final limitSql = limit == null ? '' : ' LIMIT @limit:int';
    final parameters = <String, Object?>{
      ..._scopeParameters(scope),
      if (limit != null) 'limit': limit,
    };
    final rows = await _pool.execute(
      Sql.named(
        'SELECT body::text AS body_json, body_digest '
        'FROM control_plane_reconciliation_findings '
        'WHERE ${_scopeWhere()} ORDER BY finding_id$limitSql',
      ),
      parameters: parameters,
    );
    return List.unmodifiable(
      rows.map((row) {
        final columns = row.toColumnMap();
        return ReconciliationFinding.fromJson(
          _decodeBody(
            columns['body_json'],
            'finding',
            expectedDigest: '${columns['body_digest']}',
          ),
        );
      }),
    );
  }

  @override
  Future<ReconciliationRecordWriteResult> putRepairAttempt(
    ReconciliationRepairAttempt attempt,
  ) async {
    await _disconnectIfRequested(
      PostgresDisconnectPoint.repairAttemptCommitBefore,
    );
    final body = attempt.toJson();
    final canonical = canonicalJson(body);
    final digest = sha256Digest(utf8.encode(canonical));
    final result = await _pool.runTx((session) async {
      final findingRows = await _selectById(
        session: session,
        table: 'control_plane_reconciliation_findings',
        scope: attempt.scope,
        idColumn: 'finding_id',
        id: attempt.findingId,
      );
      if (findingRows.isEmpty) {
        throw const StorageConflict(
          'Repair attempt references missing finding',
        );
      }
      final rows = await _selectById(
        session: session,
        table: 'control_plane_reconciliation_repairs',
        scope: attempt.scope,
        idColumn: 'repair_id',
        id: attempt.repairId,
        forUpdate: true,
      );
      if (rows.isNotEmpty) {
        final columns = rows.first.toColumnMap();
        final existing = _decodeBody(
          columns['body_json'],
          'repair attempt',
          expectedDigest: '${columns['body_digest']}',
        );
        if (canonicalJson(existing) == canonical) {
          return ReconciliationRecordWriteResult.replayed;
        }
        throw const StorageConflict(
          'Immutable reconciliation repair-attempt conflict',
        );
      }
      final inserted = await session.execute(
        Sql.named(
          'INSERT INTO control_plane_reconciliation_repairs '
          '(organization_id, application_id, environment_id, repair_id, finding_id, body, body_digest) '
          'VALUES (@organization:text, @application:text, @environment:text, '
          '@repair:text, @finding:text, @body:jsonb, @digest:text) '
          'ON CONFLICT (organization_id, repair_id) DO NOTHING',
        ),
        parameters: <String, Object?>{
          ..._scopeParameters(attempt.scope),
          'repair': attempt.repairId,
          'finding': attempt.findingId,
          'body': body,
          'digest': digest,
        },
      );
      if (inserted.affectedRows == 1) {
        return ReconciliationRecordWriteResult.created;
      }
      final raced = await _selectById(
        session: session,
        table: 'control_plane_reconciliation_repairs',
        scope: attempt.scope,
        idColumn: 'repair_id',
        id: attempt.repairId,
        forUpdate: true,
      );
      if (raced.isNotEmpty &&
          canonicalJson(
                _decodeBody(
                  raced.first.toColumnMap()['body_json'],
                  'repair attempt',
                  expectedDigest: '${raced.first.toColumnMap()['body_digest']}',
                ),
              ) ==
              canonical) {
        return ReconciliationRecordWriteResult.replayed;
      }
      throw const StorageConflict(
        'Immutable reconciliation repair-attempt conflict',
      );
    });
    await _disconnectIfRequested(
      PostgresDisconnectPoint.repairAttemptCommitAfter,
    );
    return result;
  }

  @override
  Future<ReconciliationRepairAttempt?> readRepairAttempt(
    ReconciliationScope scope,
    String repairId,
  ) async {
    final rows = await _selectById(
      session: _pool,
      table: 'control_plane_reconciliation_repairs',
      scope: scope,
      idColumn: 'repair_id',
      id: _reconciliationId(repairId, 'repair ID'),
    );
    if (rows.isEmpty) return null;
    final columns = rows.first.toColumnMap();
    return ReconciliationRepairAttempt.fromJson(
      _decodeBody(
        columns['body_json'],
        'repair attempt',
        expectedDigest: '${columns['body_digest']}',
      ),
    );
  }

  @override
  Future<List<ReconciliationRepairAttempt>> listRepairAttempts(
    ReconciliationScope scope, {
    int? limit,
  }) async {
    final limitSql = limit == null ? '' : ' LIMIT @limit:int';
    final parameters = <String, Object?>{
      ..._scopeParameters(scope),
      if (limit != null) 'limit': limit,
    };
    final rows = await _pool.execute(
      Sql.named(
        'SELECT body::text AS body_json, body_digest '
        'FROM control_plane_reconciliation_repairs '
        'WHERE ${_scopeWhere()} ORDER BY repair_id$limitSql',
      ),
      parameters: parameters,
    );
    return List.unmodifiable(
      rows.map((row) {
        final columns = row.toColumnMap();
        return ReconciliationRepairAttempt.fromJson(
          _decodeBody(
            columns['body_json'],
            'repair attempt',
            expectedDigest: '${columns['body_digest']}',
          ),
        );
      }),
    );
  }

  @override
  Future<ReconciliationFindingLifecycle?> readFindingLifecycle(
    ReconciliationScope scope,
    String findingId,
  ) async {
    final rows = await _selectById(
      session: _pool,
      table: 'control_plane_reconciliation_lifecycle',
      scope: scope,
      idColumn: 'finding_id',
      id: _reconciliationId(findingId, 'finding ID'),
      includeDigest: false,
    );
    if (rows.isEmpty) return null;
    final columns = rows.first.toColumnMap();
    return ReconciliationFindingLifecycle.fromJson(
      _decodeBody(columns['body_json'], 'lifecycle'),
    );
  }

  @override
  Future<ReconciliationFindingLifecycle> updateFindingLifecycle({
    required ReconciliationFindingLifecycle lifecycle,
    required int expectedVersion,
  }) async {
    await _disconnectIfRequested(PostgresDisconnectPoint.lifecycleCommitBefore);
    final result = await _pool.runTx((session) async {
      final findingRows = await _selectById(
        session: session,
        table: 'control_plane_reconciliation_findings',
        scope: lifecycle.scope,
        idColumn: 'finding_id',
        id: lifecycle.findingId,
      );
      if (findingRows.isEmpty) {
        throw const StorageConflict('Lifecycle references missing finding');
      }
      final rows = await _selectById(
        session: session,
        table: 'control_plane_reconciliation_lifecycle',
        scope: lifecycle.scope,
        idColumn: 'finding_id',
        id: lifecycle.findingId,
        forUpdate: true,
        includeVersion: true,
        includeDigest: false,
      );
      final currentVersion = rows.isEmpty
          ? 0
          : int.parse('${rows.first.toColumnMap()['version']}');
      if (currentVersion != expectedVersion ||
          lifecycle.version != expectedVersion + 1) {
        throw StoragePreconditionFailed(
          'Reconciliation lifecycle version is stale',
          currentRevision: currentVersion,
        );
      }
      final body = lifecycle.toJson();
      if (rows.isEmpty) {
        await session.execute(
          Sql.named(
            'INSERT INTO control_plane_reconciliation_lifecycle '
            '(organization_id, application_id, environment_id, finding_id, version, body) '
            'VALUES (@organization:text, @application:text, @environment:text, '
            '@finding:text, @version:int8, @body:jsonb)',
          ),
          parameters: <String, Object?>{
            ..._scopeParameters(lifecycle.scope),
            'finding': lifecycle.findingId,
            'version': lifecycle.version,
            'body': body,
          },
        );
      } else {
        final updated = await session.execute(
          Sql.named(
            'UPDATE control_plane_reconciliation_lifecycle SET '
            'version = @version:int8, body = @body:jsonb, updated_at = now() '
            'WHERE ${_scopeWhere()} AND finding_id = @finding:text '
            'AND version = @expected:int8',
          ),
          parameters: <String, Object?>{
            ..._scopeParameters(lifecycle.scope),
            'finding': lifecycle.findingId,
            'version': lifecycle.version,
            'body': body,
            'expected': expectedVersion,
          },
        );
        if (updated.affectedRows != 1) {
          throw const StorageConflict(
            'Reconciliation lifecycle CAS did not persist',
          );
        }
      }
      return lifecycle;
    });
    await _disconnectIfRequested(PostgresDisconnectPoint.lifecycleCommitAfter);
    return result;
  }

  @override
  Future<ReconciliationCursorState?> readCursor(
    ReconciliationScope scope,
  ) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT body::text AS body_json FROM control_plane_reconciliation_cursors '
        'WHERE ${_scopeWhere()} AND scope_digest = @scopeDigest:text',
      ),
      parameters: <String, Object?>{
        ..._scopeParameters(scope),
        'scopeDigest': _reconciliationScopeDigest(scope),
      },
    );
    if (rows.isEmpty) return null;
    return ReconciliationCursorState.fromJson(
      _decodeBody(rows.first.toColumnMap()['body_json'], 'cursor state'),
    );
  }

  @override
  Future<ReconciliationCursorState> saveCursor({
    required ReconciliationCursorState cursor,
    required int expectedVersion,
  }) async {
    await _disconnectIfRequested(PostgresDisconnectPoint.cursorCommitBefore);
    final result = await _pool.runTx((session) async {
      final rows = await session.execute(
        Sql.named(
          'SELECT version, body::text AS body_json '
          'FROM control_plane_reconciliation_cursors '
          'WHERE ${_scopeWhere()} AND scope_digest = @scopeDigest:text FOR UPDATE',
        ),
        parameters: <String, Object?>{
          ..._scopeParameters(cursor.scope),
          'scopeDigest': _reconciliationScopeDigest(cursor.scope),
        },
      );
      final currentVersion = rows.isEmpty
          ? 0
          : int.parse('${rows.first.toColumnMap()['version']}');
      if (currentVersion != expectedVersion ||
          cursor.version != expectedVersion + 1) {
        throw StoragePreconditionFailed(
          'Reconciliation cursor version is stale',
          currentRevision: currentVersion,
        );
      }
      final body = cursor.toJson();
      if (rows.isEmpty) {
        await session.execute(
          Sql.named(
            'INSERT INTO control_plane_reconciliation_cursors '
            '(organization_id, application_id, environment_id, scope_digest, version, body) '
            'VALUES (@organization:text, @application:text, @environment:text, '
            '@scopeDigest:text, @version:int8, @body:jsonb)',
          ),
          parameters: <String, Object?>{
            ..._scopeParameters(cursor.scope),
            'scopeDigest': _reconciliationScopeDigest(cursor.scope),
            'version': cursor.version,
            'body': body,
          },
        );
      } else {
        final updated = await session.execute(
          Sql.named(
            'UPDATE control_plane_reconciliation_cursors SET '
            'version = @version:int8, body = @body:jsonb, updated_at = now() '
            'WHERE ${_scopeWhere()} AND scope_digest = @scopeDigest:text '
            'AND version = @expected:int8',
          ),
          parameters: <String, Object?>{
            ..._scopeParameters(cursor.scope),
            'scopeDigest': _reconciliationScopeDigest(cursor.scope),
            'version': cursor.version,
            'body': body,
            'expected': expectedVersion,
          },
        );
        if (updated.affectedRows != 1) {
          throw const StorageConflict(
            'Reconciliation cursor CAS did not persist',
          );
        }
      }
      return cursor;
    });
    await _disconnectIfRequested(PostgresDisconnectPoint.cursorCommitAfter);
    return result;
  }
}
