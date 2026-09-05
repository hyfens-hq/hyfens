import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';

import 'install_receipts.dart';
import 'runtime_attestation.dart';

/// Read-only application delivery configuration for the authenticated local
/// control-plane contract. The credential is intentionally app-scoped and
/// extractable; it is not a control-plane or signing credential.
final class HyfensControlPlaneConfiguration {
  HyfensControlPlaneConfiguration({
    required this.baseUrl,
    required this.deliveryCredential,
    required this.applicationId,
    required this.environmentId,
    required this.platformId,
    this.runtimeCompatibilityVersion = patchFormatRuntimeCompatibilityV1,
    this.patchFormatVersion = patchFormatV1,
    this.requestTimeout = const Duration(seconds: 8),
    this.receiptMode = HyfensInstallReceiptMode.disabled,
    this.attestationProducer,
    this.productionGate,
  }) {
    if ((baseUrl.scheme != 'http' && baseUrl.scheme != 'https') ||
        !baseUrl.hasAuthority ||
        baseUrl.userInfo.isNotEmpty ||
        baseUrl.query.isNotEmpty ||
        baseUrl.fragment.isNotEmpty) {
      throw ArgumentError(
        'must be an HTTP(S) URL without credentials or query state',
        'baseUrl',
      );
    }
    if (baseUrl.scheme == 'http' && !_isExplicitLoopbackEndpoint(baseUrl)) {
      throw ArgumentError(
        'remote control-plane HTTP is not permitted for credential-bearing delivery',
        'baseUrl',
      );
    }
    if (deliveryCredential.isEmpty ||
        deliveryCredential.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError(
        'must be a non-empty single-line credential',
        'deliveryCredential',
      );
    }
    _validateField(applicationId, 'applicationId');
    _validateField(environmentId, 'environmentId');
    _validateField(platformId, 'platformId');
    if (runtimeCompatibilityVersion <= 0 || patchFormatVersion <= 0) {
      throw ArgumentError('Runtime and Patch Format versions must be positive');
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be positive',
      );
    }
  }

  final Uri baseUrl;
  final String deliveryCredential;
  final String applicationId;
  final String environmentId;
  final String platformId;
  final int runtimeCompatibilityVersion;
  final int patchFormatVersion;
  final Duration requestTimeout;
  final HyfensInstallReceiptMode receiptMode;
  final HyfensRuntimeAttestationEvidenceProducer? attestationProducer;
  final bool Function()? productionGate;

  /// Reads the runtime-only delivery configuration supplied by a release
  /// build. A delivery credential is intentionally a read-only app secret: it
  /// is expected to be extractable from the shipped binary and is never a
  /// signing or control-plane mutation credential.
  ///
  /// An entirely unset configuration keeps ordinary local/dev releases on the
  /// existing patch URI path. Partial configuration fails closed during
  /// bootstrap rather than silently falling back to an unauthenticated
  /// endpoint.
  static HyfensControlPlaneConfiguration? fromEnvironment() {
    const baseUrl = String.fromEnvironment('HYFENS_CONTROL_PLANE_URL');
    const deliveryCredential = String.fromEnvironment(
      'HYFENS_DELIVERY_CREDENTIAL',
    );
    const applicationId = String.fromEnvironment('HYFENS_APPLICATION_ID');
    const environmentId = String.fromEnvironment('HYFENS_ENVIRONMENT_ID');
    const platformId = String.fromEnvironment('HYFENS_PLATFORM_ID');
    const receiptMode = String.fromEnvironment('HYFENS_INSTALL_RECEIPT_MODE');
    final values = <String>[
      baseUrl,
      deliveryCredential,
      applicationId,
      environmentId,
      platformId,
    ];
    final parsedReceiptMode = HyfensInstallReceiptMode.parse(receiptMode);
    if (values.every((value) => value.isEmpty)) {
      if (parsedReceiptMode == HyfensInstallReceiptMode.disabled) return null;
      throw const FormatException(
        'Authenticated control-plane configuration is incomplete',
      );
    }
    if (values.any((value) => value.isEmpty)) {
      throw const FormatException(
        'Authenticated control-plane configuration is incomplete',
      );
    }
    return HyfensControlPlaneConfiguration(
      baseUrl: Uri.parse(baseUrl),
      deliveryCredential: deliveryCredential,
      applicationId: applicationId,
      environmentId: environmentId,
      platformId: platformId,
      receiptMode: parsedReceiptMode,
    );
  }

  Uri get updateCheckUri => _path('/v1/runtime/update-check');

  Uri artifactUri(String artifactId) =>
      _path('/v1/runtime/artifacts/${Uri.encodeComponent(artifactId)}').replace(
        queryParameters: <String, String>{
          'application_id': applicationId,
          'environment_id': environmentId,
        },
      );

  Uri _path(String path) {
    final basePath = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    return baseUrl.replace(path: '$basePath$path', queryParameters: const {});
  }

  static void _validateField(String value, String name) {
    if (value.isEmpty || value.length > 256 || value.contains('\u0000')) {
      throw ArgumentError.value(
        value,
        name,
        'must be a bounded non-empty value',
      );
    }
  }

  static bool _isExplicitLoopbackEndpoint(Uri endpoint) {
    final host = endpoint.host.toLowerCase();
    if (host == 'localhost') return true;
    final address = InternetAddress.tryParse(host);
    return address?.isLoopback ?? false;
  }
}

