import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'canonical.dart';
import 'configuration.dart';
import 'diagnostics.dart';
import 'graph.dart';
import 'profile.dart';
import 'project.dart';

typedef DiscoveryHttpClientFactory = HttpClient Function(
  SecurityContext? context,
);

/// The non-secret instance contract used before a browser or device login.
abstract final class DiscoveryApiContract {
  static const path = '.well-known/hyfens';
  static const product = 'hyfens';
  static const browserPkce = 'browser_pkce';
  static const device = 'device';
}

final class DiscoveryDocument {
  const DiscoveryDocument({
    required this.product,
    required this.apiVersion,
    required this.authMethods,
    required this.capabilities,
    this.authorizationEndpoint,
    this.tokenEndpoint,
    this.deviceAuthorizationEndpoint,
    this.deviceTokenEndpoint,
  });

  final String product;
  final String apiVersion;
  final List<String> authMethods;
  final Map<String, Object?> capabilities;
  final Uri? authorizationEndpoint;
  final Uri? tokenEndpoint;
  final Uri? deviceAuthorizationEndpoint;
  final Uri? deviceTokenEndpoint;

  bool get supportsBrowserPkce => authMethods.any(
    (method) => <String>{
      DiscoveryApiContract.browserPkce,
      'authorization_code_pkce_s256',
      'authorization_code_pkce',
      'authorization_code',
    }.contains(method.toLowerCase()),
  );

  bool get supportsDevice => authMethods.any(
    (method) => <String>{
      DiscoveryApiContract.device,
      'device_code',
      'device_authorization',
    }.contains(method.toLowerCase()),
  );

  factory DiscoveryDocument.fromJson(Map<String, Object?> json) {
    final product = _discoveryString(json, const <String>[
      'product',
      'service',
      'name',
    ], 'product');
    final apiVersion = _discoveryString(json, const <String>[
      'api_version',
      'apiVersion',
      'version',
    ], 'API version');
    if (product != DiscoveryApiContract.product &&
        product != 'hyfens-control-plane') {
      throw const FormatException('Unsupported discovery product');
    }
    if (!_supportedDiscoveryVersion(apiVersion)) {
      throw FormatException('Unsupported discovery API version: $apiVersion');
    }
    final rawMethods = json['auth_methods'] ?? json['authMethods'];
    if (rawMethods is! List || rawMethods.any((item) => item is! String)) {
      throw const FormatException('Discovery auth methods are invalid');
    }
    final rawCapabilities = json['capabilities'];
    if (rawCapabilities is List &&
        rawCapabilities.any((item) => item is! String)) {
      throw const FormatException('Discovery capabilities are invalid');
    }
    final capabilities = switch (rawCapabilities) {
      null => const <String, Object?>{},
      Map() => _mapStringKeys(rawCapabilities),
      List() => <String, Object?>{
        for (final item in rawCapabilities)
          if (item is String) item: true,
      },
      _ => throw const FormatException('Discovery capabilities are invalid'),
    };
    return DiscoveryDocument(
      product: product,
      apiVersion: apiVersion,
      authMethods: List.unmodifiable(rawMethods.cast<String>()),
      capabilities: capabilities,
      authorizationEndpoint: _optionalUri(json, const <String>[
        'authorization_endpoint',
        'authorizationEndpoint',
      ]),
      tokenEndpoint: _optionalUri(json, const <String>[
        'token_endpoint',
        'tokenEndpoint',
      ]),
      deviceAuthorizationEndpoint: _optionalUri(json, const <String>[
        'device_authorization_endpoint',
        'deviceAuthorizationEndpoint',
      ]),
      deviceTokenEndpoint: _optionalUri(json, const <String>[
        'device_token_endpoint',
        'deviceTokenEndpoint',
      ]),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'product': product,
    'api_version': apiVersion,
    'auth_methods': authMethods,
    'capabilities': capabilities,
    if (authorizationEndpoint != null)
      'authorization_endpoint': authorizationEndpoint.toString(),
    if (tokenEndpoint != null) 'token_endpoint': tokenEndpoint.toString(),
    if (deviceAuthorizationEndpoint != null)
      'device_authorization_endpoint': deviceAuthorizationEndpoint.toString(),
    if (deviceTokenEndpoint != null)
      'device_token_endpoint': deviceTokenEndpoint.toString(),
  };
}

/// Performs unauthenticated compatibility discovery for one API base.
final class DiscoveryClient {
  DiscoveryClient({
    DiscoveryHttpClientFactory? httpClientFactory,
    this.path = DiscoveryApiContract.path,
  }) : _httpClientFactory =
           httpClientFactory ?? ((context) => HttpClient(context: context));

