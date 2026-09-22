import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'diagnostics.dart';
import 'profile.dart';

/// Secret material returned by the human-session API.
///
/// This type is intentionally kept separate from [Profile] and [CliProfile].
/// Do not include it in command output, profile metadata, or project config.
final class AuthSession {
  const AuthSession({
    required this.accessToken,
    String? sessionToken,
    String? refreshToken,
    this.expiresAt,
    this.sessionExpiresAt,
  }) : sessionToken = sessionToken ?? refreshToken;

  final String accessToken;
  final String? sessionToken;
  String? get refreshToken => sessionToken;
  final DateTime? expiresAt;
  final DateTime? sessionExpiresAt;

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc());
  bool get isSessionExpired =>
      sessionExpiresAt != null &&
      !sessionExpiresAt!.isAfter(DateTime.now().toUtc());

  Map<String, Object?> toJson() => <String, Object?>{
    'accessToken': accessToken,
    if (sessionToken != null) 'sessionToken': sessionToken,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    if (sessionExpiresAt != null)
      'sessionExpiresAt': sessionExpiresAt!.toUtc().toIso8601String(),
  };

  factory AuthSession.fromJson(Map<String, Object?> json) {
    final accessToken = _requiredString(json, const <String>[
      'accessToken',
      'access_token',
      'token',
    ], field: 'access token');
    final sessionToken = _optionalString(json, const <String>[
      'sessionToken',
      'session_token',
      'refreshToken',
      'refresh_token',
    ], field: 'session token');
    final expiresAt = _optionalDateTime(json, const <String>[
      'expiresAt',
      'expires_at',
    ]);
    final sessionExpiresAt = _optionalDateTime(json, const <String>[
      'sessionExpiresAt',
      'session_expires_at',
    ]);
    _validateSecret(accessToken, 'access token');
    if (sessionToken != null) _validateSecret(sessionToken, 'session token');
    return AuthSession(
      accessToken: accessToken,
      sessionToken: sessionToken,
      expiresAt: expiresAt,
      sessionExpiresAt: sessionExpiresAt,
    );
  }
}

/// Stores one endpoint-bound auth session outside the metadata files.
///
/// Implementations must treat [endpointKey] as lookup metadata and [value] as
/// secret material. The value must not be placed in process arguments or
/// diagnostic output.
abstract interface class AuthCredentialStore {
  Future<String?> read(String endpointKey);

  Future<void> write(String endpointKey, String value);

  Future<void> delete(String endpointKey);
}

/// Signals that the native credential store is unavailable for this process.
///
/// [AuthStorage] catches this exception and uses its permission-locked file
/// fallback. The exception intentionally carries no platform output or secret.
final class AuthCredentialStoreUnavailable implements Exception {
  const AuthCredentialStoreUnavailable();
}

/// Protection policy used by the portable file-backed auth store.
enum AuthStoragePlatform {
  /// POSIX permissions enforced with `chmod` (macOS and Linux).
  posix,

  /// A non-inherited, current-account ACL enforced with `icacls` (Windows).
  windows,
}

/// Process runner used to apply the platform's auth-storage permissions.
///
/// The injection point keeps the Windows ACL path deterministic in focused
/// tests without requiring a Windows host in every test environment.
typedef AuthStorageProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Protection policy selected for the current host.
AuthStoragePlatform get defaultAuthStoragePlatform => Platform.isWindows
    ? AuthStoragePlatform.windows
    : AuthStoragePlatform.posix;

