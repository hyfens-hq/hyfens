import 'dart:convert';

import 'cloud_plans.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'persistence.dart';

const String platformCloudPlanIdempotencyScope = 'platform_cloud_plan_catalog';
const String platformCloudPlanCatalogCollection = 'billing_plan_catalog';
const String platformCloudPlanCatalogOrganizationId = 'platform';

/// Audited management for the stable Cloud catalogue.
///
/// This changes catalogue presentation and entitlement limits only. It never
/// edits a customer subscription or talks to a payment provider.
final class PlatformCloudPlanAdministrationService {
  PlatformCloudPlanAdministrationService({
    required this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final ControlPlaneStore store;
  final DateTime Function() _clock;
  Future<void> _tail = Future<void>.value();

  Future<Map<String, Object?>> update({
    required String planKey,
    required String name,
    required String description,
    required bool active,
    required Map<String, Object?> limits,
    required String reason,
    required String actorId,
    required String requestId,
    required String idempotencyKey,
  }) => _serialized(() async {
    if (!isCloudPlanKey(planKey)) {
      throw const ControlPlaneException(
        'INVALID_CLOUD_PLAN',
        'The requested Cloud plan is not supported',
        statusCode: 422,
      );
    }
    final definition = cloudPlanDefinition(planKey);
    if (planKey == cloudPlanFreeKey && !active) {
      throw const ControlPlaneException(
        'DEFAULT_CLOUD_PLAN_REQUIRED',
        'Free remains the automatic Cloud onboarding default until plan selection is enabled',
        statusCode: 409,
      );
    }
    final normalizedName = _text(name, 'Plan name', 80);
    final normalizedDescription = _text(description, 'Plan description', 400);
    final normalizedReason = _text(reason, 'Change reason', 1000);
    final normalizedIdempotency = _text(idempotencyKey, 'Idempotency key', 256);
    final normalizedLimits = _limits(limits, definition);
    final requestBody = <String, Object?>{
      'planKey': planKey,
      'name': normalizedName,
      'description': normalizedDescription,
      'active': active,
      'limits': normalizedLimits,
      'reason': normalizedReason,
    };
    final requestDigest = sha256Digest(utf8.encode(canonicalJson(requestBody)));
    final existingIdempotency = await store.readIdempotency(
      platformCloudPlanIdempotencyScope,
      normalizedIdempotency,
    );
    if (existingIdempotency != null) {
      if (existingIdempotency['requestDigest'] != requestDigest) {
        throw const ControlPlaneException(
          'IDEMPOTENCY_CONFLICT',
          'Idempotency key was already used for a different plan change',
          statusCode: 409,
        );
      }
      final result = existingIdempotency['result'];
      if (result is! Map<String, Object?>) {
        throw const ControlPlaneException(
          'STORAGE_CORRUPT',
          'Stored plan change result is invalid',
          statusCode: 500,
        );
      }
      return result;
    }

    final id = 'cloud_plan_$planKey';
    final current = await store.readJson(
      platformCloudPlanCatalogCollection,
      id,
    );
    if (current == null) {
      throw const ControlPlaneException(
        'PLAN_CATALOG_INVALID',
        'The requested Cloud plan is not seeded',
        statusCode: 500,
      );
    }
    final next = <String, Object?>{
      ...current,
      'id': id,
      'key': planKey,
      'name': normalizedName,
      'description': normalizedDescription,
      'active': active,
      'limits': normalizedLimits,
      'updatedAt': _clock().toUtc().toIso8601String(),
    };
    await store.replaceJson(platformCloudPlanCatalogCollection, id, next);

    final result = <String, Object?>{
      'plan': _safePlan(next),
      'requestId': requestId,
    };
    await _appendAudit(
      planKey: planKey,
      actorId: actorId,
      requestId: requestId,
      idempotencyKey: normalizedIdempotency,
      reason: normalizedReason,
      previous: current,
      next: next,
    );
    try {
      await store.createIdempotency(
        platformCloudPlanIdempotencyScope,
        normalizedIdempotency,
        <String, Object?>{
          'requestDigest': requestDigest,
          'result': result,
          'createdAt': _clock().toUtc().toIso8601String(),
        },
      );
    } on StorageConflict {
      final concurrent = await store.readIdempotency(
        platformCloudPlanIdempotencyScope,
        normalizedIdempotency,
      );
      if (concurrent == null || concurrent['requestDigest'] != requestDigest) {
        rethrow;
      }
      final concurrentResult = concurrent['result'];
      if (concurrentResult is Map<String, Object?>) return concurrentResult;
    }
    return result;
  });

  Future<void> _appendAudit({
    required String planKey,
    required String actorId,
    required String requestId,
    required String idempotencyKey,
    required String reason,
    required Map<String, Object?> previous,
    required Map<String, Object?> next,
  }) async {
    final auditId =
        'aud_cloud_plan_${sha256Hex(utf8.encode('$planKey:$idempotencyKey')).substring(0, 32)}';
    if (await store.readJson('audit', auditId) != null) return;
    final value = AuditRecord(
      id: auditId,
      requestId: requestId,
      organizationId: platformCloudPlanCatalogOrganizationId,
      actorId: actorId,
      action: 'platform.cloud_plan.updated',
      resourceType: 'billing_plan_catalog',
      resourceId: planKey,
      result: 'SUCCESS',
      metadata: <String, Object?>{
        'audience': platformAuthorizationAudience,
        'actor_type': 'platform_operator',
        'reason': reason,
        'correlation_id': requestId,
        'causation_id': idempotencyKey,
        'previous': _auditSnapshot(previous),
        'next': _auditSnapshot(next),
      },
      createdAt: _clock().toUtc(),
    ).toJson();
    try {
      await store.appendAudit(auditId, value);
    } on StorageConflict {
      if (await store.readJson('audit', auditId) == null) rethrow;
    }
  }

  Map<String, Object?> _auditSnapshot(Map<String, Object?> value) =>
      <String, Object?>{
        'name': value['name'],
        'description': value['description'],
        'active': value['active'],
        'limits': value['limits'],
      };

  Map<String, Object?> _safePlan(Map<String, Object?> value) =>
      <String, Object?>{
        'id': value['id'],
        'key': value['key'],
        'name': value['name'],
        'description': value['description'],
        'deploymentModel': value['deploymentModel'],
        'rank': value['rank'],
        'paymentRequired': value['paymentRequired'],
        'providerBacked': value['providerBacked'],
        'active': value['active'] == true,
        'limits': value['limits'],
        'updatedAt': value['updatedAt'],
      };

  Map<String, Object?> _limits(
    Map<String, Object?> limits,
    CloudPlanDefinition definition,
  ) {
    final expectedKeys = definition.limits.keys.toSet();
    if (limits.keys.any((key) => !expectedKeys.contains(key)) ||
        limits.length != expectedKeys.length) {
      throw const ControlPlaneException(
        'INVALID_PLAN_LIMIT',
        'Plan limits must use the seeded Cloud limit keys',
        statusCode: 422,
      );
    }
    final normalized = <String, Object?>{};
    try {
      for (final key in expectedKeys) {
        normalized[key] = CloudLimit.fromJson(limits[key]).toJson();
      }
    } on FormatException {
      throw const ControlPlaneException(
        'INVALID_PLAN_LIMIT',
        'Plan limits are malformed',
        statusCode: 422,
      );
    }
    return normalized;
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static String _text(String value, String label, int maxLength) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > maxLength ||
        normalized.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
      throw ControlPlaneException(
        'INVALID_REQUEST',
        '$label is invalid',
        statusCode: 422,
      );
    }
    return normalized;
  }
}
