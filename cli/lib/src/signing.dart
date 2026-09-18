import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'canonical.dart';
import 'diagnostics.dart';

final class SigningKey {
  SigningKey({
    required this.keyId,
    required List<int> seed,
    required List<int> publicKey,
  }) : seed = List.unmodifiable(seed),
       publicKey = List.unmodifiable(publicKey);

  final String keyId;
  final List<int> seed;
  final List<int> publicKey;

  Future<List<int>> sign(List<int> message) async {
    final algorithm = DartEd25519();
    final keyPair = await algorithm.newKeyPairFromSeed(seed);
    try {
      final signature = await algorithm.sign(message, keyPair: keyPair);
      return List.unmodifiable(signature.bytes);
    } finally {
      keyPair.destroy();
    }
  }

  Future<bool> verify(List<int> message, List<int> signature) async {
    final algorithm = DartEd25519();
    if (publicKey.isNotEmpty) {
      return algorithm.verify(
        message,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    }
    final keyPair = await algorithm.newKeyPairFromSeed(seed);
    try {
      final key = await keyPair.extractPublicKey();
      return await algorithm.verify(
        message,
        signature: Signature(signature, publicKey: key),
      );
    } finally {
      keyPair.destroy();
    }
  }
}

final class PublicSigningKey {
  const PublicSigningKey({required this.keyId, required this.publicKey});

  final String keyId;
  final List<int> publicKey;

  Future<bool> verify(List<int> message, List<int> signature) async {
    final algorithm = DartEd25519();
    return algorithm.verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  }
}

final class KeyStore {
  const KeyStore();

  Future<SigningKey> generate({
    required File privateFile,
    required File publicFile,
    Random? random,
  }) async {
    if (_samePath(privateFile, publicFile)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.refused,
        code: 'S4003',
        summary: 'Private and public key paths must be distinct',
        detail: privateFile.path,
      );
    }
    if (privateFile.existsSync() || publicFile.existsSync()) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.refused,
        code: 'S4004',
        summary: 'Refusing to overwrite existing signing material',
        detail: '${privateFile.path} or ${publicFile.path} already exists.',
        action: 'Choose a new key path or remove the files intentionally.',
      );
    }
    final source = random ?? Random.secure();
    final seed = List<int>.generate(32, (_) => source.nextInt(256));
    final algorithm = DartEd25519();
    final keyPair = await algorithm.newKeyPairFromSeed(seed);
    try {
      final publicKey = await keyPair.extractPublicKey();
      final keyId =
          'ed25519-${sha256.convert(publicKey.bytes).toString().substring(0, 16)}';
      await writeAtomicText(
        privateFile,
        jsonEncode(<String, Object>{
              'algorithm': 'ed25519',
              'keyId': keyId,
              'seed': base64.encode(seed),
            }) +
            '\n',
      );
      await writeAtomicText(
        publicFile,
        jsonEncode(<String, Object>{
              'algorithm': 'ed25519',
              'keyId': keyId,
              'publicKey': base64.encode(publicKey.bytes),
            }) +
            '\n',
      );
      await _restrictPrivateFile(privateFile);
      return SigningKey(keyId: keyId, seed: seed, publicKey: publicKey.bytes);
    } finally {
      keyPair.destroy();
    }
  }

  SigningKey readPrivate(File file) {
    final map = _readKey(file, private: true);
    return SigningKey(
      keyId: map['keyId']! as String,
      seed: map['seed']! as List<int>,
      publicKey: const <int>[],
    );
  }

  PublicSigningKey readPublic(File file) {
    final map = _readKey(file, private: false);
    return PublicSigningKey(
      keyId: map['keyId']! as String,
      publicKey: map['publicKey']! as List<int>,
    );
  }
}

Map<String, Object?> _readKey(File file, {required bool private}) {
  if (!file.existsSync()) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.signing,
      code: 'S4001',
      summary: 'Signing key is missing',
      detail: file.path,
      action: 'Run hyfens keys generate or provide an explicit key path.',
    );
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?> ||
      decoded.length != 3 ||
      decoded['algorithm'] != 'ed25519' ||
      decoded['keyId'] is! String ||
      decoded[private ? 'seed' : 'publicKey'] is! String) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.signing,
      code: 'S4002',
      summary: 'Signing key is malformed',
      detail: file.path,
      action: 'Generate a new local Ed25519 key pair and review the old files.',
    );
  }
  final encoded = decoded[private ? 'seed' : 'publicKey']! as String;
  late final List<int> bytes;
  try {
    bytes = base64.decode(encoded);
  } on FormatException {
    throw ToolFailure.single(
      exitCode: ToolExitCode.signing,
      code: 'S4002',
      summary: 'Signing key encoding is invalid',
      detail: file.path,
    );
  }
  if (bytes.length != 32) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.signing,
      code: 'S4002',
      summary: 'Signing key has the wrong length',
      detail: file.path,
    );
  }
  final keyId = decoded['keyId']! as String;
  if (!RegExp(r'^ed25519-[0-9a-f]{16}$').hasMatch(keyId) ||
      (!private && keyId != _keyIdForPublic(bytes))) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.signing,
      code: 'S4002',
      summary: 'Signing key identity is invalid',
      detail: file.path,
      action: 'Generate a new local Ed25519 key pair and review the old files.',
    );
  }
  return <String, Object?>{
    'keyId': keyId,
    if (private) 'seed': bytes else 'publicKey': bytes,
  };
}

String _keyIdForPublic(List<int> publicKey) =>
    'ed25519-${sha256.convert(publicKey).toString().substring(0, 16)}';

bool _samePath(File left, File right) =>
    left.absolute.path == right.absolute.path;

Future<void> _restrictPrivateFile(File file) async {
  if (Platform.isWindows) return;
  final result = await Process.run('chmod', <String>['600', file.path]);
  if (result.exitCode != 0) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.signing,
      code: 'S4005',
      summary: 'Could not restrict private key permissions',
      detail: '${file.path}: ${result.stderr}',
    );
  }
}
