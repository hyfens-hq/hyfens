import 'dart:convert';

import 'offset_map.dart';
import 'value.dart';

/// Stable categories used by the interpreter-hardening diagnostics surface.
///
/// These values are runtime-local metadata. They do not participate in Patch
/// Format v1 encoding or capability contract v1.
abstract final class E0RuntimeDiagnosticCode {
  static const execution = 'E8501';
  static const budget = 'E8101';
  static const capabilityBudget = 'E8102';
  static const closureBudget = 'E8103';
  static const invalidOpcode = 'E8502';
  static const sourceMap = 'E8401';
}

/// Receives only the already-bounded, sanitized rendering of a runtime fault.
typedef E0RuntimeDiagnosticSink = void Function(String diagnostic);

const int e0MaxDiagnosticMessageLength = 256;

final _e0SensitiveAssignment = RegExp(
  r'''\b(?:password|passwd|secret|token|api[-_]?key|private[-_]?key)\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;]+)''',
  caseSensitive: false,
);
final _e0EndpointAssignment = RegExp(
  r'''\b(?:path|file|url|uri)\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;]+)''',
  caseSensitive: false,
);
final _e0AuthorizationValue = RegExp(
  r'''\b(?:authorization\s*:\s*(?:bearer\s+)?|bearer\s+)[^\s,;]+''',
  caseSensitive: false,
);
final _e0LogicalUrl = RegExp(
  r'''\b(?:https?|file)://[^\s"'(),;]+''',
  caseSensitive: false,
);
final _e0AbsolutePath = RegExp(
  r'''(^|[\s"'(),;=])((?:[A-Za-z]:[\\/]|/)[^\s"'(),;]+)''',
);

String e0BoundedDiagnosticMessage(String message) {
  var sanitized = message
      .replaceAll(_e0SensitiveAssignment, '<redacted>')
      .replaceAll(_e0EndpointAssignment, '<redacted>')
      .replaceAll(_e0AuthorizationValue, '<redacted>')
      .replaceAll(_e0LogicalUrl, '<redacted>')
      .replaceAllMapped(
        _e0AbsolutePath,
        (match) => '${match.group(1)}<redacted>',
      );
  if (sanitized.length > e0MaxDiagnosticMessageLength) {
    sanitized = '${sanitized.substring(0, e0MaxDiagnosticMessageLength - 1)}…';
  }
  return sanitized;
}

bool _isDiagnosticLabel(String value, {required bool allowColon}) {
  return !value.contains('/') &&
      !value.contains('\\') &&
      !value.contains('://') &&
      (allowColon || !value.contains(':')) &&
      value.codeUnits.every((unit) => unit >= 0x20 && unit != 0x7f);
}

bool _isLogicalSourceUri(String value) {
  if (value.isEmpty ||
      value.length > E0OffsetMap.maxUriCharacters ||
      value.startsWith('/') ||
      RegExp(r'^[A-Za-z]:[/\\]').hasMatch(value) ||
      value.contains('\\') ||
      value.codeUnits.any((unit) => unit < 0x20)) {
    return false;
  }
  final uri = Uri.tryParse(value);
  return uri != null &&
      const <String>{'package', 'e0-overlay'}.contains(uri.scheme) &&
      !uri.hasAuthority &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.pathSegments.every((segment) => segment != '..') &&
      uri.toString() == value;
}

/// Release-owned interpreter limits. A patch cannot change these values.
///
/// Callers may provide a stricter instance for tests or a constrained host,
/// but every value is checked against the hard maximums below. Keeping the
/// limits outside the patch payload avoids changing Patch Format v1.
///
/// Guest-visible allocation is deliberately bounded at the typed value seam:
/// `E0ValueCodec` caps nesting, collection entries, value nodes, strings, and
/// encoded values, while instruction and closure budgets bound repeated
/// construction. A process-wide Dart heap quota is not exposed here because
/// it cannot be enforced without destabilizing the host VM.
final class E0RuntimeLimits {
  const E0RuntimeLimits({
    this.maxInstructionBudget = hardMaxInstructionBudget,
    this.maxCallDepth = hardMaxCallDepth,
    this.maxClosureInvocations = hardMaxClosureInvocations,
    this.maxCapabilityCalls = hardMaxCapabilityCalls,
    this.maxAsyncResumes = hardMaxAsyncResumes,
    this.maxAsyncDeadline = hardMaxAsyncDeadline,
  });

  static const int hardMaxInstructionBudget = 1000000;
  static const int hardMaxCallDepth = 32;
  static const int hardMaxClosureInvocations = 4096;
  static const int hardMaxCapabilityCalls = 64;
  static const int hardMaxAsyncResumes = 256;
  static const Duration hardMaxAsyncDeadline = Duration(seconds: 30);

