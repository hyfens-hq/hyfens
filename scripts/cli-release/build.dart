import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../cli/lib/src/runtime_bundle.dart';
import 'release_support.dart';

const _runtimeExcludedDirectories = <String>{
  '.dart_tool',
  '.git',
  '.gradle',
  '.symlinks',
  'build',
  'example',
  'examples',
  'pods',
  'test',
  'tests',
};

const _runtimeLegalFileNames = <String>{
  'license',
  'license.md',
  'license.txt',
  'notice',
  'notice.md',
  'notice.txt',
};

String get repositoryRoot =>
    File.fromUri(Platform.script).parent.parent.parent.absolute.path;

String archiveRootName(String archiveName) {
  final format = parseArtifactFileName(archiveName).format;
  final suffix = '.$format';
  return archiveName.substring(0, archiveName.length - suffix.length);
}

void printUsage() {
  stdout.writeln('''
Build a native Hyfens CLI release archive.

Required for a build:
  --version VERSION       Release tag version, without or with a leading v.
  --platform PLATFORM     macos, linux, or windows.

Optional:
  --architecture ARCH     x64, arm64, or arm. Defaults to the host architecture.
  --output-dir DIRECTORY  Directory for the resulting archive. Defaults to dist.
  --without-tool          Omit the deprecated tool compatibility shim.
  --check-version VERSION Validate VERSION against cli/pubspec.yaml and exit.
  --help                  Show this help.
''');
}

String? optionValue(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1) return null;
  if (index + 1 >= arguments.length || arguments[index + 1].startsWith('--')) {
    throw FormatException('$name requires a value');
  }
  return arguments[index + 1];
}

String detectArchitecture() {
  if (Platform.isWindows) {
    final raw =
        Platform.environment['PROCESSOR_ARCHITEW6432'] ??
        Platform.environment['PROCESSOR_ARCHITECTURE'] ??
        '';
    return normalizeArchitecture(raw);
  }
  final result = Process.runSync('uname', <String>['-m']);
  if (result.exitCode != 0) {
    throw StateError('Unable to determine host architecture with uname.');
  }
  return normalizeArchitecture(result.stdout.toString());
}

Future<void> runChecked(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  if (result.stdout.toString().isNotEmpty) stdout.write(result.stdout);
  if (result.stderr.toString().isNotEmpty) stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'Command failed with exit code ${result.exitCode}.',
      result.exitCode,
    );
  }
}

Future<Directory> buildCliBundle({
  required Directory cliRoot,
  required String entrypoint,
  required Directory output,
}) async {
  await runChecked(Platform.resolvedExecutable, <String>[
    'build',
    'cli',
    '--target',
    entrypoint,
    '--output',
    output.path,
    '--verbosity=warning',
  ], workingDirectory: cliRoot.path);
  final bundle = Directory(p.join(output.path, 'bundle'));
  if (!bundle.existsSync()) {
    throw StateError('Dart did not produce ${bundle.path}.');
  }
  return bundle;
}

Future<void> copyDirectory(
  Directory source,
  Directory destination, {
  Set<String> excludedDirectories = const {},
}) async {
  final sourceType = FileSystemEntity.typeSync(source.path, followLinks: false);
  if (sourceType == FileSystemEntityType.link) {
    throw StateError('Release bundle source directory is a symlink.');
  }
  if (sourceType != FileSystemEntityType.directory) {
    throw StateError('Release bundle source directory is unavailable.');
  }
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final name = p.basename(entity.path);
    final target = p.join(destination.path, name);
    if (entity is Directory) {
      if (excludedDirectories.any(
        (excluded) => excluded.toLowerCase() == name.toLowerCase(),
      )) {
        continue;
      }
      await copyDirectory(
        entity,
        Directory(target),
        excludedDirectories: excludedDirectories,
      );
    } else if (entity is File) {
      await entity.copy(target);
    } else if (entity is Link) {
      throw StateError('Release bundle contains an unsupported link: $name');
    }
  }
}

