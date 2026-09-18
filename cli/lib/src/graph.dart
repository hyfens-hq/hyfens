import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'canonical.dart';
import 'diagnostics.dart';
import 'project.dart';

enum PackageSourceType { application, path, hosted, git, sdk, unknown }

final class ProjectPackage {
  ProjectPackage({
    required this.name,
    required this.version,
    required this.source,
    required this.root,
    required this.packageUri,
    required this.isPlugin,
    required this.hasNativeImplementation,
    required this.pubspecFingerprint,
    required this.lockDescription,
  });

  final String name;
  final String? version;
  final PackageSourceType source;
  final Directory? root;
  final String packageUri;
  final bool isPlugin;
  final bool hasNativeImplementation;
  final String? pubspecFingerprint;
  final String? lockDescription;

  bool get isPureDart => !isPlugin && !hasNativeImplementation;

  Map<String, Object?> toJson(Directory projectRoot) => <String, Object?>{
    'name': name,
    'version': version,
    'source': source.name,
    'path': root == null
        ? null
        : isWithin(projectRoot, root!)
        ? relativePath(projectRoot, root!)
        : '<external>',
    'packageUri': packageUri,
    'plugin': isPlugin,
    'native': hasNativeImplementation,
    'pubspecFingerprint': pubspecFingerprint,
    'lockDescription': lockDescription,
  };
}

final class ProjectGraph {
  ProjectGraph({
    required this.project,
    required List<ProjectPackage> packages,
    required this.packageConfigPresent,
    required this.lockfilePresent,
  }) : packages = List.unmodifiable(packages);

  final FlutterProject project;
  final List<ProjectPackage> packages;
  final bool packageConfigPresent;
  final bool lockfilePresent;

  ProjectPackage get application =>
      packages.firstWhere((item) => item.name == project.packageName);

  ProjectPackage? byName(String name) {
    for (final item in packages) {
      if (item.name == name) return item;
    }
    return null;
  }

  String get fingerprint => digestJson(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'packageConfigPresent': packageConfigPresent,
    'lockfilePresent': lockfilePresent,
    'packages': packages
        .map((item) => item.toJson(project.root))
        .toList(growable: false),
  };
}

final class ProjectGraphLoader {
  const ProjectGraphLoader();

  ProjectGraph load(FlutterProject project) {
    final lock = _readLock(project.pubspecLockFile);
    final config = project.packageConfigFile == null
        ? const <_PackageConfigEntry>[]
        : _readPackageConfig(project.packageConfigFile!);
    final lockEntries = lock;
    final packageNames = <String>{project.packageName, ...lockEntries.keys};
    packageNames.addAll(config.map((entry) => entry.name));
    final packages = <ProjectPackage>[];
    for (final name in packageNames.toList()..sort()) {
      if (!RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(name)) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1303',
          summary: 'Dependency graph contains an invalid package name',
          detail: name,
        );
      }
      final matchingConfig = config.where((entry) => entry.name == name);
      final configEntry = matchingConfig.isEmpty ? null : matchingConfig.first;
      final lockEntry = lockEntries[name];
      final root = configEntry?.root;
      final source = name == project.packageName
          ? PackageSourceType.application
          : _sourceType(lockEntry?['source']);
      final pubspec = root == null ? null : _readPackagePubspec(root);
      final version =
          (lockEntry?['version'] as String?) ??
          (pubspec?['version'] as String?);
      final plugin = _hasPlugin(pubspec);
      final native =
          plugin ||
          (root != null &&
              <String>[
                'android',
                'ios',
                'macos',
                'windows',
                'linux',
              ].any((name) => Directory(p.join(root.path, name)).existsSync()));
      packages.add(
        ProjectPackage(
          name: name,
          version: version,
          source: source,
          root: root,
          packageUri: configEntry?.packageUri ?? 'lib/',
          isPlugin: plugin,
          hasNativeImplementation: native,
          pubspecFingerprint: pubspec == null
              ? null
              : digestJson(_normalizeGraphValue(pubspec, project.root)),
          lockDescription: _description(
            lockEntry?['description'],
            project.root,
          ),
        ),
      );
    }
    return ProjectGraph(
      project: project,
      packages: packages,
      packageConfigPresent: project.packageConfigFile != null,
      lockfilePresent: project.pubspecLockFile.existsSync(),
    );
  }
}

