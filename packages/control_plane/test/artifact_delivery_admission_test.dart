import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late ControlPlaneService baseService;
  late BootstrapResult bootstrap;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-artifact-admission-',
    );
    baseService = ControlPlaneService(store: FileControlPlaneStore(directory));
    bootstrap = await baseService.bootstrap(
      organizationName: 'Artifact admission test',
      runtimeApplicationId: 'com.example.admission',
      platformId: 'platform_android',
      environmentName: 'development',
    );
  });

  tearDown(() => directory.delete(recursive: true));

  test('denies before reading artifact bytes and keeps context server-owned', () async {
    final ready = await _readyArtifact(baseService, bootstrap, 'deny');
    final artifactFile = File(
      '${directory.path}/artifacts/${ready.artifact.sha256.substring(7)}/bytes',
    );
    expect(await artifactFile.exists(), isTrue);
    await artifactFile.delete();

    final admission = _RecordingAdmission(allow: false);
    final gated = ControlPlaneService(
      store: baseService.store,
      artifactDeliveryAdmission: admission,
      artifactDeliveryAdmissionRequired: true,
    );

    await expectLater(
      gated.fetchArtifact(
        token: bootstrap.deliveryCredential.token,
        artifactId: ready.artifact.id,
        applicationId: bootstrap.application.id,
        environmentId: bootstrap.environment.id,
        admissionId: 'admission-deny',
        downloadProof: 'opaque-proof',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'ARTIFACT_ADMISSION_DENIED',
        ),
      ),
    );
    expect(admission.context?.toJson(), <String, Object?>{
      'organization_id': bootstrap.organization.id,
      'application_id': bootstrap.application.id,
      'environment_id': bootstrap.environment.id,
      'runtime_application_id': 'com.example.admission',
      'platform': 'platform_android',
      'release_id': 'admission-release-deny',
      'patch_id': 'admission-patch-deny',
      'artifact_digest': ready.artifact.sha256.substring(7),
      'artifact_id': ready.artifact.id,
    });
    expect(admission.admissionId, 'admission-deny');
    expect(admission.downloadProof, 'opaque-proof');
  });

  test('allows exact bytes through the service admission seam', () async {
    final ready = await _readyArtifact(baseService, bootstrap, 'allow');
    final admission = _RecordingAdmission(allow: true);
    final gated = ControlPlaneService(
      store: baseService.store,
      artifactDeliveryAdmission: admission,
      artifactDeliveryAdmissionRequired: true,
    );

    final fetched = await gated.fetchArtifact(
      token: bootstrap.deliveryCredential.token,
      artifactId: ready.artifact.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      admissionId: 'admission-allow',
      downloadProof: 'opaque-proof',
    );
    expect(fetched.bytes, ready.bytes);
    expect(fetched.record.sha256, ready.artifact.sha256);
  });

  test('does not invoke admission before delivery authorization', () async {
    final ready = await _readyArtifact(baseService, bootstrap, 'auth');
    final admission = _RecordingAdmission(allow: true);
    final gated = ControlPlaneService(
      store: baseService.store,
      artifactDeliveryAdmission: admission,
      artifactDeliveryAdmissionRequired: true,
    );

    await expectLater(
      gated.fetchArtifact(
        token: 'invalid-delivery-token',
        artifactId: ready.artifact.id,
        applicationId: bootstrap.application.id,
        environmentId: bootstrap.environment.id,
      ),
      throwsA(isA<ControlPlaneException>()),
    );
    expect(admission.context, isNull);
  });

  test('HTTP artifact route forwards only admission headers', () async {
    final ready = await _readyArtifact(baseService, bootstrap, 'http');
    final admission = _RecordingAdmission(allow: true);
    final gated = ControlPlaneService(
      store: baseService.store,
      artifactDeliveryAdmission: admission,
      artifactDeliveryAdmissionRequired: true,
    );
    final adapter = ControlPlaneHttpServer(gated);
    final server = await adapter.bind();
    addTearDown(() => adapter.close(force: true));

    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: server.port,
          path: '/v1/runtime/artifacts/${ready.artifact.id}',
          queryParameters: <String, String>{
            'application_id': bootstrap.application.id,
            'environment_id': bootstrap.environment.id,
          },
        ),
      );
      request.headers
        ..set(
          HttpHeaders.authorizationHeader,
          'Bearer ${bootstrap.deliveryCredential.token}',
        )
        ..set(artifactAdmissionIdHeader, 'admission-http')
        ..set(artifactDownloadProofHeader, 'opaque-http-proof');
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (result, chunk) => result..addAll(chunk),
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(bytes, ready.bytes);
      expect(admission.admissionId, 'admission-http');
      expect(admission.downloadProof, 'opaque-http-proof');
      expect(admission.context?.applicationId, bootstrap.application.id);
      expect(admission.context?.environmentId, bootstrap.environment.id);
      expect(admission.context?.platform, 'platform_android');
      expect(admission.context?.runtimeReleaseId, 'admission-release-http');
      expect(admission.context?.runtimePatchId, 'admission-patch-http');
      expect(
        admission.context?.artifactDigest,
        ready.artifact.sha256.substring(7),
      );
      expect(admission.context?.artifactId, ready.artifact.id);
    } finally {
      client.close(force: true);
    }
  });

  test('remote adapter sends the frozen validator request', () async {
    final token = List<String>.filled(32, 'a').join();
    final validator = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late String? path;
    late String? authorization;
    late Map<String, Object?> requestBody;
    validator.listen((request) async {
      path = request.uri.path;
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      requestBody = jsonDecode(
        await utf8.decoder.bind(request.cast<List<int>>()).join(),
      ) as Map<String, Object?>;
      final body = utf8.encode(
        jsonEncode(<String, Object?>{
          'allowed': true,
          'admission_id': requestBody['admission_id'],
          'artifact_id': requestBody['artifact_id'],
        }),
      );
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..contentLength = body.length
        ..add(body);
      await request.response.close();
    });
    addTearDown(() => validator.close(force: true));

    final remote = RemoteArtifactDeliveryAdmission(
      endpoint: Uri.parse(
        'http://127.0.0.1:${validator.port}/internal/runtime/artifact-admission',
      ),
      serviceToken: token,
    );
    final context = ArtifactDeliveryAdmissionContext(
      organizationId: 'org_admission',
      applicationId: 'app_admission',
      environmentId: 'env_admission',
      runtimeApplicationId: 'com.example.admission',
      platform: 'platform_android',
      runtimeReleaseId: 'release-runtime',
      runtimePatchId: 'patch-runtime',
      artifactDigest: 'sha256:${List<String>.filled(64, 'b').join()}',
      artifactId: 'artifact_admission',
    );
    await remote.authorize(
      context,
      admissionId: 'admission-remote',
      downloadProof: 'raw-proof-forwarded-unchanged',
    );

    expect(path, '/internal/runtime/artifact-admission');
    expect(authorization, 'Bearer $token');
    expect(requestBody, <String, Object?>{
      ...context.toJson(),
      'admission_id': 'admission-remote',
      'signature': 'raw-proof-forwarded-unchanged',
    });
  });

  test('remote denial and outage fail closed without exposing service auth', () async {
    final token = List<String>.filled(32, 'b').join();
    final validator = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    validator.listen((request) async {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
    });
    final remote = RemoteArtifactDeliveryAdmission(
      endpoint: Uri.parse(
        'http://127.0.0.1:${validator.port}/internal/runtime/artifact-admission',
      ),
      serviceToken: token,
    );
    final context = _context();
    await expectLater(
      remote.authorize(context),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.statusCode,
          'statusCode',
          HttpStatus.forbidden,
        ),
      ),
    );
    await validator.close(force: true);
    final error = await _captureError(() => remote.authorize(context));
    expect(error.statusCode, HttpStatus.serviceUnavailable);
    expect(error.toString(), isNot(contains(token)));
  });

  test('remote endpoint validation does not echo credential-bearing URI', () {
    const endpointText =
        'https://user:query-secret@example.invalid/internal/runtime/'
        'artifact-admission?token=uri-secret';
    try {
      RemoteArtifactDeliveryAdmission(
        endpoint: Uri.parse(endpointText),
        serviceToken: List<String>.filled(32, 'c').join(),
      );
      fail('expected endpoint validation failure');
    } on ArgumentError catch (error) {
      expect(error.toString(), isNot(contains(endpointText)));
      expect(error.toString(), isNot(contains('query-secret')));
      expect(error.toString(), isNot(contains('uri-secret')));
    }
  });

  test('required admission cannot be composed without a provider', () {
    expect(
      () => ControlPlaneService(
        store: baseService.store,
        artifactDeliveryAdmissionRequired: true,
      ),
      throwsArgumentError,
    );
  });
}