  final DiscoveryHttpClientFactory _httpClientFactory;
  final String path;

  Future<DiscoveryDocument> discover(
    Uri endpoint, {
    SecurityContext? securityContext,
  }) async {
    late final Uri normalized;
    try {
      normalized = normalizeControlPlaneEndpoint(endpoint);
    } on FormatException catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'D1005',
        summary: 'Control-plane discovery endpoint is invalid',
        detail: error.message,
        action: 'Use an HTTPS API base or an explicit loopback HTTP API base.',
      );
    }
    final client = _httpClientFactory(securityContext);
    try {
      final request = await client.getUrl(_discoveryUri(normalized, path));
      request.headers.set(
        'X-Request-Id',
        'cli-${DateTime.now().microsecondsSinceEpoch}',
      );
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      final source = utf8.decode(bytes, allowMalformed: false);
      if (response.statusCode == HttpStatus.notFound ||
          response.statusCode == HttpStatus.methodNotAllowed) {
        throw _unsupportedDiscovery(
          'This control plane does not expose the Hyfens discovery endpoint.',
        );
      }
      Object? decoded;
      try {
        decoded = source.isEmpty ? <String, Object?>{} : jsonDecode(source);
      } on Object {
        throw ToolFailure.single(
          exitCode: ToolExitCode.compatibility,
          code: 'D1002',
          summary: 'Control-plane discovery response is not valid JSON',
          detail: 'GET ${_discoveryUri(normalized, path)}',
          action: 'Upgrade the control plane or expose a versioned /.well-known/hyfens response.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.compatibility,
          code: 'D1003',
          summary: 'Control-plane discovery was rejected',
          detail: 'HTTP ${response.statusCode}',
          action: 'Check the API base and expose a compatible Hyfens discovery response.',
        );
      }
      final root = decoded is Map
          ? _mapStringKeys(decoded)
          : <String, Object?>{};
      final rawData = root['data'];
      final payload = rawData is Map ? _mapStringKeys(rawData) : root;
      try {
        return DiscoveryDocument.fromJson(payload);
      } on FormatException catch (error) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.compatibility,
          code: 'D1004',
          summary: 'Control plane is not compatible with this CLI',
          detail: error.message,
          action: 'Expose product=hyfens, a supported api_version, and auth_methods at /.well-known/hyfens.',
        );
      }
    } on ToolFailure {
      rethrow;
    } on FormatException catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'D1005',
        summary: 'Control-plane endpoint is not compatible',
        detail: error.message,
        action: 'Use the managed Cloud API base or an HTTPS/self-hosted loopback API base.',
      );
    } on Object catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'D1006',
        summary: 'Control-plane discovery failed',
        detail: error.runtimeType.toString(),
        action: 'Check the API base, TLS configuration, and /.well-known/hyfens endpoint.',
      );
    } finally {
      client.close(force: true);
    }
  }
}

ToolFailure _unsupportedDiscovery(String detail) => ToolFailure.single(
  exitCode: ToolExitCode.compatibility,
  code: 'D1001',
  summary: 'Control plane does not support Hyfens CLI authentication',
  detail: detail,
  action: 'Deploy the versioned /.well-known/hyfens discovery endpoint before using browser or device login.',
);

Uri _discoveryUri(Uri endpoint, String path) {
  final root = endpoint.toString().endsWith('/')
      ? endpoint.toString()
      : '${endpoint.toString()}/';
  return Uri.parse(root).resolve(path);
}

String _discoveryString(
  Map<String, Object?> json,
  List<String> keys,
  String field,
) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    if (value is int) return value.toString();
  }
  throw FormatException('Discovery $field is missing');
}

Uri? _optionalUri(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is! String || value.isEmpty) {
      throw FormatException('Discovery $key is invalid');
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.hasQuery || uri.hasFragment) {
      throw FormatException('Discovery $key is invalid');
    }
    return uri;
  }
  return null;
}

bool _supportedDiscoveryVersion(String value) =>
    value == '1' || value == 'v1' || value.startsWith('1.');

Map<String, Object?> _mapStringKeys(Map value) => <String, Object?>{
  for (final entry in value.entries)
    if (entry.key is String) entry.key! as String: entry.value,
};

enum SourceKind {
  applicationDart,
  localPackage,
  hostedPureDartPackage,
  gitPureDartPackage,
  generatedDart,
  pluginDart,
  flutterSdk,
  dartSdk,
  nativeBoundary,
}

