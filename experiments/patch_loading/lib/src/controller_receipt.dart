import 'dart:convert';

/// The unsigned, server-admission-bound body of one successful installation
/// receipt.
///
/// The controller stores this exact body until a runtime sender receives a
/// server acknowledgement. A device-key signature can be added by that
/// sender later; the controller deliberately has no signing responsibility.
final class E1InstallReceiptContext {
  E1InstallReceiptContext({required Map<String, Object?> body})
    : body = _copyAndValidate(body);

  static const int version = 1;
  static const int maxBodyBytes = 16 * 1024;
  static const int maxFieldLength = 256;
  static const Set<String> wireKeys = <String>{
    'admission_id',
    'activation_deadline',
    'application_id',
    'artifact_digest',
    'challenge',
    'environment_id',
    'installation_id',
    'key_id',
    'patch_id',
    'platform',
    'receipt_id',
    'release_id',
    'result',
    'runtime_application_id',
    'runtime_version',
    'version',
  };

  /// An immutable, defensively copied map with the exact receipt wire keys.
  final Map<String, Object?> body;

  int get schemaVersion => body['version']! as int;
  String get receiptId => body['receipt_id']! as String;
  String get installationId => body['installation_id']! as String;
  String get keyId => body['key_id']! as String;
  String get applicationId => body['application_id']! as String;
  String get environmentId => body['environment_id']! as String;
  String get releaseId => body['release_id']! as String;
  String get runtimeApplicationId => body['runtime_application_id']! as String;
  String get platform => body['platform']! as String;
  String get patchId => body['patch_id']! as String;
  String get artifactDigest => body['artifact_digest']! as String;
  String get normalizedArtifactDigest => artifactDigest.startsWith('sha256:')
      ? artifactDigest.substring('sha256:'.length)
      : artifactDigest;
  String get admissionId => body['admission_id']! as String;
  String get activationDeadline => body['activation_deadline']! as String;
  String get challenge => body['challenge']! as String;
  String get runtimeVersion => body['runtime_version']! as String;
  String get result => body['result']! as String;

  Map<String, Object?> toJson() => body;

  static Map<String, Object?> _copyAndValidate(Map<String, Object?> input) {
    final copied = <String, Object?>{};
    for (final entry in (input as Map<Object?, Object?>).entries) {
      if (entry.key is! String) {
        throw const FormatException('Install receipt keys must be strings');
      }
      copied[entry.key! as String] = _copyJsonValue(entry.value);
    }
    final keys = copied.keys.toSet();
    if (keys.length != wireKeys.length ||
        keys.difference(wireKeys).isNotEmpty ||
        wireKeys.difference(keys).isNotEmpty) {
      throw const FormatException('Install receipt fields are not exact');
    }
    final versionValue = copied['version'];
    if (versionValue is! int || versionValue != version) {
      throw const FormatException('Install receipt version is invalid');
    }
    for (final key in <String>[
      'receipt_id',
      'installation_id',
      'application_id',
      'environment_id',
      'release_id',
      'runtime_application_id',
      'platform',
      'patch_id',
      'admission_id',
      'challenge',
      'runtime_version',
      'activation_deadline',
    ]) {
      _validateString(copied[key], key);
    }
    final activationDeadline = copied['activation_deadline']! as String;
    final parsedActivationDeadline = DateTime.tryParse(activationDeadline);
    if (parsedActivationDeadline == null || !parsedActivationDeadline.isUtc) {
      throw const FormatException(
        'Install receipt activation deadline must be UTC',
      );
    }
    final installationKeyId = copied['key_id'];
    if (installationKeyId is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(installationKeyId)) {
      throw const FormatException(
        'Install receipt installation key ID is invalid',
      );
    }
    final artifactDigest = copied['artifact_digest'];
    if (artifactDigest is! String ||
        !RegExp(r'^(?:sha256:)?[0-9a-f]{64}$').hasMatch(artifactDigest)) {
      throw const FormatException('Install receipt artifact digest is invalid');
    }
    if (copied['result'] != 'activated') {
      throw const FormatException('Install receipt result is invalid');
    }

    final canonical = <String, Object?>{
      for (final key in copied.keys.toList()..sort()) key: copied[key],
    };
    try {
      if (utf8.encode(jsonEncode(canonical)).length > maxBodyBytes) {
        throw const FormatException('Install receipt body exceeds byte limit');
      }
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Install receipt body is not JSON-safe');
    }
    return Map.unmodifiable(canonical);
  }

  static Object? _copyJsonValue(Object? value) {
    if (value == null || value is String || value is bool || value is int) {
      return value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw const FormatException('Install receipt contains non-finite JSON');
      }
      return value;
    }
    if (value is List) {
      return List.unmodifiable(value.map(_copyJsonValue));
    }
    if (value is Map) {
      final copied = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FormatException(
            'Install receipt nested keys must be strings',
          );
        }
        copied[entry.key as String] = _copyJsonValue(entry.value);
      }
      return Map.unmodifiable(copied);
    }
    throw const FormatException('Install receipt body is not JSON-safe');
  }

  static void _validateString(Object? value, String field) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maxFieldLength ||
        value.contains('\u0000') ||
        value.contains('\r') ||
        value.contains('\n')) {
      throw FormatException('Install receipt $field is invalid');
    }
  }
}
