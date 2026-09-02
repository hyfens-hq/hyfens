import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  late DateTime now;
  late ReleaseRecord release;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-observation-');
    now = DateTime.utc(2026, 8, 23, 12);
    service = ControlPlaneService(
      store: FileControlPlaneStore(directory),
      clock: () => now,
    );
    bootstrap = await service.bootstrap(
      organizationName: 'Observation organization',
      runtimeApplicationId: 'com.example.observations',
      platformId: 'android',
      environmentName: 'test',
    );
    release = await service.registerRelease(
      token: bootstrap.controlCredential.token,
      idempotencyKey: 'observation-release',
      spec: ReleaseSpec(
        applicationId: bootstrap.application.id,
        platformId: 'android',
        runtimeApplicationId: 'com.example.observations',
        runtimeReleaseId: 'observation-runtime-release',
        buildTarget: 'android-arm64-release',
        runtimeCompatibilityVersion: 1,
        patchFormatVersion: 1,
        buildFingerprint: _digest('build'),
        capabilityAuthorityDigest: _digest('capabilities'),
        functionSignatureDigest: _digest('functions'),
        displayVersion: '0.1.0',
        signingPublicKeys: <String, String>{
          'observation-key': base64.encode(List<int>.filled(32, 7)),
        },
      ),
    );
  });

  tearDown(() => directory.delete(recursive: true));

  ObservationEvent event(
    String id,
    ObservationEventType type, {
    DateTime? timestamp,
    String bucket = 'bucket:1',
    String? patchId,
    int? sequence,
    String? rolloutId,
    int? rolloutRevision,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => ObservationEvent(
    schemaVersion: 1,
    eventId: id,
    clientTimestamp: timestamp ?? now,
    organizationId: bootstrap.organization.id,
    applicationId: bootstrap.application.id,
    environmentId: bootstrap.environment.id,
    platform: 'android',
    releaseId: release.id,
    patchId: patchId,
    sequence: sequence,
    rolloutId: rolloutId,
    rolloutRevision: rolloutRevision,
    installationBucket: bucket,
    eventType: type,
    runtimeVersion: 'runtime-1',
    patchFormatVersion: 1,
    diagnosticCode: null,
    safeMetadata: metadata,
  );

  Future<IssuedCredential> issueToken({
    Duration lifetime = const Duration(minutes: 5),
  }) => service.issueObservationToken(
    token: bootstrap.controlCredential.token,
    organizationId: bootstrap.organization.id,
    applicationId: bootstrap.application.id,
    environmentId: bootstrap.environment.id,
    lifetime: lifetime,
  );

  test('schema is deterministic and rejects unsafe metadata', () {
    final original = event(
      'event-roundtrip',
      ObservationEventType.lookup_attempt,
      metadata: <String, Object?>{'attempt': 1, 'cache_hit': false},
    );
    expect(
      canonicalJson(ObservationEvent.fromJson(original.toJson()).toJson()),
      canonicalJson(original.toJson()),
    );
    expect(
      () => event(
        'event-nested',
        ObservationEventType.lookup_attempt,
        metadata: <String, Object?>{
          'nested': <String, Object?>{'value': true},
        },
      ),
      throwsFormatException,
    );
    expect(
      () => event(
        'event-unknown-key',
        ObservationEventType.lookup_attempt,
        metadata: <String, Object?>{'private.key': 'not-private-data'},
      ),
      throwsFormatException,
    );
  });

  test('accepts duplicate retries and rejects duplicate mutation', () async {
    final token = await issueToken();
    final first = await service.ingestObservation(
      token: token.token,
      event: event('event-duplicate', ObservationEventType.lookup_attempt),
    );
    final retry = await service.ingestObservation(
      token: token.token,
      event: event('event-duplicate', ObservationEventType.lookup_attempt),
    );
    expect(first.duplicate, isFalse);
    expect(retry.duplicate, isTrue);
    await expectLater(
      service.ingestObservation(
        token: token.token,
        event: event('event-duplicate', ObservationEventType.candidate_offered),
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'EVENT_DUPLICATE_MUTATION',
        ),
      ),
    );
  });

  test('observation tokens cannot cross organization boundaries', () async {
    final foreign = await service.bootstrap(
      organizationName: 'Foreign observation organization',
      runtimeApplicationId: 'com.example.foreign.observations',
      platformId: 'android',
      environmentName: 'test',
    );
    final foreignToken = await service.issueObservationToken(
      token: foreign.controlCredential.token,
      organizationId: foreign.organization.id,
      applicationId: foreign.application.id,
      environmentId: foreign.environment.id,
    );
    await expectLater(
      service.ingestObservation(
        token: foreignToken.token,
        event: event('event-cross-tenant', ObservationEventType.lookup_attempt),
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'OBSERVATION_SCOPE_MISMATCH',
        ),
      ),
    );
  });

  test(
    'quarantines impossible sequences without affecting later valid events',
    () async {
      final token = await issueToken();
      final impossible = await service.ingestObservation(
        token: token.token,
        event: event(
          'event-healthy-first',
          ObservationEventType.healthy_confirmed,
        ),
      );
      expect(impossible.disposition, ObservationDisposition.quarantined);
      expect(
        (await service.ingestObservation(
          token: token.token,
          event: event(
            'event-activation-started',
            ObservationEventType.activation_started,
          ),
        )).disposition,
        ObservationDisposition.accepted,
      );
      expect(
        (await service.ingestObservation(
          token: token.token,
          event: event(
            'event-activation-succeeded',
            ObservationEventType.activation_succeeded,
          ),
        )).disposition,
        ObservationDisposition.accepted,
      );
      expect(
        (await service.ingestObservation(
          token: token.token,
          event: event('event-healthy', ObservationEventType.healthy_confirmed),
        )).disposition,
        ObservationDisposition.accepted,
      );
      expect(
        (await service.ingestObservation(
          token: token.token,
          event: event('event-restart', ObservationEventType.restart_survived),
        )).disposition,
        ObservationDisposition.accepted,
      );
    },
  );

  test(
    'enforces clock bounds, late disposition, and retention deletion',
    () async {
      final token = await issueToken();
      await expectLater(
        service.ingestObservation(
          token: token.token,
          event: event(
            'event-future',
            ObservationEventType.lookup_attempt,
            timestamp: now.add(const Duration(hours: 1)),
          ),
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'EVENT_CLOCK_INVALID',
          ),
        ),
      );
      final late = await service.ingestObservation(
        token: token.token,
        event: event(
          'event-late',
          ObservationEventType.lookup_attempt,
          timestamp: now.subtract(const Duration(days: 8)),
        ),
      );
      expect(late.disposition, ObservationDisposition.late);
      final lateStorageId = observationStorageId(
        organizationId: bootstrap.organization.id,
        applicationId: bootstrap.application.id,
        environmentId: bootstrap.environment.id,
        eventId: 'event-late',
      );
      final lateValue = await service.store.readJson(
        'observations',
        lateStorageId,
      );
      await service.store.replaceJson(
        'observations',
        lateStorageId,
        <String, Object?>{
          ...lateValue!,
          'receivedAt': now.subtract(const Duration(days: 8)).toIso8601String(),
        },
      );
      expect(
        await service.deleteObservations(
          token: bootstrap.controlCredential.token,
          organizationId: bootstrap.organization.id,
          olderThan: now.subtract(const Duration(days: 7)),
        ),
        1,
      );
      await expectLater(
        service.ingestObservation(
          token: token.token,
          event: event(
            'event-old',
            ObservationEventType.lookup_attempt,
            timestamp: now.subtract(const Duration(days: 31)),
          ),
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'EVENT_OUTSIDE_RETENTION',
          ),
        ),
      );
    },
  );

  test('observation tokens are bounded and revocable', () async {
    final expiring = await issueToken(lifetime: const Duration(seconds: 1));
    now = now.add(const Duration(seconds: 2));
    await expectLater(
      service.ingestObservation(
        token: expiring.token,
        event: event('event-expired', ObservationEventType.lookup_attempt),
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'UNAUTHORIZED',
        ),
      ),
    );
    final replacement = await issueToken();
    await service.revokeCredential(
      token: bootstrap.controlCredential.token,
      credentialId: replacement.record.id,
      organizationId: bootstrap.organization.id,
    );
    await expectLater(
      service.ingestObservation(
        token: replacement.token,
        event: event('event-revoked', ObservationEventType.lookup_attempt),
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'UNAUTHORIZED',
        ),
      ),
    );
  });

  test(
    'rate limiting is bounded per token and does not block update checks',
    () async {
      final limited = ControlPlaneService(
        store: FileControlPlaneStore(directory),
        clock: () => now,
        observationPolicy: const ObservationPolicy(
          maxEventsPerTokenWindow: 1,
          maxEventsPerInstallationWindow: 1,
          maxEventsPerTypeWindow: 1,
        ),
      );
      final token = await limited.issueObservationToken(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
        applicationId: bootstrap.application.id,
        environmentId: bootstrap.environment.id,
      );
      final first = event('event-rate-1', ObservationEventType.lookup_attempt);
      await limited.ingestObservation(token: token.token, event: first);
      await expectLater(
        limited.ingestObservation(
          token: token.token,
          event: event('event-rate-2', ObservationEventType.lookup_attempt),
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'EVENT_RATE_LIMITED',
          ),
        ),
      );
    },
  );

  test('delivery lookup remains independent when observation storage is unavailable', () async {
    final observations = Directory('${directory.path}/observations');
    final unavailable = Directory('${directory.path}/observations.offline');
    await observations.rename(unavailable.path);
    try {
      final result = await service.updateCheck(
        token: bootstrap.deliveryCredential.token,
        request: UpdateCheckRequest(
          applicationId: bootstrap.application.id,
          environmentId: bootstrap.environment.id,
          runtimeApplicationId: 'com.example.observations',
          runtimeReleaseId: 'runtime-release',
          runtimeCompatibilityVersion: 1,
          patchFormatVersion: 1,
          highWaterSequence: 0,
        ),
      );
      expect(result.decision, 'NO_UPDATE');
    } finally {
      await unavailable.rename(observations.path);
    }
  });
}

String _digest(String value) => sha256Digest(utf8.encode(value));
