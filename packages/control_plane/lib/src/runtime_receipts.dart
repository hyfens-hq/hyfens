import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import 'encoding.dart';
import 'errors.dart';
import 'persistence.dart';

const int runtimeReceiptSchemaVersion = 1;
const String runtimeReceiptRuntimeVersion = 'hyfens-runtime/0.1.0';

/// Trust is intentionally a lattice-shaped protocol value rather than a
/// boolean. Provider evidence can strengthen an installation, but it never
/// replaces the installation key or the server admission.
enum RuntimeTrustLevel {
  developmentAcceptance('DEVELOPMENT_ACCEPTANCE'),
  signedInstallation('SIGNED_INSTALLATION'),
  attestedApplication('ATTESTED_APP'),
  attestedDevice('ATTESTED_HARDWARE'),
  productionBillable('PRODUCTION_BILLABLE');

  const RuntimeTrustLevel(this.wireName);

  final String wireName;
}

final class RuntimeReceiptScope {
  RuntimeReceiptScope({
    required String applicationId,
    required String environmentId,
    required String runtimeApplicationId,
    required String releaseId,
    required String platform,
    required String patchId,
    required String artifactDigest,
    required String installationId,
    required String keyId,
    required String? publicKey,
  }) : applicationId = _bounded(applicationId, 'application_id'),
       environmentId = _bounded(environmentId, 'environment_id'),
       runtimeApplicationId = requireRuntimeIdentity(
         runtimeApplicationId,
         'runtime application ID',
       ),
       releaseId = _bounded(releaseId, 'release_id'),
       platform = _bounded(platform, 'platform'),
       patchId = _bounded(patchId, 'patch_id'),
       artifactDigest = _normalizedDigest(artifactDigest),
       installationId = _canonicalInstallationId(installationId),
       keyId = _keyId(keyId),
       publicKey = _canonicalPublicKey(publicKey) {
    final encoded = this.publicKey;
    if (encoded != null) {
      final calculated = crypto.sha256
          .convert(_decodeBase64Url(encoded, 'public_key'))
          .toString();
      if (calculated != this.keyId) {
        throw const FormatException('public key does not match key_id');
      }
    }
  }

  static const Set<String> challengeRequestKeys = <String>{
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

  static const Set<String> scopeKeys = <String>{
    'application_id',
    'environment_id',
    'runtime_application_id',
    'release_id',
    'platform',
    'patch_id',
    'artifact_digest',
    'installation_id',
    'key_id',
  };

  static const Set<String> receiptKeys = <String>{
    'admission_id',
    'activation_deadline',
    ...scopeKeys,
    'challenge',
    'receipt_id',
    'result',
    'runtime_version',
    'version',
  };

  final String applicationId;
  final String environmentId;
  final String runtimeApplicationId;
  final String releaseId;
  final String platform;
  final String patchId;

  /// Wire compatibility keeps the client’s existing unprefixed digest form.
  final String artifactDigest;
  final String installationId;
  final String keyId;
  final String? publicKey;

  factory RuntimeReceiptScope.fromChallengeRequest(Map<String, Object?> value) {
    _exactKeys(value, challengeRequestKeys, 'challenge request');
    return RuntimeReceiptScope(
      applicationId: _string(value, 'application_id'),
      environmentId: _string(value, 'environment_id'),
      runtimeApplicationId: _string(value, 'runtime_application_id'),
      releaseId: _string(value, 'release_id'),
      platform: _string(value, 'platform'),
      patchId: _string(value, 'patch_id'),
      artifactDigest: _string(value, 'artifact_digest'),
      installationId: _string(value, 'installation_id'),
      keyId: _string(value, 'key_id'),
      publicKey: _string(value, 'public_key'),
    );
  }

  factory RuntimeReceiptScope.fromReceipt(Map<String, Object?> value) {
    _exactKeys(value, receiptKeys, 'install receipt');
    if (value['version'] != runtimeReceiptSchemaVersion ||
        value['result'] != 'activated' ||
        value['runtime_version'] != runtimeReceiptRuntimeVersion) {
      throw const FormatException(
        'install receipt version or result is invalid',
      );
    }
    _timestamp(value['activation_deadline'], 'activation_deadline');
    return RuntimeReceiptScope(
      applicationId: _string(value, 'application_id'),
      environmentId: _string(value, 'environment_id'),
      runtimeApplicationId: _string(value, 'runtime_application_id'),
      releaseId: _string(value, 'release_id'),
      platform: _string(value, 'platform'),
      patchId: _string(value, 'patch_id'),
      artifactDigest: _string(value, 'artifact_digest'),
      installationId: _string(value, 'installation_id'),
      keyId: _string(value, 'key_id'),
      publicKey: null,
    );
  }

  Map<String, Object?> toWire() => <String, Object?>{
    'application_id': applicationId,
    'environment_id': environmentId,
    'runtime_application_id': runtimeApplicationId,
    'release_id': releaseId,
    'platform': platform,
    'patch_id': patchId,
    'artifact_digest': artifactDigest,
    'installation_id': installationId,
    'key_id': keyId,
  };

  Map<String, Object?> toChallengeRequest() => <String, Object?>{
    ...toWire(),
    'public_key': publicKey,
  };

  static String _string(Map<String, Object?> value, String key) {
    final item = value[key];
    if (item is! String) throw FormatException('Missing or invalid $key');
    return item;
  }

  static String _bounded(String value, String field) =>
      requireNonEmpty(value, field, maxLength: 256);

  static String _keyId(String value) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const FormatException('Invalid key_id');
    }
    return value;
  }

  static String _normalizedDigest(String value) {
    final normalized = requireSha256Digest(value);
    return normalized.substring('sha256:'.length);
  }

  static String _canonicalInstallationId(String value) {
    final bytes = _decodeBase64Url(value, 'installation_id');
    if (bytes.length != 32 ||
        base64Url.encode(bytes).replaceAll('=', '') != value) {
      throw const FormatException('Invalid installation_id');
    }
    return value;
  }

  static String? _canonicalPublicKey(String? value) {
    if (value == null) return null;
    final bytes = _decodeBase64Url(value, 'public_key');
    if (bytes.length != 65 ||
        bytes.first != 4 ||
        base64Url.encode(bytes).replaceAll('=', '') != value) {
      throw const FormatException('Invalid public_key');
    }
    return value;
  }
}

