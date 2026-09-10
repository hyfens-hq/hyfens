import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

const _webhookSecret = 'enterprise-billing-test-secret';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late ControlPlaneService service;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-enterprise-');
    store = FileControlPlaneStore(directory);
    service = ControlPlaneService(
      store: store,
      random: Random(17),
      deploymentModel: DeploymentModel.cloud,
      razorpayBilling: RazorpayBillingConfig(
        starterPlanId: 'rzp_plan_starter_fixture',
        teamPlanId: 'rzp_plan_team_fixture',
        webhookSecret: _webhookSecret,
        currency: 'USD',
        starterAmountMinor: 4900,
        teamAmountMinor: 19900,
      ),
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'quote versions are immutable to customers and acceptance is idempotent',
    () async {
      final organization = await service.bootstrap(
        organizationName: 'Enterprise customer',
        runtimeApplicationId: 'com.example.enterprise',
        platformId: 'plt_android_arm64_release',
        environmentName: 'production',
      );
      final terms = _terms(
        recurringAmountMinor: 34900,
        internalNotes: 'Internal margin discussion',
      );
      final created = await service.billing.enterprise.createQuote(
        organizationId: organization.organization.id,
        terms: terms,
        idempotencyKey: 'enterprise-quote-1',
      );
      final issued = await service.billing.enterprise.issueQuote(
        quoteId: created['id']! as String,
      );
      final issuedVersion = issued['version']! as Map<String, Object?>;
      final customerView = await service.billing.enterprise.readCustomerQuote(
        organizationId: organization.organization.id,
        quoteId: created['id']! as String,
      );
      final customerTerms =
          (customerView['version']! as Map<String, Object?>)['terms']!
              as Map<String, Object?>;
      expect(customerTerms.containsKey('internalNotes'), isFalse);
      expect(customerTerms['customerNotes'], 'Customer-facing allowance terms');

      await expectLater(
        service.billing.enterprise.readCustomerQuote(
          organizationId: 'org_foreign_customer',
          quoteId: created['id']! as String,
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'NOT_FOUND',
          ),
        ),
      );

      final revised = await service.billing.enterprise.reviseQuote(
        quoteId: created['id']! as String,
        terms: _terms(recurringAmountMinor: 39900),
      );
      final revisedVersion = revised['version']! as Map<String, Object?>;
      final oldVersion = await store.readJson(
        enterpriseQuoteVersionCollection,
        issuedVersion['id']! as String,
      );
      expect(oldVersion?['status'], EnterpriseQuoteStatus.superseded.wireValue);
      expect(revisedVersion['status'], EnterpriseQuoteStatus.draft.wireValue);

      await service.billing.enterprise.issueQuote(
        quoteId: created['id']! as String,
      );
      final accepted = await Future.wait(<Future<Map<String, Object?>>>[
        service.billing.enterprise.acceptQuote(
          organizationId: organization.organization.id,
          quoteId: created['id']! as String,
          versionId: revisedVersion['id']! as String,
          actorId: 'customer-owner',
        ),
        service.billing.enterprise.acceptQuote(
          organizationId: organization.organization.id,
          quoteId: created['id']! as String,
          versionId: revisedVersion['id']! as String,
          actorId: 'customer-owner',
        ),
      ]);
      expect(
        accepted.map((result) => (result['contract']! as Map)['id']),
        hasLength(2),
      );
      expect(
        (accepted[0]['contract']! as Map<String, Object?>)['id'],
        (accepted[1]['contract']! as Map<String, Object?>)['id'],
      );
      expect(
        (accepted.first['contract']! as Map<String, Object?>)['status'],
        EnterpriseContractStatus.pendingPayment.wireValue,
      );

      final amendmentDraft = await service.billing.enterprise.reviseQuote(
        quoteId: created['id']! as String,
        terms: _terms(recurringAmountMinor: 44900),
      );
      expect(
        (await store.readJson(
          enterpriseQuoteVersionCollection,
          revisedVersion['id']! as String,
        ))?['status'],
        EnterpriseQuoteStatus.accepted.wireValue,
      );
      expect(
        (amendmentDraft['version']! as Map<String, Object?>)['status'],
        EnterpriseQuoteStatus.draft.wireValue,
      );

      final billing = await service.billing.read(
        organizationId: organization.organization.id,
      );
      expect(billing.effectivePlan?['key'], cloudPlanFreeKey);
    },
  );

  test(
    'provider activation is mapping-bound, idempotent, and custom-entitled',
    () async {
      final organization = await service.bootstrap(
        organizationName: 'Enterprise provider customer',
        runtimeApplicationId: 'com.example.enterprise.provider',
        platformId: 'plt_android_arm64_release',
        environmentName: 'production',
      );
      final other = await service.bootstrap(
        organizationName: 'Other enterprise customer',
        runtimeApplicationId: 'com.example.enterprise.other',
        platformId: 'plt_android_arm64_release',
        environmentName: 'production',
      );
      final quote = await _acceptedQuote(
        service.billing.enterprise,
        organization.organization.id,
        amountMinor: 34900,
      );
      final contract = quote['contract']! as Map<String, Object?>;
      final contractId = contract['id']! as String;

      await expectLater(
        service.billing.enterprise.linkProviderPlan(
          contractId: contractId,
          providerPlanId: 'plan_enterprise_usd_349',
          amountMinor: 35000,
          currency: 'USD',
          interval: 'monthly',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'BILLING_PROVIDER_MISMATCH',
          ),
        ),
      );
      await service.billing.enterprise.linkProviderPlan(
        contractId: contractId,
        providerPlanId: 'plan_enterprise_usd_349',
        amountMinor: 34900,
        currency: 'USD',
        interval: 'monthly',
      );
      await expectLater(
        service.billing.enterprise.linkProviderSubscription(
          contractId: contractId,
          providerSubscriptionId: 'sub_enterprise_wrong_plan',
          providerPlanId: 'plan_attacker',
          providerStatus: 'created',
          amountMinor: 34900,
          currency: 'USD',
          interval: 'monthly',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'BILLING_PROVIDER_MISMATCH',
          ),
        ),
      );
      await service.billing.enterprise.linkProviderSubscription(
        contractId: contractId,
        providerSubscriptionId: 'sub_enterprise_fixture',
        providerPlanId: 'plan_enterprise_usd_349',
        providerStatus: 'created',
        amountMinor: 34900,
        currency: 'USD',
        interval: 'monthly',
        totalCount: 12,
      );

      final otherQuote = await _acceptedQuote(
        service.billing.enterprise,
        other.organization.id,
        amountMinor: 34900,
      );
      final otherContract = otherQuote['contract']! as Map<String, Object?>;
      await service.billing.enterprise.linkProviderPlan(
        contractId: otherContract['id']! as String,
        providerPlanId: 'plan_enterprise_usd_349',
        amountMinor: 34900,
        currency: 'USD',
        interval: 'monthly',
      );
      await expectLater(
        service.billing.enterprise.linkProviderSubscription(
          contractId: otherContract['id']! as String,
          providerSubscriptionId: 'sub_enterprise_fixture',
          providerPlanId: 'plan_enterprise_usd_349',
          providerStatus: 'created',
          amountMinor: 34900,
          currency: 'USD',
          interval: 'monthly',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'BILLING_PROVIDER_MAPPING_CONFLICT',
          ),
        ),
      );

      final activeBody = _providerEvent(
        eventId: 'evt_enterprise_active',
        eventName: 'subscription.activated',
        subscriptionId: 'sub_enterprise_fixture',
        providerPlanId: 'plan_enterprise_usd_349',
        status: 'active',
        amountMinor: 34900,
      );
      final active = await _applyWebhook(service.billing, activeBody);
      expect(active.status, 'applied');
      expect(active.enterpriseContract?['status'], 'active');

      final snapshot = await service.billing.read(
        organizationId: organization.organization.id,
      );
      expect(snapshot.effectivePlan?['key'], cloudPlanEnterpriseKey);
      final limits = snapshot.entitlements?['limits']! as Map<String, Object?>;
      expect((limits[cloudApplicationsLimitKey] as Map)['value'], 5);
      expect(
        (limits[cloudEnvironmentsPerApplicationLimitKey] as Map)['value'],
        4,
      );
      expect(snapshot.enterpriseContract, isNotNull);
      expect(
        snapshot.enterpriseContract!.containsKey('providerPlanId'),
        isFalse,
      );

      final duplicate = await _applyWebhook(service.billing, activeBody);
      expect(duplicate.status, 'duplicate');
      expect(await store.listJson('billing_events'), hasLength(1));

      final wrongPlan = _providerEvent(
        eventId: 'evt_enterprise_wrong_plan',
        eventName: 'subscription.activated',
        subscriptionId: 'sub_enterprise_fixture',
        providerPlanId: 'plan_attacker',
        status: 'active',
        amountMinor: 34900,
      );
      await expectLater(
        _applyWebhook(service.billing, wrongPlan),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'BILLING_PROVIDER_MISMATCH',
          ),
        ),
      );
    },
  );

  test(
    'cancellation preserves scheduled state and falls back without deletion',
    () async {
      final organization = await service.bootstrap(
        organizationName: 'Enterprise cancellation customer',
        runtimeApplicationId: 'com.example.enterprise.cancel',
        platformId: 'plt_android_arm64_release',
        environmentName: 'production',
      );
      final quote = await _acceptedQuote(
        service.billing.enterprise,
        organization.organization.id,
        amountMinor: 49900,
      );
      final contract = quote['contract']! as Map<String, Object?>;
      await service.billing.enterprise.linkProviderPlan(
        contractId: contract['id']! as String,
        providerPlanId: 'plan_enterprise_usd_499',
        amountMinor: 49900,
        currency: 'USD',
        interval: 'monthly',
      );
      await service.billing.enterprise.linkProviderSubscription(
        contractId: contract['id']! as String,
        providerSubscriptionId: 'sub_enterprise_cancel',
        providerPlanId: 'plan_enterprise_usd_499',
        providerStatus: 'created',
        amountMinor: 49900,
        currency: 'USD',
        interval: 'monthly',
        currentEndAt: DateTime.now()
            .toUtc()
            .add(const Duration(days: 30))
            .toIso8601String(),
      );
      await _applyWebhook(
        service.billing,
        _providerEvent(
          eventId: 'evt_enterprise_cancel_active',
          eventName: 'subscription.activated',
          subscriptionId: 'sub_enterprise_cancel',
          providerPlanId: 'plan_enterprise_usd_499',
          status: 'active',
          amountMinor: 49900,
        ),
      );
      final scheduled = await service.billing.enterprise.requestCancellation(
        organizationId: organization.organization.id,
      );
      expect(scheduled['status'], 'cancellation_scheduled');

      await _applyWebhook(
        service.billing,
        _providerEvent(
          eventId: 'evt_enterprise_cancel_schedule_echo',
          eventName: 'subscription.activated',
          subscriptionId: 'sub_enterprise_cancel',
          providerPlanId: 'plan_enterprise_usd_499',
          status: 'active',
          amountMinor: 49900,
          cancelAtCycleEnd: true,
        ),
      );
      final stillScheduled = await service.billing.enterprise.activeContract(
        organizationId: organization.organization.id,
      );
      expect(stillScheduled?['status'], 'cancellation_scheduled');

      await _applyWebhook(
        service.billing,
        _providerEvent(
          eventId: 'evt_enterprise_cancelled',
          eventName: 'subscription.cancelled',
          subscriptionId: 'sub_enterprise_cancel',
          providerPlanId: 'plan_enterprise_usd_499',
          status: 'cancelled',
          amountMinor: 49900,
        ),
      );
      final billing = await service.billing.read(
        organizationId: organization.organization.id,
      );
      expect(billing.effectivePlan?['key'], cloudPlanFreeKey);
      expect(await store.listJson('organizations'), hasLength(1));
      expect(await store.listJson('enterprise_contracts'), hasLength(1));
      final cancellationDigest = sha256
          .convert(
            utf8.encode('${organization.organization.id}:${contract['id']}'),
          )
          .toString();
      expect(
        (await store.readJson(
          'billing_cancellations',
          'bcancel_${cancellationDigest.substring(0, 32)}',
        ))?['status'],
        'effective',
      );
    },
  );

  test(
    'self-hosted deployments never enter Enterprise Cloud billing',
    () async {
      final selfHosted = EnterpriseBillingService(
        store,
        deploymentModel: DeploymentModel.selfHosted,
      );
      await expectLater(
        selfHosted.createQuote(
          organizationId: 'org_self_hosted',
          terms: _terms(recurringAmountMinor: 34900),
          idempotencyKey: 'self-hosted-quote',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'INVALID_DEPLOYMENT_MODEL',
          ),
        ),
      );
    },
  );

  test('Enterprise quotes reject currencies outside approved USD', () {
    expect(
      () => EnterpriseQuoteTerms(
        currency: 'EUR',
        recurringAmountMinor: 34900,
        interval: 'monthly',
        validUntil: DateTime.now().toUtc().add(const Duration(days: 30)),
        entitlements: EnterpriseEntitlementSnapshot(<String, CloudLimit>{
          cloudApplicationsLimitKey: const CloudLimit.finite(5),
        }),
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'INVALID_BILLING_CURRENCY',
        ),
      ),
    );
  });
}

