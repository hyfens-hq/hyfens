import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'encoding.dart';

/// Product-level rollout lifecycle. This state is delivery policy only; it
/// never replaces runtime Patch Format or high-water verification.
enum RolloutState {
  draft,
  ready,
  internal,
  canary,
  expanding,
  paused,
  halted,
  completed,
  retired,
}

enum RolloutAction {
  ready,
  startInternal,
  startCanary,
  startExpanding,
  expand,
  pause,
  resume,
  halt,
  complete,
  retire,
}

enum RolloutCohortKind { percentage, internal }

const String rolloutExposureMode = 'deterministic_re_evaluate';

extension RolloutStateWire on RolloutState {
  String get wireName => name.toUpperCase();

  bool get servesCandidate => switch (this) {
    RolloutState.internal ||
    RolloutState.canary ||
    RolloutState.expanding ||
    RolloutState.completed => true,
    RolloutState.draft ||
    RolloutState.ready ||
    RolloutState.paused ||
    RolloutState.halted ||
    RolloutState.retired => false,
  };
}

extension RolloutActionWire on RolloutAction {
  String get wireName => name;
}

RolloutState parseRolloutState(Object? value) {
  if (value is! String) throw const FormatException('Invalid rollout state');
  for (final state in RolloutState.values) {
    if (state.wireName == value || state.name == value) return state;
  }
  throw const FormatException('Unsupported rollout state');
}

RolloutAction parseRolloutAction(Object? value) {
  if (value is! String) throw const FormatException('Invalid rollout action');
  for (final action in RolloutAction.values) {
    if (action.wireName == value || action.name == value) return action;
  }
  throw const FormatException('Unsupported rollout action');
}

RolloutCohortKind parseRolloutCohortKind(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid rollout cohort kind');
  }
  for (final kind in RolloutCohortKind.values) {
    if (kind.name == value || kind.name.toUpperCase() == value) return kind;
  }
  throw const FormatException('Unsupported rollout cohort kind');
}

/// Immutable application/release/patch/artifact identity targeted by a
/// rollout revision.
final class RolloutTarget {
  RolloutTarget({
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String platformId,
    required String releaseId,
    required String runtimeReleaseId,
    required String patchId,
    required String runtimePatchId,
    required String artifactId,
    required String sha256,
    required this.sequence,
  }) : organizationId = requireOpaqueId(organizationId, 'organization ID'),
       applicationId = requireOpaqueId(applicationId, 'application ID'),
       environmentId = requireOpaqueId(environmentId, 'environment ID'),
       platformId = requireOpaqueId(platformId, 'platform ID'),
       releaseId = requireOpaqueId(releaseId, 'release ID'),
       runtimeReleaseId = requireRuntimeIdentity(
         runtimeReleaseId,
         'runtime release ID',
       ),
       patchId = requireOpaqueId(patchId, 'patch ID'),
       runtimePatchId = requireRuntimeIdentity(
         runtimePatchId,
         'runtime patch ID',
       ),
       artifactId = requireOpaqueId(artifactId, 'artifact ID'),
       sha256 = requireSha256Digest(sha256) {
    if (sequence <= 0) throw const FormatException('Invalid rollout sequence');
  }

  final String organizationId;
  final String applicationId;
  final String environmentId;
  final String platformId;
  final String releaseId;
  final String runtimeReleaseId;
  final String patchId;
  final String runtimePatchId;
  final String artifactId;
  final String sha256;
  final int sequence;

  Map<String, Object?> toJson() => <String, Object?>{
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'platformId': platformId,
    'releaseId': releaseId,
    'runtimeReleaseId': runtimeReleaseId,
    'patchId': patchId,
    'runtimePatchId': runtimePatchId,
    'artifactId': artifactId,
    'sha256': sha256,
    'sequence': sequence,
  };

