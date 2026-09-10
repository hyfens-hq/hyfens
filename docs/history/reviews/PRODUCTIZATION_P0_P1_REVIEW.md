# Productization P0/P1 Foundation Review

Status: P0/P1 FOUNDATION — COMPLETED (BOUNDED LOCAL/SELF-HOSTED SLICE)

This review applies the P0/P1 foundation instruction to the approved
productization design. It is not a production-readiness, beta-readiness, or
managed-cloud approval. Architecture B, Patch Format v1, capability v1,
exact release binding, state-v4 trust/high-water, signed rollback, fail-closed
recovery, and runtime signature authority remain frozen.

## 1. Recommendation

PROCEED TO P2 WITH CONDITIONS

Task 41 closes the bounded P0/P1 local/self-hosted slice and stops for
maintainer review. This recommendation proposes a next phase only; it does
not authorize P2 implementation, managed cloud, production readiness, or any
new runtime breadth. The remaining Phase 1D conditions below are entry gates
for any separately approved P2 work.

The explicit maintainer approval record dated 2026-08-23 closes the four
implementation gates. The bounded local/single-node implementation is
complete for this task. The existing unauthenticated development server
remains separate from the validated authenticated product slice.

### P0 gate decision record

Recorded on 2026-08-23 from the explicit maintainer approval record. The
earlier unresolved checkpoint is preserved in the historical note at the end
of this document; it is not rewritten as though approval existed earlier.

| Gate | Decision | Current evidence |
| --- | --- | --- |
| License/governance | APPROVED | Apache-2.0 OSS core, maintainer-led governance, DCO sign-off, and no CLA initially; see `docs/decisions/2026-08-23-task-41-maintainer-approval.md`. |
| OSS/commercial boundary | APPROVED | Runtime/toolchain/protocol/local self-host core remains open; managed cloud, CDN, telemetry, enterprise, and managed signing remain outside Task 41. |
| P1D-13 signing/delivery contract | APPROVED FOR IMPLEMENTATION | Customer/local signing custody; service stores public metadata and exact signed bytes only; delivery credentials are read-only; runtime remains authoritative. |
| Dart `dart:io` modular single-node stack | APPROVED | Dart `dart:io` HTTP, filesystem metadata, and content-addressed filesystem artifact storage; no major framework or managed dependency. |

All four decisions are now explicitly recorded. The local service slice was
completed only within the bounded Task 41 scope.

## 2. Approved license and governance status

Status: APPROVED — APPLIED.

The maintainer selected Apache License 2.0 for the approved OSS core,
maintainer-led governance, DCO sign-off, and no CLA initially. The standard
license is applied in `LICENSE`; contribution guidance is in
`CONTRIBUTING.md`. Future commercial-only components require their own
explicit licensing decision.

## 3. OSS/commercial boundary

Status: APPROVED — BOUNDARY APPLIED.

The approved open core includes the runtime, verifier/interpreter, generated
bootstrap, Patch Format v1 and capability v1 specifications, instrumenter,
compiler, diagnostics, local CLI, local signing/verification, and a minimal
self-host reference path. Managed hosting, managed distribution operations,
hosted observations, collaboration, SSO/SCIM, advanced RBAC, managed KMS/HSM,
enterprise packaging, SLA, and support remain outside this slice.

The boundary preserves the runtime as independently useful and never makes a
hosted service a trust root.

## 4. Implementation stack and repository layout

Status: APPROVED — IMPLEMENTED AND VALIDATED.

The smallest implementation proposal is a Dart modular single-node service
using the standard `dart:io` HTTP boundary and existing repository
conventions, with no new major web framework until maintainers approve one.
The proposed ownership is:

```text
packages/control_plane/
  domain and canonical models
  persistence interfaces and filesystem adapter
  auth/token hashing and scope checks
  release/patch/artifact admission
  promotion/update eligibility
  audit and error envelope

cli/
  deploy/configuration integration

fixtures/
  local control-plane and Flutter end-to-end fixture
```

