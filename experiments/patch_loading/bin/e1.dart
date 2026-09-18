import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';

final E0AsyncCapabilityDescriptor _e1HostImmediate =
    E0AsyncCapabilityDescriptor(
      id: 'hyfens.e1.host.immediate',
      sourceName: 'hostImmediate',
      version: 1,
      arguments: <E0ValueSchema>[E0ValueSchema.integer],
      result: E0ValueSchema.integer,
    );

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    _usage();
    return;
  }
  if (arguments.first == 'keygen' && arguments.length == 3) {
    final privateFile = File(arguments[1]);
    final publicFile = File(arguments[2]);
    if (_canonicalPath(privateFile) == _canonicalPath(publicFile)) {
      stderr.writeln('private and public key paths must be distinct');
      exitCode = 64;
      return;
    }
    if (_pathExists(privateFile.path) || _pathExists(publicFile.path)) {
      stderr.writeln('refusing to overwrite an existing key file');
      exitCode = 73;
      return;
    }
    final privateParent = privateFile.absolute.parent;
    final publicParent = publicFile.absolute.parent;
    if (!privateParent.existsSync() || !publicParent.existsSync()) {
      stderr.writeln('key output parent directory does not exist');
      exitCode = 72;
      return;
    }
    final secureDirectory = await privateParent.createTemp('.e1-keygen-');
    File? publicTemporary;
    final algorithm = DartEd25519();
    final keyPair = await algorithm.newKeyPair();
    try {
      await _chmodChecked(secureDirectory.path, '700');
      final privateBytes = await keyPair.extractPrivateKeyBytes();
      final publicKey = await keyPair.extractPublicKey();
      final privateTemporary = File('${secureDirectory.path}/seed.hex');
      await privateTemporary.writeAsString(
        '${_hex(privateBytes)}\n',
        flush: true,
      );
      await _chmodChecked(privateTemporary.path, '600');
      final publicCandidate = File('${publicFile.path}.tmp');
      if (_pathExists(publicCandidate.path)) {
        throw const FileSystemException('public-key temporary path exists');
      }
      publicTemporary = publicCandidate;
      await publicTemporary.writeAsString(
        '${_hex(publicKey.bytes)}\n',
        flush: true,
      );
      if (_pathExists(privateFile.path) || _pathExists(publicFile.path)) {
        throw const FileSystemException(
          'key destination appeared during creation',
        );
      }
      await publicTemporary.rename(publicFile.path);
      publicTemporary = null;
      await privateTemporary.rename(privateFile.path);
      stdout.writeln('publicKey=${_hex(publicKey.bytes)}');
    } finally {
      keyPair.destroy();
      if (publicTemporary != null && await publicTemporary.exists()) {
        await publicTemporary.delete();
      }
      if (await secureDirectory.exists()) {
        await secureDirectory.delete(recursive: true);
      }
    }
    return;
  }
  if (arguments.first == 'sign' && arguments.length == 5) {
    final patchFile = File(arguments[1]);
    final seedFile = File(arguments[2]);
    final output = File(arguments[4]);
    final paths = <String>{
      _canonicalPath(patchFile),
      _canonicalPath(seedFile),
      _canonicalPath(output),
    };
    if (paths.length != 3) {
      stderr.writeln('patch, private seed, and output paths must be distinct');
      exitCode = 64;
      return;
    }
    if (_pathExists(output.path)) {
      stderr.writeln('refusing to overwrite signed output');
      exitCode = 73;
      return;
    }
    final length = await patchFile.length();
    if (length > E0PatchContainer.maxBytes) {
      stderr.writeln('patch exceeds ${E0PatchContainer.maxBytes} byte limit');
      exitCode = 65;
      return;
    }
    final temporary = File('${output.path}.tmp');
    if (_pathExists(temporary.path)) {
      stderr.writeln('signed-output temporary path exists');
      exitCode = 73;
      return;
    }
    try {
      final patch = await patchFile.readAsBytes();
      final seed = _unhex((await seedFile.readAsString()).trim());
      final signed = await E1SignedPatchEnvelope.sign(
        patchBytes: patch,
        keyId: arguments[3],
        privateKeySeed: seed,
      );
      await temporary.writeAsBytes(signed, flush: true);
      if (_pathExists(output.path)) {
        throw const FileSystemException(
          'signed output appeared during creation',
        );
      }
      await temporary.rename(output.path);
      stdout.writeln(
        'signedEnvelopeBytes=${signed.length} patchBytes=${patch.length} '
        'keyId=${arguments[3]}',
      );
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return;
  }
  if ((arguments.first == 'overlay' && arguments.length != 3) ||
      (arguments.first == 'compile-patch' &&
          (arguments.length < 3 || arguments.length > 6)) ||
      (arguments.first != 'overlay' && arguments.first != 'compile-patch')) {
    _usage();
    return;
  }
  if (arguments.first == 'overlay') {
    final result = E0OverlayBuilder(E0SourceTransformer()).build(
      input: File(arguments[1]),
      outputDirectory: Directory(arguments[2]),
      packageName: 'conformance',
      logicalLibraryPath: 'lib/main.dart',
      appId: 'dev.hyfens.conformance',
      releaseId: 'android-e1-release-1',
      buildFingerprint: 'conformance-build-1',
      capabilities: <E0AsyncCapabilityDescriptor>[_e1HostImmediate],
    );
    final input = File(arguments[1]);
    final bootstrap = File('${input.parent.path}/patch_bootstrap.dart');
    if (!bootstrap.existsSync()) {
      throw StateError('fixture bootstrap not found beside ${input.path}');
    }
    bootstrap.copySync('${arguments[2]}/patch_bootstrap.dart');
    final function = result.manifest.functions.singleWhere(
      (item) => item.name == 'calculatePrice',
    );
    if (function.id !=
        'sha256:d5a3b64831b9a76d7d43cc8645ce79415061f59039f12963a272c51a005fe361') {
      throw StateError('fixture bootstrap function ID drifted: ${function.id}');
    }
    stdout.writeln(
      'instrumented=${result.manifest.functions.length} '
      'excluded=${result.exclusions.length} functionId=${function.id}',
    );
    return;
  }
  final overlay = Directory(arguments[2]);
  final manifest = E0ReleaseManifest.decode(
    File('${overlay.path}/manifest.json').readAsStringSync(),
  );
  final bytes = E0PatchCompiler().compile(
    source: File(arguments[1]).readAsStringSync(),
    manifest: manifest,
    functionName: arguments.length >= 4 ? arguments[3] : 'calculatePrice',
    className: arguments.length >= 5 && arguments[4] != '-'
        ? arguments[4]
        : null,
    patchSequence: arguments.length == 6 ? int.parse(arguments[5]) : 1,
  );
  File('${overlay.path}/patch.e0.json').writeAsBytesSync(bytes);
  stdout.writeln('patchBytes=${bytes.length}');
}

