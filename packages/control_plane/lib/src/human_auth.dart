import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'auth.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'persistence.dart';

/// The fixed read-only capability profile granted to public client accounts.
/// It is intentionally the minimum profile required by the operator overview
/// projection and contains no write, owner, or administration capability.
const Set<String> publicClientReadScopes = <String>{
  'application:read',
  'release:read',
  'patch:read',
  'artifact:read',
  'rollout:read',
  'audit:read',
};

/// Configuration for the control-plane human authentication boundary.
///
/// The signing seed is an auth-only Ed25519 seed. It must never be reused for
/// Patch Format signing. Verification keys allow a deployment to retain old
/// public keys while an active key is rotated.
final class HumanAuthConfig {
  static const _defaultIssuer = 'hyfens-control-plane';
  static const _defaultAudience = 'hyfens-control';
  static const _defaultSigningKeyId = 'auth-ed25519-1';
  static const _defaultAccessTtl = '15m';
  static const _defaultSessionTtl = '30d';

  HumanAuthConfig({
    required String issuer,
    required String audience,
    required List<int> signingKeySeed,
    String signingKeyId = _defaultSigningKeyId,
    Map<String, List<int>> verificationKeys = const <String, List<int>>{},
    this.accessTtl = const Duration(minutes: 15),
    this.sessionTtl = const Duration(days: 30),
    this.authorizationCodeTtl = const Duration(minutes: 1),
    this.deviceCodeTtl = const Duration(minutes: 10),
    this.devicePollInterval = const Duration(seconds: 5),
    this.deviceMaxAttempts = 30,
    this.deviceAttemptsPerMinute = 10,
    Iterable<String> allowedAuthorizationRedirectUris = const <String>[],
    String deviceVerificationUri = '/auth/device/verify',
  }) : issuer = _boundedText(issuer, 'issuer', 256),
       audience = _boundedText(audience, 'audience', 256),
       signingKeySeed = _fixedBytes(signingKeySeed, 32, 'signing key seed'),
       signingKeyId = _keyId(signingKeyId),
       verificationKeys = _verificationKeys(verificationKeys),
       allowedAuthorizationRedirectUris = _redirectUris(
         allowedAuthorizationRedirectUris,
       ),
       deviceVerificationUri = _verificationUri(deviceVerificationUri) {
    if (accessTtl <= Duration.zero) {
      throw ArgumentError.value(accessTtl, 'accessTtl', 'must be positive');
    }
    if (sessionTtl <= Duration.zero) {
      throw ArgumentError.value(sessionTtl, 'sessionTtl', 'must be positive');
    }
    if (sessionTtl < accessTtl) {
      throw ArgumentError.value(
        sessionTtl,
        'sessionTtl',
        'must not be shorter than accessTtl',
      );
    }
    _positiveBoundedDuration(
      authorizationCodeTtl,
      'authorizationCodeTtl',
      const Duration(days: 1),
    );
    _positiveBoundedDuration(
      deviceCodeTtl,
      'deviceCodeTtl',
      const Duration(days: 1),
    );
    if (devicePollInterval <= Duration.zero ||
        devicePollInterval > const Duration(minutes: 5)) {
      throw ArgumentError.value(
        devicePollInterval,
        'devicePollInterval',
        'must be between one microsecond and five minutes',
      );
    }
    if (deviceMaxAttempts <= 0 || deviceMaxAttempts > 10000) {
      throw ArgumentError.value(
        deviceMaxAttempts,
        'deviceMaxAttempts',
        'must be between 1 and 10000',
      );
    }
    if (deviceAttemptsPerMinute <= 0 || deviceAttemptsPerMinute > 1000) {
      throw ArgumentError.value(
        deviceAttemptsPerMinute,
        'deviceAttemptsPerMinute',
        'must be between 1 and 1000',
      );
    }
  }

  final String issuer;
  final String audience;
  final List<int> signingKeySeed;
  final String signingKeyId;
  final Map<String, List<int>> verificationKeys;
  final Duration accessTtl;
  final Duration sessionTtl;
  final Duration authorizationCodeTtl;
  final Duration deviceCodeTtl;
  final Duration devicePollInterval;
  final int deviceMaxAttempts;
  final int deviceAttemptsPerMinute;
  final Set<String> allowedAuthorizationRedirectUris;
  final String deviceVerificationUri;

  /// Reads the auth configuration without inventing a signing secret.
  ///
  /// A deployment with no auth variables keeps the legacy opaque credential
  /// flow available and does not expose auth endpoints. A partially supplied
  /// auth configuration fails closed instead of silently disabling login.
  static HumanAuthConfig? fromEnvironment(Map<String, String> values) {
    const names = <String>{
      'HYFENS_AUTH_ISSUER',
      'HYFENS_AUTH_AUDIENCE',
      'HYFENS_AUTH_SIGNING_KEY',
      'HYFENS_AUTH_SIGNING_KEY_ID',
      'HYFENS_AUTH_VERIFY_KEYS',
      'HYFENS_AUTH_ACCESS_TTL',
      'HYFENS_AUTH_SESSION_TTL',
      'HYFENS_AUTH_CODE_TTL',
      'HYFENS_AUTH_DEVICE_TTL',
      'HYFENS_AUTH_DEVICE_POLL_INTERVAL',
      'HYFENS_AUTH_DEVICE_MAX_ATTEMPTS',
      'HYFENS_AUTH_DEVICE_ATTEMPTS_PER_MINUTE',
      'HYFENS_AUTH_ALLOWED_REDIRECT_URIS',
      'HYFENS_AUTH_DEVICE_VERIFICATION_URI',
    };
    final configured = names.any((name) => _isMeaningfulSetting(values[name]));
    final encodedSeed = values['HYFENS_AUTH_SIGNING_KEY'];
    if (encodedSeed == null || encodedSeed.isEmpty) {
      if (configured) {
        throw ArgumentError(
          'HYFENS_AUTH_SIGNING_KEY is required when auth is configured',
        );
      }
      return null;
    }
    final seed = _decodeBase64(encodedSeed, 'HYFENS_AUTH_SIGNING_KEY');
    if (seed.length != 32) {
      throw ArgumentError('HYFENS_AUTH_SIGNING_KEY must contain 32 bytes');
    }
    final verifyKeys = _parseVerificationKeys(
      values['HYFENS_AUTH_VERIFY_KEYS'],
    );
    return HumanAuthConfig(
      issuer: _valueOrDefault(values['HYFENS_AUTH_ISSUER'], _defaultIssuer),
      audience: _valueOrDefault(
        values['HYFENS_AUTH_AUDIENCE'],
        _defaultAudience,
      ),
      signingKeySeed: seed,
      signingKeyId: _valueOrDefault(
        values['HYFENS_AUTH_SIGNING_KEY_ID'],
        _defaultSigningKeyId,
      ),
      verificationKeys: verifyKeys,
      accessTtl: _duration(
        _valueOrDefault(values['HYFENS_AUTH_ACCESS_TTL'], _defaultAccessTtl),
        'HYFENS_AUTH_ACCESS_TTL',
      ),
      sessionTtl: _duration(
        _valueOrDefault(values['HYFENS_AUTH_SESSION_TTL'], _defaultSessionTtl),
        'HYFENS_AUTH_SESSION_TTL',
      ),
      authorizationCodeTtl: _duration(
        _valueOrDefault(values['HYFENS_AUTH_CODE_TTL'], '1m'),
        'HYFENS_AUTH_CODE_TTL',
      ),
      deviceCodeTtl: _duration(
        _valueOrDefault(values['HYFENS_AUTH_DEVICE_TTL'], '10m'),
        'HYFENS_AUTH_DEVICE_TTL',
      ),
      devicePollInterval: _duration(
        _valueOrDefault(values['HYFENS_AUTH_DEVICE_POLL_INTERVAL'], '5s'),
        'HYFENS_AUTH_DEVICE_POLL_INTERVAL',
      ),
      deviceMaxAttempts: _integer(
        _valueOrDefault(values['HYFENS_AUTH_DEVICE_MAX_ATTEMPTS'], '30'),
        'HYFENS_AUTH_DEVICE_MAX_ATTEMPTS',
        maximum: 10000,
      ),
      deviceAttemptsPerMinute: _integer(
        _valueOrDefault(values['HYFENS_AUTH_DEVICE_ATTEMPTS_PER_MINUTE'], '10'),
        'HYFENS_AUTH_DEVICE_ATTEMPTS_PER_MINUTE',
        maximum: 1000,
      ),
      allowedAuthorizationRedirectUris: _parseRedirectUris(
        values['HYFENS_AUTH_ALLOWED_REDIRECT_URIS'],
      ),
      deviceVerificationUri: _valueOrDefault(
        values['HYFENS_AUTH_DEVICE_VERIFICATION_URI'],
        '/auth/device/verify',
      ),
    );
  }

  static String _valueOrDefault(String? value, String fallback) =>
      value == null || value.isEmpty ? fallback : value;

  static bool _isMeaningfulSetting(String? value) {
    if (value == null || value.isEmpty) return false;
    return true;
  }

