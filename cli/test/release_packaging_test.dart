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

  Future<ProcessResult> runInventory(Directory artifacts, File output) =>
      Process.run(Platform.resolvedExecutable, <String>[
        'run',
        '../scripts/cli-release/inventory.dart',
        '--version',
        '0.1.0',
        '--artifacts-dir',
        artifacts.path,
        '--output',
        output.path,
      ], workingDirectory: p.join(repository.path, 'cli'));

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

    test('rejects malformed semantic versions', () {
      for (final value in [
        '01.2.3',
        '1.2.3-01',
        '1.2.3-a..b',
        '1.2.3+',
        '1.2.3+..',
      ]) {
        expect(
          () => normalizeReleaseVersion(value),
          throwsFormatException,
          reason: value,
        );
      }
      expect(
        normalizeReleaseVersion('1.2.3-rc.1+build.5'),
        '1.2.3-rc.1+build.5',
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
    final result = await runInventory(artifacts, inventory);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final body =
        jsonDecode(await inventory.readAsString()) as Map<String, dynamic>;
    expect(body['releaseVersion'], '0.1.0');
    expect((body['artifacts'] as List<dynamic>), hasLength(6));
    final checksums = await File(p.join(artifacts.path, 'SHA256SUMS'))
        .readAsLines();
    expect(checksums, hasLength(7));
    for (final line in checksums) {
      final parts = line.split('  ');
      expect(parts, hasLength(2));
      expect(
        parts[0],
        sha256Hex(await File(p.join(artifacts.path, parts[1])).readAsBytes()),
      );
    }
    expect(checksums.last, endsWith('  artifact-inventory.json'));
  });

  group('inventory fails closed before writing metadata', () {
    late Directory artifacts;
    late File output;
    late File firstArchive;

    setUp(() async {
      artifacts = await Directory.systemTemp.createTemp(
        'hyfens-inventory-invalid-',
      );
      output = File(p.join(artifacts.path, 'artifact-inventory.json'));
      for (final target in supportedReleaseTargets) {
        final name = artifactFileName(
          version: '0.1.0',
          platform: target.split('/')[0],
          architecture: target.split('/')[1],
        );
        firstArchive = await File(p.join(artifacts.path, name))
            .writeAsString(name);
      }
    });
    tearDown(() => artifacts.delete(recursive: true));

    Future<void> expectRejected() async {
      final result = await runInventory(artifacts, output);
      expect(result.exitCode, 2, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('cli-release inventory: Bad state:'));
      expect(output.existsSync(), isFalse);
      expect(File(p.join(artifacts.path, 'SHA256SUMS')).existsSync(), isFalse);
    }

    test('rejects an extra non-archive file', () async {
      await File(p.join(artifacts.path, 'unexpected.txt'))
          .writeAsString('unexpected');
      await expectRejected();
    });
    test('rejects a missing target', () async {
      await firstArchive.delete();
      await expectRejected();
    });
    test('rejects a noncanonical architecture alias', () async {
      await firstArchive.rename(
        firstArchive.path.replaceFirst('-x64.', '-amd64.'),
      );
      await expectRejected();
    });
    test('rejects empty archives', () async {
      await firstArchive.writeAsString('');
      await expectRejected();
    });
    test('rejects an archive replaced by a directory', () async {
      await firstArchive.delete();
      await Directory(firstArchive.path).create();
      await expectRejected();
    });
    test(
      'rejects an archive replaced by a symlink',
      () async {
        await firstArchive.delete();
        await Link(firstArchive.path).create('missing-target');
        await expectRejected();
      },
      skip: Platform.isWindows
          ? 'Symlink creation requires Windows privileges.'
          : false,
    );
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
