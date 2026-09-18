import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:test/test.dart';

const _keyId = 'closure-key';

void main() {
  late Directory directory;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  late DateTime now;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-control-plane-closure-',
    );
    now = DateTime.utc(2026, 8, 23, 12);
    service = ControlPlaneService(
      store: FileControlPlaneStore(directory),
      random: Random(9),
      clock: () => now,
    );
    bootstrap = await service.bootstrap(
      organizationName: 'Closure organization',
      runtimeApplicationId: 'com.example.closure',
      platformId: 'android-arm64-release',
      environmentName: 'development',
    );
  });

  tearDown(() => directory.delete(recursive: true));

  Future<ReleaseRecord> registerRelease() async {
    final publicKey = await _publicKey();
    return service.registerRelease(
      token: bootstrap.controlCredential.token,
      idempotencyKey: 'closure-release',
      spec: ReleaseSpec(
        applicationId: bootstrap.application.id,
        platformId: 'closure_android',
        runtimeApplicationId: 'com.example.closure',
        runtimeReleaseId: 'closure-release',
        buildTarget: 'android-arm64-release',
        runtimeCompatibilityVersion: 1,
        patchFormatVersion: 1,
        buildFingerprint: _digest('build'),
        capabilityAuthorityDigest: _digest('capabilities'),
        functionSignatureDigest: _digest('functions'),
        displayVersion: '0.1.0',
        signingPublicKeys: <String, String>{_keyId: base64.encode(publicKey)},
      ),
    );
  }

  UpdateCheckRequest updateRequest({
    String runtimeReleaseId = 'release-unused',
    int highWaterSequence = 0,
  }) => UpdateCheckRequest(
    applicationId: bootstrap.application.id,
    environmentId: bootstrap.environment.id,
    runtimeApplicationId: 'com.example.closure',
    runtimeReleaseId: runtimeReleaseId,
    runtimeCompatibilityVersion: 1,
    patchFormatVersion: 1,
    highWaterSequence: highWaterSequence,
  );

  test('control and delivery credentials rotate, expire, and revoke', () async {
    final replacementDelivery = await service.issueCredential(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
      kind: CredentialKind.delivery,
      scopes: deliveryScopes,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      expiresAt: now.add(const Duration(hours: 1)),
    );
    await service.revokeCredential(
      token: bootstrap.controlCredential.token,
      credentialId: bootstrap.deliveryCredential.record.id,
      organizationId: bootstrap.organization.id,
    );
    await expectLater(
      service.updateCheck(
        token: bootstrap.deliveryCredential.token,
        request: updateRequest(),
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'UNAUTHORIZED',
        ),
      ),
    );
    expect(
      (await service.updateCheck(
        token: replacementDelivery.token,
        request: updateRequest(),
      )).decision,
      'NO_UPDATE',
    );

    final replacementControl = await service.issueCredential(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
      kind: CredentialKind.control,
      scopes: controlScopes,
    );
    await service.revokeCredential(
      token: bootstrap.controlCredential.token,
      credentialId: bootstrap.controlCredential.record.id,
      organizationId: bootstrap.organization.id,
    );
    expect(
      (await service.readAudit(
        token: replacementControl.token,
        organizationId: bootstrap.organization.id,
      )).isNotEmpty,
      isTrue,
    );

    final expiring = await service.issueCredential(
      token: replacementControl.token,
      organizationId: bootstrap.organization.id,
      kind: CredentialKind.control,
      scopes: controlScopes,
      expiresAt: now.add(const Duration(minutes: 1)),
    );
    now = now.add(const Duration(minutes: 2));
    await expectLater(
      service.readAudit(
        token: expiring.token,
        organizationId: bootstrap.organization.id,
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'UNAUTHORIZED',
        ),
      ),
    );
  });

  test(
    'reconciliation quarantines missing/corrupt objects and detects orphans',
    () async {
      final release = await registerRelease();
      final bytes = await _patchBytes(
        releaseId: 'closure-release',
        patchId: 'closure-patch',
        sequence: 1,
      );
      final patch = await service.registerPatch(
        token: bootstrap.controlCredential.token,
        releaseId: release.id,
        idempotencyKey: 'closure-patch',
        spec: PatchSpec(
          runtimePatchId: 'closure-patch',
          sequence: 1,
          artifactId: 'closure_artifact',
          sha256: sha256Digest(bytes),
          sizeBytes: bytes.length,
          signatureKeyId: _keyId,
        ),
      );
      await service.uploadArtifact(
        token: bootstrap.controlCredential.token,
        artifactId: patch.artifactId,
        bytes: bytes,
        idempotencyKey: 'closure-artifact',
      );
      await service.promote(
        token: bootstrap.controlCredential.token,
        environmentId: bootstrap.environment.id,
        releaseId: release.id,
        expectedVersion: 0,
        idempotencyKey: 'closure-promote',
      );

      final initial = await service.reconcileArtifacts(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
      );
      expect(initial.items.map((item) => item.status), contains('verified'));
      expect(initial.inventoryAvailable, isTrue);

      final orphanBytes = utf8.encode('orphan-object');
      await (service.store as FileControlPlaneStore).putArtifact(
        sha256Digest(orphanBytes),
        orphanBytes,
      );
      final artifactFile = File(
        '${directory.path}/artifacts/${sha256Digest(bytes).substring(7)}/bytes',
      );
      await artifactFile.delete();
      final missing = await service.reconcileArtifacts(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
      );
      expect(
        missing.items.map((item) => item.status),
        contains('missing_object'),
      );
      expect(
        missing.items.map((item) => item.status),
        contains('orphan_object'),
      );

      final storedArtifact = await service.store.readJson(
        'artifacts',
        patch.artifactId,
      );
      await service.store.replaceJson(
        'artifacts',
        patch.artifactId,
        <String, Object?>{...storedArtifact!, 'state': 'READY'},
      );
      await artifactFile.writeAsString('tampered');
      final corrupt = await service.reconcileArtifacts(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
      );
      expect(
        corrupt.items.map((item) => item.status),
        contains('digest_mismatch'),
      );
      expect(
        (await service.updateCheck(
          token: bootstrap.deliveryCredential.token,
          request: updateRequest(
            runtimeReleaseId: 'closure-release',
            highWaterSequence: 0,
          ),
        )).decision,
        'NO_UPDATE',
      );
    },
  );

  test('audit export verifies its chain and detects tampering', () async {
    await service.issueCredential(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
      kind: CredentialKind.control,
      scopes: controlScopes,
    );
    final before = await service.exportAudit(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
      retentionDays: 30,
    );
    expect(before.retentionDays, 30);
    expect(before.verification.valid, isTrue);
    expect(before.records, isNotEmpty);

    final chain = await service.store.readAuditChain();
    final first = chain.first;
    final body = Map<String, Object?>.from(first['body']! as Map);
    body['action'] = 'tampered';
    await service.store.replaceJson(
      'audit_chain',
      first['auditId']! as String,
      <String, Object?>{...first, 'body': body},
    );
    final after = await service.exportAudit(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
    );
    expect(after.verification.valid, isFalse);
    expect(after.verification.failure, contains('record_digest_mismatch'));
  });

  test('audit export applies its requested retention window', () async {
    await service.issueCredential(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
      kind: CredentialKind.control,
      scopes: controlScopes,
    );
    now = now.add(const Duration(days: 2));
    await service.issueCredential(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
      kind: CredentialKind.control,
      scopes: controlScopes,
    );

    final export = await service.exportAudit(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
      retentionDays: 1,
    );
    expect(export.records, hasLength(1));
    expect(export.chain, hasLength(1));
    expect(export.verification.valid, isTrue);
    expect(export.verification.entries, 2);
  });
}

