import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  const testPolicyMarker = 'TEST VECTOR ONLY — NOT PRODUCTION POLICY';
  final now = DateTime.utc(2026, 8, 24, 20);

  group('P3E5-4A automatic-halt policy', () {
    test('canonical policy digest is strict, deterministic, and semantic', () {
      final policy = _policy(now);
      final decoded = AutomaticHaltPolicy.fromJson(policy.toJson());
      expect(decoded.canonicalSerialization, policy.canonicalSerialization);
      expect(decoded.digest, policy.digest);
      expect(
        _policy(now.add(const Duration(minutes: 1))).digest,
        policy.digest,
      );
      expect(
        _policy(now, maximumDecisionAge: const Duration(minutes: 11)).digest,
        isNot(policy.digest),
      );
      expect(policy.resourcePolicyReference, contains(testPolicyMarker));
    });

    test(
      'unknown versions, missing approval, and digest mutation fail closed',
      () {
        final policy = _policy(now);
        expect(
          () => AutomaticHaltPolicy.fromJson(<String, Object?>{
            ...policy.toJson(),
            'automaticHaltPolicyVersion': 2,
          }),
          throwsFormatException,
        );
        expect(
          () => AutomaticHaltPolicy.fromJson(<String, Object?>{
            ...policy.toJson(),
            'approvalReference': '',
          }),
          throwsFormatException,
        );
        expect(
          () => AutomaticHaltPolicy.fromJson(<String, Object?>{
            ...policy.toJson(),
            'automaticHaltPolicyDigest': _digest('wrong'),
          }),
          throwsFormatException,
        );
      },
    );

    test('approval and production enablement are separate and default off', () {
      final policy = _policy(now);
      final state = AutomaticHaltEnvironmentState.foundation(
        stateId: 'auto_halt_state_1',
        policy: policy,
        createdAt: now,
        createdBy: 'actor_1',
      );
      expect(state.policyApproved, isFalse);
      expect(state.productionEnabled, isFalse);
      expect(state.productionEnableReference, isNull);
      expect(
        AutomaticHaltEnvironmentState.fromJson(state.toJson())
            .canonicalSerialization,
        state.canonicalSerialization,
      );
      expect(
        () => AutomaticHaltEnvironmentState.fromJson(<String, Object?>{
          ...state.toJson(),
          'unexpected': true,
        }),
        throwsFormatException,
      );
      expect(
        () => AutomaticHaltEnvironmentState(
          stateId: 'auto_halt_state_invalid',
          organizationId: 'org_1',
          applicationId: 'app_1',
          environmentId: 'env_1',
          generation: 1,
          supersedesStateId: null,
          policyId: policy.policyId,
          automaticHaltPolicyDigest: policy.digest,
          policyApproved: false,
          productionEnabled: true,
          productionEnableReference: 'approval_prod_1',
          createdAt: now,
          createdBy: 'actor_1',
        ),
        throwsFormatException,
      );
    });
  });

  group('P3E5-4A logical work meaning', () {
    test('historical v1 is ineligible and v2 binds exact policy semantics', () {
      final policy = _policy(now);
      final historical = _logicalKey();
      final eligible = _logicalKey(
        logicalKeyVersion: 2,
        automaticHaltPolicyId: policy.policyId,
        automaticHaltPolicyVersion: policy.automaticHaltPolicyVersion,
        automaticHaltPolicyDigest: policy.digest,
        automaticHaltEnabled: true,
        eligibleSource: AutomaticHaltEligibleSource.scheduledOnly,
        eligibleReadiness: AutomaticHaltEligibleReadiness.sealedOnly,
        eligibleReasonClass: AutomaticHaltEligibleReasonClass.patchSafetyOnly,
      );
      expect(historical.isAutomaticHaltFoundationCandidate, isFalse);
      expect(eligible.isAutomaticHaltFoundationCandidate, isTrue);
      expect(eligible.workId, isNot(historical.workId));
      expect(
        LogicalEvaluationKey.fromJson(eligible.toJson()).workId,
        eligible.workId,
      );
      expect(
        eligible.evaluationIdempotencyKey,
        'scheduled-evaluation:${eligible.workId}',
      );
      expect(
        _logicalKey(
          logicalKeyVersion: 2,
          automaticHaltPolicyId: policy.policyId,
          automaticHaltPolicyVersion: policy.automaticHaltPolicyVersion,
          automaticHaltPolicyDigest: _digest('changed-policy'),
          automaticHaltEnabled: true,
          eligibleSource: AutomaticHaltEligibleSource.scheduledOnly,
          eligibleReadiness: AutomaticHaltEligibleReadiness.sealedOnly,
          eligibleReasonClass: AutomaticHaltEligibleReasonClass.patchSafetyOnly,
        ).workId,
        isNot(eligible.workId),
      );
    });

    test(
      'v2 rejects missing policy, CLOSED readiness, and future versions',
      () {
        final policy = _policy(now);
        expect(() => _logicalKey(logicalKeyVersion: 2), throwsFormatException);
        expect(
          () => _logicalKey(
            logicalKeyVersion: 2,
            readinessPhase: EvaluationReadinessPhase.closed,
            automaticHaltPolicyId: policy.policyId,
            automaticHaltPolicyVersion: 1,
            automaticHaltPolicyDigest: policy.digest,
            automaticHaltEnabled: true,
            eligibleSource: AutomaticHaltEligibleSource.scheduledOnly,
            eligibleReadiness: AutomaticHaltEligibleReadiness.sealedOnly,
            eligibleReasonClass:
                AutomaticHaltEligibleReasonClass.patchSafetyOnly,
          ),
          throwsFormatException,
        );
        expect(() => _logicalKey(logicalKeyVersion: 3), throwsFormatException);
      },
    );

    test('schedule revision v2 and work bind the same policy semantics', () {
      final policy = _policy(now);
      final revision = _revisionV2(now, policy: policy);
      final key = _logicalKey(
        logicalKeyVersion: 2,
        automaticHaltPolicyId: policy.policyId,
        automaticHaltPolicyVersion: policy.automaticHaltPolicyVersion,
        automaticHaltPolicyDigest: policy.digest,
        automaticHaltEnabled: false,
        eligibleSource: AutomaticHaltEligibleSource.scheduledOnly,
        eligibleReadiness: AutomaticHaltEligibleReadiness.sealedOnly,
        eligibleReasonClass: AutomaticHaltEligibleReasonClass.patchSafetyOnly,
      );
      final work = ScheduledEvaluationWork.pending(
        logicalKey: key,
        serverNow: now,
      );
      validateWorkBinding(work, _schedule(now), revision);
      expect(key.isAutomaticHaltFoundationCandidate, isFalse);
      expect(
        EvaluationScheduleRevision.fromJson(revision.toJson())
            .canonicalSerialization,
        revision.canonicalSerialization,
      );
      expect(
        () => EvaluationScheduleRevision.fromJson(<String, Object?>{
          ...revision.toJson(),
          'automaticHaltPolicyDigest': _digest('changed'),
        }),
        returnsNormally,
      );
      expect(
        () => validateWorkBinding(
          work,
          _schedule(now),
          EvaluationScheduleRevision.fromJson(<String, Object?>{
            ...revision.toJson(),
            'automaticHaltPolicyDigest': _digest('changed'),
          }),
        ),
        throwsFormatException,
      );
    });

    test('legacy v1 stays ineligible even when its schedule flag was true', () {
      final key = _logicalKey();
      final work = ScheduledEvaluationWork.pending(
        logicalKey: key,
        serverNow: now,
      );
      validateWorkBinding(work, _schedule(now), _legacyRevision(now));
      expect(key.logicalKeyVersion, 1);
      expect(key.isAutomaticHaltFoundationCandidate, isFalse);
    });
  });

  group('P3E5-4A Auto-Halt Principal', () {
    test(
      'principal is exact-scope and cannot claim, evaluate, or schedule',
      () async {
        final credentials = CredentialService(random: Random(63));
        final issued = credentials.issue(
          id: 'credential_auto_halt',
          organizationId: 'org_1',
          kind: CredentialKind.autoHalt,
          scopes: autoHaltScopes,
          applicationId: 'app_1',
          environmentId: 'env_1',
          expiresAt: now.add(const Duration(hours: 1)),
        );
        expect(issued.record.scopes, autoHaltScopes);
        for (final forbidden in const <String>{
          'health:work:claim',
          'health:evaluate',
          'observation:read',
          'observation:write',
          'health:schedule',
          'rollout:promote',
          'credential:issue',
        }) {
          expect(issued.record.scopes, isNot(contains(forbidden)));
        }
        expect(
          () => credentials.issue(
            id: 'credential_auto_halt_incomplete',
            organizationId: 'org_1',
            kind: CredentialKind.autoHalt,
            scopes: const <String>{'rollout:halt'},
            applicationId: 'app_1',
            environmentId: 'env_1',
          ),
          throwsA(isA<ControlPlaneException>()),
        );
        Future<CredentialRecord?> read(String hash) async =>
            hash == issued.record.tokenHash ? issued.record : null;
        expect(
          await CredentialService.authorize(
            token: issued.token,
            requiredScope: 'health:work:apply-halt',
            read: read,
            organizationId: 'org_1',
            applicationId: 'app_1',
            environmentId: 'env_1',
            kind: CredentialKind.autoHalt,
            now: now,
          ),
          same(issued.record),
        );
        for (final scope in const <String>{
          'health:work:claim',
          'health:evaluate',
          'health:schedule',
        }) {
          expect(
            CredentialService.authorize(
              token: issued.token,
              requiredScope: scope,
              read: read,
              kind: CredentialKind.autoHalt,
              now: now,
            ),
            throwsA(isA<ControlPlaneException>()),
          );
        }
        for (final request in <Future<CredentialRecord>>[
          CredentialService.authorize(
            token: issued.token,
            requiredScope: 'health:work:apply-halt',
            read: read,
            organizationId: 'org_1',
            applicationId: 'app_other',
            environmentId: 'env_1',
            kind: CredentialKind.autoHalt,
            now: now,
          ),
          CredentialService.authorize(
            token: issued.token,
            requiredScope: 'health:work:apply-halt',
            read: read,
            kind: CredentialKind.autoHalt,
            now: now.add(const Duration(hours: 2)),
          ),
          CredentialService.authorize(
            token: issued.token,
            requiredScope: 'health:work:apply-halt',
            read: (hash) async => hash == issued.record.tokenHash
                ? issued.record.copyWith(revoked: true)
                : null,
            kind: CredentialKind.autoHalt,
            now: now,
          ),
        ]) {
          expect(request, throwsA(isA<ControlPlaneException>()));
        }
      },
    );

    test('scheduler and broad control credentials cannot substitute', () {
      final credentials = CredentialService(random: Random(64));
      expect(
        () => credentials.issue(
          id: 'credential_scheduler_halt',
          organizationId: 'org_1',
          kind: CredentialKind.scheduler,
          scopes: const <String>{
            'health:work:claim',
            'health:evaluate',
            'observation:read',
            'rollout:read',
            'rollout:halt',
          },
          applicationId: 'app_1',
          environmentId: 'env_1',
        ),
        throwsA(isA<ControlPlaneException>()),
      );
      final control = credentials.issue(
        id: 'credential_control',
        organizationId: 'org_1',
        kind: CredentialKind.control,
        scopes: const <String>{'rollout:read', 'rollout:halt'},
      );
      expect(
        () => AutomaticHaltAuthority(
          lease: _lease(),
          principal: control.record,
          authoritativeNow: now,
        ),
        throwsFormatException,
      );
    });

    test('two-authority proof binds the exact lease and principal scope', () {
      final issued = CredentialService(random: Random(65)).issue(
        id: 'credential_auto_halt',
        organizationId: 'org_1',
        kind: CredentialKind.autoHalt,
        scopes: autoHaltScopes,
        applicationId: 'app_1',
        environmentId: 'env_1',
        expiresAt: now.add(const Duration(hours: 1)),
      );
      final authority = AutomaticHaltAuthority(
        lease: _lease(),
        principal: issued.record,
        authoritativeNow: now,
      );
      expect(authority.workId, 'work_1');
      expect(authority.principalId, issued.record.id);
      expect(
        () => AutomaticHaltAuthority(
          lease: P3e5LeaseMutation(
            scope: const P3e5ClaimScope(
              organizationId: 'org_1',
              applicationId: 'app_other',
              environmentId: 'env_1',
            ),
            workId: 'work_1',
            expectedWorkVersion: 2,
            leaseOwner: 'executor_1',
            rawLeaseToken: _leaseToken,
          ),
          principal: issued.record,
          authoritativeNow: now,
        ),
        throwsFormatException,
      );
    });
  });

  group('P3E5-4A policy persistence', () {
    test(
      'File store is immutable, tenant isolated, and restart durable',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'hyfens-p3e5-auto-halt-',
        );
        addTearDown(() => root.delete(recursive: true));
        final policy = _policy(now);
        final state = AutomaticHaltEnvironmentState.foundation(
          stateId: 'auto_halt_state_1',
          policy: policy,
          createdAt: now,
          createdBy: 'actor_1',
        );
        final store = FileP3e5ScheduleStore(root);
        await store.initialize();
        await store.putAutomaticHaltFoundation(policy, state);
        await store.putAutomaticHaltFoundation(policy, state);
        expect(
          (await store.readAutomaticHaltPolicy(
            'org_1',
            policy.policyId,
          ))?.digest,
          policy.digest,
        );
        expect(
          await store.readAutomaticHaltPolicy('org_other', policy.policyId),
          isNull,
        );
        expect(
          (await store.readCurrentAutomaticHaltState(
            'org_1',
            'app_1',
            'env_1',
          ))?.stateId,
          state.stateId,
        );
        await store.close();

        final reopened = FileP3e5ScheduleStore(root);
        await reopened.initialize();
        addTearDown(reopened.close);
        expect(await reopened.listAutomaticHaltPolicies('org_1'), hasLength(1));
        expect(
          reopened.putAutomaticHaltFoundation(
            _policy(now, maximumDecisionAge: const Duration(minutes: 11)),
            state,
          ),
          throwsA(isA<StorageConflict>()),
        );
        expect(
          reopened.putAutomaticHaltFoundation(
            policy,
            AutomaticHaltEnvironmentState.foundation(
              stateId: 'auto_halt_state_foreign',
              policy: _policy(
                now,
                organizationId: 'org_other',
                policyId: 'auto_halt_policy_foreign',
              ),
              createdAt: now,
              createdBy: 'actor_1',
            ),
          ),
          throwsA(isA<StorageConflict>()),
        );
      },
    );

    test('File store rejects malformed bundle content', () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-p3e5-auto-halt-corrupt-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = FileP3e5ScheduleStore(root);
      await store.initialize();
      addTearDown(store.close);
      final policy = _policy(now);
      await store.putAutomaticHaltFoundation(
        policy,
        AutomaticHaltEnvironmentState.foundation(
          stateId: 'auto_halt_state_1',
          policy: policy,
          createdAt: now,
          createdBy: 'actor_1',
        ),
      );
      final bundle =
          (await Directory('${root.path}/p3e5/auto_halt')
                  .list(recursive: true, followLinks: false)
                  .where(
                    (entity) => entity is File && entity.path.endsWith('.json'),
                  )
                  .cast<File>()
                  .toList())
              .single;
      final decoded = (jsonDecode(await bundle.readAsString()) as Map)
          .cast<String, Object?>();
      await bundle.writeAsString(
        jsonEncode(<String, Object?>{...decoded, 'unexpected': true}),
        flush: true,
      );
      expect(store.listAutomaticHaltPolicies('org_1'), throwsFormatException);
    });

    final postgresUrl = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
    test(
      'PostgreSQL migration and two-instance immutable race converge',
      () async {
        final bootstrapLeft = PostgresControlPlaneStore(postgresUrl!);
        final bootstrapRight = PostgresControlPlaneStore(postgresUrl);
        await Future.wait(<Future<void>>[
          bootstrapLeft.initialize(),
          bootstrapRight.initialize(),
        ]);
        await Future.wait(<Future<void>>[
          bootstrapLeft.close(),
          bootstrapRight.close(),
        ]);
        final left = PostgresP3e5ScheduleStore(postgresUrl);
        final right = PostgresP3e5ScheduleStore(postgresUrl);
        await Future.wait(<Future<void>>[
          left.initialize(),
          right.initialize(),
        ]);
        addTearDown(left.close);
        final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
        final organizationId = 'org_$suffix';
        final applicationId = 'app_$suffix';
        final environmentId = 'env_$suffix';
        final policy = _policy(
          now,
          policyId: 'auto_halt_policy_$suffix',
          organizationId: organizationId,
          applicationId: applicationId,
          environmentId: environmentId,
        );
        final state = AutomaticHaltEnvironmentState.foundation(
          stateId: 'auto_halt_state_$suffix',
          policy: policy,
          createdAt: now,
          createdBy: 'actor_1',
        );
        await Future.wait(<Future<void>>[
          left.putAutomaticHaltFoundation(policy, state),
          right.putAutomaticHaltFoundation(policy, state),
        ]);
        await right.close();
        final reopened = PostgresP3e5ScheduleStore(postgresUrl);
        await reopened.initialize();
        addTearDown(reopened.close);
        expect(
          (await reopened.readAutomaticHaltPolicy(
            organizationId,
            policy.policyId,
          ))?.digest,
          policy.digest,
        );
        expect(
          (await reopened.readCurrentAutomaticHaltState(
            organizationId,
            applicationId,
            environmentId,
          ))?.stateId,
          state.stateId,
        );
      },
      skip: postgresUrl == null
          ? 'HYFENS_TEST_POSTGRES_URL is not configured'
          : false,
    );
  });

  group('P3E5-4A administration', () {
    test(
      'service registers default-off policy and audits narrow principal',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'hyfens-p3e5-auto-halt-service-',
        );
        addTearDown(() => root.delete(recursive: true));
        final control = FileControlPlaneStore(
          Directory('${root.path}/control'),
        );
        final schedules = FileP3e5ScheduleStore(
          Directory('${root.path}/schedules'),
          clock: () => now,
        );
        await control.initialize();
        final admin = CredentialService(random: Random(66)).issue(
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
        await _seedApplicationEnvironment(control, now);
        await _seedRollout(control, now);
        final service = P3e5ScheduleService(
          controlStore: control,
          scheduleStore: schedules,
          clock: () => now,
          random: Random(67),
        );
        await service.initialize();
        addTearDown(schedules.close);
        final policy = await service.registerAutomaticHaltPolicy(
          token: admin.token,
          organizationId: 'org_1',
          applicationId: 'app_1',
          environmentId: 'env_1',
          configuration: const AutomaticHaltPolicyConfiguration(
            maximumAggregateAgeFromLateCutoff: Duration(minutes: 20),
            maximumDecisionAgeFromEvaluation: Duration(minutes: 10),
            resourcePolicyReference:
                'resource_test_vector_TEST VECTOR ONLY — NOT PRODUCTION POLICY',
            approvalReference: 'approval_pending_1',
          ),
        );
        final state = await schedules.readCurrentAutomaticHaltState(
          'org_1',
          'app_1',
          'env_1',
        );
        expect(state?.policyId, policy.policyId);
        expect(state?.policyApproved, isFalse);
        expect(state?.productionEnabled, isFalse);
        expect(
          await service.readAutomaticHaltPolicy(
            token: admin.token,
            organizationId: 'org_1',
            applicationId: 'app_other',
            environmentId: 'env_1',
            policyId: policy.policyId,
          ),
          isNull,
        );

        final controlService = ControlPlaneService(
          store: control,
          clock: () => now,
          random: Random(68),
        );
        final principal = await controlService.issueCredential(
          token: admin.token,
          organizationId: 'org_1',
          kind: CredentialKind.autoHalt,
          scopes: autoHaltScopes,
          applicationId: 'app_1',
          environmentId: 'env_1',
          expiresAt: now.add(const Duration(hours: 1)),
        );
        final scheduler = await controlService.issueCredential(
          token: admin.token,
          organizationId: 'org_1',
          kind: CredentialKind.scheduler,
          scopes: evaluationOnlySchedulerScopes,
          applicationId: 'app_1',
          environmentId: 'env_1',
          expiresAt: now.add(const Duration(hours: 1)),
        );
        final schedule = await service.createSchedule(
          token: admin.token,
          organizationId: 'org_1',
          applicationId: 'app_1',
          environmentId: 'env_1',
          rolloutId: 'rollout_1',
          rolloutRevision: 1,
          configuration: _scheduleConfigurationV2(policy),
        );
        final work = await service.materializeWork(
          token: scheduler.token,
          organizationId: 'org_1',
          applicationId: 'app_1',
          environmentId: 'env_1',
          scheduleId: schedule.scheduleId,
          scheduleRevisionId: schedule.currentScheduleRevision,
          rolloutRevision: 1,
          windowId: 'window_1',
          observationSchemaVersion: 1,
          aggregatePolicyDigest: _digest('aggregate'),
        );
        expect(work.logicalKey.logicalKeyVersion, 2);
        expect(work.logicalKey.automaticHaltPolicyId, policy.policyId);
        expect(work.logicalKey.isAutomaticHaltFoundationCandidate, isTrue);
        final replacement = await service.registerAutomaticHaltPolicy(
          token: admin.token,
          organizationId: 'org_1',
          applicationId: 'app_1',
          environmentId: 'env_1',
          configuration: const AutomaticHaltPolicyConfiguration(
            maximumAggregateAgeFromLateCutoff: Duration(minutes: 21),
            maximumDecisionAgeFromEvaluation: Duration(minutes: 10),
            resourcePolicyReference:
                'resource_test_vector_TEST VECTOR ONLY — NOT PRODUCTION POLICY',
            approvalReference: 'approval_pending_2',
          ),
        );
        expect(
          service.reviseSchedule(
            token: admin.token,
            organizationId: 'org_1',
            applicationId: 'app_1',
            environmentId: 'env_1',
            scheduleId: schedule.scheduleId,
            expectedCurrentRevisionId: schedule.currentScheduleRevision,
            configuration: _scheduleConfigurationV2(policy),
          ),
          throwsA(
            isA<ControlPlaneException>().having(
              (error) => error.code,
              'code',
              'HEALTH_AUTO_HALT_POLICY_STALE',
            ),
          ),
        );
        final revised = await service.reviseSchedule(
          token: admin.token,
          organizationId: 'org_1',
          applicationId: 'app_1',
          environmentId: 'env_1',
          scheduleId: schedule.scheduleId,
          expectedCurrentRevisionId: schedule.currentScheduleRevision,
          configuration: _scheduleConfigurationV2(replacement),
        );
        final replacementWork = await service.materializeWork(
          token: scheduler.token,
          organizationId: 'org_1',
          applicationId: 'app_1',
          environmentId: 'env_1',
          scheduleId: revised.scheduleId,
          scheduleRevisionId: revised.currentScheduleRevision,
          rolloutRevision: 1,
          windowId: 'window_1',
          observationSchemaVersion: 1,
          aggregatePolicyDigest: _digest('aggregate'),
        );
        expect(replacementWork.workId, isNot(work.workId));
        expect(
          replacementWork.logicalKey.automaticHaltPolicyId,
          replacement.policyId,
        );
        await controlService.revokeCredential(
          token: admin.token,
          credentialId: principal.record.id,
          organizationId: 'org_1',
        );
        final audit = (await control.readAuditChain()).toString();
        expect(audit, contains('health.auto_halt_policy_created'));
        expect(audit, contains('health.auto_halt_policy_revised'));
        expect(audit, contains('health.auto_halt_principal_issued'));
        expect(audit, contains('health.auto_halt_principal_revoked'));
        expect(audit, isNot(contains(principal.token)));
        expect(audit, isNot(contains(_leaseToken)));
      },
    );
  });
}

