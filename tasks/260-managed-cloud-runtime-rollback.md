# Task 260 — Managed Cloud runtime rollback control

Status: [x] Completed — acceptance verdict: RUNTIME_VERIFIED

## Goal

Provide a customer-authorized managed-Cloud rollback path that can return an
installed Flutter runtime to its trusted base after a Cloud-delivered patch,
while preserving release binding, high-water, signature, and audit invariants.

## Scope and Non-goals

Scope:

- define the Cloud rollback command or release-control representation;
- connect the authenticated customer control-plane path to the existing E1
  signed base-rollback semantics;
- preserve monotonic high-water and release/application/environment binding;
- record the operation in the existing audit model; and
- prove the path on at least one managed Cloud Flutter runtime.

Non-goals:

- weakening runtime verification;
- selecting or replaying an older patch;
- changing Cloud pricing, plan limits, or billing;
- introducing CDN or bandwidth metering; and
- replacing the local/self-hosted rollback control path.

## Owner

Codex

## Dependencies

- Task 258 managed Cloud Flutter acceptance findings.
- `packages/flutter_integration/lib/flutter_integration.dart`.
- `packages/patch_loading_e1` signed rollback/high-water state.
- `packages/control_plane/lib/src/http.dart` and `service.dart`.

## Assumptions

- The existing signed base rollback remains the runtime safety primitive.
- A Cloud rollback must be delivered as authenticated, release-bound control
  evidence rather than as an unsigned environment flag or local filesystem
  mutation.
- Existing Cloud/self-hosted separation remains unchanged.

## Work Items

- [x] Specify the managed rollback command, authorization, and audit contract.
- [x] Implement the smallest control-plane/CLI/runtime integration consistent
  with the existing signed rollback model.
- [x] Add authorization, replay, ownership, and failure-path tests.
- [x] Run a managed Cloud runtime acceptance proving patched behavior returns
  to baseline without reinstalling the application.

## Validation

Completed:

- focused control-plane and runtime tests;
- authenticated customer-scope, cross-organization, replay, high-water, and
  failure-path tests; and
- managed Cloud Android acceptance with visible patch and rollback behavior.

## Next Action

Task 260 is complete. Task 258 may advance to `RUNTIME_VERIFIED`. Task 257's
paid lifecycle and the separately authorized Task 256B customer-workspace
cutover remain outside this task.

## Blockers

No Task 260 blocker remains. Android is the accepted runtime; other platform
acceptance remains outside this task.

## Outcome

Managed Cloud rollback is now an authenticated desired-state transition. A
customer owner can request a signed base rollback for its application and
environment. The Cloud runtime receives `ROLLBACK_TO_BASE` through normal
update-check, validates application/release/platform/signature/high-water
identity, and applies the existing E1 base transition while retaining the
patch high-water. The managed Android acceptance demonstrated `0 → 101 → 0`
without APK reinstall or a local rollback-control file.

## Final implementation

### Cloud rollback model

`POST /v1/organizations/{organization}/applications/{application}/environments/{environment}/rollback`
accepts a customer-scoped signed base rollback control. The server verifies
organization/application/environment ownership, the active promoted release,
the current active patch, the trusted release key, the control signature, and
the exact patch high-water. The request is idempotent and persists base as the
environment's desired runtime state without rewriting the prior deployment or
patch records.

The immutable audit stream records `environment.rollback.request` with the
actor, target, previous desired state, resulting desired state, and high-water
metadata. It does not store signed control bytes or credentials. The runtime
uses the existing update-check path, receives a typed `ROLLBACK_TO_BASE`
response, validates the release-bound control, and calls the existing E1
rollback transition. The patch high-water remains recorded, so the old
sequence-1 patch is not rediscovered; a later higher-sequence promotion can
replace the base desired state.

### CLI and local state

