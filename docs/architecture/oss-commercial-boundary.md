# OSS and commercial boundary

Status: DESIGN ONLY — NO PRODUCTION IMPLEMENTATION

This document proposes the boundary between the open-source/self-hosted
surface and managed or enterprise product operations. It is a design proposal
for maintainer review. It does not change the current repository license,
create a commercial service, or authorize implementation.

## Decision summary

Propose an open-core boundary with a deliberately broad, useful OSS core:

1. Open the protocol specifications, runtime/verifier, capability authority,
   instrumenter/compiler, local CLI, local status/rollback tooling, conformance
   fixtures, and a minimal self-host reference control/distribution path.
2. Keep managed hosting, managed distribution operations, hosted analytics,
   team workflow, commercial support, and service availability as commercial
   product responsibilities.
3. Place SSO/SCIM, advanced enterprise policy, customer-managed KMS/HSM
   integrations, private networking, on-premises/air-gap packaging, custom
   retention, and SLA/support commitments in an enterprise offering.
4. Keep signing, runtime verification, exact-release checks, capability v1,
   state-v4 high-water, signed rollback, and fail-closed recovery in the open
   client/runtime boundary. Commercial services may orchestrate them but may
   not replace them.
5. Do not put essential runtime or protocol material behind a source-available
   license. If source-available material is used at all, limit it to optional
   managed-service/operator extensions and label it clearly as not open source.

The recommendation is conditional on a maintainer/legal license decision. The
current [`LICENSE`](../../LICENSE) is an explicit placeholder that grants no
permission to use, copy, modify, or distribute the repository.

## Frozen runtime and trust invariants

The OSS/commercial split must not create a second trust model:

- Architecture B remains automatic source instrumentation + normal Flutter AOT
  fallback + bounded interpreted dispatch.
- Patch Format v1 remains unchanged, including its canonical encoding,
  identity, capability, digest/signature boundary, bounds, and evolution rule.
- Capability v1 remains closed, versioned, release-owned, and non-reflective.
  A service cannot add a capability or native adapter to an installed release.
- The runtime, not the control plane, decides signature validity, exact release
  compatibility, sequence/high-water freshness, capability policy, resource
  bounds, health, rollback, and fallback.
- A hosted or self-hosted endpoint is untrusted and optional. It can return no
  update, delay delivery, filter a rollout, or be unavailable; it cannot turn
  an invalid artifact into a valid one.
- Product metadata, rollout state, tenancy, audit, billing, and observations
  remain outside the Patch Format v1 payload. They refer to immutable signed
  identities instead of mutating the v1 protocol.
- Private signing keys do not cross a hosted control plane unless a later
  managed-signing mode explicitly selects that custody model and documents its
  threat boundary.

## Component classification

The labels are packaging decisions, not statements that the components exist
today. “OPEN SOURCE” requires an approved OSI license; the current placeholder
license is not an OSS grant. “SOURCE AVAILABLE” is not OSI-approved open
source and must never be marketed as such.

