import 'errors.dart';

/// The operating model of a control-plane deployment. This is deliberately
/// separate from a Cloud subscription plan: self-hosted is not a free Cloud
/// subscription and must never enter the Cloud plan hierarchy.
enum DeploymentModel { cloud, selfHosted }

extension DeploymentModelValue on DeploymentModel {
  String get wireValue => switch (this) {
    DeploymentModel.cloud => 'cloud',
    DeploymentModel.selfHosted => 'self_hosted',
  };
}

DeploymentModel parseDeploymentModel(String? value) {
  return switch (value == null || value.isEmpty ? 'self_hosted' : value) {
    'cloud' => DeploymentModel.cloud,
    'self_hosted' => DeploymentModel.selfHosted,
    _ => throw ArgumentError(
      'HYFENS_DEPLOYMENT_MODEL must be cloud or self_hosted',
    ),
  };
}

const String cloudPlanFreeKey = 'free';
const String cloudPlanStarterKey = 'starter';
const String cloudPlanTeamKey = 'team';
const String cloudPlanEnterpriseKey = 'enterprise';

const String cloudApplicationsLimitKey = 'applications';
const String cloudEnvironmentsPerApplicationLimitKey =
    'environments_per_application';
const String cloudMembersLimitKey = 'members';

/// A plan limit is explicit about whether it is numeric, uncapped by the
/// commercial plan, custom to an Enterprise agreement, or not configured.
/// `null` is never overloaded for these meanings.
enum CloudLimitType { finite, unlimited, custom, notConfigured }

extension CloudLimitTypeWire on CloudLimitType {
  String get wireValue => switch (this) {
    CloudLimitType.finite => 'finite',
    CloudLimitType.unlimited => 'unlimited',
    CloudLimitType.custom => 'custom',
    CloudLimitType.notConfigured => 'not_configured',
  };

  static CloudLimitType parse(Object? value) => switch (value) {
    'finite' => CloudLimitType.finite,
    'unlimited' => CloudLimitType.unlimited,
    'custom' => CloudLimitType.custom,
    'not_configured' => CloudLimitType.notConfigured,
    _ => throw const FormatException('Invalid Cloud limit type'),
  };
}

final class CloudLimit {
  const CloudLimit(this.type, {this.value})
    : assert(
        type != CloudLimitType.finite || (value != null && value >= 0),
        'finite Cloud limits require a non-negative value',
      ),
      assert(
        type == CloudLimitType.finite || value == null,
        'only finite Cloud limits may include a value',
      );

  const CloudLimit.finite(int value)
    : this(CloudLimitType.finite, value: value);
  const CloudLimit.unlimited() : this(CloudLimitType.unlimited);
  const CloudLimit.custom() : this(CloudLimitType.custom);
  const CloudLimit.notConfigured() : this(CloudLimitType.notConfigured);

  final CloudLimitType type;
  final int? value;

  bool get isFinite => type == CloudLimitType.finite;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.wireValue,
    if (value != null) 'value': value,
  };

  static CloudLimit fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid Cloud limit');
    final type = CloudLimitTypeWire.parse(raw['type']);
    final rawValue = raw['value'];
    if (type == CloudLimitType.finite && (rawValue is! int || rawValue < 0)) {
      throw const FormatException(
        'Finite Cloud limits require a non-negative integer',
      );
    }
    if (type != CloudLimitType.finite && rawValue != null) {
      throw const FormatException(
        'Only finite Cloud limits may include a value',
      );
    }
    return CloudLimit(type, value: rawValue as int?);
  }
}

/// Stable Cloud hierarchy. Do not add deployment models to this list.
const List<String> cloudPlanOrder = <String>[
  cloudPlanFreeKey,
  cloudPlanStarterKey,
  cloudPlanTeamKey,
  cloudPlanEnterpriseKey,
];

const String signedReleasesEntitlement = 'signed_releases';
const String boundedPatchesEntitlement = 'bounded_patches';
const String controlledDeploymentEntitlement = 'controlled_deployment';
const String verificationEntitlement = 'verification';
const String rollbackEntitlement = 'rollback';

/// Core release-integrity capabilities already present in the control-plane
/// contract. They are not plan gates: every Cloud plan receives them.
const Set<String> cloudCoreEntitlements = <String>{
  signedReleasesEntitlement,
  boundedPatchesEntitlement,
  controlledDeploymentEntitlement,
  verificationEntitlement,
  rollbackEntitlement,
};

