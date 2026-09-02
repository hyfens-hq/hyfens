import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

void main() {
  test('auth commands persist split metadata and redact secrets', () async {
    final root = await Directory.systemTemp.createTemp('hyfens-auth-');
    addTearDown(() => root.delete(recursive: true));
    final storage = AuthStorage(root: root);
    final requests = <_Request>[];
    final server = await _startServer(requests);
    addTearDown(() => server.close(force: true));

    final output = await _runTool(
      <String>[
        'auth',
        'login',
        '--endpoint',
        'http://127.0.0.1:${server.port}',
        '--email',
        'operator@example.com',
        '--json',
      ],
      storage: storage,
      prompt: (message, {required secret}) async =>
          secret ? 'password-never-printed' : 'operator@example.com',
    );

    expect(output.exitCode, 0, reason: '${output.stdout}\n${output.stderr}');
    expect(output.stdout, contains('LOGGED_IN'));
    expect(output.stdout, isNot(contains('access-secret')));
    expect(output.stdout, isNot(contains('session-secret')));
    expect(output.stdout, isNot(contains('password-never-printed')));
    expect(output.stderr, isNot(contains('access-secret')));
    expect(output.stderr, isNot(contains('session-secret')));
    expect(output.stderr, isNot(contains('password-never-printed')));
    expect(requests, hasLength(1));
    expect(requests.single.path, '/auth/login');
    expect(requests.single.method, 'POST');
    expect(requests.single.body, <String, Object?>{
      'email': 'operator@example.com',
      'password': 'password-never-printed',
    });

    final profileText = await storage.profileFile.readAsString();
    final sessionText = await storage.sessionFile.readAsString();
    expect(profileText, contains('operator@example.com'));
    expect(profileText, isNot(contains('access-secret')));
    expect(profileText, isNot(contains('session-secret')));
    expect(sessionText, contains('access-secret'));
    expect(sessionText, contains('session-secret'));
    expect(sessionText, isNot(contains('operator@example.com')));

    if (!Platform.isWindows) {
      expect((await storage.root.stat()).mode & 0x1ff, 0x1c0);
      expect((await storage.profileFile.stat()).mode & 0x1ff, 0x180);
      expect((await storage.sessionFile.stat()).mode & 0x1ff, 0x180);
    }

    final status = await _runTool(const <String>[
      'auth',
      'status',
      '--json',
    ], storage: storage);
    expect(status.exitCode, 0, reason: '${status.stdout}\n${status.stderr}');
    expect(jsonDecode(status.stdout), <String, Object?>{
      'result': 'LOGGED_IN',
      'profile': <String, Object?>{
        'endpoint': 'http://127.0.0.1:${server.port}',
        'user_id': 'usr_operator',
        'email': 'operator@example.com',
        'profiles': <Object?>[
          <String, Object?>{
            'name': 'demo',
            'organization_id': 'org_demo',
            'application_id': 'app_demo',
            'environment_id': 'env_demo',
            'role': 'owner',
          },
        ],
      },
    });
  });

  test(
    'stored access token refreshes through the explicit session contract',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-auth-refresh-',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = AuthStorage(root: root);
      final endpoint = Uri.parse('http://127.0.0.1:1');
      await storage.writeProfile(
        Profile(
          endpoint: endpoint,
          userId: 'usr_operator',
          email: 'operator@example.com',
          profiles: const <ProfileScope>[
            ProfileScope(
              name: 'demo',
              organizationId: 'org_demo',
              role: 'owner',
            ),
          ],
        ),
      );
      await storage.writeSession(
        AuthSession(
          accessToken: 'expired-access',
          sessionToken: 'session-secret',
          expiresAt: DateTime.utc(2020),
          sessionExpiresAt: DateTime.utc(2099),
        ),
      );
      final requests = <_Request>[];
      final server = await _startServer(requests, refreshOnly: true);
      addTearDown(() => server.close(force: true));
      await storage.writeProfile(
        Profile(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
          userId: 'usr_operator',
          email: 'operator@example.com',
          profiles: const <ProfileScope>[
            ProfileScope(
              name: 'demo',
              organizationId: 'org_demo',
              role: 'owner',
            ),
          ],
        ),
      );

      final client = AuthClient(storage: storage);
      expect(await client.accessTokenOrNull(), 'refreshed-access');
      expect(requests, hasLength(1));
      expect(requests.single.path, '/auth/refresh');
      expect(requests.single.body, <String, Object?>{
        'session_token': 'session-secret',
      });
      expect((await storage.readSession())!.accessToken, 'refreshed-access');
    },
  );

  test('public login reuses an existing named profile endpoint when host is omitted', () async {
    final root = await Directory.systemTemp.createTemp(
      'hyfens-auth-profile-login-',
    );
    addTearDown(() => root.delete(recursive: true));
    final storage = AuthStorage(root: root);
    final requests = <_Request>[];
    final server = await _startServer(requests);
    addTearDown(() => server.close(force: true));
    final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
    await storage.writeNamedProfile(
      CliProfile(name: 'acme', endpoint: endpoint, managed: false),
    );

    final result = await _runTool(
      const <String>[
        'login',
        '--profile',
        'acme',
        '--email',
        'operator@example.com',
        '--json',
      ],
      storage: storage,
      prompt: (message, {required secret}) async =>
          secret ? 'password-never-printed' : 'operator@example.com',
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(requests, hasLength(1));
    expect(requests.single.path, '/auth/login');
    expect((await storage.readActiveProfile()).name, 'acme');
    expect(
      (await storage.readActiveProfile()).endpoint,
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
  });

  test(
    'logout sends only the session token and clears local auth data',
    () async {
      final root = await Directory.systemTemp.createTemp('hyfens-auth-logout-');
      addTearDown(() => root.delete(recursive: true));
      final storage = AuthStorage(root: root);
      await storage.writeSession(
        const AuthSession(
          accessToken: 'access-secret',
          sessionToken: 'session-secret',
        ),
      );
      final requests = <_Request>[];
      final recordingServer = await _startServer(requests);
      addTearDown(() => recordingServer.close(force: true));
      await storage.writeProfile(
        Profile(
          endpoint: Uri.parse('http://127.0.0.1:${recordingServer.port}'),
          userId: 'usr_operator',
          email: 'operator@example.com',
          profiles: const <ProfileScope>[
            ProfileScope(
              name: 'demo',
              organizationId: 'org_demo',
              role: 'owner',
            ),
          ],
        ),
      );

      final client = AuthClient(storage: storage);
      await client.logout();
      expect(requests, hasLength(1));
      expect(requests.single.path, '/auth/logout');
      expect(requests.single.authorization, isNull);
      expect(requests.single.body, <String, Object?>{
        'session_token': 'session-secret',
      });
      expect(storage.profileFile.existsSync(), isFalse);
      expect(storage.sessionFile.existsSync(), isFalse);
    },
  );

  test('stored sessions cannot be sent to another endpoint', () async {
    final root = await Directory.systemTemp.createTemp('hyfens-auth-bound-');
    addTearDown(() => root.delete(recursive: true));
    final storage = AuthStorage(root: root);
    await storage.writeProfile(
      Profile(
        endpoint: Uri.parse('https://control.example/p2/'),
        userId: 'usr_operator',
        email: 'operator@example.com',
        profiles: const <ProfileScope>[
          ProfileScope(name: 'demo', organizationId: 'org_demo', role: 'owner'),
        ],
      ),
    );
    await storage.writeSession(
      AuthSession(
        accessToken: 'access-secret',
        sessionToken: 'session-secret',
        expiresAt: DateTime.utc(2099),
        sessionExpiresAt: DateTime.utc(2099),
      ),
    );
    final client = AuthClient(storage: storage);
    final otherEndpoint = Uri.parse('https://other.example/p2/');

    await expectLater(
      client.accessTokenOrNull(endpoint: otherEndpoint),
      throwsA(isA<ToolFailure>()),
    );
    await expectLater(
      client.refresh(endpoint: otherEndpoint),
      throwsA(isA<ToolFailure>()),
    );
    await expectLater(
      client.logout(endpoint: otherEndpoint),
      throwsA(isA<ToolFailure>()),
    );
    expect(storage.sessionFile.existsSync(), isTrue);
  });
}

Future<HttpServer> _startServer(
  List<_Request> requests, {
  bool refreshOnly = false,
}) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((request) async {
    final bytes = await request.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    final body = bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
    requests.add(
      _Request(
        method: request.method,
        path: request.uri.path,
        authorization: request.headers.value('authorization'),
        body: body,
      ),
    );
    final response = refreshOnly
        ? <String, Object?>{
            'access_token': 'refreshed-access',
            'expires_at': '2099-01-01T00:00:00.000Z',
          }
        : request.uri.path == '/auth/login'
        ? <String, Object?>{
            'access_token': 'access-secret',
            'expires_at': '2099-01-01T00:00:00.000Z',
            'session_token': 'session-secret',
            'session_expires_at': '2099-01-02T00:00:00.000Z',
            'user_id': 'usr_operator',
            'email': 'operator@example.com',
            'profiles': <Object?>[
              <String, Object?>{
                'name': 'demo',
                'organization_id': 'org_demo',
                'application_id': 'app_demo',
                'environment_id': 'env_demo',
                'role': 'owner',
              },
            ],
          }
        : <String, Object?>{'status': 'signed_out'};
    final encoded = utf8.encode(jsonEncode(response));
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.contentLength = encoded.length
      ..add(encoded);
    await request.response.close();
  });
  return server;
}

