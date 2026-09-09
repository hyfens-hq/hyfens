import 'package:hyfens_flutter_integration/flutter_integration.dart';
import 'package:test/test.dart';

void main() {
  test('evidence maps use the frozen provider-specific shapes', () {
    expect(
      HyfensRuntimeAttestationEvidence.googlePlayIntegrity(token: 'play-token')
          .toMap(),
      <String, Object?>{
        'provider': 'google_play_integrity',
        'token': 'play-token',
      },
    );
    expect(
      HyfensRuntimeAttestationEvidence.appleAppAttestInitial(
        keyId: 'app-attest-key',
        attestationObject: 'attestation-object',
      ).toMap(),
      <String, Object?>{
        'provider': 'apple_app_attest',
        'key_id': 'app-attest-key',
        'attestation_object': 'attestation-object',
      },
    );
    expect(
      HyfensRuntimeAttestationEvidence.appleAppAttestAssertion(
        keyId: 'app-attest-key',
        assertion: 'assertion',
      ).toMap(),
      <String, Object?>{
        'provider': 'apple_app_attest',
        'key_id': 'app-attest-key',
        'assertion': 'assertion',
      },
    );
  });

  test('platform evidence maps reject unknown or ambiguous fields', () {
    expect(
      () => HyfensRuntimeAttestationEvidence.fromPlatformMap(
        <Object?, Object?>{
          'provider': 'google_play_integrity',
          'token': 'token',
          'extra': 'not-allowed',
        },
        expectedProvider: HyfensRuntimeAttestationProvider.googlePlayIntegrity,
      ),
      throwsA(isA<HyfensRuntimeAttestationException>()),
    );
    expect(
      () => HyfensRuntimeAttestationEvidence.fromPlatformMap(<Object?, Object?>{
        'provider': 'apple_app_attest',
        'key_id': 'key',
        'attestation_object': 'initial',
        'assertion': 'ambiguous',
      }, expectedProvider: HyfensRuntimeAttestationProvider.appleAppAttest),
      throwsA(isA<HyfensRuntimeAttestationException>()),
    );
  });

  test(
    'platform producer passes immutable canonical enrollment bytes',
    () async {
      final platform = _RecordingPlatform();
      final producer = HyfensPlatformRuntimeAttestationEvidenceProducer(
        provider: HyfensRuntimeAttestationProvider.googlePlayIntegrity,
        platformImplementation: platform,
      );
      final canonical = <int>[1, 2, 3, 4];

      final evidence = await producer.produce(canonical);

      expect(platform.provider, 'google_play_integrity');
      expect(platform.canonicalEnrollmentBytes, canonical);
      expect(
        () => platform.canonicalEnrollmentBytes![0] = 9,
        throwsUnsupportedError,
      );
      expect(evidence.toMap(), <String, Object?>{
        'provider': 'google_play_integrity',
        'token': 'platform-token',
      });
    },
  );

  test('default host platform is explicitly unsupported', () async {
    final producer = HyfensPlatformRuntimeAttestationEvidenceProducer(
      provider: HyfensRuntimeAttestationProvider.appleAppAttest,
    );

    await expectLater(
      producer.produce(<int>[1]),
      throwsA(
        isA<HyfensRuntimeAttestationException>().having(
          (error) => error.code,
          'code',
          HyfensRuntimeAttestationException.unsupported,
        ),
      ),
    );
  });

  test(
    'platform producer rejects oversized canonical enrollment input',
    () async {
      final platform = _RecordingPlatform();
      final producer = HyfensPlatformRuntimeAttestationEvidenceProducer(
        provider: HyfensRuntimeAttestationProvider.googlePlayIntegrity,
        platformImplementation: platform,
      );

      await expectLater(
        producer.produce(List<int>.filled(16 * 1024 + 1, 0)),
        throwsA(
          isA<HyfensRuntimeAttestationException>().having(
            (error) => error.code,
            'code',
            HyfensRuntimeAttestationException.invalidEvidence,
          ),
        ),
      );
      expect(platform.canonicalEnrollmentBytes, isNull);
    },
  );
}

final class _RecordingPlatform implements HyfensRuntimeAttestationPlatform {
  String? provider;
  List<int>? canonicalEnrollmentBytes;

  @override
  Future<Map<Object?, Object?>> produce({
    required String provider,
    required List<int> canonicalEnrollmentBytes,
  }) async {
    this.provider = provider;
    this.canonicalEnrollmentBytes = canonicalEnrollmentBytes;
    return <Object?, Object?>{'provider': provider, 'token': 'platform-token'};
  }
}
