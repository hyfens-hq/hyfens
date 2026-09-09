import 'dart:convert';
import 'dart:io';

import 'cloud_plans.dart';
import 'config.dart';
import 'deletion.dart';
import 'domain.dart';
import 'encoding.dart';
import 'enterprise_billing.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'observation.dart';
import 'operator_overview.dart';
import 'p3e_evaluation.dart';
import 'platform_console.dart';
import 'platform_metrics.dart';
import 'public_onboarding.dart';
import 'reconciliation_domain.dart';
import 'reconciliation_observability.dart';
import 'reconciliation_periodic.dart';
import 'release_bundle.dart';
import 'rollout.dart';
import 'runtime_receipts.dart';
import 'service.dart';
import 'support.dart';

final class ControlPlaneHttpLimits {
  const ControlPlaneHttpLimits({
    this.maxJsonBodyBytes = 256 * 1024,
    this.maxArtifactBytes = 4 * 1024 * 1024,
    this.maxBundleBytes = ReleaseBundle.maxBytes,
    this.maxRequestsPerMinute = 600,
    this.maxAuthAttemptsPerMinute = 10,
    this.maxPublicOnboardingBodyBytes = 4 * 1024,
    this.maxObservationBodyBytes = defaultObservationMaxEventBytes,
  });

  final int maxJsonBodyBytes;
  final int maxArtifactBytes;
  final int maxBundleBytes;
  final int maxRequestsPerMinute;
  final int maxAuthAttemptsPerMinute;
  final int maxPublicOnboardingBodyBytes;
  final int maxObservationBodyBytes;
}

final class _TrustedBundleKey {
  const _TrustedBundleKey({required this.keyId, required this.publicKey});

  final String keyId;
  final List<int> publicKey;
}

final class _ArtifactResponseSlice {
  const _ArtifactResponseSlice({
    required this.bytes,
    required this.statusCode,
    this.contentRange,
  });

  final List<int> bytes;
  final int statusCode;
  final String? contentRange;
}

/// The trust boundary for the local HTTP adapter.
///
/// Forwarded headers describe a proxy's view of a request; they are not an
/// authentication signal. The adapter binds to loopback by default, and an
/// explicitly configured reverse proxy must terminate TLS and enforce its own
/// public-edge policy before forwarding to this process. A private immediate
/// proxy peer may provide the exact `X-Forwarded-Proto: https` signal needed to
/// preserve the credential-transport check across TLS termination; that signal
/// never changes authorization, rate limiting, or tenant scope.
final class ControlPlaneIngressTrustPolicy {
  const ControlPlaneIngressTrustPolicy._();

  static const bool forwardedHeadersAffectAuthorization = false;
  static const bool forwardedHeadersAffectRateLimit = false;
  static const bool requestIdAffectsAuthorization = false;
  static const bool hostAffectsAuthorization = false;

