import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:path/path.dart' as p;

import '../auth_storage.dart';
import '../canonical.dart';
import '../diagnostics.dart';
import '../discovery.dart';
import '../profile.dart';
import '../project.dart';
import '../toolchain.dart';

/// The MCP identity is independent from the local release-toolchain version.
const hyfensMcpVersion = '0.1.1';
const hyfensMcpStartupMessage =
    'Hyfens MCP server running over stdio; waiting for an agent connection.';

/// SDK decision record: dart_mcp 0.5.2 is the Dart team's experimental,
/// BSD-3-Clause MCP SDK. It supplies the JSON-RPC, tools, and line-oriented
/// stream implementation used here. Its dependency impact is recorded by the
/// package manifest and lockfile: json_rpc_2, stream_transform, stream_channel,
/// async, collection, and meta are resolved through the SDK.
///
/// The server is stream-injectable. The coordinator can use
/// [HyfensMcpServer.serveStdio] and await [MCPBase.done]; protocol tests can
/// provide their own byte streams.
///
/// Deploy is a capability probe, not a fake implementation. The current CLI
/// has no public authenticated delivery service: its HTTP sequence is private
/// to the command runner. This adapter neither shells out nor duplicates that
/// private sequence, and returns an honest structured unsupported error.
final class HyfensMcpServer extends MCPServer with ToolsSupport {
  HyfensMcpServer({
    required Stream<List<int>> input,
    required StreamSink<List<int>> output,
    required HyfensToolchain toolchain,
    required AuthStorage authStorage,
    String? profileName,
    bool debug = false,
    IOSink? log,
  }) : adapter = HyfensMcpAdapter(
         toolchain: toolchain,
         authStorage: authStorage,
         defaultProfileName: profileName,
       ),
       _debug = debug,
       _log = log,
       super.fromStreamChannel(
         stdioChannel(input: input, output: output),
         implementation: Implementation(
           name: 'hyfens',
           version: hyfensMcpVersion,
           description: 'Bounded MCP adapter for the Hyfens Dart toolchain.',
         ),
         instructions:
             'Use project_path for an explicit Flutter project. Responses are '
             'structured and never contain credentials. MUTATION tools can '
             'write local project state.',
       ) {
    _addTools();
    registerRequestHandler<PingRequest?, EmptyResult?>('shutdown', (_) {
      Timer.run(() => unawaited(shutdown()));
      return EmptyResult();
    });
  }

  /// Command-boundary constructor. Defaults are resolved only in this method,
  /// so the core constructor remains fully injectable for protocol tests.
  HyfensMcpServer.serveStdio({
    required HyfensToolchain toolchain,
    required AuthStorage authStorage,
    String? profileName,
    bool debug = false,
    Stream<List<int>>? input,
    StreamSink<List<int>>? output,
    IOSink? log,
  }) : this(
         input: input ?? stdin,
         output: output ?? stdout,
         toolchain: toolchain,
         authStorage: authStorage,
         profileName: profileName,
         debug: debug,
         log: log ?? stderr,
       );

  /// Direct adapter access for an embedding coordinator or adapter tests.
  final HyfensMcpAdapter adapter;
  final bool _debug;
  final IOSink? _log;
  final _toolNames = <String>{};

  @override
  Future<CallToolResult> callTool(CallToolRequest request) async {
    try {
      final name = request.name;
      if (!_toolNames.contains(name)) {
        return _errorResult(
          name,
          const _McpError(
            code: 'MCP_TOOL_NOT_FOUND',
            summary: 'Tool is not registered',
            detail: 'No bounded Hyfens MCP tool has this name.',
            action: 'Call tools/list and select an advertised tool.',
          ),
        );
      }
    } on Object {
      return _errorResult(
        'tools/call',
        const _McpError(
          code: 'MCP_INVALID_PARAMS',
          summary: 'Tool name is missing',
          detail: 'tools/call requires a string name.',
        ),
      );
    }
    return super.callTool(request);
  }

