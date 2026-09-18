import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    E0PatchRuntime.reset();
  });

  test('value-node allocation is rejected before mutable copying', () {
    final program = E0PatchProgram(
      functionId: 'value-node-budget',
      slot: 0,
      constants: const <Object?>[],
      signature: const E0FunctionSignature(
        parameters: <E0ValueSchema>[E0ValueSchema.supportedValue],
        returnSchema: E0ValueSchema.supportedValue,
      ),
      code: <int>[E0Opcode.loadArgument.code, 0, E0Opcode.returnValue.code],
    );
    E0Interpreter.validate(program);
    final value = <Object?>[
      for (var index = 0; index < 5; index++)
        <Object?>[
          for (
            var entry = 0;
            entry < E0ValueCodec.maxCollectionEntries;
            entry++
          )
            entry,
        ],
    ];

    expect(
      () => E0Interpreter.executeValues(program, <Object?>[value]),
      throwsA(
        isA<E0RuntimeFault>().having(
          (error) => error.message,
          'message',
          contains('node'),
        ),
      ),
    );
  });

  test('collection mutation remains bounded at the runtime seam', () {
    final program = E0PatchProgram(
      functionId: 'collection-budget',
      slot: 0,
      constants: const <Object?>[1],
      signature: const E0FunctionSignature(
        parameters: <E0ValueSchema>[E0ValueSchema.list(E0ValueSchema.integer)],
        returnSchema: E0ValueSchema.list(E0ValueSchema.integer),
      ),
      code: <int>[
        E0Opcode.loadArgument.code,
        0,
        E0Opcode.loadConstant.code,
        0,
        E0Opcode.collectionAdd.code,
        E0Opcode.loadArgument.code,
        0,
        E0Opcode.returnValue.code,
      ],
    );
    E0Interpreter.validate(program);

    expect(
      () => E0Interpreter.executeValues(program, <Object?>[
        List<int>.filled(E0ValueCodec.maxCollectionEntries, 0),
      ]),
      throwsA(
        isA<E0RuntimeFault>().having(
          (error) => error.message,
          'message',
          contains('size limit'),
        ),
      ),
    );
  });

  test('offset maps reject host filesystem URIs', () {
    final map = E0OffsetMap(
      originalUri: 'file:///tmp/secret.dart',
      generatedUri: 'e0-overlay:lib/secret.dart',
      originalLength: 1,
      generatedLength: 1,
      segments: const <E0OffsetSegment>[
        E0OffsetSegment(
          generatedStart: 0,
          length: 1,
          originalStart: 0,
          syntheticKind: null,
          anchorOriginalOffset: 0,
        ),
      ],
    );

    expect(map.validate, throwsFormatException);
  });

  test('offset maps admit only logical runtime URI schemes', () {
    for (final uri in <String>['data:secret', 'custom:private-value']) {
      final map = E0OffsetMap(
        originalUri: uri,
        generatedUri: 'e0-overlay:lib/secret.dart',
        originalLength: 1,
        generatedLength: 1,
        segments: const <E0OffsetSegment>[
          E0OffsetSegment(
            generatedStart: 0,
            length: 1,
            originalStart: 0,
            syntheticKind: null,
            anchorOriginalOffset: 0,
          ),
        ],
      );

      expect(map.validate, throwsFormatException, reason: uri);
    }
  });

  test('offset-map decoding enforces encoded byte limits', () {
    final nonAscii = 'é' * ((E0OffsetMap.maxEncodedCharacters ~/ 2) + 1);

    expect(() => E0OffsetMap.decode('"$nonAscii"'), throwsFormatException);
  });

  test('source maps reject path-like diagnostic labels', () {
    final offsetMap = E0OffsetMap(
      originalUri: 'package:fixture/secret.dart',
      generatedUri: 'e0-overlay:lib/secret.dart',
      originalLength: 1,
      generatedLength: 1,
      segments: const <E0OffsetSegment>[
        E0OffsetSegment(
          generatedStart: 0,
          length: 1,
          originalStart: 0,
          syntheticKind: null,
          anchorOriginalOffset: 0,
        ),
      ],
    );

    expect(
      () => E0RuntimeSourceMap(
        functionId: 'source-map-test',
        functionName: '/tmp/secret.dart',
        offsetMap: offsetMap,
        pcToGeneratedOffset: const <int, int>{0: 0},
        lineStarts: const <int>[0],
      ),
      throwsFormatException,
    );
  });

  test('runtime faults keep diagnostics bounded', () {
    final fault = E0RuntimeFault('x' * 4096, pc: 7, functionId: 'bounded');

    expect(fault.toString().length, lessThan(400));
  });

  test('runtime diagnostics redact paths, URLs, and credential values', () {
    final fault = E0RuntimeFault(
      'secret=/tmp/private.dart url=https://example.test/?token=abc '
      'Authorization: Bearer abc123',
      pc: 7,
      functionId: 'bounded',
    );
    final rendered = fault.toString();

    expect(rendered, contains('<redacted>'));
    expect(rendered, isNot(contains('/tmp/private.dart')));
    expect(rendered, isNot(contains('https://example.test')));
    expect(rendered, isNot(contains('abc123')));
  });
}
