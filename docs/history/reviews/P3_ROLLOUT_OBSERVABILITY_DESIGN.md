# P3 Rollout & Observability design

Status: `P3A/P3D BOUNDED IMPLEMENTATION AUTHORIZED — P3E/P3F/P3G NOT AUTHORIZED`

Date: 2026-08-23

<!-- This design contains intentionally wide state/evidence tables. -->
<!-- markdownlint-disable MD013 -->

## 1. Purpose

P3 is a future Rollout & Observability phase for already-valid signed Patch
Format v1 artifacts. Its purpose is to make staged delivery operationally
safe: selected runtime populations may be offered an immutable candidate,
privacy-minimized health signals may describe what happened, and operators may
pause or halt further offers without weakening runtime trust.

P3 is not a new runtime architecture and is not a claim that rollout or
observability is implemented. This document is a design gate for maintainer
review after the bounded P2 engineering exit.

## 2. Non-goals

This design does not implement or authorize:

- runtime telemetry ingestion, an observation store, a rollout engine, cohort
  assignment, a dashboard, or alert delivery;
- billing, hosted KMS/HSM, SSO/SAML/OIDC/SCIM, enterprise RBAC, or
  multi-region cloud deployment;
- React Native, store submission, or a policy/legal conclusion;
- new Patch Format v1 fields, unsigned remote rollback, or a server-side
  override of runtime admission;
- product or business analytics, screen contents, user identity, source code,
  patch bytes, private keys, raw auth tokens, or unrestricted diagnostics.

No placeholder P3 module or endpoint is created by this task.

## 3. Frozen runtime and security boundary

The P2 invariants are prerequisites, not design suggestions:

1. The runtime verifies the exact signed Patch Format v1 bytes, application,
   release, function signatures, capability versions, runtime compatibility,
   sequence/high-water, and health state.
2. The runtime owns activation, last-known-good recovery, AOT fallback,
   signed rollback, and fail-closed behavior. A rollout service is an
   eligibility adviser only.
3. Rollout metadata is external to Patch Format v1. It cannot rewrite patch
   bytes, signature metadata, sequence, release binding, capability
   declarations, or function identity.
4. Customer/local patch signing remains outside the control plane. A rollout
   operator never receives a patch private key merely by gaining rollout
   permissions.
5. A healthy installed patch remains locally usable when delivery, control
   plane, observation, or dashboard services are unavailable.
6. A pause/kill switch may stop new offers. It cannot invalidate already
   accepted healthy code by an unsigned server flag, lower high-water, or
   force an arbitrary rollback.

If an implementation proposal requires any exception, P3 stops and returns to
the P2 trust review.

## 4. Product concepts and immutable entities

Rollout product identity is intentionally separate from runtime patch
identity. Suggested opaque identifiers use a product prefix and random
identifier; they are not hashes or sequence numbers used by the runtime.

| Entity | Design contract |
| --- | --- |
| `Rollout` | Stable product record owned by one organization/application/environment; points to the current revision and lifecycle state. |
| `RolloutRevision` | Immutable policy/state snapshot with monotonically increasing revision number, actor, timestamp, reason, previous revision, and audit event. |
| `RolloutTarget` | Exact immutable application, environment, platform, base release, candidate patch ID, candidate sequence, artifact digest, and runtime/format compatibility. |
| `RolloutPolicy` | Immutable cohort selector, percentage, exposure mode, observation window, pause/halt behavior, and optional internal allow-list reference. It never enters Patch Format v1. |
| `RolloutObservationWindow` | Start/end and proposed sample/health evaluation parameters. Numeric thresholds are proposals until measured. |
| `RolloutDecision` | Manual or future automatic recommendation (continue, pause, halt, expand, retire), actor/rule, evidence window, and audit linkage. A decision does not itself activate code. |
| `InstallationIdentity` | Random app-install-scoped identifier used only to derive a privacy-minimized bucket. It is not an advertising ID, serial number, Apple ID, Google account, or precise device identity. |
| `HealthEvent` | Versioned, authenticated, bounded patch-safety observation with idempotency identity and safe metadata. |

One rollout revision references exactly one immutable Patch record, one exact
immutable Release record, and one immutable artifact digest. Changing a
percentage, cohort, target, state, or observation policy creates a new
revision; it never mutates the historical revision or patch.

## 5. Rollout state machine

The initial conceptual states are:

```text
DRAFT → READY → INTERNAL → CANARY → EXPANDING → COMPLETED → RETIRED
                         ↘       ↘         ↘
                           PAUSED ←─────────
                         active state → HALTED → RETIRED
```

`PAUSED` remembers the prior active state in its immutable revision. Resuming
requires a new revision and an explicit action; it is not an in-place mutable
flag. `HALTED` is terminal for that rollout identity. A replacement candidate
or materially different policy creates a new rollout. `COMPLETED` means the
policy reached its declared final exposure, not that every installation
activated the patch.

