# Self-hosted operations architecture

Status: DESIGN WITH BOUNDED L0 IMPLEMENTATION IN PROGRESS

<!-- Wide architecture tables intentionally disable the line-length rule. -->
<!-- markdownlint-disable MD013 -->

This document owns the operational path from the current local Flutter
workflow to a customer-operated installation. It is a design proposal for
Task 40, not a deployment guide or a statement that any self-hosted mode is
ready to ship.

## Purpose and invariants

The self-hosted product must make the smallest useful operational step
possible without turning the server into a runtime authority. The topology is:

```text
Flutter project
    |
    v
Developer CLI -> release/patch compiler -> signing boundary
    |                                      |
    +-------------------------------> control plane
                                           |
                                           v
                                   distribution plane
                                           |
                                           v
                                   Flutter runtime
```

The following rules are invariant in every profile:

- Architecture B remains the client foundation: automatic source
  instrumentation, normal AOT fallback, bounded interpreted dispatch, and
  fail-closed recovery.
- Patch Format v1, capability v1, exact release binding, state-v4
  trust/high-water ownership, signed rollback, and process-local runtime
  ownership are not server extension points.
- A control plane can register metadata, select an eligible artifact, and
  return an authenticated response. It cannot bless malformed bytes, change
  a release identity, add a capability, reset a sequence high-water, or
  override the runtime's health and rollback decisions.
- An unavailable control or distribution plane must leave already-installed
  runtime state untouched. Offline behavior is a client safety property, not
  an availability promise for new updates.
- A private signing key stays with the developer, organization, offline
  signer, or explicitly selected managed KMS/HSM boundary. It is not a
  required control-plane database field.
- Local `tool status` remains a bounded developer-local projection. A future
  outbound observation stream is optional and is not a remote runtime-control
  channel.

The current local workflow is experimental and uses local artifacts plus a
development transport. Task 41 adds a separate authenticated single-node
filesystem control plane under `packages/control_plane/`; it must not be
described as a production service, store-ready delivery path, or compliance
control.

## Deployment progression

The profiles below are a progression of operational responsibility, not five
independent products. Each later profile must preserve the data and trust
contracts of the earlier one.

| Profile | Intended use | Logical shape | Customer owns | Entry condition | Exit evidence |
| --- | --- | --- | --- | --- | --- |
| L0 — local | One developer validating a supported Flutter project | Existing CLI, local release store, local signing, optional development server | Workstation, local keys, device connectivity | Phase 1D local evidence and maintainer-reviewed design | Reproducible release/patch/verify/rollback workflow with explicit limitations |
| L1 — single-node Compose | Small team or lab self-hosting one environment | Versioned application container, local or external PostgreSQL, filesystem/S3-compatible artifact store, optional cache/queue, customer TLS ingress | Host, volumes, secrets, backups, upgrades, network, signing | L0 contract frozen; reference import/export and recovery design approved | Install/upgrade/backup/restore rehearsal and an all-or-none update path on a non-production fixture |
| L2 — production containers | Customer VM fleet or container platform without Kubernetes | Stateless control-plane/distribution containers, external PostgreSQL, external object storage, ingress, optional Redis/Valkey and queue | Container runtime, dependencies, TLS, identity, capacity, backup and alerting | L1 operational evidence plus image/release compatibility policy | Repeatable image promotion, dependency failure tests, restore rehearsal, and documented ownership boundaries |
| L3 — Kubernetes | Medium/large self-hosted or managed operations | Deployments for stateless modules, external stateful services, ingress, workload identity, autoscaling policy, worker separation | Cluster, network policies, secrets/KMS, external stateful services or operators, observability, upgrade windows | L2 image contract and capacity model; HA/DR design accepted | Multi-zone failure rehearsal, controlled rollout/rollback, restore proof, and bounded error budgets |
| L4 — enterprise/on-prem and air-gapped | Regulated or disconnected customer environment | L2/L3 topology plus offline signed bundles, private distribution, customer identity and key custody | Full platform, trust roots, import/export ceremony, residency, audit retention, support evidence | L3 controls plus security/policy review and an agreed disconnected operating procedure | Repeated import, verification, distribution, backup/restore, and key-recovery exercises in the customer boundary |

L1 is the first self-hosted implementation target proposed by the roadmap. It
is not authorized by this document. L2 and L3 are packaging and operational
contracts to design after the single-node data and trust behavior is proven;
they are not instructions to create manifests, images, charts, or scripts now.

## Profile L0: current local boundary

The current local path is the baseline for everything that follows:

- the CLI builds a release from ordinary Flutter/Dart source through the
  existing build-time instrumentation path;
- the release contains its exact compatibility identity and release-owned
  capability authority;
- the developer signs locally, and the generated application contains public
  trust material rather than the private key;
