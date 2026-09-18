import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_patch_format/patch_format.dart';

import 'domain.dart';
import 'encoding.dart';

/// The offline transport payload for one already admitted patch artifact.
///
/// The payload is intentionally unsigned. A control plane can export it after
/// authenticating the caller, but the customer-owned signing key remains at
/// the offline operator boundary. [ReleaseBundle.sign] wraps this payload in
/// the signed canonical envelope used for transport and import.
final class ReleaseBundlePayload {
  ReleaseBundlePayload({
    required this.source,
    required DateTime exportedAt,
    required this.release,
    required this.patch,
    required this.artifact,
    required List<int> artifactBytes,
  }) : exportedAt = exportedAt.toUtc(),
       artifactBytes = List.unmodifiable(artifactBytes);

  final ReleaseBundleSource source;
  final DateTime exportedAt;
  final ReleaseRecord release;
  final PatchRecord patch;
  final ArtifactRecord artifact;
  final List<int> artifactBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'formatVersion': ReleaseBundle.formatVersion,
    'source': source.toJson(),
    'exportedAt': exportedAt.toIso8601String(),
    'release': release.toJson(),
    'patch': patch.toJson(),
    'artifact': <String, Object?>{
      'record': artifact.toJson(),
      'bytes': base64Encode(artifactBytes),
    },
  };

  static ReleaseBundlePayload fromJson(Object? value) {
    final payload = _object(value, 'release bundle payload');
    _requireExactKeys(payload, _payloadKeys, 'release bundle payload');
    if (payload['formatVersion'] != ReleaseBundle.formatVersion) {
      throw const FormatException('Unsupported release bundle format version');
    }
    final exportedAtText = _string(payload['exportedAt'], 'exportedAt');
    late final DateTime exportedAt;
    try {
      exportedAt = DateTime.parse(exportedAtText).toUtc();
    } on FormatException {
      throw const FormatException('Invalid release bundle export timestamp');
    }
    if (exportedAt.toIso8601String() != exportedAtText) {
      throw const FormatException(
        'Release bundle export timestamp is not canonical',
      );
    }
    final release = _release(payload['release']);
    final patch = _patch(payload['patch']);
    final artifactContainer = _object(
      payload['artifact'],
      'release bundle artifact',
    );
    _requireExactKeys(artifactContainer, const <String>{
      'record',
      'bytes',
    }, 'release bundle artifact');
    final artifact = _artifact(artifactContainer['record']);
    final bytesText = _string(artifactContainer['bytes'], 'artifact bytes');
    late final List<int> bytes;
    try {
      bytes = base64Decode(bytesText);
    } on FormatException {
      throw const FormatException('Release bundle artifact bytes are invalid');
    }
    return ReleaseBundlePayload(
      source: ReleaseBundleSource.fromJson(payload['source']),
      exportedAt: exportedAt,
      release: release,
      patch: patch,
      artifact: artifact,
      artifactBytes: bytes,
    );
  }
}

/// Source control-plane identifiers carried as provenance only.
final class ReleaseBundleSource {
  ReleaseBundleSource({
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String releaseId,
    required String patchId,
    required String artifactId,
  }) : organizationId = requireOpaqueId(
         organizationId,
         'source organization ID',
       ),
       applicationId = requireOpaqueId(applicationId, 'source application ID'),
       environmentId = requireOpaqueId(environmentId, 'source environment ID'),
       releaseId = requireOpaqueId(releaseId, 'source release ID'),
       patchId = requireOpaqueId(patchId, 'source patch ID'),
       artifactId = requireOpaqueId(artifactId, 'source artifact ID');

  final String organizationId;
  final String applicationId;
  final String environmentId;
  final String releaseId;
  final String patchId;
  final String artifactId;

  Map<String, Object?> toJson() => <String, Object?>{
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'releaseId': releaseId,
    'patchId': patchId,
    'artifactId': artifactId,
  };

