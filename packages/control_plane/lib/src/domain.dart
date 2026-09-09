import 'dart:convert';

import 'encoding.dart';
import 'observation.dart';

export 'content.dart';

String _lifecycleStatus(String value, String field) {
  if (value != 'active' && value != 'archived') {
    throw FormatException('Invalid $field');
  }
  return value;
}

DateTime? _optionalTimestamp(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid timestamp');
  return DateTime.parse(value).toUtc();
}

enum CredentialKind { control, delivery, observation, scheduler, autoHalt }

const String contentAdminScope = 'content:admin';
const String billingReadScope = 'billing:read';

/// Customer-owned billing lifecycle actions. This is deliberately separate
/// from [billingWriteScope], which remains an operator/provider-administration
/// scope for plan and subscription records.
const String billingManageScope = 'billing:manage';
const String billingWriteScope = 'billing:write';
const String organizationMembersReadScope = 'organization:members:read';
const String organizationMembersWriteScope = 'organization:members:write';
const String credentialReadScope = 'credential:read';
const String applicationWriteScope = 'application:write';
const String environmentWriteScope = 'environment:write';
const String supportReadScope = 'support:read';
const String supportCreateScope = 'support:create';
const String supportReplyScope = 'support:reply';
const String runtimeInstallScope = 'runtime:install';

/// Narrow service capability for provider lifecycle processing. This is not
/// included in customer or operator credential scope sets.
const String billingProviderScope = 'billing:provider';
const String organizationMembersReadScope = 'organization:members:read';
const String credentialReadScope = 'credential:read';
const String applicationWriteScope = 'application:write';
const String environmentWriteScope = 'environment:write';
const String environmentRollbackScope = 'environment:rollback';

const Set<String> controlScopes = <String>{
  'application:read',
  applicationWriteScope,
  'release:read',
  'release:write',
  'patch:read',
  'patch:write',
  'artifact:read',
  'artifact:write',
  environmentWriteScope,
  environmentRollbackScope,
  'release:promote',
  'bundle:read',
  'bundle:write',
  'audit:read',
  organizationMembersReadScope,
  credentialReadScope,
  'credential:issue',
  'credential:revoke',
  'artifact:reconcile',
  'rollout:read',
  'rollout:create',
  'rollout:update',
  'rollout:promote',
  'rollout:halt',
  'observation:read',
  'health:evaluate',
  'health:schedule',
  billingReadScope,
  billingWriteScope,
  supportReadScope,
  supportCreateScope,
  supportReplyScope,
  contentAdminScope,
  observationDeleteScope,
};

/// The full tenant-owner surface without platform/CMS mutation or provider
/// subscription administration. Public Cloud customer owners use this
/// profile; operator bootstrap credentials continue to use [controlScopes].
final Set<String> customerOwnerScopes = Set.unmodifiable(
  <String>{
      ...controlScopes,
      billingManageScope,
      billingWriteScope,
      contentAdminScope,
    }
    ..remove(billingWriteScope)
    ..remove(contentAdminScope),
);

const Set<String> deliveryScopes = <String>{
  'runtime:update:read',
  'runtime:artifact:read',
  runtimeInstallScope,
};

const Set<String> observationScopes = <String>{observationWriteScope};

/// A scheduler credential is application/environment scoped and deliberately
/// excludes credential administration, artifact/release mutation, signing,
/// and generic rollout mutation. Individual grants remain independent.
const Set<String> schedulerScopes = <String>{
  'health:work:claim',
  'health:evaluate',
  'observation:read',
  'rollout:read',
};

const Set<String> evaluationOnlySchedulerScopes = <String>{
  'health:work:claim',
  'health:evaluate',
  'observation:read',
  'rollout:read',
};

const Set<String> autoHaltScopes = <String>{
  'health:work:apply-halt',
  'rollout:read',
  'rollout:halt',
};

final class OrganizationRecord {
  OrganizationRecord({
    required String id,
    required String name,
    required this.createdAt,
    this.deletionState = 'active',
    this.deletionRequestedAt,
    this.deletedAt,
    this.deletionRequestId,
  }) : id = requireOpaqueId(id, 'organization ID'),
       name = requireNonEmpty(name, 'organization name') {
    if (!const <String>{
      'active',
      'deletion_requested',
      'deleted',
    }.contains(deletionState)) {
      throw const FormatException('Invalid organization deletion state');
    }
  }

