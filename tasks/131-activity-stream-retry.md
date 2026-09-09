# Task 131 — Activity stream error recovery and retry

Status: [x] Completed

## Goal

Preserve a real Activity stream failure in the UI and provide an explicit
retry action that recovers on the next local stream attempt.

## Scope and Non-goals

Scope:

- preserve non-cancellation errors in `WaypointActivityNotifier` instead of
  replacing them with success data during cleanup;
- add a keyed retry control to `WaypointActivityPage` for the error state;
- add a fail-once in-memory data source wrapper for the widget harness;
- prove the local failure, visible error, retry, and recovered Activity item in
  the existing app widget test.

Non-goals:

- changing the Activity API, stream protocol, cancellation contract, or
  repository implementation;
- adding persistence, networking, AWS, hosted services, Docker, device, or
  simulator work;
- changing unrelated pages, navigation behavior, or test files;
- replacing the existing start/stop feed behavior with a broader streaming
  redesign.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- existing Activity notifier and page;
- existing `WaypointDataSource` abstraction and in-memory test source;
- existing `pumpWaypointTestApp` provider overrides;
- completed Activity navigation coverage from Task 130.

## Assumptions

- `WaypointActivityNotifier.start` is the only production path that needs
  error-state preservation for this package;
- the fail-once source is test-only and will delegate all non-Activity routes
  to the existing successful source;
- the worker owns only these four paths:
  `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_activity_notifier.dart`,
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_activity_page.dart`,
  `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`, and
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- affected validation is limited to formatting those files and the changed app
  widget test file.

## Work Items

- [x] Inspect the Activity stream lifecycle, error rendering, and test seam.
- [x] Preserve non-cancellation Activity errors through notifier cleanup.
- [x] Add an explicit Activity error-state retry control.
- [x] Add a local fail-once Activity data source and recovery widget test.
- [x] Review the task-owned diff for correctness, scope, and regressions.
- [x] Run only formatting and the changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next source-based instruction.

## Validation

Planned affected-file validation only:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/application/waypoint_activity_notifier.dart`
  `lib/waypoint/presentation/screens/waypoint_activity_page.dart`
  `test/waypoint_test_support.dart`
  `test/waypoint_app_test.dart` from `fixtures/flutter_conformance_app`;
- `flutter test test/waypoint_app_test.dart` from
  `fixtures/flutter_conformance_app`;
- result: `dart format --output=none --set-exit-if-changed` reported four files
  with zero changes;
- result: `flutter test test/waypoint_app_test.dart` exited 0 with all
  twenty-three tests passing (`+23`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and the named repository files are untracked,
so Git cannot provide historical diff provenance. The coordinator verified the
Task 131 scope directly:

- production notifier path:
  `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_activity_notifier.dart`;
  SHA-256 `f9036714869ee3c1bddf0957dff138fad28c18faf379b901e773de8b0f30bec7`;
- production Activity page path:
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_activity_page.dart`;
  SHA-256 `6e6df90054e746cd9382b204b1f6fb7a654349774dd99bba273b14df0b6fb7dd`;
- test support path:
  `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`;
  SHA-256 `e69b02aeeaa6e256f5240f7f39998095ed1cf1da7e148796be1e4d8eb683f520`;
- app widget test path:
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
  SHA-256 `497585226f38110c593086b0da5d69a7e7e91902fc20b364be8ea7f00710efcb`;
- the app test source contains exactly twenty-three `testWidgets` cases;
- the only task-owned paths reported by `git status` are these four source/test
  files and this task record; no unrelated file was modified by this package.

## Next Action

Task 131 is complete. Reserve the next local-only package only after a fresh
source inspection identifies the next bounded Activity, Trips, or dashboard
capability.

## Blockers

None known.

## Outcome

The four-path implementation preserves non-cancellation Activity errors,
provides a keyed retry action, and verifies fail-once local recovery to the
existing Kyoto activity item. The worker, strict reviewer, and coordinator
validation all report twenty-three app widget tests passing. Strict review
returned `ACCEPT` with no blocking findings. The reviewer’s only observation
was non-blocking: the injected fail-once error does not check cancellation and
should be revisited before that fixture is reused for cancellation coverage.

## References

- `tasks/130-wide-rail-activity-coverage.md`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_activity_notifier.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_activity_page.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Reserved after Task 130 strict acceptance. Source inspection
  confirmed that non-cancellation Activity errors are assigned and then
  overwritten by the notifier's unconditional cleanup state, while the page
  has no explicit retry action.
- 2026-08-29: Ohm the 2nd (GPT-5.6 Luna Max, max reasoning, priority) updated
  only the four owned paths: notifier error preservation, page retry control,
  fail-once Activity fixture, and the focused recovery widget test. The worker
  reported scoped formatting with zero changes and twenty-three app tests
  passing. No task file was modified.
- 2026-08-29: Socrates the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  independently reviewed the notifier cleanup guard, keyed retry handler,
  fail-once delegation, recovery assertions, and four-path scope. Result:
  `ACCEPT`; no blocking findings or fixes required. The reviewer noted only
  that the injected fail-once error does not check cancellation before it is
  emitted, which is non-blocking for this fresh-token recovery test and should
  be considered before reusing that fixture for cancellation coverage.
- 2026-08-29: Coordinator final validation passed: scoped formatting reported
  four files with zero changes, and `flutter test test/waypoint_app_test.dart`
  passed all twenty-three tests. Task 131 is complete; no device, simulator,
  Docker, AWS, or hosted-service validation was needed.
