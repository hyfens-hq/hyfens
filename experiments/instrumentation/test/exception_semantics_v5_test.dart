import 'dart:convert';
import 'dart:io';

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
          logicalLibraryPath: 'lib/exceptions.dart',
          appId: 'app',
          releaseId: 'exceptions-v5',
          buildFingerprint: 'test-build-1',
        )
        .manifest;
  });

  group('v5 exception compiler and runtime', () {
    test('distinguishes uncaught guest throw without deactivating patch', () {
      final bytes = _compileBytes(manifest, 'scenario', '''
int scenario(int value) {
  throw value;
}
''');
      expect(_install(manifest, bytes), isTrue);
      final target = manifest.functions.singleWhere(
        (function) => function.name == 'scenario',
      );

      final result = E0PatchRuntime.invoke(
        E0PatchRuntime.lookup(target.slot)!,
        <Object?>[41],
      );
      expect(result.outcome, E0InvocationOutcome.guestThrow);
      expect(result.guestThrow!.value, 41);
      expect(result.guestThrow!.trace.functionId, target.id);
      expect(result.guestThrow!.trace.pc, greaterThanOrEqualTo(0));
      expect(E0PatchRuntime.lookup(target.slot), isNotNull);
      expect(E0PatchRuntime.lastRejection, isNull);
    });

    test('catch-all handles a bounded guest throw', () {
      final program = _compile(manifest, 'scenario', '''
int scenario(int value) {
  try {
    throw value;
  } catch (_) {
    return 17;
  }
}
''');
      expect(E0Interpreter.executeValues(program, <Object?>[4]), 17);
    });

    test(
      'copies and bounds a thrown collection without exposing host mutation',
      () {
        final program = _compile(manifest, 'throwList', '''
int throwList(List<int> values) {
  values.add(9);
  throw values;
}
''');
        final host = <int>[1];
        E0GuestThrow? guest;
        try {
          E0Interpreter.executeValues(program, <Object?>[host]);
        } on E0GuestThrow catch (error) {
          guest = error;
        }
        expect(guest!.value, <int>[1, 9]);
        expect(host, <int>[1]);
        expect(
          () => (guest!.value as List<int>).add(10),
          throwsUnsupportedError,
        );
      },
    );

    test('finally runs once on normal and caught paths', () {
      final program = _compile(manifest, 'scenario', '''
int scenario(int value) {
  int count = 0;
  try {
    if (value < 0) throw value;
    count += 2;
  } catch (_) {
    count += 4;
  } finally {
    count += 8;
  }
  return count;
}
''');
      expect(E0Interpreter.executeValues(program, <Object?>[1]), 10);
      expect(E0Interpreter.executeValues(program, <Object?>[-1]), 12);
    });

    test('accepts empty handlers and a trailing branch to completion', () {
      final program = _compile(manifest, 'scenario', '''
int scenario(int value) {
  try {
    if (value < 0) throw value;
  } catch (_) {
  } finally {
  }
  return value;
}
''');
      expect(E0Interpreter.executeValues(program, <Object?>[2]), 2);
      expect(E0Interpreter.executeValues(program, <Object?>[-2]), -2);
    });

    test('nested catch/finally and rethrow preserve original guest trace', () {
      final program = _compile(manifest, 'scenario', '''
int scenario(int value) {
  try {
    try {
      throw value;
    } catch (_) {
      rethrow;
    } finally {
      value;
    }
  } finally {
    value;
  }
}
''');
      E0GuestThrow? guest;
      try {
        E0Interpreter.executeValues(program, <Object?>[33]);
      } on E0GuestThrow catch (error) {
        guest = error;
      }
      expect(guest, isNotNull);
      expect(guest!.value, 33);
      final throwPc = program.code.indexOf(E0Opcode.throwValue.code);
      expect(guest.trace.pc, throwPc);
    });

    test('return traverses finally and return in finally overrides it', () {
      final preserved = _compile(manifest, 'scenario', '''
int scenario(int value) {
  try {
    return value + 1;
  } finally {
    value;
  }
}
''');
      expect(E0Interpreter.executeValues(preserved, <Object?>[3]), 4);

      final overridden = _compile(manifest, 'scenario', '''
int scenario(int value) {
  try {
    return value + 1;
  } finally {
    return 99;
  }
}
''');
      expect(E0Interpreter.executeValues(overridden, <Object?>[3]), 99);
    });

    test('throw in finally replaces pending return or throw', () {
      final program = _compile(manifest, 'scenario', '''
int scenario(int value) {
  try {
    if (value > 0) return value;
    throw 1;
  } finally {
    throw 88;
  }
}
''');
      for (final value in <int>[1, -1]) {
        expect(
          () => E0Interpreter.executeValues(program, <Object?>[value]),
          throwsA(
            isA<E0GuestThrow>().having((error) => error.value, 'value', 88),
          ),
        );
      }
    });

    test(
      'declared receiver nonfatal Objects become catchable bounded failures',
      () {
        final program = _compile(manifest, 'read', '''
class Service {
  int get value => 0;
  int read(int fallback) {
    try {
      return this.value;
    } catch (_) {
      return fallback;
    }
  }
}
''', className: 'Service');
        for (final thrown in <Object>[
          StateError('state failed'),
          'arbitrary thrown string',
        ]) {
          expect(
            E0Interpreter.executeValues(program, <Object?>[
              71,
            ], receiver: _ThrowingReceiver(program.receiver.id, thrown)),
            71,
          );
        }
      },
    );

    test(
      'uncaught receiver Object crosses only as stable bounded metadata',
      () {
        final program = _compile(manifest, 'read', '''
class Service {
  int get value => 0;
  int read(int fallback) {
    return this.value;
  }
}
''', className: 'Service');
        expect(
          () => E0Interpreter.executeValues(program, <Object?>[
            1,
          ], receiver: _ThrowingReceiver(program.receiver.id, 'secret object')),
          throwsA(
            isA<E0GuestThrow>().having(
              (error) => error.value,
              'value',
              isA<E0HostFailure>()
                  .having((failure) => failure.code, 'code', 'receiverFailure')
                  .having(
                    (failure) => failure.errorKind,
                    'kind',
                    'boundaryFailure',
                  )
                  .having(
                    (failure) => failure.message,
                    'message',
                    'Receiver request failed',
                  )
                  .having(
                    (failure) => failure.boundaryId,
                    'boundary',
                    program.receiver.members.single.id,
                  ),
            ),
          ),
        );
      },
    );

    test(
      'receiver runtime and fatal faults are not translated to guest data',
      () {
        final bytes = _compileBytes(manifest, 'read', '''
class Service {
  int get value => 0;
  int read(int fallback) {
    try { return this.value; } catch (_) { return fallback; }
  }
}
''', className: 'Service');
        expect(_install(manifest, bytes), isTrue);
        final target = manifest.functions.singleWhere(
          (function) => function.name == 'read',
        );
        final installed = E0PatchRuntime.lookup(target.slot)!;
        final runtime = E0PatchRuntime.invoke(
          installed,
          <Object?>[7],
          receiver: _ThrowingReceiver(
            installed.receiver.id,
            const E0RuntimeFault('bridge invariant'),
          ),
        );
        expect(runtime.isRuntimeFault, isTrue);
        expect(E0PatchRuntime.lookup(target.slot), isNull);

        final decoded = _compile(manifest, 'read', '''
class Service {
  int get value => 0;
  int read(int fallback) {
    try { return this.value; } catch (_) { return fallback; }
  }
}
''', className: 'Service');
        expect(
          () => E0Interpreter.executeValues(
            decoded,
            <Object?>[7],
            receiver: _ThrowingReceiver(
              decoded.receiver.id,
              StackOverflowError(),
            ),
          ),
          throwsA(isA<StackOverflowError>()),
        );
      },
    );

    test('collection language failures are catchable guest transfers', () {
      final read = _compile(manifest, 'readList', '''
int readList(List<int> values) {
  try { return values[99]; } catch (_) { return 7; }
}
''');
      expect(
        E0Interpreter.executeValues(read, <Object?>[
          <int>[1],
        ]),
        7,
      );

      final write = _compile(manifest, 'writeList', '''
int writeList(List<int> values) {
  try {
    values[99] = 3;
    return 1;
  } catch (_) {
    return 7;
  }
}
''');
      final host = <int>[1];
      expect(E0Interpreter.executeValues(write, <Object?>[host]), 7);
      expect(host, <int>[1]);

      final map = _compile(manifest, 'readMap', '''
int readMap(Map<String, int> values) {
  try { return values['missing']; } catch (_) { return 7; }
}
''');
      expect(
        E0Interpreter.executeValues(map, <Object?>[
          <String, int>{'x': 1},
        ]),
        7,
      );

      final nullableMap = _compile(manifest, 'readNullableMap', '''
int? readNullableMap(Map<String, int?> values) {
  return values['missing'];
}
''');
      expect(
        E0Interpreter.executeValues(nullableMap, <Object?>[
          <String, int?>{'x': 1},
        ]),
        isNull,
      );

      final target = manifest.functions.singleWhere(
        (function) => function.name == 'readList',
      );
      final forgedIteration = E0PatchProgram(
        functionId: target.id,
        slot: target.slot,
        signature: target.signature,
        receiver: target.receiver,
        constants: const <int>[99],
        code: <int>[
          E0Opcode.loadArgument.code,
          0,
          E0Opcode.loadConstant.code,
          0,
          E0Opcode.iterationValue.code,
          E0Opcode.returnValue.code,
        ],
      );
      E0Interpreter.validate(forgedIteration);
      expect(
        () => E0Interpreter.executeValues(forgedIteration, <Object?>[
          <int>[1],
        ]),
        throwsA(
          isA<E0GuestThrow>().having(
            (guest) => (guest.value as E0HostFailure).boundaryId,
            'boundary',
            'collection.iteration.read',
          ),
        ),
      );
    });

    test('uncaught collection failure keeps patch active', () {
      final bytes = _compileBytes(manifest, 'readList', '''
int readList(List<int> values) {
  return values[99];
}
''');
      expect(_install(manifest, bytes), isTrue);
      final target = manifest.functions.singleWhere(
        (function) => function.name == 'readList',
      );
      final result = E0PatchRuntime.invoke(
        E0PatchRuntime.lookup(target.slot)!,
        <Object?>[
          <int>[1],
        ],
      );
      expect(result.isGuestThrow, isTrue);
      expect(
        result.guestThrow!.value,
        isA<E0HostFailure>()
            .having(
              (failure) => failure.boundaryId,
              'boundary',
              'collection.list.index.read',
            )
            .having((failure) => failure.code, 'code', 'range'),
      );
      expect(E0PatchRuntime.lookup(target.slot), isNotNull);
    });

    test('collection size budget remains an uncatchable runtime fault', () {
      final program = _compile(manifest, 'addList', '''
int addList(List<int> values) {
  try {
    values.add(1);
    return 1;
  } catch (_) {
    return 7;
  }
}
''');
      expect(
        () => E0Interpreter.executeValues(program, <Object?>[
          List<int>.filled(1024, 0),
        ]),
        throwsA(isA<E0RuntimeFault>()),
      );
    });

    test(
      'runtime fault deactivates patch and remains distinct from guest throw',
      () {
        final bytes = _compileBytes(manifest, 'spin', '''
int spin(int value) {
  int current = value;
  try {
    while (true) {
      current += 1;
    }
    return current;
  } catch (_) {
    return 7;
  }
}
''');
        expect(_install(manifest, bytes), isTrue);
        final target = manifest.functions.singleWhere(
          (function) => function.name == 'spin',
        );
        final diagnostics = <String>[];
        E0PatchRuntime.configureFunctionContexts(
          <String, E0RuntimeFunctionContext>{
            target.id: E0RuntimeFunctionContext(
              functionId: target.id,
              functionName: target.name,
              logicalUri: target.identity.libraryUri,
            ),
          },
        );
        E0PatchRuntime.configureDiagnosticSink(diagnostics.add);
        final result = E0PatchRuntime.invoke(
          E0PatchRuntime.lookup(target.slot)!,
          <Object?>[0],
        );
        expect(result.outcome, E0InvocationOutcome.runtimeFault);
        expect(E0PatchRuntime.lookup(target.slot), isNull);
        expect(E0PatchRuntime.lastRejection, contains('budget'));
        expect(diagnostics, hasLength(1));
        expect(
          diagnostics.single,
          allOf(
            contains(E0RuntimeDiagnosticCode.budget),
            contains('spin'),
            contains('package:fixture/exceptions.dart'),
          ),
        );
        expect(
          diagnostics.single,
          isNot(contains(Directory.current.absolute.path)),
        );
        expect(diagnostics.single, isNot(contains(r'\\')));
      },
    );

    test(
      'rejects unsupported catches, catch binding reads, null throw, and break',
      () {
        final cases = <String, String>{
          'Typed': '''
int scenario(int value) {
  try { throw value; } on Exception catch (_) { return 1; }
}
''',
          'stack-trace': '''
int scenario(int value) {
  try { throw value; } catch (_, stack) { return 1; }
}
''',
          'cannot be read': '''
int scenario(int value) {
  try { throw value; } catch (error) { return error; }
}
''',
          'non-null': '''
int scenario(int value) {
  throw null;
}
''',
          'break crossing': '''
int scenario(int value) {
  while (true) {
    try { break; } finally { value; }
  }
  return value;
}
''',
        };
        for (final entry in cases.entries) {
          expect(
            () => _compile(manifest, 'scenario', entry.value),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message.toString(),
                'message',
                contains(entry.key),
              ),
            ),
            reason: entry.key,
          );
        }
      },
    );
  });

  group('v5 handler verifier', () {
    test('rejects malformed ranges and illegal handler transitions', () {
      final valid = _compile(manifest, 'scenario', '''
int scenario(int value) {
  try { return value; } finally { value; }
}
''');
      final handler = valid.handlers.single;
      final malformed = <E0PatchProgram>[
        _replaceHandler(
          valid,
          E0ExceptionHandler(
            id: 1,
            tryStart: handler.tryStart,
            tryEnd: handler.tryEnd,
            catchStart: handler.catchStart,
            catchEnd: handler.catchEnd,
            finallyStart: handler.finallyStart,
            finallyEnd: handler.finallyEnd,
            afterPc: handler.afterPc,
          ),
        ),
        _replaceHandler(
          valid,
          E0ExceptionHandler(
            id: 0,
            tryStart: handler.tryEnd,
            tryEnd: handler.tryStart,
            catchStart: handler.catchStart,
            catchEnd: handler.catchEnd,
            finallyStart: handler.finallyStart,
            finallyEnd: handler.finallyEnd,
            afterPc: handler.afterPc,
          ),
        ),
        E0PatchProgram(
          functionId: valid.functionId,
          slot: valid.slot,
          signature: valid.signature,
          receiver: valid.receiver,
          constants: valid.constants,
          locals: valid.locals,
          handlers: valid.handlers,
          code: <int>[
            ...valid.code.take(handler.finallyEnd!),
            E0Opcode.completeTry.code,
            0,
            ...valid.code.skip(handler.finallyEnd! + 2),
          ],
        ),
      ];
      for (final program in malformed) {
        expect(() => E0Interpreter.validate(program), throwsFormatException);
      }
    });

    test('rejects unknown handler fields at container decode', () {
      final bytes = _compileBytes(manifest, 'scenario', '''
int scenario(int value) {
  try { return value; } finally { value; }
}
''');
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      final handlers = json['handlers']! as List<Object?>;
      final handler = handlers.single! as Map<String, Object?>;
      handler['unknown'] = true;
      expect(_install(manifest, utf8.encode(jsonEncode(json))), isFalse);
      expect(E0PatchRuntime.lastRejection, contains('handler fields'));
    });

    test('rejects partially overlapping regions before execution', () {
      final target = manifest.functions.singleWhere(
        (function) => function.name == 'scenario',
      );
      final program = E0PatchProgram(
        functionId: target.id,
        slot: target.slot,
        signature: target.signature,
        constants: const <int>[1],
        code: <int>[
          E0Opcode.enterTry.code,
          0,
          E0Opcode.enterTry.code,
          1,
          E0Opcode.loadConstant.code,
          0,
          E0Opcode.completeTry.code,
          0,
          E0Opcode.loadConstant.code,
          0,
          E0Opcode.pop.code,
          E0Opcode.completeFinally.code,
          0,
          E0Opcode.completeTry.code,
          1,
          E0Opcode.loadConstant.code,
          0,
          E0Opcode.pop.code,
          E0Opcode.completeFinally.code,
          1,
          E0Opcode.loadConstant.code,
          0,
          E0Opcode.returnValue.code,
        ],
        handlers: const <E0ExceptionHandler>[
          E0ExceptionHandler(
            id: 0,
            tryStart: 2,
            tryEnd: 6,
            catchStart: null,
            catchEnd: null,
            finallyStart: 8,
            finallyEnd: 11,
            afterPc: 13,
          ),
          E0ExceptionHandler(
            id: 1,
            tryStart: 4,
            tryEnd: 13,
            catchStart: null,
            catchEnd: null,
            finallyStart: 15,
            finallyEnd: 18,
            afterPc: 20,
          ),
        ],
      );
      expect(
        () => E0Interpreter.validate(program),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('partially overlap'),
          ),
        ),
      );
    });

    test('rejects a direct jump into a finally section', () {
      final valid = _compile(manifest, 'scenario', '''
int scenario(int value) {
  if (value > 0) {
    try { return 1; } finally { value; }
  }
  return 2;
}
''');
      final handler = valid.handlers.single;
      final code = valid.code.toList();
      final jump = code.indexOf(E0Opcode.jumpIfFalse.code);
      code[jump + 1] = handler.finallyStart!;
      final forged = E0PatchProgram(
        functionId: valid.functionId,
        slot: valid.slot,
        signature: valid.signature,
        receiver: valid.receiver,
        constants: valid.constants,
        code: code,
        locals: valid.locals,
        handlers: valid.handlers,
      );
      expect(
        () => E0Interpreter.validate(forged),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('handler boundary'),
          ),
        ),
      );
    });

    test('rejects more than the bounded handler count', () {
      final valid = _compile(manifest, 'scenario', '''
int scenario(int value) {
  try { return value; } finally { value; }
}
''');
      final forged = E0PatchProgram(
        functionId: valid.functionId,
        slot: valid.slot,
        signature: valid.signature,
        receiver: valid.receiver,
        constants: valid.constants,
        code: valid.code,
        locals: valid.locals,
        handlers: List<E0ExceptionHandler>.filled(33, valid.handlers.single),
      );
      expect(
        () => E0Interpreter.validate(forged),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('limit'),
          ),
        ),
      );
    });
  });
}

