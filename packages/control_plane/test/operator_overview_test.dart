import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  late ControlPlaneHttpServer adapter;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyfens-operator-overview-',
    );
    service = ControlPlaneService(store: FileControlPlaneStore(directory));
    bootstrap = await service.bootstrap(
      organizationName: 'Overview test',
      runtimeApplicationId: 'com.example.overview',
      platformId: 'android',
      environmentName: 'development',
    );
    adapter = ControlPlaneHttpServer(service);
    server = await adapter.bind();
  });

  tearDown(() async {
    await adapter.close(force: true);
    await directory.delete(recursive: true);
  });

  test('overview requires an authenticated control credential', () async {
    final client = HttpClient();
    try {
      final response = await _get(
        client,
        server.port,
        '/v1/organizations/${bootstrap.organization.id}/overview',
      );
      expect(response.statusCode, 401);
      expect(response.body['error'], isNotNull);

      final delivery = await _get(
        client,
        server.port,
        '/v1/organizations/${bootstrap.organization.id}/overview',
        token: bootstrap.deliveryCredential.token,
      );
      expect(delivery.statusCode, 403);

      final limited = CredentialService().issue(
        id: 'cred_limited',
        organizationId: bootstrap.organization.id,
        kind: CredentialKind.control,
        scopes: const <String>{
          'application:read',
          'release:read',
          'patch:read',
          'artifact:read',
          'rollout:read',
        },
      );
      await service.store.createJson(
        'credentials',
        limited.record.tokenHash,
        limited.record.toJson(),
      );
      final incomplete = await _get(
        client,
        server.port,
        '/v1/organizations/${bootstrap.organization.id}/overview',
        token: limited.token,
      );
      expect(incomplete.statusCode, 403);
    } finally {
      client.close(force: true);
    }
  });

  test(
    'overview is tenant scoped, bounded, deterministic, and redacted',
    () async {
      final bytes = utf8.encode('signed-dashboard-patch');
      final digest = sha256Digest(bytes);
      final release = ReleaseRecord(
        id: 'rel_dashboard',
        organizationId: bootstrap.organization.id,
        applicationId: bootstrap.application.id,
        platformId: 'plt_android',
        runtimeApplicationId: bootstrap.application.runtimeApplicationId,
        runtimeReleaseId: 'dashboard-release',
        buildTarget: 'android-arm64-release',
        runtimeCompatibilityVersion: 1,
        patchFormatVersion: 1,
        buildFingerprint: digest,
        capabilityAuthorityDigest: digest,
        functionSignatureDigest: digest,
        displayVersion: '0.1.0',
        signingPublicKeys: const <String, String>{
          'dashboard-key': 'public-key',
        },
        createdAt: DateTime.utc(2026, 8, 28, 10),
      );
      final patch = PatchRecord(
        id: 'pat_dashboard',
        organizationId: bootstrap.organization.id,
        releaseId: release.id,
        runtimePatchId: 'dashboard-patch',
        sequence: 1,
        artifactId: 'art_dashboard',
        sha256: digest,
        sizeBytes: bytes.length,
        signatureKeyId: 'dashboard-key',
        state: 'READY',
        createdAt: DateTime.utc(2026, 8, 28, 11),
      );
      final artifact = ArtifactRecord(
        id: patch.artifactId,
        organizationId: bootstrap.organization.id,
        patchId: patch.id,
        sha256: digest,
        sizeBytes: bytes.length,
        contentType: 'application/octet-stream',
        state: 'READY',
        createdAt: DateTime.utc(2026, 8, 28, 11),
      );
      await service.store.createJson('releases', release.id, release.toJson());
      await service.store.createJson('patches', patch.id, patch.toJson());
      await service.store.createJson(
        'artifacts',
        artifact.id,
        artifact.toJson(),
      );
      await service.store.putArtifact(digest, bytes);
      final extraApplication = ApplicationRecord(
        id: 'app_extra',
        organizationId: bootstrap.organization.id,
        runtimeApplicationId: 'com.example.extra',
        createdAt: DateTime.utc(2026, 8, 27),
      );
      await service.store.createJson(
        'applications',
        extraApplication.id,
        extraApplication.toJson(),
      );

      final rollout = RolloutRecord(
        id: 'rol_dashboard',
        organizationId: bootstrap.organization.id,
        currentRevision: 1,
        state: RolloutState.draft,
        createdAt: DateTime.utc(2026, 8, 28, 12),
      );
      final revision = RolloutRevision(
        id: 'rvr_dashboard',
        rolloutId: rollout.id,
        organizationId: rollout.organizationId,
        revision: 1,
        previousRevision: null,
        state: rollout.state,
        target: RolloutTarget(
          organizationId: rollout.organizationId,
          applicationId: bootstrap.application.id,
          environmentId: bootstrap.environment.id,
          platformId: release.platformId,
          releaseId: release.id,
          runtimeReleaseId: release.runtimeReleaseId,
          patchId: patch.id,
          runtimePatchId: patch.runtimePatchId,
          artifactId: artifact.id,
          sha256: digest,
          sequence: patch.sequence,
        ),
        policy: RolloutPolicy(
          cohortKind: RolloutCohortKind.percentage,
          percentageBasisPoints: 2500,
          salt: 'dashboard-salt',
        ),
        actorId: bootstrap.controlCredential.record.id,
        reason: 'dashboard test',
        pausedFromState: null,
        createdAt: DateTime.utc(2026, 8, 28, 12),
      );
      await service.store.createJson('rollouts', rollout.id, rollout.toJson());
      await service.store.createJson(
        'rollout_revisions',
        revision.id,
        revision.toJson(),
      );

      final secretAudit = AuditRecord(
        id: 'aud_dashboard',
        requestId: 'req_dashboard',
        organizationId: bootstrap.organization.id,
        actorId: bootstrap.controlCredential.record.id,
        action: 'dashboard.test',
        resourceType: 'overview',
        resourceId: 'overview',
        result: 'SUCCESS',
        metadata: <String, Object?>{
          'code': 'VISIBLE_CODE',
          'applicationId': 'app_nested',
          'apiKey': 'api-key-value',
          'password': 'password-value',
          'hash': 'hash-value',
          'data': 'data-value',
          'content': 'content-value',
          'nested': <String, Object?>{
            'code': 'NESTED_CODE',
            'apiKey': 'nested-api-key-value',
            'password': 'nested-password-value',
            'hash': 'nested-hash-value',
            'data': 'nested-data-value',
            'content': 'nested-content-value',
          },
        },
        createdAt: DateTime.utc(2026, 8, 28, 13),
      );
      await service.store.createJson(
        'audit',
        secretAudit.id,
        secretAudit.toJson(),
      );

      final other = await service.bootstrap(
        organizationName: 'Other organization',
        runtimeApplicationId: 'com.example.other',
        platformId: 'ios',
        environmentName: 'production',
      );

      final projection = OperatorOverviewProjection(service, maxItems: 1);
      final first = await projection.read(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
      );
      final second = await projection.read(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
      );
      expect(canonicalJson(first.toJson()), canonicalJson(second.toJson()));

      final body = first.toJson();
      expect(body['readOnly'], true);
      expect(body['runtimeAuthority'], 'client');
      expect((body['applications']! as List<Object?>).length, 1);
      expect((body['releases']! as List<Object?>).single, release.toJson());
      expect((body['patches']! as List<Object?>).single, patch.toJson());
      expect((body['artifacts']! as List<Object?>).single, artifact.toJson());
      expect(body['counts'], <String, Object?>{
        'applications': 2,
        'environments': 1,
        'releases': 1,
        'patches': 1,
        'artifacts': 1,
        'rollouts': 1,
        'audit': 1,
      });
      expect(body['truncated'], <String, Object?>{
        'applications': true,
        'environments': false,
        'releases': false,
        'patches': false,
        'artifacts': false,
        'rollouts': false,
        'audit': false,
      });
      expect(
        jsonEncode(body),
        isNot(contains(bootstrap.controlCredential.token)),
      );
      expect(
        jsonEncode(body),
        isNot(contains(bootstrap.controlCredential.record.tokenHash)),
      );
      expect(jsonEncode(body), isNot(contains('dashboard-salt')));
      expect(jsonEncode(body), isNot(contains('api-key-value')));
      expect(jsonEncode(body), isNot(contains('password-value')));
      expect(jsonEncode(body), isNot(contains('hash-value')));
      expect(jsonEncode(body), isNot(contains('data-value')));
      expect(jsonEncode(body), isNot(contains('content-value')));
      expect(jsonEncode(body), isNot(contains('nested-api-key-value')));
      expect(jsonEncode(body), isNot(contains('nested-password-value')));
      expect(jsonEncode(body), isNot(contains('nested-hash-value')));
      expect(jsonEncode(body), isNot(contains('nested-data-value')));
      expect(jsonEncode(body), isNot(contains('nested-content-value')));
      expect(jsonEncode(body), contains('VISIBLE_CODE'));
      final auditRecord =
          (body['audit']! as List<Object?>).single as Map<String, Object?>;
      final auditMetadata = auditRecord['metadata']! as Map<String, Object?>;
      expect(auditMetadata, <String, Object?>{
        'applicationId': 'app_nested',
        'code': 'VISIBLE_CODE',
      });
      expect(auditMetadata['nested'], isNull);
      for (final unsafeField in const [
        'apiKey',
        'password',
        'hash',
        'data',
        'content',
      ]) {
        expect(auditMetadata.containsKey(unsafeField), isFalse);
      }

      final foreign = await projection.read(
        token: other.controlCredential.token,
        organizationId: other.organization.id,
      );
      expect(foreign.organization.id, other.organization.id);
      expect(jsonEncode(body), isNot(contains(other.organization.id)));

      final client = HttpClient();
      try {
        final routed = await _get(
          client,
          server.port,
          '/v1/organizations/${bootstrap.organization.id}/overview',
          token: bootstrap.controlCredential.token,
        );
        expect(routed.statusCode, 200, reason: jsonEncode(routed.body));
        expect(routed.body['organization'], bootstrap.organization.toJson());
        expect((routed.body['applications']! as List<Object?>).length, 2);

        final crossTenant = await _get(
          client,
          server.port,
          '/v1/organizations/${other.organization.id}/overview',
          token: bootstrap.controlCredential.token,
        );
        expect(crossTenant.statusCode, 404);
      } finally {
        client.close(force: true);
      }
    },
  );

  test('empty resource collections remain explicit and stable', () async {
    final projection = OperatorOverviewProjection(service);
    final body = (await projection.read(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
    )).toJson();
    expect(body['releases'], isEmpty);
    expect(body['patches'], isEmpty);
    expect(body['artifacts'], isEmpty);
    expect(body['rollouts'], isEmpty);
    expect(body['audit'], isEmpty);
    expect(body['counts'], <String, Object?>{
      'applications': 1,
      'environments': 1,
      'releases': 0,
      'patches': 0,
      'artifacts': 0,
      'rollouts': 0,
      'audit': 0,
    });
  });
}

Future<_Response> _get(
  HttpClient client,
  int port,
  String path, {
  String? token,
}) async {
  final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  return _Response(
    response.statusCode,
    text.isEmpty
        ? <String, Object?>{}
        : jsonDecode(text) as Map<String, Object?>,
  );
}

final class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}
