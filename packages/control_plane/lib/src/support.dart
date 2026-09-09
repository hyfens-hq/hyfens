import 'encoding.dart';
import 'human_auth.dart';

const Set<String> supportCaseStatuses = <String>{
  'OPEN',
  'IN_PROGRESS',
  'WAITING_FOR_CUSTOMER',
  'WAITING_FOR_HYFENS',
  'RESOLVED',
  'CLOSED',
};

const Set<String> supportCasePriorities = <String>{
  'LOW',
  'NORMAL',
  'HIGH',
  'URGENT',
};

const String customerSupportVisibility = 'customer';
const String platformInternalSupportVisibility = 'platform_internal';

const Set<String> organizationInvitationStatuses = <String>{
  'PENDING',
  'ACCEPTED',
  'REVOKED',
  'EXPIRED',
};

const Set<String> invitationDeliveryStatuses = <String>{
  'PENDING',
  'DELIVERED',
  'FAILED',
};

/// Delivery is deliberately an adapter. The control plane persists only a
/// token hash; a configured Cloud/SMTP adapter receives the one-time token
/// after the invitation record has been committed.
final class InvitationDeliveryRequest {
  const InvitationDeliveryRequest({
    required this.kind,
    required this.invitationId,
    required this.email,
    required this.token,
    required this.expiresAt,
    required this.role,
    required this.capabilities,
  });

  final String kind;
  final String invitationId;
  final String email;
  final String token;
  final DateTime expiresAt;
  final String role;
  final Set<String> capabilities;
}

abstract interface class OrganizationInvitationDelivery {
  Future<void> deliver(InvitationDeliveryRequest request);
}

final class NoopOrganizationInvitationDelivery
    implements OrganizationInvitationDelivery {
  const NoopOrganizationInvitationDelivery();

  @override
  Future<void> deliver(InvitationDeliveryRequest request) async {}
}

final class SupportCaseRecord {
  SupportCaseRecord({
    required String id,
    required String organizationId,
    String? applicationId,
    String? environmentId,
    required String subject,
    required String description,
    String category = 'general',
    String priority = 'NORMAL',
    String status = 'OPEN',
    required String createdBy,
    String? assignedTo,
    required this.createdAt,
    DateTime? updatedAt,
    DateTime? closedAt,
    DateTime? lastCustomerActivity,
    DateTime? lastStaffActivity,
  }) : id = requireOpaqueId(id, 'support case ID'),
       organizationId = requireOpaqueId(
         organizationId,
         'support case organization ID',
       ),
       applicationId = applicationId == null
           ? null
           : requireOpaqueId(applicationId, 'support case application ID'),
       environmentId = environmentId == null
           ? null
           : requireOpaqueId(environmentId, 'support case environment ID'),
       subject = _text(subject, 'support case subject', 200),
       description = _text(description, 'support case description', 8000),
       category = _text(category, 'support case category', 64),
       priority = _enumValue(priority, supportCasePriorities, 'priority'),
       status = _enumValue(status, supportCaseStatuses, 'status'),
       createdBy = requireNonEmpty(createdBy, 'support case creator'),
       assignedTo = assignedTo == null
           ? null
           : requireNonEmpty(assignedTo, 'support case assignee'),
       updatedAt = (updatedAt ?? createdAt).toUtc(),
       closedAt = closedAt?.toUtc(),
       lastCustomerActivity = (lastCustomerActivity ?? createdAt).toUtc(),
       lastStaffActivity = lastStaffActivity?.toUtc() {
    if (status == 'CLOSED' && this.closedAt == null) {
      throw const FormatException('Closed support case is missing closedAt');
    }
  }

  final String id;
  final String organizationId;
  final String? applicationId;
  final String? environmentId;
  final String subject;
  final String description;
  final String category;
  final String priority;
  final String status;
  final String createdBy;
  final String? assignedTo;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? closedAt;
  final DateTime lastCustomerActivity;
  final DateTime? lastStaffActivity;

