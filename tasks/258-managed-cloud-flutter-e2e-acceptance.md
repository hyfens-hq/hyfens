# Task 258 — Managed Cloud Flutter end-to-end acceptance

Status: [x] Completed — acceptance verdict: RUNTIME_VERIFIED

## Goal

Prove the supported Flutter customer workflow against managed Cloud from a
new Free organization through release, patch, verification, promotion,
deployment, runtime update, observation, and rollback.

## Scope and Non-goals

Scope:

- use a verified customer-owned Cloud organization and customer CLI scope;
- create the first Flutter application/environment and bind a real project;
- exercise release, patch, local verification, upload, promotion, deployment,
  runtime update-check/artifact retrieval, audit/usage visibility, and
  rollback; and
- distinguish code, managed-Cloud, and runtime evidence.

Non-goals:

- changing patch format or runtime architecture;
- adding React Native;
- changing the one-environment Free boundary;
- adding quotas or metering;
- testing paid billing owned by Task 257; and
- cutting over `app.hyfens.com` owned by Task 256B.

## Owner

Codex

## Dependencies

- Task 255 public Cloud onboarding.
- Task 256A public marketing deployment; 256B remains separate.
- Tasks 248–253 control-plane, artifact, lifecycle, and delivery contracts.
- A real Flutter application and an available runtime path.

## Assumptions

- The managed acceptance environment may be a disposable local fixture running
  `DeploymentModel.cloud`, provided it uses the real Cloud HTTP/auth/billing/
  artifact paths and a customer-owned organization rather than the
  self-hosted fixture.
- One Free environment demonstrates promotion into an environment, not
  source-to-target environment promotion; the current API has no latter
  operation.
- Rollback must be a supported Cloud/runtime operation. The local signed
  rollback control is not evidence of managed-Cloud rollback.

## Work Items

- [x] Run customer registration, verification, organization provisioning,
  Free assignment, owner access, and browser workspace inspection.
- [x] Authenticate the CLI with the customer human session, bind the
  organization/application/environment, and run `doctor`.
- [x] Build/install a real Android Flutter baseline and capture visible base
  behavior.
- [x] Create and explicitly verify a supported patch; register, upload,
  promote, and deploy it through the managed Cloud fixture.
- [x] Verify runtime update discovery, artifact retrieval, client-side
  verification timings, health confirmation, and visible patched behavior.
- [x] Inspect customer-visible release/patch/audit state and authoritative
  usage evidence; verify Free application/environment limit errors.
- [x] Complete supported managed-Cloud rollback and visible baseline
  restoration through the Task 260 Cloud desired-state control path.
- [x] Record platform scope, Task 257 dependency, external gates, and the
  resulting launch blocker without overstating evidence.

## Validation

Supporting validation and acceptance run completed:

- Flutter 3.47.2 / Dart 3.13.2 Android arm64 release build;
- `hyfens login`, `profile bind`, `init --force`, `keys generate`, `doctor`,
  `profile current`, `analyze`, `patch`, `verify`, and `deploy`;
- browser dashboard registration, verification, sign-in, workspace overview,
  and customer-scope inspection;
- Android emulator `emulator-5554` runtime screenshots and logcat evidence;
- customer billing, audit, identity, and plan-limit HTTP checks;
- focused control-plane, CLI, Flutter integration, artifact/delivery, usage,
  and Flutter fixture checks; and
- `git diff --check`.

The complete consolidated validation commands and results are appended to the
history after the final validation pass.

## Next Action

Task 260's authenticated managed-Cloud rollback control and Android rerun are
complete. Task 257's paid lifecycle and the separate Task 256B authorization
remain outside this acceptance. Do not cut over `app.hyfens.com` without that
separate authorization.

## Initial blockers (resolved by Task 260)

P0: the current Cloud delivery path can publish and activate a patch, but it
has no supported customer-facing rollback control. `hyfens rollback` records a
local development rollback file; the Flutter integration intentionally uses
the Cloud delivery branch when Cloud configuration is present and does not
poll that local control endpoint. Reinstalling the baseline, rebuilding it,
or modifying Cloud state directly would be an invalid workaround.

Task 257 paid Free → Starter acceptance remains pending independently and did
not block the Free runtime portion.

## Initial acceptance outcome (before Task 260)

### Verdict

`FAILED`. The managed Cloud Android workflow succeeded through runtime patch
activation and visible changed behavior, but the required supported rollback
to visible baseline behavior could not be executed. Per the acceptance rules,
this is not `RUNTIME_VERIFIED`.