  void _addTools() {
    _add(
      'status',
      'Read-only local status, toolchain, and bounded artifact inventory. '
          'No application runtime or control-plane state is queried.',
      _schema({'project_path': _pathSchema()}),
      (args) =>
          adapter.status(projectPath: _optionalPath(args, 'project_path')),
    );
    _add(
      'doctor',
      'Read-only inspection of the supported Flutter, Dart, and local runtime '
          'environment for a Flutter project.',
      _schema({'project_path': _pathSchema()}),
      (args) =>
          adapter.doctor(projectPath: _optionalPath(args, 'project_path')),
    );
    _add(
      'profile_list',
      'Read-only list of host-bound profiles and login status. Credential '
          'files are checked by endpoint and never returned.',
      _emptySchema(),
      (_) => adapter.profileList(),
    );
    _add(
      'profile_current',
      'Read-only current profile selection and non-secret endpoint/scope metadata.',
      _emptySchema(),
      (_) => adapter.profileCurrent(),
    );
    _add(
      'profile_get',
      'Read-only metadata for one named profile. Access, refresh, and session '
          'tokens are omitted.',
      _schema({'name': _profileSchema()}, required: const ['name']),
      (args) => adapter.profileGet(_requiredProfile(args, 'name')),
    );
    _add(
      'project_init',
      'MUTATION: writes tool.yaml and the local .tool store unless dry_run '
          'is true. It does not edit application source.',
      _schema({
        'project_path': _pathSchema(),
        'dry_run': Schema.bool(description: 'Preview local initialization.'),
        'force': Schema.bool(description: 'Replace existing tool.yaml.'),
      }),
      (args) => adapter.projectInit(
        projectPath: _optionalPath(args, 'project_path'),
        dryRun: _optionalBool(args, 'dry_run') ?? false,
        force: _optionalBool(args, 'force') ?? false,
      ),
      mutation: true,
    );
    _add(
      'release_create',
      'MUTATION: analyzes the project and writes a local release baseline. '
          'The existing HyfensToolchain build service may run for a full release. '
          'For flavor projects, pass the native flavor and its Dart entrypoint.',
      _schema(
        {
          'target': Schema.string(description: 'android or ios.'),
          'project_path': _pathSchema(),
          'architecture': Schema.string(maxLength: 32),
          'build_mode': Schema.string(maxLength: 32),
          'metadata_only': Schema.bool(),
          'flavor': Schema.string(maxLength: 64),
          'entrypoint': Schema.string(maxLength: 4096),
        },
        required: const ['target'],
      ),
      (args) => adapter.releaseCreate(
        target: _requiredString(args, 'target'),
        projectPath: _optionalPath(args, 'project_path'),
        architecture: _optionalString(args, 'architecture') ?? 'arm64',
        buildMode: _optionalString(args, 'build_mode') ?? 'release',
        metadataOnly: _optionalBool(args, 'metadata_only') ?? false,
        flavor: _optionalString(args, 'flavor'),
        entrypointPath: _optionalString(args, 'entrypoint'),
      ),
      mutation: true,
    );
    _add(
      'release_inspect',
      'Read-only bounded release metadata. Raw source graphs, artifacts, and '
          'signing material are not returned.',
      _schema({'project_path': _pathSchema(), 'release_id': _releaseSchema()}),
      (args) => adapter.releaseInspect(
        projectPath: _optionalPath(args, 'project_path'),
        releaseId: _optionalRelease(args, 'release_id'),
      ),
    );
    _add(
      'patch_create',
      'MUTATION: analyzes changed supported Dart functions, signs a patch with '
          'the configured local key, and advances the local sequence. It reuses '
          'the release baseline entrypoint; optional flavor/entrypoint values '
          'must match that baseline.',
      _schema({
        'project_path': _pathSchema(),
        'release_id': _releaseSchema(),
        'flavor': Schema.string(maxLength: 64),
        'entrypoint': Schema.string(maxLength: 4096),
      }),
      (args) => adapter.patchCreate(
        projectPath: _optionalPath(args, 'project_path'),
        releaseId: _optionalRelease(args, 'release_id'),
        flavor: _optionalString(args, 'flavor'),
        entrypointPath: _optionalString(args, 'entrypoint'),
      ),
      mutation: true,
    );
    _add(
      'patch_verify',
      'Read-only verification of a patch signature and optional release '
          'compatibility against the configured local trust key.',
      _schema(
        {
          'patch_path': _patchSchema(),
          'project_path': _pathSchema(),
          'release_id': _releaseSchema(),
        },
        required: const ['patch_path'],
      ),
      (args) => adapter.patchVerify(
        patchPath: _requiredPath(args, 'patch_path'),
        projectPath: _optionalPath(args, 'project_path'),
        releaseId: _optionalRelease(args, 'release_id'),
      ),
    );
    _add(
      'patch_inspect',
      'Read-only bounded patch metadata without returning bytecode or signature bytes.',
      _schema({'patch_path': _patchSchema()}, required: const ['patch_path']),
      (args) =>
          adapter.patchInspect(patchPath: _requiredPath(args, 'patch_path')),
    );
    _add(
      'deploy',
      'UNSUPPORTED CAPABILITY: the current toolchain has no public '
          'authenticated delivery service. This probe performs no network or '
          'filesystem mutation; MCP does not shell out or duplicate private '
          'CLI deploy HTTP wiring.',
      _emptySchema(),
      (_) => adapter.deploy(),
      mutation: true,
    );
    _add(
      'rollback',
      'MUTATION: records a signed rollback to the trusted store-installed AOT '
          'base and preserves the patch sequence high-water mark. It does not '
          'rewrite app-local runtime state.',
      _schema({
        'project_path': _pathSchema(),
        'release_id': _releaseSchema(),
        'to': Schema.string(description: 'base or base-aot.'),
      }),
      (args) => adapter.rollback(
        projectPath: _optionalPath(args, 'project_path'),
        releaseId: _optionalRelease(args, 'release_id'),
        target: _optionalString(args, 'to') ?? 'base',
      ),
      mutation: true,
    );
    _add(
      'control_plane_discovery',
      'Read-only unauthenticated compatibility discovery for a host-bound '
          'profile. It returns service capabilities, never credentials.',
      _schema({'profile': _profileSchema()}),
      (args) => adapter.controlPlaneDiscovery(
        profileName: _optionalProfile(args, 'profile'),
      ),
    );
  }

