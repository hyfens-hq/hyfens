import 'dart:async';
import 'dart:convert';

import 'artifact_retention.dart';
import 'billing.dart';
import 'cloud_plans.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'persistence.dart';

const String accountDeletionRequestCollection = 'account_deletion_requests';
const String organizationDeletionRequestCollection =
    'organization_deletion_requests';

/// The product deliberately does not invent legal retention durations. A
/// deployment supplies a reviewed grace period through configuration before
/// deletion workers may process verified requests.
final class DeletionPolicy {
  const DeletionPolicy({this.gracePeriod});

  final Duration? gracePeriod;

  bool get isConfigured => gracePeriod != null;

  static DeletionPolicy fromEnvironment(Map<String, String> values) {
    final raw = values['HYFENS_DELETION_GRACE_PERIOD']?.trim();
    if (raw == null || raw.isEmpty) return const DeletionPolicy();
    final match = RegExp(r'^([1-9][0-9]*)(s|m|h|d)$').firstMatch(raw);
    if (match == null) {
      throw ArgumentError(
        'HYFENS_DELETION_GRACE_PERIOD must use a duration such as 30d',
      );
    }
    final amount = int.parse(match.group(1)!);
    final duration = switch (match.group(2)) {
      's' => Duration(seconds: amount),
      'm' => Duration(minutes: amount),
      'h' => Duration(hours: amount),
      'd' => Duration(days: amount),
      _ => throw ArgumentError(
        'HYFENS_DELETION_GRACE_PERIOD has an unsupported unit',
      ),
    };
    if (duration > const Duration(days: 365)) {
      throw ArgumentError(
        'HYFENS_DELETION_GRACE_PERIOD must not exceed 365 days',
      );
    }
    return DeletionPolicy(gracePeriod: duration);
  }
}

/// Product data is not handled by a blind cascade. These classifications are
/// the durable implementation contract; legal durations remain deployment
/// and policy decisions rather than hidden constants in the worker.
const Map<String, String> deletionRetentionClassification = <String, String>{
  'user_profile': 'erase',
  'email': 'erase',
  'authentication_credentials': 'erase',
  'sessions': 'erase',
  'memberships': 'erase',
  'verification_and_recovery_tokens': 'temporary_retain',
  'deletion_tokens': 'temporary_retain',
  'applications': 'erase',
  'environments': 'erase',
  'organization_content': 'erase',
  'artifact_bytes': 'temporary_retain',
  'usage_events': 'erase',
  'release_patch_security_metadata': 'anonymize',
  'deployment_and_rollback_evidence': 'anonymize',
  'audit_chain': 'retain',
  'billing_and_refund_evidence': 'retain',
  'enterprise_commercial_evidence': 'retain',
  'security_and_abuse_events': 'retain',
  'backups_and_snapshots': 'temporary_retain',
};

const Set<String> _openDeletionStatuses = <String>{
  'policy_decision_required',
  'ownership_resolution_required',
  'billing_pending',
  'grace_period',
  'processing',
  'failed',
};

const Set<String> _terminalDeletionStatuses = <String>{
  'completed',
  'cancelled',
};

const List<String> _organizationOwnedCollections = <String>[
  'applications',
  'environments',
  'releases',
  'patches',
  'artifacts',
  'rollouts',
  'rollout_revisions',
  'bundle_imports',
  'environment_runtime_states',
  'cloud_usage_events',
  'credentials',
];

