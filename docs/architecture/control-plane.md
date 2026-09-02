# Control-plane architecture

Status: `APPROVED DESIGN — BOUNDED LOCAL IMPLEMENTATION IN PROGRESS`

<!-- Evidence tables and diagrams intentionally disable the line-length rule. -->
<!-- markdownlint-disable MD013 -->

The control plane is the product module that turns immutable, locally verified
Flutter release and patch artifacts into tenant-scoped delivery decisions. It
does not execute patch code, replace the runtime trust boundary, or imply a
hosted service exists today. The first implementation is the standard-library
single-node package in [`packages/control_plane`](../../packages/control_plane/)
and intentionally covers only the bounded Task 41 local slice.

## 1. Topology and responsibility

```text
Developer / CI
      │
      ▼
CLI ── local compiler/instrumenter ── local or managed signing boundary
      │                         │
      │ exact release/patch     │ signed Patch Format v1 bytes
      ▼                         ▼
                 Control plane ───────────────► Distribution plane
                 catalog, policy,              immutable artifacts,
                 authorization, rollout,      manifests, CDN/HTTP
                 audit, observations                  │
                                                       ▼
                                              Flutter runtime
                                      verify → stage → health → activate
                                      or AOT/fail-closed recovery
```

The seams are deliberately narrow:

| Module/interface | Owns | Must not own |
| --- | --- | --- |
| CLI/build interface | Source discovery, release baseline, patch compilation, local verification, machine-readable commands | Hosted authorization or a different patch protocol |
| Signing interface | Developer, organization, offline, or managed-provider signing choice | Making an unsigned or wrongly bound artifact valid |
| Control-plane domain interface | Tenant ownership, resource lifecycle, RBAC, policy, registration, rollout eligibility, audit, and observation intake | Executing a patch or selecting executable runtime state |
| Distribution interface | Authenticated lookup, immutable byte delivery, content digest, caching, and import/export transport | Trusting CDN/HTTP headers or changing artifact bytes |
| Runtime delivery interface | One bounded update/control decision from app/release/platform/high-water context | Lowering high-water, adding capabilities, or bypassing signature/release checks |
| Observation interface | Optional, redacted event intake and aggregation | Declaring a patch healthy or repairing runtime state |

The runtime-delivery interface is a deep module: a caller supplies a small,
versioned set of exact identities, platform, environment, installation
pseudonym, and high-water; rollout, policy, cohort, revocation, and filtering
complexity remain behind that interface. The interface returns a decision and
immutable references, not executable authority. Storage, queue, CDN, and KMS
implementations are adapters at these seams and can vary between local,
self-hosted, and managed deployments.

## 2. Control-plane responsibilities

The control plane is authoritative for product metadata and administrative
intent:

- Organization membership, Teams, Projects, Applications, Platforms, and
  Environments;
- immutable Release registration and exact baseline metadata;
- Patch and PatchArtifact catalog state, digest inventory, and optional
  source-map/debug artifact references;
- public SigningKey metadata, TrustPolicy, EnvironmentPolicy, approval and
  revocation intent;
- Rollout and Cohort definitions, target percentages, pause/stop decisions,
  and delivery eligibility;
- API tokens, ServiceAccounts, Webhooks, request/audit records, and bounded
  Diagnostics;
- optional RuntimeObservation intake, aggregation, retention, and safety
  signals; and
- the versioned API contract described in
  [`product-api-domain.md`](../spec/product-api-domain.md).

The control plane is not authoritative for whether a process is currently
executing a patch. `RuntimeObservation` is evidence that may be delayed,
sampled, missing, duplicated, or spoofed. It cannot be used to rewrite
state-v4, clear a high-water, mark a candidate healthy, or select a patch.

## 3. Release and patch registration

### Release registration

The CLI or CI first creates a Release record containing the exact target
identity and baseline facts:

- immutable `runtimeApplicationId` and `runtimeReleaseId`;
- Application and Platform ownership;
- explicit build target, runtime compatibility version, and Patch Format
  version (`1` for the current protocol);
- normalized source/dependency/build-graph fingerprint and a release
  fingerprint;
- sorted function/signature compatibility digest;
- immutable release-owned capability-authority digest; and
- registered public key IDs or managed signing references needed for later
  verification.

The server may validate the record and compare it with a supplied signed
artifact, but it cannot normalize a mismatch away. Environment names,
rollout labels, tenant IDs, source-control URLs, notes, and display versions
are product metadata outside the runtime release identity. A Release becomes
`READY` only after all required target and trust checks pass.

