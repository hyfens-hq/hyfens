import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'canonical.dart';
import 'diagnostics.dart';

/// The resolved Dart application boundary for one target build.
///
/// A native flavor and its Dart entrypoint are one release boundary. Keeping
/// them together prevents release, patch, and build adapters from selecting
/// different application entrypoints.
final class EntrypointSelection {
  const EntrypointSelection({
    required this.target,
    required this.entrypointPath,
    this.flavor,
  });

  final String target;
  final String entrypointPath;
  final String? flavor;

  Map<String, Object?> toJson() => <String, Object?>{
    'target': target,
    'entrypoint': entrypointPath,
    'flavor': flavor,
  };
}

String normalizeEntrypointPath(String value) {
  final normalizedSeparators = value.trim().replaceAll(r'\', '/');
  final segments = normalizedSeparators.split('/');
  final invalid =
      normalizedSeparators.isEmpty ||
      normalizedSeparators.contains(RegExp(r'[\u0000\r\n]')) ||
      normalizedSeparators.startsWith('/') ||
      normalizedSeparators.startsWith('//') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(normalizedSeparators) ||
      segments.contains('..') ||
      !normalizedSeparators.startsWith('lib/') ||
      !normalizedSeparators.toLowerCase().endsWith('.dart');
  if (invalid) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'T1206',
      summary: 'Invalid Flutter entrypoint path',
      detail: value,
      action:
          'Use a project-relative Dart file under lib/, such as lib/main.dart.',
    );
  }
  final result = p.posix.normalize(normalizedSeparators);
  if (result == '.' || result == '..' || result.startsWith('../')) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'T1206',
      summary: 'Invalid Flutter entrypoint path',
      detail: value,
      action:
          'Use a project-relative Dart file under lib/, such as lib/main.dart.',
    );
  }
  return result;
}

String normalizeFlavorName(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(normalized)) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.usage,
      code: 'T1207',
      summary: 'Invalid Flutter flavor name',
      detail: value,
      action: 'Use the native flavor identifier, for example local, staging, or prod.',
    );
  }
  return normalized;
}

final class ToolConfig {
  const ToolConfig({
    this.version = 1,
    this.include = const <String>['lib/**'],
    this.exclude = const <String>['lib/generated/**'],
    this.includeLocalPackages = true,
    this.includePackages = const <String>[],
    this.applicationId,
    this.entrypoints = const <String, Map<String, String>>{},
    this.applicationIds = const <String, Map<String, String>>{},
    this.publicKeyPath = '.tool/keys/public.key',
    this.privateKeyPath = '.tool/keys/private.key',
    this.updateUrl = 'http://127.0.0.1:18080/v1/patch',
  });

  final int version;
  final List<String> include;
  final List<String> exclude;
  final bool includeLocalPackages;
  final List<String> includePackages;
  final String? applicationId;
  final Map<String, Map<String, String>> entrypoints;
  final Map<String, Map<String, String>> applicationIds;
  final String publicKeyPath;
  final String privateKeyPath;
  final String updateUrl;

  ToolConfig copyWith({
    List<String>? include,
    List<String>? exclude,
    bool? includeLocalPackages,
    List<String>? includePackages,
    String? applicationId,
    Map<String, Map<String, String>>? entrypoints,
    Map<String, Map<String, String>>? applicationIds,
    String? publicKeyPath,
    String? privateKeyPath,
    String? updateUrl,
  }) => ToolConfig(
    version: version,
    include: include ?? this.include,
    exclude: exclude ?? this.exclude,
    includeLocalPackages: includeLocalPackages ?? this.includeLocalPackages,
    includePackages: includePackages ?? this.includePackages,
    applicationId: applicationId ?? this.applicationId,
    entrypoints: entrypoints ?? this.entrypoints,
    applicationIds: applicationIds ?? this.applicationIds,
    publicKeyPath: publicKeyPath ?? this.publicKeyPath,
    privateKeyPath: privateKeyPath ?? this.privateKeyPath,
    updateUrl: updateUrl ?? this.updateUrl,
  );