void _usage() {
  stderr.writeln(
    'usage: dart run bin/e1.dart overlay INPUT OUTPUT_DIR\n'
    '   or: dart run bin/e1.dart compile-patch SOURCE OVERLAY_DIR '
    '[FUNCTION [CLASS [SEQUENCE]]]\n'
    '   or: dart run bin/e1.dart keygen PRIVATE_SEED_FILE PUBLIC_KEY_FILE\n'
    '   or: dart run bin/e1.dart sign PATCH PRIVATE_SEED_FILE KEY_ID OUTPUT',
  );
  exitCode = 64;
}

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String value) {
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
    throw const FormatException('private seed must be exactly 32 hex bytes');
  }
  return <int>[
    for (var offset = 0; offset < value.length; offset += 2)
      int.parse(value.substring(offset, offset + 2), radix: 16),
  ];
}

bool _pathExists(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) !=
    FileSystemEntityType.notFound;

String _canonicalPath(File file) {
  final absolute = file.absolute;
  if (_pathExists(absolute.path)) return absolute.resolveSymbolicLinksSync();
  final parent = absolute.parent.resolveSymbolicLinksSync();
  return '$parent${Platform.pathSeparator}${absolute.uri.pathSegments.last}';
}

Future<void> _chmodChecked(String path, String mode) async {
  if (Platform.isWindows) return;
  final result = await Process.run('chmod', <String>[mode, path]);
  if (result.exitCode != 0) {
    throw FileSystemException('chmod $mode failed: ${result.stderr}', path);
  }
}
