import 'dart:async';
import 'dart:math';

import 'errors.dart';
import 'reconciliation_execution.dart';
import 'reconciliation_persistence.dart';

const Duration reconciliationPeriodicDefaultInterval = Duration(minutes: 5);
const Duration reconciliationPeriodicMinimumInterval = Duration(seconds: 5);
const Duration reconciliationPeriodicMaximumInterval = Duration(hours: 24);
const Duration reconciliationPeriodicDefaultJitter = Duration(seconds: 30);
const Duration reconciliationPeriodicDefaultStartupDelay =
    reconciliationPeriodicDefaultInterval;
const Duration reconciliationPeriodicDefaultMaximumBackoff = Duration(
  minutes: 30,
);
const Duration reconciliationPeriodicDefaultShutdownTimeout = Duration(
  seconds: 30,
);

typedef ReconciliationPeriodicJitterSource = Duration Function(Duration bound);

enum ReconciliationPeriodicRunOutcome {
  success,
  failure,
  overlapSkipped,
  lockContention,
  disabled,
  shutdown,
}

extension ReconciliationPeriodicRunOutcomeWire
    on ReconciliationPeriodicRunOutcome {
  String get wireName => switch (this) {
    ReconciliationPeriodicRunOutcome.success => 'SUCCESS',
    ReconciliationPeriodicRunOutcome.failure => 'FAILURE',
    ReconciliationPeriodicRunOutcome.overlapSkipped => 'OVERLAP_SKIPPED',
    ReconciliationPeriodicRunOutcome.lockContention => 'LOCK_CONTENTION',
    ReconciliationPeriodicRunOutcome.disabled => 'DISABLED',
    ReconciliationPeriodicRunOutcome.shutdown => 'SHUTDOWN',
  };
}

final class ReconciliationPeriodicConfig {
  const ReconciliationPeriodicConfig({
    this.enabled = false,
    this.interval = reconciliationPeriodicDefaultInterval,
    this.jitter = reconciliationPeriodicDefaultJitter,
    this.startupDelay = reconciliationPeriodicDefaultStartupDelay,
    this.maximumBackoff = reconciliationPeriodicDefaultMaximumBackoff,
    this.shutdownTimeout = reconciliationPeriodicDefaultShutdownTimeout,
  });

  final bool enabled;
  final Duration interval;
  final Duration jitter;
  final Duration startupDelay;
  final Duration maximumBackoff;
  final Duration shutdownTimeout;

  void validate() {
    if (interval < reconciliationPeriodicMinimumInterval ||
        interval > reconciliationPeriodicMaximumInterval) {
      throw ArgumentError.value(interval, 'interval');
    }
    if (jitter < Duration.zero || jitter > interval ~/ 2) {
      throw ArgumentError.value(jitter, 'jitter');
    }
    if (startupDelay < Duration.zero ||
        startupDelay > reconciliationPeriodicMaximumInterval) {
      throw ArgumentError.value(startupDelay, 'startupDelay');
    }
    if (maximumBackoff < interval ||
        maximumBackoff > reconciliationPeriodicMaximumInterval) {
      throw ArgumentError.value(maximumBackoff, 'maximumBackoff');
    }
    if (shutdownTimeout <= Duration.zero ||
        shutdownTimeout > const Duration(minutes: 5)) {
      throw ArgumentError.value(shutdownTimeout, 'shutdownTimeout');
    }
  }

