import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_patch_format/patch_format.dart';

import 'aggregation.dart';
import 'audit.dart';
import 'auth.dart';
import 'billing.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'observation.dart';
import 'p3e_auto_halt.dart';
import 'p3e_auto_halt_applicability.dart';
import 'p3e_claim.dart';
import 'p3e_evaluation.dart';
import 'p3e_halt.dart';
import 'p3e_persistence.dart';
import 'p3e_schedule.dart';
import 'persistence.dart';
import 'reconciliation.dart';
import 'release_bundle.dart';
import 'rollout.dart';

final class ArtifactPayload {
  const ArtifactPayload({required this.record, required this.bytes});

  final ArtifactRecord record;
  final List<int> bytes;
}

final class _RolloutTransitionOutcome {
  const _RolloutTransitionOutcome({
    required this.snapshot,
    required this.applied,
  });

  final RolloutSnapshot snapshot;
  final bool applied;
}

/// The local product boundary. It owns tenant/resource admission and
/// distribution policy, but it never becomes a runtime trust root.
final class ControlPlaneService {
  ControlPlaneService({
    required this.store,
    Random? random,
    DateTime Function()? clock,
    this.observationPolicy = const ObservationPolicy(),
    this.p3eStore,
    this.humanAuth,
    BillingService? billingService,
  }) : _random = random ?? Random.secure(),
       _clock = clock ?? (() => DateTime.now().toUtc()) {
    observationPolicy.validate();
    billing = billingService ?? BillingService(store);
  }

  final ControlPlaneStore store;
  final Random _random;
  final DateTime Function() _clock;
  final ObservationPolicy observationPolicy;
  final P3ePersistenceStore? p3eStore;
  final HumanAuthService? humanAuth;
  late final BillingService billing;
  Future<void> _writeTail = Future<void>.value();
  final Map<String, List<DateTime>> _observationWindows =
      <String, List<DateTime>>{};

  Future<void> initialize() async {
    await store.initialize();
    await humanAuth?.initialize();
    await p3eStore?.initialize();
  }

  /// Authorizes a control-plane read or mutation through the existing
  /// human-session or opaque-credential boundary. Read-only projections use
  /// this seam so human Auth v1 sessions and legacy service credentials keep
  /// identical tenant and capability checks.
  Future<CredentialRecord> authorizeControlCredential({
    required String token,
    required String requiredScope,
    String? organizationId,
    String? applicationId,
    String? environmentId,
  }) => _authorize(
    token,
    requiredScope,
    kind: CredentialKind.control,
    organizationId: organizationId,
    applicationId: applicationId,
    environmentId: environmentId,
  );

  /// Appends a billing lifecycle event using the same immutable audit-chain
  /// seam as release and rollout mutations. The private Cloud provider adapter
  /// never receives permission to write arbitrary audit records.
  Future<void> auditBilling({
    required CredentialRecord actor,
    required String requestId,
    required String action,
    required String resourceId,
    required Map<String, Object?> metadata,
  }) => _audit(
    requestId: requestId,
    actor: actor,
    action: action,
    resourceType: 'billing',
    resourceId: resourceId,
    metadata: metadata,
  );

  Future<HumanUserRecord> bootstrapOwner({
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String email,
    required String password,
    String profileName = 'demo',
  }) async {
    final auth = humanAuth;
    if (auth == null) {
      throw const ControlPlaneException(
        'AUTH_UNAVAILABLE',
        'Human authentication is not configured',
        statusCode: 503,
      );
    }
    await initialize();
    return auth.bootstrapOwner(
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
      email: email,
      password: password,
      profileName: profileName,
    );
  }

  Future<HumanUserRecord> bootstrapAdmin({
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String email,
    required String password,
    String profileName = 'content-admin',
  }) async {
    final auth = humanAuth;
    if (auth == null) {
      throw const ControlPlaneException(
        'AUTH_UNAVAILABLE',
        'Human authentication is not configured',
        statusCode: 503,
      );
    }
    await initialize();
    return auth.bootstrapAdmin(
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
      email: email,
      password: password,
      profileName: profileName,
    );
  }

