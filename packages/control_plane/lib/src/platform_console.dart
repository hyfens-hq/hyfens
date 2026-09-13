import 'cloud_plans.dart';
import 'domain.dart';
import 'encoding.dart';
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
              'createdAt': application.createdAt.toUtc().toIso8601String(),
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
              'createdAt': environment.createdAt.toUtc().toIso8601String(),
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
              'displayName': membership.profileName == 'super-admin'
                  ? 'Super administrator'
                  : membership.role,
              'active': membership.active && user.active,
              'managedPlatformStaff': membership.managedPlatformStaff,
              'platformCapabilities':
                  membership.managedPlatformStaff
                        ? membership.platformCapabilities
                              .intersection(
                                platformCapabilitiesForManagedStaffRole(
                                  membership.role,
                                ),
                              )
                              .toList()
                        : membership.platformCapabilities.toList()
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

  /// Returns the stable Cloud plan catalogue and bounded subscription
  /// projections. Tenant/provider billing rows are subscription evidence, not
  /// the global plan catalogue; projecting them as plans creates duplicate
  /// Starter/Team rows whenever more than one organization has paid.
  Future<Map<String, Object?>> readEntitlements() async {
    final organizations = <String, Map<String, Object?>>{};
    for (final value in await store.listJson('organizations')) {
      final id = value['id'];
      if (id is String) {
        organizations[id] = <String, Object?>{
          'name': value['name'],
          'deletionState': value['deletionState'] ?? 'active',
        };
      }
    }
    final billingPlans = await store.listJson('billing_plans');
    final providerPrices = <String, Map<String, Object?>>{};
    final providerPriceConflicts = <String>{};
    for (final value in billingPlans) {
      final key = value['key'];
      if (key is! String || !isCloudPlanKey(key)) continue;
      final price = <String, Object?>{
        'currency': value['currency'],
        'amountMinor': value['amountMinor'],
        'interval': value['interval'],
        'period': value['period'],
      };
      final previous = providerPrices[key];
      if (previous != null && canonicalJson(previous) != canonicalJson(price)) {
        providerPriceConflicts.add(key);
      } else {
        providerPrices[key] = price;
      }
    }
    final persistedCatalog = <String, Map<String, Object?>>{};
    for (final value in await store.listJson('billing_plan_catalog')) {
      final key = value['key'];
      if (key is String && isCloudPlanKey(key)) {
        persistedCatalog[key] = value;
      }
    }
    final plans = defaultCloudPlanCatalog
        .map((definition) {
          final value = persistedCatalog[definition.key];
          final price = providerPriceConflicts.contains(definition.key)
              ? null
              : providerPrices[definition.key];
          return <String, Object?>{
            'id': value?['id'] ?? 'cloud_plan_${definition.key}',
            'key': definition.key,
            'name': value?['name'] ?? definition.name,
            'description':
                value?['description'] ?? _cloudPlanDescription(definition.key),
            'deploymentModel':
                value?['deploymentModel'] ?? DeploymentModel.cloud.wireValue,
            'rank': value?['rank'] ?? definition.rank,
            'paymentRequired':
                value?['paymentRequired'] ?? definition.paymentRequired,
            'providerBacked':
                value?['providerBacked'] ?? definition.providerBacked,
            'active': value?['active'] as bool? ?? true,
            'limits':
                value?['limits'] ??
                <String, Object?>{
                  for (final entry in definition.limits.entries)
                    entry.key: entry.value.toJson(),
                },
            if (price != null) ...price,
            if (providerPriceConflicts.contains(definition.key))
              'priceStatus': 'conflicting_provider_rows'
            else if (price != null)
              'priceStatus': 'provider_projection'
            else
              'priceStatus': 'not_configured',
            'updatedAt': value?['updatedAt'],
          };
        })
        .toList(growable: false);
    final subscriptions = (await store.listJson('billing_subscriptions'))
        .map((value) {
          final organizationId = value['organizationId'];
          final organization = organizationId is String
              ? organizations[organizationId]
              : null;
          final cloudPlanKey = value['cloudPlanKey'] is String
              ? value['cloudPlanKey']! as String
              : _planKeyForTenantPlan(value['planId'], billingPlans);
          final plan = cloudPlanKey == null
              ? null
              : plans.firstWhere(
                  (candidate) => candidate['key'] == cloudPlanKey,
                  orElse: () => const <String, Object?>{},
                );
          final organizationStatus =
              organization?['deletionState'] ?? 'unknown';
          return <String, Object?>{
            'id': value['id'],
            'organizationId': organizationId,
            'organizationName': organization?['name'],
            'organizationStatus': organizationStatus,
            'planId': value['planId'],
            'cloudPlanKey': cloudPlanKey,
            'planName': plan?['name'],
            'status': organizationStatus == 'deleted'
                ? 'deleted'
                : value['status'],
            'totalCount': value['totalCount'],
            'paidCount': value['paidCount'],
            'remainingCount': value['remainingCount'],
            'currentStartAt': value['currentStartAt'],
            'currentEndAt': value['currentEndAt'],
            'cancelAtCycleEnd': value['cancelAtCycleEnd'],
            'createdAt': value['createdAt'],
            'updatedAt': value['updatedAt'],
          };
        })
        .toList(growable: false);
    return <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'scope': 'platform',
      'plans': plans,
      'subscriptions': subscriptions,
    };
  }

  String? _planKeyForTenantPlan(
    Object? planId,
    List<Map<String, Object?>> billingPlans,
  ) {
    if (planId is! String) return null;
    for (final value in billingPlans) {
      if (value['id'] == planId && value['key'] is String) {
        return value['key']! as String;
      }
    }
    return null;
  }

  String _cloudPlanDescription(String key) => switch (key) {
    cloudPlanFreeKey => 'Evaluate the core release and deployment workflow.',
    cloudPlanStarterKey => 'Serious production use with room to grow.',
    cloudPlanTeamKey => 'Collaboration and organizational scale for teams.',
    cloudPlanEnterpriseKey =>
      'Custom governance, support, and infrastructure requirements.',
    _ => 'Cloud entitlement plan',
  };

  Future<Map<String, Object?>> readEnterpriseInquiries() async {
    final inquiries = (await store.listJson('enterprise_inquiries'))
        .map(
          (value) => <String, Object?>{
            'id': value['id'],
            'email': value['email'],
            'name': value['name'],
            'organization': value['organization'],
            'message': value['message'],
            'source': value['source'],
            'status': value['status'],
            'destination': value['destination'],
            'delivery': value['delivery'],
            'notificationStatus': value['notificationStatus'],
            'notificationSentAt': value['notificationSentAt'],
            'createdAt': value['createdAt'],
            'updatedAt': value['updatedAt'],
          },
        )
        .toList(growable: false);
    inquiries.sort((left, right) {
      final leftAt = DateTime.tryParse('${left['createdAt']}');
      final rightAt = DateTime.tryParse('${right['createdAt']}');
      return (rightAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        leftAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
    return <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'scope': 'platform',
      'inquiries': List.unmodifiable(
        inquiries.take(defaultPlatformOrganizationLimit),
      ),
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
    final memberCount = await _memberCount(organization.id);
    final plan = await _organizationPlan(organization.id);
    final activity = <DateTime>[organization.createdAt];
    for (final values in <List<Map<String, Object?>>>[
      applications,
      environments,
      releases,
      patches,
      rollouts,
      audit,
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
      'status': organization.deletionState,
      'plan': plan,
      'planName': plan,
      'createdAt': organization.createdAt.toUtc().toIso8601String(),
      'lastActivityAt': activity.last.toUtc().toIso8601String(),
      'applicationCount': applications.length,
      'environmentCount': environments.length,
      'releaseCount': releases.length,
      'patchCount': patches.length,
      'memberCount': memberCount,
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

  Future<String?> _organizationPlan(String organizationId) async {
    final subscriptions = (await store.listJson('billing_subscriptions'))
        .where((value) => value['organizationId'] == organizationId)
        .toList(growable: false);
    if (subscriptions.isEmpty) return null;
    subscriptions.sort((left, right) {
      final leftAt = DateTime.tryParse('${left['updatedAt']}');
      final rightAt = DateTime.tryParse('${right['updatedAt']}');
      return (rightAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        leftAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
    final row = subscriptions.first;
    final key = row['cloudPlanKey'];
    if (key is String && isCloudPlanKey(key)) {
      final catalog = await store.readJson(
        'billing_plan_catalog',
        'cloud_plan_$key',
      );
      final name = catalog?['name'];
      if (name is String && name.isNotEmpty) return name;
      return cloudPlanDefinition(key).name;
    }
    final planId = row['planId'];
    if (planId is String) {
      final providerPlan = await store.readJson('billing_plans', planId);
      final name = providerPlan?['name'];
      if (name is String && name.isNotEmpty) return name;
    }
    return null;
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
    final metadata = value['metadata'];
    final safeMetadata = metadata is Map
        ? <String, Object?>{
            for (final key in const <String>{
              'audience',
              'actor_type',
              'role',
              'old_owner_email',
              'new_owner_email',
              'reason',
              'revision',
              'correlation_id',
              'causation_id',
            })
              if (metadata[key] != null) key: metadata[key],
          }
        : const <String, Object?>{};
    return <String, Object?>{
      for (final key in keys) key: value[key],
      if (safeMetadata.isNotEmpty) 'metadata': safeMetadata,
    };
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