`hyfens rollback --cloud` signs and submits the control through the bound
customer organization/application/environment context. The customer control
scope is `environment:rollback`; delivery credentials and legacy read-only
public clients cannot request rollback. The existing local/self-hosted
`hyfens rollback --to base` path and its `/v1/control` file behavior remain
unchanged. Managed Cloud rollback does not create or require that local file.

The Cloud request represents desired state, not an immediate runtime
acknowledgement. An offline runtime keeps its current patch until reconnecting.
In the accepted Flutter runtime, the directive caused E1 to enter base and
the process was force-stopped/relaunched so already-rendered widgets repainted
with baseline behavior. No automatic process termination was added.

### History and artifact safety

Rollback is a state transition. The patch artifact, release baseline,
deployment record, promotion state, and audit evidence remain intact. Task
252's READY-artifact protection is unchanged. Repeated rollback requests are
safe, an already-base environment returns an explicit idempotent result, and
malformed, stale, cross-application, wrong-release, wrong-platform, wrong-key,
or replayed controls are rejected without clearing runtime state.

## Validation evidence

Focused automated validation passed:

- `dart test test/cloud_rollback_test.dart test/customer_onboarding_test.dart test/control_plane_test.dart test/http_test.dart` in `packages/control_plane`;
- `dart test test/control_plane_delivery_service_test.dart test/control_plane_delivery_test.dart` in `packages/flutter_integration`;
- `dart test test/controller_test.dart` in `experiments/patch_loading`;
- `dart analyze .` in `packages/control_plane`, `cli`, and
  `packages/flutter_integration`; and
- the managed Cloud Flutter fixture's Android release build and runtime
  acceptance on emulator `emulator-5554`.

The acceptance used a disposable customer created through public registration
and verification against a `DeploymentModel.cloud` fixture. It used a
customer-scoped CLI session, not a platform/admin token, database edits,
manual organization injection, or Razorpay. The observed sequence was:

```text
baseline counter 0
  → signed Cloud patch deployed and visibly applied
patched counter 101
  → customer-scoped `hyfens rollback --cloud`
  → runtime logged signed base rollback with high-water retained
  → force-stop/relaunch without reinstall
baseline counter 0
```

After relaunch and another poll, the old patch was not reapplied. Cloud audit
and billing projections remained available; delivery usage remained labeled
partial and origin-scoped. The local rollback-control file was absent.

## Managed acceptance and remaining gates

Task 258 is updated to `RUNTIME_VERIFIED` for Android only. iOS, macOS,
Windows, Linux, and Web are not claimed as runtime-verified. Task 256B was not
run: no `app.hyfens.com` DNS or customer-workspace production cutover occurred.
The Task 258 technical rollback gate is now satisfied for Android, but Task
256B still requires its own production checks and explicit authorization. Task
257 still owns paid upgrade/cancellation acceptance.

### Task 256B recommendation

The managed Android runtime gate is technically justified for Task 256B to
proceed to its separate production review. It is not authorization to cut over
the customer workspace. Keep `app.hyfens.com` on its existing target until
Task 256B approves and performs that change.

## References

- `tasks/258-managed-cloud-flutter-e2e-acceptance.md`
- `docs/architecture/rollback.md`
- `packages/flutter_integration/lib/flutter_integration.dart`
- `packages/control_plane/lib/src/http.dart`
- `cli/lib/src/cli_runner.dart`

## History

- 2026-09-08: Created from the Task 258 managed-Cloud acceptance blocker.
- 2026-09-08: Implemented authenticated customer Cloud rollback with signed
  release-bound desired state, update-check projection, E1 runtime handling,
  CLI `--cloud` routing, audit coverage, high-water replay protection, and
  cross-organization/idempotency tests.
- 2026-09-08: Managed Android acceptance passed on emulator `emulator-5554`:
  baseline `0`, signed Cloud patch `101`, customer-requested Cloud rollback,
  runtime base transition, and post-relaunch baseline `0`. No APK reinstall,
  local rollback file, database edit, admin token, production DNS change, or
  `app.hyfens.com` cutover was used.
