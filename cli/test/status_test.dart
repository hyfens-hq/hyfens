import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

Future<Directory> createStatusProject() async {
  final root = await Directory.systemTemp.createTemp('hyfens-status-');
  await Directory('${root.path}/lib').create(recursive: true);
  await Directory('${root.path}/.dart_tool').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: status_app
version: 1.0.0
environment:
  sdk: ^3.13.0
flutter: {}
dependencies: {}
''');
  await File('${root.path}/pubspec.lock').writeAsString('''
packages: {}
sdks:
  dart: ">=3.13.0 <4.0.0"
''');
  await File('${root.path}/lib/main.dart').writeAsString('void main() {}\n');
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'status_app',
          'rootUri': root.uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
      ],
    }),
  );
  return root;
}

void main() {
  test(
    'status is local-only and does not emit paths, keys, or guest data',
    () async {
      final root = await createStatusProject();
      addTearDown(() => root.delete(recursive: true));

      final status = await HyfensToolchain().status(projectPath: root.path);
      final encoded = jsonEncode(status.toJson());

      expect(status.result, 'NOT_INITIALIZED');
      expect(status.toJson()['runtime'], <String, String>{
        'scope': 'LOCAL_TOOL_ONLY',
        'status': 'NOT_CONNECTED',
        'introspection': 'NOT_AVAILABLE',
      });
      expect(encoded, isNot(contains(root.path)));
      expect(encoded, isNot(contains('private.key')));
      expect(encoded, isNot(contains('guest-secret')));
    },
  );

  test(
    'status inventories bounded local artifacts without reading their contents',
    () async {
      final root = await createStatusProject();
      addTearDown(() => root.delete(recursive: true));
      await writeDefaultConfig(
        File('${root.path}/tool.yaml'),
        applicationId: 'com.example.status',
      );
      final releaseDirectory = Directory(
        '${root.path}/.tool/releases/release-1',
      );
      final patchDirectory = Directory('${root.path}/.tool/patches/release-1');
      await Directory('${root.path}/.tool/keys').create(recursive: true);
      await releaseDirectory.create(recursive: true);
      await patchDirectory.create(recursive: true);
      await File('${releaseDirectory.path}/metadata.json')
          .writeAsString('guest-secret-release-metadata');
      await File('${patchDirectory.path}/000001.patch')
          .writeAsString('guest-secret-patch-bytes');

      final status = await HyfensToolchain().status(projectPath: root.path);
      final store = status.toJson()['store']! as Map<String, Object?>;
      final encoded = jsonEncode(status.toJson());

      expect(status.configurationStatus, 'SUPPORTED');
      expect(status.result, 'READY');
      expect(store['status'], 'READY');
      expect(store['releaseDirectories'], 1);
      expect(store['releaseMetadataFiles'], 1);
      expect(store['patchDirectories'], 1);
      expect(store['patchArtifacts'], 1);
      expect(encoded, isNot(contains('guest-secret')));
      expect(encoded, isNot(contains(root.path)));
    },
  );

  test(
    'status marks malformed configuration without exposing its path',
    () async {
      final root = await createStatusProject();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/tool.yaml').writeAsString('''
version: 1
instrumentation: false
''');

      final status = await HyfensToolchain().status(projectPath: root.path);
      final encoded = jsonEncode(status.toJson());

      expect(status.result, 'WARNING');
      expect(status.configurationStatus, 'INVALID');
      expect(
        status.diagnostics.map((diagnostic) => diagnostic.code),
        contains('T1203'),
      );
      expect(encoded, isNot(contains(root.path)));
    },
  );

  test('status inventory stops at the bounded directory limit', () async {
    final root = await createStatusProject();
    addTearDown(() => root.delete(recursive: true));
    final store = ToolStore(
      const ProjectDiscovery().discover(projectPath: root.path),
    );
    await store.ensure();
    for (var index = 0; index < 257; index++) {
      await Directory('${store.releases.path}/release-$index').create();
    }

    final inventory = await store.inspectInventory();

    expect(inventory.status, 'READY');
    expect(inventory.releaseDirectories, 256);
    expect(inventory.scanTruncated, isTrue);
  });

  test(
    'tool status --json is registered as a machine-readable command',
    () async {
      final root = await createStatusProject();
      addTearDown(() => root.delete(recursive: true));
      final current = Directory.current;
      final cliDirectory = File('${current.path}/bin/tool.dart').existsSync()
          ? current
          : Directory('${current.path}/cli');
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        File('${cliDirectory.path}/bin/tool.dart').absolute.path,
        'status',
        '--json',
        '--project',
        root.path,
      ], workingDirectory: cliDirectory.path);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final decoded =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(decoded['schemaVersion'], 1);
      expect(decoded['runtime'], isA<Map<String, Object?>>());
      expect(result.stdout.toString(), isNot(contains(root.path)));
    },
    // Includes compilation of the real CLI, not only the local status read.
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
