# ADR 0004 — OSS/commercial boundary

- Status: Proposed for maintainer review; design only
- Date: 2026-08-23
- Decision owners: Maintainers

## Context

Task 40 needs a product boundary around the validated local Flutter
toolchain. The boundary must support a useful open-source/self-hosted path and
leave room for managed and enterprise products without turning the runtime's
trust decisions into a proprietary service.

The current repository license is intentionally a placeholder and grants no
permission. The existing third-party notices describe dependency terms but do
not select a project license. No license decision or publication is made by
this ADR.

Phase 1D permits a maintainer-reviewed productization design only. It does not
authorize cloud, accounts, rollout, telemetry, dashboard, enterprise, store,
or production infrastructure work.

## Decision

Propose an open-core boundary with the following ownership:

### OPEN SOURCE

- Patch Format v1 and capability v1 specifications, conformance vectors, and
  protocol documentation;
- the Flutter runtime, verifier, generated bootstrap, bounded interpreter,
  capability authority, state-v4 lifecycle, AOT fallback, and signed rollback
  behavior;
- the source instrumenter, bounded compiler, compatibility analysis,
  diagnostics, source mapping, and local CLI;
- local inspect/verify/status/rollback/cleanup tools;
- a minimal local/self-host reference control and distribution path, with no
  claim of high availability, hosted support, or production readiness;
- examples, fixtures, and compatibility tests needed to audit the boundary.

### SOURCE AVAILABLE

Do not place the core in this category. If maintainers later publish optional
managed-service deployment adapters or operator extensions under a
source-available license for inspection, they must be separated from the OSS
core, carry an explicit non-OSI license, and not be required for local runtime
correctness or minimum self-hosting. The default recommendation is to avoid
this category where an OSS implementation is practical.

### COMMERCIAL

- managed control-plane and distribution operations;
- hosted availability, backup/restore operations, managed observations, and
  service support;
- team/organization workflow, hosted approvals, hosted audit retention/export,
  and hosted policy management;
- commercial support, training, and other service responsibilities.

### ENTERPRISE

- SAML/OIDC/SCIM, advanced RBAC, two-person approval policies, private
  networking, customer-managed KMS/HSM integrations, on-premises and air-gap
  packaging, custom retention/residency controls, SLA, and enterprise support.

These are future product candidates, not present capabilities.

### INTERNAL OPERATIONS

Managed-service secrets, production signing/KMS operations, hosted telemetry
pipelines, abuse detection, on-call systems, customer support systems,
incident-response playbooks, and private operational data remain internal.
They must not be required as an undisclosed runtime authority or published with
credentials.

## Invariants

This boundary does not alter:

- Architecture B: automatic source instrumentation, normal Flutter AOT
  fallback, and bounded interpreted dispatch;
- Patch Format v1, including canonical encoding, exact identity, required
  sections, digest/signature boundary, bounds, and version-evolution rules;
- capability v1 as a closed, release-owned, versioned host authority;
- exact application/release/runtime binding;
- state-v4 trust/high-water authority, signed rollback, and fail-closed
  recovery;
- process-local runtime ownership and generated-start single-flight.

A control plane may select whether and when to deliver an artifact. It cannot
  replace signature verification, lower high-water, rewrite release identity,
  add capabilities, or make a server record authoritative over device state.
Cloud connectivity is never a prerequisite for local runtime correctness.

## Licensing options considered

| Option | Decision analysis |
| --- | --- |
| Apache-2.0 | Preferred candidate for the open core because it is permissive and has an explicit patent grant; requires notice and dependency review. |
| MIT | Viable lower-friction alternative for selected code, but offers less explicit patent language. |
| BSD-3-Clause | Viable permissive alternative; no current reason to prefer it over Apache-2.0. |
| GPL/AGPL | Possible if reciprocal sharing is a primary goal, but not the default for a Flutter runtime/protocol and self-host reference because adoption and service obligations need separate analysis. |
| Source-available | Not OSI-approved; reserve only for non-essential extensions if a separate rationale exists. |
| Dual licensing | Requires a separate contributor/IP and legal decision; not implied by this ADR. |

No option is selected until maintainers approve the project license. The
placeholder [`LICENSE`](../../LICENSE) and dependency
[`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md) remain unchanged.

## Consequences

Positive consequences:

- contributors can inspect and test the protocol, verifier, runtime, and
  developer workflow without a hosted account;
- self-hosting is a real design path rather than a promise to replicate a
  private service;
- commercial differentiation can come from operations, collaboration, and
  support without withholding the client safety boundary;
- managed and enterprise features can evolve without adding hosted trust to
  installed applications.

Costs and risks:

- maintaining a minimal self-host reference and a managed service creates
  compatibility work;
- a permissive OSS core does not itself provide support, HA, compliance, or
  security assurance;
- an optional source-available zone could confuse users and contributors;
  avoiding it is simpler;
- key custody, service compromise, tenant isolation, and observability need
  separate design and validation before production-shaped work.

## Conditions before implementation

Maintainers must approve the license and repository boundary, define a public
compatibility policy, and preserve the local/self-host path. Any product
implementation must pass tests that prove the private service consumes the
public protocol without changing Patch Format v1 or capability v1.

The following Phase 1D limitations remain explicit gates on later claims:

- physical power-loss durability is **NOT TESTED**;
- direct physical rejection of supplied stale valid bytes is **NOT PHYSICALLY
  PROVEN**; delivery-boundary withholding is the evidence;
- iOS runtime logs/UI and performance are **ENVIRONMENT-GATED / NOT RUN** due
  to unavailable Developer Disk Image;
- the fresh Phase 1D Android 15-sample performance reducer is **NOT RUN**;
- the full Flutter 3.47.1/Dart 3.13.1 CLI/device path is
  **SUPPORTED_WITH_LIMITATIONS**, not fully isolated;
- independent customer-application validation is **NOT RUN**;
- the additional async benchmark is **NOT RUN**;
- host stage attribution, fresh iOS timings, fresh controlled binary-growth
  comparisons, physical multi-function scaling, memory/thermal/battery
  evidence, and immutable release/CI evidence-service provenance remain
  incomplete or unmeasured.

These conditions do not authorize weakening the runtime or making production
claims.

## Explicit non-goals

This ADR does not implement or authorize a backend, schema/migration, REST
server, CDN, dashboard, authentication provider, billing, KMS integration,
telemetry ingestion, rollout scheduler, enterprise SSO, React Native runtime,
production deployment, or store submission. It does not change licenses,
repositories, packages, runtime code, protocol files, or cloud configuration.

It makes no App Store/Play, GDPR/DPDP, SOC 2, ISO, security-certification,
production-readiness, or competitor-superiority claim.

## References

- [`OSS and commercial boundary`](../architecture/oss-commercial-boundary.md)
- [`Product positioning`](../history/product/positioning.md)
- [`Phase 1D review`](../history/reviews/PHASE_1D_REVIEW.md)
- [`ADR 0002 — Architecture B baseline`](0002-adopt-source-instrumentation-for-phase-1.md)
- [`Patch Format v1`](../spec/patch-format-v1.md)
- [`Capability Contract v1`](../spec/capability-v1.md)
- [`Runtime state machine`](../architecture/runtime-state-machine.md)
- [`Threat model`](../security/threat-model.md)
