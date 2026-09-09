import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'installation_key_platform.dart'
    if (dart.library.ui) 'installation_key_platform_flutter.dart'
    as platform;

const _maxCanonicalMessageLength = 16 * 1024;

/// The protection boundary used for the non-exportable installation key.
///
/// This describes key storage only. It is deliberately not an attestation
/// result; App Attest and Play Integrity remain separate future seams.
enum HyfensInstallationStorageProtection { hardwareBacked, platformProtected }

/// Stable opaque identity and public metadata for one app installation.
final class HyfensInstallationIdentity {
  HyfensInstallationIdentity({
    required String installationId,
    required String keyId,
    required List<int> publicKey,
    required this.storageProtection,
  }) : installationId = _validateInstallationId(installationId),
       keyId = _validateKeyId(keyId),
       publicKey = List<int>.unmodifiable(_validatePublicKey(publicKey)) {
    final expectedKeyId = _keyIdForPublicKey(this.publicKey);
    if (this.keyId != expectedKeyId) {
      throw const FormatException(
        'Installation key ID does not match its public key',
      );
    }
  }

  final String installationId;
  final String keyId;
  final List<int> publicKey;
  final HyfensInstallationStorageProtection storageProtection;

  /// Decodes the exact StandardMessageCodec map returned by native code.
  factory HyfensInstallationIdentity.fromMap(Map<Object?, Object?> value) {
    const fields = <String>{
      'installationId',
      'keyId',
      'publicKey',
      'storageProtection',
    };
    final keys = value.keys.whereType<String>().toSet();
    if (value.keys.any((key) => key is! String) ||
        keys.length != value.length ||
        keys.length != fields.length ||
        keys.difference(fields).isNotEmpty ||
        fields.difference(keys).isNotEmpty ||
        value['installationId'] is! String ||
        value['keyId'] is! String ||
        value['storageProtection'] is! String) {
      throw const FormatException('Invalid native installation identity map');
    }

    final storageProtection = _storageProtectionFromName(
      value['storageProtection']! as String,
    );
    return HyfensInstallationIdentity(
      installationId: value['installationId']! as String,
      keyId: value['keyId']! as String,
      publicKey: _bytesFromValue(value['publicKey'], 'publicKey'),
      storageProtection: storageProtection,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'installationId': installationId,
    'keyId': keyId,
    'publicKey': publicKey,
    'storageProtection': storageProtection.name,
  };
}

/// Error codes returned by the native identity boundary are intentionally
/// small and transport-oriented. In particular, [keyUnavailable] means the
/// application may continue without receipts; it does not authorize a file
/// or Dart-key fallback.
final class HyfensInstallationKeyException implements Exception {
  const HyfensInstallationKeyException({
    required this.code,
    required this.message,
  });

  static const String keyUnavailable = 'keyUnavailable';

  final String code;
  final String message;

  @override
  String toString() => 'HyfensInstallationKeyException($code): $message';
}

/// Native-backed installation identity and signing operations.
///
/// The factory is the production constructor. Implementations supplied by
/// tests may implement the two abstract methods without gaining access to
/// native private key material.
abstract class HyfensInstallationKeyStore {
  factory HyfensInstallationKeyStore() => _PlatformInstallationKeyStore();

  Future<HyfensInstallationIdentity> getIdentity();

  Future<List<int>> sign(List<int> canonicalMessage);
}

final class _PlatformInstallationKeyStore
    implements HyfensInstallationKeyStore {
  @override
  Future<HyfensInstallationIdentity> getIdentity() async {
    try {
      final value = await platform.getInstallationIdentity();
      return HyfensInstallationIdentity.fromMap(value);
    } on HyfensInstallationKeyException {
      rethrow;
    } on platform.HyfensInstallationKeyPlatformException catch (error) {
      throw HyfensInstallationKeyException(
        code: error.code,
        message: error.message,
      );
    } on FormatException catch (error) {
      throw HyfensInstallationKeyException(
        code: 'invalidIdentity',
        message: error.message,
      );
    } on Object {
      throw const HyfensInstallationKeyException(
        code: HyfensInstallationKeyException.keyUnavailable,
        message: 'Native installation identity is unavailable.',
      );
    }
  }

  @override
  Future<List<int>> sign(List<int> canonicalMessage) async {
    final message = _validateBytes(canonicalMessage, 'canonicalMessage');
    if (message.length > _maxCanonicalMessageLength) {
      throw const FormatException('canonicalMessage must be at most 16 KiB');
    }
    try {
      final value = await platform.signInstallationMessage(message);
      final signature = _validateBytes(value, 'signature');
      if (signature.length != 64) {
        throw const HyfensInstallationKeyException(
          code: 'invalidSignature',
          message: 'Native installation signature must contain 64 bytes.',
        );
      }
      return List<int>.unmodifiable(signature);
    } on HyfensInstallationKeyException {
      rethrow;
    } on platform.HyfensInstallationKeyPlatformException catch (error) {
      throw HyfensInstallationKeyException(
        code: error.code,
        message: error.message,
      );
    } on FormatException catch (error) {
      throw HyfensInstallationKeyException(
        code: 'invalidSignature',
        message: error.message,
      );
    } on Object {
      throw const HyfensInstallationKeyException(
        code: HyfensInstallationKeyException.keyUnavailable,
        message: 'Native installation signing is unavailable.',
      );
    }
  }
}

String _validateInstallationId(String value) {
  late final List<int> decoded;
  try {
    final padding = (4 - value.length % 4) % 4;
    decoded = base64Url.decode(value.padRight(value.length + padding, '='));
  } on FormatException {
    throw const FormatException('Installation ID must be base64url bytes');
  }
  if (decoded.length != 32 ||
      value.length != 43 ||
      !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value) ||
      base64Url.encode(decoded).replaceAll('=', '') != value) {
    throw const FormatException(
      'Installation ID must be the unpadded base64url encoding of 32 bytes',
    );
  }
  return value;
}

String _validateKeyId(String value) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException(
      'Installation key ID must be a lowercase SHA-256 digest',
    );
  }
  return value;
}

List<int> _validatePublicKey(List<int> value) {
  if (value.length != 65 || value.first != 0x04) {
    throw const FormatException(
      'Installation public key must be an uncompressed P-256 key',
    );
  }
  return _validateBytes(value, 'publicKey');
}

List<int> _validateBytes(Iterable<int> value, String label) {
  final bytes = value.toList(growable: false);
  if (bytes.any((byte) => byte < 0 || byte > 0xff)) {
    throw FormatException('$label contains a non-byte value');
  }
  return bytes;
}

List<int> _bytesFromValue(Object? value, String label) {
  if (value is! Iterable<Object?> || value.any((item) => item is! int)) {
    throw FormatException('Native $label is not a byte list');
  }
  return _validateBytes(value.cast<int>(), label);
}

HyfensInstallationStorageProtection _storageProtectionFromName(String value) {
  for (final protection in HyfensInstallationStorageProtection.values) {
    if (protection.name == value) return protection;
  }
  throw const FormatException('Invalid installation storage protection');
}

String _keyIdForPublicKey(List<int> publicKey) =>
    crypto.sha256.convert(publicKey).toString();
