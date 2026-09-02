import 'dart:io';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

const _appId = 'dev.hyfens.conformance';
const _releaseId = 'android-e1-release-1';
const _buildFingerprint = 'conformance-build-1';
const _keyId = 'phase0b-rfc8032-test-only';
const _functionId =
    'sha256:d5a3b64831b9a76d7d43cc8645ce79415061f59039f12963a272c51a005fe361';

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

const _publicKey = <int>[
  0xd7,
  0x5a,
  0x98,
  0x01,
  0x82,
  0xb1,
  0x0a,
  0xb7,
  0xd5,
  0x4b,
  0xfe,
  0xd3,
  0xc9,
  0x64,
  0x07,
  0x3a,
  0x0e,
  0xe1,
  0x72,
  0xf3,
  0xda,
  0xa6,
  0x23,
  0x25,
  0xaf,
  0x02,
  0x1a,
  0x68,
  0xf7,
  0x07,
  0x51,
  0x1a,
];

void main() {
  late Directory root;
  late E1PatchController generatedController;
  late E1PatchController manualController;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hyfens-generated-manual-');
    final trustedKey = E1TrustedPublicKey(keyId: _keyId, bytes: _publicKey);
    generatedController = _controller(
      Directory('${root.path}/generated'),
      trustedKey,
    );
    manualController = _controller(
      Directory('${root.path}/manual'),
      trustedKey,
    );
    E0PatchRuntime.reset();
  });

  tearDown(() async {
    await generatedController.close();
    await manualController.close();
    E0PatchRuntime.reset();
    await root.delete(recursive: true);
  });

  test('conflicting controller cannot reset admitted manual patch', () async {
    // The generated bootstrap and the app-owned/manual path use separate
    // controller storage roots but share the process-global E0 registry.
    await manualController.initialize();

    final patch = await E1SignedPatchEnvelope.sign(
      patchBytes: _compilePatch(),
      keyId: _keyId,
      privateKeySeed: _seed,
    );
    expect(await manualController.activateBytes(patch), isTrue);
    expect(await manualController.markHealthy(), isTrue);
    expect(manualController.status.mode, E1PatchMode.patch);
    expect(_visiblePrice(), 450);

    // A second controller must fail before it can reset the global E0
    // registry. The generated bootstrap is single-owner; the fixture must
    // not initialize its archival manual controller in that same path.
    await expectLater(
      generatedController.initialize(),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('already owned by another patch controller'),
        ),
      ),
    );

    expect(manualController.status.mode, E1PatchMode.patch);
    expect(E0PatchRuntime.lookup(0), isNotNull);
    expect(
      _visiblePrice(),
      450,
      reason:
          'a conflicting controller must not reset an admitted/healthy '
          'patch from the active runtime owner',
    );
  });

  test('closing the owner releases the process runtime lease', () async {
    await manualController.initialize();
    await manualController.close();

    await generatedController.initialize();
    expect(generatedController.status.mode, E1PatchMode.base);
  });

  test('generated bootstrap marker survives controller runtime reset', () {
    E0PatchRuntime.markGeneratedIntegrationStarted();
    expect(E0PatchRuntime.generatedIntegrationStarted, isTrue);

    E0PatchRuntime.reset();

    expect(E0PatchRuntime.generatedIntegrationStarted, isTrue);
  });
}

E1PatchController _controller(
  Directory storage,
  E1TrustedPublicKey trustedKey,
) => E1PatchController(
  storageDirectory: storage,
  appId: _appId,
  releaseId: _releaseId,
  buildFingerprint: _buildFingerprint,
  functions: const <String, int>{_functionId: 0},
  signatures: <String, String>{
    _functionId: E0FunctionSignature.legacyInt2.encode(),
  },
  receivers: <String, String>{_functionId: E0ReceiverDescriptor.none.encode()},
  patchUri: Uri.parse('http://127.0.0.1:18080/patch.e1.signed.json'),
  trustedPublicKeys: <String, E1TrustedPublicKey>{_keyId: trustedKey},
);

List<int> _compilePatch() {
  final identity = E0Identity().declaration(
    canonicalLibraryUri: 'package:conformance/main.dart',
    declarationName: 'calculatePrice',
  );
  final manifest = E0ReleaseManifest(
    appId: _appId,
    releaseId: _releaseId,
    buildFingerprint: _buildFingerprint,
    canonicalLibraryUri: 'package:conformance/main.dart',
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
    source: '''
int calculatePrice(int quantity, int tier) {
  if (quantity < 1) return 0;
  if (tier == 2) return quantity * 70;
  if (quantity < 3) return quantity * 95;
  return quantity * 75;
}
''',
    manifest: manifest,
    functionName: 'calculatePrice',
    patchSequence: 1,
  );
}

int _visiblePrice() {
  final patch = E0PatchRuntime.lookup(0);
  if (patch == null) return 6 * 90;
  return E0PatchRuntime.invokeInt2(patch, 6, 1) ?? 6 * 90;
}
