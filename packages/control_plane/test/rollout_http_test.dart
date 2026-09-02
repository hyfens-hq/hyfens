import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:test/test.dart';

const _publicKeyId = 'rollout-http-test-key';

void main() {
  late _Fixture fixture;
  late ControlPlaneHttpServer adapter;
  late HttpServer server;

  setUp(() async {
    fixture = await _Fixture.create();
    adapter = ControlPlaneHttpServer(fixture.service);
    server = await adapter.bind();
  });

  tearDown(() async {
    await adapter.close(force: true);
    await fixture.dispose();
  });

  test('create, inspect, transition, replay, and stale revision use the rollout boundary', () async {
    final client = HttpClient();
    try {
      final createBody = <String, Object?>{
        'organization_id': fixture.bootstrap.organization.id,
        'application_id': fixture.bootstrap.application.id,
        'environment_id': fixture.bootstrap.environment.id,
        'platform_id': fixture.release.platformId,
        'release_id': fixture.release.id,
        'patch_id': fixture.patch.id,
        'percentage_basis_points': 2500,
        'cohort_kind': 'percentage',
        'internal_installation_hashes': <String>[],
      };
      final created = await _request(
        client,
        server.port,
        method: 'POST',
        path: '/v1/rollouts',
        token: fixture.bootstrap.controlCredential.token,
        idempotencyKey: 'http-rollout-create',
        body: createBody,
      );
      expect(created.statusCode, 201, reason: jsonEncode(created.body));
      expect(
        (created.body['revision']! as Map<String, Object?>)['state'],
        'DRAFT',
      );
      final rolloutId =
          (created.body['rollout']! as Map<String, Object?>)['id']! as String;

      final replay = await _request(
        client,
        server.port,
        method: 'POST',
        path: '/v1/rollouts',
        token: fixture.bootstrap.controlCredential.token,
        idempotencyKey: 'http-rollout-create',
        body: createBody,
      );
      expect(replay.statusCode, 201, reason: jsonEncode(replay.body));
      expect(
        (replay.body['rollout']! as Map<String, Object?>)['id'],
        rolloutId,
      );

      final missingAuth = await _request(
        client,
        server.port,
        method: 'GET',
        path:
            '/v1/rollouts/$rolloutId?organization_id=${fixture.bootstrap.organization.id}',
      );
      expect(missingAuth.statusCode, 401);

      final inspected = await _request(
        client,
        server.port,
        method: 'GET',
        path:
            '/v1/rollouts/$rolloutId?organization_id=${fixture.bootstrap.organization.id}',
        token: fixture.bootstrap.controlCredential.token,
      );
      expect(inspected.statusCode, 200, reason: jsonEncode(inspected.body));
      expect(
        (inspected.body['rollout']! as Map<String, Object?>)['id'],
        rolloutId,
      );

      final forbidden = await _request(
        client,
        server.port,
        method: 'GET',
        path:
            '/v1/rollouts/$rolloutId?organization_id=${fixture.bootstrap.organization.id}',
        token: fixture.bootstrap.deliveryCredential.token,
      );
      expect(forbidden.statusCode, 403);

      final transitionBody = <String, Object?>{
        'action': 'ready',
        'expected_revision': 1,
        'reason': 'prepare staged rollout',
        'organization_id': fixture.bootstrap.organization.id,
      };
      final transitioned = await _request(
        client,
        server.port,
        method: 'POST',
        path: '/v1/rollouts/$rolloutId/actions',
        token: fixture.bootstrap.controlCredential.token,
        idempotencyKey: 'http-rollout-ready',
        body: transitionBody,
      );
      expect(
        transitioned.statusCode,
        200,
        reason: jsonEncode(transitioned.body),
      );
      expect(
        (transitioned.body['revision']! as Map<String, Object?>)['state'],
        'READY',
      );

      final transitionReplay = await _request(
        client,
        server.port,
        method: 'POST',
        path: '/v1/rollouts/$rolloutId/actions',
        token: fixture.bootstrap.controlCredential.token,
        idempotencyKey: 'http-rollout-ready',
        body: transitionBody,
      );
      expect(
        transitionReplay.statusCode,
        200,
        reason: jsonEncode(transitionReplay.body),
      );
      expect(
        (transitionReplay.body['rollout']!
            as Map<String, Object?>)['currentRevision'],
        2,
      );

      final stale = await _request(
        client,
        server.port,
        method: 'POST',
        path: '/v1/rollouts/$rolloutId/actions',
        token: fixture.bootstrap.controlCredential.token,
        idempotencyKey: 'http-rollout-stale',
        body: <String, Object?>{
          'action': 'startCanary',
          'expected_revision': 1,
          'reason': 'stale operator request',
          'organization_id': fixture.bootstrap.organization.id,
        },
      );
      expect(stale.statusCode, 409, reason: jsonEncode(stale.body));
      expect(
        (stale.body['error']! as Map<String, Object?>)['code'],
        'PRECONDITION_FAILED',
      );
    } finally {
      client.close(force: true);
    }
  });

  test(
    'rollout create rejects unsupported body fields and missing idempotency',
    () async {
      final client = HttpClient();
      try {
        final body = <String, Object?>{
          'organization_id': fixture.bootstrap.organization.id,
          'application_id': fixture.bootstrap.application.id,
          'environment_id': fixture.bootstrap.environment.id,
          'platform_id': fixture.release.platformId,
          'release_id': fixture.release.id,
          'patch_id': fixture.patch.id,
          'percentage_basis_points': 100,
          'cohort_kind': 'percentage',
          'internal_installation_hashes': <String>[],
          'unsupported': true,
        };
        final unsupported = await _request(
          client,
          server.port,
          method: 'POST',
          path: '/v1/rollouts',
          token: fixture.bootstrap.controlCredential.token,
          idempotencyKey: 'http-rollout-invalid-body',
          body: body,
        );
        expect(unsupported.statusCode, 400);
        expect(
          (unsupported.body['error']! as Map<String, Object?>)['code'],
          'INVALID_REQUEST',
        );

        final create = await _request(
          client,
          server.port,
          method: 'POST',
          path: '/v1/rollouts',
          token: fixture.bootstrap.controlCredential.token,
          idempotencyKey: 'http-rollout-missing-idempotency-source',
          body: Map<String, Object?>.from(body)..remove('unsupported'),
        );
        expect(create.statusCode, 201);
        final rolloutId =
            (create.body['rollout']! as Map<String, Object?>)['id']! as String;
        final missingIdempotency = await _request(
          client,
          server.port,
          method: 'POST',
          path: '/v1/rollouts/$rolloutId/actions',
          token: fixture.bootstrap.controlCredential.token,
          body: <String, Object?>{
            'action': 'ready',
            'expected_revision': 1,
            'reason': 'missing key',
            'organization_id': fixture.bootstrap.organization.id,
          },
        );
        expect(missingIdempotency.statusCode, 400);
        expect(
          (missingIdempotency.body['error']! as Map<String, Object?>)['code'],
          'IDEMPOTENCY_REQUIRED',
        );
      } finally {
        client.close(force: true);
      }
    },
  );
}

