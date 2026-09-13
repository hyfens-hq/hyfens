import 'dart:convert';
import 'dart:math';

import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'persistence.dart';

const String platformStaffInvitationCollection = 'platform_staff_invitations';
const String platformStaffAccessReviewCollection =
    'platform_staff_access_reviews';
const String platformStaffIdempotencyScope = 'platform_staff_access';
const String platformStaffOrganizationId = 'platform';
const Duration defaultPlatformStaffInvitationTtl = Duration(days: 7);
const Duration defaultPlatformStaffCoolOff = Duration(hours: 24);

/// Durable, bounded governance for managed Platform Console staff.
///
/// A browser can request an invitation or access change, but it cannot submit
/// arbitrary capabilities or make that change effective immediately. One
/// operator creates the request, another eligible operator approves it, and a
/// short cool-off gives the organization time to notice and revoke an unsafe
/// change. The existing JSON store and audit chain remain the persistence and
/// evidence boundaries.
final class PlatformStaffAccessService {
  PlatformStaffAccessService({
    required this.store,
    required this.auth,
    Random? random,
    DateTime Function()? clock,
    this.invitationTtl = defaultPlatformStaffInvitationTtl,
    this.coolOff = defaultPlatformStaffCoolOff,
  }) : _random = random ?? Random.secure(),
       _clock = clock ?? (() => DateTime.now().toUtc()) {
    if (invitationTtl <= Duration.zero ||
        invitationTtl > const Duration(days: 30)) {
      throw ArgumentError.value(
        invitationTtl,
        'invitationTtl',
        'must be positive and at most 30 days',
      );
    }
    if (coolOff <= Duration.zero || coolOff > const Duration(days: 7)) {
      throw ArgumentError.value(
        coolOff,
        'coolOff',
        'must be positive and at most 7 days',
      );
    }
  }

  final ControlPlaneStore store;
  final HumanAuthService auth;
  final Random _random;
  final DateTime Function() _clock;
  final Duration invitationTtl;
  final Duration coolOff;
  Future<void> _tail = Future<void>.value();

  Future<List<Map<String, Object?>>> listInvitations() => _serialized(() async {
    final values = await store.listJson(platformStaffInvitationCollection);
    final invitations = values.map(_safeInvitation).toList(growable: false);
    invitations.sort(
      (left, right) =>
          '${right['requestedAt']}'.compareTo('${left['requestedAt']}'),
    );
    return List.unmodifiable(invitations);
  });

  Future<List<Map<String, Object?>>> listAccessReviews() => _serialized(
    () async {
      final values = await store.listJson(platformStaffAccessReviewCollection);
      final reviews = values.map(_safeReview).toList(growable: false);
      reviews.sort(
        (left, right) =>
            '${right['requestedAt']}'.compareTo('${left['requestedAt']}'),
      );
      return List.unmodifiable(reviews);
    },
  );

  Future<Map<String, Object?>> createInvitation({
    required String email,
    required String role,
    required String reason,
    required String actorId,
    required String requestId,
    required String idempotencyKey,
  }) => _serialized(() async {
    final normalizedEmail = _email(email);
    final normalizedRole = _role(role);
    final normalizedReason = _reason(reason);
    final requestDigest = _digest(<String, Object?>{
      'operation': 'invite',
      'email': normalizedEmail,
      'role': normalizedRole,
      'reason': normalizedReason,
    });
    final existing = await _idempotentResult(idempotencyKey, requestDigest);
    if (existing != null) return existing;

    final now = _now();
    final invitationId = _randomId('inv_');
    final reviewId = _randomId('review_');
    final token = _randomToken();
    final invitation = <String, Object?>{
      'id': invitationId,
      'email': normalizedEmail,
      'role': normalizedRole,
      'status': 'pending_review',
      'reviewId': reviewId,
      'requestedBy': actorId,
      'requestedAt': now.toIso8601String(),
      'expiresAt': now.add(invitationTtl).toIso8601String(),
      'tokenHash': sha256Hex(utf8.encode(token)),
    };
    final review = _reviewValue(
      id: reviewId,
      targetType: 'invitation',
      targetId: invitationId,
      email: normalizedEmail,
      role: normalizedRole,
      active: true,
      requestedBy: actorId,
      reason: normalizedReason,
      requestedAt: now,
    );
    await store.createJson(
      platformStaffInvitationCollection,
      invitationId,
      invitation,
    );
    await store.createJson(
      platformStaffAccessReviewCollection,
      reviewId,
      review,
    );
    await _appendAudit(
      action: 'platform.staff.invitation.requested',
      resourceType: 'platform_staff_invitation',
      resourceId: invitationId,
      actorId: actorId,
      requestId: requestId,
      operationKey: idempotencyKey,
      metadata: <String, Object?>{
        'email': normalizedEmail,
        'role': normalizedRole,
        'reason': normalizedReason,
        'status': 'pending_review',
      },
    );
    await _appendAudit(
      action: 'platform.staff.access_review.requested',
      resourceType: 'platform_staff_access_review',
      resourceId: reviewId,
      actorId: actorId,
      requestId: requestId,
      operationKey: idempotencyKey,
      metadata: <String, Object?>{
        'target_type': 'invitation',
        'target_id': invitationId,
        'role': normalizedRole,
        'reason': normalizedReason,
        'status': 'pending_review',
      },
    );
    final result = <String, Object?>{
      'invitation': _safeInvitation(invitation),
      'review': _safeReview(review),
      // The raw token is returned only on the first response. It is never
      // written to the idempotency record, list projection, or audit trail.
      'token': token,
    };
    await _saveIdempotency(idempotencyKey, requestDigest, result);
    return result;
  });