/// Auth storage that prefers a platform-native adapter when available.
///
/// The OSS default uses macOS Keychain through `security`, Linux Secret
/// Service through `secret-tool`, or Windows Credential Manager through Win32.
/// Missing utilities, unavailable services, and native failures fall back to
/// the permission-locked file store. An injected adapter, when present,
/// contains one session value per normalized API base. Profile metadata and
/// credentials intentionally use separate stores. The catalog is non-secret.
/// [credentialsFile] is the permission-locked fallback, keyed by the same
/// endpoint values. The legacy profile/session files remain readable so
/// existing local users and release/deploy tests migrate safely. Once a native
/// store fails, endpoint-bound sessions are written only to [credentialsFile];
/// the legacy session projection remains a read-only migration path.
class AuthStorage {
  AuthStorage({
    Directory? root,
    String? rootPath,
    Map<String, String>? environment,
    AuthStoragePlatform? platform,
    AuthStorageProcessRunner? processRunner,
    AuthCredentialStore? credentialStore,
    bool? useNativeCredentialStore,
  }) : root = _resolveRoot(
         root: root,
         rootPath: rootPath,
         environment: environment ?? Platform.environment,
       ),
       platform = platform ?? defaultAuthStoragePlatform,
       _processRunner = processRunner ?? _runAuthStorageProcess,
       _environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       ) {
    final preferNative =
        useNativeCredentialStore ??
        (root == null && rootPath == null && environment == null);
    _credentialStore =
        credentialStore ??
        (preferNative ? _defaultAuthCredentialStore() : null);
  }

  final Directory root;

  /// The permission policy used for this storage instance.
  final AuthStoragePlatform platform;

  final AuthStorageProcessRunner _processRunner;
  final Map<String, String> _environment;
  AuthCredentialStore? _credentialStore;
  bool _nativeCredentialStoreUnavailable = false;

  /// Whether this instance is configured to try an OS credential store.
  ///
  /// A configured native store can still be unavailable at runtime, for
  /// example when a Linux Secret Service session is not running. In that case
  /// this value becomes false after the first failed native operation.
  bool get prefersNativeCredentialStore => _credentialStore != null;

  /// Legacy identity projection retained for compatibility.
  File get profileFile => File(p.join(root.path, 'profile.json'));

  /// Legacy active-session projection retained for compatibility.
  File get sessionFile => File(p.join(root.path, 'session.json'));

  /// The canonical non-secret named-profile catalog.
  File get profilesFile => File(p.join(root.path, 'profiles.json'));

  /// Canonical host-bound credential store.
  ///
  /// This file is used only by the portable fallback or for legacy data.
  File get credentialsFile => File(p.join(root.path, 'credentials'));

  // Non-secret authority markers prevent an unavailable native store from
  // resurrecting an older login after fallback or logout in another process.
  File get _credentialAuthorityFile =>
      File(p.join(root.path, 'credential-authority.json'));

  Future<Map<String, Object?>> _credentialAuthorities() async =>
      await _readJson(_credentialAuthorityFile, code: 'A1003') ?? {};

  Future<void> _setCredentialAuthority(Uri endpoint, String authority) async {
    final authorities = await _credentialAuthorities();
    authorities[controlPlaneEndpointKey(endpoint)] = authority;
    await _writeJson(_credentialAuthorityFile, authorities, code: 'A1006');
  }

  Future<ProfileCatalog> readProfileCatalog() async {
    final json = await _readJson(profilesFile, code: 'A1022');
    if (json != null) {
      try {
        return ProfileCatalog.fromJson(json);
      } on Object catch (error) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'A1023',
          summary: 'Stored profile catalog is malformed',
          detail: error is FormatException ? error.message : '$error',
          action: 'Run hyfens profile remove or hyfens login to replace it.',
        );
      }
    }

    // A pre-profile-version install has one identity profile. Convert only
    // its non-secret endpoint/scope metadata into the named catalog.
    final legacy = await _readLegacyProfile();
    if (legacy == null) return ProfileCatalog();
    final endpoint = validateControlPlaneEndpoint(
      legacy.endpoint,
      operation: 'stored profile',
    );
    // A legacy ProfileScope name identifies a membership, not a control-plane
    // endpoint. Give migrated endpoint metadata a stable public profile name.
    final name = defaultHyfensProfileName;
    final profile = CliProfile(
      name: name,
      endpoint: endpoint,
      managed: false,
      organizationId: legacy.organizationId,
      applicationId: legacy.applicationId,
      environmentId: legacy.environmentId,
    );
    return ProfileCatalog(activeProfile: name, profiles: <CliProfile>[profile]);
  }

  Future<CliProfile?> readNamedProfile(String name) async {
    return (await readProfileCatalog()).byName(name);
  }

  Future<CliProfile> readActiveProfile() async =>
      (await readProfileCatalog()).active;

  Future<void> writeNamedProfile(
    CliProfile profile, {
    bool makeActive = true,
  }) async {
    final catalog = await readProfileCatalog();
    final profiles = <CliProfile>[profile];
    profiles.addAll(
      catalog.profiles.where((item) => item.name != profile.name),
    );
    await _writeJson(
      profilesFile,
      ProfileCatalog(
        activeProfile: makeActive ? profile.name : catalog.activeProfile,
        profiles: profiles,
      ).toJson(),
      code: 'A1024',
    );
  }

  Future<void> useProfile(String name) async {
    final catalog = await readProfileCatalog();
    if (catalog.byName(name) == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'A1025',
        summary: 'Profile does not exist',
        detail: name,
        action:
            'Run hyfens profile list or hyfens login --profile $name --host <URL>.',
      );
    }
    await _writeJson(
      profilesFile,
      catalog.copyWith(activeProfile: name).toJson(),
      code: 'A1026',
    );
  }

  Future<void> removeNamedProfile(String name) async {
    final catalog = await readProfileCatalog();
    final profile = catalog.byName(name);
    if (profile == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'A1025',
        summary: 'Profile does not exist',
        detail: name,
        action: 'Run hyfens profile list to see available profiles.',
      );
    }
    final legacy = await _readLegacyProfile();
    final remaining = catalog.profiles.where((item) => item.name != name);
    final remainingProfiles = remaining.toList(growable: false)
      ..sort((left, right) => left.name.compareTo(right.name));
    final active = catalog.activeProfile == name
        ? (remainingProfiles.isEmpty ? null : remainingProfiles.first.name)
        : catalog.activeProfile;
    final endpointStillUsed = remainingProfiles.any(
      (item) =>
          controlPlaneEndpointKey(item.endpoint) ==
          controlPlaneEndpointKey(profile.endpoint),
    );
    // Keep endpoint-bound credentials while another named profile still uses
    // the same control plane. This matters for multiple scopes on one host.
    if (!endpointStillUsed) {
      await clearSession(endpoint: profile.endpoint);
      if (legacy != null &&
          controlPlaneEndpointKey(legacy.endpoint) ==
              controlPlaneEndpointKey(profile.endpoint)) {
        await clearProfile();
      }
    }
    await _writeJson(
      profilesFile,
      ProfileCatalog(
        activeProfile: active,
        profiles: remainingProfiles,
      ).toJson(),
      code: 'A1027',
    );
  }

  /// Reads the legacy identity projection. A named profile can be selected
  /// for callers that only need the non-secret endpoint/scope view.
  Future<Profile?> readProfile({String? name}) async {
    final catalog = await readProfileCatalog();
    final selected = name == null
        ? (catalog.profiles.isEmpty ? null : catalog.active)
        : catalog.byName(name);
    if (selected != null) {
      final legacy = await _readLegacyProfile();
      final legacyForEndpoint =
          legacy != null &&
              controlPlaneEndpointKey(legacy.endpoint) ==
                  controlPlaneEndpointKey(selected.endpoint)
          ? legacy
          : null;
      // Keep the legacy identity projection for compatibility when it is
      // already bound to the selected endpoint and scope. A different named
      // profile on the same host must not inherit the old profile's scope.
      if (legacyForEndpoint != null &&
          _legacyIdentityMatchesNamedProfile(legacyForEndpoint, selected)) {
        return legacyForEndpoint;
      }
      final scope = selected.toScope();
      return Profile(
        endpoint: selected.endpoint,
        userId: legacyForEndpoint?.userId,
        email: legacyForEndpoint?.email,
        displayName: legacyForEndpoint?.displayName,
        profiles: scope == null
            ? const <ProfileScope>[]
            : <ProfileScope>[scope],
        organizationName: legacyForEndpoint?.organizationName,
      );
    }
    if (name != null) return null;
    return await _readLegacyProfile();
  }

  bool _legacyIdentityMatchesNamedProfile(Profile legacy, CliProfile selected) {
    final selectedScope = selected.toScope();
    if (selectedScope == null) return legacy.profiles.isEmpty;
    if (legacy.profiles.length != 1) return false;
    final legacyScope = legacy.profiles.single;
    return legacyScope.organizationId == selectedScope.organizationId &&
        legacyScope.applicationId == selectedScope.applicationId &&
        legacyScope.environmentId == selectedScope.environmentId;
  }

  Future<AuthSession?> readSession({Uri? endpoint}) async {
    final target = endpoint == null
        ? await _sessionEndpoint()
        : validateControlPlaneEndpoint(
            endpoint,
            operation: 'credential lookup',
          );
    if (target != null) {
      final authority =
          (await _credentialAuthorities())[controlPlaneEndpointKey(target)];
      if (authority == 'cleared') return null;
      if (authority != null && authority != 'native' && authority != 'file') {
        throw const FormatException('Invalid credential authority');
      }
      if (authority != 'file') {
        final nativeValue = await _readNativeValue(target);
        if (nativeValue != null) return _decodeSessionText(nativeValue);
        if (authority == 'native') return null;
      }
    }
    final credentials = await _readCredentials();
    if (target != null) {
      final encoded = credentials[controlPlaneEndpointKey(target)];
      if (encoded != null) return _decodeSession(encoded);
      // A legacy session file predates endpoint-keyed storage and has no
      // binding metadata. Keep it readable for the existing migration path;
      // every canonical credential entry remains keyed and explicit endpoint
      // reads below still reject a different host.
      final legacyProfile = await _readLegacyProfile();
      if (legacyProfile == null ||
          controlPlaneEndpointKey(legacyProfile.endpoint) !=
              controlPlaneEndpointKey(target)) {
        return null;
      }
    }
    if (!sessionFile.existsSync()) return null;
    final json = await _readJson(sessionFile, code: 'A1003');
    return json == null ? null : _decodeSession(json);
  }

  Future<void> writeProfile(Profile profile) =>
      _writeJson(profileFile, profile.toJson(), code: 'A1005');

  Future<void> writeSession(AuthSession session, {Uri? endpoint}) async {
    if (endpoint == null) {
      // Resolve the active profile when possible so the default storage still
      // keeps a caller that omits the optional endpoint in the native store.
      final target = await _sessionEndpoint();
      if (target != null &&
          (_credentialStore != null || _nativeCredentialStoreUnavailable)) {
        await writeSession(session, endpoint: target);
        return;
      }
      // No endpoint means this is an old compatibility projection. It cannot
      // be safely placed in a host-bound native entry.
      await _writeJson(sessionFile, session.toJson(), code: 'A1006');
      return;
    }
    final target = validateControlPlaneEndpoint(
      endpoint,
      operation: 'credential storage',
    );
    final encoded = jsonEncode(session.toJson());
    // Incomplete replacement must fail closed rather than select an older
    // account from either backend on the next process invocation.
    await _setCredentialAuthority(target, 'cleared');
    final nativeStore = _credentialStore;
    if (nativeStore != null) {
      try {
        await nativeStore.write(controlPlaneEndpointKey(target), encoded);
        await _removeFileCredential(target);
        await _setCredentialAuthority(target, 'native');
        return;
      } on AuthCredentialStoreUnavailable {
        _credentialStore = null;
        _nativeCredentialStoreUnavailable = true;
      }
    }
    await _writeFileSession(session, target);
    await _setCredentialAuthority(target, 'file');
  }

  Future<void> clearProfile() => _delete(profileFile);

  Future<void> clearSession({Uri? endpoint}) async {
    if (endpoint == null) {
      final endpoints = await _storedCredentialEndpoints();
      for (final target in endpoints) {
        await _setCredentialAuthority(target, 'cleared');
        await _deleteNativeValue(target);
      }
      await _delete(credentialsFile);
      await _delete(sessionFile);
      return;
    }
    final target = validateControlPlaneEndpoint(
      endpoint,
      operation: 'credential removal',
    );
    await _setCredentialAuthority(target, 'cleared');
    await _deleteNativeValue(target);
    await _removeFileCredential(target);
  }

  Future<void> _writeFileSession(AuthSession session, Uri endpoint) async {
    final credentials = await _readCredentials();
    credentials[controlPlaneEndpointKey(endpoint)] = session.toJson();
    await _writeJson(credentialsFile, credentials, code: 'A1006');
    if (_nativeCredentialStoreUnavailable) {
      await _removeLegacySessionProjection(endpoint);
      return;
    }
    // Keep the old projection for scripts that only inspect the active
    // session file when this instance is explicitly using the portable file
    // store. A native-store failure must not create a second secret copy.
    await _writeJson(sessionFile, session.toJson(), code: 'A1006');
  }

  Future<void> _removeFileCredential(Uri endpoint) async {
    final key = controlPlaneEndpointKey(endpoint);
    final credentials = await _readCredentials();
    credentials.remove(key);
    if (credentials.isEmpty) {
      await _delete(credentialsFile);
    } else {
      await _writeJson(credentialsFile, credentials, code: 'A1007');
    }
    await _removeLegacySessionProjection(endpoint);
  }

  Future<void> _removeLegacySessionProjection(Uri endpoint) async {
    // The compatibility projection has no endpoint field. Remove it only when
    // it belongs to the targeted endpoint; otherwise removing an inactive
    // profile would log out the active legacy projection as a side effect.
    final key = controlPlaneEndpointKey(endpoint);
    final legacyProfile = await _readLegacyProfile();
    if (legacyProfile == null ||
        controlPlaneEndpointKey(legacyProfile.endpoint) == key) {
      await _delete(sessionFile);
    }
  }

  Future<void> clear() async {
    await clearSession();
    await clearProfile();
  }

  Future<Profile?> _readLegacyProfile() async {
    final json = await _readJson(profileFile, code: 'A1001');
    if (json == null) return null;
    try {
      return Profile.fromJson(json);
    } on FormatException {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'A1002',
        summary: 'Stored auth profile is malformed',
        detail: profileFile.path,
        action: 'Run hyfens login to replace the local profile.',
      );
    }
  }

  Future<Uri?> _sessionEndpoint() async {
    final catalog = await readProfileCatalog();
    if (catalog.profiles.isNotEmpty) return catalog.active.endpoint;
    final profile = await _readLegacyProfile();
    return profile?.endpoint;
  }

  Future<List<Uri>> _storedCredentialEndpoints() async {
    final values = <String, Uri>{};
    for (final key in (await _credentialAuthorities()).keys) {
      values[key] = validateControlPlaneEndpoint(
        Uri.parse(key),
        operation: 'credential removal',
      );
    }
    final catalog = await readProfileCatalog();
    for (final profile in catalog.profiles) {
      values[controlPlaneEndpointKey(profile.endpoint)] = profile.endpoint;
    }
    final legacy = await _readLegacyProfile();
    if (legacy != null) {
      values[controlPlaneEndpointKey(legacy.endpoint)] = legacy.endpoint;
    }
    return values.values.toList(growable: false);
  }

  Future<String?> _readNativeValue(Uri endpoint) async {
    final store = _credentialStore;
    if (store == null) return null;
    try {
      return await store.read(controlPlaneEndpointKey(endpoint));
    } on AuthCredentialStoreUnavailable {
      _credentialStore = null;
      _nativeCredentialStoreUnavailable = true;
      return null;
    }
  }

  Future<void> _deleteNativeValue(Uri endpoint) async {
    final store = _credentialStore;
    if (store == null) return;
    try {
      await store.delete(controlPlaneEndpointKey(endpoint));
    } on AuthCredentialStoreUnavailable {
      _credentialStore = null;
      _nativeCredentialStoreUnavailable = true;
    }
  }

  Future<Map<String, Map<String, Object?>>> _readCredentials() async {
    final json = await _readJson(credentialsFile, code: 'A1003');
    if (json == null) return <String, Map<String, Object?>>{};
    final result = <String, Map<String, Object?>>{};
    for (final entry in json.entries) {
      if (entry.value is! Map) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'A1004',
          summary: 'Stored auth credentials are malformed',
          detail: credentialsFile.path,
          action: 'Run hyfens login to replace the local credentials.',
        );
      }
      result[entry.key] = _mapStringKeys(entry.value! as Map);
    }
    return result;
  }

  Future<Map<String, Object?>?> _readJson(File file, {required String code}) =>
      _readJsonFile(
        file,
        code: code,
        platform: platform,
        processRunner: _processRunner,
        environment: _environment,
      );

  Future<void> _writeJson(
    File file,
    Map<String, Object?> value, {
    required String code,
  }) => _writeJsonFile(
    file,
    value,
    code: code,
    platform: platform,
    processRunner: _processRunner,
    environment: _environment,
  );

  AuthSession _decodeSession(Map<String, Object?> json, {String? detail}) {
    try {
      return AuthSession.fromJson(json);
    } on FormatException {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'A1004',
        summary: 'Stored auth session is malformed',
        detail: detail ?? sessionFile.path,
        action: 'Run hyfens login to replace the local session.',
      );
    }
  }

  AuthSession _decodeSessionText(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) throw const FormatException('Expected an object');
      return _decodeSession(
        _mapStringKeys(decoded),
        detail: 'native credential store',
      );
    } on ToolFailure {
      rethrow;
    } on FormatException {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'A1004',
        summary: 'Stored auth session is malformed',
        detail: 'native credential store',
        action: 'Run hyfens login to replace the local session.',
      );
    }
  }
}