enum HyfensDeliveryDecision {
  noUpdate,
  patchAvailable,
  updateBlocked,
  storeReleaseRequired,
}

final class HyfensControlPlaneDeliveryResult {
  const HyfensControlPlaneDeliveryResult({
    required this.decision,
    required this.activated,
    required this.detail,
    this.sequence,
    this.artifactDigest,
  });

  final HyfensDeliveryDecision decision;
  final bool activated;
  final String detail;
  final int? sequence;
  final String? artifactDigest;
}

/// A bounded transport adapter for the authenticated product-service API.
///
/// This class does not parse Patch Format v1, verify signatures, inspect
/// capabilities, decide sequence/high-water admission, mark health, or roll
/// back. It only authenticates lookup/fetch, checks transport metadata, and
/// hands exact bytes to [E1PatchController].
final class HyfensControlPlaneDelivery {
  HyfensControlPlaneDelivery(this.configuration, {this.receipts});

  static const int _maxLookupBytes = 256 * 1024;
  static const int _maxLookupRequestBytes = 16 * 1024;
  static const int _maxArtifactBytes = PatchFormatLimits.maxArtifactBytes;

  final HyfensControlPlaneConfiguration configuration;
  final HyfensInstallReceipts? receipts;

  Future<HyfensControlPlaneDeliveryResult> deliver(
    E1PatchController controller,
  ) async {
    final state = controller.durableState;
    final response = await _postJson(
      configuration.updateCheckUri,
      <String, Object?>{
        'application_id': configuration.applicationId,
        'environment_id': configuration.environmentId,
        'runtime_application_id': controller.appId,
        // The service currently accepts the bounded identity fields below;
        // retaining both spellings keeps the adapter aligned with the
        // versioned product contract while unknown additive fields are ignored
        // by older local service revisions.
        'platform': configuration.platformId,
        'platform_id': configuration.platformId,
        'runtime_release_id': controller.releaseId,
        'runtime_compatibility_version':
            configuration.runtimeCompatibilityVersion,
        'patch_format_version': configuration.patchFormatVersion,
        'high_water_sequence': state.highWaterSequence,
        'high_water': <String, Object?>{
          'sequence': state.highWaterSequence,
          if (state.highWaterDigest != null) 'digest': state.highWaterDigest,
        },
      },
      maxBytes: _maxLookupBytes,
    );
    final decision = _decision(_string(response, 'decision'));
    final responseReleaseId = _optionalString(response, const <String>[
      'runtimeReleaseId',
      'runtime_release_id',
    ]);
    if (responseReleaseId != null &&
        responseReleaseId != controller.releaseId) {
      throw const HyfensControlPlaneDeliveryException(
        'RELEASE_ID_MISMATCH',
        'Delivery response is bound to another runtime release',
      );
    }
    final responsePlatformId = _optionalString(response, const <String>[
      'platformId',
      'platform_id',
    ]);
    if (responsePlatformId != null &&
        responsePlatformId != configuration.platformId) {
      throw const HyfensControlPlaneDeliveryException(
        'PLATFORM_ID_MISMATCH',
        'Delivery response is bound to another platform',
      );
    }
    switch (decision) {
      case HyfensDeliveryDecision.noUpdate:
        return const HyfensControlPlaneDeliveryResult(
          decision: HyfensDeliveryDecision.noUpdate,
          activated: false,
          detail: 'control plane reported no eligible update',
        );
      case HyfensDeliveryDecision.updateBlocked:
        return const HyfensControlPlaneDeliveryResult(
          decision: HyfensDeliveryDecision.updateBlocked,
          activated: false,
          detail: 'control plane withheld delivery',
        );
      case HyfensDeliveryDecision.storeReleaseRequired:
        return const HyfensControlPlaneDeliveryResult(
          decision: HyfensDeliveryDecision.storeReleaseRequired,
          activated: false,
          detail: 'current runtime requires a store release',
        );
      case HyfensDeliveryDecision.patchAvailable:
        break;
    }

    final patch = _object(response, 'patch');
    final artifact = _object(response, 'artifact');
    final artifactId = _requiredString(artifact, const <String>[
      'id',
      'artifactId',
      'artifact_id',
    ], 'artifact ID');
    _validateBoundedString(artifactId, 'artifact ID');
    final expectedDigest = _digest(
      _requiredString(artifact, const <String>[
        'sha256',
        'digest',
      ], 'artifact digest'),
    );
    final expectedSize = _requiredInt(artifact, const <String>[
      'sizeBytes',
      'size_bytes',
    ], 'artifact size');
    final sequence = _requiredInt(patch, const <String>[
      'sequence',
    ], 'patch sequence');
    final patchDigest = _optionalString(patch, const <String>[
      'sha256',
      'digest',
    ]);
    if (patchDigest != null && _digest(patchDigest) != expectedDigest) {
      throw const HyfensControlPlaneDeliveryException(
        'ARTIFACT_METADATA_MISMATCH',
        'Patch and artifact digests disagree',
      );
    }
    E1InstallReceiptContext? receiptContext;
    final patchReferenceDigest = _patchReferenceDigest(expectedDigest);
    final currentReference = controller.durableState.current;
    final alreadyHealthy =
        controller.durableState.health == 'healthy' &&
        (currentReference == 'patch-$patchReferenceDigest.v1.patch' ||
            currentReference == 'patch-$patchReferenceDigest.e1.signed.json');
    if (configuration.receiptMode != HyfensInstallReceiptMode.disabled &&
        alreadyHealthy &&
        !controller.recoveryNeeded) {
      return HyfensControlPlaneDeliveryResult(
        decision: HyfensDeliveryDecision.patchAvailable,
        activated: true,
        detail: 'exact healthy artifact already active; download skipped',
        sequence: sequence,
        artifactDigest: expectedDigest,
      );
    }
    if (configuration.receiptMode != HyfensInstallReceiptMode.disabled &&
        !alreadyHealthy) {
      final client = receipts;
      if (client == null) {
        if (configuration.receiptMode == HyfensInstallReceiptMode.production) {
          throw const HyfensControlPlaneDeliveryException(
            'PRODUCTION_ATTESTATION_UNAVAILABLE',
            'Production admission requires its attestation-enabled receipt client',
          );
        }
        throw const HyfensControlPlaneDeliveryException(
          'RECEIPT_CLIENT_UNAVAILABLE',
          'Managed install admission requires its configured receipt client',
        );
      }
      if (configuration.receiptMode == HyfensInstallReceiptMode.production &&
          !client.isProduction) {
        throw const HyfensControlPlaneDeliveryException(
          'PRODUCTION_ATTESTATION_UNAVAILABLE',
          'Production admission requires its attestation-enabled receipt client',
        );
      }
      if (configuration.receiptMode != HyfensInstallReceiptMode.production &&
          client.isProduction) {
        throw const HyfensControlPlaneDeliveryException(
          'RECEIPT_MODE_MISMATCH',
          'Development admission cannot use a production receipt client',
        );
      }
      receiptContext = await client.prepare(
        runtimeApplicationId: controller.appId,
        releaseId: controller.releaseId,
        patchId: _requiredString(patch, const [
          'runtimePatchId',
          'runtime_patch_id',
        ], 'runtime patch ID'),
        artifactDigest: expectedDigest,
      );
    }
    final downloadProof = receiptContext == null
        ? null
        : await receipts!.downloadProof(receiptContext, artifactId);
    final watch = Stopwatch()..start();
    final bytes = await _downloadArtifact(
      configuration.artifactUri(artifactId),
      admissionId: receiptContext?.admissionId,
      proof: downloadProof,
      retryTransiently: receiptContext != null,
    );
    watch.stop();
    if (bytes.length != expectedSize) {
      throw HyfensControlPlaneDeliveryException(
        'ARTIFACT_SIZE_MISMATCH',
        'Fetched artifact length does not match delivery metadata',
      );
    }
    final actualDigest = _digestBytes(bytes);
    if (actualDigest != expectedDigest) {
      throw HyfensControlPlaneDeliveryException(
        'ARTIFACT_DIGEST_MISMATCH',
        'Fetched artifact digest does not match delivery metadata',
      );
    }
    final activated = await controller.activateBytes(
      bytes,
      downloadMicros: watch.elapsedMicroseconds,
      receiptContext: receiptContext,
    );
    return HyfensControlPlaneDeliveryResult(
      decision: HyfensDeliveryDecision.patchAvailable,
      activated: activated,
      detail: activated
          ? 'exact artifact handed to runtime candidate activation'
          : controller.status.detail,
      sequence: sequence,
      artifactDigest: expectedDigest,
    );
  }

