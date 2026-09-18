# Task 160 — Bundled Discover categories coverage

Status: [x] Completed

## Goal

Carry the four bundled Discover category records into typed home data and show
their source-driven labels and icon treatments on Discover without changing the
existing filter semantics.

## Scope and Non-goals

Scope:

- add a typed category model containing the shipped `id`, `label`, and `icon`;
- preserve and decode the existing Discover category list through the local
  AlphaX/demo home payload;
- render an optional display-only, stable-keyed category-chip section on
  Discover using the source labels and a small known-icon mapping with a safe
  fallback;
- add exactly one real zero-latency bundled-source widget test asserting the
  four shipped labels and category keys.

Non-goals:

- changing `discover.json`, assets, search suggestions, collections,
  route-preview video, existing `WaypointDestinationFilter` values or
  semantics, search matching, Tasks 150–159 behavior, permissions/platform
  files, dependencies, devices, simulators, Docker, AWS, hosting, deployment,
  or external services;
- making category chips navigate, filter, persist state, or invent mappings
  for category IDs that do not match the existing filter enum;
- generic icon registries, broad UI refactoring, or tests outside the owned app
  test file.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Write Set

The implementation owns exactly these six paths:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_discover_category.dart`
  (new);
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.

The coordinator owns this task record and its later evidence updates.

## Dependencies

- completed Task 159;
- existing `discover.json` category records and local AlphaX/demo transport;
- existing home model/decoder, Discover screen, `Chip`/`Wrap` UI primitives, and
  widget-test seam.

## Assumptions

- the checked-in four category records are the source of truth and will not be
  edited;
- categories are optional: a missing/non-list value renders no category
  section, and malformed entries do not create placeholder labels;
- the icon field is a source identifier, not a request to add dynamic icon
  loading; only the four shipped identifiers need explicit mappings and an
  existing generic icon is the fallback;
- chips are display-only because the source data does not provide a verified
  category action/filter contract;
- the worker owns only the six paths listed above and must preserve unrelated
  shared-checkout edits;
- validation uses only the changed app scope and local bundled data.

## Work Items

- [x] Audit the bundled category records, transport/model/decoder path, current
  hardcoded filter bar, and local test seam.
- [x] Add the typed optional category data and preserve/decode it from the local
  Discover payload.
- [x] Render stable-keyed display-only category chips with known icon mapping
  and safe fallback.
- [x] Add exactly one real bundled-source widget regression test.
- [x] Review the combined task-owned diff for exact payload fidelity, optional
  malformed-data fallback, icon behavior, layout, filter compatibility,
  determinism, and scope.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/domain/waypoint_discover_category.dart`
  `lib/waypoint/domain/waypoint_home_data.dart`
  `lib/waypoint/data/waypoint_data_source.dart`
  `lib/waypoint/data/waypoint_json_decoder.dart`
  `lib/waypoint/presentation/screens/waypoint_discover_page.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze` on the same six paths;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local demo renders its Discover categories"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: format reported six files and
  zero changes; scoped `flutter analyze` reported no issues; the named
  Discover-categories test passed; and the full changed app widget test passed
  all fifty-one tests.
- no unrelated tests, devices, simulators, Docker, AWS, or hosted-service
  checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the declared six-file write set and final
observations directly:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_discover_category.dart`
  — SHA-256 `65638cc5dd2552ab07d5ad4efb856361d7f39c172be6ee7f0b8d85a590b41342`;
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart`
  — SHA-256 `d03b431b2cf8362bbcab56fcdcc749325a74207e79078607d8649ca34b9f8019`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`
  — SHA-256 `ca0f62483d836c3983093652b2d7106882f892232ede9b639646b454744695f9`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`
  — SHA-256 `0ccf46cc35ab3c7e33a0e003aad101e411335c24e0626845f58e490f680a7813`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`
  — SHA-256 `1dc884a6b071bc5e94489ddf6fef08c7f1ffa4fa84a6fc45f91e4144fe9c6251`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
  — SHA-256 `481c46abc48969effb318183eca91651b8a03af6aacdfd94662fb7fe629144c7`.

The app test contains 51 `testWidgets` declarations, including exactly one
Task-160-named case. The implementation worker reported no other paths
changed. The missing Git `HEAD` remains an explicit provenance limitation.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. The four shipped Discover category records now survive the local
AlphaX/demo transport and decoder into typed optional home data, render as
source-driven display-only chips with exact labels, stable keys, known icon
mappings, and a safe fallback, while existing filters remain unchanged. The
strict reviewer returned ACCEPT with no verified findings, and the coordinator
final changed-scope validation passed. No fixture payload, dependency,
platform, device, deployment, AWS, hosting, or external-service behavior
changed.

## References

- `tasks/159-bundled-destination-distance-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/discover.json:5-10`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:302-311`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart:140-141,568-590`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Erdos the 3rd performed a read-only audit and found that the
  four bundled Discover category records are present in `discover.json` but
  are not forwarded, modeled, decoded, rendered, or covered by a local
  source-driven test. The audit found no files edited and proposed this
  bounded six-path package.
- 2026-08-29: Rawls the 3rd implemented the six-path package, adding optional
  malformed-safe category decoding, source-driven display-only chips with
  known icon mappings and fallback, and exactly one real zero-latency
  bundled-source widget test. The worker reported focused format, analysis,
  and named-test success.
- 2026-08-29: Tesla the 3rd performed an independent strict fact-based review
  and returned ACCEPT. It verified exact category values and flow, malformed
  fallback, icon behavior, stable keys, display-only semantics, layout,
  unchanged filters, deterministic local testing, and six-path scope. Its
  full-file attempt was interrupted and therefore not claimed.
- 2026-08-29: Coordinator reran the planned changed-file validation after
  review: format exited 0 with six files unchanged, scoped analysis exited 0
  with no issues, the named category test exited 0, and the full
  `waypoint_app_test.dart` file exited 0 with all fifty-one tests passing.