  static Duration _duration(String value, String name) {
    final match = RegExp(r'^(\d+)(s|m|h|d)$').firstMatch(value);
    if (match == null) {
      throw ArgumentError('$name must use a duration such as 15m or 30d');
    }
    final amount = int.tryParse(match.group(1)!);
    if (amount == null || amount <= 0) {
      throw ArgumentError('$name must be positive');
    }
    final unit = match.group(2);
    final multiplier = switch (unit) {
      's' => const Duration(seconds: 1),
      'm' => const Duration(minutes: 1),
      'h' => const Duration(hours: 1),
      'd' => const Duration(days: 1),
      _ => throw ArgumentError('$name has an unsupported unit'),
    };
    final micros = amount * multiplier.inMicroseconds;
    if (micros <= 0 || micros > const Duration(days: 365).inMicroseconds) {
      throw ArgumentError('$name is outside the supported range');
    }
    return Duration(microseconds: micros);
  }

  static int _integer(String value, String name, {required int maximum}) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0 || parsed > maximum) {
      throw ArgumentError('$name must be between 1 and $maximum');
    }
    return parsed;
  }

  static void _positiveBoundedDuration(
    Duration value,
    String name,
    Duration maximum,
  ) {
    if (value <= Duration.zero || value > maximum) {
      throw ArgumentError.value(
        value,
        name,
        'must be positive and no longer than ${maximum.inDays} days',
      );
    }
  }

  static Set<String> _redirectUris(Iterable<String> values) {
    final result = <String>{};
    for (final value in values) {
      _validateRedirectUri(value, allowLoopback: true);
      result.add(value);
    }
    return Set.unmodifiable(result);
  }

  static List<String> _parseRedirectUris(String? value) {
    if (value == null || value.isEmpty) return const <String>[];
    late final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on Object {
      throw ArgumentError(
        'HYFENS_AUTH_ALLOWED_REDIRECT_URIS must be a JSON array',
      );
    }
    if (decoded is! List || decoded.any((item) => item is! String)) {
      throw ArgumentError(
        'HYFENS_AUTH_ALLOWED_REDIRECT_URIS must be a JSON array of strings',
      );
    }
    return decoded.cast<String>();
  }

  static String _verificationUri(String value) {
    if (value.isEmpty ||
        value.length > 2048 ||
        value.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ArgumentError('deviceVerificationUri is invalid');
    }
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        value.contains('?') ||
        value.contains('#') ||
        parsed.query.isNotEmpty ||
        parsed.fragment.isNotEmpty) {
      throw ArgumentError('deviceVerificationUri is invalid');
    }
    if (!parsed.isAbsolute &&
        (!value.startsWith('/') || value.startsWith('//'))) {
      throw ArgumentError(
        'deviceVerificationUri must be an absolute URI or path',
      );
    }
    if (parsed.isAbsolute &&
        (parsed.userInfo.isNotEmpty ||
            parsed.host.isEmpty ||
            (parsed.scheme != 'https' &&
                !(parsed.scheme == 'http' && _isLoopback(parsed.host))))) {
      throw ArgumentError(
        'deviceVerificationUri must use HTTPS except loopback',
      );
    }
    return value;
  }

  static void _validateRedirectUri(
    String value, {
    required bool allowLoopback,
  }) {
    if (value.isEmpty ||
        value.length > 2048 ||
        value.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ArgumentError('redirect URI is invalid');
    }
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        !parsed.isAbsolute ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        value.contains('#') ||
        parsed.fragment.isNotEmpty) {
      throw ArgumentError('redirect URI is invalid');
    }
    final loopback = _isLoopback(parsed.host);
    if (parsed.scheme != 'https' &&
        !(allowLoopback && loopback && parsed.scheme == 'http')) {
      throw ArgumentError('redirect URI must use HTTPS except loopback');
    }
  }

  static bool _isLoopback(String host) =>
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '[::1]' ||
      host == '::1';

  /// Validates the exact redirect URI accepted by the public-client flow.
  ///
  /// Loopback HTTP is permitted for the CLI callback. Every other redirect
  /// must be HTTPS and configured as an exact value when it is used.
  static void validateAuthorizationRedirectUri(String value) =>
      _validateRedirectUri(value, allowLoopback: true);

  static Map<String, List<int>> _parseVerificationKeys(String? value) {
    if (value == null || value.isEmpty) return const <String, List<int>>{};
    late final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on Object {
      throw ArgumentError('HYFENS_AUTH_VERIFY_KEYS must be a JSON object');
    }
    if (decoded is! Map) {
      throw ArgumentError('HYFENS_AUTH_VERIFY_KEYS must be a JSON object');
    }
    final result = <String, List<int>>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw ArgumentError(
          'HYFENS_AUTH_VERIFY_KEYS values must be base64 strings',
        );
      }
      final keyId = _keyId(entry.key as String);
      final key = _decodeBase64(
        entry.value as String,
        'HYFENS_AUTH_VERIFY_KEYS[$keyId]',
      );
      if (key.length != 32) {
        throw ArgumentError(
          'HYFENS_AUTH_VERIFY_KEYS[$keyId] must contain 32 bytes',
        );
      }
      result[keyId] = List.unmodifiable(key);
    }
    return Map.unmodifiable(result);
  }

  static List<int> _decodeBase64(String value, String field) {
    if (value.isEmpty || value.contains(RegExp(r'[\r\n\s]'))) {
      throw ArgumentError('$field must be base64 without whitespace');
    }
    try {
      final bytes = base64.decode(value);
      if (base64.encode(bytes) != value) {
        throw const FormatException('non-canonical base64');
      }
      return bytes;
    } on Object {
      throw ArgumentError('$field must be valid base64');
    }
  }

  static String _boundedText(String value, String field, int maxLength) {
    if (value.isEmpty ||
        value.length > maxLength ||
        value.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ArgumentError('$field is invalid');
    }
    return value;
  }

  static String _keyId(String value) {
    if (!RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(value)) {
      throw ArgumentError('Auth signing key ID is invalid');
    }
    return value;
  }

  static List<int> _fixedBytes(List<int> value, int length, String field) {
    if (value.length != length)
      throw ArgumentError('$field must be $length bytes');
    return List.unmodifiable(value);
  }

  static Map<String, List<int>> _verificationKeys(
    Map<String, List<int>> value,
  ) {
    return Map.unmodifiable(<String, List<int>>{
      for (final entry in value.entries)
        _keyId(entry.key): _fixedBytes(
          entry.value,
          32,
          'verification key ${entry.key}',
        ),
    });
  }
}

final class HumanMembership {
  HumanMembership({
    required String organizationId,
    required this.role,
    required Set<String> capabilities,
    required String profileName,
    String? applicationId,
    String? environmentId,
    String? profileApplicationId,
    String? profileEnvironmentId,
  }) : organizationId = requireOpaqueId(
         organizationId,
         'membership organization ID',
       ),
       applicationId = applicationId == null
           ? null
           : requireOpaqueId(applicationId, 'membership application ID'),
       environmentId = environmentId == null
           ? null
           : requireOpaqueId(environmentId, 'membership environment ID'),
       profileApplicationId = profileApplicationId == null
           ? null
           : requireOpaqueId(
               profileApplicationId,
               'membership profile application ID',
             ),
       profileEnvironmentId = profileEnvironmentId == null
           ? null
           : requireOpaqueId(
               profileEnvironmentId,
               'membership profile environment ID',
             ),
       profileName = requireNonEmpty(
         profileName,
         'membership profile name',
         maxLength: 64,
       ),
       capabilities = Set.unmodifiable(capabilities) {
    if (role.isEmpty ||
        role.length > 64 ||
        role.contains(RegExp(r'[\u0000\r\n]'))) {
      throw const FormatException('Invalid membership role');
    }
    if (this.capabilities.isEmpty ||
        this.capabilities.difference(controlScopes).isNotEmpty) {
      throw const FormatException(
        'Membership contains an unsupported capability',
      );
    }
  }

  final String organizationId;
  final String? applicationId;
  final String? environmentId;
  final String? profileApplicationId;
  final String? profileEnvironmentId;
  final String role;
  final Set<String> capabilities;
  final String profileName;

  Map<String, Object?> toJson() => <String, Object?>{
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'profileApplicationId': profileApplicationId,
    'profileEnvironmentId': profileEnvironmentId,
    'role': role,
    'capabilities': capabilities.toList()..sort(),
    'profileName': profileName,
  };

  static HumanMembership fromJson(Map<String, Object?> value) {
    final rawCapabilities = value['capabilities'];
    if (rawCapabilities is! List<Object?> ||
        rawCapabilities.any((item) => item is! String)) {
      throw const FormatException('Invalid membership capabilities');
    }
    return HumanMembership(
      organizationId: value['organizationId']! as String,
      applicationId: value['applicationId'] as String?,
      environmentId: value['environmentId'] as String?,
      profileApplicationId: value['profileApplicationId'] as String?,
      profileEnvironmentId: value['profileEnvironmentId'] as String?,
      role: value['role']! as String,
      capabilities: rawCapabilities.cast<String>().toSet(),
      profileName: value['profileName']! as String,
    );
  }
}

final class HumanUserRecord {
  HumanUserRecord({
    required String id,
    required String email,
    required this.passwordHash,
    required this.active,
    required Iterable<HumanMembership> memberships,
    required this.createdAt,
  }) : id = requireOpaqueId(id, 'human user ID'),
       email = HumanAuthService.normalizeHumanEmail(email),
       memberships = List.unmodifiable(memberships) {
    if (passwordHash.isEmpty || passwordHash.length > 1024) {
      throw const FormatException('Invalid password hash');
    }
    if (this.memberships.isEmpty) {
      throw const FormatException('Human user must have a membership');
    }
  }

  final String id;
  final String email;
  final String passwordHash;
  final bool active;
  final List<HumanMembership> memberships;
  final DateTime createdAt;

