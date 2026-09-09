import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

const _webhookSecret = 'refund-workflow-webhook-secret';
const _operatorEmail = 'refund-operator@example.com';
const _operatorPassword = 'operator-password-123';
const _customerEmail = 'refund-customer@example.com';
const _customerPassword = 'customer-password-123';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late HumanAuthService auth;
  late ControlPlaneService service;
  late HttpServer server;
  late BootstrapResult customerScope;
  late BootstrapResult foreignScope;
  late String customerToken;
  late String operatorToken;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-refund-workflow-',
    );
    store = FileControlPlaneStore(directory);
    auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'refund-workflow-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 91),
        platformAdminEmails: const <String>[_operatorEmail],
      ),
    );
    service = ControlPlaneService(
      store: store,
      humanAuth: auth,
      deploymentModel: DeploymentModel.cloud,
      razorpayBilling: RazorpayBillingConfig(
        starterPlanId: 'rzp_plan_starter_refund',
        teamPlanId: 'rzp_plan_team_refund',
        webhookSecret: _webhookSecret,
        currency: 'USD',
        starterAmountMinor: 4900,
        teamAmountMinor: 19900,
      ),
    );
    customerScope = await service.bootstrap(
      organizationName: 'Refund customer',
      runtimeApplicationId: 'com.example.refund.customer',
      platformId: 'android',
      environmentName: 'development',
    );
    await service.bootstrapOwner(
      organizationId: customerScope.organization.id,
      applicationId: customerScope.application.id,
      environmentId: customerScope.environment.id,
      email: _customerEmail,
      password: _customerPassword,
    );
    foreignScope = await service.bootstrap(
      organizationName: 'Foreign refund customer',
      runtimeApplicationId: 'com.example.refund.foreign',
      platformId: 'android',
      environmentName: 'development',
    );
    await service.bootstrapOwner(
      organizationId: foreignScope.organization.id,
      applicationId: foreignScope.application.id,
      environmentId: foreignScope.environment.id,
      email: 'foreign-refund-customer@example.com',
      password: _customerPassword,
    );
    final operatorScope = await service.bootstrap(
      organizationName: 'Refund operator scope',
      runtimeApplicationId: 'com.example.refund.operator',
      platformId: 'android',
      environmentName: 'development',
    );
    await service.bootstrapOwner(
      organizationId: operatorScope.organization.id,
      applicationId: operatorScope.application.id,
      environmentId: operatorScope.environment.id,
      email: _operatorEmail,
      password: _operatorPassword,
      profileName: 'super-admin',
    );
    final customerLogin = await auth.login(
      email: _customerEmail,
      password: _customerPassword,
      audience: customerAuthorizationAudience,
    );
    customerToken = customerLogin.accessToken;
    final operatorLogin = await auth.login(
      email: _operatorEmail,
      password: _operatorPassword,
      audience: platformAuthorizationAudience,
    );
    operatorToken = operatorLogin.accessToken;
    server = await ControlPlaneHttpServer(service).bind();
  });

  tearDown(() async {
    await server.close(force: true);
    await store.close();
    await directory.delete(recursive: true);
  });

  test('customer requests a partial refund and an authorized operator executes it', () async {
    final payment = await _createCapturedPayment(
      service,
      customerScope,
      store,
      suffix: 'customer-review',
    );
    final paymentId = payment['id']! as String;
    final requestResponse = await _request(
      server,
      method: 'POST',
      path:
          '/v1/organizations/${customerScope.organization.id}/billing/refund-requests',
      token: customerToken,
      idempotencyKey: 'refund-request-customer-review',
      body: <String, Object?>{
        'payment_id': paymentId,
        'reason_category': 'duplicate_charge',
        'explanation': 'The same charge appeared twice in the customer ledger.',
        'requested_amount_minor': 2000,
      },
    );
    expect(
      requestResponse.statusCode,
      201,
      reason: jsonEncode(requestResponse.body),
    );
    final refundRequestId = requestResponse.body['id']! as String;
    expect(requestResponse.body['status'], 'requested');

    final foreignRequest = await _request(
      server,
      method: 'POST',
      path:
          '/v1/organizations/${foreignScope.organization.id}/billing/refund-requests',
      token: customerToken,
      idempotencyKey: 'refund-request-foreign',
      body: <String, Object?>{
        'payment_id': paymentId,
        'reason_category': 'duplicate_charge',
        'explanation': 'Cross-tenant attempt.',
      },
    );
    expect(foreignRequest.statusCode, anyOf(403, 404));

    final customerApprovalAttempt = await _request(
      server,
      method: 'POST',
      path: '/v1/platform/billing/refund-requests/$refundRequestId/approve',
      token: customerToken,
      body: <String, Object?>{
        'approved_amount_minor': 2000,
        'reason': 'Customer cannot approve a refund.',
      },
    );
    expect(customerApprovalAttempt.statusCode, anyOf(401, 403));

    final operatorList = await _request(
      server,
      method: 'GET',
      path: '/v1/platform/billing/refund-requests',
      token: operatorToken,
    );
    expect(operatorList.statusCode, 200, reason: jsonEncode(operatorList.body));
    expect(operatorList.body['refund_requests'], hasLength(1));

    final approval = await _request(
      server,
      method: 'POST',
      path: '/v1/platform/billing/refund-requests/$refundRequestId/approve',
      token: operatorToken,
      body: <String, Object?>{
        'approved_amount_minor': 1500,
        'reason': 'Duplicate charge confirmed against captured payment.',
      },
    );
    expect(approval.statusCode, 200, reason: jsonEncode(approval.body));
    expect(approval.body['status'], 'approved');

    final preparation = await service.billing.prepareProviderRefund(
      refundRequestId: refundRequestId,
    );
    final repeatedPreparation = await service.billing.prepareProviderRefund(
      refundRequestId: refundRequestId,
    );
    expect(
      repeatedPreparation['providerRefundRecordId'],
      preparation['providerRefundRecordId'],
    );
    expect(
      repeatedPreparation['idempotencyKey'],
      preparation['idempotencyKey'],
    );

    final refundRawBody = _refundEventBody(
      eventId: 'evt_refund_processed',
      refundId: 'rfnd_refund_workflow_1',
      paymentId: payment['providerPaymentId']! as String,
      amount: 1500,
    );
    final processed = await service.billing.applyRazorpayWebhook(
      rawBody: refundRawBody,
      signature: _signature(refundRawBody),
    );
    final duplicate = await service.billing.applyRazorpayWebhook(
      rawBody: refundRawBody,
      signature: _signature(refundRawBody),
    );
    expect(processed.status, 'applied');
    expect(processed.refund?['status'], 'refunded');
    expect(duplicate.status, 'duplicate');
    expect(duplicate.refund?['status'], 'refunded');
    await expectLater(
      service.billing.recordProviderRefundResult(
        refundRequestId: refundRequestId,
        providerRefundRecordId:
            preparation['providerRefundRecordId']! as String,
        status: 'processed',
        providerRefundId: 'rfnd_different_payment',
        amountMinor: 1500,
        currency: 'USD',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'BILLING_PROVIDER_REFUND_CONFLICT',
        ),
      ),
    );

    final snapshot = await service.billing.read(
      organizationId: customerScope.organization.id,
    );
    expect(snapshot.payments.single['refundableBalanceMinor'], 3400);
    expect(snapshot.refundRequests.single['status'], 'refunded');
    expect(
      (await store.listJson('billing_subscriptions')).any(
        (row) =>
            row['organizationId'] == customerScope.organization.id &&
            row['status'] == 'active',
      ),
      isTrue,
    );

    final excess = await _request(
      server,
      method: 'POST',
      path:
          '/v1/organizations/${customerScope.organization.id}/billing/refund-requests',
      token: customerToken,
      idempotencyKey: 'refund-request-excess',
      body: <String, Object?>{
        'payment_id': paymentId,
        'reason_category': 'incorrect_amount',
        'explanation': 'This deliberately exceeds the remaining balance.',
        'requested_amount_minor': 3401,
      },
    );
    expect(excess.statusCode, 422);
    expect(
      (excess.body['error']! as Map)['code'],
      'REFUND_AMOUNT_EXCEEDS_BALANCE',
    );
  });

  test('full refund exhausts balance and an idempotent request can replay', () async {
    final payment = await _createCapturedPayment(
      service,
      customerScope,
      store,
      suffix: 'full-refund',
    );
    final paymentId = payment['id']! as String;
    final requestResponse = await _request(
      server,
      method: 'POST',
      path:
          '/v1/organizations/${customerScope.organization.id}/billing/refund-requests',
      token: customerToken,
      idempotencyKey: 'refund-request-full',
      body: <String, Object?>{
        'payment_id': paymentId,
        'reason_category': 'activation_failed',
        'explanation': 'The paid plan could not be activated.',
      },
    );
    expect(requestResponse.statusCode, 201);
    final refundRequestId = requestResponse.body['id']! as String;
    final approval = await _request(
      server,
      method: 'POST',
      path: '/v1/platform/billing/refund-requests/$refundRequestId/approve',
      token: operatorToken,
      body: <String, Object?>{
        'approved_amount_minor': 4900,
        'reason': 'Activation failure confirmed.',
      },
    );
    expect(approval.statusCode, 200, reason: jsonEncode(approval.body));

    final preparation = await service.billing.prepareProviderRefund(
      refundRequestId: refundRequestId,
    );
    final rawBody = _refundEventBody(
      eventId: 'evt_refund_full_processed',
      refundId: 'rfnd_refund_full',
      paymentId: payment['providerPaymentId']! as String,
      amount: 4900,
    );
    final result = await service.billing.applyRazorpayWebhook(
      rawBody: rawBody,
      signature: _signature(rawBody),
    );
    expect(result.refund?['status'], 'refunded');

    final replay = await _request(
      server,
      method: 'POST',
      path:
          '/v1/organizations/${customerScope.organization.id}/billing/refund-requests',
      token: customerToken,
      idempotencyKey: 'refund-request-full',
      body: <String, Object?>{
        'payment_id': paymentId,
        'reason_category': 'activation_failed',
        'explanation': 'The paid plan could not be activated.',
      },
    );
    expect(replay.statusCode, 201, reason: jsonEncode(replay.body));
    expect(replay.body['id'], refundRequestId);
    expect(replay.body['status'], 'refunded');
    expect(
      (await service.billing.read(
        organizationId: customerScope.organization.id,
      )).payments.single['refundableBalanceMinor'],
      0,
    );
    expect(preparation['amountMinor'], 4900);
  });

  test(
    'provider failure is retryable without a second refund for one attempt',
    () async {
      final payment = await _createCapturedPayment(
        service,
        customerScope,
        store,
        suffix: 'retryable',
      );
      final request = await service.billing.requestRefund(
        organizationId: customerScope.organization.id,
        paymentId: payment['id']! as String,
        reasonCategory: 'service_unavailable',
        explanation: 'The accepted service was unavailable after capture.',
        requestedAmountMinor: 1200,
        idempotencyKey: 'refund-request-retryable',
        actorId: 'customer-retryable',
      );
      final refundRequestId = request['id']! as String;
      final approvals = await Future.wait(<Future<Map<String, Object?>>>[
        service.billing.approveRefund(
          refundRequestId: refundRequestId,
          approvedAmountMinor: 1200,
          actorId: 'operator-a',
          decisionReason: 'Approved for review test.',
        ),
        service.billing.approveRefund(
          refundRequestId: refundRequestId,
          approvedAmountMinor: 1200,
          actorId: 'operator-a',
          decisionReason: 'Approved for review test.',
        ),
      ]);
      expect(
        approvals,
        everyElement(
          predicate<Map<String, Object?>>(
            (value) => value['status'] == 'approved',
          ),
        ),
      );

      final firstAttempt = await service.billing.prepareProviderRefund(
        refundRequestId: refundRequestId,
      );
      await expectLater(
        service.billing.recordProviderRefundResult(
          refundRequestId: refundRequestId,
          providerRefundRecordId:
              firstAttempt['providerRefundRecordId']! as String,
          status: 'pending',
          providerRefundId: 'rfnd_pending_retryable',
          amountMinor: 1199,
          currency: 'USD',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'BILLING_PROVIDER_MISMATCH',
          ),
        ),
      );
      await service.billing.recordProviderRefundResult(
        refundRequestId: refundRequestId,
        providerRefundRecordId:
            firstAttempt['providerRefundRecordId']! as String,
        status: 'failed',
        errorCode: 'provider_timeout',
      );
      final secondAttempt = await service.billing.prepareProviderRefund(
        refundRequestId: refundRequestId,
      );
      expect(
        secondAttempt['providerRefundRecordId'],
        isNot(firstAttempt['providerRefundRecordId']),
      );
      expect(
        secondAttempt['idempotencyKey'],
        isNot(firstAttempt['idempotencyKey']),
      );

      final completed = await service.billing.recordProviderRefundResult(
        refundRequestId: refundRequestId,
        providerRefundRecordId:
            secondAttempt['providerRefundRecordId']! as String,
        status: 'processed',
        providerRefundId: 'rfnd_retryable_success',
        amountMinor: 1200,
        currency: 'USD',
      );
      expect(completed['status'], 'refunded');
      expect(
        (await store.listJson('billing_provider_refunds'))
            .where((row) => row['refundRequestId'] == refundRequestId),
        hasLength(2),
      );
      expect(
        (await store.listJson('billing_subscriptions')).any(
          (row) =>
              row['organizationId'] == customerScope.organization.id &&
              row['status'] == 'active',
        ),
        isTrue,
      );
    },
  );
}

