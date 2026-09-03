import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late ControlPlaneService service;
  late ControlPlaneHttpServer adapter;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-platform-http-');
    store = FileControlPlaneStore(directory);
    final auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'platform-http-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 5),
        platformAdminEmails: const <String>[demoOwnerEmail],
      ),
    );
    service = ControlPlaneService(store: store, humanAuth: auth);
    await DemoAccountSeeder(
      store: store,
      auth: auth,
    ).seed(password: 'demo-password');
    adapter = ControlPlaneHttpServer(service);
    server = await adapter.bind();
  });

  tearDown(() async {
    await adapter.close(force: true);
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'authorizes the configured platform owner and denies ordinary owners',
    () async {
      final client = HttpClient();
      try {
        final unauthenticated = await _get(
          client,
          server.port,
          '/v1/platform/metrics',
        );
        expect(unauthenticated.statusCode, 401);

        final platformLogin = await _login(
          client,
          server.port,
          demoOwnerEmail,
          'demo-password',
          audience: platformAuthorizationAudience,
        );
        final profiles = platformLogin.body['profiles']! as List<Object?>;
        expect((profiles.single as Map<String, Object?>)['platform'], isTrue);
        expect(
          platformLogin.body['authorization_audience'],
          platformAuthorizationAudience,
        );

        final metrics = await _get(
          client,
          server.port,
          '/v1/platform/metrics?profile=$demoOwnerProfileName',
          token: platformLogin.body['access_token']! as String,
        );
        expect(metrics.statusCode, 200, reason: jsonEncode(metrics.body));
        expect(metrics.body['readOnly'], isTrue);
        expect(metrics.body['scope'], 'platform');
        expect(metrics.body['serviceMetrics'], isNotNull);
        expect(jsonEncode(metrics.body), isNot(contains('demo-password')));
        expect(jsonEncode(metrics.body), isNot(contains(demoOwnerEmail)));

        final wrongProfile = await _get(
          client,
          server.port,
          '/v1/platform/metrics?profile=client',
          token: platformLogin.body['access_token']! as String,
        );
        expect(wrongProfile.statusCode, 403);

        final other = await service.bootstrap(
          organizationName: 'Other organization',
          runtimeApplicationId: 'com.example.other',
          platformId: 'android',
          environmentName: 'development',
        );
        await service.bootstrapOwner(
          organizationId: other.organization.id,
          applicationId: other.application.id,
          environmentId: other.environment.id,
          email: 'other-owner@example.com',
          password: 'other-password',
        );
        final ordinaryLogin = await _login(
          client,
          server.port,
          'other-owner@example.com',
          'other-password',
        );
        final denied = await _get(
          client,
          server.port,
          '/v1/platform/metrics',
          token: ordinaryLogin.body['access_token']! as String,
        );
        expect(denied.statusCode, 403);

        for (final path in <String>[
          '/v1/platform/organizations',
          '/v1/platform/organizations/$demoOrganizationId',
          '/v1/platform/audit',
        ]) {
          final projectionDenied = await _get(
            client,
            server.port,
            path,
            token: ordinaryLogin.body['access_token']! as String,
          );
          expect(projectionDenied.statusCode, 403, reason: path);
        }
      } finally {
        client.close(force: true);
      }
    },
  );

  test('platform projections are bounded and customer routes reject platform sessions', () async {
    final client = HttpClient();
    try {
      final platformLogin = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
        audience: platformAuthorizationAudience,
      );
      final token = platformLogin.body['access_token']! as String;

      final organizations = await _get(
        client,
        server.port,
        '/v1/platform/organizations?profile=$demoOwnerProfileName',
        token: token,
      );
      expect(
        organizations.statusCode,
        200,
        reason: jsonEncode(organizations.body),
      );
      expect(organizations.body['scope'], 'platform');
      final values = organizations.body['organizations']! as List<Object?>;
      expect(values, isNotEmpty);
      final organization = values.single as Map<String, Object?>;
      expect(organization['id'], demoOrganizationId);
      expect(jsonEncode(organization), isNot(contains('passwordHash')));
      expect(jsonEncode(organization), isNot(contains('tokenHash')));

      final detail = await _get(
        client,
        server.port,
        '/v1/platform/organizations/$demoOrganizationId?profile=$demoOwnerProfileName',
        token: token,
      );
      expect(detail.statusCode, 200, reason: jsonEncode(detail.body));
      expect(detail.body['scope'], 'platform');
      expect(
        (detail.body['organization']! as Map<String, Object?>)['id'],
        demoOrganizationId,
      );

      final audit = await _get(
        client,
        server.port,
        '/v1/platform/audit?profile=$demoOwnerProfileName',
        token: token,
      );
      expect(audit.statusCode, 200, reason: jsonEncode(audit.body));
      expect(audit.body['scope'], 'platform');

      final customerRoute = await _get(
        client,
        server.port,
        '/v1/organizations/$demoOrganizationId/overview',
        token: token,
      );
      expect(customerRoute.statusCode, 403);

      final members = await _get(
        client,
        server.port,
        '/v1/organizations/$demoOrganizationId/members',
        token: token,
      );
      expect(members.statusCode, 403);
      expect(jsonEncode(members.body), isNot(contains('passwordHash')));

      final customerLogin = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
        audience: customerAuthorizationAudience,
      );
      final customerPlatformRoute = await _get(
        client,
        server.port,
        '/v1/platform/metrics',
        token: customerLogin.body['access_token']! as String,
      );
      expect(customerPlatformRoute.statusCode, 403);
    } finally {
      client.close(force: true);
    }
  });

  test('exposes bounded platform staff/commercial reads and customer lifecycle writes', () async {
    final client = HttpClient();
    try {
      final platformLogin = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
        audience: platformAuthorizationAudience,
      );
      final platformToken = platformLogin.body['access_token']! as String;
      final users = await _get(
        client,
        server.port,
        '/v1/platform/users?profile=$demoOwnerProfileName',
        token: platformToken,
      );
      expect(users.statusCode, 200, reason: jsonEncode(users.body));
      expect(users.body['scope'], 'platform');
      expect(jsonEncode(users.body), contains(demoOwnerEmail));
      expect(jsonEncode(users.body), isNot(contains('passwordHash')));
      expect(jsonEncode(users.body), isNot(contains('secretHash')));

      final entitlements = await _get(
        client,
        server.port,
        '/v1/platform/entitlements?profile=$demoOwnerProfileName',
        token: platformToken,
      );
      expect(
        entitlements.statusCode,
        200,
        reason: jsonEncode(entitlements.body),
      );
      expect(entitlements.body['scope'], 'platform');
      expect(entitlements.body['plans'], isA<List<Object?>>());
      expect(entitlements.body['subscriptions'], isA<List<Object?>>());

      final customerLogin = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
      );
      final customerToken = customerLogin.body['access_token']! as String;
      final application = await _postJson(
        client,
        server.port,
        '/v1/organizations/$demoOrganizationId/applications',
        token: customerToken,
        idempotencyKey: 'http-application-create-1',
        body: <String, Object?>{
          'name': 'HTTP test app',
          'platform': 'android',
          'runtime_application_id': 'com.auvanaventures.http_test',
        },
      );
      expect(application.statusCode, 201, reason: jsonEncode(application.body));
      final applicationId = application.body['id']! as String;

      final environment = await _postJson(
        client,
        server.port,
        '/v1/organizations/$demoOrganizationId/applications/$applicationId/environments',
        token: customerToken,
        idempotencyKey: 'http-environment-create-1',
        body: <String, Object?>{'name': 'staging'},
      );
      expect(environment.statusCode, 201, reason: jsonEncode(environment.body));
      expect(environment.body['applicationId'], applicationId);

      final credential = await _postJson(
        client,
        server.port,
        '/v1/organizations/$demoOrganizationId/credentials',
        token: customerToken,
        idempotencyKey: 'http-credential-create-1',
        body: <String, Object?>{
          'name': 'HTTP test credential',
          'kind': 'control',
          'scopes': <String>['application:read'],
        },
      );
      expect(credential.statusCode, 201, reason: jsonEncode(credential.body));
      expect(credential.body['token'], isA<String>());
      expect(credential.body.containsKey('tokenHash'), isFalse);

      for (final path in <String>[
        '/v1/platform/users',
        '/v1/platform/entitlements',
      ]) {
        final denied = await _get(
          client,
          server.port,
          path,
          token: customerToken,
        );
        expect(denied.statusCode, 403, reason: path);
      }
    } finally {
      client.close(force: true);
    }
  });

  test('keeps commercial and support projections audience- and tenant-scoped', () async {
    final client = HttpClient();
    try {
      final platformLogin = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
        audience: platformAuthorizationAudience,
      );
      final platformToken = platformLogin.body['access_token']! as String;
      final platformProfile = demoOwnerProfileName;
      final commercial = await _get(
        client,
        server.port,
        '/v1/platform/commercial?profile=$platformProfile',
        token: platformToken,
      );
      expect(commercial.statusCode, 200, reason: jsonEncode(commercial.body));
      expect(commercial.body['scope'], 'platform');
      expect(commercial.body['status'], 'SOURCE_NOT_AVAILABLE');
      expect(jsonEncode(commercial.body), isNot(contains('passwordHash')));

      final customerLogin = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
      );
      final customerToken = customerLogin.body['access_token']! as String;
      final customerCommercial = await _get(
        client,
        server.port,
        '/v1/platform/commercial',
        token: customerToken,
      );
      expect(customerCommercial.statusCode, 403);

      final created = await _postJson(
        client,
        server.port,
        '/v1/organizations/$demoOrganizationId/support/cases',
        token: customerToken,
        body: <String, Object?>{
          'subject': 'Promotion needs review',
          'description': 'The demo environment needs a support response.',
          'priority': 'HIGH',
        },
      );
      expect(created.statusCode, 201, reason: jsonEncode(created.body));
      final caseId =
          ((created.body['case']! as Map<Object?, Object?>)['id']! as String);

      final platformCases = await _get(
        client,
        server.port,
        '/v1/platform/support/cases?profile=$platformProfile',
        token: platformToken,
      );
      expect(
        platformCases.statusCode,
        200,
        reason: jsonEncode(platformCases.body),
      );
      expect(platformCases.body['scope'], 'platform');
      expect(jsonEncode(platformCases.body), contains(caseId));

      final staffUserId = platformLogin.body['user_id']! as String;
      final updated = await _patchJson(
        client,
        server.port,
        '/v1/platform/support/cases/$caseId?profile=$platformProfile',
        token: platformToken,
        body: <String, Object?>{
          'status': 'IN_PROGRESS',
          'priority': 'URGENT',
          'assigned_to': staffUserId,
        },
      );
      expect(updated.statusCode, 200, reason: jsonEncode(updated.body));
      expect(
        (updated.body['case']! as Map<Object?, Object?>)['status'],
        'IN_PROGRESS',
      );

      final internal = await _postJson(
        client,
        server.port,
        '/v1/platform/support/cases/$caseId/messages?profile=$platformProfile',
        token: platformToken,
        body: <String, Object?>{
          'body': 'Staff-only investigation note.',
          'visibility': platformInternalSupportVisibility,
        },
      );
      expect(internal.statusCode, 200, reason: jsonEncode(internal.body));
      expect(
        jsonEncode(internal.body),
        contains('Staff-only investigation note.'),
      );

      final customerCase = await _get(
        client,
        server.port,
        '/v1/organizations/$demoOrganizationId/support/cases/$caseId',
        token: customerToken,
      );
      expect(
        customerCase.statusCode,
        200,
        reason: jsonEncode(customerCase.body),
      );
      expect(
        jsonEncode(customerCase.body),
        isNot(contains('Staff-only investigation note.')),
      );
      expect(
        jsonEncode(customerCase.body),
        isNot(contains(platformInternalSupportVisibility)),
      );

      final deniedPlatformSupport = await _get(
        client,
        server.port,
        '/v1/platform/support/cases',
        token: customerToken,
      );
      expect(deniedPlatformSupport.statusCode, 403);
    } finally {
      client.close(force: true);
    }
  });
}