  static RolloutTarget fromJson(Object? value) {
    final map = _object(value, 'rollout target');
    _exactKeys(map, const {
      'organizationId',
      'applicationId',
      'environmentId',
      'platformId',
      'releaseId',
      'runtimeReleaseId',
      'patchId',
      'runtimePatchId',
      'artifactId',
      'sha256',
      'sequence',
    }, 'rollout target');
    return RolloutTarget(
      organizationId: _string(map['organizationId'], 'organization ID'),
      applicationId: _string(map['applicationId'], 'application ID'),
      environmentId: _string(map['environmentId'], 'environment ID'),
      platformId: _string(map['platformId'], 'platform ID'),
      releaseId: _string(map['releaseId'], 'release ID'),
      runtimeReleaseId: _string(map['runtimeReleaseId'], 'runtime release ID'),
      patchId: _string(map['patchId'], 'patch ID'),
      runtimePatchId: _string(map['runtimePatchId'], 'runtime patch ID'),
      artifactId: _string(map['artifactId'], 'artifact ID'),
      sha256: _string(map['sha256'], 'artifact digest'),
      sequence: _int(map['sequence'], 'rollout sequence'),
    );
  }
}

/// Eligibility policy stored in a rollout revision. Internal cohort entries
/// are hashes of installation identifiers; raw identifiers are never stored.
final class RolloutPolicy {
  RolloutPolicy({
    required this.cohortKind,
    required this.percentageBasisPoints,
    required String salt,
    Iterable<String> internalInstallationHashes = const <String>[],
    this.exposureMode = rolloutExposureMode,
  }) : salt = requireNonEmpty(salt, 'rollout salt', maxLength: 128),
       internalInstallationHashes = _canonicalInstallationHashes(
         internalInstallationHashes,
       ) {
    if (percentageBasisPoints < 0 || percentageBasisPoints > 10000) {
      throw const FormatException(
        'Rollout percentage must be between 0 and 10000 basis points',
      );
    }
    if (exposureMode != rolloutExposureMode) {
      throw const FormatException('Unsupported rollout exposure mode');
    }
    if (cohortKind == RolloutCohortKind.percentage &&
        this.internalInstallationHashes.isNotEmpty) {
      throw const FormatException(
        'Percentage cohorts cannot contain internal installations',
      );
    }
    if (cohortKind == RolloutCohortKind.internal &&
        this.internalInstallationHashes.isEmpty) {
      throw const FormatException(
        'Internal cohorts require installation hashes',
      );
    }
    if (cohortKind == RolloutCohortKind.internal &&
        percentageBasisPoints != 0) {
      throw const FormatException(
        'Internal cohorts must use zero percentage basis points',
      );
    }
  }

  final RolloutCohortKind cohortKind;
  final int percentageBasisPoints;
  final String salt;
  final List<String> internalInstallationHashes;
  final String exposureMode;

  Map<String, Object?> toJson() => <String, Object?>{
    'cohortKind': cohortKind.name,
    'percentageBasisPoints': percentageBasisPoints,
    'salt': salt,
    'internalInstallationHashes': internalInstallationHashes,
    'exposureMode': exposureMode,
  };

  static RolloutPolicy fromJson(Object? value) {
    final map = _object(value, 'rollout policy');
    _exactKeys(map, const {
      'cohortKind',
      'percentageBasisPoints',
      'salt',
      'internalInstallationHashes',
      'exposureMode',
    }, 'rollout policy');
    final rawHashes = map['internalInstallationHashes'];
    if (rawHashes is! List<Object?> ||
        rawHashes.any((item) => item is! String)) {
      throw const FormatException('Invalid internal installation hashes');
    }
    return RolloutPolicy(
      cohortKind: parseRolloutCohortKind(map['cohortKind']),
      percentageBasisPoints: _int(
        map['percentageBasisPoints'],
        'rollout percentage',
      ),
      salt: _string(map['salt'], 'rollout salt'),
      internalInstallationHashes: rawHashes.cast<String>(),
      exposureMode: _string(map['exposureMode'], 'rollout exposure mode'),
    );
  }
}