/// Explicit name for callers that want to document the portable file store.
final class FileAuthStorage extends AuthStorage {
  FileAuthStorage({
    super.root,
    super.rootPath,
    super.environment,
    super.platform,
    super.processRunner,
  }) : super(useNativeCredentialStore: false);
}

/// Native credential-store adapter used by the default [AuthStorage].
///
/// macOS delegates to the `security` Keychain utility, Linux delegates to the
/// Secret Service through `secret-tool`, and Windows calls Credential Manager
/// through Win32. Secret values are passed through stdin or native memory, and
/// never through a process argument.
final class NativeAuthCredentialStore implements AuthCredentialStore {
  static const _macOsService = 'org.hyfens.cli.auth.v1';
  static const _linuxApplication = 'org.hyfens.cli';
  static const _linuxLabel = 'Hyfens CLI session';

  _WindowsCredentialStore? _windows;

  @override
  Future<String?> read(String endpointKey) async {
    _validateNativeEndpointKey(endpointKey);
    if (Platform.isMacOS) return _readMacOs(endpointKey);
    if (Platform.isLinux) return _readLinux(endpointKey);
    if (Platform.isWindows) {
      try {
        return _windowsStore().read(_windowsTarget(endpointKey));
      } on AuthCredentialStoreUnavailable {
        rethrow;
      } on Object {
        throw const AuthCredentialStoreUnavailable();
      }
    }
    throw const AuthCredentialStoreUnavailable();
  }

