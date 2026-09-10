# Scale, high availability, and disaster recovery

Status: DESIGN ONLY — NO PRODUCTION IMPLEMENTATION

<!-- Wide planning tables intentionally disable the line-length rule. -->
<!-- markdownlint-disable MD013 -->

This document defines planning envelopes and failure semantics for a future
control/distribution plane. It does not report measured capacity, promise an
SLO, or authorize a hosted or production deployment. There is no service to
benchmark yet, so numerical availability, latency, RPO, and RTO targets are
intentionally unset.

## Safety premise

The installed Flutter runtime is a separate failure domain from the service.
It owns signature verification, exact release binding, capability v1, sequence
and high-water anti-replay, pending health, rollback, and AOT fallback. A
control-plane outage, stale cache, CDN error, queue loss, database restore, or
malicious artifact response must not corrupt or silently replace installed
runtime state.

The service can improve delivery and operations; it cannot turn an invalid
artifact into a valid one. The following are runtime invariants, not service
SLOs:

- invalid, malformed, wrong-release, wrong-capability, stale, or equivocal
  artifacts are rejected by the runtime;
- a server never lowers a client's high-water or selects an older patch by
  changing metadata;
- an update check failure is equivalent to no new update, not permission to
  run unverified bytes;
- a failed candidate falls back to the prior known-good patch or bundled AOT
  according to state-v4;
- installed behavior remains available as far as the mobile platform and app
  itself remain available, even if the service is down.

## Planning envelopes

The scenarios below are deliberately broad planning envelopes for load-test
design. They are not forecasts, supported-capacity statements, pricing tiers,
or SLO targets. The first real capacity model must replace them with measured
workload distributions, artifact sizes, client check behavior, cache hit rates,
and tenant isolation constraints.

| Scenario | Organizations | Applications | Releases/day | Patches/day | Installations | Peak update checks/sec | Artifact egress/day | Optional observations/sec |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Small / lab or early self-hosted | 1–10 | 1–50 | 1–25 | 1–100 | 10²–10⁴ | 1–25 | 1–100 GB | 0–250 |
| Medium / team or regional service | 10–100 | 50–2,000 | 25–1,000 | 100–5,000 | 10⁴–10⁶ | 25–2,000 | 0.1–10 TB | 250–10,000 |
| Large / multi-region service | 100–10,000+ | 2,000–100,000+ | 1,000–50,000+ | 5,000–250,000+ | 10⁶–10⁸+ | 2,000–100,000+ | 1–100 TB | 10,000–100,000+ |

The ranges are useful for asking questions, not for claiming that a selected
database, object store, or cluster can sustain them. In particular:

- update checks are usually much more frequent than patch downloads; ETags,
  immutable cache keys, and a small response are central to the model;
- launch spikes, staged-rollout boundaries, and regional time zones can make
  peak checks much higher than a daily average;
- artifact egress depends on patch size, retry behavior, cache hit rate, and
  whether an installation downloads a patch once or across multiple devices;
- observations are optional, sampled, delay-tolerant, and never needed for
  cryptographic correctness;
- a tenant with one very large application can create a different failure
  shape from many small tenants, so quotas and per-tenant fairness are part of
  the design rather than a hidden assumption.

The first load model should compute, from observed client behavior:

```text
peak checks = installations × launch/check frequency × concentration factor
patch egress = eligible installations × patch bytes × retry/cache factor
observation ingress = event rate × sampling × retry factor
```

Each factor must be measured or chosen as an explicit test assumption. No
number in this document is a capacity commitment.

## Capacity and scaling seams

The system should have small, deep interfaces at these seams:

1. **Lookup interface** — accepts application/release/platform/environment,
   current sequence/high-water, and a privacy-preserving installation/cohort
   token; returns a versioned decision and immutable artifact references.
2. **Artifact interface** — reads an immutable object by digest and verifies
   content metadata before it is made eligible for delivery.
3. **Metadata interface** — transactionally records release, patch, rollout,
   trust, and audit state without embedding runtime execution logic.
4. **Observation interface** — accepts bounded, authenticated or otherwise
   attributable events as incomplete evidence; it cannot approve an artifact
   or force a rollback by itself.
5. **Asynchronous work interface** — turns committed outbox records into
   retryable webhooks, exports, or aggregations. Losing a worker must not lose
   the only copy of a release decision.

The first implementation should keep lookup and artifact fetch synchronous and
leave cache/queue adapters optional. Horizontal scaling is meaningful only
after idempotency keys, immutable object semantics, optimistic concurrency,
and outbox recovery are specified.

## HA profiles

High availability is an offering decision, not a property that appears when a
container is replicated.

