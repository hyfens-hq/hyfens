import 'dart:convert';

import 'encoding.dart';

const int p3eHaltApplicationEntityVersion = 1;

const Set<String> p3eHaltApplicationResults = <String>{
  'APPLIED',
  'ALREADY_APPLIED',
  'STALE',
  'REJECTED',
  'CONFLICT',
  'EVIDENCE_REJECTED',
};

final RegExp _haltApplicationIdempotencyPattern = RegExp(
  r'^[A-Za-z0-9._:-]{1,200}$',
);

Map<String, Object?> _haltObject(Object? value, String label) {
  if (value is! Map) throw FormatException('Invalid $label object');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('Invalid $label key');
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _haltExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String label,
) {
  if (value.length != expected.length ||
      value.keys.any((key) => !expected.contains(key))) {
    throw FormatException('Invalid $label fields');
  }
}

String _haltString(Object? value, String label, {int maxLength = 256}) {
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('Invalid $label');
  }
  return value;
}

final RegExp _haltEntityIdPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_.:-]{0,127}$');

String _haltEntityId(String value, String label) {
  if (!_haltEntityIdPattern.hasMatch(value)) {
    throw FormatException('Invalid $label');
  }
  return value;
}

int _haltPositiveInt(Object? value, String label) {
  if (value is! int || value <= 0) throw FormatException('Invalid $label');
  return value;
}

int? _haltOptionalInt(Object? value, String label) {
  if (value == null) return null;
  if (value is! int || value < 0) throw FormatException('Invalid $label');
  return value;
}

DateTime _haltTimestamp(Object? value, String label) {
  final text = _haltString(value, label);
  try {
    return DateTime.parse(text).toUtc();
  } on FormatException {
    throw FormatException('Invalid $label');
  }
}

/// Immutable evidence describing one explicit attempt to apply a persisted
/// `HALT_NEW_OFFERS` decision through the P3A transition boundary.
final class HealthHaltApplication {
  HealthHaltApplication({
    required String applicationId,
    required String organizationId,
    required String decisionId,
    required String evaluationId,
    required String aggregateRevisionId,
    required String rolloutId,
    required this.expectedRolloutRevision,
    required String result,
    required String reason,
    required String actorIdentity,
    required String idempotencyKey,
    required this.previousRolloutRevision,
    required this.resultingRolloutRevision,
    required String? resultingTransitionReference,
    required this.createdAt,
  }) : applicationId = _haltEntityId(applicationId, 'halt application ID'),
       organizationId = _haltEntityId(organizationId, 'organization ID'),
       decisionId = _haltEntityId(decisionId, 'decision ID'),
       evaluationId = _haltEntityId(evaluationId, 'evaluation ID'),
       aggregateRevisionId = _haltEntityId(
         aggregateRevisionId,
         'aggregate revision ID',
       ),
       rolloutId = _haltEntityId(rolloutId, 'rollout ID'),
       result = _haltResult(result),
       reason = requireNonEmpty(
         reason,
         'halt application reason',
         maxLength: 512,
       ),
       actorIdentity = requireOpaqueId(actorIdentity, 'actor identity'),
       idempotencyKey = _haltIdempotencyKey(idempotencyKey),
       resultingTransitionReference = resultingTransitionReference == null
           ? null
           : requireNonEmpty(
               resultingTransitionReference,
               'resulting transition reference',
               maxLength: 256,
             ) {
    if (expectedRolloutRevision <= 0) {
      throw const FormatException('Expected rollout revision is invalid');
    }
    if (previousRolloutRevision != null && previousRolloutRevision! < 0) {
      throw const FormatException('Previous rollout revision is invalid');
    }
    if (resultingRolloutRevision != null && resultingRolloutRevision! <= 0) {
      throw const FormatException('Resulting rollout revision is invalid');
    }
    if (result == 'APPLIED' &&
        (previousRolloutRevision != expectedRolloutRevision ||
            resultingRolloutRevision != expectedRolloutRevision + 1 ||
            resultingTransitionReference == null)) {
      throw const FormatException('Applied halt outcome is incomplete');
    }
    if (result == 'ALREADY_APPLIED' && resultingTransitionReference == null) {
      throw const FormatException('Already-applied outcome is incomplete');
    }
    if (result != 'APPLIED' &&
        result != 'ALREADY_APPLIED' &&
        resultingTransitionReference != null) {
      throw const FormatException(
        'Rejected halt outcome cannot reference a transition',
      );
    }
  }

