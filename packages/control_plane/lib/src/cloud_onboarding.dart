import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'persistence.dart';
import 'service.dart';

/// Configuration for the explicit managed Cloud signup flow.
///
/// The flow is disabled unless a deployment opts in. Production deployments
/// must also configure an HTTPS verification-link delivery endpoint. Tests may
/// inject [CloudSignupVerificationDelivery] directly without configuring an
/// external mail provider.
final class CloudOnboardingConfig {
  const CloudOnboardingConfig({
    this.enabled = false,
    this.verificationUrl,
    this.deliveryEndpoint,
    this.deliveryToken,
    this.verificationTtl = const Duration(minutes: 30),
  });

  final bool enabled;
  final Uri? verificationUrl;
  final Uri? deliveryEndpoint;
  final String? deliveryToken;
  final Duration verificationTtl;

  factory CloudOnboardingConfig.fromEnvironment(Map<String, String> values) {
    final enabled = _bool(values, 'HYFENS_CLOUD_SIGNUP_ENABLED', false);
    final verificationUrl = _optionalWebUri(
      values['HYFENS_CLOUD_SIGNUP_VERIFICATION_URL'],
      'HYFENS_CLOUD_SIGNUP_VERIFICATION_URL',
    );
    final deliveryEndpoint = _optionalWebUri(
      values['HYFENS_CLOUD_SIGNUP_EMAIL_WEBHOOK_URL'],
      'HYFENS_CLOUD_SIGNUP_EMAIL_WEBHOOK_URL',
    );
    final rawToken = values['HYFENS_CLOUD_SIGNUP_EMAIL_WEBHOOK_TOKEN'];
    final deliveryToken = rawToken == null || rawToken.isEmpty
        ? null
        : rawToken;
    final rawTtl = values['HYFENS_CLOUD_SIGNUP_VERIFICATION_TTL_MINUTES'];
    final ttlMinutes = rawTtl == null || rawTtl.isEmpty
        ? 30
        : int.tryParse(rawTtl);
    if (ttlMinutes == null || ttlMinutes < 5 || ttlMinutes > 1440) {
      throw ArgumentError(
        'HYFENS_CLOUD_SIGNUP_VERIFICATION_TTL_MINUTES must be between 5 and 1440',
      );
    }
    if ((deliveryEndpoint == null) != (deliveryToken == null)) {
      throw ArgumentError(
        'Cloud signup email webhook URL and token must be configured together',
      );
    }
    if (deliveryToken != null && !_validSecret(deliveryToken)) {
      throw ArgumentError(
        'HYFENS_CLOUD_SIGNUP_EMAIL_WEBHOOK_TOKEN must be 32-256 characters without whitespace',
      );
    }
    if (enabled && verificationUrl == null) {
      throw ArgumentError(
        'HYFENS_CLOUD_SIGNUP_VERIFICATION_URL is required when Cloud signup is enabled',
      );
    }
    if (enabled && (deliveryEndpoint == null || deliveryToken == null)) {
      throw ArgumentError(
        'Cloud signup email webhook URL and token are required when Cloud signup is enabled',
      );
    }
    return CloudOnboardingConfig(
      enabled: enabled,
      verificationUrl: verificationUrl,
      deliveryEndpoint: deliveryEndpoint,
      deliveryToken: deliveryToken,
      verificationTtl: Duration(minutes: ttlMinutes),
    );
  }

  static bool _bool(Map<String, String> values, String key, bool fallback) {
    final value = values[key];
    if (value == null || value.isEmpty) return fallback;
    return switch (value.toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => throw ArgumentError('$key must be true or false'),
    };
  }

  static Uri? _optionalWebUri(String? value, String name) {
    if (value == null || value.isEmpty) return null;
    if (value.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ArgumentError('$name contains unsupported characters');
    }
    final uri = Uri.tryParse(value);
    final loopback =
        uri != null &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '::1' ||
            uri.host == '[::1]');
    if (uri == null ||
        !uri.isAbsolute ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback))) {
      throw ArgumentError('$name must be an HTTPS URI or loopback HTTP URI');
    }
    return uri;
  }

  static bool _validSecret(String value) =>
      value.length >= 32 &&
      value.length <= 256 &&
      !value.contains(RegExp(r'[\u0000\r\n\s]'));
}

final class CloudSignupVerificationRequest {
  const CloudSignupVerificationRequest({
    required this.email,
    required this.verificationUrl,
    required this.expiresAt,
  });

  final String email;
  final Uri verificationUrl;
  final DateTime expiresAt;
}

abstract interface class CloudSignupVerificationDelivery {
  Future<void> deliver(CloudSignupVerificationRequest request);
}