An Environment points at an eligible store Release through an audited
promotion operation. That relationship is not encoded in a Patch Format v1
artifact. Promoting the same exact Release into another Environment changes
delivery policy, not the release bytes.

### Patch registration

A Patch is a product record for one exact Release and sequence. Its runtime
identity, sequence, artifact digest, size, target, and signing key metadata
are immutable once `SIGNED` or later. Its title, notes, source revision,
rollout labels, and environment assignments are SaaS metadata.

The runtime artifact is the canonical Patch Format v1 byte sequence. The
control plane may store a separate JSON delivery manifest and may attach
HTTP metadata or an expiring URL, but it must not prepend, append, wrap, or
rewrite the v1 bytes. If a future protocol needs signed SaaS metadata inside
the bytes, that is a new explicit format-version decision; it is not a
server-side extension to v1.

## 4. Authority matrix

| Decision | Control plane | Distribution plane | Runtime |
| --- | --- | --- | --- |
| Tenant owns Application/Environment | Authoritative | No knowledge beyond scoped request | No authority |
| Patch is registered/eligible | Authoritative product decision | Serves only authorized references | Treats as untrusted input |
| Artifact bytes and digest | Records/compares exact digest | Stores and returns immutable bytes | Recomputes and verifies digest |
| Signature/key policy | Catalogs public keys, lifecycle intent, and policy | Does not verify trust for execution | Verifies signature and release-owned trust state |
| Exact release/runtime compatibility | Filters obvious mismatches | Does not decide | Final mandatory check |
| Capability authority | Records release digest/policy metadata | Cannot add a capability | Immutable release-owned authority; patch declarations are checked |
| Sequence/high-water | Uses client/observation values only to filter conservatively | No authority | State-v4 controller is sole activation authority |
| Health/current/fallback | Observes events and displays them | No authority | `markHealthy`, AOT fallback, LKG, rollback, and `FAILED` recovery |
| Rollout percentage/cohort | Authoritative eligibility intent | Enforces only delivery routing | May accept/reject bytes independently |

## 5. Product state versus runtime state

The product state machines are intentionally not projections of runtime state.
They can be correlated by observations but never substituted for it.

### Release

```text
DRAFT → REGISTERED → VERIFIED → READY → DEPRECATED
                         └──────→ FAILED
READY ───────────────────────────→ REVOKED
```

`READY` means the control plane has accepted the immutable release metadata
and required verification evidence for product use. It does not mean any
installation has loaded it or that a store release is installed everywhere.

### Patch

```text
DRAFT → BUILT → SIGNED → VERIFIED → READY → ROLLOUT_PENDING → ACTIVE
                                      │                         ├→ COMPLETED
                                      │                         ├→ PAUSED
                                      │                         ├→ SUPERSEDED
                                      │                         ├→ REVOKED
                                      │                         ├→ ROLLED_BACK
                                      │                         └→ FAILED
```

`ACTIVE` means at least one delivery policy may offer the Patch. It does not
mean a runtime has marked it healthy. `ROLLED_BACK` records a product
decision/outcome; the runtime may be in `BASE`, may retain a last-known-good
reference, or may require fail-closed recovery.

### Rollout

```text
DRAFT → SCHEDULED → RUNNING → PAUSED → RUNNING
                            ├→ COMPLETED
                            ├→ CANCELLED
                            ├→ EMERGENCY_STOPPED
                            └→ FAILED
```

Pause and emergency stop withhold delivery. They do not revoke a signature,
lower a sequence, or select an older Patch. A signed rollback-control
operation is a separate, release-bound product action and must still pass the
runtime's exact high-water check.

### Runtime

The installed runtime remains the E1 controller's state-v4 authority:

- `BASE`: compiled AOT only, with authenticated high-water retained;
- `CANDIDATE`: an exact verified artifact is durable and pending explicit
  health confirmation;
- `CURRENT`: the exact pending artifact was health-confirmed;
- `FAILED`: durable trust/replay state or recovery cannot be safely selected.

`lastKnownGood` is a remembered healthy artifact reference; `health=pending`
and `health=healthy` qualify the current record. A server cannot manufacture a
runtime transition by changing a product state or observation.

## 6. Frozen runtime invariants

Productization must preserve all of the following:

### Exact release binding

Patch Format v1 identity binds `applicationId`, `releaseId`, `patchId`, and
positive `sequence`. The release baseline binds runtime and format
compatibility, explicit build target, function identity/signature records, and
the release-owned capability-authority digest. A package name, dependency
version, label, environment, or source-control branch is not a substitute.
The control plane must reject a wrong Application/Release/Platform and the
runtime must independently reject it again.