  static ReleaseBundleSource fromJson(Object? value) {
    final source = _object(value, 'release bundle source');
    _requireExactKeys(source, _sourceKeys, 'release bundle source');
    return ReleaseBundleSource(
      organizationId: _string(
        source['organizationId'],
        'source organization ID',
      ),
      applicationId: _string(source['applicationId'], 'source application ID'),
      environmentId: _string(source['environmentId'], 'source environment ID'),
      releaseId: _string(source['releaseId'], 'source release ID'),
      patchId: _string(source['patchId'], 'source patch ID'),
      artifactId: _string(source['artifactId'], 'source artifact ID'),
    );
  }
}

/// Canonical signed transport envelope for one release artifact.
final class ReleaseBundle {
  ReleaseBundle._({
    required this.payload,
    required this.keyId,
    required List<int> signature,
  }) : signature = List.unmodifiable(signature);

  static const int formatVersion = 1;
  static const String algorithmName = 'ed25519';
  static const String domain = 'hyfens.release-bundle.v1';
  static const int maxBytes = 8 * 1024 * 1024;
  static const String trustedKeyIdHeader = 'X-Hyfens-Trusted-Key-Id';
  static const String trustedPublicKeyHeader = 'X-Hyfens-Trusted-Public-Key';

  static const Set<String> _envelopeKeys = <String>{
    ..._payloadKeys,
    'bundleDigest',
    'signatureMetadata',
    'signature',
  };
  static const Set<String> _signatureMetadataKeys = <String>{
    'algorithm',
    'keyId',
  };

  final ReleaseBundlePayload payload;
  final String keyId;
  final List<int> signature;

  String get bundleDigest =>
      sha256Digest(utf8.encode(canonicalJson(payload.toJson())));

  Map<String, Object?> toJson() {
    final payloadJson = payload.toJson();
    return <String, Object?>{
      ...payloadJson,
      'bundleDigest': bundleDigest,
      'signatureMetadata': <String, Object?>{
        'algorithm': algorithmName,
        'keyId': keyId,
      },
      'signature': base64Encode(signature),
    };
  }

  List<int> encode() => utf8.encode(canonicalJson(toJson()));

  /// Signs a payload with the customer-owned Ed25519 seed.
  ///
  /// The seed is consumed only in this call. The returned envelope contains
  /// the public release metadata and signature, never the private seed.
  static Future<List<int>> sign({
    required ReleaseBundlePayload payload,
    required String keyId,
    required List<int> privateKeySeed,
  }) async {
    if (privateKeySeed.length != 32) {
      throw const FormatException('Ed25519 private seed must be 32 bytes');
    }
    requireNonEmpty(keyId, 'bundle signing key ID');
    await validatePayload(payload);
    if (payload.patch.signatureKeyId != keyId) {
      throw const FormatException(
        'Bundle signing key does not match the patch signing key',
      );
    }
    final expectedPublicKey = _publicKeyFor(payload.release, keyId);
    final algorithm = DartEd25519();
    final keyPair = await algorithm.newKeyPairFromSeed(privateKeySeed);
    try {
      final publicKey = await keyPair.extractPublicKey();
      if (!_sameBytes(publicKey.bytes, expectedPublicKey)) {
        throw const FormatException(
          'Bundle signing seed does not match the release trust key',
        );
      }
      final payloadJson = payload.toJson();
      final digest = sha256Digest(utf8.encode(canonicalJson(payloadJson)));
      final metadata = <String, Object?>{
        'algorithm': algorithmName,
        'keyId': keyId,
      };
      final unsigned = <String, Object?>{
        ...payloadJson,
        'bundleDigest': digest,
        'signatureMetadata': metadata,
      };
      final signature = await algorithm.sign(
        _signingBytes(unsigned),
        keyPair: keyPair,
      );
      final envelope = <String, Object?>{
        ...unsigned,
        'signature': base64Encode(signature.bytes),
      };
      final bytes = utf8.encode(canonicalJson(envelope));
      if (bytes.length > maxBytes) {
        throw const FormatException('Release bundle exceeds maximum size');
      }
      return List<int>.unmodifiable(bytes);
    } finally {
      keyPair.destroy();
    }
  }

