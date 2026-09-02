import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'auth_storage.dart';
import 'diagnostics.dart';
import 'discovery.dart';
import 'profile.dart';

/// The deliberately small human-session HTTP contract used by the CLI.
///
/// These endpoints are intentionally outside the product resource `/v1`
/// paths. The server accepts the exact `session_token` body field for refresh
/// and logout and returns identity metadata at the top level.
abstract final class AuthApiContract {
  static const clientId = 'hyfens-cli';
  static const loginPath = 'auth/login';
  static const refreshPath = 'auth/refresh';
  static const profilePath = 'auth/me';
  static const logoutPath = 'auth/logout';
  static const authorizePath = 'auth/authorize';
  static const tokenPath = 'auth/token';
  static const deviceCodePath = 'auth/device/code';
  static const deviceTokenPath = 'auth/device/token';
}

typedef AuthHttpClientFactory = HttpClient Function(SecurityContext? context);
typedef AuthBrowserLauncher = Future<void> Function(Uri authorizationUri);
typedef AuthSleeper = Future<void> Function(Duration duration);
typedef AuthRandomBytes = List<int> Function(int length);

final class AuthLoginResult {
  const AuthLoginResult({required this.profile, required this.session});

  final Profile profile;
  final AuthSession session;
}

/// Minimal HTTP adapter and local-session coordinator for human CLI auth.
final class AuthClient {
  AuthClient({
    AuthStorage? storage,
    AuthHttpClientFactory? httpClientFactory,
    DiscoveryClient? discoveryClient,
    AuthBrowserLauncher? browserLauncher,
    AuthSleeper? sleeper,
    AuthRandomBytes? randomBytes,
    this.loginPath = AuthApiContract.loginPath,
    this.refreshPath = AuthApiContract.refreshPath,
    this.profilePath = AuthApiContract.profilePath,
    this.logoutPath = AuthApiContract.logoutPath,
  }) : storage = storage ?? AuthStorage(),
       _httpClientFactory =
           httpClientFactory ?? ((context) => HttpClient(context: context)),
       _discoveryClient =
           discoveryClient ??
           DiscoveryClient(httpClientFactory: httpClientFactory),
       _browserLauncher = browserLauncher ?? _launchBrowser,
       _sleeper = sleeper ?? ((duration) => Future<void>.delayed(duration)),
       _randomBytes = randomBytes ?? _secureRandomBytes;

  final AuthStorage storage;
  final AuthHttpClientFactory _httpClientFactory;
  final DiscoveryClient _discoveryClient;
  final AuthBrowserLauncher _browserLauncher;
  final AuthSleeper _sleeper;
  final AuthRandomBytes _randomBytes;
  final String loginPath;
  final String refreshPath;
  final String profilePath;
  final String logoutPath;

  Future<AuthLoginResult> login({
    required Uri endpoint,
    required String email,
    required String password,
    String? profileName,
    String? caCertPath,
    SecurityContext? securityContext,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'A1008',
        summary: 'Login credentials are incomplete',
        detail: 'An email and password are required.',
        action: 'Provide the values interactively and retry.',
      );
    }
    final target = validateControlPlaneEndpoint(endpoint, operation: 'login');
    final response = await _request(
      method: 'POST',
      uri: _authUri(target, loginPath),
      securityContext: securityContext ?? _securityContext(caCertPath),
      body: <String, Object?>{'email': email, 'password': password},
    );
    final payload = _payload(response.body);
    final session = _sessionFromPayload(payload);
    final profile = _hasIdentity(payload)
        ? _profile(payload, endpoint)
        : await fetchProfile(
            endpoint: target,
            accessToken: session.accessToken,
            caCertPath: caCertPath,
            securityContext: securityContext,
          );

