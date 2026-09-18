import 'dart:convert';

import 'encoding.dart';

/// Version of the P3E5-5A reconciliation domain wire contract.
const int reconciliationSchemaVersion = 1;
const int supportedReconciliationPolicyVersion = 1;
const int supportedReconciliationFairnessPolicyVersion = 1;

/// These are parser/serialization safety limits, not operational defaults.
/// Reconciliation policy values are always supplied explicitly by a caller.
const int maximumReconciliationInvocationBytes = 64 * 1024;
const int maximumReconciliationFindingBytes = 32 * 1024;
const int maximumReconciliationRepairAttemptBytes = 32 * 1024;
const int maximumReconciliationPolicyBytes = 16 * 1024;
const int maximumReconciliationCursorBytes = 8 * 1024;
const int maximumReconciliationPrincipalBytes = 16 * 1024;
const int maximumReconciliationAuditEventBytes = 16 * 1024;
const int maximumReconciliationSourceDigests = 64;
const int maximumReconciliationObservedVersions = 64;
const int maximumReconciliationTargetBindings = 32;
const int maximumReconciliationSafeCodeLength = 128;
const int maximumReconciliationCursorPositionLength = 256;
const int maximumReconciliationEntityLength = 256;
const int maximumReconciliationActorLength = 128;
const int maximumReconciliationIdLength = 512;

const Set<String> reconciliationScopes = <String>{
  'health:reconcile',
  'health:read',
  'rollout:read',
};

const Set<String> reconciliationForbiddenScopes = <String>{
  'rollout:halt',
  'rollout:expand',
  'rollout:promote',
  'release:write',
  'artifact:write',
  'credential:issue',
  'credential:revoke',
  'observation:write',
  'runtime:authority',
};

enum ReconciliationPrincipalKind { tenantScopedAdministrator }

extension ReconciliationPrincipalKindWire on ReconciliationPrincipalKind {
  String get wireName => switch (this) {
    ReconciliationPrincipalKind.tenantScopedAdministrator =>
      'TENANT_SCOPED_ADMINISTRATOR',
  };
}

ReconciliationPrincipalKind parseReconciliationPrincipalKind(Object? value) =>
    switch (value) {
      'TENANT_SCOPED_ADMINISTRATOR' =>
        ReconciliationPrincipalKind.tenantScopedAdministrator,
      _ => throw const FormatException(
        'Unsupported reconciliation principal kind',
      ),
    };

enum ReconciliationStorageMode { file, postgres }

extension ReconciliationStorageModeWire on ReconciliationStorageMode {
  String get wireName => name.toUpperCase();
}

ReconciliationStorageMode parseReconciliationStorageMode(Object? value) =>
    switch (value) {
      'FILE' => ReconciliationStorageMode.file,
      'POSTGRES' => ReconciliationStorageMode.postgres,
      _ => throw const FormatException(
        'Unsupported reconciliation storage mode',
      ),
    };

enum ReconciliationSeverity { info, warning, error, security, critical }

extension ReconciliationSeverityWire on ReconciliationSeverity {
  String get wireName => name.toUpperCase();
}

ReconciliationSeverity parseReconciliationSeverity(Object? value) {
  for (final item in ReconciliationSeverity.values) {
    if (item.wireName == value) return item;
  }
  throw const FormatException('Unsupported reconciliation severity');
}

enum ReconciliationRepairability {
  repairableProjection,
  recoverableOperationalState,
  reportOnlyImmutableDivergence,
}

extension ReconciliationRepairabilityWire on ReconciliationRepairability {
  String get wireName => switch (this) {
    ReconciliationRepairability.repairableProjection => 'REPAIRABLE_PROJECTION',
    ReconciliationRepairability.recoverableOperationalState =>
      'RECOVERABLE_OPERATIONAL_STATE',
    ReconciliationRepairability.reportOnlyImmutableDivergence =>
      'REPORT_ONLY_IMMUTABLE_DIVERGENCE',
  };
}

ReconciliationRepairability parseReconciliationRepairability(Object? value) {
  for (final item in ReconciliationRepairability.values) {
    if (item.wireName == value) return item;
  }
  throw const FormatException('Unsupported reconciliation repairability');
}

enum ReconciliationRepairAction {
  linkExistingEvaluation,
  linkExistingDecision,
  linkExistingHaltApplication,
  completeWorkFromExistingApplication,
  markStale,
  markFailedPermanent,
  rebuildDerivedProjection,
  reportOnly,
}

extension ReconciliationRepairActionWire on ReconciliationRepairAction {
  String get wireName => switch (this) {
    ReconciliationRepairAction.linkExistingEvaluation =>
      'LINK_EXISTING_EVALUATION',
    ReconciliationRepairAction.linkExistingDecision => 'LINK_EXISTING_DECISION',
    ReconciliationRepairAction.linkExistingHaltApplication =>
      'LINK_EXISTING_HALT_APPLICATION',
    ReconciliationRepairAction.completeWorkFromExistingApplication =>
      'COMPLETE_WORK_FROM_EXISTING_APPLICATION',
    ReconciliationRepairAction.markStale => 'MARK_STALE',
    ReconciliationRepairAction.markFailedPermanent => 'MARK_FAILED_PERMANENT',
    ReconciliationRepairAction.rebuildDerivedProjection =>
      'REBUILD_DERIVED_PROJECTION',
    ReconciliationRepairAction.reportOnly => 'REPORT_ONLY',
  };
}

ReconciliationRepairAction parseReconciliationRepairAction(Object? value) {
  for (final item in ReconciliationRepairAction.values) {
    if (item.wireName == value) return item;
  }
  throw const FormatException('Unsupported reconciliation repair action');
}

enum ReconciliationFindingStatus {
  open,
  repairPending,
  repaired,
  reportOnly,
  failed,
  stale,
}

extension ReconciliationFindingStatusWire on ReconciliationFindingStatus {
  String get wireName => switch (this) {
    ReconciliationFindingStatus.open => 'OPEN',
    ReconciliationFindingStatus.repairPending => 'REPAIR_PENDING',
    ReconciliationFindingStatus.repaired => 'REPAIRED',
    ReconciliationFindingStatus.reportOnly => 'REPORT_ONLY',
    ReconciliationFindingStatus.failed => 'FAILED',
    ReconciliationFindingStatus.stale => 'STALE',
  };
}

ReconciliationFindingStatus parseReconciliationFindingStatus(Object? value) {
  for (final item in ReconciliationFindingStatus.values) {
    if (item.wireName == value) return item;
  }
  throw const FormatException('Unsupported reconciliation finding status');
}

enum ReconciliationRepairResult {
  requested,
  applied,
  replayed,
  conflict,
  failed,
  reportOnly,
}

extension ReconciliationRepairResultWire on ReconciliationRepairResult {
  String get wireName => switch (this) {
    ReconciliationRepairResult.requested => 'REQUESTED',
    ReconciliationRepairResult.applied => 'APPLIED',
    ReconciliationRepairResult.replayed => 'REPLAYED',
    ReconciliationRepairResult.conflict => 'CONFLICT',
    ReconciliationRepairResult.failed => 'FAILED',
    ReconciliationRepairResult.reportOnly => 'REPORT_ONLY',
  };
}

ReconciliationRepairResult parseReconciliationRepairResult(Object? value) {
  for (final item in ReconciliationRepairResult.values) {
    if (item.wireName == value) return item;
  }
  throw const FormatException('Unsupported reconciliation repair result');
}

enum ReconciliationOperatorAction {
  review,
  investigate,
  retryWithFreshScope,
  securityIncidentReview,
  upgradeOrMigrationDecision,
  manualDisposition,
  observe,
  existingRecoveryWorkflow,
}

extension ReconciliationOperatorActionWire on ReconciliationOperatorAction {
  String get wireName => switch (this) {
    ReconciliationOperatorAction.review => 'REVIEW',
    ReconciliationOperatorAction.investigate => 'INVESTIGATE',
    ReconciliationOperatorAction.retryWithFreshScope =>
      'RETRY_WITH_FRESH_SCOPE',
    ReconciliationOperatorAction.securityIncidentReview =>
      'SECURITY_INCIDENT_REVIEW',
    ReconciliationOperatorAction.upgradeOrMigrationDecision =>
      'UPGRADE_OR_MIGRATION_DECISION',
    ReconciliationOperatorAction.manualDisposition => 'MANUAL_DISPOSITION',
    ReconciliationOperatorAction.observe => 'OBSERVE',
    ReconciliationOperatorAction.existingRecoveryWorkflow =>
      'EXISTING_RECOVERY_WORKFLOW',
  };
}

enum ReconciliationAuditBehavior {
  findingAndRepairOutcome,
  securityFinding,
  findingOnly,
  redactedSecurityEvent,
  stateTransitionAudit,
  reclaimAttemptAudit,
  findingAndDisposition,
}

extension ReconciliationAuditBehaviorWire on ReconciliationAuditBehavior {
  String get wireName => switch (this) {
    ReconciliationAuditBehavior.findingAndRepairOutcome =>
      'FINDING_AND_REPAIR_OUTCOME',
    ReconciliationAuditBehavior.securityFinding => 'SECURITY_FINDING',
    ReconciliationAuditBehavior.findingOnly => 'FINDING_ONLY',
    ReconciliationAuditBehavior.redactedSecurityEvent =>
      'REDACTED_SECURITY_EVENT',
    ReconciliationAuditBehavior.stateTransitionAudit =>
      'STATE_TRANSITION_AUDIT',
    ReconciliationAuditBehavior.reclaimAttemptAudit => 'RECLAIM_ATTEMPT_AUDIT',
    ReconciliationAuditBehavior.findingAndDisposition =>
      'FINDING_AND_DISPOSITION',
  };
}

enum ReconciliationTaxonomyCode {
  workEvaluationLinkMissing,
  workDecisionLinkMissing,
  workHaltApplicationLinkMissing,
  haltApplicationRolloutMismatch,
  rolloutApplicationReferenceMissing,
  scheduleWorkVersionMismatch,
  workLogicalKeyMismatch,
  auditReferenceMissing,
  auditChainInvalid,
  evaluationAggregateMismatch,
  decisionEvaluationMismatch,
  targetBindingMismatch,
  tenantScopeMismatch,
  unknownVersion,
  orphanWork,
  orphanApplication,
  staleActiveWork,
  expiredLease,
  retryExhausted,
}

