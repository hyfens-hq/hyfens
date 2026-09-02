import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-control-plane-http-',
    );
    service = ControlPlaneService(store: FileControlPlaneStore(directory));
    bootstrap = await service.bootstrap(
      organizationName: 'HTTP test',
      runtimeApplicationId: 'com.example.http',
      platformId: 'android',
      environmentName: 'development',
    );
    server = await ControlPlaneHttpServer(service).bind();
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('HTTP adapter enforces auth and serves the versioned contract', () async {
    final client = HttpClient();
    try {
      final health = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/healthz'),
      );
      final healthResponse = await health.close();
      expect(healthResponse.statusCode, 200);

      final readiness = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/readyz'),
      );
      final readinessResponse = await readiness.close();
      expect(readinessResponse.statusCode, 200);

      final keyPair = await DartEd25519().newKeyPairFromSeed(
        List<int>.filled(32, 4),
      );
      final publicKey = await keyPair.extractPublicKey();
      keyPair.destroy();
      final body = <String, Object?>{
        'application_id': bootstrap.application.id,
        'platform_id': 'plt_android',
        'runtime_application_id': 'com.example.http',
        'runtime_release_id': 'http-release-1',
        'build_target': 'android-arm64-release',
        'runtime_compatibility_version': 1,
        'patch_format_version': 1,
        'build_fingerprint': _digest('build'),
        'capability_authority_digest': _digest('capability'),
        'function_signature_digest': _digest('functions'),
        'display_version': '0.1.0',
        'signing_public_keys': <String, String>{
          'http-key': base64.encode(publicKey.bytes),
        },
      };
      final releaseRequest = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/v1/organizations/${bootstrap.organization.id}/applications/${bootstrap.application.id}/releases',
        ),
      );
      final encoded = utf8.encode(jsonEncode(body));
      releaseRequest
        ..headers.contentType = ContentType.json
        ..headers.set(
          'Authorization',
          'Bearer ${bootstrap.controlCredential.token}',
        )
        ..headers.set('Idempotency-Key', 'http-release-1')
        ..contentLength = encoded.length;
      releaseRequest.add(encoded);
      final releaseResponse = await releaseRequest.close();
      final decoded = jsonDecode(
        await releaseResponse.transform(utf8.decoder).join(),
      ) as Map<String, Object?>;
      expect(releaseResponse.statusCode, 201, reason: jsonEncode(decoded));
      expect(decoded['runtimeReleaseId'], 'http-release-1');

      final updateRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/v1/runtime/update-check'),
      );
      final updateBody = utf8.encode(
        jsonEncode(<String, Object?>{
          'application_id': bootstrap.application.id,
          'environment_id': bootstrap.environment.id,
          'runtime_application_id': 'com.example.http',
          'runtime_release_id': 'http-release-1',
          'runtime_compatibility_version': 1,
          'patch_format_version': 1,
          'high_water_sequence': 0,
        }),
      );
      updateRequest
        ..headers.contentType = ContentType.json
        ..headers.set(
          'Authorization',
          'Bearer ${bootstrap.deliveryCredential.token}',
        )
        ..contentLength = updateBody.length;
      updateRequest.add(updateBody);
      final updateResponse = await updateRequest.close();
      final update = jsonDecode(
        await updateResponse.transform(utf8.decoder).join(),
      ) as Map<String, Object?>;
      expect(updateResponse.statusCode, 200);
      expect(update['decision'], 'NO_UPDATE');

      final forbiddenRequest = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/v1/runtime/update-check'),
      );
      forbiddenRequest
        ..headers.contentType = ContentType.json
        ..headers.set(
          'Authorization',
          'Bearer ${bootstrap.controlCredential.token}',
        )
        ..contentLength = updateBody.length;
      forbiddenRequest.add(updateBody);
      final forbiddenResponse = await forbiddenRequest.close();
      expect(forbiddenResponse.statusCode, 403);

      final metricsRequest = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/metrics'),
      );
      final metricsResponse = await metricsRequest.close();
      final metrics = jsonDecode(
        await metricsResponse.transform(utf8.decoder).join(),
      ) as Map<String, Object?>;
      expect(metricsResponse.statusCode, 200);
      final requestMetrics = metrics['requests']! as Map<String, Object?>;
      expect(requestMetrics['count'], greaterThanOrEqualTo(5));
      expect(requestMetrics['errors'], greaterThanOrEqualTo(1));
      expect(requestMetrics['maxDurationMicros'], greaterThanOrEqualTo(0));
      expect(
        (requestMetrics['updateDecisions']!
            as Map<String, Object?>)['NO_UPDATE'],
        1,
      );
    } finally {
      client.close(force: true);
    }
  });

  test('HTTP adapter applies an explicit per-client rate limit', () async {
    final limited = ControlPlaneHttpServer(
      service,
      limits: const ControlPlaneHttpLimits(maxRequestsPerMinute: 1),
    );
    final limitedServer = await limited.bind();
    addTearDown(() => limited.close(force: true));
    final client = HttpClient();
    try {
      final first = await client.getUrl(
        Uri.parse('http://127.0.0.1:${limitedServer.port}/healthz'),
      );
      expect((await first.close()).statusCode, 200);
      final second = await client.getUrl(
        Uri.parse('http://127.0.0.1:${limitedServer.port}/healthz'),
      );
      expect((await second.close()).statusCode, 429);
    } finally {
      client.close(force: true);
    }
  });
}

String _digest(String value) => 'sha256:${sha256.convert(utf8.encode(value))}';
