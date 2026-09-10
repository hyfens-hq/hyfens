# Phase 1D conditions and disposition

Status: BOUNDED P0/P1 LOCAL IMPLEMENTATION — NO PRODUCTION IMPLEMENTATION

<!-- The disposition register intentionally uses wide evidence-table rows. -->
<!-- markdownlint-disable MD013 -->

Phase 1D concluded with **PROCEED TO PRODUCTIZATION DESIGN WITH CONDITIONS**.
That conclusion permits a maintainer-reviewed design discussion; it does not
authorize a hosted service, self-hosted deployment, dashboard, rollout system,
telemetry ingestion, enterprise product, store submission, or any other
product implementation.

The authorization boundary above is the historical Phase 1D checkpoint. Task
41 later authorized and completed the bounded local/self-hosted slice; it did
not authorize production infrastructure or any managed/cloud capability.

This document carries forward every remaining limitation called out by the
Phase 1D review, including limitations that affect only a future claim rather
than the current bounded local workflow. The dispositions are proposed gates
for roadmap planning, not evidence that a gate has passed.

## Disposition vocabulary

- **BLOCKER BEFORE IMPLEMENTATION** — the proposed implementation cannot start
  until the missing contract or prerequisite is resolved.
- **BLOCKER BEFORE BETA** — design or bounded implementation may proceed, but a
  beta claim or broader supported track cannot be made until the evidence is
  closed.
- **BLOCKER BEFORE PRODUCTION** — a limited local/beta path may exist, but a
  production or enterprise claim must wait for the evidence/control.
- **ACCEPTED LIMITATION** — retain the limitation explicitly, narrow the
  supported claim, and do not treat it as evidence for a broader capability.

“Accepted limitation” does not mean “fixed,” “safe in all environments,” or
“store/compliance ready.”

## Phase 1D disposition register

