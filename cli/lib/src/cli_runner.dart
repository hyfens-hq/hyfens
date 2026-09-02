import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:path/path.dart' as p;

import 'auth_client.dart';
import 'auth_command.dart';
import 'auth_storage.dart';
import 'canonical.dart';
import 'configuration.dart';
import 'control_plane_delivery.dart';
import 'diagnostics.dart';
import 'mcp/mcp_server.dart';
import 'profile.dart';
import 'project_initialization.dart';
import 'server.dart';
import 'signing.dart';
import 'toolchain.dart';

final class HyfensCommandRunner extends CommandRunner<void> {
  HyfensCommandRunner({
    bool deprecatedToolShim = false,
    HyfensToolchain? toolchain,
    AuthClient? authClient,
    AuthStorage? authStorage,
    AuthPrompt? authPrompt,
    AuthBrowserLauncher? authBrowserLauncher,
    AuthSleeper? authSleeper,
    IOSink? out,
    IOSink? err,
  }) : _deprecatedToolShim = deprecatedToolShim,
       toolchain = toolchain ?? HyfensToolchain(),
       authClient =
           authClient ??
           AuthClient(
             storage: authStorage ?? AuthStorage(),
             browserLauncher: authBrowserLauncher,
             sleeper: authSleeper,
           ),
       authPrompt = authPrompt ?? defaultAuthPrompt,
       out = out ?? stdout,
       err = err ?? stderr,
       super(
         'hyfens',
         'Hyfens — Flutter live-update tooling.',
         usageLineLength: 100,
       ) {
    argParser
      ..addFlag('verbose', help: 'Show detailed Hyfens diagnostics.')
      ..addFlag('json', help: 'Emit machine-readable JSON where supported.')
      ..addOption('project', help: 'Flutter project directory or pubspec path.')
      ..addFlag('no-color', help: 'Disable colored output.')
      ..addFlag('non-interactive', help: 'Fail instead of prompting.')
      ..addFlag(
        'version',
        abbr: 'v',
        help: 'Print the Hyfens CLI version.',
        negatable: false,
      );
    addCommand(VersionCommand(this));
    addCommand(DoctorCommand(this));
    addCommand(StatusCommand(this));
    addCommand(McpCommand(this));
    addCommand(LoginCommand(this));
    addCommand(LogoutCommand(this));
    addCommand(ProfileCommand(this));
    addCommand(AuthCommand(this));
    addCommand(InitCommand(this));
    addCommand(AnalyzeCommand(this));
    addCommand(ReleaseCommand(this));
    addCommand(PatchCommand(this));
    addCommand(RollbackCommand(this));
    addCommand(CleanupCommand(this));
    addCommand(InspectCommand(this));
    addCommand(VerifyCommand(this));
    addCommand(KeysCommand(this));
    addCommand(ServeCommand(this));
    addCommand(DeployCommand(this));
    addCommand(RolloutCommand(this));
    addCommand(BundleCommand(this));
  }

  final bool _deprecatedToolShim;
  final HyfensToolchain toolchain;
  final AuthClient authClient;
  final AuthPrompt authPrompt;
  final IOSink out;
  final IOSink err;

  bool _verbose = false;
  bool _json = false;

  bool get verbose => _verbose;
  bool get jsonMode => _json;

  @override
  Future<void> run(Iterable<String> arguments) async {
    final normalizedArguments = arguments.toList(growable: false);
    _verbose = normalizedArguments.contains('--verbose');
    _json = normalizedArguments.contains('--json');
    if (normalizedArguments.length == 1 &&
        (normalizedArguments.single == '--version' ||
            normalizedArguments.single == '-v')) {
      writeVersion();
      return;
    }
    await super.run(normalizedArguments);
  }

  void write(Object value) => out.writeln(value);

  void writeJson(Object value) => out.writeln(jsonEncode(value));

  void writeVersion() {
    write(
      _deprecatedToolShim ? hyfensToolVersion : 'hyfens $hyfensToolVersion',
    );
  }

  @override
  void printUsage() {
    write(usage);
    write('');
    write('Examples:');
    write('  hyfens login');
    write('  hyfens release android --metadata-only');
    write('  hyfens patch android');
    write('  hyfens mcp --profile acme');
    write('');
    write('Documentation: https://github.com/hyfens-hq/hyfens/tree/main/docs');
  }

  void writeDiagnosticReport(DiagnosticReport report) {
    if (jsonMode) {
      writeJson(report.toJson());
    } else {
      for (final diagnostic in report.diagnostics) write(diagnostic.render());
    }
  }
}

/// Shared executable boundary for both the canonical `hyfens` binary and the
/// deprecated `tool` shim. There is deliberately one command runner.
Future<void> runHyfensCli(
  List<String> arguments, {
  bool deprecatedToolShim = false,
  IOSink? out,
  IOSink? err,
}) async {
  final output = out ?? stdout;
  final errors = err ?? stderr;
  if (deprecatedToolShim) {
    errors.writeln('tool is deprecated; use hyfens');
  }
  final runner = HyfensCommandRunner(
    deprecatedToolShim: deprecatedToolShim,
    out: output,
    err: errors,
  );
  try {
    await runner.run(arguments);
  } on ToolFailure catch (error) {
    for (final diagnostic in error.diagnostics) {
      errors.writeln(diagnostic.render());
    }
    exitCode = error.exitCode.value;
  } on UsageException catch (error) {
    errors.writeln(error.message);
    errors.writeln(error.usage);
    exitCode = ToolExitCode.usage.value;
  } on Object catch (error, stackTrace) {
    errors.writeln('ERROR T9999');
    errors.writeln('  Unexpected Hyfens failure');
    errors.writeln('  $error');
    if (runner.verbose) errors.writeln(stackTrace);
    exitCode = ToolExitCode.internal.value;
  }
}

abstract base class _ToolCommand extends Command<void> {
  _ToolCommand(this.runner) {
    argParser
      ..addFlag('json', help: 'Emit machine-readable JSON.')
      ..addOption(
        'project',
        help: 'Flutter project directory or pubspec path.',
      );
  }

  final HyfensCommandRunner runner;

  @override
  void printUsage() => runner.write(usage);

  bool get jsonMode => runner.jsonMode || argResults?['json'] == true;
  String? get projectPath =>
      argResults?['project'] as String? ?? globalResults?['project'] as String?;
}

final class VersionCommand extends Command<void> {
  VersionCommand(this.runner);

  final HyfensCommandRunner runner;

  @override
  String get name => 'version';

  @override
  String get description => 'Print the Hyfens CLI version.';

  @override
  void printUsage() => runner.write(usage);

  @override
  Future<void> run() async => runner.writeVersion();
}

final class McpCommand extends Command<void> {
  McpCommand(this.runner) {
    argParser
      ..addOption(
        'profile',
        help:
            'Use this host-bound Hyfens profile instead of the active profile.',
      )
      ..addFlag(
        'debug',
        help: 'Write diagnostic information to stderr.',
        negatable: false,
      );
  }

  final HyfensCommandRunner runner;

  @override
  String get name => 'mcp';

  @override
  String get description =>
      'Start the Hyfens MCP server for AI coding agents over stdio.';

  @override
  void printUsage() {
    runner.write(usage);
    runner.write('');
    runner.write(
      'Transport: local MCP over stdio; stdout is reserved for protocol messages.',
    );
    runner.write(
      'Profile: uses the active host-bound profile, or --profile NAME.',
    );
    runner.write('Authentication: run hyfens login before launching an agent.');
    runner.write(
      'Debug: --debug writes diagnostics to stderr and never to protocol stdout.',
    );
  }

  @override
  Future<void> run() async {
    await runHyfensMcp(
      toolchain: runner.toolchain,
      authStorage: runner.authClient.storage,
      authClient: runner.authClient,
      profileName: argResults!['profile'] as String?,
      debug: argResults!['debug'] as bool,
      output: runner.out,
      log: runner.err,
    );
  }
}

final class DoctorCommand extends _ToolCommand {
  DoctorCommand(super.runner);

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Inspect the local Flutter OTA toolchain environment.';

  @override
  Future<void> run() async {
    final project = runner.toolchain.project(projectPath: projectPath);
    final environment = await runner.toolchain.doctor(projectPath: projectPath);
    final binding = HyfensProjectBinding.load(project.hyfensConfigFile);
    if (binding?.runtimeApplicationId != null &&
        binding!.runtimeApplicationId != project.applicationId) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'H1205',
        summary: 'Project application identity does not match hyfens.yaml',
        detail: '${project.applicationId} != ${binding.runtimeApplicationId}',
        action: 'Run hyfens init --force after reviewing the exact identity.',
      );
    }
    final data = <String, Object?>{
      'projectRoot': project.root.path,
      'applicationId': project.applicationId,
      'pubspec': 'SUPPORTED',
      'pubspecLock': project.pubspecLockFile.existsSync()
          ? 'SUPPORTED'
          : 'WARNING',
      'packageConfig': project.packageConfigFile == null
          ? 'WARNING'
          : 'SUPPORTED',
      'androidProject': Directory('${project.root.path}/android').existsSync()
          ? 'NOT TESTED'
          : 'NOT AVAILABLE',
      'iosProject': Directory('${project.root.path}/ios').existsSync()
          ? 'NOT TESTED'
          : 'NOT AVAILABLE',
      'hyfensBinding': binding == null ? 'NOT_INITIALIZED' : 'SUPPORTED',
      ...environment.toJson(),
      'result':
          environment.flutterStatus == 'SUPPORTED' &&
              environment.dartStatus == 'SUPPORTED' &&
              environment.runtimeStatus == 'SUPPORTED'
          ? 'READY'
          : 'WARNING',
    };
    if (jsonMode) {
      runner.writeJson(data);
      return;
    }
    runner.write('Flutter OTA Doctor');
    runner.write('');
    runner.write(
      'Flutter       ${environment.flutterVersion.padRight(12)} ${environment.flutterStatus}',
    );
    runner.write(
      'Dart          ${environment.dartVersion.padRight(12)} ${environment.dartStatus}',
    );
    runner.write('Project       ${project.root.path.padRight(12)} SUPPORTED');
    runner.write('Android       ${environment.androidStatus}');
    runner.write('Xcode         ${environment.xcodeStatus}');
    runner.write('Git           ${environment.gitStatus}');
    runner.write('Package graph ${data['packageConfig']}');
    runner.write('Patch runtime ${environment.runtimeStatus}');
    runner.write('');
    runner.write('Result: ${data['result']}');
  }
}

