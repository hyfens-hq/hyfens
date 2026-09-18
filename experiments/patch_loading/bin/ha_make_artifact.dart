import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:hyfens_patch_format/patch_format.dart';

const _seed = <int>[
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
];

Future<void> main(List<String> arguments) async {
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (!argument.startsWith('--') || index + 1 >= arguments.length) {
      throw ArgumentError('Expected --name value');
    }
    values[argument.substring(2)] = arguments[++index];
  }
  final output = values['output'];
  final publicKeyOutput = values['public-key-output'];
  final publicKeyOnly = values['public-key-only'] == 'true';
  final applicationId = values['application'];
  final releaseId = values['release'];
  final patchId = values['patch'];
  final sequence = int.tryParse(values['sequence'] ?? '');
  if (publicKeyOnly && publicKeyOutput == null) {
    throw ArgumentError('Usage: --public-key-only --public-key-output PATH');
  }
  if (!publicKeyOnly &&
      (output == null ||
          applicationId == null ||
          releaseId == null ||
          patchId == null ||
          sequence == null ||
          sequence <= 0)) {
    throw ArgumentError(
      'Usage: --output PATH --application ID --release ID --patch ID --sequence N',
    );
  }
  final algorithm = DartEd25519();
  final keyPair = await algorithm.newKeyPairFromSeed(_seed);
  try {
    if (publicKeyOutput != null) {
      final publicKey = await keyPair.extractPublicKey();
      await File(publicKeyOutput).writeAsString(
        publicKey.bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
        flush: true,
      );
    }
    if (publicKeyOnly) return;
    final draft = PatchArtifact(
      runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
      applicationId: applicationId!,
      releaseId: releaseId!,
      patchId: patchId!,
      sequence: sequence!,
      functions: const <PatchFunctionEntry>[],
      capabilities: const <PatchCapabilityEntry>[],
      constants: const <PatchValue>[],
      instructions: const <int>[],
      signatureMetadata: PatchSignatureMetadata(
        algorithm: 'ed25519',
        keyId: 'ha-fixture-key',
      ),
      payloadDigest: const <int>[],
      signature: const <int>[],
    );
    final sealed = await PatchFormatV1.sealAsync(draft, (bytes) async {
      return (await algorithm.sign(bytes, keyPair: keyPair)).bytes;
    });
    await File(output!).writeAsBytes(PatchFormatV1.encode(sealed), flush: true);
  } finally {
    keyPair.destroy();
  }
}