final class CloudPlanDefinition {
  const CloudPlanDefinition({
    required this.key,
    required this.name,
    required this.rank,
    required this.paymentRequired,
    required this.providerBacked,
    this.capabilities = cloudCoreEntitlements,
    this.limits = const <String, CloudLimit>{},
  });

  final String key;
  final String name;
  final int rank;
  final bool paymentRequired;
  final bool providerBacked;
  final Set<String> capabilities;
  final Map<String, CloudLimit> limits;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'name': name,
    'deployment_model': DeploymentModel.cloud.wireValue,
    'rank': rank,
    'payment_required': paymentRequired,
    'provider_backed': providerBacked,
    'capabilities': capabilities.toList()..sort(),
    'limits': <String, Object?>{
      for (final entry in limits.entries) entry.key: entry.value.toJson(),
    },
  };
}

const List<CloudPlanDefinition> defaultCloudPlanCatalog = <CloudPlanDefinition>[
  CloudPlanDefinition(
    key: cloudPlanFreeKey,
    name: 'Free',
    rank: 0,
    paymentRequired: false,
    providerBacked: false,
    limits: <String, CloudLimit>{
      cloudApplicationsLimitKey: CloudLimit.finite(1),
      cloudEnvironmentsPerApplicationLimitKey: CloudLimit.finite(1),
      cloudMembersLimitKey: CloudLimit.finite(1),
    },
  ),
  CloudPlanDefinition(
    key: cloudPlanStarterKey,
    name: 'Starter',
    rank: 1,
    paymentRequired: true,
    providerBacked: true,
    limits: <String, CloudLimit>{
      cloudApplicationsLimitKey: CloudLimit.unlimited(),
      cloudEnvironmentsPerApplicationLimitKey: CloudLimit.finite(2),
      cloudMembersLimitKey: CloudLimit.finite(5),
    },
  ),
  CloudPlanDefinition(
    key: cloudPlanTeamKey,
    name: 'Team',
    rank: 2,
    paymentRequired: true,
    providerBacked: true,
    limits: <String, CloudLimit>{
      cloudApplicationsLimitKey: CloudLimit.unlimited(),
      cloudEnvironmentsPerApplicationLimitKey: CloudLimit.finite(10),
      cloudMembersLimitKey: CloudLimit.finite(20),
    },
  ),
  CloudPlanDefinition(
    key: cloudPlanEnterpriseKey,
    name: 'Enterprise',
    rank: 3,
    paymentRequired: true,
    providerBacked: true,
    limits: <String, CloudLimit>{
      cloudApplicationsLimitKey: CloudLimit.custom(),
      cloudEnvironmentsPerApplicationLimitKey: CloudLimit.custom(),
      cloudMembersLimitKey: CloudLimit.custom(),
    },
  ),
];

bool isCloudPlanKey(String value) => cloudPlanOrder.contains(value);

int cloudPlanRank(String value) {
  final rank = cloudPlanOrder.indexOf(value);
  if (rank < 0) {
    throw ArgumentError.value(value, 'value', 'Unknown Cloud plan key');
  }
  return rank;
}

CloudPlanDefinition cloudPlanDefinition(String key) {
  for (final definition in defaultCloudPlanCatalog) {
    if (definition.key == key) return definition;
  }
  throw ControlPlaneException(
    'INVALID_CLOUD_PLAN',
    'Cloud plan key is unsupported: $key',
    statusCode: 500,
  );
}

final class CloudUsageSnapshot {
  const CloudUsageSnapshot({
    required this.applications,
    required this.environments,
    required this.members,
    required this.environmentsPerApplication,
    this.artifactStorageBytesCurrent,
    this.artifactDeliveryBytesPeriod,
    this.artifactDeliveryPeriodStart,
    this.artifactDeliveryPeriodEnd,
    this.artifactDeliveryAuthoritative,
    this.artifactDeliveryAuthority,
    this.artifactDeliveryQuotaEligible,
    this.artifactDeliverySource,
    this.artifactDeliveryCoveredSources,
    this.artifactDeliveryUncoveredSources,
  });

  final int applications;
  final int environments;
  final int members;
  final Map<String, int> environmentsPerApplication;
  final int? artifactStorageBytesCurrent;
  final int? artifactDeliveryBytesPeriod;
  final DateTime? artifactDeliveryPeriodStart;
  final DateTime? artifactDeliveryPeriodEnd;
  final bool? artifactDeliveryAuthoritative;
  final String? artifactDeliveryAuthority;
  final bool? artifactDeliveryQuotaEligible;
  final String? artifactDeliverySource;
  final List<String>? artifactDeliveryCoveredSources;
  final List<String>? artifactDeliveryUncoveredSources;

