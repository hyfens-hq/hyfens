import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'encoding.dart';
import 'errors.dart';
import 'observation.dart';

abstract interface class ArtifactStore {
  Future<void> putArtifact(String digest, List<int> bytes);

  Future<List<int>?> readArtifact(String digest);
}

/// Optional physical-deletion seam for lifecycle cleanup. A false result
/// means the content-addressed object was already absent, which is a safe
/// idempotent outcome for a terminal PURGED metadata transition.
abstract interface class ArtifactDeletion {
  Future<bool> deleteArtifact(String digest);
}

/// Optional dependency probe used by hosted readiness checks.
abstract interface class ArtifactStoreReadiness {
  Future<void> checkReadiness();
}

/// Optional inventory seam used by the bounded reconciliation procedure.
/// Implementations return raw content-addressed object keys without mutating
/// metadata or regenerating signed artifacts.
abstract interface class ArtifactInventory {
  Future<Set<String>> listArtifactKeys();
}

/// Optional exact-record deletion for staged lifecycle cleanup. It is kept
/// outside [ControlPlaneStore] so decorators and focused test stores do not
/// need to implement destructive operations they do not support.
abstract interface class JsonRecordDeletion {
  Future<bool> deleteJson(String collection, String id);
}

/// Optional compare-and-set seam for one-time security tokens. A null result
/// means that the token is missing or has already been consumed.
abstract interface class OneTimeTokenConsumption {
  Future<Map<String, Object?>?> consumeOneTimeTokenIfUnused({
    required String collection,
    required String id,
    required DateTime consumedAt,
  });
}

final class ObservationWriteResult {
  const ObservationWriteResult({required this.created, required this.value});

  final bool created;
  final Map<String, Object?> value;
}

final class RolloutTransitionCommitResult {
  const RolloutTransitionCommitResult({required this.applied});

  final bool applied;
}

/// Result of the one atomic runtime-receipt settlement operation.
///
/// A receipt and its canonical usage event are committed together. Retrying a
/// previously committed receipt returns [createdReceipt] and [createdUsage]
/// as false rather than creating another usage event.
final class RuntimeReceiptCommitResult {
  const RuntimeReceiptCommitResult({
    required this.createdReceipt,
    required this.createdUsage,
  });

  final bool createdReceipt;
  final bool createdUsage;
}

/// Result of the one atomic managed-Cloud signup verification operation.
///
/// Verification creates the organization, owner account, onboarding marker,
/// and verified signup record together. A repeated verification returns
/// [created] false after comparing the existing records instead of creating a
/// second organization or account.
final class ManagedCloudOnboardingCommitResult {
  const ManagedCloudOnboardingCommitResult({required this.created});

  final bool created;
}

/// Persistence seam for managed Cloud self-service onboarding. It is kept
/// separate from [ControlPlaneStore] so existing store implementations and
/// test doubles do not acquire a new required capability merely by upgrading
/// the public control-plane package.
abstract interface class ManagedCloudOnboardingStore {
  Future<Map<String, Object?>?> readJson(String collection, String id);

  Future<void> createJson(
    String collection,
    String id,
    Map<String, Object?> value,
  );

  Future<void> replaceJson(
    String collection,
    String id,
    Map<String, Object?> value,
  );

  Future<void> appendAudit(String id, Map<String, Object?> value);

  Future<ManagedCloudOnboardingCommitResult> commitManagedCloudOnboarding({
    required String signupId,
    required Map<String, Object?> expectedSignup,
    required Map<String, Object?> verifiedSignup,
    required Map<String, Object?> organization,
    required Map<String, Object?> user,
    required Map<String, Object?> onboarding,
  });
}

/// Durable storage for the runtime trust boundary. Implementations must keep
/// registration records immutable and settle a receipt plus its canonical
/// usage event atomically.
abstract interface class RuntimeReceiptStore {
  Future<void> createRuntimeAdmission(String id, Map<String, Object?> value);

  Future<Map<String, Object?>?> readRuntimeAdmission(String id);

  Future<void> createRuntimeInstallation(String id, Map<String, Object?> value);

  Future<Map<String, Object?>?> readRuntimeInstallation(String id);

  Future<void> createRuntimeRegistration(String id, Map<String, Object?> value);

  Future<Map<String, Object?>?> readRuntimeRegistration(String id);