  factory ReconciliationPeriodicConfig.fromEnvironment(
    Map<String, String> values,
  ) {
    final result = ReconciliationPeriodicConfig(
      enabled: _bool(values, 'HYFENS_RECONCILIATION_PERIODIC_ENABLED', false),
      interval: _seconds(
        values,
        'HYFENS_RECONCILIATION_PERIODIC_INTERVAL_SECONDS',
        reconciliationPeriodicDefaultInterval,
      ),
      jitter: _seconds(
        values,
        'HYFENS_RECONCILIATION_PERIODIC_JITTER_SECONDS',
        reconciliationPeriodicDefaultJitter,
      ),
      startupDelay: _seconds(
        values,
        'HYFENS_RECONCILIATION_PERIODIC_STARTUP_DELAY_SECONDS',
        reconciliationPeriodicDefaultStartupDelay,
      ),
      maximumBackoff: _seconds(
        values,
        'HYFENS_RECONCILIATION_PERIODIC_MAX_BACKOFF_SECONDS',
        reconciliationPeriodicDefaultMaximumBackoff,
      ),
      shutdownTimeout: _seconds(
        values,
        'HYFENS_RECONCILIATION_PERIODIC_SHUTDOWN_TIMEOUT_SECONDS',
        reconciliationPeriodicDefaultShutdownTimeout,
      ),
    );
    result.validate();
    return result;
  }

  static bool _bool(Map<String, String> values, String key, bool fallback) {
    final value = values[key];
    if (value == null || value.isEmpty) return fallback;
    return switch (value.toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => throw ArgumentError('$key must be true or false'),
    };
  }

  static Duration _seconds(
    Map<String, String> values,
    String key,
    Duration fallback,
  ) {
    final value = values[key];
    if (value == null || value.isEmpty) return fallback;
    final seconds = int.tryParse(value);
    if (seconds == null || seconds < 0) {
      throw ArgumentError('$key must be a non-negative integer');
    }
    return Duration(seconds: seconds);
  }
}

abstract interface class ReconciliationPeriodicOwnership {
  /// Runs [action] only when this process owns the periodic pass.
  ///
  /// `false` means another process owns the pass. The method must not wait in
  /// a loop for ownership and must release ownership after [action] returns.
  Future<bool> runIfOwned(Future<void> Function() action);
}

final class LocalReconciliationPeriodicOwnership
    implements ReconciliationPeriodicOwnership {
  const LocalReconciliationPeriodicOwnership();

  @override
  Future<bool> runIfOwned(Future<void> Function() action) async {
    await action();
    return true;
  }
}

/// PostgreSQL session-scoped ownership for the single global periodic pass.
///
/// The advisory lock is coordination only. Finding, repair, lifecycle, cursor,
/// audit, and rollout authority remain in their existing seams.
final class PostgresReconciliationPeriodicOwnership
    implements ReconciliationPeriodicOwnership {
  const PostgresReconciliationPeriodicOwnership(this.store);

  final PostgresReconciliationStore store;

  @override
  Future<bool> runIfOwned(Future<void> Function() action) =>
      store.runIfPeriodicOwner(action);
}

final class ReconciliationPeriodicMetrics {
  ReconciliationPeriodicMetrics()
    : runOutcomeCounts = <String, int>{
        for (final outcome in ReconciliationPeriodicRunOutcome.values)
          outcome.wireName: 0,
      };

  final Map<String, int> runOutcomeCounts;
  int runsTotal = 0;
  int overlapSkips = 0;
  int lockContention = 0;
  int storeFailures = 0;
  DateTime? lastRunStartedAt;
  DateTime? lastRunCompletedAt;
  int lastRunDurationSeconds = 0;
  ReconciliationPeriodicRunOutcome? lastRunOutcome;

  void recordStarted(DateTime startedAt) {
    runsTotal++;
    lastRunStartedAt = startedAt.toUtc();
  }

  void recordOutcome(
    ReconciliationPeriodicRunOutcome outcome, {
    DateTime? completedAt,
  }) {
    runOutcomeCounts[outcome.wireName] =
        (runOutcomeCounts[outcome.wireName] ?? 0) + 1;
    lastRunOutcome = outcome;
    if (outcome == ReconciliationPeriodicRunOutcome.overlapSkipped) {
      overlapSkips++;
    }
    if (outcome == ReconciliationPeriodicRunOutcome.lockContention) {
      lockContention++;
    }
    if (completedAt != null) lastRunCompletedAt = completedAt.toUtc();
    final started = lastRunStartedAt;
    if (started != null && completedAt != null) {
      lastRunDurationSeconds = completedAt
          .toUtc()
          .difference(started)
          .inSeconds
          .clamp(0, 0x7fffffff);
    }
  }

