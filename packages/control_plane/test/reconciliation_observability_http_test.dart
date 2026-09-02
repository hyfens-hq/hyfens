import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

const _digest =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late Directory controlRoot;
  late Directory reconciliationRoot;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  late FileReconciliationStore reconciliationStore;
  late ReconciliationScope expectedScope;
  late ReconciliationFinding finding;
  late ReconciliationPeriodicRunner periodicRunner;
  late ControlPlaneHttpServer adapter;
  late HttpServer server;

  setUp(() async {
    controlRoot = await Directory.systemTemp.createTemp('hyfens-http-control-');
    reconciliationRoot = await Directory.systemTemp.createTemp(
      'hyfens-http-reconciliation-',
    );
    service = ControlPlaneService(store: FileControlPlaneStore(controlRoot));
    bootstrap = await service.bootstrap(
      organizationName: 'Observability HTTP',
      runtimeApplicationId: 'com.example.observability',
      platformId: 'android',
      environmentName: 'test',
    );
    expectedScope = ReconciliationScope(
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
    );
    reconciliationStore = FileReconciliationStore(reconciliationRoot);
    await reconciliationStore.initialize();
    finding = ReconciliationFinding.create(
      scope: expectedScope,
      code: ReconciliationTaxonomyCode.orphanWork,
      entityType: 'work',
      entityId: 'work_http_observability',
      sourceDigests: const <String, String>{'schedule': _digest},
      observedVersions: const <String, int>{'work': 1},
      firstObservedAt: DateTime.utc(2026, 8, 24, 11),
      lastObservedAt: DateTime.utc(2026, 8, 24, 11, 1),
      safeDetailCode: 'ORPHAN_WORK',
    );
    await reconciliationStore.putFinding(finding);
    periodicRunner = ReconciliationPeriodicRunner(
      config: const ReconciliationPeriodicConfig(),
      invokeBoundedReconciliation: () async {},
    );
    final observability = ReconciliationObservability(
      store: reconciliationStore,
      backend: 'file',
      periodicRunner: periodicRunner,
      authorizeDiagnostics: ({required token, required scope}) async {
        if (token != 'diagnostics-token' ||
            scope.canonicalSerialization !=
                expectedScope.canonicalSerialization) {
          throw const ControlPlaneException(
            'NOT_FOUND',
            'Resource was not found',
            statusCode: 404,
          );
        }
      },
    );
    adapter = ControlPlaneHttpServer(
      service,
      reconciliationObservability: observability,
      periodicRunner: periodicRunner,
    );
    server = await adapter.bind();
    _currentServerPort = server.port;
  });

  tearDown(() async {
    await adapter.close(force: true);
    _currentServerPort = null;
    await reconciliationStore.close();
    await service.store.close();
    if (await controlRoot.exists()) await controlRoot.delete(recursive: true);
    if (await reconciliationRoot.exists()) {
      await reconciliationRoot.delete(recursive: true);
    }
  });

  test('live, readiness, metrics, and diagnostics remain read-only', () async {
    final client = HttpClient();
    try {
      final live = await _get(client, '/livez');
      expect(live.statusCode, 200);
      final ready = await _get(client, '/readyz');
      expect(ready.statusCode, 200);
      expect((ready.body['reconciliation']! as Map)['code'], 'READY');
      final beforeCursor = await reconciliationStore.readCursor(expectedScope);

      final metrics = await _get(client, '/metrics');
      expect(metrics.statusCode, 200);
      expect(metrics.body['reconciliation'], isA<Map>());
      expect(
        jsonEncode(metrics.body),
        isNot(contains(expectedScope.organizationId)),
      );
      expect(
        (metrics.body['reconciliation']! as Map<String, Object?>)['periodic'],
        isA<Map<String, Object?>>(),
      );

      final diagnosticPath =
          '/v1/reconciliation/diagnostics?organization_id=${expectedScope.organizationId}'
          '&application_id=${expectedScope.applicationId}'
          '&environment_id=${expectedScope.environmentId}&limit=1';
      final diagnostics = await _get(
        client,
        diagnosticPath,
        token: 'diagnostics-token',
      );
      expect(diagnostics.statusCode, 200);
      final findings = diagnostics.body['findings']! as List<Object?>;
      expect(findings, hasLength(1));
      expect(
        (findings.single as Map<String, Object?>)['actionDisposition'],
        'REPORT_ONLY',
      );
      expect(diagnostics.body['periodic'], containsPair('enabled', false));
      expect(
        (await reconciliationStore.readCursor(expectedScope))
            ?.canonicalSerialization,
        beforeCursor?.canonicalSerialization,
      );

      final unknown = await _get(
        client,
        '/v1/reconciliation/findings/unknown-finding?organization_id=${expectedScope.organizationId}'
        '&application_id=${expectedScope.applicationId}'
        '&environment_id=${expectedScope.environmentId}',
        token: 'diagnostics-token',
      );
      final foreign = await _get(
        client,
        '/v1/reconciliation/findings/unknown-finding?organization_id=org_foreign'
        '&application_id=app_foreign&environment_id=env_foreign',
        token: 'diagnostics-token',
      );
      expect(foreign.statusCode, unknown.statusCode);
      expect(foreign.body['error'], unknown.body['error']);
    } finally {
      client.close(force: true);
    }
  });

  test(
    'liveness stays healthy while reconciliation store is unavailable',
    () async {
      final client = HttpClient();
      try {
        await reconciliationStore.close();
        final live = await _get(client, '/livez');
        final ready = await _get(client, '/readyz');
        final metrics = await _get(client, '/metrics');
        expect(live.statusCode, 200);
        expect(ready.statusCode, 503);
        expect(
          (ready.body['reconciliation']! as Map)['code'],
          'RECONCILIATION_STORE_UNAVAILABLE',
        );
        expect(metrics.statusCode, 200);
        await reconciliationStore.initialize();
        expect((await _get(client, '/readyz')).statusCode, 200);
      } finally {
        client.close(force: true);
      }
    },
  );
}

Future<_Response> _get(HttpClient client, String path, {String? token}) async {
  final request = await client.getUrl(
    Uri.parse('http://127.0.0.1:${_currentServerPort!}$path'),
  );
  if (token != null) request.headers.set('Authorization', 'Bearer $token');
  final response = await request.close();
  final body = jsonDecode(
    await response.transform(utf8.decoder).join(),
  ) as Map<String, Object?>;
  return _Response(response.statusCode, body);
}

int? _currentServerPort;

final class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}