The first package is implemented under `packages/control_plane/` using
the approved standard-library stack. It deliberately has no service
framework, database, queue, cloud SDK, or deployment package.

## 5. Domain and tenant model

Status: LOCAL IMPLEMENTATION PASSED — BOUNDED.

Organization is the tenant root. The first slice is operationally one
organization, one application, one explicit platform, and one environment,
with tenant-safe ownership tests. API IDs are opaque and separate from exact
runtime application/release/patch identities.

Every customer-owned record has one organization ancestry. Tenant context
comes from authenticated credentials and resource ownership, never from a
caller-supplied organization ID alone.

## 6. Authentication, tokens, and scopes

Status: LOCAL IMPLEMENTATION PASSED — BOUNDED.

The bounded token proposal is:

- one organization-scoped control/service token, shown once and stored only
  as a hash;
- explicit narrow scopes for application, release, patch, artifact,
  promotion, runtime delivery, and audit read operations;
- revocation and expiry where practical;
- a separate read-only application/environment delivery credential;
- no hosted login, SSO, SCIM, or private-key storage in the service.

The existing `tool serve` has no authentication and therefore cannot satisfy
this contract by configuration alone; the new local control-plane package
does satisfy the bounded contract.

## 7. Persistence

Status: LOCAL IMPLEMENTED — VALIDATION PASSED.

The local persistence implementation is a filesystem/single-node adapter with
canonical records, bounded path handling, atomic writes, immutable artifact
blobs, and explicit readiness markers. A metadata database and external object
store are later adapters, not P0 prerequisites. No schema or migration has
been introduced.

Persistence must keep product metadata separate from Patch Format v1 bytes and
must never be able to rewrite runtime trust, high-water, or release identity.

## 8. Release, patch, and artifact immutability

Status: LOCAL IMPLEMENTED — VALIDATION PASSED.

The admission rules are:

- a Release stores exact runtime application/release IDs, target, runtime and
  format versions, build and capability/signature digests, and key metadata;
- a Patch registers against exactly one Release and preserves the supplied
  Patch Format v1 bytes;
- same identity and digest is idempotent;
- same sequence with a different digest is `SEQUENCE_EQUIVOCATION`;
- lower sequence is `STALE_SEQUENCE`;
- wrong release is `EXACT_RELEASE_MISMATCH`;
- a content-addressed artifact is ready only after complete digest-verified
  bytes are durably stored;
- overwrite and mutable replacement are rejected.

The service may perform admission checks, but the runtime repeats the complete
Patch Format v1 verification.

## 9. Signing custody and P1D-13

Status: LOCAL SECURITY EVIDENCE PASSED — PHYSICAL IOS AND ANDROID EVIDENCE
PASSED.

The bounded contract is customer/local signing: private patch signing keys
remain with the developer, organization, offline signer, or explicitly
approved future KMS boundary. The service receives verified public metadata
and exact signed bytes, never private signing keys. Delivery credentials have
no signing authority.

The local package has test evidence for artifact mutation detection, exact
release preservation, invalid-signature quarantine, credential scope
separation, and the service's inability to admit bytes that fail the release
identity/signature checks. The local deploy flow and both declared physical
runtime paths passed authenticated registration, promotion, lookup, exact-byte
fetch, activation, restart persistence, outage retention, rollback, and direct
stale-byte rejection. Broader deployment hardening and production claims
remain open; approval is not being confused with those claims.

## 10. Promotion and update lookup

Status: LOCAL IMPLEMENTATION PASSED — BOUNDED.

Promotion is an audited all-or-none product pointer protected by idempotency
and strong optimistic concurrency. The first slice has no percentages,
cohorts, automatic health rollout, telemetry, or server-side lowering of
high-water.

The bounded delivery decisions are `NO_UPDATE`, `PATCH_AVAILABLE`,
`UPDATE_BLOCKED`, and `STORE_RELEASE_REQUIRED`. `ROLLBACK_CONTROL` may be
implemented only by reusing the existing signed release-bound base-rollback
contract; no unsigned server rollback is permitted.