  /// Validates an unsigned payload before an operator signs it.
  static Future<void> validatePayload(ReleaseBundlePayload payload) =>
      _validatePayload(payload);

  /// Verifies the canonical outer envelope, its inner Patch Format v1
  /// artifact, the bundle digest, and both Ed25519 signatures offline.
  ///
  static Future<ReleaseBundle> verify({
    required List<int> bytes,
    required String expectedKeyId,
    required List<int> expectedPublicKey,
  }) async {
    _validateExpectedTrust(expectedKeyId, expectedPublicKey);
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Invalid release bundle envelope size');
    }
    late final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const FormatException('Release bundle is not valid UTF-8');
    }
    late final Map<String, Object?> envelope;
    try {
      envelope = _object(jsonDecode(source), 'release bundle envelope');
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Release bundle JSON is invalid');
    }
    _requireExactKeys(envelope, _envelopeKeys, 'release bundle envelope');
    if (canonicalJson(envelope) != source) {
      throw const FormatException('Release bundle is not canonically encoded');
    }
    final payloadJson = <String, Object?>{
      for (final key in _payloadKeys) key: envelope[key],
    };
    final payload = ReleaseBundlePayload.fromJson(payloadJson);
    final digest = _string(envelope['bundleDigest'], 'bundle digest');
    if (digest != sha256Digest(utf8.encode(canonicalJson(payloadJson)))) {
      throw const FormatException('Release bundle digest mismatch');
    }
    final metadata = _object(
      envelope['signatureMetadata'],
      'bundle signature metadata',
    );
    _requireExactKeys(
      metadata,
      _signatureMetadataKeys,
      'bundle signature metadata',
    );
    if (metadata['algorithm'] != algorithmName) {
      throw const FormatException(
        'Unsupported release bundle signature algorithm',
      );
    }
    final keyId = _string(metadata['keyId'], 'bundle signing key ID');
    final signature = _decodeSignature(
      _string(envelope['signature'], 'bundle signature'),
    );
    if (payload.patch.signatureKeyId != keyId) {
      throw const FormatException(
        'Bundle signing key does not match the patch signing key',
      );
    }
    final embeddedPublicKey = _publicKeyFor(payload.release, keyId);
    if (keyId != expectedKeyId) {
      throw const FormatException('Release bundle trust key ID mismatch');
    }
    if (!_sameBytes(embeddedPublicKey, expectedPublicKey)) {
      throw const FormatException('Release bundle trust public key mismatch');
    }
    await validatePayload(payload);
    final publicKey = expectedPublicKey;
    final valid = await DartEd25519().verify(
      _signingBytes(<String, Object?>{
        ...payloadJson,
        'bundleDigest': digest,
        'signatureMetadata': metadata,
      }),
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!valid) throw const FormatException('Invalid release bundle signature');
    return ReleaseBundle._(
      payload: payload,
      keyId: keyId,
      signature: signature,
    );
  }

  /// Returns the signed payload fields needed to revalidate an imported
  /// bundle. Artifact bytes are intentionally omitted; the object store is the
  /// source for those bytes during admission.
  Map<String, Object?> get signedPayloadMetadata {
    final payloadJson = payload.toJson();
    final artifact = _object(
      payloadJson['artifact'],
      'release bundle artifact',
    );
    return <String, Object?>{
      ...payloadJson,
      'artifact': <String, Object?>{'record': artifact['record']},
    };
  }

  /// Revalidates the minimal signed payload metadata retained for an imported
  /// bundle. This reconstructs the canonical payload with [artifactBytes],
  /// checks its digest, and verifies the outer signature against the explicit
  /// destination trust anchor.
  static Future<void> revalidateStoredPayload({
    required Map<String, Object?> signedPayloadMetadata,
    required String bundleDigest,
    required String bundleKeyId,
    required String bundleSignature,
    required List<int> artifactBytes,
    required String expectedKeyId,
    required List<int> expectedPublicKey,
  }) async {
    _validateExpectedTrust(expectedKeyId, expectedPublicKey);
    final payloadJson = _payloadFromStoredMetadata(
      signedPayloadMetadata,
      artifactBytes,
    );
    final payload = ReleaseBundlePayload.fromJson(payloadJson);
    final digest = requireSha256Digest(bundleDigest);
    if (digest != sha256Digest(utf8.encode(canonicalJson(payloadJson)))) {
      throw const FormatException('Stored release bundle digest mismatch');
    }
    if (bundleKeyId != expectedKeyId ||
        payload.patch.signatureKeyId != bundleKeyId) {
      throw const FormatException('Stored release bundle trust key mismatch');
    }
    final embeddedPublicKey = _publicKeyFor(payload.release, bundleKeyId);
    if (!_sameBytes(embeddedPublicKey, expectedPublicKey)) {
      throw const FormatException(
        'Stored release bundle trust public key mismatch',
      );
    }
    await validatePayload(payload);
    final signature = _decodeSignature(bundleSignature);
    final valid = await DartEd25519().verify(
      _signingBytes(<String, Object?>{
        ...payloadJson,
        'bundleDigest': digest,
        'signatureMetadata': <String, Object?>{
          'algorithm': algorithmName,
          'keyId': bundleKeyId,
        },
      }),
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(
          expectedPublicKey,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) {
      throw const FormatException('Stored release bundle signature is invalid');
    }
  }

  /// Revalidates a stored artifact against destination control-plane records.
  /// State is deliberately not checked here because admission calls this for
  /// a quarantined artifact and then performs the state transition itself.
  static Future<void> verifyPatchArtifact({
    required ReleaseRecord release,
    required PatchRecord patch,
    required ArtifactRecord artifact,
    required List<int> bytes,
  }) async {
    if (release.patchFormatVersion != patchFormatV1 ||
        release.runtimeCompatibilityVersion <= 0) {
      throw const FormatException('Unsupported release compatibility');
    }
    if (patch.releaseId != release.id ||
        artifact.patchId != patch.id ||
        patch.artifactId != artifact.id ||
        patch.organizationId != release.organizationId ||
        artifact.organizationId != release.organizationId ||
        patch.sha256 != artifact.sha256 ||
        patch.sizeBytes != artifact.sizeBytes) {
      throw const FormatException('Stored bundle record binding is invalid');
    }
    if (bytes.length != artifact.sizeBytes ||
        sha256Digest(bytes) != artifact.sha256) {
      throw const FormatException('Stored bundle artifact digest is invalid');
    }
    late final PatchArtifact decoded;
    try {
      decoded = PatchFormatV1.decode(bytes);
      if (!_sameBytes(PatchFormatV1.encode(decoded), bytes)) {
        throw const FormatException('Patch is not canonically encoded');
      }
    } on PatchFormatException catch (error) {
      throw FormatException('Patch artifact is invalid: ${error.message}');
    }
    if (decoded.applicationId != release.runtimeApplicationId ||
        decoded.releaseId != release.runtimeReleaseId ||
        decoded.patchId != patch.runtimePatchId ||
        decoded.sequence != patch.sequence ||
        decoded.runtimeCompatibilityVersion !=
            release.runtimeCompatibilityVersion ||
        decoded.signatureMetadata.algorithm != algorithmName ||
        decoded.signatureMetadata.keyId != patch.signatureKeyId) {
      throw const FormatException(
        'Patch identity does not match release records',
      );
    }
    final publicKey = _publicKeyFor(release, patch.signatureKeyId);
    final valid = await DartEd25519().verify(
      PatchFormatV1.signingBytes(decoded),
      signature: Signature(
        decoded.signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!valid) throw const FormatException('Patch signature is invalid');
  }

  static List<int> _publicKeyFor(ReleaseRecord release, String keyId) {
    final encoded = release.signingPublicKeys[keyId];
    if (encoded == null) {
      throw const FormatException('Bundle signing key is not registered');
    }
    late final List<int> bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      throw const FormatException('Bundle signing public key is invalid');
    }
    if (bytes.length != 32) {
      throw const FormatException('Bundle signing public key is invalid');
    }
    return bytes;
  }

  static void _validateExpectedTrust(
    String expectedKeyId,
    List<int> expectedPublicKey,
  ) {
    requireNonEmpty(expectedKeyId, 'expected bundle trust key ID');
    if (expectedPublicKey.length != 32) {
      throw const FormatException(
        'Expected bundle trust public key must be 32 bytes',
      );
    }
  }

  static Map<String, Object?> _payloadFromStoredMetadata(
    Map<String, Object?> metadata,
    List<int> artifactBytes,
  ) {
    final raw = _object(metadata, 'stored release bundle payload');
    _requireExactKeys(raw, _payloadKeys, 'stored release bundle payload');
    final artifact = _object(raw['artifact'], 'stored release bundle artifact');
    _requireExactKeys(artifact, const <String>{
      'record',
    }, 'stored release bundle artifact');
    return <String, Object?>{
      ...raw,
      'artifact': <String, Object?>{
        'record': artifact['record'],
        'bytes': base64Encode(artifactBytes),
      },
    };
  }

  static List<int> _decodeSignature(String value) {
    late final List<int> bytes;
    try {
      bytes = base64Decode(value);
    } on FormatException {
      throw const FormatException('Release bundle signature is invalid');
    }
    if (bytes.length != 64) {
      throw const FormatException('Release bundle signature is invalid');
    }
    return bytes;
  }

  static List<int> _signingBytes(Map<String, Object?> value) =>
      utf8.encode('$domain\n${canonicalJson(value)}');
}

