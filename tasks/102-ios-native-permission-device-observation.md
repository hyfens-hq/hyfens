# Task 102 — Physical iOS native-permission device observation

Status: [x] Completed

## Goal

Observe the actual iOS native permission prompt and resulting status for the
Waypoint demo on the connected iPhone using tooling that supports physical
devices. Preserve the evidence boundary established by Task 101: record only
directly observed UI or device output.

## Scope and Non-goals

Scope:

- inventory the installed, approved device-capable iOS inspection and UI
  tooling;
- use the connected iPhone to reach the existing Waypoint permission surface;
- exercise a native permission prompt only when the device tool exposes a
  deterministic, directly inspectable action and record the exact result;
- preserve raw command output or screenshots needed for independent review;
- obtain a strict fact-based review and record the next instruction.

Non-goals:

- AWS, hosted deployment, Android permission resets, or Android reruns;
- changing app source or adding a test without a demonstrated need;
- inferring iOS permission results from Info.plist, package declarations, or
  the Android result;
- broad device reset, unrelated permission changes, or speculative tooling.

## Owner

Coordinator: Codex. Device-tool investigation and bounded observation are
delegated to GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Independent reviewer must inspect the resulting evidence read-only.

## Dependencies

- Task 101 completed with the iPhone Flutter target
  `00008020-001528860E03002E`;
- XcodeBuildMCP physical device record
  `CC5119BA-1DBD-54D2-AD8C-1F15FC5E5B6F`;
- Waypoint app and permission rows from Task 99.

## Assumptions

- The iPhone is connected by cable and remains available to local tools.
- XcodeBuildMCP UI automation may remain simulator-only; that is a validation
  limitation, not evidence of an iOS permission result.
- Any permission action must be explicit, narrow, and recorded with its
  resulting device state.

## Work Items

- [x] Inventory physical-device-capable iOS tooling and confirm the connected
  iPhone identity.
- [x] Determine whether the available tooling supports direct observation; no
  native prompt was exercised because the available UI surface is
  simulator-only.
- [x] Preserve raw evidence and run only newly changed or observation-required
  validation.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record the outcome, limitations, and next instruction.

## Validation

Use only the affected physical-iOS scope:

- approved XcodeBuildMCP help/device discovery and device-capable commands;
- the smallest Flutter/device command needed to reach the existing permission
  row, if direct UI control is available;
- no Android commands or repository-wide tests;
- no iOS permission result without direct native prompt/status observation.

## Next Action

Have the assigned Luna Max worker establish whether the local iOS tooling can
inspect a physical-device native prompt. If it can, capture one bounded
permission flow; otherwise record the exact limitation and request review.

## Blockers

The connected iPhone is available for lifecycle operations, but the approved
UI automation surface is simulator-only and the Xcode IDE bridge discovery
timed out. This is the direct observation limitation recorded by this task.

## Outcome

Physical iOS tooling inventory is complete. The native prompt remains
unobserved because no approved physical-device UI control is available. Dewey
the 2nd independently accepted the evidence with no blocking findings.

## References

- Task 101: `tasks/101-device-permission-observation.md`
- Task 101 receipt:
  `docs/research/evidence/task101-device-permission/validation.md`
- Waypoint smoke:
  `fixtures/flutter_conformance_app/integration_test/waypoint_smoke_test.dart`
- iOS permission declarations:
  `fixtures/flutter_conformance_app/ios/Runner/Info.plist`
- Task 102 tooling receipt:
  `docs/research/evidence/task102-ios-permission/validation.md`

## History

- 2026-08-29: Reserved Task 102 from the Task 101 reviewer instruction. Scope
  is limited to physical iOS native-permission observation; Android remains in
  its current `Permanently denied` state and is not to be reset or rerun.
- 2026-08-29: Kant the 2nd confirmed the physical iPhone is connected and
  available to XcodeBuildMCP lifecycle commands. Help output showed physical
  UI automation is unavailable (`--simulator-id` only), and Xcode IDE bridge
  discovery timed out. No iOS prompt/result was claimed; outputs were recorded
  in the linked receipt.
- 2026-08-29: Dewey the 2nd independently reviewed the task and accepted it
  with no blocking findings. Next instruction: when physical-device UI
  tooling is available, target CoreDevice
  `CC5119BA-1DBD-54D2-AD8C-1F15FC5E5B6F`, exercise one Waypoint permission
  control, and preserve the native prompt and resulting iOS status. Keep
  Android untouched; do not rerun or reset it.
