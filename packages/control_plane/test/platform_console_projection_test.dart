import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late ControlPlaneService service;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-platform-console-',
    );
    store = FileControlPlaneStore(directory);
    await store.initialize();
    service = ControlPlaneService(
      store: store,
      deploymentModel: DeploymentModel.cloud,
    );
    await service.initialize();
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('entitlements project one named row for each Cloud plan', () async {
    await store.createJson(
      'organizations',
      'org_deleted',
      OrganizationRecord(
        id: 'org_deleted',
        name: 'Deleted customer workspace',
        createdAt: DateTime.utc(2026, 9, 1),
        deletionState: 'deleted',
        deletedAt: DateTime.utc(2026, 9, 2),
      ).toJson(),
    );

    await store.createJson(
      'billing_subscriptions',
      'subscription_deleted',
      <String, Object?>{
        'id': 'subscription_deleted',
        'organizationId': 'org_deleted',
        'cloudPlanKey': cloudPlanStarterKey,
        'planId': 'tenant_plan_starter',
        'status': 'active',
        'createdAt': '2026-09-01T00:00:00Z',
        'updatedAt': '2026-09-01T00:00:00Z',
      },
    );

    final projection = await PlatformConsoleProjection(store)
        .readEntitlements();
    final plans = (projection['plans']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final keys = plans.map((plan) => plan['key']).toList(growable: false);

    expect(
      keys,
      containsAll(<String>[
        cloudPlanFreeKey,
        cloudPlanStarterKey,
        cloudPlanTeamKey,
        cloudPlanEnterpriseKey,
      ]),
    );
    expect(keys.toSet(), hasLength(4));
    expect(plans.every((plan) => plan['name'] is String), isTrue);

    final subscriptions = (projection['subscriptions']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      subscriptions.single['organizationName'],
      'Deleted customer workspace',
    );
    expect(subscriptions.single['organizationStatus'], 'deleted');
    expect(subscriptions.single['planName'], 'Starter');
  });

  test('Cloud plan edits are reasoned, idempotent, and audited', () async {
    final admin = PlatformCloudPlanAdministrationService(store: store);
    final limits = <String, Object?>{
      cloudApplicationsLimitKey: const <String, Object?>{'type': 'unlimited'},
      cloudEnvironmentsPerApplicationLimitKey: const <String, Object?>{
        'type': 'finite',
        'value': 3,
      },
      cloudMembersLimitKey: const <String, Object?>{
        'type': 'finite',
        'value': 8,
      },
    };

    final first = await admin.update(
      planKey: cloudPlanStarterKey,
      name: 'Starter production',
      description: 'Production workspaces for a small team.',
      active: true,
      limits: limits,
      reason: 'Align the starter entitlement copy with the approved offer.',
      actorId: 'usr_platform_owner',
      requestId: 'req-plan-update-1',
      idempotencyKey: 'plan-update-1',
    );
    final repeated = await admin.update(
      planKey: cloudPlanStarterKey,
      name: 'Starter production',
      description: 'Production workspaces for a small team.',
      active: true,
      limits: limits,
      reason: 'Align the starter entitlement copy with the approved offer.',
      actorId: 'usr_platform_owner',
      requestId: 'req-plan-update-retry',
      idempotencyKey: 'plan-update-1',
    );

    expect(repeated, first);
    final persisted = await store.readJson(
      platformCloudPlanCatalogCollection,
      'cloud_plan_starter',
    );
    expect(persisted?['name'], 'Starter production');
    expect(persisted?['limits'], limits);
    await service.billing.ensurePlanCatalog();
    final afterBillingInitialization = await store.readJson(
      platformCloudPlanCatalogCollection,
      'cloud_plan_starter',
    );
    expect(afterBillingInitialization?['name'], 'Starter production');
    expect(afterBillingInitialization?['limits'], limits);
    final audits = await store.listJson('audit');
    final planAudits = audits
        .where((value) => value['action'] == 'platform.cloud_plan.updated')
        .toList(growable: false);
    expect(planAudits, hasLength(1));
    expect(
      (planAudits.single['metadata']! as Map<String, Object?>)['reason'],
      'Align the starter entitlement copy with the approved offer.',
    );
  });
}
