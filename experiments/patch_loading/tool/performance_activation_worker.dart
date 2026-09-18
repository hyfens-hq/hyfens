import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';

Future<void> main(List<String> arguments) async {
  final stage = _argument(arguments, '--stage=');
  final envelopePath = _argument(arguments, '--envelope=');
  final patchPath = _argument(arguments, '--patch=');
  final trustedKey = E1TrustedPublicKey(
    keyId: 'task22-key',
    bytes: base64.decode(_argument(arguments, '--public-key=')),
  );
  final functions = _intMap(_argument(arguments, '--functions='));
  final signatures = _stringMap(_argument(arguments, '--signatures='));
  final receivers = _stringMap(_argument(arguments, '--receivers='));
  final appId = _argument(arguments, '--app-id=');
  final releaseId = _argument(arguments, '--release-id=');
  final buildFingerprint = _argument(arguments, '--build-fingerprint=');
  final envelopeBytes = stage == 'read'
      ? const <int>[]
      : File(envelopePath).readAsBytesSync();
  final patchBytes = File(patchPath).readAsBytesSync();
  final watch = Stopwatch()..start();
  var checksum = 0;
  switch (stage) {
    case 'read':
      final bytes = File(envelopePath).readAsBytesSync();
      checksum = bytes.length;
      break;
    case 'framing':
      final framed = E1SignedPatchEnvelope.decodeFraming(envelopeBytes);
      checksum = framed.patchBytes.length;
      break;
    case 'ed25519Verify':
      final verified = await E1SignedPatchEnvelope.verify(
        envelopeBytes: envelopeBytes,
        trustedKeys: <String, E1TrustedPublicKey>{trustedKey.keyId: trustedKey},
      );
      checksum = verified.patchBytes.length;
      break;
    case 'containerDecode':
      final program = E0PatchContainer.decode(
        patchBytes,
        expectedAppId: appId,
        expectedReleaseId: releaseId,
        expectedBuildFingerprint: buildFingerprint,
        expectedFunctions: functions,
        expectedSignatures: <String, E0FunctionSignature>{
          for (final entry in signatures.entries)
            entry.key: E0FunctionSignature.decode(entry.value),
        },
        expectedReceivers: <String, E0ReceiverDescriptor>{
          for (final entry in receivers.entries)
            entry.key: E0ReceiverDescriptor.decode(entry.value),
        },
      );
      checksum = program.code.length;
      break;
    case 'runtimeInstall':
      E0PatchRuntime.reset();
      final installed = E0PatchRuntime.installBytes(
        patchBytes,
        appId: appId,
        releaseId: releaseId,
        buildFingerprint: buildFingerprint,
        functions: functions,
        signatures: signatures,
        receivers: receivers,
      );
      if (!installed) {
        throw StateError(
          E0PatchRuntime.lastRejection ?? 'Patch install failed',
        );
      }
      checksum = patchBytes.length;
      break;
    case 'fullActivation':
      final verified = await E1SignedPatchEnvelope.verify(
        envelopeBytes: envelopeBytes,
        trustedKeys: <String, E1TrustedPublicKey>{trustedKey.keyId: trustedKey},
      );
      E0PatchRuntime.reset();
      final installed = E0PatchRuntime.installBytes(
        verified.patchBytes,
        appId: appId,
        releaseId: releaseId,
        buildFingerprint: buildFingerprint,
        functions: functions,
        signatures: signatures,
        receivers: receivers,
      );
      if (!installed) {
        throw StateError(
          E0PatchRuntime.lastRejection ?? 'Patch install failed',
        );
      }
      checksum = verified.envelopeBytes.length;
      break;
    default:
      throw FormatException('Unknown activation stage $stage');
  }
  watch.stop();
  print(
    jsonEncode(<String, Object>{
      'stage': stage,
      'elapsedMicros': watch.elapsedMicroseconds,
      'checksum': checksum,
    }),
  );
}

String _argument(List<String> arguments, String prefix) => arguments
    .singleWhere((argument) => argument.startsWith(prefix))
    .substring(prefix.length);

Map<String, int> _intMap(String source) =>
    (jsonDecode(source) as Map<String, Object?>).map(
      (key, value) => MapEntry(key, value! as int),
    );

Map<String, String> _stringMap(String source) =>
    (jsonDecode(source) as Map<String, Object?>).map(
      (key, value) => MapEntry(key, value! as String),
    );