/// Explicit fail-closed provider used when managed signup is not configured.
final class UnavailableCloudSignupVerificationDelivery
    implements CloudSignupVerificationDelivery {
  const UnavailableCloudSignupVerificationDelivery();

  @override
  Future<void> deliver(CloudSignupVerificationRequest request) async {
    throw const ControlPlaneException(
      'CLOUD_EMAIL_UNAVAILABLE',
      'Cloud account verification email is not configured',
      statusCode: 503,
    );
  }
}

/// Small deployment-owned webhook adapter. The webhook receives a verification
/// link; it does not receive a password, session, or control-plane token.
final class HttpCloudSignupVerificationDelivery
    implements CloudSignupVerificationDelivery {
  HttpCloudSignupVerificationDelivery({
    required this.endpoint,
    required this.serviceToken,
    this.timeout = const Duration(seconds: 10),
  });

  final Uri endpoint;
  final String serviceToken;
  final Duration timeout;

  @override
  Future<void> deliver(CloudSignupVerificationRequest request) async {
    final client = HttpClient();
    try {
      final httpRequest = await client.postUrl(endpoint).timeout(timeout);
      httpRequest.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $serviceToken');
      httpRequest.add(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'event': 'cloud_signup_verification',
            'email': request.email,
            'verification_url': request.verificationUrl.toString(),
            'expires_at': request.expiresAt.toUtc().toIso8601String(),
          }),
        ),
      );
      final response = await httpRequest.close().timeout(timeout);
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const ControlPlaneException(
          'CLOUD_EMAIL_UNAVAILABLE',
          'Cloud account verification email could not be delivered',
          statusCode: 503,
        );
      }
    } on ControlPlaneException {
      rethrow;
    } on Object {
      throw const ControlPlaneException(
        'CLOUD_EMAIL_UNAVAILABLE',
        'Cloud account verification email could not be delivered',
        statusCode: 503,
      );
    } finally {
      client.close(force: true);
    }
  }
}

final class CloudSignupResponse {
  const CloudSignupResponse({required this.email, this.expiresAt});

  final String email;
  final DateTime? expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': 'verification_required',
    'email': email,
    if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
  };
}

final class CloudVerificationResult {
  const CloudVerificationResult({
    required this.login,
    required this.organizationId,
    required this.onboardingStatus,
  });

  final HumanLoginResult login;
  final String organizationId;
  final String onboardingStatus;
}

