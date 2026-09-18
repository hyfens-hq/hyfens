import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  test('shipped migration documents every executable schema object', () {
    final file = File('migrations/001_initial.sql');
    expect(file.existsSync(), isTrue);
    final sql = file.readAsStringSync();
    for (final marker in <String>[
      'control_plane_schema_migrations',
      'control_plane_records',
      'control_plane_artifacts',
      'control_plane_audit_chain',
    ]) {
      expect(sql, contains(marker));
      expect(postgresMigration001.join('\n'), contains(marker));
    }
    final observations = File('migrations/002_observations.sql');
    expect(observations.existsSync(), isTrue);
    final observationsSql = observations.readAsStringSync();
    for (final marker in <String>[
      'control_plane_observations',
      'control_plane_observations_scope_idx',
      'control_plane_observations_event_type_idx',
    ]) {
      expect(observationsSql, contains(marker));
      expect(postgresMigration002.join('\n'), contains(marker));
    }
    final p3e = File('migrations/003_p3e_persistence.sql');
    expect(p3e.existsSync(), isTrue);
    final p3eSql = p3e.readAsStringSync();
    for (final marker in <String>[
      'control_plane_p3e_aggregates',
      'control_plane_p3e_aggregate_revisions',
      'control_plane_p3e_evaluations',
      'control_plane_p3e_decisions',
      'control_plane_p3e_cursors',
    ]) {
      expect(p3eSql, contains(marker));
      expect(postgresMigration003.join('\n'), contains(marker));
    }
    final haltApplications = File('migrations/004_p3e_halt_applications.sql');
    expect(haltApplications.existsSync(), isTrue);
    final haltSql = haltApplications.readAsStringSync();
    for (final marker in <String>[
      'control_plane_p3e_halt_applications',
      'control_plane_p3e_halt_applications_decision_idx',
    ]) {
      expect(haltSql, contains(marker));
      expect(postgresMigration004.join('\n'), contains(marker));
    }
    final schedules = File('migrations/005_p3e5_schedule_work.sql');
    expect(schedules.existsSync(), isTrue);
    final scheduleSql = schedules.readAsStringSync();
    for (final marker in <String>[
      'control_plane_p3e5_schedules',
      'control_plane_p3e5_schedule_revisions',
      'control_plane_p3e5_work',
      'control_plane_p3e5_attempts',
    ]) {
      expect(scheduleSql, contains(marker));
      expect(postgresMigration005.join('\n'), contains(marker));
    }
    final claims = File('migrations/006_p3e5_claim_index.sql');
    expect(claims.existsSync(), isTrue);
    final claimSql = claims.readAsStringSync();
    for (final marker in <String>[
      'not_before',
      'lease_expires_at',
      'control_plane_p3e5_work_claim_idx',
    ]) {
      expect(claimSql, contains(marker));
      expect(postgresMigration006.join('\n'), contains(marker));
    }
    final autoHalt = File('migrations/007_p3e5_auto_halt_foundation.sql');
    expect(autoHalt.existsSync(), isTrue);
    final autoHaltSql = autoHalt.readAsStringSync();
    for (final marker in <String>[
      'control_plane_p3e5_auto_halt_policies',
      'control_plane_p3e5_auto_halt_states',
      'policy_approved',
      'production_enabled',
    ]) {
      expect(autoHaltSql, contains(marker));
      expect(postgresMigration007.join('\n'), contains(marker));
    }
    final reconciliation = File('migrations/008_reconciliation.sql');
    expect(reconciliation.existsSync(), isTrue);
    final reconciliationSql = reconciliation.readAsStringSync();
    for (final marker in <String>[
      'control_plane_reconciliation_findings',
      'control_plane_reconciliation_repairs',
      'control_plane_reconciliation_lifecycle',
      'control_plane_reconciliation_cursors',
    ]) {
      expect(reconciliationSql, contains(marker));
      expect(postgresMigration008.join('\n'), contains(marker));
    }
    expect(postgresSchemaVersion, 8);
  });
}
