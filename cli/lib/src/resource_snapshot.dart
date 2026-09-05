import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'canonical.dart';
import 'diagnostics.dart';
import 'graph.dart';
import 'project.dart';

const resourceSnapshotSchemaVersion = 1;
const _maxResourceEntries = 100000;
const _maxResourceFileBytes = 512 * 1024 * 1024;

enum ResourceInputKind { asset, font, native }

final class ResourceSnapshotFailure implements Exception {
  const ResourceSnapshotFailure({
    required this.kind,
    required this.path,
    required this.detail,
  });

  final ResourceInputKind kind;
  final String path;
  final String detail;

  String get diagnosticCode => switch (kind) {
    ResourceInputKind.asset => ToolDiagnosticCodes.resourceAssetChanged,
    ResourceInputKind.font => ToolDiagnosticCodes.resourceFontChanged,
    ResourceInputKind.native => ToolDiagnosticCodes.resourceNativeChanged,
  };

  ToolDiagnostic toDiagnostic() => ToolDiagnostic(
    code: diagnosticCode,
    severity: DiagnosticSeverity.error,
    summary: switch (kind) {
      ResourceInputKind.asset => 'Packaged asset input is unsafe or unreadable',
      ResourceInputKind.font => 'Packaged font input is unsafe or unreadable',
      ResourceInputKind.native =>
        'Native packaged resource input is unsafe or unreadable',
    },
    detail: detail,
    path: path,
    action: 'Create a new base release after correcting the packaged resource input.',
    storeReleaseRequired: true,
  );

  @override
  String toString() => '$path: $detail';
}

final class ResourceSnapshotEntry {
  const ResourceSnapshotEntry({
    required this.kind,
    required this.packageName,
    required this.path,
    required this.platform,
    required this.size,
    required this.sha256,
    this.metadataFingerprint,
  });

  final ResourceInputKind kind;
  final String packageName;
  final String path;
  final String? platform;
  final int size;
  final String sha256;
  final String? metadataFingerprint;

  String get key => '${kind.name}|${platform ?? ''}|$packageName|$path';

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'package': packageName,
    'path': path,
    'platform': platform,
    'size': size,
    'sha256': sha256,
    if (metadataFingerprint != null) 'metadataFingerprint': metadataFingerprint,
  };

  static ResourceSnapshotEntry decode(Object? value) {
    if (value is! Map<String, Object?> ||
        value['kind'] is! String ||
        value['package'] is! String ||
        value['path'] is! String ||
        value['size'] is! int ||
        value['sha256'] is! String) {
      throw const FormatException('Invalid resource snapshot entry');
    }
    final kind = ResourceInputKind.values.where(
      (item) => item.name == value['kind'],
    );
    if (kind.length != 1) {
      throw const FormatException('Invalid resource snapshot entry kind');
    }
    final packageName = value['package']! as String;
    if (!RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(packageName)) {
      throw const FormatException('Invalid resource snapshot package');
    }
    final path = _validateRelativeSnapshotPath(value['path']! as String);
    final platform = value['platform'] as String?;
    if (kind.single == ResourceInputKind.native &&
        platform != 'android' &&
        platform != 'ios') {
      throw const FormatException('Invalid native resource snapshot platform');
    }
    if (kind.single != ResourceInputKind.native && platform != null) {
      throw const FormatException('Non-native resource has a platform');
    }
    final size = value['size']! as int;
    final sha256 = value['sha256']! as String;
    final metadataFingerprint = value['metadataFingerprint'];
    if (size < 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
        (metadataFingerprint != null &&
            (metadataFingerprint is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(metadataFingerprint)))) {
      throw const FormatException('Invalid resource snapshot digest');
    }
    return ResourceSnapshotEntry(
      kind: kind.single,
      packageName: packageName,
      path: path,
      platform: platform,
      size: size,
      sha256: sha256,
      metadataFingerprint: metadataFingerprint as String?,
    );
  }
}

final class ResourceSnapshotChange {
  const ResourceSnapshotChange({
    required this.kind,
    required this.packageName,
    required this.path,
    required this.platform,
    required this.reason,
  });

  final ResourceInputKind kind;
  final String packageName;
  final String path;
  final String? platform;
  final String reason;

  String get key => '${kind.name}|${platform ?? ''}|$packageName|$path|$reason';

  String get displayPath =>
      platform == null ? '$packageName/$path' : '$packageName/$platform/$path';
}

final class ResourceSnapshotDiff {
  ResourceSnapshotDiff(Iterable<ResourceSnapshotChange> changes)
    : changes = List.unmodifiable(
        changes.toList()..sort((left, right) => left.key.compareTo(right.key)),
      );

  final List<ResourceSnapshotChange> changes;

  bool get changed => changes.isNotEmpty;
}