| Transition | Permission | Preconditions | Audit event | Delivery effect | Failure behavior |
| --- | --- | --- | --- | --- | --- |
| `DRAFT → READY` | `rollout:create` or `rollout:update` | Exact release/patch/digest exists, signature and metadata preflight passed, target platform/environment matches, policy is canonical, and no duplicate active target conflicts. | `rollout.ready` | No clients are offered the candidate. | Reject atomically; remain `DRAFT`; record validation diagnostics without patch bytes. |
| `READY → INTERNAL` | `rollout:promote` | Internal allow-list or approved internal cohort exists; required two-person policy, if enabled, is satisfied. | `rollout.started` | Only eligible internal installations may receive `PATCH_AVAILABLE`. | Keep `READY`; no partial offer. |
| `READY → CANARY` | `rollout:promote` | Canary percentage/cohort and observation window are valid; immutable target is still current. | `rollout.started` | Deterministic canary eligibility begins. | Keep `READY`; no candidate is offered. |
| `READY → EXPANDING` | `rollout:promote` | Explicitly approved starting percentage and policy; no implicit 100% default. | `rollout.started` | Eligible percentage receives the candidate. | Keep `READY`; reject missing/unsafe policy. |
| `INTERNAL → CANARY` | `rollout:promote` | Internal observation window has been reviewed or an explicit manual override is audited. | `rollout.expanded` | New deterministic cohort becomes eligible; already healthy installations remain local. | Keep `INTERNAL`; no automatic expansion on missing observations. |
| `CANARY → EXPANDING` | `rollout:promote` | Proposed health checks and minimum-sample review are recorded; percentage is canonical and non-ambiguous. | `rollout.expanded` | Adds buckets only when the percentage increases. | Keep `CANARY`; return a precondition/conflict error on stale revision. |
| `EXPANDING → COMPLETED` | `rollout:promote` | Declared final percentage is reached and a completion decision is audited. | `rollout.completed` | No new rollout change; candidate remains eligible according to the final policy. | Keep `EXPANDING`; no hidden mutation. |
| `INTERNAL/CANARY/EXPANDING → PAUSED` | `rollout:update` or `rollout:halt` | Actor is authorized and pause reason is recorded. | `rollout.paused` | New eligible clients stop receiving the candidate; existing healthy code stays usable. | If persistence fails, old revision remains effective and action reports failure. |
| `PAUSED → INTERNAL/CANARY/EXPANDING` | `rollout:promote` | Fresh revision, explicit resume reason, current target, and any required two-person approval. | `rollout.resumed` | Eligibility resumes using the new immutable policy. | Remain `PAUSED`; no last-write-wins. |
| `INTERNAL/CANARY/EXPANDING/PAUSED → HALTED` | `rollout:halt` | Halt reason and operator identity are recorded; emergency path is audited. | `rollout.halted` | Stop all new offers. No unsigned revocation or forced rollback. | If action cannot persist, retain the prior state and surface an operator error. |
| `COMPLETED/HALTED → RETIRED` | `rollout:update` | Replacement/retirement reason and retention policy are recorded. | `rollout.retired` | No new offers; historical audit and aggregate records remain subject to retention. | Remain in prior terminal state. |
| `DRAFT/READY → RETIRED` | `rollout:update` | Cancellation/retirement reason is recorded before any offer. | `rollout.retired` | Candidate is never offered. | Remain in prior state if persistence fails. |

Every mutation is idempotent and conditional on the caller's expected
revision. A successful transition creates a durable audit event and a new
immutable `RolloutRevision` before it becomes eligible to update lookup
responses.

## 6. Revision and artifact immutability

Rollout policy changes affect eligibility only. They must never:

- rewrite the artifact, digest, signature, Patch Format, sequence, release
  binding, capability list, or function identity;
- replace the candidate Patch record or Release record in a historical
  revision;
- put cohort, percentage, health, or operator metadata into Patch Format v1;
- make a server response authoritative over runtime verification.

The control plane should reject a revision if the target patch or release is
missing, superseded, malformed, has a digest mismatch, or is not compatible
with the target environment. Runtime admission independently repeats the
checks that protect executable trust.

## 7. Deterministic cohorts and installation identity

The proposed first algorithm uses no user account or device hardware ID:

1. On first app install, the compiled runtime creates a random 128-bit
   installation identifier and stores it in app-install-scoped support state.
2. Reinstall or explicit app-data deletion creates a new identifier. An app
   update does not intentionally rotate it.
3. The evaluator canonicalizes organization, application, environment,
   platform, exact base release, installation identifier, and a rollout salt
   into a versioned domain-separated byte string.
4. It computes SHA-256 and interprets the first 64 bits as an unsigned bucket
   in `[0, 2^64)`. The identifier is never sent as raw telemetry.
5. An installation is eligible when `bucket < floor(percentBasisPoints ×
   2^64 / 10_000)`. Percentages are represented as integer basis points, not
   floating-point values.

The rollout salt is immutable per rollout target and is non-secret. It avoids
unintended correlation between unrelated rollouts while keeping assignment
recomputable and auditable. The control plane validates that all inputs belong
to the authenticated organization/application/environment scope.

The initial exposure mode is `deterministic_re_evaluate`:

- increasing a percentage adds higher buckets and is monotonic for new
  offers;
- decreasing a percentage removes eligibility for future lookup offers but
  does not uninstall or invalidate a healthy installed patch;
