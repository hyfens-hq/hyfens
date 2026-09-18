import 'dart:io';

import 'package:crypto/crypto.dart';

final _releaseVersionPattern = RegExp(
  r'^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
);
final _artifactNamePattern = RegExp(
  r'^hyfens-(.+)-(macos|linux|windows)-([a-z0-9]+)\.(tar\.gz|zip)$',
);

const supportedReleasePlatforms = <String>{'macos', 'linux', 'windows'};
const supportedReleaseTargets = <String>{
  'macos/arm64',
  'macos/x64',
  'linux/arm64',
  'linux/x64',
  'windows/arm64',
  'windows/x64',
};

String normalizeReleaseVersion(String value) {
  final version = value.trim().replaceFirst(RegExp(r'^v'), '');
  if (!_releaseVersionPattern.hasMatch(version)) {
    throw FormatException('Release version must be a semantic version: $value');
  }
  return version;
}

String cliPackageVersion(String repositoryRoot) {
  final pubspec = File('$repositoryRoot/cli/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw StateError('CLI pubspec.yaml is missing: ${pubspec.path}');
  }
  final match = RegExp(
    r'^version:\s*([^\s#]+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) {
    throw StateError('CLI pubspec.yaml does not define a version.');
  }
  return normalizeReleaseVersion(match.group(1)!);
}

void validateReleaseVersion({
  required String repositoryRoot,
  required String version,
}) {
  final normalized = normalizeReleaseVersion(version);
  final packageVersion = cliPackageVersion(repositoryRoot);
  if (normalized != packageVersion) {
    throw StateError(
      'Release tag $normalized does not match cli/pubspec.yaml version '
      '$packageVersion.',
    );
  }
}

String normalizePlatform(String value) {
  final platform = value.trim().toLowerCase();
  if (!supportedReleasePlatforms.contains(platform)) {
    throw FormatException('Unsupported release platform: $value');
  }
  return platform;
}

String normalizeArchitecture(String value) {
  final architecture = value.trim().toLowerCase();
  switch (architecture) {
    case 'x86_64':
    case 'amd64':
    case 'x64':
      return 'x64';
    case 'aarch64':
    case 'arm64':
      return 'arm64';
    case 'armv7':
    case 'armv7l':
    case 'arm':
      return 'arm';
    default:
      throw FormatException('Unsupported release architecture: $value');
  }
}

String artifactFileName({
  required String version,
  required String platform,
  required String architecture,
}) {
  final normalizedVersion = normalizeReleaseVersion(version);
  final normalizedPlatform = normalizePlatform(platform);
  final normalizedArchitecture = normalizeArchitecture(architecture);
  final extension = normalizedPlatform == 'windows' ? 'zip' : 'tar.gz';
  return 'hyfens-$normalizedVersion-$normalizedPlatform-'
      '$normalizedArchitecture.$extension';
}

final class ReleaseArtifactName {
  const ReleaseArtifactName({
    required this.fileName,
    required this.version,
    required this.platform,
    required this.architecture,
    required this.format,
  });

  final String fileName;
  final String version;
  final String platform;
  final String architecture;
  final String format;

  Map<String, Object> toJson({required int bytes, required String sha256}) =>
      <String, Object>{
        'name': fileName,
        'platform': platform,
        'architecture': architecture,
        'format': format,
        'bytes': bytes,
        'sha256': sha256,
      };
}

ReleaseArtifactName parseArtifactFileName(String fileName) {
  final match = _artifactNamePattern.firstMatch(fileName);
  if (match == null) {
    throw FormatException('Invalid Hyfens release artifact name: $fileName');
  }
  final version = normalizeReleaseVersion(match.group(1)!);
  final platform = normalizePlatform(match.group(2)!);
  final architecture = normalizeArchitecture(match.group(3)!);
  final format = match.group(4)!;
  final expectedFormat = platform == 'windows' ? 'zip' : 'tar.gz';
  if (format != expectedFormat) {
    throw FormatException(
      'Artifact format $format is not valid for $platform: $fileName',
    );
  }
  return ReleaseArtifactName(
    fileName: fileName,
    version: version,
    platform: platform,
    architecture: architecture,
    format: format,
  );
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