  void _add(
    String name,
    String description,
    ObjectSchema schema,
    _McpOperation operation, {
    bool mutation = false,
  }) {
    _toolNames.add(name);
    registerTool(
      Tool(
        name: name,
        description: description,
        inputSchema: schema,
        annotations: ToolAnnotations(
          readOnlyHint: !mutation,
          destructiveHint: mutation,
          idempotentHint: !mutation,
          openWorldHint: false,
          title: name,
        ),
      ),
      (request) => _validated(name, schema, request, operation),
      validateArguments: false,
    );
  }

  Future<CallToolResult> _validated(
    String name,
    ObjectSchema schema,
    CallToolRequest request,
    _McpOperation operation,
  ) async {
    try {
      final args = request.arguments ?? const <String, Object?>{};
      final failures = schema.validate(args);
      if (failures.isNotEmpty) {
        return _errorResult(
          name,
          _McpError(
            code: 'MCP_INVALID_PARAMS',
            summary: 'Tool arguments are invalid',
            detail: failures.map((item) => item.toErrorString()).join('; '),
            action: 'Use the fields and types described by tools/list.',
          ),
        );
      }
      final value = await operation(args);
      final response = <String, Object?>{
        'ok': true,
        'operation': name,
        ..._safeMap(value),
      };
      return _result(response);
    } on _McpOperationException catch (error) {
      return _errorResult(name, error.error);
    } on ToolFailure catch (failure) {
      final diagnostic = failure.diagnostics.first;
      return _errorResult(
        name,
        _McpError(
          code: _safeCode(diagnostic.code),
          summary: _safeText(diagnostic.summary),
          detail: _safeText(diagnostic.detail),
          action: diagnostic.action == null
              ? null
              : _safeText(diagnostic.action!),
          exitCode: failure.exitCode.value,
          storeReleaseRequired: diagnostic.storeReleaseRequired,
        ),
      );
    } on FormatException catch (error) {
      return _errorResult(
        name,
        _McpError(
          code: 'MCP_INVALID_ARGUMENT',
          summary: 'Local metadata or operation arguments are invalid',
          detail: _safeText(error.message),
        ),
      );
    } on Object catch (error, stackTrace) {
      _writeLog(
        name + ' failed (' + error.runtimeType.toString() + ')',
        force: true,
        stackTrace: stackTrace,
      );
      return _errorResult(
        name,
        const _McpError(
          code: 'MCP_INTERNAL',
          summary: 'Hyfens MCP operation failed',
          detail:
              'An unexpected failure occurred; sensitive details were omitted.',
        ),
      );
    }
  }

