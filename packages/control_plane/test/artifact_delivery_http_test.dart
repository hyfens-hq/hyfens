import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-delivery-http-');
    store = FileControlPlaneStore(directory);
    service = ControlPlaneService(
      store: store,
      deploymentModel: DeploymentModel.cloud,
      clock: () => DateTime.utc(2026, 9, 7, 12),
    );
    bootstrap = await service.bootstrap(
      organizationName: 'Delivery HTTP test',
      runtimeApplicationId: 'com.example.delivery',
      platformId: 'android',
      environmentName: 'production',
    );

    final bytes = <int>[10, 20, 30, 40, 50, 60];
    final artifact = ArtifactRecord(
      id: 'art_http_delivery',
      organizationId: bootstrap.organization.id,
      patchId: 'pat_http_delivery',
      sha256: sha256Digest(bytes),
      sizeBytes: bytes.length,
      contentType: 'application/octet-stream',
      state: artifactReadyState,
      createdAt: DateTime.utc(2026, 9, 7),
    );
    final patch = PatchRecord(
      id: artifact.patchId,
      organizationId: bootstrap.organization.id,
      releaseId: 'rel_http_delivery',
      runtimePatchId: 'patch-http-delivery',
      sequence: 1,
      artifactId: artifact.id,
      sha256: artifact.sha256,
      sizeBytes: artifact.sizeBytes,
      signatureKeyId: 'key-http-delivery',
      state: 'READY',
      createdAt: artifact.createdAt,
    );
    final release = ReleaseRecord(
      id: patch.releaseId,
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      platformId: 'android',
      runtimeApplicationId: bootstrap.application.runtimeApplicationId,
      runtimeReleaseId: 'release-http-delivery',
      buildTarget: 'android-arm64-release',
      runtimeCompatibilityVersion: 1,
      patchFormatVersion: 1,
      buildFingerprint: _digest('build'),
      capabilityAuthorityDigest: _digest('capability'),
      functionSignatureDigest: _digest('functions'),
      displayVersion: '1.0.0',
      signingPublicKeys: const <String, String>{},
      createdAt: artifact.createdAt,
    );
    await store.createJson('releases', release.id, release.toJson());
    await store.createJson('patches', patch.id, patch.toJson());
    await store.createJson('artifacts', artifact.id, artifact.toJson());
    await store.putArtifact(artifact.sha256, bytes);
    await store.replaceJson(
      'environments',
      bootstrap.environment.id,
      bootstrap.environment.copyWith(promotedReleaseId: release.id).toJson(),
    );
    server = await ControlPlaneHttpServer(service).bind();
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('range delivery accounts only the selected bytes', () async {
    final client = HttpClient();
    try {
      final ranged = await _fetch(
        client,
        server,
        bootstrap,
        range: 'bytes=1-3',
      );
      expect(ranged.statusCode, HttpStatus.partialContent);
      expect(ranged.body, <int>[20, 30, 40]);
      expect(ranged.headers.value('content-range'), 'bytes 1-3/6');
      expect(ranged.headers.contentLength, 3);

      final full = await _fetch(client, server, bootstrap);
      expect(full.statusCode, HttpStatus.ok);
      expect(full.body, <int>[10, 20, 30, 40, 50, 60]);

      final usage = await service.usageMetering.readUsage(
        organizationId: bootstrap.organization.id,
      );
      expect(usage?.artifactDeliveryBytesPeriod, 9);
    } finally {
      client.close(force: true);
    }
  });

  test('invalid ranges do not create delivery evidence', () async {
    final client = HttpClient();
    try {
      final response = await _fetch(
        client,
        server,
        bootstrap,
        range: 'bytes=100-',
      );
      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);

      final oversized = await _fetch(
        client,
        server,
        bootstrap,
        range: 'bytes=999999999999999999999999-',
      );
      expect(oversized.statusCode, HttpStatus.requestedRangeNotSatisfiable);

      final usage = await service.usageMetering.readUsage(
        organizationId: bootstrap.organization.id,
      );
      expect(usage?.artifactDeliveryBytesPeriod, 0);
    } finally {
      client.close(force: true);
    }
  });
}

Future<_HttpResult> _fetch(
  HttpClient client,
  HttpServer server,
  BootstrapResult bootstrap, {
  String? range,
}) async {
  final request = await client.getUrl(
    Uri.parse(
      'http://127.0.0.1:${server.port}/v1/runtime/artifacts/art_http_delivery'
      '?application_id=${bootstrap.application.id}'
      '&environment_id=${bootstrap.environment.id}',
    ),
  );
  request.headers.set(
    'Authorization',
    'Bearer ${bootstrap.deliveryCredential.token}',
  );
  if (range != null) request.headers.set('Range', range);
  final response = await request.close();
  return _HttpResult(
    statusCode: response.statusCode,
    headers: response.headers,
    body: await response.fold<List<int>>(<int>[], (body, chunk) {
      body.addAll(chunk);
      return body;
    }),
  );
}

final class _HttpResult {
  const _HttpResult({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final HttpHeaders headers;
  final List<int> body;
}

String _digest(String value) => sha256Digest(utf8.encode(value));