| ID | Limitation and current evidence boundary | Disposition | Rationale and required gate | Owner / milestone |
| --- | --- | --- | --- | --- |
| P1D-01 | True physical power-loss interruption was not simulated. Process/restart and deterministic durable-boundary tests passed, but no OS-level power-cut guarantee exists. | BLOCKER BEFORE BETA | Durable state, pending-candidate recovery, and high-water behavior are central safety claims. Run a bounded physical interruption campaign across supported platforms and record both successful recovery and fail-closed corruption behavior before a beta durability claim. | Runtime + mobile validation; P1 reliability gate before beta |
| P1D-02 | Direct runtime rejection of supplied stale valid bytes was not physically exercised; fresh Android/iOS evidence showed delivery-boundary withholding and unchanged state, not direct supplied-byte rejection. | BLOCKER BEFORE BETA | Host and protocol tests are useful but do not replace a device-level anti-replay observation. Supply stale/equal-equivocal/wrong-release candidates through the delivery seam, verify runtime rejection, and prove high-water preservation. | Runtime security + distribution validation; P1 security gate before beta |
| P1D-03 | iOS runtime logs/UI evidence was unavailable because the Developer Disk Image was unavailable; iOS evidence used app-support state-v4 snapshots and process/liveness observations. | BLOCKER BEFORE BETA (iOS track) | Do not describe iOS semantic UI behavior or equivalent runtime diagnostics from state snapshots alone. Re-run on an environment with the required diagnostic channel and preserve the boundary of what is observed. | Mobile validation/toolchain; P1 iOS evidence gate |
| P1D-04 | iOS performance timings, startup/memory/thermal/battery series, and fresh iOS performance evidence were not run. | BLOCKER BEFORE BETA (iOS performance claims) | A Flutter-first beta cannot publish iOS performance or resource claims from Android/host evidence. Run a controlled iOS baseline/instrumented/active-patch series and state device/network/profile limits. | Performance + mobile validation; P1 beta evidence gate |
| P1D-05 | No fresh Phase 1D Android 15-sample dispatch/startup/memory reducer series was closed; the Phase 1C Android baseline remains authoritative. | BLOCKER BEFORE BETA (performance claims) | The existing baseline supports a bounded historical statement, not a current product capacity or regression target. Run the planned reducer series with enough samples to separate dispatch, startup, memory, and workload effects. | Performance; P1 beta evidence gate |
| P1D-06 | Full CLI/release/device validation on adjacent Flutter 3.47.1/Dart 3.13.1 was not isolated. Direct version, analysis, fatal-info, and benchmark checks passed; the child process used 3.47.0 and an explicit PATH attempt stopped at an SDK-hash build hook. | ACCEPTED LIMITATION | Keep 3.47.0/3.13.0 as the only fully bounded support claim. Do not label 3.47.1 supported until a clean SDK-selection and device path is isolated; this does not block a deliberately narrow first slice. | Toolchain; P0 support policy, optional P1 adjacent-SDK gate |
| P1D-07 | Validation used the representative conformance fixture, not an independent customer application. | BLOCKER BEFORE BETA | Fixture coverage demonstrates integration seams but not customer build graphs, generated code, flavors, packages, assets, or unsupported-change diagnostics in the wild. Validate at least one independent real application under a declared support matrix before beta. | Integrations + toolchain; P1 beta gate |
| P1D-08 | The additional async benchmark was not run to completion because the harness crossed an invalid fixture package-root/URI boundary. Existing bounded async capability tests remain passing. | BLOCKER BEFORE BETA (async support claims) | Repair the harness, rerun the benchmark, and distinguish bounded capability-mediated async from broad Future/Stream or hot-frame suitability. Until then, keep async claims limited to the existing measured subset. | Runtime benchmarking; P0 repair, P1 async gate |
| P1D-09 | Host interpreter profiles have only three samples and lack attribution for decode, frame/value allocation, budget accounting, capability checks, and source-map cost. | BLOCKER BEFORE PRODUCTION (performance claims) | Do not optimize or publish native-equivalent performance from noisy aggregate ratios. Add stage attribution and representative workloads before setting performance budgets, scale assumptions, or production support promises. | Interpreter/performance; P1 measurement, P2 production gate |
| P1D-10 | The 1/5/20/50-function bridge-size measurements validate encoding/scaling only; physical multi-function activation, source-compiler scaling, and controller multi-function performance were not established. | BLOCKER BEFORE BETA (multi-function claims) | A single-function or host bridge result cannot support a broad patch-size or multi-function product claim. Exercise multi-function generation, physical activation, controller behavior, and source-map/reporting boundaries. | Compiler + runtime + performance; P1 beta gate |
| P1D-11 | Raw coordinator captures are session evidence, not an immutable release/CI evidence service. | BLOCKER BEFORE PRODUCTION | Production auditability and incident review need durable provenance, integrity, retention, export, and access controls. Until that exists, label captures as bounded evidence and never market them as an evidence service or compliance control. | Release engineering + security; P2/P4 production-audit gate |
| P1D-12 | Historical duplicate `tasks/39` numbering exists and is intentionally preserved. | ACCEPTED LIMITATION | Renumbering history would destroy traceability and is unrelated to runtime/product safety. Keep the duplicate history visible; new task numbering remains monotonic. | Repository maintainers; ongoing documentation policy |
| P1D-13 | The local tool has no trusted production server, transport authentication, external key rotation/revocation service, or managed key custody. | BLOCKER BEFORE IMPLEMENTATION (hosted/production path) | The local development transport cannot be promoted by configuration alone. A product implementation needs an explicit authenticated delivery contract, key-custody choice, rotation/revocation/recovery ceremony, and threat-model review while keeping runtime checks authoritative. | Security + platform; P0 contract, P1 self-hosted gate, P2 hosted gate |
| P1D-14 | The runtime remains untested against rooted or fully compromised devices and local filesystem attackers can still tamper with or delete app-support state. | ACCEPTED LIMITATION | The design can fail closed with checksums, dual copies, release binding, and recovery barriers, but cannot promise secrecy or integrity after full device compromise. Keep this out of security, enterprise, and compliance claims; add threat-model testing where the offering requires it. | Security + mobile; P0 threat model, P5 enterprise review |
| P1D-15 | Physical power-loss, transport authentication, protected key custody, production delivery, and post-compromise trust recovery are not solved by the Phase 1D local milestone. | BLOCKER BEFORE PRODUCTION | These are cross-cutting production gates, not reasons to rewrite Architecture B. Each must have an owner, evidence plan, and explicit failure mode before production operations are claimed. | Security/platform/runtime; P2/P5 production gate |
| P1D-16 | Local observability is limited to bounded CLI/toolchain status; there is no application runtime bridge or remote introspection/telemetry authority. | ACCEPTED LIMITATION | This is the correct local boundary for the current milestone. A later optional outbound event path may support operations, but it must be privacy-preserving, incomplete, opt-out/disableable, and unable to override runtime safety. | Observability + privacy; P0 design, P3 implementation gate |
| P1D-17 | No long power-loss, thermal, battery, indefinite-soak, broad Future/Stream, or hot-frame suitability campaign was completed. | ACCEPTED LIMITATION | Keep the support matrix bounded to the measured semantic/runtime subset. Promote any one of these to a beta or production gate only when the roadmap explicitly markets that behavior. | Runtime/performance; P1/P2 scope-specific gates |
| P1D-18 | Store-policy classification for downloaded interpreted behavior remains unresolved; Android and Apple public policy text does not establish project-specific approval. | BLOCKER BEFORE PRODUCTION (platform-policy claims) | Maintain a dedicated Apple/Google legal/policy review per artifact category. No product document may say App Store compliant, Play approved, or equivalent based on the runtime evidence. | Legal/policy + product; before store submission or production claim |

