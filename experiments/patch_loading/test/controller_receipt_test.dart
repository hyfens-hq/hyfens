import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:hyfens_runtime/runtime.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

const _appId = 'dev.hyfens.receipts';
const _releaseId = 'android-receipts-release-1';
const _buildFingerprint = 'receipts-build-1';
const _artifactSignerKeyId = 'receipts-2026-a';
const _installationKeyId =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
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
var _controllerNow = DateTime.utc(2036, 1, 10);

void main() {
  late Directory storage;
  late E1PatchController controller;
  late E1TrustedPublicKey trustedKey;

  setUp(() async {
    _controllerNow = DateTime.utc(2036, 1, 10);
    storage = await Directory.systemTemp.createTemp('hyfens-e1-receipts-');
    final keyPair = await DartEd25519().newKeyPairFromSeed(_seed);
    trustedKey = E1TrustedPublicKey(
      keyId: _artifactSignerKeyId,
      bytes: (await keyPair.extractPublicKey()).bytes,
    );
    keyPair.destroy();
    controller = _controller(storage, trustedKey);
    E0PatchRuntime.reset();
  });

  tearDown(() async {
    await controller.close();
    E0PatchRuntime.reset();
    await storage.delete(recursive: true);
  });

  test('receipt context is exact, bounded, JSON-safe, and immutable', () {
    final source = _receiptBody(const <int>[1, 2, 3]);
    final context = E1InstallReceiptContext(body: source);
    source['receipt_id'] = 'changed-after-construction';

    expect(context.receiptId, 'receipt-1');
    expect(context.keyId, _installationKeyId);
    expect(context.keyId, isNot(_artifactSignerKeyId));
    expect(context.body.keys.toSet(), E1InstallReceiptContext.wireKeys);
    expect(context.body['result'], 'activated');
    expect(context.activationDeadline, _defaultActivationDeadline);
    expect(context.body.containsKey('signature'), isFalse);
    expect(
      () => context.body['receipt_id'] = 'changed',
      throwsUnsupportedError,
    );

    expect(
      () => E1InstallReceiptContext(
        body: <String, Object?>{
          ..._receiptBody(const <int>[1, 2, 3]),
          'signature': 'not-yet',
        },
      ),
      throwsFormatException,
    );
    expect(
      () => E1InstallReceiptContext(
        body: <String, Object?>{
          ..._receiptBody(const <int>[1, 2, 3]),
          'artifact_digest': 'not-a-digest',
        },
      ),
      throwsFormatException,
    );
    expect(
      () => E1InstallReceiptContext(
        body: <String, Object?>{
          ..._receiptBody(const <int>[1, 2, 3]),
          'challenge': <Object?>['not', 'scalar'],
        },
      ),
      throwsFormatException,
    );
    expect(
      () => E1InstallReceiptContext(
        body: <String, Object?>{
          ..._receiptBody(const <int>[1, 2, 3]),
          'activation_deadline': 'not-utc',
        },
      ),
      throwsFormatException,
    );
  });

  test(
    'healthy commit queues one receipt and healthy idempotency adds no extra',
    () async {
      await controller.initialize();
      final artifact = await _signed(_discountPatch, 1);
      final context = _receipt(artifact);

      expect(
        await controller.activateBytes(artifact, receiptContext: context),
        isTrue,
      );
      expect(controller.pendingInstallReceipts, isEmpty);
      final pending = await _state(storage);
      expect(pending['stateVersion'], 5);
      expect(pending['health'], 'pending');
      expect(pending['pendingInstallReceipt'], context.body);

      expect(await controller.markHealthy(), isTrue);
      expect(controller.pendingInstallReceipts, hasLength(1));
      expect(controller.pendingInstallReceipts.single.body, context.body);
      expect((await _state(storage))['installReceiptOutbox'], [context.body]);

      expect(
        await controller.activateBytes(artifact, receiptContext: context),
        isTrue,
      );
      expect(controller.pendingInstallReceipts, hasLength(1));
      expect(await controller.markHealthy(), isFalse);
    },
  );

  test('legacy envelope remains receipt-less and cannot attest an arbitrary patch identity', () async {
    await controller.initialize();
    final legacy = await E1SignedPatchEnvelope.sign(
      patchBytes: _compile(_discountPatch, 1),
      keyId: _artifactSignerKeyId,
      privateKeySeed: _seed,
    );
    expect(
      await controller.activateBytes(
        legacy,
        receiptContext: E1InstallReceiptContext(body: _receiptBody(legacy)),
      ),
      isFalse,
    );
    expect(controller.pendingInstallReceipts, isEmpty);
    expect(controller.durableState.current, isNull);
    expect(await controller.activateBytes(legacy), isTrue);
    expect(await controller.markHealthy(), isTrue);
    expect(controller.pendingInstallReceipts, isEmpty);
  });

  test(
    'receipt patch identity must equal the signed format identity',
    () async {
      await controller.initialize();
      final artifact = await _signed(_discountPatch, 1);
      expect(
        await controller.activateBytes(
          artifact,
          receiptContext: E1InstallReceiptContext(
            body: {..._receiptBody(artifact), 'patch_id': 'another-patch'},
          ),
        ),
        isFalse,
      );
      expect(controller.pendingInstallReceipts, isEmpty);
      expect(controller.durableState.current, isNull);
    },
  );

  test('expired receipt cannot publish a new candidate', () async {
    await controller.initialize();
    final artifact = await _signed(_discountPatch, 1);
    final expired = _receipt(
      artifact,
      activationDeadline: '2036-01-09T23:59:59.000Z',
    );

    expect(
      await controller.activateBytes(artifact, receiptContext: expired),
      isFalse,
    );
    expect(controller.durableState.health, 'base');
    expect(controller.durableState.current, isNull);
    expect(controller.pendingInstallReceipts, isEmpty);
    expect(controller.durableState.highWaterSequence, 0);
  });

  test(
    'expired pending candidate rolls back without losing ready outbox',
    () async {
      await controller.initialize();
      final first = await _signed(_discountPatch, 1);
      final firstContext = _receipt(first, receiptId: 'receipt-first');
      expect(
        await _activateHealthy(controller, first, receiptContext: firstContext),
        isTrue,
      );

      final second = await _signed(_alternatePatch, 2);
      final secondContext = _receipt(
        second,
        receiptId: 'receipt-second',
        activationDeadline: '2036-01-10T01:00:00.000Z',
      );
      expect(
        await controller.activateBytes(second, receiptContext: secondContext),
        isTrue,
      );
      _controllerNow = DateTime.utc(2036, 1, 10, 2);

      expect(await controller.markHealthy(), isFalse);
      expect(controller.durableState.health, 'healthy');
      expect(
        controller.durableState.current,
        contains(sha256.convert(first).toString()),
      );
      expect(controller.pendingInstallReceipts, hasLength(1));
      expect(controller.pendingInstallReceipts.single.body, firstContext.body);
      expect((await _state(storage))['pendingInstallReceipt'], isNull);
      expect((await _state(storage))['installReceiptOutbox'], [
        firstContext.body,
      ]);
    },
  );

  test(
    'expired pending candidate is not booted after restart and outbox survives',
    () async {
      await controller.initialize();
      final first = await _signed(_discountPatch, 1);
      final firstContext = _receipt(first, receiptId: 'receipt-first');
      expect(
        await _activateHealthy(controller, first, receiptContext: firstContext),
        isTrue,
      );

      final second = await _signed(_alternatePatch, 2);
      final secondContext = _receipt(
        second,
        receiptId: 'receipt-second',
        activationDeadline: '2036-01-10T01:00:00.000Z',
      );
      expect(
        await controller.activateBytes(second, receiptContext: secondContext),
        isTrue,
      );
      _controllerNow = DateTime.utc(2036, 1, 10, 2);
      await controller.close();

      controller = _controller(storage, trustedKey);
      await controller.initialize();

      expect(controller.durableState.health, 'healthy');
      expect(
        controller.durableState.current,
        contains(sha256.convert(first).toString()),
      );
      expect(controller.pendingInstallReceipts, hasLength(1));
      expect(controller.pendingInstallReceipts.single.body, firstContext.body);
      expect(_execute(6, 1), 450);
    },
  );

  test(
    'ack after expiry removes only the acknowledged ready receipt',
    () async {
      await controller.initialize();
      final artifact = await _signed(_discountPatch, 1);
      final context = _receipt(artifact);
      expect(
        await _activateHealthy(controller, artifact, receiptContext: context),
        isTrue,
      );
      _controllerNow = DateTime.utc(2036, 1, 12);

      expect(await controller.ackInstallReceipt(context.receiptId), isTrue);
      expect(controller.pendingInstallReceipts, isEmpty);
      expect((await _state(storage))['installReceiptOutbox'], isEmpty);
    },
  );

  test(
    'unacked receipt survives restart, retry, new patch, and persisted ack',
    () async {
      await controller.initialize();
      final first = await _signed(_discountPatch, 1);
      final context = _receipt(first);
      expect(
        await _activateHealthy(controller, first, receiptContext: context),
        isTrue,
      );

      await controller.close();
      controller = _controller(storage, trustedKey);
      await controller.initialize();
      expect(controller.pendingInstallReceipts.single.body, context.body);

      // A lost sender response retries the same activation without creating
      // another ready receipt for an already healthy artifact.
      expect(
        await controller.activateBytes(first, receiptContext: context),
        isTrue,
      );
      expect(controller.pendingInstallReceipts, hasLength(1));

      // A later patch and a rollback boundary do not consume the outbox.
      final second = await _signed(_alternatePatch, 2);
      expect(await _activateHealthy(controller, second), isTrue);
      expect(controller.pendingInstallReceipts, hasLength(1));
      await controller.close();
      controller = _controller(storage, trustedKey);
      await controller.initialize();
      expect(controller.pendingInstallReceipts.single.body, context.body);

      expect(await controller.ackInstallReceipt('unknown-receipt'), isFalse);
      expect(controller.pendingInstallReceipts, hasLength(1));
      expect(await controller.ackInstallReceipt(context.receiptId), isTrue);
      expect(controller.pendingInstallReceipts, isEmpty);

      await controller.close();
      controller = _controller(storage, trustedKey);
      await controller.initialize();
      expect(controller.pendingInstallReceipts, isEmpty);
    },
  );

  test(
    'failed candidate and failed health never produce a ready receipt',
    () async {
      await controller.close();
      controller = _controller(
        storage,
        trustedKey,
        testHooks: E1PatchControllerTestHooks(
          beforeRuntimePublish: () async {
            throw StateError('injected candidate publish failure');
          },
        ),
      );
      await controller.initialize();
      final failedArtifact = await _signed(_discountPatch, 1);
      expect(
        await controller.activateBytes(
          failedArtifact,
          receiptContext: _receipt(failedArtifact),
        ),
        isFalse,
      );
      expect(controller.pendingInstallReceipts, isEmpty);
      expect((await _state(storage))['health'], 'base');

      await controller.close();
      var failNextHealthWrite = false;
      controller = _controller(
        storage,
        trustedKey,
        testHooks: E1PatchControllerTestHooks(
          beforeStateCopyWrite: (copyName, _) async {
            if (failNextHealthWrite && copyName == 'state-v3-b.json') {
              failNextHealthWrite = false;
              throw const FileSystemException('injected health commit failure');
            }
          },
        ),
      );
      await controller.initialize();
      final healthyArtifact = await _signed(_discountPatch, 1);
      final context = _receipt(healthyArtifact);
      expect(
        await controller.activateBytes(
          healthyArtifact,
          receiptContext: context,
        ),
        isTrue,
      );
      failNextHealthWrite = true;
      await expectLater(controller.markHealthy(), throwsA(isA<Object>()));
      expect(controller.pendingInstallReceipts, isEmpty);
      final stillPending = await _state(storage);
      expect(stillPending['health'], 'pending');
      expect(stillPending['pendingInstallReceipt'], context.body);
    },
  );

  test(
    'rollback discards only the candidate context and retains ready receipts',
    () async {
      await controller.initialize();
      final first = await _signed(_discountPatch, 1);
      final firstContext = _receipt(first, receiptId: 'receipt-first');
      expect(
        await _activateHealthy(controller, first, receiptContext: firstContext),
        isTrue,
      );

      final second = await _signed(_alternatePatch, 2);
      final secondContext = _receipt(second, receiptId: 'receipt-second');
      expect(
        await controller.activateBytes(second, receiptContext: secondContext),
        isTrue,
      );
      expect(controller.pendingInstallReceipts, hasLength(1));
      expect(
        (await _state(storage))['pendingInstallReceipt'],
        secondContext.body,
      );

      expect(await controller.rollback(), isTrue);
      expect(controller.pendingInstallReceipts.single.body, firstContext.body);
      final rolledBack = await _state(storage);
      expect(rolledBack['health'], 'base');
      expect(rolledBack['pendingInstallReceipt'], isNull);
      expect(rolledBack['installReceiptOutbox'], [firstContext.body]);

      await controller.close();
      controller = _controller(storage, trustedKey);
      await controller.initialize();
      expect(controller.pendingInstallReceipts.single.body, firstContext.body);
    },
  );

  test('a full outbox rejects only a new receipt-bearing activation', () async {
    await controller.initialize();
    final first = await _signed(_discountPatch, 1);
    final firstContext = _receipt(first, receiptId: 'receipt-000');
    expect(
      await _activateHealthy(controller, first, receiptContext: firstContext),
      isTrue,
    );
    await controller.close();

    final state = await _state(storage);
    final digest = sha256.convert(first).toString();
    final fullOutbox = <Object?>[
      for (
        var index = 0;
        index < E1PatchController.maxInstallReceiptOutbox;
        index++
      )
        E1InstallReceiptContext(
          body: _receiptBody(
            first,
            receiptId: 'receipt-${index.toString().padLeft(3, '0')}',
          ),
        ).body,
    ];
    state['installReceiptOutbox'] = fullOutbox;
    state['pendingInstallReceipt'] = null;
    expect((state['current'] as String), contains(digest));
    await _writeStateCopies(storage, state);

    controller = _controller(storage, trustedKey);
    await controller.initialize();
    expect(controller.pendingInstallReceipts, hasLength(128));
    final second = await _signed(_alternatePatch, 2);
    final secondContext = _receipt(second, receiptId: 'receipt-new');
    expect(
      await controller.activateBytes(second, receiptContext: secondContext),
      isFalse,
    );
    expect(controller.lifecycleState, E1LifecycleState.current);
    expect(_execute(6, 1), 450);
    expect(controller.pendingInstallReceipts, hasLength(128));

    // Receipt-less activation remains available and preserves the existing
    // outbox, even though the new artifact cannot add another receipt.
    expect(await controller.activateBytes(second), isTrue);
    expect(await controller.markHealthy(), isTrue);
    expect(controller.pendingInstallReceipts, hasLength(128));
  });

  test(
    'tampered receipt journal fails closed through state validation',
    () async {
      await controller.initialize();
      final artifact = await _signed(_discountPatch, 1);
      expect(
        await _activateHealthy(
          controller,
          artifact,
          receiptContext: _receipt(artifact),
        ),
        isTrue,
      );
      await controller.close();
      final state = await _state(storage);
      final outbox = List<Object?>.of(state['installReceiptOutbox']! as List);
      final tampered = Map<String, Object?>.of(
        outbox.single as Map<String, Object?>,
      )..['artifact_digest'] = 'not-a-digest';
      outbox[0] = tampered;
      state['installReceiptOutbox'] = outbox;
      await _writeStateCopies(storage, state);

      controller = _controller(storage, trustedKey);
      await controller.initialize();
      expect(controller.recoveryNeeded, isTrue);
      expect(controller.lifecycleState, E1LifecycleState.failed);
      expect(controller.status.phase, 'recoveryNeeded');
      expect(E0PatchRuntime.lookup(0), isNull);
    },
  );

  test(
    'legacy v4 state is read, repaired to v5, and remains executable',
    () async {
      await controller.initialize();
      final artifact = await _signed(_discountPatch, 1);
      expect(await _activateHealthy(controller, artifact), isTrue);
      final current = (await _state(storage))['current'];
      await controller.close();

      final legacy = await _state(storage);
      legacy
        ..remove('installReceiptOutbox')
        ..remove('pendingInstallReceipt')
        ..['stateVersion'] = 4;
      await _writeStateCopies(storage, legacy);

      controller = _controller(storage, trustedKey);
      await controller.initialize();
      expect(controller.recoveryNeeded, isFalse);
      expect(controller.pendingInstallReceipts, isEmpty);
      expect(controller.lifecycleState, E1LifecycleState.current);
      expect(_execute(6, 1), 450);
      final repaired = await _state(storage);
      expect(repaired['stateVersion'], 5);
      expect(repaired['current'], current);
      expect(repaired['installReceiptOutbox'], isEmpty);
      expect(repaired['pendingInstallReceipt'], isNull);
    },
  );
}