final class _ThrowingReceiver implements E0ReceiverCapability {
  const _ThrowingReceiver(this.descriptorId, this.thrown);

  @override
  final String descriptorId;
  final Object thrown;

  @override
  Object? read(int slot) => throw thrown;
}

E0PatchProgram _replaceHandler(
  E0PatchProgram program,
  E0ExceptionHandler handler,
) => E0PatchProgram(
  functionId: program.functionId,
  slot: program.slot,
  signature: program.signature,
  receiver: program.receiver,
  constants: program.constants,
  code: program.code,
  locals: program.locals,
  handlers: <E0ExceptionHandler>[handler],
);

E0PatchProgram _compile(
  E0ReleaseManifest manifest,
  String name,
  String source, {
  String? className,
}) => E0PatchContainer.decode(
  _compileBytes(manifest, name, source, className: className),
  expectedAppId: manifest.appId,
  expectedReleaseId: manifest.releaseId,
  expectedBuildFingerprint: manifest.buildFingerprint,
  expectedFunctions: _functions(manifest),
  expectedSignatures: _signatureObjects(manifest),
  expectedReceivers: _receiverObjects(manifest),
);

List<int> _compileBytes(
  E0ReleaseManifest manifest,
  String name,
  String source, {
  String? className,
}) => E0PatchCompiler().compile(
  source: source,
  manifest: manifest,
  functionName: name,
  className: className,
);