extension ReconciliationTaxonomyCodeWire on ReconciliationTaxonomyCode {
  String get wireName => switch (this) {
    ReconciliationTaxonomyCode.workEvaluationLinkMissing =>
      'WORK_EVALUATION_LINK_MISSING',
    ReconciliationTaxonomyCode.workDecisionLinkMissing =>
      'WORK_DECISION_LINK_MISSING',
    ReconciliationTaxonomyCode.workHaltApplicationLinkMissing =>
      'WORK_HALT_APPLICATION_LINK_MISSING',
    ReconciliationTaxonomyCode.haltApplicationRolloutMismatch =>
      'HALT_APPLICATION_ROLLOUT_MISMATCH',
    ReconciliationTaxonomyCode.rolloutApplicationReferenceMissing =>
      'ROLLOUT_APPLICATION_REFERENCE_MISSING',
    ReconciliationTaxonomyCode.scheduleWorkVersionMismatch =>
      'SCHEDULE_WORK_VERSION_MISMATCH',
    ReconciliationTaxonomyCode.workLogicalKeyMismatch =>
      'WORK_LOGICAL_KEY_MISMATCH',
    ReconciliationTaxonomyCode.auditReferenceMissing =>
      'AUDIT_REFERENCE_MISSING',
    ReconciliationTaxonomyCode.auditChainInvalid => 'AUDIT_CHAIN_INVALID',
    ReconciliationTaxonomyCode.evaluationAggregateMismatch =>
      'EVALUATION_AGGREGATE_MISMATCH',
    ReconciliationTaxonomyCode.decisionEvaluationMismatch =>
      'DECISION_EVALUATION_MISMATCH',
    ReconciliationTaxonomyCode.targetBindingMismatch =>
      'TARGET_BINDING_MISMATCH',
    ReconciliationTaxonomyCode.tenantScopeMismatch => 'TENANT_SCOPE_MISMATCH',
    ReconciliationTaxonomyCode.unknownVersion => 'UNKNOWN_VERSION',
    ReconciliationTaxonomyCode.orphanWork => 'ORPHAN_WORK',
    ReconciliationTaxonomyCode.orphanApplication => 'ORPHAN_APPLICATION',
    ReconciliationTaxonomyCode.staleActiveWork => 'STALE_ACTIVE_WORK',
    ReconciliationTaxonomyCode.expiredLease => 'EXPIRED_LEASE',
    ReconciliationTaxonomyCode.retryExhausted => 'RETRY_EXHAUSTED',
  };
}

ReconciliationTaxonomyCode parseReconciliationTaxonomyCode(Object? value) {
  for (final item in ReconciliationTaxonomyCode.values) {
    if (item.wireName == value) return item;
  }
  throw const FormatException('Unsupported reconciliation taxonomy code');
}

/// Immutable source records are never rewritten by reconciliation.
enum ReconciliationImmutableSource {
  healthAggregate,
  healthAggregateRevision,
  healthEvaluation,
  rolloutDecision,
  healthHaltApplication,
  rolloutRevisionHistory,
  scheduleRevision,
  logicalWorkIdentity,
  policyDigest,
  targetBinding,
  p3aTransitionHistory,
  auditChain,
}

extension ReconciliationImmutableSourceWire on ReconciliationImmutableSource {
  String get wireName => switch (this) {
    ReconciliationImmutableSource.healthAggregate => 'HEALTH_AGGREGATE',
    ReconciliationImmutableSource.healthAggregateRevision =>
      'HEALTH_AGGREGATE_REVISION',
    ReconciliationImmutableSource.healthEvaluation => 'HEALTH_EVALUATION',
    ReconciliationImmutableSource.rolloutDecision => 'ROLLOUT_DECISION',
    ReconciliationImmutableSource.healthHaltApplication =>
      'HEALTH_HALT_APPLICATION',
    ReconciliationImmutableSource.rolloutRevisionHistory =>
      'ROLLOUT_REVISION_HISTORY',
    ReconciliationImmutableSource.scheduleRevision => 'SCHEDULE_REVISION',
    ReconciliationImmutableSource.logicalWorkIdentity =>
      'LOGICAL_WORK_IDENTITY',
    ReconciliationImmutableSource.policyDigest => 'POLICY_DIGEST',
    ReconciliationImmutableSource.targetBinding => 'TARGET_BINDING',
    ReconciliationImmutableSource.p3aTransitionHistory =>
      'P3A_TRANSITION_HISTORY',
    ReconciliationImmutableSource.auditChain => 'AUDIT_CHAIN',
  };
}

const Set<ReconciliationImmutableSource> reconciliationImmutableSources =
    <ReconciliationImmutableSource>{
      ReconciliationImmutableSource.healthAggregate,
      ReconciliationImmutableSource.healthAggregateRevision,
      ReconciliationImmutableSource.healthEvaluation,
      ReconciliationImmutableSource.rolloutDecision,
      ReconciliationImmutableSource.healthHaltApplication,
      ReconciliationImmutableSource.rolloutRevisionHistory,
      ReconciliationImmutableSource.scheduleRevision,
      ReconciliationImmutableSource.logicalWorkIdentity,
      ReconciliationImmutableSource.policyDigest,
      ReconciliationImmutableSource.targetBinding,
      ReconciliationImmutableSource.p3aTransitionHistory,
      ReconciliationImmutableSource.auditChain,
    };

enum ReconciliationProjectionTarget {
  workEvaluationLink,
  workDecisionLink,
  workHaltApplicationLink,
  workStatus,
  derivedReadModel,
  derivedDiagnostics,
}

extension ReconciliationProjectionTargetWire on ReconciliationProjectionTarget {
  String get wireName => switch (this) {
    ReconciliationProjectionTarget.workEvaluationLink => 'WORK_EVALUATION_LINK',
    ReconciliationProjectionTarget.workDecisionLink => 'WORK_DECISION_LINK',
    ReconciliationProjectionTarget.workHaltApplicationLink =>
      'WORK_HALT_APPLICATION_LINK',
    ReconciliationProjectionTarget.workStatus => 'WORK_STATUS',
    ReconciliationProjectionTarget.derivedReadModel => 'DERIVED_READ_MODEL',
    ReconciliationProjectionTarget.derivedDiagnostics => 'DERIVED_DIAGNOSTICS',
  };
}

bool isImmutableReconciliationSource(ReconciliationImmutableSource source) =>
    reconciliationImmutableSources.contains(source);

ReconciliationScope _scopeFromMap(Object? value) =>
    ReconciliationScope.fromJson(value);

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map) throw FormatException('Invalid $label');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('Invalid $label keys');
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _exactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String label,
) {
  if (value.length != expected.length ||
      value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    throw FormatException('Invalid $label fields');
  }
}

String _boundedString(
  Object? value,
  String field, {
  int maxLength = maximumReconciliationEntityLength,
}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      value.contains(RegExp(r'[\u0000\r\n]'))) {
    throw FormatException('Invalid $field');
  }
  return value;
}

String _boundedId(Object? value, String field) =>
    _boundedString(value, field, maxLength: maximumReconciliationIdLength);

String _safeCode(Object? value, String field) {
  final code = _boundedString(
    value,
    field,
    maxLength: maximumReconciliationSafeCodeLength,
  );
  if (!RegExp(r'^[A-Z][A-Z0-9_.-]*$').hasMatch(code)) {
    throw FormatException('Invalid $field');
  }
  return code;
}

String _safeKey(Object? value, String field) {
  final key = _boundedString(value, field, maxLength: 64);
  if (!RegExp(r'^[a-z][a-z0-9_.-]*$').hasMatch(key)) {
    throw FormatException('Invalid $field');
  }
  return key;
}

String _actor(Object? value) => _boundedString(
  value,
  'actor ID',
  maxLength: maximumReconciliationActorLength,
);

int _positiveInt(Object? value, String field, {int maximum = 0x7fffffff}) {
  if (value is! int || value <= 0 || value > maximum) {
    throw FormatException('Invalid $field');
  }
  return value;
}

int _nonNegativeInt(Object? value, String field, {int maximum = 0x7fffffff}) {
  if (value is! int || value < 0 || value > maximum) {
    throw FormatException('Invalid $field');
  }
  return value;
}

DateTime _utcTimestamp(Object? value, String field) {
  if (value is! String) throw FormatException('Invalid $field');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) throw FormatException('Invalid $field');
  return parsed;
}

DateTime _requireUtc(DateTime value, String field) {
  if (!value.isUtc) throw FormatException('$field must be UTC');
  return value;
}

String _digest(Object? value, String field) {
  if (value is! String) throw FormatException('Invalid $field');
  try {
    return requireSha256Digest(value);
  } on FormatException {
    throw FormatException('Invalid $field');
  }
}

Map<String, String> _digestMap(
  Object? value,
  String field, {
  int maximum = maximumReconciliationSourceDigests,
}) {
  final map = _object(value, field);
  if (map.isEmpty || map.length > maximum) {
    throw FormatException('Invalid $field count');
  }
  final result = <String, String>{};
  for (final entry in map.entries) {
    final key = _safeKey(entry.key, '$field key');
    result[key] = _digest(entry.value, '$field value');
  }
  return Map.unmodifiable(result);
}

Map<String, int> _versionMap(
  Object? value,
  String field, {
  int maximum = maximumReconciliationObservedVersions,
}) {
  final map = _object(value, field);
  if (map.length > maximum) throw FormatException('Invalid $field count');
  final result = <String, int>{};
  for (final entry in map.entries) {
    final key = _safeKey(entry.key, '$field key');
    result[key] = _nonNegativeInt(entry.value, '$field value');
  }
  return Map.unmodifiable(result);
}

Map<String, String> _boundedStringMap(
  Object? value,
  String field, {
  int maximum = maximumReconciliationTargetBindings,
}) {
  final map = _object(value, field);
  if (map.length > maximum) throw FormatException('Invalid $field count');
  final result = <String, String>{};
  for (final entry in map.entries) {
    result[_safeKey(entry.key, '$field key')] = _boundedString(
      entry.value,
      '$field value',
    );
  }
  return Map.unmodifiable(result);
}

String _canonicalDigest(Map<String, Object?> value) =>
    sha256Digest(utf8.encode(canonicalJson(value)));

String _canonicalWithLimit(
  Map<String, Object?> value,
  int maximumBytes,
  String label,
) {
  final serialized = canonicalJson(value);
  if (utf8.encode(serialized).length > maximumBytes) {
    throw FormatException('$label exceeds resource limit');
  }
  return serialized;
}

Map<String, Object?> _decodeCanonical(
  String source,
  int maximumBytes,
  String label,
) {
  if (utf8.encode(source).length > maximumBytes) {
    throw FormatException('$label exceeds resource limit');
  }
  final decoded = jsonDecode(source);
  final value = _object(decoded, label);
  if (canonicalJson(value) != source) {
    throw FormatException('$label is not canonical JSON');
  }
  return value;
}

String _scopedIdentity(String prefix, Map<String, Object?> semanticValue) =>
    '$prefix:${_canonicalDigest(semanticValue).substring(7)}';

bool _sameOrNarrowerScope(
  ReconciliationScope allowed,
  ReconciliationScope requested,
) {
  if (allowed.organizationId != requested.organizationId) return false;
  if (allowed.applicationId != null &&
      allowed.applicationId != requested.applicationId) {
    return false;
  }
  if (allowed.environmentId != null &&
      allowed.environmentId != requested.environmentId) {
    return false;
  }
  return true;
}

final class ReconciliationScope {
  const ReconciliationScope._({
    required this.organizationId,
    required this.applicationId,
    required this.environmentId,
  });

  factory ReconciliationScope({
    required String organizationId,
    String? applicationId,
    String? environmentId,
  }) {
    final organization = _scopeId(organizationId, 'organization ID');
    final application = applicationId == null
        ? null
        : _scopeId(applicationId, 'application ID');
    final environment = environmentId == null
        ? null
        : _scopeId(environmentId, 'environment ID');
    if (environment != null && application == null) {
      throw const FormatException(
        'Environment scope requires an application scope',
      );
    }
    return ReconciliationScope._(
      organizationId: organization,
      applicationId: application,
      environmentId: environment,
    );
  }

  final String organizationId;
  final String? applicationId;
  final String? environmentId;

  bool contains(ReconciliationScope requested) =>
      _sameOrNarrowerScope(this, requested);

