import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  test('v5 guest throw crosses generated guard in native AOT', () async {
    final scratch = Directory.systemTemp.createTempSync('e0_exception_aot_');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final release = File('${scratch.path}/exception_release_app.dart')
      ..writeAsBytesSync(
        File('fixture/exception_release_app.dart').readAsBytesSync(),
      );
    final overlay = Directory('${scratch.path}/overlay');
    final transformation = E0OverlayBuilder(E0SourceTransformer()).build(
      input: release,
      outputDirectory: overlay,
      packageName: 'instrumentation_fixture',
      logicalLibraryPath: 'lib/exception_app.dart',
      appId: 'app',
      releaseId: 'exception-aot-v5',
      buildFingerprint: 'test-build-1',
    );
    final patch = E0PatchCompiler().compile(
      source: File('fixture/exception_patch_app.dart').readAsStringSync(),
      manifest: transformation.manifest,
      functionName: 'scenario',
    );
    final patchFile = File('${scratch.path}/exception.patch')
      ..writeAsBytesSync(patch);
    final corruptFile = File('${scratch.path}/corrupt.patch')
      ..writeAsBytesSync(<int>[...patch.take(patch.length - 9)]);
    final executable = File('${scratch.path}/exception_app');
    final compile = await Process.run(Platform.resolvedExecutable, <String>[
      'compile',
      'exe',
      "--packages=${File('.dart_tool/package_config.json').absolute.path}",
      '${overlay.path}/app.dart',
      '-o',
      executable.path,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

    final base = await Process.run(executable.path, const <String>[]);
    final patched = await Process.run(executable.path, <String>[
      '--e0-patch=${patchFile.path}',
    ]);
    final corrupt = await Process.run(executable.path, <String>[
      '--e0-patch=${corruptFile.path}',
    ]);
    expect(base.exitCode, 0, reason: '${base.stderr}');
    expect(patched.exitCode, 0, reason: '${patched.stderr}');
    expect(corrupt.exitCode, 0, reason: '${corrupt.stderr}');
    expect(jsonDecode(base.stdout as String), <String, Object?>{'result': 6});
    expect(jsonDecode(patched.stdout as String), <String, Object?>{
      'error': 77,
      'type': 'int',
      'syntheticTrace': true,
    });
    expect(jsonDecode(corrupt.stdout as String), <String, Object?>{
      'result': 6,
    });
    expect(patch.length, lessThan(2048));
  });
}
