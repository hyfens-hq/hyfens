import 'dart:convert';

enum ToolExitCode {
  success(0),
  usage(64),
  environment(65),
  analysis(66),
  compatibility(67),
  signing(68),
  internal(70),
  refused(73);

  const ToolExitCode(this.value);

  final int value;
}

enum DiagnosticSeverity { info, warning, error }

/// Stable machine-readable diagnostics for the Phase 1B lifecycle boundary.
///
/// These codes are intentionally kept outside command implementations so the
/// rollback and cleanup surfaces can evolve without changing their contract
/// for scripts and editor integrations.
abstract final class ToolDiagnosticCodes {
  static const rollbackTargetUnsupported = 'R6001';
  static const rollbackStateInvalid = 'R6002';
  static const rollbackHighWaterUnavailable = 'R6003';
  static const rollbackHighWaterRegression = 'R6004';
  static const rollbackBaseUnavailable = 'R6005';
  static const rollbackStateCommitFailed = 'R6006';
  static const rollbackReleaseRequired = 'R6007';

  static const cleanupScopeUnsupported = 'C7001';
  static const cleanupConfirmationRequired = 'C7002';
  static const cleanupTargetInvalid = 'C7003';
  static const cleanupScopeProtected = 'C7004';
  static const cleanupRequiresBaseRollback = 'C7005';
  static const cleanupFailed = 'C7006';

  static const statusNotInitialized = 'T1801';
  static const statusStoreIncomplete = 'T1802';
  static const statusInventoryTruncated = 'T1803';

  static const resourceAssetChanged = 'A3010';
  static const resourceFontChanged = 'F3010';
  static const resourceNativeChanged = 'N3010';
  static const resourceSnapshotMissing = 'R5010';
  static const engineRevisionUnavailable = 'T1103';
}

final class ToolDiagnostic {
  const ToolDiagnostic({
    required this.code,
    required this.severity,
    required this.summary,
    required this.detail,
    this.path,
    this.line,
    this.column,
    this.action,
    this.storeReleaseRequired = false,
  });

  final String code;
  final DiagnosticSeverity severity;
  final String summary;
  final String detail;
  final String? path;
  final int? line;
  final int? column;
  final String? action;
  final bool storeReleaseRequired;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'severity': severity.name,
    'summary': summary,
    'detail': detail,
    'path': path,
    'line': line,
    'column': column,
    'action': action,
    'storeReleaseRequired': storeReleaseRequired,
  };

  String render() {
    final location = path == null
        ? ''
        : ' ${path!}${line == null ? '' : ':$line'}'
              '${column == null ? '' : ':$column'}';
    final buffer = StringBuffer()
      ..writeln('${severity.name.toUpperCase()} $code$location')
      ..writeln('  $summary')
      ..writeln('  $detail');
    if (action != null) buffer.writeln('  Action: $action');
    return buffer.toString().trimRight();
  }
}

final class ToolFailure implements Exception {
  ToolFailure({required this.exitCode, required this.diagnostics})
    : assert(diagnostics.isNotEmpty);

  ToolFailure.single({
    required ToolExitCode exitCode,
    required String code,
    required String summary,
    required String detail,
    String? path,
    String? action,
    bool storeReleaseRequired = false,
  }) : this(
         exitCode: exitCode,
         diagnostics: <ToolDiagnostic>[
           ToolDiagnostic(
             code: code,
             severity: DiagnosticSeverity.error,
             summary: summary,
             detail: detail,
             path: path,
             action: action,
             storeReleaseRequired: storeReleaseRequired,
           ),
         ],
       );

  final ToolExitCode exitCode;
  final List<ToolDiagnostic> diagnostics;

  @override
  String toString() => diagnostics.map((item) => item.render()).join('\n');
}

final class DiagnosticReport {
  DiagnosticReport(Iterable<ToolDiagnostic> diagnostics)
    : diagnostics = List.unmodifiable(diagnostics);

  final List<ToolDiagnostic> diagnostics;

  bool get hasErrors => diagnostics.any(
    (diagnostic) => diagnostic.severity == DiagnosticSeverity.error,
  );

  Map<String, Object?> toJson({String? result, String? releaseId}) =>
      <String, Object?>{
        'result': result ?? (hasErrors ? 'ERROR' : 'OK'),
        'releaseId': releaseId,
        'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
      };

  String encodeJson({String? result, String? releaseId}) =>
      jsonEncode(toJson(result: result, releaseId: releaseId));
}
