import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

const _seedHex =
    '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
const _publicHex =
    'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
const _emptySignatureHex =
    'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
    '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b';

void main() {
  test('Ed25519 matches RFC 8032 test vector 1', () async {
    final algorithm = DartEd25519();
    final keyPair = await algorithm.newKeyPairFromSeed(_unhex(_seedHex));
    final publicKey = await keyPair.extractPublicKey();
    final signature = await algorithm.sign(const <int>[], keyPair: keyPair);
    expect(_hex(publicKey.bytes), _publicHex);
    expect(_hex(signature.bytes), _emptySignatureHex);
    expect(await algorithm.verify(const <int>[], signature: signature), isTrue);
    keyPair.destroy();
  });

  test(
    'envelope signing is deterministic and verifies exact patch bytes',
    () async {
      final patch = utf8.encode('{"canonical":"patch"}');
      final first = await E1SignedPatchEnvelope.sign(
        patchBytes: patch,
        keyId: 'test-key',
        privateKeySeed: _unhex(_seedHex),
      );
      final second = await E1SignedPatchEnvelope.sign(
        patchBytes: patch,
        keyId: 'test-key',
        privateKeySeed: _unhex(_seedHex),
      );
      expect(first, second);
      final verified = await E1SignedPatchEnvelope.verify(
        envelopeBytes: first,
        trustedKeys: <String, E1TrustedPublicKey>{
          'test-key': E1TrustedPublicKey(
            keyId: 'test-key',
            bytes: _unhex(_publicHex),
          ),
        },
      );
      expect(verified.patchBytes, patch);
    },
  );

  test(
    'offline keygen/sign CLI roundtrip verifies',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final directory = await Directory.systemTemp.createTemp('hyfens-e1-cli-');
      addTearDown(() => directory.delete(recursive: true));
      final seed = File('${directory.path}/seed.hex');
      final publicKey = File('${directory.path}/public.hex');
      final patch = File('${directory.path}/patch.json')
        ..writeAsStringSync('{"exact":"bytes"}');
      final output = File('${directory.path}/patch.signed.json');

      final keygen = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'bin/e1.dart',
        'keygen',
        seed.path,
        publicKey.path,
      ], workingDirectory: Directory.current.path);
      expect(keygen.exitCode, 0, reason: '${keygen.stdout}\n${keygen.stderr}');
      if (!Platform.isWindows) {
        expect((await seed.stat()).mode & 0x1ff, 0x180);
      }
      expect(
        directory.listSync().whereType<Directory>().where(
          (item) => item.uri.pathSegments.any(
            (segment) => segment.startsWith('.e1-keygen-'),
          ),
        ),
        isEmpty,
      );
      final sign = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'bin/e1.dart',
        'sign',
        patch.path,
        seed.path,
        'cli-key',
        output.path,
      ], workingDirectory: Directory.current.path);
      expect(sign.exitCode, 0, reason: '${sign.stdout}\n${sign.stderr}');

      final verified = await E1SignedPatchEnvelope.verify(
        envelopeBytes: output.readAsBytesSync(),
        trustedKeys: <String, E1TrustedPublicKey>{
          'cli-key': E1TrustedPublicKey(
            keyId: 'cli-key',
            bytes: _unhex(publicKey.readAsStringSync().trim()),
          ),
        },
      );
      expect(verified.patchBytes, patch.readAsBytesSync());
      expect(File('${output.path}.tmp').existsSync(), isFalse);
    },
  );

  test(
    'CLI rejects aliasing, overwrite, and oversized input safely',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hyfens-e1-cli-bounds-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final same = File('${directory.path}/same.hex');
      final keyAlias = await _runCli(<String>['keygen', same.path, same.path]);
      expect(keyAlias.exitCode, 64);
      expect(same.existsSync(), isFalse);

      final seed = File('${directory.path}/seed.hex')
        ..writeAsStringSync('$_seedHex\n');
      final patch = File('${directory.path}/patch.json')
        ..writeAsStringSync('{"exact":"bytes"}');
      final alias = await _runCli(<String>[
        'sign',
        patch.path,
        seed.path,
        'cli-key',
        seed.path,
      ]);
      expect(alias.exitCode, 64);
      expect(seed.readAsStringSync().trim(), _seedHex);

      final output = File('${directory.path}/existing.signed.json')
        ..writeAsStringSync('preserve');
      final overwrite = await _runCli(<String>[
        'sign',
        patch.path,
        seed.path,
        'cli-key',
        output.path,
      ]);
      expect(overwrite.exitCode, 73);
      expect(output.readAsStringSync(), 'preserve');

      final oversized = File('${directory.path}/oversized.json')
        ..writeAsBytesSync(List<int>.filled(64 * 1024 + 1, 0));
      final oversizedOutput = File('${directory.path}/oversized.signed.json');
      final bounded = await _runCli(<String>[
        'sign',
        oversized.path,
        seed.path,
        'cli-key',
        oversizedOutput.path,
      ]);
      expect(bounded.exitCode, 65);
      expect(oversizedOutput.existsSync(), isFalse);
      expect(File('${oversizedOutput.path}.tmp').existsSync(), isFalse);
    },
  );
}

Future<ProcessResult> _runCli(List<String> arguments) => Process.run(
  Platform.resolvedExecutable,
  <String>['run', 'bin/e1.dart', ...arguments],
  workingDirectory: Directory.current.path,
);

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String value) => <int>[
  for (var offset = 0; offset < value.length; offset += 2)
    int.parse(value.substring(offset, offset + 2), radix: 16),
];