AutomaticHaltPolicy _policy(
  DateTime createdAt, {
  Duration maximumDecisionAge = const Duration(minutes: 10),
  String policyId = 'auto_halt_policy_1',
  String organizationId = 'org_1',
  String applicationId = 'app_1',
  String environmentId = 'env_1',
}) => AutomaticHaltPolicy(
  policyId: policyId,
  organizationId: organizationId,
  applicationId: applicationId,
  environmentId: environmentId,
  maximumAggregateAgeFromLateCutoff: const Duration(minutes: 20),
  maximumDecisionAgeFromEvaluation: maximumDecisionAge,
  resourcePolicyReference:
      'resource_test_vector_TEST VECTOR ONLY — NOT PRODUCTION POLICY',
  approvalReference: 'approval_pending_1',
  createdAt: createdAt,
  createdBy: 'actor_1',
);

String _digest(String seed) => sha256Digest(seed.codeUnits);

LogicalEvaluationKey _logicalKey({
  int logicalKeyVersion = 1,
  EvaluationReadinessPhase readinessPhase = EvaluationReadinessPhase.sealed,
  int? automaticHaltPolicyVersion,
  String? automaticHaltPolicyId,
  String? automaticHaltPolicyDigest,
  bool? automaticHaltEnabled,
  AutomaticHaltEligibleSource? eligibleSource,
  AutomaticHaltEligibleReadiness? eligibleReadiness,
  AutomaticHaltEligibleReasonClass? eligibleReasonClass,
}) => LogicalEvaluationKey(
  logicalKeyVersion: logicalKeyVersion,
  organizationId: 'org_1',
  applicationId: 'app_1',
  environmentId: 'env_1',
  platformId: 'android',
  rolloutId: 'rollout_1',
  rolloutRevision: 1,
  releaseId: 'release_1',
  patchId: 'patch_1',
  sequence: 1,
  targetBindingDigest: _digest('target'),
  windowId: 'window_1',
  readinessPhase: readinessPhase,
  observationSchemaVersion: 1,
  aggregationVersion: 1,
  aggregatePolicyDigest: _digest('aggregate'),
  evaluationPolicyVersion: 1,
  evaluationPolicyDigest: _digest('evaluation'),
  thresholdSetVersion: 1,
  thresholdSetDigest: _digest('threshold'),
  windowPolicyVersion: 1,
  privacyPolicyVersion: 1,
  scheduleId: 'schedule_1',
  scheduleRevisionId: 'schedule_revision_1',
  scheduleGeneration: 1,
  automaticHaltPolicyId: automaticHaltPolicyId,
  automaticHaltPolicyVersion: automaticHaltPolicyVersion,
  automaticHaltPolicyDigest: automaticHaltPolicyDigest,
  automaticHaltEnabled: automaticHaltEnabled,
  automaticHaltEligibleSource: eligibleSource,
  automaticHaltEligibleReadiness: eligibleReadiness,
  automaticHaltEligibleReasonClass: eligibleReasonClass,
);