| Component | Classification | Proposed boundary and rationale |
| --- | --- | --- |
| Patch Format v1 specification and conformance vectors | OPEN SOURCE | Protocol transparency and independent verification require public, versioned material. Changes still need an explicit format version. |
| Capability Contract v1 specification and capability-policy conformance tests | OPEN SOURCE | The host/guest trust contract must be inspectable; no arbitrary host reflection or native enumeration is exposed. |
| Flutter runtime, interpreter, verifier, generated bootstrap, state-v4 lifecycle, fallback, and local rollback controller | OPEN SOURCE | Safety-critical client behavior must remain auditable and usable without a hosted account. |
| Source instrumenter, bounded compiler, source maps, diagnostics, and compatibility analysis | OPEN SOURCE | This is the Flutter-first developer experience and should be community-testable rather than a hidden service dependency. |
| Local CLI: doctor, init, keys, release, analyze, patch, inspect, verify, status, rollback, cleanup | OPEN SOURCE | Local-first correctness, offline verification, and self-host workflows depend on a usable CLI. |
| Local development server and exact-release self-verified delivery adapter | OPEN SOURCE | The existing local boundary is a development aid; its implementation and protocol should remain reproducible. |
| Minimal self-hosted control/distribution reference implementation | OPEN SOURCE | A bounded single-tenant/reference path proves the deployment contract and supports self-hosting. It does not imply HA, support, or production readiness. |
| Protocol client interfaces, API/domain documentation, examples, and conformance fixtures | OPEN SOURCE | Keeps product/control-plane concepts portable without leaking framework-specific runtime internals into generic APIs. |
| Optional managed-service deployment adapters or admin extensions published for inspection but not required by Community | SOURCE AVAILABLE | This is the only proposed source-available zone. It may protect service-specific operations while allowing review, but it is not part of the OSS core and requires a separate license decision. Prefer avoiding this category where an OSS implementation is practical. |
| Managed hosted control plane, hosted artifact/distribution operations, service availability, backups, and managed observations | COMMERCIAL | Differentiation is operational convenience and responsibility, not a replacement for local verification. No hosted implementation is authorized here. |
| Team/organization workflow, hosted approvals, hosted audit retention/export, hosted policy management, commercial support, and training | COMMERCIAL | These are managed collaboration and service responsibilities; basic local/self-host operation remains possible without them. |
| SAML/OIDC/SCIM, advanced RBAC, two-person production approval, private networking, residency controls, on-premises packaging, air-gap support, customer-managed KMS/HSM integrations, custom retention, SLA, and enterprise support | ENTERPRISE | These require separate security, contract, deployment, and operational evidence. They are future product options, not current capabilities. |
| Hyfens managed signing/KMS operations, hosted telemetry pipelines, abuse detection, on-call systems, production secrets, customer support systems, and incident response tooling | INTERNAL OPERATIONS | These are operational assets and must not be shipped as runtime trust or exposed with secrets. A later managed-signing mode requires explicit review. |

The table does not make an availability or compliance claim. It defines where a
future implementation may live.

## Why the boundary is not a thin client / private server split

Putting only a client SDK in OSS while withholding the verifier, protocol, or
self-host path would make the security story difficult to inspect and would
turn local correctness into a hosted dependency. Conversely, putting hosted
customer data, billing, service credentials, or on-call tooling in the public
repository would mix different threat, access, and support boundaries.

The proposed boundary therefore keeps the safety-critical, developer-facing,
and self-host minimum surface open, while charging for operation of services
around that surface. This is an **INFERENCE** from the Phase 1D local-first
trust model and the competitor evidence, not a claim of superiority.

## Repository topology evaluation

The repository decision is detailed in
[`ADR 0005`](../adr/0005-repository-and-governance.md). The options are:

| Option | Strengths | Risks | Assessment |
| --- | --- | --- | --- |
| One repository for OSS, hosted, and enterprise code | Atomic protocol/runtime changes; one issue tracker; easy cross-component tests | Access-control and secret-boundary pressure; private service code becomes entangled with public history; release cadence and licensing become harder to explain | Viable for research, but not preferred once managed/enterprise implementation starts |
| Two logical repositories: public OSS core plus private commercial/operations repository | Clear legal/access boundary; OSS core remains coherent; hosted and enterprise code can evolve privately; shared protocol tests can gate integration | Cross-repository compatibility work; duplicated release coordination; risk of private features drifting from self-host reference | **RECOMMENDED** for the first productization implementation, subject to maintainer approval |
| Many package/repository splits | Independent release cadence and ownership; possible licensing isolation | Fragmented contributor experience, version skew, harder end-to-end testing, and more public/private seams | Defer until package ownership or release cadence is independently justified |

Two repositories does not mean two protocols. The public repository remains the
source of truth for v1 protocol compatibility. A private repository must consume
released public packages and pass a compatibility/conformance suite; it must not
silently fork Patch Format v1 or capability v1.

## Licensing options