/// Immutable revision containing both lifecycle state and eligibility policy.
final class RolloutRevision {
  RolloutRevision({
    required String id,
    required String rolloutId,
    required String organizationId,
    required this.revision,
    required this.previousRevision,
    required this.state,
    required this.target,
    required this.policy,
    required String actorId,
    required String reason,
    required this.pausedFromState,
    required this.createdAt,
  }) : id = requireOpaqueId(id, 'rollout revision ID'),
       rolloutId = requireOpaqueId(rolloutId, 'rollout ID'),
       organizationId = requireOpaqueId(organizationId, 'organization ID'),
       actorId = requireOpaqueId(actorId, 'rollout actor ID'),
       reason = requireNonEmpty(reason, 'rollout reason', maxLength: 512) {
    if (revision <= 0 ||
        (revision == 1 && previousRevision != null) ||
        (revision > 1 && previousRevision != revision - 1)) {
      throw const FormatException('Invalid rollout revision sequence');
    }
    if (state == RolloutState.paused) {
      if (pausedFromState == null || !pausedFromState!.servesCandidate) {
        throw const FormatException('Paused rollout must retain active state');
      }
    } else if (pausedFromState != null) {
      throw const FormatException(
        'Only paused rollouts may retain a resume state',
      );
    }
    if (target.organizationId != organizationId) {
      throw const FormatException('Rollout target tenant does not match');
    }
  }

  final String id;
  final String rolloutId;
  final String organizationId;
  final int revision;
  final int? previousRevision;
  final RolloutState state;
  final RolloutTarget target;
  final RolloutPolicy policy;
  final String actorId;
  final String reason;
  final RolloutState? pausedFromState;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'rolloutId': rolloutId,
    'organizationId': organizationId,
    'revision': revision,
    'previousRevision': previousRevision,
    'state': state.wireName,
    'target': target.toJson(),
    'policy': policy.toJson(),
    'actorId': actorId,
    'reason': reason,
    'pausedFromState': pausedFromState?.wireName,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static RolloutRevision fromJson(Object? value) {
    final map = _object(value, 'rollout revision');
    _exactKeys(map, const {
      'id',
      'rolloutId',
      'organizationId',
      'revision',
      'previousRevision',
      'state',
      'target',
      'policy',
      'actorId',
      'reason',
      'pausedFromState',
      'createdAt',
    }, 'rollout revision');
    return RolloutRevision(
      id: _string(map['id'], 'rollout revision ID'),
      rolloutId: _string(map['rolloutId'], 'rollout ID'),
      organizationId: _string(map['organizationId'], 'organization ID'),
      revision: _int(map['revision'], 'rollout revision'),
      previousRevision: _optionalInt(map['previousRevision']),
      state: parseRolloutState(map['state']),
      target: RolloutTarget.fromJson(map['target']),
      policy: RolloutPolicy.fromJson(map['policy']),
      actorId: _string(map['actorId'], 'rollout actor ID'),
      reason: _string(map['reason'], 'rollout reason'),
      pausedFromState: map['pausedFromState'] == null
          ? null
          : parseRolloutState(map['pausedFromState']),
      createdAt: _dateTime(map['createdAt'], 'rollout revision timestamp'),
    );
  }
}

/// Mutable pointer to the latest immutable revision.
final class RolloutRecord {
  RolloutRecord({
    required String id,
    required String organizationId,
    required this.currentRevision,
    required this.state,
    required this.createdAt,
  }) : id = requireOpaqueId(id, 'rollout ID'),
       organizationId = requireOpaqueId(organizationId, 'organization ID') {
    if (currentRevision <= 0) {
      throw const FormatException('Invalid current rollout revision');
    }
  }

  final String id;
  final String organizationId;
  final int currentRevision;
  final RolloutState state;
  final DateTime createdAt;

