# Task 136 — Waypoint appearance-mode coverage

Status: [x] Completed

## Goal

Verify the Settings appearance control applies the System and Light theme
modes, while preserving the existing Dark assertion.

## Scope and Non-goals

Scope:

- add one isolated app widget test using the existing local harness;
- open Settings through the real header action;
- verify the appearance control starts on System;
- select Light and assert `MaterialApp.themeMode == ThemeMode.light`;
- select System and assert `MaterialApp.themeMode == ThemeMode.system`;
- preserve the existing Dark mode assertion.

Non-goals:

- changing production theme, settings, state, persistence, or UI code;
- asserting the host's resolved brightness for `ThemeMode.system`;
- color redesign, OS settings, device interaction, or platform-specific theme
  behavior;
- changing permissions, navigation, planner, Discover, Saved, Trips, or
  Activity behavior;
- changing dependencies, assets, test support, Docker, AWS, hosting, or
  deployment configuration.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 135 prefilled planner submission coverage;
- existing `waypoint-theme-choice` `SegmentedButton`;
- existing `WaypointUiNotifier.setThemeChoice` mapping;
- existing `pumpWaypointTestApp` local fixture;
- existing `MaterialApp.themeMode` assertion in the settings test.

## Assumptions

- the default `WaypointUiState.themeChoice` is System;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- affected validation is limited to formatting that test file and running that
  changed app widget test file.

## Work Items

- [x] Inspect the Settings segments, theme-state mapping, app wiring, and
  existing Dark coverage.
- [x] Add focused Light/System appearance-mode widget coverage.
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
  changes, and the app test passing all twenty-eight tests (`+28`);
- coordinator post-review validation: `dart format --output=none
  --set-exit-if-changed test/waypoint_app_test.dart` reported one file with
  zero changes;
- coordinator post-review validation: `flutter test
  test/waypoint_app_test.dart` exited 0 with all twenty-eight tests passing
  (`+28`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and the named repository file is untracked,
so Git cannot provide historical diff provenance. The coordinator verified the
Task 136 scope directly:

- app widget test path:
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
  SHA-256 `1c30a5e21e76fae2d14ad619aa1b84adb7da227c574b4e945f0c22e6d51c0bcf`;
- the app test source contains exactly twenty-eight `testWidgets` cases;
- the task-owned status is limited to this test path and this task record; no
  production, support, or unrelated file was modified by the package.

## Next Action

Task 136 is complete. Reserve the next numbered package only after a fresh
source inspection identifies the next bounded local capability.

## Blockers

None known.

## Outcome

The isolated appearance test now proves the real Settings control starts on
System, applies Light, and returns to System through both selected values and
`MaterialApp.themeMode`. Existing Dark coverage remains intact. The worker,
strict reviewer, and coordinator validation all report twenty-eight app widget
tests passing. Strict review returned `ACCEPT` with no blocking findings. The
only limitation recorded is the checkout's missing Git `HEAD` and untracked-
file state.

## References

- `tasks/135-discover-prefilled-submit-coverage.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_settings_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_ui_state.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_ui_notifier.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_theme.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Reserved after Hypatia the 2nd's source review. Settings
  exposes System, Light, and Dark and production maps all three choices to
  `MaterialApp.themeMode`, but existing interaction coverage asserts only Dark.
  This is a test-only local package with no production change expected.
- 2026-08-29: Mill the 2nd (GPT-5.6 Luna Max, max reasoning, priority) added
  one focused appearance-mode widget test in the owned app test. The worker
  reported scoped formatting with zero changes and twenty-eight app tests
  passing. No production, task, or support file was modified.
- 2026-08-29: Anscombe the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  independently reviewed the System → Light → System selected values,
  `MaterialApp.themeMode` assertions, preserved Dark coverage, no OS-brightness
  assumption, and one-file scope. Result: `ACCEPT`; no blocking findings or
  fixes required. The only limitation recorded is the checkout's missing Git
  `HEAD` and untracked-file state.
- 2026-08-29: Coordinator final validation passed: scoped formatting reported
  one file with zero changes, and `flutter test test/waypoint_app_test.dart`
  passed all twenty-eight tests. Task 136 is complete; no production, device,
  simulator, Docker, AWS, or hosted-service validation was needed.
