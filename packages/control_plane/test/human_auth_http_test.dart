import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late ControlPlaneStore store;
  late BootstrapResult bootstrap;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-human-auth-http-',
    );
    store = FileControlPlaneStore(directory);
    final auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'http-control-plane',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 8),
      ),
    );
    final service = ControlPlaneService(store: store, humanAuth: auth);
    bootstrap = await service.bootstrap(
      organizationName: 'HTTP auth test',
      runtimeApplicationId: 'com.example.http.auth',
      platformId: 'android',
      environmentName: 'development',
    );
    await service.bootstrapOwner(
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      email: 'operator@example.com',
      password: 'correct horse battery staple',
    );
    server = await ControlPlaneHttpServer(service).bind();
  });

  tearDown(() async {
    await server.close(force: true);
    await store.close();
    await directory.delete(recursive: true);
  });

  test('HTTP login, control authorization, refresh, and logout are bounded', () async {
    final client = HttpClient();
    try {
      final login = await _jsonRequest(
        client,
        server,
        method: 'POST',
        path: '/auth/login',
        body: <String, Object?>{
          'email': 'operator@example.com',
          'password': 'correct horse battery staple',
        },
      );
      expect(login.statusCode, 200, reason: jsonEncode(login.body));
      final accessToken = login.body['access_token']! as String;
      final sessionToken = login.body['session_token']! as String;
      expect(accessToken, isNot(contains('correct horse')));

      final me = await _jsonRequest(
        client,
        server,
        method: 'GET',
        path: '/auth/me',
        token: accessToken,
      );
      expect(me.statusCode, 200, reason: jsonEncode(me.body));
      expect(me.body['email'], 'operator@example.com');

      final release = await _jsonRequest(
        client,
        server,
        method: 'POST',
        path:
            '/v1/organizations/${bootstrap.organization.id}/applications/${bootstrap.application.id}/releases',
        token: accessToken,
        idempotencyKey: 'http-auth-release',
        body: <String, Object?>{
          'application_id': bootstrap.application.id,
          'platform_id': 'plt_android',
          'runtime_application_id': 'com.example.http.auth',
          'runtime_release_id': 'http-auth-release-1',
          'build_target': 'android-arm64-release',
          'runtime_compatibility_version': 1,
          'patch_format_version': 1,
          'build_fingerprint': _digest('build'),
          'capability_authority_digest': _digest('capability'),
          'function_signature_digest': _digest('functions'),
          'display_version': '1.0.0',
          'signing_public_keys': <String, String>{
            'auth-key': base64.encode(List<int>.filled(32, 4)),
          },
        },
      );
      expect(release.statusCode, 201, reason: jsonEncode(release.body));

      final deliveryRejected = await _jsonRequest(
        client,
        server,
        method: 'POST',
        path: '/v1/runtime/update-check',
        token: accessToken,
        body: <String, Object?>{
          'application_id': bootstrap.application.id,
          'environment_id': bootstrap.environment.id,
          'runtime_application_id': 'com.example.http.auth',
          'runtime_release_id': 'http-auth-release-1',
          'runtime_compatibility_version': 1,
          'patch_format_version': 1,
          'high_water_sequence': 0,
        },
      );
      expect(deliveryRejected.statusCode, 403);

      final refreshed = await _jsonRequest(
        client,
        server,
        method: 'POST',
        path: '/auth/refresh',
        body: <String, Object?>{'session_token': sessionToken},
      );
      expect(refreshed.statusCode, 200, reason: jsonEncode(refreshed.body));

      final logout = await _jsonRequest(
        client,
        server,
        method: 'POST',
        path: '/auth/logout',
        body: <String, Object?>{'session_token': sessionToken},
      );
      expect(logout.statusCode, 200, reason: jsonEncode(logout.body));

      final afterLogout = await _jsonRequest(
        client,
        server,
        method: 'GET',
        path: '/auth/me',
        token: refreshed.body['access_token']! as String,
      );
      expect(afterLogout.statusCode, 401);
    } finally {
      client.close(force: true);
    }
  });

  test('invalid login has a generic response', () async {
    final client = HttpClient();
    try {
      final response = await _jsonRequest(
        client,
        server,
        method: 'POST',
        path: '/auth/login',
        body: <String, Object?>{
          'email': 'missing@example.com',
          'password': 'correct horse battery staple',
        },
      );
      expect(response.statusCode, 401);
      expect(response.body['error'], <String, Object?>{
        'code': 'INVALID_CREDENTIALS',
        'message': 'Email or password is invalid',
      });
    } finally {
      client.close(force: true);
    }
  });
}

Future<_Response> _jsonRequest(
  HttpClient client,
  HttpServer server, {
  required String method,
  required String path,
  String? token,
  String? idempotencyKey,
  Map<String, Object?>? body,
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:${server.port}$path'),
  );
  final encoded = body == null ? null : utf8.encode(jsonEncode(body));
  if (token != null) request.headers.set('Authorization', 'Bearer $token');
  if (idempotencyKey != null) {
    request.headers.set('Idempotency-Key', idempotencyKey);
  }
  if (encoded != null) {
    request
      ..headers.contentType = ContentType.json
      ..contentLength = encoded.length;
    request.add(encoded);
  }
  final response = await request.close();
  final source = await response.transform(utf8.decoder).join();
  final decoded = source.isEmpty ? <String, Object?>{} : jsonDecode(source);
  return _Response(
    statusCode: response.statusCode,
    body: decoded is Map
        ? <String, Object?>{
            for (final entry in decoded.entries) '${entry.key}': entry.value,
          }
        : <String, Object?>{},
  );
}

final class _Response {
  const _Response({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, Object?> body;
}

String _digest(String value) =>
    'sha256:${sha256.convert(utf8.encode(value)).toString()}';
