import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

const _webhookSecret = 'billing-fixture-secret';
const _bridgeToken = 'billing-provider-fixture-token';

final class _CapturedDelivery implements HumanAuthMessageDelivery {
  final List<String> verificationTokens = <String>[];

  @override
  Future<void> sendRecoveryEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) async {}

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
  late _CapturedDelivery delivery;
  late ControlPlaneService service;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-customer-billing-',
    );
    store = FileControlPlaneStore(directory);
    delivery = _CapturedDelivery();
    final auth = HumanAuthService(
      store: store,
      messageDelivery: delivery,
      config: HumanAuthConfig(
        issuer: 'customer-billing-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 67),
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
        starterPlanId: 'rzp_plan_starter_fixture',
        teamPlanId: 'rzp_plan_team_fixture',
        webhookSecret: _webhookSecret,
        currency: 'USD',
        starterAmountMinor: 4900,
        teamAmountMinor: 19900,
      ),
    );
    server = await ControlPlaneHttpServer(service).bind();
    _currentDelivery = delivery;
    _activeServer = server;
  });

  tearDown(() async {
    await server.close(force: true);
    _activeServer = null;
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'customer can move Free to Starter to Team on one organization',
    () async {
      final customer = await _createCustomer();
      final organizationId = customer.organizationId;
      final applicationId = await _createApplication(
        customer.token,
        organizationId,
      );
      final environmentId = await _createEnvironment(
        customer.token,
        organizationId,
        applicationId,
        'development',
      );
      final initial = await _request(
        method: 'GET',
        path: '/v1/organizations/$organizationId/billing',
        token: customer.token,
      );
      expect((initial.body['effective_plan']! as Map)['key'], cloudPlanFreeKey);

      final starterCheckout = await _startCheckout(
        customer.token,
        organizationId,
        cloudPlanStarterKey,
        'starter-upgrade',
      );
      final starterEvent = await _applyEvent(
        checkout: starterCheckout,
        subscriptionId: 'sub_starter_fixture',
        planId: 'rzp_plan_starter_fixture',
        eventId: 'evt_starter_active',
        eventName: 'subscription.activated',
        status: 'active',
        createdAt: '2026-09-08T10:00:00Z',
        amount: 4900,
      );
      expect(
        starterEvent.statusCode,
        200,
        reason: jsonEncode(starterEvent.body),
      );
      expect(starterEvent.body['status'], 'applied');

      final afterStarter = await _request(
        method: 'GET',
        path: '/v1/organizations/$organizationId/billing',
        token: customer.token,
      );
      expect(
        (afterStarter.body['effective_plan']! as Map)['key'],
        cloudPlanStarterKey,
      );
      final secondEnvironmentId = await _createEnvironment(
        customer.token,
        organizationId,
        applicationId,
        'staging',
      );
      expect(secondEnvironmentId, isNot(environmentId));

      final teamCheckout = await _startCheckout(
        customer.token,
        organizationId,
        cloudPlanTeamKey,
        'team-upgrade',
      );
      await _applyEvent(
        checkout: teamCheckout,
        subscriptionId: 'sub_team_fixture',
        planId: 'rzp_plan_team_fixture',
        eventId: 'evt_team_active',
        eventName: 'subscription.activated',
        status: 'active',
        createdAt: '2026-09-08T11:00:00Z',
        amount: 19900,
      );

      final afterTeam = await _request(
        method: 'GET',
        path: '/v1/organizations/$organizationId/billing',
        token: customer.token,
      );
      expect(
        (afterTeam.body['effective_plan']! as Map)['key'],
        cloudPlanTeamKey,
      );
      expect(await store.listJson('organizations'), hasLength(1));
      expect(
        (await store.listJson('applications')).single['id'],
        applicationId,
      );
      expect(
        (await store.listJson('environments')).map((row) => row['id']),
        containsAll(<Object?>[environmentId, secondEnvironmentId]),
      );
      expect(
        (await store.listJson('billing_subscriptions'))
            .where((row) => row['status'] == 'superseded'),
        hasLength(1),
      );
    },
  );

  test(
    'provider subscription links to one checkout intent across retries',
    () async {
      final customer = await _createCustomer(
        email: 'provider-link@example.com',
      );
      final checkout = await _startCheckout(
        customer.token,
        customer.organizationId,
        cloudPlanStarterKey,
        'provider-link',
      );
      final checkoutId = checkout['id']! as String;
      final planId = checkout['planId']! as String;
      final retriedCheckout = await _startCheckout(
        customer.token,
        customer.organizationId,
        cloudPlanStarterKey,
        'provider-link-after-browser-retry',
      );
      expect(retriedCheckout['id'], checkoutId);

      await service.billing.upsertSubscription(
        organizationId: customer.organizationId,
        provider: 'razorpay',
        providerSubscriptionId: 'sub_provider_link',
        providerPlanId: 'rzp_plan_starter_fixture',
        status: 'created',
        planId: planId,
        checkoutId: checkoutId,
      );
      await service.billing.upsertSubscription(
        organizationId: customer.organizationId,
        provider: 'razorpay',
        providerSubscriptionId: 'sub_provider_link',
        providerPlanId: 'rzp_plan_starter_fixture',
        status: 'created',
        planId: planId,
        checkoutId: checkoutId,
      );

      final linked = await store.readJson(
        'billing_checkout_intents',
        checkoutId,
      );
      expect(linked?['providerSubscriptionId'], 'sub_provider_link');
      expect(
        (await store.listJson(
          'billing_subscriptions',
        )).where((row) => row['providerSubscriptionId'] == 'sub_provider_link'),
        hasLength(1),
      );
    },
  );

  test(
    'failed, delayed, duplicate, and out-of-order events are safe',
    () async {
      final customer = await _createCustomer(email: 'events@example.com');
      final checkout = await _startCheckout(
        customer.token,
        customer.organizationId,
        cloudPlanStarterKey,
        'event-safety',
      );
      final pending = await _applyEvent(
        checkout: checkout,
        subscriptionId: 'sub_event_fixture',
        planId: 'rzp_plan_starter_fixture',
        eventId: 'evt_pending',
        eventName: 'subscription.pending',
        status: 'pending',
        createdAt: '2026-09-08T12:00:00Z',
        amount: 4900,
      );
      expect(pending.body['status'], 'applied');
      final beforeActivation = await _request(
        method: 'GET',
        path: '/v1/organizations/${customer.organizationId}/billing',
        token: customer.token,
      );
      expect(
        (beforeActivation.body['effective_plan']! as Map)['key'],
        cloudPlanFreeKey,
      );

      final activeEvents = await Future.wait(<Future<_JsonResponse>>[
        _applyEvent(
          checkout: checkout,
          subscriptionId: 'sub_event_fixture',
          planId: 'rzp_plan_starter_fixture',
          eventId: 'evt_active',
          eventName: 'subscription.activated',
          status: 'active',
          createdAt: '2026-09-08T12:01:00Z',
          amount: 4900,
        ),
        _applyEvent(
          checkout: checkout,
          subscriptionId: 'sub_event_fixture',
          planId: 'rzp_plan_starter_fixture',
          eventId: 'evt_active',
          eventName: 'subscription.activated',
          status: 'active',
          createdAt: '2026-09-08T12:01:00Z',
          amount: 4900,
        ),
      ]);
      expect(
        activeEvents.map((response) => response.body['status']),
        containsAll(<String>['applied', 'duplicate']),
      );
      expect(
        (await store.listJson('audit')).where(
          (row) =>
              row['action'] == 'billing.provider_event.applied' &&
              (row['metadata'] as Map)['event_id'] == 'evt_active',
        ),
        hasLength(1),
      );

      final failedTeamCheckout = await _startCheckout(
        customer.token,
        customer.organizationId,
        cloudPlanTeamKey,
        'failed-team-upgrade',
      );
      final failed = await _applyEvent(
        checkout: failedTeamCheckout,
        subscriptionId: 'sub_failed_team_fixture',
        planId: 'rzp_plan_team_fixture',
        eventId: 'evt_payment_failed',
        eventName: 'payment.failed',
        status: 'pending',
        createdAt: '2026-09-08T12:02:00Z',
        amount: 19900,
      );
      expect(failed.body['status'], 'applied');
      final afterFailed = await _request(
        method: 'GET',
        path: '/v1/organizations/${customer.organizationId}/billing',
        token: customer.token,
      );
      expect(
        (afterFailed.body['effective_plan']! as Map)['key'],
        cloudPlanStarterKey,
      );

      final oldCancellation = await _applyEvent(
        checkout: checkout,
        subscriptionId: 'sub_event_fixture',
        planId: 'rzp_plan_starter_fixture',
        eventId: 'evt_old_cancel',
        eventName: 'subscription.cancelled',
        status: 'cancelled',
        createdAt: '2026-09-08T11:59:00Z',
        amount: 4900,
      );
      expect(oldCancellation.body['status'], 'ignored_out_of_order');
      final current = await _request(
        method: 'GET',
        path: '/v1/organizations/${customer.organizationId}/billing',
        token: customer.token,
      );
      expect(
        (current.body['effective_plan']! as Map)['key'],
        cloudPlanStarterKey,
      );
      expect((await store.listJson('billing_events')), hasLength(4));
    },
  );

  test(
    'cancelled checkout cannot be revived and provider outage preserves Free',
    () async {
      final customer = await _createCustomer(email: 'cancelled@example.com');
      final checkout = await _startCheckout(
        customer.token,
        customer.organizationId,
        cloudPlanStarterKey,
        'cancelled-checkout',
      );
      final cancelled = await _cancelCheckout(
        customer.token,
        customer.organizationId,
        checkout['id']! as String,
      );
      expect(cancelled.statusCode, 200, reason: jsonEncode(cancelled.body));
      expect(cancelled.body['status'], 'cancelled');
      final repeatedCancel = await _cancelCheckout(
        customer.token,
        customer.organizationId,
        checkout['id']! as String,
      );
      expect(repeatedCancel.statusCode, 200);

      final lateActivation = await _applyEvent(
        checkout: checkout,
        subscriptionId: 'sub_late_cancelled_fixture',
        planId: 'rzp_plan_starter_fixture',
        eventId: 'evt_late_cancelled_activation',
        eventName: 'subscription.activated',
        status: 'active',
        createdAt: '2026-09-08T12:30:00Z',
        amount: 4900,
      );
      expect(lateActivation.body['status'], 'ignored_terminal_checkout');
      final billing = await _request(
        method: 'GET',
        path: '/v1/organizations/${customer.organizationId}/billing',
        token: customer.token,
      );
      expect((billing.body['effective_plan']! as Map)['key'], cloudPlanFreeKey);
      expect(
        (await store.listJson('audit'))
            .where((row) => row['action'] == 'billing.checkout.cancelled'),
        hasLength(1),
      );

      final providerUnavailable = BillingService(
        store,
        deploymentModel: DeploymentModel.cloud,
      );
      await expectLater(
        providerUnavailable.startCheckout(
          organizationId: customer.organizationId,
          planKey: cloudPlanStarterKey,
          idempotencyKey: 'provider-outage',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'BILLING_PROVIDER_UNAVAILABLE',
          ),
        ),
      );
      final stillFree = await providerUnavailable.read(
        organizationId: customer.organizationId,
      );
      expect(stillFree.effectivePlan?['key'], cloudPlanFreeKey);
    },
  );

  test('cancellation is scheduled, then returns to Free without deletion', () async {
    final customer = await _createCustomer(email: 'cancel@example.com');
    final applicationId = await _createApplication(
      customer.token,
      customer.organizationId,
    );
    await _createEnvironment(
      customer.token,
      customer.organizationId,
      applicationId,
      'development',
    );
    final checkout = await _startCheckout(
      customer.token,
      customer.organizationId,
      cloudPlanStarterKey,
      'cancel-upgrade',
    );
    await _applyEvent(
      checkout: checkout,
      subscriptionId: 'sub_cancel_fixture',
      planId: 'rzp_plan_starter_fixture',
      eventId: 'evt_cancel_active',
      eventName: 'subscription.activated',
      status: 'active',
      createdAt: '2026-09-08T13:00:00Z',
      amount: 4900,
      currentEnd: '2026-10-08T13:00:00Z',
    );
    final cancellation = await _request(
      method: 'POST',
      path: '/v1/organizations/${customer.organizationId}/billing/cancel',
      token: customer.token,
      body: const <String, Object?>{},
    );
    expect(cancellation.statusCode, 200, reason: jsonEncode(cancellation.body));
    expect(cancellation.body['status'], 'scheduled');
    final stillPaid = await _request(
      method: 'GET',
      path: '/v1/organizations/${customer.organizationId}/billing',
      token: customer.token,
    );
    expect(
      (stillPaid.body['effective_plan']! as Map)['key'],
      cloudPlanStarterKey,
    );

    await _applyEvent(
      checkout: checkout,
      subscriptionId: 'sub_cancel_fixture',
      planId: 'rzp_plan_starter_fixture',
      eventId: 'evt_cancel_effective',
      eventName: 'subscription.cancelled',
      status: 'cancelled',
      createdAt: '2026-10-08T13:00:00Z',
      amount: 4900,
      currentEnd: '2026-10-08T13:00:00Z',
    );
    final afterCancellation = await _request(
      method: 'GET',
      path: '/v1/organizations/${customer.organizationId}/billing',
      token: customer.token,
    );
    expect(
      (afterCancellation.body['effective_plan']! as Map)['key'],
      cloudPlanFreeKey,
    );
    expect(await store.listJson('applications'), hasLength(1));
    expect(await store.listJson('environments'), hasLength(1));
    final blockedEnvironment = await _request(
      method: 'POST',
      path:
          '/v1/organizations/${customer.organizationId}/applications/$applicationId/environments',
      token: customer.token,
      idempotencyKey: 'free-after-cancel',
      body: <String, Object?>{'name': 'staging'},
    );
    expect(blockedEnvironment.statusCode, 422);
    expect(
      (blockedEnvironment.body['error']! as Map)['code'],
      'PLAN_LIMIT_REACHED',
    );
  });

  test('Team to Starter is scheduled, reversible, and applied at cycle end', () async {
    final customer = await _createCustomer(email: 'scheduled@example.com');
    final applicationId = await _createApplication(
      customer.token,
      customer.organizationId,
    );
    await _createEnvironment(
      customer.token,
      customer.organizationId,
      applicationId,
      'development',
    );
    final starterCheckout = await _startCheckout(
      customer.token,
      customer.organizationId,
      cloudPlanStarterKey,
      'scheduled-starter',
    );
    await _applyEvent(
      checkout: starterCheckout,
      subscriptionId: 'sub_scheduled_starter',
      planId: 'rzp_plan_starter_fixture',
      eventId: 'evt_scheduled_starter_active',
      eventName: 'subscription.activated',
      status: 'active',
      createdAt: '2026-09-08T15:00:00Z',
      amount: 4900,
      currentEnd: '2026-10-08T15:00:00Z',
    );
    await _createEnvironment(
      customer.token,
      customer.organizationId,
      applicationId,
      'staging',
    );

    final teamCheckout = await _startCheckout(
      customer.token,
      customer.organizationId,
      cloudPlanTeamKey,
      'scheduled-team',
    );
    await _applyEvent(
      checkout: teamCheckout,
      subscriptionId: 'sub_scheduled_team',
      planId: 'rzp_plan_team_fixture',
      eventId: 'evt_scheduled_team_active',
      eventName: 'subscription.activated',
      status: 'active',
      createdAt: '2026-09-08T16:00:00Z',
      amount: 19900,
      currentEnd: '2026-10-08T16:00:00Z',
    );
    await _createEnvironment(
      customer.token,
      customer.organizationId,
      applicationId,
      'qa',
    );

    final scheduled = await _request(
      method: 'POST',
      path: '/v1/organizations/${customer.organizationId}/billing/plan-change',
      token: customer.token,
      idempotencyKey: 'schedule-starter',
      body: <String, Object?>{'target_plan_key': cloudPlanStarterKey},
    );
    expect(scheduled.statusCode, 201, reason: jsonEncode(scheduled.body));
    expect(scheduled.body['status'], 'pending_provider');
    expect(scheduled.body['targetPlanKey'], cloudPlanStarterKey);

    final beforeProvider = await _request(
      method: 'GET',
      path: '/v1/organizations/${customer.organizationId}/billing',
      token: customer.token,
    );
    expect(
      (beforeProvider.body['effective_plan']! as Map)['key'],
      cloudPlanTeamKey,
    );

    final providerScheduled = await _confirmScheduledChange(
      providerSubscriptionId: 'sub_scheduled_team',
      providerPlanId: 'rzp_plan_starter_fixture',
      currentEndAt: '2026-10-08T16:00:00Z',
      changeScheduledAt: '2026-10-08T16:00:00Z',
    );
    expect(
      providerScheduled.statusCode,
      200,
      reason: jsonEncode(providerScheduled.body),
    );
    expect(providerScheduled.body['status'], 'scheduled');
    expect(providerScheduled.body['effectiveAt'], '2026-10-08T16:00:00Z');

    final afterProvider = await _request(
      method: 'GET',
      path: '/v1/organizations/${customer.organizationId}/billing',
      token: customer.token,
    );
    final scheduledProjection =
        afterProvider.body['scheduled_plan_change']! as Map;
    expect(
      (afterProvider.body['effective_plan']! as Map)['key'],
      cloudPlanTeamKey,
    );
    expect(scheduledProjection['targetPlanKey'], cloudPlanStarterKey);
    expect(scheduledProjection['effectiveAt'], '2026-10-08T16:00:00Z');

    final repeated = await _request(
      method: 'POST',
      path: '/v1/organizations/${customer.organizationId}/billing/plan-change',
      token: customer.token,
      idempotencyKey: 'schedule-starter-retry',
      body: <String, Object?>{'target_plan_key': cloudPlanStarterKey},
    );
    expect(repeated.statusCode, 201);
    expect(repeated.body['id'], scheduled.body['id']);

    final cancelled = await _request(
      method: 'POST',
      path:
          '/v1/organizations/${customer.organizationId}/billing/plan-change/cancel',
      token: customer.token,
      body: const <String, Object?>{},
    );
    expect(cancelled.statusCode, 200, reason: jsonEncode(cancelled.body));
    expect(cancelled.body['status'], 'cancelled');

    final afterCancel = await _request(
      method: 'GET',
      path: '/v1/organizations/${customer.organizationId}/billing',
      token: customer.token,
    );
    expect(afterCancel.body['scheduled_plan_change'], isNull);
    expect(
      (afterCancel.body['effective_plan']! as Map)['key'],
      cloudPlanTeamKey,
    );

    final lateProviderEvent = await _applyEvent(
      checkout: teamCheckout,
      subscriptionId: 'sub_scheduled_team',
      planId: 'rzp_plan_starter_fixture',
      eventId: 'evt_cancelled_schedule_late',
      eventName: 'subscription.updated',
      status: 'active',
      createdAt: '2026-09-08T17:00:00Z',
      amount: 4900,
      currentEnd: '2026-10-08T16:00:00Z',
    );
    expect(lateProviderEvent.statusCode, 422);
    expect(
      (lateProviderEvent.body['error']! as Map)['code'],
      'BILLING_PROVIDER_MISMATCH',
    );

    final rescheduled = await _request(
      method: 'POST',
      path: '/v1/organizations/${customer.organizationId}/billing/plan-change',
      token: customer.token,
      idempotencyKey: 'schedule-starter-again',
      body: <String, Object?>{'target_plan_key': cloudPlanStarterKey},
    );
    expect(rescheduled.statusCode, 201);
    expect(rescheduled.body['revision'], 2);
    await _confirmScheduledChange(
      providerSubscriptionId: 'sub_scheduled_team',
      providerPlanId: 'rzp_plan_starter_fixture',
      currentEndAt: '2026-10-08T16:00:00Z',
      changeScheduledAt: '2026-10-08T16:00:00Z',
    );

    final effective = await _applyEvent(
      checkout: teamCheckout,
      subscriptionId: 'sub_scheduled_team',
      planId: 'rzp_plan_starter_fixture',
      eventId: 'evt_scheduled_team_effective',
      eventName: 'subscription.updated',
      status: 'active',
      createdAt: '2026-10-08T16:00:00Z',
      amount: 4900,
      currentEnd: '2026-11-08T16:00:00Z',
      hasScheduledChanges: false,
    );
    expect(effective.statusCode, 200, reason: jsonEncode(effective.body));
    expect(
      (effective.body['scheduled_plan_change']! as Map)['status'],
      'effective',
    );

    final afterEffective = await _request(
      method: 'GET',
      path: '/v1/organizations/${customer.organizationId}/billing',
      token: customer.token,
    );
    expect(afterEffective.body['scheduled_plan_change'], isNull);
    expect(
      (afterEffective.body['effective_plan']! as Map)['key'],
      cloudPlanStarterKey,
    );
    final subscription = (afterEffective.body['subscriptions'] as List)
        .cast<Map>()
        .singleWhere(
          (row) => row['providerSubscriptionId'] == 'sub_scheduled_team',
        );
    expect(subscription['providerPlanId'], 'rzp_plan_starter_fixture');

    final overLimitEnvironment = await _request(
      method: 'POST',
      path:
          '/v1/organizations/${customer.organizationId}/applications/$applicationId/environments',
      token: customer.token,
      idempotencyKey: 'starter-over-limit-after-schedule',
      body: <String, Object?>{'name': 'production'},
    );
    expect(overLimitEnvironment.statusCode, 422);
    expect(
      (overLimitEnvironment.body['error']! as Map)['code'],
      'PLAN_LIMIT_REACHED',
    );
    expect(await store.listJson('environments'), hasLength(3));

    final planChanges = await store.listJson('billing_plan_changes');
    expect(
      planChanges.where((row) => row['status'] == 'cancelled'),
      hasLength(1),
    );
    expect(
      planChanges.where((row) => row['status'] == 'effective'),
      hasLength(1),
    );
    expect(
      (await store.listJson('audit'))
          .where((row) => row['action'] == 'billing.plan_change.effective'),
      hasLength(1),
    );
  });

  test(
    'Team to Free replaces a pending lower-plan change without early downgrade',
    () async {
      final customer = await _createCustomer(email: 'team-free@example.com');
      final applicationId = await _createApplication(
        customer.token,
        customer.organizationId,
      );
      await _createEnvironment(
        customer.token,
        customer.organizationId,
        applicationId,
        'development',
      );
      final checkout = await _startCheckout(
        customer.token,
        customer.organizationId,
        cloudPlanTeamKey,
        'team-free-upgrade',
      );
      await _applyEvent(
        checkout: checkout,
        subscriptionId: 'sub_team_free_fixture',
        planId: 'rzp_plan_team_fixture',
        eventId: 'evt_team_free_active',
        eventName: 'subscription.activated',
        status: 'active',
        createdAt: '2026-09-08T18:00:00Z',
        amount: 19900,
        currentEnd: '2026-10-08T18:00:00Z',
      );

      final starter = await _request(
        method: 'POST',
        path:
            '/v1/organizations/${customer.organizationId}/billing/plan-change',
        token: customer.token,
        idempotencyKey: 'team-free-starter-pending',
        body: <String, Object?>{'target_plan_key': cloudPlanStarterKey},
      );
      expect(starter.statusCode, 201);
      expect(starter.body['status'], 'pending_provider');

      final cancellation = await _request(
        method: 'POST',
        path: '/v1/organizations/${customer.organizationId}/billing/cancel',
        token: customer.token,
        body: const <String, Object?>{},
      );
      expect(cancellation.statusCode, 200);
      expect(cancellation.body['status'], 'scheduled');
      expect(cancellation.body['targetPlanKey'], cloudPlanFreeKey);

      final snapshot = await _request(
        method: 'GET',
        path: '/v1/organizations/${customer.organizationId}/billing',
        token: customer.token,
      );
      expect(
        (snapshot.body['effective_plan']! as Map)['key'],
        cloudPlanTeamKey,
      );
      expect(
        (snapshot.body['scheduled_plan_change']! as Map)['targetPlanKey'],
        cloudPlanFreeKey,
      );
      final changes = await store.listJson('billing_plan_changes');
      expect(
        changes.where(
          (row) =>
              row['targetPlanKey'] == cloudPlanStarterKey &&
              row['status'] == 'superseded',
        ),
        hasLength(1),
      );
      expect(await store.listJson('billing_refund_requests'), isEmpty);
    },
  );

  test('customer billing is isolated from operator writes and invalid signatures', () async {
    final customer = await _createCustomer(email: 'authz@example.com');
    final otherCustomer = await _createCustomer(
      email: 'other-authz@example.com',
    );
    final foreignRead = await _request(
      method: 'GET',
      path: '/v1/organizations/${otherCustomer.organizationId}/billing',
      token: customer.token,
    );
    expect(foreignRead.statusCode, anyOf(403, 404));
    final foreignCheckout = await _request(
      method: 'POST',
      path:
          '/v1/organizations/${otherCustomer.organizationId}/billing/checkout',
      token: customer.token,
      idempotencyKey: 'foreign-checkout',
      body: <String, Object?>{'plan_key': cloudPlanStarterKey},
    );
    expect(foreignCheckout.statusCode, anyOf(403, 404));

    final operatorWrite = await _request(
      method: 'POST',
      path:
          '/v1/organizations/${customer.organizationId}/billing/subscriptions',
      token: customer.token,
      body: <String, Object?>{
        'provider': 'razorpay',
        'provider_subscription_id': 'operator-only',
        'provider_plan_id': 'operator-only',
        'status': 'active',
        'plan_id': 'not-available',
      },
    );
    expect(operatorWrite.statusCode, 403);
    final elevatedCredential = await _request(
      method: 'POST',
      path: '/v1/organizations/${customer.organizationId}/credentials',
      token: customer.token,
      body: <String, Object?>{
        'kind': 'control',
        'scopes': <String>[billingWriteScope],
      },
    );
    expect(elevatedCredential.statusCode, 403);

    final checkout = await _startCheckout(
      customer.token,
      customer.organizationId,
      cloudPlanStarterKey,
      'signature-check',
    );
    final body = _eventBody(
      checkout: checkout,
      subscriptionId: 'sub_signature_fixture',
      planId: 'rzp_plan_starter_fixture',
      eventId: 'evt_bad_signature',
      eventName: 'subscription.activated',
      status: 'active',
      createdAt: '2026-09-08T14:00:00Z',
      amount: 4900,
    );
    final invalid = await _request(
      method: 'POST',
      path: '/v1/billing/webhooks/razorpay',
      rawBody: body,
      headers: <String, String>{'X-Razorpay-Signature': '0' * 64},
    );
    expect(invalid.statusCode, 401);
  });

  test('Enterprise inquiry has a durable operator-owned destination', () async {
    final response = await _request(
      method: 'POST',
      path: '/v1/public/enterprise-inquiries',
      idempotencyKey: 'enterprise-contact-1',
      body: <String, Object?>{
        'email': 'buyer@example.com',
        'name': 'Buyer',
        'organization': 'Buyer Co',
        'message': 'We need custom Cloud governance.',
        'source': 'pricing',
      },
    );
    expect(response.statusCode, 202, reason: jsonEncode(response.body));
    expect(response.body['status'], 'received');
    expect(response.body['destination'], 'platform.enterprise_inquiries');
    expect(await store.listJson('enterprise_inquiries'), hasLength(1));
  });
}

