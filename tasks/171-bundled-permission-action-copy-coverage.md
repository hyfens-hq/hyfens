# Task 171 — Bundled permission action copy coverage

Status: [x] Completed

## Goal

Carry the bundled permission labels and rationales from `actions.json` into the local Settings permission rows, while preserving permission order, status handling, callbacks, and fallback labels.

## Scope and Non-goals

Scope:

- Preserve the existing `actions.json.permissions` array in the local home payload assembled by the data source.
- Add a small typed permission-action model and optional list on `WaypointHomeData`, then decode the bundled metadata.
- Associate metadata to the existing `WaypointPermission` enum by exact permission id and render its label and rationale in Settings.
- Keep the existing enum order, stable permission keys, status text, Test/Settings action behavior, and callbacks unchanged.
- Add exactly one real zero-latency bundled-source Settings widget test that asserts all four source labels and rationales.

Non-goals:

- Do not edit `actions.json` or platform permission mappings.
- Do not change providers, notifiers, test support, navigation, other row unit tests, or unrelated screens.
- Do not build a generic permission/action engine, dynamic platform permission mapper, device/simulator workflow, Docker/AWS/hosting integration, or deployment work.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Existing bundled `actions.json` permission metadata and local AlphaX/demo data source.
- Existing `WaypointHomeData`, JSON decoder, Settings page, permission row, platform enum, and local permission test service.
- No new dependency.

## Assumptions

- Permission metadata `id` values match `WaypointPermission.name`: `location`, `notifications`, `camera`, and `photos`.
- Metadata is optional; missing, malformed, unknown, or blank metadata falls back to the current hardcoded row labels and status-only subtitle.
- The existing `settings controls theme, media visibility, and permission state` test remains unchanged; the new bundled test uses `WaypointDemoTransport(latency: Duration.zero)` and the existing test permission service.
- The bundled-source test is the only new widget test declaration for this task.

## Work Items

- [x] Audit bundled permission source, transport, model, decoder, Settings/row omission, tests, and completed-task boundary.
- [x] Preserve `actions.json.permissions` in the local home payload.
- [x] Add and decode the optional typed permission-action list.
- [x] Render bundled label and rationale in Settings while preserving fallback/order/status/callback behavior.
- [x] Add exactly one real bundled-source Settings widget test for all four labels and rationales.
- [x] Review the combined seven-path diff for correctness and scope.
- [x] Run scoped format, analysis, named test, and affected app test file validation.
- [x] Obtain strict independent review; no blocking findings were reported.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed \
  lib/waypoint/data/waypoint_data_source.dart \
  lib/waypoint/domain/waypoint_permission_action.dart \
  lib/waypoint/domain/waypoint_home_data.dart \
  lib/waypoint/data/waypoint_json_decoder.dart \
  lib/waypoint/presentation/screens/waypoint_settings_page.dart \
  lib/waypoint/presentation/widgets/waypoint_permission_row.dart \
  test/waypoint_app_test.dart

flutter analyze \
  lib/waypoint/data/waypoint_data_source.dart \
  lib/waypoint/domain/waypoint_permission_action.dart \
  lib/waypoint/domain/waypoint_home_data.dart \
  lib/waypoint/data/waypoint_json_decoder.dart \
  lib/waypoint/presentation/screens/waypoint_settings_page.dart \
  lib/waypoint/presentation/widgets/waypoint_permission_row.dart \
  test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local Settings renders permission action copy"

flutter test test/waypoint_app_test.dart
```

Only the seven task-owned production/test files are in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test files are required.

Coordinator results on 2026-08-30:

- `dart format --output=none --set-exit-if-changed` on the seven task-owned files: passed; 7 files formatted, 0 changed.
- `flutter analyze` on the seven task-owned files: passed; no issues found.
- Named test `bundled local Settings renders permission action copy`: passed; 1 test.
- `flutter test test/waypoint_app_test.dart`: passed; 60 tests.
- Widget test declaration count is 60, reflecting exactly one new bundled Settings test.

Task-owned file hashes after validation (SHA-256):

- `lib/waypoint/data/waypoint_data_source.dart`: `1377969eb4fe6346a9b50f95d1f62d6703583a2e2af91205db79cd3201fd242a`
- `lib/waypoint/domain/waypoint_permission_action.dart`: `9c0741cac385e305aaf1a7bfd6c8069f2f1639a8d9bbc458a5bfb4f1b45af60f`
- `lib/waypoint/domain/waypoint_home_data.dart`: `4b869e03ee0e79232cbc6db40a3c014046b8044351bf9e9d9c3306f4b9cba9d9`
- `lib/waypoint/data/waypoint_json_decoder.dart`: `06ec0f4ecddb05e83dd97b1d3e247443b1a6567e9982f88339e7034ed1527032`
- `lib/waypoint/presentation/screens/waypoint_settings_page.dart`: `e0f0e1976f96f073fcc0e29324f9518c4b4504f5ccbfb5df76eb8c5e07b2f384`
- `lib/waypoint/presentation/widgets/waypoint_permission_row.dart`: `c995c25acff7610a36846124e81a3bff36a8683cf4e4a895a120f28d919af1d6`
- `test/waypoint_app_test.dart`: `cf1417f303117b6298426f1862efe9352934944f0ea8bb2df411719e18fc1f66`

## Next Action

Reserve Task 172 and audit the next uncovered bundled local conformance gap, excluding completed Tasks 150–171.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit seven-path scope.

## Outcome

Completed. Bundled permission labels and rationales now flow into Settings while enum order, status text, stable keys, actions, callbacks, and fallback behavior remain intact. No blocker remains.

## References

- `fixtures/flutter_conformance_app/assets/data/actions.json:35-40` — bundled permission ids, labels, and rationales.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart` — current actions asset loading and payload assembly.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart` — current typed home data without permission metadata.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart` — current action decoding without permissions decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_settings_page.dart` — current enum-ordered permission rows and callbacks.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_permission_row.dart` — current hardcoded labels and status rendering.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` — existing Settings behavior test and local bundled test patterns.
- `tasks/170-bundled-discover-title-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Erdos the 4th completed a read-only audit and identified the dropped bundled permission metadata; no files changed.
- 2026-08-30 — Coordinator reserved Task 171 with a bounded seven-file implementation, review, and local validation scope.
- 2026-08-30 — Mencius the 4th implemented the seven-path source-to-Settings change and reported formatting, analysis, the named test, 12 row tests, and 60 affected app tests passing.
- 2026-08-30 — Huygens the 4th independently reviewed the actual source and returned ACCEPT with no findings; coordinator validation remained pending.
- 2026-08-30 — Coordinator validation passed: format unchanged, scoped analysis clean, the named bundled Settings test passed, and all 60 tests in `waypoint_app_test.dart` passed. Task completed.
