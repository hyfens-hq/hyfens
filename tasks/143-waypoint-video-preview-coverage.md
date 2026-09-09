# Task 143 — Waypoint video preview coverage

Status: [x] Completed

## Goal

Provide deterministic local conformance coverage for video preview
initialization, play/pause control state, and the visible unavailable fallback
without claiming native media playback.

## Scope and Non-goals

Scope:

- add the already-resolved `video_player_platform_interface` 6.9.0 as a
  test-only dependency;
- update the lockfile only as required by that direct dev dependency;
- add a dedicated widget test file with a fake `VideoPlayerPlatform`;
- verify the local asset path reaches the fake platform;
- verify play changes to pause and pause returns to play;
- verify a platform event failure renders the existing unavailable message and
  removes the play control;
- restore the global video platform instance after every test.

Non-goals:

- changing production Waypoint widgets, existing app tests, assets,
  integration tests, routes, or planner behavior;
- upgrading packages beyond the already-resolved interface version;
- claiming codec, audio, Android, iOS, device, or simulator behavior;
- testing Docker, AWS, hosting, networking, or deployment.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- existing `video_player` 2.14.0;
- existing resolved `video_player_platform_interface` 6.9.0;
- existing Flutter test tooling and local video asset;
- current `WaypointVideoPreview` keys and error copy.

## Assumptions

- a fake `VideoPlayerPlatform` can emit initialized and error events without
  requiring a device codec;
- the fake captures the `VideoCreationOptions` asset path and records play and
  pause calls;
- the global `VideoPlayerPlatform.instance` is restored in teardown;
- the worker owns only
  `fixtures/flutter_conformance_app/pubspec.yaml`,
  `fixtures/flutter_conformance_app/pubspec.lock`, and the new
  `fixtures/flutter_conformance_app/test/waypoint_video_preview_test.dart`;
- any plugin API incompatibility is reported rather than expanding scope.

## Work Items

- [x] Inspect the video preview state machine, existing keys/error copy,
  current dependency resolution, asset, and prior coverage.
- [x] Add the pinned test-only interface dependency and dedicated fake-platform
  widget coverage.
- [x] Review the owned dependency/test changes for API correctness,
  determinism, cleanup, and scope.
- [x] Run only dependency resolution plus formatting, analysis, and the new
  video-preview test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and the next source-based instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `flutter pub get`;
- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_video_preview_test.dart`;
- `flutter analyze test/waypoint_video_preview_test.dart`;
- `flutter test test/waypoint_video_preview_test.dart`;
- coordinator `flutter pub get` resolved the pinned dependency and reported no
  dependency-resolution error;
- coordinator scoped formatter exited 0 and reported one file with zero
  changes;
- coordinator scoped analyzer exited 0 with no issues;
- coordinator dedicated video-preview test exited 0 with both tests passing
  (`+2`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

This checkout has no valid `HEAD` and repository files are untracked, so a Git
historical diff cannot establish provenance. The coordinator records that
limitation explicitly. No pre-Task-143 hashes for the dependency metadata or
new test file were recorded.

- Current `pubspec.yaml` SHA-256:
  `355f1d253b5a718296842acc2d2fb65dbc2dfb7d202df9a6664fc9b8627134c7`.
- Current `pubspec.lock` SHA-256:
  `c129b3e901108651df9224d6edbf045617ae411f313d499727b92af95e559cd2`.
- Current video-preview test SHA-256:
  `e41d25cb9769212b9d8f92a1a7625a2efe75a27906a258f7724823a66f5ec2b8`.
- The new test file contains exactly two `testWidgets` cases.
- The worker reported only the two dependency files and the new test file
  changed; coordinator status for those scoped paths shows them and this task
  record as untracked. Any repository-wide historical provenance beyond these
  direct observations is unavailable until a valid baseline exists.

## Next Action

Task 143 is complete. Reserve the next numbered package only after a fresh
source inspection identifies the next bounded local capability.

## Blockers

None known.

## Outcome

The local video preview now has dedicated fake-platform coverage for asset
initialization, play/pause state transitions, and the existing unavailable
fallback. The dependency remains pinned at the already-resolved 6.9.0
interface version and the lockfile marks it direct dev. Strict review returned
`ACCEPT` with no blocking findings, and coordinator final scoped validation
passed analysis and both dedicated tests. No native codec, device, or platform
behavior was changed or claimed.

## References

- `tasks/99-waypoint-demo-app.md`
- `tasks/140-permission-request-result-coverage.md`
- `tasks/142-populated-trips-planning-cta-coverage.md`
- `fixtures/flutter_conformance_app/pubspec.yaml`
- `fixtures/flutter_conformance_app/pubspec.lock`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_video_preview.dart`
- `fixtures/flutter_conformance_app/test/waypoint_demo_data_test.dart`
- `fixtures/flutter_conformance_app/integration_test/waypoint_smoke_test.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
- `fixtures/flutter_conformance_app/assets/videos/waypoint-montage.mp4`

## History

- 2026-08-29: Wegener the 3rd performed a read-only source audit after Task
  142. The audit found that `WaypointVideoPreview` owns untested controller
  initialization, keyed play/pause behavior, and error fallback. Existing
  checks cover only the outer widget, asset bytes, and a Settings smoke
  control. Task 143 is limited to a pinned test-only platform interface,
  lockfile classification, and a dedicated local widget test file; no native
  playback claim is made.
- 2026-08-29: Sagan the 3rd added the pinned direct dev dependency, the
  required lockfile classification, and two fake-platform widget tests. The
  worker reported dependency resolution changed one dependency, scoped format
  passed, scoped analysis reported no issues, and the video-preview test file
  passed both tests. No production or existing test file was edited.
- 2026-08-29: Popper the 3rd independently reviewed the resolved platform API,
  direct-dev dependency classification, event cleanup, platform restoration,
  success play/pause assertions, error fallback, and non-native scope. Result:
  `ACCEPT`; no blocking findings. Final coordinator validation remains pending.
- 2026-08-29: Coordinator final validation passed: dependency resolution
  completed, the scoped formatter exited 0 with zero changes, scoped analysis
  reported no issues, and `flutter test test/waypoint_video_preview_test.dart`
  exited 0 with both tests passing. Task 143 is complete; no device,
  simulator, Docker, AWS, hosting, or deployment validation was needed.