  void _writeLog(
    String message, {
    required bool force,
    StackTrace? stackTrace,
  }) {
    final log = _log;
    if (log == null || !force && !_debug) return;
    log.writeln('[hyfens mcp] ' + message);
    if (_debug && stackTrace != null) log.writeln(stackTrace);
  }
}

/// Convenience command-boundary runner.
Future<void> runHyfensMcp({
  required HyfensToolchain toolchain,
  required AuthStorage authStorage,
  String? profileName,
  bool debug = false,
  Stream<List<int>>? input,
  StreamSink<List<int>>? output,
  IOSink? log,
}) async {
  final server = HyfensMcpServer.serveStdio(
    toolchain: toolchain,
    authStorage: authStorage,
    profileName: profileName,
    debug: debug,
    input: input,
    output: output,
    log: log,
  );
  await server.done;
}

/// Adapter from the MCP catalog to existing Hyfens services.
final class HyfensMcpAdapter {
  HyfensMcpAdapter({
    required this.toolchain,
    required this.authStorage,
    String? defaultProfileName,
    DiscoveryClient? discoveryClient,
  }) : defaultProfileName = defaultProfileName,
       _discoveryClient = discoveryClient ?? DiscoveryClient() {
    if (defaultProfileName != null) _validateProfile(defaultProfileName);
  }

  final HyfensToolchain toolchain;
  final AuthStorage authStorage;
  final String? defaultProfileName;
  final DiscoveryClient _discoveryClient;

  Future<Map<String, Object?>> status({String? projectPath}) async =>
      (await toolchain.status(projectPath: projectPath)).toJson();

  Future<Map<String, Object?>> doctor({String? projectPath}) async {
    final project = toolchain.project(projectPath: projectPath);
    final environment = await toolchain.doctor(projectPath: project.root.path);
    return <String, Object?>{
      'project': _projectJson(project),
      'environment': environment.toJson(),
    };
  }

  Future<Map<String, Object?>> profileList() async {
    final catalog = await authStorage.readProfileCatalog();
    final profiles = catalog.profiles.toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    return <String, Object?>{
      'active_profile': catalog.activeProfile,
      'profiles': [for (final profile in profiles) await _profileJson(profile)],
    };
  }

  Future<Map<String, Object?>> profileCurrent() async {
    final catalog = await authStorage.readProfileCatalog();
    return <String, Object?>{
      'active_profile': catalog.active.name,
      'persisted': catalog.current != null,
      'profile': await _profileJson(catalog.active),
    };
  }

