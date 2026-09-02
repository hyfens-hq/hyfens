import 'dart:io';

import 'human_auth.dart';
import 'reconciliation_periodic.dart';

/// Public, non-secret instance metadata returned by the compatibility
/// discovery endpoint. The API base path is part of the instance identity and
/// is normalized once at configuration time.
final class ControlPlaneDiscoveryConfig {
  const ControlPlaneDiscoveryConfig({
    this.apiBasePath = '/',
    this.product = 'hyfens',
    this.productVersion = '0.1.0',
    this.apiVersion = 'v1',
    this.authorizationEndpoint,
    this.webOrigins = const <String>{},
    this.publicContentOrganizationId,
    this.publicRegistrationOrganizationId,
    this.capabilities = const <String>{
      'signed_releases',
      'bounded_patches',
      'controlled_deployment',
      'verification',
      'rollback',
      'opaque_credentials',
      'scoped_service_credentials',
    },
  });

  final String apiBasePath;
  final String product;
  final String productVersion;
  final String apiVersion;

  /// Optional browser approval page. The API authorization route remains
  /// published separately as `authorization_api_endpoint`.
  final Uri? authorizationEndpoint;

  /// Exact browser origins allowed to call credential-bearing web routes.
  final Set<String> webOrigins;

  /// Organization whose published editorial records are exposed through the
  /// unauthenticated public-content endpoints. A deployment must opt in so
  /// content from another tenant cannot be enumerated accidentally.
  final String? publicContentOrganizationId;

  /// Organization that receives unauthenticated client registrations. A
  /// deployment must opt in explicitly; callers never select this tenant.
  final String? publicRegistrationOrganizationId;
  final Set<String> capabilities;

  factory ControlPlaneDiscoveryConfig.fromEnvironment(
    Map<String, String> values,
  ) {
    final basePath = _normalizeApiBasePath(
      values['HYFENS_API_BASE_PATH'] ?? '/',
    );
    final product = values['HYFENS_DISCOVERY_PRODUCT'] ?? 'hyfens';
    final productVersion =
        values['HYFENS_DISCOVERY_PRODUCT_VERSION'] ?? '0.1.0';
    final apiVersion = values['HYFENS_DISCOVERY_API_VERSION'] ?? 'v1';
    final authorizationEndpoint = _optionalWebUri(
      values['HYFENS_AUTH_AUTHORIZATION_ENDPOINT'],
      'HYFENS_AUTH_AUTHORIZATION_ENDPOINT',
    );
    final webOrigins = _parseWebOrigins(values['HYFENS_WEB_ORIGINS']);
    final publicContentOrganizationId = _parsePublicContentOrganizationId(
      values['HYFENS_PUBLIC_CONTENT_ORGANIZATION_ID'],
    );
    final publicRegistrationOrganizationId =
        _parsePublicRegistrationOrganizationId(
          values['HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID'],
        );
    _boundedDiscoveryText(product, 'HYFENS_DISCOVERY_PRODUCT');
    _boundedDiscoveryText(productVersion, 'HYFENS_DISCOVERY_PRODUCT_VERSION');
    _boundedDiscoveryText(apiVersion, 'HYFENS_DISCOVERY_API_VERSION');
    return ControlPlaneDiscoveryConfig(
      apiBasePath: basePath,
      product: product,
      productVersion: productVersion,
      apiVersion: apiVersion,
      authorizationEndpoint: authorizationEndpoint,
      webOrigins: webOrigins,
      publicContentOrganizationId: publicContentOrganizationId,
      publicRegistrationOrganizationId: publicRegistrationOrganizationId,
    );
  }