  Map<String, Object?> toJson() => <String, Object?>{
    'applications': applications,
    'environments': environments,
    'members': members,
    'environments_per_application': Map<String, int>.from(
      environmentsPerApplication,
    ),
    if (artifactStorageBytesCurrent != null)
      'artifact_storage_bytes_current': artifactStorageBytesCurrent,
    if (artifactDeliveryBytesPeriod != null)
      'artifact_delivery_bytes_period': artifactDeliveryBytesPeriod,
    if (artifactDeliveryPeriodStart != null &&
        artifactDeliveryPeriodEnd != null)
      'artifact_delivery_period': <String, Object?>{
        'type': 'utc_calendar_month',
        'start': artifactDeliveryPeriodStart!.toUtc().toIso8601String(),
        'end': artifactDeliveryPeriodEnd!.toUtc().toIso8601String(),
      },
    if (artifactDeliveryAuthoritative != null)
      'artifact_delivery_authoritative': artifactDeliveryAuthoritative,
    if (artifactDeliveryAuthority != null)
      'artifact_delivery_authority': artifactDeliveryAuthority,
    if (artifactDeliveryQuotaEligible != null)
      'artifact_delivery_quota_eligible': artifactDeliveryQuotaEligible,
    if (artifactDeliverySource != null)
      'artifact_delivery_source': artifactDeliverySource,
    if (artifactDeliveryCoveredSources != null)
      'artifact_delivery_covered_sources': artifactDeliveryCoveredSources,
    if (artifactDeliveryUncoveredSources != null)
      'artifact_delivery_uncovered_sources': artifactDeliveryUncoveredSources,
  };
}

/// Previous billing experiments used these values for provider-backed plans.
/// They are retained only to prevent Self-hosted from being reintroduced as a
/// Cloud plan. Unknown paid provider rows are handled as legacy paid state.
bool isSelfHostedPlanKey(String value) =>
    value == 'self-hosted' || value == 'self_hosted' || value == 'selfhosted';

/// Maps existing authorization scopes to the core contract they exercise.
/// Current Cloud plans intentionally share these capabilities; the central
/// map still makes later plan enforcement server-authoritative.
String? cloudEntitlementForScope(String scope) => switch (scope) {
  'application:read' ||
  'application:write' ||
  'environment:write' => controlledDeploymentEntitlement,
  'environment:rollback' => rollbackEntitlement,
  'release:read' || 'release:write' => signedReleasesEntitlement,
  'patch:read' ||
  'patch:write' ||
  'runtime:update:read' => boundedPatchesEntitlement,
  'artifact:read' ||
  'artifact:write' ||
  'bundle:read' ||
  'bundle:write' ||
  'runtime:artifact:read' => verificationEntitlement,
  'release:promote' ||
  'rollout:read' ||
  'rollout:create' ||
  'rollout:update' ||
  'rollout:promote' ||
  'observation:read' ||
  'health:evaluate' ||
  'health:schedule' ||
  'health:work:claim' => controlledDeploymentEntitlement,
  'rollout:halt' || 'health:work:apply-halt' => rollbackEntitlement,
  'observation:write' => controlledDeploymentEntitlement,
  'artifact:reconcile' => verificationEntitlement,
  _ => null,
};

final class EffectiveCloudEntitlements {
  const EffectiveCloudEntitlements({
    required this.deploymentModel,
    required this.planKey,
    required this.planName,
    required this.billingStatus,
    required this.source,
    required this.capabilities,
    required this.limits,
    this.usage,
  });

  final DeploymentModel deploymentModel;
  final String? planKey;
  final String? planName;
  final String billingStatus;
  final String source;
  final Set<String> capabilities;
  final Map<String, CloudLimit> limits;
  final CloudUsageSnapshot? usage;

  Map<String, Object?> toPlanJson() => <String, Object?>{
    'key': planKey,
    'name': planName,
    'deployment_model': deploymentModel.wireValue,
    'billing_status': billingStatus,
    'source': source,
  };

  Map<String, Object?> toEntitlementsJson() => <String, Object?>{
    'deployment_model': deploymentModel.wireValue,
    'capabilities': capabilities.toList()..sort(),
    'limits': <String, Object?>{
      for (final entry in limits.entries) entry.key: entry.value.toJson(),
    },
    if (usage != null) 'usage': usage!.toJson(),
  };
}