final class _Customer {
  const _Customer(this.token, this.organizationId);

  final String token;
  final String organizationId;
}

Future<_Customer> _createCustomer({
  String email = 'billing@example.com',
}) async {
  final registration = await _request(
    method: 'POST',
    path: '/v1/public/cloud/register',
    body: <String, Object?>{
      'email': email,
      'password': 'correct horse battery staple',
      'organization_name': 'Billing customer',
    },
  );
  expect(registration.statusCode, 202, reason: jsonEncode(registration.body));
  final deliveryTokens = _deliveryTokensForCurrentTest();
  expect(deliveryTokens, isNotEmpty);
  final verified = await _request(
    method: 'POST',
    path: '/v1/public/cloud/verify',
    body: <String, Object?>{'token': deliveryTokens.last},
  );
  expect(verified.statusCode, 200, reason: jsonEncode(verified.body));
  final profiles = verified.body['profiles']! as List<Object?>;
  final profile = profiles.single as Map<String, Object?>;
  return _Customer(
    verified.body['access_token']! as String,
    profile['organization_id']! as String,
  );
}

// The test helpers below are rebound in main's setUp through the zone-local
// values. Keeping the HTTP fixture small makes the provider event assertions
// read like the customer journey they protect.
late _CapturedDelivery _currentDelivery;