Future<_Response> _login(
  HttpClient client,
  int port,
  String email,
  String password, {
  String audience = customerAuthorizationAudience,
}) async {
  final request = await client.postUrl(
    Uri.parse('http://127.0.0.1:$port/auth/login'),
  );
  final body = utf8.encode(
    jsonEncode(<String, Object?>{
      'email': email,
      'password': password,
      'audience': audience,
    }),
  );
  request
    ..headers.contentType = ContentType.json
    ..contentLength = body.length;
  request.add(body);
  final response = await request.close();
  return _decodeResponse(response);
}

Future<_Response> _get(
  HttpClient client,
  int port,
  String path, {
  String? token,
}) async {
  final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
  if (token != null) request.headers.set('Authorization', 'Bearer $token');
  final response = await request.close();
  return _decodeResponse(response);
}

Future<_Response> _postJson(
  HttpClient client,
  int port,
  String path, {
  required Map<String, Object?> body,
  String? token,
  String? idempotencyKey,
}) async {
  final request = await client.postUrl(
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  final encoded = utf8.encode(jsonEncode(body));
  request
    ..headers.contentType = ContentType.json
    ..contentLength = encoded.length;
  if (token != null) request.headers.set('Authorization', 'Bearer $token');
  if (idempotencyKey != null) {
    request.headers.set('Idempotency-Key', idempotencyKey);
  }
  request.add(encoded);
  final response = await request.close();
  return _decodeResponse(response);
}

Future<_Response> _patchJson(
  HttpClient client,
  int port,
  String path, {
  required Map<String, Object?> body,
  String? token,
}) async {
  final request = await client.openUrl(
    'PATCH',
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  final encoded = utf8.encode(jsonEncode(body));
  request
    ..headers.contentType = ContentType.json
    ..contentLength = encoded.length;
  if (token != null) request.headers.set('Authorization', 'Bearer $token');
  request.add(encoded);
  final response = await request.close();
  return _decodeResponse(response);
}

Future<_Response> _decodeResponse(HttpClientResponse response) async {
  final text = await response.transform(utf8.decoder).join();
  final decoded = text.isEmpty ? <String, Object?>{} : jsonDecode(text);
  return _Response(
    response.statusCode,
    decoded is Map
        ? <String, Object?>{
            for (final entry in decoded.entries) '${entry.key}': entry.value,
          }
        : <String, Object?>{},
  );
}

final class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}
