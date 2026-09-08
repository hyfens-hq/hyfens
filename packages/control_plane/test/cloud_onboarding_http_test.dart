import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late ControlPlaneHttpServer adapter;
  late HttpServer server;
  late _CaptureVerificationDelivery delivery;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-cloud-onboarding-',
    );
    store = FileControlPlaneStore(directory);
    final auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'cloud-onboarding-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 41),
      ),
    );
    final service = ControlPlaneService(store: store, humanAuth: auth);
    delivery = _CaptureVerificationDelivery();
    adapter = ControlPlaneHttpServer(
      service,
      discovery: const ControlPlaneDiscoveryConfig(
        webOrigins: <String>{'https://app.example'},
      ),
      cloudOnboarding: CloudOnboardingConfig(
        enabled: true,
        verificationUrl: Uri.parse('https://app.example/verify-email'),
      ),
      cloudSignupDelivery: delivery,
    );
    server = await adapter.bind();
  });

  tearDown(() async {
    await adapter.close(force: true);
    await store.close();
    await directory.delete(recursive: true);
  });

  test('signup verifies an owner and resumes through app/environment creation', () async {
    final client = HttpClient();
    try {
      final signup = await _request(
        client,
        server,
        method: 'POST',
        path: '/v1/cloud/signup',
        origin: 'https://app.example',
        body: <String, Object?>{
          'email': ' Owner@Example.com ',
          'password': 'correct horse battery staple',
          'organization_name': 'Acme Cloud',
        },
      );
      expect(signup.statusCode, HttpStatus.accepted, reason: signup.bodyText);
      expect(signup.body['status'], 'verification_required');
      expect(signup.body['email'], 'owner@example.com');
      expect(signup.body.containsKey('token'), isFalse);
      expect(delivery.requests, hasLength(1));
      expect(delivery.requests.single.email, 'owner@example.com');

      expect(await store.listJson('users'), isEmpty);
      expect(await store.listJson('organizations'), isEmpty);

      final verification = await _request(
        client,
        server,
        method: 'POST',
        path: '/v1/cloud/verify',
        origin: 'https://app.example',
        body: <String, Object?>{
          'email': 'owner@example.com',
          'token': delivery.token,
        },
      );
      expect(
        verification.statusCode,
        HttpStatus.ok,
        reason: verification.bodyText,
      );
      expect(verification.body['authorization_audience'], 'customer');
      final organizationId = verification.body['organization_id']! as String;
      expect(verification.body['onboarding_status'], 'needs_application');
      expect((verification.body['profiles']! as List), hasLength(1));

      final signupRecord = (await store.listJson('cloud_signups')).single;
      expect(signupRecord['status'], 'verified');
      expect(signupRecord.containsKey('passwordHash'), isFalse);
      expect(signupRecord['tokenHash'], isNot(delivery.token));
      expect(await store.listJson('users'), hasLength(1));
      expect(await store.listJson('organizations'), hasLength(1));
      expect(await store.listJson('cloud_onboarding'), hasLength(1));

      final accessToken = verification.body['access_token']! as String;
      final application = await _request(
        client,
        server,
        method: 'POST',
        path: '/v1/organizations/$organizationId/applications',
        token: accessToken,
        idempotencyKey: 'cloud-onboarding-app-1',
        body: <String, Object?>{
          'runtime_application_id': 'com.example.cloud',
          'name': 'Cloud app',
          'platform': 'ios',
        },
      );
      expect(
        application.statusCode,
        HttpStatus.created,
        reason: application.bodyText,
      );
      final applicationId = application.body['id']! as String;

      final applicationRetry = await _request(
        client,
        server,
        method: 'POST',
        path: '/v1/organizations/$organizationId/applications',
        token: accessToken,
        idempotencyKey: 'cloud-onboarding-app-1',
        body: <String, Object?>{
          'runtime_application_id': 'com.example.cloud',
          'name': 'Cloud app',
          'platform': 'ios',
        },
      );
      expect(applicationRetry.statusCode, HttpStatus.created);
      expect(applicationRetry.body['id'], applicationId);
      expect(await store.listJson('applications'), hasLength(1));

      final environment = await _request(
        client,
        server,
        method: 'POST',
        path:
            '/v1/organizations/$organizationId/applications/$applicationId/environments',
        token: accessToken,
        idempotencyKey: 'cloud-onboarding-env-1',
        body: <String, Object?>{'name': 'development'},
      );
      expect(
        environment.statusCode,
        HttpStatus.created,
        reason: environment.bodyText,
      );
      expect(environment.body['organizationId'], organizationId);
      expect(environment.body['applicationId'], applicationId);
      expect(await store.listJson('environments'), hasLength(1));

      final verificationRetry = await _request(
        client,
        server,
        method: 'POST',
        path: '/v1/cloud/verify',
        origin: 'https://app.example',
        body: <String, Object?>{
          'email': 'owner@example.com',
          'token': delivery.token,
        },
      );
      expect(verificationRetry.statusCode, HttpStatus.ok);
      expect(verificationRetry.body['organization_id'], organizationId);
      expect(await store.listJson('users'), hasLength(1));
      expect(await store.listJson('organizations'), hasLength(1));
      expect(await store.listJson('applications'), hasLength(1));
      expect(await store.listJson('environments'), hasLength(1));
    } finally {
      client.close(force: true);
    }
  });

  test(
    'duplicate signup stays generic and invalid verification fails closed',
    () async {
      final client = HttpClient();
      try {
        final first = await _request(
          client,
          server,
          method: 'POST',
          path: '/v1/cloud/signup',
          body: <String, Object?>{
            'email': 'duplicate@example.com',
            'password': 'correct horse battery staple',
            'organization_name': 'First org',
          },
        );
        final second = await _request(
          client,
          server,
          method: 'POST',
          path: '/v1/cloud/signup',
          body: <String, Object?>{
            'email': ' DUPLICATE@example.com ',
            'password': 'a different valid password',
            'organization_name': 'Second org',
          },
        );
        expect(first.statusCode, HttpStatus.accepted);
        expect(second.statusCode, HttpStatus.accepted);
        expect(delivery.requests, hasLength(2));
        expect(await store.listJson('cloud_signups'), hasLength(1));

        final invalid = await _request(
          client,
          server,
          method: 'POST',
          path: '/v1/cloud/verify',
          body: <String, Object?>{
            'email': 'duplicate@example.com',
            'token': 'A' * 43,
          },
        );
        expect(invalid.statusCode, HttpStatus.badRequest);
        expect(invalid.body['error'], isA<Map>());
        expect(await store.listJson('users'), isEmpty);
        expect(await store.listJson('organizations'), isEmpty);
      } finally {
        client.close(force: true);
      }
    },
  );

  test(
    'disabled signup does not alter legacy client registration semantics',
    () async {
      final directory2 = await Directory.systemTemp.createTemp(
        'hyfens-cloud-onboarding-disabled-',
      );
      final store2 = FileControlPlaneStore(directory2);
      final auth2 = HumanAuthService(
        store: store2,
        config: HumanAuthConfig(
          issuer: 'cloud-onboarding-disabled-test',
          audience: 'hyfens-control',
          signingKeySeed: List<int>.filled(32, 42),
        ),
      );
      final service2 = ControlPlaneService(store: store2, humanAuth: auth2);
      final bootstrap = await service2.bootstrap(
        organizationName: 'Legacy tenant',
        runtimeApplicationId: 'com.example.legacy',
        platformId: 'ios',
        environmentName: 'development',
      );
      final adapter2 = ControlPlaneHttpServer(
        service2,
        discovery: ControlPlaneDiscoveryConfig(
          publicRegistrationOrganizationId: bootstrap.organization.id,
        ),
      );
      final server2 = await adapter2.bind();
      final client = HttpClient();
      try {
        final cloud = await _request(
          client,
          server2,
          method: 'POST',
          path: '/v1/cloud/signup',
          body: <String, Object?>{
            'email': 'legacy@example.com',
            'password': 'correct horse battery staple',
            'organization_name': 'Should not be created',
          },
        );
        expect(cloud.statusCode, HttpStatus.serviceUnavailable);

        final legacy = await _request(
          client,
          server2,
          method: 'POST',
          path: '/v1/public/register',
          body: <String, Object?>{
            'email': 'legacy@example.com',
            'password': 'correct horse battery staple',
          },
        );
        expect(legacy.statusCode, HttpStatus.ok, reason: legacy.bodyText);
        final profile = (legacy.body['profiles']! as List).single as Map;
        expect(profile['role'], 'client');
        expect(profile['organization_id'], bootstrap.organization.id);
        expect(await store2.listJson('cloud_signups'), isEmpty);
      } finally {
        client.close(force: true);
        await adapter2.close(force: true);
        await store2.close();
        await directory2.delete(recursive: true);
      }
    },
  );
}