  Map<String, Object?> toJson({
    required bool humanAuthConfigured,
    String? deviceVerificationUri,
  }) {
    final authMethods = humanAuthConfigured
        ? const <String>[
            'password_session_v1',
            // This is the established CLI discovery name; the endpoint
            // itself accepts only code_challenge_method=S256.
            'authorization_code_pkce',
            'device_authorization',
            'opaque_token_v1',
          ]
        : const <String>['opaque_token_v1'];
    final publishedCapabilities = <String>{
      ...capabilities,
      if (humanAuthConfigured) 'human_sessions',
    }.toList()..sort();
    return <String, Object?>{
      'schema_version': 1,
      'product': product,
      'product_version': productVersion,
      'api_version': apiVersion,
      'api_base_path': apiBasePath,
      'auth_methods': authMethods,
      'capabilities': publishedCapabilities,
      // The existing credential record/service boundary is authoritative for
      // scoped, expirable, revocable service keys. No separate mutable key
      // registry is invented here.
      'api_key_management': <String, Object?>{
        'supported': true,
        'mode': 'scoped_opaque_credentials',
        'issue_endpoint': _joinApiPath(
          apiBasePath,
          'v1/organizations/{organization_id}/credentials',
        ),
        'revoke_endpoint': _joinApiPath(
          apiBasePath,
          'v1/organizations/{organization_id}/credentials/{credential_id}/revoke',
        ),
      },
      if (humanAuthConfigured) ...<String, Object?>{
        'authorization_endpoint':
            authorizationEndpoint?.toString() ??
            _joinApiPath(apiBasePath, 'auth/authorize'),
        'authorization_api_endpoint': _joinApiPath(
          apiBasePath,
          'auth/authorize',
        ),
        'token_endpoint': _joinApiPath(apiBasePath, 'auth/token'),
        'device_authorization_endpoint': _joinApiPath(
          apiBasePath,
          'auth/device/code',
        ),
        'device_token_endpoint': _joinApiPath(apiBasePath, 'auth/device/token'),
        if (deviceVerificationUri != null)
          'device_verification_uri': _relativeOrAbsoluteUri(
            deviceVerificationUri,
          ),
      },
    };
  }

  String _relativeOrAbsoluteUri(String value) {
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.isAbsolute) return value;
    return _joinApiPath(
      apiBasePath,
      value.startsWith('/') ? value.substring(1) : value,
    );
  }

  static Uri? _optionalWebUri(String? value, String name) {
    if (value == null || value.isEmpty) return null;
    if (value.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ArgumentError('$name contains unsupported characters');
    }
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        !parsed.isAbsolute ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.query.isNotEmpty ||
        parsed.fragment.isNotEmpty ||
        (parsed.scheme != 'https' &&
            !(parsed.scheme == 'http' && _isLoopbackHost(parsed.host)))) {
      throw ArgumentError('$name must be an HTTPS URI or a loopback HTTP URI');
    }
    return parsed;
  }

  static Set<String> _parseWebOrigins(String? value) {
    if (value == null || value.isEmpty) return const <String>{};
    final result = <String>{};
    for (final raw in value.split(',')) {
      final origin = raw.trim();
      if (origin.isEmpty) {
        throw ArgumentError('HYFENS_WEB_ORIGINS contains an empty origin');
      }
      result.add(_normalizeWebOrigin(origin));
    }
    return Set.unmodifiable(result);
  }

  static String? _parsePublicContentOrganizationId(String? value) {
    if (value == null || value.isEmpty) return null;
    if (!RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(value)) {
      throw ArgumentError(
        'HYFENS_PUBLIC_CONTENT_ORGANIZATION_ID contains an invalid organization ID',
      );
    }
    return value;
  }

  static String? _parsePublicRegistrationOrganizationId(String? value) {
    if (value == null || value.isEmpty) return null;
    if (!RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(value)) {
      throw ArgumentError(
        'HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID contains an invalid organization ID',
      );
    }
    return value;
  }

  static String _normalizeWebOrigin(String value) {
    if (value.contains(RegExp(r'[\u0000\r\n\s]'))) {
      throw ArgumentError('HYFENS_WEB_ORIGINS contains unsupported characters');
    }
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        !parsed.isAbsolute ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.query.isNotEmpty ||
        parsed.fragment.isNotEmpty ||
        (parsed.path.isNotEmpty && parsed.path != '/') ||
        (parsed.scheme != 'https' &&
            !(parsed.scheme == 'http' && _isLoopbackHost(parsed.host)))) {
      throw ArgumentError(
        'HYFENS_WEB_ORIGINS must contain HTTPS origins or loopback HTTP origins',
      );
    }
    final scheme = parsed.scheme.toLowerCase();
    final port =
        parsed.hasPort &&
            !((scheme == 'https' && parsed.port == 443) ||
                (scheme == 'http' && parsed.port == 80))
        ? parsed.port
        : null;
    return Uri(
      scheme: scheme,
      host: parsed.host.toLowerCase(),
      port: port,
    ).toString();
  }

  static bool _isLoopbackHost(String host) =>
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '[::1]';

  static String _normalizeApiBasePath(String value) {
    if (value.isEmpty ||
        !value.startsWith('/') ||
        value.contains('?') ||
        value.contains('#') ||
        value.contains(RegExp(r'[\u0000\r\n]'))) {
      throw ArgumentError('HYFENS_API_BASE_PATH must be an absolute path');
    }
    final normalized = value.endsWith('/') ? value : '$value/';
    if (normalized.contains('//')) {
      throw ArgumentError('HYFENS_API_BASE_PATH contains an empty segment');
    }
    return normalized == '//' ? '/' : normalized;
  }

  static void _boundedDiscoveryText(String value, String name) {
    if (value.isEmpty ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
      throw ArgumentError('$name contains unsupported characters');
    }
  }

  static String _joinApiPath(String base, String suffix) =>
      '${base.endsWith('/') ? base : '$base/'}$suffix';
}

