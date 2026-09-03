import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late HumanAuthService auth;
  late DemoAccountSeeder seeder;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-demo-seed-');
    store = FileControlPlaneStore(directory);
    auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'demo-seed-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 3),
        platformAdminEmails: const <String>[demoOwnerEmail],
      ),
    );
    seeder = DemoAccountSeeder(store: store, auth: auth);
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('creates the fixed Auvana scope idempotently', () async {
    final first = await seeder.seed(password: 'demo-password-one');
    final second = await seeder.seed(password: 'demo-password-two');

    expect(first.organization.id, demoOrganizationId);
    expect(first.organization.name, demoOrganizationName);
    expect(first.application.id, demoApplicationId);
    expect(first.application.runtimeApplicationId, demoRuntimeApplicationId);
    expect(first.environment.id, demoEnvironmentId);
    expect(first.owner.email, demoOwnerEmail);
    expect(first.owner.id, second.owner.id);
    expect(first.owner.passwordHash, second.owner.passwordHash);
    expect(await store.listJson('organizations'), hasLength(1));
    expect(await store.listJson('applications'), hasLength(1));
    expect(await store.listJson('environments'), hasLength(1));
    expect(await store.listJson('users'), hasLength(1));

    expect(first.owner.memberships, hasLength(2));
    final customerMembership = first.owner.memberships.singleWhere(
      (item) => item.profileName == demoCustomerProfileName,
    );
    expect(customerMembership.organizationId, demoOrganizationId);
    expect(customerMembership.profileApplicationId, demoApplicationId);
    expect(customerMembership.profileEnvironmentId, demoEnvironmentId);
    expect(customerMembership.role, 'owner');
    expect(customerMembership.audience, customerAuthorizationAudience);
    expect(customerMembership.capabilities, containsAll(controlScopes));

    final platformMembership = first.owner.memberships.singleWhere(
      (item) => item.profileName == demoOwnerProfileName,
    );
    expect(platformMembership.organizationId, demoOrganizationId);
    expect(platformMembership.profileApplicationId, demoApplicationId);
    expect(platformMembership.profileEnvironmentId, demoEnvironmentId);
    expect(platformMembership.role, 'owner');
    expect(platformMembership.audience, platformAuthorizationAudience);
    expect(platformMembership.capabilities, containsAll(controlScopes));
    expect(
      platformMembership.platformCapabilities,
      containsAll(platformCapabilities),
    );

    final userJson = (await store.listJson('users')).single;
    expect(userJson['passwordHash'], isNot(contains('demo-password')));
  });

  test(
    'rejects a conflicting fixed organization instead of overwriting it',
    () async {
      await store.initialize();
      await store.createJson(
        'organizations',
        demoOrganizationId,
        <String, Object?>{
          'id': demoOrganizationId,
          'name': 'Different organization',
          'createdAt': DateTime.utc(2026, 9, 3).toIso8601String(),
        },
      );

      await expectLater(
        () => seeder.seed(password: 'demo-password'),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'DEMO_SEED_CONFLICT',
          ),
        ),
      );
    },
  );
}