final class StatusCommand extends _ToolCommand {
  StatusCommand(super.runner);

  @override
  String get name => 'status';

  @override
  String get description =>
      'Show bounded local toolchain and artifact status without app introspection.';

  @override
  Future<void> run() async {
    late final ToolStatus status;
    try {
      status = await runner.toolchain.status(projectPath: projectPath);
    } on ToolFailure catch (failure) {
      final code = failure.diagnostics.first.code;
      if (projectPath != null || !<String>{'T1001', 'T1005'}.contains(code)) {
        rethrow;
      }
      await _writeProfileOnlyStatus(runner, jsonMode: jsonMode);
      return;
    }
    final profile = await runner.authClient.storage.readActiveProfile();
    final session = await runner.authClient.storage.readSession(
      endpoint: profile.endpoint,
    );
    final auth = <String, Object?>{
      'profile': profile.toJson(),
      'session': <String, Object?>{
        'status': session == null
            ? 'NOT_LOGGED_IN'
            : session.isSessionExpired
            ? 'EXPIRED'
            : 'LOGGED_IN',
        if (session?.expiresAt != null)
          'access_expires_at': session!.expiresAt!.toUtc().toIso8601String(),
        if (session?.sessionExpiresAt != null)
          'session_expires_at': session!.sessionExpiresAt!
              .toUtc()
              .toIso8601String(),
      },
    };
    if (jsonMode) {
      runner.writeJson(<String, Object?>{...status.toJson(), 'auth': auth});
      return;
    }
    final store = status.store;
    final environment = status.environment;
    runner.write('Hyfens local status');
    runner.write('');
    runner.write('Result:       ${status.result}');
    runner.write('Project:      ${status.projectPackage}');
    runner.write('Application:  ${status.applicationId}');
    runner.write('Configuration: ${status.configurationStatus}');
    runner.write('Store:        ${store.status}');
    runner.write(
      '  Releases:   ${store.releaseDirectories} directory(s), ${store.releaseMetadataFiles} metadata file(s)',
    );
    runner.write(
      '  Patches:    ${store.patchDirectories} release directory(s), ${store.patchArtifacts} artifact file(s)',
    );
    runner.write(
      'Flutter:      ${environment.flutterVersion} ${environment.flutterStatus}',
    );
    runner.write(
      'Dart:         ${environment.dartVersion} ${environment.dartStatus}',
    );
    runner.write('Runtime pkg:  ${environment.runtimeStatus}');
    runner.write('Profile:      ${profile.name} (${profile.endpoint})');
    runner.write('Auth session: ${auth['session']! as Map<String, Object?>}');
    runner.write(
      'App runtime:  ${status.applicationRuntimeStatus} (local tool only; introspection unavailable)',
    );
    if (store.scanTruncated) {
      runner.write(
        'Inventory:    bounded before all local entries were counted',
      );
    }
    if (status.diagnostics.isNotEmpty) {
      runner.write('');
      runner.write('Diagnostics:');
      for (final diagnostic in status.diagnostics) {
        runner.write(diagnostic.render());
      }
    }
  }

  Future<void> _writeProfileOnlyStatus(
    HyfensCommandRunner runner, {
    required bool jsonMode,
  }) async {
    final profile = await runner.authClient.storage.readActiveProfile();
    final session = await runner.authClient.storage.readSession(
      endpoint: profile.endpoint,
    );
    final auth = <String, Object?>{
      'profile': profile.toJson(),
      'session': session == null
          ? 'NOT_LOGGED_IN'
          : session.isSessionExpired
          ? 'EXPIRED'
          : 'LOGGED_IN',
    };
    if (jsonMode) {
      runner.writeJson(<String, Object?>{
        'schemaVersion': 1,
        'result': 'NOT_INITIALIZED',
        'project': null,
        'configuration': <String, String>{'status': 'NOT_INITIALIZED'},
        'auth': auth,
      });
    } else {
      runner.write('Hyfens status');
      runner.write('Result:       NOT_INITIALIZED');
      runner.write('Profile:      ${profile.name} (${profile.endpoint})');
      runner.write('Auth session: ${auth['session']}');
      runner.write('Project:      no Flutter project found');
    }
  }
}

final class InitCommand extends _ToolCommand {
  InitCommand(super.runner) {
    argParser
      ..addFlag('dry-run', help: 'Show changes without modifying the project.')
      ..addFlag('force', help: 'Replace the tool-owned metadata after review.');
  }

  @override
  String get name => 'init';

  @override
  String get description =>
      'Initialize local Hyfens metadata and configuration.';

  @override
  Future<void> run() async {
    final initialization =
        await ProjectInitializationService(
          toolchain: runner.toolchain,
          authStorage: runner.authClient.storage,
        ).initialize(
          projectPath: projectPath,
          dryRun: argResults!['dry-run'] as bool,
          force: argResults!['force'] as bool,
        );
    final result = initialization.result;
    final binding = initialization.binding;
    final activeProfile = await runner.authClient.storage.readActiveProfile();
    final actions = initialization.actions;
    final data = <String, Object?>{
      'projectRoot': result.project.root.path,
      'dryRun': result.dryRun,
      'flutterVersion': result.environment.flutterVersion,
      'dartVersion': result.environment.dartVersion,
      'profile': activeProfile.toJson(),
      'binding': binding.toJson(),
      'actions': actions,
    };
    if (jsonMode) {
      runner.writeJson(data);
      return;
    }
    runner.write(
      result.dryRun
          ? 'Dry run: no files modified.'
          : 'Initialized OTA support.',
    );
    runner.write('');
    runner.write('Project: ${result.project.root.path}');
    runner.write(
      'Toolchain: Flutter ${result.environment.flutterVersion}, Dart ${result.environment.dartVersion}',
    );
    runner.write('Created/updated:');
    for (final action in actions) runner.write('  $action');
    runner.write('');
    runner.write('No Flutter SDK files modified.');
    runner.write('No private signing key was generated.');
    runner.write('Next: hyfens keys generate');
    runner.write('Next: hyfens release android --metadata-only');
  }
}

final class AnalyzeCommand extends _ToolCommand {
  AnalyzeCommand(super.runner) {
    argParser.addOption('release', help: 'Exact release baseline ID.');
  }

  @override
  String get name => 'analyze';

  @override
  String get description =>
      'Classify current project changes against a release baseline.';

  @override
  Future<void> run() async {
    final result = runner.toolchain.analyze(
      projectPath: projectPath,
      releaseId: argResults!['release'] as String?,
    );
    if (jsonMode) {
      runner.writeJson(result.toJson());
      return;
    }
    runner.write(
      'Analyzing changes against release ${result.release.releaseId}...',
    );
    runner.write('');
    for (final item in result.items) {
      runner.write(_classificationLabel(item.classification));
      final location = item.line == null
          ? item.path
          : '${item.path}:${item.line}:${item.column ?? 1}';
      runner.write('  $location');
      runner.write('    ${item.detail}');
    }
    if (result.items.isEmpty) runner.write('NO_EFFECT\n  No changes detected.');
    if (result.diagnostics.isNotEmpty) {
      runner.write('');
      final errors = result.diagnostics
          .where(
            (diagnostic) => diagnostic.severity == DiagnosticSeverity.error,
          )
          .toList(growable: false);
      final warnings = result.diagnostics
          .where(
            (diagnostic) => diagnostic.severity == DiagnosticSeverity.warning,
          )
          .toList(growable: false);
      for (final diagnostic in errors) runner.write(diagnostic.render());
      if (warnings.isNotEmpty) {
        runner.write(
          'Warnings: ${warnings.length} declaration(s) are outside the current patchable subset.',
        );
        if (runner.verbose) {
          for (final diagnostic in warnings) runner.write(diagnostic.render());
        } else {
          runner.write('Use --verbose to show excluded declarations.');
        }
      }
    }
    runner.write('');
    runner.write(
      result.canPatch ? 'Result: PATCHABLE' : 'Result: PATCH BLOCKED',
    );
  }
}

String _classificationLabel(ChangeClassification classification) =>
    switch (classification) {
      ChangeClassification.patchable => 'PATCHABLE',
      ChangeClassification.unsupported => 'UNSUPPORTED',
      ChangeClassification.storeReleaseRequired => 'STORE RELEASE REQUIRED',
      ChangeClassification.noEffect => 'NO EFFECT',
      ChangeClassification.unknown => 'UNKNOWN',
    };

final class ReleaseCommand extends _ToolCommand {
  ReleaseCommand(super.runner) {
    argParser
      ..addFlag(
        'metadata-only',
        help: 'Create a baseline without running Flutter build.',
      )
      ..addOption('architecture', defaultsTo: 'arm64')
      ..addOption('mode', defaultsTo: 'release');
  }

  @override
  String get name => 'release';

  @override
  String get description => 'Create a target-specific local release baseline.';

  @override
  Future<void> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('release requires android or ios', usage);
    }
    final target = argResults!.rest.single;
    final record = await runner.toolchain.release(
      target: target,
      projectPath: projectPath,
      architecture: argResults!['architecture'] as String,
      buildMode: argResults!['mode'] as String,
      metadataOnly: argResults!['metadata-only'] as bool,
    );
    final data = <String, Object?>{
      'releaseId': record.releaseId,
      'applicationId': record.applicationId,
      'target': record.target,
      'architecture': record.architecture,
      'buildFingerprint': record.buildFingerprint,
      'functions': record.functions.length,
      'sourceUnits': record.sources.length,
      'build': record.build,
      if (record.build['artifact'] is String)
        'artifactPath': p.join(
          '.tool',
          'releases',
          record.releaseId,
          'artifacts',
          record.build['artifact']! as String,
        ),
    };
    if (jsonMode) {
      runner.writeJson(data);
      return;
    }
    runner.write('Release baseline created');
    runner.write('  Release:       ${record.releaseId}');
    runner.write('  Application:   ${record.applicationId}');
    runner.write(
      '  Target:        ${record.target}-${record.architecture}-${record.buildMode}',
    );
    runner.write('  Functions:     ${record.functions.length}');
    runner.write('  Source units:  ${record.sources.length}');
    runner.write('  Build:         ${record.build['status']}');
    final artifact = record.build['artifact'];
    if (artifact is String) {
      runner.write(
        '  Artifact:      ${p.join('.tool', 'releases', record.releaseId, 'artifacts', artifact)}',
      );
    }
    if (runner.verbose) {
      final selected = record.sources.where((item) => item.selected).length;
      final instrumented = record.sources
          .where((item) => item.instrumented)
          .length;
      runner.write('');
      runner.write('Instrumentation plan');
      runner.write('  Eligible units: $selected');
      runner.write('  Instrumented:   $instrumented');
      runner.write(
        '  Skipped:         ${record.sources.length - instrumented}',
      );
      final skipped = <String, int>{};
      for (final source in record.sources.where((item) => !item.instrumented)) {
        final reason = source.exclusions.isEmpty
            ? 'not selected'
            : source.exclusions.first.split(':').last.trim();
        skipped[reason] = (skipped[reason] ?? 0) + 1;
      }
      if (skipped.isNotEmpty) {
        runner.write('  Skip reasons:');
        for (final entry
            in skipped.entries.toList()
              ..sort((left, right) => left.key.compareTo(right.key))) {
          runner.write('    ${entry.key}: ${entry.value}');
        }
      }
    }
  }
}