  Future<Map<String, Object?>> requestAccessChange({
    required String userId,
    required String role,
    required bool active,
    required String reason,
    required String actorId,
    required String requestId,
    required String idempotencyKey,
  }) => _serialized(() async {
    final normalizedRole = _role(role);
    final normalizedReason = _reason(reason);
    final userValue = await store.readJson('users', userId);
    if (userValue == null) _staffNotFound();
    final user = HumanUserRecord.fromJson(userValue);
    final membership = user.memberships.cast<HumanMembership?>().firstWhere(
      (item) =>
          item!.audience == platformAuthorizationAudience &&
          item.managedPlatformStaff,
      orElse: () => null,
    );
    if (membership == null) _staffNotFound();
    final requestDigest = _digest(<String, Object?>{
      'operation': 'access_change',
      'userId': userId,
      'role': normalizedRole,
      'active': active,
      'reason': normalizedReason,
    });
    final existing = await _idempotentResult(idempotencyKey, requestDigest);
    if (existing != null) return existing;
    final now = _now();
    final reviewId = _randomId('review_');
    final review = _reviewValue(
      id: reviewId,
      targetType: 'membership',
      targetId: userId,
      userId: userId,
      email: user.email,
      role: normalizedRole,
      active: active,
      requestedBy: actorId,
      reason: normalizedReason,
      requestedAt: now,
    );
    await _supersedePendingReviews(
      userId: userId,
      exceptId: reviewId,
      now: now,
    );
    await store.createJson(
      platformStaffAccessReviewCollection,
      reviewId,
      review,
    );
    await _appendAudit(
      action: 'platform.staff.access_change.requested',
      resourceType: 'platform_staff_access_review',
      resourceId: reviewId,
      actorId: actorId,
      requestId: requestId,
      operationKey: idempotencyKey,
      metadata: <String, Object?>{
        'user_id': userId,
        'email': user.email,
        'role': normalizedRole,
        'active': active,
        'reason': normalizedReason,
        'status': 'pending_review',
      },
    );
    final result = <String, Object?>{'review': _safeReview(review)};
    await _saveIdempotency(idempotencyKey, requestDigest, result);
    return result;
  });

