import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hyfens_flutter_integration/src/install_receipts.dart';
import 'package:hyfens_flutter_integration/src/installation_key.dart';
import 'package:hyfens_flutter_integration/src/runtime_attestation.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2036, 1, 10);
  late _Key key;
  HttpServer? server;
  late HyfensInstallReceipts client;
  var loseResponse = false;
  var wrongScope = false;
  var productionLabel = false;
  var invalidAck = false;
  var mismatchedDeadline = false;
  var streamResponse = false;
  var productionResponse = false;
  var productionTrustLevel = 'ATTESTED_APP';
  var signedEnrollments = 0;
  var receiptAttempts = 0;
  var challengeAttempts = 0;
  final challengeDigests = <String>[];
  final registerDigests = <String>[];
  Map<String, Object?>? registeredEnrollment;
  Map<String, Object?>? registerAttestation;
  final accepted = <String>{};

  setUp(() async {
    key = await _Key.create();
    loseResponse = wrongScope = productionLabel = invalidAck = false;
    mismatchedDeadline = false;
    streamResponse = false;
    productionResponse = false;
    productionTrustLevel = 'ATTESTED_APP';
    signedEnrollments = receiptAttempts = 0;
    challengeAttempts = 0;
    challengeDigests.clear();
    registerDigests.clear();
    registeredEnrollment = null;
    registerAttestation = null;
    accepted.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      try {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer acceptance-only',
        );
        final body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, Object?>;
        Map<String, Object?> response;
        switch (request.uri.path) {
          case '/v1/runtime/installations/challenge':
            challengeAttempts++;
            challengeDigests.add(body['artifact_digest']! as String);
            response = {
              'enrollment': {
                ...body,
                'version': 1,
                'purpose': 'installation_enrollment',
                'challenge_id': 'challenge-1',
                'challenge': 'unpredictable-server-challenge',
                'expires_at': now
                    .add(const Duration(minutes: 5))
                    .toIso8601String(),
                if (wrongScope) 'environment_id': 'production',
              },
              'billable': false,
            };
          case '/v1/runtime/installations/register':
            final enrollment = body['enrollment']! as Map<String, Object?>;
            registeredEnrollment = Map<String, Object?>.from(enrollment);
            registerDigests.add(enrollment['artifact_digest']! as String);
            if (productionResponse) {
              final attestation = body['attestation'];
              expect(attestation, isA<Map<String, Object?>>());
              registerAttestation = Map<String, Object?>.from(
                attestation! as Map<String, Object?>,
              );
            } else {
              expect(body.containsKey('attestation'), isFalse);
            }
            final activationDeadline = now
                .add(const Duration(days: 1))
                .toIso8601String();
            final responseDeadline = mismatchedDeadline
                ? now.add(const Duration(days: 2)).toIso8601String()
                : activationDeadline;
            expect(
              await key.verify(enrollment, body['signature']! as String),
              isTrue,
            );
            signedEnrollments++;
            response = {
              'receipt': {
                for (final field in [
                  'application_id',
                  'environment_id',
                  'runtime_application_id',
                  'release_id',
                  'platform',
                  'patch_id',
                  'artifact_digest',
                  'installation_id',
                  'key_id',
                ])
                  field: enrollment[field],
                'version': 1,
                'receipt_id': 'receipt-${enrollment['patch_id']}',
                'admission_id': 'admission-${enrollment['patch_id']}',
                'challenge': 'receipt-challenge-${enrollment['patch_id']}',
                'runtime_version': HyfensInstallReceipts.runtimeVersion,
                'activation_deadline': activationDeadline,
                'result': 'activated',
              },
              'expires_at': responseDeadline,
              'billable': productionResponse || productionLabel,
              'trust_level': productionResponse
                  ? productionTrustLevel
                  : productionLabel
                  ? 'ATTESTED_APP'
                  : 'DEVELOPMENT_ACCEPTANCE',
            };
          case '/v1/runtime/install-success':
            final unsigned = {...body}..remove('signature');
            expect(
              await key.verify(unsigned, body['signature']! as String),
              isTrue,
            );
            receiptAttempts++;
            final added = accepted.add(body['receipt_id']! as String);
            if (loseResponse) {
              loseResponse = false;
              (await request.response.detachSocket(writeHeaders: false))
                  .destroy();
              return;
            }
            response = {
              'receipt_id': invalidAck ? 'other-receipt' : body['receipt_id'],
              'accepted': true,
              'duplicate': !added,
              'billable': productionResponse,
              'successful_installs': accepted.length,
            };
            if (streamResponse) {
              final bytes = utf8.encode(jsonEncode(response));
              try {
                for (final byte in bytes) {
                  request.response.add(<int>[byte]);
                  await request.response.flush();
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                }
                await request.response.close();
              } on Object {
                // The client closes the response when its total deadline
                // expires.
              }
              return;
            }
          default:
            throw StateError('Unexpected receipt route');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      } catch (error, stack) {
        fail('$error\n$stack');
      }
    });
    client = HyfensInstallReceipts(
      baseUrl: Uri.parse('http://127.0.0.1:${server!.port}'),
      deliveryCredential: 'acceptance-only',
      applicationId: 'app',
      environmentId: 'dev',
      platformId: 'android-arm64-release',
      keyStore: key,
      clock: () => now,
      requestTimeout: const Duration(seconds: 1),
    );
  });
  tearDown(() => server?.close(force: true));

  Future<E1InstallReceiptContext> prepare(
    String patch, {
    String? artifactDigest,
    HyfensInstallReceipts? receiptClient,
  }) => (receiptClient ?? client).prepare(
    runtimeApplicationId: 'example.acceptance',
    releaseId: 'release-1',
    patchId: patch,
    artifactDigest: artifactDigest ?? 'a' * 64,
  );

  test('prepare normalizes prefixed digest to canonical wire form', () async {
    final digest = 'a' * 64;
    final context = await prepare('patch-1', artifactDigest: 'sha256:$digest');

    expect(context.artifactDigest, digest);
    expect(context.body['artifact_digest'], digest);
    expect(challengeDigests, [digest]);
    expect(registerDigests, [digest]);
  });

  test(
    'production registration and acknowledgement retain their classifications',
    () async {
      productionResponse = true;
      final producer = _RecordingAttestationProducer(
        HyfensRuntimeAttestationEvidence.googlePlayIntegrity(
          token: 'opaque-play-integrity-token',
        ),
      );
      final productionClient = HyfensInstallReceipts.production(
        baseUrl: client.baseUrl,
        deliveryCredential: client.deliveryCredential,
        applicationId: client.applicationId,
        environmentId: client.environmentId,
        platformId: client.platformId,
        keyStore: key,
        attestationProducer: producer,
        productionGate: () => true,
        clock: () => now,
        requestTimeout: const Duration(seconds: 1),
      );

      final context = await prepare('patch-1', receiptClient: productionClient);

      expect(producer.calls, 1);
      expect(
        producer.canonicalEnrollmentBytes,
        _canonical(registeredEnrollment!),
      );
      expect(registerAttestation, <String, Object?>{
        'provider': 'google_play_integrity',
        'token': 'opaque-play-integrity-token',
      });
      expect(context.body.containsKey('attestation'), isFalse);
      await productionClient.send(context);
      expect(receiptAttempts, 1);
    },
  );

  test(
    'production registration accepts both exact attested trust levels',
    () async {
      productionResponse = true;
      final producer = _RecordingAttestationProducer(
        HyfensRuntimeAttestationEvidence.googlePlayIntegrity(token: 'token'),
      );
      final productionClient = HyfensInstallReceipts.production(
        baseUrl: client.baseUrl,
        deliveryCredential: client.deliveryCredential,
        applicationId: client.applicationId,
        environmentId: client.environmentId,
        platformId: client.platformId,
        keyStore: key,
        attestationProducer: producer,
        productionGate: () => true,
        clock: () => now,
        requestTimeout: const Duration(seconds: 1),
      );

      await prepare('attested-app', receiptClient: productionClient);
      productionTrustLevel = 'ATTESTED_HARDWARE';
      await prepare('attested-hardware', receiptClient: productionClient);

      expect(registerDigests, hasLength(2));
    },
  );

  test('production registration allows bounded provider evidence', () async {
    productionResponse = true;
    final attestationObject = 'a' * (40 * 1024);
    final productionClient = HyfensInstallReceipts.production(
      baseUrl: client.baseUrl,
      deliveryCredential: client.deliveryCredential,
      applicationId: client.applicationId,
      environmentId: client.environmentId,
      platformId: client.platformId,
      keyStore: key,
      attestationProducer: _RecordingAttestationProducer(
        HyfensRuntimeAttestationEvidence.appleAppAttestInitial(
          keyId: 'app-attest-key',
          attestationObject: attestationObject,
        ),
      ),
      productionGate: () => true,
      clock: () => now,
      requestTimeout: const Duration(seconds: 1),
    );

    await prepare('large-production-evidence', receiptClient: productionClient);

    expect(registerAttestation, <String, Object?>{
      'provider': 'apple_app_attest',
      'key_id': 'app-attest-key',
      'attestation_object': attestationObject,
    });
  });

  test('production attestation is bounded by request timeout', () async {
    final productionClient = HyfensInstallReceipts.production(
      baseUrl: client.baseUrl,
      deliveryCredential: client.deliveryCredential,
      applicationId: client.applicationId,
      environmentId: client.environmentId,
      platformId: client.platformId,
      keyStore: key,
      attestationProducer: _HangingAttestationProducer(),
      productionGate: () => true,
      clock: () => now,
      requestTimeout: const Duration(milliseconds: 100),
    );

    await expectLater(
      prepare('hanging-production-evidence', receiptClient: productionClient),
      throwsA(
        isA<HyfensRuntimeAttestationException>().having(
          (error) => error.code,
          'code',
          HyfensRuntimeAttestationException.unavailable,
        ),
      ),
    );
    expect(signedEnrollments, 0);
    expect(receiptAttempts, 0);
  });

  test('production mode requires an enabled gate before any HTTP', () {
    final producer = _RecordingAttestationProducer(
      HyfensRuntimeAttestationEvidence.googlePlayIntegrity(token: 'token'),
    );

    expect(
      () => HyfensInstallReceipts.production(
        baseUrl: client.baseUrl,
        deliveryCredential: client.deliveryCredential,
        applicationId: client.applicationId,
        environmentId: client.environmentId,
        platformId: client.platformId,
        keyStore: key,
        attestationProducer: producer,
        productionGate: () => false,
      ),
      throwsA(
        isA<HyfensRuntimeAttestationException>().having(
          (error) => error.code,
          'code',
          HyfensRuntimeAttestationException.productionNotEnabled,
        ),
      ),
    );
    expect(challengeAttempts, 0);
  });

  test('invalid artifact digest is rejected before HTTP', () async {
    await expectLater(
      prepare('patch-1', artifactDigest: 'sha256:not-a-digest'),
      throwsA(
        isA<HyfensInstallReceiptException>().having(
          (error) => error.code,
          'code',
          'ARTIFACT_DIGEST_INVALID',
        ),
      ),
    );
    expect(challengeAttempts, 0);
    expect(signedEnrollments, 0);
  });

  test(
    'enrollment possession signature is not a successful installation',
    () async {
      final context = await prepare('patch-1');
      expect(signedEnrollments, 1);
      expect(receiptAttempts, 0);
      expect(accepted, isEmpty);
      await client.send(context);
      await client.send(context);
      expect(receiptAttempts, 2);
      expect(accepted, hasLength(1));
      await client.send(await prepare('patch-2'));
      expect(accepted, hasLength(2));
    },
  );

  test('download proof has its own purpose and cannot be a receipt', () async {
    final context = await prepare('patch-1');
    final proof = await client.downloadProof(context, 'artifact-1');
    final proofBody = <String, Object?>{
      for (final entry in context.body.entries)
        if (entry.key != 'result') entry.key: entry.value,
      'purpose': 'artifact_download',
      'artifact_id': 'artifact-1',
    };

    expect(await key.verify(proofBody, proof), isTrue);
    expect(proofBody.containsKey('result'), isFalse);
    expect(await key.verify(context.body, proof), isFalse);
    expect(proof, isNot(contains('=')));
  });

  test(
    'download proof rejects an expired admission but replay remains sendable',
    () async {
      final context = await prepare('patch-1');
      final expired = E1InstallReceiptContext(
        body: <String, Object?>{
          ...context.body,
          'activation_deadline': now
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
        },
      );

      await expectLater(
        client.downloadProof(expired, 'artifact-1'),
        throwsA(
          isA<HyfensInstallReceiptException>().having(
            (error) => error.code,
            'code',
            'ADMISSION_EXPIRY_INVALID',
          ),
        ),
      );
      await client.send(expired);
      expect(receiptAttempts, 1);
    },
  );

  test(
    'register response must repeat the receipt activation deadline',
    () async {
      mismatchedDeadline = true;

      await expectLater(
        prepare('patch-1'),
        throwsA(
          isA<HyfensInstallReceiptException>().having(
            (error) => error.code,
            'code',
            'ACTIVATION_DEADLINE_MISMATCH',
          ),
        ),
      );
    },
  );

  test(
    'download proof is scoped to the configured installation identity',
    () async {
      final context = await prepare('patch-1');
      final otherClient = HyfensInstallReceipts(
        baseUrl: client.baseUrl,
        deliveryCredential: client.deliveryCredential,
        applicationId: 'other-app',
        environmentId: client.environmentId,
        platformId: client.platformId,
        keyStore: key,
        clock: () => now,
        requestTimeout: const Duration(seconds: 1),
      );

      await expectLater(
        otherClient.downloadProof(context, 'artifact-1'),
        throwsA(
          isA<HyfensInstallReceiptException>().having(
            (error) => error.code,
            'code',
            'RECEIPT_SCOPE_MISMATCH',
          ),
        ),
      );
    },
  );

  test(
    'committed receipt with lost response retries the same identity',
    () async {
      final context = await prepare('patch-1');
      loseResponse = true;
      await expectLater(
        client.send(context),
        throwsA(isA<HyfensInstallReceiptException>()),
      );
      expect(accepted, hasLength(1));
      await client.send(context);
      expect(receiptAttempts, 2);
      expect(accepted, hasLength(1));
    },
  );

  test('receipt response stream has a total deadline', () async {
    final context = await prepare('patch-1');
    streamResponse = true;

    await expectLater(
      client.send(context),
      throwsA(
        isA<HyfensInstallReceiptException>().having(
          (error) => error.code,
          'code',
          'RECEIPT_SERVICE_UNAVAILABLE',
        ),
      ),
    );
  });

  test('cross-environment enrollment is never signed', () async {
    wrongScope = true;
    await expectLater(
      prepare('patch-1'),
      throwsA(isA<HyfensInstallReceiptException>()),
    );
    expect(signedEnrollments, 0);
  });

  test('acceptance cannot silently become production/billable', () async {
    productionLabel = true;
    await expectLater(
      prepare('patch-1'),
      throwsA(isA<HyfensInstallReceiptException>()),
    );
    expect(receiptAttempts, 0);
    expect(
      HyfensInstallReceiptMode.parse('production'),
      HyfensInstallReceiptMode.production,
    );
    expect(
      HyfensInstallReceiptMode.parse(''),
      HyfensInstallReceiptMode.disabled,
    );
  });

  test(
    'unrelated acknowledgement does not acknowledge the queued receipt',
    () async {
      final context = await prepare('patch-1');
      invalidAck = true;
      await expectLater(
        client.send(context),
        throwsA(isA<HyfensInstallReceiptException>()),
      );
    },
  );
}

