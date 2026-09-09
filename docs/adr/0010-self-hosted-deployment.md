# ADR 0010: staged self-hosted deployment boundary

Status: Proposed — design only; maintainer review required

<!-- Wide decision tables disable MD013. -->
<!-- markdownlint-disable MD013 -->

Date: 2026-08-23

This ADR is a proposal for the Task 40 productization design. It does not
authorize implementation, deployment, or a production readiness claim.

## Context

The current Hyfens workflow is local and experimental. The CLI builds a
release from ordinary Flutter/Dart source, signs and verifies Patch Format v1
artifacts, and uses a local development transport. The Flutter runtime remains
the authority for exact release binding, capability v1, state-v4
trust/high-water, signed rollback, pending health, and fail-closed recovery.

Task 40 needs a credible path to open-source/self-hosted and, later, managed
operation. The path must cover a single workstation, a small customer host,
production containers, Kubernetes, and disconnected/on-prem environments
without forcing cloud connectivity or private-key custody into the runtime.

Phase 1D explicitly allows design only. It did not validate a production
server, transport authentication, KMS/HSM custody, multi-tenant isolation,
service capacity, deployment automation, or store-policy approval.

## Decision proposed

Adopt a **local-first, self-hosted-first, staged deployment boundary**:

1. retain the current local mode as a complete, offline-capable developer
   workflow;
2. define a single-tenant Docker Compose reference as the first self-hosted
   implementation profile;
3. define production-container and Kubernetes contracts only after the
   single-node data, trust, upgrade, and restore behavior is proven;
4. design managed cloud, team, enterprise, and air-gapped offerings as later
   roadmap stages rather than prerequisites for the local path;
5. keep the control plane and distribution plane behind explicit interfaces so
   they can be self-hosted, hosted, or privately operated without changing the
   runtime protocol;
6. keep customer-managed signing as the default self-hosted and air-gapped
   posture, with managed KMS/HSM as an explicit later choice;
7. treat all service and storage dependencies as untrusted for artifact
   execution. The runtime must independently verify every candidate.

The progression is:

```text
local CLI/development transport
        -> single-node Docker Compose
        -> production OCI containers + external state
        -> Kubernetes/private cluster
        -> enterprise/on-prem/air-gapped profile
        -> managed service where separately authorized
```

The full operational profiles, responsibility boundaries, and external
dependency candidates are in
[`../architecture/self-hosted-operations.md`](../architecture/self-hosted-operations.md).

## Proposed architecture boundary

```text
developer CLI
   |
   v
release/patch compiler ---- customer/offline/KMS signing boundary
   |
   v
control plane ---- PostgreSQL metadata / audit
   |
   v
distribution plane ---- immutable object storage / private edge
   |
   v
Flutter runtime ---- signature, release, capability, high-water, health, AOT
```

### Control plane

The control plane may own applications, environments, release and patch
metadata, rollout policy, import provenance, audit records, and authenticated
operator/CI access. It may select an eligible artifact for delivery. It may
not execute patch code, change signed bytes, add a capability, reset a client
high-water, or turn a stale/wrong-release candidate into a valid one.

The first implementation seam should be a deep interface consisting of exact
release registration, immutable artifact registration, authenticated lookup,
artifact fetch by digest, an all-or-none eligibility policy, and an
append-only deploy audit record. Dashboard, billing, percentage rollout,
telemetry ingestion, and enterprise identity are not part of this ADR's first
slice.

### Distribution plane

The distribution plane may be a route in a small self-hosted process, a
separate service, an object-store adapter, a customer CDN/private edge, or a
managed edge in a later offering. It must expose versioned lookup and
digest-addressed artifact fetch semantics with conservative retries, cache
validation, and `NO_UPDATE`/error behavior.

Transport authentication improves accountability and privacy, but transport
trust never replaces artifact signature, exact-release, capability, sequence,
or resource validation at the runtime.

### Persistence candidates

- PostgreSQL is the primary candidate for tenancy, application/release/patch
  metadata, rollout state, idempotency, and audit metadata. It is a system of
  record, not runtime execution authority.
- S3-compatible object storage is the primary artifact candidate. AWS S3,
  MinIO, Ceph RGW, or a native cloud/private object adapter may be evaluated.
  Objects are immutable and content-addressed; a conflicting re-upload is an
  error.
- Redis or Valkey is optional for cache acceleration, rate limiting, cohort
  lookup, or safe leases. It must never hold the only copy of trust, rollout,
  audit, artifact, or high-water state.
- A PostgreSQL outbox is the smallest asynchronous-work candidate. Redis
  Streams/Valkey Streams, NATS JetStream, RabbitMQ, and managed queue adapters
  are later candidates for webhooks, exports, and observation processing. A
  queue is not the sole authority for a release decision.

The initial self-hosted slice should use PostgreSQL plus a local or
S3-compatible artifact adapter and omit Redis/Valkey and a general-purpose
queue. This is a proposed scope, not a selected vendor or implementation.

## Deployment profiles and responsibility

| Profile | Proposed use | State placement | Main operator |
| --- | --- | --- | --- |
| Local | Developer experimentation and supported fixture workflows | Existing local release store and app-owned runtime state | Developer |
| Single-node Compose | Small team/lab self-hosting | PostgreSQL plus local/object artifact storage, with explicit host backups | Customer operator |
| Production containers | Customer VM/container platform | External PostgreSQL and object storage; optional cache/outbox | Customer platform team |
| Kubernetes | Medium/large or private cluster | Stateless replicas and workers; external/operated stateful dependencies | Customer platform/SRE team |
| Air-gapped/on-prem | Disconnected or private enterprise boundary | Customer-local state plus signed import/export bundles and private distribution | Customer security/platform team |
| Managed cloud (later) | Provider-operated control/distribution | Provider-operated state with customer export and key choice | Provider plus customer release owner |