  final String id;
  final String name;
  final DateTime createdAt;
  final String deletionState;
  final DateTime? deletionRequestedAt;
  final DateTime? deletedAt;
  final String? deletionRequestId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'deletionState': deletionState,
    if (deletionRequestedAt != null)
      'deletionRequestedAt': deletionRequestedAt!.toUtc().toIso8601String(),
    if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
    if (deletionRequestId != null) 'deletionRequestId': deletionRequestId,
  };

  static OrganizationRecord fromJson(Map<String, Object?> value) =>
      OrganizationRecord(
        id: value['id']! as String,
        name: value['name']! as String,
        createdAt: DateTime.parse(value['createdAt']! as String),
        deletionState: value['deletionState'] as String? ?? 'active',
        deletionRequestedAt: value['deletionRequestedAt'] is String
            ? DateTime.parse(value['deletionRequestedAt']! as String)
            : null,
        deletedAt: value['deletedAt'] is String
            ? DateTime.parse(value['deletedAt']! as String)
            : null,
        deletionRequestId: value['deletionRequestId'] as String?,
      );
}

final class ApplicationRecord {
  ApplicationRecord({
    required String id,
    required String organizationId,
    required String runtimeApplicationId,
    String? name,
    String? platform,
    required this.createdAt,
    this.status = 'active',
    DateTime? updatedAt,
  }) : id = requireOpaqueId(id, 'application ID'),
       organizationId = requireOpaqueId(organizationId, 'organization ID'),
       runtimeApplicationId = requireRuntimeIdentity(
         runtimeApplicationId,
         'runtime application ID',
       ),
       name = name == null
           ? null
           : requireNonEmpty(name.trim(), 'application name', maxLength: 120),
       platform = platform == null ? null : _applicationPlatform(platform);

  final String id;
  final String organizationId;
  final String runtimeApplicationId;
  final String? name;
  final String? platform;
  final DateTime createdAt;
  final String status;
  final DateTime updatedAt;

  ApplicationRecord copyWith({
    String? name,
    String? status,
    DateTime? updatedAt,
  }) => ApplicationRecord(
    id: id,
    organizationId: organizationId,
    runtimeApplicationId: runtimeApplicationId,
    name: name ?? this.name,
    platform: platform,
    createdAt: createdAt,
    status: status ?? this.status,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'runtimeApplicationId': runtimeApplicationId,
    'name': name,
    'platform': platform,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static ApplicationRecord fromJson(Map<String, Object?> value) =>
      ApplicationRecord(
        id: value['id']! as String,
        organizationId: value['organizationId']! as String,
        runtimeApplicationId: value['runtimeApplicationId']! as String,
        name: value['name'] as String?,
        platform: value['platform'] as String?,
        createdAt: DateTime.parse(value['createdAt']! as String),
        status: value['status'] as String? ?? 'active',
        updatedAt:
            _optionalTimestamp(value['updatedAt']) ??
            DateTime.parse(value['createdAt']! as String),
      );

  static String _applicationPlatform(String value) {
    if (value != 'android' && value != 'ios') {
      throw const FormatException(
        'Application platform must be android or ios',
      );
    }
    return value;
  }
}

final class EnvironmentRecord {
  EnvironmentRecord({
    required String id,
    required String organizationId,
    required String applicationId,
    required String name,
    required this.version,
    required String? promotedReleaseId,
    required this.createdAt,
    this.status = 'active',
    DateTime? updatedAt,
  }) : id = requireOpaqueId(id, 'environment ID'),
       organizationId = requireOpaqueId(organizationId, 'organization ID'),
       applicationId = requireOpaqueId(applicationId, 'application ID'),
       name = requireNonEmpty(name, 'environment name'),
       promotedReleaseId = promotedReleaseId == null
           ? null
           : requireOpaqueId(promotedReleaseId, 'release ID'),
       updatedAt = (updatedAt ?? createdAt).toUtc() {
    if (version < 0) throw const FormatException('Invalid environment version');
    _lifecycleStatus(status, 'environment status');
  }

  final String id;
  final String organizationId;
  final String applicationId;
  final String name;
  final int version;
  final String? promotedReleaseId;
  final DateTime createdAt;
  final String status;
  final DateTime updatedAt;

