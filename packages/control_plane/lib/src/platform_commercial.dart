import 'persistence.dart';

const Set<String> _recurringSubscriptionStatuses = <String>{
  'authenticated',
  'active',
};

/// Read-only commercial metrics derived from the control plane's durable
/// subscription and plan records. This projection deliberately does not call
/// a payment provider and never invents cash revenue from organization count.
final class PlatformCommercialProjection {
  PlatformCommercialProjection(this.store, {DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final ControlPlaneStore store;
  final DateTime Function() _clock;

  Future<Map<String, Object?>> read() async {
    final now = _clock().toUtc();
    final plans = <String, Map<String, Object?>>{};
    for (final value in await store.listJson('billing_plans')) {
      final id = value['id'];
      if (id is String) plans[id] = value;
    }

    final active = <Map<String, Object?>>[];
    final currencies = <String>{};
    final organizations = <String>{};
    for (final subscription in await store.listJson('billing_subscriptions')) {
      final status = subscription['status'];
      final planId = subscription['planId'];
      final organizationId = subscription['organizationId'];
      final plan = planId is String ? plans[planId] : null;
      if (status is! String ||
          !_recurringSubscriptionStatuses.contains(status) ||
          organizationId is! String ||
          plan == null ||
          plan['active'] != true ||
          plan['currency'] is! String ||
          plan['amountMinor'] is! int) {
        continue;
      }
      final currency = plan['currency']! as String;
      currencies.add(currency);
      organizations.add(organizationId);
      active.add(<String, Object?>{
        'organizationId': organizationId,
        'planId': plan['id'],
        'status': status,
        'currency': currency,
        'amountMinor': plan['amountMinor'],
      });
    }

    if (active.isEmpty) {
      return <String, Object?>{
        'schemaVersion': 1,
        'readOnly': true,
        'scope': 'platform',
        'generatedAt': now.toIso8601String(),
        'status': 'SOURCE_NOT_AVAILABLE',
        'source': 'billing_subscriptions + billing_plans',
        'currency': null,
        'mrrMinor': null,
        'arrMinor': null,
        'activeSubscriptions': 0,
        'paidOrganizations': 0,
        'historyAvailable': false,
        'cashRevenueAvailable': false,
        'note': 'Recurring commercial metrics are unavailable until an active subscription is recorded.',
      };
    }

    if (currencies.length != 1) {
      return <String, Object?>{
        'schemaVersion': 1,
        'readOnly': true,
        'scope': 'platform',
        'generatedAt': now.toIso8601String(),
        'status': 'MULTI_CURRENCY',
        'source': 'billing_subscriptions + billing_plans',
        'currency': null,
        'mrrMinor': null,
        'arrMinor': null,
        'activeSubscriptions': active.length,
        'paidOrganizations': organizations.length,
        'currencies': currencies.toList()..sort(),
        'historyAvailable': false,
        'cashRevenueAvailable': false,
        'note': 'MRR and ARR require a currency-specific view when subscriptions use multiple currencies.',
      };
    }

    final mrrMinor = active.fold<int>(
      0,
      (total, subscription) => total + (subscription['amountMinor']! as int),
    );
    return <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'scope': 'platform',
      'generatedAt': now.toIso8601String(),
      'status': 'AVAILABLE',
      'source': 'billing_subscriptions + billing_plans',
      'currency': currencies.single,
      'mrrMinor': mrrMinor,
      'arrMinor': mrrMinor * 12,
      'activeSubscriptions': active.length,
      'paidOrganizations': organizations.length,
      'historyAvailable': false,
      'cashRevenueAvailable': false,
      'note': 'MRR/ARR reflect active monthly subscription plan amounts; payment and revenue history is not recorded by this control plane.',
    };
  }
}