### Task 42 evidence update (2026-08-23)

The historical P1D-02 row above records the pre-Task-42 boundary and is kept
for traceability. The direct stale-byte test is now physically closed for the
declared iOS fixture: after sequence 4 was active and a signed rollback
returned to BASE, the exact old sequence-4 bytes were received over the USB
fixture seam, rejected as `replayAfterRollback`, and left BASE and high-water 4
unchanged. The same iOS run also passed invalid-signature rejection, rollback,
and restart persistence.

The new authenticated product-delivery path was additionally exercised on the
physical iPhone. A stock arm64 Release IPA installed once, fetched a promoted
signed patch through the read-only delivery adapter, changed the ordinary
pricing receipt 540→450, survived restart, and remained usable when the local
service was stopped. The corresponding Android Wi-Fi run then passed on the
physical Redmi Note 10 Lite (Android 16/API 36): the generated arm64 Release
APK installed once for the final sequence, authenticated lookup/fetch changed
the receipt 540→450, restart and service-outage retention passed, and package
install timestamps remained unchanged. Its direct cross-feature run also
passed invalid-signature rejection, rollback, exact stale-byte rejection, and
rollback persistence. This closes the declared direct stale-byte/device gate
for the bounded fixture on both platforms; it does not close the remaining
beta/production, performance, independent-app, power-loss, or policy gates.

### Current Task 41 disposition (2026-08-23)

The table row above preserves the pre-Task-42 evidence boundary. The current
condition state for the completed bounded P0/P1 slice is:

| ID | Current disposition | Evidence boundary |
| --- | --- | --- |
| P1D-02 | **CLOSED — DECLARED PHYSICAL FIXTURES** | Physical Android and iOS fixtures received exact stale valid bytes after rollback; the runtime rejected them as replay and retained BASE/high-water 4. Broader beta durability and independent-application confidence remains open. |
| P1D-13 | **BOUNDED LOCAL/SELF-HOSTED PHYSICAL EVIDENCE SATISFIED** | Customer/local signing custody, public metadata-only service storage, read-only delivery, authenticated lookup/fetch, runtime verification, activation, restart, outage retention, rollback, and stale rejection passed on the declared fixtures. Hosted/production custody, rotation/revocation, and availability remain open. |

No other Phase 1D condition is closed by Task 41. The register remains
explicitly non-production and makes no Apple/Google policy claim.

## Gate mapping by roadmap stage

The roadmap should not silently make every condition a P0 blocker. The
following mapping keeps implementation scope narrow while preserving honest
claims:

