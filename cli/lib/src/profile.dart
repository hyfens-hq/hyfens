import 'dart:convert';
import 'dart:io';

import 'diagnostics.dart';

const managedCloudApiBase = 'https://api.hyfens.com/p2/';
const defaultHyfensProfileName = 'hyfens-cloud';
const managedCloudProfileName = defaultHyfensProfileName;

/// Normalize a control-plane API base without dropping its API path.
///
/// The API path is part of the credential boundary: `/p2/` and `/v1/` are
/// different control-plane identities even when they share an origin.
Uri normalizeControlPlaneEndpoint(Uri endpoint) {
  final scheme = endpoint.scheme.toLowerCase();
  final host = endpoint.host.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') ||
      host.isEmpty ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.query.isNotEmpty ||
      endpoint.fragment.isNotEmpty) {
    throw const FormatException(
      'Control-plane endpoint must be an absolute HTTP or HTTPS URL without credentials or query data',
    );
  }
  var path = endpoint.path;
  if (path.isEmpty) path = '/';
  if (!path.endsWith('/')) path = '$path/';
  return endpoint.replace(scheme: scheme, host: host, path: path);
}

/// Returns the exact endpoint origin plus API-base path used for credential
/// lookup. Default ports are omitted so equivalent URLs share one key.
String controlPlaneEndpointKey(Uri endpoint) {
  final normalized = normalizeControlPlaneEndpoint(endpoint);
  final scheme = normalized.scheme.toLowerCase();
  final host = normalized.host.toLowerCase();
  final defaultPort = scheme == 'https' ? 443 : 80;
  final authority = StringBuffer();
  if (host.contains(':')) {
    authority.write('[$host]');
  } else {
    authority.write(host);
  }
  if (normalized.hasPort && normalized.port != defaultPort) {
    authority.write(':${normalized.port}');
  }
  var path = normalized.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return '$scheme://$authority$path';
}

bool isExplicitLoopbackEndpoint(Uri endpoint) {
  final host = endpoint.host.toLowerCase();
  if (host == 'localhost') return true;
  final address = InternetAddress.tryParse(host);
  return address?.isLoopback ?? false;
}

/// Enforce the credential-bearing transport policy at every CLI boundary.
Uri validateControlPlaneEndpoint(Uri endpoint, {String operation = 'request'}) {
  try {
    final normalized = normalizeControlPlaneEndpoint(endpoint);
    if (normalized.scheme == 'http' &&
        !isExplicitLoopbackEndpoint(normalized)) {
      throw const FormatException(
        'Remote control-plane HTTP is not permitted for credential-bearing flows',
      );
    }
    return normalized;
  } on FormatException catch (error) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.usage,
      code: 'A1023',
      summary: 'Control-plane endpoint is invalid for $operation',
      detail: error.message,
      action: 'Use an HTTPS API base; HTTP is allowed only for explicit localhost, 127.0.0.1, or ::1 development.',
    );
  }
}

/// One organization/application/environment profile granted to a human user.
///
/// Profile metadata is safe to display and store separately from bearer and
/// session secrets.
final class ProfileScope {
  const ProfileScope({
    required this.name,
    required this.organizationId,
    this.applicationId,
    this.environmentId,
    required this.role,
  });

  final String name;
  final String organizationId;
  final String? applicationId;
  final String? environmentId;
  final String role;

  factory ProfileScope.fromJson(Map<String, Object?> json) => ProfileScope(
    name: _requiredString(json, const <String>[
      'name',
      'profileName',
      'profile_name',
    ], 'profile name'),
    organizationId: _requiredString(json, const <String>[
      'organizationId',
      'organization_id',
    ], 'organization ID'),
    applicationId: _optionalString(json, const <String>[
      'applicationId',
      'application_id',
    ], 'application ID'),
    environmentId: _optionalString(json, const <String>[
      'environmentId',
      'environment_id',
    ], 'environment ID'),
    role: _requiredString(json, const <String>['role'], 'profile role'),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'organization_id': organizationId,
    'application_id': applicationId,
    'environment_id': environmentId,
    'role': role,
  };
}

typedef AuthProfile = ProfileScope;

