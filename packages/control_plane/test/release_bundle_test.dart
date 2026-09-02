import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:test/test.dart';

const _bundleKeyId = 'bundle-key';
final _bundleSeed = List<int>.filled(32, 7);

void main() {
  test('signs a canonical bundle and rejects envelope tampering', () async {
    final fixture = await _createReadyFixture();
    addTearDown(() => fixture.directory.delete(recursive: true));

    final verified = await ReleaseBundle.verify(
      bytes: fixture.bundleBytes,
      expectedKeyId: _bundleKeyId,
      expectedPublicKey: fixture.publicKey,
    );
    expect(verified.bundleDigest, fixture.bundleDigest);
    expect(verified.payload.artifactBytes, fixture.patchBytes);
    expect(utf8.decode(fixture.bundleBytes), canonicalJson(verified.toJson()));
    expect(utf8.decode(fixture.bundleBytes), isNot(contains('privateKeySeed')));

    final tampered = Map<String, Object?>.from(
      jsonDecode(utf8.decode(fixture.bundleBytes)) as Map,
    )..['signature'] = base64Encode(List<int>.filled(64, 0));
    await expectLater(
      ReleaseBundle.verify(
        bytes: utf8.encode(canonicalJson(tampered)),
        expectedKeyId: _bundleKeyId,
        expectedPublicKey: fixture.publicKey,
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      ReleaseBundle.verify(
        bytes: <int>[32, ...fixture.bundleBytes],
        expectedKeyId: _bundleKeyId,
        expectedPublicKey: fixture.publicKey,
      ),
      throwsA(isA<FormatException>()),
    );
    final wrongPublicKey = await _publicKey(seed: List<int>.filled(32, 8));
    await expectLater(
      ReleaseBundle.verify(
        bytes: fixture.bundleBytes,
        expectedKeyId: _bundleKeyId,
        expectedPublicKey: wrongPublicKey,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'imports to quarantine, replays idempotently, and admits explicitly',
    () async {
      final source = await _createReadyFixture(prefix: 'bundle-source');
      final target = await _createTargetFixture(
        prefix: 'bundle-target',
        runtimeApplicationId: source.bootstrap.application.runtimeApplicationId,
      );
      addTearDown(() async {
        await source.directory.delete(recursive: true);
        await target.directory.delete(recursive: true);
      });

      final trustedPublicKey = source.publicKey;
      final wrongPublicKey = await _publicKey(seed: List<int>.filled(32, 8));
      await expectLater(
        target.service.importBundle(
          token: target.bootstrap.controlCredential.token,
          organizationId: target.bootstrap.organization.id,
          applicationId: target.bootstrap.application.id,
          environmentId: target.bootstrap.environment.id,
          bytes: source.bundleBytes,
          idempotencyKey: 'bundle-import-wrong-trust',
          trustedKeyId: _bundleKeyId,
          trustedPublicKey: wrongPublicKey,
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'BUNDLE_INVALID',
          ),
        ),
      );
      expect(await target.service.store.listJson('bundle_imports'), isEmpty);

      final imported = await target.service.importBundle(
        token: target.bootstrap.controlCredential.token,
        organizationId: target.bootstrap.organization.id,
        applicationId: target.bootstrap.application.id,
        environmentId: target.bootstrap.environment.id,
        bytes: source.bundleBytes,
        idempotencyKey: 'bundle-import-1',
        trustedKeyId: _bundleKeyId,
        trustedPublicKey: trustedPublicKey,
      );
      expect(imported.patch.state, 'QUARANTINED');
      expect(imported.artifact.state, 'QUARANTINED');
      expect(imported.source.organizationId, source.bootstrap.organization.id);
      expect(imported.release.organizationId, target.bootstrap.organization.id);
      expect(imported.release.id, isNot(source.release.id));
      expect(imported.release.createdAt, source.release.createdAt);
      expect(imported.patch.createdAt, source.patch.createdAt);
      expect(imported.artifact.createdAt, source.artifact.createdAt);

      final importedRows = await target.service.store.listJson(
        'bundle_imports',
      );
      expect(importedRows, hasLength(1));
      final importedRow = importedRows.single;
      final storedPayload = Map<String, Object?>.from(
        importedRow['signedPayload']! as Map,
      );
      expect(storedPayload['exportedAt'], source.exportedAt.toIso8601String());
      expect(
        Map<String, Object?>.from(storedPayload['artifact']! as Map)
            .containsKey('bytes'),
        isFalse,
      );
      expect(importedRow['bundleKeyId'], _bundleKeyId);
      expect(importedRow['bundleSignature'], isA<String>());

      await expectLater(
        target.service.promote(
          token: target.bootstrap.controlCredential.token,
          environmentId: target.bootstrap.environment.id,
          releaseId: imported.release.id,
          expectedVersion: 0,
          idempotencyKey: 'bundle-promote-before-admit',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'RELEASE_NOT_READY',
          ),
        ),
      );

      final replay = await target.service.importBundle(
        token: target.bootstrap.controlCredential.token,
        organizationId: target.bootstrap.organization.id,
        applicationId: target.bootstrap.application.id,
        environmentId: target.bootstrap.environment.id,
        bytes: source.bundleBytes,
        idempotencyKey: 'bundle-import-1',
        trustedKeyId: _bundleKeyId,
        trustedPublicKey: trustedPublicKey,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(replay.release.id, imported.release.id);
      expect(replay.patch.state, 'QUARANTINED');

      await File('${target.directory.path}/patches/${imported.patch.id}.json')
          .delete();
      final recovered = await target.service.importBundle(
        token: target.bootstrap.controlCredential.token,
        organizationId: target.bootstrap.organization.id,
        applicationId: target.bootstrap.application.id,
        environmentId: target.bootstrap.environment.id,
        bytes: source.bundleBytes,
        idempotencyKey: 'bundle-import-recovery',
        trustedKeyId: _bundleKeyId,
        trustedPublicKey: trustedPublicKey,
      );
      expect(recovered.idempotentReplay, isTrue);
      expect(recovered.release.id, imported.release.id);
      expect(recovered.patch.id, imported.patch.id);
      expect(recovered.patch.state, 'QUARANTINED');

      final originalRelease = Map<String, Object?>.from(
        (await target.service.store.readJson('releases', imported.release.id))!,
      );
      await target.service.store.replaceJson(
        'releases',
        imported.release.id,
        Map<String, Object?>.from(originalRelease)
          ..['displayVersion'] = 'tampered',
      );
      await expectLater(
        target.service.admitBundle(
          token: target.bootstrap.controlCredential.token,
          organizationId: target.bootstrap.organization.id,
          applicationId: target.bootstrap.application.id,
          environmentId: target.bootstrap.environment.id,
          releaseId: imported.release.id,
          patchId: imported.patch.id,
          idempotencyKey: 'bundle-admit-tampered-release',
          trustedKeyId: _bundleKeyId,
          trustedPublicKey: trustedPublicKey,
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'BUNDLE_ADMISSION_FAILED',
          ),
        ),
      );
      expect(
        (await target.service.store.readJson(
          'patches',
          imported.patch.id,
        ))!['state'],
        'QUARANTINED',
      );
      expect(
        (await target.service.store.readJson(
          'artifacts',
          imported.artifact.id,
        ))!['state'],
        'QUARANTINED',
      );
      await target.service.store.replaceJson(
        'releases',
        imported.release.id,
        originalRelease,
      );

      final originalImportRow = Map<String, Object?>.from(
        (await target.service.store.readJson(
          'bundle_imports',
          importedRow['id']! as String,
        ))!,
      );
      await target.service.store.replaceJson(
        'bundle_imports',
        importedRow['id']! as String,
        Map<String, Object?>.from(originalImportRow)
          ..['bundleSignature'] = base64Encode(List<int>.filled(64, 0)),
      );
      await expectLater(
        target.service.admitBundle(
          token: target.bootstrap.controlCredential.token,
          organizationId: target.bootstrap.organization.id,
          applicationId: target.bootstrap.application.id,
          environmentId: target.bootstrap.environment.id,
          releaseId: imported.release.id,
          patchId: imported.patch.id,
          idempotencyKey: 'bundle-admit-tampered-metadata',
          trustedKeyId: _bundleKeyId,
          trustedPublicKey: trustedPublicKey,
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'BUNDLE_ADMISSION_FAILED',
          ),
        ),
      );
      await target.service.store.replaceJson(
        'bundle_imports',
        importedRow['id']! as String,
        originalImportRow,
      );

      final partialPatch = Map<String, Object?>.from(
        (await target.service.store.readJson('patches', imported.patch.id))!,
      )..['state'] = 'READY';
      await target.service.store.replaceJson(
        'patches',
        imported.patch.id,
        partialPatch,
      );
      final partialArtifact = await target.service.store.readJson(
        'artifacts',
        imported.artifact.id,
      );
      expect(partialPatch['state'], 'READY');
      expect(partialArtifact!['state'], 'QUARANTINED');
      final partialImport = await target.service.importBundle(
        token: target.bootstrap.controlCredential.token,
        organizationId: target.bootstrap.organization.id,
        applicationId: target.bootstrap.application.id,
        environmentId: target.bootstrap.environment.id,
        bytes: source.bundleBytes,
        idempotencyKey: 'bundle-import-partial-state',
        trustedKeyId: _bundleKeyId,
        trustedPublicKey: trustedPublicKey,
      );
      expect(partialImport.patch.state, 'READY');
      expect(partialImport.artifact.state, 'QUARANTINED');
      expect(partialImport.toJson()['result'], 'QUARANTINED');
      final terminalArtifact = Map<String, Object?>.from(partialArtifact)
        ..['state'] = 'READY';
      await target.service.store.replaceJson(
        'artifacts',
        imported.artifact.id,
        terminalArtifact,
      );
      final terminalReplay = await target.service.importBundle(
        token: target.bootstrap.controlCredential.token,
        organizationId: target.bootstrap.organization.id,
        applicationId: target.bootstrap.application.id,
        environmentId: target.bootstrap.environment.id,
        bytes: source.bundleBytes,
        idempotencyKey: 'bundle-import-terminal-partial',
        trustedKeyId: _bundleKeyId,
        trustedPublicKey: trustedPublicKey,
      );
      expect(terminalReplay.patch.state, 'READY');
      expect(terminalReplay.artifact.state, 'READY');
      expect(terminalReplay.toJson()['result'], 'QUARANTINED');
      expect(terminalReplay.toJson()['importState'], 'QUARANTINED');
      expect(
        (await target.service.store.readJson(
          'bundle_imports',
          importedRow['id']! as String,
        ))!['state'],
        'QUARANTINED',
      );
      await expectLater(
        target.service.promote(
          token: target.bootstrap.controlCredential.token,
          environmentId: target.bootstrap.environment.id,
          releaseId: imported.release.id,
          expectedVersion: 0,
          idempotencyKey: 'bundle-promote-terminal-partial',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'RELEASE_NOT_READY',
          ),
        ),
      );

      final admitted = await target.service.admitBundle(
        token: target.bootstrap.controlCredential.token,
        organizationId: target.bootstrap.organization.id,
        applicationId: target.bootstrap.application.id,
        environmentId: target.bootstrap.environment.id,
        releaseId: imported.release.id,
        patchId: imported.patch.id,
        idempotencyKey: 'bundle-admit-1',
        trustedKeyId: _bundleKeyId,
        trustedPublicKey: trustedPublicKey,
      );
      expect(admitted.patch.state, 'READY');
      expect(admitted.artifact.state, 'READY');
      expect(admitted.importState, 'ADMITTED');
      expect(admitted.toJson()['result'], 'ADMITTED');
      expect(
        admitted.destinationEnvironmentId,
        target.bootstrap.environment.id,
      );
      final environmentBeforePromotion = await target.service.store.readJson(
        'environments',
        target.bootstrap.environment.id,
      );
      expect(environmentBeforePromotion!['promotedReleaseId'], isNull);

      final admittedReplay = await target.service.admitBundle(
        token: target.bootstrap.controlCredential.token,
        organizationId: target.bootstrap.organization.id,
        applicationId: target.bootstrap.application.id,
        environmentId: target.bootstrap.environment.id,
        releaseId: imported.release.id,
        patchId: imported.patch.id,
        idempotencyKey: 'bundle-admit-1',
        trustedKeyId: _bundleKeyId,
        trustedPublicKey: trustedPublicKey,
      );
      expect(admittedReplay.idempotentReplay, isTrue);
      expect(admittedReplay.patch.state, 'READY');

      final promoted = await target.service.promote(
        token: target.bootstrap.controlCredential.token,
        environmentId: target.bootstrap.environment.id,
        releaseId: imported.release.id,
        expectedVersion: 0,
        idempotencyKey: 'bundle-promote-after-admit',
      );
      expect(promoted.promotedReleaseId, imported.release.id);
      expect(promoted.version, 1);

      final importRows = await target.service.store.listJson('bundle_imports');
      expect(importRows, hasLength(1));
      expect(importRows.single['state'], 'ADMITTED');
      expect(importRows.single['releaseId'], imported.release.id);
      final storedSource = Map<String, Object?>.from(
        importRows.single['source']! as Map,
      );
      expect(storedSource['organizationId'], source.bootstrap.organization.id);
      expect(storedSource['releaseId'], source.release.id);
      final audit = await target.service.readAudit(
        token: target.bootstrap.controlCredential.token,
        organizationId: target.bootstrap.organization.id,
      );
      expect(
        audit.map((record) => record.action),
        containsAll(<String>['bundle.import.quarantined', 'bundle.admit']),
      );
    },
  );

  test('HTTP export, import, retry, and admission preserve the boundary', () async {
    final source = await _createReadyFixture(prefix: 'bundle-http-source');
    final target = await _createTargetFixture(
      prefix: 'bundle-http-target',
      runtimeApplicationId: source.bootstrap.application.runtimeApplicationId,
    );
    final sourceAdapter = ControlPlaneHttpServer(source.service);
    final targetAdapter = ControlPlaneHttpServer(target.service);
    final sourceServer = await sourceAdapter.bind();
    final targetServer = await targetAdapter.bind();
    addTearDown(() async {
      await sourceAdapter.close(force: true);
      await targetAdapter.close(force: true);
      await source.directory.delete(recursive: true);
      await target.directory.delete(recursive: true);
    });

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final exportResponse = await _httpRequest(
      client: client,
      method: 'GET',
      uri: Uri.parse(
        'http://127.0.0.1:${sourceServer.port}/v1/organizations/'
        '${source.bootstrap.organization.id}/applications/'
        '${source.bootstrap.application.id}/environments/'
        '${source.bootstrap.environment.id}/releases/${source.release.id}/'
        'patches/${source.patch.id}/bundle',
      ),
      token: source.bootstrap.controlCredential.token,
    );
    expect(exportResponse.statusCode, HttpStatus.ok);
    final exportedPayload = ReleaseBundlePayload.fromJson(
      Map<String, Object?>.from(exportResponse.body)..remove('request_id'),
    );
    expect(exportedPayload.source.releaseId, source.release.id);
    expect(exportedPayload.artifactBytes, source.patchBytes);

    final importUri = Uri.parse(
      'http://127.0.0.1:${targetServer.port}/v1/organizations/'
      '${target.bootstrap.organization.id}/applications/'
      '${target.bootstrap.application.id}/environments/'
      '${target.bootstrap.environment.id}/bundles',
    );
    final importedResponse = await _httpRequest(
      client: client,
      method: 'POST',
      uri: importUri,
      token: target.bootstrap.controlCredential.token,
      idempotencyKey: 'http-bundle-import-1',
      trustedKeyId: _bundleKeyId,
      trustedPublicKey: source.publicKey,
      body: source.bundleBytes,
    );
    expect(importedResponse.statusCode, HttpStatus.created);
    expect(importedResponse.body['result'], 'QUARANTINED');
    final destination = Map<String, Object?>.from(
      importedResponse.body['destination']! as Map,
    );

    final importedReplay = await _httpRequest(
      client: client,
      method: 'POST',
      uri: importUri,
      token: target.bootstrap.controlCredential.token,
      idempotencyKey: 'http-bundle-import-1',
      trustedKeyId: _bundleKeyId,
      trustedPublicKey: source.publicKey,
      body: source.bundleBytes,
    );
    expect(importedReplay.statusCode, HttpStatus.ok);
    expect(importedReplay.body['idempotentReplay'], isTrue);

    final admitResponse = await _httpRequest(
      client: client,
      method: 'POST',
      uri: Uri.parse(
        '$importUri/${destination['releaseId']}/${destination['patchId']}/admit',
      ),
      token: target.bootstrap.controlCredential.token,
      idempotencyKey: 'http-bundle-admit-1',
      trustedKeyId: _bundleKeyId,
      trustedPublicKey: source.publicKey,
    );
    expect(admitResponse.statusCode, HttpStatus.ok);
    expect(admitResponse.body['result'], 'ADMITTED');
    expect(admitResponse.body['patch'], isA<Map>());
    expect((admitResponse.body['patch']! as Map)['state'], 'READY');
  });
}

