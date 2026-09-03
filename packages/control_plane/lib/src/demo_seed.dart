import 'domain.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'persistence.dart';

const demoOrganizationId = 'org_auvana_ventures';
const demoApplicationId = 'app_auvana_demo';
const demoEnvironmentId = 'env_auvana_development';
const demoOrganizationName = 'Auvana Ventures Private Limited';
const demoRuntimeApplicationId = 'com.auvanaventures.demo';
const demoEnvironmentName = 'development';
const demoOwnerEmail = 'admin@auvanaventures.com';
const demoCustomerProfileName = 'demo';
const demoOwnerProfileName = 'super-admin';

/// The stable scope and human identity used by the local real-project demo.
///
/// This seed deliberately accepts the password only at invocation time. It
/// returns identity metadata and never persists or exposes the secret itself.
final class DemoSeedResult {
  const DemoSeedResult({
    required this.organization,
    required this.application,
    required this.environment,
    required this.owner,
  });

  final OrganizationRecord organization;
  final ApplicationRecord application;
  final EnvironmentRecord environment;
  final HumanUserRecord owner;
}

final class DemoAccountSeeder {
  DemoAccountSeeder({
    required this.store,
    required this.auth,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final ControlPlaneStore store;
  final HumanAuthService auth;
  final DateTime Function() _clock;

  Future<DemoSeedResult> seed({required String password}) async {
    await store.initialize();
    await auth.initialize();

    final organizationValue = await _ensureRecord(
      collection: 'organizations',
      id: demoOrganizationId,
      value: OrganizationRecord(
        id: demoOrganizationId,
        name: demoOrganizationName,
        createdAt: _clock(),
      ).toJson(),
      matches: (value) =>
          value['id'] == demoOrganizationId &&
          value['name'] == demoOrganizationName,
      description: 'the expected Auvana organization',
    );
    final applicationValue = await _ensureRecord(
      collection: 'applications',
      id: demoApplicationId,
      value: ApplicationRecord(
        id: demoApplicationId,
        organizationId: demoOrganizationId,
        runtimeApplicationId: demoRuntimeApplicationId,
        createdAt: _clock(),
      ).toJson(),
      matches: (value) =>
          value['id'] == demoApplicationId &&
          value['organizationId'] == demoOrganizationId &&
          value['runtimeApplicationId'] == demoRuntimeApplicationId,
      description: 'the expected Auvana demo application',
    );
    final environmentValue = await _ensureRecord(
      collection: 'environments',
      id: demoEnvironmentId,
      value: EnvironmentRecord(
        id: demoEnvironmentId,
        organizationId: demoOrganizationId,
        applicationId: demoApplicationId,
        name: demoEnvironmentName,
        version: 0,
        promotedReleaseId: null,
        createdAt: _clock(),
      ).toJson(),
      matches: (value) =>
          value['id'] == demoEnvironmentId &&
          value['organizationId'] == demoOrganizationId &&
          value['applicationId'] == demoApplicationId &&
          value['name'] == demoEnvironmentName,
      description: 'the expected Auvana development environment',
    );

    // Keep the customer membership first so the seeded identity can exercise
    // the normal CLI workflow by default. The platform membership is
    // intentionally separate; platform audience tokens must not authorize
    // customer routes merely because the human account is the same.
    final customerOwner = await auth.bootstrapOwner(
      organizationId: demoOrganizationId,
      applicationId: demoApplicationId,
      environmentId: demoEnvironmentId,
      email: demoOwnerEmail,
      password: password,
      profileName: demoCustomerProfileName,
    );
    final owner = await auth.bootstrapOwner(
      organizationId: demoOrganizationId,
      applicationId: demoApplicationId,
      environmentId: demoEnvironmentId,
      email: demoOwnerEmail,
      password: password,
      profileName: demoOwnerProfileName,
    );
    if (customerOwner.id != owner.id) {
      throw const ControlPlaneException(
        'DEMO_SEED_CONFLICT',
        'The fixed demo memberships resolved to different users',
        statusCode: 409,
      );
    }
    _validateOwner(owner);

    return DemoSeedResult(
      organization: OrganizationRecord.fromJson(organizationValue),
      application: ApplicationRecord.fromJson(applicationValue),
      environment: EnvironmentRecord.fromJson(environmentValue),
      owner: owner,
    );
  }

  Future<Map<String, Object?>> _ensureRecord({
    required String collection,
    required String id,
    required Map<String, Object?> value,
    required bool Function(Map<String, Object?> value) matches,
    required String description,
  }) async {
    final existing = await store.readJson(collection, id);
    if (existing != null) {
      _requireMatch(existing, matches, description);
      return existing;
    }
    try {
      await store.createJson(collection, id, value);
    } on StorageConflict {
      final concurrent = await store.readJson(collection, id);
      if (concurrent == null) rethrow;
      _requireMatch(concurrent, matches, description);
      return concurrent;
    }
    return value;
  }

  void _requireMatch(
    Map<String, Object?> value,
    bool Function(Map<String, Object?> value) matches,
    String description,
  ) {
    if (!matches(value)) {
      throw ControlPlaneException(
        'DEMO_SEED_CONFLICT',
        'The fixed demo scope does not match $description',
        statusCode: 409,
      );
    }
  }

  void _validateOwner(HumanUserRecord owner) {
    final memberships = owner.memberships
        .where(
          (item) =>
              item.organizationId == demoOrganizationId &&
              item.profileApplicationId == demoApplicationId &&
              item.profileEnvironmentId == demoEnvironmentId,
        )
        .toList(growable: false);
    final customerMembership = memberships.where(
      (item) =>
          item.profileName == demoCustomerProfileName &&
          item.audience == customerAuthorizationAudience,
    );
    final platformMembership = memberships.where(
      (item) =>
          item.profileName == demoOwnerProfileName &&
          item.audience == platformAuthorizationAudience,
    );
    if (owner.email != demoOwnerEmail ||
        memberships.length != 2 ||
        customerMembership.length != 1 ||
        platformMembership.length != 1 ||
        customerMembership.single.role != 'owner' ||
        !customerMembership.single.capabilities.containsAll(controlScopes) ||
        platformMembership.single.role != 'owner' ||
        !platformMembership.single.capabilities.containsAll(controlScopes) ||
        !platformMembership.single.platformCapabilities.containsAll(
          platformCapabilities,
        )) {
      throw const ControlPlaneException(
        'DEMO_SEED_CONFLICT',
        'The fixed demo owner already exists with an incompatible membership',
        statusCode: 409,
      );
    }
  }
}