final class PatchCommand extends _ToolCommand {
  PatchCommand(super.runner) {
    argParser.addOption('release', help: 'Exact release baseline ID.');
  }

  @override
  String get name => 'patch';

  @override
  String get description =>
      'Analyze, compile, sign, and verify a local patch artifact.';

  @override
  Future<void> run() async {
    final targets = argResults!.rest;
    if (targets.length > 1 ||
        targets.any((target) => target != 'android' && target != 'ios')) {
      throw UsageException('patch accepts only android or ios', usage);
    }
    var releaseId = argResults!['release'] as String?;
    if (targets.isNotEmpty) {
      final target = targets.single;
      final project = runner.toolchain.project(projectPath: projectPath);
      final store = ToolStore(project);
      if (releaseId != null) {
        final release = store.readRelease(releaseId);
        if (release.target != target) {
          throw ToolFailure.single(
            exitCode: ToolExitCode.compatibility,
            code: 'R5002',
            summary: 'Release target does not match requested platform',
            detail: '${release.target} != $target',
            action:
                'Pass the exact $target release ID or run hyfens release $target first.',
          );
        }
      } else {
        final matches = store
            .listReleases()
            .where((release) => release.target == target)
            .toList(growable: false);
        if (matches.isEmpty) {
          throw ToolFailure.single(
            exitCode: ToolExitCode.compatibility,
            code: 'R5001',
            summary:
                'No release baseline is available for the requested platform',
            detail: target,
            action: 'Run hyfens release $target first.',
          );
        }
        if (matches.length > 1) {
          throw ToolFailure.single(
            exitCode: ToolExitCode.compatibility,
            code: 'R5002',
            summary: 'Release target is ambiguous for the requested platform',
            detail: matches.map((release) => release.releaseId).join(', '),
            action: 'Pass --release <release-id> explicitly.',
          );
        }
        releaseId = matches.single.releaseId;
      }
    }
    final result = await runner.toolchain.patch(
      projectPath: projectPath,
      releaseId: releaseId,
    );
    final data = <String, Object?>{
      'output': result.output.path,
      'releaseId': result.artifact.releaseId,
      'patchId': result.artifact.patchId,
      'sequence': result.artifact.sequence,
      'size': result.size,
      'keyId': result.artifact.signatureMetadata.keyId,
      'signature': 'verified',
    };
    if (jsonMode) {
      runner.writeJson(data);
      return;
    }
    runner.write('Patch created');
    runner.write('  Release:   ${result.artifact.releaseId}');
    runner.write('  Patch:     ${result.artifact.patchId}');
    runner.write('  Sequence:  ${result.artifact.sequence}');
    runner.write('  Size:      ${result.size} bytes');
    runner.write('  Key ID:    ${result.artifact.signatureMetadata.keyId}');
    runner.write('  Signature: verified');
    runner.write('  Output:    ${result.output.path}');
  }
}

final class RollbackCommand extends _ToolCommand {
  RollbackCommand(super.runner) {
    argParser
      ..addOption('release', help: 'Exact release baseline ID.')
      ..addOption(
        'to',
        defaultsTo: 'base',
        help: 'Rollback target; only the trusted store-installed AOT base is supported.',
      );
  }

  @override
  String get name => 'rollback';

  @override
  String get description =>
      'Record an explicit rollback to the trusted store-installed AOT base.';

  @override
  Future<void> run() async {
    final result = await runner.toolchain.rollback(
      projectPath: projectPath,
      releaseId: argResults!['release'] as String?,
      target: argResults!['to'] as String,
    );
    if (jsonMode) {
      runner.writeJson(result.toJson());
      return;
    }
    runner.write('Rollback recorded');
    runner.write('  Release:       ${result.release.releaseId}');
    runner.write('  Target:        ${result.state.target}');
    runner.write(
      '  AOT base:      ${displayRelative(result.baseArtifact, result.project.root)}',
    );
    runner.write(
      '  High-water:    ${result.state.highWaterSequence} (retained)',
    );
    runner.write(
      '  Journal:       ${displayRelative(ToolStore(result.project).rollbackStatePrimary(result.release.releaseId), result.project.root)}',
    );
    runner.write(
      '  Control:       ${displayRelative(result.commandFile, result.project.root)}',
    );
    runner.write(
      '  Signature:     verified by the release trust key ${result.keyId}',
    );
    runner.write('  Patch files and sequence evidence were preserved.');
  }
}

final class CleanupCommand extends _ToolCommand {
  CleanupCommand(super.runner) {
    argParser
      ..addOption('scope', help: 'Exact cleanup scope: builds or patches.')
      ..addOption('release', help: 'Exact release baseline ID.')
      ..addOption(
        'confirm',
        help: 'Repeat the exact release ID to confirm this cleanup target.',
      );
  }

  @override
  String get name => 'cleanup';

  @override
  String get description =>
      'Remove one explicitly confirmed mutable build or patch target.';

  @override
  Future<void> run() async {
    final scope = argResults!['scope'] as String?;
    if (scope == null || scope.isEmpty) {
      throw UsageException('cleanup requires --scope builds|patches', usage);
    }
    final result = await runner.toolchain.cleanup(
      scope: scope,
      projectPath: projectPath,
      releaseId: argResults!['release'] as String?,
      confirmation: argResults!['confirm'] as String?,
    );
    if (jsonMode) {
      runner.writeJson(result.toJson());
      return;
    }
    runner.write('Cleanup completed');
    runner.write('  Scope:   ${result.scope}');
    runner.write('  Release: ${result.release.releaseId}');
    runner.write('  Removed: ${result.removedPaths.length} path(s)');
    for (final path in result.removedPaths) runner.write('    $path');
    runner.write('  Retained protected state/evidence:');
    for (final path in result.retainedPaths) runner.write('    $path');
  }
}

final class InspectCommand extends _ToolCommand {
  InspectCommand(super.runner);

  @override
  String get name => 'inspect';

  @override
  String get description =>
      'Inspect a Patch Format v1 artifact without executing it.';

  @override
  Future<void> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('inspect requires one patch path', usage);
    }
    final inspection = runner.toolchain.inspect(File(argResults!.rest.single));
    if (jsonMode) {
      runner.writeJson(inspection.toJson());
      return;
    }
    final artifact = inspection.artifact;
    runner.write('Patch Format v1');
    runner.write('  Runtime:     ${artifact.runtimeCompatibilityVersion}');
    runner.write('  Application: ${artifact.applicationId}');
    runner.write('  Release:     ${artifact.releaseId}');
    runner.write('  Patch:       ${artifact.patchId}');
    runner.write('  Sequence:    ${artifact.sequence}');
    runner.write('  Functions:   ${artifact.functions.length}');
    runner.write('  Capabilities:${artifact.capabilities.length}');
    runner.write(
      '  Artifact:    ${PatchFormatV1.encode(artifact).length} bytes',
    );
    runner.write('  Digest:      ${base64.encode(artifact.payloadDigest)}');
    runner.write(
      '  Signature:   ${artifact.signatureMetadata.algorithm} ${artifact.signatureMetadata.keyId}',
    );
    runner.write(
      '  Extensions:  ${artifact.extensions.map((item) => item.type).join(', ')}',
    );
  }
}

final class VerifyCommand extends _ToolCommand {
  VerifyCommand(super.runner) {
    argParser.addOption(
      'release',
      help: 'Verify compatibility against an exact local release.',
    );
  }

  @override
  String get name => 'verify';

  @override
  String get description =>
      'Verify a patch digest, signature, and optional release compatibility.';

  @override
  Future<void> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('verify requires one patch path', usage);
    }
    final inspection = await runner.toolchain.verify(
      file: File(argResults!.rest.single),
      projectPath: projectPath,
      releaseId: argResults!['release'] as String?,
    );
    final data = <String, Object?>{
      'path': inspection.path,
      'result': 'VERIFIED',
      'releaseId': inspection.artifact.releaseId,
      'keyId': inspection.artifact.signatureMetadata.keyId,
    };
    if (jsonMode) {
      runner.writeJson(data);
    } else {
      runner.write('Verified');
      runner.write('  Release:   ${inspection.artifact.releaseId}');
      runner.write(
        '  Signature: ${inspection.artifact.signatureMetadata.keyId}',
      );
    }
  }
}

final class ServeCommand extends _ToolCommand {
  ServeCommand(super.runner) {
    argParser
      ..addOption('host', defaultsTo: '127.0.0.1')
      ..addOption('port', defaultsTo: '18080')
      ..addOption('release', help: 'Serve one exact release baseline.')
      ..addFlag(
        'allow-lan',
        help: 'Explicitly allow a local-network bind for physical-device testing.',
      );
  }

  @override
  String get name => 'serve';

  @override
  String get description =>
      'Serve local verified patch artifacts for development only.';

  @override
  Future<void> run() async {
    final port = int.tryParse(argResults!['port'] as String);
    if (port == null)
      throw UsageException('serve --port must be an integer', usage);
    final host = argResults!['host'] as String;
    final release = argResults!['release'] as String?;
    final server = PatchDevelopmentServer(
      project: runner.toolchain.project(projectPath: projectPath),
      releaseId: release,
    );
    final bound = await server.bind(
      host: host,
      port: port,
      allowLan: argResults!['allow-lan'] as bool,
    );
    runner.write(
      'Local patch server listening on ${bound.address.host}:${bound.port}',
    );
    runner.write(
      'Development-only; no authentication or hosted service is enabled.',
    );
    try {
      await for (final request in bound) {
        // Reuse the same server instance while keeping the public command
        // boundary intentionally small.
        await server.handleRequest(request);
      }
    } finally {
      await bound.close(force: true);
    }
  }
}

