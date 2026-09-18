import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'diagnostics.dart';
import 'toolchain.dart';

const hyfensReleaseRepository = 'hyfens-hq/hyfens';
final hyfensLatestReleaseUri = Uri.parse(
  'https://api.github.com/repos/$hyfensReleaseRepository/releases/latest',
);
final hyfensReleaseBaseUri = Uri.parse(
  'https://github.com/$hyfensReleaseRepository/releases/download',
);

final _releaseVersionPattern = RegExp(
  r'^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
);

/// Normalizes a release tag/version and rejects values that cannot name a
/// published Hyfens release.
String normalizeHyfensReleaseVersion(String value) {
  final version = value.trim().replaceFirst(RegExp(r'^v'), '');
  if (!_releaseVersionPattern.hasMatch(version)) {
    throw FormatException('Invalid Hyfens release version: $value');
  }
  return version;
}

/// Reads the stable tag from GitHub's compact `/releases/latest` JSON shape.
/// The parser intentionally works on decoded JSON instead of relying on line
/// breaks or field ordering.
String parseLatestHyfensReleaseVersion(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw const FormatException(
      'GitHub latest-release response is not an object',
    );
  }
  final json = <String, Object?>{
    for (final entry in decoded.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
  if (json['draft'] == true || json['prerelease'] == true) {
    throw const FormatException('GitHub latest release is not stable');
  }
  final tag = json['tag_name'];
  if (tag is! String || !tag.startsWith('v')) {
    throw const FormatException(
      'GitHub latest-release response has no v-prefixed tag_name',
    );
  }
  return normalizeHyfensReleaseVersion(tag);
}

/// Compares two normalized or v-prefixed semantic release versions.
int compareHyfensReleaseVersions(String left, String right) {
  final a = _ReleaseVersion.parse(left);
  final b = _ReleaseVersion.parse(right);
  for (final comparison in <int>[
    a.major.compareTo(b.major),
    a.minor.compareTo(b.minor),
    a.patch.compareTo(b.patch),
  ]) {
    if (comparison != 0) return comparison;
  }
  if (a.preRelease == null && b.preRelease == null) return 0;
  if (a.preRelease == null) return 1;
  if (b.preRelease == null) return -1;
  final leftParts = a.preRelease!.split('.');
  final rightParts = b.preRelease!.split('.');
  for (
    var index = 0;
    index < leftParts.length && index < rightParts.length;
    index++
  ) {
    final leftPart = leftParts[index];
    final rightPart = rightParts[index];
    if (leftPart == rightPart) continue;
    final leftNumber = int.tryParse(leftPart);
    final rightNumber = int.tryParse(rightPart);
    if (leftNumber != null && rightNumber != null) {
      return leftNumber.compareTo(rightNumber);
    }
    if (leftNumber != null) return -1;
    if (rightNumber != null) return 1;
    return leftPart.compareTo(rightPart);
  }
  return leftParts.length.compareTo(rightParts.length);
}

String hyfensReleaseArtifactName({
  required String version,
  required String platform,
  required String architecture,
}) {
  final normalizedVersion = normalizeHyfensReleaseVersion(version);
  final normalizedPlatform = switch (platform.trim().toLowerCase()) {
    'macos' => 'macos',
    'linux' => 'linux',
    'windows' => 'windows',
    _ => throw FormatException(
      'Unsupported Hyfens release platform: $platform',
    ),
  };
  final normalizedArchitecture = switch (architecture.trim().toLowerCase()) {
    'x64' || 'x86_64' || 'amd64' => 'x64',
    'arm64' || 'aarch64' => 'arm64',
    _ => throw FormatException(
      'Unsupported Hyfens release architecture: $architecture',
    ),
  };
  final extension = normalizedPlatform == 'windows' ? 'zip' : 'tar.gz';
  return 'hyfens-$normalizedVersion-$normalizedPlatform-'
      '$normalizedArchitecture.$extension';
}

Uri hyfensReleaseAssetUri({
  required Uri releaseBase,
  required String version,
  required String asset,
}) {
  final base = releaseBase.toString().endsWith('/')
      ? releaseBase.toString()
      : '${releaseBase.toString()}/';
  return Uri.parse('$base${Uri.encodeComponent('v$version')}/$asset');
}

abstract interface class UpgradeTransport {
  Future<List<int>> get(Uri uri);

  void close();
}

final class HttpUpgradeTransport implements UpgradeTransport {
  HttpUpgradeTransport({HttpClient? client})
    : _client = client ?? (HttpClient()..userAgent = 'hyfens-upgrade');

  final HttpClient _client;

  @override
  Future<List<int>> get(Uri uri) async {
    try {
      final request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _UpgradeTransportException(
          'HTTP ${response.statusCode} while downloading release metadata',
        );
      }
      return bytes;
    } on _UpgradeTransportException {
      rethrow;
    } on Object catch (error) {
      throw _UpgradeTransportException(error.toString());
    }
  }

  @override
  void close() => _client.close(force: true);
}