const _leaseToken =
    'lease_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

P3e5LeaseMutation _lease() => P3e5LeaseMutation(
  scope: const P3e5ClaimScope(
    organizationId: 'org_1',
    applicationId: 'app_1',
    environmentId: 'env_1',
  ),
  workId: 'work_1',
  expectedWorkVersion: 2,
  leaseOwner: 'executor_1',
  rawLeaseToken: _leaseToken,
);

EvaluationSchedule _schedule(DateTime now) => EvaluationSchedule(
  scheduleId: 'schedule_1',
  organizationId: 'org_1',
  applicationId: 'app_1',
  environmentId: 'env_1',
  rolloutId: 'rollout_1',
  currentScheduleRevision: 'schedule_revision_1',
  createdAt: now,
  createdBy: 'actor_1',
);

EvaluationScheduleRevision _revisionV2(
  DateTime now, {
  required AutomaticHaltPolicy policy,
}) => EvaluationScheduleRevision(
  scheduleRevisionId: 'schedule_revision_1',
  scheduleId: 'schedule_1',
  scheduleGeneration: 1,
  organizationId: 'org_1',
  applicationId: 'app_1',
  environmentId: 'env_1',
  rolloutId: 'rollout_1',
  logicalKeyVersion: 2,
  scheduledEvaluationEnabled: true,
  automaticHaltEnabled: false,
  readinessPhase: EvaluationReadinessPhase.sealed,
  automaticHaltPolicyId: policy.policyId,
  automaticHaltPolicyVersion: policy.automaticHaltPolicyVersion,
  automaticHaltPolicyDigest: policy.digest,
  automaticHaltEligibleSource: AutomaticHaltEligibleSource.scheduledOnly,
  automaticHaltEligibleReadiness: AutomaticHaltEligibleReadiness.sealedOnly,
  automaticHaltEligibleReasonClass:
      AutomaticHaltEligibleReasonClass.patchSafetyOnly,
  triggerPolicyVersion: 1,
  schedulePolicyVersion: 1,
  evaluationPolicyVersion: 1,
  evaluationPolicyDigest: _digest('evaluation'),
  thresholdSetVersion: 1,
  thresholdSetDigest: _digest('threshold'),
  aggregationVersion: 1,
  windowPolicyVersion: 1,
  privacyPolicyVersion: 1,
  retryPolicyReference: 'retry_test',
  resourcePolicyReference: 'resource_test',
  supersedesScheduleRevisionId: null,
  createdAt: now,
  createdBy: 'actor_1',
  reason: 'test vector',
);