  static const E0RuntimeLimits defaults = E0RuntimeLimits();

  final int maxInstructionBudget;
  final int maxCallDepth;
  final int maxClosureInvocations;
  final int maxCapabilityCalls;
  final int maxAsyncResumes;
  final Duration maxAsyncDeadline;

  void validate() {
    if (maxInstructionBudget <= 0 ||
        maxInstructionBudget > hardMaxInstructionBudget ||
        maxCallDepth <= 0 ||
        maxCallDepth > hardMaxCallDepth ||
        maxClosureInvocations <= 0 ||
        maxClosureInvocations > hardMaxClosureInvocations ||
        maxCapabilityCalls <= 0 ||
        maxCapabilityCalls > hardMaxCapabilityCalls ||
        maxAsyncResumes <= 0 ||
        maxAsyncResumes > hardMaxAsyncResumes ||
        maxAsyncDeadline <= Duration.zero ||
        maxAsyncDeadline > hardMaxAsyncDeadline) {
      throw ArgumentError('Invalid interpreter runtime limits');
    }
  }

  void validateInstructionBudget(int requested) {
    validate();
    if (requested <= 0 || requested > maxInstructionBudget) {
      throw const FormatException(
        'Instruction budget is outside runtime limits',
      );
    }
  }

  void validateAsyncInvocation({
    required int instructionBudget,
    required int maxResumes,
    required Duration deadline,
  }) {
    validateInstructionBudget(instructionBudget);
    if (maxResumes <= 0 || maxResumes > maxAsyncResumes) {
      throw const FormatException(
        'Async resume limit is outside runtime limits',
      );
    }
    if (deadline <= Duration.zero || deadline > maxAsyncDeadline) {
      throw const FormatException('Async deadline is outside runtime limits');
    }
  }

  static void validateString(String value, {int? pc}) {
    if (utf8.encode(value).length > E0ValueCodec.maxStringBytes) {
      throw FormatException(
        'String size limit exceeded${pc == null ? '' : ' at $pc'}',
      );
    }
  }
}

/// A logical source location associated with an interpreted program counter.
final class E0RuntimeSourceLocation {
  const E0RuntimeSourceLocation({
    required this.functionId,
    required this.functionName,
    required this.logicalUri,
    required this.line,
    required this.column,
    required this.pc,
    required this.originalOffset,
    required this.generatedOffset,
    required this.syntheticKind,
  });

  final String functionId;
  final String functionName;
  final String logicalUri;
  final int line;
  final int column;
  final int pc;
  final int originalOffset;
  final int generatedOffset;
  final String? syntheticKind;

  @override
  String toString() => '$logicalUri:$line:$column';
}

/// Bounded companion metadata for mapping interpreter PCs to source.
///
/// The runtime stores logical URIs, line starts, and a compact PC mapping. It
/// never needs a source snapshot and rejects absolute paths. This metadata is
/// intentionally separate from Patch Format v1; a release-owned bootstrap may
/// register it for local diagnostics.
final class E0RuntimeSourceMap {
  E0RuntimeSourceMap({
    required this.functionId,
    required this.functionName,
    required this.offsetMap,
    required Map<int, int> pcToGeneratedOffset,
    required List<int> lineStarts,
  }) : pcToGeneratedOffset = Map.unmodifiable(
         Map<int, int>.fromEntries(
           pcToGeneratedOffset.entries.toList()
             ..sort((left, right) => left.key.compareTo(right.key)),
         ),
       ),
       lineStarts = List.unmodifiable(lineStarts) {
    _validate();
  }

  factory E0RuntimeSourceMap.fromSource({
    required String functionId,
    required String functionName,
    required E0OffsetMap offsetMap,
    required String originalSource,
    required Map<int, int> pcToGeneratedOffset,
  }) {
    if (originalSource.length != offsetMap.originalLength) {
      throw const FormatException(
        'Source-map source length does not match offset map',
      );
    }
    if (originalSource.length > E0OffsetMap.maxSourceCharacters ||
        utf8.encode(originalSource).length > E0OffsetMap.maxSourceCharacters) {
      throw const FormatException('Runtime source map source exceeds bounds');
    }
    final starts = <int>[0];
    for (var index = 0; index < originalSource.length; index++) {
      if (originalSource.codeUnitAt(index) == 0x0a) starts.add(index + 1);
    }
    return E0RuntimeSourceMap(
      functionId: functionId,
      functionName: functionName,
      offsetMap: offsetMap,
      pcToGeneratedOffset: pcToGeneratedOffset,
      lineStarts: starts,
    );
  }

