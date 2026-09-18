# Task 186 — Bundled supplemental trip documents

Status: [x] Completed

## Goal

Expose the bundled supplemental Kyoto document in the local Trips detail sheet without changing the home trip’s authoritative fields or order.

## Scope and Non-goals

Scope:

- Update the local bundled-trip merge in `waypoint_data_source.dart` so a supplemental trip with an existing ID contributes only document records not already present on the home trip.
- Extend the existing real bundled Trips document coverage to assert the supplemental document’s content and `note` icon.

Non-goals:

- Do not change JSON/assets, models, decoder, Trips UI layout, home-trip non-document fields, trip ordering, or unrelated transport routes.
- Do not replace the home trip with the supplemental duplicate, append duplicate trip rows, duplicate document names, or merge checklist/itinerary/progress fields.
- Do not add generic merge infrastructure, new dependencies, a new test file, or tests outside `test/waypoint_app_test.dart`.
- Do not add document download/open/share behavior or platform, device, simulator, Docker, AWS, hosting, or deployment work.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Existing `home.json` Kyoto trip and `trips.json` supplemental duplicate.
- Existing `WaypointDemoTransport._loadHome` trip merge.
- Existing trip document model/decoder and Trips detail document rendering/icon mapping.
- Existing real zero-latency bundled Trips widget tests.

## Assumptions

- `home.json` remains authoritative for an existing trip’s non-document fields and existing document records.
- The supplemental `kyoto-notes` record contributes `Rail pass note.txt`, `Travel note`, `12 KB`, and `icon: note`.
- Document names are the stable identity available in the bundled payload for preventing duplicate rows; existing home documents win on name collisions.
- The existing Kyoto detail sheet can render both documents without a layout change.
- Validation targets only the two changed source/test paths.

## Work Items

- [x] Audit both bundled trip records, current merge behavior, document decoder/UI/icon path, existing tests, and prior merge contract.
- [x] Merge only missing supplemental documents into an existing home trip while preserving home fields/order and unseen-trip behavior.
- [x] Extend existing real bundled Trips document coverage for the supplemental document, note icon, and duplicate prevention.
- [x] Review the combined two-file diff for merge correctness, home-field preservation, duplicate prevention, empty-document compatibility, and deterministic source coverage.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named document test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed \
  lib/waypoint/data/waypoint_data_source.dart \
  test/waypoint_app_test.dart

flutter analyze \
  lib/waypoint/data/waypoint_data_source.dart \
  test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local Trips detail renders its shipped document"

flutter test test/waypoint_app_test.dart
```

Only `lib/waypoint/data/waypoint_data_source.dart` and `test/waypoint_app_test.dart` are in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task number before implementation.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit two-file scope.

## Outcome

The local bundled-trip merge now preserves the home Kyoto trip and adds only the supplemental `Rail pass note.txt` document from the duplicate ID record. The real Trips detail test proves both documents, exactly two rows, and the `note` icon; unseen supplemental trips and empty documents remain supported. No JSON, model, decoder, UI, or dependency changes were made.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:25-47` — authoritative home Kyoto trip and existing document.
- `fixtures/flutter_conformance_app/assets/data/trips.json:5-28` — supplemental Kyoto trip and `Rail pass note.txt`.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:287-329` — duplicate-ID trip merge and supplemental-document merge.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:131-153` — document-list decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart:254-317` — document rendering and `note` icon mapping.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:1188-1281` — expanded real bundled document test boundary.
- `tasks/152-trip-document-detail-coverage.md` — existing document model/section boundary.
- `tasks/154-bundled-secondary-trip-coverage.md` — existing unseen-trip merge contract.
- `tasks/167-bundled-trip-document-icon-coverage.md` — existing document icon mapping boundary.
- `tasks/185-bundled-offer-accent-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Mill the 4th completed a fresh read-only audit and identified the discarded supplemental Kyoto document; no files changed.
- 2026-08-30 — Coordinator directly verified the duplicate trip payloads, current unseen-ID-only merge, document decoder/UI support, and existing real-source test boundary.
- 2026-08-30 — Coordinator reserved Task 186 with a bounded two-file implementation, review, and local validation scope.
- 2026-08-30 — Boyle the 4th updated the local duplicate-ID merge to add only missing document names and extended the existing bundled document test; worker-reported formatting and named validation passed.
- 2026-08-30 — Hubble the 4th independently accepted the code with no High or Medium findings; two Low stale task-reference ranges were corrected before closure.
- 2026-08-30 — Coordinator corrected the merge and test references to `data_source.dart:287-329` and `waypoint_app_test.dart:1188-1281`; Ohm the 4th performed final strict review and accepted with no findings.
- 2026-08-30 — Coordinator direct scope check found only `waypoint_data_source.dart` and `waypoint_app_test.dart` newer than the Task 186 record among task-owned source paths; the checkout has no usable Git `HEAD`, so scope provenance is based on direct file inspection.
- 2026-08-30 — Coordinator validation passed: scoped `dart format --output=none --set-exit-if-changed` over the two paths (`Formatted 2 files (0 changed)`); scoped `flutter analyze` over the two paths (`No issues found`); named document selector passed two matching document tests (`+2`); and `flutter test test/waypoint_app_test.dart` passed (`68` tests). No device, simulator, Docker, AWS, hosting, or unrelated test validation was run.
