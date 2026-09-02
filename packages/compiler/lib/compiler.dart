library hyfens_compiler;

import 'dart:typed_data';

import 'package:instrumentation_e0/instrumentation_e0.dart';

export 'package:instrumentation_e0/e0_runtime.dart'
    show E0PatchContainer, E0PatchProgram, E0ReceiverDescriptor;
export 'package:instrumentation_e0/instrumentation_e0.dart'
    show
        E0FunctionManifest,
        E0FunctionSignature,
        E0ReleaseManifest,
        E0SourceTransformer,
        E0ValueSchema;

/// Stable entry point for the Phase 1A source-subset compiler.
///
/// The underlying E0 container is kept behind this facade while the canonical
/// Patch Format v1 encoder becomes the artifact handoff in the next toolchain
/// package. Keeping this seam explicit prevents research implementation names
/// from becoming the intended developer API.
final class HyfensCompiler {
  const HyfensCompiler();

  Uint8List compile(PatchCompileRequest request) => E0PatchCompiler().compile(
    source: request.source,
    manifest: request.manifest,
    functionName: request.functionName,
    className: request.className,
    canonicalLibraryUri: request.canonicalLibraryUri,
    patchSequence: request.patchSequence,
    allowSyntheticWidgetTypes: request.allowSyntheticWidgetTypes,
  );
}

final class PatchCompileRequest {
  const PatchCompileRequest({
    required this.source,
    required this.manifest,
    required this.functionName,
    this.className,
    this.canonicalLibraryUri,
    this.patchSequence = 1,
    this.allowSyntheticWidgetTypes = false,
  });

  final String source;
  final E0ReleaseManifest manifest;
  final String functionName;
  final String? className;
  final String? canonicalLibraryUri;
  final int patchSequence;
  final bool allowSyntheticWidgetTypes;
}
