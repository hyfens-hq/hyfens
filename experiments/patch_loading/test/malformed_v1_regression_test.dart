import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

const _appId = 'malformed-v1-app';
const _releaseId = 'malformed-v1-release';
const _buildFingerprint = 'malformed-v1-build';
const _keyId = 'malformed-v1-key';
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
    storage = await Directory.systemTemp.createTemp('hyfens-malformed-v1-');
    final pair = await DartEd25519().newKeyPairFromSeed(_seed);
    trustedKey = E1TrustedPublicKey(
      keyId: _keyId,
      bytes: (await pair.extractPublicKey()).bytes,
    );
    pair.destroy();

    manifest = E0SourceTransformer()
        .transform(
          source:
              'int target(int left, int right) { return left + right; }\n'
              'void main(List<String> arguments) {}',
          packageName: 'malformed_v1_fixture',
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
      patchUri: Uri.parse('http://127.0.0.1:1/v1/patch'),
      trustedPublicKeys: <String, E1TrustedPublicKey>{_keyId: trustedKey},
      log: (_) {},
    );
    await controller.initialize();
  });

  tearDown(() async {
    await controller.close();
    E0PatchRuntime.reset();
    await storage.delete(recursive: true);
  });

  test('raw malformed Patch Format v1 never mutates active state', () async {
    final envelope = await E1SignedPatchEnvelope.sign(
      patchBytes: patch,
      keyId: _keyId,
      privateKeySeed: _seed,
    );
    expect(await controller.activateBytes(envelope), isTrue);
    expect(
      await controller.markHealthy(),
      isTrue,
      reason: controller.status.detail,
    );
    final function = manifest.functions.single;
    final active = E0PatchRuntime.lookup(function.slot)!;
    final before = await _stateCopies(storage);

    final candidates = <List<int>>[
      <int>[...PatchFormatV1.magic, 0, 1, 0, 0],
      <int>[
        ...PatchFormatV1.magic,
        0,
        patchFormatV1,
        0,
        0,
        0,
        0,
        0,
        0,
        0xff,
        0xff,
      ],
      List<int>.filled(PatchFormatLimits.maxArtifactBytes + 1, 0),
    ];

    for (var index = 0; index < candidates.length; index++) {
      expect(
        await controller.activateBytes(candidates[index]),
        isFalse,
        reason: 'candidate=$index',
      );
      expect(E0PatchRuntime.lookup(function.slot), same(active));
      expect(await _stateCopies(storage), before, reason: 'candidate=$index');
    }
    expect(E0PatchRuntime.invokeInt2(active, 2, 3), 5);
  });

  test(
    'corrupting both lifecycle copies locks recovery without activation',
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
        reason: controller.status.detail,
      );
      await controller.close();

      File('${storage.path}/state-v3-a.json').writeAsStringSync('{bad-a');
      File('${storage.path}/state-v3-b.json').writeAsStringSync('{bad-b');
      controller = _newController(storage, trustedKey, manifest);
      await controller.initialize();

      expect(controller.recoveryNeeded, isTrue);
      expect(controller.status.mode, E1PatchMode.base);
      expect(E0PatchRuntime.lookup(manifest.functions.single.slot), isNull);
    },
  );
}

E1PatchController _newController(
  Directory storage,
  E1TrustedPublicKey trustedKey,
  E0ReleaseManifest manifest,
) {
  final function = manifest.functions.single;
  return E1PatchController(
    storageDirectory: storage,
    appId: _appId,
    releaseId: _releaseId,
    buildFingerprint: _buildFingerprint,
    functions: <String, int>{function.id: function.slot},
    signatures: <String, String>{function.id: function.signature.encode()},
    receivers: <String, String>{function.id: function.receiver.encode()},
    patchUri: Uri.parse('http://127.0.0.1:1/v1/patch'),
    trustedPublicKeys: <String, E1TrustedPublicKey>{_keyId: trustedKey},
    log: (_) {},
  );
}

Future<Map<String, String>> _stateCopies(Directory storage) async {
  final result = <String, String>{};
  for (final name in <String>['state-v3-a.json', 'state-v3-b.json']) {
    result[name] = await File('${storage.path}/$name').readAsString();
  }
  return result;
}
