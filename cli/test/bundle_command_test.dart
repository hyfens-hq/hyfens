import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:hyfens_control_plane/control_plane.dart' as cp;
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

void main() {
  test('bundle commands verify locally and use the authenticated remote contract', () async {
    final project = await _createProject();
    addTearDown(() => project.delete(recursive: true));
    final toolchain = HyfensToolchain();
    final flutterProject = toolchain.project(projectPath: project.path);
    final store = ToolStore(flutterProject);
    await store.ensure();
    final signingKey = await const KeyStore().generate(
      privateFile: File('${store.keys.path}/private.key'),
      publicFile: File('${store.keys.path}/public.key'),
      random: Random(90),
    );
    final payload = await _createPayload(
      keyId: signingKey.keyId,
      seed: signingKey.seed,
      publicKey: signingKey.publicKey,
    );
    final signedBytes = await cp.ReleaseBundle.sign(
      payload: payload,
      keyId: signingKey.keyId,
      privateKeySeed: signingKey.seed,
    );
    final bundleDigest = (await cp.ReleaseBundle.verify(
      bytes: signedBytes,
      expectedKeyId: signingKey.keyId,
      expectedPublicKey: signingKey.publicKey,
    )).bundleDigest;
    final output = File('${project.path}/release.bundle.json');
    final publicKeyPath = '${store.keys.path}/public.key';

    final server = await HttpServer.bind('127.0.0.1', 0);
    final paths = <String>[];
    final authorizationHeaders = <String?>[];
    final idempotencyKeys = <String?>[];
    final trustedKeyIds = <String?>[];
    final trustedPublicKeys = <String?>[];
    List<int>? importedBytes;
    final subscription = server.listen((request) async {
      paths.add(request.uri.path);
      authorizationHeaders.add(request.headers.value('authorization'));
      idempotencyKeys.add(request.headers.value('idempotency-key'));
      trustedKeyIds.add(
        request.headers.value(cp.ReleaseBundle.trustedKeyIdHeader),
      );
      trustedPublicKeys.add(
        request.headers.value(cp.ReleaseBundle.trustedPublicKeyHeader),
      );
      Map<String, Object?> responseBody;
      if (request.method == 'GET' && request.uri.path.endsWith('/bundle')) {
        responseBody = payload.toJson();
      } else if (request.method == 'POST' &&
          request.uri.path.endsWith('/bundles')) {
        importedBytes = await request.fold<List<int>>(
          <int>[],
          (all, chunk) => all..addAll(chunk),
        );
        responseBody = <String, Object?>{
          'result': 'QUARANTINED',
          'idempotentReplay': false,
          'bundleDigest': bundleDigest,
          'destination': <String, Object?>{
            'organizationId': 'org_destination_90',
            'applicationId': 'app_destination_90',
            'environmentId': 'env_destination_90',
            'releaseId': 'rel_destination_90',
            'patchId': 'pat_destination_90',
            'artifactId': 'art_destination_90',
          },
        };
      } else if (request.method == 'POST' &&
          request.uri.path.endsWith('/admit')) {
        responseBody = <String, Object?>{
          'result': 'ADMITTED',
          'idempotentReplay': false,
          'bundleDigest': bundleDigest,
          'destination': <String, Object?>{
            'organizationId': 'org_destination_90',
            'applicationId': 'app_destination_90',
            'environmentId': 'env_destination_90',
            'releaseId': 'rel_destination_90',
            'patchId': 'pat_destination_90',
            'artifactId': 'art_destination_90',
          },
        };
      } else {
        request.response.statusCode = HttpStatus.notFound;
        responseBody = <String, Object?>{'error': 'unexpected request'};
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(responseBody));
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final endpoint = 'http://127.0.0.1:${server.port}';
    final export = await _runTool(<String>[
      'bundle',
      'export',
      '--project',
      project.path,
      '--endpoint',
      endpoint,
      '--token',
      'control-token-90',
      '--organization-id',
      'org_source_90',
      '--application-id',
      'app_source_90',
      '--environment-id',
      'env_source_90',
      '--release-id',
      'rel_source_90',
      '--patch-id',
      'pat_source_90',
      '--output',
      output.path,
      '--json',
    ]);
    _expectSuccess(export, 'EXPORTED');
    expect(await output.readAsBytes(), signedBytes);

    final verify = await _runTool(<String>[
      'bundle',
      'verify',
      output.path,
      '--trusted-public-key',
      publicKeyPath,
      '--json',
    ]);
    _expectSuccess(verify, 'VERIFIED');

    final imported = await _runTool(<String>[
      'bundle',
      'import',
      output.path,
      '--endpoint',
      endpoint,
      '--token',
      'control-token-90',
      '--organization-id',
      'org_destination_90',
      '--application-id',
      'app_destination_90',
      '--environment-id',
      'env_destination_90',
      '--idempotency-key',
      'bundle-import-90',
      '--trusted-public-key',
      publicKeyPath,
      '--json',
    ]);
    _expectSuccess(imported, 'QUARANTINED');

    final admitted = await _runTool(<String>[
      'bundle',
      'admit',
      '--endpoint',
      endpoint,
      '--token',
      'control-token-90',
      '--organization-id',
      'org_destination_90',
      '--application-id',
      'app_destination_90',
      '--environment-id',
      'env_destination_90',
      '--release-id',
      'rel_destination_90',
      '--patch-id',
      'pat_destination_90',
      '--idempotency-key',
      'bundle-admit-90',
      '--trusted-public-key',
      publicKeyPath,
      '--json',
    ]);
    _expectSuccess(admitted, 'ADMITTED');

    expect(
      paths,
      containsAll(<String>[
        '/v1/organizations/org_source_90/applications/app_source_90/'
            'environments/env_source_90/releases/rel_source_90/'
            'patches/pat_source_90/bundle',
        '/v1/organizations/org_destination_90/applications/app_destination_90/'
            'environments/env_destination_90/bundles',
        '/v1/organizations/org_destination_90/applications/app_destination_90/'
            'environments/env_destination_90/bundles/'
            'rel_destination_90/pat_destination_90/admit',
      ]),
    );
    expect(authorizationHeaders, everyElement('Bearer control-token-90'));
    expect(
      idempotencyKeys,
      containsAll(<String>['bundle-import-90', 'bundle-admit-90']),
    );
    expect(trustedKeyIds, <String?>[null, signingKey.keyId, signingKey.keyId]);
    expect(trustedPublicKeys, <String?>[
      null,
      base64Encode(signingKey.publicKey),
      base64Encode(signingKey.publicKey),
    ]);
    expect(importedBytes, signedBytes);

    final commands = HyfensCommandRunner().commands;
    expect(commands.keys, containsAll(<String>['bundle', 'deploy', 'rollout']));
  });
}

void _expectSuccess(_CommandResult result, String expectedResult) {
  final output = jsonDecode(result.stdout) as Map;
  expect(output['result'], expectedResult);
}

final class _CommandResult {
  const _CommandResult({required this.stdout, required this.stderr});

  final String stdout;
  final String stderr;
}

Future<_CommandResult> _runTool(List<String> arguments) async {
  final outputDirectory = await Directory.systemTemp.createTemp(
    'hyfens-cli-bundle-output-',
  );
  final stdoutFile = File('${outputDirectory.path}/stdout');
  final stderrFile = File('${outputDirectory.path}/stderr');
  final stdout = stdoutFile.openWrite();
  final stderr = stderrFile.openWrite();
  try {
    await HyfensCommandRunner(out: stdout, err: stderr).run(arguments);
  } finally {
    await stdout.close();
    await stderr.close();
  }
  try {
    return _CommandResult(
      stdout: await stdoutFile.readAsString(),
      stderr: await stderrFile.readAsString(),
    );
  } finally {
    await outputDirectory.delete(recursive: true);
  }
}

Future<Directory> _createProject() async {
  final project = await Directory.systemTemp.createTemp('hyfens-cli-bundle-');
  await Directory('${project.path}/lib').create(recursive: true);
  await File('${project.path}/pubspec.yaml').writeAsString('''
name: bundle_cli_test
version: 1.0.0
environment:
  sdk: ^3.13.0
flutter: {}
''');
  await writeDefaultConfig(
    File('${project.path}/tool.yaml'),
    applicationId: 'com.example.bundle.cli',
  );
  return project;
}

Future<cp.ReleaseBundlePayload> _createPayload({
  required String keyId,
  required List<int> seed,
  required List<int> publicKey,
}) async {
  final patchBytes = await _patchBytes(keyId: keyId, seed: seed);
  final release = cp.ReleaseRecord(
    id: 'rel_source_90',
    organizationId: 'org_source_90',
    applicationId: 'app_source_90',
    platformId: 'plt_android',
    runtimeApplicationId: 'com.example.bundle.cli',
    runtimeReleaseId: 'runtime-release-90',
    buildTarget: 'android-arm64-release',
    runtimeCompatibilityVersion: 1,
    patchFormatVersion: patchFormatV1,
    buildFingerprint: cp.sha256Digest(utf8.encode('build-90')),
    capabilityAuthorityDigest: cp.sha256Digest(utf8.encode('capabilities-90')),
    functionSignatureDigest: cp.sha256Digest(utf8.encode('functions-90')),
    displayVersion: '0.90.0',
    signingPublicKeys: <String, String>{keyId: base64Encode(publicKey)},
    createdAt: DateTime.utc(2026, 8, 28),
  );
  final patch = cp.PatchRecord(
    id: 'pat_source_90',
    organizationId: 'org_source_90',
    releaseId: release.id,
    runtimePatchId: 'runtime-patch-90',
    sequence: 1,
    artifactId: 'art_source_90',
    sha256: cp.sha256Digest(patchBytes),
    sizeBytes: patchBytes.length,
    signatureKeyId: keyId,
    state: 'READY',
    createdAt: DateTime.utc(2026, 8, 28),
  );
  final artifact = cp.ArtifactRecord(
    id: 'art_source_90',
    organizationId: 'org_source_90',
    patchId: patch.id,
    sha256: patch.sha256,
    sizeBytes: patchBytes.length,
    contentType: 'application/octet-stream',
    state: 'READY',
    createdAt: DateTime.utc(2026, 8, 28),
  );
  return cp.ReleaseBundlePayload(
    source: cp.ReleaseBundleSource(
      organizationId: 'org_source_90',
      applicationId: 'app_source_90',
      environmentId: 'env_source_90',
      releaseId: release.id,
      patchId: patch.id,
      artifactId: artifact.id,
    ),
    exportedAt: DateTime.utc(2026, 8, 28),
    release: release,
    patch: patch,
    artifact: artifact,
    artifactBytes: patchBytes,
  );
}

Future<List<int>> _patchBytes({
  required String keyId,
  required List<int> seed,
}) async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(seed);
  try {
    final artifact = await PatchFormatV1.sealAsync(
      PatchArtifact(
        runtimeCompatibilityVersion: 1,
        applicationId: 'com.example.bundle.cli',
        releaseId: 'runtime-release-90',
        patchId: 'runtime-patch-90',
        sequence: 1,
        functions: <PatchFunctionEntry>[
          PatchFunctionEntry(
            id: 'lib:bundle#calculate',
            slot: 0,
            signatureDigest: cp.sha256Digest(utf8.encode('signature-90')),
          ),
        ],
        capabilities: const <PatchCapabilityEntry>[],
        constants: const <PatchValue>[],
        instructions: const <int>[0],
        signatureMetadata: PatchSignatureMetadata(
          algorithm: cp.ReleaseBundle.algorithmName,
          keyId: keyId,
        ),
        payloadDigest: const <int>[],
        signature: const <int>[],
      ),
      (message) async {
        final signature = await DartEd25519().sign(message, keyPair: keyPair);
        return signature.bytes;
      },
    );
    return PatchFormatV1.encode(artifact);
  } finally {
    keyPair.destroy();
  }
}
