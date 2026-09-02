import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hyfens_control_plane/control_plane.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late Directory p3eDirectory;
  late FileControlPlaneStore controlStore;
  late FileP3ePersistenceStore p3eStore;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;
  late RolloutRecord rollout;
  late RolloutRevision rolloutRevision;
  late HealthAggregate aggregate;
  late HealthAggregateRevision aggregateRevision;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-p3e-api-');
    p3eDirectory = await Directory.systemTemp.createTemp(
      'hyfens-p3e-api-store-',
    );
    controlStore = FileControlPlaneStore(directory);
    p3eStore = FileP3ePersistenceStore(p3eDirectory);
    service = ControlPlaneService(store: controlStore, p3eStore: p3eStore);
    bootstrap = await service.bootstrap(
      organizationName: 'P3E API organization',
      runtimeApplicationId: 'com.example.p3e',
      platformId: 'android',
      environmentName: 'development',
    );
    final now = DateTime.utc(2026, 8, 24, 14);
    rollout = RolloutRecord(
      id: 'rollout_api',
      organizationId: bootstrap.organization.id,
      currentRevision: 1,
      state: RolloutState.draft,
      createdAt: now,
    );
    final target = RolloutTarget(
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
      platformId: 'android',
      releaseId: 'release_api',
      runtimeReleaseId: 'runtime-release-api',
      patchId: 'patch_api',
      runtimePatchId: 'runtime-patch-api',
      artifactId: 'artifact_api',
      sha256: _digest('artifact-api'),
      sequence: 1,
    );
    rolloutRevision = RolloutRevision(
      id: 'rollout_revision_api',
      rolloutId: rollout.id,
      organizationId: rollout.organizationId,
      revision: 1,
      previousRevision: null,
      state: RolloutState.draft,
      target: target,
      policy: RolloutPolicy(
        cohortKind: RolloutCohortKind.percentage,
        percentageBasisPoints: 10000,
        salt: 'salt-api',
      ),
      actorId: bootstrap.controlCredential.record.id,
      reason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
      pausedFromState: null,
      createdAt: now,
    );
    await controlStore.createJson('rollouts', rollout.id, rollout.toJson());
    await controlStore.createJson(
      'rollout_revisions',
      rolloutRevision.id,
      rolloutRevision.toJson(),
    );
    aggregate = _aggregate(
      organizationId: bootstrap.organization.id,
      applicationId: bootstrap.application.id,
      environmentId: bootstrap.environment.id,
    );
    aggregateRevision = HealthAggregateRevision(
      aggregateRevisionId: 'aggregate_revision_api',
      aggregateId: 'aggregate_api',
      parentAggregateRevisionId: null,
      identity: aggregate.identity,
      window: aggregate.window,
      aggregationVersion: 1,
      inputCount: aggregate.inputCount,
      inputDigest: aggregate.inputDigest,
      recomputationReason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
      recomputability: P3eRecomputability.rawRecomputable,
      createdAt: now,
    );
    await p3eStore.putAggregateRevision(
      HealthAggregateRecord(
        aggregateId: 'aggregate_api',
        revisionId: aggregateRevision.aggregateRevisionId,
        aggregate: aggregate,
        recomputability: P3eRecomputability.rawRecomputable,
        createdAt: now,
      ),
      aggregateRevision,
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
    await p3eDirectory.delete(recursive: true);
  });

  test('manual evaluation persists evidence, reads, lists, and replays idempotently', () async {
    final request = _request(aggregate, aggregateRevision);
    final first = await service.evaluateHealth(
      token: bootstrap.controlCredential.token,
      rolloutId: rollout.id,
      request: request,
      idempotencyKey: 'health-eval-1',
    );
    expect(first.idempotentReplay, isFalse);
    expect(first.evaluation.decision, 'CONTINUE');
    expect(first.evaluation.evaluationInputDigest, isNotNull);
    expect(first.decision.resultingTransitionReference, isNull);
    final rolloutAfterEvaluation = await service.readRollout(
      token: bootstrap.controlCredential.token,
      rolloutId: rollout.id,
      organizationId: bootstrap.organization.id,
    );
    expect(rolloutAfterEvaluation.rollout.currentRevision, 1);
    expect(rolloutAfterEvaluation.revision.state, RolloutState.draft);

    final replay = await service.evaluateHealth(
      token: bootstrap.controlCredential.token,
      rolloutId: rollout.id,
      request: request,
      idempotencyKey: 'health-eval-1',
    );
    expect(replay.idempotentReplay, isTrue);
    expect(
      replay.evaluation.canonicalSerialization,
      first.evaluation.canonicalSerialization,
    );
    expect(
      replay.decision.canonicalSerialization,
      first.decision.canonicalSerialization,
    );

    final read = await service.readHealthEvaluation(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
      rolloutId: rollout.id,
      evaluationId: first.evaluation.evaluationId,
    );
    expect(read.evaluation.evaluationId, first.evaluation.evaluationId);
    final page = await service.listHealthEvaluations(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
      rolloutId: rollout.id,
      pageSize: 1,
    );
    expect(page.items, hasLength(1));
    expect(page.nextCursor, isNull);
    expect(
      (await service.readAudit(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
      )).map((record) => record.action),
      containsAll(<String>[
        'health.evaluation_requested',
        'health.evaluation_created',
        'health.evaluation_replayed',
      ]),
    );
  });

  test(
    'same idempotency key with changed request is immutable conflict',
    () async {
      final request = _request(aggregate, aggregateRevision);
      await service.evaluateHealth(
        token: bootstrap.controlCredential.token,
        rolloutId: rollout.id,
        request: request,
        idempotencyKey: 'health-eval-conflict',
      );
      final changed = _request(
        aggregate,
        aggregateRevision,
        maximumQuarantineRateBasisPoints: 0,
      );
      await expectLater(
        service.evaluateHealth(
          token: bootstrap.controlCredential.token,
          rolloutId: rollout.id,
          request: changed,
          idempotencyKey: 'health-eval-conflict',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'HEALTH_EVALUATION_CONFLICT',
          ),
        ),
      );
    },
  );

  test(
    'scope, stale rollout, malformed evidence, and missing policy fail closed',
    () async {
      final request = _request(aggregate, aggregateRevision);
      final wrongScope = ManualEvaluationRequest(
        organizationId: request.organizationId,
        applicationId: request.applicationId,
        environmentId: request.environmentId,
        platformId: request.platformId,
        rolloutId: request.rolloutId,
        rolloutRevision: request.rolloutRevision,
        aggregationVersion: request.aggregationVersion,
        aggregateId: request.aggregateId,
        aggregateRevisionId: request.aggregateRevisionId,
        releaseId: 'release_other',
        patchId: request.patchId,
        sequence: request.sequence,
        windowId: request.windowId,
        aggregateInputDigest: request.aggregateInputDigest,
        aggregatePolicyDigest: request.aggregatePolicyDigest,
        policyDigest: request.policyDigest,
        policy: request.policy,
      );
      await expectLater(
        service.evaluateHealth(
          token: bootstrap.controlCredential.token,
          rolloutId: rollout.id,
          request: wrongScope,
          idempotencyKey: 'health-wrong-scope',
        ),
        throwsA(isA<ControlPlaneException>()),
      );

      final stale = ManualEvaluationRequest(
        organizationId: request.organizationId,
        applicationId: request.applicationId,
        environmentId: request.environmentId,
        platformId: request.platformId,
        rolloutId: request.rolloutId,
        rolloutRevision: 2,
        aggregationVersion: request.aggregationVersion,
        aggregateId: request.aggregateId,
        aggregateRevisionId: request.aggregateRevisionId,
        releaseId: request.releaseId,
        patchId: request.patchId,
        sequence: request.sequence,
        windowId: request.windowId,
        aggregateInputDigest: request.aggregateInputDigest,
        aggregatePolicyDigest: request.aggregatePolicyDigest,
        policyDigest: request.policyDigest,
        policy: request.policy,
      );
      await expectLater(
        service.evaluateHealth(
          token: bootstrap.controlCredential.token,
          rolloutId: rollout.id,
          request: stale,
          idempotencyKey: 'health-stale',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'HEALTH_AGGREGATE_STALE',
          ),
        ),
      );

      final malformed = ManualEvaluationRequest(
        organizationId: request.organizationId,
        applicationId: request.applicationId,
        environmentId: request.environmentId,
        platformId: request.platformId,
        rolloutId: request.rolloutId,
        rolloutRevision: request.rolloutRevision,
        aggregationVersion: request.aggregationVersion,
        aggregateId: request.aggregateId,
        aggregateRevisionId: request.aggregateRevisionId,
        releaseId: request.releaseId,
        patchId: request.patchId,
        sequence: request.sequence,
        windowId: request.windowId,
        aggregateInputDigest: _digest('wrong-input'),
        aggregatePolicyDigest: request.aggregatePolicyDigest,
        policyDigest: request.policyDigest,
        policy: request.policy,
      );
      await expectLater(
        service.evaluateHealth(
          token: bootstrap.controlCredential.token,
          rolloutId: rollout.id,
          request: malformed,
          idempotencyKey: 'health-malformed',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'HEALTH_SCOPE_MISMATCH',
          ),
        ),
      );

      final actions = (await service.readAudit(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
      )).map((record) => record.action);
      expect(
        actions,
        containsAll(<String>[
          'health.evaluation_stale_rejected',
          'health.evaluation_evidence_rejected',
        ]),
      );

      final restricted = await service.issueCredential(
        token: bootstrap.controlCredential.token,
        organizationId: bootstrap.organization.id,
        kind: CredentialKind.control,
        scopes: const <String>{'health:evaluate', 'rollout:read'},
      );
      await expectLater(
        service.evaluateHealth(
          token: restricted.token,
          rolloutId: rollout.id,
          request: request,
          idempotencyKey: 'health-restricted',
        ),
        throwsA(
          isA<ControlPlaneException>().having(
            (error) => error.code,
            'code',
            'FORBIDDEN',
          ),
        ),
      );
    },
  );

  test('HTTP POST/GET/list routes are versioned and tenant-scoped', () async {
    final server = await ControlPlaneHttpServer(service).bind();
    addTearDown(() => server.close(force: true));
    final body = _apiBody(_request(aggregate, aggregateRevision));
    final client = HttpClient();
    try {
      final post = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/v1/rollouts/${rollout.id}/health/evaluations',
        ),
      );
      final bytes = utf8.encode(jsonEncode(body));
      post
        ..headers.contentType = ContentType.json
        ..headers.set(
          'Authorization',
          'Bearer ${bootstrap.controlCredential.token}',
        )
        ..headers.set('Idempotency-Key', 'http-health-eval')
        ..contentLength = bytes.length;
      post.add(bytes);
      final response = await post.close();
      final decoded = jsonDecode(await response.transform(utf8.decoder).join());
      expect(response.statusCode, 201, reason: jsonEncode(decoded));
      final evaluationId =
          ((decoded as Map)['evaluation'] as Map)['evaluationId'];

      final read = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/v1/rollouts/${rollout.id}/health/evaluations/$evaluationId?organization_id=${bootstrap.organization.id}',
        ),
      );
      read.headers.set(
        'Authorization',
        'Bearer ${bootstrap.controlCredential.token}',
      );
      expect((await read.close()).statusCode, 200);

      final list = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/v1/rollouts/${rollout.id}/health/evaluations?organization_id=${bootstrap.organization.id}&page_size=1',
        ),
      );
      list.headers.set(
        'Authorization',
        'Bearer ${bootstrap.controlCredential.token}',
      );
      final listResponse = await list.close();
      expect(listResponse.statusCode, 200);

      final foreign = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/v1/rollouts/${rollout.id}/health/evaluations',
        ),
      );
      final foreignBody = <String, Object?>{
        ...body,
        'organization_id': 'org_foreign',
      };
      final foreignBytes = utf8.encode(jsonEncode(foreignBody));
      foreign
        ..headers.contentType = ContentType.json
        ..headers.set(
          'Authorization',
          'Bearer ${bootstrap.controlCredential.token}',
        )
        ..headers.set('Idempotency-Key', 'http-health-foreign')
        ..contentLength = foreignBytes.length;
      foreign.add(foreignBytes);
      expect((await foreign.close()).statusCode, 404);
    } finally {
      client.close(force: true);
    }
  });

  test(
    'P3E-4 applies HALT_NEW_OFFERS through rollout CAS and preserves linkage',
    () async {
      final vector = await _haltVector(
        bootstrap: bootstrap,
        controlStore: controlStore,
        p3eStore: p3eStore,
      );
      final first = await service.applyHealthHalt(
        token: bootstrap.controlCredential.token,
        rolloutId: vector.rollout.id,
        decisionId: vector.decision.decisionId,
        expectedRolloutRevision: vector.decision.expectedRolloutRevision,
        targetBindingDigest: vector.targetBindingDigest,
        evaluationInputDigest: vector.evaluation.evaluationInputDigest!,
        aggregateInputDigest: vector.aggregateRevision.inputDigest,
        aggregateDigest: vector.aggregateDigest,
        operatorReason: 'activation failures exceeded the reviewed threshold',
        idempotencyKey: 'health-halt-1',
      );
      expect(first.result, 'APPLIED');
      expect(first.resultingRolloutRevision, 2);
      final halted = await service.readRollout(
        token: bootstrap.controlCredential.token,
        rolloutId: vector.rollout.id,
        organizationId: bootstrap.organization.id,
      );
      expect(halted.revision.state, RolloutState.halted);
      expect(
        RolloutEligibility.isEligible(
          revision: halted.revision,
          installationId: 'installation-a',
        ),
        isFalse,
      );

      final replay = await service.applyHealthHalt(
        token: bootstrap.controlCredential.token,
        rolloutId: vector.rollout.id,
        decisionId: vector.decision.decisionId,
        expectedRolloutRevision: vector.decision.expectedRolloutRevision,
        targetBindingDigest: vector.targetBindingDigest,
        evaluationInputDigest: vector.evaluation.evaluationInputDigest!,
        aggregateInputDigest: vector.aggregateRevision.inputDigest,
        aggregateDigest: vector.aggregateDigest,
        operatorReason: 'activation failures exceeded the reviewed threshold',
        idempotencyKey: 'health-halt-1',
      );
      expect(replay.canonicalSerialization, first.canonicalSerialization);

      final secondKey = await service.applyHealthHalt(
        token: bootstrap.controlCredential.token,
        rolloutId: vector.rollout.id,
        decisionId: vector.decision.decisionId,
        expectedRolloutRevision: vector.decision.expectedRolloutRevision,
        targetBindingDigest: vector.targetBindingDigest,
        evaluationInputDigest: vector.evaluation.evaluationInputDigest!,
        aggregateInputDigest: vector.aggregateRevision.inputDigest,
        aggregateDigest: vector.aggregateDigest,
        operatorReason: 'same reviewed halt decision',
        idempotencyKey: 'health-halt-2',
      );
      expect(secondKey.result, 'ALREADY_APPLIED');
      expect(secondKey.resultingRolloutRevision, 2);
      expect(
        (await p3eStore.listHaltApplications(bootstrap.organization.id)),
        hasLength(2),
      );
      expect(
        (await service.readAudit(
          token: bootstrap.controlCredential.token,
          organizationId: bootstrap.organization.id,
        )).map((record) => record.action),
        containsAll(<String>[
          'health.halt.requested',
          'health.halt.applied',
          'health.halt.replayed',
          'health.halt.already_applied',
        ]),
      );
    },
  );

  test('P3E-4 concurrent equal halt requests converge idempotently', () async {
    final vector = await _haltVector(
      bootstrap: bootstrap,
      controlStore: controlStore,
      p3eStore: p3eStore,
    );
    Future<HealthHaltApplication> apply() => service.applyHealthHalt(
      token: bootstrap.controlCredential.token,
      rolloutId: vector.rollout.id,
      decisionId: vector.decision.decisionId,
      expectedRolloutRevision: vector.decision.expectedRolloutRevision,
      targetBindingDigest: vector.targetBindingDigest,
      evaluationInputDigest: vector.evaluation.evaluationInputDigest!,
      aggregateInputDigest: vector.aggregateRevision.inputDigest,
      aggregateDigest: vector.aggregateDigest,
      operatorReason: 'concurrent equal reviewed halt request',
      idempotencyKey: 'health-halt-concurrent-equal',
    );

    final outcomes = await Future.wait(<Future<HealthHaltApplication>>[
      apply(),
      apply(),
    ]);
    expect(outcomes, hasLength(2));
    expect(
      outcomes.map((outcome) => outcome.result),
      everyElement(isIn(<String>{'APPLIED', 'ALREADY_APPLIED'})),
    );
    expect(
      outcomes.map((outcome) => outcome.applicationId).toSet(),
      hasLength(1),
    );
    expect(
      await p3eStore.listHaltApplications(bootstrap.organization.id),
      hasLength(1),
    );
    final snapshot = await service.readRollout(
      token: bootstrap.controlCredential.token,
      rolloutId: vector.rollout.id,
      organizationId: bootstrap.organization.id,
    );
    expect(snapshot.history, hasLength(2));
    expect(snapshot.revision.state, RolloutState.halted);
  });

  test('P3E-4 rejects mismatched evidence and records no transition', () async {
    final vector = await _haltVector(
      bootstrap: bootstrap,
      controlStore: controlStore,
      p3eStore: p3eStore,
    );
    await expectLater(
      service.applyHealthHalt(
        token: bootstrap.controlCredential.token,
        rolloutId: vector.rollout.id,
        decisionId: vector.decision.decisionId,
        expectedRolloutRevision: 1,
        targetBindingDigest: vector.targetBindingDigest,
        evaluationInputDigest: _digest('tampered-evaluation'),
        aggregateInputDigest: vector.aggregateRevision.inputDigest,
        aggregateDigest: vector.aggregateDigest,
        operatorReason: 'tampered evidence must fail closed',
        idempotencyKey: 'health-halt-tampered',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'HEALTH_EVIDENCE_INVALID',
        ),
      ),
    );
    final snapshot = await service.readRollout(
      token: bootstrap.controlCredential.token,
      rolloutId: vector.rollout.id,
      organizationId: bootstrap.organization.id,
    );
    expect(snapshot.revision.state, RolloutState.canary);
    final applications = await p3eStore.listHaltApplications(
      bootstrap.organization.id,
    );
    expect(applications.single.result, 'EVIDENCE_REJECTED');
  });

  test('P3E-4 malformed persisted decision fails closed', () async {
    final vector = await _haltVector(
      bootstrap: bootstrap,
      controlStore: controlStore,
      p3eStore: p3eStore,
    );
    final tenantKey = sha256
        .convert(utf8.encode(bootstrap.organization.id))
        .toString();
    final decisionKey = sha256
        .convert(utf8.encode(vector.decision.decisionId))
        .toString();
    final decisionFile = File(
      p.join(
        p3eDirectory.path,
        'p3e',
        'decisions',
        tenantKey,
        '$decisionKey.json',
      ),
    );
    await decisionFile.writeAsString('{}', flush: true);
    await expectLater(
      service.applyHealthHalt(
        token: bootstrap.controlCredential.token,
        rolloutId: vector.rollout.id,
        decisionId: vector.decision.decisionId,
        expectedRolloutRevision: 1,
        targetBindingDigest: vector.targetBindingDigest,
        evaluationInputDigest: vector.evaluation.evaluationInputDigest!,
        aggregateInputDigest: vector.aggregateRevision.inputDigest,
        aggregateDigest: vector.aggregateDigest,
        operatorReason: 'malformed persisted evidence',
        idempotencyKey: 'health-halt-malformed-storage',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'HEALTH_EVIDENCE_INVALID',
        ),
      ),
    );
    final snapshot = await service.readRollout(
      token: bootstrap.controlCredential.token,
      rolloutId: vector.rollout.id,
      organizationId: bootstrap.organization.id,
    );
    expect(snapshot.revision.state, RolloutState.canary);
  });

  test('P3E-4 never maps HOLD to a pause transition', () async {
    final vector = await _haltVector(
      bootstrap: bootstrap,
      controlStore: controlStore,
      p3eStore: p3eStore,
      decisionValue: 'HOLD',
    );
    await expectLater(
      service.applyHealthHalt(
        token: bootstrap.controlCredential.token,
        rolloutId: vector.rollout.id,
        decisionId: vector.decision.decisionId,
        expectedRolloutRevision: 1,
        targetBindingDigest: vector.targetBindingDigest,
        evaluationInputDigest: vector.evaluation.evaluationInputDigest!,
        aggregateInputDigest: vector.aggregateRevision.inputDigest,
        aggregateDigest: vector.aggregateDigest,
        operatorReason: 'HOLD must not mutate rollout state',
        idempotencyKey: 'health-hold-not-halt',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'HEALTH_DECISION_NOT_APPLICABLE',
        ),
      ),
    );
    final snapshot = await service.readRollout(
      token: bootstrap.controlCredential.token,
      rolloutId: vector.rollout.id,
      organizationId: bootstrap.organization.id,
    );
    expect(snapshot.revision.state, RolloutState.canary);
    expect(
      (await p3eStore.listHaltApplications(bootstrap.organization.id))
          .single
          .result,
      'REJECTED',
    );
  });

  test('P3E-4 changed idempotency body is a conflict', () async {
    final vector = await _haltVector(
      bootstrap: bootstrap,
      controlStore: controlStore,
      p3eStore: p3eStore,
    );
    final arguments = <String, Object?>{
      'token': bootstrap.controlCredential.token,
      'rolloutId': vector.rollout.id,
      'decisionId': vector.decision.decisionId,
      'expectedRolloutRevision': 1,
      'targetBindingDigest': vector.targetBindingDigest,
      'evaluationInputDigest': vector.evaluation.evaluationInputDigest!,
      'aggregateInputDigest': vector.aggregateRevision.inputDigest,
      'aggregateDigest': vector.aggregateDigest,
      'operatorReason': 'original reason',
      'idempotencyKey': 'health-halt-conflict',
    };
    await service.applyHealthHalt(
      token: arguments['token']! as String,
      rolloutId: arguments['rolloutId']! as String,
      decisionId: arguments['decisionId']! as String,
      expectedRolloutRevision: arguments['expectedRolloutRevision']! as int,
      targetBindingDigest: arguments['targetBindingDigest']! as String,
      evaluationInputDigest: arguments['evaluationInputDigest']! as String,
      aggregateInputDigest: arguments['aggregateInputDigest']! as String,
      aggregateDigest: arguments['aggregateDigest']! as String,
      operatorReason: arguments['operatorReason']! as String,
      idempotencyKey: arguments['idempotencyKey']! as String,
    );
    await expectLater(
      service.applyHealthHalt(
        token: bootstrap.controlCredential.token,
        rolloutId: vector.rollout.id,
        decisionId: vector.decision.decisionId,
        expectedRolloutRevision: 1,
        targetBindingDigest: vector.targetBindingDigest,
        evaluationInputDigest: vector.evaluation.evaluationInputDigest!,
        aggregateInputDigest: vector.aggregateRevision.inputDigest,
        aggregateDigest: vector.aggregateDigest,
        operatorReason: 'changed reason',
        idempotencyKey: 'health-halt-conflict',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'HEALTH_HALT_CONFLICT',
        ),
      ),
    );
  });

  test('P3E-4 requires the halt mutation scope', () async {
    final vector = await _haltVector(
      bootstrap: bootstrap,
      controlStore: controlStore,
      p3eStore: p3eStore,
    );
    final restricted = await service.issueCredential(
      token: bootstrap.controlCredential.token,
      organizationId: bootstrap.organization.id,
      kind: CredentialKind.control,
      scopes: const <String>{'health:evaluate', 'rollout:read'},
    );
    await expectLater(
      service.applyHealthHalt(
        token: restricted.token,
        rolloutId: vector.rollout.id,
        decisionId: vector.decision.decisionId,
        expectedRolloutRevision: 1,
        targetBindingDigest: vector.targetBindingDigest,
        evaluationInputDigest: vector.evaluation.evaluationInputDigest!,
        aggregateInputDigest: vector.aggregateRevision.inputDigest,
        aggregateDigest: vector.aggregateDigest,
        operatorReason: 'scope test',
        idempotencyKey: 'health-halt-forbidden',
      ),
      throwsA(
        isA<ControlPlaneException>().having(
          (error) => error.code,
          'code',
          'FORBIDDEN',
        ),
      ),
    );
  });

  test('P3E-4 HTTP route applies only the bounded halt decision', () async {
    final vector = await _haltVector(
      bootstrap: bootstrap,
      controlStore: controlStore,
      p3eStore: p3eStore,
    );
    final server = await ControlPlaneHttpServer(service).bind();
    addTearDown(() => server.close(force: true));
    final client = HttpClient();
    try {
      final body = <String, Object?>{
        'expected_rollout_revision': 1,
        'target_binding_digest': vector.targetBindingDigest,
        'evaluation_input_digest': vector.evaluation.evaluationInputDigest,
        'aggregate_input_digest': vector.aggregateRevision.inputDigest,
        'aggregate_digest': vector.aggregateDigest,
        'operator_reason': 'bounded HTTP halt test',
      };
      final request = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/v1/rollouts/${vector.rollout.id}/health/decisions/${vector.decision.decisionId}/apply',
        ),
      );
      final bytes = utf8.encode(jsonEncode(body));
      request
        ..headers.contentType = ContentType.json
        ..headers.set(
          'Authorization',
          'Bearer ${bootstrap.controlCredential.token}',
        )
        ..headers.set('Idempotency-Key', 'health-halt-http')
        ..contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      final decoded =
          jsonDecode(await response.transform(utf8.decoder).join()) as Map;
      expect(response.statusCode, 201, reason: jsonEncode(decoded));
      expect(decoded['result'], 'APPLIED');
    } finally {
      client.close(force: true);
    }
  });

  test('P3E-4 health halt races with manual halt safely', () async {
    final vector = await _haltVector(
      bootstrap: bootstrap,
      controlStore: controlStore,
      p3eStore: p3eStore,
    );
    Future<Object> capture(Future<Object> operation) async {
      try {
        return await operation;
      } on Object catch (error) {
        return error;
      }
    }

    final results = await Future.wait(<Future<Object>>[
      capture(
        service.applyHealthHalt(
          token: bootstrap.controlCredential.token,
          rolloutId: vector.rollout.id,
          decisionId: vector.decision.decisionId,
          expectedRolloutRevision: 1,
          targetBindingDigest: vector.targetBindingDigest,
          evaluationInputDigest: vector.evaluation.evaluationInputDigest!,
          aggregateInputDigest: vector.aggregateRevision.inputDigest,
          aggregateDigest: vector.aggregateDigest,
          operatorReason: 'race with manual halt',
          idempotencyKey: 'health-halt-race',
        ),
      ),
      capture(
        service.transitionRollout(
          token: bootstrap.controlCredential.token,
          rolloutId: vector.rollout.id,
          action: RolloutAction.halt,
          expectedRevision: 1,
          reason: 'manual operator halt race',
          idempotencyKey: 'manual-halt-race',
        ),
      ),
    ]);
    expect(results, hasLength(2));
    final snapshot = await service.readRollout(
      token: bootstrap.controlCredential.token,
      rolloutId: vector.rollout.id,
      organizationId: bootstrap.organization.id,
    );
    expect(snapshot.revision.state, RolloutState.halted);
    expect(snapshot.history, hasLength(2));
    final applications = await p3eStore.listHaltApplications(
      bootstrap.organization.id,
    );
    expect(applications, hasLength(1));
    expect(applications.single.result, anyOf('APPLIED', 'STALE'));
  });

  test('P3E-4 health halt races with expansion safely', () async {
    final vector = await _haltVector(
      bootstrap: bootstrap,
      controlStore: controlStore,
      p3eStore: p3eStore,
      percentageBasisPoints: 1000,
    );
    Future<Object> capture(Future<Object> operation) async {
      try {
        return await operation;
      } on Object catch (error) {
        return error;
      }
    }

    final results = await Future.wait(<Future<Object>>[
      capture(
        service.applyHealthHalt(
          token: bootstrap.controlCredential.token,
          rolloutId: vector.rollout.id,
          decisionId: vector.decision.decisionId,
          expectedRolloutRevision: 1,
          targetBindingDigest: vector.targetBindingDigest,
          evaluationInputDigest: vector.evaluation.evaluationInputDigest!,
          aggregateInputDigest: vector.aggregateRevision.inputDigest,
          aggregateDigest: vector.aggregateDigest,
          operatorReason: 'race with expansion',
          idempotencyKey: 'health-halt-expansion-race',
        ),
      ),
      capture(
        service.transitionRollout(
          token: bootstrap.controlCredential.token,
          rolloutId: vector.rollout.id,
          action: RolloutAction.expand,
          expectedRevision: 1,
          percentageBasisPoints: 2000,
          reason: 'manual expansion race',
          idempotencyKey: 'manual-expansion-race',
        ),
      ),
    ]);
    expect(results, hasLength(2));
    final snapshot = await service.readRollout(
      token: bootstrap.controlCredential.token,
      rolloutId: vector.rollout.id,
      organizationId: bootstrap.organization.id,
    );
    expect(snapshot.history, hasLength(2));
    expect(
      snapshot.revision.state,
      anyOf(RolloutState.halted, RolloutState.expanding),
    );
    final applications = await p3eStore.listHaltApplications(
      bootstrap.organization.id,
    );
    expect(applications, hasLength(1));
    expect(applications.single.result, anyOf('APPLIED', 'STALE'));
  });

  final postgresUrl = Platform.environment['HYFENS_TEST_POSTGRES_URL'];
  test(
    'two PostgreSQL services converge on one conservative health halt',
    () async {
      final firstControl = PostgresControlPlaneStore(postgresUrl!);
      final firstP3e = PostgresP3ePersistenceStore(postgresUrl);
      final first = ControlPlaneService(
        store: firstControl,
        p3eStore: firstP3e,
      );
      final firstBootstrap = await first.bootstrap(
        organizationName: 'P3E-4 PostgreSQL organization',
        runtimeApplicationId: 'com.example.p3e.halt.pg',
        platformId: 'android',
        environmentName: 'development',
      );
      final vector = await _haltVector(
        bootstrap: firstBootstrap,
        controlStore: firstControl,
        p3eStore: firstP3e,
      );
      final secondControl = PostgresControlPlaneStore(postgresUrl);
      final secondP3e = PostgresP3ePersistenceStore(postgresUrl);
      final second = ControlPlaneService(
        store: secondControl,
        p3eStore: secondP3e,
      );
      await second.initialize();
      addTearDown(() async {
        await firstControl.close();
        await firstP3e.close();
        await secondControl.close();
        await secondP3e.close();
      });
      final results = await Future.wait(<Future<HealthHaltApplication>>[
        first.applyHealthHalt(
          token: firstBootstrap.controlCredential.token,
          rolloutId: vector.rollout.id,
          decisionId: vector.decision.decisionId,
          expectedRolloutRevision: 1,
          targetBindingDigest: vector.targetBindingDigest,
          evaluationInputDigest: vector.evaluation.evaluationInputDigest!,
          aggregateInputDigest: vector.aggregateRevision.inputDigest,
          aggregateDigest: vector.aggregateDigest,
          operatorReason: 'two-instance health halt',
          idempotencyKey:
              'pg-health-halt-a-${firstBootstrap.organization.id.substring(4, 12)}',
        ),
        second.applyHealthHalt(
          token: firstBootstrap.controlCredential.token,
          rolloutId: vector.rollout.id,
          decisionId: vector.decision.decisionId,
          expectedRolloutRevision: 1,
          targetBindingDigest: vector.targetBindingDigest,
          evaluationInputDigest: vector.evaluation.evaluationInputDigest!,
          aggregateInputDigest: vector.aggregateRevision.inputDigest,
          aggregateDigest: vector.aggregateDigest,
          operatorReason: 'two-instance health halt',
          idempotencyKey:
              'pg-health-halt-b-${firstBootstrap.organization.id.substring(4, 12)}',
        ),
      ]);
      expect(
        results.map((item) => item.result),
        containsAll(<String>['APPLIED', 'ALREADY_APPLIED']),
      );
      final applications = await firstP3e.listHaltApplications(
        firstBootstrap.organization.id,
      );
      expect(applications, hasLength(2));
      final snapshot = await first.readRollout(
        token: firstBootstrap.controlCredential.token,
        rolloutId: vector.rollout.id,
        organizationId: firstBootstrap.organization.id,
      );
      expect(snapshot.revision.state, RolloutState.halted);
      expect(snapshot.revision.revision, 2);
    },
    skip: postgresUrl == null || postgresUrl.isEmpty
        ? 'PostgreSQL integration environment is not configured'
        : null,
  );
  test(
    'two PostgreSQL-backed services converge on one idempotent evaluation',
    () async {
      final controlDirectory = await Directory.systemTemp.createTemp(
        'hyfens-p3e-api-pg-control-',
      );
      final first = await _postgresFixture(postgresUrl!, controlDirectory);
      final secondP3e = PostgresP3ePersistenceStore(postgresUrl);
      final second = ControlPlaneService(
        store: FileControlPlaneStore(controlDirectory),
        p3eStore: secondP3e,
      );
      await second.initialize();
      addTearDown(() async {
        await first.p3e.close();
        await secondP3e.close();
        await controlDirectory.delete(recursive: true);
      });
      final results = await Future.wait(<Future<ManualEvaluationSnapshot>>[
        first.service.evaluateHealth(
          token: first.bootstrap.controlCredential.token,
          rolloutId: first.rollout.id,
          request: first.request,
          idempotencyKey: 'postgres-health-eval',
        ),
        second.evaluateHealth(
          token: first.bootstrap.controlCredential.token,
          rolloutId: first.rollout.id,
          request: first.request,
          idempotencyKey: 'postgres-health-eval',
        ),
      ]);
      expect(results, hasLength(2));
      expect(
        results.map((result) => result.evaluation.evaluationId).toSet(),
        hasLength(1),
      );
      expect(
        results.map((result) => result.decision.canonicalSerialization).toSet(),
        hasLength(1),
      );
    },
    skip: postgresUrl == null || postgresUrl.isEmpty
        ? 'PostgreSQL integration environment is not configured'
        : null,
  );
}

