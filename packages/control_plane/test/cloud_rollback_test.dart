import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

const _keyId = 'cloud-rollback-test-key';
const _runtimeApplicationId = 'com.example.cloud.rollback';
const _runtimeReleaseId = 'cloud-rollback-release-1';
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

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-cloud-rollback-');
    store = FileControlPlaneStore(directory);
    service = ControlPlaneService(
      store: store,
      deploymentModel: DeploymentModel.cloud,
    );
    bootstrap = await service.bootstrap(
      organizationName: 'Cloud rollback test',
      runtimeApplicationId: _runtimeApplicationId,
      platformId: 'plt_android_arm64_release',
      environmentName: 'production',
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('customer-authorized rollback is idempotent, audited, and projected to runtime', () async {
    final publicKey = await _publicKey();
    final patchBytes = await _patchBytes(sequence: 1);
    final release = await service.registerRelease(
      token: bootstrap.controlCredential.token,
      idempotencyKey: 'release-1',
      spec: ReleaseSpec(
        applicationId: bootstrap.application.id,
        platformId: 'plt_android_arm64_release',
        runtimeApplicationId: _runtimeApplicationId,
        runtimeReleaseId: _runtimeReleaseId,
        buildTarget: 'android-arm64-release',
        runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
        patchFormatVersion: patchFormatV1,
        buildFingerprint: _digest('build'),
        capabilityAuthorityDigest: _digest('capability'),
        functionSignatureDigest: _digest('functions'),
        displayVersion: '0.1.0',
        signingPublicKeys: <String, String>{_keyId: base64.encode(publicKey)},
      ),
    );
    final patch = await service.registerPatch(
      token: bootstrap.controlCredential.token,
      releaseId: release.id,
      idempotencyKey: 'patch-1',
      spec: PatchSpec(
        runtimePatchId: 'cloud-rollback-patch-1',
        sequence: 1,
        artifactId: 'art_cloud_rollback_1',
        sha256: sha256Digest(patchBytes),
        sizeBytes: patchBytes.length,
        signatureKeyId: _keyId,
      ),
    );
    await service.uploadArtifact(
      token: bootstrap.controlCredential.token,
      artifactId: patch.artifactId,
      bytes: patchBytes,
      idempotencyKey: 'artifact-1',
    );
    await service.promote(
      token: bootstrap.controlCredential.token,
      environmentId: bootstrap.environment.id,
      releaseId: release.id,
      expectedVersion: 0,
      idempotencyKey: 'promotion-1',
    );

    final rollbackControl = await _rollbackControl(
      applicationId: _runtimeApplicationId,
      releaseId: _runtimeReleaseId,
      sequence: 1,
      digest: sha256Digest(patchBytes).substring('sha256:'.length),
    );
    final encodedControl = base64.encode(rollbackControl.encodeBytes());
    final concurrent = await Future.wait(<Future<CloudRollbackResult>>[
      service.requestRollback(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
        applicationId: bootstrap.application.id,
        environmentId: bootstrap.environment.id,
        rollbackControl: encodedControl,
        idempotencyKey: 'rollback-concurrent-1',
      ),
      service.requestRollback(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
        applicationId: bootstrap.application.id,
        environmentId: bootstrap.environment.id,
        rollbackControl: encodedControl,
        idempotencyKey: 'rollback-concurrent-2',
      ),
    ]);
    // Future.wait preserves invocation order; the service write queue must
    // therefore make the first request the state-changing one.
    final requested = concurrent.first;
    final concurrentAlreadyBase = concurrent[1];
    expect(requested.status, 'ROLLBACK_REQUESTED');
    expect(requested.desiredState, RuntimeDesiredState.base);
    expect(requested.changed, isTrue);
    expect(concurrentAlreadyBase.status, 'ALREADY_BASE');
    expect(concurrentAlreadyBase.revision, requested.revision);

    final replay = await service.requestRollback(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      rollbackControl: encodedControl,
      idempotencyKey: 'rollback-concurrent-1',
    );
    expect(replay.toJson(), requested.toJson());

    final alreadyBase = await service.requestRollback(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      rollbackControl: encodedControl,
      idempotencyKey: 'rollback-2',
    );
    expect(alreadyBase.status, 'ALREADY_BASE');
    expect(alreadyBase.changed, isFalse);

    await expectLater(
      service.requestRollback(
        token: bootstrap.deliveryCredential.token,
        organizationId: bootstrap.organization.id,
        applicationId: bootstrap.application.id,
        environmentId: bootstrap.environment.id,
        rollbackControl: encodedControl,
        idempotencyKey: 'rollback-delivery-credential',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'FORBIDDEN',
        ),
      ),
    );

    final rollbackProjection = await service.updateCheck(
      token: bootstrap.deliveryCredential.token,
      request: UpdateCheckRequest(
        applicationId: bootstrap.application.id,
        environmentId: bootstrap.environment.id,
        runtimeApplicationId: _runtimeApplicationId,
        runtimeReleaseId: _runtimeReleaseId,
        runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
        patchFormatVersion: patchFormatV1,
        highWaterSequence: 1,
        highWaterDigest: rollbackControl.highWaterDigest,
        platformId: 'plt_android_arm64_release',
      ),
    );
    expect(rollbackProjection.decision, 'ROLLBACK_TO_BASE');
    expect(rollbackProjection.rollbackControl, encodedControl);
    expect(rollbackProjection.applicationId, bootstrap.application.id);
    expect(rollbackProjection.environmentId, bootstrap.environment.id);
    expect(rollbackProjection.platformId, 'plt_android_arm64_release');

    final staleHighWater = await service.updateCheck(
      token: bootstrap.deliveryCredential.token,
      request: UpdateCheckRequest(
        applicationId: bootstrap.application.id,
        environmentId: bootstrap.environment.id,
        runtimeApplicationId: _runtimeApplicationId,
        runtimeReleaseId: _runtimeReleaseId,
        runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
        patchFormatVersion: patchFormatV1,
        highWaterSequence: 0,
        platformId: 'plt_android_arm64_release',
      ),
    );
    expect(staleHighWater.decision, 'STORE_RELEASE_REQUIRED');

    final audit = await service.readAudit(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
    );
    expect(
      audit.map((record) => record.action),
      contains('environment.rollback.request'),
    );
    expect(
      jsonEncode(audit.map((record) => record.toJson()).toList()),
      isNot(contains(rollbackControl.encode())),
    );

    // The rollback state is superseded by a newer valid deployment. The
    // retained high-water then prevents patch 1 from being rediscovered.
    final patch2Bytes = await _patchBytes(sequence: 2);
    final patch2 = await service.registerPatch(
      token: bootstrap.controlCredential.token,
      releaseId: release.id,
      idempotencyKey: 'patch-2',
      spec: PatchSpec(
        runtimePatchId: 'cloud-rollback-patch-2',
        sequence: 2,
        artifactId: 'art_cloud_rollback_2',
        sha256: sha256Digest(patch2Bytes),
        sizeBytes: patch2Bytes.length,
        signatureKeyId: _keyId,
      ),
    );
    await service.uploadArtifact(
      token: bootstrap.controlCredential.token,
      artifactId: patch2.artifactId,
      bytes: patch2Bytes,
      idempotencyKey: 'artifact-2',
    );
    await service.promote(
      token: bootstrap.controlCredential.token,
      environmentId: bootstrap.environment.id,
      releaseId: release.id,
      expectedVersion: 1,
      idempotencyKey: 'promotion-2',
    );
    final patchProjection = await service.updateCheck(
      token: bootstrap.deliveryCredential.token,
      request: UpdateCheckRequest(
        applicationId: bootstrap.application.id,
        environmentId: bootstrap.environment.id,
        runtimeApplicationId: _runtimeApplicationId,
        runtimeReleaseId: _runtimeReleaseId,
        runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
        patchFormatVersion: patchFormatV1,
        highWaterSequence: 1,
        highWaterDigest: rollbackControl.highWaterDigest,
        platformId: 'plt_android_arm64_release',
      ),
    );
    expect(patchProjection.decision, 'PATCH_AVAILABLE');
    expect(patchProjection.patch!.sequence, 2);
  });

  test(
    'foreign customer cannot request rollback for another organization',
    () async {
      final other = await service.bootstrap(
        organizationName: 'Other organization',
        runtimeApplicationId: 'com.example.other',
        platformId: 'plt_android_arm64_release',
        environmentName: 'production',
      );

      await expectLater(
        service.requestRollback(
          token: other.controlCredential.token,
          organizationId: other.organization.id,
          applicationId: bootstrap.application.id,
          environmentId: bootstrap.environment.id,
          rollbackControl: 'not-a-control',
          idempotencyKey: 'foreign-rollback',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'NOT_FOUND',
          ),
        ),
      );
    },
  );
}

