import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'canonical.dart';
import 'configuration.dart';
import 'diagnostics.dart';

/// The workspace shape found around a Flutter application.
enum WorkspaceType {
  singleApp,
  melos,
  pubWorkspace,
  melosAndPubWorkspace,
  repository,
}

/// How much evidence supports an automatic selection.
enum DiscoveryConfidence { exact, highConfidence, ambiguous, unresolved }

/// The package kind used when filtering workspace candidates.
enum FlutterPackageKind { application, plugin, package, dartPackage }

final class FlutterEntrypointCandidate {
  const FlutterEntrypointCandidate({
    required this.path,
    this.flavor,
    required this.score,
  });

  final String path;
  final String? flavor;
  final int score;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'flavor': flavor,
    'score': score,
  };
}

final class FlutterProjectCandidate {
  const FlutterProjectCandidate({
    required this.root,
    required this.relativePath,
    required this.packageName,
    required this.kind,
    required this.entrypoints,
    required this.androidApplicationId,
    required this.iosApplicationId,
    required this.androidFlavors,
    required this.iosFlavors,
    required this.androidApplicationIds,
    required this.iosApplicationIds,
    required this.platformEntrypoints,
    this.isExample = false,
    this.toolchainHint,
  });

  final Directory root;
  final String relativePath;
  final String packageName;
  final FlutterPackageKind kind;
  final List<FlutterEntrypointCandidate> entrypoints;
  final String? androidApplicationId;
  final String? iosApplicationId;
  final List<String> androidFlavors;
  final List<String> iosFlavors;
  final Map<String, String> androidApplicationIds;
  final Map<String, String> iosApplicationIds;
  final Map<String, Map<String, String>> platformEntrypoints;
  final bool isExample;
  final String? toolchainHint;

  String? get applicationId => androidApplicationId ?? iosApplicationId;

  List<String> get flavors =>
      <String>{...androidFlavors, ...iosFlavors}.toList()..sort();

  Map<String, Object?> toJson() => <String, Object?>{
    'path': relativePath,
    'package': packageName,
    'kind': kind.name,
    'example': isExample,
    'entrypoints': entrypoints.map((item) => item.toJson()).toList(),
    'android': <String, Object?>{
      'applicationId': androidApplicationId,
      'applicationIds': androidApplicationIds,
      'flavors': androidFlavors,
    },
    'ios': <String, Object?>{
      'bundleIdentifier': iosApplicationId,
      'applicationIds': iosApplicationIds,
      'flavors': iosFlavors,
    },
    'toolchainHint': toolchainHint,
  };
}

/// A non-throwing inspection result used by doctor and init before selection.
final class ProjectDiscoveryReport {
  const ProjectDiscoveryReport({
    required this.repositoryRoot,
    required this.workspaceRoot,
    required this.workspaceType,
    required this.candidates,
    this.selected,
    this.issueCode,
    this.issueSummary,
    this.issueDetail,
    this.issueAction,
  });

  final Directory repositoryRoot;
  final Directory workspaceRoot;
  final WorkspaceType workspaceType;
  final List<FlutterProjectCandidate> candidates;
  final FlutterProjectCandidate? selected;
  final String? issueCode;
  final String? issueSummary;
  final String? issueDetail;
  final String? issueAction;

  bool get isResolved => selected != null;
  bool get isAmbiguous => issueCode == 'T1302' || issueCode == 'T1304';

  Map<String, Object?> toJson() => <String, Object?>{
    'repositoryRoot': '<repository>',
    'workspaceRoot': '<workspace>',
    'workspaceType': workspaceType.name,
    'candidates': candidates.map((item) => item.toJson()).toList(),
    'selected': selected?.toJson(),
    'issue': issueCode == null
        ? null
        : <String, Object?>{
            'code': issueCode,
            'summary': issueSummary,
            'detail': _safeDiscoveryDetail(issueDetail),
            'action': issueAction,
          },
  };

  ToolFailure toFailure() => ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: issueCode ?? 'T1301',
    summary: issueSummary ?? 'No Flutter application was found',
    detail: issueDetail ?? workspaceRoot.path,
    action:
        issueAction ??
        'Run from a Flutter application or pass --project <directory>.',
  );
}

/// The target-specific selection consumed by release and patch.
final class FlutterTargetSelection {
  const FlutterTargetSelection({
    required this.target,
    required this.entrypointPath,
    this.flavor,
    required this.confidence,
    required this.reason,
  });

  final String target;
  final String entrypointPath;
  final String? flavor;
  final DiscoveryConfidence confidence;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'target': target,
    'entrypoint': entrypointPath,
    'flavor': flavor,
    'confidence': confidence.name,
    'reason': reason,
  };
}

final class FlutterProject {
  FlutterProject({
    required this.root,
    required this.repositoryRoot,
    required this.workspaceRoot,
    required this.workspaceType,
    required this.candidateApplications,
    required this.packageName,
    required this.version,
    required this.pubspec,
    required this.pubspecFile,
    required this.pubspecLockFile,
    required this.packageConfigFile,
    required this.applicationId,
    required this.androidApplicationId,
    required this.iosApplicationId,
    required this.entrypointCandidates,
    required this.androidFlavors,
    required this.iosFlavors,
    required this.androidApplicationIds,
    required this.iosApplicationIds,
    required this.platformEntrypoints,
    this.toolchainHint,
  });