/// Non-secret identity and endpoint metadata for the current CLI user.
///
/// Tokens deliberately do not belong to this model or its JSON projection.
final class Profile {
  Profile({
    required this.endpoint,
    this.userId,
    this.email,
    this.displayName,
    List<ProfileScope> profiles = const <ProfileScope>[],
    String? organizationId,
    String? organizationName,
  }) : _organizationId = organizationId,
       _organizationName = organizationName,
       profiles = List.unmodifiable(profiles);

  final Uri endpoint;
  final String? userId;
  final String? email;
  final String? displayName;
  final List<ProfileScope> profiles;
  final String? _organizationId;
  final String? _organizationName;

  String? get id => userId;
  String? get name =>
      displayName ?? (profiles.isEmpty ? null : profiles.first.name);
  String? get organizationId =>
      _organizationId ??
      (profiles.isEmpty ? null : profiles.first.organizationId);
  String? get organizationName => _organizationName;
  List<ProfileScope> get memberships => profiles;
  String? get profileName => profiles.isEmpty ? null : profiles.first.name;
  bool? get managed =>
      endpoint.scheme == 'https' &&
      controlPlaneEndpointKey(endpoint) ==
          controlPlaneEndpointKey(Uri.parse(managedCloudApiBase));
  String? get applicationId =>
      profiles.isEmpty ? null : profiles.first.applicationId;
  String? get environmentId =>
      profiles.isEmpty ? null : profiles.first.environmentId;

  factory Profile.fromJson(Map<String, Object?> json, {Uri? endpoint}) {
    final configuredEndpoint = endpoint ?? _endpoint(json);
    if (configuredEndpoint == null) {
      throw const FormatException('Profile endpoint is missing');
    }
    final rawProfiles = json['profiles'];
    final profiles = <ProfileScope>[];
    if (rawProfiles != null) {
      if (rawProfiles is! List || rawProfiles.any((item) => item is! Map)) {
        throw const FormatException('Profile scopes are invalid');
      }
      for (final item in rawProfiles) {
        profiles.add(
          ProfileScope.fromJson(<String, Object?>{
            for (final entry in (item! as Map).entries)
              if (entry.key is String) entry.key! as String: entry.value,
          }),
        );
      }
    }
    final organizationId = _optionalString(json, const <String>[
      'organizationId',
      'organization_id',
    ], 'organization ID');
    final organizationName = _optionalString(json, const <String>[
      'organizationName',
      'organization_name',
    ], 'organization name');
    if (profiles.isEmpty && organizationId != null) {
      profiles.add(
        ProfileScope(
          name:
              _optionalString(json, const <String>[
                'displayName',
                'display_name',
                'name',
              ], 'profile name') ??
              'default',
          organizationId: organizationId,
          role:
              _optionalString(json, const <String>['role'], 'profile role') ??
              'unknown',
        ),
      );
    }
    return Profile(
      endpoint: configuredEndpoint,
      userId: _optionalString(json, const <String>[
        'userId',
        'user_id',
        'id',
      ], 'user ID'),
      email: _optionalString(json, const <String>['email', 'mail'], 'email'),
      displayName: _optionalString(json, const <String>[
        'displayName',
        'display_name',
      ], 'display name'),
      profiles: List.unmodifiable(profiles),
      organizationId: organizationId,
      organizationName: organizationName,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'endpoint': endpoint.toString(),
    if (userId != null) 'user_id': userId,
    if (email != null) 'email': email,
    if (displayName != null) 'display_name': displayName,
    'profiles': profiles.map((item) => item.toJson()).toList(growable: false),
    if (_organizationId != null) 'organization_id': _organizationId,
    if (_organizationName != null) 'organization_name': _organizationName,
  };

  String encode() => jsonEncode(toJson());
}

/// The durable, non-secret selection for one control plane.
final class ControlPlaneProfile {
  ControlPlaneProfile({
    required this.name,
    required Uri endpoint,
    required this.managed,
    this.organizationId,
    this.applicationId,
    this.environmentId,
  }) : endpoint = normalizeControlPlaneEndpoint(endpoint) {
    _validateProfileName(name);
    if (this.endpoint.scheme == 'http' &&
        !isExplicitLoopbackEndpoint(this.endpoint)) {
      throw ArgumentError(
        'Remote HTTP profile endpoints are not permitted for credential-bearing use',
      );
    }
    _validateProfileIdentifier(organizationId, 'organization');
    _validateProfileIdentifier(applicationId, 'application');
    _validateProfileIdentifier(environmentId, 'environment');
  }