  static ToolConfig load(File file) {
    if (!file.existsSync()) return const ToolConfig();
    final raw = loadYaml(file.readAsStringSync());
    if (raw is! YamlMap) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1201',
        summary: 'Tool configuration is not a mapping',
        detail: file.path,
        action:
            'Repair tool.yaml or run hyfens init --force after reviewing it.',
      );
    }
    final version = _int(raw['version'], 'version');
    if (version != 1) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'T1202',
        summary: 'Unsupported tool.yaml version',
        detail: 'Found version $version; this CLI supports version 1.',
      );
    }
    final instrumentation = _map(raw['instrumentation'], 'instrumentation');
    final packages = _map(raw['packages'], 'packages');
    final entrypoints = _entrypointMappings(raw['entrypoints']);
    final applicationIds = _applicationIdMappings(raw['application_ids']);
    final signing = _map(raw['signing'], 'signing');
    final runtime = _map(raw['runtime'], 'runtime');
    return ToolConfig(
      version: version,
      include: _strings(instrumentation['include'], const ['lib/**']),
      exclude: _strings(instrumentation['exclude'], const ['lib/generated/**']),
      includeLocalPackages: _bool(
        packages['include_local'],
        defaultValue: true,
      ),
      includePackages: _strings(packages['include'], const <String>[]),
      applicationId: _nullableString(raw['application_id']),
      entrypoints: entrypoints,
      applicationIds: applicationIds,
      publicKeyPath: _string(signing['public_key'], '.tool/keys/public.key'),
      privateKeyPath: _string(signing['private_key'], '.tool/keys/private.key'),
      updateUrl: _url(runtime['update_url'], 'http://127.0.0.1:18080/v1/patch'),
    );
  }

  String encode() {
    final lines = <String>[
      'version: 1',
      '',
      'instrumentation:',
      ..._yamlList('  include:', include),
      ..._yamlList('  exclude:', exclude),
      '',
      'packages:',
      '  include_local: ${includeLocalPackages ? 'true' : 'false'}',
      ..._yamlList('  include:', includePackages),
      if (applicationId != null) ...<String>[
        '',
        'application_id: $applicationId',
      ],
      if (applicationIds.isNotEmpty) ...<String>[
        '',
        'application_ids:',
        for (final target in applicationIds.keys.toList()..sort()) ...<String>[
          '  $target:',
          for (final flavor in applicationIds[target]!.keys.toList()..sort())
            '    $flavor: ${_yamlQuote(applicationIds[target]![flavor]!)}',
        ],
      ],
      if (entrypoints.isNotEmpty) ...<String>[
        '',
        'entrypoints:',
        for (final target in entrypoints.keys.toList()..sort()) ...<String>[
          '  $target:',
          for (final flavor in entrypoints[target]!.keys.toList()..sort())
            '    $flavor: ${_yamlQuote(entrypoints[target]![flavor]!)}',
        ],
      ],
      '',
      'signing:',
      '  public_key: $publicKeyPath',
      '  private_key: $privateKeyPath',
      '',
      'runtime:',
      '  update_url: $updateUrl',
      '',
    ];
    return lines.join('\n');
  }

  bool includes(String relativePath) {
    final normalized = relativePath.replaceAll(r'\', '/');
    if (exclude.any((pattern) => globMatches(pattern, normalized)))
      return false;
    return include.any((pattern) => globMatches(pattern, normalized));
  }

  /// Resolve an explicit entrypoint or a target/flavor mapping. A flavor with
  /// no mapping is rejected instead of silently falling back to lib/main.dart.
  EntrypointSelection resolveEntrypoint({
    required String target,
    String? flavor,
    String? entrypointPath,
  }) {
    if (target != 'android' && target != 'ios') {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'T1006',
        summary: 'Unsupported release target',
        detail: target,
        action: 'Use android or ios.',
      );
    }
    final normalizedFlavor = flavor == null
        ? null
        : normalizeFlavorName(flavor);
    final configured = entrypoints[target];
    final mappedPath = entrypointPath == null
        ? configured == null
              ? null
              : configured[normalizedFlavor ?? 'default']
        : entrypointPath;
    if (normalizedFlavor != null &&
        entrypointPath == null &&
        mappedPath == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'T1208',
        summary: 'Flavor entrypoint is not configured',
        detail: '$target/$normalizedFlavor',
        action:
            'Pass --entrypoint lib/path/to/main.dart or add entrypoints.$target.$normalizedFlavor to tool.yaml.',
      );
    }
    return EntrypointSelection(
      target: target,
      entrypointPath: normalizeEntrypointPath(mappedPath ?? 'lib/main.dart'),
      flavor: normalizedFlavor,
    );
  }

  String? applicationIdFor(String target, {String? flavor}) {
    final configured = applicationIds[target];
    final mapped = configured == null ? null : configured[flavor ?? 'default'];
    return mapped ?? applicationId;
  }
}

