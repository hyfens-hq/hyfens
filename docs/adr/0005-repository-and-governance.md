# ADR 0005 — Repository topology and OSS governance

- Status: Proposed for maintainer review; design only
- Date: 2026-08-23
- Decision owners: Maintainers

## Context

Task 40 must separate a community-auditable Flutter runtime from later
managed, enterprise, and internal operations without fragmenting the protocol.
The current checkout is a research repository with a placeholder project
license. This ADR proposes a future repository and governance shape; it does
not split the checkout, move packages, or publish code.

The fixed compatibility boundary is Architecture B, Patch Format v1,
capability v1, exact release binding, state-v4 trust/high-water, signed
rollback, and fail-closed recovery. Repository boundaries must preserve that
boundary rather than create a private replacement.

## Decision

Recommend two logical repositories when product implementation is authorized:

1. **Public OSS core repository** — the protocol, runtime, compiler/
   instrumenter, local CLI, verifier, local/self-host reference path,
   conformance tests, and design/specification documents.
2. **Private commercial/enterprise and operations repository** — managed
   control/distribution service, hosted collaboration and policy, enterprise
   integrations, deployment automation for the managed service, and internal
   operations. It consumes released public packages and passes a shared
   compatibility suite; it does not fork the v1 trust/protocol semantics.

This is a recommendation for a future implementation phase, not authorization
to create either repository now.

## Alternatives considered

### One repository

**Advantages:** atomic changes across runtime and service; one issue tracker;
simple end-to-end testing; easier coordinated refactors while the project is
small.

**Risks:** public history and private service code become entangled; access,
secrets, customer data, and operational runbooks require exceptional handling;
different licenses and release cadences become difficult to explain; a hosted
feature can accidentally become a runtime dependency.

**Assessment:** reasonable during research or before any private service
exists, but not preferred once commercial and internal operations have distinct
access and threat boundaries.

### Two logical repositories

**Advantages:** clear legal/access boundary; a coherent public contribution
surface; private operations can evolve with restricted data; a managed service
can be tested against released public contracts; internal secrets never need
to be represented as repository history.

**Risks:** cross-repository compatibility and release coordination; the private
service can drift from the self-host reference; duplicated integration tests or
release metadata may become stale.

**Assessment:** recommended, with a public conformance suite and explicit
compatibility matrix as the integration gate.

### Many package/repository splits

**Advantages:** independent ownership, release cadence, and licensing; useful
if the runtime, compiler, CLI, and server truly have different consumers.

**Risks:** fragmented contributor experience, dependency/version skew, harder
end-to-end test setup, and more seams across public/private boundaries. A
package split can become an architecture decision disguised as repository
administration.

**Assessment:** defer. Begin as one coherent public OSS monorepo and split only
when independent cadence, ownership, or licensing is demonstrated.

## Proposed repository contents

| Surface | Repository | Classification | Boundary |
| --- | --- | --- | --- |
| Patch Format v1, capability v1, API/domain contracts, ADRs, conformance vectors | Public OSS | OPEN SOURCE | Versioned public contract; no SaaS metadata in v1 |
| Runtime, verifier, interpreter, generated bootstrap, state-v4, rollback, capability authority | Public OSS | OPEN SOURCE | Device remains authoritative; no hosted account required |
| Instrumenter/compiler/source maps/diagnostics and local CLI | Public OSS | OPEN SOURCE | Normal Flutter/Dart source workflow and local verification |
| Local server and minimal self-host control/distribution reference | Public OSS | OPEN SOURCE | Reference/single-tenant path; no HA/support/compliance claim |
| Optional managed-service adapters published for inspection | Separate only if needed | SOURCE AVAILABLE | Non-essential, separately licensed, never required for runtime correctness; default is to avoid this category |
| Hosted control/distribution, team/org, billing, managed observations, hosted audit | Private product | COMMERCIAL | Service responsibility, not runtime trust |
| SSO/SCIM, advanced RBAC/approvals, KMS/HSM, private networking, on-prem/air-gap, custom retention, SLA/support | Private product | ENTERPRISE | Separate authorization and operational/security evidence |
| Production credentials, KMS operations, telemetry processing, abuse detection, on-call/support systems | Internal operations | INTERNAL OPERATIONS | Never commit secrets or customer data; no client authority |

The current research checkout is not retroactively classified as published OSS
because its [`LICENSE`](../../LICENSE) says permission is pending.

## Governance proposal

### Maintainers and decision records

- Maintain a small named maintainer group with authority over protocol,
  runtime, release, and security changes. Names and legal structure require a
  later maintainer decision.
- Keep architectural decisions in ADRs. A change to Patch Format v1, its
  digest/signature boundary, required fields, bounds, or semantics requires a
  new explicit format-version ADR. A capability schema/execution/security
  change requires a new capability version and compatibility record.
- Use public design discussions/RFCs for user-facing protocol, licensing,
  compatibility, and repository-boundary changes. Do not use a private hosted
  implementation to silently define an OSS contract.

### Contributions and provenance

The default governance candidate is a Developer Certificate of Origin (DCO)
workflow because it gives contributors a low-friction provenance attestation.
A Contributor License Agreement (CLA/CCLA) is an alternative if maintainers
need explicit relicensing or commercial licensing rights. Neither is selected
by this ADR; legal and contributor-experience review are required before
adoption.