- pausing/halting stops new offers but does not lower high-water or revoke
  local code;
- an installation is not server-pinned after exposure. A future sticky
  exposure mode would require a separate privacy, reinstall, and retention
  decision;
- a reinstalled app gets a new identity and may receive a different bucket.

An internal allow-list is a separate explicit target selector, not a hidden
exception in the hash algorithm. It must be tenant-scoped and audited.

## 8. Percentage semantics

The supported policy values are integer basis-point percentages corresponding
to 1%, 5%, 10%, 25%, 50%, and 100% in the first design review; arbitrary
values may be added only with the same canonical rule. `0` means no offers.

Eligibility is evaluated against the exact current rollout revision on each
lookup. A percentage increase can add installations but cannot change the
candidate bytes. A percentage decrease, pause, or halt affects only future
offers. Already healthy installations remain subject to their local runtime
health and rollback rules. A device does not leave a healthy patch merely
because its bucket is no longer eligible.

If multiple rollouts target the same application/environment/base release,
the evaluator must choose one deterministic winner by an explicit conflict
rule (initially reject overlapping active targets). It must not make a
last-write-wins selection.

## 9. Eligibility integration

The existing runtime decision vocabulary remains unchanged:

```text
NO_UPDATE
PATCH_AVAILABLE
UPDATE_BLOCKED
STORE_RELEASE_REQUIRED
```

Rollout eligibility affects whether the delivery service offers a candidate:

- ineligible, paused, halted, or retired rollout: `NO_UPDATE` for that
  request, with safe bounded server diagnostics if authorized;
- eligible candidate: `PATCH_AVAILABLE` plus the immutable target metadata;
- candidate present but incompatible, stale, unauthorized, malformed, or
  unavailable: the existing `UPDATE_BLOCKED`/delivery failure behavior;
- native/store boundary: `STORE_RELEASE_REQUIRED`, independent of rollout
  eligibility.

The runtime still verifies signature, exact release, capabilities,
compatibility, sequence/high-water, and health after receiving
`PATCH_AVAILABLE`. The server never returns a new trust decision.

## 10. Pause, kill switch, and rollback semantics

### Operational rollout pause

`PAUSED` stops new eligible offers at the control plane. It does not delete
artifact bytes, lower high-water, or change a locally healthy runtime. A
previously offered but not yet activated candidate may still be rejected by
the runtime if its normal checks fail; pause is not an unsigned revocation.

### Operational halt / kill switch

The safe kill switch can:

- stop offering the candidate;
- create a signed, durable `HALTED` revision and audit event;
- require an operator decision before any new offer;
- optionally point delivery at a separately valid signed rollback/control
  artifact if that artifact and protocol already exist.

It cannot force arbitrary unsigned rollback, reset high-water, invalidate
healthy local code by a flag, or grant new runtime capabilities. If no valid
signed rollback artifact exists, the kill switch only stops future offers and
the runtime's local recovery/manual rollback mechanisms remain authoritative.

### Three distinct rollback terms

1. **Operational rollout rollback:** pause or halt eligibility, leaving local
   runtime state untouched.
2. **Runtime signed rollback:** a valid, signed rollback/control artifact or
   locally authorized runtime operation clears executable selection according
   to the existing state-v4 rules while retaining high-water.
3. **Store-release rollback:** a native, manifest, entitlement, plugin, engine,
   or other store-bound change requires a normal store release; P3 cannot
   provide it.

## 11. Health-event model

The minimum patch-safety event vocabulary is:

```text
lookup_attempt
candidate_offered
download_succeeded
download_failed
admission_verified
admission_rejected
activation_started
activation_succeeded
activation_failed
healthy_confirmed
runtime_fault
rollback
fallback_to_aot
restart_survived
store_release_required
```

Events describe patch safety and delivery behavior, not product usage. A
runtime may batch or sample them. No event is required for executing normal
unpatched AOT code.

### Versioned conceptual event schema

The following is a conceptual v1 schema, not an implemented API:

| Field | Requirement |
| --- | --- |
| `schemaVersion` | Integer `1`; unknown future versions are rejected or quarantined without affecting runtime. |
| `eventId` | Random, opaque, client-generated idempotency ID; no source path or user ID. |
| `clientTimestamp` / `receivedAt` | Client time is diagnostic only; server receipt time is authoritative for windows. |
| `organizationId`, `applicationId`, `environmentId` | Scope validated from the observation credential; never trusted solely from the payload. |
| `platform` | Bounded platform enum such as `android` or `ios`. |
| `releaseId`, `patchId`, `sequence` | Candidate identity validated against the scoped release/rollout record. |
| `rolloutId`, `rolloutRevision` | Opaque product rollout identity and immutable revision reference. |
| `installationBucket` | Pseudonymous bucket or bounded cohort label; raw installation identifier is excluded. |
| `eventType` | One of the bounded patch-safety vocabulary values. |
| `runtimeVersion`, `patchFormatVersion` | Compatibility metadata, not executable content. |
| `diagnosticCode` | Stable, redacted code from a bounded registry; no raw stack or path. |
| `safeMetadata` | Small allow-listed scalar map with strict size/key limits; no business data. |

