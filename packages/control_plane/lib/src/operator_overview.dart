import 'domain.dart';
import 'errors.dart';
import 'rollout.dart';
import 'service.dart';

const int defaultOperatorOverviewMaxItems = 100;

/// The existing control-credential scopes needed to read every collection in
/// the operator overview. This is a machine credential boundary, not human
/// RBAC.
const Set<String> operatorOverviewReadScopes = <String>{
  'application:read',
  'release:read',
  'patch:read',
  'artifact:read',
  'rollout:read',
  'audit:read',
};

/// Deep projection seam for the local read-only operator surface.
///
/// The caller supplies one organization and a control credential. The
/// implementation performs tenant authorization before reading or decoding
/// collection entries, bounds each returned list, and omits runtime bytes and
/// credential material. It does not calculate health or deployment success.
final class OperatorOverviewProjection {
  OperatorOverviewProjection(
    this.service, {
    this.maxItems = defaultOperatorOverviewMaxItems,
  }) {
    if (maxItems <= 0 || maxItems > defaultOperatorOverviewMaxItems) {
      throw ArgumentError.value(
        maxItems,
        'maxItems',
        'must be between 1 and $defaultOperatorOverviewMaxItems',
      );
    }
  }

  final ControlPlaneService service;
  final int maxItems;

  Future<OperatorOverview> read({
    required String token,
    required String organizationId,
  }) async {
    final actor = await service.authorizeControlCredential(
      token: token,
      requiredScope: 'application:read',
      organizationId: organizationId,
    );
    if (!actor.scopes.containsAll(operatorOverviewReadScopes)) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'Credential does not have the required operator overview read scopes',
        statusCode: 403,
      );
    }

    final organizationValue = await service.store.readJson(
      'organizations',
      organizationId,
    );
    if (organizationValue == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final organization = OrganizationRecord.fromJson(organizationValue);
    if (organization.id != actor.organizationId) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }

    final applications = _bounded(
      await _tenantRecords(
        'applications',
        ApplicationRecord.fromJson,
        (record) => record.organizationId,
        organization.id,
      ),
      (record) => record.createdAt,
      (record) => record.id,
    );
    final environments = _bounded(
      await _tenantRecords(
        'environments',
        EnvironmentRecord.fromJson,
        (record) => record.organizationId,
        organization.id,
      ),
      (record) => record.createdAt,
      (record) => record.id,
    );
    final releases = _bounded(
      await _tenantRecords(
        'releases',
        ReleaseRecord.fromJson,
        (record) => record.organizationId,
        organization.id,
      ),
      (record) => record.createdAt,
      (record) => record.id,
    );
    final patches = _bounded(
      await _tenantRecords(
        'patches',
        PatchRecord.fromJson,
        (record) => record.organizationId,
        organization.id,
      ),
      (record) => record.createdAt,
      (record) => record.id,
    );
    final artifacts = _bounded(
      await _tenantRecords(
        'artifacts',
        ArtifactRecord.fromJson,
        (record) => record.organizationId,
        organization.id,
      ),
      (record) => record.createdAt,
      (record) => record.id,
    );
    final rollouts = await _rollouts(organization.id);
    final audit = _bounded(
      await _tenantRecords(
        'audit',
        AuditRecord.fromJson,
        (record) => record.organizationId,
        organization.id,
      ),
      (record) => record.createdAt,
      (record) => record.id,
    );

    return OperatorOverview(
      organization: organization,
      applications: applications,
      environments: environments,
      releases: releases,
      patches: patches,
      artifacts: artifacts,
      rollouts: rollouts,
      audit: audit,
      maxItems: maxItems,
    );
  }

  Future<List<T>> _tenantRecords<T>(
    String collection,
    T Function(Map<String, Object?>) decode,
    String Function(T) organizationOf,
    String organizationId,
  ) async {
    final records = <T>[];
    for (final value in await service.store.listJson(collection)) {
      // Apply the tenant predicate to the persisted envelope before decoding
      // or counting a record. Foreign malformed data must not affect this
      // organization projection.
      if (value['organizationId'] != organizationId) continue;
      final record = decode(value);
      if (organizationOf(record) == organizationId) records.add(record);
    }
    return records;
  }

  Future<OperatorOverviewCollection<OperatorRolloutSummary>> _rollouts(
    String organizationId,
  ) async {
    final revisionsByRollout = <String, List<RolloutRevision>>{};
    for (final value in await service.store.listJson('rollout_revisions')) {
      if (value['organizationId'] != organizationId) continue;
      final revision = RolloutRevision.fromJson(value);
      revisionsByRollout
          .putIfAbsent(revision.rolloutId, () => <RolloutRevision>[])
          .add(revision);
    }

    final summaries = <OperatorRolloutSummary>[];
    for (final value in await service.store.listJson('rollouts')) {
      if (value['organizationId'] != organizationId) continue;
      final rollout = RolloutRecord.fromJson(value);
      final candidates = (revisionsByRollout[rollout.id] ?? const [])
          .where((revision) => revision.revision == rollout.currentRevision)
          .toList(growable: false);
      summaries.add(
        OperatorRolloutSummary(
          rollout: rollout,
          currentRevision: candidates.length == 1 ? candidates.single : null,
          currentRevisionStatus: switch (candidates.length) {
            0 => 'missing',
            1 => 'present',
            _ => 'ambiguous',
          },
        ),
      );
    }
    return _bounded(
      summaries,
      (summary) => summary.rollout.createdAt,
      (summary) => summary.rollout.id,
    );
  }

  OperatorOverviewCollection<T> _bounded<T>(
    List<T> records,
    DateTime Function(T) createdAt,
    String Function(T) id,
  ) {
    final sorted = List<T>.from(records)
      ..sort((left, right) {
        final byTime = createdAt(right).compareTo(createdAt(left));
        if (byTime != 0) return byTime;
        return id(left).compareTo(id(right));
      });
    return OperatorOverviewCollection<T>(
      items: sorted.take(maxItems).toList(growable: false),
      total: sorted.length,
    );
  }
}