  EnvironmentRecord copyWith({
    int? version,
    String? promotedReleaseId,
    String? name,
    String? status,
    DateTime? updatedAt,
  }) => EnvironmentRecord(
    id: id,
    organizationId: organizationId,
    applicationId: applicationId,
    name: name ?? this.name,
    version: version ?? this.version,
    promotedReleaseId: promotedReleaseId ?? this.promotedReleaseId,
    createdAt: createdAt,
    status: status ?? this.status,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'applicationId': applicationId,
    'name': name,
    'version': version,
    'promotedReleaseId': promotedReleaseId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static EnvironmentRecord fromJson(Map<String, Object?> value) =>
      EnvironmentRecord(
        id: value['id']! as String,
        organizationId: value['organizationId']! as String,
        applicationId: value['applicationId']! as String,
        name: value['name']! as String,
        version: value['version']! as int,
        promotedReleaseId: value['promotedReleaseId'] as String?,
        createdAt: DateTime.parse(value['createdAt']! as String),
        status: value['status'] as String? ?? 'active',
        updatedAt:
            _optionalTimestamp(value['updatedAt']) ??
            DateTime.parse(value['createdAt']! as String),
      );
}

enum RuntimeDesiredState { patch, base }

extension RuntimeDesiredStateWire on RuntimeDesiredState {
  String get wireValue => switch (this) {
    RuntimeDesiredState.patch => 'patch',
    RuntimeDesiredState.base => 'base',
  };

  static RuntimeDesiredState parse(Object? value) => switch (value) {
    'patch' => RuntimeDesiredState.patch,
    'base' => RuntimeDesiredState.base,
    _ => throw const FormatException('Invalid runtime desired state'),
  };
}

/// The mutable desired runtime state for one environment.
///
/// Deployment history remains in immutable audit records and the environment
/// release pointer. This record only answers what a connected runtime should
/// be running now, so a base rollback never rewrites deployment history.
final class EnvironmentRuntimeStateRecord {
  EnvironmentRuntimeStateRecord({
    required String id,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required this.desiredState,
    required String releaseId,
    required String runtimeReleaseId,
    required this.environmentVersion,
    required this.revision,
    required String actorId,
    required this.updatedAt,
    String? rollbackControl,
  }) : id = requireOpaqueId(id, 'runtime state ID'),
       organizationId = requireOpaqueId(organizationId, 'organization ID'),
       applicationId = requireOpaqueId(applicationId, 'application ID'),
       environmentId = requireOpaqueId(environmentId, 'environment ID'),
       releaseId = requireOpaqueId(releaseId, 'release ID'),
       runtimeReleaseId = requireRuntimeIdentity(
         runtimeReleaseId,
         'runtime release ID',
       ),
       actorId = requireOpaqueId(actorId, 'runtime state actor ID'),
       rollbackControl = rollbackControl == null
           ? null
           : requireNonEmpty(
               rollbackControl,
               'rollback control',
               maxLength: 32768,
             ) {
    if (environmentVersion < 0 || revision < 1) {
      throw const FormatException('Invalid runtime state revision');
    }
    if (desiredState == RuntimeDesiredState.base && rollbackControl == null) {
      throw const FormatException(
        'Base runtime state requires a rollback control',
      );
    }
    if (desiredState == RuntimeDesiredState.patch && rollbackControl != null) {
      throw const FormatException(
        'Patch runtime state cannot carry a rollback control',
      );
    }
  }

  final String id;
  final String organizationId;
  final String applicationId;
  final String environmentId;
  final RuntimeDesiredState desiredState;
  final String releaseId;
  final String runtimeReleaseId;
  final int environmentVersion;
  final int revision;
  final String actorId;
  final DateTime updatedAt;
  final String? rollbackControl;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'desiredState': desiredState.wireValue,
    'releaseId': releaseId,
    'runtimeReleaseId': runtimeReleaseId,
    'environmentVersion': environmentVersion,
    'revision': revision,
    'actorId': actorId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'rollbackControl': rollbackControl,
  };

