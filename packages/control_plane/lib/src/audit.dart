import 'dart:convert';

import 'encoding.dart';

final class AuditExport {
  const AuditExport({
    required this.retentionDays,
    required this.records,
    required this.chain,
    required this.verification,
  });

  final int retentionDays;
  final List<Map<String, Object?>> records;
  final List<Map<String, Object?>> chain;
  final AuditChainVerification verification;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'retentionDays': retentionDays,
    'records': records,
    'chain': chain,
    'verification': verification.toJson(),
  };
}

/// One durable link in the control-plane audit chain.
final class AuditChainEntry {
  const AuditChainEntry({
    required this.sequence,
    required this.auditId,
    required this.organizationId,
    required this.previousDigest,
    required this.recordDigest,
    required this.body,
  });

  final int sequence;
  final String auditId;
  final String? organizationId;
  final String? previousDigest;
  final String recordDigest;
  final Map<String, Object?> body;

  factory AuditChainEntry.fromJson(Map<String, Object?> value) {
    final body = value['body'];
    if (body is! Map) throw const FormatException('Invalid audit chain body');
    return AuditChainEntry(
      sequence: _int(value['sequence'], 'audit sequence'),
      auditId: _string(value['auditId'], 'audit ID'),
      organizationId: value['organizationId'] as String?,
      previousDigest: value['previousDigest'] as String?,
      recordDigest: _string(value['recordDigest'], 'audit record digest'),
      body: body.map<String, Object?>((key, item) => MapEntry('$key', item)),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': sequence,
    'auditId': auditId,
    'organizationId': organizationId,
    'previousDigest': previousDigest,
    'recordDigest': recordDigest,
    'body': body,
  };
}

final class AuditChainVerification {
  const AuditChainVerification({
    required this.valid,
    required this.entries,
    this.failure,
  });

  final bool valid;
  final int entries;
  final String? failure;

  Map<String, Object?> toJson() => <String, Object?>{
    'valid': valid,
    'entries': entries,
    if (failure != null) 'failure': failure,
  };
}

/// Verifies sequence ordering, previous-link continuity, and the digest of
/// each canonical audit body. PostgreSQL sequence allocators may consume a
/// value for a rolled-back or idempotent insert, so numeric gaps alone are not
/// evidence of tampering; the cryptographic previous link remains mandatory.
/// It never repairs or rewrites an audit chain.
AuditChainVerification verifyAuditChain(
  Iterable<Map<String, Object?>> rawEntries,
) {
  try {
    final entries =
        rawEntries.map(AuditChainEntry.fromJson).toList(growable: false)
          ..sort((left, right) => left.sequence.compareTo(right.sequence));
    String? previous;
    var previousSequence = 0;
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (entry.sequence <= previousSequence) {
        return AuditChainVerification(
          valid: false,
          entries: entries.length,
          failure: 'sequence_order_at_${entry.sequence}',
        );
      }
      previousSequence = entry.sequence;
      if (entry.previousDigest != previous) {
        return AuditChainVerification(
          valid: false,
          entries: entries.length,
          failure: 'previous_digest_mismatch_at_${entry.sequence}',
        );
      }
      final digest = sha256Digest(utf8.encode(canonicalJson(entry.body)));
      if (digest != entry.recordDigest) {
        return AuditChainVerification(
          valid: false,
          entries: entries.length,
          failure: 'record_digest_mismatch_at_${entry.sequence}',
        );
      }
      previous = entry.recordDigest;
    }
    return AuditChainVerification(valid: true, entries: entries.length);
  } on Object catch (error) {
    return AuditChainVerification(
      valid: false,
      entries: 0,
      failure: 'malformed_chain:${error.runtimeType}',
    );
  }
}

int _int(Object? value, String name) {
  if (value is! int || value <= 0) throw FormatException('Invalid $name');
  return value;
}

String _string(Object? value, String name) {
  if (value is! String || value.isEmpty) throw FormatException('Invalid $name');
  return value;
}