final class HyfensUpgradeResult {
  const HyfensUpgradeResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.updated,
    required this.checkOnly,
    this.installedPath,
  });

  final String currentVersion;
  final String latestVersion;
  final bool updated;
  final bool checkOnly;
  final String? installedPath;

  bool get updateAvailable =>
      compareHyfensReleaseVersions(currentVersion, latestVersion) < 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'result': checkOnly
        ? 'CHECKED'
        : updated
        ? 'UPDATED'
        : 'UP_TO_DATE',
    'current_version': currentVersion,
    'latest_version': latestVersion,
    'update_available': updateAvailable,
    'updated': updated,
    if (installedPath != null) 'installed_path': installedPath,
  };
}

/// Secure in-place updater for a compiled Hyfens release binary.
///
/// The updater uses only the fixed public Hyfens GitHub repository, validates
/// the archive checksum before extraction, rejects unsafe archive entries, and
/// never touches Hyfens profiles or project state. A source-tree `dart run`
/// invocation is rejected rather than attempting to replace the Dart SDK.
final class HyfensUpgradeService {
  HyfensUpgradeService({
    UpgradeTransport? transport,
    Uri? latestReleaseUri,
    Uri? releaseBaseUri,
    String Function()? currentVersion,
    String? executablePath,
    String? platform,
    String? architecture,
    Directory? temporaryParent,
  }) : _transport = transport ?? HttpUpgradeTransport(),
       _ownsTransport = transport == null,
       _latestReleaseUri = latestReleaseUri ?? hyfensLatestReleaseUri,
       _releaseBaseUri = releaseBaseUri ?? hyfensReleaseBaseUri,
       _currentVersion = currentVersion ?? (() => hyfensToolVersion),
       _executablePath = executablePath,
       _platform = platform,
       _architecture = architecture,
       _temporaryParent = temporaryParent;

  final UpgradeTransport _transport;
  final bool _ownsTransport;
  final Uri _latestReleaseUri;
  final Uri _releaseBaseUri;
  final String Function() _currentVersion;
  final String? _executablePath;
  final String? _platform;
  final String? _architecture;
  final Directory? _temporaryParent;

