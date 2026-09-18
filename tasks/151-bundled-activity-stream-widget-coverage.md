# Task 151 — Bundled Activity stream widget coverage

Status: [x] Completed

## Goal

Prove through the real bundled AlphaX/local transport that the Activity page
renders both shipped stream updates and returns to its idle state when the
finite stream completes.

## Scope and Non-goals

Scope:

- add exactly one local app widget test to the existing Waypoint app test file;
- construct the real `WaypointAlphaXDataSource` with zero-latency
  `WaypointDemoTransport`;
- open Activity, start the feed, assert both bundled activity titles render,
  and assert the control returns to `Start feed` after stream completion;
- close the injected source in test teardown.

Non-goals:

- changing production code, activity notifier behavior, provider lifetime,
  stream transport, data assets, decoder, retry or cancellation behavior;
- changing support fixtures, dependencies, other tests, or other screens;
- testing error recovery, explicit Stop, navigation-away cancellation, devices,
  simulators, Docker, AWS, hosting, deployment, or an online endpoint.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 150 bundled Saved-state widget coverage;
- existing auto-disposed Activity provider from Task 149;
- bundled `home.json` Activity entries;
- existing `WaypointAlphaXDataSource`, `WaypointDemoTransport`, and
  `WaypointActivityNotifier` stream path;
- existing Activity navigation and `waypoint-activity-toggle` key;
- existing `pumpWaypointTestApp` repository override seam.

## Assumptions

- zero-latency `WaypointDemoTransport` emits the finite bundled NDJSON stream
  without contacting the `waypoint.demo` URI;
- the real repository decodes both streamed activity records and the page
  prepends/renders them through the existing notifier;
- completion of the finite stream sets the control back to `Start feed`;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- a production defect exposed by this test is reported rather than expanding
  the test-only package.

## Work Items

- [x] Inspect the bundled Activity payload, local streaming transport,
  repository/notifier/page path, existing real-data test, and prior task
  boundaries.
- [x] Add exactly one real-source Activity rendering widget regression test.
- [x] Review the owned test for real-source usage, exact titles, stream
  completion, teardown, determinism, and scope.
- [x] Run only formatting, scoped analysis, the named widget test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome, validation evidence, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_app_test.dart`;
- `flutter analyze test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local Activity feed renders both shipped updates"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: formatting reported one file
  and zero changes; scoped analysis reported no issues; the named regression
  test passed once; and the full app widget test passed all forty-two tests.
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the intended one-file write set and final
observations directly:

- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` — SHA-256
  `606120e99bf9eaf89e5f7cf4b38d683a495f3a9ba39d897b19f667d9c642c27d`
- `testWidgets` declarations in `waypoint_app_test.dart` — `42`, including
  exactly one Task-151-named case.
- No temporary Task-151 debug diagnostics remain in the test file.

The worker reported no other implementation paths changed; the missing Git
baseline is retained as an explicit provenance limitation.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. One local widget test now exercises the real bundled AlphaX Activity
stream, verifies both shipped update titles, and proves the finite stream
returns the control to `Start feed`. The test clears the shared Flutter asset
cache after a verified full-suite interaction, waits for the loaded page with
a finite pump loop, and performs no external I/O. No production, dependency,
asset, support, platform, or deployment behavior changed.

## References

- `tasks/149-activity-navigation-away-cancellation.md`
- `tasks/150-bundled-saved-state-widget-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/home.json`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_repository.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_activity_notifier.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_activity_page.dart`
- `fixtures/flutter_conformance_app/test/waypoint_demo_data_test.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Volta the 3rd performed a read-only source audit after Task
  150. The audit found that the bundled transport emits the finite Activity
  stream and the page renders notifier results, while the real-data test only
  asserts the stream is non-empty and current widget tests use in-memory
  failure/cancellation sources. Task 151 is limited to one real-source local
  widget test.
- 2026-08-29: Chandrasekhar the 3rd added the requested test and reported the
  isolated named test passing. The required full app widget test failed at the
  Activity-page assertion because fixed setup/navigation pumps did not
  deterministically settle the real bundled home load in the full sequence.
  The coordinator reproduced the same failure and assigned a test-only pump
  correction; Task 151 remains open.
- 2026-08-29: The first correction replaced fixed pumps with `pumpAndSettle`,
  but the coordinator reproduced a timeout while the repeating loading
  skeleton was mounted. A second bounded test-only correction is assigned to
  wait for the concrete loaded page with a finite pump loop before settling
  navigation or stream completion.
- 2026-08-29: The coordinator reproduced that capped loop still left the home
  provider in `AsyncLoading` during the full file because an empty
  `tester.runAsync` callback did not yield the asset-bundle future. Temporary
  diagnostics confirmed the injected source was open and correctly installed;
  a final test-only correction is assigned to yield a zero-duration async
  future and remove the diagnostics.
- 2026-08-29: The zero-duration async yield and capped 40-attempt loop still
  reproduced the same full-file home-load assertion failure, although the
  named test passed in isolation. The coordinator recorded the provider as
  `AsyncLoading` with the injected source open and assigned a bounded
  diagnosis/fix rather than accepting a flaky test.
- 2026-08-29: Russell the 3rd diagnosed the full-file interaction as the
  shared Flutter `rootBundle` cache populated by the preceding bundled Saved
  test. The correction clears that cache only in the real-source widget test,
  retains the finite loaded-page wait, removes diagnostics, and reports the
  named test plus the full file passing with forty-two tests. Strict review and
  final coordinator validation remain pending.
- 2026-08-29: Franklin the 3rd strictly reviewed the corrected test and
  returned ACCEPT. The review verified the public test-only cache reset,
  finite wait, real local source, exact Activity titles, finite completion,
  absence of diagnostics, one-test scope, and provenance limitation.
- 2026-08-29: Coordinator reran the planned changed-file validation: format
  exited 0 with one file unchanged, scoped analysis exited 0 with no issues,
  the named test passed once, and the full app widget test exited 0 with all
  forty-two tests passing.
