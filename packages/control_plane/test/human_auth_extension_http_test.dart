import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late HumanAuthService auth;
  late HttpServer server;
  late BootstrapResult bootstrap;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-human-auth-extension-http-',
    );
    store = FileControlPlaneStore(directory);
    auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'http-extension-control-plane',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 21),
        devicePollInterval: const Duration(seconds: 1),
      ),
      random: Random(37),
    );
    final service = ControlPlaneService(store: store, humanAuth: auth);
    bootstrap = await service.bootstrap(
      organizationName: 'HTTP auth extension',
      runtimeApplicationId: 'com.example.http.extension',
      platformId: 'android',
      environmentName: 'development',
    );
    await service.bootstrapOwner(
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      email: 'owner@example.com',
      password: 'correct horse battery staple',
    );
    server = await ControlPlaneHttpServer(
      service,
      discovery: const ControlPlaneDiscoveryConfig(
        apiBasePath: '/p2/',
        webOrigins: <String>{'https://dashboard.example'},
      ),
    ).bind();
    _server = server;
  });

  tearDown(() async {
    await server.close(force: true);
    _server = null;
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'discovery is versioned, non-secret, and relative to the API base',
    () async {
      final response = await _request(
        method: 'GET',
        path: '/p2/.well-known/hyfens',
      );
      expect(response.statusCode, 200, reason: jsonEncode(response.body));
      expect(response.body['schema_version'], 1);
      expect(response.body['product'], 'hyfens');
      expect(response.body['api_base_path'], '/p2/');
      expect(response.body['issuer'], 'http-extension-control-plane');
      expect(response.body['authorization_endpoint'], '/p2/auth/authorize');
      expect(
        response.body['device_verification_uri'],
        '/p2/auth/device/verify',
      );
      expect(
        response.body['auth_methods'],
        contains('authorization_code_pkce'),
      );
      expect(
        (response.body['api_key_management']! as Map)['supported'],
        isTrue,
      );
      expect(
        (response.body['api_key_management']! as Map)['issue_endpoint'],
        '/p2/v1/organizations/{organization_id}/credentials',
      );
      expect(jsonEncode(response.body), isNot(contains('hfs.')));
    },
  );

  test('human Auth v1 sessions can read the dashboard overview', () async {
    final login = await _request(
      method: 'POST',
      path: '/p2/auth/login',
      body: <String, Object?>{
        'email': 'owner@example.com',
        'password': 'correct horse battery staple',
      },
    );
    final response = await _request(
      method: 'GET',
      path: '/p2/v1/organizations/${bootstrap.organization.id}/overview',
      token: login.body['access_token']! as String,
    );
    expect(response.statusCode, 200, reason: jsonEncode(response.body));
    expect(response.body['readOnly'], true);
    expect(response.body['organization'], bootstrap.organization.toJson());
  });

  test(
    'HTTP PKCE state/redirect/code lifecycle does not put a session in a URL',
    () async {
      final login = await _request(
        method: 'POST',
        path: '/p2/auth/login',
        body: <String, Object?>{
          'email': 'owner@example.com',
          'password': 'correct horse battery staple',
        },
      );
      final accessToken = login.body['access_token']! as String;
      final verifier = 'c' * 43;
      final authorize = await _request(
        method: 'GET',
        path:
            '/p2/auth/authorize?client_id=hyfens-cli'
            '&redirect_uri=http%3A%2F%2F127.0.0.1%3A43127%2Fcallback'
            '&response_type=code'
            '&code_challenge=${Uri.encodeQueryComponent(_challenge(verifier))}'
            '&code_challenge_method=S256'
            '&state=state-http-extension',
      );
      expect(authorize.statusCode, 200, reason: jsonEncode(authorize.body));
      final requestId = authorize.body['authorization_request_id']! as String;

      final callback = await _request(
        method: 'POST',
        path: '/p2/auth/authorize',
        token: accessToken,
        body: <String, Object?>{'request_id': requestId},
        followRedirects: false,
      );
      expect(callback.statusCode, 302, reason: jsonEncode(callback.body));
      final location = callback.headers['location']!;
      final callbackUri = Uri.parse(location);
      expect(callbackUri.queryParameters['state'], 'state-http-extension');
      final code = callbackUri.queryParameters['code']!;
      expect(location, isNot(contains('session_token')));
      expect(location, isNot(contains('access_token')));

      final exchanged = await _request(
        method: 'POST',
        path: '/p2/auth/token',
        body: <String, Object?>{
          'grant_type': humanAuthorizationCodeGrantType,
          'client_id': 'hyfens-cli',
          'code': code,
          'redirect_uri': 'http://127.0.0.1:43127/callback',
          'code_verifier': verifier,
        },
      );
      expect(exchanged.statusCode, 200, reason: jsonEncode(exchanged.body));
      expect(exchanged.body['session_token'], startsWith('hfs.'));

      final reused = await _request(
        method: 'POST',
        path: '/p2/auth/token',
        body: <String, Object?>{
          'grant_type': humanAuthorizationCodeGrantType,
          'client_id': 'hyfens-cli',
          'code': code,
          'redirect_uri': 'http://127.0.0.1:43127/callback',
          'code_verifier': verifier,
        },
      );
      expect(reused.statusCode, 400);
      expect((reused.body['error']! as Map)['code'], 'AUTHORIZATION_CODE_USED');
    },
  );

  test(
    'browser approval exposes only exact-origin CORS and JSON code output',
    () async {
      final preflight = await _request(
        method: 'OPTIONS',
        path: '/p2/auth/authorize',
        requestHeaders: <String, String>{
          'Origin': 'https://dashboard.example',
          'Access-Control-Request-Method': 'POST',
          'Access-Control-Request-Headers': 'authorization, content-type',
        },
      );
      expect(preflight.statusCode, 204);
      expect(
        preflight.headers['access-control-allow-origin'],
        'https://dashboard.example',
      );

      final login = await _request(
        method: 'POST',
        path: '/p2/auth/login',
        requestHeaders: <String, String>{'Origin': 'https://dashboard.example'},
        body: <String, Object?>{
          'email': 'owner@example.com',
          'password': 'correct horse battery staple',
        },
      );
      final accessToken = login.body['access_token']! as String;
      final verifier = 'd' * 43;
      final authorize = await _request(
        method: 'GET',
        path:
            '/p2/auth/authorize?client_id=hyfens-cli'
            '&redirect_uri=http%3A%2F%2F127.0.0.1%3A43127%2Fcallback'
            '&response_type=code'
            '&code_challenge=${Uri.encodeQueryComponent(_challenge(verifier))}'
            '&code_challenge_method=S256'
            '&state=state-json-response',
        requestHeaders: <String, String>{
          'Origin': 'https://dashboard.example',
          'Accept': 'application/json',
        },
      );
      final requestId = authorize.body['authorization_request_id']! as String;
      final approval = await _request(
        method: 'POST',
        path: '/p2/auth/authorize',
        token: accessToken,
        requestHeaders: <String, String>{
          'Origin': 'https://dashboard.example',
          'Accept': 'application/json',
        },
        body: <String, Object?>{'request_id': requestId},
      );
      expect(approval.statusCode, 200, reason: jsonEncode(approval.body));
      expect(approval.body['code'], startsWith('hfc_'));
      expect(approval.body['state'], 'state-json-response');
      expect(
        approval.headers['access-control-allow-origin'],
        'https://dashboard.example',
      );

      final rejected = await _request(
        method: 'GET',
        path: '/p2/auth/me',
        requestHeaders: <String, String>{'Origin': 'https://evil.example'},
      );
      expect(rejected.statusCode, 403);
      expect(rejected.headers['access-control-allow-origin'], isNull);
    },
  );

  test('HTTP device code is pending, approved, consumed, and never accepted in a URL', () async {
    final login = await _request(
      method: 'POST',
      path: '/auth/login',
      body: <String, Object?>{
        'email': 'owner@example.com',
        'password': 'correct horse battery staple',
      },
    );
    final accessToken = login.body['access_token']! as String;
    final issued = await _request(
      method: 'POST',
      path: '/auth/device/code',
      body: <String, Object?>{'client_id': 'hyfens-cli'},
    );
    expect(issued.statusCode, 200, reason: jsonEncode(issued.body));
    final deviceCode = issued.body['device_code']! as String;
    final userCode = issued.body['user_code']! as String;
    expect(issued.body['verification_uri'], '/p2/auth/device/verify');

    final pending = await _request(
      method: 'POST',
      path: '/auth/device/token',
      body: <String, Object?>{
        'grant_type': humanDeviceAuthorizationGrantType,
        'client_id': 'hyfens-cli',
        'device_code': deviceCode,
      },
    );
    expect(pending.statusCode, 400);
    expect(pending.body['error'], 'authorization_pending');

    final approval = await _request(
      method: 'POST',
      path: '/auth/device/approve',
      token: accessToken,
      body: <String, Object?>{'user_code': userCode},
    );
    expect(approval.statusCode, 200, reason: jsonEncode(approval.body));

    final consumed = await _request(
      method: 'POST',
      path: '/auth/device/token',
      body: <String, Object?>{
        'client_id': 'hyfens-cli',
        'device_code': deviceCode,
      },
    );
    expect(consumed.statusCode, 200, reason: jsonEncode(consumed.body));
    expect(consumed.body['session_token'], startsWith('hfs.'));
    final replay = await _request(
      method: 'POST',
      path: '/auth/device/token?device_code=$deviceCode',
      body: <String, Object?>{
        'client_id': 'hyfens-cli',
        'device_code': deviceCode,
      },
    );
    expect(replay.statusCode, 400);
    expect((replay.body['error']! as Map)['code'], 'INVALID_REQUEST');
  });
}

Future<_HttpResponse> _request({
  required String method,
  required String path,
  String? token,
  Map<String, Object?>? body,
  Map<String, String>? requestHeaders,
  bool followRedirects = true,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${_server!.port}$path'),
    );
    request.followRedirects = followRedirects;
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    requestHeaders?.forEach((name, value) => request.headers.set(name, value));
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request
        ..headers.contentType = ContentType.json
        ..headers.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    final source = utf8.decode(bytes);
    Object? decoded;
    try {
      decoded = source.isEmpty ? <String, Object?>{} : jsonDecode(source);
    } on Object {
      decoded = <String, Object?>{};
    }
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    return _HttpResponse(
      statusCode: response.statusCode,
      body: decoded is Map
          ? <String, Object?>{
              for (final entry in decoded.entries) '${entry.key}': entry.value,
            }
          : <String, Object?>{},
      headers: headers,
    );
  } finally {
    client.close(force: true);
  }
}

HttpServer? _server;

String _challenge(String verifier) => base64Url
    .encode(sha256.convert(utf8.encode(verifier)).bytes)
    .replaceAll('=', '');

final class _HttpResponse {
  const _HttpResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final Map<String, Object?> body;
  final Map<String, String> headers;
}