Future<_CommandResult> _runTool(
  List<String> arguments, {
  required AuthStorage storage,
  AuthPrompt? prompt,
}) async {
  final outputDirectory = await Directory.systemTemp.createTemp(
    'hyfens-auth-output-',
  );
  final stdoutFile = File('${outputDirectory.path}/stdout');
  final stderrFile = File('${outputDirectory.path}/stderr');
  final stdout = stdoutFile.openWrite();
  final stderr = stderrFile.openWrite();
  try {
    await HyfensCommandRunner(
      authStorage: storage,
      authPrompt: prompt,
      out: stdout,
      err: stderr,
    ).run(arguments);
  } finally {
    await stdout.close();
    await stderr.close();
  }
  try {
    return _CommandResult(
      exitCode: 0,
      stdout: await stdoutFile.readAsString(),
      stderr: await stderrFile.readAsString(),
    );
  } on Object catch (error) {
    return _CommandResult(exitCode: 1, stdout: '', stderr: '$error');
  } finally {
    await outputDirectory.delete(recursive: true);
  }
}

final class _CommandResult {
  const _CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

final class _Request {
  const _Request({
    required this.method,
    required this.path,
    required this.authorization,
    required this.body,
  });

  final String method;
  final String path;
  final String? authorization;
  final Object? body;
}