  Future<HyfensUpgradeResult> upgrade({
    String? requestedVersion,
    bool checkOnly = false,
  }) async {
    try {
      final currentVersion = normalizeHyfensReleaseVersion(_currentVersion());
      final latestVersion = requestedVersion == null
          ? parseLatestHyfensReleaseVersion(
              utf8.decode(await _transport.get(_latestReleaseUri)),
            )
          : normalizeHyfensReleaseVersion(requestedVersion);
      if (compareHyfensReleaseVersions(currentVersion, latestVersion) >= 0) {
        return HyfensUpgradeResult(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          updated: false,
          checkOnly: checkOnly,
        );
      }
      if (checkOnly) {
        return HyfensUpgradeResult(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          updated: false,
          checkOnly: true,
        );
      }

      final target = _resolveInstallationTarget();
      final platform = _platform ?? detectHyfensReleasePlatform();
      final architecture = _architecture ?? detectHyfensReleaseArchitecture();
      final archive = hyfensReleaseArtifactName(
        version: latestVersion,
        platform: platform,
        architecture: architecture,
      );
      final temporary = await (_temporaryParent ?? Directory.systemTemp)
          .createTemp('hyfens-upgrade-');
      try {
        final archiveFile = File(p.join(temporary.path, archive));
        await archiveFile.writeAsBytes(
          await _transport.get(
            hyfensReleaseAssetUri(
              releaseBase: _releaseBaseUri,
              version: latestVersion,
              asset: archive,
            ),
          ),
        );
        final checksums = utf8.decode(
          await _transport.get(
            hyfensReleaseAssetUri(
              releaseBase: _releaseBaseUri,
              version: latestVersion,
              asset: 'SHA256SUMS',
            ),
          ),
        );
        _verifyChecksum(archiveFile, archive, checksums);
        final extractedRoot = await _extractRelease(
          archiveFile,
          temporary,
          version: latestVersion,
          platform: platform,
          architecture: architecture,
        );
        final installedPath = await _activate(
          target,
          extractedRoot,
          latestVersion,
          platform: platform,
          architecture: architecture,
        );
        return HyfensUpgradeResult(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          updated: true,
          checkOnly: false,
          installedPath: installedPath,
        );
      } finally {
        await temporary.delete(recursive: true);
      }
    } on ToolFailure {
      rethrow;
    } on FormatException catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1001',
        summary: 'Hyfens upgrade metadata is invalid',
        detail: error.message,
        action: 'Retry after checking the latest public Hyfens release.',
      );
    } on Object catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1002',
        summary: 'Hyfens upgrade failed',
        detail: error.toString(),
        action: 'Use the documented installer or direct release archive.',
      );
    } finally {
      if (_ownsTransport) _transport.close();
    }
  }

  void _verifyChecksum(File archive, String archiveName, String checksums) {
    String? expected;
    for (final line in checksums.split('\n')) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 2) continue;
      final name = fields[1];
      if (name != archiveName && name != '*$archiveName') continue;
      if (expected != null) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'U1003',
          summary: 'Release checksum is ambiguous',
          detail: archiveName,
        );
      }
      expected = fields[0];
    }
    if (expected == null || !RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(expected)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1003',
        summary: 'Release checksum is missing or invalid',
        detail: archiveName,
      );
    }
    final actual = sha256.convert(archive.readAsBytesSync()).toString();
    if (actual.toLowerCase() != expected.toLowerCase()) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1004',
        summary: 'Release checksum verification failed',
        detail: archiveName,
        action: 'The downloaded archive was not installed.',
      );
    }
  }

  Future<Directory> _extractRelease(
    File archive,
    Directory temporary, {
    required String version,
    required String platform,
    required String architecture,
  }) async {
    final rootName = p.withoutExtension(
      p.withoutExtension(archive.uri.pathSegments.last),
    );
    final extraction = Directory(p.join(temporary.path, 'extracted'));
    await extraction.create(recursive: true);
    final entries = await _archiveEntries(archive);
    _validateArchiveEntries(entries, rootName);
    await _extractArchive(archive, extraction);
    final root = Directory(p.join(extraction.path, rootName));
    if (!root.existsSync() || Link(root.path).existsSync()) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1005',
        summary: 'Release archive root is missing',
        detail: rootName,
      );
    }
    final executableName = platform == 'windows' ? 'hyfens.exe' : 'hyfens';
    final executable = File(p.join(root.path, 'bin', executableName));
    if (!executable.existsSync() || Link(executable.path).existsSync()) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1006',
        summary: 'Release archive has no safe Hyfens executable',
        detail: 'bin/$executableName for $version/$architecture',
      );
    }
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'U1007',
          summary: 'Release archive contains a symbolic link',
          detail: p.relative(entity.path, from: root.path),
        );
      }
    }
    return root;
  }

  Future<List<String>> _archiveEntries(File archive) async {
    final isZip = archive.path.toLowerCase().endsWith('.zip');
    final arguments = isZip
        ? <String>['-tf', archive.path]
        : <String>['-tzf', archive.path];
    ProcessResult result;
    try {
      result = await Process.run('tar', arguments);
    } on ProcessException catch (error) {
      if (isZip && Platform.isWindows) {
        return _powershellZipEntries(archive);
      }
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1008',
        summary: 'Archive extractor is unavailable',
        detail: error.message,
        action: 'Install tar, then retry hyfens upgrade.',
      );
    }
    if (result.exitCode != 0) {
      if (isZip && Platform.isWindows) {
        return _powershellZipEntries(archive);
      }
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1009',
        summary: 'Release archive could not be inspected',
        detail: result.stderr.toString().trim(),
      );
    }
    if (isZip && Platform.isWindows) {
      final types = await Process.run('tar', <String>['-tvf', archive.path]);
      if (types.exitCode != 0) return _powershellZipEntries(archive);
      _validateArchiveEntryTypes(types.stdout.toString());
    } else {
      final types = await Process.run(
        'tar',
        isZip
            ? <String>['-tvf', archive.path]
            : <String>['-tvzf', archive.path],
      );
      if (types.exitCode != 0) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'U1010',
          summary: 'Release archive entries could not be inspected',
          detail: types.stderr.toString().trim(),
        );
      }
      _validateArchiveEntryTypes(types.stdout.toString());
    }
    return result.stdout
        .toString()
        .split('\n')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _powershellZipEntries(File archive) {
    final environment = <String, String>{
      ...Platform.environment,
      'HYFENS_UPGRADE_ARCHIVE': archive.path,
    };
    final result = Process.runSync('powershell.exe', <String>[
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'''
$zip = [System.IO.Compression.ZipFile]::OpenRead($env:HYFENS_UPGRADE_ARCHIVE)
try {
  foreach ($entry in $zip.Entries) {
    if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { exit 42 }
    [Console]::WriteLine($entry.FullName)
  }
} finally {
  $zip.Dispose()
}
''',
    ], environment: environment);
    if (result.exitCode == 42) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1007',
        summary: 'Release archive contains a symbolic link',
        detail: archive.path,
      );
    }
    if (result.exitCode != 0) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1011',
        summary: 'Windows release archive could not be inspected',
        detail: result.stderr.toString().trim(),
      );
    }
    return result.stdout
        .toString()
        .split('\n')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  void _validateArchiveEntries(List<String> entries, String rootName) {
    if (entries.isEmpty) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1012',
        summary: 'Release archive is empty',
        detail: rootName,
      );
    }
    for (final raw in entries) {
      var entry = raw;
      while (entry.endsWith('/')) entry = entry.substring(0, entry.length - 1);
      if (entry.isEmpty || entry == rootName) continue;
      final parts = entry.split('/');
      if (!entry.startsWith('$rootName/') ||
          entry.startsWith('/') ||
          entry.contains('\\') ||
          parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
          entry.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'U1013',
          summary: 'Release archive contains an unsafe path',
          detail: raw,
        );
      }
    }
  }

  void _validateArchiveEntryTypes(String listing) {
    for (final line in listing.split('\n')) {
      if (line.isEmpty) continue;
      final type = line[0];
      if (type != '-' && type != 'd') {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'U1007',
          summary: 'Release archive contains a link or special file',
          detail: line,
        );
      }
    }
  }

  Future<void> _extractArchive(File archive, Directory destination) async {
    final isZip = archive.path.toLowerCase().endsWith('.zip');
    final arguments = isZip
        ? <String>['-xf', archive.path, '-C', destination.path]
        : <String>['-xzf', archive.path, '-C', destination.path];
    try {
      final result = await Process.run('tar', arguments);
      if (result.exitCode == 0) return;
      if (!(isZip && Platform.isWindows)) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'U1014',
          summary: 'Release archive could not be extracted',
          detail: result.stderr.toString().trim(),
        );
      }
    } on ProcessException catch (error) {
      if (!(isZip && Platform.isWindows)) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'U1008',
          summary: 'Archive extractor is unavailable',
          detail: error.message,
          action: 'Install tar, then retry hyfens upgrade.',
        );
      }
    }
    final environment = <String, String>{
      ...Platform.environment,
      'HYFENS_UPGRADE_ARCHIVE': archive.path,
      'HYFENS_UPGRADE_DESTINATION': destination.path,
    };
    final result = await Process.run('powershell.exe', <String>[
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'Expand-Archive -LiteralPath $env:HYFENS_UPGRADE_ARCHIVE -DestinationPath $env:HYFENS_UPGRADE_DESTINATION -Force',
    ], environment: environment);
    if (result.exitCode != 0) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1014',
        summary: 'Windows release archive could not be extracted',
        detail: result.stderr.toString().trim(),
      );
    }
  }

  _InstallationTarget _resolveInstallationTarget() {
    final path = _executablePath ?? Platform.resolvedExecutable;
    final executable = File(p.absolute(path));
    final name = p.basename(executable.path).toLowerCase();
    if (name == 'dart' || name == 'dart.exe' || name == 'flutter') {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'U1015',
        summary: 'Upgrade requires an installed Hyfens binary',
        detail: 'The current process is running from a Dart/Flutter source command.',
        action:
            'Install Hyfens from a release archive, then run hyfens upgrade.',
      );
    }
    if (name != 'hyfens' && name != 'hyfens.exe') {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'U1015',
        summary: 'The current executable is not Hyfens',
        detail: executable.path,
        action: 'Run upgrade from the installed hyfens executable.',
      );
    }
    if (!executable.existsSync()) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1016',
        summary: 'The current Hyfens executable is missing',
        detail: executable.path,
      );
    }
    final type = FileSystemEntity.typeSync(executable.path, followLinks: false);
    final resolved = type == FileSystemEntityType.link
        ? File(executable.resolveSymbolicLinksSync())
        : executable;
    final managed = _managedInstallation(resolved);
    if (managed != null) return _InstallationTarget.managed(managed);
    if (type == FileSystemEntityType.link) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1017',
        summary: 'The Hyfens executable is an unmanaged symbolic link',
        detail: executable.path,
        action:
            'Run the public installer or use an absolute Hyfens binary path.',
      );
    }
    return _InstallationTarget.direct(executable);
  }

  _ManagedInstallation? _managedInstallation(File executable) {
    final bin = executable.parent;
    final root = bin.parent;
    final opt = root.parent;
    if (p.basename(bin.path) != 'bin' || p.basename(opt.path) != 'opt') {
      return null;
    }
    if (!p.basename(root.path).startsWith('hyfens-')) return null;
    final prefix = opt.parent;
    final executableName = p.basename(executable.path);
    return _ManagedInstallation(
      prefix: prefix,
      launcher: File(p.join(prefix.path, 'bin', executableName)),
      toolLauncher: File(
        p.join(prefix.path, 'bin', Platform.isWindows ? 'tool.exe' : 'tool'),
      ),
    );
  }

  Future<String> _activate(
    _InstallationTarget target,
    Directory extractedRoot,
    String version, {
    required String platform,
    required String architecture,
  }) async {
    final executableName = platform == 'windows' ? 'hyfens.exe' : 'hyfens';
    final source = File(p.join(extractedRoot.path, 'bin', executableName));
    final managed = target.managedInstallation;
    if (managed != null) {
      return _activateManaged(managed, extractedRoot, version);
    }
    return _activateDirect(target.executable!, source);
  }

  Future<String> _activateManaged(
    _ManagedInstallation installation,
    Directory extractedRoot,
    String version,
  ) async {
    final opt = Directory(p.join(installation.prefix.path, 'opt'));
    await opt.create(recursive: true);
    final installRoot = Directory(p.join(opt.path, 'hyfens-$version'));
    if (installRoot.existsSync()) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1018',
        summary: 'The target Hyfens release directory already exists',
        detail: installRoot.path,
        action: 'Remove the incomplete directory after review, then retry.',
      );
    }
    final staging = Directory(
      p.join(opt.path, '.hyfens-upgrade-${pid.toString()}'),
    );
    if (staging.existsSync()) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1019',
        summary: 'A previous Hyfens upgrade is still staged',
        detail: staging.path,
      );
    }
    try {
      final stagedRoot = Directory(p.join(staging.path, 'release'));
      await _copyDirectory(extractedRoot, stagedRoot);
      await stagedRoot.rename(installRoot.path);
    } catch (error) {
      if (staging.existsSync()) await staging.delete(recursive: true);
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1020',
        summary: 'The verified Hyfens release could not be staged',
        detail: error.toString(),
      );
    } finally {
      if (staging.existsSync()) await staging.delete(recursive: true);
    }
    final linkTarget = '../opt/hyfens-$version/bin/hyfens';
    await _activateLink(installation.launcher, linkTarget);
    final toolSource = File(
      p.join(
        extractedRoot.path,
        'bin',
        Platform.isWindows ? 'tool.exe' : 'tool',
      ),
    );
    if (toolSource.existsSync() && installation.toolLauncher.existsSync()) {
      await _activateLink(
        installation.toolLauncher,
        '../opt/hyfens-$version/bin/${p.basename(toolSource.path)}',
      );
    }
    return installation.launcher.path;
  }

  Future<String> _activateDirect(File destination, File source) async {
    if (FileSystemEntity.typeSync(destination.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1021',
        summary: 'The current Hyfens executable is not a regular file',
        detail: destination.path,
      );
    }
    final staged = File('${destination.path}.hyfens-upgrade-$pid');
    if (staged.existsSync()) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1022',
        summary: 'A previous direct Hyfens upgrade is still staged',
        detail: staged.path,
      );
    }
    await source.copy(staged.path);
    if (!Platform.isWindows) await _makeExecutable(staged);
    if (Platform.isWindows) {
      await _scheduleWindowsReplacement(destination, staged);
      return destination.path;
    }
    final backup = File('${destination.path}.hyfens-previous-$pid');
    try {
      await destination.rename(backup.path);
      await staged.rename(destination.path);
      await backup.delete();
    } catch (error) {
      if (!destination.existsSync() && backup.existsSync()) {
        await backup.rename(destination.path);
      }
      if (staged.existsSync()) await staged.delete();
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1023',
        summary: 'The upgraded Hyfens executable could not be activated',
        detail: error.toString(),
      );
    }
    return destination.path;
  }

  Future<void> _activateLink(File destination, String target) async {
    final directory = destination.parent;
    await directory.create(recursive: true);
    final temporary = Link(
      p.join(directory.path, '.hyfens-${p.basename(destination.path)}-$pid'),
    );
    if (temporary.existsSync()) await temporary.delete();
    await temporary.create(target);
    final backup = Link('${destination.path}.hyfens-previous-$pid');
    final destinationType = FileSystemEntity.typeSync(
      destination.path,
      followLinks: false,
    );
    try {
      if (destinationType != FileSystemEntityType.notFound) {
        if (destinationType != FileSystemEntityType.link) {
          throw StateError('existing launcher is not a symbolic link');
        }
        if (backup.existsSync()) await backup.delete();
        await destination.rename(backup.path);
      }
      await temporary.rename(destination.path);
      if (backup.existsSync()) await backup.delete();
    } catch (error) {
      if (!destination.existsSync() && backup.existsSync()) {
        await backup.rename(destination.path);
      }
      if (temporary.existsSync()) await temporary.delete();
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1024',
        summary: 'The Hyfens launcher could not be activated',
        detail: error.toString(),
      );
    }
  }

  Future<void> _scheduleWindowsReplacement(
    File destination,
    File staged,
  ) async {
    final script = File('${destination.path}.hyfens-upgrade.ps1');
    if (script.existsSync()) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1025',
        summary: 'A previous Windows Hyfens upgrade is still pending',
        detail: script.path,
      );
    }
    await script.writeAsString(r'''
param([int]$ParentPid, [string]$Staged, [string]$Destination, [string]$Script)
while (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 100
}
Move-Item -LiteralPath $Staged -Destination $Destination -Force
Remove-Item -LiteralPath $Script -Force
''');
    try {
      await Process.start('powershell.exe', <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        '-ParentPid',
        '$pid',
        '-Staged',
        staged.path,
        '-Destination',
        destination.path,
        '-Script',
        script.path,
      ], mode: ProcessStartMode.detached);
    } on Object catch (error) {
      if (script.existsSync()) await script.delete();
      if (staged.existsSync()) await staged.delete();
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1026',
        summary: 'Windows Hyfens replacement could not be scheduled',
        detail: error.toString(),
      );
    }
  }

  Future<void> _makeExecutable(File file) async {
    final result = await Process.run('chmod', <String>['755', file.path]);
    if (result.exitCode != 0) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'U1027',
        summary: 'The upgraded Hyfens executable could not be made executable',
        detail: result.stderr.toString().trim(),
      );
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final target = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      } else {
        throw StateError('Release contains an unsupported filesystem entry.');
      }
    }
  }
}