  static EnvironmentRuntimeStateRecord fromJson(Map<String, Object?> value) =>
      EnvironmentRuntimeStateRecord(
        id: value['id']! as String,
        organizationId: value['organizationId']! as String,
        applicationId: value['applicationId']! as String,
        environmentId: value['environmentId']! as String,
        desiredState: RuntimeDesiredStateWire.parse(value['desiredState']),
        releaseId: value['releaseId']! as String,
        runtimeReleaseId: value['runtimeReleaseId']! as String,
        environmentVersion: value['environmentVersion']! as int,
        revision: value['revision']! as int,
        actorId: value['actorId']! as String,
        updatedAt: DateTime.parse(value['updatedAt']! as String),
        rollbackControl: value['rollbackControl'] as String?,
      );
}

final class ReleaseRecord {
  ReleaseRecord({
    required String id,
    required String organizationId,
    required String applicationId,
    required String platformId,
    required String runtimeApplicationId,
    required String runtimeReleaseId,
    required String buildTarget,
    required this.runtimeCompatibilityVersion,
    required this.patchFormatVersion,
    required this.buildFingerprint,
    required this.capabilityAuthorityDigest,
    required this.functionSignatureDigest,
    required this.displayVersion,
    required Map<String, String> signingPublicKeys,
    required this.createdAt,
  }) : id = requireOpaqueId(id, 'release ID'),
       organizationId = requireOpaqueId(organizationId, 'organization ID'),
       applicationId = requireOpaqueId(applicationId, 'application ID'),
       platformId = requireOpaqueId(platformId, 'platform ID'),
       runtimeApplicationId = requireRuntimeIdentity(
         runtimeApplicationId,
         'runtime application ID',
       ),
       runtimeReleaseId = requireRuntimeIdentity(
         runtimeReleaseId,
         'runtime release ID',
       ),
       buildTarget = requireNonEmpty(buildTarget, 'build target'),
       signingPublicKeys = Map.unmodifiable(signingPublicKeys);

  final String id;
  final String organizationId;
  final String applicationId;
  final String platformId;
  final String runtimeApplicationId;
  final String runtimeReleaseId;
  final String buildTarget;
  final int runtimeCompatibilityVersion;
  final int patchFormatVersion;
  final String buildFingerprint;
  final String capabilityAuthorityDigest;
  final String functionSignatureDigest;
  final String displayVersion;
  final Map<String, String> signingPublicKeys;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'applicationId': applicationId,
    'platformId': platformId,
    'runtimeApplicationId': runtimeApplicationId,
    'runtimeReleaseId': runtimeReleaseId,
    'buildTarget': buildTarget,
    'runtimeCompatibilityVersion': runtimeCompatibilityVersion,
    'patchFormatVersion': patchFormatVersion,
    'buildFingerprint': buildFingerprint,
    'capabilityAuthorityDigest': capabilityAuthorityDigest,
    'functionSignatureDigest': functionSignatureDigest,
    'displayVersion': displayVersion,
    'signingPublicKeys': signingPublicKeys,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static ReleaseRecord fromJson(Map<String, Object?> value) {
    final keys = value['signingPublicKeys'];
    if (keys is! Map<String, Object?> ||
        keys.values.any((item) => item is! String)) {
      throw const FormatException('Invalid release signing keys');
    }
    return ReleaseRecord(
      id: value['id']! as String,
      organizationId: value['organizationId']! as String,
      applicationId: value['applicationId']! as String,
      platformId: value['platformId']! as String,
      runtimeApplicationId: value['runtimeApplicationId']! as String,
      runtimeReleaseId: value['runtimeReleaseId']! as String,
      buildTarget: value['buildTarget']! as String,
      runtimeCompatibilityVersion: value['runtimeCompatibilityVersion']! as int,
      patchFormatVersion: value['patchFormatVersion']! as int,
      buildFingerprint: value['buildFingerprint']! as String,
      capabilityAuthorityDigest: value['capabilityAuthorityDigest']! as String,
      functionSignatureDigest: value['functionSignatureDigest']! as String,
      displayVersion: value['displayVersion']! as String,
      signingPublicKeys: keys.map(
        (key, item) => MapEntry(key, item! as String),
      ),
      createdAt: DateTime.parse(value['createdAt']! as String),
    );
  }
}

final class PatchRecord {
  PatchRecord({
    required String id,
    required String organizationId,
    required String releaseId,
    required String runtimePatchId,
    required this.sequence,
    required String artifactId,
    required String sha256,
    required this.sizeBytes,
    required String signatureKeyId,
    required this.state,
    required this.createdAt,
  }) : id = requireOpaqueId(id, 'patch ID'),
       organizationId = requireOpaqueId(organizationId, 'organization ID'),
       releaseId = requireOpaqueId(releaseId, 'release ID'),
       runtimePatchId = requireRuntimeIdentity(
         runtimePatchId,
         'runtime patch ID',
       ),
       artifactId = requireOpaqueId(artifactId, 'artifact ID'),
       sha256 = requireSha256Digest(sha256),
       signatureKeyId = requireNonEmpty(signatureKeyId, 'signature key ID') {
    if (sequence <= 0 || sizeBytes <= 0) {
      throw const FormatException('Invalid patch sequence or size');
    }
  }