  Future<Map<String, Object?>> profileGet(String name) async {
    _validateProfile(name);
    final catalog = await authStorage.readProfileCatalog();
    final profile = catalog.byName(name);
    if (profile == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'A1025',
        summary: 'Profile does not exist',
        detail: 'The requested profile is not in the local catalog.',
        action: 'Run profile_list and select an available profile.',
      );
    }
    return <String, Object?>{
      'profile': await _profileJson(profile),
      'current': catalog.current?.name == profile.name,
    };
  }

  Future<Map<String, Object?>> projectInit({
    String? projectPath,
    bool dryRun = false,
    bool force = false,
  }) async {
    final result = await toolchain.init(
      projectPath: projectPath,
      dryRun: dryRun,
      force: force,
    );
    return <String, Object?>{
      'project': _projectJson(result.project),
      'dryRun': result.dryRun,
      'actions': result.actions,
      'environment': result.environment.toJson(),
    };
  }

  Future<Map<String, Object?>> releaseCreate({
    required String target,
    String? projectPath,
    String architecture = 'arm64',
    String buildMode = 'release',
    bool metadataOnly = false,
    String? flavor,
    String? entrypointPath,
  }) async => _releaseJson(
    await toolchain.release(
      target: target,
      projectPath: projectPath,
      architecture: architecture,
      buildMode: buildMode,
      metadataOnly: metadataOnly,
      flavor: flavor,
      entrypointPath: entrypointPath,
    ),
  );

  Future<Map<String, Object?>> releaseInspect({
    String? projectPath,
    String? releaseId,
  }) async {
    final project = toolchain.project(projectPath: projectPath);
    return _releaseJson(_selectRelease(ToolStore(project), releaseId));
  }

  Future<Map<String, Object?>> patchCreate({
    String? projectPath,
    String? releaseId,
    String? flavor,
    String? entrypointPath,
  }) async {
    final result = await toolchain.patch(
      projectPath: projectPath,
      releaseId: releaseId,
      flavor: flavor,
      entrypointPath: entrypointPath,
    );
    final project = toolchain.project(projectPath: projectPath);
    return <String, Object?>{
      ..._patchJson(result.artifact, result.output, project.root),
      'sizeBytes': result.size,
      'created': true,
    };
  }

  Future<Map<String, Object?>> patchVerify({
    required String patchPath,
    String? projectPath,
    String? releaseId,
  }) async {
    final result = await toolchain.verify(
      file: File(patchPath),
      projectPath: projectPath,
      releaseId: releaseId,
    );
    final project = toolchain.project(projectPath: projectPath);
    return <String, Object?>{
      ..._patchJson(result.artifact, File(patchPath), project.root),
      'verified': true,
    };
  }

  Future<Map<String, Object?>> patchInspect({required String patchPath}) async {
    final result = toolchain.inspect(File(patchPath));
    return <String, Object?>{
      ..._patchJson(result.artifact, File(patchPath)),
      'verified': false,
    };
  }

  Future<Map<String, Object?>> deploy() async {
    throw const _McpOperationException(
      _McpError(
        code: 'MCP_CAPABILITY_UNSUPPORTED',
        summary: 'Authenticated deploy is unavailable through built-in MCP',
        detail:
            'There is no public authenticated delivery service in the current '
            'toolchain. MCP performs no network request and does not shell out.',
        action: 'Provide a public delivery service before registering a deploy implementation.',
      ),
    );
  }

  Future<Map<String, Object?>> rollback({
    String? projectPath,
    String? releaseId,
    String target = 'base',
  }) async {
    final result = await toolchain.rollback(
      projectPath: projectPath,
      releaseId: releaseId,
      target: target,
    );
    return <String, Object?>{
      'result': 'ROLLED_BACK',
      'target': result.state.target,
      'releaseId': result.release.releaseId,
      'baseArtifact': _pathLabel(result.baseArtifact, result.project.root),
      'highWaterSequence': result.state.highWaterSequence,
      'highWaterDigest': result.state.highWaterDigest,
      'state': _pathLabel(
        ToolStore(result.project)
            .rollbackStatePrimary(result.release.releaseId),
        result.project.root,
      ),
      'control': _pathLabel(result.commandFile, result.project.root),
      'keyId': result.keyId,
    };
  }

  Future<Map<String, Object?>> controlPlaneDiscovery({
    String? profileName,
  }) async {
    final profile = await _selectProfile(profileName);
    final document = await _discoveryClient.discover(profile.endpoint);
    return <String, Object?>{
      'profile': await _profileJson(profile),
      'discovery': document.toPublicJson(
        redactEndpoints: isManagedCloudEndpoint(profile.endpoint),
      ),
    };
  }

  Future<ControlPlaneProfile> _selectProfile(String? name) async {
    final catalog = await authStorage.readProfileCatalog();
    final selected = name ?? defaultProfileName;
    final profile = selected == null
        ? catalog.active
        : catalog.byName(selected);
    if (profile == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'A1025',
        summary: 'Profile does not exist',
        detail: 'The requested profile is not in the local catalog.',
        action: 'Run profile_list and select an available profile.',
      );
    }
    return profile;
  }

  Future<Map<String, Object?>> _profileJson(ControlPlaneProfile profile) async {
    final session = await authStorage.readSession(endpoint: profile.endpoint);
    final status = session == null
        ? 'NOT_LOGGED_IN'
        : session.isSessionExpired || session.isExpired
        ? 'EXPIRED'
        : 'LOGGED_IN';
    return <String, Object?>{
      'name': profile.name,
      ...profile.toPublicMetadataJson(),
      'auth': <String, Object?>{'status': status, 'host_bound': true},
    };
  }

  ReleaseRecord _selectRelease(ToolStore store, String? releaseId) {
    if (releaseId != null) return store.readRelease(releaseId);
    final records = store.listReleases();
    if (records.length == 1) return records.single;
    if (records.isEmpty) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'R5001',
        summary: 'No release baseline is available',
        detail: 'The local Hyfens store has no complete release baseline.',
        action: 'Create a release baseline or pass release_id explicitly.',
      );
    }
    throw ToolFailure.single(
      exitCode: ToolExitCode.compatibility,
      code: 'R5002',
      summary: 'Release target is ambiguous',
      detail: 'More than one complete release baseline is available.',
      action: 'Pass release_id explicitly.',
    );
  }
}

