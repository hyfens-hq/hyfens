# Task 104 — Physical iOS permission prompt retry

Status: [x] Completed

## Goal

Trigger one Waypoint native permission request on the connected physical iPhone
so the user can see the prompt directly and the coordinator can record only the
result that is actually observed.

## Scope and Non-goals

Scope:

- use the connected iPhone `00008020-001528860E03002E`;
- add a temporary, narrowly scoped integration probe only to navigate to
  Waypoint Settings and request one permission;
- run only that probe on the iPhone and give the user a short observation
  window;
- record whether a native prompt appeared and the directly reported result;
- remove the disposable probe unless it proves suitable as a stable test;
- obtain strict fact-based review of the resulting evidence.

Non-goals:

- Android interaction or permission changes;
- simulator validation, AWS, hosted deployment, or unrelated source changes;
- automatically selecting an iOS permission action without the user's direct
  observation;
- claiming a native prompt/result from Flutter test completion alone.

## Owner

Coordinator: Codex. Probe design and result review are delegated to GPT-5.6
Luna Max, max reasoning, priority/fast execution. The coordinator runs the
physical-device command because the user needs to watch the phone live.

## Dependencies

- connected iPhone `00008020-001528860E03002E`;
- current Waypoint app and permission rows;
- Task 102/103 evidence boundaries.

## Assumptions

- The physical iPhone is trusted and available to Flutter.
- The current installed app has not already permanently denied the selected
  permission; if it has, the probe must report that state and stop.
- The user can observe and, if desired, select the native prompt action during
  the bounded window.

## Work Items

- [x] Confirm the physical iPhone is connected and available.
- [x] Add and run one disposable permission prompt probe on the iPhone.
- [x] Record the user's/device's directly observed prompt and result, or the
  exact absence/blocked state.
- [x] Remove the disposable probe unless it is intentionally retained.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record the outcome and next instruction.

## Validation

Use only the affected physical-iOS scope:

- the dedicated integration probe on
  `00008020-001528860E03002E`;
- `dart format integration_test/waypoint_physical_permission_probe_test.dart`;
- `flutter test integration_test/waypoint_physical_permission_probe_test.dart -d
  00008020-001528860E03002E`;
- no Android command or permission reset;
- no simulator or repository-wide test;
- no iOS result claim without direct user/device observation.

## Next Action

Task 104 is complete. Reserve the next local-only task for deterministic
permission-row/status widget coverage. Do not infer or record a post-Allow
physical-device state from this task.

## Blockers

None known. If the iPhone does not show a prompt, record whether the app was
already denied/permanently denied or whether the probe failed before the
request.

## Outcome

The probe built, installed, launched, reached Settings, and sent the Camera
request. The user directly reported that the native prompt appeared and that
Allow was selected. The probe's subsequent verification run reported the
pre-request row as `Camera|Denied|Test` and passed; it did not expose the
physical UI or independently verify the post-Allow state. That limitation is
preserved in the evidence receipt rather than inferred away. The disposable
probe was removed after the observation.

## References

- Task 102: `tasks/102-ios-native-permission-device-observation.md`
- Task 103: `tasks/103-ios-simulator-permission-observation.md`
- Waypoint smoke:
  `fixtures/flutter_conformance_app/integration_test/waypoint_smoke_test.dart`
- Permission rows:
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_permission_row.dart`

## History

- 2026-08-29: Reserved Task 104 after the user requested a live physical-iPhone
  prompt retry. Android and simulator work remain out of scope.
- 2026-08-29: The first probe run built, installed, launched, and sent a
  Notifications request. The second run printed the pre-request state and sent
  a Camera request, then passed after the 20-second observation window without
  selecting an OS action. The user then directly confirmed that the prompt was
  visible and Allow was selected.
- 2026-08-29: A bounded verification run printed
  `cameraRow=Camera|Denied|Test` before sending the Camera request and passed.
  This is retained as raw tool output; it is not treated as a post-Allow
  permission result. The disposable probe was removed and the receipt was
  added at `docs/research/evidence/task104-physical-ios-permission-retry/validation.md`.
- 2026-08-29: Fermat the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  reviewed the task and receipt and returned `ACCEPT` with no blocking
  findings. The review confirmed that no post-Allow physical-device state was
  claimed and recommended deterministic permission-row/status widget coverage
  as the next local-only task.
