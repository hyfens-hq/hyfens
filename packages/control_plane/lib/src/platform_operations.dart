import 'dart:async';
import 'dart:convert';

import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'persistence.dart';

const String platformOperationsOwnerCollection = 'platform_operations_owners';
const String platformOperationsIdempotencyScope =
    'platform_operations_ownership';
const String platformOperationsOrganizationId = 'platform';

const List<String> platformOperationsOwnerRoles = <String>[
  'email_delivery',
  'payments_webhooks',
  'refunds',
  'enterprise_inquiries',
  'deletion_object_cleanup',
  'backup_restore',
];

const String defaultPlatformOperationsOwnerEmail = 'admin@hyfens.com';

final class PlatformOperationsOwner {
  PlatformOperationsOwner({
    required String role,
    required String? ownerEmail,
    required String status,
    required int revision,
    required this.createdAt,
    required this.updatedAt,
  }) : role = _role(role),
       ownerEmail = ownerEmail == null ? null : _email(ownerEmail),
       status = _status(status),
       revision = _revision(revision) {
    if (this.status == 'active' && this.ownerEmail == null) {
      throw const FormatException('Active operations owner requires an email');
    }
  }

  final String role;
  final String? ownerEmail;
  final String status;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get active => status == 'active';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': role,
    'role': role,
    'ownerEmail': ownerEmail,
    'status': status,
    'revision': revision,
    'organizationId': platformOperationsOrganizationId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory PlatformOperationsOwner.fromJson(Map<String, Object?> value) {
    final id = value['id'];
    final role = value['role'];
    if (id is! String || role is! String || id != role) {
      throw const FormatException('Invalid operations owner identity');
    }
    final ownerEmail = value['ownerEmail'];
    if (ownerEmail != null && ownerEmail is! String) {
      throw const FormatException('Invalid operations owner email');
    }
    final revision = value['revision'];
    final createdAt = value['createdAt'];
    final updatedAt = value['updatedAt'];
    if (revision is! int ||
        createdAt is! String ||
        updatedAt is! String ||
        DateTime.tryParse(createdAt) == null ||
        DateTime.tryParse(updatedAt) == null) {
      throw const FormatException('Invalid operations owner timestamps');
    }
    return PlatformOperationsOwner(
      role: role,
      ownerEmail: ownerEmail as String?,
      status: value['status'] as String? ?? 'active',
      revision: revision,
      createdAt: DateTime.parse(createdAt).toUtc(),
      updatedAt: DateTime.parse(updatedAt).toUtc(),
    );
  }

  PlatformOperationsOwner copyWith({
    String? ownerEmail,
    bool clearOwnerEmail = false,
    required String status,
    required int revision,
    required DateTime updatedAt,
  }) => PlatformOperationsOwner(
    role: role,
    ownerEmail: clearOwnerEmail ? null : ownerEmail ?? this.ownerEmail,
    status: status,
    revision: revision,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  static String _role(String value) {
    if (!platformOperationsOwnerRoles.contains(value)) {
      throw const ControlPlaneException(
        'INVALID_OPERATION_ROLE',
        'The operations owner role is not supported',
        statusCode: 422,
      );
    }
    return value;
  }

  static String _email(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.length > 320 ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      throw const ControlPlaneException(
        'INVALID_OPERATION_OWNER',
        'Operations owner must be a valid mailbox address',
        statusCode: 422,
      );
    }
    return normalized;
  }

  static String _status(String value) {
    if (value != 'active' && value != 'removed') {
      throw const FormatException('Invalid operations owner status');
    }
    return value;
  }

  static int _revision(int value) {
    if (value <= 0)
      throw const FormatException('Invalid operations owner revision');
    return value;
  }
}

