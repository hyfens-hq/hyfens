import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

import 'encoding.dart';
import 'errors.dart';
import 'p3e_auto_halt.dart';
import 'p3e_auto_halt_authority.dart';
import 'p3e_claim.dart';
import 'p3e_schedule.dart';
import 'postgres_faults.dart';

const List<String> p3e5PostgresMigration005 = <String>[
  '''CREATE TABLE IF NOT EXISTS control_plane_p3e5_schedules (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  environment_id text NOT NULL,
  rollout_id text NOT NULL,
  schedule_id text NOT NULL,
  current_schedule_revision_id text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, schedule_id)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e5_schedules_scope_idx
  ON control_plane_p3e5_schedules
    (organization_id, application_id, environment_id, rollout_id, schedule_id)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_p3e5_schedule_revisions (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  environment_id text NOT NULL,
  rollout_id text NOT NULL,
  schedule_id text NOT NULL,
  schedule_revision_id text NOT NULL,
  schedule_generation bigint NOT NULL CHECK (schedule_generation > 0),
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, schedule_revision_id),
  UNIQUE (organization_id, schedule_id, schedule_generation),
  FOREIGN KEY (organization_id, schedule_id)
    REFERENCES control_plane_p3e5_schedules(organization_id, schedule_id)
    DEFERRABLE INITIALLY DEFERRED
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e5_revisions_schedule_idx
  ON control_plane_p3e5_schedule_revisions
    (organization_id, schedule_id, schedule_generation)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_p3e5_work (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  environment_id text NOT NULL,
  rollout_id text NOT NULL,
  schedule_id text NOT NULL,
  schedule_revision_id text NOT NULL,
  work_id text NOT NULL,
  logical_key_digest text NOT NULL,
  status text NOT NULL,
  work_version bigint NOT NULL CHECK (work_version >= 0),
  attempt_count bigint NOT NULL CHECK (attempt_count >= 0),
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, work_id),
  UNIQUE (organization_id, logical_key_digest),
  FOREIGN KEY (organization_id, schedule_revision_id)
    REFERENCES control_plane_p3e5_schedule_revisions
      (organization_id, schedule_revision_id)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e5_work_scope_idx
  ON control_plane_p3e5_work
    (organization_id, application_id, environment_id, rollout_id, work_id)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_p3e5_attempts (
  organization_id text NOT NULL,
  work_id text NOT NULL,
  attempt_id text NOT NULL,
  attempt_number bigint NOT NULL CHECK (attempt_number > 0),
  body jsonb NOT NULL,
  started_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, attempt_id),
  UNIQUE (organization_id, work_id, attempt_number),
  FOREIGN KEY (organization_id, work_id)
    REFERENCES control_plane_p3e5_work(organization_id, work_id)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e5_attempts_work_idx
  ON control_plane_p3e5_attempts
    (organization_id, work_id, attempt_number)''',
];

const List<String> p3e5PostgresMigration006 = <String>[
  '''ALTER TABLE control_plane_p3e5_work
  ADD COLUMN IF NOT EXISTS not_before timestamptz''',
  '''ALTER TABLE control_plane_p3e5_work
  ADD COLUMN IF NOT EXISTS lease_expires_at timestamptz''',
  '''UPDATE control_plane_p3e5_work
  SET not_before = (body->>'notBefore')::timestamptz
  WHERE not_before IS NULL''',
  '''UPDATE control_plane_p3e5_work
  SET lease_expires_at = (body->>'leaseExpiresAt')::timestamptz
  WHERE lease_expires_at IS NULL AND body->>'leaseExpiresAt' IS NOT NULL''',
  '''ALTER TABLE control_plane_p3e5_work
  ALTER COLUMN not_before SET NOT NULL''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e5_work_claim_idx
  ON control_plane_p3e5_work
    (organization_id, application_id, environment_id, status,
     not_before, lease_expires_at, created_at, work_id)''',
];

const List<String> p3e5PostgresMigration007 = <String>[
  '''CREATE TABLE IF NOT EXISTS control_plane_p3e5_auto_halt_policies (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  environment_id text NOT NULL,
  policy_id text NOT NULL,
  policy_digest text NOT NULL,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, policy_id),
  UNIQUE (organization_id, application_id, environment_id, policy_digest)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e5_auto_halt_policy_scope_idx
  ON control_plane_p3e5_auto_halt_policies
    (organization_id, application_id, environment_id, policy_id)''',
  '''CREATE TABLE IF NOT EXISTS control_plane_p3e5_auto_halt_states (
  organization_id text NOT NULL,
  application_id text NOT NULL,
  environment_id text NOT NULL,
  state_id text NOT NULL,
  generation bigint NOT NULL CHECK (generation > 0),
  supersedes_state_id text,
  policy_id text NOT NULL,
  policy_digest text NOT NULL,
  policy_approved boolean NOT NULL DEFAULT false,
  production_enabled boolean NOT NULL DEFAULT false,
  body jsonb NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (organization_id, state_id),
  UNIQUE (organization_id, application_id, environment_id, generation),
  FOREIGN KEY (organization_id, policy_id)
    REFERENCES control_plane_p3e5_auto_halt_policies
      (organization_id, policy_id)
)''',
  '''CREATE INDEX IF NOT EXISTS control_plane_p3e5_auto_halt_state_scope_idx
  ON control_plane_p3e5_auto_halt_states
    (organization_id, application_id, environment_id, generation DESC)''',
];

final class P3e5ConsistencyIssue {
  const P3e5ConsistencyIssue(this.entityType, this.entityId, this.code);

  final String entityType;
  final String entityId;
  final String code;
}

abstract interface class P3e5ScheduleStore {
  Future<void> initialize();
  Future<void> close();

  Future<void> createSchedule(
    EvaluationSchedule schedule,
    EvaluationScheduleRevision revision,
  );

  Future<void> reviseSchedule({
    required EvaluationSchedule schedule,
    required String expectedCurrentRevisionId,
    required EvaluationScheduleRevision revision,
  });

  Future<EvaluationSchedule?> readSchedule(
    String organizationId,
    String scheduleId,
  );

  Future<List<EvaluationSchedule>> listSchedules(String organizationId);

  Future<EvaluationScheduleRevision?> readRevision(
    String organizationId,
    String scheduleRevisionId,
  );

  Future<List<EvaluationScheduleRevision>> listRevisions(
    String organizationId,
    String scheduleId,
  );

  Future<void> putAutomaticHaltFoundation(
    AutomaticHaltPolicy policy,
    AutomaticHaltEnvironmentState state,
  );

  Future<AutomaticHaltPolicy?> readAutomaticHaltPolicy(
    String organizationId,
    String policyId,
  );

  Future<List<AutomaticHaltPolicy>> listAutomaticHaltPolicies(
    String organizationId,
  );

  Future<AutomaticHaltEnvironmentState?> readCurrentAutomaticHaltState(
    String organizationId,
    String applicationId,
    String environmentId,
  );

  Future<void> putWork(ScheduledEvaluationWork work);

  Future<ScheduledEvaluationWork?> readWork(
    String organizationId,
    String workId,
  );

  Future<List<ScheduledEvaluationWork>> listWork(String organizationId);

  Future<void> putAttempt(
    String organizationId,
    ScheduledEvaluationAttempt attempt,
  );

  Future<List<ScheduledEvaluationAttempt>> listAttempts(
    String organizationId,
    String workId,
  );

  Future<List<P3e5ConsistencyIssue>> validateConsistency(String organizationId);

  Future<List<P3e5ClaimedWork>> claimDue(P3e5ClaimRequest request);

  /// Reclaims only an expired auto-halt work item. Generic scheduled
  /// evaluation must not call this seam: the recovered lease is consumed by
  /// the auto-halt application adapter, which remains the sole P3E-4/P3A
  /// mutation path.
  Future<P3e5ClaimedWork> reclaimAutomaticHalt(
    P3e5AutomaticHaltReclaimRequest request,
  );

  Future<P3e5WorkMutationResult> markAutomaticHaltStale(
    P3e5LeaseMutation lease,
  );

  Future<P3e5WorkMutationResult> failClaim({
    required P3e5LeaseMutation lease,
    required P3e5RetryFailure failure,
    required P3e5RetryPolicy retryPolicy,
  });

  Future<P3e5WorkMutationResult> cancelWork({
    required P3e5ClaimScope scope,
    required String workId,
    required int expectedWorkVersion,
  });

  Future<P3e5WorkMutationResult> manualRetry({
    required P3e5ClaimScope scope,
    required String workId,
    required int expectedWorkVersion,
    required P3e5RetryPolicy retryPolicy,
  });

  Future<P3e5WorkMutationResult> advanceExecution(P3e5ExecutionAdvance advance);

  Future<P3e5WorkMutationResult> applyAutomaticHaltIntent(
    P3e5AutomaticHaltIntentAdvance advance, {
    required Future<void> Function(
      DateTime authoritativeNow,
      ScheduledEvaluationWork currentWork,
    )
    validateCurrent,
  });

  Future<P3e5WorkMutationResult> completeAutomaticHalt(
    P3e5AutomaticHaltCompletion completion,
  );
}

enum P3e5FileClaimFailurePoint {
  beforeAttemptWrite,
  afterAttemptWrite,
  beforeWorkReplace,
  afterWorkReplace,
  beforeResponse,
}

enum P3e5PostgresClaimFailurePoint { beforeCommit, afterCommit }

enum P3e5AutomaticHaltReclaimFailurePoint { beforeCommit, afterCommit }

enum P3e5AutomaticHaltFailurePoint { beforeCommit, afterCommit }

enum P3e5AutomaticHaltCompletionFailurePoint { beforeCommit, afterCommit }

