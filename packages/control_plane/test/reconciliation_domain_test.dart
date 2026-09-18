import 'dart:convert';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

const _digest =
    'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _otherDigest =
    'sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
const _testVectorPolicyMarker = 'TEST VECTOR ONLY — NOT PRODUCTION POLICY';

final _scope = ReconciliationScope(
  organizationId: 'org_1',
  applicationId: 'app_1',
  environmentId: 'env_1',
);

final _policy = ReconciliationPolicy(
  policyVersion: 1,
  maximumRecordsScanned: 20,
  maximumTenantsScanned: 4,
  maximumLinkageDepth: 3,
  maximumFindings: 10,
  maximumRepairs: 5,
  maximumConcurrentRepairs: 2,
  maximumRetryAttempts: 3,
  lookbackHorizon: const Duration(hours: 1),
  maximumDiagnosticHistory: 5,
  maximumAuditLookupDepth: 10,
  fairnessPolicyVersion: 1,
);

final _now = DateTime.utc(2026, 8, 24, 12);

ReconciliationFinding _finding({
  ReconciliationTaxonomyCode code =
      ReconciliationTaxonomyCode.workEvaluationLinkMissing,
  Map<String, String> sourceDigests = const {'aggregate': _digest},
  ReconciliationFindingStatus status = ReconciliationFindingStatus.open,
}) => ReconciliationFinding.create(
  scope: _scope,
  code: code,
  entityType: 'scheduled_work',
  entityId: 'work_1',
  sourceDigests: sourceDigests,
  observedVersions: const {'work_version': 2},
  firstObservedAt: _now,
  lastObservedAt: _now,
  status: status,
  safeDetailCode: 'LINK_MISSING',
);

ReconciliationPrecondition _precondition(ReconciliationFinding finding) =>
    ReconciliationPrecondition(
      scope: finding.scope,
      findingId: finding.findingId,
      entityId: finding.entityId,
      expectedWorkVersion: 2,
      expectedScheduleRevision: 'revision_1',
      currentRolloutRevision: 'rollout_revision_1',
      sourceDigests: finding.sourceDigests,
      targetBinding: const {'release': 'release_1', 'patch': 'patch_1'},
      taxonomyCode: finding.code,
      action: ReconciliationRepairAction.linkExistingEvaluation,
    );

