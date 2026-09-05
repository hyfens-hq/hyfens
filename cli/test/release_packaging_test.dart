import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../scripts/cli-release/build.dart' as release_build;
import '../../scripts/cli-release/release_support.dart';
import '../lib/src/runtime_bundle.dart';

Directory repositoryDirectory() {
  var directory = Directory.current.absolute;
  while (directory.path != directory.parent.path) {
    if (File(p.join(directory.path, 'cli', 'pubspec.yaml')).existsSync()) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate the repository root.');
}

void main() {
  final repository = repositoryDirectory();

  test(
    'runtime archive retains native plugin sources but not build caches',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-native-bundle-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = Directory(p.join(root.path, 'source'));
      final destination = Directory(p.join(root.path, 'runtime'));
      for (final relative in [
        'lib/key.dart',
        'lib/src/build/code.dart',
        'pubspec.yaml',
        'android/src/main/Plugin.kt',
        'android/build.gradle',
        'ios/Classes/Plugin.swift',
        'ios/key_plugin.podspec',
        'darwin/Classes/Plugin.swift',
        'linux/src/plugin.cc',
        'macos/Classes/Plugin.swift',
        'windows/src/plugin.cpp',
        'hook/build.dart',
        'src/objective_c.c',
        'LICENSE',
        'NOTICE',
        'README.md',
        'test/ignored.dart',
        'example/ignored.dart',
        'android/build/private-output',
        'android/.gradle/cache',
        'android/test/ignored.dart',
        'ios/Pods/cache',
        'ios/example/ignored.swift',
      ]) {
        final file = File(p.join(source.path, relative));
        await file.parent.create(recursive: true);
        await file.writeAsString('package test input');
      }
      await release_build.copyRuntimePackage(
        source,
        destination,
        packageName: 'objective_c',
      );
      for (final relative in [
        'lib/key.dart',
        'lib/src/build/code.dart',
        'pubspec.yaml',
        'android/src/main/Plugin.kt',
        'android/build.gradle',
        'ios/Classes/Plugin.swift',
        'ios/key_plugin.podspec',
        'darwin/Classes/Plugin.swift',
        'linux/src/plugin.cc',
        'macos/Classes/Plugin.swift',
        'windows/src/plugin.cpp',
        'hook/build.dart',
        'src/objective_c.c',
        'LICENSE',
        'NOTICE',
      ]) {
        expect(
          File(p.join(destination.path, relative)).existsSync(),
          isTrue,
          reason: relative,
        );
      }
      for (final relative in [
        'android/build',
        'android/.gradle',
        'android/test',
        'ios/Pods',
        'ios/example',
        'test',
        'example',
        'README.md',
      ]) {
        expect(
          FileSystemEntity.typeSync(p.join(destination.path, relative)),
          FileSystemEntityType.notFound,
          reason: relative,
        );
      }
    },
  );

  test('runtime bundle pins the locked non-SDK production closure', () {
    const expectedHosted = <String>[
      '_fe_analyzer_shared',
      'analyzer',
      'async',
      'characters',
      'code_assets',
      'collection',
      'convert',
      'crypto',
      'cryptography',
      'ffi',
      'file',
      'glob',
      'hooks',
      'logging',
      'material_color_utilities',
      'meta',
      'objective_c',
      'package_config',
      'path',
      'path_provider',
      'path_provider_android',
      'path_provider_foundation',
      'path_provider_linux',
      'path_provider_platform_interface',
      'path_provider_windows',
      'platform',
      'plugin_platform_interface',
      'pub_semver',
      'record_use',
      'source_span',
      'string_scanner',
      'term_glyph',
      'typed_data',
      'vector_math',
      'watcher',
      'xdg_directories',
      'yaml',
    ];
    const expectedRepository = <String>[
      'hyfens_flutter_integration',
      'hyfens_patch_format',
      'hyfens_runtime',
      'instrumentation_e0',
      'patch_loading_e1',
    ];

    expect(
      RuntimePackageBundle.repositoryPackagePaths.keys,
      orderedEquals(expectedRepository),
    );
    expect(
      RuntimePackageBundle.hostedPackageNames,
      orderedEquals(expectedHosted),
    );
    expect(
      RuntimePackageBundle.packageNames,
      orderedEquals(<String>[...expectedRepository, ...expectedHosted]),
    );
    expect(RuntimePackageBundle.packageNames, isNot(contains('flutter')));
    expect(RuntimePackageBundle.packageNames, isNot(contains('sky_engine')));
    expect(RuntimePackageBundle.packageNames, isNot(contains('test')));
    expect(
      RuntimePackageBundle.additionalPackagePaths['objective_c'],
      orderedEquals(<String>['hook/build.dart', 'src']),
    );

    // Inspect the resolved production graph instead of only comparing two
    // copies of the allowlist. A newly introduced dependency must fail here
    // until the standalone bundle includes it, even if source builds work.
    final roots = release_build.packageRootsFromConfig(
      Directory(p.join(repository.path, 'cli')),
    );
    final pending = RuntimePackageBundle.repositoryPackagePaths.keys.toList();
    final closure = <String>{};
    while (pending.isNotEmpty) {
      final name = pending.removeLast();
      if (!closure.add(name)) continue;
      final root = roots[name];
      expect(
        root,
        isNotNull,
        reason: 'Resolved runtime package missing: $name',
      );
      final manifest = loadYaml(
        File(p.join(root!.path, 'pubspec.yaml')).readAsStringSync(),
      ) as YamlMap;
      final dependencies = manifest['dependencies'];
      if (dependencies is YamlMap) {
        pending.addAll(dependencies.keys.cast<String>());
      }
    }
    closure.removeAll(const ['flutter', 'sky_engine']);
    expect(RuntimePackageBundle.packageNames.toSet(), unorderedEquals(closure));
    expect(RuntimePackageBundle.packageNames.length, closure.length);
  });

  group('release metadata', () {
    test('normalizes tags and enforces the CLI package version', () {
      expect(normalizeReleaseVersion('v0.1.0'), '0.1.0');
      expect(cliPackageVersion(repository.path), '0.1.3');
      validateReleaseVersion(repositoryRoot: repository.path, version: '0.1.3');
      expect(
        () => validateReleaseVersion(
          repositoryRoot: repository.path,
          version: '0.1.0',
        ),
        throwsStateError,
      );
    });

    test('uses platform-specific archive names and formats', () {
      expect(
        artifactFileName(
          version: '0.1.3',
          platform: 'macos',
          architecture: 'arm64',
        ),
        'hyfens-0.1.3-macos-arm64.tar.gz',
      );
      final windows = parseArtifactFileName('hyfens-0.1.3-windows-x64.zip');
      expect(windows.platform, 'windows');
      expect(windows.architecture, 'x64');
      expect(
        () => parseArtifactFileName('hyfens-0.1.3-linux-x64.zip'),
        throwsFormatException,
      );
    });

    test(
      'keeps full archive stems as package roots for every native target',
      () {
        const targets = <String, String>{
          'macos/x64': 'tar.gz',
          'macos/arm64': 'tar.gz',
          'linux/x64': 'tar.gz',
          'linux/arm64': 'tar.gz',
          'windows/x64': 'zip',
          'windows/arm64': 'zip',
        };

        for (final entry in targets.entries) {
          final parts = entry.key.split('/');
          final platform = parts[0];
          final architecture = parts[1];
          final archiveName =
              'hyfens-0.1.3-$platform-$architecture.' + entry.value;

          expect(
            artifactFileName(
              version: '0.1.3',
              platform: platform,
              architecture: architecture,
            ),
            archiveName,
          );
          expect(
            release_build.archiveRootName(archiveName),
            'hyfens-0.1.3-$platform-$architecture',
          );
        }
      },
    );
  });

  test('inventory writes SHA256SUMS and all native platform records', () async {
    final artifacts = await Directory.systemTemp.createTemp(
      'hyfens-release-inventory-test-',
    );
    addTearDown(() => artifacts.delete(recursive: true));
    final names = <String>[
      'hyfens-0.1.3-linux-arm64.tar.gz',
      'hyfens-0.1.3-linux-x64.tar.gz',
      'hyfens-0.1.3-macos-arm64.tar.gz',
      'hyfens-0.1.3-macos-x64.tar.gz',
      'hyfens-0.1.3-windows-arm64.zip',
      'hyfens-0.1.3-windows-x64.zip',
    ];
    for (final name in names) {
      await File(p.join(artifacts.path, name)).writeAsString(name);
    }
    final inventory = File(p.join(artifacts.path, 'artifact-inventory.json'));
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'run',
      '../scripts/cli-release/inventory.dart',
      '--version',
      '0.1.3',
      '--artifacts-dir',
      artifacts.path,
      '--output',
      inventory.path,
    ], workingDirectory: p.join(repository.path, 'cli'));
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final body =
        jsonDecode(await inventory.readAsString()) as Map<String, dynamic>;
    expect(body['releaseVersion'], '0.1.3');
    expect((body['artifacts'] as List<dynamic>), hasLength(6));
    final checksums = await File(p.join(artifacts.path, 'SHA256SUMS'))
        .readAsLines();
    expect(checksums, hasLength(6));
    expect(checksums.every((line) => line.contains('  hyfens-')), isTrue);
  });

  test('package-manager files remain explicit templates', () {
    final files = <String>[
      'packaging/cli/homebrew/hyfens.rb.template',
      'packaging/cli/scoop/hyfens.json.template',
      'packaging/cli/winget/Hyfens.Hyfens.yaml.template',
      'packaging/cli/winget/Hyfens.Hyfens.installer.yaml.template',
      'packaging/cli/winget/Hyfens.Hyfens.locale.en-US.yaml.template',
    ];
    final platformPlaceholders = <String, String>{
      files[0]: '__MACOS_',
      files[1]: '__WINDOWS_',
      files[2]: '__WINGET_PUBLISHER__',
      files[3]: '__WINDOWS_',
      files[4]: '__WINGET_PUBLISHER__',
    };
    for (final relativePath in files) {
      final content = File(p.join(repository.path, relativePath))
          .readAsStringSync();
      expect(content, contains('__VERSION__'), reason: relativePath);
      expect(content.toUpperCase(), contains('TEMPLATE'), reason: relativePath);
      expect(
        content,
        contains(platformPlaceholders[relativePath]!),
        reason: relativePath,
      );
    }
  });
}