Future<_Response> _request(
  HttpClient client,
  int port, {
  required String method,
  required String path,
  String? token,
  String? idempotencyKey,
  Map<String, Object?>? body,
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  request.headers.set('X-Request-Id', 'rollout-http-test');
  if (token != null) request.headers.set('Authorization', 'Bearer $token');
  if (idempotencyKey != null) {
    request.headers.set('Idempotency-Key', idempotencyKey);
  }
  if (body != null) {
    final encoded = utf8.encode(jsonEncode(body));
    request
      ..headers.contentType = ContentType.json
      ..headers.contentLength = encoded.length;
    request.add(encoded);
  }
  final response = await request.close();
  final source = await response.transform(utf8.decoder).join();
  final decoded = source.isEmpty
      ? <String, Object?>{}
      : jsonDecode(source) as Map<String, Object?>;
  return _Response(response.statusCode, decoded);
}

final class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

final class _Fixture {
  _Fixture({
    required this.directory,
    required this.service,
    required this.bootstrap,
  });

  final Directory directory;
  final ControlPlaneService service;
  final BootstrapResult bootstrap;
  late final ReleaseRecord release;
  late final PatchRecord patch;

  static Future<_Fixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'hyfens-rollout-http-',
    );
    final service = ControlPlaneService(
      store: FileControlPlaneStore(directory),
      random: Random(89),
    );
    final bootstrap = await service.bootstrap(
      organizationName: 'Rollout HTTP organization',
      runtimeApplicationId: 'com.example.rollout.http',
      platformId: 'android-arm64-release',
      environmentName: 'development',
    );
    final publicKey = await _publicKey();
    final release = await service.registerRelease(
      token: bootstrap.controlCredential.token,
      idempotencyKey: 'http-fixture-release',
      spec: ReleaseSpec(
        applicationId: bootstrap.application.id,
        platformId: 'plt_android',
        runtimeApplicationId: 'com.example.rollout.http',
        runtimeReleaseId: 'rollout-http-release-1',
        buildTarget: 'android-arm64-release',
        runtimeCompatibilityVersion: 1,
        patchFormatVersion: 1,
        buildFingerprint: _digest('rollout-http-build'),
        capabilityAuthorityDigest: _digest('rollout-http-capabilities'),
        functionSignatureDigest: _digest('rollout-http-functions'),
        displayVersion: '0.1.0',
        signingPublicKeys: <String, String>{
          _publicKeyId: base64.encode(publicKey),
        },
      ),
    );
    final patchBytes = await _patchBytes(
      releaseId: 'rollout-http-release-1',
      patchId: 'rollout-http-patch-1',
      sequence: 1,
    );
    final patch = await service.registerPatch(
      token: bootstrap.controlCredential.token,
      releaseId: release.id,
      idempotencyKey: 'http-fixture-patch',
      spec: PatchSpec(
        runtimePatchId: 'rollout-http-patch-1',
        sequence: 1,
        artifactId: 'art_rollout_http_patch',
        sha256: sha256Digest(patchBytes),
        sizeBytes: patchBytes.length,
        signatureKeyId: _publicKeyId,
      ),
    );
    await service.uploadArtifact(
      token: bootstrap.controlCredential.token,
      artifactId: patch.artifactId,
      bytes: patchBytes,
      idempotencyKey: 'http-fixture-artifact',
    );
    await service.promote(
      token: bootstrap.controlCredential.token,
      environmentId: bootstrap.environment.id,
      releaseId: release.id,
      expectedVersion: 0,
      idempotencyKey: 'http-fixture-promotion',
    );
    return _Fixture(
        directory: directory,
        service: service,
        bootstrap: bootstrap,
      )
      ..release = release
      ..patch = patch;
  }

  Future<void> dispose() => directory.delete(recursive: true);
}