    // Write metadata first; a session is never left pointing at a profile
    // from a different endpoint when a login write fails.
    await _persistLogin(
      endpoint: target,
      profile: profile,
      session: session,
      profileName: profileName,
    );
    return AuthLoginResult(profile: profile, session: session);
  }

  /// Runs the public-client Authorization Code + PKCE flow.
  ///
  /// The callback listener accepts exactly one loopback URI and only the
  /// short-lived authorization code/state pair. Session material is exchanged
  /// in the request body and is never placed in a URL.
  Future<AuthLoginResult> loginBrowser({
    required Uri endpoint,
    String? profileName,
    String clientId = AuthApiContract.clientId,
    String? caCertPath,
    SecurityContext? securityContext,
    Duration callbackTimeout = const Duration(minutes: 2),
  }) async {
    final target = validateControlPlaneEndpoint(
      endpoint,
      operation: 'browser login',
    );
    final document = await _discoveryClient.discover(
      target,
      securityContext: securityContext ?? _securityContext(caCertPath),
    );
    if (!document.supportsBrowserPkce) {
      throw _unsupportedAuthMethod(
        method: 'browser PKCE',
        detail: 'The control plane does not advertise authorization_code_pkce_s256.',
      );
    }

    final verifier = _base64Url(_randomBytes(48));
    final challenge = _pkceChallenge(verifier);
    final state = _base64Url(_randomBytes(32));
    final callbackServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final redirectUri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: callbackServer.port,
      path: '/callback',
    );
    final authorizationEndpoint = _credentialUri(
      _advertisedUri(
        target,
        document.authorizationEndpoint,
        AuthApiContract.authorizePath,
      ),
      operation: 'browser authorization',
    );
    final authorizationUri = authorizationEndpoint.replace(
      queryParameters: <String, String>{
        'client_id': clientId,
        'redirect_uri': redirectUri.toString(),
        'response_type': 'code',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      },
    );
    final callback = Completer<_AuthorizationCallback>();
    final subscription = callbackServer.listen((request) async {
      final result = _readAuthorizationCallback(request, redirectUri, state);
      if (result == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.text
          ..write('Invalid authorization callback.');
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.text
        ..write('Hyfens login completed. You may close this window.');
      await request.response.close();
      if (!callback.isCompleted) callback.complete(result);
    });
    try {
      await _browserLauncher(authorizationUri);
      final result = await callback.future.timeout(callbackTimeout);
      final tokenEndpoint = _advertisedUri(
        target,
        document.tokenEndpoint,
        AuthApiContract.tokenPath,
        requireSameAuthority: true,
      );
      final response = await _request(
        method: 'POST',
        uri: _credentialUri(tokenEndpoint, operation: 'browser login'),
        securityContext: securityContext ?? _securityContext(caCertPath),
        body: <String, Object?>{
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'code': result.code,
          'redirect_uri': redirectUri.toString(),
          'code_verifier': verifier,
        },
        unsupportedOnMissing: true,
      );
      final payload = _payload(response.body);
      final session = _sessionFromPayload(payload);
      final profile = _hasIdentity(payload)
          ? _profile(payload, target)
          : await fetchProfile(
              endpoint: target,
              accessToken: session.accessToken,
              caCertPath: caCertPath,
              securityContext: securityContext,
            );
      await _persistLogin(
        endpoint: target,
        profile: profile,
        session: session,
        profileName: profileName,
      );
      return AuthLoginResult(profile: profile, session: session);
    } on TimeoutException {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'A1032',
        summary: 'Browser login timed out before the callback arrived',
        detail: 'The exact loopback redirect was not completed.',
        action: 'Complete login in the browser and retry hyfens login.',
      );
    } finally {
      await subscription.cancel();
      await callbackServer.close(force: true);
    }
  }

  /// Runs the short-lived, single-use device authorization flow advertised by
  /// the control plane. Pending polls never create or persist a session.
  Future<AuthLoginResult> loginDevice({
    required Uri endpoint,
    String? profileName,
    String clientId = AuthApiContract.clientId,
    String? caCertPath,
    SecurityContext? securityContext,
    void Function(DeviceAuthorizationPrompt prompt)? onPrompt,
  }) async {
    final target = validateControlPlaneEndpoint(
      endpoint,
      operation: 'device login',
    );
    final document = await _discoveryClient.discover(
      target,
      securityContext: securityContext ?? _securityContext(caCertPath),
    );
    if (!document.supportsDevice) {
      throw _unsupportedAuthMethod(
        method: 'device authorization',
        detail: 'The control plane does not advertise device_authorization.',
      );
    }
    final issueEndpoint = _advertisedUri(
      target,
      document.deviceAuthorizationEndpoint,
      AuthApiContract.deviceCodePath,
      requireSameAuthority: true,
    );
    final issuedResponse = await _request(
      method: 'POST',
      uri: _credentialUri(issueEndpoint, operation: 'device login'),
      securityContext: securityContext ?? _securityContext(caCertPath),
      body: <String, Object?>{'client_id': clientId},
      unsupportedOnMissing: true,
    );
    final issued = _deviceAuthorization(_payload(issuedResponse.body), target);
    onPrompt?.call(issued);
    final tokenEndpoint = _advertisedUri(
      target,
      document.deviceTokenEndpoint,
      AuthApiContract.deviceTokenPath,
      requireSameAuthority: true,
    );
    final started = DateTime.now().toUtc();
    final expiresAt = started.add(issued.expiresIn);
    var interval = issued.interval;
    if (interval <= Duration.zero) interval = const Duration(seconds: 1);
    while (DateTime.now().toUtc().isBefore(expiresAt)) {
      final response = await _request(
        method: 'POST',
        uri: _credentialUri(tokenEndpoint, operation: 'device login'),
        securityContext: securityContext ?? _securityContext(caCertPath),
        body: <String, Object?>{
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'client_id': clientId,
          'device_code': issued.deviceCode,
        },
        acceptedStatusCodes: const <int>{HttpStatus.badRequest},
        unsupportedOnMissing: true,
      );
      if (response.statusCode == HttpStatus.ok) {
        final payload = _payload(response.body);
        final session = _sessionFromPayload(payload);
        final profile = _hasIdentity(payload)
            ? _profile(payload, target)
            : await fetchProfile(
                endpoint: target,
                accessToken: session.accessToken,
                caCertPath: caCertPath,
                securityContext: securityContext,
              );
        await _persistLogin(
          endpoint: target,
          profile: profile,
          session: session,
          profileName: profileName,
        );
        return AuthLoginResult(profile: profile, session: session);
      }
      final payload = _payload(response.body);
      final status = _deviceError(payload);
      if (status == 'authorization_pending') {
        await _sleeper(interval);
        continue;
      }
      throw _deviceFailure(status);
    }
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'A1035',
      summary: 'Device authorization code expired',
      detail: 'The short-lived device code was not approved in time.',
      action: 'Run hyfens login --device again to issue a new code.',
    );
  }

  Future<AuthSession> refresh({
    Uri? endpoint,
    String? profileName,
    String? caCertPath,
    SecurityContext? securityContext,
  }) async {
    final storedProfile = await storage.readProfile(name: profileName);
    final target = endpoint ?? storedProfile?.endpoint;
    if (target == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'A1009',
        summary: 'No CLI auth profile is available',
        detail: 'The stored session has no bound control-plane endpoint.',
        action: 'Run hyfens login again.',
      );
    }
    final normalizedTarget = validateControlPlaneEndpoint(
      target,
      operation: 'refresh',
    );
    if (endpoint != null && storedProfile != null) {
      _requireMatchingEndpoint(endpoint, storedProfile.endpoint);
    }
    final current = await storage.readSession(endpoint: normalizedTarget);
    if (current == null || current.sessionToken == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'A1009',
        summary: 'No CLI auth session is available',
        detail: 'The stored session cannot be refreshed.',
        action: 'Run hyfens login again.',
      );
    }
    if (current.isSessionExpired) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'A1010',
        summary: 'CLI auth session has expired',
        detail: 'The stored session is no longer valid.',
        action: 'Run hyfens login again.',
      );
    }
    final response = await _request(
      method: 'POST',
      uri: _authUri(normalizedTarget, refreshPath),
      securityContext: securityContext ?? _securityContext(caCertPath),
      body: <String, Object?>{'session_token': current.sessionToken},
    );
    final payload = _payload(response.body);
    final refreshed = AuthSession(
      accessToken: _requiredString(payload, const <String>[
        'access_token',
        'accessToken',
        'token',
      ], field: 'access token'),
      sessionToken: current.sessionToken,
      expiresAt: _expiry(payload),
      sessionExpiresAt: current.sessionExpiresAt,
    );
    _validateToken(refreshed.accessToken, 'access token');
    final refreshedProfile = _hasIdentity(payload)
        ? _profile(payload, storedProfile?.endpoint ?? normalizedTarget)
        : storedProfile;
    final profile = refreshedProfile ?? Profile(endpoint: normalizedTarget);
    if (profileName == null) {
      await storage.writeProfile(profile);
    } else {
      await storage.writeNamedProfile(
        CliProfile(
          name: profileName,
          endpoint: profile.endpoint,
          managed: profile.managed ?? false,
          organizationId: profile.organizationId,
          applicationId: profile.applicationId,
          environmentId: profile.environmentId,
        ),
        makeActive: false,
      );
    }
    await storage.writeSession(refreshed, endpoint: normalizedTarget);
    return refreshed;
  }

  Future<Profile> fetchProfile({
    required Uri endpoint,
    required String accessToken,
    String? caCertPath,
    SecurityContext? securityContext,
  }) async {
    _validateToken(accessToken, 'access token');
    final response = await _request(
      method: 'GET',
      uri: _authUri(endpoint, profilePath),
      securityContext: securityContext ?? _securityContext(caCertPath),
      accessToken: accessToken,
    );
    final payload = _payload(response.body);
    return _profile(payload, endpoint);
  }

  Future<Profile?> status() async {
    final profile = await storage.readProfile();
    if (profile == null) return null;
    final session = await storage.readSession(endpoint: profile.endpoint);
    if (session == null ||
        session.isSessionExpired ||
        session.isExpired && session.sessionToken == null) {
      return null;
    }
    return profile;
  }

  Future<Profile?> readProfile() => storage.readProfile();

  Future<AuthSession?> readSession() => storage.readSession();

  /// Returns a stored, non-expired bearer token for another CLI command.
  ///
  /// An expired access token is refreshed through the stored session token;
  /// the helper is asynchronous so Deploy does not need to know the storage
  /// or refresh protocol.
  Future<String?> accessTokenOrNull({
    Uri? endpoint,
    String? profileName,
  }) async {
    final profile = await storage.readProfile(name: profileName);
    final target = endpoint ?? profile?.endpoint;
    if (target == null) return null;
    if (endpoint != null && profile != null) {
      _requireMatchingEndpoint(endpoint, profile.endpoint);
    }
    final normalizedTarget = validateControlPlaneEndpoint(
      target,
      operation: 'access',
    );
    final session = await storage.readSession(endpoint: normalizedTarget);
    if (session == null || session.isSessionExpired) return null;
    if (!session.isExpired) return session.accessToken;
    if (session.sessionToken == null) return null;
    final refreshed = await refresh(
      endpoint: normalizedTarget,
      profileName: profileName,
    );
    return refreshed.accessToken;
  }

  Future<String?> storedAccessToken({Uri? endpoint}) =>
      accessTokenOrNull(endpoint: endpoint);

  Future<String> requireAccessToken({Uri? endpoint}) async {
    final session = await storage.readSession(endpoint: endpoint);
    if (session == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'A1009',
        summary: 'No CLI auth session is available',
        detail: 'The command requires an authenticated human session.',
        action: 'Run hyfens login first.',
      );
    }
    if (session.isSessionExpired ||
        session.isExpired && session.sessionToken == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'A1010',
        summary: 'CLI auth session has expired',
        detail: 'The stored session is no longer valid.',
        action: 'Run hyfens login again.',
      );
    }
    return (await accessTokenOrNull(endpoint: endpoint)) ??
        (throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'A1010',
          summary: 'CLI auth session has expired',
          detail: 'The stored session is no longer valid.',
          action: 'Run hyfens login again.',
        ));
  }

  Future<void> logout({
    Uri? endpoint,
    String? caCertPath,
    SecurityContext? securityContext,
  }) async {
    final profile = await storage.readProfile();
    if (endpoint != null && profile != null) {
      _requireMatchingEndpoint(endpoint, profile.endpoint);
    }
    final target = endpoint ?? profile?.endpoint;
    final session = target == null
        ? await storage.readSession()
        : await storage.readSession(endpoint: target);
    try {
      if (session?.sessionToken != null && target != null) {
        await _request(
          method: 'POST',
          uri: _authUri(target, logoutPath),
          securityContext: securityContext ?? _securityContext(caCertPath),
          body: <String, Object?>{'session_token': session!.sessionToken},
        );
      }
    } finally {
      // Local logout is unconditional, including when the remote service is
      // unavailable or has already expired the session.
      if (target == null) {
        await storage.clear();
      } else {
        await storage.clearSession(endpoint: target);
        await storage.clearProfile();
      }
    }
  }

  Future<void> _persistLogin({
    required Uri endpoint,
    required Profile profile,
    required AuthSession session,
    String? profileName,
  }) async {
    final name = profileName ?? _defaultProfileName(endpoint);
    final metadata = CliProfile(
      name: name,
      endpoint: endpoint,
      managed:
          controlPlaneEndpointKey(endpoint) ==
          controlPlaneEndpointKey(Uri.parse(managedCloudApiBase)),
      organizationId: profile.organizationId,
      applicationId: profile.applicationId,
      environmentId: profile.environmentId,
    );
    await storage.writeNamedProfile(metadata);
    await storage.writeProfile(profile);
    await storage.writeSession(session, endpoint: endpoint);
  }

  Future<_AuthResponse> _request({
    required String method,
    required Uri uri,
    required SecurityContext? securityContext,
    String? accessToken,
    Map<String, Object?>? body,
    Set<int> acceptedStatusCodes = const <int>{},
    bool unsupportedOnMissing = false,
  }) async {
    final client = _httpClientFactory(securityContext);
    try {
      final request = await client.openUrl(method, uri);
      final bytes = body == null ? null : utf8.encode(jsonEncode(body));
      request.headers.set(
        'X-Request-Id',
        'cli-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (accessToken != null) {
        request.headers.set('Authorization', 'Bearer $accessToken');
      }
      if (bytes != null) {
        request
          ..headers.contentType = ContentType.json
          ..headers.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close();
      final responseBytes = await response.fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      final source = utf8.decode(responseBytes, allowMalformed: false);
      Object? decoded;
      try {
        decoded = source.isEmpty ? <String, Object?>{} : jsonDecode(source);
      } on Object {
        if (unsupportedOnMissing &&
            (response.statusCode == HttpStatus.notFound ||
                response.statusCode == HttpStatus.methodNotAllowed)) {
          throw _unsupportedAuthMethod(
            method: 'CLI authentication',
            detail: 'The advertised authentication endpoint is not available.',
          );
        }
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'A1011',
          summary: 'Auth service response is not valid JSON',
          detail: 'HTTP ${response.statusCode}',
        );
      }
      if ((response.statusCode < 200 || response.statusCode >= 300) &&
          !acceptedStatusCodes.contains(response.statusCode)) {
        if (unsupportedOnMissing &&
            (response.statusCode == HttpStatus.notFound ||
                response.statusCode == HttpStatus.methodNotAllowed)) {
          throw _unsupportedAuthMethod(
            method: 'CLI authentication',
            detail: 'The advertised authentication endpoint is not available.',
          );
        }
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: response.statusCode == HttpStatus.unauthorized
              ? 'A1012'
              : 'A1013',
          summary: 'Auth service request was rejected',
          detail: 'HTTP ${response.statusCode}',
          action: 'Check the endpoint and try again.',
        );
      }
      return _AuthResponse(decoded, response.statusCode);
    } on ToolFailure {
      rethrow;
    } on Object catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'A1014',
        summary: 'Auth service request failed',
        detail: error.runtimeType.toString(),
        action: 'Check the endpoint, credentials, and local TLS configuration.',
      );
    } finally {
      client.close(force: true);
    }
  }

  void _requireMatchingEndpoint(Uri target, Uri stored) {
    if (controlPlaneEndpointKey(target) == controlPlaneEndpointKey(stored)) {
      return;
    }
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'A1020',
      summary: 'Stored auth session is bound to a different endpoint',
      detail: 'The requested endpoint does not match the stored auth profile endpoint.',
      action: 'Use the stored profile endpoint or run hyfens login for the target endpoint.',
    );
  }
}