final class _PostgresFixture {
  _PostgresFixture({
    required this.service,
    required this.p3e,
    required this.bootstrap,
    required this.rollout,
    required this.request,
  });

  final ControlPlaneService service;
  final PostgresP3ePersistenceStore p3e;
  final BootstrapResult bootstrap;
  final RolloutRecord rollout;
  final ManualEvaluationRequest request;
}

Future<_PostgresFixture> _postgresFixture(
  String postgresUrl,
  Directory controlDirectory,
) async {
  final p3e = PostgresP3ePersistenceStore(postgresUrl);
  final control = FileControlPlaneStore(controlDirectory);
  final service = ControlPlaneService(store: control, p3eStore: p3e);
  final bootstrap = await service.bootstrap(
    organizationName: 'P3E PostgreSQL organization',
    runtimeApplicationId: 'com.example.p3e.pg',
    platformId: 'android',
    environmentName: 'development',
  );
  final now = DateTime.utc(2026, 8, 24, 14);
  final rollout = RolloutRecord(
    id: 'rollout_api',
    organizationId: bootstrap.organization.id,
    currentRevision: 1,
    state: RolloutState.draft,
    createdAt: now,
  );
  final target = RolloutTarget(
    organizationId: bootstrap.organization.id,
    applicationId: bootstrap.application.id,
    environmentId: bootstrap.environment.id,
    platformId: 'android',
    releaseId: 'release_api',
    runtimeReleaseId: 'runtime_release_api',
    patchId: 'patch_api',
    runtimePatchId: 'runtime_patch_api',
    artifactId: 'artifact_api',
    sha256: _digest('artifact-api'),
    sequence: 1,
  );
  final rolloutRevision = RolloutRevision(
    id: 'rollout_revision_api',
    rolloutId: rollout.id,
    organizationId: rollout.organizationId,
    revision: 1,
    previousRevision: null,
    state: RolloutState.draft,
    target: target,
    policy: RolloutPolicy(
      cohortKind: RolloutCohortKind.percentage,
      percentageBasisPoints: 10000,
      salt: 'salt_api',
    ),
    actorId: bootstrap.controlCredential.record.id,
    reason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
    pausedFromState: null,
    createdAt: now,
  );
  await control.createJson('rollouts', rollout.id, rollout.toJson());
  await control.createJson(
    'rollout_revisions',
    rolloutRevision.id,
    rolloutRevision.toJson(),
  );
  final aggregate = _aggregate(
    organizationId: bootstrap.organization.id,
    applicationId: bootstrap.application.id,
    environmentId: bootstrap.environment.id,
  );
  final revision = HealthAggregateRevision(
    aggregateRevisionId: 'aggregate_revision_api',
    aggregateId: 'aggregate_api',
    parentAggregateRevisionId: null,
    identity: aggregate.identity,
    window: aggregate.window,
    aggregationVersion: 1,
    inputCount: aggregate.inputCount,
    inputDigest: aggregate.inputDigest,
    recomputationReason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
    recomputability: P3eRecomputability.rawRecomputable,
    createdAt: now,
  );
  await p3e.putAggregateRevision(
    HealthAggregateRecord(
      aggregateId: 'aggregate_api',
      revisionId: revision.aggregateRevisionId,
      aggregate: aggregate,
      recomputability: P3eRecomputability.rawRecomputable,
      createdAt: now,
    ),
    revision,
  );
  return _PostgresFixture(
    service: service,
    p3e: p3e,
    bootstrap: bootstrap,
    rollout: rollout,
    request: _request(aggregate, revision),
  );
}