/// Safe, committed project binding for the public Hyfens workflow.
///
/// This is intentionally separate from the legacy local `tool.yaml`, which
/// still owns instrumentation and signing paths needed by release/patch. A
/// Hyfens binding contains selection metadata only; it never contains a
/// session, bearer token, password, or signing key.
final class HyfensProjectBinding {
  const HyfensProjectBinding({
    required this.profile,
    this.organizationId,
    this.applicationId,
    this.environmentId,
    this.runtimeApplicationId,
    this.version = 1,
  });

  final int version;
  final String profile;
  final String? organizationId;
  final String? applicationId;
  final String? environmentId;
  final String? runtimeApplicationId;

  static HyfensProjectBinding? load(File file) {
    if (!file.existsSync()) return null;
    final raw = loadYaml(file.readAsStringSync());
    if (raw is! YamlMap) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'H1201',
        summary: 'Hyfens project binding is not a mapping',
        detail: file.path,
        action: 'Repair hyfens.yaml or rerun hyfens init --force after review.',
      );
    }
    final version = _hyfensInt(raw['version'], 'version');
    if (version != 1) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'H1202',
        summary: 'Unsupported hyfens.yaml version',
        detail: 'Found version $version; this CLI supports version 1.',
      );
    }
    const allowedFields = <String>{
      'version',
      'profile',
      'organization',
      'organization_id',
      'application',
      'application_id',
      'environment',
      'environment_id',
      'runtime_application_id',
    };
    final unknownFields = raw.keys
        .whereType<String>()
        .where((key) => !allowedFields.contains(key))
        .toList();
    if (unknownFields.isNotEmpty) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'H1204',
        summary: 'hyfens.yaml contains unsupported fields',
        detail: unknownFields.join(', '),
        path: file.path,
        action: 'Keep only profile and safe organization/application/environment identifiers in hyfens.yaml.',
      );
    }
    _rejectSecretFields(raw, file);
    final profile = _hyfensRequiredString(raw['profile'], 'profile');
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(profile)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'H1203',
        summary: 'Invalid hyfens.yaml profile',
        detail: 'Expected a simple named profile.',
        path: file.path,
      );
    }
    return HyfensProjectBinding(
      version: version,
      profile: profile,
      organizationId: _hyfensNullableString(
        raw['organization'] ?? raw['organization_id'],
        'organization',
      ),
      applicationId: _hyfensNullableString(
        raw['application'] ?? raw['application_id'],
        'application',
      ),
      environmentId: _hyfensNullableString(
        raw['environment'] ?? raw['environment_id'],
        'environment',
      ),
      runtimeApplicationId: _hyfensNullableString(
        raw['runtime_application_id'],
        'runtime_application_id',
      ),
    );
  }

  String encode() {
    final lines = <String>[
      'version: 1',
      'profile: $profile',
      if (organizationId != null) 'organization: $organizationId',
      if (applicationId != null) 'application: $applicationId',
      if (environmentId != null) 'environment: $environmentId',
      if (runtimeApplicationId != null)
        'runtime_application_id: $runtimeApplicationId',
      '',
    ];
    return lines.join('\n');
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'profile': profile,
    'organization': organizationId,
    'application': applicationId,
    'environment': environmentId,
    'runtimeApplicationId': runtimeApplicationId,
  };
}