| Profile | Candidate topology | Accepted failure posture | Required evidence before calling it HA |
| --- | --- | --- | --- |
| Small self-hosted | One control-plane process, one PostgreSQL instance, one artifact store/volume, operator backups | A service outage pauses new lookup/downloads; installed runtimes continue; restore is operator-led | Backup and restore test, artifact digest reconciliation, documented degraded mode |
| Medium | Multiple stateless control-plane instances across independent failure zones; HA/external PostgreSQL; replicated object store; optional cache and durable outbox workers | Loss of one stateless instance or cache should be transparent or bounded; database/object-store failure may pause writes or downloads conservatively | Zone-loss rehearsal, idempotent retry test, no partial rollout after failover, restore test |
| Large | Regional or multi-region stateless edges, partitioned workload handling, external database/object durability, private distribution edge, isolated worker pools | A regional or dependency failure should degrade to no update, paused rollout, or read-only behavior according to policy; client safety remains local | Regional failure exercise, split-brain analysis, artifact and audit recovery, measured error budgets, key-recovery exercise |

The medium and large topologies are candidates. They do not imply that the
project has selected a cloud provider, multi-region database, CDN, or
Kubernetes implementation.

## Failure domains and safe degradation

The service should document one owner and one recovery behavior for every
dependency. A dependency that is optional for correctness must fail closed or
degrade without becoming a hidden authority.

| Failure domain | What can fail | Safe behavior | Recovery concern |
| --- | --- | --- | --- |
| Flutter installation/device | Process death, local I/O fault, corrupted state, offline device | Existing state-v4 controller verifies, falls back to last-known-good/AOT, or enters its recovery barrier; no server response can bypass this | Physical power-loss and device evidence remain explicit Phase 1D gates; do not infer them from service uptime |
| Ingress/TLS/edge | DNS, certificate, proxy, rate limit, CDN edge, transport | Runtime treats lookup/fetch failure as no update and keeps current/base behavior; no client state is rewritten | Certificate/key rotation, cache invalidation, and regional routing must be recoverable without changing artifact identity |
| Stateless control plane | Process crash, bad deploy, capacity exhaustion | Existing clients continue; new checks retry with bounded backoff or receive a conservative error; rollout writes pause | Redeploy a known image, preserve idempotency, and reconcile pending transactions |
| PostgreSQL | Primary outage, replica lag, corruption, bad migration, lost connection | New writes and eligibility decisions pause or become read-only; cached decisions must remain bounded and cannot invent a patch | Point-in-time restore, replica promotion, schema compatibility, transaction/outbox reconciliation |
| Object storage | Timeout, missing object, eventual consistency, overwritten object, region loss | Artifact fetch fails or returns a digest mismatch; runtime rejects it; release remains unavailable until object reconciliation | Replicate immutable bytes, verify digests, and restore metadata/object pairing |
| Redis/Valkey | Eviction, restart, partition, stale cache, rate-limit loss | Bypass cache, recompute from authoritative metadata, or apply conservative rate limits; never treat cache as truth | Cache warm-up, stampede control, lease expiry, and no stale rollout approval |
| Queue/worker | Backlog, duplicate delivery, poison message, broker loss | Synchronous release/lookup path remains correct; webhook/telemetry/export work is delayed or retried from an outbox | At-least-once handling, deduplication, dead-letter review, and replay without duplicate state transitions |
| Signing boundary/KMS/HSM | Key service unavailable, rotation error, revoked key, offline signer unavailable | New signing or promotion stops; existing signed artifacts can still be verified under release policy; no emergency unsigned path | Key recovery and trust-root changes require explicit ceremony and do not lower client high-water |
| Observability | Metrics/log pipeline loss, spoofed event, sampling gap | No safety decision depends solely on telemetry; operator sees degraded evidence and rollout automation pauses if policy requires | Retention, replay, source attribution, and separation of observation from authority |
| Operator/import path | Bad configuration, tampered export, wrong tenant/environment, accidental promotion | Validate, quarantine, and refuse import or promotion; preserve the prior policy and artifact state | Two-person review where required, audit record, and rollback of metadata without deleting immutable bytes |
| Region/cluster | Network partition, cluster loss, provider outage | Delivery becomes no-update/read-only/paused according to policy; installed clients remain local | Rebuild from backups, reconcile object digests and rollout state, then re-enable writes deliberately |

The phrase “no update” is a safe delivery result, not an assurance that the
service is healthy. Error responses must be distinguishable from a valid
`NO_UPDATE` decision for diagnostics, while client behavior can remain
conservative and offline-tolerant.

## SLO candidates and rationale

These are candidate SLO dimensions to be selected per offering after the first
implementation has baselines and load evidence. They deliberately do not
contain fabricated percentages, latency limits, propagation windows, RPOs, or
RTOs. A number becomes a real objective only after maintainers approve the
measurement method, dependency budget, client behavior, and error budget.

