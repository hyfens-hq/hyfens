import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

const _bridgeToken = 'billing-provider-test-token';
const _webhookSecret = 'billing-provider-webhook-secret';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late ControlPlaneService service;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-billing-provider-bridge-',
    );
    store = FileControlPlaneStore(directory);
    final auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'billing-provider-bridge-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 7),
      ),
    );
    service = ControlPlaneService(
      store: store,
      humanAuth: auth,
      deploymentModel: DeploymentModel.cloud,
      billingProvider: BillingProviderBridgeConfig(
        tokenHash: CredentialService.tokenHash(_bridgeToken),
      ),
      razorpayBilling: RazorpayBillingConfig(
        starterPlanId: 'rzp_plan_starter_bridge',
        teamPlanId: 'rzp_plan_team_bridge',
        webhookSecret: _webhookSecret,
        currency: 'USD',
        starterAmountMinor: 4900,
        teamAmountMinor: 19900,
      ),
    );
    await service.initialize();
    server = await ControlPlaneHttpServer(service).bind();
  });

  tearDown(() async {
    await server.close(force: true);
    await store.close();
    await directory.delete(recursive: true);
  });

  test('provider bridge resolves tenants from server-owned mappings', () async {
    final first = await service.bootstrap(
      organizationName: 'Bridge organization A',
      runtimeApplicationId: 'com.example.bridge.a',
      platformId: 'android',
      environmentName: 'development',
    );
    final second = await service.bootstrap(
      organizationName: 'Bridge organization B',
      runtimeApplicationId: 'com.example.bridge.b',
      platformId: 'android',
      environmentName: 'development',
    );
    final firstCheckout = await service.billing.startCheckout(
      organizationId: first.organization.id,
      planKey: 'starter',
      idempotencyKey: 'bridge-a-checkout',
    );
    final secondCheckout = await service.billing.startCheckout(
      organizationId: second.organization.id,
      planKey: 'starter',
      idempotencyKey: 'bridge-b-checkout',
    );

    final firstLink = await _request(
      server,
      method: 'POST',
      path:
          '/v1/billing/provider/checkouts/${firstCheckout['id']}/subscription',
      token: _bridgeToken,
      body: <String, Object?>{
        'provider_subscription_id': 'sub_bridge_a',
        'provider_plan_id': 'rzp_plan_starter_bridge',
        'provider_status': 'created',
      },
    );
    expect(firstLink.statusCode, 200, reason: jsonEncode(firstLink.body));
    expect(firstLink.body['organizationId'], first.organization.id);
    expect(
      BillingProviderBridgeConfig(
        tokenHash: CredentialService.tokenHash(_bridgeToken),
      ).principal.scopes,
      equals(<String>{billingProviderScope}),
    );
    expect(controlScopes, isNot(contains(billingProviderScope)));
    expect(customerOwnerScopes, isNot(contains(billingProviderScope)));

    final secondLink = await _request(
      server,
      method: 'POST',
      path:
          '/v1/billing/provider/checkouts/${secondCheckout['id']}/subscription',
      token: _bridgeToken,
      body: <String, Object?>{
        'provider_subscription_id': 'sub_bridge_b',
        'provider_plan_id': 'rzp_plan_starter_bridge',
        'provider_status': 'created',
      },
    );
    expect(secondLink.statusCode, 200, reason: jsonEncode(secondLink.body));
    expect(secondLink.body['organizationId'], second.organization.id);

    final retry = await _request(
      server,
      method: 'POST',
      path:
          '/v1/billing/provider/checkouts/${firstCheckout['id']}/subscription',
      token: _bridgeToken,
      body: <String, Object?>{
        'provider_subscription_id': 'sub_bridge_a',
        'provider_plan_id': 'rzp_plan_starter_bridge',
        'provider_status': 'created',
      },
    );
    expect(retry.statusCode, 200, reason: jsonEncode(retry.body));
    expect((await store.listJson('billing_provider_mappings')), hasLength(2));
    expect(
      (await store.listJson('billing_subscriptions'))
          .where((row) => row['provider'] == 'razorpay'),
      hasLength(2),
    );

    final foreignReuse = await _request(
      server,
      method: 'POST',
      path:
          '/v1/billing/provider/checkouts/${secondCheckout['id']}/subscription',
      token: _bridgeToken,
      body: <String, Object?>{
        'provider_subscription_id': 'sub_bridge_a',
        'provider_plan_id': 'rzp_plan_starter_bridge',
        'provider_status': 'created',
      },
    );
    expect(foreignReuse.statusCode, 409);

    final arbitraryOrganization = await _request(
      server,
      method: 'POST',
      path:
          '/v1/billing/provider/checkouts/${firstCheckout['id']}/subscription',
      token: _bridgeToken,
      body: <String, Object?>{
        'organization_id': second.organization.id,
        'provider_subscription_id': 'sub_bridge_new',
        'provider_plan_id': 'rzp_plan_starter_bridge',
      },
    );
    expect(arbitraryOrganization.statusCode, 422);

    final unsafeActivation = await _request(
      server,
      method: 'POST',
      path:
          '/v1/billing/provider/checkouts/${firstCheckout['id']}/subscription',
      token: _bridgeToken,
      body: <String, Object?>{
        'provider_subscription_id': 'sub_bridge_active_without_event',
        'provider_plan_id': 'rzp_plan_starter_bridge',
        'provider_status': 'active',
      },
    );
    expect(unsafeActivation.statusCode, 409);

    final customerCannotUseBridge = await _request(
      server,
      method: 'POST',
      path:
          '/v1/billing/provider/checkouts/${firstCheckout['id']}/subscription',
      token: first.controlCredential.token,
      body: <String, Object?>{
        'provider_subscription_id': 'sub_customer_attempt',
        'provider_plan_id': 'rzp_plan_starter_bridge',
      },
    );
    expect(customerCannotUseBridge.statusCode, 401);

    final bridgeCannotUseCustomerRoute = await _request(
      server,
      method: 'GET',
      path: '/v1/organizations/${first.organization.id}/billing',
      token: _bridgeToken,
    );
    expect(bridgeCannotUseCustomerRoute.statusCode, 401);

    final bridgeCannotUsePlatformRoute = await _request(
      server,
      method: 'GET',
      path: '/v1/platform/metrics',
      token: _bridgeToken,
    );
    expect(bridgeCannotUsePlatformRoute.statusCode, 401);

    final bridgeCannotUseCmsRoute = await _request(
      server,
      method: 'GET',
      path: '/cms/content',
      token: _bridgeToken,
    );
    expect(bridgeCannotUseCmsRoute.statusCode, 401);
  });

  test('signed provider events use the bridge mapping and stay idempotent', () async {
    final first = await service.bootstrap(
      organizationName: 'Webhook organization A',
      runtimeApplicationId: 'com.example.webhook.a',
      platformId: 'android',
      environmentName: 'development',
    );
    final second = await service.bootstrap(
      organizationName: 'Webhook organization B',
      runtimeApplicationId: 'com.example.webhook.b',
      platformId: 'android',
      environmentName: 'development',
    );
    final firstCheckout = await service.billing.startCheckout(
      organizationId: first.organization.id,
      planKey: 'starter',
      idempotencyKey: 'webhook-a-checkout',
    );
    final secondCheckout = await service.billing.startCheckout(
      organizationId: second.organization.id,
      planKey: 'starter',
      idempotencyKey: 'webhook-b-checkout',
    );
    final link = await _request(
      server,
      method: 'POST',
      path:
          '/v1/billing/provider/checkouts/${firstCheckout['id']}/subscription',
      token: _bridgeToken,
      body: <String, Object?>{
        'provider_subscription_id': 'sub_webhook_a',
        'provider_plan_id': 'rzp_plan_starter_bridge',
        'provider_status': 'created',
      },
    );
    expect(link.statusCode, 200, reason: jsonEncode(link.body));

    final rawBody = _eventBody(
      checkoutId: firstCheckout['id']! as String,
      subscriptionId: 'sub_webhook_a',
      eventId: 'evt_webhook_a_active',
      status: 'active',
    );
    final signedRequests = await Future.wait(<Future<_JsonResponse>>[
      _request(
        server,
        method: 'POST',
        path: '/v1/billing/provider/webhook',
        token: _bridgeToken,
        body: <String, Object?>{
          'raw_body': utf8.decode(rawBody),
          'signature': _signature(rawBody),
        },
      ),
      _request(
        server,
        method: 'POST',
        path: '/v1/billing/provider/webhook',
        token: _bridgeToken,
        body: <String, Object?>{
          'raw_body': utf8.decode(rawBody),
          'signature': _signature(rawBody),
        },
      ),
    ]);
    expect(
      signedRequests.map((response) => response.statusCode),
      everyElement(200),
    );
    expect(
      signedRequests.map((response) => response.body['status']),
      containsAll(<String>['applied', 'duplicate']),
    );
    expect(
      (await service.billing.read(organizationId: first.organization.id))
          .effectivePlan?['key'],
      'starter',
    );
    expect(await store.listJson('billing_events'), hasLength(1));
    expect(
      (await store.listJson('audit')).where(
        (row) =>
            row['action'] == 'billing.provider_event.applied' &&
            row['actorId'] == 'billing-provider',
      ),
      hasLength(1),
    );

    final wrongCheckoutBody = _eventBody(
      checkoutId: secondCheckout['id']! as String,
      subscriptionId: 'sub_webhook_a',
      eventId: 'evt_webhook_wrong_checkout',
      status: 'active',
    );
    final wrongCheckout = await _request(
      server,
      method: 'POST',
      path: '/v1/billing/provider/webhook',
      token: _bridgeToken,
      body: <String, Object?>{
        'raw_body': utf8.decode(wrongCheckoutBody),
        'signature': _signature(wrongCheckoutBody),
      },
    );
    expect(wrongCheckout.statusCode, 422);
    expect(
      (await service.billing.read(organizationId: second.organization.id))
          .effectivePlan?['key'],
      'free',
    );

    final secondLink = await _request(
      server,
      method: 'POST',
      path:
          '/v1/billing/provider/checkouts/${secondCheckout['id']}/subscription',
      token: _bridgeToken,
      body: <String, Object?>{
        'provider_subscription_id': 'sub_webhook_b',
        'provider_plan_id': 'rzp_plan_starter_bridge',
        'provider_status': 'created',
      },
    );
    expect(secondLink.statusCode, 200, reason: jsonEncode(secondLink.body));

    final wrongAmountBody = _eventBody(
      checkoutId: secondCheckout['id']! as String,
      subscriptionId: 'sub_webhook_b',
      eventId: 'evt_webhook_wrong_amount',
      status: 'active',
      amount: 1,
    );
    final wrongAmount = await _request(
      server,
      method: 'POST',
      path: '/v1/billing/provider/webhook',
      token: _bridgeToken,
      body: <String, Object?>{
        'raw_body': utf8.decode(wrongAmountBody),
        'signature': _signature(wrongAmountBody),
      },
    );
    expect(wrongAmount.statusCode, 422);

    final wrongCurrencyBody = _eventBody(
      checkoutId: secondCheckout['id']! as String,
      subscriptionId: 'sub_webhook_b',
      eventId: 'evt_webhook_wrong_currency',
      status: 'active',
      currency: 'INR',
    );
    final wrongCurrency = await _request(
      server,
      method: 'POST',
      path: '/v1/billing/provider/webhook',
      token: _bridgeToken,
      body: <String, Object?>{
        'raw_body': utf8.decode(wrongCurrencyBody),
        'signature': _signature(wrongCurrencyBody),
      },
    );
    expect(wrongCurrency.statusCode, 422);

    final selfHostedDirectory = await Directory.systemTemp.createTemp(
      'hyfens-self-hosted-bridge-',
    );
    final selfHostedStore = FileControlPlaneStore(selfHostedDirectory);
    final selfHosted = ControlPlaneService(
      store: selfHostedStore,
      deploymentModel: DeploymentModel.selfHosted,
      billingProvider: BillingProviderBridgeConfig(
        tokenHash: CredentialService.tokenHash(_bridgeToken),
      ),
    );
    try {
      await expectLater(
        selfHosted.authorizeBillingProvider(token: _bridgeToken),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.statusCode,
            'status code',
            401,
          ),
        ),
      );
    } finally {
      await selfHostedStore.close();
      await selfHostedDirectory.delete(recursive: true);
    }
  });
}

