import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  test('generalized typed guard changes a native AOT executable', () async {
    final scratch = Directory.systemTemp.createTempSync('e0_typed_aot_');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final release = File('${scratch.path}/typed_release_app.dart')
      ..writeAsBytesSync(
        File('fixture/typed_release_app.dart').readAsBytesSync(),
      );
    final overlay = Directory('${scratch.path}/overlay');
    final transformation = E0OverlayBuilder(E0SourceTransformer()).build(
      input: release,
      outputDirectory: overlay,
      packageName: 'instrumentation_fixture',
      logicalLibraryPath: 'lib/typed_app.dart',
      appId: 'app',
      releaseId: 'typed-aot',
      buildFingerprint: 'test-build-1',
    );
    final patch = E0PatchCompiler().compile(
      source: File('fixture/typed_patch_app.dart').readAsStringSync(),
      manifest: transformation.manifest,
      functionName: 'transform',
    );
    final patchFile = File('${scratch.path}/typed.patch')
      ..writeAsBytesSync(patch);
    final executable = File('${scratch.path}/typed_app');
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
    expect(base.exitCode, 0, reason: '${base.stderr}');
    expect(patched.exitCode, 0, reason: '${patched.stderr}');
    final baseJson = jsonDecode(base.stdout as String) as Map<String, Object?>;
    final patchedJson =
        jsonDecode(patched.stdout as String) as Map<String, Object?>;
    expect(baseJson['transform'], <String, dynamic>{'name': 'Ada'});
    expect(patchedJson['transform'], <String, dynamic>{
      'source': 'Ada',
      'patched': true,
    });
    expect(patchedJson['greet'], baseJson['greet']);
    expect(patchedJson['filter'], baseJson['filter']);
  });
}
