import 'dart:convert';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  const mainSource = 'void main(List<String> args) {}';

  E0TransformResult transform(
    String declaration, {
    String path = 'lib/app.dart',
  }) => E0SourceTransformer().transform(
    source: '$declaration\n$mainSource',
    packageName: 'fixture',
    logicalLibraryPath: path,
    appId: 'app',
    releaseId: 'release',
    buildFingerprint: 'test-build-1',
  );

  group('v2 declaration identity', () {
    test('is insensitive to whitespace and movement within one library', () {
      final first = transform(
        'int alpha(int value) { return value; }\n'
        'int target(int value) { return value + 1; }',
      );
      final moved = transform(
        'int target( int value ) {\n  return value + 1;\n}\n'
        'int alpha(int value) { return value; }',
      );
      final firstTarget = first.manifest.functions.singleWhere(
        (item) => item.name == 'target',
      );
      final movedTarget = moved.manifest.functions.singleWhere(
        (item) => item.name == 'target',
      );
      expect(movedTarget.id, firstTarget.id);
      expect(movedTarget.identity.encode(), firstTarget.identity.encode());
      expect(firstTarget.identity.libraryUri, 'package:fixture/app.dart');
      expect(
        firstTarget.identity.memberKind,
        E0DeclarationIdentity.topLevelFunction,
      );
    });

    test('changes on logical file move or rename but not signature', () {
      final original = transform('int target(int value) { return value; }');
      final originalId = original.manifest.functions.single.id;
      expect(
        transform(
          'int target(int value) { return value; }',
          path: 'lib/moved.dart',
        ).manifest.functions.single.id,
        isNot(originalId),
      );
      expect(
        transform('int renamed(int value) { return value; }')
            .manifest
            .functions
            .single
            .id,
        isNot(originalId),
      );
      final signatureChanged = transform(
        'String target(String value) { return value; }',
      ).manifest.functions.single;
      expect(signatureChanged.id, originalId);
      expect(
        signatureChanged.signatureDigest,
        isNot(original.manifest.functions.single.signatureDigest),
      );
      final firstOwner = transform(
        'class First { int target(int value) { return value; } }',
      ).manifest.functions.single.id;
      final secondOwner = transform(
        'class Second { int target(int value) { return value; } }',
      ).manifest.functions.single.id;
      expect(secondOwner, isNot(firstOwner));
    });

    test('rejects absolute identity paths', () {
      expect(
        () => transform(
          'int target(int value) { return value; }',
          path: '/tmp/app.dart',
        ),
        throwsFormatException,
      );
      expect(
        () => transform(
          'int target(int value) { return value; }',
          path: r'C:\tmp\app.dart',
        ),
        throwsFormatException,
      );
      for (final path in <String>[
        'app.dart',
        '../lib/app.dart',
        'lib/a#b.dart',
      ]) {
        expect(
          () =>
              transform('int target(int value) { return value; }', path: path),
          throwsFormatException,
        );
      }
    });

    test(
      'normalizes receiver identities through the canonical library URI',
      () {
        const source =
            'class Service { final int value = 1; '
            'int target(int input) { return input + this.value; } }';
        final direct = transform(source).manifest.functions.single;
        final normalized = transform(
          source,
          path: 'lib/nested/../app.dart',
        ).manifest.functions.single;
        expect(normalized.id, direct.id);
        expect(normalized.receiver.id, direct.receiver.id);
        expect(
          normalized.receiver.members.single.id,
          direct.receiver.members.single.id,
        );
      },
    );

    test('rejects parts explicitly', () {
      expect(
        () => E0SourceTransformer().transform(
          source: "part 'piece.dart';\n$mainSource",
          packageName: 'fixture',
          logicalLibraryPath: 'lib/app.dart',
          appId: 'app',
          releaseId: 'release',
          buildFingerprint: 'test-build-1',
        ),
        throwsFormatException,
      );
    });
  });

  group('strict release manifest v6', () {
    test(
      'round-trips deterministically and rejects tampering or unknown fields',
      () {
        final manifest = transform('int target(int value) { return value; }')
            .manifest;
        final encoded = manifest.encode();
        expect(E0ReleaseManifest.decode(encoded).encode(), encoded);

        final unknown = jsonDecode(encoded) as Map<String, Object?>
          ..['unknown'] = true;
        expect(
          () => E0ReleaseManifest.decode(jsonEncode(unknown)),
          throwsFormatException,
        );

        final noncanonicalPath = jsonDecode(encoded) as Map<String, Object?>
          ..['logicalLibraryPath'] = 'lib/nested/../app.dart';
        expect(
          () => E0ReleaseManifest.decode(jsonEncode(noncanonicalPath)),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('not canonical'),
            ),
          ),
        );

        final forged = jsonDecode(encoded) as Map<String, Object?>;
        final function =
            (forged['functions']! as List<Object?>).single!
                as Map<String, Object?>;
        function['id'] = 'sha256:${List.filled(64, '0').join()}';
        expect(
          () => E0ReleaseManifest.decode(jsonEncode(forged)),
          throwsFormatException,
        );
      },
    );

    test(
      'rejects cross-field target-routing forgeries and unsupported kinds',
      () {
        final encoded = transform(
          'class Service { int target(int value) { return value; } }',
        ).manifest.encode();
        for (final mutate in <void Function(Map<String, Object?>)>[
          (root) => root['canonicalLibraryUri'] = 'package:fixture/other.dart',
          (root) {
            final function =
                (root['functions']! as List<Object?>).single!
                    as Map<String, Object?>;
            function['name'] = 'misrouted';
          },
          (root) {
            final function =
                (root['functions']! as List<Object?>).single!
                    as Map<String, Object?>;
            final identity = function['identity']! as Map<String, Object?>;
            identity['memberKind'] = 'constructor';
          },
          (root) {
            final function =
                (root['functions']! as List<Object?>).single!
                    as Map<String, Object?>;
            final receiver = function['receiver']! as Map<String, Object?>;
            receiver['ownerClass'] = 'OtherService';
          },
        ]) {
          final forged = jsonDecode(encoded) as Map<String, Object?>;
          mutate(forged);
          expect(
            () => E0ReleaseManifest.decode(jsonEncode(forged)),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'same semantic ID still rejects a changed signature at compilation',
      () {
        final manifest = transform('int target(int value) { return value; }')
            .manifest;
        expect(
          () => E0PatchCompiler().compile(
            source: 'String target(String value) { return value; }',
            manifest: manifest,
            functionName: 'target',
          ),
          throwsFormatException,
        );
      },
    );
  });

  group('v7 compatibility activation', () {
    late E0ReleaseManifest manifest;
    late Map<String, int> functions;
    late Map<String, String> signatures;
    late Map<String, String> receivers;

    setUp(() {
      E0PatchRuntime.reset();
      manifest = transform('int target(int value) { return value; }').manifest;
      functions = <String, int>{manifest.functions.single.id: 0};
      signatures = <String, String>{
        manifest.functions.single.id: manifest.functions.single.signature
            .encode(),
      };
      receivers = <String, String>{
        manifest.functions.single.id: manifest.functions.single.receiver
            .encode(),
      };
    });

    List<int> compile(int sequence, {String expression = 'value + 1'}) =>
        E0PatchCompiler().compile(
          source: 'int target(int value) { return $expression; }',
          manifest: manifest,
          functionName: 'target',
          patchSequence: sequence,
        );

    bool install(List<int> bytes) => E0PatchRuntime.installBytes(
      bytes,
      appId: 'app',
      releaseId: 'release',
      buildFingerprint: manifest.buildFingerprint,
      functions: functions,
      signatures: signatures,
      receivers: receivers,
    );

    test('compiler output and canonical payload hash are deterministic', () {
      expect(compile(4), compile(4));
      final decoded =
          jsonDecode(utf8.decode(compile(4))) as Map<String, Object?>;
      expect(decoded['formatVersion'], e0PatchFormatVersion);
      expect(decoded['runtimeVersion'], e0RuntimeVersion);
      expect(decoded['patchSequence'], 4);
      expect(decoded['payloadHash'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(decoded['capabilities'], isA<List<Object?>>());
    });

    test('rejects noncanonical whitespace, key order, and duplicate keys', () {
      final canonical = utf8.decode(compile(1));
      expect(install(utf8.encode('$canonical\n')), isFalse);
      expect(E0PatchRuntime.lastRejection, contains('canonically encoded'));

      final decoded = jsonDecode(canonical) as Map<String, Object?>;
      final reversed = Map<String, Object?>.fromEntries(
        decoded.entries.toList().reversed,
      );
      expect(install(utf8.encode(jsonEncode(reversed))), isFalse);
      expect(E0PatchRuntime.lastRejection, contains('canonically encoded'));

      final duplicate = canonical.replaceFirst('{', '{"appId":"app",');
      expect(install(utf8.encode(duplicate)), isFalse);
      expect(E0PatchRuntime.lastRejection, contains('canonically encoded'));
    });

    test(
      'requires complete signature/receiver tables and exact build fingerprint',
      () {
        final candidate = compile(1);
        expect(
          E0PatchRuntime.installBytes(
            candidate,
            appId: 'app',
            releaseId: 'release',
            buildFingerprint: 'test-build-1',
            functions: functions,
            receivers: receivers,
          ),
          isFalse,
        );
        expect(E0PatchRuntime.lastRejection, contains('compatibility tables'));
        expect(
          E0PatchRuntime.installBytes(
            candidate,
            appId: 'app',
            releaseId: 'release',
            buildFingerprint: 'test-build-1',
            functions: functions,
            signatures: signatures,
          ),
          isFalse,
        );
        expect(E0PatchRuntime.lastRejection, contains('compatibility tables'));
        expect(
          E0PatchRuntime.installBytes(
            candidate,
            appId: 'app',
            releaseId: 'release',
            buildFingerprint: 'other-build',
            functions: functions,
            signatures: signatures,
            receivers: receivers,
          ),
          isFalse,
        );
        expect(E0PatchRuntime.lastRejection, contains('build fingerprint'));
      },
    );

    test('rejects corrupt hash and incompatible runtime', () {
      final corrupt =
          jsonDecode(utf8.decode(compile(1))) as Map<String, Object?>
            ..['payloadHash'] = List.filled(64, '0').join();
      expect(install(utf8.encode(jsonEncode(corrupt))), isFalse);
      expect(E0PatchRuntime.lastRejection, contains('payload hash mismatch'));

      final wrongRuntime =
          jsonDecode(utf8.decode(compile(1))) as Map<String, Object?>
            ..['runtimeVersion'] = 999;
      expect(install(utf8.encode(jsonEncode(wrongRuntime))), isFalse);
      expect(E0PatchRuntime.lastRejection, contains('runtime version'));
    });

    test('handles idempotent, equivocated, and stale sequences atomically', () {
      final first = compile(2);
      expect(install(first), isTrue);
      final active = E0PatchRuntime.lookup(0);
      expect(active, isNotNull);

      expect(install(first), isTrue);
      expect(E0PatchRuntime.lastRejection, isNull);
      expect(identical(E0PatchRuntime.lookup(0), active), isTrue);

      expect(install(compile(2, expression: 'value + 2')), isFalse);
      expect(E0PatchRuntime.lastRejection, contains('equivocation'));
      expect(identical(E0PatchRuntime.lookup(0), active), isTrue);

      expect(install(compile(1)), isFalse);
      expect(E0PatchRuntime.lastRejection, contains('stale'));
      expect(identical(E0PatchRuntime.lookup(0), active), isTrue);

      final corruptCandidate =
          jsonDecode(utf8.decode(compile(3))) as Map<String, Object?>
            ..['payloadHash'] = 'bad';
      expect(install(utf8.encode(jsonEncode(corruptCandidate))), isFalse);
      expect(identical(E0PatchRuntime.lookup(0), active), isTrue);
    });

    test('rejects wrong release, signature, and unknown field atomically', () {
      expect(install(compile(1)), isTrue);
      final active = E0PatchRuntime.lookup(0);
      final candidate = compile(2);

      expect(
        E0PatchRuntime.installBytes(
          candidate,
          appId: 'app',
          releaseId: 'wrong',
          buildFingerprint: manifest.buildFingerprint,
          functions: functions,
          signatures: signatures,
          receivers: receivers,
        ),
        isFalse,
      );
      expect(identical(E0PatchRuntime.lookup(0), active), isTrue);

      final wrongSignature = <String, String>{
        manifest.functions.single.id: E0FunctionSignature.legacyInt2.encode(),
      };
      expect(
        E0PatchRuntime.installBytes(
          candidate,
          appId: 'app',
          releaseId: 'release',
          buildFingerprint: manifest.buildFingerprint,
          functions: functions,
          signatures: wrongSignature,
          receivers: receivers,
        ),
        isFalse,
      );
      expect(identical(E0PatchRuntime.lookup(0), active), isTrue);

      final unknown = jsonDecode(utf8.decode(candidate)) as Map<String, Object?>
        ..['unknown'] = true;
      expect(install(utf8.encode(jsonEncode(unknown))), isFalse);
      expect(identical(E0PatchRuntime.lookup(0), active), isTrue);
    });
  });
}
