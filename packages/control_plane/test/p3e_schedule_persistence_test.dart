import 'dart:io';
import 'dart:math';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 24, 19);

  test(
    'File persistence is immutable, isolated, restart safe, and guarded',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hyfens-p3e5-file-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileP3e5ScheduleStore(directory);
      await store.initialize();
      final schedule = _schedule(now);
      final revision = _revision(now);
      await store.createSchedule(schedule, revision);
      await store.createSchedule(schedule, revision);
      expect(
        FileP3e5ScheduleStore(directory).initialize(),
        throwsA(isA<StorageConflict>()),
      );
      expect(await store.readSchedule('org_1', schedule.scheduleId), isNotNull);
      expect(
        await store.readSchedule('org_other', schedule.scheduleId),
        isNull,
      );

      final work = ScheduledEvaluationWork.pending(
        logicalKey: _key(),
        serverNow: now,
      );
      await store.putWork(work);
      await store.putWork(work);
      final attempt = _attempt(work.workId, now);
      await store.putAttempt('org_1', attempt);
      await store.putAttempt('org_1', attempt);
      expect(await store.listAttempts('org_1', work.workId), hasLength(1));
      expect(
        store.putAttempt('org_1', _attempt(work.workId, now, number: 3)),
        throwsA(isA<StorageConflict>()),
      );
      expect(await store.validateConsistency('org_1'), isEmpty);
      await store.close();

      final reopened = FileP3e5ScheduleStore(directory);
      await reopened.initialize();
      addTearDown(reopened.close);
      expect(
        (await reopened.readWork('org_1', work.workId))?.workId,
        work.workId,
      );
      expect(await reopened.listAttempts('org_1', work.workId), hasLength(1));
      final next = _revision2(now.add(const Duration(minutes: 1)));
      final updated = schedule.withCurrentRevision(next.scheduleRevisionId);
      await reopened.reviseSchedule(
        schedule: updated,
        expectedCurrentRevisionId: revision.scheduleRevisionId,
        revision: next,
      );
      expect(
        await reopened.listRevisions('org_1', schedule.scheduleId),
        hasLength(2),
      );
      expect(
        reopened.reviseSchedule(
          schedule: updated,
          expectedCurrentRevisionId: revision.scheduleRevisionId,
          revision: next,
        ),
        completes,
      );
    },
  );

  test(
    'File persistence rejects immutable mutation and corrupt JSON',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hyfens-p3e5-corrupt-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileP3e5ScheduleStore(directory);
      await store.initialize();
      addTearDown(store.close);
      final schedule = _schedule(now);
      final revision = _revision(now);
      await store.createSchedule(schedule, revision);
      final changed = EvaluationScheduleRevision.fromJson(<String, Object?>{
        ...revision.toJson(),
        'reason': 'changed immutable body',
      });
      await expectLater(
        store.createSchedule(schedule, changed),
        throwsA(isA<StorageConflict>()),
      );
      final tenantHash = _hex('org_1');
      final scheduleHash = _hex(schedule.scheduleId);
      await File(
        '${directory.path}/p3e5/schedules/$tenantHash/$scheduleHash.json',
      ).writeAsString('{not-json', flush: true);
      expect(
        store.readSchedule('org_1', schedule.scheduleId),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'scheduler credential is scoped, least privilege, expiring, and revocable',
    () async {
      final issuer = CredentialService(random: Random(7));
      final issued = issuer.issue(
        id: 'credential_scheduler',
        organizationId: 'org_1',
        kind: CredentialKind.scheduler,
        scopes: evaluationOnlySchedulerScopes,
        applicationId: 'app_1',
        environmentId: 'env_1',
        expiresAt: now.add(const Duration(hours: 1)),
      );
      expect(issued.record.scopes, isNot(contains('rollout:halt')));
      expect(issued.record.scopes, isNot(contains('credential:issue')));
      Future<CredentialRecord?> reader(String hash) async =>
          hash == issued.record.tokenHash ? issued.record : null;
      expect(
        await CredentialService.authorize(
          token: issued.token,
          requiredScope: 'health:work:claim',
          read: reader,
          organizationId: 'org_1',
          applicationId: 'app_1',
          environmentId: 'env_1',
          kind: CredentialKind.scheduler,
          now: now,
        ),
        same(issued.record),
      );
      for (final future in <Future<CredentialRecord>>[
        CredentialService.authorize(
          token: issued.token,
          requiredScope: 'health:work:claim',
          read: reader,
          organizationId: 'org_1',
          applicationId: 'app_other',
          environmentId: 'env_1',
          kind: CredentialKind.scheduler,
          now: now,
        ),
        CredentialService.authorize(
          token: issued.token,
          requiredScope: 'rollout:halt',
          read: reader,
          kind: CredentialKind.scheduler,
          now: now,
        ),
        CredentialService.authorize(
          token: issued.token,
          requiredScope: 'health:work:claim',
          read: reader,
          kind: CredentialKind.scheduler,
          now: now.add(const Duration(hours: 2)),
        ),
      ]) {
        expect(future, throwsA(isA<ControlPlaneException>()));
      }
      final revoked = issued.record.copyWith(revoked: true);
      expect(
        CredentialService.authorize(
          token: issued.token,
          requiredScope: 'health:work:claim',
          read: (hash) async => hash == revoked.tokenHash ? revoked : null,
          kind: CredentialKind.scheduler,
          now: now,
        ),
        throwsA(isA<ControlPlaneException>()),
      );
      expect(
        () => issuer.issue(
          id: 'credential_invalid',
          organizationId: 'org_1',
          kind: CredentialKind.scheduler,
          scopes: const <String>{'credential:issue'},
          applicationId: 'app_1',
          environmentId: 'env_1',
        ),
        throwsA(isA<ControlPlaneException>()),
      );
      expect(
        () => CredentialRecord.fromJson(<String, Object?>{
          ...issued.record.toJson(),
          'scopes': <String>[...issued.record.scopes, 'credential:issue'],
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'service validates target, audits, revises, and materializes explicitly',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-p3e5-service-',
      );
      addTearDown(() => root.delete(recursive: true));
      final control = FileControlPlaneStore(Directory('${root.path}/control'));
      final schedules = FileP3e5ScheduleStore(
        Directory('${root.path}/schedule'),
        clock: () => now,
      );
      await control.initialize();
      final credentials = CredentialService(random: Random(11));
      final admin = credentials.issue(
        id: 'credential_admin',
        organizationId: 'org_1',
        kind: CredentialKind.control,
        scopes: controlScopes,
      );
      await control.createJson(
        'credentials',
        admin.record.tokenHash,
        admin.record.toJson(),
      );
      await _seedTenant(control, now);
      await _seedRollout(control, now);
      final controlService = ControlPlaneService(
        store: control,
        clock: () => now,
        random: Random(12),
      );
      final scheduler = await controlService.issueCredential(
        token: admin.token,
        organizationId: 'org_1',
        kind: CredentialKind.scheduler,
        scopes: evaluationOnlySchedulerScopes,
        applicationId: 'app_1',
        environmentId: 'env_1',
        expiresAt: now.add(const Duration(days: 1)),
      );
      final service = P3e5ScheduleService(
        controlStore: control,
        scheduleStore: schedules,
        clock: () => now,
        random: Random(13),
      );
      await service.initialize();
      addTearDown(schedules.close);
      final schedule = await service.createSchedule(
        token: admin.token,
        organizationId: 'org_1',
        applicationId: 'app_1',
        environmentId: 'env_1',
        rolloutId: 'rollout_1',
        rolloutRevision: 1,
        configuration: _configuration(enabled: true),
      );
      Future<ScheduledEvaluationWork> materialize() => service.materializeWork(
        token: scheduler.token,
        organizationId: 'org_1',
        applicationId: 'app_1',
        environmentId: 'env_1',
        scheduleId: schedule.scheduleId,
        scheduleRevisionId: schedule.currentScheduleRevision,
        rolloutRevision: 1,
        windowId: 'window_1',
        observationSchemaVersion: 1,
        aggregatePolicyDigest: _digest('a'),
      );
      final work = await materialize();
      expect((await materialize()).workId, work.workId);
      expect(work.status, ScheduledEvaluationWorkStatus.pending);
      expect(work.leaseOwner, isNull);
      final revised = await service.reviseSchedule(
        token: admin.token,
        organizationId: 'org_1',
        applicationId: 'app_1',
        environmentId: 'env_1',
        scheduleId: schedule.scheduleId,
        expectedCurrentRevisionId: schedule.currentScheduleRevision,
        configuration: _configuration(enabled: false),
      );
      expect(
        revised.currentScheduleRevision,
        isNot(schedule.currentScheduleRevision),
      );
      expect(
        await schedules.listRevisions('org_1', schedule.scheduleId),
        hasLength(2),
      );
      expect(
        await service.readSchedule(
          token: admin.token,
          organizationId: 'org_1',
          applicationId: 'app_other',
          environmentId: 'env_1',
          scheduleId: schedule.scheduleId,
        ),
        isNull,
      );
      final audit = await control.readAuditChain();
      expect(
        audit.map(
          (record) => (record['body']! as Map<String, Object?>)['action'],
        ),
        containsAll(<String>[
          'health.schedule_created',
          'health.work_materialized',
          'health.schedule_updated',
          'scheduler.credential_issued',
        ]),
      );
      expect(
        audit.any((record) => record.toString().contains(scheduler.token)),
        isFalse,
      );
      await controlService.revokeCredential(
        token: admin.token,
        credentialId: scheduler.record.id,
        organizationId: 'org_1',
      );
      final revokedAudit = await control.readAuditChain();
      expect(
        revokedAudit.map(
          (record) => (record['body']! as Map<String, Object?>)['action'],
        ),
        contains('scheduler.credential_revoked'),
      );
    },
  );

  final postgresUrl = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  test(
    'PostgreSQL schema v5 persists and converges across two instances',
    () async {
      final bootstrap = PostgresControlPlaneStore(postgresUrl!);
      await bootstrap.initialize();
      await bootstrap.close();
      final left = PostgresP3e5ScheduleStore(postgresUrl);
      final right = PostgresP3e5ScheduleStore(postgresUrl);
      await Future.wait(<Future<void>>[left.initialize(), right.initialize()]);
      addTearDown(left.close);
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final schedule = _schedule(now, suffix: suffix);
      final revision = _revision(now, suffix: suffix);
      await Future.wait(<Future<void>>[
        left.createSchedule(schedule, revision),
        right.createSchedule(schedule, revision),
      ]);
      final work = ScheduledEvaluationWork.pending(
        logicalKey: _key(suffix: suffix),
        serverNow: now,
      );
      await Future.wait(<Future<void>>[
        left.putWork(work),
        right.putWork(work),
      ]);
      await right.close();
      final reopened = PostgresP3e5ScheduleStore(postgresUrl);
      await reopened.initialize();
      addTearDown(reopened.close);
      expect(
        (await reopened.readWork(schedule.organizationId, work.workId))?.workId,
        work.workId,
      );
      expect(await left.validateConsistency(schedule.organizationId), isEmpty);
    },
    skip: postgresUrl == null
        ? 'PostgreSQL P3E5 integration requires HYFENS_TEST_POSTGRES_URL'
        : false,
  );
}

EvaluationSchedule _schedule(DateTime now, {String suffix = '1'}) =>
    EvaluationSchedule(
      scheduleId: 'schedule_$suffix',
      organizationId: 'org_$suffix',
      applicationId: 'app_$suffix',
      environmentId: 'env_$suffix',
      rolloutId: 'rollout_$suffix',
      currentScheduleRevision: 'schedule_revision_${suffix}_1',
      createdAt: now,
      createdBy: 'actor_1',
    );

EvaluationScheduleRevision _revision(DateTime now, {String suffix = '1'}) =>
    EvaluationScheduleRevision(
      scheduleRevisionId: 'schedule_revision_${suffix}_1',
      scheduleId: 'schedule_$suffix',
      scheduleGeneration: 1,
      organizationId: 'org_$suffix',
      applicationId: 'app_$suffix',
      environmentId: 'env_$suffix',
      rolloutId: 'rollout_$suffix',
      scheduledEvaluationEnabled: true,
      readinessPhase: EvaluationReadinessPhase.sealed,
      triggerPolicyVersion: 1,
      schedulePolicyVersion: 1,
      evaluationPolicyVersion: 1,
      evaluationPolicyDigest: _digest('e'),
      thresholdSetVersion: 1,
      thresholdSetDigest: _digest('t'),
      aggregationVersion: 1,
      windowPolicyVersion: 1,
      privacyPolicyVersion: 1,
      retryPolicyReference: 'retry_v1',
      resourcePolicyReference: 'resource_v1',
      supersedesScheduleRevisionId: null,
      createdAt: now,
      createdBy: 'actor_1',
      reason: 'TEST VECTOR ONLY',
    );

EvaluationScheduleRevision _revision2(DateTime now) =>
    EvaluationScheduleRevision(
      scheduleRevisionId: 'schedule_revision_1_2',
      scheduleId: 'schedule_1',
      scheduleGeneration: 2,
      organizationId: 'org_1',
      applicationId: 'app_1',
      environmentId: 'env_1',
      rolloutId: 'rollout_1',
      readinessPhase: EvaluationReadinessPhase.closed,
      triggerPolicyVersion: 1,
      schedulePolicyVersion: 1,
      evaluationPolicyVersion: 1,
      evaluationPolicyDigest: _digest('e'),
      thresholdSetVersion: 1,
      thresholdSetDigest: _digest('t'),
      aggregationVersion: 1,
      windowPolicyVersion: 1,
      privacyPolicyVersion: 1,
      retryPolicyReference: 'retry_v1',
      resourcePolicyReference: 'resource_v1',
      supersedesScheduleRevisionId: 'schedule_revision_1_1',
      createdAt: now,
      createdBy: 'actor_1',
      reason: 'TEST VECTOR ONLY',
    );

LogicalEvaluationKey _key({String suffix = '1'}) => LogicalEvaluationKey(
  organizationId: 'org_$suffix',
  applicationId: 'app_$suffix',
  environmentId: 'env_$suffix',
  platformId: 'platform_$suffix',
  rolloutId: 'rollout_$suffix',
  rolloutRevision: 1,
  releaseId: 'release_$suffix',
  patchId: 'patch_$suffix',
  sequence: 1,
  targetBindingDigest: _digest('b'),
  windowId: 'window_$suffix',
  readinessPhase: EvaluationReadinessPhase.sealed,
  observationSchemaVersion: 1,
  aggregationVersion: 1,
  aggregatePolicyDigest: _digest('a'),
  evaluationPolicyVersion: 1,
  evaluationPolicyDigest: _digest('e'),
  thresholdSetVersion: 1,
  thresholdSetDigest: _digest('t'),
  windowPolicyVersion: 1,
  privacyPolicyVersion: 1,
  scheduleId: 'schedule_$suffix',
  scheduleRevisionId: 'schedule_revision_${suffix}_1',
  scheduleGeneration: 1,
);

ScheduledEvaluationAttempt _attempt(
  String workId,
  DateTime now, {
  int number = 1,
}) => ScheduledEvaluationAttempt(
  attemptId: deriveAttemptId(workId, number),
  workId: workId,
  attemptNumber: number,
  leaseOwner: 'test_worker',
  leaseTokenDigest: _digest('l'),
  startedAt: now,
  finishedAt: now,
  outcome: 'TEST_ONLY',
  errorClass: null,
  safeErrorCode: null,
  evaluationId: null,
  decisionId: null,
  haltApplicationId: null,
  actorIdentity: 'scheduler_1',
);

ScheduleRevisionConfiguration _configuration({required bool enabled}) =>
    ScheduleRevisionConfiguration(
      scheduledEvaluationEnabled: enabled,
      readinessPhase: EvaluationReadinessPhase.sealed,
      evaluationPolicyDigest: _digest('e'),
      thresholdSetDigest: _digest('t'),
      retryPolicyReference: 'retry_v1',
      resourcePolicyReference: 'resource_v1',
      reason: 'TEST VECTOR ONLY',
    );

Future<void> _seedRollout(FileControlPlaneStore store, DateTime now) async {
  final target = RolloutTarget(
    organizationId: 'org_1',
    applicationId: 'app_1',
    environmentId: 'env_1',
    platformId: 'platform_1',
    releaseId: 'release_1',
    runtimeReleaseId: 'runtime-release-1',
    patchId: 'patch_1',
    runtimePatchId: 'runtime-patch-1',
    artifactId: 'artifact_1',
    sha256: _digest('f'),
    sequence: 1,
  );
  final rollout = RolloutRecord(
    id: 'rollout_1',
    organizationId: 'org_1',
    currentRevision: 1,
    state: RolloutState.canary,
    createdAt: now,
  );
  final revision = RolloutRevision(
    id: 'rollout_revision_1',
    rolloutId: rollout.id,
    organizationId: rollout.organizationId,
    revision: 1,
    previousRevision: null,
    state: rollout.state,
    target: target,
    policy: RolloutPolicy(
      cohortKind: RolloutCohortKind.percentage,
      percentageBasisPoints: 100,
      salt: 'TEST_ONLY',
    ),
    actorId: 'actor_1',
    reason: 'TEST VECTOR ONLY',
    pausedFromState: null,
    createdAt: now,
  );
  await store.createJson('rollouts', rollout.id, rollout.toJson());
  await store.createJson('rollout_revisions', revision.id, revision.toJson());
}

Future<void> _seedTenant(FileControlPlaneStore store, DateTime now) async {
  final organization = OrganizationRecord(
    id: 'org_1',
    name: 'P3E5 test organization',
    createdAt: now,
  );
  final application = ApplicationRecord(
    id: 'app_1',
    organizationId: organization.id,
    runtimeApplicationId: 'runtime-app-1',
    createdAt: now,
  );
  final environment = EnvironmentRecord(
    id: 'env_1',
    organizationId: organization.id,
    applicationId: application.id,
    name: 'test',
    version: 0,
    promotedReleaseId: null,
    createdAt: now,
  );
  await store.createJson(
    'organizations',
    organization.id,
    organization.toJson(),
  );
  await store.createJson('applications', application.id, application.toJson());
  await store.createJson('environments', environment.id, environment.toJson());
}

String _digest(String value) => sha256Digest(value.codeUnits);

String _hex(String value) => sha256Digest(value.codeUnits).substring(7);
