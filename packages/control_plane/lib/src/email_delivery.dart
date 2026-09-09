import 'dart:convert';
import 'dart:io';

import 'human_auth.dart';

/// Production delivery for the existing human-auth message seams.
///
/// Keplars owns queueing and delivery. The control plane owns token creation,
/// persistence, expiry, and purpose separation. Raw tokens are included only
/// in the intended recipient message and are never logged or persisted here.
final class KeplarsHumanMessageDelivery
    implements HumanAuthMessageDelivery, HumanDeletionMessageDelivery {
  KeplarsHumanMessageDelivery({
    required String apiKey,
    required String from,
    this.fromName = 'Hyfens',
    required Uri dashboardOrigin,
    required Uri marketingOrigin,
    HttpClient Function()? clientFactory,
  }) : _apiKey = apiKey,
       _from = from,
       _dashboardOrigin = dashboardOrigin,
       _marketingOrigin = marketingOrigin,
       _clientFactory = clientFactory ?? HttpClient.new {
    if (_apiKey.trim().isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'must not be empty');
    }
    if (_from.trim().isEmpty) {
      throw ArgumentError.value(from, 'from', 'must not be empty');
    }
    _requireHttps(_dashboardOrigin, 'dashboardOrigin');
    _requireHttps(_marketingOrigin, 'marketingOrigin');
  }

  static final Uri _apiBase = Uri.parse('https://api.keplars.com/api/v1');

  final String _apiKey;
  final String _from;
  final String fromName;
  final Uri _dashboardOrigin;
  final Uri _marketingOrigin;
  final HttpClient Function() _clientFactory;

  /// Returns null for self-hosted deployments that intentionally have no
  /// production message provider. A managed Cloud deployment with a Keplars
  /// key must also provide a sender address.
  static KeplarsHumanMessageDelivery? fromEnvironment(
    Map<String, String> values,
  ) {
    final apiKey = _meaningful(values['KEPLARS_API_KEY']);
    if (apiKey == null) return null;
    final from = _meaningful(values['HYFENS_EMAIL_FROM']);
    if (from == null) {
      throw ArgumentError(
        'HYFENS_EMAIL_FROM is required when KEPLARS_API_KEY is configured',
      );
    }
    final origins = _origins(values['HYFENS_WEB_ORIGINS']);
    final dashboard = origins.firstWhere(
      (origin) => origin.host == 'app.hyfens.com',
      orElse: () => Uri.parse('https://app.hyfens.com'),
    );
    final marketing = origins.firstWhere(
      (origin) => origin.host == 'hyfens.com',
      orElse: () => Uri.parse('https://hyfens.com'),
    );
    return KeplarsHumanMessageDelivery(
      apiKey: apiKey,
      from: from,
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
    priority: 'instant',
    to: email,
    subject: 'Verify your Hyfens Cloud account',
    body: _verificationBody(token: token, expiresAt: expiresAt),
  );

  @override
  Future<void> sendRecoveryEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) => _send(
    priority: 'instant',
    to: email,
    subject: 'Recover your Hyfens Cloud account',
    body: _recoveryBody(token: token, expiresAt: expiresAt),
  );

  @override
  Future<void> sendDeletionEmail({
    required String email,
    required String token,
    required DateTime expiresAt,
  }) {
    final link = _marketingOrigin
        .replace(
          path: '/account-deletion',
          queryParameters: <String, String>{'token': token},
        )
        .toString();
    return _send(
      priority: 'high',
      to: email,
      subject: 'Verify your Hyfens account-deletion request',
      body: _deletionBody(link: link, expiresAt: expiresAt),
    );
  }

  Future<void> _send({
    required String priority,
    required String to,
    required String subject,
    required String body,
  }) async {
    final client = _clientFactory();
    try {
      final request = await client.postUrl(
        _apiBase.replace(path: '${_apiBase.path}/send-email/$priority'),
      );
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey')
        ..contentType = ContentType.json;
      request.add(
        utf8.encode(
          jsonEncode(<String, String>{
            'to': to,
            'subject': subject,
            'body': body,
            'from': _from,
            'from_name': fromName,
          }),
        ),
      );
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Transactional email provider rejected the message '
          '(${response.statusCode})',
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  String _verificationBody({
    required String token,
    required DateTime expiresAt,
  }) => _messageShell(
    title: 'Verify your Hyfens Cloud account',
    content:
        '''
      <p>Use this one-time verification code to finish creating your Hyfens Cloud workspace:</p>
      <p><strong>${_escape(token)}</strong></p>
      <p><a href="${_escape(_dashboardOrigin.toString())}">Open Hyfens Cloud</a> and enter the code.</p>
      <p>This code expires at ${_escape(expiresAt.toUtc().toIso8601String())}.</p>
    ''',
  );

  String _recoveryBody({required String token, required DateTime expiresAt}) =>
      _messageShell(
        title: 'Recover your Hyfens Cloud account',
        content:
            '''
      <p>Use this one-time recovery code to choose a new password:</p>
      <p><strong>${_escape(token)}</strong></p>
      <p><a href="${_escape(_dashboardOrigin.toString())}">Open Hyfens Cloud</a> and enter the code.</p>
      <p>This code expires at ${_escape(expiresAt.toUtc().toIso8601String())}.</p>
    ''',
      );

  String _deletionBody({required String link, required DateTime expiresAt}) =>
      _messageShell(
        title: 'Verify your account-deletion request',
        content:
            '''
      <p>Someone requested deletion of a Hyfens Cloud account associated with this address.</p>
      <p><a href="${_escape(link)}">Review and verify the request</a>.</p>
      <p>This link expires at ${_escape(expiresAt.toUtc().toIso8601String())} and can be used once.</p>
      <p>If you did not request this, no action is required.</p>
    ''',
      );

  String _messageShell({required String title, required String content}) =>
      '<!doctype html><html><body><h1>${_escape(title)}</h1>$content</body></html>';

  static String? _meaningful(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static List<Uri> _origins(String? value) => (value ?? '')
      .split(',')
      .map((item) => Uri.tryParse(item.trim()))
      .whereType<Uri>()
      .where((item) => item.scheme == 'https' && item.host.isNotEmpty)
      .map((item) => item.replace(path: '', query: null, fragment: null))
      .toList(growable: false);

  static void _requireHttps(Uri value, String label) {
    if (value.scheme != 'https' || value.host.isEmpty) {
      throw ArgumentError('$label must be an HTTPS origin');
    }
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
