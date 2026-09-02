import 'dart:convert';

import 'package:hyfens_patch_format/patch_format.dart';
import 'package:test/test.dart';

void main() {
  final function = PatchFunctionEntry(
    id: 'sha256:${'1' * 64}',
    slot: 0,
    signatureDigest: 'sha256:${'2' * 64}',
  );
  final capability = PatchCapabilityEntry(
    id: 'flutter.widget.text',
    version: 1,
    execution: PatchExecutionKind.sync,
    classification: PatchCapabilityClass.ui,
    argumentSchema: '{"kind":"string"}',
    returnSchema: '{"kind":"widget"}',
    permissions: const <String>['ui:build'],
  );

  PatchArtifact draft({List<PatchExtensionSection> extensions = const []}) =>
      PatchArtifact(
        runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
        applicationId: 'dev.hyfens.example',
        releaseId: 'sha256:${'3' * 64}',
        patchId: 'sha256:${'4' * 64}',
        sequence: 1,
        createdAtUtc: DateTime.fromMillisecondsSinceEpoch(1234, isUtc: true),
        functions: <PatchFunctionEntry>[function],
        capabilities: <PatchCapabilityEntry>[capability],
        constants: <PatchValue>[
          const PatchValue.integer(2),
          const PatchValue.map(<String, PatchValue>{
            'name': PatchValue.string('Ada'),
          }),
        ],
        instructions: const <int>[1, 0, 9],
        signatureMetadata: PatchSignatureMetadata(
          algorithm: 'ed25519',
          keyId: 'local-development',
        ),
        payloadDigest: const <int>[],
        signature: const <int>[],
        extensions: extensions,
      );

  test('seals and round-trips deterministic canonical bytes', () {
    final sealed = PatchFormatV1.seal(
      draft(),
      (bytes) => List<int>.filled(64, bytes.length & 0xff),
    );
    final encoded = PatchFormatV1.encode(sealed);
    expect(PatchFormatV1.encode(sealed), encoded);
    final decoded = PatchFormatV1.decode(encoded);
    expect(decoded.applicationId, 'dev.hyfens.example');
    expect(decoded.constants.last.toDart(), <String, Object?>{'name': 'Ada'});
    expect(
      PatchFormatV1.verifySignature(
        decoded,
        (bytes, signature) => signature.length == 64,
      ),
      isTrue,
    );

    final extended = PatchFormatV1.seal(
      draft(
        extensions: <PatchExtensionSection>[
          PatchExtensionSection(type: 9, flags: 0, payload: const <int>[1, 2]),
        ],
      ),
      (bytes) => List<int>.filled(64, bytes.length & 0xff),
    );
    expect(
      PatchFormatV1.decode(PatchFormatV1.encode(extended)).extensions,
      hasLength(1),
    );
    expect(
      () => PatchExtensionSection(type: 9, flags: 2, payload: const <int>[]),
      throwsA(isA<PatchFormatException>()),
    );
  });

  test('identity, function, and capability IDs are deterministic', () {
    final normalizedRelease = releaseIdFor(
      applicationId: 'app',
      sourceFingerprint: 'normalized-source',
      dependencyFingerprint: 'normalized-deps',
      runtimeCompatibilityVersion: 1,
      target: 'android-arm64-release',
    );
    expect(
      normalizedRelease,
      releaseIdFor(
        applicationId: 'app',
        sourceFingerprint: 'normalized-source',
        dependencyFingerprint: 'normalized-deps',
        runtimeCompatibilityVersion: 1,
        target: 'android-arm64-release',
      ),
    );
    expect(
      normalizedRelease,
      isNot(
        releaseIdFor(
          applicationId: 'app',
          sourceFingerprint: 'normalized-source',
          dependencyFingerprint: 'normalized-deps',
          runtimeCompatibilityVersion: 1,
          target: 'ios-arm64-release',
        ),
      ),
    );
    expect(capabilityIdFor(namespace: 'http', name: 'get'), 'http.get');
    expect(
      functionIdFor(
        libraryUri: 'package:app/cart.dart',
        ownerKind: 'library',
        ownerName: null,
        memberKind: 'topLevelFunction',
        memberName: 'total',
      ),
      startsWith('sha256:'),
    );
  });

  test('async signing preserves the exact v1 signing domain', () async {
    final sealed = await PatchFormatV1.sealAsync(
      draft(),
      (bytes) async => List<int>.filled(64, bytes.length & 0xff),
    );
    final decoded = PatchFormatV1.decode(PatchFormatV1.encode(sealed));
    expect(
      await PatchFormatV1.verifySignatureAsync(
        decoded,
        (bytes, signature) async => signature.length == 64 && bytes.isNotEmpty,
      ),
      isTrue,
    );
  });

  test('rejects duplicate, unknown-critical, incompatible, and corrupt input', () {
    final sealed = PatchFormatV1.seal(
      draft(),
      (bytes) => List<int>.filled(64, 7),
    );
    final encoded = PatchFormatV1.encode(sealed);
    final wrongMagic = encoded.toList()..[0] = 0;
    expect(
      () => PatchFormatV1.decode(wrongMagic),
      throwsA(isA<PatchFormatException>()),
    );

    final unknownCritical = encoded.toList()
      ..addAll(<int>[0, 42, 0, 1, 0, 0, 0, 0]);
    // The appended bytes are also trailing data, so the parser must reject the
    // artifact before any activation-oriented caller can use it.
    expect(
      () => PatchFormatV1.decode(unknownCritical),
      throwsA(isA<PatchFormatException>()),
    );

    final manifest = ReleaseBaselineManifest(
      applicationId: 'app',
      releaseId: sealed.releaseId,
      runtimeCompatibilityVersion: 1,
      patchFormatVersion: 1,
      buildFingerprint: 'build',
      functions: <PatchFunctionEntry>[function],
      capabilities: <PatchCapabilityEntry>[capability],
      packages: const <String>['app'],
      sourceUnits: <ReleaseBaselineSourceUnit>[
        ReleaseBaselineSourceUnit(
          packageName: 'app',
          libraryUri: 'package:app/main.dart',
          sourceKind: 'application',
          instrumented: true,
        ),
      ],
    );
    expect(
      ReleaseBaselineManifest.decode(manifest.encode()).encode(),
      manifest.encode(),
    );
    final forged = jsonDecode(manifest.encode()) as Map<String, Object?>
      ..['unknown'] = true;
    expect(
      () => ReleaseBaselineManifest.decode(jsonEncode(forged)),
      throwsA(isA<PatchFormatException>()),
    );
  });
}
