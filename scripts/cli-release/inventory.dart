import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'release_support.dart';

String get repositoryRoot =>
    File.fromUri(Platform.script).parent.parent.parent.absolute.path;

String? optionValue(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1) return null;
  if (index + 1 >= arguments.length || arguments[index + 1].startsWith('--')) {
    throw FormatException('$name requires a value');
  }
  return arguments[index + 1];
}

Future<String> fileSha256(File file) async {
  final output = AccumulatorSink<Digest>();
  final input = sha256.startChunkedConversion(output);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  return output.events.single.toString();
}

Future<void> writeInventory({
  required String version,
  required Directory artifactsDirectory,
  required File output,
}) async {
  validateReleaseVersion(repositoryRoot: repositoryRoot, version: version);
  final normalizedVersion = normalizeReleaseVersion(version);
  final files =
      artifactsDirectory
          .listSync(followLinks: false)
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.tar.gz') || file.path.endsWith('.zip'),
          )
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  if (files.isEmpty) {
    throw StateError(
      'No release archives found in ${artifactsDirectory.path}.',
    );
  }

  final records = <Map<String, Object>>[];
  final targets = <String>{};
  final checksumLines = <String>[];
  for (final file in files) {
    final descriptor = parseArtifactFileName(_fileName(file));
    if (descriptor.version != normalizedVersion) {
      throw StateError(
        'Archive ${descriptor.fileName} does not match release $normalizedVersion.',
      );
    }
    final digest = await fileSha256(file);
    records.add(descriptor.toJson(bytes: file.lengthSync(), sha256: digest));
    targets.add('${descriptor.platform}/${descriptor.architecture}');
    checksumLines.add('$digest  ${descriptor.fileName}');
  }
  if (!targets.containsAll(supportedReleaseTargets)) {
    throw StateError(
      'Release inventory must contain x64 and arm64 archives for macos, '
      'linux, and windows; found ${targets.toList()..sort()}.',
    );
  }

  final inventory = <String, Object>{
    'schemaVersion': 1,
    'releaseVersion': normalizedVersion,
    'canonicalExecutable': 'hyfens',
    'compatibilityExecutable': 'tool',
    'artifacts': records,
  };
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(inventory)}\n',
  );
  await File(p.join(artifactsDirectory.path, 'SHA256SUMS'))
      .writeAsString('${checksumLines.join('\n')}\n');
  stdout.writeln('Wrote ${output.path}');
}

String _fileName(File file) => file.uri.pathSegments.last;

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help')) {
    stdout.writeln('''
Create SHA256SUMS and a machine-readable inventory for release archives.

  --version VERSION       Release version.
  --artifacts-dir DIR     Directory containing release archives.
  --output FILE            Inventory JSON output path.
''');
    return;
  }
  try {
    final version = optionValue(arguments, '--version');
    final artifactsPath = optionValue(arguments, '--artifacts-dir');
    final outputPath = optionValue(arguments, '--output');
    if (version == null || artifactsPath == null || outputPath == null) {
      throw FormatException(
        '--version, --artifacts-dir, and --output are required',
      );
    }
    await writeInventory(
      version: version,
      artifactsDirectory: Directory(artifactsPath),
      output: File(outputPath),
    );
  } on Object catch (error) {
    stderr.writeln('cli-release inventory: $error');
    exitCode = 2;
  }
}
