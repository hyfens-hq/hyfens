import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late CloudUsageMeteringService metering;
  final now = DateTime.utc(2026, 9, 7, 12);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-usage-');
    store = FileControlPlaneStore(directory);
    await store.initialize();
    metering = CloudUsageMeteringService(
      store,
      deploymentModel: DeploymentModel.cloud,
      clock: () => now,
    );
  });

  tearDown(() => directory.delete(recursive: true));

  test(
    'storage usage is attributable and storage events are idempotent',
    () async {
      final artifact = _artifact(
        organizationId: 'org_usage_a',
        id: 'art_usage_a',
        sizeBytes: 1024,
      );
      await store.createJson('artifacts', artifact.id, artifact.toJson());

      expect(
        await metering.recordArtifactStorageAdded(
          artifact: artifact,
          sourceId: 'upload:usage-a',
          occurredAt: artifact.createdAt,
        ),
        isTrue,
      );
      expect(
        await metering.recordArtifactStorageAdded(
          artifact: artifact,
          sourceId: 'upload:usage-a',
          occurredAt: artifact.createdAt,
        ),
        isFalse,
      );

      final usage = await metering.readUsage(
        organizationId: artifact.organizationId,
      );
      expect(usage?.artifactStorageBytesCurrent, 1024);
      expect((await store.listJson(cloudUsageEventsCollection)), hasLength(1));
    },
  );

  test(
    'storage removal follows the logical ready lifecycle and reconciles',
    () async {
      final artifact = _artifact(
        organizationId: 'org_usage_a',
        id: 'art_usage_b',
        sizeBytes: 4096,
      );
      await store.createJson('artifacts', artifact.id, artifact.toJson());
      await metering.recordArtifactStorageAdded(
        artifact: artifact,
        sourceId: 'upload:usage-b',
        occurredAt: artifact.createdAt,
      );
      expect(
        (await metering.reconcileStorage(
          organizationId: artifact.organizationId,
        )).balanced,
        isTrue,
      );

      await store.replaceJson(
        'artifacts',
        artifact.id,
        artifact.copyWith(state: 'QUARANTINED').toJson(),
      );
      expect(
        await metering.recordArtifactStorageRemoved(
          artifact: artifact,
          sourceId: 'quarantine:usage-b',
        ),
        isTrue,
      );
      expect(
        await metering.recordArtifactStorageRemoved(
          artifact: artifact,
          sourceId: 'quarantine:usage-b',
        ),
        isFalse,
      );
      expect(
        (await metering.readUsage(organizationId: artifact.organizationId))
            ?.artifactStorageBytesCurrent,
        0,
      );
      final report = await metering.reconcileStorage(
        organizationId: artifact.organizationId,
      );
      expect(report.balanced, isTrue);
      expect(report.accountedStorageBytes, 0);
    },
  );

  test(
    'reconciliation reports a missing storage fact without repairing it',
    () async {
      final artifact = _artifact(
        organizationId: 'org_usage_a',
        id: 'art_usage_c',
        sizeBytes: 8192,
      );
      await store.createJson('artifacts', artifact.id, artifact.toJson());

      final report = await metering.reconcileStorage(
        organizationId: artifact.organizationId,
      );
      expect(report.balanced, isFalse);
      expect(report.expectedStorageBytes, 8192);
      expect(report.accountedStorageBytes, 0);
      expect(report.findings, contains('storage_event_net_mismatch'));
      expect(await store.listJson(cloudUsageEventsCollection), isEmpty);
    },
  );

  test('delivery counts exact origin bytes for the requested period', () async {
    final period = CloudUsagePeriod(
      start: DateTime.utc(2026, 9),
      end: DateTime.utc(2026, 10),
    );
    final artifact = _artifact(
      organizationId: 'org_usage_a',
      id: 'art_delivery_a',
      sizeBytes: 1,
    );
    await store.createJson('artifacts', artifact.id, artifact.toJson());
    expect(
      await metering.recordArtifactDelivery(
        artifact: artifact,
        bytes: 1 << 40,
        sourceId: 'delivery:one',
        occurredAt: DateTime.utc(2026, 9, 2),
      ),
      isTrue,
    );
    expect(
      await metering.recordArtifactDelivery(
        artifact: artifact,
        bytes: 1 << 40,
        sourceId: 'delivery:one',
        occurredAt: DateTime.utc(2026, 9, 2),
      ),
      isFalse,
    );
    await metering.recordArtifactDelivery(
      artifact: artifact,
      bytes: 7,
      sourceId: 'delivery:outside',
      occurredAt: DateTime.utc(2026, 10, 1),
    );

    final usage = await metering.readUsage(
      organizationId: 'org_usage_a',
      period: period,
    );
    expect(usage?.artifactDeliveryBytesPeriod, 1 << 40);
    expect(usage?.artifactDeliveryAuthoritative, isFalse);
    expect(
      usage?.artifactDeliveryAuthority,
      CloudDeliveryMeterAuthority.partial.name,
    );
    expect(usage?.artifactDeliveryQuotaEligible, isFalse);
    expect(usage?.period.start, period.start);
    expect(usage?.period.end, period.end);
  });

  test(
    'trusted delivery observations resolve ownership and use occurrence time',
    () async {
      final artifact = _artifact(
        organizationId: 'org_usage_a',
        id: 'art_delivery_b',
        sizeBytes: 32,
      );
      await store.createJson('artifacts', artifact.id, artifact.toJson());
      final observation = TrustedArtifactDeliveryObservation(
        artifactId: artifact.id,
        artifactDigest: artifact.sha256,
        source: artifactDeliveryCdnSource,
        sourceId: 'cdn:late-1',
        bytes: 32,
        occurredAt: DateTime.utc(2026, 8, 31, 23, 59),
      );

      expect(
        await metering.recordTrustedArtifactDelivery(observation: observation),
        isTrue,
      );
      expect(
        await metering.recordTrustedArtifactDelivery(observation: observation),
        isFalse,
      );
      expect(
        (await metering.readUsage(
          organizationId: artifact.organizationId,
          period: CloudUsagePeriod(
            start: DateTime.utc(2026, 8),
            end: DateTime.utc(2026, 9),
          ),
        ))?.artifactDeliveryBytesPeriod,
        32,
      );
      expect(
        (await metering.readUsage(organizationId: 'org_usage_b'))
            ?.artifactDeliveryBytesPeriod,
        0,
      );
      expect(
        () => TrustedArtifactDeliveryObservation(
          artifactId: artifact.id,
          source: 'customer_report',
          sourceId: 'spoofed',
          bytes: 32,
          occurredAt: now,
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        metering.recordTrustedArtifactDelivery(
          observation: TrustedArtifactDeliveryObservation(
            artifactId: artifact.id,
            artifactDigest: sha256Digest(utf8.encode('different-artifact')),
            source: artifactDeliveryCdnSource,
            sourceId: 'cdn:mismatch',
            bytes: 32,
            occurredAt: now,
          ),
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'DELIVERY_ARTIFACT_MISMATCH',
          ),
        ),
      );
    },
  );

  test(
    'organizations are isolated and conflicting event identities fail',
    () async {
      final artifactA = _artifact(
        organizationId: 'org_usage_a',
        id: 'art_usage_d',
        sizeBytes: 10,
      );
      final artifactB = _artifact(
        organizationId: 'org_usage_b',
        id: 'art_usage_e',
        sizeBytes: 20,
      );
      await store.createJson('artifacts', artifactA.id, artifactA.toJson());
      await store.createJson('artifacts', artifactB.id, artifactB.toJson());
      await metering.recordArtifactStorageAdded(
        artifact: artifactA,
        sourceId: 'upload:usage-d',
      );
      await metering.recordArtifactStorageAdded(
        artifact: artifactB,
        sourceId: 'upload:usage-e',
      );

      expect(
        (await metering.readUsage(organizationId: artifactA.organizationId))
            ?.artifactStorageBytesCurrent,
        10,
      );
      expect(
        (await metering.readUsage(organizationId: artifactB.organizationId))
            ?.artifactStorageBytesCurrent,
        20,
      );
      await metering.recordArtifactDelivery(
        artifact: artifactA,
        bytes: 10,
        sourceId: 'delivery:one',
      );
      await expectLater(
        metering.recordArtifactDelivery(
          artifact: artifactA,
          bytes: 11,
          sourceId: 'delivery:one',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'USAGE_EVENT_CONFLICT',
          ),
        ),
      );
    },
  );

  test('self-hosted deployments do not emit Cloud usage', () async {
    final selfHosted = CloudUsageMeteringService(
      store,
      deploymentModel: DeploymentModel.selfHosted,
      clock: () => now,
    );
    final artifact = _artifact(
      organizationId: 'org_usage_a',
      id: 'art_usage_f',
      sizeBytes: 32,
    );
    await store.createJson('artifacts', artifact.id, artifact.toJson());

    expect(
      await selfHosted.recordArtifactStorageAdded(
        artifact: artifact,
        sourceId: 'self-hosted-upload',
      ),
      isFalse,
    );
    expect(
      await selfHosted.recordArtifactDelivery(
        artifact: artifact,
        bytes: 32,
        sourceId: 'self-hosted-delivery',
      ),
      isFalse,
    );
    expect(
      await selfHosted.readUsage(organizationId: artifact.organizationId),
      isNull,
    );
    expect(await store.listJson(cloudUsageEventsCollection), isEmpty);
  });

  test('Cloud billing projects measured usage without quota fields', () async {
    final service = ControlPlaneService(
      store: store,
      deploymentModel: DeploymentModel.cloud,
      clock: () => now,
    );
    final bootstrap = await service.bootstrap(
      organizationName: 'Usage billing organization',
      runtimeApplicationId: 'com.example.usage',
      platformId: 'android',
      environmentName: 'development',
    );
    final artifact = _artifact(
      organizationId: bootstrap.organization.id,
      id: 'art_usage_g',
      sizeBytes: 5,
    );
    await store.createJson('artifacts', artifact.id, artifact.toJson());
    await service.usageMetering.ensureArtifactStorageAdded(
      artifact: artifact,
      sourceId: 'upload:usage-g',
    );
    await service.recordArtifactDelivery(
      payload: ArtifactPayload(record: artifact, bytes: List<int>.filled(5, 1)),
    );

    final snapshot = await service.billing.read(
      organizationId: bootstrap.organization.id,
    );
    expect(snapshot.usage?['artifact_storage_bytes_current'], 5);
    expect(snapshot.usage?['artifact_delivery_bytes_period'], 5);
    expect(snapshot.usage?['artifact_delivery_authoritative'], isFalse);
    expect(snapshot.usage?['artifact_delivery_authority'], 'partial');
    expect(snapshot.usage?['artifact_delivery_quota_eligible'], isFalse);
    expect(snapshot.usage?['artifact_storage_bytes_current'], isNotNull);
  });
}

ArtifactRecord _artifact({
  required String organizationId,
  required String id,
  required int sizeBytes,
  String state = 'READY',
}) => ArtifactRecord(
  id: id,
  organizationId: organizationId,
  patchId: 'pat_${id.substring(4)}',
  sha256: sha256Digest(utf8.encode(id)),
  sizeBytes: sizeBytes,
  contentType: 'application/octet-stream',
  state: state,
  createdAt: DateTime.utc(2026, 9, 1),
);