E1PatchController _controller(
  Directory storage,
  E1TrustedPublicKey key, {
  E1PatchControllerTestHooks? testHooks,
  DateTime Function()? clock,
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
  clock: clock ?? (() => _controllerNow),
);

Future<List<int>> _signed(String source, int sequence) async {
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: _appId,
    releaseId: _releaseId,
    patchId: 'patch-$sequence',
    sequence: sequence,
    functions: [
      PatchFunctionEntry(
        id: _functionId,
        slot: 0,
        signatureDigest: 'sha256:${'0' * 64}',
      ),
    ],
    capabilities: const [],
    constants: const [PatchValue.string('hyfens-e0-bridge-v1')],
    instructions: const [0],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: _artifactSignerKeyId,
    ),
    payloadDigest: const [],
    signature: const [],
    extensions: [
      PatchExtensionSection(
        type: patchFormatV1E0BridgeExtensionType,
        flags: 0,
        payload: utf8.encode(
          jsonEncode({
            'bridgeVersion': 1,
            'encoding': 'e0-patch-container-v9-bytes',
            'functions': {
              _functionId: base64.encode(_compile(source, sequence)),
            },
          }),
        ),
      ),
    ],
  );
  final algorithm = DartEd25519();
  final key = await algorithm.newKeyPairFromSeed(_seed);
  try {
    return PatchFormatV1.encode(
      await PatchFormatV1.sealAsync(
        draft,
        (bytes) async => (await algorithm.sign(bytes, keyPair: key)).bytes,
      ),
    );
  } finally {
    key.destroy();
  }
}

