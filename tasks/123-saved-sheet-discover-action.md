# Task 123 — Saved detail sheet Discover action

Status: [x] Completed

## Goal

Turn the Saved destination detail sheet's existing plain Discover guidance into
an explicit action that closes the sheet and returns the user to Discover.

## Scope and Non-goals

Scope:

- add the smallest reusable action control to the existing Saved detail sheet;
- preserve the current Discover guidance copy and destination content;
- route the action through the existing `WaypointSection.discover` state
  selection;
- extend the existing Saved detail widget test to prove the sheet closes and
  Discover is visible.

Non-goals:

- adding a new navigation package, route layer, persistence, or API;
- changing the empty Saved-state Browse destinations action;
- changing unrelated Saved, Discover, Trips, Activity, permission, or settings
  behavior;
- device, simulator, Docker, AWS, or hosted-service work;
- JSON-driven actions/forms or speculative UI abstraction.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Task 122 Saved destination detail-sheet coverage;
- existing `WaypointSavedPage._showSaved` sheet;
- existing `WaypointUiNotifier.selectSection` and `WaypointSection.discover`;
- existing app test harness and local Kyoto fixture.

## Assumptions

- the current plain guidance text is the intended label to preserve while
  making it actionable;
- closing the modal before selecting Discover is the expected navigation
  sequence for the current single-page section state;
- a stable key for the new action is appropriate for focused widget coverage;
- the worker owns only:
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_saved_page.dart`
  and `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- affected validation is limited to those changed source/test files.

## Work Items

- [x] Inspect the current plain guidance and existing section-selection path.
- [x] Add the explicit detail-sheet Discover action with minimal production
  changes.
- [x] Extend the existing detail-sheet widget test to verify action behavior.
- [x] Preserve and review Task 121/122 Saved coverage.
- [x] Review the task-owned change for scope and factual correctness.
- [x] Run only formatting and the changed app test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next instruction.

## Validation

Planned affected-file validation only:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/presentation/screens/waypoint_saved_page.dart`
  `test/waypoint_app_test.dart` from `fixtures/flutter_conformance_app`;
- `flutter test test/waypoint_app_test.dart` from
  `fixtures/flutter_conformance_app`;
- result: both files formatted with 0 changes and the affected app test run
  passed all nineteen tests (`+19`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and repository files are untracked, so Git
cannot provide a historical diff. The coordinator verified the Task 123
source-level change as follows:

- implementation paths are exactly
  `lib/waypoint/presentation/screens/waypoint_saved_page.dart` and
  `test/waypoint_app_test.dart` under `fixtures/flutter_conformance_app`;
- the Saved page adds the existing notifier reference to the card tap callback,
  replaces the plain guidance `Text` with one keyed `FilledButton.icon`, and
  closes the modal before selecting `WaypointSection.discover` at current lines
  56 and 77–118;
- the app test adds one contiguous action assertion block at current lines
  145–158 after the existing detail-sheet content assertions;
- current SHA-256 values are
  `33a1a2140f95f9d2cc9be8f9147cec670b5dd6b6c561e13c69c9459068d1a8ea` for the
  Saved page and
  `f9c5ae1d9cd9b178f6ed82b8cb3c399caa87445b5579951c778cfa4e1725a4da` for the
  app test;
- the worker reported no other files modified, and no unrelated file was
  observed in the task-owned inspection;
- this manifest records the missing Git provenance explicitly and does not
  claim a commit, tracked baseline, or persistence behavior.

## Next Action

Task 123 is complete. Reserve the next local-only task to preserve selected
destination context when the Saved detail action returns to Discover.

## Blockers

None known.

## Outcome

The worker updated only the Saved page and app test within the assigned scope.
The Saved detail sheet now exposes a keyed action that closes the modal and
selects Discover; the existing detail assertions and Task 121/122 coverage
remain intact. Formatting reported 0 changes and the affected app test file
passed all nineteen tests. Strict review accepted the behavior, validation,
and source-level scope manifest with no blocking findings or fixes required.

## References

- `tasks/122-saved-detail-bottom-sheet.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_saved_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_ui_notifier.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_ui_state.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Reserved Task 123 from the accepted Task 122 review. Scope is
  the smallest actionable navigation control for the existing Saved detail
  sheet, with focused local widget coverage and no new navigation abstraction.
- 2026-08-29: Heisenberg the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  updated only the two owned files. The worker reported 0 formatting changes
  and `flutter test test/waypoint_app_test.dart` passing all nineteen tests.
- 2026-08-29: Nietzsche the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  strictly reviewed the explicit action, existing notifier path, focused test,
  validation count, and source-level scope manifest. Result: `ACCEPT`; no
  blocking findings or fixes required. The next instruction is selected
  destination context on return to Discover.