  void requireContains(ReconciliationScope requested) {
    if (!contains(requested)) {
      throw const FormatException('Reconciliation scope is not permitted');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static ReconciliationScope fromJson(Object? value) {
    final map = _object(value, 'reconciliation scope');
    _exactKeys(map, const {
      'organizationId',
      'applicationId',
      'environmentId',
    }, 'reconciliation scope');
    return ReconciliationScope(
      organizationId: map['organizationId']! as String,
      applicationId: map['applicationId'] as String?,
      environmentId: map['environmentId'] as String?,
    );
  }
}

String _scopeId(Object? value, String field) {
  final id = _boundedString(value, field, maxLength: 128);
  if (!RegExp(r'^[a-z][a-z0-9_]{1,127}$').hasMatch(id)) {
    throw FormatException('Invalid $field');
  }
  return id;
}

final class ReconciliationPolicy {
  ReconciliationPolicy({
    this.schemaVersion = reconciliationSchemaVersion,
    required this.policyVersion,
    required this.maximumRecordsScanned,
    required this.maximumTenantsScanned,
    required this.maximumLinkageDepth,
    required this.maximumFindings,
    required this.maximumRepairs,
    required this.maximumConcurrentRepairs,
    required this.maximumRetryAttempts,
    required Duration lookbackHorizon,
    required this.maximumDiagnosticHistory,
    required this.maximumAuditLookupDepth,
    required this.fairnessPolicyVersion,
  }) : lookbackHorizon = lookbackHorizon {
    _validatePolicy(
      schemaVersion: schemaVersion,
      policyVersion: policyVersion,
      maximumRecordsScanned: maximumRecordsScanned,
      maximumTenantsScanned: maximumTenantsScanned,
      maximumLinkageDepth: maximumLinkageDepth,
      maximumFindings: maximumFindings,
      maximumRepairs: maximumRepairs,
      maximumConcurrentRepairs: maximumConcurrentRepairs,
      maximumRetryAttempts: maximumRetryAttempts,
      lookbackHorizon: this.lookbackHorizon,
      maximumDiagnosticHistory: maximumDiagnosticHistory,
      maximumAuditLookupDepth: maximumAuditLookupDepth,
      fairnessPolicyVersion: fairnessPolicyVersion,
    );
  }

  final int schemaVersion;
  final int policyVersion;
  final int maximumRecordsScanned;
  final int maximumTenantsScanned;
  final int maximumLinkageDepth;
  final int maximumFindings;
  final int maximumRepairs;
  final int maximumConcurrentRepairs;
  final int maximumRetryAttempts;
  final Duration lookbackHorizon;
  final int maximumDiagnosticHistory;
  final int maximumAuditLookupDepth;
  final int fairnessPolicyVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'policyVersion': policyVersion,
    'maximumRecordsScanned': maximumRecordsScanned,
    'maximumTenantsScanned': maximumTenantsScanned,
    'maximumLinkageDepth': maximumLinkageDepth,
    'maximumFindings': maximumFindings,
    'maximumRepairs': maximumRepairs,
    'maximumConcurrentRepairs': maximumConcurrentRepairs,
    'maximumRetryAttempts': maximumRetryAttempts,
    'lookbackHorizonSeconds': lookbackHorizon.inSeconds,
    'maximumDiagnosticHistory': maximumDiagnosticHistory,
    'maximumAuditLookupDepth': maximumAuditLookupDepth,
    'fairnessPolicyVersion': fairnessPolicyVersion,
  };

  String get canonicalSerialization => _canonicalWithLimit(
    toJson(),
    maximumReconciliationPolicyBytes,
    'Reconciliation policy',
  );

  String get digest => _canonicalDigest(toJson());

  static ReconciliationPolicy fromJson(Object? value) {
    final map = _object(value, 'reconciliation policy');
    _exactKeys(map, const {
      'schemaVersion',
      'policyVersion',
      'maximumRecordsScanned',
      'maximumTenantsScanned',
      'maximumLinkageDepth',
      'maximumFindings',
      'maximumRepairs',
      'maximumConcurrentRepairs',
      'maximumRetryAttempts',
      'lookbackHorizonSeconds',
      'maximumDiagnosticHistory',
      'maximumAuditLookupDepth',
      'fairnessPolicyVersion',
    }, 'reconciliation policy');
    return ReconciliationPolicy(
      schemaVersion: map['schemaVersion']! as int,
      policyVersion: map['policyVersion']! as int,
      maximumRecordsScanned: map['maximumRecordsScanned']! as int,
      maximumTenantsScanned: map['maximumTenantsScanned']! as int,
      maximumLinkageDepth: map['maximumLinkageDepth']! as int,
      maximumFindings: map['maximumFindings']! as int,
      maximumRepairs: map['maximumRepairs']! as int,
      maximumConcurrentRepairs: map['maximumConcurrentRepairs']! as int,
      maximumRetryAttempts: map['maximumRetryAttempts']! as int,
      lookbackHorizon: Duration(seconds: map['lookbackHorizonSeconds']! as int),
      maximumDiagnosticHistory: map['maximumDiagnosticHistory']! as int,
      maximumAuditLookupDepth: map['maximumAuditLookupDepth']! as int,
      fairnessPolicyVersion: map['fairnessPolicyVersion']! as int,
    );
  }

  static ReconciliationPolicy fromCanonicalJson(String source) => fromJson(
    _decodeCanonical(
      source,
      maximumReconciliationPolicyBytes,
      'Reconciliation policy',
    ),
  );
}

void _validatePolicy({
  required int schemaVersion,
  required int policyVersion,
  required int maximumRecordsScanned,
  required int maximumTenantsScanned,
  required int maximumLinkageDepth,
  required int maximumFindings,
  required int maximumRepairs,
  required int maximumConcurrentRepairs,
  required int maximumRetryAttempts,
  required Duration lookbackHorizon,
  required int maximumDiagnosticHistory,
  required int maximumAuditLookupDepth,
  required int fairnessPolicyVersion,
}) {
  if (schemaVersion != reconciliationSchemaVersion) {
    throw const FormatException('Unsupported reconciliation schema version');
  }
  if (policyVersion != supportedReconciliationPolicyVersion) {
    throw const FormatException('Unsupported reconciliation policy version');
  }
  if (fairnessPolicyVersion != supportedReconciliationFairnessPolicyVersion) {
    throw const FormatException(
      'Unsupported reconciliation fairness policy version',
    );
  }
  final values = <String, int>{
    'maximumRecordsScanned': maximumRecordsScanned,
    'maximumTenantsScanned': maximumTenantsScanned,
    'maximumLinkageDepth': maximumLinkageDepth,
    'maximumFindings': maximumFindings,
    'maximumRepairs': maximumRepairs,
    'maximumConcurrentRepairs': maximumConcurrentRepairs,
    'maximumRetryAttempts': maximumRetryAttempts,
    'maximumDiagnosticHistory': maximumDiagnosticHistory,
    'maximumAuditLookupDepth': maximumAuditLookupDepth,
  };
  for (final entry in values.entries) {
    _positiveInt(entry.value, entry.key);
  }
  if (lookbackHorizon <= Duration.zero) {
    throw const FormatException('Lookback horizon must be positive');
  }
  if (lookbackHorizon.inSeconds <= 0 ||
      lookbackHorizon.inSeconds > 0x7fffffff ||
      lookbackHorizon.inSeconds * 1000 != lookbackHorizon.inMilliseconds) {
    throw const FormatException(
      'Lookback horizon must be a positive whole number of seconds',
    );
  }
  if (maximumTenantsScanned > maximumRecordsScanned ||
      maximumFindings > maximumRecordsScanned ||
      maximumRepairs > maximumFindings ||
      maximumConcurrentRepairs > maximumRepairs ||
      maximumDiagnosticHistory > maximumFindings ||
      maximumAuditLookupDepth > maximumRecordsScanned) {
    throw const FormatException(
      'Reconciliation policy bounds are inconsistent',
    );
  }
}

final class ReconciliationCursor {
  ReconciliationCursor({
    this.schemaVersion = reconciliationSchemaVersion,
    required this.scope,
    String? position,
    required this.oldestUnresolvedAge,
    required this.perTenantCap,
    required this.globalCap,
  }) : position = position == null
           ? null
           : _boundedString(
               position,
               'cursor position',
               maxLength: maximumReconciliationCursorPositionLength,
             ) {
    if (schemaVersion != reconciliationSchemaVersion) {
      throw const FormatException('Unsupported reconciliation cursor version');
    }
    if (oldestUnresolvedAge < Duration.zero) {
      throw const FormatException('Cursor unresolved age cannot be negative');
    }
    if (oldestUnresolvedAge.inSeconds * 1000 !=
        oldestUnresolvedAge.inMilliseconds) {
      throw const FormatException(
        'Cursor unresolved age must be a whole number of seconds',
      );
    }
    _positiveInt(perTenantCap, 'cursor per-tenant cap');
    _positiveInt(globalCap, 'cursor global cap');
    if (perTenantCap > globalCap) {
      throw const FormatException('Cursor per-tenant cap exceeds global cap');
    }
  }

  final int schemaVersion;
  final ReconciliationScope scope;
  final String? position;
  final Duration oldestUnresolvedAge;
  final int perTenantCap;
  final int globalCap;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'scope': scope.toJson(),
    'position': position,
    'oldestUnresolvedAgeSeconds': oldestUnresolvedAge.inSeconds,
    'perTenantCap': perTenantCap,
    'globalCap': globalCap,
  };

  String get canonicalSerialization => _canonicalWithLimit(
    toJson(),
    maximumReconciliationCursorBytes,
    'Reconciliation cursor',
  );

  String get digest => _canonicalDigest(toJson());

  static ReconciliationCursor fromJson(Object? value) {
    final map = _object(value, 'reconciliation cursor');
    _exactKeys(map, const {
      'schemaVersion',
      'scope',
      'position',
      'oldestUnresolvedAgeSeconds',
      'perTenantCap',
      'globalCap',
    }, 'reconciliation cursor');
    return ReconciliationCursor(
      schemaVersion: map['schemaVersion']! as int,
      scope: _scopeFromMap(map['scope']),
      position: map['position'] as String?,
      oldestUnresolvedAge: Duration(
        seconds: map['oldestUnresolvedAgeSeconds']! as int,
      ),
      perTenantCap: map['perTenantCap']! as int,
      globalCap: map['globalCap']! as int,
    );
  }

  static ReconciliationCursor fromCanonicalJson(String source) => fromJson(
    _decodeCanonical(
      source,
      maximumReconciliationCursorBytes,
      'Reconciliation cursor',
    ),
  );
}

final class ReconciliationInvocation {
  ReconciliationInvocation({
    this.schemaVersion = reconciliationSchemaVersion,
    required String invocationId,
    required this.scope,
    required String actorId,
    required String principalId,
    required this.principalKind,
    required this.storageMode,
    required this.policy,
    required DateTime startedAt,
    this.cursor,
  }) : invocationId = _boundedId(invocationId, 'invocation ID'),
       actorId = _actor(actorId),
       principalId = _boundedId(principalId, 'principal ID'),
       startedAt = _requireUtc(startedAt, 'Invocation timestamp') {
    if (schemaVersion != reconciliationSchemaVersion) {
      throw const FormatException('Unsupported reconciliation schema version');
    }
    if (principalKind !=
        ReconciliationPrincipalKind.tenantScopedAdministrator) {
      throw const FormatException('Unsupported reconciliation principal kind');
    }
    if (cursor != null) scope.requireContains(cursor!.scope);
    final expected = deriveInvocationId(
      scope: scope,
      actorId: this.actorId,
      principalId: this.principalId,
      principalKind: principalKind,
      storageMode: storageMode,
      policy: policy,
      startedAt: this.startedAt,
      cursor: cursor,
    );
    if (this.invocationId != expected) {
      throw const FormatException(
        'Invocation ID does not match canonical identity',
      );
    }
  }