const _rolloutActionNames = <String>[
  'ready',
  'startInternal',
  'startCanary',
  'startExpanding',
  'expand',
  'pause',
  'resume',
  'halt',
  'complete',
  'retire',
];

const _rolloutCohortKindNames = <String>['percentage', 'internal'];

final class RolloutCommand extends _ToolCommand {
  RolloutCommand(super.runner) {
    addSubcommand(RolloutCreateCommand(runner));
    addSubcommand(RolloutInspectCommand(runner));
    addSubcommand(RolloutTransitionCommand(runner));
  }

  @override
  String get name => 'rollout';

  @override
  String get description =>
      'Create, inspect, and explicitly transition a local control-plane rollout.';

  @override
  Future<void> run() async {}
}

final class RolloutCreateCommand extends _ToolCommand {
  RolloutCreateCommand(super.runner) {
    argParser
      ..addOption(
        'endpoint',
        help: 'Self-hosted control-plane URL or HYFENS_CONTROL_PLANE_URL.',
      )
      ..addOption(
        'token',
        help: 'Explicit token or HYFENS_TOKEN (legacy HYFENS_CONTROL_TOKEN is also accepted); otherwise use hyfens login.',
      )
      ..addOption(
        'organization-id',
        help: 'Organization ID or HYFENS_ORGANIZATION_ID.',
      )
      ..addOption(
        'application-id',
        help: 'Application ID or HYFENS_APPLICATION_ID.',
      )
      ..addOption(
        'environment-id',
        help: 'Environment ID or HYFENS_ENVIRONMENT_ID.',
      )
      ..addOption('platform-id', help: 'Platform ID or HYFENS_PLATFORM_ID.')
      ..addOption('release-id', help: 'Release ID or HYFENS_RELEASE_ID.')
      ..addOption('patch-id', help: 'Patch ID or HYFENS_PATCH_ID.')
      ..addOption(
        'percentage-basis-points',
        help: 'Initial rollout percentage in basis points.',
      )
      ..addOption(
        'cohort-kind',
        allowed: _rolloutCohortKindNames,
        help: 'Rollout cohort kind: percentage or internal.',
      )
      ..addMultiOption(
        'internal-installation-hash',
        help: 'Repeatable SHA-256 installation hash for an internal cohort.',
      )
      ..addOption(
        'idempotency-key',
        help: 'Idempotency key or HYFENS_IDEMPOTENCY_KEY.',
      )
      ..addOption('ca-cert', help: 'PEM CA certificate or HYFENS_TLS_CA_CERT.');
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create one authenticated rollout snapshot.';

  @override
  Future<void> run() async {
    final endpointValue = _rolloutOptionOrEnvironment(
      argResults,
      globalResults,
      'endpoint',
      'HYFENS_CONTROL_PLANE_URL',
    );
    final auth = await _resolveControlPlaneRequest(
      runner: runner,
      endpoint: endpointValue == null
          ? null
          : _rolloutEndpoint(endpointValue, usage),
      token:
          _rolloutOptionOrEnvironment(
            argResults,
            globalResults,
            'token',
            'HYFENS_CONTROL_TOKEN',
          ) ??
          _rolloutOptionOrEnvironment(
            argResults,
            globalResults,
            'token',
            'HYFENS_TOKEN',
          ),
      organizationId: _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'organization-id',
        'HYFENS_ORGANIZATION_ID',
      ),
      applicationId: _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'application-id',
        'HYFENS_APPLICATION_ID',
      ),
      environmentId: _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'environment-id',
        'HYFENS_ENVIRONMENT_ID',
      ),
      missingSummary: 'Rollout configuration is incomplete',
      missingCode: 'R8901',
      requireApplication: true,
      requireEnvironment: true,
    );
    final endpointUri = auth.endpoint;
    final token = auth.token;
    final organizationId = auth.organizationId;
    final applicationId = auth.applicationId!;
    final environmentId = auth.environmentId!;
    final platformId = _rolloutRequiredOption(
      _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'platform-id',
        'HYFENS_PLATFORM_ID',
      ),
      '--platform-id',
      'HYFENS_PLATFORM_ID',
    );
    final releaseId = _rolloutRequiredOption(
      _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'release-id',
        'HYFENS_RELEASE_ID',
      ),
      '--release-id',
      'HYFENS_RELEASE_ID',
    );
    final patchId = _rolloutRequiredOption(
      _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'patch-id',
        'HYFENS_PATCH_ID',
      ),
      '--patch-id',
      'HYFENS_PATCH_ID',
    );
    final percentage = _rolloutInteger(
      _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'percentage-basis-points',
        'HYFENS_ROLLOUT_PERCENTAGE_BASIS_POINTS',
      ),
      option: 'rollout create --percentage-basis-points',
      usage: usage,
      minimum: 0,
      maximum: 10000,
    );
    final cohortKind = _rolloutChoice(
      _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'cohort-kind',
        'HYFENS_ROLLOUT_COHORT_KIND',
      ),
      option: 'rollout create --cohort-kind',
      choices: _rolloutCohortKindNames,
      usage: usage,
    );
    final internalInstallationHashes =
        (argResults!['internal-installation-hash'] as List).cast<String>();
    final idempotencyKey = _rolloutRequiredOption(
      _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'idempotency-key',
        'HYFENS_IDEMPOTENCY_KEY',
      ),
      '--idempotency-key',
      'HYFENS_IDEMPOTENCY_KEY',
    );
    final caCertPath = _rolloutOptionOrEnvironment(
      argResults,
      globalResults,
      'ca-cert',
      'HYFENS_TLS_CA_CERT',
    );
    final response = await _rolloutRequest(
      method: 'POST',
      uri: _deployUri(endpointUri, 'v1/rollouts'),
      token: token,
      securityContext: _securityContext(caCertPath),
      idempotencyKey: idempotencyKey,
      body: <String, Object?>{
        'organization_id': organizationId,
        'application_id': applicationId,
        'environment_id': environmentId,
        'platform_id': platformId,
        'release_id': releaseId,
        'patch_id': patchId,
        'percentage_basis_points': percentage,
        'cohort_kind': cohortKind,
        'internal_installation_hashes': internalInstallationHashes,
      },
    );
    _writeRolloutSnapshot(runner, response, jsonMode: jsonMode);
  }
}

final class RolloutInspectCommand extends _ToolCommand {
  RolloutInspectCommand(super.runner) {
    argParser
      ..addOption(
        'endpoint',
        help: 'Self-hosted control-plane URL or HYFENS_CONTROL_PLANE_URL.',
      )
      ..addOption(
        'token',
        help: 'Token or HYFENS_TOKEN (legacy HYFENS_CONTROL_TOKEN is also accepted); never written to disk.',
      )
      ..addOption(
        'organization-id',
        help: 'Organization ID or HYFENS_ORGANIZATION_ID.',
      )
      ..addOption('rollout-id', help: 'Rollout ID or HYFENS_ROLLOUT_ID.')
      ..addOption('ca-cert', help: 'PEM CA certificate or HYFENS_TLS_CA_CERT.');
  }

  @override
  String get name => 'inspect';

  @override
  String get description => 'Inspect one authenticated rollout snapshot.';

  @override
  Future<void> run() async {
    final endpointValue = _rolloutOptionOrEnvironment(
      argResults,
      globalResults,
      'endpoint',
      'HYFENS_CONTROL_PLANE_URL',
    );
    final auth = await _resolveControlPlaneRequest(
      runner: runner,
      endpoint: endpointValue == null
          ? null
          : _rolloutEndpoint(endpointValue, usage),
      token: _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'token',
        'HYFENS_CONTROL_TOKEN',
      ),
      organizationId: _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'organization-id',
        'HYFENS_ORGANIZATION_ID',
      ),
      applicationId: null,
      environmentId: null,
      missingSummary: 'Rollout configuration is incomplete',
      missingCode: 'R8901',
      requireApplication: false,
      requireEnvironment: false,
    );
    final endpointUri = auth.endpoint;
    final token = auth.token;
    final organizationId = auth.organizationId;
    final rolloutId = _rolloutRequiredOption(
      _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'rollout-id',
        'HYFENS_ROLLOUT_ID',
      ),
      '--rollout-id',
      'HYFENS_ROLLOUT_ID',
    );
    final caCertPath = _rolloutOptionOrEnvironment(
      argResults,
      globalResults,
      'ca-cert',
      'HYFENS_TLS_CA_CERT',
    );
    final response = await _rolloutRequest(
      method: 'GET',
      uri:
          _deployUri(
            endpointUri,
            'v1/rollouts/${Uri.encodeComponent(rolloutId)}',
          ).replace(
            queryParameters: <String, String>{
              'organization_id': organizationId,
            },
          ),
      token: token,
      securityContext: _securityContext(caCertPath),
    );
    _writeRolloutSnapshot(runner, response, jsonMode: jsonMode);
  }
}

final class RolloutTransitionCommand extends _ToolCommand {
  RolloutTransitionCommand(super.runner) {
    argParser
      ..addOption(
        'endpoint',
        help: 'Self-hosted control-plane URL or HYFENS_CONTROL_PLANE_URL.',
      )
      ..addOption(
        'token',
        help: 'Token or HYFENS_TOKEN (legacy HYFENS_CONTROL_TOKEN is also accepted); never written to disk.',
      )
      ..addOption(
        'organization-id',
        help: 'Organization ID or HYFENS_ORGANIZATION_ID.',
      )
      ..addOption('rollout-id', help: 'Rollout ID or HYFENS_ROLLOUT_ID.')
      ..addOption(
        'action',
        allowed: _rolloutActionNames,
        help: 'Rollout state-machine action.',
      )
      ..addOption(
        'expected-revision',
        help: 'Expected current rollout revision.',
      )
      ..addOption(
        'reason',
        help: 'Audited operator reason or HYFENS_ROLLOUT_REASON.',
      )
      ..addOption(
        'percentage-basis-points',
        help: 'Optional next percentage in basis points.',
      )
      ..addOption(
        'idempotency-key',
        help: 'Idempotency key or HYFENS_IDEMPOTENCY_KEY.',
      )
      ..addOption('ca-cert', help: 'PEM CA certificate or HYFENS_TLS_CA_CERT.');
  }

