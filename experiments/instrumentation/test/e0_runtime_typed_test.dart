import 'dart:convert';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('E0ValueSchema', () {
    test('parses supported explicit Dart schemas', () {
      expect(E0ValueSchema.parseDartType('bool'), E0ValueSchema.boolean);
      expect(E0ValueSchema.parseDartType('int?').nullable, isTrue);
      expect(
        E0ValueSchema.parseDartType('List<int>'),
        const E0ValueSchema.list(E0ValueSchema.integer),
      );
      expect(
        E0ValueSchema.parseDartType('Map<String, dynamic>'),
        const E0ValueSchema.map(E0ValueSchema.supportedValue),
      );
    });

    test('rejects object, non-String map key, and malformed schemas', () {
      for (final source in <String>[
        'Object',
        'Map<int, String>',
        'List',
        'Map<String, Object?>',
      ]) {
        expect(
          () => E0ValueSchema.parseDartType(source),
          throwsFormatException,
          reason: source,
        );
      }
      expect(
        () => E0ValueSchema.fromJson(<String, Object?>{
          'kind': 'int',
          'nullable': false,
          'extra': true,
        }),
        throwsFormatException,
      );
    });
  });

  group('E0ValueCodec', () {
    test('encodes maps and arguments deterministically with explicit tags', () {
      const schema = E0ValueSchema.map(E0ValueSchema.supportedValue);
      final first = E0ValueCodec.encode(
        E0Value.fromHost(<String, dynamic>{
          'z': <int>[2, 3],
          'a': null,
          'm': 1.5,
        }, schema),
      );
      final second = E0ValueCodec.encode(
        E0Value.fromHost(<String, dynamic>{
          'm': 1.5,
          'a': null,
          'z': <int>[2, 3],
        }, schema),
      );
      expect(first, second);
      expect(E0ValueCodec.decode(first).toHost(schema), <String, dynamic>{
        'a': null,
        'm': 1.5,
        'z': <int>[2, 3],
      });
      expect(
        E0ValueCodec.encodeArguments(
          <Object?>['Ada'],
          const <E0ValueSchema>[E0ValueSchema.string],
        ),
        E0ValueCodec.encodeArguments(
          <Object?>['Ada'],
          const <E0ValueSchema>[E0ValueSchema.string],
        ),
      );
    });

    test('preserves int and double as distinct wire values', () {
      final integer = utf8.decode(E0ValueCodec.encode(E0Value.infer(1)));
      final doubleValue = utf8.decode(E0ValueCodec.encode(E0Value.infer(1.0)));
      expect(integer, contains('"t":"int"'));
      expect(doubleValue, contains('"t":"double"'));
      expect(integer, isNot(doubleValue));
    });

    test('rejects wrong types, unsupported objects, and non-finite values', () {
      expect(
        () => E0Value.fromHost('1', E0ValueSchema.integer),
        throwsFormatException,
      );
      expect(() => E0Value.infer(DateTime(2026)), throwsFormatException);
      expect(() => E0Value.infer(double.nan), throwsFormatException);
      expect(
        () => E0Value.fromHost(<Object?, Object?>{
          1: 'bad',
        }, const E0ValueSchema.map(E0ValueSchema.supportedValue)),
        throwsFormatException,
      );
    });

    test('rejects malformed tags, non-canonical maps, depth, and size', () {
      expect(
        () => E0ValueCodec.decode(utf8.encode('{"t":"int","v":"1"}')),
        throwsFormatException,
      );
      expect(
        () => E0ValueCodec.decode(
          utf8.encode(
            '{"t":"Map","v":['
            '{"k":"z","v":{"t":"int","v":1}},'
            '{"k":"a","v":{"t":"int","v":2}}]}',
          ),
        ),
        throwsFormatException,
      );
      Object? nested = 1;
      for (var index = 0; index < E0ValueCodec.maxNestingDepth + 2; index++) {
        nested = <Object?>[nested];
      }
      expect(() => E0Value.infer(nested), throwsFormatException);
      expect(
        () => E0Value.fromHost(
          List<int>.filled(E0ValueCodec.maxCollectionEntries + 1, 1),
          const E0ValueSchema.list(E0ValueSchema.integer),
        ),
        throwsFormatException,
      );
      Map<String, Object?> nestedSchema = <String, Object?>{
        'kind': 'int',
        'nullable': false,
      };
      for (var index = 0; index < E0ValueCodec.maxNestingDepth + 2; index++) {
        nestedSchema = <String, Object?>{
          'kind': 'List',
          'nullable': false,
          'element': nestedSchema,
        };
      }
      expect(() => E0ValueSchema.fromJson(nestedSchema), throwsFormatException);
      expect(
        () => E0ValueCodec.decode(
          List<int>.filled(E0ValueCodec.maxEncodedBytes + 1, 0),
        ),
        throwsFormatException,
      );
    });
  });
}