The runtime remains authoritative for signature, exact release, capabilities,
sequence/high-water, health, rollback, and fallback. The bounded authenticated
service path was exercised on both declared physical fixtures.

## 11. CLI `deploy`

Status: LOCAL END-TO-END PASSED — PHYSICAL IOS AND ANDROID SERVICE PATHS
PASSED.

The proposed command flow is:

```text
resolve local immutable release
resolve locally verified Patch Format v1 bytes
register release if absent
register exact patch metadata
upload the exact verified bytes
promote the selected environment
return request IDs and machine-readable results
```

The bounded command is present in `cli/`. It verifies the exact local Patch
Format v1 bytes against the selected release before making network requests,
registers immutable metadata, uploads the exact bytes, and promotes with an
optimistic version precondition. It accepts credentials through flags or
environment variables and does not persist them. The local service then
returned the promoted artifact through authenticated lookup/fetch with a
byte-for-byte match. Physical Flutter runtime activation through this new API
passed on the declared Android and iOS fixtures.

## 12. Basic append-only audit

Status: LOCAL IMPLEMENTED — VALIDATION PASSED.

The first slice records one event for each semantic mutation and
relevant authentication failure, including event ID, request ID, tenant,
actor/token identity, resource, action, result, timestamp, and redacted
metadata. Idempotent replay must not create duplicate semantic events.

Audit must not contain raw tokens, private keys, patch bytes, credentials,
absolute source paths, or unbounded payloads. This is basic operational audit,
not compliance-grade immutable evidence.

## 13. Tenant isolation

Status: LOCAL TENANT ISOLATION TESTS PASSED — BOUNDED.

Required tests cover synthetic tenants where tenant A cannot read tenant B's
application, release, patch, artifact, delivery metadata, or promotion state;
cannot attach or promote across tenants; and receives the same external
not-found shape for foreign and unknown IDs. Filtering, cursors, counts,
caches, audit, and artifact paths must not leak tenant B.

The local service tests cover foreign-tenant resource boundaries and the
external not-found shape. Filtering, cursors, caches, and production storage
adapters remain outside this bounded slice and are not claimed here.

## 14. Idempotency and concurrency

Status: LOCAL IMPLEMENTED — VALIDATION PASSED.

Release, patch, artifact, promotion, and deploy mutations require an
idempotency key. Same key and canonical body returns the original result;
same key with a different body returns `IDEMPOTENCY_KEY_REUSED`. Promotion and
security-sensitive state use strong ETags/versions; stale preconditions return
`PRECONDITION_FAILED`; last-write-wins is not acceptable.

The local service tests cover retry/key reuse, parallel promotion conflicts,
and stale optimistic-concurrency preconditions. A broader deploy retry matrix
and production persistence adapters remain pending.

## 15. Service outage behavior

Status: HOST/PHYSICAL IOS AND ANDROID EVIDENCE PASSED.

An unavailable control plane, artifact store, or local service must leave the
installed runtime current/LKG/base state untouched. The runtime may continue
using already verified local state and must fail closed for unavailable or
unverified new bytes. No cloud or service connectivity may be mandatory for
runtime correctness.

Host tests and both generated physical bootstraps observed this behavior: a
healthy patch remained active after each local control-plane process was
stopped. Production availability behavior remains unverified.

## 16. Direct stale-byte physical status and P1D-02

Status: **IOS AND ANDROID PHYSICAL PASS FOR THE DECLARED FIXTURES**.

The historical Phase 1D evidence established delivery-boundary withholding,
not direct device rejection of supplied stale valid bytes. Task 42 then used
the safe fixture-only USB seam on the physical iPhone: after sequence 4 was
active and a signed rollback returned to BASE, exact sequence-4 bytes were
received and rejected as `replayAfterRollback`; BASE and high-water 4 were
unchanged. Invalid-signature rejection, signed rollback, and restart
persistence passed in the same run.

