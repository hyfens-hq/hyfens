import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// A signed lifecycle command, separate from Patch Format v1.
///
/// The command selects the release-owned AOT base. It is bound to the exact
/// authenticated patch high-water that was present when the developer issued
/// the command. It never carries code, capabilities, or a new patch sequence.
final class RollbackControlCommand {
  RollbackControlCommand._({
    required this.applicationId,
    required this.releaseId,
    required this.highWaterSequence,
    required this.highWaterDigest,
    required this.keyId,
    required this.signatureBytes,
  });

  static const int version = 1;
  static const String algorithm = 'Ed25519';
  static const String command = 'rollback-base';
  static const int maxBytes = 16 * 1024;
  static final Uint8List _domain = Uint8List.fromList(
    utf8.encode('hyfens-rollback-control-v1\u0000'),
  );
  static final DartEd25519 _ed25519 = DartEd25519();

  final String applicationId;
  final String releaseId;
  final int highWaterSequence;
  final String? highWaterDigest;
  final String keyId;
  final List<int> signatureBytes;

  /// Creates a command after signing the exact canonical control bytes.
  static Future<RollbackControlCommand> sign({
    required String applicationId,
    required String releaseId,
    required int highWaterSequence,
    required String? highWaterDigest,
    required String keyId,
    required Future<List<int>> Function(List<int> message) signer,
  }) async {
    _validateBody(
      applicationId: applicationId,
      releaseId: releaseId,
      highWaterSequence: highWaterSequence,
      highWaterDigest: highWaterDigest,
      keyId: keyId,
    );
    final signature = await signer(
      _message(
        _body(
          applicationId: applicationId,
          releaseId: releaseId,
          highWaterSequence: highWaterSequence,
          highWaterDigest: highWaterDigest,
          keyId: keyId,
        ),
      ),
    );
    if (signature.length != 64) {
      throw const FormatException(
        'Rollback control signature must be 64 bytes',
      );
    }
    return RollbackControlCommand._(
      applicationId: applicationId,
      releaseId: releaseId,
      highWaterSequence: highWaterSequence,
      highWaterDigest: highWaterDigest,
      keyId: keyId,
      signatureBytes: List<int>.unmodifiable(signature),
    );
  }