Never include source code, patch bytes, private keys, auth tokens, screen
contents, user/business payloads, absolute source paths, raw stacks, precise
device serials, advertising IDs, Apple/Google account identity, or unrestricted
native diagnostics.

## 12. Privacy and installation identity

The random installation ID is app-install scoped and is used to make cohort
assignment stable, not to identify a person. It may be stored alongside local
runtime state only as a non-authoritative eligibility input. The runtime may
operate normally when it cannot create or upload observation state.

The design must support disable/opt-out at the application or customer policy
boundary. Disabling observations must not disable patch signature checks,
activation, rollback, or AOT fallback. Raw event collection must be bounded,
aggregated where possible, and subject to tenant deletion and data-locality
rules.

The default design does not use advertising IDs, hardware serials, platform
account IDs, contacts, precise location, or user content. Reinstall resets the
identity; a customer may choose a shorter local lifetime, but that choice
requires a new cohort-stability analysis.

## 13. Event authentication and compromise impact

Candidate options:

| Option | Benefit | Compromise impact | Decision |
| --- | --- | --- | --- |
| Reuse read-only delivery credential | Minimal credential plumbing | A leaked token could submit observations for its application/environment and possibly read artifacts; scopes are too coupled for a long-lived production default. | Not preferred. |
| Long-lived observation credential | Separates read and write surfaces | A leak permits metric poisoning for its scoped tenant until rotation; storage and rotation burden remains. | Possible self-host adapter with explicit rotation. |
| Short-lived observation upload token | Narrow scope, expiry, and no control-plane/artifact-write authority | A leak permits bounded event injection during the token lifetime; it cannot sign patches, mutate rollout state, read artifacts, or change trust. | **Preferred design**, subject to implementation/security review. |

The preferred token is minted only for one application/environment and
observation purpose, has a short expiry and bounded event rate, and is not
accepted on control-plane mutation routes. Event payload identity is validated
against token scope and current release/patch/rollout records.

## 14. Event idempotency and late data

The ingestion contract must be duplicate-safe:

- `eventId` is unique within an organization/application/environment and a
  bounded retention window; an exact duplicate is acknowledged without
  incrementing counts;
- payload mutation with an existing ID is rejected and audited;
- client timestamps are checked for a bounded skew but server receipt time
  controls observation windows;
- late events may be accepted into a late-data bucket without rewriting
  already published decisions;
- retention of idempotency keys must cover the maximum offline retry window;
  its exact duration is a P3 implementation decision, not a current claim;
- rate limits, payload-size limits, and per-installation/event-type bounds
  prevent one client from dominating a cohort.

## 15. Aggregation and health metrics

Only patch-safety aggregates are required:

| Aggregate | Definition |
| --- | --- |
| Eligible installations | Deterministic eligible bucket count for the revision, subject to privacy minimums. |
| Lookup attempts/offers | Scoped lookup and candidate-offer counts, deduplicated by event ID. |
| Downloads | Success/failure counts and bounded failure codes. |
| Admissions | Signature/format/identity/capability/compatibility admission outcomes. |
| Activations | Started, succeeded, failed, and healthy-confirmed counts. |
| Runtime faults | Bounded diagnostic-code counts after activation. |
| Rollbacks/fallbacks | Runtime rollback and AOT fallback events, separated from operator halt. |
| Restart survival | Healthy patch observed after process restart, when emitted. |
| Stale/replay rejects | Safety rejections, never counted as activation failures. |

The first proposed candidate health metrics are activation success rate,
healthy-confirmation rate, runtime-fault rate, rollback/fallback rate,
download failure rate, and post-activation restart survival. Thresholds and
minimum sample counts are **PROPOSED — REQUIRES EMPIRICAL CALIBRATION**; no
numeric production threshold is declared in P3 design.

Aggregates should suppress or coarsen small populations to reduce tenant or
installation re-identification. A dashboard must show sample size, missing
data, event freshness, and confidence limitations rather than a falsely
precise percentage.

## 16. Automatic halt design

Future automatic halt may evaluate a revision over an explicit observation
window using:

- minimum eligible/activation sample count;
- activation and healthy-confirmation failure rates;
- runtime-fault and rollback/fallback rates;
- download/admission failure rates;
- event freshness and observation outage state.

All thresholds are proposed until representative production-like measurement
exists. A halt action only stops new eligibility and records a signed/audited
control-plane decision. It never remotely invalidates already installed
healthy patches or overrides runtime trust. If observations are missing or
spoofing confidence is low, the safe default is no expansion and manual
review, not automatic rollback.

## 17. Manual operator controls and audit

Future controls are:

```text
create, inspect, start, increase, pause, resume, halt, retire
```

Each requires the least-privilege scope in the RBAC design, an expected
revision/idempotency key, an immutable new revision, reason, actor, and audit
event. High-risk actions may require future two-person control: production
start, 100% expansion, manual health override, resume after halt, and any
key/trust-related operation. No approval workflow is implemented here.

Conceptually additive operator resources are:

```text
/v1/rollouts
/v1/rollouts/{id}
/v1/rollouts/{id}/revisions
/v1/rollouts/{id}/actions
/v1/rollouts/{id}/summary
```

