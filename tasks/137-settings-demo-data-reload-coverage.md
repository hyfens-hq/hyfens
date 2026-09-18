# Task 137 — Settings demo-data reload coverage

Status: [x] Completed

## Goal

Prove that Settings' Reload demo data action fetches a changed local home
payload and that Discover renders the refreshed destination set.

## Scope and Non-goals

Scope:

- add one focused app widget test using a mutable `WaypointTestDataSource`;
- open Settings through the existing header action;
- mutate the injected in-memory home payload after the initial load;
- activate the real `waypoint-settings-reload` control;
- return to Discover and verify a second home read plus the new destination.

Non-goals:

- changing production reload, repository, decoding, persistence, or error
  handling behavior;
- adding reload failure/retry coverage already covered by Task 117;
- changing search, navigation, permissions, appearance, planner, Discover,
  Saved, Trips, or Activity behavior;
- changing test support, dependencies, assets, Docker, AWS, hosting, device,
  simulator, or deployment configuration.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 136 appearance-mode coverage;
- existing `waypoint-settings-reload` key and `WaypointHomeNotifier.reload`;
- existing mutable `WaypointTestDataSource(home: ...)` seam;
- existing header Settings action and bottom navigation.

## Assumptions

- mutating the injected fixture map models a later local `/api/home` response;
  it makes no persistence or remote-service claim;
- the default Discover state has no active search query, so refreshed
  destination visibility can be asserted directly;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- affected validation is limited to formatting that test file and running that
  changed app widget test file.

## Work Items

- [x] Inspect the Settings reload control, home notifier, mutable fixture seam,
  and current tests.
- [x] Add focused local demo-data reload widget coverage.
- [x] Review the task-owned test change for factual assertions and scope.
- [x] Run only formatting and the changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next source-based instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart`;
- worker and strict reviewer reported formatting with one file and zero
  changes, and the app test passing all twenty-nine tests (`+29`);
- coordinator post-review validation: `dart format --output=none
  --set-exit-if-changed test/waypoint_app_test.dart` reported one file with
  zero changes;
- coordinator post-review validation: `flutter test
  test/waypoint_app_test.dart` exited 0 with all twenty-nine tests passing
  (`+29`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and the named repository file is untracked,
so Git cannot provide historical diff provenance. The coordinator verified the
Task 137 scope directly:

- app widget test path:
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
  SHA-256 `c3b333af47156b5b8a59c4b08525e2162b284e4559631262a10e1990b81ed77d`;
- the app test source contains exactly twenty-nine `testWidgets` cases;
- the task-owned status is limited to this test path and this task record; no
  production, support, or unrelated file was modified by the package.

## Next Action

Task 137 is complete. Reserve the next numbered package only after a fresh
source inspection identifies the next bounded local capability.

## Blockers

None known.

## Outcome

The isolated Settings reload test mutates a local home payload after initial
load, activates the real reload control, proves exactly two `/api/home` reads,
and verifies the refreshed Reykjavik destination on Discover. The worker,
strict reviewer, and coordinator validation all report twenty-nine app widget
tests passing. Strict review returned `ACCEPT` with no blocking findings. The
only limitation recorded is the checkout's missing Git `HEAD` and untracked-
file state.

## References

- `tasks/136-waypoint-appearance-mode-coverage.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_settings_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_home_notifier.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Reserved after Averroes the 2nd's source review. Settings
  exposes `waypoint-settings-reload`, which calls the existing home notifier
  reload path, and the test source accepts a mutable home payload, but no test
  proves a changed local response reaches Discover. Scope is limited to the
  existing app widget test file.
- 2026-08-29: Parfit the 2nd (GPT-5.6 Luna Max, max reasoning, priority) added
  one focused reload test in the owned app widget test. The worker reported
  scoped formatting with zero changes and twenty-nine app tests passing. No
  production, support, or task file was modified.
- 2026-08-29: Zeno the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  independently reviewed the mutable local payload, exact two-home-read
  assertion, deterministic reload wait, refreshed Reykjavik visibility, and
  one-file scope. Result: `ACCEPT`; no blocking findings or fixes required.
  The only limitation recorded is the checkout's missing Git `HEAD` and
  untracked-file state.
- 2026-08-29: Coordinator final validation passed: scoped formatting reported
  one file with zero changes, and `flutter test test/waypoint_app_test.dart`
  passed all twenty-nine tests. Task 137 is complete; no production, device,
  simulator, Docker, AWS, or hosted-service validation was needed.