### Managed environment and customer

The run used a disposable local managed-Cloud fixture backed by
`ControlPlaneService(deploymentModel: DeploymentModel.cloud)` and
`FileControlPlaneStore`, with an injected verification-message delivery seam.
It was not the self-hosted fixture and was not production. The accepted
Android organization was created through `POST /v1/public/cloud/register`,
verified through `POST /v1/public/cloud/verify`, and resolved to Free with
internal `billing_status: not_required`. No database edit, admin token,
Razorpay checkout, or maintainer-created organization was used.

### End-to-end timeline

1. Public customer registration returned `verification_required`; the
   one-time verification message was consumed through the fixture seam.
2. Verification created the customer-owned organization, owner membership,
   and Free assignment. `/auth/me` exposed customer capabilities only; no
   platform or CMS capabilities were present.
3. The first application and first Free environment were created. Attempts to
   create a second application and second environment returned structured
   `PLAN_LIMIT_REACHED` errors.
4. The CLI logged in with the customer password, bound the non-secret profile
   context, and reported a ready Flutter project from `hyfens doctor`.
5. `flutter_toolchain_app` built and installed a baseline APK. The real
   emulator showed the stock Flutter screen with counter `0`; logcat reported
   `E1_STATUS` healthy/base.
6. `displayCount` was changed from `return value` to `return value + 100`.
   `hyfens analyze` classified the change as `PATCHABLE`; `hyfens patch`
   produced a 1,798-byte signed patch and `hyfens verify` returned
   `VERIFIED`.
7. Customer-scoped `hyfens deploy` registered the release and patch, uploaded
   the artifact, and promoted it into the single environment at version 1.
8. The running emulator logged authenticated candidate activation with
   `patchBytes: 1798`, `downloadMicros: 323501`, and
   `verificationMicros: 41145`, followed by healthy confirmation. The visible
   counter became `101`, proving runtime patch behavior rather than only an
   API/database transition.
9. The customer dashboard showed the release, READY patch, application,
   environment, and redacted audit projection. Billing showed 1 application,
   1 environment, 1 member, 1,798 logical storage bytes, and 1,798 measured
   origin-delivery bytes; delivery authority remained `partial`.
10. No supported managed-Cloud rollback endpoint, CLI operation, or Cloud
    rollback control was available. The run stopped at that required gate.

### Evidence matrix

| Step | Code verified | Cloud verified | Runtime verified | Result |
| --- | --- | --- | --- | --- |
| Customer onboarding | Existing Task 255 tests | Disposable Cloud fixture | N/A | Pass |
| Free assignment | Existing billing tests | `effective_plan=free`, internal/not required | N/A | Pass |
| First application | Existing plan-limit tests | Customer POST 201 | N/A | Pass |
| First environment | Existing plan-limit tests | Customer POST 201 | N/A | Pass |
| CLI authentication/binding | CLI auth tests | Customer human session/profile | N/A | Pass |
| Flutter integration | Package/build path | Cloud defines embedded in APK | Bootstrap healthy/base | Pass |
| Baseline release | CLI release/build | Not yet promoted | Base screen showed `0` | Pass |
| Patch creation | Analyzer/compiler/signature | N/A | N/A | Pass |
| Local verification | `hyfens verify` | N/A | N/A | Pass |
| Upload | Deploy path/tests | Customer-scoped artifact upload | N/A | Pass |
| Promotion | Promotion tests | Environment version advanced to 1 | N/A | Pass |
| Deployment | Deploy path/tests | Customer Cloud deployment/audit records | N/A | Pass |
| Update discovery | Delivery/client tests | Update-check returned candidate | Runtime fetched candidate | Pass |
| Artifact retrieval | Origin delivery tests | Cloud origin served 1,798 bytes | `patchBytes=1798` | Pass |
| Runtime verification | E1 verification tests | Server admitted signed artifact | Nonzero verification timing + healthy state | Pass |
| Patch application | E1 activation tests | Cloud candidate published | Visible counter `0 → 101` | Pass |
| Observability | Projection/API tests | Dashboard/audit/billing visible | Dashboard correctly defers client-health claims | Pass |
| Rollback | Local rollback code only | No Cloud rollback operation | Not run; no valid Cloud path | **Blocked** |
| Usage evidence | Usage tests | Storage/delivery bytes reported | N/A | Pass, delivery partial |
| Free → Starter | Billing path exists | Not tested; Task 257 pending | N/A | Blocked independently |

### Runtime security