final class DeviceAuthorizationPrompt {
  const DeviceAuthorizationPrompt({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  /// Secret used only in the polling request body. Never display or persist it.
  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final Duration expiresIn;
  final Duration interval;
}

final class _AuthorizationCallback {
  const _AuthorizationCallback({required this.code});

  final String code;
}

final class _AuthResponse {
  const _AuthResponse(this.body, this.statusCode);

  final Object? body;
  final int statusCode;
}

Uri _authUri(Uri endpoint, String path) {
  final target = validateControlPlaneEndpoint(endpoint, operation: 'auth');
  return _credentialUri(target.resolve(path), operation: 'auth');
}

Map<String, Object?> _payload(Object? body) {
  if (body is! Map) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'A1016',
      summary: 'Auth service response is malformed',
      detail: 'Expected a JSON object.',
    );
  }
  final root = <String, Object?>{
    for (final entry in body.entries)
      if (entry.key is String) entry.key! as String: entry.value,
  };
  final data = _firstMap(root, const <String>['data']);
  return data ?? root;
}

Map<String, Object?>? _firstMap(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key! as String: entry.value,
      };
    }
  }
  return null;
}

bool _hasIdentity(Map<String, Object?> json) =>
    json.containsKey('user_id') ||
    json.containsKey('userId') ||
    json.containsKey('profiles');

