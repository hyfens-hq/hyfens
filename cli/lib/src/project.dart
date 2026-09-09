import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'canonical.dart';
import 'diagnostics.dart';

final class FlutterProject {
  FlutterProject({
    required this.root,
    required this.packageName,
    required this.version,
    required this.pubspec,
    required this.pubspecFile,
    required this.pubspecLockFile,
    required this.packageConfigFile,
    required this.applicationId,
    required this.androidApplicationId,
    required this.iosApplicationId,
  });

  final Directory root;
  final String packageName;
  final String? version;
  final Map<String, Object?> pubspec;
  final File pubspecFile;
  final File pubspecLockFile;
  final File? packageConfigFile;
  final String applicationId;
  final String? androidApplicationId;
  final String? iosApplicationId;

  Directory get libDirectory => Directory(p.join(root.path, 'lib'));
  File get mainFile => File(p.join(libDirectory.path, 'main.dart'));
  Directory get toolDirectory => Directory(p.join(root.path, '.tool'));
  File get configFile => File(p.join(root.path, 'tool.yaml'));

  /// Safe project-to-profile binding written by `hyfens init`.
  File get hyfensConfigFile => File(p.join(root.path, 'hyfens.yaml'));

  String relative(FileSystemEntity entity) => relativePath(root, entity);

  String applicationIdFor(String target) {
    if (target == 'android' && androidApplicationId != null) {
      return androidApplicationId!;
    }
    if (target == 'ios' && iosApplicationId != null) return iosApplicationId!;
    return applicationId;
  }
}

final class ProjectDiscovery {
  const ProjectDiscovery();

  FlutterProject discover({String? projectPath, Directory? start}) {
    final root = _locateRoot(projectPath, start ?? Directory.current);
    final pubspecFile = File(p.join(root.path, 'pubspec.yaml'));
    final raw = loadYaml(pubspecFile.readAsStringSync());
    if (raw is! YamlMap) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1003',
        summary: 'pubspec.yaml is not a mapping',
        detail: pubspecFile.path,
      );
    }
    final pubspec = _toDart(raw);
    final packageName = pubspec['name'];
    if (packageName is! String ||
        !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(packageName)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1004',
        summary: 'Flutter project package name is invalid',
        detail: 'pubspec.yaml must contain a valid lowercase package name.',
        path: pubspecFile.path,
      );
    }
    final flutterSection = pubspec['flutter'];
    if (flutterSection is! Map<String, Object?>) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1005',
        summary: 'Project is not a Flutter application',
        detail: 'The root pubspec.yaml has no flutter section.',
        path: pubspecFile.path,
      );
    }
    final androidId = _androidApplicationId(root);
    final iosId = _iosApplicationId(root);
    final applicationId = androidId ?? iosId ?? packageName;
    final packageConfigFile = File(
      p.join(root.path, '.dart_tool', 'package_config.json'),
    );
    return FlutterProject(
      root: root,
      packageName: packageName,
      version: pubspec['version'] as String?,
      pubspec: pubspec,
      pubspecFile: pubspecFile,
      pubspecLockFile: File(p.join(root.path, 'pubspec.lock')),
      packageConfigFile: packageConfigFile.existsSync()
          ? packageConfigFile
          : null,
      applicationId: applicationId,
      androidApplicationId: androidId,
      iosApplicationId: iosId,
    );
  }

  Directory _locateRoot(String? explicitPath, Directory start) {
    if (explicitPath != null) {
      final entity =
          FileSystemEntity.typeSync(explicitPath) == FileSystemEntityType.file
          ? File(explicitPath).parent
          : Directory(explicitPath);
      final root = Directory(entity.absolute.path);
      if (!File(p.join(root.path, 'pubspec.yaml')).existsSync()) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1001',
          summary: 'Flutter project not found',
          detail: 'No pubspec.yaml was found at ${root.path}.',
          action: 'Run from a project or pass --project <directory>.',
        );
      }
      return root;
    }
    var directory = start.absolute;
    for (var depth = 0; depth < 64; depth++) {
      if (File(p.join(directory.path, 'pubspec.yaml')).existsSync()) {
        return directory;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'T1001',
      summary: 'Flutter project not found',
      detail: 'No pubspec.yaml was found from ${start.absolute.path} upward.',
      action: 'Run from a project or pass --project <directory>.',
    );
  }
}

Map<String, Object?> _toDart(YamlMap map) => <String, Object?>{
  for (final entry in map.entries)
    if (entry.key is String) entry.key! as String: _yamlValue(entry.value),
};

Object? _yamlValue(Object? value) {
  if (value is YamlMap) return _toDart(value);
  if (value is YamlList) return value.map(_yamlValue).toList(growable: false);
  return value;
}

String? _androidApplicationId(Directory root) {
  final files = <File>[
    File(p.join(root.path, 'android', 'app', 'build.gradle')),
    File(p.join(root.path, 'android', 'app', 'build.gradle.kts')),
  ];
  for (final file in files) {
    if (!file.existsSync()) continue;
    final source = file.readAsStringSync();
    final match = RegExp(r'''applicationId\s*(?:=|\(|)\s*["']([^"']+)''')
        .firstMatch(source);
    if (match != null) return match.group(1);
  }
  for (final file in files) {
    if (!file.existsSync()) continue;
    final source = file.readAsStringSync();
    final match = RegExp(r'''namespace\s*(?:=|\(|)\s*["']([^"']+)''')
        .firstMatch(source);
    if (match != null) return match.group(1);
  }
  return null;
}

String? _iosApplicationId(Directory root) {
  final file = File(
    p.join(root.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
  );
  if (!file.existsSync()) return null;
  final source = file.readAsStringSync();
  final values = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);')
      .allMatches(source)
      .map((match) => match.group(1)!.trim());
  return values
          .firstWhere((value) => !value.startsWith(r'$('), orElse: () => '')
          .isEmpty
      ? null
      : values.firstWhere((value) => !value.startsWith(r'$('));
}

String? extractFlutterVersion(String output) {
  final match = RegExp(r'Flutter\s+(\d+\.\d+\.\d+)').firstMatch(output);
  return match?.group(1);
}

String? extractDartVersion(String output) {
  final match = RegExp(r'Dart SDK version:\s*(\d+\.\d+\.\d+)')
      .firstMatch(output);
  return match?.group(1);
}

String flutterToolchainStatus(bool available, String? version) {
  if (!available) return 'NOT AVAILABLE';
  if (version == null) return 'NOT TESTED';
  return version.startsWith('3.47.') ? 'SUPPORTED' : 'NOT TESTED';
}

String dartToolchainStatus(bool available, String? version) {
  if (!available) return 'NOT AVAILABLE';
  if (version == null) return 'NOT TESTED';
  return version.startsWith('3.13.') ? 'SUPPORTED' : 'NOT TESTED';
}

Map<String, Object?> decodeJsonObject(File file) {
  final value = jsonDecode(file.readAsStringSync());
  if (value is! Map<String, Object?>) {
    throw FormatException('${file.path} must contain a JSON object');
  }
  return value;
}
