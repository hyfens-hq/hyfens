import 'dart:convert';
import 'dart:math';

import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';

typedef CredentialReader = Future<CredentialRecord?> Function(String tokenHash);

/// The non-tenant identity used by the private billing bridge. It is kept
/// separate from [CredentialRecord] because provider processing is authorized
/// by the Hyfens deployment, not by membership in a customer organization.
final class BillingProviderPrincipal {
  const BillingProviderPrincipal({required this.id});

  final String id;

  Set<String> get scopes => const <String>{billingProviderScope};
}

/// Deployment-owned billing bridge configuration. The control plane stores
/// only a token hash; the corresponding bearer is held by the private web
/// deployment and is never serialized into a customer record.
final class BillingProviderBridgeConfig {
  const BillingProviderBridgeConfig({
    required this.tokenHash,
    this.principalId = 'billing-provider',
  });

  final String tokenHash;
  final String principalId;

  BillingProviderPrincipal get principal =>
      BillingProviderPrincipal(id: principalId);

  static BillingProviderBridgeConfig? fromEnvironment(
    Map<String, String> values,
  ) {
    final value = values['HYFENS_BILLING_PROVIDER_TOKEN_HASH']?.trim();
    if (value == null || value.isEmpty) return null;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw ArgumentError(
        'HYFENS_BILLING_PROVIDER_TOKEN_HASH must be a SHA-256 hex digest',
      );
    }
    return BillingProviderBridgeConfig(tokenHash: value);
  }

  bool matches(String token) {
    if (token.isEmpty || token.length > 512) return false;
    final candidate = CredentialService.tokenHash(token);
    return _constantTimeEquals(candidate, tokenHash);
  }

  static bool _constantTimeEquals(String left, String right) {
    var difference = left.length ^ right.length;
    final length = left.length < right.length ? left.length : right.length;
    for (var index = 0; index < length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}

final class CredentialService {
  CredentialService({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  IssuedCredential issue({
    required String id,
    required String organizationId,
    String name = 'Credential',
    required CredentialKind kind,
    required Set<String> scopes,
    String? applicationId,
    String? environmentId,
    DateTime? expiresAt,
  }) {
    final allowed = switch (kind) {
      CredentialKind.control => controlScopes,
      CredentialKind.delivery => deliveryScopes,
      CredentialKind.observation => observationScopes,
      CredentialKind.scheduler => schedulerScopes,
      CredentialKind.autoHalt => autoHaltScopes,
    };
    if (scopes.isEmpty || scopes.difference(allowed).isNotEmpty) {
      throw const ControlPlaneException(
        'INVALID_SCOPE',
        'Credential contains an unsupported scope',
      );
    }
    if (kind == CredentialKind.autoHalt &&
        (scopes.length != autoHaltScopes.length ||
            !scopes.containsAll(autoHaltScopes))) {
      throw const ControlPlaneException(
        'INVALID_SCOPE',
        'Auto-Halt Principal requires its exact fixed scope profile',
      );
    }
    if ((kind == CredentialKind.delivery ||
            kind == CredentialKind.observation ||
            kind == CredentialKind.scheduler ||
            kind == CredentialKind.autoHalt) &&
        (applicationId == null || environmentId == null)) {
      throw const ControlPlaneException(
        'INVALID_CREDENTIAL_SCOPE',
        'Application-scoped credentials require application and environment',
      );
    }
    if (kind == CredentialKind.control &&
        (applicationId != null || environmentId != null)) {
      throw const ControlPlaneException(
        'INVALID_CREDENTIAL_SCOPE',
        'Control credentials cannot be application scoped',
      );
    }
    final tokenBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final token = 'hfy_${base64Url.encode(tokenBytes).replaceAll('=', '')}';
    final record = CredentialRecord(
      id: id,
      organizationId: organizationId,
      name: name,
      kind: kind,
      tokenHash: tokenHash(token),
      scopes: scopes,
      applicationId: applicationId,
      environmentId: environmentId,
      createdAt: DateTime.now().toUtc(),
      expiresAt: expiresAt,
      revoked: false,
    );
    return IssuedCredential(record: record, token: token);
  }

  static String tokenHash(String token) => sha256Hex(utf8.encode(token));

  static Future<CredentialRecord> authorize({
    required String token,
    required String requiredScope,
    required CredentialReader read,
    String? organizationId,
    String? applicationId,
    String? environmentId,
    CredentialKind? kind,
    DateTime? now,
  }) async {
    if (token.isEmpty || token.length > 512) {
      throw const ControlPlaneException(
        'UNAUTHORIZED',
        'Credential is invalid',
        statusCode: 401,
      );
    }
    final record = await read(tokenHash(token));
    if (record == null || record.revoked) {
      throw const ControlPlaneException(
        'UNAUTHORIZED',
        'Credential is invalid',
        statusCode: 401,
      );
    }
    final current = now ?? DateTime.now().toUtc();
    if (record.expiresAt != null && !record.expiresAt!.isAfter(current)) {
      throw const ControlPlaneException(
        'UNAUTHORIZED',
        'Credential is expired',
        statusCode: 401,
      );
    }
    if (kind != null && record.kind != kind) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'Credential kind is not permitted',
        statusCode: 403,
      );
    }
    if (!record.scopes.contains(requiredScope)) {
      throw const ControlPlaneException(
        'FORBIDDEN',
        'Credential scope is not permitted',
        statusCode: 403,
      );
    }
    if (organizationId != null && record.organizationId != organizationId) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    if (record.applicationId != null && record.applicationId != applicationId) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    if (record.environmentId != null && record.environmentId != environmentId) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    return record;
  }
}