final class RuntimeEnrollment {
  RuntimeEnrollment({
    required this.scope,
    required String admissionId,
    required String challenge,
    required DateTime expiresAt,
  }) : admissionId = _boundedWire(admissionId, 'challenge_id'),
       challenge = _boundedWire(challenge, 'challenge'),
       expiresAt = _utcTimestamp(expiresAt, 'expires_at') {
    if (scope.publicKey == null) {
      throw const FormatException('Enrollment requires a public key');
    }
  }

  static const Set<String> wireKeys = <String>{
    'version',
    'purpose',
    'challenge_id',
    'challenge',
    'expires_at',
    ...RuntimeReceiptScope.scopeKeys,
    'public_key',
  };

  final RuntimeReceiptScope scope;
  final String admissionId;
  final String challenge;
  final DateTime expiresAt;

  factory RuntimeEnrollment.fromJson(Map<String, Object?> value) {
    _exactKeys(value, wireKeys, 'enrollment');
    if (value['version'] != runtimeReceiptSchemaVersion ||
        value['purpose'] != 'installation_enrollment') {
      throw const FormatException('Invalid enrollment version or purpose');
    }
    return RuntimeEnrollment(
      scope: RuntimeReceiptScope(
        applicationId: _string(value, 'application_id'),
        environmentId: _string(value, 'environment_id'),
        runtimeApplicationId: _string(value, 'runtime_application_id'),
        releaseId: _string(value, 'release_id'),
        platform: _string(value, 'platform'),
        patchId: _string(value, 'patch_id'),
        artifactDigest: _string(value, 'artifact_digest'),
        installationId: _string(value, 'installation_id'),
        keyId: _string(value, 'key_id'),
        publicKey: _string(value, 'public_key'),
      ),
      admissionId: _string(value, 'challenge_id'),
      challenge: _string(value, 'challenge'),
      expiresAt: _timestamp(value['expires_at'], 'expires_at'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': runtimeReceiptSchemaVersion,
    'purpose': 'installation_enrollment',
    'challenge_id': admissionId,
    'challenge': challenge,
    'expires_at': expiresAt.toIso8601String(),
    ...scope.toWire(),
    'public_key': scope.publicKey,
  };

  static String _string(Map<String, Object?> value, String key) {
    final item = value[key];
    if (item is! String) throw FormatException('Missing or invalid $key');
    return item;
  }
}

final class RuntimeReceiptAuthorization {
  const RuntimeReceiptAuthorization({
    required this.organizationId,
    required this.applicationId,
    required this.environmentId,
  });

  final String organizationId;
  final String applicationId;
  final String environmentId;
}

final class RuntimeAttestationEvidence {
  RuntimeAttestationEvidence._(this.body, this.provider, this.keyId)
    : digest = sha256Digest(utf8.encode(canonicalJson(body)));

  final Map<String, Object?> body;
  final String provider;
  final String? keyId;
  final String digest;

  factory RuntimeAttestationEvidence.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Attestation evidence must be an object');
    }
    final body = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) {
        throw const FormatException('Attestation evidence keys are invalid');
      }
      body[entry.key as String] = entry.value;
    }
    final provider = body['provider'];
    if (provider == 'google_play_integrity') {
      _exactKeys(body, const <String>{'provider', 'token'}, 'attestation');
      _opaque(body['token'], 'token', 64 * 1024);
      return RuntimeAttestationEvidence._(
        Map.unmodifiable(body),
        provider as String,
        null,
      );
    }
    if (provider == 'apple_app_attest') {
      final hasAttestation = body.containsKey('attestation_object');
      final hasAssertion = body.containsKey('assertion');
      if (body['key_id'] is! String || hasAttestation == hasAssertion) {
        throw const FormatException('Apple attestation evidence is invalid');
      }
      _boundedWire(body['key_id'], 'key_id');
      final key = hasAttestation ? 'attestation_object' : 'assertion';
      _exactKeys(body, <String>{'provider', 'key_id', key}, 'attestation');
      _opaque(body[key], key, 64 * 1024);
      return RuntimeAttestationEvidence._(
        Map.unmodifiable(body),
        provider as String,
        body['key_id']! as String,
      );
    }
    throw const FormatException('Unsupported attestation provider');
  }
}