  @override
  Future<void> write(String endpointKey, String value) async {
    _validateNativeEndpointKey(endpointKey);
    if (Platform.isMacOS) {
      await _writeMacOs(endpointKey, value);
      return;
    }
    if (Platform.isLinux) {
      await _writeLinux(endpointKey, value);
      return;
    }
    if (Platform.isWindows) {
      try {
        _windowsStore().write(_windowsTarget(endpointKey), value);
        return;
      } on AuthCredentialStoreUnavailable {
        rethrow;
      } on Object {
        throw const AuthCredentialStoreUnavailable();
      }
    }
    throw const AuthCredentialStoreUnavailable();
  }

  @override
  Future<void> delete(String endpointKey) async {
    _validateNativeEndpointKey(endpointKey);
    if (Platform.isMacOS) {
      await _deleteMacOs(endpointKey);
      return;
    }
    if (Platform.isLinux) {
      await _deleteLinux(endpointKey);
      return;
    }
    if (Platform.isWindows) {
      try {
        _windowsStore().delete(_windowsTarget(endpointKey));
        return;
      } on AuthCredentialStoreUnavailable {
        rethrow;
      } on Object {
        throw const AuthCredentialStoreUnavailable();
      }
    }
    throw const AuthCredentialStoreUnavailable();
  }

