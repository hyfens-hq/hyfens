# Task 192 — Bundled destination location coverage

Status: [x] Completed

## Goal

Prove that the real bundled Lantern House location reaches its Discover destination card.

## Scope and Non-goals

Scope:

- Extend the existing real bundled destination-distance widget test with one exact card-scoped location assertion.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, renderer, search, filters, categories, detail metadata, navigation, dependencies, or infrastructure.
- Do not add a new test declaration or test file; do not change tests outside `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
- Do not use synthetic destination data or a global/ambiguous text assertion.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled Lantern House `location` value in `home.json`.
- Existing `WaypointJsonDecoder.decodeDestination` location mapping and `WaypointDestinationCard` rendering.
- Existing real zero-latency bundled destination-distance test with keyed Lantern House card and cleanup.

## Assumptions

- The bundled Lantern House card renders the exact location `Gion, Kyoto`.
- The existing `waypoint-destination-lantern-house` key uniquely scopes the assertion to the intended card.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit the bundled location, decoder/rendering path, existing coverage, and completed-task boundary.
- [x] Add one exact card-scoped location assertion to the existing destination-distance test.
- [x] Review the task-owned test diff for source fidelity, stable scoping, and preservation of existing assertions.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named destination test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local demo renders destination distance"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task only after direct source and test evidence identifies a bounded gap.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

Completed as a test-only extension of the existing real bundled Lantern House destination-distance test. The test now verifies `Gion, Kyoto` within the keyed `waypoint-destination-lantern-house` card, while preserving the existing distance, visibility, setup, and cleanup assertions. No production, fixture, dependency, device, simulator, Docker, AWS, hosting, or deployment work was required.

Validation passed from `fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` — `Formatted 1 file (0 changed)` after the final formatter pass.
- `flutter analyze test/waypoint_app_test.dart` — `No issues found!`.
- Named destination selector — `+1: All tests passed!`.
- `flutter test test/waypoint_app_test.dart` — `+68: All tests passed!`.

The repository has no usable Git `HEAD`; review and scope evidence therefore used direct file inspection and the explicit single-file ownership boundary. No unrelated test files were validated.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:70-79` — bundled Lantern House location.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:110-123` — destination location mapping.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart:100-112` — destination-card location rendering.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:356-388` — existing real bundled destination-distance test, keyed card scope, and new location assertion.
- `tasks/175-bundled-local-destination-description-search.md` — prior bundled destination description coverage boundary.
- `tasks/184-bundled-destination-accent-coverage.md` — prior bundled destination accent coverage boundary.
- `tasks/191-bundled-discover-detail-description-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Sagan the 4th completed a focused read-only scan and identified unasserted bundled Lantern House card location propagation; no files changed.
- 2026-08-30 — Coordinator directly verified the bundled value, decoder mapping, card rendering, existing real test seam, and coverage boundary.
- 2026-08-30 — Coordinator reserved Task 192 with a bounded single-file test implementation, review, and local validation scope.
- 2026-08-30 — Ramanujan the 4th extended only `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` with one exact card-scoped location assertion; the named destination test passed.
- 2026-08-30 — Rawls the 4th identified one Low stale test-range reference during strict review; the coordinator corrected the task reference to include the new assertion.
- 2026-08-30 — Nash the 4th completed strict review with `ACCEPT — no findings` after the reference correction.
- 2026-08-30 — Coordinator applied the formatter, which changed only test layout, and requested a fresh review of the final formatted state.
- 2026-08-30 — Volta the 4th completed the final strict review with `ACCEPT — no findings`, verifying source fidelity, precise card scoping, preserved assertions, and the corrected reference.
- 2026-08-30 — Coordinator completed the declared scoped validation: final format clean, analyzer clean, named destination test passed, and the affected app test file passed all 68 tests.
