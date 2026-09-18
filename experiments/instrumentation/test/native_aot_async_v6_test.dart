import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  test('v6 ordinary async guard changes behavior in native AOT', () async {
    final scratch = Directory.systemTemp.createTempSync('e0_async_aot_');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final release = File('${scratch.path}/async_release_app.dart')
      ..writeAsBytesSync(
        File('fixture/async_release_app.dart').readAsBytesSync(),
      );
    final overlay = Directory('${scratch.path}/overlay');
    final transformation = E0OverlayBuilder(E0SourceTransformer()).build(
      input: release,
      outputDirectory: overlay,
      packageName: 'instrumentation_fixture',
      logicalLibraryPath: 'lib/async_app.dart',
      appId: 'app',
      releaseId: 'async-aot-v6',
      buildFingerprint: 'test-build-1',
      capabilities: <E0AsyncCapabilityDescriptor>[
        E0AsyncCapabilityDescriptor(
          id: 'e0.test.future.immediate',
          sourceName: 'hostImmediate',
          version: 1,
          arguments: <E0ValueSchema>[E0ValueSchema.integer],
          result: E0ValueSchema.integer,
        ),
        E0AsyncCapabilityDescriptor(
          id: 'e0.test.future.delayed',
          sourceName: 'hostDelayed',
          version: 1,
          arguments: <E0ValueSchema>[E0ValueSchema.integer],
          result: E0ValueSchema.integer,
        ),
      ],
    );
    final patch = E0PatchCompiler().compile(
      source: File('fixture/async_patch_app.dart').readAsStringSync(),
      manifest: transformation.manifest,
      functionName: 'calculateAsync',
    );
    final instancePatch = E0PatchCompiler().compile(
      source: File('fixture/async_instance_patch_app.dart').readAsStringSync(),
      manifest: transformation.manifest,
      functionName: 'calculate',
      className: 'AsyncService',
    );
    final patchFile = File('${scratch.path}/async.patch')
      ..writeAsBytesSync(patch);
    final instancePatchFile = File('${scratch.path}/async-instance.patch')
      ..writeAsBytesSync(instancePatch);
    final corruptInstancePatchFile = File(
      '${scratch.path}/async-instance-corrupt.patch',
    )..writeAsBytesSync(instancePatch.sublist(0, instancePatch.length - 11));
    final executable = File('${scratch.path}/async_app');
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
    final instancePatched = await Process.run(executable.path, <String>[
      '--e0-patch=${instancePatchFile.path}',
    ]);
    final corruptFallback = await Process.run(executable.path, <String>[
      '--e0-patch=${corruptInstancePatchFile.path}',
    ]);
    expect(base.exitCode, 0, reason: '${base.stderr}');
    expect(patched.exitCode, 0, reason: '${patched.stderr}');
    expect(instancePatched.exitCode, 0, reason: '${instancePatched.stderr}');
    expect(corruptFallback.exitCode, 0, reason: '${corruptFallback.stderr}');
    expect(jsonDecode(base.stdout as String), <String, Object?>{
      'result': 4,
      'instanceResult': 7,
      'eventLoopTicked': true,
    });
    expect(jsonDecode(patched.stdout as String), <String, Object?>{
      'result': 18,
      'instanceResult': 7,
      'eventLoopTicked': true,
    });
    expect(jsonDecode(instancePatched.stdout as String), <String, Object?>{
      'result': 4,
      'instanceResult': 28,
      'eventLoopTicked': true,
    });
    expect(jsonDecode(corruptFallback.stdout as String), <String, Object?>{
      'result': 4,
      'instanceResult': 7,
      'eventLoopTicked': true,
    });
    expect(patch.length, lessThan(4096));
  });
}