List<String> _deliveryTokensForCurrentTest() =>
    _currentDelivery.verificationTokens;

Future<String> _createApplication(String token, String organizationId) async {
  final response = await _request(
    method: 'POST',
    path: '/v1/organizations/$organizationId/applications',
    token: token,
    idempotencyKey: 'application-${organizationId.substring(0, 8)}',
    body: <String, Object?>{
      'runtime_application_id': 'com.example.billing',
      'name': 'Billing app',
      'platform': 'android',
    },
  );
  expect(response.statusCode, 201, reason: jsonEncode(response.body));
  return response.body['id']! as String;
}

Future<String> _createEnvironment(
  String token,
  String organizationId,
  String applicationId,
  String name,
) async {
  final response = await _request(
    method: 'POST',
    path:
        '/v1/organizations/$organizationId/applications/$applicationId/environments',
    token: token,
    idempotencyKey: 'environment-$name-${organizationId.substring(0, 8)}',
    body: <String, Object?>{'name': name},
  );
  expect(response.statusCode, 201, reason: jsonEncode(response.body));
  return response.body['id']! as String;
}

Future<Map<String, Object?>> _startCheckout(
  String token,
  String organizationId,
  String planKey,
  String idempotencyKey,
) async {
  final response = await _request(
    method: 'POST',
    path: '/v1/organizations/$organizationId/billing/checkout',
    token: token,
    idempotencyKey: idempotencyKey,
    body: <String, Object?>{'plan_key': planKey},
  );
  expect(response.statusCode, 201, reason: jsonEncode(response.body));
  return response.body;
}