/// File persistence is deliberately one-process/one-writer. The process guard
/// and non-blocking OS file lock reject a second writer; they are not leases
/// and confer no permission to execute scheduled work.
final class FileP3e5ScheduleStore implements P3e5ScheduleStore {
  FileP3e5ScheduleStore(
    this.root, {
    this.limits = const P3e5ScheduleLimits(),
    DateTime Function()? clock,
    this.claimFailure,
    this.automaticHaltFailure,
    this.automaticHaltCompletionFailure,
    this.automaticHaltReclaimFailure,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()) {
    limits.validate();
  }

  final Directory root;
  final P3e5ScheduleLimits limits;
  final DateTime Function() _clock;
  final void Function(P3e5FileClaimFailurePoint point)? claimFailure;
  final void Function(P3e5AutomaticHaltFailurePoint point)?
  automaticHaltFailure;
  final void Function(P3e5AutomaticHaltCompletionFailurePoint point)?
  automaticHaltCompletionFailure;
  final void Function(P3e5AutomaticHaltReclaimFailurePoint point)?
  automaticHaltReclaimFailure;
  RandomAccessFile? _guard;
  Future<void> _tail = Future<void>.value();
  static final Set<String> _activeRoots = <String>{};

  String get _rootKey => p.normalize(p.absolute(root.path));

  @override
  Future<void> initialize() async {
    if (_guard != null) return;
    await root.create(recursive: true);
    if (!_activeRoots.add(_rootKey)) {
      throw const StorageConflict(
        'File scheduled-evaluation persistence allows one process/writer only',
      );
    }
    try {
      final file = File(p.join(root.path, 'p3e5', '.writer.lock'));
      await file.parent.create(recursive: true);
      final guard = await file.open(mode: FileMode.append);
      await guard.lock(FileLock.exclusive);
      _guard = guard;
      for (final directory in const <String>[
        'schedules',
        'work',
        'attempts',
        'auto_halt',
      ]) {
        await Directory(p.join(root.path, 'p3e5', directory))
            .create(recursive: true);
      }
      await _recoverClaimJournals();
    } on Object {
      _activeRoots.remove(_rootKey);
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    final guard = _guard;
    _guard = null;
    _activeRoots.remove(_rootKey);
    if (guard != null) {
      await guard.unlock();
      await guard.close();
    }
  }

  @override
  Future<void> createSchedule(
    EvaluationSchedule schedule,
    EvaluationScheduleRevision revision,
  ) => _serialized(() async {
    validateScheduleRevisionBinding(schedule, revision);
    if (revision.scheduleGeneration != 1 ||
        schedule.currentScheduleRevision != revision.scheduleRevisionId) {
      throw const StorageConflict('Initial schedule revision is invalid');
    }
    final existing = await _readBundle(
      schedule.organizationId,
      schedule.scheduleId,
    );
    final incoming = _bundle(schedule, <EvaluationScheduleRevision>[revision]);
    _equalOrAbsent(existing, incoming, 'Schedule already exists');
    if (existing == null) {
      await _writeAtomic(
        _scheduleFile(schedule.organizationId, schedule.scheduleId),
        incoming,
      );
    }
  });

  @override
  Future<void> reviseSchedule({
    required EvaluationSchedule schedule,
    required String expectedCurrentRevisionId,
    required EvaluationScheduleRevision revision,
  }) => _serialized(() async {
    validateScheduleRevisionBinding(schedule, revision);
    final existing = await _readBundle(
      schedule.organizationId,
      schedule.scheduleId,
    );
    if (existing == null)
      throw const StorageConflict('Schedule does not exist');
    final current = EvaluationSchedule.fromJson(existing['schedule']);
    final revisions = _decodeRevisions(existing['revisions']);
    if (current.currentScheduleRevision != expectedCurrentRevisionId) {
      if (current.currentScheduleRevision == schedule.currentScheduleRevision) {
        final match = revisions.where(
          (item) => item.scheduleRevisionId == revision.scheduleRevisionId,
        );
        if (match.length == 1 &&
            match.single.canonicalSerialization ==
                revision.canonicalSerialization &&
            current.canonicalSerialization == schedule.canonicalSerialization) {
          return;
        }
      }
      throw StoragePreconditionFailed(
        'Schedule revision is stale',
        currentRevision: revisions.last.scheduleGeneration,
      );
    }
    final previous = revisions.last;
    if (schedule.currentScheduleRevision != revision.scheduleRevisionId ||
        revision.scheduleGeneration != previous.scheduleGeneration + 1 ||
        revision.supersedesScheduleRevisionId != previous.scheduleRevisionId) {
      throw const StorageConflict('Schedule revision lineage is invalid');
    }
    await _writeAtomic(
      _scheduleFile(schedule.organizationId, schedule.scheduleId),
      _bundle(schedule, <EvaluationScheduleRevision>[...revisions, revision]),
    );
  });

  @override
  Future<EvaluationSchedule?> readSchedule(
    String organizationId,
    String scheduleId,
  ) async {
    final bundle = await _readBundle(organizationId, scheduleId);
    return bundle == null
        ? null
        : EvaluationSchedule.fromJson(bundle['schedule']);
  }

  @override
  Future<List<EvaluationSchedule>> listSchedules(String organizationId) async {
    final directory = _tenantDirectory('schedules', organizationId);
    if (!await directory.exists()) return const <EvaluationSchedule>[];
    final files =
        (await directory.list(followLinks: false).toList())
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final values = <EvaluationSchedule>[];
    for (final file in files) {
      final bundle = _decode(await file.readAsString(), 'schedule bundle');
      values.add(EvaluationSchedule.fromJson(bundle['schedule']));
    }
    return List.unmodifiable(values);
  }

  @override
  Future<EvaluationScheduleRevision?> readRevision(
    String organizationId,
    String scheduleRevisionId,
  ) async {
    for (final schedule in await listSchedules(organizationId)) {
      for (final revision in await listRevisions(
        organizationId,
        schedule.scheduleId,
      )) {
        if (revision.scheduleRevisionId == scheduleRevisionId) return revision;
      }
    }
    return null;
  }

  @override
  Future<List<EvaluationScheduleRevision>> listRevisions(
    String organizationId,
    String scheduleId,
  ) async {
    final bundle = await _readBundle(organizationId, scheduleId);
    if (bundle == null) return const <EvaluationScheduleRevision>[];
    return List.unmodifiable(_decodeRevisions(bundle['revisions']));
  }

  @override
  Future<void> putAutomaticHaltFoundation(
    AutomaticHaltPolicy policy,
    AutomaticHaltEnvironmentState state,
  ) => _serialized(() async {
    _validateAutomaticHaltFoundation(policy, state);
    final file = _automaticHaltBundleFile(
      policy.organizationId,
      policy.applicationId,
      policy.environmentId,
    );
    final bundle = await _readFile(file);
    final decoded = _decodeAutomaticHaltBundle(
      bundle,
      policy.organizationId,
      applicationId: policy.applicationId,
      environmentId: policy.environmentId,
    );
    final policies = decoded.policies;
    final states = decoded.states;
    final existingPolicy = policies.where(
      (item) => item.policyId == policy.policyId,
    );
    if (existingPolicy.isNotEmpty &&
        existingPolicy.single.canonicalSerialization !=
            policy.canonicalSerialization) {
      throw const StorageConflict(
        'Immutable automatic-halt policy already exists',
      );
    }
    final existingState = states.where((item) => item.stateId == state.stateId);
    if (existingState.isNotEmpty) {
      if (existingState.single.canonicalSerialization !=
          state.canonicalSerialization) {
        throw const StorageConflict(
          'Immutable automatic-halt state already exists',
        );
      }
      if (existingPolicy.isNotEmpty) return;
    }
    if (existingState.isEmpty) {
      if (states.isEmpty) {
        if (state.generation != 1 || state.supersedesStateId != null) {
          throw const StorageConflict(
            'Initial automatic-halt state lineage is invalid',
          );
        }
      } else {
        final current = states.last;
        if (state.generation != current.generation + 1 ||
            state.supersedesStateId != current.stateId) {
          throw const StorageConflict(
            'Automatic-halt state lineage is invalid',
          );
        }
      }
    }
    await _writeAtomic(file, <String, Object?>{
      'entityVersion': automaticHaltEntityVersion,
      'policies': <Object?>[
        ...policies.map((item) => item.toJson()),
        if (existingPolicy.isEmpty) policy.toJson(),
      ],
      'states': <Object?>[
        ...states.map((item) => item.toJson()),
        if (existingState.isEmpty) state.toJson(),
      ],
    });
  });

  @override
  Future<AutomaticHaltPolicy?> readAutomaticHaltPolicy(
    String organizationId,
    String policyId,
  ) async {
    for (final policy in await listAutomaticHaltPolicies(organizationId)) {
      if (policy.policyId == policyId) return policy;
    }
    return null;
  }

  @override
  Future<List<AutomaticHaltPolicy>> listAutomaticHaltPolicies(
    String organizationId,
  ) async {
    final directory = _tenantDirectory('auto_halt', organizationId);
    if (!await directory.exists()) return const <AutomaticHaltPolicy>[];
    final files =
        (await directory.list(followLinks: false).toList())
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final result = <AutomaticHaltPolicy>[];
    for (final file in files) {
      final bundle = await _readFile(file);
      result.addAll(
        _decodeAutomaticHaltBundle(bundle, organizationId).policies,
      );
    }
    result.sort((left, right) => left.policyId.compareTo(right.policyId));
    if (result.map((item) => item.policyId).toSet().length != result.length) {
      throw const FormatException(
        'Duplicate automatic-halt policy identity across tenant bundles',
      );
    }
    return List.unmodifiable(result);
  }

  @override
  Future<AutomaticHaltEnvironmentState?> readCurrentAutomaticHaltState(
    String organizationId,
    String applicationId,
    String environmentId,
  ) async {
    final bundle = await _readFile(
      _automaticHaltBundleFile(organizationId, applicationId, environmentId),
    );
    final decoded = _decodeAutomaticHaltBundle(
      bundle,
      organizationId,
      applicationId: applicationId,
      environmentId: environmentId,
    );
    return decoded.states.isEmpty ? null : decoded.states.last;
  }

  @override
  Future<void> putWork(ScheduledEvaluationWork work) => _serialized(() async {
    final schedule = await readSchedule(
      work.logicalKey.organizationId,
      work.logicalKey.scheduleId,
    );
    final revision = await readRevision(
      work.logicalKey.organizationId,
      work.logicalKey.scheduleRevisionId,
    );
    if (schedule == null || revision == null) {
      throw const StorageConflict(
        'Work references a missing schedule revision',
      );
    }
    validateWorkBinding(work, schedule, revision);
    final file = _workFile(work.logicalKey.organizationId, work.workId);
    final existing = await _readFile(file);
    _equalOrAbsent(existing, work.toJson(), 'Immutable work already exists');
    if (existing == null) await _writeAtomic(file, work.toJson());
  });

  @override
  Future<ScheduledEvaluationWork?> readWork(
    String organizationId,
    String workId,
  ) async {
    final value = await _readFile(_workFile(organizationId, workId));
    return value == null ? null : ScheduledEvaluationWork.fromJson(value);
  }

  @override
  Future<List<ScheduledEvaluationWork>> listWork(String organizationId) =>
      _listTenant('work', organizationId, ScheduledEvaluationWork.fromJson);

  @override
  Future<void> putAttempt(
    String organizationId,
    ScheduledEvaluationAttempt attempt,
  ) => _serialized(() async {
    final work = await readWork(organizationId, attempt.workId);
    if (work == null || work.logicalKey.organizationId != organizationId) {
      throw const StorageConflict('Attempt references missing work');
    }
    final attempts = await listAttempts(organizationId, attempt.workId);
    final existing = attempts.where(
      (item) => item.attemptId == attempt.attemptId,
    );
    if (existing.isNotEmpty) {
      if (existing.single.canonicalSerialization !=
          attempt.canonicalSerialization) {
        throw const StorageConflict('Immutable attempt already exists');
      }
      return;
    }
    if (attempt.attemptNumber != attempts.length + 1) {
      throw const StorageConflict('Attempt sequence is invalid');
    }
    await _writeAtomic(
      _attemptFile(organizationId, attempt.workId, attempt.attemptId),
      attempt.toJson(),
    );
  });

  @override
  Future<List<ScheduledEvaluationAttempt>> listAttempts(
    String organizationId,
    String workId,
  ) async {
    final directory = Directory(
      p.join(
        _tenantDirectory('attempts', organizationId).path,
        sha256Hex(utf8.encode(workId)),
      ),
    );
    if (!await directory.exists()) return const <ScheduledEvaluationAttempt>[];
    final files = (await directory.list(followLinks: false).toList())
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList();
    final values = <ScheduledEvaluationAttempt>[];
    for (final file in files) {
      values.add(
        ScheduledEvaluationAttempt.fromJson(
          _decode(await file.readAsString(), 'attempt record'),
        ),
      );
    }
    values.sort(
      (left, right) => left.attemptNumber.compareTo(right.attemptNumber),
    );
    return List.unmodifiable(values);
  }

  @override
  Future<List<P3e5ConsistencyIssue>> validateConsistency(
    String organizationId,
  ) async => _validateValues(
    organizationId,
    await listSchedules(organizationId),
    await listWork(organizationId),
    this,
  );

  @override
  Future<List<P3e5ClaimedWork>> claimDue(P3e5ClaimRequest request) =>
      _serialized(() async {
        final now = _clock().toUtc();
        final all = await listWork(request.scope.organizationId);
        final active = all
            .where(request.scope.contains)
            .where(
              (item) =>
                  _hasActiveLease(item.status) &&
                  item.leaseExpiresAt!.isAfter(now),
            )
            .length;
        var remaining = min(
          request.resourcePolicy.claimBatchSize,
          request.resourcePolicy.maximumActiveLeasesPerTenant - active,
        );
        if (remaining <= 0) return const <P3e5ClaimedWork>[];
        final candidates =
            all
                .where(request.scope.contains)
                .where((item) => _isClaimCandidate(item, now))
                .toList()
              ..sort(_compareClaimCandidates);
        final selected = _fairCandidates(
          candidates.take(request.resourcePolicy.pendingConsiderationLimit),
          remaining,
        );
        final claimed = <P3e5ClaimedWork>[];
        for (var index = 0; index < selected.length; index++) {
          final current = selected[index];
          final binding = await _currentBinding(current);
          if (!binding) {
            await _replaceWork(
              current.withOperationalState(
                status: ScheduledEvaluationWorkStatus.stale,
                workVersion: current.workVersion + 1,
                attemptCount: current.attemptCount,
                notBefore: current.notBefore,
                leaseOwner: null,
                leaseTokenDigest: null,
                leaseAcquiredAt: null,
                leaseExpiresAt: null,
                updatedAt: now,
                lastAttemptAt: current.lastAttemptAt,
                lastErrorClass: P3e5RetryClass.stale.wireName,
                lastErrorCode: 'STALE_BINDING',
              ),
            );
            continue;
          }
          final prepared = request.preparedLeases[index];
          final reclaimed = _hasActiveLease(current.status);
          final claimedStatus = reclaimed
              ? current.status
              : ScheduledEvaluationWorkStatus.leased;
          final next = current.withOperationalState(
            status: claimedStatus,
            workVersion: current.workVersion + 1,
            attemptCount: current.attemptCount + 1,
            notBefore: current.notBefore,
            leaseOwner: request.leaseOwner,
            leaseTokenDigest: prepared.tokenDigest,
            leaseAcquiredAt: now,
            leaseExpiresAt: now.add(request.leasePolicy.duration),
            updatedAt: now,
            lastAttemptAt: now,
            lastErrorClass: null,
            lastErrorCode: null,
          );
          await _commitWorkAttempt(
            next,
            claimedAttempt(next, actorIdentity: request.leaseOwner),
          );
          claimFailure?.call(P3e5FileClaimFailurePoint.beforeResponse);
          claimed.add(
            P3e5ClaimedWork(
              work: next,
              rawLeaseToken: prepared.rawToken,
              reclaimed: reclaimed,
            ),
          );
          remaining--;
          if (remaining == 0) break;
        }
        return List.unmodifiable(claimed);
      });

  @override
  Future<P3e5ClaimedWork> reclaimAutomaticHalt(
    P3e5AutomaticHaltReclaimRequest request,
  ) => _serialized(() async {
    final current = await _requiredScopedWork(request.scope, request.workId);
    final now = _clock().toUtc();
    if (current.workVersion != request.expectedWorkVersion ||
        current.status != ScheduledEvaluationWorkStatus.haltApplying ||
        current.automaticHaltIntent == null ||
        current.leaseExpiresAt == null ||
        current.leaseExpiresAt!.isAfter(now)) {
      throw const StorageConflict(
        'Automatic-halt work is not expired or no longer current',
      );
    }
    final next = current.withOperationalState(
      status: ScheduledEvaluationWorkStatus.haltApplying,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: current.notBefore,
      leaseOwner: request.leaseOwner,
      leaseTokenDigest: request.tokenDigest,
      leaseAcquiredAt: now,
      leaseExpiresAt: now.add(request.leasePolicy.duration),
      updatedAt: now,
      lastAttemptAt: now,
      lastErrorClass: null,
      lastErrorCode: null,
    );
    automaticHaltReclaimFailure?.call(
      P3e5AutomaticHaltReclaimFailurePoint.beforeCommit,
    );
    await _replaceWork(next);
    automaticHaltReclaimFailure?.call(
      P3e5AutomaticHaltReclaimFailurePoint.afterCommit,
    );
    return P3e5ClaimedWork(
      work: next,
      rawLeaseToken: request.rawLeaseToken,
      reclaimed: true,
    );
  });

  @override
  Future<P3e5WorkMutationResult> markAutomaticHaltStale(
    P3e5LeaseMutation lease,
  ) => _serialized(() async {
    final current = await _requiredScopedWork(lease.scope, lease.workId);
    final now = _clock().toUtc();
    _validateLease(
      current,
      lease,
      now,
      expectedStatus: ScheduledEvaluationWorkStatus.haltApplying,
    );
    final next = current.withOperationalState(
      status: ScheduledEvaluationWorkStatus.stale,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: current.notBefore,
      leaseOwner: null,
      leaseTokenDigest: null,
      leaseAcquiredAt: null,
      leaseExpiresAt: null,
      updatedAt: now,
      lastAttemptAt: current.lastAttemptAt,
      lastErrorClass: P3e5RetryClass.stale.wireName,
      lastErrorCode: 'AUTO_HALT_STALE',
      clearAutomaticHaltIntent: true,
    );
    await _replaceWork(next);
    return P3e5WorkMutationResult(next, changed: true);
  });

  @override
  Future<P3e5WorkMutationResult> failClaim({
    required P3e5LeaseMutation lease,
    required P3e5RetryFailure failure,
    required P3e5RetryPolicy retryPolicy,
  }) => _serialized(() async {
    retryPolicy.validate();
    final current = await _requiredScopedWork(lease.scope, lease.workId);
    final now = _clock().toUtc();
    if (!_hasActiveLease(current.status)) {
      throw const StorageConflict('Work is not claim-side mutable');
    }
    _validateLease(current, lease, now, expectedStatus: current.status);
    final exhausted = current.attemptCount >= retryPolicy.maximumAttempts;
    final retryable = failure.classification == P3e5RetryClass.transient;
    final status = failure.classification == P3e5RetryClass.stale
        ? ScheduledEvaluationWorkStatus.stale
        : (!retryable || exhausted)
        ? ScheduledEvaluationWorkStatus.failedPermanent
        : ScheduledEvaluationWorkStatus.retryWait;
    validateScheduledEvaluationTransition(current.status, status);
    final next = current.withOperationalState(
      status: status,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: status == ScheduledEvaluationWorkStatus.retryWait
          ? now.add(retryPolicy.delayFor(current.workId, current.attemptCount))
          : current.notBefore,
      leaseOwner: null,
      leaseTokenDigest: null,
      leaseAcquiredAt: null,
      leaseExpiresAt: null,
      updatedAt: now,
      lastAttemptAt: current.lastAttemptAt,
      lastErrorClass: failure.classification.wireName,
      lastErrorCode: failure.safeCode,
    );
    await _replaceWork(next);
    return P3e5WorkMutationResult(next, changed: true);
  });

  @override
  Future<P3e5WorkMutationResult> cancelWork({
    required P3e5ClaimScope scope,
    required String workId,
    required int expectedWorkVersion,
  }) => _serialized(() async {
    final current = await _requiredScopedWork(scope, workId);
    _validateVersion(current, expectedWorkVersion);
    validateScheduledEvaluationTransition(
      current.status,
      ScheduledEvaluationWorkStatus.cancelled,
    );
    final next = current.withOperationalState(
      status: ScheduledEvaluationWorkStatus.cancelled,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: current.notBefore,
      leaseOwner: null,
      leaseTokenDigest: null,
      leaseAcquiredAt: null,
      leaseExpiresAt: null,
      updatedAt: _clock().toUtc(),
      lastAttemptAt: current.lastAttemptAt,
      lastErrorClass: current.lastErrorClass,
      lastErrorCode: current.lastErrorCode,
    );
    await _replaceWork(next);
    return P3e5WorkMutationResult(next, changed: true);
  });

  @override
  Future<P3e5WorkMutationResult> manualRetry({
    required P3e5ClaimScope scope,
    required String workId,
    required int expectedWorkVersion,
    required P3e5RetryPolicy retryPolicy,
  }) => _serialized(() async {
    retryPolicy.validate();
    final current = await _requiredScopedWork(scope, workId);
    _validateVersion(current, expectedWorkVersion);
    validateScheduledEvaluationTransition(
      current.status,
      ScheduledEvaluationWorkStatus.retryWait,
    );
    if (!await _currentBinding(current)) {
      throw const StorageConflict('Work binding is stale');
    }
    final now = _clock().toUtc();
    final next = current.withOperationalState(
      status: ScheduledEvaluationWorkStatus.retryWait,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: now.add(
        retryPolicy.delayFor(current.workId, current.attemptCount + 1),
      ),
      leaseOwner: null,
      leaseTokenDigest: null,
      leaseAcquiredAt: null,
      leaseExpiresAt: null,
      updatedAt: now,
      lastAttemptAt: current.lastAttemptAt,
      lastErrorClass: null,
      lastErrorCode: null,
    );
    await _replaceWork(next);
    return P3e5WorkMutationResult(next, changed: true);
  });

  @override
  Future<P3e5WorkMutationResult> advanceExecution(
    P3e5ExecutionAdvance advance,
  ) => _serialized(() async {
    final current = await _requiredScopedWork(
      advance.lease.scope,
      advance.lease.workId,
    );
    final now = _clock().toUtc();
    _validateLease(
      current,
      advance.lease,
      now,
      expectedStatus: advance.expectedStatus,
    );
    validateScheduledEvaluationTransition(current.status, advance.nextStatus);
    final retainLease =
        advance.nextStatus == ScheduledEvaluationWorkStatus.evaluating ||
        advance.nextStatus == ScheduledEvaluationWorkStatus.evaluated ||
        advance.nextStatus == ScheduledEvaluationWorkStatus.haltApplying;
    final next = current.withOperationalState(
      status: advance.nextStatus,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: current.notBefore,
      leaseOwner: retainLease ? current.leaseOwner : null,
      leaseTokenDigest: retainLease ? current.leaseTokenDigest : null,
      leaseAcquiredAt: retainLease ? current.leaseAcquiredAt : null,
      leaseExpiresAt: retainLease ? current.leaseExpiresAt : null,
      updatedAt: now,
      lastAttemptAt: current.lastAttemptAt,
      lastErrorClass: null,
      lastErrorCode: null,
      linkedAggregateId: advance.aggregateId,
      linkedAggregateRevisionId: advance.aggregateRevisionId,
      linkedEvaluationId: advance.evaluationId,
      linkedDecisionId: advance.decisionId,
    );
    await _replaceWork(next);
    return P3e5WorkMutationResult(next, changed: true);
  });

  @override
  Future<P3e5WorkMutationResult> applyAutomaticHaltIntent(
    P3e5AutomaticHaltIntentAdvance advance, {
    required Future<void> Function(
      DateTime authoritativeNow,
      ScheduledEvaluationWork currentWork,
    )
    validateCurrent,
  }) => _serialized(() async {
    final current = await _requiredScopedWork(
      advance.authority.lease.scope,
      advance.authority.workId,
    );
    if (current.status == ScheduledEvaluationWorkStatus.haltApplying) {
      if (current.automaticHaltIntent?.intentDigest ==
          advance.intent.intentDigest) {
        return P3e5WorkMutationResult(current, changed: false);
      }
      throw const StorageConflict('Automatic-halt intent conflict');
    }
    final now = _clock().toUtc();
    advance.authority.validateAt(now);
    _validateLease(
      current,
      advance.authority.lease,
      now,
      expectedStatus: ScheduledEvaluationWorkStatus.evaluated,
    );
    await validateCurrent(now, current);
    final next = current.withOperationalState(
      status: ScheduledEvaluationWorkStatus.haltApplying,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: current.notBefore,
      leaseOwner: current.leaseOwner,
      leaseTokenDigest: current.leaseTokenDigest,
      leaseAcquiredAt: current.leaseAcquiredAt,
      leaseExpiresAt: current.leaseExpiresAt,
      updatedAt: now,
      lastAttemptAt: current.lastAttemptAt,
      lastErrorClass: null,
      lastErrorCode: null,
      linkedAutomaticHaltIntent: advance.intent,
    );
    automaticHaltFailure?.call(P3e5AutomaticHaltFailurePoint.beforeCommit);
    await _replaceWork(next);
    automaticHaltFailure?.call(P3e5AutomaticHaltFailurePoint.afterCommit);
    return P3e5WorkMutationResult(next, changed: true);
  });

  @override
  Future<P3e5WorkMutationResult> completeAutomaticHalt(
    P3e5AutomaticHaltCompletion completion,
  ) => _serialized(() async {
    final current = await _requiredScopedWork(
      completion.lease.scope,
      completion.lease.workId,
    );
    final now = _clock().toUtc();
    _validateAutomaticHaltCompletion(current, completion, now);
    final next = current.withOperationalState(
      status: ScheduledEvaluationWorkStatus.completed,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: current.notBefore,
      leaseOwner: null,
      leaseTokenDigest: null,
      leaseAcquiredAt: null,
      leaseExpiresAt: null,
      updatedAt: now,
      lastAttemptAt: current.lastAttemptAt,
      lastErrorClass: null,
      lastErrorCode: null,
      linkedHaltApplicationId: completion.haltApplicationId,
    );
    automaticHaltCompletionFailure?.call(
      P3e5AutomaticHaltCompletionFailurePoint.beforeCommit,
    );
    await _replaceWork(next);
    automaticHaltCompletionFailure?.call(
      P3e5AutomaticHaltCompletionFailurePoint.afterCommit,
    );
    return P3e5WorkMutationResult(next, changed: true);
  });

  Future<bool> _currentBinding(ScheduledEvaluationWork work) async {
    final schedule = await readSchedule(
      work.logicalKey.organizationId,
      work.logicalKey.scheduleId,
    );
    final revision = await readRevision(
      work.logicalKey.organizationId,
      work.logicalKey.scheduleRevisionId,
    );
    return schedule != null &&
        revision != null &&
        schedule.currentScheduleRevision == revision.scheduleRevisionId &&
        revision.scheduledEvaluationEnabled &&
        revision.scheduleGeneration == work.logicalKey.scheduleGeneration;
  }

  Future<ScheduledEvaluationWork> _requiredScopedWork(
    P3e5ClaimScope scope,
    String workId,
  ) async {
    final work = await readWork(scope.organizationId, workId);
    if (work == null || !scope.contains(work)) {
      throw const StorageConflict('Scheduled work was not found');
    }
    return work;
  }

  Future<void> _replaceWork(ScheduledEvaluationWork work) => _writeAtomic(
    _workFile(work.logicalKey.organizationId, work.workId),
    work.toJson(),
  );

  Future<void> _commitWorkAttempt(
    ScheduledEvaluationWork work,
    ScheduledEvaluationAttempt attempt,
  ) async {
    final journal = File(
      '${_workFile(work.logicalKey.organizationId, work.workId).path}.claim',
    );
    await _writeAtomic(journal, <String, Object?>{
      'work': work.toJson(),
      'attempt': attempt.toJson(),
    });
    claimFailure?.call(P3e5FileClaimFailurePoint.beforeAttemptWrite);
    await _writeAtomic(
      _attemptFile(
        work.logicalKey.organizationId,
        work.workId,
        attempt.attemptId,
      ),
      attempt.toJson(),
    );
    claimFailure?.call(P3e5FileClaimFailurePoint.afterAttemptWrite);
    claimFailure?.call(P3e5FileClaimFailurePoint.beforeWorkReplace);
    await _replaceWork(work);
    claimFailure?.call(P3e5FileClaimFailurePoint.afterWorkReplace);
    await journal.delete();
  }

  Future<void> _recoverClaimJournals() async {
    final workRoot = Directory(p.join(root.path, 'p3e5', 'work'));
    if (!await workRoot.exists()) return;
    await for (final entity in workRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.json.claim')) continue;
      final value = await _readFile(entity);
      if (value == null) continue;
      final work = ScheduledEvaluationWork.fromJson(value['work']);
      final attempt = ScheduledEvaluationAttempt.fromJson(value['attempt']);
      await _writeAtomic(
        _attemptFile(
          work.logicalKey.organizationId,
          work.workId,
          attempt.attemptId,
        ),
        attempt.toJson(),
      );
      await _replaceWork(work);
      await entity.delete();
    }
  }

  Future<List<T>> _listTenant<T>(
    String collection,
    String organizationId,
    T Function(Object?) decode,
  ) async {
    final directory = _tenantDirectory(collection, organizationId);
    if (!await directory.exists()) return List<T>.unmodifiable(const []);
    final files =
        (await directory.list(followLinks: false).toList())
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final result = <T>[];
    for (final file in files) {
      result.add(
        decode(_decode(await file.readAsString(), '$collection record')),
      );
    }
    return List.unmodifiable(result);
  }

  Directory _tenantDirectory(String collection, String organizationId) =>
      Directory(
        p.join(
          root.path,
          'p3e5',
          collection,
          sha256Hex(utf8.encode(organizationId)),
        ),
      );

  File _scheduleFile(String organizationId, String scheduleId) => File(
    p.join(
      _tenantDirectory('schedules', organizationId).path,
      '${sha256Hex(utf8.encode(scheduleId))}.json',
    ),
  );

  File _workFile(String organizationId, String workId) => File(
    p.join(
      _tenantDirectory('work', organizationId).path,
      '${sha256Hex(utf8.encode(workId))}.json',
    ),
  );

  File _attemptFile(String organizationId, String workId, String attemptId) =>
      File(
        p.join(
          _tenantDirectory('attempts', organizationId).path,
          sha256Hex(utf8.encode(workId)),
          '${sha256Hex(utf8.encode(attemptId))}.json',
        ),
      );

  File _automaticHaltBundleFile(
    String organizationId,
    String applicationId,
    String environmentId,
  ) => File(
    p.join(
      _tenantDirectory('auto_halt', organizationId).path,
      '${sha256Hex(utf8.encode('$applicationId\u0000$environmentId'))}.json',
    ),
  );

  Future<Map<String, Object?>?> _readBundle(
    String organizationId,
    String scheduleId,
  ) => _readFile(_scheduleFile(organizationId, scheduleId));

  Future<Map<String, Object?>?> _readFile(File file) async {
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    if (utf8.encode(text).length > limits.maximumWorkBytes * 4) {
      throw const FormatException('Persisted P3E5 file exceeds byte limit');
    }
    return _decode(text, 'persisted P3E5 record');
  }

  Future<void> _writeAtomic(File file, Map<String, Object?> value) async {
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.tmp.${pid}.${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.writeAsString('${canonicalJson(value)}\n', flush: true);
    await temporary.rename(file.path);
  }

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final prior = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    await prior;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }
}

final class PostgresP3e5ScheduleStore implements P3e5ScheduleStore {
  PostgresP3e5ScheduleStore(
    String connectionString, {
    this.limits = const P3e5ScheduleLimits(),
    this.claimFailure,
    this.automaticHaltFailure,
    this.automaticHaltCompletionFailure,
    this.automaticHaltReclaimFailure,
    this.disconnectInjector,
  }) : _pool = Pool.withUrl(connectionString) {
    limits.validate();
  }

  PostgresP3e5ScheduleStore.withPool(
    Pool pool, {
    this.limits = const P3e5ScheduleLimits(),
    this.claimFailure,
    this.automaticHaltFailure,
    this.automaticHaltCompletionFailure,
    this.automaticHaltReclaimFailure,
    this.disconnectInjector,
  }) : _pool = pool {
    limits.validate();
  }

  final Pool _pool;
  final P3e5ScheduleLimits limits;
  final void Function(P3e5PostgresClaimFailurePoint point)? claimFailure;
  final void Function(P3e5AutomaticHaltFailurePoint point)?
  automaticHaltFailure;
  final void Function(P3e5AutomaticHaltCompletionFailurePoint point)?
  automaticHaltCompletionFailure;
  final void Function(P3e5AutomaticHaltReclaimFailurePoint point)?
  automaticHaltReclaimFailure;

  /// Test-only fault injection. Production callers leave this null.
  final PostgresDisconnectInjector? disconnectInjector;
  bool _initialized = false;

  Future<void> _disconnectIfRequested(PostgresDisconnectPoint point) async {
    if (disconnectInjector?.call(point) != true) return;
    await _pool.close(force: true);
    throw StorageUnavailable(
      'Injected PostgreSQL connection loss at ${point.name}',
    );
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _pool.runTx((session) async {
      await session.execute('SELECT pg_advisory_xact_lock(7812450)');
      await session.execute(
        '''CREATE TABLE IF NOT EXISTS control_plane_schema_migrations (
        version integer PRIMARY KEY,
        applied_at timestamptz NOT NULL DEFAULT now()
      )''',
      );
      final rows = await session.execute(
        'SELECT COALESCE(MAX(version), 0) AS version FROM control_plane_schema_migrations',
      );
      var version = int.parse('${rows.first.toColumnMap()['version']}');
      if (version < 4 || version > 8) {
        throw StorageConflict(
          'P3E5 requires control-plane schema version 4 through 8; found $version',
        );
      }
      if (version == 4) {
        for (final statement in p3e5PostgresMigration005) {
          await session.execute(statement);
        }
        await session.execute(
          'INSERT INTO control_plane_schema_migrations(version) VALUES (5) '
          'ON CONFLICT (version) DO NOTHING',
        );
        version = 5;
      }
      if (version == 5) {
        for (final statement in p3e5PostgresMigration006) {
          await session.execute(statement);
        }
        await session.execute(
          'INSERT INTO control_plane_schema_migrations(version) VALUES (6) '
          'ON CONFLICT (version) DO NOTHING',
        );
        version = 6;
      }
      if (version == 6) {
        for (final statement in p3e5PostgresMigration007) {
          await session.execute(statement);
        }
        await session.execute(
          'INSERT INTO control_plane_schema_migrations(version) VALUES (7) '
          'ON CONFLICT (version) DO NOTHING',
        );
      }
    });
    _initialized = true;
  }

  @override
  Future<void> close() => _pool.close();

  @override
  Future<void> createSchedule(
    EvaluationSchedule schedule,
    EvaluationScheduleRevision revision,
  ) async {
    validateScheduleRevisionBinding(schedule, revision);
    if (revision.scheduleGeneration != 1 ||
        schedule.currentScheduleRevision != revision.scheduleRevisionId) {
      throw const StorageConflict('Initial schedule revision is invalid');
    }
    await _pool.runTx((session) async {
      await _insertSchedule(session, schedule);
      await _insertRevision(session, revision);
    });
  }

  @override
  Future<void> reviseSchedule({
    required EvaluationSchedule schedule,
    required String expectedCurrentRevisionId,
    required EvaluationScheduleRevision revision,
  }) async {
    validateScheduleRevisionBinding(schedule, revision);
    await _pool.runTx((session) async {
      final currentRaw = await _readRawSession(
        session,
        'control_plane_p3e5_schedules',
        'schedule_id',
        schedule.organizationId,
        schedule.scheduleId,
        forUpdate: true,
      );
      if (currentRaw == null)
        throw const StorageConflict('Schedule does not exist');
      final current = EvaluationSchedule.fromJson(currentRaw);
      if (current.currentScheduleRevision != expectedCurrentRevisionId) {
        if (current.currentScheduleRevision ==
            schedule.currentScheduleRevision) {
          final existing = await _readRawSession(
            session,
            'control_plane_p3e5_schedule_revisions',
            'schedule_revision_id',
            schedule.organizationId,
            revision.scheduleRevisionId,
          );
          if (existing != null &&
              canonicalJson(existing) == canonicalJson(revision.toJson()) &&
              current.canonicalSerialization ==
                  schedule.canonicalSerialization) {
            return;
          }
        }
        throw StoragePreconditionFailed(
          'Schedule revision is stale',
          currentRevision: revision.scheduleGeneration - 1,
        );
      }
      final previous = await _readRawSession(
        session,
        'control_plane_p3e5_schedule_revisions',
        'schedule_revision_id',
        schedule.organizationId,
        expectedCurrentRevisionId,
      );
      if (previous == null)
        throw const StorageConflict('Current schedule revision is missing');
      final previousRevision = EvaluationScheduleRevision.fromJson(previous);
      if (revision.scheduleGeneration !=
              previousRevision.scheduleGeneration + 1 ||
          revision.supersedesScheduleRevisionId !=
              previousRevision.scheduleRevisionId ||
          schedule.currentScheduleRevision != revision.scheduleRevisionId) {
        throw const StorageConflict('Schedule revision lineage is invalid');
      }
      await _insertRevision(session, revision);
      final updated = await session.execute(
        Sql.named(
          'UPDATE control_plane_p3e5_schedules SET '
          'current_schedule_revision_id = @revision:text, body = @body:jsonb, '
          'updated_at = now() WHERE organization_id = @organization:text '
          'AND schedule_id = @schedule:text '
          'AND current_schedule_revision_id = @expected:text',
        ),
        parameters: <String, Object?>{
          'revision': revision.scheduleRevisionId,
          'body': schedule.toJson(),
          'organization': schedule.organizationId,
          'schedule': schedule.scheduleId,
          'expected': expectedCurrentRevisionId,
        },
      );
      if (updated.affectedRows != 1) {
        throw const StorageConflict('Schedule CAS did not persist');
      }
    });
  }

  @override
  Future<EvaluationSchedule?> readSchedule(
    String organizationId,
    String scheduleId,
  ) async {
    final raw = await _readRaw(
      'control_plane_p3e5_schedules',
      'schedule_id',
      organizationId,
      scheduleId,
    );
    return raw == null ? null : EvaluationSchedule.fromJson(raw);
  }

  @override
  Future<List<EvaluationSchedule>> listSchedules(String organizationId) =>
      _list(
        'control_plane_p3e5_schedules',
        'schedule_id',
        organizationId,
        EvaluationSchedule.fromJson,
      );

  @override
  Future<EvaluationScheduleRevision?> readRevision(
    String organizationId,
    String scheduleRevisionId,
  ) async {
    final raw = await _readRaw(
      'control_plane_p3e5_schedule_revisions',
      'schedule_revision_id',
      organizationId,
      scheduleRevisionId,
    );
    return raw == null ? null : EvaluationScheduleRevision.fromJson(raw);
  }

  @override
  Future<List<EvaluationScheduleRevision>> listRevisions(
    String organizationId,
    String scheduleId,
  ) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT body::text AS body_json FROM control_plane_p3e5_schedule_revisions '
        'WHERE organization_id = @organization:text AND schedule_id = @schedule:text '
        'ORDER BY schedule_generation',
      ),
      parameters: <String, Object?>{
        'organization': organizationId,
        'schedule': scheduleId,
      },
    );
    return List.unmodifiable(
      result.map(
        (row) => EvaluationScheduleRevision.fromJson(
          _decodeBody(row.toColumnMap()['body_json']),
        ),
      ),
    );
  }

  @override
  Future<void> putAutomaticHaltFoundation(
    AutomaticHaltPolicy policy,
    AutomaticHaltEnvironmentState state,
  ) async {
    _validateAutomaticHaltFoundation(policy, state);
    await _pool.runTx((session) async {
      await _insertImmutable(
        session,
        table: 'control_plane_p3e5_auto_halt_policies',
        idColumn: 'policy_id',
        organizationId: policy.organizationId,
        id: policy.policyId,
        body: policy.toJson(),
        columns: <String, Object?>{
          'application_id': policy.applicationId,
          'environment_id': policy.environmentId,
          'policy_digest': policy.digest,
          'created_at': policy.createdAt,
        },
      );
      final currentRows = await session.execute(
        Sql.named(
          'SELECT body::text AS body_json '
          'FROM control_plane_p3e5_auto_halt_states '
          'WHERE organization_id=@organization:text '
          'AND application_id=@application:text '
          'AND environment_id=@environment:text '
          'ORDER BY generation DESC LIMIT 1 FOR UPDATE',
        ),
        parameters: <String, Object?>{
          'organization': policy.organizationId,
          'application': policy.applicationId,
          'environment': policy.environmentId,
        },
      );
      final current = currentRows.isEmpty
          ? null
          : AutomaticHaltEnvironmentState.fromJson(
              _decodeBody(currentRows.first.toColumnMap()['body_json']),
            );
      if (current == null) {
        if (state.generation != 1 || state.supersedesStateId != null) {
          throw const StorageConflict(
            'Initial automatic-halt state lineage is invalid',
          );
        }
      } else if (current.stateId != state.stateId &&
          (state.generation != current.generation + 1 ||
              state.supersedesStateId != current.stateId)) {
        throw const StorageConflict('Automatic-halt state lineage is invalid');
      }
      await _insertImmutable(
        session,
        table: 'control_plane_p3e5_auto_halt_states',
        idColumn: 'state_id',
        organizationId: state.organizationId,
        id: state.stateId,
        body: state.toJson(),
        columns: <String, Object?>{
          'application_id': state.applicationId,
          'environment_id': state.environmentId,
          'generation': state.generation,
          'supersedes_state_id': state.supersedesStateId,
          'policy_id': state.policyId,
          'policy_digest': state.automaticHaltPolicyDigest,
          'policy_approved': state.policyApproved,
          'production_enabled': state.productionEnabled,
          'created_at': state.createdAt,
        },
      );
    });
  }

  @override
  Future<AutomaticHaltPolicy?> readAutomaticHaltPolicy(
    String organizationId,
    String policyId,
  ) async {
    final raw = await _readRaw(
      'control_plane_p3e5_auto_halt_policies',
      'policy_id',
      organizationId,
      policyId,
    );
    return raw == null ? null : AutomaticHaltPolicy.fromJson(raw);
  }

  @override
  Future<List<AutomaticHaltPolicy>> listAutomaticHaltPolicies(
    String organizationId,
  ) => _list(
    'control_plane_p3e5_auto_halt_policies',
    'policy_id',
    organizationId,
    AutomaticHaltPolicy.fromJson,
  );

  @override
  Future<AutomaticHaltEnvironmentState?> readCurrentAutomaticHaltState(
    String organizationId,
    String applicationId,
    String environmentId,
  ) async {
    final rows = await _pool.execute(
      Sql.named(
        'SELECT body::text AS body_json '
        'FROM control_plane_p3e5_auto_halt_states '
        'WHERE organization_id=@organization:text '
        'AND application_id=@application:text '
        'AND environment_id=@environment:text '
        'ORDER BY generation DESC LIMIT 1',
      ),
      parameters: <String, Object?>{
        'organization': organizationId,
        'application': applicationId,
        'environment': environmentId,
      },
    );
    return rows.isEmpty
        ? null
        : AutomaticHaltEnvironmentState.fromJson(
            _decodeBody(rows.first.toColumnMap()['body_json']),
          );
  }

  @override
  Future<void> putWork(ScheduledEvaluationWork work) async {
    await _pool.runTx((session) async {
      final scheduleRaw = await _readRawSession(
        session,
        'control_plane_p3e5_schedules',
        'schedule_id',
        work.logicalKey.organizationId,
        work.logicalKey.scheduleId,
      );
      final revisionRaw = await _readRawSession(
        session,
        'control_plane_p3e5_schedule_revisions',
        'schedule_revision_id',
        work.logicalKey.organizationId,
        work.logicalKey.scheduleRevisionId,
      );
      if (scheduleRaw == null || revisionRaw == null) {
        throw const StorageConflict(
          'Work references a missing schedule revision',
        );
      }
      validateWorkBinding(
        work,
        EvaluationSchedule.fromJson(scheduleRaw),
        EvaluationScheduleRevision.fromJson(revisionRaw),
      );
      await _insertImmutable(
        session,
        table: 'control_plane_p3e5_work',
        idColumn: 'work_id',
        organizationId: work.logicalKey.organizationId,
        id: work.workId,
        body: work.toJson(),
        columns: <String, Object?>{
          'application_id': work.logicalKey.applicationId,
          'environment_id': work.logicalKey.environmentId,
          'rollout_id': work.logicalKey.rolloutId,
          'schedule_id': work.logicalKey.scheduleId,
          'schedule_revision_id': work.logicalKey.scheduleRevisionId,
          'logical_key_digest': work.logicalKey.digest,
          'status': work.status.wireName,
          'work_version': work.workVersion,
          'attempt_count': work.attemptCount,
          'not_before': work.notBefore,
          'created_at': work.createdAt,
          'updated_at': work.updatedAt,
        },
      );
    });
  }

  @override
  Future<ScheduledEvaluationWork?> readWork(
    String organizationId,
    String workId,
  ) async {
    await _disconnectIfRequested(
      PostgresDisconnectPoint.postconditionReadBefore,
    );
    final raw = await _readRaw(
      'control_plane_p3e5_work',
      'work_id',
      organizationId,
      workId,
    );
    return raw == null ? null : ScheduledEvaluationWork.fromJson(raw);
  }

  @override
  Future<List<ScheduledEvaluationWork>> listWork(String organizationId) =>
      _list(
        'control_plane_p3e5_work',
        'work_id',
        organizationId,
        ScheduledEvaluationWork.fromJson,
      );

  @override
  Future<void> putAttempt(
    String organizationId,
    ScheduledEvaluationAttempt attempt,
  ) async {
    await _pool.runTx((session) async {
      final work = await _readRawSession(
        session,
        'control_plane_p3e5_work',
        'work_id',
        organizationId,
        attempt.workId,
      );
      if (work == null)
        throw const StorageConflict('Attempt references missing work');
      final existing = await _readRawSession(
        session,
        'control_plane_p3e5_attempts',
        'attempt_id',
        organizationId,
        attempt.attemptId,
      );
      if (existing != null) {
        if (canonicalJson(existing) != canonicalJson(attempt.toJson())) {
          throw const StorageConflict('Immutable attempt already exists');
        }
        return;
      }
      final rows = await session.execute(
        Sql.named(
          'SELECT COALESCE(MAX(attempt_number), 0) AS maximum '
          'FROM control_plane_p3e5_attempts WHERE organization_id = @organization:text '
          'AND work_id = @work:text',
        ),
        parameters: <String, Object?>{
          'organization': organizationId,
          'work': attempt.workId,
        },
      );
      final maximum = int.parse('${rows.first.toColumnMap()['maximum']}');
      if (attempt.attemptNumber != maximum + 1) {
        throw const StorageConflict('Attempt sequence is invalid');
      }
      await _insertImmutable(
        session,
        table: 'control_plane_p3e5_attempts',
        idColumn: 'attempt_id',
        organizationId: organizationId,
        id: attempt.attemptId,
        body: attempt.toJson(),
        columns: <String, Object?>{
          'work_id': attempt.workId,
          'attempt_number': attempt.attemptNumber,
          'started_at': attempt.startedAt,
        },
      );
    });
  }

  @override
  Future<List<ScheduledEvaluationAttempt>> listAttempts(
    String organizationId,
    String workId,
  ) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT body::text AS body_json FROM control_plane_p3e5_attempts '
        'WHERE organization_id = @organization:text AND work_id = @work:text '
        'ORDER BY attempt_number',
      ),
      parameters: <String, Object?>{
        'organization': organizationId,
        'work': workId,
      },
    );
    return List.unmodifiable(
      result.map(
        (row) => ScheduledEvaluationAttempt.fromJson(
          _decodeBody(row.toColumnMap()['body_json']),
        ),
      ),
    );
  }

  @override
  Future<List<P3e5ConsistencyIssue>> validateConsistency(
    String organizationId,
  ) async => _validateValues(
    organizationId,
    await listSchedules(organizationId),
    await listWork(organizationId),
    this,
  );

  @override
  Future<List<P3e5ClaimedWork>> claimDue(P3e5ClaimRequest request) async {
    final List<P3e5ClaimedWork> claims = await _pool.runTx((session) async {
      final now = await _pgNow(session);
      final activeResult = await session.execute(
        Sql.named(
          "SELECT COUNT(*) AS count FROM control_plane_p3e5_work "
          "WHERE organization_id=@organization:text AND application_id=@application:text "
          "AND environment_id=@environment:text "
          "AND status IN ('LEASED','EVALUATING','EVALUATED','HALT_APPLYING') "
          'AND lease_expires_at > clock_timestamp()',
        ),
        parameters: <String, Object?>{
          'organization': request.scope.organizationId,
          'application': request.scope.applicationId,
          'environment': request.scope.environmentId,
        },
      );
      final active = int.parse('${activeResult.first.toColumnMap()['count']}');
      final available = min(
        request.resourcePolicy.claimBatchSize,
        request.resourcePolicy.maximumActiveLeasesPerTenant - active,
      );
      if (available <= 0) return const <P3e5ClaimedWork>[];
      final rows = await session.execute(
        Sql.named(
          "SELECT body::text AS body_json FROM control_plane_p3e5_work "
          "WHERE organization_id=@organization:text AND application_id=@application:text "
          "AND environment_id=@environment:text AND "
          "(((status='PENDING' OR status='RETRY_WAIT') AND "
          'not_before <= clock_timestamp()) OR '
          "(status IN ('LEASED','EVALUATING','EVALUATED') "
          'AND lease_expires_at <= clock_timestamp())) '
          "ORDER BY created_at, work_id LIMIT @limit:int4 FOR UPDATE SKIP LOCKED",
        ),
        parameters: <String, Object?>{
          'organization': request.scope.organizationId,
          'application': request.scope.applicationId,
          'environment': request.scope.environmentId,
          'limit': request.resourcePolicy.pendingConsiderationLimit,
        },
      );
      final candidates = rows
          .map(
            (row) => ScheduledEvaluationWork.fromJson(
              _decodeBody(row.toColumnMap()['body_json']),
            ),
          )
          .toList(growable: false);
      final result = <P3e5ClaimedWork>[];
      for (final current in _fairCandidates(candidates, available)) {
        if (!await _pgCurrentBinding(session, current)) {
          await _pgUpdate(
            session,
            current.workVersion,
            current.withOperationalState(
              status: ScheduledEvaluationWorkStatus.stale,
              workVersion: current.workVersion + 1,
              attemptCount: current.attemptCount,
              notBefore: current.notBefore,
              leaseOwner: null,
              leaseTokenDigest: null,
              leaseAcquiredAt: null,
              leaseExpiresAt: null,
              updatedAt: now,
              lastAttemptAt: current.lastAttemptAt,
              lastErrorClass: P3e5RetryClass.stale.wireName,
              lastErrorCode: 'STALE_BINDING',
            ),
          );
          continue;
        }
        final prepared = request.preparedLeases[result.length];
        final reclaimed = _hasActiveLease(current.status);
        final claimedStatus = reclaimed
            ? current.status
            : ScheduledEvaluationWorkStatus.leased;
        final next = current.withOperationalState(
          status: claimedStatus,
          workVersion: current.workVersion + 1,
          attemptCount: current.attemptCount + 1,
          notBefore: current.notBefore,
          leaseOwner: request.leaseOwner,
          leaseTokenDigest: prepared.tokenDigest,
          leaseAcquiredAt: now,
          leaseExpiresAt: now.add(request.leasePolicy.duration),
          updatedAt: now,
          lastAttemptAt: now,
          lastErrorClass: null,
          lastErrorCode: null,
        );
        await _pgUpdate(session, current.workVersion, next);
        final attempt = claimedAttempt(next, actorIdentity: request.leaseOwner);
        await _insertImmutable(
          session,
          table: 'control_plane_p3e5_attempts',
          idColumn: 'attempt_id',
          organizationId: next.logicalKey.organizationId,
          id: attempt.attemptId,
          body: attempt.toJson(),
          columns: <String, Object?>{
            'work_id': attempt.workId,
            'attempt_number': attempt.attemptNumber,
            'started_at': attempt.startedAt,
          },
        );
        result.add(
          P3e5ClaimedWork(
            work: next,
            rawLeaseToken: prepared.rawToken,
            reclaimed: reclaimed,
          ),
        );
      }
      claimFailure?.call(P3e5PostgresClaimFailurePoint.beforeCommit);
      return List.unmodifiable(result);
    });
    claimFailure?.call(P3e5PostgresClaimFailurePoint.afterCommit);
    return claims;
  }

  @override
  Future<P3e5ClaimedWork> reclaimAutomaticHalt(
    P3e5AutomaticHaltReclaimRequest request,
  ) async {
    final result = await _pool.runTx((session) async {
      final raw = await _readRawSession(
        session,
        'control_plane_p3e5_work',
        'work_id',
        request.scope.organizationId,
        request.workId,
        forUpdate: true,
      );
      if (raw == null) {
        throw const StorageConflict('Scheduled work was not found');
      }
      final current = ScheduledEvaluationWork.fromJson(raw);
      if (!request.scope.contains(current) ||
          current.workVersion != request.expectedWorkVersion) {
        throw const StorageConflict('Scheduled work version conflict');
      }
      final now = await _pgNow(session);
      if (current.status != ScheduledEvaluationWorkStatus.haltApplying ||
          current.automaticHaltIntent == null ||
          current.leaseExpiresAt == null ||
          current.leaseExpiresAt!.isAfter(now)) {
        throw const StorageConflict(
          'Automatic-halt work is not expired or no longer current',
        );
      }
      final next = current.withOperationalState(
        status: ScheduledEvaluationWorkStatus.haltApplying,
        workVersion: current.workVersion + 1,
        attemptCount: current.attemptCount,
        notBefore: current.notBefore,
        leaseOwner: request.leaseOwner,
        leaseTokenDigest: request.tokenDigest,
        leaseAcquiredAt: now,
        leaseExpiresAt: now.add(request.leasePolicy.duration),
        updatedAt: now,
        lastAttemptAt: now,
        lastErrorClass: null,
        lastErrorCode: null,
      );
      await _pgUpdate(session, current.workVersion, next);
      automaticHaltReclaimFailure?.call(
        P3e5AutomaticHaltReclaimFailurePoint.beforeCommit,
      );
      return P3e5ClaimedWork(
        work: next,
        rawLeaseToken: request.rawLeaseToken,
        reclaimed: true,
      );
    });
    automaticHaltReclaimFailure?.call(
      P3e5AutomaticHaltReclaimFailurePoint.afterCommit,
    );
    return result;
  }

  @override
  Future<P3e5WorkMutationResult> markAutomaticHaltStale(
    P3e5LeaseMutation lease,
  ) => _pgMutate(lease.scope, lease.workId, (session, current, now) async {
    _validateLease(
      current,
      lease,
      now,
      expectedStatus: ScheduledEvaluationWorkStatus.haltApplying,
    );
    return current.withOperationalState(
      status: ScheduledEvaluationWorkStatus.stale,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: current.notBefore,
      leaseOwner: null,
      leaseTokenDigest: null,
      leaseAcquiredAt: null,
      leaseExpiresAt: null,
      updatedAt: now,
      lastAttemptAt: current.lastAttemptAt,
      lastErrorClass: P3e5RetryClass.stale.wireName,
      lastErrorCode: 'AUTO_HALT_STALE',
      clearAutomaticHaltIntent: true,
    );
  });

  @override
  Future<P3e5WorkMutationResult> failClaim({
    required P3e5LeaseMutation lease,
    required P3e5RetryFailure failure,
    required P3e5RetryPolicy retryPolicy,
  }) => _pgMutate(lease.scope, lease.workId, (session, current, now) async {
    retryPolicy.validate();
    if (!_hasActiveLease(current.status)) {
      throw const StorageConflict('Work is not claim-side mutable');
    }
    _validateLease(current, lease, now, expectedStatus: current.status);
    final retryable = failure.classification == P3e5RetryClass.transient;
    final status = failure.classification == P3e5RetryClass.stale
        ? ScheduledEvaluationWorkStatus.stale
        : (!retryable || current.attemptCount >= retryPolicy.maximumAttempts)
        ? ScheduledEvaluationWorkStatus.failedPermanent
        : ScheduledEvaluationWorkStatus.retryWait;
    validateScheduledEvaluationTransition(current.status, status);
    return current.withOperationalState(
      status: status,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: status == ScheduledEvaluationWorkStatus.retryWait
          ? now.add(retryPolicy.delayFor(current.workId, current.attemptCount))
          : current.notBefore,
      leaseOwner: null,
      leaseTokenDigest: null,
      leaseAcquiredAt: null,
      leaseExpiresAt: null,
      updatedAt: now,
      lastAttemptAt: current.lastAttemptAt,
      lastErrorClass: failure.classification.wireName,
      lastErrorCode: failure.safeCode,
    );
  });

  @override
  Future<P3e5WorkMutationResult> cancelWork({
    required P3e5ClaimScope scope,
    required String workId,
    required int expectedWorkVersion,
  }) => _pgMutate(scope, workId, (session, current, now) async {
    _validateVersion(current, expectedWorkVersion);
    validateScheduledEvaluationTransition(
      current.status,
      ScheduledEvaluationWorkStatus.cancelled,
    );
    return current.withOperationalState(
      status: ScheduledEvaluationWorkStatus.cancelled,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: current.notBefore,
      leaseOwner: null,
      leaseTokenDigest: null,
      leaseAcquiredAt: null,
      leaseExpiresAt: null,
      updatedAt: now,
      lastAttemptAt: current.lastAttemptAt,
      lastErrorClass: current.lastErrorClass,
      lastErrorCode: current.lastErrorCode,
    );
  });

  @override
  Future<P3e5WorkMutationResult> manualRetry({
    required P3e5ClaimScope scope,
    required String workId,
    required int expectedWorkVersion,
    required P3e5RetryPolicy retryPolicy,
  }) => _pgMutate(scope, workId, (session, current, now) async {
    retryPolicy.validate();
    _validateVersion(current, expectedWorkVersion);
    validateScheduledEvaluationTransition(
      current.status,
      ScheduledEvaluationWorkStatus.retryWait,
    );
    if (!await _pgCurrentBinding(session, current)) {
      throw const StorageConflict('Work binding is stale');
    }
    return current.withOperationalState(
      status: ScheduledEvaluationWorkStatus.retryWait,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: now.add(
        retryPolicy.delayFor(current.workId, current.attemptCount + 1),
      ),
      leaseOwner: null,
      leaseTokenDigest: null,
      leaseAcquiredAt: null,
      leaseExpiresAt: null,
      updatedAt: now,
      lastAttemptAt: current.lastAttemptAt,
      lastErrorClass: null,
      lastErrorCode: null,
    );
  });

  @override
  Future<P3e5WorkMutationResult> advanceExecution(
    P3e5ExecutionAdvance advance,
  ) => _pgMutate(advance.lease.scope, advance.lease.workId, (
    session,
    current,
    now,
  ) async {
    _validateLease(
      current,
      advance.lease,
      now,
      expectedStatus: advance.expectedStatus,
    );
    validateScheduledEvaluationTransition(current.status, advance.nextStatus);
    final retainLease =
        advance.nextStatus == ScheduledEvaluationWorkStatus.evaluating ||
        advance.nextStatus == ScheduledEvaluationWorkStatus.evaluated ||
        advance.nextStatus == ScheduledEvaluationWorkStatus.haltApplying;
    return current.withOperationalState(
      status: advance.nextStatus,
      workVersion: current.workVersion + 1,
      attemptCount: current.attemptCount,
      notBefore: current.notBefore,
      leaseOwner: retainLease ? current.leaseOwner : null,
      leaseTokenDigest: retainLease ? current.leaseTokenDigest : null,
      leaseAcquiredAt: retainLease ? current.leaseAcquiredAt : null,
      leaseExpiresAt: retainLease ? current.leaseExpiresAt : null,
      updatedAt: now,
      lastAttemptAt: current.lastAttemptAt,
      lastErrorClass: null,
      lastErrorCode: null,
      linkedAggregateId: advance.aggregateId,
      linkedAggregateRevisionId: advance.aggregateRevisionId,
      linkedEvaluationId: advance.evaluationId,
      linkedDecisionId: advance.decisionId,
    );
  });

  @override
  Future<P3e5WorkMutationResult> applyAutomaticHaltIntent(
    P3e5AutomaticHaltIntentAdvance advance, {
    required Future<void> Function(
      DateTime authoritativeNow,
      ScheduledEvaluationWork currentWork,
    )
    validateCurrent,
  }) async {
    // The callback is a cross-store validator. PostgreSQL cannot safely call
    // it while holding this store's pool connection because the validator
    // reloads schedule rows through the public store seam. Run that reload
    // before the transaction, then repeat the schedule/work binding check in
    // the transaction itself. P3E-4/P3A performs the complete final reload
    // before any delivery-eligibility mutation.
    final preflight = await readWork(
      advance.authority.lease.scope.organizationId,
      advance.authority.workId,
    );
    if (preflight == null) {
      throw const StorageConflict('Scheduled work was not found');
    }
    if (preflight.status != ScheduledEvaluationWorkStatus.haltApplying) {
      final preflightNow = await _pool.runTx(_pgNow);
      await validateCurrent(preflightNow, preflight);
    }
    final result = await _pool.runTx((session) async {
      final raw = await _readRawSession(
        session,
        'control_plane_p3e5_work',
        'work_id',
        advance.authority.lease.scope.organizationId,
        advance.authority.workId,
        forUpdate: true,
      );
      if (raw == null) {
        throw const StorageConflict('Scheduled work was not found');
      }
      final current = ScheduledEvaluationWork.fromJson(raw);
      if (!advance.authority.lease.scope.contains(current)) {
        throw const StorageConflict('Scheduled work was not found');
      }
      if (current.status == ScheduledEvaluationWorkStatus.haltApplying) {
        if (current.automaticHaltIntent?.intentDigest ==
            advance.intent.intentDigest) {
          return P3e5WorkMutationResult(current, changed: false);
        }
        throw const StorageConflict('Automatic-halt intent conflict');
      }
      final now = await _pgNow(session);
      advance.authority.validateAt(now);
      _validateLease(
        current,
        advance.authority.lease,
        now,
        expectedStatus: ScheduledEvaluationWorkStatus.evaluated,
      );
      if (!await _pgCurrentBinding(session, current)) {
        throw const StorageConflict(
          'Scheduled automatic-halt binding is stale',
        );
      }
      final next = current.withOperationalState(
        status: ScheduledEvaluationWorkStatus.haltApplying,
        workVersion: current.workVersion + 1,
        attemptCount: current.attemptCount,
        notBefore: current.notBefore,
        leaseOwner: current.leaseOwner,
        leaseTokenDigest: current.leaseTokenDigest,
        leaseAcquiredAt: current.leaseAcquiredAt,
        leaseExpiresAt: current.leaseExpiresAt,
        updatedAt: now,
        lastAttemptAt: current.lastAttemptAt,
        lastErrorClass: null,
        lastErrorCode: null,
        linkedAutomaticHaltIntent: advance.intent,
      );
      await _pgUpdate(session, current.workVersion, next);
      automaticHaltFailure?.call(P3e5AutomaticHaltFailurePoint.beforeCommit);
      return P3e5WorkMutationResult(next, changed: true);
    });
    automaticHaltFailure?.call(P3e5AutomaticHaltFailurePoint.afterCommit);
    return result;
  }

  @override
  Future<P3e5WorkMutationResult> completeAutomaticHalt(
    P3e5AutomaticHaltCompletion completion,
  ) async {
    final result = await _pgMutate(
      completion.lease.scope,
      completion.lease.workId,
      (session, current, now) async {
        _validateAutomaticHaltCompletion(current, completion, now);
        final next = current.withOperationalState(
          status: ScheduledEvaluationWorkStatus.completed,
          workVersion: current.workVersion + 1,
          attemptCount: current.attemptCount,
          notBefore: current.notBefore,
          leaseOwner: null,
          leaseTokenDigest: null,
          leaseAcquiredAt: null,
          leaseExpiresAt: null,
          updatedAt: now,
          lastAttemptAt: current.lastAttemptAt,
          lastErrorClass: null,
          lastErrorCode: null,
          linkedHaltApplicationId: completion.haltApplicationId,
        );
        automaticHaltCompletionFailure?.call(
          P3e5AutomaticHaltCompletionFailurePoint.beforeCommit,
        );
        return next;
      },
    );
    automaticHaltCompletionFailure?.call(
      P3e5AutomaticHaltCompletionFailurePoint.afterCommit,
    );
    return result;
  }

  Future<P3e5WorkMutationResult> _pgMutate(
    P3e5ClaimScope scope,
    String workId,
    Future<ScheduledEvaluationWork> Function(
      Session session,
      ScheduledEvaluationWork current,
      DateTime now,
    )
    operation,
  ) async {
    await _disconnectIfRequested(
      PostgresDisconnectPoint.projectionCommitBefore,
    );
    final result = await _pool.runTx((session) async {
      final raw = await _readRawSession(
        session,
        'control_plane_p3e5_work',
        'work_id',
        scope.organizationId,
        workId,
        forUpdate: true,
      );
      if (raw == null)
        throw const StorageConflict('Scheduled work was not found');
      final current = ScheduledEvaluationWork.fromJson(raw);
      if (!scope.contains(current)) {
        throw const StorageConflict('Scheduled work was not found');
      }
      final next = await operation(session, current, await _pgNow(session));
      await _pgUpdate(session, current.workVersion, next);
      return P3e5WorkMutationResult(next, changed: true);
    });
    await _disconnectIfRequested(PostgresDisconnectPoint.projectionCommitAfter);
    return result;
  }

  Future<DateTime> _pgNow(Session session) async {
    final result = await session.execute('SELECT clock_timestamp() AS now');
    return (result.first.toColumnMap()['now'] as DateTime).toUtc();
  }

  Future<bool> _pgCurrentBinding(
    Session session,
    ScheduledEvaluationWork work,
  ) async {
    final schedule = await _readRawSession(
      session,
      'control_plane_p3e5_schedules',
      'schedule_id',
      work.logicalKey.organizationId,
      work.logicalKey.scheduleId,
    );
    final revision = await _readRawSession(
      session,
      'control_plane_p3e5_schedule_revisions',
      'schedule_revision_id',
      work.logicalKey.organizationId,
      work.logicalKey.scheduleRevisionId,
    );
    if (schedule == null || revision == null) return false;
    final current = EvaluationSchedule.fromJson(schedule);
    final bound = EvaluationScheduleRevision.fromJson(revision);
    if (current.currentScheduleRevision != bound.scheduleRevisionId ||
        !bound.scheduledEvaluationEnabled ||
        bound.scheduleGeneration != work.logicalKey.scheduleGeneration) {
      return false;
    }
    try {
      validateWorkBinding(work, current, bound);
      return true;
    } on FormatException {
      return false;
    }
  }

  Future<void> _pgUpdate(
    Session session,
    int expectedVersion,
    ScheduledEvaluationWork work,
  ) async {
    final result = await session.execute(
      Sql.named(
        'UPDATE control_plane_p3e5_work SET status=@status:text, '
        'work_version=@version:int8, attempt_count=@attempts:int8, '
        'body=@body:jsonb, updated_at=@updated:timestamptz, '
        'not_before=@notBefore:timestamptz, lease_expires_at=@leaseExpires:timestamptz '
        'WHERE organization_id=@organization:text AND work_id=@work:text '
        'AND work_version=@expected:int8',
      ),
      parameters: <String, Object?>{
        'status': work.status.wireName,
        'version': work.workVersion,
        'attempts': work.attemptCount,
        'body': work.toJson(),
        'updated': work.updatedAt,
        'notBefore': work.notBefore,
        'leaseExpires': work.leaseExpiresAt,
        'organization': work.logicalKey.organizationId,
        'work': work.workId,
        'expected': expectedVersion,
      },
    );
    if (result.affectedRows != 1) {
      throw const StorageConflict('Scheduled work version conflict');
    }
  }

  Future<void> _insertSchedule(Session session, EvaluationSchedule schedule) =>
      _insertImmutable(
        session,
        table: 'control_plane_p3e5_schedules',
        idColumn: 'schedule_id',
        organizationId: schedule.organizationId,
        id: schedule.scheduleId,
        body: schedule.toJson(),
        columns: <String, Object?>{
          'application_id': schedule.applicationId,
          'environment_id': schedule.environmentId,
          'rollout_id': schedule.rolloutId,
          'current_schedule_revision_id': schedule.currentScheduleRevision,
          'created_at': schedule.createdAt,
        },
      );

  Future<void> _insertRevision(
    Session session,
    EvaluationScheduleRevision revision,
  ) => _insertImmutable(
    session,
    table: 'control_plane_p3e5_schedule_revisions',
    idColumn: 'schedule_revision_id',
    organizationId: revision.organizationId,
    id: revision.scheduleRevisionId,
    body: revision.toJson(),
    columns: <String, Object?>{
      'application_id': revision.applicationId,
      'environment_id': revision.environmentId,
      'rollout_id': revision.rolloutId,
      'schedule_id': revision.scheduleId,
      'schedule_generation': revision.scheduleGeneration,
      'created_at': revision.createdAt,
    },
  );

  Future<void> _insertImmutable(
    Session session, {
    required String table,
    required String idColumn,
    required String organizationId,
    required String id,
    required Map<String, Object?> body,
    required Map<String, Object?> columns,
  }) async {
    final names = <String>[
      'organization_id',
      idColumn,
      ...columns.keys,
      'body',
    ];
    final parameters = <String, Object?>{
      'organization_id': organizationId,
      idColumn: id,
      ...columns,
      'body': body,
    };
    String placeholder(String name, Object? value) {
      if (value is int) return '@$name:int8';
      if (value is bool) return '@$name:boolean';
      if (value is DateTime) return '@$name:timestamptz';
      if (name == 'body') return '@body:jsonb';
      return '@$name:text';
    }

    await session.execute(
      Sql.named(
        'INSERT INTO $table (${names.join(', ')}) VALUES '
        '(${names.map((name) => placeholder(name, parameters[name])).join(', ')}) '
        'ON CONFLICT DO NOTHING',
      ),
      parameters: parameters,
    );
    final existing = await _readRawSession(
      session,
      table,
      idColumn,
      organizationId,
      id,
    );
    if (existing == null || canonicalJson(existing) != canonicalJson(body)) {
      throw const StorageConflict('Immutable P3E5 record already exists');
    }
  }

  Future<Map<String, Object?>?> _readRaw(
    String table,
    String idColumn,
    String organizationId,
    String id,
  ) => _readRawSession(_pool, table, idColumn, organizationId, id);

  Future<Map<String, Object?>?> _readRawSession(
    Session session,
    String table,
    String idColumn,
    String organizationId,
    String id, {
    bool forUpdate = false,
  }) async {
    final result = await session.execute(
      Sql.named(
        'SELECT body::text AS body_json FROM $table '
        'WHERE organization_id = @organization:text AND $idColumn = @id:text '
        '${forUpdate ? 'FOR UPDATE' : ''}',
      ),
      parameters: <String, Object?>{'organization': organizationId, 'id': id},
    );
    return result.isEmpty
        ? null
        : _decodeBody(result.first.toColumnMap()['body_json']);
  }

  Future<List<T>> _list<T>(
    String table,
    String idColumn,
    String organizationId,
    T Function(Object?) decode,
  ) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT body::text AS body_json FROM $table '
        'WHERE organization_id = @organization:text ORDER BY $idColumn',
      ),
      parameters: <String, Object?>{'organization': organizationId},
    );
    return List.unmodifiable(
      result.map((row) => decode(_decodeBody(row.toColumnMap()['body_json']))),
    );
  }
}