  final String id;
  final String organizationId;
  final String releaseId;
  final String runtimePatchId;
  final int sequence;
  final String artifactId;
  final String sha256;
  final int sizeBytes;
  final String signatureKeyId;
  final String state;
  final DateTime createdAt;

  PatchRecord copyWith({String? state}) => PatchRecord(
    id: id,
    organizationId: organizationId,
    releaseId: releaseId,
    runtimePatchId: runtimePatchId,
    sequence: sequence,
    artifactId: artifactId,
    sha256: sha256,
    sizeBytes: sizeBytes,
    signatureKeyId: signatureKeyId,
    state: state ?? this.state,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'releaseId': releaseId,
    'runtimePatchId': runtimePatchId,
    'sequence': sequence,
    'artifactId': artifactId,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
    'signatureKeyId': signatureKeyId,
    'state': state,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static PatchRecord fromJson(Map<String, Object?> value) => PatchRecord(
    id: value['id']! as String,
    organizationId: value['organizationId']! as String,
    releaseId: value['releaseId']! as String,
    runtimePatchId: value['runtimePatchId']! as String,
    sequence: value['sequence']! as int,
    artifactId: value['artifactId']! as String,
    sha256: value['sha256']! as String,
    sizeBytes: value['sizeBytes']! as int,
    signatureKeyId: value['signatureKeyId']! as String,
    state: value['state']! as String,
    createdAt: DateTime.parse(value['createdAt']! as String),
  );
}

final class ArtifactRecord {
  ArtifactRecord({
    required String id,
    required String organizationId,
    required String patchId,
    required String sha256,
    required this.sizeBytes,
    required String contentType,
    required this.state,
    required this.createdAt,
    DateTime? purgeEligibleAt,
    DateTime? purgedAt,
    String? purgeReason,
  }) : id = requireOpaqueId(id, 'artifact ID'),
       organizationId = requireOpaqueId(organizationId, 'organization ID'),
       patchId = requireOpaqueId(patchId, 'patch ID'),
       sha256 = requireSha256Digest(sha256),
       contentType = requireNonEmpty(
         contentType,
         'content type',
         maxLength: 128,
       ),
       purgeEligibleAt = purgeEligibleAt?.toUtc(),
       purgedAt = purgedAt?.toUtc(),
       purgeReason = purgeReason == null
           ? null
           : requireNonEmpty(
               purgeReason,
               'artifact purge reason',
               maxLength: 256,
             );

  final String id;
  final String organizationId;
  final String patchId;
  final String sha256;
  final int sizeBytes;
  final String contentType;
  final String state;
  final DateTime createdAt;
  final DateTime? purgeEligibleAt;
  final DateTime? purgedAt;
  final String? purgeReason;

  ArtifactRecord copyWith({
    String? state,
    DateTime? purgeEligibleAt,
    DateTime? purgedAt,
    String? purgeReason,
    bool clearPurgeEligibleAt = false,
    bool clearPurgedAt = false,
    bool clearPurgeReason = false,
  }) => ArtifactRecord(
    id: id,
    organizationId: organizationId,
    patchId: patchId,
    sha256: sha256,
    sizeBytes: sizeBytes,
    contentType: contentType,
    state: state ?? this.state,
    createdAt: createdAt,
    purgeEligibleAt: clearPurgeEligibleAt
        ? null
        : purgeEligibleAt ?? this.purgeEligibleAt,
    purgedAt: clearPurgedAt ? null : purgedAt ?? this.purgedAt,
    purgeReason: clearPurgeReason ? null : purgeReason ?? this.purgeReason,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'patchId': patchId,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
    'contentType': contentType,
    'state': state,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (purgeEligibleAt != null)
      'purgeEligibleAt': purgeEligibleAt!.toUtc().toIso8601String(),
    if (purgedAt != null) 'purgedAt': purgedAt!.toUtc().toIso8601String(),
    if (purgeReason != null) 'purgeReason': purgeReason,
  };

