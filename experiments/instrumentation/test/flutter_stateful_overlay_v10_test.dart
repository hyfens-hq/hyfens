import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  test('transformed app preserves mounted Flutter State through signed E1 lifecycle', () async {
    final fixture = Directory('../../fixtures/flutter_conformance_app')
        .absolute;
    final ecosystemPackageLibs = <String, Directory>{
      for (final package in <String>[
        'bloc',
        'flutter_bloc',
        'flutter_riverpod',
        'riverpod',
      ])
        package: _packageLibDirectory(fixture, package),
    };
    final ecosystemPackageDigests = <String, Digest>{
      for (final entry in ecosystemPackageLibs.entries)
        entry.key: _directoryDigest(entry.value),
    };
    final sourceFile = File('${fixture.path}/lib/main.dart');
    final source = sourceFile.readAsStringSync();
    final scratch = await fixture.createTemp('.dart_tool/stateful-overlay-');
    addTearDown(() => scratch.delete(recursive: true));

    final transformation = E0SourceTransformer().transform(
      source: source,
      packageName: 'conformance',
      logicalLibraryPath: 'lib/main.dart',
      appId: 'dev.hyfens.conformance',
      releaseId: 'android-e1-release-1',
      buildFingerprint: 'conformance-build-1',
    );
    expect(sourceFile.readAsStringSync(), source);
    final calculatePrice = transformation.manifest.functions.singleWhere(
      (function) => function.name == 'calculatePrice',
    );
    expect(calculatePrice.slot, 1);
    expect(transformation.source, contains('E0PatchRuntime.lookup(1);'));

    final patchBytes = E0PatchCompiler().compile(
      source: File('${fixture.path}/test/fixtures/mounted_price_patch.dart')
          .readAsStringSync(),
      manifest: transformation.manifest,
      functionName: 'calculatePrice',
      patchSequence: 1,
    );
    File('${scratch.path}/app.dart').writeAsStringSync(transformation.source);
    File('${fixture.path}/lib/patch_bootstrap.dart')
        .copySync('${scratch.path}/patch_bootstrap.dart');
    File('${fixture.path}/lib/widget_factories.dart')
        .copySync('${scratch.path}/widget_factories.dart');
    final patchFile = File('${scratch.path}/mounted-price.e0.json')
      ..writeAsBytesSync(patchBytes);
    final generatedTest = File('${scratch.path}/stateful_overlay_test.dart')
      ..writeAsStringSync(_generatedFlutterTest(patchPath: patchFile.path));

    final result = await Process.run('flutter', <String>[
      'test',
      generatedTest.path,
    ], workingDirectory: fixture.path);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('All tests passed'));
    for (final entry in ecosystemPackageLibs.entries) {
      expect(
        _directoryDigest(entry.value),
        ecosystemPackageDigests[entry.key],
        reason:
            'the overlay must not rewrite the resolved ${entry.key} lib Dart files',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Directory _packageLibDirectory(Directory package, String dependency) {
  final packageConfig = File('${package.path}/.dart_tool/package_config.json');
  final json =
      jsonDecode(packageConfig.readAsStringSync()) as Map<String, Object?>;
  final packages = (json['packages']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final entry = packages.singleWhere((item) => item['name'] == dependency);
  final root = packageConfig.uri.resolve(entry['rootUri']! as String);
  return Directory('${root.toFilePath()}/lib');
}

Digest _directoryDigest(Directory directory) {
  final files =
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  return sha256.convert(
    utf8.encode(
      files
          .map(
            (file) =>
                '${file.path.substring(directory.path.length)}:'
                '${sha256.convert(file.readAsBytesSync())}',
          )
          .join('|'),
    ),
  );
}

String _generatedFlutterTest({required String patchPath}) =>
    '''
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';

import 'app.dart' as app;
import 'patch_bootstrap.dart';

void main() {
  late Directory storage;
  late E1PatchController patches;

  setUp(() async {
    E0PatchRuntime.reset();
    storage = await Directory.systemTemp.createTemp('hyfens-stateful-overlay-');
    patches = createPatchController(storage);
    await patches.initialize();
  });

  tearDown(() async {
    await patches.close();
    E0PatchRuntime.reset();
    await storage.delete(recursive: true);
  });

  testWidgets('real generated guard is active before State construction', (tester) async {
    final signed = await _signedPatch();
    expect(
      await tester.runAsync(() => patches.activateBytes(signed)),
      isTrue,
    );
    expect(patches.status.phase, 'pendingHealth');
    final lifecycle = app.PriceScreenLifecycle();

    await tester.pumpWidget(app.ConformanceApp(patches: patches, lifecycle: lifecycle));

    expect(find.text('price: 450'), findsOneWidget);
    expect(lifecycle.initStateCount, 1);
    expect(lifecycle.disposeCount, 0);
    expect(await tester.runAsync(patches.markHealthy), isTrue);
    await tester.pump();
    expect(patches.status.phase, 'healthy');
  });

  testWidgets('real generated guard preserves mounted State through activate reject rollback', (tester) async {
    final lifecycle = app.PriceScreenLifecycle();
    await tester.pumpWidget(app.ConformanceApp(patches: patches, lifecycle: lifecycle));
    await tester.tap(find.byKey(const Key('increment')));
    await tester.enterText(find.byKey(const Key('draft-input')), 'overlay draft');
    await tester.pump();

    final state = lifecycle.currentState!;
    state.noteController.selection = const TextSelection(baseOffset: 1, extentOffset: 8);
    state.scrollController.jumpTo(73.0);
    await tester.pump();
    final textController = state.noteController;
    final scrollController = state.scrollController;
    final screenElement = tester.element(find.byKey(const Key('price-screen')));
    final selection = textController.selection;

    final signed = await _signedPatch();
    expect(
      await tester.runAsync(() => patches.activateBytes(signed)),
      isTrue,
    );
    await tester.pump();
    expect(patches.status.phase, 'pendingHealth');
    expect(find.text('price: 525'), findsOneWidget);
    _expectContinuity(
      tester,
      lifecycle,
      state,
      screenElement,
      textController,
      scrollController,
      selection,
    );
    expect(await tester.runAsync(patches.markHealthy), isTrue);
    await tester.pump();
    expect(patches.status.phase, 'healthy');
    _expectContinuity(
      tester,
      lifecycle,
      state,
      screenElement,
      textController,
      scrollController,
      selection,
    );

    expect(
      await tester.runAsync(() => patches.activateBytes(<int>[1, 2, 3])),
      isFalse,
    );
    await tester.pump();
    expect(find.text('price: 525'), findsOneWidget);
    expect(patches.status.mode, E1PatchMode.patch);
    _expectContinuity(
      tester,
      lifecycle,
      state,
      screenElement,
      textController,
      scrollController,
      selection,
    );

    expect(await tester.runAsync(patches.rollback), isTrue);
    await tester.pump();
    expect(find.text('price: 630'), findsOneWidget);
    expect(E0PatchRuntime.lookup(e1CalculatePriceSlot), isNull);
    _expectContinuity(
      tester,
      lifecycle,
      state,
      screenElement,
      textController,
      scrollController,
      selection,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(lifecycle.disposeCount, 1);
    await tester.pumpWidget(app.ConformanceApp(patches: patches, lifecycle: lifecycle));
    expect(lifecycle.initStateCount, 2);
    expect(lifecycle.currentState, isNot(same(state)));
    expect(lifecycle.currentState!.noteController, isNot(same(textController)));
    expect(lifecycle.currentState!.scrollController, isNot(same(scrollController)));
    expect(find.text('quantity: 6'), findsOneWidget);
    expect(find.text('price: 540'), findsOneWidget);
  });

  testWidgets('real generated guard interoperates with an existing Riverpod graph', (tester) async {
    await tester.pumpWidget(const app.RiverpodPricingApp());
    final context = tester.element(find.byType(app.RiverpodPricingPanel));
    final container = ProviderScope.containerOf(context, listen: false);
    final provider = app.quotedPriceProvider;
    final notifier = container.read(app.pricingInputProvider.notifier);
    final asyncNotifier = container.read(app.asyncQuotedPriceProvider.notifier);
    final prices = <int>[];
    final asyncStates = <AsyncValue<int>>[];
    final subscription = container.listen<int>(
      provider,
      (_, next) => prices.add(next),
      fireImmediately: true,
    );
    final asyncSubscription = container.listen<AsyncValue<int>>(
      app.asyncQuotedPriceProvider,
      (_, next) => asyncStates.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(asyncSubscription.close);

    expect(asyncStates.single, isA<AsyncLoading<int>>());
    expect(await _pumpAsyncPrice(tester, container), 540);
    expect(find.text('riverpod price: 540'), findsOneWidget);
    expect(find.text('riverpod async price: 540'), findsOneWidget);

    await tester.tap(find.byKey(const Key('riverpod-increment')));
    expect(
      container.read(app.asyncQuotedPriceProvider),
      isA<AsyncLoading<int>>(),
    );
    expect(await _pumpAsyncPrice(tester, container), 630);
    expect(find.text('riverpod price: 630'), findsOneWidget);
    expect(find.text('riverpod async price: 630'), findsOneWidget);
    expect(prices, <int>[540, 630]);

    final signed = await _signedPatch();
    expect(
      await tester.runAsync(() => patches.activateBytes(signed)),
      isTrue,
    );
    await tester.pump();
    expect(patches.status.phase, 'pendingHealth');

    // Activation is not a Riverpod dependency. Both already-cached values
    // remain stale until the ordinary application graph recomputes.
    expect(container.read(provider), 630);
    expect(container.read(app.asyncQuotedPriceProvider).requireValue, 630);
    expect(find.text('riverpod price: 630'), findsOneWidget);
    expect(find.text('riverpod async price: 630'), findsOneWidget);

    await tester.tap(find.byKey(const Key('riverpod-tier-toggle')));
    expect(
      container.read(app.asyncQuotedPriceProvider),
      isA<AsyncLoading<int>>(),
    );
    expect(await _pumpAsyncPrice(tester, container), 490);
    expect(find.text('riverpod price: 490'), findsOneWidget);
    expect(find.text('riverpod async price: 490'), findsOneWidget);
    expect(prices, <int>[540, 630, 490]);
    _expectRiverpodIdentity(
      tester,
      container,
      provider,
      notifier,
      asyncNotifier,
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
    await tester.tap(find.byKey(const Key('riverpod-tier-toggle')));
    expect(await _pumpAsyncPrice(tester, container), 525);
    expect(find.text('riverpod price: 525'), findsOneWidget);
    expect(find.text('riverpod async price: 525'), findsOneWidget);
    expect(prices, <int>[540, 630, 490, 525]);
    _expectRiverpodIdentity(
      tester,
      container,
      provider,
      notifier,
      asyncNotifier,
    );

    expect(await tester.runAsync(patches.rollback), isTrue);
    await tester.pump();
    expect(find.text('riverpod price: 525'), findsOneWidget);
    expect(find.text('riverpod async price: 525'), findsOneWidget);
    expect(container.read(app.asyncQuotedPriceProvider).requireValue, 525);
    await tester.tap(find.byKey(const Key('riverpod-increment')));
    expect(await _pumpAsyncPrice(tester, container), 720);
    expect(find.text('riverpod price: 720'), findsOneWidget);
    expect(find.text('riverpod async price: 720'), findsOneWidget);
    expect(prices, <int>[540, 630, 490, 525, 720]);
    expect(
      asyncStates.whereType<AsyncData<int>>().map((state) => state.value),
      <int>[540, 630, 490, 525, 720],
    );
    _expectRiverpodIdentity(
      tester,
      container,
      provider,
      notifier,
      asyncNotifier,
    );
  });

  testWidgets('real generated guard preserves an existing Cubit stream and BlocBuilder', (tester) async {
    final cubit = app.BlocPricingCubit();
    final lifecycle = app.BlocPricingLifecycle();
    final states = <app.BlocPricingState>[];
    final subscription = cubit.stream.listen(states.add);
    addTearDown(subscription.cancel);
    addTearDown(cubit.close);

    await tester.pumpWidget(
      app.BlocPricingApp(cubit: cubit, lifecycle: lifecycle),
    );
    final panelElement = tester.element(find.byType(app.BlocPricingPanel));

    expect(cubit.state.quantity, 6);
    expect(cubit.state.tier, 1);
    expect(cubit.state.price, 540);
    expect(find.text('bloc price: 540'), findsOneWidget);
    expect(lifecycle.buildCount, 1);

    await tester.tap(find.byKey(const Key('bloc-increment')));
    await tester.pump();
    expect(cubit.state.quantity, 7);
    expect(cubit.state.price, 630);
    expect(states.map((state) => state.price), <int>[630]);
    expect(find.text('bloc price: 630'), findsOneWidget);
    expect(lifecycle.buildCount, 2);

    final signed = await _signedPatch();
    expect(
      await tester.runAsync(() => patches.activateBytes(signed)),
      isTrue,
    );
    await tester.pump();
    expect(patches.status.phase, 'pendingHealth');

    // Patch activation is not a Cubit input and does not emit or rebuild.
    expect(cubit.state.price, 630);
    expect(states.map((state) => state.price), <int>[630]);
    expect(find.text('bloc price: 630'), findsOneWidget);
    expect(lifecycle.buildCount, 2);
    _expectBlocIdentity(tester, cubit, panelElement);

    await tester.tap(find.byKey(const Key('bloc-tier-toggle')));
    await tester.pump();
    expect(cubit.state.quantity, 7);
    expect(cubit.state.tier, 2);
    expect(cubit.state.price, 490);
    expect(states.map((state) => state.price), <int>[630, 490]);
    expect(find.text('bloc price: 490'), findsOneWidget);
    expect(lifecycle.buildCount, 3);
    _expectBlocIdentity(tester, cubit, panelElement);

    expect(await tester.runAsync(patches.markHealthy), isTrue);
    await tester.pump();
    expect(patches.status.phase, 'healthy');
    expect(states.map((state) => state.price), <int>[630, 490]);
    expect(lifecycle.buildCount, 3);

    expect(
      await tester.runAsync(() => patches.activateBytes(<int>[1, 2, 3])),
      isFalse,
    );
    await tester.pump();
    expect(patches.status.phase, 'rejected');
    expect(patches.status.mode, E1PatchMode.patch);
    expect(cubit.state.price, 490);
    expect(states.map((state) => state.price), <int>[630, 490]);
    expect(lifecycle.buildCount, 3);
    _expectBlocIdentity(tester, cubit, panelElement);

    await tester.tap(find.byKey(const Key('bloc-increment')));
    await tester.pump();
    expect(cubit.state.quantity, 8);
    expect(cubit.state.price, 560);
    expect(states.map((state) => state.price), <int>[630, 490, 560]);
    expect(find.text('bloc price: 560'), findsOneWidget);
    expect(lifecycle.buildCount, 4);

    expect(await tester.runAsync(patches.rollback), isTrue);
    await tester.pump();
    expect(E0PatchRuntime.lookup(e1CalculatePriceSlot), isNull);

    // Rollback likewise has no Cubit emission. The next ordinary input invokes
    // the restored app-owned function while retaining the current state.
    expect(cubit.state.quantity, 8);
    expect(cubit.state.tier, 2);
    expect(cubit.state.price, 560);
    expect(states.map((state) => state.price), <int>[630, 490, 560]);
    expect(lifecycle.buildCount, 4);
    _expectBlocIdentity(tester, cubit, panelElement);

    await tester.tap(find.byKey(const Key('bloc-tier-toggle')));
    await tester.pump();
    expect(cubit.state.quantity, 8);
    expect(cubit.state.tier, 1);
    expect(cubit.state.price, 720);
    expect(
      states.map((state) => state.price),
      <int>[630, 490, 560, 720],
    );
    expect(find.text('bloc price: 720'), findsOneWidget);
    expect(lifecycle.buildCount, 5);
    _expectBlocIdentity(tester, cubit, panelElement);
  });
}

Future<int> _pumpAsyncPrice(
  WidgetTester tester,
  ProviderContainer container,
) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    await tester.pump(const Duration(milliseconds: 1));
    final state = container.read(app.asyncQuotedPriceProvider);
    if (state case AsyncData<int>(:final value)) return value;
  }
  return container.read(app.asyncQuotedPriceProvider).requireValue;
}

void _expectRiverpodIdentity(
  WidgetTester tester,
  ProviderContainer container,
  Provider<int> provider,
  app.PricingInputNotifier notifier,
  app.AsyncPricingNotifier asyncNotifier,
) {
  final context = tester.element(find.byType(app.RiverpodPricingPanel));
  expect(ProviderScope.containerOf(context, listen: false), same(container));
  expect(app.quotedPriceProvider, same(provider));
  expect(container.read(app.pricingInputProvider.notifier), same(notifier));
  expect(
    container.read(app.asyncQuotedPriceProvider.notifier),
    same(asyncNotifier),
  );
}

void _expectBlocIdentity(
  WidgetTester tester,
  app.BlocPricingCubit cubit,
  Element panelElement,
) {
  final context = tester.element(find.byType(app.BlocPricingPanel));
  expect(context, same(panelElement));
  expect(BlocProvider.of<app.BlocPricingCubit>(context), same(cubit));
  expect(cubit.isClosed, isFalse);
}

void _expectContinuity(
  WidgetTester tester,
  app.PriceScreenLifecycle lifecycle,
  app.PriceScreenState state,
  Element screenElement,
  TextEditingController textController,
  ScrollController scrollController,
  TextSelection selection,
) {
  expect(lifecycle.initStateCount, 1);
  expect(lifecycle.disposeCount, 0);
  expect(lifecycle.currentState, same(state));
  expect(tester.element(find.byKey(const Key('price-screen'))), same(screenElement));
  expect(state.noteController, same(textController));
  expect(state.noteController.text, 'overlay draft');
  expect(state.noteController.selection, selection);
  expect(state.scrollController, same(scrollController));
  expect(state.scrollController.offset, 73.0);
}

Future<List<int>> _signedPatch() async => E1SignedPatchEnvelope.sign(
  patchBytes: File(${jsonEncode(patchPath)}).readAsBytesSync(),
  keyId: e1SigningKeyId,
  privateKeySeed: _testSigningSeed,
);

const List<int> _testSigningSeed = <int>[
  0x9d, 0x61, 0xb1, 0x9d, 0xef, 0xfd, 0x5a, 0x60,
  0xba, 0x84, 0x4a, 0xf4, 0x92, 0xec, 0x2c, 0xc4,
  0x44, 0x49, 0xc5, 0x69, 0x7b, 0x32, 0x69, 0x19,
  0x70, 0x3b, 0xac, 0x03, 0x1c, 0xae, 0x7f, 0x60,
];
''';
