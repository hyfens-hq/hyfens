import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:test/test.dart';

const publicKeyId = 'test-key';

void main() {
  late Directory directory;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  late List<int> patchBytes;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-control-plane-');
    service = ControlPlaneService(
      store: FileControlPlaneStore(directory),
      random: Random(1),
    );
    bootstrap = await service.bootstrap(
      organizationName: 'Test organization',
      runtimeApplicationId: 'com.example.test',
      platformId: 'android-arm64-release',
      environmentName: 'development',
    );
    patchBytes = await _patchBytes(
      releaseId: 'release-runtime-1',
      patchId: 'patch-runtime-1',
      sequence: 1,
    );
  });

  tearDown(() => directory.delete(recursive: true));

  test(
    'registers, verifies, promotes, and delivers exact signed bytes',
    () async {
      final publicKey = await _publicKey();
      final release = await service.registerRelease(
        token: bootstrap.controlCredential.token,
        idempotencyKey: 'release-1',
        spec: ReleaseSpec(
          applicationId: bootstrap.application.id,
          platformId: 'plt_android',
          runtimeApplicationId: 'com.example.test',
          runtimeReleaseId: 'release-runtime-1',
          buildTarget: 'android-arm64-release',
          runtimeCompatibilityVersion: 1,
          patchFormatVersion: 1,
          buildFingerprint: _digest('build'),
          capabilityAuthorityDigest: _digest('capabilities'),
          functionSignatureDigest: _digest('functions'),
          displayVersion: '0.1.0',
          signingPublicKeys: <String, String>{
            publicKeyId: base64.encode(publicKey),
          },
        ),
      );
      final patch = await service.registerPatch(
        token: bootstrap.controlCredential.token,
        releaseId: release.id,
        idempotencyKey: 'patch-1',
        spec: PatchSpec(
          runtimePatchId: 'patch-runtime-1',
          sequence: 1,
          artifactId: 'art_test_patch_1',
          sha256: sha256Digest(patchBytes),
          sizeBytes: patchBytes.length,
          signatureKeyId: publicKeyId,
        ),
      );
      final artifact = await service.uploadArtifact(
        token: bootstrap.controlCredential.token,
        artifactId: patch.artifactId,
        bytes: patchBytes,
        idempotencyKey: 'artifact-1',
      );
      expect(artifact.state, 'READY');
      final environment = await service.promote(
        token: bootstrap.controlCredential.token,
        environmentId: bootstrap.environment.id,
        releaseId: release.id,
        expectedVersion: 0,
        idempotencyKey: 'promote-1',
      );
      expect(environment.version, 1);
      final update = await service.updateCheck(
        token: bootstrap.deliveryCredential.token,
        request: UpdateCheckRequest(
          applicationId: bootstrap.application.id,
          environmentId: bootstrap.environment.id,
          runtimeApplicationId: 'com.example.test',
          runtimeReleaseId: 'release-runtime-1',
          runtimeCompatibilityVersion: 1,
          patchFormatVersion: 1,
          highWaterSequence: 0,
        ),
      );
      expect(update.decision, 'PATCH_AVAILABLE');
      expect(update.patch!.sequence, 1);
      final fetched = await service.fetchArtifact(
        token: bootstrap.deliveryCredential.token,
        artifactId: artifact.id,
        applicationId: bootstrap.application.id,
        environmentId: bootstrap.environment.id,
      );
      expect(fetched.bytes, patchBytes);
      expect(fetched.record.sha256, sha256Digest(patchBytes));
      final noUpdate = await service.updateCheck(
        token: bootstrap.deliveryCredential.token,
        request: UpdateCheckRequest(
          applicationId: bootstrap.application.id,
          environmentId: bootstrap.environment.id,
          runtimeApplicationId: 'com.example.test',
          runtimeReleaseId: 'release-runtime-1',
          runtimeCompatibilityVersion: 1,
          patchFormatVersion: 1,
          highWaterSequence: 1,
        ),
      );
      expect(noUpdate.decision, 'NO_UPDATE');
      final mutated = patchBytes.toList()..[0] = patchBytes[0] ^ 1;
      await expectLater(
        service.uploadArtifact(
          token: bootstrap.controlCredential.token,
          artifactId: artifact.id,
          bytes: mutated,
          idempotencyKey: 'artifact-mutated',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'ARTIFACT_DIGEST_MISMATCH',
          ),
        ),
      );
      final persistedArtifact = await FileControlPlaneStore(directory)
          .readJson('artifacts', artifact.id);
      expect(persistedArtifact!['state'], 'READY');
      final audit = await service.readAudit(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
      );
      expect(
        audit.map((record) => record.action),
        containsAll(<String>[
          'release.register',
          'patch.register',
          'artifact.upload',
          'release.promote',
        ]),
      );
      expect(
        jsonEncode(audit.map((record) => record.toJson()).toList()),
        isNot(contains(bootstrap.controlCredential.token)),
      );

      final promotionResults = await Future.wait(<Future<String?>>[
        service
            .promote(
              token: bootstrap.controlCredential.token,
              environmentId: bootstrap.environment.id,
              releaseId: release.id,
              expectedVersion: 1,
              idempotencyKey: 'parallel-a',
            )
            .then<String?>(
              (_) => null,
              onError: (Object error) {
                return (error as ControlPlaneException).code;
              },
            ),
        service
            .promote(
              token: bootstrap.controlCredential.token,
              environmentId: bootstrap.environment.id,
              releaseId: release.id,
              expectedVersion: 1,
              idempotencyKey: 'parallel-b',
            )
            .then<String?>(
              (_) => null,
              onError: (Object error) {
                return (error as ControlPlaneException).code;
              },
            ),
      ]);
      expect(promotionResults.whereType<String>(), <String>[
        'PRECONDITION_FAILED',
      ]);
    },
  );

  test(
    'control credentials can be revoked and are rejected thereafter',
    () async {
      await service.revokeCredential(
        token: bootstrap.controlCredential.token,
        credentialId: bootstrap.deliveryCredential.record.id,
        organizationId: bootstrap.organization.id,
      );
      await expectLater(
        service.updateCheck(
          token: bootstrap.deliveryCredential.token,
          request: UpdateCheckRequest(
            applicationId: bootstrap.application.id,
            environmentId: bootstrap.environment.id,
            runtimeApplicationId: 'com.example.test',
            runtimeReleaseId: 'release-runtime-1',
            runtimeCompatibilityVersion: 1,
            patchFormatVersion: 1,
            highWaterSequence: 0,
          ),
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'UNAUTHORIZED',
          ),
        ),
      );
    },
  );

  test('delivery credential cannot mutate control-plane state', () async {
    expect(
      () => service.registerRelease(
        token: bootstrap.deliveryCredential.token,
        idempotencyKey: 'release-delivery',
        spec: ReleaseSpec(
          applicationId: bootstrap.application.id,
          platformId: 'plt_android',
          runtimeApplicationId: 'com.example.test',
          runtimeReleaseId: 'release-runtime-delivery',
          buildTarget: 'android-arm64-release',
          runtimeCompatibilityVersion: 1,
          patchFormatVersion: 1,
          buildFingerprint: _digest('build'),
          capabilityAuthorityDigest: _digest('capabilities'),
          functionSignatureDigest: _digest('functions'),
          displayVersion: '0.1.0',
          signingPublicKeys: const <String, String>{},
        ),
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'FORBIDDEN',
        ),
      ),
    );
  });

  test('foreign tenant IDs have the same not-found boundary', () async {
    final other = await service.bootstrap(
      organizationName: 'Other organization',
      runtimeApplicationId: 'com.example.other',
      platformId: 'android-arm64-release',
      environmentName: 'development',
    );
    expect(
      () => service.registerRelease(
        token: bootstrap.controlCredential.token,
        idempotencyKey: 'foreign',
        spec: ReleaseSpec(
          applicationId: other.application.id,
          platformId: 'plt_android',
          runtimeApplicationId: 'com.example.other',
          runtimeReleaseId: 'other-release',
          buildTarget: 'android-arm64-release',
          runtimeCompatibilityVersion: 1,
          patchFormatVersion: 1,
          buildFingerprint: _digest('build'),
          capabilityAuthorityDigest: _digest('capabilities'),
          functionSignatureDigest: _digest('functions'),
          displayVersion: '0.1.0',
          signingPublicKeys: const <String, String>{},
        ),
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'NOT_FOUND',
        ),
      ),
    );
  });

  test(
    'idempotency and optimistic concurrency reject conflicting requests',
    () async {
      final publicKey = await _publicKey();
      final spec = ReleaseSpec(
        applicationId: bootstrap.application.id,
        platformId: 'plt_android',
        runtimeApplicationId: 'com.example.test',
        runtimeReleaseId: 'release-runtime-idempotent',
        buildTarget: 'android-arm64-release',
        runtimeCompatibilityVersion: 1,
        patchFormatVersion: 1,
        buildFingerprint: _digest('build'),
        capabilityAuthorityDigest: _digest('capabilities'),
        functionSignatureDigest: _digest('functions'),
        displayVersion: '0.1.0',
        signingPublicKeys: <String, String>{
          publicKeyId: base64.encode(publicKey),
        },
      );
      final first = await service.registerRelease(
        token: bootstrap.controlCredential.token,
        idempotencyKey: 'same-key',
        spec: spec,
      );
      final second = await service.registerRelease(
        token: bootstrap.controlCredential.token,
        idempotencyKey: 'same-key',
        spec: spec,
      );
      expect(second.id, first.id);
      expect(
        () => service.registerRelease(
          token: bootstrap.controlCredential.token,
          idempotencyKey: 'same-key',
          spec: ReleaseSpec(
            applicationId: spec.applicationId,
            platformId: spec.platformId,
            runtimeApplicationId: spec.runtimeApplicationId,
            runtimeReleaseId: 'different-release',
            buildTarget: spec.buildTarget,
            runtimeCompatibilityVersion: spec.runtimeCompatibilityVersion,
            patchFormatVersion: spec.patchFormatVersion,
            buildFingerprint: spec.buildFingerprint,
            capabilityAuthorityDigest: spec.capabilityAuthorityDigest,
            functionSignatureDigest: spec.functionSignatureDigest,
            displayVersion: spec.displayVersion,
            signingPublicKeys: spec.signingPublicKeys,
          ),
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'IDEMPOTENCY_KEY_REUSED',
          ),
        ),
      );
      expect(
        () => service.promote(
          token: bootstrap.controlCredential.token,
          environmentId: bootstrap.environment.id,
          releaseId: first.id,
          expectedVersion: 4,
          idempotencyKey: 'stale-promotion',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'PRECONDITION_FAILED',
          ),
        ),
      );
    },
  );

  test('invalid signatures are quarantined and never become ready', () async {
    final publicKey = await _publicKey();
    final release = await service.registerRelease(
      token: bootstrap.controlCredential.token,
      idempotencyKey: 'release-invalid',
      spec: ReleaseSpec(
        applicationId: bootstrap.application.id,
        platformId: 'plt_android',
        runtimeApplicationId: 'com.example.test',
        runtimeReleaseId: 'release-runtime-invalid',
        buildTarget: 'android-arm64-release',
        runtimeCompatibilityVersion: 1,
        patchFormatVersion: 1,
        buildFingerprint: _digest('build'),
        capabilityAuthorityDigest: _digest('capabilities'),
        functionSignatureDigest: _digest('functions'),
        displayVersion: '0.1.0',
        signingPublicKeys: <String, String>{
          publicKeyId: base64.encode(publicKey),
        },
      ),
    );
    final invalid = await _patchBytes(
      releaseId: 'release-runtime-invalid',
      patchId: 'patch-runtime-invalid',
      sequence: 1,
      corruptSignature: true,
    );
    final patch = await service.registerPatch(
      token: bootstrap.controlCredential.token,
      releaseId: release.id,
      idempotencyKey: 'patch-invalid',
      spec: PatchSpec(
        runtimePatchId: 'patch-runtime-invalid',
        sequence: 1,
        artifactId: 'art_invalid_patch',
        sha256: sha256Digest(invalid),
        sizeBytes: invalid.length,
        signatureKeyId: publicKeyId,
      ),
    );
    await expectLater(
      service.uploadArtifact(
        token: bootstrap.controlCredential.token,
        artifactId: patch.artifactId,
        bytes: invalid,
        idempotencyKey: 'artifact-invalid',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'INVALID_SIGNATURE',
        ),
      ),
    );
    final artifacts = await FileControlPlaneStore(directory)
        .readJson('artifacts', patch.artifactId);
    expect(artifacts!['state'], 'QUARANTINED');
  });

  test('wrong-release bytes and sequence equivocation fail closed', () async {
    final publicKey = await _publicKey();
    final release = await service.registerRelease(
      token: bootstrap.controlCredential.token,
      idempotencyKey: 'release-boundary',
      spec: ReleaseSpec(
        applicationId: bootstrap.application.id,
        platformId: 'plt_android',
        runtimeApplicationId: 'com.example.test',
        runtimeReleaseId: 'release-runtime-boundary',
        buildTarget: 'android-arm64-release',
        runtimeCompatibilityVersion: 1,
        patchFormatVersion: 1,
        buildFingerprint: _digest('build'),
        capabilityAuthorityDigest: _digest('capabilities'),
        functionSignatureDigest: _digest('functions'),
        displayVersion: '0.1.0',
        signingPublicKeys: <String, String>{
          publicKeyId: base64.encode(publicKey),
        },
      ),
    );
    final wrongReleaseBytes = await _patchBytes(
      releaseId: 'different-release',
      patchId: 'patch-runtime-boundary',
      sequence: 1,
    );
    final patch = await service.registerPatch(
      token: bootstrap.controlCredential.token,
      releaseId: release.id,
      idempotencyKey: 'patch-boundary',
      spec: PatchSpec(
        runtimePatchId: 'patch-runtime-boundary',
        sequence: 1,
        artifactId: 'art_boundary_patch',
        sha256: sha256Digest(wrongReleaseBytes),
        sizeBytes: wrongReleaseBytes.length,
        signatureKeyId: publicKeyId,
      ),
    );
    await expectLater(
      service.uploadArtifact(
        token: bootstrap.controlCredential.token,
        artifactId: patch.artifactId,
        bytes: wrongReleaseBytes,
        idempotencyKey: 'artifact-boundary',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'PATCH_EXACT_RELEASE_MISMATCH',
        ),
      ),
    );
    final sameSequenceBytes = await _patchBytes(
      releaseId: 'release-runtime-boundary',
      patchId: 'patch-runtime-boundary-2',
      sequence: 1,
    );
    await expectLater(
      service.registerPatch(
        token: bootstrap.controlCredential.token,
        releaseId: release.id,
        idempotencyKey: 'patch-equivocation',
        spec: PatchSpec(
          runtimePatchId: 'patch-runtime-boundary-2',
          sequence: 1,
          artifactId: 'art_boundary_patch_2',
          sha256: sha256Digest(sameSequenceBytes),
          sizeBytes: sameSequenceBytes.length,
          signatureKeyId: publicKeyId,
        ),
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'SEQUENCE_EQUIVOCATION',
        ),
      ),
    );
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
  bool corruptSignature = false,
}) async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(
    List<int>.filled(32, 7),
  );
  try {
    final artifact = await PatchFormatV1.sealAsync(
      PatchArtifact(
        runtimeCompatibilityVersion: 1,
        applicationId: 'com.example.test',
        releaseId: releaseId,
        patchId: patchId,
        sequence: sequence,
        functions: <PatchFunctionEntry>[
          PatchFunctionEntry(
            id: 'lib:test#calculate',
            slot: 0,
            signatureDigest: _digest('signature'),
          ),
        ],
        capabilities: const <PatchCapabilityEntry>[],
        constants: const <PatchValue>[],
        instructions: const <int>[0],
        signatureMetadata: PatchSignatureMetadata(
          algorithm: 'ed25519',
          keyId: publicKeyId,
        ),
        payloadDigest: const <int>[],
        signature: const <int>[],
      ),
      (message) async {
        final signature = await DartEd25519().sign(message, keyPair: keyPair);
        return signature.bytes;
      },
    );
    final bytes = PatchFormatV1.encode(artifact);
    if (!corruptSignature) return bytes;
    final decoded = PatchFormatV1.decode(bytes);
    final changed = decoded.signature.toList()..[0] = decoded.signature[0] ^ 1;
    return PatchFormatV1.encode(decoded.copyWith(signature: changed));
  } finally {
    keyPair.destroy();
  }
}