  static const int maxPcEntries = 4096;
  static const int maxLineStarts = 4096;
  static const int maxFunctionIdBytes = 256;
  static const int maxFunctionNameBytes = 256;
  static const int maxEncodedBytes = 4 * 1024 * 1024;

  final String functionId;
  final String functionName;
  final E0OffsetMap offsetMap;
  final Map<int, int> pcToGeneratedOffset;
  final List<int> lineStarts;

  E0RuntimeSourceLocation? lookup(int pc) {
    final generatedOffset = pcToGeneratedOffset[pc];
    if (generatedOffset == null) return null;
    E0OffsetLookup mapped;
    try {
      mapped = offsetMap.lookupGenerated(generatedOffset);
    } on Object {
      // Diagnostics must fail closed if a stale sidecar is encountered. A
      // malformed map must never turn a guest fault into a host exception.
      return null;
    }
    final originalOffset = mapped.originalOffset ?? mapped.anchorOriginalOffset;
    final boundedOffset = originalOffset.clamp(0, offsetMap.originalLength);
    final lineIndex = _lineIndex(boundedOffset);
    return E0RuntimeSourceLocation(
      functionId: functionId,
      functionName: functionName,
      logicalUri: offsetMap.originalUri,
      line: lineIndex + 1,
      column: boundedOffset - lineStarts[lineIndex] + 1,
      pc: pc,
      originalOffset: boundedOffset,
      generatedOffset: generatedOffset,
      syntheticKind: mapped.syntheticKind,
    );
  }