Map<String, Object?> _bundle(
  EvaluationSchedule schedule,
  List<EvaluationScheduleRevision> revisions,
) => <String, Object?>{
  'schemaVersion': p3e5ScheduleSchemaVersion,
  'schedule': schedule.toJson(),
  'revisions': revisions.map((item) => item.toJson()).toList(growable: false),
};

List<EvaluationScheduleRevision> _decodeRevisions(Object? value) {
  if (value is! List<Object?>)
    throw const FormatException('Invalid schedule revisions');
  final revisions = value.map(EvaluationScheduleRevision.fromJson).toList();
  for (var index = 0; index < revisions.length; index++) {
    if (revisions[index].scheduleGeneration != index + 1) {
      throw const FormatException(
        'Schedule revision history is not contiguous',
      );
    }
  }
  return revisions;
}

List<AutomaticHaltPolicy> _decodeAutomaticHaltPolicies(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('Invalid automatic-halt policies');
  }
  return value.map(AutomaticHaltPolicy.fromJson).toList(growable: true);
}

List<AutomaticHaltEnvironmentState> _decodeAutomaticHaltStates(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('Invalid automatic-halt states');
  }
  final states = value
      .map(AutomaticHaltEnvironmentState.fromJson)
      .toList(growable: true);
  for (var index = 0; index < states.length; index++) {
    if (states[index].generation != index + 1 ||
        (index > 0 &&
            states[index].supersedesStateId != states[index - 1].stateId)) {
      throw const FormatException(
        'Automatic-halt state history is not contiguous',
      );
    }
  }
  return states;
}

