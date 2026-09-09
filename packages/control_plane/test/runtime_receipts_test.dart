import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

const _artifactHex =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late _Key key;
  late DateTime now;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-runtime-receipts-',
    );
    store = FileControlPlaneStore(directory);
    await store.initialize();
    key = _Key.create(2, 7);
    now = DateTime.utc(2036, 1, 10, 12);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('development receipt settles once and is non-billable', () async {
    final settlement = _developmentSettlement(store, () => now);
    final challenge = await settlement.issueChallenge(
      organizationId: 'org_receipts',
      request: _scopeRequest(key),
    );
    final enrollment = _map(challenge['enrollment']);
    final registered = await settlement.register(
      organizationId: 'org_receipts',
      request: <String, Object?>{
        'enrollment': enrollment,
        'signature': key.sign(enrollment),
      },
    );
    expect(registered['billable'], isFalse);
    expect(registered['trust_level'], 'DEVELOPMENT_ACCEPTANCE');

    final receipt = _map(registered['receipt']);
    final first = await settlement.settleInstall(
      organizationId: 'org_receipts',
      request: <String, Object?>{...receipt, 'signature': key.sign(receipt)},
    );
    final retry = await settlement.settleInstall(
      organizationId: 'org_receipts',
      request: <String, Object?>{...receipt, 'signature': key.sign(receipt)},
    );

    expect(first['accepted'], isTrue);
    expect(first['billable'], isFalse);
    expect(first['duplicate'], isFalse);
    expect(retry['accepted'], isTrue);
    expect(retry['billable'], isFalse);
    expect(retry['duplicate'], isTrue);
    final events = await store.listJson('runtime_usage_events');
    expect(events, hasLength(1));
    expect(events.single['eventType'], 'successful_patch_install');
    expect(events.single['financialUsageUnits'], 0);
  });

  test(
    'response loss and restart-style retry produce one durable event',
    () async {
      final settlement = _developmentSettlement(store, () => now);
      final challenge = await settlement.issueChallenge(
        organizationId: 'org_receipts',
        request: _scopeRequest(key),
      );
      final enrollment = _map(challenge['enrollment']);
      final registered = await settlement.register(
        organizationId: 'org_receipts',
        request: <String, Object?>{
          'enrollment': enrollment,
          'signature': key.sign(enrollment),
        },
      );
      final receipt = _map(registered['receipt']);
      final request = <String, Object?>{
        ...receipt,
        'signature': key.sign(receipt),
      };

      await settlement.settleInstall(
        organizationId: 'org_receipts',
        request: request,
      );
      // Model a client that lost the first response and restarted with its
      // durable unsigned body. The P1363 signature may be regenerated.
      now = now.add(const Duration(minutes: 1));
      final afterRestart = await settlement.settleInstall(
        organizationId: 'org_receipts',
        request: <String, Object?>{...receipt, 'signature': key.sign(receipt)},
      );
      expect(afterRestart['duplicate'], isTrue);
      expect(await store.listJson('runtime_receipts'), hasLength(1));
      expect(await store.listJson('runtime_usage_events'), hasLength(1));
    },
  );

  test(
    'wrong key, app, environment, and expired admission fail closed',
    () async {
      final settlement = _developmentSettlement(store, () => now);
      final challenge = await settlement.issueChallenge(
        organizationId: 'org_receipts',
        request: _scopeRequest(key),
      );
      final enrollment = _map(challenge['enrollment']);
      final registered = await settlement.register(
        organizationId: 'org_receipts',
        request: <String, Object?>{
          'enrollment': enrollment,
          'signature': key.sign(enrollment),
        },
      );
      final receipt = _map(registered['receipt']);

      final otherKey = _Key.create(3, 8);
      final substitutedChallenge = await settlement.issueChallenge(
        organizationId: 'org_receipts',
        request: _scopeRequest(
          otherKey,
          installationId: enrollment['installation_id']! as String,
        ),
      );
      final substitutedEnrollment = _map(substitutedChallenge['enrollment']);
      await expectLater(
        settlement.register(
          organizationId: 'org_receipts',
          request: <String, Object?>{
            'enrollment': substitutedEnrollment,
            'signature': otherKey.sign(substitutedEnrollment),
          },
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'KEY_SUBSTITUTION',
          ),
        ),
      );

      final wrongApp = <String, Object?>{
        ...receipt,
        'application_id': 'app_other',
      };
      await expectLater(
        settlement.settleInstall(
          organizationId: 'org_receipts',
          request: <String, Object?>{
            ...wrongApp,
            'signature': key.sign(wrongApp),
          },
        ),
        throwsA(isA<ControlPlaneException>()),
      );
      final wrongEnvironment = <String, Object?>{
        ...receipt,
        'environment_id': 'env_other',
      };
      await expectLater(
        settlement.settleInstall(
          organizationId: 'org_receipts',
          request: <String, Object?>{
            ...wrongEnvironment,
            'signature': key.sign(wrongEnvironment),
          },
        ),
        throwsA(isA<ControlPlaneException>()),
      );

      now = now.add(const Duration(days: 2));
      await expectLater(
        settlement.settleInstall(
          organizationId: 'org_receipts',
          request: <String, Object?>{
            ...receipt,
            'signature': key.sign(receipt),
          },
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'ADMISSION_EXPIRED',
          ),
        ),
      );
      final rejectionCodes = (await store.listJson('runtime_rejections'))
          .map((value) => value['code'])
          .toSet();
      expect(rejectionCodes, contains('KEY_SUBSTITUTION'));
      expect(rejectionCodes, contains('RECEIPT_SCOPE_MISMATCH'));
      expect(rejectionCodes, contains('ADMISSION_EXPIRED'));
    },
  );

  test('attested production policy is explicit and billable only after verification', () async {
    final verifier = _FakeAttestationVerifier();
    final settlement = RuntimeReceiptSettlement(
      store: store,
      policy: const AttestedProductionRuntimeReceiptPolicy(enabled: true),
      attestationVerifier: verifier,
      clock: () => now,
      random: Random(4),
    );
    final challenge = await settlement.issueChallenge(
      organizationId: 'org_receipts',
      request: _scopeRequest(key),
    );
    final enrollment = _map(challenge['enrollment']);
    final registered = await settlement.register(
      organizationId: 'org_receipts',
      request: <String, Object?>{
        'enrollment': enrollment,
        'signature': key.sign(enrollment),
        'attestation': <String, Object?>{
          'provider': 'apple_app_attest',
          'key_id': 'app-attest-key',
          'attestation_object': 'opaque-attestation',
        },
      },
    );
    expect(registered['billable'], isTrue);
    expect(registered['trust_level'], 'ATTESTED_APP');
    final receipt = _map(registered['receipt']);
    final result = await settlement.settleInstall(
      organizationId: 'org_receipts',
      request: <String, Object?>{...receipt, 'signature': key.sign(receipt)},
    );
    expect(result['billable'], isTrue);
    final event = (await store.listJson('runtime_usage_events')).single;
    expect(event['financialUsageUnits'], 1);
    expect(verifier.requests, hasLength(1));
  });

  test('attestation evidence cannot be replayed for a new admission', () async {
    final verifier = _StaleBindingAttestationVerifier();
    final settlement = RuntimeReceiptSettlement(
      store: store,
      policy: const AttestedProductionRuntimeReceiptPolicy(enabled: true),
      attestationVerifier: verifier,
      clock: () => now,
      random: Random(5),
    );
    final evidence = <String, Object?>{
      'provider': 'google_play_integrity',
      'token': 'opaque-integrity-token',
    };
    final firstChallenge = await settlement.issueChallenge(
      organizationId: 'org_receipts',
      request: _scopeRequest(key),
    );
    final firstEnrollment = _map(firstChallenge['enrollment']);
    await settlement.register(
      organizationId: 'org_receipts',
      request: <String, Object?>{
        'enrollment': firstEnrollment,
        'signature': key.sign(firstEnrollment),
        'attestation': evidence,
      },
    );

    final replayChallenge = await settlement.issueChallenge(
      organizationId: 'org_receipts',
      request: _scopeRequest(key),
    );
    final replayEnrollment = _map(replayChallenge['enrollment']);
    await expectLater(
      settlement.register(
        organizationId: 'org_receipts',
        request: <String, Object?>{
          'enrollment': replayEnrollment,
          'signature': key.sign(replayEnrollment),
          'attestation': evidence,
        },
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'RUNTIME_TRUST_REJECTED',
        ),
      ),
    );
  });

  test('attestation outage fails closed without creating usage', () async {
    final settlement = RuntimeReceiptSettlement(
      store: store,
      policy: const AttestedProductionRuntimeReceiptPolicy(enabled: true),
      attestationVerifier: const _UnavailableAttestationVerifier(),
      clock: () => now,
      random: Random(7),
    );
    final challenge = await settlement.issueChallenge(
      organizationId: 'org_receipts',
      request: _scopeRequest(key),
    );
    final enrollment = _map(challenge['enrollment']);
    await expectLater(
      settlement.register(
        organizationId: 'org_receipts',
        request: <String, Object?>{
          'enrollment': enrollment,
          'signature': key.sign(enrollment),
          'attestation': <String, Object?>{
            'provider': 'google_play_integrity',
            'token': 'opaque-integrity-token',
          },
        },
      ),
      throwsA(
        isA<ControlPlaneException>()
            .having((error) => error.code, 'code', 'ATTESTATION_UNAVAILABLE')
            .having((error) => error.statusCode, 'status', 503),
      ),
    );
    expect(await store.listJson('runtime_usage_events'), isEmpty);
  });

  test('a custom policy cannot make an unattested install billable', () async {
    final settlement = RuntimeReceiptSettlement(
      store: store,
      policy: const _UnsafeBillablePolicy(),
      clock: () => now,
      random: Random(6),
    );
    final challenge = await settlement.issueChallenge(
      organizationId: 'org_receipts',
      request: _scopeRequest(key),
    );
    final enrollment = _map(challenge['enrollment']);
    await expectLater(
      settlement.register(
        organizationId: 'org_receipts',
        request: <String, Object?>{
          'enrollment': enrollment,
          'signature': key.sign(enrollment),
        },
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'RUNTIME_TRUST_REJECTED',
        ),
      ),
    );
  });

  test(
    'HTTP routes enforce the scoped delivery credential and resource graph',
    () async {
      final service = ControlPlaneService(store: store, clock: () => now);
      final bootstrap = await service.bootstrap(
        organizationName: 'Receipt HTTP',
        runtimeApplicationId: 'com.example.receipts',
        platformId: 'plt_ios',
        environmentName: 'development',
      );
      final digest = 'sha256:$_artifactHex';
      final release = ReleaseRecord(
        id: 'rel_receipts',
        organizationId: bootstrap.organization.id,
        applicationId: bootstrap.application.id,
        platformId: 'plt_ios',
        runtimeApplicationId: 'com.example.receipts',
        runtimeReleaseId: 'release-1',
        buildTarget: 'ios-arm64-release',
        runtimeCompatibilityVersion: 1,
        patchFormatVersion: 1,
        buildFingerprint: digest,
        capabilityAuthorityDigest: digest,
        functionSignatureDigest: digest,
        displayVersion: '1.0.0',
        signingPublicKeys: const <String, String>{'release-key': 'public'},
        createdAt: now,
      );
      final patch = PatchRecord(
        id: 'patch_receipts',
        organizationId: bootstrap.organization.id,
        releaseId: release.id,
        runtimePatchId: 'patch-1',
        sequence: 1,
        artifactId: 'artifact_receipts',
        sha256: digest,
        sizeBytes: 1,
        signatureKeyId: 'release-key',
        state: 'READY',
        createdAt: now,
      );
      final artifact = ArtifactRecord(
        id: 'artifact_receipts',
        organizationId: bootstrap.organization.id,
        patchId: patch.id,
        sha256: digest,
        sizeBytes: 1,
        contentType: 'application/octet-stream',
        state: 'READY',
        createdAt: now,
      );
      final environment = EnvironmentRecord(
        id: bootstrap.environment.id,
        organizationId: bootstrap.organization.id,
        applicationId: bootstrap.application.id,
        name: bootstrap.environment.name,
        version: 1,
        promotedReleaseId: release.id,
        createdAt: bootstrap.environment.createdAt,
      );
      await store.createJson('releases', release.id, release.toJson());
      await store.createJson('patches', patch.id, patch.toJson());
      await store.createJson('artifacts', artifact.id, artifact.toJson());
      await store.replaceJson(
        'environments',
        environment.id,
        environment.toJson(),
      );

      final server = await ControlPlaneHttpServer(
        service,
        runtimeReceiptSettlement: RuntimeReceiptSettlement(
          store: store,
          policy: DevelopmentRuntimeReceiptPolicy(
            environmentIds: <String>{bootstrap.environment.id},
          ),
          clock: () => now,
          random: Random(1),
        ),
      ).bind();
      addTearDown(() => server.close(force: true));
      final client = HttpClient();
      try {
        final challengeBody = _scopeRequest(
          key,
          applicationId: bootstrap.application.id,
          environmentId: bootstrap.environment.id,
          runtimeApplicationId: 'com.example.receipts',
          releaseId: 'release-1',
          patchId: 'patch-1',
          artifactDigest: _artifactHex,
        );
        final challengeResponse = await _post(
          client,
          server.port,
          '/v1/runtime/installations/challenge',
          bootstrap.deliveryCredential.token,
          challengeBody,
        );
        expect(challengeResponse.statusCode, 200);
        final challenge = _map(challengeResponse.body['enrollment']);
        final registerResponse = await _post(
          client,
          server.port,
          '/v1/runtime/installations/register',
          bootstrap.deliveryCredential.token,
          <String, Object?>{
            'enrollment': challenge,
            'signature': key.sign(challenge),
          },
        );
        expect(registerResponse.statusCode, 200);
        final registered = registerResponse.body;
        final receipt = _map(registered['receipt']);
        final successResponse = await _post(
          client,
          server.port,
          '/v1/runtime/install-success',
          bootstrap.deliveryCredential.token,
          <String, Object?>{...receipt, 'signature': key.sign(receipt)},
        );
        expect(
          successResponse.statusCode,
          200,
          reason: jsonEncode(successResponse.body),
        );
        expect(successResponse.body['accepted'], isTrue);
        expect(await store.listJson('runtime_usage_events'), hasLength(1));
      } finally {
        client.close(force: true);
      }
    },
  );
}

