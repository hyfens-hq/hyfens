import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

final class _CapturedAuthDelivery implements HumanAuthMessageDelivery {
  final List<String> verificationTokens = <String>[];
  final List<String> recoveryTokens = <String>[];

  @override
  Future<void> sendRecoveryEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) async {
    recoveryTokens.add(token);
  }

  @override
  Future<void> sendVerificationEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) async {
    verificationTokens.add(token);
  }
}

final class _JsonResponse {
  const _JsonResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late _CapturedAuthDelivery delivery;
  late HumanAuthService auth;
  late ControlPlaneService service;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-customer-onboarding-',
    );
    store = FileControlPlaneStore(directory);
    delivery = _CapturedAuthDelivery();
    auth = HumanAuthService(
      store: store,
      messageDelivery: delivery,
      config: HumanAuthConfig(
        issuer: 'customer-onboarding-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 41),
      ),
    );
    service = ControlPlaneService(
      store: store,
      humanAuth: auth,
      deploymentModel: DeploymentModel.cloud,
    );
    server = await ControlPlaneHttpServer(service).bind();
  });

  tearDown(() async {
    await server.close(force: true);
    await store.close();
    await directory.delete(recursive: true);
  });

  test('verified customer receives Free owner workspace and usable first scope', () async {
    final client = HttpClient();
    try {
      final registration = await _request(
        client,
        server,
        method: 'POST',
        path: '/v1/public/cloud/register',
        body: <String, Object?>{
          'email': 'new-customer@example.com',
          'password': 'correct horse battery staple',
          'organization_name': 'New Customer',
        },
      );
      expect(
        registration.statusCode,
        202,
        reason: jsonEncode(registration.body),
      );
      expect(registration.body['status'], 'verification_required');
      expect(delivery.verificationTokens, hasLength(1));
      expect(await store.listJson('organizations'), isEmpty);

      final verified = await _request(
        client,
        server,
        method: 'POST',
        path: '/v1/public/cloud/verify',
        body: <String, Object?>{'token': delivery.verificationTokens.single},
      );
      expect(verified.statusCode, 200, reason: jsonEncode(verified.body));
      final accessToken = verified.body['access_token']! as String;
      final profiles = verified.body['profiles']! as List<Object?>;
      expect(profiles, hasLength(1));
      final profile = profiles.single as Map<String, Object?>;
      expect(profile['role'], 'owner');
      expect(profile['capabilities'], contains(applicationWriteScope));
      expect(profile['capabilities'], contains(environmentRollbackScope));
      expect(profile['capabilities'], isNot(contains(contentAdminScope)));
      expect(profile['capabilities'], isNot(contains(billingWriteScope)));
      expect(profile['platform'], isNot(true));

      final organizationId = profile['organization_id']! as String;
      final billing = await _request(
        client,
        server,
        method: 'GET',
        path: '/v1/organizations/$organizationId/billing',
        token: accessToken,
      );
      expect(billing.statusCode, 200, reason: jsonEncode(billing.body));
      expect(billing.body['effective_plan'], isA<Map>());
      expect((billing.body['effective_plan']! as Map)['key'], cloudPlanFreeKey);
      expect(
        (await store.listJson('billing_subscriptions')).single['provider'],
        'internal',
      );

      final application = await _request(
        client,
        server,
        method: 'POST',
        path: '/v1/organizations/$organizationId/applications',
        token: accessToken,
        idempotencyKey: 'first-application',
        body: <String, Object?>{
          'runtime_application_id': 'com.example.customer',
          'name': 'Customer app',
          'platform': 'android',
        },
      );
      expect(application.statusCode, 201, reason: jsonEncode(application.body));
      final applicationId = application.body['id']! as String;

      final environment = await _request(
        client,
        server,
        method: 'POST',
        path:
            '/v1/organizations/$organizationId/applications/$applicationId/environments',
        token: accessToken,
        idempotencyKey: 'first-environment',
        body: <String, Object?>{'name': 'production'},
      );
      expect(environment.statusCode, 201, reason: jsonEncode(environment.body));

      final secondApplication = await _request(
        client,
        server,
        method: 'POST',
        path: '/v1/organizations/$organizationId/applications',
        token: accessToken,
        idempotencyKey: 'second-application',
        body: <String, Object?>{
          'runtime_application_id': 'com.example.customer.second',
        },
      );
      expect(secondApplication.statusCode, 422);
      expect(
        (secondApplication.body['error']! as Map)['code'],
        'PLAN_LIMIT_REACHED',
      );

      final secondEnvironment = await _request(
        client,
        server,
        method: 'POST',
        path:
            '/v1/organizations/$organizationId/applications/$applicationId/environments',
        token: accessToken,
        idempotencyKey: 'second-environment',
        body: <String, Object?>{'name': 'staging'},
      );
      expect(secondEnvironment.statusCode, 422);
      expect(
        (secondEnvironment.body['error']! as Map)['code'],
        'PLAN_LIMIT_REACHED',
      );
    } finally {
      client.close(force: true);
    }
  });

  test('recovery keeps the same customer organization and verification is one-time', () async {
    final registration = await service.registerCloudCustomer(
      email: 'recover@example.com',
      password: 'correct horse battery staple',
      organizationName: 'Recovery workspace',
    );
    expect(registration.toJson()['status'], 'verification_required');
    await service.verifyCloudCustomer(
      token: delivery.verificationTokens.single,
    );
    final before = (await store.listJson('organizations')).single['id'];

    await auth.requestPasswordRecovery(email: 'recover@example.com');
    expect(delivery.recoveryTokens, hasLength(1));
    await auth.resetPassword(
      token: delivery.recoveryTokens.single,
      password: 'new correct horse battery staple',
    );
    final login = await auth.login(
      email: 'recover@example.com',
      password: 'new correct horse battery staple',
    );
    expect(login.identity.profiles.single.organizationId, before);

    await expectLater(
      service.verifyCloudCustomer(token: delivery.verificationTokens.single),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'EMAIL_VERIFICATION_INVALID',
        ),
      ),
    );
    expect(await store.listJson('organizations'), hasLength(1));
  });

  test(
    'customer organizations are isolated and onboarding is retry safe',
    () async {
      final first = await service.registerCloudCustomer(
        email: 'first@example.com',
        password: 'correct horse battery staple',
        organizationName: 'First workspace',
      );
      expect(first.expiresAt, isNotNull);
      final firstToken = delivery.verificationTokens.single;
      final verified = await service.verifyCloudCustomer(token: firstToken);
      final firstProfile = verified.identity.profiles.single;
      final firstOrganizationId = firstProfile.organizationId;

      final replay = await service.createCustomerOrganization(
        token: verified.accessToken,
        organizationName: 'First workspace',
        idempotencyKey: 'first-org:${verified.identity.user.id}',
      );
      expect((replay['organization']! as Map)['id'], firstOrganizationId);
      expect(await store.listJson('organizations'), hasLength(1));

      final second = await service.registerCloudCustomer(
        email: 'second@example.com',
        password: 'correct horse battery staple',
        organizationName: 'Second workspace',
      );
      final secondLogin = await service.verifyCloudCustomer(
        token: delivery.verificationTokens.last,
      );
      final secondOrganizationId =
          secondLogin.identity.profiles.single.organizationId;
      expect(secondOrganizationId, isNot(firstOrganizationId));
      expect(
        () => service.createApplication(
          token: secondLogin.accessToken,
          organizationId: firstOrganizationId,
          runtimeApplicationId: 'com.example.foreign',
          idempotencyKey: 'foreign-application',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.statusCode,
            'status',
            anyOf(401, 403, 404),
          ),
        ),
      );
      expect(second.expiresAt, isNotNull);
    },
  );

  test(
    'concurrent first-workspace retries converge on one organization',
    () async {
      await service.registerCloudCustomer(
        email: 'concurrent@example.com',
        password: 'correct horse battery staple',
        organizationName: 'Concurrent workspace',
      );
      final verification = await auth.verifyCustomerEmail(
        token: delivery.verificationTokens.single,
      );
      final session = await auth.issueSessionForVerifiedUser(
        userId: verification.user.id,
      );

      final results = await Future.wait(<Future<Map<String, Object?>>>[
        service.createCustomerOrganization(
          token: session.accessToken,
          organizationName: verification.organizationName,
          idempotencyKey: 'first-org:${verification.user.id}',
        ),
        service.createCustomerOrganization(
          token: session.accessToken,
          organizationName: verification.organizationName,
          idempotencyKey: 'first-org:${verification.user.id}',
        ),
      ]);

      final ids = results
          .map((result) => (result['organization']! as Map)['id'])
          .toSet();
      expect(ids, hasLength(1));
      expect(await store.listJson('organizations'), hasLength(1));
      expect(
        (await store.listJson('billing_subscriptions'))
            .where((row) => row['organizationId'] == ids.single),
        hasLength(1),
      );
    },
  );

  test('self-hosted public onboarding is unavailable and does not create Cloud state', () async {
    final selfHostedStore = FileControlPlaneStore(
      await Directory.systemTemp.createTemp('hyfens-self-hosted-onboarding-'),
    );
    addTearDown(() async {
      await selfHostedStore.close();
      await Directory(selfHostedStore.root.path).delete(recursive: true);
    });
    final selfHostedAuth = HumanAuthService(
      store: selfHostedStore,
      messageDelivery: delivery,
      config: HumanAuthConfig(
        issuer: 'self-hosted-onboarding-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 42),
      ),
    );
    final selfHosted = ControlPlaneService(
      store: selfHostedStore,
      humanAuth: selfHostedAuth,
      deploymentModel: DeploymentModel.selfHosted,
    );
    await expectLater(
      selfHosted.registerCloudCustomer(
        email: 'self-hosted@example.com',
        password: 'correct horse battery staple',
        organizationName: 'Not Cloud',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'CLOUD_ONBOARDING_UNAVAILABLE',
        ),
      ),
    );
    expect(await selfHostedStore.listJson('users'), isEmpty);
  });
}

Future<_JsonResponse> _request(
  HttpClient client,
  HttpServer server, {
  required String method,
  required String path,
  Map<String, Object?>? body,
  String? token,
  String? idempotencyKey,
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:${server.port}$path'),
  );
  request.headers.contentType = ContentType.json;
  request.headers.set('Accept', 'application/json');
  if (token != null) request.headers.set('Authorization', 'Bearer $token');
  if (idempotencyKey != null)
    request.headers.set('Idempotency-Key', idempotencyKey);
  if (body != null) request.write(jsonEncode(body));
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  final decoded = jsonDecode(text);
  return _JsonResponse(response.statusCode, decoded as Map<String, Object?>);
}
