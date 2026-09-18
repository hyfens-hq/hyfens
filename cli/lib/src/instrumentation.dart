import 'dart:convert';

import 'package:hyfens_instrumenter/instrumenter.dart';

import 'configuration.dart';
import 'diagnostics.dart';
import 'discovery.dart';
import 'project.dart';

final class PlannedFunction {
  PlannedFunction({required this.source, required this.manifest});

  final SourceUnit source;
  final E0FunctionManifest manifest;

  Map<String, Object?> toJson(FlutterProject project) => <String, Object?>{
    'source': source.relativeTo(project),
    'libraryUri': source.libraryUri,
    'manifest': manifest.toJson(),
  };
}

final class InstrumentedUnit {
  InstrumentedUnit({
    required this.source,
    required this.instrumented,
    required this.exclusions,
    required this.manifest,
    required this.transformedSource,
  });

  final SourceUnit source;
  final bool instrumented;
  final List<String> exclusions;
  final E0ReleaseManifest? manifest;
  final String? transformedSource;

  Map<String, Object?> toJson(FlutterProject project) => <String, Object?>{
    'source': source.relativeTo(project),
    'libraryUri': source.libraryUri,
    'instrumented': instrumented,
    'exclusions': exclusions,
    'manifest': manifest == null ? null : manifest!.encode(),
  };
}

/// Build-time data for the generated lifecycle bootstrap. It is deliberately
/// a source-injection descriptor rather than a runtime dependency in the CLI;
/// this keeps the instrumenter reusable for metadata-only analysis.
final class RuntimeBootstrapConfiguration {
  RuntimeBootstrapConfiguration({
    required this.updateUrl,
    required this.keyId,
    required List<int> publicKey,
  }) : publicKey = List.unmodifiable(publicKey) {
    if (updateUrl.scheme != 'http' && updateUrl.scheme != 'https') {
      throw ArgumentError.value(updateUrl, 'updateUrl', 'must be HTTP(S)');
    }
    if (keyId.isEmpty || this.publicKey.length != 32) {
      throw ArgumentError('Invalid generated runtime bootstrap key material');
    }
  }

  final Uri updateUrl;
  final String keyId;
  final List<int> publicKey;

  String get importSource =>
      "import 'package:hyfens_flutter_integration/flutter_integration.dart' {prefix};";

  String invocation({
    required String appId,
    required String releaseId,
    required String buildFingerprint,
    required List<E0FunctionManifest> functions,
  }) {
    final sorted = functions.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    final functionMap = <String, int>{
      for (final function in sorted) function.id: function.slot,
    };
    final signatureMap = <String, String>{
      for (final function in sorted) function.id: function.signature.encode(),
    };
    final receiverMap = <String, String>{
      for (final function in sorted) function.id: function.receiver.encode(),
    };
    final functionNames = <String, String>{
      for (final function in sorted)
        function.id: function.identity.ownerName == null
            ? function.name
            : '${function.identity.ownerName}.${function.name}',
    };
    final functionUris = <String, String>{
      for (final function in sorted) function.id: function.identity.libraryUri,
    };
    String intMap(Map<String, int> values) =>
        '<String, int>{${values.entries.map((entry) => '${jsonEncode(entry.key)}: ${entry.value}').join(', ')}}';
    String stringMap(Map<String, String> values) =>
        '<String, String>{${values.entries.map((entry) => '${jsonEncode(entry.key)}: ${jsonEncode(entry.value)}').join(', ')}}';
    return '{prefix}.HyfensFlutterIntegration.start('
        'appId: ${jsonEncode(appId)}, '
        'releaseId: ${jsonEncode(releaseId)}, '
        'buildFingerprint: ${jsonEncode(buildFingerprint)}, '
        'functions: ${intMap(functionMap)}, '
        'signatures: ${stringMap(signatureMap)}, '
        'receivers: ${stringMap(receiverMap)}, '
        'functionNames: ${stringMap(functionNames)}, '
        'functionUris: ${stringMap(functionUris)}, '
        'keyId: ${jsonEncode(keyId)}, '
        'publicKey: <int>[${publicKey.join(', ')}], '
        'patchUri: Uri.parse(${jsonEncode(updateUrl.toString())}),'
        'controlPlane: _hyfens_bootstrap.HyfensControlPlaneConfiguration.fromEnvironment(),'
        ');';
  }
}

