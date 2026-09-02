import 'dart:io';

import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  test(
    'ordinary build dispatch survives native AOT and rolls back to base',
    () async {
      final scratch = await Directory.systemTemp.createTemp('e0-widget-aot-');
      addTearDown(() => scratch.delete(recursive: true));
      final sourceFile = File('fixture/widget_release_app.dart');
      final source = sourceFile.readAsStringSync();
      final descriptors = _descriptors();
      final transformation = E0SourceTransformer().transform(
        source: source,
        packageName: 'instrumentation_e0',
        logicalLibraryPath: 'lib/widget_release_app.dart',
        appId: 'widget-aot',
        releaseId: 'release-1',
        buildFingerprint: 'widget-aot-build-1',
        widgetFactories: descriptors,
        widgetBuildClasses: const <String>{'PricingCard'},
        allowSyntheticWidgetTypes: true,
      );
      final overlay = Directory('${scratch.path}/overlay')..createSync();
      File('${overlay.path}/app.dart').writeAsStringSync(transformation.source);
      expect(sourceFile.readAsStringSync(), source);
      final bytes = E0PatchCompiler().compile(
        source: File('fixture/widget_patch_app.dart').readAsStringSync(),
        manifest: transformation.manifest,
        className: 'PricingCard',
        functionName: 'build',
        allowSyntheticWidgetTypes: true,
      );
      final patch = File('${scratch.path}/widget.e0.json')
        ..writeAsBytesSync(bytes);
      final executable = '${scratch.path}/widget_app';
      final compile = await Process.run('dart', <String>[
        'compile',
        'exe',
        '--packages=.dart_tool/package_config.json',
        '${overlay.path}/app.dart',
        '-o',
        executable,
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '${compile.stdout}\n${compile.stderr}',
      );

      final base = await Process.run(executable, const <String>[]);
      expect(base.exitCode, 0, reason: '${base.stdout}\n${base.stderr}');
      expect(base.stdout, contains('Text(BASE Pro)'));

      final patched = await Process.run(executable, <String>[
        '--e0-patch=${patch.path}',
      ]);
      expect(
        patched.exitCode,
        0,
        reason: '${patched.stdout}\n${patched.stderr}',
      );
      expect(
        patched.stdout,
        contains(
          'Column(min:[Text(PATCH Pro,size=24.0),Text(conditional hierarchy),ElevatedButton(Text(Upgrade))])',
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

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