  SupportCaseRecord copyWith({
    String? subject,
    String? description,
    String? category,
    String? priority,
    String? status,
    String? assignedTo,
    bool clearAssignedTo = false,
    DateTime? updatedAt,
    DateTime? closedAt,
    DateTime? lastCustomerActivity,
    DateTime? lastStaffActivity,
  }) => SupportCaseRecord(
    id: id,
    organizationId: organizationId,
    applicationId: applicationId,
    environmentId: environmentId,
    subject: subject ?? this.subject,
    description: description ?? this.description,
    category: category ?? this.category,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    createdBy: createdBy,
    assignedTo: clearAssignedTo ? null : assignedTo ?? this.assignedTo,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    closedAt: closedAt ?? this.closedAt,
    lastCustomerActivity: lastCustomerActivity ?? this.lastCustomerActivity,
    lastStaffActivity: lastStaffActivity ?? this.lastStaffActivity,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'subject': subject,
    'description': description,
    'category': category,
    'priority': priority,
    'status': status,
    'createdBy': createdBy,
    'assignedTo': assignedTo,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'closedAt': closedAt?.toUtc().toIso8601String(),
    'lastCustomerActivity': lastCustomerActivity.toUtc().toIso8601String(),
    'lastStaffActivity': lastStaffActivity?.toUtc().toIso8601String(),
  };

  static SupportCaseRecord fromJson(Map<String, Object?> value) =>
      SupportCaseRecord(
        id: value['id']! as String,
        organizationId: value['organizationId']! as String,
        applicationId: value['applicationId'] as String?,
        environmentId: value['environmentId'] as String?,
        subject: value['subject']! as String,
        description: value['description']! as String,
        category: value['category'] as String? ?? 'general',
        priority: value['priority'] as String? ?? 'NORMAL',
        status: value['status'] as String? ?? 'OPEN',
        createdBy: value['createdBy']! as String,
        assignedTo: value['assignedTo'] as String?,
        createdAt: DateTime.parse(value['createdAt']! as String),
        updatedAt:
            _timestamp(value['updatedAt']) ??
            DateTime.parse(value['createdAt']! as String),
        closedAt: _timestamp(value['closedAt']),
        lastCustomerActivity:
            _timestamp(value['lastCustomerActivity']) ??
            DateTime.parse(value['createdAt']! as String),
        lastStaffActivity: _timestamp(value['lastStaffActivity']),
      );
}

final class SupportMessageRecord {
  SupportMessageRecord({
    required String id,
    required String caseId,
    required String organizationId,
    required String authorId,
    required String authorAudience,
    required String body,
    required String visibility,
    required this.createdAt,
  }) : id = requireOpaqueId(id, 'support message ID'),
       caseId = requireOpaqueId(caseId, 'support message case ID'),
       organizationId = requireOpaqueId(
         organizationId,
         'support message organization ID',
       ),
       authorId = requireNonEmpty(authorId, 'support message author'),
       authorAudience = _enumValue(authorAudience, const <String>{
         customerAuthorizationAudience,
         platformAuthorizationAudience,
       }, 'author audience'),
       body = _text(body, 'support message body', 8000),
       visibility = _enumValue(visibility, const <String>{
         customerSupportVisibility,
         platformInternalSupportVisibility,
       }, 'support message visibility');

  final String id;
  final String caseId;
  final String organizationId;
  final String authorId;
  final String authorAudience;
  final String body;
  final String visibility;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'caseId': caseId,
    'organizationId': organizationId,
    'authorId': authorId,
    'authorAudience': authorAudience,
    'body': body,
    'visibility': visibility,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  Map<String, Object?> toPublicJson({required bool includeVisibility}) =>
      <String, Object?>{
        'id': id,
        'caseId': caseId,
        'organizationId': organizationId,
        'authorId': authorId,
        'authorAudience': authorAudience,
        'body': body,
        if (includeVisibility) 'visibility': visibility,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  static SupportMessageRecord fromJson(Map<String, Object?> value) =>
      SupportMessageRecord(
        id: value['id']! as String,
        caseId: value['caseId']! as String,
        organizationId: value['organizationId']! as String,
        authorId: value['authorId']! as String,
        authorAudience: value['authorAudience']! as String,
        body: value['body']! as String,
        visibility: value['visibility']! as String,
        createdAt: DateTime.parse(value['createdAt']! as String),
      );
}

final class OrganizationInvitationRecord {
  OrganizationInvitationRecord({
    required String id,
    required String organizationId,
    required String email,
    required String role,
    required Set<String> capabilities,
    required String tokenHash,
    required String createdBy,
    required DateTime createdAt,
    required DateTime expiresAt,
    String status = 'PENDING',
    String? acceptedBy,
    DateTime? acceptedAt,
    DateTime? revokedAt,
    String deliveryStatus = 'PENDING',
    DateTime? deliveryFailedAt,
  }) : id = requireOpaqueId(id, 'invitation ID'),
       organizationId = requireOpaqueId(
         organizationId,
         'invitation organization ID',
       ),
       email = requireNonEmpty(email, 'invitation email', maxLength: 320),
       role = requireNonEmpty(role, 'invitation role', maxLength: 64),
       capabilities = Set.unmodifiable(capabilities),
       tokenHash = requireNonEmpty(tokenHash, 'invitation token hash'),
       createdBy = requireNonEmpty(createdBy, 'invitation creator'),
       createdAt = createdAt.toUtc(),
       expiresAt = expiresAt.toUtc(),
       status = _enumValue(
         status,
         organizationInvitationStatuses,
         'invitation status',
       ),
       acceptedBy = acceptedBy == null
           ? null
           : requireNonEmpty(acceptedBy, 'invitation accepter'),
       acceptedAt = acceptedAt?.toUtc(),
       revokedAt = revokedAt?.toUtc(),
       deliveryStatus = _enumValue(
         deliveryStatus,
         invitationDeliveryStatuses,
         'invitation delivery status',
       ),
       deliveryFailedAt = deliveryFailedAt?.toUtc();

