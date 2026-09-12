import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'artifact_retention.dart';
import 'billing.dart';
import 'cloud_plans.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'notifications.dart';
import 'persistence.dart';

const String accountDeletionRequestCollection = 'account_deletion_requests';
const String organizationDeletionRequestCollection =
    'organization_deletion_requests';

/// A small deterministic business calendar for privacy deadlines.
///
/// The control plane intentionally supports UTC, Asia/Kolkata, and explicit
/// fixed offsets without pretending to have an IANA timezone database. A
/// deployment that needs a DST-observing timezone must supply a timezone-aware
/// calendar at its integration boundary rather than silently using server
/// local time.
final class BusinessCalendar {
  BusinessCalendar({
    required this.businessTimeZone,
    Iterable<String> holidays = const <String>[],
  }) : _offset = _parseOffset(businessTimeZone),
       holidays = Set.unmodifiable(_validateHolidays(holidays));

  final String businessTimeZone;
  final Duration _offset;
  final Set<String> holidays;

  DateTime scheduleAt({
    required DateTime verifiedAt,
    required int workingDaysAfter,
  }) {
    if (workingDaysAfter <= 0) {
      throw ArgumentError.value(
        workingDaysAfter,
        'workingDaysAfter',
        'must be positive',
      );
    }
    var date = _localDate(verifiedAt);
    var remaining = workingDaysAfter;
    while (remaining > 0) {
      date = date.add(const Duration(days: 1));
      if (isBusinessDate(date)) remaining--;
    }
    return _startOfLocalDate(date);
  }

  /// Returns the start of a numbered working day, counting the verification
  /// date as day 1 when it is a business date. Weekend/holiday verification
  /// starts on the next configured business date. This keeps day 5, day 7,
  /// and day 8 deadlines distinct and deterministic.
  DateTime workingDayAt({
    required DateTime verifiedAt,
    required int workingDay,
  }) {
    if (workingDay <= 0) {
      throw ArgumentError.value(workingDay, 'workingDay', 'must be positive');
    }
    var date = _localDate(verifiedAt);
    var remaining = workingDay;
    while (remaining > 0) {
      if (isBusinessDate(date)) remaining--;
      if (remaining > 0) date = date.add(const Duration(days: 1));
    }
    return _startOfLocalDate(date);
  }

  bool isBusinessDate(DateTime date) {
    final local = DateTime.utc(date.year, date.month, date.day);
    final key = _dateKey(local);
    return local.weekday <= DateTime.friday && !holidays.contains(key);
  }

  String dateKeyAt(DateTime utc) => _dateKey(_localDate(utc));

  DateTime _localDate(DateTime value) {
    final shifted = value.toUtc().add(_offset);
    return DateTime.utc(shifted.year, shifted.month, shifted.day);
  }

  DateTime _startOfLocalDate(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day).subtract(_offset);
  }

  static Duration _parseOffset(String value) {
    final normalized = value.trim();
    if (normalized == 'UTC' || normalized == 'Etc/UTC') {
      return Duration.zero;
    }
    if (normalized == 'Asia/Kolkata' || normalized == 'Asia/Calcutta') {
      return const Duration(hours: 5, minutes: 30);
    }
    final match = RegExp(r'^([+-])(\d{2}):(\d{2})$').firstMatch(normalized);
    if (match == null) {
      throw ArgumentError(
        'HYFENS_DELETION_BUSINESS_TIMEZONE must be UTC, Asia/Kolkata, or a fixed offset such as +05:30',
      );
    }
    final hours = int.parse(match.group(2)!);
    final minutes = int.parse(match.group(3)!);
    if (hours > 23 || minutes > 59) {
      throw ArgumentError.value(
        value,
        'businessTimeZone',
        'has an invalid offset',
      );
    }
    final offset = Duration(hours: hours, minutes: minutes);
    return match.group(1) == '-' ? -offset : offset;
  }

  static Set<String> _validateHolidays(Iterable<String> values) {
    final result = <String>{};
    for (final value in values) {
      final normalized = value.trim();
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(normalized)) {
        throw ArgumentError.value(value, 'holidays', 'must use YYYY-MM-DD');
      }
      final parsed = DateTime.tryParse('${normalized}T00:00:00Z');
      if (parsed == null || _dateKey(parsed) != normalized) {
        throw ArgumentError.value(
          value,
          'holidays',
          'contains an invalid date',
        );
      }
      result.add(normalized);
    }
    return result;
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

final class DeletionPolicy {
  const DeletionPolicy({
    this.graceWorkingDays,
    this.businessTimeZone = 'UTC',
    this.holidayDates = const <String>[],
  });

  final int? graceWorkingDays;
  final String businessTimeZone;
  final List<String> holidayDates;

  bool get isConfigured => graceWorkingDays != null;

  BusinessCalendar get calendar => BusinessCalendar(
    businessTimeZone: businessTimeZone,
    holidays: holidayDates,
  );

