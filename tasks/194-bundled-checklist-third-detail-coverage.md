# Task 194 — Bundled checklist third-item detail coverage

Status: [/] Cancelled

## Goal

Prove that the real bundled Kyoto checklist’s third-item detail reaches its rendered checklist row.

## Scope and Non-goals

Scope:

- Extend the existing real bundled checklist widget test with one exact assertion scoped to the third checklist row.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, renderer, checklist state behavior, navigation, dependencies, or infrastructure.
- Do not add a new test declaration or test file; do not change tests outside `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
- Do not use synthetic checklist data or a global/ambiguous text assertion.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled Kyoto third checklist item detail in `trips.json`.
- Existing checklist decoding and `CheckboxListTile` rendering/keying in `WaypointTripsPage`.
- Existing real zero-latency bundled checklist test with rows 0 and 1 assertions, navigation, and cleanup.

## Assumptions

- The third Kyoto checklist row is keyed `waypoint-trip-checklist-item-kyoto-notes-2` and renders `Send the plan to your travel group` as its subtitle.
- The row key plus descendant finder uniquely scopes the detail assertion to the third bundled checklist item.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit the bundled third-item detail, decoder/model/rendering path, existing coverage, and completed-task boundary.
- [/] Add one exact third-row-scoped detail assertion to the existing checklist test; cancelled after the real bundled test returned zero matches.
- [x] Review the corrective cleanup for contract fidelity, stable supported-row scoping, and preservation of existing assertions.
- [x] Obtain strict independent review of the cleanup and resolve the disposition finding.
- [x] Run scoped format, analysis, and the named checklist test after cleanup.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after the corrective cleanup and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local Trips detail toggles checklist completion"

```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required because the proposed assertion was cancelled.

## Next Action

Do not reopen this task without an explicit product/data-contract decision to make supplemental checklist data authoritative or mergeable; continue auditing the next valid local capability.

## Blockers

No technical blocker exists in the supported contract. The proposed third-row assertion is cancelled because `home.json` is authoritative for duplicate-trip non-document fields and Task 186 explicitly excludes checklist merging; any change requires a new decision and task. The repository has no usable Git `HEAD`; review used direct file evidence and the explicit cleanup scope.

## Outcome

Cancelled after direct validation showed that the proposed third checklist row is present only in the supplemental duplicate `trips.json` record and is not rendered by the supported `/api/trips/kyoto-notes` path. `home.json` supplies the authoritative two-row checklist, while the current loader merges only supplemental documents for an existing trip ID. Task 186 explicitly prohibits merging checklist, itinerary, or progress fields. The failing assertion was removed; the supported two-row assertions, toggle behavior, navigation, and cleanup remain intact. No production, fixture, dependency, device, simulator, Docker, AWS, hosting, or deployment changes were made.

Disposition validation passed from `fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` — `Formatted 1 file (0 changed)`.
- `flutter analyze test/waypoint_app_test.dart` — `No issues found!`.
- `flutter test test/waypoint_app_test.dart --plain-name "bundled local Trips detail toggles checklist completion"` — `+1: All tests passed!`.

The repository has no usable Git `HEAD`; review and scope evidence therefore used direct file inspection. No unrelated test files were validated.

## References

- `fixtures/flutter_conformance_app/assets/data/trips.json:20-24` — bundled Kyoto checklist third-item detail.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:145-147` — checklist list decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_checklist_item.dart:1-10` — checklist title/detail model fields.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart:228-249` — keyed checklist row and detail rendering.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:1400-1484` — supported real bundled checklist test and row 0/1 assertions after cleanup.
- `fixtures/flutter_conformance_app/assets/data/home.json:41-43` — authoritative two-row Kyoto checklist.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:287-330` — duplicate-trip loader and document-only merge behavior.
- `tasks/186-bundled-trip-document-merge.md` — prior bundled trip-detail data boundary.
- `tasks/193-bundled-destination-card-rating-duration-coverage.md` — prior completed local coverage task.

## History

- 2026-08-30 — Pasteur the 4th completed a focused read-only scan and identified unasserted bundled Kyoto checklist third-item detail propagation; no files changed.
- 2026-08-30 — Coordinator directly verified the bundled detail, decoder/model mapping, keyed row renderer, existing test seam, and coverage boundary.
- 2026-08-30 — Coordinator reserved Task 194 with a bounded single-file test implementation, review, and local validation scope.
- 2026-08-30 — Avicenna the 4th added the proposed third-row assertion, but its named real bundled test failed with zero matches; no broad tests ran.
- 2026-08-30 — Pascal the 4th independently diagnosed the source mismatch and confirmed Task 186’s document-only duplicate-trip contract; recommended cancellation without a production merge.
- 2026-08-30 — Bernoulli the 4th removed only the failing third-row assertion; the supported checklist test passed.
- 2026-08-30 — Plato the 4th strictly reviewed the cleanup and returned `ACCEPT — no findings`, verifying preserved supported assertions, contract fidelity, and no separate third-item test.
- 2026-08-30 — Coordinator completed disposition validation: format clean, analyzer clean, and the named checklist test passed.