bool _install(E0ReleaseManifest manifest, List<int> bytes) =>
    E0PatchRuntime.installBytes(
      bytes,
      appId: manifest.appId,
      releaseId: manifest.releaseId,
      buildFingerprint: manifest.buildFingerprint,
      functions: _functions(manifest),
      signatures: _signatures(manifest),
      receivers: _receivers(manifest),
    );

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

Map<String, E0FunctionSignature> _signatureObjects(
  E0ReleaseManifest manifest,
) => <String, E0FunctionSignature>{
  for (final function in manifest.functions) function.id: function.signature,
};

Map<String, E0ReceiverDescriptor> _receiverObjects(
  E0ReleaseManifest manifest,
) => <String, E0ReceiverDescriptor>{
  for (final function in manifest.functions) function.id: function.receiver,
};

const _releaseSource = '''
int scenario(int value) { return value; }
int spin(int value) { return value; }
int throwList(List<int> values) { return values.length; }
int readList(List<int> values) { return values[0]; }
int writeList(List<int> values) { values[0] = 1; return values[0]; }
int addList(List<int> values) { values.add(1); return values.length; }
int readMap(Map<String, int> values) { return values['x']!; }
int? readNullableMap(Map<String, int?> values) { return values['x']; }
class Service {
  int get value => 4;
  int read(int fallback) { return this.value; }
}
void main(List<String> arguments) {}
''';
