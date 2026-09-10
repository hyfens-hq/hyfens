import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'cloud_plans.dart';
import 'encoding.dart';
import 'enterprise_billing.dart';
import 'errors.dart';
import 'persistence.dart';
import 'usage_metering.dart';

const Set<String> _subscriptionStatuses = <String>{
  'created',
  'authenticated',
  'active',
  'pending',
  'halted',
  'cancel_requested',
  'cancelled',
  'paused',
  'completed',
  'expired',
  'superseded',
};

const Set<String> _scheduledPlanChangeStatuses = <String>{
  'pending_provider',
  'scheduled',
  'failed',
};

const Set<String> _activeScheduledPlanChangeStatuses = <String>{
  'pending_provider',
  'scheduled',
};

const Set<String> _refundRequestStatuses = <String>{
  'requested',
  'under_review',
  'approved',
  'provider_pending',
  'refunded',
  'rejected',
  'failed',
};

const Set<String> _providerRefundStatuses = <String>{
  'pending',
  'processed',
  'failed',
};

const Set<String> _refundReasonCategories = <String>{
  'duplicate_charge',
  'activation_failed',
  'incorrect_amount',
  'incorrect_plan',
  'service_unavailable',
  'other',
};

/// Provider identifiers and verification material are deployment configuration,
/// not customer-supplied billing data. A missing configuration keeps checkout
/// unavailable rather than allowing a browser to choose a plan or price.
final class RazorpayBillingConfig {
  RazorpayBillingConfig({
    required this.starterPlanId,
    required this.teamPlanId,
    required this.webhookSecret,
    required this.currency,
    required this.starterAmountMinor,
    required this.teamAmountMinor,
  }) {
    if (starterPlanId.trim().isEmpty ||
        teamPlanId.trim().isEmpty ||
        webhookSecret.trim().isEmpty ||
        starterPlanId.contains(RegExp(r'[\u0000\r\n]')) ||
        teamPlanId.contains(RegExp(r'[\u0000\r\n]')) ||
        webhookSecret.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ArgumentError(
        'Razorpay billing configuration contains invalid text',
      );
    }
    if (currency != 'USD' ||
        starterAmountMinor != 4900 ||
        teamAmountMinor != 19900) {
      throw ArgumentError(
        'Razorpay billing configuration must use the approved USD Starter 4900 and Team 19900 amounts',
      );
    }
  }

  final String starterPlanId;
  final String teamPlanId;
  final String webhookSecret;
  final String currency;
  final int starterAmountMinor;
  final int teamAmountMinor;

  String providerPlanId(String planKey) => switch (planKey) {
    cloudPlanStarterKey => starterPlanId,
    cloudPlanTeamKey => teamPlanId,
    _ => throw ControlPlaneException(
      'INVALID_BILLING_PLAN',
      'The Cloud plan is not available for Razorpay checkout',
      statusCode: 422,
    ),
  };

  int amountMinor(String planKey) => switch (planKey) {
    cloudPlanStarterKey => starterAmountMinor,
    cloudPlanTeamKey => teamAmountMinor,
    _ => throw ControlPlaneException(
      'INVALID_BILLING_PLAN',
      'The Cloud plan is not available for Razorpay checkout',
      statusCode: 422,
    ),
  };

  static RazorpayBillingConfig? fromEnvironment(Map<String, String> values) {
    final starter = _optionalEnvironmentText(
      values['HYFENS_RAZORPAY_STARTER_PLAN_ID'],
      'starter plan ID',
    );
    final team = _optionalEnvironmentText(
      values['HYFENS_RAZORPAY_TEAM_PLAN_ID'],
      'Team plan ID',
    );
    final secret = _optionalEnvironmentText(
      values['HYFENS_RAZORPAY_WEBHOOK_SECRET'],
      'webhook secret',
    );
    final currency = _optionalEnvironmentText(
      values['HYFENS_RAZORPAY_CURRENCY'],
      'currency',
    );
    final starterAmountText = _optionalEnvironmentText(
      values['HYFENS_RAZORPAY_STARTER_AMOUNT_MINOR'],
      'Starter amount',
    );
    final teamAmountText = _optionalEnvironmentText(
      values['HYFENS_RAZORPAY_TEAM_AMOUNT_MINOR'],
      'Team amount',
    );
    final anyConfigured = <String?>[
      starter,
      team,
      secret,
      currency,
      starterAmountText,
      teamAmountText,
    ].any((value) => value != null);
    if (!anyConfigured) return null;
    if (starter == null || team == null || secret == null || currency == null) {
      throw ArgumentError(
        'Razorpay checkout requires starter/team plan IDs, currency, and a webhook secret',
      );
    }
    final starterAmount = int.tryParse(starterAmountText ?? '');
    final teamAmount = int.tryParse(teamAmountText ?? '');
    if (starterAmount == null ||
        starterAmount <= 0 ||
        teamAmount == null ||
        teamAmount <= 0) {
      throw ArgumentError(
        'Razorpay checkout requires positive Starter and Team amounts in minor units',
      );
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw ArgumentError(
        'Razorpay checkout requires an explicit three-letter uppercase currency',
      );
    }
    if (currency != 'USD' || starterAmount != 4900 || teamAmount != 19900) {
      throw ArgumentError(
        'Razorpay checkout must use the approved USD Starter 4900 and Team 19900 amounts',
      );
    }
    return RazorpayBillingConfig(
      starterPlanId: _requiredEnvironmentText(starter, 'starter plan ID'),
      teamPlanId: _requiredEnvironmentText(team, 'Team plan ID'),
      webhookSecret: _requiredEnvironmentText(secret, 'webhook secret'),
      currency: currency,
      starterAmountMinor: starterAmount,
      teamAmountMinor: teamAmount,
    );
  }

  static String? _optionalEnvironmentText(String? value, String label) {
    if (value == null) return null;
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    if (normalized.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ArgumentError('Razorpay $label is invalid');
    }
    return normalized;
  }

  static String _requiredEnvironmentText(String value, String label) {
    if (value.isEmpty || value.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ArgumentError('Razorpay $label is invalid');
    }
    return value;
  }
}

final class BillingProviderEventResult {
  const BillingProviderEventResult({
    required this.status,
    required this.eventId,
    required this.organizationId,
    this.eventName,
    this.subscription,
    this.checkout,
    this.enterpriseContract,
    this.payment,
    this.refund,
    this.scheduledPlanChange,
  });

  final String status;
  final String eventId;
  final String organizationId;
  final String? eventName;
  final Map<String, Object?>? subscription;
  final Map<String, Object?>? checkout;
  final Map<String, Object?>? enterpriseContract;
  final Map<String, Object?>? payment;
  final Map<String, Object?>? refund;
  final Map<String, Object?>? scheduledPlanChange;

  BillingProviderEventResult copyWith({String? eventName}) =>
      BillingProviderEventResult(
        status: status,
        eventId: eventId,
        organizationId: organizationId,
        eventName: eventName ?? this.eventName,
        subscription: subscription,
        checkout: checkout,
        enterpriseContract: enterpriseContract,
        payment: payment,
        refund: refund,
        scheduledPlanChange: scheduledPlanChange,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status,
    'event_id': eventId,
    'organization_id': organizationId,
    if (eventName != null) 'event_name': eventName,
    if (subscription != null) 'subscription': subscription,
    if (checkout != null) 'checkout': checkout,
    if (enterpriseContract != null) 'enterprise_contract': enterpriseContract,
    if (payment != null) 'payment': payment,
    if (refund != null) 'refund': refund,
    if (scheduledPlanChange != null)
      'scheduled_plan_change': scheduledPlanChange,
  };
}

final class BillingSnapshot {
  const BillingSnapshot({
    required this.plans,
    required this.subscriptions,
    this.cloudPlans = const <Map<String, Object?>>[],
    this.deploymentModel = 'self_hosted',
    this.effectivePlan,
    this.entitlements,
    this.usage,
    this.checkoutIntents = const <Map<String, Object?>>[],
    this.cancellation,
    this.scheduledPlanChange,
    this.actions = const <String>[],
    this.enterpriseQuotes = const <Map<String, Object?>>[],
    this.enterpriseContract,
    this.payments = const <Map<String, Object?>>[],
    this.refundRequests = const <Map<String, Object?>>[],
  });

  final List<Map<String, Object?>> plans;
  final List<Map<String, Object?>> subscriptions;
  final List<Map<String, Object?>> cloudPlans;
  final String deploymentModel;
  final Map<String, Object?>? effectivePlan;
  final Map<String, Object?>? entitlements;
  final Map<String, Object?>? usage;
  final List<Map<String, Object?>> checkoutIntents;
  final Map<String, Object?>? cancellation;
  final Map<String, Object?>? scheduledPlanChange;
  final List<String> actions;
  final List<Map<String, Object?>> enterpriseQuotes;
  final Map<String, Object?>? enterpriseContract;
  final List<Map<String, Object?>> payments;
  final List<Map<String, Object?>> refundRequests;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': 4,
    'plans': plans,
    'subscriptions': subscriptions,
    'cloud_plans': cloudPlans,
    'deployment_model': deploymentModel,
    if (effectivePlan != null) 'effective_plan': effectivePlan,
    if (entitlements != null) 'entitlements': entitlements,
    if (usage != null) 'usage': usage,
    'checkout_intents': checkoutIntents,
    if (cancellation != null) 'cancellation': cancellation,
    if (scheduledPlanChange != null)
      'scheduled_plan_change': scheduledPlanChange,
    'actions': actions,
    'enterprise_quotes': enterpriseQuotes,
    if (enterpriseContract != null) 'enterprise_contract': enterpriseContract,
    'payments': payments,
    'refund_requests': refundRequests,
  };
}

/// Durable billing metadata stored through the existing control-plane record
/// seam. No payment method, secret, signature, or raw webhook body is stored.
final class BillingService {
  factory BillingService(
    ControlPlaneStore store, {
    DateTime Function()? clock,
    DeploymentModel deploymentModel = DeploymentModel.selfHosted,
    CloudUsageMeteringService? usageMetering,
    RazorpayBillingConfig? razorpay,
  }) {
    final actualClock = clock ?? (() => DateTime.now().toUtc());
    return BillingService._(
      store,
      clock: actualClock,
      deploymentModel: deploymentModel,
      usageMetering: usageMetering,
      razorpay: razorpay,
    );
  }

  BillingService._(
    this.store, {
    required DateTime Function() clock,
    required DeploymentModel deploymentModel,
    CloudUsageMeteringService? usageMetering,
    required this.razorpay,
  }) : _clock = clock,
       this.deploymentModel = deploymentModel,
       usageMetering =
           usageMetering ??
           CloudUsageMeteringService(
             store,
             deploymentModel: deploymentModel,
             clock: clock,
           ),
       enterprise = EnterpriseBillingService(
         store,
         clock: clock,
         deploymentModel: deploymentModel,
       );

  final ControlPlaneStore store;
  final DateTime Function() _clock;
  final DeploymentModel deploymentModel;
  final CloudUsageMeteringService usageMetering;
  final RazorpayBillingConfig? razorpay;
  final EnterpriseBillingService enterprise;
  Future<void> _assignmentWriteTail = Future<void>.value();
  Future<void> _providerBridgeWriteTail = Future<void>.value();
  Future<void> _providerEventWriteTail = Future<void>.value();
  Future<void> _refundWriteTail = Future<void>.value();
  Future<void> _scheduledPlanChangeWriteTail = Future<void>.value();

  /// Seeds only the backend Cloud identity/entitlement catalog. Prices and
  /// marketing copy intentionally remain outside this OSS billing metadata.
  Future<void> initialize() async {
    await ensurePlanCatalog();
    await _cloudPlanCatalogProjection();
    if (deploymentModel == DeploymentModel.cloud) {
      await backfillCloudPlanAssignments();
    }
  }

  Future<void> ensurePlanCatalog() async {
    for (final definition in defaultCloudPlanCatalog) {
      final value = <String, Object?>{
        'id': _cloudPlanId(definition.key),
        'key': definition.key,
        'name': definition.name,
        'deploymentModel': DeploymentModel.cloud.wireValue,
        'rank': definition.rank,
        'paymentRequired': definition.paymentRequired,
        'providerBacked': definition.providerBacked,
        'capabilities': definition.capabilities.toList()..sort(),
        'limits': <String, Object?>{
          for (final entry in definition.limits.entries)
            entry.key: entry.value.toJson(),
        },
      };
      final id = value['id']! as String;
      final existing = await store.readJson('billing_plan_catalog', id);
      if (existing != null) {
        // Task 248 seeded the stable rows before typed limits existed. Keep
        // the plan policy current without replacing catalog state or touching
        // organization subscriptions.
        if (canonicalJson(existing['limits']) !=
            canonicalJson(value['limits'])) {
          await store.replaceJson('billing_plan_catalog', id, <String, Object?>{
            ...existing,
            'limits': value['limits'],
          });
        }
        continue;
      }
      try {
        await store.createJson('billing_plan_catalog', id, value);
      } on StorageConflict {
        // Another process may have seeded the same stable row. The resolver
        // validates the persisted definition before using it.
        if (await store.readJson('billing_plan_catalog', id) == null) rethrow;
      }
    }
  }

  /// Backfills organizations already present in a managed Cloud store. The
  /// deterministic assignment is safe to retry and never replaces a valid
  /// provider-backed paid state.
  Future<void> backfillCloudPlanAssignments() async {
    if (deploymentModel != DeploymentModel.cloud) return;
    await ensurePlanCatalog();
    final organizations = await store.listJson('organizations');
    for (final organization in organizations) {
      final organizationId = organization['id'];
      if (organizationId is! String) {
        throw const ControlPlaneException(
          'STORAGE_CORRUPT',
          'An organization record has no valid ID',
          statusCode: 500,
        );
      }
      await ensureCloudPlanAssignment(organizationId: organizationId);
    }
  }

  Future<BillingSnapshot> read({required String organizationId}) async {
    _organization(organizationId);
    await ensurePlanCatalog();
    final effective = await resolveEffectiveEntitlements(
      organizationId: organizationId,
      includeMeasuredUsage: true,
    );
    return BillingSnapshot(
      plans: await _scoped('billing_plans', organizationId),
      subscriptions: await _scoped('billing_subscriptions', organizationId),
      cloudPlans: await _cloudPlanCatalogProjection(),
      deploymentModel: deploymentModel.wireValue,
      effectivePlan: effective.toPlanJson(),
      entitlements: effective.toEntitlementsJson(),
      usage: effective.usage?.toJson(),
      checkoutIntents: await _scoped(
        'billing_checkout_intents',
        organizationId,
      ),
      cancellation: await _currentCancellation(organizationId),
      scheduledPlanChange: await _currentScheduledPlanChange(organizationId),
      actions: _billingActions(effective.planKey),
      enterpriseQuotes: deploymentModel == DeploymentModel.cloud
          ? await enterprise.listCustomerQuotes(organizationId: organizationId)
          : const <Map<String, Object?>>[],
      enterpriseContract: deploymentModel == DeploymentModel.cloud
          ? await _customerEnterpriseContract(organizationId)
          : null,
      payments: deploymentModel == DeploymentModel.cloud
          ? await _customerPayments(organizationId)
          : const <Map<String, Object?>>[],
      refundRequests: deploymentModel == DeploymentModel.cloud
          ? await _customerRefundRequests(organizationId)
          : const <Map<String, Object?>>[],
    );
  }

  Future<Map<String, Object?>?> _customerEnterpriseContract(
    String organizationId,
  ) async {
    final contract = await enterprise.currentContract(
      organizationId: organizationId,
    );
    if (contract == null) return null;
    return enterprise.customerContract(contract);
  }

  /// Creates a server-owned checkout intent. This is deliberately not a paid
  /// state transition: only a verified Razorpay event can activate the
  /// provider subscription.
  Future<Map<String, Object?>> startCheckout({
    required String organizationId,
    required String planKey,
    required String idempotencyKey,
  }) async {
    _requireCloudDeployment();
    _organization(organizationId);
    await _ensureOrganizationCanStartPaidCheckout(organizationId);
    final target = _paidCloudPlanKey(planKey);
    final normalizedIdempotency = _text(
      idempotencyKey,
      'billing checkout idempotency key',
      256,
    );
    final effective = await resolveEffectiveEntitlements(
      organizationId: organizationId,
    );
    final currentRank = effective.planKey == null
        ? -1
        : cloudPlanRank(effective.planKey!);
    final targetRank = cloudPlanRank(target);
    if (currentRank >= targetRank) {
      if (currentRank == targetRank) {
        return <String, Object?>{
          'id': null,
          'status': 'already_active',
          'planKey': target,
          'effectivePlan': effective.toPlanJson(),
        };
      }
      throw const ControlPlaneException(
        'INVALID_PLAN_TRANSITION',
        'Cloud checkout can only move to a higher plan',
        statusCode: 409,
      );
    }
    final config = _requireRazorpayConfiguration();
    final plan = await _ensureConfiguredProviderPlan(
      organizationId: organizationId,
      planKey: target,
      config: config,
    );
    final pending = (await _scoped('billing_checkout_intents', organizationId))
        .where(
          (row) =>
              row['planKey'] == target &&
              row['status'] == 'awaiting_provider_confirmation',
        )
        .toList();
    if (pending.isNotEmpty) {
      pending.sort((left, right) {
        final leftUpdated = left['updatedAt'];
        final rightUpdated = right['updatedAt'];
        if (leftUpdated is! String || rightUpdated is! String) return 0;
        return rightUpdated.compareTo(leftUpdated);
      });
      return pending.first;
    }
    final id =
        'bchk_${sha256Hex(utf8.encode('$organizationId:$normalizedIdempotency')).substring(0, 32)}';
    final existing = await store.readJson('billing_checkout_intents', id);
    if (existing != null) {
      if (existing['organizationId'] != organizationId ||
          existing['planKey'] != target ||
          existing['idempotencyKey'] != normalizedIdempotency) {
        throw const ControlPlaneException(
          'BILLING_CHECKOUT_CONFLICT',
          'The checkout idempotency key was already used for another plan',
          statusCode: 409,
        );
      }
      return existing;
    }
    final now = _clock().toUtc().toIso8601String();
    final intent = <String, Object?>{
      'id': id,
      'organizationId': organizationId,
      'planKey': target,
      'planId': plan['id'],
      'provider': 'razorpay',
      'providerPlanId': plan['providerPlanId'],
      'status': 'awaiting_provider_confirmation',
      'amountMinor': plan['amountMinor'],
      'currency': plan['currency'],
      'idempotencyKey': normalizedIdempotency,
      'providerSubscriptionId': null,
      'createdAt': now,
      'updatedAt': now,
    };
    try {
      await store.createJson('billing_checkout_intents', id, intent);
      return intent;
    } on StorageConflict {
      final concurrent = await store.readJson('billing_checkout_intents', id);
      if (concurrent == null) rethrow;
      if (concurrent['organizationId'] != organizationId ||
          concurrent['planKey'] != target ||
          concurrent['idempotencyKey'] != normalizedIdempotency) {
        throw const ControlPlaneException(
          'BILLING_CHECKOUT_CONFLICT',
          'The checkout idempotency key was already used for another plan',
          statusCode: 409,
        );
      }
      return concurrent;
    }
  }