The corresponding authenticated Android sequence then ran on the explicit
Wi-Fi device `192.168.50.135:38657`. The direct fixture received exact stale
sequence-4 bytes after rollback and rejected them with BASE/high-water 4
preserved; the generated authenticated bootstrap separately activated a
promoted signed patch and retained it through restart and service outage. The
cross-platform fixture gate is therefore observed, while broader beta,
power-loss, performance, and independent-app gates remain open.

## 17. End-to-end Flutter fixture

Status: LOCAL SERVICE E2E PASSED — PHYSICAL IOS AND ANDROID SERVICE PATHS
PASSED.

The existing ordinary Flutter fixture proves local `tool release`, `tool
patch`, `tool verify`, runtime activation, health, restart persistence, and
rollback within the documented local boundary. The new service package and
`tool deploy` have local artifact E2E evidence, and Task 42's generated iOS
and Android Release bootstraps activated promoted signed patches through
authenticated `/v1` lookup/fetch, then retained them across restart and
service outage. The Android direct cross-feature run also covered UI,
Riverpod, async, invalid-signature, rollback, and stale-byte behavior.

## 18. Security findings

Current findings:

- `cli serve` is development-only, unauthenticated, and not persistent;
- the control-plane implementation is new and remains scoped to local/single-node use;
- no managed or service-side private-key custody exists or is authorized;
- server/product metadata cannot replace runtime Patch Format v1 checks;
- P1D-13 local implementation/security evidence passed; physical iOS and
  Android runtime/outage evidence passed for the bounded fixture, while
  broader deployment evidence remains pending;
- direct supplied-byte physical stale rejection passed on both declared
  fixtures; broader customer-app and power-loss evidence remains pending;
- the package now has unit and HTTP tests for token scopes, foreign-tenant
  boundaries, immutable admission, signature rejection/quarantine,
  idempotency, promotion preconditions, delivery lookup/fetch, and audit
  records; broader customer-application and production evidence remains
  pending.

No finding warrants changing Architecture B or weakening runtime authority.

## 19. Remaining Phase 1D conditions

All 18 Phase 1D conditions remain carried forward with their approved
dispositions. This slice must not silently close them:

- P1D-01 power-loss remains a beta blocker;
- P1D-02 is closed for both declared fixtures; broader beta
  confidence still requires the remaining durability and customer-app gates;
- P1D-03/04 remain iOS diagnostic/performance gates;
- P1D-05 remains a performance-claim gate;
- P1D-06 remains an accepted adjacent-SDK limitation;
- P1D-07/08/09/10/11 remain independent-app, async, attribution,
  multi-function, and evidence-service gates;
- P1D-12 remains accepted historical task-numbering history;
- P1D-13 bounded local/self-hosted physical evidence is satisfied; hosted,
  key-custody, and production evidence remains open;
- P1D-14/16/17 remain explicitly bounded limitations;
- P1D-15 and P1D-18 remain production/security and store-policy gates.

The condition register remains the source of truth.

## 20. Deviations from design

The approved Dart `dart:io` stack and filesystem adapter are implemented as
the first local slice. No major framework, database, cloud
provider, managed KMS, or deployment package was added. Architecture B,
Patch Format v1, capability v1, release identities, runtime state, trust,
high-water, rollback, and AOT fallback remain unchanged.

## 21. Completed implementation sequence

The maintainer approval record authorizes one local/single-node slice in this
order:

1. add the approved control-plane module and canonical domain models;
2. add hashed organization/service and read-only delivery credentials;
3. add tenant-safe filesystem persistence with immutable release/patch/
   artifact admission;
4. add all-or-none promotion and exact update lookup/fetch;
5. add CLI `deploy` using locally verified bytes;
6. add append-only redacted audit;
7. add isolation, auth, immutability, idempotency, delivery, outage, and
   Flutter fixture tests;
8. attempt the direct physical P1D-02 stale-byte test if the device seam is
   available;
9. produce evidence-labeled documentation and stop for maintainer review.

