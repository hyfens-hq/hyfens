# Hyfens product positioning

Status: DESIGN ONLY — NO PRODUCTION IMPLEMENTATION

This document is the positioning package for Task 40. It defines the product
boundary and the claims that a later product review may consider. It does not
authorize a hosted service, a commercial launch, a store submission, or any
runtime change.

## Position in one sentence

Hyfens is a Flutter-first, local-first patch platform for supported ordinary
Dart/Flutter source changes, carrying them from a normal developer workflow to
a signed, exact-release, capability-limited patch while preserving the
compiled AOT fallback.

The intended promise is narrower than “arbitrary Dart OTA”:

- a supported source edit is discovered and analyzed by the build-time
  toolchain rather than requiring a patch widget, source-unit file, function
  annotation, or manually rewritten call site;
- the runtime keeps normal Flutter AOT as the fallback and interprets only a
  bounded, signed patch payload;
- product services may decide eligibility and report observations, but they
  cannot make an invalid artifact valid;
- a developer or operator can recover to base without lowering the runtime's
  anti-replay high-water.

This is a design direction, not a claim that a production product exists.

## Evidence vocabulary

The competitor documents use the following labels, which this document keeps:

- **FACT** — directly stated by the local Phase 1D evidence or the pinned
  competitor research.
- **INFERENCE** — a product conclusion derived from those facts; it is not a
  demonstrated product capability.
- **UNKNOWN** — the available evidence does not establish the claim.

“Design target” and “recommendation” are proposals, not evidence labels.
Hyfens must not use a design target as a current product claim.

## Frozen foundation and product boundary

The product is an adapter around the validated Architecture B boundary:

```text
ordinary Flutter/Dart source
        ↓
automatic build-time source instrumentation
        ↓
normal Flutter AOT fallback
        +
bounded patch dispatch
        ↓
signed interpreted patch runtime
```

The following are fixed design invariants:

1. Architecture B remains the runtime architecture. Product services do not
   introduce a Flutter/Dart fork, Kernel transformation, PatchView, annotation
   requirement, or manual dispatch path.
2. Patch Format v1 remains normative and unchanged. Product metadata refers to
   a signed artifact and release identity; it is not inserted into or used to
   reinterpret the v1 container.
3. Capability v1 remains a closed, release-owned authority. A patch cannot
   enumerate native APIs, reflect over arbitrary host objects, add a plugin,
   or add a capability that was not shipped in the store release.
4. Exact application/release/runtime binding remains a runtime decision. A
   control plane can filter delivery, but cannot repair a wrong-release patch.
5. State-v4 trust/high-water, signed rollback, health confirmation, and
   fail-closed recovery remain authoritative on the device. Product rollback
   controls must not lower high-water or make an old artifact replayable.
6. Local runtime correctness must not require cloud connectivity. A hosted or
   self-hosted endpoint is an untrusted delivery input and may be absent,
   delayed, unavailable, or compromised.

## Who the product is for

The primary audience is a Flutter team that wants a narrow, observable path
from an ordinary source edit to a release-bound patch without adopting a
toolchain fork. The jobs are intentionally separated by product mode:

| Audience | Job | Required product posture |
| --- | --- | --- |
| Flutter developer | Turn a supported source edit into a verified patch | Local CLI, clear diagnostics, no bytecode authoring |
| Release engineer | Register an immutable release, sign, deploy, and recover | Idempotent workflows, exact binding, audit trail |
| OSS/self-host operator | Run delivery without depending on Hyfens hosting | Open protocol, reference server, documented storage and backup boundary |
| Team owner | Control environments and approvals | Later managed workflow; not a runtime authority |
| Security/enterprise administrator | Control keys, access, retention, and deployment location | Later enterprise policies; no current compliance claim |

## Positioning pillars

### 1. Flutter-first developer experience

**FACT:** The Phase 1D workflow records ordinary source edits, automatic
build-time instrumentation, local analysis, patch generation, inspection,
verification, status, and signed base rollback. It requires no source-unit
files, function IDs, slots, bytecode, manual manifests, annotations, rewritten
call sites, PatchView, or Flutter SDK modification in the validated fixture.

**INFERENCE:** This is the strongest first product wedge: make the safe path
feel like normal Flutter development while keeping the supported subset and
store-release boundary explicit. “Transparent” means transparent source
workflow; it does not mean every Dart construct, native input, asset, or
platform change is patchable.

The supported workflow must keep an explicit failure path:

```text
ordinary source edit
        ├─ supported, exact-release-compatible → analyze → sign → deployable patch
        └─ unsupported/native/build input      → clear store-release-required result
```

No product tier should turn a false negative into an unsafe partial patch.

### 2. Rollback that is a safety operation, not a content pointer

**FACT:** The current state-v4 controller verifies candidates, confirms health,
retains a last-known-good/base fallback, preserves high-water across restart
and signed base rollback, and fails closed when durable trust state is
ambiguous. Phase 1D physical runs demonstrated process/restart behavior on the
bounded fixture.

**INFERENCE:** Rollback is a product differentiator only if the hosted or
self-hosted control plane exposes the same distinction:

- pause delivery eligibility;
- issue a release-bound signed rollback control to base;
- promote a newly signed known-good patch above the retained high-water;
- require a store release when the fix crosses the patch boundary.

An operator pointer to an older patch is not sufficient. Product records and
runtime states must remain separate: `DRAFT`, `READY`, `ACTIVE`, or
`ROLLED_BACK` are control-plane states, while `BASE`, `CANDIDATE`, `CURRENT`,
and `FAILED` are runtime states.

### 3. Security that remains inspectable and local

**FACT:** Patch Format v1 binds identity, capabilities, digest, and signature;
capability v1 is closed and release-owned; exact release checks, sequence
high-water, signed rollback, bounded verification, and fail-closed recovery are
part of the current local boundary. The local threat model explicitly does
not claim protection against a rooted/fully compromised device, compromised
signing keys, trusted transport, or production key custody.

**INFERENCE:** Open specifications, an auditable runtime/verifier, local
verification, and an optional self-host path can be intended differentiators.
They are not superiority claims. A managed service may add convenience and
operations, but it must not hide or replace the device trust boundary.

### 4. Self-hosting as a deployment choice

**FACT:** The current repository contains a local development server and
toolchain, not a production control plane. Ejenix's inspected repository
contains a public server and deployment material; its durability and live
operation were not independently established. Shorebird's public material
does not provide a complete production-equivalent self-hostable backend.

**INFERENCE:** A minimal self-hostable reference path is a credible design
differentiator, especially for teams that cannot make the runtime depend on a
vendor cloud. It must be treated as a product requirement to design and later
validate, not as a current availability claim. The self-hosted path must
preserve immutable artifacts, tenant/application isolation, customer-managed
signing choices, backups, air-gap import verification, and the same runtime
protocol boundary.

### 5. Enterprise controls as a later operational layer

**UNKNOWN:** Neither competitor teardown establishes a complete, independently
verified enterprise feature set, and this repository has no enterprise control
plane. SSO/SCIM, advanced RBAC, approval policies, audit export/retention,
managed KMS/HSM, private networking, on-premises operation, air-gap support,
SLA, and support commitments therefore remain design candidates.

**INFERENCE:** Enterprise value should come from deployment, governance, and
operational controls around the open runtime—not from withholding signature,
release-binding, verifier, or rollback safety. No enterprise feature is a
reason to weaken the local boundary.

## Competitive evidence and classification

The following comparison is deliberately scoped to what the repository
research establishes. It does not copy competitor internals or infer store
approval, security superiority, or service quality.

| Dimension | Shorebird evidence | Ejenix evidence | Hyfens positioning implication |
| --- | --- | --- | --- |
| Developer experience | **FACT:** ordinary Dart/Flutter code is patchable without a special view; a coordinated Flutter/engine/toolchain distribution is used. | **FACT:** an explicit `EjenixPatchView`/`InterpretedView` and separate patch source are required; existing screens are not transparently patchable. | **FACT:** Hyfens has bounded ordinary-source/local workflow evidence. **UNKNOWN:** breadth on independent applications. |
| Rollback/recovery | **FACT:** updater persists launch state and falls back after failed launch; public anti-replay/key-rotation semantics are not fully established. | **FACT:** signed bundles, local history, health, crash-loop rollback, and monotonic generations exist; the teardown identifies a server-pointer rollback/high-water interaction. | **FACT:** state-v4 and signed base rollback are bounded locally. **UNKNOWN:** production transport and full power-loss behavior. |
| Security/trust | **FACT:** public updater has a signing verification mode, but verification is documented as optional in the inspected configuration; the critical iOS SDK is private. | **FACT:** Ed25519 bundles, bounded decoding, and a closed host registry are public; first-class operational key rotation/fleet health are not established. | **FACT:** v1 signature, exact release, closed capability, high-water, and fail-closed local controls exist. **UNKNOWN:** protected production key custody and service threat controls. |
| Self-hosting | **UNKNOWN:** a complete production-equivalent hosted backend/self-host stack is not supplied by the inspected public repositories. | **FACT:** a self-hostable server and deployment material are public; live production durability was not tested by the teardown. | **INFERENCE:** open minimal self-hosting is an intended differentiator. It is not yet a delivery claim. |
| Enterprise | **UNKNOWN:** the inspected public material does not establish a complete enterprise/on-prem control set. | **UNKNOWN:** the inspected public material does not establish a complete enterprise/on-prem control set. | **FUTURE:** enterprise identity, policy, key custody, residency, and support are later design tracks. |
| Store policy | **UNKNOWN:** competitor existence or technical architecture does not establish future review outcomes. | **UNKNOWN:** public examples and claims do not establish store acceptance. | **OUT OF SCOPE:** require an independent Apple/Google/legal review; make no approval or compliance claim. |