  HumanUserRecord copyWith({Iterable<HumanMembership>? memberships}) =>
      HumanUserRecord(
        id: id,
        email: email,
        passwordHash: passwordHash,
        active: active,
        memberships: memberships ?? this.memberships,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'email': email,
    'passwordHash': passwordHash,
    'active': active,
    'memberships': memberships.map((item) => item.toJson()).toList(),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static HumanUserRecord fromJson(Map<String, Object?> value) {
    final rawMemberships = value['memberships'];
    if (rawMemberships is! List<Object?> ||
        rawMemberships.any((item) => item is! Map)) {
      throw const FormatException('Invalid human user memberships');
    }
    return HumanUserRecord(
      id: value['id']! as String,
      email: value['email']! as String,
      passwordHash: value['passwordHash']! as String,
      active: value['active']! as bool,
      memberships: rawMemberships.map(
        (item) => HumanMembership.fromJson(<String, Object?>{
          for (final entry in (item! as Map).entries)
            '${entry.key}': entry.value,
        }),
      ),
      createdAt: DateTime.parse(value['createdAt']! as String),
    );
  }
}

final class HumanSessionRecord {
  HumanSessionRecord({
    required String id,
    required String userId,
    required String secretHash,
    required this.createdAt,
    required this.expiresAt,
    required this.lastUsedAt,
    required this.revokedAt,
  }) : id = requireOpaqueId(id, 'human session ID'),
       userId = requireOpaqueId(userId, 'human session user ID'),
       secretHash = requireNonEmpty(secretHash, 'human session secret hash');

  final String id;
  final String userId;
  final String secretHash;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime lastUsedAt;
  final DateTime? revokedAt;

  HumanSessionRecord copyWith({DateTime? lastUsedAt, DateTime? revokedAt}) =>
      HumanSessionRecord(
        id: id,
        userId: userId,
        secretHash: secretHash,
        createdAt: createdAt,
        expiresAt: expiresAt,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
        revokedAt: revokedAt ?? this.revokedAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'userId': userId,
    'secretHash': secretHash,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'lastUsedAt': lastUsedAt.toUtc().toIso8601String(),
    'revokedAt': revokedAt?.toUtc().toIso8601String(),
  };

  static HumanSessionRecord fromJson(Map<String, Object?> value) =>
      HumanSessionRecord(
        id: value['id']! as String,
        userId: value['userId']! as String,
        secretHash: value['secretHash']! as String,
        createdAt: DateTime.parse(value['createdAt']! as String),
        expiresAt: DateTime.parse(value['expiresAt']! as String),
        lastUsedAt: DateTime.parse(value['lastUsedAt']! as String),
        revokedAt: value['revokedAt'] == null
            ? null
            : DateTime.parse(value['revokedAt']! as String),
      );
}

final class HumanAuthProfile {
  const HumanAuthProfile({
    required this.name,
    required this.organizationId,
    required this.applicationId,
    required this.environmentId,
    required this.role,
    required this.capabilities,
  });

  final String name;
  final String organizationId;
  final String? applicationId;
  final String? environmentId;
  final String role;
  final Set<String> capabilities;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'organization_id': organizationId,
    'application_id': applicationId,
    'environment_id': environmentId,
    'role': role,
    'capabilities': capabilities.toList()..sort(),
  };
}

final class HumanIdentity {
  const HumanIdentity({required this.user, required this.profiles});

  final HumanUserRecord user;
  final List<HumanAuthProfile> profiles;

  Map<String, Object?> toJson() => <String, Object?>{
    'user_id': user.id,
    'email': user.email,
    'profiles': profiles.map((item) => item.toJson()).toList(),
  };
}

final class HumanLoginResult {
  const HumanLoginResult({
    required this.accessToken,
    required this.sessionToken,
    required this.accessExpiresAt,
    required this.sessionExpiresAt,
    required this.identity,
  });

  final String accessToken;
  final String sessionToken;
  final DateTime accessExpiresAt;
  final DateTime sessionExpiresAt;
  final HumanIdentity identity;

  Map<String, Object?> toJson() => <String, Object?>{
    'access_token': accessToken,
    'token_type': 'Bearer',
    'expires_at': accessExpiresAt.toUtc().toIso8601String(),
    'session_token': sessionToken,
    'session_expires_at': sessionExpiresAt.toUtc().toIso8601String(),
    ...identity.toJson(),
  };
}

final class HumanRefreshResult {
  const HumanRefreshResult({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.identity,
  });

  final String accessToken;
  final DateTime accessExpiresAt;
  final HumanIdentity identity;

  Map<String, Object?> toJson() => <String, Object?>{
    'access_token': accessToken,
    'token_type': 'Bearer',
    'expires_at': accessExpiresAt.toUtc().toIso8601String(),
    ...identity.toJson(),
  };
}

/// OAuth-style grant names supported by the control plane. These are kept in
/// this package instead of being inferred from a hostname or a client.
const String humanAuthorizationCodeGrantType = 'authorization_code';
const String humanDeviceAuthorizationGrantType =
    'urn:ietf:params:oauth:grant-type:device_code';

final class HumanAuthorizationRequest {
  const HumanAuthorizationRequest({
    required this.id,
    required this.clientId,
    required this.redirectUri,
    required this.codeChallenge,
    required this.codeChallengeMethod,
    required this.state,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String clientId;
  final String redirectUri;
  final String codeChallenge;
  final String codeChallengeMethod;
  final String state;
  final DateTime createdAt;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'request_id': id,
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'code_challenge': codeChallenge,
    'code_challenge_method': codeChallengeMethod,
    'state': state,
    'created_at': createdAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };
}

final class HumanAuthorizationCodeResult {
  const HumanAuthorizationCodeResult({
    required this.code,
    required this.request,
  });

  /// The raw code is returned only to the authorization response and is never
  /// persisted or written to an operator log; the server stores only its
  /// one-way hash.
  final String code;
  final HumanAuthorizationRequest request;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'state': request.state,
    'redirect_uri': request.redirectUri,
    'expires_at': request.expiresAt.toUtc().toIso8601String(),
  };
}

final class HumanDeviceAuthorizationResult {
  const HumanDeviceAuthorizationResult({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.interval,
    this.expiresInSeconds,
  });

  /// The device code is a credential for the polling client. It is returned
  /// in the response body only and is not included in the verification URL.
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final DateTime expiresAt;
  final Duration interval;
  final int? expiresInSeconds;

  int expiresIn([DateTime? now]) {
    final configured = expiresInSeconds;
    if (configured != null) return configured;
    final seconds = expiresAt
        .difference(now ?? DateTime.now().toUtc())
        .inSeconds;
    return max(0, seconds);
  }

  Map<String, Object?> toJson({DateTime? now}) => <String, Object?>{
    'device_code': deviceCode,
    'user_code': userCode,
    'verification_uri': verificationUri,
    'expires_in': expiresIn(now),
    'interval': interval.inSeconds,
  };
}

final class HumanDevicePollResult {
  const HumanDevicePollResult._({required this.status, this.loginResult});

  const HumanDevicePollResult.pending()
    : this._(status: 'authorization_pending');

  const HumanDevicePollResult.denied() : this._(status: 'access_denied');

  const HumanDevicePollResult.expired() : this._(status: 'expired_token');

  const HumanDevicePollResult.consumed() : this._(status: 'invalid_grant');

  const HumanDevicePollResult.approved(HumanLoginResult result)
    : this._(status: 'approved', loginResult: result);

  final String status;
  final HumanLoginResult? loginResult;

  bool get isPending => status == 'authorization_pending';
  bool get isApproved => status == 'approved';
}