- the optional local server is a development transport, not an authenticated
  multi-tenant service;
- the runtime verifies canonical bytes, signature, exact release, sequence,
  capability declarations, and resource bounds before staging or activation;
- pending health, current/last-known-good selection, base fallback, signed
  rollback, and state-v4 high-water remain inside the app-owned support
  directory.

L0 must continue to work with no hosted account, no network, and no control
plane. A later server is an adapter at the delivery seam, not a replacement
for the runtime controller.

## Profile L1: single-node Docker Compose

L1 is the smallest useful self-hosted shape. A reference installation would
package the logical application as versioned containers with a Compose-level
configuration, but the package is deliberately described without producing a
Compose file here.

### Logical services

The initial shape can keep the interface small:

1. **Control-plane module** — owns application/release/patch metadata,
   operator authentication, eligibility rules, and an append-only basic audit
   record. It does not execute patch code or accept private signing keys as a
   default.
2. **Distribution module** — serves immutable manifests and patch artifacts by
   digest, using authenticated lookup plus an artifact endpoint. It may be a
   route in the control-plane container in L1, but the interface must leave
   room for a separate edge or object-store adapter later.
3. **PostgreSQL adapter** — stores mutable metadata and transactional state
   when the selected profile uses PostgreSQL. A local database volume may be
   convenient for a lab; it is not a backup policy.
4. **Artifact-store adapter** — writes immutable release and patch objects to a
   local volume or an S3-compatible endpoint. The store is not trusted merely
   because it is on the same host.
5. **Optional cache/queue adapters** — Redis/Valkey and an asynchronous queue
   are not required for all-or-none lookup. They may be added for rate limits,
   cache acceleration, webhooks, and observation processing.

Compose should make the safe default obvious: a single tenant, one explicitly
named environment, customer-owned signing, no mandatory telemetry, and no
automatic rollout scheduler. An operator must be able to inspect which
dependencies are authoritative, optional, or unavailable before starting the
installation.

### Data and volume rules

- Database volumes contain metadata, not patch bytecode authority. The runtime
  remains authoritative for downloaded artifacts.
- Artifact objects are immutable and content-addressed. A re-upload with the
  same identity but different bytes is an integrity error, not an overwrite.
- Object-store metadata must retain content digest, application/release
  binding, platform, sequence, signing key identifier, and import provenance.
- Local files used as an artifact adapter must be isolated from database and
  application configuration volumes. A backup that includes only the database
  is incomplete.
- Secrets are injected through the host/container secret mechanism selected by
  the customer. They are not copied into images, artifacts, logs, or export
  bundles by design.
- A configuration change must not silently change tenant, application,
  environment, or trust-root identity. Changes that would do so require an
  explicit operator migration procedure in a later implementation plan.

### Compose operational contract

The reference contract should define, before implementation:

- supported container image and dependency compatibility ranges;
- required versus optional environment variables and secret inputs;
- health semantics for readiness, liveness, database access, and artifact
  access;
- an upgrade order that keeps old artifacts fetchable while metadata and
  containers change;
- backup scope for PostgreSQL, artifact objects, audit records, and trust
  metadata;
- restore verification that checks artifact digests and release bindings;
- log redaction, request IDs, and an operator-facing diagnostic projection;
- an explicit behavior when PostgreSQL, object storage, Redis/Valkey, a queue,
  or the signing boundary is unavailable.

No one-command installer, deployment script, or production Compose file is
authorized in this design phase.

## Profile L2: production containers

L2 separates the stateless application image from stateful customer services.
The intended interface is an OCI-compatible image plus documented configuration
and dependency contracts, not a bundled database that pretends to be highly
available.

The recommended shape is:

```text
customer ingress/TLS
          |
  stateless control-plane containers ---- optional workers
       |                    |                 |
       v                    v                 v
 external PostgreSQL   external object store   queue/cache
       |
 customer backup/replication and key boundary
```

The control plane can scale horizontally only after request idempotency,
transaction boundaries, artifact immutability, and worker delivery semantics
are defined. A second container does not itself provide HA.

Customer-managed TLS, private networking, egress restrictions, and secret
injection are first-class configuration concerns. The product should support
an external identity provider later, but L2 must have a narrowly scoped
bootstrap operator credential and a documented rotation path before it is
called production-capable.

## Profile L3: Kubernetes

Kubernetes is an execution target, not a substitute for a data model or DR
plan. A later design should separate these modules at the deployment seam:

- stateless API/control-plane replicas;
- artifact lookup or edge adapter where traffic warrants it;
- asynchronous worker replicas for webhooks, audit export, or observation
  processing;
- a migration/maintenance job with an explicit operator gate;
- optional cache and queue clients;
- external PostgreSQL and object storage, preferably with their own HA and
  backup guarantees;