  RolloutRecord copyWith({int? currentRevision, RolloutState? state}) =>
      RolloutRecord(
        id: id,
        organizationId: organizationId,
        currentRevision: currentRevision ?? this.currentRevision,
        state: state ?? this.state,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'currentRevision': currentRevision,
    'state': state.wireName,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static RolloutRecord fromJson(Object? value) {
    final map = _object(value, 'rollout record');
    _exactKeys(map, const {
      'id',
      'organizationId',
      'currentRevision',
      'state',
      'createdAt',
    }, 'rollout record');
    return RolloutRecord(
      id: _string(map['id'], 'rollout ID'),
      organizationId: _string(map['organizationId'], 'organization ID'),
      currentRevision: _int(map['currentRevision'], 'current rollout revision'),
      state: parseRolloutState(map['state']),
      createdAt: _dateTime(map['createdAt'], 'rollout timestamp'),
    );
  }
}

final class RolloutSpec {
  RolloutSpec({
    required String applicationId,
    required String environmentId,
    required String platformId,
    required String releaseId,
    required String patchId,
    required this.percentageBasisPoints,
    this.cohortKind = RolloutCohortKind.percentage,
    Iterable<String> internalInstallationHashes = const <String>[],
  }) : applicationId = requireOpaqueId(applicationId, 'application ID'),
       environmentId = requireOpaqueId(environmentId, 'environment ID'),
       platformId = requireOpaqueId(platformId, 'platform ID'),
       releaseId = requireOpaqueId(releaseId, 'release ID'),
       patchId = requireOpaqueId(patchId, 'patch ID'),
       internalInstallationHashes = _canonicalInstallationHashes(
         internalInstallationHashes,
       ) {
    if (percentageBasisPoints < 0 || percentageBasisPoints > 10000) {
      throw const FormatException(
        'Rollout percentage must be between 0 and 10000 basis points',
      );
    }
    if (cohortKind == RolloutCohortKind.percentage &&
        this.internalInstallationHashes.isNotEmpty) {
      throw const FormatException(
        'Percentage cohorts cannot contain internal installations',
      );
    }
    if (cohortKind == RolloutCohortKind.internal &&
        this.internalInstallationHashes.isEmpty) {
      throw const FormatException(
        'Internal cohorts require installation hashes',
      );
    }
    if (cohortKind == RolloutCohortKind.internal &&
        percentageBasisPoints != 0) {
      throw const FormatException(
        'Internal cohorts must use zero percentage basis points',
      );
    }
  }

  final String applicationId;
  final String environmentId;
  final String platformId;
  final String releaseId;
  final String patchId;
  final int percentageBasisPoints;
  final RolloutCohortKind cohortKind;
  final List<String> internalInstallationHashes;

  Map<String, Object?> toJson() => <String, Object?>{
    'applicationId': applicationId,
    'environmentId': environmentId,
    'platformId': platformId,
    'releaseId': releaseId,
    'patchId': patchId,
    'percentageBasisPoints': percentageBasisPoints,
    'cohortKind': cohortKind.name,
    'internalInstallationHashes': internalInstallationHashes,
  };
}

final class RolloutSnapshot {
  const RolloutSnapshot({
    required this.rollout,
    required this.revision,
    required this.history,
  });

  final RolloutRecord rollout;
  final RolloutRevision revision;
  final List<RolloutRevision> history;

  Map<String, Object?> toJson() => <String, Object?>{
    'rollout': rollout.toJson(),
    'revision': revision.toJson(),
    'history': history.map((item) => item.toJson()).toList(growable: false),
  };
}

/// Pure deterministic cohort evaluator. It returns false for all non-serving
/// lifecycle states and never changes runtime trust or local high-water.
final class RolloutEligibility {
  RolloutEligibility._();

  static bool isEligible({
    required RolloutRevision revision,
    required String installationId,
  }) {
    if (!revision.state.servesCandidate || installationId.isEmpty) return false;
    if (revision.policy.cohortKind == RolloutCohortKind.internal) {
      return revision.policy.internalInstallationHashes.contains(
        installationHash(installationId),
      );
    }
    return bucketFor(revision: revision, installationId: installationId) <
        thresholdFor(revision.policy.percentageBasisPoints);
  }

  static String installationHash(String installationId) {
    final normalized = requireRuntimeIdentity(
      installationId,
      'installation ID',
    );
    return sha256Hex(utf8.encode(normalized));
  }

