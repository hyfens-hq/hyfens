import 'runtime_attestation_platform.dart';
import 'runtime_attestation_platform.dart'
    if (dart.library.ui) 'runtime_attestation_platform_flutter.dart'
    as platformRuntime;

export 'runtime_attestation_platform.dart'
    show
        HyfensRuntimeAttestationPlatform,
        HyfensRuntimeAttestationPlatformException;

/// The provider selected by the private verifier's platform configuration.
/// The value carried by a client is only a routing label; it is not a trust
/// decision and never replaces server-side provider verification.
enum HyfensRuntimeAttestationProvider {
  googlePlayIntegrity('google_play_integrity'),
  appleAppAttest('apple_app_attest');

  const HyfensRuntimeAttestationProvider(this.wireName);

  final String wireName;
}

enum HyfensRuntimeAttestationEvidenceKind {
  googlePlayIntegrityToken,
  appleAppAttestAttestation,
  appleAppAttestAssertion,
}

/// Typed, opaque evidence returned by a configured platform provider.
///
/// The map is deliberately the exact production registration extension:
/// Google returns `{provider, token}`; App Attest returns either
/// `{provider, key_id, attestation_object}` for initial enrollment or
/// `{provider, key_id, assertion}` for subsequent use. No receipt fields or
/// client-side verification result are included.
final class HyfensRuntimeAttestationEvidence {
  HyfensRuntimeAttestationEvidence.googlePlayIntegrity({required String token})
    : this._(
        provider: HyfensRuntimeAttestationProvider.googlePlayIntegrity,
        kind: HyfensRuntimeAttestationEvidenceKind.googlePlayIntegrityToken,
        token: _boundedOpaque(token),
      );

  HyfensRuntimeAttestationEvidence.appleAppAttestInitial({
    required String keyId,
    required String attestationObject,
  }) : this._(
         provider: HyfensRuntimeAttestationProvider.appleAppAttest,
         kind: HyfensRuntimeAttestationEvidenceKind.appleAppAttestAttestation,
         keyId: _boundedKeyId(keyId),
         attestationObject: _boundedOpaque(attestationObject),
       );

  HyfensRuntimeAttestationEvidence.appleAppAttestAssertion({
    required String keyId,
    required String assertion,
  }) : this._(
         provider: HyfensRuntimeAttestationProvider.appleAppAttest,
         kind: HyfensRuntimeAttestationEvidenceKind.appleAppAttestAssertion,
         keyId: _boundedKeyId(keyId),
         assertion: _boundedOpaque(assertion),
       );

  const HyfensRuntimeAttestationEvidence._({
    required this.provider,
    required this.kind,
    this.keyId,
    this.token,
    this.attestationObject,
    this.assertion,
  });

  static const int maxOpaqueCharacters = 64 * 1024;
  static const int _maxKeyIdCharacters = 256;

  final HyfensRuntimeAttestationProvider provider;
  final HyfensRuntimeAttestationEvidenceKind kind;
  final String? keyId;
  final String? token;
  final String? attestationObject;
  final String? assertion;

  /// Strictly decodes the fixed method-channel response for [expectedProvider].
  factory HyfensRuntimeAttestationEvidence.fromPlatformMap(
    Map<Object?, Object?> value, {
    required HyfensRuntimeAttestationProvider expectedProvider,
  }) {
    final keys = value.keys.whereType<String>().toSet();
    if (value.keys.any((key) => key is! String) ||
        keys.length != value.length ||
        value['provider'] != expectedProvider.wireName) {
      throw const HyfensRuntimeAttestationException('INVALID_EVIDENCE');
    }
    switch (expectedProvider) {
      case HyfensRuntimeAttestationProvider.googlePlayIntegrity:
        if (!_exactKeys(keys, const <String>{'provider', 'token'}) ||
            value['token'] is! String) {
          throw const HyfensRuntimeAttestationException('INVALID_EVIDENCE');
        }
        return HyfensRuntimeAttestationEvidence.googlePlayIntegrity(
          token: value['token']! as String,
        );
      case HyfensRuntimeAttestationProvider.appleAppAttest:
        final hasAttestation = value.containsKey('attestation_object');
        final hasAssertion = value.containsKey('assertion');
        if (value['key_id'] is! String ||
            hasAttestation == hasAssertion ||
            (hasAttestation &&
                (!_exactKeys(keys, const <String>{
                      'provider',
                      'key_id',
                      'attestation_object',
                    }) ||
                    value['attestation_object'] is! String)) ||
            (hasAssertion &&
                (!_exactKeys(keys, const <String>{
                      'provider',
                      'key_id',
                      'assertion',
                    }) ||
                    value['assertion'] is! String))) {
          throw const HyfensRuntimeAttestationException('INVALID_EVIDENCE');
        }
        if (hasAttestation) {
          return HyfensRuntimeAttestationEvidence.appleAppAttestInitial(
            keyId: value['key_id']! as String,
            attestationObject: value['attestation_object']! as String,
          );
        }
        return HyfensRuntimeAttestationEvidence.appleAppAttestAssertion(
          keyId: value['key_id']! as String,
          assertion: value['assertion']! as String,
        );
    }
  }