  factory ReconciliationInvocation.create({
    int schemaVersion = reconciliationSchemaVersion,
    required ReconciliationScope scope,
    required String actorId,
    required String principalId,
    ReconciliationPrincipalKind principalKind =
        ReconciliationPrincipalKind.tenantScopedAdministrator,
    required ReconciliationStorageMode storageMode,
    required ReconciliationPolicy policy,
    required DateTime startedAt,
    ReconciliationCursor? cursor,
  }) {
    final normalizedActor = _actor(actorId);
    final normalizedPrincipal = _boundedId(principalId, 'principal ID');
    final normalizedStartedAt = _requireUtc(startedAt, 'Invocation timestamp');
    final invocationId = deriveInvocationId(
      scope: scope,
      actorId: normalizedActor,
      principalId: normalizedPrincipal,
      principalKind: principalKind,
      storageMode: storageMode,
      policy: policy,
      startedAt: normalizedStartedAt,
      cursor: cursor,
    );
    return ReconciliationInvocation(
      schemaVersion: schemaVersion,
      invocationId: invocationId,
      scope: scope,
      actorId: normalizedActor,
      principalId: normalizedPrincipal,
      principalKind: principalKind,
      storageMode: storageMode,
      policy: policy,
      startedAt: normalizedStartedAt,
      cursor: cursor,
    );
  }

  final int schemaVersion;
  final String invocationId;
  final ReconciliationScope scope;
  final String actorId;
  final String principalId;
  final ReconciliationPrincipalKind principalKind;
  final ReconciliationStorageMode storageMode;
  final ReconciliationPolicy policy;
  final DateTime startedAt;
  final ReconciliationCursor? cursor;

  int get policyVersion => policy.policyVersion;
  Duration get lookbackHorizon => policy.lookbackHorizon;
  int get maximumRecords => policy.maximumRecordsScanned;
  int get maximumTenants => policy.maximumTenantsScanned;
  int get maximumLinkageDepth => policy.maximumLinkageDepth;
  int get maximumFindings => policy.maximumFindings;
  int get maximumRepairs => policy.maximumRepairs;
  int get maximumConcurrentRepairs => policy.maximumConcurrentRepairs;
  int get maximumRetryAttempts => policy.maximumRetryAttempts;
  int get maximumDiagnosticHistory => policy.maximumDiagnosticHistory;
  int get maximumAuditLookupDepth => policy.maximumAuditLookupDepth;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'invocationId': invocationId,
    'organizationId': scope.organizationId,
    'applicationId': scope.applicationId,
    'environmentId': scope.environmentId,
    'actorId': actorId,
    'principalId': principalId,
    'principalKind': principalKind.wireName,
    'storageMode': storageMode.wireName,
    'policyVersion': policy.policyVersion,
    'startedAt': startedAt.toIso8601String(),
    'lookbackHorizonSeconds': lookbackHorizon.inSeconds,
    'maximumRecords': maximumRecords,
    'maximumTenants': maximumTenants,
    'maximumLinkageDepth': maximumLinkageDepth,
    'maximumFindings': maximumFindings,
    'maximumRepairs': maximumRepairs,
    'maximumConcurrentRepairs': maximumConcurrentRepairs,
    'maximumRetryAttempts': maximumRetryAttempts,
    'maximumDiagnosticHistory': maximumDiagnosticHistory,
    'maximumAuditLookupDepth': maximumAuditLookupDepth,
    'fairnessPolicyVersion': policy.fairnessPolicyVersion,
    'cursor': cursor?.toJson(),
  };

  String get canonicalSerialization => _canonicalWithLimit(
    toJson(),
    maximumReconciliationInvocationBytes,
    'Reconciliation invocation',
  );

  String get digest => _canonicalDigest(toJson());

  static String deriveInvocationId({
    required ReconciliationScope scope,
    required String actorId,
    required String principalId,
    required ReconciliationPrincipalKind principalKind,
    required ReconciliationStorageMode storageMode,
    required ReconciliationPolicy policy,
    required DateTime startedAt,
    ReconciliationCursor? cursor,
  }) {
    final semantic = <String, Object?>{
      'scope': scope.toJson(),
      'actorId': _actor(actorId),
      'principalId': _boundedId(principalId, 'principal ID'),
      'principalKind': principalKind.wireName,
      'storageMode': storageMode.wireName,
      'policy': policy.toJson(),
      'startedAt': _requireUtc(
        startedAt,
        'Invocation timestamp',
      ).toIso8601String(),
      'cursor': cursor?.toJson(),
    };
    return _scopedIdentity('reconcile-invocation', semantic);
  }

  static ReconciliationInvocation fromJson(Object? value) {
    final map = _object(value, 'reconciliation invocation');
    _exactKeys(map, const {
      'schemaVersion',
      'invocationId',
      'organizationId',
      'applicationId',
      'environmentId',
      'actorId',
      'principalId',
      'principalKind',
      'storageMode',
      'policyVersion',
      'startedAt',
      'lookbackHorizonSeconds',
      'maximumRecords',
      'maximumTenants',
      'maximumLinkageDepth',
      'maximumFindings',
      'maximumRepairs',
      'maximumConcurrentRepairs',
      'maximumRetryAttempts',
      'maximumDiagnosticHistory',
      'maximumAuditLookupDepth',
      'fairnessPolicyVersion',
      'cursor',
    }, 'reconciliation invocation');
    final policy = ReconciliationPolicy(
      policyVersion: map['policyVersion']! as int,
      maximumRecordsScanned: map['maximumRecords']! as int,
      maximumTenantsScanned: map['maximumTenants']! as int,
      maximumLinkageDepth: map['maximumLinkageDepth']! as int,
      maximumFindings: map['maximumFindings']! as int,
      maximumRepairs: map['maximumRepairs']! as int,
      maximumConcurrentRepairs: map['maximumConcurrentRepairs']! as int,
      maximumRetryAttempts: map['maximumRetryAttempts']! as int,
      lookbackHorizon: Duration(seconds: map['lookbackHorizonSeconds']! as int),
      maximumDiagnosticHistory: map['maximumDiagnosticHistory']! as int,
      maximumAuditLookupDepth: map['maximumAuditLookupDepth']! as int,
      fairnessPolicyVersion: map['fairnessPolicyVersion']! as int,
    );
    return ReconciliationInvocation(
      schemaVersion: map['schemaVersion']! as int,
      invocationId: map['invocationId']! as String,
      scope: ReconciliationScope(
        organizationId: map['organizationId']! as String,
        applicationId: map['applicationId'] as String?,
        environmentId: map['environmentId'] as String?,
      ),
      actorId: map['actorId']! as String,
      principalId: map['principalId']! as String,
      principalKind: parseReconciliationPrincipalKind(map['principalKind']),
      storageMode: parseReconciliationStorageMode(map['storageMode']),
      policy: policy,
      startedAt: _utcTimestamp(map['startedAt'], 'invocation timestamp'),
      cursor: map['cursor'] == null
          ? null
          : ReconciliationCursor.fromJson(map['cursor']),
    );
  }

  static ReconciliationInvocation fromCanonicalJson(String source) => fromJson(
    _decodeCanonical(
      source,
      maximumReconciliationInvocationBytes,
      'Reconciliation invocation',
    ),
  );
}

final class ReconciliationTaxonomyMetadata {
  const ReconciliationTaxonomyMetadata({
    required this.code,
    required this.defaultSeverity,
    required this.repairability,
    required this.automaticAction,
    required this.operatorAction,
    required this.auditBehavior,
  });

  final ReconciliationTaxonomyCode code;
  final ReconciliationSeverity defaultSeverity;
  final ReconciliationRepairability repairability;
  final ReconciliationRepairAction? automaticAction;
  final ReconciliationOperatorAction operatorAction;
  final ReconciliationAuditBehavior auditBehavior;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code.wireName,
    'defaultSeverity': defaultSeverity.wireName,
    'repairability': repairability.wireName,
    'automaticAction': automaticAction?.wireName,
    'operatorAction': operatorAction.wireName,
    'auditBehavior': auditBehavior.wireName,
  };
}

