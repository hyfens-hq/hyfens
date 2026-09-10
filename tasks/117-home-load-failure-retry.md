# Task 117 — Home load failure and retry recovery

Status: [x] Completed

## Goal

Verify the Waypoint app renders its home-load error state and recovers to the
real home content when the user taps the production retry action.

## Scope and Non-goals

Scope:

- add a test-only data source that fails the first home load and succeeds on a
  later load using the existing local fixture payload;
- open `WaypointApp` through the existing provider override seam;
- assert the error UI and `waypoint-retry` key after the first failure;
- tap retry and assert the normal Discover content returns.

Non-goals:

- changing production loading, caching, retry, or network behavior;
- real network, Docker, AWS, hosted deployment, device, or simulator work;
- broad error-state refactoring or new dependencies;
- claiming remote-service reliability from a test-only data source.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Task 99 Waypoint app and current test harness;
- `WaypointDataSource`, `WaypointRepository`, and provider override seam;
- existing local fixture home payload.

## Assumptions

- a small test-only fail-once source is sufficient to exercise the production
  error/retry path;
- the helper class should live in its own test support file if added;
- affected validation is limited to the changed test and test-support files.

## Work Items

- [x] Inspect the actual home notifier/error/retry path and test harness.
- [x] Add a controlled test-only fail-once data source and recovery test.
- [x] Review the task-owned diff for scope and factual correctness.
- [x] Run only formatting and the affected app test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next instruction.

## Validation

Planned affected-file validation only:

- `dart format --output=none --set-exit-if-changed` on the changed test files
  completed with `Formatted 2 files (0 changed)`;
- `flutter test test/waypoint_app_test.dart` from
  `fixtures/flutter_conformance_app`;
- result: `00:05 +12: All tests passed!`;
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Next Action

Task 117 is complete. Reserve the next local-only task for search/filter
resilience: empty results, clearing the query, and search-error retry. Do not
claim remote-service reliability.

## Blockers

None known.

## Outcome

The worker added the test-only
`fixtures/flutter_conformance_app/test/waypoint_retry_data_source.dart` and a
focused test in `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
The test proves one initial home-load failure, the production error message and
`waypoint-retry` key, then a successful retry rendering Discover and
`Kyoto, Japan`. Formatting made no changes and the affected app-test file
passed with twelve tests. Strict review accepted the implementation with no
blocking findings.

## References

- `tasks/116-settings-refreshed-permanent-denial-remaining.md`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_home_notifier.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`

## History

- 2026-08-29: Reserved Task 117 from the read-only app-gap assessment. This is
  the first non-permission, non-AWS local gap selected because the production
  error/retry branch is present but lacks a recovery test.
- 2026-08-29: Meitner the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  added the fail-once data source and recovery test in the owned test scope.
  The worker reported `Formatted 2 files (0 changed)` and `00:05 +12: All tests passed!`.
  No production or external-service files were changed.
- 2026-08-29: Sagan the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  reviewed the test-only data-source interface, fail-once behavior, provider
  override, production error/retry wiring, recovery assertions, and validation.
  Result: `ACCEPT`, with no blocking findings. The reviewer recommended local
  search/filter resilience coverage next.
