# Product roadmap and packaging

Status: DESIGN ONLY — NO PRODUCTION IMPLEMENTATION

<!-- Wide roadmap tables intentionally disable the line-length rule. -->
<!-- markdownlint-disable MD013 -->

This is the operations/self-hosting/roadmap package for Task 40. It proposes a
staged path from the validated local Flutter workflow to self-hosted and later
managed offerings. It does not authorize implementation, select final pricing,
or make a store/compliance readiness claim.

## Product direction

Hyfens should earn trust in this order:

1. preserve the local, ordinary Flutter/Dart workflow and make its limits
   visible;
2. provide a small, inspectable self-hosted delivery seam that customers can
   operate without surrendering signing authority;
3. add managed control/distribution services only after the self-hosted data,
   trust, rollback, and recovery contracts are proven;
4. add team, enterprise, and air-gapped operations as explicit responsibilities
   rather than hiding them behind a hosted-only assumption;
5. keep the Flutter runtime contract stable while exploring other frameworks
   as separate adapters.

The product/control plane adapts to Architecture B. It does not change
automatic source instrumentation, normal AOT fallback, bounded interpreted
dispatch, Patch Format v1, capability v1, exact release binding, state-v4
trust/high-water, signed rollback, or fail-closed recovery.

## Current gate

Phase 1D recommends **PROCEED TO PRODUCTIZATION DESIGN WITH CONDITIONS**. That
recommendation permits maintainer-reviewed design work only. The following are
not authorized by this document:

- a backend or production REST service;
- deployment scripts, Docker/Compose/Kubernetes artifacts, migrations, CDN,
  KMS integration, accounts, billing, dashboard, rollout scheduler, or
  telemetry ingestion;
- enterprise SSO, React Native runtime work, production deployment, or store
  submission.

The next decision is a maintainer gate after the design artifacts and Phase 1D
condition dispositions are reviewed. P1 below is a proposed future
implementation stage, not a current instruction.

## Product credibility floor

The first public product must be credible against Flutter patch/update tools
without promising every enterprise feature. Its minimum story should be:

| Capability | First-public expectation | Classification |
| --- | --- | --- |
| Ordinary Flutter/Dart developer flow | Release and patch from ordinary supported source with clear exclusion diagnostics | FIRST CREDIBLE PRODUCT |
| Exact release and signed artifact verification | Runtime remains authoritative; server cannot weaken it | COMPETITIVE PARITY / SAFETY INVARIANT |
| Local rollback and AOT fallback | Signed base rollback and pending-candidate recovery remain visible and testable | COMPETITIVE PARITY |
| Single-node self-hosting | Inspectable packaging, customer signing, private distribution, backup/restore guidance | DIFFERENTIATOR |
| Immutable artifact and audit trail | Every accepted artifact is digest-addressed and registration/deploy actions are attributable | COMPETITIVE PARITY |
| All-or-none delivery | Safe default before percentage/canary automation exists | FIRST CREDIBLE PRODUCT |
| Staged rollout and runtime observations | Deliberately later, opt-in, and fail-safe | FUTURE → P3 |
| Teams, RBAC, approvals, retention, SSO/SCIM | Later commercial/enterprise boundary | FUTURE → P4/P5 |
| Air-gapped/on-prem operation | Designed as an explicit deployment mode, not a marketing implication | DIFFERENTIATOR → P5 |
| React Native | Framework-neutral concepts and a research track only | OUT OF SCOPE for Flutter-first releases |

Self-hosting, open protocol/runtime transparency, customer-managed signing,
deployment flexibility, and a clear trust boundary are the intended
differentiators. The design must not claim superiority over Shorebird, Ejenix,
or another competitor without comparable evidence.

## Candidate offerings (no final pricing)

These are candidate responsibility boundaries. Pricing, packaging names, usage
meters, and commercial terms require separate authorization.