  final Directory root;
  final Directory repositoryRoot;
  final Directory workspaceRoot;
  final WorkspaceType workspaceType;
  final List<FlutterProjectCandidate> candidateApplications;
  final String packageName;
  final String? version;
  final Map<String, Object?> pubspec;
  final File pubspecFile;
  final File pubspecLockFile;
  final File? packageConfigFile;
  final String applicationId;
  final String? androidApplicationId;
  final String? iosApplicationId;
  final List<FlutterEntrypointCandidate> entrypointCandidates;
  final List<String> androidFlavors;
  final List<String> iosFlavors;
  final Map<String, String> androidApplicationIds;
  final Map<String, String> iosApplicationIds;
  final Map<String, Map<String, String>> platformEntrypoints;
  final String? toolchainHint;

  Directory get libDirectory => Directory(p.join(root.path, 'lib'));

  /// The legacy default remains available to callers that only need a path.
  File get mainFile => File(p.join(libDirectory.path, 'main.dart'));

  Directory get toolDirectory => Directory(p.join(root.path, '.tool'));
  File get configFile => File(p.join(root.path, 'tool.yaml'));

  /// Safe project-to-profile binding written by `hyfens init`.
  File get hyfensConfigFile => File(p.join(root.path, 'hyfens.yaml'));

  /// A workspace-level binding can select this app when invoked from the
  /// workspace root. It is only consulted when the app-local binding is
  /// absent, so existing projects keep their established layout.
  File get workspaceHyfensConfigFile =>
      File(p.join(workspaceRoot.path, 'hyfens.yaml'));

  String get relativeProjectPath {
    if (p.normalize(root.path) == p.normalize(workspaceRoot.path)) return '.';
    return p
        .relative(root.path, from: workspaceRoot.path)
        .replaceAll(r'\', '/');
  }

  String relative(FileSystemEntity entity) => relativePath(root, entity);

  List<String> get flavors =>
      <String>{...androidFlavors, ...iosFlavors}.toList()..sort();

  /// Native flavors are kept separate from filename-derived entrypoint
  /// labels. A custom Dart target does not imply that Flutter should receive a
  /// native `--flavor` argument.
  List<String> flavorsFor(String target) => target == 'ios'
      ? List.unmodifiable(iosFlavors)
      : List.unmodifiable(androidFlavors);

  String applicationIdFor(String target, {String? flavor}) {
    final values = target == 'ios' ? iosApplicationIds : androidApplicationIds;
    if (flavor != null && values[flavor] != null) return values[flavor]!;
    if (target == 'android' && androidApplicationId != null) {
      return androidApplicationId!;
    }
    if (target == 'ios' && iosApplicationId != null) return iosApplicationId!;
    return applicationId;
  }

  List<FlutterEntrypointCandidate> entrypointsForFlavor(
    String target,
    String flavor,
  ) {
    final configured = platformEntrypoints[target]?[flavor];
    final candidates = entrypointCandidates
        .where((item) => item.flavor?.toLowerCase() == flavor.toLowerCase())
        .toList(growable: false);
    final result = <FlutterEntrypointCandidate>[];
    if (configured != null) {
      result.add(
        FlutterEntrypointCandidate(
          path: configured,
          flavor: flavor,
          score: 110,
        ),
      );
    }
    result.addAll(candidates);
    return result;
  }

  FlutterTargetSelection resolveTarget({
    required String target,
    String? flavor,
    String? entrypointPath,
    String? persistedFlavor,
    String? persistedEntrypoint,
    HyfensTargetBinding? persistedTarget,
    Map<String, String>? configuredEntrypoints,
  }) {
    if (target != 'android' && target != 'ios') {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'T1006',
        summary: 'Unsupported release target',
        detail: target,
        action: 'Use android or ios.',
      );
    }
    final targetFlavors = flavorsFor(target);
    final requestedFlavor =
        flavor ?? persistedTarget?.flavor ?? persistedFlavor;
    final normalizedFlavor = requestedFlavor == null
        ? null
        : _validatedFlavor(requestedFlavor);
    final configured = configuredEntrypoints ?? const <String, String>{};
    final configuredPath = normalizedFlavor == null
        ? configured['default']
        : configured[normalizedFlavor];
    var selectedPath =
        entrypointPath ??
        persistedTarget?.entrypointPath ??
        persistedEntrypoint ??
        configuredPath;
    var selectedFlavor = normalizedFlavor;
    final hasPersistedSelection =
        persistedTarget != null ||
        persistedFlavor != null ||
        persistedEntrypoint != null;
    var confidence = flavor != null || entrypointPath != null
        ? DiscoveryConfidence.exact
        : DiscoveryConfidence.highConfidence;
    var reason = flavor != null || entrypointPath != null
        ? 'explicit override'
        : hasPersistedSelection
        ? 'persisted hyfens.yaml selection'
        : 'project configuration';

    if (selectedFlavor != null &&
        targetFlavors.isNotEmpty &&
        !targetFlavors.contains(selectedFlavor)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1307',
        summary: 'Selected flavor is not defined for the target',
        detail: '$target/$selectedFlavor; found ${targetFlavors.join(', ')}',
        action:
            'Choose a flavor defined by the target or run hyfens init again.',
      );
    }