The client/runtime path did not blindly apply an arbitrary artifact. The
authenticated delivery branch reported a 1,798-byte candidate, nonzero
download and verification timings, and a subsequent E1 healthy confirmation;
the runtime package code enforces digest, signature, release, platform,
capability, sequence, and resource checks. A managed-Cloud negative-artifact
test was not attempted because there is no safe reason to corrupt this
customer fixture; automated negative verification remains supporting code
evidence, not runtime negative acceptance.

### Rollback

No managed-Cloud rollback was claimed. The supported current `hyfens rollback`
command writes a release-bound local `/v1/control` rollback message. With
Cloud runtime configuration, `HyfensFlutterIntegration` takes the authenticated
Cloud delivery branch and does not poll that local message. Therefore local
rollback would not change the Cloud environment or the running Cloud client.

### Platform matrix

| Platform | Status | Evidence |
| --- | --- | --- |
| Android | Patch runtime verified; overall acceptance blocked at Cloud rollback | Android API 36 arm64 emulator, APK install, logcat, visible `0 → 101` |
| iOS | Code-supported but not Task 258 accepted | CLI supports an iOS release path; no managed-Cloud runtime run in this acceptance |
| macOS | Not accepted; outside current managed release command | Current CLI release command accepts Android/iOS only |
| Windows | Not accepted; outside current managed release command | No Task 258 runtime evidence |
| Linux | Not accepted; outside current managed release command | No Task 258 runtime evidence |
| Web | Not accepted; outside current managed release command | No Task 258 runtime evidence |

### Free → Starter

Not tested. Task 257 owns the paid lifecycle and remains pending; no paid
transition was fabricated or manually forced. The Free organization and its
data remain intact.

### Small fixes performed

No product source fix was made. A disposable fixture harness and temporary
Flutter source change were used for the run and removed/restored afterward.
The maintained fixture and unrelated user changes were preserved.

### Follow-up tasks created

- **P0 / Task 260:** define and implement authenticated managed-Cloud runtime
  rollback control, then rerun the blocked gate.
- **P1 / Task 257:** complete genuine Free → Starter and paid failure/
  cancellation lifecycle acceptance.
- **Task 259:** verify production email and launch operations independently.

### Recommendation

Task 256B customer-workspace cutover is **not technically justified** by this
acceptance yet. Cloud patch deployment and Android runtime activation are
working against the managed fixture, but the required managed rollback proof
is still missing. Keep `app.hyfens.com` on its existing target until Task 260,
Task 257's paid-flow gate, and explicit cutover authorization are complete.

## Task 260 rerun outcome

### Verdict

`RUNTIME_VERIFIED`. The same disposable customer-owned managed-Cloud fixture
was rerun after Task 260. A real Android Flutter runtime showed baseline
counter `0`, received and visibly applied the signed Cloud patch as counter
`101`, then received an authenticated Cloud rollback directive, transitioned
to base, and showed counter `0` again after a normal force-stop/relaunch. The
APK was not reinstalled and no local rollback-control file was used.

### Rollback timeline

1. The customer invoked `hyfens rollback --cloud` with the bound customer
   organization/application/environment context and the fixture endpoint.
2. The authenticated Cloud operation returned `ROLLBACK_REQUESTED` and
   persisted base as the environment's desired runtime state. The existing
   patch deployment, artifact, and release history remained intact.
3. The Cloud-configured runtime polled update-check, validated the signed
   release-bound rollback control, and logged `rolledBack` with mode `base`
   while retaining the patch high-water.
4. The already-rendered process was force-stopped and relaunched, as required
   by the current runtime semantics. It started from the trusted base AOT and
   the visible counter returned to `0` without reinstalling the APK.
5. A subsequent poll did not reactivate the old sequence-1 patch. The Cloud
   audit projection contained `environment.rollback.request` with the prior
   patch desired state and the new base desired state.

### Final evidence matrix