EvaluationScheduleRevision _legacyRevision(DateTime now) =>
    EvaluationScheduleRevision(
      scheduleRevisionId: 'schedule_revision_1',
      scheduleId: 'schedule_1',
      scheduleGeneration: 1,
      organizationId: 'org_1',
      applicationId: 'app_1',
      environmentId: 'env_1',
      rolloutId: 'rollout_1',
      scheduledEvaluationEnabled: true,
      automaticHaltEnabled: true,
      readinessPhase: EvaluationReadinessPhase.sealed,
      triggerPolicyVersion: 1,
      schedulePolicyVersion: 1,
      evaluationPolicyVersion: 1,
      evaluationPolicyDigest: _digest('evaluation'),
      thresholdSetVersion: 1,
      thresholdSetDigest: _digest('threshold'),
      aggregationVersion: 1,
      windowPolicyVersion: 1,
      privacyPolicyVersion: 1,
      retryPolicyReference: 'retry_legacy',
      resourcePolicyReference: 'resource_legacy',
      supersedesScheduleRevisionId: null,
      createdAt: now,
      createdBy: 'actor_1',
      reason: 'historical test vector',
    );

Future<void> _seedApplicationEnvironment(
  ControlPlaneStore store,
  DateTime now,
) async {
  await store.createJson(
    'applications',
    'app_1',
    ApplicationRecord(
      id: 'app_1',
      organizationId: 'org_1',
      runtimeApplicationId: 'runtime.app',
      createdAt: now,
    ).toJson(),
  );
  await store.createJson(
    'environments',
    'env_1',
    EnvironmentRecord(
      id: 'env_1',
      organizationId: 'org_1',
      applicationId: 'app_1',
      name: 'test',
      version: 0,
      promotedReleaseId: null,
      createdAt: now,
    ).toJson(),
  );
}

