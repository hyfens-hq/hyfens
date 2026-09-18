import 'dart:convert';

import 'package:crypto/crypto.dart';

String canonicalJson(Object? value) => jsonEncode(_normalize(value));

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String sha256Digest(List<int> bytes) => 'sha256:${sha256Hex(bytes)}';

Object? _normalize(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Map<Object?, Object?>) {
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Canonical maps require string keys');
      }
      normalized[entry.key! as String] = _normalize(entry.value);
    }
    final keys = normalized.keys.toList()..sort();
    return <String, Object?>{for (final key in keys) key: normalized[key]};
  }
  if (value is Iterable<Object?>) {
    return value.map(_normalize).toList(growable: false);
  }
  if (value is double && !value.isFinite) {
    throw const FormatException(
      'Canonical JSON cannot encode non-finite numbers',
    );
  }
  return value;
}

Map<String, Object?> decodeObject(String source) {
  final value = jsonDecode(source);
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object');
  }
  return value;
}

String requireSha256Digest(String value) {
  final normalized = value.startsWith('sha256:') ? value.substring(7) : value;
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
    throw const FormatException('Expected a lowercase SHA-256 digest');
  }
  return 'sha256:$normalized';
}

String requireOpaqueId(String value, String field) {
  if (!RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(value)) {
    throw FormatException('Invalid $field');
  }
  return value;
}

String requireRuntimeIdentity(String value, String field) {
  if (value.isEmpty ||
      value.length > 256 ||
      value.contains(RegExp(r'[\u0000\r\n]'))) {
    throw FormatException('Invalid $field');
  }
  return value;
}

String requireNonEmpty(String value, String field, {int maxLength = 256}) {
  if (value.isEmpty ||
      value.length > maxLength ||
      value.contains(RegExp(r'[\u0000\r\n]'))) {
    throw FormatException('Invalid $field');
  }
  return value;
}