  @override
  String get name => 'transition';

  @override
  String get description => 'Apply one authenticated explicit rollout action.';

  @override
  Future<void> run() async {
    final endpointValue = _rolloutOptionOrEnvironment(
      argResults,
      globalResults,
      'endpoint',
      'HYFENS_CONTROL_PLANE_URL',
    );
    final auth = await _resolveControlPlaneRequest(
      runner: runner,
      endpoint: endpointValue == null
          ? null
          : _rolloutEndpoint(endpointValue, usage),
      token: _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'token',
        'HYFENS_CONTROL_TOKEN',
      ),
      organizationId: _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'organization-id',
        'HYFENS_ORGANIZATION_ID',
      ),
      applicationId: null,
      environmentId: null,
      missingSummary: 'Rollout configuration is incomplete',
      missingCode: 'R8901',
      requireApplication: false,
      requireEnvironment: false,
    );
    final endpointUri = auth.endpoint;
    final token = auth.token;
    final organizationId = auth.organizationId;
    final rolloutId = _rolloutRequiredOption(
      _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'rollout-id',
        'HYFENS_ROLLOUT_ID',
      ),
      '--rollout-id',
      'HYFENS_ROLLOUT_ID',
    );
    final action = _rolloutChoice(
      _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'action',
        'HYFENS_ROLLOUT_ACTION',
      ),
      option: 'rollout transition --action',
      choices: _rolloutActionNames,
      usage: usage,
    );
    final expectedRevision = _rolloutInteger(
      _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'expected-revision',
        'HYFENS_ROLLOUT_EXPECTED_REVISION',
      ),
      option: 'rollout transition --expected-revision',
      usage: usage,
      minimum: 0,
    );
    final reason = _rolloutRequiredOption(
      _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'reason',
        'HYFENS_ROLLOUT_REASON',
      ),
      '--reason',
      'HYFENS_ROLLOUT_REASON',
    );
    final percentageText = _rolloutOptionOrEnvironment(
      argResults,
      globalResults,
      'percentage-basis-points',
      'HYFENS_ROLLOUT_PERCENTAGE_BASIS_POINTS',
    );
    final percentage = percentageText == null
        ? null
        : _rolloutInteger(
            percentageText,
            option: 'rollout transition --percentage-basis-points',
            usage: usage,
            minimum: 0,
            maximum: 10000,
          );
    final idempotencyKey = _rolloutRequiredOption(
      _rolloutOptionOrEnvironment(
        argResults,
        globalResults,
        'idempotency-key',
        'HYFENS_IDEMPOTENCY_KEY',
      ),
      '--idempotency-key',
      'HYFENS_IDEMPOTENCY_KEY',
    );
    final caCertPath = _rolloutOptionOrEnvironment(
      argResults,
      globalResults,
      'ca-cert',
      'HYFENS_TLS_CA_CERT',
    );
    final response = await _rolloutRequest(
      method: 'POST',
      uri: _deployUri(
        endpointUri,
        'v1/rollouts/${Uri.encodeComponent(rolloutId)}/actions',
      ),
      token: token,
      securityContext: _securityContext(caCertPath),
      idempotencyKey: idempotencyKey,
      body: <String, Object?>{
        'action': action,
        'expected_revision': expectedRevision,
        'reason': reason,
        if (percentage != null) 'percentage_basis_points': percentage,
        'organization_id': organizationId,
      },
    );
    _writeRolloutSnapshot(runner, response, jsonMode: jsonMode);
  }
}

final class DeployCommand extends _ToolCommand {
  DeployCommand(super.runner) {
    argParser
      ..addOption('release', help: 'Exact local release baseline ID.')
      ..addOption(
        'patch',
        help: 'Exact locally verified Patch Format v1 artifact path.',
      )
      ..addOption(
        'endpoint',
        help: 'Self-hosted control-plane URL or HYFENS_CONTROL_PLANE_URL.',
      )
      ..addOption(
        'token',
        help: 'Token or HYFENS_TOKEN (legacy HYFENS_CONTROL_TOKEN is also accepted); never written to disk.',
      )
      ..addOption(
        'organization-id',
        help: 'Control-plane organization ID or HYFENS_ORGANIZATION_ID.',
      )
      ..addOption(
        'application-id',
        help: 'Control-plane application ID or HYFENS_APPLICATION_ID.',
      )
      ..addOption(
        'environment-id',
        help: 'Control-plane environment ID or HYFENS_ENVIRONMENT_ID.',
      )
      ..addOption(
        'ca-cert',
        help: 'PEM CA certificate for a private HTTPS control plane or HYFENS_TLS_CA_CERT.',
      )
      ..addOption(
        'expected-version',
        defaultsTo: '0',
        help: 'Expected environment version for optimistic promotion.',
      )
      ..addOption('display-version', defaultsTo: 'local');
  }

  @override
  String get name => 'deploy';

  @override
  String get description =>
      'Register, upload, and promote one locally verified patch to a self-hosted control plane.';

  @override
  Future<void> run() async {
    final endpointValue = _optionOrEnvironment(
      'endpoint',
      'HYFENS_CONTROL_PLANE_URL',
    );
    final expectedVersion = int.tryParse(
      argResults!['expected-version'] as String,
    );
    if (expectedVersion == null) {
      throw UsageException(
        'deploy --expected-version must be a non-negative integer',
        usage,
      );
    }
    final deployment =
        await ControlPlaneDeliveryService(
          toolchain: runner.toolchain,
          authClient: runner.authClient,
        ).deploy(
          projectPath: projectPath,
          releaseId: argResults!['release'] as String?,
          patchPath: argResults!['patch'] as String?,
          endpoint: endpointValue == null
              ? null
              : _deployEndpoint(endpointValue),
          token: _optionOrEnvironment('token', 'HYFENS_TOKEN'),
          organizationId: _optionOrEnvironment(
            'organization-id',
            'HYFENS_ORGANIZATION_ID',
          ),
          applicationId: _optionOrEnvironment(
            'application-id',
            'HYFENS_APPLICATION_ID',
          ),
          environmentId: _optionOrEnvironment(
            'environment-id',
            'HYFENS_ENVIRONMENT_ID',
          ),
          caCertPath: _optionOrEnvironment('ca-cert', 'HYFENS_TLS_CA_CERT'),
          expectedVersion: expectedVersion,
          displayVersion: argResults!['display-version'] as String,
        );
    final result = deployment.data;
    if (jsonMode) {
      runner.writeJson(result);
    } else {
      runner.write('Deploy completed');
      runner.write('  Release:     ${result['releaseId']}');
      runner.write('  Patch:       ${result['patchId']}');
      runner.write('  Artifact:    ${result['artifactId']}');
      runner.write(
        '  Environment: ${result['environmentId']} v${result['environmentVersion']}',
      );
      runner.write('  Signature:   verified locally before upload');
    }
  }

  String? _optionOrEnvironment(String option, String environment) {
    final value = argResults![option] as String?;
    if (value != null && value.isNotEmpty) return value;
    final fallback = _compatibilityEnvironmentValue(environment);
    return fallback == null || fallback.isEmpty ? null : fallback;
  }
}

ProfileScope? _singleProfileScope(Profile? profile) {
  final profiles = profile?.profiles ?? const <ProfileScope>[];
  return profiles.length == 1 ? profiles.single : null;
}

ProfileScope? _profileScopeForEndpoint(Profile? profile, Uri endpoint) {
  if (profile == null ||
      !controlPlaneEndpointsMatch(profile.endpoint, endpoint)) {
    return null;
  }
  return _singleProfileScope(profile);
}

final class _ResolvedControlPlaneRequest {
  const _ResolvedControlPlaneRequest({
    required this.endpoint,
    required this.token,
    required this.organizationId,
    this.applicationId,
    this.environmentId,
  });

  final Uri endpoint;
  final String token;
  final String organizationId;
  final String? applicationId;
  final String? environmentId;
}

Future<_ResolvedControlPlaneRequest> _resolveControlPlaneRequest({
  required HyfensCommandRunner runner,
  required Uri? endpoint,
  required String? token,
  required String? organizationId,
  required String? applicationId,
  required String? environmentId,
  required String missingSummary,
  required String missingCode,
  required bool requireApplication,
  required bool requireEnvironment,
}) async {
  final profile = await runner.authClient.readProfile();
  final resolvedEndpoint = validateControlPlaneEndpoint(
    endpoint ?? profile?.endpoint ?? Uri.parse(managedCloudApiBase),
    operation: 'control-plane request',
  );
  final profileScope = _profileScopeForEndpoint(profile, resolvedEndpoint);
  final resolvedToken = await _resolveControlPlaneToken(
    runner: runner,
    endpoint: resolvedEndpoint,
    fallback: token,
  );
  final resolvedOrganization = organizationId ?? profileScope?.organizationId;
  final resolvedApplication = applicationId ?? profileScope?.applicationId;
  final resolvedEnvironment = environmentId ?? profileScope?.environmentId;
  if (resolvedToken == null ||
      resolvedOrganization == null ||
      requireApplication && resolvedApplication == null ||
      requireEnvironment && resolvedEnvironment == null) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: missingCode,
      summary: missingSummary,
      detail: 'Provide the endpoint, token, and required scope values or run hyfens login with one selected profile.',
      action: 'Explicit credentials are request-scoped; authenticated sessions use the stored profile endpoint and scope.',
    );
  }
  return _ResolvedControlPlaneRequest(
    endpoint: resolvedEndpoint,
    token: resolvedToken,
    organizationId: resolvedOrganization,
    applicationId: resolvedApplication,
    environmentId: resolvedEnvironment,
  );
}

Future<String?> _resolveControlPlaneToken({
  required HyfensCommandRunner runner,
  required Uri endpoint,
  required String? fallback,
}) async {
  if (fallback != null && fallback.isNotEmpty) return fallback;
  return runner.authClient.accessTokenOrNull(endpoint: endpoint);
}