  Future<String?> _readMacOs(String endpointKey) async {
    final result = await _runNativeCredentialCommand('security', <String>[
      'find-generic-password',
      '-a',
      endpointKey,
      '-s',
      _macOsService,
      '-w',
    ]);
    if (result.exitCode != 0) return null;
    return _stripTrailingLineBreak(result.stdout);
  }

  Future<void> _writeMacOs(String endpointKey, String value) async {
    // Interactive command mode reads a complete command from stdin. A bare
    // trailing -w instead invokes getpass on the terminal, not this pipe.
    // Hex keeps secret bytes out of command parsing; nothing secret is argv.
    final command = <String>[
      'add-generic-password',
      '-a',
      '"${endpointKey.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"',
      '-s',
      '"$_macOsService"',
      '-U',
      '-X',
      utf8
          .encode(value)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(),
    ].join(' ');
    // Apple's interactive parser has a 4096-byte line buffer. Refuse to
    // truncate a credential; larger sessions use the permission-locked file.
    if (utf8.encode(command).length >= 4095) {
      throw const AuthCredentialStoreUnavailable();
    }
    final result = await _runNativeCredentialCommand(
      '/usr/bin/security',
      <String>['-i'],
      input: command,
    );
    if (result.exitCode != 0) {
      throw const AuthCredentialStoreUnavailable();
    }
  }

  Future<void> _deleteMacOs(String endpointKey) async {
    final result = await _runNativeCredentialCommand('security', <String>[
      'delete-generic-password',
      '-a',
      endpointKey,
      '-s',
      _macOsService,
    ]);
    if (result.exitCode != 0) {
      throw const AuthCredentialStoreUnavailable();
    }
  }

  Future<String?> _readLinux(String endpointKey) async {
    final result = await _runNativeCredentialCommand('secret-tool', <String>[
      'lookup',
      'application',
      _linuxApplication,
      'endpoint',
      endpointKey,
    ]);
    if (result.exitCode != 0) return null;
    return _stripTrailingLineBreak(result.stdout);
  }

