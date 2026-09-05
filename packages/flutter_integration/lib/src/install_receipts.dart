import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:patch_loading_e1/patch_loading_e1.dart';

import 'installation_key.dart';
import 'runtime_attestation.dart';

/// Receipt mode is explicit. Ordinary self-host runtimes do not enroll keys or
/// contact a commercial service. Acceptance never upgrades itself to billable.
enum HyfensInstallReceiptMode {
  disabled,
  developmentAcceptance,
  production;

  static HyfensInstallReceiptMode parse(String value) => switch (value) {
    '' || 'disabled' => disabled,
    'development_acceptance' => developmentAcceptance,
    'production' => production,
    _ => throw const FormatException('Unsupported install receipt mode'),
  };
}

final class HyfensInstallReceiptException implements Exception {
  const HyfensInstallReceiptException(this.code);
  final String code;
  @override
  String toString() => 'HyfensInstallReceiptException($code)';
}

/// The device sender signs only enrollment contexts bound to this installation
/// and receipts already committed to the controller's healthy-patch outbox.
/// Neither an enrollment signature nor a download produces an install receipt.
final class HyfensInstallReceipts {
  HyfensInstallReceipts({
    required Uri baseUrl,
    required String deliveryCredential,
    required String applicationId,
    required String environmentId,
    required String platformId,
    required HyfensInstallationKeyStore keyStore,
    Duration requestTimeout = const Duration(seconds: 8),
    DateTime Function()? clock,
  }) : this._internal(
         baseUrl: baseUrl,
         deliveryCredential: deliveryCredential,
         applicationId: applicationId,
         environmentId: environmentId,
         platformId: platformId,
         keyStore: keyStore,
         requestTimeout: requestTimeout,
         clock: clock,
         receiptMode: HyfensInstallReceiptMode.developmentAcceptance,
         attestationProducer: null,
         productionGate: null,
       );

  /// Creates the explicitly gated production receipt client.
  ///
  /// Production registration carries provider evidence outside the signed
  /// enrollment and receipt bodies. A missing or disabled provider is an
  /// error; the development client is never used as a fallback.
  factory HyfensInstallReceipts.production({
    required Uri baseUrl,
    required String deliveryCredential,
    required String applicationId,
    required String environmentId,
    required String platformId,
    required HyfensInstallationKeyStore keyStore,
    required HyfensRuntimeAttestationEvidenceProducer attestationProducer,
    required bool Function() productionGate,
    Duration requestTimeout = const Duration(seconds: 8),
    DateTime Function()? clock,
  }) {
    if (!_productionGateEnabled(productionGate)) {
      throw const HyfensRuntimeAttestationException(
        HyfensRuntimeAttestationException.productionNotEnabled,
      );
    }
    return HyfensInstallReceipts._internal(
      baseUrl: baseUrl,
      deliveryCredential: deliveryCredential,
      applicationId: applicationId,
      environmentId: environmentId,
      platformId: platformId,
      keyStore: keyStore,
      requestTimeout: requestTimeout,
      clock: clock,
      receiptMode: HyfensInstallReceiptMode.production,
      attestationProducer: attestationProducer,
      productionGate: productionGate,
    );
  }

  HyfensInstallReceipts._internal({
    required this.baseUrl,
    required this.deliveryCredential,
    required this.applicationId,
    required this.environmentId,
    required this.platformId,
    required this.keyStore,
    required Duration requestTimeout,
    DateTime Function()? clock,
    required HyfensInstallReceiptMode receiptMode,
    required HyfensRuntimeAttestationEvidenceProducer? attestationProducer,
    required bool Function()? productionGate,
  }) : requestTimeout = requestTimeout,
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _receiptMode = receiptMode,
       _attestationProducer = attestationProducer,
       _productionGate = productionGate {
    final loopback =
        baseUrl.host == 'localhost' ||
        (InternetAddress.tryParse(baseUrl.host)?.isLoopback ?? false);
    if (!baseUrl.hasAuthority ||
        baseUrl.userInfo.isNotEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment ||
        !(baseUrl.scheme == 'https' || baseUrl.scheme == 'http' && loopback) ||
        deliveryCredential.isEmpty ||
        deliveryCredential.contains(RegExp(r'[\r\n]')) ||
        requestTimeout <= Duration.zero) {
      throw const HyfensInstallReceiptException('INVALID_CONFIGURATION');
    }
    if (receiptMode == HyfensInstallReceiptMode.production &&
        (attestationProducer == null || productionGate == null)) {
      throw const HyfensRuntimeAttestationException(
        HyfensRuntimeAttestationException.productionNotEnabled,
      );
    }
  }