  final String name;
  final Uri endpoint;
  final bool managed;
  final String? organizationId;
  final String? applicationId;
  final String? environmentId;

  String get organization => organizationId ?? '';
  String get application => applicationId ?? '';
  String get environment => environmentId ?? '';

  Map<String, Object?> toMetadataJson() => <String, Object?>{
    'endpoint': endpoint.toString(),
    'managed': managed,
    if (organizationId != null) 'organization': organizationId,
    if (applicationId != null) 'application': applicationId,
    if (environmentId != null) 'environment': environmentId,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    ...toMetadataJson(),
  };

  ProfileScope? toScope({String role = 'unknown'}) {
    final organization = organizationId;
    if (organization == null) return null;
    return ProfileScope(
      name: name,
      organizationId: organization,
      applicationId: applicationId,
      environmentId: environmentId,
      role: role,
    );
  }

  Profile toIdentityProfile({String? userId, String? email}) {
    final scope = toScope();
    return Profile(
      endpoint: endpoint,
      userId: userId,
      email: email,
      profiles: scope == null ? const <ProfileScope>[] : <ProfileScope>[scope],
    );
  }

  factory ControlPlaneProfile.fromJson(String name, Map<String, Object?> json) {
    const allowed = <String>{
      'endpoint',
      'managed',
      'organization',
      'application',
      'environment',
      'organization_id',
      'application_id',
      'environment_id',
    };
    final unexpected = json.keys.toSet().difference(allowed);
    if (unexpected.isNotEmpty) {
      throw FormatException(
        'Profile metadata contains unsupported fields: ${unexpected.toList()..sort()}',
      );
    }
    final endpointValue = _stringValue(json['endpoint'], 'profile endpoint');
    final parsedEndpoint = Uri.tryParse(endpointValue);
    if (parsedEndpoint == null) {
      throw const FormatException('Invalid profile endpoint');
    }
    final managedValue = json['managed'];
    if (managedValue is! bool) {
      throw const FormatException('Profile managed flag is invalid');
    }
    return ControlPlaneProfile(
      name: name,
      endpoint: parsedEndpoint,
      managed: managedValue,
      organizationId: _optionalIdentifier(json, const <String>[
        'organization',
        'organization_id',
      ], 'organization'),
      applicationId: _optionalIdentifier(json, const <String>[
        'application',
        'application_id',
      ], 'application'),
      environmentId: _optionalIdentifier(json, const <String>[
        'environment',
        'environment_id',
      ], 'environment'),
    );
  }
}

typedef CliProfile = ControlPlaneProfile;
typedef HyfensProfile = ControlPlaneProfile;
typedef ProfileCatalog = ProfileSet;

/// Collection persisted by [AuthStorage]. It intentionally has no secret
/// fields; credentials are stored under endpoint keys in a separate file.
final class ProfileSet {
  ProfileSet({
    String? activeProfile,
    List<ControlPlaneProfile> profiles = const [],
  }) : activeProfile = activeProfile,
       profiles = List.unmodifiable(profiles) {
    final names = this.profiles.map((profile) => profile.name).toSet();
    if (names.length != this.profiles.length) {
      throw const FormatException('Duplicate profile names');
    }
    if (activeProfile != null && !names.contains(activeProfile)) {
      throw FormatException('Active profile does not exist: $activeProfile');
    }
  }

  final String? activeProfile;
  final List<ControlPlaneProfile> profiles;

  ControlPlaneProfile? get current {
    final name = activeProfile;
    if (name == null) return null;
    for (final profile in profiles) {
      if (profile.name == name) return profile;
    }
    return null;
  }

  /// Returns the selected entry, or a stable fallback when the catalog has no
  /// explicit selection. The managed default is only used for a new,
  /// unconfigured installation; an existing catalog must continue to resolve
  /// to one of its persisted profiles.
  ControlPlaneProfile get active {
    final selected = current;
    if (selected != null) return selected;
    if (profiles.isNotEmpty) {
      return byName(defaultHyfensProfileName) ?? profiles.first;
    }
    return ControlPlaneProfile(
      name: defaultHyfensProfileName,
      endpoint: Uri.parse(managedCloudApiBase),
      managed: true,
    );
  }