/// Bounded platform-only ownership registry for launch-critical operations.
///
/// It deliberately reuses the existing JSON store and immutable audit chain.
/// Owner changes are not tenant mutations and therefore use the synthetic
/// `platform` audit organization with an explicit platform audience.
final class PlatformOperationsOwnershipService {
  PlatformOperationsOwnershipService({
    required this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final ControlPlaneStore store;
  final DateTime Function() _clock;
  Future<void> _tail = Future<void>.value();

  Future<void> ensureSeeded() => _serialized(() async {
    for (final role in platformOperationsOwnerRoles) {
      final existing = await store.readJson(
        platformOperationsOwnerCollection,
        role,
      );
      if (existing != null) {
        PlatformOperationsOwner.fromJson(existing);
        continue;
      }
      final now = _clock().toUtc();
      final owner = PlatformOperationsOwner(
        role: role,
        ownerEmail: defaultPlatformOperationsOwnerEmail,
        status: 'active',
        revision: 1,
        createdAt: now,
        updatedAt: now,
      );
      await store.createJson(
        platformOperationsOwnerCollection,
        role,
        owner.toJson(),
      );
      await _appendAudit(
        action: 'platform.operations_owner.seeded',
        role: role,
        actorId: 'system_bootstrap',
        requestId: 'platform-operations-owner-seed',
        operationKey: 'seed:$role',
        oldOwnerEmail: null,
        newOwnerEmail: owner.ownerEmail,
        reason: 'Initial managed Cloud ownership bootstrap',
        revision: owner.revision,
      );
    }
  });

  Future<List<PlatformOperationsOwner>> list() => _serialized(() async {
    final values = await store.listJson(platformOperationsOwnerCollection);
    final owners = values
        .map(PlatformOperationsOwner.fromJson)
        .toList(growable: false);
    owners.sort((left, right) => left.role.compareTo(right.role));
    return List.unmodifiable(owners);
  });

  Future<PlatformOperationsOwner> add({
    required String role,
    required String ownerEmail,
    required String reason,
    required String actorId,
    required String requestId,
    required String idempotencyKey,
  }) => _mutate(
    operation: 'add',
    role: role,
    ownerEmail: ownerEmail,
    reason: reason,
    actorId: actorId,
    requestId: requestId,
    idempotencyKey: idempotencyKey,
  );

  Future<PlatformOperationsOwner> update({
    required String role,
    required String ownerEmail,
    required String reason,
    required String actorId,
    required String requestId,
    required String idempotencyKey,
  }) => _mutate(
    operation: 'update',
    role: role,
    ownerEmail: ownerEmail,
    reason: reason,
    actorId: actorId,
    requestId: requestId,
    idempotencyKey: idempotencyKey,
  );

  Future<PlatformOperationsOwner> remove({
    required String role,
    required String reason,
    required String actorId,
    required String requestId,
    required String idempotencyKey,
  }) => _mutate(
    operation: 'remove',
    role: role,
    ownerEmail: null,
    reason: reason,
    actorId: actorId,
    requestId: requestId,
    idempotencyKey: idempotencyKey,
  );

  Future<PlatformOperationsOwner> _mutate({
    required String operation,
    required String role,
    required String? ownerEmail,
    required String reason,
    required String actorId,
    required String requestId,
    required String idempotencyKey,
  }) => _serialized(() async {
    final normalizedRole = _normalizeRole(role);
    final normalizedReason = _reason(reason);
    final normalizedEmail = ownerEmail == null ? null : _email(ownerEmail);
    if (operation != 'remove' && normalizedEmail == null) {
      throw const ControlPlaneException(
        'INVALID_OPERATION_OWNER',
        'An owner mailbox is required for this operation',
        statusCode: 422,
      );
    }
    final requestBody = <String, Object?>{
      'operation': operation,
      'role': normalizedRole,
      'ownerEmail': normalizedEmail,
      'reason': normalizedReason,
    };
    final requestDigest = sha256Digest(utf8.encode(canonicalJson(requestBody)));
    final existingIdempotency = await store.readIdempotency(
      platformOperationsIdempotencyScope,
      idempotencyKey,
    );
    if (existingIdempotency != null) {
      if (existingIdempotency['requestDigest'] != requestDigest) {
        throw const ControlPlaneException(
          'IDEMPOTENCY_CONFLICT',
          'Idempotency key was already used for a different ownership change',
          statusCode: 409,
        );
      }
      final result = existingIdempotency['result'];
      if (result is! Map) {
        throw const ControlPlaneException(
          'STORAGE_CORRUPT',
          'Stored ownership idempotency result is invalid',
          statusCode: 500,
        );
      }
      return PlatformOperationsOwner.fromJson(
        result.map<String, Object?>((key, value) => MapEntry('$key', value)),
      );
    }

    final currentValue = await store.readJson(
      platformOperationsOwnerCollection,
      normalizedRole,
    );
    final current = currentValue == null
        ? null
        : PlatformOperationsOwner.fromJson(currentValue);
    final next = switch (operation) {
      'add' => _addNext(current, normalizedRole, normalizedEmail!),
      'update' => _updateNext(current, normalizedEmail!),
      'remove' => _removeNext(current),
      _ => throw const ControlPlaneException(
        'INVALID_OPERATION',
        'Ownership operation is not supported',
        statusCode: 422,
      ),
    };
    if (current == null) {
      await store.createJson(
        platformOperationsOwnerCollection,
        normalizedRole,
        next.toJson(),
      );
    } else {
      await store.replaceJson(
        platformOperationsOwnerCollection,
        normalizedRole,
        next.toJson(),
      );
    }
    await _appendAudit(
      action: switch (operation) {
        'add' => 'platform.operations_owner.added',
        'update' => 'platform.operations_owner.updated',
        'remove' => 'platform.operations_owner.removed',
        _ => 'platform.operations_owner.changed',
      },
      role: normalizedRole,
      actorId: actorId,
      requestId: requestId,
      operationKey: idempotencyKey,
      oldOwnerEmail: current?.ownerEmail,
      newOwnerEmail: next.ownerEmail,
      reason: normalizedReason,
      revision: next.revision,
    );
    final idempotencyValue = <String, Object?>{
      'requestDigest': requestDigest,
      'result': next.toJson(),
      'createdAt': _clock().toUtc().toIso8601String(),
    };
    try {
      await store.createIdempotency(
        platformOperationsIdempotencyScope,
        idempotencyKey,
        idempotencyValue,
      );
    } on StorageConflict {
      final concurrent = await store.readIdempotency(
        platformOperationsIdempotencyScope,
        idempotencyKey,
      );
      if (concurrent == null || concurrent['requestDigest'] != requestDigest) {
        rethrow;
      }
    }
    return next;
  });

  PlatformOperationsOwner _addNext(
    PlatformOperationsOwner? current,
    String role,
    String ownerEmail,
  ) {
    if (current?.active == true) {
      throw const ControlPlaneException(
        'OPERATION_OWNER_EXISTS',
        'An active owner already exists for this operation',
        statusCode: 409,
      );
    }
    final now = _clock().toUtc();
    return PlatformOperationsOwner(
      role: role,
      ownerEmail: ownerEmail,
      status: 'active',
      revision: (current?.revision ?? 0) + 1,
      createdAt: current?.createdAt ?? now,
      updatedAt: now,
    );
  }

  PlatformOperationsOwner _updateNext(
    PlatformOperationsOwner? current,
    String ownerEmail,
  ) {
    if (current == null || !current.active) {
      throw const ControlPlaneException(
        'OPERATION_OWNER_NOT_FOUND',
        'No active owner exists for this operation',
        statusCode: 404,
      );
    }
    return current.copyWith(
      ownerEmail: ownerEmail,
      status: 'active',
      revision: current.revision + 1,
      updatedAt: _clock().toUtc(),
    );
  }

  PlatformOperationsOwner _removeNext(PlatformOperationsOwner? current) {
    if (current == null || !current.active) {
      throw const ControlPlaneException(
        'OPERATION_OWNER_NOT_FOUND',
        'No active owner exists for this operation',
        statusCode: 404,
      );
    }
    return current.copyWith(
      clearOwnerEmail: true,
      status: 'removed',
      revision: current.revision + 1,
      updatedAt: _clock().toUtc(),
    );
  }

  Future<void> _appendAudit({
    required String action,
    required String role,
    required String actorId,
    required String requestId,
    required String operationKey,
    required String? oldOwnerEmail,
    required String? newOwnerEmail,
    required String reason,
    required int revision,
  }) async {
    final auditId =
        'aud_platform_owner_${sha256Hex(utf8.encode('$action:$role:$operationKey')).substring(0, 32)}';
    if (await store.readJson('audit', auditId) != null) return;
    final value = AuditRecord(
      id: auditId,
      requestId: requestId,
      organizationId: platformOperationsOrganizationId,
      actorId: actorId,
      action: action,
      resourceType: 'platform_operations_owner',
      resourceId: role,
      result: 'SUCCESS',
      metadata: <String, Object?>{
        'audience': platformAuthorizationAudience,
        'actor_type': actorId == 'system_bootstrap'
            ? 'system_bootstrap'
            : 'platform_operator',
        'role': role,
        'old_owner_email': oldOwnerEmail,
        'new_owner_email': newOwnerEmail,
        'reason': reason,
        'revision': revision,
        'correlation_id': requestId,
        'causation_id': operationKey,
      },
      createdAt: _clock().toUtc(),
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

  static String _normalizeRole(String value) {
    final normalized = value.trim();
    if (!platformOperationsOwnerRoles.contains(normalized)) {
      throw const ControlPlaneException(
        'INVALID_OPERATION_ROLE',
        'The operations owner role is not supported',
        statusCode: 422,
      );
    }
    return normalized;
  }

  static String _email(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.length > 320 ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      throw const ControlPlaneException(
        'INVALID_OPERATION_OWNER',
        'Operations owner must be a valid mailbox address',
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
        'A non-empty reason is required for ownership changes',
        statusCode: 422,
      );
    }
    if (normalized.contains(RegExp(r'[\u0000\r\n]'))) {
      throw const ControlPlaneException(
        'INVALID_CHANGE_REASON',
        'The ownership change reason contains unsupported characters',
        statusCode: 422,
      );
    }
    return normalized;
  }
}