final class _HaltVector {
  _HaltVector({
    required this.rollout,
    required this.aggregate,
    required this.aggregateRevision,
    required this.evaluation,
    required this.decision,
    required this.targetBindingDigest,
  });

  final RolloutRecord rollout;
  final HealthAggregate aggregate;
  final HealthAggregateRevision aggregateRevision;
  final HealthEvaluation evaluation;
  final RolloutDecisionRecord decision;
  final String targetBindingDigest;

  String get aggregateDigest =>
      sha256Digest(utf8.encode(aggregate.canonicalSerialization));
}

Future<_HaltVector> _haltVector({
  required BootstrapResult bootstrap,
  required ControlPlaneStore controlStore,
  required P3ePersistenceStore p3eStore,
  String decisionValue = 'HALT_NEW_OFFERS',
  int percentageBasisPoints = 10000,
}) async {
  final now = DateTime.utc(2026, 8, 24, 14);
  final suffix = bootstrap.organization.id.substring(4, 12);
  final rolloutId = 'rollout_halt_$suffix';
  final rolloutRevisionId = 'rollout_revision_halt_$suffix';
  final evaluationId = 'evaluation_halt_$suffix';
  final decisionId = 'decision_halt_$suffix';
  final rollout = RolloutRecord(
    id: rolloutId,
    organizationId: bootstrap.organization.id,
    currentRevision: 1,
    state: RolloutState.canary,
    createdAt: now,
  );
  final target = RolloutTarget(
    organizationId: bootstrap.organization.id,
    applicationId: bootstrap.application.id,
    environmentId: bootstrap.environment.id,
    platformId: 'android',
    releaseId: 'release_halt',
    runtimeReleaseId: 'runtime_release_halt',
    patchId: 'patch_halt',
    runtimePatchId: 'runtime_patch_halt',
    artifactId: 'artifact_halt',
    sha256: _digest('artifact-halt'),
    sequence: 1,
  );
  final rolloutRevision = RolloutRevision(
    id: rolloutRevisionId,
    rolloutId: rollout.id,
    organizationId: rollout.organizationId,
    revision: 1,
    previousRevision: null,
    state: RolloutState.canary,
    target: target,
    policy: RolloutPolicy(
      cohortKind: RolloutCohortKind.percentage,
      percentageBasisPoints: percentageBasisPoints,
      salt: 'salt-halt',
    ),
    actorId: bootstrap.controlCredential.record.id,
    reason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
    pausedFromState: null,
    createdAt: now,
  );
  await controlStore.createJson('rollouts', rollout.id, rollout.toJson());
  await controlStore.createJson(
    'rollout_revisions',
    rolloutRevision.id,
    rolloutRevision.toJson(),
  );
  final aggregate = _aggregate(
    organizationId: bootstrap.organization.id,
    applicationId: bootstrap.application.id,
    environmentId: bootstrap.environment.id,
    rolloutId: rollout.id,
    releaseId: 'release_halt',
    patchId: 'patch_halt',
  );
  final aggregateRevision = HealthAggregateRevision(
    aggregateRevisionId: 'aggregate_revision_halt',
    aggregateId: 'aggregate_halt',
    parentAggregateRevisionId: null,
    identity: aggregate.identity,
    window: aggregate.window,
    aggregationVersion: 1,
    inputCount: aggregate.inputCount,
    inputDigest: aggregate.inputDigest,
    recomputationReason: 'TEST VECTOR ONLY — NOT PRODUCTION POLICY',
    recomputability: P3eRecomputability.rawRecomputable,
    createdAt: now,
  );
  await p3eStore.putAggregateRevision(
    HealthAggregateRecord(
      aggregateId: 'aggregate_halt',
      revisionId: aggregateRevision.aggregateRevisionId,
      aggregate: aggregate,
      recomputability: P3eRecomputability.rawRecomputable,
      createdAt: now,
    ),
    aggregateRevision,
  );
  final evaluation = HealthEvaluation(
    evaluationId: evaluationId,
    organizationId: bootstrap.organization.id,
    aggregateRevisionId: aggregateRevision.aggregateRevisionId,
    rolloutId: rollout.id,
    rolloutRevision: 1,
    evaluationVersion: 1,
    policyVersion: 1,
    thresholdSetVersion: 1,
    windowPolicyVersion: 1,
    privacyPolicyVersion: 1,
    aggregateInputDigest: aggregateRevision.inputDigest,
    decision: decisionValue,
    reasonClass: 'PATCH_SAFETY',
    reasonCodes: const <String>['ACTIVATION_FAILURE_RATE_EXCEEDED'],
    coverageState: 'SUFFICIENT',
    freshnessState: 'FRESH',
    sampleState: 'PASSED',
    createdAt: now,
    auditReference: 'audit:health-halt-vector',
    evaluationInputDigest: _digest('evaluation-halt'),
    targetBindingDigest: sha256Digest(
      utf8.encode(canonicalJson(target.toJson())),
    ),
  );
  final decision = RolloutDecisionRecord(
    decisionId: decisionId,
    organizationId: bootstrap.organization.id,
    rolloutId: rollout.id,
    expectedRolloutRevision: 1,
    evaluationId: evaluation.evaluationId,
    aggregateRevisionId: aggregateRevision.aggregateRevisionId,
    decision: decisionValue,
    reason: 'ACTIVATION_FAILURE_RATE_EXCEEDED',
    actorIdentity: bootstrap.controlCredential.record.id,
    idempotencyKey: 'health-eval-halt-vector',
    createdAt: now,
    previousDecisionId: null,
    resultingTransitionReference: null,
  );
  await p3eStore.putEvaluation(evaluation);
  await p3eStore.putDecision(decision);
  return _HaltVector(
    rollout: rollout,
    aggregate: aggregate,
    aggregateRevision: aggregateRevision,
    evaluation: evaluation,
    decision: decision,
    targetBindingDigest: sha256Digest(
      utf8.encode(canonicalJson(target.toJson())),
    ),
  );
}

