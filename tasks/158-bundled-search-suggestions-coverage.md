# Task 158 — Bundled search suggestions coverage

Status: [x] Completed

## Goal

Carry the four bundled Discover search suggestions into typed home data and
render them as source-driven quick-search chips that use the existing query and
local search flow.

## Scope and Non-goals

Scope:

- preserve the existing `discover.json` `searchSuggestions` values through the
  local AlphaX/demo home payload;
- add an optional typed suggestions list to `WaypointHomeData` and decode it;
- render stable-keyed quick-search chips on Discover when suggestions exist;
- make a chip update the visible search field and invoke the existing search
  notifier with that suggestion;
- add exactly one real zero-latency bundled-source widget test proving the
  shipped suggestions and one chip interaction.

Non-goals:

- changing `discover.json`, search matching, filters/categories, collections,
  route-preview video, Tasks 150–157 behavior, permissions/platform files,
  dependencies, devices, simulators, Docker, AWS, hosting, deployment, or
  external services;
- inventing suggestions, adding persistence, changing repository/API
  contracts, adding a generic chip/action registry, or broad UI refactoring;
- tests outside the owned app test file.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Write Set

The implementation owns exactly these five paths:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.

The coordinator owns this task record and its later evidence updates.

## Dependencies

- completed Task 157;
- existing `discover.json` `searchSuggestions` payload;
- existing home model/decoder, local AlphaX/demo transport, search field,
  `WaypointSearchNotifier`, and widget-test seam.

## Assumptions

- the checked-in bundled suggestions are the source of truth and will not be
  edited;
- suggestions are optional for compatibility with minimal or older payloads;
- tapping a suggestion uses the same normalized query path as manual typing and
  does not alter search matching or persistence;
- stable widget keys are derived only from the source suggestion index/value;
- the worker owns only the five paths listed above and must preserve unrelated
  shared-checkout edits;
- validation uses only the changed app scope and local bundled data.

## Work Items

- [x] Audit the bundled suggestions, transport/model/decoder path, Discover
  search field, search notifier, and existing manual-search coverage.
- [x] Thread bundled suggestions through the local transport, home data, and
  decoder.
- [x] Render source-driven quick-search chips and wire their interaction to the
  existing query/search flow.
- [x] Add exactly one real bundled-source widget regression test.
- [x] Review the combined task-owned diff for payload fidelity, optional-data
  fallback, controller/query synchronization, search behavior, layout,
  determinism, and scope compliance.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/domain/waypoint_home_data.dart`
  `lib/waypoint/data/waypoint_data_source.dart`
  `lib/waypoint/data/waypoint_json_decoder.dart`
  `lib/waypoint/presentation/screens/waypoint_discover_page.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze` on the same five paths;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local demo renders its search suggestions"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: format reported five files and
  zero changes; scoped `flutter analyze` reported no issues; the named search-
  suggestions test passed; and the full changed app widget test passed all
  forty-nine tests.
- no unrelated tests, devices, simulators, Docker, AWS, or hosted-service
  checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the declared five-file write set and final
observations directly:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart`
  — SHA-256 `c475b2a7255ad5b37ef2312600ae028fcaaebbad7ad919a63e11cacf0900e197`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`
  — SHA-256 `6ebca105d67f2ae2125b6a7c821dccbc22305ad13697f2ff95974874dad31feb`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`
  — SHA-256 `e3f62161e7aa5083c3023f035588d118f44eabfcda2c3330af181312cea50b67`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`
  — SHA-256 `e5cd6631a95604c165a4f957ba43846d934c4bf133909ca060232036eb742abd`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
  — SHA-256 `1c239bd302c509122fcc6640b3c9c2c4e27e5f7a00805980de830dea0ba8379e`.

The app test contains 49 `testWidgets` declarations, including exactly one
Task-158-named case. The implementation and correction workers reported no
other paths changed. The missing Git `HEAD` remains an explicit provenance
limitation.

## Next Action

Assign the five-path implementation package to one Luna Max worker, then
obtain an independent strict review before coordinator validation.

## Blockers

None known.

## Outcome

Accepted. The four shipped search suggestions now survive the local
AlphaX/demo transport and decoder into optional typed home data, render as
source-driven Discover chips, and update the visible query through the
existing search notifier when selected. Malformed optional suggestion data now
fails closed to an empty/valid-string list. The initial strict review finding
was corrected, the independent re-review returned ACCEPT, and the coordinator
final changed-scope validation passed. No fixture payload, dependency,
platform, device, deployment, AWS, hosting, or external-service behavior
changed.

## References

- `tasks/157-bundled-route-preview-action-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/discover.json:62`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:302-315`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart:121-136`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_search_notifier.dart:16-33`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:1284-1301`

## History

- 2026-08-29: Hilbert the 3rd performed a read-only audit and found that the
  four bundled `searchSuggestions` values are present in `discover.json` but
  are not copied, modeled, decoded, rendered, or covered by a source-driven
  interaction test. The audit found no files edited and proposed this bounded
  five-path package.
- 2026-08-29: Aristotle the 3rd performed an independent strict fact-based
  review. It verified the source flow, chip interaction, test scope, and
  passing named/full checks, but returned REJECT because the optional
  `searchSuggestions` decoder reused a throwing/stringifying helper for
  malformed values. The exact correction is to fail closed for non-lists and
  retain only valid strings.
- 2026-08-29: Laplace the 3rd applied only the verified decoder correction in
  `waypoint_json_decoder.dart`. A search-specific helper now returns an empty
  list for non-lists and keeps only actual string entries; the shared helper
  and four shipped values are unchanged. Focused format and analysis passed;
  tests were not run by the correction worker.
- 2026-08-29: Huygens the 3rd performed an independent strict re-review and
  returned ACCEPT. It verified the correction, exact source values, typed
  transport/model/decoder flow, controller synchronization, existing search
  invocation, stable chip keys, optional UI behavior, and five-path scope. Its
  named and full changed-file checks passed with forty-nine tests.
- 2026-08-29: Coordinator reran the planned changed-file validation after
  re-review: format exited 0 with five files unchanged, scoped analysis exited
  0 with no issues, the named search-suggestions test exited 0, and the full
  `waypoint_app_test.dart` file exited 0 with all forty-nine tests passing.