  final String id;
  final String organizationId;
  final String email;
  final String role;
  final Set<String> capabilities;
  final String tokenHash;
  final String createdBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String status;
  final String? acceptedBy;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;
  final String deliveryStatus;
  final DateTime? deliveryFailedAt;

  String statusAt(DateTime now) {
    if (status == 'ACCEPTED' || acceptedAt != null) return 'ACCEPTED';
    if (status == 'REVOKED' || revokedAt != null) return 'REVOKED';
    if (!expiresAt.isAfter(now.toUtc())) return 'EXPIRED';
    return 'PENDING';
  }

  bool activeAt(DateTime now) => statusAt(now) == 'PENDING';

  OrganizationInvitationRecord copyWith({
    String? status,
    String? acceptedBy,
    DateTime? acceptedAt,
    DateTime? revokedAt,
    String? deliveryStatus,
    DateTime? deliveryFailedAt,
  }) => OrganizationInvitationRecord(
    id: id,
    organizationId: organizationId,
    email: email,
    role: role,
    capabilities: capabilities,
    tokenHash: tokenHash,
    createdBy: createdBy,
    createdAt: createdAt,
    expiresAt: expiresAt,
    status: status ?? this.status,
    acceptedBy: acceptedBy ?? this.acceptedBy,
    acceptedAt: acceptedAt ?? this.acceptedAt,
    revokedAt: revokedAt ?? this.revokedAt,
    deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    deliveryFailedAt: deliveryFailedAt ?? this.deliveryFailedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'email': email,
    'role': role,
    'capabilities': capabilities.toList()..sort(),
    'tokenHash': tokenHash,
    'createdBy': createdBy,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'status': status,
    'acceptedBy': acceptedBy,
    'acceptedAt': acceptedAt?.toUtc().toIso8601String(),
    'revokedAt': revokedAt?.toUtc().toIso8601String(),
    'deliveryStatus': deliveryStatus,
    'deliveryFailedAt': deliveryFailedAt?.toUtc().toIso8601String(),
  };

  Map<String, Object?> toMetadataJson({DateTime? now}) => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'email': email,
    'role': role,
    'capabilities': capabilities.toList()..sort(),
    'createdBy': createdBy,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'status': statusAt((now ?? DateTime.now()).toUtc()),
    'acceptedBy': acceptedBy,
    'acceptedAt': acceptedAt?.toUtc().toIso8601String(),
    'revokedAt': revokedAt?.toUtc().toIso8601String(),
    'deliveryStatus': deliveryStatus,
    'active': statusAt((now ?? DateTime.now()).toUtc()) == 'PENDING',
  };

  /// Public invitation metadata is intentionally smaller than the
  /// organization-admin projection. It is safe to return before an account
  /// exists and never reveals creator, accepter, or authorization data.
  Map<String, Object?> toPublicMetadataJson({DateTime? now}) =>
      <String, Object?>{
        'email': email,
        'role': role,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'status': statusAt((now ?? DateTime.now()).toUtc()),
        'active': statusAt((now ?? DateTime.now()).toUtc()) == 'PENDING',
      };