/// Account and organization privacy transitions share a durable request record
/// and a bounded worker, but deliberately have different ownership effects.
final class AccountDeletionService {
  AccountDeletionService({
    required this.store,
    this.humanAuth,
    required this.billing,
    required this.deploymentModel,
    this.policy = const DeletionPolicy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()) {
    final gracePeriod = policy.gracePeriod;
    if (gracePeriod != null &&
        (gracePeriod <= Duration.zero ||
            gracePeriod > const Duration(days: 365))) {
      throw ArgumentError(
        'Deletion grace period must be greater than zero and no more than 365 days',
      );
    }
  }

  final ControlPlaneStore store;
  final HumanAuthService? humanAuth;
  final BillingService billing;
  final DeploymentModel deploymentModel;
  final DeletionPolicy policy;
  final DateTime Function() _clock;
  Future<void> _writeTail = Future<void>.value();

  Future<Map<String, Object?>> requestAccountDeletion({
    required String userId,
    required String actorId,
    required String requestId,
    String source = 'authenticated',
  }) => _serialized(() async {
    final id = _accountRequestId(userId);
    final existing = await store.readJson(accountDeletionRequestCollection, id);
    if (existing != null &&
        (_terminalDeletionStatuses.contains(existing['status']) ||
            existing['status'] == 'grace_period' ||
            existing['status'] == 'processing' ||
            existing['status'] == 'failed')) {
      return existing;
    }
    final user = await _activeVerifiedUser(userId);
    final ownership = await _soleOwnedOrganizations(user);
    final accountRequestId = _accountRequestId(user.id);
    final now = _now();
    final requiredOwnership = ownership.toList(growable: false);
    final request = <String, Object?>{
      'id': accountRequestId,
      'scope': 'account',
      'userId': user.id,
      'requestedBy': actorId,
      'source': source,
      'status': requiredOwnership.isNotEmpty
          ? 'ownership_resolution_required'
          : _verifiedStatus(),
      'stage': requiredOwnership.isNotEmpty ? 'ownership' : 'grace_period',
      'requestedAt': existing?['requestedAt'] ?? now.toIso8601String(),
      'verifiedAt': existing?['verifiedAt'] ?? now.toIso8601String(),
      'gracePeriodEndsAt': existing?['gracePeriodEndsAt'] ?? _graceEndsAt(now),
      'ownershipRequiredOrganizations': requiredOwnership,
      'updatedAt': now.toIso8601String(),
      'attempt': existing?['attempt'] ?? 0,
      if (existing?['createdAt'] != null) 'createdAt': existing!['createdAt'],
      if (existing?['createdAt'] == null) 'createdAt': now.toIso8601String(),
    };
    await _createOrReplaceRequest(
      accountDeletionRequestCollection,
      accountRequestId,
      request,
      existing,
    );
    final auditOrganizationId = _auditOrganization(user);
    if (source == 'email_verification') {
      await _audit(
        requestId: requestId,
        organizationId: auditOrganizationId,
        actorId: actorId,
        action: 'account.deletion.verified',
        resourceType: 'account_deletion_request',
        resourceId: accountRequestId,
        metadata: <String, Object?>{
          'source': source,
          'ownership_required_count': requiredOwnership.length,
        },
      );
    }
    await _audit(
      requestId: requestId,
      organizationId: auditOrganizationId,
      actorId: actorId,
      action: requiredOwnership.isNotEmpty
          ? 'account.deletion.ownership_resolution_required'
          : 'account.deletion.requested',
      resourceType: 'account_deletion_request',
      resourceId: accountRequestId,
      metadata: <String, Object?>{
        'source': source,
        'ownership_required_count': requiredOwnership.length,
        'status': request['status'],
      },
    );
    return request;
  });

  Future<Map<String, Object?>> verifyAccountDeletionToken({
    required String userId,
    required String actorId,
    required String requestId,
  }) => requestAccountDeletion(
    userId: userId,
    actorId: actorId,
    requestId: requestId,
    source: 'email_verification',
  );

  /// Performs the customer/owner checks required before a separate Cloud web
  /// layer calls the provider adapter. This method has no mutation: billing
  /// cancellation and the durable deletion request remain distinct steps.
  Future<void> authorizeOrganizationDeletion({
    required String userId,
    required String organizationId,
  }) async {
    if (deploymentModel != DeploymentModel.cloud) {
      throw const ControlPlaneException(
        'CLOUD_DELETION_UNAVAILABLE',
        'Organization deletion is only available for Cloud organizations',
        statusCode: 404,
      );
    }
    final user = await _activeCustomer(userId);
    await _requireOwner(user, organizationId);
    final organization = await store.readJson('organizations', organizationId);
    if (organization == null || organization['deletionState'] == 'deleted') {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Organization was not found',
        statusCode: 404,
      );
    }
  }

