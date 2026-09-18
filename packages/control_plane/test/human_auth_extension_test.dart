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
  late BootstrapResult bootstrap;
  late HumanLoginResult login;
  var now = DateTime.utc(2026, 8, 31, 10);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-human-auth-extension-',
    );
    store = FileControlPlaneStore(directory);
    auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'extension-control-plane',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 19),
        authorizationCodeTtl: const Duration(minutes: 1),
        deviceCodeTtl: const Duration(minutes: 5),
        devicePollInterval: const Duration(seconds: 1),
        deviceMaxAttempts: 3,
        deviceAttemptsPerMinute: 3,
        allowedAuthorizationRedirectUris: <String>[
          'https://dashboard.example/callback',
        ],
      ),
      random: Random(23),
      clock: () => now,
    );
    final service = ControlPlaneService(
      store: store,
      humanAuth: auth,
      random: Random(29),
      clock: () => now,
    );
    bootstrap = await service.bootstrap(
      organizationName: 'Auth extension',
      runtimeApplicationId: 'com.example.auth.extension',
      platformId: 'android',
      environmentName: 'development',
    );
    await service.bootstrapOwner(
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      email: 'owner@example.com',
      password: 'correct horse battery staple',
    );
    login = await auth.login(
      email: 'owner@example.com',
      password: 'correct horse battery staple',
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'PKCE binds state and exact redirect, then rejects code reuse',
    () async {
      final verifier = 'a' * 43;
      final request = await auth.beginAuthorization(
        clientId: 'hyfens-cli',
        redirectUri: 'http://127.0.0.1:43127/callback',
        codeChallenge: _challenge(verifier),
        state: 'state-extension-123',
        responseType: 'code',
        codeChallengeMethod: 'S256',
      );
      final issued = await auth.authorize(
        requestId: request.id,
        accessToken: login.accessToken,
      );

      expect(issued.request.state, request.state);
      expect(issued.request.redirectUri, request.redirectUri);
      expect(issued.code, startsWith('hfc_'));
      expect(
        (await store.listJson('auth_authorization_codes')).single.values,
        isNot(contains(issued.code)),
      );

      final exchanged = await auth.exchangeAuthorizationCode(
        clientId: 'hyfens-cli',
        code: issued.code,
        redirectUri: request.redirectUri,
        codeVerifier: verifier,
      );
      expect(exchanged.identity.user.id, login.identity.user.id);
      expect(exchanged.sessionToken, startsWith('hfs.'));
      await expectCode(
        () => auth.exchangeAuthorizationCode(
          clientId: 'hyfens-cli',
          code: issued.code,
          redirectUri: request.redirectUri,
          codeVerifier: verifier,
        ),
        'AUTHORIZATION_CODE_USED',
      );
    },
  );

  test('PKCE rejects redirect mismatch and expired one-time code', () async {
    final verifier = 'b' * 43;
    final request = await auth.beginAuthorization(
      clientId: 'hyfens-cli',
      redirectUri: 'https://dashboard.example/callback',
      codeChallenge: _challenge(verifier),
      state: 'state-extension-456',
    );
    final issued = await auth.authorize(
      requestId: request.id,
      accessToken: login.accessToken,
    );
    await expectCode(
      () => auth.exchangeAuthorizationCode(
        clientId: 'hyfens-cli',
        code: issued.code,
        redirectUri: 'https://dashboard.example/other',
        codeVerifier: verifier,
      ),
      'INVALID_REDIRECT_URI',
    );
    now = now.add(const Duration(minutes: 2));
    await expectCode(
      () => auth.exchangeAuthorizationCode(
        clientId: 'hyfens-cli',
        code: issued.code,
        redirectUri: request.redirectUri,
        codeVerifier: verifier,
      ),
      'INVALID_GRANT',
    );
  });

  test(
    'device authorization is pending, approved once, and consumed once',
    () async {
      final device = await auth.createDeviceAuthorization(
        clientId: 'hyfens-cli',
      );
      expect(device.deviceCode, startsWith('hfd_'));
      expect(device.userCode, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$')));
      expect(device.verificationUri, '/auth/device/verify');

      final pending = await auth.pollDeviceAuthorization(
        clientId: 'hyfens-cli',
        deviceCode: device.deviceCode,
      );
      expect(pending.status, 'authorization_pending');
      await auth.approveDeviceAuthorization(
        userCode: device.userCode,
        accessToken: login.accessToken,
      );
      final approved = await auth.pollDeviceAuthorization(
        clientId: 'hyfens-cli',
        deviceCode: device.deviceCode,
      );
      expect(approved.isApproved, isTrue);
      expect(approved.loginResult!.identity.user.id, login.identity.user.id);
      final consumed = await auth.pollDeviceAuthorization(
        clientId: 'hyfens-cli',
        deviceCode: device.deviceCode,
      );
      expect(consumed.status, 'invalid_grant');
    },
  );

  test('first-owner bootstrap is consumed per scope', () async {
    await expectCode(
      () => auth.bootstrapOwner(
        organizationId: bootstrap.organization.id,
        applicationId: bootstrap.application.id,
        environmentId: bootstrap.environment.id,
        email: 'second-owner@example.com',
        password: 'another correct horse battery staple',
      ),
      'BOOTSTRAP_ALREADY_CONSUMED',
    );
    final sameOwner = await auth.bootstrapOwner(
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      email: 'owner@example.com',
      password: 'correct horse battery staple',
    );
    expect(sameOwner.email, 'owner@example.com');
    expect(
      (await store.listJson('auth_bootstrap_consumptions')).single['email'],
      'owner@example.com',
    );
  });

  test('device expiry and attempt limits cannot create a session', () async {
    final expired = await auth.createDeviceAuthorization(
      clientId: 'hyfens-cli',
    );
    now = now.add(const Duration(minutes: 6));
    expect(
      (await auth.pollDeviceAuthorization(
        clientId: 'hyfens-cli',
        deviceCode: expired.deviceCode,
      )).status,
      'expired_token',
    );
    await expectCode(
      () => auth.approveDeviceAuthorization(
        userCode: expired.userCode,
        accessToken: login.accessToken,
      ),
      'DEVICE_CODE_EXPIRED',
    );

    now = DateTime.utc(2026, 8, 31, 10);
    final limitedAuth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'limited-control-plane',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 20),
        deviceMaxAttempts: 2,
        deviceAttemptsPerMinute: 2,
      ),
      random: Random(31),
      clock: () => now,
    );
    final limited = await limitedAuth.createDeviceAuthorization(
      clientId: 'hyfens-cli',
    );
    await limitedAuth.pollDeviceAuthorization(
      clientId: 'hyfens-cli',
      deviceCode: limited.deviceCode,
    );
    await limitedAuth.pollDeviceAuthorization(
      clientId: 'hyfens-cli',
      deviceCode: limited.deviceCode,
    );
    await expectCode(
      () => limitedAuth.pollDeviceAuthorization(
        clientId: 'hyfens-cli',
        deviceCode: limited.deviceCode,
      ),
      'DEVICE_ATTEMPTS_EXCEEDED',
    );
  });
}

String _challenge(String verifier) => base64Url
    .encode(sha256.convert(utf8.encode(verifier)).bytes)
    .replaceAll('=', '');

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