  static OrganizationInvitationRecord fromJson(Map<String, Object?> value) {
    final rawCapabilities = value['capabilities'];
    if (rawCapabilities is! List<Object?> ||
        rawCapabilities.any((item) => item is! String)) {
      throw const FormatException('Invalid invitation capabilities');
    }
    return OrganizationInvitationRecord(
      id: value['id']! as String,
      organizationId: value['organizationId']! as String,
      email: value['email']! as String,
      role: value['role']! as String,
      capabilities: rawCapabilities.cast<String>().toSet(),
      tokenHash: value['tokenHash']! as String,
      createdBy: value['createdBy']! as String,
      createdAt: DateTime.parse(value['createdAt']! as String),
      expiresAt: DateTime.parse(value['expiresAt']! as String),
      status: value['status'] as String? ?? 'PENDING',
      acceptedBy: value['acceptedBy'] as String?,
      acceptedAt: _timestamp(value['acceptedAt']),
      revokedAt: _timestamp(value['revokedAt']),
      deliveryStatus: value['deliveryStatus'] as String? ?? 'DELIVERED',
      deliveryFailedAt: _timestamp(value['deliveryFailedAt']),
    );
  }
}

final class IssuedOrganizationInvitation {
  const IssuedOrganizationInvitation({
    required this.record,
    required this.token,
  });

  final OrganizationInvitationRecord record;
  final String token;

  Map<String, Object?> toJson() => <String, Object?>{
    ...record.toMetadataJson(),
    'token': token,
  };
}

final class PlatformStaffInvitationRecord {
  PlatformStaffInvitationRecord({
    required String id,
    required String email,
    required String role,
    required Set<String> platformCapabilities,
    required String tokenHash,
    required String createdBy,
    required DateTime createdAt,
    required DateTime expiresAt,
    String status = 'PENDING',
    String? acceptedBy,
    DateTime? acceptedAt,
    DateTime? revokedAt,
    String deliveryStatus = 'PENDING',
    DateTime? deliveryFailedAt,
  }) : id = requireOpaqueId(id, 'staff invitation ID'),
       email = requireNonEmpty(email, 'staff invitation email', maxLength: 320),
       role = requireNonEmpty(role, 'staff invitation role', maxLength: 64),
       platformCapabilities = Set.unmodifiable(platformCapabilities),
       tokenHash = requireNonEmpty(tokenHash, 'staff invitation token hash'),
       createdBy = requireNonEmpty(createdBy, 'staff invitation creator'),
       createdAt = createdAt.toUtc(),
       expiresAt = expiresAt.toUtc(),
       status = _enumValue(
         status,
         organizationInvitationStatuses,
         'staff invitation status',
       ),
       acceptedBy = acceptedBy == null
           ? null
           : requireNonEmpty(acceptedBy, 'staff invitation accepter'),
       acceptedAt = acceptedAt?.toUtc(),
       revokedAt = revokedAt?.toUtc(),
       deliveryStatus = _enumValue(
         deliveryStatus,
         invitationDeliveryStatuses,
         'staff invitation delivery status',
       ),
       deliveryFailedAt = deliveryFailedAt?.toUtc() {
    if (this.platformCapabilities.isEmpty ||
        this.platformCapabilities
            .difference(supportedPlatformCapabilities)
            .isNotEmpty ||
        !platformRoleCapabilities.containsKey(role) ||
        !this.platformCapabilities.containsAll(
          platformCapabilitiesForRole(role),
        ) ||
        !platformCapabilitiesForRole(role)
            .containsAll(this.platformCapabilities)) {
      throw const FormatException('Invalid staff invitation capabilities');
    }
  }

  final String id;
  final String email;
  final String role;
  final Set<String> platformCapabilities;
  final String tokenHash;
  final String createdBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String status;
  final String? acceptedBy;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;
  final String deliveryStatus;
  final DateTime? deliveryFailedAt;

  String statusAt(DateTime now) {
    if (status == 'ACCEPTED' || acceptedAt != null) return 'ACCEPTED';
    if (status == 'REVOKED' || revokedAt != null) return 'REVOKED';
    if (!expiresAt.isAfter(now.toUtc())) return 'EXPIRED';
    return 'PENDING';
  }

  bool activeAt(DateTime now) => statusAt(now) == 'PENDING';