  void recordStoreFailure() {
    storeFailures++;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'counters': <String, int>{
      'reconciliation_periodic_runs_total': runsTotal,
      'reconciliation_periodic_overlap_skips_total': overlapSkips,
      'reconciliation_periodic_lock_contention_total': lockContention,
      'reconciliation_periodic_store_failures_total': storeFailures,
      'reconciliation_periodic_last_run_duration_seconds':
          lastRunDurationSeconds,
    },
    'runOutcomes': Map<String, int>.from(runOutcomeCounts),
    'lastRun': <String, Object?>{
      'startedAt': lastRunStartedAt?.toIso8601String(),
      'completedAt': lastRunCompletedAt?.toIso8601String(),
      'outcome': lastRunOutcome?.wireName,
    },
  };
}

final class ReconciliationPeriodicRunner {
  ReconciliationPeriodicRunner({
    required this.config,
    required this.invokeBoundedReconciliation,
    ReconciliationPeriodicOwnership? ownership,
    ReconciliationPeriodicMetrics? metrics,
    DateTime Function()? clock,
    ReconciliationPeriodicJitterSource? jitterSource,
  }) : ownership = ownership ?? const LocalReconciliationPeriodicOwnership(),
       metrics = metrics ?? ReconciliationPeriodicMetrics(),
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _jitterSource = jitterSource ?? _randomJitter {
    config.validate();
  }

  final ReconciliationPeriodicConfig config;
  final Future<void> Function() invokeBoundedReconciliation;
  final ReconciliationPeriodicOwnership ownership;
  final ReconciliationPeriodicMetrics metrics;
  final DateTime Function() _clock;
  final ReconciliationPeriodicJitterSource _jitterSource;

  Timer? _timer;
  Future<ReconciliationPeriodicRunOutcome>? _activeTick;
  bool _started = false;
  bool _stopping = false;
  bool _running = false;
  bool _lockOwned = false;
  int _consecutiveFailures = 0;
  DateTime? _nextDueAt;
  DateTime? _lastRunStartedAt;
  DateTime? _lastRunCompletedAt;
  ReconciliationPeriodicRunOutcome? _lastRunOutcome;
  bool _shutdownTimedOut = false;

  bool get enabled => config.enabled;
  bool get started => _started;
  bool get running => _running;
  bool get lockOwned => _lockOwned;
  Future<ReconciliationPeriodicRunOutcome>? get activeTick => _activeTick;

  Future<void> start() async {
    if (_started) return;
    _stopping = false;
    _shutdownTimedOut = false;
    _started = true;
    if (!config.enabled) return;
    _schedule(config.startupDelay);
  }

  /// Stops future scheduling and waits a bounded time for the active callback.
  /// The callback itself is never force-cancelled inside an authoritative CAS.
  Future<void> stop() async {
    _started = false;
    _stopping = true;
    _timer?.cancel();
    _timer = null;
    _nextDueAt = null;
    final active = _activeTick;
    if (active == null) return;
    try {
      await active.timeout(config.shutdownTimeout);
    } on TimeoutException {
      _shutdownTimedOut = true;
    }
  }

  /// Executes one scheduled tick. This is an in-process composition seam for
  /// tests and service lifecycle code, not an HTTP run-now endpoint.
  Future<ReconciliationPeriodicRunOutcome> runTick() {
    if (!config.enabled) {
      metrics.recordOutcome(ReconciliationPeriodicRunOutcome.disabled);
      _lastRunOutcome = ReconciliationPeriodicRunOutcome.disabled;
      return Future.value(ReconciliationPeriodicRunOutcome.disabled);
    }
    if (_stopping) {
      metrics.recordOutcome(ReconciliationPeriodicRunOutcome.shutdown);
      _lastRunOutcome = ReconciliationPeriodicRunOutcome.shutdown;
      return Future.value(ReconciliationPeriodicRunOutcome.shutdown);
    }
    if (_activeTick != null) {
      metrics.recordOutcome(ReconciliationPeriodicRunOutcome.overlapSkipped);
      _lastRunOutcome = ReconciliationPeriodicRunOutcome.overlapSkipped;
      return Future.value(ReconciliationPeriodicRunOutcome.overlapSkipped);
    }
    late final Future<ReconciliationPeriodicRunOutcome> tick;
    tick = _runTick().whenComplete(() {
      if (identical(_activeTick, tick)) _activeTick = null;
    });
    _activeTick = tick;
    return tick;
  }

