import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  test('transformed ordinary build returns real Flutter widgets', () async {
    final fixture = Directory('../../fixtures/flutter_conformance_app')
        .absolute;
    final sourceFile = File('${fixture.path}/lib/main.dart');
    final source = sourceFile.readAsStringSync();
    final scratch = await fixture.createTemp('.dart_tool/widget-overlay-');
    addTearDown(() => scratch.delete(recursive: true));

    final transformation = E0SourceTransformer().transform(
      source: source,
      packageName: 'conformance',
      logicalLibraryPath: 'lib/main.dart',
      appId: 'widget-flutter-overlay',
      releaseId: 'release-1',
      buildFingerprint: 'widget-flutter-overlay-1',
      widgetFactories: _descriptors(),
      widgetBuildClasses: const <String>{'PricingCard'},
    );
    expect(sourceFile.readAsStringSync(), source);
    final build = transformation.manifest.functions.singleWhere(
      (function) =>
          function.name == 'build' &&
          function.receiver.ownerClass == 'PricingCard',
    );
    expect(build.signature, e0WidgetBuildSignature);
    final patchBytes = E0PatchCompiler().compile(
      source: File('${fixture.path}/test/fixtures/pricing_card_patch.dart')
          .readAsStringSync(),
      manifest: transformation.manifest,
      className: 'PricingCard',
      functionName: 'build',
    );
    File('${scratch.path}/app.dart').writeAsStringSync(transformation.source);
    File('${fixture.path}/lib/patch_bootstrap.dart')
        .copySync('${scratch.path}/patch_bootstrap.dart');
    File('${fixture.path}/lib/widget_factories.dart')
        .copySync('${scratch.path}/widget_factories.dart');
    final patchFile = File('${scratch.path}/widget.e0.json')
      ..writeAsBytesSync(patchBytes);
    final generatedTest = File('${scratch.path}/overlay_widget_test.dart');
    generatedTest.writeAsStringSync(
      _generatedFlutterTest(
        patchPath: patchFile.path,
        manifest: transformation.manifest,
        buildSlot: build.slot,
      ),
    );

    final result = await Process.run('flutter', <String>[
      'test',
      generatedTest.path,
    ], workingDirectory: fixture.path);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('All tests passed'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

String _generatedFlutterTest({
  required String patchPath,
  required E0ReleaseManifest manifest,
  required int buildSlot,
}) {
  final functions = _dartMap(<String, Object?>{
    for (final function in manifest.functions) function.id: function.slot,
  });
  final signatures = _dartMap(<String, Object?>{
    for (final function in manifest.functions)
      function.id: function.signature.encode(),
  });
  final receivers = _dartMap(<String, Object?>{
    for (final function in manifest.functions)
      function.id: function.receiver.encode(),
  });
  return '''
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instrumentation_e0/e0_runtime.dart';

import 'app.dart' as app;
import 'widget_factories.dart';

void main() {
  setUp(E0PatchRuntime.reset);
  tearDown(E0PatchRuntime.reset);

  testWidgets('guarded PricingCard builds patched real Widgets', (tester) async {
    expect(_install(_registry()), isTrue, reason: E0PatchRuntime.lastRejection);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: app.PricingCard(featured: true, plan: 'Pro')),
      ),
    );
    expect(find.text('PATCH Pro'), findsOneWidget);
    expect(find.text('BASE Pro'), findsNothing);
    expect(find.text('conditional hierarchy'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Upgrade'), findsOneWidget);
    expect(tester.widget<Text>(find.text('PATCH Pro')).style?.fontSize, 24.0);
  });

  testWidgets('factory throw deactivates and safely builds original tree', (tester) async {
    expect(
      _install(_registry(throwText: true)),
      isTrue,
      reason: E0PatchRuntime.lastRejection,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: app.PricingCard(featured: true, plan: 'Pro')),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('BASE Pro'), findsOneWidget);
    expect(find.text('PATCH Pro'), findsNothing);
    expect(E0PatchRuntime.lookup($buildSlot), isNull);
  });

  testWidgets('wrong nested child type deactivates before lazy cast escapes', (tester) async {
    expect(
      _install(_registry(wrongText: true)),
      isTrue,
      reason: E0PatchRuntime.lastRejection,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: app.PricingCard(featured: true, plan: 'Pro')),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('BASE Pro'), findsOneWidget);
    expect(find.text('PATCH Pro'), findsNothing);
    expect(E0PatchRuntime.lastRejection, contains('expected Widget'));
  });

  testWidgets('active patch rolls back to base on mounted rebuild', (tester) async {
    expect(_install(_registry()), isTrue, reason: E0PatchRuntime.lastRejection);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: app.PricingCard(featured: true, plan: 'Pro')),
      ),
    );
    expect(find.text('PATCH Pro'), findsOneWidget);

    E0PatchRuntime.reset();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: app.PricingCard(featured: true, plan: 'Pro')),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('PATCH Pro'), findsNothing);
    expect(find.text('BASE Pro'), findsOneWidget);
  });
}

bool _install(E0WidgetFactoryRegistry registry) {
  E0PatchRuntime.configureWidgetFactories(registry);
  return E0PatchRuntime.installBytes(
    File(${jsonEncode(patchPath)}).readAsBytesSync(),
    appId: ${jsonEncode(manifest.appId)},
    releaseId: ${jsonEncode(manifest.releaseId)},
    buildFingerprint: ${jsonEncode(manifest.buildFingerprint)},
    functions: $functions,
    signatures: $signatures,
    receivers: $receivers,
  );
}

E0WidgetFactoryRegistry _registry({
  bool throwText = false,
  bool wrongText = false,
}) => E0WidgetFactoryRegistry(<E0WidgetFactoryRegistration>[
  E0WidgetFactoryRegistration(
    descriptor: conformanceWidgetFactories[0],
    create: (properties, children) {
      if (throwText) throw StateError('factory rejected text');
      if (wrongText) return 'not a Widget';
      return Text(
        properties['data']! as String,
        style: properties['fontSize'] == null
            ? null
            : TextStyle(fontSize: properties['fontSize']! as double),
      );
    },
  ),
  E0WidgetFactoryRegistration(
    descriptor: conformanceWidgetFactories[1],
    create: (properties, children) => Column(
      mainAxisSize: switch (properties['mainAxisSize']) {
        null || 'max' => MainAxisSize.max,
        'min' => MainAxisSize.min,
        _ => throw const FormatException('Invalid MainAxisSize value'),
      },
      children: children.cast<Widget>(),
    ),
  ),
  E0WidgetFactoryRegistration(
    descriptor: conformanceWidgetFactories[2],
    create: (properties, children) => ElevatedButton(
      onPressed: null,
      child: children.single as Widget,
    ),
  ),
]);
''';
}

String _dartMap(Map<String, Object?> values) =>
    '<String, ${values.values.firstOrNull is int ? 'int' : 'String'}>{${values.entries.map((entry) => '${jsonEncode(entry.key)}: ${jsonEncode(entry.value)}').join(', ')}}';

List<E0WidgetFactoryDescriptor> _descriptors() => <E0WidgetFactoryDescriptor>[
  E0WidgetFactoryDescriptor(
    id: 'flutter.text.v1',
    sourceName: 'Text',
    properties: const <E0WidgetPropertyDescriptor>[
      E0WidgetPropertyDescriptor(
        name: 'data',
        schema: E0ValueSchema.string,
        required: true,
      ),
      E0WidgetPropertyDescriptor(
        name: 'fontSize',
        schema: E0ValueSchema.doubleValue,
      ),
    ],
    minChildren: 0,
    maxChildren: 0,
  ),
  E0WidgetFactoryDescriptor(
    id: 'flutter.column.v1',
    sourceName: 'Column',
    properties: const <E0WidgetPropertyDescriptor>[
      E0WidgetPropertyDescriptor(
        name: 'mainAxisSize',
        schema: E0ValueSchema.string,
        allowedValues: <String>['min', 'max'],
      ),
    ],
    minChildren: 0,
    maxChildren: E0WidgetFactoryRegistry.maxChildren,
  ),
  E0WidgetFactoryDescriptor(
    id: 'flutter.elevated-button.v1',
    sourceName: 'ElevatedButton',
    properties: const <E0WidgetPropertyDescriptor>[],
    minChildren: 1,
    maxChildren: 1,
  ),
];
