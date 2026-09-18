# Runtime storage

Status: Phase 1B implementation boundary retained and reviewed in Phase 1C.

The generated Flutter bootstrap gives the existing E1 controller one
app-owned, release-scoped directory:

```text
host application-support directory/
└── hyfens/<appId>/<releaseId>/
```

The host directory comes from Flutter's standard application-support location
lookup. On Android this resolves to the app-private `filesDir`; on iOS it is
`NSApplicationSupportDirectory` inside the application sandbox. The runtime
does not use the shared system temporary directory, Android external/shared
storage, iOS Documents, or a cache directory for lifecycle state.

The relative `hyfens/<appId>/<releaseId>` layout is kept from the earlier
bootstrap. App and release identifiers are accepted only as single path
components, so generated metadata cannot escape the host-provided root. The
resolver only selects the directory; it does not create a second persistence
store or interpret runtime state.

After resolution, E1 remains the sole owner of lifecycle persistence. Its two
state copies, verified artifact files, integrated trust/replay ledger,
high-water checks, recovery behavior, and atomic temporary-file/rename
semantics remain in the same directory. The state-v4 journal keeps the
historical `state-v3-a.json` and `state-v3-b.json` paths for compatibility. A
new controller instance for the same app and release therefore sees the same
durable directory and can perform the restart recovery path without a second
trust store.

The Flutter lookup is isolated behind an internal conditional import. The
bootstrap initializes Flutter's binding and registers the pinned platform
path-provider implementations before resolving the support directory. The
Android implementation is pinned to `path_provider_android 2.2.23` because the
newer JNI-backed implementation crashed before JNI initialization in the
release bootstrap; the pinned implementation passed the physical Android
workflow. The iOS Foundation implementation passed the physical iPhone
workflow.

Host tests inject a temporary support root to exercise path construction,
identifier safety, and reuse across a simulated controller restart without
requiring a Flutter engine or a device. The non-Flutter branch fails closed;
it never falls back to system-temp storage.

## Evidence

The generated bootstrap was validated with durable app-support storage on a
physical arm64 Android device (Android 16/API 36) and a physical iPhone XR
(iOS 18.7.9). Both workflows installed the release once, activated a signed
patch, confirmed health, terminated and restarted the process, and observed
the patch remain current. Both then accepted the signed developer base
rollback, restarted again, and observed `BASE` persist. No device workflow
used shared Android storage or iOS Documents.

This boundary does not add a second persistence store, new artifact formats,
capabilities, or crash/power-loss fault injection. Patch Format v1 and the
capability contract remain unchanged.

## Phase 1C hardening note

The storage location remains the same app-owned support directory. Phase 1C
hardens the controller's use of it with two checksummed release-bound copies,
generation/high-water validation, atomic temporary-file/rename boundaries, a
one-attempt pending-candidate boot lease, and a fail-closed recovery barrier.
Those controls are documented in
[`runtime-state-machine.md`](runtime-state-machine.md). The test hooks model
I/O boundaries deterministically; they do not claim that a particular mobile
filesystem provides a power-loss guarantee stronger than its platform API.
