import 'package:flutter/services.dart';

import 'runtime_attestation_platform.dart';

/// Fixed host seam for optional provider SDK modules. This package deliberately
/// does not load provider SDKs dynamically or claim that a channel response is
/// trusted; an Android/iOS host must register this channel and perform the
/// configured Play Integrity/App Attest operation itself.
const MethodChannel _channel = MethodChannel('hyfens/runtime_attestation');

final class _FlutterRuntimeAttestationPlatform
    implements HyfensRuntimeAttestationPlatform {
  @override
  Future<Map<Object?, Object?>> produce({
    required String provider,
    required List<int> canonicalEnrollmentBytes,
  }) async {
    try {
      final value = await _channel.invokeMethod<Object?>(
        'produce',
        <String, Object?>{
          'provider': provider,
          'canonical_enrollment_bytes': Uint8List.fromList(
            canonicalEnrollmentBytes,
          ),
        },
      );
      if (value is! Map<Object?, Object?>) {
        throw const HyfensRuntimeAttestationPlatformException(
          code: HyfensRuntimeAttestationPlatformException.invalidEvidence,
          message: 'Native runtime attestation response is not a map.',
        );
      }
      return value;
    } on HyfensRuntimeAttestationPlatformException {
      rethrow;
    } on MissingPluginException {
      throw const HyfensRuntimeAttestationPlatformException(
        code: HyfensRuntimeAttestationPlatformException.unsupported,
        message: 'Runtime attestation plugin is unavailable.',
      );
    } on PlatformException {
      throw const HyfensRuntimeAttestationPlatformException(
        code: HyfensRuntimeAttestationPlatformException.unavailable,
        message: 'Native runtime attestation is unavailable.',
      );
    }
  }
}

HyfensRuntimeAttestationPlatform createDefaultRuntimeAttestationPlatform() =>
    _FlutterRuntimeAttestationPlatform();