### Signature and key lifecycle

Patch Format v1 uses the canonical unsigned payload, SHA-256 payload digest,
signature metadata, and the exact algorithm-specific signature input. The
unsigned payload is the exact header and canonical known sections 1–6 plus
sorted unknown non-critical extensions, with digest and signature sections
omitted. The digest is SHA-256 over those bytes; the signature covers that
same canonical header/payload plus section 7, with the signature section
omitted. Phase 1A uses `ed25519` and the signing package's 32-byte protocol
key ID encoding; unknown algorithms are rejected. Private keys are never
embedded in an artifact or application. The runtime verifies bounded
framing, canonical bytes, digest, and signature before trusting decoded patch
data.

The release-owned state-v4 trust journal remains authoritative for active,
retired, revoked, authority, rollback, and recovery roles. Rotation is an
overlap of an added key followed by retirement; retirement may preserve exact
remembered artifacts, while revocation rejects even retained artifacts. A
downloaded key cannot self-authorize, and managed KMS/HSM metadata cannot
replace the release-bound runtime trust state.

### Capability authority

Capabilities are release-owned contracts, not reflective names. Every patch
declares a sorted, unique stable ID, positive version, execution kind,
security class, permission labels, and canonical argument/return schema it
needs. A runtime rejects missing IDs, version/schema/execution-kind/security
mismatches, duplicate or forbidden declarations, and denied policy. A data
Patch cannot add native code, a host adapter, or a new capability; a
native-boundary change requires a new store Release.

The control plane may filter a Patch whose declared capability digest is not
registered for the target Release, but it cannot grant a capability and it
must not treat its own catalog as the runtime registry.

### High-water and rollback

The controller-owned high-water `(sequence, digest)` is monotonic across
activation, cleanup, recovery, and signed base rollback. A lower sequence is
stale; an equal sequence with a different digest is equivocation; an equal
digest is idempotent only when it remains the durable current target. After a
base rollback, an old Patch cannot become current again. Restoring old
behavior requires a newly signed artifact above the retained high-water.

The control plane may use a client-supplied or observed high-water to avoid
offering obviously stale data, but it never treats an observation as an
authority and never asks the runtime to reset or lower its high-water.

## 7. Signing and trust deployment modes

| Mode | Private-key custody | Control-plane role | Runtime requirement |
| --- | --- | --- | --- |
| Developer-managed | Local workstation or CI secret manager | Register public key and verify metadata | Release embeds/initializes the corresponding trust anchor |
| Organization-managed | Customer-controlled CI/KMS/HSM | Store provider reference and approval/audit metadata | Same release-bound public-key and lifecycle checks |
| Managed signing | Explicit opt-in provider/HSM boundary | Submit a digest/bytes for signing; never expose private key material | Artifact still carries v1 signature metadata and passes runtime checks |
| Offline/self-hosted | Offline signer and export/import bundle | Validate manifest, digest, signature, and import provenance | Private/offline trust state remains release-owned |
| Air-gapped | Customer signer and private distribution | No mandatory cloud dependency; import/export is revalidated | Runtime accepts only exact signed, release-compatible bytes |

The hosted control plane must not silently become a key escrow service. If
managed signing is offered, it is a distinct, explicitly authorized boundary
with provider isolation, key-use audit, rotation/recovery procedures, and no
API response containing private key material.

## 8. Rollout and delivery evaluation

The delivery evaluator takes:

```text
application/runtimeApplicationId
environment
platform/build target
runtimeReleaseId and runtime compatibility
client high-water (sequence, digest)
installation pseudonym
optional client capability/version facts
```

It returns exactly one product decision such as `NO_UPDATE`,
`PATCH_AVAILABLE`, `ROLLBACK_CONTROL`, `UPDATE_BLOCKED`, or
`STORE_RELEASE_REQUIRED`, plus immutable references and cache metadata. It
does not return an instruction to skip signature verification or to install a
specific old Patch.

Filtering order is:

1. authenticate the delivery request and establish one Application/
   Environment tenant context;
2. verify the requested platform, exact runtime release, and environment
   relationship;
3. apply EnvironmentPolicy, TrustPolicy, release/Patch product state, and
   rollout/cohort eligibility;
4. exclude revoked, superseded, incompatible, and sequence-not-above-
   high-water candidates;
5. return only the newest eligible exact artifact, or a safe no-update/block
   decision.

The server never uses IMEI, advertising ID, hardware serial, phone number, or
account email to assign a Cohort. It hashes a random app-scoped Installation
ID with a versioned app/rollout scope. A rollout changes delivery eligibility,
not cryptographic validity.