final class ResourceSnapshot {
  ResourceSnapshot({
    required this.target,
    required Iterable<ResourceSnapshotEntry> entries,
    required this.usesMaterialDesign,
    required this.materialIconAstComplete,
    required Iterable<String> materialIconReferences,
  }) : entries = List.unmodifiable(
         entries.toList()..sort((left, right) => left.key.compareTo(right.key)),
       ),
       materialIconReferences = List.unmodifiable(
         materialIconReferences.toSet().toList()..sort(),
       ) {
    if (target != 'android' && target != 'ios') {
      throw ArgumentError.value(target, 'target', 'must be android or ios');
    }
    if (this.entries.length > _maxResourceEntries) {
      throw ArgumentError.value(entries.length, 'entries', 'too many entries');
    }
  }

  final String target;
  final List<ResourceSnapshotEntry> entries;
  final bool usesMaterialDesign;
  final bool materialIconAstComplete;
  final List<String> materialIconReferences;

  String get fingerprint => digestJson(_payloadJson());

  Map<String, Object?> _payloadJson() => <String, Object?>{
    'version': resourceSnapshotSchemaVersion,
    'target': target,
    'entries': entries.map((item) => item.toJson()).toList(growable: false),
    'materialIcons': <String, Object?>{
      'usesMaterialDesign': usesMaterialDesign,
      'astComplete': materialIconAstComplete,
      'references': materialIconReferences,
    },
  };

  Map<String, Object?> toJson() => <String, Object?>{
    ..._payloadJson(),
    'fingerprint': fingerprint,
  };

  String encode() => canonicalJson(toJson());

  static ResourceSnapshot decode(Object value) {
    final raw = value is String ? jsonDecode(value) : value;
    if (raw is! Map<String, Object?> ||
        raw['version'] != resourceSnapshotSchemaVersion ||
        raw['target'] is! String ||
        raw['entries'] is! List<Object?> ||
        raw['materialIcons'] is! Map<String, Object?> ||
        raw['fingerprint'] is! String) {
      throw const FormatException('Invalid resource snapshot');
    }
    final materialIcons = raw['materialIcons']! as Map<String, Object?>;
    if (materialIcons['usesMaterialDesign'] is! bool ||
        materialIcons['astComplete'] is! bool ||
        materialIcons['references'] is! List<Object?> ||
        (materialIcons['references']! as List<Object?>).any(
          (item) => item is! String,
        )) {
      throw const FormatException('Invalid material icon snapshot');
    }
    final entries = (raw['entries']! as List<Object?>)
        .map(ResourceSnapshotEntry.decode)
        .toList(growable: false);
    final result = ResourceSnapshot(
      target: raw['target']! as String,
      entries: entries,
      usesMaterialDesign: materialIcons['usesMaterialDesign']! as bool,
      materialIconAstComplete: materialIcons['astComplete']! as bool,
      materialIconReferences: (materialIcons['references']! as List<Object?>)
          .cast<String>(),
    );
    if (result.fingerprint != raw['fingerprint'] ||
        result.encode() != canonicalJson(raw)) {
      throw const FormatException('Resource snapshot is not canonical');
    }
    return result;
  }

  ResourceSnapshotDiff diff(ResourceSnapshot current) {
    final changes = <ResourceSnapshotChange>[];
    if (target != current.target) {
      changes.add(
        ResourceSnapshotChange(
          kind: ResourceInputKind.native,
          packageName: '<snapshot>',
          path: 'target',
          platform: current.target,
          reason: 'target-changed',
        ),
      );
    }
    final before = <String, ResourceSnapshotEntry>{
      for (final entry in entries) entry.key: entry,
    };
    final after = <String, ResourceSnapshotEntry>{
      for (final entry in current.entries) entry.key: entry,
    };
    final keys = <String>{...before.keys, ...after.keys}.toList()..sort();
    for (final key in keys) {
      final oldEntry = before[key];
      final newEntry = after[key];
      if (oldEntry == null) {
        changes.add(_change(newEntry!, 'added'));
      } else if (newEntry == null) {
        changes.add(_change(oldEntry, 'removed'));
      } else if (oldEntry.metadataFingerprint != newEntry.metadataFingerprint) {
        changes.add(_change(newEntry, 'metadata-changed'));
      } else if (oldEntry.sha256 != newEntry.sha256 ||
          oldEntry.size != newEntry.size) {
        changes.add(_change(newEntry, 'bytes-changed'));
      }
    }

    if (usesMaterialDesign != current.usesMaterialDesign) {
      changes.add(
        const ResourceSnapshotChange(
          kind: ResourceInputKind.font,
          packageName: '<flutter>',
          path: '<material-icons>',
          platform: null,
          reason: 'uses-material-design-changed',
        ),
      );
    }
    if (!materialIconAstComplete || !current.materialIconAstComplete) {
      changes.add(
        const ResourceSnapshotChange(
          kind: ResourceInputKind.font,
          packageName: '<flutter>',
          path: '<material-icons>',
          platform: null,
          reason: 'material-icon-ast-incomplete',
        ),
      );
    } else {
      final beforeIcons = materialIconReferences.toSet();
      final addedIcons =
          current.materialIconReferences
              .where((icon) => !beforeIcons.contains(icon))
              .toList()
            ..sort();
      for (final icon in addedIcons) {
        changes.add(
          ResourceSnapshotChange(
            kind: ResourceInputKind.font,
            packageName: '<flutter>',
            path: '<material-icons>/$icon',
            platform: null,
            reason: 'material-icon-reference-added',
          ),
        );
      }
    }
    return ResourceSnapshotDiff(changes);
  }