  final String applicationId;
  final String organizationId;
  final String decisionId;
  final String evaluationId;
  final String aggregateRevisionId;
  final String rolloutId;
  final int expectedRolloutRevision;
  final String result;
  final String reason;
  final String actorIdentity;
  final String idempotencyKey;
  final int? previousRolloutRevision;
  final int? resultingRolloutRevision;
  final String? resultingTransitionReference;
  final DateTime createdAt;

  bool get applied => result == 'APPLIED' || result == 'ALREADY_APPLIED';

  Map<String, Object?> toJson() => <String, Object?>{
    'entityVersion': p3eHaltApplicationEntityVersion,
    'applicationId': applicationId,
    'organizationId': organizationId,
    'decisionId': decisionId,
    'evaluationId': evaluationId,
    'aggregateRevisionId': aggregateRevisionId,
    'rolloutId': rolloutId,
    'expectedRolloutRevision': expectedRolloutRevision,
    'result': result,
    'reason': reason,
    'actorIdentity': actorIdentity,
    'idempotencyKey': idempotencyKey,
    'previousRolloutRevision': previousRolloutRevision,
    'resultingRolloutRevision': resultingRolloutRevision,
    'resultingTransitionReference': resultingTransitionReference,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  String get canonicalSerialization => canonicalJson(toJson());

  static HealthHaltApplication fromJson(Object? value) {
    final map = _haltObject(value, 'health halt application');
    _haltExactKeys(map, const {
      'entityVersion',
      'applicationId',
      'organizationId',
      'decisionId',
      'evaluationId',
      'aggregateRevisionId',
      'rolloutId',
      'expectedRolloutRevision',
      'result',
      'reason',
      'actorIdentity',
      'idempotencyKey',
      'previousRolloutRevision',
      'resultingRolloutRevision',
      'resultingTransitionReference',
      'createdAt',
    }, 'health halt application');
    if (map['entityVersion'] != p3eHaltApplicationEntityVersion) {
      throw const FormatException(
        'Unsupported health halt application version',
      );
    }
    return HealthHaltApplication(
      applicationId: _haltString(map['applicationId'], 'application ID'),
      organizationId: _haltString(map['organizationId'], 'organization ID'),
      decisionId: _haltString(map['decisionId'], 'decision ID'),
      evaluationId: _haltString(map['evaluationId'], 'evaluation ID'),
      aggregateRevisionId: _haltString(
        map['aggregateRevisionId'],
        'aggregate revision ID',
      ),
      rolloutId: _haltString(map['rolloutId'], 'rollout ID'),
      expectedRolloutRevision: _haltPositiveInt(
        map['expectedRolloutRevision'],
        'expected rollout revision',
      ),
      result: _haltString(map['result'], 'result'),
      reason: _haltString(map['reason'], 'reason', maxLength: 512),
      actorIdentity: _haltString(map['actorIdentity'], 'actor identity'),
      idempotencyKey: _haltString(map['idempotencyKey'], 'idempotency key'),
      previousRolloutRevision: _haltOptionalInt(
        map['previousRolloutRevision'],
        'previous rollout revision',
      ),
      resultingRolloutRevision: _haltOptionalInt(
        map['resultingRolloutRevision'],
        'resulting rollout revision',
      ),
      resultingTransitionReference: map['resultingTransitionReference'] == null
          ? null
          : _haltString(
              map['resultingTransitionReference'],
              'resulting transition reference',
            ),
      createdAt: _haltTimestamp(map['createdAt'], 'created at'),
    );
  }
}

String _haltResult(String value) {
  if (!p3eHaltApplicationResults.contains(value)) {
    throw FormatException('Unsupported halt application result: $value');
  }
  return value;
}

String _haltIdempotencyKey(String value) {
  if (!_haltApplicationIdempotencyPattern.hasMatch(value)) {
    throw const FormatException('Invalid halt application idempotency key');
  }
  return value;
}

String healthHaltApplicationId({
  required String organizationId,
  required String decisionId,
  required String idempotencyKey,
}) =>
    'halt_app_${sha256Digest(utf8.encode('$organizationId|$decisionId|$idempotencyKey')).substring(7)}';

String healthHaltTransitionIdempotencyKey(String decisionId) =>
    'health-halt:${_haltEntityId(decisionId, 'decision ID')}';
