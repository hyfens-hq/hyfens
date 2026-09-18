import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  group('Phase 1A language/runtime foundation', () {
    test('binds named, optional positional, and default parameters', () {
      final source = '''
int summarize({required String name, int count = 1}) {
  return name.length + count;
}

int add(String name, [int count = 1]) {
  return name.length + count;
}
''';
      final transformed = _transform(source);
      expect(transformed.source, contains('namedArguments'));
      final manifest = transformed.manifest;
      final program = _compile(manifest, 'summarize', '''
int summarize({required String name, int count = 1}) {
  return name.length + count;
}
''');

      expect(program.signature.parameterDetails, hasLength(2));
      expect(
        E0Interpreter.executeValues(
          program,
          const <Object?>[],
          namedArguments: <String, Object?>{'name': 'cart'},
        ),
        5,
      );
      expect(
        E0Interpreter.executeValues(
          program,
          const <Object?>[],
          namedArguments: <String, Object?>{'name': 'cart', 'count': 4},
        ),
        8,
      );
      expect(
        () => E0Interpreter.executeValues(
          program,
          const <Object?>[],
          namedArguments: <String, Object?>{},
        ),
        throwsA(isA<E0RuntimeFault>()),
      );
      expect(
        () => E0Interpreter.executeValues(
          program,
          const <Object?>[],
          namedArguments: <String, Object?>{'name': null},
        ),
        throwsA(isA<E0RuntimeFault>()),
      );

      final optionalPositional = _compile(manifest, 'add', '''
int add(String name, [int count = 1]) {
  return name.length + count;
}
''');
      expect(
        E0Interpreter.executeValues(optionalPositional, <Object?>['cart']),
        5,
      );
      expect(
        E0Interpreter.executeValues(optionalPositional, <Object?>['cart', 4]),
        8,
      );
    });

    test('executes captured closures through common collection callbacks', () {
      final source = '''
List<int> transform(List<int> values) {
  final multiplier = 2;
  return values.map((value) => value * multiplier).toList();
}

int total(List<int> values) {
  return values.fold(1, (accumulator, value) => accumulator + value);
}

int countLarge(List<int> values) {
  return values.where((value) => value > 1).length;
}
''';
      final manifest = _manifest(source);
      final transform = _compile(manifest, 'transform', source);
      final total = _compile(manifest, 'total', source);
      final countLarge = _compile(manifest, 'countLarge', source);

      expect(
        E0Interpreter.executeValues(transform, <Object?>[
          <int>[1, 2, 3],
        ]),
        <int>[2, 4, 6],
      );
      expect(
        E0Interpreter.executeValues(total, <Object?>[
          <int>[1, 2, 3],
        ]),
        7,
      );
      expect(
        E0Interpreter.executeValues(countLarge, <Object?>[
          <int>[1, 2, 3],
        ]),
        2,
      );
      expect(transform.closures, hasLength(1));
      expect(total.closures, hasLength(1));
      expect(countLarge.closures, hasLength(1));
      expect(
        () => E0Interpreter.executeValues(transform, <Object?>[
          <int>[1, 2, 3, 4, 5, 6, 7, 8],
        ], instructionBudget: 20),
        throwsA(isA<E0RuntimeFault>()),
      );
    });

    test('supports local closure invocation and Future.value await', () async {
      const source = '''
int apply(int value) {
  final increment = (int input) => input + 1;
  return increment(value);
}

Future<int> immediate(int value) async {
  final result = await Future.value(value + 1);
  return result;
}
''';
      final manifest = _manifest(source);
      final apply = _compile(manifest, 'apply', source);
      expect(E0Interpreter.executeValues(apply, <Object?>[4]), 5);

      final immediate = _compile(manifest, 'immediate', source);
      expect(immediate.signature.isAsync, isTrue);
      expect(immediate.capabilities, isEmpty);
      final result = await E0AsyncInterpreter.execute(immediate, <Object?>[
        4,
      ], onRuntimeFault: (_) {});
      expect(result, 5);
    });
  });
}

E0TransformResult _transform(String source) => E0SourceTransformer().transform(
  source: '$source\nvoid main() {}',
  packageName: 'phase1a_fixture',
  logicalLibraryPath: 'lib/phase1a.dart',
  appId: 'phase1a-app',
  releaseId: 'phase1a-release',
  buildFingerprint: 'phase1a-build',
);

E0ReleaseManifest _manifest(String source) => _transform(source).manifest;

E0PatchProgram _compile(
  E0ReleaseManifest manifest,
  String functionName,
  String source,
) {
  final bytes = E0PatchCompiler().compile(
    source: source,
    manifest: manifest,
    functionName: functionName,
  );
  return E0PatchContainer.decode(
    bytes,
    expectedAppId: manifest.appId,
    expectedReleaseId: manifest.releaseId,
    expectedBuildFingerprint: manifest.buildFingerprint,
    expectedFunctions: {
      for (final function in manifest.functions) function.id: function.slot,
    },
    expectedSignatures: {
      for (final function in manifest.functions)
        function.id: function.signature,
    },
    expectedReceivers: {
      for (final function in manifest.functions) function.id: function.receiver,
    },
  );
}