AuthSession _sessionFromPayload(Map<String, Object?> payload) {
  final accessToken = _requiredString(payload, const <String>[
    'access_token',
    'accessToken',
    'token',
  ], field: 'access token');
  final sessionToken = _requiredString(payload, const <String>[
    'session_token',
    'sessionToken',
  ], field: 'session token');
  _validateToken(accessToken, 'access token');
  _validateToken(sessionToken, 'session token');
  return AuthSession(
    accessToken: accessToken,
    sessionToken: sessionToken,
    expiresAt: _expiry(payload),
    sessionExpiresAt: _sessionExpiry(payload),
  );
}

DateTime? _sessionExpiry(Map<String, Object?> json) {
  final value = json['session_expires_at'] ?? json['sessionExpiresAt'];
  if (value == null) return null;
  if (value is! String) _malformed('session expiry');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) _malformed('session expiry');
  return parsed.toUtc();
}

DateTime? _expiry(Map<String, Object?> json) {
  final value = json['expires_at'] ?? json['expiresAt'];
  if (value == null) return null;
  if (value is! String) _malformed('access expiry');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) _malformed('access expiry');
  return parsed.toUtc();
}

Profile _profile(Map<String, Object?> json, Uri endpoint) {
  try {
    return Profile.fromJson(json, endpoint: endpoint);
  } on FormatException {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'A1016',
      summary: 'Auth service profile is malformed',
      detail: 'The response did not contain valid profile metadata.',
    );
  }
}

