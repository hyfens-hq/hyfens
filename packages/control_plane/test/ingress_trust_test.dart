import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  late ControlPlaneHttpServer adapter;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-ingress-');
    service = ControlPlaneService(store: FileControlPlaneStore(directory));
    bootstrap = await service.bootstrap(
      organizationName: 'Ingress test',
      runtimeApplicationId: 'com.example.ingress',
      platformId: 'android',
      environmentName: 'development',
    );
    adapter = ControlPlaneHttpServer(service);
    server = await adapter.bind();
  });

  tearDown(() async {
    await adapter.close(force: true);
    await directory.delete(recursive: true);
  });

  test('spoofed proxy headers cannot replace bearer authentication', () async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/v1/runtime/update-check'),
      );
      final body = utf8.encode(
        jsonEncode(<String, Object?>{
          'application_id': bootstrap.application.id,
          'environment_id': bootstrap.environment.id,
          'runtime_application_id': 'com.example.ingress',
          'runtime_release_id': 'missing-release',
          'runtime_compatibility_version': 1,
          'patch_format_version': 1,
          'high_water_sequence': 0,
        }),
      );
      request
        ..headers.contentType = ContentType.json
        ..headers.host = 'spoofed.example'
        ..headers.add('Forwarded', 'for=198.51.100.1;proto=https')
        ..headers.add('Forwarded', 'for=198.51.100.2;proto=http')
        ..headers.add('X-Forwarded-For', '198.51.100.1')
        ..headers.add('X-Forwarded-For', '198.51.100.2')
        ..headers.set('X-Forwarded-Host', 'spoofed.example')
        ..headers.set('X-Forwarded-Proto', 'https')
        ..contentLength = body.length;
      request.add(body);
      final response = await request.close();
      expect(response.statusCode, 401);
    } finally {
      client.close(force: true);
    }
  });

  test('forwarded headers do not change tenant authorization or correlation', () async {
    final client = HttpClient();
    try {
      final own = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/v1/organizations/${bootstrap.organization.id}/audit',
        ),
      );
      own
        ..headers.set(
          'Authorization',
          'Bearer ${bootstrap.controlCredential.token}',
        )
        ..headers.set('Forwarded', 'for=203.0.113.9;proto=http')
        ..headers.set('X-Forwarded-For', '203.0.113.9')
        ..headers.set('X-Forwarded-Proto', 'http')
        ..headers.set('X-Forwarded-Host', 'foreign.example')
        ..headers.set('X-Request-Id', 'trusted-correlation-1');
      final ownResponse = await own.close();
      expect(ownResponse.statusCode, 200);
      expect(
        ownResponse.headers.value('x-request-id'),
        'trusted-correlation-1',
      );

      final foreign = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/v1/organizations/org_foreign/audit',
        ),
      );
      foreign
        ..headers.set(
          'Authorization',
          'Bearer ${bootstrap.controlCredential.token}',
        )
        ..headers.set('X-Forwarded-For', '127.0.0.1');
      final foreignResponse = await foreign.close();
      expect(foreignResponse.statusCode, anyOf(403, 404));

      final invalidId = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/healthz'),
      );
      invalidId.headers.set('X-Request-Id', 'spoof invalid');
      final invalidIdResponse = await invalidId.close();
      final returnedId = invalidIdResponse.headers.value('x-request-id');
      expect(returnedId, isNot('spoof invalid'));
      expect(returnedId, startsWith('req_'));
    } finally {
      client.close(force: true);
    }
  });

  test('oversized forwarded metadata is not an authorization bypass', () async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/v1/organizations/${bootstrap.organization.id}/audit',
        ),
      );
      request
        ..headers.set('X-Forwarded-For', '1' * 8192)
        ..headers.set('Forwarded', 'for=198.51.100.2')
        ..headers.set('Host', 'untrusted.example');
      final response = await request.close();
      expect(response.statusCode, anyOf(400, 401, 431));
    } finally {
      client.close(force: true);
    }
  });

  test('policy constants keep the trust boundary explicit', () {
    expect(
      ControlPlaneIngressTrustPolicy.forwardedHeadersAffectAuthorization,
      isFalse,
    );
    expect(
      ControlPlaneIngressTrustPolicy.forwardedHeadersAffectRateLimit,
      isFalse,
    );
    expect(
      ControlPlaneIngressTrustPolicy.requestIdAffectsAuthorization,
      isFalse,
    );
    expect(ControlPlaneIngressTrustPolicy.hostAffectsAuthorization, isFalse);
  });
}