    if (selectedFlavor == null && targetFlavors.length > 1) {
      final pathMatch = selectedPath == null
          ? null
          : entrypointCandidates.where((item) => item.path == selectedPath);
      final inferred = pathMatch == null || pathMatch.isEmpty
          ? null
          : pathMatch.first.flavor;
      if (inferred != null && targetFlavors.contains(inferred)) {
        selectedFlavor = inferred;
        confidence = DiscoveryConfidence.highConfidence;
        reason = 'entrypoint matches native flavor';
      } else {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1304',
          summary: 'Multiple Flutter flavors require a selection',
          detail: targetFlavors.join(', '),
          action: 'Run hyfens init to choose one, or pass --flavor <name> for this command.',
        );
      }
    }

    if (selectedFlavor == null && targetFlavors.length == 1) {
      selectedFlavor = targetFlavors.single;
      reason = 'single native flavor detected';
    }

    if (selectedPath == null && selectedFlavor != null) {
      final matches = entrypointsForFlavor(target, selectedFlavor);
      if (matches.isNotEmpty) selectedPath = matches.first.path;
    }

    if (selectedPath == null) {
      final main = entrypointCandidates.where(
        (item) => item.path == 'lib/main.dart',
      );
      if (main.isNotEmpty) {
        selectedPath = main.first.path;
        if (targetFlavors.length <= 1)
          reason = 'valid lib/main.dart entrypoint';
      } else if (entrypointCandidates.length == 1) {
        selectedPath = entrypointCandidates.single.path;
        reason = 'only valid Dart entrypoint detected';
      } else if (entrypointCandidates.isEmpty) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1305',
          summary: 'No valid Flutter Dart entrypoint was found',
          detail: libDirectory.path,
          action: 'Add a top-level main() under lib/ or pass --entrypoint <lib/file.dart>.',
        );
      } else {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1304',
          summary: 'Multiple Dart entrypoints require a selection',
          detail: entrypointCandidates.map((item) => item.path).join(', '),
          action: 'Run hyfens init to choose one, or pass --entrypoint <lib/file.dart>.',
        );
      }
    }

    final normalizedPath = _validatedEntrypoint(selectedPath);
    final file = File(p.join(root.path, normalizedPath));
    if (!isWithin(root, file) ||
        FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1306',
        summary: 'Selected Flutter entrypoint was not found',
        detail: normalizedPath,
        action: 'Run hyfens init or choose a project-relative file under lib/.',
      );
    }
    if (!_containsTopLevelMain(file)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1305',
        summary: 'Selected Dart file is not an executable entrypoint',
        detail: normalizedPath,
        action: 'Choose the Dart file that defines top-level main(), such as lib/src/flavors/dev.dart.',
      );
    }
    if (entrypointPath != null) reason = 'explicit entrypoint override';
    return FlutterTargetSelection(
      target: target,
      entrypointPath: normalizedPath,
      flavor: selectedFlavor,
      confidence: confidence,
      reason: reason,
    );
  }
}

final class ProjectDiscovery {
  const ProjectDiscovery();

  /// Inspects without throwing for ordinary multi-app ambiguity. Commands
  /// such as doctor and init use this to explain what was found.
  ProjectDiscoveryReport inspect({String? projectPath, Directory? start}) {
    final requested = _requestedDirectory(
      projectPath,
      start ?? Directory.current,
    );
    final explicitCandidate = projectPath == null
        ? null
        : _readCandidate(requested);
    final explicitPathIssue = projectPath == null
        ? null
        : _explicitPathIssue(requested, explicitCandidate);
    if (explicitPathIssue != null) {
      final workspaceRoot = _workspaceRoot(requested);
      return ProjectDiscoveryReport(
        repositoryRoot: _repositoryRoot(workspaceRoot),
        workspaceRoot: workspaceRoot,
        workspaceType: _workspaceType(workspaceRoot),
        candidates: const <FlutterProjectCandidate>[],
        issueCode: explicitPathIssue.$1,
        issueSummary: explicitPathIssue.$2,
        issueDetail: explicitPathIssue.$3,
        issueAction: explicitPathIssue.$4,
      );
    }
    final nearest = projectPath == null
        ? _nearestApplication(requested)
        : _directApplication(requested);
    final workspaceRoot = _workspaceRoot(nearest?.root ?? requested);
    final repositoryRoot = _repositoryRoot(workspaceRoot);
    final workspaceType = _workspaceType(workspaceRoot);
    final candidates = _discoverCandidates(
      workspaceRoot,
      focus: nearest,
      forceScan: projectPath != null || nearest == null,
    );
    if (candidates.isEmpty) {
      return ProjectDiscoveryReport(
        repositoryRoot: repositoryRoot,
        workspaceRoot: workspaceRoot,
        workspaceType: workspaceType,
        candidates: const <FlutterProjectCandidate>[],
        issueCode: 'T1301',
        issueSummary: 'No Flutter application was found',
        issueDetail: workspaceRoot.path,
        issueAction:
            'Run from a Flutter application or pass --project <directory>.',
      );
    }
    FlutterProjectCandidate? selected;
    if (nearest != null) {
      selected = candidates.firstWhere(
        (candidate) =>
            p.normalize(candidate.root.path) == p.normalize(nearest.root.path),
        orElse: () => nearest,
      );
    } else {
      selected = _persistedCandidate(candidates, workspaceRoot);
      if (selected == null && candidates.length == 1)
        selected = candidates.single;
    }
    if (selected == null && candidates.length > 1) {
      return ProjectDiscoveryReport(
        repositoryRoot: repositoryRoot,
        workspaceRoot: workspaceRoot,
        workspaceType: workspaceType,
        candidates: candidates,
        issueCode: 'T1302',
        issueSummary: 'Multiple Flutter applications were found',
        issueDetail: candidates.map((item) => item.relativePath).join(', '),
        issueAction:
            'Run hyfens init to choose one, or pass --project <directory>.',
      );
    }
    return ProjectDiscoveryReport(
      repositoryRoot: repositoryRoot,
      workspaceRoot: workspaceRoot,
      workspaceType: workspaceType,
      candidates: candidates,
      selected: selected,
    );
  }

