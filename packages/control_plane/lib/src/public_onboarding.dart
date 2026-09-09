import 'dart:async';
import 'dart:convert';

import 'encoding.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'persistence.dart';

const String publicWaitlistCollection = 'waitlist';
const String publicNewsletterCollection = 'newsletter';
const String publicEnterpriseInquiryCollection = 'enterprise_inquiries';
const int publicOnboardingNameMaxLength = 128;
const int publicOnboardingSourceMaxLength = 64;
const int publicEnterpriseMessageMaxLength = 4000;

typedef EnterpriseInquiryNotifier = Future<void> Function(
  Map<String, Object?> inquiry,
);

/// Durable, unauthenticated onboarding intake. Registration is owned by
/// [HumanAuthService]; this service owns only the two non-auth collections.
final class PublicOnboardingService {
  PublicOnboardingService({
    required this.store,
    DateTime Function()? clock,
    this.enterpriseInquiryNotifier,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final ControlPlaneStore store;
  final EnterpriseInquiryNotifier? enterpriseInquiryNotifier;
  final DateTime Function() _clock;
  Future<void> _writeTail = Future<void>.value();

  Future<bool> submitWaitlist({
    required String email,
    String? name,
    String? source,
  }) => _submit(
    collection: publicWaitlistCollection,
    email: email,
    name: name,
    source: source,
  );

  Future<bool> submitNewsletter({
    required String email,
    String? name,
    String? source,
  }) => _submit(
    collection: publicNewsletterCollection,
    email: email,
    name: name,
    source: source,
  );

  /// Stores Enterprise interest in the operator-owned inbox. Email delivery
  /// is intentionally a separate deployment concern; the durable record gives
  /// the platform a real, auditable destination without promising a response
  /// time or inventing a CRM integration.
  Future<Map<String, Object?>> submitEnterpriseInquiry({
    required String email,
    required String message,
    required String idempotencyKey,
    String? name,
    String? organization,
    String? source,
  }) => _serialized(() async {
    final normalizedEmail = normalizeEmail(email);
    final normalizedMessage = _requiredText(
      message,
      'message',
      publicEnterpriseMessageMaxLength,
    );
    final normalizedIdempotency = _requiredText(
      idempotencyKey,
      'idempotency key',
      256,
    );
    final normalizedName = _optionalText(
      name,
      'name',
      publicOnboardingNameMaxLength,
    );
    final normalizedOrganization = _optionalText(
      organization,
      'organization',
      publicOnboardingNameMaxLength,
    );
    final normalizedSource = _optionalText(
      source,
      'source',
      publicOnboardingSourceMaxLength,
    );
    final id = sha256Digest(
      utf8.encode('$normalizedEmail:$normalizedIdempotency'),
    ).substring(7);
    final digest = sha256Digest(
      utf8.encode(
        '$normalizedEmail:$normalizedMessage:${normalizedOrganization ?? ''}',
      ),
    );
    final existing = await store.readJson(
      publicEnterpriseInquiryCollection,
      id,
    );
    if (existing != null) {
      if (existing['payloadDigest'] != digest) {
        throw const ControlPlaneException(
          'PUBLIC_INQUIRY_CONFLICT',
          'The inquiry idempotency key was already used for different content',
          statusCode: 409,
        );
      }
      return _deliverEnterpriseInquiry(id, existing);
    }
    final record = <String, Object?>{
      'id': id,
      'email': normalizedEmail,
      'emailDigest': sha256Digest(utf8.encode(normalizedEmail)),
      if (normalizedName != null) 'name': normalizedName,
      if (normalizedOrganization != null)
        'organization': normalizedOrganization,
      'message': normalizedMessage,
      if (normalizedSource != null) 'source': normalizedSource,
      'status': 'received',
      'destination': 'platform.enterprise_inquiries',
      'delivery': 'durable_control_plane_inbox',
      if (enterpriseInquiryNotifier != null) 'notificationStatus': 'pending',
      'payloadDigest': digest,
      'createdAt': _clock().toUtc().toIso8601String(),
      'updatedAt': _clock().toUtc().toIso8601String(),
    };
    try {
      await store.createJson(publicEnterpriseInquiryCollection, id, record);
      return await _deliverEnterpriseInquiry(id, record);
    } on StorageConflict {
      final concurrent = await store.readJson(
        publicEnterpriseInquiryCollection,
        id,
      );
      if (concurrent == null) rethrow;
      if (concurrent['payloadDigest'] != digest) {
        throw const ControlPlaneException(
          'PUBLIC_INQUIRY_CONFLICT',
          'The inquiry idempotency key was already used for different content',
          statusCode: 409,
        );
      }
      return await _deliverEnterpriseInquiry(id, concurrent);
    }
  });

  Future<Map<String, Object?>> _deliverEnterpriseInquiry(
    String id,
    Map<String, Object?> inquiry,
  ) async {
    final notifier = enterpriseInquiryNotifier;
    if (notifier == null || inquiry['notificationStatus'] == 'sent') {
      return inquiry;
    }
    try {
      await notifier(Map.unmodifiable(inquiry));
    } on Object {
      final failed = <String, Object?>{
        ...inquiry,
        'notificationStatus': 'failed',
        'updatedAt': _clock().toUtc().toIso8601String(),
      };
      await store.replaceJson(publicEnterpriseInquiryCollection, id, failed);
      return failed;
    }
    final delivered = <String, Object?>{
      ...inquiry,
      'notificationStatus': 'sent',
      'notificationSentAt': _clock().toUtc().toIso8601String(),
      'updatedAt': _clock().toUtc().toIso8601String(),
    };
    await store.replaceJson(publicEnterpriseInquiryCollection, id, delivered);
    return delivered;
  }

  Future<bool> _submit({
    required String collection,
    required String email,
    required String? name,
    required String? source,
  }) => _serialized(() async {
    final normalizedEmail = normalizeEmail(email);
    final normalizedName = _optionalText(
      name,
      'name',
      publicOnboardingNameMaxLength,
    );
    final normalizedSource = _optionalText(
      source,
      'source',
      publicOnboardingSourceMaxLength,
    );
    final emailDigest = sha256Digest(utf8.encode(normalizedEmail));
    final recordId = emailDigest.substring(7);
    final record = <String, Object?>{
      'id': recordId,
      'email': normalizedEmail,
      'emailDigest': emailDigest,
      if (normalizedName != null) 'name': normalizedName,
      if (normalizedSource != null) 'source': normalizedSource,
      'createdAt': _clock().toUtc().toIso8601String(),
    };
    final existing = await store.readJson(collection, recordId);
    if (existing != null) {
      if (_sameEmail(existing, normalizedEmail, emailDigest)) return false;
      throw const StorageConflict(
        'Public onboarding email digest collides with an existing record',
      );
    }
    try {
      await store.createJson(collection, recordId, record);
    } on StorageConflict {
      final persisted = await store.readJson(collection, recordId);
      if (persisted != null &&
          _sameEmail(persisted, normalizedEmail, emailDigest)) {
        return false;
      }
      rethrow;
    }
    return true;
  });

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _writeTail.then((_) => action());
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  /// Reuses the human-auth normalization policy while giving public intake a
  /// validation status that does not look like a failed password login.
  static String normalizeEmail(String value) {
    try {
      return HumanAuthService.normalizeHumanEmail(value);
    } on ControlPlaneException {
      throw const ControlPlaneException(
        'INVALID_PUBLIC_SUBMISSION',
        'Email is invalid',
        statusCode: 422,
      );
    }
  }

  static String? _optionalText(String? value, String field, int maxLength) {
    if (value == null) return null;
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    if (normalized.length > maxLength ||
        normalized.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
      throw ControlPlaneException(
        'INVALID_PUBLIC_SUBMISSION',
        '$field is invalid',
        statusCode: 422,
      );
    }
    return normalized;
  }

  static String _requiredText(String value, String field, int maxLength) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > maxLength ||
        normalized.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
      throw ControlPlaneException(
        'INVALID_PUBLIC_SUBMISSION',
        '$field is invalid',
        statusCode: 422,
      );
    }
    return normalized;
  }

  static bool _sameEmail(
    Map<String, Object?> value,
    String normalizedEmail,
    String emailDigest,
  ) =>
      value['email'] == normalizedEmail &&
      (value['emailDigest'] == null || value['emailDigest'] == emailDigest);
}
