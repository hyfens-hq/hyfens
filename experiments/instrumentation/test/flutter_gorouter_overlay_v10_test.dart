import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  test(
    'transformed route decision interoperates with the installed GoRouter',
    () async {
      final fixture = Directory('../../fixtures/flutter_conformance_app')
          .absolute;
      final sourceFile = File('${fixture.path}/lib/navigation_fixture.dart');
      final source = sourceFile.readAsStringSync();
      final goRouterLib = _packageLibDirectory(fixture, 'go_router');
      final goRouterDigest = _directoryDigest(goRouterLib);
      final scratch = await fixture.createTemp('.dart_tool/gorouter-overlay-');
      addTearDown(() => scratch.delete(recursive: true));

      final transformation = E0SourceTransformer().transform(
        source: source,
        packageName: 'conformance',
        logicalLibraryPath: 'lib/navigation_fixture.dart',
        appId: 'dev.hyfens.navigation',
        releaseId: 'navigation-release-1',
        buildFingerprint: 'navigation-build-1',
      );
      expect(sourceFile.readAsStringSync(), source);
      final decision = transformation.manifest.functions.singleWhere(
        (function) => function.name == 'chooseDestination',
      );
      expect(decision.slot, 0);
      expect(transformation.source, contains('E0PatchRuntime.lookup(0);'));

      final patchBytes = E0PatchCompiler().compile(
        source: File('${fixture.path}/test/fixtures/navigation_patch.dart')
            .readAsStringSync(),
        manifest: transformation.manifest,
        functionName: 'chooseDestination',
        patchSequence: 1,
      );
      File('${scratch.path}/navigation_app.dart')
          .writeAsStringSync(transformation.source);
      final patchFile = File('${scratch.path}/navigation.e0.json')
        ..writeAsBytesSync(patchBytes);
      final generatedTest = File('${scratch.path}/navigation_overlay_test.dart')
        ..writeAsStringSync(
          _generatedFlutterTest(
            patchPath: patchFile.path,
            functionId: decision.id,
            signature: decision.signature.encode(),
            receiver: decision.receiver.encode(),
          ),
        );

      final result = await Process.run('flutter', <String>[
        'test',
        generatedTest.path,
      ], workingDirectory: fixture.path);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('All tests passed'));
      expect(
        _directoryDigest(goRouterLib),
        goRouterDigest,
        reason:
            'resolved go_router Dart library files must remain byte-identical',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
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

String _generatedFlutterTest({
  required String patchPath,
  required String functionId,
  required String signature,
  required String receiver,
}) =>
    '''
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';

import 'navigation_app.dart' as app;

void main() {
  late Directory storage;
  late E1PatchController patches;

  setUp(() async {
    E0PatchRuntime.reset();
    storage = await Directory.systemTemp.createTemp('hyfens-gorouter-overlay-');
    patches = _createController(storage);
    await patches.initialize();
  });

  tearDown(() async {
    await patches.close();
    E0PatchRuntime.reset();
    await storage.delete(recursive: true);
  });

  testWidgets(
    'ordinary navigation reevaluates a signed patched decision and rollback',
    (tester) async {
      final lifecycle = _RouteLifecycle();
      final router = _router(lifecycle);
      var routerNotifications = 0;
      void observeRouter() => routerNotifications++;
      router.routerDelegate.addListener(observeRouter);
      addTearDown(() {
        router.routerDelegate.removeListener(observeRouter);
        router.dispose();
      });
      await tester.pumpWidget(_MountedRouterHost(router: router));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/a');
      expect(find.text('destination A'), findsOneWidget);
      final hostState = tester.state<_MountedRouterHostState>(
        find.byType(_MountedRouterHost),
      );
      final hostElement = tester.element(find.byType(_MountedRouterHost));
      final aState = lifecycle.aState!;
      final aElement = tester.element(find.byKey(const Key('destination-a')));
      final redirectsBeforeActivation = lifecycle.redirectCount;
      final notificationsBeforeActivation = routerNotifications;

      final signed = await _signedPatch();
      expect(
        await tester.runAsync(() => patches.activateBytes(signed)),
        isTrue,
      );
      await tester.pump();
      expect(patches.status.phase, 'pendingHealth');

      // Patch activation is not a GoRouter navigation event or refresh signal.
      expect(router.state.uri.path, '/a');
      expect(find.text('destination A'), findsOneWidget);
      expect(lifecycle.redirectCount, redirectsBeforeActivation);
      expect(routerNotifications, notificationsBeforeActivation);
      _expectMountedContinuity(
        tester,
        lifecycle,
        hostState,
        hostElement,
        aState,
        aElement,
      );
      expect(await tester.runAsync(patches.markHealthy), isTrue);

      unawaited(router.push<void>('/details'));
      await tester.pumpAndSettle();
      expect(find.text('details'), findsOneWidget);
      expect(routerNotifications, greaterThan(notificationsBeforeActivation));
      expect(aState.mounted, isTrue);
      router.pop();
      await tester.pumpAndSettle();
      expect(tester.element(find.byKey(const Key('destination-a'))), same(aElement));

      // A normal push invokes GoRouter's redirect callback again. The existing
      // router reaches the patched function and selects compiled destination B.
      unawaited(router.push<void>('/decision/2'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/b');
      expect(find.text('destination B'), findsOneWidget);
      expect(aState.mounted, isTrue);
      expect(lifecycle.aDisposeCount, 0);
      expect(tester.state<_MountedRouterHostState>(find.byType(_MountedRouterHost)), same(hostState));
      router.pop();
      await tester.pumpAndSettle();
      expect(tester.element(find.byKey(const Key('destination-a'))), same(aElement));

      expect(
        await tester.runAsync(() => patches.activateBytes(<int>[1, 2, 3])),
        isFalse,
      );
      await tester.pump();
      expect(patches.status.mode, E1PatchMode.patch);
      expect(router.state.uri.path, '/a');
      _expectMountedContinuity(
        tester,
        lifecycle,
        hostState,
        hostElement,
        aState,
        aElement,
      );
      unawaited(router.push<void>('/decision/2'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/b');
      router.pop();
      await tester.pumpAndSettle();

      final redirectsBeforeRollback = lifecycle.redirectCount;
      final notificationsBeforeRollback = routerNotifications;
      expect(await tester.runAsync(patches.rollback), isTrue);
      await tester.pump();
      // Rollback also does not synthesize a refresh; the mounted route remains.
      expect(router.state.uri.path, '/a');
      expect(lifecycle.redirectCount, redirectsBeforeRollback);
      expect(routerNotifications, notificationsBeforeRollback);
      expect(tester.element(find.byKey(const Key('destination-a'))), same(aElement));
      final notificationsBeforePostRollbackNavigation = routerNotifications;
      unawaited(router.push<void>('/decision/2'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/a');
      expect(
        routerNotifications,
        greaterThan(notificationsBeforePostRollbackNavigation),
      );
      expect(lifecycle.aInitCount, 2);
      router.pop();
      await tester.pumpAndSettle();
      _expectMountedContinuity(
        tester,
        lifecycle,
        hostState,
        hostElement,
        aState,
        aElement,
        expectedAInitCount: 2,
        expectLifecycleCurrent: false,
      );
    },
  );

  testWidgets('compiled capability allow-list rejects unknown destinations', (tester) async {
    final lifecycle = _RouteLifecycle();
    final router = _router(lifecycle);
    addTearDown(router.dispose);
    final navigation = _NavigationCapability(router);
    await tester.pumpWidget(_MountedRouterHost(router: router));
    await tester.pumpAndSettle();

    expect(navigation.push('admin'), isFalse);
    await tester.pump();
    expect(router.state.uri.path, '/a');
    expect(find.text('destination A'), findsOneWidget);

    expect(navigation.push('details'), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('details'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    router.go('/not-compiled');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/not-compiled');
    expect(router.routerDelegate.currentConfiguration.isError, isTrue);
    expect(find.text('route rejected'), findsOneWidget);
  });
}

GoRouter _router(_RouteLifecycle lifecycle) => GoRouter(
  initialLocation: '/decision/2',
  redirect: (context, state) {
    lifecycle.redirectCount++;
    final segments = state.uri.pathSegments;
    if (segments.length != 2 || segments.first != 'decision') return null;
    final cohort = int.tryParse(segments.last);
    if (cohort == null) return '/rejected';
    return switch (app.chooseDestination(cohort)) {
      0 => '/a',
      1 => '/b',
      _ => '/rejected',
    };
  },
  errorBuilder: (context, state) => const _Page('route rejected'),
  routes: <RouteBase>[
    GoRoute(path: '/decision/:cohort', redirect: (context, state) => null),
    GoRoute(path: '/a', builder: (context, state) => _DestinationA(lifecycle)),
    GoRoute(path: '/b', builder: (context, state) => const _Page('destination B')),
    GoRoute(path: '/details', builder: (context, state) => const _Page('details')),
    GoRoute(path: '/rejected', builder: (context, state) => const _Page('route rejected')),
  ],
);

final class _NavigationCapability {
  _NavigationCapability(this.router);

  final GoRouter router;

  bool push(String destinationId) {
    final location = switch (destinationId) {
      'decision' => '/decision/2',
      'details' => '/details',
      _ => null,
    };
    if (location == null) return false;
    unawaited(router.push<void>(location));
    return true;
  }
}

final class _MountedRouterHost extends StatefulWidget {
  const _MountedRouterHost({required this.router});

  final GoRouter router;

  @override
  State<_MountedRouterHost> createState() => _MountedRouterHostState();
}

final class _MountedRouterHostState extends State<_MountedRouterHost> {
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: widget.router,
  );
}

final class _RouteLifecycle {
  _DestinationAState? aState;
  int aInitCount = 0;
  int aDisposeCount = 0;
  int redirectCount = 0;
}

final class _DestinationA extends StatefulWidget {
  const _DestinationA(this.lifecycle);

  final _RouteLifecycle lifecycle;

  @override
  State<_DestinationA> createState() => _DestinationAState();
}

final class _DestinationAState extends State<_DestinationA> {
  @override
  void initState() {
    super.initState();
    widget.lifecycle.aInitCount++;
    widget.lifecycle.aState = this;
  }

  @override
  void dispose() {
    widget.lifecycle.aDisposeCount++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const _Page(
    'destination A',
    key: Key('destination-a'),
  );
}

final class _Page extends StatelessWidget {
  const _Page(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

void _expectMountedContinuity(
  WidgetTester tester,
  _RouteLifecycle lifecycle,
  _MountedRouterHostState hostState,
  Element hostElement,
  _DestinationAState aState,
  Element aElement, {
  int expectedAInitCount = 1,
  bool expectLifecycleCurrent = true,
}) {
  expect(tester.state<_MountedRouterHostState>(find.byType(_MountedRouterHost)), same(hostState));
  expect(tester.element(find.byType(_MountedRouterHost)), same(hostElement));
  if (expectLifecycleCurrent) expect(lifecycle.aState, same(aState));
  expect(aState.mounted, isTrue);
  expect(lifecycle.aInitCount, expectedAInitCount);
  expect(lifecycle.aDisposeCount, expectedAInitCount - 1);
  expect(tester.element(find.byKey(const Key('destination-a'))), same(aElement));
}

E1PatchController _createController(Directory storage) => E1PatchController(
  storageDirectory: Directory('\${storage.path}/hyfens-e1'),
  appId: 'dev.hyfens.navigation',
  releaseId: 'navigation-release-1',
  buildFingerprint: 'navigation-build-1',
  functions: const <String, int>{${jsonEncode(functionId)}: 0},
  signatures: const <String, String>{${jsonEncode(functionId)}: ${jsonEncode(signature)}},
  receivers: const <String, String>{${jsonEncode(functionId)}: ${jsonEncode(receiver)}},
  trustedPublicKeys: <String, E1TrustedPublicKey>{
    _keyId: E1TrustedPublicKey(keyId: _keyId, bytes: _publicKey),
  },
  patchUri: Uri.parse('http://127.0.0.1:18080/navigation.e1.signed.json'),
);

Future<List<int>> _signedPatch() async => E1SignedPatchEnvelope.sign(
  patchBytes: File(${jsonEncode(patchPath)}).readAsBytesSync(),
  keyId: _keyId,
  privateKeySeed: _privateKeySeed,
);

const String _keyId = 'phase0b-rfc8032-test-only';
const List<int> _privateKeySeed = <int>[
  0x9d, 0x61, 0xb1, 0x9d, 0xef, 0xfd, 0x5a, 0x60,
  0xba, 0x84, 0x4a, 0xf4, 0x92, 0xec, 0x2c, 0xc4,
  0x44, 0x49, 0xc5, 0x69, 0x7b, 0x32, 0x69, 0x19,
  0x70, 0x3b, 0xac, 0x03, 0x1c, 0xae, 0x7f, 0x60,
];
const List<int> _publicKey = <int>[
  0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7,
  0xd5, 0x4b, 0xfe, 0xd3, 0xc9, 0x64, 0x07, 0x3a,
  0x0e, 0xe1, 0x72, 0xf3, 0xda, 0xa6, 0x23, 0x25,
  0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a,
];
''';
