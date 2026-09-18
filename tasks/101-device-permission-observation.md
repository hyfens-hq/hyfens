# Task 101 — Waypoint device permission observation

Status: [x] Completed

## Goal

Observe and record the actual permission-control behavior exposed by the
Waypoint demo on the connected Android and iOS devices, without converting
unobserved or nondeterministic OS-dialog behavior into a success claim.

## Scope and Non-goals

Scope:

- verify the current app reaches Settings on both connected devices;
- exercise the existing permission-control surface where the device tooling
  permits it and record the actual status/prompt/result;
- use read-only device inspection where possible and preserve device state
  unless an explicit permission action is required for observation;
- add only narrowly necessary changed-scope test/receipt coverage;
- obtain a strict fact-based review and record the next instruction.

Non-goals:

- AWS, hosted deployment, or unrelated app/source changes;
- resetting the device, revoking unrelated permissions, or broad automation;
- claiming permission success from manifest declarations or unit-test fakes;
- rerunning unchanged repository tests.

## Owner

Coordinator: Codex. Device observation is delegated to GPT-5.6 Luna Max,
max reasoning, priority/fast execution. Independent reviewer must inspect the
result read-only and report only directly observed facts.

## Dependencies

- Waypoint Task 99 completed;
- Android device `192.168.50.135:42691`, Redmi Note 10 Lite, Android 16/API 36;
- iPhone device `00008020-001528860E03002E`, iOS 18.7.9;
- current changed integration smoke in
  `fixtures/flutter_conformance_app/integration_test/waypoint_smoke_test.dart`.

## Assumptions

- The existing smoke intentionally avoids tapping OS permission dialogs because
  Flutter integration automation cannot deterministically control every native
  prompt.
- A device/tooling limitation is a valid outcome and must be recorded as such.

## Work Items

- [x] Confirm both device identities are visible to the local tools.
- [x] Exercise and observe the current permission surface on Android and iOS
  where the available tooling permits.
- [x] Run only any newly changed permission-observation test or the existing
  changed integration smoke needed for the observation.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record receipts, observed outcomes, and tooling limitations.

## Validation

Use only the affected device/integration scope:

- `adb devices -l` and `flutter devices`;
- `flutter test integration_test/waypoint_smoke_test.dart` on each available
  device where applicable;
- read-only Android UI/package inspection or approved XcodeBuildMCP device
  inspection where available;
- no permission result is recorded without direct observation.

## Next Action

Task 101 is complete. The next task is physical iOS native-permission
observation using device-capable tooling; retain the current Android state and
do not rerun or reset Android permissions unless explicitly required.

## Blockers

None known. Native permission dialog automation may be unavailable on one or
both devices; if so, record the exact limitation rather than forcing a result.

## Outcome

Android permission prompts and denial results were directly observed. The first
denial pass left the four rows `Denied`; a second pass used to preserve raw
review evidence left them `Permanently denied` with `USER_FIXED` flags. The iOS
Settings surface is verified by the existing smoke, but its native prompt and
result remain unobserved because the available UI automation is simulator-only.
The independent strict review accepted the evidence with no blocking findings.

## References

- Task 99: `tasks/99-waypoint-demo-app.md`
- Task 100: `tasks/100-android-device-overflow-fix.md`
- Existing integration smoke:
  `fixtures/flutter_conformance_app/integration_test/waypoint_smoke_test.dart`
- Permission declarations:
  `fixtures/flutter_conformance_app/android/app/src/main/AndroidManifest.xml`
  and `fixtures/flutter_conformance_app/ios/Runner/Info.plist`
- Observation receipt:
  `docs/research/evidence/task101-device-permission/validation.md`
- Raw Android command output:
  `docs/research/evidence/task101-device-permission/android-command-output.md`

## History

- 2026-08-29: Reserved Task 101 after Android became visible. Both device
  identities are now reported by local tools; direct OS permission outcomes
  remain unobserved from Task 99 and require a bounded follow-up.
- 2026-08-29: Ran Android Wi-Fi and iPhone integration smoke flows. Directly
  exercised Android Location, Camera, Notifications, and Photo library
  prompts and selected `Don't allow` for each. Recorded final Android denied
  state and the simulator-only limitation for iOS native prompt inspection.
- 2026-08-29: Strict review rejected the first receipt because the raw device
  output was not durable in the review context. Recaptured narrow Android UI,
  native prompt, final status, and package-state output in the linked raw
  receipt. The repeated explicit denials changed the current rows to
  `Permanently denied` and set `USER_FIXED`; this is recorded as the current
  device state.
- 2026-08-29: Leibniz the 2nd independently re-reviewed the task and accepted
  it with no blocking findings. Non-blocking notes were limited to omitted
  command strings for some preserved excerpts and the unavoidable lack of a
  committed Git baseline. Next instruction: reserve a physical-iOS,
  device-capable permission-observation task; retain Android as-is.
