/// Platform operations used by the optional runtime-attestation producer.
///
/// The platform implementation owns the provider SDK and any provider key
/// material. The Dart package only receives typed, opaque evidence and never
/// treats a missing implementation as a successful attestation.
///
/// The Flutter host contract is the fixed `hyfens/runtime_attestation`
/// channel, method `produce`, with arguments `provider` and
/// `canonical_enrollment_bytes` (`Uint8List`). The host must hash those exact
/// bytes for the selected SDK: Google Play Integrity receives the unpadded
/// base64url SHA-256 digest as `requestHash`; Apple App Attest receives the
/// raw SHA-256 digest as `clientDataHash`. It must return only one of the
/// provider-specific maps documented by [HyfensRuntimeAttestationEvidence],
/// or report `UNSUPPORTED`/`UNAVAILABLE`/`INVALID_EVIDENCE`. SDK provisioning
/// and server verification remain host/private responsibilities.
abstract interface class HyfensRuntimeAttestationPlatform {
  Future<Map<Object?, Object?>> produce({
    required String provider,
    required List<int> canonicalEnrollmentBytes,
  });
}

final class HyfensRuntimeAttestationPlatformException implements Exception {
  const HyfensRuntimeAttestationPlatformException({
    required this.code,
    required this.message,
  });

  static const String unsupported = 'UNSUPPORTED';
  static const String unavailable = 'UNAVAILABLE';
  static const String invalidEvidence = 'INVALID_EVIDENCE';

  final String code;
  final String message;

  @override
  String toString() =>
      'HyfensRuntimeAttestationPlatformException($code): $message';
}

final class _UnsupportedRuntimeAttestationPlatform
    implements HyfensRuntimeAttestationPlatform {
  @override
  Future<Map<Object?, Object?>> produce({
    required String provider,
    required List<int> canonicalEnrollmentBytes,
  }) async {
    throw const HyfensRuntimeAttestationPlatformException(
      code: HyfensRuntimeAttestationPlatformException.unsupported,
      message: 'Runtime attestation is unavailable on this host.',
    );
  }
}

HyfensRuntimeAttestationPlatform createDefaultRuntimeAttestationPlatform() =>
    _UnsupportedRuntimeAttestationPlatform();
