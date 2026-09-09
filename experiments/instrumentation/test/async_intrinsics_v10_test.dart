import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  late E0ReleaseManifest manifest;

  setUp(() {
    E0PatchRuntime.reset();
    manifest = E0SourceTransformer()
        .transform(
          source: _releaseSource,
          packageName: 'async_intrinsics_fixture',
          logicalLibraryPath: 'lib/async.dart',
          appId: 'async-intrinsics-app',
          releaseId: 'async-intrinsics-release',
          buildFingerprint: 'async-intrinsics-build',
        )
        .manifest;
  });

  tearDown(E0PatchRuntime.reset);

  test(
    'compiles, installs, and executes bounded Flutter async intrinsics',
    () async {
      final program = _compile('waitForFrame');
      expect(program.signature.isAsync, isTrue);
      expect(
        program.code,
        containsAllInOrder(<int>[
          E0Opcode.futureDelay.code,
          1,
          E0Opcode.awaitValue.code,
          E0Opcode.flutterEndOfFrame.code,
          E0Opcode.awaitValue.code,
        ]),
      );
      E0PatchRuntime.configureFlutterFrameWaiterIfAbsent(() async {});
      expect(_install(program), isTrue, reason: E0PatchRuntime.lastRejection);
      final result = E0PatchRuntime.invokeAsync<void>(
        E0PatchRuntime.lookup(program.slot)!,
        const <Object?>[],
      );
      expect(result, isNotNull);
      await result;
      expect(E0AsyncInterpreter.activeContinuations, 0);
    },
  );

  test('typed Future<T>.value stays within the same async ABI', () async {
    final program = _compile('typedValue');
    expect(program.signature.returnSchema, E0ValueSchema.boolean);
    expect(_install(program), isTrue, reason: E0PatchRuntime.lastRejection);
    expect(
      await E0PatchRuntime.invokeAsync<bool>(
        E0PatchRuntime.lookup(program.slot)!,
        const <Object?>[],
      ),
      isTrue,
    );
  });

  test('duration expressions are bounded and deterministic', () {
    expect(
      () => E0PatchCompiler().compile(
        source: '''
Future<void> waitForFrame() async {
  await Future<void>.delayed(const Duration(minutes: 6));
}
''',
        manifest: manifest,
        functionName: 'waitForFrame',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('five-minute patch limit'),
        ),
      ),
    );
    expect(
      () => E0PatchCompiler().compile(
        source: '''
Future<void> waitForFrame() async {
  final int milliseconds = 1;
  await Future<void>.delayed(Duration(milliseconds: milliseconds));
}
''',
        manifest: manifest,
        functionName: 'waitForFrame',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('bounded Duration'),
        ),
      ),
    );
  });
}

E0PatchProgram _compile(String functionName) {
  final bytes = E0PatchCompiler().compile(
    source: _patchSource,
    manifest: _manifest,
    functionName: functionName,
  );
  return E0PatchContainer.decode(
    bytes,
    expectedAppId: _manifest.appId,
    expectedReleaseId: _manifest.releaseId,
    expectedBuildFingerprint: _manifest.buildFingerprint,
    expectedFunctions: {
      for (final function in _manifest.functions) function.id: function.slot,
    },
    expectedSignatures: {
      for (final function in _manifest.functions)
        function.id: function.signature,
    },
    expectedReceivers: {
      for (final function in _manifest.functions)
        function.id: function.receiver,
    },
  );
}

bool _install(E0PatchProgram program) => E0PatchRuntime.installBytes(
  E0PatchContainer.encode(
    appId: _manifest.appId,
    releaseId: _manifest.releaseId,
    buildFingerprint: _manifest.buildFingerprint,
    program: program,
  ),
  appId: _manifest.appId,
  releaseId: _manifest.releaseId,
  buildFingerprint: _manifest.buildFingerprint,
  functions: {
    for (final function in _manifest.functions) function.id: function.slot,
  },
  signatures: {
    for (final function in _manifest.functions)
      function.id: function.signature.encode(),
  },
  receivers: {
    for (final function in _manifest.functions)
      function.id: function.receiver.encode(),
  },
);

final E0ReleaseManifest _manifest = E0SourceTransformer()
    .transform(
      source: _releaseSource,
      packageName: 'async_intrinsics_fixture',
      logicalLibraryPath: 'lib/async.dart',
      appId: 'async-intrinsics-app',
      releaseId: 'async-intrinsics-release',
      buildFingerprint: 'async-intrinsics-build',
    )
    .manifest;

const _releaseSource = '''
Future<void> waitForFrame() async {
  await Future<void>.delayed(Duration.zero);
  await WidgetsBinding.instance.endOfFrame;
}

Future<bool> typedValue() async {
  return await Future<bool>.value(true);
}

void main() {}
''';

const _patchSource = '''
Future<void> waitForFrame() async {
  await Future<void>.delayed(const Duration(milliseconds: 1));
  await WidgetsBinding.instance.endOfFrame;
}

Future<bool> typedValue() async {
  return await Future<bool>.value(true);
}

void main() {}
''';