| Stage | Conditions that must be resolved or explicitly narrowed |
| --- | --- |
| P0 design review | All rows have an owner, evidence plan, supported-claim boundary, and maintainer disposition; no design weakens the frozen runtime/protocol invariants |
| P1 minimal self-hosted slice | P1D-02 declared physical-fixture gate is closed; P1D-13 bounded local evidence is satisfied; artifact immutability, authenticated lookup, customer signing custody, and service-outage behavior passed; P1D-01/P1D-03–P1D-10 remain visible as beta gates |
| P2 managed cloud | P1D-01–P1D-02, P1D-07–P1D-11, P1D-13, measured SLO/DR evidence, tenant isolation, transport/authentication, and key recovery; no platform-policy claim without P1D-18 |
| P3 rollout/observability | P1D-16 plus conservative treatment of missing/spoofed telemetry; observation must never replace signature, release, capability, high-water, or health authority |
| P4 teams/audit | P1D-11, credential/audit provenance, retention/export/redaction, and independent application evidence for the supported workflow |
| P5 enterprise/on-prem/air-gap | P1D-01, P1D-02, P1D-03, P1D-04, P1D-06, P1D-11, P1D-13–P1D-15, P1D-18, plus customer-specific HA/DR and key/import review |
| P6 framework expansion | Flutter evidence must be stable; a new framework needs its own independent runtime, policy, performance, and real-application evidence |

## What remains true now

The conditions do not erase the evidence that did pass:

- Architecture B, Patch Format v1, capability v1, exact release binding,
  state-v4 trust/high-water, signed rollback, and fail-closed recovery remain
  frozen.
- Android and iOS physical process/restart, activation, rollback, and bounded
  state persistence evidence exists for the stated fixture and devices.
- The malformed corpus, activation soak, host directional profile, local CLI
  status, and scoped regression evidence remain valid within their documented
  boundaries.
- No limitation authorizes weakening a signature check, accepting a stale
  artifact, lowering high-water, adding arbitrary host capabilities, or making
  cloud connectivity mandatory.

The complete evidence is in [`../PHASE_1D_REVIEW.md`](../reviews/PHASE_1D_REVIEW.md).
The operational consequences are in
[`../architecture/scale-ha-dr.md`](../../architecture/scale-ha-dr.md), and the
roadmap gates are in
[`../architecture/product-roadmap.md`](../../architecture/product-roadmap.md).

## Non-goals and stop point

This register does not implement tests, deployment, a backend, migrations,
dashboard, accounts, billing, KMS, telemetry, rollout automation, enterprise
SSO, React Native, production infrastructure, store submission, or compliance
work. It is the condition source for the bounded local milestone and remains
subject to maintainer review before any separately authorized next phase.

## P2 managed-cloud foundation addendum (2026-08-23)

The separately authorized P2 foundation was implemented without changing the
Phase 1D runtime/security boundary. PostgreSQL metadata, S3-compatible
immutable objects, narrow hosted authentication, idempotent promotion,
redacted audit, Compose deployment, readiness, backup/restore, and bounded
operator metrics now have `UNIT`, `INTEGRATION`, `BACKUP_RESTORE`, and
`END_TO_END_HOSTED_LIKE` evidence. This does not change the disposition of
any Phase 1D beta or production gate.

P1D-07 (independent real application), P1D-01 (true power loss), P1D-03/04
(iOS diagnostic/performance), P1D-05/08/09/10 (performance, async, and
multi-function claims), P1D-15 (production security/recovery), and P1D-18
(policy review) remain open. P1D-11 now has a bounded P2 provenance pass
(durable chain, export, retention limit, and tamper detection), but its
compliance-grade/production disposition remains open. The
initial P2 hosted-like Android attempt was environment-gated when the declared
Wi-Fi phone was pingable but its ADB wireless-debugging port was closed. A
follow-up physical Redmi run then passed the hosted-like base-to-patch,
restart, outage-retention, invalid-signature, rollback, and stale/replay
scenarios; the separate evidence is recorded in
`docs/research/evidence/p2-hosted-like-2026-08-23.md`. This closes the declared
P2 Android device evidence gap for the conformance fixture only and does not
close any independent-app, performance, power-loss, production, or policy
gate.