These are design candidates only. Existing `/v1` release registration,
promotion, runtime lookup, and artifact fetch remain compatible. A future API
must reject stale `If-Match`/revision values with a precondition error rather
than applying last-write-wins.

## 18. Audit integration

Every rollout mutation must create a durable, redacted audit record before the
new revision can affect eligibility:

```text
rollout.created
rollout.ready
rollout.started
rollout.expanded
rollout.paused
rollout.resumed
rollout.halted
rollout.retired
rollout.manual_override
rollout.policy_changed
```

The existing signed off-box audit-export boundary remains the audit trust
mechanism. Audit-export signing keys stay separate from patch-signing keys.
Rollout IDs, revision numbers, exact target digest, actor scope, reason,
predecessor revision, and server time may be included; patch bytes and
credentials may not.

## 19. RBAC and tenant isolation

P3 does not implement enterprise RBAC. The minimum future scopes to review are:

```text
rollout:read
rollout:create
rollout:update
rollout:promote
rollout:halt
observation:read
observation:write
audit:read
```

A rollout actor must be authorized for the exact organization/application/
environment and platform target. Observation writers may not mutate rollout
state, releases, artifacts, credentials, or signing keys. Read summaries must
be tenant-bound, and cross-tenant rollout reads, event injection, cohort
assignment, and metric leakage must be explicit implementation tests.

The self-hosted single-tenant path may map these scopes to local operator
credentials. A hosted offering requires a separate identity/privacy review;
this design does not assume an enterprise identity provider.

## 20. Data retention, deletion, and locality

Retention classes are proposals, not production commitments:

| Data | Proposed starting treatment | Required review |
| --- | --- | --- |
| Raw health events | Short bounded window (for example, 30 days), then aggregate or delete. | Privacy, customer contract, storage/cost, and incident needs. |
| Aggregated rollout metrics | Longer bounded window (for example, 180 days), with small-cohort suppression and tenant deletion. | Product/support and data-residency review. |
| Rollout revisions/decisions | Durable operational history tied to audit retention, with immutable history and explicit deletion/legal-hold rules. | Security, legal, and self-host retention review. |
| Audit records/exports | Existing configured audit retention and signed off-box export contract; no indefinite default. | Compliance/customer policy review. |
| Diagnostics | Shortest useful window, bounded codes only, with source-map identity redaction. | Privacy and incident-response review. |

Future hosted deployments may need region selection and tenant-level data
residency (EU, India, US, or customer-selected region), deletion/anonymization
workflows, and an explicit cross-region transfer policy. No multi-region
infrastructure is designed or built in P3.

## 21. Runtime observability boundary

Keep three domains separate:

1. **Service/process metrics:** latency, availability, database/object-store
   health, queue depth, and operator infrastructure signals.
2. **Runtime patch-safety observations:** the bounded event vocabulary above.
3. **Product/business analytics:** user actions, screens, conversions, and
   business payloads, which are outside P3.

P3 may design the first two only. Runtime observations are incomplete and
optional. They do not decide cryptographic validity, capability authority,
health, or rollback.

Diagnostics must use stable bounded codes and, where needed, opaque source-map
identity fields. They must not include absolute source paths, full source
stacks, patch bytes, secrets, tokens, private keys, or user/business data.

## 22. Offline and outage behavior

### Runtime offline behavior

If delivery or observation upload fails, the app continues using its current
local runtime state. Observation events may queue in a bounded local buffer;
queue exhaustion drops oldest low-value events and records only a local bounded
counter. Event upload never blocks the UI isolate, causes a rollback, or
changes AOT fallback.

The exact initial queue budget is a future implementation parameter. A
reasonable proposal is a small count-and-byte cap (for example, hundreds of
events and about one megabyte), with no unbounded disk growth.

### Control-plane outage

An already installed healthy patch remains usable. A client may report
`NO_UPDATE` or retain its current state until lookup resumes. No server outage
may invalidate local trust state.

### Observation outage

Observation availability is independent from artifact delivery. When health
data is stale or unavailable, future rollout expansion pauses conservatively or
requires an explicit manual decision. Existing eligible installations and
runtime execution continue. An operator cannot infer “healthy” from missing
events.

## 23. Threat model