final class ReleaseBundleImportResult {
  const ReleaseBundleImportResult({
    required this.source,
    required this.bundleDigest,
    required this.destinationEnvironmentId,
    required this.release,
    required this.patch,
    required this.artifact,
    required this.importState,
    required this.idempotentReplay,
  });

  final ReleaseBundleSource source;
  final String bundleDigest;
  final String destinationEnvironmentId;
  final ReleaseRecord release;
  final PatchRecord patch;
  final ArtifactRecord artifact;
  final String importState;
  final bool idempotentReplay;

  Map<String, Object?> toJson() => <String, Object?>{
    'result':
        importState == 'ADMITTED' &&
            patch.state == 'READY' &&
            artifact.state == 'READY'
        ? 'ADMITTED'
        : 'QUARANTINED',
    'importState': importState,
    'idempotentReplay': idempotentReplay,
    'bundleDigest': bundleDigest,
    'source': source.toJson(),
    'destination': <String, Object?>{
      'organizationId': release.organizationId,
      'applicationId': release.applicationId,
      'environmentId': destinationEnvironmentId,
      'releaseId': release.id,
      'patchId': patch.id,
      'artifactId': artifact.id,
    },
    'release': release.toJson(),
    'patch': patch.toJson(),
    'artifact': artifact.toJson(),
  };
}

