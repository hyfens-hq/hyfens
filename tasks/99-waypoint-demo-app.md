# Task 99 — Waypoint production-style demo app

Status: [x] Completed

## Goal

Replace the visible conformance fixture surface with a small, production-style
travel discovery and planning app named Waypoint. The app is a realistic host
for Hyfens experiments: it must exercise ordinary Flutter assets, Riverpod
state, AlphaX requests, dynamic UI, responsive layouts, and selected platform
permission flows without becoming a full travel product.

## Scope and Non-goals

Scope:

- make Waypoint the app's visible launch surface while preserving the existing
  conformance functions, evidence sessions, and compatibility test seams;
- organize new code into small, separately filed UI, domain, data, service,
  and platform-permission classes;
- use Riverpod for application and feature state with repository injection;
- use `alphax` plus `alphax_native` for request/response boundaries, with a
  deterministic local AlphaX transport backed by bundled JSON and an optional
  local-network mode backed by a Docker fixture server;
- add local destination imagery, a bundled custom font, a short local video,
  and mock JSON assets, all registered through `pubspec.yaml`;
- implement responsive Discover, Trips, Saved, Activity, and Settings areas;
- add a dismissible time-limited offer banner, an actionable bottom sheet with
  a small planning form, skeleton loading, dynamic theme selection, search,
  save/unsave, and app-settings controls for test actions;
- add explicit settings actions for location, notifications, camera, and photo
  library permission requests and show the observed status without hiding
  platform denial/restriction outcomes;
- add focused widget/unit coverage and one device smoke flow with stable keys;
- validate the visible app on the connected iPhone and Android device where
  the local toolchain permits, recording actual outcomes and limitations.

Non-goals:

- AWS, hosted deployment, cloud accounts, or production travel APIs;
- payment, authentication, account creation, analytics, push delivery, or
  real booking execution;
- replacing or broad-refactoring the existing Hyfens conformance/evidence
  implementation;
- claiming that a local fixture proves production network, permission, store,
  or performance behavior;
- adding a CLI, owner dashboard, or end-user backend;
- automating every OS permission dialog when the device state or platform
  policy prevents deterministic automation.

## Owner

Coordinator: Codex. Delegated implementation owners are GPT-5.6 Luna Max,
priority/fast execution, with disjoint file ownership. Independent reviewers
must review the combined task-owned result read-only and report only facts
verified from source, tests, device output, and receipts.

## Dependencies

- Flutter 3.47.0 / Dart 3.13.0 available locally;
- `alphax: 1.0.0-rc.3` and `alphax_native: 1.0.0-rc.3` available from the
  verified Auvana Ventures package publication;
- `flutter_riverpod` already present in the fixture;
- `video_player`, `flutter_svg`, and `permission_handler` only if the bounded
  implementation requires them and their resolved versions are recorded;
- local Docker, if network-mode validation is included;
- connected iPhone and Android device for device smoke checks;
- no valid Git baseline is assumed; task-owned paths and direct evidence are
  the review boundary.

## Assumptions

- The demo category is travel discovery/planning because it naturally combines
  destination imagery, short-form video, itinerary cards, saved content,
  location/notification permissions, and actionable date/guest forms.
- Mobbin is design reference only. Waypoint must not copy proprietary assets,
  text, or branding from the referenced apps.
- Local demo mode is the deterministic default. Network mode is an explicit
  local fixture option and must fail visibly rather than silently substituting
  data after a configured request fails.
- Existing physical evidence build defines and current conformance test imports
  remain compatible after the visible launch surface changes.

## Work Items

- [x] Inspect the existing fixture, AlphaX package API, connected-device tools,
  and Mobbin travel flows; choose the Waypoint category and interaction model.
- [x] Implement the Waypoint domain/data/service foundation and AlphaX-backed
  demo/network data sources with local JSON models.
- [x] Implement the responsive Waypoint shell, screens, reusable components,
  dynamic theme state, skeletons, banner, bottom-sheet form, and settings
  action surface.
- [x] Add bundled image/font/video/mock-data assets and platform permission
  declarations with truthful status handling.
- [x] Add focused widget/unit tests and a stable-key device smoke flow.
- [x] Integrate the disjoint slices without regressing existing conformance
  APIs or physical evidence startup.
- [x] Complete strict fact-based code/spec review and fix blocking findings.
- [x] Run changed-scope validation plus connected iOS/Android smoke checks and
  record actual results.
- [x] Update this task with outcome, receipts, skipped checks, and the next
  bounded instruction from the final reviewer.

## Validation

Planned validation is limited to changed app scope:

- `flutter pub get` in `fixtures/flutter_conformance_app` after dependency
  changes;
- `dart format --output=none --set-exit-if-changed` for changed Dart files;
- `flutter analyze` for changed fixture Dart files only;
- focused `flutter test` files added or changed by this task only;
- local asset manifest/build verification for the registered SVG, font, video,
  and JSON assets;
- local Docker API smoke only if the network fixture is changed;
- iOS device build/run and UI smoke through the XcodeBuildMCP workflow after
  help-first command discovery;
- Android device build/run and UI smoke through the existing Flutter/ADB
  device workflow;
- permission actions observed on both devices where the OS exposes a prompt or
  status; denied/unavailable outcomes are recorded rather than treated as
  success.

Do not run tests for unchanged files, the full repository suite, AWS workflows,
or unrelated deployment targets.

## Next Action

Preserve the recorded Android-device and OS-permission limitations. The next
coordinator task may begin only from a newly reserved task number.

## Blockers

None known at reservation. A missing package API, unavailable device, signing
failure, or nondeterministic OS permission state must be recorded as an actual
validation limitation and must not be converted into a success claim.

## Outcome

Implementation and local validation are complete. The current iPhone
integration smoke passes after the Riverpod disposal fix. Android target build
passes, but no Android device is currently visible to ADB, so Android runtime
and permission outcomes remain unobserved. Final independent strict review
accepted the task with no blocking findings.

## References

- Mobbin discovery screen references:
  `https://mobbin.com/screens/8c683be5-cf1f-4efc-a94f-6c38ca885903`
  (GetYourGuide),
  `https://mobbin.com/screens/f54e7aef-7cd2-4e7b-84c6-ee1899e49ada`
  (Wanderlog), and
  `https://mobbin.com/screens/fe2d61dd-9505-424b-ac6a-f4d1efeb0c7f`
  (Polarsteps).
- Mobbin permission/settings references:
  `https://mobbin.com/flows/247308cf-b335-49b7-9644-bb99eabc7217`
  (Viator location permission),
  `https://mobbin.com/flows/a5eeb480-1524-4a31-b819-5cc74f7fbef2`
  (Polarsteps location services), and
  `https://mobbin.com/flows/bd6cf0f5-bf57-40d4-9c52-9cd1ef01c837`
  (Agoda notification onboarding).
- Mobbin action-form references:
  `https://mobbin.com/flows/7bd218ac-16e5-4d2c-89a2-9239ebe4f2a9`
  (Vrbo date selection) and
  `https://mobbin.com/flows/48a61650-6d90-4897-b723-a0c25ea6b2cc`
  (Flighty detail form).
- AlphaX package: `https://pub.dev/packages/alphax` and
  `https://pub.dev/packages/alphax_native`.
- Existing local AlphaX reference app:
  `/Volumes/970EvoPlus/Development/projects/auvana-ventures/packages/alpha-x/examples/waypoint`
- `fixtures/flutter_conformance_app/pubspec.yaml`
- `fixtures/flutter_conformance_app/lib/main.dart`
- `docs/research/evidence/task99-waypoint-demo/validation.md`

## History

- 2026-08-29: Reserved Task 99 after inspection found all prior non-AWS Hyfens
  tasks complete and the conformance fixture still lacking realistic asset,
  dynamic-surface, permission, and AlphaX consumer coverage. Mobbin searches
  returned travel discovery, permission, notification, settings, and form
  patterns. The existing Auvana Ventures Waypoint AlphaX example was verified
  as a suitable architectural reference; no external app assets or branding
  are copied.
- 2026-08-29: GPT-5.6 Luna Max implementation slices added the Waypoint
  application, local JSON/SVG/font/MP4 assets, AlphaX demo/network seam,
  Docker fixture, platform declarations, focused tests, and iPhone smoke flow.
- 2026-08-29: Coordinator review found and fixed the local Docker search
  contract expectation, unknown-trip fallback, Inter text-theme application,
  null-valued demo fields, permanent-denial labeling, activity completion
  notification, Android API 37 compatibility, and disposed-ref permission
  refresh/request writes.
- 2026-08-29: Strict review findings were recorded and addressed. Final
  changed-scope tests (11), analysis, formatting, asset bundle, Android APK,
  local Docker route smoke, and current iPhone integration smoke passed. The
  durable receipt is linked above.
- 2026-08-29: Final independent GPT-5.6 Luna Max strict review returned
  ACCEPTED with no blocking findings. Task closed while preserving the
  unobserved Android runtime and OS-permission limitations.
- 2026-08-29: Removed the exact disposable Task 99 Docker images after the
  local route smoke; no Task 99 containers or networks remain.
