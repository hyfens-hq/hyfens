import 'dart:io';

import 'package:hyfens_flutter_integration/flutter_integration.dart';
import 'package:hyfens_flutter_integration/src/runtime_storage.dart';
import 'package:test/test.dart';

void main() {
  group('generated bootstrap', () {
    test('invocation source is deterministic and release-bound', () {
      final source = HyfensFlutterIntegration.invocationSource(
        appId: 'com.example.app',
        releaseId: 'sha256:release',
        buildFingerprint: 'sha256:build',
        functions: const <String, int>{'function-b': 1, 'function-a': 0},
        signatures: const <String, String>{
          'function-a': 'a',
          'function-b': 'b',
        },
        receivers: const <String, String>{
          'function-a': 'none',
          'function-b': 'none',
        },
        functionNames: const <String, String>{
          'function-a': 'calculate',
          'function-b': 'Cart.build',
        },
        functionUris: const <String, String>{
          'function-a': 'package:example/cart.dart',
          'function-b': 'package:example/cart.dart',
        },
        keyId: 'ed25519-test',
        publicKey: const <int>[1, 2, 3],
        patchUri: Uri.parse('http://127.0.0.1:18080/v1/patch'),
      );

      expect(source, contains('releaseId: "sha256:release"'));
      expect(source, contains('patchUri: Uri.parse'));
      expect(
        source,
        contains(
          '_hyfens_bootstrap.HyfensControlPlaneConfiguration.fromEnvironment()',
        ),
      );
      expect(source, contains('functionNames'));
      expect(source, contains('functionUris'));
      expect(
        source.indexOf('"function-a"'),
        lessThan(source.indexOf('"function-b"')),
      );
    });
  });

  group('runtime storage', () {
    late Directory supportRoot;

    setUp(() async {
      supportRoot = await Directory.systemTemp.createTemp(
        'hyfens-runtime-storage-test-',
      );
    });

    tearDown(() async {
      await supportRoot.delete(recursive: true);
    });

    RuntimeStorageRootProvider rootProvider() =>
        () async => supportRoot;

    test('uses one private support root per app and release', () async {
      final storage = await runtimeStorageDirectory(
        appId: 'com.example.app',
        releaseId: 'sha256:release',
        rootProvider: rootProvider(),
      );

      expect(
        storage.path,
        equals(
          '${supportRoot.path}${Platform.pathSeparator}hyfens'
          '${Platform.pathSeparator}com.example.app'
          '${Platform.pathSeparator}sha256:release',
        ),
      );
      expect(storage.path, startsWith(supportRoot.absolute.path));
      expect(storage.existsSync(), isFalse);

      final otherRelease = await runtimeStorageDirectory(
        appId: 'com.example.app',
        releaseId: 'sha256:other-release',
        rootProvider: rootProvider(),
      );
      final otherApp = await runtimeStorageDirectory(
        appId: 'com.example.other',
        releaseId: 'sha256:release',
        rootProvider: rootProvider(),
      );
      expect(otherRelease.path, isNot(equals(storage.path)));
      expect(otherApp.path, isNot(equals(storage.path)));
    });

    test('rejects path traversal in app and release identifiers', () async {
      for (final invalidAppId in <String>[
        '',
        '.',
        '..',
        '../escape',
        r'foo\bar',
      ]) {
        await expectLater(
          runtimeStorageDirectory(
            appId: invalidAppId,
            releaseId: 'sha256:release',
            rootProvider: rootProvider(),
          ),
          throwsA(isA<ArgumentError>()),
        );
      }

      for (final invalidReleaseId in <String>[
        '',
        '.',
        '..',
        '../escape',
        r'foo\bar',
      ]) {
        await expectLater(
          runtimeStorageDirectory(
            appId: 'com.example.app',
            releaseId: invalidReleaseId,
            rootProvider: rootProvider(),
          ),
          throwsA(isA<ArgumentError>()),
        );
      }
    });

    test('reuses the same directory after a controller restart', () async {
      final first = await runtimeStorageDirectory(
        appId: 'com.example.app',
        releaseId: 'sha256:release',
        rootProvider: rootProvider(),
      );
      await first.create(recursive: true);
      await File('${first.path}/restart-marker').writeAsString('healthy');

      final afterRestart = await runtimeStorageDirectory(
        appId: 'com.example.app',
        releaseId: 'sha256:release',
        rootProvider: rootProvider(),
      );

      expect(afterRestart.path, equals(first.path));
      expect(
        await File('${afterRestart.path}/restart-marker').readAsString(),
        equals('healthy'),
      );
    });

    test('has no host system-temp fallback', () async {
      await expectLater(
        runtimeStorageDirectory(
          appId: 'com.example.app',
          releaseId: 'sha256:release',
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