  PlatformStaffInvitationRecord copyWith({
    String? status,
    String? acceptedBy,
    DateTime? acceptedAt,
    DateTime? revokedAt,
    String? deliveryStatus,
    DateTime? deliveryFailedAt,
  }) => PlatformStaffInvitationRecord(
    id: id,
    email: email,
    role: role,
    platformCapabilities: platformCapabilities,
    tokenHash: tokenHash,
    createdBy: createdBy,
    createdAt: createdAt,
    expiresAt: expiresAt,
    status: status ?? this.status,
    acceptedBy: acceptedBy ?? this.acceptedBy,
    acceptedAt: acceptedAt ?? this.acceptedAt,
    revokedAt: revokedAt ?? this.revokedAt,
    deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    deliveryFailedAt: deliveryFailedAt ?? this.deliveryFailedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'email': email,
    'role': role,
    'platformCapabilities': platformCapabilities.toList()..sort(),
    'tokenHash': tokenHash,
    'createdBy': createdBy,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'status': status,
    'acceptedBy': acceptedBy,
    'acceptedAt': acceptedAt?.toUtc().toIso8601String(),
    'revokedAt': revokedAt?.toUtc().toIso8601String(),
    'deliveryStatus': deliveryStatus,
    'deliveryFailedAt': deliveryFailedAt?.toUtc().toIso8601String(),
  };

  Map<String, Object?> toMetadataJson({DateTime? now}) => <String, Object?>{
    'id': id,
    'email': email,
    'role': role,
    'platformCapabilities': platformCapabilities.toList()..sort(),
    'createdBy': createdBy,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'status': statusAt((now ?? DateTime.now()).toUtc()),
    'acceptedBy': acceptedBy,
    'acceptedAt': acceptedAt?.toUtc().toIso8601String(),
    'revokedAt': revokedAt?.toUtc().toIso8601String(),
    'deliveryStatus': deliveryStatus,
    'active': activeAt((now ?? DateTime.now()).toUtc()),
  };

  /// Public staff-invitation metadata excludes the issuing operator and the
  /// capability bundle. The invited recipient only needs role and lifetime
  /// information to make an informed acceptance decision.
  Map<String, Object?> toPublicMetadataJson({DateTime? now}) =>
      <String, Object?>{
        'email': email,
        'role': role,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'status': statusAt((now ?? DateTime.now()).toUtc()),
        'active': activeAt((now ?? DateTime.now()).toUtc()),
      };

  static PlatformStaffInvitationRecord fromJson(Map<String, Object?> value) {
    final rawCapabilities = value['platformCapabilities'];
    if (rawCapabilities is! List<Object?> ||
        rawCapabilities.any((item) => item is! String)) {
      throw const FormatException('Invalid staff invitation capabilities');
    }
    return PlatformStaffInvitationRecord(
      id: value['id']! as String,
      email: value['email']! as String,
      role: value['role']! as String,
      platformCapabilities: rawCapabilities.cast<String>().toSet(),
      tokenHash: value['tokenHash']! as String,
      createdBy: value['createdBy']! as String,
      createdAt: DateTime.parse(value['createdAt']! as String),
      expiresAt: DateTime.parse(value['expiresAt']! as String),
      status: value['status'] as String? ?? 'PENDING',
      acceptedBy: value['acceptedBy'] as String?,
      acceptedAt: _timestamp(value['acceptedAt']),
      revokedAt: _timestamp(value['revokedAt']),
      deliveryStatus: value['deliveryStatus'] as String? ?? 'DELIVERED',
      deliveryFailedAt: _timestamp(value['deliveryFailedAt']),
    );
  }
}

final class IssuedPlatformStaffInvitation {
  const IssuedPlatformStaffInvitation({
    required this.record,
    required this.token,
  });

  final PlatformStaffInvitationRecord record;
  final String token;

  Map<String, Object?> toJson({DateTime? now}) => <String, Object?>{
    ...record.toMetadataJson(now: now),
    'token': token,
  };
}

String _text(String value, String field, int maxLength) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > maxLength ||
      normalized.contains(RegExp(r'[\u0000\r\n]'))) {
    throw FormatException('Invalid $field');
  }
  return normalized;
}

String _enumValue(String value, Set<String> allowed, String field) {
  if (!allowed.contains(value)) throw FormatException('Invalid $field');
  return value;
}

DateTime? _timestamp(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid timestamp');
  return DateTime.parse(value).toUtc();
}