  Future<Map<String, Object?>> requestOrganizationDeletion({
    required String userId,
    required String organizationId,
    required String requestId,
  }) => _serialized(() async {
    if (deploymentModel != DeploymentModel.cloud) {
      throw const ControlPlaneException(
        'CLOUD_DELETION_UNAVAILABLE',
        'Organization deletion is only available for Cloud organizations',
        statusCode: 404,
      );
    }
    final user = await _activeCustomer(userId);
    await _requireOwner(user, organizationId);
    final organizationValue = await store.readJson(
      'organizations',
      organizationId,
    );
    if (organizationValue == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Organization was not found',
        statusCode: 404,
      );
    }
    final organization = OrganizationRecord.fromJson(organizationValue);
    final id = _organizationRequestId(organizationId);
    final existing = await store.readJson(
      organizationDeletionRequestCollection,
      id,
    );
    if (existing != null &&
        _openDeletionStatuses.contains(existing['status']) &&
        !(existing['status'] == 'failed' && existing['stage'] == 'billing')) {
      return existing;
    }
    if (organization.deletionState == 'deleted') {
      return <String, Object?>{
        'id': id,
        'scope': 'organization',
        'organizationId': organizationId,
        'status': 'completed',
      };
    }
    final now = _now();
    var request = <String, Object?>{
      'id': id,
      'scope': 'organization',
      'organizationId': organizationId,
      'requestedBy': userId,
      'source': 'authenticated',
      'status': 'billing_pending',
      'stage': 'billing',
      'requestedAt': existing?['requestedAt'] ?? now.toIso8601String(),
      'verifiedAt': now.toIso8601String(),
      'gracePeriodEndsAt': _graceEndsAt(now),
      'updatedAt': now.toIso8601String(),
      'attempt': existing?['attempt'] ?? 0,
      if (existing?['createdAt'] != null) 'createdAt': existing!['createdAt'],
      if (existing?['createdAt'] == null) 'createdAt': now.toIso8601String(),
    };
    await _createOrReplaceRequest(
      organizationDeletionRequestCollection,
      id,
      request,
      existing,
    );
    try {
      final billingStop = await billing.stopFutureRenewalForDeletion(
        organizationId: organizationId,
        actorId: userId,
      );
      await _revokeOrganizationCredentials(organizationId);
      final marked = OrganizationRecord(
        id: organization.id,
        name: organization.name,
        createdAt: organization.createdAt,
        deletionState: 'deletion_requested',
        deletionRequestedAt: now,
        deletionRequestId: id,
      );
      await store.replaceJson('organizations', organizationId, marked.toJson());
      request = <String, Object?>{
        ...request,
        'status': _verifiedStatus(),
        'stage': 'grace_period',
        'billingStop': <String, Object?>{
          'status': billingStop['status'],
          'effectivePlan': billingStop['effectivePlan'],
        },
        'billingStoppedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };
      await store.replaceJson(
        organizationDeletionRequestCollection,
        id,
        request,
      );
    } on ControlPlaneException catch (error) {
      request = <String, Object?>{
        ...request,
        'status': 'failed',
        'stage': 'billing',
        'lastError': error.code,
        'updatedAt': _now().toIso8601String(),
        'attempt': (request['attempt']! as int) + 1,
      };
      await store.replaceJson(
        organizationDeletionRequestCollection,
        id,
        request,
      );
      await _audit(
        requestId: requestId,
        organizationId: organizationId,
        actorId: userId,
        action: 'organization.deletion.failed',
        resourceType: 'organization_deletion_request',
        resourceId: id,
        metadata: <String, Object?>{'stage': 'billing', 'code': error.code},
      );
      rethrow;
    }
    await _audit(
      requestId: requestId,
      organizationId: organizationId,
      actorId: userId,
      action: 'organization.deletion.verified',
      resourceType: 'organization_deletion_request',
      resourceId: id,
      metadata: const <String, Object?>{'source': 'authenticated'},
    );
    await _audit(
      requestId: requestId,
      organizationId: organizationId,
      actorId: userId,
      action: 'organization.deletion.requested',
      resourceType: 'organization_deletion_request',
      resourceId: id,
      metadata: <String, Object?>{
        'status': request['status'],
        'billing_status': request['billingStop'],
      },
    );
    return request;
  });

  Future<Map<String, Object?>> accountStatus({required String userId}) async {
    final request = await store.readJson(
      accountDeletionRequestCollection,
      _accountRequestId(userId),
    );
    return request ??
        <String, Object?>{
          'scope': 'account',
          'status': 'not_requested',
          'userId': userId,
        };
  }

  Future<Map<String, Object?>> organizationStatus({
    required String userId,
    required String organizationId,
  }) async {
    final user = await _activeCustomer(userId);
    await _requireCustomerMembership(user, organizationId);
    final request = await store.readJson(
      organizationDeletionRequestCollection,
      _organizationRequestId(organizationId),
    );
    return request ??
        <String, Object?>{
          'scope': 'organization',
          'status': 'not_requested',
          'organizationId': organizationId,
        };
  }

  Future<Map<String, Object?>> cancelAccountDeletion({
    required String userId,
    required String actorId,
    required String requestId,
  }) => _serialized(() async {
    final id = _accountRequestId(userId);
    final current = await store.readJson(accountDeletionRequestCollection, id);
    if (current == null ||
        !_openDeletionStatuses.contains(current['status']) ||
        current['status'] == 'processing') {
      return current ??
          <String, Object?>{'scope': 'account', 'status': 'not_requested'};
    }
    final updated = <String, Object?>{
      ...current,
      'status': 'cancelled',
      'stage': 'cancelled',
      'cancelledAt': _now().toIso8601String(),
      'updatedAt': _now().toIso8601String(),
    };
    await store.replaceJson(accountDeletionRequestCollection, id, updated);
    await _audit(
      requestId: requestId,
      organizationId: await _auditOrganizationForUser(userId),
      actorId: actorId,
      action: 'account.deletion.cancelled',
      resourceType: 'account_deletion_request',
      resourceId: id,
      metadata: const <String, Object?>{},
    );
    return updated;
  });