({
  List<AutomaticHaltPolicy> policies,
  List<AutomaticHaltEnvironmentState> states,
})
_decodeAutomaticHaltBundle(
  Map<String, Object?>? value,
  String organizationId, {
  String? applicationId,
  String? environmentId,
}) {
  if (value == null) {
    return (
      policies: <AutomaticHaltPolicy>[],
      states: <AutomaticHaltEnvironmentState>[],
    );
  }
  if (value.length != 3 ||
      value['entityVersion'] != automaticHaltEntityVersion ||
      !value.containsKey('policies') ||
      !value.containsKey('states')) {
    throw const FormatException('Invalid automatic-halt bundle');
  }
  final policies = _decodeAutomaticHaltPolicies(value['policies']);
  final states = _decodeAutomaticHaltStates(value['states']);
  if (states.isNotEmpty && policies.isEmpty) {
    throw const FormatException('Automatic-halt state has no policy');
  }
  final boundApplication =
      applicationId ??
      (policies.isNotEmpty ? policies.first.applicationId : null);
  final boundEnvironment =
      environmentId ??
      (policies.isNotEmpty ? policies.first.environmentId : null);
  final byId = <String, AutomaticHaltPolicy>{};
  for (final policy in policies) {
    if (policy.organizationId != organizationId ||
        policy.applicationId != boundApplication ||
        policy.environmentId != boundEnvironment ||
        byId.containsKey(policy.policyId)) {
      throw const FormatException(
        'Automatic-halt policy bundle scope is invalid',
      );
    }
    byId[policy.policyId] = policy;
  }
  for (final state in states) {
    final policy = byId[state.policyId];
    if (state.organizationId != organizationId ||
        state.applicationId != boundApplication ||
        state.environmentId != boundEnvironment ||
        policy == null ||
        policy.digest != state.automaticHaltPolicyDigest) {
      throw const FormatException(
        'Automatic-halt state bundle scope is invalid',
      );
    }
  }
  return (policies: policies, states: states);
}