  /// Returns whether a TLS-terminating private proxy may be trusted for the
  /// transport check. The proxy must overwrite the header rather than forward
  /// an untrusted client value, and the control-plane upstream must not be
  /// publicly reachable.
  static bool isTrustedForwardedTls({
    required String? remoteAddress,
    required String? forwardedProto,
  }) {
    if (forwardedProto?.trim().toLowerCase() != 'https') return false;
    final value = remoteAddress?.trim();
    if (value == null || value.isEmpty || value == 'localhost') return false;
    final address = InternetAddress.tryParse(value);
    if (address == null) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return _isTrustedPrivateIpv4(bytes);
    }
    if (address.type != InternetAddressType.IPv6 || bytes.length != 16) {
      return false;
    }
    if (_isIpv4Mapped(bytes)) {
      return _isTrustedPrivateIpv4(bytes.sublist(12));
    }
    // Loopback and unique-local IPv6 are the private proxy ranges relevant to
    // the supported host/container deployment topology.
    return _isIpv6Loopback(bytes) || (bytes[0] & 0xfe) == 0xfc;
  }

  static bool _isTrustedPrivateIpv4(List<int> bytes) {
    if (bytes.length != 4) return false;
    return bytes[0] == 127 ||
        bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  static bool _isIpv4Mapped(List<int> bytes) =>
      bytes.take(10).every((value) => value == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;

  static bool _isIpv6Loopback(List<int> bytes) =>
      bytes.take(15).every((value) => value == 0) && bytes[15] == 1;
}

/// Bounded operator metrics for one control-plane process.
///
/// These counters are intentionally process-local. They provide measurement
/// for a self-hosted instance without becoming runtime telemetry or a claim
/// about fleet-wide availability/capacity.
final class ControlPlaneMetrics {
  int requestCount = 0;
  int errorCount = 0;
  int totalDurationMicros = 0;
  int maxDurationMicros = 0;
  final Map<String, int> operationCounts = <String, int>{};
  final Map<String, int> statusCounts = <String, int>{};
  final Map<String, int> updateDecisionCounts = <String, int>{};

  void record(HttpRequest request, int durationMicros) {
    requestCount++;
    totalDurationMicros += durationMicros;
    if (durationMicros > maxDurationMicros) {
      maxDurationMicros = durationMicros;
    }
    final operation = _operation(request);
    operationCounts[operation] = (operationCounts[operation] ?? 0) + 1;
    final status = request.response.statusCode;
    final statusClass = '${status ~/ 100}xx';
    statusCounts[statusClass] = (statusCounts[statusClass] ?? 0) + 1;
    if (status >= 400) errorCount++;
  }

  void recordUpdateDecision(String decision) {
    updateDecisionCounts[decision] = (updateDecisionCounts[decision] ?? 0) + 1;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'requests': <String, Object?>{
      'count': requestCount,
      'errors': errorCount,
      'totalDurationMicros': totalDurationMicros,
      'maxDurationMicros': maxDurationMicros,
      'operationCounts': Map<String, int>.from(operationCounts),
      'statusClasses': Map<String, int>.from(statusCounts),
      'updateDecisions': Map<String, int>.from(updateDecisionCounts),
    },
  };

  static String _operation(HttpRequest request) {
    final segments = request.uri.pathSegments;
    if (request.uri.path == '/healthz' || request.uri.path == '/livez') {
      return '${request.method} ${request.uri.path}';
    }
    if (request.uri.path == '/readyz' || request.uri.path == '/metrics') {
      return '${request.method} ${request.uri.path}';
    }
    if (segments.length >= 2 && segments[0] == 'v1') {
      final bounded = switch (segments[1]) {
        'organizations' =>
          segments.length >= 3 ? 'v1/organizations/*' : 'v1/organizations',
        'platform' =>
          segments.length >= 3 ? 'v1/platform/${segments[2]}' : 'v1/platform',
        'rollouts' => segments.length >= 3 ? 'v1/rollouts/*' : 'v1/rollouts',
        'runtime' =>
          segments.length >= 3 &&
                  const <String>{
                    'update-check',
                    'artifacts',
                  }.contains(segments[2])
              ? 'v1/runtime/${segments[2]}'
              : 'v1/runtime/other',
        'reconciliation' =>
          segments.length >= 3 &&
                  const <String>{
                    'diagnostics',
                    'findings',
                  }.contains(segments[2])
              ? 'v1/reconciliation/${segments[2]}'
              : 'v1/reconciliation/other',
        _ => 'v1/other',
      };
      return '${request.method} /$bounded';
    }
    if (segments.length == 2 && segments[0] == 'auth') {
      return '${request.method} /auth/${segments[1]}';
    }
    return '${request.method} /other';
  }
}

/// Small `dart:io` HTTP adapter for the local control-plane service. It is
/// intentionally a transport adapter, not a framework or a second policy
/// engine.
final class ControlPlaneHttpServer {
  ControlPlaneHttpServer(
    this.service, {
    ControlPlaneHttpLimits limits = const ControlPlaneHttpLimits(),
    ControlPlaneDiscoveryConfig? discovery,
    Future<bool> Function()? readyCheck,
    this.reconciliationObservability,
    this.periodicRunner,
    this.auditRetentionDays = 365,
    this.allowInsecureAuth = false,
    this.runtimeReceiptSettlement,
    CloudOnboardingConfig? cloudOnboarding,
    CloudSignupVerificationDelivery? cloudSignupDelivery,
  }) : limits = limits,
       discovery =
           discovery ??
           ControlPlaneDiscoveryConfig.fromEnvironment(Platform.environment),
       _operatorOverview = OperatorOverviewProjection(service),
       _publicOnboarding = PublicOnboardingService(store: service.store),
       _platformConsole = PlatformConsoleProjection(service.store),
       _platformMetrics = PlatformMetricsProjection(store: service.store),
       _readyCheck = readyCheck ?? service.checkReadiness;

  final ControlPlaneService service;
  final ControlPlaneHttpLimits limits;
  final ControlPlaneDiscoveryConfig discovery;
  final int auditRetentionDays;
  final bool allowInsecureAuth;
  final RuntimeReceiptSettlement? runtimeReceiptSettlement;
  final ReconciliationObservability? reconciliationObservability;
  final ReconciliationPeriodicRunner? periodicRunner;
  final OperatorOverviewProjection _operatorOverview;
  final PublicOnboardingService _publicOnboarding;
  final PlatformConsoleProjection _platformConsole;
  final PlatformMetricsProjection _platformMetrics;
  final ControlPlaneMetrics metrics = ControlPlaneMetrics();
  final Future<bool> Function() _readyCheck;
  final Map<String, List<DateTime>> _requestWindows =
      <String, List<DateTime>>{};
  final Map<String, List<DateTime>> _authRequestWindows =
      <String, List<DateTime>>{};
  HttpServer? _server;

  Future<HttpServer> bind({String host = '127.0.0.1', int port = 0}) async {
    if (_server != null)
      throw StateError('Control-plane server is already bound');
    _server = await HttpServer.bind(host, port);
    _server!.idleTimeout = const Duration(seconds: 30);
    _server!.listen(_handle, onError: (Object error, StackTrace stack) {});
    await periodicRunner?.start();
    return _server!;
  }

  Future<void> close({bool force = false}) async {
    final server = _server;
    _server = null;
    await periodicRunner?.stop();
    await server?.close(force: force);
  }

  Future<void> handle(HttpRequest request) => _handle(request);

  Future<void> _handle(HttpRequest request) async {
    final requestId = _requestId(request);
    final stopwatch = Stopwatch()..start();
    request.response.headers
      ..set('X-Request-Id', requestId)
      ..set('Cache-Control', 'no-store');
    try {
      final apiPath = _apiRelativePath(request.uri.path);
      // Route product APIs against the configured API base while retaining
      // the legacy root paths used by existing local callers. Auth already
      // uses this relative path below; product/runtime dispatch must use the
      // same view or a `/p2/` deployment cannot serve its advertised API.
      final path = apiPath == null
          ? const <String>[]
          : Uri.parse(apiPath).pathSegments;
      _applyCors(request);
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }
      _enforceRateLimit(request);
      if (request.method == 'GET' && request.uri.path == _discoveryPath) {
        await _discovery(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          (request.uri.path == '/healthz' || request.uri.path == '/livez')) {
        await _json(request.response, 200, <String, Object?>{
          'status': 'ok',
          'service': 'hyfens-control-plane',
          'request_id': requestId,
        });
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/readyz') {
        final serviceReady = await _readyCheck();
        final reconciliationReadiness = await reconciliationObservability
            ?.checkReadiness();
        final ready = serviceReady && (reconciliationReadiness?.ready ?? true);
        await _json(request.response, ready ? 200 : 503, <String, Object?>{
          'status': ready ? 'ready' : 'not_ready',
          'service': 'hyfens-control-plane',
          if (reconciliationReadiness != null)
            'reconciliation': reconciliationReadiness.toJson(),
          'request_id': requestId,
        });
        return;
      }
      // Auth and product-resource routes carry bearer/session material or
      // can issue it. Apply the transport boundary before route-specific
      // parsing so opaque credentials receive the same HTTPS protection as
      // human sessions.
      if (apiPath != null &&
          (apiPath.startsWith('/auth/') ||
              apiPath.startsWith('/v1/') ||
              apiPath.startsWith('/cms/'))) {
        _enforceCredentialTransport(request);
      }
      if (apiPath != null && apiPath.startsWith('/auth/')) {
        _rejectAuthSecretsInQuery(request);
      }
      if (request.method == 'POST' && apiPath == '/auth/login') {
        _enforceAuthRateLimit(request);
        await _authLogin(request, requestId);
        return;
      }
      if (request.method == 'POST' && apiPath == '/auth/refresh') {
        await _authRefresh(request, requestId);
        return;
      }
      if (request.method == 'POST' && apiPath == '/auth/logout') {
        await _authLogout(request, requestId);
        return;
      }
      if (request.method == 'GET' && apiPath == '/auth/me') {
        await _authMe(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'metrics'])) {
        await _readPlatformMetrics(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'organizations'])) {
        await _readPlatformOrganizations(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'organizations', '*'])) {
        await _readPlatformOrganization(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'audit'])) {
        await _readPlatformAudit(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'users'])) {
        await _readPlatformUsers(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'entitlements'])) {
        await _readPlatformEntitlements(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'enterprise-inquiries'])) {
        await _readPlatformEnterpriseInquiries(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'enterprise-quotes'])) {
        await _readPlatformEnterpriseQuotes(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const [
            'v1',
            'platform',
            'billing',
            'refund-requests',
          ])) {
        await _readPlatformRefundRequests(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'platform',
            'billing',
            'refund-requests',
            '*',
            'approve',
          ])) {
        await _approvePlatformRefund(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'platform',
            'billing',
            'refund-requests',
            '*',
            'reject',
          ])) {
        await _rejectPlatformRefund(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'platform', 'enterprise-quotes'])) {
        await _createPlatformEnterpriseQuote(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'platform',
            'enterprise-quotes',
            '*',
            'issue',
          ])) {
        await _issuePlatformEnterpriseQuote(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'platform',
            'enterprise-quotes',
            '*',
            'revise',
          ])) {
        await _revisePlatformEnterpriseQuote(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'platform',
            'enterprise-quotes',
            '*',
            'withdraw',
          ])) {
        await _withdrawPlatformEnterpriseQuote(request, path, requestId);
        return;
      }
      if (request.method == 'GET' && apiPath == '/auth/authorize') {
        await _authAuthorize(request, requestId);
        return;
      }
      if (request.method == 'POST' && apiPath == '/auth/authorize') {
        await _authAuthorize(request, requestId);
        return;
      }
      if (request.method == 'POST' && apiPath == '/auth/token') {
        await _authToken(request, requestId);
        return;
      }
      if (request.method == 'POST' && apiPath == '/auth/device/code') {
        _enforceAuthRateLimit(request);
        await _authDeviceCode(request, requestId);
        return;
      }
      if (request.method == 'POST' && apiPath == '/auth/device/token') {
        await _authDeviceToken(request, requestId);
        return;
      }
      if (request.method == 'POST' && apiPath == '/auth/device/approve') {
        await _authDeviceApprove(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'cloud', 'signup'])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _cloudSignup(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'cloud', 'verify'])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _cloudVerify(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          apiPath == (_deviceVerificationPath ?? '/auth/device/verify')) {
        await _authDeviceVerify(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'public', 'cloud', 'register'])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _publicCloudRegister(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'public', 'cloud', 'verify'])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _publicCloudVerify(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'public',
            'cloud',
            'verification',
            'resend',
          ])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _publicCloudVerificationResend(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'public', 'cloud', 'recovery'])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _publicCloudRecovery(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'public',
            'cloud',
            'recovery',
            'complete',
          ])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _publicCloudRecoveryComplete(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'public', 'cloud', 'account-deletion'])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _publicAccountDeletionRequest(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'public',
            'cloud',
            'account-deletion',
            'verify',
          ])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _publicAccountDeletionVerify(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'account', 'deletion'])) {
        await _readAccountDeletion(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'account', 'deletion'])) {
        _enforceAuthRateLimit(request);
        await _requestAccountDeletion(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'account', 'deletion', 'cancel'])) {
        _enforceAuthRateLimit(request);
        await _cancelAccountDeletion(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'organizations', '*', 'deletion'])) {
        await _readOrganizationDeletion(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'deletion',
            'authorize',
          ])) {
        _enforceAuthRateLimit(request);
        await _authorizeOrganizationDeletion(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'organizations', '*', 'deletion'])) {
        _enforceAuthRateLimit(request);
        await _requestOrganizationDeletion(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'deletion',
            'cancel',
          ])) {
        _enforceAuthRateLimit(request);
        await _cancelOrganizationDeletion(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'organizations'])) {
        _enforceAuthRateLimit(request);
        await _createCustomerOrganization(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'billing',
            'provider',
            'checkouts',
            '*',
            'subscription',
          ])) {
        await _linkBillingProviderSubscription(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'billing',
            'provider',
            'enterprise-contracts',
            '*',
            'subscription',
          ])) {
        await _linkEnterpriseProviderSubscription(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'billing',
            'provider',
            'enterprise-contracts',
            '*',
            'plan',
          ])) {
        await _linkEnterpriseProviderPlan(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const [
            'v1',
            'billing',
            'provider',
            'enterprise-contracts',
            '*',
          ])) {
        await _readEnterpriseProviderContract(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'billing',
            'provider',
            'subscriptions',
            '*',
            'scheduled-change',
          ])) {
        await _confirmBillingScheduledPlanChange(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'billing',
            'provider',
            'subscriptions',
            '*',
          ])) {
        await _syncBillingProviderSubscription(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'billing',
            'provider',
            'enterprise-subscriptions',
            '*',
          ])) {
        await _syncEnterpriseProviderSubscription(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'billing', 'provider', 'webhook'])) {
        await _applyBillingProviderWebhook(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'billing',
            'provider',
            'refunds',
            '*',
            'prepare',
          ])) {
        await _prepareBillingProviderRefund(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'billing',
            'provider',
            'refunds',
            '*',
            'result',
          ])) {
        await _recordBillingProviderRefundResult(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'billing', 'webhooks', 'razorpay'])) {
        await _applyRazorpayBillingWebhook(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'public', 'register'])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _publicRegister(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'public', 'waitlist'])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _publicWaitlist(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'public', 'newsletter'])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _publicNewsletter(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'public', 'enterprise-inquiries'])) {
        _enforceAuthRateLimit(request);
        _rejectPublicQuery(request);
        await _publicEnterpriseInquiry(request, requestId);
        return;
      }
      if (request.method == 'GET' && apiPath == '/content') {
        await _listPublishedContent(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          (_matches(path, const ['content', '*']) ||
              _matches(path, const ['content', '*', '*']))) {
        await _readPublishedContent(request, path, requestId);
        return;
      }
      if (request.method == 'GET' && _matches(path, const ['cms', 'content'])) {
        await _listCmsContent(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['cms', 'content'])) {
        await _createCmsContent(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['cms', 'content', '*'])) {
        await _readCmsContent(request, path, requestId);
        return;
      }
      if ((request.method == 'PATCH' || request.method == 'PUT') &&
          _matches(path, const ['cms', 'content', '*'])) {
        await _updateCmsContent(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['cms', 'content', '*', 'publish'])) {
        await _publishCmsContent(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['cms', 'content', '*', 'archive'])) {
        await _archiveCmsContent(request, path, requestId);
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/metrics') {
        await _json(request.response, 200, <String, Object?>{
          ...metrics.toJson(),
          if (reconciliationObservability != null)
            'reconciliation': reconciliationObservability!.metrics.toJson(),
          'request_id': requestId,
        });
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'reconciliation', 'diagnostics'])) {
        await _readReconciliationDiagnostics(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'reconciliation', 'findings', '*'])) {
        await _readReconciliationFinding(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'observations', 'token'])) {
        await _issueObservationToken(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'observations', 'events'])) {
        await _ingestObservation(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'rollouts'])) {
        await _createRollout(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'rollouts', '*'])) {
        await _readRollout(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'rollouts', '*', 'actions'])) {
        await _transitionRollout(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'rollouts',
            '*',
            'health',
            'evaluations',
          ])) {
        await _evaluateHealth(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'rollouts',
            '*',
            'health',
            'decisions',
            '*',
            'apply',
          ])) {
        await _applyHealthHalt(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const [
            'v1',
            'rollouts',
            '*',
            'health',
            'evaluations',
            '*',
          ])) {
        await _readHealthEvaluation(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const [
            'v1',
            'rollouts',
            '*',
            'health',
            'evaluations',
          ])) {
        await _listHealthEvaluations(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'organizations', '*', 'applications'])) {
        await _createApplication(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'applications',
            '*',
            'releases',
          ])) {
        await _registerRelease(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'applications',
            '*',
            'environments',
            '*',
            'releases',
            '*',
            'patches',
            '*',
            'bundle',
          ])) {
        await _exportBundle(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'applications',
            '*',
            'environments',
            '*',
            'bundles',
          ])) {
        await _importBundle(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'applications',
            '*',
            'environments',
            '*',
            'bundles',
            '*',
            '*',
            'admit',
          ])) {
        await _admitBundle(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'organizations', '*', 'credentials'])) {
        await _issueCredential(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'applications',
            '*',
            'environments',
          ])) {
        await _createEnvironment(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'organizations', '*', 'credentials'])) {
        await _readCredentials(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'organizations', '*', 'members'])) {
        await _readOrganizationMembers(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'organizations', '*', 'audit'])) {
        await _exportAudit(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'organizations', '*', 'overview'])) {
        await _readOperatorOverview(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'organizations', '*', 'billing'])) {
        await _readBilling(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'enterprise-quotes',
            '*',
          ])) {
        await _readCustomerEnterpriseQuote(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'enterprise-quotes',
            '*',
            'accept',
          ])) {
        await _acceptCustomerEnterpriseQuote(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'enterprise-quotes',
            '*',
            'reject',
          ])) {
        await _rejectCustomerEnterpriseQuote(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'enterprise',
            'cancel',
          ])) {
        await _requestEnterpriseCancellation(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'checkout',
          ])) {
        await _startBillingCheckout(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'refund-requests',
          ])) {
        await _requestBillingRefund(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'plan-change',
          ])) {
        await _requestBillingPlanChange(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'plan-change',
            'cancel',
          ])) {
        await _cancelBillingPlanChange(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'cancel',
          ])) {
        await _requestBillingCancellation(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'checkouts',
            '*',
            'cancel',
          ])) {
        await _cancelBillingCheckout(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'plans',
          ])) {
        await _createBillingPlan(request, path, requestId);
        return;
      }
      if (request.method == 'PATCH' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'plans',
            '*',
          ])) {
        await _setBillingPlanActive(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'subscriptions',
          ])) {
        await _upsertBillingSubscription(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'billing',
            'events',
          ])) {
        await _recordBillingEvent(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'artifact-reconciliation',
          ])) {
        await _reconcileArtifacts(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'credentials',
            '*',
            'revoke',
          ])) {
        await service.revokeCredential(
          token: _bearer(request),
          credentialId: path[4],
          organizationId: path[2],
          requestId: requestId,
        );
        await _json(request.response, 200, <String, Object?>{
          'status': 'revoked',
          'credential_id': path[4],
          'request_id': requestId,
        });
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'releases',
            '*',
            'patches',
          ])) {
        await _registerPatch(request, path, requestId);
        return;
      }
      if (request.method == 'PUT' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'artifacts',
            '*',
          ])) {
        await _uploadArtifact(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'environments',
            '*',
            'release-promotions',
          ])) {
        await _promote(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'applications',
            '*',
            'environments',
            '*',
            'rollback',
          ])) {
        await _rollback(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          path.length == 3 &&
          path[0] == 'v1' &&
          path[1] == 'runtime' &&
          path[2] == 'update-check') {
        await _updateCheck(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          path.length == 4 &&
          path[0] == 'v1' &&
          path[1] == 'runtime' &&
          path[2] == 'artifacts') {
        await _fetchArtifact(request, path[3], requestId);
        return;
      }
      throw ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    } on ControlPlaneException catch (error) {
      await _json(request.response, error.statusCode, error.toJson(requestId));
      _logRequestError(
        request,
        requestId,
        error.code,
        stopwatch.elapsedMicroseconds,
      );
    } on FormatException catch (error) {
      await _json(
        request.response,
        400,
        <String, Object?>{
          'error': <String, Object?>{
            'code': 'INVALID_REQUEST',
            'message': 'Request is malformed',
          },
          'request_id': requestId,
        },
        overrideMessage: error.message,
        requestId: requestId,
      );
      _logRequestError(
        request,
        requestId,
        'INVALID_REQUEST',
        stopwatch.elapsedMicroseconds,
      );
    } on StorageUnavailable {
      final failure = const ControlPlaneException(
        'DEPENDENCY_UNAVAILABLE',
        'A persistence or object dependency is unavailable',
        statusCode: 503,
      );
      await _json(
        request.response,
        failure.statusCode,
        failure.toJson(requestId),
      );
      _logRequestError(
        request,
        requestId,
        failure.code,
        stopwatch.elapsedMicroseconds,
      );
    } on StorageConflict {
      final failure = const ControlPlaneException(
        'STORAGE_CONFLICT',
        'The requested immutable storage operation conflicted',
        statusCode: 409,
      );
      await _json(
        request.response,
        failure.statusCode,
        failure.toJson(requestId),
      );
      _logRequestError(
        request,
        requestId,
        failure.code,
        stopwatch.elapsedMicroseconds,
      );
    } on StorageDigestMismatch {
      final failure = const ControlPlaneException(
        'STORAGE_DIGEST_MISMATCH',
        'Stored content failed its digest check',
        statusCode: 409,
      );
      await _json(
        request.response,
        failure.statusCode,
        failure.toJson(requestId),
      );
      _logRequestError(
        request,
        requestId,
        failure.code,
        stopwatch.elapsedMicroseconds,
      );
    } on Object {
      await _json(
        request.response,
        500,
        const ControlPlaneException(
          'INTERNAL_ERROR',
          'Request could not be completed',
        ).toJson(requestId),
      );
      _logRequestError(
        request,
        requestId,
        'INTERNAL_ERROR',
        stopwatch.elapsedMicroseconds,
      );
    } finally {
      metrics.record(request, stopwatch.elapsedMicroseconds);
    }
  }

  Future<void> _readPublishedContent(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final configuredOrganizationId = discovery.publicContentOrganizationId;
    final requestedOrganizationId =
        request.uri.queryParameters['organization_id'];
    if (configuredOrganizationId == null ||
        (requestedOrganizationId != null &&
            requestedOrganizationId != configuredOrganizationId)) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final kindValue = path.length == 3
        ? path[1]
        : request.uri.queryParameters['kind'];
    final kind = kindValue == null || kindValue.isEmpty
        ? ContentKind.blog
        : _contentKind(kindValue);
    final record = await service.readPublishedContent(
      slug: path.length == 3 ? path[2] : path[1],
      kind: kind,
      organizationId: configuredOrganizationId,
    );
    await _json(request.response, 200, <String, Object?>{
      'data': record.toPublicJson(),
      'request_id': requestId,
    });
  }

  Future<void> _listPublishedContent(
    HttpRequest request,
    String requestId,
  ) async {
    final organizationId = discovery.publicContentOrganizationId;
    if (organizationId == null) {
      await _json(request.response, 200, <String, Object?>{
        'data': const <Object?>[],
        'request_id': requestId,
      });
      return;
    }
    final kindValue = request.uri.queryParameters['kind'];
    final kind = kindValue == null || kindValue.isEmpty
        ? null
        : _contentKind(kindValue);
    final records = await service.listPublishedContent(
      organizationId: organizationId,
      kind: kind,
    );
    await _json(request.response, 200, <String, Object?>{
      'data': records
          .map((record) => record.toPublicJson())
          .toList(growable: false),
      'request_id': requestId,
    });
  }

  Future<void> _listCmsContent(HttpRequest request, String requestId) async {
    final statusValue = request.uri.queryParameters['status'];
    final kindValue = request.uri.queryParameters['kind'];
    final organizationValue = request.uri.queryParameters['organization_id'];
    final organizationId =
        organizationValue == null || organizationValue.isEmpty
        ? null
        : organizationValue;
    final records = await service.listContent(
      token: _bearer(request),
      organizationId: organizationId,
      status: statusValue == null || statusValue.isEmpty
          ? null
          : _contentStatus(statusValue),
      kind: kindValue == null || kindValue.isEmpty
          ? null
          : _contentKind(kindValue),
    );
    await _json(request.response, 200, <String, Object?>{
      'data': records.map((record) => record.toJson()).toList(growable: false),
      'request_id': requestId,
    });
  }

  Future<void> _createCmsContent(HttpRequest request, String requestId) async {
    final organizationValue = request.uri.queryParameters['organization_id'];
    final organizationId =
        organizationValue == null || organizationValue.isEmpty
        ? null
        : organizationValue;
    final record = await service.createContent(
      token: _bearer(request),
      draft: _contentWrite(await _jsonBody(request)),
      organizationId: organizationId,
      requestId: requestId,
    );
    await _json(request.response, 201, <String, Object?>{
      'data': record.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _readCmsContent(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final record = await service.readContent(
      token: _bearer(request),
      contentId: path[2],
    );
    await _json(request.response, 200, <String, Object?>{
      'data': record.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _updateCmsContent(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final record = await service.updateContent(
      token: _bearer(request),
      contentId: path[2],
      draft: _contentWrite(await _jsonBody(request)),
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      'data': record.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _publishCmsContent(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final record = await service.publishContent(
      token: _bearer(request),
      contentId: path[2],
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      'data': record.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _archiveCmsContent(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final record = await service.archiveContent(
      token: _bearer(request),
      contentId: path[2],
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      'data': record.toJson(),
      'request_id': requestId,
    });
  }

  ContentWrite _contentWrite(Map<String, Object?> body) {
    const required = <String>{'title', 'slug', 'excerpt', 'body'};
    const allowed = <String>{
      ...required,
      'kind',
      'tags',
      'author',
      'hero',
      'seo',
    };
    if (!body.keys.toSet().containsAll(required) ||
        body.keys.any((key) => !allowed.contains(key))) {
      throw const ControlPlaneException(
        'INVALID_CONTENT',
        'Content fields are unsupported',
        statusCode: 422,
      );
    }
    try {
      final rawTags = body['tags'];
      if (rawTags != null &&
          (rawTags is! List || rawTags.any((item) => item is! String))) {
        throw const FormatException('Invalid content tags');
      }
      final rawAuthor = body['author'];
      final rawHero = body['hero'];
      final rawSeo = body['seo'];
      return ContentWrite(
        title: _string(body, 'title'),
        slug: _string(body, 'slug'),
        excerpt: _string(body, 'excerpt'),
        body: _string(body, 'body'),
        kind: body['kind'] == null ? null : _contentKind(_string(body, 'kind')),
        tags: rawTags == null ? null : (rawTags as List).cast<String>(),
        author: rawAuthor == null
            ? null
            : ContentAuthorMetadata.fromJson(
                _contentObject(rawAuthor, 'author'),
              ),
        hero: rawHero == null
            ? null
            : ContentHeroMetadata.fromJson(_contentObject(rawHero, 'hero')),
        seo: rawSeo == null
            ? null
            : ContentSeoMetadata.fromJson(_contentObject(rawSeo, 'seo')),
      );
    } on FormatException {
      throw const ControlPlaneException(
        'INVALID_CONTENT',
        'Content payload is invalid',
        statusCode: 422,
      );
    } on TypeError {
      throw const ControlPlaneException(
        'INVALID_CONTENT',
        'Content payload is invalid',
        statusCode: 422,
      );
    }
  }

  Map<String, Object?> _contentObject(Object? value, String field) {
    if (value is! Map) throw FormatException('Invalid content $field');
    return <String, Object?>{
      for (final entry in value.entries) '${entry.key}': entry.value,
    };
  }

  ContentKind _contentKind(String value) {
    try {
      return parseContentKind(value);
    } on FormatException {
      throw const ControlPlaneException(
        'INVALID_CONTENT',
        'Content kind must be blog, news, or policy',
        statusCode: 422,
      );
    }
  }

  ContentStatus _contentStatus(String value) {
    try {
      return parseContentStatus(value);
    } on FormatException {
      throw const ControlPlaneException(
        'INVALID_CONTENT_STATUS',
        'Content status is invalid',
        statusCode: 422,
      );
    }
  }

  Future<void> _createRollout(HttpRequest request, String requestId) async {
    final body = await _jsonBody(request);
    const expected = <String>{
      'organization_id',
      'application_id',
      'environment_id',
      'platform_id',
      'release_id',
      'patch_id',
      'percentage_basis_points',
      'cohort_kind',
      'internal_installation_hashes',
    };
    if (!setEquals(body.keys.toSet(), expected)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Rollout create body fields are unsupported',
      );
    }
    final snapshot = await service.createRollout(
      token: _bearer(request),
      spec: RolloutSpec(
        applicationId: _string(body, 'application_id'),
        environmentId: _string(body, 'environment_id'),
        platformId: _string(body, 'platform_id'),
        releaseId: _string(body, 'release_id'),
        patchId: _string(body, 'patch_id'),
        percentageBasisPoints: _int(body, 'percentage_basis_points'),
        cohortKind: parseRolloutCohortKind(body['cohort_kind']),
        internalInstallationHashes: _stringList(
          body,
          'internal_installation_hashes',
        ),
      ),
      idempotencyKey: _idempotency(request),
      organizationId: _string(body, 'organization_id'),
      requestId: requestId,
    );
    await _json(request.response, 201, <String, Object?>{
      ...snapshot.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _readRollout(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final organizationId = request.uri.queryParameters['organization_id'];
    if (organizationId == null || organizationId.isEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Rollout reads require organization_id',
      );
    }
    final snapshot = await service.readRollout(
      token: _bearer(request),
      rolloutId: path[2],
      organizationId: organizationId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...snapshot.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _transitionRollout(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    const required = <String>{
      'action',
      'expected_revision',
      'reason',
      'organization_id',
    };
    const allowed = <String>{...required, 'percentage_basis_points'};
    if (!body.keys.toSet().containsAll(required) ||
        body.keys.any((key) => !allowed.contains(key))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Rollout transition body fields are unsupported',
      );
    }
    final snapshot = await service.transitionRollout(
      token: _bearer(request),
      rolloutId: path[2],
      action: parseRolloutAction(_string(body, 'action')),
      expectedRevision: _int(body, 'expected_revision'),
      reason: _string(body, 'reason'),
      idempotencyKey: _idempotency(request),
      percentageBasisPoints: _nullableInt(body, 'percentage_basis_points'),
      organizationId: _string(body, 'organization_id'),
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...snapshot.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _readReconciliationDiagnostics(
    HttpRequest request,
    String requestId,
  ) async {
    final observability = reconciliationObservability;
    if (observability == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final scope = _reconciliationScope(request);
    final pageText = request.uri.queryParameters['limit'];
    final limit = pageText == null ? 50 : int.tryParse(pageText);
    if (limit == null) {
      throw const ControlPlaneException(
        'INVALID_PAGE_SIZE',
        'Diagnostic page size must be an integer',
      );
    }
    final codeText = request.uri.queryParameters['code'];
    final statusText = request.uri.queryParameters['status'];
    final outcomeText = request.uri.queryParameters['outcome'];
    final reportOnlyText = request.uri.queryParameters['report_only'];
    final reportOnly = reportOnlyText == null
        ? null
        : switch (reportOnlyText) {
            'true' => true,
            'false' => false,
            _ => throw const ControlPlaneException(
              'INVALID_FILTER',
              'report_only must be true or false',
            ),
          };
    final result = await observability.diagnostics(
      token: _bearer(request),
      scope: scope,
      limit: limit,
      cursor: request.uri.queryParameters['cursor'],
      code: codeText == null ? null : parseReconciliationTaxonomyCode(codeText),
      status: statusText == null
          ? null
          : parseReconciliationFindingStatus(statusText),
      outcome: outcomeText == null
          ? null
          : parseReconciliationRepairResult(outcomeText),
      reportOnly: reportOnly,
      since: _optionalQueryDate(request, 'since'),
      until: _optionalQueryDate(request, 'until'),
    );
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _readReconciliationFinding(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final observability = reconciliationObservability;
    if (observability == null) {
      throw const ControlPlaneException(
        'NOT_FOUND',
        'Resource was not found',
        statusCode: 404,
      );
    }
    final result = await observability.finding(
      token: _bearer(request),
      scope: _reconciliationScope(request),
      findingId: path[3],
    );
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  ReconciliationScope _reconciliationScope(HttpRequest request) {
    final organizationId = request.uri.queryParameters['organization_id'];
    final applicationId = request.uri.queryParameters['application_id'];
    final environmentId = request.uri.queryParameters['environment_id'];
    if (organizationId == null ||
        applicationId == null ||
        environmentId == null ||
        organizationId.isEmpty ||
        applicationId.isEmpty ||
        environmentId.isEmpty) {
      throw const ControlPlaneException(
        'INVALID_SCOPE',
        'Reconciliation diagnostics require exact organization, application, and environment scope',
      );
    }
    return ReconciliationScope(
      organizationId: organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
    );
  }

  DateTime? _optionalQueryDate(HttpRequest request, String key) {
    final value = request.uri.queryParameters[key];
    if (value == null) return null;
    try {
      return DateTime.parse(value).toUtc();
    } on FormatException {
      throw ControlPlaneException(
        'INVALID_TIME_WINDOW',
        '$key is not a valid timestamp',
      );
    }
  }

  Future<void> _registerRelease(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    final token = _bearer(request);
    final spec = ReleaseSpec(
      applicationId: _string(body, 'application_id'),
      platformId: _string(body, 'platform_id'),
      runtimeApplicationId: _string(body, 'runtime_application_id'),
      runtimeReleaseId: _string(body, 'runtime_release_id'),
      buildTarget: _string(body, 'build_target'),
      runtimeCompatibilityVersion: _int(body, 'runtime_compatibility_version'),
      patchFormatVersion: _int(body, 'patch_format_version'),
      buildFingerprint: _string(body, 'build_fingerprint'),
      capabilityAuthorityDigest: _string(body, 'capability_authority_digest'),
      functionSignatureDigest: _string(body, 'function_signature_digest'),
      displayVersion: _string(body, 'display_version'),
      signingPublicKeys: _stringMap(body, 'signing_public_keys'),
    );
    _requirePathMatch(path[4], spec.applicationId, 'application');
    final release = await service.registerRelease(
      token: token,
      spec: spec,
      idempotencyKey: _idempotency(request),
      organizationId: path[2],
      requestId: requestId,
    );
    await _json(request.response, 201, <String, Object?>{
      ...release.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _createApplication(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    final application = await service.createApplication(
      token: _bearer(request),
      organizationId: path[2],
      runtimeApplicationId: _string(body, 'runtime_application_id'),
      name: _optionalString(body, 'name'),
      platform: _optionalString(body, 'platform'),
      idempotencyKey: _idempotency(request),
      requestId: requestId,
    );
    await _json(request.response, 201, <String, Object?>{
      ...application.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _evaluateHealth(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    final evaluationRequest = ManualEvaluationRequest.fromApiJson(
      body,
      rolloutId: path[2],
    );
    final snapshot = await service.evaluateHealth(
      token: _bearer(request),
      rolloutId: path[2],
      request: evaluationRequest,
      idempotencyKey: _idempotency(request),
      organizationId: evaluationRequest.organizationId,
      requestId: requestId,
    );
    await _json(
      request.response,
      snapshot.idempotentReplay ? 200 : 201,
      <String, Object?>{...snapshot.toJson(), 'request_id': requestId},
    );
  }

  Future<void> _applyHealthHalt(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    const expected = <String>{
      'expected_rollout_revision',
      'target_binding_digest',
      'evaluation_input_digest',
      'aggregate_input_digest',
      'aggregate_digest',
      'operator_reason',
    };
    if (!setEquals(body.keys.toSet(), expected)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Health halt application body fields are unsupported',
      );
    }
    final application = await service.applyHealthHalt(
      token: _bearer(request),
      rolloutId: path[2],
      decisionId: path[5],
      expectedRolloutRevision: _int(body, 'expected_rollout_revision'),
      targetBindingDigest: _string(body, 'target_binding_digest'),
      evaluationInputDigest: _string(body, 'evaluation_input_digest'),
      aggregateInputDigest: _string(body, 'aggregate_input_digest'),
      aggregateDigest: _string(body, 'aggregate_digest'),
      operatorReason: _string(body, 'operator_reason'),
      idempotencyKey: _idempotency(request),
      requestId: requestId,
    );
    await _json(
      request.response,
      application.result == 'APPLIED' ? 201 : 200,
      <String, Object?>{...application.toJson(), 'request_id': requestId},
    );
  }

  Future<void> _readHealthEvaluation(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final organizationId = request.uri.queryParameters['organization_id'];
    if (organizationId == null || organizationId.isEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Health evaluation reads require organization_id',
      );
    }
    final snapshot = await service.readHealthEvaluation(
      token: _bearer(request),
      rolloutId: path[2],
      evaluationId: path[5],
      organizationId: organizationId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...snapshot.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _listHealthEvaluations(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final organizationId = request.uri.queryParameters['organization_id'];
    if (organizationId == null || organizationId.isEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Health evaluation lists require organization_id',
      );
    }
    final pageText = request.uri.queryParameters['page_size'];
    final pageSize = pageText == null ? 50 : int.tryParse(pageText);
    if (pageSize == null) {
      throw const ControlPlaneException(
        'INVALID_PAGE_SIZE',
        'Page size must be an integer',
      );
    }
    final page = await service.listHealthEvaluations(
      token: _bearer(request),
      rolloutId: path[2],
      organizationId: organizationId,
      pageSize: pageSize,
      cursor: request.uri.queryParameters['cursor'],
    );
    await _json(request.response, 200, <String, Object?>{
      ...page.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _issueCredential(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    final kindValue = _string(body, 'kind');
    final kind = CredentialKind.values.firstWhere(
      (candidate) => candidate.name == kindValue,
      orElse: () => throw FormatException('Invalid credential kind'),
    );
    final issued = await service.issueCredential(
      token: _bearer(request),
      organizationId: path[2],
      name: _optionalString(body, 'name'),
      kind: kind,
      scopes: _stringSet(body, 'scopes'),
      applicationId: _optionalString(body, 'application_id'),
      environmentId: _optionalString(body, 'environment_id'),
      expiresAt: _optionalDateTime(body, 'expires_at'),
      idempotencyKey: _idempotency(request),
      requestId: requestId,
    );
    await _json(request.response, 201, <String, Object?>{
      ...issued.record.toMetadataJson(),
      'token': issued.token,
      'request_id': requestId,
    });
  }

  Future<void> _createEnvironment(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    final environment = await service.createEnvironment(
      token: _bearer(request),
      organizationId: path[2],
      applicationId: path[4],
      name: _string(body, 'name'),
      idempotencyKey: _idempotency(request),
      requestId: requestId,
    );
    await _json(request.response, 201, <String, Object?>{
      ...environment.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _issueObservationToken(
    HttpRequest request,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    final ttlSeconds = body['ttl_seconds'] == null
        ? service.observationPolicy.tokenLifetime.inSeconds
        : _int(body, 'ttl_seconds');
    final issued = await service.issueObservationToken(
      token: _bearer(request),
      organizationId: _string(body, 'organization_id'),
      applicationId: _string(body, 'application_id'),
      environmentId: _string(body, 'environment_id'),
      lifetime: Duration(seconds: ttlSeconds),
      requestId: requestId,
    );
    await _json(request.response, 201, <String, Object?>{
      ...issued.record.toJson(),
      'token': issued.token,
      'request_id': requestId,
    });
  }

  Future<void> _ingestObservation(HttpRequest request, String requestId) async {
    final body = await _jsonBody(
      request,
      maxBytes: limits.maxObservationBodyBytes,
      tooLargeCode: 'EVENT_TOO_LARGE',
    );
    final event = _observationEvent(body);
    final result = await service.ingestObservation(
      token: _bearer(request),
      event: event,
      requestId: requestId,
    );
    await _json(
      request.response,
      result.duplicate ? 200 : 202,
      <String, Object?>{...result.toJson(), 'request_id': requestId},
    );
  }

  Future<void> _exportAudit(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final retentionText = request.uri.queryParameters['retention_days'];
    final retentionDays = retentionText == null
        ? auditRetentionDays
        : int.tryParse(retentionText);
    if (retentionDays == null || retentionDays <= 0) {
      throw ControlPlaneException(
        'INVALID_RETENTION',
        'Audit retention must be positive',
      );
    }
    final export = await service.exportAudit(
      token: _bearer(request),
      organizationId: path[2],
      retentionDays: retentionDays,
    );
    await _json(request.response, 200, <String, Object?>{
      ...export.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _exportBundle(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final payload = await service.exportBundle(
      token: _bearer(request),
      organizationId: path[2],
      applicationId: path[4],
      environmentId: path[6],
      releaseId: path[8],
      patchId: path[10],
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...payload.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _importBundle(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final trustedKey = _trustedBundleKey(request);
    final bytes = await _bytesBody(
      request,
      maxBytes: limits.maxBundleBytes,
      tooLargeCode: 'BUNDLE_TOO_LARGE',
    );
    final result = await service.importBundle(
      token: _bearer(request),
      organizationId: path[2],
      applicationId: path[4],
      environmentId: path[6],
      bytes: bytes,
      idempotencyKey: _idempotency(request),
      trustedKeyId: trustedKey.keyId,
      trustedPublicKey: trustedKey.publicKey,
      requestId: requestId,
    );
    await _json(
      request.response,
      result.idempotentReplay ? 200 : 201,
      <String, Object?>{...result.toJson(), 'request_id': requestId},
    );
  }

  Future<void> _admitBundle(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final trustedKey = _trustedBundleKey(request);
    final result = await service.admitBundle(
      token: _bearer(request),
      organizationId: path[2],
      applicationId: path[4],
      environmentId: path[6],
      releaseId: path[8],
      patchId: path[9],
      idempotencyKey: _idempotency(request),
      trustedKeyId: trustedKey.keyId,
      trustedPublicKey: trustedKey.publicKey,
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _reconcileArtifacts(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final report = await service.reconcileArtifacts(
      token: _bearer(request),
      organizationId: path[2],
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...report.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _readOperatorOverview(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final overview = await _operatorOverview.read(
      token: _bearer(request),
      organizationId: path[2],
    );
    await _json(request.response, 200, <String, Object?>{
      ...overview.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformMetrics(
    HttpRequest request,
    String requestId,
  ) async {
    final queryKeys = request.uri.queryParameters.keys.toSet();
    if (queryKeys.length > 1 ||
        (queryKeys.isNotEmpty && !queryKeys.contains('profile'))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform metrics supports only the optional profile query parameter',
        statusCode: 422,
      );
    }
    await _humanAuth().authorizePlatformMetrics(
      accessToken: _bearer(request),
      profileName: request.uri.queryParameters['profile'],
    );
    final snapshot = await _platformMetrics.read();
    await _json(request.response, 200, <String, Object?>{
      ...snapshot,
      'serviceMetrics': metrics.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformOrganizations(
    HttpRequest request,
    String requestId,
  ) async {
    final query = request.uri.queryParameters;
    if (query.keys.any((key) => key != 'profile' && key != 'q')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform organizations supports only profile and q query parameters',
        statusCode: 422,
      );
    }
    await _humanAuth().authorizePlatformCapability(
      accessToken: _bearer(request),
      capability: platformOrganizationsReadCapability,
      profileName: query['profile'],
    );
    final projection = await _platformConsole.listOrganizations(
      query: query['q'],
    );
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformOrganization(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final query = request.uri.queryParameters;
    if (query.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform organization reads support only the profile query parameter',
        statusCode: 422,
      );
    }
    await _humanAuth().authorizePlatformCapability(
      accessToken: _bearer(request),
      capability: platformOrganizationsInspectCapability,
      profileName: query['profile'],
    );
    final projection = await _platformConsole.readOrganization(path[3]);
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformAudit(HttpRequest request, String requestId) async {
    final query = request.uri.queryParameters;
    if (query.keys.any((key) => key != 'profile' && key != 'organization_id')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform audit supports only profile and organization_id query parameters',
        statusCode: 422,
      );
    }
    await _humanAuth().authorizePlatformCapability(
      accessToken: _bearer(request),
      capability: platformAuditReadCapability,
      profileName: query['profile'],
    );
    final organizationId = query['organization_id'];
    if (organizationId != null && organizationId.isEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'organization_id must not be empty',
        statusCode: 422,
      );
    }
    final projection = await _platformConsole.readAudit(
      organizationId: organizationId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformUsers(HttpRequest request, String requestId) async {
    final query = request.uri.queryParameters;
    if (query.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform users supports only the profile query parameter',
        statusCode: 422,
      );
    }
    await _humanAuth().authorizePlatformCapability(
      accessToken: _bearer(request),
      capability: platformAccountsReadCapability,
      profileName: query['profile'],
    );
    final projection = await _platformConsole.listUsers();
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformEntitlements(
    HttpRequest request,
    String requestId,
  ) async {
    final query = request.uri.queryParameters;
    if (query.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform entitlements supports only the profile query parameter',
        statusCode: 422,
      );
    }
    await _humanAuth().authorizePlatformCapability(
      accessToken: _bearer(request),
      capability: platformEntitlementsReadCapability,
      profileName: query['profile'],
    );
    final projection = await _platformConsole.readEntitlements();
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformEnterpriseInquiries(
    HttpRequest request,
    String requestId,
  ) async {
    if (request.uri.hasQuery) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise inquiry reads do not accept query parameters',
        statusCode: 422,
      );
    }
    await _humanAuth().authorizePlatformCapability(
      accessToken: _bearer(request),
      capability: platformAccountsReadCapability,
    );
    final projection = await _platformConsole.readEnterpriseInquiries();
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformEnterpriseQuotes(
    HttpRequest request,
    String requestId,
  ) async {
    if (request.uri.hasQuery) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise quote reads do not accept query parameters',
        statusCode: 422,
      );
    }
    await _authorizeEnterprisePlatform(
      request,
      platformEnterpriseQuotesReadCapability,
    );
    final quotes = await service.billing.enterprise.listOperatorQuotes();
    await _json(request.response, 200, <String, Object?>{
      'schemaVersion': 1,
      'quotes': quotes,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformRefundRequests(
    HttpRequest request,
    String requestId,
  ) async {
    if (request.uri.hasQuery) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Refund request reads do not accept query parameters',
        statusCode: 422,
      );
    }
    await _humanAuth().authorizePlatformCapability(
      accessToken: _bearer(request),
      capability: platformBillingRefundsReadCapability,
    );
    final requests = await service.billing.listRefundRequests();
    await _json(request.response, 200, <String, Object?>{
      'schema_version': 1,
      'refund_requests': requests,
      'request_id': requestId,
    });
  }

  Future<void> _approvePlatformRefund(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final identity = await _authorizeRefundReviewPlatform(
      request,
      manage: true,
    );
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{
      'approved_amount_minor',
      'reason',
    })) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Refund approval requires approved_amount_minor and reason',
        statusCode: 422,
      );
    }
    final result = await service.billing.approveRefund(
      refundRequestId: path[4],
      approvedAmountMinor: _int(body, 'approved_amount_minor'),
      actorId: identity.user.id,
      decisionReason: _string(body, 'reason'),
    );
    final organizationId = result['organizationId'];
    if (organizationId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Refund approval is missing its organization',
        statusCode: 500,
      );
    }
    await service.auditEnterpriseCommercialOperation(
      actorId: identity.user.id,
      actorType: 'platform_billing_operator',
      audience: platformAuthorizationAudience,
      organizationId: organizationId,
      requestId: requestId,
      action: 'billing.refund.approved',
      resourceType: 'billing_refund_request',
      resourceId: result['id']! as String,
      metadata: <String, Object?>{
        'approved_amount_minor': result['approvedAmountMinor'],
        'currency': result['currency'],
      },
      stableKey: result['decisionId']! as String,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _rejectPlatformRefund(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final identity = await _authorizeRefundReviewPlatform(
      request,
      manage: true,
    );
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'reason'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Refund rejection requires reason',
        statusCode: 422,
      );
    }
    final result = await service.billing.rejectRefund(
      refundRequestId: path[4],
      actorId: identity.user.id,
      decisionReason: _string(body, 'reason'),
    );
    final organizationId = result['organizationId'];
    if (organizationId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Refund rejection is missing its organization',
        statusCode: 500,
      );
    }
    await service.auditEnterpriseCommercialOperation(
      actorId: identity.user.id,
      actorType: 'platform_billing_operator',
      audience: platformAuthorizationAudience,
      organizationId: organizationId,
      requestId: requestId,
      action: 'billing.refund.rejected',
      resourceType: 'billing_refund_request',
      resourceId: result['id']! as String,
      metadata: <String, Object?>{'reason': body['reason']},
      stableKey: result['decisionId']! as String,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<HumanIdentity> _authorizeRefundReviewPlatform(
    HttpRequest request, {
    required bool manage,
  }) async {
    final token = _bearer(request);
    await _humanAuth().authorizePlatformCapability(
      accessToken: token,
      capability: manage
          ? platformBillingRefundsManageCapability
          : platformBillingRefundsReadCapability,
    );
    return _humanAuth().me(accessToken: token);
  }

  Future<void> _createPlatformEnterpriseQuote(
    HttpRequest request,
    String requestId,
  ) async {
    final identity = await _authorizeEnterprisePlatform(
      request,
      platformEnterpriseQuotesManageCapability,
    );
    final body = await _jsonBody(request);
    const required = <String>{'organization_id', 'entitlement_limits'};
    const allowed = <String>{
      'organization_id',
      'inquiry_id',
      'currency',
      'recurring_amount_minor',
      'interval',
      'valid_until',
      'term_months',
      'total_count',
      'upfront_amount_minor',
      'contact_name',
      'contact_email',
      'support_level',
      'customer_notes',
      'internal_notes',
      'entitlement_limits',
    };
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(required)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise quote fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final terms = _enterpriseQuoteTerms(body);
    final quote = await service.billing.enterprise.createQuote(
      organizationId: _string(body, 'organization_id'),
      terms: terms,
      inquiryId: _optionalString(body, 'inquiry_id'),
      idempotencyKey: _idempotency(request),
    );
    final organizationId = quote['organizationId'];
    if (organizationId is! String) {
      throw const ControlPlaneException(
        'ENTERPRISE_BILLING_STATE_CORRUPT',
        'Created Enterprise quote has no organization',
        statusCode: 500,
      );
    }
    await service.auditEnterpriseCommercialOperation(
      actorId: identity.user.id,
      actorType: 'platform_commercial_operator',
      audience: platformAuthorizationAudience,
      organizationId: organizationId,
      requestId: requestId,
      action: 'enterprise.quote.created',
      resourceType: 'enterprise_quote',
      resourceId: quote['id']! as String,
      metadata: <String, Object?>{'quote_version': quote['currentVersion']},
      stableKey: _idempotency(request),
    );
    await _json(request.response, 201, <String, Object?>{
      ...quote,
      'request_id': requestId,
    });
  }

  Future<void> _issuePlatformEnterpriseQuote(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final identity = await _authorizeEnterprisePlatform(
      request,
      platformEnterpriseQuotesManageCapability,
    );
    final body = await _jsonBody(request);
    if (body.isNotEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Issuing an Enterprise quote does not accept request fields',
        statusCode: 422,
      );
    }
    final quote = await service.billing.enterprise.issueQuote(quoteId: path[3]);
    await _auditEnterpriseQuoteResult(
      identity: identity,
      requestId: requestId,
      action: 'enterprise.quote.issued',
      quote: quote,
    );
    await _json(request.response, 200, <String, Object?>{
      ...quote,
      'request_id': requestId,
    });
  }

  Future<void> _revisePlatformEnterpriseQuote(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final identity = await _authorizeEnterprisePlatform(
      request,
      platformEnterpriseQuotesManageCapability,
    );
    final body = await _jsonBody(request);
    final terms = _enterpriseQuoteTerms(body);
    final quote = await service.billing.enterprise.reviseQuote(
      quoteId: path[3],
      terms: terms,
    );
    await _auditEnterpriseQuoteResult(
      identity: identity,
      requestId: requestId,
      action: 'enterprise.quote.revised',
      quote: quote,
    );
    await _json(request.response, 200, <String, Object?>{
      ...quote,
      'request_id': requestId,
    });
  }

  Future<void> _withdrawPlatformEnterpriseQuote(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final identity = await _authorizeEnterprisePlatform(
      request,
      platformEnterpriseQuotesManageCapability,
    );
    final body = await _jsonBody(request);
    if (body.isNotEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Withdrawing an Enterprise quote does not accept request fields',
        statusCode: 422,
      );
    }
    final quote = await service.billing.enterprise.withdrawQuote(
      quoteId: path[3],
    );
    await _auditEnterpriseQuoteResult(
      identity: identity,
      requestId: requestId,
      action: 'enterprise.quote.withdrawn',
      quote: quote,
    );
    await _json(request.response, 200, <String, Object?>{
      ...quote,
      'request_id': requestId,
    });
  }

  Future<HumanIdentity> _authorizeEnterprisePlatform(
    HttpRequest request,
    String capability,
  ) async {
    final accessToken = _bearer(request);
    await _humanAuth().authorizePlatformCapability(
      accessToken: accessToken,
      capability: capability,
    );
    return _humanAuth().me(accessToken: accessToken);
  }

  Future<void> _auditEnterpriseQuoteResult({
    required HumanIdentity identity,
    required String requestId,
    required String action,
    required Map<String, Object?> quote,
  }) async {
    final organizationId = quote['organizationId'];
    final quoteId = quote['id'];
    if (organizationId is! String || quoteId is! String) {
      throw const ControlPlaneException(
        'ENTERPRISE_BILLING_STATE_CORRUPT',
        'Enterprise quote response is missing its identity',
        statusCode: 500,
      );
    }
    await service.auditEnterpriseCommercialOperation(
      actorId: identity.user.id,
      actorType: 'platform_commercial_operator',
      audience: platformAuthorizationAudience,
      organizationId: organizationId,
      requestId: requestId,
      action: action,
      resourceType: 'enterprise_quote',
      resourceId: quoteId,
    );
  }

  Future<void> _readCredentials(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    if (request.uri.hasQuery) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Credential metadata does not accept query parameters',
        statusCode: 422,
      );
    }
    final credentials = await service.listCredentials(
      token: _bearer(request),
      organizationId: path[2],
    );
    await _json(request.response, 200, <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'credentials': credentials,
      'request_id': requestId,
    });
  }

  Future<void> _readOrganizationMembers(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    if (request.uri.hasQuery) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Organization member reads do not accept query parameters',
        statusCode: 422,
      );
    }
    final members = await service.listOrganizationMembers(
      token: _bearer(request),
      organizationId: path[2],
    );
    await _json(request.response, 200, <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'members': members,
      'request_id': requestId,
    });
  }

  Future<void> _readBilling(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingReadScope,
      organizationId: path[2],
    );
    final snapshot = await service.billing.read(
      organizationId: actor.organizationId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...snapshot.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _readCustomerEnterpriseQuote(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingReadScope,
      organizationId: path[2],
    );
    final quote = await service.billing.enterprise.readCustomerQuote(
      organizationId: actor.organizationId,
      quoteId: path[5],
    );
    await _json(request.response, 200, <String, Object?>{
      ...quote,
      'request_id': requestId,
    });
  }

  Future<void> _acceptCustomerEnterpriseQuote(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'version_id'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise quote acceptance requires version_id',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingManageScope,
      organizationId: path[2],
    );
    final result = await service.billing.enterprise.acceptQuote(
      organizationId: actor.organizationId,
      quoteId: path[5],
      versionId: _string(body, 'version_id'),
      actorId: actor.id,
    );
    final quote = result['quote']! as Map<String, Object?>;
    final contract = result['contract']! as Map<String, Object?>;
    await service.auditEnterpriseCommercialOperation(
      actorId: actor.id,
      actorType: 'customer_owner',
      audience: customerAuthorizationAudience,
      organizationId: actor.organizationId,
      requestId: requestId,
      action: 'enterprise.quote.accepted',
      resourceType: 'enterprise_quote',
      resourceId: quote['id']! as String,
      metadata: <String, Object?>{
        'quote_version_id': quote['currentVersionId'],
        'contract_id': contract['id'],
      },
      stableKey: quote['currentVersionId']! as String,
    );
    await service.auditEnterpriseCommercialOperation(
      actorId: actor.id,
      actorType: 'customer_owner',
      audience: customerAuthorizationAudience,
      organizationId: actor.organizationId,
      requestId: requestId,
      action: 'enterprise.contract.created',
      resourceType: 'enterprise_contract',
      resourceId: contract['id']! as String,
      metadata: <String, Object?>{
        'quote_id': quote['id'],
        'quote_version_id': quote['currentVersionId'],
        'status': contract['status'],
      },
      stableKey: contract['id']! as String,
    );
    await _json(request.response, 201, <String, Object?>{
      'quote': quote,
      'contract': contract,
      'request_id': requestId,
    });
  }

  Future<void> _rejectCustomerEnterpriseQuote(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'version_id'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise quote rejection requires version_id',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingManageScope,
      organizationId: path[2],
    );
    final quote = await service.billing.enterprise.rejectQuote(
      organizationId: actor.organizationId,
      quoteId: path[5],
      versionId: _string(body, 'version_id'),
    );
    await service.auditEnterpriseCommercialOperation(
      actorId: actor.id,
      actorType: 'customer_owner',
      audience: customerAuthorizationAudience,
      organizationId: actor.organizationId,
      requestId: requestId,
      action: 'enterprise.quote.rejected',
      resourceType: 'enterprise_quote',
      resourceId: quote['id']! as String,
      metadata: <String, Object?>{
        'quote_version_id': quote['currentVersionId'],
      },
      stableKey: quote['currentVersionId']! as String,
    );
    await _json(request.response, 200, <String, Object?>{
      ...quote,
      'request_id': requestId,
    });
  }

  Future<void> _requestEnterpriseCancellation(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (body.isNotEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise cancellation does not accept request fields',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingManageScope,
      organizationId: path[2],
    );
    final contract = await service.billing.enterprise.requestCancellation(
      organizationId: actor.organizationId,
    );
    if (contract['id'] is String &&
        contract['status'] == 'cancellation_scheduled') {
      await service.auditEnterpriseCommercialOperation(
        actorId: actor.id,
        actorType: 'customer_owner',
        audience: customerAuthorizationAudience,
        organizationId: actor.organizationId,
        requestId: requestId,
        action: 'enterprise.cancellation.requested',
        resourceType: 'enterprise_contract',
        resourceId: contract['id']! as String,
      );
    }
    await _json(request.response, 200, <String, Object?>{
      'contract': contract,
      'request_id': requestId,
    });
  }

  Future<void> _startBillingCheckout(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'plan_key'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Billing checkout requires a plan_key',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingManageScope,
      organizationId: path[2],
    );
    final checkout = await service.billing.startCheckout(
      organizationId: actor.organizationId,
      planKey: _string(body, 'plan_key'),
      idempotencyKey: _idempotency(request),
    );
    if (checkout['id'] is String) {
      await service.auditBilling(
        actor: actor,
        requestId: requestId,
        action: 'billing.checkout.initiated',
        resourceId: checkout['id']! as String,
        metadata: <String, Object?>{
          'plan': checkout['planKey'],
          'provider': checkout['provider'],
          'amount_minor': checkout['amountMinor'],
          'currency': checkout['currency'],
        },
        stableKey: _idempotency(request),
      );
    }
    await _json(
      request.response,
      checkout['status'] == 'already_active' ? 200 : 201,
      <String, Object?>{...checkout, 'request_id': requestId},
    );
  }

  Future<void> _requestBillingRefund(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    const required = <String>{'payment_id', 'reason_category', 'explanation'};
    const allowed = <String>{...required, 'requested_amount_minor'};
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(required)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Refund request fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingManageScope,
      organizationId: path[2],
    );
    final result = await service.billing.requestRefund(
      organizationId: actor.organizationId,
      paymentId: _string(body, 'payment_id'),
      reasonCategory: _string(body, 'reason_category'),
      explanation: _string(body, 'explanation'),
      requestedAmountMinor: _nullableInt(body, 'requested_amount_minor'),
      idempotencyKey: _idempotency(request),
      actorId: actor.id,
    );
    await service.auditBilling(
      actor: actor,
      requestId: requestId,
      action: 'billing.refund.requested',
      resourceId: result['id']! as String,
      metadata: <String, Object?>{
        'payment_id': result['paymentId'],
        'reason_category': result['reasonCategory'],
        'requested_amount_minor': result['requestedAmountMinor'],
        'currency': result['currency'],
      },
      stableKey: _idempotency(request),
    );
    await _json(request.response, 201, <String, Object?>{
      ..._customerRefundResponse(result),
      'request_id': requestId,
    });
  }

  Future<void> _requestBillingPlanChange(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    const required = <String>{'target_plan_key'};
    if (body.keys.any((key) => !required.contains(key)) ||
        !body.keys.toSet().containsAll(required)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Scheduled plan change fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingManageScope,
      organizationId: path[2],
    );
    final target = _string(body, 'target_plan_key');
    if (target == cloudPlanFreeKey) {
      throw const ControlPlaneException(
        'INVALID_PLAN_TRANSITION',
        'Use the billing cancellation operation to stop renewal and return to Free',
        statusCode: 422,
      );
    }
    final change = await service.billing.prepareScheduledPlanChange(
      organizationId: actor.organizationId,
      targetPlanKey: target,
      actorId: actor.id,
    );
    final resourceId = change['id'];
    if (resourceId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Scheduled plan change is missing its identity',
        statusCode: 500,
      );
    }
    await service.auditBilling(
      actor: actor,
      requestId: requestId,
      action: 'billing.plan_change.requested',
      resourceId: resourceId,
      metadata: <String, Object?>{
        'current_plan': change['currentPlanKey'],
        'target_plan': change['targetPlanKey'],
        'status': change['status'],
        'effective_at': change['effectiveAt'],
      },
      stableKey: '${resourceId}:${change['revision']}',
    );
    await _json(request.response, 201, <String, Object?>{
      ...change,
      'request_id': requestId,
    });
  }

  Future<void> _cancelBillingPlanChange(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (body.isNotEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Scheduled plan change cancellation does not accept request fields',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingManageScope,
      organizationId: path[2],
    );
    final change = await service.billing.cancelScheduledPlanChange(
      organizationId: actor.organizationId,
    );
    final resourceId = change['id'];
    if (change['status'] == 'cancelled' && resourceId is String) {
      await service.auditBilling(
        actor: actor,
        requestId: requestId,
        action: 'billing.plan_change.cancelled',
        resourceId: resourceId,
        metadata: <String, Object?>{
          'target_plan': change['targetPlanKey'],
          'status': change['status'],
        },
        stableKey: '${resourceId}:${change['revision']}',
      );
    }
    await _json(request.response, 200, <String, Object?>{
      ...change,
      'request_id': requestId,
    });
  }

  Future<void> _requestBillingCancellation(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (body.isNotEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Billing cancellation does not accept request fields',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingManageScope,
      organizationId: path[2],
    );
    final cancellation = await service.billing.requestCancellation(
      organizationId: actor.organizationId,
      actorId: actor.id,
    );
    if (cancellation['status'] == 'scheduled') {
      await service.auditBilling(
        actor: actor,
        requestId: requestId,
        action: 'billing.cancellation.requested',
        resourceId: cancellation['subscriptionId']! as String,
        metadata: <String, Object?>{
          'status': cancellation['status'],
          'effective_at': cancellation['effectiveAt'],
          'scheduled_plan_change_id': cancellation['scheduledPlanChangeId'],
        },
        stableKey: cancellation['subscriptionId']! as String,
      );
    }
    await _json(request.response, 200, <String, Object?>{
      ...cancellation,
      'request_id': requestId,
    });
  }

  Future<void> _confirmBillingScheduledPlanChange(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final actor = await service.authorizeBillingProvider(
      token: _bearer(request),
    );
    final body = await _jsonBody(request);
    const allowed = <String>{
      'provider_plan_id',
      'provider_status',
      'has_scheduled_changes',
      'schedule_change_at',
      'change_scheduled_at',
      'current_end_at',
    };
    const required = <String>{'provider_plan_id', 'has_scheduled_changes'};
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(required)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Provider scheduled change fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    if (body['has_scheduled_changes'] is! bool) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'has_scheduled_changes must be a boolean',
        statusCode: 422,
      );
    }
    final change = await service.billing.confirmScheduledPlanChange(
      providerSubscriptionId: path[4],
      providerPlanId: _string(body, 'provider_plan_id'),
      providerStatus: _nullableString(body, 'provider_status'),
      hasScheduledChanges: body['has_scheduled_changes']! as bool,
      scheduleChangeAt: _nullableString(body, 'schedule_change_at'),
      changeScheduledAt: _nullableString(body, 'change_scheduled_at'),
      currentEndAt: _nullableString(body, 'current_end_at'),
    );
    final organizationId = change['organizationId'];
    final resourceId = change['id'];
    if (organizationId is! String || resourceId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Provider scheduled change is missing its identity',
        statusCode: 500,
      );
    }
    await service.auditBillingProviderOperation(
      actor: actor,
      organizationId: organizationId,
      requestId: requestId,
      action: 'billing.provider_plan_change.scheduled',
      resourceId: resourceId,
      metadata: <String, Object?>{
        'provider_subscription_id': change['providerSubscriptionId'],
        'provider_plan_id': change['targetProviderPlanId'],
        'target_plan': change['targetPlanKey'],
        'status': change['status'],
        'effective_at': change['effectiveAt'],
      },
      stableKey: '${change['providerSubscriptionId']}:${change['revision']}',
    );
    await _json(request.response, 200, <String, Object?>{
      ...change,
      'request_id': requestId,
    });
  }

  Future<void> _cancelBillingCheckout(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (body.isNotEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Billing checkout cancellation does not accept request fields',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingManageScope,
      organizationId: path[2],
    );
    final checkout = await service.billing.cancelCheckout(
      organizationId: actor.organizationId,
      checkoutId: path[5],
    );
    await service.auditBilling(
      actor: actor,
      requestId: requestId,
      action: 'billing.checkout.cancelled',
      resourceId: checkout['id']! as String,
      metadata: <String, Object?>{
        'plan': checkout['planKey'],
        'status': checkout['status'],
      },
      stableKey: checkout['id']! as String,
    );
    await _json(request.response, 200, <String, Object?>{
      ...checkout,
      'request_id': requestId,
    });
  }

  Future<void> _applyRazorpayBillingWebhook(
    HttpRequest request,
    String requestId,
  ) async {
    final signature = request.headers.value('x-razorpay-signature');
    if (signature == null || signature.isEmpty) {
      throw const ControlPlaneException(
        'INVALID_BILLING_SIGNATURE',
        'Razorpay webhook signature is required',
        statusCode: 401,
      );
    }
    final rawBody = await _bytesBody(
      request,
      maxBytes: limits.maxJsonBodyBytes,
      tooLargeCode: 'REQUEST_TOO_LARGE',
    );
    final result = await service.billing.applyRazorpayWebhook(
      rawBody: rawBody,
      signature: signature,
      eventIdOverride: request.headers.value('x-razorpay-event-id'),
    );
    await service.auditBillingProviderEvent(
      result: result,
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _linkBillingProviderSubscription(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final actor = await service.authorizeBillingProvider(
      token: _bearer(request),
    );
    final body = await _jsonBody(request);
    const allowed = <String>{
      'provider_subscription_id',
      'provider_plan_id',
      'provider_status',
      'user_id',
      'total_count',
      'paid_count',
      'remaining_count',
      'current_start_at',
      'current_end_at',
      'cancel_at_cycle_end',
    };
    const required = <String>{'provider_subscription_id', 'provider_plan_id'};
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(required)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Provider subscription link fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    if (body['cancel_at_cycle_end'] != null &&
        body['cancel_at_cycle_end'] is! bool) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'cancel_at_cycle_end must be a boolean',
        statusCode: 422,
      );
    }
    final subscription = await service.billing.linkProviderSubscription(
      checkoutId: path[4],
      providerSubscriptionId: _string(body, 'provider_subscription_id'),
      providerPlanId: _string(body, 'provider_plan_id'),
      providerStatus: _nullableString(body, 'provider_status'),
      userId: _nullableString(body, 'user_id'),
      totalCount: _nullableInt(body, 'total_count'),
      paidCount: _nullableInt(body, 'paid_count'),
      remainingCount: _nullableInt(body, 'remaining_count'),
      currentStartAt: _nullableString(body, 'current_start_at'),
      currentEndAt: _nullableString(body, 'current_end_at'),
      cancelAtCycleEnd: body['cancel_at_cycle_end'] as bool?,
    );
    await service.auditBillingProviderOperation(
      actor: actor,
      organizationId: subscription['organizationId']! as String,
      requestId: requestId,
      action: 'billing.provider_subscription.linked',
      resourceId: subscription['id']! as String,
      metadata: <String, Object?>{
        'provider': subscription['provider'],
        'provider_subscription_id': subscription['providerSubscriptionId'],
        'provider_plan_id': subscription['providerPlanId'],
        'status': subscription['status'],
      },
      stableKey: subscription['providerSubscriptionId']! as String,
    );
    await _json(request.response, 200, <String, Object?>{
      ...subscription,
      'request_id': requestId,
    });
  }

  Future<void> _syncBillingProviderSubscription(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final actor = await service.authorizeBillingProvider(
      token: _bearer(request),
    );
    final body = await _jsonBody(request);
    const allowed = <String>{
      'provider_plan_id',
      'provider_status',
      'user_id',
      'total_count',
      'paid_count',
      'remaining_count',
      'current_start_at',
      'current_end_at',
      'cancel_at_cycle_end',
    };
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.containsKey('provider_plan_id')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Provider subscription sync fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    if (body['cancel_at_cycle_end'] != null &&
        body['cancel_at_cycle_end'] is! bool) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'cancel_at_cycle_end must be a boolean',
        statusCode: 422,
      );
    }
    final subscription = await service.billing.syncProviderSubscription(
      providerSubscriptionId: path[4],
      providerPlanId: _string(body, 'provider_plan_id'),
      providerStatus: _nullableString(body, 'provider_status'),
      userId: _nullableString(body, 'user_id'),
      totalCount: _nullableInt(body, 'total_count'),
      paidCount: _nullableInt(body, 'paid_count'),
      remainingCount: _nullableInt(body, 'remaining_count'),
      currentStartAt: _nullableString(body, 'current_start_at'),
      currentEndAt: _nullableString(body, 'current_end_at'),
      cancelAtCycleEnd: body['cancel_at_cycle_end'] as bool?,
    );
    await service.auditBillingProviderOperation(
      actor: actor,
      organizationId: subscription['organizationId']! as String,
      requestId: requestId,
      action: 'billing.provider_subscription.synced',
      resourceId: subscription['id']! as String,
      metadata: <String, Object?>{
        'provider': subscription['provider'],
        'provider_subscription_id': subscription['providerSubscriptionId'],
        'provider_plan_id': subscription['providerPlanId'],
        'status': subscription['status'],
      },
      stableKey:
          '${subscription['providerSubscriptionId']}:${subscription['cancelAtCycleEnd']}',
    );
    await _json(request.response, 200, <String, Object?>{
      ...subscription,
      'request_id': requestId,
    });
  }

  Future<void> _prepareBillingProviderRefund(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final actor = await service.authorizeBillingProvider(
      token: _bearer(request),
    );
    final body = await _jsonBody(request);
    if (body.isNotEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Provider refund preparation does not accept request fields',
        statusCode: 422,
      );
    }
    final result = await service.billing.prepareProviderRefund(
      refundRequestId: path[4],
    );
    final organizationId = result['organizationId'];
    final attemptId = result['providerRefundRecordId'];
    if (organizationId is! String || attemptId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Provider refund preparation is missing its identity',
        statusCode: 500,
      );
    }
    await service.auditBillingProviderOperation(
      actor: actor,
      organizationId: organizationId,
      requestId: requestId,
      action: 'billing.refund.provider_prepared',
      resourceId: attemptId,
      metadata: <String, Object?>{
        'refund_request_id': result['refundRequestId'],
        'amount_minor': result['amountMinor'],
        'currency': result['currency'],
        'status': result['status'],
      },
      stableKey: attemptId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _recordBillingProviderRefundResult(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final actor = await service.authorizeBillingProvider(
      token: _bearer(request),
    );
    final body = await _jsonBody(request);
    const required = <String>{'provider_refund_record_id', 'status'};
    const allowed = <String>{
      ...required,
      'provider_refund_id',
      'amount_minor',
      'currency',
      'error_code',
    };
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(required)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Provider refund result fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final result = await service.billing.recordProviderRefundResult(
      refundRequestId: path[4],
      providerRefundRecordId: _string(body, 'provider_refund_record_id'),
      status: _string(body, 'status'),
      providerRefundId: _nullableString(body, 'provider_refund_id'),
      amountMinor: _nullableInt(body, 'amount_minor'),
      currency: _nullableString(body, 'currency'),
      errorCode: _nullableString(body, 'error_code'),
    );
    final organizationId = result['organizationId'];
    final providerRefund = result['providerRefund'];
    final resourceId = providerRefund is Map
        ? providerRefund['id']
        : body['provider_refund_record_id'];
    if (organizationId is! String || resourceId is! String) {
      throw const ControlPlaneException(
        'BILLING_STATE_CORRUPT',
        'Provider refund result is missing its identity',
        statusCode: 500,
      );
    }
    await service.auditBillingProviderOperation(
      actor: actor,
      organizationId: organizationId,
      requestId: requestId,
      action: 'billing.refund.provider_result',
      resourceId: resourceId,
      metadata: <String, Object?>{
        'refund_request_id': result['id'],
        'status': result['status'],
        'provider_status': providerRefund is Map
            ? providerRefund['status']
            : null,
      },
      stableKey: '$resourceId:${body['status']}',
    );
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _linkEnterpriseProviderSubscription(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final actor = await service.authorizeBillingProvider(
      token: _bearer(request),
    );
    final body = await _jsonBody(request);
    const allowed = <String>{
      'provider_subscription_id',
      'provider_plan_id',
      'provider_status',
      'amount_minor',
      'currency',
      'interval',
      'total_count',
      'paid_count',
      'remaining_count',
      'current_start_at',
      'current_end_at',
      'cancel_at_cycle_end',
    };
    const required = <String>{
      'provider_subscription_id',
      'provider_plan_id',
      'provider_status',
      'amount_minor',
      'currency',
      'interval',
    };
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(required)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise provider link fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final subscription = await service.billing.enterprise
        .linkProviderSubscription(
          contractId: path[4],
          providerSubscriptionId: _string(body, 'provider_subscription_id'),
          providerPlanId: _string(body, 'provider_plan_id'),
          providerStatus: _string(body, 'provider_status'),
          amountMinor: _int(body, 'amount_minor'),
          currency: _string(body, 'currency'),
          interval: _string(body, 'interval'),
          totalCount: _nullableInt(body, 'total_count'),
          paidCount: _nullableInt(body, 'paid_count'),
          remainingCount: _nullableInt(body, 'remaining_count'),
          currentStartAt: _nullableString(body, 'current_start_at'),
          currentEndAt: _nullableString(body, 'current_end_at'),
          cancelAtCycleEnd: body['cancel_at_cycle_end'] as bool?,
        );
    final value = subscription['subscription']! as Map<String, Object?>;
    await service.auditBillingProviderOperation(
      actor: actor,
      organizationId: value['organizationId']! as String,
      requestId: requestId,
      action: 'enterprise.provider_subscription.linked',
      resourceId: value['id']! as String,
      metadata: <String, Object?>{
        'provider_subscription_id': value['providerSubscriptionId'],
        'provider_plan_id': value['providerPlanId'],
        'status': value['status'],
      },
      stableKey: value['providerSubscriptionId']! as String,
    );
    await _json(request.response, 200, <String, Object?>{
      ...subscription,
      'request_id': requestId,
    });
  }

  Future<void> _linkEnterpriseProviderPlan(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final actor = await service.authorizeBillingProvider(
      token: _bearer(request),
    );
    final body = await _jsonBody(request);
    const allowed = <String>{
      'provider_plan_id',
      'amount_minor',
      'currency',
      'interval',
    };
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(allowed)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise provider plan fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final contract = await service.billing.enterprise.linkProviderPlan(
      contractId: path[4],
      providerPlanId: _string(body, 'provider_plan_id'),
      amountMinor: _int(body, 'amount_minor'),
      currency: _string(body, 'currency'),
      interval: _string(body, 'interval'),
    );
    final organizationId = contract['organizationId'];
    final contractId = contract['id'];
    if (organizationId is! String || contractId is! String) {
      throw const ControlPlaneException(
        'ENTERPRISE_BILLING_STATE_CORRUPT',
        'Enterprise provider plan link has no contract identity',
        statusCode: 500,
      );
    }
    await service.auditBillingProviderOperation(
      actor: actor,
      organizationId: organizationId,
      requestId: requestId,
      action: 'enterprise.provider_plan.linked',
      resourceId: contractId,
      metadata: <String, Object?>{
        'provider_plan_id': contract['providerPlanId'],
        'amount_minor': contract['providerAmountMinor'],
        'currency': contract['providerCurrency'],
        'interval': contract['providerInterval'],
      },
      stableKey: contract['providerPlanId']! as String,
    );
    await _json(request.response, 200, <String, Object?>{
      ...contract,
      'request_id': requestId,
    });
  }

  Future<void> _readEnterpriseProviderContract(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    await service.authorizeBillingProvider(token: _bearer(request));
    if (request.uri.hasQuery) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise provider contract reads do not accept query parameters',
        statusCode: 422,
      );
    }
    final contract = await service.billing.enterprise.providerContract(path[4]);
    await _json(request.response, 200, <String, Object?>{
      ...contract,
      'request_id': requestId,
    });
  }

  Future<void> _syncEnterpriseProviderSubscription(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final actor = await service.authorizeBillingProvider(
      token: _bearer(request),
    );
    final body = await _jsonBody(request);
    const allowed = <String>{
      'provider_plan_id',
      'provider_status',
      'total_count',
      'paid_count',
      'remaining_count',
      'current_start_at',
      'current_end_at',
      'cancel_at_cycle_end',
    };
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.containsKey('provider_plan_id')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise provider sync fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final subscription = await service.billing.enterprise
        .syncProviderSubscription(
          providerSubscriptionId: path[4],
          providerPlanId: _string(body, 'provider_plan_id'),
          providerStatus: _nullableString(body, 'provider_status'),
          totalCount: _nullableInt(body, 'total_count'),
          paidCount: _nullableInt(body, 'paid_count'),
          remainingCount: _nullableInt(body, 'remaining_count'),
          currentStartAt: _nullableString(body, 'current_start_at'),
          currentEndAt: _nullableString(body, 'current_end_at'),
          cancelAtCycleEnd: body['cancel_at_cycle_end'] as bool?,
        );
    await service.auditBillingProviderOperation(
      actor: actor,
      organizationId: subscription['organizationId']! as String,
      requestId: requestId,
      action: 'enterprise.provider_subscription.synced',
      resourceId: subscription['id']! as String,
      metadata: <String, Object?>{
        'provider_subscription_id': subscription['providerSubscriptionId'],
        'provider_plan_id': subscription['providerPlanId'],
        'status': subscription['status'],
      },
      stableKey:
          '${subscription['providerSubscriptionId']}:${subscription['cancelAtCycleEnd']}',
    );
    await _json(request.response, 200, <String, Object?>{
      ...subscription,
      'request_id': requestId,
    });
  }

  Future<void> _applyBillingProviderWebhook(
    HttpRequest request,
    String requestId,
  ) async {
    final actor = await service.authorizeBillingProvider(
      token: _bearer(request),
    );
    final body = await _jsonBody(request);
    const allowed = <String>{'raw_body', 'signature', 'event_id'};
    const required = <String>{'raw_body', 'signature'};
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(required)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Provider webhook fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final rawBody = _string(body, 'raw_body');
    final signature = _string(body, 'signature');
    final result = await service.billing.applyRazorpayWebhook(
      rawBody: utf8.encode(rawBody),
      signature: signature,
      eventIdOverride: _nullableString(body, 'event_id'),
    );
    await service.auditBillingProviderEvent(
      result: result,
      requestId: requestId,
      actorId: actor.id,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _createBillingPlan(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    const expected = <String>{
      'key',
      'name',
      'description',
      'currency',
      'amount_minor',
      'interval',
      'period',
      'provider',
      'provider_plan_id',
    };
    if (!setEquals(body.keys.toSet(), expected)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Billing plan fields are unsupported',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingWriteScope,
      organizationId: path[2],
    );
    final plan = await service.billing.createPlan(
      organizationId: actor.organizationId,
      key: _string(body, 'key'),
      name: _string(body, 'name'),
      description: _string(body, 'description'),
      currency: _string(body, 'currency'),
      amountMinor: _int(body, 'amount_minor'),
      interval: _string(body, 'interval'),
      period: _int(body, 'period'),
      provider: _string(body, 'provider'),
      providerPlanId: _string(body, 'provider_plan_id'),
    );
    await service.auditBilling(
      actor: actor,
      requestId: requestId,
      action: 'billing.plan.created',
      resourceId: plan['id']! as String,
      metadata: <String, Object?>{
        'planKey': plan['key'],
        'provider': plan['provider'],
        'currency': plan['currency'],
        'amountMinor': plan['amountMinor'],
      },
    );
    await _json(request.response, 201, <String, Object?>{
      ...plan,
      'request_id': requestId,
    });
  }

  Future<void> _setBillingPlanActive(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'active'}) ||
        body['active'] is! bool) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Billing plan activation requires an active boolean',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingWriteScope,
      organizationId: path[2],
    );
    final plan = await service.billing.setPlanActive(
      organizationId: actor.organizationId,
      planId: path[5],
      active: body['active']! as bool,
    );
    await service.auditBilling(
      actor: actor,
      requestId: requestId,
      action: 'billing.plan.status_changed',
      resourceId: plan['id']! as String,
      metadata: <String, Object?>{'active': plan['active']},
    );
    await _json(request.response, 200, <String, Object?>{
      ...plan,
      'request_id': requestId,
    });
  }

  Future<void> _upsertBillingSubscription(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    const allowed = <String>{
      'provider',
      'provider_subscription_id',
      'provider_plan_id',
      'status',
      'plan_id',
      'user_id',
      'checkout_id',
      'total_count',
      'paid_count',
      'remaining_count',
      'current_start_at',
      'current_end_at',
      'cancel_at_cycle_end',
    };
    const required = <String>{
      'provider',
      'provider_subscription_id',
      'provider_plan_id',
      'status',
    };
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(required)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Billing subscription fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    if (body['cancel_at_cycle_end'] != null &&
        body['cancel_at_cycle_end'] is! bool) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'cancel_at_cycle_end must be a boolean',
        statusCode: 422,
      );
    }
    if (body['checkout_id'] != null && body['checkout_id'] is! String) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'checkout_id must be a string',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingWriteScope,
      organizationId: path[2],
    );
    final subscription = await service.billing.upsertSubscription(
      organizationId: actor.organizationId,
      provider: _string(body, 'provider'),
      providerSubscriptionId: _string(body, 'provider_subscription_id'),
      providerPlanId: _string(body, 'provider_plan_id'),
      status: _string(body, 'status'),
      planId: _optionalString(body, 'plan_id'),
      userId: _optionalString(body, 'user_id'),
      checkoutId: _optionalString(body, 'checkout_id'),
      totalCount: _nullableInt(body, 'total_count'),
      paidCount: _nullableInt(body, 'paid_count'),
      remainingCount: _nullableInt(body, 'remaining_count'),
      currentStartAt: _optionalString(body, 'current_start_at'),
      currentEndAt: _optionalString(body, 'current_end_at'),
      cancelAtCycleEnd: body['cancel_at_cycle_end'] as bool?,
    );
    await service.auditBilling(
      actor: actor,
      requestId: requestId,
      action: 'billing.subscription.updated',
      resourceId: subscription['id']! as String,
      metadata: <String, Object?>{
        'provider': subscription['provider'],
        'status': subscription['status'],
        'planId': subscription['planId'],
      },
    );
    await _json(request.response, 200, <String, Object?>{
      ...subscription,
      'request_id': requestId,
    });
  }

  Future<void> _recordBillingEvent(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    const allowed = <String>{
      'provider',
      'event_id',
      'event_name',
      'payload_digest',
      'provider_subscription_id',
      'occurred_at',
    };
    const required = <String>{
      'provider',
      'event_id',
      'event_name',
      'payload_digest',
    };
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(required)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Billing event fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final actor = await service.authorizeControlCredential(
      token: _bearer(request),
      requiredScope: billingWriteScope,
      organizationId: path[2],
    );
    final created = await service.billing.recordEvent(
      organizationId: actor.organizationId,
      provider: _string(body, 'provider'),
      eventId: _string(body, 'event_id'),
      eventName: _string(body, 'event_name'),
      payloadDigest: _string(body, 'payload_digest'),
      providerSubscriptionId: _optionalString(body, 'provider_subscription_id'),
      occurredAt: _optionalString(body, 'occurred_at'),
    );
    await _json(request.response, created ? 201 : 200, <String, Object?>{
      'event_recorded': created,
      'request_id': requestId,
    });
  }

  Future<void> _registerPatch(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    final token = _bearer(request);
    final spec = PatchSpec(
      runtimePatchId: _string(body, 'runtime_patch_id'),
      sequence: _int(body, 'sequence'),
      artifactId: _string(body, 'artifact_id'),
      sha256: _string(body, 'sha256'),
      sizeBytes: _int(body, 'size_bytes'),
      signatureKeyId: _string(body, 'signature_key_id'),
    );
    final patch = await service.registerPatch(
      token: token,
      releaseId: path[4],
      spec: spec,
      idempotencyKey: _idempotency(request),
      organizationId: path[2],
      requestId: requestId,
    );
    await _json(request.response, 201, <String, Object?>{
      ...patch.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _uploadArtifact(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final bytes = await _bytesBody(request, maxBytes: limits.maxArtifactBytes);
    final artifact = await service.uploadArtifact(
      token: _bearer(request),
      artifactId: path[4],
      bytes: bytes,
      idempotencyKey: _idempotency(request),
      organizationId: path[2],
      requestId: requestId,
    );
    request.response.headers.set('ETag', '"${artifact.sha256}"');
    await _json(request.response, 200, <String, Object?>{
      ...artifact.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _promote(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    final expectedVersion =
        _ifMatchVersion(request) ?? _int(body, 'expected_version');
    final environment = await service.promote(
      token: _bearer(request),
      environmentId: path[4],
      releaseId: _string(body, 'release_id'),
      expectedVersion: expectedVersion,
      idempotencyKey: _idempotency(request),
      organizationId: path[2],
      requestId: requestId,
    );
    request.response.headers.set(
      'ETag',
      '"environment-v${environment.version}"',
    );
    await _json(request.response, 200, <String, Object?>{
      ...environment.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _rollback(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    final result = await service.requestRollback(
      token: _bearer(request),
      organizationId: path[2],
      applicationId: path[4],
      environmentId: path[6],
      rollbackControl: _string(body, 'rollback_control'),
      idempotencyKey: _idempotency(request),
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _updateCheck(HttpRequest request, String requestId) async {
    final body = await _jsonBody(request);
    final highWater = body['high_water'];
    if (highWater != null && highWater is! Map<String, Object?>) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'high_water must be a JSON object',
      );
    }
    final result = await service.updateCheck(
      token: _bearer(request),
      request: UpdateCheckRequest(
        applicationId: _string(body, 'application_id'),
        environmentId: _string(body, 'environment_id'),
        runtimeApplicationId: _string(body, 'runtime_application_id'),
        runtimeReleaseId: _string(body, 'runtime_release_id'),
        runtimeCompatibilityVersion: _int(
          body,
          'runtime_compatibility_version',
        ),
        patchFormatVersion: _int(body, 'patch_format_version'),
        highWaterSequence: _int(body, 'high_water_sequence'),
        highWaterDigest: highWater is Map<String, Object?>
            ? _optionalString(highWater, 'digest')
            : null,
        platformId: _optionalString(body, 'platform_id'),
        installationId: _optionalString(body, 'installation_id'),
      ),
    );
    metrics.recordUpdateDecision(result.decision);
    await _json(request.response, 200, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _fetchArtifact(
    HttpRequest request,
    String artifactId,
    String requestId,
  ) async {
    final applicationId = request.uri.queryParameters['application_id'];
    final environmentId = request.uri.queryParameters['environment_id'];
    if (applicationId == null || environmentId == null) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Artifact fetch requires application_id and environment_id',
      );
    }
    final result = await service.fetchArtifact(
      token: _bearer(request),
      artifactId: artifactId,
      applicationId: applicationId,
      environmentId: environmentId,
      admissionId: _optionalArtifactHeader(
        request,
        artifactAdmissionIdHeader,
        maxLength: 256,
      ),
      downloadProof: _optionalArtifactHeader(
        request,
        artifactDownloadProofHeader,
        maxLength: 4096,
      ),
    );
    final responseBody = _artifactResponseSlice(request, result.bytes);
    await service.recordArtifactDelivery(
      payload: result,
      bytes: responseBody.bytes.length,
    );
    request.response
      ..statusCode = responseBody.statusCode
      ..headers.contentType = ContentType('application', 'octet-stream')
      ..headers.contentLength = responseBody.bytes.length
      ..headers.set('Accept-Ranges', 'bytes')
      ..headers.set('ETag', '"${result.record.sha256}"')
      ..headers.set('Digest', result.record.sha256);
    if (responseBody.contentRange != null) {
      request.response.headers.set('Content-Range', responseBody.contentRange!);
    }
    request.response.add(responseBody.bytes);
    await request.response.close();
  }

  _ArtifactResponseSlice _artifactResponseSlice(
    HttpRequest request,
    List<int> bytes,
  ) {
    final range = request.headers.value('range');
    if (range == null || range.trim().isEmpty) {
      return _ArtifactResponseSlice(bytes: bytes, statusCode: HttpStatus.ok);
    }
    final value = range.trim();
    if (!value.startsWith('bytes=') || value.substring(6).contains(',')) {
      throw const ControlPlaneException(
        'RANGE_NOT_SATISFIABLE',
        'Only one byte range is supported for artifact delivery',
        statusCode: 416,
      );
    }
    final expression = value.substring(6).trim();
    final separator = expression.indexOf('-');
    if (separator < 0) {
      throw const ControlPlaneException(
        'RANGE_NOT_SATISFIABLE',
        'Artifact byte range is malformed',
        statusCode: 416,
      );
    }
    final startText = expression.substring(0, separator).trim();
    final endText = expression.substring(separator + 1).trim();
    if (bytes.isEmpty) {
      throw const ControlPlaneException(
        'RANGE_NOT_SATISFIABLE',
        'Artifact byte range is outside the response',
        statusCode: 416,
      );
    }

    int start;
    int end;
    if (startText.isEmpty) {
      final suffixLength = int.tryParse(endText);
      if (suffixLength == null) {
        throw const ControlPlaneException(
          'RANGE_NOT_SATISFIABLE',
          'Artifact byte range is malformed',
          statusCode: 416,
        );
      }
      if (suffixLength <= 0) {
        throw const ControlPlaneException(
          'RANGE_NOT_SATISFIABLE',
          'Artifact byte range is outside the response',
          statusCode: 416,
        );
      }
      start = suffixLength >= bytes.length ? 0 : bytes.length - suffixLength;
      end = bytes.length - 1;
    } else {
      final parsedStart = int.tryParse(startText);
      final parsedEnd = endText.isEmpty ? null : int.tryParse(endText);
      if (parsedStart == null || (endText.isNotEmpty && parsedEnd == null)) {
        throw const ControlPlaneException(
          'RANGE_NOT_SATISFIABLE',
          'Artifact byte range is malformed',
          statusCode: 416,
        );
      }
      start = parsedStart;
      end = parsedEnd ?? bytes.length - 1;
      if (start >= bytes.length || end < start) {
        throw const ControlPlaneException(
          'RANGE_NOT_SATISFIABLE',
          'Artifact byte range is outside the response',
          statusCode: 416,
        );
      }
      if (end >= bytes.length) end = bytes.length - 1;
    }
    return _ArtifactResponseSlice(
      bytes: bytes.sublist(start, end + 1),
      statusCode: HttpStatus.partialContent,
      contentRange: 'bytes $start-$end/${bytes.length}',
    );
  }

  Future<void> _discovery(HttpRequest request, String requestId) async {
    final auth = service.humanAuth;
    final body = discovery.toJson(
      humanAuthConfigured: auth != null,
      deviceVerificationUri: auth?.config.deviceVerificationUri,
    );
    if (auth != null) body['issuer'] = auth.config.issuer;
    body['request_id'] = requestId;
    await _json(request.response, 200, body);
  }

  Future<void> _authAuthorize(HttpRequest request, String requestId) async {
    final auth = _humanAuth();
    late final HumanAuthorizationRequest authorizationRequest;
    if (request.method == 'GET') {
      final query = request.uri.queryParameters;
      const expected = <String>{
        'client_id',
        'redirect_uri',
        'response_type',
        'code_challenge',
        'code_challenge_method',
        'state',
      };
      if (!setEquals(query.keys.toSet(), expected)) {
        throw const ControlPlaneException(
          'INVALID_REQUEST',
          'Authorization request fields are unsupported',
        );
      }
      authorizationRequest = await auth.beginAuthorization(
        clientId: _queryString(query, 'client_id'),
        redirectUri: _queryString(query, 'redirect_uri'),
        responseType: _queryString(query, 'response_type'),
        codeChallenge: _queryString(query, 'code_challenge'),
        codeChallengeMethod: _queryString(query, 'code_challenge_method'),
        state: _queryString(query, 'state'),
      );
    } else {
      final body = await _authBody(request);
      if (body.keys.length == 1 &&
          (body.containsKey('request_id') ||
              body.containsKey('authorization_request_id'))) {
        authorizationRequest = await auth.authorizationRequest(
          requestId: _string(
            body,
            body.containsKey('authorization_request_id')
                ? 'authorization_request_id'
                : 'request_id',
          ),
        );
      } else {
        const expected = <String>{
          'client_id',
          'redirect_uri',
          'response_type',
          'code_challenge',
          'code_challenge_method',
          'state',
        };
        if (!setEquals(body.keys.toSet(), expected)) {
          throw const ControlPlaneException(
            'INVALID_REQUEST',
            'Authorization request fields are unsupported',
          );
        }
        authorizationRequest = await auth.beginAuthorization(
          clientId: _string(body, 'client_id'),
          redirectUri: _string(body, 'redirect_uri'),
          responseType: _string(body, 'response_type'),
          codeChallenge: _string(body, 'code_challenge'),
          codeChallengeMethod: _string(body, 'code_challenge_method'),
          state: _string(body, 'state'),
        );
      }
    }
    final authorizationHeader = request.headers.value('authorization');
    if (authorizationHeader == null) {
      await _json(request.response, 200, <String, Object?>{
        'status': 'authorization_required',
        ...authorizationRequest.toJson(),
        'approval_endpoint': _apiPath('auth/authorize'),
        'authorization_request_id': authorizationRequest.id,
        'request_id': requestId,
      });
      return;
    }
    _enforceCredentialTransport(request);
    final result = await auth.authorize(
      requestId: authorizationRequest.id,
      accessToken: _bearer(request),
    );
    if (_acceptsJson(request)) {
      await _json(request.response, 200, <String, Object?>{
        ...result.toJson(),
        'request_id': requestId,
      });
      return;
    }
    final location = _authorizationRedirect(result);
    request.response
      ..statusCode = HttpStatus.found
      ..headers.set('Location', location.toString())
      ..headers.set('Referrer-Policy', 'no-referrer');
    await request.response.close();
  }

  Future<void> _authToken(HttpRequest request, String requestId) async {
    _enforceCredentialTransport(request);
    final body = await _authBody(request);
    final grantType = _string(body, 'grant_type');
    if (grantType != humanAuthorizationCodeGrantType) {
      if (grantType == humanDeviceAuthorizationGrantType) {
        await _authDeviceTokenBody(body, request, requestId);
        return;
      }
      throw const ControlPlaneException(
        'UNSUPPORTED_GRANT_TYPE',
        'The requested auth grant is not supported',
      );
    }
    const expected = <String>{
      'grant_type',
      'client_id',
      'code',
      'redirect_uri',
      'code_verifier',
    };
    if (!setEquals(body.keys.toSet(), expected)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Authorization code exchange fields are unsupported',
      );
    }
    final result = await _humanAuth().exchangeAuthorizationCode(
      clientId: _string(body, 'client_id'),
      code: _string(body, 'code'),
      redirectUri: _string(body, 'redirect_uri'),
      codeVerifier: _string(body, 'code_verifier'),
    );
    await _json(request.response, 200, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _authDeviceCode(HttpRequest request, String requestId) async {
    _enforceCredentialTransport(request);
    final body = await _authBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'client_id'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Device authorization request fields are unsupported',
      );
    }
    final result = await _humanAuth().createDeviceAuthorization(
      clientId: _string(body, 'client_id'),
    );
    final responseBody = result.toJson();
    final verificationUri = result.verificationUri;
    final parsedVerification = Uri.tryParse(verificationUri);
    if (parsedVerification != null && !parsedVerification.isAbsolute) {
      responseBody['verification_uri'] = _apiPath(
        verificationUri.startsWith('/')
            ? verificationUri.substring(1)
            : verificationUri,
      );
    }
    await _json(request.response, 200, <String, Object?>{
      ...responseBody,
      'request_id': requestId,
    });
  }

  Future<void> _authDeviceToken(HttpRequest request, String requestId) async {
    _enforceCredentialTransport(request);
    final body = await _authBody(request);
    await _authDeviceTokenBody(body, request, requestId);
  }

  Future<void> _authDeviceTokenBody(
    Map<String, Object?> body,
    HttpRequest request,
    String requestId,
  ) async {
    const withoutGrant = <String>{'client_id', 'device_code'};
    const withGrant = <String>{'grant_type', 'client_id', 'device_code'};
    if (!setEquals(body.keys.toSet(), withoutGrant) &&
        !setEquals(body.keys.toSet(), withGrant)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Device token request fields are unsupported',
      );
    }
    if (body['grant_type'] != null &&
        body['grant_type'] != humanDeviceAuthorizationGrantType) {
      throw const ControlPlaneException(
        'UNSUPPORTED_GRANT_TYPE',
        'The requested auth grant is not supported',
      );
    }
    final result = await _humanAuth().pollDeviceAuthorization(
      clientId: _string(body, 'client_id'),
      deviceCode: _string(body, 'device_code'),
    );
    if (result.isApproved) {
      await _json(request.response, 200, <String, Object?>{
        ...result.loginResult!.toJson(),
        'request_id': requestId,
      });
      return;
    }
    final message = switch (result.status) {
      'authorization_pending' => 'Device authorization is still pending',
      'expired_token' => 'Device authorization code has expired',
      'invalid_grant' => 'Device authorization code has already been consumed',
      _ => 'Device authorization was denied',
    };
    await _json(request.response, 400, <String, Object?>{
      'error': result.status,
      'error_description': message,
      'request_id': requestId,
    });
  }

  Future<void> _authDeviceApprove(HttpRequest request, String requestId) async {
    _enforceCredentialTransport(request);
    final body = await _authBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'user_code'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Device approval request fields are unsupported',
      );
    }
    await _humanAuth().approveDeviceAuthorization(
      userCode: _string(body, 'user_code'),
      accessToken: _bearer(request),
    );
    await _json(request.response, 200, <String, Object?>{
      'status': 'approved',
      'request_id': requestId,
    });
  }

  Future<void> _authDeviceVerify(HttpRequest request, String requestId) async {
    _humanAuth();
    await _json(request.response, 200, <String, Object?>{
      'status': 'verification_required',
      'approval_endpoint': _apiPath('auth/device/approve'),
      'request_id': requestId,
    });
  }

  Future<void> _publicRegister(HttpRequest request, String requestId) async {
    final organizationId = discovery.publicRegistrationOrganizationId;
    final auth = service.humanAuth;
    if (organizationId == null || auth == null) {
      throw const ControlPlaneException(
        'PUBLIC_REGISTRATION_UNAVAILABLE',
        'Public registration is not configured',
        statusCode: 503,
      );
    }
    final body = await _publicJsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'email', 'password'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Public registration fields are unsupported',
        statusCode: 422,
      );
    }
    final result = await auth.registerClient(
      organizationId: organizationId,
      email: _string(body, 'email'),
      password: _string(body, 'password'),
    );
    await _json(request.response, 200, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _publicCloudRegister(
    HttpRequest request,
    String requestId,
  ) async {
    final body = await _publicJsonBody(request);
    const required = <String>{'email', 'password'};
    const optional = <String>{'organization_name'};
    if (!body.keys.toSet().containsAll(required) ||
        body.keys.any(
          (key) => !required.contains(key) && !optional.contains(key),
        )) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Cloud registration fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final result = await service.registerCloudCustomer(
      email: _string(body, 'email'),
      password: _string(body, 'password'),
      organizationName: _publicOptionalString(body, 'organization_name') ?? '',
    );
    await _json(request.response, 202, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _publicCloudVerify(HttpRequest request, String requestId) async {
    final body = await _publicJsonBody(request);
    const allowed = <String>{'token', 'organization_name'};
    if (!body.containsKey('token') ||
        body.keys.any((key) => !allowed.contains(key))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Cloud verification fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final result = await service.verifyCloudCustomer(
      token: _string(body, 'token'),
      organizationName: _publicOptionalString(body, 'organization_name'),
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _publicCloudVerificationResend(
    HttpRequest request,
    String requestId,
  ) async {
    final body = await _publicJsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'email'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Cloud verification fields are unsupported',
        statusCode: 422,
      );
    }
    final result = await _humanAuth().resendCustomerVerification(
      email: _string(body, 'email'),
    );
    await _json(request.response, 200, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _publicCloudRecovery(
    HttpRequest request,
    String requestId,
  ) async {
    final body = await _publicJsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'email'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Recovery fields are unsupported',
        statusCode: 422,
      );
    }
    final result = await _humanAuth().requestPasswordRecovery(
      email: _string(body, 'email'),
    );
    await _json(request.response, 200, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _publicCloudRecoveryComplete(
    HttpRequest request,
    String requestId,
  ) async {
    final body = await _publicJsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'token', 'password'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Recovery completion fields are unsupported',
        statusCode: 422,
      );
    }
    await _humanAuth().resetPassword(
      token: _string(body, 'token'),
      password: _string(body, 'password'),
    );
    await _json(request.response, 200, <String, Object?>{
      'status': 'password_reset',
      'request_id': requestId,
    });
  }

  Future<void> _publicAccountDeletionRequest(
    HttpRequest request,
    String requestId,
  ) async {
    final body = await _publicJsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'email'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Deletion request fields are unsupported',
        statusCode: 422,
      );
    }
    final result = await _humanAuth().requestAccountDeletion(
      email: _string(body, 'email'),
    );
    await _json(request.response, 202, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _publicAccountDeletionVerify(
    HttpRequest request,
    String requestId,
  ) async {
    final body = await _publicJsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'token'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Deletion verification fields are unsupported',
        statusCode: 422,
      );
    }
    final userId = await _humanAuth().consumeAccountDeletionToken(
      token: _string(body, 'token'),
    );
    final deletion = _deletion();
    final result = await deletion.verifyAccountDeletionToken(
      userId: userId,
      actorId: 'email:account-deletion',
      requestId: requestId,
    );
    await _json(request.response, 202, <String, Object?>{
      'status': result['status'],
      'request_id': requestId,
    });
  }

  Future<void> _readAccountDeletion(
    HttpRequest request,
    String requestId,
  ) async {
    final user = await _humanAuth().verifiedCustomerForAccessToken(
      accessToken: _bearer(request),
    );
    await _json(request.response, 200, <String, Object?>{
      ...await _deletion().accountStatus(userId: user.id),
      'request_id': requestId,
    });
  }

  Future<void> _requestAccountDeletion(
    HttpRequest request,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{
      'confirmation',
      'password',
    })) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Account deletion confirmation fields are unsupported',
        statusCode: 422,
      );
    }
    final user = await _confirmCustomerDeletion(request, body);
    final result = await _deletion().requestAccountDeletion(
      userId: user.id,
      actorId: user.id,
      requestId: requestId,
    );
    await _json(request.response, 202, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _cancelAccountDeletion(
    HttpRequest request,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{
      'confirmation',
      'password',
    })) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Account deletion cancellation fields are unsupported',
        statusCode: 422,
      );
    }
    final user = await _confirmCustomerDeletion(request, body);
    final result = await _deletion().cancelAccountDeletion(
      userId: user.id,
      actorId: user.id,
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _readOrganizationDeletion(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final user = await _humanAuth().verifiedCustomerForAccessToken(
      accessToken: _bearer(request),
    );
    await _json(request.response, 200, <String, Object?>{
      ...await _deletion().organizationStatus(
        userId: user.id,
        organizationId: path[2],
      ),
      'request_id': requestId,
    });
  }

  Future<void> _requestOrganizationDeletion(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{
      'confirmation',
      'password',
    })) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Organization deletion confirmation fields are unsupported',
        statusCode: 422,
      );
    }
    final user = await _confirmCustomerDeletion(request, body);
    final result = await _deletion().requestOrganizationDeletion(
      userId: user.id,
      organizationId: path[2],
      requestId: requestId,
    );
    await _json(request.response, 202, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _authorizeOrganizationDeletion(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{
      'confirmation',
      'password',
    })) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Organization deletion confirmation fields are unsupported',
        statusCode: 422,
      );
    }
    final user = await _confirmCustomerDeletion(request, body);
    await _deletion().authorizeOrganizationDeletion(
      userId: user.id,
      organizationId: path[2],
    );
    await _json(request.response, 200, <String, Object?>{
      'status': 'authorized',
      'organization_id': path[2],
      'request_id': requestId,
    });
  }

  Future<void> _cancelOrganizationDeletion(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{
      'confirmation',
      'password',
    })) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Organization deletion cancellation fields are unsupported',
        statusCode: 422,
      );
    }
    final user = await _confirmCustomerDeletion(request, body);
    final result = await _deletion().cancelOrganizationDeletion(
      userId: user.id,
      organizationId: path[2],
      actorId: user.id,
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<HumanUserRecord> _confirmCustomerDeletion(
    HttpRequest request,
    Map<String, Object?> body,
  ) async {
    if (body['confirmation'] != 'DELETE') {
      throw const ControlPlaneException(
        'CONFIRMATION_REQUIRED',
        'Type DELETE to confirm this action',
        statusCode: 422,
      );
    }
    return _humanAuth().confirmCustomerPassword(
      accessToken: _bearer(request),
      password: _string(body, 'password'),
    );
  }

  Future<void> _createCustomerOrganization(
    HttpRequest request,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'name'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Organization creation fields are unsupported',
        statusCode: 422,
      );
    }
    final result = await service.createCustomerOrganization(
      token: _bearer(request),
      organizationName: _string(body, 'name'),
      idempotencyKey: _idempotency(request),
      requestId: requestId,
    );
    await _json(request.response, 201, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _publicWaitlist(HttpRequest request, String requestId) async {
    final body = await _publicSubmissionBody(request);
    await _publicOnboarding.submitWaitlist(
      email: _string(body, 'email'),
      name: _publicOptionalString(body, 'name'),
      source: _publicOptionalString(body, 'source'),
    );
    await _json(request.response, 200, <String, Object?>{
      'status': 'accepted',
      'request_id': requestId,
    });
  }

  Future<void> _publicNewsletter(HttpRequest request, String requestId) async {
    final body = await _publicSubmissionBody(request);
    await _publicOnboarding.submitNewsletter(
      email: _string(body, 'email'),
      name: _publicOptionalString(body, 'name'),
      source: _publicOptionalString(body, 'source'),
    );
    await _json(request.response, 200, <String, Object?>{
      'status': 'accepted',
      'request_id': requestId,
    });
  }

  Future<void> _publicEnterpriseInquiry(
    HttpRequest request,
    String requestId,
  ) async {
    final body = await _publicJsonBody(request);
    const required = <String>{'email', 'message'};
    const optional = <String>{'name', 'organization', 'source'};
    if (!body.keys.toSet().containsAll(required) ||
        body.keys.any(
          (key) => !required.contains(key) && !optional.contains(key),
        )) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise inquiry fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final inquiry = await _publicOnboarding.submitEnterpriseInquiry(
      email: _string(body, 'email'),
      message: _string(body, 'message'),
      idempotencyKey: _idempotency(request),
      name: _publicOptionalString(body, 'name'),
      organization: _publicOptionalString(body, 'organization'),
      source: _publicOptionalString(body, 'source'),
    );
    await _json(request.response, 202, <String, Object?>{
      'status': inquiry['status'],
      'destination': inquiry['destination'],
      'request_id': requestId,
    });
  }

  Future<Map<String, Object?>> _publicSubmissionBody(
    HttpRequest request,
  ) async {
    final body = await _publicJsonBody(request);
    const allowed = <String>{'email', 'name', 'source'};
    if (!body.containsKey('email') ||
        body.keys.any((key) => !allowed.contains(key))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Public submission fields are unsupported or incomplete',
        statusCode: 422,
      );
    }
    return body;
  }

  Future<Map<String, Object?>> _publicJsonBody(HttpRequest request) async {
    if (request.headers.contentType?.mimeType != 'application/json') {
      throw const ControlPlaneException(
        'UNSUPPORTED_MEDIA_TYPE',
        'Public onboarding requests must use application/json',
        statusCode: HttpStatus.unsupportedMediaType,
      );
    }
    return _jsonBody(
      request,
      maxBytes: limits.maxPublicOnboardingBodyBytes,
      tooLargeCode: 'REQUEST_TOO_LARGE',
    );
  }

  String? _publicOptionalString(Map<String, Object?> body, String key) {
    if (!body.containsKey(key)) return null;
    final value = body[key];
    if (value == null) return null;
    if (value is! String) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Public submission fields are invalid',
        statusCode: 422,
      );
    }
    return value;
  }

  void _rejectPublicQuery(HttpRequest request) {
    if (request.uri.queryParameters.isNotEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Public onboarding query parameters are unsupported',
        statusCode: 422,
      );
    }
  }

  Future<Map<String, Object?>> _authBody(HttpRequest request) async {
    final bytes = await _bytesBody(request, maxBytes: limits.maxJsonBodyBytes);
    final source = utf8.decode(bytes, allowMalformed: false);
    final contentType = request.headers.contentType?.mimeType;
    if (contentType == 'application/x-www-form-urlencoded') {
      final fields = Uri.splitQueryString(source);
      return <String, Object?>{
        for (final entry in fields.entries) entry.key: entry.value,
      };
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Authentication body must be a JSON object or form',
      );
    }
    return <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  Uri _authorizationRedirect(HumanAuthorizationCodeResult result) {
    final raw = result.request.redirectUri;
    final separator = raw.contains('?')
        ? (raw.endsWith('?') || raw.endsWith('&') ? '' : '&')
        : '?';
    return Uri.parse(
      '$raw${separator}code=${Uri.encodeQueryComponent(result.code)}'
      '&state=${Uri.encodeQueryComponent(result.request.state)}',
    );
  }

  String _queryString(Map<String, String> query, String key) {
    final value = query[key];
    if (value == null || value.isEmpty) {
      throw FormatException('Missing or invalid $key');
    }
    return value;
  }

  int _queryInt(Map<String, String> query, String key, int fallback) {
    final value = query[key];
    if (value == null) return fallback;
    final parsed = int.tryParse(value);
    if (parsed == null) throw FormatException('Invalid $key');
    return parsed;
  }

  String _apiPath(String suffix) =>
      '${discovery.apiBasePath.endsWith('/') ? discovery.apiBasePath : '${discovery.apiBasePath}/'}$suffix';

  String get _discoveryPath => _apiPath('.well-known/hyfens');

  String? get _deviceVerificationPath {
    final configured = service.humanAuth?.config.deviceVerificationUri;
    if (configured == null) return null;
    final parsed = Uri.tryParse(configured);
    if (parsed == null || parsed.isAbsolute) return null;
    return configured;
  }

  String? _apiRelativePath(String path) {
    if (discovery.apiBasePath == '/') return path;
    final basePath = discovery.apiBasePath.endsWith('/')
        ? discovery.apiBasePath
        : '${discovery.apiBasePath}/';
    final base = basePath.substring(0, basePath.length - 1);
    if (path == base || path.startsWith(basePath)) {
      return path.substring(base.length);
    }
    // Keep the existing root paths available for compatibility with current
    // local callers while publishing the configured base-path routes.
    if (path.startsWith('/auth/') || path.startsWith('/v1/')) return path;
    return null;
  }

  void _rejectAuthSecretsInQuery(HttpRequest request) {
    const forbidden = <String>{
      'access_token',
      'code',
      'code_verifier',
      'device_code',
      'password',
      'refresh_token',
      'session_token',
      'client_secret',
      'token',
      'user_code',
    };
    if (request.uri.queryParameters.keys.any(
      (key) => forbidden.contains(key.toLowerCase()),
    )) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Credential-bearing auth parameters must be sent in the request body',
      );
    }
  }

  void _enforceCredentialTransport(HttpRequest request) {
    final remote = request.connectionInfo?.remoteAddress.address;
    final loopback =
        remote == 'localhost' ||
        remote == '127.0.0.1' ||
        remote == '::1' ||
        remote == '::ffff:127.0.0.1';
    final proxyTerminatedTls =
        ControlPlaneIngressTrustPolicy.isTrustedForwardedTls(
          remoteAddress: remote,
          forwardedProto: request.headers.value('x-forwarded-proto'),
        );
    if (!loopback &&
        !proxyTerminatedTls &&
        request.uri.scheme != 'https' &&
        !allowInsecureAuth) {
      throw const ControlPlaneException(
        'INSECURE_TRANSPORT',
        'Credential-bearing authentication requires HTTPS',
        statusCode: 400,
      );
    }
  }

  void _applyCors(HttpRequest request) {
    final origin = request.headers.value('origin');
    if (origin == null) return;
    if (!discovery.webOrigins.contains(origin)) {
      throw const ControlPlaneException(
        'ORIGIN_NOT_ALLOWED',
        'The browser origin is not allowed for this control plane',
        statusCode: HttpStatus.forbidden,
      );
    }
    request.response.headers
      ..set('Access-Control-Allow-Origin', origin)
      ..set('Access-Control-Allow-Methods', 'GET, POST, PATCH, PUT, OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        'Authorization, Content-Type, Idempotency-Key, X-Request-Id',
      )
      ..set('Access-Control-Expose-Headers', 'X-Request-Id')
      ..set('Vary', 'Origin');
  }

  bool _acceptsJson(HttpRequest request) {
    final accept = request.headers.value('accept');
    if (accept == null) return false;
    return accept.split(',').any((value) {
      final mediaType = value.trim().split(';').first.trim().toLowerCase();
      return mediaType == 'application/json' || mediaType == '*/*';
    });
  }

  Future<void> _authLogin(HttpRequest request, String requestId) async {
    _enforceCredentialTransport(request);
    final body = await _jsonBody(request);
    if (!body.keys.toSet().every(
          const <String>{'email', 'password', 'audience'}.contains,
        ) ||
        !body.keys.toSet().containsAll(const <String>{'email', 'password'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Authentication request fields are unsupported',
      );
    }
    final result = await _humanAuth().login(
      email: _string(body, 'email'),
      password: _string(body, 'password'),
      audience:
          _optionalString(body, 'audience') ?? customerAuthorizationAudience,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _authRefresh(HttpRequest request, String requestId) async {
    _enforceCredentialTransport(request);
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'session_token'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Authentication request fields are unsupported',
      );
    }
    final result = await _humanAuth().refresh(
      sessionToken: _string(body, 'session_token'),
    );
    await _json(request.response, 200, <String, Object?>{
      ...result.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _authLogout(HttpRequest request, String requestId) async {
    _enforceCredentialTransport(request);
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'session_token'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Authentication request fields are unsupported',
      );
    }
    await _humanAuth().logout(sessionToken: _string(body, 'session_token'));
    await _json(request.response, 200, <String, Object?>{
      'status': 'signed_out',
      'request_id': requestId,
    });
  }

  Future<void> _authMe(HttpRequest request, String requestId) async {
    _enforceCredentialTransport(request);
    final identity = await _humanAuth().me(accessToken: _bearer(request));
    await _json(request.response, 200, <String, Object?>{
      ...identity.toJson(),
      'request_id': requestId,
    });
  }

  HumanAuthService _humanAuth() {
    final auth = service.humanAuth;
    if (auth == null) {
      throw const ControlPlaneException(
        'AUTH_UNAVAILABLE',
        'Human authentication is not configured',
        statusCode: 503,
      );
    }
    return auth;
  }

  AccountDeletionService _deletion() {
    final deletion = service.deletion;
    if (deletion == null) {
      throw const ControlPlaneException(
        'DELETION_UNAVAILABLE',
        'Account deletion is not configured for this deployment',
        statusCode: 503,
      );
    }
    return deletion;
  }

  Future<Map<String, Object?>> _jsonBody(
    HttpRequest request, {
    int? maxBytes,
    String tooLargeCode = 'ARTIFACT_TOO_LARGE',
  }) async {
    final bytes = await _bytesBody(
      request,
      maxBytes: maxBytes ?? limits.maxJsonBodyBytes,
      tooLargeCode: tooLargeCode,
    );
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map<String, Object?>) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'JSON body must be an object',
      );
    }
    return decoded;
  }

  Future<List<int>> _bytesBody(
    HttpRequest request, {
    required int maxBytes,
    String tooLargeCode = 'ARTIFACT_TOO_LARGE',
  }) async {
    final contentLength = request.contentLength;
    if (contentLength > maxBytes) {
      throw ControlPlaneException(
        tooLargeCode,
        'Request body exceeds the supported limit',
        statusCode: 413,
      );
    }
    final result = <int>[];
    await for (final chunk in request) {
      result.addAll(chunk);
      if (result.length > maxBytes) {
        throw ControlPlaneException(
          tooLargeCode,
          'Request body exceeds the supported limit',
          statusCode: 413,
        );
      }
    }
    return result;
  }

  String _bearer(HttpRequest request) {
    // Only the direct Authorization header is trusted. Host, Forwarded, and
    // X-Forwarded-* headers are intentionally ignored for authentication.
    final value = request.headers.value('authorization');
    if (value == null || !value.startsWith('Bearer ')) {
      throw const ControlPlaneException(
        'UNAUTHORIZED',
        'Bearer credential is required',
        statusCode: 401,
      );
    }
    final token = value.substring(7);
    if (token.isEmpty || token.contains(RegExp(r'[\r\n]'))) {
      throw const ControlPlaneException(
        'UNAUTHORIZED',
        'Bearer credential is invalid',
        statusCode: 401,
      );
    }
    return token;
  }

  String? _optionalArtifactHeader(
    HttpRequest request,
    String name, {
    required int maxLength,
  }) {
    final values = request.headers[name] ?? const <String>[];
    if (values.isEmpty) return null;
    if (values.length != 1) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Artifact admission headers are invalid',
      );
    }
    final value = values.single;
    if (value.isEmpty ||
        value.length > maxLength ||
        value.contains(RegExp(r'[\u0000\r\n]'))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Artifact admission headers are invalid',
      );
    }
    return value;
  }

  String? _optionalBearer(HttpRequest request) {
    final value = request.headers.value('authorization');
    if (value == null) return null;
    if (!value.startsWith('Bearer ')) {
      throw const ControlPlaneException(
        'UNAUTHORIZED',
        'Bearer credential is invalid',
        statusCode: 401,
      );
    }
    final token = value.substring(7);
    if (token.isEmpty || token.contains(RegExp(r'[\r\n]'))) {
      throw const ControlPlaneException(
        'UNAUTHORIZED',
        'Bearer credential is invalid',
        statusCode: 401,
      );
    }
    return token;
  }

  String _idempotency(HttpRequest request) {
    final value = request.headers.value('idempotency-key');
    if (value == null) {
      throw const ControlPlaneException(
        'IDEMPOTENCY_REQUIRED',
        'Idempotency-Key is required',
      );
    }
    return value;
  }

  _TrustedBundleKey _trustedBundleKey(HttpRequest request) {
    final keyId = request.headers.value(ReleaseBundle.trustedKeyIdHeader);
    final encoded = request.headers.value(ReleaseBundle.trustedPublicKeyHeader);
    if (keyId == null || keyId.isEmpty || encoded == null || encoded.isEmpty) {
      throw const ControlPlaneException(
        'BUNDLE_TRUST_KEY_REQUIRED',
        'Trusted bundle key ID and public key headers are required',
      );
    }
    late final List<int> publicKey;
    try {
      publicKey = base64Decode(encoded);
    } on FormatException {
      throw const ControlPlaneException(
        'BUNDLE_TRUST_KEY_INVALID',
        'Trusted bundle public key is not valid base64',
      );
    }
    if (publicKey.length != 32 || base64Encode(publicKey) != encoded) {
      throw const ControlPlaneException(
        'BUNDLE_TRUST_KEY_INVALID',
        'Trusted bundle public key must be canonical Ed25519 bytes',
      );
    }
    return _TrustedBundleKey(keyId: keyId, publicKey: publicKey);
  }

  int? _ifMatchVersion(HttpRequest request) {
    final value = request.headers.value('if-match');
    if (value == null) return null;
    final match = RegExp(r'^"?environment-v([0-9]+)"?$').firstMatch(value);
    if (match == null)
      throw const ControlPlaneException(
        'INVALID_PRECONDITION',
        'If-Match must contain an environment version',
      );
    return int.parse(match.group(1)!);
  }

  String _requestId(HttpRequest request) {
    // A caller-supplied request ID is correlation-only. It never participates
    // in authentication, tenant selection, authorization, or idempotency.
    final supplied = request.headers.value('x-request-id');
    if (supplied != null &&
        RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(supplied))
      return supplied;
    return 'req_${DateTime.now().microsecondsSinceEpoch}';
  }

  void _enforceRateLimit(HttpRequest request) {
    if (request.method == 'GET' && request.uri.path == '/livez') return;
    final now = DateTime.now().toUtc();
    // Use the socket peer, not X-Forwarded-For/Forwarded, for this local
    // process-local limit. A public edge should rate-limit before proxying.
    final key = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    final window = _requestWindows.putIfAbsent(key, () => <DateTime>[])
      ..removeWhere(
        (time) => now.difference(time) >= const Duration(minutes: 1),
      );
    if (window.length >= limits.maxRequestsPerMinute) {
      throw const ControlPlaneException(
        'RATE_LIMITED',
        'Request rate limit exceeded',
        statusCode: 429,
      );
    }
    window.add(now);
    if (_requestWindows.length > 1024) {
      _requestWindows.removeWhere((_, values) => values.isEmpty);
    }
  }

  void _enforceAuthRateLimit(HttpRequest request) {
    final now = DateTime.now().toUtc();
    final key = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    final window = _authRequestWindows.putIfAbsent(key, () => <DateTime>[])
      ..removeWhere(
        (time) => now.difference(time) >= const Duration(minutes: 1),
      );
    if (window.length >= limits.maxAuthAttemptsPerMinute) {
      throw const ControlPlaneException(
        'RATE_LIMITED',
        'Authentication rate limit exceeded',
        statusCode: 429,
      );
    }
    window.add(now);
    if (_authRequestWindows.length > 1024) {
      _authRequestWindows.removeWhere((_, values) => values.isEmpty);
    }
  }

  ObservationEvent _observationEvent(Map<String, Object?> body) {
    const expected = <String>{
      'schema_version',
      'event_id',
      'client_timestamp',
      'organization_id',
      'application_id',
      'environment_id',
      'platform',
      'release_id',
      'patch_id',
      'sequence',
      'rollout_id',
      'rollout_revision',
      'installation_bucket',
      'event_type',
      'runtime_version',
      'patch_format_version',
      'diagnostic_code',
      'safe_metadata',
    };
    if (!setEquals(body.keys.toSet(), expected)) {
      throw const ControlPlaneException(
        'EVENT_SCHEMA_UNSUPPORTED',
        'Observation event schema is unsupported',
        statusCode: 422,
      );
    }
    final metadata = body['safe_metadata'];
    if (metadata is! Map) {
      throw const ControlPlaneException(
        'EVENT_SCHEMA_UNSUPPORTED',
        'Observation safe metadata is invalid',
        statusCode: 422,
      );
    }
    try {
      return ObservationEvent(
        schemaVersion: _int(body, 'schema_version'),
        eventId: _string(body, 'event_id'),
        clientTimestamp: DateTime.parse(_string(body, 'client_timestamp'))
            .toUtc(),
        organizationId: _string(body, 'organization_id'),
        applicationId: _string(body, 'application_id'),
        environmentId: _string(body, 'environment_id'),
        platform: _string(body, 'platform'),
        releaseId: _string(body, 'release_id'),
        patchId: _nullableString(body, 'patch_id'),
        sequence: _nullableInt(body, 'sequence'),
        rolloutId: _nullableString(body, 'rollout_id'),
        rolloutRevision: _nullableInt(body, 'rollout_revision'),
        installationBucket: _string(body, 'installation_bucket'),
        eventType: parseObservationEventType(body['event_type']),
        runtimeVersion: _string(body, 'runtime_version'),
        patchFormatVersion: _int(body, 'patch_format_version'),
        diagnosticCode: _nullableString(body, 'diagnostic_code'),
        safeMetadata: Map<String, Object?>.from(
          metadata.map<String, Object?>(
            (key, value) => MapEntry('$key', value),
          ),
        ),
      );
    } on FormatException {
      throw const ControlPlaneException(
        'EVENT_SCHEMA_UNSUPPORTED',
        'Observation event schema is unsupported',
        statusCode: 422,
      );
    }
  }

  void _logRequestError(
    HttpRequest request,
    String requestId,
    String code,
    int durationMicros,
  ) {
    // Structured, redacted operator log. Do not include headers, query values,
    // bodies, credentials, or exception text in this process log.
    stderr.writeln(
      canonicalJson(<String, Object?>{
        'event': 'control_plane_request_error',
        'request_id': requestId,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'level': 'ERROR',
        'operation': ControlPlaneMetrics._operation(request),
        'method': request.method,
        'path': _redactedLogPath(request.uri.path),
        'code': code,
        'durationMicros': durationMicros,
      }),
    );
  }

  static String _redactedLogPath(String path) {
    final segments = Uri.parse(path).pathSegments;
    if (segments.length == 3 &&
        segments[0] == 'v1' &&
        (segments[1] == 'organization-invitations' ||
            segments[1] == 'platform-staff-invitations')) {
      return '/v1/${segments[1]}/:token';
    }
    return path;
  }

  String _string(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! String || value.isEmpty)
      throw FormatException('Missing or invalid $key');
    return value;
  }

  String? _nullableString(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value == null) return null;
    if (value is! String || value.isEmpty) {
      throw FormatException('Invalid $key');
    }
    return value;
  }

  int _int(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! int) throw FormatException('Missing or invalid $key');
    return value;
  }

  Map<String, Object?> _customerRefundResponse(Map<String, Object?> value) {
    final payment = value['payment'];
    final decision = value['decision'];
    final providerRefund = value['providerRefund'];
    return <String, Object?>{
      'id': value['id'],
      'paymentId': value['paymentId'],
      'reasonCategory': value['reasonCategory'],
      'explanation': value['explanation'],
      'requestedAmountMinor': value['requestedAmountMinor'],
      'approvedAmountMinor': value['approvedAmountMinor'],
      'currency': value['currency'],
      'status': value['status'],
      'createdAt': value['createdAt'],
      'updatedAt': value['updatedAt'],
      if (payment is Map)
        'payment': <String, Object?>{
          'id': payment['id'],
          'amountMinor': payment['amountMinor'],
          'currency': payment['currency'],
          'status': payment['status'],
          'capturedAt': payment['capturedAt'],
        },
      if (decision is Map)
        'decision': <String, Object?>{
          'status': decision['status'],
          'approvedAmountMinor': decision['approvedAmountMinor'],
          'currency': decision['currency'],
          'createdAt': decision['createdAt'],
        },
      if (providerRefund is Map)
        'providerRefund': <String, Object?>{
          'status': providerRefund['status'],
          'amountMinor': providerRefund['amountMinor'],
          'currency': providerRefund['currency'],
          'createdAt': providerRefund['createdAt'],
          'updatedAt': providerRefund['updatedAt'],
        },
    };
  }

  int? _nullableInt(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value == null) return null;
    if (value is! int) throw FormatException('Invalid $key');
    return value;
  }

  Map<String, String> _stringMap(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! Map<String, Object?> ||
        value.values.any((item) => item is! String)) {
      throw FormatException('Missing or invalid $key');
    }
    return value.map((name, item) => MapEntry(name, item! as String));
  }

  Set<String> _stringSet(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! List<Object?> || value.any((item) => item is! String)) {
      throw FormatException('Missing or invalid $key');
    }
    return value.cast<String>().toSet();
  }

  List<String> _stringList(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! List<Object?> || value.any((item) => item is! String)) {
      throw FormatException('Missing or invalid $key');
    }
    return value.cast<String>();
  }

  DateTime? _optionalDateTime(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('Invalid $key');
    try {
      return DateTime.parse(value).toUtc();
    } on FormatException {
      throw FormatException('Invalid $key');
    }
  }

  String? _optionalString(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value == null) return null;
    if (value is! String || value.isEmpty) {
      throw FormatException('Invalid $key');
    }
    return value;
  }

  EnterpriseQuoteTerms _enterpriseQuoteTerms(Map<String, Object?> body) {
    const required = <String>{
      'currency',
      'recurring_amount_minor',
      'interval',
      'valid_until',
      'entitlement_limits',
    };
    const allowed = <String>{
      'currency',
      'recurring_amount_minor',
      'interval',
      'valid_until',
      'term_months',
      'total_count',
      'upfront_amount_minor',
      'contact_name',
      'contact_email',
      'support_level',
      'customer_notes',
      'internal_notes',
      'entitlement_limits',
    };
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(required)) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise quote terms are unsupported or incomplete',
        statusCode: 422,
      );
    }
    final rawLimits = body['entitlement_limits'];
    if (rawLimits is! Map) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise entitlement limits must be an object',
        statusCode: 422,
      );
    }
    final limits = <String, CloudLimit>{};
    for (final entry in rawLimits.entries) {
      if (entry.key is! String ||
          !const <String>{
            cloudApplicationsLimitKey,
            cloudEnvironmentsPerApplicationLimitKey,
            cloudMembersLimitKey,
          }.contains(entry.key)) {
        throw const ControlPlaneException(
          'INVALID_REQUEST',
          'Enterprise entitlement key is unsupported',
          statusCode: 422,
        );
      }
      try {
        limits[entry.key as String] = CloudLimit.fromJson(entry.value);
      } on FormatException {
        throw const ControlPlaneException(
          'INVALID_REQUEST',
          'Enterprise entitlement limit is invalid',
          statusCode: 422,
        );
      }
    }
    if (limits.isEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'At least one Enterprise entitlement limit is required',
        statusCode: 422,
      );
    }
    final validUntil = _optionalDateTime(body, 'valid_until');
    if (validUntil == null) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Enterprise quote validity is required',
        statusCode: 422,
      );
    }
    return EnterpriseQuoteTerms(
      currency: _string(body, 'currency'),
      recurringAmountMinor: _int(body, 'recurring_amount_minor'),
      interval: _string(body, 'interval'),
      validUntil: validUntil,
      entitlements: EnterpriseEntitlementSnapshot(limits),
      termMonths: _nullableInt(body, 'term_months'),
      totalCount: _nullableInt(body, 'total_count'),
      upfrontAmountMinor: _nullableInt(body, 'upfront_amount_minor'),
      contactName: _optionalString(body, 'contact_name'),
      contactEmail: _optionalString(body, 'contact_email'),
      supportLevel: _optionalString(body, 'support_level'),
      customerNotes: _optionalString(body, 'customer_notes'),
      internalNotes: _optionalString(body, 'internal_notes'),
    );
  }

  bool _matches(List<String> actual, List<String> pattern) {
    if (actual.length != pattern.length) return false;
    for (var index = 0; index < pattern.length; index++) {
      if (pattern[index] != '*' && actual[index] != pattern[index])
        return false;
    }
    return true;
  }

  void _requirePathMatch(String actual, String expected, String field) {
    if (actual != expected)
      throw FormatException('Path $field does not match request body');
  }

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> body, {
    String? overrideMessage,
    String? requestId,
  }) async {
    final value = overrideMessage == null
        ? body
        : <String, Object?>{
            ...body,
            'error': <String, Object?>{
              ...(body['error'] as Map<String, Object?>? ??
                  const <String, Object?>{}),
              'message': overrideMessage,
            },
            'request_id': requestId ?? body['request_id'] ?? '',
          };
    final bytes = utf8.encode(canonicalJson(value));
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.contentLength = bytes.length;
    response.add(bytes);
    await response.close();
  }
}