final class _CaptureVerificationDelivery
    implements CloudSignupVerificationDelivery {
  final List<CloudSignupVerificationRequest> requests =
      <CloudSignupVerificationRequest>[];

  String get token => requests.last.verificationUrl.queryParameters['token']!;

  @override
  Future<void> deliver(CloudSignupVerificationRequest request) async {
    requests.add(request);
  }
}

Future<_Response> _request(
  HttpClient client,
  HttpServer server, {
  required String method,
  required String path,
  String? token,
  String? idempotencyKey,
  String? origin,
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
  if (origin != null) request.headers.set('Origin', origin);
  if (encoded != null) {
    request
      ..headers.contentType = ContentType.json
      ..contentLength = encoded.length;
    request.add(encoded);
  }
  final response = await request.close();
  final bodyText = await response.transform(utf8.decoder).join();
  final decoded = bodyText.isEmpty ? <String, Object?>{} : jsonDecode(bodyText);
  return _Response(
    statusCode: response.statusCode,
    body: decoded is Map
        ? <String, Object?>{
            for (final entry in decoded.entries) '${entry.key}': entry.value,
          }
        : <String, Object?>{},
    bodyText: bodyText,
  );
}

final class _Response {
  const _Response({
    required this.statusCode,
    required this.body,
    required this.bodyText,
  });

  final int statusCode;
  final Map<String, Object?> body;
  final String bodyText;
}