RuntimeReceiptSettlement _developmentSettlement(
  RuntimeReceiptStore store,
  DateTime Function() clock,
) => RuntimeReceiptSettlement(
  store: store,
  policy: DevelopmentRuntimeReceiptPolicy(
    environmentIds: const <String>{'env_accept'},
  ),
  clock: clock,
  random: Random(1),
);

Map<String, Object?> _scopeRequest(
  _Key key, {
  String applicationId = 'app_receipts',
  String environmentId = 'env_accept',
  String runtimeApplicationId = 'com.example.receipts',
  String releaseId = 'release-1',
  String patchId = 'patch-1',
  String artifactDigest = _artifactHex,
  String? installationId,
}) => <String, Object?>{
  'application_id': applicationId,
  'environment_id': environmentId,
  'runtime_application_id': runtimeApplicationId,
  'release_id': releaseId,
  'platform': 'ios-arm64-release',
  'patch_id': patchId,
  'artifact_digest': artifactDigest,
  'installation_id': installationId ?? key.installationId,
  'key_id': key.keyId,
  'public_key': key.publicKey,
};

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw StateError('Expected map');
  return <String, Object?>{
    for (final entry in value.entries) entry.key as String: entry.value,
  };
}

final class _HttpResponse {
  const _HttpResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

Future<_HttpResponse> _post(
  HttpClient client,
  int port,
  String path,
  String token,
  Map<String, Object?> body,
) async {
  final request = await client.postUrl(
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  final bytes = utf8.encode(jsonEncode(body));
  request
    ..headers.contentType = ContentType.json
    ..headers.set(HttpHeaders.authorizationHeader, 'Bearer $token')
    ..contentLength = bytes.length
    ..add(bytes);
  final response = await request.close();
  return _HttpResponse(
    response.statusCode,
    _map(jsonDecode(await response.transform(utf8.decoder).join())),
  );
}

final class _FakeAttestationVerifier implements RuntimeAttestationVerifier {
  final requests = <RuntimeAttestationRequest>[];

  @override
  Future<RuntimeAttestationVerification> verify(
    RuntimeAttestationRequest request,
  ) async {
    requests.add(request);
    return RuntimeAttestationVerification(
      provider: request.evidence.provider,
      trustLevel: RuntimeTrustLevel.attestedApplication,
      verified: true,
      evidenceDigest: request.evidence.digest,
      challengeBindingDigest: sha256Digest(request.canonicalEnrollmentBytes),
    );
  }
}

final class _StaleBindingAttestationVerifier
    implements RuntimeAttestationVerifier {
  String? _firstBindingDigest;

  @override
  Future<RuntimeAttestationVerification> verify(
    RuntimeAttestationRequest request,
  ) async {
    final bindingDigest = _firstBindingDigest ??= sha256Digest(
      request.canonicalEnrollmentBytes,
    );
    return RuntimeAttestationVerification(
      provider: request.evidence.provider,
      trustLevel: RuntimeTrustLevel.attestedApplication,
      verified: true,
      evidenceDigest: request.evidence.digest,
      challengeBindingDigest: bindingDigest,
    );
  }
}

final class _UnavailableAttestationVerifier
    implements RuntimeAttestationVerifier {
  const _UnavailableAttestationVerifier();

  @override
  Future<RuntimeAttestationVerification> verify(
    RuntimeAttestationRequest request,
  ) => throw const RuntimeAttestationException(
    RuntimeAttestationException.unavailable,
    'provider unavailable',
  );
}

final class _UnsafeBillablePolicy implements RuntimeReceiptAcceptancePolicy {
  const _UnsafeBillablePolicy();

  @override
  Future<RuntimeReceiptPolicyDecision> evaluate(
    RuntimeReceiptPolicyInput input,
  ) async => const RuntimeReceiptPolicyDecision(
    accepted: true,
    billable: true,
    trustLevel: RuntimeTrustLevel.attestedApplication,
    reason: 'UNSAFE_TEST_POLICY',
  );
}

final class _Key {
  _Key(
    this.privateKey,
    this.publicPoint,
    this.installationId,
    this.keyId,
    this.publicKeyWire,
  );

  final ECPrivateKey privateKey;
  final ECPublicKey publicPoint;
  final String installationId;
  final String keyId;
  final String publicKeyWire;

  static _Key create(int privateScalar, int installationByte) {
    final curve = ECDomainParameters('prime256v1');
    final privateKey = ECPrivateKey(BigInt.from(privateScalar), curve);
    final publicKey = ECPublicKey(curve.G * BigInt.from(privateScalar), curve);
    final publicBytes = publicKey.Q!.getEncoded(false);
    return _Key(
      privateKey,
      publicKey,
      base64Url
          .encode(List<int>.filled(32, installationByte))
          .replaceAll('=', ''),
      sha256.convert(publicBytes).toString(),
      base64Url.encode(publicBytes).replaceAll('=', ''),
    );
  }

  String get publicKey => publicKeyWire;

  String sign(Map<String, Object?> value) {
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(privateKey));
    final signature = signer.generateSignature(
      Uint8List.fromList(utf8.encode(canonicalJson(value))),
    ) as ECSignature;
    final raw = <int>[..._scalar(signature.r), ..._scalar(signature.s)];
    return base64Url.encode(raw).replaceAll('=', '');
  }

  static List<int> _scalar(BigInt value) => [
    for (var index = 31; index >= 0; index--)
      ((value >> (index * 8)) & BigInt.from(255)).toInt(),
  ];
}
