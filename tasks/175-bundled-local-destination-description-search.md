# Task 175 — Bundled local destination-description search

Status: [x] Completed

## Goal

Make the existing local search path match destination descriptions as well as the already-supported name, country, category, and location fields, and prove the bundled description search with a real local demo flow.

## Scope and Non-goals

Scope:

- Include the raw local payload's `description`/`summary` value in the existing demo transport search haystack.
- Keep the in-memory test data source's search behavior aligned with its existing `summary` payload field.
- Add one real zero-latency bundled-source widget regression test for a description-only query (`old city` → `Rose Courtyard`).

Non-goals:

- Do not edit JSON/assets, domain models, decoder, repository, search UI, query normalization, filters, suggestions, retry/race behavior, ranking, fuzzy matching, planner/offer/permission behavior, dependencies, or infrastructure.
- Do not alter empty-query behavior or existing case-insensitive substring semantics.
- Do not create a generic search engine or change completed task files.
- No device, simulator, Docker, AWS, online hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Existing bundled `discover.json` place descriptions.
- Existing `WaypointDemoTransport` and `WaypointTestDataSource` search routes.
- Existing `WaypointDestination.summary` decoder mapping and Discover search UI.
- Existing zero-latency bundled app-test setup.

## Assumptions

- The raw bundled alias is `description`, while the in-memory test payload uses `summary`; both should be matched as source data without changing the domain contract.
- Search continues to trim and lowercase the query, join fields, and use case-insensitive substring matching.
- The description query test uses the real `WaypointAlphaXDataSource` with `WaypointDemoTransport(latency: Duration.zero)`, not only the in-memory test double.
- The new regression test is added to the existing `waypoint_app_test.dart`; no unrelated test files are changed.

## Work Items

- [x] Audit the search routes, raw bundled description fields, decoder/model mapping, existing test doubles, current tests, and completed-task boundary.
- [x] Include description/summary in the two existing local search haystacks and add the real bundled description-query regression test within the three-file scope.
- [x] Review the combined three-path diff for query semantics, payload fidelity, scope, and test adequacy.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named description-search test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed \
  lib/waypoint/data/waypoint_data_source.dart \
  test/waypoint_test_support.dart \
  test/waypoint_app_test.dart

flutter analyze \
  lib/waypoint/data/waypoint_data_source.dart \
  test/waypoint_test_support.dart \
  test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local demo searches destination descriptions"

flutter test test/waypoint_app_test.dart
```

Only the three task-owned files are in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task number before implementation.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit three-file scope.

## Outcome

The local demo and in-memory search haystacks now include description/summary text without changing existing query behavior. The real bundled `old city` flow finds Rose Courtyard and excludes the real bundled Lantern House candidate. The initial vacuous non-match assertion was corrected and the fresh strict review accepted the result.

## References

- `fixtures/flutter_conformance_app/assets/data/discover.json:21-49` — bundled descriptions, including Rose Courtyard's “old city” text.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:254-267` — demo search haystack currently omits description/summary.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:287-313` — local home/discover payload merge used by the demo search route.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:111-120` — description-to-summary mapping already exists.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_destination.dart:12-35` — destination summary is already typed.
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart:398-415` — in-memory summary payload and current search double.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:2074-2090` — existing name-query search coverage.
- `tasks/158-bundled-search-suggestions-coverage.md` — prior task explicitly left search matching unchanged.
- `tasks/174-bundled-offer-dismissibility-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Faraday the 4th completed a read-only audit and identified the missing description field in both local search haystacks; no files changed.
- 2026-08-30 — Coordinator reserved Task 175 with a bounded three-file implementation, review, and local validation scope.
- 2026-08-30 — James the 4th implemented the two haystack additions and the real bundled `old city` search test; worker-reported scoped checks passed.
- 2026-08-30 — Singer the 4th rejected the test evidence: `waypoint-destination-kyoto` is not a bundled destination, so the non-match assertion is vacuous. Required correction is limited to asserting a real bundled candidate such as `lantern-house` before and after the search.
- 2026-08-30 — James the 4th corrected only the existing bundled description-search test, asserting `lantern-house` is present before the query and absent after it; the focused test passed.
- 2026-08-30 — Kepler the 4th independently accepted the corrected three-file implementation with no findings.
- 2026-08-30 — Coordinator validation passed: scoped `dart format --output=none --set-exit-if-changed` over the three paths (3 formatted, 0 changed); scoped `flutter analyze` over the three paths (no issues); named description-search test (`+1`); and `flutter test test/waypoint_app_test.dart` (`63` tests passed). No device, simulator, Docker, AWS, or unrelated test validation was run.