  Future<void> _writeLinux(String endpointKey, String value) async {
    final result = await _runNativeCredentialCommand('secret-tool', <String>[
      'store',
      '--label=$_linuxLabel',
      'application',
      _linuxApplication,
      'endpoint',
      endpointKey,
    ], input: value);
    if (result.exitCode != 0) {
      throw const AuthCredentialStoreUnavailable();
    }
  }

  Future<void> _deleteLinux(String endpointKey) async {
    final result = await _runNativeCredentialCommand('secret-tool', <String>[
      'clear',
      'application',
      _linuxApplication,
      'endpoint',
      endpointKey,
    ]);
    if (result.exitCode != 0) {
      throw const AuthCredentialStoreUnavailable();
    }
  }

  _WindowsCredentialStore _windowsStore() {
    try {
      return _windows ??= _WindowsCredentialStore();
    } on AuthCredentialStoreUnavailable {
      rethrow;
    } on Object {
      throw const AuthCredentialStoreUnavailable();
    }
  }

  String _windowsTarget(String endpointKey) =>
      'Hyfens CLI auth v1/$endpointKey';
}

/// Returns the native adapter only for the supported desktop operating systems.
///
/// Runtime availability is still best-effort: Linux needs a usable Secret
/// Service session and `secret-tool`, while the macOS and Windows adapters need
/// their respective host APIs. [AuthStorage] falls back when an adapter fails.
AuthCredentialStore? _defaultAuthCredentialStore() {
  if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    return NativeAuthCredentialStore();
  }
  return null;
}

void _validateNativeEndpointKey(String endpointKey) {
  if (endpointKey.isEmpty || endpointKey.contains(RegExp(r'[\u0000\r\n]'))) {
    throw ArgumentError.value(endpointKey, 'endpointKey');
  }
}

Future<_NativeCredentialCommandResult> _runNativeCredentialCommand(
  String executable,
  List<String> arguments, {
  String? input,
}) async {
  late final Process process;
  try {
    process = await Process.start(executable, arguments, runInShell: false);
  } on ProcessException {
    throw const AuthCredentialStoreUnavailable();
  }
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  try {
    if (input != null) process.stdin.write('$input\n');
    await process.stdin.close();
  } on Object {
    process.kill();
    throw const AuthCredentialStoreUnavailable();
  }
  try {
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        process.kill();
        throw const AuthCredentialStoreUnavailable();
      },
    );
    final output = await stdout;
    await stderr;
    return _NativeCredentialCommandResult(exitCode: exitCode, stdout: output);
  } on Object {
    throw const AuthCredentialStoreUnavailable();
  }
}

String _stripTrailingLineBreak(String value) {
  if (value.endsWith('\r\n')) return value.substring(0, value.length - 2);
  if (value.endsWith('\n')) return value.substring(0, value.length - 1);
  return value;
}

final class _NativeCredentialCommandResult {
  const _NativeCredentialCommandResult({
    required this.exitCode,
    required this.stdout,
  });

  final int exitCode;
  final String stdout;
}

final class _WindowsCredentialStore {
  _WindowsCredentialStore()
    : _advapi = DynamicLibrary.open('Advapi32.dll'),
      _kernel32 = DynamicLibrary.open('Kernel32.dll');

  final DynamicLibrary _advapi;
  final DynamicLibrary _kernel32;

  late final _CredReadDart _credRead = _advapi
      .lookupFunction<_CredReadNative, _CredReadDart>('CredReadW');
  late final _CredWriteDart _credWrite = _advapi
      .lookupFunction<_CredWriteNative, _CredWriteDart>('CredWriteW');
  late final _CredDeleteDart _credDelete = _advapi
      .lookupFunction<_CredDeleteNative, _CredDeleteDart>('CredDeleteW');
  late final _CredFreeDart _credFree = _advapi
      .lookupFunction<_CredFreeNative, _CredFreeDart>('CredFree');
  late final _LocalAllocDart _localAlloc = _kernel32
      .lookupFunction<_LocalAllocNative, _LocalAllocDart>('LocalAlloc');
  late final _LocalFreeDart _localFree = _kernel32
      .lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
  late final _GetLastErrorDart _getLastError = _kernel32
      .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

  String? read(String targetName) {
    final target = _utf16(targetName);
    final result = _allocate(sizeOf<Pointer<_WindowsCredential>>())
        .cast<Pointer<_WindowsCredential>>();
    Pointer<_WindowsCredential>? credential;
    try {
      final success = _credRead(target, _windowsGenericCredential, 0, result);
      if (success == 0) {
        if (_getLastError() == _windowsCredentialNotFound) return null;
        throw const AuthCredentialStoreUnavailable();
      }
      credential = result.value;
      if (credential.address == 0) {
        throw const AuthCredentialStoreUnavailable();
      }
      final blobSize = credential.ref.credentialBlobSize;
      final blob = credential.ref.credentialBlob;
      if (blobSize == 0) return '';
      if (blob.address == 0) {
        throw const AuthCredentialStoreUnavailable();
      }
      final bytes = List<int>.generate(
        blobSize,
        (index) => (blob + index).value,
        growable: false,
      );
      try {
        return utf8.decode(bytes);
      } on FormatException {
        throw const AuthCredentialStoreUnavailable();
      }
    } finally {
      if (credential != null && credential.address != 0) {
        _credFree(credential.cast<Void>());
      }
      _localFree(target.cast<Void>());
      _localFree(result.cast<Void>());
    }
  }

