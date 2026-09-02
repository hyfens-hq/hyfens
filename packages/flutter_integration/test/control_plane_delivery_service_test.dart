import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:hyfens_flutter_integration/flutter_integration.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:hyfens_runtime/runtime.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

const _appId = 'dev.hyfens.service-delivery';
const _releaseId = 'service-delivery-release-1';
const _buildFingerprint = 'service-delivery-build-1';
const _keyId = 'service-delivery-key';
const _functionId =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
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
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  late ControlPlaneHttpServer httpService;
  late HttpServer server;

  setUp(() async {
    storage = await Directory.systemTemp.createTemp(
      'hyfens-control-plane-runtime-',
    );
    service = ControlPlaneService(store: FileControlPlaneStore(storage));
    bootstrap = await service.bootstrap(
      organizationName: 'Runtime delivery test',
      runtimeApplicationId: _appId,
      platformId: 'android-arm64-release',
      environmentName: 'development',
    );
    httpService = ControlPlaneHttpServer(
      service,
      discovery: const ControlPlaneDiscoveryConfig(apiBasePath: '/p2/'),
    );
    server = await httpService.bind();
    final publicKey = await _publicKey();
    final controllerStorage = Directory('${storage.path}/runtime');
    controller = E1PatchController(
      storageDirectory: controllerStorage,
      appId: _appId,
      releaseId: _releaseId,
      buildFingerprint: _buildFingerprint,
      functions: const <String, int>{_functionId: 0},
      signatures: <String, String>{
        _functionId: E0FunctionSignature.legacyInt2.encode(),
      },
      receivers: <String, String>{
        _functionId: E0ReceiverDescriptor.none.encode(),
      },
      patchUri: Uri.parse('http://127.0.0.1:1/unused'),
      trustedPublicKeys: <String, E1TrustedPublicKey>{
        _keyId: E1TrustedPublicKey(keyId: _keyId, bytes: publicKey),
      },
    );
    E0PatchRuntime.reset();
    await controller.initialize();
  });

  tearDown(() async {
    await server.close(force: true);
    await controller.close();
    E0PatchRuntime.reset();
    await storage.delete(recursive: true);
  });

  test(
    'real authenticated service lookup/fetch reaches runtime activation',
    () async {
      final publicKey = await _publicKey();
      final patchBytes = await _patchFormatArtifact();
      final release = await service.registerRelease(
        token: bootstrap.controlCredential.token,
        idempotencyKey: 'service-release-1',
        spec: ReleaseSpec(
          applicationId: bootstrap.application.id,
          platformId: 'plt_android_arm64_release',
          runtimeApplicationId: _appId,
          runtimeReleaseId: _releaseId,
          buildTarget: 'android-arm64-release',
          runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
          patchFormatVersion: patchFormatV1,
          buildFingerprint: _digest('build'),
          capabilityAuthorityDigest: _digest('capability'),
          functionSignatureDigest: _digest('functions'),
          displayVersion: '0.1.0',
          signingPublicKeys: <String, String>{_keyId: base64.encode(publicKey)},
        ),
      );
      final patch = await service.registerPatch(
        token: bootstrap.controlCredential.token,
        releaseId: release.id,
        idempotencyKey: 'service-patch-1',
        spec: PatchSpec(
          runtimePatchId: 'service-patch-1',
          sequence: 1,
          artifactId: 'art_service_delivery_1',
          sha256: _digest(patchBytes),
          sizeBytes: patchBytes.length,
          signatureKeyId: _keyId,
        ),
      );
      await service.uploadArtifact(
        token: bootstrap.controlCredential.token,
        artifactId: patch.artifactId,
        bytes: patchBytes,
        idempotencyKey: 'service-artifact-1',
      );
      await service.promote(
        token: bootstrap.controlCredential.token,
        environmentId: bootstrap.environment.id,
        releaseId: release.id,
        expectedVersion: 0,
        idempotencyKey: 'service-promotion-1',
      );

      final adapter = HyfensControlPlaneDelivery(
        HyfensControlPlaneConfiguration(
          baseUrl: Uri.parse('http://127.0.0.1:${server.port}/p2/'),
          deliveryCredential: bootstrap.deliveryCredential.token,
          applicationId: bootstrap.application.id,
          environmentId: bootstrap.environment.id,
          platformId: 'plt_android_arm64_release',
        ),
      );
      final result = await adapter.deliver(controller);

      expect(result.decision, HyfensDeliveryDecision.patchAvailable);
      expect(result.activated, isTrue);
      expect(await controller.markHealthy(), isTrue);
      expect(controller.durableState.highWaterSequence, 1);
      expect(controller.status.mode, E1PatchMode.patch);

      await server.close(force: true);
      await expectLater(
        adapter.deliver(controller),
        throwsA(isA<HyfensControlPlaneDeliveryException>()),
      );
      expect(controller.status.mode, E1PatchMode.patch);
      expect(controller.durableState.highWaterSequence, 1);

      expect(await controller.rollback(), isTrue);
      expect(controller.status.mode, E1PatchMode.base);
      expect(controller.durableState.highWaterSequence, 1);
    },
  );
}

Future<List<int>> _publicKey() async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(_seed);
  try {
    return (await keyPair.extractPublicKey()).bytes;
  } finally {
    keyPair.destroy();
  }
}

Future<List<int>> _patchFormatArtifact() async {
  final e0Bytes = _compile();
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: _appId,
    releaseId: _releaseId,
    patchId: 'service-patch-1',
    sequence: 1,
    functions: <PatchFunctionEntry>[
      PatchFunctionEntry(
        id: _functionId,
        slot: 0,
        signatureDigest: 'sha256:${'0' * 64}',
      ),
    ],
    capabilities: const <PatchCapabilityEntry>[],
    constants: const <PatchValue>[PatchValue.string('service-delivery')],
    instructions: const <int>[0],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: _keyId,
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
    extensions: <PatchExtensionSection>[
      PatchExtensionSection(
        type: patchFormatV1E0BridgeExtensionType,
        flags: 0,
        payload: utf8.encode(
          jsonEncode(<String, Object?>{
            'bridgeVersion': 1,
            'encoding': 'e0-patch-container-v9-bytes',
            'functions': <String, String>{_functionId: base64.encode(e0Bytes)},
          }),
        ),
      ),
    ],
  );
  final algorithm = DartEd25519();
  final keyPair = await algorithm.newKeyPairFromSeed(_seed);
  try {
    final artifact = await PatchFormatV1.sealAsync(draft, (bytes) async {
      final signature = await algorithm.sign(bytes, keyPair: keyPair);
      return signature.bytes;
    });
    return PatchFormatV1.encode(artifact);
  } finally {
    keyPair.destroy();
  }
}

List<int> _compile() {
  final identity = E0Identity().declaration(
    canonicalLibraryUri: 'package:service_delivery/main.dart',
    declarationName: 'calculatePrice',
  );
  final manifest = E0ReleaseManifest(
    appId: _appId,
    releaseId: _releaseId,
    buildFingerprint: _buildFingerprint,
    canonicalLibraryUri: 'package:service_delivery/main.dart',
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
  if (tier == 2) return quantity * 80;
  return quantity * 70;
}
''',
    manifest: manifest,
    functionName: 'calculatePrice',
    patchSequence: 1,
  );
}

String _digest(Object value) {
  final bytes = value is List<int> ? value : utf8.encode(value.toString());
  return 'sha256:${sha256.convert(bytes).toString()}';
}