| Step | Code verified | Cloud verified | Runtime verified | Result |
| --- | --- | --- | --- | --- |
| Customer onboarding / Free | Task 255 tests | Customer-owned `DeploymentModel.cloud` fixture; `effective_plan=free`; internal billing | N/A | Pass |
| Application / environment | Plan-limit tests | First application and environment created; second attempts returned `PLAN_LIMIT_REACHED` | N/A | Pass |
| CLI authentication / binding | CLI auth tests | Customer human session, bound organization/application/environment | N/A | Pass |
| Baseline release | CLI/build/signature tests | Customer-scoped release path | Android showed counter `0` | Pass |
| Patch creation / verification | Analyzer, compiler, signature tests | N/A | N/A | Pass |
| Upload / promotion / deployment | Control-plane tests | Customer Cloud environment advanced to version 1 | N/A | Pass |
| Patch retrieval / verification | Flutter delivery and E1 tests | Covered origin delivery recorded 1,798 bytes; authority remained partial | Runtime logged patch verification timings and healthy patch state | Pass |
| Visible patch | E1 activation tests | Patch remained READY and customer-owned | Counter changed `0 → 101` | Pass |
| Cloud rollback request | Authorization/idempotency tests | `ROLLBACK_REQUESTED`; audit event recorded; no local control file | N/A | Pass |
| Rollback directive | Desired-state/update-check tests | Cloud projected `ROLLBACK_TO_BASE` with signed control | Runtime logged `rolledBack`, base mode, retained high-water | Pass |
| Visible rollback | Controller/replay tests | Old patch was not reoffered after rollback | Relaunch showed counter `0` | Pass |
| Usage / observability | Metering/projection tests | 1 app, 1 environment, 1 member, 1,798 storage bytes, 1,798 measured origin-delivery bytes; delivery authority partial | N/A | Pass |

### Runtime security and scope

The rollback directive was validated against application, release, platform,
trusted release key, signature, and the exact active patch high-water before E1
cleared the patch selection. The customer rollback credential used the
customer control scope and was not a Platform Console or CMS credential. The
fixture was not production and no `app.hyfens.com` customer-workspace cutover
or DNS mutation occurred.

### Platform and paid-flow status

Android is the only runtime accepted by this task. iOS, macOS, Windows, Linux,
and Web remain independently unaccepted. Free → Starter was not repeated;
Task 257 owns the genuine paid transition and no provider state was fabricated.

### Task 256B recommendation

The Task 258 technical runtime gate is now satisfied for Android, so the
managed-Cloud rollback blocker no longer prevents Task 256B planning. This is
not production cutover authorization: Task 256B must still perform its own
production checks and receive explicit authorization. No `app.hyfens.com`
customer-workspace cutover was performed.

## Blockers

No Task 258 P0 remains after the Task 260 rerun. Task 257's paid lifecycle and
Task 256B's separately authorized customer-workspace production cutover remain
external launch gates.

## References

- `docs/getting-started.md`
- `docs/cli.md`
- `docs/architecture/rollback.md`
- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/lib/src/service.dart`
- `packages/flutter_integration/lib/flutter_integration.dart`
- `cli/lib/src/cli_runner.dart`
- `fixtures/flutter_toolchain_app/README.md`
- `tasks/247-independent-real-flutter-app-acceptance.md`
- `tasks/255-public-cloud-self-service-onboarding.md`
- `tasks/256-cloud-web-production-cutover.md`
- `tasks/257-customer-billing-upgrade-lifecycle.md`
- `tasks/260-managed-cloud-runtime-rollback.md`

## History

- 2026-09-07: Created from the Task 254 P0/P2 managed-Cloud workflow and
  runtime-evidence gap.
- 2026-09-08: Ran the disposable customer-owned `DeploymentModel.cloud`
  fixture with Android emulator `emulator-5554`. Verified public customer
  onboarding, Free assignment, CLI binding, baseline APK, signed patch,
  customer-scoped deploy/promotion, authenticated runtime retrieval and
  verification, healthy patch activation, visible `0 → 101` behavior, usage,
  audit, and Free plan-limit errors. Found no supported managed-Cloud
  rollback path; acceptance verdict is `FAILED`; created Task 260. No
  production domains were changed.
- 2026-09-08: Final scoped validation passed: `dart analyze .` in
  `packages/control_plane`, `cli`, and `packages/flutter_integration`; focused
  control-plane tests (26), Flutter integration tests (12), and CLI tests (32);
  `flutter analyze fixtures/flutter_toolchain_app`; `flutter test test` from
  the fixture project; and `git diff --check`. The Flutter integration package
  required the existing `flutter pub get` cache repair before its focused test
  run; no source or lockfile change resulted.
- 2026-09-08: Task 260 rerun passed on managed `DeploymentModel.cloud` with
  Android emulator `emulator-5554`: the customer-scoped CLI requested Cloud
  rollback, the runtime observed the signed `ROLLBACK_TO_BASE` directive,
  logged the base transition while retaining high-water, and a relaunch showed
  visible `101 → 0` restoration without APK reinstall or local rollback-file
  intervention. Acceptance verdict advanced to `RUNTIME_VERIFIED`; no
  production domains changed.
