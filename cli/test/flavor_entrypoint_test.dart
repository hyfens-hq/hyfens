import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<Directory> _createFlavorProject() async {
  final root = await Directory.systemTemp.createTemp('hyfens-flavor-');
  await Directory(p.join(root.path, 'lib', 'src', 'flavors'))
      .create(recursive: true);
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
  await File(p.join(root.path, 'lib', 'src', 'flavors', 'dev.dart'))
      .writeAsString('''
void main() {
  devValue();
}

int devValue() => 1;
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
        'android': <String, String>{'dev': 'lib/src/flavors/dev.dart'},
      },
      applicationIds: <String, Map<String, String>>{
        'android': <String, String>{'dev': 'com.example.flavor.dev'},
      },
    ).encode(),
  );
}

void main() {
  test('config resolves and round-trips a flavor entrypoint and ID', () {
    const config = ToolConfig(
      applicationId: 'com.example.flavor',
      entrypoints: <String, Map<String, String>>{
        'android': <String, String>{'dev': 'lib/src/flavors/dev.dart'},
      },
      applicationIds: <String, Map<String, String>>{
        'android': <String, String>{'dev': 'com.example.flavor.dev'},
      },
    );
    final file = File(
      p.join(Directory.systemTemp.path, 'hyfens-flavor-config.yaml'),
    );
    addTearDown(() => file.delete());
    file.writeAsStringSync(config.encode());
    final loaded = ToolConfig.load(file);

    expect(
      loaded.resolveEntrypoint(target: 'android', flavor: 'dev').entrypointPath,
      'lib/src/flavors/dev.dart',
    );
    expect(
      loaded.applicationIdFor('android', flavor: 'dev'),
      'com.example.flavor.dev',
    );
    expect(loaded.encode(), config.encode());
  });

  test(
    'automatic init preserves the native dev identity through release',
    () async {
      final root = await _createFlavorProject();
      addTearDown(() => root.delete(recursive: true));
      await File(p.join(root.path, 'android', 'app', 'build.gradle'))
          .writeAsString('''
android {
  defaultConfig { applicationId "com.example.flavor" }
  productFlavors { dev { applicationIdSuffix ".dev" } }
}
''');
      final toolchain = HyfensToolchain();
      final source = File(p.join(root.path, 'lib/src/flavors/dev.dart'));
      await source.writeAsString(
        'void main() { devValue(); }\nint devValue() { return 1; }\n',
      );
      final initialized = await ProjectInitializationService(
        toolchain: toolchain,
        authStorage: AuthStorage(root: Directory(p.join(root.path, '.auth'))),
      ).initialize(projectPath: root.path);
      await toolchain.generateKeys(projectPath: root.path);
      // Exercise real init, not a hand-written application_ids override.
      final release = await toolchain.release(
        target: 'android',
        projectPath: root.path,
        metadataOnly: true,
      );
      expect(release.flavor, 'dev');
      expect(release.applicationId, 'com.example.flavor.dev');
      expect(initialized.binding.runtimeApplicationId, release.applicationId);
      expect(
        toolchain.resolveApplicationId(
          project: initialized.result.project,
          target: 'android',
          flavor: 'dev',
        ),
        release.applicationId,
      );
      await source.writeAsString(
        source.readAsStringSync().replaceFirst('return 1', 'return 2'),
      );
      final patch = await toolchain.patch(
        projectPath: root.path,
        releaseId: release.releaseId,
      );
      expect(patch.artifact.applicationId, release.applicationId);
      expect(patch.artifact.releaseId, release.releaseId);
    },
  );

  test('native flavor fallback does not require tool configuration', () async {
    final root = await _createFlavorProject();
    addTearDown(() => root.delete(recursive: true));
    await _nativeDev(root);
    final release = await HyfensToolchain().release(
      target: 'android',
      projectPath: root.path,
      metadataOnly: true,
    );
    expect(release.applicationId, 'com.example.flavor.dev');
  });

  test(
    'stale base identity fails closed and reviewed force init repairs it',
    () async {
      final root = await _createFlavorProject();
      addTearDown(() => root.delete(recursive: true));
      await _nativeDev(root);
      await writeDefaultConfig(
        File(p.join(root.path, 'tool.yaml')),
        applicationId: 'com.example.flavor',
      );
      await writeHyfensBinding(
        File(p.join(root.path, 'hyfens.yaml')),
        binding: const HyfensProjectBinding(
          profile: 'local',
          flavor: 'dev',
          runtimeApplicationId: 'com.example.flavor',
        ),
      );
      final tool = HyfensToolchain();
      final initialization = ProjectInitializationService(
        toolchain: tool,
        authStorage: AuthStorage(root: Directory(p.join(root.path, '.auth'))),
      );
      expect(
        () => tool.resolveApplicationId(
          project: tool.project(projectPath: root.path),
          target: 'android',
          flavor: 'dev',
        ),
        _identityFailure,
      );
      await expectLater(
        tool.release(
          target: 'android',
          projectPath: root.path,
          metadataOnly: true,
        ),
        _identityFailure,
      );
      await expectLater(
        initialization.initialize(projectPath: root.path),
        _identityFailure,
      );
      final repaired = await initialization.initialize(
        projectPath: root.path,
        force: true,
      );
      expect(repaired.binding.runtimeApplicationId, 'com.example.flavor.dev');
      final release = await tool.release(
        target: 'android',
        projectPath: root.path,
        metadataOnly: true,
      );
      expect(release.applicationId, 'com.example.flavor.dev');
      // A later native/config identity change cannot repoint this baseline.
      await _nativeDev(root, suffix: '.other');
      final analysis = tool.analyze(
        projectPath: root.path,
        releaseId: release.releaseId,
      );
      expect(analysis.canPatch, isFalse);
      expect(analysis.diagnostics.map((d) => d.code), contains('H1205'));
    },
  );

  test(
    'different platform IDs stay separate while flavor overrides resolve',
    () async {
      final root = await _createFlavorProject();
      addTearDown(() => root.delete(recursive: true));
      await _nativeDev(root);
      final ios = File(p.join(root.path, 'ios/Flutter/Flavors/dev.xcconfig'));
      await ios.parent.create(recursive: true);
      await ios.writeAsString(
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.apple.dev\nFLUTTER_TARGET = lib/src/flavors/dev.dart\n',
      );
      final tool = HyfensToolchain();
      final initialized = await ProjectInitializationService(
        toolchain: tool,
        authStorage: AuthStorage(root: Directory(p.join(root.path, '.auth'))),
      ).initialize(projectPath: root.path);
      expect(initialized.binding.runtimeApplicationId, isNull);
      for (final target in ['android', 'ios']) {
        final release = await tool.release(
          target: target,
          projectPath: root.path,
          flavor: 'dev',
          entrypointPath: 'lib/src/flavors/dev.dart',
          metadataOnly: true,
        );
        expect(
          release.applicationId,
          target == 'ios' ? 'com.example.apple.dev' : 'com.example.flavor.dev',
        );
      }
    },
  );

  test('explicit entrypoint works without a flavor mapping', () {
    final selection = const ToolConfig().resolveEntrypoint(
      target: 'android',
      flavor: 'dev',
      entrypointPath: r'lib\src\flavors\dev.dart',
    );
    expect(selection.entrypointPath, 'lib/src/flavors/dev.dart');
    expect(selection.flavor, 'dev');
  });

  test('rejects unsafe entrypoint paths and missing flavor mappings', () {
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
    expect(
      () => const ToolConfig().resolveEntrypoint(
        target: 'android',
        flavor: 'dev',
      ),
      throwsA(
        isA<ToolFailure>().having(
          (failure) => failure.diagnostics.single.code,
          'code',
          'T1208',
        ),
      ),
    );
  });

  test('release metadata records the selected flavor boundary', () async {
    final root = await _createFlavorProject();
    addTearDown(() => root.delete(recursive: true));
    await _writeFlavorConfig(root);

    final release = await HyfensToolchain().release(
      target: 'android',
      flavor: 'dev',
      projectPath: root.path,
      metadataOnly: true,
    );

    expect(release.entrypointPath, 'lib/src/flavors/dev.dart');
    expect(release.flavor, 'dev');
    expect(release.applicationId, 'com.example.flavor.dev');
    expect(release.build['entrypoint'], 'lib/src/flavors/dev.dart');
    expect(release.build['flavor'], 'dev');
    expect(
      ToolStore(HyfensToolchain().project(projectPath: root.path))
          .readRelease(release.releaseId)
          .entrypointPath,
      release.entrypointPath,
    );
  });
}

Matcher get _identityFailure => throwsA(
  isA<ToolFailure>().having(
    (failure) => failure.diagnostics.single.code,
    'code',
    'H1205',
  ),
);

Future<void> _nativeDev(Directory root, {String suffix = '.dev'}) =>
    File(p.join(root.path, 'android/app/build.gradle')).writeAsString('''
android {
  defaultConfig { applicationId "com.example.flavor" }
  productFlavors { dev { applicationIdSuffix "$suffix" } }
}
''');