  void write(String targetName, String value) {
    final target = _utf16(targetName);
    final username = _utf16('hyfens');
    final bytes = utf8.encode(value);
    final credential = _allocate(sizeOf<_WindowsCredential>());
    final blob = bytes.isEmpty
        ? Pointer<Uint8>.fromAddress(0)
        : _allocate(bytes.length).cast<Uint8>();
    try {
      for (var index = 0; index < bytes.length; index++) {
        (blob + index).value = bytes[index];
      }
      final valuePointer = credential.cast<_WindowsCredential>().ref
        ..flags = 0
        ..type = _windowsGenericCredential
        ..targetName = target
        ..comment = Pointer<Uint16>.fromAddress(0)
        ..credentialBlobSize = bytes.length
        ..credentialBlob = blob
        ..persist = _windowsPersistLocalMachine
        ..attributeCount = 0
        ..attributes = Pointer<Void>.fromAddress(0)
        ..targetAlias = Pointer<Uint16>.fromAddress(0)
        ..userName = username;
      valuePointer.lastWritten.lowDateTime = 0;
      valuePointer.lastWritten.highDateTime = 0;
      if (_credWrite(credential.cast<_WindowsCredential>(), 0) == 0) {
        throw const AuthCredentialStoreUnavailable();
      }
    } finally {
      _localFree(target.cast<Void>());
      _localFree(username.cast<Void>());
      _localFree(credential.cast<Void>());
      if (blob.address != 0) _localFree(blob.cast<Void>());
    }
  }

  void delete(String targetName) {
    final target = _utf16(targetName);
    try {
      if (_credDelete(target, _windowsGenericCredential, 0) == 0 &&
          _getLastError() != _windowsCredentialNotFound) {
        throw const AuthCredentialStoreUnavailable();
      }
    } finally {
      _localFree(target.cast<Void>());
    }
  }

  Pointer<Uint16> _utf16(String value) {
    final units = value.codeUnits;
    final pointer = _allocate((units.length + 1) * sizeOf<Uint16>())
        .cast<Uint16>();
    for (var index = 0; index < units.length; index++) {
      (pointer + index).value = units[index];
    }
    (pointer + units.length).value = 0;
    return pointer;
  }

  Pointer<Void> _allocate(int bytes) {
    final pointer = _localAlloc(0, bytes);
    if (pointer.address == 0) {
      throw const AuthCredentialStoreUnavailable();
    }
    return pointer;
  }
}

const _windowsGenericCredential = 1;
const _windowsPersistLocalMachine = 2;
const _windowsCredentialNotFound = 1168;

final class _WindowsFileTime extends Struct {
  @Uint32()
  external int lowDateTime;

  @Uint32()
  external int highDateTime;
}

final class _WindowsCredential extends Struct {
  @Uint32()
  external int flags;

  @Uint32()
  external int type;

  external Pointer<Uint16> targetName;
  external Pointer<Uint16> comment;
  external _WindowsFileTime lastWritten;

  @Uint32()
  external int credentialBlobSize;

  external Pointer<Uint8> credentialBlob;

  @Uint32()
  external int persist;

  @Uint32()
  external int attributeCount;

  external Pointer<Void> attributes;
  external Pointer<Uint16> targetAlias;
  external Pointer<Uint16> userName;
}

typedef _CredReadNative = Int32 Function(
  Pointer<Uint16> targetName,
  Uint32 type,
  Uint32 flags,
  Pointer<Pointer<_WindowsCredential>> credential,
);
typedef _CredReadDart = int Function(
  Pointer<Uint16> targetName,
  int type,
  int flags,
  Pointer<Pointer<_WindowsCredential>> credential,
);
typedef _CredWriteNative = Int32 Function(
  Pointer<_WindowsCredential> credential,
  Uint32 flags,
);
typedef _CredWriteDart = int Function(
  Pointer<_WindowsCredential> credential,
  int flags,
);
typedef _CredDeleteNative = Int32 Function(
  Pointer<Uint16> targetName,
  Uint32 type,
  Uint32 flags,
);
typedef _CredDeleteDart = int Function(
  Pointer<Uint16> targetName,
  int type,
  int flags,
);
typedef _CredFreeNative = Void Function(Pointer<Void> buffer);
typedef _CredFreeDart = void Function(Pointer<Void> buffer);
typedef _LocalAllocNative = Pointer<Void> Function(Uint32 flags, IntPtr bytes);
typedef _LocalAllocDart = Pointer<Void> Function(int flags, int bytes);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> pointer);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> pointer);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

Directory defaultAuthStorageRoot({Map<String, String>? environment}) =>
    _resolveRoot(environment: environment ?? Platform.environment);

Directory _resolveRoot({
  Directory? root,
  String? rootPath,
  required Map<String, String> environment,
}) {
  if (root != null && rootPath != null) {
    throw ArgumentError('Provide either root or rootPath, not both.');
  }
  if (rootPath != null) {
    if (rootPath.isEmpty) throw ArgumentError.value(rootPath, 'rootPath');
    return Directory(rootPath).absolute;
  }
  if (root != null) return Directory(root.path).absolute;

  final override = _firstEnvironment(environment, const <String>[
    'HYFENS_AUTH_DIR',
    'HYFENS_CONFIG_DIR',
  ]);
  if (override != null) return Directory(override).absolute;

  final home = environment['HOME'] ?? environment['USERPROFILE'];
  if (home == null || home.isEmpty) {
    return Directory(p.join(Directory.current.path, '.hyfens-auth')).absolute;
  }
  return Directory(p.join(home, '.hyfens')).absolute;
}