  (String, String, String, String)? _explicitPathIssue(
    Directory requested,
    FlutterProjectCandidate? candidate,
  ) {
    final type = FileSystemEntity.typeSync(requested.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return (
        'T1306',
        'The selected Flutter project path was not found',
        requested.path,
        'Pass --project with an existing application or workspace directory.',
      );
    }
    if (candidate?.kind == FlutterPackageKind.application) {
      return null;
    }
    final hasWorkspaceMarker =
        File(p.join(requested.path, 'melos.yaml')).existsSync() ||
        _pubWorkspace(File(p.join(requested.path, 'pubspec.yaml')));
    if (candidate == null &&
        !File(p.join(requested.path, 'pubspec.yaml')).existsSync()) {
      return null;
    }
    if (candidate == null && hasWorkspaceMarker) return null;
    return (
      'T1301',
      'The selected package is not a runnable Flutter application',
      candidate == null
          ? requested.path
          : '${candidate.relativePath} (${candidate.kind.name})',
      'Pass --project with an application package, not a Flutter package or plugin.',
    );
  }

  FlutterProject discover({String? projectPath, Directory? start}) {
    final report = inspect(projectPath: projectPath, start: start);
    final selected = report.selected;
    if (selected == null) throw report.toFailure();
    return _readProject(
      selected.root,
      report.repositoryRoot,
      report.workspaceRoot,
      report.workspaceType,
      report.candidates,
    );
  }

  Directory _requestedDirectory(String? explicitPath, Directory start) {
    final rawPath = explicitPath ?? start.path;
    final canonicalPath = _resolveExistingPath(rawPath);
    final type = FileSystemEntity.typeSync(canonicalPath, followLinks: false);
    if (explicitPath != null && type == FileSystemEntityType.file) {
      return File(canonicalPath).parent.absolute;
    }
    return Directory(canonicalPath).absolute;
  }