Replicating a stateless container is not by itself HA. Each profile must state
backup scope, artifact durability, key custody, TLS/identity ownership,
upgrade ordering, and degraded behavior. The HA/DR design is in
[`../architecture/scale-ha-dr.md`](../architecture/scale-ha-dr.md).

## Air-gapped import/export

Air-gapped operation uses a signed transport envelope around existing
artifacts, not a new runtime format. A future export may contain exact
application/environment/release identifiers, signed Patch Format v1 artifacts,
digest manifests, provenance, optional audit/debug objects, and an explicit
expiry or import policy. It must not contain private keys, unrelated tenant
data, live tokens, or an implicit trust-root change.

Import must authenticate and quarantine the outer bundle, verify each inner
digest/signature/release/environment binding, apply local policy, and record
provenance before making an artifact eligible. The preferred disconnected
mode signs inside the customer boundary; pre-signed transfer is possible only
with re-verification at the destination. Optional observations are exported
separately and are never required for activation or rollback.

## Consequences

### Positive

- Developers retain a useful local workflow without accounts or network
  availability.
- Self-hosting is a real product path rather than a promise that appears after
  a hosted service is built.
- Customer-controlled PostgreSQL, object storage, TLS, identity, and signing
  fit on-prem and air-gapped requirements.
- The runtime has one trust authority across local, self-hosted, private, and
  future hosted delivery adapters.
- Optional cache and queue dependencies can be added for scale without making
  their failure a safety failure.
- A small first slice can prove registration, immutable upload, lookup, fetch,
  audit, and runtime verification before dashboards or rollout automation.

### Costs and risks

- The project must document and support multiple dependency combinations,
  backup/restore procedures, and customer upgrade responsibility.
- A self-hosted reference can be secure in design but still be misconfigured
  by an operator; threat-model and diagnostic quality matter as much as
  packaging.
- External PostgreSQL/object storage availability and restore semantics must
  be tested together; restoring only one creates an unsafe partial service.
- Air-gap import ceremonies, key recovery, and private distribution add
  operational friction that cannot be hidden behind a hosted UI.
- Multi-region HA, managed KMS, SSO/SCIM, audit retention, and SLOs should not
  be implied by Compose support.
- Store-policy classification for downloaded interpreted behavior remains an
  external gate. This ADR makes no Apple/Google approval claim.

## Alternatives considered

### Local-only

This preserves the smallest maintenance surface but fails the Task 40
self-hosting and deployment-flexibility requirement. It remains the baseline
mode, not the complete product direction.

### Compose-only forever

This is approachable for small teams but makes external state, HA, backup,
enterprise networking, and disconnected operation implicit or inadequate. It
is the first reference profile, not the long-term boundary.

### Kubernetes-first

This would optimize for later scale before proving the data/trust contract and
would impose a cluster on small self-hosted users. Kubernetes remains a later
execution adapter after the container/dependency interface is stable.

### Hosted-only

This could centralize operations but contradicts the self-hosted and air-gap
requirements, increases dependence on provider trust, and makes local
connectivity a product prerequisite. It is rejected as the foundation.

### Server-authoritative patch trust

This would simplify lookup but violate the runtime safety model. It is
rejected: servers and object stores are untrusted delivery mechanisms, and the
Flutter runtime remains the final authority.

## Validation and decision gates

Before this ADR is accepted, maintainers should review:

1. the five-file operations package and its Phase 1D dispositions;
2. exact release, signature, capability, high-water, rollback, and AOT
   fallback invariants;
3. the proposed P1 smallest slice and its explicit non-goals;
4. external dependency ownership, air-gap import/export, and failure behavior;
5. scale/HA/DR assumptions and the rule against fabricated SLO/RPO/RTO
   targets;
6. security, privacy, and store-policy gates, with no compliance claim.

Implementation must not start until the design gate is separately approved.
When implementation is later authorized, the first validation should cover
idempotent registration/deploy, digest immutability, authenticated lookup,
transport/service outage, artifact tampering, wrong-release/stale rejection,
backup/restore reconciliation, and signed rollback without lowering
high-water.

## Scope stop

This ADR does not create deployment scripts, containers, Kubernetes resources,
backend code, REST endpoints, migrations, a dashboard, accounts, billing,
CDN/KMS/telemetry integrations, rollout automation, enterprise SSO, React
Native support, production infrastructure, store submission, or compliance
certification. It is a proposed design decision for maintainer review only.

## Task 76 provider-deployment design addendum (2026-08-25)

Task 76 expands the staged self-hosting boundary into a provider-neutral
deployment design. It compares managed containers, Kubernetes/container
orchestration, and VM/container service profiles while preserving PostgreSQL
coordination, immutable object bytes, customer/local signing, runtime
verification, bounded reconciliation, and exact tenant/audit authority.

No provider, region, IaC tool, managed service, current price envelope, or
implementation profile is selected by this addendum. Provider-specific
failover, edge/TLS, supply-chain, capacity, soak, power-loss, independent-app,
iOS, beta, production, store, privacy, and legal gates remain open. See
`docs/PROVIDER_DEPLOYMENT_DESIGN_REVIEW.md` and Task 76. This remains design
only and does not authorize provider resources or deployment.
