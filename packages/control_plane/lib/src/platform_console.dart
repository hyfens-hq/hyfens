import 'domain.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'persistence.dart';

const int defaultPlatformOrganizationLimit = 100;

/// Bounded read projections for the Hyfens Platform Console.
///
/// This projection deliberately has no tenant credential or customer-session
/// authorization logic. The HTTP adapter authorizes an explicit platform
/// capability before calling it, and the projection only returns operational
/// metadata required for the directory/detail views.
final class PlatformConsoleProjection {
  PlatformConsoleProjection(
    this.store, {
    this.maxOrganizations = defaultPlatformOrganizationLimit,
  }) {
    if (maxOrganizations <= 0 ||
        maxOrganizations > defaultPlatformOrganizationLimit) {
      throw ArgumentError.value(
        maxOrganizations,
        'maxOrganizations',
        'must be between 1 and $defaultPlatformOrganizationLimit',
      );
    }
  }

  final ControlPlaneStore store;
  final int maxOrganizations;

  Future<Map<String, Object?>> listOrganizations({String? query}) async {
    final normalizedQuery = query?.trim().toLowerCase() ?? '';
    if (normalizedQuery.length > 128) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Organization search is too long',
        statusCode: 422,
      );
    }
    final organizations = (await store.listJson('organizations'))
        .map(OrganizationRecord.fromJson)
        .where(
          (organization) =>
              normalizedQuery.isEmpty ||
              organization.id.toLowerCase().contains(normalizedQuery) ||
              organization.name.toLowerCase().contains(normalizedQuery),
        )
        .toList(growable: false);
    final sorted = List<OrganizationRecord>.from(organizations)
      ..sort(_compareNewest);
    final items = <Map<String, Object?>>[];
    for (final organization in sorted.take(maxOrganizations)) {
      items.add(await _organizationSummary(organization));
    }
    return <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'scope': 'platform',
      'organizations': items,
      'counts': <String, Object?>{
        'matchingOrganizations': sorted.length,
        'returnedOrganizations': items.length,
      },
      'limits': <String, Object?>{'maxOrganizations': maxOrganizations},
    };
  }

  Future<Map<String, Object?>> readOrganization(String organizationId) async {
    final value = await store.readJson('organizations', organizationId);
    if (value == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final organization = OrganizationRecord.fromJson(value);
    final summary = await _organizationSummary(organization);
    final applications = await _tenantRecords(
      'applications',
      organization.id,
      ApplicationRecord.fromJson,
    );
    final environments = await _tenantRecords(
      'environments',
      organization.id,
      EnvironmentRecord.fromJson,
    );
    final releases = await _tenantValues('releases', organization.id);
    final patches = await _tenantValues('patches', organization.id);
    final rollouts = await _tenantValues('rollouts', organization.id);
    final audit = await _tenantValues('audit', organization.id);
    return <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'scope': 'platform',
      'organization': summary,
      'applications': applications
          .map(
            (application) => <String, Object?>{
              'id': application.id,
              'name': application.name,
              'platform': application.platform,
              'runtimeApplicationId': application.runtimeApplicationId,
              'status': application.status,
              'createdAt': application.createdAt.toUtc().toIso8601String(),
              'updatedAt': application.updatedAt.toUtc().toIso8601String(),
            },
          )
          .toList(growable: false),
      'environments': environments
          .map(
            (environment) => <String, Object?>{
              'id': environment.id,
              'applicationId': environment.applicationId,
              'name': environment.name,
              'version': environment.version,
              'promotedReleaseId': environment.promotedReleaseId,
              'status': environment.status,
              'createdAt': environment.createdAt.toUtc().toIso8601String(),
              'updatedAt': environment.updatedAt.toUtc().toIso8601String(),
            },
          )
          .toList(growable: false),
      'counts': <String, Object?>{
        'applications': applications.length,
        'environments': environments.length,
        'releases': releases.length,
        'patches': patches.length,
        'rollouts': rollouts.length,
        'auditEvents': audit.length,
      },
    };
  }

  /// Returns only audit records explicitly marked as platform-audience
  /// events. Customer audit rows are never re-labelled as platform events.
  Future<Map<String, Object?>> readAudit({String? organizationId}) async {
    final events = <Map<String, Object?>>[];
    for (final value in await store.listJson('audit')) {
      if (organizationId != null && value['organizationId'] != organizationId) {
        continue;
      }
      final metadata = value['metadata'];
      if (metadata is! Map ||
          metadata['audience'] != platformAuthorizationAudience) {
        continue;
      }
      final event = _safePlatformAuditEvent(value);
      if (event != null) events.add(event);
    }
    events.sort((left, right) {
      final rightTime = DateTime.tryParse('${right['createdAt']}');
      final leftTime = DateTime.tryParse('${left['createdAt']}');
      final byTime = (rightTime ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(leftTime ?? DateTime.fromMillisecondsSinceEpoch(0));
      if (byTime != 0) return byTime;
      return '${left['id']}'.compareTo('${right['id']}');
    });
    return <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'scope': 'platform',
      'events': List.unmodifiable(
        events.take(defaultPlatformOrganizationLimit),
      ),
      'available': events.isNotEmpty,
      if (events.isEmpty) 'note': 'No platform-audience audit events are recorded by this control plane.',
    };
  }

  /// Returns staff metadata for the Platform Console. Customer memberships,
  /// password hashes, sessions, and credential material are intentionally not
  /// part of this projection.
  Future<Map<String, Object?>> listUsers() async {
    final users = <Map<String, Object?>>[];
    for (final value in await store.listJson('users')) {
      final user = HumanUserRecord.fromJson(value);
      final memberships = user.memberships
          .where(
            (membership) =>
                membership.audience == platformAuthorizationAudience &&
                membership.platformCapabilities.isNotEmpty,
          )
          .map(
            (membership) => <String, Object?>{
              'organizationId': membership.organizationId,
              'profileName': membership.profileName,
              'role': membership.role,
              'platformCapabilities': membership.platformCapabilities.toList()
                ..sort(),
            },
          )
          .toList(growable: false);
      if (memberships.isEmpty) continue;
      users.add(<String, Object?>{
        'id': user.id,
        'email': user.email,
        'active': user.active,
        'createdAt': user.createdAt.toUtc().toIso8601String(),
        'memberships': memberships,
      });
    }
    users.sort((left, right) {
      final byEmail = '${left['email']}'.compareTo('${right['email']}');
      return byEmail != 0
          ? byEmail
          : '${left['id']}'.compareTo('${right['id']}');
    });
    return <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'scope': 'platform',
      'users': List.unmodifiable(users),
    };
  }

  /// Returns a read-only commercial projection without provider identifiers
  /// or payment/customer secrets.
  Future<Map<String, Object?>> readEntitlements() async {
    final organizationNames = <String, String>{};
    for (final value in await store.listJson('organizations')) {
      final id = value['id'];
      final name = value['name'];
      if (id is String && name is String) organizationNames[id] = name;
    }
    final plans = (await store.listJson('billing_plans'))
        .map(
          (value) => <String, Object?>{
            'id': value['id'],
            'organizationId': value['organizationId'],
            'organizationName': organizationNames[value['organizationId']],
            'key': value['key'],
            'name': value['name'],
            'description': value['description'],
            'currency': value['currency'],
            'amountMinor': value['amountMinor'],
            'interval': value['interval'],
            'period': value['period'],
            'active': value['active'],
            'createdAt': value['createdAt'],
            'updatedAt': value['updatedAt'],
          },
        )
        .toList(growable: false);
    final subscriptions = (await store.listJson('billing_subscriptions'))
        .map(
          (value) => <String, Object?>{
            'id': value['id'],
            'organizationId': value['organizationId'],
            'organizationName': organizationNames[value['organizationId']],
            'planId': value['planId'],
            'status': value['status'],
            'totalCount': value['totalCount'],
            'paidCount': value['paidCount'],
            'remainingCount': value['remainingCount'],
            'currentStartAt': value['currentStartAt'],
            'currentEndAt': value['currentEndAt'],
            'cancelAtCycleEnd': value['cancelAtCycleEnd'],
            'createdAt': value['createdAt'],
            'updatedAt': value['updatedAt'],
          },
        )
        .toList(growable: false);
    return <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'scope': 'platform',
      'plans': plans,
      'subscriptions': subscriptions,
    };
  }

  Future<Map<String, Object?>> _organizationSummary(
    OrganizationRecord organization,
  ) async {
    final applications = await _tenantValues('applications', organization.id);
    final environments = await _tenantValues('environments', organization.id);
    final releases = await _tenantValues('releases', organization.id);
    final patches = await _tenantValues('patches', organization.id);
    final rollouts = await _tenantValues('rollouts', organization.id);
    final audit = await _tenantValues('audit', organization.id);
    final supportCases = await _tenantValues('support_cases', organization.id);
    final subscriptions = await _tenantValues(
      'billing_subscriptions',
      organization.id,
    );
    final plans = <String, Map<String, Object?>>{
      for (final value in await store.listJson('billing_plans'))
        if (value['id'] is String) value['id']! as String: value,
    };
    final activeSubscriptions = subscriptions
        .where(
          (value) =>
              value['status'] == 'active' || value['status'] == 'authenticated',
        )
        .toList(growable: false);
    final activeSubscription = activeSubscriptions.isEmpty
        ? null
        : activeSubscriptions.first;
    final activePlan = activeSubscription?['planId'] is String
        ? plans[activeSubscription!['planId']! as String]
        : null;
    final memberCount = await _memberCount(organization.id);
    final activity = <DateTime>[organization.createdAt];
    for (final values in <List<Map<String, Object?>>>[
      applications,
      environments,
      releases,
      patches,
      rollouts,
      audit,
      supportCases,
    ]) {
      for (final value in values) {
        final createdAt = _createdAt(value);
        if (createdAt != null) activity.add(createdAt);
      }
    }
    activity.sort();
    return <String, Object?>{
      'id': organization.id,
      'name': organization.name,
      'status': 'active',
      'createdAt': organization.createdAt.toUtc().toIso8601String(),
      'lastActivityAt': activity.last.toUtc().toIso8601String(),
      'applicationCount': applications.length,
      'environmentCount': environments.length,
      'releaseCount': releases.length,
      'patchCount': patches.length,
      'memberCount': memberCount,
      'openSupportCaseCount': supportCases
          .where(
            (value) =>
                value['status'] != 'CLOSED' && value['status'] != 'RESOLVED',
          )
          .length,
      if (activeSubscription != null)
        'subscription': <String, Object?>{
          'status': activeSubscription['status'],
          'planId': activeSubscription['planId'],
          'planName': activePlan?['name'],
          'currency': activePlan?['currency'],
          'amountMinor': activePlan?['amountMinor'],
          'currentEndAt': activeSubscription['currentEndAt'],
          'cancelAtCycleEnd': activeSubscription['cancelAtCycleEnd'],
        },
    };
  }

  Future<List<T>> _tenantRecords<T>(
    String collection,
    String organizationId,
    T Function(Map<String, Object?>) decode,
  ) async {
    final values = <T>[];
    for (final value in await store.listJson(collection)) {
      if (value['organizationId'] != organizationId) continue;
      values.add(decode(value));
    }
    return List.unmodifiable(values);
  }

  Future<List<Map<String, Object?>>> _tenantValues(
    String collection,
    String organizationId,
  ) async =>
      (await store.listJson(collection))
          .where((value) => value['organizationId'] == organizationId)
          .toList(growable: false);

  Future<int> _memberCount(String organizationId) async {
    var count = 0;
    for (final value in await store.listJson('users')) {
      final user = HumanUserRecord.fromJson(value);
      if (user.memberships.any(
        (membership) =>
            membership.organizationId == organizationId &&
            membership.audience == customerAuthorizationAudience,
      )) {
        count++;
      }
    }
    return count;
  }

  Map<String, Object?>? _safePlatformAuditEvent(Map<String, Object?> value) {
    const keys = <String>{
      'id',
      'requestId',
      'organizationId',
      'actorId',
      'action',
      'resourceType',
      'resourceId',
      'result',
      'createdAt',
    };
    if (keys.any((key) => value[key] is! String)) return null;
    return <String, Object?>{for (final key in keys) key: value[key]};
  }

  DateTime? _createdAt(Map<String, Object?> value) {
    final raw = value['createdAt'] ?? value['created_at'];
    return raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
  }

  static int _compareNewest(OrganizationRecord left, OrganizationRecord right) {
    final byTime = right.createdAt.compareTo(left.createdAt);
    return byTime != 0 ? byTime : left.id.compareTo(right.id);
  }
}