final class _ReadyFixture {
  const _ReadyFixture({
    required this.directory,
    required this.service,
    required this.bootstrap,
    required this.release,
    required this.patch,
    required this.artifact,
    required this.publicKey,
    required this.patchBytes,
    required this.bundleBytes,
    required this.bundleDigest,
    required this.exportedAt,
  });

  final Directory directory;
  final ControlPlaneService service;
  final BootstrapResult bootstrap;
  final ReleaseRecord release;
  final PatchRecord patch;
  final ArtifactRecord artifact;
  final List<int> publicKey;
  final List<int> patchBytes;
  final List<int> bundleBytes;
  final String bundleDigest;
  final DateTime exportedAt;
}

final class _TargetFixture {
  const _TargetFixture({
    required this.directory,
    required this.service,
    required this.bootstrap,
  });

  final Directory directory;
  final ControlPlaneService service;
  final BootstrapResult bootstrap;
}

Future<_ReadyFixture> _createReadyFixture({
  String prefix = 'bundle',
  String runtimeApplicationId = 'com.example.bundle',
}) async {
  final directory = await Directory.systemTemp.createTemp('hyfens-$prefix-');
  final service = ControlPlaneService(
    store: FileControlPlaneStore(directory),
    random: Random(7),
  );
  final bootstrap = await service.bootstrap(
    organizationName: '$prefix organization',
    runtimeApplicationId: runtimeApplicationId,
    platformId: 'android-arm64-release',
    environmentName: 'development',
  );
  final publicKey = await _publicKey();
  final patchBytes = await _patchBytes(
    applicationId: runtimeApplicationId,
    releaseId: 'release-runtime-90',
    patchId: 'patch-runtime-90',
  );
  final release = await service.registerRelease(
    token: bootstrap.controlCredential.token,
    idempotencyKey: '$prefix-release',
    spec: ReleaseSpec(
      applicationId: bootstrap.application.id,
      platformId: 'plt_android',
      runtimeApplicationId: runtimeApplicationId,
      runtimeReleaseId: 'release-runtime-90',
      buildTarget: 'android-arm64-release',
      runtimeCompatibilityVersion: 1,
      patchFormatVersion: patchFormatV1,
      buildFingerprint: _digest('bundle-build'),
      capabilityAuthorityDigest: _digest('bundle-capabilities'),
      functionSignatureDigest: _digest('bundle-functions'),
      displayVersion: '0.90.0',
      signingPublicKeys: <String, String>{
        _bundleKeyId: base64Encode(publicKey),
      },
    ),
  );
  final patch = await service.registerPatch(
    token: bootstrap.controlCredential.token,
    releaseId: release.id,
    idempotencyKey: '$prefix-patch',
    spec: PatchSpec(
      runtimePatchId: 'patch-runtime-90',
      sequence: 1,
      artifactId: 'art_bundle_source_90',
      sha256: sha256Digest(patchBytes),
      sizeBytes: patchBytes.length,
      signatureKeyId: _bundleKeyId,
    ),
  );
  await service.uploadArtifact(
    token: bootstrap.controlCredential.token,
    artifactId: patch.artifactId,
    bytes: patchBytes,
    idempotencyKey: '$prefix-artifact',
  );
  final payload = await service.exportBundle(
    token: bootstrap.controlCredential.token,
    organizationId: bootstrap.organization.id,
    applicationId: bootstrap.application.id,
    environmentId: bootstrap.environment.id,
    releaseId: release.id,
    patchId: patch.id,
  );
  final bundleBytes = await ReleaseBundle.sign(
    payload: payload,
    keyId: _bundleKeyId,
    privateKeySeed: _bundleSeed,
  );
  final bundleDigest = (await ReleaseBundle.verify(
    bytes: bundleBytes,
    expectedKeyId: _bundleKeyId,
    expectedPublicKey: publicKey,
  )).bundleDigest;
  return _ReadyFixture(
    directory: directory,
    service: service,
    bootstrap: bootstrap,
    release: release,
    patch: patch,
    artifact: payload.artifact,
    publicKey: publicKey,
    patchBytes: patchBytes,
    bundleBytes: bundleBytes,
    bundleDigest: bundleDigest,
    exportedAt: payload.exportedAt,
  );
}