Uri _deployEndpoint(String value) {
  final endpoint = Uri.tryParse(value);
  if (endpoint == null) {
    throw UsageException(
      'deploy endpoint must be an absolute HTTP or HTTPS URL without embedded credentials',
      'hyfens deploy --help',
    );
  }
  try {
    return validateControlPlaneEndpoint(endpoint, operation: 'deploy');
  } on ToolFailure {
    rethrow;
  }
}

final class BundleCommand extends _ToolCommand {
  BundleCommand(super.runner) {
    addSubcommand(BundleExportCommand(runner));
    addSubcommand(BundleVerifyCommand(runner));
    addSubcommand(BundleImportCommand(runner));
    addSubcommand(BundleAdmitCommand(runner));
  }

  @override
  String get name => 'bundle';

  @override
  String get description =>
      'Export, verify, quarantine, and admit one offline signed release bundle.';

  @override
  Future<void> run() async {}
}

String? _compatibilityEnvironmentValue(String environment) {
  switch (environment) {
    case 'HYFENS_TOKEN':
      return _firstEnvironmentValue(const <String>[
        'HYFENS_TOKEN',
        'HYFENS_CONTROL_TOKEN',
      ]);
    case 'HYFENS_CONTROL_TOKEN':
      return _firstEnvironmentValue(const <String>[
        'HYFENS_CONTROL_TOKEN',
        'HYFENS_TOKEN',
      ]);
    case 'HYFENS_DELIVERY_TOKEN':
      return _firstEnvironmentValue(const <String>[
        'HYFENS_DELIVERY_TOKEN',
        'HYFENS_DELIVERY_CREDENTIAL',
      ]);
    default:
      return Platform.environment[environment];
  }
}

String? _firstEnvironmentValue(Iterable<String> keys) {
  for (final key in keys) {
    final value = Platform.environment[key];
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

abstract base class _BundleRemoteCommand extends _ToolCommand {
  _BundleRemoteCommand(super.runner) {
    argParser
      ..addOption(
        'endpoint',
        help: 'Self-hosted control-plane URL or HYFENS_CONTROL_PLANE_URL.',
      )
      ..addOption(
        'token',
        help: 'Token or HYFENS_TOKEN (legacy HYFENS_CONTROL_TOKEN is also accepted); never written to disk.',
      )
      ..addOption(
        'organization-id',
        help: 'Organization ID or HYFENS_ORGANIZATION_ID.',
      )
      ..addOption(
        'application-id',
        help: 'Application ID or HYFENS_APPLICATION_ID.',
      )
      ..addOption(
        'environment-id',
        help: 'Environment ID or HYFENS_ENVIRONMENT_ID.',
      )
      ..addOption(
        'trusted-public-key',
        help: 'Trusted Ed25519 public key file or HYFENS_TRUSTED_PUBLIC_KEY; required for bundle acceptance.',
      )
      ..addOption('ca-cert', help: 'PEM CA certificate or HYFENS_TLS_CA_CERT.');
  }

  String requiredOption(String option, String environment) =>
      _bundleRequiredOption(
        _bundleOptionOrEnvironment(
          argResults,
          globalResults,
          option,
          environment,
        ),
        option,
        environment,
      );

  String? optionalOption(String option, String environment) =>
      _bundleOptionOrEnvironment(
        argResults,
        globalResults,
        option,
        environment,
      );

  Uri endpoint(String value) => _bundleEndpoint(value, usage);

  Future<_ResolvedControlPlaneRequest> resolveControlAuth() {
    final endpointValue = optionalOption(
      'endpoint',
      'HYFENS_CONTROL_PLANE_URL',
    );
    return _resolveControlPlaneRequest(
      runner: runner,
      endpoint: endpointValue == null ? null : endpoint(endpointValue),
      token: optionalOption('token', 'HYFENS_CONTROL_TOKEN'),
      organizationId: optionalOption(
        'organization-id',
        'HYFENS_ORGANIZATION_ID',
      ),
      applicationId: optionalOption('application-id', 'HYFENS_APPLICATION_ID'),
      environmentId: optionalOption('environment-id', 'HYFENS_ENVIRONMENT_ID'),
      missingSummary: 'Bundle configuration is incomplete',
      missingCode: 'B9001',
      requireApplication: true,
      requireEnvironment: true,
    );
  }

  SecurityContext? caSecurityContext() =>
      _securityContext(optionalOption('ca-cert', 'HYFENS_TLS_CA_CERT'));

  Uri bundleUri(
    Uri endpointUri,
    String organizationId,
    String applicationId,
    String environmentId,
  ) => _deployUri(
    endpointUri,
    'v1/organizations/${Uri.encodeComponent(organizationId)}'
    '/applications/${Uri.encodeComponent(applicationId)}'
    '/environments/${Uri.encodeComponent(environmentId)}',
  );
}

final class BundleExportCommand extends _BundleRemoteCommand {
  BundleExportCommand(super.runner) {
    argParser
      ..addOption('release-id', help: 'Source control-plane release ID.')
      ..addOption('patch-id', help: 'Source control-plane patch ID.')
      ..addOption(
        'output',
        help: 'Destination path for the signed bundle or HYFENS_BUNDLE_OUTPUT.',
      )
      ..addOption(
        'private-key',
        help:
            'Ed25519 private key path; defaults to the configured project key.',
      );
  }

  @override
  String get name => 'export';

  @override
  String get description =>
      'Fetch one verified artifact payload and sign it locally.';

  @override
  Future<void> run() async {
    final auth = await resolveControlAuth();
    final endpointUri = auth.endpoint;
    final token = auth.token;
    final organizationId = auth.organizationId;
    final applicationId = auth.applicationId!;
    final environmentId = auth.environmentId!;
    final releaseId = requiredOption('release-id', 'HYFENS_RELEASE_ID');
    final patchId = requiredOption('patch-id', 'HYFENS_PATCH_ID');
    final outputPath = requiredOption('output', 'HYFENS_BUNDLE_OUTPUT');
    final output = File(outputPath);
    if (output.existsSync()) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.refused,
        code: 'B9005',
        summary: 'Refusing to overwrite an existing bundle',
        detail: output.path,
        action: 'Choose a new output path or remove the existing file deliberately.',
      );
    }
    final project = runner.toolchain.project(projectPath: projectPath);
    final config = runner.toolchain.config(project);
    final projectStore = ToolStore(project);
    final privateKeyPath =
        (argResults!['private-key'] as String?) ?? config.privateKeyPath;
    final privateKey = const KeyStore().readPrivate(
      projectStore.resolveConfiguredPath(privateKeyPath, allowExternal: true),
    );
    final trustedPublicKeyPath =
        _bundleOptionOrEnvironment(
          argResults,
          globalResults,
          'trusted-public-key',
          'HYFENS_TRUSTED_PUBLIC_KEY',
        ) ??
        config.publicKeyPath;
    final trustedPublicKey = const KeyStore().readPublic(
      projectStore.resolveConfiguredPath(
        trustedPublicKeyPath,
        allowExternal: true,
      ),
    );
    final response = await _bundleHttpRequest(
      method: 'GET',
      uri: _deployUri(
        bundleUri(endpointUri, organizationId, applicationId, environmentId),
        'releases/${Uri.encodeComponent(releaseId)}'
        '/patches/${Uri.encodeComponent(patchId)}/bundle',
      ),
      token: token,
      securityContext: caSecurityContext(),
    );
    final payloadJson = <String, Object?>{
      for (final entry in response.entries)
        if (entry.key != 'request_id') entry.key: entry.value,
    };
    late final ReleaseBundlePayload payload;
    try {
      payload = ReleaseBundlePayload.fromJson(payloadJson);
    } on Object catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'B9004',
        summary: 'Control-plane bundle payload is invalid',
        detail: '$error',
      );
    }
    late final List<int> signed;
    try {
      signed = await ReleaseBundle.sign(
        payload: payload,
        keyId: privateKey.keyId,
        privateKeySeed: privateKey.seed,
      );
    } on Object catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.signing,
        code: 'B9008',
        summary: 'Bundle signing failed',
        detail: '$error',
      );
    }
    late final ReleaseBundle bundle;
    try {
      bundle = await ReleaseBundle.verify(
        bytes: signed,
        expectedKeyId: trustedPublicKey.keyId,
        expectedPublicKey: trustedPublicKey.publicKey,
      );
    } on Object catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.signing,
        code: 'B9008',
        summary: 'Bundle signing failed trust-anchor verification',
        detail: '$error',
      );
    }
    await writeAtomicBytes(output, signed);
    final result = <String, Object?>{
      'result': 'EXPORTED',
      'path': output.path,
      'bundleDigest': bundle.bundleDigest,
      'keyId': bundle.keyId,
      'source': bundle.payload.source.toJson(),
    };
    if (jsonMode) {
      runner.writeJson(result);
    } else {
      runner.write('Bundle exported');
      runner.write('  Path:   ${output.path}');
      runner.write('  Digest: ${bundle.bundleDigest}');
      runner.write('  Key:    ${bundle.keyId}');
    }
  }
}

final class BundleVerifyCommand extends _ToolCommand {
  BundleVerifyCommand(super.runner) {
    argParser.addOption(
      'trusted-public-key',
      help: 'Trusted Ed25519 public key file or HYFENS_TRUSTED_PUBLIC_KEY; required for acceptance.',
    );
  }

  @override
  String get name => 'verify';

  @override
  String get description => 'Verify one signed release bundle offline.';

  @override
  Future<void> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('bundle verify requires one bundle path', usage);
    }
    final trustedKey = _readTrustedBundleKey(
      _bundleRequiredOption(
        _bundleOptionOrEnvironment(
          argResults,
          globalResults,
          'trusted-public-key',
          'HYFENS_TRUSTED_PUBLIC_KEY',
        ),
        'trusted-public-key',
        'HYFENS_TRUSTED_PUBLIC_KEY',
      ),
    );
    final bundle = await _readAndVerifyBundle(
      File(argResults!.rest.single),
      trustedKey: trustedKey,
    );
    final result = <String, Object?>{
      'result': 'VERIFIED',
      'bundleDigest': bundle.bundleDigest,
      'keyId': bundle.keyId,
      'source': bundle.payload.source.toJson(),
      'runtimeApplicationId': bundle.payload.release.runtimeApplicationId,
      'runtimeReleaseId': bundle.payload.release.runtimeReleaseId,
      'runtimePatchId': bundle.payload.patch.runtimePatchId,
      'sequence': bundle.payload.patch.sequence,
      'artifactSha256': bundle.payload.artifact.sha256,
    };
    if (jsonMode) {
      runner.writeJson(result);
    } else {
      runner.write('Bundle verified');
      runner.write('  Digest: ${bundle.bundleDigest}');
      runner.write('  Release: ${bundle.payload.release.runtimeReleaseId}');
      runner.write('  Patch:   ${bundle.payload.patch.runtimePatchId}');
      runner.write('  Key:     ${bundle.keyId}');
    }
  }
}