final class OperatorOverview {
  const OperatorOverview({
    required this.organization,
    required this.applications,
    required this.environments,
    required this.releases,
    required this.patches,
    required this.artifacts,
    required this.rollouts,
    required this.audit,
    required this.maxItems,
  });

  final OrganizationRecord organization;
  final OperatorOverviewCollection<ApplicationRecord> applications;
  final OperatorOverviewCollection<EnvironmentRecord> environments;
  final OperatorOverviewCollection<ReleaseRecord> releases;
  final OperatorOverviewCollection<PatchRecord> patches;
  final OperatorOverviewCollection<ArtifactRecord> artifacts;
  final OperatorOverviewCollection<OperatorRolloutSummary> rollouts;
  final OperatorOverviewCollection<AuditRecord> audit;
  final int maxItems;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'readOnly': true,
    'runtimeAuthority': 'client',
    'organization': organization.toJson(),
    'applications': applications.items
        .map((record) => record.toJson())
        .toList(growable: false),
    'environments': environments.items
        .map((record) => record.toJson())
        .toList(growable: false),
    'releases': releases.items
        .map((record) => record.toJson())
        .toList(growable: false),
    'patches': patches.items
        .map((record) => record.toJson())
        .toList(growable: false),
    'artifacts': artifacts.items
        .map((record) => record.toJson())
        .toList(growable: false),
    'rollouts': rollouts.items
        .map((summary) => summary.toJson())
        .toList(growable: false),
    'audit': audit.items.map(_auditJson).toList(growable: false),
    'limits': <String, Object?>{'maxItemsPerCollection': maxItems},
    'counts': <String, Object?>{
      'applications': applications.total,
      'environments': environments.total,
      'releases': releases.total,
      'patches': patches.total,
      'artifacts': artifacts.total,
      'rollouts': rollouts.total,
      'audit': audit.total,
    },
    'truncated': <String, Object?>{
      'applications': applications.truncated,
      'environments': environments.truncated,
      'releases': releases.truncated,
      'patches': patches.truncated,
      'artifacts': artifacts.truncated,
      'rollouts': rollouts.truncated,
      'audit': audit.truncated,
    },
  };
}

final class OperatorRolloutSummary {
  const OperatorRolloutSummary({
    required this.rollout,
    required this.currentRevision,
    required this.currentRevisionStatus,
  });

  final RolloutRecord rollout;
  final RolloutRevision? currentRevision;
  final String currentRevisionStatus;

