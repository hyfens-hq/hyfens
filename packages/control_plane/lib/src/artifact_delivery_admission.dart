import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'encoding.dart';
import 'errors.dart';

const String artifactAdmissionIdHeader = 'X-Hyfens-Install-Admission';
const String artifactDownloadProofHeader = 'X-Hyfens-Install-Proof';

/// Server-resolved identity for one artifact delivery attempt.
///
/// The public control plane does not interpret admission policy or proof
/// signatures. It only supplies the resolved release graph to an optional
/// adapter. The validator owns the meaning of [admissionId] and
/// [downloadProof].
final class ArtifactDeliveryAdmissionContext {
  ArtifactDeliveryAdmissionContext({
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String runtimeApplicationId,
    required String platform,
    required String runtimeReleaseId,
    required String runtimePatchId,
    required String artifactDigest,
    required String artifactId,
  }) : organizationId = requireOpaqueId(organizationId, 'organization ID'),
       applicationId = requireOpaqueId(applicationId, 'application ID'),
       environmentId = requireOpaqueId(environmentId, 'environment ID'),
       runtimeApplicationId = requireRuntimeIdentity(
         runtimeApplicationId,
         'runtime application ID',
       ),
       platform = requireOpaqueId(platform, 'platform ID'),
       runtimeReleaseId = requireRuntimeIdentity(
         runtimeReleaseId,
         'runtime release ID',
       ),
       runtimePatchId = requireRuntimeIdentity(
         runtimePatchId,
         'runtime patch ID',
       ),
       artifactDigest = _normalizedDigest(artifactDigest),
       artifactId = requireOpaqueId(artifactId, 'artifact ID');

  final String organizationId;
  final String applicationId;
  final String environmentId;
  final String runtimeApplicationId;
  final String platform;
  final String runtimeReleaseId;
  final String runtimePatchId;
  final String artifactDigest;
  final String artifactId;

  /// Exactly the server-owned fields in the validator request.
  Map<String, Object?> toJson() => <String, Object?>{
    'organization_id': organizationId,
    'application_id': applicationId,
    'environment_id': environmentId,
    'runtime_application_id': runtimeApplicationId,
    'platform': platform,
    'release_id': runtimeReleaseId,
    'patch_id': runtimePatchId,
    'artifact_digest': artifactDigest,
    'artifact_id': artifactId,
  };

  static String _normalizedDigest(String value) {
    final normalized = requireSha256Digest(value);
    return normalized.substring('sha256:'.length);
  }
}

/// Generic delivery gate for a deployment-specific admission decision. The
/// public control plane does not define the decision's policy semantics.
abstract interface class ArtifactDeliveryAdmission {
  Future<void> authorize(
    ArtifactDeliveryAdmissionContext context, {
    String? admissionId,
    String? downloadProof,
  });
}

/// HTTP adapter for the configured artifact-admission endpoint.
///
/// The endpoint and service token are runtime configuration. The adapter does
/// not parse or verify [downloadProof]; it forwards that opaque header value.
final class RemoteArtifactDeliveryAdmission
    implements ArtifactDeliveryAdmission {
  RemoteArtifactDeliveryAdmission({
    required Uri endpoint,
    required String serviceToken,
    this.requestTimeout = const Duration(seconds: 8),
    this.maxResponseBytes = 32 * 1024,
  }) : endpoint = _validateEndpoint(endpoint),
       serviceToken = _validateServiceToken(serviceToken) {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be positive',
      );
    }
    if (maxResponseBytes <= 0) {
      throw ArgumentError.value(
        maxResponseBytes,
        'maxResponseBytes',
        'must be positive',
      );
    }
  }

  final Uri endpoint;
  final String serviceToken;
  final Duration requestTimeout;
  final int maxResponseBytes;

  @override
  Future<void> authorize(
    ArtifactDeliveryAdmissionContext context, {
    String? admissionId,
    String? downloadProof,
  }) async {
    _validateOptionalHeader(admissionId, 'admission ID', maxLength: 256);
    _validateOptionalHeader(downloadProof, 'download proof', maxLength: 4096);
    final body = <String, Object?>{
      ...context.toJson(),
      'admission_id': admissionId,
      'signature': downloadProof,
    };
    final client = HttpClient()..connectionTimeout = requestTimeout;
    try {
      final request = await client.postUrl(endpoint).timeout(requestTimeout);
      request
        ..followRedirects = false
        ..headers.contentType = ContentType.json
        ..headers.set(HttpHeaders.authorizationHeader, 'Bearer $serviceToken');
      final bytes = utf8.encode(jsonEncode(body));
      request
        ..contentLength = bytes.length
        ..add(bytes);
      final response = await request.close().timeout(requestTimeout);
      final responseBytes = await _readResponse(response)
          .timeout(requestTimeout);
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw _denied();
      }
      if (response.statusCode != HttpStatus.ok) {
        throw _unavailable();
      }
      final decoded = jsonDecode(
        utf8.decode(responseBytes, allowMalformed: false),
      );
      if (decoded is! Map<String, Object?>) throw _unavailable();
      const expectedKeys = <String>{'allowed', 'admission_id', 'artifact_id'};
      if (!decoded.keys.toSet().containsAll(expectedKeys) ||
          decoded.keys.length != expectedKeys.length) {
        throw _unavailable();
      }
      if (decoded['allowed'] != true) throw _denied();
      if (decoded['admission_id'] != admissionId ||
          decoded['artifact_id'] != context.artifactId) {
        throw _unavailable();
      }
    } on ControlPlaneException {
      rethrow;
    } on TimeoutException {
      throw _unavailable();
    } on FormatException {
      throw _unavailable();
    } on Object {
      throw _unavailable();
    } finally {
      client.close(force: true);
    }
  }

  static Uri _validateEndpoint(Uri value) {
    final loopback =
        value.host.toLowerCase() == 'localhost' ||
        (InternetAddress.tryParse(value.host)?.isLoopback ?? false);
    if (!value.hasAuthority ||
        value.userInfo.isNotEmpty ||
        value.hasQuery ||
        value.hasFragment ||
        value.path != '/internal/runtime/artifact-admission' ||
        !(value.scheme == 'https' || value.scheme == 'http' && loopback)) {
      throw ArgumentError(
        'endpoint must be the HTTPS or loopback HTTP artifact-admission endpoint',
      );
    }
    return value;
  }

  static String _validateServiceToken(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{32,256}$').hasMatch(value)) {
      throw ArgumentError(
        'serviceToken must be a 32-256 character base64url value',
      );
    }
    return value;
  }

  static void _validateOptionalHeader(
    String? value,
    String _, {
    required int maxLength,
  }) {
    if (value == null) return;
    if (value.isEmpty ||
        value.length > maxLength ||
        value.contains(RegExp(r'[\u0000\r\n]'))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Artifact admission headers are invalid',
        statusCode: 400,
      );
    }
  }

  static ControlPlaneException _denied() => const ControlPlaneException(
    'ARTIFACT_ADMISSION_DENIED',
    'Artifact delivery admission was denied',
    statusCode: 403,
  );

  static ControlPlaneException _unavailable() => const ControlPlaneException(
    'ARTIFACT_ADMISSION_UNAVAILABLE',
    'Artifact delivery admission is unavailable',
    statusCode: 503,
  );

  Future<List<int>> _readResponse(HttpClientResponse response) async {
    if (response.contentLength > maxResponseBytes) throw _unavailable();
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > maxResponseBytes) throw _unavailable();
    }
    return bytes;
  }
}
