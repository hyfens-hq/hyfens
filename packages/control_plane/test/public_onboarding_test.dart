import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  late ControlPlaneHttpServer adapter;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-public-');
    store = FileControlPlaneStore(directory);
    final auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'public-onboarding-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 19),
      ),
    );
    service = ControlPlaneService(store: store, humanAuth: auth);
    bootstrap = await service.bootstrap(
      organizationName: 'Public onboarding test',
      runtimeApplicationId: 'com.example.public',
      platformId: 'android',
      environmentName: 'development',
    );
    adapter = ControlPlaneHttpServer(
      service,
      discovery: ControlPlaneDiscoveryConfig(
        apiBasePath: '/p2/',
        publicRegistrationOrganizationId: bootstrap.organization.id,
        webOrigins: const <String>{'https://dashboard.example'},
      ),
    );
    server = await adapter.bind();
  });

  tearDown(() async {
    await adapter.close(force: true);
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'registers a client in the configured tenant with overview reads only',
    () async {
      final response = await _request(
        server,
        method: 'POST',
        path: '/p2/v1/public/register',
        body: <String, Object?>{
          'email': ' Client@Example.com ',
          'password': 'correct horse battery staple',
        },
      );
      expect(response.statusCode, 200, reason: jsonEncode(response.body));
      expect(response.body['session_token'], startsWith('hfs.'));
      expect(response.body['email'], 'client@example.com');
      final profile = (response.body['profiles']! as List).single as Map;
      expect(profile['role'], 'client');
      expect(profile['organization_id'], bootstrap.organization.id);
      expect(profile['application_id'], isNull);
      expect(profile['environment_id'], isNull);
      expect(
        (profile['capabilities']! as List).cast<String>().toSet(),
        publicClientReadScopes,
      );
      expect(
        publicClientReadScopes.any((scope) => scope.endsWith(':write')),
        isFalse,
      );

      final users = await store.listJson('users');
      expect(users, hasLength(1));
      expect(users.single['active'], isTrue);
      expect(users.single['passwordHash'], startsWith('argon2id\$v=19\$'));
      expect(users.single['passwordHash'], isNot(contains('correct horse')));

      final overview = await _request(
        server,
        method: 'GET',
        path: '/p2/v1/organizations/${bootstrap.organization.id}/overview',
        token: response.body['access_token']! as String,
      );
      expect(overview.statusCode, 200, reason: jsonEncode(overview.body));
      expect(overview.body['organization'], bootstrap.organization.toJson());
    },
  );

  test('duplicate registration is deterministic and non-destructive', () async {
    final first = await _request(
      server,
      method: 'POST',
      path: '/p2/v1/public/register',
      body: <String, Object?>{
        'email': 'duplicate@example.com',
        'password': 'correct horse battery staple',
      },
    );
    expect(first.statusCode, 200, reason: jsonEncode(first.body));
    final before = (await store.listJson('users')).single;

    final duplicate = await _request(
      server,
      method: 'POST',
      path: '/p2/v1/public/register',
      body: <String, Object?>{
        'email': ' DUPLICATE@example.com ',
        'password': 'a different valid password',
      },
    );
    expect(duplicate.statusCode, 409, reason: jsonEncode(duplicate.body));
    expect(
      (duplicate.body['error']! as Map)['code'],
      'EMAIL_ALREADY_REGISTERED',
    );
    expect((await store.listJson('users')).single, before);
    expect(await store.listJson('sessions'), hasLength(1));
  });

  test(
    'waitlist and newsletter are durable, separate, normalized, and idempotent',
    () async {
      final waitlist = await _request(
        server,
        method: 'POST',
        path: '/p2/v1/public/waitlist',
        body: <String, Object?>{
          'email': ' Waiter@Example.com ',
          'name': ' Ada Lovelace ',
          'source': 'landing',
        },
      );
      final waitlistDuplicate = await _request(
        server,
        method: 'POST',
        path: '/p2/v1/public/waitlist',
        body: <String, Object?>{
          'email': 'waiter@example.com',
          'name': 'Changed name',
          'source': 'other',
        },
      );
      expect(waitlist.statusCode, 200, reason: jsonEncode(waitlist.body));
      expect(waitlistDuplicate.statusCode, 200);
      expect(waitlist.body['status'], 'accepted');
      expect(waitlistDuplicate.body['status'], 'accepted');

      final newsletter = await _request(
        server,
        method: 'POST',
        path: '/p2/v1/public/newsletter',
        body: <String, Object?>{'email': 'WAITER@example.com'},
      );
      final newsletterDuplicate = await _request(
        server,
        method: 'POST',
        path: '/p2/v1/public/newsletter',
        body: <String, Object?>{
          'email': ' waiter@example.com ',
          'name': 'Ignored duplicate',
        },
      );
      expect(newsletter.statusCode, 200);
      expect(newsletterDuplicate.statusCode, 200);
      expect(await store.listJson(publicWaitlistCollection), hasLength(1));
      expect(await store.listJson(publicNewsletterCollection), hasLength(1));
      final waitlistRecord = (await store.listJson(publicWaitlistCollection))
          .single;
      expect(waitlistRecord['email'], 'waiter@example.com');
      expect(waitlistRecord['name'], 'Ada Lovelace');
      expect(waitlistRecord['source'], 'landing');
      expect(waitlistRecord['emailDigest'], startsWith('sha256:'));
    },
  );

  test(
    'public routes enforce versioning, strict fields, CORS, and validation',
    () async {
      final unversioned = await _request(
        server,
        method: 'POST',
        path: '/p2/public/register',
        body: <String, Object?>{
          'email': 'unversioned@example.com',
          'password': 'correct horse battery staple',
        },
      );
      expect(unversioned.statusCode, 404);

      final extraField = await _request(
        server,
        method: 'POST',
        path: '/p2/v1/public/register',
        body: <String, Object?>{
          'email': 'extra@example.com',
          'password': 'correct horse battery staple',
          'organization_id': bootstrap.organization.id,
        },
      );
      expect(extraField.statusCode, 422);

      final invalidIntake = await _request(
        server,
        method: 'POST',
        path: '/p2/v1/public/waitlist',
        body: <String, Object?>{
          'email': 'invalid@example.com',
          'source': 'x' * (publicOnboardingSourceMaxLength + 1),
        },
      );
      expect(invalidIntake.statusCode, 422);

      final preflight = await _request(
        server,
        method: 'OPTIONS',
        path: '/p2/v1/public/register',
        requestHeaders: <String, String>{'Origin': 'https://dashboard.example'},
      );
      expect(preflight.statusCode, 204);
      expect(
        preflight.headers['access-control-allow-origin'],
        'https://dashboard.example',
      );

      final rejectedOrigin = await _request(
        server,
        method: 'POST',
        path: '/p2/v1/public/waitlist',
        requestHeaders: <String, String>{'Origin': 'https://evil.example'},
        body: <String, Object?>{'email': 'evil@example.com'},
      );
      expect(rejectedOrigin.statusCode, 403);
    },
  );

  test(
    'registration clearly fails closed without configured organization',
    () async {
      final unconfigured = ControlPlaneHttpServer(
        service,
        discovery: const ControlPlaneDiscoveryConfig(apiBasePath: '/p2/'),
      );
      final unconfiguredServer = await unconfigured.bind();
      addTearDown(() => unconfigured.close(force: true));
      final response = await _request(
        unconfiguredServer,
        method: 'POST',
        path: '/p2/v1/public/register',
        body: <String, Object?>{
          'email': 'disabled@example.com',
          'password': 'correct horse battery staple',
        },
      );
      expect(response.statusCode, 503);
      expect(
        (response.body['error']! as Map)['code'],
        'PUBLIC_REGISTRATION_UNAVAILABLE',
      );
    },
  );
}

Future<_Response> _request(
  HttpServer server, {
  required String method,
  required String path,
  String? token,
  Map<String, Object?>? body,
  Map<String, String>? requestHeaders,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    requestHeaders?.forEach((name, value) => request.headers.set(name, value));
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request
        ..headers.contentType = ContentType.json
        ..contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final source = await response.transform(utf8.decoder).join();
    final decoded = source.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(source);
    final result = _Response(
      statusCode: response.statusCode,
      headers: <String, String>{},
      body: decoded is Map
          ? <String, Object?>{
              for (final entry in decoded.entries) '${entry.key}': entry.value,
            }
          : <String, Object?>{},
    );
    response.headers.forEach((name, values) {
      result.headers[name] = values.join(',');
    });
    return result;
  } finally {
    client.close(force: true);
  }
}

final class _Response {
  const _Response({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Map<String, Object?> body;
}