ArtifactDeliveryAdmissionContext _context() => ArtifactDeliveryAdmissionContext(
  organizationId: 'org_admission',
  applicationId: 'app_admission',
  environmentId: 'env_admission',
  runtimeApplicationId: 'com.example.admission',
  platform: 'platform_android',
  runtimeReleaseId: 'release-runtime',
  runtimePatchId: 'patch-runtime',
  artifactDigest: List<String>.filled(64, 'c').join(),
  artifactId: 'artifact_admission',
);

Future<_ReadyArtifact> _readyArtifact(
  ControlPlaneService service,
  BootstrapResult bootstrap,
  String suffix,
) async {
  final runtimeReleaseId = 'admission-release-$suffix';
  final runtimePatchId = 'admission-patch-$suffix';
  final bytes = await _patchBytes(
    releaseId: runtimeReleaseId,
    patchId: runtimePatchId,
  );
  final publicKey = await _publicKey();
  final release = await service.registerRelease(
    token: bootstrap.controlCredential.token,
    idempotencyKey: 'admission-release-$suffix',
    spec: ReleaseSpec(
      applicationId: bootstrap.application.id,
      platformId: 'platform_android',
      runtimeApplicationId: 'com.example.admission',
      runtimeReleaseId: runtimeReleaseId,
      buildTarget: 'android-arm64-release',
      runtimeCompatibilityVersion: 1,
      patchFormatVersion: 1,
      buildFingerprint: _digest('build-$suffix'),
      capabilityAuthorityDigest: _digest('capability-$suffix'),
      functionSignatureDigest: _digest('functions-$suffix'),
      displayVersion: '0.1.0',
      signingPublicKeys: <String, String>{'test-key': base64.encode(publicKey)},
    ),
  );
  final patch = await service.registerPatch(
    token: bootstrap.controlCredential.token,
    releaseId: release.id,
    idempotencyKey: 'admission-patch-$suffix',
    spec: PatchSpec(
      runtimePatchId: runtimePatchId,
      sequence: 1,
      artifactId: 'artifact_admission_$suffix',
      sha256: sha256Digest(bytes),
      sizeBytes: bytes.length,
      signatureKeyId: 'test-key',
    ),
  );
  final artifact = await service.uploadArtifact(
    token: bootstrap.controlCredential.token,
    artifactId: patch.artifactId,
    bytes: bytes,
    idempotencyKey: 'admission-artifact-$suffix',
  );
  await service.promote(
    token: bootstrap.controlCredential.token,
    environmentId: bootstrap.environment.id,
    releaseId: release.id,
    expectedVersion: 0,
    idempotencyKey: 'admission-promote-$suffix',
  );
  return _ReadyArtifact(artifact: artifact, bytes: bytes);
}