  static ResourceSnapshotChange _change(
    ResourceSnapshotEntry entry,
    String reason,
  ) => ResourceSnapshotChange(
    kind: entry.kind,
    packageName: entry.packageName,
    path: entry.path,
    platform: entry.platform,
    reason: reason,
  );

  static ResourceSnapshot capture({
    required FlutterProject project,
    required ProjectGraph graph,
    required String target,
  }) {
    if (target != 'android' && target != 'ios') {
      throw ArgumentError.value(target, 'target', 'must be android or ios');
    }
    if (!graph.packageConfigPresent) {
      throw const ResourceSnapshotFailure(
        kind: ResourceInputKind.native,
        path: '.dart_tool/package_config.json',
        detail: 'Resolved package configuration is unavailable.',
      );
    }

    final entries = <ResourceSnapshotEntry>[];
    final packages = graph.packages.toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    var usesMaterialDesign = false;
    var materialIconAstComplete = true;
    final materialIconReferences = <String>{};

    for (final package in packages) {
      final root = package.name == project.packageName
          ? project.root
          : package.root;
      if (root == null) {
        throw ResourceSnapshotFailure(
          kind: ResourceInputKind.native,
          path: 'package:${package.name}',
          detail: 'Resolved package root is unavailable.',
        );
      }
      _requireDirectoryRoot(root, ResourceInputKind.native, package.name);
      final pubspec = package.name == project.packageName
          ? project.pubspec
          : _readPackagePubspec(root, package.name);
      final flutter = pubspec['flutter'];
      if (flutter == null) {
        _collectNativeEntries(
          entries,
          packageName: package.name,
          root: root,
          target: target,
        );
        _collectMaterialIcons(
          package: package,
          root: root,
          materialIconReferences: materialIconReferences,
          onIncomplete: () => materialIconAstComplete = false,
        );
        continue;
      }
      if (flutter is! Map<String, Object?>) {
        throw ResourceSnapshotFailure(
          kind: ResourceInputKind.asset,
          path: 'package:${package.name}/pubspec.yaml',
          detail: 'The flutter section is not a mapping.',
        );
      }
      usesMaterialDesign =
          usesMaterialDesign || flutter['uses-material-design'] == true;
      _collectDeclaredEntries(
        entries,
        packageName: package.name,
        root: root,
        kind: ResourceInputKind.asset,
        declarations: flutter['assets'],
        graph: graph,
        projectPackageName: project.packageName,
        target: target,
      );
      _collectFontEntries(
        entries,
        packageName: package.name,
        root: root,
        declarations: flutter['fonts'],
        graph: graph,
        projectPackageName: project.packageName,
        target: target,
      );
      _collectNativeEntries(
        entries,
        packageName: package.name,
        root: root,
        target: target,
      );
      _collectMaterialIcons(
        package: package,
        root: root,
        materialIconReferences: materialIconReferences,
        onIncomplete: () => materialIconAstComplete = false,
      );
    }
    if (entries.length > _maxResourceEntries) {
      throw const ResourceSnapshotFailure(
        kind: ResourceInputKind.native,
        path: '<resource snapshot>',
        detail: 'Packaged resource traversal exceeded the safety limit.',
      );
    }
    final uniqueEntries = <String, ResourceSnapshotEntry>{};
    for (final entry in entries) {
      final previous = uniqueEntries[entry.key];
      if (previous != null &&
          (previous.size != entry.size ||
              previous.sha256 != entry.sha256 ||
              previous.metadataFingerprint != entry.metadataFingerprint)) {
        throw ResourceSnapshotFailure(
          kind: entry.kind,
          path: 'package:${entry.packageName}/${entry.path}',
          detail:
              'Resource was observed with conflicting contents or metadata.',
        );
      }
      uniqueEntries[entry.key] = entry;
    }
    return ResourceSnapshot(
      target: target,
      entries: uniqueEntries.values,
      usesMaterialDesign: usesMaterialDesign,
      materialIconAstComplete: materialIconAstComplete,
      materialIconReferences: materialIconReferences,
    );
  }
}

void _collectDeclaredEntries(
  List<ResourceSnapshotEntry> entries, {
  required String packageName,
  required Directory root,
  required ResourceInputKind kind,
  required Object? declarations,
  required ProjectGraph graph,
  required String projectPackageName,
  required String target,
}) {
  if (declarations == null) return;
  if (declarations is! List<Object?>) {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:$packageName/pubspec.yaml',
      detail: '${kind.name} declarations must be a list.',
    );
  }
  for (final declaration in declarations) {
    final resolved = _resolveDeclaredResource(
      declaration,
      packageName: packageName,
      root: root,
      kind: kind,
      graph: graph,
      projectPackageName: projectPackageName,
      target: target,
    );
    if (resolved == null) continue;
    _collectResolvedDeclaration(
      entries,
      resolved: resolved,
      kind: kind,
      allowResolutionVariants: kind == ResourceInputKind.asset,
    );
  }
}