final class SourceUnit {
  SourceUnit({
    required this.file,
    required this.packageName,
    required this.libraryUri,
    required this.logicalLibraryPath,
    required this.kind,
    required this.selected,
    required this.entrypoint,
    required this.fingerprint,
    this.reason,
  });

  final File file;
  final String packageName;
  final String libraryUri;
  final String logicalLibraryPath;
  final SourceKind kind;
  final bool selected;
  final bool entrypoint;
  final String fingerprint;
  final String? reason;

  String relativeTo(FlutterProject project) {
    if (isWithin(project.root, file)) return relativePath(project.root, file);
    // External package paths must remain stable and collision-free. Never
    // expose their checkout path or reduce two packages' lib/foo.dart files
    // to the same basename.
    return 'package:$packageName/$logicalLibraryPath';
  }

  Map<String, Object?> toJson(FlutterProject project) => <String, Object?>{
    'packageName': packageName,
    'libraryUri': libraryUri,
    'relativePath': relativeTo(project),
    'logicalLibraryPath': logicalLibraryPath,
    'kind': kind.name,
    'selected': selected,
    'entrypoint': entrypoint,
    'fingerprint': fingerprint,
    'reason': reason,
  };
}

final class SourceDiscoveryResult {
  SourceDiscoveryResult({
    required this.project,
    required List<SourceUnit> units,
  }) : units = List.unmodifiable(units);

  final FlutterProject project;
  final List<SourceUnit> units;

  List<SourceUnit> get selected =>
      units.where((unit) => unit.selected).toList(growable: false);
  List<SourceUnit> get skipped =>
      units.where((unit) => !unit.selected).toList(growable: false);

  String get fingerprint => digestJson(<String, Object?>{
    'sources': units
        .map(
          (unit) => <String, Object?>{
            'uri': unit.libraryUri,
            'kind': unit.kind.name,
            'fingerprint': unit.fingerprint,
          },
        )
        .toList(growable: false),
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'selected': selected.length,
    'skipped': skipped.length,
    'units': units.map((unit) => unit.toJson(project)).toList(),
  };
}

final class SourceDiscoverer {
  const SourceDiscoverer();

  SourceDiscoveryResult discover(
    FlutterProject project,
    ProjectGraph graph,
    ToolConfig config, {
    String entrypointPath = 'lib/main.dart',
  }) {
    final selectedEntrypointPath = normalizeEntrypointPath(entrypointPath);
    final selectedEntrypoint = File(
      p.join(project.root.path, selectedEntrypointPath),
    );
    final units = <SourceUnit>[];
    for (final package in graph.packages) {
      if (package.name != project.packageName &&
          (package.source == PackageSourceType.hosted ||
              package.source == PackageSourceType.git ||
              package.source == PackageSourceType.sdk) &&
          !config.includePackages.contains(package.name)) {
        continue;
      }
      final root = package.root;
      if (root == null) continue;
      final lib = Directory(p.join(root.path, package.packageUri));
      if (!lib.existsSync()) continue;
      for (final file in listDartFiles(lib)) {
        final relative = _relativeLibraryPath(file, lib);
        final logicalPath = 'lib/$relative';
        final libraryUri = 'package:${package.name}/$relative';
        final source = file.readAsStringSync();
        final kind = _kind(package, file, source, project);
        final entrypoint =
            file.absolute.path == selectedEntrypoint.absolute.path;
        final decision = _decision(
          project: project,
          package: package,
          kind: kind,
          logicalPath: logicalPath,
          entrypoint: entrypoint,
          config: config,
        );
        units.add(
          SourceUnit(
            file: file,
            packageName: package.name,
            libraryUri: libraryUri,
            logicalLibraryPath: logicalPath,
            kind: kind,
            selected: decision.$1,
            entrypoint: entrypoint,
            fingerprint: sha256Hex(file.readAsBytesSync()),
            reason: decision.$2,
          ),
        );
      }
    }
    units.sort((left, right) => left.libraryUri.compareTo(right.libraryUri));
    if (!units.any((unit) => unit.entrypoint && unit.selected)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.analysis,
        code: 'T1401',
        summary: 'Application entrypoint is not selected for instrumentation',
        detail: selectedEntrypointPath,
        action: 'Ensure the selected entrypoint is under lib/, contains main(), and is not excluded; use --entrypoint to select it explicitly.',
      );
    }
    return SourceDiscoveryResult(project: project, units: units);
  }
}