  Future<List<ContentRecord>> listContent({
    required String token,
    String? organizationId,
    ContentKind? kind,
    ContentStatus? status,
  }) async {
    final actor = await _authorize(
      token,
      contentAdminScope,
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final records = await _contentRecords();
    final filtered =
        records
            .where(
              (record) =>
                  record.organizationId == actor.organizationId &&
                  (kind == null || record.kind == kind) &&
                  (status == null || record.status == status),
            )
            .toList()
          ..sort((left, right) {
            final updated = right.updatedAt.compareTo(left.updatedAt);
            return updated != 0 ? updated : left.id.compareTo(right.id);
          });
    return List.unmodifiable(filtered);
  }

  Future<ContentRecord> readContent({
    required String token,
    required String contentId,
  }) async {
    final record = await _content(contentId);
    await _authorize(
      token,
      contentAdminScope,
      kind: CredentialKind.control,
      organizationId: record.organizationId,
    );
    return record;
  }

  Future<ContentRecord> readPublishedContent({
    required String slug,
    ContentKind? kind,
    String? organizationId,
  }) async {
    final normalizedSlug = normalizeContentSlug(slug);
    final records = await _contentRecords();
    final matches = records
        .where(
          (record) =>
              record.status == ContentStatus.published &&
              record.slug == normalizedSlug &&
              (kind == null || record.kind == kind) &&
              (organizationId == null ||
                  record.organizationId == organizationId),
        )
        .toList(growable: false);
    if (matches.isEmpty) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    if (matches.length > 1) {
      throw const ControlPlaneException(
        'CONTENT_SLUG_AMBIGUOUS',
        'Published content slug requires an organization scope',
        statusCode: 409,
      );
    }
    return matches.single;
  }

  Future<List<ContentRecord>> listPublishedContent({
    required String organizationId,
    ContentKind? kind,
  }) async {
    final records = await _contentRecords();
    final filtered =
        records
            .where(
              (record) =>
                  record.status == ContentStatus.published &&
                  record.organizationId == organizationId &&
                  (kind == null || record.kind == kind),
            )
            .toList()
          ..sort((left, right) {
            final leftDate = left.publishedAt ?? left.updatedAt;
            final rightDate = right.publishedAt ?? right.updatedAt;
            final published = rightDate.compareTo(leftDate);
            return published != 0 ? published : left.slug.compareTo(right.slug);
          });
    return List.unmodifiable(filtered);
  }

  Future<ContentRecord> createContent({
    required String token,
    required ContentWrite draft,
    String? organizationId,
    String? requestId,
  }) => _serialized(() async {
    final actor = await _authorize(
      token,
      contentAdminScope,
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final kind = draft.kind ?? ContentKind.blog;
    final slug = _writeSlug(draft.slug, draft.title);
    await _ensureContentSlugAvailable(
      organizationId: actor.organizationId,
      kind: kind,
      slug: slug,
    );
    final now = _now();
    final record = ContentRecord(
      id: contentRecordId(
        organizationId: actor.organizationId,
        kind: kind,
        slug: slug,
      ),
      organizationId: actor.organizationId,
      kind: kind,
      slug: slug,
      status: ContentStatus.draft,
      title: draft.title,
      excerpt: draft.excerpt,
      body: draft.body,
      tags: draft.tags ?? const <String>{},
      author:
          draft.author?.copyWith(id: actor.id) ??
          ContentAuthorMetadata(id: actor.id, name: actor.id),
      hero: draft.hero ?? ContentHeroMetadata(),
      seo: draft.seo ?? ContentSeoMetadata(),
      createdAt: now,
      updatedAt: now,
      publishedAt: null,
      archivedAt: null,
    );
    try {
      await store.createJson(contentCollection, record.id, record.toJson());
    } on StorageConflict {
      throw const ControlPlaneException(
        'CONTENT_SLUG_CONFLICT',
        'A content entry with this kind and slug already exists',
        statusCode: 409,
      );
    }
    await _audit(
      requestId: requestId ?? _id('req'),
      actor: actor,
      action: 'content.create',
      resourceType: 'content',
      resourceId: record.id,
      metadata: <String, Object?>{
        'kind': record.kind.name,
        'slug': record.slug,
      },
    );
    return record;
  });

  Future<ContentRecord> updateContent({
    required String token,
    required String contentId,
    required ContentWrite draft,
    String? requestId,
  }) => _serialized(() async {
    final current = await _content(contentId);
    final actor = await _authorize(
      token,
      contentAdminScope,
      kind: CredentialKind.control,
      organizationId: current.organizationId,
    );
    if (draft.kind != null && draft.kind != current.kind) {
      throw const ControlPlaneException(
        'CONTENT_KIND_IMMUTABLE',
        'Content kind cannot be changed after creation',
        statusCode: 409,
      );
    }
    final slug = draft.slug.trim().isEmpty
        ? current.slug
        : normalizeContentSlug(draft.slug);
    await _ensureContentSlugAvailable(
      organizationId: current.organizationId,
      kind: current.kind,
      slug: slug,
      excludingId: current.id,
    );
    final record = ContentRecord(
      id: current.id,
      organizationId: current.organizationId,
      kind: current.kind,
      slug: slug,
      status: current.status,
      title: draft.title,
      excerpt: draft.excerpt,
      body: draft.body,
      tags: draft.tags ?? current.tags,
      author: draft.author?.copyWith(id: actor.id) ?? current.author,
      hero: draft.hero ?? current.hero,
      seo: draft.seo ?? current.seo,
      createdAt: current.createdAt,
      updatedAt: _now(),
      publishedAt: current.publishedAt,
      archivedAt: current.archivedAt,
    );
    await store.replaceJson(contentCollection, record.id, record.toJson());
    await _audit(
      requestId: requestId ?? _id('req'),
      actor: actor,
      action: 'content.update',
      resourceType: 'content',
      resourceId: record.id,
      metadata: <String, Object?>{
        'kind': record.kind.name,
        'slug': record.slug,
        'status': record.status.name,
      },
    );
    return record;
  });

  Future<ContentRecord> publishContent({
    required String token,
    required String contentId,
    String? requestId,
  }) => _serialized(() async {
    final current = await _content(contentId);
    final actor = await _authorize(
      token,
      contentAdminScope,
      kind: CredentialKind.control,
      organizationId: current.organizationId,
    );
    if (current.status == ContentStatus.archived) {
      throw const ControlPlaneException(
        'CONTENT_STATE_INVALID',
        'Archived content cannot be published',
        statusCode: 409,
      );
    }
    if (current.status == ContentStatus.published) return current;
    final now = _now();
    final record = ContentRecord(
      id: current.id,
      organizationId: current.organizationId,
      kind: current.kind,
      slug: current.slug,
      status: ContentStatus.published,
      title: current.title,
      excerpt: current.excerpt,
      body: current.body,
      tags: current.tags,
      author: current.author,
      hero: current.hero,
      seo: current.seo,
      createdAt: current.createdAt,
      updatedAt: now,
      publishedAt: current.publishedAt ?? now,
      archivedAt: null,
    );
    await store.replaceJson(contentCollection, record.id, record.toJson());
    await _audit(
      requestId: requestId ?? _id('req'),
      actor: actor,
      action: 'content.publish',
      resourceType: 'content',
      resourceId: record.id,
      metadata: <String, Object?>{
        'kind': record.kind.name,
        'slug': record.slug,
      },
    );
    return record;
  });

  Future<ContentRecord> archiveContent({
    required String token,
    required String contentId,
    String? requestId,
  }) => _serialized(() async {
    final current = await _content(contentId);
    final actor = await _authorize(
      token,
      contentAdminScope,
      kind: CredentialKind.control,
      organizationId: current.organizationId,
    );
    if (current.status == ContentStatus.archived) return current;
    final now = _now();
    final record = ContentRecord(
      id: current.id,
      organizationId: current.organizationId,
      kind: current.kind,
      slug: current.slug,
      status: ContentStatus.archived,
      title: current.title,
      excerpt: current.excerpt,
      body: current.body,
      tags: current.tags,
      author: current.author,
      hero: current.hero,
      seo: current.seo,
      createdAt: current.createdAt,
      updatedAt: now,
      publishedAt: current.publishedAt,
      archivedAt: now,
    );
    await store.replaceJson(contentCollection, record.id, record.toJson());
    await _audit(
      requestId: requestId ?? _id('req'),
      actor: actor,
      action: 'content.archive',
      resourceType: 'content',
      resourceId: record.id,
      metadata: <String, Object?>{
        'kind': record.kind.name,
        'slug': record.slug,
      },
    );
    return record;
  });

  /// Cheap dependency check used by `/readyz`. It never changes runtime
  /// authority: an unavailable control plane only makes delivery unavailable.
  Future<bool> checkReadiness() async {
    try {
      await store.checkReadiness();
      await p3eStore?.listAggregates('__readiness_probe__');
      return true;
    } on Object {
      return false;
    }
  }

  Future<BootstrapResult> bootstrap({
    required String organizationName,
    required String runtimeApplicationId,
    required String platformId,
    required String environmentName,
  }) => _serialized(() async {
    await initialize();
    final now = _now();
    final organization = OrganizationRecord(
      id: _id('org'),
      name: organizationName,
      createdAt: now,
    );
    final application = ApplicationRecord(
      id: _id('app'),
      organizationId: organization.id,
      runtimeApplicationId: runtimeApplicationId,
      createdAt: now,
    );
    final environment = EnvironmentRecord(
      id: _id('env'),
      organizationId: organization.id,
      applicationId: application.id,
      name: environmentName,
      version: 0,
      promotedReleaseId: null,
      createdAt: now,
    );
    final credentialService = CredentialService(random: _random);
    final control = credentialService.issue(
      id: _id('cred'),
      organizationId: organization.id,
      kind: CredentialKind.control,
      scopes: controlScopes,
    );
    final delivery = credentialService.issue(
      id: _id('cred'),
      organizationId: organization.id,
      kind: CredentialKind.delivery,
      scopes: deliveryScopes,
      applicationId: application.id,
      environmentId: environment.id,
    );
    await store.createJson(
      'organizations',
      organization.id,
      organization.toJson(),
    );
    await store.createJson(
      'applications',
      application.id,
      application.toJson(),
    );
    await store.createJson(
      'environments',
      environment.id,
      environment.toJson(),
    );
    await store.createJson(
      'credentials',
      control.record.tokenHash,
      control.record.toJson(),
    );
    await store.createJson(
      'credentials',
      delivery.record.tokenHash,
      delivery.record.toJson(),
    );
    return BootstrapResult(
      organization: organization,
      application: application,
      environment: environment,
      controlCredential: control,
      deliveryCredential: delivery,
    );
  });

  /// Issues one short-lived or non-expiring credential and returns its secret
  /// exactly once to the caller. The service persists only the token hash.
  /// Customer operators rotate by issuing a replacement and then revoking the
  /// old credential; the control plane never becomes signing authority.
  Future<IssuedCredential> issueCredential({
    required String token,
    required String organizationId,
    required CredentialKind kind,
    required Set<String> scopes,
    String? applicationId,
    String? environmentId,
    DateTime? expiresAt,
    String? requestId,
  }) => _serialized(() async {
    final actor = await _authorize(
      token,
      'credential:issue',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    if (expiresAt != null && !expiresAt.isAfter(_now())) {
      throw const ControlPlaneException(
        'INVALID_CREDENTIAL_EXPIRY',
        'Credential expiry must be in the future',
      );
    }
    if (kind == CredentialKind.control &&
        (applicationId != null || environmentId != null)) {
      throw const ControlPlaneException(
        'INVALID_CREDENTIAL_SCOPE',
        'Control credentials cannot be application scoped',
      );
    }
    if (kind == CredentialKind.delivery ||
        kind == CredentialKind.observation ||
        kind == CredentialKind.scheduler ||
        kind == CredentialKind.autoHalt) {
      if (applicationId == null || environmentId == null) {
        throw const ControlPlaneException(
          'INVALID_CREDENTIAL_SCOPE',
          'Application-scoped credentials require application and environment',
        );
      }
      final application = await _application(applicationId);
      _requireTenant(application.organizationId, actor.organizationId);
      final environment = await _environment(environmentId);
      _requireTenant(environment.organizationId, actor.organizationId);
      if (environment.applicationId != application.id) {
        throw const ControlPlaneException(
          'NOT_FOUND',
          'Resource was not found',
          statusCode: 404,
        );
      }
    }
    if (kind == CredentialKind.observation) {
      if (scopes.length != observationScopes.length ||
          scopes.difference(observationScopes).isNotEmpty) {
        throw const ControlPlaneException(
          'INVALID_SCOPE',
          'Observation credentials may only write observations',
        );
      }
      final maximum = _now().add(maxObservationTokenLifetime);
      if (expiresAt == null || expiresAt.isAfter(maximum)) {
        throw const ControlPlaneException(
          'INVALID_CREDENTIAL_EXPIRY',
          'Observation credentials must be short lived',
        );
      }
    }
    final issued = CredentialService(random: _random).issue(
      id: _id('cred'),
      organizationId: actor.organizationId,
      kind: kind,
      scopes: scopes,
      applicationId: applicationId,
      environmentId: environmentId,
      expiresAt: expiresAt,
    );
    await store.createJson(
      'credentials',
      issued.record.tokenHash,
      issued.record.toJson(),
    );
    await _audit(
      requestId: requestId ?? _id('req'),
      actor: actor,
      action: switch (kind) {
        CredentialKind.observation => 'observation.token_issued',
        CredentialKind.scheduler => 'scheduler.credential_issued',
        CredentialKind.autoHalt => 'health.auto_halt_principal_issued',
        _ => 'credential.issue',
      },
      resourceType: 'credential',
      resourceId: issued.record.id,
      metadata: <String, Object?>{
        'kind': issued.record.kind.name,
        'applicationId': issued.record.applicationId,
        'environmentId': issued.record.environmentId,
        'expiresAt': issued.record.expiresAt?.toUtc().toIso8601String(),
      },
    );
    return issued;
  });

  Future<IssuedCredential> issueObservationToken({
    required String token,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    Duration? lifetime,
    String? requestId,
  }) {
    final actualLifetime = lifetime ?? observationPolicy.tokenLifetime;
    if (actualLifetime <= Duration.zero ||
        actualLifetime > observationPolicy.tokenLifetime ||
        actualLifetime > maxObservationTokenLifetime) {
      throw const ControlPlaneException(
        'INVALID_CREDENTIAL_EXPIRY',
        'Observation token lifetime is outside the supported bound',
      );
    }
    return issueCredential(
      token: token,
      organizationId: organizationId,
      kind: CredentialKind.observation,
      scopes: observationScopes,
      applicationId: applicationId,
      environmentId: environmentId,
      expiresAt: _now().add(actualLifetime),
      requestId: requestId,
    );
  }

  Future<ReleaseRecord> registerRelease({
    required String token,
    required ReleaseSpec spec,
    required String idempotencyKey,
    String? organizationId,
    String? requestId,
  }) => _serialized(() async {
    final actor = await _authorize(
      token,
      'release:write',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final request = requestId ?? _id('req');
    final body = spec.toJson();
    final existing = await _existingIdempotency(
      'release',
      idempotencyKey,
      body,
    );
    if (existing != null) {
      final releaseId = existing['releaseId']! as String;
      final release = await _release(releaseId);
      _requireTenant(release.organizationId, actor.organizationId);
      return release;
    }
    final application = await _application(spec.applicationId);
    _requireTenant(application.organizationId, actor.organizationId);
    if (application.runtimeApplicationId != spec.runtimeApplicationId) {
      throw const ControlPlaneException(
        'EXACT_APPLICATION_MISMATCH',
        'Runtime application identity does not match the application record',
        statusCode: 409,
      );
    }
    _validateReleaseSpec(spec);
    final releases = await store.listJson('releases');
    if (releases.any(
      (value) =>
          value['organizationId'] == actor.organizationId &&
          value['applicationId'] == spec.applicationId &&
          value['runtimeReleaseId'] == spec.runtimeReleaseId,
    )) {
      throw const ControlPlaneException(
        'RELEASE_ID_CONFLICT',
        'The runtime release identity is already registered',
        statusCode: 409,
      );
    }
    final release = ReleaseRecord(
      id: _id('rel'),
      organizationId: actor.organizationId,
      applicationId: spec.applicationId,
      platformId: spec.platformId,
      runtimeApplicationId: spec.runtimeApplicationId,
      runtimeReleaseId: spec.runtimeReleaseId,
      buildTarget: spec.buildTarget,
      runtimeCompatibilityVersion: spec.runtimeCompatibilityVersion,
      patchFormatVersion: spec.patchFormatVersion,
      buildFingerprint: requireSha256Digest(spec.buildFingerprint),
      capabilityAuthorityDigest: requireSha256Digest(
        spec.capabilityAuthorityDigest,
      ),
      functionSignatureDigest: requireSha256Digest(
        spec.functionSignatureDigest,
      ),
      displayVersion: requireNonEmpty(spec.displayVersion, 'display version'),
      signingPublicKeys: spec.signingPublicKeys,
      createdAt: _now(),
    );
    await store.createJson('releases', release.id, release.toJson());
    await _saveIdempotency('release', idempotencyKey, body, <String, Object?>{
      'releaseId': release.id,
    });
    await _audit(
      requestId: request,
      actor: actor,
      action: 'release.register',
      resourceType: 'release',
      resourceId: release.id,
      metadata: <String, Object?>{'applicationId': release.applicationId},
    );
    return release;
  });

  Future<PatchRecord> registerPatch({
    required String token,
    required String releaseId,
    required PatchSpec spec,
    required String idempotencyKey,
    String? organizationId,
    String? requestId,
  }) => _serialized(() async {
    final actor = await _authorize(
      token,
      'patch:write',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final request = requestId ?? _id('req');
    final release = await _release(releaseId);
    _requireTenant(release.organizationId, actor.organizationId);
    final body = <String, Object?>{'releaseId': releaseId, ...spec.toJson()};
    final existing = await _existingIdempotency('patch', idempotencyKey, body);
    if (existing != null) return _patch(existing['patchId']! as String);
    _validatePatchSpec(spec);
    if (!release.signingPublicKeys.containsKey(spec.signatureKeyId)) {
      throw const ControlPlaneException(
        'UNKNOWN_SIGNING_KEY',
        'Patch signing key is not registered on the exact release',
        statusCode: 409,
      );
    }
    final patches = await store.listJson('patches');
    for (final value in patches) {
      if (value['organizationId'] != actor.organizationId ||
          value['releaseId'] != release.id) {
        continue;
      }
      if (value['sequence'] == spec.sequence) {
        if (value['sha256'] == requireSha256Digest(spec.sha256)) {
          throw const ControlPlaneException(
            'PATCH_IDEMPOTENCY_REQUIRED',
            'This sequence is already registered; retry with the original idempotency key',
            statusCode: 409,
          );
        }
        throw const ControlPlaneException(
          'SEQUENCE_EQUIVOCATION',
          'The sequence is already bound to a different digest',
          statusCode: 409,
        );
      }
      if (value['runtimePatchId'] == spec.runtimePatchId) {
        throw const ControlPlaneException(
          'PATCH_ID_CONFLICT',
          'The runtime patch identity is already registered',
          statusCode: 409,
        );
      }
    }
    final patch = PatchRecord(
      id: _id('pat'),
      organizationId: actor.organizationId,
      releaseId: release.id,
      runtimePatchId: spec.runtimePatchId,
      sequence: spec.sequence,
      artifactId: spec.artifactId,
      sha256: spec.sha256,
      sizeBytes: spec.sizeBytes,
      signatureKeyId: spec.signatureKeyId,
      state: 'REGISTERED',
      createdAt: _now(),
    );
    final artifact = ArtifactRecord(
      id: spec.artifactId,
      organizationId: actor.organizationId,
      patchId: patch.id,
      sha256: spec.sha256,
      sizeBytes: spec.sizeBytes,
      contentType: 'application/octet-stream',
      state: 'UPLOADING',
      createdAt: _now(),
    );
    await store.createJson('patches', patch.id, patch.toJson());
    await store.createJson('artifacts', artifact.id, artifact.toJson());
    await _saveIdempotency('patch', idempotencyKey, body, <String, Object?>{
      'patchId': patch.id,
    });
    await _audit(
      requestId: request,
      actor: actor,
      action: 'patch.register',
      resourceType: 'patch',
      resourceId: patch.id,
      metadata: <String, Object?>{
        'releaseId': patch.releaseId,
        'sequence': patch.sequence,
        'sha256': patch.sha256,
      },
    );
    return patch;
  });

  Future<ArtifactRecord> uploadArtifact({
    required String token,
    required String artifactId,
    required List<int> bytes,
    required String idempotencyKey,
    String? organizationId,
    String? requestId,
  }) => _serialized(() async {
    final artifact = await _artifact(artifactId);
    final patch = await _patch(artifact.patchId);
    final actor = await _authorize(
      token,
      'artifact:write',
      kind: CredentialKind.control,
      organizationId: organizationId ?? artifact.organizationId,
    );
    final request = requestId ?? _id('req');
    final body = <String, Object?>{
      'artifactId': artifactId,
      'sha256': artifact.sha256,
      'sizeBytes': bytes.length,
    };
    final existing = await _existingIdempotency(
      'artifact',
      idempotencyKey,
      body,
    );
    if (existing != null) return _artifact(existing['artifactId']! as String);
    if (bytes.length != artifact.sizeBytes) {
      throw const ControlPlaneException(
        'ARTIFACT_SIZE_MISMATCH',
        'Artifact byte length does not match the registered size',
        statusCode: 409,
      );
    }
    final actualDigest = sha256Digest(bytes);
    if (actualDigest != artifact.sha256) {
      throw ControlPlaneException(
        'ARTIFACT_DIGEST_MISMATCH',
        'Artifact bytes do not match the registered digest',
        statusCode: 409,
        details: <String, Object?>{
          'expected': artifact.sha256,
          'actual': actualDigest,
        },
      );
    }
    final release = await _release(patch.releaseId);
    try {
      final decoded = PatchFormatV1.decode(bytes);
      if (decoded.applicationId != release.runtimeApplicationId ||
          decoded.releaseId != release.runtimeReleaseId ||
          decoded.patchId != patch.runtimePatchId ||
          decoded.sequence != patch.sequence ||
          decoded.runtimeCompatibilityVersion !=
              release.runtimeCompatibilityVersion ||
          decoded.signatureMetadata.keyId != patch.signatureKeyId) {
        throw const ControlPlaneException(
          'PATCH_EXACT_RELEASE_MISMATCH',
          'Patch bytes do not match the registered release and patch identity',
          statusCode: 409,
        );
      }
      final encoded = PatchFormatV1.encode(decoded);
      if (!_sameBytes(encoded, bytes)) {
        throw const ControlPlaneException(
          'PATCH_NON_CANONICAL',
          'Patch bytes are not the canonical Patch Format v1 encoding',
          statusCode: 415,
        );
      }
      final publicKey = base64.decode(
        release.signingPublicKeys[patch.signatureKeyId]!,
      );
      final verified = await DartEd25519().verify(
        PatchFormatV1.signingBytes(decoded),
        signature: Signature(
          decoded.signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
      if (!verified) {
        throw const ControlPlaneException(
          'INVALID_SIGNATURE',
          'Patch signature verification failed',
          statusCode: 409,
        );
      }
      await store.putArtifact(artifact.sha256, bytes);
      final readyArtifact = artifact.copyWith(state: 'READY');
      final readyPatch = patch.copyWith(state: 'READY');
      await store.replaceJson('artifacts', artifact.id, readyArtifact.toJson());
      await store.replaceJson('patches', patch.id, readyPatch.toJson());
      await _saveIdempotency(
        'artifact',
        idempotencyKey,
        body,
        <String, Object?>{'artifactId': artifact.id},
      );
      await _audit(
        requestId: request,
        actor: actor,
        action: 'artifact.upload',
        resourceType: 'artifact',
        resourceId: artifact.id,
        metadata: <String, Object?>{
          'sha256': artifact.sha256,
          'sizeBytes': artifact.sizeBytes,
        },
      );
      return readyArtifact;
    } on ControlPlaneException {
      await _markQuarantined(artifact);
      rethrow;
    } on Object catch (error) {
      await _markQuarantined(artifact);
      throw ControlPlaneException(
        'INVALID_ARTIFACT',
        'Patch artifact admission failed: $error',
        statusCode: 415,
      );
    }
  });

  /// Exports one verified artifact payload. The control plane deliberately
  /// returns an unsigned payload; the customer-owned private key stays at the
  /// offline operator boundary and is never accepted by this service.
  Future<ReleaseBundlePayload> exportBundle({
    required String token,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String releaseId,
    required String patchId,
    String? requestId,
  }) => _serialized(() async {
    final actor = await _authorize(
      token,
      'bundle:read',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final application = await _application(applicationId);
    _requireTenant(application.organizationId, actor.organizationId);
    final environment = await _environment(environmentId);
    _requireTenant(environment.organizationId, actor.organizationId);
    if (environment.applicationId != application.id) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final release = await _release(releaseId);
    _requireTenant(release.organizationId, actor.organizationId);
    if (release.applicationId != application.id) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final patch = await _patch(patchId);
    _requireTenant(patch.organizationId, actor.organizationId);
    if (patch.releaseId != release.id || patch.state != 'READY') {
      throw const ControlPlaneException(
        'BUNDLE_SOURCE_NOT_READY',
        'The selected patch is not ready for offline export',
        statusCode: 409,
      );
    }
    final artifact = await _artifact(patch.artifactId);
    if (artifact.organizationId != actor.organizationId ||
        artifact.patchId != patch.id ||
        artifact.state != 'READY') {
      throw const ControlPlaneException(
        'BUNDLE_SOURCE_NOT_READY',
        'The selected artifact is not ready for offline export',
        statusCode: 409,
      );
    }
    final bytes = await store.readArtifact(artifact.sha256);
    if (bytes == null || sha256Digest(bytes) != artifact.sha256) {
      throw const ControlPlaneException(
        'BUNDLE_SOURCE_CORRUPT',
        'The selected artifact failed its content digest check',
        statusCode: 500,
      );
    }
    final payload = ReleaseBundlePayload(
      source: ReleaseBundleSource(
        organizationId: actor.organizationId,
        applicationId: application.id,
        environmentId: environment.id,
        releaseId: release.id,
        patchId: patch.id,
        artifactId: artifact.id,
      ),
      exportedAt: _now(),
      release: release,
      patch: patch,
      artifact: artifact,
      artifactBytes: bytes,
    );
    try {
      await ReleaseBundle.validatePayload(payload);
    } on Object {
      throw const ControlPlaneException(
        'BUNDLE_SOURCE_INVALID',
        'The selected artifact failed Patch Format v1 admission checks',
        statusCode: 500,
      );
    }
    await _audit(
      requestId: requestId ?? _id('req'),
      actor: actor,
      action: 'bundle.export',
      resourceType: 'release-bundle',
      resourceId: release.id,
      metadata: <String, Object?>{
        'patchId': patch.id,
        'artifactId': artifact.id,
        'sha256': artifact.sha256,
        'environmentId': environment.id,
      },
    );
    return payload;
  });

  /// Verifies and stores one signed bundle without making it eligible for
  /// promotion. Destination control-plane identifiers are authenticated
  /// request inputs; source identifiers remain provenance in the import row.
  Future<ReleaseBundleImportResult> importBundle({
    required String token,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required List<int> bytes,
    required String idempotencyKey,
    required String trustedKeyId,
    required List<int> trustedPublicKey,
    String? requestId,
  }) => _serialized(() async {
    final actor = await _authorize(
      token,
      'bundle:write',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final application = await _application(applicationId);
    _requireTenant(application.organizationId, actor.organizationId);
    final environment = await _environment(environmentId);
    _requireTenant(environment.organizationId, actor.organizationId);
    if (environment.applicationId != application.id) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    late final ReleaseBundle bundle;
    try {
      bundle = await ReleaseBundle.verify(
        bytes: bytes,
        expectedKeyId: trustedKeyId,
        expectedPublicKey: trustedPublicKey,
      );
    } on Object {
      throw const ControlPlaneException(
        'BUNDLE_INVALID',
        'Signed release bundle verification failed',
        statusCode: 415,
      );
    }
    final payload = bundle.payload;
    final body = <String, Object?>{
      'organizationId': actor.organizationId,
      'applicationId': application.id,
      'environmentId': environment.id,
      'bundleDigest': bundle.bundleDigest,
    };
    final existingIdempotency = await _existingIdempotency(
      'bundle-import',
      idempotencyKey,
      body,
    );
    String? replayImportId;
    if (existingIdempotency != null) {
      final importId = existingIdempotency['bundleImportId'];
      if (importId is! String) {
        throw const ControlPlaneException(
          'STORAGE_CORRUPT',
          'Bundle import idempotency record is malformed',
          statusCode: 500,
        );
      }
      replayImportId = importId;
    }
    if (application.runtimeApplicationId !=
        payload.release.runtimeApplicationId) {
      throw const ControlPlaneException(
        'BUNDLE_APPLICATION_MISMATCH',
        'Bundle runtime application does not match the destination application',
        statusCode: 409,
      );
    }
    final importId = _bundleImportId(
      organizationId: actor.organizationId,
      applicationId: application.id,
      environmentId: environment.id,
      bundleDigest: bundle.bundleDigest,
    );
    if (replayImportId != null && replayImportId != importId) {
      throw const ControlPlaneException(
        'STORAGE_CORRUPT',
        'Bundle import idempotency record points to a different bundle',
        statusCode: 500,
      );
    }
    final sourceRelease = payload.release;
    final sourcePatch = payload.patch;
    final sourceArtifact = payload.artifact;
    final destinationReleaseId = _bundleRecordId(
      prefix: 'rel',
      organizationId: actor.organizationId,
      applicationId: application.id,
      environmentId: environment.id,
      bundleDigest: bundle.bundleDigest,
    );
    final destinationPatchId = _bundleRecordId(
      prefix: 'pat',
      organizationId: actor.organizationId,
      applicationId: application.id,
      environmentId: environment.id,
      bundleDigest: bundle.bundleDigest,
    );
    final destinationArtifactId = _bundleRecordId(
      prefix: 'art',
      organizationId: actor.organizationId,
      applicationId: application.id,
      environmentId: environment.id,
      bundleDigest: bundle.bundleDigest,
    );
    final existingImport = await store.readJson('bundle_imports', importId);
    final existingState = existingImport == null
        ? null
        : _validateExistingBundleImport(
            existingImport,
            importId: importId,
            organizationId: actor.organizationId,
            applicationId: application.id,
            environmentId: environment.id,
            bundle: bundle,
            releaseId: destinationReleaseId,
            patchId: destinationPatchId,
            artifactId: destinationArtifactId,
          );
    final releases = await store.listJson('releases');
    if (releases.any(
      (value) =>
          value['id'] != destinationReleaseId &&
          value['organizationId'] == actor.organizationId &&
          value['applicationId'] == application.id &&
          value['runtimeReleaseId'] == sourceRelease.runtimeReleaseId,
    )) {
      throw const ControlPlaneException(
        'BUNDLE_RELEASE_CONFLICT',
        'The runtime release identity already exists at the destination',
        statusCode: 409,
      );
    }
    final patches = await store.listJson('patches');
    final destinationReleaseIds =
        releases
            .where(
              (value) =>
                  value['organizationId'] == actor.organizationId &&
                  value['applicationId'] == application.id,
            )
            .map((value) => value['id'])
            .whereType<String>()
            .toSet()
          ..add(destinationReleaseId);
    if (patches.any(
      (value) =>
          value['id'] != destinationPatchId &&
          value['organizationId'] == actor.organizationId &&
          destinationReleaseIds.contains(value['releaseId']) &&
          value['runtimePatchId'] == sourcePatch.runtimePatchId,
    )) {
      throw const ControlPlaneException(
        'BUNDLE_PATCH_CONFLICT',
        'The runtime patch identity already exists at the destination',
        statusCode: 409,
      );
    }
    final destinationState = existingState == 'ADMITTED'
        ? 'READY'
        : 'QUARANTINED';
    final destinationRelease = ReleaseRecord(
      id: destinationReleaseId,
      organizationId: actor.organizationId,
      applicationId: application.id,
      platformId: sourceRelease.platformId,
      runtimeApplicationId: sourceRelease.runtimeApplicationId,
      runtimeReleaseId: sourceRelease.runtimeReleaseId,
      buildTarget: sourceRelease.buildTarget,
      runtimeCompatibilityVersion: sourceRelease.runtimeCompatibilityVersion,
      patchFormatVersion: sourceRelease.patchFormatVersion,
      buildFingerprint: sourceRelease.buildFingerprint,
      capabilityAuthorityDigest: sourceRelease.capabilityAuthorityDigest,
      functionSignatureDigest: sourceRelease.functionSignatureDigest,
      displayVersion: sourceRelease.displayVersion,
      signingPublicKeys: sourceRelease.signingPublicKeys,
      // Release metadata is source-authored and is retained exactly; the
      // authenticated destination IDs are the only ownership substitutions.
      createdAt: sourceRelease.createdAt,
    );
    final destinationPatch = PatchRecord(
      id: destinationPatchId,
      organizationId: actor.organizationId,
      releaseId: destinationRelease.id,
      runtimePatchId: sourcePatch.runtimePatchId,
      sequence: sourcePatch.sequence,
      artifactId: destinationArtifactId,
      sha256: sourcePatch.sha256,
      sizeBytes: sourcePatch.sizeBytes,
      signatureKeyId: sourcePatch.signatureKeyId,
      state: destinationState,
      createdAt: sourcePatch.createdAt,
    );
    final destinationArtifact = ArtifactRecord(
      id: destinationArtifactId,
      organizationId: actor.organizationId,
      patchId: destinationPatch.id,
      sha256: sourceArtifact.sha256,
      sizeBytes: sourceArtifact.sizeBytes,
      contentType: sourceArtifact.contentType,
      state: destinationState,
      createdAt: sourceArtifact.createdAt,
    );
    await store.putArtifact(destinationArtifact.sha256, payload.artifactBytes);
    await _ensureBundleRecord(
      collection: 'releases',
      id: destinationRelease.id,
      value: destinationRelease.toJson(),
    );
    await _ensureBundleRecord(
      collection: 'patches',
      id: destinationPatch.id,
      value: destinationPatch.toJson(),
    );
    await _ensureBundleRecord(
      collection: 'artifacts',
      id: destinationArtifact.id,
      value: destinationArtifact.toJson(),
    );
    if (existingImport == null) {
      await store.createJson('bundle_imports', importId, <String, Object?>{
        'id': importId,
        'organizationId': actor.organizationId,
        'applicationId': application.id,
        'environmentId': environment.id,
        'bundleDigest': bundle.bundleDigest,
        'source': payload.source.toJson(),
        'signedPayload': bundle.signedPayloadMetadata,
        'bundleKeyId': bundle.keyId,
        'bundleSignature': base64Encode(bundle.signature),
        'releaseId': destinationRelease.id,
        'patchId': destinationPatch.id,
        'artifactId': destinationArtifact.id,
        'state': 'QUARANTINED',
        // The exported timestamp is signed source metadata and gives replay
        // recovery a stable provenance timestamp for this import row.
        'createdAt': payload.exportedAt.toIso8601String(),
      });
    }
    if (existingIdempotency == null) {
      await _saveIdempotency(
        'bundle-import',
        idempotencyKey,
        body,
        <String, Object?>{'bundleImportId': importId},
      );
    }
    if (existingImport == null) {
      await _audit(
        requestId: requestId ?? _id('req'),
        actor: actor,
        action: 'bundle.import.quarantined',
        resourceType: 'release-bundle',
        resourceId: importId,
        metadata: <String, Object?>{
          'bundleDigest': bundle.bundleDigest,
          'sourceOrganizationId': payload.source.organizationId,
          'sourceApplicationId': payload.source.applicationId,
          'sourceEnvironmentId': payload.source.environmentId,
          'sourceReleaseId': payload.source.releaseId,
          'sourcePatchId': payload.source.patchId,
          'sourceArtifactId': payload.source.artifactId,
          'releaseId': destinationRelease.id,
          'patchId': destinationPatch.id,
          'artifactId': destinationArtifact.id,
        },
      );
    }
    return _readBundleImport(
      importId,
      idempotentReplay: existingImport != null || existingIdempotency != null,
    );
  });

  /// Revalidates one quarantined import and makes it eligible for the existing
  /// promotion path. Admission never changes environment promotion state.
  Future<ReleaseBundleImportResult> admitBundle({
    required String token,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String releaseId,
    required String patchId,
    required String idempotencyKey,
    required String trustedKeyId,
    required List<int> trustedPublicKey,
    String? requestId,
  }) => _serialized(() async {
    final actor = await _authorize(
      token,
      'bundle:write',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final application = await _application(applicationId);
    _requireTenant(application.organizationId, actor.organizationId);
    final environment = await _environment(environmentId);
    _requireTenant(environment.organizationId, actor.organizationId);
    if (environment.applicationId != application.id) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final body = <String, Object?>{
      'organizationId': actor.organizationId,
      'applicationId': applicationId,
      'environmentId': environmentId,
      'releaseId': releaseId,
      'patchId': patchId,
    };
    final existing = await _existingIdempotency(
      'bundle-admit',
      idempotencyKey,
      body,
    );
    var idempotentReplay = false;
    Map<String, Object?>? importRecord;
    late final String importId;
    if (existing != null) {
      final replayImportId = existing['bundleImportId'];
      if (replayImportId is! String) {
        throw const ControlPlaneException(
          'STORAGE_CORRUPT',
          'Bundle admission idempotency record is malformed',
          statusCode: 500,
        );
      }
      importId = replayImportId;
      importRecord = await store.readJson('bundle_imports', importId);
      if (importRecord == null) {
        throw const ControlPlaneException(
          'STORAGE_CORRUPT',
          'Bundle admission provenance is missing',
          statusCode: 500,
        );
      }
      idempotentReplay = true;
    } else {
      importRecord = await _findBundleImport(
        organizationId: actor.organizationId,
        applicationId: application.id,
        environmentId: environment.id,
        releaseId: releaseId,
        patchId: patchId,
      );
      if (importRecord == null) {
        throw const ControlPlaneException(
          'BUNDLE_NOT_IMPORTED',
          'The release and patch are not a recorded bundle import',
          statusCode: 409,
        );
      }
      importId = _bundleStoredString(importRecord, 'id');
    }
    final current = await _readBundleImport(
      importId,
      idempotentReplay: idempotentReplay,
    );
    if (current.release.id != releaseId ||
        current.patch.id != patchId ||
        current.destinationEnvironmentId != environment.id ||
        current.release.applicationId != application.id ||
        current.release.organizationId != actor.organizationId ||
        current.release.runtimeApplicationId !=
            application.runtimeApplicationId) {
      throw const ControlPlaneException(
        'BUNDLE_APPLICATION_MISMATCH',
        'Imported release does not match the destination application',
        statusCode: 409,
      );
    }
    final bytes = await store.readArtifact(current.artifact.sha256);
    if (bytes == null) {
      throw const ControlPlaneException(
        'BUNDLE_ARTIFACT_MISSING',
        'The quarantined artifact object is missing',
        statusCode: 409,
      );
    }
    try {
      final signedPayload = _bundleStoredObject(importRecord, 'signedPayload');
      await ReleaseBundle.revalidateStoredPayload(
        signedPayloadMetadata: signedPayload,
        bundleDigest: current.bundleDigest,
        bundleKeyId: _bundleStoredString(importRecord, 'bundleKeyId'),
        bundleSignature: _bundleStoredString(importRecord, 'bundleSignature'),
        artifactBytes: bytes,
        expectedKeyId: trustedKeyId,
        expectedPublicKey: trustedPublicKey,
      );
      _validateBundleDestinationMetadata(
        sourcePayload: _bundlePayloadFromStoredMetadata(signedPayload, bytes),
        current: current,
        organizationId: actor.organizationId,
        applicationId: application.id,
      );
      await ReleaseBundle.verifyPatchArtifact(
        release: current.release,
        patch: current.patch,
        artifact: current.artifact,
        bytes: bytes,
      );
    } on Object {
      throw const ControlPlaneException(
        'BUNDLE_ADMISSION_FAILED',
        'Quarantined artifact failed destination admission checks',
        statusCode: 409,
      );
    }
    final patchReady = current.patch.state == 'READY';
    final artifactReady = current.artifact.state == 'READY';
    if (!patchReady && current.patch.state != 'QUARANTINED') {
      throw const ControlPlaneException(
        'BUNDLE_NOT_QUARANTINED',
        'The imported patch is not awaiting explicit admission',
        statusCode: 409,
      );
    }
    if (!artifactReady && current.artifact.state != 'QUARANTINED') {
      throw const ControlPlaneException(
        'BUNDLE_NOT_QUARANTINED',
        'The imported artifact is not awaiting explicit admission',
        statusCode: 409,
      );
    }
    final admittedPatch = current.patch.copyWith(state: 'READY');
    final admittedArtifact = current.artifact.copyWith(state: 'READY');
    var changed = false;
    // Artifact readiness is established before patch readiness. If a process
    // stops between these writes, the next admission can safely finish the
    // patch transition; promotion still requires both records to be READY.
    if (!artifactReady) {
      await store.replaceJson(
        'artifacts',
        admittedArtifact.id,
        admittedArtifact.toJson(),
      );
      changed = true;
    }
    if (!patchReady) {
      await store.replaceJson(
        'patches',
        admittedPatch.id,
        admittedPatch.toJson(),
      );
      changed = true;
    }
    if (_bundleStoredString(importRecord, 'state') != 'ADMITTED') {
      await store.replaceJson('bundle_imports', importId, <String, Object?>{
        ...importRecord,
        'state': 'ADMITTED',
        'admittedAt': _now().toIso8601String(),
      });
      changed = true;
    }
    if (existing == null) {
      await _saveIdempotency(
        'bundle-admit',
        idempotencyKey,
        body,
        <String, Object?>{'bundleImportId': importId},
      );
    }
    if (changed) {
      await _audit(
        requestId: requestId ?? _id('req'),
        actor: actor,
        action: 'bundle.admit',
        resourceType: 'release-bundle',
        resourceId: importId,
        metadata: <String, Object?>{
          'bundleDigest': current.bundleDigest,
          'releaseId': current.release.id,
          'patchId': current.patch.id,
          'artifactId': current.artifact.id,
        },
      );
    }
    return _readBundleImport(importId, idempotentReplay: idempotentReplay);
  });

  Future<EnvironmentRecord> promote({
    required String token,
    required String environmentId,
    required String releaseId,
    required int expectedVersion,
    required String idempotencyKey,
    String? organizationId,
    String? requestId,
  }) => _serialized(() async {
    final environment = await _environment(environmentId);
    final actor = await _authorize(
      token,
      'release:promote',
      kind: CredentialKind.control,
      organizationId: organizationId ?? environment.organizationId,
    );
    final request = requestId ?? _id('req');
    final body = <String, Object?>{
      'environmentId': environmentId,
      'releaseId': releaseId,
      'expectedVersion': expectedVersion,
    };
    final existing = await _existingIdempotency(
      'promotion',
      idempotencyKey,
      body,
    );
    if (existing != null)
      return _environment(existing['environmentId']! as String);
    if (environment.version != expectedVersion) {
      throw ControlPlaneException(
        'PRECONDITION_FAILED',
        'Environment version is stale',
        statusCode: 412,
        details: <String, Object?>{'currentVersion': environment.version},
      );
    }
    final release = await _release(releaseId);
    _requireTenant(release.organizationId, actor.organizationId);
    if (release.applicationId != environment.applicationId) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final patches = await store.listJson('patches');
    final quarantinedBundlePatchIds = (await store.listJson('bundle_imports'))
        .where(
          (value) =>
              value['organizationId'] == actor.organizationId &&
              value['applicationId'] == environment.applicationId &&
              value['environmentId'] == environment.id &&
              value['releaseId'] == release.id &&
              value['state'] == 'QUARANTINED',
        )
        .map((value) => value['patchId'])
        .whereType<String>()
        .toSet();
    var hasVerifiedReadyPatch = false;
    for (final value in patches) {
      if (value['organizationId'] != actor.organizationId ||
          value['releaseId'] != release.id ||
          value['state'] != 'READY' ||
          quarantinedBundlePatchIds.contains(value['id'])) {
        continue;
      }
      try {
        final patch = PatchRecord.fromJson(value);
        if (patch.state != 'READY') continue;
        final artifact = await _artifact(patch.artifactId);
        if (artifact.state != 'READY') continue;
        final bytes = await store.readArtifact(artifact.sha256);
        if (bytes == null) continue;
        await ReleaseBundle.verifyPatchArtifact(
          release: release,
          patch: patch,
          artifact: artifact,
          bytes: bytes,
        );
        hasVerifiedReadyPatch = true;
        break;
      } on StorageUnavailable {
        rethrow;
      } on StorageConflict {
        rethrow;
      } on StorageDigestMismatch {
        rethrow;
      } on ControlPlaneException catch (error) {
        if (error.code != 'NOT_FOUND') rethrow;
      } on FormatException {
        // A malformed candidate cannot make the release promotable. Other
        // valid ready patches may still be considered.
      } on TypeError {
        // A malformed or incomplete candidate cannot make the release
        // promotable. Other valid ready patches may still be considered.
      }
    }
    if (!hasVerifiedReadyPatch) {
      throw const ControlPlaneException(
        'RELEASE_NOT_READY',
        'Release has no matching verified ready patch and artifact',
        statusCode: 409,
      );
    }
    final promoted = EnvironmentRecord(
      id: environment.id,
      organizationId: environment.organizationId,
      applicationId: environment.applicationId,
      name: environment.name,
      version: environment.version + 1,
      promotedReleaseId: release.id,
      createdAt: environment.createdAt,
    );
    await store.replaceJson('environments', environment.id, promoted.toJson());
    await _saveIdempotency('promotion', idempotencyKey, body, <String, Object?>{
      'environmentId': environment.id,
    });
    await _audit(
      requestId: request,
      actor: actor,
      action: 'release.promote',
      resourceType: 'environment',
      resourceId: environment.id,
      metadata: <String, Object?>{
        'releaseId': release.id,
        'version': promoted.version,
      },
    );
    return promoted;
  });

  /// Creates a DRAFT rollout and its immutable revision. The target is
  /// resolved from trusted control-plane records rather than accepting runtime
  /// identity, digest, or artifact metadata from the caller.
  Future<RolloutSnapshot> createRollout({
    required String token,
    required RolloutSpec spec,
    required String idempotencyKey,
    String? organizationId,
    String? requestId,
  }) => _serialized(() async {
    final actor = await _authorize(
      token,
      'rollout:create',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final request = requestId ?? _id('req');
    final body = spec.toJson();
    final existing = await _existingIdempotency(
      'rollout',
      idempotencyKey,
      body,
    );
    if (existing != null) {
      return _rolloutSnapshot(existing['rolloutId']! as String, actor);
    }
    final application = await _application(spec.applicationId);
    _requireTenant(application.organizationId, actor.organizationId);
    final environment = await _environment(spec.environmentId);
    _requireTenant(environment.organizationId, actor.organizationId);
    if (environment.applicationId != application.id) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final release = await _release(spec.releaseId);
    _requireTenant(release.organizationId, actor.organizationId);
    if (release.applicationId != application.id ||
        release.platformId != spec.platformId ||
        environment.promotedReleaseId != release.id) {
      throw const ControlPlaneException(
        'ROLLOUT_TARGET_MISMATCH',
        'Rollout release does not match the application environment',
        statusCode: 409,
      );
    }
    final patch = await _readyPatch(spec.releaseId, spec.patchId);
    final artifact = await _artifact(patch.artifactId);
    if (patch.organizationId != actor.organizationId ||
        artifact.patchId != patch.id ||
        artifact.sha256 != patch.sha256 ||
        artifact.organizationId != actor.organizationId ||
        artifact.state != 'READY') {
      throw const ControlPlaneException(
        'ROLLOUT_TARGET_MISMATCH',
        'Rollout patch or artifact is not ready for this tenant',
        statusCode: 409,
      );
    }
    final target = RolloutTarget(
      organizationId: actor.organizationId,
      applicationId: application.id,
      environmentId: environment.id,
      platformId: release.platformId,
      releaseId: release.id,
      runtimeReleaseId: release.runtimeReleaseId,
      patchId: patch.id,
      runtimePatchId: patch.runtimePatchId,
      artifactId: artifact.id,
      sha256: artifact.sha256,
      sequence: patch.sequence,
    );
    await _rejectOverlappingRollout(target);
    final rollout = RolloutRecord(
      id: _id('rol'),
      organizationId: actor.organizationId,
      currentRevision: 1,
      state: RolloutState.draft,
      createdAt: _now(),
    );
    final revision = RolloutRevision(
      id: _id('rvr'),
      rolloutId: rollout.id,
      organizationId: actor.organizationId,
      revision: 1,
      previousRevision: null,
      state: RolloutState.draft,
      target: target,
      policy: RolloutPolicy(
        cohortKind: spec.cohortKind,
        percentageBasisPoints: spec.percentageBasisPoints,
        salt: _id('salt'),
        internalInstallationHashes: spec.internalInstallationHashes,
      ),
      actorId: actor.id,
      reason: 'created',
      pausedFromState: null,
      createdAt: _now(),
    );
    await store.createJson('rollouts', rollout.id, rollout.toJson());
    await store.createJson('rollout_revisions', revision.id, revision.toJson());
    await _saveIdempotency('rollout', idempotencyKey, body, <String, Object?>{
      'rolloutId': rollout.id,
    });
    await _audit(
      requestId: request,
      actor: actor,
      action: 'rollout.created',
      resourceType: 'rollout',
      resourceId: rollout.id,
      metadata: <String, Object?>{
        'rolloutRevision': revision.revision,
        'state': revision.state.wireName,
        'releaseId': target.releaseId,
        'patchId': target.patchId,
        'artifactDigest': target.sha256,
      },
    );
    return RolloutSnapshot(
      rollout: rollout,
      revision: revision,
      history: <RolloutRevision>[revision],
    );
  });

  Future<RolloutSnapshot> readRollout({
    required String token,
    required String rolloutId,
    required String organizationId,
  }) async {
    final actor = await _authorize(
      token,
      'rollout:read',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final rollout = await _rollout(rolloutId);
    _requireTenant(rollout.organizationId, actor.organizationId);
    return _rolloutSnapshot(rollout.id, actor);
  }

  /// Evaluates one exact immutable P3E-2 aggregate revision under explicit
  /// caller-supplied policy. The result is advisory evidence only: this
  /// method never calls [transitionRollout] and never changes runtime trust.
  Future<ManualEvaluationSnapshot> evaluateHealth({
    required String token,
    required String rolloutId,
    required ManualEvaluationRequest request,
    required String idempotencyKey,
    String? organizationId,
    String? requestId,
  }) => _serialized(() async {
    final actor = await _authorizeHealth(
      token,
      schedulerApplicationId: request.applicationId,
      schedulerEnvironmentId: request.environmentId,
    );
    validateManualEvaluationIdempotencyKey(idempotencyKey);
    if ((organizationId != null && organizationId != actor.organizationId) ||
        request.organizationId != actor.organizationId ||
        request.rolloutId != rolloutId) {
      await _auditHealth(
        actor: actor,
        requestId: requestId,
        action: 'health.evaluation_scope_rejected',
        evaluationId: request.aggregateRevisionId,
        metadata: const <String, Object?>{'code': 'HEALTH_SCOPE_MISMATCH'},
      );
      throw const ControlPlaneException(
        'HEALTH_SCOPE_MISMATCH',
        'Evaluation scope does not match the authorized rollout',
        statusCode: 404,
      );
    }
    final evaluationId = manualEvaluationId(
      organizationId: actor.organizationId,
      rolloutId: rolloutId,
      idempotencyKey: idempotencyKey,
    );
    await _auditHealth(
      actor: actor,
      requestId: requestId,
      action: 'health.evaluation_requested',
      evaluationId: evaluationId,
      metadata: <String, Object?>{
        'rolloutRevision': request.rolloutRevision,
        'aggregateRevisionId': request.aggregateRevisionId,
      },
    );
    final p3e = _requireP3eStore();
    final rollout = await _rollout(rolloutId);
    _requireTenant(rollout.organizationId, actor.organizationId);
    final currentRevision = await _rolloutRevision(
      rolloutId,
      rollout.currentRevision,
    );
    if (currentRevision.revision != request.rolloutRevision ||
        !_sameHealthTarget(currentRevision.target, request)) {
      await _auditHealth(
        actor: actor,
        requestId: requestId,
        action: 'health.evaluation_stale_rejected',
        evaluationId: evaluationId,
        metadata: <String, Object?>{
          'code': 'HEALTH_AGGREGATE_STALE',
          'requestedRolloutRevision': request.rolloutRevision,
          'currentRolloutRevision': currentRevision.revision,
        },
      );
      throw const ControlPlaneException(
        'HEALTH_AGGREGATE_STALE',
        'Evaluation references a stale rollout revision',
        statusCode: 409,
      );
    }

    final aggregate = await p3e.readAggregate(
      actor.organizationId,
      request.aggregateId,
    );
    if (aggregate == null) {
      await _auditHealth(
        actor: actor,
        requestId: requestId,
        action: 'health.evaluation_evidence_rejected',
        evaluationId: evaluationId,
        metadata: const <String, Object?>{'code': 'HEALTH_AGGREGATE_NOT_FOUND'},
      );
      throw const ControlPlaneException(
        'HEALTH_AGGREGATE_NOT_FOUND',
        'Health aggregate was not found',
        statusCode: 404,
      );
    }
    final revision = await p3e.readAggregateRevision(
      actor.organizationId,
      request.aggregateRevisionId,
    );
    if (revision == null) {
      await _auditHealth(
        actor: actor,
        requestId: requestId,
        action: 'health.evaluation_evidence_rejected',
        evaluationId: evaluationId,
        metadata: const <String, Object?>{'code': 'HEALTH_AGGREGATE_NOT_FOUND'},
      );
      throw const ControlPlaneException(
        'HEALTH_AGGREGATE_NOT_FOUND',
        'Health aggregate revision was not found',
        statusCode: 404,
      );
    }
    try {
      await _validateP3eEvidence(p3e, aggregate, revision);
    } on ControlPlaneException catch (error) {
      await _auditHealth(
        actor: actor,
        requestId: requestId,
        action: 'health.evaluation_evidence_rejected',
        evaluationId: evaluationId,
        metadata: <String, Object?>{'code': error.code},
      );
      rethrow;
    }
    final evaluator = const ManualP3eEvaluator();
    final inputDigest = evaluator.evaluationInputDigest(
      aggregate: aggregate,
      revision: revision,
      request: request,
    );
    final existing = await p3e.readEvaluation(
      actor.organizationId,
      evaluationId,
    );
    if (existing != null) {
      if (existing.evaluationInputDigest != inputDigest) {
        await _auditHealth(
          actor: actor,
          requestId: requestId,
          action: 'health.evaluation_conflict',
          evaluationId: evaluationId,
          metadata: const <String, Object?>{
            'code': 'HEALTH_EVALUATION_CONFLICT',
          },
        );
        throw const ControlPlaneException(
          'HEALTH_EVALUATION_CONFLICT',
          'Idempotency key was already used for a different evaluation',
          statusCode: 409,
        );
      }
      await _ensureHealthDecision(
        p3e,
        evaluation: existing,
        actor: actor,
        idempotencyKey: idempotencyKey,
      );
      final replay = await _readHealthSnapshot(
        p3e,
        actor.organizationId,
        rolloutId,
        existing,
      );
      await _auditHealth(
        actor: actor,
        requestId: requestId,
        action: 'health.evaluation_replayed',
        evaluationId: evaluationId,
        metadata: const <String, Object?>{'idempotent': true},
      );
      return ManualEvaluationSnapshot(
        evaluation: replay.evaluation,
        decision: replay.decision,
        idempotentReplay: true,
      );
    }

    late final ManualEvaluationDecision outcome;
    try {
      outcome = evaluator.evaluate(
        aggregate: aggregate,
        revision: revision,
        request: request,
      );
    } on FormatException catch (error) {
      final code = error.message.contains('non-recomputable')
          ? 'HEALTH_EVALUATION_NOT_EVALUABLE'
          : 'HEALTH_SCOPE_MISMATCH';
      await _auditHealth(
        actor: actor,
        requestId: requestId,
        action: 'health.evaluation_evidence_rejected',
        evaluationId: evaluationId,
        metadata: <String, Object?>{'code': code},
      );
      throw ControlPlaneException(
        code,
        'Health evidence cannot be evaluated under the requested policy',
        statusCode: 422,
      );
    }
    final now = _now();
    final evaluation = HealthEvaluation(
      evaluationId: evaluationId,
      organizationId: actor.organizationId,
      aggregateRevisionId: revision.aggregateRevisionId,
      rolloutId: revision.identity.rolloutId,
      rolloutRevision: revision.identity.rolloutRevision,
      evaluationVersion: request.policy.evaluationVersion,
      policyVersion: request.policy.policyVersion,
      thresholdSetVersion: request.policy.thresholdSetVersion,
      windowPolicyVersion: request.policy.windowPolicyVersion,
      privacyPolicyVersion: request.policy.privacyPolicyVersion,
      aggregateInputDigest: revision.inputDigest,
      decision: outcome.decision,
      reasonClass: outcome.reasonClass,
      reasonCodes: outcome.reasonCodes,
      coverageState: outcome.coverageState,
      freshnessState: outcome.freshnessState,
      sampleState: outcome.sampleState,
      createdAt: now,
      auditReference: manualAuditReference(evaluationId),
      evaluationInputDigest: inputDigest,
      targetBindingDigest: _rolloutTargetDigest(currentRevision.target),
    );
    final decision = RolloutDecisionRecord(
      decisionId: manualDecisionId(evaluationId),
      organizationId: actor.organizationId,
      rolloutId: rolloutId,
      expectedRolloutRevision: request.rolloutRevision,
      evaluationId: evaluationId,
      aggregateRevisionId: revision.aggregateRevisionId,
      decision: outcome.decision,
      reason: _healthDecisionReason(outcome.reasonCodes),
      actorIdentity: actor.id,
      idempotencyKey: idempotencyKey,
      createdAt: now,
      previousDecisionId: null,
      resultingTransitionReference: null,
    );
    try {
      await p3e.putEvaluation(evaluation);
    } on StorageConflict {
      final raced = await p3e.readEvaluation(
        actor.organizationId,
        evaluationId,
      );
      if (raced == null || raced.evaluationInputDigest != inputDigest) {
        throw const ControlPlaneException(
          'HEALTH_EVALUATION_CONFLICT',
          'Concurrent evaluation body conflicted with immutable evidence',
          statusCode: 409,
        );
      }
      await _ensureHealthDecision(
        p3e,
        evaluation: raced,
        actor: actor,
        idempotencyKey: idempotencyKey,
      );
      final replay = await _readHealthSnapshot(
        p3e,
        actor.organizationId,
        rolloutId,
        raced,
      );
      await _auditHealth(
        actor: actor,
        requestId: requestId,
        action: 'health.evaluation_replayed',
        evaluationId: evaluationId,
        metadata: const <String, Object?>{
          'idempotent': true,
          'concurrent': true,
        },
      );
      return ManualEvaluationSnapshot(
        evaluation: replay.evaluation,
        decision: replay.decision,
        idempotentReplay: true,
      );
    }
    try {
      await p3e.putDecision(decision);
    } on StorageConflict {
      final raced = await p3e.readDecision(
        actor.organizationId,
        decision.decisionId,
      );
      if (raced == null ||
          raced.canonicalSerialization != decision.canonicalSerialization) {
        throw const ControlPlaneException(
          'HEALTH_EVALUATION_CONFLICT',
          'Concurrent decision evidence conflicted with immutable storage',
          statusCode: 409,
        );
      }
    }
    await _auditHealth(
      actor: actor,
      requestId: requestId,
      action: 'health.evaluation_created',
      evaluationId: evaluationId,
      metadata: <String, Object?>{
        'decision': evaluation.decision,
        'reasonClass': evaluation.reasonClass,
        'rolloutRevision': evaluation.rolloutRevision,
        'aggregateRevisionId': evaluation.aggregateRevisionId,
        'evaluationInputDigest': inputDigest,
      },
    );
    return ManualEvaluationSnapshot(evaluation: evaluation, decision: decision);
  });

  Future<ManualEvaluationSnapshot> readHealthEvaluation({
    required String token,
    required String rolloutId,
    required String evaluationId,
    required String organizationId,
  }) async {
    final actor = await _authorizeHealth(token);
    if (actor.organizationId != organizationId) {
      await _auditHealth(
        actor: actor,
        requestId: null,
        action: 'health.evaluation_scope_rejected',
        evaluationId: evaluationId,
        metadata: const <String, Object?>{'code': 'HEALTH_SCOPE_MISMATCH'},
      );
      throw const ControlPlaneException(
        'HEALTH_EVALUATION_NOT_FOUND',
        'Health evaluation was not found',
        statusCode: 404,
      );
    }
    final evaluation = await _requireP3eStore().readEvaluation(
      actor.organizationId,
      evaluationId,
    );
    if (evaluation == null || evaluation.rolloutId != rolloutId) {
      throw const ControlPlaneException(
        'HEALTH_EVALUATION_NOT_FOUND',
        'Health evaluation was not found',
        statusCode: 404,
      );
    }
    return _readHealthSnapshot(
      _requireP3eStore(),
      actor.organizationId,
      rolloutId,
      evaluation,
    );
  }

  Future<ManualEvaluationPage> listHealthEvaluations({
    required String token,
    required String rolloutId,
    required String organizationId,
    int pageSize = 50,
    String? cursor,
  }) async {
    final actor = await _authorizeHealth(token);
    if (actor.organizationId != organizationId) {
      await _auditHealth(
        actor: actor,
        requestId: null,
        action: 'health.evaluation_scope_rejected',
        evaluationId: rolloutId,
        metadata: const <String, Object?>{'code': 'HEALTH_SCOPE_MISMATCH'},
      );
      throw const ControlPlaneException(
        'HEALTH_EVALUATION_NOT_FOUND',
        'Health evaluations were not found',
        statusCode: 404,
      );
    }
    if (pageSize <= 0 || pageSize > 100) {
      throw const ControlPlaneException(
        'INVALID_PAGE_SIZE',
        'Page size must be between 1 and 100',
      );
    }
    final evaluations =
        (await _requireP3eStore().listEvaluations(actor.organizationId))
            .where((evaluation) => evaluation.rolloutId == rolloutId)
            .toList()
          ..sort((left, right) {
            final timestamp = left.createdAt.compareTo(right.createdAt);
            return timestamp == 0
                ? left.evaluationId.compareTo(right.evaluationId)
                : timestamp;
          });
    final start = _healthCursorIndex(evaluations, cursor);
    final end = (start + pageSize).clamp(0, evaluations.length);
    final selected = evaluations.sublist(start, end);
    final items = <ManualEvaluationSnapshot>[];
    for (final evaluation in selected) {
      items.add(
        await _readHealthSnapshot(
          _requireP3eStore(),
          actor.organizationId,
          rolloutId,
          evaluation,
        ),
      );
    }
    final nextCursor = end < evaluations.length
        ? _healthCursor(evaluations[end - 1])
        : null;
    return ManualEvaluationPage(items: items, nextCursor: nextCursor);
  }

  /// Applies one immutable P3E-3 `HALT_NEW_OFFERS` decision through the
  /// existing P3A rollout CAS. This operation changes only future delivery
  /// eligibility; it never changes runtime trust, high-water, artifacts, or
  /// patch signatures. The method deliberately does not hold [_serialized]
  /// while calling [transitionRollout], whose own CAS path is serialized.
  Future<HealthHaltApplication> applyHealthHalt({
    required String token,
    required String rolloutId,
    required String decisionId,
    required int expectedRolloutRevision,
    required String targetBindingDigest,
    required String evaluationInputDigest,
    required String aggregateInputDigest,
    required String aggregateDigest,
    required String operatorReason,
    required String idempotencyKey,
    String? organizationId,
    String? requestId,
  }) async {
    final actor = await _authorizeHealthHalt(
      token,
      organizationId: organizationId,
    );
    return _applyHealthHaltCore(
      actor: actor,
      rolloutId: rolloutId,
      decisionId: decisionId,
      expectedRolloutRevision: expectedRolloutRevision,
      targetBindingDigest: targetBindingDigest,
      evaluationInputDigest: evaluationInputDigest,
      aggregateInputDigest: aggregateInputDigest,
      aggregateDigest: aggregateDigest,
      operatorReason: operatorReason,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
  }

  Future<HealthHaltApplication> _applyHealthHaltCore({
    required CredentialRecord actor,
    required String rolloutId,
    required String decisionId,
    required int expectedRolloutRevision,
    required String targetBindingDigest,
    required String evaluationInputDigest,
    required String aggregateInputDigest,
    required String aggregateDigest,
    required String operatorReason,
    required String idempotencyKey,
    String? requestId,
  }) async {
    _validateIdempotencyKey(idempotencyKey);
    if (expectedRolloutRevision <= 0) {
      throw const ControlPlaneException(
        'HEALTH_HALT_INVALID_REQUEST',
        'Expected rollout revision must be positive',
      );
    }
    final reason = requireNonEmpty(
      operatorReason,
      'health halt reason',
      maxLength: 512,
    );
    final evaluationDigest = _healthDigest(
      evaluationInputDigest,
      'evaluation input digest',
    );
    final targetDigest = _healthDigest(
      targetBindingDigest,
      'target binding digest',
    );
    final aggregateInput = _healthDigest(
      aggregateInputDigest,
      'aggregate input digest',
    );
    final aggregateContent = _healthDigest(aggregateDigest, 'aggregate digest');
    final body = <String, Object?>{
      'rolloutId': rolloutId,
      'decisionId': decisionId,
      'expectedRolloutRevision': expectedRolloutRevision,
      'targetBindingDigest': targetDigest,
      'evaluationInputDigest': evaluationDigest,
      'aggregateInputDigest': aggregateInput,
      'aggregateDigest': aggregateContent,
      'operatorReason': reason,
    };
    final p3e = _requireP3eStore();

    Map<String, Object?>? existingIdempotency;
    try {
      existingIdempotency = await _existingIdempotency(
        'health-halt-application',
        idempotencyKey,
        body,
      );
    } on ControlPlaneException catch (error) {
      if (error.code == 'IDEMPOTENCY_KEY_REUSED') {
        await _auditHealthHalt(
          actor: actor,
          requestId: requestId,
          action: 'health.halt.conflict',
          resourceId: decisionId,
          metadata: const <String, Object?>{
            'code': 'HEALTH_HALT_IDEMPOTENCY_CONFLICT',
          },
        );
        throw const ControlPlaneException(
          'HEALTH_HALT_CONFLICT',
          'Idempotency key was already used for a different halt request',
          statusCode: 409,
        );
      }
      rethrow;
    }
    if (existingIdempotency != null) {
      final applicationId = existingIdempotency['applicationId'];
      if (applicationId is! String) {
        throw const ControlPlaneException(
          'STORAGE_CORRUPT',
          'Health halt idempotency record is malformed',
          statusCode: 500,
        );
      }
      final replay = await p3e.readHaltApplication(
        actor.organizationId,
        applicationId,
      );
      if (replay == null) {
        throw const ControlPlaneException(
          'STORAGE_CORRUPT',
          'Health halt application evidence is missing',
          statusCode: 500,
        );
      }
      await _auditHealthHalt(
        actor: actor,
        requestId: requestId,
        action: 'health.halt.replayed',
        resourceId: decisionId,
        metadata: <String, Object?>{
          'applicationId': replay.applicationId,
          'result': replay.result,
        },
      );
      return replay;
    }

    final rollout = await _rollout(rolloutId);
    if (rollout.organizationId != actor.organizationId) {
      await _auditHealthHalt(
        actor: actor,
        requestId: requestId,
        action: 'health.halt.cross_tenant',
        resourceId: rolloutId,
        metadata: const <String, Object?>{'code': 'NOT_FOUND'},
      );
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final current = await _rolloutRevision(rolloutId, rollout.currentRevision);
    await _auditHealthHalt(
      actor: actor,
      requestId: requestId,
      action: 'health.halt.requested',
      resourceId: decisionId,
      metadata: <String, Object?>{
        'rolloutId': rolloutId,
        'expectedRolloutRevision': expectedRolloutRevision,
        'currentRolloutRevision': current.revision,
      },
    );

    RolloutDecisionRecord? loadedDecision;
    HealthEvaluation? evaluation;
    HealthAggregateRevision? revision;
    HealthAggregateRecord? aggregate;
    try {
      final decodedDecision = await p3e.readDecision(
        actor.organizationId,
        decisionId,
      );
      loadedDecision = decodedDecision;
      if (decodedDecision != null) {
        evaluation = await p3e.readEvaluation(
          actor.organizationId,
          decodedDecision.evaluationId,
        );
        revision = await p3e.readAggregateRevision(
          actor.organizationId,
          decodedDecision.aggregateRevisionId,
        );
        aggregate = revision == null
            ? null
            : await p3e.readAggregate(
                actor.organizationId,
                revision.aggregateId,
              );
      }
    } on StorageUnavailable {
      rethrow;
    } on Object {
      await _auditHealthHalt(
        actor: actor,
        requestId: requestId,
        action: 'health.halt.evidence_rejected',
        resourceId: decisionId,
        metadata: const <String, Object?>{'code': 'HEALTH_EVIDENCE_INVALID'},
      );
      throw const ControlPlaneException(
        'HEALTH_EVIDENCE_INVALID',
        'Persisted health halt evidence could not be decoded',
        statusCode: 422,
      );
    }
    if (loadedDecision == null) {
      await _auditHealthHalt(
        actor: actor,
        requestId: requestId,
        action: 'health.halt.cross_tenant',
        resourceId: decisionId,
        metadata: const <String, Object?>{'code': 'HEALTH_DECISION_NOT_FOUND'},
      );
      throw const ControlPlaneException(
        'HEALTH_DECISION_NOT_FOUND',
        'Health decision was not found',
        statusCode: 404,
      );
    }
    final decision = loadedDecision;
    if (evaluation == null || revision == null || aggregate == null) {
      await _auditHealthHalt(
        actor: actor,
        requestId: requestId,
        action: 'health.halt.evidence_rejected',
        resourceId: decisionId,
        metadata: const <String, Object?>{'code': 'HEALTH_EVIDENCE_INVALID'},
      );
      throw const ControlPlaneException(
        'HEALTH_EVIDENCE_INVALID',
        'Health halt evidence is incomplete',
        statusCode: 422,
      );
    }
    if (decision.rolloutId != rolloutId ||
        decision.expectedRolloutRevision != expectedRolloutRevision) {
      return _recordHealthHaltOutcome(
        p3e: p3e,
        actor: actor,
        decision: decision,
        evaluation: evaluation,
        revision: revision,
        result: 'STALE',
        reason: 'Decision does not match the requested rollout precondition',
        idempotencyKey: idempotencyKey,
        idempotencyBody: body,
        requestId: requestId,
        error: const ControlPlaneException(
          'HEALTH_DECISION_STALE',
          'Health decision does not match the requested rollout revision',
          statusCode: 409,
        ),
      );
    }
    try {
      await _validateHaltEvidence(
        current: current,
        decision: decision,
        evaluation: evaluation,
        aggregate: aggregate,
        revision: revision,
        expectedRolloutRevision: expectedRolloutRevision,
        targetBindingDigest: targetDigest,
        evaluationInputDigest: evaluationDigest,
        aggregateInputDigest: aggregateInput,
        aggregateDigest: aggregateContent,
        p3e: p3e,
      );
    } on ControlPlaneException catch (error) {
      await _auditHealthHalt(
        actor: actor,
        requestId: requestId,
        action: 'health.halt.evidence_rejected',
        resourceId: decisionId,
        metadata: <String, Object?>{'code': error.code},
      );
      await _recordHaltApplicationBestEffort(
        p3e: p3e,
        actor: actor,
        decision: decision,
        evaluation: evaluation,
        revision: revision,
        result: 'EVIDENCE_REJECTED',
        reason: error.code,
        idempotencyKey: idempotencyKey,
        idempotencyBody: body,
        requestId: requestId,
      );
      rethrow;
    }
    if (decision.decision != 'HALT_NEW_OFFERS') {
      return _recordHealthHaltOutcome(
        p3e: p3e,
        actor: actor,
        decision: decision,
        evaluation: evaluation,
        revision: revision,
        result: 'REJECTED',
        reason: 'Only HALT_NEW_OFFERS may halt a rollout',
        idempotencyKey: idempotencyKey,
        idempotencyBody: body,
        requestId: requestId,
        error: const ControlPlaneException(
          'HEALTH_DECISION_NOT_APPLICABLE',
          'Only HALT_NEW_OFFERS decisions can halt a rollout',
          statusCode: 409,
        ),
      );
    }
    if (current.revision != expectedRolloutRevision) {
      final alreadyApplied =
          (await p3e.listHaltApplications(actor.organizationId)).where(
            (application) =>
                application.decisionId == decision.decisionId &&
                application.applied,
          );
      if (alreadyApplied.isNotEmpty) {
        final applied = alreadyApplied.first;
        return _recordHealthHaltOutcome(
          p3e: p3e,
          actor: actor,
          decision: decision,
          evaluation: evaluation,
          revision: revision,
          result: 'ALREADY_APPLIED',
          reason: 'Health halt decision was already applied',
          idempotencyKey: idempotencyKey,
          idempotencyBody: body,
          previousRolloutRevision: applied.previousRolloutRevision,
          resultingRolloutRevision: applied.resultingRolloutRevision,
          resultingTransitionReference: applied.resultingTransitionReference,
          requestId: requestId,
        );
      }
      final historical = _healthHaltRevision(
        await _rolloutSnapshot(rolloutId, actor),
        expectedRolloutRevision,
        decisionId,
      );
      if (historical != null) {
        return _recordHealthHaltOutcome(
          p3e: p3e,
          actor: actor,
          decision: decision,
          evaluation: evaluation,
          revision: revision,
          result: 'ALREADY_APPLIED',
          reason: 'Health halt transition was already committed',
          idempotencyKey: idempotencyKey,
          idempotencyBody: body,
          previousRolloutRevision: expectedRolloutRevision,
          resultingRolloutRevision: historical.revision,
          resultingTransitionReference: historical.id,
          requestId: requestId,
        );
      }
      return _recordHealthHaltOutcome(
        p3e: p3e,
        actor: actor,
        decision: decision,
        evaluation: evaluation,
        revision: revision,
        result: 'STALE',
        reason: 'Rollout revision changed before health halt application',
        idempotencyKey: idempotencyKey,
        idempotencyBody: body,
        requestId: requestId,
        error: ControlPlaneException(
          'HEALTH_DECISION_STALE',
          'Rollout revision changed before health halt application',
          statusCode: 409,
          details: <String, Object?>{'currentRevision': current.revision},
        ),
      );
    }

    final existingDecisionApplication =
        (await p3e.listHaltApplications(actor.organizationId)).where(
          (application) =>
              application.decisionId == decision.decisionId &&
              application.applied,
        );
    if (existingDecisionApplication.isNotEmpty) {
      final applied = existingDecisionApplication.first;
      return _recordHealthHaltOutcome(
        p3e: p3e,
        actor: actor,
        decision: decision,
        evaluation: evaluation,
        revision: revision,
        result: 'ALREADY_APPLIED',
        reason: 'Health halt decision was already applied',
        idempotencyKey: idempotencyKey,
        idempotencyBody: body,
        previousRolloutRevision: applied.previousRolloutRevision,
        resultingRolloutRevision: applied.resultingRolloutRevision,
        resultingTransitionReference: applied.resultingTransitionReference,
        requestId: requestId,
      );
    }

    final snapshotBeforeTransition = await _rolloutSnapshot(rolloutId, actor);
    final historicalHealthHalt = _healthHaltRevision(
      snapshotBeforeTransition,
      expectedRolloutRevision,
      decisionId,
    );
    if (historicalHealthHalt != null) {
      return _recordHealthHaltOutcome(
        p3e: p3e,
        actor: actor,
        decision: decision,
        evaluation: evaluation,
        revision: revision,
        result: 'ALREADY_APPLIED',
        reason: 'Health halt transition was already committed',
        idempotencyKey: idempotencyKey,
        idempotencyBody: body,
        previousRolloutRevision: expectedRolloutRevision,
        resultingRolloutRevision: historicalHealthHalt.revision,
        resultingTransitionReference: historicalHealthHalt.id,
        requestId: requestId,
      );
    }

    late final _RolloutTransitionOutcome transition;
    try {
      transition = await _transitionRolloutWithStatus(
        token: null,
        authorizedActor: actor,
        rolloutId: rolloutId,
        action: RolloutAction.halt,
        expectedRevision: expectedRolloutRevision,
        reason: 'P3E4 health halt decision $decisionId: $reason',
        idempotencyKey: healthHaltTransitionIdempotencyKey(decisionId),
        organizationId: actor.organizationId,
        requestId: requestId,
      );
    } on ControlPlaneException catch (error) {
      final fresh = await _rolloutSnapshot(rolloutId, actor);
      final recovered = _healthHaltRevision(
        fresh,
        expectedRolloutRevision,
        decisionId,
      );
      if (recovered != null) {
        return _recordHealthHaltOutcome(
          p3e: p3e,
          actor: actor,
          decision: decision,
          evaluation: evaluation,
          revision: revision,
          result: 'ALREADY_APPLIED',
          reason: 'Health halt transition was already committed',
          idempotencyKey: idempotencyKey,
          idempotencyBody: body,
          previousRolloutRevision: expectedRolloutRevision,
          resultingRolloutRevision: recovered.revision,
          resultingTransitionReference: recovered.id,
          requestId: requestId,
        );
      }
      if (error.code == 'PRECONDITION_FAILED') {
        return _recordHealthHaltOutcome(
          p3e: p3e,
          actor: actor,
          decision: decision,
          evaluation: evaluation,
          revision: revision,
          result: 'STALE',
          reason: 'Rollout CAS rejected a stale health halt',
          idempotencyKey: idempotencyKey,
          idempotencyBody: body,
          requestId: requestId,
          error: ControlPlaneException(
            'HEALTH_DECISION_STALE',
            'Rollout revision changed before health halt application',
            statusCode: 409,
            details: error.details,
          ),
        );
      }
      rethrow;
    }
    final committedRevision = _healthHaltRevision(
      transition.snapshot,
      expectedRolloutRevision,
      decisionId,
    );
    if (committedRevision == null) {
      throw const ControlPlaneException(
        'HEALTH_HALT_TRANSITION_UNVERIFIED',
        'Rollout halt transition could not be linked to health evidence',
        statusCode: 500,
      );
    }
    return _recordHealthHaltOutcome(
      p3e: p3e,
      actor: actor,
      decision: decision,
      evaluation: evaluation,
      revision: revision,
      result: transition.applied ? 'APPLIED' : 'ALREADY_APPLIED',
      reason: transition.applied
          ? reason
          : 'Health halt transition was already committed',
      idempotencyKey: idempotencyKey,
      idempotencyBody: body,
      previousRolloutRevision: expectedRolloutRevision,
      resultingRolloutRevision: committedRevision.revision,
      resultingTransitionReference: committedRevision.id,
      requestId: requestId,
    );
  }

  /// Applies automatic-halt evidence through the same P3E-4 validation and
  /// P3A expected-revision CAS as the manual API. The caller must have already
  /// reloaded the current scheduled-work/evidence bindings; this method still
  /// re-authorizes the exact-scope Auto-Halt Principal immediately before the
  /// shared core is entered. It has no scheduler-specific rollout writer.
  Future<HealthHaltApplication> applyAutomaticHealthHalt({
    required String token,
    required P3e5LeaseMutation lease,
    required ScheduledEvaluationWork work,
    required AutomaticHaltIntent intent,
    required P3e5AutomaticHaltCurrentEvidence evidence,
    String? requestId,
  }) async {
    if (!lease.scope.contains(work) ||
        work.status != ScheduledEvaluationWorkStatus.haltApplying ||
        work.automaticHaltIntent?.intentDigest != intent.intentDigest) {
      throw const ControlPlaneException(
        'HEALTH_AUTO_HALT_SECURITY_REJECTED',
        'Automatic-halt work authority is out of scope',
        statusCode: 403,
      );
    }
    final actor = await _authorize(
      token,
      'health:work:apply-halt',
      kind: CredentialKind.autoHalt,
      organizationId: lease.scope.organizationId,
      applicationId: lease.scope.applicationId,
      environmentId: lease.scope.environmentId,
    );
    if (actor.id != intent.authorizedPrincipalId ||
        evidence.principal != null && evidence.principal!.id != actor.id ||
        intent.workId != lease.workId ||
        intent.evaluationId != evidence.evaluation.evaluationId ||
        intent.decisionId != evidence.decision.decisionId ||
        intent.expectedRolloutRevision != evidence.rolloutRevision.revision ||
        intent.targetBindingDigest != evidence.evaluation.targetBindingDigest ||
        intent.automaticHaltPolicyVersion !=
            evidence.policy.automaticHaltPolicyVersion ||
        intent.automaticHaltPolicyDigest != evidence.policy.digest) {
      throw const ControlPlaneException(
        'HEALTH_AUTO_HALT_SECURITY_REJECTED',
        'Automatic-halt authority and evidence are not exactly bound',
        statusCode: 422,
      );
    }
    final idempotencyKey = 'scheduled-halt:${intent.workId}';
    final operatorReason =
        'P3E5 scheduled automatic halt for work ${intent.workId} '
        'decision ${intent.decisionId}';
    final application = await _applyHealthHaltCore(
      actor: actor,
      rolloutId: evidence.decision.rolloutId,
      decisionId: evidence.decision.decisionId,
      expectedRolloutRevision: intent.expectedRolloutRevision,
      targetBindingDigest: intent.targetBindingDigest,
      evaluationInputDigest: evidence.evaluation.evaluationInputDigest!,
      aggregateInputDigest: evidence.aggregateRevision.inputDigest,
      aggregateDigest: evidence.aggregate.aggregateDigest,
      operatorReason: operatorReason,
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    return application;
  }

  /// Applies one explicit state-machine action and writes a new immutable
  /// revision. The current pointer is changed only after the revision exists.
  Future<RolloutSnapshot> transitionRollout({
    required String token,
    required String rolloutId,
    required RolloutAction action,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
    int? percentageBasisPoints,
    String? organizationId,
    String? requestId,
  }) async {
    final outcome = await _transitionRolloutWithStatus(
      token: token,
      rolloutId: rolloutId,
      action: action,
      expectedRevision: expectedRevision,
      reason: reason,
      idempotencyKey: idempotencyKey,
      percentageBasisPoints: percentageBasisPoints,
      organizationId: organizationId,
      requestId: requestId,
    );
    return outcome.snapshot;
  }

  Future<_RolloutTransitionOutcome> _transitionRolloutWithStatus({
    required String? token,
    CredentialRecord? authorizedActor,
    required String rolloutId,
    required RolloutAction action,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
    int? percentageBasisPoints,
    String? organizationId,
    String? requestId,
  }) => _serialized(() async {
    if ((token == null) == (authorizedActor == null)) {
      throw const ControlPlaneException(
        'INVALID_AUTHORITY',
        'Exactly one rollout actor authority is required',
        statusCode: 500,
      );
    }
    final actor =
        authorizedActor ??
        await _authorize(
          token!,
          _rolloutScope(action),
          kind: CredentialKind.control,
          organizationId: organizationId,
        );
    final rollout = await _rollout(rolloutId);
    _requireTenant(rollout.organizationId, actor.organizationId);
    final current = await _rolloutRevision(rollout.id, rollout.currentRevision);
    final body = <String, Object?>{
      'rolloutId': rollout.id,
      'action': action.wireName,
      'expectedRevision': expectedRevision,
      'reason': reason,
      if (percentageBasisPoints != null)
        'percentageBasisPoints': percentageBasisPoints,
    };
    final request = requestId ?? _id('req');
    final existing = await _existingIdempotency(
      'rollout-transition',
      idempotencyKey,
      body,
    );
    if (existing != null) {
      return _RolloutTransitionOutcome(
        snapshot: await _rolloutSnapshot(
          existing['rolloutId']! as String,
          actor,
        ),
        applied: false,
      );
    }
    if (current.revision != expectedRevision) {
      throw ControlPlaneException(
        'PRECONDITION_FAILED',
        'Rollout revision does not match the current revision',
        statusCode: 409,
        details: <String, Object?>{'currentRevision': current.revision},
      );
    }
    final nextState = nextRolloutState(
      current.state,
      action,
      pausedFromState: current.pausedFromState,
    );
    if (nextState == null) {
      throw ControlPlaneException(
        'INVALID_ROLLOUT_TRANSITION',
        'Action ${action.wireName} is not valid from ${current.state.wireName}',
        statusCode: 409,
      );
    }
    final policy = _transitionPolicy(current, action, percentageBasisPoints);
    final revision = RolloutRevision(
      id: _id('rvr'),
      rolloutId: rollout.id,
      organizationId: actor.organizationId,
      revision: current.revision + 1,
      previousRevision: current.revision,
      state: nextState,
      target: current.target,
      policy: policy,
      actorId: actor.id,
      reason: reason,
      pausedFromState: nextState == RolloutState.paused ? current.state : null,
      createdAt: _now(),
    );
    final updated = rollout.copyWith(
      currentRevision: revision.revision,
      state: revision.state,
    );
    final audit = _buildAudit(
      requestId: request,
      actor: actor,
      action: _rolloutAuditAction(action, current.state),
      resourceType: 'rollout',
      resourceId: rollout.id,
      metadata: <String, Object?>{
        'action': action.wireName,
        'fromState': current.state.wireName,
        'toState': revision.state.wireName,
        'rolloutRevision': revision.revision,
        'percentageBasisPoints': revision.policy.percentageBasisPoints,
      },
    );
    try {
      final committed = await store.commitRolloutTransition(
        rolloutId: rollout.id,
        expectedRevision: expectedRevision,
        rollout: updated.toJson(),
        revision: revision.toJson(),
        audit: audit.toJson(),
        idempotencyScope: 'rollout-transition',
        idempotencyKey: idempotencyKey,
        requestDigest: sha256Digest(utf8.encode(canonicalJson(body))),
        idempotencyResult: <String, Object?>{'rolloutId': rollout.id},
      );
      if (!committed.applied) {
        return _RolloutTransitionOutcome(
          snapshot: await _rolloutSnapshot(rollout.id, actor),
          applied: false,
        );
      }
    } on StoragePreconditionFailed catch (error) {
      throw ControlPlaneException(
        'PRECONDITION_FAILED',
        error.message,
        statusCode: 409,
        details: <String, Object?>{'currentRevision': error.currentRevision},
      );
    } on StorageIdempotencyConflict {
      throw const ControlPlaneException(
        'IDEMPOTENCY_KEY_REUSED',
        'Idempotency key was already used for a different request',
        statusCode: 409,
      );
    }
    return _RolloutTransitionOutcome(
      snapshot: await _rolloutSnapshot(rollout.id, actor),
      applied: true,
    );
  });

  Future<UpdateCheckResult> updateCheck({
    required String token,
    required UpdateCheckRequest request,
  }) async {
    final actor = await _authorize(
      token,
      'runtime:update:read',
      kind: CredentialKind.delivery,
      applicationId: request.applicationId,
      environmentId: request.environmentId,
    );
    final environment = await _environment(request.environmentId);
    _requireTenant(environment.organizationId, actor.organizationId);
    final application = await _application(request.applicationId);
    if (application.runtimeApplicationId != request.runtimeApplicationId ||
        request.highWaterSequence < 0) {
      return UpdateCheckResult(
        decision: 'STORE_RELEASE_REQUIRED',
        runtimeReleaseId: request.runtimeReleaseId,
      );
    }
    if (request.patchFormatVersion != 1) {
      return UpdateCheckResult(
        decision: 'STORE_RELEASE_REQUIRED',
        runtimeReleaseId: request.runtimeReleaseId,
      );
    }
    final releaseId = environment.promotedReleaseId;
    if (releaseId == null) {
      return UpdateCheckResult(
        decision: 'NO_UPDATE',
        runtimeReleaseId: request.runtimeReleaseId,
      );
    }
    final release = await _release(releaseId);
    if (release.runtimeApplicationId != request.runtimeApplicationId ||
        release.runtimeReleaseId != request.runtimeReleaseId ||
        release.runtimeCompatibilityVersion !=
            request.runtimeCompatibilityVersion) {
      return UpdateCheckResult(
        decision: 'STORE_RELEASE_REQUIRED',
        runtimeReleaseId: request.runtimeReleaseId,
      );
    }
    final rollout = await _rolloutForUpdate(
      organizationId: actor.organizationId,
      applicationId: application.id,
      environmentId: environment.id,
      release: release,
    );
    if (rollout != null) {
      final installationId = request.installationId;
      final eligible = installationId == null || installationId.isEmpty
          ? false
          : _rolloutEligible(rollout.revision, installationId);
      if (!eligible) {
        return UpdateCheckResult(
          decision: 'NO_UPDATE',
          runtimeReleaseId: release.runtimeReleaseId,
        );
      }
    }
    final candidates = <PatchRecord>[];
    for (final value in await store.listJson('patches')) {
      final patch = PatchRecord.fromJson(value);
      if (patch.organizationId == actor.organizationId &&
          patch.releaseId == release.id &&
          patch.state == 'READY' &&
          patch.sequence > request.highWaterSequence &&
          (rollout == null || patch.id == rollout.revision.target.patchId)) {
        final artifact = await _artifact(patch.artifactId);
        if (artifact.state == 'READY') candidates.add(patch);
      }
    }
    if (candidates.isEmpty) {
      return UpdateCheckResult(
        decision: 'NO_UPDATE',
        runtimeReleaseId: release.runtimeReleaseId,
      );
    }
    candidates.sort((left, right) => left.sequence.compareTo(right.sequence));
    final patch = candidates.first;
    final artifact = await _artifact(patch.artifactId);
    return UpdateCheckResult(
      decision: 'PATCH_AVAILABLE',
      runtimeReleaseId: release.runtimeReleaseId,
      patch: patch,
      artifact: artifact,
    );
  }

  Future<ArtifactPayload> fetchArtifact({
    required String token,
    required String artifactId,
    required String applicationId,
    required String environmentId,
  }) async {
    final artifact = await _artifact(artifactId);
    final patch = await _patch(artifact.patchId);
    final actor = await _authorize(
      token,
      'runtime:artifact:read',
      kind: CredentialKind.delivery,
      applicationId: applicationId,
      environmentId: environmentId,
    );
    _requireTenant(artifact.organizationId, actor.organizationId);
    final environment = await _environment(environmentId);
    final release = await _release(patch.releaseId);
    if (environment.promotedReleaseId != release.id ||
        environment.applicationId != applicationId ||
        release.applicationId != applicationId ||
        artifact.state != 'READY') {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final bytes = await store.readArtifact(artifact.sha256);
    if (bytes == null || sha256Digest(bytes) != artifact.sha256) {
      throw const ControlPlaneException(
        'ARTIFACT_CORRUPT',
        'Stored artifact failed its content digest check',
        statusCode: 500,
      );
    }
    return ArtifactPayload(record: artifact, bytes: List.unmodifiable(bytes));
  }

  /// Validates and durably records one bounded client observation. This path
  /// is deliberately independent of update eligibility and runtime trust: a
  /// failed or unavailable observation write can never block a patch, rollback,
  /// high-water update, startup, or AOT fallback.
  Future<ObservationIngestResult> ingestObservation({
    required String token,
    required ObservationEvent event,
    String? requestId,
  }) => _serialized(() async {
    late final CredentialRecord actor;
    try {
      actor = await _authorize(
        token,
        observationWriteScope,
        kind: CredentialKind.observation,
        organizationId: event.organizationId,
        applicationId: event.applicationId,
        environmentId: event.environmentId,
      );
    } on ControlPlaneException catch (error) {
      if (error.code == 'NOT_FOUND') {
        throw const ControlPlaneException(
          'OBSERVATION_SCOPE_MISMATCH',
          'Observation token scope does not match the event',
          statusCode: 404,
        );
      }
      rethrow;
    }
    if (actor.applicationId != event.applicationId ||
        actor.environmentId != event.environmentId ||
        actor.organizationId != event.organizationId) {
      throw const ControlPlaneException(
        'OBSERVATION_SCOPE_MISMATCH',
        'Observation token scope does not match the event',
        statusCode: 404,
      );
    }
    _validateObservationPolicy(event);
    final now = _now();
    final age = now.difference(event.clientTimestamp);
    if (age < -observationPolicy.futureSkew) {
      await _auditObservationSecurity(
        actor: actor,
        requestId: requestId,
        event: event,
        action: 'observation.rejected',
        code: 'EVENT_CLOCK_INVALID',
      );
      throw const ControlPlaneException(
        'EVENT_CLOCK_INVALID',
        'Observation client timestamp is outside the future skew bound',
        statusCode: 422,
      );
    }
    if (age > observationPolicy.retention) {
      await _auditObservationSecurity(
        actor: actor,
        requestId: requestId,
        event: event,
        action: 'observation.rejected',
        code: 'EVENT_OUTSIDE_RETENTION',
      );
      throw const ControlPlaneException(
        'EVENT_OUTSIDE_RETENTION',
        'Observation is outside the retention window',
        statusCode: 422,
      );
    }
    await _validateObservationIdentity(event, actor);
    final existing = await store.readJson(
      'observations',
      observationStorageId(
        organizationId: event.organizationId,
        applicationId: event.applicationId,
        environmentId: event.environmentId,
        eventId: event.eventId,
      ),
    );
    if (existing != null) {
      final stored = ObservationRecord.fromJson(existing);
      if (canonicalJson(stored.event.toJson()) !=
          canonicalJson(event.toJson())) {
        await _auditObservationSecurity(
          actor: actor,
          requestId: requestId,
          event: event,
          action: 'observation.duplicate_mutation',
          code: 'EVENT_DUPLICATE_MUTATION',
        );
        throw const ControlPlaneException(
          'EVENT_DUPLICATE_MUTATION',
          'Event ID was already used for a different event',
          statusCode: 409,
        );
      }
      return ObservationIngestResult(
        eventId: stored.event.eventId,
        receivedAt: stored.receivedAt,
        disposition: stored.disposition,
        duplicate: true,
      );
    }
    final prior = await _observationHistory(event);
    final quarantined = _observationIsImpossible(event, prior);
    await _enforceObservationRate(actor, event, now);
    if (quarantined) {
      await _auditObservationSecurity(
        actor: actor,
        requestId: requestId,
        event: event,
        action: 'observation.quarantined',
        code: 'EVENT_SEQUENCE_QUARANTINED',
      );
    }
    final disposition = quarantined
        ? ObservationDisposition.quarantined
        : age > observationPolicy.lateWindow
        ? ObservationDisposition.late
        : ObservationDisposition.accepted;
    final record = ObservationRecord(
      event: event,
      receivedAt: now,
      disposition: disposition,
    );
    final stored = await store.createObservation(
      event.organizationId,
      event.applicationId,
      event.environmentId,
      event.eventId,
      record.toJson(),
    );
    if (!stored.created) {
      final previous = ObservationRecord.fromJson(stored.value);
      if (canonicalJson(previous.event.toJson()) !=
          canonicalJson(event.toJson())) {
        await _auditObservationSecurity(
          actor: actor,
          requestId: requestId,
          event: event,
          action: 'observation.duplicate_mutation',
          code: 'EVENT_DUPLICATE_MUTATION',
        );
        throw const ControlPlaneException(
          'EVENT_DUPLICATE_MUTATION',
          'Event ID was already used for a different event',
          statusCode: 409,
        );
      }
      return ObservationIngestResult(
        eventId: previous.event.eventId,
        receivedAt: previous.receivedAt,
        disposition: previous.disposition,
        duplicate: true,
      );
    }
    return ObservationIngestResult(
      eventId: event.eventId,
      receivedAt: now,
      disposition: disposition,
      duplicate: false,
    );
  });

  Future<int> deleteObservations({
    required String token,
    required String organizationId,
    String? applicationId,
    String? environmentId,
    required DateTime olderThan,
    String? requestId,
  }) => _serialized(() async {
    final actor = await _authorize(
      token,
      observationDeleteScope,
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    if (applicationId != null) {
      final application = await _application(applicationId);
      _requireTenant(application.organizationId, actor.organizationId);
    }
    if (environmentId != null) {
      final environment = await _environment(environmentId);
      _requireTenant(environment.organizationId, actor.organizationId);
      if (applicationId != null && environment.applicationId != applicationId) {
        throw const ControlPlaneException(
          'NOT_FOUND',
          'Resource was not found',
          statusCode: 404,
        );
      }
    }
    final count = await store.deleteObservations(
      organizationId: actor.organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
      olderThan: olderThan,
    );
    await _audit(
      requestId: requestId ?? _id('req'),
      actor: actor,
      action: 'observation.delete',
      resourceType: 'observation',
      resourceId: actor.organizationId,
      metadata: <String, Object?>{
        'applicationId': applicationId,
        'environmentId': environmentId,
        'deletedCount': count,
      },
    );
    return count;
  });

  void _validateObservationPolicy(ObservationEvent event) {
    final encoded = utf8.encode(canonicalJson(event.toJson()));
    if (encoded.length > observationPolicy.maxEventBytes) {
      throw const ControlPlaneException(
        'EVENT_TOO_LARGE',
        'Observation event exceeds the supported size',
        statusCode: 413,
      );
    }
    if (event.safeMetadata.length > observationPolicy.maxMetadataKeys ||
        utf8.encode(canonicalJson(event.safeMetadata)).length >
            observationPolicy.maxMetadataBytes ||
        event.safeMetadata.values.any(
          (value) =>
              value is String &&
              utf8.encode(value).length >
                  observationPolicy.maxMetadataValueBytes,
        )) {
      throw const ControlPlaneException(
        'EVENT_TOO_LARGE',
        'Observation metadata exceeds the supported size',
        statusCode: 413,
      );
    }
  }

  Future<void> _validateObservationIdentity(
    ObservationEvent event,
    CredentialRecord actor,
  ) async {
    try {
      final application = await _application(event.applicationId);
      final environment = await _environment(event.environmentId);
      final release = await _release(event.releaseId);
      if (application.organizationId != actor.organizationId ||
          environment.organizationId != actor.organizationId ||
          release.organizationId != actor.organizationId ||
          environment.applicationId != application.id ||
          release.applicationId != application.id ||
          release.platformId != event.platform) {
        throw const FormatException('Observation identity mismatch');
      }
      if (event.patchId != null) {
        final patch = await _patch(event.patchId!);
        if (patch.organizationId != actor.organizationId ||
            patch.releaseId != release.id ||
            (event.sequence != null && patch.sequence != event.sequence)) {
          throw const FormatException('Observation patch identity mismatch');
        }
      } else if (event.sequence != null) {
        throw const FormatException('Observation sequence has no patch');
      }
      if (event.rolloutId != null) {
        final rollout = await _rollout(event.rolloutId!);
        if (rollout.organizationId != actor.organizationId) {
          throw const FormatException('Observation rollout identity mismatch');
        }
        final revision = await _rolloutRevision(
          rollout.id,
          event.rolloutRevision!,
        );
        final target = revision.target;
        if (target.organizationId != actor.organizationId ||
            target.applicationId != application.id ||
            target.environmentId != environment.id ||
            target.releaseId != release.id ||
            (event.patchId != null && target.patchId != event.patchId) ||
            (event.sequence != null && target.sequence != event.sequence)) {
          throw const FormatException('Observation rollout target mismatch');
        }
      }
    } on Object {
      await _auditObservationSecurity(
        actor: actor,
        requestId: null,
        event: event,
        action: 'observation.rejected',
        code: 'EVENT_IDENTITY_MISMATCH',
      );
      throw const ControlPlaneException(
        'EVENT_IDENTITY_MISMATCH',
        'Observation identity does not match trusted control-plane records',
        statusCode: 422,
      );
    }
  }

  Future<List<ObservationRecord>> _observationHistory(
    ObservationEvent event,
  ) async {
    final records = <ObservationRecord>[];
    for (final value in await store.listObservations(
      organizationId: event.organizationId,
      applicationId: event.applicationId,
      environmentId: event.environmentId,
    )) {
      try {
        final record = ObservationRecord.fromJson(value);
        if (record.event.installationBucket == event.installationBucket &&
            record.event.releaseId == event.releaseId &&
            record.event.patchId == event.patchId) {
          records.add(record);
        }
      } on FormatException {
        // A corrupt observation is quarantined from semantic decisions. It
        // cannot become runtime truth or influence eligibility.
      }
    }
    records.sort((left, right) => left.receivedAt.compareTo(right.receivedAt));
    return records;
  }

  bool _observationIsImpossible(
    ObservationEvent event,
    List<ObservationRecord> prior,
  ) {
    bool has(ObservationEventType type) => prior.any(
      (record) =>
          record.disposition != ObservationDisposition.quarantined &&
          record.event.eventType == type,
    );
    return switch (event.eventType) {
      ObservationEventType.healthy_confirmed =>
        !has(ObservationEventType.activation_started) &&
            !has(ObservationEventType.activation_succeeded),
      ObservationEventType.restart_survived =>
        !has(ObservationEventType.activation_succeeded) &&
            !has(ObservationEventType.healthy_confirmed),
      ObservationEventType.activation_succeeded => !has(
        ObservationEventType.activation_started,
      ),
      ObservationEventType.activation_failed => !has(
        ObservationEventType.activation_started,
      ),
      _ => false,
    };
  }

  Future<void> _enforceObservationRate(
    CredentialRecord actor,
    ObservationEvent event,
    DateTime now,
  ) async {
    final keys = <String>[
      'token:${actor.tokenHash}',
      'installation:${actor.tokenHash}:${event.installationBucket}',
      'type:${actor.tokenHash}:${event.eventType.wireName}',
    ];
    final limits = <int>[
      observationPolicy.maxEventsPerTokenWindow,
      observationPolicy.maxEventsPerInstallationWindow,
      observationPolicy.maxEventsPerTypeWindow,
    ];
    final windows = <List<DateTime>>[];
    for (var index = 0; index < keys.length; index++) {
      final window =
          _observationWindows.putIfAbsent(keys[index], () => <DateTime>[])
            ..removeWhere(
              (time) => now.difference(time) >= observationPolicy.rateWindow,
            );
      windows.add(window);
      if (window.length >= limits[index]) {
        await _auditObservationSecurity(
          actor: actor,
          requestId: null,
          event: event,
          action: 'observation.rate_limited',
          code: 'EVENT_RATE_LIMITED',
        );
        throw const ControlPlaneException(
          'EVENT_RATE_LIMITED',
          'Observation rate limit exceeded',
          statusCode: 429,
        );
      }
    }
    for (final window in windows) {
      window.add(now);
    }
    if (_observationWindows.length > 4096) {
      _observationWindows.removeWhere((_, values) => values.isEmpty);
    }
  }

  Future<void> _auditObservationSecurity({
    required CredentialRecord actor,
    required String? requestId,
    required ObservationEvent event,
    required String action,
    required String code,
  }) => _audit(
    requestId: requestId ?? _id('req'),
    actor: actor,
    action: action,
    resourceType: 'observation',
    resourceId: event.eventId,
    metadata: <String, Object?>{
      'eventType': event.eventType.wireName,
      'diagnosticCode': event.diagnosticCode,
      'code': code,
    },
  );

  Future<PatchRecord> _readyPatch(String releaseId, String patchId) async {
    final patch = await _patch(patchId);
    if (patch.releaseId != releaseId || patch.state != 'READY') {
      throw const ControlPlaneException(
        'ROLLOUT_TARGET_MISMATCH',
        'Rollout patch is not a ready patch for the release',
        statusCode: 409,
      );
    }
    return patch;
  }

  Future<RolloutRecord> _rollout(String rolloutId) async {
    final value = await store.readJson('rollouts', rolloutId);
    if (value == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    return RolloutRecord.fromJson(value);
  }

  Future<RolloutRevision> _rolloutRevision(
    String rolloutId,
    int revision,
  ) async {
    final matches = (await store.listJson('rollout_revisions'))
        .where(
          (value) =>
              value['rolloutId'] == rolloutId && value['revision'] == revision,
        )
        .map(RolloutRevision.fromJson)
        .toList(growable: false);
    if (matches.length != 1) {
      throw const ControlPlaneException(
        'ROLLOUT_STORAGE_CORRUPT',
        'Rollout revision is missing or duplicated',
        statusCode: 500,
      );
    }
    return matches.single;
  }

  Future<List<RolloutRevision>> _rolloutHistory(String rolloutId) async {
    final history =
        (await store.listJson('rollout_revisions'))
            .where((value) => value['rolloutId'] == rolloutId)
            .map(RolloutRevision.fromJson)
            .toList()
          ..sort((left, right) => left.revision.compareTo(right.revision));
    return List.unmodifiable(history);
  }

  Future<RolloutSnapshot> _rolloutSnapshot(
    String rolloutId,
    CredentialRecord actor,
  ) async {
    final rollout = await _rollout(rolloutId);
    _requireTenant(rollout.organizationId, actor.organizationId);
    final revision = await _rolloutRevision(
      rollout.id,
      rollout.currentRevision,
    );
    _requireTenant(revision.organizationId, actor.organizationId);
    if (rollout.state != revision.state) {
      throw const ControlPlaneException(
        'ROLLOUT_STORAGE_CORRUPT',
        'Rollout pointer state does not match its current revision',
        statusCode: 500,
      );
    }
    final history = await _rolloutHistory(rollout.id);
    _validateRolloutHistory(rollout, history);
    return RolloutSnapshot(
      rollout: rollout,
      revision: revision,
      history: history,
    );
  }

  Future<void> _rejectOverlappingRollout(RolloutTarget target) async {
    for (final value in await store.listJson('rollouts')) {
      final rollout = RolloutRecord.fromJson(value);
      if (rollout.organizationId != target.organizationId ||
          rollout.state == RolloutState.retired) {
        continue;
      }
      final revision = await _rolloutRevision(
        rollout.id,
        rollout.currentRevision,
      );
      if (_sameRolloutTarget(revision.target, target)) {
        throw const ControlPlaneException(
          'ROLLOUT_CONFLICT',
          'An existing rollout already targets this release and environment',
          statusCode: 409,
        );
      }
    }
  }

  Future<RolloutSnapshot?> _rolloutForUpdate({
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required ReleaseRecord release,
  }) async {
    RolloutSnapshot? found;
    for (final value in await store.listJson('rollouts')) {
      final rollout = RolloutRecord.fromJson(value);
      if (rollout.organizationId != organizationId ||
          rollout.state == RolloutState.retired) {
        continue;
      }
      final revision = await _rolloutRevision(
        rollout.id,
        rollout.currentRevision,
      );
      if (rollout.state != revision.state) {
        throw const ControlPlaneException(
          'ROLLOUT_STORAGE_CORRUPT',
          'Rollout pointer state does not match its current revision',
          statusCode: 500,
        );
      }
      final target = revision.target;
      if (target.applicationId != applicationId ||
          target.environmentId != environmentId ||
          target.platformId != release.platformId ||
          target.releaseId != release.id) {
        continue;
      }
      if (found != null) {
        throw const ControlPlaneException(
          'ROLLOUT_CONFLICT',
          'Multiple rollouts target the same release and environment',
          statusCode: 500,
        );
      }
      found = RolloutSnapshot(
        rollout: rollout,
        revision: revision,
        history: const <RolloutRevision>[],
      );
    }
    return found;
  }

  bool _rolloutEligible(RolloutRevision revision, String installationId) {
    try {
      return RolloutEligibility.isEligible(
        revision: revision,
        installationId: installationId,
      );
    } on FormatException {
      // Invalid client identity is an ineligible client, never a reason to
      // widen delivery or turn a rollout into a runtime trust decision.
      return false;
    }
  }

  RolloutPolicy _transitionPolicy(
    RolloutRevision current,
    RolloutAction action,
    int? requestedPercentage,
  ) {
    final internalToCanary =
        action == RolloutAction.startCanary &&
        current.state == RolloutState.internal;
    if (requestedPercentage != null &&
        action != RolloutAction.expand &&
        !internalToCanary) {
      throw const ControlPlaneException(
        'INVALID_ROLLOUT_POLICY',
        'Only an expand action may change the rollout percentage',
        statusCode: 409,
      );
    }
    if (internalToCanary) {
      final percentage = requestedPercentage;
      if (percentage == null || percentage <= 0 || percentage > 10000) {
        throw const ControlPlaneException(
          'INVALID_ROLLOUT_POLICY',
          'Internal to canary transition requires a positive percentage',
          statusCode: 409,
        );
      }
      return RolloutPolicy(
        cohortKind: RolloutCohortKind.percentage,
        percentageBasisPoints: percentage,
        salt: current.policy.salt,
      );
    }
    final cohort = current.policy.cohortKind;
    if (action == RolloutAction.startInternal &&
        cohort != RolloutCohortKind.internal) {
      throw const ControlPlaneException(
        'INVALID_ROLLOUT_POLICY',
        'Internal rollout state requires an internal cohort',
        statusCode: 409,
      );
    }
    if ((action == RolloutAction.startCanary ||
            action == RolloutAction.startExpanding ||
            action == RolloutAction.expand) &&
        cohort != RolloutCohortKind.percentage) {
      throw const ControlPlaneException(
        'INVALID_ROLLOUT_POLICY',
        'Percentage rollout action requires a percentage cohort',
        statusCode: 409,
      );
    }
    if ((action == RolloutAction.startCanary ||
            action == RolloutAction.startExpanding) &&
        current.policy.percentageBasisPoints == 0) {
      throw const ControlPlaneException(
        'INVALID_ROLLOUT_POLICY',
        'A percentage rollout must start above zero basis points',
        statusCode: 409,
      );
    }
    if (action != RolloutAction.expand) {
      return current.policy;
    }
    final percentage = requestedPercentage;
    if (percentage == null ||
        percentage <= current.policy.percentageBasisPoints ||
        percentage > 10000) {
      throw const ControlPlaneException(
        'INVALID_ROLLOUT_POLICY',
        'Expansion must increase the percentage within 10000 basis points',
        statusCode: 409,
      );
    }
    return RolloutPolicy(
      cohortKind: cohort,
      percentageBasisPoints: percentage,
      salt: current.policy.salt,
      internalInstallationHashes: current.policy.internalInstallationHashes,
      exposureMode: current.policy.exposureMode,
    );
  }

  String _rolloutScope(RolloutAction action) => switch (action) {
    RolloutAction.ready ||
    RolloutAction.pause ||
    RolloutAction.retire => 'rollout:update',
    RolloutAction.startInternal ||
    RolloutAction.startCanary ||
    RolloutAction.startExpanding ||
    RolloutAction.expand ||
    RolloutAction.resume ||
    RolloutAction.complete => 'rollout:promote',
    RolloutAction.halt => 'rollout:halt',
  };

  String _rolloutAuditAction(RolloutAction action, RolloutState fromState) {
    if (action == RolloutAction.startCanary &&
        fromState == RolloutState.internal) {
      return 'rollout.expanded';
    }
    return switch (action) {
      RolloutAction.ready => 'rollout.ready',
      RolloutAction.startInternal ||
      RolloutAction.startCanary ||
      RolloutAction.startExpanding => 'rollout.started',
      RolloutAction.expand => 'rollout.expanded',
      RolloutAction.pause => 'rollout.paused',
      RolloutAction.resume => 'rollout.resumed',
      RolloutAction.halt => 'rollout.halted',
      RolloutAction.complete => 'rollout.completed',
      RolloutAction.retire => 'rollout.retired',
    };
  }

  bool _sameRolloutTarget(RolloutTarget left, RolloutTarget right) =>
      left.organizationId == right.organizationId &&
      left.applicationId == right.applicationId &&
      left.environmentId == right.environmentId &&
      left.platformId == right.platformId &&
      left.releaseId == right.releaseId;

  void _validateRolloutHistory(
    RolloutRecord rollout,
    List<RolloutRevision> history,
  ) {
    if (history.length != rollout.currentRevision || history.isEmpty) {
      throw const ControlPlaneException(
        'ROLLOUT_STORAGE_CORRUPT',
        'Rollout revision history is incomplete',
        statusCode: 500,
      );
    }
    final firstTarget = history.first.target;
    for (var index = 0; index < history.length; index++) {
      final revision = history[index];
      if (revision.revision != index + 1 ||
          revision.rolloutId != rollout.id ||
          revision.organizationId != rollout.organizationId ||
          revision.previousRevision != (index == 0 ? null : index)) {
        throw const ControlPlaneException(
          'ROLLOUT_STORAGE_CORRUPT',
          'Rollout revision history is not contiguous',
          statusCode: 500,
        );
      }
      if (!_sameRolloutRevisionTarget(revision.target, firstTarget)) {
        throw const ControlPlaneException(
          'ROLLOUT_STORAGE_CORRUPT',
          'Rollout target changed across immutable revisions',
          statusCode: 500,
        );
      }
    }
  }

  bool _sameRolloutRevisionTarget(RolloutTarget left, RolloutTarget right) =>
      left.organizationId == right.organizationId &&
      left.applicationId == right.applicationId &&
      left.environmentId == right.environmentId &&
      left.platformId == right.platformId &&
      left.releaseId == right.releaseId &&
      left.runtimeReleaseId == right.runtimeReleaseId &&
      left.patchId == right.patchId &&
      left.runtimePatchId == right.runtimePatchId &&
      left.artifactId == right.artifactId &&
      left.sha256 == right.sha256 &&
      left.sequence == right.sequence;

  Future<List<AuditRecord>> readAudit({
    required String token,
    required String organizationId,
  }) async {
    final actor = await _authorize(
      token,
      'audit:read',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final result = <AuditRecord>[];
    for (final value in await store.listJson('audit')) {
      final record = AuditRecord.fromJson(value);
      if (record.organizationId == actor.organizationId) result.add(record);
    }
    return List.unmodifiable(result);
  }

  Future<AuditExport> exportAudit({
    required String token,
    required String organizationId,
    int retentionDays = 365,
  }) async {
    if (retentionDays <= 0) {
      throw const ControlPlaneException(
        'INVALID_RETENTION',
        'Audit retention must be positive',
      );
    }
    final actor = await _authorize(
      token,
      'audit:read',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final cutoff = _now().subtract(Duration(days: retentionDays));
    final records = (await store.listJson('audit'))
        .where(
          (value) =>
              value['organizationId'] == actor.organizationId &&
              _auditWithinRetention(value['createdAt'], cutoff),
        )
        .toList(growable: false);
    final rawChain = await store.readAuditChain();
    final verification = verifyAuditChain(rawChain);
    final chain = rawChain
        .where((value) {
          final body = value['body'];
          return value['organizationId'] == actor.organizationId &&
              body is Map &&
              _auditWithinRetention(body['createdAt'], cutoff);
        })
        .toList(growable: false);
    return AuditExport(
      retentionDays: retentionDays,
      records: List.unmodifiable(records),
      chain: List.unmodifiable(chain),
      verification: verification,
    );
  }

  Future<ArtifactReconciliationReport> reconcileArtifacts({
    required String token,
    required String organizationId,
    String? requestId,
  }) => _serialized(() async {
    final actor = await _authorize(
      token,
      'artifact:reconcile',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final rawArtifacts = await store.listJson('artifacts');
    final rawPatches = <String, Map<String, Object?>>{
      for (final value in await store.listJson('patches'))
        if (value['id'] is String) value['id']! as String: value,
    };
    final expectedKeys = <String>{};
    final items = <ArtifactReconciliationItem>[];
    var quarantined = 0;
    for (final raw in rawArtifacts) {
      final artifact = ArtifactRecord.fromJson(raw);
      expectedKeys.add(artifact.sha256.substring(7));
      if (artifact.organizationId != actor.organizationId) continue;
      final patch = rawPatches[artifact.patchId];
      if (patch == null) {
        items.add(
          ArtifactReconciliationItem(
            status: 'orphan_metadata',
            artifactId: artifact.id,
            digest: artifact.sha256,
            detail: 'Artifact metadata references a missing patch',
          ),
        );
        continue;
      }
      if (artifact.state != 'READY') {
        items.add(
          ArtifactReconciliationItem(
            status: 'non_ready',
            artifactId: artifact.id,
            digest: artifact.sha256,
            detail: artifact.state,
          ),
        );
        continue;
      }
      List<int>? bytes;
      try {
        bytes = await store.readArtifact(artifact.sha256);
      } on StorageUnavailable catch (error) {
        items.add(
          ArtifactReconciliationItem(
            status: 'unavailable',
            artifactId: artifact.id,
            digest: artifact.sha256,
            detail: error.message,
          ),
        );
        continue;
      }
      final actual = bytes == null ? null : sha256Digest(bytes);
      final status = bytes == null
          ? 'missing_object'
          : actual != artifact.sha256
          ? 'digest_mismatch'
          : bytes.length != artifact.sizeBytes
          ? 'size_mismatch'
          : 'verified';
      if (status != 'verified') {
        await store.replaceJson(
          'artifacts',
          artifact.id,
          artifact.copyWith(state: 'QUARANTINED').toJson(),
        );
        quarantined++;
      }
      items.add(
        ArtifactReconciliationItem(
          status: status,
          artifactId: artifact.id,
          digest: artifact.sha256,
          detail: actual,
        ),
      );
    }
    var inventoryAvailable = false;
    final inventory = <String>{};
    try {
      final source = store;
      if (source case final ArtifactInventory provider) {
        inventory.addAll(await provider.listArtifactKeys());
        inventoryAvailable = true;
        for (final key in inventory) {
          final normalized = key.startsWith('sha256:') ? key.substring(7) : key;
          if (!expectedKeys.contains(normalized)) {
            items.add(
              ArtifactReconciliationItem(
                status: 'orphan_object',
                artifactId: null,
                digest: 'sha256:$normalized',
              ),
            );
          }
        }
      }
    } on StorageUnavailable catch (error) {
      items.add(
        ArtifactReconciliationItem(
          status: 'inventory_unavailable',
          artifactId: null,
          digest: null,
          detail: error.message,
        ),
      );
    }
    final report = ArtifactReconciliationReport(
      items: List.unmodifiable(items),
      inventoryAvailable: inventoryAvailable,
      quarantinedCount: quarantined,
    );
    await _audit(
      requestId: requestId ?? _id('req'),
      actor: actor,
      action: 'artifact.reconcile',
      resourceType: 'artifact-inventory',
      resourceId: actor.organizationId,
      metadata: <String, Object?>{
        'inventoryAvailable': report.inventoryAvailable,
        'quarantinedCount': report.quarantinedCount,
        'itemCount': report.items.length,
      },
    );
    return report;
  });

  Future<void> revokeCredential({
    required String token,
    required String credentialId,
    required String organizationId,
    String? requestId,
  }) => _serialized(() async {
    final actor = await _authorize(
      token,
      'credential:revoke',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    final values = await store.listJson('credentials');
    Map<String, Object?>? raw;
    for (final value in values) {
      if (value['id'] == credentialId) {
        raw = value;
        break;
      }
    }
    if (raw == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final credential = CredentialRecord.fromJson(raw);
    _requireTenant(credential.organizationId, actor.organizationId);
    await store.replaceJson(
      'credentials',
      credential.tokenHash,
      credential.copyWith(revoked: true).toJson(),
    );
    await _audit(
      requestId: requestId ?? _id('req'),
      actor: actor,
      action: switch (credential.kind) {
        CredentialKind.observation => 'observation.token_revoked',
        CredentialKind.scheduler => 'scheduler.credential_revoked',
        CredentialKind.autoHalt => 'health.auto_halt_principal_revoked',
        _ => 'credential.revoke',
      },
      resourceType: 'credential',
      resourceId: credential.id,
      metadata: const <String, Object?>{},
    );
  });

  Future<List<ContentRecord>> _contentRecords() async {
    try {
      return List.unmodifiable(
        (await store.listJson(contentCollection)).map(ContentRecord.fromJson),
      );
    } on FormatException {
      throw const ControlPlaneException(
        'STORAGE_CORRUPT',
        'A content record is malformed',
        statusCode: 500,
      );
    } on TypeError {
      throw const ControlPlaneException(
        'STORAGE_CORRUPT',
        'A content record is malformed',
        statusCode: 500,
      );
    }
  }

  Future<ContentRecord> _content(String contentId) async {
    final value = await store.readJson(contentCollection, contentId);
    if (value == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    try {
      return ContentRecord.fromJson(value);
    } on FormatException {
      throw const ControlPlaneException(
        'STORAGE_CORRUPT',
        'The content record is malformed',
        statusCode: 500,
      );
    } on TypeError {
      throw const ControlPlaneException(
        'STORAGE_CORRUPT',
        'The content record is malformed',
        statusCode: 500,
      );
    }
  }

  Future<void> _ensureContentSlugAvailable({
    required String organizationId,
    required ContentKind kind,
    required String slug,
    String? excludingId,
  }) async {
    final conflict = (await _contentRecords()).any(
      (record) =>
          record.id != excludingId &&
          record.organizationId == organizationId &&
          record.kind == kind &&
          record.slug == slug,
    );
    if (conflict) {
      throw const ControlPlaneException(
        'CONTENT_SLUG_CONFLICT',
        'A content entry with this kind and slug already exists',
        statusCode: 409,
      );
    }
  }

  String _writeSlug(String slug, String title) =>
      normalizeContentSlug(slug.trim().isEmpty ? title : slug);

  Future<CredentialRecord> _authorize(
    String token,
    String scope, {
    CredentialKind? kind,
    String? organizationId,
    String? applicationId,
    String? environmentId,
  }) async {
    final auth = humanAuth;
    if (auth != null && AuthJwt.isJwtLike(token)) {
      if (kind != null && kind != CredentialKind.control) {
        throw const ControlPlaneException(
          'FORBIDDEN',
          'Human access tokens are not permitted for this credential kind',
          statusCode: 403,
        );
      }
      return auth.authorizeAccessToken(
        token: token,
        requiredScope: scope,
        kind: kind ?? CredentialKind.control,
        organizationId: organizationId,
        applicationId: applicationId,
        environmentId: environmentId,
      );
    }
    return CredentialService.authorize(
      token: token,
      requiredScope: scope,
      read: (hash) async {
        final value = await store.readJson('credentials', hash);
        return value == null ? null : CredentialRecord.fromJson(value);
      },
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
      kind: kind,
      now: _now(),
    );
  }

  Future<CredentialRecord> _authorizeHealth(
    String token, {
    String? schedulerApplicationId,
    String? schedulerEnvironmentId,
  }) async {
    final schedulerAllowed =
        schedulerApplicationId != null && schedulerEnvironmentId != null;
    late final CredentialRecord actor;
    if (schedulerAllowed) {
      try {
        actor = await _authorize(
          token,
          'health:evaluate',
          kind: CredentialKind.scheduler,
          applicationId: schedulerApplicationId,
          environmentId: schedulerEnvironmentId,
        );
      } on ControlPlaneException catch (error) {
        if (error.code != 'FORBIDDEN') rethrow;
        actor = await _authorize(
          token,
          'health:evaluate',
          kind: CredentialKind.control,
        );
      }
    } else {
      actor = await _authorize(
        token,
        'health:evaluate',
        kind: CredentialKind.control,
      );
    }
    final required = <String>{
      'observation:read',
      'rollout:read',
      if (actor.kind == CredentialKind.scheduler) 'health:work:claim',
    };
    if (!actor.scopes.containsAll(required)) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'Credential does not have the required health-read scopes',
        statusCode: 403,
      );
    }
    return actor;
  }

  Future<CredentialRecord> _authorizeHealthHalt(
    String token, {
    String? organizationId,
  }) async {
    final actor = await _authorize(
      token,
      'health:evaluate',
      kind: CredentialKind.control,
      organizationId: organizationId,
    );
    const required = <String>{'rollout:read', 'rollout:halt'};
    if (!actor.scopes.containsAll(required)) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'Credential does not have the required health-halt scopes',
        statusCode: 403,
      );
    }
    return actor;
  }

  String _healthDigest(String value, String label) {
    try {
      return requireSha256Digest(value);
    } on FormatException {
      throw ControlPlaneException(
        'HEALTH_HALT_INVALID_REQUEST',
        '$label is invalid',
      );
    }
  }

  Future<void> _validateHaltEvidence({
    required RolloutRevision current,
    required RolloutDecisionRecord decision,
    required HealthEvaluation evaluation,
    required HealthAggregateRecord aggregate,
    required HealthAggregateRevision revision,
    required int expectedRolloutRevision,
    required String targetBindingDigest,
    required String evaluationInputDigest,
    required String aggregateInputDigest,
    required String aggregateDigest,
    required P3ePersistenceStore p3e,
  }) async {
    try {
      if (decision.decision != evaluation.decision ||
          decision.evaluationId != evaluation.evaluationId ||
          decision.aggregateRevisionId != evaluation.aggregateRevisionId ||
          decision.rolloutId != evaluation.rolloutId ||
          decision.expectedRolloutRevision != evaluation.rolloutRevision ||
          decision.resultingTransitionReference != null ||
          evaluation.evaluationInputDigest == null ||
          evaluation.targetBindingDigest == null ||
          evaluation.evaluationInputDigest != evaluationInputDigest ||
          evaluation.targetBindingDigest != targetBindingDigest ||
          _rolloutTargetDigest(current.target) != targetBindingDigest ||
          evaluation.aggregateInputDigest != aggregateInputDigest ||
          aggregate.aggregateDigest != aggregateDigest ||
          revision.inputDigest != aggregateInputDigest ||
          revision.identity.rolloutRevision != expectedRolloutRevision ||
          revision.identity.rolloutId != current.rolloutId ||
          !_sameHealthTargetIdentity(current.target, revision.identity)) {
        throw const FormatException('Health halt evidence binding is invalid');
      }
      validateP3eAggregateLineage(aggregate, revision);
      final report = await p3e.reconcile(aggregate.organizationId);
      final affected = report.issues.where(
        (issue) =>
            (issue.entityType == 'aggregate' &&
                issue.entityId == aggregate.aggregateId) ||
            (issue.entityType == 'revision' &&
                issue.entityId == revision.aggregateRevisionId) ||
            (issue.entityType == 'evaluation' &&
                issue.entityId == evaluation.evaluationId) ||
            (issue.entityType == 'decision' &&
                issue.entityId == decision.decisionId),
      );
      if (affected.isNotEmpty) {
        throw const FormatException(
          'Health halt evidence failed reconciliation',
        );
      }
    } on ControlPlaneException {
      rethrow;
    } on StorageUnavailable {
      rethrow;
    } on Object {
      throw const ControlPlaneException(
        'HEALTH_EVIDENCE_INVALID',
        'Persisted health halt evidence failed validation',
        statusCode: 422,
      );
    }
  }

  bool _sameHealthTargetIdentity(
    RolloutTarget target,
    AggregateIdentity identity,
  ) =>
      target.organizationId == identity.organizationId &&
      target.applicationId == identity.applicationId &&
      target.environmentId == identity.environmentId &&
      target.platformId == identity.platformId &&
      target.releaseId == identity.releaseId &&
      target.patchId == identity.patchId &&
      target.sequence == identity.sequence;

  String _rolloutTargetDigest(RolloutTarget target) =>
      sha256Digest(utf8.encode(canonicalJson(target.toJson())));

  RolloutRevision? _healthHaltRevision(
    RolloutSnapshot snapshot,
    int expectedRevision,
    String decisionId,
  ) {
    final marker = 'P3E4 health halt decision $decisionId:';
    for (final revision in snapshot.history) {
      if (revision.revision == expectedRevision + 1 &&
          revision.state == RolloutState.halted &&
          revision.reason.startsWith(marker)) {
        return revision;
      }
    }
    return null;
  }

  Future<HealthHaltApplication> _recordHealthHaltOutcome({
    required P3ePersistenceStore p3e,
    required CredentialRecord actor,
    required RolloutDecisionRecord decision,
    required HealthEvaluation evaluation,
    required HealthAggregateRevision revision,
    required String result,
    required String reason,
    required String idempotencyKey,
    required Map<String, Object?> idempotencyBody,
    required String? requestId,
    int? previousRolloutRevision,
    int? resultingRolloutRevision,
    String? resultingTransitionReference,
    ControlPlaneException? error,
  }) async {
    final application = HealthHaltApplication(
      applicationId: healthHaltApplicationId(
        organizationId: actor.organizationId,
        decisionId: decision.decisionId,
        idempotencyKey: idempotencyKey,
      ),
      organizationId: actor.organizationId,
      decisionId: decision.decisionId,
      evaluationId: evaluation.evaluationId,
      aggregateRevisionId: revision.aggregateRevisionId,
      rolloutId: decision.rolloutId,
      expectedRolloutRevision: decision.expectedRolloutRevision,
      result: result,
      reason: reason,
      actorIdentity: actor.id,
      idempotencyKey: idempotencyKey,
      previousRolloutRevision: previousRolloutRevision,
      resultingRolloutRevision: resultingRolloutRevision,
      resultingTransitionReference: resultingTransitionReference,
      createdAt: _now(),
    );
    HealthHaltApplication persisted = application;
    try {
      await p3e.putHaltApplication(application);
    } on StorageConflict {
      final existing = await p3e.readHaltApplication(
        actor.organizationId,
        application.applicationId,
      );
      if (existing == null || !_sameHealthHaltAttempt(existing, application)) {
        throw const ControlPlaneException(
          'HEALTH_HALT_CONFLICT',
          'Immutable health halt application evidence conflicted',
          statusCode: 409,
        );
      }
      persisted = existing;
    }
    try {
      await _saveIdempotency(
        'health-halt-application',
        idempotencyKey,
        idempotencyBody,
        <String, Object?>{'applicationId': persisted.applicationId},
      );
    } on StorageConflict {
      final existing = await store.readIdempotency(
        'health-halt-application',
        idempotencyKey,
      );
      if (existing == null ||
          existing['requestDigest'] !=
              sha256Digest(utf8.encode(canonicalJson(idempotencyBody)))) {
        throw const ControlPlaneException(
          'HEALTH_HALT_CONFLICT',
          'Idempotency key was already used for a different halt request',
          statusCode: 409,
        );
      }
    }
    final action = switch (persisted.result) {
      'APPLIED' => 'health.halt.applied',
      'ALREADY_APPLIED' => 'health.halt.already_applied',
      'STALE' => 'health.halt.stale',
      'CONFLICT' => 'health.halt.conflict',
      'EVIDENCE_REJECTED' => 'health.halt.evidence_rejected',
      _ => 'health.halt.rejected',
    };
    await _auditHealthHalt(
      actor: actor,
      requestId: requestId,
      action: action,
      resourceId: decision.decisionId,
      metadata: <String, Object?>{
        'applicationId': persisted.applicationId,
        'result': persisted.result,
        if (persisted.resultingRolloutRevision != null)
          'resultingRolloutRevision': persisted.resultingRolloutRevision,
      },
    );
    if (error != null) throw error;
    return persisted;
  }

  bool _sameHealthHaltAttempt(
    HealthHaltApplication left,
    HealthHaltApplication right,
  ) =>
      left.organizationId == right.organizationId &&
      left.decisionId == right.decisionId &&
      left.evaluationId == right.evaluationId &&
      left.aggregateRevisionId == right.aggregateRevisionId &&
      left.rolloutId == right.rolloutId &&
      left.expectedRolloutRevision == right.expectedRolloutRevision &&
      left.actorIdentity == right.actorIdentity &&
      left.idempotencyKey == right.idempotencyKey;

  Future<void> _recordHaltApplicationBestEffort({
    required P3ePersistenceStore p3e,
    required CredentialRecord actor,
    required RolloutDecisionRecord decision,
    required HealthEvaluation evaluation,
    required HealthAggregateRevision revision,
    required String result,
    required String reason,
    required String idempotencyKey,
    required Map<String, Object?> idempotencyBody,
    required String? requestId,
  }) async {
    try {
      await _recordHealthHaltOutcome(
        p3e: p3e,
        actor: actor,
        decision: decision,
        evaluation: evaluation,
        revision: revision,
        result: result,
        reason: reason,
        idempotencyKey: idempotencyKey,
        idempotencyBody: idempotencyBody,
        requestId: requestId,
      );
    } on Object {
      // Evidence rejection must remain fail-closed even if its optional
      // append-only audit/link record cannot be written during an outage.
    }
  }

  Future<void> _auditHealthHalt({
    required CredentialRecord actor,
    required String? requestId,
    required String action,
    required String resourceId,
    required Map<String, Object?> metadata,
  }) => _audit(
    requestId: requestId ?? _id('req'),
    actor: actor,
    action: action,
    resourceType: 'health-halt-application',
    resourceId: resourceId,
    metadata: metadata,
  );

  P3ePersistenceStore _requireP3eStore() {
    final value = p3eStore;
    if (value == null) {
      throw const ControlPlaneException(
        'HEALTH_EVALUATION_UNAVAILABLE',
        'P3E persistence is not configured',
        statusCode: 503,
      );
    }
    return value;
  }

  Future<void> _validateP3eEvidence(
    P3ePersistenceStore p3e,
    HealthAggregateRecord aggregate,
    HealthAggregateRevision revision,
  ) async {
    try {
      validateP3eAggregateLineage(aggregate, revision);
      final report = await p3e.reconcile(aggregate.organizationId);
      final affected = report.issues.where(
        (issue) =>
            (issue.entityType == 'aggregate' &&
                issue.entityId == aggregate.aggregateId) ||
            (issue.entityType == 'revision' &&
                issue.entityId == revision.aggregateRevisionId),
      );
      if (affected.isNotEmpty) {
        throw const FormatException('P3E evidence failed reconciliation');
      }
    } on ControlPlaneException {
      rethrow;
    } on StorageUnavailable {
      rethrow;
    } on Object {
      throw const ControlPlaneException(
        'HEALTH_AGGREGATE_INVALID',
        'Persisted health evidence failed validation',
        statusCode: 422,
      );
    }
  }

  bool _sameHealthTarget(
    RolloutTarget target,
    ManualEvaluationRequest request,
  ) =>
      target.organizationId == request.organizationId &&
      target.applicationId == request.applicationId &&
      target.environmentId == request.environmentId &&
      target.platformId == request.platformId &&
      target.releaseId == request.releaseId &&
      target.patchId == request.patchId &&
      target.sequence == request.sequence;

  Future<ManualEvaluationSnapshot> _readHealthSnapshot(
    P3ePersistenceStore p3e,
    String organizationId,
    String rolloutId,
    HealthEvaluation evaluation,
  ) async {
    try {
      if (evaluation.rolloutId != rolloutId ||
          evaluation.organizationId != organizationId ||
          evaluation.evaluationInputDigest == null) {
        throw const FormatException('Manual evaluation body is invalid');
      }
      final revision = await p3e.readAggregateRevision(
        organizationId,
        evaluation.aggregateRevisionId,
      );
      if (revision == null) {
        throw const FormatException('Manual evaluation revision is missing');
      }
      final aggregate = await p3e.readAggregate(
        organizationId,
        revision.aggregateId,
      );
      if (aggregate == null ||
          revision.identity.organizationId != organizationId ||
          revision.identity.rolloutId != rolloutId ||
          revision.identity.rolloutRevision != evaluation.rolloutRevision ||
          revision.inputDigest != evaluation.aggregateInputDigest) {
        throw const FormatException('Manual evaluation scope is invalid');
      }
      await _validateP3eEvidence(p3e, aggregate, revision);
      final direct = await p3e.readDecision(
        organizationId,
        manualDecisionId(evaluation.evaluationId),
      );
      final decision =
          direct ??
          (await p3e.listDecisions(organizationId)).firstWhere(
            (candidate) => candidate.evaluationId == evaluation.evaluationId,
            orElse: () => throw const FormatException(
              'Health evaluation decision evidence is missing',
            ),
          );
      if (decision.organizationId != organizationId ||
          decision.evaluationId != evaluation.evaluationId ||
          decision.rolloutId != rolloutId ||
          decision.expectedRolloutRevision != evaluation.rolloutRevision ||
          decision.decision != evaluation.decision ||
          decision.aggregateRevisionId != evaluation.aggregateRevisionId ||
          decision.resultingTransitionReference != null) {
        throw const FormatException(
          'Health evaluation decision binding is invalid',
        );
      }
      return ManualEvaluationSnapshot(
        evaluation: evaluation,
        decision: decision,
      );
    } on ControlPlaneException {
      rethrow;
    } on StorageUnavailable {
      rethrow;
    } on Object {
      throw const ControlPlaneException(
        'HEALTH_EVALUATION_INVALID',
        'Persisted health evaluation is not a valid manual-evaluation record',
        statusCode: 500,
      );
    }
  }

  Future<void> _ensureHealthDecision(
    P3ePersistenceStore p3e, {
    required HealthEvaluation evaluation,
    required CredentialRecord actor,
    required String idempotencyKey,
  }) async {
    final decision = RolloutDecisionRecord(
      decisionId: manualDecisionId(evaluation.evaluationId),
      organizationId: evaluation.organizationId,
      rolloutId: evaluation.rolloutId,
      expectedRolloutRevision: evaluation.rolloutRevision,
      evaluationId: evaluation.evaluationId,
      aggregateRevisionId: evaluation.aggregateRevisionId,
      decision: evaluation.decision,
      reason: _healthDecisionReason(evaluation.reasonCodes),
      actorIdentity: actor.id,
      idempotencyKey: idempotencyKey,
      createdAt: evaluation.createdAt,
      previousDecisionId: null,
      resultingTransitionReference: null,
    );
    try {
      await p3e.putDecision(decision);
    } on StorageConflict {
      final existing = await p3e.readDecision(
        evaluation.organizationId,
        decision.decisionId,
      );
      if (existing == null ||
          existing.evaluationId != evaluation.evaluationId ||
          existing.decision != evaluation.decision) {
        throw const ControlPlaneException(
          'HEALTH_EVALUATION_CONFLICT',
          'Concurrent decision evidence conflicted with immutable storage',
          statusCode: 409,
        );
      }
    }
  }

  Future<void> _auditHealth({
    required CredentialRecord actor,
    required String? requestId,
    required String action,
    required String evaluationId,
    required Map<String, Object?> metadata,
  }) => _audit(
    requestId: requestId ?? _id('req'),
    actor: actor,
    action: action,
    resourceType: 'health-evaluation',
    resourceId: evaluationId,
    metadata: metadata,
  );

  String _healthDecisionReason(Iterable<String> reasonCodes) {
    final value = reasonCodes.join(',');
    return value.isEmpty ? 'MANUAL_EVALUATION' : value;
  }

  int _healthCursorIndex(List<HealthEvaluation> evaluations, String? cursor) {
    if (cursor == null) return 0;
    final decoded = _decodeHealthCursor(cursor);
    final index = evaluations.indexWhere(
      (evaluation) =>
          evaluation.createdAt.toIso8601String() == decoded.$1 &&
          evaluation.evaluationId == decoded.$2,
    );
    if (index < 0) {
      throw const ControlPlaneException(
        'INVALID_CURSOR',
        'Evaluation cursor is invalid or expired',
      );
    }
    return index + 1;
  }

  String _healthCursor(HealthEvaluation evaluation) => base64Url
      .encode(
        utf8.encode(
          '${evaluation.createdAt.toIso8601String()}|${evaluation.evaluationId}',
        ),
      )
      .replaceAll('=', '');

  (String, String) _decodeHealthCursor(String cursor) {
    try {
      final padded = cursor.padRight((cursor.length + 3) ~/ 4 * 4, '=');
      final value = utf8.decode(base64Url.decode(padded));
      final separator = value.indexOf('|');
      if (separator <= 0 || separator == value.length - 1) {
        throw const FormatException();
      }
      final timestamp = DateTime.parse(value.substring(0, separator)).toUtc();
      final evaluationId = value.substring(separator + 1);
      return (timestamp.toIso8601String(), evaluationId);
    } on Object {
      throw const ControlPlaneException(
        'INVALID_CURSOR',
        'Evaluation cursor is invalid or expired',
      );
    }
  }

  String _bundleImportId({
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String bundleDigest,
  }) =>
      'bnd_${sha256Hex(utf8.encode('$organizationId|$applicationId|$environmentId|$bundleDigest')).substring(0, 48)}';

  String _bundleRecordId({
    required String prefix,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String bundleDigest,
  }) =>
      '${prefix}_bnd_${sha256Hex(utf8.encode('hyfens.release-bundle.v1|$prefix|$organizationId|$applicationId|$environmentId|$bundleDigest')).substring(0, 56)}';

  Future<void> _ensureBundleRecord({
    required String collection,
    required String id,
    required Map<String, Object?> value,
  }) async {
    final existing = await store.readJson(collection, id);
    if (existing == null) {
      await store.createJson(collection, id, value);
      return;
    }
    if (canonicalJson(existing) == canonicalJson(value)) return;
    final canRecoverAdmissionState =
        (collection == 'patches' || collection == 'artifacts') &&
        existing['state'] == 'READY' &&
        value['state'] == 'QUARANTINED';
    if (canRecoverAdmissionState) {
      final existingMetadata = Map<String, Object?>.from(existing)
        ..remove('state');
      final expectedMetadata = Map<String, Object?>.from(value)
        ..remove('state');
      if (canonicalJson(existingMetadata) == canonicalJson(expectedMetadata)) {
        return;
      }
    }
    throw const StorageConflict(
      'Bundle destination record conflicts with the expected immutable record',
    );
  }

  String _validateExistingBundleImport(
    Map<String, Object?> value, {
    required String importId,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required ReleaseBundle bundle,
    required String releaseId,
    required String patchId,
    required String artifactId,
  }) {
    final expected = <String, Object?>{
      'id': importId,
      'organizationId': organizationId,
      'applicationId': applicationId,
      'environmentId': environmentId,
      'bundleDigest': bundle.bundleDigest,
      'source': bundle.payload.source.toJson(),
      'signedPayload': bundle.signedPayloadMetadata,
      'bundleKeyId': bundle.keyId,
      'bundleSignature': base64Encode(bundle.signature),
      'releaseId': releaseId,
      'patchId': patchId,
      'artifactId': artifactId,
    };
    for (final entry in expected.entries) {
      if (canonicalJson(value[entry.key]) != canonicalJson(entry.value)) {
        throw const StorageConflict(
          'Bundle import provenance conflicts with the signed bundle',
        );
      }
    }
    final state = _bundleStoredString(value, 'state');
    if (state != 'QUARANTINED' && state != 'ADMITTED') {
      throw const StorageConflict('Bundle import state is invalid');
    }
    _validateBundleTimestamp(value, 'createdAt');
    if (value.containsKey('admittedAt')) {
      _validateBundleTimestamp(value, 'admittedAt');
    }
    return state;
  }

  void _validateBundleTimestamp(Map<String, Object?> value, String key) {
    final text = _bundleStoredString(value, key);
    try {
      final parsed = DateTime.parse(text).toUtc();
      if (parsed.toIso8601String() != text) throw const FormatException();
    } on Object {
      throw const StorageConflict('Bundle import timestamp is invalid');
    }
  }

  Future<Map<String, Object?>?> _findBundleImport({
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String releaseId,
    required String patchId,
  }) async {
    final matches = (await store.listJson('bundle_imports'))
        .where(
          (value) =>
              value['organizationId'] == organizationId &&
              value['applicationId'] == applicationId &&
              value['environmentId'] == environmentId &&
              value['releaseId'] == releaseId &&
              value['patchId'] == patchId,
        )
        .toList(growable: false);
    if (matches.length > 1) {
      throw const ControlPlaneException(
        'STORAGE_CORRUPT',
        'Multiple bundle imports match the destination records',
        statusCode: 500,
      );
    }
    return matches.isEmpty ? null : matches.single;
  }

  Future<ReleaseBundleImportResult> _readBundleImport(
    String importId, {
    required bool idempotentReplay,
  }) async {
    final raw = await store.readJson('bundle_imports', importId);
    if (raw == null) {
      throw const ControlPlaneException(
        'STORAGE_CORRUPT',
        'Bundle import provenance is missing',
        statusCode: 500,
      );
    }
    try {
      final state = _bundleStoredString(raw, 'state');
      if (_bundleStoredString(raw, 'id') != importId ||
          state != 'QUARANTINED' && state != 'ADMITTED') {
        throw const FormatException('Invalid bundle import state');
      }
      final source = ReleaseBundleSource.fromJson(raw['source']);
      final bundleDigest = requireSha256Digest(
        _bundleStoredString(raw, 'bundleDigest'),
      );
      final organizationId = _bundleStoredString(raw, 'organizationId');
      final applicationId = _bundleStoredString(raw, 'applicationId');
      final environmentId = _bundleStoredString(raw, 'environmentId');
      final releaseId = _bundleStoredString(raw, 'releaseId');
      final patchId = _bundleStoredString(raw, 'patchId');
      final artifactId = _bundleStoredString(raw, 'artifactId');
      final signedPayload = _bundleStoredObject(raw, 'signedPayload');
      _bundleStoredString(raw, 'bundleKeyId');
      _bundleStoredString(raw, 'bundleSignature');
      // Parsing only needs a non-empty canonical base64 value here; the
      // actual content is reloaded and verified during admission.
      final storedPayload = _bundlePayloadFromStoredMetadata(
        signedPayload,
        const <int>[0],
      );
      final release = await _release(releaseId);
      final patch = await _patch(patchId);
      final artifact = await _artifact(artifactId);
      final environment = await _environment(environmentId);
      if (release.organizationId != organizationId ||
          release.applicationId != applicationId ||
          environment.organizationId != organizationId ||
          environment.applicationId != applicationId ||
          patch.organizationId != organizationId ||
          patch.releaseId != release.id ||
          patch.artifactId != artifact.id ||
          artifact.organizationId != organizationId ||
          artifact.patchId != patch.id) {
        throw const FormatException(
          'Bundle import destination binding is invalid',
        );
      }
      if (canonicalJson(storedPayload.source.toJson()) !=
              canonicalJson(source.toJson()) ||
          storedPayload.release.id != source.releaseId ||
          storedPayload.patch.id != source.patchId ||
          storedPayload.artifact.id != source.artifactId) {
        throw const FormatException(
          'Bundle import signed payload metadata is not bound to its records',
        );
      }
      final recordsReady = patch.state == 'READY' && artifact.state == 'READY';
      final safeQuarantine =
          patch.state == 'QUARANTINED' && artifact.state == 'QUARANTINED';
      final safeArtifactPartial =
          patch.state == 'QUARANTINED' && artifact.state == 'READY';
      final safePatchPartial =
          patch.state == 'READY' && artifact.state == 'QUARANTINED';
      final safeTerminalPartial =
          patch.state == 'READY' && artifact.state == 'READY';
      if ((state == 'ADMITTED' && !recordsReady) ||
          (state == 'QUARANTINED' &&
              !(safeQuarantine ||
                  safeArtifactPartial ||
                  safePatchPartial ||
                  safeTerminalPartial))) {
        throw const FormatException(
          'Bundle import state does not match destination records',
        );
      }
      return ReleaseBundleImportResult(
        source: source,
        bundleDigest: bundleDigest,
        destinationEnvironmentId: environmentId,
        release: release,
        patch: patch,
        artifact: artifact,
        importState: state,
        idempotentReplay: idempotentReplay,
      );
    } on ControlPlaneException {
      rethrow;
    } on Object catch (error) {
      throw ControlPlaneException(
        'STORAGE_CORRUPT',
        'Bundle import provenance is malformed: $error',
        statusCode: 500,
      );
    }
  }

  String _bundleStoredString(Map<String, Object?> value, String key) {
    final item = value[key];
    if (item is! String || item.isEmpty) {
      throw const FormatException('Bundle import provenance field is invalid');
    }
    return item;
  }

  Map<String, Object?> _bundleStoredObject(
    Map<String, Object?> value,
    String key,
  ) {
    final item = value[key];
    if (item is! Map) {
      throw const FormatException('Bundle import provenance field is invalid');
    }
    return item.map<String, Object?>((key, value) => MapEntry('$key', value));
  }

  ReleaseBundlePayload _bundlePayloadFromStoredMetadata(
    Map<String, Object?> signedPayload,
    List<int> artifactBytes,
  ) => ReleaseBundlePayload.fromJson(<String, Object?>{
    ...signedPayload,
    'artifact': <String, Object?>{
      ..._bundleStoredObject(signedPayload, 'artifact'),
      'bytes': base64Encode(artifactBytes),
    },
  });

  void _validateBundleDestinationMetadata({
    required ReleaseBundlePayload sourcePayload,
    required ReleaseBundleImportResult current,
    required String organizationId,
    required String applicationId,
  }) {
    final sourceRelease = sourcePayload.release;
    final expectedRelease = ReleaseRecord(
      id: current.release.id,
      organizationId: organizationId,
      applicationId: applicationId,
      platformId: sourceRelease.platformId,
      runtimeApplicationId: sourceRelease.runtimeApplicationId,
      runtimeReleaseId: sourceRelease.runtimeReleaseId,
      buildTarget: sourceRelease.buildTarget,
      runtimeCompatibilityVersion: sourceRelease.runtimeCompatibilityVersion,
      patchFormatVersion: sourceRelease.patchFormatVersion,
      buildFingerprint: sourceRelease.buildFingerprint,
      capabilityAuthorityDigest: sourceRelease.capabilityAuthorityDigest,
      functionSignatureDigest: sourceRelease.functionSignatureDigest,
      displayVersion: sourceRelease.displayVersion,
      signingPublicKeys: sourceRelease.signingPublicKeys,
      createdAt: sourceRelease.createdAt,
    );
    if (canonicalJson(current.release.toJson()) !=
        canonicalJson(expectedRelease.toJson())) {
      throw const FormatException(
        'Destination release metadata does not match the signed source',
      );
    }

    final patchState = current.patch.state;
    final artifactState = current.artifact.state;
    if (!(patchState == 'QUARANTINED' || patchState == 'READY') ||
        !(artifactState == 'QUARANTINED' || artifactState == 'READY')) {
      throw const FormatException('Destination bundle record state is invalid');
    }
    final sourcePatch = sourcePayload.patch;
    final expectedPatch = PatchRecord(
      id: current.patch.id,
      organizationId: organizationId,
      releaseId: current.release.id,
      runtimePatchId: sourcePatch.runtimePatchId,
      sequence: sourcePatch.sequence,
      artifactId: current.artifact.id,
      sha256: sourcePatch.sha256,
      sizeBytes: sourcePatch.sizeBytes,
      signatureKeyId: sourcePatch.signatureKeyId,
      state: patchState,
      createdAt: sourcePatch.createdAt,
    );
    if (!_sameBundleRecordExceptState(
      current.patch.toJson(),
      expectedPatch.toJson(),
    )) {
      throw const FormatException(
        'Destination patch metadata does not match the signed source',
      );
    }

    final sourceArtifact = sourcePayload.artifact;
    final expectedArtifact = ArtifactRecord(
      id: current.artifact.id,
      organizationId: organizationId,
      patchId: current.patch.id,
      sha256: sourceArtifact.sha256,
      sizeBytes: sourceArtifact.sizeBytes,
      contentType: sourceArtifact.contentType,
      state: artifactState,
      createdAt: sourceArtifact.createdAt,
    );
    if (!_sameBundleRecordExceptState(
      current.artifact.toJson(),
      expectedArtifact.toJson(),
    )) {
      throw const FormatException(
        'Destination artifact metadata does not match the signed source',
      );
    }
  }

  bool _sameBundleRecordExceptState(
    Map<String, Object?> actual,
    Map<String, Object?> expected,
  ) {
    final actualMetadata = Map<String, Object?>.from(actual)..remove('state');
    final expectedMetadata = Map<String, Object?>.from(expected)
      ..remove('state');
    return canonicalJson(actualMetadata) == canonicalJson(expectedMetadata);
  }

  Future<ApplicationRecord> _application(String id) async {
    final value = await store.readJson('applications', id);
    if (value == null)
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    return ApplicationRecord.fromJson(value);
  }

  Future<EnvironmentRecord> _environment(String id) async {
    final value = await store.readJson('environments', id);
    if (value == null)
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    return EnvironmentRecord.fromJson(value);
  }

  Future<ReleaseRecord> _release(String id) async {
    final value = await store.readJson('releases', id);
    if (value == null)
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    return ReleaseRecord.fromJson(value);
  }

  Future<PatchRecord> _patch(String id) async {
    final value = await store.readJson('patches', id);
    if (value == null)
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    return PatchRecord.fromJson(value);
  }

  Future<ArtifactRecord> _artifact(String id) async {
    final value = await store.readJson('artifacts', id);
    if (value == null)
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    return ArtifactRecord.fromJson(value);
  }

  Future<Map<String, Object?>?> _existingIdempotency(
    String scope,
    String key,
    Map<String, Object?> body,
  ) async {
    _validateIdempotencyKey(key);
    final existing = await store.readIdempotency(scope, key);
    if (existing == null) return null;
    if (existing['requestDigest'] !=
        sha256Digest(utf8.encode(canonicalJson(body)))) {
      throw const ControlPlaneException(
        'IDEMPOTENCY_KEY_REUSED',
        'Idempotency key was already used for a different request',
        statusCode: 409,
      );
    }
    final result = existing['result'];
    if (result is! Map<String, Object?>) {
      throw const ControlPlaneException(
        'STORAGE_CORRUPT',
        'Idempotency record is malformed',
        statusCode: 500,
      );
    }
    return result;
  }

  Future<void> _saveIdempotency(
    String scope,
    String key,
    Map<String, Object?> body,
    Map<String, Object?> result,
  ) async {
    await store.createIdempotency(scope, key, <String, Object?>{
      'requestDigest': sha256Digest(utf8.encode(canonicalJson(body))),
      'result': result,
      'createdAt': _now().toIso8601String(),
    });
  }

  Future<void> _audit({
    required String requestId,
    required CredentialRecord actor,
    required String action,
    required String resourceType,
    required String resourceId,
    required Map<String, Object?> metadata,
  }) async {
    final record = _buildAudit(
      requestId: requestId,
      actor: actor,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      metadata: metadata,
    );
    await store.appendAudit(record.id, record.toJson());
  }

  AuditRecord _buildAudit({
    required String requestId,
    required CredentialRecord actor,
    required String action,
    required String resourceType,
    required String resourceId,
    required Map<String, Object?> metadata,
  }) {
    final safeMetadata = <String, Object?>{
      for (final entry in metadata.entries)
        if (!entry.key.toLowerCase().contains('token') &&
            !entry.key.toLowerCase().contains('private') &&
            !entry.key.toLowerCase().contains('secret'))
          entry.key: entry.value,
    };
    return AuditRecord(
      id: _id('aud'),
      requestId: requestId,
      organizationId: actor.organizationId,
      actorId: actor.id,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      result: 'SUCCESS',
      metadata: safeMetadata,
      createdAt: _now(),
    );
  }

  Future<void> _markQuarantined(ArtifactRecord artifact) async {
    if (artifact.state == 'QUARANTINED') return;
    await store.replaceJson(
      'artifacts',
      artifact.id,
      artifact.copyWith(state: 'QUARANTINED').toJson(),
    );
  }

  void _validateReleaseSpec(ReleaseSpec spec) {
    if (spec.patchFormatVersion != patchFormatV1 ||
        spec.runtimeCompatibilityVersion <= 0) {
      throw const ControlPlaneException(
        'UNSUPPORTED_COMPATIBILITY',
        'Release format/runtime compatibility is unsupported',
        statusCode: 409,
      );
    }
    requireOpaqueId(spec.applicationId, 'application ID');
    requireOpaqueId(spec.platformId, 'platform ID');
    requireRuntimeIdentity(spec.runtimeApplicationId, 'runtime application ID');
    requireRuntimeIdentity(spec.runtimeReleaseId, 'runtime release ID');
    requireSha256Digest(spec.buildFingerprint);
    requireSha256Digest(spec.capabilityAuthorityDigest);
    requireSha256Digest(spec.functionSignatureDigest);
    if (spec.signingPublicKeys.isEmpty) {
      throw const ControlPlaneException(
        'MISSING_TRUST_KEY',
        'Release must register at least one public signing key',
        statusCode: 409,
      );
    }
    for (final entry in spec.signingPublicKeys.entries) {
      requireNonEmpty(entry.key, 'signing key ID');
      try {
        if (base64.decode(entry.value).length != 32)
          throw const FormatException();
      } on FormatException {
        throw const ControlPlaneException(
          'INVALID_TRUST_KEY',
          'Release public signing keys must be base64 Ed25519 keys',
          statusCode: 409,
        );
      }
    }
  }

  void _validatePatchSpec(PatchSpec spec) {
    requireRuntimeIdentity(spec.runtimePatchId, 'runtime patch ID');
    requireOpaqueId(spec.artifactId, 'artifact ID');
    requireSha256Digest(spec.sha256);
    requireNonEmpty(spec.signatureKeyId, 'signature key ID');
    if (spec.sequence <= 0 ||
        spec.sizeBytes <= 0 ||
        spec.sizeBytes > PatchFormatLimits.maxArtifactBytes) {
      throw const ControlPlaneException(
        'INVALID_PATCH_METADATA',
        'Patch sequence or size is outside the supported bounds',
        statusCode: 409,
      );
    }
  }

  void _requireTenant(String actual, String expected) {
    if (actual != expected) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
  }

  void _validateIdempotencyKey(String key) {
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,200}$').hasMatch(key)) {
      throw const ControlPlaneException(
        'INVALID_IDEMPOTENCY_KEY',
        'Idempotency key is invalid',
      );
    }
  }

  bool _auditWithinRetention(Object? value, DateTime cutoff) {
    if (value is! String) {
      throw const ControlPlaneException(
        'AUDIT_INVALID_TIMESTAMP',
        'Audit record timestamp is invalid',
        statusCode: 500,
      );
    }
    final timestamp = DateTime.tryParse(value)?.toUtc();
    if (timestamp == null) {
      throw const ControlPlaneException(
        'AUDIT_INVALID_TIMESTAMP',
        'Audit record timestamp is invalid',
        statusCode: 500,
      );
    }
    return !timestamp.isBefore(cutoff);
  }

  DateTime _now() => _clock().toUtc();

  String _id(String prefix) {
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return '$prefix${bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';
  }

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _writeTail;
    final gate = Completer<void>();
    _writeTail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