### Capability classification

Classification means priority for a credible product, not current
availability. Each row has an evidence state so a proposal cannot be read as
a shipped feature.

| Capability | Classification | Evidence state and boundary |
| --- | --- | --- |
| Automatic source instrumentation for supported ordinary Flutter/Dart code | FIRST CREDIBLE PRODUCT | **FACT:** bounded Architecture B/local workflow evidence. Broad language and app coverage remain unproven. |
| Local CLI for doctor/init/release/analyze/patch/inspect/verify/status/rollback | FIRST CREDIBLE PRODUCT | **FACT:** the Phase 1D workflow exists locally; hosted packaging is not implemented. |
| Patch Format v1, capability v1, exact release binding, signed verification | FIRST CREDIBLE PRODUCT | **FACT:** frozen normative/runtime boundary. No product metadata may mutate it. |
| AOT fallback, bounded interpretation, health confirmation, fail-closed recovery | FIRST CREDIBLE PRODUCT | **FACT:** current runtime model; physical and independent-app limitations remain. |
| Clear unsupported-change and store-release-required diagnostics | COMPETITIVE PARITY | **INFERENCE:** required to make a transparent workflow safe and credible. |
| Local/offline verification and signed base rollback retaining high-water | COMPETITIVE PARITY | **FACT:** bounded local behavior; direct stale-byte physical rejection and power-loss guarantees remain unknown. |
| Immutable/content-addressed artifacts and all-or-none self-host promotion | COMPETITIVE PARITY | **INFERENCE:** required control/distribution design; no server implementation is authorized here. |
| Managed release registry, artifact delivery, environment policy, and audit | COMPETITIVE PARITY | **UNKNOWN:** no managed product exists; design only. |
| Canary, percentage, deterministic cohort, pause, emergency stop, and promotion history | COMPETITIVE PARITY | **INFERENCE:** expected managed-product controls; rollout must never override runtime validity. |
| Optional privacy-preserving observations and bounded fault signals | COMPETITIVE PARITY | **UNKNOWN:** no telemetry ingestion exists; telemetry must never be required for correctness. |
| Open protocol/runtime/compiler/verifier and minimal self-host reference | DIFFERENTIATOR | **INFERENCE:** transparency and deployment choice are intended differentiators, not superiority claims. |
| Customer-managed signing, offline/air-gapped import, private distribution | DIFFERENTIATOR | **FUTURE:** design target requiring security, packaging, and operational validation. |
| SSO/SCIM, advanced RBAC, two-person approval, audit export/retention, managed KMS/HSM, private networking, on-premises, SLA/support | FUTURE | **UNKNOWN:** enterprise controls are not present and require separate authorization and validation. |
| Framework-neutral control-plane vocabulary and a future React Native adapter | FUTURE | No React Native runtime or adapter is in scope for this phase. |
| Downloaded native code, plugin implementation, manifest/plist, permissions, entitlements, asset/compiled-library changes | OUT OF SCOPE | These remain store-release boundaries; no product tier changes that rule. |
| Store approval, App Store/Play compliance, security certification, or privacy-law compliance | OUT OF SCOPE | **UNKNOWN:** requires authoritative legal, policy, and audit evidence. |

## Product modes and responsibility boundary

These are candidate packages, not pricing or launch commitments:

| Mode | Intended contents | Responsibility boundary |
| --- | --- | --- |
| Community / OSS self-hosted | Open runtime, specs, compiler/instrumenter, CLI, verifier, local status/rollback, and minimal reference control/distribution path | Operator owns hosting, storage, keys, upgrades, policy, and availability |
| Managed Cloud | Hosted control/distribution operations, managed availability, optional observations, team workflow, and support | Hyfens operates services; runtime still verifies locally |
| Team / Business | Shared projects/environments, approvals, access policy, retention, and audit workflows | Product governance layer; no new runtime authority |
| Enterprise | SSO/SCIM, advanced policy, private networking, customer-managed KMS/HSM, on-premises/air-gap support, custom retention, and SLA/support | Separate enterprise authorization, contracts, security review, and operational evidence |

Pricing, packaging names, and final feature gates require a later decision.

## Claims discipline

Until a maintainer review and later implementation evidence exist, Hyfens must
not say that it is production-ready, arbitrary-Dart compatible, native-speed,
fully self-hosted in production, store-approved, App Store/Play compliant,
GDPR/DPDP/SOC 2/ISO compliant, secure against rooted devices, or validated on
independent customer applications. “Open,” “self-hosted,” “enterprise,” and
“managed” describe design targets until their licensing, deployment, and
operational evidence exists.

## Phase 1D limitations carried into product design

These limitations are conditions on claims, not permission to weaken the
architecture:

| Limitation | Required wording/disposition for positioning |
| --- | --- |
| True physical power-loss interruption was not tested. | **UNKNOWN / NOT TESTED.** Do not promise power-loss durability; assign a later release-gate decision. |
| Direct physical runtime rejection of supplied stale valid bytes was not proven; delivery-boundary withholding was observed. | **UNKNOWN / NOT PHYSICALLY PROVEN.** Do not describe delivery withholding as runtime rejection. |
| iOS runtime logs/UI and performance were unavailable because the Developer Disk Image was unavailable. | **UNKNOWN / ENVIRONMENT-GATED.** The physical run is process/state evidence, not iOS UI or timing evidence. |
| A fresh Phase 1D Android 15-sample performance reducer was not run. | **UNKNOWN / NOT RUN.** Phase 1C Android baseline remains authoritative; no new percentage or regression claim. |
| Flutter 3.47.1/Dart 3.13.1 full CLI/device workflow was not isolated. | **SUPPORTED_WITH_LIMITATIONS.** Direct checks do not establish the full adjacent-SDK workflow. |
| Independent customer-application validation was not run. | **UNKNOWN / NOT RUN.** Fixture-level evidence must not be marketed as customer validation. |
| The additional async benchmark was not completed. | **UNKNOWN / NOT RUN.** No broader Future/Stream, hot-frame, or async performance claim. |
| Host interpreter stage attribution, fresh iOS timings, memory/thermal/battery data, fresh controlled binary growth, and physical multi-function scaling remain incomplete or unmeasured. | **UNKNOWN / PARTIAL.** Use the preserved Phase 1C evidence only within its original scope. |
| Raw coordinator captures are session evidence, not an immutable release/CI evidence service. | **FACT:** evidence provenance must be designed before production claims. |
| Duplicate historical task/39 numbering is preserved. | **FACT:** do not renumber or reinterpret repository history as product evidence. |

The authoritative review remains [`docs/PHASE_1D_REVIEW.md`](../reviews/PHASE_1D_REVIEW.md).

## Explicit non-goals for this package

This package does not implement or authorize:

- backend services, database schemas or migrations, a production REST server,
  CDN integration, a web dashboard, authentication providers, billing, KMS
  integration, telemetry ingestion, or a rollout scheduler;
- enterprise SSO/SCIM, production deployment, store submission, or a React
  Native runtime;
- changes to Architecture B, Patch Format v1, capability v1, exact release
  binding, state-v4 trust/high-water, signed rollback, or fail-closed recovery;
- a Flutter/Dart fork, Kernel transformation, PatchView, manual dispatch,
  arbitrary host reflection, native enumeration, or cloud-required runtime
  correctness;
- a license change, public publication, pricing decision, compliance claim, or
  superiority claim about Hyfens or a competitor.

## References

- [`Productization PRD`](PRODUCTIZATION_PRD.md)
- [`Phase 1D maintainer review`](../reviews/PHASE_1D_REVIEW.md)
- [`Shorebird teardown`](../../competitors/shorebird.md)
- [`Ejenix teardown`](../../competitors/ejenix.md)
- [`Patch Format v1`](../../spec/patch-format-v1.md)
- [`Capability Contract v1`](../../spec/capability-v1.md)
- [`Runtime state machine`](../../architecture/runtime-state-machine.md)
- [`Threat model`](../../security/threat-model.md)