Future<void> copyRuntimePackage(
  Directory source,
  Directory destination, {
  required String packageName,
}) async {
  final sourceType = FileSystemEntity.typeSync(source.path, followLinks: false);
  if (sourceType == FileSystemEntityType.link) {
    throw StateError('Runtime package source is a symlink: $packageName');
  }
  if (sourceType != FileSystemEntityType.directory) {
    throw StateError('Runtime package source is unavailable: $packageName');
  }
  final sourceLib = Directory(p.join(source.path, 'lib'));
  final sourcePubspec = File(p.join(source.path, 'pubspec.yaml'));
  if (FileSystemEntity.typeSync(sourceLib.path, followLinks: false) !=
          FileSystemEntityType.directory ||
      FileSystemEntity.typeSync(sourcePubspec.path, followLinks: false) !=
          FileSystemEntityType.file) {
    throw StateError('Runtime package is incomplete: $packageName');
  }
  await copyDirectory(sourceLib, Directory(p.join(destination.path, 'lib')));
  await sourcePubspec.copy(p.join(destination.path, 'pubspec.yaml'));
  for (final relative
      in RuntimePackageBundle.additionalPackagePaths[packageName] ??
          const <String>[]) {
    await _copyRuntimePath(
      source: source,
      destination: destination,
      relative: relative,
      packageName: packageName,
    );
  }
  // Runtime-owned platform plugins are part of the base build, not OTA data.
  // The released executable must carry their source just like their Dart API;
  // native registrants cannot resolve an omitted platform implementation.
  for (final platform in RuntimePackageBundle.nativePackageDirectoryNames) {
    final native = Directory(p.join(source.path, platform));
    final type = FileSystemEntity.typeSync(native.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type == FileSystemEntityType.link) {
      throw StateError(
        'Runtime package platform directory is a symlink: $packageName/$platform',
      );
    }
    if (type != FileSystemEntityType.directory) {
      throw StateError(
        'Runtime package platform directory is unavailable: $packageName/$platform',
      );
    }
    await copyDirectory(
      native,
      Directory(p.join(destination.path, platform)),
      excludedDirectories: _runtimeExcludedDirectories,
    );
  }
  await _copyRuntimeLegalFiles(source, destination);
}

Future<void> _copyRuntimePath({
  required Directory source,
  required Directory destination,
  required String relative,
  required String packageName,
}) async {
  final sourcePath = p.join(source.path, relative);
  var checkedPath = source.path;
  for (final segment in p.split(relative)) {
    checkedPath = p.join(checkedPath, segment);
    if (FileSystemEntity.typeSync(checkedPath, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError(
        'Runtime package path is a symlink: $packageName/$relative',
      );
    }
  }
  final type = FileSystemEntity.typeSync(sourcePath, followLinks: false);
  if (type == FileSystemEntityType.link) {
    throw StateError(
      'Runtime package path is a symlink: $packageName/$relative',
    );
  }
  if (type == FileSystemEntityType.file) {
    final target = File(p.join(destination.path, relative));
    await target.parent.create(recursive: true);
    await File(sourcePath).copy(target.path);
    return;
  }
  if (type == FileSystemEntityType.directory) {
    await copyDirectory(
      Directory(sourcePath),
      Directory(p.join(destination.path, relative)),
      excludedDirectories: _runtimeExcludedDirectories,
    );
    return;
  }
  throw StateError('Runtime package path is missing: $packageName/$relative');
}

Future<void> _copyRuntimeLegalFiles(
  Directory source,
  Directory destination,
) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (!_runtimeLegalFileNames.contains(name.toLowerCase())) continue;
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw StateError('Runtime package legal file is a symlink: $name');
    }
    if (type != FileSystemEntityType.file) {
      throw StateError('Runtime package legal file is unavailable: $name');
    }
    await File(entity.path).copy(p.join(destination.path, name));
  }
}

Map<String, Directory> packageRootsFromConfig(Directory cliRoot) {
  final file = File(p.join(cliRoot.path, '.dart_tool', 'package_config.json'));
  if (!file.existsSync()) {
    throw StateError('Dart package configuration is missing: ${file.path}');
  }
  final raw = jsonDecode(file.readAsStringSync());
  if (raw is! Map<String, Object?> || raw['packages'] is! List<Object?>) {
    throw StateError('Dart package configuration is malformed: ${file.path}');
  }
  final roots = <String, Directory>{};
  for (final item in raw['packages']! as List<Object?>) {
    if (item is! Map<String, Object?> ||
        item['name'] is! String ||
        item['rootUri'] is! String) {
      continue;
    }
    final uri = Uri.parse(item['rootUri']! as String);
    final resolved = uri.isAbsolute ? uri : file.parent.uri.resolveUri(uri);
    if (resolved.scheme == 'file') {
      roots[item['name']! as String] = Directory.fromUri(resolved);
    }
  }
  return roots;
}

