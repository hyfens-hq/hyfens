import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

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
final _error = E0AsyncCapabilityDescriptor(
  id: 'e0.test.future.error',
  sourceName: 'hostError',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.integer],
  result: E0ValueSchema.integer,
);
final _never = E0AsyncCapabilityDescriptor(
  id: 'e0.test.future.never',
  sourceName: 'hostNever',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.integer],
  result: E0ValueSchema.integer,
);
final _wrong = E0AsyncCapabilityDescriptor(
  id: 'e0.test.future.wrong-result',
  sourceName: 'hostWrong',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.integer],
  result: E0ValueSchema.integer,
);
final _map = E0AsyncCapabilityDescriptor(
  id: 'e0.test.future.map',
  sourceName: 'hostMap',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.map(E0ValueSchema.supportedValue)],
  result: E0ValueSchema.map(E0ValueSchema.supportedValue),
);

void main() {
  late E0ReleaseManifest manifest;

  setUp(() {
    E0PatchRuntime.reset();
    _configureCapabilities();
    manifest = E0SourceTransformer()
        .transform(
          source: _releaseSource,
          packageName: 'fixture',
          logicalLibraryPath: 'lib/async.dart',
          appId: 'app',
          releaseId: 'async-v6',
          buildFingerprint: 'test-build-1',
          capabilities: <E0AsyncCapabilityDescriptor>[
            _immediate,
            _delayed,
            _error,
            _never,
            _wrong,
            _map,
          ],
        )
        .manifest;
  });

  group('v6 compiler and metadata', () {
    test('lowers an ordinary Future<int> async function deterministically', () {
      const source = '''
Future<int> calculateAsync(int value) async {
  final int first = await hostImmediate(value);
  final int second = await hostDelayed(first);
  return second + 1;
}
''';
      final first = _compileBytes(manifest, 'calculateAsync', source);
      final second = _compileBytes(manifest, 'calculateAsync', source);
      expect(first, second);
      final program = _decode(manifest, first);
      expect(program.signature.isAsync, isTrue);
      expect(program.asyncPoints, hasLength(2));
      expect(program.capabilities.map((item) => item.id), <String>[
        _immediate.id,
        _delayed.id,
      ]);
      expect(
        program.code.where((word) => word == E0Opcode.awaitValue.code),
        hasLength(2),
      );
    });

    test(
      'rejects unknown calls, nested Future<Result>, async*, and closures',
      () {
        expect(
          () => _compileBytes(manifest, 'calculateAsync', '''
Future<int> calculateAsync(int value) async {
  return await arbitraryNetworkCall(value);
}
'''),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Unsupported async capability'),
            ),
          ),
        );
        expect(
          () => E0SourceTransformer().transform(
            source: 'Future<Result> f(int x) async { throw x; } void main() {}',
            packageName: 'fixture',
            logicalLibraryPath: 'lib/result.dart',
            appId: 'app',
            releaseId: 'r',
            buildFingerprint: 'test-build-1',
          ),
          returnsNormally,
        );
        final resultTransform = E0SourceTransformer().transform(
          source: 'Future<Result> f(int x) async { throw x; } void main() {}',
          packageName: 'fixture',
          logicalLibraryPath: 'lib/result.dart',
          appId: 'app',
          releaseId: 'r',
          buildFingerprint: 'test-build-1',
        );
        expect(resultTransform.manifest.functions, isEmpty);
        expect(resultTransform.exclusions.single, contains('Unsupported'));
        final generatorTransform = E0SourceTransformer().transform(
          source: 'Stream<int> f(int x) async* { yield x; } void main() {}',
          packageName: 'fixture',
          logicalLibraryPath: 'lib/generator.dart',
          appId: 'app',
          releaseId: 'r',
          buildFingerprint: 'test-build-1',
        );
        expect(generatorTransform.manifest.functions, isEmpty);
        expect(generatorTransform.exclusions.single, contains('generator'));
        expect(
          () => _compileBytes(manifest, 'calculateAsync', '''
Future<int> calculateAsync(int value) async {
  final int multiplier = 2;
  final callback = (int item) { return item * multiplier; };
  return callback(value);
}
'''),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              anyOf(
                contains('explicit supported Dart type'),
                contains('Closures'),
              ),
            ),
          ),
        );
      },
    );

    test('closure spike fails explicitly for capture and nested scopes', () {
      for (final source in <String>[
        '''
Future<int> closureAsync(List<int> values) async {
  final int multiplier = 2;
  return values.map((int item) { return item * multiplier; }).first;
}
''',
        '''
Future<int> closureAsync(List<int> values) async {
  int multiplier = 2;
  multiplier += 1;
  return values.where((int item) { return item > multiplier; }).length;
}
''',
        '''
Future<int> closureAsync(List<int> values) async {
  int nested(int item) { return item + values.length; }
  return nested(1);
}
''',
      ]) {
        expect(
          () => _compileBytes(manifest, 'closureAsync', source),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              anyOf(
                contains('closure'),
                contains('Closure'),
                contains('Unsupported statement'),
              ),
            ),
          ),
        );
      }
    });

    test('rejects malformed point, capability, and signature metadata', () {
      final bytes = _compileBytes(manifest, 'calculateAsync', '''
Future<int> calculateAsync(int value) async {
  return await hostImmediate(value);
}
''');
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      final points = json['asyncPoints']! as List<Object?>;
      (points.single! as Map<String, Object?>)['resumePc'] = 999;
      expect(
        () => _decode(manifest, utf8.encode(jsonEncode(json))),
        throwsFormatException,
      );

      final capabilityJson =
          jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      final capabilities = capabilityJson['capabilities']! as List<Object?>;
      (capabilities.single! as Map<String, Object?>)['version'] = 0;
      expect(
        () => _decode(manifest, utf8.encode(jsonEncode(capabilityJson))),
        throwsFormatException,
      );
    });

    test('installation rejects a missing capability', () {
      final bytes = _compileBytes(manifest, 'calculateAsync', '''
Future<int> calculateAsync(int value) async {
  return await hostImmediate(value);
}
''');
      E0PatchRuntime.reset();
      _configureCapabilities(only: <String>{});
      expect(_install(manifest, bytes), isFalse);
      expect(E0PatchRuntime.lastRejection, contains('Missing or incompatible'));
    });

    test('failed N+1 activation preserves and executes known-good N', () async {
      E0PatchRuntime.reset();
      _configureCapabilities(only: <String>{_immediate.id});
      final knownGoodBytes = _compileBytes(manifest, 'calculateAsync', '''
Future<int> calculateAsync(int value) async {
  final int result = await hostImmediate(value);
  return result + 10;
}
''');
      expect(_install(manifest, knownGoodBytes), isTrue);
      final target = manifest.functions.singleWhere(
        (function) => function.name == 'calculateAsync',
      );
      final knownGood = E0PatchRuntime.lookup(target.slot)!;

      expect(
        _install(
          manifest,
          knownGoodBytes.sublist(0, knownGoodBytes.length - 7),
        ),
        isFalse,
      );
      expect(identical(E0PatchRuntime.lookup(target.slot), knownGood), isTrue);

      final incompatibleBytes = _compileBytes(manifest, 'calculateAsync', '''
Future<int> calculateAsync(int value) async {
  return await hostDelayed(value);
}
''');
      expect(_install(manifest, incompatibleBytes), isFalse);
      expect(identical(E0PatchRuntime.lookup(target.slot), knownGood), isTrue);
      expect(
        await E0PatchRuntime.invokeAsync<int>(knownGood, <Object?>[1]),
        12,
      );
    });
  });

  group('v6 continuation runtime', () {
    test(
      'immediate, delayed, and multiple awaits remain non-blocking',
      () async {
        final program = _compile(manifest, 'calculateAsync', '''
Future<int> calculateAsync(int value) async {
  final int first = await hostImmediate(value);
  final int second = await hostDelayed(first);
  return second + 1;
}
''');
        var eventLoopProgress = false;
        Timer.run(() => eventLoopProgress = true);
        final result = E0AsyncInterpreter.execute(program, <Object?>[
          3,
        ], onRuntimeFault: fail);
        await Future<void>.delayed(const Duration(milliseconds: 1));
        expect(eventLoopProgress, isTrue);
        expect(await result, 9);
        expect(E0AsyncInterpreter.activeContinuations, 0);
        expect(E0AsyncInterpreter.debugAttemptDuplicateResume(), isFalse);
      },
    );

    test('Future<Map<String, dynamic>> remains schema-bounded', () async {
      final program = _compile(manifest, 'mapAsync', '''
Future<Map<String, dynamic>> mapAsync(Map<String, dynamic> input) async {
  return await hostMap(input);
}
''');
      expect(
        await E0AsyncInterpreter.execute(program, <Object?>[
          <String, Object?>{'name': 'Ada', 'count': 2},
        ], onRuntimeFault: fail),
        <String, Object?>{'count': 3, 'name': 'Ada'},
      );
    });

    test('preserves invocation zone across every resume', () async {
      final seen = <String?>[];
      E0PatchRuntime.reset();
      _configureCapabilities(
        overrides: <String, E0CapabilityHandler>{
          for (final descriptor in <E0AsyncCapabilityDescriptor>[
            _immediate,
            _delayed,
          ])
            descriptor.id: (arguments) async {
              seen.add(Zone.current[#request] as String?);
              await Future<void>.delayed(Duration.zero);
              seen.add(Zone.current[#request] as String?);
              return (arguments.single! as int) + 1;
            },
        },
      );
      final program = _compile(manifest, 'calculateAsync', '''
Future<int> calculateAsync(int value) async {
  final int first = await hostImmediate(value);
  final int second = await hostDelayed(first);
  return second;
}
''');
      final result = await runZoned(
        () => E0AsyncInterpreter.execute(program, <Object?>[
          1,
        ], onRuntimeFault: fail),
        zoneValues: <Object?, Object?>{#request: 'zone-a'},
      );
      expect(result, 3);
      expect(seen, everyElement('zone-a'));
    });

    test('awaited host error is catchable and finally executes once', () async {
      final program = _compile(manifest, 'errorAsync', '''
Future<int> errorAsync(int value) async {
  int count = 0;
  try {
    final int ignored = await hostError(value);
    return ignored;
  } catch (_) {
    count += 2;
  } finally {
    count += 3;
  }
  return count;
}
''');
      expect(
        await E0AsyncInterpreter.execute(program, <Object?>[
          4,
        ], onRuntimeFault: fail),
        5,
      );
    });

    test(
      'guest throw after resume uses the saved catch/finally frames',
      () async {
        final program = _compile(manifest, 'errorAsync', '''
Future<int> errorAsync(int value) async {
  int count = 0;
  try {
    final int result = await hostImmediate(value);
    if (result > 0) throw result;
  } catch (_) {
    count += 4;
  } finally {
    count += 6;
  }
  return count;
}
''');
        expect(
          await E0AsyncInterpreter.execute(program, <Object?>[
            1,
          ], onRuntimeFault: fail),
          10,
        );
      },
    );

    test('uncaught Future error crosses as bounded host failure', () async {
      final program = _compile(manifest, 'errorAsync', '''
Future<int> errorAsync(int value) async {
  return await hostError(value);
}
''');
      await expectLater(
        E0AsyncInterpreter.execute(program, <Object?>[7], onRuntimeFault: fail),
        throwsA(
          isA<E0HostFailure>()
              .having((error) => error.boundaryId, 'boundary', _error.id)
              .having((error) => error.code, 'code', 'hostFailure'),
        ),
      );
    });

    for (final scenario
        in <({String name, Object Function() error, Matcher matcher})>[
          (
            name: 'E0RuntimeFault',
            error: () => const E0RuntimeFault('capability invariant'),
            matcher: isA<E0RuntimeFault>(),
          ),
          (
            name: 'StackOverflowError',
            error: StackOverflowError.new,
            matcher: isA<StackOverflowError>(),
          ),
          (
            name: 'OutOfMemoryError',
            error: OutOfMemoryError.new,
            matcher: isA<OutOfMemoryError>(),
          ),
        ]) {
      test(
        'synchronous capability ${scenario.name} bypasses guest catch and disables patch',
        () async {
          E0PatchRuntime.reset();
          _configureCapabilities(
            overrides: <String, E0CapabilityHandler>{
              _error.id: (arguments) => throw scenario.error(),
            },
          );
          final bytes = _compileBytes(manifest, 'errorAsync', '''
Future<int> errorAsync(int value) async {
  try {
    return await hostError(value);
  } catch (_) {
    return 999;
  }
}
''');
          expect(_install(manifest, bytes), isTrue);
          final target = manifest.functions.singleWhere(
            (function) => function.name == 'errorAsync',
          );
          final program = E0PatchRuntime.lookup(target.slot)!;
          final future = E0PatchRuntime.invokeAsync<int>(program, <Object?>[1]);
          expect(future, isNotNull);
          await expectLater(future, throwsA(scenario.matcher));
          expect(E0PatchRuntime.lookup(target.slot), isNull);
        },
      );

      test(
        'Future completion ${scenario.name} bypasses guest catch and disables patch',
        () async {
          E0PatchRuntime.reset();
          _configureCapabilities(
            overrides: <String, E0CapabilityHandler>{
              _error.id: (arguments) => Future<Object?>.error(scenario.error()),
            },
          );
          final bytes = _compileBytes(manifest, 'errorAsync', '''
Future<int> errorAsync(int value) async {
  try {
    return await hostError(value);
  } catch (_) {
    return 999;
  }
}
''');
          expect(_install(manifest, bytes), isTrue);
          final target = manifest.functions.singleWhere(
            (function) => function.name == 'errorAsync',
          );
          final program = E0PatchRuntime.lookup(target.slot)!;
          final future = E0PatchRuntime.invokeAsync<int>(program, <Object?>[1]);
          expect(future, isNotNull);
          await expectLater(future, throwsA(scenario.matcher));
          expect(E0PatchRuntime.lookup(target.slot), isNull);
        },
      );

      test(
        'resumed receiver read ${scenario.name} bypasses guest catch and disables patch',
        () async {
          final bytes = _compileBytes(manifest, 'calculate', '''
class AsyncService {
  final int delta;
  AsyncService(this.delta);
  Future<int> calculate(int value) async {
    try {
      final int result = await hostImmediate(value);
      return result + this.delta;
    } catch (_) {
      return 999;
    }
  }
}
''', className: 'AsyncService');
          expect(_install(manifest, bytes), isTrue);
          final target = manifest.functions.singleWhere(
            (function) => function.name == 'calculate',
          );
          final program = E0PatchRuntime.lookup(target.slot)!;
          final future = E0PatchRuntime.invokeAsync<int>(program, <Object?>[
            1,
          ], receiver: _ThrowingReceiver(program.receiver.id, scenario.error));
          expect(future, isNotNull);
          await expectLater(future, throwsA(scenario.matcher));
          expect(E0PatchRuntime.lookup(target.slot), isNull);
        },
      );
    }

    test('ordinary receiver failure is fixed and redacted', () async {
      final bytes = _compileBytes(manifest, 'calculate', '''
class AsyncService {
  final int delta;
  AsyncService(this.delta);
  Future<int> calculate(int value) async {
    final int result = await hostImmediate(value);
    return result + this.delta;
  }
}
''', className: 'AsyncService');
      expect(_install(manifest, bytes), isTrue);
      final target = manifest.functions.singleWhere(
        (function) => function.name == 'calculate',
      );
      final program = E0PatchRuntime.lookup(target.slot)!;
      try {
        await E0PatchRuntime.invokeAsync<int>(
          program,
          <Object?>[1],
          receiver: _ThrowingReceiver(
            program.receiver.id,
            () => _SecretReceiverError(),
          ),
        );
        fail('expected receiver failure');
      } on E0HostFailure catch (error) {
        expect(error.code, 'receiverFailure');
        expect(error.errorKind, 'boundaryFailure');
        expect(error.message, 'Receiver request failed');
        final guest = jsonEncode(error.toGuestValue());
        expect(guest, isNot(contains('https://secret.example')));
        expect(guest, isNot(contains('/tmp/credential')));
      }
    });

    test(
      'wrong resumed receiver type is a runtime fault, not a guest failure',
      () async {
        final bytes = _compileBytes(manifest, 'calculate', '''
class AsyncService {
  final int delta;
  AsyncService(this.delta);
  Future<int> calculate(int value) async {
    try {
      final int result = await hostImmediate(value);
      return result + this.delta;
    } catch (_) {
      return 999;
    }
  }
}
''', className: 'AsyncService');
        expect(_install(manifest, bytes), isTrue);
        final target = manifest.functions.singleWhere(
          (function) => function.name == 'calculate',
        );
        final program = E0PatchRuntime.lookup(target.slot)!;
        final future = E0PatchRuntime.invokeAsync<int>(program, <Object?>[
          1,
        ], receiver: _Receiver(program.receiver.id, 'wrong'));
        expect(future, isNotNull);
        await expectLater(future, throwsA(isA<E0RuntimeFault>()));
        expect(E0PatchRuntime.lookup(target.slot), isNull);
      },
    );

    test(
      'wrong resumed type faults, disables current patch, and never falls back',
      () async {
        final bytes = _compileBytes(manifest, 'wrongAsync', '''
Future<int> wrongAsync(int value) async {
  return await hostWrong(value);
}
''');
        expect(_install(manifest, bytes), isTrue);
        final target = manifest.functions.singleWhere(
          (function) => function.name == 'wrongAsync',
        );
        final program = E0PatchRuntime.lookup(target.slot)!;
        final future = E0PatchRuntime.invokeAsync<int>(program, <Object?>[1]);
        expect(future, isNotNull);
        await expectLater(future, throwsA(isA<E0RuntimeFault>()));
        expect(E0PatchRuntime.lookup(target.slot), isNull);
        expect(E0PatchRuntime.lastRejection, contains('validation failed'));
      },
    );

    test('frozen authority cannot disappear before capability start', () {
      final bytes = _compileBytes(manifest, 'calculateAsync', '''
Future<int> calculateAsync(int value) async {
  return await hostImmediate(value);
}
''');
      expect(_install(manifest, bytes), isTrue);
      final target = manifest.functions.singleWhere(
        (function) => function.name == 'calculateAsync',
      );
      final program = E0PatchRuntime.lookup(target.slot)!;
      expect(() => _configureCapabilities(only: <String>{}), throwsStateError);
      expect(E0PatchRuntime.invokeAsync<int>(program, <Object?>[1]), isNotNull);
    });

    test('deadline settles never Future and releases retained state', () async {
      final gate = Completer<Object?>();
      E0PatchRuntime.reset();
      _configureCapabilities(
        overrides: <String, E0CapabilityHandler>{
          _never.id: (arguments) => gate.future,
        },
      );
      final program = _compile(manifest, 'calculate', '''
class AsyncService {
  final int delta;
  AsyncService(this.delta);
  Future<int> calculate(int value) async {
    final int result = await hostNever(value);
    return result + this.delta;
  }
}
''', className: 'AsyncService');
      await expectLater(
        E0AsyncInterpreter.execute(
          program,
          <Object?>[
            <int>[1, 2, 3].length,
          ],
          receiver: _Receiver(program.receiver.id, 9),
          deadline: const Duration(milliseconds: 20),
          onRuntimeFault: (_) {},
        ),
        throwsA(
          isA<E0RuntimeFault>().having(
            (error) => error.message,
            'message',
            contains('deadline'),
          ),
        ),
      );
      expect(E0AsyncInterpreter.activeContinuations, 0);
      final retention = E0AsyncInterpreter.lastRetentionSnapshot;
      expect(retention, isNotNull);
      expect(retention!.heavyStateReleased, isTrue);
      expect(retention.programRetained, isFalse);
      expect(retention.argumentsRetained, isFalse);
      expect(retention.receiverRetained, isFalse);
      expect(retention.resumeTokenAttached, isFalse);
      expect(E0AsyncInterpreter.debugAttemptStaleResume(), isFalse);
      expect(E0AsyncInterpreter.rejectedResumeAttempts, 1);
      gate.complete(44);
      await Future<void>.delayed(Duration.zero);
      expect(E0AsyncInterpreter.rejectedResumeAttempts, 2);
      expect(
        E0AsyncInterpreter.lastRetentionSnapshot!.heavyStateReleased,
        isTrue,
      );
    });

    test(
      'run budget fault bypasses guest catch and disables installed patch',
      () async {
        final bytes = _compileBytes(manifest, 'calculateAsync', '''
Future<int> calculateAsync(int value) async {
  try {
    final int first = await hostImmediate(value);
    int count = 0;
    while (count < 100) {
      count += 1;
    }
    return first + count;
  } catch (_) {
    return 999;
  }
}
''');
        expect(_install(manifest, bytes), isTrue);
        final target = manifest.functions.singleWhere(
          (function) => function.name == 'calculateAsync',
        );
        final program = E0PatchRuntime.lookup(target.slot)!;
        final future = E0PatchRuntime.invokeAsync<int>(program, <Object?>[
          1,
        ], instructionBudget: 25);
        expect(future, isNotNull);
        await expectLater(
          future,
          throwsA(
            isA<E0RuntimeFault>()
                .having((error) => error.message, 'message', contains('budget'))
                .having(
                  (error) => error.code,
                  'code',
                  E0RuntimeDiagnosticCode.budget,
                ),
          ),
        );
        expect(E0PatchRuntime.lookup(target.slot), isNull);
      },
    );

    test(
      'pending invocation pins old program while new calls use replacement',
      () async {
        final gate = Completer<Object?>();
        E0PatchRuntime.reset();
        _configureCapabilities(
          overrides: <String, E0CapabilityHandler>{
            _delayed.id: (arguments) => gate.future,
          },
        );
        final oldBytes = _compileBytes(manifest, 'calculateAsync', '''
Future<int> calculateAsync(int value) async {
  final int result = await hostDelayed(value);
  return result + 100;
}
''');
        final newBytes = _compileBytes(manifest, 'calculateAsync', '''
Future<int> calculateAsync(int value) async {
  final int result = await hostImmediate(value);
  return result + 200;
}
''', patchSequence: 2);
        expect(_install(manifest, oldBytes), isTrue);
        final target = manifest.functions.singleWhere(
          (function) => function.name == 'calculateAsync',
        );
        final oldProgram = E0PatchRuntime.lookup(target.slot)!;
        final oldFuture = E0PatchRuntime.invokeAsync<int>(oldProgram, <Object?>[
          1,
        ])!;
        expect(E0AsyncInterpreter.debugAttemptStaleResume(), isFalse);
        expect(_install(manifest, newBytes), isTrue);
        final newProgram = E0PatchRuntime.lookup(target.slot)!;
        expect(identical(oldProgram, newProgram), isFalse);
        expect(
          await E0PatchRuntime.invokeAsync<int>(newProgram, <Object?>[1]),
          202,
        );
        gate.complete(10);
        expect(await oldFuture, 110);
        expect(
          identical(E0PatchRuntime.lookup(target.slot), newProgram),
          isTrue,
        );
      },
    );

    test(
      'ordinary async instance method reads selected receiver state',
      () async {
        final program = _compile(manifest, 'calculate', '''
class AsyncService {
  final int delta;
  AsyncService(this.delta);
  Future<int> calculate(int value) async {
    final int result = await hostImmediate(value);
    return result + this.delta;
  }
}
''', className: 'AsyncService');
        expect(
          await E0AsyncInterpreter.execute(
            program,
            <Object?>[2],
            receiver: _Receiver(program.receiver.id, 5),
            onRuntimeFault: fail,
          ),
          8,
        );
      },
    );
  });
}

void _configureCapabilities({
  Map<String, E0CapabilityHandler> overrides = const {},
  Set<String>? only,
}) {
  final handlers = <String, E0CapabilityHandler>{
    _immediate.id: (arguments) =>
        Future<Object?>.value((arguments.single! as int) + 1),
    _delayed.id: (arguments) => Future<Object?>.delayed(
      const Duration(milliseconds: 5),
      () => (arguments.single! as int) * 2,
    ),
    _error.id: (arguments) => Future<Object?>.error(StateError('host-secret')),
    _never.id: (arguments) => Completer<Object?>().future,
    _wrong.id: (arguments) => Future<Object?>.value('wrong'),
    _map.id: (arguments) async {
      final input = arguments.single! as Map<String, Object?>;
      return <String, Object?>{...input, 'count': (input['count']! as int) + 1};
    },
    ...overrides,
  };
  final descriptors = <E0AsyncCapabilityDescriptor>[
    _immediate,
    _delayed,
    _error,
    _never,
    _wrong,
    _map,
  ];
  E0PatchRuntime.configureCapabilities(
    E0CapabilityAuthority(
      shipped: descriptors,
      registry: E0CapabilityRegistry(<E0CapabilityRegistration>[
        for (final descriptor in descriptors)
          if (only == null || only.contains(descriptor.id))
            E0CapabilityRegistration(descriptor, handlers[descriptor.id]!),
      ]),
    ),
  );
}

Uint8List _compileBytes(
  E0ReleaseManifest manifest,
  String functionName,
  String source, {
  String? className,
  int patchSequence = 1,
}) => E0PatchCompiler().compile(
  source: source,
  manifest: manifest,
  functionName: functionName,
  className: className,
  patchSequence: patchSequence,
);

E0PatchProgram _compile(
  E0ReleaseManifest manifest,
  String functionName,
  String source, {
  String? className,
}) => _decode(
  manifest,
  _compileBytes(manifest, functionName, source, className: className),
);

E0PatchProgram _decode(
  E0ReleaseManifest manifest,
  List<int> bytes,
) => E0PatchContainer.decode(
  bytes,
  expectedAppId: manifest.appId,
  expectedReleaseId: manifest.releaseId,
  expectedBuildFingerprint: manifest.buildFingerprint,
  expectedFunctions: <String, int>{
    for (final function in manifest.functions) function.id: function.slot,
  },
  expectedSignatures: <String, E0FunctionSignature>{
    for (final function in manifest.functions) function.id: function.signature,
  },
  expectedReceivers: <String, E0ReceiverDescriptor>{
    for (final function in manifest.functions) function.id: function.receiver,
  },
);

bool _install(E0ReleaseManifest manifest, List<int> bytes) =>
    E0PatchRuntime.installBytes(
      bytes,
      appId: manifest.appId,
      releaseId: manifest.releaseId,
      buildFingerprint: manifest.buildFingerprint,
      functions: <String, int>{
        for (final function in manifest.functions) function.id: function.slot,
      },
      signatures: <String, String>{
        for (final function in manifest.functions)
          function.id: function.signature.encode(),
      },
      receivers: <String, String>{
        for (final function in manifest.functions)
          function.id: function.receiver.encode(),
      },
    );

final class _Receiver implements E0ReceiverCapability {
  const _Receiver(this.descriptorId, this.value);

  @override
  final String descriptorId;
  final Object? value;

  @override
  Object? read(int slot) =>
      slot == 0 ? value : throw RangeError.index(slot, const <Object?>[]);
}

final class _ThrowingReceiver implements E0ReceiverCapability {
  const _ThrowingReceiver(this.descriptorId, this.error);

  @override
  final String descriptorId;
  final Object Function() error;

  @override
  Object? read(int slot) => throw error();
}

final class _SecretReceiverError {
  @override
  String toString() =>
      'credential at /tmp/credential https://secret.example?token=abc';
}

const _releaseSource = '''
Future<int> hostImmediate(int value) async { return value; }
Future<int> hostDelayed(int value) async { return value; }
Future<int> hostError(int value) async { return value; }
Future<int> hostNever(int value) async { return value; }
Future<int> hostWrong(int value) async { return value; }

Future<int> calculateAsync(int value) async { return value + 1; }
Future<int> errorAsync(int value) async { return value + 1; }
Future<int> neverAsync(int value) async { return value + 1; }
Future<int> wrongAsync(int value) async { return value + 1; }
Future<Map<String, dynamic>> mapAsync(Map<String, dynamic> input) async { return input; }
Future<int> closureAsync(List<int> values) async { return values.length; }

class AsyncService {
  final int delta;
  AsyncService(this.delta);
  Future<int> calculate(int value) async { return value + this.delta; }
}

void main() {}
''';