### P2 closure-hardening addendum (2026-08-23)

Task 44 executed a coupled PostgreSQL/object backup and restore, digest
reconciliation, credential issuance/expiry/revocation, audit export and
hash-chain tamper detection, private TLS proxy traffic, certificate rotation,
dependency outage/recovery, and an interrupted artifact mutation retried by
the same idempotency key. These are bounded single-node/operator-fixture
results. They do not prove HA/DR, public-ingress security, RPO/RTO, managed
key recovery, compliance-grade auditability, or store-policy approval.

The repository-owned `fixtures/flutter_toolchain_app` passed its Flutter tests
as a secondary fixture. It is not an independent customer application, so
P1D-07 remains a blocker before a beta recommendation. Existing physical
Android and iOS fixture evidence remains valid; the closure-hardening source
changes did not modify the mobile runtime or release artifacts, so no new
physical-device claim is added by this addendum.

### P2 final-evidence gate addendum (2026-08-23)

Task 45 repaired the async benchmark's invalid fixture package-root setup and
completed the bounded supported async run. It also revalidated the retained
15-sample physical Android performance reducer. The following current
dispositions apply only to the exact declared evidence boundaries; historical
rows above remain unchanged for traceability.

| ID | Current disposition | Exact boundary |
| --- | --- | --- |
| P1D-05 | **CLOSED — DECLARED PHYSICAL ANDROID REDUCER** | Redmi Note 10 Lite / Android 16 / arm64-v8a / Flutter 3.47.0 / Dart 3.13.0, 15 process-isolated samples per variant, startup/PSS/RSS/APK measurements. No universal SLO or iOS inference. |
| P1D-08 | **CLOSED — BOUNDED ASYNC SUBSET** | Capability-mediated `Future<int>` with immediate and delayed completion, two awaits, continuation/error/budget tests, and native-AOT integration. `Stream`, `async*`, closures, cancellation, and hot-frame claims remain unsupported. |
| P1D-01 | **OPEN — ENVIRONMENT-GATED** | No true OS-level power-loss interruption was safely/reproducibly executed. |
| P1D-03 | **OPEN — ENVIRONMENT-GATED** | iOS Developer Disk Image/runtime diagnostic stream was unavailable for fresh diagnostic-code/log claims. |
| P1D-04 | **OPEN — NOT RUN** | No controlled iOS stock/instrumented/active-patch performance campaign was run. |
| P1D-07 | **OPEN — BETA BLOCKER** | No independent maintained Flutter application was supplied; repository fixtures and generated copies do not qualify. |
| P1D-09 | **OPEN — PRODUCTION BLOCKER** | Internal interpreter-stage attribution remains unavailable; public-layer timings are not stage attribution. |
| P1D-10 | **OPEN — BETA BLOCKER FOR MULTI-FUNCTION CLAIMS** | Host bridge scaling exists, but physical multi-function activation and rollback were not run. |
| P1D-15 | **OPEN — PRODUCTION** | Option A is selected: signing-key replacement requires a new store release; production ceremony and availability controls remain open. |
| P1D-18 | **OPEN — POLICY REVIEW** | Apple/Google review package is prepared; no approval or compliance claim exists. |

The detailed evidence and production checklists are in
[`../research/p2-final-evidence-gates-2026-08-23.md`](../../research/p2-final-evidence-gates-2026-08-23.md)
and [`../store-policy/p2-review-package.md`](../../store-policy/p2-review-package.md).

### P2 external-gate continuation addendum (2026-08-23)

Task 46 audited the workspace for a genuinely independent maintained Flutter
application. None was supplied or present. The conformance fixture,
toolchain fixture, and generated benchmark copy remain repository-owned and
cannot satisfy P1D-07. The prescribed stop condition was followed; no
independent-app, multi-function, attribution, iOS profiling, power-loss, or
production evidence claim was added.

