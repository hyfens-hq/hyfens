import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late HumanAuthService auth;
  late ControlPlaneService service;
  late DemoSeedResult demo;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-operational-mvp-',
    );
    store = FileControlPlaneStore(directory);
    auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'operational-mvp-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 19),
        platformAdminEmails: const <String>[demoOwnerEmail],
      ),
    );
    service = ControlPlaneService(store: store, humanAuth: auth);
    demo = await DemoAccountSeeder(
      store: store,
      auth: auth,
    ).seed(password: 'demo-password');
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'customer application and environment lifecycle stays tenant-scoped',
    () async {
      final customer = await auth.login(
        email: demoOwnerEmail,
        password: 'demo-password',
      );
      final application = await service.createApplication(
        token: customer.accessToken,
        organizationId: demo.organization.id,
        runtimeApplicationId: 'com.auvana.operational',
        name: 'Operational app',
        platform: 'android',
        idempotencyKey: 'operational-app-create',
      );
      final renamedApplication = await service.updateApplication(
        token: customer.accessToken,
        organizationId: demo.organization.id,
        applicationId: application.id,
        name: 'Renamed operational app',
      );
      expect(renamedApplication.name, 'Renamed operational app');

      final environment = await service.createEnvironment(
        token: customer.accessToken,
        organizationId: demo.organization.id,
        applicationId: application.id,
        name: 'staging',
        idempotencyKey: 'operational-env-create',
      );
      final renamedEnvironment = await service.updateEnvironment(
        token: customer.accessToken,
        organizationId: demo.organization.id,
        environmentId: environment.id,
        name: 'pre-production',
      );
      expect(renamedEnvironment.name, 'pre-production');

      final archivedEnvironment = await service.archiveEnvironment(
        token: customer.accessToken,
        organizationId: demo.organization.id,
        environmentId: environment.id,
      );
      final archivedApplication = await service.archiveApplication(
        token: customer.accessToken,
        organizationId: demo.organization.id,
        applicationId: application.id,
      );
      expect(archivedEnvironment.status, 'archived');
      expect(archivedApplication.status, 'archived');

      final other = await service.bootstrap(
        organizationName: 'Other operational organization',
        runtimeApplicationId: 'com.example.other.operational',
        platformId: 'android',
        environmentName: 'development',
      );
      await service.bootstrapOwner(
        organizationId: other.organization.id,
        applicationId: other.application.id,
        environmentId: other.environment.id,
        email: 'other-operational@example.com',
        password: 'other-password',
      );
      final otherLogin = await auth.login(
        email: 'other-operational@example.com',
        password: 'other-password',
      );
      await _expectCode(
        () => service.updateApplication(
          token: otherLogin.accessToken,
          organizationId: demo.organization.id,
          applicationId: application.id,
          name: 'cross-tenant update',
        ),
        'NOT_FOUND',
      );
    },
  );

  test('invitations persist only hashes and can be revoked', () async {
    final customer = await auth.login(
      email: demoOwnerEmail,
      password: 'demo-password',
    );
    final issued = await service.inviteOrganizationMember(
      token: customer.accessToken,
      organizationId: demo.organization.id,
      email: 'developer@example.com',
      role: 'developer',
    );
    expect(issued.token, isNotEmpty);
    final persisted = await store.readJson(
      'organization_invitations',
      issued.record.id,
    );
    expect(persisted, isNotNull);
    expect(persisted!.containsKey('token'), isFalse);
    expect(persisted['tokenHash'], isNot(issued.token));

    final listed = await service.listOrganizationInvitations(
      token: customer.accessToken,
      organizationId: demo.organization.id,
    );
    expect(listed.single['active'], isTrue);
    expect(jsonEncode(listed), isNot(contains(issued.token)));

    await service.revokeOrganizationInvitation(
      token: customer.accessToken,
      organizationId: demo.organization.id,
      invitationId: issued.record.id,
    );
    final revoked = await service.listOrganizationInvitations(
      token: customer.accessToken,
      organizationId: demo.organization.id,
    );
    expect(revoked.single['active'], isFalse);
  });

  test(
    'support cases isolate internal notes and enforce platform capabilities',
    () async {
      final customer = await auth.login(
        email: demoOwnerEmail,
        password: 'demo-password',
      );
      final platform = await auth.login(
        email: demoOwnerEmail,
        password: 'demo-password',
        audience: platformAuthorizationAudience,
      );
      final created = await service.createSupportCase(
        token: customer.accessToken,
        organizationId: demo.organization.id,
        subject: 'Demo support question',
        description: 'The customer-visible question',
      );
      final caseId =
          (created['case']! as Map<String, Object?>)['id']! as String;

      final internal = await service.replyPlatformSupportCase(
        accessToken: platform.accessToken,
        profileName: demoOwnerProfileName,
        caseId: caseId,
        body: 'Staff-only diagnostic note',
        visibility: platformInternalSupportVisibility,
      );
      expect(jsonEncode(internal), contains('Staff-only diagnostic note'));

      final customerView = await service.readSupportCase(
        token: customer.accessToken,
        organizationId: demo.organization.id,
        caseId: caseId,
      );
      expect(
        jsonEncode(customerView),
        isNot(contains('Staff-only diagnostic note')),
      );

      final platformView = await service.readPlatformSupportCase(
        accessToken: platform.accessToken,
        profileName: demoOwnerProfileName,
        caseId: caseId,
      );
      expect(jsonEncode(platformView), contains('Staff-only diagnostic note'));

      await _expectCode(
        () => service.updatePlatformSupportCase(
          accessToken: platform.accessToken,
          profileName: demoOwnerProfileName,
          caseId: caseId,
          assignedTo: 'not-a-platform-user',
        ),
        'INVALID_SUPPORT_ASSIGNEE',
      );
      final updated = await service.updatePlatformSupportCase(
        accessToken: platform.accessToken,
        profileName: demoOwnerProfileName,
        caseId: caseId,
        assignedTo: demo.owner.id,
        status: 'IN_PROGRESS',
      );
      expect(
        (updated['case']! as Map<String, Object?>)['assignedTo'],
        demo.owner.id,
      );
      expect(
        (updated['case']! as Map<String, Object?>)['status'],
        'IN_PROGRESS',
      );

      await _expectCode(
        () =>
            service.listPlatformSupportCases(accessToken: customer.accessToken),
        'FORBIDDEN',
      );
    },
  );

  test('commercial projection uses active plans and reports missing sources honestly', () async {
    final unavailable = await PlatformCommercialProjection(store).read();
    expect(unavailable['status'], 'SOURCE_NOT_AVAILABLE');
    expect(unavailable['mrrMinor'], isNull);

    final plan = await service.billing.createPlan(
      organizationId: demo.organization.id,
      key: 'demo-monthly',
      name: 'Demo monthly',
      description: 'Operational test plan',
      currency: 'INR',
      amountMinor: 125000,
      interval: 'monthly',
      period: 1,
      provider: 'razorpay',
      providerPlanId: 'plan_operational_demo',
    );
    await service.billing.upsertSubscription(
      organizationId: demo.organization.id,
      provider: 'razorpay',
      providerSubscriptionId: 'sub_operational_demo',
      providerPlanId: 'plan_operational_demo',
      planId: plan['id']! as String,
      status: 'active',
    );

    final available = await PlatformCommercialProjection(store).read();
    expect(available['status'], 'AVAILABLE');
    expect(available['currency'], 'INR');
    expect(available['mrrMinor'], 125000);
    expect(available['arrMinor'], 1500000);
    expect(available['paidOrganizations'], 1);

    await service.billing.setPlanActive(
      organizationId: demo.organization.id,
      planId: plan['id']! as String,
      active: false,
    );
    final inactive = await PlatformCommercialProjection(store).read();
    expect(inactive['status'], 'SOURCE_NOT_AVAILABLE');
  });
}

Future<void> _expectCode(
  Future<Object?> Function() operation,
  String expected,
) async {
  try {
    await operation();
    fail('Expected ControlPlaneException($expected)');
  } on ControlPlaneException catch (error) {
    expect(error.code, expected);
  }
}