const _flutterAssetMapKeys = <String>{
  'path',
  'flavors',
  'platforms',
  'transformers',
};
const _flutterAssetPlatforms = <String>{
  'android',
  'ios',
  'web',
  'linux',
  'macos',
  'windows',
};
final _resolutionVariantDirectory = RegExp(r'^\d+(\.\d*)?x$');

_ResolvedResource? _resolveDeclaredResource(
  Object? declaration, {
  required String packageName,
  required Directory root,
  required ResourceInputKind kind,
  required ProjectGraph graph,
  required String projectPackageName,
  required String target,
}) {
  late final String declaredPath;
  var isMap = false;
  var hasFlavors = false;
  var hasPlatforms = false;
  var hasTransformers = false;
  var flavors = const <String>[];
  var platforms = const <String>[];

  if (declaration is String) {
    declaredPath = declaration;
  } else if (declaration is Map<String, Object?>) {
    isMap = true;
    if (declaration.keys.any((key) => !_flutterAssetMapKeys.contains(key))) {
      throw ResourceSnapshotFailure(
        kind: kind,
        path: 'package:$packageName/pubspec.yaml',
        detail: 'Asset declaration contains unsupported map metadata.',
      );
    }
    final path = declaration['path'];
    if (path is! String) {
      throw ResourceSnapshotFailure(
        kind: kind,
        path: 'package:$packageName/pubspec.yaml',
        detail: 'Asset declaration map must contain a path string.',
      );
    }
    declaredPath = path;
    hasFlavors = declaration.containsKey('flavors');
    hasPlatforms = declaration.containsKey('platforms');
    hasTransformers = declaration.containsKey('transformers');
    flavors = _assetMapStrings(
      declaration,
      key: 'flavors',
      packageName: packageName,
    );
    platforms = _assetMapStrings(
      declaration,
      key: 'platforms',
      packageName: packageName,
    );
    if (platforms.any(
      (platform) => !_flutterAssetPlatforms.contains(platform),
    )) {
      throw ResourceSnapshotFailure(
        kind: kind,
        path: 'package:$packageName/pubspec.yaml',
        detail: 'Asset declaration contains an unsupported platform.',
      );
    }
    if (hasTransformers) {
      final transformers = declaration['transformers'];
      if (transformers is! List<Object?> || transformers.isNotEmpty) {
        throw ResourceSnapshotFailure(
          kind: kind,
          path: 'package:$packageName/pubspec.yaml',
          detail: 'Asset transformers are unsupported for snapshot capture.',
        );
      }
    }
  } else {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:$packageName/pubspec.yaml',
      detail:
          '${kind.name} declaration must be a string path or supported map.',
    );
  }

  final normalized = _normalizeDeclaredPath(declaredPath, kind, packageName);
  if (platforms.isNotEmpty && !platforms.contains(target)) return null;
  final resolved = _resolveDeclaredPath(
    normalized,
    packageName: packageName,
    root: root,
    kind: kind,
    graph: graph,
    projectPackageName: projectPackageName,
  );
  if (!isMap) return resolved;
  final metadata = <String, Object?>{
    'path': normalized,
    if (hasFlavors) 'flavors': flavors,
    if (hasPlatforms) 'platforms': platforms,
    if (hasTransformers) 'transformers': const <Object?>[],
    'logicalPath': normalized,
    'physicalPackage': resolved.packageName,
    'physicalPath': resolved.relative,
  };
  return resolved.withMetadata(digestJson(metadata));
}

List<String> _assetMapStrings(
  Map<String, Object?> declaration, {
  required String key,
  required String packageName,
}) {
  if (!declaration.containsKey(key)) return const <String>[];
  final value = declaration[key];
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw ResourceSnapshotFailure(
      kind: ResourceInputKind.asset,
      path: 'package:$packageName/pubspec.yaml',
      detail: 'Asset declaration map metadata must be a string list.',
    );
  }
  final values = value.cast<String>().toSet().toList()..sort();
  if (values.any((item) => item.isEmpty)) {
    throw ResourceSnapshotFailure(
      kind: ResourceInputKind.asset,
      path: 'package:$packageName/pubspec.yaml',
      detail: 'Asset declaration map metadata contains an empty value.',
    );
  }
  return List.unmodifiable(values);
}