const Map<ReconciliationTaxonomyCode, ReconciliationTaxonomyMetadata>
reconciliationTaxonomy =
    <ReconciliationTaxonomyCode, ReconciliationTaxonomyMetadata>{
      ReconciliationTaxonomyCode.workEvaluationLinkMissing:
          ReconciliationTaxonomyMetadata(
            code: ReconciliationTaxonomyCode.workEvaluationLinkMissing,
            defaultSeverity: ReconciliationSeverity.error,
            repairability: ReconciliationRepairability.repairableProjection,
            automaticAction: ReconciliationRepairAction.linkExistingEvaluation,
            operatorAction: ReconciliationOperatorAction.review,
            auditBehavior: ReconciliationAuditBehavior.findingAndRepairOutcome,
          ),
      ReconciliationTaxonomyCode.workDecisionLinkMissing:
          ReconciliationTaxonomyMetadata(
            code: ReconciliationTaxonomyCode.workDecisionLinkMissing,
            defaultSeverity: ReconciliationSeverity.error,
            repairability: ReconciliationRepairability.repairableProjection,
            automaticAction: ReconciliationRepairAction.linkExistingDecision,
            operatorAction: ReconciliationOperatorAction.review,
            auditBehavior: ReconciliationAuditBehavior.findingAndRepairOutcome,
          ),
      ReconciliationTaxonomyCode
          .workHaltApplicationLinkMissing: ReconciliationTaxonomyMetadata(
        code: ReconciliationTaxonomyCode.workHaltApplicationLinkMissing,
        defaultSeverity: ReconciliationSeverity.error,
        repairability: ReconciliationRepairability.repairableProjection,
        automaticAction: ReconciliationRepairAction.linkExistingHaltApplication,
        operatorAction: ReconciliationOperatorAction.review,
        auditBehavior: ReconciliationAuditBehavior.findingAndRepairOutcome,
      ),
      ReconciliationTaxonomyCode.haltApplicationRolloutMismatch:
          ReconciliationTaxonomyMetadata(
            code: ReconciliationTaxonomyCode.haltApplicationRolloutMismatch,
            defaultSeverity: ReconciliationSeverity.security,
            repairability:
                ReconciliationRepairability.reportOnlyImmutableDivergence,
            automaticAction: null,
            operatorAction: ReconciliationOperatorAction.investigate,
            auditBehavior: ReconciliationAuditBehavior.securityFinding,
          ),
      ReconciliationTaxonomyCode.rolloutApplicationReferenceMissing:
          ReconciliationTaxonomyMetadata(
            code: ReconciliationTaxonomyCode.rolloutApplicationReferenceMissing,
            defaultSeverity: ReconciliationSeverity.error,
            repairability:
                ReconciliationRepairability.reportOnlyImmutableDivergence,
            automaticAction: null,
            operatorAction: ReconciliationOperatorAction.investigate,
            auditBehavior: ReconciliationAuditBehavior.findingOnly,
          ),
      ReconciliationTaxonomyCode
          .scheduleWorkVersionMismatch: ReconciliationTaxonomyMetadata(
        code: ReconciliationTaxonomyCode.scheduleWorkVersionMismatch,
        defaultSeverity: ReconciliationSeverity.error,
        repairability: ReconciliationRepairability.recoverableOperationalState,
        automaticAction: null,
        operatorAction: ReconciliationOperatorAction.retryWithFreshScope,
        auditBehavior: ReconciliationAuditBehavior.findingAndRepairOutcome,
      ),
      ReconciliationTaxonomyCode.workLogicalKeyMismatch:
          ReconciliationTaxonomyMetadata(
            code: ReconciliationTaxonomyCode.workLogicalKeyMismatch,
            defaultSeverity: ReconciliationSeverity.security,
            repairability:
                ReconciliationRepairability.reportOnlyImmutableDivergence,
            automaticAction: null,
            operatorAction: ReconciliationOperatorAction.securityIncidentReview,
            auditBehavior: ReconciliationAuditBehavior.securityFinding,
          ),
      ReconciliationTaxonomyCode.auditReferenceMissing:
          ReconciliationTaxonomyMetadata(
            code: ReconciliationTaxonomyCode.auditReferenceMissing,
            defaultSeverity: ReconciliationSeverity.warning,
            repairability:
                ReconciliationRepairability.reportOnlyImmutableDivergence,
            automaticAction: null,
            operatorAction: ReconciliationOperatorAction.review,
            auditBehavior: ReconciliationAuditBehavior.findingOnly,
          ),
      ReconciliationTaxonomyCode.auditChainInvalid:
          ReconciliationTaxonomyMetadata(
            code: ReconciliationTaxonomyCode.auditChainInvalid,
            defaultSeverity: ReconciliationSeverity.critical,
            repairability:
                ReconciliationRepairability.reportOnlyImmutableDivergence,
            automaticAction: null,
            operatorAction: ReconciliationOperatorAction.securityIncidentReview,
            auditBehavior: ReconciliationAuditBehavior.redactedSecurityEvent,
          ),
      ReconciliationTaxonomyCode.evaluationAggregateMismatch:
          ReconciliationTaxonomyMetadata(
            code: ReconciliationTaxonomyCode.evaluationAggregateMismatch,
            defaultSeverity: ReconciliationSeverity.security,
            repairability:
                ReconciliationRepairability.reportOnlyImmutableDivergence,
            automaticAction: null,
            operatorAction: ReconciliationOperatorAction.securityIncidentReview,
            auditBehavior: ReconciliationAuditBehavior.securityFinding,
          ),
      ReconciliationTaxonomyCode.decisionEvaluationMismatch:
          ReconciliationTaxonomyMetadata(
            code: ReconciliationTaxonomyCode.decisionEvaluationMismatch,
            defaultSeverity: ReconciliationSeverity.security,
            repairability:
                ReconciliationRepairability.reportOnlyImmutableDivergence,
            automaticAction: null,
            operatorAction: ReconciliationOperatorAction.securityIncidentReview,
            auditBehavior: ReconciliationAuditBehavior.securityFinding,
          ),
      ReconciliationTaxonomyCode.targetBindingMismatch:
          ReconciliationTaxonomyMetadata(
            code: ReconciliationTaxonomyCode.targetBindingMismatch,
            defaultSeverity: ReconciliationSeverity.security,
            repairability:
                ReconciliationRepairability.reportOnlyImmutableDivergence,
            automaticAction: null,
            operatorAction: ReconciliationOperatorAction.securityIncidentReview,
            auditBehavior: ReconciliationAuditBehavior.securityFinding,
          ),
      ReconciliationTaxonomyCode.tenantScopeMismatch:
          ReconciliationTaxonomyMetadata(
            code: ReconciliationTaxonomyCode.tenantScopeMismatch,
            defaultSeverity: ReconciliationSeverity.critical,
            repairability:
                ReconciliationRepairability.reportOnlyImmutableDivergence,
            automaticAction: null,
            operatorAction: ReconciliationOperatorAction.securityIncidentReview,
            auditBehavior: ReconciliationAuditBehavior.redactedSecurityEvent,
          ),
      ReconciliationTaxonomyCode.unknownVersion: ReconciliationTaxonomyMetadata(
        code: ReconciliationTaxonomyCode.unknownVersion,
        defaultSeverity: ReconciliationSeverity.error,
        repairability:
            ReconciliationRepairability.reportOnlyImmutableDivergence,
        automaticAction: null,
        operatorAction: ReconciliationOperatorAction.upgradeOrMigrationDecision,
        auditBehavior: ReconciliationAuditBehavior.findingOnly,
      ),
      ReconciliationTaxonomyCode.orphanWork: ReconciliationTaxonomyMetadata(
        code: ReconciliationTaxonomyCode.orphanWork,
        defaultSeverity: ReconciliationSeverity.error,
        repairability:
            ReconciliationRepairability.reportOnlyImmutableDivergence,
        automaticAction: null,
        operatorAction: ReconciliationOperatorAction.manualDisposition,
        auditBehavior: ReconciliationAuditBehavior.findingAndDisposition,
      ),
      ReconciliationTaxonomyCode.orphanApplication:
          ReconciliationTaxonomyMetadata(
            code: ReconciliationTaxonomyCode.orphanApplication,
            defaultSeverity: ReconciliationSeverity.warning,
            repairability:
                ReconciliationRepairability.reportOnlyImmutableDivergence,
            automaticAction: null,
            operatorAction: ReconciliationOperatorAction.investigate,
            auditBehavior: ReconciliationAuditBehavior.findingOnly,
          ),
      ReconciliationTaxonomyCode
          .staleActiveWork: ReconciliationTaxonomyMetadata(
        code: ReconciliationTaxonomyCode.staleActiveWork,
        defaultSeverity: ReconciliationSeverity.warning,
        repairability: ReconciliationRepairability.recoverableOperationalState,
        automaticAction: ReconciliationRepairAction.markStale,
        operatorAction: ReconciliationOperatorAction.retryWithFreshScope,
        auditBehavior: ReconciliationAuditBehavior.stateTransitionAudit,
      ),
      ReconciliationTaxonomyCode.expiredLease: ReconciliationTaxonomyMetadata(
        code: ReconciliationTaxonomyCode.expiredLease,
        defaultSeverity: ReconciliationSeverity.info,
        repairability: ReconciliationRepairability.recoverableOperationalState,
        automaticAction: null,
        operatorAction: ReconciliationOperatorAction.existingRecoveryWorkflow,
        auditBehavior: ReconciliationAuditBehavior.reclaimAttemptAudit,
      ),
      ReconciliationTaxonomyCode.retryExhausted: ReconciliationTaxonomyMetadata(
        code: ReconciliationTaxonomyCode.retryExhausted,
        defaultSeverity: ReconciliationSeverity.warning,
        repairability: ReconciliationRepairability.recoverableOperationalState,
        automaticAction: ReconciliationRepairAction.markFailedPermanent,
        operatorAction: ReconciliationOperatorAction.manualDisposition,
        auditBehavior: ReconciliationAuditBehavior.findingAndDisposition,
      ),
    };

ReconciliationTaxonomyMetadata reconciliationMetadataFor(
  ReconciliationTaxonomyCode code,
) {
  final metadata = reconciliationTaxonomy[code];
  if (metadata == null) {
    throw const FormatException('Missing reconciliation taxonomy metadata');
  }
  return metadata;
}

final Set<String> reconciliationTaxonomyWireValues = Set.unmodifiable(
  ReconciliationTaxonomyCode.values.map((item) => item.wireName),
);

final class ReconciliationRepairActionPolicy {
  const ReconciliationRepairActionPolicy({
    required this.action,
    required this.allowedRepairabilities,
    required this.requiredScopes,
    required this.target,
    required this.rolloutMutationAllowed,
  });

  final ReconciliationRepairAction action;
  final Set<ReconciliationRepairability> allowedRepairabilities;
  final Set<String> requiredScopes;
  final ReconciliationProjectionTarget? target;
  final bool rolloutMutationAllowed;

  void validateFor(ReconciliationRepairability repairability) {
    if (!allowedRepairabilities.contains(repairability)) {
      throw const FormatException(
        'Repair action is not allowed for finding repairability',
      );
    }
    if (rolloutMutationAllowed) {
      throw const FormatException(
        'Reconciliation actions cannot mutate rollout state',
      );
    }
  }
}

/// Binding status for the frozen repair-action taxonomy. This is deliberately
/// separate from the wire action enum: a taxonomy action may be proven
/// unreachable or report-only without inventing a mutation API.
enum ReconciliationRepairBindingDisposition {
  bound,
  modelUnreachable,
  coveredByExistingOperation,
  reportOnly,
  notApplicable,
}

extension ReconciliationRepairBindingDispositionWire
    on ReconciliationRepairBindingDisposition {
  String get wireName => switch (this) {
    ReconciliationRepairBindingDisposition.bound => 'BOUND',
    ReconciliationRepairBindingDisposition.modelUnreachable =>
      'MODEL_UNREACHABLE',
    ReconciliationRepairBindingDisposition.coveredByExistingOperation =>
      'COVERED_BY_EXISTING_OPERATION',
    ReconciliationRepairBindingDisposition.reportOnly => 'REPORT_ONLY',
    ReconciliationRepairBindingDisposition.notApplicable => 'NOT_APPLICABLE',
  };
}

/// Exhaustive Task 70/71 action disposition. Keep this map total whenever a
/// taxonomy action is added; an absent entry is a review-time failure.
final Map<ReconciliationRepairAction, ReconciliationRepairBindingDisposition>
reconciliationRepairBindingDispositions = Map.unmodifiable(
  <ReconciliationRepairAction, ReconciliationRepairBindingDisposition>{
    ReconciliationRepairAction.linkExistingEvaluation:
        ReconciliationRepairBindingDisposition.bound,
    ReconciliationRepairAction.linkExistingDecision:
        ReconciliationRepairBindingDisposition.modelUnreachable,
    ReconciliationRepairAction.linkExistingHaltApplication:
        ReconciliationRepairBindingDisposition.bound,
    ReconciliationRepairAction.completeWorkFromExistingApplication:
        ReconciliationRepairBindingDisposition.coveredByExistingOperation,
    ReconciliationRepairAction.markStale:
        ReconciliationRepairBindingDisposition.bound,
    ReconciliationRepairAction.markFailedPermanent:
        ReconciliationRepairBindingDisposition.bound,
    ReconciliationRepairAction.rebuildDerivedProjection:
        ReconciliationRepairBindingDisposition.notApplicable,
    ReconciliationRepairAction.reportOnly:
        ReconciliationRepairBindingDisposition.reportOnly,
  },
);

ReconciliationRepairBindingDisposition reconciliationRepairBindingFor(
  ReconciliationRepairAction action,
) {
  final disposition = reconciliationRepairBindingDispositions[action];
  if (disposition == null) {
    throw const FormatException('Missing reconciliation action disposition');
  }
  return disposition;
}

