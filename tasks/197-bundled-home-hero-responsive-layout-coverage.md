# Task 197 — Bundled home hero responsive-layout coverage

Status: [x] Completed

## Goal

Prove that the real bundled home hero selects its stacked layout below the 640 logical-pixel breakpoint and its side-by-side layout at the breakpoint.

## Scope and Non-goals

Scope:

- Add focused Flutter widget coverage for the existing bundled home hero responsive branch.
- Exercise one viewport that produces hero constraints below 640 and one viewport that produces hero constraints at or above 640 with the existing zero-latency bundled data source (using 1.0 device-pixel ratio and accounting for the page/card/padding insets).
- Assert the layout ancestor of the keyed hero artwork is `Column` below the breakpoint and `Row` at/above it.

Non-goals:

- Do not change production code, bundled JSON/assets, models, decoder, repository, navigation, or dependencies.
- Do not modify tests outside `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
- Do not test unrelated responsive layouts, screenshots, pixel values, devices, simulator, Docker, AWS, hosting, or deployment.
- Do not add speculative abstractions or synthetic hero payloads.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled hero in `fixtures/flutter_conformance_app/assets/data/home.json`.
- `_HomeHero` breakpoint implementation in `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`.
- Existing real bundled hero test and `pumpWaypointTestApp` support in `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` and `waypoint_test_support.dart`.

## Assumptions

- The existing test view API can set a 1.0 device-pixel ratio and restore its physical size after the test.
- The selected view widths are wide enough to produce the intended `_HomeHero` constraints after the existing page, card, and hero padding insets; the test must use concrete below/at-or-above branch evidence rather than equating viewport width with the inner constraint.
- The keyed hero artwork has the responsive `Row` or `Column` as an inspectable ancestor after the bundled app is pumped.
- Validation is limited to the changed app test file.

## Work Items

- [x] Audit the bundled hero source, decoder/model path, rendering breakpoint, existing test, and supported coverage boundary.
- [x] Add focused test-only coverage for below-breakpoint and at/above-breakpoint hero layout selection.
- [x] Review the task-owned test diff for source fidelity, stable widget scoping, cleanup, and preservation of existing assertions.
- [x] Obtain strict independent review; no behavioral or geometry defect was found, and the repository-baseline limitation was recorded without speculative code changes.
- [x] Run scoped format, analysis, the named responsive-hero test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local demo switches hero layout at the responsive breakpoint"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or deployment validation is required.

## Next Action

Audit the next supported local fixture capability and reserve the next task only after direct source and test evidence identifies a bounded gap.

## Blockers

No functional blocker remains. The repository has no usable Git `HEAD` or tracked index, so an independent historical diff cannot prove preservation of pre-existing untracked content. This provenance limitation is recorded; the coordinator's scoped edit targeted only the approved test file, and no code change is warranted to manufacture a baseline.

## Outcome

Completed as a test-only extension of the real bundled home-hero coverage. The test sets a 1.0 device-pixel ratio, exercises a 639-pixel viewport that leaves the hero's inner constraint below 640 and a 720-pixel viewport that clears the existing page/Card/hero insets, then identifies the nearest `Row`/`Column` ancestor of the keyed hero artwork. It proves the stacked `Column` branch and side-by-side `Row` branch without changing production code, bundled data/assets, dependencies, or other test files.

The strict independent review found the behavior and geometry evidence sound. Its only finding was that the checkout has no usable Git `HEAD`, so historical preservation of pre-existing untracked content cannot be independently proven. That limitation is factual and non-functional; no speculative baseline or unrelated change was introduced.

Validation passed from `fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` — `Formatted 1 file (0 changed)`.
- `flutter analyze test/waypoint_app_test.dart` — `No issues found!`.
- Named responsive-hero selector — `+1: All tests passed!`.
- `flutter test test/waypoint_app_test.dart` — `+69: All tests passed!`.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:5-12` — bundled home hero fields.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:40-54` — hero decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_hero.dart:1-18` — hero model.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart:493-510` — 640 logical-pixel `Row`/`Column` branch.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_surface.dart:3-15` — existing Card and hero padding insets accounted for by the selected viewport widths.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart:40-78` — 900 logical-pixel shell breakpoint kept out of the test's 639/720 viewport cases.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:112-164` — existing real bundled hero content/action coverage.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:213-273` — responsive layout test, nearest ancestor assertions, view cleanup, and bundled source setup.
- `tasks/196-bundled-note-submit-label-coverage.md` — preceding completed local fixture coverage task.

## History

- 2026-08-30 — Aquinas the 5th completed a focused read-only audit and identified the unasserted responsive hero branch; no files changed.
- 2026-08-30 — Coordinator directly verified the bundled source, rendering branch, existing test seam, task boundary, and next task number.
- 2026-08-30 — Coordinator reserved Task 197 with a bounded single-file test implementation, strict review, and local validation scope.
- 2026-08-30 — Lagrange the 5th and Volta the 5th were assigned the implementation but returned without a patch; the coordinator closed those assignments without changing their scope.
- 2026-08-30 — Descartes the 5th was assigned a final edit-only handoff but was stopped without a patch; the coordinator applied the minimal test-only change locally.
- 2026-08-30 — Coordinator completed the direct code/geometry review and confirmed the nearest ancestor traversal, view cleanup, source cleanup, and one-test-file edit scope.
- 2026-08-30 — Lorentz the 5th and Hilbert the 5th timed out during independent review; Gauss the 5th returned the strict finding that behavior was sound but historical preservation cannot be proven without a Git baseline.
- 2026-08-30 — Coordinator verified `git rev-parse --verify HEAD` fails and the repository has no tracked index, recorded the provenance limitation, and made no speculative fix.
- 2026-08-30 — Coordinator completed scoped validation: format clean, analyzer clean, named responsive-hero test passed, and all 69 tests in the affected app test file passed.
- 2026-08-30 — Coordinator verified that the 640 threshold applies to the hero's inner `LayoutBuilder` constraint, not the full viewport, because the existing page/card/padding insets consume width; the implementation must account for those insets.