P1D-07 remains **OPEN — BETA BLOCKER**. All other external-gate dispositions
remain unchanged from the Task 45 addendum. Maintainer review and an actual
independent application are required before this gate can be exercised.

### Task 47 residual evidence addendum (2026-08-23)

Task 47 independently exercised the physical multi-function and production
hardening gates without changing the frozen runtime or trust boundaries.

| ID | Current disposition | Evidence boundary |
| --- | --- | --- |
| P1D-01 | **OPEN — ENVIRONMENT-GATED** | No safe true OS-level power-loss campaign was executed. |
| P1D-03 | **OPEN — ENVIRONMENT-GATED** | iPhone state receipts passed, but the Developer Disk Image/runtime diagnostic stream remains unavailable. |
| P1D-04 | **OPEN — NOT RUN** | No controlled iOS stock/instrumented/active-patch performance series was collected. |
| P1D-07 | **OPEN — BETA BLOCKER** | No independent maintained Flutter application was supplied; repository fixtures remain excluded. |
| P1D-09 | **OPEN — INSUFFICIENT ATTRIBUTION / PRODUCTION BLOCKER** | Directional host workload/profile timings ran, but no private interpreter-stage hooks exist and no optimization was made. |
| P1D-10 | **CLOSED — DECLARED ANDROID + IOS SCOPE** | Both devices verified the selected business/async/widget slots through restart, tamper rejection, rollback, and persistence. The claim is limited to the named fixture/artifact and does not generalize to arbitrary patch counts. |
| P1D-11 | **OPEN — SECURITY REVIEW** | Local audit chain/export/tamper evidence remains bounded; off-box signed export and compliance controls remain open. |
| P1D-15 | **OPEN — SECURITY REVIEW** | Disposable signing/tabletop and local ingress checks passed; production ceremony, public edge, durability, HA/DR, and provenance remain open. |
| P1D-18 | **OPEN — EXTERNAL REVIEW REQUIRED** | No Apple/Google approval or legal conclusion is inferred. |

Physical Android evidence used one install invocation on the Redmi Note 10
Lite. Physical iOS evidence used the AUVANA VENTURES PRIVATE LIMITED team and
one arm64 Release install. A leading-slash iOS USB staging attempt failed
closed before the target was corrected to `Documents/...`; the successful
suffix did not reinstall the app and is documented separately in
[`../research/p2-multi-function-physical-2026-08-23.md`](../../research/p2-multi-function-physical-2026-08-23.md).

Task 47 stops with four separate statuses: P2 technical implementation is
bounded-complete for the declared single-node scope, beta is blocked,
production is blocked, and store-policy/legal status is external review
required. The Task 47 recommendation is **CONTINUE P2 FOR EXTERNAL EVIDENCE**;
P3 remains prohibited.

### Task 48 repository-controlled production-readiness addendum (2026-08-23)

Task 48 narrowed only the conditions that the repository and disposable local
environment could execute. It did not close the external gates.

| ID | Updated disposition | Evidence boundary |
| --- | --- | --- |
| P1D-09 | **OPEN — INSUFFICIENT ATTRIBUTION / PRODUCTION BLOCKER** | The opt-in profiler now measures private interpreter stages for six supported host workloads, but attribution still excludes AOT guard cost, Flutter-frame cost, heap allocation, healthy source-map lookup, and device/release behavior. No optimization was justified. |
| P1D-11 | **BOUNDED LOCAL — `AUDIT_EXPORT_SIGNED_OFFBOX`; production review open** | A separate deterministic Ed25519 audit-export envelope verifies offline and rejects record/identity/signature tampering. It is not WORM, legal hold, compliance retention, or an external evidence service. |
| P1D-15 | **BOUNDED REPOSITORY CONTROLS; production/provider review open** | Local ingress trust, disposable two-instance application HA, directional DR, SBOM/inventory, secret lifecycle, signing incidents, and runbooks have executed or explicit bounded evidence. Public edge, provider HA/durability, numeric RPO/RTO, production key custody, and image attestation remain open. |
| P1D-01 | **OPEN — ENVIRONMENT-GATED** | No safe true physical power-loss campaign. |
| P1D-03 | **OPEN — ENVIRONMENT-GATED** | Developer Disk Image diagnostics unavailable. |
| P1D-04 | **OPEN — NOT RUN** | No controlled iOS performance series. |
| P1D-07 | **OPEN — BETA BLOCKER** | No independent maintained Flutter application supplied. |
| P1D-18 | **OPEN — EXTERNAL REVIEW REQUIRED** | No Apple/Google or legal approval inferred. |

