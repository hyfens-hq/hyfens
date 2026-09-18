import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  test(
    'instance guard changes direct virtual and tear-off native AOT dispatch',
    () async {
      final scratch = Directory.systemTemp.createTempSync('e0_instance_aot_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final release = File('${scratch.path}/instance_release_app.dart')
        ..writeAsBytesSync(
          File('fixture/instance_release_app.dart').readAsBytesSync(),
        );
      final transformation = E0OverlayBuilder(E0SourceTransformer()).build(
        input: release,
        outputDirectory: Directory('${scratch.path}/overlay'),
        packageName: 'instrumentation_fixture',
        logicalLibraryPath: 'lib/instance_app.dart',
        appId: 'app',
        releaseId: 'instance-aot',
        buildFingerprint: 'test-build-1',
      );
      final patch = E0PatchCompiler().compile(
        source: File('fixture/instance_patch_app.dart').readAsStringSync(),
        manifest: transformation.manifest,
        className: 'PricingService',
        functionName: 'calculate',
      );
      final patchFile = File('${scratch.path}/instance.patch')
        ..writeAsBytesSync(patch);
      final executable = File('${scratch.path}/instance_app');
      final compile = await Process.run(Platform.resolvedExecutable, <String>[
        'compile',
        'exe',
        "--packages=${File('.dart_tool/package_config.json').absolute.path}",
        '${scratch.path}/overlay/app.dart',
        '-o',
        executable.path,
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '${compile.stdout}\n${compile.stderr}',
      );

      final base = await Process.run(executable.path, const <String>[]);
      final patched = await Process.run(executable.path, <String>[
        '--e0-patch=${patchFile.path}',
      ]);
      expect(base.exitCode, 0, reason: '${base.stderr}');
      expect(patched.exitCode, 0, reason: '${patched.stderr}');
      expect(jsonDecode(base.stdout as String), <String, Object?>{
        'direct': 18.5,
        'virtual': 18.5,
        'tearOff': 18.5,
        'override': 99.0,
      });
      expect(jsonDecode(patched.stdout as String), <String, Object?>{
        'direct': 26.5,
        'virtual': 26.5,
        'tearOff': 26.5,
        'override': 99.0,
      });
    },
  );
}