  FlutterProjectCandidate? _nearestApplication(Directory start) {
    var directory = start;
    for (var depth = 0; depth < 64; depth++) {
      final candidate = _readCandidate(directory);
      if (candidate?.kind == FlutterPackageKind.application) return candidate;
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    return null;
  }

  FlutterProjectCandidate? _directApplication(Directory directory) {
    final candidate = _readCandidate(directory);
    return candidate?.kind == FlutterPackageKind.application ? candidate : null;
  }

  List<FlutterProjectCandidate> _discoverCandidates(
    Directory root, {
    FlutterProjectCandidate? focus,
    required bool forceScan,
  }) {
    final found = <String, FlutterProjectCandidate>{};
    if (focus != null) found[p.normalize(focus.root.path)] = focus;
    if (!forceScan && focus != null)
      return _relativeCandidates(found.values, root);
    var visited = 0;
    void visit(Directory directory, int depth) {
      if (depth > 6 || visited >= 800) return;
      if (depth > 0 &&
          (File(p.join(directory.path, '.git')).existsSync() ||
              Directory(p.join(directory.path, '.git')).existsSync())) {
        return;
      }
      visited++;
      final candidate = _readCandidate(directory);
      if (candidate?.kind == FlutterPackageKind.application) {
        found[p.normalize(directory.path)] = candidate!;
        return;
      }
      List<FileSystemEntity> entries;
      try {
        entries = directory.listSync(followLinks: false)
          ..sort((left, right) => left.path.compareTo(right.path));
      } on Object {
        return;
      }
      for (final entry in entries) {
        if (visited >= 800) return;
        if (FileSystemEntity.typeSync(entry.path, followLinks: false) !=
            FileSystemEntityType.directory) {
          continue;
        }
        final name = p.basename(entry.path);
        if (_ignoredDirectoryNames.contains(name) || name.startsWith('.')) {
          continue;
        }
        visit(Directory(entry.path), depth + 1);
      }
    }

    visit(root, 0);
    final candidates = _relativeCandidates(found.values, root);
    final productionCandidates = candidates
        .where((candidate) => !candidate.isExample)
        .toList(growable: false);
    return productionCandidates.isNotEmpty
        ? List.unmodifiable(productionCandidates)
        : candidates;
  }

  List<FlutterProjectCandidate> _relativeCandidates(
    Iterable<FlutterProjectCandidate> values,
    Directory workspaceRoot,
  ) {
    final candidates = values
        .map(
          (candidate) => FlutterProjectCandidate(
            root: candidate.root,
            relativePath: _relativeOrDot(workspaceRoot, candidate.root),
            packageName: candidate.packageName,
            kind: candidate.kind,
            entrypoints: candidate.entrypoints,
            androidApplicationId: candidate.androidApplicationId,
            iosApplicationId: candidate.iosApplicationId,
            androidFlavors: candidate.androidFlavors,
            iosFlavors: candidate.iosFlavors,
            androidApplicationIds: candidate.androidApplicationIds,
            iosApplicationIds: candidate.iosApplicationIds,
            platformEntrypoints: candidate.platformEntrypoints,
            isExample:
                candidate.isExample ||
                _isExamplePath(candidate.root, workspaceRoot),
            toolchainHint: candidate.toolchainHint,
          ),
        )
        .toList();
    candidates.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    return List.unmodifiable(candidates);
  }

  FlutterProjectCandidate? _persistedCandidate(
    Iterable<FlutterProjectCandidate> candidates,
    Directory workspaceRoot,
  ) {
    final file = File(p.join(workspaceRoot.path, 'hyfens.yaml'));
    try {
      if (file.existsSync()) {
        final raw = loadYaml(file.readAsStringSync());
        if (raw is YamlMap) {
          final value = raw['project'] ?? raw['project_path'];
          if (value is String) {
            final normalized = p.posix.normalize(value.replaceAll(r'\', '/'));
            for (final candidate in candidates) {
              if (candidate.relativePath == normalized) return candidate;
            }
          }
        }
      }
      for (final candidate in candidates) {
        final local = File(p.join(candidate.root.path, 'hyfens.yaml'));
        if (!local.existsSync()) continue;
        final localRaw = loadYaml(local.readAsStringSync());
        if (localRaw is! YamlMap) continue;
        final localValue = localRaw['project'] ?? localRaw['project_path'];
        if (localValue is String &&
            p.posix.normalize(localValue.replaceAll(r'\', '/')) ==
                candidate.relativePath) {
          return candidate;
        }
      }
    } on Object {
      return null;
    }
    return null;
  }

  FlutterProject _readProject(
    Directory root,
    Directory repositoryRoot,
    Directory workspaceRoot,
    WorkspaceType workspaceType,
    List<FlutterProjectCandidate> candidates,
  ) {
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
    final candidate = _readCandidate(root);
    if (candidate == null || candidate.kind != FlutterPackageKind.application) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1301',
        summary: 'Project is not a runnable Flutter application',
        detail: root.path,
        action:
            'Choose an application package, not a Flutter package or plugin.',
      );
    }
    final packageConfigFile = _findPackageConfig(root, packageName);
    final pubspecLockFile = _findPubspecLock(root, packageConfigFile);
    final applicationId = candidate.applicationId ?? packageName;
    return FlutterProject(
      root: root,
      repositoryRoot: repositoryRoot,
      workspaceRoot: workspaceRoot,
      workspaceType: workspaceType,
      candidateApplications: candidates,
      packageName: packageName,
      version: pubspec['version'] as String?,
      pubspec: pubspec,
      pubspecFile: pubspecFile,
      pubspecLockFile: pubspecLockFile,
      packageConfigFile: packageConfigFile,
      applicationId: applicationId,
      androidApplicationId: candidate.androidApplicationId,
      iosApplicationId: candidate.iosApplicationId,
      entrypointCandidates: candidate.entrypoints,
      androidFlavors: candidate.androidFlavors,
      iosFlavors: candidate.iosFlavors,
      androidApplicationIds: candidate.androidApplicationIds,
      iosApplicationIds: candidate.iosApplicationIds,
      platformEntrypoints: candidate.platformEntrypoints,
      toolchainHint: candidate.toolchainHint,
    );
  }
}

const _ignoredDirectoryNames = <String>{
  '.dart_tool',
  '.git',
  '.idea',
  '.fvm',
  '.puro',
  'build',
  'node_modules',
  'Pods',
  '.gradle',
  'ephemeral',
  'generated',
};

FlutterProjectCandidate? _readCandidate(Directory root) {
  final pubspecFile = File(p.join(root.path, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) return null;
  YamlMap raw;
  try {
    final loaded = loadYaml(pubspecFile.readAsStringSync());
    if (loaded is! YamlMap) return null;
    raw = loaded;
  } on Object {
    return null;
  }
  final pubspec = _toDart(raw);
  final packageName = pubspec['name'];
  if (packageName is! String ||
      !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(packageName)) {
    return null;
  }
  final flutter = pubspec['flutter'];
  if (flutter is! Map<String, Object?>) return null;
  final isPlugin = flutter['plugin'] is Map<String, Object?>;
  final entrypoints = _entrypointCandidates(root);
  final hasPlatformApp = _hasPlatformApplication(root);
  final kind = isPlugin
      ? FlutterPackageKind.plugin
      : entrypoints.isNotEmpty || hasPlatformApp
      ? FlutterPackageKind.application
      : FlutterPackageKind.package;
  final android = _androidConfiguration(root);
  final ios = _iosConfiguration(root);
  return FlutterProjectCandidate(
    root: root.absolute,
    relativePath: '.',
    packageName: packageName,
    kind: kind,
    entrypoints: entrypoints,
    androidApplicationId: android.baseId,
    iosApplicationId: ios.baseId,
    androidFlavors: android.flavors,
    iosFlavors: ios.flavors,
    androidApplicationIds: android.applicationIds,
    iosApplicationIds: ios.applicationIds,
    platformEntrypoints: <String, Map<String, String>>{
      if (android.entrypoints.isNotEmpty) 'android': android.entrypoints,
      if (ios.entrypoints.isNotEmpty) 'ios': ios.entrypoints,
    },
    isExample: false,
    toolchainHint: _toolchainHint(root),
  );
}

bool _hasPlatformApplication(Directory root) => <String>[
  'android/app',
  'ios',
  'web',
  'macos',
  'windows',
  'linux',
].any((path) => Directory(p.join(root.path, path)).existsSync());

bool _isExamplePath(Directory root, Directory workspaceRoot) => p
    .split(_relativeOrDot(workspaceRoot, root))
    .any(
      (segment) =>
          <String>{'example', 'examples'}.contains(segment.toLowerCase()),
    );

final class _NativeConfiguration {
  const _NativeConfiguration({
    this.baseId,
    this.flavors = const <String>[],
    this.applicationIds = const <String, String>{},
    this.entrypoints = const <String, String>{},
  });

  final String? baseId;
  final List<String> flavors;
  final Map<String, String> applicationIds;
  final Map<String, String> entrypoints;
}

_NativeConfiguration _androidConfiguration(Directory root) {
  final files = <File>[
    File(p.join(root.path, 'android', 'app', 'build.gradle')),
    File(p.join(root.path, 'android', 'app', 'build.gradle.kts')),
  ].where((file) => file.existsSync()).toList(growable: false);
  if (files.isEmpty) return const _NativeConfiguration();
  final source = files.map((file) => file.readAsStringSync()).join('\n');
  final defaultConfig = _namedBlock(source, 'defaultConfig');
  final namespace = _firstString(source, 'namespace');
  final baseId =
      _firstString(defaultConfig ?? '', 'applicationId') ?? namespace;
  final flavorBlock = _namedBlock(source, 'productFlavors');
  final flavorNames = <String>[];
  final applicationIds = <String, String>{};
  if (baseId != null) applicationIds['default'] = baseId;
  if (flavorBlock != null) {
    for (final entry in _directBlocks(flavorBlock)) {
      final name = entry.$1;
      final body = entry.$2;
      flavorNames.add(name);
      final explicit = _firstString(body, 'applicationId');
      final suffix = _firstString(body, 'applicationIdSuffix');
      if (explicit != null) {
        applicationIds[name] = explicit;
      } else if (baseId != null && suffix != null) {
        applicationIds[name] = '$baseId$suffix';
      } else if (baseId != null) {
        applicationIds[name] = baseId;
      }
    }
  }
  flavorNames.sort();
  return _NativeConfiguration(
    baseId: baseId,
    flavors: flavorNames,
    applicationIds: applicationIds,
  );
}

_NativeConfiguration _iosConfiguration(Directory root) {
  final flavorDirectory = Directory(
    p.join(root.path, 'ios', 'Flutter', 'Flavors'),
  );
  final flavors = <String>[];
  final ids = <String, String>{};
  final entrypoints = <String, String>{};
  if (flavorDirectory.existsSync()) {
    for (final entity in flavorDirectory.listSync(followLinks: false)) {
      if (entity is! File || p.extension(entity.path) != '.xcconfig') continue;
      final name = p.basenameWithoutExtension(entity.path);
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$').hasMatch(name)) continue;
      final source = entity.readAsStringSync();
      flavors.add(name);
      final id = _configValue(source, 'PRODUCT_BUNDLE_IDENTIFIER');
      if (id != null) ids[name] = id;
      final target = _configValue(source, 'FLUTTER_TARGET');
      if (target != null) entrypoints[name] = target;
    }
  }
  for (final file in _filesUnder(
    Directory(
      p.join(root.path, 'ios', 'Runner.xcodeproj', 'xcshareddata', 'xcschemes'),
    ),
    extension: '.xcscheme',
  )) {
    final name = p.basenameWithoutExtension(file.path);
    if (name != 'Runner' && !flavors.contains(name)) flavors.add(name);
  }
  final pbxproj = File(
    p.join(root.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
  );
  String? baseId;
  if (pbxproj.existsSync()) {
    final values = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);')
        .allMatches(pbxproj.readAsStringSync())
        .map((match) => match.group(1)!.trim())
        .where((value) => !value.startsWith(r'$('))
        .toList(growable: false);
    if (values.isNotEmpty) baseId = values.first;
  }
  if (ids['prod'] != null) baseId = ids['prod'];
  if (baseId == null && ids.isNotEmpty) baseId = ids.values.first;
  flavors.sort();
  return _NativeConfiguration(
    baseId: baseId,
    flavors: flavors,
    applicationIds: <String, String>{
      if (baseId != null) 'default': baseId,
      ...ids,
    },
    entrypoints: entrypoints,
  );
}

List<FlutterEntrypointCandidate> _entrypointCandidates(Directory root) {
  final lib = Directory(p.join(root.path, 'lib'));
  if (!lib.existsSync()) return const <FlutterEntrypointCandidate>[];
  final candidates = <FlutterEntrypointCandidate>[];
  void visit(Directory directory, int depth) {
    if (depth > 5) return;
    List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } on Object {
      return;
    }
    for (final entry in entries) {
      final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        if (!_ignoredDirectoryNames.contains(p.basename(entry.path))) {
          visit(Directory(entry.path), depth + 1);
        }
        continue;
      }
      if (type != FileSystemEntityType.file ||
          p.extension(entry.path) != '.dart') {
        continue;
      }
      final relative = p
          .relative(entry.path, from: root.path)
          .replaceAll(r'\', '/');
      if (!_looksLikeEntrypoint(relative)) continue;
      final file = File(entry.path);
      if (!_containsTopLevelMain(file)) continue;
      candidates.add(
        FlutterEntrypointCandidate(
          path: relative,
          flavor: _entrypointFlavor(relative),
          score: _entrypointScore(relative),
        ),
      );
    }
  }

  visit(lib, 0);
  candidates.sort((left, right) {
    final score = right.score.compareTo(left.score);
    return score == 0 ? left.path.compareTo(right.path) : score;
  });
  return List.unmodifiable(candidates);
}

bool _looksLikeEntrypoint(String path) {
  final normalized = path.toLowerCase();
  if (normalized.endsWith('.g.dart') || normalized.contains('/generated/'))
    return false;
  final basename = p.basenameWithoutExtension(normalized);
  return normalized == 'lib/main.dart' ||
      p.dirname(normalized) == 'lib' ||
      basename.startsWith('main_') ||
      basename.startsWith('main-') ||
      normalized.startsWith('lib/flavors/') ||
      normalized.startsWith('lib/src/flavors/');
}

String? _entrypointFlavor(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final basename = p.basenameWithoutExtension(normalized);
  if (normalized == 'lib/main.dart') return null;
  if (normalized.startsWith('lib/flavors/') ||
      normalized.startsWith('lib/src/flavors/')) {
    return basename;
  }
  if (basename.startsWith('main_')) return basename.substring(5);
  if (basename.startsWith('main-')) return basename.substring(5);
  return null;
}

int _entrypointScore(String path) {
  if (path == 'lib/main.dart') return 100;
  if (path.startsWith('lib/src/flavors/')) return 90;
  if (path.startsWith('lib/flavors/')) return 85;
  return 80;
}

bool _containsTopLevelMain(File file) {
  try {
    final parsed = parseString(
      content: file.readAsStringSync(),
      path: file.path,
      throwIfDiagnostics: false,
    );
    if (parsed.errors.isNotEmpty) return false;
    return parsed.unit.declarations.any(
      (declaration) =>
          declaration is FunctionDeclaration &&
          declaration.name.lexeme == 'main',
    );
  } on Object {
    return false;
  }
}

String? _toolchainHint(Directory root) {
  final fvmConfig = File(p.join(root.path, '.fvm', 'fvm_config.json'));
  if (fvmConfig.existsSync()) {
    try {
      final raw = jsonDecode(fvmConfig.readAsStringSync());
      if (raw is Map<String, Object?> && raw['flutter'] is String) {
        return 'FVM Flutter ${raw['flutter']} is configured; run Hyfens from the pinned SDK shell.';
      }
    } on Object {
      return 'FVM configuration detected; run Hyfens from the pinned SDK shell.';
    }
  }
  if (File(p.join(root.path, '.fvmrc')).existsSync() ||
      File(p.join(root.path, 'puro.json')).existsSync() ||
      Directory(p.join(root.path, '.puro')).existsSync()) {
    return 'A project Flutter version manager is configured; run Hyfens from its pinned SDK shell.';
  }
  return null;
}

String? _firstString(String source, String key) {
  final expression = RegExp(
    '${RegExp.escape(key)}\\s*(?:=|\\(|)\\s*["\\\']([^"\\\']+)',
  );
  return expression.firstMatch(source)?.group(1);
}

String? _configValue(String source, String key) {
  final match = RegExp(
    '^\\s*${RegExp.escape(key)}\\s*=\\s*(.+?)\\s*'
    r'$',
    multiLine: true,
  ).firstMatch(source);
  return match?.group(1)?.trim().replaceAll('"', '').replaceAll("'", '');
}

String? _namedBlock(String source, String name) {
  final match = RegExp('\\b${RegExp.escape(name)}\\s*\\{').firstMatch(source);
  if (match == null) return null;
  return _balancedBlock(source, match.end - 1);
}

String? _balancedBlock(String source, int openingBrace) {
  var depth = 0;
  String? quote;
  for (var index = openingBrace; index < source.length; index++) {
    final character = source[index];
    if (quote != null) {
      if (character == quote && (index == 0 || source[index - 1] != r'\')) {
        quote = null;
      }
      continue;
    }
    if (character == '"' || character == "'") {
      quote = character;
      continue;
    }
    if (character == '{') depth++;
    if (character == '}') {
      depth--;
      if (depth == 0) return source.substring(openingBrace + 1, index);
    }
  }
  return null;
}

List<(String, String)> _directBlocks(String source) {
  final result = <(String, String)>[];
  final pattern = RegExp(
    r'''(?:(?:create|maybeCreate)\s*\(\s*["']([^"']+)["']\s*\)|\b([A-Za-z][A-Za-z0-9_-]*))\s*\{''',
  );
  for (final match in pattern.allMatches(source)) {
    final name = match.group(1) ?? match.group(2);
    if (name == null) continue;
    final body = _balancedBlock(source, match.end - 1);
    if (body != null) result.add((name, body));
  }
  return result;
}

List<File> _filesUnder(Directory directory, {required String extension}) {
  if (!directory.existsSync()) return const <File>[];
  return directory
      .listSync(followLinks: false)
      .whereType<File>()
      .where((file) => p.extension(file.path) == extension)
      .toList(growable: false);
}

Directory _workspaceRoot(Directory start) {
  var directory = start.absolute;
  for (var depth = 0; depth < 64; depth++) {
    if (File(p.join(directory.path, 'melos.yaml')).existsSync() ||
        _pubWorkspace(File(p.join(directory.path, 'pubspec.yaml')))) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return start.absolute;
}

bool _pubWorkspace(File pubspecFile) {
  if (!pubspecFile.existsSync()) return false;
  try {
    final raw = loadYaml(pubspecFile.readAsStringSync());
    return raw is YamlMap && raw['workspace'] is YamlList;
  } on Object {
    return false;
  }
}

Directory _repositoryRoot(Directory workspaceRoot) {
  var directory = workspaceRoot.absolute;
  for (var depth = 0; depth < 64; depth++) {
    final gitDirectory = File(p.join(directory.path, '.git'));
    if (gitDirectory.existsSync() ||
        Directory(gitDirectory.path).existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return workspaceRoot.absolute;
}

WorkspaceType _workspaceType(Directory root) {
  final melos = File(p.join(root.path, 'melos.yaml')).existsSync();
  final pub = _pubWorkspace(File(p.join(root.path, 'pubspec.yaml')));
  if (melos && pub) return WorkspaceType.melosAndPubWorkspace;
  if (melos) return WorkspaceType.melos;
  if (pub) return WorkspaceType.pubWorkspace;
  if (File(p.join(root.path, 'pubspec.yaml')).existsSync()) {
    return WorkspaceType.singleApp;
  }
  return WorkspaceType.repository;
}

String _relativeOrDot(Directory root, Directory entity) {
  final relative = p
      .relative(entity.path, from: root.path)
      .replaceAll(r'\', '/');
  return relative.isEmpty ? '.' : relative;
}

String? _safeDiscoveryDetail(String? value) {
  if (value == null) return null;
  return p.isAbsolute(value) ? '<workspace>' : value;
}

String _resolveExistingPath(String value) {
  final absolute = p.normalize(p.absolute(value));
  try {
    final type = FileSystemEntity.typeSync(absolute, followLinks: false);
    // Resolve only a symlink at the requested path. Resolving every parent
    // component would turn macOS /var paths into /private/var paths, while
    // Flutter's package configuration may retain the former spelling.
    return type == FileSystemEntityType.link
        ? p.normalize(Link(absolute).resolveSymbolicLinksSync())
        : absolute;
  } on Object {
    return absolute;
  }
}

String _validatedEntrypoint(String value) {
  final normalized = value.trim().replaceAll(r'\', '/');
  if (normalized.isEmpty ||
      normalized.contains(RegExp(r'[\u0000\r\n]')) ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(normalized) ||
      normalized.split('/').contains('..') ||
      !normalized.startsWith('lib/') ||
      !normalized.toLowerCase().endsWith('.dart')) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.usage,
      code: 'T1306',
      summary: 'Invalid Flutter entrypoint path',
      detail: value,
      action: 'Use a project-relative Dart file under lib/.',
    );
  }
  return p.posix.normalize(normalized);
}

String _validatedFlavor(String value) {
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(value.trim())) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.usage,
      code: 'T1308',
      summary: 'Invalid Flutter flavor name',
      detail: value,
      action: 'Use the native flavor identifier, for example dev or staging.',
    );
  }
  return value.trim();
}

File? _findPackageConfig(Directory projectRoot, String packageName) {
  final local = File(
    p.join(projectRoot.path, '.dart_tool', 'package_config.json'),
  );
  if (local.existsSync()) return local;
  var directory = projectRoot.parent;
  for (var depth = 0; depth < 64; depth++) {
    final candidate = File(
      p.join(directory.path, '.dart_tool', 'package_config.json'),
    );
    if (candidate.existsSync() &&
        _packageConfigContainsProject(candidate, packageName, projectRoot)) {
      return candidate;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return null;
}

File _findPubspecLock(Directory projectRoot, File? packageConfigFile) {
  final local = File(p.join(projectRoot.path, 'pubspec.lock'));
  if (local.existsSync()) return local;
  if (packageConfigFile != null) {
    final workspace = File(
      p.join(packageConfigFile.parent.parent.path, 'pubspec.lock'),
    );
    if (workspace.existsSync()) return workspace;
  }
  return local;
}

bool _packageConfigContainsProject(
  File packageConfigFile,
  String packageName,
  Directory projectRoot,
) {
  try {
    final decoded = jsonDecode(packageConfigFile.readAsStringSync());
    if (decoded is! Map<String, Object?> || decoded['packages'] is! List) {
      return false;
    }
    for (final raw in decoded['packages']! as List<Object?>) {
      if (raw is! Map<String, Object?> || raw['name'] != packageName) continue;
      final rootUriValue = raw['rootUri'];
      if (rootUriValue is! String) return false;
      final rootUri = Uri.tryParse(rootUriValue);
      if (rootUri == null) return false;
      final resolved = rootUri.isAbsolute
          ? rootUri
          : packageConfigFile.parent.uri.resolveUri(rootUri);
      if (resolved.scheme != 'file') return false;
      final resolvedPath = p.normalize(
        Directory.fromUri(resolved).absolute.path,
      );
      return resolvedPath == p.normalize(projectRoot.absolute.path);
    }
  } on Object {
    return false;
  }
  return false;
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

String? extractFlutterVersion(String output) {
  final match = RegExp(r'Flutter\s+(\d+\.\d+\.\d+)').firstMatch(output);
  return match?.group(1);
}

String? extractFlutterEngineRevision(String output) {
  final match = RegExp(
    r'Engine\s+[•·]\s+(?:hash\s+([0-9a-f]{40})|revision\s+([0-9a-f]{7,64}))',
    caseSensitive: false,
  ).firstMatch(output);
  return (match?.group(1) ?? match?.group(2))?.toLowerCase();
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