  static DeletionPolicy fromEnvironment(Map<String, String> values) {
    final raw = values['HYFENS_DELETION_GRACE_PERIOD']?.trim();
    final timezone = values['HYFENS_DELETION_BUSINESS_TIMEZONE']?.trim();
    final holidays = values['HYFENS_DELETION_HOLIDAYS']
        ?.split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (raw == null || raw.isEmpty) {
      if (timezone != null && timezone.isNotEmpty) {
        BusinessCalendar(
          businessTimeZone: timezone,
          holidays: holidays ?? const <String>[],
        );
      }
      if (holidays != null && holidays.isNotEmpty) {
        BusinessCalendar(
          businessTimeZone: timezone ?? 'UTC',
          holidays: holidays,
        );
      }
      return const DeletionPolicy();
    }
    final match = RegExp(r'^([1-9][0-9]*)d$').firstMatch(raw);
    if (match == null) {
      throw ArgumentError(
        'HYFENS_DELETION_GRACE_PERIOD must use working days such as 7d',
      );
    }
    final amount = int.parse(match.group(1)!);
    if (amount > 365) {
      throw ArgumentError(
        'HYFENS_DELETION_GRACE_PERIOD must not exceed 365 working days',
      );
    }
    final policy = DeletionPolicy(
      graceWorkingDays: amount,
      businessTimeZone: timezone == null || timezone.isEmpty ? 'UTC' : timezone,
      holidayDates: List.unmodifiable(holidays ?? const <String>[]),
    );
    policy.calendar;
    return policy;
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
  'cancellation_pending',
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

const Duration _deletionProcessingLease = Duration(minutes: 15);

/// Returns the bounded deletion projection exposed to a customer. Durable
/// request records also contain worker state, credential references, and
/// ownership internals that must never cross the customer API boundary.
Map<String, Object?> deletionStatusForCustomer(Map<String, Object?> request) {
  final result = <String, Object?>{
    for (final key in const <String>[
      'scope',
      'status',
      'stage',
      'requestedAt',
      'verifiedAt',
      'processingAt',
      'processingDate',
      'workingDay5Date',
      'workingDay7Date',
      'businessTimeZone',
      'businessDayPolicy',
      'cancellationAllowed',
      'billingCancellationRetained',
      'restriction',
      'cancelledAt',
      'completedAt',
      'blocker',
    ])
      if (request.containsKey(key) && request[key] != null) key: request[key],
  };
  final ownership = request['ownershipRequiredOrganizations'];
  if (ownership is List && ownership.isNotEmpty) {
    result['ownershipResolutionRequired'] = true;
    result['ownershipResolutionCount'] = ownership.length;
  }
  final billingStop = request['billingStop'];
  if (billingStop is Map) {
    final status = billingStop['status'];
    final plan = billingStop['effectivePlan'];
    if (status is String) result['billingStopStatus'] = status;
    if (plan is String) result['billingEffectivePlan'] = plan;
  }
  return result;
}

/// Account and organization privacy transitions share a durable request record
/// and a bounded worker, but deliberately have different ownership effects.
final class AccountDeletionService {
  AccountDeletionService({
    required this.store,
    this.humanAuth,
    required this.billing,
    required this.deploymentModel,
    this.notifications,
    this.policy = const DeletionPolicy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()) {
    final graceWorkingDays = policy.graceWorkingDays;
    if (graceWorkingDays != null &&
        (graceWorkingDays <= 0 || graceWorkingDays > 365)) {
      throw ArgumentError(
        'Deletion grace period must be between 1 and 365 working days',
      );
    }
    policy.calendar;
  }

  final ControlPlaneStore store;
  final HumanAuthService? humanAuth;
  final BillingService billing;
  final DeploymentModel deploymentModel;
  final NotificationService? notifications;
  final DeletionPolicy policy;
  final DateTime Function() _clock;
  final Random _random = Random.secure();
  Future<void> _writeTail = Future<void>.value();

  Future<Map<String, Object?>> requestAccountDeletion({
    required String userId,
    required String actorId,
    required String requestId,
    String source = 'authenticated',
  }) => _serialized(() async {
    if (deploymentModel != DeploymentModel.cloud) {
      throw const ControlPlaneException(
        'CLOUD_DELETION_UNAVAILABLE',
        'Account deletion is only available for Cloud accounts',
        statusCode: 404,
      );
    }
    final id = _accountRequestId(userId);
    final existing = await store.readJson(accountDeletionRequestCollection, id);
    if (existing != null &&
        (existing['status'] == 'completed' ||
            existing['status'] == 'ownership_resolution_required' ||
            existing['status'] == 'policy_decision_required' ||
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
      'requestGeneration': _requestGeneration(existing),
      'source': source,
      'status': requiredOwnership.isNotEmpty
          ? 'ownership_resolution_required'
          : _verifiedStatus(),
      'stage': requiredOwnership.isNotEmpty ? 'ownership' : 'grace_period',
      'requestedAt': existing?['requestedAt'] ?? now.toIso8601String(),
      'verifiedAt': existing?['verifiedAt'] ?? now.toIso8601String(),
      ..._scheduleFields(
        existing ?? const <String, Object?>{},
        now,
        enabled: requiredOwnership.isEmpty,
        allowCancellation: true,
      ),
      'ownershipRequiredOrganizations': requiredOwnership,
      'updatedAt': now.toIso8601String(),
      'attempt': existing?['attempt'] ?? 0,
      'blockedCredentialIds':
          existing?['blockedCredentialIds'] ??
          await _credentialIdsForUser(user.id),
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
    await _notify(
      key: 'account.deletion.verified',
      stableKey: _deletionNotificationStableKey(request, 'verified'),
      recipient: user.email,
      organizationId: auditOrganizationId == 'system'
          ? null
          : auditOrganizationId,
      entityType: 'account_deletion_request',
      entityId: accountRequestId,
      correlationId: requestId,
      variables: await _deletionNotificationVariables(
        request: request,
        message: requiredOwnership.isNotEmpty
            ? 'Your account deletion request needs ownership resolution before it can proceed.'
            : 'Your account deletion is scheduled for the end of the grace period. Your account is restricted to deletion status and cancellation until then.',
        includeCancelLink: true,
      ),
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
      'requestGeneration': _requestGeneration(existing),
      'status': 'billing_pending',
      'stage': 'billing',
      'requestedAt': existing?['requestedAt'] ?? now.toIso8601String(),
      'verifiedAt': now.toIso8601String(),
      ..._scheduleFields(existing ?? const <String, Object?>{}, now),
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
      final revokedCredentialIds = await _revokeOrganizationCredentials(
        organizationId,
        now,
        id,
      );
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
        'organizationCredentialsRevoked': revokedCredentialIds.length,
        'organizationCredentialRevocationIds': revokedCredentialIds,
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
      action: 'organization.deletion.credentials_revoked',
      resourceType: 'organization_deletion_request',
      resourceId: id,
      metadata: <String, Object?>{
        'credential_count': request['organizationCredentialsRevoked'],
      },
    );
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
    await _notify(
      key: 'organization.deletion.verified',
      stableKey: _deletionNotificationStableKey(request, 'verified'),
      recipient: user.email,
      organizationId: organizationId,
      entityType: 'organization_deletion_request',
      entityId: id,
      correlationId: requestId,
      variables: await _deletionNotificationVariables(
        request: request,
        organization: organization.name,
        message: 'Deletion of this Cloud organization is scheduled. Access is restricted to deletion status and cancellation during the grace period; customer data is preserved until staged processing begins.',
        includeCancelLink: true,
      ),
    );
    return request;
  });

  Future<Map<String, Object?>> accountStatus({required String userId}) async {
    if (deploymentModel != DeploymentModel.cloud) {
      throw const ControlPlaneException(
        'CLOUD_DELETION_UNAVAILABLE',
        'Account deletion is only available for Cloud accounts',
        statusCode: 404,
      );
    }
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

  /// Blocks new Cloud product mutations while a personal deletion request is
  /// unresolved. Ownership-resolution and cancellation remain separate
  /// privacy actions and are handled by their dedicated endpoints.
  Future<void> ensureAccountMutationAllowed({required String userId}) async {
    final request = await store.readJson(
      accountDeletionRequestCollection,
      _accountRequestId(userId),
    );
    final status = request?['status'];
    if (!_isAccountDeletionRestrictedStatus(status)) return;
    throw const ControlPlaneException(
      'ACCOUNT_DELETION_PENDING',
      'This account is restricted while deletion is pending',
      statusCode: 409,
      details: <String, Object?>{
        'scope': 'account',
        'status': 'deletion_pending',
      },
    );
  }

  Future<Map<String, Object?>> organizationStatus({
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
    String? expectedDeletionRequestId,
    int? expectedDeletionRequestGeneration,
  }) => _serialized(() async {
    if (deploymentModel != DeploymentModel.cloud) {
      throw const ControlPlaneException(
        'CLOUD_DELETION_UNAVAILABLE',
        'Account deletion is only available for Cloud accounts',
        statusCode: 404,
      );
    }
    final id = _accountRequestId(userId);
    final current = await store.readJson(accountDeletionRequestCollection, id);
    if (expectedDeletionRequestId != null && expectedDeletionRequestId != id) {
      throw const ControlPlaneException(
        'DELETION_REQUEST_MISMATCH',
        'The deletion cancellation link does not match the current request',
        statusCode: 409,
      );
    }
    if (expectedDeletionRequestGeneration != null &&
        (current == null ||
            current['requestGeneration'] !=
                expectedDeletionRequestGeneration)) {
      throw const ControlPlaneException(
        'DELETION_CANCELLATION_TOKEN_INVALID',
        'The deletion cancellation link is invalid or expired',
        statusCode: 400,
      );
    }
    if (current == null || !_isCancellableStatus(current['status'])) {
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
    if (!await _replaceRequestIfStatus(
      accountDeletionRequestCollection,
      id,
      current['status']! as String,
      updated,
    )) {
      return await store.readJson(accountDeletionRequestCollection, id) ??
          current;
    }
    await _audit(
      requestId: requestId,
      organizationId: await _auditOrganizationForUser(userId),
      actorId: actorId,
      action: 'account.deletion.cancelled',
      resourceType: 'account_deletion_request',
      resourceId: id,
      metadata: const <String, Object?>{},
    );
    final user = await store.readJson('users', userId);
    if (user?['email'] is String) {
      await _notify(
        key: 'account.deletion.cancelled',
        stableKey: _deletionNotificationStableKey(updated, 'cancelled'),
        recipient: user!['email']! as String,
        organizationId: await _auditOrganizationForUser(userId),
        entityType: 'account_deletion_request',
        entityId: id,
        correlationId: requestId,
        variables: const <String, Object?>{
          'message': 'Your account deletion request was cancelled.',
        },
      );
    }
    return updated;
  });

  /// Organization deletion cancellation remains available until the deletion
  /// worker claims irreversible processing. If the provider cancellation has
  /// already been scheduled, local access is restored but the provider billing
  /// state is reported honestly and is not silently reactivated.
  Future<Map<String, Object?>> cancelOrganizationDeletion({
    required String userId,
    required String organizationId,
    required String actorId,
    required String requestId,
    String? expectedDeletionRequestId,
    int? expectedDeletionRequestGeneration,
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
    final id = _organizationRequestId(organizationId);
    final current = await store.readJson(
      organizationDeletionRequestCollection,
      id,
    );
    if (expectedDeletionRequestId != null && expectedDeletionRequestId != id) {
      throw const ControlPlaneException(
        'DELETION_REQUEST_MISMATCH',
        'The deletion cancellation link does not match the current request',
        statusCode: 409,
      );
    }
    if (expectedDeletionRequestGeneration != null &&
        (current == null ||
            current['requestGeneration'] !=
                expectedDeletionRequestGeneration)) {
      throw const ControlPlaneException(
        'DELETION_CANCELLATION_TOKEN_INVALID',
        'The deletion cancellation link is invalid or expired',
        statusCode: 400,
      );
    }
    final currentStatus = current?['status'];
    if (current == null || !_isCancellableStatus(currentStatus)) {
      return current ??
          <String, Object?>{'scope': 'organization', 'status': 'not_requested'};
    }
    final cancellationStartedAt = _now();
    final stop = current['billingStop'];
    final stopMap = stop is Map<String, Object?> ? stop : null;
    final cancellationPending = <String, Object?>{
      ...current,
      'status': 'cancellation_pending',
      'stage': 'cancellation',
      'cancellationStartedAt': cancellationStartedAt.toIso8601String(),
      'updatedAt': cancellationStartedAt.toIso8601String(),
      if (stopMap?['status'] != 'not_active')
        'billingCancellationRetained': true,
    };
    if (!await _replaceRequestIfStatus(
      organizationDeletionRequestCollection,
      id,
      currentStatus as String,
      cancellationPending,
    )) {
      return await store.readJson(organizationDeletionRequestCollection, id) ??
          current;
    }
    late final int restoredCredentialCount;
    try {
      restoredCredentialCount = await _restoreOrganizationCredentials(
        organizationId,
        id,
        _now(),
      );
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
    } on Object catch (error) {
      final retryable = <String, Object?>{
        ...cancellationPending,
        'lastError': _safeError(error),
        'attempt':
            (cancellationPending['attempt'] is int
                ? cancellationPending['attempt']! as int
                : 0) +
            1,
        'updatedAt': _now().toIso8601String(),
      };
      await _replaceRequestIfStatus(
        organizationDeletionRequestCollection,
        id,
        'cancellation_pending',
        retryable,
      );
      rethrow;
    }
    final updated = <String, Object?>{
      ...cancellationPending,
      'status': 'cancelled',
      'stage': 'cancelled',
      'cancelledAt': _now().toIso8601String(),
      'updatedAt': _now().toIso8601String(),
    };
    if (!await _replaceRequestIfStatus(
      organizationDeletionRequestCollection,
      id,
      'cancellation_pending',
      updated,
    )) {
      return await store.readJson(organizationDeletionRequestCollection, id) ??
          cancellationPending;
    }
    await _audit(
      requestId: requestId,
      organizationId: organizationId,
      actorId: actorId,
      action: 'organization.deletion.cancelled',
      resourceType: 'organization_deletion_request',
      resourceId: id,
      metadata: <String, Object?>{
        'credentials_restored': restoredCredentialCount,
        'billing_cancellation_retained':
            updated['billingCancellationRetained'] == true,
      },
    );
    if (user.email.isNotEmpty) {
      await _notify(
        key: 'organization.deletion.cancelled',
        stableKey: _deletionNotificationStableKey(updated, 'cancelled'),
        recipient: user.email,
        organizationId: organizationId,
        entityType: 'organization_deletion_request',
        entityId: id,
        correlationId: requestId,
        variables: <String, Object?>{
          'organization': organizationId,
          'message': stopMap?['status'] == 'not_active'
              ? 'Your Cloud organization deletion request was cancelled.'
              : 'Your Cloud organization deletion request was cancelled. Provider renewal remains in its current scheduled state; it was not silently reactivated.',
        },
      );
    }
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
    final normalizedNow = (now ?? _now()).toUtc();
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
    if (status == 'cancellation_pending') return current;
    if (status == 'processing') {
      final leaseExpiresAt = _parseTime(current['processingLeaseExpiresAt']);
      if (leaseExpiresAt != null && leaseExpiresAt.isAfter(normalizedNow)) {
        return current;
      }
    }
    if (status == 'policy_decision_required') {
      return <String, Object?>{
        ...current,
        'blocker': 'POLICY_DECISION_REQUIRED: deletion_grace_period',
      };
    }
    var ready = current;
    if (scope == 'organization' &&
        (status == 'billing_pending' ||
            (status == 'failed' && current['stage'] == 'billing'))) {
      try {
        ready = await _retryOrganizationBilling(
          current,
          normalizedNow: normalizedNow,
          expectedStatus: status as String,
        );
      } on Object catch (error) {
        final failed = <String, Object?>{
          ...current,
          'status': 'failed',
          'stage': 'billing',
          'lastError': _safeError(error),
          'attempt':
              (current['attempt'] is int ? current['attempt']! as int : 0) + 1,
          'updatedAt': normalizedNow.toIso8601String(),
        };
        if (await _replaceRequestIfStatus(
          collection,
          requestId,
          status as String,
          failed,
        )) {
          await _audit(
            requestId: requestId,
            organizationId: current['organizationId']! as String,
            actorId: 'hyfens:deletion-worker',
            action: 'organization.deletion.failed',
            resourceType: 'organization_deletion_request',
            resourceId: requestId,
            metadata: <String, Object?>{
              'stage': 'billing',
              'error': _safeError(error),
            },
          );
          return failed;
        }
        return await store.readJson(collection, requestId) ?? current;
      }
      if (ready['status'] == 'policy_decision_required') return ready;
      if (ready['status'] == 'billing_pending') return ready;
    }
    final readyStatus = ready['status'];
    // The persisted processing boundary is the authority. The grace-period
    // field remains a compatibility fallback for records created before the
    // working-day schedule was added.
    final processingAt = _parseTime(
      ready['processingAt'] ?? ready['gracePeriodEndsAt'],
    );
    if (readyStatus == 'grace_period' &&
        processingAt != null &&
        processingAt.isAfter(normalizedNow)) {
      return ready;
    }
    final expectedProcessingLeaseId = readyStatus == 'processing'
        ? ready['processingLeaseId'] as String?
        : null;
    final expectProcessingLeaseAbsent =
        readyStatus == 'processing' && expectedProcessingLeaseId == null;
    final processingLeaseId = _newProcessingLeaseId(requestId, normalizedNow);
    final processing = <String, Object?>{
      ...ready,
      'status': 'processing',
      'stage': 'processing',
      'attempt': (ready['attempt'] is int ? ready['attempt']! as int : 0) + 1,
      'processingLeaseId': processingLeaseId,
      'processingLeaseExpiresAt': normalizedNow
          .add(_deletionProcessingLease)
          .toIso8601String(),
      'updatedAt': normalizedNow.toIso8601String(),
    };
    if (!await _replaceRequestIfStatus(
      collection,
      requestId,
      readyStatus as String,
      processing,
      expectedProcessingLeaseId: expectedProcessingLeaseId,
      expectProcessingLeaseAbsent: expectProcessingLeaseAbsent,
    )) {
      return await store.readJson(collection, requestId) ?? ready;
    }
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
          ? await _processAccount(
              processing,
              normalizedNow,
              requestId,
              processingLeaseId,
            )
          : await _processOrganization(
              processing,
              normalizedNow,
              requestId,
              maxItems,
              processingLeaseId,
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
      if (!await _replaceRequestIfStatus(
        collection,
        requestId,
        'processing',
        failed,
        expectedProcessingLeaseId: processingLeaseId,
      )) {
        return await store.readJson(collection, requestId) ?? processing;
      }
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
    final normalizedNow = (now ?? _now()).toUtc();
    for (final request in requests) {
      await _serialized(
        () => _processScheduledReminders(request, normalizedNow),
      );
    }
    final due = requests
        .where((request) {
          final status = request['status'];
          if (status != 'grace_period' &&
              status != 'failed' &&
              status != 'processing' &&
              status != 'billing_pending') {
            return false;
          }
          final at = _parseTime(
            request['processingAt'] ?? request['gracePeriodEndsAt'],
          );
          if (status == 'failed' || status == 'billing_pending') return true;
          if (status == 'processing') {
            final lease = _parseTime(request['processingLeaseExpiresAt']);
            return lease == null || !lease.isAfter(normalizedNow);
          }
          return at != null && !at.isAfter(normalizedNow);
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

  Future<void> _processScheduledReminders(
    Map<String, Object?> request,
    DateTime now,
  ) async {
    if (request['status'] != 'grace_period' ||
        request['ownershipRequiredOrganizations'] is List &&
            (request['ownershipRequiredOrganizations']! as List).isNotEmpty) {
      return;
    }
    final processingAt = _parseTime(request['processingAt']);
    if (processingAt != null && !processingAt.isAfter(now)) return;
    final id = request['id'];
    final scope = request['scope'];
    if (id is! String || (scope != 'account' && scope != 'organization')) {
      return;
    }
    final collection = scope == 'account'
        ? accountDeletionRequestCollection
        : organizationDeletionRequestCollection;
    final userId = scope == 'account'
        ? request['userId']
        : request['requestedBy'];
    if (userId is! String) return;
    final user = await store.readJson('users', userId);
    final recipient = user?['email'];
    if (recipient is! String || recipient.isEmpty) return;
    final organization = request['organizationId'] is String
        ? await store.readJson(
            'organizations',
            request['organizationId']! as String,
          )
        : null;
    final organizationName = organization?['name'] as String?;
    final milestones = <String, DateTime?>{
      'day5': _parseTime(request['workingDay5At']),
      'day7': _parseTime(request['workingDay7At']),
    };
    for (final entry in milestones.entries) {
      final milestone = entry.key;
      final due = entry.value;
      if (due == null || due.isAfter(now)) continue;
      final notifiedKey = milestone == 'day5'
          ? 'workingDay5NotifiedAt'
          : 'workingDay7NotifiedAt';
      if (request[notifiedKey] != null) continue;
      final latest = await store.readJson(collection, id);
      if (latest == null ||
          latest['status'] != 'grace_period' ||
          latest[notifiedKey] != null) {
        return;
      }
      request = latest;
      final key = scope == 'account'
          ? 'account.deletion.reminder_$milestone'
          : 'organization.deletion.reminder_$milestone';
      final workingDay = milestone == 'day5'
          ? 'Day 5 of ${policy.graceWorkingDays} working days; ${policy.graceWorkingDays! - 5} working days remain'
          : 'Day 7 of ${policy.graceWorkingDays} working days; staged processing begins next working day';
      final variables = await _deletionNotificationVariables(
        request: request,
        organization: organizationName,
        workingDay: workingDay,
        message: milestone == 'day5'
            ? 'Your deletion request is still pending. Your account remains restricted but recoverable during the grace period.'
            : 'This is the final reminder. Staged deletion begins after the grace period unless you cancel the request securely.',
        includeCancelLink: true,
      );
      final queued = await _notify(
        key: key,
        stableKey: _deletionNotificationStableKey(
          request,
          'reminder:$milestone',
        ),
        recipient: recipient,
        organizationId: request['organizationId'] as String?,
        entityType: '${scope}_deletion_request',
        entityId: id,
        correlationId: id,
        variables: variables,
      );
      if (!queued) continue;
      final updated = <String, Object?>{
        ...request,
        notifiedKey: now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };
      if (await _replaceRequestIfStatus(
        collection,
        id,
        'grace_period',
        updated,
      )) {
        request = updated;
        await _audit(
          requestId: id,
          organizationId:
              request['organizationId'] as String? ??
              await _auditOrganizationForUser(userId),
          actorId: 'hyfens:deletion-worker',
          action: key,
          resourceType: '${scope}_deletion_request',
          resourceId: '$id:reminder:$milestone',
          metadata: <String, Object?>{
            'working_day': workingDay,
            'notification_key': key,
          },
        );
      }
    }
  }

  Future<Map<String, Object?>> _retryOrganizationBilling(
    Map<String, Object?> request, {
    required DateTime normalizedNow,
    required String expectedStatus,
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
    final newlyRevokedCredentialIds = await _revokeOrganizationCredentials(
      organizationId,
      normalizedNow,
      requestId,
    );
    final priorCredentialIds = request['organizationCredentialRevocationIds'];
    final revokedCredentialIds = <String>{
      if (priorCredentialIds is List) ...priorCredentialIds.whereType<String>(),
      ...newlyRevokedCredentialIds,
    };
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
      'organizationCredentialsRevoked': revokedCredentialIds.length,
      'organizationCredentialRevocationIds': revokedCredentialIds.toList(
        growable: false,
      ),
      'updatedAt': normalizedNow.toIso8601String(),
      'attempt':
          (request['attempt'] is int ? request['attempt']! as int : 0) + 1,
    };
    if (!await _replaceRequestIfStatus(
      organizationDeletionRequestCollection,
      requestId,
      expectedStatus,
      updated,
    )) {
      return await store.readJson(
            organizationDeletionRequestCollection,
            requestId,
          ) ??
          request;
    }
    return updated;
  }

  Future<Map<String, Object?>> _processAccount(
    Map<String, Object?> request,
    DateTime now,
    String requestId,
    String processingLeaseId,
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
        if (!await _replaceRequestIfStatus(
          accountDeletionRequestCollection,
          requestId,
          'processing',
          blocked,
          expectedProcessingLeaseId: processingLeaseId,
        )) {
          return await store.readJson(
                accountDeletionRequestCollection,
                requestId,
              ) ??
              request;
        }
        return blocked;
      }
      await _revokeAccountCredentials(request, now);
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
      'processingLeaseId': null,
      'processingLeaseExpiresAt': null,
    };
    if (!await _replaceRequestIfStatus(
      accountDeletionRequestCollection,
      requestId,
      'processing',
      completed,
      expectedProcessingLeaseId: processingLeaseId,
    )) {
      return await store.readJson(
            accountDeletionRequestCollection,
            requestId,
          ) ??
          request;
    }
    await _audit(
      requestId: requestId,
      organizationId: _auditOrganization(user),
      actorId: 'hyfens:deletion-worker',
      action: 'account.deletion.completed',
      resourceType: 'account_deletion_request',
      resourceId: requestId,
      metadata: const <String, Object?>{'retention': 'classified'},
    );
    await _notify(
      key: 'account.deleted',
      stableKey: _deletionNotificationStableKey(request, 'completed'),
      recipient: user.email,
      organizationId: _auditOrganization(user) == 'system'
          ? null
          : _auditOrganization(user),
      entityType: 'account_deletion_request',
      entityId: requestId,
      correlationId: requestId,
      variables: const <String, Object?>{
        'message': 'Your account deletion is complete.',
      },
    );
    return completed;
  }

  Future<Map<String, Object?>> _processOrganization(
    Map<String, Object?> request,
    DateTime now,
    String requestId,
    int maxItems,
    String processingLeaseId,
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
        final storageId = collection == 'credentials' ? value['tokenHash'] : id;
        if (storageId is! String) {
          throw const FormatException('Credential storage ID is invalid');
        }
        await deletion.deleteJson(collection, storageId);
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
        'processingLeaseId': null,
        'processingLeaseExpiresAt': null,
      };
      if (!await _replaceRequestIfStatus(
        organizationDeletionRequestCollection,
        requestId,
        'processing',
        progress,
        expectedProcessingLeaseId: processingLeaseId,
      )) {
        return await store.readJson(
              organizationDeletionRequestCollection,
              requestId,
            ) ??
            request;
      }
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
      'processingLeaseId': null,
      'processingLeaseExpiresAt': null,
    };
    if (!await _replaceRequestIfStatus(
      organizationDeletionRequestCollection,
      requestId,
      'processing',
      completed,
      expectedProcessingLeaseId: processingLeaseId,
    )) {
      return await store.readJson(
            organizationDeletionRequestCollection,
            requestId,
          ) ??
          request;
    }
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
    final ownerId = request['requestedBy'];
    final owner = ownerId is String
        ? await store.readJson('users', ownerId)
        : null;
    if (owner?['email'] is String) {
      await _notify(
        key: 'organization.deleted',
        stableKey: _deletionNotificationStableKey(request, 'completed'),
        recipient: owner!['email']! as String,
        organizationId: organizationId,
        entityType: 'organization_deletion_request',
        entityId: requestId,
        correlationId: requestId,
        variables: <String, Object?>{
          'organization': 'Deleted organization',
          'message': 'Deletion of your organization and its customer-owned data is complete. Required evidence remains according to policy.',
        },
      );
    }
    return completed;
  }

  Future<bool> _notify({
    required String key,
    required String stableKey,
    required String recipient,
    required String? organizationId,
    required String entityType,
    required String entityId,
    required String correlationId,
    required Map<String, Object?> variables,
    bool sensitive = true,
  }) async {
    final service = notifications;
    if (service == null) return false;
    try {
      await service.enqueue(
        NotificationEvent(
          key: key,
          stableKey: stableKey,
          recipientEmails: <String>[recipient],
          variables: variables,
          occurredAt: _now(),
          organizationId: organizationId,
          entityType: entityType,
          entityId: entityId,
          source: 'deletion',
          correlationId: correlationId,
          sensitive: sensitive,
        ),
      );
      return true;
    } on Object catch (error) {
      await _audit(
        requestId: correlationId,
        organizationId: organizationId ?? 'system',
        actorId: 'hyfens:notification-worker',
        action: 'notification.enqueue_failed',
        resourceType: entityType,
        resourceId: entityId,
        metadata: <String, Object?>{'error': error.runtimeType.toString()},
      );
      return false;
    }
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

  Future<bool> _replaceRequestIfStatus(
    String collection,
    String id,
    String expectedStatus,
    Map<String, Object?> value, {
    String? expectedProcessingLeaseId,
    bool expectProcessingLeaseAbsent = false,
  }) async {
    final atomic = store;
    if (atomic case final DeletionRequestStateStore stateStore) {
      return stateStore.compareAndSetDeletionRequestStatus(
        collection: collection,
        id: id,
        expectedStatus: expectedStatus,
        value: value,
        expectedProcessingLeaseId: expectedProcessingLeaseId,
        expectProcessingLeaseAbsent: expectProcessingLeaseAbsent,
      );
    }
    final current = await store.readJson(collection, id);
    if (current == null || current['status'] != expectedStatus) return false;
    final currentLease = current['processingLeaseId'];
    if (expectedProcessingLeaseId != null &&
        currentLease != expectedProcessingLeaseId) {
      return false;
    }
    if (expectProcessingLeaseAbsent && currentLease != null) return false;
    await store.replaceJson(collection, id, value);
    return true;
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
      policy.isConfigured ? 'grace_period' : 'policy_decision_required';

  bool _isCancellableStatus(Object? status) =>
      status == 'ownership_resolution_required' ||
      status == 'policy_decision_required' ||
      status == 'grace_period' ||
      status == 'cancellation_pending';

  Map<String, Object?> _scheduleFields(
    Map<String, Object?> existing,
    DateTime verifiedAt, {
    bool enabled = true,
    bool allowCancellation = true,
  }) {
    final priorProcessing = existing['status'] == 'cancelled'
        ? null
        : existing['processingAt'];
    if (priorProcessing is String) {
      return <String, Object?>{
        'gracePeriodEndsAt': existing['gracePeriodEndsAt'] ?? priorProcessing,
        'workingDay5At': existing['workingDay5At'],
        'workingDay7At': existing['workingDay7At'],
        'workingDay5Date': existing['workingDay5Date'],
        'workingDay7Date': existing['workingDay7Date'],
        'processingAt': priorProcessing,
        'processingDate': existing['processingDate'],
        'businessTimeZone':
            existing['businessTimeZone'] ?? policy.businessTimeZone,
        'businessDayPolicy': existing['businessDayPolicy'] ?? 'monday_friday',
        'businessHolidays': existing['businessHolidays'] ?? policy.holidayDates,
        'cancellationAllowed':
            existing['cancellationAllowed'] ?? allowCancellation,
        'restriction': existing['restriction'] ?? 'Only deletion status, privacy information, billing status, and cancellation remain available during the grace period.',
      };
    }
    final workingDays = policy.graceWorkingDays;
    if (!enabled || workingDays == null) {
      return <String, Object?>{
        'gracePeriodEndsAt': null,
        'workingDay5At': null,
        'workingDay7At': null,
        'workingDay5Date': null,
        'workingDay7Date': null,
        'processingAt': null,
        'processingDate': null,
        'businessTimeZone': policy.businessTimeZone,
        'businessDayPolicy': 'monday_friday',
        'businessHolidays': policy.holidayDates,
        'cancellationAllowed': allowCancellation,
        'restriction': null,
      };
    }
    final calendar = policy.calendar;
    final processingAt = calendar.workingDayAt(
      verifiedAt: verifiedAt,
      workingDay: workingDays + 1,
    );
    final day5 = workingDays >= 5
        ? calendar.workingDayAt(verifiedAt: verifiedAt, workingDay: 5)
        : null;
    final day7 = workingDays >= 7
        ? calendar.workingDayAt(verifiedAt: verifiedAt, workingDay: 7)
        : null;
    return <String, Object?>{
      'gracePeriodEndsAt': processingAt.toIso8601String(),
      'workingDay5At': day5?.toIso8601String(),
      'workingDay7At': day7?.toIso8601String(),
      'processingAt': processingAt.toIso8601String(),
      'workingDay5Date': day5 == null ? null : calendar.dateKeyAt(day5),
      'workingDay7Date': day7 == null ? null : calendar.dateKeyAt(day7),
      'processingDate': calendar.dateKeyAt(processingAt),
      'businessTimeZone': policy.businessTimeZone,
      'businessDayPolicy': 'monday_friday',
      'businessHolidays': policy.holidayDates,
      'cancellationAllowed': true,
      'restriction': 'Only deletion status, privacy information, billing status, and cancellation remain available during the grace period.',
    };
  }

  Future<Map<String, Object?>> _deletionNotificationVariables({
    required Map<String, Object?> request,
    required String message,
    String? organization,
    String? workingDay,
    required bool includeCancelLink,
  }) async {
    final variables = <String, Object?>{
      if (organization != null) 'organization': organization,
      'message': message,
      'effective_at':
          request['processingDate'] ??
          request['processingAt'] ??
          request['gracePeriodEndsAt'],
      'processing_at':
          request['processingDate'] ??
          request['processingAt'] ??
          request['gracePeriodEndsAt'],
      if (workingDay != null) 'working_day': workingDay,
      'business_timezone':
          request['businessTimeZone'] ?? policy.businessTimeZone,
      'restriction': 'Only deletion status, privacy information, billing status, and cancellation remain available during the grace period.',
      'billing_message': 'No automatic refund is created by account or organization deletion. Future renewal is stopped through the billing lifecycle; current paid access follows that state.',
    };
    final auth = humanAuth;
    final renderer = notifications?.renderer;
    final requestId = request['id'];
    final scope = request['scope'];
    if (includeCancelLink &&
        auth != null &&
        renderer != null &&
        requestId is String &&
        (scope == 'account' || scope == 'organization')) {
      final issued = await auth.issueDeletionCancellationToken(
        userId: scope == 'account'
            ? request['userId']! as String
            : request['requestedBy']! as String,
        deletionRequestId: requestId,
        deletionRequestGeneration: request['requestGeneration'] as int?,
        scope: scope! as String,
        organizationId: request['organizationId'] as String?,
        expiresAt: _parseTime(request['processingAt']),
      );
      variables['action_url'] = renderer.marketingOrigin
          .replace(
            path: '/account-deletion',
            queryParameters: <String, String>{
              'cancel_token': issued['token']! as String,
            },
          )
          .toString();
      variables['action_label'] = 'Cancel deletion';
    }
    return variables;
  }

  String _deletionNotificationStableKey(
    Map<String, Object?> request,
    String event,
  ) {
    final id = request['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Deletion request ID is invalid');
    }
    final generation = request['requestGeneration'];
    final normalizedGeneration = generation is int && generation > 0
        ? generation
        : 1;
    return '$id:g$normalizedGeneration:$event';
  }

  Future<List<String>> _credentialIdsForUser(String userId) async {
    final issued = <String>{};
    for (final value in await store.listJson('audit')) {
      if (value['action'] != 'credential.issue' || value['actorId'] != userId) {
        continue;
      }
      final resourceId = value['resourceId'];
      if (resourceId is String) issued.add(resourceId);
    }
    return issued.toList(growable: false);
  }

  Future<void> _revokeAccountCredentials(
    Map<String, Object?> request,
    DateTime now,
  ) async {
    final rawIds = request['blockedCredentialIds'];
    if (rawIds is! List) return;
    final ids = rawIds.whereType<String>().toSet();
    if (ids.isEmpty) return;
    for (final value in await store.listJson('credentials')) {
      if (!ids.contains(value['id']) || value['revoked'] == true) continue;
      final storageId = value['tokenHash'];
      if (storageId is! String) continue;
      await store.replaceJson('credentials', storageId, <String, Object?>{
        ...value,
        'revoked': true,
        'revokedAt': now.toIso8601String(),
      });
    }
  }

  Future<List<String>> _revokeOrganizationCredentials(
    String organizationId,
    DateTime now,
    String deletionRequestId,
  ) async {
    final revoked = <String>[];
    for (final value in await store.listJson('credentials')) {
      if (value['organizationId'] != organizationId ||
          value['revoked'] == true) {
        continue;
      }
      final storageId = value['tokenHash'];
      if (storageId is! String) continue;
      await store.replaceJson('credentials', storageId, <String, Object?>{
        ...value,
        'revoked': true,
        'revokedAt': now.toIso8601String(),
        'deletionRevocationRequestId': deletionRequestId,
      });
      final credentialId = value['id'];
      if (credentialId is String) revoked.add(credentialId);
    }
    return List.unmodifiable(revoked);
  }

  Future<int> _restoreOrganizationCredentials(
    String organizationId,
    String deletionRequestId,
    DateTime now,
  ) async {
    var restored = 0;
    for (final value in await store.listJson('credentials')) {
      if (value['organizationId'] != organizationId ||
          value['revoked'] != true ||
          value['deletionRevocationRequestId'] != deletionRequestId) {
        continue;
      }
      final storageId = value['tokenHash'];
      if (storageId is! String) continue;
      await store.replaceJson('credentials', storageId, <String, Object?>{
        ...value,
        'revoked': false,
        'revokedAt': null,
        'deletionRevocationRequestId': null,
        'updatedAt': now.toIso8601String(),
      });
      restored++;
    }
    return restored;
  }

  int _requestGeneration(Map<String, Object?>? existing) {
    final prior = existing?['requestGeneration'];
    final generation = prior is int && prior > 0 ? prior : 1;
    return existing?['status'] == 'cancelled' ? generation + 1 : generation;
  }

  bool _isAccountDeletionRestrictedStatus(Object? status) =>
      status == 'ownership_resolution_required' ||
      status == 'policy_decision_required' ||
      status == 'grace_period' ||
      status == 'processing' ||
      status == 'failed' ||
      status == 'cancellation_pending';

  String _newProcessingLeaseId(String requestId, DateTime now) {
    final entropy = List<int>.generate(
      16,
      (_) => _random.nextInt(256),
      growable: false,
    );
    return 'dlease_${sha256Hex(<int>[...utf8.encode('$requestId:${now.microsecondsSinceEpoch}:'), ...entropy]).substring(0, 32)}';
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
