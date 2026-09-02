import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  final fixture = File('fixture/release_app.dart');

  test(
    'overlay is deterministic across absolute directories and preserves input',
    () {
      final before = fixture.readAsBytesSync();
      final firstRoot = Directory.systemTemp.createTempSync('e0_first_');
      final secondRoot = Directory.systemTemp.createTempSync('e0_second_');
      addTearDown(() => firstRoot.deleteSync(recursive: true));
      addTearDown(() => secondRoot.deleteSync(recursive: true));
      final firstInput = File('${firstRoot.path}/input/app.dart')
        ..createSync(recursive: true)
        ..writeAsBytesSync(before);
      final secondInput = File('${secondRoot.path}/input/app.dart')
        ..createSync(recursive: true)
        ..writeAsBytesSync(before);
      final builder = E0OverlayBuilder(E0SourceTransformer());
      final first = builder.build(
        input: firstInput,
        outputDirectory: Directory('${firstRoot.path}/output'),
        packageName: 'fixture',
        logicalLibraryPath: 'lib/app.dart',
        appId: 'app',
        releaseId: 'release',
        buildFingerprint: 'test-build-1',
      );
      final second = builder.build(
        input: secondInput,
        outputDirectory: Directory('${secondRoot.path}/output'),
        packageName: 'fixture',
        logicalLibraryPath: 'lib/app.dart',
        appId: 'app',
        releaseId: 'release',
        buildFingerprint: 'test-build-1',
      );
      expect(first.source, second.source);
      expect(first.manifest.encode(), second.manifest.encode());
      expect(first.manifest.encode(), isNot(contains(firstRoot.path)));
      expect(second.manifest.encode(), isNot(contains(secondRoot.path)));
      expect(
        File('${firstRoot.path}/output/app.dart').readAsBytesSync(),
        File('${secondRoot.path}/output/app.dart').readAsBytesSync(),
      );
      expect(
        File('${firstRoot.path}/output/manifest.json').readAsBytesSync(),
        File('${secondRoot.path}/output/manifest.json').readAsBytesSync(),
      );
      expect(
        File('${firstRoot.path}/output/source-map.json').readAsBytesSync(),
        File('${secondRoot.path}/output/source-map.json').readAsBytesSync(),
      );
      expect(
        sha256.convert(firstInput.readAsBytesSync()),
        sha256.convert(before),
      );
      expect(
        sha256.convert(secondInput.readAsBytesSync()),
        sha256.convert(before),
      );
      expect(sha256.convert(fixture.readAsBytesSync()), sha256.convert(before));
      expect(fixture.readAsStringSync(), isNot(contains('E0PatchRuntime')));
      expect(first.source, contains('E0PatchRuntime.lookup(0)'));
      expect(first.source, isNot(contains('lookup(0, [')));

      final originalSource = firstInput.readAsStringSync();
      final map = first.offsetMap;
      for (final originalOffset in <int>[
        originalSource.indexOf('calculate'),
        originalSource.indexOf('if (a < 0)'),
        originalSource.indexOf('return a + b'),
      ]) {
        final generatedOffset = map.generatedOffsetForOriginal(originalOffset);
        expect(
          first.source.substring(generatedOffset, generatedOffset + 4),
          originalSource.substring(originalOffset, originalOffset + 4),
        );
        final lookup = map.lookupGenerated(generatedOffset);
        expect(lookup.isSynthetic, isFalse);
        expect(lookup.originalOffset, originalOffset);
      }
      final guardOffset = first.source.indexOf('final \$e0Patch');
      final guardLookup = map.lookupGenerated(guardOffset);
      expect(guardLookup.isSynthetic, isTrue);
      expect(guardLookup.syntheticKind, 'callee-guard');
      expect(
        guardLookup.anchorOriginalOffset,
        originalSource.indexOf('{', originalSource.indexOf('calculate')) + 1,
      );
      expect(() => map.lookupGenerated(-1), throwsRangeError);
      expect(() => map.lookupGenerated(map.generatedLength), throwsRangeError);
      expect(() => map.generatedOffsetForOriginal(-1), throwsRangeError);
      final malformed = jsonDecode(map.encode()) as Map<String, Object?>
        ..['generatedLength'] = map.generatedLength + 1;
      expect(
        () => E0OffsetMap.decode(jsonEncode(malformed)),
        throwsFormatException,
      );
    },
  );

  test('stable ID collisions fail closed', () {
    final transformer = E0SourceTransformer(
      identity: E0Identity(digest: (_) => 'collision'),
    );
    expect(
      () => transformer.transform(
        source:
            'int a(int x, int y) { return x + y; }\n'
            'int b(int x, int y) { return x - y; }\n'
            'void main(List<String> args) {}',
        packageName: 'fixture',
        logicalLibraryPath: 'lib/app.dart',
        appId: 'app',
        releaseId: 'release',
        buildFingerprint: 'test-build-1',
      ),
      throwsStateError,
    );
  });

  test(
    'package-config discovery is checkout-root and discovery-order independent',
    () {
      final roots = <Directory>[
        Directory.systemTemp.createTempSync('e0_checkout_a_'),
        Directory.systemTemp.createTempSync('e0_checkout_b_'),
      ];
      for (final root in roots) {
        addTearDown(() => root.deleteSync(recursive: true));
        File('${root.path}/.dart_tool/package_config.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode(<String, Object>{
              'configVersion': 2,
              'packages': <Object>[
                <String, Object>{
                  'name': 'fixture',
                  'rootUri': '../',
                  'packageUri': 'lib/',
                },
              ],
            }),
          );
      }
      final firstInput = File('${roots[0].path}/lib/app.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'int alpha(int value) { return value; }\n'
          'int beta(int value) { return value + 1; }\n'
          'void main(List<String> args) {}',
        );
      final secondInput = File('${roots[1].path}/lib/app.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'int beta(int value) { return value + 1; }\n'
          'int alpha(int value) { return value; }\n'
          'void main(List<String> args) {}',
        );
      final builder = E0OverlayBuilder(E0SourceTransformer());
      E0TransformResult build(File input, Directory root) => builder.build(
        input: input,
        outputDirectory: Directory('${root.path}/output'),
        packageName: 'fixture',
        logicalLibraryPath: 'lib/app.dart',
        appId: 'app',
        releaseId: 'release',
        buildFingerprint: 'checkout-independent-build',
      );
      final first = build(firstInput, roots[0]);
      final second = build(secondInput, roots[1]);
      expect(first.manifest.canonicalLibraryUri, 'package:fixture/app.dart');
      expect(
        first.manifest.functions.map((item) => item.id),
        second.manifest.functions.map((item) => item.id),
      );
      expect(first.manifest.encode(), second.manifest.encode());
    },
  );

  test(
    'configured file outside package URI root cannot masquerade as lib input',
    () {
      final root = Directory.systemTemp.createTempSync('e0_outside_lib_');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/.dart_tool/package_config.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode(<String, Object>{
            'configVersion': 2,
            'packages': <Object>[
              <String, Object>{
                'name': 'fixture',
                'rootUri': '../',
                'packageUri': 'lib/',
              },
            ],
          }),
        );
      final input = File('${root.path}/bin/app.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'int target(int value) { return value; }\n'
          'void main(List<String> args) {}',
        );
      expect(
        () => E0OverlayBuilder(E0SourceTransformer()).build(
          input: input,
          outputDirectory: Directory('${root.path}/output'),
          packageName: 'fixture',
          logicalLibraryPath: 'lib/app.dart',
          appId: 'app',
          releaseId: 'release',
          buildFingerprint: 'test-build-1',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('outside the configured package URI root'),
          ),
        ),
      );
    },
  );
}