Map<String, Map<String, Object?>> _readLock(File file) {
  if (!file.existsSync()) return <String, Map<String, Object?>>{};
  final raw = loadYaml(file.readAsStringSync());
  if (raw is! YamlMap) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'T1301',
      summary: 'pubspec.lock is not a mapping',
      detail: file.path,
    );
  }
  final packages = raw['packages'];
  if (packages is! YamlMap) return <String, Map<String, Object?>>{};
  return <String, Map<String, Object?>>{
    for (final entry in packages.entries)
      if (entry.key is String && entry.value is YamlMap)
        entry.key! as String: _yamlMap(entry.value! as YamlMap),
  };
}

List<_PackageConfigEntry> _readPackageConfig(File file) {
  final value = jsonDecode(file.readAsStringSync());
  if (value is! Map<String, Object?> || value['packages'] is! List<Object?>) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'T1302',
      summary: 'package_config.json is malformed',
      detail: file.path,
    );
  }
  final result = <_PackageConfigEntry>[];
  for (final raw in value['packages']! as List<Object?>) {
    if (raw is! Map<String, Object?> ||
        raw['name'] is! String ||
        raw['rootUri'] is! String ||
        raw['packageUri'] is! String ||
        !RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(raw['name']! as String) ||
        _packageUriEscapes(raw['packageUri']! as String)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1303',
        summary: 'package_config.json contains an invalid package entry',
        detail: file.path,
      );
    }
    late final Uri rootUri;
    try {
      rootUri = Uri.parse(raw['rootUri']! as String);
    } on FormatException {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1303',
        summary: 'package_config.json contains an invalid root URI',
        detail: file.path,
      );
    }
    final resolvedRoot = rootUri.isAbsolute
        ? rootUri
        : file.absolute.parent.uri.resolveUri(rootUri);
    if (resolvedRoot.scheme != 'file') continue;
    result.add(
      _PackageConfigEntry(
        name: raw['name']! as String,
        root: Directory.fromUri(resolvedRoot),
        packageUri: raw['packageUri']! as String,
      ),
    );
  }
  return List.unmodifiable(result);
}

bool _packageUriEscapes(String value) {
  final normalized = value.replaceAll(r'\', '/');
  return normalized.startsWith('/') ||
      normalized.startsWith('//') ||
      normalized.split('/').any((segment) => segment == '..');
}

Map<String, Object?> _yamlMap(YamlMap value) => <String, Object?>{
  for (final entry in value.entries)
    if (entry.key is String) entry.key! as String: _yamlValue(entry.value),
};

Object? _yamlValue(Object? value) {
  if (value is YamlMap) return _yamlMap(value);
  if (value is YamlList) return value.map(_yamlValue).toList(growable: false);
  return value;
}

Map<String, Object?>? _readPackagePubspec(Directory root) {
  final file = File(p.join(root.path, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  final raw = loadYaml(file.readAsStringSync());
  return raw is YamlMap ? _yamlMap(raw) : null;
}

bool _hasPlugin(Map<String, Object?>? pubspec) {
  final flutter = pubspec?['flutter'];
  if (flutter is! Map<String, Object?>) return false;
  return flutter['plugin'] is Map<String, Object?>;
}

PackageSourceType _sourceType(Object? source) => switch (source) {
  'path' => PackageSourceType.path,
  'hosted' => PackageSourceType.hosted,
  'git' => PackageSourceType.git,
  'sdk' => PackageSourceType.sdk,
  _ => PackageSourceType.unknown,
};

String? _description(Object? value, Directory projectRoot) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is Map<String, Object?>) {
    return canonicalJson(_normalizeGraphValue(value, projectRoot));
  }
  return value.toString();
}

Object? _normalizeGraphValue(Object? value, Directory projectRoot) {
  if (value is List<Object?>) {
    return value
        .map((item) => _normalizeGraphValue(item, projectRoot))
        .toList(growable: false);
  }
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key: _normalizeGraphValue(entry.value, projectRoot),
    };
  }
  if (value is String && _looksLikePathMaterial(value)) {
    final normalized = value.replaceAll(r'\', '/');
    final path = p.isAbsolute(normalized)
        ? normalized
        : normalized.startsWith('file://')
        ? Uri.tryParse(normalized)?.toFilePath()
        : null;
    if (path != null) {
      final absolute = Directory(path);
      if (isWithin(projectRoot, absolute)) {
        return relativePath(projectRoot, absolute);
      }
      return '<external>';
    }
  }
  return value;
}

bool _looksLikePathMaterial(String value) =>
    value.startsWith('/') ||
    RegExp(r'^[A-Za-z]:/').hasMatch(value) ||
    value.startsWith('file://');

final class _PackageConfigEntry {
  const _PackageConfigEntry({
    required this.name,
    required this.root,
    required this.packageUri,
  });

  final String name;
  final Directory root;
  final String packageUri;
}
