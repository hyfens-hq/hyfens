import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  test(
    'v4 control flow and isolated collection mutation run in native AOT',
    () async {
      final scratch = Directory.systemTemp.createTempSync('e0_control_aot_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final release = File('${scratch.path}/control_release_app.dart')
        ..writeAsBytesSync(
          File('fixture/control_release_app.dart').readAsBytesSync(),
        );
      final overlay = Directory('${scratch.path}/overlay');
      final transformation = E0OverlayBuilder(E0SourceTransformer()).build(
        input: release,
        outputDirectory: overlay,
        packageName: 'instrumentation_fixture',
        logicalLibraryPath: 'lib/control_app.dart',
        appId: 'app',
        releaseId: 'control-aot-v4',
        buildFingerprint: 'test-build-1',
      );
      final patch = E0PatchCompiler().compile(
        source: File('fixture/control_patch_app.dart').readAsStringSync(),
        manifest: transformation.manifest,
        functionName: 'revise',
      );
      final patchFile = File('${scratch.path}/control.patch')
        ..writeAsBytesSync(patch);
      final executable = File('${scratch.path}/control_app');
      final compile = await Process.run(Platform.resolvedExecutable, <String>[
        'compile',
        'exe',
        "--packages=${File('.dart_tool/package_config.json').absolute.path}",
        '${overlay.path}/app.dart',
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
        'input': <int>[2, 3],
        'result': <int>[2, 3],
      });
      expect(jsonDecode(patched.stdout as String), <String, Object?>{
        'input': <int>[2, 3],
        'result': <int>[4, 6, 7],
      });
    },
  );
}