final class RuntimeAttestationRequest {
  const RuntimeAttestationRequest({
    required this.scope,
    required this.evidence,
    required this.canonicalEnrollmentBytes,
  });

  final RuntimeReceiptScope scope;
  final RuntimeAttestationEvidence evidence;
  final List<int> canonicalEnrollmentBytes;
}

final class RuntimeAttestationVerification {
  const RuntimeAttestationVerification({
    required this.provider,
    required this.trustLevel,
    required this.verified,
    required this.evidenceDigest,
    required this.challengeBindingDigest,
    this.reason,
  });

  final String provider;
  final RuntimeTrustLevel trustLevel;
  final bool verified;
  final String evidenceDigest;

  /// Digest of the exact canonical enrollment bytes verified by the provider.
  ///
  /// A provider token/assertion is not sufficient if it is detached from the
  /// server-issued challenge. Provider adapters must verify that their
  /// platform-specific nonce/client-data binding covers these bytes.
  final String challengeBindingDigest;
  final String? reason;
}

final class RuntimeAttestationException implements Exception {
  const RuntimeAttestationException(this.code, this.message);

  static const unavailable = 'UNAVAILABLE';
  static const invalid = 'INVALID_EVIDENCE';
  static const rejected = 'REJECTED';

  final String code;
  final String message;

  @override
  String toString() => 'RuntimeAttestationException($code): $message';
}

/// Provider adapters receive already-bounded evidence and return a server
/// verification result. Provider SDKs, Google/Apple credentials, and network
/// calls stay outside the control-plane/domain package.
abstract interface class RuntimeAttestationVerifier {
  Future<RuntimeAttestationVerification> verify(
    RuntimeAttestationRequest request,
  );
}

abstract interface class RuntimeAttestationProviderDelegate {
  Future<RuntimeAttestationVerification> verify(
    RuntimeAttestationRequest request,
  );
}

final class AndroidPlayIntegrityAttestationVerifier
    implements RuntimeAttestationVerifier {
  const AndroidPlayIntegrityAttestationVerifier(this.delegate);

  final RuntimeAttestationProviderDelegate delegate;

  @override
  Future<RuntimeAttestationVerification> verify(
    RuntimeAttestationRequest request,
  ) async {
    if (request.evidence.provider != 'google_play_integrity') {
      throw const RuntimeAttestationException(
        RuntimeAttestationException.invalid,
        'Evidence provider does not match the Android adapter',
      );
    }
    return delegate.verify(request);
  }
}

final class AppleAppAttestVerifier implements RuntimeAttestationVerifier {
  const AppleAppAttestVerifier(this.delegate);

  final RuntimeAttestationProviderDelegate delegate;

  @override
  Future<RuntimeAttestationVerification> verify(
    RuntimeAttestationRequest request,
  ) async {
    if (request.evidence.provider != 'apple_app_attest') {
      throw const RuntimeAttestationException(
        RuntimeAttestationException.invalid,
        'Evidence provider does not match the Apple adapter',
      );
    }
    return delegate.verify(request);
  }
}

final class RuntimeReceiptPolicyInput {
  const RuntimeReceiptPolicyInput({
    required this.organizationId,
    required this.scope,
    required this.now,
    required this.challengeBindingDigest,
    this.attestation,
    this.verification,
  });

  final String organizationId;
  final RuntimeReceiptScope scope;
  final DateTime now;
  final String challengeBindingDigest;
  final RuntimeAttestationEvidence? attestation;
  final RuntimeAttestationVerification? verification;
}

final class RuntimeReceiptPolicyDecision {
  const RuntimeReceiptPolicyDecision({
    required this.accepted,
    required this.billable,
    required this.trustLevel,
    required this.reason,
  });

  final bool accepted;
  final bool billable;
  final RuntimeTrustLevel trustLevel;
  final String reason;
}

abstract interface class RuntimeReceiptAcceptancePolicy {
  Future<RuntimeReceiptPolicyDecision> evaluate(
    RuntimeReceiptPolicyInput input,
  );
}