Future<void> stageRuntimePackages({
  required Directory repository,
  required Directory cliRoot,
  required Directory packageDirectory,
}) async {
  final runtimeRoot = Directory(p.join(packageDirectory.path, 'runtime'));
  final hostedRoots = packageRootsFromConfig(cliRoot);
  for (final entry in RuntimePackageBundle.repositoryPackagePaths.entries) {
    await copyRuntimePackage(
      Directory(p.join(repository.path, entry.value)),
      Directory(p.join(runtimeRoot.path, entry.key)),
      packageName: entry.key,
    );
  }
  for (final name in RuntimePackageBundle.hostedPackageNames) {
    final source = hostedRoots[name];
    if (source == null) {
      throw StateError('Runtime package is missing from the CLI graph: $name');
    }
    await copyRuntimePackage(
      source,
      Directory(p.join(runtimeRoot.path, name)),
      packageName: name,
    );
  }
}

Future<void> createArchive({
  required String platform,
  required Directory packageDirectory,
  required File archive,
}) async {
  if (platform == 'windows') {
    final environment = <String, String>{
      ...Platform.environment,
      'HYFENS_PACKAGE_DIR': packageDirectory.path,
      'HYFENS_ARCHIVE_PATH': archive.path,
    };
    await runChecked(
      'powershell.exe',
      <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'Compress-Archive -LiteralPath $env:HYFENS_PACKAGE_DIR '
            r'-DestinationPath $env:HYFENS_ARCHIVE_PATH -Force',
      ],
      workingDirectory: packageDirectory.parent.path,
      environment: environment,
    );
  } else {
    await runChecked('tar', <String>[
      '-czf',
      archive.path,
      '-C',
      packageDirectory.parent.path,
      p.basename(packageDirectory.path),
    ], workingDirectory: packageDirectory.parent.path);
  }
  if (!archive.existsSync() || archive.lengthSync() == 0) {
    throw StateError('Archive was not produced: ${archive.path}');
  }
}