final class BundleImportCommand extends _BundleRemoteCommand {
  BundleImportCommand(super.runner) {
    argParser.addOption(
      'idempotency-key',
      help: 'Idempotency key or HYFENS_IDEMPOTENCY_KEY.',
    );
  }

  @override
  String get name => 'import';

  @override
  String get description =>
      'Verify and import one bundle into destination quarantine.';

  @override
  Future<void> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('bundle import requires one bundle path', usage);
    }
    final bundleFile = File(argResults!.rest.single);
    final bundleBytes = await _readBundleBytes(bundleFile);
    final trustedKey = _readTrustedBundleKey(
      requiredOption('trusted-public-key', 'HYFENS_TRUSTED_PUBLIC_KEY'),
    );
    final bundle = await _verifyBundleBytes(
      bundleFile.path,
      bundleBytes,
      trustedKey: trustedKey,
    );
    final auth = await resolveControlAuth();
    final response = await _bundleHttpRequest(
      method: 'POST',
      uri: _deployUri(
        bundleUri(
          auth.endpoint,
          auth.organizationId,
          auth.applicationId!,
          auth.environmentId!,
        ),
        'bundles',
      ),
      token: auth.token,
      securityContext: caSecurityContext(),
      idempotencyKey: requiredOption(
        'idempotency-key',
        'HYFENS_IDEMPOTENCY_KEY',
      ),
      trustedKeyId: trustedKey.keyId,
      trustedPublicKey: trustedKey.publicKey,
      body: bundleBytes,
    );
    _writeBundleRemoteResult(
      runner,
      response,
      humanTitle: 'Bundle imported',
      verifiedDigest: bundle.bundleDigest,
      jsonMode: jsonMode,
    );
  }
}

final class BundleAdmitCommand extends _BundleRemoteCommand {
  BundleAdmitCommand(super.runner) {
    argParser
      ..addOption('release-id', help: 'Destination control-plane release ID.')
      ..addOption('patch-id', help: 'Destination control-plane patch ID.')
      ..addOption(
        'idempotency-key',
        help: 'Idempotency key or HYFENS_IDEMPOTENCY_KEY.',
      );
  }

  @override
  String get name => 'admit';

  @override
  String get description =>
      'Revalidate one quarantined bundle and mark it ready for promotion.';

  @override
  Future<void> run() async {
    final auth = await resolveControlAuth();
    final organizationId = auth.organizationId;
    final applicationId = auth.applicationId!;
    final environmentId = auth.environmentId!;
    final releaseId = requiredOption('release-id', 'HYFENS_RELEASE_ID');
    final patchId = requiredOption('patch-id', 'HYFENS_PATCH_ID');
    final trustedKey = _readTrustedBundleKey(
      requiredOption('trusted-public-key', 'HYFENS_TRUSTED_PUBLIC_KEY'),
    );
    final response = await _bundleHttpRequest(
      method: 'POST',
      uri: _deployUri(
        bundleUri(auth.endpoint, organizationId, applicationId, environmentId),
        'bundles/${Uri.encodeComponent(releaseId)}'
        '/${Uri.encodeComponent(patchId)}/admit',
      ),
      token: auth.token,
      securityContext: caSecurityContext(),
      idempotencyKey: requiredOption(
        'idempotency-key',
        'HYFENS_IDEMPOTENCY_KEY',
      ),
      trustedKeyId: trustedKey.keyId,
      trustedPublicKey: trustedKey.publicKey,
    );
    _writeBundleRemoteResult(
      runner,
      response,
      humanTitle: 'Bundle admitted',
      jsonMode: jsonMode,
    );
  }
}

SecurityContext? _securityContext(String? certificatePath) {
  if (certificatePath == null || certificatePath.isEmpty) return null;
  final file = File(certificatePath);
  if (!file.existsSync()) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'D8006',
      summary: 'Configured TLS CA certificate is missing',
      detail: certificatePath,
      action: 'Provide a readable PEM CA certificate or remove --ca-cert.',
    );
  }
  try {
    final context = SecurityContext(withTrustedRoots: true);
    context.setTrustedCertificates(file.path);
    return context;
  } on Object catch (error) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'D8007',
      summary: 'Configured TLS CA certificate is invalid',
      detail: '$certificatePath (${error.runtimeType})',
      action: 'Provide a readable PEM CA certificate.',
    );
  }
}

Uri _deployUri(Uri endpoint, String path) {
  final root = endpoint.toString().endsWith('/')
      ? endpoint.toString()
      : '${endpoint.toString()}/';
  return Uri.parse(root).resolve(path);
}

String? _bundleOptionOrEnvironment(
  ArgResults? local,
  ArgResults? global,
  String option,
  String environment,
) {
  final localValue = _bundleArgumentValue(local, option);
  if (localValue is String && localValue.isNotEmpty) return localValue;
  final globalValue = _bundleArgumentValue(global, option);
  if (globalValue is String && globalValue.isNotEmpty) return globalValue;
  final environmentValue = _compatibilityEnvironmentValue(environment);
  return environmentValue == null || environmentValue.isEmpty
      ? null
      : environmentValue;
}

Object? _bundleArgumentValue(ArgResults? results, String option) {
  if (results == null) return null;
  try {
    return results[option];
  } on ArgumentError catch (error) {
    if (error.message == 'Could not find an option named "--$option".') {
      return null;
    }
    rethrow;
  }
}

String _bundleRequiredOption(String? value, String option, String environment) {
  if (value != null && value.isNotEmpty) return value;
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'B9001',
    summary: 'Bundle configuration is incomplete',
    detail: 'Provide --$option or $environment.',
    action: 'Credentials are used only for this request and are never stored by the CLI.',
  );
}

Uri _bundleEndpoint(String value, String usage) {
  try {
    final endpoint = Uri.parse(value);
    if ((endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      throw const FormatException('Invalid control-plane endpoint');
    }
    return endpoint;
  } on Object {
    throw UsageException(
      'bundle endpoint must be an absolute HTTP or HTTPS URL without embedded credentials',
      usage,
    );
  }
}

Future<List<int>> _readBundleBytes(File file) async {
  if (!file.existsSync()) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'B9002',
      summary: 'Bundle file is missing',
      detail: file.path,
    );
  }
  try {
    return await file.readAsBytes();
  } on Object catch (error) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'B9002',
      summary: 'Bundle file could not be read',
      detail: '$error',
      path: file.path,
    );
  }
}

PublicSigningKey _readTrustedBundleKey(String path) =>
    const KeyStore().readPublic(File(path));

Future<ReleaseBundle> _readAndVerifyBundle(
  File file, {
  required PublicSigningKey trustedKey,
}) async {
  return _verifyBundleBytes(
    file.path,
    await _readBundleBytes(file),
    trustedKey: trustedKey,
  );
}

Future<ReleaseBundle> _verifyBundleBytes(
  String path,
  List<int> bytes, {
  required PublicSigningKey trustedKey,
}) async {
  try {
    return await ReleaseBundle.verify(
      bytes: bytes,
      expectedKeyId: trustedKey.keyId,
      expectedPublicKey: trustedKey.publicKey,
    );
  } on Object catch (error) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.signing,
      code: 'B9003',
      summary: 'Signed bundle verification failed',
      detail: '$error',
      path: path,
    );
  }
}

Future<Map<String, Object?>> _bundleHttpRequest({
  required String method,
  required Uri uri,
  required String token,
  SecurityContext? securityContext,
  String? idempotencyKey,
  String? trustedKeyId,
  List<int>? trustedPublicKey,
  List<int>? body,
}) async {
  if ((trustedKeyId == null) != (trustedPublicKey == null)) {
    throw StateError('Bundle trust key ID and public key must be paired');
  }
  final client = HttpClient(context: securityContext);
  try {
    final request = await client.openUrl(method, uri);
    request
      ..headers.set('Authorization', 'Bearer $token')
      ..headers.set(
        'X-Request-Id',
        'cli-${DateTime.now().microsecondsSinceEpoch}',
      );
    if (idempotencyKey != null) {
      request.headers.set('Idempotency-Key', idempotencyKey);
    }
    if (trustedKeyId != null) {
      request.headers
        ..set(ReleaseBundle.trustedKeyIdHeader, trustedKeyId)
        ..set(
          ReleaseBundle.trustedPublicKeyHeader,
          base64Encode(trustedPublicKey!),
        );
    }
    if (body != null) {
      request
        ..headers.contentType = ContentType.json
        ..headers.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close();
    final responseBytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    late final Object? decoded;
    try {
      decoded = responseBytes.isEmpty
          ? <String, Object?>{}
          : jsonDecode(utf8.decode(responseBytes, allowMalformed: false));
    } on Object catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'B9006',
        summary: 'Control-plane response is not valid JSON',
        detail: '$error',
      );
    }
    final responseBody = decoded is Map
        ? <String, Object?>{
            for (final entry in decoded.entries) '${entry.key}': entry.value,
          }
        : null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorValue = responseBody?['error'];
      final errorBody = errorValue is Map
          ? <String, Object?>{
              for (final entry in errorValue.entries)
                '${entry.key}': entry.value,
            }
          : null;
      final code = errorBody?['code'];
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: code is String && code.isNotEmpty ? code : 'B9007',
        summary: 'Control-plane bundle request was rejected',
        detail: errorBody == null
            ? 'HTTP ${response.statusCode}'
            : jsonEncode(errorBody),
      );
    }
    if (responseBody == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'B9009',
        summary: 'Control-plane bundle response is malformed',
        detail: uri.toString(),
      );
    }
    return responseBody;
  } on ToolFailure {
    rethrow;
  } on Object catch (error) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'B9010',
      summary: 'Control-plane bundle request failed',
      detail: error.runtimeType.toString(),
      action: 'Check the endpoint, credentials, and local TLS configuration.',
    );
  } finally {
    client.close(force: true);
  }
}