| SLO candidate | Measurement boundary | Candidate objective | Rationale | Evidence needed before a numeric target |
| --- | --- | --- | --- | --- |
| Control-plane availability | Authenticated API requests excluding planned maintenance that is disclosed by the offering | Define an availability objective per managed/self-hosted offering; target unset | The control plane should be usable, but its outage must not disable installed runtime behavior | Multi-tenant load, dependency budgets, failover behavior, and error classification |
| Update lookup availability | Versioned lookup response for supported inputs, including conservative errors | Prefer a valid `NO_UPDATE`/error response over an unsafe eligibility decision; target unset | Lookup is on the client delivery path but is not the runtime trust boundary | Peak check model, cache behavior, regional failure tests, and retry impact |
| Lookup latency | Client-visible lookup request, measured by percentile and region/network class | Track p50/p95/p99 and define a budget after real client and edge measurements; no limit claimed | Slow lookup harms launch experience and creates retry storms | Representative devices, network profiles, cache hit/miss, and spike tests |
| Artifact availability | Digest-addressed fetch of an already committed artifact | Every acknowledged artifact must remain recoverable or be marked unavailable before promotion; availability target unset | An artifact must not disappear between registration and rollout | Object-store durability, replication, backup restore, and digest reconciliation |
| Artifact integrity | Digest/signature/release/capability verification at import, fetch, and runtime activation | Zero tolerance for accepting a mismatch; this is an invariant, not a service percentage | A bad artifact is a safety failure even if the service is otherwise available | Malformed, tampered, stale, wrong-release, and import-transfer corpus |
| Rollout propagation | Time from an authorized policy change to lookup eligibility at the supported edge/cache population | Define a bounded propagation objective only after cache and queue semantics are measured; target unset | Operators need to know when pause/canary/full decisions take effect | Cache TTL/ETag tests, partitions, duplicate events, and regional convergence |
| API/dashboard responsiveness | Human and automation requests for the supported management surface | Measure separately from runtime lookup; target unset | Dashboard/API overload should not consume the lookup budget or hide rollback controls | Endpoint-level load, tenant fairness, and degraded dependency behavior |
| Observation freshness | Time from optional runtime event receipt to an operator-visible aggregate | Eventual and explicitly incomplete; target unset | Telemetry is useful for operations but cannot be required for correctness | Sampling, offline queues, spoofing, retention, and aggregation delay |
| Backup/restore readiness | Restore rehearsal from the declared backup set to a clean boundary | A restore must recover metadata plus matching immutable artifacts, or refuse to enable delivery; target unset | Database-only or object-only recovery can produce an unsafe partial service | Repeated restore drills, checksum reconciliation, key availability, and audit continuity |
| Runtime safety during service outage | Installed application behavior while control/distribution dependencies are unavailable | Preserve existing current/base state and fail closed for new artifacts; no availability percentage claimed | This is the most important cross-plane contract | Device offline/outage tests, state-v4 recovery tests, and power-loss evidence |

### Why numeric targets are not set yet

There is no hosted control plane, artifact edge, production database, queue,
or representative client fleet in the current evidence. Choosing a number now
would describe an aspiration as an observation and could hide the real cost of
cache misses, retry storms, artifact size, or tenant skew. The implementation
phase should publish a target only after:

1. a measured baseline exists for each dependency and client class;
2. the scope (managed service, self-hosted reference, or enterprise install)
   is explicit;
3. the target has an error-budget owner and an exclusion policy;
4. degraded behavior and security failures are not counted as success merely
   because the endpoint returned HTTP 200;
5. maintainers approve the target as a product claim.

## RPO and RTO candidates

RPO and RTO are also offering-specific design candidates. The following
qualitative objectives are safe defaults for review; no time or data-loss
number is asserted.

| Data or capability | Candidate RPO objective | Candidate RTO objective | Rationale and guard |
| --- | --- | --- | --- |
| Installed runtime state | Client-local state must not be erased or lowered by a server restore; server RPO is not authoritative | Runtime continues with current/last-known-good/AOT while the service is unavailable | This is a runtime invariant. It does not claim OS-level power-loss durability; Phase 1D evidence is limited to process/restart scope |
| Acknowledged patch/release artifact | No acknowledged immutable artifact may be silently replaced; restore must recover the exact digest or keep it ineligible | Restore artifact access before re-enabling promotion; duration unset | Object bytes and metadata are a coupled recovery unit |
| Release, rollout, and trust metadata | Recover to a transactionally consistent point and conservatively pause ambiguous rollout state | Restore read-only inspection first, then writes/promotion only after reconciliation; duration unset | A slightly stale policy is safer than a partially applied policy; trust changes need explicit review |
| Audit records | Retain according to the selected offering/customer policy; loss tolerance is explicitly agreed, not assumed | Restore query/export access after metadata and integrity checks; duration unset | Audit is operational evidence and may be regulated by customer policy, but no compliance claim is made |
| Optional telemetry | Event loss or delay is allowed within the declared sampling/retention policy | Resume ingestion eventually; never block runtime or artifact delivery | Observation is not authority |
| Control-plane service | Preserve authoritative data or enter read-only/degraded mode | Re-enable lookup, artifact fetch, then promotion in that order after health checks; duration unset | Prevents a fast but inconsistent recovery from creating unsafe eligibility |

