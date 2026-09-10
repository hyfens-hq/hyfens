import 'dart:io';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';

final _immediate = E0AsyncCapabilityDescriptor(
  id: 'e0.test.future.immediate',
  sourceName: 'hostImmediate',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.integer],
  result: E0ValueSchema.integer,
);
final _delayed = E0AsyncCapabilityDescriptor(
  id: 'e0.test.future.delayed',
  sourceName: 'hostDelayed',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.integer],
  result: E0ValueSchema.integer,
);

Future<void> main(List<String> arguments) async {
  final iterations = arguments.isEmpty ? 10000 : int.parse(arguments.single);
  // Keep the input outside the instrumentation package's package_config root.
  // The fixture intentionally lives outside lib/, so resolving it through the
  // package config would (correctly) reject it as an invalid package URI. The
  // benchmark only needs a stable source copy; it does not need package URI
  // discovery for this isolated fixture.
  final scratch = Directory.systemTemp.createTempSync('e0_async_bench_');
  try {
    final input = File('${scratch.path}/async_release_app.dart')
      ..writeAsBytesSync(
        File('fixture/async_release_app.dart').readAsBytesSync(),
      );
    final transformation = E0OverlayBuilder(E0SourceTransformer()).build(
      input: input,
      outputDirectory: Directory('${scratch.path}/overlay'),
      packageName: 'instrumentation_fixture',
      logicalLibraryPath: 'lib/async_app.dart',
      appId: 'app',
      releaseId: 'async-benchmark-v6',
      buildFingerprint: 'async-benchmark-build-1',
      capabilities: <E0AsyncCapabilityDescriptor>[_immediate, _delayed],
    );
    final bytes = E0PatchCompiler().compile(
      source: File('fixture/async_patch_app.dart').readAsStringSync(),
      manifest: transformation.manifest,
      functionName: 'calculateAsync',
    );
    final program = E0PatchContainer.decode(
      bytes,
      expectedAppId: transformation.manifest.appId,
      expectedReleaseId: transformation.manifest.releaseId,
      expectedBuildFingerprint: transformation.manifest.buildFingerprint,
      expectedFunctions: <String, int>{
        for (final function in transformation.manifest.functions)
          function.id: function.slot,
      },
      expectedSignatures: <String, E0FunctionSignature>{
        for (final function in transformation.manifest.functions)
          function.id: function.signature,
      },
      expectedReceivers: <String, E0ReceiverDescriptor>{
        for (final function in transformation.manifest.functions)
          function.id: function.receiver,
      },
    );

    _register(immediateDelayed: true);
    for (var index = 0; index < 100; index++) {
      await E0AsyncInterpreter.execute(program, <Object?>[
        index,
      ], onRuntimeFault: _fail);
    }
    final immediateWatch = Stopwatch()..start();
    for (var index = 0; index < iterations; index++) {
      await E0AsyncInterpreter.execute(program, <Object?>[
        index,
      ], onRuntimeFault: _fail);
    }
    immediateWatch.stop();

    E0PatchRuntime.reset();
    _register(immediateDelayed: false);
    final delayedWatch = Stopwatch()..start();
    for (var index = 0; index < 20; index++) {
      await E0AsyncInterpreter.execute(program, <Object?>[
        index,
      ], onRuntimeFault: _fail);
    }
    delayedWatch.stop();

    stdout.writeln('patchBytes=${bytes.length}');
    stdout.writeln('asyncPoints=${program.asyncPoints.length}');
    stdout.writeln('codeWords=${program.code.length}');
    stdout.writeln('immediateIterations=$iterations');
    stdout.writeln('immediateTotalUs=${immediateWatch.elapsedMicroseconds}');
    stdout.writeln(
      'immediateUsPerInvocation='
      '${immediateWatch.elapsedMicroseconds / iterations}',
    );
    stdout.writeln('delayedIterations=20');
    stdout.writeln('delayedTotalUs=${delayedWatch.elapsedMicroseconds}');
  } finally {
    scratch.deleteSync(recursive: true);
    E0PatchRuntime.reset();
  }
}

void _register({required bool immediateDelayed}) {
  E0PatchRuntime.configureCapabilities(
    E0CapabilityAuthority(
      shipped: <E0AsyncCapabilityDescriptor>[_immediate, _delayed],
      registry: E0CapabilityRegistry(<E0CapabilityRegistration>[
        E0CapabilityRegistration(
          _immediate,
          (arguments) => Future<Object?>.value((arguments.single! as int) + 1),
        ),
        E0CapabilityRegistration(
          _delayed,
          immediateDelayed
              ? (arguments) =>
                    Future<Object?>.value((arguments.single! as int) * 2)
              : (arguments) => Future<Object?>.delayed(
                  const Duration(milliseconds: 1),
                  () => (arguments.single! as int) * 2,
                ),
        ),
      ]),
    ),
  );
}

Never _fail(String message) => throw StateError(message);