  Map<String, Object?> toJson() => <String, Object?>{
    ...rollout.toJson(),
    'currentRevision': currentRevision == null
        ? null
        : <String, Object?>{
            'id': currentRevision!.id,
            'rolloutId': currentRevision!.rolloutId,
            'organizationId': currentRevision!.organizationId,
            'revision': currentRevision!.revision,
            'previousRevision': currentRevision!.previousRevision,
            'state': currentRevision!.state.wireName,
            'target': currentRevision!.target.toJson(),
            'policy': <String, Object?>{
              'cohortKind': currentRevision!.policy.cohortKind.name,
              'percentageBasisPoints':
                  currentRevision!.policy.percentageBasisPoints,
              'exposureMode': currentRevision!.policy.exposureMode,
              'internalInstallationCount':
                  currentRevision!.policy.internalInstallationHashes.length,
            },
            'actorId': currentRevision!.actorId,
            'reason': currentRevision!.reason,
            'pausedFromState': currentRevision!.pausedFromState?.wireName,
            'createdAt': currentRevision!.createdAt.toUtc().toIso8601String(),
          },
    'currentRevisionStatus': currentRevisionStatus,
  };
}

final class OperatorOverviewCollection<T> {
  const OperatorOverviewCollection({required this.items, required this.total});

  final List<T> items;
  final int total;

  bool get truncated => total > items.length;
}

Map<String, Object?> _auditJson(AuditRecord record) => <String, Object?>{
  'id': record.id,
  'requestId': record.requestId,
  'organizationId': record.organizationId,
  'actorId': record.actorId,
  'action': record.action,
  'resourceType': record.resourceType,
  'resourceId': record.resourceId,
  'result': record.result,
  'metadata': _allowlistedAuditValue(record.metadata),
  'createdAt': record.createdAt.toUtc().toIso8601String(),
};

const Set<String> _safeAuditMetadataKeys = <String>{
  'action',
  'actionDisposition',
  'aggregateId',
  'aggregateRevisionId',
  'aggregationVersion',
  'applicationId',
  'application_id',
  'artifactDigest',
  'artifactId',
  'artifact_id',
  'attempt',
  'attemptCount',
  'attemptNumber',
  'attempt_count',
  'attempt_number',
  'auditReference',
  'authorizedAt',
  'backoffDelaySeconds',
  'backoffState',
  'boundedCount',
  'bundleDigest',
  'bundleImportId',
  'checkedAggregates',
  'checkedCursors',
  'checkedDecisions',
  'checkedEvaluations',
  'checkedHaltApplications',
  'checkedRevisions',
  'code',
  'concurrent',
  'consecutiveFailures',
  'coverageState',
  'currentRolloutRevision',
  'currentVersion',
  'decision',
  'decisionId',
  'decision_id',
  'deletedCount',
  'diagnosticCode',
  'environmentId',
  'environment_id',
  'errorClass',
  'errorCode',
  'evaluationId',
  'evaluationInputDigest',
  'evaluation_id',
  'eventType',
  'expectedRolloutRevision',
  'expiresAt',
  'fromState',
  'freshnessState',
  'idempotent',
  'inventoryAvailable',
  'itemCount',
  'kind',
  'lastErrorCode',
  'lastOutcome',
  'lastRunOutcome',
  'maximumRecords',
  'nextDueAt',
  'outcome',
  'outcomeCount',
  'patchId',
  'patch_id',
  'percentageBasisPoints',
  'platformId',
  'policyDigest',
  'policyId',
  'policyVersion',
  'quarantinedCount',
  'readinessPhase',
  'reasonClass',
  'releaseId',
  'release_id',
  'reportOnly',
  'result',
  'resultingRolloutRevision',
  'retryPolicyVersion',
  'rolloutId',
  'rolloutRevision',
  'rollout_id',
  'scheduleId',
  'scheduleRevisionId',
  'sequence',
  'sha256',
  'sizeBytes',
  'state',
  'status',
  'storageMode',
  'toState',
  'truncated',
  'valid',
  'version',
  'workId',
  'workVersion',
};

Object? _allowlistedAuditValue(Object? value) {
  if (value is Map) {
    final allowlisted = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is String &&
          _safeAuditMetadataKeys.contains(entry.key as String)) {
        allowlisted[entry.key as String] = _allowlistedAuditValue(entry.value);
      }
    }
    return allowlisted;
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  return null;
}