String detectHyfensReleasePlatform() {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  if (Platform.isWindows) return 'windows';
  throw FormatException('Unsupported operating system for Hyfens upgrade');
}

String detectHyfensReleaseArchitecture() {
  final raw = Platform.isWindows
      ? Platform.environment['PROCESSOR_ARCHITEW6432'] ??
            Platform.environment['PROCESSOR_ARCHITECTURE'] ??
            ''
      : _unameMachine();
  return switch (raw.trim().toLowerCase()) {
    'x86_64' || 'amd64' || 'x64' => 'x64',
    'arm64' || 'aarch64' => 'arm64',
    _ => throw FormatException('Unsupported machine architecture: $raw'),
  };
}

String _unameMachine() {
  final result = Process.runSync('uname', <String>['-m']);
  if (result.exitCode != 0) {
    throw FormatException('Unable to determine machine architecture');
  }
  return result.stdout.toString();
}

final class _ReleaseVersion {
  const _ReleaseVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease,
  });

  final int major;
  final int minor;
  final int patch;
  final String? preRelease;

  static _ReleaseVersion parse(String value) {
    final normalized = normalizeHyfensReleaseVersion(value);
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?')
        .firstMatch(normalized)!;
    return _ReleaseVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      preRelease: match.group(4),
    );
  }
}

final class _UpgradeTransportException implements Exception {
  const _UpgradeTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _ManagedInstallation {
  const _ManagedInstallation({
    required this.prefix,
    required this.launcher,
    required this.toolLauncher,
  });

  final Directory prefix;
  final File launcher;
  final File toolLauncher;
}

final class _InstallationTarget {
  const _InstallationTarget._({this.executable, this.managedInstallation});

  const _InstallationTarget.direct(File executable)
    : this._(executable: executable);

  const _InstallationTarget.managed(_ManagedInstallation installation)
    : this._(managedInstallation: installation);

  final File? executable;
  final _ManagedInstallation? managedInstallation;
}