  String encode() {
    final encoded = jsonEncode(<String, Object?>{
      'runtimeSourceMapVersion': 1,
      'functionId': functionId,
      'functionName': functionName,
      'offsetMap': jsonDecode(offsetMap.encode()),
      'pcToGeneratedOffset': [
        for (final entry in pcToGeneratedOffset.entries)
          <String, int>{'pc': entry.key, 'generatedOffset': entry.value},
      ],
      'lineStarts': lineStarts,
    });
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw const FormatException('Runtime source map exceeds byte limit');
    }
    return encoded;
  }

  static E0RuntimeSourceMap decode(String source) {
    if (source.length > maxEncodedBytes ||
        utf8.encode(source).length > maxEncodedBytes) {
      throw const FormatException('Runtime source map exceeds byte limit');
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Runtime source map root must be an object');
    }
    const keys = <String>{
      'runtimeSourceMapVersion',
      'functionId',
      'functionName',
      'offsetMap',
      'pcToGeneratedOffset',
      'lineStarts',
    };
    if (decoded.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(decoded.keys.toSet()).isNotEmpty ||
        decoded['runtimeSourceMapVersion'] != 1 ||
        decoded['functionId'] is! String ||
        decoded['functionName'] is! String ||
        decoded['offsetMap'] is! Map<String, Object?> ||
        decoded['pcToGeneratedOffset'] is! List<Object?> ||
        decoded['lineStarts'] is! List<Object?>) {
      throw const FormatException('Invalid runtime source map fields');
    }
    final entries = <int, int>{};
    for (final item in decoded['pcToGeneratedOffset']! as List<Object?>) {
      if (item is! Map<String, Object?> ||
          item.keys.toSet().difference({'pc', 'generatedOffset'}).isNotEmpty ||
          item.keys.toSet().length != 2 ||
          item['pc'] is! int ||
          item['generatedOffset'] is! int ||
          entries[item['pc']! as int] != null) {
        throw const FormatException('Invalid runtime source map PC entry');
      }
      entries[item['pc']! as int] = item['generatedOffset']! as int;
    }
    final rawStarts = decoded['lineStarts']! as List<Object?>;
    if (rawStarts.any((item) => item is! int)) {
      throw const FormatException('Invalid runtime source map line table');
    }
    final starts = rawStarts.cast<int>();
    return E0RuntimeSourceMap(
      functionId: decoded['functionId']! as String,
      functionName: decoded['functionName']! as String,
      offsetMap: E0OffsetMap.decode(
        jsonEncode(decoded['offsetMap']! as Map<String, Object?>),
      ),
      pcToGeneratedOffset: entries,
      lineStarts: starts,
    );
  }

  int _lineIndex(int offset) {
    var low = 0;
    var high = lineStarts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (lineStarts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  void _validate() {
    offsetMap.validate();
    if (functionId.isEmpty ||
        utf8.encode(functionId).length > maxFunctionIdBytes ||
        functionName.isEmpty ||
        utf8.encode(functionName).length > maxFunctionNameBytes ||
        !_isDiagnosticLabel(functionId, allowColon: true) ||
        !_isDiagnosticLabel(functionName, allowColon: false) ||
        pcToGeneratedOffset.isEmpty ||
        pcToGeneratedOffset.length > maxPcEntries ||
        lineStarts.isEmpty ||
        lineStarts.length > maxLineStarts ||
        lineStarts.first != 0) {
      throw const FormatException('Runtime source map exceeds bounds');
    }
    var previousPc = -1;
    for (final entry in pcToGeneratedOffset.entries) {
      if (entry.key <= previousPc ||
          entry.key < 0 ||
          entry.value < 0 ||
          entry.value >= offsetMap.generatedLength) {
        throw const FormatException('Invalid runtime source map PC mapping');
      }
      previousPc = entry.key;
    }
    var previousLineStart = -1;
    for (final lineStart in lineStarts) {
      if (lineStart <= previousLineStart ||
          lineStart < 0 ||
          lineStart > offsetMap.originalLength) {
        throw const FormatException('Invalid runtime source map line table');
      }
      previousLineStart = lineStart;
    }
  }
}

/// Process-local registry populated only by release-owned diagnostics setup.
final class E0RuntimeSourceMaps {
  E0RuntimeSourceMaps._();

  static const int maxRegisteredFunctions = 4096;
  static final Map<String, E0RuntimeSourceMap> _maps =
      <String, E0RuntimeSourceMap>{};

  static void register(E0RuntimeSourceMap map) {
    final existing = _maps[map.functionId];
    if (existing != null && existing.encode() != map.encode()) {
      throw StateError(
        'Source map is already registered for ${map.functionId}',
      );
    }
    if (existing == null && _maps.length >= maxRegisteredFunctions) {
      throw StateError('Runtime source map registry limit exceeded');
    }
    _maps[map.functionId] = map;
  }

  static E0RuntimeSourceLocation? lookup(String functionId, int pc) {
    final map = _maps[functionId];
    if (map == null) return null;
    try {
      return map.lookup(pc);
    } on Object {
      // Source maps are optional diagnostics metadata and are never allowed
      // to interfere with patch execution or guest error delivery.
      return null;
    }
  }

  static void clear() => _maps.clear();
}

/// Release-owned logical context used when a patch has no PC-level sidecar.
///
/// This is deliberately smaller than a source snapshot: it gives a runtime
/// fault a stable function and package URI while leaving exact line mapping to
/// the optional [E0RuntimeSourceMap] registry. The generated release bootstrap
/// supplies these values from the release manifest; downloaded patches cannot
/// replace them.
final class E0RuntimeFunctionContext {
  const E0RuntimeFunctionContext({
    required this.functionId,
    required this.functionName,
    required this.logicalUri,
  });

  static const int maxFunctionIdBytes = 256;
  static const int maxFunctionNameBytes = 256;
  static const int maxRegisteredFunctions = 4096;

  final String functionId;
  final String functionName;
  final String logicalUri;

  void validate() {
    if (functionId.isEmpty ||
        utf8.encode(functionId).length > maxFunctionIdBytes ||
        functionName.isEmpty ||
        utf8.encode(functionName).length > maxFunctionNameBytes ||
        !_isDiagnosticLabel(functionId, allowColon: true) ||
        !_isDiagnosticLabel(functionName, allowColon: false) ||
        !_isLogicalSourceUri(logicalUri)) {
      throw const FormatException('Invalid runtime function context');
    }
  }

  bool sameAs(E0RuntimeFunctionContext other) =>
      functionId == other.functionId &&
      functionName == other.functionName &&
      logicalUri == other.logicalUri;
}

/// Process-local function context registered by the release-owned bootstrap.
final class E0RuntimeFunctionContexts {
  E0RuntimeFunctionContexts._();

  static final Map<String, E0RuntimeFunctionContext> _contexts =
      <String, E0RuntimeFunctionContext>{};

  static void registerAll(Map<String, E0RuntimeFunctionContext> contexts) {
    if (contexts.length > E0RuntimeFunctionContext.maxRegisteredFunctions) {
      throw StateError('Runtime function context limit exceeded');
    }
    for (final entry in contexts.entries) {
      if (entry.key != entry.value.functionId) {
        throw const FormatException('Runtime function context key mismatch');
      }
      entry.value.validate();
      final existing = _contexts[entry.key];
      if (existing != null && !existing.sameAs(entry.value)) {
        throw StateError(
          'Runtime function context is already registered for ${entry.key}',
        );
      }
    }
    final newCount = contexts.keys
        .where((key) => !_contexts.containsKey(key))
        .length;
    if (_contexts.length + newCount >
        E0RuntimeFunctionContext.maxRegisteredFunctions) {
      throw StateError('Runtime function context limit exceeded');
    }
    for (final entry in contexts.entries) {
      _contexts[entry.key] = entry.value;
    }
  }

  static E0RuntimeFunctionContext? lookup(String functionId) =>
      _contexts[functionId];

  static void clear() => _contexts.clear();
}