String _requiredString(
  Map<String, Object?> json,
  List<String> keys, {
  required String field,
}) {
  final value = _optionalString(json, keys, field: field);
  if (value == null) _malformed(field);
  return value;
}

String? _optionalString(
  Map<String, Object?> json,
  List<String> keys, {
  required String field,
}) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is! String || value.isEmpty) _malformed(field);
    return value;
  }
  return null;
}

Never _malformed(String field) => throw ToolFailure.single(
  exitCode: ToolExitCode.environment,
  code: 'A1016',
  summary: 'Auth service response is malformed',
  detail: 'Invalid or missing $field.',
);

SecurityContext? _securityContext(String? certificatePath) {
  if (certificatePath == null || certificatePath.isEmpty) return null;
  final file = File(certificatePath);
  if (!file.existsSync()) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'A1017',
      summary: 'Configured TLS CA certificate is missing',
      detail: certificatePath,
      action: 'Provide a readable PEM CA certificate or remove --ca-cert.',
    );
  }
  try {
    final context = SecurityContext(withTrustedRoots: true);
    context.setTrustedCertificates(file.path);
    return context;
  } on Object {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'A1018',
      summary: 'Configured TLS CA certificate is invalid',
      detail: certificatePath,
      action: 'Provide a readable PEM CA certificate.',
    );
  }
}

