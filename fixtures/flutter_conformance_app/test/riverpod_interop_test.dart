import 'dart:io';

import 'package:conformance/main.dart';
import 'package:conformance/patch_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';

void main() {
  late Directory storage;
  late E1PatchController patches;

  setUp(() async {
    E0PatchRuntime.reset();
    storage = await Directory.systemTemp.createTemp('hyfens-riverpod-');
    patches = createPatchController(storage);
    await patches.initialize();
  });

  tearDown(() async {
    await patches.close();
    E0PatchRuntime.reset();
    await storage.delete(recursive: true);
  });

  testWidgets(
    'Provider subscription and Notifier survive signed activation rejection and rollback',
    (tester) async {
      await tester.pumpWidget(_guardedRiverpodApp());

      final panelContext = tester.element(find.byType(RiverpodPricingPanel));
      final container = ProviderScope.containerOf(panelContext, listen: false);
      final provider = quotedPriceProvider;
      final notifier = container.read(pricingInputProvider.notifier);
      final asyncNotifier = container.read(asyncQuotedPriceProvider.notifier);
      final prices = <int>[];
      final asyncStates = <AsyncValue<int>>[];
      final subscription = container.listen<int>(
        provider,
        (_, next) => prices.add(next),
        fireImmediately: true,
      );
      final asyncSubscription = container.listen<AsyncValue<int>>(
        asyncQuotedPriceProvider,
        (_, next) => asyncStates.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(asyncSubscription.close);

      expect(find.text('riverpod quantity: 6'), findsOneWidget);
      expect(find.text('riverpod tier: 1'), findsOneWidget);
      expect(find.text('riverpod price: 540'), findsOneWidget);
      expect(asyncStates.single, isA<AsyncLoading<int>>());
      expect(await _awaitWidgetAsyncPrice(tester, container), 540);
      expect(find.text('riverpod async price: 540'), findsOneWidget);
      expect(prices, <int>[540]);

      await tester.tap(find.byKey(const Key('riverpod-increment')));
      expect(
        container.read(asyncQuotedPriceProvider),
        isA<AsyncLoading<int>>(),
      );
      expect(await _awaitWidgetAsyncPrice(tester, container), 630);
      expect(find.text('riverpod price: 630'), findsOneWidget);
      expect(find.text('riverpod async price: 630'), findsOneWidget);
      expect(prices, <int>[540, 630]);

      final signed = await _signedPricePatch(1);
      expect(
        await tester.runAsync(() => patches.activateBytes(signed)),
        isTrue,
      );
      await tester.pump();
      expect(patches.status.phase, 'pendingHealth');

      // Riverpod has no dependency on E1 status. Activation alone therefore
      // leaves both already-cached Provider values unchanged.
      expect(container.read(provider), 630);
      expect(container.read(asyncQuotedPriceProvider).requireValue, 630);
      expect(find.text('riverpod price: 630'), findsOneWidget);
      expect(find.text('riverpod async price: 630'), findsOneWidget);
      expect(prices, <int>[540, 630]);

      // The application's ordinary input change invalidates the derived
      // Provider through its existing dependency and reaches the patch guard.
      await tester.tap(find.byKey(const Key('riverpod-tier-toggle')));
      expect(
        container.read(asyncQuotedPriceProvider),
        isA<AsyncLoading<int>>(),
      );
      expect(await _awaitWidgetAsyncPrice(tester, container), 490);
      expect(find.text('riverpod tier: 2'), findsOneWidget);
      expect(find.text('riverpod price: 490'), findsOneWidget);
      expect(find.text('riverpod async price: 490'), findsOneWidget);
      expect(prices, <int>[540, 630, 490]);
      _expectRiverpodIdentity(
        tester,
        container: container,
        provider: provider,
        notifier: notifier,
        asyncNotifier: asyncNotifier,
      );

      expect(await tester.runAsync(patches.markHealthy), isTrue);
      await tester.pump();
      expect(patches.status.phase, 'healthy');

      expect(
        await tester.runAsync(() => patches.activateBytes(<int>[1, 2, 3])),
        isFalse,
      );
      await tester.pump();
      expect(patches.status.phase, 'rejected');
      expect(patches.status.mode, E1PatchMode.patch);
      expect(find.text('riverpod price: 490'), findsOneWidget);

      await tester.tap(find.byKey(const Key('riverpod-tier-toggle')));
      expect(await _awaitWidgetAsyncPrice(tester, container), 525);
      expect(find.text('riverpod price: 525'), findsOneWidget);
      expect(find.text('riverpod async price: 525'), findsOneWidget);
      expect(prices, <int>[540, 630, 490, 525]);
      _expectRiverpodIdentity(
        tester,
        container: container,
        provider: provider,
        notifier: notifier,
        asyncNotifier: asyncNotifier,
      );

      expect(await tester.runAsync(patches.rollback), isTrue);
      await tester.pump();

      // Rollback has the same honest cache boundary. The next ordinary input
      // update recomputes against the restored base function.
      expect(find.text('riverpod price: 525'), findsOneWidget);
      expect(find.text('riverpod async price: 525'), findsOneWidget);
      await tester.tap(find.byKey(const Key('riverpod-increment')));
      expect(await _awaitWidgetAsyncPrice(tester, container), 720);
      expect(find.text('riverpod quantity: 8'), findsOneWidget);
      expect(find.text('riverpod price: 720'), findsOneWidget);
      expect(find.text('riverpod async price: 720'), findsOneWidget);
      expect(prices, <int>[540, 630, 490, 525, 720]);
      expect(
        asyncStates.whereType<AsyncData<int>>().map((state) => state.value),
        <int>[540, 630, 490, 525, 720],
      );
      _expectRiverpodIdentity(
        tester,
        container: container,
        provider: provider,
        notifier: notifier,
        asyncNotifier: asyncNotifier,
      );
      expect(notifier.state.quantity, 8);
      expect(notifier.state.tier, 1);
    },
  );

  test('explicit invalidation is an available host integration option', () {
    final container = ProviderContainer(
      overrides: [
        priceCalculatorProvider.overrideWithValue(
          _generatedGuardEquivalentPriceCalculator,
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(pricingInputProvider.notifier);

    expect(container.read(quotedPriceProvider), 540);
    notifier.incrementQuantity();
    expect(container.read(quotedPriceProvider), 630);

    final transformation = _priceTransformation();
    final bytes = E0PatchCompiler().compile(
      source: File('test/fixtures/mounted_price_patch.dart').readAsStringSync(),
      manifest: transformation.manifest,
      functionName: 'calculatePrice',
      patchSequence: 1,
    );
    expect(
      E0PatchRuntime.installBytes(
        bytes,
        appId: transformation.manifest.appId,
        releaseId: transformation.manifest.releaseId,
        buildFingerprint: transformation.manifest.buildFingerprint,
        functions: <String, int>{
          for (final function in transformation.manifest.functions)
            function.id: function.slot,
        },
        signatures: <String, String>{
          for (final function in transformation.manifest.functions)
            function.id: function.signature.encode(),
        },
        receivers: <String, String>{
          for (final function in transformation.manifest.functions)
            function.id: function.receiver.encode(),
        },
      ),
      isTrue,
      reason: E0PatchRuntime.lastRejection,
    );

    expect(container.read(quotedPriceProvider), 630);
    container.invalidate(quotedPriceProvider);
    expect(container.read(quotedPriceProvider), 525);
    expect(container.read(pricingInputProvider.notifier), same(notifier));
    expect(notifier.state.quantity, 7);
  });

  test('AsyncNotifier keeps identity and subscription through guarded recomputation', () async {
    final container = ProviderContainer(
      overrides: [
        priceCalculatorProvider.overrideWithValue(
          _generatedGuardEquivalentPriceCalculator,
        ),
      ],
    );
    addTearDown(container.dispose);
    final inputNotifier = container.read(pricingInputProvider.notifier);
    final asyncNotifier = container.read(asyncQuotedPriceProvider.notifier);
    final states = <AsyncValue<int>>[];
    final subscription = container.listen<AsyncValue<int>>(
      asyncQuotedPriceProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    expect(states.single, isA<AsyncLoading<int>>());
    expect(await _awaitAsyncPrice(container), 540);

    final signed = await _signedPricePatch(1);
    expect(await patches.activateBytes(signed), isTrue);
    expect(patches.status.phase, 'pendingHealth');
    expect(container.read(asyncQuotedPriceProvider).requireValue, 540);

    inputNotifier.incrementQuantity();
    expect(container.read(asyncQuotedPriceProvider), isA<AsyncLoading<int>>());
    expect(await _awaitAsyncPrice(container), 525);
    expect(
      container.read(asyncQuotedPriceProvider.notifier),
      same(asyncNotifier),
    );
    expect(states.whereType<AsyncLoading<int>>(), hasLength(2));
    expect(
      states.whereType<AsyncData<int>>().map((state) => state.value),
      <int>[540, 525],
    );
    expect(await patches.markHealthy(), isTrue);
    expect(patches.status.phase, 'healthy');

    expect(await patches.rollback(), isTrue);
    expect(container.read(asyncQuotedPriceProvider).requireValue, 525);
    inputNotifier.toggleTier();
    expect(container.read(asyncQuotedPriceProvider), isA<AsyncLoading<int>>());
    expect(await _awaitAsyncPrice(container), 560);
    expect(
      container.read(asyncQuotedPriceProvider.notifier),
      same(asyncNotifier),
    );
    expect(states.whereType<AsyncLoading<int>>(), hasLength(3));
    expect(
      states.whereType<AsyncData<int>>().map((state) => state.value),
      <int>[540, 525, 560],
    );
  });

  test(
    'AsyncNotifier recovers from host Future failure on ordinary input change',
    () async {
      final hostWait = _FailOnceHostWait();
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [pricingHostWaitProvider.overrideWithValue(hostWait.call)],
      );
      addTearDown(container.dispose);
      final inputNotifier = container.read(pricingInputProvider.notifier);
      final asyncNotifier = container.read(asyncQuotedPriceProvider.notifier);
      final states = <AsyncValue<int>>[];
      final subscription = container.listen<AsyncValue<int>>(
        asyncQuotedPriceProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      expect(states.single, isA<AsyncLoading<int>>());
      final failure = await _awaitAsyncTerminal(container);
      expect(failure, isA<AsyncError<int>>());
      final error = (failure as AsyncError<int>).error;
      expect(error, isA<StateError>());
      expect(error.toString(), contains('host pricing unavailable'));
      expect(hostWait.callCount, 1);
      expect(
        container.read(asyncQuotedPriceProvider.notifier),
        same(asyncNotifier),
      );

      inputNotifier.incrementQuantity();
      expect(
        container.read(asyncQuotedPriceProvider),
        isA<AsyncLoading<int>>(),
      );
      expect(await _awaitAsyncPrice(container), 630);
      expect(hostWait.callCount, 2);
      expect(
        container.read(asyncQuotedPriceProvider.notifier),
        same(asyncNotifier),
      );
      expect(states.whereType<AsyncLoading<int>>(), hasLength(2));
      expect(states.whereType<AsyncError<int>>(), hasLength(1));
      expect(
        states.whereType<AsyncData<int>>().map((state) => state.value),
        <int>[630],
      );
    },
  );
}

final class _FailOnceHostWait {
  int callCount = 0;

  Future<void> call() async {
    callCount++;
    await Future<void>.delayed(Duration.zero);
    if (callCount == 1) throw StateError('host pricing unavailable');
  }
}

Widget _guardedRiverpodApp() => ProviderScope(
  overrides: [
    priceCalculatorProvider.overrideWithValue(
      _generatedGuardEquivalentPriceCalculator,
    ),
  ],
  child: const MaterialApp(home: Scaffold(body: RiverpodPricingPanel())),
);

int _generatedGuardEquivalentPriceCalculator(int quantity, int tier) {
  final patch = E0PatchRuntime.lookup(e1CalculatePriceSlot);
  if (patch != null) {
    final patched = E0PatchRuntime.invokeInt2(patch, quantity, tier);
    if (patched != null) return patched;
  }
  return calculatePrice(quantity, tier);
}

void _expectRiverpodIdentity(
  WidgetTester tester, {
  required ProviderContainer container,
  required Provider<int> provider,
  required PricingInputNotifier notifier,
  required AsyncPricingNotifier asyncNotifier,
}) {
  final currentContext = tester.element(find.byType(RiverpodPricingPanel));
  expect(
    ProviderScope.containerOf(currentContext, listen: false),
    same(container),
  );
  expect(quotedPriceProvider, same(provider));
  expect(container.read(pricingInputProvider.notifier), same(notifier));
  expect(
    container.read(asyncQuotedPriceProvider.notifier),
    same(asyncNotifier),
  );
}

Future<int> _awaitWidgetAsyncPrice(
  WidgetTester tester,
  ProviderContainer container,
) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    await tester.pump(const Duration(milliseconds: 1));
    final state = container.read(asyncQuotedPriceProvider);
    if (state case AsyncData<int>(:final value)) return value;
  }
  return container.read(asyncQuotedPriceProvider).requireValue;
}

Future<int> _awaitAsyncPrice(ProviderContainer container) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    final state = container.read(asyncQuotedPriceProvider);
    if (state case AsyncData<int>(:final value)) return value;
  }
  return container.read(asyncQuotedPriceProvider).requireValue;
}

Future<AsyncValue<int>> _awaitAsyncTerminal(ProviderContainer container) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    final state = container.read(asyncQuotedPriceProvider);
    if (state is! AsyncLoading<int>) return state;
  }
  return container.read(asyncQuotedPriceProvider);
}

