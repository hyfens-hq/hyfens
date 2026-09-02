import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../scripts/cli-release/release_support.dart';

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

  group('release metadata', () {
    test('normalizes tags and enforces the CLI package version', () {
      expect(normalizeReleaseVersion('v0.1.0'), '0.1.0');
      expect(cliPackageVersion(repository.path), '0.1.0');
      expect(
        () => validateReleaseVersion(
          repositoryRoot: repository.path,
          version: '0.1.1',
        ),
        throwsStateError,
      );
    });

    test('uses platform-specific archive names and formats', () {
      expect(
        artifactFileName(
          version: '0.1.0',
          platform: 'macos',
          architecture: 'arm64',
        ),
        'hyfens-0.1.0-macos-arm64.tar.gz',
      );
      final windows = parseArtifactFileName('hyfens-0.1.0-windows-x64.zip');
      expect(windows.platform, 'windows');
      expect(windows.architecture, 'x64');
      expect(
        () => parseArtifactFileName('hyfens-0.1.0-linux-x64.zip'),
        throwsFormatException,
      );
    });
  });

  test('inventory writes SHA256SUMS and all native platform records', () async {
    final artifacts = await Directory.systemTemp.createTemp(
      'hyfens-release-inventory-test-',
    );
    addTearDown(() => artifacts.delete(recursive: true));
    final names = <String>[
      'hyfens-0.1.0-linux-arm64.tar.gz',
      'hyfens-0.1.0-linux-x64.tar.gz',
      'hyfens-0.1.0-macos-arm64.tar.gz',
      'hyfens-0.1.0-macos-x64.tar.gz',
      'hyfens-0.1.0-windows-arm64.zip',
      'hyfens-0.1.0-windows-x64.zip',
    ];
    for (final name in names) {
      await File(p.join(artifacts.path, name)).writeAsString(name);
    }
    final inventory = File(p.join(artifacts.path, 'artifact-inventory.json'));
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'run',
      '../scripts/cli-release/inventory.dart',
      '--version',
      '0.1.0',
      '--artifacts-dir',
      artifacts.path,
      '--output',
      inventory.path,
    ], workingDirectory: p.join(repository.path, 'cli'));
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final body =
        jsonDecode(await inventory.readAsString()) as Map<String, dynamic>;
    expect(body['releaseVersion'], '0.1.0');
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
      'packaging/cli/winget/Hyfens.Hyfens.installer.yaml.template',
      'packaging/cli/winget/Hyfens.Hyfens.locale.en-US.yaml.template',
    ];
    final platformPlaceholders = <String, String>{
      files[0]: '__MACOS_',
      files[1]: '__WINDOWS_',
      files[2]: '__WINDOWS_',
      files[3]: '__WINGET_PUBLISHER__',
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