| Offering | Candidate value | Included design boundary | Customer responsibility | Explicit non-claim |
| --- | --- | --- | --- | --- |
| Community / OSS self-hosted | Inspectable local-to-single-node path for developers and small teams | Flutter runtime, instrumenter/compiler, local CLI, protocol/specs, verification libraries, minimal self-host reference, rollback/status tooling, protocol documentation | Hosting, PostgreSQL/object storage, TLS, identity, signing keys, backups, upgrades, support, policy review | Not a hosted SLA, certification, or store approval |
| Managed Cloud | Provider-operated control and distribution for teams that accept hosted operations | Multi-tenant control plane, immutable artifacts, authenticated lookup/fetch, managed operations, optional telemetry, documented service objectives after measurement | Project configuration, release approvals, customer trust/key choice, client app behavior, store/legal review | No implied compliance or platform-policy approval |
| Team / Business | Collaboration and safer release operations | Teams, RBAC, environment protection, audit, CI credentials, all-or-none and staged rollout controls, support boundary | Member lifecycle, release policy, customer data retention and key ownership choice | No final pricing or enterprise SSO promise at launch |
| Enterprise | Private governance and deployment options | On-prem/private cluster, air-gap import/export, SAML/OIDC/SCIM candidates, advanced RBAC/approvals, audit export/retention, KMS/HSM adapters, custom support/SLO options | Infrastructure, identity, network, key custody, residency decisions, validation and policy approvals | Designed controls are not GDPR/DPDP/SOC 2/ISO certification |

The OSS/commercial split should be reviewed with licensing and security
maintainers. A useful default is to keep the runtime, patch/capability
contracts, local CLI, verification libraries, and minimal self-host seam open;
commercial differentiation can come from hosted operations, managed
distribution, team workflows, advanced rollout/observability, support, and
enterprise integrations. This proposal does not change the repository or
license files.

## Roadmap stages

Each stage has an entry and exit gate. “Exit” means evidence exists for the
stage's claims; it does not automatically authorize the next stage. A stage
must stop if it would weaken exact release binding, high-water anti-replay,
capability v1, signed rollback, AOT fallback, or the local/offline correctness
path.

### P0 — productization foundations and maintainer review

**Purpose:** turn Phase 1D evidence into a bounded, internally consistent
design that can be reviewed before implementation.

#### P0 entry criteria

- Phase 1D review is complete with the conditional recommendation.
- Architecture B, Patch Format v1, capability v1, and state-v4 trust/high-water
  are frozen for the productization discussion.
- Existing local security, rollback, storage, and store-policy documents are
  the evidence baseline.

#### P0 work proposed

- review self-hosted progression, scale/HA/DR, roadmap, and Phase 1D condition
  disposition;
- agree the control-plane/distribution/runtime seams and data ownership;
- choose what “first public” means and what remains future;
- record security, privacy, air-gap, and store-policy gates without claiming
  that any gate has passed.

#### P0 exit criteria

- Maintainers accept a single productization design and the explicit
  implementation stop point.
- Every Phase 1D limitation has an owner, milestone, and disposition.
- The smallest first slice has testable entry/exit criteria and no dependency
  on a dashboard, billing, telemetry, KMS, or a framework fork.
- No numeric SLO/RPO/RTO target is published without a measurement plan and
  evidence.

### P1 — minimal single-tenant self-hosted control plane

**Purpose:** prove the smallest end-to-end delivery seam while retaining local
runtime authority.

#### P1 entry criteria

- P0 design is maintainer-approved and implementation is separately
  authorized.
- Runtime artifact and rollback contracts remain unchanged and are covered by
  the applicable Phase 1D gates.
- A threat-model review accepts authenticated registration/lookup,
  immutability, customer signing custody, and offline behavior.

#### P1 exit criteria

- A single-tenant self-hosted reference can register an exact release, accept
  an immutable signed Patch Format v1 artifact, return an authenticated lookup,
  and serve the artifact by digest.
- The CLI can perform an idempotent deploy/promotion and produce a basic audit
  record; the default rollout is all-or-none.
- A runtime receives a valid response, verifies the artifact itself, rejects
  tampered/wrong-release/stale input, and preserves AOT fallback during a
  service outage.
- Backup/restore and artifact digest reconciliation have been rehearsed for
  the reference profile.

P1 is the smallest implementation proposal in this package. Details are in
the section below.

### P2 — managed cloud foundation

**Purpose:** offer hosted control/distribution only after the self-hosted
interfaces and safety behavior are proven.

#### P2 entry criteria

- P1 exit evidence is complete, including service outage and restore behavior.
- Tenant isolation, authentication/token lifecycle, artifact storage,
  transport security, and privacy review are accepted for a hosted boundary.
