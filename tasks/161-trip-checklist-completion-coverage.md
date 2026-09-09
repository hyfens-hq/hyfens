# Task 161 — Trip checklist completion coverage

Status: [x] Completed

## Goal

Preserve the shipped trip checklist title, detail, and completion state in
typed data, then make the existing Trips detail checklist toggleable for the
current sheet session.

## Scope and Non-goals

Scope:

- add a typed checklist-item model containing title, optional detail, and
  completion state;
- decode object checklist entries from the existing bundled payload and keep
  legacy string entries as unchecked items;
- render checked/unchecked checklist rows with their source detail in the
  existing Trips detail sheet;
- support session-local toggling while the detail sheet is open;
- add exactly one real zero-latency bundled-source widget test asserting the
  shipped state and one toggle.

Non-goals:

- changing JSON/assets, transport, persistence, backend/network calls, trip
  progress calculation, itinerary/documents, navigation, search, permissions,
  platform files, dependencies, devices, simulators, Docker, AWS, hosting,
  deployment, or external services;
- changing checklist order or source values, adding a checklist repository,
  editing outside the Trips detail sheet, or tests outside the owned app test
  file.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Write Set

The implementation owns exactly these five paths:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_checklist_item.dart`
  (new);
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_trip.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.

The coordinator owns this task record and its later evidence updates.

## Dependencies

- completed Task 160;
- existing bundled `home.json` checklist entries and local AlphaX/demo
  transport;
- existing trip model/decoder, Trips detail sheet, and widget-test seam.

## Assumptions

- the checked-in checklist payload is the source of truth and will not be
  edited;
- object entries use the shipped `title`, `detail`, and `done` fields; legacy
  string entries remain supported as unchecked items;
- toggling is in-memory for the open detail sheet only and does not mutate the
  repository, home data, progress, or persisted state;
- missing/non-string detail is absent rather than rendered as a placeholder;
- the worker owns only the five paths listed above and must preserve unrelated
  shared-checkout edits;
- validation uses only the changed app scope and local bundled data.

## Work Items

- [x] Audit the shipped checklist payload, current decoder/model/UI, existing
  tests, and Task 145 exclusions.
- [x] Add the typed checklist item and legacy-compatible decode/model path.
- [x] Render source title/detail and checked state in the Trips detail sheet.
- [x] Add session-local checklist toggling without persistence or progress
  mutation.
- [x] Add exactly one real bundled-source widget regression test.
- [x] Review the combined task-owned diff for payload fidelity, legacy
  compatibility, state isolation, layout, semantics, and scope.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/domain/waypoint_checklist_item.dart`
  `lib/waypoint/domain/waypoint_trip.dart`
  `lib/waypoint/data/waypoint_json_decoder.dart`
  `lib/waypoint/presentation/screens/waypoint_trips_page.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze` on the same five paths;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local Trips detail toggles checklist completion"`;
- `flutter test test/waypoint_app_test.dart`;
- no unrelated tests, devices, simulators, Docker, AWS, or hosted-service
  checks.

Coordinator validation results:

- `dart format --output=none --set-exit-if-changed` on the five owned paths:
  passed; 5 files inspected, 0 changed.
- `flutter analyze` on the five owned paths: passed with no issues.
- `flutter test test/waypoint_app_test.dart --plain-name "bundled local Trips
  detail toggles checklist completion"`: passed, 1 test.
- `flutter test test/waypoint_app_test.dart`: passed, all 52 tests.
- Faraday the 3rd independently reviewed the combined diff and returned
  `ACCEPT`; no blocking findings were identified.
- No unrelated tests or device, simulator, Docker, AWS, or hosted-service
  checks were run.

Scope Manifest (coordinator capture after validation; repository has no
usable Git `HEAD` for a baseline comparison):

- `lib/waypoint/domain/waypoint_checklist_item.dart` —
  `235d194a272a8c1fcddd9ac30e1bfddd8ae44078739d56f6b6335abcbe0db90c`
- `lib/waypoint/domain/waypoint_trip.dart` —
  `fe8d83c6fb1cdc3c53e60f0a87d0c454d9332edfb978d3a4e19bb4539bd740ea`
- `lib/waypoint/data/waypoint_json_decoder.dart` —
  `74afe98c89e68c9ddc5270d7bbff44e0b76d97cad3d84574d91c9b081e1c2904`
- `lib/waypoint/presentation/screens/waypoint_trips_page.dart` —
  `81ede46b19aae19f991847376824bb07107ae38b630678e60ee718bcf3be07cf`
- `test/waypoint_app_test.dart` —
  `420208175a44f9712309721cf27741f56c00562129a65ce555284169d2daa83e`
- Test declaration count in the owned app test file: `52`.

## Next Action

Perform the next read-only audit for the highest-value local, non-AWS gap,
excluding completed Tasks 150–161 and preserving the same bounded validation
policy.

## Blockers

None known.

## Outcome

Implemented typed checklist title/detail/completion data, preserved legacy
string entries, rendered source details and checked state, and added
session-local completion toggling in the Trips detail sheet. The bundled
zero-latency regression test verifies shipped data and one toggle. Independent
strict review returned `ACCEPT`, and coordinator validation passed all 52 app
tests. No persistence, progress mutation, JSON change, dependency change,
platform change, or deployment/AWS work was introduced.

## References

- `tasks/160-bundled-discover-categories-coverage.md`
- `tasks/145-trips-checklist-detail-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/home.json:41-43`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_trip.dart:4-30`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:139-141,280-285`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart:175-205`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:1236-1272`

## History

- 2026-08-29: Bohr the 3rd performed a read-only audit and found that bundled
  checklist `title`, `detail`, and `done` values are reduced to labels and
  rendered as fixed bullets without completion controls. The audit found no
  files edited and proposed this bounded five-path package.
- 2026-08-30: Linnaeus the 3rd implemented the bounded five-path package and
  reported the targeted and full app tests passing with 52 tests.
- 2026-08-30: Faraday the 3rd independently reviewed the combined diff and
  returned `ACCEPT`; the typed decode, legacy compatibility, session-local
  state, semantics, and scope were factually verified.
- 2026-08-30: Coordinator ran the planned format, scoped analysis, named test,
  and full app test. All passed; the task was marked completed with the scope
  manifest above.