void _validateToken(String token, String field) {
  if (token.trim().isEmpty || token.contains(RegExp(r'[\r\n]'))) {
    _malformed(field);
  }
}

String _defaultProfileName(Uri endpoint) {
  return controlPlaneEndpointKey(endpoint) ==
          controlPlaneEndpointKey(Uri.parse(managedCloudApiBase))
      ? managedCloudProfileName
      : 'self-hosted';
}

ToolFailure _unsupportedAuthMethod({
  required String method,
  required String detail,
}) => ToolFailure.single(
  exitCode: ToolExitCode.compatibility,
  code: 'A1030',
  summary: '$method is not supported by this control plane',
  detail: detail,
  action: 'Use a control plane that advertises the requested method at /.well-known/hyfens, or use password login where enabled.',
);

Uri _advertisedUri(
  Uri endpoint,
  Uri? advertised,
  String fallback, {
  bool requireSameAuthority = false,
}) {
  final candidate = advertised == null
      ? endpoint.resolve(fallback)
      : advertised.isAbsolute
      ? advertised
      : endpoint.resolve(advertised.toString());
  if (candidate.host.isEmpty || candidate.userInfo.isNotEmpty) {
    throw _unsupportedAuthMethod(
      method: 'CLI authentication',
      detail:
          'The discovery document contains an invalid authentication endpoint.',
    );
  }
  if ((candidate.scheme != 'http' && candidate.scheme != 'https') ||
      (candidate.scheme == 'http' && !isExplicitLoopbackEndpoint(candidate))) {
    throw _unsupportedAuthMethod(
      method: 'CLI authentication',
      detail: 'The discovery document contains an authentication endpoint that is not HTTPS or explicit loopback HTTP.',
    );
  }
  if (requireSameAuthority &&
      (candidate.scheme.toLowerCase() != endpoint.scheme.toLowerCase() ||
          candidate.host.toLowerCase() != endpoint.host.toLowerCase() ||
          _effectivePort(candidate) != _effectivePort(endpoint))) {
    throw _unsupportedAuthMethod(
      method: 'CLI authentication',
      detail: 'The discovery document points a credential exchange at another host.',
    );
  }
  if (candidate.query.isNotEmpty || candidate.fragment.isNotEmpty) {
    throw _unsupportedAuthMethod(
      method: 'CLI authentication',
      detail: 'The discovery document contains credential-bearing endpoint data in a URL.',
    );
  }
  return candidate;
}

