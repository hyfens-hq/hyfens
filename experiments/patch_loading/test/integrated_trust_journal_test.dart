import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

const _appId = 'dev.hyfens.integrated-trust';
const _releaseId = 'android-e1-integrated-trust-1';
const _buildFingerprint = 'integrated-trust-build-1';
const _signingKeyId = 'integrated-signing-a';
const _nextKeyId = 'integrated-signing-b';
const _replacementKeyId = 'integrated-signing-c';
const _recoveryKeyId = 'integrated-recovery';
const _signingSeed = <int>[
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
final _nextSeed = List<int>.unmodifiable(List<int>.filled(32, 2));
final _replacementSeed = List<int>.unmodifiable(List<int>.filled(32, 3));
final _recoverySeed = List<int>.unmodifiable(List<int>.filled(32, 4));
const _functionId =
    'sha256:d5a3b64831b9a76d7d43cc8645ce79415061f59039f12963a272c51a005fe361';
const _functions = <String, int>{_functionId: 0};
const _signatures = <String, String>{
  _functionId: '{"parameters":[{"kind":"int","nullable":false},{"kind":"int","nullable":false}],"return":{"kind":"int","nullable":false},"async":false}',
};
const _receivers = <String, String>{
  _functionId: '{"id":"none","ownerClass":null,"members":[]}',
};
const _delegatedRoles = <E1ReleaseKeyRole>{
  E1ReleaseKeyRole.authority,
  E1ReleaseKeyRole.patch,
  E1ReleaseKeyRole.rollback,
};

void main() {
  late Directory storage;
  late E1PatchController controller;
  late E1TrustedPublicKey signingKey;
  late E1TrustedPublicKey nextKey;
  late E1TrustedPublicKey replacementKey;
  late E1TrustedPublicKey recoveryKey;
  late E1KeyLifecycleState baseline;

  E1PatchController makeController({
    required E1KeyLifecycleState trust,
    E1PatchControllerTestHooks? testHooks,
    String releaseId = _releaseId,
  }) => E1PatchController(
    storageDirectory: storage,
    appId: _appId,
    releaseId: releaseId,
    buildFingerprint: _buildFingerprint,
    functions: _functions,
    signatures: _signatures,
    receivers: _receivers,
    patchUri: Uri.parse('http://127.0.0.1:18080/patch.e1.signed.json'),
    trustedPublicKeys: <String, E1TrustedPublicKey>{
      signingKey.keyId: signingKey,
    },
    initialTrustState: trust,
    log: (_) {},
    testHooks: testHooks,
  );

  setUp(() async {
    storage = await Directory.systemTemp.createTemp(
      'hyfens-e1-integrated-trust-',
    );
    signingKey = await _publicKey(_signingKeyId, _signingSeed);
    nextKey = await _publicKey(_nextKeyId, _nextSeed);
    replacementKey = await _publicKey(_replacementKeyId, _replacementSeed);
    recoveryKey = await _publicKey(_recoveryKeyId, _recoverySeed);
    baseline = _baseline(
      releaseId: _releaseId,
      signingKey: signingKey,
      recoveryKey: recoveryKey,
    );
    controller = makeController(trust: baseline);
    E0PatchRuntime.reset();
  });

  tearDown(() async {
    await controller.close();
    E0PatchRuntime.reset();
    await storage.delete(recursive: true);
  });

  test('one durable view covers rotation, retirement, revocation, rollback, cleanup, and replay', () async {
    await controller.initialize();

    final unknownKeyPatch = await _signedPatch(
      _discountPatch,
      1,
      keyId: nextKey.keyId,
      seed: _nextSeed,
    );
    expect(await controller.activateBytes(unknownKeyPatch), isFalse);
    expect(controller.status.detail, contains('not trusted'));
    expect(controller.durableState.trustGeneration, 0);
    expect(controller.durableState.highWaterSequence, 0);

    final addNext = await _lifecycleCommand(
      state: controller.trustState,
      operation: E1KeyLifecycleOperation.add,
      signerKeyId: signingKey.keyId,
      signerSeed: _signingSeed,
      newKeyId: nextKey.keyId,
      newPublicKey: nextKey.bytes,
      newRoles: _delegatedRoles,
    );
    expect(await controller.applyKeyLifecycleCommand(addNext), isTrue);
    expect(controller.trustGeneration, 1);
    expect(
      controller.trustState[nextKey.keyId]!.state,
      E1ReleaseKeyState.active,
    );

    final first = await _signedPatch(
      _discountPatch,
      1,
      keyId: signingKey.keyId,
      seed: _signingSeed,
    );
    expect(await _activateHealthy(controller, first), isTrue);

    final second = await _signedPatch(
      _alternatePatch,
      2,
      keyId: nextKey.keyId,
      seed: _nextSeed,
    );
    expect(await _activateHealthy(controller, second), isTrue);
    final secondDigest = sha256.convert(second).toString();
    final afterRotation = controller.durableState;
    expect(afterRotation.highWaterSequence, 2);
    expect(afterRotation.trustGeneration, 1);
    expect(afterRotation.lastKnownGood, isNotNull);
    expect(
      afterRotation.replayLedger.activeArtifactDigest,
      equals(
        afterRotation.replayLedger.artifacts.values
            .singleWhere((artifact) => artifact.keyId == nextKey.keyId)
            .digest,
      ),
    );

    final retireSigning = await _lifecycleCommand(
      state: controller.trustState,
      operation: E1KeyLifecycleOperation.retire,
      signerKeyId: signingKey.keyId,
      signerSeed: _signingSeed,
      targetKeyId: signingKey.keyId,
    );
    expect(await controller.applyKeyLifecycleCommand(retireSigning), isTrue);
    expect(controller.trustGeneration, 2);
    expect(
      controller.trustState[signingKey.keyId]!.state,
      E1ReleaseKeyState.retired,
    );
    expect(
      controller.durableState.current,
      'patch-$secondDigest.e1.signed.json',
    );
    expect(controller.durableState.lastKnownGood, isNotNull);

    final oldAfterRetirement = await _signedPatch(
      _discountPatch,
      3,
      keyId: signingKey.keyId,
      seed: _signingSeed,
    );
    expect(await controller.activateBytes(oldAfterRetirement), isFalse);
    expect(controller.status.detail, contains('not trusted'));

    final revokeSigning = await _lifecycleCommand(
      state: controller.trustState,
      operation: E1KeyLifecycleOperation.revoke,
      signerKeyId: nextKey.keyId,
      signerSeed: _nextSeed,
      targetKeyId: signingKey.keyId,
    );
    expect(await controller.applyKeyLifecycleCommand(revokeSigning), isTrue);
    final afterRevocation = controller.durableState;
    expect(afterRevocation.trustGeneration, 3);
    expect(
      afterRevocation.trustState[signingKey.keyId]!.state,
      E1ReleaseKeyState.revoked,
    );
    expect(afterRevocation.current, 'patch-$secondDigest.e1.signed.json');
    expect(afterRevocation.lastKnownGood, isNull);
    expect(afterRevocation.highWaterSequence, 2);

    final oldIdentity = afterRevocation.replayLedger.artifacts.values
        .singleWhere((artifact) => artifact.keyId == signingKey.keyId);
    final oldArtifact = File(
      '${storage.path}/patch-${oldIdentity.digest}.e1.signed.json',
    );
    expect(await oldArtifact.exists(), isTrue);
    await oldArtifact.delete();
    expect(await oldArtifact.exists(), isFalse);
    expect(
      controller.durableState.replayLedger.artifacts,
      containsPair(oldIdentity.digest, oldIdentity),
    );

    final rollback = await _rollbackControl(
      state: controller.durableState,
      keyId: nextKey.keyId,
      seed: _nextSeed,
    );
    expect(await controller.applyRollbackControl(rollback), isTrue);
    final afterRollback = controller.durableState;
    expect(afterRollback.current, isNull);
    expect(afterRollback.health, 'base');
    expect(afterRollback.replayLedger.activeArtifactDigest, isNull);
    expect(afterRollback.highWaterSequence, 2);
    expect(afterRollback.highWaterDigest, isNotNull);
    expect(afterRollback.trustGeneration, 3);

    expect(await controller.activateBytes(second), isFalse);
    expect(controller.status.detail, contains('replayAfterRollback'));
    expect(await controller.activateBytes(oldAfterRetirement), isFalse);
    expect(controller.status.detail, contains('not trusted'));
  });

  test(
    'recovery replacement revokes current code and preserves high-water',
    () async {
      await controller.initialize();
      final first = await _signedPatch(
        _discountPatch,
        1,
        keyId: signingKey.keyId,
        seed: _signingSeed,
      );
      expect(await _activateHealthy(controller, first), isTrue);

      final recover = await _lifecycleCommand(
        state: controller.trustState,
        operation: E1KeyLifecycleOperation.recover,
        signerKeyId: recoveryKey.keyId,
        signerSeed: _recoverySeed,
        targetKeyId: signingKey.keyId,
        newKeyId: replacementKey.keyId,
        newPublicKey: replacementKey.bytes,
        newRoles: _delegatedRoles,
      );
      expect(await controller.applyKeyLifecycleCommand(recover), isTrue);

      final recoveredView = controller.durableState;
      expect(recoveredView.current, isNull);
      expect(recoveredView.health, 'base');
      expect(recoveredView.highWaterSequence, 1);
      expect(recoveredView.replayLedger.activeArtifactDigest, isNull);
      expect(recoveredView.trustGeneration, 1);
      expect(
        recoveredView.trustState[signingKey.keyId]!.state,
        E1ReleaseKeyState.revoked,
      );
      expect(
        recoveredView.trustState[replacementKey.keyId]!.state,
        E1ReleaseKeyState.active,
      );
      expect(E0PatchRuntime.lookup(0), isNull);

      final replacement = await _signedPatch(
        _alternatePatch,
        2,
        keyId: replacementKey.keyId,
        seed: _replacementSeed,
      );
      expect(await _activateHealthy(controller, replacement), isTrue);
      expect(controller.durableState.highWaterSequence, 2);
      expect(
        controller.durableState.replayLedger.activeArtifactDigest,
        equals(
          controller.durableState.replayLedger.artifacts.values
              .singleWhere((artifact) => artifact.keyId == replacementKey.keyId)
              .digest,
        ),
      );

      final oldIdentity = controller.durableState.replayLedger.artifacts.values
          .singleWhere((artifact) => artifact.keyId == signingKey.keyId);
      await File('${storage.path}/patch-${oldIdentity.digest}.e1.signed.json')
          .delete();
      expect(await controller.activateBytes(first), isFalse);
      expect(controller.status.detail, contains('not trusted'));
    },
  );

  test(
    'trust transition faults are atomic before rename and recover after rename',
    () async {
      await controller.initialize();
      final first = await _signedPatch(
        _discountPatch,
        1,
        keyId: signingKey.keyId,
        seed: _signingSeed,
      );
      expect(await _activateHealthy(controller, first), isTrue);
      final command = await _lifecycleCommand(
        state: controller.trustState,
        operation: E1KeyLifecycleOperation.add,
        signerKeyId: signingKey.keyId,
        signerSeed: _signingSeed,
        newKeyId: nextKey.keyId,
        newPublicKey: nextKey.bytes,
        newRoles: _delegatedRoles,
      );
      final primaryBefore = await File('${storage.path}/state-v3-a.json')
          .readAsString();
      final backupBefore = await File('${storage.path}/state-v3-b.json')
          .readAsString();

      await controller.close();
      var beforeRenameInjected = false;
      controller = makeController(
        trust: baseline,
        testHooks: E1PatchControllerTestHooks(
          durableBoundary: (boundary, name, _) async {
            if (!beforeRenameInjected &&
                name == 'state-v3-b.json' &&
                boundary == E1DurableBoundary.beforeStateCopyRename) {
              beforeRenameInjected = true;
              throw StateError('injected trust pre-rename fault');
            }
          },
        ),
      );
      await controller.initialize();
      expect(await controller.applyKeyLifecycleCommand(command), isFalse);
      expect(beforeRenameInjected, isTrue);
      expect(controller.trustGeneration, 0);
      expect(controller.durableState.highWaterSequence, 1);
      expect(
        await File('${storage.path}/state-v3-a.json').readAsString(),
        primaryBefore,
      );
      expect(
        await File('${storage.path}/state-v3-b.json').readAsString(),
        backupBefore,
      );

      await controller.close();
      var afterRenameInjected = false;
      controller = makeController(
        trust: baseline,
        testHooks: E1PatchControllerTestHooks(
          durableBoundary: (boundary, name, _) async {
            if (!afterRenameInjected &&
                name == 'state-v3-b.json' &&
                boundary == E1DurableBoundary.afterStateCopyRename) {
              afterRenameInjected = true;
              throw StateError('injected trust post-rename fault');
            }
          },
        ),
      );
      await controller.initialize();
      expect(await controller.applyKeyLifecycleCommand(command), isTrue);
      expect(afterRenameInjected, isTrue);
      expect(controller.trustGeneration, 1);
      expect(
        controller.trustState[nextKey.keyId]!.state,
        E1ReleaseKeyState.active,
      );

      await controller.close();
      controller = makeController(trust: baseline);
      await controller.initialize();
      expect(controller.trustGeneration, 1);
      expect(
        controller.trustState[nextKey.keyId]!.state,
        E1ReleaseKeyState.active,
      );
      expect(
        await File('${storage.path}/state-v3-a.json').readAsString(),
        await File('${storage.path}/state-v3-b.json').readAsString(),
      );
    },
  );

  test('wrong release and dual-copy trust corruption fail closed', () async {
    await controller.initialize();
    final addNext = await _lifecycleCommand(
      state: controller.trustState,
      operation: E1KeyLifecycleOperation.add,
      signerKeyId: signingKey.keyId,
      signerSeed: _signingSeed,
      newKeyId: nextKey.keyId,
      newPublicKey: nextKey.bytes,
      newRoles: _delegatedRoles,
    );
    expect(await controller.applyKeyLifecycleCommand(addNext), isTrue);
    final first = await _signedPatch(
      _discountPatch,
      1,
      keyId: signingKey.keyId,
      seed: _signingSeed,
    );
    expect(await _activateHealthy(controller, first), isTrue);
    await controller.close();

    final primary = await _stateFile(storage, 'state-v3-a.json');
    final corruptTrust = Map<String, Object?>.of(
      primary['trust']! as Map<String, Object?>,
    )..['stateDigest'] = '0' * 64;
    final corrupted = Map<String, Object?>.of(primary)
      ..['trust'] = corruptTrust;
    await _writeStateFile(storage, 'state-v3-a.json', corrupted);
    await _writeStateFile(storage, 'state-v3-b.json', corrupted);

    controller = makeController(trust: baseline);
    await controller.initialize();
    expect(controller.recoveryNeeded, isTrue);
    expect(controller.lifecycleState, E1LifecycleState.failed);
    expect(controller.status.phase, 'recoveryNeeded');
    expect(E0PatchRuntime.lookup(0), isNull);
    expect(await controller.activateBytes(first), isFalse);

    await controller.close();
    final wrongRelease = 'android-e1-wrong-release';
    controller = makeController(
      releaseId: wrongRelease,
      trust: _baseline(
        releaseId: wrongRelease,
        signingKey: signingKey,
        recoveryKey: recoveryKey,
      ),
    );
    await controller.initialize();
    expect(controller.recoveryNeeded, isTrue);
    expect(controller.status.phase, 'recoveryNeeded');
    expect(E0PatchRuntime.lookup(0), isNull);
  });
}

Future<E1TrustedPublicKey> _publicKey(String keyId, List<int> seed) async {
  final pair = await DartEd25519().newKeyPairFromSeed(seed);
  try {
    return E1TrustedPublicKey(
      keyId: keyId,
      bytes: (await pair.extractPublicKey()).bytes,
    );
  } finally {
    pair.destroy();
  }
}

E1KeyLifecycleState _baseline({
  required String releaseId,
  required E1TrustedPublicKey signingKey,
  required E1TrustedPublicKey recoveryKey,
}) => E1KeyLifecycleState.initial(
  applicationId: _appId,
  releaseId: releaseId,
  keys: <E1ReleaseKey>[
    E1ReleaseKey(
      keyId: signingKey.keyId,
      publicKeyBytes: signingKey.bytes,
      roles: _delegatedRoles,
    ),
    E1ReleaseKey(
      keyId: recoveryKey.keyId,
      publicKeyBytes: recoveryKey.bytes,
      roles: const <E1ReleaseKeyRole>{E1ReleaseKeyRole.recovery},
    ),
  ],
);

Future<List<int>> _lifecycleCommand({
  required E1KeyLifecycleState state,
  required E1KeyLifecycleOperation operation,
  required String signerKeyId,
  required List<int> signerSeed,
  String? targetKeyId,
  String? newKeyId,
  List<int>? newPublicKey,
  Set<E1ReleaseKeyRole>? newRoles,
}) async {
  final pair = await DartEd25519().newKeyPairFromSeed(signerSeed);
  try {
    final command = await E1KeyLifecycleCommand.sign(
      applicationId: state.applicationId,
      releaseId: state.releaseId,
      commandSequence: state.commandSequence + 1,
      previousStateDigest: state.stateDigest,
      operation: operation,
      signerKeyId: signerKeyId,
      targetKeyId: targetKeyId,
      newKeyId: newKeyId,
      newPublicKey: newPublicKey,
      newRoles: newRoles,
      signer: (message) async =>
          (await DartEd25519().sign(message, keyPair: pair)).bytes,
    );
    return command.encodeBytes();
  } finally {
    pair.destroy();
  }
}

Future<List<int>> _signedPatch(
  String source,
  int sequence, {
  required String keyId,
  required List<int> seed,
  String releaseId = _releaseId,
}) => E1SignedPatchEnvelope.sign(
  patchBytes: _compile(source, sequence, releaseId: releaseId),
  keyId: keyId,
  privateKeySeed: seed,
);

Future<List<int>> _rollbackControl({
  required E1ControllerDurableState state,
  required String keyId,
  required List<int> seed,
}) async {
  final pair = await DartEd25519().newKeyPairFromSeed(seed);
  try {
    final command = await RollbackControlCommand.sign(
      applicationId: state.appId,
      releaseId: state.releaseId,
      highWaterSequence: state.highWaterSequence,
      highWaterDigest: state.highWaterDigest,
      keyId: keyId,
      signer: (message) async =>
          (await DartEd25519().sign(message, keyPair: pair)).bytes,
    );
    return command.encodeBytes();
  } finally {
    pair.destroy();
  }
}

Future<bool> _activateHealthy(
  E1PatchController controller,
  List<int> bytes,
) async {
  if (!await controller.activateBytes(bytes)) return false;
  return controller.markHealthy();
}

Future<Map<String, Object?>> _stateFile(Directory storage, String name) async =>
    jsonDecode(await File('${storage.path}/$name').readAsString())
        as Map<String, Object?>;

Future<void> _writeStateFile(
  Directory storage,
  String name,
  Map<String, Object?> input,
) async {
  final body = Map<String, Object?>.of(input)..remove('checksum');
  final checksum = sha256.convert(utf8.encode(jsonEncode(body))).toString();
  final value = <String, Object?>{...body, 'checksum': checksum};
  final encoded = jsonEncode(<String, Object?>{
    for (final key in value.keys.toList()..sort()) key: value[key],
  });
  await File('${storage.path}/$name').writeAsString(encoded);
}

List<int> _compile(
  String source,
  int sequence, {
  String releaseId = _releaseId,
}) {
  final identity = E0Identity().declaration(
    canonicalLibraryUri: 'package:integrated/main.dart',
    declarationName: 'calculatePrice',
  );
  final manifest = E0ReleaseManifest(
    appId: _appId,
    releaseId: releaseId,
    buildFingerprint: _buildFingerprint,
    canonicalLibraryUri: 'package:integrated/main.dart',
    logicalLibraryPath: 'lib/main.dart',
    functions: <E0FunctionManifest>[
      E0FunctionManifest(
        name: 'calculatePrice',
        identity: identity,
        id: _functionId,
        slot: 0,
        signature: E0FunctionSignature.legacyInt2,
        receiver: E0ReceiverDescriptor.none,
      ),
    ],
  );
  return E0PatchCompiler().compile(
    source: source,
    manifest: manifest,
    functionName: 'calculatePrice',
    patchSequence: sequence,
  );
}

const _discountPatch = '''
int calculatePrice(int quantity, int tier) {
  if (quantity < 1) return 0;
  if (tier == 2) return quantity * 70;
  if (quantity < 3) return quantity * 95;
  return quantity * 75;
}
''';

const _alternatePatch = '''
int calculatePrice(int quantity, int tier) {
  if (quantity < 1) return 0;
  if (tier == 2) return quantity * 65;
  if (quantity < 3) return quantity * 80;
  return quantity * 60;
}
''';