  static ArtifactRecord fromJson(Map<String, Object?> value) => ArtifactRecord(
    id: value['id']! as String,
    organizationId: value['organizationId']! as String,
    patchId: value['patchId']! as String,
    sha256: value['sha256']! as String,
    sizeBytes: value['sizeBytes']! as int,
    contentType: value['contentType']! as String,
    state: value['state']! as String,
    createdAt: DateTime.parse(value['createdAt']! as String),
    purgeEligibleAt: _optionalArtifactTime(value['purgeEligibleAt']),
    purgedAt: _optionalArtifactTime(value['purgedAt']),
    purgeReason: value['purgeReason'] as String?,
  );
}

DateTime? _optionalArtifactTime(Object? value) =>
    value is String ? DateTime.parse(value) : null;

final class CredentialRecord {
  CredentialRecord({
    required String id,
    required String organizationId,
    String name = 'Credential',
    required this.kind,
    required String tokenHash,
    required Set<String> scopes,
    required String? applicationId,
    required String? environmentId,
    required this.createdAt,
    required this.expiresAt,
    required this.revoked,
  }) : id = requireOpaqueId(id, 'credential ID'),
       organizationId = requireOpaqueId(organizationId, 'organization ID'),
       name = requireNonEmpty(name.trim(), 'credential name', maxLength: 120),
       tokenHash = requireNonEmpty(tokenHash, 'token hash'),
       scopes = Set.unmodifiable(scopes),
       applicationId = applicationId == null
           ? null
           : requireOpaqueId(applicationId, 'credential application ID'),
       environmentId = environmentId == null
           ? null
           : requireOpaqueId(environmentId, 'credential environment ID') {
    final allowed = switch (kind) {
      CredentialKind.control => <String>{...controlScopes, billingManageScope},
      CredentialKind.delivery => deliveryScopes,
      CredentialKind.observation => observationScopes,
      CredentialKind.scheduler => schedulerScopes,
      CredentialKind.autoHalt => autoHaltScopes,
    };
    if (this.scopes.isEmpty || this.scopes.difference(allowed).isNotEmpty) {
      throw const FormatException('Credential contains an unsupported scope');
    }
    if (kind == CredentialKind.autoHalt &&
        (this.scopes.length != autoHaltScopes.length ||
            !this.scopes.containsAll(autoHaltScopes))) {
      throw const FormatException(
        'Auto-Halt Principal requires its exact fixed scope profile',
      );
    }
    final scopedKind =
        kind == CredentialKind.delivery ||
        kind == CredentialKind.observation ||
        kind == CredentialKind.scheduler ||
        kind == CredentialKind.autoHalt;
    if (scopedKind &&
        (this.applicationId == null || this.environmentId == null)) {
      throw const FormatException(
        'Application-scoped credential is missing its scope',
      );
    }
    if (!scopedKind &&
        (this.applicationId != null || this.environmentId != null)) {
      throw const FormatException('Credential kind cannot be resource scoped');
    }
  }

  final String id;
  final String organizationId;
  final String name;
  final CredentialKind kind;
  final String tokenHash;
  final Set<String> scopes;
  final String? applicationId;
  final String? environmentId;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool revoked;

  CredentialRecord copyWith({bool? revoked}) => CredentialRecord(
    id: id,
    organizationId: organizationId,
    name: name,
    kind: kind,
    tokenHash: tokenHash,
    scopes: scopes,
    applicationId: applicationId,
    environmentId: environmentId,
    createdAt: createdAt,
    expiresAt: expiresAt,
    revoked: revoked ?? this.revoked,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'name': name,
    'kind': kind.name,
    'tokenHash': tokenHash,
    'scopes': scopes.toList()..sort(),
    'applicationId': applicationId,
    'environmentId': environmentId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'revoked': revoked,
  };

  /// Returns the credential metadata safe for dashboard/API responses.
  ///
  /// The persisted token hash is an authorization implementation detail and
  /// must never be sent to a customer-facing client.
  Map<String, Object?> toMetadataJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'name': name,
    'kind': kind.name,
    'scopes': scopes.toList()..sort(),
    'applicationId': applicationId,
    'environmentId': environmentId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'revoked': revoked,
  };

