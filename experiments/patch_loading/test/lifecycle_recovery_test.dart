import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

const _appId = 'dev.hyfens.lifecycle';
const _releaseId = 'android-lifecycle-release-1';
const _buildFingerprint = 'lifecycle-build-1';
const _keyId = 'lifecycle-2026-a';
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
const _functionId =
    'sha256:d5a3b64831b9a76d7d43cc8645ce79415061f59039f12963a272c51a005fe361';
const _functions = <String, int>{_functionId: 0};
const _signatures = <String, String>{
  _functionId: '{"parameters":[{"kind":"int","nullable":false},{"kind":"int","nullable":false}],"return":{"kind":"int","nullable":false},"async":false}',
};
const _receivers = <String, String>{
  _functionId: '{"id":"none","ownerClass":null,"members":[]}',
};

void main() {
  late Directory storage;
  late E1TrustedPublicKey trustedKey;
  late E1PatchController controller;

  setUp(() async {
    storage = await Directory.systemTemp.createTemp('hyfens-e1-lifecycle-');
    final keyPair = await DartEd25519().newKeyPairFromSeed(_seed);
    trustedKey = E1TrustedPublicKey(
      keyId: _keyId,
      bytes: (await keyPair.extractPublicKey()).bytes,
    );
    keyPair.destroy();
    controller = _makeController(storage, trustedKey);
    E0PatchRuntime.reset();
  });

  tearDown(() async {
    await controller.close();
    E0PatchRuntime.reset();
    await storage.delete(recursive: true);
  });

  test(
    'pending candidate is a one-attempt boot lease and keeps high-water',
    () async {
      await controller.initialize();
      final candidate = await _signed(_discountPatch, 1);
      expect(await controller.activateBytes(candidate), isTrue);
      expect(controller.lifecycleState, E1LifecycleState.candidate);
      final pending = await _state(storage);
      expect(pending['health'], 'pending');
      expect(pending['candidateBootAttempts'], 1);

      await controller.close();
      controller = _makeController(storage, trustedKey);
      await controller.initialize();

      expect(controller.lifecycleState, E1LifecycleState.base);
      expect(controller.status.phase, 'fallback');
      expect(E0PatchRuntime.lookup(0), isNull);
      final recovered = await _state(storage);
      expect(recovered['health'], 'base');
      expect(recovered['candidateBootAttempts'], 0);
      expect(recovered['highWaterSequence'], 1);

      // A second initialize sees the recovered base record; it never retries
      // the abandoned candidate and does not move the high-water backwards.
      await controller.initialize();
      expect(controller.lifecycleState, E1LifecycleState.base);
      expect((await _state(storage))['highWaterSequence'], 1);
      expect(await controller.markHealthy(), isFalse);
    },
  );

  test(
    'durable boundary fault after backup rename heals without state split',
    () async {
      await controller.close();
      var injected = false;
      final boundaries = <E1DurableBoundary>[];
      controller = _makeController(
        storage,
        trustedKey,
        testHooks: E1PatchControllerTestHooks(
          durableBoundary: (boundary, name, _) async {
            boundaries.add(boundary);
            if (!injected &&
                name == 'state-v3-b.json' &&
                boundary == E1DurableBoundary.afterStateCopyRename) {
              injected = true;
              throw StateError('simulated process boundary');
            }
          },
        ),
      );
      await controller.initialize();

      expect(
        await _activateHealthy(controller, await _signed(_discountPatch, 1)),
        isTrue,
      );
      expect(injected, isTrue);
      expect(boundaries, contains(E1DurableBoundary.afterStateCopyFlush));
      expect(boundaries, contains(E1DurableBoundary.afterStateCopyReadback));
      expect(
        await File('${storage.path}/state-v3-a.json').readAsString(),
        await File('${storage.path}/state-v3-b.json').readAsString(),
      );
      expect(controller.lifecycleState, E1LifecycleState.current);
      expect(_execute(6, 1), 450);
    },
  );

  test(
    'malformed peer heals, but a newer lower-high-water peer fails closed',
    () async {
      await controller.initialize();
      expect(
        await _activateHealthy(controller, await _signed(_discountPatch, 1)),
        isTrue,
      );
      final firstState = await _state(storage);
      expect(
        await _activateHealthy(controller, await _signed(_alternatePatch, 2)),
        isTrue,
      );
      await controller.close();
      await File('${storage.path}/state-v3-a.json').writeAsString('{torn');

      controller = _makeController(storage, trustedKey);
      await controller.initialize();
      expect(controller.lifecycleState, E1LifecycleState.current);
      expect(controller.recoveryNeeded, isFalse);
      expect(
        await File('${storage.path}/state-v3-a.json').readAsString(),
        await File('${storage.path}/state-v3-b.json').readAsString(),
      );

      final backup = await _stateFile(storage, 'state-v3-b.json');
      final forgedLedger =
          Map<String, Object?>.of(
              backup['artifactLedger']! as Map<String, Object?>,
            )
            ..['highWaterSequence'] = firstState['highWaterSequence']
            ..['highWaterDigest'] = firstState['highWaterDigest'];
      final forgedNewer = Map<String, Object?>.of(backup)
        ..['generation'] = (backup['generation']! as int) + 1
        ..['highWaterSequence'] = firstState['highWaterSequence']
        ..['highWaterDigest'] = firstState['highWaterDigest']
        ..['artifactLedger'] = forgedLedger;
      await _writeStateFile(storage, 'state-v3-a.json', forgedNewer);
      await controller.close();

      controller = _makeController(storage, trustedKey);
      await controller.initialize();
      expect(controller.lifecycleState, E1LifecycleState.failed);
      expect(controller.recoveryNeeded, isTrue);
      expect(controller.status.phase, 'recoveryNeeded');
      expect(E0PatchRuntime.lookup(0), isNull);
      expect(
        await controller.activateBytes(await _signed(_alternatePatch, 2)),
        isFalse,
      );
      expect(controller.lifecycleState, E1LifecycleState.failed);
    },
  );

  test(
    'LKG recovery changes execution without reopening an old high-water slot',
    () async {
      await controller.initialize();
      expect(
        await _activateHealthy(controller, await _signed(_discountPatch, 1)),
        isTrue,
      );
      final second = await _signed(_alternatePatch, 2);
      expect(await controller.activateBytes(second), isTrue);
      expect(controller.lifecycleState, E1LifecycleState.candidate);

      await controller.close();
      controller = _makeController(storage, trustedKey);
      await controller.initialize();
      expect(controller.lifecycleState, E1LifecycleState.current);
      expect(controller.status.phase, 'fallback');
      expect(_execute(6, 1), 450);

      final recovered = await _state(storage);
      expect(recovered['health'], 'healthy');
      expect(recovered['highWaterSequence'], 2);
      expect(await controller.activateBytes(second), isFalse);
      expect(controller.status.detail, contains('replay'));
    },
  );
}

