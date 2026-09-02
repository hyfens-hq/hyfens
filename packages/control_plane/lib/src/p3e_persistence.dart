import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

import 'aggregation.dart';
import 'encoding.dart';
import 'errors.dart';
import 'p3e_halt.dart';

const int p3ePersistenceSchemaVersion = 1;
const int supportedP3eEvaluationVersion = 1;
const int supportedP3eThresholdSetVersion = 1;
const int supportedP3ePrivacyPolicyVersion = 1;

/// Storage safety bounds. These are resource limits, not health thresholds or
/// retention policy; callers may inject stricter deployment-specific values.
final class P3ePersistenceLimits {
  const P3ePersistenceLimits({
    this.maximumRecordBytes = 4 * 1024 * 1024,
    this.maximumLineageDepth = 128,
    this.maximumReconciliationBatch = 10000,
  });

  final int maximumRecordBytes;
  final int maximumLineageDepth;
  final int maximumReconciliationBatch;

  void validate() {
    if (maximumRecordBytes <= 0 ||
        maximumLineageDepth <= 0 ||
        maximumReconciliationBatch <= 0) {
      throw const FormatException('P3E persistence limits are invalid');
    }
  }
}

/// Forward-only P3E-2 schema migration. The application runs this list under
/// the same advisory transaction lock as the existing control-plane schema.
const List<String> p3ePostgresMigration003 = <String>[
  '''CREATE TABLE IF NOT EXISTS control_plane_p3e_aggregates (
  organization_id text NOT NULL,
  aggregate_id text NOT NULL,
  revision_id text NOT NULL,
  aggregate_digest text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, aggregate_id)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e_aggregates_revision_idx
  ON control_plane_p3e_aggregates
    (organization_id, revision_id, aggregate_id)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_p3e_aggregate_revisions (
  organization_id text NOT NULL,
  aggregate_revision_id text NOT NULL,
  aggregate_id text NOT NULL,
  parent_aggregate_revision_id text,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, aggregate_revision_id),
  UNIQUE (organization_id, aggregate_id, aggregate_revision_id),
  FOREIGN KEY (organization_id, aggregate_id)
    REFERENCES control_plane_p3e_aggregates(organization_id, aggregate_id)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e_revisions_aggregate_idx
  ON control_plane_p3e_aggregate_revisions
    (organization_id, aggregate_id, created_at, aggregate_revision_id)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_p3e_evaluations (
  organization_id text NOT NULL,
  evaluation_id text NOT NULL,
  aggregate_revision_id text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, evaluation_id),
  FOREIGN KEY (organization_id, aggregate_revision_id)
    REFERENCES control_plane_p3e_aggregate_revisions
      (organization_id, aggregate_revision_id)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e_evaluations_revision_idx
  ON control_plane_p3e_evaluations
    (organization_id, aggregate_revision_id, created_at, evaluation_id)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_p3e_decisions (
  organization_id text NOT NULL,
  decision_id text NOT NULL,
  evaluation_id text NOT NULL,
  aggregate_revision_id text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, decision_id),
  FOREIGN KEY (organization_id, evaluation_id)
    REFERENCES control_plane_p3e_evaluations(organization_id, evaluation_id),
  FOREIGN KEY (organization_id, aggregate_revision_id)
    REFERENCES control_plane_p3e_aggregate_revisions
      (organization_id, aggregate_revision_id)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e_decisions_rollout_idx
  ON control_plane_p3e_decisions
    (organization_id, created_at, decision_id)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_p3e_cursors (
  organization_id text NOT NULL,
  cursor_id text NOT NULL,
  aggregate_id text NOT NULL,
  input_digest text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, cursor_id),
  FOREIGN KEY (organization_id, aggregate_id)
    REFERENCES control_plane_p3e_aggregates(organization_id, aggregate_id)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e_cursors_aggregate_idx
  ON control_plane_p3e_cursors
    (organization_id, aggregate_id, cursor_id)''',
];

/// P3E-4 append-only linkage between immutable health decisions and the
/// existing rollout transition CAS. The original decision is never updated.
const List<String> p3ePostgresMigration004 = <String>[
  '''CREATE TABLE IF NOT EXISTS control_plane_p3e_halt_applications (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  decision_id text NOT NULL,
  evaluation_id text NOT NULL,
  aggregate_revision_id text NOT NULL,
  rollout_id text NOT NULL,
  expected_rollout_revision bigint NOT NULL CHECK (expected_rollout_revision > 0),
  result text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, application_id),
  FOREIGN KEY (organization_id, decision_id)
    REFERENCES control_plane_p3e_decisions(organization_id, decision_id),
  FOREIGN KEY (organization_id, evaluation_id)
    REFERENCES control_plane_p3e_evaluations(organization_id, evaluation_id),
  FOREIGN KEY (organization_id, aggregate_revision_id)
    REFERENCES control_plane_p3e_aggregate_revisions
      (organization_id, aggregate_revision_id)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e_halt_applications_decision_idx
  ON control_plane_p3e_halt_applications
    (organization_id, decision_id, created_at, application_id)''',
];

enum P3eRecomputability {
  rawRecomputable,
  rawExpired,
  rawDeletedByPolicy,
  inputIncomplete,
}

extension P3eRecomputabilityWire on P3eRecomputability {
  String get wireName => switch (this) {
    P3eRecomputability.rawRecomputable => 'RAW_RECOMPUTABLE',
    P3eRecomputability.rawExpired => 'RAW_EXPIRED',
    P3eRecomputability.rawDeletedByPolicy => 'RAW_DELETED_BY_POLICY',
    P3eRecomputability.inputIncomplete => 'INPUT_INCOMPLETE',
  };
}

P3eRecomputability parseP3eRecomputability(Object? value) => switch (value) {
  'RAW_RECOMPUTABLE' => P3eRecomputability.rawRecomputable,
  'RAW_EXPIRED' => P3eRecomputability.rawExpired,
  'RAW_DELETED_BY_POLICY' => P3eRecomputability.rawDeletedByPolicy,
  'INPUT_INCOMPLETE' => P3eRecomputability.inputIncomplete,
  _ => throw const FormatException('Unsupported P3E recomputability state'),
};

const Set<String> p3eDecisionValues = <String>{
  'INSUFFICIENT_DATA',
  'CONTINUE',
  'HOLD',
  'HALT_NEW_OFFERS',
  'MANUAL_REVIEW',
};

const Set<String> p3eReasonClasses = <String>{
  'PATCH_SAFETY',
  'DELIVERY_HEALTH',
  'OBSERVATION_HEALTH',
  'DATA_QUALITY',
  'OPERATOR_POLICY',
};

const Set<String> p3eCoverageStates = <String>{
  'SUFFICIENT',
  'INSUFFICIENT',
  'NOT_EVALUABLE',
};

const Set<String> p3eFreshnessStates = <String>{'FRESH', 'STALE', 'UNKNOWN'};

const Set<String> p3eSampleStates = <String>{
  'PASSED',
  'INSUFFICIENT',
  'NOT_EVALUABLE',
};

final RegExp _p3eIdPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_.:-]{0,127}$');

String _p3eId(String value, String label) {
  if (!_p3eIdPattern.hasMatch(value)) throw FormatException('Invalid $label');
  return value;
}

String _p3eRequiredString(Object? value, String label, {int maxLength = 256}) {
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('Invalid $label');
  }
  return value;
}

String? _p3eOptionalString(Object? value, String label) {
  if (value == null) return null;
  return _p3eRequiredString(value, label);
}

int _p3eNonNegativeInt(Object? value, String label) {
  if (value is! int || value < 0) throw FormatException('Invalid $label');
  return value;
}

int _p3ePositiveInt(Object? value, String label) {
  final parsed = _p3eNonNegativeInt(value, label);
  if (parsed <= 0) throw FormatException('Invalid $label');
  return parsed;
}

DateTime _p3eTimestamp(Object? value, String label) {
  final text = _p3eRequiredString(value, label);
  try {
    return DateTime.parse(text).toUtc();
  } on FormatException {
    throw FormatException('Invalid $label');
  }
}

Map<String, Object?> _p3eObject(Object? value, String label) {
  if (value is! Map) throw FormatException('Invalid $label object');
  final map = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('Invalid $label key');
    map[entry.key as String] = entry.value;
  }
  return map;
}

void _p3eExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String label,
) {
  if (value.length != expected.length ||
      value.keys.any((key) => !expected.contains(key))) {
    throw FormatException('Invalid $label fields');
  }
}

void _p3eEntityVersion(Object? value, String label) {
  if (value != p3ePersistenceSchemaVersion) {
    throw FormatException('Unsupported $label entity version');
  }
}

