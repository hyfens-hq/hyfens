import 'dart:async';
import 'dart:convert';

import 'encoding.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'persistence.dart';

const String publicWaitlistCollection = 'waitlist';
const String publicNewsletterCollection = 'newsletter';
const int publicOnboardingNameMaxLength = 128;
const int publicOnboardingSourceMaxLength = 64;

/// Durable, unauthenticated onboarding intake. Registration is owned by
/// [HumanAuthService]; this service owns only the two non-auth collections.
final class PublicOnboardingService {
  PublicOnboardingService({required this.store, DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final ControlPlaneStore store;
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

  static bool _sameEmail(
    Map<String, Object?> value,
    String normalizedEmail,
    String emailDigest,
  ) =>
      value['email'] == normalizedEmail &&
      (value['emailDigest'] == null || value['emailDigest'] == emailDigest);
}
