import 'dart:convert';

final class E0OffsetSegment {
  const E0OffsetSegment({
    required this.generatedStart,
    required this.length,
    required this.originalStart,
    required this.syntheticKind,
    required this.anchorOriginalOffset,
  });

  final int generatedStart;
  final int length;
  final int? originalStart;
  final String? syntheticKind;
  final int anchorOriginalOffset;

  bool get isSynthetic => originalStart == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'generatedStart': generatedStart,
    'length': length,
    'originalStart': originalStart,
    'syntheticKind': syntheticKind,
    'anchorOriginalOffset': anchorOriginalOffset,
  };
}

final class E0OffsetLookup {
  const E0OffsetLookup({
    required this.generatedOffset,
    required this.originalOffset,
    required this.syntheticKind,
    required this.anchorOriginalOffset,
  });

  final int generatedOffset;
  final int? originalOffset;
  final String? syntheticKind;
  final int anchorOriginalOffset;

  bool get isSynthetic => originalOffset == null;
}

final class E0OffsetMap {
  static const int maxSegments = 8192;
  static const int maxUriCharacters = 512;
  static const int maxSourceCharacters = 4 * 1024 * 1024;
  static const int maxSyntheticKindCharacters = 128;
  static const int maxEncodedCharacters = 4 * 1024 * 1024;

  const E0OffsetMap({
    required this.originalUri,
    required this.generatedUri,
    required this.originalLength,
    required this.generatedLength,
    required this.segments,
  });

  final String originalUri;
  final String generatedUri;
  final int originalLength;
  final int generatedLength;
  final List<E0OffsetSegment> segments;

  String encode() {
    final encoded = jsonEncode(<String, Object>{
      'offsetMapVersion': 1,
      'unit': 'utf16-code-unit',
      'originalUri': originalUri,
      'generatedUri': generatedUri,
      'originalLength': originalLength,
      'generatedLength': generatedLength,
      'segments': segments.map((segment) => segment.toJson()).toList(),
    });
    if (utf8.encode(encoded).length > maxEncodedCharacters) {
      throw const FormatException('Offset map exceeds byte limit');
    }
    return encoded;
  }