final class HealthAggregateRevision {
  HealthAggregateRevision({
    required String aggregateRevisionId,
    required String aggregateId,
    required this.parentAggregateRevisionId,
    required this.identity,
    required this.window,
    required this.aggregationVersion,
    required this.inputCount,
    required String inputDigest,
    required String recomputationReason,
    required this.recomputability,
    required DateTime createdAt,
  }) : aggregateRevisionId = _p3eId(
         aggregateRevisionId,
         'aggregate revision ID',
       ),
       aggregateId = _p3eId(aggregateId, 'aggregate ID'),
       inputDigest = requireSha256Digest(inputDigest),
       recomputationReason = _p3eRequiredString(
         recomputationReason,
         'recomputation reason',
       ),
       createdAt = createdAt.toUtc() {
    if (identity.organizationId.isEmpty || inputCount < 0) {
      throw const FormatException('Invalid aggregate revision binding');
    }
    if (parentAggregateRevisionId != null) {
      _p3eId(parentAggregateRevisionId!, 'parent aggregate revision ID');
      if (parentAggregateRevisionId == aggregateRevisionId) {
        throw const FormatException('Aggregate revision cannot parent itself');
      }
    }
    if (identity.aggregationVersion != aggregationVersion ||
        identity.windowId != window.windowId ||
        identity.windowStart != window.serverStart ||
        identity.windowEnd != window.serverEnd ||
        identity.lateCutoff != window.lateCutoff) {
      throw const FormatException('Aggregate revision binding is inconsistent');
    }
  }

  final String aggregateRevisionId;
  final String aggregateId;
  final String? parentAggregateRevisionId;
  final AggregateIdentity identity;
  final ObservationWindow window;
  final int aggregationVersion;
  final int inputCount;
  final String inputDigest;
  final String recomputationReason;
  final P3eRecomputability recomputability;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': p3ePersistenceSchemaVersion,
    'organizationId': identity.organizationId,
    'aggregateRevisionId': aggregateRevisionId,
    'aggregateId': aggregateId,
    'parentAggregateRevisionId': parentAggregateRevisionId,
    'identity': identity.toJson(),
    'window': window.toJson(),
    'aggregationVersion': aggregationVersion,
    'inputCount': inputCount,
    'inputDigest': inputDigest,
    'recomputationReason': recomputationReason,
    'recomputability': recomputability.wireName,
    'createdAt': createdAt.toIso8601String(),
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static HealthAggregateRevision fromJson(Object? value) {
    final map = _p3eObject(value, 'aggregate revision');
    _p3eExactKeys(map, const {
      'entityVersion',
      'organizationId',
      'aggregateRevisionId',
      'aggregateId',
      'parentAggregateRevisionId',
      'identity',
      'window',
      'aggregationVersion',
      'inputCount',
      'inputDigest',
      'recomputationReason',
      'recomputability',
      'createdAt',
    }, 'aggregate revision');
    _p3eEntityVersion(map['entityVersion'], 'aggregate revision');
    final identity = AggregateIdentity.fromJson(map['identity']);
    final revision = HealthAggregateRevision(
      aggregateRevisionId: _p3eRequiredString(
        map['aggregateRevisionId'],
        'aggregate revision ID',
      ),
      aggregateId: _p3eRequiredString(map['aggregateId'], 'aggregate ID'),
      parentAggregateRevisionId: _p3eOptionalString(
        map['parentAggregateRevisionId'],
        'parent aggregate revision ID',
      ),
      identity: identity,
      window: ObservationWindow.fromJson(map['window']),
      aggregationVersion: _p3ePositiveInt(
        map['aggregationVersion'],
        'aggregation version',
      ),
      inputCount: _p3eNonNegativeInt(map['inputCount'], 'input count'),
      inputDigest: _p3eRequiredString(map['inputDigest'], 'input digest'),
      recomputationReason: _p3eRequiredString(
        map['recomputationReason'],
        'recomputation reason',
      ),
      recomputability: parseP3eRecomputability(map['recomputability']),
      createdAt: _p3eTimestamp(map['createdAt'], 'created at'),
    );
    if (map['organizationId'] != identity.organizationId) {
      throw const FormatException('Aggregate revision tenant mismatch');
    }
    return revision;
  }
}

final class HealthAggregateRecord {
  HealthAggregateRecord({
    required String aggregateId,
    required this.revisionId,
    required this.aggregate,
    required this.recomputability,
    required DateTime createdAt,
  }) : aggregateId = _p3eId(aggregateId, 'aggregate ID'),
       createdAt = createdAt.toUtc() {
    if (aggregate.identity.organizationId.isEmpty) {
      throw const FormatException('Aggregate tenant is required');
    }
    _p3eId(revisionId, 'aggregate revision ID');
  }

  final String aggregateId;
  final String revisionId;
  final HealthAggregate aggregate;
  final P3eRecomputability recomputability;
  final DateTime createdAt;

  String get organizationId => aggregate.identity.organizationId;

  String get aggregateDigest =>
      sha256Digest(utf8.encode(aggregate.canonicalSerialization));

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': p3ePersistenceSchemaVersion,
    'organizationId': organizationId,
    'aggregateId': aggregateId,
    'revisionId': revisionId,
    'aggregateDigest': aggregateDigest,
    'aggregate': aggregate.toJson(),
    'recomputability': recomputability.wireName,
    'createdAt': createdAt.toIso8601String(),
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static HealthAggregateRecord fromJson(Object? value) {
    final map = _p3eObject(value, 'health aggregate record');
    _p3eExactKeys(map, const {
      'entityVersion',
      'organizationId',
      'aggregateId',
      'revisionId',
      'aggregateDigest',
      'aggregate',
      'recomputability',
      'createdAt',
    }, 'health aggregate record');
    _p3eEntityVersion(map['entityVersion'], 'health aggregate');
    final aggregate = HealthAggregate.fromJson(map['aggregate']);
    final record = HealthAggregateRecord(
      aggregateId: _p3eRequiredString(map['aggregateId'], 'aggregate ID'),
      revisionId: _p3eRequiredString(
        map['revisionId'],
        'aggregate revision ID',
      ),
      aggregate: aggregate,
      recomputability: parseP3eRecomputability(map['recomputability']),
      createdAt: _p3eTimestamp(map['createdAt'], 'created at'),
    );
    if (map['organizationId'] != record.organizationId ||
        map['aggregateDigest'] != record.aggregateDigest) {
      throw const StorageDigestMismatch(
        'aggregate record binding',
        'stored aggregate binding',
      );
    }
    return record;
  }
}

final class HealthEvaluation {
  HealthEvaluation({
    required String evaluationId,
    required String organizationId,
    required String aggregateRevisionId,
    required String rolloutId,
    required this.rolloutRevision,
    required this.evaluationVersion,
    required this.policyVersion,
    required this.thresholdSetVersion,
    required this.windowPolicyVersion,
    required this.privacyPolicyVersion,
    required String aggregateInputDigest,
    required String decision,
    required String reasonClass,
    Iterable<String> reasonCodes = const <String>[],
    required String coverageState,
    required String freshnessState,
    required String sampleState,
    required DateTime createdAt,
    String? auditReference,
    String? evaluationInputDigest,
    String? targetBindingDigest,
  }) : evaluationId = _p3eId(evaluationId, 'evaluation ID'),
       organizationId = _p3eId(organizationId, 'organization ID'),
       aggregateRevisionId = _p3eId(
         aggregateRevisionId,
         'aggregate revision ID',
       ),
       rolloutId = _p3eId(rolloutId, 'rollout ID'),
       aggregateInputDigest = requireSha256Digest(aggregateInputDigest),
       decision = _p3eDecision(decision),
       reasonClass = _p3eReasonClass(reasonClass),
       reasonCodes = _p3eReasonCodes(reasonCodes),
       coverageState = _p3eState(
         coverageState,
         'coverage state',
         p3eCoverageStates,
       ),
       freshnessState = _p3eState(
         freshnessState,
         'freshness state',
         p3eFreshnessStates,
       ),
       sampleState = _p3eState(sampleState, 'sample state', p3eSampleStates),
       auditReference = _p3eOptionalString(auditReference, 'audit reference'),
       evaluationInputDigest = evaluationInputDigest == null
           ? null
           : requireSha256Digest(evaluationInputDigest),
       targetBindingDigest = targetBindingDigest == null
           ? null
           : requireSha256Digest(targetBindingDigest),
       createdAt = createdAt.toUtc() {
    if (rolloutRevision <= 0 ||
        evaluationVersion != supportedP3eEvaluationVersion ||
        policyVersion != supportedAggregationPolicyVersion ||
        thresholdSetVersion != supportedP3eThresholdSetVersion ||
        windowPolicyVersion != supportedWindowPolicyVersion ||
        privacyPolicyVersion != supportedP3ePrivacyPolicyVersion) {
      throw const FormatException('Invalid health evaluation version binding');
    }
  }