Future<bool> _activateHealthy(
  E1PatchController controller,
  List<int> artifact, {
  E1InstallReceiptContext? receiptContext,
}) async {
  if (!await controller.activateBytes(
    artifact,
    receiptContext: receiptContext,
  )) {
    return false;
  }
  return controller.markHealthy();
}

E1InstallReceiptContext _receipt(
  List<int> artifact, {
  String receiptId = 'receipt-1',
  String activationDeadline = _defaultActivationDeadline,
}) => E1InstallReceiptContext(
  body: _receiptBody(
    artifact,
    patchId: PatchFormatV1.decode(artifact).patchId,
    receiptId: receiptId,
    activationDeadline: activationDeadline,
  ),
);

Map<String, Object?> _receiptBody(
  List<int> artifact, {
  String receiptId = 'receipt-1',
  String patchId = 'patch-1',
  String activationDeadline = _defaultActivationDeadline,
}) => <String, Object?>{
  'version': 1,
  'receipt_id': receiptId,
  'installation_id': 'installation-1',
  'key_id': _installationKeyId,
  'application_id': 'control-plane-app-1',
  'environment_id': 'environment-1',
  'release_id': _releaseId,
  'runtime_application_id': _appId,
  'platform': 'android',
  'patch_id': patchId,
  'artifact_digest': 'sha256:${sha256.convert(artifact)}',
  'admission_id': 'admission-1',
  'challenge': 'challenge-1',
  'runtime_version': 'runtime-test-1',
  'activation_deadline': activationDeadline,
  'result': 'activated',
};

const _defaultActivationDeadline = '2036-01-11T00:00:00.000Z';

List<int> _compile(String source, int sequence) {
  final identity = E0Identity().declaration(
    canonicalLibraryUri: 'package:receipts/main.dart',
    declarationName: 'calculatePrice',
  );
  final manifest = E0ReleaseManifest(
    appId: _appId,
    releaseId: _releaseId,
    buildFingerprint: _buildFingerprint,
    canonicalLibraryUri: 'package:receipts/main.dart',
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

Future<Map<String, Object?>> _state(Directory storage) async =>
    jsonDecode(await File('${storage.path}/state-v3-a.json').readAsString())
        as Map<String, Object?>;

Future<void> _writeStateCopies(
  Directory storage,
  Map<String, Object?> input,
) async {
  final body = Map<String, Object?>.of(input)..remove('checksum');
  final checksum = sha256.convert(utf8.encode(jsonEncode(body))).toString();
  final value = <String, Object?>{...body, 'checksum': checksum};
  final encoded = jsonEncode(<String, Object?>{
    for (final key in value.keys.toList()..sort()) key: value[key],
  });
  for (final name in <String>['state-v3-a.json', 'state-v3-b.json']) {
    await File('${storage.path}/$name').writeAsString(encoded);
  }
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
