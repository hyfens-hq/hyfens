import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_flutter_integration/flutter_integration.dart';
import 'package:hyfens_flutter_integration/src/installation_key.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:hyfens_runtime/runtime.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

const _appId = 'dev.hyfens.delivery';
const _releaseId = 'delivery-release-1';
const _buildFingerprint = 'delivery-build-1';
const _keyId = 'delivery-test-key';
const _deliveryToken = 'hfy_delivery_test_token';
const _functionId =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _seed = <int>[
  0x9d,
  0x61,
  0xb1,
  0x9d,
  0xef,
  0xfd,
  0x5a,
  0x60,
  0xba,
  0x84,
  0x4a,
  0xf4,
  0x92,
  0xec,
  0x2c,
  0xc4,
  0x44,
  0x49,
  0xc5,
  0x69,
  0x7b,
  0x32,
  0x69,
  0x19,
  0x70,
  0x3b,
  0xac,
  0x03,
  0x1c,
  0xae,
  0x7f,
  0x60,
];

void main() {
  late Directory storage;
  late E1PatchController controller;
  late _FakeDeliveryServer server;
  late HyfensControlPlaneDelivery adapter;

  setUp(() async {
    storage = await Directory.systemTemp.createTemp('hyfens-control-delivery-');
    final publicKey = await _publicKey();
    controller = E1PatchController(
      storageDirectory: storage,
      appId: _appId,
      releaseId: _releaseId,
      buildFingerprint: _buildFingerprint,
      functions: const <String, int>{_functionId: 0},
      signatures: <String, String>{
        _functionId: E0FunctionSignature.legacyInt2.encode(),
      },
      receivers: <String, String>{
        _functionId: E0ReceiverDescriptor.none.encode(),
      },
      patchUri: Uri.parse('http://127.0.0.1:1/unused'),
      trustedPublicKeys: <String, E1TrustedPublicKey>{
        _keyId: E1TrustedPublicKey(keyId: _keyId, bytes: publicKey),
      },
    );
    E0PatchRuntime.reset();
    await controller.initialize();
    server = _FakeDeliveryServer(
      patchBytes: await _patchFormatArtifact(sequence: 1),
    );
    await server.start();
    adapter = HyfensControlPlaneDelivery(
      HyfensControlPlaneConfiguration(
        baseUrl: server.baseUrl,
        deliveryCredential: _deliveryToken,
        applicationId: 'app_delivery',
        environmentId: 'env_delivery',
        platformId: 'android-arm64-release',
        requestTimeout: const Duration(milliseconds: 250),
      ),
    );
  });

  tearDown(() async {
    await server.close();
    await controller.close();
    E0PatchRuntime.reset();
    await storage.delete(recursive: true);
  });

  group('credential-bearing transport policy', () {
    HyfensControlPlaneConfiguration configurationFor(Uri baseUrl) =>
        HyfensControlPlaneConfiguration(
          baseUrl: baseUrl,
          deliveryCredential: _deliveryToken,
          applicationId: 'app_delivery',
          environmentId: 'env_delivery',
          platformId: 'android-arm64-release',
        );

    test('allows remote HTTPS endpoints', () {
      final configuration = configurationFor(
        Uri.parse('https://api.example.com/p2/'),
      );

      expect(configuration.baseUrl, Uri.parse('https://api.example.com/p2/'));
    });

    test('allows HTTP only for explicit loopback endpoints', () {
      for (final endpoint in <Uri>[
        Uri.parse('http://localhost:18081/p2/'),
        Uri.parse('http://127.0.0.1:18081/p2/'),
        Uri.parse('http://[::1]:18081/p2/'),
      ]) {
        expect(configurationFor(endpoint).baseUrl, endpoint);
      }
    });

    test('rejects remote HTTP endpoints', () {
      expect(
        () => configurationFor(Uri.parse('http://api.example.com/p2/')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('configuration errors do not echo URL or credential secrets', () {
      const secret = 'config-secret-sentinel';
      final urlWithSecret = Uri.parse(
        'https://user:$secret@api.example.com/p2/?token=$secret',
      );

      for (final invalid in <Object Function()>[
        () => HyfensControlPlaneConfiguration(
          baseUrl: urlWithSecret,
          deliveryCredential: _deliveryToken,
          applicationId: 'app_delivery',
          environmentId: 'env_delivery',
          platformId: 'android-arm64-release',
        ),
        () => HyfensControlPlaneConfiguration(
          baseUrl: Uri.parse('https://api.example.com/p2/'),
          deliveryCredential: '$secret\n',
          applicationId: 'app_delivery',
          environmentId: 'env_delivery',
          platformId: 'android-arm64-release',
        ),
      ]) {
        try {
          invalid();
          fail('invalid configuration unexpectedly succeeded');
        } on ArgumentError catch (error) {
          expect(error.toString(), isNot(contains(secret)));
          expect(error.toString(), isNot(contains(urlWithSecret.toString())));
        }
      }
    });
  });

  test('authenticated lookup/fetch hands exact bytes to E1', () async {
    final result = await adapter.deliver(controller);

    expect(result.decision, HyfensDeliveryDecision.patchAvailable);
    expect(result.activated, isTrue);
    expect(result.sequence, 1);
    expect(controller.status.phase, 'pendingHealth');
    expect(controller.durableState.highWaterSequence, 1);
    expect(await controller.markHealthy(), isTrue);
    expect(controller.status.phase, 'healthy');
    expect(server.authorizationHeaders, [
      'Bearer $_deliveryToken',
      'Bearer $_deliveryToken',
    ]);
    expect(server.lookupBody['application_id'], 'app_delivery');
    expect(server.lookupBody['environment_id'], 'env_delivery');
    expect(server.lookupBody['platform'], 'android-arm64-release');
    expect(server.lookupBody['high_water_sequence'], 0);

    server.mode = _DeliveryMode.noUpdate;
    final noUpdate = await adapter.deliver(controller);
    expect(noUpdate.decision, HyfensDeliveryDecision.noUpdate);
    expect(controller.durableState.highWaterSequence, 1);
  });

  test(
    'healthy artifact does not prepare a second receipt admission',
    () async {
      final first = await adapter.deliver(controller);
      expect(first.activated, isTrue);
      expect(await controller.markHealthy(), isTrue);
      final fetchesBeforeReceiptDelivery = server.artifactFetchCount;

      final receiptAdapter = HyfensControlPlaneDelivery(
        HyfensControlPlaneConfiguration(
          baseUrl: server.baseUrl,
          deliveryCredential: _deliveryToken,
          applicationId: 'app_delivery',
          environmentId: 'env_delivery',
          platformId: 'android-arm64-release',
          requestTimeout: const Duration(milliseconds: 250),
          receiptMode: HyfensInstallReceiptMode.developmentAcceptance,
        ),
        receipts: HyfensInstallReceipts(
          baseUrl: server.baseUrl,
          deliveryCredential: _deliveryToken,
          applicationId: 'app_delivery',
          environmentId: 'env_delivery',
          platformId: 'android-arm64-release',
          keyStore: _UnexpectedReceiptKeyStore(),
          requestTimeout: const Duration(milliseconds: 250),
        ),
      );

      final result = await receiptAdapter.deliver(controller);
      expect(result.activated, isTrue);
      expect(controller.durableState.health, 'healthy');
      expect(server.artifactFetchCount, fetchesBeforeReceiptDelivery);
    },
  );

  test(
    'artifact proof headers survive one retry without a second admission',
    () async {
      final receiptKey = await _ProofKey.create();
      server.receiptKey = receiptKey;
      server.verifyDownloadProof = true;
      server.artifactFailuresRemaining = 1;
      final receiptAdapter = HyfensControlPlaneDelivery(
        HyfensControlPlaneConfiguration(
          baseUrl: server.baseUrl,
          deliveryCredential: _deliveryToken,
          applicationId: 'app_delivery',
          environmentId: 'env_delivery',
          platformId: 'android-arm64-release',
          requestTimeout: const Duration(milliseconds: 250),
          receiptMode: HyfensInstallReceiptMode.developmentAcceptance,
        ),
        receipts: HyfensInstallReceipts(
          baseUrl: server.baseUrl,
          deliveryCredential: _deliveryToken,
          applicationId: 'app_delivery',
          environmentId: 'env_delivery',
          platformId: 'android-arm64-release',
          keyStore: receiptKey,
          requestTimeout: const Duration(milliseconds: 250),
        ),
      );

      final result = await receiptAdapter.deliver(controller);

      expect(result.activated, isTrue);
      expect(controller.durableState.health, 'pending');
      expect(server.receiptAdmissions, 1);
      expect(server.artifactFetchCount, 2);
      expect(server.artifactMethods, ['GET', 'GET']);
      // HttpClient omits Content-Length for an empty GET, which the fixture
      // exposes as -1; either representation is bodyless.
      expect(
        server.artifactContentLengths.every((length) => length <= 0),
        isTrue,
      );
      expect(server.downloadProofValid, [true, true]);
      expect(server.downloadAdmissions.toSet(), hasLength(1));
      expect(server.downloadProofs.toSet(), hasLength(1));
      expect(server.installSuccessCount, 0);
    },
  );

  test('streaming lookup response has a total deadline', () async {
    server.mode = _DeliveryMode.streamTimeout;

    await expectLater(
      adapter.deliver(controller),
      throwsA(
        isA<HyfensControlPlaneDeliveryException>().having(
          (error) => error.code,
          'code',
          'DELIVERY_TIMEOUT',
        ),
      ),
    );
    expect(controller.durableState.highWaterSequence, 0);
  });

  test('oversized lookup response is rejected before buffering', () async {
    server.mode = _DeliveryMode.oversizedLookup;

    await expectLater(
      adapter.deliver(controller),
      throwsA(
        isA<HyfensControlPlaneDeliveryException>().having(
          (error) => error.code,
          'code',
          'RESPONSE_TOO_LARGE',
        ),
      ),
    );
    expect(controller.durableState.highWaterSequence, 0);
  });

  test(
    'blocked and store-release decisions do not touch runtime state',
    () async {
      for (final mode in <_DeliveryMode>[
        _DeliveryMode.blocked,
        _DeliveryMode.storeReleaseRequired,
      ]) {
        server.mode = mode;
        final result = await adapter.deliver(controller);
        expect(result.activated, isFalse);
        expect(controller.status.mode, E1PatchMode.base);
        expect(controller.durableState.highWaterSequence, 0);
      }
    },
  );

  test(
    'lookup and artifact failures preserve BASE and durable state',
    () async {
      for (final mode in <_DeliveryMode>[
        _DeliveryMode.lookup404,
        _DeliveryMode.artifact404,
        _DeliveryMode.truncatedArtifact,
        _DeliveryMode.wrongDigest,
        _DeliveryMode.timeout,
      ]) {
        server.mode = mode;
        await expectLater(
          adapter.deliver(controller),
          throwsA(isA<HyfensControlPlaneDeliveryException>()),
        );
        expect(controller.status.mode, E1PatchMode.base, reason: '$mode');
        expect(controller.durableState.highWaterSequence, 0, reason: '$mode');
        server.mode = _DeliveryMode.patch;
      }
    },
  );

  test(
    'wrong-release bytes are handed to E1 and rejected independently',
    () async {
      server.mode = _DeliveryMode.wrongRelease;
      final result = await adapter.deliver(controller);

      expect(result.decision, HyfensDeliveryDecision.patchAvailable);
      expect(result.activated, isFalse);
      expect(controller.status.phase, 'rejected');
      expect(controller.status.mode, E1PatchMode.base);
      expect(controller.durableState.highWaterSequence, 0);
    },
  );

  test(
    'a mismatched platform response is rejected before activation',
    () async {
      server.mode = _DeliveryMode.wrongPlatform;

      await expectLater(
        adapter.deliver(controller),
        throwsA(
          isA<HyfensControlPlaneDeliveryException>().having(
            (error) => error.code,
            'code',
            'PLATFORM_ID_MISMATCH',
          ),
        ),
      );
      expect(controller.status.mode, E1PatchMode.base);
      expect(controller.durableState.highWaterSequence, 0);
    },
  );

  test(
    'service unavailable during artifact fetch does not clear a healthy patch',
    () async {
      final first = await adapter.deliver(controller);
      expect(first.activated, isTrue);
      expect(await controller.markHealthy(), isTrue);
      expect(controller.durableState.highWaterSequence, 1);

      server.mode = _DeliveryMode.artifactUnavailable;
      await expectLater(
        adapter.deliver(controller),
        throwsA(isA<HyfensControlPlaneDeliveryException>()),
      );
      expect(controller.status.mode, E1PatchMode.patch);
      expect(controller.durableState.highWaterSequence, 1);
    },
  );

  test(
    'exact stale bytes reach E1 after rollback and high-water rejects them',
    () async {
      final first = await adapter.deliver(controller);
      expect(first.activated, isTrue);
      expect(await controller.markHealthy(), isTrue);
      expect(await controller.rollback(), isTrue);
      expect(controller.status.mode, E1PatchMode.base);
      expect(controller.durableState.highWaterSequence, 1);

      server.mode = _DeliveryMode.staleSequence;
      final stale = await adapter.deliver(controller);

      expect(stale.decision, HyfensDeliveryDecision.patchAvailable);
      expect(stale.activated, isFalse);
      expect(controller.status.phase, 'rejected');
      expect(controller.status.mode, E1PatchMode.base);
      expect(controller.durableState.highWaterSequence, 1);
      expect(server.artifactFetchCount, greaterThanOrEqualTo(2));
    },
  );

  test(
    'connection refusal is bounded and does not expose the credential',
    () async {
      await server.close();

      await expectLater(
        adapter.deliver(controller),
        throwsA(
          isA<HyfensControlPlaneDeliveryException>().having(
            (error) => error.code,
            'code',
            'DELIVERY_UNAVAILABLE',
          ),
        ),
      );
      expect(controller.durableState.highWaterSequence, 0);
      expect(
        server.authorizationHeaders.join('\n'),
        isNot(contains(_deliveryToken)),
      );
    },
  );
}

enum _DeliveryMode {
  patch,
  noUpdate,
  blocked,
  storeReleaseRequired,
  lookup404,
  artifact404,
  truncatedArtifact,
  wrongDigest,
  wrongRelease,
  wrongPlatform,
  timeout,
  streamTimeout,
  oversizedLookup,
  artifactUnavailable,
  staleSequence,
}

final class _FakeDeliveryServer {
  _FakeDeliveryServer({required this.patchBytes});

  final List<int> patchBytes;
  final authorizationHeaders = <String>[];
  final artifactMethods = <String>[];
  final artifactContentLengths = <int>[];
  final downloadAdmissions = <String>[];
  final downloadProofs = <String>[];
  final downloadProofValid = <bool>[];
  Map<String, Object?> lookupBody = const <String, Object?>{};
  _DeliveryMode mode = _DeliveryMode.patch;
  HttpServer? _server;
  int artifactFetchCount = 0;
  int artifactFailuresRemaining = 0;
  int receiptAdmissions = 0;
  int installSuccessCount = 0;
  _ProofKey? receiptKey;
  bool verifyDownloadProof = false;

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server!.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    authorizationHeaders.add(
      request.headers.value(HttpHeaders.authorizationHeader) ?? '',
    );
    if (request.uri.path == '/v1/runtime/installations/challenge') {
      await _receiptChallenge(request);
      return;
    }
    if (request.uri.path == '/v1/runtime/installations/register') {
      await _receiptRegister(request);
      return;
    }
    if (request.uri.path == '/v1/runtime/install-success') {
      await _receiptSuccess(request);
      return;
    }
    if (request.uri.path == '/v1/runtime/update-check') {
      await _lookup(request);
      return;
    }
    if (request.uri.path.startsWith('/v1/runtime/artifacts/')) {
      await _artifact(request);
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  Future<Map<String, Object?>> _requestBody(HttpRequest request) async =>
      jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, Object?>;

  Future<void> _writeJson(
    HttpRequest request,
    Map<String, Object?> body,
  ) async {
    final bytes = utf8.encode(jsonEncode(body));
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.contentLength = bytes.length
      ..add(bytes);
    await request.response.close();
  }

  Future<void> _receiptChallenge(HttpRequest request) async {
    final body = await _requestBody(request);
    final artifactDigest = body['artifact_digest'];
    if (artifactDigest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(artifactDigest)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    await _writeJson(request, <String, Object?>{
      'enrollment': <String, Object?>{
        ...body,
        'version': 1,
        'purpose': 'installation_enrollment',
        'challenge_id': 'delivery-challenge',
        'challenge': 'delivery-server-challenge',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
      },
      'billable': false,
    });
  }

  Future<void> _receiptRegister(HttpRequest request) async {
    final body = await _requestBody(request);
    final enrollment = body['enrollment']! as Map<String, Object?>;
    final signature = body['signature']! as String;
    final key = receiptKey;
    if (key == null || !await key.verify(enrollment, signature)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    receiptAdmissions++;
    final activationDeadline = DateTime.now()
        .toUtc()
        .add(const Duration(days: 1))
        .toIso8601String();
    final receipt = <String, Object?>{
      'version': 1,
      'receipt_id': 'receipt-${enrollment['patch_id']}',
      'installation_id': enrollment['installation_id'],
      'key_id': enrollment['key_id'],
      'application_id': enrollment['application_id'],
      'environment_id': enrollment['environment_id'],
      'release_id': enrollment['release_id'],
      'runtime_application_id': enrollment['runtime_application_id'],
      'platform': enrollment['platform'],
      'patch_id': enrollment['patch_id'],
      'artifact_digest': enrollment['artifact_digest'],
      'admission_id': 'admission-${enrollment['patch_id']}',
      'challenge': 'receipt-challenge-${enrollment['patch_id']}',
      'runtime_version': HyfensInstallReceipts.runtimeVersion,
      'activation_deadline': activationDeadline,
      'result': 'activated',
    };
    lastReceipt = receipt;
    await _writeJson(request, <String, Object?>{
      'receipt': receipt,
      'expires_at': activationDeadline,
      'billable': false,
      'trust_level': 'DEVELOPMENT_ACCEPTANCE',
    });
  }

  Future<void> _receiptSuccess(HttpRequest request) async {
    await _requestBody(request);
    installSuccessCount++;
    await _writeJson(request, <String, Object?>{
      'receipt_id': 'accepted',
      'accepted': true,
      'billable': false,
    });
  }

  Map<String, Object?>? lastReceipt;

  Future<void> _lookup(HttpRequest request) async {
    if (mode == _DeliveryMode.timeout) {
      await Future<void>.delayed(const Duration(seconds: 1));
      await request.response.close();
      return;
    }
    if (mode == _DeliveryMode.streamTimeout) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..add(utf8.encode('{"decision":'));
      await request.response.flush();
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        await request.response.close();
      } on Object {
        // The client closes the response when its total deadline expires.
      }
      return;
    }
    if (mode == _DeliveryMode.oversizedLookup) {
      final bytes = List<int>.filled(256 * 1024 + 1, 0x20);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..headers.contentLength = bytes.length
        ..add(bytes);
      await request.response.close();
      return;
    }
    if (mode == _DeliveryMode.lookup404) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final body = await utf8.decoder.bind(request).join();
    lookupBody = jsonDecode(body) as Map<String, Object?>;
    final decision = switch (mode) {
      _DeliveryMode.noUpdate => 'NO_UPDATE',
      _DeliveryMode.blocked => 'UPDATE_BLOCKED',
      _DeliveryMode.storeReleaseRequired => 'STORE_RELEASE_REQUIRED',
      _ => 'PATCH_AVAILABLE',
    };
    final artifact = mode == _DeliveryMode.wrongDigest
        ? patchBytes
        : await _artifactBytesForMode();
    final digest = _digest(artifact);
    final response = <String, Object?>{
      'decision': decision,
      'runtimeReleaseId': _releaseId,
      'platformId': mode == _DeliveryMode.wrongPlatform
          ? 'ios-arm64-release'
          : 'android-arm64-release',
      if (decision == 'PATCH_AVAILABLE') ...<String, Object?>{
        'patch': <String, Object?>{
          'runtimePatchId': 'delivery-patch-1',
          'sequence': mode == _DeliveryMode.staleSequence ? 1 : 1,
          'sha256': digest,
        },
        'artifact': <String, Object?>{
          'id': 'artifact-delivery-1',
          'sha256': digest,
          'sizeBytes': artifact.length,
        },
      },
    };
    final bytes = utf8.encode(jsonEncode(response));
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  }

  Future<void> _artifact(HttpRequest request) async {
    artifactFetchCount++;
    artifactMethods.add(request.method);
    artifactContentLengths.add(request.contentLength);
    final admission = request.headers.value('X-Hyfens-Install-Admission');
    final proof = request.headers.value('X-Hyfens-Install-Proof');
    if (admission != null) downloadAdmissions.add(admission);
    if (proof != null) downloadProofs.add(proof);
    final artifactId = Uri.decodeComponent(
      request.uri.path.substring('/v1/runtime/artifacts/'.length),
    );
    if (verifyDownloadProof) {
      final receipt = lastReceipt;
      final key = receiptKey;
      final valid =
          receipt != null &&
          key != null &&
          admission == receipt['admission_id'] &&
          proof != null &&
          await key.verify(_downloadProofBody(receipt, artifactId), proof);
      downloadProofValid.add(valid);
      if (!valid) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
    }
    if (artifactFailuresRemaining > 0) {
      artifactFailuresRemaining--;
      try {
        (await request.response.detachSocket(writeHeaders: false)).destroy();
      } on Object {
        // The client is expected to retry this deliberately dropped response.
      }
      return;
    }
    if (mode == _DeliveryMode.artifact404 ||
        mode == _DeliveryMode.artifactUnavailable) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final artifact = await _artifactBytesForMode();
    final digest = _digest(artifact);
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('application', 'octet-stream')
      ..headers.set('ETag', '"$digest"')
      ..headers.set('Digest', digest);
    if (mode == _DeliveryMode.truncatedArtifact) {
      request.response.headers.contentLength = artifact.length;
      request.response.add(artifact.sublist(0, artifact.length ~/ 2));
      try {
        await request.response.close();
      } on Object {
        // Deliberately violate the declared length; the client must fail
        // closed and the fixture server must not turn that into test noise.
      }
      return;
    }
    request.response
      ..headers.contentLength = artifact.length
      ..add(artifact);
    await request.response.close();
  }

  static Map<String, Object?> _downloadProofBody(
    Map<String, Object?> receipt,
    String artifactId,
  ) => <String, Object?>{
    for (final entry in receipt.entries)
      if (entry.key != 'result') entry.key: entry.value,
    'purpose': 'artifact_download',
    'artifact_id': artifactId,
  };

  Future<List<int>> _artifactBytesForMode() async {
    if (mode == _DeliveryMode.wrongDigest) {
      return <int>[...patchBytes, 0x01];
    }
    if (mode == _DeliveryMode.wrongRelease) {
      return _patchFormatArtifact(sequence: 1, releaseId: 'other-release');
    }
    return patchBytes;
  }
}

Future<List<int>> _publicKey() async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(_seed);
  try {
    return (await keyPair.extractPublicKey()).bytes;
  } finally {
    keyPair.destroy();
  }
}

Future<List<int>> _patchFormatArtifact({
  required int sequence,
  String releaseId = _releaseId,
}) async {
  final e0Bytes = _compile(sequence, releaseId: releaseId);
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: _appId,
    releaseId: releaseId,
    patchId: 'delivery-patch-$sequence',
    sequence: sequence,
    functions: <PatchFunctionEntry>[
      PatchFunctionEntry(
        id: _functionId,
        slot: 0,
        signatureDigest: 'sha256:${'0' * 64}',
      ),
    ],
    capabilities: const <PatchCapabilityEntry>[],
    constants: const <PatchValue>[PatchValue.string('delivery-test')],
    instructions: const <int>[0],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: _keyId,
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
    extensions: <PatchExtensionSection>[
      PatchExtensionSection(
        type: patchFormatV1E0BridgeExtensionType,
        flags: 0,
        payload: utf8.encode(
          jsonEncode(<String, Object?>{
            'bridgeVersion': 1,
            'encoding': 'e0-patch-container-v9-bytes',
            'functions': <String, String>{_functionId: base64.encode(e0Bytes)},
          }),
        ),
      ),
    ],
  );
  final algorithm = DartEd25519();
  final keyPair = await algorithm.newKeyPairFromSeed(_seed);
  try {
    final artifact = await PatchFormatV1.sealAsync(draft, (bytes) async {
      final signature = await algorithm.sign(bytes, keyPair: keyPair);
      return signature.bytes;
    });
    return PatchFormatV1.encode(artifact);
  } finally {
    keyPair.destroy();
  }
}

List<int> _compile(int sequence, {required String releaseId}) {
  final identity = E0Identity().declaration(
    canonicalLibraryUri: 'package:delivery/main.dart',
    declarationName: 'calculatePrice',
  );
  final manifest = E0ReleaseManifest(
    appId: _appId,
    releaseId: releaseId,
    buildFingerprint: _buildFingerprint,
    canonicalLibraryUri: 'package:delivery/main.dart',
    logicalLibraryPath: 'lib/main.dart',
    functions: <E0FunctionManifest>[
      E0FunctionManifest(
        name: 'calculatePrice',
        identity: identity,
        id: _functionId,
        slot: 0,
        signature: E0FunctionSignature.legacyInt2,
        receiver: E0ReceiverDescriptor.none,
      ),
    ],
  );
  return E0PatchCompiler().compile(
    source: '''
int calculatePrice(int quantity, int tier) {
  if (tier == 2) return quantity * 80;
  return quantity * 70;
}
''',
    manifest: manifest,
    functionName: 'calculatePrice',
    patchSequence: sequence,
  );
}

String _digest(List<int> bytes) => 'sha256:${sha256.convert(bytes).toString()}';

final class _UnexpectedReceiptKeyStore implements HyfensInstallationKeyStore {
  @override
  Future<HyfensInstallationIdentity> getIdentity() async {
    throw StateError('receipt admission was unexpectedly prepared');
  }

  @override
  Future<List<int>> sign(List<int> canonicalMessage) async {
    throw StateError('receipt admission was unexpectedly signed');
  }
}

final class _ProofKey implements HyfensInstallationKeyStore {
  _ProofKey(this.private, this.public, this.identity);

  final ECPrivateKey private;
  final ECPublicKey public;
  final HyfensInstallationIdentity identity;

  static Future<_ProofKey> create() async {
    final curve = ECDomainParameters('prime256v1');
    final private = ECPrivateKey(BigInt.from(3), curve);
    final public = ECPublicKey(curve.G * BigInt.from(3), curve);
    final publicBytes = public.Q!.getEncoded(false);
    return _ProofKey(
      private,
      public,
      HyfensInstallationIdentity(
        installationId: base64Url
            .encode(List.filled(32, 9))
            .replaceAll('=', ''),
        keyId: sha256.convert(publicBytes).toString(),
        publicKey: publicBytes,
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

  Future<bool> verify(Map<String, Object?> body, String encoded) async {
    try {
      final raw = base64Url.decode(base64Url.normalize(encoded));
      if (raw.length != 64) return false;
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
    } on Object {
      return false;
    }
  }

  static List<int> _scalar(BigInt value) => [
    for (var index = 31; index >= 0; index--)
      ((value >> (index * 8)) & BigInt.from(255)).toInt(),
  ];
}
