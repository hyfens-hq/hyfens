# Task 191 — Bundled Discover detail description coverage

Status: [x] Completed

## Goal

Prove that the real bundled Lantern House description reaches the Discover detail sheet.

## Scope and Non-goals

Scope:

- Extend the existing real bundled Discover detail widget test with one exact `BottomSheet`-scoped description assertion.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, renderer, search behavior, filters, categories, metadata already covered, navigation, dependencies, or infrastructure.
- Do not add a new test declaration or test file; do not change tests outside `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
- Do not use synthetic destination data or a global/ambiguous text assertion.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled Lantern House description in `home.json`.
- Existing `WaypointJsonDecoder.decodeDestination` summary mapping and Discover detail-sheet rendering.
- Existing real zero-latency bundled Discover detail test with Lantern House navigation and metadata assertions.

## Assumptions

- The Lantern House detail sheet renders the exact description `A calm machiya stay with a small inner garden.`.
- The existing `BottomSheet` finder uniquely scopes the description assertion to the opened Lantern House detail.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit the bundled description, decoder/rendering path, existing coverage, and completed-task boundary.
- [x] Add one exact `BottomSheet`-scoped description assertion to the existing Discover detail test.
- [x] Review the task-owned test diff for source fidelity, stable scoping, and preservation of existing assertions.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named Discover-detail test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local Discover detail renders source metadata"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task only after direct source and test evidence identifies a bounded gap.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

Completed as a test-only extension of the existing real bundled Lantern House Discover-detail test. The test now verifies `A calm machiya stay with a small inner garden.` inside the opened `BottomSheet`, while preserving the existing metadata, navigation, and cleanup assertions. No production, fixture, dependency, device, simulator, Docker, AWS, hosting, or deployment work was required.

Validation passed from `fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` — `Formatted 1 file (0 changed)` after the final formatter pass.
- `flutter analyze test/waypoint_app_test.dart` — `No issues found!`.
- Named Discover-detail test — `+1: All tests passed!`.
- `flutter test test/waypoint_app_test.dart` — `+68: All tests passed!`.

The repository has no usable Git `HEAD`; review and scope evidence therefore used direct file inspection and the explicit single-file ownership boundary. No unrelated test files were validated.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:70-82` — bundled Lantern House description.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:110-122` — destination description-to-summary mapping.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart:360-380` — Discover detail description rendering.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:386-444` — existing real bundled Discover detail test, `BottomSheet` metadata assertions, and the new description assertion.
- `tasks/175-bundled-local-destination-description-search.md` — prior description search coverage boundary.
- `tasks/179-bundled-discover-detail-metadata.md` — prior Discover detail metadata coverage boundary.
- `tasks/190-bundled-trip-title-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Dirac the 4th completed a focused read-only scan and identified unasserted bundled Lantern House detail description propagation; no files changed.
- 2026-08-30 — Coordinator directly verified the bundled text, decoder mapping, detail-sheet rendering, existing real test seam, and coverage boundary.
- 2026-08-30 — Coordinator reserved Task 191 with a bounded single-file test implementation, review, and local validation scope.
- 2026-08-30 — Hegel the 4th extended only `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` with one exact `BottomSheet`-scoped description assertion; the named Discover-detail test passed.
- 2026-08-30 — Maxwell the 4th identified one Low stale test-range reference during strict review; the coordinator corrected the task reference to include the new assertion.
- 2026-08-30 — Raman the 4th completed strict review with `ACCEPT — no findings` after the reference correction.
- 2026-08-30 — Coordinator formatted the test file after the first validation check and requested a fresh review of the final formatted state.
- 2026-08-30 — Aquinas the 4th completed the final strict review with `ACCEPT — no findings`, verifying source fidelity, precise sheet scoping, preserved assertions, and corrected references.
- 2026-08-30 — Coordinator completed the declared scoped validation: final format clean, analyzer clean, named Discover-detail test passed, and the affected app test file passed all 68 tests.