void _validateAutomaticHaltFoundation(
  AutomaticHaltPolicy policy,
  AutomaticHaltEnvironmentState state,
) {
  if (state.organizationId != policy.organizationId ||
      state.applicationId != policy.applicationId ||
      state.environmentId != policy.environmentId ||
      state.policyId != policy.policyId ||
      state.automaticHaltPolicyDigest != policy.digest) {
    throw const StorageConflict(
      'Automatic-halt policy and state binding is invalid',
    );
  }
}

Map<String, Object?> _decode(Object? value, String label) {
  final decoded = value is String ? jsonDecode(value) : value;
  if (decoded is! Map) throw FormatException('Invalid $label');
  return decoded.map<String, Object?>((key, item) {
    if (key is! String) throw FormatException('Invalid $label key');
    return MapEntry(key, item);
  });
}

Map<String, Object?> _decodeBody(Object? value) =>
    _decode(value, 'PostgreSQL body');

void _equalOrAbsent(
  Map<String, Object?>? existing,
  Map<String, Object?> incoming,
  String message,
) {
  if (existing != null && canonicalJson(existing) != canonicalJson(incoming)) {
    throw StorageConflict(message);
  }
}

Future<List<P3e5ConsistencyIssue>> _validateValues(
  String organizationId,
  List<EvaluationSchedule> schedules,
  List<ScheduledEvaluationWork> work,
  P3e5ScheduleStore store,
) async {
  final issues = <P3e5ConsistencyIssue>[];
  final schedulesById = <String, EvaluationSchedule>{
    for (final schedule in schedules) schedule.scheduleId: schedule,
  };
  for (final schedule in schedules) {
    final revisions = await store.listRevisions(
      organizationId,
      schedule.scheduleId,
    );
    if (revisions.isEmpty ||
        revisions.last.scheduleRevisionId != schedule.currentScheduleRevision) {
      issues.add(
        P3e5ConsistencyIssue(
          'schedule',
          schedule.scheduleId,
          'INVALID_CURRENT_REVISION',
        ),
      );
      continue;
    }
    for (final revision in revisions) {
      try {
        validateScheduleRevisionBinding(schedule, revision);
      } on Object {
        issues.add(
          P3e5ConsistencyIssue(
            'revision',
            revision.scheduleRevisionId,
            'SCOPE_MISMATCH',
          ),
        );
      }
    }
  }
  for (final item in work) {
    final schedule = schedulesById[item.logicalKey.scheduleId];
    final revision = await store.readRevision(
      organizationId,
      item.logicalKey.scheduleRevisionId,
    );
    if (schedule == null || revision == null) {
      issues.add(
        P3e5ConsistencyIssue('work', item.workId, 'MISSING_SCHEDULE_REVISION'),
      );
      continue;
    }
    try {
      validateWorkBinding(item, schedule, revision);
    } on Object {
      issues.add(P3e5ConsistencyIssue('work', item.workId, 'BINDING_MISMATCH'));
    }
    for (final attempt in await store.listAttempts(
      organizationId,
      item.workId,
    )) {
      if (attempt.workId != item.workId) {
        issues.add(
          P3e5ConsistencyIssue('attempt', attempt.attemptId, 'WORK_MISMATCH'),
        );
      }
    }
  }
  return List.unmodifiable(issues);
}