  static const runtimeVersion = 'hyfens-runtime/0.1.0';
  static const _maxResponseBytes = 32 * 1024;
  static const _maxRequestBytes = 32 * 1024;
  static const _maxProductionRegisterRequestBytes = 128 * 1024;
  static const _enrollmentFields = <String>{
    'version',
    'purpose',
    'challenge_id',
    'challenge',
    'expires_at',
    'application_id',
    'environment_id',
    'runtime_application_id',
    'release_id',
    'platform',
    'patch_id',
    'artifact_digest',
    'installation_id',
    'key_id',
    'public_key',
  };
  final Uri baseUrl;
  final String deliveryCredential;
  final String applicationId;
  final String environmentId;
  final String platformId;
  final HyfensInstallationKeyStore keyStore;
  final Duration requestTimeout;
  final DateTime Function() _clock;
  final HyfensInstallReceiptMode _receiptMode;
  final HyfensRuntimeAttestationEvidenceProducer? _attestationProducer;
  final bool Function()? _productionGate;
  int _nextReceipt = 0;

  HyfensInstallReceiptMode get receiptMode => _receiptMode;
  bool get isProduction => _receiptMode == HyfensInstallReceiptMode.production;

  Future<E1InstallReceiptContext> prepare({
    required String runtimeApplicationId,
    required String releaseId,
    required String patchId,
    required String artifactDigest,
  }) async {
    _ensureProductionReady();
    final normalizedArtifactDigest = _normalizeArtifactDigest(artifactDigest);
    final identity = await keyStore.getIdentity();
    final scope = <String, Object?>{
      'application_id': applicationId,
      'environment_id': environmentId,
      'runtime_application_id': runtimeApplicationId,
      'release_id': releaseId,
      'platform': platformId,
      'patch_id': patchId,
      'artifact_digest': normalizedArtifactDigest,
      'installation_id': identity.installationId,
      'key_id': identity.keyId,
    };
    final challenge = await _post('/v1/runtime/installations/challenge', {
      ...scope,
      'public_key': _base64(identity.publicKey),
    });
    final enrollment = _object(challenge['enrollment']);
    if (challenge['billable'] != false ||
        enrollment.keys.toSet().difference(_enrollmentFields).isNotEmpty ||
        enrollment.length != _enrollmentFields.length ||
        enrollment['version'] != 1 ||
        enrollment['purpose'] != 'installation_enrollment' ||
        enrollment['public_key'] != _base64(identity.publicKey)) {
      throw const HyfensInstallReceiptException('ENROLLMENT_INVALID');
    }
    _matches(enrollment, scope);
    _boundedString(enrollment['challenge_id']);
    _boundedString(enrollment['challenge']);
    _validateExpiry(enrollment['expires_at']);
    final canonicalEnrollment = List<int>.unmodifiable(_canonical(enrollment));
    final signature = await keyStore.sign(canonicalEnrollment);
    _validateSignature(signature);
    final register = <String, Object?>{
      'enrollment': enrollment,
      'signature': _base64(signature),
    };
    if (isProduction) {
      final producer = _attestationProducer!;
      final evidence = await _produceAttestation(
        producer,
        canonicalEnrollment,
        requestTimeout,
      );
      register['attestation'] = evidence.toMap();
    }
    final response = await _post(
      '/v1/runtime/installations/register',
      register,
      maxRequestBytes: isProduction
          ? _maxProductionRegisterRequestBytes
          : _maxRequestBytes,
    );
    final responseIsValid = isProduction
        ? response['billable'] == true &&
              (response['trust_level'] == 'ATTESTED_APP' ||
                  response['trust_level'] == 'ATTESTED_HARDWARE')
        : response['billable'] == false &&
              response['trust_level'] == 'DEVELOPMENT_ACCEPTANCE';
    if (!responseIsValid) {
      throw const HyfensInstallReceiptException('TRUST_MODE_MISMATCH');
    }
    final responseDeadline = _validateExpiry(response['expires_at']);
    final context = E1InstallReceiptContext(body: _object(response['receipt']));
    if (response['expires_at'] != context.activationDeadline ||
        responseDeadline != DateTime.parse(context.activationDeadline)) {
      throw const HyfensInstallReceiptException('ACTIVATION_DEADLINE_MISMATCH');
    }
    _matches(context.body, scope);
    if (context.runtimeVersion != runtimeVersion) {
      throw const HyfensInstallReceiptException('RUNTIME_VERSION_MISMATCH');
    }
    return context;
  }