Regardless of DCO/CLA choice, the project should require:

- contribution provenance and third-party license review;
- tests and conformance evidence for runtime/protocol changes;
- no private keys, credentials, customer data, or production operations in
  public history;
- security-sensitive changes to receive maintainer/security review;
- generated artifacts to be changed through their source/generator and
  reviewed for protocol compatibility.

### Release and compatibility policy

- Publish a versioned compatibility matrix for Flutter/Dart, runtime, Patch
  Format, capability contract, platform, and toolchain.
- Keep the supported matrix narrow and evidence-based. The Phase 1D status for
  Flutter 3.47.1/Dart 3.13.1 remains `SUPPORTED_WITH_LIMITATIONS` until the
  full workflow is isolated.
- Use reproducible release notes with supported, limited, unknown, and
  unsupported classifications. Do not convert fixture evidence into customer
  validation.
- Preserve the normal AOT fallback and require explicit store-release-required
  outcomes for native/build-input/unsupported changes.
- Define a security support window and backport policy before offering service
  or enterprise commitments. A support window is not an assurance or
  compliance certification.

### Security governance

- Provide a private vulnerability-reporting path and a documented embargo and
  advisory process once public publication is authorized.
- Keep signing-key custody, key rotation/revocation, managed KMS, and recovery
  decisions separate from ordinary feature review.
- Require threat-model updates for tenant isolation, artifact/control-plane/
  CDN compromise, key compromise, rollout abuse, telemetry spoofing, webhook
  replay, SSRF, supply-chain compromise, self-host misconfiguration, and
  air-gap import tampering.
- Treat runtime signature, exact release, high-water, capability, and
  fail-closed checks as the final safety boundary even when service telemetry
  or audit is unavailable.

### Community/service relationship

- The public repository owns the normative open protocol and reference
  behavior.
- The private repository consumes tagged public artifacts and must run the
  public conformance suite before a managed service release.
- Hosted-only features must be documented as hosted-only. They cannot be
  required for local runtime correctness or presented as part of the open
  protocol without a public contract decision.
- The self-host reference must not be intentionally crippled in ways that
  undermine the stated self-hosting requirement. Commercial value comes from
  operated service, collaboration, policy, support, and enterprise controls.

## Phase 1D limitations retained

Repository governance must preserve these exact evidence boundaries:

- physical power-loss interruption: **NOT TESTED**;
- direct runtime rejection of supplied stale valid bytes: **NOT PHYSICALLY
  PROVEN**; delivery-boundary withholding is proven;
- iOS runtime logs/UI and performance: **ENVIRONMENT-GATED / NOT RUN** because
  the Developer Disk Image was unavailable;
- fresh Phase 1D Android 15-sample performance reducer: **NOT RUN**;
- Flutter 3.47.1/Dart 3.13.1 full CLI/device path:
  **SUPPORTED_WITH_LIMITATIONS**;
- independent customer application validation: **NOT RUN**;
- additional async benchmark: **NOT RUN**;
- host interpreter stage attribution, fresh iOS timings,
  memory/thermal/battery, fresh controlled binary growth, physical
  multi-function scaling, and immutable release/CI evidence-service
  provenance: incomplete, partial, or unmeasured.

No repository or governance decision may turn these into production claims.

## Explicit non-goals

This ADR does not create repositories, move files, change the license, add a
CLA/DCO, implement governance tooling, or authorize any production code. It
does not implement a backend, schema/migration, REST server, CDN, dashboard,
authentication provider, billing, KMS integration, telemetry ingestion,
rollout scheduler, enterprise SSO, React Native runtime, production
deployment, or store submission.

It does not change Architecture B, Patch Format v1, capability v1, exact
release binding, state-v4 trust/high-water, signed rollback, or fail-closed
recovery. It makes no store-policy, privacy-law, security-certification,
production-readiness, or competitor-superiority claim.

## Implementation-gate checklist for a later phase

Before acting on this ADR, maintainers should approve:

1. an OSI-approved open-core license and third-party notice process;
2. the public/private repository boundary and package ownership map;
3. DCO versus CLA/CCLA and the contributor/IP policy;
4. a compatibility matrix and public conformance gate for private consumers;
5. the minimum self-host reference and its backup/air-gap evidence;
6. the security disclosure, release, and support policy;
7. the separate legal/store-policy review and Phase 1D limitation disposition.

## References

- [`OSS and commercial boundary`](../architecture/oss-commercial-boundary.md)
- [`Product positioning`](../history/product/positioning.md)
- [`Productization PRD`](../history/product/PRODUCTIZATION_PRD.md)
- [`Phase 1D review`](../history/reviews/PHASE_1D_REVIEW.md)
- [`ADR 0002 — Architecture B baseline`](0002-adopt-source-instrumentation-for-phase-1.md)
- [`Patch Format v1`](../spec/patch-format-v1.md)
- [`Capability Contract v1`](../spec/capability-v1.md)
- [`Threat model`](../security/threat-model.md)
- [`License placeholder`](../../LICENSE)
- [`Third-party notices`](../../THIRD_PARTY_NOTICES.md)