String _digest(String value) => 'sha256:${sha256.convert(utf8.encode(value))}';

Future<List<int>> _publicKey() async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(
    List<int>.filled(32, 7),
  );
  try {
    return (await keyPair.extractPublicKey()).bytes;
  } finally {
    keyPair.destroy();
  }
}

Future<List<int>> _patchBytes({
  required String releaseId,
  required String patchId,
}) async {
  final keyPair = await DartEd25519().newKeyPairFromSeed(
    List<int>.filled(32, 7),
  );
  try {
    final artifact = await PatchFormatV1.sealAsync(
      PatchArtifact(
        runtimeCompatibilityVersion: 1,
        applicationId: 'com.example.admission',
        releaseId: releaseId,
        patchId: patchId,
        sequence: 1,
        functions: <PatchFunctionEntry>[
          PatchFunctionEntry(
            id: 'lib:test#calculate',
            slot: 0,
            signatureDigest: _digest('signature'),
          ),
        ],
        capabilities: const <PatchCapabilityEntry>[],
        constants: const <PatchValue>[],
        instructions: const <int>[0],
        signatureMetadata: PatchSignatureMetadata(
          algorithm: 'ed25519',
          keyId: 'test-key',
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

Future<ControlPlaneException> _captureError(
  Future<void> Function() action,
) async {
  try {
    await action();
  } on ControlPlaneException catch (error) {
    return error;
  }
  throw StateError('Expected a control-plane exception');
}

final class _ReadyArtifact {
  const _ReadyArtifact({required this.artifact, required this.bytes});

  final ArtifactRecord artifact;
  final List<int> bytes;
}

final class _RecordingAdmission implements ArtifactDeliveryAdmission {
  _RecordingAdmission({required this.allow});

  final bool allow;
  ArtifactDeliveryAdmissionContext? context;
  String? admissionId;
  String? downloadProof;

  @override
  Future<void> authorize(
    ArtifactDeliveryAdmissionContext context, {
    String? admissionId,
    String? downloadProof,
  }) async {
    this.context = context;
    this.admissionId = admissionId;
    this.downloadProof = downloadProof;
    if (!allow) {
      throw const ControlPlaneException(
        'ARTIFACT_ADMISSION_DENIED',
        'Artifact delivery admission was denied',
        statusCode: 403,
      );
    }
  }
}