  static E0OffsetMap decode(String source) {
    if (source.length > maxEncodedCharacters ||
        utf8.encode(source).length > maxEncodedCharacters) {
      throw const FormatException('Offset map exceeds byte limit');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on Object {
      throw const FormatException('Offset map is not JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Offset map root must be an object');
    }
    const expectedKeys = <String>{
      'offsetMapVersion',
      'unit',
      'originalUri',
      'generatedUri',
      'originalLength',
      'generatedLength',
      'segments',
    };
    if (decoded.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(decoded.keys.toSet()).isNotEmpty ||
        decoded['offsetMapVersion'] != 1 ||
        decoded['unit'] != 'utf16-code-unit') {
      throw const FormatException('Invalid offset map v1 fields');
    }
    final originalUri = decoded['originalUri'];
    final generatedUri = decoded['generatedUri'];
    final originalLength = decoded['originalLength'];
    final generatedLength = decoded['generatedLength'];
    final rawSegments = decoded['segments'];
    if (originalUri is! String ||
        generatedUri is! String ||
        originalLength is! int ||
        generatedLength is! int ||
        originalLength < 0 ||
        generatedLength < 0 ||
        originalUri.length > maxUriCharacters ||
        generatedUri.length > maxUriCharacters ||
        originalLength > maxSourceCharacters ||
        generatedLength > maxSourceCharacters ||
        rawSegments is! List<Object?> ||
        rawSegments.length > maxSegments) {
      throw const FormatException('Invalid offset map header types');
    }
    final segments = <E0OffsetSegment>[];
    for (final raw in rawSegments) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Invalid offset segment');
      }
      const segmentKeys = <String>{
        'generatedStart',
        'length',
        'originalStart',
        'syntheticKind',
        'anchorOriginalOffset',
      };
      if (raw.keys.toSet().difference(segmentKeys).isNotEmpty ||
          segmentKeys.difference(raw.keys.toSet()).isNotEmpty) {
        throw const FormatException('Invalid offset segment fields');
      }
      final generatedStart = raw['generatedStart'];
      final length = raw['length'];
      final originalStart = raw['originalStart'];
      final syntheticKind = raw['syntheticKind'];
      final anchor = raw['anchorOriginalOffset'];
      if (generatedStart is! int ||
          length is! int ||
          anchor is! int ||
          (originalStart != null && originalStart is! int) ||
          (syntheticKind != null && syntheticKind is! String)) {
        throw const FormatException('Invalid offset segment types');
      }
      segments.add(
        E0OffsetSegment(
          generatedStart: generatedStart,
          length: length,
          originalStart: originalStart as int?,
          syntheticKind: syntheticKind as String?,
          anchorOriginalOffset: anchor,
        ),
      );
    }
    final result = E0OffsetMap(
      originalUri: originalUri,
      generatedUri: generatedUri,
      originalLength: originalLength,
      generatedLength: generatedLength,
      segments: List.unmodifiable(segments),
    );
    result._validate();
    return result;
  }

  E0OffsetLookup lookupGenerated(int generatedOffset) {
    if (generatedOffset < 0 || generatedOffset >= generatedLength) {
      throw RangeError.range(generatedOffset, 0, generatedLength - 1);
    }
    for (final segment in segments) {
      final relative = generatedOffset - segment.generatedStart;
      if (relative >= 0 && relative < segment.length) {
        return E0OffsetLookup(
          generatedOffset: generatedOffset,
          originalOffset: segment.originalStart == null
              ? null
              : segment.originalStart! + relative,
          syntheticKind: segment.syntheticKind,
          anchorOriginalOffset: segment.anchorOriginalOffset,
        );
      }
    }
    throw StateError('Validated map has an unmapped generated offset');
  }

  int generatedOffsetForOriginal(int originalOffset) {
    if (originalOffset < 0 || originalOffset >= originalLength) {
      throw RangeError.range(originalOffset, 0, originalLength - 1);
    }
    for (final segment in segments) {
      final originalStart = segment.originalStart;
      if (originalStart == null) continue;
      final relative = originalOffset - originalStart;
      if (relative >= 0 && relative < segment.length) {
        return segment.generatedStart + relative;
      }
    }
    throw StateError('Validated map has an unmapped original offset');
  }

  /// Validates a map supplied through a runtime-only diagnostic sidecar.
  void validate() => _validate();

  void _validate() {
    if (!_isLogicalUri(originalUri) ||
        !_isLogicalUri(generatedUri) ||
        originalLength > maxSourceCharacters ||
        generatedLength > maxSourceCharacters ||
        segments.length > maxSegments) {
      throw const FormatException('Offset map URIs must be logical');
    }
    var nextGenerated = 0;
    var nextOriginal = 0;
    for (final segment in segments) {
      if (segment.length <= 0 || segment.generatedStart != nextGenerated) {
        throw const FormatException('Segments must cover generated source');
      }
      if (segment.anchorOriginalOffset < 0 ||
          segment.anchorOriginalOffset > originalLength) {
        throw const FormatException('Invalid original anchor');
      }
      if (segment.isSynthetic) {
        if (segment.syntheticKind == null ||
            segment.syntheticKind!.isEmpty ||
            segment.syntheticKind!.length > maxSyntheticKindCharacters) {
          throw const FormatException('Synthetic segment requires a kind');
        }
      } else {
        if (segment.syntheticKind != null ||
            segment.originalStart != nextOriginal ||
            segment.originalStart! + segment.length > originalLength) {
          throw const FormatException('Invalid original segment coverage');
        }
        nextOriginal += segment.length;
      }
      nextGenerated += segment.length;
    }
    if (nextGenerated != generatedLength || nextOriginal != originalLength) {
      throw const FormatException('Offset map lengths do not match segments');
    }
  }

  static bool _isLogicalUri(String value) {
    if (value.isEmpty ||
        value.length > maxUriCharacters ||
        value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[/\\]').hasMatch(value) ||
        value.contains('\\') ||
        value.codeUnits.any((unit) => unit < 0x20)) {
      return false;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.isEmpty ||
        !const <String>{
          'package',
          'e0-overlay',
        }.contains(uri.scheme.toLowerCase()) ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.any((segment) => segment == '..')) {
      return false;
    }
    return true;
  }
}