  final String evaluationId;
  final String organizationId;
  final String aggregateRevisionId;
  final String rolloutId;
  final int rolloutRevision;
  final int evaluationVersion;
  final int policyVersion;
  final int thresholdSetVersion;
  final int windowPolicyVersion;
  final int privacyPolicyVersion;
  final String aggregateInputDigest;
  final String decision;
  final String reasonClass;
  final List<String> reasonCodes;
  final String coverageState;
  final String freshnessState;
  final String sampleState;
  final DateTime createdAt;
  final String? auditReference;
  final String? evaluationInputDigest;
  final String? targetBindingDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': p3ePersistenceSchemaVersion,
    'evaluationId': evaluationId,
    'organizationId': organizationId,
    'aggregateRevisionId': aggregateRevisionId,
    'rolloutId': rolloutId,
    'rolloutRevision': rolloutRevision,
    'evaluationVersion': evaluationVersion,
    'policyVersion': policyVersion,
    'thresholdSetVersion': thresholdSetVersion,
    'windowPolicyVersion': windowPolicyVersion,
    'privacyPolicyVersion': privacyPolicyVersion,
    'aggregateInputDigest': aggregateInputDigest,
    'decision': decision,
    'reasonClass': reasonClass,
    'reasonCodes': reasonCodes,
    'coverageState': coverageState,
    'freshnessState': freshnessState,
    'sampleState': sampleState,
    'createdAt': createdAt.toIso8601String(),
    'auditReference': auditReference,
    if (evaluationInputDigest != null)
      'evaluationInputDigest': evaluationInputDigest,
    if (targetBindingDigest != null) 'targetBindingDigest': targetBindingDigest,
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static HealthEvaluation fromJson(Object? value) {
    final map = _p3eObject(value, 'health evaluation');
    const requiredKeys = <String>{
      'entityVersion',
      'evaluationId',
      'organizationId',
      'aggregateRevisionId',
      'rolloutId',
      'rolloutRevision',
      'evaluationVersion',
      'policyVersion',
      'thresholdSetVersion',
      'windowPolicyVersion',
      'privacyPolicyVersion',
      'aggregateInputDigest',
      'decision',
      'reasonClass',
      'reasonCodes',
      'coverageState',
      'freshnessState',
      'sampleState',
      'createdAt',
      'auditReference',
    };
    if (map.length < requiredKeys.length ||
        map.length > requiredKeys.length + 2) {
      throw const FormatException('Invalid health evaluation fields');
    }
    if (map.keys.any(
      (key) =>
          !requiredKeys.contains(key) &&
          key != 'evaluationInputDigest' &&
          key != 'targetBindingDigest',
    )) {
      throw const FormatException('Invalid health evaluation fields');
    }
    _p3eEntityVersion(map['entityVersion'], 'health evaluation');
    final reasonCodes = map['reasonCodes'];
    if (reasonCodes is! List) {
      throw const FormatException('Invalid evaluation reason codes');
    }
    return HealthEvaluation(
      evaluationId: _p3eRequiredString(map['evaluationId'], 'evaluation ID'),
      organizationId: _p3eRequiredString(
        map['organizationId'],
        'organization ID',
      ),
      aggregateRevisionId: _p3eRequiredString(
        map['aggregateRevisionId'],
        'aggregate revision ID',
      ),
      rolloutId: _p3eRequiredString(map['rolloutId'], 'rollout ID'),
      rolloutRevision: _p3ePositiveInt(
        map['rolloutRevision'],
        'rollout revision',
      ),
      evaluationVersion: _p3ePositiveInt(
        map['evaluationVersion'],
        'evaluation version',
      ),
      policyVersion: _p3ePositiveInt(map['policyVersion'], 'policy version'),
      thresholdSetVersion: _p3ePositiveInt(
        map['thresholdSetVersion'],
        'threshold set version',
      ),
      windowPolicyVersion: _p3ePositiveInt(
        map['windowPolicyVersion'],
        'window policy version',
      ),
      privacyPolicyVersion: _p3ePositiveInt(
        map['privacyPolicyVersion'],
        'privacy policy version',
      ),
      aggregateInputDigest: _p3eRequiredString(
        map['aggregateInputDigest'],
        'aggregate input digest',
      ),
      decision: _p3eRequiredString(map['decision'], 'decision'),
      reasonClass: _p3eRequiredString(map['reasonClass'], 'reason class'),
      reasonCodes: reasonCodes.map(
        (code) => _p3eRequiredString(code, 'reason code', maxLength: 128),
      ),
      coverageState: _p3eRequiredString(map['coverageState'], 'coverage state'),
      freshnessState: _p3eRequiredString(
        map['freshnessState'],
        'freshness state',
      ),
      sampleState: _p3eRequiredString(map['sampleState'], 'sample state'),
      createdAt: _p3eTimestamp(map['createdAt'], 'created at'),
      auditReference: _p3eOptionalString(
        map['auditReference'],
        'audit reference',
      ),
      evaluationInputDigest: map['evaluationInputDigest'] == null
          ? null
          : _p3eRequiredString(
              map['evaluationInputDigest'],
              'evaluation input digest',
            ),
      targetBindingDigest: map['targetBindingDigest'] == null
          ? null
          : _p3eRequiredString(
              map['targetBindingDigest'],
              'target binding digest',
            ),
    );
  }
}

final class RolloutDecisionRecord {
  RolloutDecisionRecord({
    required String decisionId,
    required String organizationId,
    required String rolloutId,
    required this.expectedRolloutRevision,
    required String evaluationId,
    required String aggregateRevisionId,
    required String decision,
    required String reason,
    required String actorIdentity,
    required String idempotencyKey,
    required DateTime createdAt,
    this.previousDecisionId,
    this.resultingTransitionReference,
  }) : decisionId = _p3eId(decisionId, 'decision ID'),
       organizationId = _p3eId(organizationId, 'organization ID'),
       rolloutId = _p3eId(rolloutId, 'rollout ID'),
       evaluationId = _p3eId(evaluationId, 'evaluation ID'),
       aggregateRevisionId = _p3eId(
         aggregateRevisionId,
         'aggregate revision ID',
       ),
       decision = _p3eDecision(decision),
       reason = _p3eRequiredString(reason, 'decision reason'),
       actorIdentity = _p3eRequiredString(actorIdentity, 'actor identity'),
       idempotencyKey = _p3eRequiredString(idempotencyKey, 'idempotency key'),
       createdAt = createdAt.toUtc() {
    if (expectedRolloutRevision <= 0) {
      throw const FormatException('Expected rollout revision is invalid');
    }
    if (previousDecisionId != null) {
      _p3eId(previousDecisionId!, 'previous decision ID');
      if (previousDecisionId == decisionId) {
        throw const FormatException('Decision cannot reference itself');
      }
    }
    if (resultingTransitionReference != null) {
      _p3eRequiredString(
        resultingTransitionReference,
        'resulting transition reference',
      );
    }
  }

  final String decisionId;
  final String organizationId;
  final String rolloutId;
  final int expectedRolloutRevision;
  final String evaluationId;
  final String aggregateRevisionId;
  final String decision;
  final String reason;
  final String actorIdentity;
  final String idempotencyKey;
  final DateTime createdAt;
  final String? previousDecisionId;
  final String? resultingTransitionReference;

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': p3ePersistenceSchemaVersion,
    'decisionId': decisionId,
    'organizationId': organizationId,
    'rolloutId': rolloutId,
    'expectedRolloutRevision': expectedRolloutRevision,
    'evaluationId': evaluationId,
    'aggregateRevisionId': aggregateRevisionId,
    'decision': decision,
    'reason': reason,
    'actorIdentity': actorIdentity,
    'idempotencyKey': idempotencyKey,
    'createdAt': createdAt.toIso8601String(),
    'previousDecisionId': previousDecisionId,
    'resultingTransitionReference': resultingTransitionReference,
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static RolloutDecisionRecord fromJson(Object? value) {
    final map = _p3eObject(value, 'rollout decision');
    _p3eExactKeys(map, const {
      'entityVersion',
      'decisionId',
      'organizationId',
      'rolloutId',
      'expectedRolloutRevision',
      'evaluationId',
      'aggregateRevisionId',
      'decision',
      'reason',
      'actorIdentity',
      'idempotencyKey',
      'createdAt',
      'previousDecisionId',
      'resultingTransitionReference',
    }, 'rollout decision');
    _p3eEntityVersion(map['entityVersion'], 'rollout decision');
    return RolloutDecisionRecord(
      decisionId: _p3eRequiredString(map['decisionId'], 'decision ID'),
      organizationId: _p3eRequiredString(
        map['organizationId'],
        'organization ID',
      ),
      rolloutId: _p3eRequiredString(map['rolloutId'], 'rollout ID'),
      expectedRolloutRevision: _p3ePositiveInt(
        map['expectedRolloutRevision'],
        'expected rollout revision',
      ),
      evaluationId: _p3eRequiredString(map['evaluationId'], 'evaluation ID'),
      aggregateRevisionId: _p3eRequiredString(
        map['aggregateRevisionId'],
        'aggregate revision ID',
      ),
      decision: _p3eRequiredString(map['decision'], 'decision'),
      reason: _p3eRequiredString(map['reason'], 'decision reason'),
      actorIdentity: _p3eRequiredString(map['actorIdentity'], 'actor identity'),
      idempotencyKey: _p3eRequiredString(
        map['idempotencyKey'],
        'idempotency key',
      ),
      createdAt: _p3eTimestamp(map['createdAt'], 'created at'),
      previousDecisionId: _p3eOptionalString(
        map['previousDecisionId'],
        'previous decision ID',
      ),
      resultingTransitionReference: _p3eOptionalString(
        map['resultingTransitionReference'],
        'resulting transition reference',
      ),
    );
  }
}

