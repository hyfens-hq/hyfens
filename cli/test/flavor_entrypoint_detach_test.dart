import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<Directory> _createProject() async {
  final root = await Directory.systemTemp.createTemp('hyfens-flavor-');
  await Directory(p.join(root.path, 'lib', 'flavors')).create(recursive: true);
  await Directory(p.join(root.path, 'android', 'app')).create(recursive: true);
  await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: flavor_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter: {}
dependencies: {}
''');
  await File(p.join(root.path, 'pubspec.lock')).writeAsString('''
packages: {}
sdks:
  dart: ">=3.13.0 <4.0.0"
''');
  await File(p.join(root.path, 'android', 'app', 'build.gradle')).writeAsString(
    'android { namespace "com.example.flavor" applicationId "com.example.flavor" }',
  );
  await File(p.join(root.path, 'lib', 'main.dart'))
      .writeAsString('void main() {}\n');
  await File(p.join(root.path, 'lib', 'flavors', 'local.dart'))
      .writeAsString('''
void main() {
  localValue();
}

int localValue() => 1;
''');
  await Directory(p.join(root.path, '.dart_tool')).create();
  await File(p.join(root.path, '.dart_tool', 'package_config.json'))
      .writeAsString(
        jsonEncode(<String, Object?>{
          'configVersion': 2,
          'packages': <Object?>[
            <String, Object?>{
              'name': 'flavor_app',
              'rootUri': root.uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.13',
            },
          ],
        }),
      );
  return root;
}

Future<void> _writeFlavorConfig(Directory root) async {
  await File(p.join(root.path, 'tool.yaml')).writeAsString(
    const ToolConfig(
      applicationId: 'com.example.flavor',
      entrypoints: <String, Map<String, String>>{
        'android': <String, String>{'local': 'lib/flavors/local.dart'},
      },
      applicationIds: <String, Map<String, String>>{
        'android': <String, String>{'local': 'com.example.flavor.local'},
      },
    ).encode(),
  );
}

Future<void> _writeAttachableState(Directory root) async {
  await _writeFlavorConfig(root);
  await writeHyfensBinding(
    File(p.join(root.path, 'hyfens.yaml')),
    binding: const HyfensProjectBinding(
      profile: 'local',
      organizationId: 'org_demo',
      applicationId: 'app_demo',
      environmentId: 'env_demo',
      runtimeApplicationId: 'com.example.flavor',
    ),
  );
  await Directory(p.join(root.path, '.tool', 'keys')).create(recursive: true);
  await Directory(p.join(root.path, '.tool', 'releases')).create();
  await Directory(p.join(root.path, '.tool', 'patches')).create();
  await File(p.join(root.path, '.tool', '.gitignore'))
      .writeAsString('keys/\nreleases/\npatches/\nbuilds/\n');
}

void main() {
  group('flavor entrypoint selection', () {
    test('loads mappings, preserves application IDs, and round-trips', () {
      const config = ToolConfig(
        applicationId: 'com.example.flavor',
        entrypoints: <String, Map<String, String>>{
          'android': <String, String>{
            'default': 'lib/main.dart',
            'local': 'lib/flavors/local.dart',
          },
        },
        applicationIds: <String, Map<String, String>>{
          'android': <String, String>{'local': 'com.example.flavor.local'},
        },
      );
      final file = File(
        p.join(Directory.systemTemp.path, 'hyfens-flavor-config.yaml'),
      );
      addTearDown(() => file.delete());

      file.writeAsStringSync(config.encode());
      final loaded = ToolConfig.load(file);

      expect(
        loaded
            .resolveEntrypoint(target: 'android', flavor: 'local')
            .entrypointPath,
        'lib/flavors/local.dart',
      );
      expect(
        loaded.applicationIdFor('android', flavor: 'local'),
        'com.example.flavor.local',
      );
      expect(ToolConfig.load(file).encode(), config.encode());
    });

    test('requires an explicit path when a flavor has no mapping', () {
      expect(
        () => const ToolConfig().resolveEntrypoint(
          target: 'android',
          flavor: 'local',
        ),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            'T1208',
          ),
        ),
      );
      final selection = const ToolConfig().resolveEntrypoint(
        target: 'android',
        flavor: 'local',
        entrypointPath: r'lib\flavors\local.dart',
      );
      expect(selection.entrypointPath, 'lib/flavors/local.dart');
    });

    test('rejects unsafe and non-library entrypoint paths', () {
      for (final path in <String>[
        '../main.dart',
        '/tmp/main.dart',
        'tool/main.dart',
        'lib/../main.dart',
        'lib/main.txt',
      ]) {
        expect(
          () => normalizeEntrypointPath(path),
          throwsA(
            isA<ToolFailure>().having(
              (failure) => failure.diagnostics.single.code,
              'code',
              'T1206',
            ),
          ),
          reason: path,
        );
      }
    });

    test(
      'fails closed when a configured flavor entrypoint is missing',
      () async {
        final root = await _createProject();
        addTearDown(() => root.delete(recursive: true));
        await File(p.join(root.path, 'tool.yaml')).writeAsString(
          const ToolConfig(
            applicationId: 'com.example.flavor',
            entrypoints: <String, Map<String, String>>{
              'android': <String, String>{'local': 'lib/flavors/missing.dart'},
            },
          ).encode(),
        );

        await expectLater(
          HyfensToolchain().release(
            target: 'android',
            flavor: 'local',
            projectPath: root.path,
            metadataOnly: true,
          ),
          throwsA(
            isA<ToolFailure>().having(
              (failure) => failure.diagnostics.single.code,
              'code',
              'T1402',
            ),
          ),
        );
      },
    );

    test('release and analysis retain the selected flavor boundary', () async {
      final root = await _createProject();
      addTearDown(() => root.delete(recursive: true));
      await _writeFlavorConfig(root);
      final tool = HyfensToolchain();

      final release = await tool.release(
        target: 'android',
        flavor: 'local',
        projectPath: root.path,
        metadataOnly: true,
      );

      expect(release.entrypointPath, 'lib/flavors/local.dart');
      expect(release.flavor, 'local');
      expect(release.applicationId, 'com.example.flavor.local');
      expect(release.build['entrypoint'], 'lib/flavors/local.dart');
      expect(release.build['flavor'], 'local');
      final stored = ToolStore(tool.project(projectPath: root.path))
          .readRelease(release.releaseId);
      expect(stored.entrypointPath, release.entrypointPath);
      expect(stored.flavor, release.flavor);

      await File(p.join(root.path, 'lib', 'flavors', 'local.dart'))
          .writeAsString('''
void main() {
  localValue();
}

int localValue() => 2;
''');
      expect(
        tool
            .analyze(projectPath: root.path, releaseId: release.releaseId)
            .release
            .entrypointPath,
        'lib/flavors/local.dart',
      );
      expect(
        () => tool.analyze(
          projectPath: root.path,
          releaseId: release.releaseId,
          entrypointPath: 'lib/main.dart',
        ),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            'R5007',
          ),
        ),
      );
    });

    test(
      'selects a matching baseline when multiple flavor releases exist',
      () async {
        final root = await _createProject();
        addTearDown(() => root.delete(recursive: true));
        await File(p.join(root.path, 'tool.yaml')).writeAsString(
          const ToolConfig(
            applicationId: 'com.example.flavor',
            entrypoints: <String, Map<String, String>>{
              'android': <String, String>{
                'default': 'lib/main.dart',
                'local': 'lib/flavors/local.dart',
              },
            },
            applicationIds: <String, Map<String, String>>{
              'android': <String, String>{'local': 'com.example.flavor.local'},
            },
          ).encode(),
        );
        final tool = HyfensToolchain();
        final local = await tool.release(
          target: 'android',
          flavor: 'local',
          projectPath: root.path,
          metadataOnly: true,
        );
        await tool.release(
          target: 'android',
          projectPath: root.path,
          metadataOnly: true,
        );

        expect(
          tool
              .analyze(projectPath: root.path, flavor: 'local')
              .release
              .releaseId,
          local.releaseId,
        );
        await expectLater(
          () => tool.analyze(projectPath: root.path),
          throwsA(
            isA<ToolFailure>().having(
              (failure) => failure.diagnostics.single.code,
              'code',
              'R5002',
            ),
          ),
        );
      },
    );
  });

  group('project detach', () {
    test('does not delete a lone generic tool.yaml', () async {
      final root = await _createProject();
      addTearDown(() => root.delete(recursive: true));
      final config = File(p.join(root.path, 'tool.yaml'));
      await config.writeAsString(const ToolConfig().encode());

      final result = await HyfensToolchain().detach(
        projectPath: root.path,
        confirmation: 'DETACH',
      );

      expect(result.removedPaths, isEmpty);
      expect(result.retainedPaths, contains('tool.yaml'));
      expect(config.existsSync(), isTrue);
    });

    test('dry-run and confirmation remove only Hyfens state', () async {
      final root = await _createProject();
      addTearDown(() => root.delete(recursive: true));
      await _writeAttachableState(root);
      final source = File(p.join(root.path, 'lib', 'main.dart'));
      final native = Directory(p.join(root.path, 'android'));
      final tool = HyfensToolchain();

      final preview = await tool.detach(projectPath: root.path, dryRun: true);
      expect(preview.removedPaths, contains('tool.yaml'));
      expect(preview.removedPaths, contains('hyfens.yaml'));
      expect(preview.removedPaths, contains('.tool'));
      expect(source.existsSync(), isTrue);
      expect(native.existsSync(), isTrue);
      expect(File(p.join(root.path, 'tool.yaml')).existsSync(), isTrue);

      expect(
        () => tool.detach(projectPath: root.path, confirmation: 'wrong'),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            ToolDiagnosticCodes.detachConfirmationRequired,
          ),
        ),
      );
      expect(File(p.join(root.path, 'hyfens.yaml')).existsSync(), isTrue);

      final result = await tool.detach(
        projectPath: root.path,
        confirmation: 'DETACH',
      );
      expect(result.toJson()['result'], 'DETACHED');
      expect(File(p.join(root.path, 'tool.yaml')).existsSync(), isFalse);
      expect(File(p.join(root.path, 'hyfens.yaml')).existsSync(), isFalse);
      expect(Directory(p.join(root.path, '.tool')).existsSync(), isFalse);
      expect(source.existsSync(), isTrue);
      expect(native.existsSync(), isTrue);
    });

    test(
      'refuses unexpected store content without deleting anything',
      () async {
        final root = await _createProject();
        addTearDown(() => root.delete(recursive: true));
        await _writeAttachableState(root);
        await File(p.join(root.path, '.tool', 'notes.txt'))
            .writeAsString('keep');

        expect(
          () => HyfensToolchain().detach(
            projectPath: root.path,
            confirmation: 'DETACH',
          ),
          throwsA(
            isA<ToolFailure>().having(
              (failure) => failure.diagnostics.single.code,
              'code',
              ToolDiagnosticCodes.detachUnexpectedContent,
            ),
          ),
        );
        expect(File(p.join(root.path, 'tool.yaml')).existsSync(), isTrue);
        expect(Directory(p.join(root.path, '.tool')).existsSync(), isTrue);
      },
    );

    test(
      'can detach generated artifacts while retaining signing keys',
      () async {
        final root = await _createProject();
        addTearDown(() => root.delete(recursive: true));
        await _writeAttachableState(root);
        final key = File(p.join(root.path, '.tool', 'keys', 'private.key'));
        await key.writeAsString('key material');

        final result = await HyfensToolchain().detach(
          projectPath: root.path,
          confirmation: 'DETACH',
          keepKeys: true,
        );

        expect(key.existsSync(), isTrue);
        expect(
          Directory(p.join(root.path, '.tool', 'keys')).existsSync(),
          isTrue,
        );
        expect(
          Directory(p.join(root.path, '.tool', 'releases')).existsSync(),
          isFalse,
        );
        expect(result.retainedPaths, contains('.tool/keys'));
      },
    );
  });
}
