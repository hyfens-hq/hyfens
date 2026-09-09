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

/// Optional compare-and-set support for privacy lifecycle records.
///
/// A deletion worker and a cancellation request may run at the same time. A
/// store implementing this seam must only write [value] when the durable
/// request still has [expectedStatus]. Returning false means another actor
/// won the transition and the caller must re-read the request.
abstract interface class DeletionRequestStateStore {
  Future<bool> compareAndSetDeletionRequestStatus({
    required String collection,
    required String id,
    required String expectedStatus,
    required Map<String, Object?> value,
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

/// Optional durable claim/compare-and-set support for notification delivery.
///
/// A worker must claim a delivery before calling an external provider. The
/// lease lets another worker recover a process that stopped while the provider
/// call was in flight, while the claim check prevents that stale worker from
/// overwriting the newer worker's result. Stores without this seam retain the
/// single-process dispatcher fallback.
abstract interface class NotificationDeliveryClaimStore {
  Future<Map<String, Object?>?> claimNotificationDelivery({
    required String deliveryId,
    required DateTime now,
    required DateTime leaseUntil,
    required String claimId,
  });

  Future<bool> updateClaimedNotificationDelivery({
    required String deliveryId,
    required String claimId,
    required Map<String, Object?> value,
  });
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
        DeletionRequestStateStore,
        BoundedObservationDeletion,
        BillingRefundTransactionStore,
        NotificationDeliveryClaimStore {
  FileControlPlaneStore(this.root);

  final Directory root;
  Future<void> _sessionOperationTail = Future<void>.value();
  Future<void> _notificationOperationTail = Future<void>.value();
  Future<void> _deletionOperationTail = Future<void>.value();
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
      'auth_deletion_cancel_tokens',
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
      'notification_events',
      'notification_deliveries',
    ]) {
      await Directory(p.join(root.path, name)).create(recursive: true);
    }
  }

  @override
  Future<bool> compareAndSetDeletionRequestStatus({
    required String collection,
    required String id,
    required String expectedStatus,
    required Map<String, Object?> value,
  }) {
    final result = _deletionOperationTail.then((_) async {
      final current = await readJson(collection, id);
      if (current == null || current['status'] != expectedStatus) return false;
      await replaceJson(collection, id, value);
      return true;
    });
    _deletionOperationTail = result.then<void>((_) {}).catchError((_) {});
    return result;
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
  Future<Map<String, Object?>?> claimNotificationDelivery({
    required String deliveryId,
    required DateTime now,
    required DateTime leaseUntil,
    required String claimId,
  }) => _notificationOperation(() async {
    const collection = 'notification_deliveries';
    final current = await readJson(collection, deliveryId);
    if (current == null || !_notificationClaimIsEligible(current, now)) {
      return null;
    }
    final updated = <String, Object?>{
      ...current,
      'state': 'processing',
      'attempts': (current['attempts'] as int? ?? 0) + 1,
      'claimId': claimId,
      'processingAt': now.toUtc().toIso8601String(),
      'processingLeaseUntil': leaseUntil.toUtc().toIso8601String(),
    };
    await replaceJson(collection, deliveryId, updated);
    return updated;
  });

  @override
  Future<bool> updateClaimedNotificationDelivery({
    required String deliveryId,
    required String claimId,
    required Map<String, Object?> value,
  }) => _notificationOperation(() async {
    const collection = 'notification_deliveries';
    final current = await readJson(collection, deliveryId);
    if (current == null || current['claimId'] != claimId) return false;
    await replaceJson(collection, deliveryId, value);
    return true;
  });

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

  Future<T> _notificationOperation<T>(Future<T> Function() action) {
    final result = _notificationOperationTail.then((_) => action());
    _notificationOperationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  bool _notificationClaimIsEligible(
    Map<String, Object?> delivery,
    DateTime now,
  ) {
    final state = delivery['state'];
    if (state == 'pending' || state == 'soft_failed') {
      final nextAttemptAt = delivery['nextAttemptAt'];
      final next = nextAttemptAt is String
          ? DateTime.tryParse(nextAttemptAt)
          : null;
      return next == null || !next.isAfter(now.toUtc());
    }
    if (state != 'processing') return false;
    final lease = delivery['processingLeaseUntil'];
    final leaseUntil = lease is String ? DateTime.tryParse(lease) : null;
    return leaseUntil == null || !leaseUntil.isAfter(now.toUtc());
  }

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