An offline or rate-limited client continues with its compiled AOT code or
already installed runtime state. Telemetry is optional and must never be a
precondition for correctness.

## 9. Distribution and data responsibilities

The design permits these deployment adapters without changing the domain
interface:

- relational storage for tenant/catalog/auth/policy/rollout/audit metadata;
- immutable object storage for runtime artifacts, signed controls, and
  optional debug/source-map bundles;
- cache or Redis/Valkey for scoped lookup acceleration and rate limits; and
- a queue for webhooks, observation aggregation, and non-critical processing.

Every adapter receives tenant context explicitly. Artifact storage is
content-addressed and immutable; deletion is a retention operation, never a
way to erase replay metadata. The distribution plane may use object storage,
CDN, authenticated HTTP, private enterprise endpoints, or air-gapped import.
Its response headers, URL, cache, and transport are untrusted by the runtime.

## 10. Observations, diagnostics, and operational safety

The runtime may emit bounded events such as `release_seen`,
`patch_offered`, `patch_downloaded`, `patch_verified`, `patch_activated`,
`patch_healthy`, `patch_rejected`, `runtime_fault`, `rollback_applied`, and
`base_active`. Events are sampled/optional, redact absolute paths and secrets,
and carry a client event ID for deduplication.

The control plane may pause a Rollout when fault/rejection/health signals
cross a configured threshold, but the signal is incomplete and non-authoritative:

- automation can withhold future delivery;
- it cannot alter installed state, lower high-water, or revoke a valid runtime
  signature by policy alone;
- a signed rollback-control command remains separately authenticated and
  release/high-water bound; and
- all automated pauses and operator overrides create AuditEvents.

`tool status` remains a developer-local toolchain surface. The hosted control
plane does not assume unauthenticated remote introspection of a running app.

## 11. Self-hosted and managed shape

The same domain interface supports a progression:

1. local/single-tenant self-hosted mode with a relational store and local
   filesystem/object adapter;
2. production self-hosted containers with external PostgreSQL,
   S3-compatible storage, optional Redis/Valkey, customer TLS, and customer
   signing; and
3. managed cloud with isolated tenant controls, managed distribution, and an
   explicitly selected managed KMS/HSM adapter.

Air-gapped operation uses offline release registration, local build/sign,
export of an immutable manifest/artifact bundle, import-time revalidation,
and private HTTP/object distribution. Cloud availability is never required
for an already installed runtime to remain safe.

## 12. Design stop conditions

Maintainer review is required before implementation if a design proposal
would:

- change Patch Format v1 or capability v1 to carry SaaS metadata;
- make the server or CDN replace runtime signature/release/high-water checks;
- lower/reset high-water for rollback, cleanup, recovery, or rollout;
- make cloud connectivity mandatory for local/runtime correctness;
- permit a downloaded key or product policy to self-authorize runtime trust;
- require customer private keys to traverse the hosted control plane without
  an explicit managed-signing decision; or
- turn incomplete observations into claims of runtime health or activation.

## 13. Hosted-like control-plane foundation (implemented, not production)

The historical internal “P2” label referred to this hosted-like foundation; it
is not the public API version or URL path. The bounded hosted-like adapter
keeps the same authority split while replacing only
the persistence and artifact adapters:

```text
tool deploy
    │ exact locally verified Patch Format v1 bytes
    ▼
dart:io control plane ── PostgreSQL metadata/migrations
    │                    └─ tenant-scoped immutable records,
    │                       idempotency, promotion, audit hash chain
    └─ S3-compatible object store ── digest-addressed exact bytes
                 │
                 ▼
        read-only runtime delivery
                 │
                 ▼
        E1 re-verification and state-v4 activation
```

`PostgresControlPlaneStore` and `S3CompatibleArtifactStore` implement the
existing interfaces; the filesystem adapter remains available for local and
self-hosted use. The hosted-like Compose stack is deliberately a bounded
single-node reference with PostgreSQL, MinIO, and one non-root Dart process.
It is not HA, internet-scale capacity, or production hardening evidence.

The service exposes liveness (`/healthz`), dependency/migration readiness
(`/readyz`), and process-local aggregate operator metrics (`/metrics`). The
metrics endpoint reports request counts, status classes, update decisions, and
duration totals/maxima only. It is not runtime telemetry and cannot alter
delivery or runtime state. TLS termination and trusted-proxy behavior remain
an ingress responsibility documented in `deploy/p2/nginx.conf.example`.
