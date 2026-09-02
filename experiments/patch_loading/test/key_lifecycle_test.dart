import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

const _authoritySeed = <int>[
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
const _oldPatchSeed = <int>[
  0x11,
  0x22,
  0x33,
  0x44,
  0x55,
  0x66,
  0x77,
  0x88,
  0x99,
  0xaa,
  0xbb,
  0xcc,
  0xdd,
  0xee,
  0xff,
  0x10,
  0x21,
  0x32,
  0x43,
  0x54,
  0x65,
  0x76,
  0x87,
  0x98,
  0xa9,
  0xba,
  0xcb,
  0xdc,
  0xed,
  0xfe,
  0x0f,
  0x01,
];
final _newPatchSeed = List<int>.filled(32, 0x42);
final _replacementAuthoritySeed = List<int>.filled(32, 0x53);
final _recoverySeed = List<int>.filled(32, 0x64);

void main() {
  group('release-owned key lifecycle', () {
    test('state and signed commands round-trip canonically', () async {
      final state = await _initialState();
      final command = await _addCommand(state);
      final decodedCommand = E1KeyLifecycleCommand.decode(
        command.encodeBytes(),
      );
      expect(decodedCommand.encode(), command.encode());

      final next = await state.apply(command.encodeBytes());
      expect(next.commandSequence, 1);
      expect(next['new-patch']?.state, E1ReleaseKeyState.active);
      final restored = E1KeyLifecycleState.decode(next.encodeBytes());
      expect(restored.stateDigest, next.stateDigest);
      expect(restored.keys.keys, containsAll(next.keys.keys));
    });

    test('rotation overlaps, then retirement stops new artifacts', () async {
      var state = await _initialState();
      state = await state.apply((await _addCommand(state)).encodeBytes());

      final retire = await _command(
        state: state,
        operation: E1KeyLifecycleOperation.retire,
        signerKeyId: 'authority',
        signerSeed: _authoritySeed,
        targetKeyId: 'old-patch',
      );
      state = await state.apply(retire.encodeBytes());

      expect(state['old-patch']?.state, E1ReleaseKeyState.retired);
      expect(state.activeArtifactTrust.containsKey('old-patch'), isFalse);
      expect(state.retainedArtifactTrust.containsKey('old-patch'), isTrue);
      expect(state.activeArtifactTrust.containsKey('new-patch'), isTrue);
    });

    test(
      'recovery replaces a compromised authority without delegating recovery',
      () async {
        final state = await _initialState();
        final command = await _command(
          state: state,
          operation: E1KeyLifecycleOperation.recover,
          signerKeyId: 'recovery',
          signerSeed: _recoverySeed,
          targetKeyId: 'authority',
          newKeyId: 'authority-recovered',
          newPublicKey: _publicKey(_replacementAuthoritySeed),
          newRoles: const {
            E1ReleaseKeyRole.authority,
            E1ReleaseKeyRole.patch,
            E1ReleaseKeyRole.rollback,
          },
        );
        final recovered = await state.apply(command.encodeBytes());

        expect(recovered['authority']?.state, E1ReleaseKeyState.revoked);
        expect(
          recovered['authority-recovered']?.state,
          E1ReleaseKeyState.active,
        );
        expect(recovered['authority-recovered']?.roles, const {
          E1ReleaseKeyRole.authority,
          E1ReleaseKeyRole.patch,
          E1ReleaseKeyRole.rollback,
        });
        expect(recovered['recovery']?.isRecoveryAnchor, isTrue);
      },
    );

    test('unknown signer cannot self-authorize a downloaded key', () async {
      final state = await _initialState();
      final command = await _command(
        state: state,
        operation: E1KeyLifecycleOperation.add,
        signerKeyId: 'future-key',
        signerSeed: _newPatchSeed,
        newKeyId: 'attacker-key',
        newPublicKey: _publicKey(_newPatchSeed),
        newRoles: const {E1ReleaseKeyRole.patch},
      );

      await expectLater(
        state.apply(command.encodeBytes()),
        throwsA(isA<FormatException>()),
      );
      expect(state['attacker-key'], isNull);
    });

    test('patch-only signer cannot rotate lifecycle authority', () async {
      final state = await _initialState();
      final command = await _command(
        state: state,
        operation: E1KeyLifecycleOperation.add,
        signerKeyId: 'old-patch',
        signerSeed: _oldPatchSeed,
        newKeyId: 'forged-authority',
        newPublicKey: _publicKey(_newPatchSeed),
        newRoles: const {E1ReleaseKeyRole.authority},
      );

      await expectLater(
        state.apply(command.encodeBytes()),
        throwsA(isA<FormatException>()),
      );
    });

    test('replay, gaps, and state equivocation fail closed', () async {
      final state = await _initialState();
      final command = await _addCommand(state);
      final next = await state.apply(command.encodeBytes());

      await expectLater(
        next.apply(command.encodeBytes()),
        throwsA(isA<FormatException>()),
      );
      final gap = await _command(
        state: state,
        operation: E1KeyLifecycleOperation.retire,
        signerKeyId: 'authority',
        signerSeed: _authoritySeed,
        targetKeyId: 'old-patch',
      );
      final gapJson = jsonDecode(gap.encode()) as Map<String, Object?>;
      gapJson['commandSequence'] = 3;
      final forgedGap = utf8.encode(jsonEncode(gapJson));
      await expectLater(
        state.apply(forgedGap),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('cross-feature artifact anti-replay', () {
    test('valid signed envelope is retained after rotation but cannot replay as new', () async {
      var state = await _initialState();
      final envelope = await E1SignedPatchEnvelope.sign(
        patchBytes: utf8.encode('{"patch":"old"}'),
        keyId: 'old-patch',
        privateKeySeed: _oldPatchSeed,
      );
      final verified = await E1SignedPatchEnvelope.verify(
        envelopeBytes: envelope,
        trustedKeys: <String, E1TrustedPublicKey>{
          'old-patch': await _trustedKey('old-patch', _oldPatchSeed),
        },
      );
      final oldArtifact = E1VerifiedArtifactIdentity.fromBytes(
        keyId: verified.keyId,
        sequence: 1,
        envelopeBytes: verified.envelopeBytes,
      );
      var ledger = E1ArtifactReplayLedger.empty(releaseId: state.releaseId);
      var admission = ledger.admitNewArtifact(
        lifecycle: state,
        artifact: oldArtifact,
      );
      expect(admission.status, E1ArtifactAdmissionStatus.accepted);
      ledger = admission.ledger;

      state = await state.apply((await _addCommand(state)).encodeBytes());
      final retire = await _command(
        state: state,
        operation: E1KeyLifecycleOperation.retire,
        signerKeyId: 'authority',
        signerSeed: _authoritySeed,
        targetKeyId: 'old-patch',
      );
      state = await state.apply(retire.encodeBytes());

      admission = ledger.admitNewArtifact(
        lifecycle: state,
        artifact: oldArtifact,
      );
      expect(
        admission.status,
        E1ArtifactAdmissionStatus.keyRetiredForNewArtifact,
      );
      expect(
        ledger
            .verifyRetainedArtifact(lifecycle: state, artifact: oldArtifact)
            .status,
        E1ArtifactAdmissionStatus.retained,
      );

      final newEnvelope = await E1SignedPatchEnvelope.sign(
        patchBytes: utf8.encode('{"patch":"new"}'),
        keyId: 'new-patch',
        privateKeySeed: _newPatchSeed,
      );
      final newVerified = await E1SignedPatchEnvelope.verify(
        envelopeBytes: newEnvelope,
        trustedKeys: <String, E1TrustedPublicKey>{
          'new-patch': await _trustedKey('new-patch', _newPatchSeed),
        },
      );
      final newArtifact = E1VerifiedArtifactIdentity.fromBytes(
        keyId: newVerified.keyId,
        sequence: 2,
        envelopeBytes: newVerified.envelopeBytes,
      );
      admission = ledger.admitNewArtifact(
        lifecycle: state,
        artifact: newArtifact,
      );
      expect(admission.status, E1ArtifactAdmissionStatus.accepted);
      ledger = admission.ledger;
      expect(
        ledger.admitNewArtifact(lifecycle: state, artifact: newArtifact).status,
        E1ArtifactAdmissionStatus.idempotent,
      );

      final alternate = E1VerifiedArtifactIdentity.fromBytes(
        keyId: 'new-patch',
        sequence: 2,
        envelopeBytes: utf8.encode('different-envelope'),
      );
      expect(
        ledger.admitNewArtifact(lifecycle: state, artifact: alternate).status,
        E1ArtifactAdmissionStatus.equivocation,
      );
      final staleArtifact = E1VerifiedArtifactIdentity(
        keyId: 'new-patch',
        sequence: 1,
        digest: 'b' * 64,
      );
      expect(
        ledger
            .admitNewArtifact(lifecycle: state, artifact: staleArtifact)
            .status,
        E1ArtifactAdmissionStatus.stale,
      );

      final rolledBack = ledger.rollbackToBase();
      expect(
        rolledBack
            .admitNewArtifact(lifecycle: state, artifact: newArtifact)
            .status,
        E1ArtifactAdmissionStatus.replayAfterRollback,
      );

      final revoked = await state.apply(
        (await _command(
          state: state,
          operation: E1KeyLifecycleOperation.revoke,
          signerKeyId: 'authority',
          signerSeed: _authoritySeed,
          targetKeyId: 'old-patch',
        )).encodeBytes(),
      );
      expect(
        ledger
            .verifyRetainedArtifact(lifecycle: revoked, artifact: oldArtifact)
            .status,
        E1ArtifactAdmissionStatus.keyRevoked,
      );
    });
  });
}

Future<E1KeyLifecycleState> _initialState() async =>
    E1KeyLifecycleState.initial(
      applicationId: 'dev.hyfens.app',
      releaseId: 'android-arm64-release',
      keys: <E1ReleaseKey>[
        await _releaseKey('authority', _authoritySeed, const {
          E1ReleaseKeyRole.authority,
          E1ReleaseKeyRole.patch,
          E1ReleaseKeyRole.rollback,
        }),
        await _releaseKey('old-patch', _oldPatchSeed, const {
          E1ReleaseKeyRole.patch,
          E1ReleaseKeyRole.rollback,
        }),
        await _releaseKey('recovery', _recoverySeed, const {
          E1ReleaseKeyRole.recovery,
        }),
      ],
    );

Future<E1KeyLifecycleCommand> _addCommand(E1KeyLifecycleState state) =>
    _command(
      state: state,
      operation: E1KeyLifecycleOperation.add,
      signerKeyId: 'authority',
      signerSeed: _authoritySeed,
      newKeyId: 'new-patch',
      newPublicKey: _publicKey(_newPatchSeed),
      newRoles: const {E1ReleaseKeyRole.patch, E1ReleaseKeyRole.rollback},
    );

Future<E1KeyLifecycleCommand> _command({
  required E1KeyLifecycleState state,
  required E1KeyLifecycleOperation operation,
  required String signerKeyId,
  required List<int> signerSeed,
  String? targetKeyId,
  String? newKeyId,
  Future<List<int>>? newPublicKey,
  Set<E1ReleaseKeyRole>? newRoles,
}) async => E1KeyLifecycleCommand.sign(
  applicationId: state.applicationId,
  releaseId: state.releaseId,
  commandSequence: state.commandSequence + 1,
  previousStateDigest: state.stateDigest,
  operation: operation,
  signerKeyId: signerKeyId,
  targetKeyId: targetKeyId,
  newKeyId: newKeyId,
  newPublicKey: await newPublicKey,
  newRoles: newRoles,
  signer: (message) => _sign(signerSeed, message),
);

Future<E1ReleaseKey> _releaseKey(
  String keyId,
  List<int> seed,
  Set<E1ReleaseKeyRole> roles,
) async => E1ReleaseKey(
  keyId: keyId,
  publicKeyBytes: await _publicKey(seed),
  roles: roles,
);

Future<E1TrustedPublicKey> _trustedKey(String keyId, List<int> seed) async =>
    E1TrustedPublicKey(keyId: keyId, bytes: await _publicKey(seed));

Future<List<int>> _publicKey(List<int> seed) async {
  final pair = await DartEd25519().newKeyPairFromSeed(seed);
  try {
    return (await pair.extractPublicKey()).bytes;
  } finally {
    pair.destroy();
  }
}

Future<List<int>> _sign(List<int> seed, List<int> message) async {
  final pair = await DartEd25519().newKeyPairFromSeed(seed);
  try {
    return (await DartEd25519().sign(message, keyPair: pair)).bytes;
  } finally {
    pair.destroy();
  }
}