The license decision requires maintainer and legal approval. This document does
not change [`LICENSE`](../../LICENSE) or [`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md).

| Option | Fit | Trade-offs | Design disposition |
| --- | --- | --- | --- |
| Apache-2.0 for code and protocol implementations | Permissive adoption with an explicit patent grant and notice model | Requires preserving notices and reviewing third-party compatibility | **Preferred candidate**, pending approval and dependency review |
| MIT for code and possibly simple reference tools | Familiar and low-friction for Flutter/Dart consumers | Less explicit patent language; downstream obligations still need review | Viable fallback for selected packages, not a decision |
| BSD-3-Clause | Familiar permissive alternative | Attribution/non-endorsement conditions; no broad patent grant | Viable but not preferred over Apache-2.0 without a reason |
| GPL/AGPL or another copyleft license | Can require sharing modifications in defined distribution/service cases | May reduce embedding, self-host adoption, and commercial interoperability; exact obligations need legal analysis | Not the default for the runtime/protocol core; revisit only with explicit rationale |
| Source-available license for non-core extensions | Can reserve service-specific rights while publishing implementation for inspection | Not OSI-approved; complicates contribution, packaging, and “open source” language | Avoid for core; optional only for clearly non-essential managed-service extensions |
| Dual licensing | Can support OSS use plus commercial licensing or relicensing flexibility | Contributor copyright/CLA complexity, legal administration, and trust cost | Do not select without a separate legal/governance decision |

The repository's existing dependency notices must remain authoritative for
resolved packages. No competitor code is to be copied into the OSS or private
repository as part of this design, and no third-party notice is replaced by a
project-level license.

## Community and commercial compatibility contract

The later implementation should publish a compatibility matrix with these
seams:

- `applicationId`, exact `releaseId`, platform/architecture target, runtime
  version, Patch Format version, and capability contract versions;
- open artifact identity and digest rules;
- delivery API behavior for no update, blocked, stale, wrong-release, and
  store-release-required outcomes;
- self-host storage and backup responsibilities;
- client-side verification and rollback semantics;
- deprecation and support windows.

The hosted service may add product metadata, rollout policy, auth, audit, and
observations, but those are not permission to alter the open protocol. A
breaking runtime/protocol change requires a new compatibility/versioning
decision; it must not be disguised as a SaaS field.

## Explicit non-goals

This proposal does not implement or authorize:

- a backend service, production REST server, database schema/migration, CDN,
  dashboard, authentication provider, billing, KMS integration, telemetry
  ingestion, rollout scheduler, enterprise SSO, or production deployment;
- a license change, public publication, repository split, package move, or
  commercial pricing decision;
- a Flutter/Dart fork, Kernel transformation, PatchView, manual dispatch, or
  new native/plugin capability;
- store submission, App Store/Play approval, GDPR/DPDP/SOC 2/ISO or other
  compliance certification;
- any weakening of Architecture B, Patch Format v1, capability v1, exact
  release binding, high-water anti-replay, signed rollback, or fail-closed
  recovery.

## Open decisions before implementation

Maintainers must decide, with legal review where applicable:

1. The OSI-approved license for the open core and the treatment of documents,
   examples, and generated artifacts.
2. Whether any non-core source-available extension is worth its complexity;
   the default is to avoid one.
3. Whether the minimal self-host reference is single-tenant/local-only at its
   first implementation gate and what backup/air-gap evidence it must provide.
4. The exact public/private repository boundary and release coordination
   mechanism.
5. Whether managed signing is offered at all, and if so, its separate custody,
   approval, recovery, and audit model.

## References

- [`Product positioning`](../history/product/positioning.md)
- [`Productization PRD`](../history/product/PRODUCTIZATION_PRD.md)
- [`Phase 1D review`](../history/reviews/PHASE_1D_REVIEW.md)
- [`ADR 0002 — Architecture B baseline`](../adr/0002-adopt-source-instrumentation-for-phase-1.md)
- [`Patch Format v1`](../spec/patch-format-v1.md)
- [`Capability Contract v1`](../spec/capability-v1.md)
- [`Runtime state machine`](runtime-state-machine.md)
- [`Threat model`](../security/threat-model.md)
- [`Shorebird teardown`](../competitors/shorebird.md)
- [`Ejenix teardown`](../competitors/ejenix.md)