Future<void> writeHyfensBinding(
  File file, {
  required HyfensProjectBinding binding,
}) => writeAtomicText(file, binding.encode());

Future<void> writeDefaultConfig(File file, {String? applicationId}) async {
  await writeAtomicText(
    file,
    ToolConfig(applicationId: applicationId).encode(),
  );
}

bool globMatches(String pattern, String value) {
  final source = StringBuffer('^');
  for (var index = 0; index < pattern.length; index++) {
    final character = pattern[index];
    if (character == '*') {
      final isDouble = index + 1 < pattern.length && pattern[index + 1] == '*';
      if (isDouble) {
        source.write('.*');
        index++;
      } else {
        source.write('[^/]*');
      }
    } else if (character == '?') {
      source.write('[^/]');
    } else {
      source.write(RegExp.escape(character));
    }
  }
  source.write(r'$');
  return RegExp(source.toString()).hasMatch(value);
}

YamlMap _map(Object? value, String name) {
  if (value == null) return YamlMap();
  if (value is YamlMap) return value;
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'T1203',
    summary: 'Invalid tool.yaml $name',
    detail: 'Expected a mapping.',
  );
}

int _int(Object? value, String name) {
  if (value is int) return value;
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'T1203',
    summary: 'Invalid tool.yaml $name',
    detail: 'Expected an integer.',
  );
}

bool _bool(Object? value, {required bool defaultValue}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'T1203',
    summary: 'Invalid tool.yaml boolean',
    detail: 'Expected true or false.',
  );
}

String _string(Object? value, String defaultValue) {
  if (value == null) return defaultValue;
  if (value is String && value.isNotEmpty) return value;
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'T1203',
    summary: 'Invalid tool.yaml string',
    detail: 'Expected a non-empty string.',
  );
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'T1203',
    summary: 'Invalid tool.yaml string',
    detail: 'Expected a non-empty string.',
  );
}

String _url(Object? value, String defaultValue) {
  final result = _string(value, defaultValue);
  final uri = Uri.tryParse(result);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'T1205',
      summary: 'Invalid tool.yaml runtime URL',
      detail: result,
      action: 'Use an http:// or https:// patch endpoint.',
    );
  }
  return result;
}

List<String> _strings(Object? value, List<String> fallback) {
  if (value == null) return List.unmodifiable(fallback);
  if (value is! YamlList || value.any((item) => item is! String)) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'T1204',
      summary: 'Invalid tool.yaml list',
      detail: 'Expected a list of strings.',
    );
  }
  return List.unmodifiable(value.cast<String>());
}

List<String> _yamlList(String label, List<String> values) => <String>[
  '$label${values.isEmpty ? ' []' : ''}',
  for (final value in values) '    - $value',
];

String _yamlQuote(String value) => "'${value.replaceAll("'", "''")}'";

Map<String, Map<String, String>> _entrypointMappings(Object? value) {
  if (value == null) return const <String, Map<String, String>>{};
  final targets = _map(value, 'entrypoints');
  final result = <String, Map<String, String>>{};
  for (final entry in targets.entries) {
    final target = entry.key;
    if (target is! String || (target != 'android' && target != 'ios')) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1203',
        summary: 'Invalid tool.yaml entrypoints target',
        detail: '$target',
        action: 'Use android or ios as entrypoint mapping targets.',
      );
    }
    final flavors = _map(entry.value, 'entrypoints.$target');
    final targetEntries = <String, String>{};
    for (final flavorEntry in flavors.entries) {
      final flavor = flavorEntry.key;
      if (flavor is! String ||
          (flavor != 'default' &&
              !RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(flavor))) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1203',
          summary: 'Invalid tool.yaml flavor name',
          detail: '$target/$flavor',
          action:
              'Use default or a native flavor identifier as the mapping key.',
        );
      }
      if (flavorEntry.value is! String) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1203',
          summary: 'Invalid tool.yaml entrypoint mapping',
          detail: '$target/$flavor',
          action: 'Map each flavor to one Dart entrypoint path.',
        );
      }
      targetEntries[flavor] = normalizeEntrypointPath(
        flavorEntry.value as String,
      );
    }
    result[target] = Map.unmodifiable(targetEntries);
  }
  return Map.unmodifiable(result);
}

