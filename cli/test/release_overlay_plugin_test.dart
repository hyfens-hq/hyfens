import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<Directory> _createOverlayProject() async {
  final root = await Directory.systemTemp.createTemp(
    'hyfens-release-overlay-plugin-',
  );
  final create = await Process.run(
    'flutter',
    <String>[
      'create',
      '--no-pub',
      '--platforms=android',
      '--project-name=overlay_app',
      '--org=dev.example',
      '.',
    ],
    workingDirectory: root.path,
  );
  if (create.exitCode != 0) {
    throw StateError('${create.stdout}\n${create.stderr}');
  }

  await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: overlay_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  integration_test:
    sdk: flutter
  flutter_test:
    sdk: flutter

flutter:
  uses-material-design: true
''');
  await File(p.join(root.path, 'lib', 'main.dart')).writeAsString('''
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(home: Text('overlay test')));
}
''');

  final pubGet = await Process.run(
    'flutter',
    <String>['pub', 'get'],
    workingDirectory: root.path,
  );
  if (pubGet.exitCode != 0) {
    throw StateError('${pubGet.stdout}\n${pubGet.stderr}');
  }
  return root;
}

Future<ProcessResult> _runTool(
  Directory project,
  List<String> arguments,
) => Process.run(
  Platform.resolvedExecutable,
  <String>['run', 'bin/tool.dart', '--project', project.path, ...arguments],
  workingDirectory: Directory.current.path,
);

void main() {
  test(
    'release overlay excludes a dev-only integration-test plugin from Android registrant',
    () async {
      final project = await _createOverlayProject();
      addTearDown(() => project.delete(recursive: true));

      final init = await _runTool(project, <String>['init', '--json']);
      expect(init.exitCode, 0, reason: '${init.stdout}\n${init.stderr}');
      final keys = await _runTool(project, <String>['keys', 'generate', '--json']);
      expect(keys.exitCode, 0, reason: '${keys.stdout}\n${keys.stderr}');

      final release = await _runTool(
        project,
        <String>['release', 'android', '--json'],
      );
      expect(
        release.exitCode,
        0,
        reason: '${release.stdout}\n${release.stderr}',
      );
      final body = jsonDecode(release.stdout.toString()) as Map<String, dynamic>;
      final build = body['build'] as Map<String, dynamic>;
      expect(build['status'], 'SUCCESS');
      expect(build['artifact'], endsWith('.apk'));
      expect(
        Directory(p.join(project.path, '.tool', 'releases')).existsSync(),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
