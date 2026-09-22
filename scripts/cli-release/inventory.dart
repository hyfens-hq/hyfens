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
  final expectedNames = <String>{
    for (final target in supportedReleaseTargets)
      artifactFileName(
        version: normalizedVersion,
        platform: target.split('/')[0],
        architecture: target.split('/')[1],
      ),
  };
  final entries = artifactsDirectory.listSync(followLinks: false);
  // The publisher uploads this whole directory. Do not silently ignore extra
  // files, directories, aliases, or symlinks outside the checksummed inventory.
  if (entries.length != expectedNames.length ||
      entries.any(
        (entry) =>
            entry is! File || !expectedNames.contains(p.basename(entry.path)),
      )) {
    throw StateError(
      'Release directory must contain exactly the six canonical archives; '
      'no extra files, directories, or links are allowed.',
    );
  }
  final files = entries.cast<File>()
    ..sort((left, right) => left.path.compareTo(right.path));

  final records = <Map<String, Object>>[];
  final checksumLines = <String>[];
  for (final file in files) {
    final descriptor = parseArtifactFileName(_fileName(file));
    final bytes = file.lengthSync();
    if (bytes == 0) {
      throw StateError('Release archive ${descriptor.fileName} is empty.');
    }
    final digest = await fileSha256(file);
    records.add(descriptor.toJson(bytes: bytes, sha256: digest));
    checksumLines.add('$digest  ${descriptor.fileName}');
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
  // Include metadata integrity too. The workflow attests SHA256SUMS itself.
  final inventoryPath = p.relative(output.path, from: artifactsDirectory.path);
  checksumLines.add('${await fileSha256(output)}  $inventoryPath');
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