List<int> _canonical(Map<String, Object?> value) => utf8.encode(
  jsonEncode({for (final key in value.keys.toList()..sort()) key: value[key]}),
);

final class _RecordingAttestationProducer
    implements HyfensRuntimeAttestationEvidenceProducer {
  _RecordingAttestationProducer(this.evidence);

  final HyfensRuntimeAttestationEvidence evidence;
  int calls = 0;
  List<int>? canonicalEnrollmentBytes;

  @override
  Future<HyfensRuntimeAttestationEvidence> produce(
    List<int> canonicalEnrollmentBytes,
  ) async {
    calls++;
    this.canonicalEnrollmentBytes = canonicalEnrollmentBytes;
    return evidence;
  }
}

final class _HangingAttestationProducer
    implements HyfensRuntimeAttestationEvidenceProducer {
  @override
  Future<HyfensRuntimeAttestationEvidence> produce(
    List<int> canonicalEnrollmentBytes,
  ) => Completer<HyfensRuntimeAttestationEvidence>().future;
}

final class _Key implements HyfensInstallationKeyStore {
  _Key(this.private, this.public, this.identity);
  final ECPrivateKey private;
  final ECPublicKey public;
  final HyfensInstallationIdentity identity;

  static Future<_Key> create() async {
    // Public deterministic TEST key only. Production keys are native-only.
    final curve = ECDomainParameters('prime256v1');
    final private = ECPrivateKey(BigInt.two, curve);
    final public = ECPublicKey(curve.G * BigInt.two, curve);
    final bytes = public.Q!.getEncoded(false);
    return _Key(
      private,
      public,
      HyfensInstallationIdentity(
        installationId: base64Url
            .encode(List.filled(32, 7))
            .replaceAll('=', ''),
        keyId: sha256.convert(bytes).toString(),
        publicKey: bytes,
        storageProtection:
            HyfensInstallationStorageProtection.platformProtected,
      ),
    );
  }

  @override
  Future<HyfensInstallationIdentity> getIdentity() async => identity;
  @override
  Future<List<int>> sign(List<int> message) async {
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(private));
    final signature =
        signer.generateSignature(Uint8List.fromList(message)) as ECSignature;
    return [..._scalar(signature.r), ..._scalar(signature.s)];
  }

  Future<bool> verify(Map<String, Object?> body, String signature) async {
    final raw = base64Url.decode(base64Url.normalize(signature));
    BigInt integer(List<int> bytes) => bytes.fold(
      BigInt.zero,
      (value, byte) => (value << 8) | BigInt.from(byte),
    );
    final verifier = ECDSASigner(SHA256Digest())
      ..init(false, PublicKeyParameter<ECPublicKey>(public));
    return verifier.verifySignature(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            for (final key in body.keys.toList()..sort()) key: body[key],
          }),
        ),
      ),
      ECSignature(integer(raw.sublist(0, 32)), integer(raw.sublist(32))),
    );
  }

  static List<int> _scalar(BigInt value) => [
    for (var index = 31; index >= 0; index--)
      ((value >> (index * 8)) & BigInt.from(255)).toInt(),
  ];
}