Future<List<int>> _publicKey() async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(_seed);
  try {
    return (await keyPair.extractPublicKey()).bytes;
  } finally {
    keyPair.destroy();
  }
}

Future<RollbackControlCommand> _rollbackControl({
  required String applicationId,
  required String releaseId,
  required int sequence,
  required String digest,
}) async {
  final algorithm = DartEd25519();
  final keyPair = await algorithm.newKeyPairFromSeed(_seed);
  try {
    return await RollbackControlCommand.sign(
      applicationId: applicationId,
      releaseId: releaseId,
      highWaterSequence: sequence,
      highWaterDigest: digest,
      keyId: _keyId,
      signer: (message) async =>
          (await algorithm.sign(message, keyPair: keyPair)).bytes,
    );
  } finally {
    keyPair.destroy();
  }
}

Future<List<int>> _patchBytes({required int sequence}) async {
  final algorithm = DartEd25519();
  final keyPair = await algorithm.newKeyPairFromSeed(_seed);
  try {
    final artifact = await PatchFormatV1.sealAsync(
      PatchArtifact(
        runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
        applicationId: _runtimeApplicationId,
        releaseId: _runtimeReleaseId,
        patchId: 'cloud-rollback-patch-$sequence',
        sequence: sequence,
        functions: <PatchFunctionEntry>[
          PatchFunctionEntry(
            id: 'cloud:rollback',
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
      (message) async =>
          (await algorithm.sign(message, keyPair: keyPair)).bytes,
    );
    return PatchFormatV1.encode(artifact);
  } finally {
    keyPair.destroy();
  }
}

String _digest(Object value) {
  final bytes = value is List<int> ? value : utf8.encode(value.toString());
  return 'sha256:${sha256.convert(bytes)}';
}
