import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'audit.dart';
import 'encoding.dart';

/// Signs a control-plane audit export for offline custody and verification.
///
/// This envelope is intentionally independent of Patch Format v1 and patch
/// signing. The control plane never receives the private key: an operator
/// obtains the authenticated [AuditExport], then signs the deterministic
/// bytes locally or in an offline evidence environment.
final class SignedAuditExport {
  static const int formatVersion = 1;
  static const String algorithmName = 'ed25519';
  static const String domain = 'hyfens.audit-export.v1';
  static const int maxRecords = 100000;
  static const int maxBytes = 16 * 1024 * 1024;
  static const Set<String> _envelopeKeys = <String>{
    'formatVersion',
    'organizationId',
    'exportTimestamp',
    'retentionDays',
    'firstSequence',
    'lastSequence',
    'recordCount',
    'records',
    'chain',
    'verification',
    'recordsDigest',
    'chainDigest',
    'exportDigest',
    'signatureMetadata',
    'signature',
  };
  static const Set<String> _signatureMetadataKeys = <String>{
    'algorithm',
    'keyId',
  };

  const SignedAuditExport._();

  static Future<List<int>> sign({
    required AuditExport export,
    required String organizationId,
    required DateTime exportTimestamp,
    required String keyId,
    required List<int> privateKeySeed,
  }) async {
    _requireOrganizationId(organizationId);
    _requireKeyId(keyId);
    if (privateKeySeed.length != 32) {
      throw const FormatException('Ed25519 private seed must be 32 bytes');
    }
    final chainVerification = verifyAuditChain(export.chain);
    if (!chainVerification.valid ||
        !_sameVerification(export.verification, chainVerification)) {
      throw const FormatException('Cannot sign an invalid audit chain');
    }
    _requireRecordLimit(export.records);
    final payload = _payload(
      export: export,
      organizationId: organizationId,
      exportTimestamp: exportTimestamp,
    );
    final withDigest = <String, Object?>{
      ...payload,
      'exportDigest': sha256Digest(utf8.encode(canonicalJson(payload))),
      'signatureMetadata': <String, Object?>{
        'algorithm': algorithmName,
        'keyId': keyId,
      },
    };
    final algorithm = DartEd25519();
    final keyPair = await algorithm.newKeyPairFromSeed(privateKeySeed);
    try {
      final signature = await algorithm.sign(
        _signingBytes(withDigest),
        keyPair: keyPair,
      );
      final envelope = <String, Object?>{
        ...withDigest,
        'signature': base64Encode(signature.bytes),
      };
      final bytes = utf8.encode(canonicalJson(envelope));
      if (bytes.length > maxBytes) {
        throw const FormatException(
          'Audit export exceeds maximum envelope size',
        );
      }
      return List<int>.unmodifiable(bytes);
    } finally {
      keyPair.destroy();
    }
  }