final Map<ReconciliationRepairAction, ReconciliationRepairActionPolicy>
reconciliationRepairActionPolicies = Map.unmodifiable(<
  ReconciliationRepairAction,
  ReconciliationRepairActionPolicy
>{
  ReconciliationRepairAction.linkExistingEvaluation:
      const ReconciliationRepairActionPolicy(
        action: ReconciliationRepairAction.linkExistingEvaluation,
        allowedRepairabilities: <ReconciliationRepairability>{
          ReconciliationRepairability.repairableProjection,
        },
        requiredScopes: <String>{'health:reconcile', 'health:read'},
        target: ReconciliationProjectionTarget.workEvaluationLink,
        rolloutMutationAllowed: false,
      ),
  ReconciliationRepairAction.linkExistingDecision:
      const ReconciliationRepairActionPolicy(
        action: ReconciliationRepairAction.linkExistingDecision,
        allowedRepairabilities: <ReconciliationRepairability>{
          ReconciliationRepairability.repairableProjection,
        },
        requiredScopes: <String>{'health:reconcile', 'health:read'},
        target: ReconciliationProjectionTarget.workDecisionLink,
        rolloutMutationAllowed: false,
      ),
  ReconciliationRepairAction
      .linkExistingHaltApplication: const ReconciliationRepairActionPolicy(
    action: ReconciliationRepairAction.linkExistingHaltApplication,
    allowedRepairabilities: <ReconciliationRepairability>{
      ReconciliationRepairability.repairableProjection,
    },
    requiredScopes: <String>{'health:reconcile', 'health:read', 'rollout:read'},
    target: ReconciliationProjectionTarget.workHaltApplicationLink,
    rolloutMutationAllowed: false,
  ),
  ReconciliationRepairAction.completeWorkFromExistingApplication:
      const ReconciliationRepairActionPolicy(
        action: ReconciliationRepairAction.completeWorkFromExistingApplication,
        allowedRepairabilities: <ReconciliationRepairability>{
          ReconciliationRepairability.recoverableOperationalState,
        },
        requiredScopes: <String>{
          'health:reconcile',
          'health:read',
          'rollout:read',
        },
        target: ReconciliationProjectionTarget.workStatus,
        rolloutMutationAllowed: false,
      ),
  ReconciliationRepairAction.markStale: const ReconciliationRepairActionPolicy(
    action: ReconciliationRepairAction.markStale,
    allowedRepairabilities: <ReconciliationRepairability>{
      ReconciliationRepairability.recoverableOperationalState,
    },
    requiredScopes: <String>{'health:reconcile', 'health:read'},
    target: ReconciliationProjectionTarget.workStatus,
    rolloutMutationAllowed: false,
  ),
  ReconciliationRepairAction.markFailedPermanent:
      const ReconciliationRepairActionPolicy(
        action: ReconciliationRepairAction.markFailedPermanent,
        allowedRepairabilities: <ReconciliationRepairability>{
          ReconciliationRepairability.recoverableOperationalState,
        },
        requiredScopes: <String>{'health:reconcile', 'health:read'},
        target: ReconciliationProjectionTarget.workStatus,
        rolloutMutationAllowed: false,
      ),
  ReconciliationRepairAction.rebuildDerivedProjection:
      const ReconciliationRepairActionPolicy(
        action: ReconciliationRepairAction.rebuildDerivedProjection,
        allowedRepairabilities: <ReconciliationRepairability>{
          ReconciliationRepairability.repairableProjection,
        },
        requiredScopes: <String>{'health:reconcile', 'health:read'},
        target: ReconciliationProjectionTarget.derivedReadModel,
        rolloutMutationAllowed: false,
      ),
  ReconciliationRepairAction.reportOnly: const ReconciliationRepairActionPolicy(
    action: ReconciliationRepairAction.reportOnly,
    allowedRepairabilities: <ReconciliationRepairability>{
      ReconciliationRepairability.repairableProjection,
      ReconciliationRepairability.recoverableOperationalState,
      ReconciliationRepairability.reportOnlyImmutableDivergence,
    },
    requiredScopes: <String>{'health:reconcile', 'health:read'},
    target: null,
    rolloutMutationAllowed: false,
  ),
});

ReconciliationRepairActionPolicy reconciliationRepairPolicyFor(
  ReconciliationRepairAction action,
) {
  final policy = reconciliationRepairActionPolicies[action];
  if (policy == null) {
    throw const FormatException('Missing reconciliation repair-action policy');
  }
  return policy;
}

final class ReconciliationFinding {
  ReconciliationFinding({
    this.schemaVersion = reconciliationSchemaVersion,
    required String findingId,
    required this.scope,
    required this.code,
    required this.severity,
    required this.repairability,
    required String entityType,
    required String entityId,
    required Map<String, String> sourceDigests,
    required Map<String, int> observedVersions,
    required DateTime firstObservedAt,
    required DateTime lastObservedAt,
    required this.status,
    required String safeDetailCode,
  }) : findingId = _boundedId(findingId, 'finding ID'),
       entityType = _safeKey(entityType, 'entity type'),
       entityId = _boundedString(
         entityId,
         'entity ID',
         maxLength: maximumReconciliationEntityLength,
       ),
       sourceDigests = _validatedDigestMap(sourceDigests),
       observedVersions = _validatedVersionMap(observedVersions),
       firstObservedAt = _requireUtc(firstObservedAt, 'first observation time'),
       lastObservedAt = _requireUtc(lastObservedAt, 'last observation time'),
       safeDetailCode = _safeCode(safeDetailCode, 'safe detail code') {
    if (schemaVersion != reconciliationSchemaVersion) {
      throw const FormatException('Unsupported reconciliation schema version');
    }
    final metadata = reconciliationMetadataFor(code);
    if (severity != metadata.defaultSeverity ||
        repairability != metadata.repairability) {
      throw const FormatException(
        'Finding severity or repairability does not match taxonomy metadata',
      );
    }
    if (this.sourceDigests.isEmpty) {
      throw const FormatException('Finding requires source digests');
    }
    if (this.firstObservedAt.isAfter(this.lastObservedAt)) {
      throw const FormatException('Finding observation timestamps are invalid');
    }
    final expected = deriveFindingId(
      scope: scope,
      code: code,
      entityType: this.entityType,
      entityId: this.entityId,
      sourceDigests: this.sourceDigests,
      observedVersions: this.observedVersions,
    );
    if (this.findingId != expected) {
      throw const FormatException(
        'Finding ID does not match canonical identity',
      );
    }
  }

  factory ReconciliationFinding.create({
    int schemaVersion = reconciliationSchemaVersion,
    required ReconciliationScope scope,
    required ReconciliationTaxonomyCode code,
    required String entityType,
    required String entityId,
    required Map<String, String> sourceDigests,
    required Map<String, int> observedVersions,
    required DateTime firstObservedAt,
    required DateTime lastObservedAt,
    ReconciliationFindingStatus status = ReconciliationFindingStatus.open,
    required String safeDetailCode,
  }) {
    final normalizedEntityType = _safeKey(entityType, 'entity type');
    final normalizedEntityId = _boundedString(
      entityId,
      'entity ID',
      maxLength: maximumReconciliationEntityLength,
    );
    final normalizedDigests = _validatedDigestMap(sourceDigests);
    final normalizedVersions = _validatedVersionMap(observedVersions);
    final findingId = deriveFindingId(
      scope: scope,
      code: code,
      entityType: normalizedEntityType,
      entityId: normalizedEntityId,
      sourceDigests: normalizedDigests,
      observedVersions: normalizedVersions,
    );
    return ReconciliationFinding(
      schemaVersion: schemaVersion,
      findingId: findingId,
      scope: scope,
      code: code,
      severity: reconciliationMetadataFor(code).defaultSeverity,
      repairability: reconciliationMetadataFor(code).repairability,
      entityType: normalizedEntityType,
      entityId: normalizedEntityId,
      sourceDigests: normalizedDigests,
      observedVersions: normalizedVersions,
      firstObservedAt: firstObservedAt,
      lastObservedAt: lastObservedAt,
      status: status,
      safeDetailCode: safeDetailCode,
    );
  }

  final int schemaVersion;
  final String findingId;
  final ReconciliationScope scope;
  final ReconciliationTaxonomyCode code;
  final ReconciliationSeverity severity;
  final ReconciliationRepairability repairability;
  final String entityType;
  final String entityId;
  final Map<String, String> sourceDigests;
  final Map<String, int> observedVersions;
  final DateTime firstObservedAt;
  final DateTime lastObservedAt;
  final ReconciliationFindingStatus status;
  final String safeDetailCode;

  ReconciliationTaxonomyMetadata get metadata =>
      reconciliationMetadataFor(code);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'findingId': findingId,
    'scope': scope.toJson(),
    'code': code.wireName,
    'severity': severity.wireName,
    'repairability': repairability.wireName,
    'entityType': entityType,
    'entityId': entityId,
    'sourceDigests': sourceDigests,
    'observedVersions': observedVersions,
    'firstObservedAt': firstObservedAt.toIso8601String(),
    'lastObservedAt': lastObservedAt.toIso8601String(),
    'status': status.wireName,
    'safeDetailCode': safeDetailCode,
  };

  String get canonicalSerialization => _canonicalWithLimit(
    toJson(),
    maximumReconciliationFindingBytes,
    'Reconciliation finding',
  );

  String get digest => _canonicalDigest(toJson());

  void requireWithin(ReconciliationScope allowedScope) {
    allowedScope.requireContains(scope);
  }

  static String deriveFindingId({
    required ReconciliationScope scope,
    required ReconciliationTaxonomyCode code,
    required String entityType,
    required String entityId,
    required Map<String, String> sourceDigests,
    required Map<String, int> observedVersions,
  }) {
    final semantic = <String, Object?>{
      'scope': scope.toJson(),
      'code': code.wireName,
      'entityType': _safeKey(entityType, 'entity type'),
      'entityId': _boundedString(
        entityId,
        'entity ID',
        maxLength: maximumReconciliationEntityLength,
      ),
      'sourceDigests': _validatedDigestMap(sourceDigests),
      'observedVersions': _validatedVersionMap(observedVersions),
    };
    return _scopedIdentity('reconcile-finding', semantic);
  }

  static ReconciliationFinding fromJson(Object? value) {
    final map = _object(value, 'reconciliation finding');
    _exactKeys(map, const {
      'schemaVersion',
      'findingId',
      'scope',
      'code',
      'severity',
      'repairability',
      'entityType',
      'entityId',
      'sourceDigests',
      'observedVersions',
      'firstObservedAt',
      'lastObservedAt',
      'status',
      'safeDetailCode',
    }, 'reconciliation finding');
    return ReconciliationFinding(
      schemaVersion: map['schemaVersion']! as int,
      findingId: map['findingId']! as String,
      scope: _scopeFromMap(map['scope']),
      code: parseReconciliationTaxonomyCode(map['code']),
      severity: parseReconciliationSeverity(map['severity']),
      repairability: parseReconciliationRepairability(map['repairability']),
      entityType: map['entityType']! as String,
      entityId: map['entityId']! as String,
      sourceDigests: _digestMap(map['sourceDigests'], 'source digests'),
      observedVersions: _versionMap(
        map['observedVersions'],
        'observed versions',
      ),
      firstObservedAt: _utcTimestamp(
        map['firstObservedAt'],
        'first observation time',
      ),
      lastObservedAt: _utcTimestamp(
        map['lastObservedAt'],
        'last observation time',
      ),
      status: parseReconciliationFindingStatus(map['status']),
      safeDetailCode: map['safeDetailCode']! as String,
    );
  }

  static ReconciliationFinding fromCanonicalJson(String source) => fromJson(
    _decodeCanonical(
      source,
      maximumReconciliationFindingBytes,
      'Reconciliation finding',
    ),
  );
}

Map<String, String> _validatedDigestMap(Map<String, String> value) {
  if (value.isEmpty || value.length > maximumReconciliationSourceDigests) {
    throw const FormatException('Invalid source digest count');
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    result[_safeKey(entry.key, 'source digest key')] = _digest(
      entry.value,
      'source digest',
    );
  }
  return Map.unmodifiable(result);
}

Map<String, int> _validatedVersionMap(Map<String, int> value) {
  if (value.length > maximumReconciliationObservedVersions) {
    throw const FormatException('Invalid observed version count');
  }
  final result = <String, int>{};
  for (final entry in value.entries) {
    result[_safeKey(entry.key, 'observed version key')] = _nonNegativeInt(
      entry.value,
      'observed version',
    );
  }
  return Map.unmodifiable(result);
}