  Future<Map<String, Object?>> approveAccessReview({
    required String reviewId,
    required String actorId,
    required String reason,
    required String requestId,
    required String idempotencyKey,
  }) => _serialized(() async {
    final normalizedReason = _reason(reason);
    final value = await store.readJson(
      platformStaffAccessReviewCollection,
      reviewId,
    );
    if (value == null) _reviewNotFound();
    final status = _string(value, 'status');
    final requestedBy = _string(value, 'requestedBy');
    if (status != 'pending_review') {
      throw const ControlPlaneException(
        'PLATFORM_STAFF_REVIEW_NOT_PENDING',
        'This access review is no longer awaiting approval',
        statusCode: 409,
      );
    }
    if (requestedBy == actorId) {
      throw const ControlPlaneException(
        'PLATFORM_STAFF_MAKER_CHECKER_REQUIRED',
        'The requester cannot approve the same platform access change',
        statusCode: 403,
      );
    }
    final requestDigest = _digest(<String, Object?>{
      'operation': 'approve',
      'reviewId': reviewId,
      'reason': normalizedReason,
    });
    final existing = await _idempotentResult(idempotencyKey, requestDigest);
    if (existing != null) return existing;
    final now = _now();
    final updated = <String, Object?>{
      ...value,
      'status': 'cooling_off',
      'approvedBy': actorId,
      'approvalReason': normalizedReason,
      'approvedAt': now.toIso8601String(),
      'effectiveAt': now.add(coolOff).toIso8601String(),
    };
    await store.replaceJson(
      platformStaffAccessReviewCollection,
      reviewId,
      updated,
    );
    final targetType = _string(value, 'targetType');
    final targetId = _string(value, 'targetId');
    if (targetType == 'invitation') {
      final invitation = await store.readJson(
        platformStaffInvitationCollection,
        targetId,
      );
      if (invitation != null) {
        await store.replaceJson(
          platformStaffInvitationCollection,
          targetId,
          <String, Object?>{...invitation, 'status': 'cooling_off'},
        );
      }
    }
    await _appendAudit(
      action: 'platform.staff.access_review.approved',
      resourceType: 'platform_staff_access_review',
      resourceId: reviewId,
      actorId: actorId,
      requestId: requestId,
      operationKey: idempotencyKey,
      metadata: <String, Object?>{
        'target_type': targetType,
        'target_id': targetId,
        'reason': normalizedReason,
        'status': 'cooling_off',
        'effective_at': updated['effectiveAt'],
      },
    );
    final result = <String, Object?>{'review': _safeReview(updated)};
    await _saveIdempotency(idempotencyKey, requestDigest, result);
    return result;
  });

  Future<Map<String, Object?>> revokeInvitation({
    required String invitationId,
    required String actorId,
    required String reason,
    required String requestId,
    required String idempotencyKey,
  }) => _serialized(() async {
    final normalizedReason = _reason(reason);
    final requestDigest = _digest(<String, Object?>{
      'operation': 'revoke_invitation',
      'invitationId': invitationId,
      'reason': normalizedReason,
    });
    final existing = await _idempotentResult(idempotencyKey, requestDigest);
    if (existing != null) return existing;
    final invitation = await store.readJson(
      platformStaffInvitationCollection,
      invitationId,
    );
    if (invitation == null) _invitationNotFound();
    final currentStatus = _string(invitation, 'status');
    if (currentStatus == 'accepted' || currentStatus == 'revoked') {
      final result = <String, Object?>{
        'invitation': _safeInvitation(invitation),
      };
      await _saveIdempotency(idempotencyKey, requestDigest, result);
      return result;
    }
    final updated = <String, Object?>{
      ...invitation,
      'status': 'revoked',
      'revokedAt': _now().toIso8601String(),
    };
    await store.replaceJson(
      platformStaffInvitationCollection,
      invitationId,
      updated,
    );
    final reviewId = invitation['reviewId'];
    if (reviewId is String) {
      final review = await store.readJson(
        platformStaffAccessReviewCollection,
        reviewId,
      );
      if (review != null &&
          const <String>{
            'pending_review',
            'cooling_off',
          }.contains(review['status'])) {
        await store.replaceJson(
          platformStaffAccessReviewCollection,
          reviewId,
          <String, Object?>{
            ...review,
            'status': 'cancelled',
            'cancelledAt': _now().toIso8601String(),
            'cancellationReason': normalizedReason,
          },
        );
      }
    }
    await _appendAudit(
      action: 'platform.staff.invitation.revoked',
      resourceType: 'platform_staff_invitation',
      resourceId: invitationId,
      actorId: actorId,
      requestId: requestId,
      operationKey: idempotencyKey,
      metadata: <String, Object?>{
        'email': invitation['email'],
        'reason': normalizedReason,
        'status': 'revoked',
      },
    );
    final result = <String, Object?>{'invitation': _safeInvitation(updated)};
    await _saveIdempotency(idempotencyKey, requestDigest, result);
    return result;
  });