/// Managed Cloud account and first-organization onboarding.
///
/// The service intentionally creates only the identity, organization owner,
/// and minimal onboarding marker. Application and environment records remain
/// normal control-plane resources and are created through their existing
/// authorization and idempotency contracts.
final class CloudOnboardingService {
  CloudOnboardingService({
    required this.controlPlane,
    required this.config,
    required this.delivery,
    Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? Random.secure(),
       _clock = clock ?? (() => DateTime.now().toUtc()) {
    _validateConfig(config);
  }

  final ControlPlaneService controlPlane;
  final CloudOnboardingConfig config;
  final CloudSignupVerificationDelivery delivery;
  final Random _random;
  final DateTime Function() _clock;
  Future<void> _writeTail = Future<void>.value();

  Future<CloudSignupResponse> beginSignup({
    required String email,
    required String password,
    required String organizationName,
  }) => _serialized(() async {
    final store = _store();
    final auth = _auth();
    final normalizedEmail = _email(email);
    final normalizedOrganizationName = _organizationName(organizationName);

    // Do not disclose whether an unrelated account exists. A verified account
    // or an existing verified signup receives the same generic response and no
    // new delivery attempt.
    if (await auth.userByEmail(normalizedEmail) != null) {
      return CloudSignupResponse(email: normalizedEmail);
    }

    final signupId = _signupId(normalizedEmail);
    final current = await store.readJson('cloud_signups', signupId);
    if (current != null && current['status'] == 'verified') {
      return CloudSignupResponse(email: normalizedEmail);
    }
    if (current != null && current['status'] != 'pending') {
      throw const ControlPlaneException(
        'CLOUD_SIGNUP_UNAVAILABLE',
        'Cloud account onboarding is temporarily unavailable',
        statusCode: 503,
      );
    }

    final now = _now();
    final expiresAt = now.add(config.verificationTtl);
    final token = _token();
    final pending = <String, Object?>{
      'id': signupId,
      'email': normalizedEmail,
      'organizationName': normalizedOrganizationName,
      'passwordHash': await auth.hashPasswordForRegistration(password),
      'tokenHash': sha256Hex(utf8.encode(token)),
      'status': 'pending',
      'createdAt': now.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
    };
    var persisted = true;
    if (current == null) {
      try {
        await store.createJson('cloud_signups', signupId, pending);
      } on StorageConflict {
        // A concurrent request won the deterministic signup key. Do not
        // deliver a link for a token that this process does not own.
        persisted = false;
      }
    } else if (store case final ConditionalJsonStore conditional) {
      persisted = await conditional.replaceJsonIfCurrent(
        collection: 'cloud_signups',
        id: signupId,
        expected: current,
        replacement: pending,
      );
    } else {
      await store.replaceJson('cloud_signups', signupId, pending);
    }
    if (!persisted) {
      final winner = await store.readJson('cloud_signups', signupId);
      return CloudSignupResponse(
        email: normalizedEmail,
        expiresAt: _dateOrNull(winner?['expiresAt']),
      );
    }

    final verificationUrl = config.verificationUrl!.replace(
      queryParameters: <String, String>{
        ...config.verificationUrl!.queryParameters,
        'email': normalizedEmail,
        'token': token,
      },
    );
    await delivery.deliver(
      CloudSignupVerificationRequest(
        email: normalizedEmail,
        verificationUrl: verificationUrl,
        expiresAt: expiresAt,
      ),
    );
    final requestAuditId =
        '$signupId:requested:${sha256Hex(utf8.encode(pending['tokenHash']! as String)).substring(0, 16)}';
    await store.appendAudit(requestAuditId, <String, Object?>{
      'id': requestAuditId,
      'organizationId': null,
      'actorId': 'cloud-signup',
      'action': 'cloud.signup.requested',
      'resourceType': 'cloud_signup',
      'resourceId': signupId,
      'result': 'success',
      'metadata': <String, Object?>{'email': normalizedEmail},
      'createdAt': now.toIso8601String(),
    });
    return CloudSignupResponse(email: normalizedEmail, expiresAt: expiresAt);
  });

  Future<CloudVerificationResult> verifySignup({
    required String email,
    required String token,
  }) => _serialized(() async {
    final store = _store();
    final auth = _auth();
    final normalizedEmail = _verificationEmail(email);
    if (!_tokenPattern.hasMatch(token)) _invalidVerification();
    final signupId = _signupId(normalizedEmail);
    final signup = await store.readJson('cloud_signups', signupId);
    if (signup == null || signup['email'] != normalizedEmail) {
      _invalidVerification();
    }
    final tokenHash = signup['tokenHash'];
    if (tokenHash is! String ||
        !_constantTimeEqual(tokenHash, _hashToken(token))) {
      _invalidVerification();
    }

    final existingStatus = signup['status'];
    final organizationId = signup['organizationId'];
    final userId = signup['userId'];
    if (existingStatus == 'verified') {
      if (organizationId is! String || userId is! String) {
        _invalidVerification();
      }
      final onboarding = await store.readJson('cloud_onboarding', signupId);
      final login = await auth.issueSessionForUserId(
        userId: userId,
        audience: customerAuthorizationAudience,
        profileName: 'owner',
      );
      return CloudVerificationResult(
        login: login,
        organizationId: organizationId,
        onboardingStatus:
            onboarding?['status'] as String? ?? 'needs_application',
      );
    }
    if (existingStatus != 'pending') _invalidVerification();
    final expiresAt = _dateOrNull(signup['expiresAt']);
    if (expiresAt == null || !expiresAt.isAfter(_now())) {
      _invalidVerification();
    }
    final passwordHash = signup['passwordHash'];
    final organizationName = signup['organizationName'];
    if (passwordHash is! String || organizationName is! String) {
      _invalidVerification();
    }

    final now = _now();
    final derivedOrganizationId = _organizationId(signupId);
    final derivedUserId = HumanAuthService.userIdForEmail(normalizedEmail);
    final organization = OrganizationRecord(
      id: derivedOrganizationId,
      name: organizationName,
      createdAt: now,
    );
    final membership = HumanMembership(
      organizationId: organization.id,
      role: 'owner',
      capabilities: controlScopes,
      profileName: 'owner',
      audience: customerAuthorizationAudience,
    );
    final user = HumanUserRecord(
      id: derivedUserId,
      email: normalizedEmail,
      passwordHash: passwordHash,
      active: true,
      memberships: <HumanMembership>[membership],
      createdAt: now,
    );
    final onboarding = <String, Object?>{
      'id': signupId,
      'organizationId': organization.id,
      'userId': user.id,
      'status': 'needs_application',
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };
    final verifiedSignup = <String, Object?>{
      'id': signupId,
      'email': normalizedEmail,
      'tokenHash': tokenHash,
      'status': 'verified',
      'createdAt': signup['createdAt'],
      'expiresAt': signup['expiresAt'],
      'verifiedAt': now.toIso8601String(),
      'organizationId': organization.id,
      'userId': user.id,
    };
    final commit = await store.commitManagedCloudOnboarding(
      signupId: signupId,
      expectedSignup: signup,
      verifiedSignup: verifiedSignup,
      organization: organization.toJson(),
      user: user.toJson(),
      onboarding: onboarding,
    );
    if (commit.created) {
      await store.appendAudit('$signupId:verified', <String, Object?>{
        'id': '$signupId:verified',
        'organizationId': organization.id,
        'actorId': user.id,
        'action': 'cloud.signup.verified',
        'resourceType': 'organization',
        'resourceId': organization.id,
        'result': 'success',
        'metadata': <String, Object?>{
          'signupId': signupId,
          'onboardingStatus': 'needs_application',
        },
        'createdAt': now.toIso8601String(),
      });
    }
    final login = await auth.issueSessionForUserId(
      userId: user.id,
      audience: customerAuthorizationAudience,
      profileName: 'owner',
    );
    return CloudVerificationResult(
      login: login,
      organizationId: organization.id,
      onboardingStatus: 'needs_application',
    );
  });

  ManagedCloudOnboardingStore _store() {
    _requireAvailable();
    final store = controlPlane.store;
    if (store is! ManagedCloudOnboardingStore) {
      throw const ControlPlaneException(
        'CLOUD_SIGNUP_UNAVAILABLE',
        'Cloud account onboarding is not supported by this storage backend',
        statusCode: 503,
      );
    }
    return store as ManagedCloudOnboardingStore;
  }

  HumanAuthService _auth() {
    _requireAvailable();
    final auth = controlPlane.humanAuth;
    if (auth == null) {
      throw const ControlPlaneException(
        'CLOUD_SIGNUP_UNAVAILABLE',
        'Cloud account onboarding is not configured for this deployment',
        statusCode: 503,
      );
    }
    return auth;
  }

  void _requireAvailable() {
    if (!config.enabled || config.verificationUrl == null) {
      throw const ControlPlaneException(
        'CLOUD_SIGNUP_UNAVAILABLE',
        'Managed Cloud signup is not enabled',
        statusCode: 503,
      );
    }
  }

  String _email(String value) {
    try {
      return HumanAuthService.normalizeHumanEmail(value);
    } on ControlPlaneException {
      throw const ControlPlaneException(
        'INVALID_CLOUD_SIGNUP',
        'Enter a valid email, password, and organization name',
        statusCode: 422,
      );
    }
  }

  String _verificationEmail(String value) {
    try {
      return HumanAuthService.normalizeHumanEmail(value);
    } on ControlPlaneException {
      _invalidVerification();
    }
  }

  String _organizationName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > 120 ||
        normalized.contains(RegExp(r'[\u0000\r\n]'))) {
      throw const ControlPlaneException(
        'INVALID_CLOUD_SIGNUP',
        'Enter a valid email, password, and organization name',
        statusCode: 422,
      );
    }
    return normalized;
  }

