import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'auth_client.dart';
import 'canonical.dart';
import 'diagnostics.dart';
import 'profile.dart';
import 'toolchain.dart';

/// The structured result of registering, uploading, and promoting one patch.
///
/// The service is shared by the terminal CLI and MCP adapters. It performs
/// local verification before sending any bytes to the control plane and never
/// returns the bearer token used for the request.
final class ControlPlaneDeployment {
  const ControlPlaneDeployment({required this.data});

  final Map<String, Object?> data;
}

/// Authenticated control-plane delivery implemented as a domain service.
///
/// CLI and MCP are intentionally thin adapters over this service. In
/// particular, the MCP adapter does not spawn the CLI or scrape terminal
/// output to perform a deploy.
final class ControlPlaneDeliveryService {
  const ControlPlaneDeliveryService({
    required this.toolchain,
    required this.authClient,
  });

  final HyfensToolchain toolchain;
  final AuthClient authClient;

  Future<ControlPlaneDeployment> deploy({
    String? projectPath,
    String? releaseId,
    String? patchPath,
    Uri? endpoint,
    String? token,
    String? organizationId,
    String? applicationId,
    String? environmentId,
    String? caCertPath,
    int expectedVersion = 0,
    String displayVersion = 'local',
    String? profileName,
  }) async {
    final profile = await authClient.storage.readProfile(name: profileName);
    final target = validateControlPlaneEndpoint(
      endpoint ?? profile?.endpoint ?? Uri.parse(managedCloudApiBase),
      operation: 'deploy',
    );
    final profileScope = _profileScopeForEndpoint(profile, target);
    final resolvedToken = token == null || token.isEmpty
        ? await authClient.accessTokenOrNull(
            endpoint: target,
            profileName: profileName,
          )
        : token;
    final organization = organizationId ?? profileScope?.organizationId;
    final application = applicationId ?? profileScope?.applicationId;
    final environment = environmentId ?? profileScope?.environmentId;
    if (resolvedToken == null ||
        organization == null ||
        application == null ||
        environment == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'D8001',
        summary: 'Deploy configuration is incomplete',
        detail: 'A host-bound session or explicit endpoint, token, organization, application, and environment are required.',
        action: 'Run hyfens login with one selected profile or provide request-scoped values.',
      );
    }
    if (expectedVersion < 0) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'D8001',
        summary: 'Expected environment version is invalid',
        detail: '$expectedVersion',
        action: 'Use a non-negative integer.',
      );
    }

    final project = toolchain.project(projectPath: projectPath);
    final store = ToolStore(project);
    final selectedReleaseId = releaseId ?? _onlyReleaseId(store);
    final release = store.readRelease(selectedReleaseId);
    final selectedPatchPath =
        patchPath ?? _latestPatchPath(store, release.releaseId);
    final patchFile = File(selectedPatchPath);
    if (!patchFile.existsSync()) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'D8002',
        summary: 'Deploy patch artifact is missing',
        detail: patchFile.path,
        action: 'Create a patch first or pass an existing patch_path.',
      );
    }

    final inspection = await toolchain.verify(
      file: patchFile,
      projectPath: projectPath,
      releaseId: release.releaseId,
    );
    final artifactBytes = await patchFile.readAsBytes();
    final artifact = inspection.artifact;
    final publicKey = toolchain.inspectPublicKey(projectPath: projectPath);
    final securityContext = _securityContext(caCertPath);
    final releaseBody = <String, Object?>{
      'application_id': application,
      'platform_id': 'plt_${release.target}_${release.architecture}',
      'runtime_application_id': release.applicationId,
      'runtime_release_id': release.releaseId,
      'build_target':
          '${release.target}-${release.architecture}-${release.buildMode}',
      'runtime_compatibility_version':
          release.manifest.runtimeCompatibilityVersion,
      'patch_format_version': release.manifest.patchFormatVersion,
      'build_fingerprint': release.buildFingerprint,
      'capability_authority_digest': digestJson(
        release.manifest.capabilities.map((item) => item.toJson()).toList(),
      ),
      'function_signature_digest': digestJson(
        release.manifest.functions.map((item) => item.toJson()).toList(),
      ),
      'display_version': displayVersion,
      'signing_public_keys': <String, String>{
        publicKey.keyId: base64.encode(publicKey.publicKey),
      },
    };
    final releaseResponse = await _postJson(
      uri: _resolveUri(
        target,
        'v1/organizations/$organization/applications/$application/releases',
      ),
      token: resolvedToken,
      securityContext: securityContext,
      idempotencyKey: 'release-${release.releaseId}',
      body: releaseBody,
    );
    final serviceReleaseId = _requiredResponseString(releaseResponse, 'id');
    final artifactId = 'art_${sha256Hex(artifactBytes).substring(0, 24)}';
    final patchBody = <String, Object?>{
      'runtime_patch_id': artifact.patchId,
      'sequence': artifact.sequence,
      'artifact_id': artifactId,
      'sha256': 'sha256:${sha256Hex(artifactBytes)}',
      'size_bytes': artifactBytes.length,
      'signature_key_id': artifact.signatureMetadata.keyId,
    };
    final patchResponse = await _postJson(
      uri: _resolveUri(
        target,
        'v1/organizations/$organization/releases/$serviceReleaseId/patches',
      ),
      token: resolvedToken,
      securityContext: securityContext,
      idempotencyKey: 'patch-${artifact.patchId}',
      body: patchBody,
    );
    await _putBytes(
      uri: _resolveUri(
        target,
        'v1/organizations/$organization/artifacts/$artifactId',
      ),
      token: resolvedToken,
      securityContext: securityContext,
      idempotencyKey: 'artifact-${sha256Hex(artifactBytes)}',
      bytes: artifactBytes,
    );
    final promotion = await _postJson(
      uri: _resolveUri(
        target,
        'v1/organizations/$organization/environments/$environment/release-promotions',
      ),
      token: resolvedToken,
      securityContext: securityContext,
      idempotencyKey: 'promote-${release.releaseId}-$expectedVersion',
      body: <String, Object?>{
        'release_id': serviceReleaseId,
        'expected_version': expectedVersion,
      },
    );
    return ControlPlaneDeployment(
      data: <String, Object?>{
        'result': 'DEPLOYED',
        'releaseId': release.releaseId,
        'serviceReleaseId': serviceReleaseId,
        'patchId': artifact.patchId,
        'servicePatchId': _requiredResponseString(patchResponse, 'id'),
        'artifactId': artifactId,
        'environmentId': environment,
        'environmentVersion': promotion['version'],
        'signature': 'verified locally before upload',
      },
    );
  }

  String _onlyReleaseId(ToolStore store) {
    final releases = store.listReleases();
    if (releases.length == 1) return releases.single.releaseId;
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'D8001',
      summary: releases.isEmpty
          ? 'Deploy requires a local release baseline'
          : 'Deploy release selection is ambiguous',
      detail: releases.map((release) => release.releaseId).join(', '),
      action: releases.isEmpty
          ? 'Run hyfens release android or hyfens release ios first.'
          : 'Pass release_id explicitly.',
    );
  }

  String _latestPatchPath(ToolStore store, String releaseId) {
    final directory = store.patchDirectory(releaseId);
    final patches = directory.existsSync()
        ? directory
              .listSync(followLinks: false)
              .whereType<File>()
              .map((file) {
                final match = RegExp(r'^(\d+)\.patch$')
                    .firstMatch(p.basename(file.path));
                return (
                  file: file,
                  sequence: match == null
                      ? null
                      : int.tryParse(match.group(1)!),
                );
              })
              .where((entry) => entry.sequence != null && entry.sequence! > 0)
              .toList()
        : <({File file, int? sequence})>[];
    patches.sort((left, right) => left.sequence!.compareTo(right.sequence!));
    if (patches.isEmpty) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'D8001',
        summary: 'Deploy requires a local patch artifact',
        detail: releaseId,
        action: 'Run hyfens patch android or hyfens patch ios first.',
      );
    }
    return patches.last.file.path;
  }
}