  Future<List<int>> _downloadArtifact(
    Uri uri, {
    required String? admissionId,
    required String? proof,
    required bool retryTransiently,
  }) async {
    try {
      return await _getBytes(uri, admissionId: admissionId, proof: proof);
    } on HyfensControlPlaneDeliveryException catch (error) {
      if (!retryTransiently || !_retryableArtifactError(error)) rethrow;
      // Reuse the exact admission and proof for the bounded retry. A retry
      // must not create a second server admission or sign a different scope.
      return _getBytes(uri, admissionId: admissionId, proof: proof);
    }
  }

  Future<Map<String, Object?>> _postJson(
    Uri uri,
    Map<String, Object?> body, {
    required int maxBytes,
  }) async {
    final encoded = utf8.encode(jsonEncode(body));
    if (encoded.length > _maxLookupRequestBytes) {
      throw const HyfensControlPlaneDeliveryException(
        'REQUEST_TOO_LARGE',
        'Update lookup request exceeds the runtime transport bound',
      );
    }
    final client = HttpClient()
      ..connectionTimeout = configuration.requestTimeout;
    try {
      final request =
          await client.postUrl(uri).timeout(configuration.requestTimeout)
            ..followRedirects = false;
      _headers(request, json: true);
      request.contentLength = encoded.length;
      request.add(encoded);
      final response = await request.close().timeout(
        configuration.requestTimeout,
      );
      final bytes = await _readResponse(
        response,
        maxBytes: maxBytes,
      ).timeout(configuration.requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HyfensControlPlaneDeliveryException(
          'LOOKUP_HTTP_${response.statusCode}',
          'Authenticated update lookup failed',
          statusCode: response.statusCode,
        );
      }
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      return _objectValue(decoded, 'update lookup response');
    } on HyfensControlPlaneDeliveryException {
      rethrow;
    } on TimeoutException {
      throw const HyfensControlPlaneDeliveryException(
        'DELIVERY_TIMEOUT',
        'Authenticated update lookup timed out',
      );
    } on Object {
      throw const HyfensControlPlaneDeliveryException(
        'DELIVERY_UNAVAILABLE',
        'Authenticated update lookup was unavailable',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> _getBytes(
    Uri uri, {
    String? admissionId,
    String? proof,
  }) async {
    if (!_sameOrigin(configuration.baseUrl, uri)) {
      throw const HyfensControlPlaneDeliveryException(
        'ARTIFACT_ORIGIN_MISMATCH',
        'Artifact fetch must remain same-origin with the control plane',
      );
    }
    if ((admissionId == null) != (proof == null)) {
      throw const HyfensControlPlaneDeliveryException(
        'ARTIFACT_PROOF_INVALID',
        'Artifact admission and proof headers must be supplied together',
      );
    }
    final client = HttpClient()
      ..connectionTimeout = configuration.requestTimeout;
    try {
      final request =
          await client.getUrl(uri).timeout(configuration.requestTimeout)
            ..followRedirects = false;
      _headers(request, installAdmission: admissionId, installProof: proof);
      request.contentLength = 0;
      final response = await request.close().timeout(
        configuration.requestTimeout,
      );
      final bytes = await _readResponse(
        response,
        maxBytes: _maxArtifactBytes,
      ).timeout(configuration.requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HyfensControlPlaneDeliveryException(
          'ARTIFACT_HTTP_${response.statusCode}',
          'Authenticated artifact fetch failed',
          statusCode: response.statusCode,
        );
      }
      final contentLength = response.contentLength;
      if (contentLength >= 0 && contentLength != bytes.length) {
        throw const HyfensControlPlaneDeliveryException(
          'ARTIFACT_CONTENT_LENGTH_MISMATCH',
          'Artifact response content length is inconsistent',
        );
      }
      final etag = response.headers.value('etag');
      if (etag != null && _normalizeTransportDigest(etag) != null) {
        final transportDigest = _normalizeTransportDigest(etag)!;
        if (transportDigest != _digestBytes(bytes)) {
          throw const HyfensControlPlaneDeliveryException(
            'ARTIFACT_ETAG_MISMATCH',
            'Artifact response ETag does not match its bytes',
          );
        }
      }
      final digest = response.headers.value('digest');
      if (digest != null && _normalizeTransportDigest(digest) != null) {
        final transportDigest = _normalizeTransportDigest(digest)!;
        if (transportDigest != _digestBytes(bytes)) {
          throw const HyfensControlPlaneDeliveryException(
            'ARTIFACT_HEADER_DIGEST_MISMATCH',
            'Artifact response digest does not match its bytes',
          );
        }
      }
      return bytes;
    } on HyfensControlPlaneDeliveryException {
      rethrow;
    } on TimeoutException {
      throw const HyfensControlPlaneDeliveryException(
        'DELIVERY_TIMEOUT',
        'Authenticated artifact fetch timed out',
      );
    } on Object {
      throw const HyfensControlPlaneDeliveryException(
        'DELIVERY_UNAVAILABLE',
        'Authenticated artifact fetch was unavailable',
      );
    } finally {
      client.close(force: true);
    }
  }

  void _headers(
    HttpClientRequest request, {
    bool json = false,
    String? installAdmission,
    String? installProof,
  }) {
    request.headers
      ..set(
        HttpHeaders.authorizationHeader,
        'Bearer ${configuration.deliveryCredential}',
      )
      ..set(HttpHeaders.acceptHeader, json ? 'application/json' : '*/*')
      ..set('X-Hyfens-Client', 'flutter-runtime-v1');
    if (installAdmission != null) {
      request.headers.set('X-Hyfens-Install-Admission', installAdmission);
    }
    if (installProof != null) {
      request.headers.set('X-Hyfens-Install-Proof', installProof);
    }
    if (json) request.headers.contentType = ContentType.json;
  }

  Future<List<int>> _readResponse(
    HttpClientResponse response, {
    required int maxBytes,
  }) async {
    if (response.contentLength > maxBytes) {
      throw const HyfensControlPlaneDeliveryException(
        'RESPONSE_TOO_LARGE',
        'Delivery response exceeds the runtime transport bound',
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (chunk.length > maxBytes - builder.length) {
        throw const HyfensControlPlaneDeliveryException(
          'RESPONSE_TOO_LARGE',
          'Delivery response exceeds the runtime transport bound',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  HyfensDeliveryDecision _decision(String value) => switch (value) {
    'NO_UPDATE' => HyfensDeliveryDecision.noUpdate,
    'PATCH_AVAILABLE' => HyfensDeliveryDecision.patchAvailable,
    'UPDATE_BLOCKED' => HyfensDeliveryDecision.updateBlocked,
    'STORE_RELEASE_REQUIRED' => HyfensDeliveryDecision.storeReleaseRequired,
    _ => throw HyfensControlPlaneDeliveryException(
      'UNKNOWN_DECISION',
      'Control plane returned an unsupported delivery decision',
    ),
  };

  static Map<String, Object?> _object(Map<String, Object?> value, String key) =>
      _objectValue(value[key], key);

  static Map<String, Object?> _objectValue(Object? value, String name) {
    if (value is! Map<String, Object?>) {
      throw HyfensControlPlaneDeliveryException(
        'MALFORMED_RESPONSE',
        '$name must be a JSON object',
      );
    }
    return value;
  }

  static String _string(Map<String, Object?> value, String key) {
    final item = value[key];
    if (item is! String || item.isEmpty) {
      throw HyfensControlPlaneDeliveryException(
        'MALFORMED_RESPONSE',
        'Delivery response field $key is invalid',
      );
    }
    return item;
  }

  static String _requiredString(
    Map<String, Object?> value,
    List<String> keys,
    String name,
  ) {
    for (final key in keys) {
      final item = value[key];
      if (item is String && item.isNotEmpty) return item;
    }
    throw HyfensControlPlaneDeliveryException(
      'MALFORMED_RESPONSE',
      'Delivery response field $name is invalid',
    );
  }

  static String? _optionalString(
    Map<String, Object?> value,
    List<String> keys,
  ) {
    for (final key in keys) {
      final item = value[key];
      if (item == null) continue;
      if (item is String && item.isNotEmpty) return item;
      throw const HyfensControlPlaneDeliveryException(
        'MALFORMED_RESPONSE',
        'Delivery response string field is invalid',
      );
    }
    return null;
  }

  static int _requiredInt(
    Map<String, Object?> value,
    List<String> keys,
    String name,
  ) {
    for (final key in keys) {
      final item = value[key];
      if (item is int && item >= 0) return item;
    }
    throw HyfensControlPlaneDeliveryException(
      'MALFORMED_RESPONSE',
      'Delivery response field $name is invalid',
    );
  }

  static String _digest(String value) {
    final normalized = value.startsWith('sha256:')
        ? value.substring('sha256:'.length)
        : value;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw const HyfensControlPlaneDeliveryException(
        'MALFORMED_RESPONSE',
        'Delivery response digest is invalid',
      );
    }
    return 'sha256:$normalized';
  }

  static String _patchReferenceDigest(String digest) =>
      digest.startsWith('sha256:')
      ? digest.substring('sha256:'.length)
      : digest;

  static void _validateBoundedString(String value, String name) {
    if (value.length > 256 || value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw HyfensControlPlaneDeliveryException(
        'MALFORMED_RESPONSE',
        'Delivery response field $name is invalid',
      );
    }
  }

  static bool _sameOrigin(Uri left, Uri right) =>
      left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
      left.host.toLowerCase() == right.host.toLowerCase() &&
      left.port == right.port;

  static bool _retryableArtifactError(
    HyfensControlPlaneDeliveryException error,
  ) {
    if (error.code == 'DELIVERY_TIMEOUT' ||
        error.code == 'DELIVERY_UNAVAILABLE') {
      return true;
    }
    const prefix = 'ARTIFACT_HTTP_';
    if (!error.code.startsWith(prefix)) return false;
    final statusCode = int.tryParse(error.code.substring(prefix.length));
    return statusCode == HttpStatus.requestTimeout ||
        statusCode == HttpStatus.tooManyRequests ||
        statusCode != null && statusCode >= 500;
  }

  static String _digestBytes(List<int> bytes) =>
      'sha256:${sha256.convert(bytes).toString()}';

  static String? _normalizeTransportDigest(String value) {
    final trimmed = value.trim();
    final unquoted =
        trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')
        ? trimmed.substring(1, trimmed.length - 1)
        : trimmed;
    if (RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(unquoted)) return unquoted;
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(unquoted)) {
      return 'sha256:$unquoted';
    }
    return null;
  }
}

final class HyfensControlPlaneDeliveryException implements Exception {
  const HyfensControlPlaneDeliveryException(
    this.code,
    this.message, {
    this.statusCode,
  });

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'HyfensControlPlaneDeliveryException($code): $message';
}
