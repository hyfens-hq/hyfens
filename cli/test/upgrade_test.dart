import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hyfens_tool/tool.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('latest-release parser accepts compact stable GitHub JSON', () {
    expect(
      parseLatestHyfensReleaseVersion(
        '{"tag_name":"v0.1.1","draft":false,"prerelease":false}',
      ),
      '0.1.1',
    );
    expect(
      () => parseLatestHyfensReleaseVersion(
        '{"tag_name":"v0.1.1","draft":true,"prerelease":false}',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseLatestHyfensReleaseVersion('{"draft":false}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('release version comparison uses semantic pre-release ordering', () {
    expect(compareHyfensReleaseVersions('0.1.0', '0.1.1'), lessThan(0));
    expect(compareHyfensReleaseVersions('v0.1.1', '0.1.1'), 0);
    expect(compareHyfensReleaseVersions('0.1.1-rc.1', '0.1.1'), lessThan(0));
    expect(
      compareHyfensReleaseVersions('0.1.1-rc.2', '0.1.1-rc.10'),
      lessThan(0),
    );
  });

  test(
    'explicit version check does not request mutable latest metadata',
    () async {
      final transport = _FakeUpgradeTransport();
      final service = HyfensUpgradeService(
        transport: transport,
        currentVersion: () => '0.1.0',
        executablePath: '/tmp/hyfens',
        platform: 'macos',
        architecture: 'arm64',
      );

      final result = await service.upgrade(
        requestedVersion: 'v0.1.1',
        checkOnly: true,
      );

      expect(result.latestVersion, '0.1.1');
      expect(result.updateAvailable, isTrue);
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'upgrade verifies checksum before activating a release archive',
    () async {
      final fixture = await Directory.systemTemp.createTemp('hyfens-upgrade-');
      addTearDown(() => fixture.delete(recursive: true));
      final version = '0.1.1';
      final platform = 'macos';
      final architecture = 'arm64';
      final archiveName = hyfensReleaseArtifactName(
        version: version,
        platform: platform,
        architecture: architecture,
      );
      final rootName = p.withoutExtension(p.withoutExtension(archiveName));
      final releaseRoot = Directory(p.join(fixture.path, rootName));
      await Directory(p.join(releaseRoot.path, 'bin')).create(recursive: true);
      final releaseExecutable = File(p.join(releaseRoot.path, 'bin', 'hyfens'));
      await releaseExecutable.writeAsBytes(<int>[1, 2, 3]);
      final archive = File(p.join(fixture.path, archiveName));
      final archiveResult = await Process.run('tar', <String>[
        '-czf',
        archive.path,
        '-C',
        fixture.path,
        rootName,
      ]);
      expect(
        archiveResult.exitCode,
        0,
        reason: '${archiveResult.stdout}\n${archiveResult.stderr}',
      );
      final archiveBytes = await archive.readAsBytes();
      final latestUri = Uri.parse('https://api.example/latest');
      final releaseBase = Uri.parse('https://downloads.example/releases');
      final archiveUri = hyfensReleaseAssetUri(
        releaseBase: releaseBase,
        version: version,
        asset: archiveName,
      );
      final checksumUri = hyfensReleaseAssetUri(
        releaseBase: releaseBase,
        version: version,
        asset: 'SHA256SUMS',
      );
      final target = File(p.join(fixture.path, 'install', 'bin', 'hyfens'));
      await target.parent.create(recursive: true);
      await target.writeAsBytes(<int>[9, 9, 9]);
      final transport = _FakeUpgradeTransport(
        responses: <Uri, List<int>>{
          latestUri: utf8.encode(
            '{"tag_name":"v$version","draft":false,"prerelease":false}',
          ),
          archiveUri: archiveBytes,
          checksumUri: utf8.encode(
            '${sha256.convert(archiveBytes)}  $archiveName\n',
          ),
        },
      );
      final service = HyfensUpgradeService(
        transport: transport,
        latestReleaseUri: latestUri,
        releaseBaseUri: releaseBase,
        currentVersion: () => '0.1.0',
        executablePath: target.path,
        platform: platform,
        architecture: architecture,
        temporaryParent: fixture,
      );

      final result = await service.upgrade();

      expect(result.updated, isTrue);
      expect(result.installedPath, target.path);
      expect(await target.readAsBytes(), <int>[1, 2, 3]);
    },
  );

  test('checksum failure leaves the installed binary untouched', () async {
    final fixture = await Directory.systemTemp.createTemp('hyfens-upgrade-');
    addTearDown(() => fixture.delete(recursive: true));
    final version = '0.1.1';
    final archiveName = hyfensReleaseArtifactName(
      version: version,
      platform: 'macos',
      architecture: 'arm64',
    );
    final rootName = p.withoutExtension(p.withoutExtension(archiveName));
    final releaseRoot = Directory(p.join(fixture.path, rootName));
    await Directory(p.join(releaseRoot.path, 'bin')).create(recursive: true);
    await File(p.join(releaseRoot.path, 'bin', 'hyfens'))
        .writeAsBytes(<int>[1, 2, 3]);
    final archive = File(p.join(fixture.path, archiveName));
    final archiveResult = await Process.run('tar', <String>[
      '-czf',
      archive.path,
      '-C',
      fixture.path,
      rootName,
    ]);
    expect(archiveResult.exitCode, 0);
    final archiveBytes = await archive.readAsBytes();
    final latestUri = Uri.parse('https://api.example/latest');
    final releaseBase = Uri.parse('https://downloads.example/releases');
    final archiveUri = hyfensReleaseAssetUri(
      releaseBase: releaseBase,
      version: version,
      asset: archiveName,
    );
    final checksumUri = hyfensReleaseAssetUri(
      releaseBase: releaseBase,
      version: version,
      asset: 'SHA256SUMS',
    );
    final target = File(p.join(fixture.path, 'install', 'bin', 'hyfens'));
    await target.parent.create(recursive: true);
    await target.writeAsBytes(<int>[9, 9, 9]);
    final transport = _FakeUpgradeTransport(
      responses: <Uri, List<int>>{
        latestUri: utf8.encode(
          '{"tag_name":"v$version","draft":false,"prerelease":false}',
        ),
        archiveUri: archiveBytes,
        checksumUri: utf8.encode(
          '${List.filled(64, '0').join()}  $archiveName\n',
        ),
      },
    );
    final service = HyfensUpgradeService(
      transport: transport,
      latestReleaseUri: latestUri,
      releaseBaseUri: releaseBase,
      currentVersion: () => '0.1.0',
      executablePath: target.path,
      platform: 'macos',
      architecture: 'arm64',
      temporaryParent: fixture,
    );

    await expectLater(
      service.upgrade,
      throwsA(
        isA<ToolFailure>().having(
          (failure) => failure.diagnostics.single.code,
          'diagnostic code',
          'U1004',
        ),
      ),
    );
    expect(await target.readAsBytes(), <int>[9, 9, 9]);
  });

  test(
    'source-tree execution is refused before downloading an archive',
    () async {
      final latestUri = Uri.parse('https://api.example/latest');
      final transport = _FakeUpgradeTransport(
        responses: <Uri, List<int>>{
          latestUri: utf8.encode(
            '{"tag_name":"v0.1.1","draft":false,"prerelease":false}',
          ),
        },
      );
      final service = HyfensUpgradeService(
        transport: transport,
        latestReleaseUri: latestUri,
        currentVersion: () => '0.1.0',
        executablePath: Platform.resolvedExecutable,
        platform: 'macos',
        architecture: 'arm64',
      );

      await expectLater(
        service.upgrade(),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'diagnostic code',
            'U1015',
          ),
        ),
      );
      expect(transport.requests, hasLength(1));
    },
  );
}

final class _FakeUpgradeTransport implements UpgradeTransport {
  _FakeUpgradeTransport({Map<Uri, List<int>>? responses})
    : _responses = responses ?? <Uri, List<int>>{};

  final Map<Uri, List<int>> _responses;
  final requests = <Uri>[];

  @override
  Future<List<int>> get(Uri uri) async {
    requests.add(uri);
    final response = _responses[uri];
    if (response == null) throw StateError('Unexpected upgrade request: $uri');
    return response;
  }

  @override
  void close() {}
}
