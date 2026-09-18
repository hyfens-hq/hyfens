import 'dart:convert';

import 'package:hyfens_patch_format/patch_format.dart';
import 'package:hyfens_runtime/runtime.dart';
import 'package:test/test.dart';

void main() {
  final contract = PatchCapabilityEntry(
    id: 'http.get',
    version: 1,
    execution: PatchExecutionKind.sync,
    classification: PatchCapabilityClass.network,
    argumentSchema: '["String"]',
    returnSchema: '"String"',
    permissions: const <String>['network'],
  );

  test('freezes the capability authority and validates exact contracts', () {
    final authority = CapabilityAuthority(
      registrations: <CapabilityRegistration>[
        CapabilityRegistration(
          contract: contract,
          handler: (arguments) => 'ok:${arguments.single}',
          argumentsValidator: (value) =>
              value is List<Object?> &&
              value.length == 1 &&
              value.single is String,
          resultValidator: (value) => value is String,
        ),
      ],
    );
    authority.validatePatch(<PatchCapabilityEntry>[contract]);
    authority.validateArtifact(
      PatchArtifact(
        runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
        applicationId: 'app',
        releaseId: 'release',
        patchId: 'patch',
        sequence: 1,
        functions: const <PatchFunctionEntry>[],
        capabilities: <PatchCapabilityEntry>[contract],
        constants: const <PatchValue>[],
        instructions: const <int>[],
        signatureMetadata: PatchSignatureMetadata(
          algorithm: 'ed25519',
          keyId: 'test',
        ),
        payloadDigest: const <int>[],
        signature: const <int>[],
      ),
    );
    expect(authority.invoke(contract, <Object?>['/health']), 'ok:/health');
    expect(
      () => authority.invoke(
        PatchCapabilityEntry(
          id: contract.id,
          version: 2,
          execution: contract.execution,
          classification: contract.classification,
          argumentSchema: contract.argumentSchema,
          returnSchema: contract.returnSchema,
          permissions: contract.permissions,
        ),
        <Object?>['/health'],
      ),
      throwsA(
        isA<RuntimeError>().having((error) => error.code, 'code', 'R1007'),
      ),
    );
  });

  test('policy rejects undeclared, forbidden, and malformed calls', () {
    final authority = CapabilityAuthority(
      policy: CapabilityPolicy(
        allowedClasses: const <PatchCapabilityClass>{PatchCapabilityClass.pure},
      ),
      registrations: <CapabilityRegistration>[
        CapabilityRegistration(contract: contract, handler: (_) => 'no'),
      ],
    );
    expect(
      () => authority.validatePatch(<PatchCapabilityEntry>[contract]),
      throwsA(
        isA<RuntimeError>().having((error) => error.code, 'code', 'R1002'),
      ),
    );
    expect(
      () => authority.invoke(contract, <Object?>[]),
      throwsA(isA<RuntimeError>()),
    );
  });

  test(
    'patch state requires a higher sequence and explicit health confirmation',
    () {
      final state = PatchState();
      state.stage(1);
      expect(state.candidateStaged, isTrue);
      state.confirmHealth(1);
      expect(state.lastKnownGoodSequence, 1);
      expect(() => state.stage(1), throwsA(isA<RuntimeError>()));
      state.stage(2);
      state.discardCandidate();
      expect(state.currentSequence, 1);
    },
  );

  test('decodes the canonical Patch Format v1 E0 bridge', () {
    const functionId = 'function:pricing.calculate';
    final e0Bytes = utf8.encode('{"formatVersion":9}');
    final artifact = PatchArtifact(
      runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
      applicationId: 'app',
      releaseId: 'release',
      patchId: 'patch',
      sequence: 1,
      functions: <PatchFunctionEntry>[
        PatchFunctionEntry(
          id: functionId,
          slot: 0,
          signatureDigest: 'sha256:${'0' * 64}',
        ),
      ],
      capabilities: const <PatchCapabilityEntry>[],
      constants: const <PatchValue>[],
      instructions: const <int>[],
      signatureMetadata: PatchSignatureMetadata(
        algorithm: 'ed25519',
        keyId: 'test',
      ),
      payloadDigest: const <int>[],
      signature: const <int>[],
      extensions: <PatchExtensionSection>[
        PatchExtensionSection(
          type: patchFormatV1E0BridgeExtensionType,
          flags: 0,
          payload: utf8.encode(
            jsonEncode(<String, Object?>{
              'bridgeVersion': PatchFormatV1E0Bridge.version,
              'encoding': PatchFormatV1E0Bridge.encoding,
              'functions': <String, String>{functionId: base64.encode(e0Bytes)},
            }),
          ),
        ),
      ],
    );

    expect(PatchFormatV1E0Bridge.decode(artifact)[functionId], e0Bytes);
  });

  test('rejects bridge tables that do not match the v1 function table', () {
    final artifact = PatchArtifact(
      runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
      applicationId: 'app',
      releaseId: 'release',
      patchId: 'patch',
      sequence: 1,
      functions: <PatchFunctionEntry>[
        PatchFunctionEntry(
          id: 'function:expected',
          slot: 0,
          signatureDigest: 'sha256:${'0' * 64}',
        ),
      ],
      capabilities: const <PatchCapabilityEntry>[],
      constants: const <PatchValue>[],
      instructions: const <int>[],
      signatureMetadata: PatchSignatureMetadata(
        algorithm: 'ed25519',
        keyId: 'test',
      ),
      payloadDigest: const <int>[],
      signature: const <int>[],
      extensions: <PatchExtensionSection>[
        PatchExtensionSection(
          type: patchFormatV1E0BridgeExtensionType,
          flags: 0,
          payload: utf8.encode(
            jsonEncode(<String, Object?>{
              'bridgeVersion': PatchFormatV1E0Bridge.version,
              'encoding': PatchFormatV1E0Bridge.encoding,
              'functions': <String, String>{'function:other': 'eA=='},
            }),
          ),
        ),
      ],
    );

    expect(
      () => PatchFormatV1E0Bridge.decode(artifact),
      throwsA(
        isA<PatchFormatBridgeException>().having(
          (error) => error.code,
          'code',
          'B1006',
        ),
      ),
    );
  });
}