_ResolvedResource _resolveDeclaredPath(
  String normalized, {
  required String packageName,
  required Directory root,
  required ResourceInputKind kind,
  required ProjectGraph graph,
  required String projectPackageName,
}) {
  final localPath = _safeJoin(root, normalized, kind, packageName);
  final localType = FileSystemEntity.typeSync(localPath, followLinks: false);
  final segments = normalized.split('/');
  if (localType != FileSystemEntityType.notFound ||
      segments.first != 'packages' ||
      packageName != projectPackageName) {
    return _ResolvedResource(
      packageName: packageName,
      root: root,
      relative: normalized,
      logicalPath: normalized,
    );
  }
  if (segments.length < 3 ||
      !RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(segments[1])) {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:$packageName/pubspec.yaml',
      detail: 'Package asset path is not a supported logical package path.',
    );
  }
  final targetPackage = graph.byName(segments[1]);
  if (targetPackage == null || targetPackage.root == null) {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:$packageName/pubspec.yaml',
      detail:
          'Logical package asset is unavailable from package configuration.',
    );
  }
  final packageUri = _normalizePackageUri(
    targetPackage.packageUri,
    kind: kind,
    packageName: packageName,
  );
  final packageRelative = _validateRelativeSnapshotPath(
    '$packageUri/${segments.sublist(2).join('/')}',
  );
  return _ResolvedResource(
    packageName: targetPackage.name,
    root: targetPackage.root!,
    relative: packageRelative,
    logicalPath: normalized,
  );
}

void _collectResolvedDeclaration(
  List<ResourceSnapshotEntry> entries, {
  required _ResolvedResource resolved,
  required ResourceInputKind kind,
  required bool allowResolutionVariants,
}) {
  final path = resolved.path;
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type == FileSystemEntityType.file) {
    _addFile(
      entries,
      file: File(path),
      kind: kind,
      packageName: resolved.packageName,
      relative: resolved.relative,
      metadataFingerprint: resolved.metadataFingerprint,
    );
    if (allowResolutionVariants) {
      for (final variant in _resolutionVariants(resolved, kind)) {
        _addFile(
          entries,
          file: variant.file,
          kind: kind,
          packageName: resolved.packageName,
          relative: variant.relative,
          metadataFingerprint: resolved.metadataFingerprint,
        );
      }
    }
    return;
  }
  if (type == FileSystemEntityType.directory) {
    _addTree(
      entries,
      root: Directory(path),
      kind: kind,
      packageName: resolved.packageName,
      prefix: resolved.relative,
      rejectSymlinks: true,
      metadataFingerprint: resolved.metadataFingerprint,
    );
    return;
  }
  if (type == FileSystemEntityType.link) {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:${resolved.packageName}/${resolved.relative}',
      detail: 'Declared resource path is a symlink.',
    );
  }
  if (allowResolutionVariants) {
    final variants = _resolutionVariants(resolved, kind);
    if (variants.isNotEmpty) {
      for (final variant in variants) {
        _addFile(
          entries,
          file: variant.file,
          kind: kind,
          packageName: resolved.packageName,
          relative: variant.relative,
          metadataFingerprint: resolved.metadataFingerprint,
        );
      }
      return;
    }
  }
  throw ResourceSnapshotFailure(
    kind: kind,
    path: 'package:${resolved.packageName}/${resolved.relative}',
    detail: 'Declared resource path does not exist.',
  );
}

List<_ScannedFile> _resolutionVariants(
  _ResolvedResource resolved,
  ResourceInputKind kind,
) {
  final parent = p.posix.dirname(resolved.relative);
  final basename = p.posix.basename(resolved.relative);
  final parentPath = parent == '.'
      ? resolved.root.path
      : _safeJoin(resolved.root, parent, kind, resolved.packageName);
  if (FileSystemEntity.typeSync(parentPath, followLinks: false) !=
      FileSystemEntityType.directory) {
    return const <_ScannedFile>[];
  }
  late final List<FileSystemEntity> children;
  try {
    children = Directory(parentPath).listSync(followLinks: false).toList()
      ..sort((left, right) => left.path.compareTo(right.path));
  } on Object {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:${resolved.packageName}/$parent',
      detail: 'Unable to enumerate the package resource directory.',
    );
  }
  final variants = <_ScannedFile>[];
  for (final child in children) {
    final scale = p.basename(child.path);
    if (!_resolutionVariantDirectory.hasMatch(scale)) continue;
    final childType = FileSystemEntity.typeSync(child.path, followLinks: false);
    if (childType == FileSystemEntityType.link) {
      throw ResourceSnapshotFailure(
        kind: kind,
        path: 'package:${resolved.packageName}/${_joinRelative(parent, scale)}',
        detail: 'Resolution variant directory is a symlink.',
      );
    }
    if (childType != FileSystemEntityType.directory) continue;
    final relative = _joinRelative(_joinRelative(parent, scale), basename);
    final path = _safeJoin(resolved.root, relative, kind, resolved.packageName);
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.file) {
      variants.add(_ScannedFile(file: File(path), relative: relative));
    }
  }
  variants.sort((left, right) => left.relative.compareTo(right.relative));
  return variants;
}

String _joinRelative(String parent, String child) {
  if (parent == '.') return child;
  return '$parent/$child';
}

final class _ResolvedResource {
  const _ResolvedResource({
    required this.packageName,
    required this.root,
    required this.relative,
    required this.logicalPath,
    this.metadataFingerprint,
  });

  final String packageName;
  final Directory root;
  final String relative;
  final String logicalPath;
  final String? metadataFingerprint;

  String get path => p.join(root.path, relative);