Uri _credentialUri(Uri uri, {required String operation}) {
  try {
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException(
        'Auth URL must be an absolute URL without credentials or query data',
      );
    }
    if (uri.scheme == 'http' && !isExplicitLoopbackEndpoint(uri)) {
      throw const FormatException('Remote HTTP is not permitted');
    }
    return uri;
  } on FormatException catch (error) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.usage,
      code: 'A1015',
      summary: 'Auth endpoint is invalid for $operation',
      detail: error.message,
      action: 'Use an HTTPS control plane; HTTP is allowed only for explicit loopback development.',
    );
  }
}

_AuthorizationCallback? _readAuthorizationCallback(
  HttpRequest request,
  Uri redirectUri,
  String expectedState,
) {
  if (request.method != 'GET' || request.uri.path != redirectUri.path) {
    return null;
  }
  final query = request.uri.queryParametersAll;
  if (query.length != 2 ||
      query['code']?.length != 1 ||
      query['state']?.length != 1) {
    return null;
  }
  if (query['state']!.single != expectedState) return null;
  final code = query['code']!.single;
  if (code.isEmpty || code.contains(RegExp(r'[\r\n]'))) return null;
  return _AuthorizationCallback(code: code);
}

DeviceAuthorizationPrompt _deviceAuthorization(
  Map<String, Object?> payload,
  Uri endpoint,
) {
  final deviceCode = _requiredString(payload, const <String>[
    'device_code',
    'deviceCode',
  ], field: 'device code');
  final userCode = _requiredString(payload, const <String>[
    'user_code',
    'userCode',
  ], field: 'user code');
  _validateToken(deviceCode, 'device code');
  _validateToken(userCode, 'user code');
  final verificationValue = _requiredString(payload, const <String>[
    'verification_uri',
    'verificationUri',
  ], field: 'verification URL');
  final parsedVerification = Uri.tryParse(verificationValue);
  if (parsedVerification == null) {
    throw _unsupportedAuthMethod(
      method: 'device authorization',
      detail: 'The control plane returned an invalid verification URL.',
    );
  }
  final verification = _credentialUri(
    _advertisedUri(
      endpoint,
      parsedVerification,
      AuthApiContract.deviceCodePath,
    ),
    operation: 'device verification',
  );
  if (verification.queryParameters.keys.any(
    (key) => <String>{
      'code',
      'device_code',
      'user_code',
      'access_token',
      'session_token',
    }.contains(key.toLowerCase()),
  )) {
    throw _unsupportedAuthMethod(
      method: 'device authorization',
      detail: 'The verification URL contains a credential or device code.',
    );
  }
  final expiresIn = _durationSeconds(
    payload['expires_in'] ?? payload['expiresIn'],
    field: 'device expiry',
    fallback: const Duration(minutes: 10),
  );
  final interval = _durationSeconds(
    payload['interval'],
    field: 'device poll interval',
    fallback: const Duration(seconds: 5),
  );
  return DeviceAuthorizationPrompt(
    deviceCode: deviceCode,
    userCode: userCode,
    verificationUri: verification,
    expiresIn: expiresIn,
    interval: interval,
  );
}