String _digest(String value) => 'sha256:${sha256.convert(utf8.encode(value))}';

Future<List<int>> _publicKey() async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(
    List<int>.filled(32, 89),
  );
  try {
    return (await keyPair.extractPublicKey()).bytes;
  } finally {
    keyPair.destroy();
  }
}

Future<List<int>> _patchBytes({
  required String releaseId,
  required String patchId,
  required int sequence,
}) async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(
    List<int>.filled(32, 89),
  );
  try {
    final artifact = await PatchFormatV1.sealAsync(
      PatchArtifact(
        runtimeCompatibilityVersion: 1,
        applicationId: 'com.example.rollout.http',
        releaseId: releaseId,
        patchId: patchId,
        sequence: sequence,
        functions: <PatchFunctionEntry>[
          PatchFunctionEntry(
            id: 'lib:test#rollout_http',
            slot: 0,
            signatureDigest: _digest('rollout-http-signature'),
          ),
        ],
        capabilities: const <PatchCapabilityEntry>[],
        constants: const <PatchValue>[],
        instructions: const <int>[0],
        signatureMetadata: PatchSignatureMetadata(
          algorithm: 'ed25519',
          keyId: _publicKeyId,
        ),
        payloadDigest: const <int>[],
        signature: const <int>[],
      ),
      (message) async {
        final signature = await DartEd25519().sign(message, keyPair: keyPair);
        return signature.bytes;
      },
    );
    return PatchFormatV1.encode(artifact);
  } finally {
    keyPair.destroy();
  }
}