  /// Verifies a signed export without contacting a control plane.
  ///
  /// The returned export is still a report, not an authorization token. Callers
  /// should separately decide whether the signed organization, retention, and
  /// chain status are acceptable for their evidence workflow.
  static Future<AuditExport> verify({
    required List<int> bytes,
    required List<int> publicKey,
    String? expectedOrganizationId,
    String? expectedKeyId,
  }) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Invalid audit export envelope size');
    }
    if (publicKey.length != 32) {
      throw const FormatException('Ed25519 public key must be 32 bytes');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    final envelope = _object(decoded, 'audit export envelope');
    _requireExactKeys(envelope, _envelopeKeys, 'audit export envelope');
    if (canonicalJson(envelope) != utf8.decode(bytes)) {
      throw const FormatException('Audit export is not canonically encoded');
    }
    if (envelope['formatVersion'] != formatVersion) {
      throw const FormatException('Unsupported audit export format version');
    }
    final organizationId = _string(
      envelope['organizationId'],
      'organizationId',
    );
    _requireOrganizationId(organizationId);
    if (expectedOrganizationId != null &&
        expectedOrganizationId != organizationId) {
      throw const FormatException('Audit export organization mismatch');
    }
    final metadata = _object(
      envelope['signatureMetadata'],
      'signature metadata',
    );
    _requireExactKeys(metadata, _signatureMetadataKeys, 'signature metadata');
    if (metadata['algorithm'] != algorithmName) {
      throw const FormatException(
        'Unsupported audit export signature algorithm',
      );
    }
    final keyId = _string(metadata['keyId'], 'audit export key ID');
    _requireKeyId(keyId);
    if (expectedKeyId != null && expectedKeyId != keyId) {
      throw const FormatException('Audit export key ID mismatch');
    }
    final signatureText = _string(
      envelope['signature'],
      'audit export signature',
    );
    final signature = _decodeBase64(signatureText, 'audit export signature');
    final payload = _payloadFromEnvelope(envelope);
    final expectedExportDigest = sha256Digest(
      utf8.encode(canonicalJson(payload)),
    );
    if (envelope['exportDigest'] != expectedExportDigest) {
      throw const FormatException('Audit export digest mismatch');
    }
    final records = _records(envelope['records']);
    final chain = _records(envelope['chain']);
    final sequenceBounds = _sequenceBounds(chain);
    if (envelope['firstSequence'] != sequenceBounds.$1 ||
        envelope['lastSequence'] != sequenceBounds.$2 ||
        envelope['recordCount'] != records.length) {
      throw const FormatException('Audit export sequence metadata mismatch');
    }
    if (envelope['recordsDigest'] !=
        sha256Digest(utf8.encode(canonicalJson(records)))) {
      throw const FormatException('Audit export records digest mismatch');
    }
    if (envelope['chainDigest'] !=
        sha256Digest(utf8.encode(canonicalJson(chain)))) {
      throw const FormatException('Audit export chain digest mismatch');
    }
    final verification = _verification(envelope['verification']);
    final recomputedVerification = verifyAuditChain(chain);
    if (!_sameVerification(verification, recomputedVerification)) {
      throw const FormatException('Audit export chain verification mismatch');
    }
    final valid = await DartEd25519().verify(
      _signingBytes(_withoutSignature(envelope)),
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!valid) throw const FormatException('Invalid audit export signature');
    return AuditExport(
      retentionDays: _positiveInt(envelope['retentionDays'], 'retentionDays'),
      records: records,
      chain: chain,
      verification: verification,
    );
  }

  static Map<String, Object?> _payload({
    required AuditExport export,
    required String organizationId,
    required DateTime exportTimestamp,
  }) {
    final records = _records(export.records);
    final chain = _records(export.chain);
    final sequenceBounds = _sequenceBounds(chain);
    return <String, Object?>{
      'formatVersion': formatVersion,
      'organizationId': organizationId,
      'exportTimestamp': exportTimestamp.toUtc().toIso8601String(),
      'retentionDays': export.retentionDays,
      'firstSequence': sequenceBounds.$1,
      'lastSequence': sequenceBounds.$2,
      'recordCount': records.length,
      'records': records,
      'chain': chain,
      'verification': verifyAuditChain(chain).toJson(),
      'recordsDigest': sha256Digest(utf8.encode(canonicalJson(records))),
      'chainDigest': sha256Digest(utf8.encode(canonicalJson(chain))),
    };
  }

  static Map<String, Object?> _payloadFromEnvelope(
    Map<String, Object?> envelope,
  ) => <String, Object?>{
    'formatVersion': envelope['formatVersion'],
    'organizationId': envelope['organizationId'],
    'exportTimestamp': envelope['exportTimestamp'],
    'retentionDays': envelope['retentionDays'],
    'firstSequence': envelope['firstSequence'],
    'lastSequence': envelope['lastSequence'],
    'recordCount': envelope['recordCount'],
    'records': envelope['records'],
    'chain': envelope['chain'],
    'verification': envelope['verification'],
    'recordsDigest': envelope['recordsDigest'],
    'chainDigest': envelope['chainDigest'],
  };

  static Map<String, Object?> _withoutSignature(
    Map<String, Object?> envelope,
  ) => <String, Object?>{
    ..._payloadFromEnvelope(envelope),
    'exportDigest': envelope['exportDigest'],
    'signatureMetadata': envelope['signatureMetadata'],
  };

  static List<int> _signingBytes(Map<String, Object?> value) =>
      utf8.encode('$domain\n${canonicalJson(value)}');

  static List<Map<String, Object?>> _records(Object? value) {
    if (value is! List || value.length > maxRecords) {
      throw const FormatException('Invalid or oversized audit export records');
    }
    return List<Map<String, Object?>>.unmodifiable(
      value.map((item) => _object(item, 'audit export record')),
    );
  }

  static AuditChainVerification _verification(Object? value) {
    final object = _object(value, 'audit chain verification');
    final keys = object.keys.toSet();
    if (!(keys.length == 2 &&
            keys.contains('valid') &&
            keys.contains('entries')) &&
        !(keys.length == 3 &&
            keys.contains('valid') &&
            keys.contains('entries') &&
            keys.contains('failure'))) {
      throw const FormatException('Invalid audit chain verification fields');
    }
    final valid = object['valid'];
    final entries = object['entries'];
    if (valid is! bool || entries is! int || entries < 0) {
      throw const FormatException('Invalid audit chain verification');
    }
    final failure = object['failure'];
    if (failure != null && failure is! String) {
      throw const FormatException('Invalid audit chain verification failure');
    }
    return AuditChainVerification(
      valid: valid,
      entries: entries,
      failure: failure as String?,
    );
  }

  static bool _sameVerification(
    AuditChainVerification left,
    AuditChainVerification right,
  ) =>
      left.valid == right.valid &&
      left.entries == right.entries &&
      left.failure == right.failure;

  static Map<String, Object?> _object(Object? value, String name) {
    if (value is! Map) throw FormatException('Invalid $name');
    return value.map<String, Object?>((key, item) => MapEntry('$key', item));
  }

  static void _requireExactKeys(
    Map<String, Object?> value,
    Set<String> expected,
    String name,
  ) {
    final actual = value.keys.toSet();
    if (actual.length != expected.length ||
        actual.difference(expected).isNotEmpty ||
        expected.difference(actual).isNotEmpty) {
      throw FormatException('Invalid $name fields');
    }
  }

  static String _string(Object? value, String name) {
    if (value is! String || value.isEmpty)
      throw FormatException('Invalid $name');
    return value;
  }

  static int _positiveInt(Object? value, String name) {
    if (value is! int || value <= 0) throw FormatException('Invalid $name');
    return value;
  }

  static (int?, int?) _sequenceBounds(List<Map<String, Object?>> chain) {
    if (chain.isEmpty) return (null, null);
    final first = chain.first['sequence'];
    final last = chain.last['sequence'];
    if (first is! int || first < 0 || last is! int || last < 0) {
      throw const FormatException('Invalid audit sequence metadata');
    }
    return (first, last);
  }

  static List<int> _decodeBase64(String value, String name) {
    try {
      final decoded = base64Decode(value);
      if (decoded.length != 64) throw const FormatException('wrong length');
      return decoded;
    } on Object {
      throw FormatException('Invalid $name');
    }
  }

  static void _requireOrganizationId(String value) {
    if (!RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(value)) {
      throw const FormatException('Invalid organizationId');
    }
  }

  static void _requireKeyId(String value) {
    if (value.isEmpty || value.length > 128 || value.contains('\n')) {
      throw const FormatException('Invalid audit export key ID');
    }
  }

  static void _requireRecordLimit(List<Object?> records) {
    if (records.length > maxRecords) {
      throw const FormatException('Audit export record limit exceeded');
    }
  }
}
