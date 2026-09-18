import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  late E0ReleaseManifest manifest;
  late List<int> patch;

  setUp(() {
    E0PatchRuntime.reset();
    final transformation = E0SourceTransformer().transform(
      source:
          'int calculate(int a, int b) { return a + b; }\n'
          'void main(List<String> args) {}',
      packageName: 'fixture',
      logicalLibraryPath: 'lib/app.dart',
      appId: 'app',
      releaseId: 'release',
      buildFingerprint: 'test-build-1',
    );
    manifest = transformation.manifest;
    patch = E0PatchCompiler().compile(
      source:
          'int calculate(int a, int b) {\n'
          '  if (a < 0) return b - a;\n'
          '  if (a == b) return a * 10;\n'
          '  return a * b + 7;\n'
          '}',
      manifest: manifest,
      functionName: 'calculate',
    );
  });

  test('compiles changed normal Dart control flow deterministically', () {
    final again = E0PatchCompiler().compile(
      source:
          'int calculate(int a, int b) {\n'
          '  if (a < 0) return b - a;\n'
          '  if (a == b) return a * 10;\n'
          '  return a * b + 7;\n'
          '}',
      manifest: manifest,
      functionName: 'calculate',
    );
    expect(patch, again);
    expect(
      E0PatchRuntime.installBytes(
        patch,
        appId: 'app',
        releaseId: 'release',
        buildFingerprint: manifest.buildFingerprint,
        functions: {manifest.functions.single.id: 0},
        signatures: {
          manifest.functions.single.id: manifest.functions.single.signature
              .encode(),
        },
        receivers: {
          manifest.functions.single.id: manifest.functions.single.receiver
              .encode(),
        },
      ),
      isTrue,
    );
    final program = E0PatchRuntime.lookup(0)!;
    expect(E0PatchRuntime.invokeInt2(program, -2, 5), 7);
    expect(E0PatchRuntime.invokeInt2(program, 3, 3), 30);
    expect(E0PatchRuntime.invokeInt2(program, 4, 3), 19);
  });

  test('unpatched lookup performs no patched argument allocation', () {
    expect(E0PatchRuntime.lookup(0), isNull);
    expect(E0PatchRuntime.patchedArgumentListAllocations, 0);
  });

  test(
    'argument loading preserves active patch on absent or invalid candidates',
    () {
      final function = manifest.functions.single;
      final functions = <String, int>{function.id: function.slot};
      final signatures = <String, String>{
        function.id: function.signature.encode(),
      };
      final receivers = <String, String>{
        function.id: function.receiver.encode(),
      };
      expect(
        E0PatchRuntime.installBytes(
          patch,
          appId: manifest.appId,
          releaseId: manifest.releaseId,
          buildFingerprint: manifest.buildFingerprint,
          functions: functions,
          signatures: signatures,
          receivers: receivers,
        ),
        isTrue,
      );
      final active = E0PatchRuntime.lookup(function.slot)!;

      void load(List<String> arguments) => E0PatchRuntime.installFromArguments(
        arguments,
        appId: manifest.appId,
        releaseId: manifest.releaseId,
        buildFingerprint: manifest.buildFingerprint,
        functions: functions,
        signatures: signatures,
        receivers: receivers,
      );

      load(const <String>[]);
      expect(identical(E0PatchRuntime.lookup(function.slot), active), isTrue);
      expect(E0PatchRuntime.invokeInt2(active, 4, 3), 19);

      final missing =
          '${Directory.systemTemp.path}/e0-missing-patch-does-not-exist';
      load(<String>['--e0-patch=$missing']);
      expect(identical(E0PatchRuntime.lookup(function.slot), active), isTrue);
      expect(E0PatchRuntime.invokeInt2(active, 4, 3), 19);

      final scratch = Directory.systemTemp.createTempSync('e0_invalid_patch_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final corrupt = File('${scratch.path}/patch.e0.json')
        ..writeAsStringSync('{not-json');
      load(<String>['--e0-patch=${corrupt.path}']);
      expect(identical(E0PatchRuntime.lookup(function.slot), active), isTrue);
      expect(E0PatchRuntime.invokeInt2(active, 4, 3), 19);
    },
  );

  group('patch compiler signature boundary', () {
    for (final source in <String>[
      'int calculate(String a, int b) { return b; }',
      'int calculate(a, int b) { return b; }',
      'int calculate(int a, [int b = 0]) { return a + b; }',
      'int calculate(int a, {required int b}) { return a + b; }',
      'int calculate(int a, int b) async { return a + b; }',
      'int calculate(int a, int b) sync* { yield a + b; }',
    ]) {
      test('rejects `${source.split('{').first.trim()}`', () {
        expect(
          () => E0PatchCompiler().compile(
            source: source,
            manifest: manifest,
            functionName: 'calculate',
          ),
          throwsFormatException,
        );
      });
    }
  });

  group('malformed input fails closed', () {
    test('omitted compatibility tables are rejected', () {
      final function = manifest.functions.single;
      final forged = E0PatchContainer.encode(
        appId: 'app',
        releaseId: 'release',
        buildFingerprint: manifest.buildFingerprint,
        program: E0PatchProgram(
          functionId: function.id,
          slot: function.slot,
          signature: const E0FunctionSignature(
            parameters: <E0ValueSchema>[E0ValueSchema.string],
            returnSchema: E0ValueSchema.string,
          ),
          constants: const <Object?>['forged'],
          code: const <int>[2, 0, 9],
        ),
      );
      expect(
        E0PatchRuntime.installBytes(
          forged,
          appId: 'app',
          releaseId: 'release',
          buildFingerprint: manifest.buildFingerprint,
          functions: <String, int>{function.id: function.slot},
        ),
        isFalse,
      );
      expect(E0PatchRuntime.lookup(function.slot), isNull);
      expect(E0PatchRuntime.lastRejection, contains('compatibility tables'));
      expect(
        () => E0PatchContainer.decode(
          forged,
          expectedAppId: 'app',
          expectedReleaseId: 'release',
          expectedBuildFingerprint: manifest.buildFingerprint,
          expectedFunctions: <String, int>{function.id: function.slot},
        ),
        throwsFormatException,
      );
    });

    test('wrong release and unknown field are rejected', () {
      expect(
        E0PatchRuntime.installBytes(
          patch,
          appId: 'app',
          releaseId: 'other',
          buildFingerprint: manifest.buildFingerprint,
          functions: {manifest.functions.single.id: 0},
        ),
        isFalse,
      );
      final json = jsonDecode(utf8.decode(patch)) as Map<String, Object?>;
      json['surprise'] = true;
      expect(
        E0PatchRuntime.installBytes(
          utf8.encode(jsonEncode(json)),
          appId: 'app',
          releaseId: 'release',
          buildFingerprint: manifest.buildFingerprint,
          functions: {manifest.functions.single.id: 0},
        ),
        isFalse,
      );
    });

    for (final mutation in <String, void Function(Map<String, Object?>)>{
      'unknown opcode': (json) => json['code'] = <int>[255],
      'invalid jump': (json) => json['code'] = <int>[1, 0, 8, 1, 9],
      'invalid argument index': (json) => json['code'] = <int>[1, 3, 9],
      'invalid constant index': (json) => json['code'] = <int>[2, 99, 9],
      'invalid code type': (json) => json['code'] = <Object>['bad'],
    }.entries) {
      test('${mutation.key} is rejected', () {
        final json = jsonDecode(utf8.decode(patch)) as Map<String, Object?>;
        mutation.value(json);
        expect(
          E0PatchRuntime.installBytes(
            utf8.encode(jsonEncode(json)),
            appId: 'app',
            releaseId: 'release',
            buildFingerprint: manifest.buildFingerprint,
            functions: {manifest.functions.single.id: 0},
          ),
          isFalse,
        );
        expect(E0PatchRuntime.lookup(0), isNull);
      });
    }

    test('instruction budget and runtime type errors are bounded', () {
      final function = manifest.functions.single;
      final budgetProgram = E0PatchProgram(
        functionId: function.id,
        slot: 0,
        constants: const <int>[],
        code: const <int>[1, 0, 1, 1, 7, 8, 0, 1, 0, 9],
      );
      E0Interpreter.validate(budgetProgram);
      expect(
        () => E0Interpreter.execute(budgetProgram, 0, 1, instructionBudget: 4),
        throwsA(isA<E0RuntimeFault>()),
      );
      final typeProgram = E0PatchProgram(
        functionId: function.id,
        slot: 0,
        constants: const <int>[1],
        code: const <int>[2, 0, 8, 0],
      );
      expect(() => E0Interpreter.validate(typeProgram), throwsFormatException);
    });
  });
}
