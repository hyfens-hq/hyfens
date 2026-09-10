import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

final class _DeletionDelivery
    implements HumanAuthMessageDelivery, HumanDeletionMessageDelivery {
  final List<String> verificationTokens = <String>[];
  final List<String> recoveryTokens = <String>[];
  final List<String> deletionTokens = <String>[];

  @override
  Future<void> sendVerificationEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) async {
    verificationTokens.add(token);
  }

  @override
  Future<void> sendRecoveryEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) async {
    recoveryTokens.add(token);
  }

  @override
  Future<void> sendDeletionEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) async {
    deletionTokens.add(token);
  }
}

final class _Customer {
  const _Customer({required this.userId, required this.organizationId});

  final String userId;
  final String organizationId;
}

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late _DeletionDelivery delivery;
  late HumanAuthService auth;
  late ControlPlaneService service;
  late DateTime now;

  setUp(() async {
    now = DateTime.utc(2026, 9, 9, 10);
    directory = await Directory.systemTemp.createTemp('hyfens-deletion-');
    store = FileControlPlaneStore(directory);
    delivery = _DeletionDelivery();
    auth = HumanAuthService(
      store: store,
      messageDelivery: delivery,
      deletionMessageDelivery: delivery,
      config: HumanAuthConfig(
        issuer: 'deletion-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 73),
      ),
      clock: () => now,
    );
    service = ControlPlaneService(
      store: store,
      humanAuth: auth,
      deploymentModel: DeploymentModel.cloud,
      deletionPolicy: const DeletionPolicy(gracePeriod: Duration(hours: 1)),
      clock: () => now,
    );
    deliveryForCurrentTest = delivery;
    serviceForCurrentTest = service;
    await service.initialize();
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'no-login deletion is neutral, purpose-bound, expiring, and one-time',
    () async {
      final customer = await _createCustomer(
        email: 'privacy@example.com',
        password: 'correct horse battery staple',
      );

      await auth.requestAccountDeletion(email: 'unknown@example.com');
      expect(delivery.deletionTokens, isEmpty);

      await auth.requestAccountDeletion(email: 'privacy@example.com');
      expect(delivery.deletionTokens, hasLength(1));
      final deletionToken = delivery.deletionTokens.single;

      await auth.requestPasswordRecovery(email: 'privacy@example.com');
      expect(delivery.recoveryTokens, hasLength(1));
      await expectLater(
        auth.consumeAccountDeletionToken(token: delivery.recoveryTokens.single),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'DELETION_TOKEN_INVALID',
          ),
        ),
      );

      expect(
        await auth.consumeAccountDeletionToken(token: deletionToken),
        customer.userId,
      );
      await expectLater(
        auth.consumeAccountDeletionToken(token: deletionToken),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'DELETION_TOKEN_INVALID',
          ),
        ),
      );

      await auth.requestAccountDeletion(email: 'privacy@example.com');
      final expiringToken = delivery.deletionTokens.last;
      now = now.add(const Duration(minutes: 31));
      await expectLater(
        auth.consumeAccountDeletionToken(token: expiringToken),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'DELETION_TOKEN_INVALID',
          ),
        ),
      );
    },
  );

  test('sole-owner account deletion stops at ownership resolution', () async {
    final customer = await _createCustomer(
      email: 'owner@example.com',
      password: 'correct horse battery staple',
    );

    final result = await service.deletion!.requestAccountDeletion(
      userId: customer.userId,
      actorId: customer.userId,
      requestId: 'request-owner-delete',
    );

    expect(result['status'], 'ownership_resolution_required');
    expect(result['ownershipRequiredOrganizations'], [customer.organizationId]);
    expect((await store.readJson('users', customer.userId))!['active'], isTrue);
    expect(
      (await store.readJson(
        'organizations',
        customer.organizationId,
      ))!['deletionState'],
      'active',
    );
  });

  test(
    'non-owner account deletion deactivates identity only after grace',
    () async {
      final customer = await _createCustomer(
        email: 'member@example.com',
        password: 'correct horse battery staple',
      );
      final user = HumanUserRecord.fromJson(
        (await store.readJson('users', customer.userId))!,
      );
      final membership = user.memberships.single;
      final nonOwner = HumanMembership(
        organizationId: membership.organizationId,
        role: 'member',
        capabilities: membership.capabilities,
        profileName: membership.profileName,
        audience: membership.audience,
        platformCapabilities: membership.platformCapabilities,
      );
      await store.replaceJson(
        'users',
        customer.userId,
        user.copyWith(memberships: <HumanMembership>[nonOwner]).toJson(),
      );

      final request = await service.deletion!.requestAccountDeletion(
        userId: customer.userId,
        actorId: customer.userId,
        requestId: 'request-member-delete',
      );
      expect(request['status'], 'grace_period');

      final beforeGrace = await service.deletion!.processDeletion(
        requestId: request['id']! as String,
        now: now,
      );
      expect(beforeGrace['status'], 'grace_period');

      now = now.add(const Duration(hours: 2));
      final completed = await service.deletion!.processDeletion(
        requestId: request['id']! as String,
        now: now,
      );
      expect(completed['status'], 'completed');
      final deleted = HumanUserRecord.fromJson(
        (await store.readJson('users', customer.userId))!,
      );
      expect(deleted.active, isFalse);
      expect(deleted.memberships, isEmpty);
      expect(deleted.passwordHash, 'deleted');
      expect(
        (await store.listJson('sessions'))
            .where((value) => value['userId'] == customer.userId),
        isEmpty,
      );
      expect(
        (await store.listJson('audit'))
            .any((value) => value['action'] == 'account.deletion.completed'),
        isTrue,
      );
    },
  );

  test(
    'organization deletion is staged, tenant-safe, and shared-object safe',
    () async {
      final customer = await _createCustomer(
        email: 'tenant-a@example.com',
        password: 'correct horse battery staple',
      );
      final other = await _createCustomer(
        email: 'tenant-b@example.com',
        password: 'correct horse battery staple',
      );
      final sharedBytes = <int>[1, 2, 3, 4];
      final sharedDigest = sha256Digest(sharedBytes);
      final exclusiveBytes = <int>[5, 6, 7, 8];
      final exclusiveDigest = sha256Digest(exclusiveBytes);

      await store.putArtifact(sharedDigest, sharedBytes);
      await store.putArtifact(exclusiveDigest, exclusiveBytes);
      await store.createJson(
        'artifacts',
        'artifact_shared_a',
        ArtifactRecord(
          id: 'artifact_shared_a',
          organizationId: customer.organizationId,
          patchId: 'patch_shared_a',
          sha256: sharedDigest,
          sizeBytes: sharedBytes.length,
          contentType: 'application/octet-stream',
          state: artifactReadyState,
          createdAt: now,
        ).toJson(),
      );
      await store.createJson(
        'artifacts',
        'artifact_shared_b',
        ArtifactRecord(
          id: 'artifact_shared_b',
          organizationId: other.organizationId,
          patchId: 'patch_shared_b',
          sha256: sharedDigest,
          sizeBytes: sharedBytes.length,
          contentType: 'application/octet-stream',
          state: artifactReadyState,
          createdAt: now,
        ).toJson(),
      );
      await store.createJson(
        'artifacts',
        'artifact_exclusive_a',
        ArtifactRecord(
          id: 'artifact_exclusive_a',
          organizationId: customer.organizationId,
          patchId: 'patch_exclusive_a',
          sha256: exclusiveDigest,
          sizeBytes: exclusiveBytes.length,
          contentType: 'application/octet-stream',
          state: artifactReadyState,
          createdAt: now,
        ).toJson(),
      );

      final request = await service.deletion!.requestOrganizationDeletion(
        userId: customer.userId,
        organizationId: customer.organizationId,
        requestId: 'request-org-delete',
      );
      expect(request['status'], 'grace_period');
      expect(
        (await store.readJson(
          'organizations',
          customer.organizationId,
        ))!['deletionState'],
        'deletion_requested',
      );
      expect(
        (await store.listJson('billing_subscriptions'))
            .any((value) => value['organizationId'] == customer.organizationId),
        isTrue,
      );

      final cancelledRequest = await service.deletion!
          .cancelOrganizationDeletion(
            userId: customer.userId,
            organizationId: customer.organizationId,
            actorId: customer.userId,
            requestId: 'request-org-delete-cancel',
          );
      expect(cancelledRequest['status'], 'cancelled');
      expect(
        (await store.readJson(
          'organizations',
          customer.organizationId,
        ))!['deletionState'],
        'active',
      );

      final secondRequest = await service.deletion!.requestOrganizationDeletion(
        userId: customer.userId,
        organizationId: customer.organizationId,
        requestId: 'request-org-delete-again',
      );
      now = now.add(const Duration(hours: 2));
      Map<String, Object?> state = secondRequest;
      for (
        var attempt = 0;
        attempt < 20 && state['status'] != 'completed';
        attempt++
      ) {
        state = await service.deletion!.processDeletion(
          requestId: secondRequest['id']! as String,
          maxItems: 1,
          now: now,
        );
      }
      expect(state['status'], 'completed');
      expect(
        (await store.readJson(
          'organizations',
          customer.organizationId,
        ))!['deletionState'],
        'deleted',
      );
      expect(await store.readJson('artifacts', 'artifact_shared_a'), isNull);
      expect(await store.readJson('artifacts', 'artifact_exclusive_a'), isNull);
      expect(await store.readArtifact(sharedDigest), sharedBytes);
      expect(await store.readArtifact(exclusiveDigest), isNull);
      expect(
        (await store.readJson('artifacts', 'artifact_shared_b')),
        isNotNull,
      );
      expect(await store.listJson('deletion_evidence'), isNotEmpty);
      expect(
        (await store.listJson(
          'audit',
        )).any((value) => value['action'] == 'organization.deletion.completed'),
        isTrue,
      );
      await expectLater(
        service.ensureOrganizationAccessAllowed(customer.organizationId),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'ORGANIZATION_DELETED',
          ),
        ),
      );

      // A completed organization deletion removes memberships, but must not
      // prevent the same human from using the no-login personal deletion
      // request path later.
      final deletionTokenCount = deliveryForCurrentTest.deletionTokens.length;
      await auth.requestAccountDeletion(email: 'tenant-a@example.com');
      expect(
        deliveryForCurrentTest.deletionTokens.length,
        deletionTokenCount + 1,
      );
    },
  );

  test(
    'unconfigured grace policy blocks processing without inventing a duration',
    () async {
      final noPolicy = AccountDeletionService(
        store: store,
        humanAuth: auth,
        billing: service.billing,
        deploymentModel: DeploymentModel.cloud,
      );
      final customer = await _createCustomer(
        email: 'policy@example.com',
        password: 'correct horse battery staple',
      );
      final user = HumanUserRecord.fromJson(
        (await store.readJson('users', customer.userId))!,
      );
      final membership = user.memberships.single;
      await store.replaceJson(
        'users',
        customer.userId,
        user
            .copyWith(
              memberships: <HumanMembership>[
                HumanMembership(
                  organizationId: membership.organizationId,
                  role: 'member',
                  capabilities: membership.capabilities,
                  profileName: membership.profileName,
                  audience: membership.audience,
                  platformCapabilities: membership.platformCapabilities,
                ),
              ],
            )
            .toJson(),
      );
      final request = await noPolicy.requestAccountDeletion(
        userId: customer.userId,
        actorId: customer.userId,
        requestId: 'request-policy-delete',
      );
      expect(request['status'], 'policy_decision_required');
      final blocked = await noPolicy.processDeletion(
        requestId: request['id']! as String,
        now: now.add(const Duration(days: 365)),
      );
      expect(
        blocked['blocker'],
        'POLICY_DECISION_REQUIRED: deletion_grace_period',
      );
    },
  );
}

Future<_Customer> _createCustomer({
  required String email,
  required String password,
}) async {
  final before = deliveryForCurrentTest.verificationTokens.length;
  await serviceForCurrentTest.registerCloudCustomer(
    email: email,
    password: password,
    organizationName: 'Deletion test workspace',
  );
  final verificationToken = deliveryForCurrentTest.verificationTokens[before];
  final login = await serviceForCurrentTest.verifyCloudCustomer(
    token: verificationToken,
  );
  return _Customer(
    userId: login.identity.user.id,
    organizationId: login.identity.profiles.single.organizationId,
  );
}

// These late bindings keep the fixture helper readable while allowing each
// test's setUp-created service and delivery to remain isolated.
late _DeletionDelivery deliveryForCurrentTest;
late ControlPlaneService serviceForCurrentTest;
