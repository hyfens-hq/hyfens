import 'dart:async';
import 'dart:io';

import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:instrumentation_e0/e0_runtime.dart';

import 'package:conformance/widget_factories.dart';

const String e1AppId = 'dev.hyfens.conformance';
const String e1ReleaseId = 'android-e1-release-1';
const String e1BuildFingerprint = 'conformance-build-1';
const String e1CalculateAsyncPriceId =
    'sha256:27df5cfb07c0a0fa103e75928e160dd93aa6e197e4d334e241445eb4f6ad187e';
const String e1CalculatePriceId =
    'sha256:d5a3b64831b9a76d7d43cc8645ce79415061f59039f12963a272c51a005fe361';
const String e1PricingCardBuildId =
    'sha256:4c3e1a9b4ff3f6eddee674c52fef538d69b214842366cff571cf88b0c95f2849';
const int e1CalculateAsyncPriceSlot = 0;
const int e1CalculatePriceSlot = 1;
const int e1PricingCardBuildSlot = 1;
const String e1CalculateAsyncPriceSignature =
    '{"parameters":[{"kind":"int","nullable":false},{"kind":"int","nullable":false}],"return":{"kind":"int","nullable":false},"async":true}';
const String e1CalculatePriceSignature =
    '{"parameters":[{"kind":"int","nullable":false},{"kind":"int","nullable":false}],"return":{"kind":"int","nullable":false},"async":false}';
const String e1NoReceiver = '{"id":"none","ownerClass":null,"members":[]}';
const String e1SigningKeyId = 'phase0b-rfc8032-test-only';
const List<int> e1SigningPublicKey = <int>[
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

/// This public key belongs to an RFC 8032 test vector. It is intentionally
/// public and suitable only for the local Phase 0B conformance fixture.
final Map<String, E1TrustedPublicKey> e1TrustedPublicKeys =
    <String, E1TrustedPublicKey>{
      e1SigningKeyId: E1TrustedPublicKey(
        keyId: e1SigningKeyId,
        bytes: e1SigningPublicKey,
      ),
    };

final E0AsyncCapabilityDescriptor e1HostImmediateCapability =
    E0AsyncCapabilityDescriptor(
      id: 'hyfens.e1.host.immediate',
      sourceName: 'hostImmediate',
      version: 1,
      arguments: <E0ValueSchema>[E0ValueSchema.integer],
      result: E0ValueSchema.integer,
    );

final E0CapabilityAuthority e1CapabilityAuthority = E0CapabilityAuthority(
  shipped: <E0AsyncCapabilityDescriptor>[e1HostImmediateCapability],
  registry: E0CapabilityRegistry(<E0CapabilityRegistration>[
    E0CapabilityRegistration(
      e1HostImmediateCapability,
      (arguments) => Future<Object?>.delayed(
        const Duration(milliseconds: 2),
        () => (arguments.single as int) * 80,
      ),
    ),
  ]),
);

/// The fixture's single integration seam. Business functions and widgets do
/// not import a per-function patch API, annotation, or PatchView.
E1PatchController createPatchController(
  Directory supportDirectory, {
  Uri? patchUri,
}) {
  return E1PatchController(
    storageDirectory: Directory('${supportDirectory.path}/hyfens-e1'),
    appId: e1AppId,
    releaseId: e1ReleaseId,
    buildFingerprint: e1BuildFingerprint,
    functions: const <String, int>{
      e1CalculateAsyncPriceId: e1CalculateAsyncPriceSlot,
      e1CalculatePriceId: e1CalculatePriceSlot,
    },
    signatures: const <String, String>{
      e1CalculateAsyncPriceId: e1CalculateAsyncPriceSignature,
      e1CalculatePriceId: e1CalculatePriceSignature,
    },
    receivers: const <String, String>{
      e1CalculateAsyncPriceId: e1NoReceiver,
      e1CalculatePriceId: e1NoReceiver,
    },
    runtimeConfiguration: E1RuntimeConfiguration(
      capabilities: e1CapabilityAuthority,
      widgetFactories: createConformanceWidgetRegistry(),
    ),
    trustedPublicKeys: e1TrustedPublicKeys,
    patchUri:
        patchUri ?? Uri.parse('http://127.0.0.1:18080/patch.e1.signed.json'),
  );
}