  /// Organization deletion cancellation is fail-closed after a paid provider
  /// cancellation has been scheduled. Reversing that provider action is a
  /// separate provider-first operation and cannot be faked by changing local
  /// deletion state.
  Future<Map<String, Object?>> cancelOrganizationDeletion({
    required String userId,
    required String organizationId,
    required String actorId,
    required String requestId,
  }) => _serialized(() async {
    final user = await _activeCustomer(userId);
    await _requireOwner(user, organizationId);
    final id = _organizationRequestId(organizationId);
    final current = await store.readJson(
      organizationDeletionRequestCollection,
      id,
    );
    if (current == null ||
        !_openDeletionStatuses.contains(current['status']) ||
        current['status'] == 'processing') {
      return current ??
          <String, Object?>{'scope': 'organization', 'status': 'not_requested'};
    }
    final stop = current['billingStop'];
    final stopMap = stop is Map<String, Object?> ? stop : null;
    if (stopMap?['status'] != 'not_active') {
      throw const ControlPlaneException(
        'DELETION_CANCEL_REQUIRES_BILLING_RECONCILIATION',
        'This deletion request cannot be cancelled after provider renewal was stopped',
        statusCode: 409,
      );
    }
    final organizationValue = await store.readJson(
      'organizations',
      organizationId,
    );
    if (organizationValue != null) {
      final organization = OrganizationRecord.fromJson(organizationValue);
      await store.replaceJson(
        'organizations',
        organizationId,
        OrganizationRecord(
          id: organization.id,
          name: organization.name,
          createdAt: organization.createdAt,
        ).toJson(),
      );
    }
    final updated = <String, Object?>{
      ...current,
      'status': 'cancelled',
      'stage': 'cancelled',
      'cancelledAt': _now().toIso8601String(),
      'updatedAt': _now().toIso8601String(),
    };
    await store.replaceJson(organizationDeletionRequestCollection, id, updated);
    await _audit(
      requestId: requestId,
      organizationId: organizationId,
      actorId: actorId,
      action: 'organization.deletion.cancelled',
      resourceType: 'organization_deletion_request',
      resourceId: id,
      metadata: const <String, Object?>{},
    );
    return updated;
  });