  Future<Map<String, Object?>> revokeStaffSessions({
    required String userId,
    required String actorId,
    required String reason,
    required String requestId,
    required String idempotencyKey,
  }) => _serialized(() async {
    final normalizedReason = _reason(reason);
    final requestDigest = _digest(<String, Object?>{
      'operation': 'revoke_sessions',
      'userId': userId,
      'reason': normalizedReason,
    });
    final existing = await _idempotentResult(idempotencyKey, requestDigest);
    if (existing != null) return existing;
    final revoked = await auth.revokePlatformStaffSessions(userId: userId);
    await _appendAudit(
      action: 'platform.staff.sessions.revoked',
      resourceType: 'human_user',
      resourceId: userId,
      actorId: actorId,
      requestId: requestId,
      operationKey: idempotencyKey,
      metadata: <String, Object?>{
        'reason': normalizedReason,
        'revoked_sessions': revoked,
      },
    );
    final result = <String, Object?>{
      'userId': userId,
      'revokedSessions': revoked,
    };
    await _saveIdempotency(idempotencyKey, requestDigest, result);
    return result;
  });

  /// Applies approved reviews whose cool-off has elapsed. A scheduled worker
  /// may call this method, and the HTTP adapter also invokes it at bounded
  /// platform boundaries so an accepted change cannot remain indefinitely
  /// pending when a separate scheduler is unavailable.
  Future<int> processDueReviews({
    String requestId = 'platform-staff-review-worker',
  }) => _serialized(() async {
    var processed = 0;
    final now = _now();
    final values = await store.listJson(platformStaffAccessReviewCollection);
    for (final value in values) {
      if (value['status'] != 'cooling_off') continue;
      final effectiveAt = DateTime.tryParse('${value['effectiveAt']}')?.toUtc();
      if (effectiveAt == null || effectiveAt.isAfter(now)) continue;
      try {
        final targetType = _string(value, 'targetType');
        if (targetType == 'membership') {
          await auth.applyManagedPlatformStaff(
            userId: _string(value, 'userId'),
            role: _string(value, 'role'),
            active: value['active'] == true,
          );
        } else if (targetType == 'invitation') {
          final invitation = await store.readJson(
            platformStaffInvitationCollection,
            _string(value, 'targetId'),
          );
          if (invitation == null || invitation['status'] == 'revoked') {
            await _finishReview(
              value,
              status: 'cancelled',
              now: now,
              requestId: requestId,
              reason: 'Invitation was revoked before cool-off elapsed',
            );
            continue;
          }
          await store.replaceJson(
            platformStaffInvitationCollection,
            _string(value, 'targetId'),
            <String, Object?>{...invitation, 'status': 'ready'},
          );
        } else {
          throw const FormatException('Unsupported platform staff target');
        }
        await _finishReview(
          value,
          status: 'effective',
          now: now,
          requestId: requestId,
        );
        processed++;
      } on Object catch (error) {
        await _finishReview(
          value,
          status: 'failed',
          now: now,
          requestId: requestId,
          reason: _safeFailure(error),
        );
      }
      // Keep a worker invocation bounded even if a corrupted store has a
      // large backlog. A later tick resumes at the next record.
      if (processed >= 25) break;
    }
    return processed;
  });

  Future<Map<String, Object?>> acceptInvitation({
    required String token,
    required String password,
  }) => _serialized(() async {
    final normalizedToken = token.trim();
    if (normalizedToken.length < 32 || normalizedToken.length > 512) {
      _invitationTokenInvalid();
    }
    final tokenHash = sha256Hex(utf8.encode(normalizedToken));
    Map<String, Object?>? invitation;
    for (final value in await store.listJson(
      platformStaffInvitationCollection,
    )) {
      if (value['tokenHash'] == tokenHash) {
        invitation = value;
        break;
      }
    }
    if (invitation == null ||
        !const <String>{'ready', 'effective'}.contains(invitation['status']) ||
        DateTime.tryParse('${invitation['expiresAt']}')?.isAfter(_now()) !=
            true) {
      _invitationTokenInvalid();
    }
    final confirmedInvitation = invitation;
    final invitationId = _string(confirmedInvitation, 'id');
    final existing = (await store.listJson('users'))
        .map(HumanUserRecord.fromJson)
        .where((user) => user.email == _string(confirmedInvitation, 'email'))
        .toList(growable: false);
    final user = existing.isEmpty
        ? await auth.createManagedPlatformStaff(
            email: _string(confirmedInvitation, 'email'),
            password: password,
            role: _string(confirmedInvitation, 'role'),
          )
        : await auth.addManagedPlatformStaffMembership(
            userId: existing.single.id,
            role: _string(confirmedInvitation, 'role'),
          );
    await store.replaceJson(
      platformStaffInvitationCollection,
      invitationId,
      <String, Object?>{
        ...confirmedInvitation,
        'status': 'accepted',
        'acceptedAt': _now().toIso8601String(),
        'tokenHash': null,
      },
    );
    return <String, Object?>{
      'status': 'accepted',
      'userId': user.id,
      'role': _string(confirmedInvitation, 'role'),
    };
  });