ProfileScope? _profileScopeForEndpoint(Profile? profile, Uri endpoint) {
  if (profile == null ||
      !controlPlaneEndpointsMatch(profile.endpoint, endpoint) ||
      profile.profiles.length != 1) {
    return null;
  }
  return profile.profiles.single;
}

SecurityContext? _securityContext(String? certificatePath) {
  if (certificatePath == null || certificatePath.isEmpty) return null;
  final file = File(certificatePath);
  if (!file.existsSync()) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'D8006',
      summary: 'Configured TLS CA certificate is missing',
      detail: certificatePath,
      action: 'Provide a readable PEM CA certificate or remove ca_cert.',
    );
  }
  try {
    final context = SecurityContext(withTrustedRoots: true);
    context.setTrustedCertificates(file.path);
    return context;
  } on Object catch (error) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'D8007',
      summary: 'Configured TLS CA certificate is invalid',
      detail: '${error.runtimeType}',
      action: 'Provide a readable PEM CA certificate.',
    );
  }
}

Uri _resolveUri(Uri endpoint, String path) {
  final root = endpoint.toString().endsWith('/')
      ? endpoint.toString()
      : '${endpoint.toString()}/';
  return Uri.parse(root).resolve(path);
}

Future<Map<String, Object?>> _postJson({
  required Uri uri,
  required String token,
  required SecurityContext? securityContext,
  required String idempotencyKey,
  required Map<String, Object?> body,
}) async {
  final client = HttpClient(context: securityContext);
  try {
    final request = await client.postUrl(uri);
    final bytes = utf8.encode(jsonEncode(body));
    request
      ..headers.contentType = ContentType.json
      ..headers.set('Authorization', 'Bearer $token')
      ..headers.set('Idempotency-Key', idempotencyKey)
      ..headers.set(
        'X-Request-Id',
        'cli-${DateTime.now().microsecondsSinceEpoch}',
      )
      ..contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    final source = await response.transform(utf8.decoder).join();
    Object? decoded;
    try {
      decoded = source.isEmpty ? <String, Object?>{} : jsonDecode(source);
    } on Object {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'D8004',
        summary: 'Control-plane response is malformed',
        detail: 'HTTP ${response.statusCode}',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: decoded is Map && (decoded['error'] is Map)
            ? ((decoded['error'] as Map)['code'] as String? ?? 'D8003')
            : 'D8003',
        summary: 'Control-plane request was rejected',
        detail: decoded is Map
            ? jsonEncode(decoded['error'] ?? decoded)
            : 'HTTP ${response.statusCode}',
      );
    }
    if (decoded is! Map) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'D8004',
        summary: 'Control-plane response is malformed',
        detail: uri.toString(),
      );
    }
    return <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
  } finally {
    client.close(force: true);
  }
}

Future<void> _putBytes({
  required Uri uri,
  required String token,
  required SecurityContext? securityContext,
  required String idempotencyKey,
  required List<int> bytes,
}) async {
  final client = HttpClient(context: securityContext);
  try {
    final request = await client.putUrl(uri);
    request
      ..headers.contentType = ContentType('application', 'octet-stream')
      ..headers.set('Authorization', 'Bearer $token')
      ..headers.set('Idempotency-Key', idempotencyKey)
      ..headers.set(
        'X-Request-Id',
        'cli-${DateTime.now().microsecondsSinceEpoch}',
      )
      ..contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    final source = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'D8005',
        summary: 'Artifact upload was rejected',
        detail: source,
      );
    }
  } finally {
    client.close(force: true);
  }
}

String _requiredResponseString(Map<String, Object?> body, String key) {
  final value = body[key];
  if (value is! String || value.isEmpty) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.environment,
      code: 'D8004',
      summary: 'Control-plane response is missing a required identifier',
      detail: key,
    );
  }
  return value;
}
