# Task 126 — Centralize the wide-layout breakpoint

Status: [x] Completed

## Goal

Give the Waypoint shell one source of truth for the existing 900 logical-pixel
wide-layout breakpoint while preserving rail and bottom-navigation behavior.

## Scope and Non-goals

Scope:

- define one local breakpoint constant in the existing shell implementation;
- use it for both rail selection and bottom-navigation suppression;
- add focused boundary coverage at exactly 900 logical pixels;
- preserve the existing 1200-wide and narrow viewport coverage.

Non-goals:

- changing the breakpoint value, layout design, navigation behavior, or
  breakpoint strategy;
- adding responsive infrastructure, a new utility package, visual snapshots,
  or arbitrary viewport matrices;
- changing navigation widgets or unrelated production/test files;
- device, simulator, Docker, AWS, or hosted-service work.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Task 125 wide-layout rail coverage;
- existing `WaypointShell` breakpoint expressions and viewport test pattern;
- existing Flutter app test harness.

## Assumptions

- the current intended breakpoint is 900 logical pixels, inclusive;
- a file-local constant in `waypoint_app.dart` is sufficient and avoids an
  unnecessary responsive abstraction;
- exact-boundary coverage can be added to
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- the worker owns only
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart`
  and `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- affected validation is limited to those changed source/test files.

## Work Items

- [x] Inspect both existing breakpoint decisions and current viewport tests.
- [x] Define one shared breakpoint constant without changing its value.
- [x] Replace both shell threshold literals with the shared constant.
- [x] Add focused exact-boundary widget coverage with viewport cleanup.
- [x] Preserve and review Task 121–125 coverage.
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
- result: formatting reported 0 changes; the worker initially reported `+22`,
  but the coordinator reran the changed app test file and verified exit 0 with
  exactly twenty-one tests (`+21`), matching the 21 `testWidgets` declarations;
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and repository files are untracked, so Git
cannot provide a historical diff. The coordinator verified the Task 126
source-level scope as follows:

- implementation paths are exactly
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart`
  and `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- `waypoint_app.dart` contains one file-local `_wideLayoutBreakpoint` constant
  at current line 19, and both existing threshold decisions use it at current
  lines 50 and 81;
- the app test adds one exact-900 viewport test at current lines 832–847 and
  retains the existing 432 and 1200 viewport tests;
- current SHA-256 values are
  `e1af6424e90bf12501bd40b73828506c56a9a3f95fb53266b2c875599c74a61d` for the
  shell and
  `61cd8ddcf580d45185cb5b3d0b350eeb00c581e4572dbfcbc20a366b20d77ab5` for the
  app test;
- the worker reported no other files modified, and no unrelated file was
  observed in the task-owned inspection;
- this manifest records the missing Git provenance explicitly and does not
  claim a commit, tracked baseline, or persistence behavior.

## Next Action

Task 126 is complete. Reserve the next local-only task to align rail and
bottom-navigation decisions to the same post-SafeArea width.

## Blockers

None known.

## Outcome

The worker updated only the shell and app test within the assigned scope. One
file-local 900.0 breakpoint constant now drives both shell decisions, and the
exact-boundary test proves the rail is selected. Formatting reported 0 changes;
the coordinator reran the affected app test and verified all twenty-one tests
passed. Strict review accepted the behavior, corrected validation count, scope
manifest, and exact-boundary coverage with no blocking findings or fixes
required.

## References

- `tasks/125-wide-navigation-rail-coverage.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Reserved Task 126 from the accepted Task 125 review. Scope is
  centralizing the existing 900 breakpoint and proving its inclusive boundary;
  no responsive behavior change is implied.
- 2026-08-29: Aristotle the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  updated only the two owned files. The worker reported 0 formatting changes
  and `flutter test test/waypoint_app_test.dart` as `+22`.
- 2026-08-29: The coordinator reran `flutter test test/waypoint_app_test.dart`
  after finding 21 `testWidgets` declarations and verified exit 0 at `+21`.
  The task record uses the coordinator-verified count; strict review is
  pending.
- 2026-08-29: Rawls the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  strictly reviewed the shared constant, both uses, exact-900 test, preserved
  viewport coverage, corrected validation count, and scope manifest. Result:
  `ACCEPT`; no blocking findings or fixes required. The next instruction is
  post-SafeArea width alignment.
