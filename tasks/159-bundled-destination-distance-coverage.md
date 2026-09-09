# Task 159 — Bundled destination distance coverage

Status: [x] Completed

## Goal

Carry the shipped destination `distance` values into the typed model and render
an optional distance label on the shared destination card, with real local
coverage for the bundled data.

## Scope and Non-goals

Scope:

- add an optional `distance` field to `WaypointDestination` and preserve it in
  `copyWith`;
- decode the existing bundled `distance` field without changing its value;
- render non-empty distance text on the existing destination card;
- add exactly one real zero-latency bundled-source widget test asserting
  `0.8 km from your route`.

Non-goals:

- changing JSON/assets, search/filter/saved behavior, other destination fields,
  destination detail behavior, permissions/platform files, dependencies,
  devices, simulators, Docker, AWS, hosting, deployment, or external services;
- inventing or reformatting distance values, adding a distance service, broad
  card redesign, or tests outside the owned app test file.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Write Set

The implementation owns exactly these four paths:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_destination.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.

The coordinator owns this task record and its later evidence updates.

## Dependencies

- completed Task 158;
- existing bundled `home.json`/`discover.json` place maps and local AlphaX/demo
  transport;
- existing destination model decoder, shared destination card, and widget-test
  seam.

## Assumptions

- the checked-in bundled `distance` values are the source of truth and will not
  be edited;
- missing or non-string distance data remains absent and does not create
  placeholder text;
- `copyWith` and all existing destination behavior remain compatible;
- the worker owns only the four paths listed above and must preserve unrelated
  shared-checkout edits;
- validation uses only the changed app scope and local bundled data.

## Work Items

- [x] Audit the bundled distance fields, destination model/decoder, shared card,
  and existing local test seam.
- [x] Add optional distance to the model and decoder while preserving copy
  behavior.
- [x] Render non-empty distance on the existing destination card without
  disturbing the existing metadata layout.
- [x] Add exactly one real bundled-source widget regression test.
- [x] Review the combined task-owned diff for payload fidelity, missing-value
  compatibility, layout, saved/search behavior, determinism, and scope.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/domain/waypoint_destination.dart`
  `lib/waypoint/data/waypoint_json_decoder.dart`
  `lib/waypoint/presentation/widgets/waypoint_destination_card.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze` on the same four paths;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local demo renders destination distance"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: format reported four files and
  zero changes; scoped `flutter analyze` reported no issues; the named
  destination-distance test passed; and the full changed app widget test passed
  all fifty tests.
- no unrelated tests, devices, simulators, Docker, AWS, or hosted-service
  checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the declared four-file write set and final
observations directly:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_destination.dart`
  — SHA-256 `a8f814fd393d275b690f7e8170823b6a7240fd44f240d28f0403353fa88bcbeb`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`
  — SHA-256 `d0be119fae71956ce6945590f57457c6357c34a772aa7b02e9b7ca7e89f19ca3`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart`
  — SHA-256 `be3e658d0eff3fb0239e85d3bf94c016ee34a00c85867e0677a035de6c1f7066`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
  — SHA-256 `0c82ca6fb64225f46e409371d5197cd3319e4733539c8c7489ba7bf24352772b`.

The app test contains 50 `testWidgets` declarations, including exactly one
Task-159-named case. The implementation worker reported no other paths
changed. The missing Git `HEAD` remains an explicit provenance limitation.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. The bundled destination distance now survives the local payload and
decoder into an optional typed model field, is preserved by `copyWith`, and is
rendered only when non-empty on the shared destination card. The strict
reviewer returned ACCEPT with no verified findings, and the coordinator final
changed-scope validation passed. No fixture payload, dependency, platform,
device, deployment, AWS, hosting, or external-service behavior changed.

## References

- `tasks/158-bundled-search-suggestions-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/home.json:69-99`
- `fixtures/flutter_conformance_app/assets/data/discover.json:15-59`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:306-308`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_destination.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:74-90`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart:66-104`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Kant the 3rd performed a read-only audit and found that shipped
  place `distance` fields are preserved in local payload maps but dropped by
  the destination model/decoder and never rendered by the shared card. The
  audit found no files edited and proposed this bounded four-path package.
- 2026-08-29: Socrates the 3rd implemented the four-path package, adding
  optional distance decode/copy preservation, compact non-empty card text, and
  exactly one real zero-latency bundled-source widget test for the shipped
  `0.8 km from your route` value. The worker reported focused format, analysis,
  and named-test success.
- 2026-08-29: Gauss the 3rd performed an independent strict fact-based review
  and returned ACCEPT. It verified exact source flow, optional fallback,
  `copyWith` preservation, card layout, semantics, compatibility, deterministic
  local setup, and four-path scope. No blocking finding was reported.
- 2026-08-29: Coordinator reran the planned changed-file validation after
  review: format exited 0 with four files unchanged, scoped analysis exited 0
  with no issues, the named destination-distance test exited 0, and the full
  `waypoint_app_test.dart` file exited 0 with all fifty tests passing.
