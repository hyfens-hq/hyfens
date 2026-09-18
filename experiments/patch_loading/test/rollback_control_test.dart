import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
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

void main() {
  test('signing and decoding are deterministic and canonical', () async {
    final first = await _signed();
    final second = await _signed();

    expect(first.encode(), second.encode());
    expect(first.encodeBytes(), utf8.encode(first.encode()));
    expect(await first.verify((await _publicKey()).bytes), isTrue);
    expect(
      RollbackControlCommand.decode(first.encodeBytes()).encode(),
      first.encode(),
    );
  });

  test('wrong public key and tampered command are rejected', () async {
    final command = await _signed();
    final otherPair = await DartEd25519().newKeyPairFromSeed(
      List<int>.filled(32, 1),
    );
    final otherPublic = await otherPair.extractPublicKey();
    otherPair.destroy();
    expect(await command.verify(otherPublic.bytes), isFalse);

    final tampered = command.encodeBytes()..[20] ^= 1;
    expect(
      () => RollbackControlCommand.decode(tampered),
      throwsA(isA<FormatException>()),
    );
  });

  test('high-water zero requires a null digest', () async {
    expect(
      () => RollbackControlCommand.decode(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'algorithm': 'Ed25519',
            'applicationId': 'dev.hyfens.app',
            'command': 'rollback-base',
            'commandVersion': 1,
            'highWaterDigest': '0' * 64,
            'highWaterSequence': 0,
            'keyId': 'release-key',
            'signature': base64.encode(List<int>.filled(64, 0)),
          }),
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('unknown fields and oversized commands are rejected', () async {
    final command = await _signed();
    final decoded = jsonDecode(command.encode()) as Map<String, Object?>;
    decoded['unknown'] = true;
    expect(
      () => RollbackControlCommand.decode(utf8.encode(jsonEncode(decoded))),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => RollbackControlCommand.decode(
        List<int>.filled(RollbackControlCommand.maxBytes + 1, 0),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

Future<RollbackControlCommand> _signed() => RollbackControlCommand.sign(
  applicationId: 'dev.hyfens.app',
  releaseId: 'android-arm64-release',
  highWaterSequence: 3,
  highWaterDigest: 'a' * 64,
  keyId: 'release-key',
  signer: (message) async {
    final pair = await DartEd25519().newKeyPairFromSeed(_seed);
    try {
      return (await DartEd25519().sign(message, keyPair: pair)).bytes;
    } finally {
      pair.destroy();
    }
  },
);

Future<SimplePublicKey> _publicKey() async {
  final pair = await DartEd25519().newKeyPairFromSeed(_seed);
  try {
    return await pair.extractPublicKey();
  } finally {
    pair.destroy();
  }
}