The sequence completed within the approved boundary. Do not proceed to P2
managed cloud, rollout, telemetry, dashboard, enterprise, or React Native
work automatically.

## 22. Current approval record and evidence boundary

The four gates are approved and the bounded implementation and tests have
passed. Evidence labels remain conservative: `UNIT`, `INTEGRATION`,
`END_TO_END_LOCAL`, `PHYSICAL ANDROID`, and `PHYSICAL IOS` are used only where
the corresponding command or device sequence is recorded.

P1D-02 is `CLOSED — DECLARED PHYSICAL FIXTURES`: exact stale sequence-N bytes
were supplied after rollback and rejected while high-water and fallback state
were retained on both declared devices. Delivery withholding alone was not
used to close it.

## Historical checkpoint

The prior checkpoint on 2026-08-23 recorded all four gates as
`MAINTAINER DECISION REQUIRED`, left `LICENSE` as a non-permission
placeholder, and stopped implementation. That state was correct before the
explicit maintainer approval record arrived and is preserved here for audit.

## Evidence boundary

This is a P0/P1 implementation and evidence-gating document. It records the
explicit approval and current repository evidence; it does not claim
production readiness, close Phase 1D limitations, or authorize P2 managed
cloud work.

## Task 42 runtime-delivery follow-up — historical checkpoint (2026-08-23)

The prior sections intentionally preserved the pre-integration `NOT RUN`
checkpoint. Task 42 now adds the following observed evidence without
reclassifying Android or production gates:

- The authenticated lookup/fetch adapter, read-only credential boundary,
  transport checks, host tests, and real CLI → local control-plane → E1
  activation flow passed. E1 remained authoritative for Patch Format v1,
  signatures, exact release/function/capability compatibility, high-water,
  health, and rollback.
- A stock Flutter arm64 iOS Release IPA built with team `CYT7A4VAZ3` installed
  once on the physical iPhone. Its generated bootstrap authenticated to the
  local service over the Mac private LAN, changed the ordinary pricing receipt
  from 540 to 450, retained the patch after restart, and retained it after the
  service process was stopped. The release metadata redacted the delivery
  credential.
- The direct iOS USB cross-feature evidence received the exact old sequence-4
  bytes after rollback and recorded `replayAfterRollback`, BASE mode, and
  high-water 4. Invalid signature rejection, signed rollback, and restart
  persistence also passed in that run.
- The Android authenticated sequence was not run in this checkpoint: ADB and
  mDNS exposed no device and the known Wi-Fi endpoints refused connection.
  This is `ENVIRONMENT-GATED`, not a pass. The new cross-platform runtime
  integration remains in progress and P2/cloud work remains prohibited.

## Task 42 Android completion update (2026-08-23)

The Android transport was restored on the physical Wi-Fi device
`192.168.50.135:38657` (Redmi Note 10 Lite, Android 16/API 36). A fresh
direct cross-feature run passed base, business, async, UI, Riverpod, restart,
invalid-signature, rollback, exact stale-byte, and rollback-persistence
stages. The first retry exposed and corrected a fixture-only receipt-routing
mistake; the fresh `android-task42-wifi-20260823-r2` run is the authoritative
direct result.

The generated authenticated path then passed `tool release android` →
`tool patch` → `tool deploy` against the local service. A stock arm64 Release
APK was installed once for the final sequence, a 2,069-byte signed patch
changed the ordinary fixture receipt from `540` to `450`, and the patch
survived process restart and a stopped control-plane process with unchanged
package install timestamps. The final evidence is recorded in
`docs/research/evidence/task42-android-control-plane.md`.

This closes Task 42's bounded Android/iOS runtime-delivery evidence. It does
not close Phase 1D power-loss, performance, independent-application,
production availability, or store-policy conditions, and it authorizes no P2
or cloud work.

## Final P0/P1 closure (2026-08-23)

Task 41 is `Completed` for the bounded P0/P1 local/self-hosted milestone.
The closure preserves all historical checkpoints above and changes no frozen
runtime or protocol boundary.