  Future<void> _supersedePendingReviews({
    required String userId,
    required String exceptId,
    required DateTime now,
  }) async {
    for (final value in await store.listJson(
      platformStaffAccessReviewCollection,
    )) {
      if (value['targetType'] != 'membership' || value['targetId'] != userId)
        continue;
      if (!const <String>{
        'pending_review',
        'cooling_off',
      }.contains(value['status']))
        continue;
      final id = _string(value, 'id');
      if (id == exceptId) continue;
      await store.replaceJson(
        platformStaffAccessReviewCollection,
        id,
        <String, Object?>{
          ...value,
          'status': 'superseded',
          'supersededAt': now.toIso8601String(),
        },
      );
    }
  }

  Future<void> _finishReview(
    Map<String, Object?> value, {
    required String status,
    required DateTime now,
    required String requestId,
    String? reason,
  }) async {
    final reviewId = _string(value, 'id');
    final current = await store.readJson(
      platformStaffAccessReviewCollection,
      reviewId,
    );
    if (current == null || current['status'] != 'cooling_off') return;
    await store.replaceJson(
      platformStaffAccessReviewCollection,
      reviewId,
      <String, Object?>{
        ...current,
        'status': status,
        'appliedAt': now.toIso8601String(),
        if (reason != null) 'failureReason': reason,
      },
    );
    await _appendAudit(
      action: 'platform.staff.access_review.$status',
      resourceType: 'platform_staff_access_review',
      resourceId: reviewId,
      actorId: 'system_platform_staff_worker',
      requestId: requestId,
      operationKey: reviewId,
      metadata: <String, Object?>{
        'target_type': current['targetType'],
        'target_id': current['targetId'],
        'status': status,
        if (reason != null) 'reason': reason,
      },
    );
  }

  Future<Map<String, Object?>?> _idempotentResult(
    String key,
    String requestDigest,
  ) async {
    final value = await store.readIdempotency(
      platformStaffIdempotencyScope,
      key,
    );
    if (value == null) return null;
    if (value['requestDigest'] != requestDigest) {
      throw const ControlPlaneException(
        'IDEMPOTENCY_CONFLICT',
        'Idempotency key was already used for a different staff access change',
        statusCode: 409,
      );
    }
    final result = value['result'];
    if (result is! Map) {
      throw const ControlPlaneException(
        'STORAGE_CORRUPT',
        'Stored staff access idempotency result is invalid',
        statusCode: 500,
      );
    }
    return result.map<String, Object?>((key, value) => MapEntry('$key', value));
  }

  Future<void> _saveIdempotency(
    String key,
    String requestDigest,
    Map<String, Object?> result,
  ) async {
    try {
      await store.createIdempotency(
        platformStaffIdempotencyScope,
        key,
        <String, Object?>{
          'requestDigest': requestDigest,
          'result': _withoutRawToken(result),
          'createdAt': _now().toIso8601String(),
        },
      );
    } on StorageConflict {
      final concurrent = await store.readIdempotency(
        platformStaffIdempotencyScope,
        key,
      );
      if (concurrent == null || concurrent['requestDigest'] != requestDigest)
        rethrow;
    }
  }

  Map<String, Object?> _withoutRawToken(Map<String, Object?> value) =>
      <String, Object?>{
        for (final entry in value.entries)
          if (entry.key != 'token') entry.key: entry.value,
      };

  Map<String, Object?> _reviewValue({
    required String id,
    required String targetType,
    required String targetId,
    String? userId,
    required String email,
    required String role,
    required bool active,
    required String requestedBy,
    required String reason,
    required DateTime requestedAt,
  }) => <String, Object?>{
    'id': id,
    'targetType': targetType,
    'targetId': targetId,
    if (userId != null) 'userId': userId,
    'email': email,
    'role': role,
    'active': active,
    'status': 'pending_review',
    'requestedBy': requestedBy,
    'reason': reason,
    'requestedAt': requestedAt.toIso8601String(),
  };