Future<_TargetFixture> _createTargetFixture({
  required String prefix,
  required String runtimeApplicationId,
}) async {
  final directory = await Directory.systemTemp.createTemp('hyfens-$prefix-');
  final service = ControlPlaneService(
    store: FileControlPlaneStore(directory),
    random: Random(11),
  );
  final bootstrap = await service.bootstrap(
    organizationName: '$prefix organization',
    runtimeApplicationId: runtimeApplicationId,
    platformId: 'android-arm64-release',
    environmentName: 'development',
  );
  return _TargetFixture(
    directory: directory,
    service: service,
    bootstrap: bootstrap,
  );
}

Future<List<int>> _publicKey({List<int>? seed}) async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(seed ?? _bundleSeed);
  try {
    return (await keyPair.extractPublicKey()).bytes;
  } finally {
    keyPair.destroy();
  }
}

Future<List<int>> _patchBytes({
  required String applicationId,
  required String releaseId,
  required String patchId,
}) async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(_bundleSeed);
  try {
    final artifact = await PatchFormatV1.sealAsync(
      PatchArtifact(
        runtimeCompatibilityVersion: 1,
        applicationId: applicationId,
        releaseId: releaseId,
        patchId: patchId,
        sequence: 1,
        functions: <PatchFunctionEntry>[
          PatchFunctionEntry(
            id: 'lib:bundle#calculate',
            slot: 0,
            signatureDigest: _digest('bundle-signature'),
          ),
        ],
        capabilities: const <PatchCapabilityEntry>[],
        constants: const <PatchValue>[],
        instructions: const <int>[0],
        signatureMetadata: PatchSignatureMetadata(
          algorithm: ReleaseBundle.algorithmName,
          keyId: _bundleKeyId,
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

String _digest(String value) => sha256Digest(utf8.encode(value));

final class _HttpResult {
  const _HttpResult({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, Object?> body;
}

Future<_HttpResult> _httpRequest({
  required HttpClient client,
  required String method,
  required Uri uri,
  required String token,
  String? idempotencyKey,
  String? trustedKeyId,
  List<int>? trustedPublicKey,
  List<int>? body,
}) async {
  final request = await client.openUrl(method, uri);
  request.headers.set('Authorization', 'Bearer $token');
  if (idempotencyKey != null) {
    request.headers.set('Idempotency-Key', idempotencyKey);
  }
  if (trustedKeyId != null) {
    request.headers
      ..set(ReleaseBundle.trustedKeyIdHeader, trustedKeyId)
      ..set(
        ReleaseBundle.trustedPublicKeyHeader,
        base64Encode(trustedPublicKey!),
      );
  }
  if (body != null) {
    request
      ..headers.contentType = ContentType.json
      ..headers.contentLength = body.length;
    request.add(body);
  }
  final response = await request.close();
  final bytes = await response.fold<List<int>>(
    <int>[],
    (all, chunk) => all..addAll(chunk),
  );
  final decoded = jsonDecode(utf8.decode(bytes)) as Map;
  return _HttpResult(
    statusCode: response.statusCode,
    body: Map<String, Object?>.from(decoded),
  );
}