  ControlPlaneProfile? byName(String name) {
    for (final profile in profiles) {
      if (profile.name == name) return profile;
    }
    return null;
  }

  ProfileSet upsert(ControlPlaneProfile profile, {bool activate = true}) {
    final next = profiles.where((item) => item.name != profile.name).toList();
    next.add(profile);
    next.sort((left, right) => left.name.compareTo(right.name));
    return ProfileSet(
      activeProfile: activate ? profile.name : activeProfile,
      profiles: next,
    );
  }

  ProfileSet activate(String name) {
    if (byName(name) == null) {
      throw FormatException('Profile does not exist: $name');
    }
    return ProfileSet(activeProfile: name, profiles: profiles);
  }

  ProfileSet remove(String name) {
    final next = profiles.where((item) => item.name != name).toList();
    if (next.length == profiles.length) return this;
    next.sort((left, right) => left.name.compareTo(right.name));
    final nextActive = activeProfile == name
        ? (next.isEmpty ? null : next.first.name)
        : activeProfile;
    return ProfileSet(activeProfile: nextActive, profiles: next);
  }

  ProfileSet copyWith({
    String? activeProfile,
    Iterable<ControlPlaneProfile>? profiles,
  }) => ProfileSet(
    activeProfile: activeProfile ?? this.activeProfile,
    profiles: profiles?.toList(growable: false) ?? this.profiles,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    if (activeProfile != null) 'active_profile': activeProfile,
    'profiles': <String, Object?>{
      for (final profile in profiles) profile.name: profile.toMetadataJson(),
    },
  };

  factory ProfileSet.fromJson(Map<String, Object?> json) {
    final active = _optionalString(json, const <String>[
      'active_profile',
      'activeProfile',
    ], 'active profile');
    final rawProfiles = json['profiles'];
    if (rawProfiles == null) return ProfileSet(activeProfile: active);
    final profiles = <ControlPlaneProfile>[];
    if (rawProfiles is Map) {
      for (final entry in rawProfiles.entries) {
        if (entry.key is! String || entry.value is! Map) {
          throw const FormatException('Profile collection is invalid');
        }
        profiles.add(
          ControlPlaneProfile.fromJson(entry.key as String, <String, Object?>{
            for (final item in (entry.value! as Map).entries)
              if (item.key is String) item.key! as String: item.value,
          }),
        );
      }
    } else if (rawProfiles is List) {
      for (final item in rawProfiles) {
        if (item is! Map)
          throw const FormatException('Profile collection is invalid');
        final values = <String, Object?>{
          for (final entry in item.entries)
            if (entry.key is String) entry.key! as String: entry.value,
        };
        final name = _requiredString(values, const <String>[
          'name',
        ], 'profile name');
        values.remove('name');
        profiles.add(ControlPlaneProfile.fromJson(name, values));
      }
    } else {
      throw const FormatException('Profile collection is invalid');
    }
    profiles.sort((left, right) => left.name.compareTo(right.name));
    final result = ProfileSet(activeProfile: active, profiles: profiles);
    return result;
  }
}

Uri? _endpoint(Map<String, Object?> json) {
  final value = _optionalString(json, const <String>[
    'endpoint',
    'baseUrl',
    'base_url',
  ], 'endpoint');
  if (value == null) return null;
  return Uri.tryParse(value);
}

String _requiredString(
  Map<String, Object?> json,
  List<String> keys,
  String field,
) {
  final value = _optionalString(json, keys, field);
  if (value == null) throw FormatException('Missing $field');
  return value;
}

String? _optionalString(
  Map<String, Object?> json,
  List<String> keys,
  String field,
) {
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

String _stringValue(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Invalid $field');
}

String? _optionalIdentifier(
  Map<String, Object?> json,
  List<String> keys,
  String field,
) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is! String || value.isEmpty) {
      throw FormatException('Invalid $field');
    }
    _validateProfileIdentifier(value, field);
    return value;
  }
  return null;
}

void _validateProfileIdentifier(String? value, String field) {
  if (value == null) return;
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$').hasMatch(value)) {
    throw ArgumentError('$field identifier is invalid');
  }
}

void _validateProfileName(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(value)) {
    throw ArgumentError('Profile name is invalid');
  }
}
