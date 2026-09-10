import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:hyfens_runtime/runtime.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';

/// Composes the already-compiled E0 programs into one signed Patch Format v1
/// artifact. This is deliberately a small evidence tool: it does not compile
/// source, infer host capabilities, or alter the normative v1 protocol.
///
/// Usage:
///   dart run bin/e1_patch_format_batch.dart MANIFEST SEED KEY_ID OUTPUT E0...
///
/// Every E0 program must belong to the manifest, use a distinct function slot,
/// and carry the same positive patch sequence. The manifest and all E0 bytes
/// are validated before any artifact is written.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 5) {
    stderr.writeln(
      'usage: dart run bin/e1_patch_format_batch.dart '
      'MANIFEST SEED_HEX_FILE KEY_ID OUTPUT E0... ',
    );
    exitCode = 64;
    return;
  }
  final manifestFile = File(arguments[0]);
  final seedFile = File(arguments[1]);
  final keyId = arguments[2];
  final output = File(arguments[3]);
  final e0Files = arguments.skip(4).map(File.new).toList(growable: false);
  if (output.existsSync()) {
    stderr.writeln('refusing to overwrite existing output: ${output.path}');
    exitCode = 73;
    return;
  }

  final manifest = E0ReleaseManifest.decode(await manifestFile.readAsString());
  final functions = <String, int>{
    for (final function in manifest.functions) function.id: function.slot,
  };
  final signatures = <String, E0FunctionSignature>{
    for (final function in manifest.functions) function.id: function.signature,
  };
  final receivers = <String, E0ReceiverDescriptor>{
    for (final function in manifest.functions) function.id: function.receiver,
  };
  final programs = <E0PatchProgram>[];
  final programBytes = <String, List<int>>{};
  for (final file in e0Files) {
    final bytes = await file.readAsBytes();
    final program = E0PatchContainer.decode(
      bytes,
      expectedAppId: manifest.appId,
      expectedReleaseId: manifest.releaseId,
      expectedBuildFingerprint: manifest.buildFingerprint,
      expectedFunctions: functions,
      expectedSignatures: signatures,
      expectedReceivers: receivers,
    );
    if (programBytes.containsKey(program.functionId)) {
      throw FormatException(
        'duplicate function in batch: ${program.functionId}',
      );
    }
    programs.add(program);
    programBytes[program.functionId] = List<int>.unmodifiable(bytes);
  }
  if (programs.length < 2) {
    throw const FormatException(
      'multi-function evidence requires two programs',
    );
  }
  final sequence = programs.first.patchSequence;
  if (sequence <= 0 ||
      programs.any((program) => program.patchSequence != sequence)) {
    throw const FormatException(
      'batch programs must share one positive sequence',
    );
  }

  final entries = <PatchFunctionEntry>[
    for (final program
        in programs
          ..sort((left, right) => left.functionId.compareTo(right.functionId)))
      PatchFunctionEntry(
        id: program.functionId,
        slot: program.slot,
        signatureDigest: _signatureDigest(
          manifest.functions.singleWhere(
            (function) => function.id == program.functionId,
          ),
        ),
      ),
  ];
  final bridge = <String, Object?>{
    'bridgeVersion': 1,
    'encoding': 'e0-patch-container-v9-bytes',
    'functions': <String, Object?>{
      for (final id in programBytes.keys.toList()..sort())
        id: base64.encode(programBytes[id]!),
    },
  };
  final bridgeBytes = utf8.encode(_canonicalJson(bridge));
  final digestInput = <int>[
    for (final program in programs) ...programBytes[program.functionId]!,
  ];
  final patchId = 'sha256:${sha256.convert(digestInput).toString()}';
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: manifest.appId,
    releaseId: manifest.releaseId,
    patchId: patchId,
    sequence: sequence,
    functions: entries,
    capabilities: const <PatchCapabilityEntry>[],
    constants: const <PatchValue>[PatchValue.string('hyfens-e0-bridge-v1')],
    instructions: const <int>[0],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: keyId,
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
    extensions: <PatchExtensionSection>[
      PatchExtensionSection(type: 9, flags: 0, payload: bridgeBytes),
    ],
  );
  final seed = _decodeSeed(await seedFile.readAsString());
  final algorithm = DartEd25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  late final PatchArtifact artifact;
  try {
    artifact = await PatchFormatV1.sealAsync(draft, (bytes) async {
      final signature = await algorithm.sign(bytes, keyPair: keyPair);
      return signature.bytes;
    });
  } finally {
    keyPair.destroy();
  }
  final encoded = PatchFormatV1.encode(artifact);
  // A composer must prove its own output through the same bridge parser used
  // by the controller before it writes an artifact for a device run.
  final decoded = PatchFormatV1.decode(encoded);
  final bridgeFunctions = PatchFormatV1E0Bridge.decode(decoded);
  if (bridgeFunctions.length != programs.length ||
      !_sameKeys(bridgeFunctions.keys, programBytes.keys)) {
    throw StateError(
      'composed bridge does not round-trip: '
      'bridge=${bridgeFunctions.keys.toList()} '
      'programs=${programs.map((program) => program.functionId).toList()} '
      'bytes=${programBytes.keys.toList()}',
    );
  }
  await output.writeAsBytes(encoded, flush: true);
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'artifact': output.path,
      'bytes': encoded.length,
      'applicationId': manifest.appId,
      'releaseId': manifest.releaseId,
      'sequence': sequence,
      'functions': entries
          .map(
            (entry) => <String, Object?>{
              'id': entry.id,
              'slot': entry.slot,
              'signatureDigest': entry.signatureDigest,
            },
          )
          .toList(),
      'patchId': patchId,
      'keyId': keyId,
    }),
  );
}

bool _sameKeys(Iterable<String> left, Iterable<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}

String _signatureDigest(E0FunctionManifest function) =>
    function.signatureDigest.startsWith('sha256:')
    ? function.signatureDigest
    : 'sha256:${function.signatureDigest}';

List<int> _decodeSeed(String source) {
  final value = source.trim();
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
    throw const FormatException('private seed must be exactly 32 hex bytes');
  }
  return <int>[
    for (var offset = 0; offset < value.length; offset += 2)
      int.parse(value.substring(offset, offset + 2), radix: 16),
  ];
}

String _canonicalJson(Object? value) {
  Object? canonical(Object? current) {
    if (current is Map<String, Object?>) {
      final keys = current.keys.toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: canonical(current[key]),
      };
    }
    if (current is List<Object?>) {
      return current.map(canonical).toList(growable: false);
    }
    return current;
  }

  return jsonEncode(canonical(value));
}