/// Environment-injected service configuration. Secrets are never given
/// defaults and are not serialized into health responses or logs.
final class ControlPlaneConfig {
  const ControlPlaneConfig({
    required this.host,
    required this.port,
    required this.fileRoot,
    this.databaseUrl,
    this.artifactEndpoint,
    this.artifactBucket = 'hyfens-artifacts',
    this.artifactAuthorization,
    this.artifactAccessKey,
    this.artifactSecretKey,
    this.artifactUseTaskRole = false,
    this.artifactKeyPrefix = '',
    this.artifactRegion = 'us-east-1',
    this.maxJsonBodyBytes = 256 * 1024,
    this.maxArtifactBytes = 4 * 1024 * 1024,
    this.rateLimitPerMinute = 600,
    this.auditRetentionDays = 365,
    this.reconciliationPeriodic = const ReconciliationPeriodicConfig(),
    this.auth,
    this.allowInsecureAuth = false,
    this.discovery = const ControlPlaneDiscoveryConfig(),
  });

  final String host;
  final int port;
  final Directory fileRoot;
  final String? databaseUrl;
  final Uri? artifactEndpoint;
  final String artifactBucket;
  final String? artifactAuthorization;
  final String? artifactAccessKey;
  final String? artifactSecretKey;
  final bool artifactUseTaskRole;
  final String artifactKeyPrefix;
  final String artifactRegion;
  final int maxJsonBodyBytes;
  final int maxArtifactBytes;
  final int rateLimitPerMinute;
  final int auditRetentionDays;
  final ReconciliationPeriodicConfig reconciliationPeriodic;
  final HumanAuthConfig? auth;

  /// Explicit local-Docker development escape hatch for credential-bearing
  /// HTTP requests. It is disabled by default; remote deployments must use
  /// HTTPS at the public edge.
  final bool allowInsecureAuth;
  final ControlPlaneDiscoveryConfig discovery;

  /// Convenience access to the server-selected public registration tenant.
  String? get publicRegistrationOrganizationId =>
      discovery.publicRegistrationOrganizationId;

  bool get usesPostgres => databaseUrl != null;

