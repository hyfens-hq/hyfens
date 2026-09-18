import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:instrumentation_e0/e0_runtime.dart';

/// An application-embedded Ed25519 verification key selected by [keyId].
final class E1TrustedPublicKey {
  E1TrustedPublicKey({required this.keyId, required List<int> bytes})
    : bytes = List<int>.unmodifiable(bytes) {
    _validateKeyId(keyId);
    if (bytes.length != 32) {
      throw ArgumentError.value(bytes.length, 'bytes', 'must contain 32 bytes');
    }
  }

  final String keyId;
  final List<int> bytes;
}

/// A verified signed envelope. The patch bytes have not yet been E0-decoded.
final class E1VerifiedPatch {
  const E1VerifiedPatch({
    required this.keyId,
    required this.patchBytes,
    required this.envelopeBytes,
  });

  final String keyId;
  final List<int> patchBytes;
  final List<int> envelopeBytes;
}

/// Deterministic Ed25519 envelope for the exact canonical E0 patch bytes.
///
/// The signed message is a domain separator followed by canonical JSON for
/// every envelope field except `signature`. The E0 payload is base64 encoded,
/// so its exact bytes (including all release and sequence metadata) are signed.
final class E1SignedPatchEnvelope {
  E1SignedPatchEnvelope._({
    required this.keyId,
    required this.patchBytes,
    required this.signatureBytes,
  });

  static const int envelopeVersion = 1;
  static const String algorithm = 'Ed25519';
  static const int maxBytes = 96 * 1024;
  static final Uint8List _domain = Uint8List.fromList(
    utf8.encode('hyfens-signed-patch-v1\u0000'),
  );

  final String keyId;
  final List<int> patchBytes;
  final List<int> signatureBytes;

  static final DartEd25519 _ed25519 = DartEd25519();

  static Future<Uint8List> sign({
    required List<int> patchBytes,
    required String keyId,
    required List<int> privateKeySeed,
  }) async {
    _validateKeyId(keyId);
    if (patchBytes.length > E0PatchContainer.maxBytes) {
      throw const FormatException('Patch exceeds byte limit');
    }
    if (privateKeySeed.length != 32) {
      throw ArgumentError.value(
        privateKeySeed.length,
        'privateKeySeed',
        'must contain 32 bytes',
      );
    }
    final body = _body(keyId, patchBytes);
    final keyPair = await _ed25519.newKeyPairFromSeed(privateKeySeed);
    try {
      final signature = await _ed25519.sign(_message(body), keyPair: keyPair);
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object>{
            ...body,
            'signature': base64.encode(signature.bytes),
          }),
        ),
      );
      if (bytes.length > maxBytes) {
        throw const FormatException('Signed envelope exceeds byte limit');
      }
      return bytes;
    } finally {
      keyPair.destroy();
    }
  }

  static Future<E1VerifiedPatch> verify({
    required List<int> envelopeBytes,
    required Map<String, E1TrustedPublicKey> trustedKeys,
  }) async {
    final envelope = decodeFraming(envelopeBytes);
    final trustedKey = trustedKeys[envelope.keyId];
    if (trustedKey == null || trustedKey.keyId != envelope.keyId) {
      throw const FormatException('Signed patch key is not trusted');
    }
    final body = _body(envelope.keyId, envelope.patchBytes);
    final valid = await _ed25519.verify(
      _message(body),
      signature: Signature(
        envelope.signatureBytes,
        publicKey: SimplePublicKey(trustedKey.bytes, type: KeyPairType.ed25519),
      ),
    );
    if (!valid) {
      throw const FormatException('Signed patch signature is invalid');
    }
    return E1VerifiedPatch(
      keyId: envelope.keyId,
      patchBytes: List<int>.unmodifiable(envelope.patchBytes),
      envelopeBytes: List<int>.unmodifiable(envelopeBytes),
    );
  }

  static E1SignedPatchEnvelope decodeFraming(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Signed envelope exceeds byte limit');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object {
      throw const FormatException('Signed envelope is not strict UTF-8 JSON');
    }
    const keys = <String>{
      'algorithm',
      'envelopeVersion',
      'keyId',
      'patch',
      'signature',
    };
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(decoded.keys.toSet()).isNotEmpty ||
        decoded['algorithm'] != algorithm ||
        decoded['envelopeVersion'] != envelopeVersion ||
        decoded['keyId'] is! String ||
        decoded['patch'] is! String ||
        decoded['signature'] is! String) {
      throw const FormatException('Invalid signed envelope');
    }
    final canonical = utf8.encode(jsonEncode(_canonicalJson(decoded)));
    if (!_equalBytes(bytes, canonical)) {
      throw const FormatException('Signed envelope is not canonically encoded');
    }
    final keyId = decoded['keyId']! as String;
    _validateKeyId(keyId);
    final patchBytes = _decodeCanonicalBase64(
      decoded['patch']! as String,
      'patch',
    );
    final signatureBytes = _decodeCanonicalBase64(
      decoded['signature']! as String,
      'signature',
    );
    if (patchBytes.length > E0PatchContainer.maxBytes) {
      throw const FormatException('Patch exceeds byte limit');
    }
    if (signatureBytes.length != 64) {
      throw const FormatException('Invalid Ed25519 signature length');
    }
    return E1SignedPatchEnvelope._(
      keyId: keyId,
      patchBytes: List<int>.unmodifiable(patchBytes),
      signatureBytes: List<int>.unmodifiable(signatureBytes),
    );
  }

  static Map<String, Object> _body(String keyId, List<int> patchBytes) =>
      <String, Object>{
        'algorithm': algorithm,
        'envelopeVersion': envelopeVersion,
        'keyId': keyId,
        'patch': base64.encode(patchBytes),
      };

  static Uint8List _message(Map<String, Object> body) => Uint8List.fromList(
    <int>[..._domain, ...utf8.encode(jsonEncode(_canonicalJson(body)))],
  );

  static Uint8List _decodeCanonicalBase64(String value, String field) {
    try {
      final decoded = base64.decode(value);
      if (base64.encode(decoded) != value) {
        throw FormatException('Non-canonical base64 in $field');
      }
      return Uint8List.fromList(decoded);
    } on FormatException {
      throw FormatException('Invalid base64 in signed envelope $field');
    }
  }

  static Object? _canonicalJson(Object? value) {
    if (value is List<Object?>) {
      return value.map(_canonicalJson).toList(growable: false);
    }
    if (value is Map<String, Object?>) {
      final sortedKeys = value.keys.toList()..sort();
      return <String, Object?>{
        for (final key in sortedKeys) key: _canonicalJson(value[key]),
      };
    }
    return value;
  }

  static bool _equalBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

void _validateKeyId(String keyId) {
  if (!RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(keyId)) {
    throw const FormatException('Invalid signed patch key ID');
  }
}
