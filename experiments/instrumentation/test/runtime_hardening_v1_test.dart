import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    E0PatchRuntime.reset();
    E0RuntimeSourceMaps.clear();
  });

  group('runtime limits', () {
    test(
      'rejects a caller-supplied instruction budget above the hard bound',
      () {
        final program = _intProgram(
          functionId: 'budget',
          code: <int>[E0Opcode.loadArgument.code, 0, E0Opcode.returnValue.code],
        );
        E0Interpreter.validate(program);

        expect(
          () => E0Interpreter.executeValues(program, <Object?>[
            1,
          ], instructionBudget: E0RuntimeLimits.hardMaxInstructionBudget + 1),
          throwsA(
            isA<E0RuntimeFault>()
                .having(
                  (error) => error.code,
                  'code',
                  E0RuntimeDiagnosticCode.budget,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('budget'),
                ),
          ),
        );
      },
    );

    test('enforces the release-owned closure invocation limit', () {
      const source = '''
List<int> mapValues(List<int> values) {
  return values.map((value) => value + 1).toList();
}
''';
      final manifest = _manifest(source);
      final program = _compile(manifest, 'mapValues', source);

      expect(
        () => E0Interpreter.executeValues(program, <Object?>[
          <int>[1, 2],
        ], limits: const E0RuntimeLimits(maxClosureInvocations: 1)),
        throwsA(
          isA<E0RuntimeFault>().having(
            (error) => error.code,
            'code',
            E0RuntimeDiagnosticCode.closureBudget,
          ),
        ),
      );
    });

    test('enforces the capability call limit before starting the host', () {
      final descriptor = E0AsyncCapabilityDescriptor(
        id: 'e0.test.sync',
        version: 1,
        arguments: const <E0ValueSchema>[],
        result: E0ValueSchema.boolean,
        executionKind: E0CapabilityExecutionKind.sync,
      );
      var calls = 0;
      final authority = E0CapabilityAuthority(
        shipped: <E0AsyncCapabilityDescriptor>[descriptor],
        registry: E0CapabilityRegistry(<E0CapabilityRegistration>[
          E0CapabilityRegistration(descriptor, (_) {
            calls++;
            return true;
          }),
        ]),
      );
      final program = E0PatchProgram(
        functionId: 'capability-budget',
        slot: 0,
        constants: const <Object?>[],
        signature: const E0FunctionSignature(
          parameters: <E0ValueSchema>[],
          returnSchema: E0ValueSchema.boolean,
        ),
        capabilities: <E0AsyncCapabilityDescriptor>[descriptor],
        code: <int>[
          E0Opcode.callSyncCapability.code,
          0,
          0,
          E0Opcode.pop.code,
          E0Opcode.callSyncCapability.code,
          0,
          0,
          E0Opcode.returnValue.code,
        ],
      );
      E0Interpreter.validate(program);

      expect(
        () => E0Interpreter.executeValues(
          program,
          const <Object?>[],
          authority: authority,
          limits: const E0RuntimeLimits(maxCapabilityCalls: 1),
        ),
        throwsA(
          isA<E0RuntimeFault>().having(
            (error) => error.code,
            'code',
            E0RuntimeDiagnosticCode.capabilityBudget,
          ),
        ),
      );
      expect(calls, 1);
    });

    test('bounds runtime string concatenation', () {
      final program = E0PatchProgram(
        functionId: 'string-budget',
        slot: 0,
        signature: const E0FunctionSignature(
          parameters: <E0ValueSchema>[],
          returnSchema: E0ValueSchema.string,
        ),
        constants: <Object?>['a' * 40000, 'b' * 40000],
        code: <int>[
          E0Opcode.loadConstant.code,
          0,
          E0Opcode.loadConstant.code,
          1,
          E0Opcode.addInt.code,
          E0Opcode.returnValue.code,
        ],
      );
      E0Interpreter.validate(program);

      expect(
        () => E0Interpreter.executeValues(program, const <Object?>[]),
        throwsA(
          isA<E0RuntimeFault>().having(
            (error) => error.code,
            'code',
            E0RuntimeDiagnosticCode.budget,
          ),
        ),
      );
    });
  });

  group('runtime error isolation', () {
    test('invalid opcode becomes a bounded runtime fault', () {
      final program = _intProgram(
        functionId: 'invalid-opcode',
        code: const <int>[255],
      );

      expect(
        () => E0Interpreter.executeValues(program, <Object?>[1]),
        throwsA(
          isA<E0RuntimeFault>()
              .having(
                (error) => error.code,
                'code',
                E0RuntimeDiagnosticCode.invalidOpcode,
              )
              .having((error) => error.pc, 'pc', 0),
        ),
      );
      expect(
        () => E0Interpreter.validate(program),
        throwsA(isA<FormatException>()),
      );
    });

    test('wrong host value is isolated as a runtime fault', () {
      final program = _intProgram(
        functionId: 'type-failure',
        code: <int>[E0Opcode.loadArgument.code, 0, E0Opcode.returnValue.code],
      );
      E0Interpreter.validate(program);

      expect(
        () => E0Interpreter.executeValues(program, <Object?>['not-an-int']),
        throwsA(isA<E0RuntimeFault>()),
      );
    });

    test('out-of-range collection access remains a guest boundary failure', () {
      const source = '''
int read(List<int> values) {
  return values[4];
}
''';
      final manifest = _manifest(source);
      final program = _compile(manifest, 'read', source);
      E0GuestThrow? guest;
      try {
        E0Interpreter.executeValues(program, <Object?>[
          <int>[1],
        ]);
      } on E0GuestThrow catch (error) {
        guest = error;
      }
      expect(guest, isNotNull);
      expect(guest!.value, isA<E0HostFailure>());
      expect((guest.value as E0HostFailure).code, 'range');
    });

    test(
      'division is rejected rather than introducing an unbounded opcode',
      () {
        const source =
            'int divide(int left, int right) { return left ~/ right; }';
        final manifest = _manifest(source);
        expect(
          () => E0PatchCompiler().compile(
            source: source,
            manifest: manifest,
            functionName: 'divide',
          ),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });

  group('source-mapped diagnostics', () {
    test(
      'maps guest traces and runtime faults to logical source locations',
      () {
        const source = '''
int calculate(int value) {
  return value + 1;
}
''';
        final transformed = E0SourceTransformer().transform(
          source: '$source\nvoid main() {}',
          packageName: 'fixture',
          logicalLibraryPath: 'lib/cart_service.dart',
          appId: 'app',
          releaseId: 'release',
          buildFingerprint: 'build',
        );
        final function = transformed.manifest.functions.single;
        final generatedOffset = transformed.offsetMap
            .generatedOffsetForOriginal(source.indexOf('return'));
        final sourceMap = E0RuntimeSourceMap.fromSource(
          functionId: function.id,
          functionName: function.name,
          offsetMap: transformed.offsetMap,
          originalSource: '$source\nvoid main() {}',
          pcToGeneratedOffset: <int, int>{17: generatedOffset},
        );
        E0RuntimeSourceMaps.register(sourceMap);

        final trace = E0GuestTrace(function.id, 17);
        expect(trace.location, isNotNull);
        expect(trace.location!.logicalUri, 'package:fixture/cart_service.dart');
        expect(trace.location!.line, 2);
        expect(trace.location!.column, 3);
        expect(
          trace.toString(),
          contains('package:fixture/cart_service.dart:2:3'),
        );

        final fault = E0RuntimeFault(
          'Division by zero',
          pc: 17,
          functionId: function.id,
        );
        expect(fault.location, isNotNull);
        expect(
          fault.toString(),
          contains('package:fixture/cart_service.dart:2:3'),
        );
      },
    );

    test('source map encoding is bounded, logical, and deterministic', () {
      final offsetMap = E0OffsetMap(
        originalUri: 'package:fixture/app.dart',
        generatedUri: 'e0-overlay:lib/app.dart',
        originalLength: 3,
        generatedLength: 3,
        segments: const <E0OffsetSegment>[
          E0OffsetSegment(
            generatedStart: 0,
            length: 3,
            originalStart: 0,
            syntheticKind: null,
            anchorOriginalOffset: 0,
          ),
        ],
      );
      final first = E0RuntimeSourceMap(
        functionId: 'function',
        functionName: 'target',
        offsetMap: offsetMap,
        pcToGeneratedOffset: const <int, int>{0: 1},
        lineStarts: const <int>[0],
      );
      final second = E0RuntimeSourceMap.decode(first.encode());
      expect(second.encode(), first.encode());
      expect(second.lookup(0)!.logicalUri, 'package:fixture/app.dart');
      expect(
        () => E0RuntimeSourceMap(
          functionId: 'function',
          functionName: 'target',
          offsetMap: offsetMap,
          pcToGeneratedOffset: const <int, int>{0: 99},
          lineStarts: const <int>[0],
        ),
        throwsFormatException,
      );
      final malformed = first.encode().replaceFirst(
        '"lineStarts":[0]',
        '"lineStarts":["bad"]',
      );
      expect(() => E0RuntimeSourceMap.decode(malformed), throwsFormatException);
    });
  });
}

E0PatchProgram _intProgram({
  required String functionId,
  required List<int> code,
}) => E0PatchProgram(
  functionId: functionId,
  slot: 0,
  constants: const <Object?>[],
  signature: const E0FunctionSignature(
    parameters: <E0ValueSchema>[E0ValueSchema.integer],
    returnSchema: E0ValueSchema.integer,
  ),
  code: code,
);

E0ReleaseManifest _manifest(String source) => E0SourceTransformer()
    .transform(
      source: '$source\nvoid main() {}',
      packageName: 'fixture',
      logicalLibraryPath: 'lib/runtime_hardening.dart',
      appId: 'app',
      releaseId: 'release',
      buildFingerprint: 'build',
    )
    .manifest;

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