final class ReconciliationPrecondition {
  ReconciliationPrecondition({
    required this.scope,
    required String findingId,
    required String entityId,
    required this.expectedWorkVersion,
    required String? expectedScheduleRevision,
    required String? currentRolloutRevision,
    required Map<String, String> sourceDigests,
    required Map<String, String> targetBinding,
    required this.taxonomyCode,
    required this.action,
  }) : findingId = _boundedId(findingId, 'finding ID'),
       entityId = _boundedString(entityId, 'entity ID'),
       expectedScheduleRevision = expectedScheduleRevision == null
           ? null
           : _boundedId(expectedScheduleRevision, 'schedule revision'),
       currentRolloutRevision = currentRolloutRevision == null
           ? null
           : _boundedId(currentRolloutRevision, 'rollout revision'),
       sourceDigests = _validatedDigestMap(sourceDigests),
       targetBinding = _boundedStringMap(targetBinding, 'target binding') {
    if (expectedWorkVersion != null && expectedWorkVersion! < 0) {
      throw const FormatException('Expected work version cannot be negative');
    }
    if (this.sourceDigests.isEmpty) {
      throw const FormatException('Precondition requires source digests');
    }
    if (this.targetBinding.isEmpty) {
      throw const FormatException('Precondition requires target binding');
    }
  }

  final ReconciliationScope scope;
  final String findingId;
  final String entityId;
  final int? expectedWorkVersion;
  final String? expectedScheduleRevision;
  final String? currentRolloutRevision;
  final Map<String, String> sourceDigests;
  final Map<String, String> targetBinding;
  final ReconciliationTaxonomyCode taxonomyCode;
  final ReconciliationRepairAction action;

  Map<String, Object?> toJson() => <String, Object?>{
    'scope': scope.toJson(),
    'findingId': findingId,
    'entityId': entityId,
    'expectedWorkVersion': expectedWorkVersion,
    'expectedScheduleRevision': expectedScheduleRevision,
    'currentRolloutRevision': currentRolloutRevision,
    'sourceDigests': sourceDigests,
    'targetBinding': targetBinding,
    'taxonomyCode': taxonomyCode.wireName,
    'action': action.wireName,
  };

  String get canonicalSerialization => canonicalJson(toJson());

  String get digest => _canonicalDigest(toJson());

  void validateAgainst(ReconciliationFinding finding) {
    if (finding.scope.canonicalSerialization != scope.canonicalSerialization ||
        finding.findingId != findingId ||
        finding.entityId != entityId ||
        finding.code != taxonomyCode) {
      throw const FormatException(
        'Precondition does not match reconciliation finding',
      );
    }
    if (!_mapsEqual(finding.sourceDigests, sourceDigests)) {
      throw const FormatException('Precondition source digests are stale');
    }
    reconciliationRepairPolicyFor(action).validateFor(finding.repairability);
  }

  static ReconciliationPrecondition fromJson(Object? value) {
    final map = _object(value, 'reconciliation precondition');
    _exactKeys(map, const {
      'scope',
      'findingId',
      'entityId',
      'expectedWorkVersion',
      'expectedScheduleRevision',
      'currentRolloutRevision',
      'sourceDigests',
      'targetBinding',
      'taxonomyCode',
      'action',
    }, 'reconciliation precondition');
    return ReconciliationPrecondition(
      scope: _scopeFromMap(map['scope']),
      findingId: map['findingId']! as String,
      entityId: map['entityId']! as String,
      expectedWorkVersion: map['expectedWorkVersion'] as int?,
      expectedScheduleRevision: map['expectedScheduleRevision'] as String?,
      currentRolloutRevision: map['currentRolloutRevision'] as String?,
      sourceDigests: _digestMap(map['sourceDigests'], 'source digests'),
      targetBinding: _boundedStringMap(map['targetBinding'], 'target binding'),
      taxonomyCode: parseReconciliationTaxonomyCode(map['taxonomyCode']),
      action: parseReconciliationRepairAction(map['action']),
    );
  }
}

enum ReconciliationRepairAttemptComparison { newAttempt, replay, conflict }

final class ReconciliationRepairAttempt {
  ReconciliationRepairAttempt({
    this.schemaVersion = reconciliationSchemaVersion,
    required String repairId,
    required this.scope,
    required String findingId,
    required this.action,
    required String actorId,
    required this.expectedWorkVersion,
    required String? expectedScheduleRevision,
    required String preconditionDigest,
    required this.result,
    required String? safeErrorCode,
    required DateTime createdAt,
  }) : repairId = _boundedId(repairId, 'repair ID'),
       findingId = _boundedId(findingId, 'finding ID'),
       actorId = _actor(actorId),
       expectedScheduleRevision = expectedScheduleRevision == null
           ? null
           : _boundedId(expectedScheduleRevision, 'schedule revision'),
       preconditionDigest = _digest(preconditionDigest, 'precondition digest'),
       safeErrorCode = safeErrorCode == null
           ? null
           : _safeCode(safeErrorCode, 'safe error code'),
       createdAt = _requireUtc(createdAt, 'repair creation time') {
    if (schemaVersion != reconciliationSchemaVersion) {
      throw const FormatException('Unsupported reconciliation schema version');
    }
    if (expectedWorkVersion != null && expectedWorkVersion! < 0) {
      throw const FormatException('Expected work version cannot be negative');
    }
    final expectedId = deriveRepairId(findingId, action);
    if (this.repairId != expectedId) {
      throw const FormatException(
        'Repair ID does not match canonical identity',
      );
    }
    if (action == ReconciliationRepairAction.reportOnly &&
        result == ReconciliationRepairResult.applied) {
      throw const FormatException('Report-only action cannot be applied');
    }
    if (result == ReconciliationRepairResult.failed && safeErrorCode == null) {
      throw const FormatException('Failed repair requires a safe error code');
    }
    if (result == ReconciliationRepairResult.conflict &&
        safeErrorCode == null) {
      throw const FormatException(
        'Conflicting repair requires a safe error code',
      );
    }
  }

  factory ReconciliationRepairAttempt.create({
    int schemaVersion = reconciliationSchemaVersion,
    required ReconciliationFinding finding,
    required ReconciliationPrecondition precondition,
    required String actorId,
    required ReconciliationRepairResult result,
    String? safeErrorCode,
    required DateTime createdAt,
  }) {
    precondition.validateAgainst(finding);
    final normalizedActor = _actor(actorId);
    return ReconciliationRepairAttempt(
      schemaVersion: schemaVersion,
      repairId: deriveRepairId(finding.findingId, precondition.action),
      scope: finding.scope,
      findingId: finding.findingId,
      action: precondition.action,
      actorId: normalizedActor,
      expectedWorkVersion: precondition.expectedWorkVersion,
      expectedScheduleRevision: precondition.expectedScheduleRevision,
      preconditionDigest: precondition.digest,
      result: result,
      safeErrorCode: safeErrorCode,
      createdAt: createdAt,
    );
  }

  factory ReconciliationRepairAttempt.createAuthorized({
    int schemaVersion = reconciliationSchemaVersion,
    required ReconciliationPrincipal principal,
    required ReconciliationFinding finding,
    required ReconciliationPrecondition precondition,
    required ReconciliationRepairResult result,
    String? safeErrorCode,
    required DateTime now,
    required DateTime createdAt,
  }) {
    principal.authorizeAction(precondition.action, finding.scope, now: now);
    return ReconciliationRepairAttempt.create(
      schemaVersion: schemaVersion,
      finding: finding,
      precondition: precondition,
      actorId: principal.actorId,
      result: result,
      safeErrorCode: safeErrorCode,
      createdAt: createdAt,
    );
  }

  final int schemaVersion;
  final String repairId;
  final ReconciliationScope scope;
  final String findingId;
  final ReconciliationRepairAction action;
  final String actorId;
  final int? expectedWorkVersion;
  final String? expectedScheduleRevision;
  final String preconditionDigest;
  final ReconciliationRepairResult result;
  final String? safeErrorCode;
  final DateTime createdAt;

  static String deriveRepairId(
    String findingId,
    ReconciliationRepairAction action,
  ) =>
      'reconcile-repair:${_boundedId(findingId, 'finding ID')}:${action.wireName}';

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'repairId': repairId,
    'scope': scope.toJson(),
    'findingId': findingId,
    'action': action.wireName,
    'actorId': actorId,
    'expectedWorkVersion': expectedWorkVersion,
    'expectedScheduleRevision': expectedScheduleRevision,
    'preconditionDigest': preconditionDigest,
    'result': result.wireName,
    'safeErrorCode': safeErrorCode,
    'createdAt': createdAt.toIso8601String(),
  };

  String get canonicalSerialization => _canonicalWithLimit(
    toJson(),
    maximumReconciliationRepairAttemptBytes,
    'Reconciliation repair attempt',
  );

  String get digest => _canonicalDigest(toJson());

  ReconciliationRepairAttemptComparison compareWith(
    ReconciliationRepairAttempt other,
  ) {
    if (repairId != other.repairId) {
      return ReconciliationRepairAttemptComparison.newAttempt;
    }
    if (canonicalSerialization == other.canonicalSerialization) {
      return ReconciliationRepairAttemptComparison.replay;
    }
    return ReconciliationRepairAttemptComparison.conflict;
  }

  void requireWithin(ReconciliationScope allowedScope) {
    allowedScope.requireContains(scope);
  }

  static ReconciliationRepairAttempt fromJson(Object? value) {
    final map = _object(value, 'reconciliation repair attempt');
    _exactKeys(map, const {
      'schemaVersion',
      'repairId',
      'scope',
      'findingId',
      'action',
      'actorId',
      'expectedWorkVersion',
      'expectedScheduleRevision',
      'preconditionDigest',
      'result',
      'safeErrorCode',
      'createdAt',
    }, 'reconciliation repair attempt');
    return ReconciliationRepairAttempt(
      schemaVersion: map['schemaVersion']! as int,
      repairId: map['repairId']! as String,
      scope: _scopeFromMap(map['scope']),
      findingId: map['findingId']! as String,
      action: parseReconciliationRepairAction(map['action']),
      actorId: map['actorId']! as String,
      expectedWorkVersion: map['expectedWorkVersion'] as int?,
      expectedScheduleRevision: map['expectedScheduleRevision'] as String?,
      preconditionDigest: map['preconditionDigest']! as String,
      result: parseReconciliationRepairResult(map['result']),
      safeErrorCode: map['safeErrorCode'] as String?,
      createdAt: _utcTimestamp(map['createdAt'], 'repair creation time'),
    );
  }

  static ReconciliationRepairAttempt fromCanonicalJson(String source) =>
      fromJson(
        _decodeCanonical(
          source,
          maximumReconciliationRepairAttemptBytes,
          'Reconciliation repair attempt',
        ),
      );
}

bool _mapsEqual(Map<String, Object?> left, Map<String, Object?> right) =>
    canonicalJson(left) == canonicalJson(right);