  static BigInt bucketFor({
    required RolloutRevision revision,
    required String installationId,
  }) {
    final normalized = requireRuntimeIdentity(
      installationId,
      'installation ID',
    );
    final input = <String>[
      'hyfens.rollout.cohort.v1',
      revision.organizationId,
      revision.target.applicationId,
      revision.target.environmentId,
      revision.target.platformId,
      revision.target.releaseId,
      normalized,
      revision.policy.salt,
    ].join('\u0000');
    final digest = sha256.convert(utf8.encode(input)).bytes;
    var bucket = BigInt.zero;
    for (final byte in digest.take(8)) {
      bucket = (bucket << 8) | BigInt.from(byte);
    }
    return bucket;
  }

  static BigInt thresholdFor(int percentageBasisPoints) {
    if (percentageBasisPoints < 0 || percentageBasisPoints > 10000) {
      throw const FormatException('Rollout percentage is out of range');
    }
    return (BigInt.from(percentageBasisPoints) * (BigInt.one << 64)) ~/
        BigInt.from(10000);
  }
}

/// Computes the next lifecycle state for one explicit action. A null result
/// means the transition is not permitted from the current state.
RolloutState? nextRolloutState(
  RolloutState current,
  RolloutAction action, {
  RolloutState? pausedFromState,
}) => switch (action) {
  RolloutAction.ready =>
    current == RolloutState.draft ? RolloutState.ready : null,
  RolloutAction.startInternal =>
    current == RolloutState.ready ? RolloutState.internal : null,
  RolloutAction.startCanary =>
    current == RolloutState.ready || current == RolloutState.internal
        ? RolloutState.canary
        : null,
  RolloutAction.startExpanding =>
    current == RolloutState.ready ? RolloutState.expanding : null,
  RolloutAction.expand =>
    current == RolloutState.canary || current == RolloutState.expanding
        ? RolloutState.expanding
        : null,
  RolloutAction.pause =>
    current.servesCandidate && current != RolloutState.completed
        ? RolloutState.paused
        : null,
  RolloutAction.resume =>
    current == RolloutState.paused ? pausedFromState : null,
  RolloutAction.halt =>
    current == RolloutState.internal ||
            current == RolloutState.canary ||
            current == RolloutState.expanding ||
            current == RolloutState.paused
        ? RolloutState.halted
        : null,
  RolloutAction.complete =>
    current == RolloutState.expanding ? RolloutState.completed : null,
  RolloutAction.retire =>
    current == RolloutState.draft ||
            current == RolloutState.ready ||
            current == RolloutState.halted ||
            current == RolloutState.completed
        ? RolloutState.retired
        : null,
};

List<String> _canonicalInstallationHashes(Iterable<String> values) {
  final normalized = values.map(_normalizeInstallationHash).toList()..sort();
  if (normalized.toSet().length != normalized.length) {
    throw const FormatException('Duplicate internal installation hash');
  }
  return List.unmodifiable(normalized);
}

String _normalizeInstallationHash(String value) {
  final normalized = value.startsWith('sha256:') ? value.substring(7) : value;
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
    throw const FormatException('Invalid internal installation hash');
  }
  return normalized;
}

Map<String, Object?> _object(Object? value, String field) {
  if (value is! Map) throw FormatException('Invalid $field');
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

void _exactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String field,
) {
  if (value.keys.toSet().length != expected.length ||
      value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    throw FormatException('Invalid $field fields');
  }
}

String _string(Object? value, String field) {
  if (value is! String) throw FormatException('Invalid $field');
  return value;
}

int _int(Object? value, String field) {
  if (value is! int) throw FormatException('Invalid $field');
  return value;
}

int? _optionalInt(Object? value) {
  if (value == null) return null;
  return _int(value, 'previous rollout revision');
}

DateTime _dateTime(Object? value, String field) {
  final text = _string(value, field);
  final parsed = DateTime.tryParse(text);
  if (parsed == null) throw FormatException('Invalid $field');
  return parsed.toUtc();
}