- A measured capacity baseline exists for lookup, artifact fetch, metadata,
  and declared client/network classes.

#### P2 exit criteria

- Hosted tenancy isolates applications, environments, artifacts, audit, keys,
  observations, and billing metadata by design and test.
- Managed distribution is immutable/content-addressed, supports bounded cache
  behavior, and cannot replace runtime verification.
- Backup/DR procedures, service health, incident ownership, and measured
  service objectives are published for the selected offering.
- Customer-managed signing remains available, and managed KMS is an explicit
  opt-in boundary rather than a hidden default.

### P3 — staged rollout and privacy-preserving observability

**Purpose:** add operational control without making incomplete telemetry a
  cryptographic authority.

#### P3 entry criteria

- P2 tenant and artifact boundaries are proven.
- Event schema, sampling/opt-out, retention, redaction, and spoofing limits
  have security/privacy review.
- Rollout pause, signed rollback, store-release-required, and delivery failure
  are distinct states and actions.

#### P3 exit criteria

- Internal, canary, cohort, percentage, full, paused, and emergency-stop
  policies are modeled with deterministic app-scoped installation cohorts.
- A delivery pause prevents new eligibility without claiming to revoke code
  already accepted by the runtime.
- Optional events such as offered, downloaded, verified, activated, healthy,
  rejected, runtime fault, rollback, and base-active are bounded and sampled.
- Automation pauses conservatively on thresholds but never overrides runtime
  signature, release, capability, high-water, or health decisions.

### P4 — teams, access, audit, and approvals

**Purpose:** make collaboration and production release governance explicit.

#### P4 entry criteria

- P3 observations are known to be incomplete and the operational response is
  safe under missing data.
- Organization/team/project/application/environment ownership and tenant
  isolation are tested.
- Credential and audit threat models are reviewed.

#### P4 exit criteria

- Owner, Admin, Developer, Release Manager, Security Manager, Viewer, and
  Billing Admin roles (or a reviewed equivalent) have least-privilege
  interfaces.
- Human sessions, personal/service tokens, CI credentials, rotation, and
  revocation are attributable and bounded.
- Environment protection, two-person production approval, key-change review,
  signed CI provenance, append-only audit, export, retention, and redaction
  are implemented or explicitly scoped by offering.

### P5 — enterprise, on-prem, and air-gapped operations

**Purpose:** deliver the deployment flexibility and governance that make
self-hosting a meaningful differentiator.

#### P5 entry criteria

- P4 identity/audit controls are stable, and P1–P3 operational contracts are
  compatible with customer-operated infrastructure.
- L2/L3 container and Kubernetes packaging contracts have evidence from
  supported dependency combinations.
- HA/DR, key recovery, private networking, import/export, and store-policy
  review gates are accepted for the claimed deployment mode.

#### P5 exit criteria

- Customer can operate external PostgreSQL, object storage, optional
  Redis/Valkey, and queue adapters with documented ownership and failure
  behavior.
- Offline signed-bundle import/export verifies digests, release/environment
  binding, provenance, and policy without transporting private keys by default.
- On-prem/private distribution, audit export, retention, and customer-managed
  key boundaries are tested in a representative environment.
- The offering states its support and recovery objectives without claiming
  certification or platform-policy approval.

### P6 — framework-expansion research

**Purpose:** investigate additional runtimes only after the Flutter-first
product has a stable, framework-neutral control/distribution model.

#### P6 entry criteria

- Flutter runtime and self-hosted/managed contracts are stable and supported.
- Framework-neutral resource concepts (application, release, patch, artifact,
  rollout, installation, observation, signing) are documented without leaking
  Flutter internals.
- A separate runtime adapter proposal proves that the new framework's trust,
  release, capability, and rollback model can be explicit.

#### P6 exit criteria

- A bounded research adapter either demonstrates independent evidence or is
  rejected with the reasons recorded.
- No React Native or other framework work changes the Flutter runtime,
  Patch Format v1, capability v1, or product security assumptions.
- The expansion has its own compatibility and policy review; it is not implied
  by the existence of a framework-neutral API.

## Smallest first implementation slice — proposal only

The smallest slice that proves the architecture is a **single-tenant, local
self-hosted control/distribution path**. It should be intentionally boring and
CLI-driven:

```text
exact release registration
        -> immutable signed Patch Format v1 upload by digest
        -> authenticated update lookup for one environment
        -> artifact fetch
        -> all-or-none eligibility
        -> runtime verification/activation using existing authority
        -> basic append-only deploy audit
```

### Proposed in-scope surface

- one application, one self-hosted installation, and one explicitly named
  environment;
- release registration that records exact application/release/platform
  identity and rejects ambiguity;
- customer-managed signing outside the control-plane default;
- immutable artifact upload to a local filesystem or S3-compatible adapter,
  with digest and signature metadata;
- an authenticated, versioned lookup returning at most `NO_UPDATE`,
  `PATCH_AVAILABLE`, `UPDATE_BLOCKED`, or `STORE_RELEASE_REQUIRED` for the
  all-or-none policy;
- artifact fetch by digest with ETag/cache semantics designed but kept
  conservative;
- CLI `deploy` plus machine-readable result and basic append-only audit;
- an operator-visible health/diagnostic projection that does not pretend to
  be remote runtime introspection;
- service-outage/offline behavior that leaves the current/base runtime state
  alone.

### Explicitly out of scope for this slice

There is no dashboard, multi-tenant account model, billing, percentage or
canary scheduler, telemetry ingestion, hosted cloud, CDN, Redis/Valkey,
general-purpose queue, KMS integration, SSO/SCIM, Kubernetes chart, production
deployment, or store-submission workflow. Those belong to later stages and
require separate authorization.

### Proposed slice exit evidence

- repeated registration and deploy requests are idempotent;
- a same-identity/different-bytes upload is rejected and cannot overwrite the
  original object;
- transport, database, and artifact-store failures result in a safe degraded
  path;
- tampered, malformed, stale, wrong-release, wrong-capability, and
  wrong-environment artifacts are rejected by the runtime;
- service rollback/pause does not lower the client high-water or choose an old
  patch by metadata alone;
- backup/restore recovers metadata and matching artifact digests, or keeps
  delivery disabled;
- diagnostics expose enough request/audit context to investigate without
  exposing keys, patch bytes, absolute paths, or private data.

This slice remains a proposal until P0 is approved and implementation is
explicitly authorized.

## Design-level success measures

Later implementation should measure, without pre-baking targets:

- time from source edit to a verified deployable patch;
- patch artifact size and growth by changed declaration count;
- update lookup latency by percentile, cache state, region, and network class;
- activation and health-confirmation success rate;
- signed rollback success and time to safe base behavior;
- runtime-fault, rejection, and fallback rates, with telemetry completeness;
- managed control-plane availability and artifact recoverability;
- self-host setup, upgrade, backup, and restore time;
- CLI diagnostic usefulness and machine-readable failure stability;
- tenant-isolation and security incident count/severity.

These measures need definitions, sampling, ownership, and evidence before a
numeric objective or marketing claim is chosen. See
[`scale-ha-dr.md`](scale-ha-dr.md) for the target-setting discipline.

## Phase 1D conditions

Every Phase 1D limitation has a disposition and owner in
[`../product/phase-1d-conditions.md`](../history/product/phase-1d-conditions.md). The
roadmap must not promote a stage merely because the service-side design is
complete while a runtime evidence gate remains open.

## Store and compliance boundary

Platform policy is a separate pre-production gate. Data-driven interpreted
behavior, native code, manifests, permissions, entitlements, assets, and
compiled bundle changes require category-specific Apple/Google review. This
roadmap makes no App Store or Google Play approval claim and does not describe
any offering as compliant with GDPR, DPDP, SOC 2, ISO, or another framework.

## Risks and stop triggers

Return to maintainer review if any implementation proposal would:

- make cloud connectivity mandatory for local runtime correctness;
- let control-plane metadata replace signature, exact-release, capability, or
  high-water checks;
- lower/reset high-water to implement a convenient rollback;
- put private signing keys in the default hosted database or export bundle;
- change Patch Format v1 to carry SaaS metadata;
- hide an unresolved Phase 1D limitation behind a product label;
- abandon self-hosting after selecting it as a product requirement;
- require a Flutter/Dart fork or silently imply React Native support;
- use telemetry as the only authority for safety-critical rollout decisions.

The roadmap stops at design until maintainers review these risks.