  Future<void> createRuntimeRejection(String id, Map<String, Object?> value);

  Future<Map<String, Object?>?> readRuntimeReceipt(String id);

  Future<RuntimeReceiptCommitResult> commitRuntimeReceipt({
    required String receiptId,
    required Map<String, Object?> receipt,
    required String usageEventId,
    required Map<String, Object?> usageEvent,
  });
}

/// Storage operations whose correctness depends on a durable unique key.
/// Implementations must compare an existing event's canonical body before
/// acknowledging a retry; they must never silently overwrite an observation.
abstract interface class ObservationStore {
  Future<ObservationWriteResult> createObservation(
    String organizationId,
    String applicationId,
    String environmentId,
    String eventId,
    Map<String, Object?> value,
  );

  Future<List<Map<String, Object?>>> listObservations({
    String? organizationId,
    String? applicationId,
    String? environmentId,
  });

  Future<int> deleteObservations({
    required String organizationId,
    String? applicationId,
    String? environmentId,
    required DateTime olderThan,
  });
}

/// Optional bounded observation cleanup used by privacy workers. Keeping this
/// separate preserves compatibility with focused decorators that only expose
/// the original observation store contract.
abstract interface class BoundedObservationDeletion {
  Future<int> deleteObservationsBatch({
    required String organizationId,
    String? applicationId,
    String? environmentId,
    required DateTime olderThan,
    required int limit,
  });
}

/// The one rollout write that must be serialized across control-plane
/// processes. PostgreSQL implements this as a transaction with a row lock;
/// the file store provides the equivalent single-node queue.
abstract interface class RolloutTransitionStore {
  Future<RolloutTransitionCommitResult> commitRolloutTransition({
    required String rolloutId,
    required int expectedRevision,
    required Map<String, Object?> rollout,
    required Map<String, Object?> revision,
    required Map<String, Object?> audit,
    required String idempotencyScope,
    required String idempotencyKey,
    required String requestDigest,
    required Map<String, Object?> idempotencyResult,
  });
}

/// Transactional record access for billing refund decisions.
///
/// Refund approval and provider-attempt claims need to reserve a captured
/// balance as one durable operation. This optional seam lets stores with a
/// transaction implementation provide that guarantee without widening the
/// general JSON store contract or making every test/decorator implement a
/// billing-specific method.
abstract interface class BillingRefundTransaction {
  Future<Map<String, Object?>?> readJson(String collection, String id);

  Future<List<Map<String, Object?>>> listJson(String collection);

  Future<void> createJson(
    String collection,
    String id,
    Map<String, Object?> value,
  );

  Future<void> replaceJson(
    String collection,
    String id,
    Map<String, Object?> value,
  );

  Future<void> appendAudit(String id, Map<String, Object?> value);
}

/// Optional durable transaction support for refund balance reservation and
/// provider-attempt idempotency. Implementations must serialize operations for
/// the supplied lock key and commit the callback atomically where supported.
abstract interface class BillingRefundTransactionStore {
  Future<T> runBillingRefundTransaction<T>(
    String lockKey,
    Future<T> Function(BillingRefundTransaction transaction) action,
  );
}

abstract interface class ControlPlaneStore
    implements ArtifactStore, ObservationStore, RolloutTransitionStore {
  Future<void> initialize();

  Future<void> close();

  Future<void> checkReadiness();

  Future<Map<String, Object?>?> readJson(String collection, String id);

  Future<List<Map<String, Object?>>> listJson(String collection);

  Future<void> createJson(
    String collection,
    String id,
    Map<String, Object?> value,
  );

  Future<void> replaceJson(
    String collection,
    String id,
    Map<String, Object?> value,
  );

  /// Replaces multiple records as one serialized metadata operation.
  ///
  /// PostgreSQL commits the replacements in one transaction. The file store
  /// serializes the operation and keeps each replacement atomic, which is the
  /// supported single-process semantics for local self-hosted storage.
  Future<void> replaceJsonBatch(
    String collection,
    Map<String, Map<String, Object?>> values,
  );

  /// Touches an active human session only when its secret hash still matches.
  ///
  /// The operation is authoritative at the persistence seam: a concurrent
  /// revocation makes it return null instead of overwriting the revoked
  /// record. The returned map is the record written by the operation.
  Future<Map<String, Object?>?> touchSessionIfActive({
    required String id,
    required String expectedSecretHash,
    required DateTime now,
  });

  /// Revokes a human session when it is still active.
  ///
  /// A false result includes a missing, mismatched, or already revoked record,
  /// making repeated logout calls idempotent.
  Future<bool> revokeSessionIfActive({
    required String id,
    required String expectedSecretHash,
    required DateTime revokedAt,
  });

  Future<void> createIdempotency(
    String scope,
    String key,
    Map<String, Object?> value,
  );

  Future<Map<String, Object?>?> readIdempotency(String scope, String key);

  Future<void> appendAudit(String id, Map<String, Object?> value);

  Future<List<Map<String, Object?>>> readAuditChain();
}