/// Explicit development policy. The accepted environment list is mandatory;
/// a self-host deployment cannot accidentally make every environment billable
/// by constructing the default policy.
final class DevelopmentRuntimeReceiptPolicy
    implements RuntimeReceiptAcceptancePolicy {
  DevelopmentRuntimeReceiptPolicy({required Set<String> environmentIds})
    : environmentIds = Set.unmodifiable(environmentIds) {
    if (this.environmentIds.isEmpty) {
      throw ArgumentError.value(
        environmentIds,
        'environmentIds',
        'must contain at least one explicit acceptance environment',
      );
    }
  }

  final Set<String> environmentIds;

  @override
  Future<RuntimeReceiptPolicyDecision> evaluate(
    RuntimeReceiptPolicyInput input,
  ) async {
    if (!environmentIds.contains(input.scope.environmentId)) {
      return const RuntimeReceiptPolicyDecision(
        accepted: false,
        billable: false,
        trustLevel: RuntimeTrustLevel.developmentAcceptance,
        reason: 'ENVIRONMENT_NOT_ALLOWED_FOR_DEVELOPMENT_ACCEPTANCE',
      );
    }
    if (input.attestation != null || input.verification != null) {
      return const RuntimeReceiptPolicyDecision(
        accepted: false,
        billable: false,
        trustLevel: RuntimeTrustLevel.developmentAcceptance,
        reason: 'DEVELOPMENT_ACCEPTANCE_DOES_NOT_ACCEPT_PRODUCTION_EVIDENCE',
      );
    }
    return const RuntimeReceiptPolicyDecision(
      accepted: true,
      billable: false,
      trustLevel: RuntimeTrustLevel.developmentAcceptance,
      reason: 'DEVELOPMENT_ACCEPTANCE',
    );
  }
}

/// Production policy is explicit and requires an attestation result from an
/// injected provider adapter. Subscription plans, quotas, and overage pricing
/// remain a private Cloud policy layered on the canonical event.
final class AttestedProductionRuntimeReceiptPolicy
    implements RuntimeReceiptAcceptancePolicy {
  const AttestedProductionRuntimeReceiptPolicy({this.enabled = false});

  final bool enabled;

  @override
  Future<RuntimeReceiptPolicyDecision> evaluate(
    RuntimeReceiptPolicyInput input,
  ) async {
    final verification = input.verification;
    if (!enabled) {
      return const RuntimeReceiptPolicyDecision(
        accepted: false,
        billable: false,
        trustLevel: RuntimeTrustLevel.signedInstallation,
        reason: 'PRODUCTION_TRUST_POLICY_DISABLED',
      );
    }
    if (input.attestation == null || verification == null) {
      return const RuntimeReceiptPolicyDecision(
        accepted: false,
        billable: false,
        trustLevel: RuntimeTrustLevel.signedInstallation,
        reason: 'ATTESTATION_REQUIRED',
      );
    }
    if (!verification.verified ||
        verification.evidenceDigest != input.attestation!.digest ||
        verification.challengeBindingDigest != input.challengeBindingDigest ||
        verification.provider != input.attestation!.provider ||
        (verification.trustLevel != RuntimeTrustLevel.attestedApplication &&
            verification.trustLevel != RuntimeTrustLevel.attestedDevice)) {
      return const RuntimeReceiptPolicyDecision(
        accepted: false,
        billable: false,
        trustLevel: RuntimeTrustLevel.signedInstallation,
        reason: 'ATTESTATION_VERIFICATION_FAILED',
      );
    }
    return RuntimeReceiptPolicyDecision(
      accepted: true,
      billable: true,
      trustLevel: verification.trustLevel,
      reason: 'PRODUCTION_ATTESTED_INSTALLATION',
    );
  }
}

final class RuntimeReceiptSettlement {
  RuntimeReceiptSettlement({
    required this.store,
    required this.policy,
    this.attestationVerifier,
    Random? random,
    DateTime Function()? clock,
    this.admissionLifetime = const Duration(minutes: 5),
    this.receiptDeliveryGrace = const Duration(hours: 24),
  }) : _random = random ?? Random.secure(),
       _clock = clock ?? (() => DateTime.now().toUtc()) {
    if (admissionLifetime <= Duration.zero ||
        admissionLifetime > const Duration(days: 7) ||
        receiptDeliveryGrace < Duration.zero ||
        receiptDeliveryGrace > const Duration(days: 7)) {
      throw ArgumentError('Runtime receipt lifetimes are outside safe bounds');
    }
  }

  final RuntimeReceiptStore store;
  final RuntimeReceiptAcceptancePolicy policy;
  final RuntimeAttestationVerifier? attestationVerifier;
  final Random _random;
  final DateTime Function() _clock;
  final Duration admissionLifetime;
  final Duration receiptDeliveryGrace;

  Future<Map<String, Object?>> issueChallenge({
    required String organizationId,
    required Map<String, Object?> request,
  }) async {
    final scope = RuntimeReceiptScope.fromChallengeRequest(request);
    final now = _clock().toUtc();
    final enrollment = RuntimeEnrollment(
      scope: scope,
      admissionId: _newId('adm'),
      challenge: _randomOpaque(),
      expiresAt: now.add(admissionLifetime),
    );
    await store.createRuntimeAdmission(
      enrollment.admissionId,
      <String, Object?>{
        'organizationId': _boundedWire(organizationId, 'organization_id'),
        'admissionId': enrollment.admissionId,
        'enrollment': enrollment.toJson(),
        'createdAt': now.toIso8601String(),
      },
    );
    return <String, Object?>{
      'enrollment': enrollment.toJson(),
      // Challenge issuance never authorizes a financial event.
      'billable': false,
    };
  }