E1PatchController _makeController(
  Directory storage,
  E1TrustedPublicKey key, {
  E1PatchControllerTestHooks? testHooks,
}) => E1PatchController(
  storageDirectory: storage,
  appId: _appId,
  releaseId: _releaseId,
  buildFingerprint: _buildFingerprint,
  functions: _functions,
  signatures: _signatures,
  receivers: _receivers,
  patchUri: Uri.parse('http://127.0.0.1:18080/patch.e1.signed.json'),
  trustedPublicKeys: <String, E1TrustedPublicKey>{key.keyId: key},
  log: (_) {},
  testHooks: testHooks,
);

Future<List<int>> _signed(String source, int sequence) =>
    E1SignedPatchEnvelope.sign(
      patchBytes: _compile(source, sequence),
      keyId: _keyId,
      privateKeySeed: _seed,
    );

List<int> _compile(String source, int sequence) {
  final identity = E0Identity().declaration(
    canonicalLibraryUri: 'package:lifecycle/main.dart',
    declarationName: 'calculatePrice',
  );
  final manifest = E0ReleaseManifest(
    appId: _appId,
    releaseId: _releaseId,
    buildFingerprint: _buildFingerprint,
    canonicalLibraryUri: 'package:lifecycle/main.dart',
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

Future<Map<String, Object?>> _state(Directory storage) =>
    _stateFile(storage, 'state-v3-a.json');

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

Future<bool> _activateHealthy(
  E1PatchController controller,
  List<int> bytes,
) async {
  if (!await controller.activateBytes(bytes)) return false;
  return controller.markHealthy();
}

int _execute(int quantity, int tier) =>
    E0PatchRuntime.invokeInt2(E0PatchRuntime.lookup(0)!, quantity, tier)!;

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