/// Single-node filesystem storage. Metadata and bytes use separate namespaces;
/// artifact paths are content addressed and never selected from a caller's
/// arbitrary filesystem path.
final class FileControlPlaneStore
    implements
        ControlPlaneStore,
        ArtifactInventory,
        ArtifactDeletion,
        JsonRecordDeletion,
        OneTimeTokenConsumption,
        BoundedObservationDeletion,
        BillingRefundTransactionStore {
  FileControlPlaneStore(this.root);

  final Directory root;
  Future<void> _sessionOperationTail = Future<void>.value();
  final Map<String, Future<void>> _billingRefundTails =
      <String, Future<void>>{};

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_.:-]{1,256}$');

  Future<void> initialize() async {
    await root.create(recursive: true);
    for (final name in const <String>[
      'organizations',
      'applications',
      'environments',
      'releases',
      'patches',
      'artifacts',
      'rollouts',
      'rollout_revisions',
      'credentials',
      'users',
      'sessions',
      'auth_verification_tokens',
      'auth_recovery_tokens',
      'auth_deletion_tokens',
      'auth_bootstrap_consumptions',
      'audit',
      'audit_chain',
      'idempotency',
      'observations',
      'waitlist',
      'newsletter',
      'billing_plan_catalog',
      'billing_plans',
      'billing_subscriptions',
      'billing_events',
      'billing_provider_mappings',
      'billing_payments',
      'billing_refund_requests',
      'billing_refund_decisions',
      'billing_provider_refunds',
      'enterprise_quotes',
      'enterprise_quote_versions',
      'enterprise_contracts',
      'enterprise_provider_mappings',
      'cloud_usage_events',
      'environment_runtime_states',
      'account_deletion_requests',
      'organization_deletion_requests',
      'deletion_artifact_items',
      'deletion_evidence',
    ]) {
      await Directory(p.join(root.path, name)).create(recursive: true);
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<T> runBillingRefundTransaction<T>(
    String lockKey,
    Future<T> Function(BillingRefundTransaction transaction) action,
  ) async {
    final previous = _billingRefundTails[lockKey] ?? Future<void>.value();
    final gate = Completer<void>();
    _billingRefundTails[lockKey] = gate.future;
    await previous;
    try {
      return await action(_FileBillingRefundTransaction(this));
    } finally {
      gate.complete();
      if (identical(_billingRefundTails[lockKey], gate.future)) {
        _billingRefundTails.remove(lockKey);
      }
    }
  }

  @override
  Future<void> checkReadiness() async {
    await listJson('__readiness_probe__');
  }

  @override
  Future<Map<String, Object?>?> readJson(String collection, String id) async {
    final file = _jsonFile(collection, id);
    if (!await file.exists()) return null;
    return decodeObject(await file.readAsString());
  }

  @override
  Future<List<Map<String, Object?>>> listJson(String collection) async {
    final directory = Directory(p.join(root.path, _safeCollection(collection)));
    if (!await directory.exists()) return const <Map<String, Object?>>[];
    final entries = await directory.list(followLinks: false).toList();
    final files = entries.whereType<File>().toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    final result = <Map<String, Object?>>[];
    for (final file in files) {
      if (!file.path.endsWith('.json')) continue;
      result.add(decodeObject(await file.readAsString()));
    }
    return List.unmodifiable(result);
  }

  @override
  Future<void> createJson(
    String collection,
    String id,
    Map<String, Object?> value,
  ) async {
    final file = _jsonFile(collection, id);
    if (await file.exists()) {
      final existing = await file.readAsString();
      final incoming = canonicalJson(value);
      if (existing == '$incoming\n' || existing == incoming) return;
      throw const StorageConflict('Immutable record already exists');
    }
    await _writeAtomic(file, utf8.encode('${canonicalJson(value)}\n'));
  }

  @override
  Future<void> createRuntimeAdmission(String id, Map<String, Object?> value) =>
      _metadataOperation(() => createJson('runtime_admissions', id, value));

  @override
  Future<Map<String, Object?>?> readRuntimeAdmission(String id) =>
      readJson('runtime_admissions', id);

  @override
  Future<void> createRuntimeInstallation(
    String id,
    Map<String, Object?> value,
  ) => _metadataOperation(() => createJson('runtime_installations', id, value));

  @override
  Future<Map<String, Object?>?> readRuntimeInstallation(String id) =>
      readJson('runtime_installations', id);

  @override
  Future<void> createRuntimeRegistration(
    String id,
    Map<String, Object?> value,
  ) => _metadataOperation(() => createJson('runtime_registrations', id, value));

  @override
  Future<Map<String, Object?>?> readRuntimeRegistration(String id) =>
      readJson('runtime_registrations', id);

  @override
  Future<void> createRuntimeRejection(String id, Map<String, Object?> value) =>
      _metadataOperation(() => createJson('runtime_rejections', id, value));

  @override
  Future<ManagedCloudOnboardingCommitResult> commitManagedCloudOnboarding({
    required String signupId,
    required Map<String, Object?> expectedSignup,
    required Map<String, Object?> verifiedSignup,
    required Map<String, Object?> organization,
    required Map<String, Object?> user,
    required Map<String, Object?> onboarding,
  }) => _metadataOperation(() async {
    final current = await readJson('cloud_signups', signupId);
    if (current == null) {
      throw const StorageConflict('Cloud signup does not exist');
    }
    if (canonicalJson(current) == canonicalJson(verifiedSignup)) {
      await _verifyManagedCloudRecord('organizations', organization);
      await _verifyManagedCloudRecord('users', user);
      await _verifyManagedCloudRecord('cloud_onboarding', onboarding);
      return const ManagedCloudOnboardingCommitResult(created: false);
    }
    if (canonicalJson(current) != canonicalJson(expectedSignup)) {
      throw const StorageConflict('Cloud signup changed during verification');
    }
    await _createManagedCloudRecord('organizations', organization);
    await _createManagedCloudRecord('users', user);
    await _createManagedCloudRecord('cloud_onboarding', onboarding);
    await replaceJson('cloud_signups', signupId, verifiedSignup);
    return const ManagedCloudOnboardingCommitResult(created: true);
  });

  Future<void> _createManagedCloudRecord(
    String collection,
    Map<String, Object?> value,
  ) async {
    final id = value['id'];
    if (id is! String) {
      throw const StorageConflict('Managed Cloud record has no ID');
    }
    await createJson(collection, id, value);
  }

  Future<void> _verifyManagedCloudRecord(
    String collection,
    Map<String, Object?> value,
  ) async {
    final id = value['id'];
    if (id is! String) {
      throw const StorageConflict('Managed Cloud record has no ID');
    }
    final current = await readJson(collection, id);
    if (current == null || canonicalJson(current) != canonicalJson(value)) {
      throw const StorageConflict(
        'Managed Cloud onboarding record is incomplete',
      );
    }
  }

  @override
  Future<Map<String, Object?>?> readRuntimeReceipt(String id) =>
      readJson('runtime_receipts', id);

  @override
  Future<RuntimeReceiptCommitResult> commitRuntimeReceipt({
    required String receiptId,
    required Map<String, Object?> receipt,
    required String usageEventId,
    required Map<String, Object?> usageEvent,
  }) => _metadataOperation(() async {
    final existingReceipt = await readJson('runtime_receipts', receiptId);
    if (existingReceipt != null) {
      if (canonicalJson(existingReceipt) != canonicalJson(receipt)) {
        throw const StorageConflict('Runtime receipt ID was reused');
      }
      final existingUsage = await readJson(
        'runtime_usage_events',
        usageEventId,
      );
      if (existingUsage == null) {
        throw const StorageConflict(
          'Runtime receipt exists without its usage event',
        );
      }
      return const RuntimeReceiptCommitResult(
        createdReceipt: false,
        createdUsage: false,
      );
    }
    final existingUsage = await readJson('runtime_usage_events', usageEventId);
    if (existingUsage != null) {
      throw const StorageConflict('Runtime usage key was already settled');
    }
    await createJson('runtime_receipts', receiptId, receipt);
    await createJson('runtime_usage_events', usageEventId, usageEvent);
    return const RuntimeReceiptCommitResult(
      createdReceipt: true,
      createdUsage: true,
    );
  });

  @override
  Future<void> replaceJson(
    String collection,
    String id,
    Map<String, Object?> value,
  ) async {
    final file = _jsonFile(collection, id);
    if (!await file.exists())
      throw const StorageConflict('Record does not exist');
    await _writeAtomic(file, utf8.encode('${canonicalJson(value)}\n'));
  }

  @override
  Future<bool> deleteJson(String collection, String id) async {
    final file = _jsonFile(collection, id);
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  @override
  Future<Map<String, Object?>?> consumeOneTimeTokenIfUnused({
    required String collection,
    required String id,
    required DateTime consumedAt,
  }) => _sessionOperation(() async {
    final current = await readJson(collection, id);
    if (current == null || current['consumedAt'] != null) return null;
    final updated = <String, Object?>{
      ...current,
      'consumedAt': consumedAt.toUtc().toIso8601String(),
    };
    await replaceJson(collection, id, updated);
    return updated;
  });

  @override
  Future<Map<String, Object?>?> touchSessionIfActive({
    required String id,
    required String expectedSecretHash,
    required DateTime now,
  }) => _sessionOperation(() async {
    final current = await readJson('sessions', id);
    if (current == null ||
        current['secretHash'] != expectedSecretHash ||
        current['revokedAt'] != null) {
      return null;
    }
    final expiresAt = current['expiresAt'];
    final expires = expiresAt is String
        ? DateTime.tryParse(expiresAt)?.toUtc()
        : null;
    final normalizedNow = now.toUtc();
    if (expires == null || !expires.isAfter(normalizedNow)) return null;
    final updated = <String, Object?>{
      ...current,
      'lastUsedAt': normalizedNow.toIso8601String(),
    };
    await replaceJson('sessions', id, updated);
    return updated;
  });

  @override
  Future<bool> revokeSessionIfActive({
    required String id,
    required String expectedSecretHash,
    required DateTime revokedAt,
  }) => _sessionOperation(() async {
    final current = await readJson('sessions', id);
    if (current == null ||
        current['secretHash'] != expectedSecretHash ||
        current['revokedAt'] != null) {
      return false;
    }
    final updated = <String, Object?>{
      ...current,
      'revokedAt': revokedAt.toUtc().toIso8601String(),
    };
    await replaceJson('sessions', id, updated);
    return true;
  });

  @override
  Future<void> putArtifact(String digest, List<int> bytes) async {
    final normalized = requireSha256Digest(digest);
    final hex = normalized.substring(7);
    final actual = sha256Digest(bytes);
    if (actual != normalized) throw StorageDigestMismatch(normalized, actual);
    final file = File(p.join(root.path, 'artifacts', hex, 'bytes'));
    if (await file.exists()) {
      final existing = await file.readAsBytes();
      if (_sameBytes(existing, bytes)) return;
      throw const StorageConflict('Content-addressed artifact was changed');
    }
    await _writeAtomic(file, bytes);
  }

  @override
  Future<Set<String>> listArtifactKeys() async {
    final directory = Directory(p.join(root.path, 'artifacts'));
    if (!await directory.exists()) return const <String>{};
    final entries = await directory.list(followLinks: false).toList();
    final keys = <String>{};
    for (final entry in entries.whereType<Directory>()) {
      final name = p.basename(entry.path);
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(name) &&
          await File(p.join(entry.path, 'bytes')).exists()) {
        keys.add(name);
      }
    }
    return Set.unmodifiable(keys);
  }

  @override
  Future<List<int>?> readArtifact(String digest) async {
    final normalized = requireSha256Digest(digest);
    final file = File(
      p.join(root.path, 'artifacts', normalized.substring(7), 'bytes'),
    );
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<bool> deleteArtifact(String digest) async {
    final normalized = requireSha256Digest(digest);
    final file = File(
      p.join(root.path, 'artifacts', normalized.substring(7), 'bytes'),
    );
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  @override
  Future<void> createIdempotency(
    String scope,
    String key,
    Map<String, Object?> value,
  ) => createJson('idempotency', _idempotencyId(scope, key), value);

  @override
  Future<Map<String, Object?>?> readIdempotency(String scope, String key) =>
      readJson('idempotency', _idempotencyId(scope, key));

  @override
  Future<void> appendAudit(String id, Map<String, Object?> value) =>
      _appendAudit(id, value);

  @override
  Future<List<Map<String, Object?>>> readAuditChain() =>
      listJson('audit_chain');

  @override
  Future<ObservationWriteResult> createObservation(
    String organizationId,
    String applicationId,
    String environmentId,
    String eventId,
    Map<String, Object?> value,
  ) async {
    final id = observationStorageId(
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
      eventId: eventId,
    );
    final existing = await readJson('observations', id);
    if (existing != null) {
      return ObservationWriteResult(created: false, value: existing);
    }
    await createJson('observations', id, value);
    return ObservationWriteResult(created: true, value: value);
  }

  @override
  Future<List<Map<String, Object?>>> listObservations({
    String? organizationId,
    String? applicationId,
    String? environmentId,
  }) async {
    final values = await listJson('observations');
    return List.unmodifiable(
      values.where((value) {
        final event = value['event'];
        if (event is! Map) return false;
        return (organizationId == null ||
                event['organizationId'] == organizationId) &&
            (applicationId == null ||
                event['applicationId'] == applicationId) &&
            (environmentId == null || event['environmentId'] == environmentId);
      }),
    );
  }

  @override
  Future<int> deleteObservations({
    required String organizationId,
    String? applicationId,
    String? environmentId,
    required DateTime olderThan,
  }) => _deleteObservations(
    organizationId: organizationId,
    applicationId: applicationId,
    environmentId: environmentId,
    olderThan: olderThan,
  );

  @override
  Future<int> deleteObservationsBatch({
    required String organizationId,
    String? applicationId,
    String? environmentId,
    required DateTime olderThan,
    required int limit,
  }) {
    if (limit < 1) return Future<int>.value(0);
    return _deleteObservations(
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
      olderThan: olderThan,
      limit: limit,
    );
  }

  Future<int> _deleteObservations({
    required String organizationId,
    String? applicationId,
    String? environmentId,
    required DateTime olderThan,
    int? limit,
  }) async {
    final directory = Directory(p.join(root.path, 'observations'));
    if (!await directory.exists()) return 0;
    var deleted = 0;
    final entries = await directory.list(followLinks: false).toList();
    for (final entry in entries.whereType<File>()) {
      if (!entry.path.endsWith('.json')) continue;
      final value = decodeObject(await entry.readAsString());
      final event = value['event'];
      final receivedAt = value['receivedAt'];
      if (event is! Map || receivedAt is! String) continue;
      if (event['organizationId'] != organizationId ||
          (applicationId != null && event['applicationId'] != applicationId) ||
          (environmentId != null && event['environmentId'] != environmentId)) {
        continue;
      }
      final received = DateTime.tryParse(receivedAt);
      if (received == null || !received.isBefore(olderThan.toUtc())) continue;
      await entry.delete();
      deleted++;
      if (limit != null && deleted >= limit) break;
    }
    return deleted;
  }

  Future<void> _commitRolloutTransitionFile({
    required String rolloutId,
    required int expectedRevision,
    required Map<String, Object?> rollout,
    required Map<String, Object?> revision,
    required Map<String, Object?> audit,
    required String idempotencyScope,
    required String idempotencyKey,
    required String requestDigest,
    required Map<String, Object?> idempotencyResult,
  }) async {
    final existing = await readIdempotency(idempotencyScope, idempotencyKey);
    if (existing != null) {
      if (existing['requestDigest'] != requestDigest) {
        throw const StorageIdempotencyConflict(
          'Idempotency key was already used for a different request',
        );
      }
      return;
    }
    final current = await readJson('rollouts', rolloutId);
    if (current == null) throw const StorageConflict('Rollout does not exist');
    final currentRevision = current['currentRevision'];
    if (currentRevision is! int || currentRevision != expectedRevision) {
      throw StoragePreconditionFailed(
        'Rollout revision is stale',
        currentRevision: currentRevision is int ? currentRevision : -1,
      );
    }
    await createJson('rollout_revisions', revision['id']! as String, revision);
    await replaceJson('rollouts', rolloutId, rollout);
    await createIdempotency(idempotencyScope, idempotencyKey, <String, Object?>{
      'requestDigest': requestDigest,
      'result': idempotencyResult,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });

    await appendAudit(audit['id']! as String, audit);
  }

  Future<void> _rolloutTransitionTail = Future<void>.value();

  @override
  Future<RolloutTransitionCommitResult> commitRolloutTransition({
    required String rolloutId,
    required int expectedRevision,
    required Map<String, Object?> rollout,
    required Map<String, Object?> revision,
    required Map<String, Object?> audit,
    required String idempotencyScope,
    required String idempotencyKey,
    required String requestDigest,
    required Map<String, Object?> idempotencyResult,
  }) {
    final completer = _rolloutTransitionTail.then((_) async {
      final before = await readIdempotency(idempotencyScope, idempotencyKey);
      if (before != null && before['requestDigest'] == requestDigest) {
        return const RolloutTransitionCommitResult(applied: false);
      }
      await _commitRolloutTransitionFile(
        rolloutId: rolloutId,
        expectedRevision: expectedRevision,
        rollout: rollout,
        revision: revision,
        audit: audit,
        idempotencyScope: idempotencyScope,
        idempotencyKey: idempotencyKey,
        requestDigest: requestDigest,
        idempotencyResult: idempotencyResult,
      );
      return const RolloutTransitionCommitResult(applied: true);
    });
    _rolloutTransitionTail = completer.then<void>((_) {}).catchError((_) {});
    return completer;
  }

  Future<void> _appendAudit(String id, Map<String, Object?> value) async {
    final chain = (await listJson('audit_chain')).toList();
    chain.sort(
      (left, right) =>
          (left['sequence']! as int).compareTo(right['sequence']! as int),
    );
    final previous = chain.isEmpty
        ? null
        : chain.last['recordDigest'] as String?;
    final recordDigest = sha256Digest(utf8.encode(canonicalJson(value)));
    await createJson('audit_chain', id, <String, Object?>{
      'sequence': chain.length + 1,
      'auditId': id,
      'organizationId': value['organizationId'],
      'previousDigest': previous,
      'recordDigest': recordDigest,
      'body': value,
    });
    await createJson('audit', id, value);
  }

  Future<T> _sessionOperation<T>(Future<T> Function() action) {
    final result = _sessionOperationTail.then((_) => action());
    _sessionOperationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<T> _metadataOperation<T>(Future<T> Function() action) {
    final result = _metadataOperationTail.then((_) => action());
    _metadataOperationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> _metadataOperationTail = Future<void>.value();

  File _jsonFile(String collection, String id) =>
      File(p.join(root.path, _safeCollection(collection), '${_safe(id)}.json'));

  String _safeCollection(String value) {
    if (!_safeId.hasMatch(value) || value.contains('..')) {
      throw const FormatException('Invalid storage collection');
    }
    return value;
  }

  String _safe(String value) {
    if (!_safeId.hasMatch(value) || value.contains('..')) {
      throw const FormatException('Invalid storage identifier');
    }
    return value;
  }

  String _idempotencyId(String scope, String key) =>
      '${sha256Hex(utf8.encode(scope))}-${sha256Hex(utf8.encode(key))}';

  Future<void> _writeAtomic(File destination, List<int> bytes) async {
    await destination.parent.create(recursive: true);
    final temporary = File(
      '${destination.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
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

final class _FileBillingRefundTransaction implements BillingRefundTransaction {
  const _FileBillingRefundTransaction(this.store);

  final FileControlPlaneStore store;

  @override
  Future<Map<String, Object?>?> readJson(String collection, String id) =>
      store.readJson(collection, id);

  @override
  Future<List<Map<String, Object?>>> listJson(String collection) =>
      store.listJson(collection);

  @override
  Future<void> createJson(
    String collection,
    String id,
    Map<String, Object?> value,
  ) => store.createJson(collection, id, value);

  @override
  Future<void> replaceJson(
    String collection,
    String id,
    Map<String, Object?> value,
  ) => store.replaceJson(collection, id, value);

  @override
  Future<void> appendAudit(String id, Map<String, Object?> value) =>
      store.appendAudit(id, value);
}