void _writeBundleRemoteResult(
  HyfensCommandRunner runner,
  Map<String, Object?> response, {
  required String humanTitle,
  required bool jsonMode,
  String? verifiedDigest,
}) {
  if (jsonMode) {
    runner.writeJson(response);
    return;
  }
  final result = response['result'];
  final destination = response['destination'];
  runner.write(humanTitle);
  if (result is String) runner.write('  Result: $result');
  if (verifiedDigest != null) runner.write('  Digest: $verifiedDigest');
  if (destination is Map) {
    final values = <String, Object?>{
      for (final entry in destination.entries) '${entry.key}': entry.value,
    };
    for (final key in const <String>[
      'organizationId',
      'applicationId',
      'environmentId',
      'releaseId',
      'patchId',
      'artifactId',
    ]) {
      final value = values[key];
      if (value is String) runner.write('  ${key}: $value');
    }
  }
}

String? _rolloutOptionOrEnvironment(
  ArgResults? local,
  ArgResults? global,
  String option,
  String environment,
) {
  final localValue = _rolloutArgumentValue(local, option);
  if (localValue is String && localValue.isNotEmpty) return localValue;
  final globalValue = _rolloutArgumentValue(global, option);
  if (globalValue is String && globalValue.isNotEmpty) return globalValue;
  final environmentValue = _compatibilityEnvironmentValue(environment);
  return environmentValue == null || environmentValue.isEmpty
      ? null
      : environmentValue;
}

Object? _rolloutArgumentValue(ArgResults? results, String option) {
  if (results == null) return null;
  try {
    return results[option];
  } on ArgumentError catch (error) {
    if (error.message == 'Could not find an option named "--$option".') {
      return null;
    }
    rethrow;
  }
}

String _rolloutRequiredOption(
  String? value,
  String option,
  String environment,
) {
  if (value != null && value.isNotEmpty) return value;
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'R8901',
    summary: 'Rollout configuration is incomplete',
    detail: 'Provide $option or $environment.',
    action: 'Credentials are used only for this request and are never stored by the CLI.',
  );
}

Uri _rolloutEndpoint(String value, String usage) {
  try {
    final endpoint = Uri.parse(value);
    if ((endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      throw const FormatException('Invalid control-plane endpoint');
    }
    return endpoint;
  } on Object {
    throw UsageException(
      'rollout endpoint must be an absolute HTTP or HTTPS URL without embedded credentials',
      usage,
    );
  }
}

int _rolloutInteger(
  String? value, {
  required String option,
  required String usage,
  int? minimum,
  int? maximum,
}) {
  if (value == null || value.isEmpty) {
    throw UsageException('$option is required', usage);
  }
  final parsed = int.tryParse(value);
  if (parsed == null ||
      minimum != null && parsed < minimum ||
      maximum != null && parsed > maximum) {
    final bounds = minimum != null && maximum != null
        ? ' between $minimum and $maximum'
        : minimum != null
        ? ' greater than or equal to $minimum'
        : maximum != null
        ? ' less than or equal to $maximum'
        : '';
    throw UsageException('$option must be an integer$bounds', usage);
  }
  return parsed;
}

String _rolloutChoice(
  String? value, {
  required String option,
  required Iterable<String> choices,
  required String usage,
}) {
  if (value == null || !choices.contains(value)) {
    throw UsageException('$option must be one of ${choices.join(', ')}', usage);
  }
  return value;
}

Future<Map<String, Object?>> _rolloutRequest({
  required String method,
  required Uri uri,
  required String token,
  SecurityContext? securityContext,
  String? idempotencyKey,
  Map<String, Object?>? body,
}) async {
  final client = HttpClient(context: securityContext);
  try {
    final request = await client.openUrl(method, uri);
    final bytes = body == null ? null : utf8.encode(jsonEncode(body));
    request
      ..headers.set('Authorization', 'Bearer $token')
      ..headers.set(
        'X-Request-Id',
        'cli-${DateTime.now().microsecondsSinceEpoch}',
      );
    if (idempotencyKey != null) {
      request.headers.set('Idempotency-Key', idempotencyKey);
    }
    if (bytes != null) {
      request
        ..headers.contentType = ContentType.json
        ..headers.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final source = await response.transform(utf8.decoder).join();
    Object? decoded;
    try {
      decoded = source.isEmpty ? <String, Object?>{} : jsonDecode(source);
    } on Object {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'R8903',
        summary: 'Control-plane response is not valid JSON',
        detail: 'HTTP ${response.statusCode}',
      );
    }
    final responseBody = decoded is Map
        ? <String, Object?>{
            for (final entry in decoded.entries) '${entry.key}': entry.value,
          }
        : null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = responseBody?['error'];
      final errorBody = error is Map
          ? <String, Object?>{
              for (final entry in error.entries) '${entry.key}': entry.value,
            }
          : null;
      final errorCode = errorBody?['code'];
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: errorCode is String && errorCode.isNotEmpty ? errorCode : 'R8902',
        summary: 'Control-plane request was rejected',
        detail: errorBody == null
            ? 'HTTP ${response.statusCode}'
            : jsonEncode(errorBody),
      );
    }
    if (responseBody == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'R8904',
        summary: 'Control-plane response is malformed',
        detail: 'Expected a JSON object from $method request',
      );
    }
    return responseBody;
  } on ToolFailure {
    rethrow;
  } on Object catch (error) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'R8905',
      summary: 'Control-plane request failed',
      detail: error.runtimeType.toString(),
      action: 'Check the endpoint, credentials, and local TLS configuration.',
    );
  } finally {
    client.close(force: true);
  }
}

void _writeRolloutSnapshot(
  HyfensCommandRunner runner,
  Map<String, Object?> response, {
  required bool jsonMode,
}) {
  if (jsonMode) {
    runner.writeJson(response);
    return;
  }
  final rollout = _rolloutResponseObject(response['rollout'], 'rollout');
  final revision = _rolloutResponseObject(response['revision'], 'revision');
  final target = _rolloutResponseObject(revision['target'], 'target');
  final policy = _rolloutResponseObject(revision['policy'], 'policy');
  final hashes = policy['internalInstallationHashes'];
  if (hashes is! List) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'R8904',
      summary: 'Control-plane response is malformed',
      detail: 'policy.internalInstallationHashes',
    );
  }
  runner.write('Rollout snapshot');
  runner.write('  Rollout ID: ${_rolloutResponseString(rollout, 'id')}');
  runner.write('  State:      ${_rolloutResponseString(revision, 'state')}');
  runner.write('  Revision:   ${_rolloutResponseInt(revision, 'revision')}');
  runner.write(
    '  Target:     application=${_rolloutResponseString(target, 'applicationId')} '
    'environment=${_rolloutResponseString(target, 'environmentId')} '
    'platform=${_rolloutResponseString(target, 'platformId')} '
    'release=${_rolloutResponseString(target, 'releaseId')} '
    'patch=${_rolloutResponseString(target, 'patchId')}',
  );
  runner.write(
    '  Policy:     cohort=${_rolloutResponseString(policy, 'cohortKind')} '
    'percentage-basis-points=${_rolloutResponseInt(policy, 'percentageBasisPoints')} '
    'internal-installations=${hashes.length}',
  );
}

Map<String, Object?> _rolloutResponseObject(Object? value, String field) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) '${entry.key}': entry.value,
    };
  }
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'R8904',
    summary: 'Control-plane response is malformed',
    detail: field,
  );
}

String _rolloutResponseString(Map<String, Object?> body, String key) {
  final value = body[key];
  if (value is String && value.isNotEmpty) return value;
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'R8904',
    summary: 'Control-plane response is malformed',
    detail: key,
  );
}

int _rolloutResponseInt(Map<String, Object?> body, String key) {
  final value = body[key];
  if (value is int) return value;
  throw ToolFailure.single(
    exitCode: ToolExitCode.environment,
    code: 'R8904',
    summary: 'Control-plane response is malformed',
    detail: key,
  );
}

final class KeysCommand extends _ToolCommand {
  KeysCommand(super.runner) {
    addSubcommand(KeysGenerateCommand(runner));
    addSubcommand(KeysInspectCommand(runner));
  }

  @override
  String get name => 'keys';

  @override
  String get description => 'Manage local Ed25519 signing material.';

  @override
  Future<void> run() async {}
}

final class KeysGenerateCommand extends _ToolCommand {
  KeysGenerateCommand(super.runner);

  @override
  String get name => 'generate';

  @override
  String get description =>
      'Generate a local Ed25519 key pair without overwriting files.';

  @override
  Future<void> run() async {
    final key = await runner.toolchain.generateKeys(projectPath: projectPath);
    final project = runner.toolchain.project(projectPath: projectPath);
    final config = runner.toolchain.config(project);
    final privateFile = ToolStore(project)
        .resolveConfiguredPath(config.privateKeyPath, allowExternal: true);
    final privateKeyUnderProject = p.isWithin(
      project.root.absolute.path,
      privateFile.absolute.path,
    );
    if (jsonMode) {
      runner.writeJson(<String, Object>{
        'keyId': key.keyId,
        'result': 'GENERATED',
        'privateKeyUnderProject': privateKeyUnderProject,
      });
    } else {
      runner.write('Generated local Ed25519 signing key.');
      runner.write('  Key ID: ${key.keyId}');
      runner.write('  Private key is stored separately and was not printed.');
      if (privateKeyUnderProject) {
        runner.write(
          '  Warning: private key is under the project; keep .tool ignored and never commit it.',
        );
      }
    }
  }
}

final class KeysInspectCommand extends _ToolCommand {
  KeysInspectCommand(super.runner);

  @override
  String get name => 'inspect';

  @override
  String get description => 'Inspect the configured public signing key.';

  @override
  Future<void> run() async {
    final key = runner.toolchain.inspectPublicKey(projectPath: projectPath);
    if (jsonMode) {
      runner.writeJson(<String, Object>{
        'keyId': key.keyId,
        'algorithm': 'ed25519',
        'publicKeyBytes': key.publicKey.length,
      });
    } else {
      runner.write('Trusted public key');
      runner.write('  Algorithm: Ed25519');
      runner.write('  Key ID:    ${key.keyId}');
      runner.write('  Bytes:     ${key.publicKey.length}');
    }
  }
}

String displayRelative(FileSystemEntity file, Directory root) => p
    .relative(file.absolute.path, from: root.absolute.path)
    .replaceAll(r'\', '/');
