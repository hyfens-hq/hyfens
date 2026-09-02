import 'dart:convert';

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
          logicalLibraryPath: 'lib/control.dart',
          appId: 'app',
          releaseId: 'control-v4',
          buildFingerprint: 'test-build-1',
        )
        .manifest;
  });

  group('v4 compiler and runtime', () {
    test(
      'lowers typed locals, nested branches, loops, switch, and early return',
      () {
        final program = _compile(manifest, 'control', '''
int control(int seed, List<int> values) {
  int total = seed;
  if (values.contains(seed)) {
    if (seed > 0) {
      total += 1;
    } else {
      total -= 1;
    }
  } else {
    total += 2;
  }
  int i = 0;
  while (i < values.length) {
    total += values[i];
    i++;
  }
  for (int j = 0; j < 2; j++) {
    total += j;
  }
  switch (total) {
    case 10:
      return 100;
    case 11:
      return 110;
    default:
      return total;
  }
}
''');

        expect(
          E0Interpreter.executeValues(program, <Object?>[
            1,
            <int>[1, 2, 3],
          ]),
          9,
        );
        expect(
          E0Interpreter.executeValues(program, <Object?>[
            2,
            <int>[2, 3],
          ]),
          9,
        );
      },
    );

    test('supports List, Set, Map mutation and bounded iteration', () {
      final list = _compile(manifest, 'mutateList', '''
List<int> mutateList(List<int> values) {
  List<int> output = values;
  output[0] = output[0] * 2;
  output.add(9);
  return output;
}
''');
      final host = <int>[3, 4];
      expect(E0Interpreter.executeValues(list, <Object?>[host]), <int>[
        6,
        4,
        9,
      ]);
      expect(host, <int>[3, 4], reason: 'host List must not be mutated');

      final set = _compile(manifest, 'setTotal', '''
int setTotal(Set<int> values) {
  Set<int> copy = values;
  copy.add(4);
  int total = 0;
  for (int value in copy) {
    total += value;
  }
  if (copy.contains(4)) return total;
  return -1;
}
''');
      final hostSet = <int>{1, 2};
      expect(E0Interpreter.executeValues(set, <Object?>[hostSet]), 7);
      expect(hostSet, <int>{1, 2});

      final map = _compile(manifest, 'mapTotal', '''
int mapTotal(Map<String, int> values) {
  Map<String, int> copy = values;
  copy['extra'] = 4;
  int total = 0;
  for (String key in copy.keys) {
    total += copy[key];
  }
  return total;
}
''');
      final hostMap = <String, int>{'base': 3};
      expect(E0Interpreter.executeValues(map, <Object?>[hostMap]), 7);
      expect(hostMap, <String, int>{'base': 3});
    });

    test('preserves mutable identity shared across host arguments', () {
      final program = _compile(manifest, 'alias', '''
List<int> alias(List<int> left, List<int> right) {
  left.add(7);
  right[0] = 9;
  return left;
}
''');
      final shared = <int>[1, 2];
      expect(
        E0Interpreter.executeValues(program, <Object?>[shared, shared]),
        <int>[9, 2, 7],
      );
      expect(shared, <int>[1, 2]);
    });

    test('global instruction budget terminates a compiled loop', () {
      final program = _compile(manifest, 'spin', '''
int spin(int value) {
  int current = value;
  while (true) {
    current += 1;
  }
  return current;
}
''');
      expect(
        () => E0Interpreter.executeValues(program, <Object?>[
          0,
        ], instructionBudget: 20),
        throwsA(isA<E0RuntimeFault>()),
      );
    });

    test('requires explicit switch termination and preserves break', () {
      expect(
        () => _compile(manifest, 'spin', '''
int spin(int value) {
  int result = 0;
  switch (value) {
    case 1:
      result = 5;
    case 2:
      return 7;
    default:
      return 9;
  }
  return result;
}
'''),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('fall through'),
          ),
        ),
      );

      final program = _compile(manifest, 'spin', '''
int spin(int value) {
  int result = 0;
  switch (value) {
    case 1:
      result = 5;
      break;
    case 2:
      return 7;
    default:
      return 9;
  }
  return result;
}
''');
      expect(E0Interpreter.executeValues(program, <Object?>[1]), 5);
      expect(E0Interpreter.executeValues(program, <Object?>[2]), 7);
    });

    test('Map.keys and Set for-in preserve insertion order', () {
      final map = _compile(manifest, 'mapOrder', '''
String mapOrder(Map<String, int> values) {
  String order = '';
  for (String key in values.keys) {
    order += key;
  }
  return order;
}
''');
      expect(
        E0Interpreter.executeValues(map, <Object?>[
          <String, int>{'b': 1, 'a': 2, 'c': 3},
        ]),
        'bac',
      );

      final set = _compile(manifest, 'setOrder', '''
int setOrder(Set<int> values) {
  int order = 0;
  for (int value in values) {
    order = order * 10 + value;
  }
  return order;
}
''');
      expect(
        E0Interpreter.executeValues(set, <Object?>[
          <int>{3, 1, 2},
        ]),
        312,
      );
    });

    test('installs and dispatches a collection patch through the integration boundary', () {
      final bytes = E0PatchCompiler().compile(
        source: '''
List<int> mutateList(List<int> values) {
  List<int> output = values;
  output.add(8);
  return output;
}
''',
        manifest: manifest,
        functionName: 'mutateList',
      );
      expect(
        E0PatchRuntime.installBytes(
          bytes,
          appId: 'app',
          releaseId: 'control-v4',
          buildFingerprint: manifest.buildFingerprint,
          functions: _functions(manifest),
          signatures: _signatures(manifest),
          receivers: _receivers(manifest),
        ),
        isTrue,
      );
      final target = manifest.functions.singleWhere(
        (item) => item.name == 'mutateList',
      );
      final host = <int>[1];
      final result = E0PatchRuntime.invoke(
        E0PatchRuntime.lookup(target.slot)!,
        <Object?>[host],
      );
      expect(result.isSuccess, isTrue);
      expect(result.value, <int>[1, 8]);
      expect(host, <int>[1]);
    });
  });

  group('v4 fail-closed boundaries', () {
    test(
      'verifier rejects uninitialized, mistyped, and invalid local slots',
      () {
        final function = manifest.functions.first;
        expect(
          () => E0Interpreter.validate(
            E0PatchProgram(
              functionId: function.id,
              slot: function.slot,
              signature: const E0FunctionSignature(
                parameters: <E0ValueSchema>[],
                returnSchema: E0ValueSchema.integer,
              ),
              locals: const <E0ValueSchema>[E0ValueSchema.integer],
              constants: const <Object?>[],
              code: const <int>[16, 0, 9],
            ),
          ),
          throwsFormatException,
        );
        expect(
          () => E0Interpreter.validate(
            E0PatchProgram(
              functionId: function.id,
              slot: function.slot,
              signature: const E0FunctionSignature(
                parameters: <E0ValueSchema>[],
                returnSchema: E0ValueSchema.integer,
              ),
              locals: const <E0ValueSchema>[E0ValueSchema.integer],
              constants: const <Object?>['wrong'],
              code: const <int>[2, 0, 17, 0, 16, 0, 9],
            ),
          ),
          throwsFormatException,
        );
        expect(
          () => E0Interpreter.validate(
            E0PatchProgram(
              functionId: function.id,
              slot: function.slot,
              constants: const <Object?>[],
              code: const <int>[16, 99, 9],
            ),
          ),
          throwsFormatException,
        );
        expect(
          () => E0Interpreter.validate(
            E0PatchProgram(
              functionId: function.id,
              slot: function.slot,
              signature: const E0FunctionSignature(
                parameters: <E0ValueSchema>[],
                returnSchema: E0ValueSchema.integer,
              ),
              locals: const <E0ValueSchema>[E0ValueSchema.integer],
              constants: const <Object?>[true, 1],
              code: const <int>[2, 0, 8, 8, 2, 1, 17, 0, 16, 0, 9],
            ),
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('uninitialized'),
            ),
          ),
        );
      },
    );

    test('runtime fault after guest mutation leaves host input intact', () {
      final program = _compile(manifest, 'mutateList', '''
List<int> mutateList(List<int> values) {
  List<int> output = values;
  output.add(8);
  output[99] = 2;
  return output;
}
''');
      final host = <int>[1];
      expect(
        () => E0Interpreter.executeValues(program, <Object?>[host]),
        throwsA(anything),
      );
      expect(host, <int>[1]);
    });

    test(
      'compiler rejects non-definite locals and executes bounded closures',
      () {
        expect(
          () => _compile(manifest, 'spin', '''
int spin(int value) {
  int result;
  if (value > 0) result = value;
  return result;
}
'''),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('uninitialized'),
            ),
          ),
        );
        final mapped = _compile(
          manifest,
          'mutateList',
          'List<int> mutateList(List<int> values) { return values.map((int value) { return value + 1; }).toList(); }',
        );
        expect(
          E0Interpreter.executeValues(mapped, <Object?>[
            <int>[1, 2],
          ]),
          <int>[2, 3],
        );
        expect(
          () => _compile(manifest, 'spin', '''
int spin(int value) {
  final int result = value;
  result = 3;
  return result;
}
'''),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('final local'),
            ),
          ),
        );
      },
    );

    test('Set wire values are canonical, bounded, and reject duplicates', () {
      final value = E0Value.infer(<int>{3, 1, 2});
      final first = E0ValueCodec.encode(value);
      final second = E0ValueCodec.encode(E0Value.infer(<int>{2, 3, 1}));
      expect(first, second);
      expect(
        E0ValueCodec.decode(first)
            .toHost(const E0ValueSchema.set(E0ValueSchema.integer)),
        <int>{1, 2, 3},
      );

      expect(
        () => E0Value.fromJson(<String, Object?>{
          't': 'Set',
          'v': <Object?>[
            <String, Object?>{'t': 'int', 'v': 1},
            <String, Object?>{'t': 'int', 'v': 1},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => E0Value.fromHost(<int>{
          for (
            var index = 0;
            index <= E0ValueCodec.maxCollectionEntries;
            index++
          )
            index,
        }, const E0ValueSchema.set(E0ValueSchema.integer)),
        throwsFormatException,
      );
    });

    test('v4 manifest includes deterministic local schemas and rejects malformed locals', () {
      final bytes = E0PatchCompiler().compile(
        source: 'int spin(int value) { int copy = value; return copy; }',
        manifest: manifest,
        functionName: 'spin',
      );
      final again = E0PatchCompiler().compile(
        source: 'int spin(int value) { int copy = value; return copy; }',
        manifest: manifest,
        functionName: 'spin',
      );
      expect(bytes, again);
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      expect(json['formatVersion'], e0PatchFormatVersion);
      expect(json['locals'], hasLength(1));
      json['locals'] = <Object?>[
        <String, Object?>{'kind': 'int'},
      ];
      expect(
        E0PatchRuntime.installBytes(
          utf8.encode(jsonEncode(json)),
          appId: 'app',
          releaseId: 'control-v4',
          buildFingerprint: manifest.buildFingerprint,
          functions: _functions(manifest),
          signatures: _signatures(manifest),
          receivers: _receivers(manifest),
        ),
        isFalse,
      );
    });
  });
}

E0PatchProgram _compile(
  E0ReleaseManifest manifest,
  String name,
  String source,
) {
  final bytes = E0PatchCompiler().compile(
    source: source,
    manifest: manifest,
    functionName: name,
  );
  return E0PatchContainer.decode(
    bytes,
    expectedAppId: 'app',
    expectedReleaseId: 'control-v4',
    expectedBuildFingerprint: manifest.buildFingerprint,
    expectedFunctions: _functions(manifest),
    expectedSignatures: {
      for (final function in manifest.functions)
        function.id: function.signature,
    },
    expectedReceivers: {
      for (final function in manifest.functions) function.id: function.receiver,
    },
  );
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
int control(int seed, List<int> values) { return seed; }
List<int> mutateList(List<int> values) { return values; }
int setTotal(Set<int> values) { return 0; }
int mapTotal(Map<String, int> values) { return 0; }
List<int> alias(List<int> left, List<int> right) { return left; }
int spin(int value) { return value; }
String mapOrder(Map<String, int> values) { return ''; }
int setOrder(Set<int> values) { return 0; }
void main(List<String> arguments) {}
''';