Map<String, Map<String, String>> _applicationIdMappings(Object? value) {
  if (value == null) return const <String, Map<String, String>>{};
  final targets = _map(value, 'application_ids');
  final result = <String, Map<String, String>>{};
  for (final entry in targets.entries) {
    final target = entry.key;
    if (target is! String || (target != 'android' && target != 'ios')) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1203',
        summary: 'Invalid tool.yaml application_ids target',
        detail: '$target',
        action: 'Use android or ios as application ID mapping targets.',
      );
    }
    final flavors = _map(entry.value, 'application_ids.$target');
    final targetIds = <String, String>{};
    for (final flavorEntry in flavors.entries) {
      final flavor = flavorEntry.key;
      if (flavor is! String ||
          (flavor != 'default' &&
              !RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(flavor))) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1203',
          summary: 'Invalid tool.yaml application ID flavor',
          detail: '$target/$flavor',
          action:
              'Use default or a native flavor identifier as the mapping key.',
        );
      }
      final id = flavorEntry.value;
      if (id is! String || id.isEmpty || id.contains(RegExp(r'[\u0000\r\n]'))) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1203',
          summary: 'Invalid tool.yaml application ID mapping',
          detail: '$target/$flavor',
          action: 'Map each flavor to one non-empty application identifier.',
        );
      }
      targetIds[flavor] = id;
    }
    result[target] = Map.unmodifiable(targetIds);
  }
  return Map.unmodifiable(result);
}

int _hyfensInt(Object? value, String field) {
  if (value is int) return value;
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'H1203',
    summary: 'Invalid hyfens.yaml $field',
    detail: 'Expected an integer.',
  );
}

String _hyfensRequiredString(Object? value, String field) {
  final result = _hyfensNullableString(value, field);
  if (result == null) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'H1203',
      summary: 'Invalid hyfens.yaml $field',
      detail: 'Expected a non-empty string.',
    );
  }
  return result;
}

String? _hyfensNullableString(Object? value, String field) {
  if (value == null) return null;
  if (value is String &&
      value.isNotEmpty &&
      !value.contains(RegExp(r'[\u0000\r\n]'))) {
    return value;
  }
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'H1203',
    summary: 'Invalid hyfens.yaml $field',
    detail: 'Expected a non-empty safe string.',
  );
}

void _rejectSecretFields(YamlMap value, File file) {
  const secretFragments = <String>{
    'token',
    'secret',
    'password',
    'jwt',
    'bearer',
    'private_key',
    'privatekey',
    'session',
    'credential',
  };
  bool isSecretField(Object? key) {
    if (key is! String) return false;
    final normalized = key.toLowerCase().replaceAll('-', '_');
    return secretFragments.any(
      (fragment) => normalized == fragment || normalized.contains(fragment),
    );
  }

  void visit(Object? current) {
    if (current is YamlMap) {
      for (final entry in current.entries) {
        if (isSecretField(entry.key)) {
          throw ToolFailure.single(
            exitCode: ToolExitCode.environment,
            code: 'H1204',
            summary: 'hyfens.yaml contains secret material',
            detail: 'The field ${entry.key} is not allowed.',
            path: file.path,
            action: 'Remove credentials from hyfens.yaml; use hyfens login or HYFENS_TOKEN.',
          );
        }
        visit(entry.value);
      }
    } else if (current is YamlList) {
      for (final item in current) visit(item);
    }
  }

  visit(value);
}