Future<_JsonResponse> _applyEvent({
  required Map<String, Object?> checkout,
  required String subscriptionId,
  required String planId,
  required String eventId,
  required String eventName,
  required String status,
  required String createdAt,
  required int amount,
  String? currentEnd,
  bool? hasScheduledChanges,
  String? changeScheduledAt,
}) async {
  final body = _eventBody(
    checkout: checkout,
    subscriptionId: subscriptionId,
    planId: planId,
    eventId: eventId,
    eventName: eventName,
    status: status,
    createdAt: createdAt,
    amount: amount,
    currentEnd: currentEnd,
    hasScheduledChanges: hasScheduledChanges,
    changeScheduledAt: changeScheduledAt,
  );
  return _request(
    method: 'POST',
    path: '/v1/billing/webhooks/razorpay',
    rawBody: body,
    headers: <String, String>{
      'X-Razorpay-Signature': Hmac(
        sha256,
        utf8.encode(_webhookSecret),
      ).convert(body).toString(),
    },
  );
}

Future<_JsonResponse> _confirmScheduledChange({
  required String providerSubscriptionId,
  required String providerPlanId,
  String? currentEndAt,
  String? changeScheduledAt,
}) => _request(
  method: 'POST',
  path:
      '/v1/billing/provider/subscriptions/$providerSubscriptionId/scheduled-change',
  token: _bridgeToken,
  body: <String, Object?>{
    'provider_plan_id': providerPlanId,
    'provider_status': 'active',
    'has_scheduled_changes': true,
    'schedule_change_at': 'cycle_end',
    if (changeScheduledAt != null) 'change_scheduled_at': changeScheduledAt,
    if (currentEndAt != null) 'current_end_at': currentEndAt,
  },
);