| Threat | Mitigation | Residual risk |
| --- | --- | --- |
| Cohort manipulation | Canonical domain-separated hash, scoped inputs, immutable salt, deterministic evaluator, revision/audit history. | A compromised control plane can misconfigure policy; runtime still verifies bytes but cannot detect a dishonest percentage without independent review. |
| Metric poisoning | Short-lived scoped event token, schema validation, event IDs, rate limits, release/patch binding, duplicate handling, outlier/sample review. | A compromised client can still submit bounded false events for its scope. Metrics are advisory, not trust. |
| Event replay | Unique event ID, idempotency retention, payload binding, server receipt time, late-event bucket. | Replay outside retention or after a data-store restore requires operational reconciliation. |
| Event spoofing | Authenticated observation upload and tenant/application/environment scope checks. | Credential theft permits bounded poisoning until expiry/revocation. |
| Operator account compromise | Least privilege, immutable revisions, audit, optimistic concurrency, optional two-person control for high-risk actions. | An authorized compromised operator can halt or expand within their scope; runtime signature checks remain intact. |
| Accidental 100% expansion | Explicit basis-point policy, no implicit default, precondition review, two-person option, alerting, immutable revision. | Human error can still cause a valid but unwanted offer; halt must be rapid and safe. |
| Bad health threshold | Proposed thresholds, minimum samples, conservative missing-data behavior, manual override/audit, no forced rollback. | A false positive can pause a rollout; a false negative can expose more clients before detection. |
| Dashboard/API authorization bug | Tenant-bound queries, route scope checks, negative cross-tenant tests, no dashboard authority over runtime. | Information leakage or operator action may occur before detection; audit and isolation reduce impact. |
| Observation-store compromise | Encrypt/limit access as deployment responsibility, retention minimization, redaction, separate credentials, signed audit export. | Historical bounded metadata may be exposed; patch bytes/private keys are not stored in observations. |
| Delivery/observation outage | Local runtime independence, bounded queues, conservative expansion, immutable artifact storage. | New offers may pause or become stale; healthy local code continues. |
| Rollout policy tampering | Immutable revisions, digest-bound target, authenticated mutation, audit chain/export, concurrency preconditions. | A fully compromised control plane can deny service; it cannot forge a runtime-valid artifact without the signing key. |

## 24. Metric-poisoning resistance

Future ingestion must validate, before aggregation:

- token scope matches organization/application/environment;
- release, patch, sequence, rollout ID, and revision match known immutable
  records;
- event type and metadata keys are allow-listed and size-limited;
- event ID is new or an exact duplicate;
- client time is within a bounded skew and server receipt time is recorded;
- per-token, per-installation-bucket, and per-event-type rate limits hold;
- impossible transitions (for example, `healthy_confirmed` without a prior
  admitted/activated candidate in the same scoped history) are quarantined or
  marked low-confidence rather than silently counted;
- outliers, late events, and observation gaps are visible in summaries.

The server must never accept a client-reported identity as proof that a patch
was actually signed or admitted. Runtime evidence remains advisory.

## 25. Rollout failure modes

| Failure | Expected behavior | Safe default | Operator action | Runtime impact |
| --- | --- | --- | --- | --- |
| Server thinks a bad patch is eligible; runtime rejects it | Count admission rejection; do not count activation; preserve base/LKG. | Stop expansion if rejection rate is material. | Inspect artifact/release/signature and halt the rollout. | Normal fail-closed rejection; no trust weakening. |
| Artifact unavailable | Lookup may return blocked/delivery failure; no partial artifact is staged. | Do not expand. | Restore immutable object or correct delivery dependency; create a new revision if digest changes. | Existing healthy patch/base remains usable. |
| Delivery outage | New offers fail or are absent. | Preserve local state; pause expansion if window is affected. | Repair edge/storage/service. | No invalidation of installed code. |
| Observation outage | Events are missing/stale. | Pause expansion; require manual review. | Repair observation path or document a bounded decision. | Runtime continues independently. |
| Database outage | Mutations and eligibility reads fail closed or use last known safe revision according to delivery contract. | No new mutation; do not invent a policy. | Restore database and reconcile audit/revisions. | Installed code unaffected. |
| Percentage misconfiguration | Canonical validation rejects invalid/out-of-range basis points or stale revision. | No transition. | Submit reviewed immutable revision; high-risk values may need two-person approval. | No effect until a valid offer. |
| Cohort algorithm bug | Revision/evaluator version mismatch is detected; assignment is quarantined. | No expansion. | Halt, publish a corrected evaluator/revision, review affected metrics. | Existing patches remain local. |
| Accidental 100% | Audit/alert and two-person controls provide detection; valid candidate may be offered if action committed. | Halt new offers immediately after review. | Use operational halt, not unsigned revocation; assess signed rollback/store release separately. | Runtime continues its own checks. |
| Health false positive | Automatic halt may stop expansion unnecessarily. | No forced rollback. | Review sample quality and resume with new revision if safe. | Healthy installations remain healthy/local. |
| Health false negative | Candidate reaches more eligible clients before detection. | Keep thresholds conservative and expose confidence/sample gaps. | Halt and follow signed runtime/store procedures. | Runtime can still reject/fallback/rollback. |
| Event replay/spoofing | Duplicate or invalid-scope events are rejected/quarantined. | Exclude from aggregates. | Rotate observation token and investigate. | None. |
| High latency | Lookup/fetch/ingestion latency is visible as service metrics and bounded event class. | Do not block runtime on observation. | Repair service or pause expansion if update safety is affected. | Existing code continues; new update may be delayed. |
| Clock skew | Server receipt time controls windows; client timestamp is diagnostic. | Quarantine events outside bounded skew. | Review device/service clocks and late-data bucket. | None. |

## 26. SLO and error-budget design

P3 may define objectives for a future deployment, but no numeric production
values are declared without measurement. Candidate objectives are:

- update lookup availability and correctness;
- immutable artifact fetch availability and digest correctness;
- rollout mutation durability and conflict response;
- health-event ingestion availability and duplicate handling;
- summary/dashboard freshness and data-loss bounds;
- halt decision persistence and propagation time;
- observation outage detection and conservative expansion behavior.