  /// Returns the exact outer registration map, with no additional fields.
  Map<String, Object?> toMap() => switch (kind) {
    HyfensRuntimeAttestationEvidenceKind.googlePlayIntegrityToken =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        'provider': provider.wireName,
        'token': token,
      }),
    HyfensRuntimeAttestationEvidenceKind.appleAppAttestAttestation =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        'provider': provider.wireName,
        'key_id': keyId,
        'attestation_object': attestationObject,
      }),
    HyfensRuntimeAttestationEvidenceKind.appleAppAttestAssertion =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        'provider': provider.wireName,
        'key_id': keyId,
        'assertion': assertion,
      }),
  };

  static bool _exactKeys(Set<String> actual, Set<String> expected) =>
      actual.length == expected.length && actual.containsAll(expected);

  static String _boundedKeyId(String value) {
    if (value.isEmpty ||
        value.length > _maxKeyIdCharacters ||
        value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const HyfensRuntimeAttestationException('INVALID_EVIDENCE');
    }
    return value;
  }

  static String _boundedOpaque(String value) {
    if (value.isEmpty ||
        value.length > maxOpaqueCharacters ||
        value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw HyfensRuntimeAttestationException('INVALID_EVIDENCE');
    }
    return value;
  }
}

final class HyfensRuntimeAttestationException implements Exception {
  const HyfensRuntimeAttestationException(this.code);

  static const String unsupported = 'UNSUPPORTED';
  static const String unavailable = 'UNAVAILABLE';
  static const String invalidEvidence = 'INVALID_EVIDENCE';
  static const String productionNotEnabled = 'PRODUCTION_NOT_ENABLED';

  final String code;

  @override
  String toString() => 'HyfensRuntimeAttestationException($code)';
}

/// An injected producer receives the exact canonical enrollment bytes that are
/// signed by the installation key. It must bind provider evidence to those
/// bytes; the private verifier computes the corresponding SHA-256 hash.
abstract interface class HyfensRuntimeAttestationEvidenceProducer {
  /// Produces evidence bound to the exact canonical enrollment bytes.
  Future<HyfensRuntimeAttestationEvidence> produce(
    List<int> canonicalEnrollmentBytes,
  );
}

/// Fixed native seam for the Android and Apple SDK adapters. The public
/// package contains no provider SDK dependency; platform modules implement the
/// `hyfens/runtime_attestation` method channel.
final class HyfensPlatformRuntimeAttestationEvidenceProducer
    implements HyfensRuntimeAttestationEvidenceProducer {
  HyfensPlatformRuntimeAttestationEvidenceProducer({
    required this.provider,
    HyfensRuntimeAttestationPlatform? platformImplementation,
  }) : _platform =
           platformImplementation ??
           // The conditional import selects the Flutter MethodChannel only
           // under Flutter; pure-Dart hosts receive an explicit unsupported
           // result instead of a simulated attestation.
           platformRuntime.createDefaultRuntimeAttestationPlatform();

  final HyfensRuntimeAttestationProvider provider;
  final HyfensRuntimeAttestationPlatform _platform;

  @override
  Future<HyfensRuntimeAttestationEvidence> produce(
    List<int> canonicalEnrollmentBytes,
  ) async {
    final bytes = _boundedBytes(canonicalEnrollmentBytes);
    try {
      final response = await _platform.produce(
        provider: provider.wireName,
        canonicalEnrollmentBytes: bytes,
      );
      return HyfensRuntimeAttestationEvidence.fromPlatformMap(
        response,
        expectedProvider: provider,
      );
    } on HyfensRuntimeAttestationPlatformException catch (error) {
      throw HyfensRuntimeAttestationException(error.code);
    }
  }

  static List<int> _boundedBytes(List<int> value) {
    if (value.isEmpty ||
        value.length > _maxCanonicalEnrollmentBytes ||
        value.any((byte) => byte < 0 || byte > 0xff)) {
      throw const HyfensRuntimeAttestationException('INVALID_EVIDENCE');
    }
    return List<int>.unmodifiable(value);
  }

  static const int _maxCanonicalEnrollmentBytes = 16 * 1024;
}
