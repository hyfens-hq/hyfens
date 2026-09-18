# Task 127 — Align breakpoint measurement with SafeArea width

Status: [x] Completed

## Goal

Ensure the Waypoint shell makes one navigation-surface decision from the same
post-`SafeArea` width, so horizontal safe-area insets cannot suppress both the
rail and bottom navigation at the 900 breakpoint.

## Scope and Non-goals

Scope:

- derive the shell’s available width consistently for the existing breakpoint;
- preserve the inclusive 900 breakpoint and existing navigation surfaces;
- add focused widget coverage with horizontal view padding at a 900-wide
  viewport;
- preserve the existing exact-900, 1200-wide, and 432-narrow coverage.

Non-goals:

- changing the breakpoint value, navigation design, or SafeArea policy;
- adding responsive infrastructure, a layout utility package, or viewport
  matrices;
- changing navigation widgets or unrelated production/test files;
- device, simulator, Docker, AWS, or hosted-service work.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Task 126 centralized breakpoint ownership;
- existing `WaypointShell`, `SafeArea`, and viewport test APIs;
- existing Flutter app widget test harness.

## Assumptions

- the current 900.0 breakpoint remains inclusive;
- post-`SafeArea` width can be represented by the current view width minus
  horizontal media padding, or an equivalent minimal source-level calculation;
- `FakeViewPadding` and `resetViewPadding` are available in the current Flutter
  test SDK;
- the worker owns only
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart`
  and `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- affected validation is limited to those changed source/test files.

## Work Items

- [x] Inspect the two shell width measurements and Flutter test view-padding
  APIs.
- [x] Align rail and bottom-navigation decisions to one post-SafeArea width.
- [x] Add focused horizontal-inset coverage at a 900-wide viewport.
- [x] Preserve and review Task 121–126 coverage.
- [x] Review the task-owned change for scope and factual correctness.
- [x] Run only formatting and the changed app test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next instruction.

## Validation

Planned affected-file validation only:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/presentation/waypoint_app.dart`
  `test/waypoint_app_test.dart` from `fixtures/flutter_conformance_app`;
- `flutter test test/waypoint_app_test.dart` from
  `fixtures/flutter_conformance_app`;
- result: formatting reported 0 changes and the coordinator rerun of the
  affected app test file exited 0 with all twenty-two tests passing (`+22`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and repository files are untracked, so Git
cannot provide a historical diff. The coordinator verified the Task 127
source-level scope as follows:

- implementation paths are exactly
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart`
  and `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- the shell computes one available width from the current media size minus
  horizontal media padding, derives one `wide` decision, and uses it for both
  the SafeArea body and bottom-navigation choice at current lines 45–77;
- the app test adds one horizontal-inset case at current lines 849–869, with
  900×900 size, 20-point left/right `FakeViewPadding`, and reset teardown;
- current SHA-256 values are
  `f4a26c6ec7ff728c20b67d77ccd6a714901d24de1310dc493b8a5279650797af` for the
  shell and
  `7712dc914d34c4a65bacbec56bd9b193ff2a01ec33f7cc7dfe661af3909bc551` for the
  app test;
- the worker reported no other files modified, and no unrelated file was
  observed in the task-owned inspection;
- this manifest records the missing Git provenance explicitly and does not
  claim a commit, tracked baseline, or persistence behavior.

## Next Action

Task 127 is complete. Reserve the next local-only task to verify the compact
header Settings affordance under the narrow SafeArea layout.

## Blockers

None known.

## Outcome

The worker updated only the shell and app test within the assigned scope. The
shell now uses one post-SafeArea available-width decision for both navigation
surfaces, and the horizontal-inset test proves a 900-wide viewport still shows
bottom navigation when the available width is 860. Formatting reported 0
changes and the coordinator reran the affected app test with all twenty-two
tests passing. Strict review accepted the post-SafeArea calculation, inset
coverage, scope manifest, and validation with no blocking findings or fixes
required.

## References

- `tasks/126-centralize-wide-breakpoint.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/navigation/waypoint_navigation_rail.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/navigation/waypoint_bottom_navigation.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Reserved Task 127 from the accepted Task 126 review. Scope is
  post-SafeArea width alignment only; no breakpoint or navigation-design change
  is implied.
- 2026-08-29: Newton the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  updated only the two owned files. The worker reported 0 formatting changes
  and `flutter test test/waypoint_app_test.dart` passing all twenty-two tests.
- 2026-08-29: Herschel the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  strictly reviewed the shared available-width decision, inset cleanup,
  preserved viewport coverage, validation, and scope manifest. Result:
  `ACCEPT`; no blocking findings or fixes required. The next instruction is
  narrow header Settings coverage.