String _digest(String value) => 'sha256:${sha256.convert(utf8.encode(value))}';

Future<List<int>> _publicKey() async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(
    List<int>.filled(32, 7),
  );
  try {
    return (await keyPair.extractPublicKey()).bytes;
  } finally {
    keyPair.destroy();
  }
}

Future<List<int>> _patchBytes({
  required String releaseId,
  required String patchId,
  required int sequence,
}) async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(
    List<int>.filled(32, 7),
  );
  try {
    final artifact = await PatchFormatV1.sealAsync(
      PatchArtifact(
        runtimeCompatibilityVersion: 1,
        applicationId: 'com.example.closure',
        releaseId: releaseId,
        patchId: patchId,
        sequence: sequence,
        functions: <PatchFunctionEntry>[
          PatchFunctionEntry(
            id: 'lib:closure#calculate',
            slot: 0,
            signatureDigest: _digest('signature'),
          ),
        ],
        capabilities: const <PatchCapabilityEntry>[],
        constants: const <PatchValue>[],
        instructions: const <int>[0],
        signatureMetadata: PatchSignatureMetadata(
          algorithm: 'ed25519',
          keyId: _keyId,
        ),
        payloadDigest: const <int>[],
        signature: const <int>[],
      ),
      (message) async {
        final signature = await DartEd25519().sign(message, keyPair: keyPair);
        return signature.bytes;
      },
    );
    return PatchFormatV1.encode(artifact);
  } finally {
    keyPair.destroy();
  }
}