List<int> _eventBody({
  required String checkoutId,
  required String subscriptionId,
  required String eventId,
  required String status,
  int amount = 4900,
  String currency = 'USD',
}) => utf8.encode(
  jsonEncode(<String, Object?>{
    'id': eventId,
    'event': 'subscription.activated',
    'created_at': 1788861600,
    'payload': <String, Object?>{
      'subscription': <String, Object?>{
        'entity': <String, Object?>{
          'id': subscriptionId,
          'plan_id': 'rzp_plan_starter_bridge',
          'status': status,
          'amount': amount,
          'currency': currency,
          'created_at': 1788861600,
          'current_start': 1788861600,
          'notes': <String, Object?>{'hyfens_checkout_id': checkoutId},
        },
      },
    },
  }),
);

String _signature(List<int> body) =>
    Hmac(sha256, utf8.encode(_webhookSecret)).convert(body).toString();

final class _JsonResponse {
  const _JsonResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

Future<_JsonResponse> _request(
  HttpServer server, {
  required String method,
  required String path,
  String? token,
  Map<String, Object?>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    request.headers
      ..contentType = ContentType.json
      ..set('Accept', 'application/json');
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(text) as Map;
    return _JsonResponse(response.statusCode, <String, Object?>{
      for (final entry in decoded.entries) entry.key as String: entry.value,
    });
  } finally {
    client.close(force: true);
  }
}
