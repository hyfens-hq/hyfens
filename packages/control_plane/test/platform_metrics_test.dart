import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-platform-metrics-',
    );
    store = FileControlPlaneStore(directory);
    await store.initialize();
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'returns aggregate counts and rolling activity without record data',
    () async {
      final now = DateTime.utc(2026, 9, 3, 12);
      await store.createJson('organizations', 'org_metrics', <String, Object?>{
        'id': 'org_metrics',
        'name': 'Metrics organization',
        'createdAt': now.subtract(const Duration(hours: 2)).toIso8601String(),
      });
      await store.createJson('users', 'usr_metrics', <String, Object?>{
        'id': 'usr_metrics',
        'email': 'private@example.com',
        'passwordHash': 'argon2id\$private',
        'active': true,
        'createdAt': now.subtract(const Duration(days: 2)).toIso8601String(),
      });
      await store.createJson('applications', 'app_metrics', <String, Object?>{
        'id': 'app_metrics',
        'organizationId': 'org_metrics',
        'createdAt': now.subtract(const Duration(days: 40)).toIso8601String(),
      });
      await store.createJson('releases', 'rel_metrics', <String, Object?>{
        'id': 'rel_metrics',
        'createdAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
      });
      await store.createJson('sessions', 'session_metrics', <String, Object?>{
        'id': 'session_metrics',
        'secretHash': 'session-secret-hash',
        'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
      });

      final snapshot = await PlatformMetricsProjection(
        store: store,
        clock: () => now,
      ).read();
      final counts = snapshot['counts']! as Map<String, Object?>;
      final activity = snapshot['activity']! as Map<String, Object?>;
      final last24h = activity['last24h']! as Map<String, Object?>;
      final last30d = activity['last30d']! as Map<String, Object?>;

      expect(snapshot['readOnly'], isTrue);
      expect(snapshot['scope'], 'platform');
      expect(counts['organizations'], 1);
      expect(counts['users'], 1);
      expect(counts['applications'], 1);
      expect(counts['releases'], 1);
      expect(counts['activeUsers'], 1);
      expect(counts['activeSessions'], 1);
      expect(last24h['organizations'], 1);
      expect(last24h['releases'], 1);
      expect(last30d['users'], 1);
      expect(last30d['applications'], 0);

      final encoded = jsonEncode(snapshot);
      expect(encoded, isNot(contains('private@example.com')));
      expect(encoded, isNot(contains('passwordHash')));
      expect(encoded, isNot(contains('session-secret-hash')));
      expect(encoded, isNot(contains('org_metrics')));
      expect(encoded, isNot(contains('app_metrics')));
    },
  );
}