Future<List<int>> _signedPricePatch(int sequence) async {
  final transformation = _priceTransformation();
  final bytes = E0PatchCompiler().compile(
    source: File('test/fixtures/mounted_price_patch.dart').readAsStringSync(),
    manifest: transformation.manifest,
    functionName: 'calculatePrice',
    patchSequence: sequence,
  );
  return E1SignedPatchEnvelope.sign(
    patchBytes: bytes,
    keyId: e1SigningKeyId,
    privateKeySeed: _e1TestSigningSeed,
  );
}

E0TransformResult _priceTransformation() => E0SourceTransformer().transform(
  source: File('lib/main.dart').readAsStringSync(),
  packageName: 'conformance',
  logicalLibraryPath: 'lib/main.dart',
  appId: e1AppId,
  releaseId: e1ReleaseId,
  buildFingerprint: e1BuildFingerprint,
);

const List<int> _e1TestSigningSeed = <int>[
  0x9d,
  0x61,
  0xb1,
  0x9d,
  0xef,
  0xfd,
  0x5a,
  0x60,
  0xba,
  0x84,
  0x4a,
  0xf4,
  0x92,
  0xec,
  0x2c,
  0xc4,
  0x44,
  0x49,
  0xc5,
  0x69,
  0x7b,
  0x32,
  0x69,
  0x19,
  0x70,
  0x3b,
  0xac,
  0x03,
  0x1c,
  0xae,
  0x7f,
  0x60,
];
