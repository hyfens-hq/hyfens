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
    directory = await Directory.systemTemp.createTemp(
      'hyfens-observation-http-',
    );
    service = ControlPlaneService(store: FileControlPlaneStore(directory));
    bootstrap = await service.bootstrap(
      organizationName: 'Observation HTTP',
      runtimeApplicationId: 'com.example.observation.http',
      platformId: 'android',
      environmentName: 'test',
    );
    server = ControlPlaneHttpServer(service);
    port = (await server.bind()).port;
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
    'token and event endpoints fail closed with stable bounded errors',
    () async {
      final client = HttpClient();
      try {
        final token = await _request(
          client,
          port,
          method: 'POST',
          path: '/v1/observations/token',
          token: bootstrap.controlCredential.token,
          body: <String, Object?>{
            'organization_id': bootstrap.organization.id,
            'application_id': bootstrap.application.id,
            'environment_id': bootstrap.environment.id,
            'ttl_seconds': 300,
          },
        );
        expect(token.statusCode, 201, reason: jsonEncode(token.body));
        final observationToken = token.body['token']! as String;

        final deniedControlRoute = await _request(
          client,
          port,
          method: 'POST',
          path: '/v1/organizations/${bootstrap.organization.id}/credentials',
          token: observationToken,
          body: <String, Object?>{
            'kind': 'delivery',
            'scopes': deliveryScopes.toList(),
            'application_id': bootstrap.application.id,
            'environment_id': bootstrap.environment.id,
          },
        );
        expect(deniedControlRoute.statusCode, 403);

        final malformed = await _request(
          client,
          port,
          method: 'POST',
          path: '/v1/observations/events',
          token: observationToken,
          body: <String, Object?>{'schema_version': 1, 'unexpected': true},
        );
        expect(malformed.statusCode, 422, reason: jsonEncode(malformed.body));
        expect(
          (malformed.body['error']! as Map<String, Object?>)['code'],
          'EVENT_SCHEMA_UNSUPPORTED',
        );

        final validShape = <String, Object?>{
          'schema_version': 1,
          'event_id': 'http-event-1',
          'client_timestamp': DateTime.now().toUtc().toIso8601String(),
          'organization_id': bootstrap.organization.id,
          'application_id': bootstrap.application.id,
          'environment_id': bootstrap.environment.id,
          'platform': 'android',
          'release_id': 'rel_missing',
          'patch_id': null,
          'sequence': null,
          'rollout_id': null,
          'rollout_revision': null,
          'installation_bucket': 'bucket:1',
          'event_type': 'lookup_attempt',
          'runtime_version': 'runtime-1',
          'patch_format_version': 1,
          'diagnostic_code': null,
          'safe_metadata': <String, Object?>{},
        };
        final identityMismatch = await _request(
          client,
          port,
          method: 'POST',
          path: '/v1/observations/events',
          token: observationToken,
          body: validShape,
        );
        expect(
          identityMismatch.statusCode,
          422,
          reason: jsonEncode(identityMismatch.body),
        );
        expect(
          (identityMismatch.body['error']! as Map<String, Object?>)['code'],
          'EVENT_IDENTITY_MISMATCH',
        );

        final oversized = await _request(
          client,
          port,
          method: 'POST',
          path: '/v1/observations/events',
          token: observationToken,
          body: <String, Object?>{
            ...validShape,
            'event_id': 'http-event-large',
            'safe_metadata': <String, Object?>{'large': 'x' * 300},
          },
        );
        expect(oversized.statusCode, 422);
        expect(
          (oversized.body['error']! as Map<String, Object?>)['code'],
          'EVENT_SCHEMA_UNSUPPORTED',
        );

        final unauthorized = await _request(
          client,
          port,
          method: 'POST',
          path: '/v1/observations/events',
          token: bootstrap.deliveryCredential.token,
          body: validShape,
        );
        expect(unauthorized.statusCode, 403);
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
    ..set('X-Request-Id', 'observation-http-test');
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