void main() {
  group('scope, policy, cursor, and invocation', () {
    test('canonical policy and cursor are deterministic and bounded', () {
      expect(_testVectorPolicyMarker, contains('NOT PRODUCTION POLICY'));
      final policyRoundTrip = ReconciliationPolicy.fromCanonicalJson(
        _policy.canonicalSerialization,
      );
      expect(
        policyRoundTrip.canonicalSerialization,
        _policy.canonicalSerialization,
      );
      expect(policyRoundTrip.digest, _policy.digest);

      final cursor = ReconciliationCursor(
        scope: _scope,
        position: 'tenant_cursor_1',
        oldestUnresolvedAge: const Duration(minutes: 5),
        perTenantCap: 2,
        globalCap: 5,
      );
      expect(
        ReconciliationCursor.fromCanonicalJson(cursor.canonicalSerialization)
            .digest,
        cursor.digest,
      );
      expect(
        () => ReconciliationPolicy(
          policyVersion: 1,
          maximumRecordsScanned: 1,
          maximumTenantsScanned: 2,
          maximumLinkageDepth: 1,
          maximumFindings: 1,
          maximumRepairs: 1,
          maximumConcurrentRepairs: 1,
          maximumRetryAttempts: 1,
          lookbackHorizon: const Duration(seconds: 1),
          maximumDiagnosticHistory: 1,
          maximumAuditLookupDepth: 1,
          fairnessPolicyVersion: 1,
        ),
        throwsFormatException,
      );
    });

    test('invocation identity is derived from scope and policy', () {
      final cursor = ReconciliationCursor(
        scope: _scope,
        position: 'tenant_cursor_1',
        oldestUnresolvedAge: const Duration(minutes: 5),
        perTenantCap: 2,
        globalCap: 5,
      );
      final invocation = ReconciliationInvocation.create(
        scope: _scope,
        actorId: 'operator_1',
        principalId: 'principal_1',
        storageMode: ReconciliationStorageMode.postgres,
        policy: _policy,
        startedAt: _now,
        cursor: cursor,
      );
      expect(
        invocation.invocationId,
        ReconciliationInvocation.deriveInvocationId(
          scope: _scope,
          actorId: 'operator_1',
          principalId: 'principal_1',
          principalKind: ReconciliationPrincipalKind.tenantScopedAdministrator,
          storageMode: ReconciliationStorageMode.postgres,
          policy: _policy,
          startedAt: _now,
          cursor: cursor,
        ),
      );
      expect(
        ReconciliationInvocation.fromCanonicalJson(
          invocation.canonicalSerialization,
        ).canonicalSerialization,
        invocation.canonicalSerialization,
      );
      final tampered = Map<String, Object?>.from(invocation.toJson())
        ..['invocationId'] = 'reconcile-invocation:tampered';
      expect(
        () => ReconciliationInvocation.fromJson(tampered),
        throwsFormatException,
      );
    });

    test('cursor cannot escape invocation scope', () {
      final foreignCursor = ReconciliationCursor(
        scope: ReconciliationScope(
          organizationId: 'org_2',
          applicationId: 'app_2',
          environmentId: 'env_2',
        ),
        position: 'cursor_1',
        oldestUnresolvedAge: Duration.zero,
        perTenantCap: 1,
        globalCap: 1,
      );
      expect(
        () => ReconciliationInvocation.create(
          scope: _scope,
          actorId: 'operator_1',
          principalId: 'principal_1',
          storageMode: ReconciliationStorageMode.file,
          policy: _policy,
          startedAt: _now,
          cursor: foreignCursor,
        ),
        throwsFormatException,
      );
    });
  });

  group('taxonomy and immutable boundary', () {
    test('all stable taxonomy codes have complete typed metadata', () {
      expect(
        reconciliationTaxonomy.length,
        ReconciliationTaxonomyCode.values.length,
      );
      for (final code in ReconciliationTaxonomyCode.values) {
        final metadata = reconciliationMetadataFor(code);
        expect(metadata.code, code);
        expect(metadata.defaultSeverity, isA<ReconciliationSeverity>());
        expect(metadata.repairability, isA<ReconciliationRepairability>());
        expect(metadata.operatorAction, isA<ReconciliationOperatorAction>());
        expect(metadata.auditBehavior, isA<ReconciliationAuditBehavior>());
      }
      expect(
        isImmutableReconciliationSource(
          ReconciliationImmutableSource.healthEvaluation,
        ),
        isTrue,
      );
      expect(
        isImmutableReconciliationSource(
          ReconciliationImmutableSource.auditChain,
        ),
        isTrue,
      );
    });

    test('repair actions cannot cross repairability or rollout boundaries', () {
      final immutableFinding = _finding(
        code: ReconciliationTaxonomyCode.targetBindingMismatch,
      );
      final immutablePrecondition = ReconciliationPrecondition(
        scope: immutableFinding.scope,
        findingId: immutableFinding.findingId,
        entityId: immutableFinding.entityId,
        expectedWorkVersion: 2,
        expectedScheduleRevision: 'revision_1',
        currentRolloutRevision: 'rollout_revision_1',
        sourceDigests: immutableFinding.sourceDigests,
        targetBinding: const {'release': 'release_1'},
        taxonomyCode: immutableFinding.code,
        action: ReconciliationRepairAction.reportOnly,
      );
      expect(
        () => immutablePrecondition.validateAgainst(immutableFinding),
        returnsNormally,
      );
      final invalid = ReconciliationPrecondition(
        scope: immutableFinding.scope,
        findingId: immutableFinding.findingId,
        entityId: immutableFinding.entityId,
        expectedWorkVersion: 2,
        expectedScheduleRevision: 'revision_1',
        currentRolloutRevision: 'rollout_revision_1',
        sourceDigests: immutableFinding.sourceDigests,
        targetBinding: const {'release': 'release_1'},
        taxonomyCode: immutableFinding.code,
        action: ReconciliationRepairAction.markStale,
      );
      expect(
        () => invalid.validateAgainst(immutableFinding),
        throwsFormatException,
      );
      expect(
        reconciliationRepairPolicyFor(
          ReconciliationRepairAction.linkExistingHaltApplication,
        ).rolloutMutationAllowed,
        isFalse,
      );
      expect(
        reconciliationRepairPolicyFor(
          ReconciliationRepairAction.linkExistingEvaluation,
        ).target,
        ReconciliationProjectionTarget.workEvaluationLink,
      );
    });
  });

  group('findings, preconditions, and repair attempts', () {
    test(
      'finding identity excludes observation timestamps but includes evidence',
      () {
        final finding = _finding();
        final later = ReconciliationFinding.create(
          scope: _scope,
          code: finding.code,
          entityType: finding.entityType,
          entityId: finding.entityId,
          sourceDigests: finding.sourceDigests,
          observedVersions: finding.observedVersions,
          firstObservedAt: _now,
          lastObservedAt: _now.add(const Duration(minutes: 10)),
          safeDetailCode: finding.safeDetailCode,
        );
        expect(later.findingId, finding.findingId);
        final changed = _finding(sourceDigests: {'aggregate': _otherDigest});
        expect(changed.findingId, isNot(finding.findingId));
        expect(
          ReconciliationFinding.fromCanonicalJson(
            finding.canonicalSerialization,
          ).canonicalSerialization,
          finding.canonicalSerialization,
        );
      },
    );

    test('repair ID is deterministic and changed body conflicts', () {
      final finding = _finding();
      final precondition = _precondition(finding);
      final attempt = ReconciliationRepairAttempt.create(
        finding: finding,
        precondition: precondition,
        actorId: 'operator_1',
        result: ReconciliationRepairResult.requested,
        createdAt: _now,
      );
      final replay = ReconciliationRepairAttempt.fromCanonicalJson(
        attempt.canonicalSerialization,
      );
      expect(
        attempt.compareWith(replay),
        ReconciliationRepairAttemptComparison.replay,
      );
      expect(
        attempt.repairId,
        'reconcile-repair:${finding.findingId}:LINK_EXISTING_EVALUATION',
      );
      final principal = ReconciliationPrincipal(
        principalId: 'principal_1',
        scope: _scope,
        actorId: 'operator_1',
        issuedAt: _now,
        expiresAt: _now.add(const Duration(hours: 1)),
      );
      final authorized = ReconciliationRepairAttempt.createAuthorized(
        principal: principal,
        finding: finding,
        precondition: precondition,
        result: ReconciliationRepairResult.requested,
        now: _now,
        createdAt: _now,
      );
      expect(authorized.actorId, principal.actorId);
      final conflict = ReconciliationRepairAttempt.create(
        finding: finding,
        precondition: precondition,
        actorId: 'operator_1',
        result: ReconciliationRepairResult.failed,
        safeErrorCode: 'CAS_CONFLICT',
        createdAt: _now.add(const Duration(seconds: 1)),
      );
      expect(
        attempt.compareWith(conflict),
        ReconciliationRepairAttemptComparison.conflict,
      );
      expect(
        () => ReconciliationRepairAttempt.create(
          finding: finding,
          precondition: ReconciliationPrecondition(
            scope: finding.scope,
            findingId: finding.findingId,
            entityId: finding.entityId,
            expectedWorkVersion: 3,
            expectedScheduleRevision: 'revision_1',
            currentRolloutRevision: 'rollout_revision_1',
            sourceDigests: finding.sourceDigests,
            targetBinding: const {'release': 'release_1', 'patch': 'patch_1'},
            taxonomyCode: finding.code,
            action: precondition.action,
          ),
          actorId: 'operator_1',
          result: ReconciliationRepairResult.requested,
          createdAt: _now,
        ),
        returnsNormally,
      );
    });

    test('unknown taxonomy and malformed digest fail closed', () {
      expect(
        () => parseReconciliationTaxonomyCode('FUTURE_CODE'),
        throwsFormatException,
      );
      expect(
        () => _finding(sourceDigests: {'aggregate': 'not-a-digest'}),
        throwsFormatException,
      );
      final map = _finding().toJson()..['severity'] = 'INFO';
      expect(() => ReconciliationFinding.fromJson(map), throwsFormatException);
    });
  });

  group('reconciliation principal and audit redaction', () {
    test('principal is exact-scope, expiring, revocable, and rotatable', () {
      final principal = ReconciliationPrincipal(
        principalId: 'principal_1',
        scope: _scope,
        actorId: 'operator_1',
        issuedAt: _now,
        expiresAt: _now.add(const Duration(hours: 1)),
      );
      final invocation = ReconciliationInvocation.create(
        scope: _scope,
        actorId: 'operator_1',
        principalId: 'principal_1',
        storageMode: ReconciliationStorageMode.file,
        policy: _policy,
        startedAt: _now,
      );
      expect(
        () => principal.authorizeInvocation(invocation, now: _now),
        returnsNormally,
      );
      expect(principal.scopes, reconciliationScopes);
      expect(
        principal.scopes.intersection(reconciliationForbiddenScopes),
        isEmpty,
      );
      expect(
        principal.isActiveAt(_now.add(const Duration(minutes: 30))),
        isTrue,
      );
      expect(principal.isActiveAt(_now.add(const Duration(hours: 1))), isFalse);
      final revoked = principal.revokeAt(
        at: _now.add(const Duration(minutes: 1)),
        actorId: 'security_operator_1',
      );
      expect(revoked.isActiveAt(_now.add(const Duration(minutes: 2))), isFalse);
      final rotated = principal.rotate(
        newPrincipalId: 'principal_2',
        newActorId: 'operator_2',
        issuedAt: _now,
        expiresAt: _now.add(const Duration(hours: 2)),
      );
      expect(rotated.rotationGeneration, 2);
      expect(
        rotated.scope.canonicalSerialization,
        principal.scope.canonicalSerialization,
      );
      expect(
        () => principal.authorizeAction(
          ReconciliationRepairAction.linkExistingEvaluation,
          _scope,
          now: _now,
        ),
        returnsNormally,
      );
      expect(
        () => principal.authorizeAction(
          ReconciliationRepairAction.markStale,
          ReconciliationScope(
            organizationId: 'org_2',
            applicationId: 'app_2',
            environmentId: 'env_2',
          ),
          now: _now,
        ),
        throwsFormatException,
      );
    });

    test('audit events contain only bounded safe fields', () {
      final event = ReconciliationAuditEvent(
        eventType: ReconciliationAuditEventType.repairRejected,
        scope: _scope,
        actorId: 'operator_1',
        resourceId: 'repair_1',
        taxonomyCode: ReconciliationTaxonomyCode.tenantScopeMismatch,
        action: ReconciliationRepairAction.reportOnly,
        result: ReconciliationRepairResult.conflict,
        safeErrorCode: 'FOREIGN_SCOPE',
        boundedCount: 1,
        createdAt: _now,
      );
      final json = event.toJson();
      expect(json.keys, isNot(contains('token')));
      expect(json.keys, isNot(contains('patchBytes')));
      expect(json.keys, isNot(contains('privateKey')));
      expect(
        ReconciliationAuditEvent.fromCanonicalJson(event.canonicalSerialization)
            .canonicalSerialization,
        event.canonicalSerialization,
      );
    });
  });

  group('resource and canonical input safety', () {
    test(
      'unknown fields, noncanonical JSON, and oversized safe codes reject',
      () {
        final finding = _finding();
        final unknown = finding.toJson()..['unexpected'] = true;
        expect(
          () => ReconciliationFinding.fromJson(unknown),
          throwsFormatException,
        );
        expect(
          () => ReconciliationFinding.fromCanonicalJson(
            jsonEncode(finding.toJson()),
          ),
          throwsFormatException,
        );
        expect(
          () => _finding().copyWithForTest(
            safeDetailCode: 'X' * (maximumReconciliationSafeCodeLength + 1),
          ),
          throwsFormatException,
        );
      },
    );
  });
}

extension on ReconciliationFinding {
  ReconciliationFinding copyWithForTest({required String safeDetailCode}) =>
      ReconciliationFinding(
        schemaVersion: schemaVersion,
        findingId: findingId,
        scope: scope,
        code: code,
        severity: severity,
        repairability: repairability,
        entityType: entityType,
        entityId: entityId,
        sourceDigests: sourceDigests,
        observedVersions: observedVersions,
        firstObservedAt: firstObservedAt,
        lastObservedAt: lastObservedAt,
        status: status,
        safeDetailCode: safeDetailCode,
      );
}
