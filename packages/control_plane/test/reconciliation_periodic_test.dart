import 'dart:async';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  test('periodic configuration is disabled by default and parses bounds', () {
    final defaults = ReconciliationPeriodicConfig.fromEnvironment(
      <String, String>{},
    );
    expect(defaults.enabled, isFalse);
    expect(defaults.interval, reconciliationPeriodicDefaultInterval);
    expect(defaults.jitter, reconciliationPeriodicDefaultJitter);

    final configured = ReconciliationPeriodicConfig.fromEnvironment(
      <String, String>{
        'HYFENS_RECONCILIATION_PERIODIC_ENABLED': 'true',
        'HYFENS_RECONCILIATION_PERIODIC_INTERVAL_SECONDS': '10',
        'HYFENS_RECONCILIATION_PERIODIC_JITTER_SECONDS': '2',
        'HYFENS_RECONCILIATION_PERIODIC_STARTUP_DELAY_SECONDS': '3',
        'HYFENS_RECONCILIATION_PERIODIC_MAX_BACKOFF_SECONDS': '30',
        'HYFENS_RECONCILIATION_PERIODIC_SHUTDOWN_TIMEOUT_SECONDS': '4',
      },
    );
    expect(configured.enabled, isTrue);
    expect(configured.interval, const Duration(seconds: 10));
    expect(configured.jitter, const Duration(seconds: 2));
    expect(configured.startupDelay, const Duration(seconds: 3));
    expect(configured.maximumBackoff, const Duration(seconds: 30));
    expect(configured.shutdownTimeout, const Duration(seconds: 4));

    expect(
      () => ReconciliationPeriodicConfig.fromEnvironment(<String, String>{
        'HYFENS_RECONCILIATION_PERIODIC_ENABLED': 'yes',
      }),
      throwsArgumentError,
    );
    expect(
      () => ReconciliationPeriodicConfig.fromEnvironment(<String, String>{
        'HYFENS_RECONCILIATION_PERIODIC_INTERVAL_SECONDS': '1',
      }),
      throwsArgumentError,
    );
    expect(
      () => ReconciliationPeriodicConfig.fromEnvironment(<String, String>{
        'HYFENS_RECONCILIATION_PERIODIC_INTERVAL_SECONDS': '10',
        'HYFENS_RECONCILIATION_PERIODIC_JITTER_SECONDS': '6',
      }),
      throwsArgumentError,
    );
  });

  test(
    'ControlPlaneConfig carries the explicit disabled-by-default runner',
    () {
      final config = ControlPlaneConfig.fromEnvironment(<String, String>{});
      expect(config.reconciliationPeriodic.enabled, isFalse);
    },
  );

  test('disabled runner never invokes reconciliation', () async {
    var invocations = 0;
    final runner = ReconciliationPeriodicRunner(
      config: const ReconciliationPeriodicConfig(),
      invokeBoundedReconciliation: () async => invocations++,
    );
    await runner.start();
    expect(await runner.runTick(), ReconciliationPeriodicRunOutcome.disabled);
    await runner.stop();
    expect(invocations, 0);
    expect(runner.metrics.runOutcomeCounts['DISABLED'], 1);
  });

  test('startup scheduling applies bounded jitter and stops cleanly', () async {
    final now = DateTime.utc(2026, 8, 24, 12);
    final runner = ReconciliationPeriodicRunner(
      config: const ReconciliationPeriodicConfig(
        enabled: true,
        interval: Duration(seconds: 10),
        jitter: Duration(seconds: 2),
        startupDelay: Duration(seconds: 3),
        maximumBackoff: Duration(seconds: 30),
        shutdownTimeout: Duration(seconds: 1),
      ),
      invokeBoundedReconciliation: () async {},
      clock: () => now,
      jitterSource: (bound) => bound,
    );
    await runner.start();
    expect(
      DateTime.parse(runner.statusJson()['nextDueAt'] as String),
      now.add(const Duration(seconds: 5)),
    );
    await runner.stop();
    expect(runner.statusJson()['nextDueAt'], isNull);
  });

  test('overlap is skipped without an in-memory backlog', () async {
    final release = Completer<void>();
    var invocations = 0;
    final runner = ReconciliationPeriodicRunner(
      config: const ReconciliationPeriodicConfig(enabled: true),
      invokeBoundedReconciliation: () async {
        invocations++;
        await release.future;
      },
    );
    final first = runner.runTick();
    expect(
      await runner.runTick(),
      ReconciliationPeriodicRunOutcome.overlapSkipped,
    );
    release.complete();
    expect(await first, ReconciliationPeriodicRunOutcome.success);
    expect(invocations, 1);
    expect(runner.metrics.overlapSkips, 1);
  });

  test(
    'shared execution gate rejects periodic overlap with startup/manual work',
    () async {
      final release = Completer<void>();
      final gate = ReconciliationExecutionGate();
      final active = gate.run(() async => release.future);
      final runner = ReconciliationPeriodicRunner(
        config: const ReconciliationPeriodicConfig(enabled: true),
        invokeBoundedReconciliation: () => gate.run(() async {}),
      );
      expect(
        await runner.runTick(),
        ReconciliationPeriodicRunOutcome.overlapSkipped,
      );
      release.complete();
      await active;
    },
  );

  test(
    'store failure uses bounded exponential backoff and resets on success',
    () async {
      var fail = true;
      final runner = ReconciliationPeriodicRunner(
        config: const ReconciliationPeriodicConfig(
          enabled: true,
          interval: Duration(seconds: 5),
          jitter: Duration.zero,
          maximumBackoff: Duration(seconds: 20),
        ),
        invokeBoundedReconciliation: () async {
          if (fail) {
            throw const StorageUnavailable('test outage');
          }
        },
      );
      expect(await runner.runTick(), ReconciliationPeriodicRunOutcome.failure);
      expect(runner.statusJson()['consecutiveFailures'], 1);
      expect(runner.statusJson()['backoffDelaySeconds'], 10);
      expect(runner.metrics.storeFailures, 1);
      fail = false;
      expect(await runner.runTick(), ReconciliationPeriodicRunOutcome.success);
      expect(runner.statusJson()['backoffState'], 'NORMAL');
      expect(runner.statusJson()['consecutiveFailures'], 0);
    },
  );

  test('ownership contention skips and later handoff succeeds', () async {
    final ownership = _FakeOwnership()..available = false;
    var invocations = 0;
    final runner = ReconciliationPeriodicRunner(
      config: const ReconciliationPeriodicConfig(enabled: true),
      ownership: ownership,
      invokeBoundedReconciliation: () async => invocations++,
    );
    expect(
      await runner.runTick(),
      ReconciliationPeriodicRunOutcome.lockContention,
    );
    ownership.available = true;
    expect(await runner.runTick(), ReconciliationPeriodicRunOutcome.success);
    expect(invocations, 1);
    expect(runner.metrics.lockContention, 1);
  });

  test(
    'shutdown waits within a bounded budget and never force-cancels work',
    () async {
      final release = Completer<void>();
      final runner = ReconciliationPeriodicRunner(
        config: const ReconciliationPeriodicConfig(
          enabled: true,
          shutdownTimeout: Duration(milliseconds: 10),
        ),
        invokeBoundedReconciliation: () async => release.future,
      );
      final tick = runner.runTick();
      await runner.stop();
      expect(runner.statusJson()['shutdownTimedOut'], isTrue);
      release.complete();
      expect(await tick, ReconciliationPeriodicRunOutcome.success);
    },
  );

  test('File runner remains bounded and single-process', () async {
    final root = await Directory.systemTemp.createTemp('hyfens-periodic-file-');
    final store = FileReconciliationStore(root);
    await store.initialize();
    addTearDown(() async {
      await store.close();
      if (await root.exists()) await root.delete(recursive: true);
    });
    var invocations = 0;
    final runner = ReconciliationPeriodicRunner(
      config: const ReconciliationPeriodicConfig(enabled: true),
      invokeBoundedReconciliation: () async {
        await store.checkReadiness();
        invocations++;
      },
    );
    expect(await runner.runTick(), ReconciliationPeriodicRunOutcome.success);
    expect(await runner.runTick(), ReconciliationPeriodicRunOutcome.success);
    expect(invocations, 2);
  });

  test('malformed invocation fails once without a retry loop', () async {
    var invocations = 0;
    final runner = ReconciliationPeriodicRunner(
      config: const ReconciliationPeriodicConfig(enabled: true),
      invokeBoundedReconciliation: () async {
        invocations++;
        throw const FormatException('malformed persisted row');
      },
    );
    expect(await runner.runTick(), ReconciliationPeriodicRunOutcome.failure);
    expect(invocations, 1);
    expect(runner.metrics.runOutcomeCounts['FAILURE'], 1);
  });

  test(
    'restart resumes normal cadence without replaying missed ticks',
    () async {
      var firstInvocations = 0;
      final first = ReconciliationPeriodicRunner(
        config: const ReconciliationPeriodicConfig(
          enabled: true,
          interval: Duration(seconds: 5),
          jitter: Duration.zero,
          startupDelay: Duration(hours: 1),
          maximumBackoff: Duration(seconds: 20),
        ),
        invokeBoundedReconciliation: () async => firstInvocations++,
      );
      await first.start();
      expect(first.statusJson()['nextDueAt'], isNotNull);
      await first.stop();
      expect(firstInvocations, 0);

      var secondInvocations = 0;
      final second = ReconciliationPeriodicRunner(
        config: first.config,
        invokeBoundedReconciliation: () async => secondInvocations++,
      );
      await second.start();
      expect(second.statusJson()['nextDueAt'], isNotNull);
      await second.stop();
      expect(secondInvocations, 0);
    },
  );

  final postgresUrl = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  test(
    'PostgreSQL advisory ownership contends and hands off',
    () async {
      final first = PostgresReconciliationStore(postgresUrl!);
      final second = PostgresReconciliationStore(postgresUrl);
      addTearDown(first.close);
      addTearDown(second.close);
      await Future.wait(<Future<void>>[
        first.initialize(),
        second.initialize(),
      ]);
      final ownerA = PostgresReconciliationPeriodicOwnership(first);
      final ownerB = PostgresReconciliationPeriodicOwnership(second);
      final started = Completer<void>();
      final release = Completer<void>();
      final held = ownerA.runIfOwned(() async {
        await first.checkReadiness();
        started.complete();
        await release.future;
      });
      await started.future;
      expect(
        await ownerB.runIfOwned(() async => second.checkReadiness()),
        isFalse,
      );
      release.complete();
      expect(await held, isTrue);
      expect(
        await ownerB.runIfOwned(() async => second.checkReadiness()),
        isTrue,
      );
    },
    skip: postgresUrl == null || postgresUrl.isEmpty
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );

  test(
    'PostgreSQL ownership action failure releases the lock safely',
    () async {
      final ownership = _FakeOwnership()..available = true;
      ownership.throwOnAction = true;
      final runner = ReconciliationPeriodicRunner(
        config: const ReconciliationPeriodicConfig(enabled: true),
        ownership: ownership,
        invokeBoundedReconciliation: () async {},
      );
      expect(await runner.runTick(), ReconciliationPeriodicRunOutcome.failure);
      ownership.throwOnAction = false;
      expect(await runner.runTick(), ReconciliationPeriodicRunOutcome.success);
    },
  );

  test(
    'PostgreSQL ownership failure releases the lock for handoff',
    () async {
      final first = PostgresReconciliationStore(postgresUrl!);
      final second = PostgresReconciliationStore(postgresUrl);
      addTearDown(first.close);
      addTearDown(second.close);
      await Future.wait(<Future<void>>[
        first.initialize(),
        second.initialize(),
      ]);
      final ownerA = PostgresReconciliationPeriodicOwnership(first);
      final ownerB = PostgresReconciliationPeriodicOwnership(second);
      await expectLater(
        ownerA.runIfOwned(() async {
          throw const FormatException('simulated bounded pass failure');
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        await ownerB.runIfOwned(() async => second.checkReadiness()),
        isTrue,
      );
    },
    skip: postgresUrl == null || postgresUrl.isEmpty
        ? 'HYFENS_TEST_POSTGRES_URL is not configured'
        : false,
  );
}

final class _FakeOwnership implements ReconciliationPeriodicOwnership {
  bool available = true;
  bool throwOnAction = false;

  @override
  Future<bool> runIfOwned(Future<void> Function() action) async {
    if (!available) return false;
    if (throwOnAction) {
      throw const StorageUnavailable('simulated ownership/session loss');
    }
    await action();
    return true;
  }
}