  Map<String, Object?> _safeInvitation(Map<String, Object?> value) =>
      <String, Object?>{
        for (final entry in value.entries)
          if (entry.key != 'tokenHash') entry.key: entry.value,
        'active': const <String>{
          'pending_review',
          'cooling_off',
          'ready',
          'effective',
        }.contains(value['status']),
      };

  Map<String, Object?> _safeReview(Map<String, Object?> value) =>
      <String, Object?>{
        for (final entry in value.entries)
          if (entry.key != 'tokenHash') entry.key: entry.value,
      };

  Future<void> _appendAudit({
    required String action,
    required String resourceType,
    required String resourceId,
    required String actorId,
    required String requestId,
    required String operationKey,
    required Map<String, Object?> metadata,
  }) async {
    final auditId =
        'aud_platform_staff_${sha256Hex(utf8.encode('$action:$resourceId:$operationKey')).substring(0, 32)}';
    if (await store.readJson('audit', auditId) != null) return;
    final value = AuditRecord(
      id: auditId,
      requestId: requestId,
      organizationId: platformStaffOrganizationId,
      actorId: actorId,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      result: 'SUCCESS',
      metadata: <String, Object?>{
        'audience': platformAuthorizationAudience,
        'actor_type': actorId.startsWith('system_')
            ? 'system'
            : 'platform_operator',
        'correlation_id': requestId,
        'causation_id': operationKey,
        ...metadata,
      },
      createdAt: _now(),
    ).toJson();
    try {
      await store.appendAudit(auditId, value);
    } on StorageConflict {
      if (await store.readJson('audit', auditId) == null) rethrow;
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  DateTime _now() => _clock().toUtc();

  String _randomId(String prefix) =>
      '$prefix${List<int>.generate(18, (_) => _random.nextInt(256)).map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';

  String _randomToken() =>
      'hfi_${base64Url.encode(List<int>.generate(32, (_) => _random.nextInt(256))).replaceAll('=', '')}';

  static String _digest(Map<String, Object?> value) =>
      sha256Digest(utf8.encode(canonicalJson(value)));

  static String _email(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.length > 320 ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      throw const ControlPlaneException(
        'INVALID_PLATFORM_STAFF_EMAIL',
        'Platform staff email must be a valid mailbox address',
        statusCode: 422,
      );
    }
    return normalized;
  }

  static String _role(String value) {
    final normalized = value.trim();
    if (!managedPlatformStaffRoles.contains(normalized)) {
      throw const ControlPlaneException(
        'INVALID_PLATFORM_STAFF_ROLE',
        'The platform staff role is not supported',
        statusCode: 422,
      );
    }
    return normalized;
  }

  static String _reason(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 1000) {
      throw const ControlPlaneException(
        'CHANGE_REASON_REQUIRED',
        'A non-empty reason is required for platform staff changes',
        statusCode: 422,
      );
    }
    return normalized;
  }

  static String _string(Map<String, Object?> value, String key) {
    final item = value[key];
    if (item is! String || item.isEmpty)
      throw const FormatException('Invalid platform staff record');
    return item;
  }

  static String _safeFailure(Object error) => error is ControlPlaneException
      ? error.code
      : 'PLATFORM_STAFF_PROCESSING_FAILED';

  static Never _staffNotFound() => throw const ControlPlaneException(
    'PLATFORM_STAFF_NOT_FOUND',
    'The platform staff identity was not found',
    statusCode: 404,
  );

  static Never _reviewNotFound() => throw const ControlPlaneException(
    'PLATFORM_STAFF_REVIEW_NOT_FOUND',
    'The platform access review was not found',
    statusCode: 404,
  );

  static Never _invitationNotFound() => throw const ControlPlaneException(
    'PLATFORM_STAFF_INVITATION_NOT_FOUND',
    'The platform staff invitation was not found',
    statusCode: 404,
  );

  static Never _invitationTokenInvalid() => throw const ControlPlaneException(
    'PLATFORM_STAFF_INVITATION_INVALID',
    'The platform staff invitation is invalid or expired',
    statusCode: 400,
  );
}
