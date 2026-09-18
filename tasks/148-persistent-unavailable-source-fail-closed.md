# Task 148 — Persistent unavailable source remains fail-closed

Status: [x] Completed

## Goal

Prove locally that a permanently unavailable data source remains visible as an
error after retry and never falls back to demo content.

## Scope and Non-goals

Scope:

- add exactly one local app widget test to the existing Waypoint app test file;
- inject the existing `WaypointUnavailableDataSource` through the current
  repository override;
- verify the error page, retry action, and absence of Discover/demo content
  before and after retry;
- verify the same configured-source error remains visible after retry.

Non-goals:

- changing production code, bootstrap behavior, retry policy, backoff,
  telemetry, error copy, repository contracts, support fixtures, dependencies,
  assets, or integration tests;
- testing network, devices, simulators, Docker, AWS, hosting, or deployment;
- claiming online-provider behavior or adding a replacement data source;
- adding more than one test or changing unrelated test files.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 147 fresh planner state on default re-entry;
- existing `WaypointUnavailableDataSource` fail-closed implementation;
- existing `_WaypointErrorPage` retry UI;
- existing `WaypointRepository` and `pumpWaypointTestApp` override seams;
- existing fail-once home-error recovery test for contrast.

## Assumptions

- `WaypointUnavailableDataSource` returns the same failure for every read, so
  retry remains deterministic and cannot reveal demo data;
- the existing app shell maps the failed home provider to the error page and
  invokes its reload callback from `waypoint-retry`;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- a production defect exposed by the test is reported rather than expanding
  this test-only package.

## Work Items

- [x] Inspect the unavailable data source, shell error/retry path, existing
  fail-once coverage, and prior task boundaries.
- [x] Add exactly one persistent-failure widget regression test in the existing
  app test file.
- [x] Review the owned test for exact fail-closed assertions, deterministic
  retry behavior, and scope.
- [x] Run only formatting, scoped analysis, the named widget test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome, validation evidence, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_app_test.dart`;
- `flutter analyze test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"persistent unavailable data source remains visible after retry"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: formatting reported one file
  and zero changes; scoped analysis reported no issues; the named regression
  test passed once; and the full app widget test passed all thirty-nine tests.
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the intended one-file write set and final
observations directly:

- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` — SHA-256
  `108031f88610a6ae4d77a7c9aed8f0518292fb3f5ae9949be48adacdb3915d93`
- `testWidgets` declarations in `waypoint_app_test.dart` — `39`, including
  exactly one Task-148-named case.

The worker reported no other implementation paths changed; the missing Git
baseline is retained as an explicit provenance limitation.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. The existing permanently unavailable data source now has one local
widget regression test proving that the real shell shows its configured error,
offers retry, and remains fail-closed with no Discover or Kyoto demo content
after retry. No production, dependency, fixture, platform, external-service,
or deployment behavior changed.

## References

- `tasks/99-waypoint-demo-app.md`
- `tasks/146-latest-search-result-wins.md`
- `tasks/147-fresh-planner-state-on-reentry.md`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`

## History

- 2026-08-29: Descartes the 3rd performed a read-only source audit after Task
  147. The audit found that the production unavailable data source fails every
  read, the shell exposes a retry action, and current coverage only verifies a
  fail-once source recovering to Discover. Task 148 is limited to one local
  persistent-failure widget test; no production change or external validation
  is required.
- 2026-08-29: Ptolemy the 3rd added exactly one persistent-failure widget test
  in the reserved app test file. The worker reported formatting, scoped
  analysis, the named test, and the full app widget test passing with thirty-
  nine tests.
- 2026-08-29: Turing the 3rd strictly reviewed the test and returned ACCEPT.
  The review verified the existing unavailable-source seam, real retry path,
  exact error and no-content assertions before and after retry, deterministic
  pumps, one-test scope, and the recorded provenance limitation.
- 2026-08-29: Coordinator reran the planned changed-file validation: format
  exited 0 with one file unchanged, scoped analysis exited 0 with no issues,
  the named test passed once, and the full app widget test exited 0 with all
  thirty-nine tests passing.
