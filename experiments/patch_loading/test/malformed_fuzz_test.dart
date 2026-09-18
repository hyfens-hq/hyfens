import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

const _lifecycleFuzzSeed = 0x1c_18_24_47;
const _lifecycleFuzzCases = 48;
const _appId = 'fuzz-app';
const _releaseId = 'fuzz-release';
const _buildFingerprint = 'fuzz-build';
const _keyId = 'fuzz-key';
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
  late Directory storage;
  late E1PatchController controller;
  late E0ReleaseManifest manifest;
  late List<int> patch;
  late E1TrustedPublicKey trustedKey;

  setUp(() async {
    E0PatchRuntime.reset();
    storage = await Directory.systemTemp.createTemp('hyfens-fuzz-lifecycle-');
    final keyPair = await DartEd25519().newKeyPairFromSeed(_seed);
    trustedKey = E1TrustedPublicKey(
      keyId: _keyId,
      bytes: (await keyPair.extractPublicKey()).bytes,
    );
    keyPair.destroy();

    manifest = E0SourceTransformer()
        .transform(
          source:
              'int target(int left, int right) { return left + right; }\n'
              'void main(List<String> arguments) {}',
          packageName: 'fuzz_fixture',
          logicalLibraryPath: 'lib/target.dart',
          appId: _appId,
          releaseId: _releaseId,
          buildFingerprint: _buildFingerprint,
        )
        .manifest;
    patch = E0PatchCompiler().compile(
      source: 'int target(int left, int right) { return left + right; }',
      manifest: manifest,
      functionName: 'target',
      patchSequence: 1,
    );
    final function = manifest.functions.single;
    controller = E1PatchController(
      storageDirectory: storage,
      appId: _appId,
      releaseId: _releaseId,
      buildFingerprint: _buildFingerprint,
      functions: <String, int>{function.id: function.slot},
      signatures: <String, String>{function.id: function.signature.encode()},
      receivers: <String, String>{function.id: function.receiver.encode()},
      patchUri: Uri.parse('http://127.0.0.1:18080/patch.e1.signed.json'),
      trustedPublicKeys: <String, E1TrustedPublicKey>{
        trustedKey.keyId: trustedKey,
      },
      log: (_) {},
    );
    await controller.initialize();
  });

  tearDown(() async {
    await controller.close();
    E0PatchRuntime.reset();
    await storage.delete(recursive: true);
  });

  test('minimal signed-envelope corpus rejects before activation', () {
    final corpus = <List<int>>[
      const <int>[],
      const <int>[0],
      utf8.encode('{}'),
      utf8.encode('{not-json'),
      <int>[0xff, 0xfe, 0xfd],
      List<int>.filled(E1SignedPatchEnvelope.maxBytes + 1, 0),
    ];
    for (var index = 0; index < corpus.length; index++) {
      expect(
        () => E1SignedPatchEnvelope.decodeFraming(corpus[index]),
        throwsFormatException,
        reason: 'seed=0x${_lifecycleFuzzSeed.toRadixString(16)} case=$index',
      );
    }
  });

  test(
    'seeded malformed candidates never mutate active runtime or durable state',
    () async {
      final envelope = await E1SignedPatchEnvelope.sign(
        patchBytes: patch,
        keyId: _keyId,
        privateKeySeed: _seed,
      );
      expect(await controller.activateBytes(envelope), isTrue);
      expect(
        await controller.markHealthy(),
        isTrue,
        reason: controller.status.toJson().toString(),
      );
      final function = manifest.functions.single;
      final active = E0PatchRuntime.lookup(function.slot)!;
      final before = await _stateCopies(storage);
      var state = _lifecycleFuzzSeed;

      for (var index = 0; index < _lifecycleFuzzCases; index++) {
        state = _nextSeed(state);
        final candidate = _mutatedEnvelope(envelope, state, index);
        expect(
          await controller.activateBytes(candidate),
          isFalse,
          reason: 'seed=0x${state.toRadixString(16)} case=$index',
        );
        expect(E0PatchRuntime.lookup(function.slot), same(active));
        final after = await _stateCopies(storage);
        for (final name in before.keys) {
          expect(after[name], before[name], reason: 'state copy $name changed');
        }
      }
    },
  );
}

List<int> _mutatedEnvelope(List<int> envelope, int seed, int index) {
  if ((seed + index) % 9 == 8) {
    return List<int>.filled(E1SignedPatchEnvelope.maxBytes + 1, 0);
  }
  if ((seed + index) % 9 == 0) {
    return envelope.sublist(0, envelope.length - 1);
  }
  if ((seed + index) % 9 == 1) {
    return <int>[...envelope, 0];
  }

  final value = jsonDecode(utf8.decode(envelope)) as Map<String, Object?>;
  switch ((seed + index) % 9) {
    case 2:
      value['keyId'] = 'untrusted-key';
    case 3:
      final bytes = base64.decode(value['patch']! as String).toList();
      bytes[seed % bytes.length] ^= 1;
      value['patch'] = base64.encode(bytes);
    case 4:
      value['signature'] = base64.encode(List<int>.filled(64, 0));
    case 5:
      value['unexpected'] = true;
    case 6:
      value['patch'] = '*';
    case 7:
      value['envelopeVersion'] = 2;
  }
  return utf8.encode(jsonEncode(value));
}

Future<Map<String, String>> _stateCopies(Directory storage) async {
  final result = <String, String>{};
  for (final name in <String>['state-v3-a.json', 'state-v3-b.json']) {
    result[name] = await File('${storage.path}/$name').readAsString();
  }
  return result;
}

int _nextSeed(int state) => (state * 1_664_525 + 1_013_904_223) & 0x7fffffff;