  /// Decodes and validates the canonical wire representation.
  factory RollbackControlCommand.decode(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Rollback control exceeds byte limit');
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object {
      throw const FormatException('Rollback control is not strict UTF-8 JSON');
    }
    const keys = <String>{
      'algorithm',
      'applicationId',
      'command',
      'commandVersion',
      'highWaterDigest',
      'highWaterSequence',
      'keyId',
      'releaseId',
      'signature',
    };
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(decoded.keys.toSet()).isNotEmpty ||
        decoded['algorithm'] != algorithm ||
        decoded['command'] != command ||
        decoded['commandVersion'] != version ||
        decoded['applicationId'] is! String ||
        decoded['releaseId'] is! String ||
        decoded['highWaterSequence'] is! int ||
        (decoded['highWaterDigest'] != null &&
            decoded['highWaterDigest'] is! String) ||
        decoded['keyId'] is! String ||
        decoded['signature'] is! String) {
      throw const FormatException('Invalid rollback control fields');
    }
    final applicationId = decoded['applicationId']! as String;
    final releaseId = decoded['releaseId']! as String;
    final highWaterSequence = decoded['highWaterSequence']! as int;
    final highWaterDigest = decoded['highWaterDigest'] as String?;
    final keyId = decoded['keyId']! as String;
    _validateBody(
      applicationId: applicationId,
      releaseId: releaseId,
      highWaterSequence: highWaterSequence,
      highWaterDigest: highWaterDigest,
      keyId: keyId,
    );
    final signature = _decodeCanonicalBase64(
      decoded['signature']! as String,
      'signature',
    );
    if (signature.length != 64) {
      throw const FormatException('Invalid rollback control signature length');
    }
    final canonical = utf8.encode(_json(_canonicalJson(decoded)));
    if (!_equalBytes(bytes, canonical)) {
      throw const FormatException(
        'Rollback control is not canonically encoded',
      );
    }
    return RollbackControlCommand._(
      applicationId: applicationId,
      releaseId: releaseId,
      highWaterSequence: highWaterSequence,
      highWaterDigest: highWaterDigest,
      keyId: keyId,
      signatureBytes: List<int>.unmodifiable(signature),
    );
  }

  /// Verifies this command against a release-embedded trusted public key.
  Future<bool> verify(List<int> publicKey) async {
    if (publicKey.length != 32) return false;
    try {
      return await _ed25519.verify(
        _message(
          _body(
            applicationId: applicationId,
            releaseId: releaseId,
            highWaterSequence: highWaterSequence,
            highWaterDigest: highWaterDigest,
            keyId: keyId,
          ),
        ),
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }

  List<int> encodeBytes() => utf8.encode(encode());

  String encode() {
    final body = _body(
      applicationId: applicationId,
      releaseId: releaseId,
      highWaterSequence: highWaterSequence,
      highWaterDigest: highWaterDigest,
      keyId: keyId,
    );
    return _json(<String, Object?>{
      ...body,
      'signature': base64.encode(signatureBytes),
    });
  }

  static Map<String, Object?> _body({
    required String applicationId,
    required String releaseId,
    required int highWaterSequence,
    required String? highWaterDigest,
    required String keyId,
  }) => <String, Object?>{
    'algorithm': algorithm,
    'applicationId': applicationId,
    'command': command,
    'commandVersion': version,
    'highWaterDigest': highWaterDigest,
    'highWaterSequence': highWaterSequence,
    'keyId': keyId,
    'releaseId': releaseId,
  };

  static Uint8List _message(Map<String, Object?> body) => Uint8List.fromList(
    <int>[..._domain, ...utf8.encode(_json(_canonicalJson(body)))],
  );

  static void _validateBody({
    required String applicationId,
    required String releaseId,
    required int highWaterSequence,
    required String? highWaterDigest,
    required String keyId,
  }) {
    _validateComponent(applicationId, 'application ID');
    _validateComponent(releaseId, 'release ID');
    if (highWaterSequence < 0 || highWaterSequence > 0x7fffffffffffffff) {
      throw const FormatException('Rollback high-water sequence is invalid');
    }
    if ((highWaterSequence == 0) != (highWaterDigest == null) ||
        (highWaterDigest != null &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(highWaterDigest))) {
      throw const FormatException('Rollback high-water digest is invalid');
    }
    if (!RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(keyId)) {
      throw const FormatException('Rollback control key ID is invalid');
    }
  }

  static void _validateComponent(String value, String label) {
    if (value.isEmpty || value.length > 256 || value == '.' || value == '..') {
      throw FormatException('Rollback $label is invalid');
    }
    if (value.contains('/') ||
        value.contains(r'\') ||
        value.codeUnits.any((unit) => unit == 0 || unit < 0x20)) {
      throw FormatException('Rollback $label is invalid');
    }
  }

  static List<int> _decodeCanonicalBase64(String value, String field) {
    try {
      final decoded = base64.decode(value);
      if (base64.encode(decoded) != value) {
        throw FormatException('Non-canonical base64 in $field');
      }
      return decoded;
    } on FormatException {
      throw FormatException('Invalid base64 in rollback control $field');
    }
  }

  static Object? _canonicalJson(Object? value) {
    if (value is List<Object?>) {
      return value.map(_canonicalJson).toList(growable: false);
    }
    if (value is Map<String, Object?>) {
      final keys = value.keys.toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalJson(value[key]),
      };
    }
    return value;
  }

  static String _json(Object? value) => jsonEncode(_canonicalJson(value));

  static bool _equalBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
