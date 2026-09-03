import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'human_auth.dart';
import 'observation.dart';
import 'operator_overview.dart';
import 'p3e_evaluation.dart';
import 'platform_commercial.dart';
import 'platform_console.dart';
import 'platform_metrics.dart';
import 'public_onboarding.dart';
import 'reconciliation_domain.dart';
import 'reconciliation_observability.dart';
import 'reconciliation_periodic.dart';
import 'release_bundle.dart';
import 'rollout.dart';
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

/// The trust boundary for the local HTTP adapter.
///
/// Forwarded headers describe a proxy's view of a request; they are not an
/// authentication signal. The adapter binds to loopback by default, and an
/// explicitly configured reverse proxy must terminate TLS and enforce its own
/// public-edge policy before forwarding to this process.
final class ControlPlaneIngressTrustPolicy {
  const ControlPlaneIngressTrustPolicy._();

  static const bool forwardedHeadersAffectAuthorization = false;
  static const bool forwardedHeadersAffectRateLimit = false;
  static const bool requestIdAffectsAuthorization = false;
  static const bool hostAffectsAuthorization = false;
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
          segments.length >= 3 &&
                  const <String>{
                    'audit',
                    'commercial',
                    'entitlements',
                    'metrics',
                    'organizations',
                    'staff',
                    'support',
                    'users',
                  }.contains(segments[2])
              ? 'v1/platform/${segments[2]}'
              : 'v1/platform/other',
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
  }) : limits = limits,
       discovery =
           discovery ??
           ControlPlaneDiscoveryConfig.fromEnvironment(Platform.environment),
       _operatorOverview = OperatorOverviewProjection(service),
       _publicOnboarding = PublicOnboardingService(store: service.store),
       _platformConsole = PlatformConsoleProjection(
         service.store,
         platformMfaRequired:
             service.humanAuth?.config.platformMfaRequired ?? false,
         platformMembershipPredicate:
             service.humanAuth?.isRecognizedPlatformMembership,
       ),
       _platformCommercial = PlatformCommercialProjection(service.store),
       _platformMetrics = PlatformMetricsProjection(store: service.store),
       _readyCheck = readyCheck ?? service.checkReadiness;

  final ControlPlaneService service;
  final ControlPlaneHttpLimits limits;
  final ControlPlaneDiscoveryConfig discovery;
  final int auditRetentionDays;
  final bool allowInsecureAuth;
  final ReconciliationObservability? reconciliationObservability;
  final ReconciliationPeriodicRunner? periodicRunner;
  final OperatorOverviewProjection _operatorOverview;
  final PublicOnboardingService _publicOnboarding;
  final PlatformConsoleProjection _platformConsole;
  final PlatformCommercialProjection _platformCommercial;
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
          _matches(path, const ['v1', 'platform', 'commercial'])) {
        await _readPlatformCommercial(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'commercial', 'history'])) {
        await _readPlatformCommercialHistory(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'staff'])) {
        await _readPlatformStaff(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'staff', 'invitations'])) {
        await _readPlatformStaffInvitations(request, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'platform', 'staff', 'invitations'])) {
        await _invitePlatformStaff(request, requestId);
        return;
      }
      if (request.method == 'PATCH' &&
          _matches(path, const ['v1', 'platform', 'staff', '*'])) {
        await _updatePlatformStaff(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'platform',
            'staff',
            '*',
            'sessions',
            'revoke',
          ])) {
        await _revokePlatformStaffSessions(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'platform',
            'staff',
            'invitations',
            '*',
            'revoke',
          ])) {
        await _revokePlatformStaffInvitation(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'support', 'cases'])) {
        await _readPlatformSupportCases(request, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform', 'support', 'cases', '*'])) {
        await _readPlatformSupportCase(request, path, requestId);
        return;
      }
      if (request.method == 'PATCH' &&
          _matches(path, const ['v1', 'platform', 'support', 'cases', '*'])) {
        await _updatePlatformSupportCase(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'platform',
            'support',
            'cases',
            '*',
            'messages',
          ])) {
        await _replyPlatformSupportCase(request, path, requestId);
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
      if (request.method == 'GET' &&
          apiPath == (_deviceVerificationPath ?? '/auth/device/verify')) {
        await _authDeviceVerify(request, requestId);
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
      if (request.method == 'PATCH' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'applications',
            '*',
          ])) {
        await _updateApplication(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'applications',
            '*',
            'archive',
          ])) {
        await _archiveApplication(request, path, requestId);
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
      if (request.method == 'PATCH' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'environments',
            '*',
          ])) {
        await _updateEnvironment(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'environments',
            '*',
            'archive',
          ])) {
        await _archiveEnvironment(request, path, requestId);
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
      if (request.method == 'PATCH' &&
          _matches(path, const ['v1', 'organizations', '*', 'members', '*'])) {
        await _updateOrganizationMember(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'members',
            '*',
            'remove',
          ])) {
        await _removeOrganizationMember(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'ownership-transfer',
          ])) {
        await _transferOrganizationOwnership(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'organizations', '*', 'invitations'])) {
        await _readOrganizationInvitations(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'organizations', '*', 'invitations'])) {
        await _inviteOrganizationMember(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'invitations',
            '*',
            'revoke',
          ])) {
        await _revokeOrganizationInvitation(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'organization-invitations', '*'])) {
        await _previewOrganizationInvitation(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'organization-invitations', '*'])) {
        await _acceptOrganizationInvitation(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const ['v1', 'platform-staff-invitations', '*'])) {
        await _previewPlatformStaffInvitation(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const ['v1', 'platform-staff-invitations', '*'])) {
        await _acceptPlatformStaffInvitation(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'support',
            'cases',
          ])) {
        await _readSupportCases(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'support',
            'cases',
          ])) {
        await _createSupportCase(request, path, requestId);
        return;
      }
      if (request.method == 'GET' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'support',
            'cases',
            '*',
          ])) {
        await _readSupportCase(request, path, requestId);
        return;
      }
      if (request.method == 'POST' &&
          _matches(path, const [
            'v1',
            'organizations',
            '*',
            'support',
            'cases',
            '*',
            'messages',
          ])) {
        await _replySupportCase(request, path, requestId);
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
        'Content kind must be blog or news',
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

  Future<void> _updateApplication(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'name'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Application updates support only name',
        statusCode: 422,
      );
    }
    final application = await service.updateApplication(
      token: _bearer(request),
      organizationId: path[2],
      applicationId: path[4],
      name: _string(body, 'name'),
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...application.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _archiveApplication(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final application = await service.archiveApplication(
      token: _bearer(request),
      organizationId: path[2],
      applicationId: path[4],
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
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

  Future<void> _updateEnvironment(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'name'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Environment updates support only name',
        statusCode: 422,
      );
    }
    final environment = await service.updateEnvironment(
      token: _bearer(request),
      organizationId: path[2],
      environmentId: path[4],
      name: _string(body, 'name'),
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...environment.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _archiveEnvironment(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final environment = await service.archiveEnvironment(
      token: _bearer(request),
      organizationId: path[2],
      environmentId: path[4],
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
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

  Future<void> _readPlatformCommercial(
    HttpRequest request,
    String requestId,
  ) async {
    final query = request.uri.queryParameters;
    if (query.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform commercial metrics supports only the profile query parameter',
        statusCode: 422,
      );
    }
    await _humanAuth().authorizePlatformCapability(
      accessToken: _bearer(request),
      capability: platformCommercialReadCapability,
      profileName: query['profile'],
    );
    final projection = await _platformCommercial.read();
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformCommercialHistory(
    HttpRequest request,
    String requestId,
  ) async {
    final query = request.uri.queryParameters;
    const allowed = <String>{'profile', 'limit', 'offset'};
    if (query.keys.any((key) => !allowed.contains(key))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Commercial history supports profile, limit, and offset',
        statusCode: 422,
      );
    }
    await _humanAuth().authorizePlatformCapability(
      accessToken: _bearer(request),
      capability: platformCommercialReadCapability,
      profileName: query['profile'],
    );
    final projection = await _platformCommercial.readHistory(
      limit: _queryInt(query, 'limit', 50),
      offset: _queryInt(query, 'offset', 0),
    );
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformStaff(HttpRequest request, String requestId) async {
    final query = request.uri.queryParameters;
    if (query.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform staff reads support only the profile query parameter',
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

  Future<void> _readPlatformStaffInvitations(
    HttpRequest request,
    String requestId,
  ) async {
    final query = request.uri.queryParameters;
    if (query.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Staff invitation reads support only the profile query parameter',
        statusCode: 422,
      );
    }
    final invitations = await service.listPlatformStaffInvitations(
      accessToken: _bearer(request),
      profileName: query['profile'],
    );
    await _json(request.response, 200, <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'invitations': invitations,
      'request_id': requestId,
    });
  }

  Future<void> _invitePlatformStaff(
    HttpRequest request,
    String requestId,
  ) async {
    final query = request.uri.queryParameters;
    if (query.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Staff invitations support only the profile query parameter',
        statusCode: 422,
      );
    }
    final body = await _jsonBody(request);
    const allowed = <String>{'email', 'role', 'expires_at'};
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(const <String>{'email', 'role'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Staff invitations require email and role',
        statusCode: 422,
      );
    }
    final invitation = await service.invitePlatformStaff(
      accessToken: _bearer(request),
      profileName: query['profile'],
      email: _string(body, 'email'),
      role: _string(body, 'role'),
      expiresAt: _optionalDateTime(body, 'expires_at'),
      idempotencyKey: _idempotency(request),
      requestId: requestId,
    );
    await _json(request.response, 201, <String, Object?>{
      ...invitation.toJson(now: DateTime.now().toUtc()),
      'request_id': requestId,
    });
  }

  Future<void> _updatePlatformStaff(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final query = request.uri.queryParameters;
    if (query.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Staff updates support only the profile query parameter',
        statusCode: 422,
      );
    }
    final body = await _jsonBody(request);
    const allowed = <String>{'role', 'active'};
    if (body.keys.any((key) => !allowed.contains(key)) || body.isEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Staff updates require role or active',
        statusCode: 422,
      );
    }
    final active = body['active'];
    if (active != null && active is! bool) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Staff active must be a boolean',
        statusCode: 422,
      );
    }
    final result = await service.updatePlatformStaff(
      accessToken: _bearer(request),
      profileName: query['profile'],
      userId: path[3],
      role: _optionalString(body, 'role'),
      active: active as bool?,
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _revokePlatformStaffSessions(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    if (request.uri.hasQuery &&
        request.uri.queryParameters.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Session revocation supports only the profile query parameter',
        statusCode: 422,
      );
    }
    final count = await service.revokePlatformStaffSessions(
      accessToken: _bearer(request),
      profileName: request.uri.queryParameters['profile'],
      userId: path[3],
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      'status': 'revoked',
      'session_count': count,
      'request_id': requestId,
    });
  }

  Future<void> _revokePlatformStaffInvitation(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    if (request.uri.hasQuery &&
        request.uri.queryParameters.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Staff invitation revocation supports only the profile query parameter',
        statusCode: 422,
      );
    }
    final invitation = await service.revokePlatformStaffInvitation(
      accessToken: _bearer(request),
      profileName: request.uri.queryParameters['profile'],
      invitationId: path[4],
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...invitation.toMetadataJson(now: DateTime.now().toUtc()),
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformSupportCases(
    HttpRequest request,
    String requestId,
  ) async {
    final query = request.uri.queryParameters;
    const allowed = <String>{
      'profile',
      'status',
      'q',
      'organization_id',
      'limit',
      'offset',
    };
    if (query.keys.any((key) => !allowed.contains(key))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform support accepts profile, status, q, organization_id, limit, and offset',
        statusCode: 422,
      );
    }
    final projection = await service.listPlatformSupportCases(
      accessToken: _bearer(request),
      profileName: query['profile'],
      status: query['status'],
      query: query['q'],
      organizationId: query['organization_id'],
      limit: _queryInt(query, 'limit', 50),
      offset: _queryInt(query, 'offset', 0),
    );
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformSupportCase(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final query = request.uri.queryParameters;
    if (query.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform support case reads support only the profile query parameter',
        statusCode: 422,
      );
    }
    final projection = await service.readPlatformSupportCase(
      accessToken: _bearer(request),
      profileName: query['profile'],
      caseId: path[4],
    );
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _updatePlatformSupportCase(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    if (request.uri.queryParameters.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform support updates support only the profile query parameter',
        statusCode: 422,
      );
    }
    final body = await _jsonBody(request);
    const allowed = <String>{'status', 'priority', 'assigned_to'};
    if (body.keys.any((key) => !allowed.contains(key)) || body.isEmpty) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Support case updates require status, priority, or assigned_to',
        statusCode: 422,
      );
    }
    final projection = await service.updatePlatformSupportCase(
      accessToken: _bearer(request),
      profileName: request.uri.queryParameters['profile'],
      caseId: path[4],
      status: _optionalString(body, 'status'),
      priority: _optionalString(body, 'priority'),
      assignedTo: _nullableString(body, 'assigned_to'),
      clearAssignedTo:
          body.containsKey('assigned_to') && body['assigned_to'] == null,
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _replyPlatformSupportCase(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    if (request.uri.queryParameters.keys.any((key) => key != 'profile')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform support replies support only the profile query parameter',
        statusCode: 422,
      );
    }
    final body = await _jsonBody(request);
    final allowed = <String>{'body', 'visibility'};
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.containsKey('body')) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Support replies require body and optionally visibility',
        statusCode: 422,
      );
    }
    final projection = await service.replyPlatformSupportCase(
      accessToken: _bearer(request),
      profileName: request.uri.queryParameters['profile'],
      caseId: path[4],
      body: _string(body, 'body'),
      visibility:
          _optionalString(body, 'visibility') ?? customerSupportVisibility,
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformOrganizations(
    HttpRequest request,
    String requestId,
  ) async {
    final query = request.uri.queryParameters;
    const allowed = <String>{'profile', 'q', 'limit', 'offset'};
    if (query.keys.any((key) => !allowed.contains(key))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform organizations supports profile, q, limit, and offset query parameters',
        statusCode: 422,
      );
    }
    final auth = _humanAuth();
    final operator = await auth.authorizePlatformCapability(
      accessToken: _bearer(request),
      capability: platformOrganizationsReadCapability,
      profileName: query['profile'],
    );
    final projection = await _platformConsole.listOrganizationsPage(
      query: query['q'],
      limit: _queryInt(query, 'limit', defaultPlatformOrganizationLimit),
      offset: _queryInt(query, 'offset', 0),
      includeCommercial: auth.hasPlatformCapability(
        operator,
        platformCommercialReadCapability,
        profileName: query['profile'],
      ),
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
    final auth = _humanAuth();
    final operator = await auth.authorizePlatformCapability(
      accessToken: _bearer(request),
      capability: platformOrganizationsInspectCapability,
      profileName: query['profile'],
    );
    final projection = await _platformConsole.readOrganization(
      path[3],
      includeCommercial: auth.hasPlatformCapability(
        operator,
        platformCommercialReadCapability,
        profileName: query['profile'],
      ),
    );
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformAudit(HttpRequest request, String requestId) async {
    final query = request.uri.queryParameters;
    const allowed = <String>{'profile', 'organization_id', 'limit', 'offset'};
    if (query.keys.any((key) => !allowed.contains(key))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform audit supports profile, organization_id, limit, and offset query parameters',
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
      limit: _queryInt(query, 'limit', defaultPlatformOrganizationLimit),
      offset: _queryInt(query, 'offset', 0),
    );
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readPlatformUsers(HttpRequest request, String requestId) async {
    final query = request.uri.queryParameters;
    const allowed = <String>{'profile', 'q', 'limit', 'offset'};
    if (query.keys.any((key) => !allowed.contains(key))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Platform users supports profile, q, limit, and offset query parameters',
        statusCode: 422,
      );
    }
    await _humanAuth().authorizePlatformCapability(
      accessToken: _bearer(request),
      capability: platformAccountsReadCapability,
      profileName: query['profile'],
    );
    final projection = await _platformConsole.listUsers(
      query: query['q'],
      limit: _queryInt(query, 'limit', defaultPlatformOrganizationLimit),
      offset: _queryInt(query, 'offset', 0),
    );
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

  Future<void> _updateOrganizationMember(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'role'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Member updates support only role',
        statusCode: 422,
      );
    }
    final member = await service.updateOrganizationMemberRole(
      token: _bearer(request),
      organizationId: path[2],
      userId: path[4],
      role: _string(body, 'role'),
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...member,
      'request_id': requestId,
    });
  }

  Future<void> _removeOrganizationMember(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    await service.removeOrganizationMember(
      token: _bearer(request),
      organizationId: path[2],
      userId: path[4],
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      'status': 'removed',
      'user_id': path[4],
      'request_id': requestId,
    });
  }

  Future<void> _readOrganizationInvitations(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    if (request.uri.hasQuery) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Organization invitation reads do not accept query parameters',
        statusCode: 422,
      );
    }
    final invitations = await service.listOrganizationInvitations(
      token: _bearer(request),
      organizationId: path[2],
    );
    await _json(request.response, 200, <String, Object?>{
      'schemaVersion': 1,
      'readOnly': true,
      'invitations': invitations,
      'request_id': requestId,
    });
  }

  Future<void> _inviteOrganizationMember(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    const allowed = <String>{'email', 'role', 'expires_at'};
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(const <String>{'email', 'role'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Member invitations require email and role',
        statusCode: 422,
      );
    }
    final invitation = await service.inviteOrganizationMember(
      token: _bearer(request),
      organizationId: path[2],
      email: _string(body, 'email'),
      role: _string(body, 'role'),
      expiresAt: _optionalDateTime(body, 'expires_at'),
      idempotencyKey: _idempotency(request),
      requestId: requestId,
    );
    await _json(request.response, 201, <String, Object?>{
      ...invitation.toJson(),
      'request_id': requestId,
    });
  }

  Future<void> _revokeOrganizationInvitation(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final invitation = await service.revokeOrganizationInvitation(
      token: _bearer(request),
      organizationId: path[2],
      invitationId: path[4],
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...invitation.toMetadataJson(now: DateTime.now().toUtc()),
      'request_id': requestId,
    });
  }

  Future<void> _transferOrganizationOwnership(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'target_user_id'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Ownership transfer requires target_user_id',
        statusCode: 422,
      );
    }
    final result = await service.transferOrganizationOwnership(
      token: _bearer(request),
      organizationId: path[2],
      targetUserId: _string(body, 'target_user_id'),
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _previewOrganizationInvitation(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    if (request.uri.hasQuery) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Invitation previews do not accept query parameters',
        statusCode: 422,
      );
    }
    final result = await service.previewOrganizationInvitation(token: path[2]);
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _acceptOrganizationInvitation(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    const allowed = <String>{'email', 'password'};
    if (body.keys.any((key) => !allowed.contains(key))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Invitation acceptance supports email and password',
        statusCode: 422,
      );
    }
    final result = await service.acceptOrganizationInvitation(
      token: path[2],
      accessToken: _optionalBearer(request),
      email: _optionalString(body, 'email'),
      password: _optionalString(body, 'password'),
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _previewPlatformStaffInvitation(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    if (request.uri.hasQuery) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Invitation previews do not accept query parameters',
        statusCode: 422,
      );
    }
    final result = await service.previewPlatformStaffInvitation(token: path[2]);
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _acceptPlatformStaffInvitation(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'email', 'password'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Staff invitation acceptance requires email and password',
        statusCode: 422,
      );
    }
    final result = await service.acceptPlatformStaffInvitation(
      token: path[2],
      email: _string(body, 'email'),
      password: _string(body, 'password'),
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...result,
      'request_id': requestId,
    });
  }

  Future<void> _readSupportCases(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final query = request.uri.queryParameters;
    const allowed = <String>{'status', 'q', 'limit', 'offset'};
    if (query.keys.any((key) => !allowed.contains(key))) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Support case reads accept status, q, limit, and offset',
        statusCode: 422,
      );
    }
    final projection = await service.listSupportCases(
      token: _bearer(request),
      organizationId: path[2],
      status: query['status'],
      query: query['q'],
      limit: _queryInt(query, 'limit', 50),
      offset: _queryInt(query, 'offset', 0),
    );
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _createSupportCase(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    const allowed = <String>{
      'subject',
      'description',
      'category',
      'priority',
      'application_id',
      'environment_id',
    };
    if (body.keys.any((key) => !allowed.contains(key)) ||
        !body.keys.toSet().containsAll(const <String>{
          'subject',
          'description',
        })) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Support cases require subject and description',
        statusCode: 422,
      );
    }
    final projection = await service.createSupportCase(
      token: _bearer(request),
      organizationId: path[2],
      subject: _string(body, 'subject'),
      description: _string(body, 'description'),
      category: _optionalString(body, 'category') ?? 'general',
      priority: _optionalString(body, 'priority') ?? 'NORMAL',
      applicationId: _optionalString(body, 'application_id'),
      environmentId: _optionalString(body, 'environment_id'),
      requestId: requestId,
    );
    await _json(request.response, 201, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _readSupportCase(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    if (request.uri.hasQuery) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Support case reads do not accept query parameters',
        statusCode: 422,
      );
    }
    final projection = await service.readSupportCase(
      token: _bearer(request),
      organizationId: path[2],
      caseId: path[5],
    );
    await _json(request.response, 200, <String, Object?>{
      ...projection,
      'request_id': requestId,
    });
  }

  Future<void> _replySupportCase(
    HttpRequest request,
    List<String> path,
    String requestId,
  ) async {
    final body = await _jsonBody(request);
    if (!setEquals(body.keys.toSet(), const <String>{'body'})) {
      throw const ControlPlaneException(
        'INVALID_REQUEST',
        'Support replies require body',
        statusCode: 422,
      );
    }
    final projection = await service.replySupportCase(
      token: _bearer(request),
      organizationId: path[2],
      caseId: path[5],
      body: _string(body, 'body'),
      requestId: requestId,
    );
    await _json(request.response, 200, <String, Object?>{
      ...projection,
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

  Future<void> _updateCheck(HttpRequest request, String requestId) async {
    final body = await _jsonBody(request);
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
    );
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType('application', 'octet-stream')
      ..headers.contentLength = result.bytes.length
      ..headers.set('ETag', '"${result.record.sha256}"')
      ..headers.set('Digest', result.record.sha256);
    request.response.add(result.bytes);
    await request.response.close();
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
    if (!loopback && request.uri.scheme != 'https' && !allowInsecureAuth) {
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
        'Authorization, Content-Type, X-Request-Id',
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
