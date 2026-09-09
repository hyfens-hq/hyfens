# Task 170 — Bundled Discover title coverage

Status: [x] Completed

## Goal

Carry the bundled `discover.json` title through the local AlphaX/demo payload and typed home model, then render it in the initial Discover header while preserving the existing greeting and fallback description.

## Scope and Non-goals

Scope:

- Preserve the optional `discover.title` value in the local home payload assembled by the data source.
- Add one optional typed `discoverTitle` field to `WaypointHomeData` and decode it from the payload.
- Render the nonblank bundled title in the Discover header's description slot, leaving the greeting as the header title.
- Update the existing real, zero-latency bundled-source home test with the exact source-title assertion.

Non-goals:

- Do not change `discover.json`, assets, dependencies, repository contracts, search, filters, categories, collections, places, greeting behavior, planner/actions, or unrelated screens.
- Do not add a new model file, generic payload mapper, refactor, device/simulator test, Docker/AWS/hosting work, or tests outside `waypoint_app_test.dart`.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Existing bundled `discover.json` and local AlphaX/demo data source.
- Existing `WaypointHomeData`, JSON decoder, Discover page, and bundled home widget test.
- No new dependency.

## Assumptions

- `discover.title` remains an optional string and maps to `WaypointHomeData.discoverTitle` to avoid ambiguity with the home hero title.
- The current greeting remains the header title; the source-driven Discover title occupies the existing description slot.
- Missing, non-string, or blank title values retain the existing hardcoded description.
- The existing `bundled local demo renders its home hero` test is extended in place rather than adding another bundled-source widget test.

## Work Items

- [x] Audit the bundled source, transport, model, decoder, UI omission, existing test, and completed-task boundary.
- [x] Preserve `discover.title` in the local home payload.
- [x] Add and decode the optional typed Discover title.
- [x] Render the optional title in the Discover header while preserving greeting and fallback behavior.
- [x] Update exactly one existing real bundled-source widget test for the exact title.
- [x] Review the combined five-path diff for correctness and scope.
- [x] Run scoped format, analysis, named test, and affected app test file validation.
- [x] Obtain strict independent review; no blocking findings were reported.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed \
  lib/waypoint/data/waypoint_data_source.dart \
  lib/waypoint/domain/waypoint_home_data.dart \
  lib/waypoint/data/waypoint_json_decoder.dart \
  lib/waypoint/presentation/screens/waypoint_discover_page.dart \
  test/waypoint_app_test.dart

flutter analyze \
  lib/waypoint/data/waypoint_data_source.dart \
  lib/waypoint/domain/waypoint_home_data.dart \
  lib/waypoint/data/waypoint_json_decoder.dart \
  lib/waypoint/presentation/screens/waypoint_discover_page.dart \
  test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local demo renders its home hero"

flutter test test/waypoint_app_test.dart
```

Only the five task-owned production/test files are in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test files are required.

Coordinator results on 2026-08-30:

- `dart format --output=none --set-exit-if-changed` on the five task-owned files: passed; 5 files formatted, 0 changed.
- `flutter analyze` on the five task-owned files: passed; no issues found.
- Named test `bundled local demo renders its home hero`: passed; 1 test.
- `flutter test test/waypoint_app_test.dart`: passed; 59 tests.
- Widget test declaration count remained 59; the existing bundled home test was updated in place.

Task-owned file hashes after validation (SHA-256):

- `lib/waypoint/data/waypoint_data_source.dart`: `fd8d313d49a5940fd26401c4478daab2b0e7bb013fe792ea09898828d1e54058`
- `lib/waypoint/domain/waypoint_home_data.dart`: `a8c59a9db76ca76474574ecb23bd234396a60fa78c5628b10310a8ed06d20237`
- `lib/waypoint/data/waypoint_json_decoder.dart`: `5704f8b0b66a8b99914d14b2308f9e53d80a52d438ccfca511eed7fbafbe431c`
- `lib/waypoint/presentation/screens/waypoint_discover_page.dart`: `5a8c89b2aca892765dc3246f07b30862403a61e63f0a27f5958eae2a9851278a`
- `test/waypoint_app_test.dart`: `3765fc29755f0091cd56859b08ed91d2b8dc81510e4f10dd2678494e669c0b1c`

## Next Action

Reserve Task 171 and audit the next uncovered bundled local conformance gap, excluding completed Tasks 150–170.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit five-path scope.

## Outcome

Completed. The bundled Discover title now flows from `discover.json` through the local payload, typed model, decoder, and header description; the existing greeting and fallback remain intact. No blocker remains.

## References

- `fixtures/flutter_conformance_app/assets/data/discover.json:4` — source title `Find your next feeling`.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart` — current Discover payload assembly omits `title`.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart` — current typed home data has no Discover-title field.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart` — current home decoder has no Discover-title mapping.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart` — current header uses greeting and a hardcoded description.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` — existing real bundled home test.
- `tasks/169-bundled-open-planner-action-copy-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Meitner the 3rd completed a read-only audit and identified the dropped bundled Discover title; no files changed.
- 2026-08-30 — Coordinator reserved Task 170 with a bounded five-file implementation, review, and local validation scope.
- 2026-08-30 — Euclid the 4th implemented the five-path source-to-header change and reported scoped format, analysis, named test, and affected test-file checks passing.
- 2026-08-30 — Carson the 4th independently reviewed the actual source and returned ACCEPT with no findings.
- 2026-08-30 — Coordinator validation passed: format unchanged, scoped analysis clean, named hero test passed, and all 59 tests in `waypoint_app_test.dart` passed. Task completed.
- 2026-08-30 — Euclid the 4th implemented the five-path source-to-header change and reported scoped format, analysis, named test, and affected test-file checks passing.
- 2026-08-30 — Carson the 4th independently reviewed the actual source and returned ACCEPT with no findings; coordinator validation remained pending.
