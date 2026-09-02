import 'dart:io';

import 'package:conformance/main.dart';
import 'package:conformance/patch_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';

import 'package:conformance/widget_factories.dart';

void main() {
  late Directory storage;
  late E1PatchController patches;

  setUp(() async {
    E0PatchRuntime.reset();
    storage = await Directory.systemTemp.createTemp('hyfens-e1-widget-');
    patches = createPatchController(storage);
    await patches.initialize();
  });

  tearDown(() async {
    await patches.close();
    E0PatchRuntime.reset();
    await storage.delete(recursive: true);
  });

  testWidgets(
    'bounded factories materialize real Flutter hierarchy and style',
    (tester) async {
      final registry = createConformanceWidgetRegistry();
      final widget = registry.materialize(<String, Object?>{
        'factory': 'flutter.column.v1',
        'properties': <String, Object?>{'mainAxisSize': 'min'},
        'children': <Object?>[
          <String, Object?>{
            'factory': 'flutter.text.v1',
            'properties': <String, Object?>{
              'data': 'PATCH Pro',
              'fontSize': 24.0,
            },
            'children': <Object?>[],
          },
          <String, Object?>{
            'factory': 'flutter.text.v1',
            'properties': <String, Object?>{'data': 'conditional hierarchy'},
            'children': <Object?>[],
          },
          <String, Object?>{
            'factory': 'flutter.elevated-button.v1',
            'properties': <String, Object?>{},
            'children': <Object?>[
              <String, Object?>{
                'factory': 'flutter.text.v1',
                'properties': <String, Object?>{'data': 'Upgrade'},
                'children': <Object?>[],
              },
            ],
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: widget as Widget)),
      );

      expect(find.text('PATCH Pro'), findsOneWidget);
      expect(find.text('conditional hierarchy'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Upgrade'), findsOneWidget);
      expect(tester.widget<Text>(find.text('PATCH Pro')).style?.fontSize, 24.0);
      expect(
        tester.widget<Column>(find.byType(Column)).mainAxisSize,
        MainAxisSize.min,
      );
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
    },
  );

  test('ordinary source generates the production calculatePrice guard', () {
    final checkedIn = File('lib/main.dart').readAsStringSync();
    final transformation = _priceTransformation(checkedIn);
    final calculatePriceFunction = transformation.manifest.functions
        .singleWhere((function) => function.name == 'calculatePrice');

    expect(checkedIn, isNot(contains('E0PatchRuntime.lookup')));
    expect(
      transformation.manifest.functions.map((function) => function.name),
      <String>['calculateAsyncPrice', 'calculatePrice'],
      reason: 'ordinary async and synchronous application functions are both instrumented',
    );
    expect(calculatePriceFunction.slot, e1CalculatePriceSlot);
    expect(
      transformation.source,
      contains('E0PatchRuntime.lookup($e1CalculatePriceSlot);'),
    );
    expect(
      calculatePriceFunction.id,
      e1CalculatePriceId,
      reason: 'the release-owned E1 compatibility table must match the overlay',
    );
  });

  testWidgets(
    'ordinary PricingCard build compiles and invokes real factories',
    (tester) async {
      final source = File('lib/main.dart').readAsStringSync();
      final transformation = E0SourceTransformer().transform(
        source: source,
        packageName: 'conformance',
        logicalLibraryPath: 'lib/main.dart',
        appId: 'widget-conformance',
        releaseId: 'release-1',
        buildFingerprint: 'widget-conformance-1',
        widgetFactories: conformanceWidgetFactories,
        widgetBuildClasses: const <String>{'PricingCard'},
      );
      final build = transformation.manifest.functions.singleWhere(
        (function) =>
            function.name == 'build' &&
            function.receiver.ownerClass == 'PricingCard',
      );
      final bytes = E0PatchCompiler().compile(
        source: File('test/fixtures/pricing_card_patch.dart')
            .readAsStringSync(),
        manifest: transformation.manifest,
        className: 'PricingCard',
        functionName: 'build',
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
      final result = E0PatchRuntime.invokeWidget(
        E0PatchRuntime.lookup(build.slot)!,
        const <Object?>[],
        receiver: _PricingCardReceiver(build.receiver),
      );
      expect(result.isSuccess, isTrue);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: result.value! as Widget)),
      );

      expect(transformation.source, contains('E0PatchRuntime.invokeWidget'));
      expect(find.text('PATCH Pro'), findsOneWidget);
      expect(find.text('conditional hierarchy'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Upgrade'), findsOneWidget);
      expect(tester.widget<Text>(find.text('PATCH Pro')).style?.fontSize, 24.0);
    },
  );

  testWidgets('ordinary function drives meaningful branches and state', (
    tester,
  ) async {
    await tester.pumpWidget(ConformanceApp(patches: patches));

    expect(find.text('BASE AOT'), findsOneWidget);
    expect(find.text('quantity: 6'), findsOneWidget);
    expect(find.text('price: 540'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tier')));
    await tester.pump();
    expect(find.text('tier: 2'), findsOneWidget);
    expect(find.text('price: 480'), findsOneWidget);

    await tester.tap(find.byKey(const Key('increment')));
    await tester.pump();
    expect(find.text('quantity: 7'), findsOneWidget);
    expect(find.text('price: 560'), findsOneWidget);
  });

  testWidgets('invalid activation status preserves screen state', (
    tester,
  ) async {
    await tester.pumpWidget(ConformanceApp(patches: patches));
    await tester.tap(find.byKey(const Key('increment')));
    await tester.pump();

    // Patch verification and durable activation use real asynchronous I/O.
    // Keep that work outside WidgetTester's fake-async clock.
    await tester.runAsync(() => patches.activateBytes(<int>[1, 2, 3]));
    await tester.pump();

    expect(find.text('quantity: 7'), findsOneWidget);
    expect(find.text('price: 630'), findsOneWidget);
    expect(patches.status.phase, 'rejected');
    expect(patches.status.mode, E1PatchMode.base);
  });

  testWidgets(
    'patch activated before construction drives initial State build',
    (tester) async {
      final signed = await _signedPricePatch(1);
      expect(
        await tester.runAsync(() => patches.activateBytes(signed)),
        isTrue,
      );
      expect(patches.status.phase, 'pendingHealth');
      final lifecycle = PriceScreenLifecycle();

      await tester.pumpWidget(
        ConformanceApp(
          patches: patches,
          lifecycle: lifecycle,
          priceCalculator: _generatedGuardEquivalentPriceCalculator,
        ),
      );

      expect(find.text('price: 450'), findsOneWidget);
      expect(lifecycle.initStateCount, 1);
      expect(lifecycle.disposeCount, 0);
      expect(lifecycle.currentState, isNotNull);
      expect(await tester.runAsync(patches.markHealthy), isTrue);
      await tester.pump();
      expect(patches.status.phase, 'healthy');
    },
  );

  testWidgets(
    'mounted patch, rejection, and rollback preserve State; tree remount does not',
    (tester) async {
      final lifecycle = PriceScreenLifecycle();
      await tester.pumpWidget(
        ConformanceApp(
          patches: patches,
          lifecycle: lifecycle,
          priceCalculator: _generatedGuardEquivalentPriceCalculator,
        ),
      );
      await tester.tap(find.byKey(const Key('increment')));
      await tester.enterText(
        find.byKey(const Key('draft-input')),
        'mounted draft',
      );
      await tester.pump();

      final state = lifecycle.currentState!;
      state.noteController.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 9,
      );
      state.scrollController.jumpTo(86.0);
      await tester.pump();
      final textController = state.noteController;
      final scrollController = state.scrollController;
      final screenElement = tester.element(
        find.byKey(const Key('price-screen')),
      );
      final selection = state.noteController.selection;
      final buildsBeforePatch = lifecycle.buildCount;

      final signed = await _signedPricePatch(1);
      expect(
        await tester.runAsync(() => patches.activateBytes(signed)),
        isTrue,
      );
      await tester.pump();

      expect(patches.status.phase, 'pendingHealth');
      expect(find.text('price: 525'), findsOneWidget);
      expect(lifecycle.buildCount, greaterThan(buildsBeforePatch));
      _expectMountedContinuity(
        tester,
        lifecycle: lifecycle,
        state: state,
        screenElement: screenElement,
        textController: textController,
        scrollController: scrollController,
        selection: selection,
      );
      expect(await tester.runAsync(patches.markHealthy), isTrue);
      await tester.pump();
      expect(patches.status.phase, 'healthy');
      _expectMountedContinuity(
        tester,
        lifecycle: lifecycle,
        state: state,
        screenElement: screenElement,
        textController: textController,
        scrollController: scrollController,
        selection: selection,
      );

      expect(
        await tester.runAsync(() => patches.activateBytes(<int>[1, 2, 3])),
        isFalse,
      );
      await tester.pump();
      expect(patches.status.phase, 'rejected');
      expect(patches.status.mode, E1PatchMode.patch);
      expect(find.text('price: 525'), findsOneWidget);
      _expectMountedContinuity(
        tester,
        lifecycle: lifecycle,
        state: state,
        screenElement: screenElement,
        textController: textController,
        scrollController: scrollController,
        selection: selection,
      );

      expect(await tester.runAsync(patches.rollback), isTrue);
      await tester.pump();
      expect(find.text('price: 630'), findsOneWidget);
      expect(E0PatchRuntime.lookup(e1CalculatePriceSlot), isNull);
      _expectMountedContinuity(
        tester,
        lifecycle: lifecycle,
        state: state,
        screenElement: screenElement,
        textController: textController,
        scrollController: scrollController,
        selection: selection,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(lifecycle.disposeCount, 1);
      expect(lifecycle.currentState, isNull);

      await tester.pumpWidget(
        ConformanceApp(
          patches: patches,
          lifecycle: lifecycle,
          priceCalculator: _generatedGuardEquivalentPriceCalculator,
        ),
      );
      final restartedState = lifecycle.currentState!;
      expect(lifecycle.initStateCount, 2);
      expect(restartedState, isNot(same(state)));
      expect(restartedState.noteController, isNot(same(textController)));
      expect(restartedState.scrollController, isNot(same(scrollController)));
      expect(find.text('quantity: 6'), findsOneWidget);
      expect(find.text('price: 540'), findsOneWidget);
    },
  );
}

void _expectMountedContinuity(
  WidgetTester tester, {
  required PriceScreenLifecycle lifecycle,
  required PriceScreenState state,
  required Element screenElement,
  required TextEditingController textController,
  required ScrollController scrollController,
  required TextSelection selection,
}) {
  expect(lifecycle.initStateCount, 1);
  expect(lifecycle.disposeCount, 0);
  expect(lifecycle.currentState, same(state));
  expect(
    tester.element(find.byKey(const Key('price-screen'))),
    same(screenElement),
  );
  expect(state.noteController, same(textController));
  expect(state.noteController.text, 'mounted draft');
  expect(state.noteController.selection, selection);
  expect(state.scrollController, same(scrollController));
  expect(state.scrollController.offset, 86.0);
}

/// Widget tests cannot dynamically load the generated overlay library. This is
/// the generated calculatePrice guard's exact runtime branch; the separate
/// overlay test above proves that ordinary production source receives it.
int _generatedGuardEquivalentPriceCalculator(int quantity, int tier) {
  final patch = E0PatchRuntime.lookup(e1CalculatePriceSlot);
  if (patch != null) {
    final patched = E0PatchRuntime.invokeInt2(patch, quantity, tier);
    if (patched != null) return patched;
  }
  return calculatePrice(quantity, tier);
}

Future<List<int>> _signedPricePatch(int sequence) async {
  final transformation = _priceTransformation(
    File('lib/main.dart').readAsStringSync(),
  );
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

E0TransformResult _priceTransformation(String source) =>
    E0SourceTransformer().transform(
      source: source,
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

final class _PricingCardReceiver implements E0ReceiverCapability {
  const _PricingCardReceiver(this.descriptor);

  final E0ReceiverDescriptor descriptor;

  @override
  String get descriptorId => descriptor.id;

  @override
  Object? read(int slot) => switch (descriptor.members[slot].name) {
    'featured' => true,
    'plan' => 'Pro',
    final name => throw StateError('Unexpected receiver member $name'),
  };
}