/// Human operator authentication owned by the control plane.
///
/// Passwords and session bearer values are never persisted in plaintext.
/// Every privileged JWT authorization re-reads the user and membership from
/// the authoritative store, so a stale token does not preserve authorization
/// after membership or account changes.
final class HumanAuthService {
  HumanAuthService({
    required this.store,
    required this.config,
    Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? Random.secure(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  static const int _argonMemory = 16 * 1024;
  static const int _argonIterations = 2;
  static const int _argonParallelism = 1;
  static const int _argonHashLength = 32;
  static const int _saltLength = 16;
  static const List<int> _dummySalt = <int>[
    0x48,
    0x79,
    0x66,
    0x65,
    0x6e,
    0x73,
    0x2d,
    0x64,
    0x75,
    0x6d,
    0x6d,
    0x79,
    0x2d,
    0x73,
    0x61,
    0x6c,
  ];

  final ControlPlaneStore store;
  final HumanAuthConfig config;
  final Random _random;
  final DateTime Function() _clock;
  final Ed25519 _ed25519 = DartEd25519();
  final Argon2id _argon2 = const DartArgon2id(
    parallelism: _argonParallelism,
    memory: _argonMemory,
    iterations: _argonIterations,
    hashLength: _argonHashLength,
  );
  final Map<String, List<int>> _verificationKeys = <String, List<int>>{};
  Future<void> _writeTail = Future<void>.value();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    final keyPair = await _ed25519.newKeyPairFromSeed(config.signingKeySeed);
    try {
      final publicKey = await keyPair.extractPublicKey();
      _verificationKeys
        ..clear()
        ..addAll(config.verificationKeys)
        ..[config.signingKeyId] = List.unmodifiable(publicKey.bytes);
    } finally {
      keyPair.destroy();
    }
    _initialized = true;
  }

  Future<HumanUserRecord> bootstrapOwner({
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String email,
    required String password,
    String profileName = 'demo',
  }) => _serialized(() async {
    await _ensureInitialized();
    _validatePassword(password);
    final normalizedEmail = normalizeHumanEmail(email);
    final organization = await store.readJson('organizations', organizationId);
    final application = await store.readJson('applications', applicationId);
    final environment = await store.readJson('environments', environmentId);
    if (organization == null || application == null || environment == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    if (application['organizationId'] != organizationId ||
        environment['organizationId'] != organizationId ||
        environment['applicationId'] != applicationId) {
      throw const ControlPlaneException(
        'INVALID_SCOPE',
        'Owner scope does not match the existing resources',
        statusCode: 409,
      );
    }
    final ownerMembership = HumanMembership(
      organizationId: organizationId,
      profileApplicationId: applicationId,
      profileEnvironmentId: environmentId,
      role: 'owner',
      capabilities: controlScopes,
      profileName: profileName,
    );
    final bootstrapId = '$organizationId:$applicationId:$environmentId';
    final plannedUserId =
        'usr_${sha256Hex(utf8.encode(normalizedEmail)).substring(0, 32)}';
    final bootstrapClaim = <String, Object?>{
      'id': bootstrapId,
      'organizationId': organizationId,
      'applicationId': applicationId,
      'environmentId': environmentId,
      'userId': plannedUserId,
      'email': normalizedEmail,
      'consumedAt': _now().toIso8601String(),
    };
    try {
      // The generic collection/id uniqueness seam is atomic in both the file
      // and PostgreSQL stores. Repeating the exact same claim is idempotent;
      // a different owner cannot consume this scope's bootstrap capability.
      await store.createJson(
        'auth_bootstrap_consumptions',
        bootstrapId,
        bootstrapClaim,
      );
    } on StorageConflict {
      final existingClaim = await store.readJson(
        'auth_bootstrap_consumptions',
        bootstrapId,
      );
      if (existingClaim == null || existingClaim['email'] != normalizedEmail) {
        throw const ControlPlaneException(
          'BOOTSTRAP_ALREADY_CONSUMED',
          'The first-owner bootstrap capability has already been consumed for this scope',
          statusCode: 409,
        );
      }
    }
    final users = await _users();
    final existing = users.where((item) => item.email == normalizedEmail);
    if (existing.isNotEmpty) {
      final user = existing.first;
      final sameScope = user.memberships.indexWhere(
        (membership) => _sameMembershipScope(membership, ownerMembership),
      );
      if (sameScope >= 0) {
        final current = user.memberships[sameScope];
        if (current.capabilities.length ==
                ownerMembership.capabilities.length &&
            current.capabilities.containsAll(ownerMembership.capabilities)) {
          return user;
        }
        final memberships = user.memberships.toList();
        memberships[sameScope] = HumanMembership(
          organizationId: current.organizationId,
          applicationId: current.applicationId,
          environmentId: current.environmentId,
          profileApplicationId: current.profileApplicationId,
          profileEnvironmentId: current.profileEnvironmentId,
          role: current.role,
          capabilities: <String>{
            ...current.capabilities,
            ...ownerMembership.capabilities,
          },
          profileName: current.profileName,
        );
        final updated = user.copyWith(memberships: memberships);
        await store.replaceJson('users', user.id, updated.toJson());
        return updated;
      }
      final updated = user.copyWith(
        memberships: <HumanMembership>[...user.memberships, ownerMembership],
      );
      await store.replaceJson('users', user.id, updated.toJson());
      return updated;
    }
    final user = HumanUserRecord(
      id: plannedUserId,
      email: normalizedEmail,
      passwordHash: await _hashPassword(password),
      active: true,
      memberships: <HumanMembership>[ownerMembership],
      createdAt: _now(),
    );
    await store.createJson('users', user.id, user.toJson());
    return user;
  });

  /// Creates the bounded demo content administrator for an existing scope.
  ///
  /// This is deliberately a separate claim from [bootstrapOwner]. The admin
  /// membership contains only [contentAdminScope] and cannot authorize
  /// release, rollout, credential, or delivery operations.
  Future<HumanUserRecord> bootstrapAdmin({
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String email,
    required String password,
    String profileName = 'content-admin',
  }) => _serialized(() async {
    await _ensureInitialized();
    _validatePassword(password);
    final normalizedEmail = normalizeHumanEmail(email);
    final organization = await store.readJson('organizations', organizationId);
    final application = await store.readJson('applications', applicationId);
    final environment = await store.readJson('environments', environmentId);
    if (organization == null || application == null || environment == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    if (application['organizationId'] != organizationId ||
        environment['organizationId'] != organizationId ||
        environment['applicationId'] != applicationId) {
      throw const ControlPlaneException(
        'INVALID_SCOPE',
        'Admin scope does not match the existing resources',
        statusCode: 409,
      );
    }
    final adminMembership = HumanMembership(
      organizationId: organizationId,
      profileApplicationId: applicationId,
      profileEnvironmentId: environmentId,
      role: 'admin',
      capabilities: const <String>{contentAdminScope},
      profileName: profileName,
    );
    final bootstrapId = 'admin:$organizationId:$applicationId:$environmentId';
    final plannedUserId =
        'usr_${sha256Hex(utf8.encode(normalizedEmail)).substring(0, 32)}';
    final bootstrapClaim = <String, Object?>{
      'id': bootstrapId,
      'organizationId': organizationId,
      'applicationId': applicationId,
      'environmentId': environmentId,
      'userId': plannedUserId,
      'email': normalizedEmail,
      'role': adminMembership.role,
      'profileName': adminMembership.profileName,
      'capabilities': <String>[contentAdminScope],
      'consumedAt': _now().toIso8601String(),
    };
    try {
      await store.createJson(
        'auth_admin_bootstrap_consumptions',
        bootstrapId,
        bootstrapClaim,
      );
    } on StorageConflict {
      final existingClaim = await store.readJson(
        'auth_admin_bootstrap_consumptions',
        bootstrapId,
      );
      if (existingClaim == null ||
          existingClaim['organizationId'] != organizationId ||
          existingClaim['applicationId'] != applicationId ||
          existingClaim['environmentId'] != environmentId ||
          existingClaim['email'] != normalizedEmail ||
          existingClaim['role'] != adminMembership.role ||
          existingClaim['profileName'] != adminMembership.profileName) {
        throw const ControlPlaneException(
          'BOOTSTRAP_ALREADY_CONSUMED',
          'The content-admin bootstrap capability has already been consumed for this scope',
          statusCode: 409,
        );
      }
    }
    final users = await _users();
    final existing = users.where((item) => item.email == normalizedEmail);
    if (existing.isNotEmpty) {
      final user = existing.first;
      final sameScope = user.memberships.indexWhere(
        (membership) => _sameMembershipScope(membership, adminMembership),
      );
      if (sameScope >= 0) {
        final current = user.memberships[sameScope];
        if (current.capabilities.length ==
                adminMembership.capabilities.length &&
            current.capabilities.containsAll(adminMembership.capabilities)) {
          return user;
        }
        final memberships = user.memberships.toList();
        memberships[sameScope] = adminMembership;
        final updated = user.copyWith(memberships: memberships);
        await store.replaceJson('users', user.id, updated.toJson());
        return updated;
      }
      final updated = user.copyWith(
        memberships: <HumanMembership>[...user.memberships, adminMembership],
      );
      await store.replaceJson('users', user.id, updated.toJson());
      return updated;
    }
    final user = HumanUserRecord(
      id: plannedUserId,
      email: normalizedEmail,
      passwordHash: await _hashPassword(password),
      active: true,
      memberships: <HumanMembership>[adminMembership],
      createdAt: _now(),
    );
    try {
      await store.createJson('users', user.id, user.toJson());
    } on StorageConflict {
      final existingUser = await store.readJson('users', user.id);
      if (existingUser == null) rethrow;
      final concurrent = HumanUserRecord.fromJson(existingUser);
      if (concurrent.email != normalizedEmail) rethrow;
      return concurrent;
    }
    return user;
  });

  /// Creates an active read-only client in the server-selected organization
  /// and returns the same session contract as password login.
  ///
  /// The organization is supplied by trusted server configuration. This
  /// method deliberately accepts no role or capability arguments so a public
  /// request cannot widen its authorization profile.
  Future<HumanLoginResult> registerClient({
    required String organizationId,
    required String email,
    required String password,
  }) => _serialized(() async {
    await _ensureInitialized();
    late final String normalizedEmail;
    try {
      _validatePassword(password);
      normalizedEmail = normalizeHumanEmail(email);
    } on ControlPlaneException {
      throw const ControlPlaneException(
        'INVALID_REGISTRATION',
        'Email or password does not meet the registration policy',
        statusCode: 422,
      );
    }
    final organization = await store.readJson('organizations', organizationId);
    if (organization == null || organization['id'] != organizationId) {
      throw const ControlPlaneException(
        'PUBLIC_REGISTRATION_UNAVAILABLE',
        'Public registration is not configured for an available organization',
        statusCode: 503,
      );
    }
    final users = await _users();
    if (users.any((user) => user.email == normalizedEmail)) {
      _emailAlreadyRegistered();
    }
    final membership = HumanMembership(
      organizationId: organizationId,
      role: 'client',
      capabilities: publicClientReadScopes,
      profileName: 'client',
    );
    final user = HumanUserRecord(
      id: 'usr_${sha256Hex(utf8.encode(normalizedEmail)).substring(0, 32)}',
      email: normalizedEmail,
      passwordHash: await _hashPassword(password),
      active: true,
      memberships: <HumanMembership>[membership],
      createdAt: _now(),
    );
    try {
      await store.createJson('users', user.id, user.toJson());
    } on StorageConflict {
      // The deterministic user ID makes a concurrent registration for this
      // email collide in both stores. Preserve the first record and expose a
      // stable duplicate result; never overwrite its password or membership.
      final existing = await store.readJson('users', user.id);
      if (existing != null && existing['email'] == normalizedEmail) {
        _emailAlreadyRegistered();
      }
      rethrow;
    }
    return _issueSessionForUser(user);
  });

  Future<HumanLoginResult> login({
    required String email,
    required String password,
  }) => _serialized(() async {
    await _ensureInitialized();
    _validatePassword(password);
    final normalizedEmail = normalizeHumanEmail(email);
    late final HumanUserRecord? user;
    try {
      user = (await _users()).cast<HumanUserRecord?>().firstWhere(
        (item) => item!.email == normalizedEmail,
        orElse: () => null,
      );
    } on FormatException {
      _invalidCredentials();
    } on TypeError {
      _invalidCredentials();
    } on ControlPlaneException {
      _invalidCredentials();
    }
    late final String passwordHash;
    try {
      passwordHash = user == null
          ? await _hashPassword(password, salt: _dummySalt)
          : await _hashPassword(password, encoded: user.passwordHash);
    } on FormatException {
      _invalidCredentials();
    } on TypeError {
      _invalidCredentials();
    }
    if (user == null || !user.active || passwordHash != user.passwordHash) {
      _invalidCredentials();
    }
    return _issueSessionForUser(user);
  });

  /// Starts a public-client authorization request.
  ///
  /// The request binds the client, exact redirect URI, state, and S256 PKCE
  /// challenge. It contains no user identity until an authenticated browser
  /// session completes it.
  Future<HumanAuthorizationRequest> beginAuthorization({
    required String clientId,
    required String redirectUri,
    required String codeChallenge,
    required String state,
    String responseType = 'code',
    String codeChallengeMethod = 'S256',
  }) => _serialized(() async {
    await _ensureInitialized();
    _validateClientId(clientId);
    if (responseType != 'code') {
      throw const ControlPlaneException(
        'UNSUPPORTED_RESPONSE_TYPE',
        'Only the authorization code response type is supported',
      );
    }
    if (codeChallengeMethod != 'S256') {
      throw const ControlPlaneException(
        'UNSUPPORTED_CODE_CHALLENGE_METHOD',
        'Only S256 PKCE is supported',
      );
    }
    _validatePkceChallenge(codeChallenge);
    _validateState(state);
    _validateAuthorizationRedirect(clientId, redirectUri);
    final now = _now();
    final request = HumanAuthorizationRequest(
      id: _randomId('areq_'),
      clientId: clientId,
      redirectUri: redirectUri,
      codeChallenge: codeChallenge,
      codeChallengeMethod: codeChallengeMethod,
      state: state,
      createdAt: now,
      expiresAt: now.add(config.authorizationCodeTtl),
    );
    await store.createJson(
      'auth_authorization_requests',
      request.id,
      <String, Object?>{
        'id': request.id,
        'clientId': request.clientId,
        'redirectUri': request.redirectUri,
        'codeChallenge': request.codeChallenge,
        'codeChallengeMethod': request.codeChallengeMethod,
        'state': request.state,
        'stateHash': sha256Hex(utf8.encode(request.state)),
        'createdAt': request.createdAt.toIso8601String(),
        'expiresAt': request.expiresAt.toIso8601String(),
      },
    );
    return request;
  });

  /// Reads a still-addressable authorization request for a browser approval
  /// page. The request has no user authority until [authorize] is called.
  Future<HumanAuthorizationRequest> authorizationRequest({
    required String requestId,
  }) async {
    await _ensureInitialized();
    final request = await _readAuthorizationRequest(requestId);
    if (!request.expiresAt.isAfter(_now())) _invalidAuthorizationRequest();
    return request;
  }

  /// Completes an authorization request using an already authenticated human
  /// session. The resulting code is sent only to the exact validated redirect.
  Future<HumanAuthorizationCodeResult> authorize({
    required String requestId,
    required String accessToken,
  }) => _serialized(() async {
    await _ensureInitialized();
    final context = await _authenticateAccessToken(accessToken);
    final request = await _readAuthorizationRequest(requestId);
    final now = _now();
    if (!request.expiresAt.isAfter(now)) {
      throw const ControlPlaneException(
        'AUTHORIZATION_REQUEST_EXPIRED',
        'Authorization request has expired',
        statusCode: 400,
      );
    }
    await _claimOnce(
      'auth_authorization_request_uses',
      request.id,
      'authorization request',
    );
    final codeBytes = _randomBytes(32);
    final code = 'hfc_${_encodeBytes(codeBytes)}';
    final codeHash = sha256Hex(utf8.encode(code));
    await store.createJson(
      'auth_authorization_codes',
      codeHash,
      <String, Object?>{
        'id': codeHash,
        'requestId': request.id,
        'clientId': request.clientId,
        'redirectUri': request.redirectUri,
        'codeChallenge': request.codeChallenge,
        'codeChallengeMethod': request.codeChallengeMethod,
        'userId': context.user.id,
        'createdAt': now.toIso8601String(),
        'expiresAt': now.add(config.authorizationCodeTtl).toIso8601String(),
      },
    );
    return HumanAuthorizationCodeResult(code: code, request: request);
  });

  /// Alias with an explicit name for callers that model this as code issuance.
  Future<HumanAuthorizationCodeResult> issueAuthorizationCode({
    required String requestId,
    required String accessToken,
  }) => authorize(requestId: requestId, accessToken: accessToken);

  /// Exchanges a one-time authorization code for the same revocable server
  /// session and short-lived access JWT used by password login.
  Future<HumanLoginResult> exchangeAuthorizationCode({
    required String clientId,
    required String code,
    required String redirectUri,
    required String codeVerifier,
  }) => _serialized(() async {
    await _ensureInitialized();
    _validateClientId(clientId);
    _validatePkceVerifier(codeVerifier);
    _validateAuthorizationRedirect(clientId, redirectUri);
    final codeHash = _authorizationCodeHash(code);
    final value = await store.readJson('auth_authorization_codes', codeHash);
    if (value == null) _invalidAuthorizationCode();
    final record = _authorizationCodeRecord(value);
    final now = _now();
    if (record.clientId != clientId ||
        record.redirectUri != redirectUri ||
        !record.expiresAt.isAfter(now) ||
        record.codeChallengeMethod != 'S256' ||
        !_constantTimeEqual(
          _pkceChallenge(codeVerifier),
          record.codeChallenge,
        )) {
      _invalidAuthorizationCode();
    }
    final user = await _activeUser(record.userId);
    await _claimOnce(
      'auth_authorization_code_uses',
      codeHash,
      'authorization code',
    );
    return _issueSessionForUser(user);
  });

  /// Exchanges a code using the common OAuth parameter names. This keeps the
  /// server-side API easy to use from a form or a JSON HTTP adapter.
  Future<HumanLoginResult> redeemAuthorizationCode({
    required String clientId,
    required String code,
    required String redirectUri,
    required String codeVerifier,
  }) => exchangeAuthorizationCode(
    clientId: clientId,
    code: code,
    redirectUri: redirectUri,
    codeVerifier: codeVerifier,
  );

  /// Creates a short-lived headless device authorization. The device secret
  /// is returned to the polling client, while the user-facing URL contains no
  /// secret or user code.
  Future<HumanDeviceAuthorizationResult> createDeviceAuthorization({
    required String clientId,
  }) => _serialized(() async {
    await _ensureInitialized();
    _validateClientId(clientId);
    final now = _now();
    for (var attempt = 0; attempt < 5; attempt++) {
      final deviceCode = 'hfd_${_encodeBytes(_randomBytes(32))}';
      final userCode = _newUserCode();
      final deviceHash = sha256Hex(utf8.encode(deviceCode));
      final userHash = sha256Hex(utf8.encode(userCode));
      final expiresAt = now.add(config.deviceCodeTtl);
      try {
        await store.createJson(
          'auth_device_codes',
          deviceHash,
          <String, Object?>{
            'id': deviceHash,
            'clientId': clientId,
            'userCodeHash': userHash,
            'createdAt': now.toIso8601String(),
            'expiresAt': expiresAt.toIso8601String(),
          },
        );
        await store.createJson(
          'auth_device_user_codes',
          userHash,
          <String, Object?>{
            'id': userHash,
            'deviceCodeHash': deviceHash,
            'createdAt': now.toIso8601String(),
            'expiresAt': expiresAt.toIso8601String(),
          },
        );
        return HumanDeviceAuthorizationResult(
          deviceCode: deviceCode,
          userCode: _displayUserCode(userCode),
          verificationUri: config.deviceVerificationUri,
          expiresAt: expiresAt,
          interval: config.devicePollInterval,
          expiresInSeconds: config.deviceCodeTtl.inSeconds,
        );
      } on StorageConflict {
        // A random user-code collision is safe to retry. If the device
        // record was inserted but its secondary index collided, the
        // immutable record remains harmless and the next code is used.
        if (attempt == 4) rethrow;
      }
    }
    throw const StorageConflict('Could not allocate a device authorization');
  });

  /// Approves a device code from an authenticated browser/dashboard session.
  Future<void> approveDeviceAuthorization({
    required String userCode,
    required String accessToken,
  }) => _serialized(() async {
    await _ensureInitialized();
    final context = await _authenticateAccessToken(accessToken);
    final normalized = _normalizeUserCode(userCode);
    final userHash = sha256Hex(utf8.encode(normalized));
    final index = await store.readJson('auth_device_user_codes', userHash);
    if (index == null) _invalidDeviceCode();
    final deviceHash = _recordString(index, 'deviceCodeHash');
    final device = await store.readJson('auth_device_codes', deviceHash);
    if (device == null || _recordString(device, 'userCodeHash') != userHash) {
      _invalidDeviceCode();
    }
    if (await store.readJson('auth_device_consumptions', deviceHash) != null) {
      throw const ControlPlaneException(
        'DEVICE_CODE_CONSUMED',
        'Device authorization code has already been consumed',
        statusCode: 400,
      );
    }
    final expiresAt = _recordTime(device, 'expiresAt');
    if (!expiresAt.isAfter(_now())) _deviceExpired();
    final approval = <String, Object?>{
      'id': deviceHash,
      'deviceCodeHash': deviceHash,
      'userId': context.user.id,
      'approvedAt': _now().toIso8601String(),
      'nonce': _randomId('dap_'),
    };
    try {
      await store.createJson('auth_device_approvals', deviceHash, approval);
    } on StorageConflict {
      final existing = await store.readJson(
        'auth_device_approvals',
        deviceHash,
      );
      if (existing == null || existing['userId'] != context.user.id) {
        throw const ControlPlaneException(
          'DEVICE_ALREADY_APPROVED',
          'Device authorization has already been approved',
          statusCode: 409,
        );
      }
    }
  });

  /// Polls and, after approval, atomically consumes a device code.
  Future<HumanDevicePollResult> pollDeviceAuthorization({
    required String clientId,
    required String deviceCode,
  }) => _serialized(() async {
    await _ensureInitialized();
    _validateClientId(clientId);
    if (!_validDeviceSecret(deviceCode)) _invalidDeviceCode();
    final deviceHash = sha256Hex(utf8.encode(deviceCode));
    final device = await store.readJson('auth_device_codes', deviceHash);
    if (device == null || _recordString(device, 'clientId') != clientId) {
      _invalidDeviceCode();
    }
    final consumed = await store.readJson(
      'auth_device_consumptions',
      deviceHash,
    );
    if (consumed != null) return const HumanDevicePollResult.consumed();
    final now = _now();
    final expiresAt = _recordTime(device, 'expiresAt');
    if (!expiresAt.isAfter(now)) return const HumanDevicePollResult.expired();
    await _recordDeviceAttempt(deviceHash, now);
    final approval = await store.readJson('auth_device_approvals', deviceHash);
    if (approval == null) return const HumanDevicePollResult.pending();
    final user = await _activeUser(_recordString(approval, 'userId'));
    await _claimOnce('auth_device_consumptions', deviceHash, 'device code');
    return HumanDevicePollResult.approved(await _issueSessionForUser(user));
  });

  Future<HumanLoginResult> _issueSessionForUser(HumanUserRecord user) async {
    final now = _now();
    final sessionId = _randomId('ses_');
    final secret = _randomBytes(32);
    final sessionToken = _sessionToken(sessionId, secret);
    final session = HumanSessionRecord(
      id: sessionId,
      userId: user.id,
      secretHash: sha256Hex(utf8.encode(sessionToken)),
      createdAt: now,
      expiresAt: now.add(config.sessionTtl),
      lastUsedAt: now,
      revokedAt: null,
    );
    await store.createJson('sessions', session.id, session.toJson());
    final issued = await _issueAccessToken(user, session);
    return HumanLoginResult(
      accessToken: issued.token,
      sessionToken: sessionToken,
      accessExpiresAt: issued.expiresAt,
      sessionExpiresAt: session.expiresAt,
      identity: _identity(user),
    );
  }

  Future<HumanAuthorizationRequest> _readAuthorizationRequest(
    String requestId,
  ) async {
    if (!_safeTokenPart(requestId)) _invalidAuthorizationRequest();
    final value = await store.readJson(
      'auth_authorization_requests',
      requestId,
    );
    if (value == null) _invalidAuthorizationRequest();
    try {
      final state = _recordString(value, 'state');
      final stateHash = _recordString(value, 'stateHash');
      final request = HumanAuthorizationRequest(
        id: _recordString(value, 'id'),
        clientId: _recordString(value, 'clientId'),
        redirectUri: _recordString(value, 'redirectUri'),
        codeChallenge: _recordString(value, 'codeChallenge'),
        codeChallengeMethod: _recordString(value, 'codeChallengeMethod'),
        state: state,
        createdAt: _recordTime(value, 'createdAt'),
        expiresAt: _recordTime(value, 'expiresAt'),
      );
      if (request.id != requestId ||
          request.codeChallengeMethod != 'S256' ||
          stateHash.length != 64 ||
          !_constantTimeEqual(stateHash, sha256Hex(utf8.encode(state)))) {
        _invalidAuthorizationRequest();
      }
      _validateClientId(request.clientId);
      _validatePkceChallenge(request.codeChallenge);
      _validateState(request.state);
      _validateAuthorizationRedirect(request.clientId, request.redirectUri);
      return request;
    } on Object {
      _invalidAuthorizationRequest();
    }
  }

  _AuthorizationCodeRecord _authorizationCodeRecord(
    Map<String, Object?> value,
  ) {
    try {
      return _AuthorizationCodeRecord(
        clientId: _recordString(value, 'clientId'),
        redirectUri: _recordString(value, 'redirectUri'),
        codeChallenge: _recordString(value, 'codeChallenge'),
        codeChallengeMethod: _recordString(value, 'codeChallengeMethod'),
        userId: _recordString(value, 'userId'),
        createdAt: _recordTime(value, 'createdAt'),
        expiresAt: _recordTime(value, 'expiresAt'),
      );
    } on Object {
      _invalidAuthorizationCode();
    }
  }

  Future<void> _recordDeviceAttempt(String deviceHash, DateTime now) async {
    final attempts = await store.listJson('auth_device_attempts');
    final current = <DateTime>[];
    for (final value in attempts) {
      if (value['deviceCodeHash'] != deviceHash) continue;
      final raw = value['createdAt'];
      if (raw is! String) continue;
      final timestamp = DateTime.tryParse(raw)?.toUtc();
      if (timestamp == null || timestamp.isAfter(now)) continue;
      current.add(timestamp);
    }
    if (current.length >= config.deviceMaxAttempts) {
      throw const ControlPlaneException(
        'DEVICE_ATTEMPTS_EXCEEDED',
        'Device authorization polling attempts are exhausted',
        statusCode: 429,
      );
    }
    final recent = current
        .where(
          (timestamp) => now.difference(timestamp) < const Duration(minutes: 1),
        )
        .length;
    if (recent >= config.deviceAttemptsPerMinute) {
      throw const ControlPlaneException(
        'DEVICE_RATE_LIMITED',
        'Device authorization polling is rate limited',
        statusCode: 429,
      );
    }
    await store.createJson(
      'auth_device_attempts',
      '$deviceHash-${_randomId('att_')}',
      <String, Object?>{
        'deviceCodeHash': deviceHash,
        'createdAt': now.toIso8601String(),
      },
    );
  }

  Future<void> _claimOnce(String collection, String id, String resource) async {
    try {
      await store.createJson(collection, id, <String, Object?>{
        'id': id,
        'claimedAt': _now().toIso8601String(),
        'nonce': _randomId('claim_'),
      });
    } on StorageConflict {
      throw ControlPlaneException(
        switch (resource) {
          'authorization request' => 'AUTHORIZATION_REQUEST_USED',
          'authorization code' => 'AUTHORIZATION_CODE_USED',
          'device code' => 'DEVICE_CODE_CONSUMED',
          _ => 'AUTHORIZATION_ALREADY_USED',
        },
        '$resource has already been used',
        statusCode: 400,
      );
    }
  }

  void _validateAuthorizationRedirect(String clientId, String redirectUri) {
    try {
      HumanAuthConfig.validateAuthorizationRedirectUri(redirectUri);
    } on ArgumentError {
      _invalidRedirectUri();
    }
    final parsed = Uri.parse(redirectUri);
    final loopback = _isLoopbackHost(parsed.host);
    if (!loopback &&
        !config.allowedAuthorizationRedirectUris.contains(redirectUri)) {
      _invalidRedirectUri();
    }
    // Keep the argument in the policy seam so future client registration can
    // narrow redirect ownership without changing the grant implementation.
    if (clientId.isEmpty) _invalidRedirectUri();
  }

  static void _validateClientId(String value) {
    if (!RegExp(r'^[A-Za-z0-9._~-]{1,128}$').hasMatch(value)) {
      throw const ControlPlaneException(
        'INVALID_CLIENT',
        'Client identifier is invalid',
      );
    }
  }

  static void _validateState(String value) {
    if (!RegExp(r'^[A-Za-z0-9._~-]{8,512}$').hasMatch(value)) {
      throw const ControlPlaneException(
        'INVALID_STATE',
        'Authorization state is invalid',
      );
    }
  }

  static void _validatePkceChallenge(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
      throw const ControlPlaneException(
        'INVALID_CODE_CHALLENGE',
        'PKCE code challenge must be an unpadded base64url S256 value',
      );
    }
  }

  static void _validatePkceVerifier(String value) {
    if (!RegExp(r'^[A-Za-z0-9._~-]{43,128}$').hasMatch(value)) {
      throw const ControlPlaneException(
        'INVALID_CODE_VERIFIER',
        'PKCE code verifier is invalid',
      );
    }
  }

  static String _pkceChallenge(String verifier) => base64Url
      .encode(crypto.sha256.convert(utf8.encode(verifier)).bytes)
      .replaceAll('=', '');

  static String _authorizationCodeHash(String value) {
    if (!_validAuthorizationCode(value)) _invalidAuthorizationCode();
    return sha256Hex(utf8.encode(value));
  }

  static bool _validAuthorizationCode(String value) =>
      value.length <= 512 && RegExp(r'^hfc_[A-Za-z0-9_-]{43}$').hasMatch(value);

  static bool _validDeviceSecret(String value) =>
      value.length <= 512 && RegExp(r'^hfd_[A-Za-z0-9_-]{43}$').hasMatch(value);

  static String _normalizeUserCode(String value) {
    final normalized = value.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (!RegExp(r'^[A-Z2-9]{8}$').hasMatch(normalized)) _invalidDeviceCode();
    return normalized;
  }

  String _newUserCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List<String>.generate(
      8,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }

  static String _displayUserCode(String normalized) =>
      '${normalized.substring(0, 4)}-${normalized.substring(4)}';

  static bool _isLoopbackHost(String host) =>
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '[::1]';

  static String _recordString(Map<String, Object?> value, String key) {
    final result = value[key];
    if (result is! String || result.isEmpty) {
      throw const FormatException('Invalid auth record');
    }
    return result;
  }

  static DateTime _recordTime(Map<String, Object?> value, String key) {
    final raw = _recordString(value, key);
    final result = DateTime.tryParse(raw)?.toUtc();
    if (result == null) throw const FormatException('Invalid auth timestamp');
    return result;
  }

  static Never _invalidAuthorizationRequest() =>
      throw const ControlPlaneException(
        'INVALID_AUTHORIZATION_REQUEST',
        'Authorization request is invalid or expired',
        statusCode: 400,
      );

  static Never _invalidRedirectUri() => throw const ControlPlaneException(
    'INVALID_REDIRECT_URI',
    'Redirect URI is not registered for this client',
    statusCode: 400,
  );

  static Never _invalidAuthorizationCode() => throw const ControlPlaneException(
    'INVALID_GRANT',
    'Authorization code is invalid, expired, or already used',
    statusCode: 400,
  );

  static Never _invalidDeviceCode() => throw const ControlPlaneException(
    'INVALID_DEVICE_CODE',
    'Device authorization code is invalid',
    statusCode: 400,
  );

  static Never _deviceExpired() => throw const ControlPlaneException(
    'DEVICE_CODE_EXPIRED',
    'Device authorization code has expired',
    statusCode: 400,
  );

  Future<HumanRefreshResult> refresh({required String sessionToken}) =>
      _serialized(() async {
        await _ensureInitialized();
        final session = await _sessionForToken(sessionToken);
        final user = await _activeUser(session.userId);
        final now = _now();
        final updatedValue = await store.touchSessionIfActive(
          id: session.id,
          expectedSecretHash: session.secretHash,
          now: now,
        );
        if (updatedValue == null) _unauthorized();
        late final HumanSessionRecord updated;
        try {
          updated = HumanSessionRecord.fromJson(updatedValue);
        } on FormatException {
          _unauthorized();
        } on TypeError {
          _unauthorized();
        }
        final issued = await _issueAccessToken(user, updated);
        return HumanRefreshResult(
          accessToken: issued.token,
          accessExpiresAt: issued.expiresAt,
          identity: _identity(user),
        );
      });

  Future<void> logout({required String sessionToken}) => _serialized(() async {
    await _ensureInitialized();
    final session = await _sessionForToken(sessionToken, requireActive: false);
    await store.revokeSessionIfActive(
      id: session.id,
      expectedSecretHash: session.secretHash,
      revokedAt: _now(),
    );
  });

  Future<HumanIdentity> me({required String accessToken}) async {
    final context = await _authenticateAccessToken(accessToken);
    return _identity(context.user);
  }

  /// Converts a valid human control JWT into the existing service actor shape.
  /// The returned record is ephemeral and is never persisted as an opaque
  /// credential. Delivery operations must continue using delivery authority.
  Future<CredentialRecord> authorizeAccessToken({
    required String token,
    required String requiredScope,
    required CredentialKind kind,
    String? organizationId,
    String? applicationId,
    String? environmentId,
  }) async {
    if (kind != CredentialKind.control) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'Human access tokens are not delivery credentials',
        statusCode: 403,
      );
    }
    final context = await _authenticateAccessToken(token);
    final membership = _membershipFor(
      context.user,
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
    );
    // Owner membership is the authoritative full-control role. Unioning the
    // current control scope set keeps an owner created before a newly added
    // control capability from being stranded with a stale serialized scope
    // list, while delegated roles remain explicitly capability-bound.
    final effectiveCapabilities = membership.role == 'owner'
        ? <String>{...membership.capabilities, ...controlScopes}
        : membership.capabilities;
    if (!effectiveCapabilities.contains(requiredScope)) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'Credential scope is not permitted',
        statusCode: 403,
      );
    }
    return CredentialRecord(
      id: context.user.id,
      organizationId: membership.organizationId,
      kind: CredentialKind.control,
      tokenHash: CredentialService.tokenHash(token),
      scopes: effectiveCapabilities,
      applicationId: null,
      environmentId: null,
      createdAt: context.session.createdAt,
      expiresAt: context.expiresAt,
      revoked: false,
    );
  }

  Future<_AccessContext> _authenticateAccessToken(String token) async {
    await _ensureInitialized();
    final claims = await _verifyJwt(token);
    final sessionValue = await store.readJson('sessions', claims.sessionId);
    if (sessionValue == null) _unauthorized();
    late final HumanSessionRecord session;
    try {
      session = HumanSessionRecord.fromJson(sessionValue);
    } on FormatException {
      _unauthorized();
    } on TypeError {
      _unauthorized();
    }
    final now = _now();
    if (session.revokedAt != null || !session.expiresAt.isAfter(now)) {
      _unauthorized();
    }
    if (claims.expiration.isBefore(now) ||
        session.expiresAt.isBefore(claims.expiration)) {
      _unauthorized();
    }
    final user = await _activeUser(session.userId);
    if (claims.subject != user.id) _unauthorized();
    return _AccessContext(
      user: user,
      session: session,
      expiresAt: claims.expiration,
    );
  }

  Future<_IssuedAccessToken> _issueAccessToken(
    HumanUserRecord user,
    HumanSessionRecord session,
  ) async {
    final now = _now();
    final expiration = session.expiresAt.isBefore(now.add(config.accessTtl))
        ? session.expiresAt
        : now.add(config.accessTtl);
    final iat = now.millisecondsSinceEpoch ~/ 1000;
    final exp = expiration.millisecondsSinceEpoch ~/ 1000;
    if (exp <= iat) _unauthorized();
    final header = <String, Object?>{
      'alg': 'EdDSA',
      'kid': config.signingKeyId,
      'typ': 'JWT',
    };
    final payload = <String, Object?>{
      'iss': config.issuer,
      'sub': user.id,
      'aud': config.audience,
      'iat': iat,
      'exp': exp,
      'jti': _randomId('jti'),
      'session_id': session.id,
    };
    final encodedHeader = _encodeJson(header);
    final encodedPayload = _encodeJson(payload);
    final signingInput = '$encodedHeader.$encodedPayload';
    final keyPair = await _ed25519.newKeyPairFromSeed(config.signingKeySeed);
    try {
      final signature = await _ed25519.sign(
        utf8.encode(signingInput),
        keyPair: keyPair,
      );
      return _IssuedAccessToken(
        token: '$signingInput.${_encodeBytes(signature.bytes)}',
        expiresAt: DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
      );
    } finally {
      keyPair.destroy();
    }
  }

  Future<_JwtClaims> _verifyJwt(String token) async {
    if (!AuthJwt.isJwtLike(token) || token.length > 8192) _unauthorized();
    final parts = token.split('.');
    late final Map<String, Object?> header;
    late final Map<String, Object?> payload;
    late final List<int> signature;
    try {
      header = _decodeJson(parts[0]);
      payload = _decodeJson(parts[1]);
      signature = _decodeBytes(parts[2]);
    } on Object {
      _unauthorized();
    }
    if (header.length != 3 ||
        header['alg'] != 'EdDSA' ||
        header['typ'] != 'JWT' ||
        header['kid'] is! String) {
      _unauthorized();
    }
    final keyId = header['kid']! as String;
    final publicKey = _verificationKeys[keyId];
    if (publicKey == null || signature.length != 64) _unauthorized();
    final verified = await _ed25519.verify(
      utf8.encode('${parts[0]}.${parts[1]}'),
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!verified) _unauthorized();
    const required = <String>{
      'iss',
      'sub',
      'aud',
      'iat',
      'exp',
      'jti',
      'session_id',
    };
    final allowed = <String>{...required, 'nbf'};
    if (!payload.keys.toSet().containsAll(required) ||
        payload.keys.any((key) => !allowed.contains(key)) ||
        payload['iss'] != config.issuer ||
        payload['aud'] != config.audience ||
        payload['sub'] is! String ||
        payload['jti'] is! String ||
        payload['session_id'] is! String ||
        payload['iat'] is! int ||
        payload['exp'] is! int ||
        (payload['nbf'] != null && payload['nbf'] is! int)) {
      _unauthorized();
    }
    final iat = payload['iat']! as int;
    final exp = payload['exp']! as int;
    final nowSeconds = _now().millisecondsSinceEpoch ~/ 1000;
    if (iat > nowSeconds || exp <= iat || exp <= nowSeconds) _unauthorized();
    final nbf = payload['nbf'];
    if (nbf is int && nbf > nowSeconds) _unauthorized();
    final subject = payload['sub']! as String;
    final sessionId = payload['session_id']! as String;
    if (!_safeTokenPart(subject) ||
        !_safeTokenPart(payload['jti']! as String) ||
        !_safeTokenPart(sessionId)) {
      _unauthorized();
    }
    return _JwtClaims(
      subject: subject,
      sessionId: sessionId,
      expiration: DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
    );
  }

  Future<HumanSessionRecord> _sessionForToken(
    String value, {
    bool requireActive = true,
  }) async {
    final parts = value.split('.');
    if (parts.length != 3 ||
        parts[0] != 'hfs' ||
        parts[1].isEmpty ||
        parts[2].isEmpty) {
      _unauthorized();
    }
    final record = await store.readJson('sessions', parts[1]);
    if (record == null) _unauthorized();
    late final HumanSessionRecord session;
    try {
      session = HumanSessionRecord.fromJson(record);
    } on FormatException {
      _unauthorized();
    } on TypeError {
      _unauthorized();
    }
    final expected = sha256Hex(utf8.encode(value));
    if (!_constantTimeEqual(expected, session.secretHash) ||
        requireActive &&
            (session.revokedAt != null || !session.expiresAt.isAfter(_now()))) {
      _unauthorized();
    }
    return session;
  }

  Future<HumanUserRecord> _activeUser(String id) async {
    final value = await store.readJson('users', id);
    if (value == null) _unauthorized();
    late final HumanUserRecord user;
    try {
      user = HumanUserRecord.fromJson(value);
    } on FormatException {
      _unauthorized();
    } on TypeError {
      _unauthorized();
    } on ControlPlaneException {
      _unauthorized();
    }
    if (!user.active) _unauthorized();
    return user;
  }

  Future<List<HumanUserRecord>> _users() async =>
      (await store.listJson('users'))
          .map(HumanUserRecord.fromJson)
          .toList(growable: false);

  HumanMembership _membershipFor(
    HumanUserRecord user, {
    required String? organizationId,
    required String? applicationId,
    required String? environmentId,
  }) {
    final matches = user.memberships
        .where((membership) {
          if (organizationId != null &&
              membership.organizationId != organizationId) {
            return false;
          }
          if (membership.applicationId != null &&
              membership.applicationId != applicationId) {
            return false;
          }
          if (membership.environmentId != null &&
              membership.environmentId != environmentId) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    if (matches.isEmpty) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    if (organizationId == null && matches.length != 1) {
      throw const ControlPlaneException(
        'INVALID_SCOPE',
        'An explicit organization scope is required',
        statusCode: 400,
      );
    }
    return matches.first;
  }

  HumanIdentity _identity(HumanUserRecord user) => HumanIdentity(
    user: user,
    profiles: user.memberships
        .map(
          (membership) => HumanAuthProfile(
            name: membership.profileName,
            organizationId: membership.organizationId,
            applicationId:
                membership.profileApplicationId ?? membership.applicationId,
            environmentId:
                membership.profileEnvironmentId ?? membership.environmentId,
            role: membership.role,
            capabilities: membership.capabilities,
          ),
        )
        .toList(growable: false),
  );

  Future<String> _hashPassword(
    String password, {
    String? encoded,
    List<int>? salt,
  }) async {
    final actualSalt =
        salt ??
        (encoded == null
            ? _randomBytes(_saltLength)
            : _parsePasswordHash(encoded).salt);
    final derived = await _argon2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: actualSalt,
    );
    final bytes = await derived.extractBytes();
    if (encoded == null) {
      return 'argon2id\$v=19\$m=$_argonMemory,t=$_argonIterations,p=$_argonParallelism\$'
          '${_encodeBytes(actualSalt)}\$${_encodeBytes(bytes)}';
    }
    final parsed = _parsePasswordHash(encoded);
    return _constantTimeEqual(bytes, parsed.hash) ? encoded : '';
  }

  _PasswordHash _parsePasswordHash(String value) {
    final parts = value.split(r'$');
    if (parts.length != 5 ||
        parts[0] != 'argon2id' ||
        parts[1] != 'v=19' ||
        parts[2] !=
            'm=$_argonMemory,t=$_argonIterations,p=$_argonParallelism') {
      throw const FormatException('Unsupported password hash');
    }
    final salt = _decodeBytes(parts[3]);
    final hash = _decodeBytes(parts[4]);
    if (salt.length != _saltLength || hash.length != _argonHashLength) {
      throw const FormatException('Invalid password hash length');
    }
    return _PasswordHash(salt: salt, hash: hash);
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _writeTail.then((_) => action());
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  DateTime _now() => _clock().toUtc();

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));

  String _randomId(String prefix) =>
      '$prefix${_randomBytes(18).map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';

  static String _sessionToken(String id, List<int> secret) =>
      'hfs.$id.${_encodeBytes(secret)}';

  static String normalizeHumanEmail(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.length > 320 ||
        !RegExp(r'^[^@\s]{1,254}@[^@\s]{1,254}$').hasMatch(normalized)) {
      _invalidCredentials();
    }
    return normalized;
  }

  static void _validatePassword(String password) {
    if (password.length < 12 || password.length > 1024) {
      _invalidCredentials();
    }
  }

  static Never _invalidCredentials() => throw const ControlPlaneException(
    'INVALID_CREDENTIALS',
    'Email or password is invalid',
    statusCode: 401,
  );

  static Never _emailAlreadyRegistered() => throw const ControlPlaneException(
    'EMAIL_ALREADY_REGISTERED',
    'An account with this email already exists',
    statusCode: 409,
  );

  static String _encodeJson(Map<String, Object?> value) =>
      _encodeBytes(utf8.encode(canonicalJson(value)));

  static String _encodeBytes(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _decodeBytes(String value) {
    if (value.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const FormatException('Invalid base64url');
    }
    final padded = '$value${'=' * ((4 - value.length % 4) % 4)}';
    final bytes = base64Url.decode(padded);
    if (_encodeBytes(bytes) != value)
      throw const FormatException('Invalid base64url');
    return bytes;
  }

  static Map<String, Object?> _decodeJson(String value) {
    final decoded = jsonDecode(
      utf8.decode(_decodeBytes(value), allowMalformed: false),
    );
    if (decoded is! Map) throw const FormatException('JWT object expected');
    return <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static bool _constantTimeEqual(Object left, Object right) {
    final leftBytes = left is String ? utf8.encode(left) : left as List<int>;
    final rightBytes = right is String
        ? utf8.encode(right)
        : right as List<int>;
    var difference = leftBytes.length ^ rightBytes.length;
    final length = max(leftBytes.length, rightBytes.length);
    for (var index = 0; index < length; index++) {
      final leftValue = index < leftBytes.length ? leftBytes[index] : 0;
      final rightValue = index < rightBytes.length ? rightBytes[index] : 0;
      difference |= leftValue ^ rightValue;
    }
    return difference == 0;
  }

  static bool _safeTokenPart(String value) =>
      value.isNotEmpty &&
      value.length <= 256 &&
      !value.contains(RegExp(r'[\r\n]'));

  static bool _sameMembershipScope(
    HumanMembership left,
    HumanMembership right,
  ) =>
      left.organizationId == right.organizationId &&
      left.applicationId == right.applicationId &&
      left.environmentId == right.environmentId &&
      left.profileApplicationId == right.profileApplicationId &&
      left.profileEnvironmentId == right.profileEnvironmentId &&
      left.role == right.role &&
      left.profileName == right.profileName;

  Never _unauthorized() => throw const ControlPlaneException(
    'UNAUTHORIZED',
    'Authentication is invalid',
    statusCode: 401,
  );
}

final class AuthJwt {
  const AuthJwt._();

  static bool isJwtLike(String value) => value.split('.').length == 3;
}

final class _AuthorizationCodeRecord {
  const _AuthorizationCodeRecord({
    required this.clientId,
    required this.redirectUri,
    required this.codeChallenge,
    required this.codeChallengeMethod,
    required this.userId,
    required this.createdAt,
    required this.expiresAt,
  });

  final String clientId;
  final String redirectUri;
  final String codeChallenge;
  final String codeChallengeMethod;
  final String userId;
  final DateTime createdAt;
  final DateTime expiresAt;
}

final class _PasswordHash {
  const _PasswordHash({required this.salt, required this.hash});

  final List<int> salt;
  final List<int> hash;
}

final class _JwtClaims {
  const _JwtClaims({
    required this.subject,
    required this.sessionId,
    required this.expiration,
  });

  final String subject;
  final String sessionId;
  final DateTime expiration;
}

final class _IssuedAccessToken {
  const _IssuedAccessToken({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;
}

final class _AccessContext {
  const _AccessContext({
    required this.user,
    required this.session,
    required this.expiresAt,
  });

  final HumanUserRecord user;
  final HumanSessionRecord session;
  final DateTime expiresAt;
}