- ingress/TLS and network-policy boundaries.

Kubernetes-specific controls should be designed only after the L2 contract is
stable. Candidate controls include pod disruption budgets, topology spread,
readiness gates, workload identity, resource requests/limits, network policy,
secret-provider integration, and a bounded autoscaling signal. None of these
controls authorizes the application to bypass runtime verification or makes a
single-zone stateful dependency highly available.

The supported deployment seam should be portable across a customer cluster,
a managed Kubernetes service, and a private cluster. Vendor-specific CRDs,
operators, and cloud load-balancer assumptions are candidates for adapters,
not part of the core protocol.

## External dependency candidates

These are candidates for adapters, not mandates or tested support claims.

| Responsibility | First design candidate | Alternatives to evaluate | What it may own | What it must never own |
| --- | --- | --- | --- | --- |
| System-of-record metadata | Customer-managed PostgreSQL | Managed PostgreSQL from a cloud provider; PostgreSQL HA distribution/operator for on-prem | Tenancy, release/patch metadata, rollout policy, audit metadata, idempotency keys | Patch execution, runtime health authority, signed-byte validity, client high-water |
| Immutable artifacts | S3-compatible object storage | AWS S3, MinIO, Ceph RGW, a private object gateway, or a native cloud blob adapter | Release manifests, patch artifacts, signatures, optional debug/source-map bundles, export bundles | Trust decisions, mutable replacement of a digest, runtime activation |
| Cache/rate limiting | Redis or Valkey | Managed Redis/Valkey, a local bounded cache, database-backed rate limiting for small installs | Read acceleration, short-lived rate limits, cohort lookup cache, leases where loss is safe | Durable rollout truth, signing state, audit history, sequence high-water |
| Asynchronous work | Transactional PostgreSQL outbox plus worker | Redis Streams/Valkey Streams, NATS JetStream, RabbitMQ, SQS/Pub/Sub/Service Bus adapters | Webhooks, audit export, optional telemetry aggregation, retryable housekeeping | The only copy of a release decision, artifact bytes, or a safety-critical rollback command |
| Key custody | Customer offline key or organization HSM/KMS | AWS KMS, Google Cloud KMS, Azure Key Vault, HashiCorp Vault, customer HSM, air-gapped signer | Signing operations, key policy, rotation/revocation ceremony, audit at the key boundary | Automatic authority to approve incompatible artifacts or alter client state |

The first slice should prefer PostgreSQL plus a local filesystem or one
S3-compatible artifact adapter and omit Redis and a queue. This keeps the
initial seam deep: registration, immutable storage, authenticated lookup, and
runtime verification can be tested without making cache or worker failure part
of correctness. A PostgreSQL outbox is a later option when asynchronous work
is added; it should not be confused with a general-purpose queue commitment.

## Air-gapped and disconnected operation

Air-gapped support is feasible only for release and distribution workflows
that can operate without cloud access. It does not mean a disconnected
runtime can receive a new patch without an operator moving an artifact into a
private distribution boundary.

### Offline release and import flow

```text
connected or offline build workspace
        |
        | build and verify exact release-bound Patch Format v1 artifact
        v
offline/customer signing boundary
        |
        | export signed bundle + digest manifest + provenance
        v
controlled transfer media / approved exchange
        |
        | scan, authenticate, verify, quarantine, import
        v
air-gapped control plane + private artifact distribution
        |
        v
customer Flutter runtime
```

An export bundle is a transport envelope around existing artifacts; it is not
a replacement for Patch Format v1. It may contain:

- application, environment, and exact release identifiers;
- immutable release manifest and platform compatibility metadata;
- signed Patch Format v1 artifacts and their SHA-256 digests;
- signed rollback-control material only when the customer explicitly requests
  it and the target high-water is bound;
- import provenance, source/build fingerprint, creation time, and an
  operator-selected expiry;
- optional non-secret audit or source-map/debug objects, clearly separated
  from runtime delivery.

It must not contain private signing keys, unrelated tenant data, live tokens,
absolute checkout paths, or an implicit trust-root change. Import must verify
the outer bundle integrity, inner artifact digest, signature, exact target
application/release/environment, supported protocol versions, and local
policy before making the artifact eligible. A failed import remains
quarantined and cannot become a candidate merely because the bundle is signed.

For a disconnected target, the operator can choose one of two designs:

1. **Customer-managed signing:** build and sign inside the disconnected
   boundary, then register/import the artifact locally. This is the preferred
   air-gap path because the private key never crosses the gap.
2. **Pre-signed transfer:** sign in an approved connected or offline signing
   enclave, transfer only the signed artifact bundle, and verify it again at
   import. The target still treats the source and transport as untrusted.