Future<void> _seedRollout(ControlPlaneStore store, DateTime now) async {
  final target = RolloutTarget(
    organizationId: 'org_1',
    applicationId: 'app_1',
    environmentId: 'env_1',
    platformId: 'android',
    releaseId: 'release_1',
    runtimeReleaseId: 'runtime-release-1',
    patchId: 'patch_1',
    runtimePatchId: 'runtime-patch-1',
    artifactId: 'artifact_1',
    sha256: _digest('artifact'),
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

ScheduleRevisionConfiguration _scheduleConfigurationV2(
  AutomaticHaltPolicy policy,
) => ScheduleRevisionConfiguration(
  logicalKeyVersion: 2,
  scheduledEvaluationEnabled: true,
  automaticHaltEnabled: true,
  readinessPhase: EvaluationReadinessPhase.sealed,
  automaticHaltPolicyId: policy.policyId,
  automaticHaltPolicyVersion: policy.automaticHaltPolicyVersion,
  automaticHaltPolicyDigest: policy.digest,
  automaticHaltEligibleSource: AutomaticHaltEligibleSource.scheduledOnly,
  automaticHaltEligibleReadiness: AutomaticHaltEligibleReadiness.sealedOnly,
  automaticHaltEligibleReasonClass:
      AutomaticHaltEligibleReasonClass.patchSafetyOnly,
  evaluationPolicyDigest: _digest('evaluation'),
  thresholdSetDigest: _digest('threshold'),
  retryPolicyReference: 'retry_test',
  resourcePolicyReference: 'resource_test',
  reason: 'TEST VECTOR ONLY',
);