  String _token() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _signupId(String email) =>
      'sgn_${sha256Hex(utf8.encode('hyfens.cloud.signup.v1|$email')).substring(0, 48)}';

  String _organizationId(String signupId) =>
      'org_${sha256Hex(utf8.encode('hyfens.cloud.organization.v1|$signupId')).substring(0, 32)}';

  String _hashToken(String token) => sha256Hex(utf8.encode(token));

  DateTime _now() => _clock().toUtc();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _writeTail.then((_) => action());
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  static DateTime? _dateOrNull(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static Never _invalidVerification() {
    throw const ControlPlaneException(
      'CLOUD_VERIFICATION_INVALID',
      'This verification link is invalid or has expired',
      statusCode: 400,
    );
  }

  static void _validateConfig(CloudOnboardingConfig config) {
    if (config.verificationTtl < const Duration(minutes: 5) ||
        config.verificationTtl > const Duration(hours: 24)) {
      throw ArgumentError(
        'Cloud signup verification TTL is outside its bounds',
      );
    }
    for (final entry in <String, Uri?>{
      'verification URL': config.verificationUrl,
      'delivery endpoint': config.deliveryEndpoint,
    }.entries) {
      final uri = entry.value;
      if (uri == null) continue;
      final loopback =
          uri.host == 'localhost' ||
          uri.host == '127.0.0.1' ||
          uri.host == '::1' ||
          uri.host == '[::1]';
      if (!uri.isAbsolute ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.fragment.isNotEmpty ||
          (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback))) {
        throw ArgumentError(
          '${entry.key} must be an HTTPS URI or loopback HTTP URI',
        );
      }
    }
    final token = config.deliveryToken;
    if (token != null && !CloudOnboardingConfig._validSecret(token)) {
      throw ArgumentError('Cloud signup delivery token is invalid');
    }
  }

  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  static bool _constantTimeEqual(String left, String right) {
    var difference = left.length ^ right.length;
    final length = min(left.length, right.length);
    for (var index = 0; index < length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}
