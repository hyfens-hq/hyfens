import 'dart:io';
import 'dart:math';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  if (url == null || url.isEmpty) {
    test(
      'PostgreSQL service integration requires HYFENS_TEST_POSTGRES_URL',
      () {},
      skip: 'PostgreSQL integration environment is not configured',
    );
    return;
  }

  late PostgresControlPlaneStore store;
  late ControlPlaneService service;
  final suffix = DateTime.now().microsecondsSinceEpoch.toString();

  setUp(() async {
    store = PostgresControlPlaneStore(url);
    // The external PostgreSQL fixture is intentionally reused across test
    // invocations, so deterministic IDs would collide with a prior run.
    service = ControlPlaneService(store: store, random: Random());
    await service.initialize();
  });

  tearDown(() => store.close());

  test(
    'service persists isolated bootstrap tenants through PostgreSQL',
    () async {
      final first = await service.bootstrap(
        organizationName: 'First $suffix',
        runtimeApplicationId: 'com.example.first.$suffix',
        platformId: 'android',
        environmentName: 'production',
      );
      final second = await service.bootstrap(
        organizationName: 'Second $suffix',
        runtimeApplicationId: 'com.example.second.$suffix',
        platformId: 'ios',
        environmentName: 'production',
      );

      expect(
        (await store.listJson('organizations'))
            .where((record) => record['id'] == first.organization.id),
        hasLength(1),
      );
      expect(
        (await store.listJson('organizations'))
            .where((record) => record['id'] == second.organization.id),
        hasLength(1),
      );
      expect(
        service.readAudit(
          token: first.controlCredential.token,
          organizationId: second.organization.id,
        ),
        throwsA(isA<ControlPlaneException>()),
      );
      expect(
        service.updateCheck(
          token: first.deliveryCredential.token,
          request: UpdateCheckRequest(
            applicationId: second.application.id,
            environmentId: second.environment.id,
            runtimeApplicationId: 'com.example.second.$suffix',
            runtimeReleaseId: 'release-other',
            runtimeCompatibilityVersion: 1,
            patchFormatVersion: 1,
            highWaterSequence: 0,
          ),
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    },
  );
}