Runtime observations, if enabled, are exported as a separate, opt-in bundle.
They are not required for activation, health confirmation, rollback, or base
fallback. Export must support redaction and customer retention policy; no
telemetry is silently sent across an air gap.

### Private distribution

The air-gapped endpoint can be a private HTTP service, an internal reverse
proxy, or a customer CDN/object gateway. The runtime should use the same
versioned delivery interface as connected deployments, with transport failure
treated as no update. Caches may return stale metadata, but an artifact that
fails runtime verification is never accepted. The distribution endpoint cannot
manufacture a rollback or lower a client high-water.

### Transfer and recovery ceremony

The implementation design must eventually specify two-person review or an
equivalent control for production imports, a tamper-evident import record,
quarantine and deletion rules, digest comparison before/after transfer, and a
restore rehearsal that does not require access to the connected service.
Those are design gates, not implemented air-gap controls.

## Upgrades, backups, and operational ownership

Every profile must make ownership visible:

| Concern | Local | Self-hosted customer | Managed service (future) |
| --- | --- | --- | --- |
| Signing key | Developer | Customer organization/offline signer/KMS | Customer key or explicitly selected managed KMS |
| Control-plane data | Local files | Customer PostgreSQL/backup | Provider-operated database with customer export |
| Artifact durability | Local release store | Customer object store/backup | Provider object store/replication |
| TLS/identity | Development transport | Customer ingress/identity | Provider edge plus customer auth policy |
| Runtime correctness | Flutter runtime | Flutter runtime | Flutter runtime |
| Recovery ceremony | Developer command | Customer operator/runbook | Provider operations plus customer rollback authority |

An upgrade must preserve old immutable artifacts until every supported runtime
and rollback window no longer needs them. The control plane should reject a
partial upgrade rather than serve metadata it cannot resolve to an artifact.
Database schema evolution, if later implemented, must use a reversible,
versioned migration plan with a backup checkpoint; this document proposes no
migrations.

Backups should cover PostgreSQL metadata, object artifacts, audit records,
trust metadata, and the configuration needed to resolve external endpoints.
Restoring the database without the matching artifact objects is an incomplete
restore. Restoring object bytes without their recorded digests and release
bindings is also incomplete. See
[`scale-ha-dr.md`](scale-ha-dr.md) for failure-domain and recovery objectives.

## Security and non-goals

Self-hosting increases customer control and customer responsibility. The
design must address tenant isolation, token theft, malicious operators,
artifact replacement, import tampering, SSRF, secret leakage, dependency
compromise, and misconfigured network access before a public production claim.
The runtime remains the last safety boundary even when every server is
customer-operated.

This document does not implement or authorize:

- deployment scripts, Dockerfiles, Compose files, Helm charts, operators, or
  infrastructure-as-code;
- a backend, REST server, database schema, migrations, dashboard, accounts,
  billing, KMS integration, telemetry ingestion, rollout scheduler, or CDN;
- enterprise SSO, React Native support, store submission, or compliance
  certification;
- any claim that a self-hosted or air-gapped installation is production-ready,
  App Store/Google Play approved, GDPR/DPDP/SOC 2/ISO compliant, or secure
  against a rooted or fully compromised device.

## Design gates before implementation

Maintainer approval is required before implementation begins. At minimum, the
review must accept:

1. the L0-to-L4 progression and which profile is in the first release;
2. the storage and queue ownership model, including what can be unavailable
   without changing runtime safety;
3. artifact immutability, import verification, and customer signing custody;
4. backup/restore and HA/DR objectives in
   [`scale-ha-dr.md`](scale-ha-dr.md);
5. the Phase 1D limitation dispositions in
   [`../product/phase-1d-conditions.md`](../history/product/phase-1d-conditions.md);
6. the staged roadmap and smallest first slice in
   [`product-roadmap.md`](product-roadmap.md).

Until then this is an architecture proposal only.

## P2 hosted-like reference (2026-08-23)

The bounded reference implementation is now available under
[`deploy/p2/`](../../deploy/p2): a non-root Dart control-plane container,
PostgreSQL, MinIO, Compose health dependencies, and an example TLS reverse
proxy boundary. Configuration is injected through environment variables; no
database password, object-store secret, control token, delivery token, or
private signing key is committed. `scripts/p2-postgres-backup.sh` and
`scripts/p2-postgres-restore.sh` provide explicit operator backup/restore
commands and require an opt-in restore flag.

The reference has been exercised as `END_TO_END_HOSTED_LIKE` and is not a
production deployment. It has no HA, Kubernetes, managed key custody,
dashboard, runtime telemetry, rollout service, or automatic object
replication. The customer/local signing boundary and runtime-authoritative
verification remain unchanged.
