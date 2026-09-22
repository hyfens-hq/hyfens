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

/// Platform permission policy used for private signing-key files.
enum SigningPlatform { posix, windows }

/// Process boundary used by signing-key permission enforcement.
///
/// The injection point keeps Windows ACL generation and read validation
/// deterministic in focused tests on non-Windows hosts.
typedef SigningProcessRunner = ProcessResult Function(
  String executable,
  List<String> arguments,
);

SigningPlatform get defaultSigningPlatform =>
    Platform.isWindows ? SigningPlatform.windows : SigningPlatform.posix;

final class KeyStore {
  const KeyStore({this.platform, this.processRunner});

  final SigningPlatform? platform;
  final SigningProcessRunner? processRunner;

  SigningPlatform get _effectivePlatform => platform ?? defaultSigningPlatform;

  SigningProcessRunner get _runProcess => processRunner ?? _runSigningProcess;

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
      await privateFile.parent.create(recursive: true);
      final staging = await privateFile.parent.createTemp('.hyfens-key-');
      final stagedPrivate = File('${staging.path}/private.key');
      try {
        await stagedPrivate.create();
        _restrictPrivateFile(
          stagedPrivate,
          platform: _effectivePlatform,
          processRunner: _runProcess,
        );
        await stagedPrivate.writeAsString(
          jsonEncode(<String, Object>{
                'algorithm': 'ed25519',
                'keyId': keyId,
                'seed': base64.encode(seed),
              }) +
              '\n',
          flush: true,
        );
        await stagedPrivate.rename(privateFile.path);
      } finally {
        await staging.delete(recursive: true);
      }
      await writeAtomicText(
        publicFile,
        jsonEncode(<String, Object>{
              'algorithm': 'ed25519',
              'keyId': keyId,
              'publicKey': base64.encode(publicKey.bytes),
            }) +
            '\n',
      );
      return SigningKey(keyId: keyId, seed: seed, publicKey: publicKey.bytes);
    } finally {
      keyPair.destroy();
    }
  }

  SigningKey readPrivate(File file) {
    if (_effectivePlatform == SigningPlatform.windows && file.existsSync()) {
      final principal = _currentWindowsPrincipal(
        file,
        processRunner: _runProcess,
      );
      _verifyWindowsAcl(file, principal, processRunner: _runProcess);
    }
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

void _restrictPrivateFile(
  File file, {
  required SigningPlatform platform,
  required SigningProcessRunner processRunner,
}) {
  switch (platform) {
    case SigningPlatform.posix:
      final result = _runSigningCommand(file, processRunner, 'chmod', <String>[
        '600',
        file.path,
      ]);
      if (result.exitCode != 0) throw _privatePermissionFailure(file);
    case SigningPlatform.windows:
      final principal = _currentWindowsPrincipal(
        file,
        processRunner: processRunner,
      );
      final result = _runSigningCommand(file, processRunner, 'icacls', <String>[
        file.path,
        '/reset',
        '/inheritance:r',
        '/grant:r',
        '$principal:F',
      ]);
      if (result.exitCode != 0) throw _privatePermissionFailure(file);
      _verifyWindowsAcl(file, principal, processRunner: processRunner);
  }
}

String _currentWindowsPrincipal(
  File file, {
  required SigningProcessRunner processRunner,
}) {
  final result = _runSigningCommand(
    file,
    processRunner,
    'whoami',
    const <String>[],
  );
  if (result.exitCode != 0) throw _privatePermissionFailure(file);
  final principals = const LineSplitter()
      .convert(result.stdout.toString())
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (principals.length != 1 || !_isSafeWindowsPrincipal(principals.single)) {
    throw _privatePermissionFailure(file);
  }
  return principals.single;
}

void _verifyWindowsAcl(
  File file,
  String principal, {
  required SigningProcessRunner processRunner,
}) {
  final result = _runSigningCommand(file, processRunner, 'icacls', <String>[
    file.path,
  ]);
  if (result.exitCode != 0) throw _privatePermissionFailure(file);
  final entries = _parseWindowsAcl(result.stdout.toString(), file);
  if (entries.length != 1) throw _privatePermissionFailure(file);
  final entry = entries.single;
  final rights = entry.rights
      .map((right) => right.toUpperCase())
      .toList(growable: false);
  if (entry.principal.toLowerCase() != principal.toLowerCase() ||
      rights.length != 1 ||
      rights.single != 'F') {
    throw _privatePermissionFailure(file);
  }
}

List<_WindowsAclEntry> _parseWindowsAcl(String output, File file) {
  final entryPattern = RegExp(r'^\s*(.+?)\s*:\s*((?:\([^)]+\))+)$');
  final entries = <_WindowsAclEntry>[];
  for (final line in const LineSplitter().convert(output)) {
    final aclLine = _stripWindowsAclPath(line, file);
    final match = entryPattern.firstMatch(aclLine);
    if (match == null) continue;
    final rights = RegExp(r'\(([^)]*)\)')
        .allMatches(match.group(2)!)
        .map((item) => item.group(1)!)
        .toList(growable: false);
    entries.add(
      _WindowsAclEntry(principal: match.group(1)!.trim(), rights: rights),
    );
  }
  return entries;
}

String _stripWindowsAclPath(String line, File file) {
  final candidates = <String>{
    file.path,
    file.absolute.path,
    file.path.replaceAll('/', '\\'),
    file.absolute.path.replaceAll('/', '\\'),
  };
  for (final candidate in candidates) {
    for (final prefix in <String>[candidate, '"$candidate"']) {
      if (line.startsWith(prefix)) {
        return line.substring(prefix.length).trimLeft();
      }
    }
  }
  return line;
}

bool _isSafeWindowsPrincipal(String principal) {
  if (principal.isEmpty ||
      principal.startsWith('-') ||
      principal.startsWith('/')) {
    return false;
  }
  return !principal.contains(RegExp(r'[<>:"/|?*()]'));
}

ProcessResult _runSigningCommand(
  File file,
  SigningProcessRunner processRunner,
  String executable,
  List<String> arguments,
) {
  try {
    return processRunner(executable, arguments);
  } on Object {
    throw _privatePermissionFailure(file);
  }
}

ProcessResult _runSigningProcess(String executable, List<String> arguments) =>
    Process.runSync(executable, arguments);

ToolFailure _privatePermissionFailure(File file) => ToolFailure.single(
  exitCode: ToolExitCode.signing,
  code: 'S4005',
  summary: 'Could not restrict private key permissions',
  detail: file.path,
  action: 'Fix the private key permissions before signing.',
);

final class _WindowsAclEntry {
  const _WindowsAclEntry({required this.principal, required this.rights});

  final String principal;
  final List<String> rights;
}
