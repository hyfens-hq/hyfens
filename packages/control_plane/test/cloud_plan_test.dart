import 'dart:io';
import 'dart:math';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

Future<void> activateProviderPlan(
  BillingService billing,
  String organizationId,
  String planKey,
) async {
  final plan = await billing.createPlan(
    organizationId: organizationId,
    key: planKey,
    name: planKey,
    description: 'Cloud $planKey test plan',
    currency: 'INR',
    amountMinor: 4900,
    interval: 'monthly',
    period: 1,
    provider: 'razorpay',
    providerPlanId: 'provider-$planKey',
  );
  await billing.upsertSubscription(
    organizationId: organizationId,
    provider: 'razorpay',
    providerSubscriptionId: 'subscription-$planKey',
    providerPlanId: 'provider-$planKey',
    status: 'active',
    planId: plan['id']! as String,
  );
}

void main() {
  late Directory directory;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-cloud-plan-');
    service = ControlPlaneService(
      store: FileControlPlaneStore(directory),
      random: Random(7),
      deploymentModel: DeploymentModel.cloud,
    );
    bootstrap = await service.bootstrap(
      organizationName: 'Cloud plan test',
      runtimeApplicationId: 'com.example.cloud-plan',
      platformId: 'android',
      environmentName: 'development',
    );
  });

  tearDown(() => directory.delete(recursive: true));

  test('new Cloud organizations receive an explicit Free assignment', () async {
    final subscriptions = await service.billing.read(
      organizationId: bootstrap.organization.id,
    );
    final freeAssignments = subscriptions.subscriptions.where(
      (row) =>
          row['provider'] == 'internal' &&
          row['cloudPlanKey'] == cloudPlanFreeKey,
    );

    expect(freeAssignments, hasLength(1));
    expect(freeAssignments.single['billingStatus'], 'not_required');
    expect(freeAssignments.single['providerSubscriptionId'], isNotNull);
    expect(subscriptions.effectivePlan?['key'], cloudPlanFreeKey);
    expect(subscriptions.deploymentModel, 'cloud');
    expect(
      (subscriptions.entitlements?['capabilities'] as List<Object?>),
      containsAll(cloudCoreEntitlements),
    );
    expect(
      subscriptions.cloudPlans.map((value) => value['key']),
      containsAll(cloudPlanOrder),
    );
    final limits = subscriptions.entitlements?['limits']! as Map;
    expect((limits[cloudApplicationsLimitKey] as Map)['type'], 'finite');
    expect((limits[cloudApplicationsLimitKey] as Map)['value'], 1);
    expect(
      (limits[cloudEnvironmentsPerApplicationLimitKey] as Map)['value'],
      1,
    );
    expect((limits[cloudMembersLimitKey] as Map)['value'], 1);
    expect(subscriptions.usage?['applications'], 1);
    expect(subscriptions.usage?['environments'], 1);
    expect(subscriptions.usage?['members'], 0);
    expect(subscriptions.usage?['artifact_storage_bytes_current'], 0);
    expect(subscriptions.usage?['artifact_delivery_bytes_period'], 0);
    expect(
      (subscriptions.usage?['artifact_delivery_period'] as Map)['type'],
      'utc_calendar_month',
    );
  });

  test(
    'Free rejects new applications and environments at the boundary',
    () async {
      await expectLater(
        service.createApplication(
          token: bootstrap.controlCredential.token,
          organizationId: bootstrap.organization.id,
          runtimeApplicationId: 'com.example.free-second',
          idempotencyKey: 'free-second-application',
        ),
        throwsA(
          isA<ControlPlaneException>()
              .having((error) => error.code, 'code', 'PLAN_LIMIT_REACHED')
              .having(
                (error) => error.details['resource'],
                'resource',
                cloudApplicationsLimitKey,
              )
              .having((error) => error.details['current'], 'current', 1)
              .having((error) => error.details['limit'], 'limit', 1),
        ),
      );
      await expectLater(
        service.createEnvironment(
          token: bootstrap.controlCredential.token,
          organizationId: bootstrap.organization.id,
          applicationId: bootstrap.application.id,
          name: 'staging',
          idempotencyKey: 'free-second-environment',
        ),
        throwsA(
          isA<ControlPlaneException>()
              .having((error) => error.code, 'code', 'PLAN_LIMIT_REACHED')
              .having(
                (error) => error.details['resource'],
                'resource',
                cloudEnvironmentsPerApplicationLimitKey,
              ),
        ),
      );
    },
  );

  test(
    'Starter and Team resolve higher environment and member boundaries',
    () async {
      await activateProviderPlan(
        service.billing,
        bootstrap.organization.id,
        cloudPlanStarterKey,
      );
      final starter = await service.billing.resolveEffectiveEntitlements(
        organizationId: bootstrap.organization.id,
      );
      expect(starter.planKey, cloudPlanStarterKey);
      expect(
        starter.limits[cloudApplicationsLimitKey]?.type,
        CloudLimitType.unlimited,
      );
      expect(starter.limits[cloudEnvironmentsPerApplicationLimitKey]?.value, 2);
      expect(starter.limits[cloudMembersLimitKey]?.value, 5);

      final secondEnvironment = await service.createEnvironment(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
        applicationId: bootstrap.application.id,
        name: 'staging',
        idempotencyKey: 'starter-second-environment',
      );
      expect(secondEnvironment.name, 'staging');
      await expectLater(
        service.createEnvironment(
          token: bootstrap.controlCredential.token,
          organizationId: bootstrap.organization.id,
          applicationId: bootstrap.application.id,
          name: 'production',
          idempotencyKey: 'starter-third-environment',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'PLAN_LIMIT_REACHED',
          ),
        ),
      );

      await activateProviderPlan(
        service.billing,
        bootstrap.organization.id,
        cloudPlanTeamKey,
      );
      final team = await service.billing.resolveEffectiveEntitlements(
        organizationId: bootstrap.organization.id,
      );
      expect(team.planKey, cloudPlanTeamKey);
      expect(team.limits[cloudEnvironmentsPerApplicationLimitKey]?.value, 10);
      expect(team.limits[cloudMembersLimitKey]?.value, 20);
    },
  );

  test(
    'Free member admission is enforced without consuming the owner flow',
    () async {
      final authDirectory = await Directory.systemTemp.createTemp(
        'hyfens-cloud-member-limit-',
      );
      final authStore = FileControlPlaneStore(authDirectory);
      try {
        final auth = HumanAuthService(
          store: authStore,
          config: HumanAuthConfig(
            issuer: 'test-control-plane',
            audience: 'hyfens-control',
            signingKeySeed: List<int>.filled(32, 17),
          ),
          random: Random(19),
        );
        final authService = ControlPlaneService(
          store: authStore,
          humanAuth: auth,
          random: Random(23),
          deploymentModel: DeploymentModel.cloud,
        );
        final authBootstrap = await authService.bootstrap(
          organizationName: 'Cloud member limit',
          runtimeApplicationId: 'com.example.cloud-member-limit',
          platformId: 'android',
          environmentName: 'development',
        );
        await authService.bootstrapOwner(
          organizationId: authBootstrap.organization.id,
          applicationId: authBootstrap.application.id,
          environmentId: authBootstrap.environment.id,
          email: 'owner@example.com',
          password: 'correct horse battery staple',
        );
        expect(await authStore.listJson('users'), hasLength(1));

        await expectLater(
          auth.registerClient(
            organizationId: authBootstrap.organization.id,
            email: 'second@example.com',
            password: 'correct horse battery staple',
          ),
          throwsA(
            isA<ControlPlaneException>().having(
              (error) => error.code,
              'code',
              'PLAN_LIMIT_REACHED',
            ),
          ),
        );
        expect(await authStore.listJson('users'), hasLength(1));
      } finally {
        await authStore.close();
        await authDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'downgrade keeps existing resources and blocks further growth',
    () async {
      await activateProviderPlan(
        service.billing,
        bootstrap.organization.id,
        cloudPlanTeamKey,
      );
      final second = await service.createApplication(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
        runtimeApplicationId: 'com.example.team-second',
        idempotencyKey: 'team-second-application',
      );
      expect(await service.store.listJson('applications'), hasLength(2));

      final teamPlan = (await service.store.listJson('billing_plans')).single;
      await service.billing.upsertSubscription(
        organizationId: bootstrap.organization.id,
        provider: 'razorpay',
        providerSubscriptionId: 'subscription-$cloudPlanTeamKey',
        providerPlanId: 'provider-$cloudPlanTeamKey',
        status: 'cancelled',
        planId: teamPlan['id']! as String,
      );

      final resolved = await service.billing.resolveEffectiveEntitlements(
        organizationId: bootstrap.organization.id,
      );
      expect(resolved.planKey, cloudPlanFreeKey);
      expect(await service.store.listJson('applications'), hasLength(2));
      await expectLater(
        service.createApplication(
          token: bootstrap.controlCredential.token,
          organizationId: bootstrap.organization.id,
          runtimeApplicationId: 'com.example.team-third',
          idempotencyKey: 'team-third-application',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'PLAN_LIMIT_REACHED',
          ),
        ),
      );
      expect(second.organizationId, bootstrap.organization.id);
    },
  );

  test('Free assignment is idempotent under repeated provisioning', () async {
    await Future.wait(
      List<Future<Map<String, Object?>>>.generate(
        6,
        (_) => service.billing.ensureCloudPlanAssignment(
          organizationId: bootstrap.organization.id,
        ),
      ),
    );

    final subscriptions = await service.billing.read(
      organizationId: bootstrap.organization.id,
    );
    expect(
      subscriptions.subscriptions.where(
        (row) => row['cloudPlanKey'] == cloudPlanFreeKey,
      ),
      hasLength(1),
    );
  });

  test('paid provider state wins without changing the workspace', () async {
    final paidPlan = await service.billing.createPlan(
      organizationId: bootstrap.organization.id,
      key: cloudPlanStarterKey,
      name: 'Starter',
      description: 'Cloud Starter test plan',
      currency: 'INR',
      amountMinor: 4900,
      interval: 'monthly',
      period: 1,
      provider: 'razorpay',
      providerPlanId: 'plan_starter_test',
    );
    await service.billing.upsertSubscription(
      organizationId: bootstrap.organization.id,
      provider: 'razorpay',
      providerSubscriptionId: 'sub_starter_test',
      providerPlanId: 'plan_starter_test',
      status: 'active',
      planId: paidPlan['id']! as String,
    );

    final resolved = await service.billing.resolveEffectiveEntitlements(
      organizationId: bootstrap.organization.id,
    );
    final applications = await service.store.listJson('applications');

    expect(resolved.planKey, cloudPlanStarterKey);
    expect(resolved.source, 'provider_subscription');
    expect(applications, hasLength(1));
    expect(applications.single['organizationId'], bootstrap.organization.id);
    expect(
      (await service.billing.read(organizationId: bootstrap.organization.id))
          .subscriptions
          .where((row) => row['cloudPlanKey'] == cloudPlanFreeKey),
      hasLength(1),
    );
  });

  test('Cloud backfill preserves an existing paid organization', () async {
    final legacyDirectory = await Directory.systemTemp.createTemp(
      'hyfens-cloud-paid-backfill-',
    );
    try {
      final legacyStore = FileControlPlaneStore(legacyDirectory);
      await legacyStore.initialize();
      final organization = OrganizationRecord(
        id: 'org_legacy_paid',
        name: 'Legacy paid organization',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await legacyStore.createJson(
        'organizations',
        organization.id,
        organization.toJson(),
      );
      final legacyService = ControlPlaneService(
        store: legacyStore,
        random: Random(9),
        deploymentModel: DeploymentModel.cloud,
      );
      final paidPlan = await legacyService.billing.createPlan(
        organizationId: organization.id,
        key: cloudPlanTeamKey,
        name: 'Team',
        description: 'Cloud Team test plan',
        currency: 'INR',
        amountMinor: 19900,
        interval: 'monthly',
        period: 1,
        provider: 'razorpay',
        providerPlanId: 'plan_team_backfill_test',
      );
      await legacyService.billing.upsertSubscription(
        organizationId: organization.id,
        provider: 'razorpay',
        providerSubscriptionId: 'sub_team_backfill_test',
        providerPlanId: 'plan_team_backfill_test',
        status: 'active',
        planId: paidPlan['id']! as String,
      );

      await legacyService.initialize();
      final snapshot = await legacyService.billing.read(
        organizationId: organization.id,
      );

      expect(snapshot.effectivePlan?['key'], cloudPlanTeamKey);
      expect(
        snapshot.subscriptions.where((row) => row['provider'] == 'internal'),
        isEmpty,
      );
    } finally {
      await legacyDirectory.delete(recursive: true);
    }
  });

  test('Cloud scope authorization uses the server catalog', () async {
    final catalogId = 'cloud_plan_$cloudPlanFreeKey';
    final catalog = await service.store.readJson(
      'billing_plan_catalog',
      catalogId,
    );
    expect(catalog, isNotNull);
    await service.store.replaceJson(
      'billing_plan_catalog',
      catalogId,
      <String, Object?>{...catalog!, 'capabilities': <String>[]},
    );

    await expectLater(
      service.createApplication(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
        runtimeApplicationId: 'com.example.blocked',
        idempotencyKey: 'blocked-application',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'FORBIDDEN',
        ),
      ),
    );
  });

  test('self-hosted never receives a Cloud subscription assignment', () async {
    final selfHostedDirectory = await Directory.systemTemp.createTemp(
      'hyfens-self-hosted-plan-',
    );
    try {
      final selfHosted = ControlPlaneService(
        store: FileControlPlaneStore(selfHostedDirectory),
        random: Random(8),
      );
      final result = await selfHosted.bootstrap(
        organizationName: 'Self-hosted plan test',
        runtimeApplicationId: 'com.example.self-hosted-plan',
        platformId: 'android',
        environmentName: 'development',
      );
      final snapshot = await selfHosted.billing.read(
        organizationId: result.organization.id,
      );

      expect(snapshot.subscriptions, isEmpty);
      expect(snapshot.effectivePlan?['key'], isNull);
      expect(snapshot.deploymentModel, 'self_hosted');
      final second = await selfHosted.createApplication(
        token: result.controlCredential.token,
        organizationId: result.organization.id,
        runtimeApplicationId: 'com.example.self-hosted-second',
        idempotencyKey: 'self-hosted-second-application',
      );
      expect(second.organizationId, result.organization.id);
    } finally {
      await selfHostedDirectory.delete(recursive: true);
    }
  });

  test('Cloud plan ordering excludes Self-hosted', () {
    expect(cloudPlanOrder, <String>[
      cloudPlanFreeKey,
      cloudPlanStarterKey,
      cloudPlanTeamKey,
      cloudPlanEnterpriseKey,
    ]);
    expect(
      cloudPlanRank(cloudPlanFreeKey),
      lessThan(cloudPlanRank(cloudPlanStarterKey)),
    );
    expect(
      cloudPlanRank(cloudPlanStarterKey),
      lessThan(cloudPlanRank(cloudPlanTeamKey)),
    );
    expect(
      cloudPlanRank(cloudPlanTeamKey),
      lessThan(cloudPlanRank(cloudPlanEnterpriseKey)),
    );
    expect(isCloudPlanKey('self_hosted'), isFalse);
    expect(isCloudPlanKey('self-hosted'), isFalse);
    for (final definition in defaultCloudPlanCatalog) {
      expect(definition.capabilities, containsAll(cloudCoreEntitlements));
    }
  });
}