The implementation plan must turn these into numeric RPO/RTO objectives only
after choosing backup frequency, replication, key recovery, object-store
semantics, and a customer support model. A self-hosted customer may select a
different objective from a managed offering, but the runtime trust invariants
do not vary.

## Backup, restore, and DR procedure

The future implementation should treat a recovery as a consistency exercise,
not merely a process restart:

1. Declare the service degraded and stop new promotion or rollout writes.
2. Preserve the existing audit and operator evidence, including the failed
   dependency and restore point.
3. Provision a clean control-plane boundary with the intended image and
   configuration; never restore into an unverified mixed version.
4. Restore PostgreSQL metadata, trust policy, idempotency records, and audit
   state to a known transactionally consistent point.
5. Restore immutable object bytes and compare every referenced digest,
   application, release, platform, and sequence binding.
6. Reconcile outbox/queue records. Duplicate work must be idempotent; missing
   work may be re-enqueued only from authoritative metadata.
7. Keep rollout state paused or read-only if any decision or artifact cannot
   be proved complete. Do not guess the intended promotion.
8. Verify key/KMS/offline-signer availability without generating an emergency
   trust root or accepting unsigned bytes.
9. Run synthetic lookup/fetch/verification checks, including a wrong-release
   and stale-candidate rejection check at the runtime boundary.
10. Re-enable artifact fetch, then lookup, then promotion/rollout in that
    order, with an append-only recovery audit event.

The procedure is a proposed runbook shape only. It must be rehearsed before
any production or enterprise readiness statement.

## DR evidence and test matrix

Before a later stage can make an HA/DR claim, test at least:

- single stateless process loss and restart;
- database connection loss, replica lag, and clean failover;
- object-store timeout, missing object, digest mismatch, and restore;
- Redis/Valkey loss with cache bypass;
- duplicate, delayed, and poisoned queue messages;
- KMS/offline-signer unavailability and key rotation/revocation review;
- edge/cache stale decisions and rollout pause propagation;
- region or cluster loss with a clean rebuild;
- import/export tampering and wrong-tenant/wrong-environment bundles;
- client offline behavior, service outage, pending candidate recovery, and
  signed rollback without lowering high-water;
- physical power-loss evidence where the Phase 1D conditions require it.

Test output must distinguish observed facts, injected-failure results,
assumptions, and untested cases. Coordinator session captures are not by
themselves an immutable production evidence service.

## Non-goals and claims boundary

This document does not implement backend services, schema migrations,
containers, Kubernetes resources, queues, dashboards, telemetry ingestion,
CDN integration, KMS adapters, or deployment automation. It does not claim
App Store or Google Play readiness, GDPR/DPDP/SOC 2/ISO compliance, hosted
availability, or capacity at any planning-envelope value.

The relevant deployment progression is in
[`self-hosted-operations.md`](self-hosted-operations.md), the staged gates are
in [`product-roadmap.md`](product-roadmap.md), and the evidence conditions are
in [`../product/phase-1d-conditions.md`](../history/product/phase-1d-conditions.md).

## P2 hosted-like evidence boundary (2026-08-23)

The P2 foundation now has a runnable single-node Compose reference with
PostgreSQL metadata, MinIO S3-compatible objects, and a containerized Dart
control plane. A disposable run restored PostgreSQL into a clean database and
preserved organization/application/environment identities, release/patch
metadata, promotion state, idempotency records, and audit rows. Artifact
metadata was restored; object-byte backup/restore remains a separate operator
responsibility and was not claimed as complete.

Injected database loss returned `/readyz` as `503` and recovered to `200`.
Injected object-store loss returned a bounded `503 DEPENDENCY_UNAVAILABLE`
for artifact fetch, and the same control-plane process fetched the verified
2,069-byte object after object-store recovery. These are
`END_TO_END_HOSTED_LIKE` and `BACKUP_RESTORE` observations, not availability,
RPO, RTO, or HA claims. The service metrics endpoint and bounded load script
provide measurement scaffolding; no production SLO has been selected.
