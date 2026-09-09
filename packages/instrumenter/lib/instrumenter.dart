library hyfens_instrumenter;

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';

export 'package:instrumentation_e0/e0_runtime.dart'
    show E0AsyncCapabilityDescriptor;
export 'package:instrumentation_e0/instrumentation_e0.dart'
    show
        E0OffsetMap,
        E0FunctionManifest,
        E0Identity,
        E0ReleaseManifest,
        E0TransformResult,
        E0WidgetFactoryDescriptor;

/// Stable facade for source discovery/instrumentation output.
///
/// Project-wide file discovery is intentionally outside this Phase 1A seam;
/// the facade accepts one discovered source unit and preserves the existing
/// transformer diagnostics and release manifest as its test boundary.
final class HyfensInstrumenter {
  HyfensInstrumenter({E0Identity? identity})
    : _transformer = E0SourceTransformer(identity: identity);

  final E0SourceTransformer _transformer;

  E0TransformResult transform(SourceInstrumentationRequest request) =>
      _transformer.transform(
        source: request.source,
        packageName: request.packageName,
        logicalLibraryPath: request.logicalLibraryPath,
        appId: request.appId,
        releaseId: request.releaseId,
        buildFingerprint: request.buildFingerprint,
        canonicalLibraryUri: request.canonicalLibraryUri,
        capabilities: request.capabilities,
        widgetFactories: request.widgetFactories,
        widgetBuildClasses: request.widgetBuildClasses,
        allowSyntheticWidgetTypes: request.allowSyntheticWidgetTypes,
        requireMain: request.requireMain,
        installRuntime: request.installRuntime,
        assignedSlots: request.assignedSlots,
        releaseFunctions: request.releaseFunctions,
        runtimeBootstrapImport: request.runtimeBootstrapImport,
        runtimeBootstrapInvocation: request.runtimeBootstrapInvocation,
      );
}

final class SourceInstrumentationRequest {
  const SourceInstrumentationRequest({
    required this.source,
    required this.packageName,
    required this.logicalLibraryPath,
    required this.appId,
    required this.releaseId,
    required this.buildFingerprint,
    this.canonicalLibraryUri,
    this.capabilities = const <E0AsyncCapabilityDescriptor>[],
    this.widgetFactories = const <E0WidgetFactoryDescriptor>[],
    this.widgetBuildClasses = const <String>{},
    this.allowSyntheticWidgetTypes = false,
    this.requireMain = true,
    this.installRuntime = true,
    this.assignedSlots,
    this.releaseFunctions,
    this.runtimeBootstrapImport,
    this.runtimeBootstrapInvocation,
  });

  final String source;
  final String packageName;
  final String logicalLibraryPath;
  final String appId;
  final String releaseId;
  final String buildFingerprint;
  final String? canonicalLibraryUri;
  final List<E0AsyncCapabilityDescriptor> capabilities;
  final List<E0WidgetFactoryDescriptor> widgetFactories;
  final Set<String> widgetBuildClasses;
  final bool allowSyntheticWidgetTypes;
  final bool requireMain;
  final bool installRuntime;
  final Map<String, int>? assignedSlots;
  final List<E0FunctionManifest>? releaseFunctions;

  /// Import source containing the `{prefix}` placeholder for the generated
  /// runtime bootstrap alias.
  final String? runtimeBootstrapImport;

  /// Expression statement source containing the `{prefix}` placeholder.
  final String? runtimeBootstrapInvocation;
}
