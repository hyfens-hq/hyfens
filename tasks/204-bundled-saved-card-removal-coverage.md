# Task 204: Bundled Saved-card removal coverage

Status: [x] Completed

## Goal

Extend the bundled local Saved-screen test to prove that removing the shipped saved destination updates the visible Saved list.

## Scope and Non-goals

Scope:

- Extend only `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
- Reuse the existing bundled `WaypointAlphaXDataSource` and Saved-screen test.
- Tap the card-scoped `waypoint-save-lantern-house` control after entering Saved.
- Assert the `waypoint-destination-lantern-house` card is absent after the state update.

Non-goals:

- No production code, fixture data, assets, dependencies, task files beyond this record, or platform changes.
- No changes to Discover save behavior, card layout, detail sheets, or copy.
- No new test support source, device, simulator, Docker, AWS, hosting, or deployment work.
- No unrelated test-file or repository-wide test changes.

## Owner

GPT-5.6 Luna Max worker, priority/fast service; coordinator integrates the result. A separate GPT-5.6 Luna Max reviewer owns the strict fact-based review.

## Dependencies

- Existing bundled `Lantern House` record with `saved: true`.
- Existing `WaypointSavedPage` card callback and `waypointUiProvider` saved override behavior.
- Existing bundled Saved-screen test and local AlphaX transport.

## Assumptions

- The bundled `Lantern House` destination remains initially saved and is rendered in Saved.
- The existing keyed control `waypoint-save-lantern-house` invokes the current `toggleSaved` callback.
- The UI state update is observable after the established `pumpAndSettle()` pattern.
- The repository has no resolvable Git `HEAD`; review evidence will use direct current-file/source evidence rather than a fabricated commit diff.

## Work Items

- [x] Reserve Task 204 and document the evidence-backed bundled Saved interaction scope.
- [x] Extend the existing bundled Saved test with removal and disappearance assertions.
- [x] Perform self-review and strict independent review against the task and current source.
- [x] Run scoped formatting, analysis, the named test, and the complete changed app test file; record results.
- [x] Mark the task complete only after all findings and required validation pass.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart
flutter analyze test/waypoint_app_test.dart
flutter test test/waypoint_app_test.dart --plain-name "bundled local demo preserves its initial saved destination"
flutter test test/waypoint_app_test.dart
```

Results on 2026-08-30:

- Final format check: PASS — `Formatted 1 file (0 changed)`.
- Final scoped analysis: PASS — `No issues found!`.
- Final named test: PASS — `+1: All tests passed!`.
- Final changed-file test: PASS — `+70: All tests passed!`.

Only the changed app test file and its directly exercised Flutter test target were in scope. No device or Docker validation was required for this test-only change.

## Next Action

Continue with the next reserved local coverage package: icon-only shell-header tooltip semantics (Task 205).

## Blockers

None.

## Outcome

Completed as a test-only extension at `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:1217-1228`. The bundled Saved flow now taps the actual `waypoint-save-lantern-house` control and verifies the `waypoint-destination-lantern-house` card disappears after the UI state update, while preserving the initial saved-card, tooltip, and count assertions. No production, fixture, dependency, platform, device, Docker, AWS, hosting, or deployment files changed.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:71-83` — bundled `Lantern House` record with `saved: true`.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_saved_page.dart:40-69` — Saved list rendering and saved-count state.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart:77-93` — keyed remove-save control and callback.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:1171-1228` — bundled Saved test with initial presence/count and removal/disappearance coverage.
- Read-only audit by Sartre the 5th on 2026-08-30 — confirmed the bundled removal-coverage gap and no production change is needed.
- Strict review by Popper the 5th on 2026-08-30 — implementation accepted; coordinator corrected stale task metadata.
- Final strict review by Aristotle the 5th on 2026-08-30 — ACCEPT — no findings.

## History

- 2026-08-30: Reserved serial Task 204 after direct source/test audit; implementation pending.
- 2026-08-30: Luna Max worker extended the existing bundled Saved test with the card-scoped removal action and disappearance assertion.
- 2026-08-30: Strict review found stale task metadata only; coordinator corrected the current test range and work-item/next-action state.
- 2026-08-30: Final strict review accepted the corrected task/test record with no findings.
- 2026-08-30: Scoped format, analysis, named test, and full changed-file test passed; Task 204 completed.