Each objective must later state scope, measurement source, population,
maintenance exclusions, error budget, owner, and response. Values are **TBD
FROM PRODUCTION MEASUREMENT**. Runtime correctness must not be an error-budget
dependent service promise.

## 27. Concurrency and consistency

Rollout mutations require an idempotency key and an expected current revision
or state version. The service creates a new immutable revision in one durable
transaction with its audit event. Concurrent stale actions return a
precondition/conflict response; there is no last-write-wins policy mutation.

Repeated identical actions are idempotent. A retry after an ambiguous network
failure can inspect the idempotency result. Eligibility reads must use a
consistent current revision and must not combine target metadata from one
revision with percentage policy from another.

## 28. Multi-tenant isolation tests required before implementation

Future implementation must prove at least:

- cross-tenant rollout read denial;
- cross-tenant rollout mutation denial;
- cross-tenant observation injection denial;
- cross-tenant summary/metric leakage prevention;
- cohort hash separation by tenant/application/environment;
- no credential from one tenant can fetch another tenant's artifact or
  observation data;
- audit export remains tenant-scoped and signature-verifiable.

These are entry criteria, not P3 evidence today.

## 29. OSS/commercial boundary

The existing open-core direction is preserved. A candidate open-source P3
surface is:

- rollout protocol and domain model;
- deterministic eligibility evaluator and cohort algorithm;
- local/self-hosted rollout engine;
- versioned health-event schema and privacy/redaction rules;
- bounded aggregation core, CLI primitives, and audit model.

A candidate managed/commercial surface is:

- hosted dashboard and collaboration workflows;
- managed large-scale observation pipeline and alerting;
- advanced retention/residency controls, support, and managed SLO
  operations;
- enterprise approvals/RBAC and managed multi-region rollout operations.

This is a packaging proposal only; it changes no license and grants no
commercial implementation authority.

## 30. Future CLI design

Conceptual commands, not implemented:

```text
tool rollout create
tool rollout inspect
tool rollout start
tool rollout expand
tool rollout pause
tool rollout resume
tool rollout halt
tool rollout retire
tool rollout summary
```

Each command must show the exact app/environment/platform/base release,
candidate patch/digest, percentage/cohort policy, revision, actor, and audit
result. Commands must use explicit confirmation for high-risk actions and
never sign or mutate patch bytes.

## 31. Operator API design

The additive candidate resources are:

```text
GET/POST   /v1/rollouts
GET        /v1/rollouts/{id}
GET        /v1/rollouts/{id}/revisions
POST       /v1/rollouts/{id}/actions
GET        /v1/rollouts/{id}/summary
```

The current release/patch/artifact/runtime-delivery endpoints remain
compatible. API contracts must define authorization, idempotency, expected
revision, error codes, pagination/retention, redaction, and tenant scope.
No endpoint is implemented by this task.

## 32. Dashboard information architecture

A future operator view should organize information as:

```text
applications
  environments
    releases
      patches
        rollouts
          rollout health
          audit
          incidents
```

The navigation must keep runtime trust state separate from service eligibility
and product analytics. A self-hosted CLI must remain sufficient when no
dashboard is deployed.

## 33. Rollout view and alerting

The rollout view must answer, with freshness and sample caveats:

- what immutable candidate is rolling out, for which exact release/platform;
- current state, revision, percentage, cohort selector, and observation
  window;
- eligible, offered, downloaded, admitted, activated, healthy, failed,
  rolled-back, fallback, and stale/replay-rejected counts;
- whether the rollout is paused/halting/halted and why;
- what changed recently, which actor changed it, and which audit event proves
  the change.

Potential alerts are proposed only: activation failure spike, runtime fault
spike, rollback/fallback spike, artifact-fetch failure spike, observation
outage/staleness, unexpected expansion, and audit verification failure.
Thresholds, routing, and external alert integrations require a separate
implementation/operations review.

## 34. Privacy-preserving diagnostics and deletion

Source-map identity, if ever needed, must be an opaque bounded ID mapped only
within the customer's controlled release metadata. It must not expose an
absolute path, source text, line-level user data, or patch bytes. Deletion and
anonymization must cover raw events, installation-bucket mappings, aggregates,
and derived summaries while preserving only the minimum audit/legal record
required by the customer policy.

An observation service must not become a hidden source-code or business-data
collector. Customers must be able to disable or self-host it without changing
runtime trust behavior.

## 35. Proposed implementation sequencing (not authorized)

If the maintainer approves the design and all entry criteria are met, the
future sequence is:

| Phase | Proposed scope | Exit evidence |
| --- | --- | --- |
| P3A | Rollout domain/state machine, immutable revisions, audit integration, and local persistence. | Transition/property tests, conflict/idempotency tests, no Patch Format changes. |
| P3B | Deterministic cohort and percentage evaluator. | Canonical vectors, monotonicity/decrease/reinstall tests, privacy review. |
| P3C | Rollout-aware update eligibility integrated with current lookup. | `NO_UPDATE`/`PATCH_AVAILABLE` compatibility, pause/halt, runtime-authority tests. |
| P3D | Bounded health-event contract and ingestion. | Auth/scope/idempotency/redaction/size/rate/tenant tests, offline queue behavior. |
| P3E | Aggregation and conservative automatic-halt policy. | Missing-data, poisoning, threshold, and no-remote-revocation tests. |
| P3F | CLI/operator API. | Least-privilege, concurrency, audit, confirmation, and local self-host tests. |
| P3G | Dashboard and operator presentation. | Read-only trust separation, freshness/sample caveats, accessibility, and tenant tests. |

