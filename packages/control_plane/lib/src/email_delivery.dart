import 'dart:convert';
import 'dart:io';

import 'encoding.dart' show sha256Hex;
import 'human_auth.dart';
import 'notifications.dart';

/// Compatibility delivery for deployments that have not enabled the durable
/// encrypted notification queue. It still uses the shared Hyfens renderer and
/// sender policy; the notification worker is preferred in managed Cloud.
final class KeplarsHumanMessageDelivery
    implements HumanAuthMessageDelivery, HumanDeletionMessageDelivery {
  KeplarsHumanMessageDelivery({
    required String apiKey,
    required String from,
    this.fromName = 'Hyfens',
    required Uri dashboardOrigin,
    required Uri marketingOrigin,
    HttpClient Function()? clientFactory,
  }) : _provider = KeplarsNotificationProvider(
         apiKey: apiKey,
         from: from,
         fromName: fromName,
         clientFactory: clientFactory,
       ),
       _renderer = NotificationRenderer(
         dashboardOrigin: dashboardOrigin,
         marketingOrigin: marketingOrigin,
       ) {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'must not be empty');
    }
    if (from.trim().isEmpty) {
      throw ArgumentError.value(from, 'from', 'must not be empty');
    }
  }

  final KeplarsNotificationProvider _provider;
  final NotificationRenderer _renderer;
  final String fromName;

  /// Returns null for self-hosted deployments that intentionally have no
  /// production message provider. A managed Cloud deployment with a Keplars
  /// key must also provide a sender address.
  static KeplarsHumanMessageDelivery? fromEnvironment(
    Map<String, String> values,
  ) {
    final apiKey = _meaningful(values['KEPLARS_API_KEY']);
    if (apiKey == null) return null;
    final from =
        _meaningful(values['HYFENS_EMAIL_FROM']) ??
        HyfensSenderPolicy.transactional.from;
    final origins = _origins(values['HYFENS_WEB_ORIGINS']);
    final dashboard = _configuredOrigin(
      origins,
      host: 'app.hyfens.com',
      fallbackIndex: 0,
      fallback: Uri.parse('https://app.hyfens.com'),
    );
    final marketing = _configuredOrigin(
      origins,
      host: 'hyfens.com',
      fallbackIndex: 1,
      fallback: Uri.parse('https://hyfens.com'),
    );
    return KeplarsHumanMessageDelivery(
      apiKey: apiKey,
      from: from,
      fromName: values['HYFENS_EMAIL_FROM_NAME'] ?? 'Hyfens',
      dashboardOrigin: dashboard,
      marketingOrigin: marketing,
    );
  }

  @override
  Future<void> sendVerificationEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) => _send(
    key: 'auth.email.verification_requested',
    stableKey:
        'verification:$email:${expiresAt.toUtc().toIso8601String()}:${sha256Hex(utf8.encode(token))}',
    to: email,
    variables: <String, Object?>{
      'token': token,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'action_url': _renderer.dashboardOrigin.toString(),
      'action_label': 'Open workspace',
    },
  );

  @override
  Future<void> sendRecoveryEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) => _send(
    key: 'auth.password.recovery_requested',
    stableKey:
        'recovery:$email:${expiresAt.toUtc().toIso8601String()}:${sha256Hex(utf8.encode(token))}',
    to: email,
    variables: <String, Object?>{
      'token': token,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'action_url': _renderer.marketingOrigin
          .replace(
            path: '/auth/reset-password',
            queryParameters: <String, String>{'token': token},
          )
          .toString(),
      'action_label': 'Reset password',
    },
  );

  @override
  Future<void> sendDeletionEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) => _send(
    key: 'account.deletion.requested',
    stableKey:
        'deletion:$email:${expiresAt.toUtc().toIso8601String()}:${sha256Hex(utf8.encode(token))}',
    to: email,
    variables: <String, Object?>{
      'token': token,
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'action_url': _renderer.marketingOrigin
          .replace(
            path: '/account-deletion',
            queryParameters: <String, String>{'token': token},
          )
          .toString(),
      'action_label': 'Review deletion request',
      'message': 'Someone requested deletion of the account associated with this address.',
    },
  );

  Future<void> sendEnterpriseInquiryNotification({
    required Iterable<String> recipients,
    required Map<String, Object?> inquiry,
  }) async {
    for (final recipient in recipients) {
      await _send(
        key: 'ops.enterprise.inquiry_received',
        stableKey: 'enterprise:${inquiry['id']}:$recipient',
        to: recipient,
        variables: <String, Object?>{
          'inquiry_id': inquiry['id'],
          'contact': inquiry['email'],
          'organization': inquiry['organization'],
          'message': inquiry['message'],
        },
      );
    }
  }

  Future<void> _send({
    required String key,
    required String stableKey,
    required String to,
    required Map<String, Object?> variables,
  }) async {
    final event = NotificationEvent(
      key: key,
      stableKey: stableKey,
      recipientEmails: <String>[to],
      variables: variables,
      occurredAt: DateTime.now().toUtc(),
      source: 'human_auth',
      sensitive: key.startsWith('auth.') || key.startsWith('account.deletion'),
    );
    await _provider.send(
      _renderer.messageFor(event, to),
      idempotencyKey: event.id,
    );
  }

  static String? _meaningful(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static Uri _configuredOrigin(
    List<Uri> origins, {
    required String host,
    required int fallbackIndex,
    required Uri fallback,
  }) {
    for (final origin in origins) {
      if (origin.host == host) return origin;
    }
    if (fallbackIndex < origins.length) return origins[fallbackIndex];
    if (origins.isNotEmpty) return origins.first;
    return fallback;
  }

  static List<Uri> _origins(String? value) => (value ?? '')
      .split(',')
      .map((item) => Uri.tryParse(item.trim()))
      .whereType<Uri>()
      .where((item) => item.scheme == 'https' && item.host.isNotEmpty)
      .map((item) => item.replace(path: '', query: null, fragment: null))
      .toList(growable: false);
}
