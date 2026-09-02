import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late HumanAuthService auth;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  var now = DateTime.utc(2026, 8, 30, 10);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-human-auth-');
    store = FileControlPlaneStore(directory);
    auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'test-control-plane',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 7),
      ),
      random: Random(11),
      clock: () => now,
    );
    service = ControlPlaneService(
      store: store,
      humanAuth: auth,
      clock: () => now,
      random: Random(13),
    );
    bootstrap = await service.bootstrap(
      organizationName: 'Auth test',
      runtimeApplicationId: 'com.example.auth',
      platformId: 'android',
      environmentName: 'development',
    );
    await service.bootstrapOwner(
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      email: 'Owner@Example.com',
      password: 'correct horse battery staple',
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'login stores only password and session hashes and authorizes control work',
    () async {
      final result = await auth.login(
        email: 'owner@example.com',
        password: 'correct horse battery staple',
      );

      expect(result.identity.user.email, 'owner@example.com');
      expect(result.identity.profiles.single.name, 'demo');
      expect(result.accessToken.split('.'), hasLength(3));
      expect(result.sessionToken, startsWith('hfs.'));

      final userJson = (await store.listJson('users')).single;
      final sessionJson = (await store.listJson('sessions')).single;
      expect(userJson['passwordHash'], startsWith('argon2id\$v=19\$'));
      expect(userJson['passwordHash'], isNot('correct horse battery staple'));
      expect(sessionJson['secretHash'], isNot(result.sessionToken));
      expect(canonicalJson(sessionJson), isNot(contains(result.sessionToken)));

      final key = base64.encode(List<int>.filled(32, 4));
      final release = await service.registerRelease(
        token: result.accessToken,
        organizationId: bootstrap.organization.id,
        idempotencyKey: 'human-auth-release',
        spec: ReleaseSpec(
          applicationId: bootstrap.application.id,
          platformId: 'plt_android',
          runtimeApplicationId: 'com.example.auth',
          runtimeReleaseId: 'auth-release-1',
          buildTarget: 'android-arm64-release',
          runtimeCompatibilityVersion: 1,
          patchFormatVersion: 1,
          buildFingerprint: _digest('build'),
          capabilityAuthorityDigest: _digest('capability'),
          functionSignatureDigest: _digest('functions'),
          displayVersion: '1.0.0',
          signingPublicKeys: <String, String>{'auth-key': key},
        ),
      );
      expect(release.runtimeReleaseId, 'auth-release-1');
    },
  );

  test(
    'rejects wrong audience, wrong issuer, malformed JWT, and delivery use',
    () async {
      final result = await auth.login(
        email: 'owner@example.com',
        password: 'correct horse battery staple',
      );
      final wrongAudience = HumanAuthService(
        store: store,
        config: HumanAuthConfig(
          issuer: 'test-control-plane',
          audience: 'hyfens-delivery',
          signingKeySeed: List<int>.filled(32, 7),
        ),
        clock: () => now,
      );
      final wrongIssuer = HumanAuthService(
        store: store,
        config: HumanAuthConfig(
          issuer: 'other-control-plane',
          audience: 'hyfens-control',
          signingKeySeed: List<int>.filled(32, 7),
        ),
        clock: () => now,
      );

      await expectCode(
        () => wrongAudience.authorizeAccessToken(
          token: result.accessToken,
          requiredScope: 'release:write',
          kind: CredentialKind.control,
          organizationId: bootstrap.organization.id,
        ),
        'UNAUTHORIZED',
      );
      await expectCode(
        () => wrongIssuer.authorizeAccessToken(
          token: result.accessToken,
          requiredScope: 'release:write',
          kind: CredentialKind.control,
          organizationId: bootstrap.organization.id,
        ),
        'UNAUTHORIZED',
      );
      await expectCode(
        () => auth.authorizeAccessToken(
          token: 'not.a.jwt',
          requiredScope: 'release:write',
          kind: CredentialKind.control,
          organizationId: bootstrap.organization.id,
        ),
        'UNAUTHORIZED',
      );
      await expectCode(
        () => service.updateCheck(
          token: result.accessToken,
          request: UpdateCheckRequest(
            applicationId: bootstrap.application.id,
            environmentId: bootstrap.environment.id,
            runtimeApplicationId: 'com.example.auth',
            runtimeReleaseId: 'auth-release-1',
            runtimeCompatibilityVersion: 1,
            patchFormatVersion: 1,
            highWaterSequence: 0,
          ),
        ),
        'FORBIDDEN',
      );
    },
  );

  test(
    'rejects cross-tenant authorization and enforces revocation on logout',
    () async {
      final other = await service.bootstrap(
        organizationName: 'Other',
        runtimeApplicationId: 'com.example.other',
        platformId: 'android',
        environmentName: 'development',
      );
      final result = await auth.login(
        email: 'owner@example.com',
        password: 'correct horse battery staple',
      );
      await expectCode(
        () => auth.authorizeAccessToken(
          token: result.accessToken,
          requiredScope: 'release:write',
          kind: CredentialKind.control,
          organizationId: other.organization.id,
        ),
        'NOT_FOUND',
      );

      await auth.logout(sessionToken: result.sessionToken);
      await auth.logout(sessionToken: result.sessionToken);
      await expectCode(
        () => auth.me(accessToken: result.accessToken),
        'UNAUTHORIZED',
      );
      await expectCode(
        () => auth.refresh(sessionToken: result.sessionToken),
        'UNAUTHORIZED',
      );
    },
  );

  test('access token expires independently of the session', () async {
    final shortAuth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'short-control-plane',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 9),
        accessTtl: const Duration(seconds: 1),
        sessionTtl: const Duration(seconds: 10),
      ),
      clock: () => now,
    );
    final result = await shortAuth.login(
      email: 'owner@example.com',
      password: 'correct horse battery staple',
    );
    now = now.add(const Duration(seconds: 2));
    await expectCode(
      () => shortAuth.me(accessToken: result.accessToken),
      'UNAUTHORIZED',
    );
    final refreshed = await shortAuth.refresh(
      sessionToken: result.sessionToken,
    );
    expect(refreshed.accessToken, isNot(result.accessToken));
  });
}

Future<void> expectCode(
  Future<Object?> Function() action,
  String expected,
) async {
  try {
    await action();
    fail('Expected ControlPlaneException $expected');
  } on ControlPlaneException catch (error) {
    expect(error.code, expected);
  }
}

String _digest(String value) =>
    'sha256:${sha256.convert(utf8.encode(value)).toString()}';
