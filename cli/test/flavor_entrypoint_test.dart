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
