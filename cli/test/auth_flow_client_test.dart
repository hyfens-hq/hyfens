import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

void main() {
  test(
    'browser login uses S256 PKCE and exchanges only through the body',
    () async {
      final root = await Directory.systemTemp.createTemp('hyfens-pkce-');
      addTearDown(() => root.delete(recursive: true));
      final requests = <_Request>[];
      final server = await _startAuthServer(requests);
      addTearDown(() => server.close(force: true));
      Uri? authorizationUri;

      final client = AuthClient(
        storage: AuthStorage(root: root),
        browserLauncher: (uri) async {
          authorizationUri = uri;
          final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
          final callback = redirect.replace(
            queryParameters: <String, String>{
              'code': 'short-lived-code',
              'state': uri.queryParameters['state']!,
            },
          );
          final callbackClient = HttpClient();
          try {
            final request = await callbackClient.getUrl(callback);
            final response = await request.close();
            await response.drain<void>();
          } finally {
            callbackClient.close(force: true);
          }
        },
      );

      final result = await client.loginBrowser(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      );
      expect(result.profile.organizationId, 'org_demo');
      expect(authorizationUri, isNotNull);
      final query = authorizationUri!.queryParameters;
      expect(query['code_challenge_method'], 'S256');
      expect(query.containsKey('code'), isFalse);
      expect(query.containsKey('session_token'), isFalse);
      expect(query.containsKey('access_token'), isFalse);
      expect(requests.map((request) => request.path), contains('/auth/token'));
      final exchange = requests.singleWhere(
        (request) => request.path == '/auth/token',
      );
      final body = exchange.body!;
      expect(body['redirect_uri'], query['redirect_uri']);
      expect(body['code'], 'short-lived-code');
      final verifier = body['code_verifier']! as String;
      final expectedChallenge = base64Url
          .encode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', '');
      expect(expectedChallenge, query['code_challenge']);
    },
  );

  test('device login polls a supported endpoint and keeps the device secret out of the URL', () async {
    final root = await Directory.systemTemp.createTemp('hyfens-device-');
    addTearDown(() => root.delete(recursive: true));
    final requests = <_Request>[];
    final server = await _startAuthServer(requests, deviceFlow: true);
    addTearDown(() => server.close(force: true));
    DeviceAuthorizationPrompt? prompt;

    final client = AuthClient(
      storage: AuthStorage(root: root),
      sleeper: (_) async {},
    );
    final result = await client.loginDevice(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      onPrompt: (value) => prompt = value,
    );

    expect(result.session.sessionToken, 'session-secret');
    expect(prompt, isNotNull);
    expect(prompt!.verificationUri.queryParameters, isEmpty);
    expect(
      requests.where((request) => request.path == '/auth/device/token'),
      hasLength(2),
    );
    expect(
      requests
          .where((request) => request.path == '/auth/device/token')
          .every(
            (request) =>
                !request.uri.queryParameters.containsKey('device_code'),
          ),
      isTrue,
    );
  });

  test(
    'device login reports unsupported discovery instead of claiming success',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-device-unsupported-',
      );
      addTearDown(() => root.delete(recursive: true));
      final server = await _startAuthServer(<_Request>[]);
      addTearDown(() => server.close(force: true));
      final client = AuthClient(storage: AuthStorage(root: root));

      await expectLater(
        client.loginDevice(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        ),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            'A1030',
          ),
        ),
      );
      expect(File('${root.path}/credentials').existsSync(), isFalse);
    },
  );
}

Future<HttpServer> _startAuthServer(
  List<_Request> requests, {
  bool deviceFlow = false,
}) async {
  var devicePolls = 0;
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((request) async {
    final bytes = await request.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    final body = bytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    requests.add(
      _Request(path: request.uri.path, uri: request.uri, body: body),
    );
    if (request.uri.path == '/.well-known/hyfens') {
      await _respond(request, <String, Object?>{
        'product': 'hyfens',
        'api_version': 'v1',
        'auth_methods': deviceFlow
            ? <String>['device_authorization']
            : <String>['authorization_code_pkce_s256'],
        'authorization_endpoint': '/auth/authorize',
        'token_endpoint': '/auth/token',
        'device_authorization_endpoint': '/auth/device/code',
        'device_token_endpoint': '/auth/device/token',
        'capabilities': <String>[],
      });
      return;
    }
    if (request.uri.path == '/auth/device/code') {
      await _respond(request, <String, Object?>{
        'device_code': 'device-secret',
        'user_code': 'ABCD-EFGH',
        'verification_uri': '/auth/device/verify',
        'expires_in': 60,
        'interval': 1,
      });
      return;
    }
    if (request.uri.path == '/auth/device/token') {
      devicePolls++;
      if (devicePolls == 1) {
        await _respond(request, <String, Object?>{
          'error': 'authorization_pending',
        }, statusCode: HttpStatus.badRequest);
      } else {
        await _respond(request, _loginPayload());
      }
      return;
    }
    if (request.uri.path == '/auth/token') {
      await _respond(request, _loginPayload());
      return;
    }
    await _respond(request, <String, Object?>{
      'error': 'not_found',
    }, statusCode: 404);
  });
  return server;
}

Map<String, Object?> _loginPayload() => <String, Object?>{
  'access_token': 'access-secret',
  'session_token': 'session-secret',
  'expires_at': '2099-01-01T00:00:00.000Z',
  'session_expires_at': '2099-01-02T00:00:00.000Z',
  'user_id': 'usr_demo',
  'email': 'demo@example.com',
  'profiles': <Object?>[
    <String, Object?>{
      'name': 'demo',
      'organization_id': 'org_demo',
      'application_id': 'app_demo',
      'environment_id': 'env_demo',
      'role': 'owner',
    },
  ],
};

Future<void> _respond(
  HttpRequest request,
  Map<String, Object?> body, {
  int statusCode = HttpStatus.ok,
}) async {
  final bytes = utf8.encode(jsonEncode(body));
  request.response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..headers.contentLength = bytes.length
    ..add(bytes);
  await request.response.close();
}

final class _Request {
  const _Request({required this.path, required this.uri, required this.body});

  final String path;
  final Uri uri;
  final Map<String, Object?>? body;
}
