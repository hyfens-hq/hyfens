import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  group('explicit pure-Dart package overlay', () {
    test(
      'patches local dependency direct and tear-off calls in native AOT',
      () async {
        final scratch = Directory.systemTemp.createTempSync('e0_pure_dep_');
        addTearDown(() => scratch.deleteSync(recursive: true));
        final appRoot = Directory('${scratch.path}/release_app');
        final app = File('${appRoot.path}/lib/app.dart')
          ..createSync(recursive: true)
          ..writeAsBytesSync(
            File('fixture/dependency_release_app.dart').readAsBytesSync(),
          );
        final dependencyRoot = Directory('fixture/pure_dart_dependency')
            .absolute;
        final dependency = File('${dependencyRoot.path}/lib/pure_dep.dart');
        final dependencyHash = sha256.convert(dependency.readAsBytesSync());
        final config = _writePackageConfig(
          Directory('${scratch.path}/input_config'),
          <String, Directory>{
            'release_app': appRoot,
            'pure_dep': dependencyRoot,
          },
        );
        final overlay = E0PackageOverlayBuilder(E0SourceTransformer()).build(
          units: <E0PackageUnit>[
            E0PackageUnit(input: app, isEntrypoint: true),
            E0PackageUnit(input: dependency),
          ],
          packageConfig: config,
          outputDirectory: Directory('${scratch.path}/overlay'),
          appId: 'app',
          releaseId: 'pure-dependency-release',
          buildFingerprint: 'pure-dependency-build-1',
        );
        final reordered = E0PackageOverlayBuilder(E0SourceTransformer()).build(
          units: <E0PackageUnit>[
            E0PackageUnit(input: dependency),
            E0PackageUnit(input: app, isEntrypoint: true),
          ],
          packageConfig: config,
          outputDirectory: Directory('${scratch.path}/reordered_overlay'),
          appId: 'app',
          releaseId: 'pure-dependency-release',
          buildFingerprint: 'pure-dependency-build-1',
        );

        expect(reordered.manifest.encode(), overlay.manifest.encode());
        for (final unit in overlay.units.values) {
          expect(
            E0ReleaseManifest.decode(unit.manifest.encode()).encode(),
            overlay.manifest.encode(),
          );
        }
        expect(
          overlay.units.values
              .map(
                (unit) =>
                    RegExp(r'E0PatchRuntime\.installFromArguments')
                        .allMatches(unit.source)
                        .length,
              )
              .reduce((left, right) => left + right),
          1,
        );
        expect(
          reordered.units['package:pure_dep/pure_dep.dart']!.source,
          overlay.units['package:pure_dep/pure_dep.dart']!.source,
        );
        expect(overlay.manifest.libraryUris, <String>[
          'package:pure_dep/pure_dep.dart',
          'package:release_app/app.dart',
        ]);
        expect(
          overlay.manifest.functions.map((function) => function.id).toList(),
          orderedEquals(
            overlay.manifest.functions.map((function) => function.id).toList()
              ..sort(),
          ),
        );
        expect(
          overlay.manifest.functions.map((function) => function.slot).toList(),
          <int>[0, 1],
        );
        final decorated = overlay.manifest.functions.singleWhere(
          (function) => function.name == 'decorate',
        );
        expect(decorated.identity.libraryUri, 'package:pure_dep/pure_dep.dart');
        expect(
          overlay.units['package:pure_dep/pure_dep.dart']!.source,
          contains('E0PatchRuntime.lookup(${decorated.slot})'),
        );
        expect(sha256.convert(dependency.readAsBytesSync()), dependencyHash);
        expect(
          dependency.readAsStringSync(),
          isNot(contains('E0PatchRuntime')),
        );

        final patch = E0PatchCompiler().compile(
          source: File('fixture/dependency_patch.dart').readAsStringSync(),
          manifest: overlay.manifest,
          functionName: 'decorate',
          canonicalLibraryUri: 'package:pure_dep/pure_dep.dart',
        );
        expect(
          () => E0PatchCompiler().compile(
            source: File('fixture/dependency_patch.dart').readAsStringSync(),
            manifest: overlay.manifest,
            functionName: 'decorate',
            canonicalLibraryUri: 'package:release_app/app.dart',
          ),
          throwsFormatException,
        );
        expect(
          () => E0PatchCompiler().compile(
            source: 'int decorate(int value) { return value; }',
            manifest: overlay.manifest,
            functionName: 'decorate',
            canonicalLibraryUri: 'package:pure_dep/pure_dep.dart',
          ),
          throwsFormatException,
        );

        final wrongPackage = E0SourceTransformer()
            .transform(
              source:
                  "String decorate(String value) { return 'wrong:' + value; }\n"
                  'void main(List<String> arguments) {}',
              packageName: 'other_dep',
              logicalLibraryPath: 'lib/pure_dep.dart',
              appId: overlay.manifest.appId,
              releaseId: overlay.manifest.releaseId,
              buildFingerprint: overlay.manifest.buildFingerprint,
            )
            .manifest;
        final wrongPackagePatch = E0PatchCompiler().compile(
          source: File('fixture/dependency_patch.dart').readAsStringSync(),
          manifest: wrongPackage,
          functionName: 'decorate',
          canonicalLibraryUri: 'package:other_dep/pure_dep.dart',
        );

        final patchFile = File('${scratch.path}/dependency.patch')
          ..writeAsBytesSync(patch);
        final corruptFile = File('${scratch.path}/corrupt.patch')
          ..writeAsStringSync('{not-json');
        final wrongPackageFile = File('${scratch.path}/wrong-package.patch')
          ..writeAsBytesSync(wrongPackagePatch);
        final executable = File('${scratch.path}/release_app_executable');
        final compile = await Process.run(Platform.resolvedExecutable, <String>[
          'compile',
          'exe',
          '--packages=${overlay.packageConfig.path}',
          overlay.entrypoint.path,
          '-o',
          executable.path,
        ]);
        expect(
          compile.exitCode,
          0,
          reason: '${compile.stdout}\n${compile.stderr}',
        );

        Future<Map<String, Object?>> run([File? candidate]) async {
          final result = await Process.run(executable.path, <String>[
            if (candidate != null) '--e0-patch=${candidate.path}',
          ]);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          return jsonDecode(result.stdout as String) as Map<String, Object?>;
        }

        expect(await run(), <String, Object?>{
          'direct': 'base:direct',
          'tearOff': 'base:tear-off',
        });
        expect(await run(patchFile), <String, Object?>{
          'direct': 'patched:direct',
          'tearOff': 'patched:tear-off',
        });
        expect(await run(corruptFile), <String, Object?>{
          'direct': 'base:direct',
          'tearOff': 'base:tear-off',
        });
        expect(await run(wrongPackageFile), <String, Object?>{
          'direct': 'base:direct',
          'tearOff': 'base:tear-off',
        });
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('manifest and excluded unit boundaries fail closed', () {
      final source = E0SourceTransformer()
          .transform(
            source:
                'int target(int value) { return value; }\n'
                'void main(List<String> arguments) {}',
            packageName: 'fixture',
            logicalLibraryPath: 'lib/app.dart',
            appId: 'app',
            releaseId: 'release',
            buildFingerprint: 'build',
          )
          .manifest;
      final missingLibrary = jsonDecode(source.encode()) as Map<String, Object?>
        ..['libraryUris'] = <String>[];
      expect(
        () => E0ReleaseManifest.decode(jsonEncode(missingLibrary)),
        throwsFormatException,
      );
      final wrongOrder = jsonDecode(source.encode()) as Map<String, Object?>
        ..['libraryUris'] = <String>[
          'package:z/z.dart',
          'package:fixture/app.dart',
        ];
      expect(
        () => E0ReleaseManifest.decode(jsonEncode(wrongOrder)),
        throwsFormatException,
      );

      final twoFunctions = E0SourceTransformer()
          .transform(
            source:
                'int first(int value) { return value; }\n'
                'int second(int value) { return value; }\n'
                'void main(List<String> arguments) {}',
            packageName: 'fixture',
            logicalLibraryPath: 'lib/app.dart',
            appId: 'app',
            releaseId: 'release',
            buildFingerprint: 'build',
          )
          .manifest;
      final reorderedFunctions =
          jsonDecode(twoFunctions.encode()) as Map<String, Object?>;
      final functions = (reorderedFunctions['functions']! as List<Object?>)
          .reversed
          .cast<Map<String, Object?>>()
          .toList();
      for (var index = 0; index < functions.length; index++) {
        functions[index]['slot'] = index;
      }
      reorderedFunctions['functions'] = functions;
      expect(
        () => E0ReleaseManifest.decode(jsonEncode(reorderedFunctions)),
        throwsFormatException,
      );

      final scratch = Directory.systemTemp.createTempSync('e0_excluded_unit_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final appRoot = Directory('${scratch.path}/app');
      final entrypoint = File('${appRoot.path}/lib/app.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main(List<String> arguments) {}');
      final config = _writePackageConfig(
        Directory('${scratch.path}/config'),
        <String, Directory>{'excluded_app': appRoot},
      );
      for (final badUnit in <({String name, String source})>[
        (
          name: 'generated.g.dart',
          source: 'int generated(int value) { return value; }',
        ),
        (
          name: 'native.dart',
          source:
              "import/* comment */'stub.dart' if (dart.library.io) 'dart:ffi';\n"
              'int nativeTarget(int value) { return value; }',
        ),
        (
          name: 'flutter.dart',
          source: "import 'package:flutter/widgets.dart';\nint flutterTarget(int value) { return value; }",
        ),
      ]) {
        final input = File('${appRoot.path}/lib/${badUnit.name}')
          ..writeAsStringSync(badUnit.source);
        expect(
          () => E0PackageOverlayBuilder(E0SourceTransformer()).build(
            units: <E0PackageUnit>[
              E0PackageUnit(input: entrypoint, isEntrypoint: true),
              E0PackageUnit(input: input),
            ],
            packageConfig: config,
            outputDirectory: Directory('${scratch.path}/overlay'),
            appId: 'app',
            releaseId: 'release',
            buildFingerprint: 'build',
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('excluded'),
            ),
          ),
        );
      }

      final outside = File('${scratch.path}/outside.dart')
        ..writeAsStringSync('int escaped(int value) { return value; }');
      final linked = Link('${appRoot.path}/lib/linked.dart')
        ..createSync(outside.path);
      expect(
        () => E0PackageOverlayBuilder(E0SourceTransformer()).build(
          units: <E0PackageUnit>[
            E0PackageUnit(input: entrypoint, isEntrypoint: true),
            E0PackageUnit(input: File(linked.path)),
          ],
          packageConfig: config,
          outputDirectory: Directory('${scratch.path}/linked_overlay'),
          appId: 'app',
          releaseId: 'release',
          buildFingerprint: 'build',
        ),
        throwsFormatException,
      );

      final existingOutput = Directory('${scratch.path}/existing_overlay')
        ..createSync();
      final entrypointBefore = entrypoint.readAsStringSync();
      expect(
        () => E0PackageOverlayBuilder(E0SourceTransformer()).build(
          units: <E0PackageUnit>[
            E0PackageUnit(input: entrypoint, isEntrypoint: true),
          ],
          packageConfig: config,
          outputDirectory: existingOutput,
          appId: 'app',
          releaseId: 'release',
          buildFingerprint: 'build',
        ),
        throwsFormatException,
      );
      expect(entrypoint.readAsStringSync(), entrypointBefore);

      final fakeRuntimeRoot = Directory('${scratch.path}/fake_runtime');
      File('${fakeRuntimeRoot.path}/lib/e0_runtime.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('final class E0PatchRuntime {}');
      final redirectedRuntimeConfig = _writePackageConfig(
        Directory('${scratch.path}/redirected_runtime_config'),
        <String, Directory>{
          'excluded_app': appRoot,
          'instrumentation_e0': fakeRuntimeRoot,
        },
      );
      expect(
        () => E0PackageOverlayBuilder(E0SourceTransformer()).build(
          units: <E0PackageUnit>[
            E0PackageUnit(input: entrypoint, isEntrypoint: true),
          ],
          packageConfig: redirectedRuntimeConfig,
          outputDirectory: Directory('${scratch.path}/redirected_overlay'),
          appId: 'app',
          releaseId: 'release',
          buildFingerprint: 'build',
        ),
        throwsFormatException,
      );
    });
  });

  test(
    'patches collection 1.19.1 equalsIgnoreAsciiCase from an ephemeral copy',
    () async {
      final collectionUri = Isolate.resolvePackageUriSync(
        Uri.parse('package:collection/src/comparators.dart'),
      );
      expect(collectionUri, isNotNull);
      final collectionSource = File.fromUri(collectionUri!);
      final collectionRoot = collectionSource.parent.parent.parent;
      expect(
        File('${collectionRoot.path}/pubspec.yaml').readAsStringSync(),
        contains('version: 1.19.1'),
      );
      final originalHash = sha256.convert(collectionSource.readAsBytesSync());
      final scratch = Directory.systemTemp.createTempSync('e0_collection_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final appRoot = Directory('${scratch.path}/hosted_app');
      final app = File('${appRoot.path}/lib/app.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "import 'dart:convert';\n"
          "import 'package:collection/src/comparators.dart';\n"
          'void main(List<String> arguments) {\n'
          '  final tearOff = equalsIgnoreAsciiCase;\n'
          "  print(jsonEncode(<bool>[equalsIgnoreAsciiCase('A', 'a'), tearOff('B', 'b')]));\n"
          '}',
        );
      final config = _writePackageConfig(
        Directory('${scratch.path}/input_config'),
        <String, Directory>{
          'hosted_app': appRoot,
          'collection': collectionRoot,
        },
      );
      final overlay = E0PackageOverlayBuilder(E0SourceTransformer()).build(
        units: <E0PackageUnit>[
          E0PackageUnit(input: app, isEntrypoint: true),
          E0PackageUnit(input: collectionSource),
        ],
        packageConfig: config,
        outputDirectory: Directory('${scratch.path}/overlay'),
        appId: 'app',
        releaseId: 'collection-1.19.1-release',
        buildFingerprint: 'collection-1.19.1-build-1',
      );
      final target = overlay.manifest.functions.singleWhere(
        (function) => function.name == 'equalsIgnoreAsciiCase',
      );
      expect(
        target.identity.libraryUri,
        'package:collection/src/comparators.dart',
      );
      final patch = E0PatchCompiler().compile(
        source:
            'bool equalsIgnoreAsciiCase(String a, String b) { return a == b; }',
        manifest: overlay.manifest,
        functionName: 'equalsIgnoreAsciiCase',
        canonicalLibraryUri: 'package:collection/src/comparators.dart',
      );
      final patchFile = File('${scratch.path}/collection.patch')
        ..writeAsBytesSync(patch);

      Future<List<Object?>> run([File? candidate]) async {
        final result = await Process.run(Platform.resolvedExecutable, <String>[
          '--packages=${overlay.packageConfig.path}',
          overlay.entrypoint.path,
          if (candidate != null) '--e0-patch=${candidate.path}',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return jsonDecode(result.stdout as String) as List<Object?>;
      }

      expect(await run(), <Object?>[true, true]);
      expect(await run(patchFile), <Object?>[false, false]);
      expect(sha256.convert(collectionSource.readAsBytesSync()), originalHash);
      expect(
        collectionSource.readAsStringSync(),
        isNot(contains('E0PatchRuntime')),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

File _writePackageConfig(Directory directory, Map<String, Directory> packages) {
  directory.createSync(recursive: true);
  final instrumentationUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:instrumentation_e0/e0_runtime.dart'),
  )!;
  final cryptoUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:crypto/crypto.dart'),
  )!;
  final roots = <String, Directory>{
    'instrumentation_e0': File.fromUri(instrumentationUri).parent.parent,
    'crypto': File.fromUri(cryptoUri).parent.parent,
    ...packages,
  };
  final config = File('${directory.path}/package_config.json');
  config.writeAsStringSync(
    jsonEncode(<String, Object>{
      'configVersion': 2,
      'packages': <Object>[
        for (final entry
            in (roots.entries.toList()
              ..sort((left, right) => left.key.compareTo(right.key))))
          <String, Object>{
            'name': entry.key,
            'rootUri': entry.value.absolute.uri.toString(),
            'packageUri': 'lib/',
          },
      ],
    }),
  );
  return config;
}