final class AggregationCursor {
  AggregationCursor({
    required String cursorId,
    required String organizationId,
    required String aggregateId,
    required this.identity,
    required String canonicalInputPosition,
    required String inputDigest,
    required this.aggregationVersion,
    required DateTime createdAt,
  }) : cursorId = _p3eId(cursorId, 'cursor ID'),
       organizationId = _p3eId(organizationId, 'organization ID'),
       aggregateId = _p3eId(aggregateId, 'aggregate ID'),
       canonicalInputPosition = _p3eRequiredString(
         canonicalInputPosition,
         'canonical input position',
       ),
       inputDigest = requireSha256Digest(inputDigest),
       createdAt = createdAt.toUtc() {
    if (identity.organizationId != organizationId ||
        identity.aggregationVersion != aggregationVersion) {
      throw const FormatException('Cursor scope/version binding is invalid');
    }
    if (aggregationVersion <= 0) {
      throw const FormatException('Cursor aggregation version is invalid');
    }
  }

  final String cursorId;
  final String organizationId;
  final String aggregateId;
  final AggregateIdentity identity;
  final String canonicalInputPosition;
  final String inputDigest;
  final int aggregationVersion;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': p3ePersistenceSchemaVersion,
    'cursorId': cursorId,
    'organizationId': organizationId,
    'aggregateId': aggregateId,
    'identity': identity.toJson(),
    'canonicalInputPosition': canonicalInputPosition,
    'inputDigest': inputDigest,
    'aggregationVersion': aggregationVersion,
    'createdAt': createdAt.toIso8601String(),
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static AggregationCursor fromJson(Object? value) {
    final map = _p3eObject(value, 'aggregation cursor');
    _p3eExactKeys(map, const {
      'entityVersion',
      'cursorId',
      'organizationId',
      'aggregateId',
      'identity',
      'canonicalInputPosition',
      'inputDigest',
      'aggregationVersion',
      'createdAt',
    }, 'aggregation cursor');
    _p3eEntityVersion(map['entityVersion'], 'aggregation cursor');
    return AggregationCursor(
      cursorId: _p3eRequiredString(map['cursorId'], 'cursor ID'),
      organizationId: _p3eRequiredString(
        map['organizationId'],
        'organization ID',
      ),
      aggregateId: _p3eRequiredString(map['aggregateId'], 'aggregate ID'),
      identity: AggregateIdentity.fromJson(map['identity']),
      canonicalInputPosition: _p3eRequiredString(
        map['canonicalInputPosition'],
        'canonical input position',
      ),
      inputDigest: _p3eRequiredString(map['inputDigest'], 'input digest'),
      aggregationVersion: _p3ePositiveInt(
        map['aggregationVersion'],
        'aggregation version',
      ),
      createdAt: _p3eTimestamp(map['createdAt'], 'created at'),
    );
  }
}

String _p3eDecision(String value) {
  if (!p3eDecisionValues.contains(value)) {
    throw FormatException('Unsupported P3E decision: $value');
  }
  return value;
}

String _p3eReasonClass(String value) {
  if (!p3eReasonClasses.contains(value)) {
    throw FormatException('Unsupported P3E reason class: $value');
  }
  return value;
}

String _p3eState(String value, String label, Set<String> supported) {
  if (!supported.contains(value)) throw FormatException('Unsupported $label');
  return value;
}

List<String> _p3eReasonCodes(Iterable<String> values) {
  final result =
      values
          .map(
            (value) => _p3eRequiredString(value, 'reason code', maxLength: 128),
          )
          .toSet()
          .toList()
        ..sort();
  if (result.length > 64) {
    throw const FormatException('Too many P3E reason codes');
  }
  return List.unmodifiable(result);
}

final class P3eReconciliationIssue {
  const P3eReconciliationIssue({
    required this.entityType,
    required this.entityId,
    required this.code,
    required this.detail,
  });

  final String entityType;
  final String entityId;
  final String code;
  final String detail;

  Map<String, Object?> toJson() => <String, Object?>{
    'entityType': entityType,
    'entityId': entityId,
    'code': code,
    'detail': detail,
  };
}

final class P3eReconciliationReport {
  P3eReconciliationReport({
    required this.organizationId,
    required this.checkedAggregates,
    required this.checkedRevisions,
    required this.checkedEvaluations,
    required this.checkedDecisions,
    required this.checkedHaltApplications,
    required this.checkedCursors,
    required Iterable<P3eReconciliationIssue> issues,
  }) : issues = List.unmodifiable(issues);

  final String organizationId;
  final int checkedAggregates;
  final int checkedRevisions;
  final int checkedEvaluations;
  final int checkedDecisions;
  final int checkedHaltApplications;
  final int checkedCursors;
  final List<P3eReconciliationIssue> issues;

  bool get clean => issues.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': p3ePersistenceSchemaVersion,
    'organizationId': organizationId,
    'checkedAggregates': checkedAggregates,
    'checkedRevisions': checkedRevisions,
    'checkedEvaluations': checkedEvaluations,
    'checkedDecisions': checkedDecisions,
    'checkedHaltApplications': checkedHaltApplications,
    'checkedCursors': checkedCursors,
    'clean': clean,
    'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
  };
}

/// Storage boundary for immutable P3E evidence. The domain types above do not
/// depend on PostgreSQL, files, HTTP, or control-plane globals.
abstract interface class P3ePersistenceStore {
  Future<void> initialize();

  Future<void> close();

  Future<void> putAggregateRevision(
    HealthAggregateRecord aggregate,
    HealthAggregateRevision revision,
  );

  Future<HealthAggregateRecord?> readAggregate(
    String organizationId,
    String aggregateId,
  );

  Future<List<HealthAggregateRecord>> listAggregates(String organizationId);

  Future<HealthAggregateRevision?> readAggregateRevision(
    String organizationId,
    String aggregateRevisionId,
  );

  Future<List<HealthAggregateRevision>> listAggregateRevisions(
    String organizationId,
  );

  Future<void> putEvaluation(HealthEvaluation evaluation);

  Future<HealthEvaluation?> readEvaluation(
    String organizationId,
    String evaluationId,
  );

  Future<List<HealthEvaluation>> listEvaluations(String organizationId);

  Future<void> putDecision(RolloutDecisionRecord decision);

  Future<RolloutDecisionRecord?> readDecision(
    String organizationId,
    String decisionId,
  );

  Future<List<RolloutDecisionRecord>> listDecisions(String organizationId);

  Future<void> putHaltApplication(HealthHaltApplication application);

  Future<HealthHaltApplication?> readHaltApplication(
    String organizationId,
    String applicationId,
  );

  Future<List<HealthHaltApplication>> listHaltApplications(
    String organizationId,
  );

  Future<void> putCursor(AggregationCursor cursor);

  Future<AggregationCursor?> readCursor(String organizationId, String cursorId);

  Future<void> deleteCursor(String organizationId, String cursorId);

  Future<P3eReconciliationReport> reconcile(String organizationId);
}

void _validateAggregateLineage(
  HealthAggregateRecord aggregate,
  HealthAggregateRevision revision,
) {
  if (aggregate.organizationId != revision.identity.organizationId ||
      aggregate.aggregateId != revision.aggregateId ||
      aggregate.revisionId != revision.aggregateRevisionId ||
      aggregate.aggregate.identity.canonicalSerialization !=
          revision.identity.canonicalSerialization ||
      aggregate.aggregate.window.canonicalSerialization !=
          revision.window.canonicalSerialization ||
      aggregate.aggregate.inputCount != revision.inputCount ||
      aggregate.aggregate.inputDigest != revision.inputDigest ||
      aggregate.recomputability != revision.recomputability) {
    throw const FormatException('Aggregate/revision lineage is inconsistent');
  }
}

/// Validates the exact aggregate/revision lineage before an evaluator uses
/// persisted counters and metrics. It has no mutation or rollout authority.
void validateP3eAggregateLineage(
  HealthAggregateRecord aggregate,
  HealthAggregateRevision revision,
) {
  _validateAggregateLineage(aggregate, revision);
}

void _validateEvaluationReference(
  HealthEvaluation evaluation,
  HealthAggregateRevision revision,
) {
  if (evaluation.organizationId != revision.identity.organizationId ||
      evaluation.aggregateRevisionId != revision.aggregateRevisionId ||
      evaluation.rolloutId != revision.identity.rolloutId ||
      evaluation.rolloutRevision != revision.identity.rolloutRevision ||
      evaluation.aggregateInputDigest != revision.inputDigest) {
    throw const FormatException(
      'Evaluation scope or digest binding is invalid',
    );
  }
}

