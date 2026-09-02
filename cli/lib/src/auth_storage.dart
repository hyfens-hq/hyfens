import 'dart:convert';
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

/// File-backed auth storage used when an OS credential store is unavailable.
///
/// Profile metadata and credentials intentionally use separate files. The
/// catalog is non-secret; [credentialsFile] is keyed by normalized API base
/// and contains only session material. The legacy profile/session files remain
/// readable so existing local users and release/deploy tests migrate safely.
class AuthStorage {
  AuthStorage({
    Directory? root,
    String? rootPath,
    Map<String, String>? environment,
  }) : root = _resolveRoot(
         root: root,
         rootPath: rootPath,
         environment: environment ?? Platform.environment,
       );

  final Directory root;

  /// Legacy identity projection retained for compatibility.
  File get profileFile => File(p.join(root.path, 'profile.json'));

  /// Legacy active-session projection retained for compatibility.
  File get sessionFile => File(p.join(root.path, 'session.json'));

  /// The canonical non-secret named-profile catalog.
  File get profilesFile => File(p.join(root.path, 'profiles.json'));

  /// Canonical host-bound credential store.
  File get credentialsFile => File(p.join(root.path, 'credentials'));

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
    final managed =
        controlPlaneEndpointKey(endpoint) ==
        controlPlaneEndpointKey(Uri.parse(managedCloudApiBase));
    // A legacy ProfileScope name identifies a membership, not a control-plane
    // endpoint. Give migrated endpoint metadata a stable public profile name.
    final name = managed ? managedCloudProfileName : 'self-hosted';
    final profile = CliProfile(
      name: name,
      endpoint: endpoint,
      managed: managed,
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
    final target = endpoint ?? await _sessionEndpoint();
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
    // Calls that do not identify an endpoint are the legacy compatibility
    // projection. New auth flows always pass the normalized endpoint so the
    // canonical credential file remains strictly host/API-base bound.
    if (endpoint == null) {
      await _writeJson(sessionFile, session.toJson(), code: 'A1006');
      return;
    }
    final target = validateControlPlaneEndpoint(
      endpoint,
      operation: 'credential storage',
    );
    final credentials = await _readCredentials();
    credentials[controlPlaneEndpointKey(target)] = session.toJson();
    await _writeJson(credentialsFile, credentials, code: 'A1006');
    // Keep the old projection for scripts that only inspect the active
    // session file. Reads use the keyed store whenever it exists.
    await _writeJson(sessionFile, session.toJson(), code: 'A1006');
  }

  Future<void> clearProfile() => _delete(profileFile);

  Future<void> clearSession({Uri? endpoint}) async {
    if (endpoint == null) {
      await _delete(credentialsFile);
      await _delete(sessionFile);
      return;
    }
    final credentials = await _readCredentials();
    credentials.remove(controlPlaneEndpointKey(endpoint));
    if (credentials.isEmpty) {
      await _delete(credentialsFile);
    } else {
      await _writeJson(credentialsFile, credentials, code: 'A1007');
    }
    // The compatibility projection has no endpoint field. Remove it only when
    // it belongs to the targeted endpoint; otherwise removing an inactive
    // profile would log out the active legacy projection as a side effect.
    final legacyProfile = await _readLegacyProfile();
    if (legacyProfile == null ||
        controlPlaneEndpointKey(legacyProfile.endpoint) ==
            controlPlaneEndpointKey(endpoint)) {
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

  AuthSession _decodeSession(Map<String, Object?> json) {
    try {
      return AuthSession.fromJson(json);
    } on FormatException {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'A1004',
        summary: 'Stored auth session is malformed',
        detail: sessionFile.path,
        action: 'Run hyfens login to replace the local session.',
      );
    }
  }
}

/// Explicit name for callers that want to document the portable fallback.
final class FileAuthStorage extends AuthStorage {
  FileAuthStorage({super.root, super.rootPath, super.environment});
}

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

Future<Map<String, Object?>?> _readJson(
  File file, {
  required String code,
}) async {
  if (!file.existsSync()) return null;
  await _restrict(file.parent, code: code, directory: true);
  await _restrict(file, code: code);
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

Future<void> _writeJson(
  File file,
  Map<String, Object?> value, {
  required String code,
}) async {
  try {
    await file.parent.create(recursive: true);
    await _restrict(file.parent, code: code, directory: true);
    final temporary = File(
      '${file.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString('${jsonEncode(value)}\n', flush: true);
      await _restrict(temporary, code: code);
      await temporary.rename(file.path);
      await _restrict(file, code: code);
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
}) async {
  if (Platform.isWindows) return;
  final mode = directory ? '700' : '600';
  final result = await Process.run('chmod', <String>[mode, entity.path]);
  if (result.exitCode != 0) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: code,
      summary: 'Auth storage permissions could not be restricted',
      detail: entity.path,
      action: 'Use a local auth directory writable only by the current user.',
    );
  }
}

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
