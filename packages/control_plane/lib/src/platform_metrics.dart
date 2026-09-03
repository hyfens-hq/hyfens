import 'persistence.dart';

const _activityCollections = <String, String>{
  'organizations': 'organizations',
  'users': 'users',
  'applications': 'applications',
  'environments': 'environments',
  'releases': 'releases',
  'patches': 'patches',
  'rollouts': 'rollouts',
  'auditEvents': 'audit',
  'observations': 'observations',
  'supportCases': 'support_cases',
  'billingEvents': 'billing_events',
  'organizationInvitations': 'organization_invitations',
  'platformStaffInvitations': 'platform_staff_invitations',
};

/// Read-only, aggregate account and delivery measurements for a configured
/// platform operator. This is a bounded snapshot, not a time-series or
/// revenue/fleet analytics system.
final class PlatformMetricsProjection {
  PlatformMetricsProjection({required this.store, DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final ControlPlaneStore store;
  final DateTime Function() _clock;

  Future<Map<String, Object?>> read() async {
    final now = _clock().toUtc();
    final records = <String, List<Map<String, Object?>>>{};
    for (final collection in <String>{
      ..._activityCollections.values,
      'sessions',
    }) {
      records[collection] = await store.listJson(collection);
    }

    final counts = <String, int>{
      for (final entry in _activityCollections.entries)
        entry.key: records[entry.value]!.length,
      'activeUsers': _countWhere(
        records['users']!,
        (value) => value['active'] == true,
      ),
      'activeSessions': _countWhere(
        records['sessions']!,
        (value) => _isActiveSession(value, now),
      ),
      'openSupportCases': _countWhere(
        records['support_cases']!,
        (value) => value['status'] != 'CLOSED' && value['status'] != 'RESOLVED',
      ),
      'pendingOrganizationInvitations': _countWhere(
        records['organization_invitations']!,
        (value) => _isPendingInvitation(value, now),
      ),
      'pendingPlatformStaffInvitations': _countWhere(
        records['platform_staff_invitations']!,
        (value) => _isPendingInvitation(value, now),
      ),
      'failedAuditEvents': _countWhere(records['audit']!, (value) {
        final result = '${value['result']}'.toLowerCase();
        return result == 'failure' || result == 'denied';
      }),
    };
    return <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'scope': 'platform',
      'generatedAt': now.toIso8601String(),
      'counts': counts,
      'activity': <String, Object?>{
        'last24h': _activity(records, now.subtract(const Duration(hours: 24))),
        'last30d': _activity(records, now.subtract(const Duration(days: 30))),
      },
      'operations': <String, Object?>{
        'status': 'UNKNOWN',
        'statusReason': 'This snapshot has no external dependency probes; process health is reported separately.',
        'telemetrySource': 'bounded durable control-plane records and process-local service metrics',
        'lifecycle': <String, Object?>{
          'releases': counts['releases'],
          'patches': counts['patches'],
          'deployments': _countDeployments(records['rollouts']!),
          'rollbacks': _countRollbackEvents(records['observations']!),
        },
        'support': <String, Object?>{
          'openCases': counts['openSupportCases'],
          'pendingOrganizationInvitations':
              counts['pendingOrganizationInvitations'],
        },
      },
    };
  }

  bool _isPendingInvitation(Map<String, Object?> value, DateTime now) {
    if (value['status'] == 'ACCEPTED' || value['status'] == 'REVOKED') {
      return false;
    }
    final raw = value['expiresAt'] ?? value['expires_at'];
    final expiresAt = raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
    return expiresAt?.isAfter(now) ?? false;
  }

  int _countDeployments(Iterable<Map<String, Object?>> values) =>
      values.where((value) {
        final rawState = value['state'];
        return rawState is String && rawState.toUpperCase() != 'DRAFT';
      }).length;

  int _countRollbackEvents(Iterable<Map<String, Object?>> values) =>
      values.where((value) {
        final event = value['event'];
        if (event is! Map) {
          return false;
        }
        return '${event['eventType'] ?? event['event_type']}'.toLowerCase() ==
            'rollback';
      }).length;

  Map<String, int> _activity(
    Map<String, List<Map<String, Object?>>> records,
    DateTime since,
  ) => <String, int>{
    for (final entry in _activityCollections.entries)
      entry.key: _countWhere(
        records[entry.value]!,
        (value) => _activityAt(entry.value, value)?.isAfter(since) ?? false,
      ),
  };

  DateTime? _activityAt(String collection, Map<String, Object?> value) {
    if (collection == 'observations') {
      final received = _timestamp(value['receivedAt'] ?? value['received_at']);
      if (received != null) {
        return received;
      }
      final event = value['event'];
      if (event is Map) {
        final clientTimestamp = _timestamp(
          event['clientTimestamp'] ?? event['client_timestamp'],
        );
        if (clientTimestamp != null) {
          return clientTimestamp;
        }
      }
    }
    final raw =
        value['createdAt'] ??
        value['created_at'] ??
        value['receivedAt'] ??
        value['received_at'] ??
        value['occurredAt'] ??
        value['occurred_at'];
    return _timestamp(raw);
  }

  DateTime? _timestamp(Object? raw) {
    return raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
  }

  bool _isActiveSession(Map<String, Object?> value, DateTime now) {
    if (value['revokedAt'] != null || value['revoked_at'] != null) {
      return false;
    }
    final raw = value['expiresAt'] ?? value['expires_at'];
    final expiresAt = raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
    return expiresAt?.isAfter(now) ?? false;
  }

  int _countWhere(
    Iterable<Map<String, Object?>> values,
    bool Function(Map<String, Object?> value) test,
  ) => values.where(test).length;
}