bool _isClaimCandidate(ScheduledEvaluationWork work, DateTime now) =>
    ((work.status == ScheduledEvaluationWorkStatus.pending ||
            work.status == ScheduledEvaluationWorkStatus.retryWait) &&
        !work.notBefore.isAfter(now)) ||
    (_hasActiveLease(work.status) &&
        work.status != ScheduledEvaluationWorkStatus.haltApplying &&
        !work.leaseExpiresAt!.isAfter(now));

bool _hasActiveLease(ScheduledEvaluationWorkStatus status) =>
    status == ScheduledEvaluationWorkStatus.leased ||
    status == ScheduledEvaluationWorkStatus.evaluating ||
    status == ScheduledEvaluationWorkStatus.evaluated ||
    status == ScheduledEvaluationWorkStatus.haltApplying;

int _compareClaimCandidates(
  ScheduledEvaluationWork left,
  ScheduledEvaluationWork right,
) {
  final due = left.notBefore.compareTo(right.notBefore);
  return due != 0 ? due : left.workId.compareTo(right.workId);
}

List<ScheduledEvaluationWork> _fairCandidates(
  Iterable<ScheduledEvaluationWork> candidates,
  int limit,
) {
  final groups = <String, List<ScheduledEvaluationWork>>{};
  for (final candidate in candidates) {
    groups
        .putIfAbsent(candidate.logicalKey.scheduleId, () => [])
        .add(candidate);
  }
  for (final values in groups.values) {
    values.sort(_compareClaimCandidates);
  }
  final keys = groups.keys.toList()..sort();
  final result = <ScheduledEvaluationWork>[];
  var offset = 0;
  while (result.length < limit) {
    var added = false;
    for (final key in keys) {
      final values = groups[key]!;
      if (offset < values.length) {
        result.add(values[offset]);
        added = true;
        if (result.length == limit) break;
      }
    }
    if (!added) break;
    offset++;
  }
  return result;
}