final class ReconciliationPrincipal {
  ReconciliationPrincipal({
    this.schemaVersion = reconciliationSchemaVersion,
    required String principalId,
    required this.scope,
    required String actorId,
    required DateTime issuedAt,
    required DateTime expiresAt,
    this.rotationGeneration = 1,
    DateTime? revokedAt,
    String? revocationActorId,
  }) : principalId = _boundedId(principalId, 'principal ID'),
       actorId = _actor(actorId),
       issuedAt = _requireUtc(issuedAt, 'principal issue time'),
       expiresAt = _requireUtc(expiresAt, 'principal expiry time'),
       revokedAt = revokedAt == null
           ? null
           : _requireUtc(revokedAt, 'principal revocation time'),
       revocationActorId = revocationActorId == null
           ? null
           : _actor(revocationActorId) {
    if (schemaVersion != reconciliationSchemaVersion) {
      throw const FormatException(
        'Unsupported reconciliation principal version',
      );
    }
    if (scope.applicationId == null || scope.environmentId == null) {
      throw const FormatException(
        'Reconciliation principal requires exact application/environment scope',
      );
    }
    if (!expiresAt.isAfter(issuedAt)) {
      throw const FormatException('Principal expiry must follow issue time');
    }
    _positiveInt(rotationGeneration, 'principal rotation generation');
    if (this.revokedAt != null && this.revokedAt!.isBefore(this.issuedAt)) {
      throw const FormatException('Principal revocation precedes issue time');
    }
    if ((this.revokedAt == null) != (this.revocationActorId == null)) {
      throw const FormatException(
        'Principal revocation time and actor must be provided together',
      );
    }
    if (reconciliationScopes
        .intersection(reconciliationForbiddenScopes)
        .isNotEmpty) {
      throw const FormatException(
        'Reconciliation scope contains control authority',
      );
    }
  }

  final int schemaVersion;
  final String principalId;
  final ReconciliationScope scope;
  final String actorId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final int rotationGeneration;
  final DateTime? revokedAt;
  final String? revocationActorId;

  Set<String> get scopes => reconciliationScopes;

  ReconciliationPrincipal revokeAt({
    required DateTime at,
    required String actorId,
  }) {
    final timestamp = _requireUtc(at, 'principal revocation time');
    if (timestamp.isBefore(issuedAt)) {
      throw const FormatException('Principal revocation precedes issue time');
    }
    return ReconciliationPrincipal(
      schemaVersion: schemaVersion,
      principalId: principalId,
      scope: scope,
      actorId: this.actorId,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      rotationGeneration: rotationGeneration,
      revokedAt: timestamp,
      revocationActorId: actorId,
    );
  }

  ReconciliationPrincipal rotate({
    required String newPrincipalId,
    required String newActorId,
    required DateTime issuedAt,
    required DateTime expiresAt,
  }) => ReconciliationPrincipal(
    schemaVersion: schemaVersion,
    principalId: newPrincipalId,
    scope: scope,
    actorId: newActorId,
    issuedAt: issuedAt,
    expiresAt: expiresAt,
    rotationGeneration: rotationGeneration + 1,
  );

  bool isActiveAt(DateTime at) {
    final timestamp = _requireUtc(at, 'authorization time');
    return revokedAt == null &&
        !timestamp.isBefore(issuedAt) &&
        timestamp.isBefore(expiresAt);
  }

  void authorizeInvocation(
    ReconciliationInvocation invocation, {
    required DateTime now,
  }) {
    if (!isActiveAt(now)) {
      throw const FormatException('Reconciliation principal is not active');
    }
    if (invocation.principalId != principalId ||
        invocation.actorId != actorId ||
        invocation.principalKind !=
            ReconciliationPrincipalKind.tenantScopedAdministrator) {
      throw const FormatException('Invocation principal identity is invalid');
    }
    scope.requireContains(invocation.scope);
    if (invocation.scope.canonicalSerialization !=
        scope.canonicalSerialization) {
      throw const FormatException(
        'Reconciliation invocation must use the exact principal scope',
      );
    }
  }

  void authorizeAction(
    ReconciliationRepairAction action,
    ReconciliationScope requestedScope, {
    required DateTime now,
  }) {
    if (!isActiveAt(now)) {
      throw const FormatException('Reconciliation principal is not active');
    }
    scope.requireContains(requestedScope);
    final actionPolicy = reconciliationRepairPolicyFor(action);
    if (!scopes.containsAll(actionPolicy.requiredScopes)) {
      throw const FormatException(
        'Reconciliation principal lacks action scope',
      );
    }
    if (actionPolicy.rolloutMutationAllowed) {
      throw const FormatException(
        'Reconciliation principal cannot mutate rollout state',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'principalId': principalId,
    'scope': scope.toJson(),
    'actorId': actorId,
    'scopes': scopes.toList()..sort(),
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'rotationGeneration': rotationGeneration,
    'revokedAt': revokedAt?.toIso8601String(),
    'revocationActorId': revocationActorId,
  };

  String get canonicalSerialization => _canonicalWithLimit(
    toJson(),
    maximumReconciliationPrincipalBytes,
    'Reconciliation principal',
  );

  String get digest => _canonicalDigest(toJson());

  static ReconciliationPrincipal fromJson(Object? value) {
    final map = _object(value, 'reconciliation principal');
    _exactKeys(map, const {
      'schemaVersion',
      'principalId',
      'scope',
      'actorId',
      'scopes',
      'issuedAt',
      'expiresAt',
      'rotationGeneration',
      'revokedAt',
      'revocationActorId',
    }, 'reconciliation principal');
    final rawScopes = map['scopes'];
    if (rawScopes is! List ||
        rawScopes.any((item) => item is! String) ||
        !Set<String>.from(rawScopes.cast<String>())
            .containsAll(reconciliationScopes) ||
        Set<String>.from(rawScopes.cast<String>()).length !=
            reconciliationScopes.length) {
      throw const FormatException(
        'Reconciliation principal scopes are invalid',
      );
    }
    return ReconciliationPrincipal(
      schemaVersion: map['schemaVersion']! as int,
      principalId: map['principalId']! as String,
      scope: _scopeFromMap(map['scope']),
      actorId: map['actorId']! as String,
      issuedAt: _utcTimestamp(map['issuedAt'], 'principal issue time'),
      expiresAt: _utcTimestamp(map['expiresAt'], 'principal expiry time'),
      rotationGeneration: map['rotationGeneration']! as int,
      revokedAt: map['revokedAt'] == null
          ? null
          : _utcTimestamp(map['revokedAt'], 'principal revocation time'),
      revocationActorId: map['revocationActorId'] as String?,
    );
  }

  static ReconciliationPrincipal fromCanonicalJson(String source) => fromJson(
    _decodeCanonical(
      source,
      maximumReconciliationPrincipalBytes,
      'Reconciliation principal',
    ),
  );
}

enum ReconciliationAuditEventType {
  invocationRequested,
  findingRecorded,
  repairRequested,
  repairRejected,
  principalIssued,
  principalRevoked,
}

extension ReconciliationAuditEventTypeWire on ReconciliationAuditEventType {
  String get wireName => switch (this) {
    ReconciliationAuditEventType.invocationRequested =>
      'reconciliation.invocation_requested',
    ReconciliationAuditEventType.findingRecorded =>
      'reconciliation.finding_recorded',
    ReconciliationAuditEventType.repairRequested =>
      'reconciliation.repair_requested',
    ReconciliationAuditEventType.repairRejected =>
      'reconciliation.repair_rejected',
    ReconciliationAuditEventType.principalIssued =>
      'reconciliation.principal_issued',
    ReconciliationAuditEventType.principalRevoked =>
      'reconciliation.principal_revoked',
  };
}

ReconciliationAuditEventType parseReconciliationAuditEventType(Object? value) {
  for (final item in ReconciliationAuditEventType.values) {
    if (item.wireName == value) return item;
  }
  throw const FormatException('Unsupported reconciliation audit event type');
}

final class ReconciliationAuditEvent {
  ReconciliationAuditEvent({
    this.schemaVersion = reconciliationSchemaVersion,
    required this.eventType,
    required this.scope,
    required String actorId,
    required String resourceId,
    ReconciliationTaxonomyCode? taxonomyCode,
    ReconciliationRepairAction? action,
    ReconciliationRepairResult? result,
    String? safeErrorCode,
    int? boundedCount,
    required DateTime createdAt,
  }) : actorId = _actor(actorId),
       resourceId = _boundedId(resourceId, 'audit resource ID'),
       taxonomyCode = taxonomyCode,
       action = action,
       result = result,
       safeErrorCode = safeErrorCode == null
           ? null
           : _safeCode(safeErrorCode, 'safe error code'),
       boundedCount = boundedCount,
       createdAt = _requireUtc(createdAt, 'audit event time') {
    if (schemaVersion != reconciliationSchemaVersion) {
      throw const FormatException('Unsupported reconciliation audit version');
    }
    if (boundedCount != null && boundedCount < 0) {
      throw const FormatException('Audit count cannot be negative');
    }
    if ((eventType == ReconciliationAuditEventType.repairRequested &&
            result != ReconciliationRepairResult.requested) ||
        (eventType == ReconciliationAuditEventType.repairRejected &&
            (result == null ||
                result == ReconciliationRepairResult.applied ||
                result == ReconciliationRepairResult.replayed)) ||
        (eventType != ReconciliationAuditEventType.repairRequested &&
            eventType != ReconciliationAuditEventType.repairRejected &&
            result != null)) {
      throw const FormatException('Audit event result is not permitted');
    }
  }

  final int schemaVersion;
  final ReconciliationAuditEventType eventType;
  final ReconciliationScope scope;
  final String actorId;
  final String resourceId;
  final ReconciliationTaxonomyCode? taxonomyCode;
  final ReconciliationRepairAction? action;
  final ReconciliationRepairResult? result;
  final String? safeErrorCode;
  final int? boundedCount;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'eventType': eventType.wireName,
    'scope': scope.toJson(),
    'actorId': actorId,
    'resourceId': resourceId,
    'taxonomyCode': taxonomyCode?.wireName,
    'action': action?.wireName,
    'result': result?.wireName,
    'safeErrorCode': safeErrorCode,
    'boundedCount': boundedCount,
    'createdAt': createdAt.toIso8601String(),
  };

  String get canonicalSerialization => _canonicalWithLimit(
    toJson(),
    maximumReconciliationAuditEventBytes,
    'Reconciliation audit event',
  );

  String get digest => _canonicalDigest(toJson());

  static ReconciliationAuditEvent fromJson(Object? value) {
    final map = _object(value, 'reconciliation audit event');
    _exactKeys(map, const {
      'schemaVersion',
      'eventType',
      'scope',
      'actorId',
      'resourceId',
      'taxonomyCode',
      'action',
      'result',
      'safeErrorCode',
      'boundedCount',
      'createdAt',
    }, 'reconciliation audit event');
    return ReconciliationAuditEvent(
      schemaVersion: map['schemaVersion']! as int,
      eventType: parseReconciliationAuditEventType(map['eventType']),
      scope: _scopeFromMap(map['scope']),
      actorId: map['actorId']! as String,
      resourceId: map['resourceId']! as String,
      taxonomyCode: map['taxonomyCode'] == null
          ? null
          : parseReconciliationTaxonomyCode(map['taxonomyCode']),
      action: map['action'] == null
          ? null
          : parseReconciliationRepairAction(map['action']),
      result: map['result'] == null
          ? null
          : parseReconciliationRepairResult(map['result']),
      safeErrorCode: map['safeErrorCode'] as String?,
      boundedCount: map['boundedCount'] as int?,
      createdAt: _utcTimestamp(map['createdAt'], 'audit event time'),
    );
  }

  static ReconciliationAuditEvent fromCanonicalJson(String source) => fromJson(
    _decodeCanonical(
      source,
      maximumReconciliationAuditEventBytes,
      'Reconciliation audit event',
    ),
  );
}
