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
    directory = await Directory.systemTemp.createTemp('hyfens-operational-');
    store = FileControlPlaneStore(directory);
    auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'operational-backlog-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 23),
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

  test('organization invitations redeem once, mutate roles, and transfer ownership', () async {
    final owner = await auth.login(
      email: demoOwnerEmail,
      password: 'demo-password',
    );
    final issued = await service.inviteOrganizationMember(
      token: owner.accessToken,
      organizationId: demo.organization.id,
      email: 'developer@example.com',
      role: 'developer',
    );

    final preview = await service.previewOrganizationInvitation(
      token: issued.token,
    );
    expect(preview['email'], 'developer@example.com');
    expect(preview['organization'], demoOrganizationName);
    expect(preview['status'], 'PENDING');
    expect(preview.containsKey('createdBy'), isFalse);
    expect(preview.containsKey('capabilities'), isFalse);

    final accepted = await service.acceptOrganizationInvitation(
      token: issued.token,
      email: 'DEVELOPER@example.com',
      password: 'developer-password',
    );
    expect(accepted['accepted'], isTrue);
    expect(accepted['idempotent'], isFalse);
    final invitedUserId =
        (accepted['member']! as Map<String, Object?>)['id']! as String;

    final roleUpdated = await service.updateOrganizationMemberRole(
      token: owner.accessToken,
      organizationId: demo.organization.id,
      userId: invitedUserId,
      role: 'auditor',
    );
    expect(_mapList(roleUpdated['memberships']).single['role'], 'auditor');

    await service.removeOrganizationMember(
      token: owner.accessToken,
      organizationId: demo.organization.id,
      userId: invitedUserId,
    );
    final removed = await auth.userById(invitedUserId);
    expect(removed, isNotNull);
    expect(removed!.active, isFalse);
    expect(removed.memberships.single.active, isFalse);

    final idempotent = await service.acceptOrganizationInvitation(
      token: issued.token,
      email: 'developer@example.com',
      password: 'developer-password',
    );
    expect(idempotent['accepted'], isTrue);
    expect(idempotent['idempotent'], isTrue);

    final targetLogin = await auth.registerInvitedCustomer(
      organizationId: demo.organization.id,
      email: 'new-owner@example.com',
      password: 'new-owner-password',
      role: 'developer',
      capabilities: customerCapabilitiesForRole('developer'),
    );
    final transfer = await service.transferOrganizationOwnership(
      token: owner.accessToken,
      organizationId: demo.organization.id,
      targetUserId: targetLogin.identity.user.id,
    );
    expect(
      (transfer['owner']! as Map<String, Object?>)['memberships']! as List,
      hasLength(1),
    );
    final transferredMemberships = _mapList(
      (transfer['owner']! as Map<String, Object?>)['memberships'],
    );
    expect(transferredMemberships.single['role'], 'owner');
    final formerOwner = await auth.userById(owner.identity.user.id);
    expect(
      formerOwner!.memberships
          .firstWhere(
            (membership) => membership.organizationId == demo.organization.id,
          )
          .role,
      'admin',
    );
  });

  test(
    'an authenticated platform user can accept a customer invitation without '
    'sharing platform credentials',
    () async {
      final owner = await auth.login(
        email: demoOwnerEmail,
        password: 'demo-password',
      );
      final platformUser = await auth.registerInvitedPlatformStaff(
        email: 'platform-developer@example.com',
        password: 'platform-password',
        role: 'support',
      );
      final issued = await service.inviteOrganizationMember(
        token: owner.accessToken,
        organizationId: demo.organization.id,
        email: 'platform-developer@example.com',
        role: 'developer',
      );

      final accepted = await service.acceptOrganizationInvitation(
        token: issued.token,
        accessToken: platformUser.accessToken,
        email: 'platform-developer@example.com',
      );
      final login = accepted['login']! as Map<String, Object?>;
      expect(login['authorization_audience'], customerAuthorizationAudience);

      final customerIdentity = await auth.me(
        accessToken: login['access_token']! as String,
      );
      expect(
        customerIdentity.profiles.any(
          (profile) => profile.organizationId == demo.organization.id,
        ),
        isTrue,
      );
      expect(
        customerIdentity.profiles.any((profile) => profile.platform),
        isFalse,
      );
    },
  );

  test('invitation revocation and expiry fail closed', () async {
    final owner = await auth.login(
      email: demoOwnerEmail,
      password: 'demo-password',
    );
    final revoked = await service.inviteOrganizationMember(
      token: owner.accessToken,
      organizationId: demo.organization.id,
      email: 'revoked@example.com',
      role: 'auditor',
    );
    await service.revokeOrganizationInvitation(
      token: owner.accessToken,
      organizationId: demo.organization.id,
      invitationId: revoked.record.id,
    );
    await _expectCode(
      () => service.acceptOrganizationInvitation(
        token: revoked.token,
        email: 'revoked@example.com',
        password: 'revoked-password',
      ),
      'INVITATION_REVOKED',
    );

    final expired = OrganizationInvitationRecord(
      id: 'inv_expired',
      organizationId: demo.organization.id,
      email: 'expired@example.com',
      role: 'auditor',
      capabilities: customerCapabilitiesForRole('auditor'),
      tokenHash: 'hash',
      createdBy: demo.owner.id,
      createdAt: DateTime.utc(2026, 1, 1),
      expiresAt: DateTime.utc(2026, 1, 2),
    );
    expect(expired.statusAt(DateTime.utc(2026, 1, 3)), 'EXPIRED');
    expect(
      expired.toMetadataJson(now: DateTime.utc(2026, 1, 3))['active'],
      isFalse,
    );
  });

  test(
    'failed invitation delivery revokes the bearer before returning',
    () async {
      final owner = await auth.login(
        email: demoOwnerEmail,
        password: 'demo-password',
      );
      final deliveryFailingService = ControlPlaneService(
        store: store,
        humanAuth: auth,
        invitationDelivery: const _FailingInvitationDelivery(),
      );
      await _expectCode(
        () => deliveryFailingService.inviteOrganizationMember(
          token: owner.accessToken,
          organizationId: demo.organization.id,
          email: 'delivery-failure@example.com',
          role: 'auditor',
        ),
        'INVITATION_DELIVERY_FAILED',
      );
      final stored = (await store.listJson('organization_invitations'))
          .singleWhere(
            (value) => value['email'] == 'delivery-failure@example.com',
          );
      expect(stored['status'], 'REVOKED');
      expect(stored['deliveryStatus'], 'FAILED');
      expect(jsonEncode(stored), isNot(contains('hvi_')));
    },
  );

  test(
    'platform staff administration is capability-checked and auditable',
    () async {
      final platformAdmin = await auth.login(
        email: demoOwnerEmail,
        password: 'demo-password',
        audience: platformAuthorizationAudience,
        profileName: demoOwnerProfileName,
      );
      final issued = await service.invitePlatformStaff(
        accessToken: platformAdmin.accessToken,
        profileName: demoOwnerProfileName,
        email: 'support@example.com',
        role: 'support',
      );
      final invitationMetadata = await service.listPlatformStaffInvitations(
        accessToken: platformAdmin.accessToken,
        profileName: demoOwnerProfileName,
      );
      expect(invitationMetadata.single['email'], 'support@example.com');
      expect(invitationMetadata.single['active'], isTrue);

      final accepted = await service.acceptPlatformStaffInvitation(
        token: issued.token,
        email: 'support@example.com',
        password: 'support-password',
      );
      final supportId =
          (accepted['login']! as Map<String, Object?>)['user_id']! as String;
      final listed = await PlatformConsoleProjection(store).listUsers();
      final staff = (listed['users']! as List).cast<Map<String, Object?>>();
      expect(staff.any((item) => item['id'] == supportId), isTrue);
      final firstStaffPage = await PlatformConsoleProjection(store)
          .listUsers(limit: 1);
      expect(firstStaffPage['pagination'], isA<Map<String, Object?>>());
      expect(
        (firstStaffPage['pagination']! as Map<String, Object?>)['total'],
        2,
      );

      final updated = await service.updatePlatformStaff(
        accessToken: platformAdmin.accessToken,
        profileName: demoOwnerProfileName,
        userId: supportId,
        role: 'operations',
      );
      expect(_mapList(updated['memberships']).single['role'], 'operations');

      final support = await auth.login(
        email: 'support@example.com',
        password: 'support-password',
        audience: platformAuthorizationAudience,
        profileName: 'platform-operations',
      );
      final revokedCount = await service.revokePlatformStaffSessions(
        accessToken: platformAdmin.accessToken,
        profileName: demoOwnerProfileName,
        userId: supportId,
      );
      expect(revokedCount, greaterThanOrEqualTo(1));
      await _expectCode(
        () => auth.me(accessToken: support.accessToken),
        'UNAUTHORIZED',
      );

      final deactivated = await service.updatePlatformStaff(
        accessToken: platformAdmin.accessToken,
        profileName: demoOwnerProfileName,
        userId: supportId,
        active: false,
      );
      expect(deactivated['active'], isFalse);
      await _expectCode(
        () => auth.authorizePlatformCapability(
          accessToken: support.accessToken,
          capability: platformOperationsReadCapability,
          profileName: 'platform-operations',
        ),
        'UNAUTHORIZED',
      );
    },
  );

  test(
    'privileged platform MFA enforcement fails closed when enabled',
    () async {
      final platform = await auth.login(
        email: demoOwnerEmail,
        password: 'demo-password',
        audience: platformAuthorizationAudience,
        profileName: demoOwnerProfileName,
      );
      final mfaRequiredAuth = HumanAuthService(
        store: store,
        config: HumanAuthConfig(
          issuer: 'operational-backlog-test',
          audience: 'hyfens-control',
          signingKeySeed: List<int>.filled(32, 23),
          platformAdminEmails: const <String>[demoOwnerEmail],
          platformMfaRequired: true,
        ),
      );
      await mfaRequiredAuth.initialize();
      await _expectCode(
        () => mfaRequiredAuth.authorizePlatformCapability(
          accessToken: platform.accessToken,
          capability: platformOverviewCapability,
          profileName: demoOwnerProfileName,
        ),
        'PLATFORM_MFA_REQUIRED',
      );
    },
  );

  test(
    'operations and commercial history report only bounded honest data',
    () async {
      final metrics = await PlatformMetricsProjection(store: store).read();
      expect(metrics['operations'], isA<Map<String, Object?>>());
      expect(
        (metrics['operations']! as Map<String, Object?>)['status'],
        'UNKNOWN',
      );
      final organizations = await PlatformConsoleProjection(store)
          .listOrganizationsPage(limit: 1);
      expect(organizations['pagination'], isA<Map<String, Object?>>());

      final history = await PlatformCommercialProjection(store).readHistory();
      expect(history['status'], 'SOURCE_NOT_AVAILABLE');
      expect(history['cashRevenueAvailable'], isFalse);
      expect(jsonEncode(history), isNot(contains('password')));

      await service.billing.recordEvent(
        organizationId: demo.organization.id,
        provider: 'razorpay',
        eventId: 'evt_subscription_created',
        eventName: 'subscription.created',
        payloadDigest: List<String>.filled(64, 'a').join(),
      );
      final historyWithEvent = await PlatformCommercialProjection(store)
          .readHistory(limit: 1);
      expect(historyWithEvent['historyAvailable'], isTrue);
      expect(historyWithEvent['events'], hasLength(1));
    },
  );
}

Future<void> _expectCode(Future<Object?> Function() action, String code) async {
  try {
    await action();
    fail('Expected $code');
  } on ControlPlaneException catch (error) {
    expect(error.code, code);
  }
}

List<Map<String, Object?>> _mapList(Object? value) => (value! as List<Object?>)
    .map((item) => item! as Map<String, Object?>)
    .toList(growable: false);

final class _FailingInvitationDelivery
    implements OrganizationInvitationDelivery {
  const _FailingInvitationDelivery();

  @override
  Future<void> deliver(InvitationDeliveryRequest request) async {
    throw StateError('delivery provider unavailable');
  }
}