### Task 51 physical iOS diagnostics and performance rerun (2026-08-23)

Task 51 reran the two iOS gates that had been environment-gated when the
Developer Disk Image was unavailable. Historical rows and prior dispositions
remain unchanged for traceability; the following is the current bounded
addendum for the newly available unlocked USB iPhone.

| ID | Current disposition | Evidence boundary |
| --- | --- | --- |
| P1D-03 | **CLOSED — DECLARED DEVICE/TOOLCHAIN SCOPE** | On the iPhone XR running iOS 18.7.9, a personalized Developer Disk Image was mounted (`/System/Developer`), `idevicesyslog` captured Runner and Flutter process observations, and `xcodebuildmcp device launch` succeeded. This removes the prior environment blocker for this device/run only; it is not universal iOS or production telemetry evidence. |
| P1D-04 | **PARTIAL — STARTUP/CPU PROFILE CLOSED; RESOURCE/THROUGHPUT OPEN** | Physical Release stock, instrumented-unpatched, and active-patch variants have retained Time Profiler and App Launch traces plus binary-size measurements. Allocations did not yield usable numeric RSS/heap data; thermal, battery, soak, and dispatch-throughput campaigns were not run. |

The exact device/build identity, commands, raw evidence, lifecycle receipts,
and reductions are in
[`docs/research/ios-gate-rerun-2026-08-23.md`](../../research/ios-gate-rerun-2026-08-23.md).
P1D-01, P1D-07, P1D-09, P1D-15, P1D-18, provider readiness, beta readiness, and
store/legal review remain open. No App Store, Google Play, or legal-compliance
claim follows from this rerun.

### Task 98 physical iOS dispatch-throughput evidence (2026-08-28)

Task 98 adds a separate device-specific dispatch-throughput observation; it
does not rewrite the historical Task 51 disposition. The retained
`flutter-devices.json` and `ios-deploy-detect-usb.txt` identify the named
iPhone XR running iOS 18.7.9; `build.json` and `architectures.txt` record the
Release/device arm64 build. It ran over USB with one exact-bundle
uninstall/install boundary, evidenced by `uninstall.txt` and `install.txt`. The app wrote a readiness marker, received the
Patch Format v1 artifact through the Documents container, measured the three
declared callable paths, and returned a reducer-accepted report with two
untimed warmups and 15 timed samples per variant.

| ID | Current disposition | Evidence boundary |
| --- | --- | --- |
| P1D-04 | **PARTIAL — DEVICE-SCOPED DISPATCH THROUGHPUT; RESOURCE/BROAD PERFORMANCE OPEN** | Run `task98-ios-dispatch-usb-20260828T173915Z` measured stock/direct, instrumented-unpatched, and active-patch loop timings with fixed results/checksums. This closes only the declared fixture/device dispatch-throughput observation; RSS/heap, thermal, battery, soak, power-loss, Flutter-frame, independent-app, production, and hosted/provider claims remain open. |

The raw and reduced evidence, exact identity, hashes, and command receipts are
retained under
`fixtures/flutter_conformance_app/.dart_tool/e1_ios_dispatch_runs/task98-ios-dispatch-usb-20260828T173915Z/evidence/`.
The performance research record contains the measured medians and nearest-rank
p95 values. No iOS-wide, App Store, AWS, hosted-deployment, or legal claim
follows from this bounded run.

The detailed evidence labels and commands are recorded in the Task 48
focused research notes and `tasks/48-p2-repository-controlled-production-readiness.md`.
The overall beta, external/provider production, and store-policy decisions
remain blocked or review-required.