void _validateVersion(ScheduledEvaluationWork work, int expectedVersion) {
  if (expectedVersion < 0 || work.workVersion != expectedVersion) {
    throw const StorageConflict('Scheduled work version conflict');
  }
}

void _validateLease(
  ScheduledEvaluationWork work,
  P3e5LeaseMutation lease,
  DateTime now, {
  ScheduledEvaluationWorkStatus expectedStatus =
      ScheduledEvaluationWorkStatus.leased,
}) {
  _validateVersion(work, lease.expectedWorkVersion);
  if (!lease.scope.contains(work) ||
      work.status != expectedStatus ||
      work.leaseOwner != lease.leaseOwner ||
      work.leaseTokenDigest != lease.tokenDigest ||
      !work.leaseExpiresAt!.isAfter(now)) {
    throw const StorageConflict('Lease ownership is invalid or expired');
  }
}

void _validateAutomaticHaltCompletion(
  ScheduledEvaluationWork current,
  P3e5AutomaticHaltCompletion completion,
  DateTime now,
) {
  _validateLease(
    current,
    completion.lease,
    now,
    expectedStatus: ScheduledEvaluationWorkStatus.haltApplying,
  );
  final intent = current.automaticHaltIntent;
  if (intent == null ||
      current.haltApplicationId != null &&
          current.haltApplicationId != completion.haltApplicationId ||
      intent.intentDigest != completion.intentDigest ||
      intent.evaluationId != completion.evaluationId ||
      intent.decisionId != completion.decisionId ||
      intent.expectedRolloutRevision != completion.previousRolloutRevision ||
      completion.resultingRolloutRevision !=
          completion.previousRolloutRevision + 1 ||
      completion.idempotencyKey != current.logicalKey.haltIdempotencyKey) {
    throw const StorageConflict(
      'Automatic-halt completion evidence is not linked to current work',
    );
  }
}
