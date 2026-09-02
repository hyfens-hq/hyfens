import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  test('state machine accepts only explicit lifecycle transitions', () {
    expect(
      nextRolloutState(RolloutState.draft, RolloutAction.ready),
      RolloutState.ready,
    );
    expect(
      nextRolloutState(RolloutState.ready, RolloutAction.startCanary),
      RolloutState.canary,
    );
    expect(
      nextRolloutState(RolloutState.internal, RolloutAction.startCanary),
      RolloutState.canary,
    );
    expect(
      nextRolloutState(RolloutState.canary, RolloutAction.expand),
      RolloutState.expanding,
    );
    expect(
      nextRolloutState(
        RolloutState.paused,
        RolloutAction.resume,
        pausedFromState: RolloutState.canary,
      ),
      RolloutState.canary,
    );
    expect(
      nextRolloutState(RolloutState.completed, RolloutAction.pause),
      isNull,
    );
    expect(nextRolloutState(RolloutState.ready, RolloutAction.resume), isNull);
  });

  test('percentage cohorts are deterministic and monotonic', () {
    final fivePercent = _revision(percentageBasisPoints: 500);
    final tenPercent = _revision(percentageBasisPoints: 1000);
    final installations = List<String>.generate(
      200,
      (index) => 'install-$index',
    );
    for (final installation in installations) {
      final five = RolloutEligibility.isEligible(
        revision: fivePercent,
        installationId: installation,
      );
      final ten = RolloutEligibility.isEligible(
        revision: tenPercent,
        installationId: installation,
      );
      if (five) expect(ten, isTrue);
      expect(
        RolloutEligibility.bucketFor(
          revision: fivePercent,
          installationId: installation,
        ),
        RolloutEligibility.bucketFor(
          revision: fivePercent,
          installationId: installation,
        ),
      );
    }
    final zero = _revision(percentageBasisPoints: 0);
    final all = _revision(percentageBasisPoints: 10000);
    expect(
      installations.any(
        (installation) => RolloutEligibility.isEligible(
          revision: zero,
          installationId: installation,
        ),
      ),
      isFalse,
    );
    expect(
      installations.every(
        (installation) => RolloutEligibility.isEligible(
          revision: all,
          installationId: installation,
        ),
      ),
      isTrue,
    );
    expect(RolloutEligibility.thresholdFor(0), BigInt.zero);
    expect(RolloutEligibility.thresholdFor(10000), BigInt.one << 64);
  });

  test('internal cohorts compare only hashed installation identifiers', () {
    final installation = 'internal-installation';
    final revision = _revision(
      cohortKind: RolloutCohortKind.internal,
      internalInstallationHashes: <String>[
        RolloutEligibility.installationHash(installation),
      ],
    );
    expect(
      RolloutEligibility.isEligible(
        revision: revision,
        installationId: installation,
      ),
      isTrue,
    );
    expect(
      RolloutEligibility.isEligible(
        revision: revision,
        installationId: 'different-installation',
      ),
      isFalse,
    );
    expect(revision.policy.toJson()['internalInstallationHashes'], <String>[
      RolloutEligibility.installationHash(installation),
    ]);
  });

  test('domain decoding rejects unknown or malformed fields', () {
    final value = _revision().toJson();
    expect(
      () => RolloutRevision.fromJson(<String, Object?>{
        ...value,
        'unknown': true,
      }),
      throwsFormatException,
    );
    expect(
      () => RolloutPolicy(
        cohortKind: RolloutCohortKind.percentage,
        percentageBasisPoints: 10001,
        salt: 'salt_test',
      ),
      throwsFormatException,
    );
    expect(
      () => RolloutPolicy(
        cohortKind: RolloutCohortKind.internal,
        percentageBasisPoints: 0,
        salt: 'salt_test',
      ),
      throwsFormatException,
    );
    expect(
      () => RolloutPolicy(
        cohortKind: RolloutCohortKind.internal,
        percentageBasisPoints: 100,
        salt: 'salt_test',
        internalInstallationHashes: <String>{
          RolloutEligibility.installationHash('internal-installation'),
        },
      ),
      throwsFormatException,
    );
    expect(
      () => RolloutTarget(
        organizationId: 'org_test',
        applicationId: 'app_test',
        environmentId: 'env_test',
        platformId: 'plt_android',
        releaseId: 'rel_test',
        runtimeReleaseId: 'runtime-release-test',
        patchId: 'pat_test',
        runtimePatchId: 'runtime-patch-test',
        artifactId: 'art_test',
        sha256: 'sha256:invalid',
        sequence: 1,
      ),
      throwsFormatException,
    );
  });
}

RolloutRevision _revision({
  int percentageBasisPoints = 10000,
  RolloutCohortKind cohortKind = RolloutCohortKind.percentage,
  Iterable<String> internalInstallationHashes = const <String>[],
}) => RolloutRevision(
  id: 'rvr_test',
  rolloutId: 'rol_test',
  organizationId: 'org_test',
  revision: 1,
  previousRevision: null,
  state: cohortKind == RolloutCohortKind.internal
      ? RolloutState.internal
      : RolloutState.canary,
  target: RolloutTarget(
    organizationId: 'org_test',
    applicationId: 'app_test',
    environmentId: 'env_test',
    platformId: 'plt_android',
    releaseId: 'rel_test',
    runtimeReleaseId: 'runtime-release-test',
    patchId: 'pat_test',
    runtimePatchId: 'runtime-patch-test',
    artifactId: 'art_test',
    sha256: 'sha256:0000000000000000000000000000000000000000000000000000000000000000',
    sequence: 1,
  ),
  policy: RolloutPolicy(
    cohortKind: cohortKind,
    percentageBasisPoints: cohortKind == RolloutCohortKind.internal
        ? 0
        : percentageBasisPoints,
    salt: 'salt_test',
    internalInstallationHashes: internalInstallationHashes,
  ),
  actorId: 'cred_test',
  reason: 'test',
  pausedFromState: null,
  createdAt: DateTime.utc(2026, 8, 23),
);
