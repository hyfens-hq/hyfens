import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

const _seed = <int>[
  0x9d,
  0x61,
  0xb1,
  0x9d,
  0xef,
  0xfd,
  0x5a,
  0x60,
  0xba,
  0x84,
  0x4a,
  0xf4,
  0x92,
  0xec,
  0x2c,
  0xc4,
  0x44,
  0x49,
  0xc5,
  0x69,
  0x7b,
  0x32,
  0x69,
  0x19,
  0x70,
  0x3b,
  0xac,
  0x03,
  0x1c,
  0xae,
  0x7f,
  0x60,
];

Future<List<int>> _publicKey(List<int> seed) async =>
    (await DartEd25519().newKeyPairFromSeed(seed))
        .extractPublicKey()
        .then((value) => value.bytes);

AuditExport _export({bool valid = true}) {
  final body = <String, Object?>{
    'id': 'audit_001',
    'organizationId': 'org_demo',
    'action': 'patch.deploy',
    'createdAt': '2026-08-23T12:00:00.000Z',
  };
  final entry = <String, Object?>{
    'sequence': 1,
    'auditId': 'audit_001',
    'organizationId': 'org_demo',
    'previousDigest': null,
    'recordDigest': sha256Digest(utf8.encode(canonicalJson(body))),
    'body': body,
  };
  return AuditExport(
    retentionDays: 30,
    records: <Map<String, Object?>>[body],
    chain: <Map<String, Object?>>[entry],
    verification: valid
        ? verifyAuditChain(<Map<String, Object?>>[entry])
        : const AuditChainVerification(
            valid: false,
            entries: 1,
            failure: 'test_invalid',
          ),
  );
}

void main() {
  test('signs and verifies a deterministic export offline', () async {
    final bytes = await SignedAuditExport.sign(
      export: _export(),
      organizationId: 'org_demo',
      exportTimestamp: DateTime.utc(2026, 8, 23, 12),
      keyId: 'audit-key-2026-08',
      privateKeySeed: _seed,
    );
    final repeated = await SignedAuditExport.sign(
      export: _export(),
      organizationId: 'org_demo',
      exportTimestamp: DateTime.utc(2026, 8, 23, 12),
      keyId: 'audit-key-2026-08',
      privateKeySeed: _seed,
    );
    expect(bytes, orderedEquals(repeated));
    final verified = await SignedAuditExport.verify(
      bytes: bytes,
      publicKey: await _publicKey(_seed),
      expectedOrganizationId: 'org_demo',
      expectedKeyId: 'audit-key-2026-08',
    );
    expect(verified.retentionDays, 30);
    expect(verified.records, hasLength(1));
    expect(verified.verification.valid, isTrue);
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(envelope['firstSequence'], 1);
    expect(envelope['lastSequence'], 1);
    expect(envelope['recordCount'], 1);

    final directory = await Directory.systemTemp.createTemp('hyfens-audit-');
    try {
      final file = File('${directory.path}/export.json');
      await file.writeAsBytes(bytes, flush: true);
      final copied = await file.readAsBytes();
      await expectLater(
        SignedAuditExport.verify(
          bytes: copied,
          publicKey: await _publicKey(_seed),
        ),
        completes,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'rejects record, sequence, identity, key, and signature tampering',
    () async {
      final bytes = await SignedAuditExport.sign(
        export: _export(),
        organizationId: 'org_demo',
        exportTimestamp: DateTime.utc(2026, 8, 23),
        keyId: 'audit-key',
        privateKeySeed: _seed,
      );
      Future<void> expectRejected(Map<String, dynamic> envelope) async {
        await expectLater(
          SignedAuditExport.verify(
            bytes: utf8.encode(canonicalJson(envelope)),
            publicKey: await _publicKey(_seed),
          ),
          throwsA(isA<FormatException>()),
        );
      }

      Map<String, dynamic> freshEnvelope() =>
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      final envelope = freshEnvelope();
      final records = envelope['records'] as List<dynamic>;
      (records.single as Map<String, dynamic>)['action'] = 'tampered';
      await expectRejected(envelope);

      final removed = freshEnvelope();
      (removed['records'] as List<dynamic>).removeAt(0);
      await expectRejected(removed);

      final inserted = freshEnvelope();
      (inserted['records'] as List<dynamic>).add(<String, Object?>{
        'id': 'audit_002',
        'organizationId': 'org_demo',
        'action': 'unexpected',
      });
      await expectRejected(inserted);

      final sequence = freshEnvelope();
      ((sequence['chain'] as List<dynamic>).single
              as Map<String, dynamic>)['sequence'] =
          2;
      await expectRejected(sequence);

      final changedOrganization = freshEnvelope();
      changedOrganization['organizationId'] = 'org_other';
      await expectRejected(changedOrganization);

      final changedRetention = freshEnvelope();
      changedRetention['retentionDays'] = 31;
      await expectRejected(changedRetention);

      await expectLater(
        SignedAuditExport.verify(
          bytes: bytes,
          publicKey: await _publicKey(List<int>.filled(32, 7)),
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        SignedAuditExport.verify(
          bytes: bytes,
          publicKey: await _publicKey(_seed),
          expectedOrganizationId: 'org_other',
        ),
        throwsA(isA<FormatException>()),
      );

      final signature = envelope['signature'] as String;
      envelope['signature'] =
          '${signature.substring(0, signature.length - 2)}AA';
      await expectRejected(envelope);
    },
  );

  test('refuses signing an invalid chain and malformed envelopes', () async {
    await expectLater(
      SignedAuditExport.sign(
        export: _export(valid: false),
        organizationId: 'org_demo',
        exportTimestamp: DateTime.utc(2026, 8, 23),
        keyId: 'audit-key',
        privateKeySeed: _seed,
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      SignedAuditExport.verify(
        bytes: utf8.encode('{}'),
        publicKey: await _publicKey(_seed),
      ),
      throwsA(isA<FormatException>()),
    );

    final valid = await SignedAuditExport.sign(
      export: _export(),
      organizationId: 'org_demo',
      exportTimestamp: DateTime.utc(2026, 8, 23),
      keyId: 'audit-key',
      privateKeySeed: _seed,
    );
    final envelope = jsonDecode(utf8.decode(valid)) as Map<String, dynamic>;
    envelope['firstSequence'] = 99;
    await expectLater(
      SignedAuditExport.verify(
        bytes: utf8.encode(canonicalJson(envelope)),
        publicKey: await _publicKey(_seed),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