Future<_JsonResponse> _cancelCheckout(
  String token,
  String organizationId,
  String checkoutId,
) => _request(
  method: 'POST',
  path:
      '/v1/organizations/$organizationId/billing/checkouts/$checkoutId/cancel',
  token: token,
  body: const <String, Object?>{},
);

List<int> _eventBody({
  required Map<String, Object?> checkout,
  required String subscriptionId,
  required String planId,
  required String eventId,
  required String eventName,
  required String status,
  required String createdAt,
  required int amount,
  String? currentEnd,
  bool? hasScheduledChanges,
  String? changeScheduledAt,
}) {
  final event = <String, Object?>{
    'id': eventId,
    'event': eventName,
    'created_at': DateTime.parse(createdAt).millisecondsSinceEpoch ~/ 1000,
    'payload': <String, Object?>{
      'subscription': <String, Object?>{
        'entity': <String, Object?>{
          'id': subscriptionId,
          'plan_id': planId,
          'status': status,
          'amount': amount,
          'currency': 'USD',
          'current_start':
              DateTime.parse(createdAt).millisecondsSinceEpoch ~/ 1000,
          'current_end': currentEnd == null
              ? null
              : DateTime.parse(currentEnd).millisecondsSinceEpoch ~/ 1000,
          if (hasScheduledChanges != null)
            'has_scheduled_changes': hasScheduledChanges,
          if (changeScheduledAt != null)
            'change_scheduled_at':
                DateTime.parse(changeScheduledAt).millisecondsSinceEpoch ~/
                1000,
          'notes': <String, Object?>{'hyfens_checkout_id': checkout['id']},
        },
      },
    },
  };
  return utf8.encode(jsonEncode(event));
}

Future<_JsonResponse> _request({
  required String method,
  required String path,
  Map<String, Object?>? body,
  List<int>? rawBody,
  String? token,
  String? idempotencyKey,
  Map<String, String>? headers,
}) async {
  final client = HttpClient();
  try {
    final port = _serverPort();
    if (port == null) throw StateError('Billing test server is not active');
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('Accept', 'application/json');
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    if (idempotencyKey != null) {
      request.headers.set('Idempotency-Key', idempotencyKey);
    }
    headers?.forEach((key, value) => request.headers.set(key, value));
    if (rawBody != null) {
      request.add(rawBody);
    } else if (body != null) {
      request.write(jsonEncode(body));
    }
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

int? _serverPort() => _activeServer?.port;
HttpServer? _activeServer;
