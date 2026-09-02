import 'dart:convert';

import 'encoding.dart';
import 'errors.dart';
import 'persistence.dart';

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
};

final class BillingSnapshot {
  const BillingSnapshot({required this.plans, required this.subscriptions});

  final List<Map<String, Object?>> plans;
  final List<Map<String, Object?>> subscriptions;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': 1,
    'plans': plans,
    'subscriptions': subscriptions,
  };
}

/// Durable billing metadata stored through the existing control-plane record
/// seam. No payment method, secret, signature, or raw webhook body is stored.
final class BillingService {
  BillingService(this.store, {DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final ControlPlaneStore store;
  final DateTime Function() _clock;

  Future<BillingSnapshot> read({required String organizationId}) async {
    _organization(organizationId);
    return BillingSnapshot(
      plans: await _scoped('billing_plans', organizationId),
      subscriptions: await _scoped('billing_subscriptions', organizationId),
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
    int? totalCount,
    int? paidCount,
    int? remainingCount,
    String? currentStartAt,
    String? currentEndAt,
    bool? cancelAtCycleEnd,
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
    if (userId != null) _text(userId, 'billing user ID', 128);

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
      'status': status,
      'userId': userId ?? current?['userId'],
      'totalCount': totalCount ?? current?['totalCount'],
      'paidCount': paidCount ?? current?['paidCount'],
      'remainingCount': remainingCount ?? current?['remainingCount'],
      'currentStartAt': currentStartAt ?? current?['currentStartAt'],
      'currentEndAt': currentEndAt ?? current?['currentEndAt'],
      'cancelAtCycleEnd':
          cancelAtCycleEnd ?? current?['cancelAtCycleEnd'] ?? false,
      'createdAt': current?['createdAt'] ?? now,
      'updatedAt': now,
    };
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
    String? occurredAt,
  }) async {
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
    await store.createJson('billing_events', id, value);
    return true;
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
