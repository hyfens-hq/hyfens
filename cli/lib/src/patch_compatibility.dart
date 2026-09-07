/// Typed compatibility outcomes shared by analysis, patch creation, release
/// metadata, and MCP responses.
const patchCompatibilityModel = 'flutter-dart-abi-v1';

enum PatchCompatibilityDecision {
  patchable,
  patchableRestartRequired,
  newBaseRelease,
  notYetSupported,
}

extension PatchCompatibilityDecisionLabel on PatchCompatibilityDecision {
  String get label => switch (this) {
    PatchCompatibilityDecision.patchable => 'PATCHABLE',
    PatchCompatibilityDecision.patchableRestartRequired =>
      'PATCHABLE_RESTART_REQUIRED',
    PatchCompatibilityDecision.newBaseRelease => 'NEW_BASE_RELEASE',
    PatchCompatibilityDecision.notYetSupported => 'NOT_YET_SUPPORTED',
  };
}

/// The single policy seam for the public patchability vocabulary.
///
/// The bytecode verifier and host registries remain the final safety
/// authority. This module owns the user-facing classification of those
/// decisions so terminal analysis, patch admission, release records, and MCP
/// do not invent different meanings for the same boundary.
final class PatchCompatibilityAnalyzer {
  const PatchCompatibilityAnalyzer._();

  static PatchCompatibilityDecision fromLegacyClassification(
    String classification,
  ) => switch (classification) {
    'patchable' || 'noEffect' => PatchCompatibilityDecision.patchable,
    'storeReleaseRequired' => PatchCompatibilityDecision.newBaseRelease,
    'unsupported' || 'unknown' => PatchCompatibilityDecision.notYetSupported,
    _ => PatchCompatibilityDecision.notYetSupported,
  };

  /// Adapts the existing diagnostic classifier without losing the stronger
  /// meaning carried by a declaration-shape detail. Older releases use
  /// `unsupported` for both a compiler gap and an unsafe field/hierarchy
  /// change; those outcomes have different user actions.
  static PatchCompatibilityDecision forAnalysis({
    required String classification,
    String? detail,
  }) {
    final legacy = fromLegacyClassification(classification);
    if (legacy != PatchCompatibilityDecision.notYetSupported) return legacy;
    final lower = (detail ?? '').toLowerCase();
    if (lower.contains('field|') ||
        lower.contains('classheader|') ||
        lower.contains('constructor|') ||
        lower.contains('member|') ||
        lower.contains('field layout') ||
        lower.contains('type hierarchy')) {
      return PatchCompatibilityDecision.newBaseRelease;
    }
    return legacy;
  }

  static String reasonCode({
    required PatchCompatibilityDecision decision,
    String? diagnosticCode,
    String? detail,
  }) {
    if (diagnosticCode != null && diagnosticCode.isNotEmpty) {
      return diagnosticCode;
    }
    if (decision == PatchCompatibilityDecision.newBaseRelease) {
      final lower = (detail ?? '').toLowerCase();
      if (lower.contains('field') || lower.contains('layout')) {
        return 'FIELD_LAYOUT_CHANGED';
      }
      if (lower.contains('classheader') || lower.contains('hierarchy')) {
        return 'TYPE_HIERARCHY_CHANGED';
      }
      if (lower.contains('constructor')) return 'CONSTRUCTOR_CHANGED';
      if (lower.contains('native')) return 'NATIVE_BOUNDARY_CHANGED';
      if (lower.contains('asset') || lower.contains('font')) {
        return 'RESOURCE_CHANGED';
      }
      if (lower.contains('engine')) return 'ENGINE_CHANGED';
    }
    return decision.name.toUpperCase();
  }

  static PatchCompatibilityDecision declarationChange(String key) {
    if (key.startsWith('function|')) {
      return PatchCompatibilityDecision.patchable;
    }
    if (key.startsWith('method|')) {
      final parts = key.split('|');
      return parts.length >= 4 && parts[2] == 'instanceMethod'
          ? PatchCompatibilityDecision.patchable
          : PatchCompatibilityDecision.notYetSupported;
    }
    if (key.startsWith('field|') ||
        key.startsWith('classHeader|') ||
        key.startsWith('constructor|') ||
        key.startsWith('member|')) {
      return PatchCompatibilityDecision.newBaseRelease;
    }
    return PatchCompatibilityDecision.notYetSupported;
  }

  static String explainExclusion(String exclusion) {
    final separator = exclusion.indexOf(':');
    final reason =
        (separator < 0 ? exclusion : exclusion.substring(separator + 1)).trim();
    if (reason.contains('receiver setter writes')) {
      return 'This patch changes live receiver state. Hyfens cannot commit '
          'that object mutation atomically yet; create a new base release.';
    }
    if (reason.contains('field') || reason.contains('layout')) {
      return 'This patch changes the field layout of an existing live receiver '
          'state object. Hyfens cannot safely update instances yet; create a '
          'new base release.';
    }
    if (reason.contains('classHeader') || reason.contains('hierarchy')) {
      return 'This patch changes a type hierarchy or class shape that existing '
          'runtime objects may depend on; create a new base release.';
    }
    if (reason.contains('constructor')) {
      return 'This patch changes a constructor shape used by the base release; '
          'create a new base release.';
    }
    if (reason.contains('generic owner') || reason.contains('generic')) {
      return 'The declaration uses generic runtime shape metadata that the '
          'current patch ABI cannot preserve; create a new base release.';
    }
    if (reason.contains('BuildContext')) {
      return 'BuildContext is host-owned. Only the bounded opaque context '
          'parameter is patchable; unsupported framework dispatch requires a '
          'new base release.';
    }
    if (reason.contains('closure')) {
      return 'This closure shape is outside the bounded callback ABI; create '
          'a new base release.';
    }
    if (reason.contains('generator')) {
      return 'Generator state machines are not ABI-compatible with the '
          'current interpreter; create a new base release.';
    }
    if (reason.contains('manifest') ||
        reason.contains('resource') ||
        reason.contains('Material icon') ||
        reason.contains('font')) {
      return 'The base release does not contain complete, verified resource '
          'evidence; create a new base release.';
    }
    if (reason.contains('native')) {
      return 'This patch crosses the native application boundary; create a '
          'new base release.';
    }
    if (reason.contains('engine') || reason.contains('toolchain')) {
      return 'The Flutter/Dart engine or toolchain differs from the base; '
          'create a new base release.';
    }
    if (reason.contains('static') ||
        reason.contains('accessor') ||
        reason.contains('operator')) {
      return 'This declaration has no stable ordinary instance-call ABI in '
          'the current runtime; create a new base release.';
    }
    return 'This declaration is outside the supported patch ABI; create a '
        'new base release or change only a supported method body.';
  }
}