final class InstrumentationPlan {
  InstrumentationPlan({
    required this.project,
    required List<InstrumentedUnit> units,
    required List<ToolDiagnostic> diagnostics,
  }) : units = List.unmodifiable(units),
       diagnostics = List.unmodifiable(diagnostics);

  final FlutterProject project;
  final List<InstrumentedUnit> units;
  final List<ToolDiagnostic> diagnostics;

  List<InstrumentedUnit> get successful =>
      units.where((unit) => unit.instrumented).toList(growable: false);

  List<PlannedFunction> get functions => successful
      .where((unit) => unit.manifest != null)
      .expand(
        (unit) => unit.manifest!.functions.map(
          (manifest) =>
              PlannedFunction(source: unit.source, manifest: manifest),
        ),
      )
      .toList(growable: false);

  Map<String, Object?> toJson() => <String, Object?>{
    'selected': units.length,
    'instrumented': successful.length,
    'excluded': units.length - successful.length,
    'units': units.map((unit) => unit.toJson(project)).toList(),
    'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
  };
}

final class InstrumentationPlanner {
  const InstrumentationPlanner();

  InstrumentationPlan build({
    required FlutterProject project,
    required SourceDiscoveryResult discovery,
    required ToolConfig config,
    required String applicationId,
    required String releaseId,
    required String buildFingerprint,
    RuntimeBootstrapConfiguration? runtimeBootstrap,
    bool retainTransformedSources = true,
  }) {
    final instrumenter = HyfensInstrumenter();
    final units = <InstrumentedUnit>[];
    final diagnostics = <ToolDiagnostic>[];
    final initialResults = <String, E0TransformResult>{};
    final failures = <String, String>{};
    for (final source in discovery.selected) {
      try {
        final result = instrumenter.transform(
          SourceInstrumentationRequest(
            source: source.file.readAsStringSync(),
            packageName: source.packageName,
            logicalLibraryPath: source.logicalLibraryPath,
            appId: applicationId,
            releaseId: releaseId,
            buildFingerprint: buildFingerprint,
            canonicalLibraryUri: source.libraryUri,
            requireMain: source.entrypoint,
            installRuntime: source.entrypoint,
          ),
        );
        initialResults[source.libraryUri] = result;
      } on Object catch (error) {
        failures[source.libraryUri] = error is FormatException
            ? error.message.toString()
            : error.toString();
      }
    }

    final discoveredFunctions =
        initialResults.values
            .expand((result) => result.manifest.functions)
            .toList(growable: false)
          ..sort((left, right) => left.id.compareTo(right.id));
    final globalFunctions = <E0FunctionManifest>[
      for (var index = 0; index < discoveredFunctions.length; index++)
        E0FunctionManifest(
          name: discoveredFunctions[index].name,
          receiver: discoveredFunctions[index].receiver,
          identity: discoveredFunctions[index].identity,
          id: discoveredFunctions[index].id,
          slot: index,
          signature: discoveredFunctions[index].signature,
        ),
    ];
    final globalSlots = <String, int>{
      for (final function in globalFunctions) function.id: function.slot,
    };
    final bootstrapInvocation = runtimeBootstrap?.invocation(
      appId: applicationId,
      releaseId: releaseId,
      buildFingerprint: buildFingerprint,
      functions: globalFunctions,
    );

    for (final source in discovery.selected) {
      final initial = initialResults[source.libraryUri];
      final failure = failures[source.libraryUri];
      if (initial == null || failure != null) {
        final detail = failure ?? 'No instrumentation result was produced.';
        diagnostics.add(
          ToolDiagnostic(
            code: source.entrypoint ? 'P2004' : 'P2002',
            severity: source.entrypoint
                ? DiagnosticSeverity.error
                : DiagnosticSeverity.warning,
            summary: source.entrypoint
                ? 'Application entrypoint cannot be instrumented'
                : 'Source unit cannot be instrumented',
            detail: detail,
            path: source.relativeTo(project),
            action: source.entrypoint
                ? 'Fix the unsupported entrypoint before creating a release.'
                : 'Changes in this source unit require a store release.',
          ),
        );
        units.add(
          InstrumentedUnit(
            source: source,
            instrumented: false,
            exclusions: <String>[detail],
            manifest: null,
            transformedSource: null,
          ),
        );
        continue;
      }
      try {
        final assignedSlots = <String, int>{
          for (final function in initial.manifest.functions)
            function.id: globalSlots[function.id]!,
        };
        final result = instrumenter.transform(
          SourceInstrumentationRequest(
            source: source.file.readAsStringSync(),
            packageName: source.packageName,
            logicalLibraryPath: source.logicalLibraryPath,
            appId: applicationId,
            releaseId: releaseId,
            buildFingerprint: buildFingerprint,
            canonicalLibraryUri: source.libraryUri,
            requireMain: source.entrypoint,
            installRuntime: source.entrypoint,
            assignedSlots: assignedSlots,
            releaseFunctions: globalFunctions,
            runtimeBootstrapImport: source.entrypoint
                ? runtimeBootstrap?.importSource
                : null,
            runtimeBootstrapInvocation: source.entrypoint
                ? bootstrapInvocation
                : null,
          ),
        );
        if (result.exclusions.isNotEmpty) {
          diagnostics.add(
            ToolDiagnostic(
              code: 'P2001',
              severity: DiagnosticSeverity.warning,
              summary: 'Some declarations are not instrumented',
              detail: result.exclusions.join('; '),
              path: source.relativeTo(project),
              action: 'Changes within excluded declarations require a store release.',
            ),
          );
        }
        units.add(
          InstrumentedUnit(
            source: source,
            instrumented: true,
            exclusions: result.exclusions,
            manifest: result.manifest,
            transformedSource: retainTransformedSources ? result.source : null,
          ),
        );
      } on Object catch (error) {
        final detail = error is FormatException
            ? error.message.toString()
            : error.toString();
        diagnostics.add(
          ToolDiagnostic(
            code: source.entrypoint ? 'P2004' : 'P2002',
            severity: source.entrypoint
                ? DiagnosticSeverity.error
                : DiagnosticSeverity.warning,
            summary: source.entrypoint
                ? 'Application entrypoint cannot be instrumented'
                : 'Source unit cannot be instrumented',
            detail: detail,
            path: source.relativeTo(project),
            action: source.entrypoint
                ? 'Fix the unsupported entrypoint before creating a release.'
                : 'Changes in this source unit require a store release.',
          ),
        );
        units.add(
          InstrumentedUnit(
            source: source,
            instrumented: false,
            exclusions: <String>[detail],
            manifest: null,
            transformedSource: null,
          ),
        );
      }
    }
    if (units
        .where((unit) => unit.source.entrypoint)
        .every((unit) => !unit.instrumented)) {
      throw ToolFailure(
        exitCode: ToolExitCode.analysis,
        diagnostics:
            diagnostics
                .where((item) => item.severity == DiagnosticSeverity.error)
                .isEmpty
            ? <ToolDiagnostic>[
                const ToolDiagnostic(
                  code: 'P2004',
                  severity: DiagnosticSeverity.error,
                  summary: 'Application entrypoint cannot be instrumented',
                  detail: 'No instrumented main.dart is available.',
                  action:
                      'Fix the entrypoint or perform a normal store release.',
                ),
              ]
            : diagnostics
                  .where((item) => item.severity == DiagnosticSeverity.error)
                  .toList(),
      );
    }
    return InstrumentationPlan(
      project: project,
      units: units,
      diagnostics: diagnostics,
    );
  }
}