  static CredentialRecord fromJson(Map<String, Object?> value) {
    final rawScopes = value['scopes'];
    if (rawScopes is! List<Object?> ||
        rawScopes.any((item) => item is! String)) {
      throw const FormatException('Invalid credential scopes');
    }
    return CredentialRecord(
      id: value['id']! as String,
      organizationId: value['organizationId']! as String,
      name: value['name'] as String? ?? 'Credential',
      kind: CredentialKind.values.byName(value['kind']! as String),
      tokenHash: value['tokenHash']! as String,
      scopes: rawScopes.cast<String>().toSet(),
      applicationId: value['applicationId'] as String?,
      environmentId: value['environmentId'] as String?,
      createdAt: DateTime.parse(value['createdAt']! as String),
      expiresAt: value['expiresAt'] == null
          ? null
          : DateTime.parse(value['expiresAt']! as String),
      revoked: value['revoked']! as bool,
    );
  }
}

final class AuditRecord {
  AuditRecord({
    required String id,
    required String requestId,
    required String organizationId,
    required String actorId,
    required String action,
    required String resourceType,
    required String resourceId,
    required String result,
    required Map<String, Object?> metadata,
    required this.createdAt,
  }) : id = requireOpaqueId(id, 'audit ID'),
       requestId = requireNonEmpty(requestId, 'request ID'),
       organizationId = requireOpaqueId(organizationId, 'organization ID'),
       actorId = requireNonEmpty(actorId, 'audit actor ID'),
       action = requireNonEmpty(action, 'audit action', maxLength: 128),
       resourceType = requireNonEmpty(
         resourceType,
         'audit resource type',
         maxLength: 64,
       ),
       resourceId = requireNonEmpty(resourceId, 'audit resource ID'),
       result = requireNonEmpty(result, 'audit result', maxLength: 64),
       metadata = Map.unmodifiable(metadata);

  final String id;
  final String requestId;
  final String organizationId;
  final String actorId;
  final String action;
  final String resourceType;
  final String resourceId;
  final String result;
  final Map<String, Object?> metadata;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'requestId': requestId,
    'organizationId': organizationId,
    'actorId': actorId,
    'action': action,
    'resourceType': resourceType,
    'resourceId': resourceId,
    'result': result,
    'metadata': metadata,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static AuditRecord fromJson(Map<String, Object?> value) => AuditRecord(
    id: value['id']! as String,
    requestId: value['requestId']! as String,
    organizationId: value['organizationId']! as String,
    actorId: value['actorId']! as String,
    action: value['action']! as String,
    resourceType: value['resourceType']! as String,
    resourceId: value['resourceId']! as String,
    result: value['result']! as String,
    metadata: (value['metadata']! as Map<String, Object?>),
    createdAt: DateTime.parse(value['createdAt']! as String),
  );
}

final class ReleaseSpec {
  const ReleaseSpec({
    required this.applicationId,
    required this.platformId,
    required this.runtimeApplicationId,
    required this.runtimeReleaseId,
    required this.buildTarget,
    required this.runtimeCompatibilityVersion,
    required this.patchFormatVersion,
    required this.buildFingerprint,
    required this.capabilityAuthorityDigest,
    required this.functionSignatureDigest,
    required this.displayVersion,
    required this.signingPublicKeys,
  });

  final String applicationId;
  final String platformId;
  final String runtimeApplicationId;
  final String runtimeReleaseId;
  final String buildTarget;
  final int runtimeCompatibilityVersion;
  final int patchFormatVersion;
  final String buildFingerprint;
  final String capabilityAuthorityDigest;
  final String functionSignatureDigest;
  final String displayVersion;
  final Map<String, String> signingPublicKeys;

  Map<String, Object?> toJson() => <String, Object?>{
    'applicationId': applicationId,
    'platformId': platformId,
    'runtimeApplicationId': runtimeApplicationId,
    'runtimeReleaseId': runtimeReleaseId,
    'buildTarget': buildTarget,
    'runtimeCompatibilityVersion': runtimeCompatibilityVersion,
    'patchFormatVersion': patchFormatVersion,
    'buildFingerprint': buildFingerprint,
    'capabilityAuthorityDigest': capabilityAuthorityDigest,
    'functionSignatureDigest': functionSignatureDigest,
    'displayVersion': displayVersion,
    'signingPublicKeys': signingPublicKeys,
  };
}

final class PatchSpec {
  const PatchSpec({
    required this.runtimePatchId,
    required this.sequence,
    required this.artifactId,
    required this.sha256,
    required this.sizeBytes,
    required this.signatureKeyId,
  });