Map<String, Object?> _apiBody(ManualEvaluationRequest request) =>
    <String, Object?>{
      'organization_id': request.organizationId,
      'application_id': request.applicationId,
      'environment_id': request.environmentId,
      'platform_id': request.platformId,
      'rollout_revision': request.rolloutRevision,
      'aggregation_version': request.aggregationVersion,
      'aggregate_id': request.aggregateId,
      'aggregate_revision_id': request.aggregateRevisionId,
      'release_id': request.releaseId,
      'patch_id': request.patchId,
      'sequence': request.sequence,
      'window_id': request.windowId,
      'aggregate_input_digest': request.aggregateInputDigest,
      'aggregate_policy_digest': request.aggregatePolicyDigest,
      'policy_digest': request.policyDigest,
      'policy': request.policy.toJson(),
    };

ManualEvaluationRequest _request(
  HealthAggregate aggregate,
  HealthAggregateRevision revision, {
  int maximumQuarantineRateBasisPoints = 10000,
}) {
  final policy = ManualEvaluationPolicy(
    evaluationVersion: 1,
    policyVersion: 1,
    thresholdSetVersion: 1,
    windowPolicyVersion: 1,
    privacyPolicyVersion: 1,
    thresholdSetDigest: _digest('threshold-api'),
    minimumSamples: const AggregationMinimumSamples(
      minimumEligibleObserved: 1,
      minimumOffers: 1,
      minimumActivated: 1,
      minimumHealthyConfirmations: 1,
      minimumCoverageBasisPoints: 10000,
    ),
    requireFreshness: true,
    allowNonRecomputable: false,
    maximumQuarantineRateBasisPoints: maximumQuarantineRateBasisPoints,
    maximumRejectedRateBasisPoints: 10000,
    maximumLateRateBasisPoints: 10000,
    haltActivationFailureRateBasisPoints: null,
    haltAdmissionRejectionRateBasisPoints: null,
    haltRuntimeFaultRateBasisPoints: null,
    haltRollbackFallbackRateBasisPoints: null,
  );
  return ManualEvaluationRequest(
    organizationId: aggregate.identity.organizationId,
    applicationId: aggregate.identity.applicationId,
    environmentId: aggregate.identity.environmentId,
    platformId: aggregate.identity.platformId,
    rolloutId: aggregate.identity.rolloutId,
    rolloutRevision: aggregate.identity.rolloutRevision,
    aggregationVersion: aggregate.identity.aggregationVersion,
    aggregateId: 'aggregate_api',
    aggregateRevisionId: revision.aggregateRevisionId,
    releaseId: aggregate.identity.releaseId,
    patchId: aggregate.identity.patchId,
    sequence: aggregate.identity.sequence,
    windowId: aggregate.identity.windowId,
    aggregateInputDigest: revision.inputDigest,
    aggregatePolicyDigest: aggregate.policyDigest,
    policyDigest: policy.policyDigest,
    policy: policy,
  );
}