No phase starts automatically from this design. Each phase requires a new
task, explicit scope/owner/validation, and maintainer authorization.

## 36. Unresolved decisions

The following remain open and must be resolved before P3A implementation:

- maintainer acceptance of the state names/transitions and terminal-state
  behavior;
- whether internal allow-lists and deterministic percentage cohorts share one
  policy or are separate rollout targets;
- exact basis-point values, monotonicity guarantees, and any sticky-exposure
  mode;
- rollout evaluator versioning and compatibility when the algorithm changes;
- short-lived observation-token issuance/rotation and self-hosted equivalent;
- event queue size, retry/discard behavior, idempotency retention, and late
  event policy;
- minimum cohort/privacy suppression rules and data residency/deletion;
- empirical health thresholds, sample windows, and automatic-halt ownership;
- operator roles, two-person controls, and hosted/OSS responsibility split;
- SLO/error-budget measurements and production incident ownership.

No unresolved item may be hidden behind a dashboard default or an implicit
server authority.

## 37. P3A entry criteria and maintainer gate

Before a future implementation task may begin, maintainers must explicitly
approve:

1. the rollout state machine and immutable revision model;
2. the canonical cohort algorithm and percentage semantics;
3. pause, halt, operational rollback, runtime signed rollback, and
   store-release distinctions;
4. the event schema, authentication, idempotency, redaction, and metric
   poisoning boundaries;
5. privacy, installation identity, retention, deletion, and locality policy;
6. the OSS/commercial boundary and self-hosted responsibility;
7. representative evidence plans, owners, and validation budgets;
8. confirmation that Patch Format v1, capability v1, high-water, runtime
   signature authority, AOT fallback, and customer/local signing custody are
   unchanged.

The current task stops here. The maintainer must choose one exact option:

```text
HOLD P3 — EXTERNAL GATES FIRST
AUTHORIZE P3 DESIGN ONLY — COMPLETE
AUTHORIZE P3 IMPLEMENTATION WITH CONDITIONS
RETURN TO P2
STOP PROJECT
```

`AUTHORIZE P3 IMPLEMENTATION WITH CONDITIONS` must not be inferred from the
quality of this design. Beta, provider-production, and store/legal gates remain
open regardless of the design decision.

## 38. P3D implementation addendum (2026-08-24)

The maintainer has authorized the bounded P3D health-event ingestion slice.
The implementation is tracked in repository Task 52 because Task 51 is already
reserved for the completed physical-iOS diagnostics rerun. This addendum does
not reopen or rewrite the earlier P3A design evidence.

Implemented boundaries are intentionally small:

- PostgreSQL schema version 2 adds a tenant/application/environment-scoped
  append-only observation table and indexes. Rollout transitions use one
  PostgreSQL transaction with a fixed advisory-lock order, row-level CAS,
  immutable revision insertion, idempotency, and audit-chain insertion.
- File storage provides the same API for local/self-host testing and remains
  a single-node adapter; it makes no distributed-safety claim.
- Observation tokens are short-lived, application/environment scoped, and
  limited to `observation:write`. They cannot authorize signing, artifacts,
  releases, rollouts, credentials, or audit/control mutations.
- Events use schema version 1 and the bounded vocabulary in this document.
  Server receipt time controls retention and sequence interpretation; client
  time is diagnostic and late events are marked rather than reordered.
- Event identity is checked against trusted control-plane records. Duplicate
  canonical retries are acknowledged, mutated reuses are rejected and
  audited, impossible lifecycle sequences are quarantined, and raw
  installation identifiers, code, bytes, stacks, paths, tokens, and user
  payloads are not accepted.
- Request/event size, metadata, per-token/install/type rate, future-skew,
  late-data, and retention bounds are enforced before persistence. Deletion
  operates only on observation rows and cannot alter artifacts, rollouts,
  audit, or other tenants.
- `/v1/observations/token` and `/v1/observations/events` are the only new HTTP
  routes. No aggregation, health score, automatic halt, dashboard, alerting,
  runtime queue, or rollout decision is introduced by P3D.

Focused File-store and HTTP tests pass. PostgreSQL migration/CAS/observation
tests are present and execute only when `HYFENS_TEST_POSTGRES_URL` is
configured; an unconfigured environment is recorded as not-run rather than
inferred. P3D does not change mobile runtime code, so no physical-device
rerun is claimed for this slice.

The following remain outside this addendum and require separate review:
P3E aggregation/health scoring/automatic halt, P3F operator API expansion,
P3G dashboard/alerting, provider-production readiness, independent customer
application evidence, power-loss evidence, iOS performance/diagnostics,
store-policy review, and legal/compliance claims.
