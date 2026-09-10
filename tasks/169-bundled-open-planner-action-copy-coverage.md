# Task 169 — Bundled open-planner action copy coverage

Status: [x] Completed

## Goal

Render and verify the bundled `open_planner` action's source-driven title, subtitle, and submit label when the home hero opens the existing planning sheet.

## Scope and Non-goals

Scope:

- Pass an optional `WaypointTestAction` into the existing planning sheet.
- Pass only the validated `open_planner` action from the bundled home hero.
- Preserve the current fallback copy for settings, offer banner, video, trips, and destination-detail callers.
- Update the existing real, zero-latency bundled-source hero test with the source-copy assertions.

Non-goals:

- Do not render the action `fields` array dynamically or add a generic form engine.
- Do not change planner state, validation, prefill, submission semantics, JSON, assets, decoder, repository, dependencies, or completed task behavior.
- No AWS, hosting, deployment, Docker, simulator, device, or platform work.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Existing typed `WaypointTestAction` contract and bundled local data source.
- Existing `open_planner` home-hero handoff and planning-sheet implementation.
- Existing zero-latency local test transport.
- No new dependency.

## Assumptions

- `open_planner` remains the home hero action id.
- Missing action metadata retains the existing fallback copy.
- Planner controls remain intentionally static; only top-level copy is source-driven.
- The existing Task 155 hero test is extended rather than adding a second real bundled-source widget test.

## Work Items

- [x] Audit the source, contract, omission, nearby tests, and completed-task boundary.
- [x] Add optional action metadata to the planning-sheet API while preserving fallback copy.
- [x] Pass only the validated `open_planner` metadata from the home hero.
- [x] Update exactly one real bundled-source widget test for the three source strings and submit label.
- [x] Review the combined task-owned diff for correctness and scope.
- [x] Run scoped format, analysis, named test, and affected app test file validation.
- [x] Obtain strict independent review; no blocking findings were reported.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed \
  lib/waypoint/presentation/screens/waypoint_discover_page.dart \
  lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart \
  test/waypoint_app_test.dart

flutter analyze \
  lib/waypoint/presentation/screens/waypoint_discover_page.dart \
  lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart \
  test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local demo renders its home hero"

flutter test test/waypoint_app_test.dart
```

Only the three task-owned production/test files are in validation scope. No device, simulator, Docker, AWS, or unrelated test files are required.

Coordinator results on 2026-08-30:

- `dart format --output=none --set-exit-if-changed` on the three task-owned files: passed; 3 files formatted, 0 changed.
- `flutter analyze` on the three task-owned files: passed; no issues found.
- Named test `bundled local demo renders its home hero`: passed; 1 test.
- `flutter test test/waypoint_app_test.dart`: passed; 59 tests.
- Widget test declaration count remained 59; the existing Task 155 hero test was updated in place.

Task-owned file hashes after validation (SHA-256):

- `lib/waypoint/presentation/screens/waypoint_discover_page.dart`: `f794fbdf0b9b77810505d8a18fc834b79d9201f8e70132666cf70fa02beb520f`
- `lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart`: `11a680c543e50a5f856158c3d9c3309878184a234c4a504aa9035f08ea5b06b1`
- `test/waypoint_app_test.dart`: `3a3d791f6dfc7b8c33c74ed796514196cdcb87647f2b68354cbab9739393ff41`

## Next Action

Reserve Task 170 and audit the next uncovered bundled local conformance gap, excluding completed Tasks 150–169.

## Blockers

None.

## Outcome

Completed. The bundled hero now renders the validated `open_planner` title, subtitle, and submit label, while callers that omit action metadata retain the previous fallback copy. No blocker remains.

## References

- `fixtures/flutter_conformance_app/assets/data/actions.json` — bundled `open_planner` values: `Start a small plan`, `Choose a place, a pace, and a few open days.`, and `Show ideas`.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_test_action.dart` — typed action copy contract.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart` — current hero handoff.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart` — current hardcoded planning-sheet copy and fallback boundary.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` — existing bundled hero test.
- `tasks/155-bundled-home-hero-coverage.md` — prior hero coverage and handoff boundary.

## History

- 2026-08-30 — Ramanujan the 3rd audited the next gap: decoded `open_planner` copy was discarded before the planning sheet opened; no files changed.
- 2026-08-30 — Coordinator reserved Task 169 and bounded the three-file implementation, review, and local validation scope.
- 2026-08-30 — Epicurus the 3rd implemented the exact three-file change and reported format, scoped analysis, the named hero test, and 59 affected tests passing.
- 2026-08-30 — Herschel the 3rd independently reviewed the actual source and returned ACCEPT with no findings.
- 2026-08-30 — Coordinator validation passed: format unchanged, scoped analysis clean, named hero test passed, and all 59 tests in `waypoint_app_test.dart` passed. Task completed.