typedef _McpOperation = FutureOr<Map<String, Object?>> Function(
  Map<String, Object?> arguments,
);

final class _McpOperationException implements Exception {
  const _McpOperationException(this.error);

  final _McpError error;
}

final class _McpError {
  const _McpError({
    required this.code,
    required this.summary,
    required this.detail,
    this.action,
    this.exitCode,
    this.storeReleaseRequired = false,
  });

  final String code;
  final String summary;
  final String detail;
  final String? action;
  final int? exitCode;
  final bool storeReleaseRequired;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'summary': summary,
    'detail': detail,
    if (action != null) 'action': action,
    if (exitCode != null) 'exitCode': exitCode,
    if (storeReleaseRequired) 'storeReleaseRequired': true,
  };
}

CallToolResult _result(Map<String, Object?> value) => CallToolResult(
  content: <Content>[TextContent(text: jsonEncode(value))],
  structuredContent: value,
);

CallToolResult _errorResult(String operation, _McpError error) {
  final value = <String, Object?>{
    'ok': false,
    'operation': operation,
    'error': error.toJson(),
  };
  return CallToolResult(
    content: <Content>[TextContent(text: jsonEncode(value))],
    structuredContent: value,
    isError: true,
  );
}

ObjectSchema _emptySchema() => ObjectSchema(
  properties: const <String, Schema>{},
  additionalProperties: false,
);

ObjectSchema _schema(
  Map<String, Schema> properties, {
  List<String> required = const <String>[],
}) => ObjectSchema(
  properties: properties,
  required: required,
  additionalProperties: false,
);

StringSchema _pathSchema() => Schema.string(
  maxLength: 4096,
  description:
      'A bounded filesystem path without control characters or symlink roots.',
);

StringSchema _patchSchema() => Schema.string(
  minLength: 1,
  maxLength: 4096,
  description: 'Path to a local patch artifact.',
);