| Closure area | Current evidence | Status |
| --- | --- | --- |
| License/governance | Apache-2.0 core, maintainer-led governance, DCO, no CLA initially | PASS |
| OSS/commercial boundary | Runtime/toolchain/protocol/local self-host core open; managed/cloud/enterprise outside scope | PASS |
| Implementation stack | Dart `dart:io` single-node control plane and filesystem artifacts | PASS |
| Tenant isolation and scopes | Local organization/resource ownership, control scopes, read-only delivery credential, foreign-tenant tests | PASS — BOUNDED |
| Release/patch/artifact immutability | Exact release binding, digest-addressed bytes, equivocation and mutation rejection | PASS |
| Signing custody | Customer/local Ed25519 signing; service has public metadata and exact bytes only | PASS — BOUNDED |
| Promotion and deploy | Authenticated lookup/fetch and `tool deploy` local E2E | PASS |
| Audit/redaction | Append-only redacted audit and credential/private-material scans | PASS — BOUNDED |
| Authenticated Android delivery | Stock arm64 Release APK, one install, `540→450`, restart/outage retention | PHYSICAL ANDROID — PASS |
| Authenticated iOS delivery | Stock arm64/arm64e Release IPA, one install, `540→450`, restart/outage retention | PHYSICAL IOS — PASS |
| Direct stale-byte rejection | Exact old sequence-4 bytes rejected after rollback; BASE/high-water 4 retained | P1D-02 — CLOSED |
| Service outage | Healthy patch remained active after service stop and app restart on both fixtures | PASS — BOUNDED |
| Rollback/high-water | Signed rollback and persisted high-water on both direct fixture runs | PASS — BOUNDED |
| Architecture/protocol | Architecture B, Patch Format v1, capability v1, state-v4, AOT fallback unchanged | UNCHANGED |

### Consolidated regression

The final serial regression passed: format (89 Dart files, no changes), root
and affected analysis, fatal-info analysis for all pure-Dart packages, control
plane (7), CLI (39), patch-loading (59 passed plus 2 existing skips), Flutter
integration (17), compiler (1), instrumenter (2), Patch Format (12), runtime
(5), Flutter fixture (18), and root (1). Shell syntax, Python AST syntax,
Markdown links/whitespace, and redaction scans also passed. The physical
Android/iOS results are the recorded Task 42 device runs linked above, not an
inference from host tests.

### Security and evidence boundary

The service cannot make invalid bytes valid; a delivery credential is not a
signing authority; service outage does not clear verified local state; exact
release binding remains authoritative; direct stale bytes are rejected by the
runtime high-water; and signed rollback preserves that high-water. These are
bounded fixture/device observations, not claims of compromised-device
resistance, hosted availability, production key management, or store approval.

### Remaining Phase 1D conditions

P1D-01, P1D-03, P1D-04, P1D-05, P1D-07, P1D-08, P1D-10, P1D-11, P1D-15, and
P1D-18 remain gates before the corresponding beta, production, or policy
claims. P1D-06 remains an accepted adjacent-SDK limitation; P1D-09 remains a
production performance-claim gate; P1D-12 remains accepted historical task
numbering; and P1D-14, P1D-16, and P1D-17 remain bounded limitations. P1D-02
is closed only for the declared physical fixtures, and P1D-13 is satisfied
only for the bounded local/self-hosted physical contract; hosted/production
custody, rotation, recovery, and availability remain open.

### Proposed next milestone (not executed)

`P2 Managed Cloud Foundation` may be proposed after maintainer review, with
true power-loss testing, independent customer-app validation, fresh Android
and iOS performance/diagnostic evidence, async benchmarking, production
audit/evidence maturity, and store-policy review carried forward as explicit
entry conditions. No cloud, dashboard, telemetry, rollout, billing, managed
KMS, SSO/SCIM, enterprise, or React Native work was started.

**Final recommendation: PROCEED TO P2 WITH CONDITIONS.**