  /// Sends a bounded batch. Failure leaves exact unsigned receipt bodies in the
  /// durable journal; signatures can safely be regenerated after restart.
  Future<int> flush(E1PatchController controller) async {
    var acknowledged = 0;
    final pending = controller.pendingInstallReceipts;
    if (pending.isEmpty) return 0;
    final start = _nextReceipt % pending.length;
    final count = pending.length < 8 ? pending.length : 8;
    _nextReceipt = (start + count) % pending.length;
    var failed = false;
    for (var index = 0; index < count; index++) {
      final context = pending[(start + index) % pending.length];
      try {
        if (context.runtimeApplicationId != controller.appId ||
            context.releaseId != controller.releaseId) {
          throw const HyfensInstallReceiptException('OUTBOX_SCOPE_MISMATCH');
        }
        await send(context);
        if (await controller.ackInstallReceipt(context.receiptId))
          acknowledged++;
      } on Object {
        // Retain failed evidence, but do not let one rejected receipt starve
        // later valid receipts. The next poll advances through the bounded queue.
        failed = true;
      }
    }
    if (failed && acknowledged == 0) {
      throw const HyfensInstallReceiptException('RECEIPTS_REMAIN_QUEUED');
    }
    return acknowledged;
  }

  /// The caller must obtain [context] from the healthy-patch controller outbox.
  /// The server independently validates its admission and signature; a public
  /// client API is never the production billing authority.
  Future<void> send(E1InstallReceiptContext context) async {
    await _identityForContext(context);
    final signature = await keyStore.sign(_canonical(context.body));
    _validateSignature(signature);
    final response = await _post('/v1/runtime/install-success', {
      ...context.body,
      'signature': _base64(signature),
    });
    if (response['receipt_id'] != context.receiptId ||
        response['accepted'] != true ||
        response['billable'] != isProduction) {
      throw const HyfensInstallReceiptException('ACKNOWLEDGEMENT_INVALID');
    }
  }

  /// Signs the admission-bound proof carried by an artifact GET request.
  ///
  /// This is deliberately a different message from [send]: the receipt's
  /// `result` field is removed and the artifact-download purpose and server
  /// artifact ID are added. The returned value is only a transport header;
  /// it is not an install-success receipt signature.
  Future<String> downloadProof(
    E1InstallReceiptContext context,
    String artifactId,
  ) async {
    await _identityForContext(context);
    _boundedString(artifactId);
    _validateExpiry(context.activationDeadline);
    final proofBody = <String, Object?>{
      for (final entry in context.body.entries)
        if (entry.key != 'result') entry.key: entry.value,
      'purpose': 'artifact_download',
      'artifact_id': artifactId,
    };
    final signature = await keyStore.sign(_canonical(proofBody));
    _validateSignature(signature);
    return _base64(signature);
  }

  Future<HyfensInstallationIdentity> _identityForContext(
    E1InstallReceiptContext context,
  ) async {
    final identity = await keyStore.getIdentity();
    _matches(context.body, {
      'application_id': applicationId,
      'environment_id': environmentId,
      'platform': platformId,
      'installation_id': identity.installationId,
      'key_id': identity.keyId,
      'runtime_version': runtimeVersion,
    });
    return identity;
  }

