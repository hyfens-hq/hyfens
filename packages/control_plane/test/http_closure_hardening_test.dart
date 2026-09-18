import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  late ControlPlaneHttpServer server;
  late int port;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-http-closure-');
    service = ControlPlaneService(store: FileControlPlaneStore(directory));
    bootstrap = await service.bootstrap(
      organizationName: 'HTTP closure',
      runtimeApplicationId: 'com.example.http.closure',
      platformId: 'android',
      environmentName: 'test',
    );
    server = ControlPlaneHttpServer(service, auditRetentionDays: 42);
    port = (await server.bind()).port;
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('credential, audit export, and reconciliation endpoints are bounded', () async {
    final client = HttpClient();
    try {
      final issued = await _request(
        client,
        port,
        method: 'POST',
        path: '/v1/organizations/${bootstrap.organization.id}/credentials',
        token: bootstrap.controlCredential.token,
        body: <String, Object?>{
          'kind': 'delivery',
          'scopes': deliveryScopes.toList(),
          'application_id': bootstrap.application.id,
          'environment_id': bootstrap.environment.id,
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        },
      );
      expect(issued.statusCode, 201, reason: jsonEncode(issued.body));
      expect(issued.body['token'], startsWith('hfy_'));

      final audit = await _request(
        client,
        port,
        method: 'GET',
        path:
            '/v1/organizations/${bootstrap.organization.id}/audit?retention_days=7',
        token: bootstrap.controlCredential.token,
      );
      expect(audit.statusCode, 200, reason: jsonEncode(audit.body));
      expect(audit.body['retentionDays'], 7);
      expect(
        (audit.body['verification'] as Map<String, Object?>)['valid'],
        isTrue,
      );

      final reconciliation = await _request(
        client,
        port,
        method: 'POST',
        path:
            '/v1/organizations/${bootstrap.organization.id}/artifact-reconciliation',
        token: bootstrap.controlCredential.token,
      );
      expect(
        reconciliation.statusCode,
        200,
        reason: jsonEncode(reconciliation.body),
      );
      expect(reconciliation.body['inventoryAvailable'], isTrue);

      final forbidden = await _request(
        client,
        port,
        method: 'POST',
        path: '/v1/organizations/${bootstrap.organization.id}/credentials',
        token: bootstrap.deliveryCredential.token,
        body: <String, Object?>{
          'kind': 'control',
          'scopes': controlScopes.toList(),
        },
      );
      expect(forbidden.statusCode, 403);
    } finally {
      client.close(force: true);
    }
  });
}

Future<_Response> _request(
  HttpClient client,
  int port, {
  required String method,
  required String path,
  required String token,
  Map<String, Object?>? body,
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  final encoded = body == null ? null : utf8.encode(jsonEncode(body));
  request.headers
    ..set('Authorization', 'Bearer $token')
    ..set('X-Request-Id', 'closure-http-request');
  if (encoded != null) {
    request.headers
      ..contentType = ContentType.json
      ..contentLength = encoded.length;
    request.add(encoded);
  }
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  final decoded = text.isEmpty
      ? <String, Object?>{}
      : jsonDecode(text) as Map<String, Object?>;
  return _Response(response.statusCode, decoded);
}

final class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}