Future<Map<String, Object?>> _acceptedQuote(
  EnterpriseBillingService enterprise,
  String organizationId, {
  required int amountMinor,
}) async {
  final created = await enterprise.createQuote(
    organizationId: organizationId,
    terms: _terms(recurringAmountMinor: amountMinor),
    idempotencyKey: 'quote-$organizationId-$amountMinor',
  );
  final issued = await enterprise.issueQuote(quoteId: created['id']! as String);
  final version = issued['version']! as Map<String, Object?>;
  return enterprise.acceptQuote(
    organizationId: organizationId,
    quoteId: created['id']! as String,
    versionId: version['id']! as String,
    actorId: 'customer-owner',
  );
}

Future<BillingProviderEventResult> _applyWebhook(
  BillingService billing,
  List<int> body,
) => billing.applyRazorpayWebhook(
  rawBody: body,
  signature: Hmac(sha256, utf8.encode(_webhookSecret)).convert(body).toString(),
);

EnterpriseQuoteTerms _terms({
  required int recurringAmountMinor,
  String? internalNotes,
}) => EnterpriseQuoteTerms(
  currency: 'USD',
  recurringAmountMinor: recurringAmountMinor,
  interval: 'monthly',
  validUntil: DateTime.now().toUtc().add(const Duration(days: 30)),
  entitlements: EnterpriseEntitlementSnapshot(<String, CloudLimit>{
    cloudApplicationsLimitKey: const CloudLimit.finite(5),
    cloudEnvironmentsPerApplicationLimitKey: const CloudLimit.finite(4),
    cloudMembersLimitKey: const CloudLimit.finite(25),
  }),
  contactName: 'Enterprise Buyer',
  contactEmail: 'buyer@example.com',
  termMonths: 12,
  totalCount: 12,
  supportLevel: 'Priority',
  customerNotes: 'Customer-facing allowance terms',
  internalNotes: internalNotes,
);

List<int> _providerEvent({
  required String eventId,
  required String eventName,
  required String subscriptionId,
  required String providerPlanId,
  required String status,
  required int amountMinor,
  bool cancelAtCycleEnd = false,
}) {
  final now = DateTime.now().toUtc();
  final epoch = now.millisecondsSinceEpoch ~/ 1000;
  final body = <String, Object?>{
    'id': eventId,
    'event': eventName,
    'created_at': epoch,
    'payload': <String, Object?>{
      'subscription': <String, Object?>{
        'entity': <String, Object?>{
          'id': subscriptionId,
          'plan_id': providerPlanId,
          'status': status,
          'amount': amountMinor,
          'currency': 'USD',
          'interval': 'monthly',
          'cancel_at_cycle_end': cancelAtCycleEnd,
          'current_start': epoch,
          'current_end': epoch + 30 * 24 * 60 * 60,
        },
      },
    },
  };
  return utf8.encode(jsonEncode(body));
}