Duration _durationSeconds(
  Object? value, {
  required String field,
  required Duration fallback,
}) {
  if (value == null) return fallback;
  final seconds = value is int ? value : int.tryParse('$value');
  if (seconds == null || seconds <= 0 || seconds > 86400) {
    _malformed(field);
  }
  return Duration(seconds: seconds);
}

String _deviceError(Map<String, Object?> payload) {
  final value = payload['error'] ?? payload['status'];
  if (value is String && value.isNotEmpty) return value;
  if (value is Map) {
    final code = value['code'];
    if (code is String && code.isNotEmpty) return code;
  }
  _malformed('device authorization status');
}

ToolFailure _deviceFailure(String status) {
  final normalized = status.toLowerCase();
  final (String summary, String action) = switch (normalized) {
    'expired_token' => (
      'Device authorization code expired',
      'Run hyfens login --device again to issue a new code.',
    ),
    'invalid_grant' => (
      'Device authorization code was already consumed',
      'Run hyfens login --device again to issue a new code.',
    ),
    'access_denied' => (
      'Device authorization was denied',
      'Approve the new code in the authenticated Hyfens application.',
    ),
    _ => (
      'Device authorization failed',
      'Check the control-plane auth service and run hyfens login --device again.',
    ),
  };
  return ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'A1035',
    summary: summary,
    detail: status,
    action: action,
  );
}

String _pkceChallenge(String verifier) => base64Url
    .encode(sha256.convert(utf8.encode(verifier)).bytes)
    .replaceAll('=', '');

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

int _effectivePort(Uri uri) {
  if (uri.hasPort) return uri.port;
  return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
}

List<int> _secureRandomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(
    length,
    (_) => random.nextInt(256),
    growable: false,
  );
}

Future<void> _launchBrowser(Uri uri) async {
  final executable = Platform.isMacOS
      ? 'open'
      : Platform.isWindows
      ? 'rundll32'
      : 'xdg-open';
  final arguments = Platform.isWindows
      ? <String>['url.dll,FileProtocolHandler', uri.toString()]
      : <String>[uri.toString()];
  try {
    final result = await Process.run(executable, arguments);
    if (result.exitCode == 0) return;
  } on Object {
    // Fall through to the actionable diagnostic below.
  }
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'A1033',
    summary: 'Unable to open the browser for Hyfens login',
    detail: uri.toString(),
    action: 'Open the authorization URL in a browser and retry with a supported desktop environment.',
  );
}
