# Task 103 — iOS simulator permission observation

Status: [x] Completed

## Goal

Use an available iOS simulator to exercise and directly observe the Waypoint
demo's native permission surface, covering the iOS behavior that cannot be
inspected on the connected physical iPhone with the currently available
tooling.

## Scope and Non-goals

Scope:

- use the approved XcodeBuildMCP simulator workflow on one available iPhone
  simulator;
- launch the current Waypoint app and reach its Settings permission rows;
- exercise only permission prompts that the simulator exposes and record the
  exact native prompt, action, and resulting status;
- preserve raw UI-automation output and the simulator identity for review;
- obtain a strict fact-based review and record the next instruction.

Non-goals:

- changing app source or adding tests unless the simulator reveals a verified
  app defect requiring a narrowly scoped fix;
- physical iPhone interaction, Android interaction, Android permission reset,
  AWS, hosted deployment, or external APIs;
- claiming physical-device behavior from simulator results;
- rerunning unchanged repository tests or broad platform builds.

## Owner

Coordinator: Codex. Simulator execution is delegated to GPT-5.6 Luna Max,
max reasoning, priority/fast execution. An independent Luna Max reviewer must
inspect the evidence read-only.

## Dependencies

- Task 102 completed with physical iOS UI automation unavailable;
- available simulator `01E37F43-D39E-4039-82B7-FDD9EABC6754` (iPhone 16 Pro,
  iOS 18.2), confirmed by `xcodebuildmcp simulator list`;
- current Waypoint app in `fixtures/flutter_conformance_app`.

## Assumptions

- The simulator is disposable for this bounded permission observation and has
  no production data.
- Native permission state may be simulator-specific and must be labeled as
  such.
- The XcodeBuildMCP simulator UI commands are the approved interaction path.

## Work Items

- [x] Confirm the selected simulator and discover the required simulator/UI
  commands through XcodeBuildMCP help.
- [x] Build, launch, and navigate the Waypoint app on the selected simulator.
- [x] Exercise and capture the Notifications native permission prompt and
  record the explicit denial plus resulting simulator status.
- [x] Preserve evidence and run only observation-required validation.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record the outcome, limitations, and next instruction.

## Validation

Use only the affected simulator scope:

- `xcodebuildmcp simulator list --enabled true --output json`;
- explicit `xcodebuildmcp simulator build-and-run` for the selected simulator;
- `xcodebuildmcp simulator snapshot-ui` and `xcodebuildmcp ui-automation`
  commands for direct UI observation;
- `xcodebuildmcp simulator screenshot` only if needed to preserve a visible
  native prompt;
- no Android commands, physical-device commands, repository-wide tests, or
  unchanged-file tests.

## Next Action

Task 103 is complete. The simulator evidence is limited to iOS 18.2
simulator behavior. Physical-iPhone native permission observation remains a
separate task for when physical-device UI tooling becomes available.

## Blockers

The first simulator build attempt encountered a stale generated Flutter
test-listener path. The explicit `FLUTTER_TARGET` workaround succeeded without
source changes. The native prompt itself was available and directly observed.

## Outcome

The iPhone 16 Pro / iOS 18.2 simulator built and launched Waypoint. The
Notifications native prompt was directly observed, `Don’t Allow` was selected,
and the resulting simulator row showed `Permanently denied`. The stale-listener
workaround and durable raw UI/tap output are recorded. Popper the 2nd
independently accepted the evidence with no blocking findings.

## References

- Task 102: `tasks/102-ios-native-permission-device-observation.md`
- Task 102 receipt:
  `docs/research/evidence/task102-ios-permission/validation.md`
- Waypoint app:
  `fixtures/flutter_conformance_app`
- Permission rows:
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_permission_row.dart`
- Simulator receipt:
  `docs/research/evidence/task103-ios-simulator-permission/validation.md`
- Raw simulator output:
  `docs/research/evidence/task103-ios-simulator-permission/raw-command-output.md`

## History

- 2026-08-29: Reserved Task 103 from the Task 102 reviewer instruction and
  selected the available iPhone 16 Pro / iOS 18.2 simulator. Physical iPhone
  and Android remain out of scope for this simulator-only task.
- 2026-08-29: Confucius the 2nd built and launched the app on the selected
  simulator. The first build hit a missing generated Flutter test-listener
  path; an explicit `FLUTTER_TARGET` retry succeeded. The coordinator then
  recaptured a Notifications permission flow with raw pre-prompt, prompt,
  denial-tap, and post-prompt outputs. `Don’t Allow` was selected and the
  simulator reported `Permanently denied`. No app source or test files were
  edited.
- 2026-08-29: The first strict review rejected the receipt because the
  simulator-list mapping and pre-tap button frame were not preserved. The
  coordinator added the exact simulator-list output, frame-backed pre-action
  snapshot excerpt, successful tap output, prompt output, denial output, and
  post-action snapshot to the raw receipt. Review is pending again.
- 2026-08-29: Popper the 2nd independently re-reviewed the corrected evidence
  and accepted it with no blocking findings. The task is closed. Next
  instruction: retain simulator-only scope; resume physical-iPhone native
  permission observation only when device-capable UI tooling is available.