String? _firstEnvironment(Map<String, String> environment, List<String> keys) {
  for (final key in keys) {
    final value = environment[key];
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

Future<Map<String, Object?>?> _readJsonFile(
  File file, {
  required String code,
  required AuthStoragePlatform platform,
  required AuthStorageProcessRunner processRunner,
  required Map<String, String> environment,
}) async {
  if (!file.existsSync()) return null;
  await _restrict(
    file.parent,
    code: code,
    directory: true,
    platform: platform,
    processRunner: processRunner,
    environment: environment,
  );
  await _restrict(
    file,
    code: code,
    platform: platform,
    processRunner: processRunner,
    environment: environment,
  );
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) throw const FormatException('Expected an object');
    return _mapStringKeys(decoded);
  } on ToolFailure {
    rethrow;
  } on Object {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: code,
      summary: 'Stored auth data is unreadable',
      detail: file.path,
      action: 'Run hyfens login to replace the local auth data.',
    );
  }
}

Future<void> _writeJsonFile(
  File file,
  Map<String, Object?> value, {
  required String code,
  required AuthStoragePlatform platform,
  required AuthStorageProcessRunner processRunner,
  required Map<String, String> environment,
}) async {
  try {
    await file.parent.create(recursive: true);
    await _restrict(
      file.parent,
      code: code,
      directory: true,
      platform: platform,
      processRunner: processRunner,
      environment: environment,
    );
    final temporary = File(
      '${file.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString('${jsonEncode(value)}\n', flush: true);
      await _restrict(
        temporary,
        code: code,
        platform: platform,
        processRunner: processRunner,
        environment: environment,
      );
      await temporary.rename(file.path);
      await _restrict(
        file,
        code: code,
        platform: platform,
        processRunner: processRunner,
        environment: environment,
      );
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  } on ToolFailure {
    rethrow;
  } on Object {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: code,
      summary: 'Auth data could not be stored securely',
      detail: file.path,
      action: 'Check the local auth directory and its permissions.',
    );
  }
}

Future<void> _delete(File file) async {
  if (!file.existsSync()) return;
  try {
    await file.delete();
  } on Object {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'A1007',
      summary: 'Stored auth data could not be removed',
      detail: file.path,
    );
  }
}

Future<void> _restrict(
  FileSystemEntity entity, {
  required String code,
  bool directory = false,
  required AuthStoragePlatform platform,
  required AuthStorageProcessRunner processRunner,
  required Map<String, String> environment,
}) async {
  late final String executable;
  late final List<String> arguments;
  switch (platform) {
    case AuthStoragePlatform.posix:
      executable = 'chmod';
      arguments = <String>[directory ? '700' : '600', entity.path];
    case AuthStoragePlatform.windows:
      final principal = _windowsPrincipal(environment);
      if (principal == null) {
        throw _permissionFailure(entity, code);
      }
      executable = 'icacls';
      final permission = directory ? '(OI)(CI)F' : 'F';
      arguments = <String>[
        entity.path,
        '/reset',
        '/inheritance:r',
        '/grant:r',
        '$principal:$permission',
      ];
  }

  ProcessResult result;
  try {
    result = await processRunner(executable, arguments);
  } on Object {
    throw _permissionFailure(entity, code);
  }
  if (result.exitCode != 0) {
    throw _permissionFailure(entity, code);
  }
}

Future<ProcessResult> _runAuthStorageProcess(
  String executable,
  List<String> arguments,
) => Process.run(executable, arguments);

String? _windowsPrincipal(Map<String, String> environment) {
  final username = environment['USERNAME']?.trim();
  if (username == null || username.isEmpty) return null;
  final domain = environment['USERDOMAIN']?.trim();
  return domain == null || domain.isEmpty ? username : '$domain\\$username';
}

ToolFailure _permissionFailure(FileSystemEntity entity, String code) =>
    ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: code,
      summary: 'Auth storage permissions could not be restricted',
      detail: entity.path,
      action: 'Use a local auth directory writable only by the current user.',
    );

Map<String, Object?> _mapStringKeys(Map value) => <String, Object?>{
  for (final entry in value.entries)
    if (entry.key is String) entry.key! as String: entry.value,
};

String _requiredString(
  Map<String, Object?> json,
  List<String> keys, {
  required String field,
}) {
  final value = _optionalString(json, keys, field: field);
  if (value == null) throw FormatException('Missing $field');
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
    if (value is! String || value.isEmpty) {
      throw FormatException('Invalid $field');
    }
    return value;
  }
  return null;
}

DateTime? _optionalDateTime(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is! String) throw const FormatException('Invalid expiry');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw const FormatException('Invalid expiry');
    return parsed.toUtc();
  }
  return null;
}

void _validateSecret(String value, String field) {
  if (value.trim().isEmpty || value.contains(RegExp(r'[\r\n]'))) {
    throw FormatException('Invalid $field');
  }
}