  _ResolvedResource withMetadata(String fingerprint) => _ResolvedResource(
    packageName: packageName,
    root: root,
    relative: relative,
    logicalPath: logicalPath,
    metadataFingerprint: fingerprint,
  );
}

void _collectFontEntries(
  List<ResourceSnapshotEntry> entries, {
  required String packageName,
  required Directory root,
  required Object? declarations,
  required ProjectGraph graph,
  required String projectPackageName,
  required String target,
}) {
  if (declarations == null) return;
  if (declarations is! List<Object?>) {
    throw ResourceSnapshotFailure(
      kind: ResourceInputKind.font,
      path: 'package:$packageName/pubspec.yaml',
      detail: 'font declarations must be a list.',
    );
  }
  for (final family in declarations) {
    if (family is! Map<String, Object?> || family['fonts'] is! List<Object?>) {
      throw ResourceSnapshotFailure(
        kind: ResourceInputKind.font,
        path: 'package:$packageName/pubspec.yaml',
        detail: 'font family must contain a fonts list.',
      );
    }
    for (final font in family['fonts']! as List<Object?>) {
      if (font is! Map<String, Object?> || font['asset'] is! String) {
        throw ResourceSnapshotFailure(
          kind: ResourceInputKind.font,
          path: 'package:$packageName/pubspec.yaml',
          detail: 'font entry must contain an asset path.',
        );
      }
      _collectDeclaredEntries(
        entries,
        packageName: packageName,
        root: root,
        kind: ResourceInputKind.font,
        declarations: <Object?>[font['asset']],
        graph: graph,
        projectPackageName: projectPackageName,
        target: target,
      );
    }
  }
}

