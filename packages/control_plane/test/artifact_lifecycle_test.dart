import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late ControlPlaneService service;
  final now = DateTime.utc(2026, 9, 7, 12);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-retention-');
    store = FileControlPlaneStore(directory);
    service = ControlPlaneService(
      store: store,
      deploymentModel: DeploymentModel.cloud,
      clock: () => now,
    );
    await service.initialize();
  });

  tearDown(() => directory.delete(recursive: true));

  test('READY artifacts remain available and have no time-based expiry', () {
    final artifact = _artifact(state: artifactReadyState);
    final decision = const ArtifactRetentionPolicy().evaluate(
      artifact,
      now: now,
    );

    expect(decision.countsTowardLogicalStorage, isTrue);
    expect(decision.availableForDelivery, isTrue);
    expect(decision.availableForDeployment, isTrue);
    expect(decision.purgeEligible, isFalse);
    expect(decision.reason, 'ready_without_time_based_expiry');
  });

  test('quarantined cleanup removes bytes but preserves evidence', () async {
    final bytes = <int>[1, 2, 3, 4];
    final artifact = _artifact(
      state: artifactQuarantinedState,
      bytes: bytes,
      purgeEligibleAt: now.subtract(const Duration(minutes: 1)),
    );
    await store.putArtifact(artifact.sha256, bytes);
    await store.createJson('artifacts', artifact.id, artifact.toJson());

    final first = await service.runArtifactRetentionCleanup(
      organizationId: artifact.organizationId,
    );
    expect(first.purgedCount, 1);
    expect(first.items.single.status, 'purged');
    expect(await store.readArtifact(artifact.sha256), isNull);

    final stored = ArtifactRecord.fromJson(
      (await store.readJson('artifacts', artifact.id))!,
    );
    expect(stored.state, artifactPurgedState);
    expect(stored.purgedAt, now);
    expect(stored.purgeReason, 'quarantined_artifact_cleanup');

    final replay = await service.runArtifactRetentionCleanup(
      organizationId: artifact.organizationId,
    );
    expect(replay.purgedCount, 0);
    expect(replay.items, isEmpty);
  });

  test(
    'pending quarantined bundle imports protect their artifact bytes',
    () async {
      final bytes = <int>[5, 6, 7];
      final artifact = _artifact(
        id: 'art_pending_bundle',
        state: artifactQuarantinedState,
        bytes: bytes,
        purgeEligibleAt: now.subtract(const Duration(minutes: 1)),
      );
      await store.putArtifact(artifact.sha256, bytes);
      await store.createJson('artifacts', artifact.id, artifact.toJson());
      await store.createJson(
        'bundle_imports',
        'bundle_pending',
        <String, Object?>{
          'id': 'bundle_pending',
          'artifactId': artifact.id,
          'state': 'QUARANTINED',
        },
      );

      final report = await service.runArtifactRetentionCleanup(
        organizationId: artifact.organizationId,
      );
      expect(report.purgedCount, 0);
      expect(report.skippedCount, 1);
      expect(report.items.single.status, 'protected');
      expect(await store.readArtifact(artifact.sha256), bytes);
    },
  );

  test(
    'shared content-addressed bytes are deleted only after all owners purge',
    () async {
      final bytes = <int>[8, 9];
      final first = _artifact(
        id: 'art_shared_one',
        state: artifactQuarantinedState,
        bytes: bytes,
        purgeEligibleAt: now,
      );
      final second = _artifact(
        id: 'art_shared_two',
        state: artifactQuarantinedState,
        bytes: bytes,
        purgeEligibleAt: now,
      );
      await store.putArtifact(first.sha256, bytes);
      await store.createJson('artifacts', first.id, first.toJson());
      await store.createJson('artifacts', second.id, second.toJson());

      final report = await service.runArtifactRetentionCleanup(
        organizationId: first.organizationId,
      );
      expect(report.purgedCount, 2);
      expect(await store.readArtifact(first.sha256), isNull);
    },
  );

  test(
    'a scoped cleanup does not delete another organization owner bytes',
    () async {
      final bytes = <int>[12, 13];
      final first = _artifact(
        id: 'art_cross_org_a',
        organizationId: 'org_lifecycle',
        state: artifactQuarantinedState,
        bytes: bytes,
        purgeEligibleAt: now,
      );
      final second = _artifact(
        id: 'art_cross_org_b',
        organizationId: 'org_other',
        state: artifactQuarantinedState,
        bytes: bytes,
        purgeEligibleAt: now,
      );
      await store.putArtifact(first.sha256, bytes);
      await store.createJson('artifacts', first.id, first.toJson());
      await store.createJson('artifacts', second.id, second.toJson());

      final scoped = await service.runArtifactRetentionCleanup(
        organizationId: first.organizationId,
      );
      expect(scoped.purgedCount, 1);
      expect(scoped.items.single.status, 'purged_shared_object');
      expect(await store.readArtifact(first.sha256), bytes);
      expect(
        ArtifactRecord.fromJson((await store.readJson('artifacts', first.id))!)
            .state,
        artifactPurgedState,
      );
      expect(
        ArtifactRecord.fromJson((await store.readJson('artifacts', second.id))!)
            .state,
        artifactQuarantinedState,
      );

      final other = await service.runArtifactRetentionCleanup(
        organizationId: second.organizationId,
      );
      expect(other.purgedCount, 1);
      expect(await store.readArtifact(first.sha256), isNull);
    },
  );

  test('self-hosted cleanup does not apply Cloud retention', () async {
    final bytes = <int>[10, 11];
    final artifact = _artifact(
      id: 'art_self_hosted',
      state: artifactQuarantinedState,
      bytes: bytes,
      purgeEligibleAt: now.subtract(const Duration(minutes: 1)),
    );
    await store.putArtifact(artifact.sha256, bytes);
    await store.createJson('artifacts', artifact.id, artifact.toJson());
    final selfHosted = ControlPlaneService(
      store: store,
      deploymentModel: DeploymentModel.selfHosted,
      clock: () => now,
    );

    final report = await selfHosted.runArtifactRetentionCleanup();
    expect(report.managed, isFalse);
    expect(await store.readArtifact(artifact.sha256), bytes);
  });
}

ArtifactRecord _artifact({
  String id = 'art_lifecycle',
  String organizationId = 'org_lifecycle',
  String state = artifactQuarantinedState,
  List<int> bytes = const <int>[1, 2, 3],
  DateTime? purgeEligibleAt,
}) {
  return ArtifactRecord(
    id: id,
    organizationId: organizationId,
    patchId: 'pat_lifecycle',
    sha256: sha256Digest(bytes),
    sizeBytes: bytes.length,
    contentType: 'application/octet-stream',
    state: state,
    createdAt: DateTime.utc(2026, 9, 1),
    purgeEligibleAt: purgeEligibleAt,
  );
}