  factory ControlPlaneConfig.fromEnvironment([Map<String, String>? values]) {
    final env = values ?? Platform.environment;
    final port = int.tryParse(env['HYFENS_PORT'] ?? '18081');
    final maxJson = int.tryParse(env['HYFENS_MAX_JSON_BYTES'] ?? '262144');
    final maxArtifact = int.tryParse(
      env['HYFENS_MAX_ARTIFACT_BYTES'] ?? '4194304',
    );
    final rate = int.tryParse(env['HYFENS_RATE_LIMIT_PER_MINUTE'] ?? '600');
    final auditRetention = int.tryParse(
      env['HYFENS_AUDIT_RETENTION_DAYS'] ?? '365',
    );
    final allowInsecureAuth = _bool(
      env,
      'HYFENS_AUTH_ALLOW_INSECURE_HTTP',
      false,
    );
    final periodic = ReconciliationPeriodicConfig.fromEnvironment(env);
    final auth = HumanAuthConfig.fromEnvironment(env);
    final discovery = ControlPlaneDiscoveryConfig.fromEnvironment(env);
    if (port == null || port < 1 || port > 65535) {
      throw ArgumentError('HYFENS_PORT must be between 1 and 65535');
    }
    if (maxJson == null ||
        maxJson <= 0 ||
        maxArtifact == null ||
        maxArtifact <= 0) {
      throw ArgumentError('Request limits must be positive integers');
    }
    if (rate == null || rate <= 0) {
      throw ArgumentError('HYFENS_RATE_LIMIT_PER_MINUTE must be positive');
    }
    if (auditRetention == null || auditRetention <= 0) {
      throw ArgumentError('HYFENS_AUDIT_RETENTION_DAYS must be positive');
    }
    var database = env['HYFENS_DATABASE_URL'];
    if (database != null && database.isEmpty) {
      throw ArgumentError('HYFENS_DATABASE_URL must not be empty');
    }
    if (database == null) {
      database = _databaseUrlFromComponents(env);
    }
    final endpointText = env['HYFENS_ARTIFACT_ENDPOINT'];
    final endpoint = endpointText == null || endpointText.isEmpty
        ? null
        : Uri.tryParse(endpointText);
    if (endpointText != null &&
        (endpoint == null ||
            !endpoint.hasScheme ||
            endpoint.host.isEmpty ||
            (endpoint.scheme != 'http' && endpoint.scheme != 'https'))) {
      throw ArgumentError('HYFENS_ARTIFACT_ENDPOINT must be a URI');
    }
    final accessKey = env['HYFENS_ARTIFACT_ACCESS_KEY'];
    final secretKey = env['HYFENS_ARTIFACT_SECRET_KEY'];
    final useTaskRole = _bool(env, 'HYFENS_ARTIFACT_USE_TASK_ROLE', false);
    if ((accessKey == null) != (secretKey == null)) {
      throw ArgumentError(
        'HYFENS_ARTIFACT_ACCESS_KEY and HYFENS_ARTIFACT_SECRET_KEY must be set together',
      );
    }
    if (useTaskRole &&
        (accessKey != null ||
            secretKey != null ||
            env['HYFENS_ARTIFACT_AUTHORIZATION'] != null)) {
      throw ArgumentError(
        'HYFENS_ARTIFACT_USE_TASK_ROLE cannot be combined with static S3 auth',
      );
    }
    if (useTaskRole && endpoint == null) {
      throw ArgumentError(
        'HYFENS_ARTIFACT_USE_TASK_ROLE requires HYFENS_ARTIFACT_ENDPOINT',
      );
    }
    return ControlPlaneConfig(
      host: env['HYFENS_HOST'] ?? '127.0.0.1',
      port: port,
      fileRoot: Directory(env['HYFENS_FILE_ROOT'] ?? '.hyfens-control-plane'),
      databaseUrl: database,
      artifactEndpoint: endpoint,
      artifactBucket: env['HYFENS_ARTIFACT_BUCKET'] ?? 'hyfens-artifacts',
      artifactAuthorization: env['HYFENS_ARTIFACT_AUTHORIZATION'],
      artifactAccessKey: accessKey,
      artifactSecretKey: secretKey,
      artifactUseTaskRole: useTaskRole,
      artifactKeyPrefix: env['HYFENS_ARTIFACT_KEY_PREFIX'] ?? '',
      artifactRegion: env['HYFENS_ARTIFACT_REGION'] ?? 'us-east-1',
      maxJsonBodyBytes: maxJson,
      maxArtifactBytes: maxArtifact,
      rateLimitPerMinute: rate,
      auditRetentionDays: auditRetention,
      reconciliationPeriodic: periodic,
      auth: auth,
      allowInsecureAuth: allowInsecureAuth,
      discovery: discovery,
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

  static String? _databaseUrlFromComponents(Map<String, String> env) {
    final host = env['HYFENS_DATABASE_HOST'];
    final user = env['HYFENS_DATABASE_USER'];
    final password = env['HYFENS_DATABASE_PASSWORD'];
    final anyComponent = host != null || user != null || password != null;
    if (!anyComponent) return null;
    if (host == null ||
        host.isEmpty ||
        user == null ||
        user.isEmpty ||
        password == null ||
        password.isEmpty) {
      throw ArgumentError(
        'HYFENS_DATABASE_HOST, HYFENS_DATABASE_USER, and '
        'HYFENS_DATABASE_PASSWORD must be set together',
      );
    }
    final port = int.tryParse(env['HYFENS_DATABASE_PORT'] ?? '5432');
    if (port == null || port < 1 || port > 65535) {
      throw ArgumentError('HYFENS_DATABASE_PORT must be a valid TCP port');
    }
    final database = env['HYFENS_DATABASE_NAME'] ?? 'hyfens';
    if (!RegExp(r'^[A-Za-z0-9_\-]{1,63}$').hasMatch(database)) {
      throw ArgumentError(
        'HYFENS_DATABASE_NAME contains unsupported characters',
      );
    }
    return Uri(
      scheme: 'postgresql',
      userInfo: '$user:$password',
      host: host,
      port: port,
      path: '/$database',
    ).toString();
  }
}