StringSchema _releaseSchema() =>
    Schema.string(minLength: 1, maxLength: 256, pattern: r'^[A-Za-z0-9:_-]+$');

StringSchema _profileSchema() => Schema.string(
  minLength: 1,
  maxLength: 64,
  pattern: r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$',
);

String? _optionalPath(Map<String, Object?> args, String name) {
  final value = _optionalString(args, name);
  return value == null ? null : _checkedPath(value, name);
}

String _requiredPath(Map<String, Object?> args, String name) =>
    _checkedPath(_requiredString(args, name), name);

String _checkedPath(String value, String name) {
  if (value.isEmpty ||
      value.length > 4096 ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw const _McpOperationException(
      _McpError(
        code: 'MCP_INVALID_PATH',
        summary: 'Filesystem path is invalid',
        detail: 'Paths must be bounded, non-empty, and contain no control characters.',
      ),
    );
  }
  if (p.normalize(value).isEmpty) {
    throw const _McpOperationException(
      _McpError(
        code: 'MCP_INVALID_PATH',
        summary: 'Filesystem path is invalid',
        detail: 'The normalized path is empty.',
      ),
    );
  }
  if (FileSystemEntity.typeSync(value, followLinks: false) ==
      FileSystemEntityType.link) {
    throw _McpOperationException(
      _McpError(
        code: 'MCP_INVALID_PATH',
        summary: 'Symlink paths are not accepted',
        detail: name + ' must be a regular path rather than a symlink.',
      ),
    );
  }
  return value;
}

String _requiredString(Map<String, Object?> args, String name) {
  final value = args[name];
  if (value is String && value.isNotEmpty) return value;
  throw _McpOperationException(
    _McpError(
      code: 'MCP_INVALID_PARAMS',
      summary: 'Required argument is missing',
      detail: name + ' must be a non-empty string.',
    ),
  );
}

String? _optionalString(Map<String, Object?> args, String name) {
  final value = args[name];
  if (value == null) return null;
  if (value is String) return value;
  throw _McpOperationException(
    _McpError(
      code: 'MCP_INVALID_PARAMS',
      summary: 'Argument type is invalid',
      detail: name + ' must be a string.',
    ),
  );
}

bool? _optionalBool(Map<String, Object?> args, String name) {
  final value = args[name];
  if (value == null) return null;
  if (value is bool) return value;
  throw _McpOperationException(
    _McpError(
      code: 'MCP_INVALID_PARAMS',
      summary: 'Argument type is invalid',
      detail: name + ' must be a boolean.',
    ),
  );
}

String _requiredProfile(Map<String, Object?> args, String name) {
  final value = _requiredString(args, name);
  _validateProfile(value);
  return value;
}

String? _optionalProfile(Map<String, Object?> args, String name) {
  final value = _optionalString(args, name);
  if (value == null) return null;
  _validateProfile(value);
  return value;
}

String? _optionalRelease(Map<String, Object?> args, String name) {
  final value = _optionalString(args, name);
  if (value == null) return null;
  if (!RegExp(r'^[A-Za-z0-9:_-]{1,256}$').hasMatch(value)) {
    throw const _McpOperationException(
      _McpError(
        code: 'MCP_INVALID_IDENTIFIER',
        summary: 'Release identifier is invalid',
        detail: 'release_id contains unsupported characters.',
      ),
    );
  }
  return value;
}

void _validateProfile(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(value)) {
    throw const _McpOperationException(
      _McpError(
        code: 'MCP_INVALID_PROFILE',
        summary: 'Profile name is invalid',
        detail: 'Profile names must use bounded ASCII identifier characters.',
      ),
    );
  }
}

String _safeCode(String value) =>
    RegExp(r'^[A-Z][A-Z0-9_-]{1,63}$').hasMatch(value)
    ? value
    : 'MCP_DOMAIN_ERROR';