  DateTime _validateExpiry(Object? value) {
    final expires = value is String ? DateTime.tryParse(value) : null;
    final now = _clock().toUtc();
    if (expires == null ||
        !expires.isUtc ||
        !expires.isAfter(now) ||
        expires.isAfter(now.add(const Duration(days: 7)))) {
      throw const HyfensInstallReceiptException('ADMISSION_EXPIRY_INVALID');
    }
    return expires;
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body, {
    int maxRequestBytes = _maxRequestBytes,
  }) async {
    final client = HttpClient()..connectionTimeout = requestTimeout;
    try {
      final prefix = baseUrl.path.replaceFirst(RegExp(r'/$'), '');
      final request = await client
          .postUrl(baseUrl.replace(path: '$prefix$path'))
          .timeout(requestTimeout);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $deliveryCredential',
      );
      final bytes = utf8.encode(jsonEncode(body));
      if (bytes.length > maxRequestBytes) {
        throw const HyfensInstallReceiptException('REQUEST_TOO_LARGE');
      }
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode != HttpStatus.ok || response.isRedirect) {
        throw HyfensInstallReceiptException(
          'RECEIPT_HTTP_${response.statusCode}',
        );
      }
      final received = await _readResponse(response).timeout(requestTimeout);
      return _object(jsonDecode(utf8.decode(received)));
    } on HyfensInstallReceiptException {
      rethrow;
    } on Object {
      // Do not log credentials, response bodies, or private endpoint URLs.
      throw const HyfensInstallReceiptException('RECEIPT_SERVICE_UNAVAILABLE');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> _readResponse(HttpClientResponse response) async {
    if (response.contentLength > _maxResponseBytes) {
      throw const HyfensInstallReceiptException('RESPONSE_TOO_LARGE');
    }
    final received = <int>[];
    await for (final chunk in response.timeout(requestTimeout)) {
      if (chunk.length > _maxResponseBytes - received.length) {
        throw const HyfensInstallReceiptException('RESPONSE_TOO_LARGE');
      }
      received.addAll(chunk);
    }
    return received;
  }

  static void _matches(
    Map<String, Object?> actual,
    Map<String, Object?> expected,
  ) {
    for (final entry in expected.entries) {
      if (actual[entry.key] != entry.value) {
        throw const HyfensInstallReceiptException('RECEIPT_SCOPE_MISMATCH');
      }
    }
  }

  void _ensureProductionReady() {
    if (!isProduction ||
        _attestationProducer == null ||
        !_productionGateEnabled(_productionGate)) {
      if (isProduction) {
        throw const HyfensRuntimeAttestationException(
          HyfensRuntimeAttestationException.productionNotEnabled,
        );
      }
      return;
    }
  }

  static Future<HyfensRuntimeAttestationEvidence> _produceAttestation(
    HyfensRuntimeAttestationEvidenceProducer producer,
    List<int> canonicalEnrollment,
    Duration timeout,
  ) async {
    try {
      final evidence = await producer
          .produce(canonicalEnrollment)
          .timeout(timeout);
      return evidence;
    } on HyfensRuntimeAttestationException {
      rethrow;
    } on Object {
      throw const HyfensRuntimeAttestationException(
        HyfensRuntimeAttestationException.unavailable,
      );
    }
  }

  static bool _productionGateEnabled(bool Function()? gate) {
    if (gate == null) return false;
    try {
      return gate();
    } on Object {
      return false;
    }
  }

  static String _normalizeArtifactDigest(String value) {
    final normalized = value.startsWith('sha256:')
        ? value.substring('sha256:'.length)
        : value;
    if ((value.length != 64 && value.length != 71) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw const HyfensInstallReceiptException('ARTIFACT_DIGEST_INVALID');
    }
    return normalized;
  }

  static void _boundedString(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 256 ||
        value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const HyfensInstallReceiptException('ENROLLMENT_INVALID');
    }
  }

  static void _validateSignature(List<int> value) {
    if (value.length != 64 || value.any((byte) => byte < 0 || byte > 255)) {
      throw const HyfensInstallReceiptException('SIGNATURE_INVALID');
    }
  }

  static Map<String, Object?> _object(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const HyfensInstallReceiptException('RESPONSE_INVALID');
    }
    return value;
  }

  static List<int> _canonical(Map<String, Object?> value) => utf8.encode(
    jsonEncode({
      for (final key in value.keys.toList()..sort()) key: value[key],
    }),
  );
  static String _base64(List<int> value) =>
      base64Url.encode(value).replaceAll('=', '');
}