  Future<Map<String, Object?>> register({
    required String organizationId,
    required Map<String, Object?> request,
  }) async {
    try {
      return await _register(organizationId: organizationId, request: request);
    } on ControlPlaneException catch (error) {
      await _recordRejection(
        organizationId: organizationId,
        operation: 'register',
        request: request,
        error: error,
      );
      rethrow;
    } on FormatException {
      await _recordFormatRejection(
        organizationId: organizationId,
        operation: 'register',
        request: request,
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> _register({
    required String organizationId,
    required Map<String, Object?> request,
  }) async {
    _requireRegistrationKeys(request);
    final enrollment = _object(request['enrollment'], 'enrollment');
    final parsed = RuntimeEnrollment.fromJson(enrollment);
    final admission = await store.readRuntimeAdmission(parsed.admissionId);
    if (admission == null || admission['organizationId'] != organizationId) {
      throw const ControlPlaneException(
        'ADMISSION_INVALID',
        'The installation admission is not valid for this organization',
        statusCode: 403,
      );
    }
    final storedEnrollment = _object(admission['enrollment'], 'enrollment');
    if (canonicalJson(storedEnrollment) != canonicalJson(parsed.toJson())) {
      throw const ControlPlaneException(
        'ADMISSION_SCOPE_MISMATCH',
        'The enrollment does not match the server-issued admission',
        statusCode: 403,
      );
    }
    final enrollmentBytes = utf8.encode(canonicalJson(parsed.toJson()));
    if (!_verifySignature(
      parsed.scope.publicKey!,
      enrollmentBytes,
      _base64Bytes(request['signature'], 'signature', 64),
    )) {
      throw const ControlPlaneException(
        'SIGNATURE_INVALID',
        'The installation enrollment signature is invalid',
        statusCode: 403,
      );
    }

    final attestation = request.containsKey('attestation')
        ? RuntimeAttestationEvidence.fromJson(request['attestation'])
        : null;
    final registrationDigest = sha256Digest(
      utf8.encode(
        canonicalJson(<String, Object?>{
          'enrollment': parsed.toJson(),
          if (attestation != null) 'attestation': attestation.body,
        }),
      ),
    );
    final existingRegistration = await store.readRuntimeRegistration(
      parsed.admissionId,
    );
    if (existingRegistration != null) {
      if (existingRegistration['registrationDigest'] != registrationDigest) {
        throw const ControlPlaneException(
          'ADMISSION_REPLAY',
          'The admission was already registered for different evidence',
          statusCode: 409,
        );
      }
      return _object(existingRegistration['response'], 'registration response');
    }

    if (!_clock().toUtc().isBefore(parsed.expiresAt)) {
      throw const ControlPlaneException(
        'ADMISSION_EXPIRED',
        'The installation admission has expired',
        statusCode: 403,
      );
    }

    RuntimeAttestationVerification? verification;
    if (attestation != null) {
      final verifier = attestationVerifier;
      if (verifier == null) {
        throw const ControlPlaneException(
          'ATTESTATION_UNAVAILABLE',
          'No production attestation verifier is configured',
          statusCode: 503,
        );
      }
      try {
        verification = await verifier.verify(
          RuntimeAttestationRequest(
            scope: parsed.scope,
            evidence: attestation,
            canonicalEnrollmentBytes: List<int>.unmodifiable(enrollmentBytes),
          ),
        );
      } on RuntimeAttestationException catch (error) {
        throw ControlPlaneException(
          error.code == RuntimeAttestationException.unavailable
              ? 'ATTESTATION_UNAVAILABLE'
              : 'ATTESTATION_REJECTED',
          error.message,
          statusCode: error.code == RuntimeAttestationException.unavailable
              ? 503
              : 403,
        );
      }
    }
    final decision = await policy.evaluate(
      RuntimeReceiptPolicyInput(
        organizationId: organizationId,
        scope: parsed.scope,
        now: _clock().toUtc(),
        challengeBindingDigest: sha256Digest(enrollmentBytes),
        attestation: attestation,
        verification: verification,
      ),
    );
    if (!decision.accepted) {
      throw ControlPlaneException(
        'RUNTIME_TRUST_REJECTED',
        'The runtime installation did not satisfy the configured trust policy',
        statusCode: 403,
        details: <String, Object?>{
          'reason': decision.reason,
          'trust_level': decision.trustLevel.wireName,
        },
      );
    }
    if (decision.billable &&
        (attestation == null ||
            verification == null ||
            !verification.verified ||
            verification.evidenceDigest != attestation.digest ||
            verification.challengeBindingDigest !=
                sha256Digest(enrollmentBytes) ||
            verification.provider != attestation.provider ||
            (decision.trustLevel != RuntimeTrustLevel.attestedApplication &&
                decision.trustLevel != RuntimeTrustLevel.attestedDevice))) {
      throw const ControlPlaneException(
        'RUNTIME_TRUST_REJECTED',
        'A billable runtime installation requires verified admission-bound attestation',
        statusCode: 403,
      );
    }

    final installationRecordId = _installationRecordId(
      organizationId,
      parsed.scope,
    );
    final installation = <String, Object?>{
      'organizationId': organizationId,
      'applicationId': parsed.scope.applicationId,
      'environmentId': parsed.scope.environmentId,
      'installationId': parsed.scope.installationId,
      'keyId': parsed.scope.keyId,
      'publicKey': parsed.scope.publicKey,
    };
    var existingInstallation = await store.readRuntimeInstallation(
      installationRecordId,
    );
    if (existingInstallation != null &&
        canonicalJson(existingInstallation) != canonicalJson(installation)) {
      throw const ControlPlaneException(
        'KEY_SUBSTITUTION',
        'The installation identity is already bound to another public key',
        statusCode: 403,
      );
    }
    if (existingInstallation == null) {
      try {
        await store.createRuntimeInstallation(
          installationRecordId,
          installation,
        );
      } on StorageConflict {
        existingInstallation = await store.readRuntimeInstallation(
          installationRecordId,
        );
        if (existingInstallation == null ||
            canonicalJson(existingInstallation) !=
                canonicalJson(installation)) {
          throw const ControlPlaneException(
            'KEY_SUBSTITUTION',
            'The installation identity is already bound to another public key',
            statusCode: 403,
          );
        }
      }
    }

    final receiptId = 'rcpt_${registrationDigest.substring(7)}';
    final receipt = <String, Object?>{
      'version': runtimeReceiptSchemaVersion,
      'receipt_id': receiptId,
      'admission_id': parsed.admissionId,
      'challenge': parsed.challenge,
      ...parsed.scope.toWire(),
      'runtime_version': runtimeReceiptRuntimeVersion,
      'activation_deadline': parsed.expiresAt.toIso8601String(),
      'result': 'activated',
    };
    final response = <String, Object?>{
      'billable': decision.billable,
      'trust_level': decision.trustLevel.wireName,
      'expires_at': parsed.expiresAt.toIso8601String(),
      'receipt': receipt,
    };
    final registration = <String, Object?>{
      'organizationId': organizationId,
      'registrationDigest': registrationDigest,
      'installationId': parsed.scope.installationId,
      'keyId': parsed.scope.keyId,
      'billable': decision.billable,
      'trustLevel': decision.trustLevel.wireName,
      'attestationDigest': attestation?.digest,
      'response': response,
    };
    try {
      await store.createRuntimeRegistration(parsed.admissionId, registration);
    } on StorageConflict {
      final persisted = await store.readRuntimeRegistration(parsed.admissionId);
      if (persisted == null ||
          persisted['registrationDigest'] != registrationDigest) {
        throw const ControlPlaneException(
          'ADMISSION_REPLAY',
          'The admission was already registered for different evidence',
          statusCode: 409,
        );
      }
      return _object(persisted['response'], 'registration response');
    }
    return response;
  }

  Future<Map<String, Object?>> settleInstall({
    required String organizationId,
    required Map<String, Object?> request,
  }) async {
    try {
      return await _settleInstall(
        organizationId: organizationId,
        request: request,
      );
    } on ControlPlaneException catch (error) {
      await _recordRejection(
        organizationId: organizationId,
        operation: 'settle',
        request: request,
        error: error,
      );
      rethrow;
    } on FormatException {
      await _recordFormatRejection(
        organizationId: organizationId,
        operation: 'settle',
        request: request,
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> _settleInstall({
    required String organizationId,
    required Map<String, Object?> request,
  }) async {
    _exactKeys(request, <String>{
      ...RuntimeReceiptScope.receiptKeys,
      'signature',
    }, 'install-success request');
    final body = <String, Object?>{
      for (final key in RuntimeReceiptScope.receiptKeys) key: request[key],
    };
    final scope = RuntimeReceiptScope.fromReceipt(body);
    final receiptId = _string(request, 'receipt_id');
    final admissionId = _string(request, 'admission_id');
    final admission = await store.readRuntimeAdmission(admissionId);
    if (admission == null || admission['organizationId'] != organizationId) {
      throw const ControlPlaneException(
        'ADMISSION_INVALID',
        'The receipt admission is not valid for this organization',
        statusCode: 403,
      );
    }
    final registration = await store.readRuntimeRegistration(admissionId);
    if (registration == null ||
        registration['organizationId'] != organizationId) {
      throw const ControlPlaneException(
        'REGISTRATION_REQUIRED',
        'The installation must be registered before successful activation',
        statusCode: 403,
      );
    }
    final response = _object(registration['response'], 'registration response');
    final registeredReceipt = _object(response['receipt'], 'receipt');
    if (canonicalJson(registeredReceipt) != canonicalJson(body) ||
        receiptId != registeredReceipt['receipt_id']) {
      throw const ControlPlaneException(
        'RECEIPT_SCOPE_MISMATCH',
        'The receipt does not match its server admission',
        statusCode: 403,
      );
    }
    final installation = await store.readRuntimeInstallation(
      _installationRecordId(organizationId, scope),
    );
    if (installation == null ||
        installation['keyId'] != scope.keyId ||
        installation['applicationId'] != scope.applicationId ||
        installation['environmentId'] != scope.environmentId) {
      throw const ControlPlaneException(
        'INSTALLATION_INVALID',
        'The receipt installation identity is not registered',
        statusCode: 403,
      );
    }
    final publicKey = installation['publicKey'];
    if (publicKey is! String ||
        !_verifySignature(
          publicKey,
          utf8.encode(canonicalJson(body)),
          _base64Bytes(request['signature'], 'signature', 64),
        )) {
      throw const ControlPlaneException(
        'SIGNATURE_INVALID',
        'The successful-install receipt signature is invalid',
        statusCode: 403,
      );
    }

    final existingReceipt = await store.readRuntimeReceipt(receiptId);
    final deadline = _timestamp(
      request['activation_deadline'],
      'activation_deadline',
    );
    if (existingReceipt == null &&
        _clock().toUtc().isAfter(deadline.add(receiptDeliveryGrace))) {
      throw const ControlPlaneException(
        'ADMISSION_EXPIRED',
        'The successful-install receipt delivery window has expired',
        statusCode: 403,
      );
    }

    final usageKey = canonicalJson(<String, Object?>{
      'organization_id': organizationId,
      'application_id': scope.applicationId,
      'environment_id': scope.environmentId,
      'installation_id': scope.installationId,
      'patch_id': scope.patchId,
    });
    final usageEventId = 'usage_${sha256Hex(utf8.encode(usageKey))}';
    final billable = response['billable'];
    final trustLevel = response['trust_level'];
    final parsedTrustLevel = trustLevel is String
        ? _trustLevelFromWire(trustLevel)
        : null;
    if (billable is! bool ||
        parsedTrustLevel == null ||
        (billable &&
            parsedTrustLevel != RuntimeTrustLevel.attestedApplication &&
            parsedTrustLevel != RuntimeTrustLevel.attestedDevice)) {
      throw const ControlPlaneException(
        'REGISTRATION_INVALID',
        'The stored runtime registration is invalid',
        statusCode: 500,
      );
    }
    final now = _clock().toUtc();
    final receiptRecord = <String, Object?>{
      'organizationId': organizationId,
      'receiptId': receiptId,
      'body': body,
      'usageEventId': usageEventId,
      'billable': billable,
      'trustLevel': parsedTrustLevel.wireName,
    };
    final usageEvent = <String, Object?>{
      'organizationId': organizationId,
      'eventType': 'successful_patch_install',
      'eventId': usageEventId,
      'usageKeyDigest': sha256Digest(utf8.encode(usageKey)),
      'receiptId': receiptId,
      'applicationId': scope.applicationId,
      'environmentId': scope.environmentId,
      'installationId': scope.installationId,
      'releaseId': scope.releaseId,
      'patchId': scope.patchId,
      'artifactDigest': scope.artifactDigest,
      'platform': scope.platform,
      'trustLevel': parsedTrustLevel.wireName,
      'billable': billable,
      // Acceptance telemetry is retained, but financial usage is always zero.
      'financialUsageUnits': billable ? 1 : 0,
      'usagePeriod': _period(now),
      'createdAt': now.toIso8601String(),
    };
    late final RuntimeReceiptCommitResult committed;
    try {
      committed = await store.commitRuntimeReceipt(
        receiptId: receiptId,
        receipt: receiptRecord,
        usageEventId: usageEventId,
        usageEvent: usageEvent,
      );
    } on StorageConflict {
      throw const ControlPlaneException(
        'RECEIPT_CONFLICT',
        'The successful-install receipt conflicts with an existing settlement',
        statusCode: 409,
      );
    }
    return <String, Object?>{
      'accepted': true,
      'billable': billable,
      'receipt_id': receiptId,
      'usage_event_id': usageEventId,
      'duplicate': !committed.createdReceipt,
    };
  }

  String _newId(String prefix) => '$prefix${_randomOpaque(12)}';

  String _randomOpaque([int length = 32]) => base64Url
      .encode(List<int>.generate(length, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  String _installationRecordId(
    String organizationId,
    RuntimeReceiptScope scope,
  ) =>
      'inst_${sha256Hex(utf8.encode(canonicalJson(<String, Object?>{'organization_id': organizationId, 'application_id': scope.applicationId, 'environment_id': scope.environmentId, 'installation_id': scope.installationId})))}';

  static String _period(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';

  Future<void> _recordRejection({
    required String organizationId,
    required String operation,
    required Map<String, Object?> request,
    required ControlPlaneException error,
  }) async {
    final details = <String, Object?>{
      for (final key in const <String>{'reason', 'trust_level'})
        if (error.details[key] is String) key: error.details[key],
    };
    await _recordRejectionValue(
      organizationId: organizationId,
      operation: operation,
      request: request,
      code: error.code,
      statusCode: error.statusCode,
      details: details,
    );
  }

  Future<void> _recordFormatRejection({
    required String organizationId,
    required String operation,
    required Map<String, Object?> request,
  }) => _recordRejectionValue(
    organizationId: organizationId,
    operation: operation,
    request: request,
    code: 'INVALID_REQUEST',
    statusCode: 400,
    details: const <String, Object?>{},
  );

  Future<void> _recordRejectionValue({
    required String organizationId,
    required String operation,
    required Map<String, Object?> request,
    required String code,
    required int statusCode,
    required Map<String, Object?> details,
  }) async {
    String requestDigest;
    try {
      requestDigest = sha256Digest(utf8.encode(canonicalJson(request)));
    } on Object {
      requestDigest = sha256Digest(utf8.encode(request.keys.join('\u0000')));
    }
    final record = <String, Object?>{
      'organizationId': organizationId,
      'operation': operation,
      'code': code,
      'statusCode': statusCode,
      'requestDigest': requestDigest,
      if (request['admission_id'] is String)
        'admissionId': request['admission_id'],
      if (request['receipt_id'] is String) 'receiptId': request['receipt_id'],
      if (details.isNotEmpty) 'details': details,
      'createdAt': _clock().toUtc().toIso8601String(),
    };
    try {
      await store.createRuntimeRejection(_newId('reject_'), record);
    } on Object {
      // Rejection telemetry must never turn a fail-closed decision into an
      // acceptance or mask the original client-visible error.
    }
  }

  static void _requireRegistrationKeys(Map<String, Object?> value) {
    final allowed = <String>{'enrollment', 'signature', 'attestation'};
    if (value.keys.toSet().difference(allowed).isNotEmpty ||
        !value.keys.toSet().containsAll(const <String>{
          'enrollment',
          'signature',
        })) {
      throw const FormatException('Registration fields are invalid');
    }
  }

  static Map<String, Object?> _object(Object? value, String field) {
    if (value is! Map) throw FormatException('$field must be an object');
    final result = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    if (result.length != value.length)
      throw FormatException('$field is invalid');
    return result;
  }

  static String _string(Map<String, Object?> value, String key) {
    final item = value[key];
    if (item is! String || item.isEmpty) throw FormatException('Invalid $key');
    return item;
  }

  static DateTime _timestamp(Object? value, String field) {
    if (value is! String) throw FormatException('Invalid $field');
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !parsed.isUtc)
      throw FormatException('Invalid $field');
    return parsed;
  }

  static void _exactKeys(
    Map<String, Object?> value,
    Set<String> expected,
    String field,
  ) {
    final actual = value.keys.toSet();
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      throw FormatException('$field fields are invalid');
    }
  }

  static List<int> _base64Bytes(Object? value, String field, int length) {
    if (value is! String) throw FormatException('Invalid $field');
    final bytes = _decodeBase64Url(value, field);
    if (bytes.length != length) throw FormatException('Invalid $field');
    return bytes;
  }

  static List<int> _decodeBase64Url(String value, String field) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(value));
      if (base64Url.encode(bytes).replaceAll('=', '') != value) {
        throw FormatException('Invalid $field');
      }
      return bytes;
    } on FormatException {
      rethrow;
    } on Object {
      throw FormatException('Invalid $field');
    }
  }

  static bool _verifySignature(
    String encodedPublicKey,
    List<int> message,
    List<int> rawSignature,
  ) {
    try {
      final publicBytes = _decodeBase64Url(encodedPublicKey, 'public_key');
      if (publicBytes.length != 65 || publicBytes.first != 4) return false;
      final signature = ECSignature(
        _bigInt(rawSignature.sublist(0, 32)),
        _bigInt(rawSignature.sublist(32)),
      );
      final curve = ECDomainParameters('prime256v1');
      final point = curve.curve.decodePoint(Uint8List.fromList(publicBytes));
      if (point == null ||
          point.isInfinity ||
          signature.r <= BigInt.zero ||
          signature.s <= BigInt.zero ||
          signature.r >= curve.n ||
          signature.s >= curve.n) {
        return false;
      }
      final verifier = ECDSASigner(SHA256Digest())
        ..init(
          false,
          PublicKeyParameter<ECPublicKey>(ECPublicKey(point, curve)),
        );
      return verifier.verifySignature(Uint8List.fromList(message), signature);
    } on Object {
      return false;
    }
  }

  static BigInt _bigInt(List<int> bytes) => bytes.fold(
    BigInt.zero,
    (value, byte) => (value << 8) | BigInt.from(byte),
  );
}

String _boundedWire(Object? value, String field) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 256 ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw FormatException('Invalid $field');
  }
  return value;
}

DateTime _timestamp(Object? value, String field) {
  if (value is! String) throw FormatException('Invalid $field');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) throw FormatException('Invalid $field');
  return parsed;
}

DateTime _utcTimestamp(DateTime value, String field) =>
    _timestamp(value.toUtc().toIso8601String(), field);

void _opaque(Object? value, String field, int maxLength) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw FormatException('Invalid attestation $field');
  }
}

RuntimeTrustLevel? _trustLevelFromWire(String value) {
  for (final level in RuntimeTrustLevel.values) {
    if (level.wireName == value) return level;
  }
  return null;
}

void _exactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String field,
) {
  final actual = value.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw FormatException('$field fields are invalid');
  }
}

List<int> _decodeBase64Url(String value, String field) {
  try {
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (base64Url.encode(bytes).replaceAll('=', '') != value) {
      throw FormatException('Invalid $field');
    }
    return bytes;
  } on FormatException {
    rethrow;
  } on Object {
    throw FormatException('Invalid $field');
  }
}