  /// Links a server-created Razorpay subscription to an existing checkout.
  /// The checkout is the only tenant selector accepted here; the provider
  /// bridge cannot choose an organization or plan in its request body.
  Future<Map<String, Object?>> linkProviderSubscription({
    required String checkoutId,
    required String providerSubscriptionId,
    required String providerPlanId,
    String? providerStatus,
    String? userId,
    int? totalCount,
    int? paidCount,
    int? remainingCount,
    String? currentStartAt,
    String? currentEndAt,
    bool? cancelAtCycleEnd,
  }) => _serializedProviderBridge(() async {
    _requireCloudDeployment();
    final normalizedCheckoutId = requireOpaqueId(
      checkoutId,
      'billing checkout ID',
    );
    final normalizedSubscriptionId = _text(
      providerSubscriptionId,
      'provider subscription ID',
      128,
    );
    final normalizedProviderPlanId = _text(
      providerPlanId,
      'provider plan ID',
      128,
    );
    final checkout = await store.readJson(
      'billing_checkout_intents',
      normalizedCheckoutId,
    );
    if (checkout == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Billing checkout was not found',
        statusCode: 404,
      );
    }
    final organizationId = checkout['organizationId'];
    final planId = checkout['planId'];
    if (organizationId is! String || planId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Billing checkout is missing its organization or plan',
        statusCode: 500,
      );
    }
    _organization(organizationId);
    if (checkout['provider'] != 'razorpay' ||
        checkout['providerPlanId'] != normalizedProviderPlanId ||
        checkout['planId'] != planId) {
      throw const ControlPlaneException(
        'BILLING_CHECKOUT_CONFLICT',
        'The provider subscription does not match the checkout intent',
        statusCode: 409,
      );
    }
    final plan = await store.readJson('billing_plans', planId);
    if (plan == null ||
        plan['organizationId'] != organizationId ||
        plan['provider'] != 'razorpay' ||
        plan['providerPlanId'] != normalizedProviderPlanId) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Billing checkout references an invalid provider plan',
        statusCode: 500,
      );
    }
    final linkedProviderSubscriptionId = checkout['providerSubscriptionId'];
    if (linkedProviderSubscriptionId is String &&
        linkedProviderSubscriptionId != normalizedSubscriptionId) {
      throw const ControlPlaneException(
        'BILLING_CHECKOUT_CONFLICT',
        'The checkout is already linked to another provider subscription',
        statusCode: 409,
      );
    }
    if (checkout['status'] == 'cancelled' || checkout['status'] == 'failed') {
      throw const ControlPlaneException(
        'BILLING_CHECKOUT_CONFLICT',
        'A terminal checkout cannot be linked to a provider subscription',
        statusCode: 409,
      );
    }

    final existingMapping = await _findProviderMapping(
      providerSubscriptionId: normalizedSubscriptionId,
    );
    if (existingMapping != null) {
      if (existingMapping['organizationId'] != organizationId) {
        throw const ControlPlaneException(
          'BILLING_PROVIDER_MAPPING_CONFLICT',
          'The provider subscription is already linked to another organization',
          statusCode: 409,
        );
      }
      final mappedCheckout = existingMapping['checkout'];
      if (mappedCheckout is Map<String, Object?> &&
          mappedCheckout['id'] != normalizedCheckoutId) {
        throw const ControlPlaneException(
          'BILLING_PROVIDER_MAPPING_CONFLICT',
          'The provider subscription is already linked to another checkout',
          statusCode: 409,
        );
      }
      final mappedSubscription = existingMapping['subscription'];
      if (mappedSubscription is Map<String, Object?>) {
        if (mappedSubscription['providerPlanId'] != normalizedProviderPlanId) {
          throw const ControlPlaneException(
            'BILLING_PROVIDER_MISMATCH',
            'The provider subscription plan does not match the checkout',
            statusCode: 409,
          );
        }
        return mappedSubscription;
      }
    }

    final status = providerStatus ?? 'created';
    if (!_subscriptionStatuses.contains(status) ||
        !const <String>{
          'created',
          'authenticated',
          'pending',
        }.contains(status)) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_LINK_REQUIRES_EVENT',
        'Paid activation requires a verified Razorpay provider event',
        statusCode: 409,
      );
    }
    await _claimProviderMapping(
      organizationId: organizationId,
      checkoutId: normalizedCheckoutId,
      providerSubscriptionId: normalizedSubscriptionId,
      providerPlanId: normalizedProviderPlanId,
      planId: planId,
    );
    return upsertSubscription(
      organizationId: organizationId,
      provider: 'razorpay',
      providerSubscriptionId: normalizedSubscriptionId,
      providerPlanId: normalizedProviderPlanId,
      status: status,
      planId: planId,
      userId: userId,
      checkoutId: normalizedCheckoutId,
      totalCount: totalCount,
      paidCount: paidCount,
      remainingCount: remainingCount,
      currentStartAt: currentStartAt,
      currentEndAt: currentEndAt,
      cancelAtCycleEnd: cancelAtCycleEnd,
    );
  });

  /// Refreshes provider metadata for a subscription already linked by
  /// [linkProviderSubscription]. It deliberately preserves the effective
  /// Hyfens status; only a signature-verified webhook may change entitlement.
  Future<Map<String, Object?>> syncProviderSubscription({
    required String providerSubscriptionId,
    required String providerPlanId,
    String? providerStatus,
    String? userId,
    int? totalCount,
    int? paidCount,
    int? remainingCount,
    String? currentStartAt,
    String? currentEndAt,
    bool? cancelAtCycleEnd,
  }) => _serializedProviderBridge(() async {
    _requireCloudDeployment();
    final normalizedSubscriptionId = _text(
      providerSubscriptionId,
      'provider subscription ID',
      128,
    );
    final normalizedProviderPlanId = _text(
      providerPlanId,
      'provider plan ID',
      128,
    );
    if (providerStatus != null &&
        !_subscriptionStatuses.contains(providerStatus)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_STATUS',
        'Subscription status is unsupported',
        statusCode: 422,
      );
    }
    final mapping = await _findProviderMapping(
      providerSubscriptionId: normalizedSubscriptionId,
    );
    final existing = mapping?['subscription'];
    if (mapping == null || existing is! Map<String, Object?>) {
      throw const ControlPlaneException(
        'BILLING_SUBSCRIPTION_UNMAPPED',
        'Razorpay subscription is not linked to a Hyfens checkout',
        statusCode: 404,
      );
    }
    final organizationId = mapping['organizationId'];
    final planId = existing['planId'];
    if (organizationId is! String || planId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Mapped provider subscription is missing its organization or plan',
        statusCode: 500,
      );
    }
    if (existing['providerPlanId'] != normalizedProviderPlanId) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'The provider subscription plan does not match its Hyfens mapping',
        statusCode: 409,
      );
    }
    return upsertSubscription(
      organizationId: organizationId,
      provider: 'razorpay',
      providerSubscriptionId: normalizedSubscriptionId,
      providerPlanId: normalizedProviderPlanId,
      status: existing['status']! as String,
      planId: planId,
      userId: userId ?? existing['userId'] as String?,
      checkoutId: mapping['checkout'] is Map<String, Object?>
          ? (mapping['checkout']! as Map<String, Object?>)['id'] as String?
          : null,
      totalCount: totalCount,
      paidCount: paidCount,
      remainingCount: remainingCount,
      currentStartAt: currentStartAt,
      currentEndAt: currentEndAt,
      cancelAtCycleEnd: cancelAtCycleEnd,
    );
  });

  Future<Map<String, Object?>> cancelCheckout({
    required String organizationId,
    required String checkoutId,
  }) async {
    _requireCloudDeployment();
    _organization(organizationId);
    final normalizedId = requireOpaqueId(checkoutId, 'checkout ID');
    final current = await store.readJson(
      'billing_checkout_intents',
      normalizedId,
    );
    if (current == null || current['organizationId'] != organizationId) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Billing checkout was not found',
        statusCode: 404,
      );
    }
    if (current['status'] == 'completed') {
      throw const ControlPlaneException(
        'BILLING_CHECKOUT_COMPLETED',
        'A completed checkout cannot be cancelled',
        statusCode: 409,
      );
    }
    if (current['status'] == 'cancelled' || current['status'] == 'failed') {
      return current;
    }
    final updated = <String, Object?>{
      ...current,
      'status': 'cancelled',
      'updatedAt': _clock().toUtc().toIso8601String(),
    };
    await store.replaceJson('billing_checkout_intents', normalizedId, updated);
    return updated;
  }

  /// Records a customer cancellation request without removing paid access.
  /// Razorpay remains authoritative for the final end-of-cycle event.
  Future<Map<String, Object?>> requestCancellation({
    required String organizationId,
    String? actorId,
  }) => _serializedScheduledPlanChange(
    () =>
        _requestCancellation(organizationId: organizationId, actorId: actorId),
  );

  /// Stops future Cloud renewal for a verified organization-deletion request.
  /// This is a billing-domain seam: privacy/deletion code does not manipulate
  /// Razorpay or billing records directly. Pending checkout intents are
  /// cancelled as part of the same serialized transition so a delayed browser
  /// retry cannot create a paid state after deletion has begun.
  Future<Map<String, Object?>> stopFutureRenewalForDeletion({
    required String organizationId,
    String? actorId,
  }) => _serializedScheduledPlanChange(() async {
    _requireCloudDeployment();
    final pending = (await _scoped(
      'billing_checkout_intents',
      organizationId,
    )).where((row) => row['status'] == 'awaiting_provider_confirmation');
    final now = _clock().toUtc().toIso8601String();
    for (final checkout in pending) {
      final id = checkout['id'];
      if (id is! String) continue;
      await store.replaceJson('billing_checkout_intents', id, <String, Object?>{
        ...checkout,
        'status': 'cancelled',
        'cancelReason': 'organization_deletion',
        'updatedAt': now,
      });
    }
    final enterpriseContract = await enterprise.activeContract(
      organizationId: organizationId,
    );
    if (enterpriseContract != null) {
      final cancellation = await enterprise.requestCancellation(
        organizationId: organizationId,
      );
      final effective = await resolveEffectiveEntitlements(
        organizationId: organizationId,
      );
      return <String, Object?>{
        'status': cancellation['status'] ?? 'scheduled',
        'effectivePlan': effective.toPlanJson(),
      };
    }
    return _requestCancellation(
      organizationId: organizationId,
      actorId: actorId,
    );
  });

  Future<Map<String, Object?>> _requestCancellation({
    required String organizationId,
    String? actorId,
  }) async {
    _requireCloudDeployment();
    _organization(organizationId);
    final active = await _activeProviderSubscription(
      await _scoped('billing_subscriptions', organizationId),
      organizationId,
    );
    if (active == null) {
      final effective = await resolveEffectiveEntitlements(
        organizationId: organizationId,
      );
      return <String, Object?>{
        'status': 'not_active',
        'effectivePlan': effective.toPlanJson(),
      };
    }
    final subscriptionId = active['id']! as String;
    final cancellationId =
        'bcancel_${sha256Hex(utf8.encode('$organizationId:$subscriptionId')).substring(0, 32)}';
    final now = _clock().toUtc().toIso8601String();
    final existing = await store.readJson(
      'billing_cancellations',
      cancellationId,
    );
    if (existing?['status'] == 'scheduled') return existing!;
    final existingChange = await _activeScheduledPlanChange(
      organizationId: organizationId,
      subscriptionId: subscriptionId,
    );
    if (existingChange != null) {
      await _replaceScheduledPlanChange(
        existingChange,
        status: 'superseded',
        supersededBy: cancellationId,
        now: now,
      );
    }
    final updatedSubscription = <String, Object?>{
      ...active,
      'cancelAtCycleEnd': true,
      'scheduledPlanChangeId': null,
      'scheduledPlanKey': null,
      'scheduledProviderPlanId': null,
      'providerScheduledAt': null,
      'hasScheduledProviderChanges': false,
      'updatedAt': now,
    };
    await store.replaceJson(
      'billing_subscriptions',
      subscriptionId,
      updatedSubscription,
    );
    final cancellation = <String, Object?>{
      'id': cancellationId,
      'organizationId': organizationId,
      'subscriptionId': subscriptionId,
      'provider': 'razorpay',
      'status': 'scheduled',
      'effectiveAt': active['currentEndAt'],
      'createdAt': existing?['createdAt'] ?? now,
      'updatedAt': now,
    };
    final revision = await _nextScheduledPlanChangeRevision(organizationId);
    final scheduledPlanChange = <String, Object?>{
      'id': _scheduledPlanChangeId(organizationId, subscriptionId, revision),
      'organizationId': organizationId,
      'subscriptionId': subscriptionId,
      'providerSubscriptionId': active['providerSubscriptionId'],
      'currentPlanKey': active['cloudPlanKey'],
      'targetPlanKey': cloudPlanFreeKey,
      'targetPlanId': null,
      'targetProviderPlanId': null,
      'status': 'scheduled',
      'effectiveAt': active['currentEndAt'],
      'providerScheduledAt': null,
      'providerStatus': null,
      'revision': revision,
      'source': 'cancellation',
      'requestedBy': actorId,
      'requestedAt': now,
      'createdAt': now,
      'updatedAt': now,
    };
    await store.createJson(
      'billing_plan_changes',
      scheduledPlanChange['id']! as String,
      scheduledPlanChange,
    );
    final cancellationWithChange = <String, Object?>{
      ...cancellation,
      'scheduledPlanChangeId': scheduledPlanChange['id'],
      'targetPlanKey': cloudPlanFreeKey,
    };
    if (existing == null) {
      await store.createJson(
        'billing_cancellations',
        cancellationId,
        cancellationWithChange,
      );
    } else {
      await store.replaceJson(
        'billing_cancellations',
        cancellationId,
        cancellationWithChange,
      );
    }
    return cancellationWithChange;
  }

  /// Creates a server-owned future lower-plan transition. The current
  /// entitlement remains unchanged until Razorpay confirms the cycle-end
  /// update. Free is represented by the cancellation operation so provider
  /// renewal and Hyfens state cannot diverge.
  Future<Map<String, Object?>> prepareScheduledPlanChange({
    required String organizationId,
    required String targetPlanKey,
    String? actorId,
  }) => _serializedScheduledPlanChange(() async {
    _requireCloudDeployment();
    _organization(organizationId);
    await _ensureOrganizationCanStartPaidCheckout(organizationId);
    final target = _scheduledDowngradeTarget(targetPlanKey);
    if (target == cloudPlanFreeKey) {
      return _requestCancellation(
        organizationId: organizationId,
        actorId: actorId,
      );
    }
    final effective = await resolveEffectiveEntitlements(
      organizationId: organizationId,
    );
    if (effective.planKey != cloudPlanTeamKey) {
      throw const ControlPlaneException(
        'INVALID_PLAN_TRANSITION',
        'Only an active Team subscription can schedule a Starter downgrade',
        statusCode: 409,
      );
    }
    final active = await _activeProviderSubscription(
      await _scoped('billing_subscriptions', organizationId),
      organizationId,
    );
    if (active == null) {
      throw const ControlPlaneException(
        'BILLING_SUBSCRIPTION_NOT_ACTIVE',
        'An active paid subscription is required for a scheduled downgrade',
        statusCode: 409,
      );
    }
    final subscriptionId = active['id']! as String;
    final currentChange = await _activeScheduledPlanChange(
      organizationId: organizationId,
      subscriptionId: subscriptionId,
    );
    if (currentChange != null) {
      if (currentChange['targetPlanKey'] == target) return currentChange;
      if (currentChange['targetPlanKey'] == cloudPlanFreeKey) {
        throw const ControlPlaneException(
          'PLAN_CHANGE_CONFLICT',
          'Cancellation is already scheduled for this subscription',
          statusCode: 409,
        );
      }
      await _replaceScheduledPlanChange(
        currentChange,
        status: 'superseded',
        now: _clock().toUtc().toIso8601String(),
      );
    }
    final cancellation = await _currentCancellation(organizationId);
    if (cancellation?['status'] == 'scheduled' &&
        cancellation?['subscriptionId'] == subscriptionId) {
      throw const ControlPlaneException(
        'PLAN_CHANGE_CONFLICT',
        'Cancellation is already scheduled for this subscription',
        statusCode: 409,
      );
    }
    final config = _requireRazorpayConfiguration();
    final plan = await _ensureConfiguredProviderPlan(
      organizationId: organizationId,
      planKey: target,
      config: config,
    );
    final now = _clock().toUtc().toIso8601String();
    final revision = await _nextScheduledPlanChangeRevision(organizationId);
    final change = <String, Object?>{
      'id': _scheduledPlanChangeId(organizationId, subscriptionId, revision),
      'organizationId': organizationId,
      'subscriptionId': subscriptionId,
      'providerSubscriptionId': active['providerSubscriptionId'],
      'currentPlanKey': effective.planKey,
      'targetPlanKey': target,
      'targetPlanId': plan['id'],
      'targetProviderPlanId': plan['providerPlanId'],
      'status': 'pending_provider',
      'effectiveAt': active['currentEndAt'],
      'providerScheduledAt': null,
      'providerStatus': null,
      'revision': revision,
      'source': 'customer',
      'requestedBy': actorId,
      'requestedAt': now,
      'createdAt': now,
      'updatedAt': now,
    };
    try {
      await store.createJson(
        'billing_plan_changes',
        change['id']! as String,
        change,
      );
    } on StorageConflict {
      final concurrent = await store.readJson(
        'billing_plan_changes',
        change['id']! as String,
      );
      if (concurrent != null &&
          concurrent['organizationId'] == organizationId &&
          concurrent['subscriptionId'] == subscriptionId &&
          concurrent['targetPlanKey'] == target) {
        return concurrent;
      }
      rethrow;
    }
    return change;
  });

  /// Cancels a pending Team → Starter provider change. Provider cancellation
  /// is performed by the Cloud adapter before this authoritative projection
  /// is changed.
  Future<Map<String, Object?>> cancelScheduledPlanChange({
    required String organizationId,
  }) => _serializedScheduledPlanChange(() async {
    _requireCloudDeployment();
    _organization(organizationId);
    final change = await _activeScheduledPlanChange(
      organizationId: organizationId,
    );
    if (change == null) {
      return <String, Object?>{
        'organizationId': organizationId,
        'status': 'not_scheduled',
      };
    }
    if (change['targetPlanKey'] == cloudPlanFreeKey) {
      throw const ControlPlaneException(
        'PLAN_CHANGE_CONFLICT',
        'A cancellation is not a reversible plan downgrade',
        statusCode: 409,
      );
    }
    final now = _clock().toUtc().toIso8601String();
    final updated = await _replaceScheduledPlanChange(
      change,
      status: 'cancelled',
      now: now,
    );
    final subscriptionId = change['subscriptionId'];
    if (subscriptionId is String) {
      final subscription = await store.readJson(
        'billing_subscriptions',
        subscriptionId,
      );
      if (subscription != null &&
          subscription['scheduledPlanChangeId'] == change['id']) {
        await store.replaceJson(
          'billing_subscriptions',
          subscriptionId,
          <String, Object?>{
            ...subscription,
            'scheduledPlanChangeId': null,
            'scheduledPlanKey': null,
            'scheduledProviderPlanId': null,
            'providerScheduledAt': null,
            'hasScheduledProviderChanges': false,
            'updatedAt': now,
          },
        );
      }
    }
    return updated;
  });

  /// Records Razorpay's accepted cycle-end update without changing the
  /// effective Hyfens plan. This is an internal provider-bridge operation;
  /// tenant identity is derived from the existing provider mapping.
  Future<Map<String, Object?>> confirmScheduledPlanChange({
    required String providerSubscriptionId,
    required String providerPlanId,
    String? providerStatus,
    required bool hasScheduledChanges,
    String? scheduleChangeAt,
    String? changeScheduledAt,
    String? currentEndAt,
  }) => _serializedProviderBridge(() async {
    _requireCloudDeployment();
    final normalizedSubscriptionId = _text(
      providerSubscriptionId,
      'provider subscription ID',
      128,
    );
    final normalizedProviderPlanId = _text(
      providerPlanId,
      'provider plan ID',
      128,
    );
    if (providerStatus != null &&
        !_subscriptionStatuses.contains(providerStatus)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_STATUS',
        'Subscription status is unsupported',
        statusCode: 422,
      );
    }
    if (!hasScheduledChanges ||
        (scheduleChangeAt != null && scheduleChangeAt != 'cycle_end')) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Razorpay did not confirm a cycle-end subscription update',
        statusCode: 422,
      );
    }
    _optionalTimestamp(changeScheduledAt, 'provider scheduled change time');
    _optionalTimestamp(currentEndAt, 'subscription current end');
    final mapping = await _findProviderMapping(
      providerSubscriptionId: normalizedSubscriptionId,
    );
    final existing = mapping?['subscription'];
    final organizationId = mapping?['organizationId'];
    if (mapping == null ||
        existing is! Map<String, Object?> ||
        organizationId is! String) {
      throw const ControlPlaneException(
        'BILLING_SUBSCRIPTION_UNMAPPED',
        'Razorpay subscription is not linked to a Hyfens checkout',
        statusCode: 404,
      );
    }
    final change = await _activeScheduledPlanChange(
      organizationId: organizationId,
      subscriptionId: existing['id'] as String?,
    );
    if (change == null ||
        change['providerSubscriptionId'] != normalizedSubscriptionId) {
      throw const ControlPlaneException(
        'PLAN_CHANGE_NOT_PENDING',
        'No pending scheduled change matches this provider subscription',
        statusCode: 409,
      );
    }
    if (change['targetProviderPlanId'] != normalizedProviderPlanId) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Razorpay scheduled plan does not match the Hyfens target',
        statusCode: 422,
      );
    }
    final targetPlanId = change['targetPlanId'];
    if (targetPlanId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Scheduled plan change is missing its target plan',
        statusCode: 500,
      );
    }
    final targetPlan = await store.readJson('billing_plans', targetPlanId);
    if (targetPlan == null ||
        targetPlan['organizationId'] != organizationId ||
        targetPlan['provider'] != 'razorpay' ||
        targetPlan['providerPlanId'] != normalizedProviderPlanId) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Scheduled plan change references an invalid provider plan',
        statusCode: 500,
      );
    }
    // Razorpay's change_scheduled_at is the timestamp when the update takes
    // effect. Prefer the current cycle end when it is available, while still
    // accepting that provider field as the fallback for older responses.
    final effectiveAt =
        currentEndAt ?? changeScheduledAt ?? change['effectiveAt'];
    final now = _clock().toUtc().toIso8601String();
    final updatedChange = <String, Object?>{
      ...change,
      'status': 'scheduled',
      'effectiveAt': effectiveAt,
      'providerScheduledAt': changeScheduledAt ?? change['providerScheduledAt'],
      'providerStatus': providerStatus ?? change['providerStatus'],
      'updatedAt': now,
    };
    await store.replaceJson(
      'billing_plan_changes',
      change['id']! as String,
      updatedChange,
    );
    final subscriptionId = existing['id'];
    if (subscriptionId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Mapped provider subscription is missing its ID',
        statusCode: 500,
      );
    }
    await store.replaceJson(
      'billing_subscriptions',
      subscriptionId,
      <String, Object?>{
        ...existing,
        'scheduledPlanChangeId': change['id'],
        'scheduledPlanKey': change['targetPlanKey'],
        'scheduledProviderPlanId': normalizedProviderPlanId,
        'providerScheduledAt': effectiveAt,
        'hasScheduledProviderChanges': true,
        'updatedAt': now,
      },
    );
    return updatedChange;
  });

  /// Requests review of a captured payment. This never changes subscription
  /// state; only an authorized operator can approve an amount for provider
  /// execution.
  Future<Map<String, Object?>> requestRefund({
    required String organizationId,
    required String paymentId,
    required String reasonCategory,
    required String explanation,
    required String idempotencyKey,
    int? requestedAmountMinor,
    String? actorId,
  }) async {
    _requireCloudDeployment();
    _organization(organizationId);
    final normalizedPaymentId = requireOpaqueId(paymentId, 'payment ID');
    final normalizedCategory = _text(
      reasonCategory.trim(),
      'refund reason category',
      64,
    );
    if (!_refundReasonCategories.contains(normalizedCategory)) {
      throw const ControlPlaneException(
        'INVALID_REFUND_REASON',
        'The refund reason category is unsupported',
        statusCode: 422,
      );
    }
    final normalizedExplanation = _text(
      explanation.trim(),
      'refund explanation',
      4000,
    );
    final normalizedKey = _text(
      idempotencyKey.trim(),
      'refund idempotency key',
      256,
    );
    final normalizedActor = actorId == null
        ? null
        : _text(actorId.trim(), 'refund actor ID', 256);

    return _withRefundTransaction(normalizedPaymentId, (tx) async {
      final payment = await tx.readJson(
        'billing_payments',
        normalizedPaymentId,
      );
      if (payment == null || payment['organizationId'] != organizationId) {
        throw const ControlPlaneException(
          'NOT_FOUND',
          'Payment was not found for this organization',
          statusCode: 404,
        );
      }
      _assertCapturedPayment(payment);
      final id = _refundRequestId(organizationId, normalizedKey);
      final existing = await tx.readJson('billing_refund_requests', id);
      if (existing != null) {
        final existingAmount = existing['requestedAmountMinor'];
        if (existing['organizationId'] != organizationId ||
            existing['paymentId'] != normalizedPaymentId ||
            existing['reasonCategory'] != normalizedCategory ||
            existing['explanation'] != normalizedExplanation ||
            (requestedAmountMinor != null &&
                existingAmount != requestedAmountMinor)) {
          throw const ControlPlaneException(
            'REFUND_IDEMPOTENCY_CONFLICT',
            'The refund idempotency key was already used for another request',
            statusCode: 409,
          );
        }
        return _refundRequestProjection(existing, payment: payment);
      }
      final balance = await _refundableBalance(tx, payment);
      if (balance <= 0) {
        throw const ControlPlaneException(
          'REFUND_NOT_AVAILABLE',
          'This payment has no refundable balance',
          statusCode: 409,
        );
      }
      final amount = requestedAmountMinor ?? balance;
      _refundAmount(amount);
      if (amount > balance) {
        throw const ControlPlaneException(
          'REFUND_AMOUNT_EXCEEDS_BALANCE',
          'The requested refund exceeds the refundable balance',
          statusCode: 422,
        );
      }
      final now = _clock().toUtc().toIso8601String();
      final request = <String, Object?>{
        'id': id,
        'organizationId': organizationId,
        'paymentId': normalizedPaymentId,
        'provider': payment['provider'],
        'providerPaymentId': payment['providerPaymentId'],
        'reasonCategory': normalizedCategory,
        'explanation': normalizedExplanation,
        'requestedAmountMinor': amount,
        'currency': payment['currency'],
        'requestedBy': normalizedActor,
        'status': 'requested',
        'createdAt': now,
        'updatedAt': now,
      };
      await tx.createJson('billing_refund_requests', id, request);
      return _refundRequestProjection(request, payment: payment);
    });
  }

  /// Returns the operator refund projection. Customer callers receive only
  /// the organization-scoped request projection through [read].
  Future<List<Map<String, Object?>>> listRefundRequests({
    String? organizationId,
  }) async {
    _requireCloudDeployment();
    if (organizationId != null) _organization(organizationId);
    final requests = await store.listJson('billing_refund_requests');
    final result = <Map<String, Object?>>[];
    for (final request in requests) {
      if (organizationId != null && request['organizationId'] != organizationId)
        continue;
      final paymentId = request['paymentId'];
      if (paymentId is! String) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Refund request has no payment reference',
          statusCode: 500,
        );
      }
      final payment = await store.readJson('billing_payments', paymentId);
      if (payment == null) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Refund request references a missing payment',
          statusCode: 500,
        );
      }
      final decision = await _decisionForRequest(request['id']! as String);
      final provider = await _latestProviderRefund(request['id']! as String);
      result.add(
        _refundRequestProjection(
          request,
          payment: payment,
          decision: decision,
          providerRefund: provider,
        ),
      );
    }
    result.sort((left, right) {
      final leftAt = DateTime.tryParse('${left['updatedAt']}');
      final rightAt = DateTime.tryParse('${right['updatedAt']}');
      return (rightAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        leftAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
    return List.unmodifiable(result);
  }

  /// Approves one exact amount after reloading the captured payment and
  /// reserving the remaining balance under the refund transaction lock.
  Future<Map<String, Object?>> approveRefund({
    required String refundRequestId,
    required int approvedAmountMinor,
    required String actorId,
    required String decisionReason,
  }) async {
    _requireCloudDeployment();
    final normalizedRequestId = requireOpaqueId(
      refundRequestId,
      'refund request ID',
    );
    final initial = await store.readJson(
      'billing_refund_requests',
      normalizedRequestId,
    );
    if (initial == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Refund request was not found',
        statusCode: 404,
      );
    }
    final paymentId = initial['paymentId'];
    if (paymentId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Refund request has no payment reference',
        statusCode: 500,
      );
    }
    final normalizedActor = _text(actorId.trim(), 'refund operator ID', 256);
    final normalizedReason = _text(
      decisionReason.trim(),
      'refund decision reason',
      4000,
    );
    _refundAmount(approvedAmountMinor);
    return _withRefundTransaction(paymentId, (tx) async {
      final request = await tx.readJson(
        'billing_refund_requests',
        normalizedRequestId,
      );
      if (request == null) {
        throw const ControlPlaneException(
          'NOT_FOUND',
          'Refund request was not found',
          statusCode: 404,
        );
      }
      final organizationId = request['organizationId'];
      final requestPaymentId = request['paymentId'];
      if (organizationId is! String || requestPaymentId != paymentId) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Refund request mapping is invalid',
          statusCode: 500,
        );
      }
      final payment = await tx.readJson('billing_payments', paymentId);
      if (payment == null || payment['organizationId'] != organizationId) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Refund payment mapping is invalid',
          statusCode: 500,
        );
      }
      _assertCapturedPayment(payment);
      final existingDecision = await _decisionForRequestWith(
        tx,
        normalizedRequestId,
      );
      if (existingDecision != null) {
        if (existingDecision['status'] == 'approved' &&
            existingDecision['approvedAmountMinor'] == approvedAmountMinor) {
          return _refundRequestProjection(
            request,
            payment: payment,
            decision: existingDecision,
            providerRefund: await _latestProviderRefundWith(
              tx,
              normalizedRequestId,
            ),
          );
        }
        throw const ControlPlaneException(
          'REFUND_DECISION_CONFLICT',
          'This refund request already has a different terminal decision',
          statusCode: 409,
        );
      }
      if (request['status'] == 'rejected' || request['status'] == 'refunded') {
        throw const ControlPlaneException(
          'REFUND_DECISION_CONFLICT',
          'This refund request cannot be approved in its current state',
          statusCode: 409,
        );
      }
      final balance = await _refundableBalance(tx, payment);
      if (approvedAmountMinor > balance) {
        throw const ControlPlaneException(
          'REFUND_AMOUNT_EXCEEDS_BALANCE',
          'The approved refund exceeds the refundable balance',
          statusCode: 422,
        );
      }
      final now = _clock().toUtc().toIso8601String();
      final decision = <String, Object?>{
        'id': _refundDecisionId(normalizedRequestId),
        'organizationId': organizationId,
        'refundRequestId': normalizedRequestId,
        'status': 'approved',
        'approvedAmountMinor': approvedAmountMinor,
        'currency': payment['currency'],
        'operatorId': normalizedActor,
        'reason': normalizedReason,
        'createdAt': now,
        'updatedAt': now,
      };
      await tx.createJson(
        'billing_refund_decisions',
        decision['id']! as String,
        decision,
      );
      final updated = <String, Object?>{
        ...request,
        'status': 'approved',
        'approvedAmountMinor': approvedAmountMinor,
        'decisionId': decision['id'],
        'updatedAt': now,
      };
      await tx.replaceJson(
        'billing_refund_requests',
        normalizedRequestId,
        updated,
      );
      return _refundRequestProjection(
        updated,
        payment: payment,
        decision: decision,
      );
    });
  }

  Future<Map<String, Object?>> rejectRefund({
    required String refundRequestId,
    required String actorId,
    required String decisionReason,
  }) async {
    _requireCloudDeployment();
    final normalizedRequestId = requireOpaqueId(
      refundRequestId,
      'refund request ID',
    );
    final initial = await store.readJson(
      'billing_refund_requests',
      normalizedRequestId,
    );
    if (initial == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Refund request was not found',
        statusCode: 404,
      );
    }
    final paymentId = initial['paymentId'];
    if (paymentId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Refund request has no payment reference',
        statusCode: 500,
      );
    }
    final normalizedActor = _text(actorId.trim(), 'refund operator ID', 256);
    final normalizedReason = _text(
      decisionReason.trim(),
      'refund decision reason',
      4000,
    );
    return _withRefundTransaction(paymentId, (tx) async {
      final request = await tx.readJson(
        'billing_refund_requests',
        normalizedRequestId,
      );
      if (request == null) {
        throw const ControlPlaneException(
          'NOT_FOUND',
          'Refund request was not found',
          statusCode: 404,
        );
      }
      final organizationId = request['organizationId'];
      if (organizationId is! String || request['paymentId'] != paymentId) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Refund request mapping is invalid',
          statusCode: 500,
        );
      }
      final payment = await tx.readJson('billing_payments', paymentId);
      if (payment == null || payment['organizationId'] != organizationId) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Refund payment mapping is invalid',
          statusCode: 500,
        );
      }
      final existingDecision = await _decisionForRequestWith(
        tx,
        normalizedRequestId,
      );
      if (existingDecision != null) {
        if (existingDecision['status'] == 'rejected') {
          return _refundRequestProjection(
            request,
            payment: payment,
            decision: existingDecision,
          );
        }
        throw const ControlPlaneException(
          'REFUND_DECISION_CONFLICT',
          'This refund request already has a provider decision',
          statusCode: 409,
        );
      }
      final now = _clock().toUtc().toIso8601String();
      final decision = <String, Object?>{
        'id': _refundDecisionId(normalizedRequestId),
        'organizationId': organizationId,
        'refundRequestId': normalizedRequestId,
        'status': 'rejected',
        'approvedAmountMinor': 0,
        'currency': payment['currency'],
        'operatorId': normalizedActor,
        'reason': normalizedReason,
        'createdAt': now,
        'updatedAt': now,
      };
      await tx.createJson(
        'billing_refund_decisions',
        decision['id']! as String,
        decision,
      );
      final updated = <String, Object?>{
        ...request,
        'status': 'rejected',
        'decisionId': decision['id'],
        'updatedAt': now,
      };
      await tx.replaceJson(
        'billing_refund_requests',
        normalizedRequestId,
        updated,
      );
      return _refundRequestProjection(
        updated,
        payment: payment,
        decision: decision,
      );
    });
  }

  /// Claims a provider refund attempt. The returned provider payment ID and
  /// amount are derived from the approved Hyfens records, never from a
  /// provider/browser request.
  Future<Map<String, Object?>> prepareProviderRefund({
    required String refundRequestId,
  }) async {
    _requireCloudDeployment();
    final normalizedRequestId = requireOpaqueId(
      refundRequestId,
      'refund request ID',
    );
    final initial = await store.readJson(
      'billing_refund_requests',
      normalizedRequestId,
    );
    if (initial == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Refund request was not found',
        statusCode: 404,
      );
    }
    final paymentId = initial['paymentId'];
    if (paymentId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Refund request has no payment reference',
        statusCode: 500,
      );
    }
    return _withRefundTransaction(paymentId, (tx) async {
      final request = await tx.readJson(
        'billing_refund_requests',
        normalizedRequestId,
      );
      if (request == null) {
        throw const ControlPlaneException(
          'NOT_FOUND',
          'Refund request was not found',
          statusCode: 404,
        );
      }
      final organizationId = request['organizationId'];
      if (organizationId is! String || request['paymentId'] != paymentId) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Refund request mapping is invalid',
          statusCode: 500,
        );
      }
      final payment = await tx.readJson('billing_payments', paymentId);
      if (payment == null || payment['organizationId'] != organizationId) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Refund payment mapping is invalid',
          statusCode: 500,
        );
      }
      _assertCapturedPayment(payment);
      final decision = await _decisionForRequestWith(tx, normalizedRequestId);
      if (decision == null || decision['status'] != 'approved') {
        throw const ControlPlaneException(
          'REFUND_NOT_APPROVED',
          'Refund must be approved before provider execution',
          statusCode: 409,
        );
      }
      final amount = decision['approvedAmountMinor'];
      final currency = payment['currency'];
      if (amount is! int || currency is! String) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Approved refund is missing its amount or currency',
          statusCode: 500,
        );
      }
      final attempts = (await tx.listJson('billing_provider_refunds'))
          .where((row) => row['refundRequestId'] == normalizedRequestId)
          .toList();
      attempts.sort(
        (left, right) => ((right['attempt'] as int?) ?? 0).compareTo(
          (left['attempt'] as int?) ?? 0,
        ),
      );
      final latest = attempts.isEmpty ? null : attempts.first;
      if (latest != null && latest['status'] == 'processed') {
        return _providerRefundPreparation(latest, payment, request);
      }
      if (latest != null && latest['status'] == 'pending') {
        // Reuse the same attempt and idempotency key after a transport
        // failure. Creating a new attempt before the provider result is
        // known could turn one operator action into two refunds.
        return _providerRefundPreparation(latest, payment, request);
      }
      final attempt = ((latest?['attempt'] as int?) ?? 0) + 1;
      final now = _clock().toUtc().toIso8601String();
      final providerRefund = <String, Object?>{
        'id': _providerRefundId(normalizedRequestId, attempt),
        'organizationId': organizationId,
        'refundRequestId': normalizedRequestId,
        'paymentId': paymentId,
        'provider': 'razorpay',
        'providerPaymentId': payment['providerPaymentId'],
        'providerRefundId': null,
        'amountMinor': amount,
        'currency': currency,
        'attempt': attempt,
        'idempotencyKey': _providerRefundIdempotencyKey(
          normalizedRequestId,
          attempt,
        ),
        'status': 'pending',
        'createdAt': now,
        'updatedAt': now,
      };
      await tx.createJson(
        'billing_provider_refunds',
        providerRefund['id']! as String,
        providerRefund,
      );
      await tx.replaceJson(
        'billing_refund_requests',
        normalizedRequestId,
        <String, Object?>{
          ...request,
          'status': 'provider_pending',
          'providerRefundId': providerRefund['id'],
          'updatedAt': now,
        },
      );
      return _providerRefundPreparation(providerRefund, payment, request);
    });
  }

  /// Records a provider response. A processed refund is terminal; a failed
  /// response remains retryable without changing subscription entitlements.
  Future<Map<String, Object?>> recordProviderRefundResult({
    required String refundRequestId,
    required String providerRefundRecordId,
    required String status,
    String? providerRefundId,
    int? amountMinor,
    String? currency,
    String? errorCode,
  }) async {
    _requireCloudDeployment();
    final normalizedRequestId = requireOpaqueId(
      refundRequestId,
      'refund request ID',
    );
    final normalizedAttemptId = requireOpaqueId(
      providerRefundRecordId,
      'provider refund record ID',
    );
    if (!_providerRefundStatuses.contains(status)) {
      throw const ControlPlaneException(
        'INVALID_REFUND_STATUS',
        'Provider refund status is unsupported',
        statusCode: 422,
      );
    }
    if (status != 'failed' &&
        (providerRefundId == null || providerRefundId.trim().isEmpty)) {
      throw const ControlPlaneException(
        'INVALID_PROVIDER_REFUND',
        'A provider refund ID is required for this status',
        statusCode: 422,
      );
    }
    final initial = await store.readJson(
      'billing_provider_refunds',
      normalizedAttemptId,
    );
    if (initial == null || initial['refundRequestId'] != normalizedRequestId) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Provider refund attempt was not found',
        statusCode: 404,
      );
    }
    final paymentId = initial['paymentId'];
    if (paymentId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Provider refund attempt has no payment reference',
        statusCode: 500,
      );
    }
    return _withRefundTransaction(paymentId, (tx) async {
      final providerRefund = await tx.readJson(
        'billing_provider_refunds',
        normalizedAttemptId,
      );
      final request = await tx.readJson(
        'billing_refund_requests',
        normalizedRequestId,
      );
      final payment = await tx.readJson('billing_payments', paymentId);
      if (providerRefund == null || request == null || payment == null) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Refund provider state is incomplete',
          statusCode: 500,
        );
      }
      if (providerRefund['refundRequestId'] != normalizedRequestId ||
          request['paymentId'] != paymentId ||
          payment['organizationId'] != request['organizationId']) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Refund provider mapping is invalid',
          statusCode: 500,
        );
      }
      _assertCapturedPayment(payment);
      final expectedAmount = providerRefund['amountMinor'];
      final expectedCurrency = providerRefund['currency'];
      if (expectedAmount is! int || expectedCurrency is! String) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Provider refund attempt is missing amount or currency',
          statusCode: 500,
        );
      }
      if (amountMinor != null && amountMinor != expectedAmount ||
          currency != null && currency != expectedCurrency) {
        throw const ControlPlaneException(
          'BILLING_PROVIDER_MISMATCH',
          'Provider refund amount or currency does not match approval',
          statusCode: 422,
        );
      }
      final normalizedProviderRefundId = providerRefundId == null
          ? null
          : _text(providerRefundId.trim(), 'provider refund ID', 128);
      if (normalizedProviderRefundId != null) {
        for (final row in await tx.listJson('billing_provider_refunds')) {
          if (row['providerRefundId'] == normalizedProviderRefundId &&
              row['id'] != normalizedAttemptId) {
            throw const ControlPlaneException(
              'BILLING_PROVIDER_REFUND_CONFLICT',
              'The provider refund is already mapped to another attempt',
              statusCode: 409,
            );
          }
        }
      }
      final currentStatus = providerRefund['status'];
      if (currentStatus == 'processed') {
        if (normalizedProviderRefundId != null &&
            providerRefund['providerRefundId'] != null &&
            providerRefund['providerRefundId'] != normalizedProviderRefundId) {
          throw const ControlPlaneException(
            'BILLING_PROVIDER_REFUND_CONFLICT',
            'The provider refund is already mapped to a different refund',
            statusCode: 409,
          );
        }
        if (status != 'processed' ||
            providerRefund['providerRefundId'] != normalizedProviderRefundId) {
          return _refundRequestProjection(
            request,
            payment: payment,
            decision: await _decisionForRequestWith(tx, normalizedRequestId),
            providerRefund: providerRefund,
          );
        }
      }
      if (currentStatus == 'failed' && status == 'pending') {
        return _refundRequestProjection(
          request,
          payment: payment,
          decision: await _decisionForRequestWith(tx, normalizedRequestId),
          providerRefund: providerRefund,
        );
      }
      final now = _clock().toUtc().toIso8601String();
      final updatedProvider = <String, Object?>{
        ...providerRefund,
        'providerRefundId':
            normalizedProviderRefundId ?? providerRefund['providerRefundId'],
        'status': status,
        if (errorCode != null)
          'errorCode': _text(errorCode, 'refund error', 128),
        'updatedAt': now,
      };
      await tx.replaceJson(
        'billing_provider_refunds',
        normalizedAttemptId,
        updatedProvider,
      );
      final requestStatus = status == 'processed'
          ? 'refunded'
          : status == 'failed'
          ? 'failed'
          : 'provider_pending';
      final updatedRequest = <String, Object?>{
        ...request,
        'status': requestStatus,
        'updatedAt': now,
      };
      await tx.replaceJson(
        'billing_refund_requests',
        normalizedRequestId,
        updatedRequest,
      );
      return _refundRequestProjection(
        updatedRequest,
        payment: payment,
        decision: await _decisionForRequestWith(tx, normalizedRequestId),
        providerRefund: updatedProvider,
      );
    });
  }

  /// Applies a signed Razorpay subscription event. The event is mapped to an
  /// organization through an existing provider subscription or a server-owned
  /// checkout intent; the payload can never choose its own tenant.
  Future<BillingProviderEventResult> applyRazorpayWebhook({
    required List<int> rawBody,
    required String signature,
    String? eventIdOverride,
  }) async {
    _requireCloudDeployment();
    final config = _requireRazorpayConfiguration();
    _verifyWebhookSignature(rawBody, signature, config.webhookSecret);
    late final Map<String, Object?> body;
    try {
      final decoded = jsonDecode(utf8.decode(rawBody, allowMalformed: false));
      if (decoded is! Map)
        throw const FormatException('Webhook body is not an object');
      body = <String, Object?>{
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    } on FormatException {
      throw const ControlPlaneException(
        'INVALID_BILLING_WEBHOOK',
        'Razorpay webhook JSON is invalid',
        statusCode: 422,
      );
    }
    final eventId = _providerText(
      body['id'] ?? eventIdOverride,
      'Razorpay event ID',
      256,
    );
    final eventName = _providerText(body['event'], 'Razorpay event name', 128);
    final result = await _applyRazorpayWebhookBody(
      rawBody: rawBody,
      body: body,
      eventId: eventId,
      eventName: eventName,
    );
    return result.copyWith(eventName: eventName);
  }

  Future<BillingProviderEventResult> _applyRazorpayWebhookBody({
    required List<int> rawBody,
    required Map<String, Object?> body,
    required String eventId,
    required String eventName,
    bool processSubscriptionPayment = true,
  }) async {
    final paymentEntity = _providerPaymentEntity(body);
    if (paymentEntity != null && eventName.startsWith('payment.')) {
      return _applyRazorpayPaymentWebhook(
        body: body,
        entity: paymentEntity,
        rawBody: rawBody,
        eventId: eventId,
        eventName: eventName,
      );
    }
    if (processSubscriptionPayment &&
        paymentEntity != null &&
        (eventName == 'subscription.charged' ||
            eventName == 'subscription.completed')) {
      final subscriptionEntity = _providerSubscriptionEntity(body);
      final subscriptionResult = await _applyRazorpayWebhookBody(
        rawBody: rawBody,
        body: body,
        eventId: eventId,
        eventName: eventName,
        processSubscriptionPayment: false,
      );
      final paymentResult = await _applyRazorpayPaymentWebhook(
        body: body,
        entity: paymentEntity,
        providerSubscriptionIdOverride: _providerString(
          subscriptionEntity['id'],
        ),
        recordProviderEvent: false,
        rawBody: rawBody,
        eventId: eventId,
        eventName: eventName,
      );
      return BillingProviderEventResult(
        status: subscriptionResult.status,
        eventId: eventId,
        organizationId: subscriptionResult.organizationId,
        subscription: subscriptionResult.subscription,
        checkout: subscriptionResult.checkout,
        enterpriseContract: subscriptionResult.enterpriseContract,
        payment: paymentResult.payment,
        refund: subscriptionResult.refund,
        scheduledPlanChange: subscriptionResult.scheduledPlanChange,
      );
    }
    final refundEntity = _providerRefundEntity(body);
    if (refundEntity != null && eventName.startsWith('refund.')) {
      return _applyRazorpayRefundWebhook(
        body: body,
        entity: refundEntity,
        rawBody: rawBody,
        eventId: eventId,
        eventName: eventName,
      );
    }
    final entity = _providerSubscriptionEntity(body);
    final providerSubscriptionId = _providerText(
      entity['id'],
      'Razorpay subscription ID',
      128,
    );
    final providerPlanId = _providerText(
      entity['plan_id'],
      'Razorpay plan ID',
      128,
    );
    final enterpriseMapping = await enterprise.providerMapping(
      providerSubscriptionId,
    );
    if (enterpriseMapping != null) {
      return _applyEnterpriseRazorpayWebhook(
        body: body,
        entity: entity,
        rawBody: rawBody,
        eventId: eventId,
        eventName: eventName,
        providerSubscriptionId: providerSubscriptionId,
        providerPlanId: providerPlanId,
        mapping: enterpriseMapping,
      );
    }
    final notes = _providerMap(entity['notes']);
    final checkoutId = notes?['hyfens_checkout_id'];
    final mapped = await _findProviderMapping(
      providerSubscriptionId: providerSubscriptionId,
      checkoutId: checkoutId is String ? checkoutId : null,
    );
    if (mapped == null) {
      throw const ControlPlaneException(
        'BILLING_SUBSCRIPTION_UNMAPPED',
        'Razorpay subscription is not linked to a Hyfens checkout',
        statusCode: 422,
      );
    }
    final organizationId = mapped['organizationId']! as String;
    _organization(organizationId);
    final existing = mapped['subscription'] is Map<String, Object?>
        ? mapped['subscription']! as Map<String, Object?>
        : null;
    final intent = mapped['checkout'] is Map<String, Object?>
        ? mapped['checkout']! as Map<String, Object?>
        : null;
    final providerStatus = _providerStatus(eventName, entity['status']);
    final scheduledChange = existing == null
        ? null
        : await _activeScheduledPlanChange(
            organizationId: organizationId,
            subscriptionId: existing['id'] as String?,
          );
    final isScheduledTransition =
        scheduledChange != null &&
        scheduledChange['targetProviderPlanId'] == providerPlanId;
    final expectedPlanId = isScheduledTransition
        ? providerPlanId
        : existing?['providerPlanId'] ?? intent?['providerPlanId'];
    if (expectedPlanId is! String || expectedPlanId != providerPlanId) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Razorpay subscription plan does not match the customer checkout',
        statusCode: 422,
      );
    }
    final planId = isScheduledTransition
        ? scheduledChange['targetPlanId']
        : existing?['planId'] ?? intent?['planId'];
    if (planId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Mapped Razorpay subscription is missing a billing plan',
        statusCode: 500,
      );
    }
    final plan = await store.readJson('billing_plans', planId);
    if (plan == null || plan['organizationId'] != organizationId) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Mapped Razorpay subscription references an invalid billing plan',
        statusCode: 500,
      );
    }
    _validateProviderAmounts(entity, plan);
    final occurredAt = _providerTimestamp(
      body['created_at'] ?? entity['created_at'],
    );
    final created = await recordEvent(
      organizationId: organizationId,
      provider: 'razorpay',
      eventId: eventId,
      eventName: eventName,
      payloadDigest: sha256Digest(rawBody),
      providerSubscriptionId: providerSubscriptionId,
      occurredAt: occurredAt,
    );
    if (!created) {
      return BillingProviderEventResult(
        status: 'duplicate',
        eventId: eventId,
        organizationId: organizationId,
        subscription: existing,
        checkout: intent,
      );
    }
    if (_providerEventIsOlder(existing, occurredAt)) {
      return BillingProviderEventResult(
        status: 'ignored_out_of_order',
        eventId: eventId,
        organizationId: organizationId,
        subscription: existing,
        checkout: intent,
      );
    }
    if (existing == null &&
        intent != null &&
        (intent['status'] == 'cancelled' || intent['status'] == 'failed')) {
      return BillingProviderEventResult(
        status: 'ignored_terminal_checkout',
        eventId: eventId,
        organizationId: organizationId,
        checkout: intent,
      );
    }
    if ((eventName == 'payment.failed' ||
            eventName == 'subscription.payment_failed') &&
        existing == null &&
        intent != null) {
      final failedCheckout = <String, Object?>{
        ...intent,
        'status': 'failed',
        'providerEventId': eventId,
        'updatedAt': _clock().toUtc().toIso8601String(),
      };
      await store.replaceJson(
        'billing_checkout_intents',
        intent['id']! as String,
        failedCheckout,
      );
      return BillingProviderEventResult(
        status: 'applied',
        eventId: eventId,
        organizationId: organizationId,
        checkout: failedCheckout,
      );
    }
    if ((eventName == 'payment.failed' ||
            eventName == 'subscription.payment_failed') &&
        existing != null) {
      // A failed renewal payment is not, by itself, proof that a previously
      // active subscription has ended. Preserve the last trusted paid state
      // until Razorpay sends a terminal subscription event.
      return BillingProviderEventResult(
        status: 'applied',
        eventId: eventId,
        organizationId: organizationId,
        subscription: existing,
        checkout: intent,
      );
    }
    if (isScheduledTransition &&
        _providerBool(entity['has_scheduled_changes']) == true) {
      final scheduledChange = await _recordScheduledPlanChangeProviderState(
        organizationId: organizationId,
        providerSubscriptionId: providerSubscriptionId,
        providerStatus: providerStatus,
        providerScheduledAt: _providerTimestampText(
          entity['change_scheduled_at'] ?? entity['current_end'],
        ),
        effectiveAt: _providerTimestampText(entity['current_end']),
        providerEventId: eventId,
        providerEventOccurredAt: occurredAt,
      );
      return BillingProviderEventResult(
        status: 'applied',
        eventId: eventId,
        organizationId: organizationId,
        subscription: existing,
        checkout: intent,
        scheduledPlanChange: scheduledChange,
      );
    }
    final status = providerStatus;
    var updatedSubscription = await upsertSubscription(
      organizationId: organizationId,
      provider: 'razorpay',
      providerSubscriptionId: providerSubscriptionId,
      providerPlanId: providerPlanId,
      status: status,
      planId: planId,
      userId: _providerString(entity['customer_id']),
      checkoutId: isScheduledTransition
          ? null
          : intent?['id'] is String
          ? intent!['id']! as String
          : null,
      totalCount: _providerInt(entity['total_count']),
      paidCount: _providerInt(entity['paid_count']),
      remainingCount: _providerInt(entity['remaining_count']),
      currentStartAt: _providerTimestampText(entity['current_start']),
      currentEndAt: _providerTimestampText(entity['current_end']),
      cancelAtCycleEnd: _providerBool(entity['cancel_at_cycle_end']),
      providerEventId: eventId,
      providerEventOccurredAt: occurredAt,
    );
    Map<String, Object?>? updatedCheckout = intent;
    if (intent != null && !isScheduledTransition) {
      final checkoutStatus = intent['status'] == 'completed'
          ? 'completed'
          : status == 'active'
          ? 'completed'
          : _isTerminalProviderStatus(status)
          ? 'failed'
          : 'awaiting_provider_confirmation';
      updatedCheckout = <String, Object?>{
        ...intent,
        'status': checkoutStatus,
        'providerSubscriptionId': providerSubscriptionId,
        'providerEventId': eventId,
        'updatedAt': _clock().toUtc().toIso8601String(),
      };
      await store.replaceJson(
        'billing_checkout_intents',
        intent['id']! as String,
        updatedCheckout,
      );
    }
    Map<String, Object?>? effectiveScheduledChange;
    if (isScheduledTransition) {
      effectiveScheduledChange = await _markScheduledPlanChangeEffective(
        organizationId: organizationId,
        providerSubscriptionId: providerSubscriptionId,
        effectiveAt:
            _providerTimestampText(entity['current_start']) ?? occurredAt,
      );
      updatedSubscription =
          await store.readJson(
            'billing_subscriptions',
            updatedSubscription['id']! as String,
          ) ??
          updatedSubscription;
    }
    if (status == 'active') {
      await _supersedeOtherProviderSubscriptions(
        organizationId: organizationId,
        activeSubscriptionId: updatedSubscription['id']! as String,
      );
    }
    if (_isTerminalProviderStatus(status)) {
      effectiveScheduledChange ??= await _markCancellationEffective(
        organizationId: organizationId,
        subscriptionId: updatedSubscription['id']! as String,
      );
    }
    return BillingProviderEventResult(
      status: 'applied',
      eventId: eventId,
      organizationId: organizationId,
      subscription: updatedSubscription,
      checkout: updatedCheckout,
      scheduledPlanChange: effectiveScheduledChange,
    );
  }

  Future<BillingProviderEventResult> _applyRazorpayPaymentWebhook({
    required Map<String, Object?> body,
    required Map<String, Object?> entity,
    String? providerSubscriptionIdOverride,
    bool recordProviderEvent = true,
    required List<int> rawBody,
    required String eventId,
    required String eventName,
  }) async {
    final providerPaymentId = _providerText(
      entity['id'],
      'Razorpay payment ID',
      128,
    );
    final providerSubscriptionId =
        _providerString(entity['subscription_id']) ??
        providerSubscriptionIdOverride;
    final subscriptionIdFromPayload = providerSubscriptionId;
    if (subscriptionIdFromPayload == null) {
      throw const ControlPlaneException(
        'BILLING_PAYMENT_UNMAPPED',
        'Razorpay payment does not identify a Hyfens subscription',
        statusCode: 422,
      );
    }

    final enterpriseMapping = await enterprise.providerMapping(
      subscriptionIdFromPayload,
    );
    Map<String, Object?>? subscription;
    Map<String, Object?>? checkout;
    Map<String, Object?>? contract;
    String organizationId;
    int? expectedAmount;
    String? expectedCurrency;
    String? planId;
    String? cloudPlanKey;
    String? contractId;
    if (enterpriseMapping != null) {
      final mappedOrganization = enterpriseMapping['organizationId'];
      final mappedContract = enterpriseMapping['contractId'];
      if (mappedOrganization is! String || mappedContract is! String) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Enterprise provider mapping is missing its organization or contract',
          statusCode: 500,
        );
      }
      organizationId = mappedOrganization;
      contractId = mappedContract;
      expectedAmount = enterpriseMapping['amountMinor'] as int?;
      expectedCurrency = enterpriseMapping['currency'] as String?;
      subscription = await enterprise.providerSubscription(
        subscriptionIdFromPayload,
      );
      contract = await enterprise.currentContract(
        organizationId: organizationId,
      );
    } else {
      final mapped = await _findProviderMapping(
        providerSubscriptionId: subscriptionIdFromPayload,
      );
      if (mapped == null) {
        throw const ControlPlaneException(
          'BILLING_PAYMENT_UNMAPPED',
          'Razorpay payment is not linked to a Hyfens subscription',
          statusCode: 422,
        );
      }
      organizationId = mapped['organizationId']! as String;
      _organization(organizationId);
      subscription = mapped['subscription'] is Map<String, Object?>
          ? mapped['subscription']! as Map<String, Object?>
          : null;
      checkout = mapped['checkout'] is Map<String, Object?>
          ? mapped['checkout']! as Map<String, Object?>
          : null;
      final rawPlanId = subscription?['planId'] ?? checkout?['planId'];
      if (rawPlanId is! String) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Mapped payment subscription has no billing plan',
          statusCode: 500,
        );
      }
      planId = rawPlanId;
      final plan = await store.readJson('billing_plans', planId);
      if (plan == null || plan['organizationId'] != organizationId) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Mapped payment subscription references an invalid plan',
          statusCode: 500,
        );
      }
      expectedAmount = plan['amountMinor'] as int?;
      expectedCurrency = plan['currency'] as String?;
      cloudPlanKey = plan['key'] as String?;
    }
    _organization(organizationId);
    final amount = _providerInt(entity['amount']);
    final currency = _providerString(entity['currency']);
    if (expectedAmount != null && amount != null && amount != expectedAmount) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Razorpay payment amount does not match the Hyfens billing state',
        statusCode: 422,
      );
    }
    if (expectedCurrency != null &&
        currency != null &&
        currency != expectedCurrency) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Razorpay payment currency does not match the Hyfens billing state',
        statusCode: 422,
      );
    }
    final isCaptured =
        eventName == 'payment.captured' ||
        entity['status'] == 'captured' ||
        entity['captured'] == true;
    if (isCaptured && (amount == null || currency == null)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_WEBHOOK',
        'A captured Razorpay payment must include amount and currency',
        statusCode: 422,
      );
    }
    final occurredAt = _providerTimestamp(
      body['created_at'] ?? entity['created_at'],
    );
    final created = recordProviderEvent
        ? await recordEvent(
            organizationId: organizationId,
            provider: 'razorpay',
            eventId: eventId,
            eventName: eventName,
            payloadDigest: sha256Digest(rawBody),
            providerSubscriptionId: subscriptionIdFromPayload,
            providerPaymentId: providerPaymentId,
            occurredAt: occurredAt,
          )
        : true;
    final paymentId = _paymentId(organizationId, providerPaymentId);
    final current = await store.readJson('billing_payments', paymentId);
    if (!created && current != null) {
      return BillingProviderEventResult(
        status: 'duplicate',
        eventId: eventId,
        organizationId: organizationId,
        subscription: subscription,
        checkout: checkout,
        enterpriseContract: contract,
        payment: current,
      );
    }
    final status = isCaptured
        ? 'captured'
        : eventName == 'payment.failed' || entity['status'] == 'failed'
        ? 'failed'
        : 'authorized';
    final now = _clock().toUtc().toIso8601String();
    final value = <String, Object?>{
      'id': paymentId,
      'organizationId': organizationId,
      'provider': 'razorpay',
      'providerPaymentId': providerPaymentId,
      'providerSubscriptionId': subscriptionIdFromPayload,
      'subscriptionId': subscription?['id'],
      'planId': planId ?? subscription?['planId'],
      if (cloudPlanKey != null) 'cloudPlanKey': cloudPlanKey,
      if (contractId != null) 'contractId': contractId,
      'amountMinor': amount ?? expectedAmount,
      'currency': currency ?? expectedCurrency,
      'status': current?['status'] == 'captured' ? 'captured' : status,
      'capturedAt': isCaptured
          ? (current?['capturedAt'] ?? occurredAt ?? now)
          : current?['capturedAt'],
      'providerEventId': eventId,
      'createdAt': current?['createdAt'] ?? now,
      'updatedAt': now,
    };
    if (value['amountMinor'] is! int || value['currency'] is! String) {
      if (isCaptured) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Payment amount or currency could not be resolved',
          statusCode: 500,
        );
      }
      return BillingProviderEventResult(
        status: 'applied',
        eventId: eventId,
        organizationId: organizationId,
        subscription: subscription,
        checkout: checkout,
        enterpriseContract: contract,
      );
    }
    if (current == null) {
      await store.createJson('billing_payments', paymentId, value);
    } else {
      if (current['organizationId'] != organizationId ||
          current['providerPaymentId'] != providerPaymentId ||
          current['amountMinor'] != value['amountMinor'] ||
          current['currency'] != value['currency']) {
        throw const ControlPlaneException(
          'BILLING_PAYMENT_CONFLICT',
          'Razorpay payment is already mapped to different billing state',
          statusCode: 409,
        );
      }
      await store.replaceJson('billing_payments', paymentId, value);
    }
    return BillingProviderEventResult(
      status: 'applied',
      eventId: eventId,
      organizationId: organizationId,
      subscription: subscription,
      checkout: checkout,
      enterpriseContract: contract,
      payment: value,
    );
  }

  Future<BillingProviderEventResult> _applyRazorpayRefundWebhook({
    required Map<String, Object?> body,
    required Map<String, Object?> entity,
    required List<int> rawBody,
    required String eventId,
    required String eventName,
  }) async {
    final providerRefundId = _providerText(
      entity['id'],
      'Razorpay refund ID',
      128,
    );
    final providerPaymentId = _providerText(
      entity['payment_id'],
      'Razorpay refund payment ID',
      128,
    );
    final paymentRows = (await store.listJson('billing_payments')).where(
      (row) =>
          row['provider'] == 'razorpay' &&
          row['providerPaymentId'] == providerPaymentId,
    );
    final payments = paymentRows.toList();
    if (payments.length != 1) {
      throw const ControlPlaneException(
        'BILLING_REFUND_UNMAPPED',
        'Razorpay refund is not linked to one Hyfens payment',
        statusCode: 422,
      );
    }
    final payment = payments.single;
    final organizationId = payment['organizationId'];
    final paymentId = payment['id'];
    if (organizationId is! String || paymentId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Mapped payment has no organization or ID',
        statusCode: 500,
      );
    }
    _organization(organizationId);
    final occurredAt = _providerTimestamp(
      body['created_at'] ?? entity['created_at'],
    );
    final created = await recordEvent(
      organizationId: organizationId,
      provider: 'razorpay',
      eventId: eventId,
      eventName: eventName,
      payloadDigest: sha256Digest(rawBody),
      providerPaymentId: providerPaymentId,
      providerRefundId: providerRefundId,
      occurredAt: occurredAt,
    );
    final providerRows = (await store.listJson('billing_provider_refunds'))
        .where(
          (row) =>
              row['paymentId'] == paymentId &&
              (row['providerRefundId'] == providerRefundId ||
                  (row['providerRefundId'] == null &&
                      row['status'] == 'pending')),
        )
        .toList();
    if (providerRows.length != 1) {
      throw const ControlPlaneException(
        'BILLING_REFUND_UNMAPPED',
        'Razorpay refund is not linked to one Hyfens refund attempt',
        statusCode: 422,
      );
    }
    final providerRefund = providerRows.single;
    final requestId = providerRefund['refundRequestId'];
    final attemptId = providerRefund['id'];
    if (requestId is! String || attemptId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Provider refund attempt has no request identity',
        statusCode: 500,
      );
    }
    final providerStatus = switch (eventName) {
      'refund.processed' => 'processed',
      'refund.failed' || 'refund.reversed' => 'failed',
      _ => 'pending',
    };
    final result = await recordProviderRefundResult(
      refundRequestId: requestId,
      providerRefundRecordId: attemptId,
      status: providerStatus,
      providerRefundId: providerRefundId,
      amountMinor: _providerInt(entity['amount']),
      currency: _providerString(entity['currency']),
    );
    if (!created) {
      return BillingProviderEventResult(
        status: 'duplicate',
        eventId: eventId,
        organizationId: organizationId,
        payment: payment,
        refund: result,
      );
    }
    return BillingProviderEventResult(
      status: 'applied',
      eventId: eventId,
      organizationId: organizationId,
      payment: payment,
      refund: result,
    );
  }

  Future<BillingProviderEventResult> _applyEnterpriseRazorpayWebhook({
    required Map<String, Object?> body,
    required Map<String, Object?> entity,
    required List<int> rawBody,
    required String eventId,
    required String eventName,
    required String providerSubscriptionId,
    required String providerPlanId,
    required Map<String, Object?> mapping,
  }) async {
    final organizationId = mapping['organizationId'];
    final contractId = mapping['contractId'];
    if (organizationId is! String || contractId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Enterprise provider mapping is missing its server-owned scope',
        statusCode: 500,
      );
    }
    _organization(organizationId);
    if (mapping['providerPlanId'] != providerPlanId) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Razorpay subscription plan does not match the Enterprise contract',
        statusCode: 422,
      );
    }
    final mappedAmount = mapping['amountMinor'];
    final actualAmount = entity['amount'];
    if (actualAmount is int &&
        mappedAmount is int &&
        actualAmount != mappedAmount) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Razorpay subscription amount does not match the Enterprise contract',
        statusCode: 422,
      );
    }
    final mappedCurrency = mapping['currency'];
    final actualCurrency = entity['currency'];
    if (actualCurrency is String &&
        mappedCurrency is String &&
        actualCurrency != mappedCurrency) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Razorpay subscription currency does not match the Enterprise contract',
        statusCode: 422,
      );
    }
    final mappedInterval = mapping['interval'];
    final actualInterval = entity['interval'];
    if (actualInterval is String &&
        mappedInterval is String &&
        actualInterval != mappedInterval) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Razorpay subscription interval does not match the Enterprise contract',
        statusCode: 422,
      );
    }
    final existing = await enterprise.providerSubscription(
      providerSubscriptionId,
    );
    final occurredAt = _providerTimestamp(
      body['created_at'] ?? entity['created_at'],
    );
    final created = await recordEvent(
      organizationId: organizationId,
      provider: 'razorpay',
      eventId: eventId,
      eventName: eventName,
      payloadDigest: sha256Digest(rawBody),
      providerSubscriptionId: providerSubscriptionId,
      occurredAt: occurredAt,
    );
    if (!created) {
      return BillingProviderEventResult(
        status: 'duplicate',
        eventId: eventId,
        organizationId: organizationId,
        subscription: existing,
      );
    }
    if (_providerEventIsOlder(existing, occurredAt)) {
      return BillingProviderEventResult(
        status: 'ignored_out_of_order',
        eventId: eventId,
        organizationId: organizationId,
        subscription: existing,
      );
    }
    final status = _providerStatus(eventName, entity['status']);
    final result = await enterprise.applyProviderEvent(
      providerSubscriptionId: providerSubscriptionId,
      providerPlanId: providerPlanId,
      status: status,
      eventId: eventId,
      occurredAt: occurredAt,
      totalCount: _providerInt(entity['total_count']),
      paidCount: _providerInt(entity['paid_count']),
      remainingCount: _providerInt(entity['remaining_count']),
      currentStartAt: _providerTimestampText(entity['current_start']),
      currentEndAt: _providerTimestampText(entity['current_end']),
      cancelAtCycleEnd: _providerBool(entity['cancel_at_cycle_end']),
    );
    if (status == 'active') {
      await _supersedeOtherProviderSubscriptions(
        organizationId: organizationId,
        activeSubscriptionId: result.subscription['id']! as String,
      );
    }
    final contract = result.contract;
    return BillingProviderEventResult(
      status: 'applied',
      eventId: eventId,
      organizationId: organizationId,
      subscription: result.subscription,
      enterpriseContract: enterprise.customerContract(contract),
    );
  }

  /// Ensures the organization has an explicit Cloud plan assignment. A valid
  /// paid provider subscription always wins; otherwise a deterministic
  /// internal Free assignment is created without contacting a payment
  /// provider.
  Future<Map<String, Object?>> ensureCloudPlanAssignment({
    required String organizationId,
  }) async => _serializedAssignment(() async {
    _requireCloudDeployment();
    _organization(organizationId);
    final organization = await store.readJson('organizations', organizationId);
    if (organization == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Organization was not found',
        statusCode: 404,
      );
    }
    await ensurePlanCatalog();
    final rows = await _scoped('billing_subscriptions', organizationId);
    final paid = await _activeProviderSubscription(rows, organizationId);
    if (paid != null) return paid;

    final existingFree = rows.where(
      (row) =>
          row['provider'] == 'internal' &&
          row['deploymentModel'] == DeploymentModel.cloud.wireValue &&
          row['cloudPlanKey'] == cloudPlanFreeKey &&
          row['status'] == 'active',
    );
    if (existingFree.length > 1) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'More than one active Free assignment matches the organization',
        statusCode: 500,
      );
    }
    if (existingFree.isNotEmpty) return existingFree.first;

    final now = _clock().toUtc().toIso8601String();
    final value = <String, Object?>{
      'id': _cloudFreeAssignmentId(organizationId),
      'organizationId': organizationId,
      'provider': 'internal',
      'providerSubscriptionId': 'hyfens-cloud-free:$organizationId',
      'providerPlanId': cloudPlanFreeKey,
      'planId': null,
      'cloudPlanKey': cloudPlanFreeKey,
      'deploymentModel': DeploymentModel.cloud.wireValue,
      'billingStatus': 'not_required',
      'status': 'active',
      'userId': null,
      'totalCount': null,
      'paidCount': null,
      'remainingCount': null,
      'currentStartAt': null,
      'currentEndAt': null,
      'cancelAtCycleEnd': false,
      'createdAt': now,
      'updatedAt': now,
    };
    try {
      await store.createJson(
        'billing_subscriptions',
        value['id']! as String,
        value,
      );
      return value;
    } on StorageConflict {
      final concurrent = await store.readJson(
        'billing_subscriptions',
        value['id']! as String,
      );
      if (concurrent == null) rethrow;
      if (concurrent['organizationId'] != organizationId ||
          concurrent['provider'] != 'internal' ||
          concurrent['deploymentModel'] != DeploymentModel.cloud.wireValue ||
          concurrent['cloudPlanKey'] != cloudPlanFreeKey ||
          concurrent['status'] != 'active') {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'The deterministic Free assignment conflicts with existing state',
          statusCode: 500,
        );
      }
      return concurrent;
    }
  });

  Future<EffectiveCloudEntitlements> resolveEffectiveEntitlements({
    required String organizationId,
    bool includeMeasuredUsage = false,
  }) async {
    _organization(organizationId);
    await ensurePlanCatalog();
    if (deploymentModel == DeploymentModel.selfHosted) {
      return const EffectiveCloudEntitlements(
        deploymentModel: DeploymentModel.selfHosted,
        planKey: null,
        planName: null,
        billingStatus: 'not_applicable',
        source: 'deployment_model',
        capabilities: cloudCoreEntitlements,
        limits: <String, CloudLimit>{},
      );
    }

    final enterpriseContract = await enterprise.activeContract(
      organizationId: organizationId,
    );
    if (enterpriseContract != null) {
      final definition = await _catalogDefinition(cloudPlanEnterpriseKey);
      final enterpriseLimits = await enterprise.activeEntitlementLimits(
        organizationId: organizationId,
      );
      return EffectiveCloudEntitlements(
        deploymentModel: DeploymentModel.cloud,
        planKey: definition.key,
        planName: definition.name,
        billingStatus: 'provider_managed',
        source: 'enterprise_contract',
        capabilities: definition.capabilities,
        limits: enterpriseLimits ?? definition.limits,
        usage: await _cloudUsage(
          organizationId,
          includeMeasuredUsage: includeMeasuredUsage,
        ),
      );
    }

    final assignment = await ensureCloudPlanAssignment(
      organizationId: organizationId,
    );
    final key = await _cloudPlanKeyForSubscription(
      assignment,
      organizationId: organizationId,
    );
    final usage = await _cloudUsage(
      organizationId,
      includeMeasuredUsage: includeMeasuredUsage,
    );
    if (key != null && key != cloudPlanFreeKey) {
      final definition = await _catalogDefinition(key);
      return EffectiveCloudEntitlements(
        deploymentModel: DeploymentModel.cloud,
        planKey: definition.key,
        planName: definition.name,
        billingStatus: 'provider_managed',
        source: 'provider_subscription',
        capabilities: definition.capabilities,
        limits: definition.limits,
        usage: usage,
      );
    }
    if (assignment['provider'] == 'internal' &&
        assignment['deploymentModel'] == DeploymentModel.cloud.wireValue &&
        assignment['cloudPlanKey'] == cloudPlanFreeKey) {
      final definition = await _catalogDefinition(cloudPlanFreeKey);
      return EffectiveCloudEntitlements(
        deploymentModel: DeploymentModel.cloud,
        planKey: definition.key,
        planName: definition.name,
        billingStatus: 'not_required',
        source: 'cloud_free_assignment',
        capabilities: definition.capabilities,
        limits: definition.limits,
        usage: usage,
      );
    }

    // Preserve a valid paid provider record whose legacy key cannot yet be
    // mapped to one of the four Cloud plans. It must not be silently reduced
    // to Free, but it also must not be promoted to Enterprise by guessing.
    return EffectiveCloudEntitlements(
      deploymentModel: DeploymentModel.cloud,
      planKey: null,
      planName: 'Paid Cloud subscription',
      billingStatus: 'provider_managed',
      source: 'legacy_provider_subscription',
      capabilities: cloudCoreEntitlements,
      limits: const <String, CloudLimit>{},
      usage: usage,
    );
  }

  /// Rejects only new resource admission when a finite Cloud plan boundary is
  /// reached. Existing records are never removed or disabled by a downgrade.
  Future<void> enforceCloudLimit({
    required String organizationId,
    required String resource,
    String? applicationId,
  }) async {
    if (deploymentModel != DeploymentModel.cloud) return;
    final effective = await resolveEffectiveEntitlements(
      organizationId: organizationId,
    );
    final limit = effective.limits[resource];
    if (limit == null || !limit.isFinite || limit.value == null) return;
    final usage = effective.usage ?? await _cloudUsage(organizationId);
    final current = switch (resource) {
      cloudApplicationsLimitKey => usage.applications,
      cloudMembersLimitKey => usage.members,
      cloudEnvironmentsPerApplicationLimitKey => _environmentUsage(
        usage,
        applicationId,
      ),
      _ => throw ControlPlaneException(
        'INVALID_PLAN_LIMIT',
        'The Cloud plan limit is unsupported: $resource',
        statusCode: 500,
      ),
    };
    if (current < limit.value!) return;
    throw ControlPlaneException(
      'PLAN_LIMIT_REACHED',
      'The ${effective.planName ?? 'active Cloud'} plan limit has been reached',
      statusCode: 422,
      details: <String, Object?>{
        'resource': resource,
        'current': current,
        'limit': limit.value,
        'effective_plan': effective.planKey,
      },
    );
  }

  Future<Map<String, Object?>> createPlan({
    required String organizationId,
    required String key,
    required String name,
    required String description,
    required String currency,
    required int amountMinor,
    required String interval,
    required int period,
    required String provider,
    required String providerPlanId,
  }) async {
    _organization(organizationId);
    final normalizedKey = _planKey(key);
    if (isSelfHostedPlanKey(normalizedKey)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_PLAN',
        'Self-hosted is a deployment model, not a Cloud subscription plan',
        statusCode: 422,
      );
    }
    final normalizedName = _text(name, 'plan name', 120);
    final normalizedDescription = _text(description, 'plan description', 500);
    final normalizedCurrency = _currency(currency);
    _amount(amountMinor);
    if (interval != 'monthly' || period != 1) {
      throw const ControlPlaneException(
        'INVALID_BILLING_INTERVAL',
        'Only a one-month billing interval is supported',
        statusCode: 422,
      );
    }
    final normalizedProvider = _text(provider, 'billing provider', 32);
    _requireRazorpay(normalizedProvider);
    final normalizedProviderPlanId = _text(
      providerPlanId,
      'provider plan ID',
      128,
    );
    final current = await _scoped('billing_plans', organizationId);
    for (final plan in current) {
      final sameKey = plan['key'] == normalizedKey;
      final sameProviderPlan =
          plan['provider'] == normalizedProvider &&
          plan['providerPlanId'] == normalizedProviderPlanId;
      if (sameKey || sameProviderPlan) {
        final sameDefinition =
            plan['name'] == normalizedName &&
            plan['description'] == normalizedDescription &&
            plan['currency'] == normalizedCurrency &&
            plan['amountMinor'] == amountMinor &&
            plan['interval'] == interval &&
            plan['period'] == period &&
            plan['provider'] == normalizedProvider &&
            plan['providerPlanId'] == normalizedProviderPlanId;
        if (sameDefinition) return plan;
        throw const ControlPlaneException(
          'BILLING_PLAN_CONFLICT',
          'A billing plan key or provider plan already exists',
          statusCode: 409,
        );
      }
    }

    final now = _clock().toUtc().toIso8601String();
    final value = <String, Object?>{
      'id': _planId(
        organizationId,
        normalizedProvider,
        normalizedProviderPlanId,
      ),
      'organizationId': organizationId,
      'key': normalizedKey,
      'name': normalizedName,
      'description': normalizedDescription,
      'currency': normalizedCurrency,
      'amountMinor': amountMinor,
      'interval': interval,
      'period': period,
      'provider': normalizedProvider,
      'providerPlanId': normalizedProviderPlanId,
      'active': true,
      'createdAt': now,
      'updatedAt': now,
    };
    await store.createJson('billing_plans', value['id']! as String, value);
    return value;
  }

  Future<Map<String, Object?>> setPlanActive({
    required String organizationId,
    required String planId,
    required bool active,
  }) async {
    _organization(organizationId);
    final normalizedPlanId = requireOpaqueId(planId, 'billing plan ID');
    final current = await store.readJson('billing_plans', normalizedPlanId);
    if (current == null || current['organizationId'] != organizationId) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Billing plan was not found',
        statusCode: 404,
      );
    }
    final updated = <String, Object?>{
      ...current,
      'active': active,
      'updatedAt': _clock().toUtc().toIso8601String(),
    };
    await store.replaceJson('billing_plans', normalizedPlanId, updated);
    return updated;
  }

  Future<Map<String, Object?>> upsertSubscription({
    required String organizationId,
    required String provider,
    required String providerSubscriptionId,
    required String providerPlanId,
    required String status,
    String? planId,
    String? userId,
    String? checkoutId,
    int? totalCount,
    int? paidCount,
    int? remainingCount,
    String? currentStartAt,
    String? currentEndAt,
    bool? cancelAtCycleEnd,
    String? providerEventId,
    String? providerEventOccurredAt,
  }) async {
    _organization(organizationId);
    final normalizedProvider = _text(provider, 'billing provider', 32);
    _requireRazorpay(normalizedProvider);
    final normalizedSubscriptionId = _text(
      providerSubscriptionId,
      'provider subscription ID',
      128,
    );
    final normalizedProviderPlanId = _text(
      providerPlanId,
      'provider plan ID',
      128,
    );
    if (!_subscriptionStatuses.contains(status)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_STATUS',
        'Subscription status is unsupported',
        statusCode: 422,
      );
    }
    if (planId == null) {
      throw const ControlPlaneException(
        'INVALID_BILLING_PLAN',
        'A subscription must reference a registered billing plan',
        statusCode: 422,
      );
    }
    final normalizedPlanId = requireOpaqueId(planId, 'billing plan ID');
    final plan = await store.readJson('billing_plans', normalizedPlanId);
    if (plan == null || plan['organizationId'] != organizationId) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Billing plan was not found',
        statusCode: 404,
      );
    }
    final planKey = plan['key'];
    if (planKey is String && isSelfHostedPlanKey(planKey)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_PLAN',
        'Self-hosted is a deployment model, not a Cloud subscription plan',
        statusCode: 422,
      );
    }
    if (plan['provider'] != normalizedProvider ||
        plan['providerPlanId'] != normalizedProviderPlanId) {
      throw const ControlPlaneException(
        'BILLING_PLAN_CONFLICT',
        'Subscription provider plan does not match the registered plan',
        statusCode: 409,
      );
    }
    _optionalPositive(totalCount, 'subscription total count');
    _optionalNonNegative(paidCount, 'subscription paid count');
    _optionalNonNegative(remainingCount, 'subscription remaining count');
    _optionalTimestamp(currentStartAt, 'subscription current start');
    _optionalTimestamp(currentEndAt, 'subscription current end');
    _optionalTimestamp(providerEventOccurredAt, 'provider event time');
    if (userId != null) _text(userId, 'billing user ID', 128);

    Map<String, Object?>? checkout;
    if (checkoutId != null) {
      final normalizedCheckoutId = requireOpaqueId(
        checkoutId,
        'billing checkout ID',
      );
      checkout = await store.readJson(
        'billing_checkout_intents',
        normalizedCheckoutId,
      );
      if (checkout == null || checkout['organizationId'] != organizationId) {
        throw const ControlPlaneException(
          'NOT_FOUND',
          'Billing checkout was not found',
          statusCode: 404,
        );
      }
      if (checkout['provider'] != normalizedProvider ||
          checkout['planId'] != normalizedPlanId ||
          checkout['providerPlanId'] != normalizedProviderPlanId) {
        throw const ControlPlaneException(
          'BILLING_CHECKOUT_CONFLICT',
          'The provider subscription does not match the checkout intent',
          statusCode: 409,
        );
      }
      final linkedProviderSubscriptionId = checkout['providerSubscriptionId'];
      if (linkedProviderSubscriptionId != null &&
          linkedProviderSubscriptionId != normalizedSubscriptionId) {
        throw const ControlPlaneException(
          'BILLING_CHECKOUT_CONFLICT',
          'The checkout is already linked to another provider subscription',
          statusCode: 409,
        );
      }
    }

    final rows = await _scoped('billing_subscriptions', organizationId);
    final existing = rows.where(
      (row) =>
          row['provider'] == normalizedProvider &&
          row['providerSubscriptionId'] == normalizedSubscriptionId,
    );
    if (existing.length > 1) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'More than one subscription record matches the provider ID',
        statusCode: 500,
      );
    }
    final current = existing.isEmpty ? null : existing.first;
    if (current != null && current['organizationId'] != organizationId) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Billing subscription was not found',
        statusCode: 404,
      );
    }
    if (current != null &&
        providerEventOccurredAt != null &&
        _providerEventIsOlder(current, providerEventOccurredAt)) {
      return current;
    }
    final now = _clock().toUtc().toIso8601String();
    final value = <String, Object?>{
      'id':
          current?['id'] ??
          _subscriptionId(
            organizationId,
            normalizedProvider,
            normalizedSubscriptionId,
          ),
      'organizationId': organizationId,
      'provider': normalizedProvider,
      'providerSubscriptionId': normalizedSubscriptionId,
      'providerPlanId': normalizedProviderPlanId,
      'planId': normalizedPlanId,
      if (planKey is String && isCloudPlanKey(planKey)) 'cloudPlanKey': planKey,
      'deploymentModel': deploymentModel.wireValue,
      'billingStatus': 'provider_managed',
      'status': status,
      'userId': userId ?? current?['userId'],
      'totalCount': totalCount ?? current?['totalCount'],
      'paidCount': paidCount ?? current?['paidCount'],
      'remainingCount': remainingCount ?? current?['remainingCount'],
      'currentStartAt': currentStartAt ?? current?['currentStartAt'],
      'currentEndAt': currentEndAt ?? current?['currentEndAt'],
      'cancelAtCycleEnd':
          cancelAtCycleEnd ?? current?['cancelAtCycleEnd'] ?? false,
      'scheduledPlanChangeId': current?['scheduledPlanChangeId'],
      'scheduledPlanKey': current?['scheduledPlanKey'],
      'scheduledProviderPlanId': current?['scheduledProviderPlanId'],
      'providerScheduledAt': current?['providerScheduledAt'],
      'hasScheduledProviderChanges':
          current?['hasScheduledProviderChanges'] ?? false,
      'lastProviderEventId': providerEventId ?? current?['lastProviderEventId'],
      'lastProviderEventAt':
          providerEventOccurredAt ?? current?['lastProviderEventAt'],
      'createdAt': current?['createdAt'] ?? now,
      'updatedAt': now,
    };
    if (checkout != null) {
      final checkoutValue = <String, Object?>{
        ...checkout,
        'providerSubscriptionId': normalizedSubscriptionId,
        'updatedAt': now,
      };
      await store.replaceJson(
        'billing_checkout_intents',
        checkout['id']! as String,
        checkoutValue,
      );
    }
    final id = value['id']! as String;
    if (current == null) {
      await store.createJson('billing_subscriptions', id, value);
    } else {
      await store.replaceJson('billing_subscriptions', id, value);
    }
    return value;
  }

  /// Records an already signature-checked provider event without retaining
  /// the raw request body. Returns false when the event was already recorded
  /// with the same metadata.
  Future<bool> recordEvent({
    required String organizationId,
    required String provider,
    required String eventId,
    required String eventName,
    required String payloadDigest,
    String? providerSubscriptionId,
    String? providerPaymentId,
    String? providerRefundId,
    String? occurredAt,
  }) => _serializedProviderEvent(() async {
    _organization(organizationId);
    final normalizedProvider = _text(provider, 'billing provider', 32);
    _requireRazorpay(normalizedProvider);
    final normalizedEventId = _text(eventId, 'billing event ID', 256);
    final normalizedEventName = _text(eventName, 'billing event name', 128);
    final normalizedDigest = requireSha256Digest(payloadDigest);
    _optionalTimestamp(occurredAt, 'billing event time');
    final id =
        'bevt_${sha256Hex(utf8.encode('$organizationId:$normalizedProvider:$normalizedEventId')).substring(0, 32)}';
    final value = <String, Object?>{
      'id': id,
      'organizationId': organizationId,
      'provider': normalizedProvider,
      'eventId': normalizedEventId,
      'eventName': normalizedEventName,
      'payloadDigest': normalizedDigest,
      'providerSubscriptionId': providerSubscriptionId,
      if (providerPaymentId != null) 'providerPaymentId': providerPaymentId,
      if (providerRefundId != null) 'providerRefundId': providerRefundId,
      'occurredAt': occurredAt,
      'receivedAt': _clock().toUtc().toIso8601String(),
    };
    final existing = await store.readJson('billing_events', id);
    if (existing != null) {
      final comparable = <String, Object?>{
        ...value,
        'receivedAt': existing['receivedAt'],
      };
      if (canonicalJson(existing) != canonicalJson(comparable)) {
        throw const ControlPlaneException(
          'BILLING_EVENT_CONFLICT',
          'Billing event ID was received with different metadata',
          statusCode: 409,
        );
      }
      return false;
    }
    try {
      await store.createJson('billing_events', id, value);
      return true;
    } on StorageConflict {
      final concurrent = await store.readJson('billing_events', id);
      if (concurrent == null) rethrow;
      final comparable = <String, Object?>{
        ...value,
        'receivedAt': concurrent['receivedAt'],
      };
      if (canonicalJson(concurrent) != canonicalJson(comparable)) {
        throw const ControlPlaneException(
          'BILLING_EVENT_CONFLICT',
          'Billing event ID was received with different metadata',
          statusCode: 409,
        );
      }
      return false;
    }
  });

  Future<T> _withRefundTransaction<T>(
    String lockKey,
    Future<T> Function(BillingRefundTransaction transaction) action,
  ) {
    final transactional = store;
    if (transactional is BillingRefundTransactionStore) {
      return (transactional as BillingRefundTransactionStore)
          .runBillingRefundTransaction(lockKey, action);
    }
    return _serializedRefund(
      () => action(_StoreBillingRefundTransaction(store)),
    );
  }

  Future<T> _serializedRefund<T>(Future<T> Function() action) async {
    final previous = _refundWriteTail;
    final gate = Completer<void>();
    _refundWriteTail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  Future<List<Map<String, Object?>>> _customerPayments(
    String organizationId,
  ) async {
    final result = <Map<String, Object?>>[];
    for (final payment in await _scoped('billing_payments', organizationId)) {
      final id = payment['id'];
      if (id is! String) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Payment record has no valid ID',
          statusCode: 500,
        );
      }
      final balance = payment['status'] == 'captured'
          ? await _withRefundTransaction(
              id,
              (tx) => _refundableBalance(tx, payment),
            )
          : 0;
      result.add(_paymentProjection(payment, refundableBalance: balance));
    }
    return List.unmodifiable(result);
  }

  Future<List<Map<String, Object?>>> _customerRefundRequests(
    String organizationId,
  ) async {
    final requests = await listRefundRequests(organizationId: organizationId);
    return List.unmodifiable(requests.map(_customerRefundRequestProjection));
  }

  Future<int> _refundableBalance(
    BillingRefundTransaction tx,
    Map<String, Object?> payment,
  ) async {
    _assertCapturedPayment(payment);
    final paymentId = payment['id'];
    final organizationId = payment['organizationId'];
    final captured = payment['amountMinor'];
    if (paymentId is! String || organizationId is! String || captured is! int) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Captured payment is missing its identity or amount',
        statusCode: 500,
      );
    }
    var reserved = 0;
    final activeRequests = <String>{};
    final providerRows = await tx.listJson('billing_provider_refunds');
    for (final row in providerRows) {
      if (row['paymentId'] != paymentId ||
          row['organizationId'] != organizationId) {
        continue;
      }
      final status = row['status'];
      final amount = row['amountMinor'];
      final requestId = row['refundRequestId'];
      if (status != 'pending' && status != 'processed') continue;
      if (amount is! int || amount <= 0 || requestId is! String) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Provider refund record is malformed',
          statusCode: 500,
        );
      }
      reserved = _addRefundAmount(reserved, amount);
      activeRequests.add(requestId);
    }

    final requests = await tx.listJson('billing_refund_requests');
    final decisions = await tx.listJson('billing_refund_decisions');
    for (final decision in decisions) {
      if (decision['organizationId'] != organizationId ||
          decision['status'] != 'approved') {
        continue;
      }
      final requestId = decision['refundRequestId'];
      final amount = decision['approvedAmountMinor'];
      if (requestId is! String || amount is! int || amount <= 0) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'Refund decision is malformed',
          statusCode: 500,
        );
      }
      final request = requests.where((row) => row['id'] == requestId).toList();
      if (request.length != 1 || request.first['paymentId'] != paymentId) {
        continue;
      }
      if (activeRequests.contains(requestId)) continue;
      final attempts = providerRows.where(
        (row) => row['refundRequestId'] == requestId,
      );
      if (attempts.isNotEmpty) continue;
      reserved = _addRefundAmount(reserved, amount);
    }
    if (reserved > captured) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Refund reservations exceed the captured payment amount',
        statusCode: 500,
      );
    }
    return captured - reserved;
  }

  int _addRefundAmount(int current, int amount) {
    final next = current + amount;
    if (next > 100000000000) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Refund amount exceeds the supported range',
        statusCode: 500,
      );
    }
    return next;
  }

  void _assertCapturedPayment(Map<String, Object?> payment) {
    if (payment['provider'] != 'razorpay' ||
        payment['status'] != 'captured' ||
        payment['providerPaymentId'] is! String ||
        payment['providerPaymentId'] == null ||
        payment['amountMinor'] is! int ||
        payment['currency'] is! String) {
      throw const ControlPlaneException(
        'REFUND_PAYMENT_NOT_CAPTURED',
        'Only a captured Razorpay payment can be refunded',
        statusCode: 409,
      );
    }
    final amount = payment['amountMinor']! as int;
    _amount(amount);
    _currency(payment['currency']! as String);
  }

  void _refundAmount(int amount) {
    if (amount <= 0 || amount > 100000000000) {
      throw const ControlPlaneException(
        'INVALID_REFUND_AMOUNT',
        'Refund amount must be a positive minor-unit amount',
        statusCode: 422,
      );
    }
  }

  Future<Map<String, Object?>?> _decisionForRequest(String requestId) async =>
      _decisionForRequestWith(_StoreBillingRefundTransaction(store), requestId);

  Future<Map<String, Object?>?> _decisionForRequestWith(
    BillingRefundTransaction tx,
    String requestId,
  ) async {
    final matches = (await tx.listJson('billing_refund_decisions'))
        .where((row) => row['refundRequestId'] == requestId)
        .toList();
    if (matches.length > 1) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Refund request has multiple decisions',
        statusCode: 500,
      );
    }
    return matches.isEmpty ? null : matches.single;
  }

  Future<Map<String, Object?>?> _latestProviderRefund(String requestId) async =>
      _latestProviderRefundWith(
        _StoreBillingRefundTransaction(store),
        requestId,
      );

  Future<Map<String, Object?>?> _latestProviderRefundWith(
    BillingRefundTransaction tx,
    String requestId,
  ) async {
    final matches = (await tx.listJson('billing_provider_refunds'))
        .where((row) => row['refundRequestId'] == requestId)
        .toList();
    matches.sort(
      (left, right) => ((right['attempt'] as int?) ?? 0).compareTo(
        (left['attempt'] as int?) ?? 0,
      ),
    );
    return matches.isEmpty ? null : matches.first;
  }

  Map<String, Object?> _paymentProjection(
    Map<String, Object?> payment, {
    required int refundableBalance,
  }) => <String, Object?>{
    'id': payment['id'],
    'provider': payment['provider'],
    'amountMinor': payment['amountMinor'],
    'currency': payment['currency'],
    'status': payment['status'],
    'capturedAt': payment['capturedAt'],
    'createdAt': payment['createdAt'],
    'refundableBalanceMinor': refundableBalance,
  };

  Map<String, Object?> _refundRequestProjection(
    Map<String, Object?> request, {
    required Map<String, Object?> payment,
    Map<String, Object?>? decision,
    Map<String, Object?>? providerRefund,
  }) {
    final status = request['status'];
    if (status is! String || !_refundRequestStatuses.contains(status)) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Refund request has an unsupported status',
        statusCode: 500,
      );
    }
    return <String, Object?>{
      ...request,
      'payment': <String, Object?>{
        'id': payment['id'],
        'provider': payment['provider'],
        'providerPaymentId': payment['providerPaymentId'],
        'amountMinor': payment['amountMinor'],
        'currency': payment['currency'],
        'status': payment['status'],
        'capturedAt': payment['capturedAt'],
      },
      if (decision != null)
        'decision': <String, Object?>{
          'id': decision['id'],
          'status': decision['status'],
          'approvedAmountMinor': decision['approvedAmountMinor'],
          'currency': decision['currency'],
          'operatorId': decision['operatorId'],
          'reason': decision['reason'],
          'createdAt': decision['createdAt'],
        },
      if (providerRefund != null)
        'providerRefund': <String, Object?>{
          'id': providerRefund['id'],
          'provider': providerRefund['provider'],
          'providerRefundId': providerRefund['providerRefundId'],
          'amountMinor': providerRefund['amountMinor'],
          'currency': providerRefund['currency'],
          'status': providerRefund['status'],
          'attempt': providerRefund['attempt'],
          'errorCode': providerRefund['errorCode'],
          'createdAt': providerRefund['createdAt'],
          'updatedAt': providerRefund['updatedAt'],
        },
    };
  }

  Map<String, Object?> _customerRefundRequestProjection(
    Map<String, Object?> value,
  ) {
    final payment = value['payment'];
    final decision = value['decision'];
    final providerRefund = value['providerRefund'];
    final paymentMap = payment is Map
        ? <String, Object?>{
            'id': payment['id'],
            'amountMinor': payment['amountMinor'],
            'currency': payment['currency'],
            'status': payment['status'],
            'capturedAt': payment['capturedAt'],
          }
        : null;
    final decisionMap = decision is Map
        ? <String, Object?>{
            'status': decision['status'],
            'approvedAmountMinor': decision['approvedAmountMinor'],
            'currency': decision['currency'],
            'createdAt': decision['createdAt'],
          }
        : null;
    final providerMap = providerRefund is Map
        ? <String, Object?>{
            'status': providerRefund['status'],
            'amountMinor': providerRefund['amountMinor'],
            'currency': providerRefund['currency'],
            'createdAt': providerRefund['createdAt'],
            'updatedAt': providerRefund['updatedAt'],
          }
        : null;
    return <String, Object?>{
      'id': value['id'],
      'paymentId': value['paymentId'],
      'reasonCategory': value['reasonCategory'],
      'explanation': value['explanation'],
      'requestedAmountMinor': value['requestedAmountMinor'],
      'approvedAmountMinor': value['approvedAmountMinor'],
      'currency': value['currency'],
      'status': value['status'],
      'createdAt': value['createdAt'],
      'updatedAt': value['updatedAt'],
      if (paymentMap != null) 'payment': paymentMap,
      if (decisionMap != null) 'decision': decisionMap,
      if (providerMap != null) 'providerRefund': providerMap,
    };
  }

  Map<String, Object?> _providerRefundPreparation(
    Map<String, Object?> providerRefund,
    Map<String, Object?> payment,
    Map<String, Object?> request,
  ) => <String, Object?>{
    'organizationId': request['organizationId'],
    'refundRequestId': request['id'],
    'providerRefundRecordId': providerRefund['id'],
    'provider': providerRefund['provider'],
    'providerPaymentId': payment['providerPaymentId'],
    'amountMinor': providerRefund['amountMinor'],
    'currency': providerRefund['currency'],
    'idempotencyKey': providerRefund['idempotencyKey'],
    'status': providerRefund['status'],
    'providerRefundId': providerRefund['providerRefundId'],
  };

  String _refundRequestId(String organizationId, String idempotencyKey) =>
      'brq_${sha256Hex(utf8.encode('$organizationId:$idempotencyKey')).substring(0, 32)}';

  String _refundDecisionId(String refundRequestId) =>
      'brd_${sha256Hex(utf8.encode(refundRequestId)).substring(0, 32)}';

  String _providerRefundId(String refundRequestId, int attempt) =>
      'bpr_${sha256Hex(utf8.encode('$refundRequestId:$attempt')).substring(0, 32)}';

  String _providerRefundIdempotencyKey(String refundRequestId, int attempt) =>
      'hyfens-refund-${sha256Hex(utf8.encode('$refundRequestId:$attempt')).substring(0, 48)}';

  Future<Map<String, Object?>?> _currentCancellation(
    String organizationId,
  ) async {
    final values = (await _scoped(
      'billing_cancellations',
      organizationId,
    )).toList();
    if (values.isEmpty) return null;
    values.sort((left, right) {
      final leftAt = DateTime.tryParse('${left['updatedAt']}');
      final rightAt = DateTime.tryParse('${right['updatedAt']}');
      return (rightAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        leftAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
    return values.first;
  }

  Future<Map<String, Object?>?> _currentScheduledPlanChange(
    String organizationId,
  ) async {
    final values = (await _scoped('billing_plan_changes', organizationId))
        .where((row) {
          final status = row['status'];
          return status is String &&
              _scheduledPlanChangeStatuses.contains(status);
        })
        .toList();
    if (values.isEmpty) return null;
    values.sort(_scheduledPlanChangeComparator);
    return values.first;
  }

  Future<Map<String, Object?>?> _activeScheduledPlanChange({
    required String organizationId,
    String? subscriptionId,
    String? providerSubscriptionId,
  }) async {
    final values = (await _scoped('billing_plan_changes', organizationId))
        .where((row) {
          final status = row['status'];
          if (status is! String ||
              !_activeScheduledPlanChangeStatuses.contains(status)) {
            return false;
          }
          if (subscriptionId != null &&
              row['subscriptionId'] != subscriptionId) {
            return false;
          }
          if (providerSubscriptionId != null &&
              row['providerSubscriptionId'] != providerSubscriptionId) {
            return false;
          }
          return true;
        })
        .toList();
    if (values.isEmpty) return null;
    values.sort(_scheduledPlanChangeComparator);
    return values.first;
  }

  int _scheduledPlanChangeComparator(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    final leftRevision = left['revision'] is int ? left['revision']! as int : 0;
    final rightRevision = right['revision'] is int
        ? right['revision']! as int
        : 0;
    final byRevision = rightRevision.compareTo(leftRevision);
    if (byRevision != 0) return byRevision;
    final leftAt = DateTime.tryParse('${left['updatedAt']}');
    final rightAt = DateTime.tryParse('${right['updatedAt']}');
    return (rightAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
      leftAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Future<Map<String, Object?>> _replaceScheduledPlanChange(
    Map<String, Object?> current, {
    required String status,
    required String now,
    String? supersededBy,
  }) async {
    final id = current['id'];
    if (id is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Scheduled plan change has no valid ID',
        statusCode: 500,
      );
    }
    final updated = <String, Object?>{
      ...current,
      'status': status,
      if (supersededBy != null) 'supersededBy': supersededBy,
      'updatedAt': now,
    };
    await store.replaceJson('billing_plan_changes', id, updated);
    return updated;
  }

  Future<int> _nextScheduledPlanChangeRevision(String organizationId) async {
    var revision = 0;
    for (final row in await _scoped('billing_plan_changes', organizationId)) {
      final value = row['revision'];
      if (value is int && value > revision) revision = value;
    }
    return revision + 1;
  }

  String _scheduledPlanChangeId(
    String organizationId,
    String subscriptionId,
    int revision,
  ) =>
      'bchange_${sha256Hex(utf8.encode('$organizationId:$subscriptionId:$revision')).substring(0, 32)}';

  String _scheduledDowngradeTarget(String value) {
    final target = _text(value.trim(), 'scheduled plan target', 32);
    if (target != cloudPlanStarterKey && target != cloudPlanFreeKey) {
      throw const ControlPlaneException(
        'INVALID_PLAN_TRANSITION',
        'Only Starter and Free are available as scheduled lower plans',
        statusCode: 422,
      );
    }
    return target;
  }

  List<String> _billingActions(String? planKey) => switch (planKey) {
    cloudPlanFreeKey => <String>['upgrade_to_starter', 'upgrade_to_team'],
    cloudPlanStarterKey => <String>['upgrade_to_team', 'manage_subscription'],
    cloudPlanTeamKey => <String>['manage_subscription', 'schedule_downgrade'],
    cloudPlanEnterpriseKey => <String>['manage_enterprise'],
    _ => const <String>[],
  };

  String _paidCloudPlanKey(String value) {
    if (!isCloudPlanKey(value) ||
        (value != cloudPlanStarterKey && value != cloudPlanTeamKey)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_PLAN',
        'Only Starter and Team are available through Cloud checkout',
        statusCode: 422,
      );
    }
    return value;
  }

  RazorpayBillingConfig _requireRazorpayConfiguration() {
    final config = razorpay;
    if (config == null) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_UNAVAILABLE',
        'Razorpay billing is not configured for this Cloud deployment',
        statusCode: 503,
      );
    }
    return config;
  }

  Future<Map<String, Object?>> _ensureConfiguredProviderPlan({
    required String organizationId,
    required String planKey,
    required RazorpayBillingConfig config,
  }) async {
    final providerPlanId = config.providerPlanId(planKey);
    final current = await _scoped('billing_plans', organizationId);
    for (final plan in current) {
      if (plan['key'] == planKey &&
          plan['provider'] == 'razorpay' &&
          plan['providerPlanId'] == providerPlanId) {
        if (plan['active'] != true) {
          throw const ControlPlaneException(
            'BILLING_PLAN_UNAVAILABLE',
            'The selected Cloud plan is not currently available',
            statusCode: 409,
          );
        }
        return plan;
      }
    }
    return createPlan(
      organizationId: organizationId,
      key: planKey,
      name: planKey == cloudPlanStarterKey ? 'Starter' : 'Team',
      description: 'Hyfens Cloud $planKey',
      currency: config.currency,
      amountMinor: config.amountMinor(planKey),
      interval: 'monthly',
      period: 1,
      provider: 'razorpay',
      providerPlanId: providerPlanId,
    );
  }

  Future<Map<String, Object?>?> _findProviderMapping({
    required String providerSubscriptionId,
    String? checkoutId,
  }) async {
    final providerMapping = await store.readJson(
      'billing_provider_mappings',
      _providerMappingId(providerSubscriptionId),
    );
    if (providerMapping != null &&
        (providerMapping['provider'] != 'razorpay' ||
            providerMapping['providerSubscriptionId'] !=
                providerSubscriptionId)) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'The provider subscription mapping is invalid',
        statusCode: 500,
      );
    }
    Map<String, Object?>? subscription;
    for (final row in await store.listJson('billing_subscriptions')) {
      if (row['provider'] != 'razorpay' ||
          row['providerSubscriptionId'] != providerSubscriptionId) {
        continue;
      }
      if (subscription != null) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'A provider subscription has multiple billing records',
          statusCode: 500,
        );
      }
      subscription = row;
    }
    Map<String, Object?>? checkout;
    if (checkoutId != null) {
      checkout = await store.readJson('billing_checkout_intents', checkoutId);
      if (checkout != null && checkout['provider'] != 'razorpay') {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'The checkout provider is invalid',
          statusCode: 500,
        );
      }
    }
    Map<String, Object?>? linkedCheckout;
    for (final row in await store.listJson('billing_checkout_intents')) {
      if (row['provider'] == 'razorpay' &&
          row['providerSubscriptionId'] == providerSubscriptionId) {
        if (linkedCheckout != null) {
          throw const ControlPlaneException(
            'BILLING_STATE_CORRUPT',
            'A provider subscription is linked to multiple checkouts',
            statusCode: 500,
          );
        }
        linkedCheckout = row;
      }
    }
    if (providerMapping != null) {
      final mappedCheckoutId = providerMapping['checkoutId'];
      if (mappedCheckoutId is! String) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'The provider subscription mapping has no checkout',
          statusCode: 500,
        );
      }
      final mappedCheckout = await store.readJson(
        'billing_checkout_intents',
        mappedCheckoutId,
      );
      if (mappedCheckout == null) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'The provider subscription mapping references a missing checkout',
          statusCode: 500,
        );
      }
      if (mappedCheckout['provider'] != 'razorpay') {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'The provider subscription mapping references another provider',
          statusCode: 500,
        );
      }
      if (checkout != null && checkout['id'] != mappedCheckoutId) {
        throw const ControlPlaneException(
          'BILLING_PROVIDER_MISMATCH',
          'The provider event checkout does not match its Hyfens mapping',
          statusCode: 422,
        );
      }
      if (linkedCheckout != null && linkedCheckout['id'] != mappedCheckoutId) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'The provider subscription mapping disagrees with its checkout',
          statusCode: 500,
        );
      }
      final checkoutProviderSubscriptionId =
          mappedCheckout['providerSubscriptionId'];
      if (checkoutProviderSubscriptionId is String &&
          checkoutProviderSubscriptionId != providerSubscriptionId) {
        throw const ControlPlaneException(
          'BILLING_STATE_CORRUPT',
          'The provider subscription mapping disagrees with its checkout',
          statusCode: 500,
        );
      }
      checkout = mappedCheckout;
    } else if (checkout == null) {
      checkout = linkedCheckout;
    } else if (linkedCheckout != null &&
        linkedCheckout['id'] != checkout['id']) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'The provider event checkout does not match its Hyfens mapping',
        statusCode: 422,
      );
    }
    if (subscription == null && checkout == null && providerMapping == null) {
      return null;
    }
    final organizationId =
        subscription?['organizationId'] ??
        checkout?['organizationId'] ??
        providerMapping?['organizationId'];
    if (organizationId is! String) return null;
    if (providerMapping != null &&
        (providerMapping['organizationId'] != organizationId ||
            providerMapping['planId'] !=
                (subscription?['planId'] ?? checkout?['planId']) ||
            providerMapping['providerPlanId'] !=
                (subscription?['providerPlanId'] ??
                    checkout?['providerPlanId']))) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'The provider subscription mapping disagrees with billing state',
        statusCode: 500,
      );
    }
    if (checkout != null && checkout['organizationId'] != organizationId) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Provider subscription and checkout belong to different organizations',
        statusCode: 500,
      );
    }
    return <String, Object?>{
      'organizationId': organizationId,
      if (subscription != null) 'subscription': subscription,
      if (checkout != null) 'checkout': checkout,
    };
  }

  Future<void> _claimProviderMapping({
    required String organizationId,
    required String checkoutId,
    required String providerSubscriptionId,
    required String providerPlanId,
    required String planId,
  }) async {
    final id = _providerMappingId(providerSubscriptionId);
    final value = <String, Object?>{
      'id': id,
      'organizationId': organizationId,
      'provider': 'razorpay',
      'providerSubscriptionId': providerSubscriptionId,
      'providerPlanId': providerPlanId,
      'planId': planId,
      'checkoutId': checkoutId,
      'createdAt': _clock().toUtc().toIso8601String(),
    };
    try {
      await store.createJson('billing_provider_mappings', id, value);
    } on StorageConflict {
      final existing = await store.readJson('billing_provider_mappings', id);
      if (existing == null ||
          existing['organizationId'] != organizationId ||
          existing['provider'] != 'razorpay' ||
          existing['providerSubscriptionId'] != providerSubscriptionId ||
          existing['providerPlanId'] != providerPlanId ||
          existing['planId'] != planId ||
          existing['checkoutId'] != checkoutId) {
        throw const ControlPlaneException(
          'BILLING_PROVIDER_MAPPING_CONFLICT',
          'The provider subscription is already mapped to different billing state',
          statusCode: 409,
        );
      }
    }
  }

  Map<String, Object?> _providerSubscriptionEntity(Map<String, Object?> body) {
    final payload = _providerMap(body['payload']);
    final subscriptionPayload = _providerMap(payload?['subscription']);
    final entity = _providerMap(subscriptionPayload?['entity']);
    if (entity == null) {
      throw const ControlPlaneException(
        'INVALID_BILLING_WEBHOOK',
        'Razorpay webhook does not contain a subscription entity',
        statusCode: 422,
      );
    }
    return entity;
  }

  Map<String, Object?>? _providerPaymentEntity(Map<String, Object?> body) {
    final payload = _providerMap(body['payload']);
    final paymentPayload = _providerMap(payload?['payment']);
    return _providerMap(paymentPayload?['entity']);
  }

  Map<String, Object?>? _providerRefundEntity(Map<String, Object?> body) {
    final payload = _providerMap(body['payload']);
    final refundPayload = _providerMap(payload?['refund']);
    return _providerMap(refundPayload?['entity']);
  }

  void _validateProviderAmounts(
    Map<String, Object?> entity,
    Map<String, Object?> plan,
  ) {
    final amount = _providerInt(entity['amount']);
    if (amount != null && amount != plan['amountMinor']) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Razorpay subscription amount does not match the registered plan',
        statusCode: 422,
      );
    }
    final currency = _providerString(entity['currency']);
    if (currency != null && currency != plan['currency']) {
      throw const ControlPlaneException(
        'BILLING_PROVIDER_MISMATCH',
        'Razorpay subscription currency does not match the registered plan',
        statusCode: 422,
      );
    }
  }

  String _providerStatus(Object? eventName, Object? rawStatus) {
    final status = rawStatus is String ? rawStatus : null;
    if (status != null && _subscriptionStatuses.contains(status)) return status;
    final event = eventName is String ? eventName : '';
    return switch (event) {
      'subscription.activated' || 'subscription.charged' => 'active',
      'subscription.pending' => 'pending',
      'subscription.halted' => 'halted',
      'subscription.cancelled' => 'cancelled',
      'subscription.completed' => 'completed',
      'subscription.expired' => 'expired',
      'subscription.paused' => 'paused',
      _ => 'pending',
    };
  }

  bool _isTerminalProviderStatus(String status) =>
      status == 'cancelled' ||
      status == 'completed' ||
      status == 'expired' ||
      status == 'halted' ||
      status == 'paused' ||
      status == 'superseded';

  Future<void> _supersedeOtherProviderSubscriptions({
    required String organizationId,
    required String activeSubscriptionId,
  }) async {
    final now = _clock().toUtc().toIso8601String();
    final scheduledChanges = await _scoped(
      'billing_plan_changes',
      organizationId,
    );
    final cancellations = await _scoped(
      'billing_cancellations',
      organizationId,
    );
    for (final row in await _scoped('billing_subscriptions', organizationId)) {
      final id = row['id'];
      if (row['provider'] != 'razorpay' ||
          row['status'] != 'active' ||
          id == activeSubscriptionId ||
          id is! String) {
        continue;
      }
      for (final change in scheduledChanges) {
        if (change['subscriptionId'] != id ||
            !_activeScheduledPlanChangeStatuses.contains(change['status'])) {
          continue;
        }
        await _replaceScheduledPlanChange(
          change,
          status: 'superseded',
          supersededBy: activeSubscriptionId,
          now: now,
        );
      }
      for (final cancellation in cancellations) {
        if (cancellation['subscriptionId'] != id ||
            cancellation['status'] != 'scheduled') {
          continue;
        }
        final cancellationId = cancellation['id'];
        if (cancellationId is String) {
          await store.replaceJson(
            'billing_cancellations',
            cancellationId,
            <String, Object?>{
              ...cancellation,
              'status': 'superseded',
              'supersededBy': activeSubscriptionId,
              'updatedAt': now,
            },
          );
        }
      }
      await store.replaceJson('billing_subscriptions', id, <String, Object?>{
        ...row,
        'status': 'superseded',
        'supersededBy': activeSubscriptionId,
        'scheduledPlanChangeId': null,
        'scheduledPlanKey': null,
        'scheduledProviderPlanId': null,
        'providerScheduledAt': null,
        'hasScheduledProviderChanges': false,
        'updatedAt': now,
      });
    }
  }

  Future<Map<String, Object?>?> _markCancellationEffective({
    required String organizationId,
    required String subscriptionId,
  }) async {
    final cancellationId =
        'bcancel_${sha256Hex(utf8.encode('$organizationId:$subscriptionId')).substring(0, 32)}';
    final current = await store.readJson(
      'billing_cancellations',
      cancellationId,
    );
    if (current != null && current['status'] == 'scheduled') {
      await store.replaceJson(
        'billing_cancellations',
        cancellationId,
        <String, Object?>{
          ...current,
          'status': 'effective',
          'updatedAt': _clock().toUtc().toIso8601String(),
        },
      );
    }
    final scheduledChange = await _activeScheduledPlanChange(
      organizationId: organizationId,
      subscriptionId: subscriptionId,
    );
    if (scheduledChange == null) return null;
    if (scheduledChange['targetPlanKey'] == cloudPlanFreeKey) {
      return _markScheduledPlanChangeEffective(
        organizationId: organizationId,
        providerSubscriptionId:
            scheduledChange['providerSubscriptionId']! as String,
        effectiveAt: current?['effectiveAt'] is String
            ? current!['effectiveAt']! as String
            : null,
      );
    } else {
      await _markScheduledPlanChangeFailed(
        organizationId: organizationId,
        providerSubscriptionId:
            scheduledChange['providerSubscriptionId']! as String,
        reason:
            'The provider subscription ended before the scheduled plan change',
      );
      return null;
    }
  }

  Future<Map<String, Object?>?> _markScheduledPlanChangeEffective({
    required String organizationId,
    required String providerSubscriptionId,
    String? effectiveAt,
  }) async {
    final change = await _activeScheduledPlanChange(
      organizationId: organizationId,
      providerSubscriptionId: providerSubscriptionId,
    );
    if (change == null) return null;
    final now = _clock().toUtc().toIso8601String();
    final updatedChange = <String, Object?>{
      ...change,
      'status': 'effective',
      'effectiveAt': effectiveAt ?? change['effectiveAt'],
      'updatedAt': now,
    };
    await store.replaceJson(
      'billing_plan_changes',
      change['id']! as String,
      updatedChange,
    );
    final subscriptionId = change['subscriptionId'];
    if (subscriptionId is String) {
      final subscription = await store.readJson(
        'billing_subscriptions',
        subscriptionId,
      );
      if (subscription != null) {
        await store.replaceJson(
          'billing_subscriptions',
          subscriptionId,
          <String, Object?>{
            ...subscription,
            'scheduledPlanChangeId': null,
            'scheduledPlanKey': null,
            'scheduledProviderPlanId': null,
            'providerScheduledAt': null,
            'hasScheduledProviderChanges': false,
            'updatedAt': now,
          },
        );
        final mappingId = _providerMappingId(providerSubscriptionId);
        final mapping = await store.readJson(
          'billing_provider_mappings',
          mappingId,
        );
        if (mapping != null) {
          if (mapping['organizationId'] != organizationId ||
              mapping['providerSubscriptionId'] != providerSubscriptionId) {
            throw const ControlPlaneException(
              'BILLING_STATE_CORRUPT',
              'The provider mapping disagrees with the scheduled subscription',
              statusCode: 500,
            );
          }
          await store.replaceJson(
            'billing_provider_mappings',
            mappingId,
            <String, Object?>{
              ...mapping,
              'planId': subscription['planId'],
              'providerPlanId': subscription['providerPlanId'],
              'updatedAt': now,
            },
          );
        }
      }
    }
    return updatedChange;
  }

  Future<Map<String, Object?>> _recordScheduledPlanChangeProviderState({
    required String organizationId,
    required String providerSubscriptionId,
    required String providerStatus,
    String? providerScheduledAt,
    String? effectiveAt,
    String? providerEventId,
    String? providerEventOccurredAt,
  }) async {
    final change = await _activeScheduledPlanChange(
      organizationId: organizationId,
      providerSubscriptionId: providerSubscriptionId,
    );
    if (change == null) {
      throw const ControlPlaneException(
        'PLAN_CHANGE_NOT_PENDING',
        'No pending scheduled change matches this provider subscription',
        statusCode: 409,
      );
    }
    final now = _clock().toUtc().toIso8601String();
    final updatedChange = <String, Object?>{
      ...change,
      'status': 'scheduled',
      'providerStatus': providerStatus,
      'providerScheduledAt':
          providerScheduledAt ?? change['providerScheduledAt'],
      'effectiveAt': effectiveAt ?? change['effectiveAt'],
      'updatedAt': now,
    };
    await store.replaceJson(
      'billing_plan_changes',
      change['id']! as String,
      updatedChange,
    );
    final subscriptionId = change['subscriptionId'];
    if (subscriptionId is String) {
      final subscription = await store.readJson(
        'billing_subscriptions',
        subscriptionId,
      );
      if (subscription != null) {
        await store.replaceJson(
          'billing_subscriptions',
          subscriptionId,
          <String, Object?>{
            ...subscription,
            'scheduledPlanChangeId': change['id'],
            'scheduledPlanKey': change['targetPlanKey'],
            'scheduledProviderPlanId': change['targetProviderPlanId'],
            'providerScheduledAt':
                providerScheduledAt ?? subscription['providerScheduledAt'],
            'hasScheduledProviderChanges': true,
            'lastProviderEventId':
                providerEventId ?? subscription['lastProviderEventId'],
            'lastProviderEventAt':
                providerEventOccurredAt ?? subscription['lastProviderEventAt'],
            'updatedAt': now,
          },
        );
      }
    }
    return updatedChange;
  }

  Future<void> _markScheduledPlanChangeFailed({
    required String organizationId,
    required String providerSubscriptionId,
    required String reason,
  }) async {
    final change = await _activeScheduledPlanChange(
      organizationId: organizationId,
      providerSubscriptionId: providerSubscriptionId,
    );
    if (change == null) return;
    final id = change['id'];
    if (id is! String) return;
    await store.replaceJson('billing_plan_changes', id, <String, Object?>{
      ...change,
      'status': 'failed',
      'failureReason': reason,
      'updatedAt': _clock().toUtc().toIso8601String(),
    });
  }

  bool _providerEventIsOlder(Map<String, Object?>? current, String? incoming) {
    if (current == null || incoming == null) return false;
    final currentAt = current['lastProviderEventAt'];
    if (currentAt is! String) return false;
    final currentTime = DateTime.tryParse(currentAt);
    final incomingTime = DateTime.tryParse(incoming);
    return currentTime != null &&
        incomingTime != null &&
        incomingTime.isBefore(currentTime);
  }

  Map<String, Object?>? _providerMap(Object? value) {
    if (value is! Map) return null;
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  String _providerText(Object? value, String field, int maxLength) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maxLength ||
        value.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ControlPlaneException(
        'INVALID_BILLING_WEBHOOK',
        '$field is invalid',
        statusCode: 422,
      );
    }
    return value;
  }

  String? _providerString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  int? _providerInt(Object? value) => value is int ? value : null;

  bool? _providerBool(Object? value) => value is bool ? value : null;

  String? _providerTimestamp(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        value * 1000,
        isUtc: true,
      ).toIso8601String();
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      return parsed?.toUtc().toIso8601String();
    }
    return null;
  }

  String? _providerTimestampText(Object? value) => _providerTimestamp(value);

  void _verifyWebhookSignature(
    List<int> rawBody,
    String signature,
    String secret,
  ) {
    final normalized = signature.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_SIGNATURE',
        'Razorpay webhook signature is invalid',
        statusCode: 401,
      );
    }
    final expected = crypto.Hmac(
      crypto.sha256,
      utf8.encode(secret),
    ).convert(rawBody).toString();
    var difference = expected.length ^ normalized.length;
    for (
      var index = 0;
      index < expected.length && index < normalized.length;
      index++
    ) {
      difference |= expected.codeUnitAt(index) ^ normalized.codeUnitAt(index);
    }
    if (difference != 0) {
      throw const ControlPlaneException(
        'INVALID_BILLING_SIGNATURE',
        'Razorpay webhook signature is invalid',
        statusCode: 401,
      );
    }
  }

  Future<List<Map<String, Object?>>> _scoped(
    String collection,
    String organizationId,
  ) async {
    final values = await store.listJson(collection);
    return List.unmodifiable(
      values.where((value) => value['organizationId'] == organizationId),
    );
  }

  Future<Map<String, Object?>?> _activeProviderSubscription(
    List<Map<String, Object?>> rows,
    String organizationId,
  ) async {
    Map<String, Object?>? best;
    var bestRank = -1;
    DateTime? bestUpdatedAt;
    for (final row in rows) {
      if (row['provider'] != 'razorpay' || row['status'] != 'active') {
        continue;
      }
      if (row['deploymentModel'] == DeploymentModel.selfHosted.wireValue) {
        continue;
      }
      final registeredKey = await _registeredPlanKey(
        row,
        organizationId: organizationId,
      );
      if (registeredKey != null && isSelfHostedPlanKey(registeredKey)) {
        continue;
      }
      final knownCloudKey =
          registeredKey != null && isCloudPlanKey(registeredKey)
          ? registeredKey
          : null;
      final rank = knownCloudKey == null || knownCloudKey == cloudPlanFreeKey
          ? -1
          : cloudPlanRank(knownCloudKey);
      final updatedAt = _subscriptionTimestamp(row['updatedAt']);
      final shouldReplace =
          best == null ||
          rank > bestRank ||
          (rank == bestRank &&
              updatedAt != null &&
              (bestUpdatedAt == null || updatedAt.isAfter(bestUpdatedAt)));
      if (shouldReplace) {
        best = row;
        bestRank = rank;
        bestUpdatedAt = updatedAt;
      }
    }
    return best;
  }

  Future<String?> _cloudPlanKeyForSubscription(
    Map<String, Object?> row, {
    required String organizationId,
  }) async {
    final key = await _registeredPlanKey(row, organizationId: organizationId);
    return key != null && isCloudPlanKey(key) ? key : null;
  }

  Future<CloudPlanDefinition> _catalogDefinition(String key) async {
    final value = await store.readJson(
      'billing_plan_catalog',
      _cloudPlanId(key),
    );
    final expected = cloudPlanDefinition(key);
    final capabilities = value?['capabilities'];
    final limits = value?['limits'];
    if (value == null ||
        value['key'] != key ||
        value['deploymentModel'] != DeploymentModel.cloud.wireValue ||
        value['name'] is! String ||
        value['rank'] is! int ||
        value['rank'] != expected.rank ||
        value['paymentRequired'] is! bool ||
        value['providerBacked'] is! bool ||
        capabilities is! List<Object?> ||
        capabilities.any((item) => item is! String) ||
        limits is! Map) {
      throw const ControlPlaneException(
        'PLAN_CATALOG_INVALID',
        'The Cloud plan catalog is malformed',
        statusCode: 500,
      );
    }
    late final Map<String, CloudLimit> parsedLimits;
    try {
      final parsed = <String, CloudLimit>{};
      for (final entry in limits.entries) {
        if (entry.key is! String) {
          throw const FormatException('Cloud limit keys must be strings');
        }
        parsed[entry.key as String] = CloudLimit.fromJson(entry.value);
      }
      parsedLimits = Map.unmodifiable(parsed);
    } on FormatException {
      throw const ControlPlaneException(
        'PLAN_CATALOG_INVALID',
        'The Cloud plan catalog limits are malformed',
        statusCode: 500,
      );
    } on TypeError {
      throw const ControlPlaneException(
        'PLAN_CATALOG_INVALID',
        'The Cloud plan catalog limits are malformed',
        statusCode: 500,
      );
    }
    return CloudPlanDefinition(
      key: key,
      name: value['name']! as String,
      rank: value['rank']! as int,
      paymentRequired: value['paymentRequired']! as bool,
      providerBacked: value['providerBacked']! as bool,
      capabilities: Set.unmodifiable(capabilities.cast<String>()),
      limits: parsedLimits,
    );
  }

  Future<CloudUsageSnapshot> _cloudUsage(
    String organizationId, {
    bool includeMeasuredUsage = false,
  }) async {
    var applications = 0;
    var environments = 0;
    var members = 0;
    final environmentsPerApplication = <String, int>{};

    for (final value in await store.listJson('applications')) {
      if (value['organizationId'] == organizationId) applications++;
    }
    for (final value in await store.listJson('environments')) {
      if (value['organizationId'] != organizationId) continue;
      environments++;
      final applicationId = value['applicationId'];
      if (applicationId is String) {
        environmentsPerApplication[applicationId] =
            (environmentsPerApplication[applicationId] ?? 0) + 1;
      }
    }
    for (final value in await store.listJson('users')) {
      if (value['active'] != true) continue;
      final rawMemberships = value['memberships'];
      if (rawMemberships is! List) continue;
      final belongsToOrganization = rawMemberships.any((membership) {
        if (membership is! Map) return false;
        final audience = membership['audience'];
        return membership['organizationId'] == organizationId &&
            (audience == null || audience == 'customer');
      });
      if (belongsToOrganization) members++;
    }
    final metered = includeMeasuredUsage
        ? await usageMetering.readUsage(organizationId: organizationId)
        : null;
    return CloudUsageSnapshot(
      applications: applications,
      environments: environments,
      members: members,
      environmentsPerApplication: Map.unmodifiable(environmentsPerApplication),
      artifactStorageBytesCurrent: metered?.artifactStorageBytesCurrent,
      artifactDeliveryBytesPeriod: metered?.artifactDeliveryBytesPeriod,
      artifactDeliveryPeriodStart: metered?.period.start,
      artifactDeliveryPeriodEnd: metered?.period.end,
      artifactDeliveryAuthoritative: metered?.artifactDeliveryAuthoritative,
      artifactDeliveryAuthority: metered?.artifactDeliveryAuthority,
      artifactDeliveryQuotaEligible: metered?.artifactDeliveryQuotaEligible,
      artifactDeliverySource: metered == null
          ? null
          : artifactDeliveryOriginSource,
      artifactDeliveryCoveredSources: metered == null
          ? null
          : (metered.deliveryCoverage.coveredSources.toList()..sort()),
      artifactDeliveryUncoveredSources: metered == null
          ? null
          : (metered.deliveryCoverage.uncoveredSources.toList()..sort()),
    );
  }

  int _environmentUsage(CloudUsageSnapshot usage, String? applicationId) {
    if (applicationId == null) {
      throw const ControlPlaneException(
        'INVALID_PLAN_LIMIT',
        'An application is required for the environment limit',
        statusCode: 500,
      );
    }
    return usage.environmentsPerApplication[applicationId] ?? 0;
  }

  Future<List<Map<String, Object?>>> _cloudPlanCatalogProjection() async {
    final projections = <Map<String, Object?>>[];
    for (final definition in defaultCloudPlanCatalog) {
      projections.add((await _catalogDefinition(definition.key)).toJson());
    }
    return List.unmodifiable(projections);
  }

  Future<String?> _registeredPlanKey(
    Map<String, Object?> row, {
    required String organizationId,
  }) async {
    final persistedKey = row['cloudPlanKey'];
    if (persistedKey is String &&
        (isCloudPlanKey(persistedKey) || isSelfHostedPlanKey(persistedKey))) {
      return persistedKey;
    }
    final planId = row['planId'];
    if (planId is! String) return null;
    final plan = await store.readJson('billing_plans', planId);
    if (plan == null || plan['organizationId'] != organizationId) return null;
    final key = plan['key'];
    return key is String ? key : null;
  }

  DateTime? _subscriptionTimestamp(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  void _requireCloudDeployment() {
    if (deploymentModel != DeploymentModel.cloud) {
      throw const ControlPlaneException(
        'INVALID_DEPLOYMENT_MODEL',
        'Cloud plan assignment is unavailable for a self-hosted deployment',
        statusCode: 409,
      );
    }
  }

  String _cloudPlanId(String key) => 'cloud_plan_$key';

  Future<void> _ensureOrganizationCanStartPaidCheckout(
    String organizationId,
  ) async {
    final organization = await store.readJson('organizations', organizationId);
    final state = organization?['deletionState'];
    if (state == 'deleted') {
      throw const ControlPlaneException(
        'ORGANIZATION_DELETED',
        'This Cloud organization is no longer active',
        statusCode: 410,
      );
    }
    if (state == 'deletion_requested') {
      throw const ControlPlaneException(
        'ORGANIZATION_DELETION_PENDING',
        'Paid plan changes are unavailable while organization deletion is pending',
        statusCode: 409,
      );
    }
  }

  String _cloudFreeAssignmentId(String organizationId) =>
      'bsub_cloud_free_${sha256Hex(utf8.encode(organizationId)).substring(0, 32)}';

  Future<T> _serializedAssignment<T>(Future<T> Function() action) async {
    final previous = _assignmentWriteTail;
    final gate = Completer<void>();
    _assignmentWriteTail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  Future<T> _serializedProviderBridge<T>(Future<T> Function() action) async {
    final previous = _providerBridgeWriteTail;
    final gate = Completer<void>();
    _providerBridgeWriteTail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  Future<T> _serializedScheduledPlanChange<T>(
    Future<T> Function() action,
  ) async {
    final previous = _scheduledPlanChangeWriteTail;
    final gate = Completer<void>();
    _scheduledPlanChangeWriteTail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  Future<T> _serializedProviderEvent<T>(Future<T> Function() action) async {
    final previous = _providerEventWriteTail;
    final gate = Completer<void>();
    _providerEventWriteTail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  void _organization(String value) => requireOpaqueId(value, 'organization ID');

  void _requireRazorpay(String provider) {
    if (provider != 'razorpay') {
      throw const ControlPlaneException(
        'INVALID_BILLING_PROVIDER',
        'Only Razorpay billing is supported',
        statusCode: 422,
      );
    }
  }

  String _planId(
    String organizationId,
    String provider,
    String providerPlanId,
  ) =>
      'bpl_${sha256Hex(utf8.encode('$organizationId:$provider:$providerPlanId')).substring(0, 32)}';

  String _subscriptionId(
    String organizationId,
    String provider,
    String providerSubscriptionId,
  ) =>
      'bsub_${sha256Hex(utf8.encode('$organizationId:$provider:$providerSubscriptionId')).substring(0, 32)}';

  String _providerMappingId(String providerSubscriptionId) =>
      'bpmap_${sha256Hex(utf8.encode('razorpay:$providerSubscriptionId')).substring(0, 32)}';

  String _paymentId(String organizationId, String providerPaymentId) =>
      'bpay_${sha256Hex(utf8.encode('$organizationId:razorpay:$providerPaymentId')).substring(0, 32)}';

  String _planKey(String value) {
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{1,31}$').hasMatch(value)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_PLAN',
        'Plan key must use lowercase letters, digits, underscores, or hyphens',
        statusCode: 422,
      );
    }
    return value;
  }

  String _currency(String value) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
      throw const ControlPlaneException(
        'INVALID_BILLING_CURRENCY',
        'Currency must be a three-letter uppercase code',
        statusCode: 422,
      );
    }
    return value;
  }

  void _amount(int value) {
    if (value <= 0 || value > 100000000000) {
      throw const ControlPlaneException(
        'INVALID_BILLING_AMOUNT',
        'Billing amount is outside the supported range',
        statusCode: 422,
      );
    }
  }

  String _text(String value, String field, int maxLength) {
    if (value.isEmpty ||
        value.length > maxLength ||
        value.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ControlPlaneException(
        'INVALID_BILLING_FIELD',
        '$field is invalid',
        statusCode: 422,
      );
    }
    return value;
  }

  void _optionalPositive(int? value, String field) {
    if (value != null && (value <= 0 || value > 1000000)) {
      throw ControlPlaneException(
        'INVALID_BILLING_FIELD',
        '$field is invalid',
        statusCode: 422,
      );
    }
  }

  void _optionalNonNegative(int? value, String field) {
    if (value != null && (value < 0 || value > 1000000)) {
      throw ControlPlaneException(
        'INVALID_BILLING_FIELD',
        '$field is invalid',
        statusCode: 422,
      );
    }
  }

  void _optionalTimestamp(String? value, String field) {
    if (value == null) return;
    if (DateTime.tryParse(value) == null) {
      throw ControlPlaneException(
        'INVALID_BILLING_FIELD',
        '$field is invalid',
        statusCode: 422,
      );
    }
  }
}

final class _StoreBillingRefundTransaction implements BillingRefundTransaction {
  const _StoreBillingRefundTransaction(this.store);

  final ControlPlaneStore store;

  @override
  Future<Map<String, Object?>?> readJson(String collection, String id) =>
      store.readJson(collection, id);

  @override
  Future<List<Map<String, Object?>>> listJson(String collection) =>
      store.listJson(collection);

  @override
  Future<void> createJson(
    String collection,
    String id,
    Map<String, Object?> value,
  ) => store.createJson(collection, id, value);

  @override
  Future<void> replaceJson(
    String collection,
    String id,
    Map<String, Object?> value,
  ) => store.replaceJson(collection, id, value);

  @override
  Future<void> appendAudit(String id, Map<String, Object?> value) =>
      store.appendAudit(id, value);
}