void _validateDecisionReference(
  RolloutDecisionRecord decision,
  HealthEvaluation evaluation,
) {
  if (decision.organizationId != evaluation.organizationId ||
      decision.evaluationId != evaluation.evaluationId ||
      decision.aggregateRevisionId != evaluation.aggregateRevisionId ||
      decision.rolloutId != evaluation.rolloutId ||
      decision.expectedRolloutRevision != evaluation.rolloutRevision) {
    throw const FormatException('Decision reference binding is invalid');
  }
}

void _validateHaltApplicationReference(
  HealthHaltApplication application,
  RolloutDecisionRecord decision,
  HealthEvaluation evaluation,
  HealthAggregateRevision revision,
) {
  if (application.organizationId != decision.organizationId ||
      application.decisionId != decision.decisionId ||
      application.evaluationId != decision.evaluationId ||
      application.aggregateRevisionId != decision.aggregateRevisionId ||
      application.rolloutId != decision.rolloutId ||
      application.expectedRolloutRevision != decision.expectedRolloutRevision ||
      decision.organizationId != evaluation.organizationId ||
      decision.evaluationId != evaluation.evaluationId ||
      decision.aggregateRevisionId != evaluation.aggregateRevisionId ||
      decision.rolloutId != evaluation.rolloutId ||
      decision.expectedRolloutRevision != evaluation.rolloutRevision ||
      evaluation.organizationId != revision.identity.organizationId ||
      evaluation.aggregateRevisionId != revision.aggregateRevisionId ||
      evaluation.rolloutId != revision.identity.rolloutId ||
      evaluation.rolloutRevision != revision.identity.rolloutRevision) {
    throw const FormatException('Halt application evidence binding is invalid');
  }
}

void _validateCursorReference(
  AggregationCursor cursor,
  HealthAggregateRecord aggregate,
) {
  if (cursor.organizationId != aggregate.organizationId ||
      cursor.aggregateId != aggregate.aggregateId ||
      cursor.identity.canonicalSerialization !=
          aggregate.aggregate.identity.canonicalSerialization ||
      cursor.inputDigest != aggregate.aggregate.inputDigest ||
      cursor.aggregationVersion !=
          aggregate.aggregate.identity.aggregationVersion) {
    throw const FormatException('Cursor binding is invalid');
  }
}

/// Single-node append-only File adapter. Tenant paths are hashed and records
/// are canonical JSON; the adapter makes no multi-process safety claim.
final class FileP3ePersistenceStore implements P3ePersistenceStore {
  FileP3ePersistenceStore(
    this.root, {
    this.limits = const P3ePersistenceLimits(),
  }) {
    limits.validate();
  }

  final Directory root;
  final P3ePersistenceLimits limits;

  static const _collections = <String>[
    'aggregates',
    'revisions',
    'evaluations',
    'decisions',
    'halt_applications',
    'cursors',
  ];

