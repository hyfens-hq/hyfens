# Task 122 — Saved destination detail bottom-sheet coverage

Status: [x] Completed

## Goal

Verify that selecting the existing saved Kyoto destination opens its detail
bottom sheet with the destination content and the Discover guidance text.

## Scope and Non-goals

Scope:

- save the local Kyoto destination through the existing Discover control;
- navigate to Saved and select the existing Kyoto card;
- verify the real detail bottom sheet renders Kyoto content and its guidance
  copy;
- preserve the existing Saved removal and empty-state coverage.

Non-goals:

- changing Saved or bottom-sheet production behavior;
- adding persistence, deep links, or new navigation abstractions;
- testing unrelated Trips, Activity, permissions, device, simulator, Docker,
  AWS, or hosted-service behavior;
- adding tests outside the affected app test file.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Task 121 Saved removal and empty-state coverage;
- existing `WaypointSavedPage._showSaved` bottom-sheet path;
- local home fixture containing Kyoto and the existing save action.

## Assumptions

- `waypoint-destination-kyoto` is the existing destination-card key and its
  `onTap` is wired to the Saved detail sheet;
- `Open Discover to compare this place with the full list.` is the existing
  sheet guidance copy;
- the test can use the current in-memory fixture and makes no persistence
  claim;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- affected validation is limited to that changed test file.

## Work Items

- [x] Inspect the Saved card tap wiring and existing detail sheet content.
- [x] Add focused widget coverage for opening the saved Kyoto detail sheet.
- [x] Preserve and review the existing Saved removal and empty-state flow.
- [x] Review the task-owned change for scope and factual correctness.
- [x] Run only formatting and the changed app test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next instruction.

## Validation

Planned affected-file validation only:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_app_test.dart` from `fixtures/flutter_conformance_app`;
- `flutter test test/waypoint_app_test.dart` from
  `fixtures/flutter_conformance_app`;
- result: formatting reported 0 changes and the affected app test run passed
  all nineteen tests (`+19`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and the repository files are untracked, so a
Git diff cannot establish a historical baseline. The coordinator verified the
Task 122 source-level patch as follows:

- implementation path: `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- current SHA-256: `df16eeed77ad99d7f5f75ff13dc77d31f7c2ae9da250bf1f70f96af21c15a796`;
- the only Task 122 insertion is the contiguous block at current lines 100–144,
  between the existing first Saved-flow test and the existing home-retry test;
- removing current lines 100–145 and comparing the result with the current file
  produces one source-level diff hunk containing only the new detail-sheet
  test; the surrounding pre-existing tests remain unchanged in that manifest;
- the worker reported no other files modified, and no production file was
  written by the worker instruction or observed in the task-owned inspection;
- this manifest records the missing Git provenance explicitly and does not
  claim a commit, tracked baseline, or persistence behavior.

## Next Action

Task 122 is complete. Reserve the next local-only task for making the Saved
detail sheet's existing Discover guidance an explicit navigation control.

## Blockers

None known.

## Outcome

The worker updated only
`fixtures/flutter_conformance_app/test/waypoint_app_test.dart`, adding a real
save -> Saved -> Kyoto card tap flow and assertions for the existing bottom
sheet type, Kyoto content, summary, and Discover guidance. Existing Task 121
coverage remains intact. Formatting reported 0 changes and the affected app
test file passed all nineteen tests. The first strict review found no app-code
defect but rejected the task because Git has no baseline. A source-level scope
manifest records the exact contiguous insertion, current hash, and provenance
limitation. Fresh strict review accepted that manifest and the implementation
with no blocking findings or fixes required.

## References

- `tasks/121-saved-unsave-empty-state.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_saved_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Reserved Task 122 from the accepted Task 121 review. Scope is
  local widget coverage for the existing Saved Kyoto detail bottom sheet; no
  production behavior or persistence is implied.
- 2026-08-29: Hooke the 2nd (GPT-5.6 Luna Max, max reasoning, priority) updated
  only the owned app test file. The worker reported 0 formatting changes and
  `flutter test test/waypoint_app_test.dart` passing all nineteen tests.
- 2026-08-29: Aquinas the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  strictly verified the test behavior and validation count, but rejected the
  task because the checkout has no commit or tracked baseline. The coordinator
  recorded a reproducible source-level scope manifest; no app-code fix was
  identified and fresh review is required.
- 2026-08-29: Turing the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  re-reviewed the source-level manifest, exact 19-test validation, real card
  tap, and bottom-sheet content. Result: `ACCEPT`; no blocking findings or
  fixes required. The next instruction is to make the existing Discover
  guidance an explicit navigation control.