  Map<String, Object?> statusJson() => <String, Object?>{
    'enabled': config.enabled,
    'started': _started,
    'running': _running,
    'lockOwned': _lockOwned,
    'lastRunStartedAt': _lastRunStartedAt?.toIso8601String(),
    'lastRunCompletedAt': _lastRunCompletedAt?.toIso8601String(),
    'lastRunOutcome': _lastRunOutcome?.wireName,
    'nextDueAt': _nextDueAt?.toIso8601String(),
    'backoffState': _consecutiveFailures == 0 ? 'NORMAL' : 'EXPONENTIAL',
    'consecutiveFailures': _consecutiveFailures,
    'backoffDelaySeconds': _baseDelay().inSeconds,
    'shutdownTimedOut': _shutdownTimedOut,
    'overlapSkips': metrics.overlapSkips,
  };

  Future<ReconciliationPeriodicRunOutcome> _runTick() async {
    final startedAt = _clock().toUtc();
    _lastRunStartedAt = startedAt;
    _running = true;
    metrics.recordStarted(startedAt);
    var outcome = ReconciliationPeriodicRunOutcome.failure;
    try {
      final acquired = await ownership.runIfOwned(() async {
        _lockOwned = true;
        try {
          await invokeBoundedReconciliation();
        } finally {
          _lockOwned = false;
        }
      });
      if (!acquired) {
        outcome = ReconciliationPeriodicRunOutcome.lockContention;
        metrics.recordOutcome(outcome, completedAt: _clock());
        return outcome;
      }
      _consecutiveFailures = 0;
      outcome = ReconciliationPeriodicRunOutcome.success;
      metrics.recordOutcome(outcome, completedAt: _clock());
      return outcome;
    } on ReconciliationExecutionBusy {
      outcome = ReconciliationPeriodicRunOutcome.overlapSkipped;
      metrics.recordOutcome(outcome, completedAt: _clock());
      return outcome;
    } on StorageUnavailable {
      metrics.recordStoreFailure();
      _consecutiveFailures++;
      metrics.recordOutcome(
        ReconciliationPeriodicRunOutcome.failure,
        completedAt: _clock(),
      );
      return outcome;
    } on Object {
      _consecutiveFailures++;
      metrics.recordOutcome(
        ReconciliationPeriodicRunOutcome.failure,
        completedAt: _clock(),
      );
      return outcome;
    } finally {
      _lockOwned = false;
      _running = false;
      final completedAt = _clock().toUtc();
      _lastRunCompletedAt = completedAt;
      _lastRunOutcome = outcome;
    }
  }

  void _schedule(Duration baseDelay) {
    if (!_started || !config.enabled) return;
    final delay = baseDelay + _jitterSource(config.jitter);
    _nextDueAt = _clock().add(delay);
    _timer = Timer(delay, () {
      unawaited(_timerFired());
    });
  }

  Future<void> _timerFired() async {
    await runTick();
    if (_started) _schedule(_baseDelay());
  }

  Duration _baseDelay() {
    var micros = config.interval.inMicroseconds;
    final cap = config.maximumBackoff.inMicroseconds;
    for (var index = 0; index < _consecutiveFailures; index++) {
      if (micros >= cap) return config.maximumBackoff;
      micros = min(cap, micros * 2);
    }
    return Duration(microseconds: micros);
  }

  static Duration _randomJitter(Duration bound) {
    if (bound <= Duration.zero) return Duration.zero;
    final micros = (Random().nextDouble() * bound.inMicroseconds).floor();
    return Duration(microseconds: micros);
  }
}