const Set<String> _payloadKeys = <String>{
  'formatVersion',
  'source',
  'exportedAt',
  'release',
  'patch',
  'artifact',
};

const Set<String> _sourceKeys = <String>{
  'organizationId',
  'applicationId',
  'environmentId',
  'releaseId',
  'patchId',
  'artifactId',
};

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map) throw FormatException('Invalid $name');
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

void _requireExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String name,
) {
  final actual = value.keys.toSet();
  if (actual.length != expected.length ||
      actual.difference(expected).isNotEmpty ||
      expected.difference(actual).isNotEmpty) {
    throw FormatException('Invalid $name fields');
  }
}

String _string(Object? value, String name) {
  if (value is! String || value.isEmpty) throw FormatException('Invalid $name');
  return value;
}

ReleaseRecord _release(Object? value) {
  final raw = _object(value, 'release bundle release');
  final expected = ReleaseRecord(
    id: 'rel_bundle_placeholder',
    organizationId: 'org_bundle_placeholder',
    applicationId: 'app_bundle_placeholder',
    platformId: 'plt_bundle_placeholder',
    runtimeApplicationId: 'runtime-app',
    runtimeReleaseId: 'runtime-release',
    buildTarget: 'build',
    runtimeCompatibilityVersion: 1,
    patchFormatVersion: patchFormatV1,
    buildFingerprint: 'sha256:${'0' * 64}',
    capabilityAuthorityDigest: 'sha256:${'0' * 64}',
    functionSignatureDigest: 'sha256:${'0' * 64}',
    displayVersion: 'version',
    signingPublicKeys: const <String, String>{'key': ''},
    createdAt: DateTime.utc(2026),
  );
  _requireExactKeys(
    raw,
    expected.toJson().keys.toSet(),
    'release bundle release',
  );
  try {
    final record = ReleaseRecord.fromJson(raw);
    if (canonicalJson(record.toJson()) != canonicalJson(raw)) {
      throw const FormatException(
        'Release bundle release record is not canonically encoded',
      );
    }
    return record;
  } on Object catch (error) {
    throw FormatException('Invalid release bundle release: $error');
  }
}