  /// Processes one request in bounded, retryable batches. The request record
  /// is the durable queue: a scheduler can call this method repeatedly after
  /// restart without a second queue or a synchronous HTTP cascade.
  Future<Map<String, Object?>> processDeletion({
    required String requestId,
    int maxItems = 50,
    DateTime? now,
  }) => _serialized(() async {
    if (maxItems < 1 || maxItems > 1000) {
      throw ArgumentError.value(
        maxItems,
        'maxItems',
        'must be between 1 and 1000',
      );
    }
    final scope = requestId.startsWith('adel_')
        ? 'account'
        : requestId.startsWith('odel_')
        ? 'organization'
        : null;
    if (scope == null) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Deletion request ID is invalid',
        statusCode: 422,
      );
    }
    final collection = scope == 'account'
        ? accountDeletionRequestCollection
        : organizationDeletionRequestCollection;
    final current = await store.readJson(collection, requestId);
    if (current == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Deletion request was not found',
        statusCode: 404,
      );
    }
    final status = current['status'];
    if (_terminalDeletionStatuses.contains(status)) return current;
    if (status == 'ownership_resolution_required') return current;
    if (status == 'policy_decision_required') {
      return <String, Object?>{
        ...current,
        'blocker': 'POLICY_DECISION_REQUIRED: deletion_grace_period',
      };
    }
    final normalizedNow = (now ?? _now()).toUtc();
    var ready = current;
    if (scope == 'organization' &&
        status == 'failed' &&
        current['stage'] == 'billing') {
      ready = await _retryOrganizationBilling(
        current,
        normalizedNow: normalizedNow,
      );
      if (ready['status'] == 'policy_decision_required') return ready;
    }
    final readyStatus = ready['status'];
    final graceEndsAt = _parseTime(ready['gracePeriodEndsAt']);
    if (readyStatus == 'grace_period' &&
        graceEndsAt != null &&
        graceEndsAt.isAfter(normalizedNow)) {
      return ready;
    }
    final processing = <String, Object?>{
      ...ready,
      'status': 'processing',
      'stage': 'processing',
      'attempt': (ready['attempt'] is int ? ready['attempt']! as int : 0) + 1,
      'updatedAt': normalizedNow.toIso8601String(),
    };
    await store.replaceJson(collection, requestId, processing);
    try {
      final organizationValue = processing['organizationId'];
      final processingOrganizationId =
          scope == 'organization' && organizationValue is String
          ? organizationValue
          : _auditOrganizationFromRequest(processing);
      await _audit(
        requestId: requestId,
        organizationId: processingOrganizationId,
        actorId: 'hyfens:deletion-worker',
        action: '${scope}.deletion.processing',
        resourceType: '${scope}_deletion_request',
        resourceId: requestId,
        metadata: <String, Object?>{
          'attempt': processing['attempt'],
          'stage': processing['stage'],
        },
      );
      final result = scope == 'account'
          ? await _processAccount(processing, normalizedNow, requestId)
          : await _processOrganization(
              processing,
              normalizedNow,
              requestId,
              maxItems,
            );
      return result;
    } on Object catch (error) {
      final failed = <String, Object?>{
        ...processing,
        'status': 'failed',
        'stage': processing['stage'],
        'lastError': _safeError(error),
        'updatedAt': _now().toIso8601String(),
      };
      await store.replaceJson(collection, requestId, failed);
      final organizationValue = processing['organizationId'];
      final organizationId =
          scope == 'organization' && organizationValue is String
          ? organizationValue
          : _auditOrganizationFromRequest(processing);
      await _audit(
        requestId: requestId,
        organizationId: organizationId,
        actorId: 'hyfens:deletion-worker',
        action: '${scope}.deletion.failed',
        resourceType: '${scope}_deletion_request',
        resourceId: requestId,
        metadata: <String, Object?>{
          'stage': processing['stage'],
          'error': _safeError(error),
        },
      );
      return failed;
    }
  });

  Future<List<Map<String, Object?>>> processPendingDeletions({
    int maxRequests = 10,
    int maxItemsPerRequest = 50,
    DateTime? now,
  }) async {
    if (maxRequests < 1 ||
        maxRequests > 100 ||
        maxItemsPerRequest < 1 ||
        maxItemsPerRequest > 1000) {
      throw ArgumentError('Deletion worker limits are out of range');
    }
    final requests = <Map<String, Object?>>[
      ...await store.listJson(accountDeletionRequestCollection),
      ...await store.listJson(organizationDeletionRequestCollection),
    ];
    final due = requests
        .where((request) {
          final status = request['status'];
          if (status != 'grace_period' &&
              status != 'failed' &&
              status != 'processing') {
            return false;
          }
          final at = _parseTime(request['gracePeriodEndsAt']);
          return status == 'processing' ||
              (at != null && !at.isAfter((now ?? _now()).toUtc()));
        })
        .take(maxRequests)
        .toList(growable: false);
    final result = <Map<String, Object?>>[];
    for (final request in due) {
      final id = request['id'];
      if (id is String) {
        result.add(
          await processDeletion(
            requestId: id,
            maxItems: maxItemsPerRequest,
            now: now,
          ),
        );
      }
    }
    return List.unmodifiable(result);
  }

  Future<Map<String, Object?>> _retryOrganizationBilling(
    Map<String, Object?> request, {
    required DateTime normalizedNow,
  }) async {
    final organizationId = request['organizationId'];
    if (organizationId is! String) {
      throw const FormatException('Deletion organization is invalid');
    }
    final organizationValue = await store.readJson(
      'organizations',
      organizationId,
    );
    if (organizationValue == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Organization was not found',
        statusCode: 404,
      );
    }
    final organization = OrganizationRecord.fromJson(organizationValue);
    final billingStop = await billing.stopFutureRenewalForDeletion(
      organizationId: organizationId,
      actorId: 'hyfens:deletion-worker',
    );
    await _revokeOrganizationCredentials(organizationId);
    final requestId = request['id'];
    if (requestId is! String)
      throw const FormatException('Deletion ID is invalid');
    if (organization.deletionState != 'deletion_requested') {
      await store.replaceJson(
        'organizations',
        organizationId,
        OrganizationRecord(
          id: organization.id,
          name: organization.name,
          createdAt: organization.createdAt,
          deletionState: 'deletion_requested',
          deletionRequestedAt:
              organization.deletionRequestedAt ?? normalizedNow,
          deletionRequestId: requestId,
        ).toJson(),
      );
    }
    final updated = <String, Object?>{
      ...request,
      'status': _verifiedStatus(),
      'stage': 'grace_period',
      'billingStop': <String, Object?>{
        'status': billingStop['status'],
        'effectivePlan': billingStop['effectivePlan'],
      },
      'billingStoppedAt':
          request['billingStoppedAt'] ?? normalizedNow.toIso8601String(),
      'updatedAt': normalizedNow.toIso8601String(),
      'attempt':
          (request['attempt'] is int ? request['attempt']! as int : 0) + 1,
    };
    await store.replaceJson(
      organizationDeletionRequestCollection,
      requestId,
      updated,
    );
    return updated;
  }

  Future<Map<String, Object?>> _processAccount(
    Map<String, Object?> request,
    DateTime now,
    String requestId,
  ) async {
    final userId = request['userId'];
    if (userId is! String)
      throw const FormatException('Deletion user is invalid');
    final value = await store.readJson('users', userId);
    if (value == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Customer account was not found',
        statusCode: 404,
      );
    }
    final user = HumanUserRecord.fromJson(value);
    if (user.active) {
      final ownership = await _soleOwnedOrganizations(user);
      if (ownership.isNotEmpty) {
        final blocked = <String, Object?>{
          ...request,
          'status': 'ownership_resolution_required',
          'stage': 'ownership',
          'ownershipRequiredOrganizations': ownership.toList(growable: false),
          'updatedAt': now.toIso8601String(),
        };
        await store.replaceJson(
          accountDeletionRequestCollection,
          requestId,
          blocked,
        );
        return blocked;
      }
      // Deactivation is the final identity mutation. If the worker crashes
      // after it succeeds, a retry must be able to finish the request instead
      // of treating the already-deactivated account as an auth failure.
      await _requireHumanAuth().deactivateUser(userId: user.id);
    }
    final completed = <String, Object?>{
      ...request,
      'status': 'completed',
      'stage': 'completed',
      'completedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };
    await store.replaceJson(
      accountDeletionRequestCollection,
      requestId,
      completed,
    );
    await _audit(
      requestId: requestId,
      organizationId: _auditOrganization(user),
      actorId: 'hyfens:deletion-worker',
      action: 'account.deletion.completed',
      resourceType: 'account_deletion_request',
      resourceId: requestId,
      metadata: const <String, Object?>{'retention': 'classified'},
    );
    return completed;
  }

  Future<Map<String, Object?>> _processOrganization(
    Map<String, Object?> request,
    DateTime now,
    String requestId,
    int maxItems,
  ) async {
    if (deploymentModel != DeploymentModel.cloud) {
      throw const ControlPlaneException(
        'CLOUD_DELETION_UNAVAILABLE',
        'Organization deletion is only available for Cloud organizations',
        statusCode: 404,
      );
    }
    final organizationId = request['organizationId'];
    if (organizationId is! String) {
      throw const FormatException('Deletion organization is invalid');
    }
    final deletion = store is JsonRecordDeletion
        ? store as JsonRecordDeletion
        : null;
    if (deletion == null) {
      throw const StorageUnavailable(
        'The configured store cannot perform staged record deletion',
      );
    }
    var processed = 0;
    for (final collection in _organizationOwnedCollections) {
      if (processed >= maxItems) break;
      final values = await store.listJson(collection);
      if (collection == 'artifacts') {
        final allArtifacts = values;
        for (final value in values) {
          if (processed >= maxItems) break;
          if (value['organizationId'] != organizationId) continue;
          final id = value['id'];
          if (id is! String)
            throw const FormatException('Artifact ID is invalid');
          await _deleteArtifactRecord(
            deletion,
            value,
            allArtifacts,
            organizationId,
            requestId,
            now,
          );
          processed++;
        }
        continue;
      }
      for (final value in values) {
        if (processed >= maxItems ||
            value['organizationId'] != organizationId) {
          continue;
        }
        final id = value['id'];
        if (id is! String) continue;
        await _retainEvidence(
          collection: collection,
          id: id,
          organizationId: organizationId,
          value: value,
          requestId: requestId,
          createdAt: now,
        );
        await deletion.deleteJson(collection, id);
        processed++;
      }
    }
    if (processed < maxItems) {
      final remaining = maxItems - processed;
      final observations = store is BoundedObservationDeletion
          ? await (store as BoundedObservationDeletion).deleteObservationsBatch(
              organizationId: organizationId,
              olderThan: now.add(const Duration(days: 1)),
              limit: remaining,
            )
          : await store.deleteObservations(
              organizationId: organizationId,
              olderThan: now.add(const Duration(days: 1)),
            );
      processed += observations;
    }

    for (final value in await store.listJson('users')) {
      if (processed >= maxItems) break;
      final user = HumanUserRecord.fromJson(value);
      final remaining = user.memberships
          .where((membership) => membership.organizationId != organizationId)
          .toList(growable: false);
      if (remaining.length == user.memberships.length) continue;
      await store.replaceJson(
        'users',
        user.id,
        user.copyWith(memberships: remaining).toJson(),
      );
      processed++;
    }

    if (await _hasOrganizationRecords(organizationId) ||
        await _hasOrganizationMemberships(organizationId)) {
      final progress = <String, Object?>{
        ...request,
        'status': 'processing',
        'stage': 'processing',
        'processedItems':
            (request['processedItems'] is int
                ? request['processedItems']! as int
                : 0) +
            processed,
        'updatedAt': now.toIso8601String(),
      };
      await store.replaceJson(
        organizationDeletionRequestCollection,
        requestId,
        progress,
      );
      return progress;
    }
    final organizationValue = await store.readJson(
      'organizations',
      organizationId,
    );
    if (organizationValue != null) {
      final organization = OrganizationRecord.fromJson(organizationValue);
      final tombstone = OrganizationRecord(
        id: organization.id,
        name: 'Deleted organization',
        createdAt: organization.createdAt,
        deletionState: 'deleted',
        deletionRequestedAt: organization.deletionRequestedAt ?? now,
        deletedAt: now,
        deletionRequestId: requestId,
      );
      await store.replaceJson(
        'organizations',
        organizationId,
        tombstone.toJson(),
      );
    }
    final completed = <String, Object?>{
      ...request,
      'status': 'completed',
      'stage': 'completed',
      'processedItems':
          (request['processedItems'] is int
              ? request['processedItems']! as int
              : 0) +
          processed,
      'completedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };
    await store.replaceJson(
      organizationDeletionRequestCollection,
      requestId,
      completed,
    );
    await _audit(
      requestId: requestId,
      organizationId: organizationId,
      actorId: 'hyfens:deletion-worker',
      action: 'organization.deletion.completed',
      resourceType: 'organization_deletion_request',
      resourceId: requestId,
      metadata: <String, Object?>{
        'processed_items': completed['processedItems'],
        'artifact_bytes': 'shared_reference_checked',
      },
    );
    return completed;
  }

  Future<void> _deleteArtifactRecord(
    JsonRecordDeletion deletion,
    Map<String, Object?> value,
    List<Map<String, Object?>> allArtifacts,
    String organizationId,
    String requestId,
    DateTime now,
  ) async {
    final id = value['id'];
    final digest = value['sha256'];
    if (id is! String || digest is! String) {
      throw const FormatException('Artifact deletion record is invalid');
    }
    final shared = allArtifacts.any(
      (other) =>
          other['id'] != id &&
          other['sha256'] == digest &&
          other['organizationId'] != organizationId &&
          other['state'] != artifactPurgedState,
    );
    final physical = store is ArtifactDeletion
        ? store as ArtifactDeletion
        : null;
    if (!shared && physical == null) {
      throw const StorageUnavailable(
        'The configured store cannot purge exclusive artifact bytes',
      );
    }
    final itemId =
        'ditem_${sha256Hex(utf8.encode('$requestId:$id')).substring(0, 32)}';
    final pending = <String, Object?>{
      'id': itemId,
      'organizationId': organizationId,
      'requestId': requestId,
      'artifactId': id,
      'digest': digest,
      'status': 'pending',
      'updatedAt': now.toIso8601String(),
    };
    final existing = await store.readJson('deletion_artifact_items', itemId);
    if (existing == null) {
      await store.createJson('deletion_artifact_items', itemId, pending);
    } else if (existing['status'] == 'purged' ||
        existing['status'] == 'shared_retained' ||
        existing['status'] == 'already_absent') {
      return;
    }
    await _retainEvidence(
      collection: 'artifacts',
      id: id,
      organizationId: organizationId,
      value: value,
      requestId: requestId,
      createdAt: now,
    );
    var status = 'shared_retained';
    if (!shared && physical != null) {
      final existed = await physical.deleteArtifact(digest);
      status = existed ? 'purged' : 'already_absent';
    }
    final deleted = await deletion.deleteJson('artifacts', id);
    if (!deleted && await store.readJson('artifacts', id) != null) {
      throw const StorageConflict('Artifact metadata could not be deleted');
    }
    await store.replaceJson(
      'deletion_artifact_items',
      itemId,
      <String, Object?>{
        ...pending,
        'status': status,
        'updatedAt': _now().toIso8601String(),
      },
    );
  }

  Future<bool> _hasOrganizationRecords(String organizationId) async {
    for (final collection in _organizationOwnedCollections) {
      for (final value in await store.listJson(collection)) {
        if (value['organizationId'] == organizationId) return true;
      }
    }
    return (await store.listObservations(organizationId: organizationId))
        .isNotEmpty;
  }

  Future<bool> _hasOrganizationMemberships(String organizationId) async {
    for (final value in await store.listJson('users')) {
      final memberships = value['memberships'];
      if (memberships is! List) continue;
      if (memberships.any(
        (membership) =>
            membership is Map && membership['organizationId'] == organizationId,
      )) {
        return true;
      }
    }
    return false;
  }

  Future<void> _retainEvidence({
    required String collection,
    required String id,
    required String organizationId,
    required Map<String, Object?> value,
    required String requestId,
    required DateTime createdAt,
  }) async {
    final evidenceId =
        'dev_${sha256Hex(utf8.encode('$requestId:$collection:$id')).substring(0, 32)}';
    final evidence = <String, Object?>{
      'id': evidenceId,
      'organizationId': organizationId,
      'requestId': requestId,
      'sourceCollection': collection,
      'sourceId': id,
      'sourceDigest': sha256Digest(utf8.encode(canonicalJson(value))),
      'createdAt': createdAt.toIso8601String(),
      'retention': 'anonymized_security_evidence',
    };
    final existing = await store.readJson('deletion_evidence', evidenceId);
    if (existing == null) {
      await store.createJson('deletion_evidence', evidenceId, evidence);
    }
  }

  Future<void> _revokeOrganizationCredentials(String organizationId) async {
    final now = _now();
    for (final value in await store.listJson('credentials')) {
      if (value['organizationId'] != organizationId ||
          value['revoked'] == true) {
        continue;
      }
      final id = value['tokenHash'] ?? value['id'];
      if (id is String) {
        await store.replaceJson('credentials', id, <String, Object?>{
          ...value,
          'revoked': true,
          'revokedAt': now.toIso8601String(),
        });
      }
    }
  }

  Future<HumanUserRecord> _activeCustomer(String userId) async {
    final user = await _activeVerifiedUser(userId);
    if (user.memberships.every(
      (membership) => membership.audience != customerAuthorizationAudience,
    )) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'A verified customer account is required',
        statusCode: 403,
      );
    }
    return user;
  }

  Future<HumanUserRecord> _activeVerifiedUser(String userId) async {
    final value = await store.readJson('users', userId);
    if (value == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Customer account was not found',
        statusCode: 404,
      );
    }
    final user = HumanUserRecord.fromJson(value);
    if (!user.active || !user.emailVerified) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'A verified account is required',
        statusCode: 403,
      );
    }
    return user;
  }

  HumanAuthService _requireHumanAuth() {
    final auth = humanAuth;
    if (auth == null) {
      throw const ControlPlaneException(
        'AUTH_UNAVAILABLE',
        'Human authentication is not configured',
        statusCode: 503,
      );
    }
    return auth;
  }

  Future<void> _requireCustomerMembership(
    HumanUserRecord user,
    String organizationId,
  ) async {
    if (!user.memberships.any(
      (membership) =>
          membership.audience == customerAuthorizationAudience &&
          membership.organizationId == organizationId,
    )) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Organization was not found',
        statusCode: 404,
      );
    }
  }

  Future<void> _requireOwner(
    HumanUserRecord user,
    String organizationId,
  ) async {
    await _requireCustomerMembership(user, organizationId);
    if (!user.memberships.any(
      (membership) =>
          membership.audience == customerAuthorizationAudience &&
          membership.organizationId == organizationId &&
          membership.role == 'owner',
    )) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'Organization ownership is required for deletion',
        statusCode: 403,
      );
    }
  }

  Future<Set<String>> _soleOwnedOrganizations(HumanUserRecord user) async {
    final allUsers = (await store.listJson('users'))
        .map(HumanUserRecord.fromJson)
        .toList(growable: false);
    final owned = user.memberships
        .where(
          (membership) =>
              membership.audience == customerAuthorizationAudience &&
              membership.role == 'owner',
        )
        .map((membership) => membership.organizationId)
        .toSet();
    return owned
        .where(
          (organizationId) =>
              allUsers
                  .where(
                    (candidate) =>
                        candidate.active &&
                        candidate.memberships.any(
                          (membership) =>
                              membership.audience ==
                                  customerAuthorizationAudience &&
                              membership.organizationId == organizationId &&
                              membership.role == 'owner',
                        ),
                  )
                  .length ==
              1,
        )
        .toSet();
  }

  Future<void> _createOrReplaceRequest(
    String collection,
    String id,
    Map<String, Object?> value,
    Map<String, Object?>? existing,
  ) async {
    if (existing == null) {
      try {
        await store.createJson(collection, id, value);
      } on StorageConflict {
        final concurrent = await store.readJson(collection, id);
        if (concurrent == null) rethrow;
      }
      return;
    }
    await store.replaceJson(collection, id, value);
  }

  Future<void> _audit({
    required String requestId,
    required String organizationId,
    required String actorId,
    required String action,
    required String resourceType,
    required String resourceId,
    required Map<String, Object?> metadata,
  }) async {
    final id =
        'aud_deletion_${sha256Hex(utf8.encode('$organizationId:$action:$resourceId')).substring(0, 32)}';
    final value = AuditRecord(
      id: id,
      requestId: requestId,
      organizationId: organizationId,
      actorId: actorId,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      result: 'SUCCESS',
      metadata: metadata,
      createdAt: _now(),
    ).toJson();
    if (await store.readJson('audit', id) == null) {
      try {
        await store.appendAudit(id, value);
      } on StorageConflict {
        if (await store.readJson('audit', id) == null) rethrow;
      }
    }
  }

  String _verifiedStatus() =>
      policy.gracePeriod == null ? 'policy_decision_required' : 'grace_period';

  String? _graceEndsAt(DateTime now) {
    final duration = policy.gracePeriod;
    return duration == null ? null : now.add(duration).toIso8601String();
  }

  DateTime _now() => _clock().toUtc();

  String _accountRequestId(String userId) =>
      'adel_${sha256Hex(utf8.encode(userId)).substring(0, 32)}';

  String _organizationRequestId(String organizationId) =>
      'odel_${sha256Hex(utf8.encode(organizationId)).substring(0, 32)}';

  String _auditOrganization(HumanUserRecord user) {
    for (final membership in user.memberships) {
      if (membership.audience == customerAuthorizationAudience) {
        return membership.organizationId;
      }
    }
    return 'org_system';
  }

  Future<String> _auditOrganizationForUser(String userId) async {
    final value = await store.readJson('users', userId);
    if (value == null) return 'org_system';
    final user = HumanUserRecord.fromJson(value);
    return user.memberships.isEmpty ? 'org_system' : _auditOrganization(user);
  }

  String _auditOrganizationFromRequest(Map<String, Object?> request) {
    final organizations =
        request['organizationIds'] ?? request['ownershipRequiredOrganizations'];
    if (organizations is List &&
        organizations.isNotEmpty &&
        organizations.first is String) {
      return organizations.first as String;
    }
    return 'org_system';
  }

  static DateTime? _parseTime(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  static String _safeError(Object error) => switch (error) {
    ControlPlaneException(:final code) => code,
    StorageUnavailable(:final message) =>
      message.length > 128 ? message.substring(0, 128) : message,
    _ => 'DELETION_PROCESSING_FAILED',
  };

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _writeTail.then((_) => action());
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }
}