void _collectNativeEntries(
  List<ResourceSnapshotEntry> entries, {
  required String packageName,
  required Directory root,
  required String target,
}) {
  final platformRoot = Directory(p.join(root.path, target));
  if (FileSystemEntity.typeSync(platformRoot.path, followLinks: false) ==
      FileSystemEntityType.notFound) {
    return;
  }
  if (FileSystemEntity.typeSync(platformRoot.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw ResourceSnapshotFailure(
      kind: ResourceInputKind.native,
      path: 'package:$packageName/$target',
      detail: 'Native platform root is not a directory.',
    );
  }
  _addTree(
    entries,
    root: platformRoot,
    kind: ResourceInputKind.native,
    packageName: packageName,
    prefix: target,
    rejectSymlinks: true,
    include: (relative) =>
        !_isVolatileResourcePath(relative) && !isNativeBuildInputPath(relative),
    platform: target,
  );
}

void _collectMaterialIcons({
  required ProjectPackage package,
  required Directory root,
  required Set<String> materialIconReferences,
  required void Function() onIncomplete,
}) {
  final packageUri = _normalizePackageUri(package.packageUri);
  final lib = Directory(
    _safeJoin(root, packageUri, ResourceInputKind.font, package.name),
  );
  final type = FileSystemEntity.typeSync(lib.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type != FileSystemEntityType.directory) {
    onIncomplete();
    return;
  }
  final files = <_ScannedFile>[];
  _scanTree(
    root: lib,
    prefix: packageUri,
    kind: ResourceInputKind.font,
    packageName: package.name,
    files: files,
    rejectSymlinks: true,
  );
  for (final scanned in files.where(
    (item) => p.extension(item.file.path).toLowerCase() == '.dart',
  )) {
    final source = _readText(scanned.file, package.name, scanned.relative);
    try {
      final parsed = parseString(
        content: source,
        path: scanned.file.path,
        throwIfDiagnostics: false,
      );
      if (parsed.errors.isNotEmpty) {
        onIncomplete();
        continue;
      }
      final visitor = _MaterialIconVisitor();
      parsed.unit.accept(visitor);
      if (!visitor.complete) onIncomplete();
      for (final reference in visitor.references) {
        materialIconReferences.add(
          'package:${package.name}/${scanned.relative}:$reference',
        );
      }
    } on Object {
      onIncomplete();
    }
  }
}

final class _MaterialIconVisitor extends RecursiveAstVisitor<void> {
  final references = <String>{};
  final _knownIconsOffsets = <int>{};
  bool complete = true;

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final prefix = node.prefix.name;
    if (prefix == 'Icons') {
      references.add('Icons.${node.identifier.name}');
      _knownIconsOffsets.add(node.prefix.offset);
    } else if (node.identifier.name == 'Icons') {
      complete = false;
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (target is SimpleIdentifier && target.name == 'Icons') {
      references.add('Icons.${node.propertyName.name}');
      _knownIconsOffsets.add(target.offset);
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'Icons' && !_knownIconsOffsets.contains(node.offset)) {
      complete = false;
    }
    super.visitSimpleIdentifier(node);
  }
}

void _addTree(
  List<ResourceSnapshotEntry> entries, {
  required Directory root,
  required ResourceInputKind kind,
  required String packageName,
  required String prefix,
  required bool rejectSymlinks,
  bool Function(String relative)? include,
  String? platform,
  String? metadataFingerprint,
}) {
  final files = <_ScannedFile>[];
  _scanTree(
    root: root,
    prefix: prefix,
    kind: kind,
    packageName: packageName,
    files: files,
    rejectSymlinks: rejectSymlinks,
    include: include,
  );
  for (final scanned in files) {
    _addFile(
      entries,
      file: scanned.file,
      kind: kind,
      packageName: packageName,
      relative: scanned.relative,
      platform: platform,
      metadataFingerprint: metadataFingerprint,
    );
  }
}

void _scanTree({
  required Directory root,
  required String prefix,
  required ResourceInputKind kind,
  required String packageName,
  required List<_ScannedFile> files,
  required bool rejectSymlinks,
  bool Function(String relative)? include,
}) {
  void visit(Directory directory, String relativeDirectory) {
    List<FileSystemEntity> children;
    try {
      children = directory.listSync(followLinks: false).toList()
        ..sort((left, right) => left.path.compareTo(right.path));
    } on Object {
      throw ResourceSnapshotFailure(
        kind: kind,
        path: 'package:$packageName/$relativeDirectory',
        detail: 'Unable to enumerate the package resource directory.',
      );
    }
    for (final child in children) {
      final name = p.basename(child.path);
      final relative = relativeDirectory.isEmpty
          ? name
          : '$relativeDirectory/$name';
      final type = FileSystemEntity.typeSync(child.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        if (rejectSymlinks) {
          throw ResourceSnapshotFailure(
            kind: kind,
            path: 'package:$packageName/$relative',
            detail: 'Resource traversal encountered a symlink.',
          );
        }
        continue;
      }
      if (type == FileSystemEntityType.directory) {
        if (include != null &&
            _isVolatileResourcePath(relative) &&
            kind == ResourceInputKind.native) {
          continue;
        }
        visit(Directory(child.path), relative);
      } else if (type == FileSystemEntityType.file &&
          (include == null || include(relative))) {
        files.add(_ScannedFile(file: File(child.path), relative: relative));
      } else if (type == FileSystemEntityType.notFound) {
        throw ResourceSnapshotFailure(
          kind: kind,
          path: 'package:$packageName/$relative',
          detail: 'Resource disappeared during traversal.',
        );
      }
      if (files.length > _maxResourceEntries) {
        throw ResourceSnapshotFailure(
          kind: kind,
          path: 'package:$packageName/$prefix',
          detail: 'Resource traversal exceeded the safety limit.',
        );
      }
    }
  }

  visit(root, prefix);
  files.sort((left, right) => left.relative.compareTo(right.relative));
}

void _addFile(
  List<ResourceSnapshotEntry> entries, {
  required File file,
  required ResourceInputKind kind,
  required String packageName,
  required String relative,
  String? platform,
  String? metadataFingerprint,
}) {
  final type = FileSystemEntity.typeSync(file.path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:$packageName/$relative',
      detail: 'Resource path is a symlink.',
    );
  }
  if (type != FileSystemEntityType.file) {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:$packageName/$relative',
      detail: 'Resource file is unavailable.',
    );
  }
  late final int size;
  late final String digest;
  try {
    size = file.lengthSync();
    if (size > _maxResourceFileBytes) {
      throw ResourceSnapshotFailure(
        kind: kind,
        path: 'package:$packageName/$relative',
        detail: 'Resource file exceeds the safety limit.',
      );
    }
    digest = sha256Hex(file.readAsBytesSync());
  } on ResourceSnapshotFailure {
    rethrow;
  } on Object {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:$packageName/$relative',
      detail: 'Unable to read the resource file.',
    );
  }
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:$packageName/$relative',
      detail: 'Resource file changed while it was being read.',
    );
  }
  if (entries.length >= _maxResourceEntries) {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: '<resource snapshot>',
      detail: 'Packaged resource traversal exceeded the safety limit.',
    );
  }
  entries.add(
    ResourceSnapshotEntry(
      kind: kind,
      packageName: packageName,
      path: _validateRelativeSnapshotPath(relative),
      platform: platform,
      size: size,
      sha256: digest,
      metadataFingerprint: metadataFingerprint,
    ),
  );
}

String _readText(File file, String packageName, String relative) {
  try {
    return file.readAsStringSync();
  } on Object {
    throw ResourceSnapshotFailure(
      kind: ResourceInputKind.font,
      path: 'package:$packageName/$relative',
      detail: 'Unable to read Dart source for icon evidence.',
    );
  }
}

void _requireDirectoryRoot(
  Directory root,
  ResourceInputKind kind,
  String packageName,
) {
  final type = FileSystemEntity.typeSync(root.path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:$packageName',
      detail: 'Package root is a symlink.',
    );
  }
  if (type != FileSystemEntityType.directory) {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:$packageName',
      detail: 'Package root is unavailable.',
    );
  }
}

String _safeJoin(
  Directory root,
  String relative,
  ResourceInputKind kind,
  String packageName,
) {
  final normalized = _validateRelativeSnapshotPath(relative);
  var current = root.path;
  for (final segment in normalized.split('/')) {
    current = p.join(current, segment);
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw ResourceSnapshotFailure(
        kind: kind,
        path: 'package:$packageName/$normalized',
        detail: 'Resource path traverses a symlink.',
      );
    }
  }
  return current;
}