Future<void> buildRelease({
  required String version,
  required String platform,
  required String architecture,
  required String outputPath,
  required bool includeTool,
}) async {
  final root = Directory(repositoryRoot);
  validateReleaseVersion(repositoryRoot: root.path, version: version);
  final normalizedVersion = normalizeReleaseVersion(version);
  final normalizedPlatform = normalizePlatform(platform);
  final normalizedArchitecture = normalizeArchitecture(architecture);
  final hostArchitecture = detectArchitecture();
  if (normalizedArchitecture != hostArchitecture) {
    throw StateError(
      'Release architecture $normalizedArchitecture does not match the '
      'host architecture $hostArchitecture. Use a matching runner.',
    );
  }
  if ((normalizedPlatform == 'windows' && !Platform.isWindows) ||
      (normalizedPlatform == 'macos' && !Platform.isMacOS) ||
      (normalizedPlatform == 'linux' && !Platform.isLinux)) {
    throw StateError(
      'Native release build for $normalizedPlatform must run on a matching '
      'GitHub runner.',
    );
  }

  final outputDirectory = Directory(
    p.isAbsolute(outputPath)
        ? outputPath
        : p.join(Directory.current.path, outputPath),
  );
  await outputDirectory.create(recursive: true);
  final archiveName = artifactFileName(
    version: normalizedVersion,
    platform: normalizedPlatform,
    architecture: normalizedArchitecture,
  );
  final archive = File(p.join(outputDirectory.path, archiveName));
  if (archive.existsSync()) {
    throw StateError('Refusing to overwrite existing archive: ${archive.path}');
  }

  final staging = await Directory.systemTemp.createTemp('hyfens-cli-release-');
  try {
    final packageName = archiveRootName(archiveName);
    final packageDirectory = Directory(p.join(staging.path, packageName));
    final binDirectory = Directory(p.join(packageDirectory.path, 'bin'));
    await binDirectory.create(recursive: true);
    final cliRoot = Directory(p.join(root.path, 'cli'));
    await stageRuntimePackages(
      repository: root,
      cliRoot: cliRoot,
      packageDirectory: packageDirectory,
    );
    final canonicalBundle = await buildCliBundle(
      cliRoot: cliRoot,
      entrypoint: 'bin/hyfens.dart',
      output: Directory(p.join(staging.path, 'canonical')),
    );
    final executableName = Platform.isWindows ? 'hyfens.exe' : 'hyfens';
    final canonicalExecutable = File(
      p.join(canonicalBundle.path, 'bin', executableName),
    );
    if (!canonicalExecutable.existsSync() ||
        canonicalExecutable.lengthSync() == 0) {
      throw StateError('Dart did not produce ${canonicalExecutable.path}.');
    }
    await canonicalExecutable.copy(p.join(binDirectory.path, executableName));
    final libraryDirectory = Directory(p.join(canonicalBundle.path, 'lib'));
    if (libraryDirectory.existsSync()) {
      await copyDirectory(
        libraryDirectory,
        Directory(p.join(packageDirectory.path, 'lib')),
      );
    }
    if (includeTool) {
      final toolBundle = await buildCliBundle(
        cliRoot: cliRoot,
        entrypoint: 'bin/tool.dart',
        output: Directory(p.join(staging.path, 'tool')),
      );
      final toolName = Platform.isWindows ? 'tool.exe' : 'tool';
      final toolExecutable = File(p.join(toolBundle.path, 'bin', toolName));
      if (!toolExecutable.existsSync() || toolExecutable.lengthSync() == 0) {
        throw StateError('Dart did not produce ${toolExecutable.path}.');
      }
      await toolExecutable.copy(p.join(binDirectory.path, toolName));
    }
    if (!Platform.isWindows) {
      await runChecked('chmod', <String>[
        '755',
        p.join(binDirectory.path, executableName),
      ], workingDirectory: packageDirectory.path);
      if (includeTool) {
        await runChecked('chmod', <String>[
          '755',
          p.join(binDirectory.path, 'tool'),
        ], workingDirectory: packageDirectory.path);
      }
      final packageLibraries = Directory(p.join(packageDirectory.path, 'lib'));
      if (packageLibraries.existsSync()) {
        await for (final library in packageLibraries.list(followLinks: false)) {
          if (library is File) {
            await runChecked('chmod', <String>[
              '755',
              library.path,
            ], workingDirectory: packageDirectory.path);
          }
        }
      }
    }
    for (final name in <String>['LICENSE', 'THIRD_PARTY_NOTICES.md']) {
      final source = File(p.join(root.path, name));
      if (source.existsSync()) {
        await source.copy(p.join(packageDirectory.path, name));
      }
    }
    await File(p.join(packageDirectory.path, 'README.txt')).writeAsString('''
Hyfens CLI $normalizedVersion

Run bin/hyfens${Platform.isWindows ? '.exe' : ''} --help.
''');
    await createArchive(
      platform: normalizedPlatform,
      packageDirectory: packageDirectory,
      archive: archive,
    );
  } finally {
    await staging.delete(recursive: true);
  }
  stdout.writeln('Built ${archive.path}');
}

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help')) {
    printUsage();
    return;
  }
  try {
    final checkVersion = optionValue(arguments, '--check-version');
    if (checkVersion != null) {
      final version = normalizeReleaseVersion(checkVersion);
      validateReleaseVersion(repositoryRoot: repositoryRoot, version: version);
      stdout.writeln('Release version $version matches cli/pubspec.yaml.');
      return;
    }
    final version = optionValue(arguments, '--version');
    final platform = optionValue(arguments, '--platform');
    if (version == null || platform == null) {
      throw FormatException('--version and --platform are required');
    }
    await buildRelease(
      version: version,
      platform: platform,
      architecture:
          optionValue(arguments, '--architecture') ?? detectArchitecture(),
      outputPath: optionValue(arguments, '--output-dir') ?? 'dist',
      includeTool: !arguments.contains('--without-tool'),
    );
  } on Object catch (error) {
    stderr.writeln('cli-release build: $error');
    exitCode = 2;
  }
}