  @override
  Future<void> initialize() async {
    await root.create(recursive: true);
    for (final collection in _collections) {
      await Directory(p.join(root.path, 'p3e', collection))
          .create(recursive: true);
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> putAggregateRevision(
    HealthAggregateRecord aggregate,
    HealthAggregateRevision revision,
  ) async {
    _validateAggregateLineage(aggregate, revision);
    final existingAggregate = await _readRaw(
      'aggregates',
      aggregate.organizationId,
      aggregate.aggregateId,
    );
    final existingRevision = await _readRaw(
      'revisions',
      revision.identity.organizationId,
      revision.aggregateRevisionId,
    );
    final aggregateBody = aggregate.toJson();
    final revisionBody = revision.toJson();
    _p3eCheckPayload(aggregateBody, limits, 'Aggregate record');
    _p3eCheckPayload(revisionBody, limits, 'Aggregate revision');
    _checkExisting(existingAggregate, aggregateBody);
    _checkExisting(existingRevision, revisionBody);
    if (existingAggregate == null) {
      await _writeImmutable(
        _file('aggregates', aggregate.organizationId, aggregate.aggregateId),
        aggregateBody,
      );
    }
    if (existingRevision == null) {
      await _writeImmutable(
        _file(
          'revisions',
          revision.identity.organizationId,
          revision.aggregateRevisionId,
        ),
        revisionBody,
      );
    }
  }

  @override
  Future<HealthAggregateRecord?> readAggregate(
    String organizationId,
    String aggregateId,
  ) async {
    final raw = await _readRaw('aggregates', organizationId, aggregateId);
    return raw == null ? null : HealthAggregateRecord.fromJson(raw);
  }

  @override
  Future<List<HealthAggregateRecord>> listAggregates(String organizationId) =>
      _list('aggregates', organizationId, HealthAggregateRecord.fromJson);

  @override
  Future<HealthAggregateRevision?> readAggregateRevision(
    String organizationId,
    String aggregateRevisionId,
  ) async {
    final raw = await _readRaw(
      'revisions',
      organizationId,
      aggregateRevisionId,
    );
    return raw == null ? null : HealthAggregateRevision.fromJson(raw);
  }

  @override
  Future<List<HealthAggregateRevision>> listAggregateRevisions(
    String organizationId,
  ) => _list('revisions', organizationId, HealthAggregateRevision.fromJson);

  @override
  Future<void> putEvaluation(HealthEvaluation evaluation) async {
    final revision = await readAggregateRevision(
      evaluation.organizationId,
      evaluation.aggregateRevisionId,
    );
    if (revision == null) {
      throw const StorageConflict('Evaluation references a missing revision');
    }
    _validateEvaluationReference(evaluation, revision);
    await _putImmutable(
      'evaluations',
      evaluation.organizationId,
      evaluation.evaluationId,
      evaluation.toJson(),
    );
  }

  @override
  Future<HealthEvaluation?> readEvaluation(
    String organizationId,
    String evaluationId,
  ) async {
    final raw = await _readRaw('evaluations', organizationId, evaluationId);
    return raw == null ? null : HealthEvaluation.fromJson(raw);
  }

  @override
  Future<List<HealthEvaluation>> listEvaluations(String organizationId) =>
      _list('evaluations', organizationId, HealthEvaluation.fromJson);

  @override
  Future<void> putDecision(RolloutDecisionRecord decision) async {
    final evaluation = await readEvaluation(
      decision.organizationId,
      decision.evaluationId,
    );
    if (evaluation == null) {
      throw const StorageConflict('Decision references a missing evaluation');
    }
    _validateDecisionReference(decision, evaluation);
    final revision = await readAggregateRevision(
      decision.organizationId,
      decision.aggregateRevisionId,
    );
    if (revision == null) {
      throw const StorageConflict('Decision references a missing revision');
    }
    await _putImmutable(
      'decisions',
      decision.organizationId,
      decision.decisionId,
      decision.toJson(),
    );
  }

  @override
  Future<RolloutDecisionRecord?> readDecision(
    String organizationId,
    String decisionId,
  ) async {
    final raw = await _readRaw('decisions', organizationId, decisionId);
    return raw == null ? null : RolloutDecisionRecord.fromJson(raw);
  }

  @override
  Future<List<RolloutDecisionRecord>> listDecisions(String organizationId) =>
      _list('decisions', organizationId, RolloutDecisionRecord.fromJson);

  @override
  Future<void> putHaltApplication(HealthHaltApplication application) async {
    final decision = await readDecision(
      application.organizationId,
      application.decisionId,
    );
    if (decision == null) {
      throw const StorageConflict(
        'Halt application references a missing decision',
      );
    }
    final evaluation = await readEvaluation(
      application.organizationId,
      application.evaluationId,
    );
    if (evaluation == null) {
      throw const StorageConflict(
        'Halt application references a missing evaluation',
      );
    }
    final revision = await readAggregateRevision(
      application.organizationId,
      application.aggregateRevisionId,
    );
    if (revision == null) {
      throw const StorageConflict(
        'Halt application references a missing aggregate revision',
      );
    }
    _validateHaltApplicationReference(
      application,
      decision,
      evaluation,
      revision,
    );
    await _putImmutable(
      'halt_applications',
      application.organizationId,
      application.applicationId,
      application.toJson(),
    );
  }

  @override
  Future<HealthHaltApplication?> readHaltApplication(
    String organizationId,
    String applicationId,
  ) async {
    final raw = await _readRaw(
      'halt_applications',
      organizationId,
      applicationId,
    );
    return raw == null ? null : HealthHaltApplication.fromJson(raw);
  }

  @override
  Future<List<HealthHaltApplication>> listHaltApplications(
    String organizationId,
  ) => _list(
    'halt_applications',
    organizationId,
    HealthHaltApplication.fromJson,
  );

  @override
  Future<void> putCursor(AggregationCursor cursor) async {
    final aggregate = await readAggregate(
      cursor.organizationId,
      cursor.aggregateId,
    );
    if (aggregate == null) {
      throw const StorageConflict('Cursor references a missing aggregate');
    }
    _validateCursorReference(cursor, aggregate);
    await _putImmutable(
      'cursors',
      cursor.organizationId,
      cursor.cursorId,
      cursor.toJson(),
    );
  }

  @override
  Future<AggregationCursor?> readCursor(
    String organizationId,
    String cursorId,
  ) async {
    final raw = await _readRaw('cursors', organizationId, cursorId);
    return raw == null ? null : AggregationCursor.fromJson(raw);
  }

  @override
  Future<void> deleteCursor(String organizationId, String cursorId) async {
    final file = _file('cursors', organizationId, cursorId);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<P3eReconciliationReport> reconcile(String organizationId) async {
    final aggregates = await listAggregates(organizationId);
    final revisions = await listAggregateRevisions(organizationId);
    final evaluations = await listEvaluations(organizationId);
    final decisions = await listDecisions(organizationId);
    final haltApplications = await listHaltApplications(organizationId);
    final cursors = await _list(
      'cursors',
      organizationId,
      AggregationCursor.fromJson,
    );
    return _reconcileValues(
      organizationId: organizationId,
      aggregates: aggregates,
      revisions: revisions,
      evaluations: evaluations,
      decisions: decisions,
      haltApplications: haltApplications,
      cursors: cursors,
      limits: limits,
    );
  }

  Future<void> _putImmutable(
    String collection,
    String organizationId,
    String id,
    Map<String, Object?> value,
  ) async {
    final existing = await _readRaw(collection, organizationId, id);
    _checkExisting(existing, value);
    if (existing == null)
      await _writeImmutable(_file(collection, organizationId, id), value);
  }

  Future<Map<String, Object?>?> _readRaw(
    String collection,
    String organizationId,
    String id,
  ) async {
    final file = _file(collection, organizationId, id);
    if (!await file.exists()) return null;
    if (await file.length() > limits.maximumRecordBytes) {
      throw const FormatException('Persisted P3E record exceeds byte limit');
    }
    final value = decodeObject(await file.readAsString());
    _p3eCheckPayload(value, limits, 'Persisted P3E record');
    return value;
  }

  Future<List<T>> _list<T>(
    String collection,
    String organizationId,
    T Function(Object?) decode,
  ) async {
    final directory = Directory(
      p.join(root.path, 'p3e', collection, _tenantKey(organizationId)),
    );
    if (!await directory.exists()) return <T>[];
    final entries = await directory.list(followLinks: false).toList();
    final files = entries.whereType<File>().toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    final result = <T>[];
    for (final file in files) {
      if (!file.path.endsWith('.json')) continue;
      if (await file.length() > limits.maximumRecordBytes) {
        throw const FormatException('Persisted P3E record exceeds byte limit');
      }
      final value = decodeObject(await file.readAsString());
      _p3eCheckPayload(value, limits, 'Persisted P3E record');
      result.add(decode(value));
    }
    return List.unmodifiable(result);
  }

  File _file(String collection, String organizationId, String id) => File(
    p.join(
      root.path,
      'p3e',
      collection,
      _tenantKey(organizationId),
      '${_key(id)}.json',
    ),
  );

  String _tenantKey(String organizationId) =>
      sha256Hex(utf8.encode(organizationId));

  String _key(String value) => sha256Hex(utf8.encode(value));

  Future<void> _writeImmutable(
    File destination,
    Map<String, Object?> value,
  ) async {
    _p3eCheckPayload(value, limits, 'P3E record');
    await destination.parent.create(recursive: true);
    final bytes = utf8.encode('${canonicalJson(value)}\n');
    final temporary = File(
      '${destination.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
      final persisted = decodeObject(await destination.readAsString());
      if (canonicalJson(persisted) != canonicalJson(value)) {
        throw const StorageConflict('Immutable File record was changed');
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

/// PostgreSQL adapter for P3E evidence. Every query carries the organization
/// key; immutable writes use unique constraints and transactions rather than
/// last-write-wins updates.
final class PostgresP3ePersistenceStore implements P3ePersistenceStore {
  PostgresP3ePersistenceStore(
    String connectionString, {
    this.limits = const P3ePersistenceLimits(),
  }) : _pool = Pool.withUrl(connectionString),
       _ownsPool = true {
    limits.validate();
  }

  PostgresP3ePersistenceStore.withPool(
    Pool pool, {
    this.limits = const P3ePersistenceLimits(),
  }) : _pool = pool,
       _ownsPool = false {
    limits.validate();
  }

  final Pool _pool;
  final bool _ownsPool;
  final P3ePersistenceLimits limits;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _pool.runTx((session) async {
      await session.execute('SELECT pg_advisory_xact_lock(7812450)');
      for (final statement in p3ePostgresMigration003) {
        await session.execute(statement);
      }
      for (final statement in p3ePostgresMigration004) {
        await session.execute(statement);
      }
    });
    _initialized = true;
  }

  @override
  Future<void> close() async {
    if (_ownsPool) await _pool.close();
  }

  @override
  Future<void> putAggregateRevision(
    HealthAggregateRecord aggregate,
    HealthAggregateRevision revision,
  ) async {
    _validateAggregateLineage(aggregate, revision);
    await _pool.runTx((session) async {
      await _insertAggregate(session, aggregate);
      await _insertRevision(session, revision);
    });
  }

  @override
  Future<HealthAggregateRecord?> readAggregate(
    String organizationId,
    String aggregateId,
  ) async {
    final raw = await _readRaw(
      'control_plane_p3e_aggregates',
      'aggregate_id',
      organizationId,
      aggregateId,
    );
    return raw == null ? null : HealthAggregateRecord.fromJson(raw);
  }

  @override
  Future<List<HealthAggregateRecord>> listAggregates(String organizationId) =>
      _list(
        'control_plane_p3e_aggregates',
        'aggregate_id',
        organizationId,
        HealthAggregateRecord.fromJson,
      );

  @override
  Future<HealthAggregateRevision?> readAggregateRevision(
    String organizationId,
    String aggregateRevisionId,
  ) async {
    final raw = await _readRaw(
      'control_plane_p3e_aggregate_revisions',
      'aggregate_revision_id',
      organizationId,
      aggregateRevisionId,
    );
    return raw == null ? null : HealthAggregateRevision.fromJson(raw);
  }

  @override
  Future<List<HealthAggregateRevision>> listAggregateRevisions(
    String organizationId,
  ) => _list(
    'control_plane_p3e_aggregate_revisions',
    'aggregate_revision_id',
    organizationId,
    HealthAggregateRevision.fromJson,
  );

  @override
  Future<void> putEvaluation(HealthEvaluation evaluation) async {
    await _pool.runTx((session) async {
      final revision = await _readRevisionSession(
        session,
        evaluation.organizationId,
        evaluation.aggregateRevisionId,
      );
      if (revision == null) {
        throw const StorageConflict('Evaluation references a missing revision');
      }
      _validateEvaluationReference(evaluation, revision);
      await _insertEvaluation(session, evaluation);
    });
  }

  @override
  Future<HealthEvaluation?> readEvaluation(
    String organizationId,
    String evaluationId,
  ) async {
    final raw = await _readRaw(
      'control_plane_p3e_evaluations',
      'evaluation_id',
      organizationId,
      evaluationId,
    );
    return raw == null ? null : HealthEvaluation.fromJson(raw);
  }

  @override
  Future<List<HealthEvaluation>> listEvaluations(String organizationId) =>
      _list(
        'control_plane_p3e_evaluations',
        'evaluation_id',
        organizationId,
        HealthEvaluation.fromJson,
      );

  @override
  Future<void> putDecision(RolloutDecisionRecord decision) async {
    await _pool.runTx((session) async {
      final evaluation = await _readEvaluationSession(
        session,
        decision.organizationId,
        decision.evaluationId,
      );
      if (evaluation == null) {
        throw const StorageConflict('Decision references a missing evaluation');
      }
      _validateDecisionReference(decision, evaluation);
      final revision = await _readRevisionSession(
        session,
        decision.organizationId,
        decision.aggregateRevisionId,
      );
      if (revision == null) {
        throw const StorageConflict('Decision references a missing revision');
      }
      await _insertDecision(session, decision);
    });
  }

  @override
  Future<RolloutDecisionRecord?> readDecision(
    String organizationId,
    String decisionId,
  ) async {
    final raw = await _readRaw(
      'control_plane_p3e_decisions',
      'decision_id',
      organizationId,
      decisionId,
    );
    return raw == null ? null : RolloutDecisionRecord.fromJson(raw);
  }

  @override
  Future<List<RolloutDecisionRecord>> listDecisions(String organizationId) =>
      _list(
        'control_plane_p3e_decisions',
        'decision_id',
        organizationId,
        RolloutDecisionRecord.fromJson,
      );

  @override
  Future<void> putHaltApplication(HealthHaltApplication application) async {
    await _pool.runTx((session) async {
      final decision = await _readDecisionSession(
        session,
        application.organizationId,
        application.decisionId,
      );
      if (decision == null) {
        throw const StorageConflict(
          'Halt application references a missing decision',
        );
      }
      final evaluation = await _readEvaluationSession(
        session,
        application.organizationId,
        application.evaluationId,
      );
      if (evaluation == null) {
        throw const StorageConflict(
          'Halt application references a missing evaluation',
        );
      }
      final revision = await _readRevisionSession(
        session,
        application.organizationId,
        application.aggregateRevisionId,
      );
      if (revision == null) {
        throw const StorageConflict(
          'Halt application references a missing aggregate revision',
        );
      }
      _validateHaltApplicationReference(
        application,
        decision,
        evaluation,
        revision,
      );
      await _insertHaltApplication(session, application);
    });
  }

  @override
  Future<HealthHaltApplication?> readHaltApplication(
    String organizationId,
    String applicationId,
  ) async {
    final raw = await _readRaw(
      'control_plane_p3e_halt_applications',
      'application_id',
      organizationId,
      applicationId,
    );
    return raw == null ? null : HealthHaltApplication.fromJson(raw);
  }

  @override
  Future<List<HealthHaltApplication>> listHaltApplications(
    String organizationId,
  ) => _list(
    'control_plane_p3e_halt_applications',
    'application_id',
    organizationId,
    HealthHaltApplication.fromJson,
  );

  @override
  Future<void> putCursor(AggregationCursor cursor) async {
    await _pool.runTx((session) async {
      final aggregate = await _readAggregateSession(
        session,
        cursor.organizationId,
        cursor.aggregateId,
      );
      if (aggregate == null) {
        throw const StorageConflict('Cursor references a missing aggregate');
      }
      _validateCursorReference(cursor, aggregate);
      await _insertCursor(session, cursor);
    });
  }

  @override
  Future<AggregationCursor?> readCursor(
    String organizationId,
    String cursorId,
  ) async {
    final raw = await _readRaw(
      'control_plane_p3e_cursors',
      'cursor_id',
      organizationId,
      cursorId,
    );
    return raw == null ? null : AggregationCursor.fromJson(raw);
  }

  @override
  Future<void> deleteCursor(String organizationId, String cursorId) async {
    await _pool.execute(
      Sql.named(
        'DELETE FROM control_plane_p3e_cursors '
        'WHERE organization_id = @organization:text AND cursor_id = @id:text',
      ),
      parameters: <String, Object?>{
        'organization': organizationId,
        'id': cursorId,
      },
    );
  }

  @override
  Future<P3eReconciliationReport> reconcile(String organizationId) async {
    final aggregates = await listAggregates(organizationId);
    final revisions = await listAggregateRevisions(organizationId);
    final evaluations = await listEvaluations(organizationId);
    final decisions = await listDecisions(organizationId);
    final haltApplications = await listHaltApplications(organizationId);
    final cursors = await _list(
      'control_plane_p3e_cursors',
      'cursor_id',
      organizationId,
      AggregationCursor.fromJson,
    );
    return _reconcileValues(
      organizationId: organizationId,
      aggregates: aggregates,
      revisions: revisions,
      evaluations: evaluations,
      decisions: decisions,
      haltApplications: haltApplications,
      cursors: cursors,
      limits: limits,
    );
  }

  Future<void> _insertAggregate(
    Session session,
    HealthAggregateRecord aggregate,
  ) async {
    await _insertImmutable(
      session,
      table: 'control_plane_p3e_aggregates',
      idColumn: 'aggregate_id',
      organizationId: aggregate.organizationId,
      id: aggregate.aggregateId,
      body: aggregate.toJson(),
      extraColumns: const <String>['revision_id', 'aggregate_digest'],
      extraValues: <String, Object?>{
        'revision_id': aggregate.revisionId,
        'aggregate_digest': aggregate.aggregateDigest,
      },
      createdAt: aggregate.createdAt,
    );
  }

  Future<void> _insertRevision(
    Session session,
    HealthAggregateRevision revision,
  ) async {
    await _insertImmutable(
      session,
      table: 'control_plane_p3e_aggregate_revisions',
      idColumn: 'aggregate_revision_id',
      organizationId: revision.identity.organizationId,
      id: revision.aggregateRevisionId,
      body: revision.toJson(),
      extraColumns: const <String>[
        'aggregate_id',
        'parent_aggregate_revision_id',
      ],
      extraValues: <String, Object?>{
        'aggregate_id': revision.aggregateId,
        'parent_aggregate_revision_id': revision.parentAggregateRevisionId,
      },
      createdAt: revision.createdAt,
    );
  }

  Future<void> _insertEvaluation(
    Session session,
    HealthEvaluation evaluation,
  ) => _insertImmutable(
    session,
    table: 'control_plane_p3e_evaluations',
    idColumn: 'evaluation_id',
    organizationId: evaluation.organizationId,
    id: evaluation.evaluationId,
    body: evaluation.toJson(),
    extraColumns: const <String>['aggregate_revision_id'],
    extraValues: <String, Object?>{
      'aggregate_revision_id': evaluation.aggregateRevisionId,
    },
    createdAt: evaluation.createdAt,
  );

  Future<void> _insertDecision(
    Session session,
    RolloutDecisionRecord decision,
  ) => _insertImmutable(
    session,
    table: 'control_plane_p3e_decisions',
    idColumn: 'decision_id',
    organizationId: decision.organizationId,
    id: decision.decisionId,
    body: decision.toJson(),
    extraColumns: const <String>['evaluation_id', 'aggregate_revision_id'],
    extraValues: <String, Object?>{
      'evaluation_id': decision.evaluationId,
      'aggregate_revision_id': decision.aggregateRevisionId,
    },
    createdAt: decision.createdAt,
  );

  Future<void> _insertHaltApplication(
    Session session,
    HealthHaltApplication application,
  ) => _insertImmutable(
    session,
    table: 'control_plane_p3e_halt_applications',
    idColumn: 'application_id',
    organizationId: application.organizationId,
    id: application.applicationId,
    body: application.toJson(),
    extraColumns: const <String>[
      'decision_id',
      'evaluation_id',
      'aggregate_revision_id',
      'rollout_id',
      'expected_rollout_revision',
      'result',
    ],
    extraValues: <String, Object?>{
      'decision_id': application.decisionId,
      'evaluation_id': application.evaluationId,
      'aggregate_revision_id': application.aggregateRevisionId,
      'rollout_id': application.rolloutId,
      'expected_rollout_revision': application.expectedRolloutRevision,
      'result': application.result,
    },
    createdAt: application.createdAt,
  );

  Future<void> _insertCursor(Session session, AggregationCursor cursor) =>
      _insertImmutable(
        session,
        table: 'control_plane_p3e_cursors',
        idColumn: 'cursor_id',
        organizationId: cursor.organizationId,
        id: cursor.cursorId,
        body: cursor.toJson(),
        extraColumns: const <String>['aggregate_id', 'input_digest'],
        extraValues: <String, Object?>{
          'aggregate_id': cursor.aggregateId,
          'input_digest': cursor.inputDigest,
        },
        createdAt: cursor.createdAt,
      );

  Future<void> _insertImmutable(
    Session session, {
    required String table,
    required String idColumn,
    required String organizationId,
    required String id,
    required Map<String, Object?> body,
    required List<String> extraColumns,
    required Map<String, Object?> extraValues,
    required DateTime createdAt,
  }) async {
    _p3eCheckPayload(body, limits, 'P3E record');
    final columns = <String>[
      'organization_id',
      idColumn,
      ...extraColumns,
      'body',
      'created_at',
    ];
    final placeholders = <String>[
      '@organization:text',
      '@id:text',
      ...extraColumns.map(
        (column) => column == 'expected_rollout_revision'
            ? '@$column:int8'
            : '@$column:text',
      ),
      '@body:jsonb',
      '@created:timestamptz',
    ];
    await session.execute(
      Sql.named(
        'INSERT INTO $table (${columns.join(', ')}) VALUES '
        '(${placeholders.join(', ')}) '
        'ON CONFLICT (organization_id, $idColumn) DO NOTHING',
      ),
      parameters: <String, Object?>{
        'organization': organizationId,
        'id': id,
        ...extraValues,
        'body': body,
        'created': createdAt.toUtc(),
      },
    );
    final existing = await _readRawSession(
      session,
      table,
      idColumn,
      organizationId,
      id,
    );
    if (existing == null || canonicalJson(existing) != canonicalJson(body)) {
      throw const StorageConflict('Immutable P3E record already exists');
    }
  }

  Future<Map<String, Object?>?> _readRaw(
    String table,
    String idColumn,
    String organizationId,
    String id,
  ) async => _readRawSession(_pool, table, idColumn, organizationId, id);

  Future<Map<String, Object?>?> _readRawSession(
    Session session,
    String table,
    String idColumn,
    String organizationId,
    String id,
  ) async {
    final result = await session.execute(
      Sql.named(
        'SELECT body::text AS body_json FROM $table '
        'WHERE organization_id = @organization:text AND $idColumn = @id:text',
      ),
      parameters: <String, Object?>{'organization': organizationId, 'id': id},
    );
    if (result.isEmpty) return null;
    final body = _p3eDecodeBody(result.first.toColumnMap()['body_json']);
    _p3eCheckPayload(body, limits, 'Persisted P3E record');
    return body;
  }

  Future<List<T>> _list<T>(
    String table,
    String idColumn,
    String organizationId,
    T Function(Object?) decode,
  ) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT body::text AS body_json FROM $table '
        'WHERE organization_id = @organization:text ORDER BY $idColumn',
      ),
      parameters: <String, Object?>{'organization': organizationId},
    );
    final decoded = <T>[];
    for (final row in result) {
      final body = _p3eDecodeBody(row.toColumnMap()['body_json']);
      _p3eCheckPayload(body, limits, 'Persisted P3E record');
      decoded.add(decode(body));
    }
    return List.unmodifiable(decoded);
  }

  Future<HealthAggregateRecord?> _readAggregateSession(
    Session session,
    String organizationId,
    String aggregateId,
  ) async {
    final raw = await _readRawSession(
      session,
      'control_plane_p3e_aggregates',
      'aggregate_id',
      organizationId,
      aggregateId,
    );
    return raw == null ? null : HealthAggregateRecord.fromJson(raw);
  }

  Future<HealthAggregateRevision?> _readRevisionSession(
    Session session,
    String organizationId,
    String revisionId,
  ) async {
    final raw = await _readRawSession(
      session,
      'control_plane_p3e_aggregate_revisions',
      'aggregate_revision_id',
      organizationId,
      revisionId,
    );
    return raw == null ? null : HealthAggregateRevision.fromJson(raw);
  }

  Future<HealthEvaluation?> _readEvaluationSession(
    Session session,
    String organizationId,
    String evaluationId,
  ) async {
    final raw = await _readRawSession(
      session,
      'control_plane_p3e_evaluations',
      'evaluation_id',
      organizationId,
      evaluationId,
    );
    return raw == null ? null : HealthEvaluation.fromJson(raw);
  }

  Future<RolloutDecisionRecord?> _readDecisionSession(
    Session session,
    String organizationId,
    String decisionId,
  ) async {
    final raw = await _readRawSession(
      session,
      'control_plane_p3e_decisions',
      'decision_id',
      organizationId,
      decisionId,
    );
    return raw == null ? null : RolloutDecisionRecord.fromJson(raw);
  }
}

Map<String, Object?> _p3eDecodeBody(Object? value) {
  final decoded = value is String ? jsonDecode(value) : value;
  return _p3eObject(decoded, 'persisted JSON body');
}

P3eReconciliationReport _reconcileValues({
  required String organizationId,
  required List<HealthAggregateRecord> aggregates,
  required List<HealthAggregateRevision> revisions,
  required List<HealthEvaluation> evaluations,
  required List<RolloutDecisionRecord> decisions,
  required List<HealthHaltApplication> haltApplications,
  required List<AggregationCursor> cursors,
  required P3ePersistenceLimits limits,
}) {
  limits.validate();
  final total =
      aggregates.length +
      revisions.length +
      evaluations.length +
      decisions.length +
      haltApplications.length +
      cursors.length;
  _p3eCheckBatch(total, limits);
  final revisionById = <String, HealthAggregateRevision>{
    for (final revision in revisions) revision.aggregateRevisionId: revision,
  };
  final evaluationById = <String, HealthEvaluation>{
    for (final evaluation in evaluations) evaluation.evaluationId: evaluation,
  };
  final aggregateById = <String, HealthAggregateRecord>{
    for (final aggregate in aggregates) aggregate.aggregateId: aggregate,
  };
  final decisionById = <String, RolloutDecisionRecord>{
    for (final decision in decisions) decision.decisionId: decision,
  };
  final issues = <P3eReconciliationIssue>[];
  for (final aggregate in aggregates) {
    final revision = revisionById[aggregate.revisionId];
    if (revision == null) {
      issues.add(
        _issue('aggregate', aggregate.aggregateId, 'MISSING_REVISION'),
      );
    } else {
      try {
        _validateAggregateLineage(aggregate, revision);
      } on Object catch (error) {
        issues.add(
          _issue(
            'aggregate',
            aggregate.aggregateId,
            'BINDING_MISMATCH',
            '$error',
          ),
        );
      }
    }
  }
  for (final revision in revisions) {
    final seen = <String>{revision.aggregateRevisionId};
    var current = revision;
    var depth = 0;
    while (current.parentAggregateRevisionId != null) {
      depth++;
      if (depth > limits.maximumLineageDepth) {
        issues.add(
          _issue(
            'revision',
            revision.aggregateRevisionId,
            'LINEAGE_DEPTH_EXCEEDED',
          ),
        );
        break;
      }
      final parentId = current.parentAggregateRevisionId!;
      if (!seen.add(parentId)) {
        issues.add(
          _issue('revision', revision.aggregateRevisionId, 'LINEAGE_CYCLE'),
        );
        break;
      }
      final parent = revisionById[parentId];
      if (parent == null) {
        issues.add(
          _issue('revision', revision.aggregateRevisionId, 'MISSING_PARENT'),
        );
        break;
      }
      current = parent;
    }
  }
  for (final evaluation in evaluations) {
    final revision = revisionById[evaluation.aggregateRevisionId];
    if (revision == null) {
      issues.add(
        _issue('evaluation', evaluation.evaluationId, 'MISSING_REVISION'),
      );
    } else {
      try {
        _validateEvaluationReference(evaluation, revision);
      } on Object catch (error) {
        issues.add(
          _issue(
            'evaluation',
            evaluation.evaluationId,
            'BINDING_MISMATCH',
            '$error',
          ),
        );
      }
    }
  }
  for (final decision in decisions) {
    final evaluation = evaluationById[decision.evaluationId];
    if (evaluation == null) {
      issues.add(_issue('decision', decision.decisionId, 'MISSING_EVALUATION'));
    } else {
      try {
        _validateDecisionReference(decision, evaluation);
      } on Object catch (error) {
        issues.add(
          _issue('decision', decision.decisionId, 'BINDING_MISMATCH', '$error'),
        );
      }
    }
  }
  for (final application in haltApplications) {
    final decision = decisionById[application.decisionId];
    final evaluation = evaluationById[application.evaluationId];
    final revision = revisionById[application.aggregateRevisionId];
    if (decision == null || evaluation == null || revision == null) {
      issues.add(
        _issue(
          'halt_application',
          application.applicationId,
          'MISSING_REFERENCE',
        ),
      );
    } else {
      try {
        _validateHaltApplicationReference(
          application,
          decision,
          evaluation,
          revision,
        );
      } on Object catch (error) {
        issues.add(
          _issue(
            'halt_application',
            application.applicationId,
            'BINDING_MISMATCH',
            '$error',
          ),
        );
      }
    }
  }
  for (final cursor in cursors) {
    final aggregate = aggregateById[cursor.aggregateId];
    if (aggregate == null) {
      issues.add(_issue('cursor', cursor.cursorId, 'MISSING_AGGREGATE'));
    } else {
      try {
        _validateCursorReference(cursor, aggregate);
      } on Object catch (error) {
        issues.add(
          _issue('cursor', cursor.cursorId, 'BINDING_MISMATCH', '$error'),
        );
      }
    }
  }
  return P3eReconciliationReport(
    organizationId: organizationId,
    checkedAggregates: aggregates.length,
    checkedRevisions: revisions.length,
    checkedEvaluations: evaluations.length,
    checkedDecisions: decisions.length,
    checkedHaltApplications: haltApplications.length,
    checkedCursors: cursors.length,
    issues: List.unmodifiable(issues),
  );
}

P3eReconciliationIssue _issue(
  String entityType,
  String entityId,
  String code, [
  String detail = 'Persisted evidence failed reconciliation',
]) => P3eReconciliationIssue(
  entityType: entityType,
  entityId: entityId,
  code: code,
  detail: detail,
);

void _checkExisting(
  Map<String, Object?>? existing,
  Map<String, Object?> incoming,
) {
  if (existing == null) return;
  if (canonicalJson(existing) != canonicalJson(incoming)) {
    throw const StorageConflict('Immutable P3E record already exists');
  }
}

void _p3eCheckPayload(
  Map<String, Object?> value,
  P3ePersistenceLimits limits,
  String label,
) {
  limits.validate();
  final bytes = utf8.encode(canonicalJson(value));
  if (bytes.length > limits.maximumRecordBytes) {
    throw FormatException('$label exceeds persistence byte limit');
  }
}

void _p3eCheckBatch(int count, P3ePersistenceLimits limits) {
  if (count > limits.maximumReconciliationBatch) {
    throw const FormatException('P3E reconciliation batch exceeds limit');
  }
}