String _normalizeDeclaredPath(
  String value,
  ResourceInputKind kind,
  String packageName,
) {
  final normalized = value.trim().replaceAll(r'\', '/');
  if (normalized.isEmpty ||
      normalized.contains(RegExp(r'[\u0000\r\n]')) ||
      normalized.startsWith('/') ||
      normalized.startsWith('//') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(normalized) ||
      normalized.split('/').any((segment) => segment == '..') ||
      normalized.contains(RegExp(r'[\*\?\[\]]'))) {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:$packageName/pubspec.yaml',
      detail: 'Declared resource path is unsafe or unsupported.',
    );
  }
  try {
    return _validateRelativeSnapshotPath(p.posix.normalize(normalized));
  } on FormatException {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: 'package:$packageName/pubspec.yaml',
      detail: 'Declared resource path is unsafe or unsupported.',
    );
  }
}

String _normalizePackageUri(
  String value, {
  ResourceInputKind kind = ResourceInputKind.font,
  String packageName = '<package config>',
}) {
  final normalized = value.trim().replaceAll(r'\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      normalized.startsWith('//') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(normalized) ||
      normalized.split('/').any((segment) => segment == '..')) {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: packageName == '<package config>'
          ? '<package config>'
          : 'package:$packageName/pubspec.yaml',
      detail: 'Package URI escapes its package root.',
    );
  }
  try {
    return _validateRelativeSnapshotPath(p.posix.normalize(normalized));
  } on FormatException {
    throw ResourceSnapshotFailure(
      kind: kind,
      path: packageName == '<package config>'
          ? '<package config>'
          : 'package:$packageName/pubspec.yaml',
      detail: 'Package URI is invalid.',
    );
  }
}

String _validateRelativeSnapshotPath(String value) {
  final normalized = value.replaceAll(r'\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      normalized.startsWith('//') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(normalized) ||
      normalized
          .split('/')
          .any((segment) => segment.isEmpty || segment == '..') ||
      p.posix.normalize(normalized) != normalized ||
      normalized == '.' ||
      normalized.startsWith('../')) {
    throw const FormatException('Resource path is not project-relative');
  }
  return normalized;
}

bool _isVolatileResourcePath(String relative) {
  final segments = relative
      .replaceAll(r'\', '/')
      .split('/')
      .map((segment) => segment.toLowerCase());
  const volatile = <String>{
    '.cxx',
    '.dart_tool',
    '.git',
    '.gradle',
    '.symlinks',
    'build',
    'deriveddata',
    'ephemeral',
    'pods',
    'xcuserdata',
  };
  return segments.any(volatile.contains);
}

bool isNativeBuildInputPath(String relative) {
  final lower = relative.toLowerCase();
  final basename = p.basename(lower);
  return lower.endsWith('androidmanifest.xml') ||
      lower.endsWith('podfile.lock') ||
      basename == 'podfile' ||
      lower.endsWith('.plist') ||
      lower.endsWith('.pbxproj') ||
      lower.endsWith('.entitlements') ||
      lower.endsWith('.xcconfig') ||
      lower.endsWith('.gradle') ||
      lower.endsWith('.gradle.kts') ||
      lower.endsWith('gradle.properties') ||
      lower.endsWith('settings.gradle') ||
      lower.endsWith('settings.gradle.kts') ||
      lower.endsWith('.podfile') ||
      lower.endsWith('.podspec') ||
      lower.endsWith('.kt') ||
      lower.endsWith('.swift') ||
      lower.endsWith('.java') ||
      lower.endsWith('.mm') ||
      lower.endsWith('.m') ||
      lower.endsWith('.h') ||
      lower.endsWith('.cpp') ||
      lower.endsWith('.c');
}

Map<String, Object?> _readPackagePubspec(Directory root, String packageName) {
  final file = File(p.join(root.path, 'pubspec.yaml'));
  if (!file.existsSync()) {
    throw ResourceSnapshotFailure(
      kind: ResourceInputKind.asset,
      path: 'package:$packageName/pubspec.yaml',
      detail: 'Package pubspec is unavailable.',
    );
  }
  try {
    final raw = loadYaml(file.readAsStringSync());
    if (raw is! YamlMap) {
      throw const FormatException('Package pubspec is not a mapping');
    }
    return _yamlValue(raw) as Map<String, Object?>;
  } on ResourceSnapshotFailure {
    rethrow;
  } on Object {
    throw ResourceSnapshotFailure(
      kind: ResourceInputKind.asset,
      path: 'package:$packageName/pubspec.yaml',
      detail: 'Unable to read or parse the package pubspec.',
    );
  }
}

Object? _yamlValue(Object? value) {
  if (value is YamlMap) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key! as String: _yamlValue(entry.value),
    };
  }
  if (value is YamlList) {
    return value.map(_yamlValue).toList(growable: false);
  }
  return value;
}

final class _ScannedFile {
  const _ScannedFile({required this.file, required this.relative});

  final File file;
  final String relative;
}
