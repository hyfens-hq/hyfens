import 'dart:io';

import 'package:yaml/yaml.dart';

import 'canonical.dart';
import 'diagnostics.dart';

final class ToolConfig {
  const ToolConfig({
    this.version = 1,
    this.include = const <String>['lib/**'],
    this.exclude = const <String>['lib/generated/**'],
    this.includeLocalPackages = true,
    this.includePackages = const <String>[],
    this.applicationId,
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
  final String publicKeyPath;
  final String privateKeyPath;
  final String updateUrl;

  ToolConfig copyWith({
    List<String>? include,
    List<String>? exclude,
    bool? includeLocalPackages,
    List<String>? includePackages,
    String? applicationId,
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
