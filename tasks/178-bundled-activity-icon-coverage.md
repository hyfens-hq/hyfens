# Task 178 — Bundled Activity icon coverage

Status: [x] Completed

## Goal

Map the two shipped bundled Activity icon names to the existing Material icons and prove the real local Activity stream renders those source-driven icons while retaining the unknown-icon fallback.

## Scope and Non-goals

Scope:

- Add only the `spark` and `bookmark` mappings to the existing Activity tile icon resolver.
- Extend the existing real zero-latency bundled Activity widget test with exact icon assertions.

Non-goals:

- Do not edit JSON/assets, Activity model/decoder/repository, stream lifecycle, retry/cancellation behavior, accent colors, or other screens.
- Do not add a generic icon registry, dependencies, new test files, or tests outside `waypoint_app_test.dart`.
- Preserve all existing aliases and the current `Icons.explore_rounded` fallback for unknown names.
- No device, simulator, Docker, AWS, online hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Existing bundled `home.json` Activity records with `icon: spark` and `icon: bookmark`.
- Existing `WaypointActivity.iconName` decoder field and Activity tile icon resolver.
- Existing local zero-latency AlphaX/demo Activity stream and widget-test harness.
- Existing Material `Icons.auto_awesome_rounded` and `Icons.bookmark_rounded` conventions.

## Assumptions

- `spark` maps to `Icons.auto_awesome_rounded`; `bookmark` maps to `Icons.bookmark_rounded`, matching existing UI conventions.
- The existing bundled Activity test is extended in place; no new test declaration is needed.
- Unknown icon names continue to use `Icons.explore_rounded`; no separate fallback test is needed because the resolver's default remains unchanged.
- Validation targets only the changed Activity tile and app test files.

## Work Items

- [x] Audit bundled Activity icon values, decoder/model path, tile resolver, existing icon conventions, tests, and completed-task boundary.
- [x] Add the two shipped icon mappings and exact real bundled Activity icon assertions within the two-file scope.
- [x] Review the combined two-path diff for payload fidelity, fallback preservation, scope, and test adequacy.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named Activity test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed \
  lib/waypoint/presentation/widgets/waypoint_activity_tile.dart \
  test/waypoint_app_test.dart

flutter analyze \
  lib/waypoint/presentation/widgets/waypoint_activity_tile.dart \
  test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local Activity feed renders both shipped updates"

flutter test test/waypoint_app_test.dart
```

Only the two task-owned files are in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task number before implementation.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit two-file scope.

## Outcome

The bundled Activity `spark` and `bookmark` names now render as `Icons.auto_awesome_rounded` and `Icons.bookmark_rounded` through the existing tile resolver. The real local Activity stream test proves both mappings; existing aliases and the unknown-icon fallback remain unchanged.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:102-103` — bundled Activity icon names.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:181-190` — Activity icon decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_activity.dart:2-17` — typed Activity icon field.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_activity_tile.dart:21-63` — current icon resolver and fallback.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_activity_page.dart:114-121` — Activity tile rendering path.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:843-920` — existing real bundled Activity flow and exact icon assertions.
- `tasks/151-bundled-activity-stream-widget-coverage.md` — prior Activity coverage boundary.
- `tasks/177-bundled-trip-progress-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Faraday the 4th completed a read-only audit and identified the dropped bundled Activity icon mappings; no files changed.
- 2026-08-30 — Coordinator reserved Task 178 with a bounded two-file implementation, review, and local validation scope.
- 2026-08-30 — Laplace the 4th added the two shipped icon mappings and exact tile-scoped assertions to the existing bundled Activity test; worker-reported scoped checks passed.
- 2026-08-30 — Epicurus the 4th independently accepted the source with no High or Medium findings; stale task references were corrected before closure.
- 2026-08-30 — Coordinator direct scope check inspected the two task boundary paths: only `test/waypoint_app_test.dart` contains the intended Activity-test change, while `waypoint_activity_tile.dart` was inspected as unchanged after worker integration; `git status --short` reports the checkout as untracked with no usable baseline.
- 2026-08-30 — Coordinator validation passed: scoped `dart format --output=none --set-exit-if-changed` over the two paths (2 formatted, 0 changed); scoped `flutter analyze` over the two paths (no issues); named Activity test (`+1`); and `flutter test test/waypoint_app_test.dart` (`65` tests passed). No device, simulator, Docker, AWS, or unrelated test validation was run.