Future<Map<String, Object?>> _createCapturedPayment(
  ControlPlaneService service,
  BootstrapResult scope,
  FileControlPlaneStore store, {
  required String suffix,
}) async {
  final checkout = await service.billing.startCheckout(
    organizationId: scope.organization.id,
    planKey: cloudPlanStarterKey,
    idempotencyKey: 'refund-checkout-$suffix',
  );
  await service.billing.upsertSubscription(
    organizationId: scope.organization.id,
    provider: 'razorpay',
    providerSubscriptionId: 'sub_refund_$suffix',
    providerPlanId: 'rzp_plan_starter_refund',
    status: 'active',
    planId: checkout['planId']! as String,
    checkoutId: checkout['id']! as String,
  );
  final rawBody = utf8.encode(
    jsonEncode(<String, Object?>{
      'id': 'evt_payment_refund_$suffix',
      'event': 'payment.captured',
      'created_at': 1788861600,
      'payload': <String, Object?>{
        'payment': <String, Object?>{
          'entity': <String, Object?>{
            'id': 'pay_refund_$suffix',
            'subscription_id': 'sub_refund_$suffix',
            'amount': 4900,
            'currency': 'USD',
            'status': 'captured',
            'captured': true,
          },
        },
      },
    }),
  );
  final applied = await service.billing.applyRazorpayWebhook(
    rawBody: rawBody,
    signature: _signature(rawBody),
  );
  expect(applied.status, 'applied');
  final payments = (await store.listJson('billing_payments'))
      .where((row) => row['organizationId'] == scope.organization.id);
  return payments.single;
}

List<int> _refundEventBody({
  required String eventId,
  required String refundId,
  required String paymentId,
  required int amount,
}) {
  return utf8.encode(
    jsonEncode(<String, Object?>{
      'id': eventId,
      'event': 'refund.processed',
      'created_at': 1788861601,
      'payload': <String, Object?>{
        'refund': <String, Object?>{
          'entity': <String, Object?>{
            'id': refundId,
            'payment_id': paymentId,
            'amount': amount,
            'currency': 'USD',
            'status': 'processed',
          },
        },
      },
    }),
  );
}

String _signature(List<int> body) {
  return Hmac(sha256, utf8.encode(_webhookSecret)).convert(body).toString();
}

Future<_JsonResponse> _request(
  HttpServer server, {
  required String method,
  required String path,
  String? token,
  String? idempotencyKey,
  Map<String, Object?>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('Accept', 'application/json');
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    if (idempotencyKey != null) {
      request.headers.set('Idempotency-Key', idempotencyKey);
    }
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

final class _JsonResponse {
  const _JsonResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}