HealthAggregate _aggregate({
  required String organizationId,
  required String applicationId,
  required String environmentId,
  String rolloutId = 'rollout_api',
  String releaseId = 'release_api',
  String patchId = 'patch_api',
}) {
  final start = DateTime.utc(2026, 8, 24, 12);
  final window = ObservationWindow(
    windowId: 'window_api',
    serverStart: start,
    serverEnd: start.add(const Duration(hours: 1)),
    lateCutoff: start.add(const Duration(hours: 2)),
    minimumDuration: const Duration(hours: 1),
    maximumDuration: const Duration(hours: 3),
    windowPolicyVersion: 1,
  );
  final identity = AggregateIdentity(
    organizationId: organizationId,
    applicationId: applicationId,
    environmentId: environmentId,
    platformId: 'android',
    releaseId: releaseId,
    patchId: patchId,
    sequence: 1,
    rolloutId: rolloutId,
    rolloutRevision: 1,
    windowId: window.windowId,
    windowStart: window.serverStart,
    windowEnd: window.serverEnd,
    lateCutoff: window.lateCutoff,
    observationSchemaVersion: 1,
    aggregationVersion: 1,
  );
  final zeroQuality = const AggregateQualityCounters(
    accepted: 1,
    duplicate: 0,
    duplicateMutations: 0,
    excessContributions: 0,
    late: 0,
    quarantined: 0,
    rejected: 0,
    securityRejected: 0,
    identityMismatch: 0,
    scopeMismatch: 0,
    impossibleSequence: 0,
    clockInvalid: 0,
    schemaUnsupported: 0,
    securitySuspicion: 0,
    otherQuarantine: 0,
    outOfWindow: 0,
  );
  final counters = const AggregateCounters(
    eligibleInstallationsObserved: 1,
    lookupAttempts: 1,
    candidateOffers: 1,
    downloadSucceeded: 1,
    downloadFailed: 0,
    admissionVerified: 1,
    admissionRejected: 0,
    activationStarted: 1,
    activationSucceeded: 1,
    activationFailed: 0,
    healthyConfirmed: 1,
    runtimeFaults: 0,
    rollbacks: 0,
    fallbacksToAot: 0,
    restartSurvived: 1,
    staleOrReplayRejects: 0,
    lateEvents: 0,
    quarantinedEvents: 0,
    missingExpectedEvents: 0,
  );
  final metrics = <AggregateMetricName, AggregateMetric>{
    for (final name in AggregateMetricName.values)
      name:
          name == AggregateMetricName.runtimeFaultRate ||
              name == AggregateMetricName.rollbackFallbackRate ||
              name == AggregateMetricName.quarantineRate
          ? const AggregateMetric.evaluable(numerator: 0, denominator: 1)
          : const AggregateMetric.evaluable(numerator: 1, denominator: 1),
  };
  return HealthAggregate(
    identity: identity,
    window: window,
    inputCount: 1,
    acceptedInputCount: 1,
    inputDigest: _digest('aggregate-input-api'),
    policyVersion: 1,
    policyDigest: _digest('aggregate-policy-api'),
    externalQualityDigest: _digest('aggregate-quality-api'),
    counters: counters,
    quality: zeroQuality,
    metrics: metrics,
    coverage: const AggregateCoverage(
      observedInstallations: 1,
      expectedInstallations: 1,
      observedBasisPoints: 10000,
      minimumBasisPoints: 10000,
      state: AggregateCoverageState.sufficient,
    ),
    samples: const AggregateSampleStatus(
      eligible: AggregateSampleCheck(observed: 1, required: 1, passed: true),
      offers: AggregateSampleCheck(observed: 1, required: 1, passed: true),
      activated: AggregateSampleCheck(observed: 1, required: 1, passed: true),
      healthy: AggregateSampleCheck(observed: 1, required: 1, passed: true),
      coveragePassed: true,
      allPassed: true,
    ),
    privacyState: AggregatePrivacyState.normal,
    freshnessState: AggregateFreshnessState.fresh,
    missingData: const <AggregateMissingDataReason>[],
    latestPrimaryReceivedAt: start.add(const Duration(minutes: 5)),
  );
}

String _digest(String value) =>
    'sha256:${sha256.convert(utf8.encode(value)).toString()}';