String _relativeLibraryPath(File file, Directory lib) {
  final value = p
      .relative(file.absolute.path, from: lib.absolute.path)
      .replaceAll(r'\', '/');
  if (value.startsWith('../') || value == '..') {
    throw const FormatException('Source escaped package lib directory');
  }
  return value;
}

SourceKind _kind(
  ProjectPackage package,
  File file,
  String source,
  FlutterProject project,
) {
  final name = p.basename(file.path);
  final relative = relativePath(package.root!, file);
  if (package.source == PackageSourceType.sdk &&
      <String>{
        'flutter',
        'flutter_test',
        'flutter_web_plugins',
        'sky_engine',
      }.contains(package.name)) {
    return SourceKind.flutterSdk;
  }
  if (name.endsWith('.g.dart') ||
      name.endsWith('.freezed.dart') ||
      name.endsWith('.gr.dart') ||
      name.endsWith('.mocks.dart') ||
      relative.split('/').contains('generated')) {
    return SourceKind.generatedDart;
  }
  if (RegExp(
    r'''import\s+['"]dart:ffi['"]|\b(MethodChannel|EventChannel|BasicMessageChannel|AndroidView|UiKitView)\b''',
  ).hasMatch(source)) {
    return SourceKind.nativeBoundary;
  }
  if (package.name != project.packageName &&
      (package.isPlugin || package.hasNativeImplementation)) {
    return SourceKind.pluginDart;
  }
  if (package.name == project.packageName) return SourceKind.applicationDart;
  return switch (package.source) {
    PackageSourceType.path => SourceKind.localPackage,
    PackageSourceType.hosted => SourceKind.hostedPureDartPackage,
    PackageSourceType.git => SourceKind.gitPureDartPackage,
    PackageSourceType.sdk => SourceKind.dartSdk,
    PackageSourceType.application => SourceKind.applicationDart,
    PackageSourceType.unknown => SourceKind.hostedPureDartPackage,
  };
}

(bool, String?) _decision({
  required FlutterProject project,
  required ProjectPackage package,
  required SourceKind kind,
  required String logicalPath,
  required bool entrypoint,
  required ToolConfig config,
}) {
  if (kind == SourceKind.generatedDart) {
    return (false, 'generated source');
  }
  if (kind == SourceKind.nativeBoundary || kind == SourceKind.pluginDart) {
    return (false, 'native boundary');
  }
  if (kind == SourceKind.dartSdk || kind == SourceKind.flutterSdk) {
    return (false, 'SDK source');
  }
  if (package.name == project.packageName) {
    final relative = logicalPath;
    final selected = config.includes(relative) || entrypoint;
    return (selected, selected ? null : 'configuration exclusion');
  }
  if (package.source == PackageSourceType.path && config.includeLocalPackages) {
    return (true, null);
  }
  if (config.includePackages.contains(package.name)) return (true, null);
  return (false, 'dependency requires explicit selection');
}

String stripDartCommentsAndWhitespace(String source) {
  final result = StringBuffer();
  String? quote;
  var triple = false;
  var raw = false;
  for (var index = 0; index < source.length;) {
    final character = source[index];
    if (quote != null) {
      if (triple && source.startsWith('$quote$quote$quote', index)) {
        result.write('$quote$quote$quote');
        index += 3;
        quote = null;
        triple = false;
        raw = false;
        continue;
      }
      if (!triple && character == quote) {
        result.write(character);
        index++;
        quote = null;
        raw = false;
        continue;
      }
      result.write(character);
      if (!raw && character == r'\' && index + 1 < source.length) {
        result.write(source[index + 1]);
        index += 2;
      } else {
        index++;
      }
      continue;
    }
    if (source.startsWith('//', index)) {
      final newline = source.indexOf('\n', index + 2);
      index = newline == -1 ? source.length : newline;
      continue;
    }
    if (source.startsWith('/*', index)) {
      final end = source.indexOf('*/', index + 2);
      index = end == -1 ? source.length : end + 2;
      continue;
    }
    if (character == "'" || character == '"') {
      quote = character;
      triple = source.startsWith('$character$character$character', index);
      raw = result.isNotEmpty && result.toString().endsWith('r');
      final length = triple ? 3 : 1;
      result.write(source.substring(index, index + length));
      index += length;
      continue;
    }
    if (!RegExp(r'\s').hasMatch(character)) result.write(character);
    index++;
  }
  return result.toString();
}

Map<String, Object?> decodeSourceJson(String source) {
  final value = jsonDecode(source);
  if (value is! Map<String, Object?>) {
    throw const FormatException('Source JSON must be an object');
  }
  return value;
}
