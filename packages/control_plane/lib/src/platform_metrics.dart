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
    };
  }

  Map<String, int> _activity(
    Map<String, List<Map<String, Object?>>> records,
    DateTime since,
  ) => <String, int>{
    for (final entry in _activityCollections.entries)
      entry.key: _countWhere(
        records[entry.value]!,
        (value) => _createdAt(value)?.isAfter(since) ?? false,
      ),
  };

  DateTime? _createdAt(Map<String, Object?> value) {
    final raw = value['createdAt'] ?? value['created_at'];
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
