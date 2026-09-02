import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:test/test.dart';

const _publicKeyId = 'rollout-test-key';

void main() {
  late _Fixture fixture;

  setUp(() async {
    fixture = await _Fixture.create();
  });

  tearDown(() => fixture.dispose());

  test('creates an immutable draft and records the audit event', () async {
    final snapshot = await fixture.createRollout(
      percentageBasisPoints: 10000,
      idempotencyKey: 'rollout-create',
    );

    expect(snapshot.rollout.state, RolloutState.draft);
    expect(snapshot.rollout.currentRevision, 1);
    expect(snapshot.revision.revision, 1);
    expect(snapshot.revision.previousRevision, isNull);
    expect(snapshot.revision.target.patchId, fixture.patch.id);
    expect(snapshot.history, hasLength(1));
    final audit = await fixture.service.readAudit(
      token: fixture.bootstrap.controlCredential.token,
      organizationId: fixture.bootstrap.organization.id,
    );
    expect(audit.map((record) => record.action), contains('rollout.created'));

    final retry = await fixture.createRollout(
      percentageBasisPoints: 10000,
      idempotencyKey: 'rollout-create',
    );
    expect(retry.rollout.id, snapshot.rollout.id);
    expect(retry.history, hasLength(1));
  });

  test(
    'transitions atomically, preserves history, and gates update lookup',
    () async {
      final created = await fixture.createRollout(
        percentageBasisPoints: 10000,
        idempotencyKey: 'rollout-create',
      );
      expect(
        (await fixture.updateCheck(installationId: 'install-a')).decision,
        'NO_UPDATE',
      );
      final ready = await fixture.transition(
        rolloutId: created.rollout.id,
        action: RolloutAction.ready,
        expectedRevision: 1,
        idempotencyKey: 'rollout-ready',
      );
      final canary = await fixture.transition(
        rolloutId: created.rollout.id,
        action: RolloutAction.startCanary,
        expectedRevision: 2,
        idempotencyKey: 'rollout-canary',
      );
      final canaryRetry = await fixture.transition(
        rolloutId: created.rollout.id,
        action: RolloutAction.startCanary,
        expectedRevision: 2,
        idempotencyKey: 'rollout-canary',
      );
      expect(ready.revision.state, RolloutState.ready);
      expect(canary.revision.state, RolloutState.canary);
      expect(canaryRetry.revision.revision, canary.revision.revision);
      expect(canary.history.map((revision) => revision.revision), [1, 2, 3]);

      final noIdentity = await fixture.updateCheck();
      expect(noIdentity.decision, 'NO_UPDATE');
      final eligible = await fixture.updateCheck(installationId: 'install-a');
      expect(eligible.decision, 'PATCH_AVAILABLE');
      expect(eligible.patch!.id, fixture.patch.id);
      expect(eligible.artifact!.id, fixture.artifact.id);

      final paused = await fixture.transition(
        rolloutId: created.rollout.id,
        action: RolloutAction.pause,
        expectedRevision: 3,
        idempotencyKey: 'rollout-pause',
      );
      expect(paused.revision.state, RolloutState.paused);
      expect(paused.revision.pausedFromState, RolloutState.canary);
      expect(
        (await fixture.updateCheck(installationId: 'install-a')).decision,
        'NO_UPDATE',
      );

      final resumed = await fixture.transition(
        rolloutId: created.rollout.id,
        action: RolloutAction.resume,
        expectedRevision: 4,
        idempotencyKey: 'rollout-resume',
      );
      expect(resumed.revision.state, RolloutState.canary);
      final halted = await fixture.transition(
        rolloutId: created.rollout.id,
        action: RolloutAction.halt,
        expectedRevision: 5,
        idempotencyKey: 'rollout-halt',
      );
      expect(halted.revision.state, RolloutState.halted);
      expect(
        (await fixture.updateCheck(installationId: 'install-a')).decision,
        'NO_UPDATE',
      );
      expect(halted.history, hasLength(6));

      final audit = await fixture.service.readAudit(
        token: fixture.bootstrap.controlCredential.token,
        organizationId: fixture.bootstrap.organization.id,
      );
      expect(
        audit.map((record) => record.action),
        containsAll(<String>[
          'rollout.ready',
          'rollout.started',
          'rollout.paused',
          'rollout.resumed',
          'rollout.halted',
        ]),
      );
    },
  );

  test('rejects stale transitions and overlapping targets', () async {
    final first = await fixture.createRollout(
      percentageBasisPoints: 10000,
      idempotencyKey: 'rollout-first',
    );
    await expectLater(
      fixture.transition(
        rolloutId: first.rollout.id,
        action: RolloutAction.ready,
        expectedRevision: 99,
        idempotencyKey: 'rollout-stale',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'PRECONDITION_FAILED',
        ),
      ),
    );
    await expectLater(
      fixture.createRollout(
        percentageBasisPoints: 10000,
        idempotencyKey: 'rollout-overlap',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'ROLLOUT_CONFLICT',
        ),
      ),
    );
  });

  test('moves an internal cohort to a percentage canary explicitly', () async {
    final internalInstallation = 'internal-installation';
    final created = await fixture.createRollout(
      percentageBasisPoints: 0,
      cohortKind: RolloutCohortKind.internal,
      internalInstallationHashes: <String>[
        RolloutEligibility.installationHash(internalInstallation),
      ],
      idempotencyKey: 'rollout-internal',
    );
    await fixture.transition(
      rolloutId: created.rollout.id,
      action: RolloutAction.ready,
      expectedRevision: 1,
      idempotencyKey: 'rollout-internal-ready',
    );
    final internal = await fixture.transition(
      rolloutId: created.rollout.id,
      action: RolloutAction.startInternal,
      expectedRevision: 2,
      idempotencyKey: 'rollout-internal-start',
    );
    expect(internal.revision.policy.cohortKind, RolloutCohortKind.internal);
    expect(
      (await fixture.updateCheck(installationId: internalInstallation))
          .decision,
      'PATCH_AVAILABLE',
    );
    final canary = await fixture.transition(
      rolloutId: created.rollout.id,
      action: RolloutAction.startCanary,
      expectedRevision: 3,
      percentageBasisPoints: 10000,
      idempotencyKey: 'rollout-internal-canary',
    );
    expect(canary.revision.policy.cohortKind, RolloutCohortKind.percentage);
    expect(canary.revision.policy.percentageBasisPoints, 10000);
    final audit = await fixture.service.readAudit(
      token: fixture.bootstrap.controlCredential.token,
      organizationId: fixture.bootstrap.organization.id,
    );
    expect(audit.map((record) => record.action), contains('rollout.expanded'));
  });

  test('enforces control scopes and tenant boundaries', () async {
    final created = await fixture.createRollout(
      percentageBasisPoints: 10000,
      idempotencyKey: 'rollout-auth',
    );
    await expectLater(
      fixture.service.readRollout(
        token: fixture.bootstrap.deliveryCredential.token,
        rolloutId: created.rollout.id,
        organizationId: fixture.bootstrap.organization.id,
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'FORBIDDEN',
        ),
      ),
    );
    await expectLater(
      fixture.service.transitionRollout(
        token: fixture.bootstrap.deliveryCredential.token,
        rolloutId: created.rollout.id,
        action: RolloutAction.ready,
        expectedRevision: 1,
        reason: 'delivery must not mutate',
        idempotencyKey: 'rollout-delivery-transition',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'FORBIDDEN',
        ),
      ),
    );

    final other = await fixture.service.bootstrap(
      organizationName: 'Other organization',
      runtimeApplicationId: 'com.example.other',
      platformId: 'android-arm64-release',
      environmentName: 'development',
    );
    await expectLater(
      fixture.service.readRollout(
        token: other.controlCredential.token,
        rolloutId: created.rollout.id,
        organizationId: other.organization.id,
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

  test('malformed persisted revisions fail closed', () async {
    final created = await fixture.createRollout(
      percentageBasisPoints: 10000,
      idempotencyKey: 'rollout-corrupt',
    );
    final store = FileControlPlaneStore(fixture.directory);
    final value = await store.readJson(
      'rollout_revisions',
      created.revision.id,
    );
    await store.replaceJson(
      'rollout_revisions',
      created.revision.id,
      <String, Object?>{...value!, 'unexpected': true},
    );
    await expectLater(
      fixture.service.readRollout(
        token: fixture.bootstrap.controlCredential.token,
        rolloutId: created.rollout.id,
        organizationId: fixture.bootstrap.organization.id,
      ),
      throwsFormatException,
    );
  });
}

final class _Fixture {
  _Fixture({
    required this.directory,
    required this.service,
    required this.bootstrap,
  });

  final Directory directory;
  final ControlPlaneService service;
  final BootstrapResult bootstrap;
  late final ReleaseRecord release;
  late final PatchRecord patch;
  late final ArtifactRecord artifact;

  static Future<_Fixture> create() async {
    final directory = await Directory.systemTemp.createTemp('hyfens-rollout-');
    final service = ControlPlaneService(
      store: FileControlPlaneStore(directory),
      random: Random(4),
    );
    final bootstrap = await service.bootstrap(
      organizationName: 'Rollout organization',
      runtimeApplicationId: 'com.example.rollout',
      platformId: 'android-arm64-release',
      environmentName: 'development',
    );
    final publicKey = await _publicKey();
    final release = await service.registerRelease(
      token: bootstrap.controlCredential.token,
      idempotencyKey: 'release',
      spec: ReleaseSpec(
        applicationId: bootstrap.application.id,
        platformId: 'plt_android',
        runtimeApplicationId: 'com.example.rollout',
        runtimeReleaseId: 'rollout-release-1',
        buildTarget: 'android-arm64-release',
        runtimeCompatibilityVersion: 1,
        patchFormatVersion: 1,
        buildFingerprint: _digest('rollout-build'),
        capabilityAuthorityDigest: _digest('rollout-capabilities'),
        functionSignatureDigest: _digest('rollout-functions'),
        displayVersion: '0.1.0',
        signingPublicKeys: <String, String>{
          _publicKeyId: base64.encode(publicKey),
        },
      ),
    );
    final patchBytes = await _patchBytes(
      releaseId: 'rollout-release-1',
      patchId: 'rollout-patch-1',
      sequence: 1,
    );
    final patch = await service.registerPatch(
      token: bootstrap.controlCredential.token,
      releaseId: release.id,
      idempotencyKey: 'patch',
      spec: PatchSpec(
        runtimePatchId: 'rollout-patch-1',
        sequence: 1,
        artifactId: 'art_rollout_patch',
        sha256: sha256Digest(patchBytes),
        sizeBytes: patchBytes.length,
        signatureKeyId: _publicKeyId,
      ),
    );
    final artifact = await service.uploadArtifact(
      token: bootstrap.controlCredential.token,
      artifactId: patch.artifactId,
      bytes: patchBytes,
      idempotencyKey: 'artifact',
    );
    await service.promote(
      token: bootstrap.controlCredential.token,
      environmentId: bootstrap.environment.id,
      releaseId: release.id,
      expectedVersion: 0,
      idempotencyKey: 'promote',
    );
    return _Fixture(
        directory: directory,
        service: service,
        bootstrap: bootstrap,
      )
      ..release = release
      ..patch = patch
      ..artifact = artifact;
  }

  Future<RolloutSnapshot> createRollout({
    required int percentageBasisPoints,
    required String idempotencyKey,
    RolloutCohortKind cohortKind = RolloutCohortKind.percentage,
    Iterable<String> internalInstallationHashes = const <String>[],
  }) => service.createRollout(
    token: bootstrap.controlCredential.token,
    spec: RolloutSpec(
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      platformId: release.platformId,
      releaseId: release.id,
      patchId: patch.id,
      percentageBasisPoints: percentageBasisPoints,
      cohortKind: cohortKind,
      internalInstallationHashes: internalInstallationHashes,
    ),
    idempotencyKey: idempotencyKey,
  );

  Future<RolloutSnapshot> transition({
    required String rolloutId,
    required RolloutAction action,
    required int expectedRevision,
    required String idempotencyKey,
    int? percentageBasisPoints,
  }) => service.transitionRollout(
    token: bootstrap.controlCredential.token,
    rolloutId: rolloutId,
    action: action,
    expectedRevision: expectedRevision,
    reason: 'test ${action.wireName}',
    idempotencyKey: idempotencyKey,
    percentageBasisPoints: percentageBasisPoints,
  );

  Future<UpdateCheckResult> updateCheck({String? installationId}) =>
      service.updateCheck(
        token: bootstrap.deliveryCredential.token,
        request: UpdateCheckRequest(
          applicationId: bootstrap.application.id,
          environmentId: bootstrap.environment.id,
          runtimeApplicationId: 'com.example.rollout',
          runtimeReleaseId: 'rollout-release-1',
          runtimeCompatibilityVersion: 1,
          patchFormatVersion: 1,
          highWaterSequence: 0,
          installationId: installationId,
        ),
      );

  Future<void> dispose() => directory.delete(recursive: true);
}

String _digest(String value) => 'sha256:${sha256.convert(utf8.encode(value))}';

Future<List<int>> _publicKey() async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(
    List<int>.filled(32, 9),
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
    List<int>.filled(32, 9),
  );
  try {
    final artifact = await PatchFormatV1.sealAsync(
      PatchArtifact(
        runtimeCompatibilityVersion: 1,
        applicationId: 'com.example.rollout',
        releaseId: releaseId,
        patchId: patchId,
        sequence: sequence,
        functions: <PatchFunctionEntry>[
          PatchFunctionEntry(
            id: 'lib:test#rollout',
            slot: 0,
            signatureDigest: _digest('rollout-signature'),
          ),
        ],
        capabilities: const <PatchCapabilityEntry>[],
        constants: const <PatchValue>[],
        instructions: const <int>[0],
        signatureMetadata: PatchSignatureMetadata(
          algorithm: 'ed25519',
          keyId: _publicKeyId,
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
