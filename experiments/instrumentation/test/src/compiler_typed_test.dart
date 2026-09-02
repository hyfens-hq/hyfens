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
          packageName: 'fixture',
          logicalLibraryPath: 'lib/typed.dart',
          appId: 'app',
          releaseId: 'typed-release',
          buildFingerprint: 'test-build-1',
        )
        .manifest;
  });

  group('required generalized functions', () {
    final scenarios =
        <String, ({String source, List<Object?> arguments, Object? expected})>{
          'greet': (
            source: "String greet(String name) { return 'Welcome, ' + name; }",
            arguments: <Object?>['Ada'],
            expected: 'Welcome, Ada',
          ),
          'isEligible': (
            source:
                'bool isEligible(int age, bool verified) { '
                'return age >= 21 && verified; }',
            arguments: <Object?>[24, true],
            expected: true,
          ),
          'calculate': (
            source:
                'double calculate(double amount, double rate) { '
                'return amount * rate; }',
            arguments: <Object?>[12.5, 0.2],
            expected: 2.5,
          ),
          'transform': (
            source:
                'Map<String, dynamic> transform(Map<String, dynamic> input) { '
                "return <String, dynamic>{'source': input['name'], "
                "'patched': true}; }",
            arguments: <Object?>[
              <String, dynamic>{'name': 'Ada'},
            ],
            expected: <String, dynamic>{'source': 'Ada', 'patched': true},
          ),
          'filterValues': (
            source:
                'List<int> filterValues(List<int> values) { '
                'return <int>[values[0], values[2]]; }',
            arguments: <Object?>[
              <int>[3, 4, 9],
            ],
            expected: <int>[3, 9],
          ),
        };

    for (final scenario in scenarios.entries) {
      test('compiles and executes ${scenario.key}', () {
        final patch = E0PatchCompiler().compile(
          source: scenario.value.source,
          manifest: manifest,
          functionName: scenario.key,
        );
        expect(
          E0PatchRuntime.installBytes(
            patch,
            appId: 'app',
            releaseId: 'typed-release',
            buildFingerprint: manifest.buildFingerprint,
            functions: _functions(manifest),
            signatures: _signatures(manifest),
            receivers: _receivers(manifest),
          ),
          isTrue,
        );
        final function = manifest.functions.singleWhere(
          (item) => item.name == scenario.key,
        );
        final result = E0PatchRuntime.invoke(
          E0PatchRuntime.lookup(function.slot)!,
          scenario.value.arguments,
        );
        expect(result.isSuccess, isTrue);
        expect(result.value, scenario.value.expected);
      });
    }

    test('supports interpolation and explicit nullable arguments/returns', () {
      final interpolation = E0PatchCompiler().compile(
        source: "String greet(String name) { return 'Hi, \$name'; }",
        manifest: manifest,
        functionName: 'greet',
      );
      expect(interpolation, isNotEmpty);

      final nullableManifest = E0SourceTransformer()
          .transform(
            source:
                'String? maybeName(String? name) { return name; }\n'
                'void main(List<String> args) {}',
            packageName: 'fixture',
            logicalLibraryPath: 'lib/nullable.dart',
            appId: 'app',
            releaseId: 'nullable',
            buildFingerprint: 'test-build-1',
          )
          .manifest;
      final patch = E0PatchCompiler().compile(
        source: 'String? maybeName(String? name) { return name; }',
        manifest: nullableManifest,
        functionName: 'maybeName',
      );
      expect(
        E0PatchRuntime.installBytes(
          patch,
          appId: 'app',
          releaseId: 'nullable',
          buildFingerprint: nullableManifest.buildFingerprint,
          functions: _functions(nullableManifest),
          signatures: _signatures(nullableManifest),
          receivers: _receivers(nullableManifest),
        ),
        isTrue,
      );
      final program = E0PatchRuntime.lookup(0)!;
      expect(E0PatchRuntime.invoke(program, <Object?>[null]).value, isNull);
      expect(E0PatchRuntime.invoke(program, <Object?>['Ada']).value, 'Ada');
    });

    test('materializes empty collection literals with the declared type', () {
      final patch = E0PatchCompiler().compile(
        source: 'List<int> filterValues(List<int> values) { return <int>[]; }',
        manifest: manifest,
        functionName: 'filterValues',
      );
      expect(
        E0PatchRuntime.installBytes(
          patch,
          appId: 'app',
          releaseId: 'typed-release',
          buildFingerprint: manifest.buildFingerprint,
          functions: _functions(manifest),
          signatures: _signatures(manifest),
          receivers: _receivers(manifest),
        ),
        isTrue,
      );
      final function = manifest.functions.singleWhere(
        (item) => item.name == 'filterValues',
      );
      final result = E0PatchRuntime.invoke(
        E0PatchRuntime.lookup(function.slot)!,
        <Object?>[
          <int>[1],
        ],
      );
      expect(result.value, isA<List<int>>());
      expect(result.value, isEmpty);
    });

    test('short-circuits && before an unsafe right operand', () {
      final guardedManifest = E0SourceTransformer()
          .transform(
            source:
                'bool guarded(bool enabled, List<int> values) { return enabled; }\n'
                'void main(List<String> args) {}',
            packageName: 'fixture',
            logicalLibraryPath: 'lib/guarded.dart',
            appId: 'app',
            releaseId: 'guarded',
            buildFingerprint: 'test-build-1',
          )
          .manifest;
      final patch = E0PatchCompiler().compile(
        source:
            'bool guarded(bool enabled, List<int> values) { '
            'return enabled && values[99] == 1; }',
        manifest: guardedManifest,
        functionName: 'guarded',
      );
      expect(
        E0PatchRuntime.installBytes(
          patch,
          appId: 'app',
          releaseId: 'guarded',
          buildFingerprint: guardedManifest.buildFingerprint,
          functions: _functions(guardedManifest),
          signatures: _signatures(guardedManifest),
          receivers: _receivers(guardedManifest),
        ),
        isTrue,
      );
      final skipped = E0PatchRuntime.invoke(
        E0PatchRuntime.lookup(0)!,
        <Object?>[false, <int>[]],
      );
      expect(skipped.isSuccess, isTrue);
      expect(skipped.value, isFalse);
      expect(E0PatchRuntime.lookup(0), isNotNull);

      final evaluated = E0PatchRuntime.invoke(
        E0PatchRuntime.lookup(0)!,
        <Object?>[true, <int>[]],
      );
      expect(evaluated.isSuccess, isFalse);
      expect(evaluated.isGuestThrow, isTrue);
      expect(
        evaluated.guestThrow!.value,
        isA<E0HostFailure>().having(
          (failure) => failure.boundaryId,
          'boundary',
          'collection.list.index.read',
        ),
      );
      expect(E0PatchRuntime.lookup(0), isNotNull);
    });
  });

  group('compiler and activation boundaries', () {
    test('container bytes are deterministic', () {
      const source = "String greet(String name) { return 'Hello ' + name; }";
      final first = E0PatchCompiler().compile(
        source: source,
        manifest: manifest,
        functionName: 'greet',
      );
      final second = E0PatchCompiler().compile(
        source: source,
        manifest: manifest,
        functionName: 'greet',
      );
      expect(first, second);
    });

    test('rejects mismatched declaration and expression return types', () {
      expect(
        () => E0PatchCompiler().compile(
          source: 'int greet(String name) { return 1; }',
          manifest: manifest,
          functionName: 'greet',
        ),
        throwsFormatException,
      );
      expect(
        () => E0PatchCompiler().compile(
          source: 'String greet(String name) { return 1; }',
          manifest: manifest,
          functionName: 'greet',
        ),
        throwsFormatException,
      );
    });

    test(
      'rejects dynamic host parameters and unsupported expressions clearly',
      () {
        final dynamicTransformation = E0SourceTransformer().transform(
          source:
              'dynamic unsafe(dynamic value) { return value; }\n'
              'void main(List<String> args) {}',
          packageName: 'fixture',
          logicalLibraryPath: 'lib/unsafe.dart',
          appId: 'app',
          releaseId: 'unsafe',
          buildFingerprint: 'test-build-1',
        );
        expect(dynamicTransformation.manifest.functions, isEmpty);
        expect(dynamicTransformation.exclusions.single, contains('explicit'));
        expect(
          () => E0PatchCompiler().compile(
            source: 'String greet(String name) { return name.toUpperCase(); }',
            manifest: manifest,
            functionName: 'greet',
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Unsupported expression'),
            ),
          ),
        );
      },
    );

    test('rejects a patch signature changed after compilation', () {
      final patch = E0PatchCompiler().compile(
        source: "String greet(String name) { return 'Hi ' + name; }",
        manifest: manifest,
        functionName: 'greet',
      );
      final wrongSignatures = _signatures(manifest);
      wrongSignatures[manifest.functions
          .singleWhere((item) => item.name == 'greet')
          .id] = E0FunctionSignature.legacyInt2
          .encode();
      expect(
        E0PatchRuntime.installBytes(
          patch,
          appId: 'app',
          releaseId: 'typed-release',
          buildFingerprint: manifest.buildFingerprint,
          functions: _functions(manifest),
          signatures: wrongSignatures,
          receivers: _receivers(manifest),
        ),
        isFalse,
      );
      expect(E0PatchRuntime.lookup(0), isNull);
      expect(E0PatchRuntime.lastRejection, contains('signature mismatch'));
    });

    test('malformed host arguments fail closed and restore AOT fallback', () {
      final patch = E0PatchCompiler().compile(
        source:
            'List<int> filterValues(List<int> values) { '
            'return <int>[values[0]]; }',
        manifest: manifest,
        functionName: 'filterValues',
      );
      expect(
        E0PatchRuntime.installBytes(
          patch,
          appId: 'app',
          releaseId: 'typed-release',
          buildFingerprint: manifest.buildFingerprint,
          functions: _functions(manifest),
          signatures: _signatures(manifest),
          receivers: _receivers(manifest),
        ),
        isTrue,
      );
      final function = manifest.functions.singleWhere(
        (item) => item.name == 'filterValues',
      );
      final result = E0PatchRuntime.invoke(
        E0PatchRuntime.lookup(function.slot)!,
        <Object?>[
          <Object?>[1, 'bad'],
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(E0PatchRuntime.lookup(function.slot), isNull);
      expect(E0PatchRuntime.lastRejection, contains('must be int'));
    });
  });
}

Map<String, int> _functions(E0ReleaseManifest manifest) => <String, int>{
  for (final function in manifest.functions) function.id: function.slot,
};

Map<String, String> _signatures(E0ReleaseManifest manifest) => <String, String>{
  for (final function in manifest.functions)
    function.id: function.signature.encode(),
};

Map<String, String> _receivers(E0ReleaseManifest manifest) => <String, String>{
  for (final function in manifest.functions)
    function.id: function.receiver.encode(),
};

const _releaseSource = '''
String greet(String name) { return 'Hello, ' + name; }
bool isEligible(int age, bool verified) { return age >= 18 && verified; }
double calculate(double amount, double rate) { return amount + rate; }
Map<String, dynamic> transform(Map<String, dynamic> input) { return input; }
List<int> filterValues(List<int> values) { return values; }
void main(List<String> args) {}
''';