  final String runtimePatchId;
  final int sequence;
  final String artifactId;
  final String sha256;
  final int sizeBytes;
  final String signatureKeyId;

  Map<String, Object?> toJson() => <String, Object?>{
    'runtimePatchId': runtimePatchId,
    'sequence': sequence,
    'artifactId': artifactId,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
    'signatureKeyId': signatureKeyId,
  };
}

final class IssuedCredential {
  const IssuedCredential({required this.record, required this.token});

  final CredentialRecord record;
  final String token;
}

final class BootstrapResult {
  const BootstrapResult({
    required this.organization,
    required this.application,
    required this.environment,
    required this.controlCredential,
    required this.deliveryCredential,
  });

  final OrganizationRecord organization;
  final ApplicationRecord application;
  final EnvironmentRecord environment;
  final IssuedCredential controlCredential;
  final IssuedCredential deliveryCredential;
}

final class UpdateCheckRequest {
  const UpdateCheckRequest({
    required this.applicationId,
    required this.environmentId,
    required this.runtimeApplicationId,
    required this.runtimeReleaseId,
    required this.runtimeCompatibilityVersion,
    required this.patchFormatVersion,
    required this.highWaterSequence,
    this.highWaterDigest,
    this.platformId,
    this.installationId,
  });

  final String applicationId;
  final String environmentId;
  final String runtimeApplicationId;
  final String runtimeReleaseId;
  final int runtimeCompatibilityVersion;
  final int patchFormatVersion;
  final int highWaterSequence;
  final String? highWaterDigest;
  final String? platformId;
  final String? installationId;
}

final class UpdateCheckResult {
  const UpdateCheckResult({
    required this.decision,
    required this.runtimeReleaseId,
    this.patch,
    this.artifact,
    this.rollbackControl,
    this.applicationId,
    this.environmentId,
    this.platformId,
  });

  final String decision;
  final String runtimeReleaseId;
  final PatchRecord? patch;
  final ArtifactRecord? artifact;
  final String? rollbackControl;
  final String? applicationId;
  final String? environmentId;
  final String? platformId;

  Map<String, Object?> toJson() => <String, Object?>{
    'decision': decision,
    'runtimeReleaseId': runtimeReleaseId,
    if (rollbackControl != null) 'rollbackControl': rollbackControl,
    if (applicationId != null) 'applicationId': applicationId,
    if (environmentId != null) 'environmentId': environmentId,
    if (platformId != null) 'platformId': platformId,
    if (patch != null)
      'patch': <String, Object?>{
        'runtimePatchId': patch!.runtimePatchId,
        'sequence': patch!.sequence,
        'sha256': patch!.sha256,
        'signatureKeyId': patch!.signatureKeyId,
      },
    if (artifact != null)
      'artifact': <String, Object?>{
        'id': artifact!.id,
        'sha256': artifact!.sha256,
        'sizeBytes': artifact!.sizeBytes,
      },
  };
}

final class CloudRollbackResult {
  const CloudRollbackResult({
    required this.status,
    required this.desiredState,
    required this.organizationId,
    required this.applicationId,
    required this.environmentId,
    required this.runtimeReleaseId,
    required this.revision,
    required this.changed,
  });

  final String status;
  final RuntimeDesiredState desiredState;
  final String organizationId;
  final String applicationId;
  final String environmentId;
  final String runtimeReleaseId;
  final int revision;
  final bool changed;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status,
    'desired_state': desiredState.wireValue,
    'organization_id': organizationId,
    'application_id': applicationId,
    'environment_id': environmentId,
    'runtime_release_id': runtimeReleaseId,
    'revision': revision,
    'changed': changed,
  };

  static CloudRollbackResult fromJson(Map<String, Object?> value) =>
      CloudRollbackResult(
        status: value['status']! as String,
        desiredState: RuntimeDesiredStateWire.parse(value['desired_state']),
        organizationId: value['organization_id']! as String,
        applicationId: value['application_id']! as String,
        environmentId: value['environment_id']! as String,
        runtimeReleaseId: value['runtime_release_id']! as String,
        revision: value['revision']! as int,
        changed: value['changed']! as bool,
      );
}

String encodeTokenScope(Set<String> scopes) =>
    jsonEncode(scopes.toList()..sort());
