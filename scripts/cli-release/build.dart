import 'dart:io';

import 'package:path/path.dart' as p;

import 'release_support.dart';

String get repositoryRoot =>
    File.fromUri(Platform.script).parent.parent.parent.absolute.path;

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

Future<void> copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final name = p.basename(entity.path);
    final target = p.join(destination.path, name);
    if (entity is Directory) {
      await copyDirectory(entity, Directory(target));
    } else if (entity is File) {
      await entity.copy(target);
    } else if (entity is Link) {
      throw StateError('Release bundle contains an unsupported link: $name');
    }
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
    final packageName = p.withoutExtension(p.withoutExtension(archiveName));
    final packageDirectory = Directory(p.join(staging.path, packageName));
    final binDirectory = Directory(p.join(packageDirectory.path, 'bin'));
    await binDirectory.create(recursive: true);
    final cliRoot = Directory(p.join(root.path, 'cli'));
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