String _safeText(String value, {int maxLength = 2048}) {
  var result = value
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ')
      .replaceAll(
        RegExp(
          r'(access[_-]?token|session[_-]?token|refresh[_-]?token|password|secret|authorization)\s*[:=]\s*[^\s,;]+',
          caseSensitive: false,
        ),
        r'$1=<redacted>',
      )
      .replaceAll(
        RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
        'Bearer <redacted>',
      );
  if (result.length > maxLength)
    result = result.substring(0, maxLength) + '...';
  return result;
}

Map<String, Object?> _projectJson(FlutterProject project) => <String, Object?>{
  'package': project.packageName,
  'applicationId': project.applicationId,
  if (project.version != null) 'version': _safeText(project.version!),
  'root': '<project>',
};

Map<String, Object?> _releaseJson(ReleaseRecord release) => <String, Object?>{
  'releaseId': release.releaseId,
  'applicationId': release.applicationId,
  'target': release.target,
  'entrypoint': release.entrypointPath,
  'flavor': release.flavor,
  'architecture': release.architecture,
  'buildMode': release.buildMode,
  'toolVersion': release.toolVersion,
  'flutterVersion': release.flutterVersion,
  'dartVersion': release.dartVersion,
  'buildFingerprint': release.buildFingerprint,
  'sourceFingerprint': release.sourceFingerprint,
  'graphFingerprint': release.graphFingerprint,
  'manifest': <String, Object?>{
    'runtimeCompatibilityVersion': release.manifest.runtimeCompatibilityVersion,
    'patchFormatVersion': release.manifest.patchFormatVersion,
    'functionCount': release.manifest.functions.length,
    'capabilityCount': release.manifest.capabilities.length,
    'packageCount': release.manifest.packages.length,
    'sourceUnitCount': release.manifest.sourceUnits.length,
  },
  'sourceCount': release.sources.length,
  'functionCount': release.functions.length,
  'diagnosticCount': release.diagnostics.length,
  'build': _safe(release.build),
};

Map<String, Object?> _patchJson(
  PatchArtifact artifact,
  File file, [
  Directory? project,
]) => <String, Object?>{
  'path': _pathLabel(file, project),
  'formatVersion': patchFormatV1,
  'runtimeCompatibilityVersion': artifact.runtimeCompatibilityVersion,
  'applicationId': artifact.applicationId,
  'releaseId': artifact.releaseId,
  'patchId': artifact.patchId,
  'sequence': artifact.sequence,
  'functionCount': artifact.functions.length,
  'functions': artifact.functions.map((item) => _safe(item.toJson())).toList(),
  'capabilityCount': artifact.capabilities.length,
  'artifactBytes': PatchFormatV1.encode(artifact).length,
  'payloadDigest': base64.encode(artifact.payloadDigest),
  'signatureAlgorithm': artifact.signatureMetadata.algorithm,
  'keyId': artifact.signatureMetadata.keyId,
  'extensionTypes': artifact.extensions.map((item) => item.type).toList(),
};

String _pathLabel(FileSystemEntity entity, [Directory? project]) {
  if (project != null) {
    try {
      return relativePath(project, entity);
    } on Object {
      // An explicitly supplied external patch is represented by its basename.
    }
  }
  final name = p.basename(entity.path);
  return name.isEmpty ? '<file>' : name;
}

Map<String, Object?> _safeMap(Map<String, Object?> value) =>
    _safe(value) as Map<String, Object?>;

Object? _safe(Object? value, {String? key}) {
  if (key != null &&
      RegExp(
        r'(access[_-]?token|session[_-]?token|refresh[_-]?token|password|secret|credential|private[_-]?key|authorization|bearer)',
        caseSensitive: false,
      ).hasMatch(key)) {
    return '<redacted>';
  }
  if (value == null || value is bool || value is num) return value;
  if (value is String) return _safeText(value);
  if (value is List) return value.take(256).map(_safe).toList();
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is String) {
        final name = entry.key! as String;
        result[name] = _safe(entry.value, key: name);
      }
    }
    return result;
  }
  return _safeText(value.toString());
}