PatchRecord _patch(Object? value) {
  final raw = _object(value, 'release bundle patch');
  final expected = PatchRecord(
    id: 'pat_bundle_placeholder',
    organizationId: 'org_bundle_placeholder',
    releaseId: 'rel_bundle_placeholder',
    runtimePatchId: 'runtime-patch',
    sequence: 1,
    artifactId: 'art_bundle_placeholder',
    sha256: 'sha256:${'0' * 64}',
    sizeBytes: 1,
    signatureKeyId: 'key',
    state: 'READY',
    createdAt: DateTime.utc(2026),
  );
  _requireExactKeys(
    raw,
    expected.toJson().keys.toSet(),
    'release bundle patch',
  );
  try {
    final record = PatchRecord.fromJson(raw);
    if (canonicalJson(record.toJson()) != canonicalJson(raw)) {
      throw const FormatException(
        'Release bundle patch record is not canonically encoded',
      );
    }
    return record;
  } on Object catch (error) {
    throw FormatException('Invalid release bundle patch: $error');
  }
}

ArtifactRecord _artifact(Object? value) {
  final raw = _object(value, 'release bundle artifact record');
  final expected = ArtifactRecord(
    id: 'art_bundle_placeholder',
    organizationId: 'org_bundle_placeholder',
    patchId: 'pat_bundle_placeholder',
    sha256: 'sha256:${'0' * 64}',
    sizeBytes: 1,
    contentType: 'application/octet-stream',
    state: 'READY',
    createdAt: DateTime.utc(2026),
  );
  _requireExactKeys(
    raw,
    expected.toJson().keys.toSet(),
    'release bundle artifact record',
  );
  try {
    final record = ArtifactRecord.fromJson(raw);
    if (canonicalJson(record.toJson()) != canonicalJson(raw)) {
      throw const FormatException(
        'Release bundle artifact record is not canonically encoded',
      );
    }
    return record;
  } on Object catch (error) {
    throw FormatException('Invalid release bundle artifact record: $error');
  }
}

Future<void> _validatePayload(ReleaseBundlePayload payload) async {
  final source = payload.source;
  final release = payload.release;
  final patch = payload.patch;
  final artifact = payload.artifact;
  if (source.organizationId != release.organizationId ||
      source.organizationId != patch.organizationId ||
      source.organizationId != artifact.organizationId ||
      source.releaseId != release.id ||
      source.patchId != patch.id ||
      source.artifactId != artifact.id ||
      source.applicationId != release.applicationId ||
      patch.releaseId != release.id ||
      patch.artifactId != artifact.id ||
      artifact.patchId != patch.id) {
    throw const FormatException('Release bundle source binding is invalid');
  }
  if (release.patchFormatVersion != patchFormatV1 ||
      release.runtimeCompatibilityVersion <= 0 ||
      patch.state != 'READY' ||
      artifact.state != 'READY') {
    throw const FormatException('Release bundle source is not ready');
  }
  await ReleaseBundle.verifyPatchArtifact(
    release: release,
    patch: patch,
    artifact: artifact,
    bytes: payload.artifactBytes,
  );
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
