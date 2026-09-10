# Productization threat model

Status: Task 41 bounded local implementation and physical evidence recorded;
not a production audit, security certification, or store-policy approval.

<!-- Security evidence tables intentionally disable the line-length rule. -->
<!-- markdownlint-disable MD013 -->

This model extends the bounded Phase 1B/1C toolchain/runtime threat model to
control-plane, distribution, rollout, signing, telemetry, self-hosted, and
air-gapped product modes. It assumes the runtime remains the final client-side
safety boundary. A trusted server, CDN, KMS, HSM, organization, or operator
does not make downloaded code safe by declaration.

## Scope and security posture

In scope are tenants and organizations, applications and environments,
release/patch metadata, immutable artifacts, signing and trust transitions,
runtime update lookup/fetch, rollout policies, optional observations,
webhooks, self-hosted deployments, and offline transfer.

Out of scope are a rooted or fully compromised device, a malicious OS, secure
hardware implementation details, provider-specific KMS/HSM guarantees, a
production identity provider, and legal/store approval. Those exclusions are
not evidence that the risks are solved.

The primary invariant is:

```text
untrusted lookup/fetch/observation
        ↓
bounded runtime verification
        ↓
exact release + closed capability authority
        ↓
monotonic state-v4 high-water/replay and health-controlled activation
        ↓
current patch, last-known-good, or compiled AOT base
```

The control plane may choose availability. Only the release-owned runtime
authority may choose executable downloaded behavior.

## Assets

- release identity, build/runtime compatibility, function/signature records,
  capability v1 authority, and the compiled AOT fallback;
- exact Patch Format v1 bytes, artifact digests, signed rollback controls,
  key-lifecycle commands, and state-v4 high-water/replay records;
- signing private keys, recovery anchors, KMS/HSM authorization, CI tokens,
  webhook verification keys, and operator approval records;
- tenant/application/environment isolation, rollout policy, audit events,
  optional runtime observations, installation/cohort keys, and debug/source
  maps;
- source/build provenance and release metadata, without exposing source paths,
  secrets, user content, or private keys to runtime telemetry;
- availability of lookup and artifact delivery, while preserving the
  installed runtime state during an outage.

## Actors and trust assumptions

| Actor | Assumed capability | Required containment |
| --- | --- | --- |
| Unauthenticated network attacker | Modify, delay, replay, drop, or substitute transport bytes | Digest/signature/exact-release/high-water checks; TLS is defense in depth |
| Authenticated runtime caller with a stolen token | Request offers, fetch objects, submit observations, or cause load | Narrow scopes, rate limits, tenant binding, no signing/key authority |
| Compromised control plane | Change rollout pointers, metadata, cohort eligibility, audit availability, and delivery responses | Runtime remains authoritative; signing is separate; immutable artifacts and audit history limit impact |
| Compromised CDN/object store | Serve stale, corrupt, substituted, or unavailable bytes | Content addressing, exact digest, signature, release/capability/replay verification |
| Malicious or careless tenant/insider | Abuse RBAC, approve unsafe rollout, exfiltrate metadata, or misuse a key | Tenant isolation, least privilege, approvals, immutable audit, key separation, incident revocation |
| Compromised developer/CI workstation | Produce a malicious but correctly signed artifact or leak a key | Review/provenance, scoped signers, independent approvals, release-bound key lifecycle, runtime limits |
| KMS/HSM/API administrator compromise | Invoke an authorized signer, alter key policy, or block signing/recovery | Non-exportable scoped keys, separation of duties, approval/quorum policy, monitoring, recovery anchor |
| Self-host operator | Misconfigure storage, TLS, auth, retention, or import | Secure defaults, deployment checklist, customer-owned trust and explicit residual responsibility |
| Compromised device | Read/alter local app storage, observe runtime, or suppress telemetry | No claim of device tamper resistance; runtime fails closed where state is inconsistent |

## Trust boundaries and non-negotiable invariants

1. A distribution response is a hint. It cannot replace the runtime's bounded
   Patch Format v1 parsing, canonical/digest/signature checks, exact release
   binding, function/signature compatibility, resource limits, or capability
   v1 authority.
2. The control plane cannot lower or reset the runtime `(sequence, digest)`
   high-water, select a stale artifact, make a different digest valid at the
   same sequence, or turn a product rollback field into a runtime command.
3. A signed rollback is a separate canonical control and must match the exact
   durable release/high-water state. Returning to base retains high-water; a
   known-good behavior requires a newly signed higher-sequence artifact.
4. Downloaded code cannot add a host capability, enumerate reflection or
   native APIs, use arbitrary platform channels/FFI, or change package,
   manifest, entitlement, permission, or native-library surface.
5. Telemetry, dashboard status, webhooks, cohort membership, and audit views
   are observations or operator controls. None can authorize execution.
6. Network, CDN, control-plane, KMS, and telemetry outages preserve the local
   last verified state or AOT fallback. Cloud connectivity is not required for
   local runtime correctness.
7. Private keys never enter a patch, release artifact, ordinary control-plane
   record, runtime payload, or optional observation. Managed signing is an
   explicit custody choice with a separate threat model.

## Threat analysis

| Threat | Attack path and impact | Design controls | Residual risk / disposition |
| --- | --- | --- | --- |
| Cross-tenant isolation failure | Guess an application/object URL, alter a tenant ID in a request, query shared cache keys, or read another tenant's audit/observation/billing metadata | Authorize every request against an immutable tenant context; opaque IDs; tenant-qualified database/object keys; no cross-tenant CDN cache; separate encryption/access policies; deny-by-default service roles; isolation tests and audit review | A control-plane or deployment bug can expose metadata or artifacts. Treat as a release-blocking security incident; do not rely on object-path secrecy |
| Account, PAT, service-account, or runtime-token theft | Use stolen credentials to publish, promote, fetch private artifacts, read observations, or invoke emergency controls | Short-lived credentials; narrow scopes and environments; rotation/revocation; MFA for humans; separate runtime lookup tokens from signing/administrative tokens; request IDs/rate limits; two-person approval for production/key actions | A stolen authorized signing credential can produce a valid malicious artifact. Revoke/rotate through the release-owned trust process and retain high-water |
| Malicious insider or colluding operator | Approve an unsafe patch, change rollout/cohort, delete audit evidence, leak a key, or route observations to an attacker | Role separation (developer, release manager, security manager, auditor); append-only audit; immutable artifact history; protected environments; dual approval/break-glass logging; no single dashboard action signs bytes | Authorized insiders can still create legitimate behavior. Independent review, provenance, and key custody are required before production |
| Artifact substitution or corruption | Modify object bytes, response body, compression, range segments, or transfer media | SHA-256 content address of exact bytes; size/media checks; canonical Patch Format v1 digest and signature; exact release/runtime/capability checks; immutable storage and import inventory | A signer with malicious intent can sign new bytes. Signing-key compromise is handled separately; device compromise is out of scope |
| Artifact replay, downgrade, or equivocation | Serve an old valid patch, reuse a sequence after base rollback, or offer two digests at one sequence | State-v4 monotonic high-water, exact remembered artifact ledger, release/key lifecycle, signed rollback high-water match, product rollout cannot select `latest`; equal-sequence digest disagreement is rejected | Task 42 physically observed exact stale-byte rejection on both declared Android and iOS fixtures; broader beta confidence remains gated by durability/customer evidence |
| Control-plane compromise | Change release metadata, rollout status, cohort eligibility, artifact URL, or emergency pause; cause availability loss or targeted offers | Control plane is not a runtime trust root; immutable artifact digests; runtime checks every binding; scoped service accounts; append-only audit; independent signer/recovery anchor; fail-safe no-update behavior | A compromised control plane can suppress updates, misreport health, target clients, or trigger load. It can cause availability harm; it cannot forge a patch without signing authority |
| CDN/cache/object-store compromise | Poison cache, return a stale body, expose private objects, delete artifacts, or redirect to attacker infrastructure | Digest-addressed objects; origin authorization; private buckets; signed URLs as transport-only; no mutable `latest`; ETag/length checks; runtime re-verification; replication/backups | Confidentiality and availability may be lost if storage is misconfigured. Installed verified state must remain usable; object compromise cannot make bytes valid |
| KMS/HSM/provider compromise | Invoke a signing key, change key policy, export material, suppress recovery, or impersonate a signing service | Provider-neutral signer interface; non-exportable per-application keys where supported; least-privilege sign-only API; separate patch/authority/rollback/recovery roles; approval/quorum and audit; independent recovery anchor; key rotation/revocation | A provider is not a trust root for artifact semantics. If an authorized key signs malicious bytes, revoke it and publish a higher-sequence recovery artifact/control; no provider is implemented or endorsed here |
| Signing-key compromise or unsafe rotation | Leak developer/offline/CI private key, self-authorize an unknown key, or retire the only recovery path | Release-embedded trusted public keys; no downloaded key bootstrapping; signed add/retire/revoke/recover transitions; overlap rotation; bounded replay ledger; recovery anchor cannot be delegated; private key custody chosen explicitly | Key compromise can authorize behavior within the shipped capability surface until revocation propagates. Physical device evidence and production custody remain gates |
| Rollout or emergency-control abuse | Promote too quickly, target a sensitive cohort, pause all recovery, or use a dashboard flag as a rollback | Exact patch target; environment protection; deterministic pseudonymous cohorts; optimistic concurrency; conservative pause-only automation; signed rollback/key actions; audit and approvals; store-release gate | A policy error can cause broad availability or policy harm even when runtime security holds. Emergency actions require incident ownership and review |
| Telemetry spoofing or omission | Forge healthy/fault events, flood a tenant, suppress bad outcomes, or correlate installations into profiles | Optional events; bounded schemas/reason codes; sampling and rate limits; event IDs/deduplication; confidence/minimum-count thresholds; telemetry never controls runtime acceptance; no raw IDs/user content | Incomplete metrics can delay detection or cause a false pause. Absence of an event is never evidence of health |
| Privacy leakage through observations | Send source paths, payloads, stack traces, device IDs, user data, precise times, or linkable identifiers | Explicit minimal payload; random app-scoped installation token; keyed digest/pseudonymous cohort key; opt-in/configurable disablement; per-event sampling; retention/deletion/export; separate debug/source maps | Even pseudonymous release/installation data may be personal data in context. Product-specific privacy/legal review is required; no compliance claim follows |
| Webhook forgery or replay | Resend a valid event, alter body, use a retired key, or cause an external system to deploy/rollback | Canonical body digest/signature, key ID, timestamp window, event/delivery ID dedupe with expiry, key overlap/rotation, idempotent receiver, authenticated refetch and optimistic concurrency; webhook is notification only | Receiver misconfiguration can still cause an external side effect. Require endpoint ownership, least privilege, and manual approval for security-sensitive actions |
| SSRF and egress pivot | Register a webhook or artifact URL to loopback, cloud metadata, internal admin, private tenant service, or DNS-rebinding target | Prefer client upload/direct object storage rather than server-side fetch; allowlisted schemes/hosts; resolve and validate every hop; block loopback/private/link-local/metadata ranges; no ambient credentials; egress proxy and response-size/time limits; no arbitrary redirect chains | Customer-controlled self-host networks may have unusual address space. Make outbound fetch an explicit opt-in with per-tenant review and safe failure |
| Supply-chain compromise | Malicious compiler/CLI dependency, build action, container, signing library, base image, or generated release input emits a malicious artifact | Pin/review dependencies; reproducible or attestable builds; isolated build and signing stages; provenance bound to release; code review and release allowlists; verify tool/runtime/format versions; no private keys in build artifacts | A compromised build pipeline can produce correctly signed behavior. Runtime bounds reduce blast radius but do not replace independent source/provenance review |
| Self-hosted misconfiguration | Expose object storage, disable TLS/auth, share tenants, permit arbitrary URLs, lose audit, or run stale server/runtime versions | Single-node secure defaults; deployment checklist and health checks; customer TLS; external secret management; scoped service accounts; tenant-aware backups; explicit supported topology; import/export verification; local-only fallback | Customer chooses its own perimeter and may create exposure. Self-hosting documentation must state residual responsibility; no hosted SLO applies automatically |
| Air-gap import tampering or replay | Modify removable media, swap an artifact, import a wrong tenant/release, reuse an old export, or bypass review while disconnected | Signed transfer inventory; exact digest/size checks; offline signature and release/capability verification; import scope/approval log; idempotent bundle ID; state-v4 high-water/replay retention; no private key in bundle | Operators may intentionally override process. An offline signed artifact remains dangerous if the signer is compromised; incident recovery must be offline-capable |
| Audit deletion or repudiation | Rewrite rollout/key/rollback history or deny who approved an action | Append-only events, immutable storage/retention lock where available, actor/request IDs, signed export, separate audit access, clock/sequence validation, break-glass logging | A fully compromised deployment can destroy local evidence. Export to customer-controlled storage is a design option, not yet implemented |
| Store-policy evasion | Use a secure OTA channel to introduce hidden functionality, new data use, native behavior, billing changes, or unreviewed interpreted code | Dedicated Apple/Google change review; classify store-release-required boundaries; capability registry and release manifests; no reviewer/user branching; no marketing compliance claims | Security correctness is not policy approval. Policy outcome is app- and change-specific and remains an explicit pre-production gate |
| Rooted or fully compromised runtime device | Read keys/state, alter local files, hook the interpreter, suppress events, or execute arbitrary local behavior | App sandbox, checksums, dual-copy state, fail-closed recovery, no claim of device secrecy or tamper resistance | Out of scope for this productization design. Server telemetry cannot detect all local compromise |

## Signing and trust response

The signing choice changes key-custody risk, not runtime authority. Supported
design choices are developer-managed local/offline keys, organization-managed
keys, CI-triggered signing, non-exportable managed KMS/HSM signing, and fully
offline/air-gapped signing. The hosted control plane receives public trust
metadata and signed bytes by default, not private key material. A managed
signing product is an explicit opt-in whose provider adapters and policies are
not implemented here.

The release embeds trusted public-key state. Patch, lifecycle authority,
rollback, and recovery roles remain distinct; rotations overlap; retirement
does not erase remembered artifacts; revocation can invalidate even retained
artifacts; recovery cannot self-authorize a new recovery anchor. Any
compromise response must preserve exact release identity and high-water and
must use newly signed higher-sequence material for restored behavior.

## Privacy and data inventory

| Category | Examples | Default handling |
| --- | --- | --- |
| Required control-plane metadata | Tenant/application/environment IDs, release/patch IDs, artifact digests/sizes, rollout revisions, authorization and audit actor IDs | Collect for product operation; tenant-scoped and access-controlled |
| Optional runtime observations | Bounded lifecycle events, reason codes, coarse time, platform/runtime, pseudonymous installation/cohort key | Off unless application/operator opts in; sampled, retained briefly, and deletable |
| Security/audit | Key changes, approvals, auth/token events, rollout/emergency actions, webhook delivery | Append-only product security record with redaction and explicit retention |
| Debug/support | Optional source maps, build provenance, diagnostics | Separate access policy and retention; never in runtime telemetry |
| Secrets | Private signing keys, recovery material, KMS credentials, webhook verification secrets | Remain in the selected custody boundary; never in ordinary product records or artifacts |
| Billing/accounting | Commercial entitlement or invoice metadata | Separate product boundary; no runtime or telemetry dependency |

The design provides deletion/export and residency hooks but does not claim a
privacy or security certification. Exact retention, processor/subprocessor,
and end-user notice decisions need a product/legal owner for each deployment
mode.

## Store-policy gate

Apple and Google policy research remains separate from this threat model.
Interpreted code, UI/navigation, pure-Dart dependencies, data-use changes,
payments, and hidden functionality require change-specific review. New native
code, AOT output, manifests, entitlements, permissions, plugins, or native SDK
changes require a normal store release. A valid signature, safe rollout, or
closed capability registry does not prove App Store or Play approval. The
project must not state “App Store compliant,” “Play approved,” or an equivalent
claim without authoritative, app-specific evidence.

## Phase 1D limitations carried forward

| Evidence limitation | Disposition for future implementation |
| --- | --- |
| True physical power-loss interruption was not tested | **BLOCKER BEFORE PRODUCTION** for a production durability claim; require device/OS fault campaigns |
| Direct runtime rejection of supplied stale valid bytes was physically observed on the declared iOS and Android fixtures; broader customer-app and power-loss coverage remains open | **BLOCKER BEFORE BETA** for broad durability/customer confidence; the bounded direct device gate is closed for the declared fixtures |
| iOS runtime logs/UI and performance were unavailable due missing Developer Disk Image | **BLOCKER BEFORE IOS BETA** for iOS observability/performance claims |
| No fresh Phase 1D Android 15-sample performance reducer was run | **BLOCKER BEFORE PRODUCTION** for new Android performance/SLO claims |
| Adjacent Flutter 3.47.1/Dart 3.13.1 full CLI/device path is not isolated; status is `SUPPORTED_WITH_LIMITATIONS` | **ACCEPTED LIMITATION** in design; a compatibility gate is required before claiming support |
| Independent real customer-application validation was not run | **BLOCKER BEFORE BETA** for broad compatibility or customer-readiness claims |
| Additional async benchmark was not run | **BLOCKER BEFORE BETA** for async performance claims |

The current evidence remains fixture-level and process/restart-level where
stated. No product layer may hide, reinterpret, or promote these limitations
to a production claim.

## Task 41 local implementation evidence

The bounded `packages/control_plane` slice now exercises the following
controls with `UNIT` and `INTEGRATION` tests: credential hashing and scope
separation; organization/application/environment authorization; immutable
release, patch, and artifact records; exact release/runtime identity;
Ed25519 signature verification; content-addressed bytes and digest checks;
quarantine of invalid signatures, identities, and byte mutations; idempotent
registration; optimistic-concurrency promotion; all-or-none promotion
behavior; read-only delivery lookup/fetch; redacted audit records; and
parallel promotion conflict handling. The local `tool deploy` path has
`END_TO_END_LOCAL` evidence for registration, signed-byte admission, storage,
promotion, update lookup, and byte-for-byte fetch.

The host tests, Task 42 local E2E, and declared physical Android/iOS evidence
now prove bounded activation, direct supplied-byte stale rejection,
service-outage retention, rollback/high-water, and runtime-authoritative
verification. They do not prove physical power-loss durability, production
deployment hardening, managed key custody, compromised-device resistance, or
App Store/Play policy approval. Those remain explicit gates below and in
`tasks/41-productization-p0-p1-foundation.md`.

### Task 42 runtime-delivery update (2026-08-23)

The authenticated adapter and local service integration now have host and
local end-to-end evidence. The runtime remains authoritative: the adapter only
performs scoped lookup/fetch and transport checks, while E1 repeats Patch
Format v1 parsing, Ed25519 verification, exact release/function/capability
checks, high-water admission, health, and rollback. A delivery credential was
redacted from the generated release command and was not written to release
metadata.

Physical iOS evidence now includes both the direct stale-byte gate and a
generated authenticated bootstrap. The USB cross-feature receipt records
exact sequence-4 stale bytes rejected as `replayAfterRollback` with BASE and
high-water `4` preserved. The generated bootstrap changed ordinary pricing
from `540` to `450`, retained the patch across restart, and retained it when
the local service was stopped. This is fixture/device evidence, not a claim of
transport security, production availability, or store approval.

Android authenticated runtime evidence is now physical evidence on the explicit
Wi-Fi device `192.168.50.135:38657` (Redmi Note 10 Lite, Android 16/API 36).
The generated arm64 Release APK fetched the promoted signed patch through the
read-only adapter, changed the ordinary pricing receipt `540→450`, preserved
the patch across restart, and retained it after the local service was stopped.
The direct Android fixture also rejected invalid and stale bytes and preserved
the high-water/rollback boundary. This is bounded fixture evidence; it is not
production availability, transport-security, or store-policy evidence.

### Task 41 closure controls physically demonstrated

For the declared fixture/device runs, the evidence demonstrates that:

- the control plane cannot make invalid bytes valid because E1 re-verifies the
  exact Patch Format v1 bytes and release/signature bindings;
- the read-only delivery credential is not signing authority and private
  signing material is absent from service metadata and artifacts;
- stopping the local control plane does not clear verified local runtime state;
- exact stale valid bytes supplied after rollback are rejected by runtime
  high-water/replay checks;
- signed rollback returns to BASE without lowering high-water; and
- exact release identity remains authoritative at admission and activation.

These are bounded local/self-hosted fixture observations, not universal
production or customer-application guarantees.

## Remaining security validation before broader acceptance

The completed local phase must not be promoted to broader acceptance without
tenant isolation tests, object/cache authorization tests,
signer-role and revocation tests, malformed/replayed transfer tests, webhook
signature/replay tests, SSRF/egress tests, supply-chain provenance checks,
self-host hardening checks, and direct device stale-byte/power-loss campaigns.
The remaining validation is for beta/production claims; this document does not
waive those gates or authorize P2 managed cloud work.

## P2 hosted-like security review (2026-08-23)

The P2 implementation adds PostgreSQL and S3-compatible adapters without
changing the trust root. PostgreSQL records are tenant-filtered after
credential authorization; release, patch, artifact, promotion, idempotency,
and audit rows are immutable or concurrency-checked as appropriate. Artifact
objects are addressed by SHA-256, uploaded with an immutable precondition, and
re-hashed on download. The object store and database remain untrusted: an
invalid, truncated, wrong-release, or wrongly signed artifact cannot become a
runtime candidate through metadata alone.

Control credentials are hashed at rest, delivery credentials are read-only,
revocation is explicit, and request/rate/body limits are bounded. Structured
error logs include request IDs, normalized paths, safe codes, timestamps, and
durations; they exclude authorization headers, query values, bodies, tokens,
private keys, and patch bytes. `/healthz` is liveness, `/readyz` checks the
metadata dependency/migration boundary, and `/metrics` is process-local
aggregate operator measurement rather than runtime telemetry.

Residual risks remain intentionally open: TLS termination and proxy trust are
deployment responsibilities, private signing-key custody/rotation/recovery
is not managed by the service, object-byte replication is not implemented,
the Compose stack is not HA, and the service has not been tested against a
fully compromised device or production operator environment. These are
production gates, not reasons to weaken runtime verification.

## P3D observation-ingestion security boundary (2026-08-24)

The bounded P3D implementation adds an advisory observation channel without
changing the runtime trust root or rollout eligibility authority. PostgreSQL
schema version 2 stores observation bodies in a separate tenant-scoped table;
raw observation deletion does not touch artifacts, rollout revisions, audit
records, or other organizations. The local file adapter is suitable for
self-hosted single-node testing only.

Observation upload credentials are short-lived and scoped to one
organization/application/environment and `observation:write`. They cannot be
used on control, release, patch, artifact, credential, rollout, signing, or
audit mutations. Revoked and expired credentials fail closed. Event claims are
checked against trusted release, patch, environment, and rollout records;
client-supplied identity never authorizes a write.

Event IDs are unique within the tenant scope. A canonical retry is idempotent;
an event-ID reuse with a mutated body is rejected and audited. Schema version,
event vocabulary, platform, diagnostic code, safe metadata, timestamp skew,
late-data, body size, per-token/install/type rate, and retention limits are
bounded. Only scalar allowlisted metadata is accepted. Raw installation IDs,
source, patch bytes, stack traces, file paths, tokens, private keys, and user
business payloads are rejected. Impossible lifecycle sequences are stored as
quarantined observations and never become rollout/runtime truth.

The PostgreSQL rollout transition path now acquires a fixed advisory lock,
locks the current rollout row, checks the expected revision, and commits the
immutable revision, pointer, idempotency record, and audit-chain record in one
transaction. A stale concurrent writer receives a precondition failure; an
ambiguous retry can be replayed by idempotency key. Observation ingestion is
not on the runtime activation path, so its outage cannot block startup, AOT
fallback, patch activation, rollback, high-water, or existing delivery.

These controls are engineering evidence only. They do not establish privacy
compliance, store approval, provider production readiness, compromised-device
resistance, or a production availability guarantee.

## P3E-3 manual evaluation boundary (2026-08-24)

Task 56 adds an authenticated manual health-evaluation seam over immutable
P3E-2 evidence. The evaluator is advisory and cannot authorize executable
patch bytes, change Patch Format v1/capability v1, lower state-v4 high-water,
invoke rollback, or mutate a P3A rollout. `HALT_NEW_OFFERS` is a persisted
decision vocabulary value only until a separately reviewed P3E-4 CAS boundary.

| P3E-3 threat | Implemented mitigation | Residual risk |
| --- | --- | --- |
| Evaluation policy tampering or hidden defaults | Exact policy schema, supported version checks, caller-supplied minimums/quality limits, threshold-set digest, canonical policy digest, no source production thresholds | An authorized operator can intentionally select an unsafe test policy; production calibration and approval remain open. |
| Stale aggregate or rollout revision | Exact aggregate/revision/identity/window/input/policy digest binding, current P3A target/revision revalidation, reconciliation before evaluation, fail-closed stale error | Historical evidence remains readable outside the manual current-revision POST path; no P3E-4 transition exists yet. |
| Cross-tenant evaluation or read | Control credential scope checks, tenant-keyed P3E reads, body/path scope comparison, non-revealing 404s, negative API tests, redacted scope-rejection audit | A compromised deployment or storage operator can still bypass application-level isolation; deployment controls remain customer responsibility. |
| Idempotency mutation or concurrent duplicate | Deterministic evaluation/decision IDs derived from tenant/rollout/idempotency key, immutable equal-body acknowledgement, semantic digest conflict, PostgreSQL transaction/unique-key race tests | File adapter is single-node only; an operator can submit separate idempotency keys for separate historical evidence. |
| Privacy-suppressed leakage | No raw counters in request, aggregate-only input, suppression takes precedence to `INSUFFICIENT_DATA`, no installation bucket in evaluator/API response | Aggregate sensitivity, differencing, retention, and legal/privacy obligations remain deployment-specific. |
| Evaluation/audit reference divergence | Deterministic `auditReference` stored with new evaluations, redacted audit events for request/create/replay/conflict/scope/stale/evidence rejection, decision evidence references evaluation immutably | File/P3E and control-plane audit stores are separate adapters, so cross-store atomicity and off-box durability are not claimed. |
| Delivery/observer outage misclassified as patch failure | Explicit reason classes and precedence keep delivery/observation issues at `HOLD`/`INSUFFICIENT_DATA`; no runtime dependency | Missing evidence can delay detection or require manual review; thresholds and denominator calibration remain unresolved. |

The manual routes require `health:evaluate`, `rollout:read`, and
`observation:read`. They do not grant rollout mutation authority. The API
accepts no raw observations, installation identities, patch bytes, or client
counters, and no scheduler, worker, automatic halt, automatic expansion,
dashboard, mobile/runtime, signing, or provider key-custody path was changed.

The evidence is labelled `UNIT`, `MANUAL_EVALUATION`, `API_AUTHORIZATION`,
`TENANT_ISOLATION`, `IDEMPOTENCY`, `CONCURRENCY`, `STALE_INPUT`,
`MALFORMED_EVIDENCE`, `PRIVACY`, and `ENVIRONMENT_GATED` where applicable.
It is not `PHYSICAL`, `BETA`, or `PRODUCTION` evidence and does not close
P1D/provider/App Store/Google Play/legal readiness gates.

## P3E-1 deterministic aggregation core (2026-08-24)

Task 54 adds a storage-agnostic pure-Dart aggregation core over already
validated P3D records. The core binds each result to exact tenant,
application, environment, platform, release, patch, sequence, rollout
revision, window, observation schema, aggregation version, policy version,
canonical input digest, and bounded external-quality digest. It rejects mixed
scope and unknown versions before producing an aggregate.

The implementation sorts by server receipt time, event ID, and canonical event
body; deduplicates exact event IDs; taints mutated event IDs; and caps one
logical contribution per installation bucket/event type/checkpoint. Resource
limits bound record count, canonical bytes, diagnostic-code cardinality, and
quarantine-reason cardinality. Rejected/security-rejected request counts are
accepted only as explicit external quality context and never enter health
denominators. Aggregate output contains no installation-bucket values.

Executable vectors cover permutation determinism, duplicate mutation,
cross-scope rejection, late/sealed-primary behavior, quarantine reasons,
noisy-installation caps, small-cohort state, missing lifecycle evidence,
not-evaluable denominators, input/policy digests, and malformed/resource-bound
inputs. The core does not mutate rollout state, persist aggregates, expose an
API, schedule evaluation, or become runtime/signature/high-water/rollback
authority.

Residual risks remain: production thresholds, denominator calibration,
privacy suppression values, retention/deletion, independent-application
evidence, provider operation, and P3E-2/3/4/5 behavior are unresolved. This
addendum is implementation evidence for P3E-1 only, not complete P3E threat
closure or a beta/production/store-readiness claim.

## P3E-2 immutable persistence boundary (2026-08-24)

Task 55 adds storage for derived P3E evidence without changing the runtime trust
root. The domain boundary remains storage-agnostic: PostgreSQL and File adapters
accept validated typed records and persist canonical JSON, while runtime
signature verification, Patch Format v1, capability authority, high-water,
signed rollback, AOT fallback, and rollout eligibility remain authoritative
elsewhere.

Mitigations implemented for this slice include:

- immutable aggregate, revision, evaluation, decision-reference, and cursor
  records with deterministic canonical bodies and exact input/policy/external-
  quality digest preservation;
- strict entity, aggregation, evaluation, threshold, window, privacy, enum,
  timestamp, metric, and scope validation that fails closed on unknown or
  malformed persisted data;
- tenant-scoped PostgreSQL keys/queries and hashed File tenant paths, with
  wrong-tenant reads returning no record and no cross-tenant listing;
- PostgreSQL unique constraints, transactionally paired aggregate/revision
  inserts, reference checks, and idempotent equal-body retries; changed bodies
  are immutable conflicts rather than last-write-wins updates;
- atomic File writes, restart/reconnect round trips, bounded backup-copy
  evidence, cursor deletion that leaves authoritative evidence intact, and
  reconciliation that reports missing parents/references or binding mismatches
  without rewriting history; and
- explicit `RAW_RECOMPUTABLE`, `RAW_EXPIRED`, `RAW_DELETED_BY_POLICY`, and
  `INPUT_INCOMPLETE` metadata instead of silently claiming recomputability after
  raw observation deletion.

Residual risks remain. A compromised database, filesystem, operator, or backup
can delete or expose evidence; encryption, residency, retention periods,
multi-process File safety, provider durability, and legal/privacy compliance
are deployment responsibilities. Persistence corruption is fail-closed for
future evaluation use but does not repair historical records. P3E-2 does not
implement an evaluation API, automatic halt, rollout mutation, scheduler,
dashboard, or runtime action, and no beta/production/store-readiness claim is
authorized by these tests.

## P3E-4 conservative halt application boundary (2026-08-24)

Task 57 adds one authenticated application path for an existing P3E-3
`HALT_NEW_OFFERS` decision. It is a control-plane eligibility mutation, not a
runtime trust authority. The existing P3A expected-revision CAS remains the
only rollout-state writer for this operation.

| P3E-4 threat | Implemented mitigation | Residual risk |
| --- | --- | --- |
| Forged, stale, or cross-scope health evidence | Reload exact tenant-scoped decision, evaluation, aggregate, aggregate revision, rollout revision, complete target-binding digest, input digests, aggregate digest, and reconciliation state; reject mismatches before CAS | A compromised persistence operator can alter or delete evidence; deployment integrity and recovery controls remain open. |
| HOLD accidentally becoming a pause | Only `HALT_NEW_OFFERS` is transition-eligible; `HOLD`, `CONTINUE`, and other decisions persist `REJECTED` evidence and return a bounded non-applicable result | Future policy changes must preserve this explicit distinction. |
| Concurrent halt, expansion, or manual transition | Expected revision plus the existing PostgreSQL/File P3A CAS, deterministic transition idempotency key, and history-marker retry recovery | File storage is single-node; cross-store linkage is recoverable but not a distributed transaction. |
| Duplicate or mutated retry | Required idempotency key, canonical request body, immutable application ID/body, equal replay, and changed-body conflict | Separate idempotency keys can create multiple immutable attempt records, but cannot create a second halt transition. |
| Tenant or scope escalation | `health:evaluate`, `rollout:read`, and `rollout:halt` are all required; foreign resources use non-revealing failure behavior and redacted audit events | Provider/operator credential custody and network termination remain deployment responsibilities. |
| Malformed persisted evidence or byte-level corruption | Strict typed decoding, digest/reference validation, bounded error handling, and no transition on evidence failure | Historical evidence is not repaired automatically; reconciliation remains an operator concern. |
| Halt weakens runtime safety | The path changes future offer eligibility only; it cannot alter Patch Format v1, capability authority, signatures, artifacts, high-water, signed rollback, AOT fallback, or installed state | Broader production/store/legal readiness and independent-app evidence remain open. |

The application outcome is append-only in File and PostgreSQL migration 004,
and its audit reference is recorded through the existing redacted audit chain.
Evidence labels for this slice are `UNIT`, `API_AUTHORIZATION`,
`TENANT_ISOLATION`, `IDEMPOTENCY`, `CONCURRENCY`, `STALE_INPUT`,
`MALFORMED_EVIDENCE`, and `ENVIRONMENT_GATED`; there is no physical-device,
beta, production, provider-SLO, App Store, Google Play, or legal-compliance
claim. P3E-5 scheduling and automatic evaluation remain unauthorized until a
new design review.

## P3E-5 scheduled-evaluation design boundary (2026-08-24)

Task 58 proposes a durable cooperative scheduling boundary without adding an
implementation or changing runtime trust. PostgreSQL is the proposed
multi-instance claim authority; File remains single-process. At-least-once
attempts are expected and are bounded by deterministic work identity,
P3E-3/P3E-4 idempotency, P3A expected-revision CAS, and reconciliation.

| P3E-5 threat | Required design mitigation | Residual risk |
| --- | --- | --- |
| Duplicate workers | Canonical logical key/work ID, token/work-version claims, downstream idempotency, one P3A CAS effect | Duplicate compute and attempt evidence can still occur. |
| Stale work or manual-action race | Exact rollout/target/window/policy/schedule binding and repeated revalidation; final P3E-3/P3E-4/P3A stale rejection | Races remain possible after a check but cannot silently overwrite a newer revision. |
| Lease theft/stale completion | Random token, persisted digest, scoped owner, database time, expiry, and CAS | Database/operator compromise remains a deployment risk. |
| Worker impersonation | Dedicated rotatable tenant/application/environment scheduler principal with minimal claim/evaluate/read and optional halt scopes | Current auth does not provide this principal; implementation is blocked until it does. |
| Cross-tenant claim/enumeration | Tenant in every key/query/claim, non-revealing APIs, negative tests | Storage/operator compromise remains outside application isolation. |
| Starvation/retry storm | Per-tenant/global concurrency, bounded batches/attempts/backoff/jitter, starvation-resistant claim order | Production bounds need load evidence. |
| Clock skew/client timestamp abuse | Database/server time controls readiness, leases, retry, and schedule activation; client time cannot trigger work | File host clock remains operator responsibility. |
| Policy tampering/automatic-halt abuse | Immutable versioned schedule revisions, separate default-off evaluation/halt flags, sealed evidence, least privilege, audit, P3E-4 validation | Authorized unsafe policy or false-positive thresholds remain calibration/governance risks. |
| Crash/cross-store divergence | Deterministic downstream IDs, append-only attempts, expiry/reclaim, bounded reconciliation, no 2PC claim | Some outages require operator reconciliation. |
| Observation/delivery outage misclassification | Preserve P3E-3 reason classes and `HOLD`/`INSUFFICIENT_DATA`; no conversion to healthy/halt/expansion | Missing data can delay a needed halt. |

`CONTINUE` never expands, `HOLD` never pauses, terminal P3A rollouts are never
unhalted, and no scheduler path writes rollout state directly. The scheduler is
not available to the Flutter runtime and cannot change patch validity,
signatures, capabilities, high-water, rollback, AOT fallback, artifacts, or
installed state.

This is design evidence only. No scheduler, worker, queue, table, migration,
automatic halt, dashboard, provider SLO, beta, production, App Store, Google
Play, privacy, or legal claim is implemented or closed by Task 58.

## P3E5-1 schedule/work persistence boundary (2026-08-24)

Task 59 implements storage and authorization preparation only. It does not
execute scheduled work or create lease authority.

| P3E5-1 threat | Implemented mitigation | Residual risk |
| --- | --- | --- |
| Scheduler credential over-privilege | Dedicated app/environment-scoped credential kind; bounded scope universe; evaluation-only default profile; optional halt grant; expiry/revocation and redacted audit | Credential custody, rotation procedure, and provider identity integration remain deployment concerns. |
| Cross-tenant schedule/work access | Tenant in every entity, hashed File path, PostgreSQL composite keys/indexes, exact auth scope checks, and non-revealing foreign reads | Filesystem/database/operator compromise is outside application-level isolation. |
| Logical identity collision or mutation | Versioned canonical key, domain-separated SHA-256 IDs, persisted key digest, equal-body acknowledgement, and changed-body conflict | Cryptographic collision is treated fail-closed; hash agility would require a reviewed version change. |
| Schedule-policy tampering | Immutable revision rows/bundles, explicit versions/digests, generation lineage, and expected-current-pointer CAS | An authorized administrator can still choose an unsafe future policy; governance remains open. |
| Revision-pointer race | Atomic File bundle replacement and PostgreSQL row lock/CAS preserve one current pointer and all old revisions | File mode is one writer only; cross-store audit append is not a distributed transaction. |
| File multi-process misuse | In-process root guard plus non-blocking OS file lock rejects a second writer | Network-filesystem lock semantics and host failure recovery require deployment validation. |
| Malformed persisted work | Exact-key codecs, supported enums/versions, ID/digest recomputation, lease-field consistency, timestamps, byte/string bounds, and read-only consistency checks | Corrupt records are rejected/reported, not repaired automatically. |
| Premature execution | No due query, lease generation, claim, worker, timer, retry, P3E-3 invocation, or P3E-4 invocation exists | P3E5-2 onward requires separate authorization and new threat review. |

Patch Format, capabilities, signatures, state-v4 high-water, rollback, AOT
fallback, artifacts, and installed runtime state remain outside this principal
and persistence boundary.

## P3E5-2 claim/recovery boundary (2026-08-24)

| P3E5-2 threat | Implemented mitigation | Residual risk |
| --- | --- | --- |
| Duplicate PostgreSQL claimants | Database-time transaction, bounded indexed selection, `FOR UPDATE SKIP LOCKED`, work-version CAS, and unique attempt number | Provider failover, isolation tuning, and production load remain provider-readiness gates. |
| Stale token replay or owner substitution | Fresh 256-bit token, digest-only persistence, and exact scope + owner + digest + work-version + state + expiry validation | Database/operator compromise remains outside application fencing. |
| Crash before/after claim commit | PostgreSQL rollback/lost-response seams and durable lease readback; File claim journal completes work/attempt persistence on restart | A claimant that loses its raw token waits for expiry; no heartbeat exists. |
| Expired claim reuse | Reclaim revalidates current schedule binding, increments attempt/version, generates a new token, and rejects the old token | Rollout revalidation is fail-closed before return, but is not a distributed transaction with schedule persistence. |
| Retry storm or starvation | Maximum attempts, deterministic bounded backoff/jitter, bounded consideration/batch/recovery, active-lease cap, and round-robin schedule selection | Cross-tenant fleet dispatch and production values require executor/load evidence. |
| Secret leakage | Raw token exists only in the response; work/attempt/audit retain one-way digest; audit tests reject raw-token presence | Claimant memory/logging remains an executor responsibility. |
| Malformed operational state | Strict lease-state/error codecs, timestamp/order/bounds checks, CAS conflict, and fail-closed reads | Corrupt history is not automatically repaired. |
| Privilege expansion | Claim requires scheduler kind + exact app/environment + `health:work:claim`; evaluate/halt scopes are not required | Credential custody and provider identity integration remain open. |

No claim-side path invokes P3E-3 evaluation or P3E-4 halt. No worker, timer,
queue, automatic expansion, HOLD-to-pause, runtime trust, mobile change, or
release-readiness claim is introduced.

## P3E5-3 explicit executor boundary (2026-08-24)

| P3E5-3 threat | Implemented mitigation | Residual risk |
| --- | --- | --- |
| Executor credential overreach | Exact scheduler kind/app/environment plus claim, evaluate, observation-read, and rollout-read scopes; halt scope is not required or consumed | Credential custody and provider workload identity remain production gates. |
| Duplicate evaluation execution | P3E5-2 cooperative claim plus deterministic `scheduled-evaluation:<workId>` evaluator idempotency | The schedule, rollout, and evidence stores are not one distributed transaction. |
| Stale rollout or target evaluation | Current schedule generation, current rollout revision/state, exact target digest, release, patch, sequence, platform, and policy digests are reloaded after claim | A current binding can change after revalidation; lease fencing and downstream evaluator currentness fail closed, but no global lock exists. |
| Premature window execution | Aggregate window phase is re-derived from authoritative lease-acquisition time; `CLOSED` and `SEALED` thresholds plus `notBefore` are checked before evaluation | File mode depends on the single-node operator clock; PostgreSQL claim time is database authoritative. |
| Lease expiry and old-token replay | Every transition checks exact scope, owner, digest, version, state, and unexpired lease; expiry recovery issues a new token/version | Long evaluation duration may force idempotent replay after expiry; no heartbeat is implemented. |
| Cross-tenant starvation | Canonical scope ordering and explicit caller-retained round-robin cursor under bounded work/tenant limits | Fleet cursor durability and provider-wide load calibration remain caller/operator responsibilities. |
| Evaluation/link divergence | Aggregate/revision links persist before invocation; evaluation/decision links persist before completion and are rebound to tenant, rollout, target, aggregate, decision, and idempotency identities on recovery | Broad fleet reconciliation and repair remain P3E5-5 work. |
| Crash after evaluator commit or lost response | Immutable evaluator evidence plus deterministic idempotency permits bounded replay from `EVALUATING`; `EVALUATED` recovery completes only non-halt outcomes | Recovery waits for lease expiry when the claimant response is lost. |
| Automatic-halt boundary bypass | `HALT_NEW_OFFERS` stops at `EVALUATED`; no P3E-4 call, `HALT_APPLYING`, rollout CAS, pause, or expansion exists in this executor | Optional automatic halt requires a separate design/review and authorization. |
| Malformed or excessive evidence | Strict codecs and exact bindings; aggregate load/work and invocation limits; malformed/missing evidence fails without process termination | Production limits and adversarial provider-scale testing remain unresolved. |

Audits record bounded executor/work identifiers, versions, attempts, and
evaluation/decision IDs. They exclude raw lease tokens, scheduler credentials,
observation/user payloads, patch bytes, private keys, stacks, and paths. This
slice adds no runtime/mobile trust and makes no beta, production, provider, or
store-policy claim.

## P3E5-4 automatic-halt design boundary (2026-08-24)

Task 62 defines a future fail-closed boundary; it does not implement or enable
automatic halt. Scheduled evaluation and halt application remain separate
authorities. A future application must hold both the current fenced work lease
and a distinct exact-scope Auto-Halt Principal, then reuse the existing P3E-4
validation and P3A expected-revision CAS.

| P3E5-4 threat | Required design mitigation | Residual risk |
| --- | --- | --- |
| Automatic-action abuse | Default-off immutable policy; scheduled, `SEALED`, `PATCH_SAFETY` evidence only; separate implementation, policy-approval, and production-enablement states | An authorized unsafe policy remains a governance risk. |
| Compromised evaluator | Evaluation credential has no halt scope; halt requires a separately issued Auto-Halt Principal and a current fenced lease | Collusion or compromise of both principals remains a deployment risk. |
| Compromised Auto-Halt Principal | Exact tenant/application/environment scope and only `health:work:apply-halt`, `rollout:read`, and `rollout:halt`; no claim/evaluate/admin/sign/artifact authority | Credential custody and provider workload identity remain production gates. |
| Observation poisoning | Only immutable scheduled aggregate/evaluation/decision evidence with exact digests and `PATCH_SAFETY` classification is eligible | Validly ingested false observations can still cause a false-positive halt; calibration remains open. |
| Stale evidence or policy downgrade | Approved policy version/digest, maximum aggregate and decision ages, exact schedule/rollout/target bindings, and no reinterpretation of logical-key v1 | Bad approved bounds or compromised policy governance remain residual risks. |
| Schedule/manual-action race | Revalidate immediately before application; existing P3E-4 currentness checks and P3A expected-revision CAS decide the race | The loser may produce a stale/rejected immutable record and require reconciliation. |
| Duplicate application | Deterministic `scheduled-halt:<workId>`, immutable P3E-4 application evidence, and P3A idempotency/CAS | Duplicate compute and audit attempts can occur. |
| Crash across stores | `EVALUATED -> HALT_APPLYING -> COMPLETED`, lease expiry/reclaim, immutable P3E-4 history marker, and bounded reconciliation; no 2PC claim | Recovery may wait for lease expiry and needs operational visibility. |
| Cross-tenant application | Tenant in work, principal, evidence, target, request, persistence, audit, and all lookup/CAS predicates; foreign IDs fail non-revealingly | Storage/operator compromise remains outside application-level isolation. |
| Production misconfiguration | Separate `AUTO_HALT_IMPLEMENTED`, `AUTO_HALT_POLICY_APPROVED`, and `AUTO_HALT_PRODUCTION_ENABLED` states with two-person control and startup fail-closed validation | Provider process and human governance require later production evidence. |

The automatic path must never write rollout rows directly, broaden eligibility,
expand/start/resume/promote a rollout, convert `HOLD` to pause, roll back or
unhalt, lower runtime high-water, alter artifact validity, or invalidate an
installed healthy patch. Production values, provider deployment, and beta,
production, store, privacy, or legal claims remain unapproved.

## P3E5-4A implemented foundation boundary (2026-08-24)

Task 63 implements policy identity and authority separation, not automatic
halt application.

| P3E5-4A threat | Implemented mitigation | Residual risk |
| --- | --- | --- |
| Scheduler credential escalation | Scheduler scope universe excludes both `rollout:halt` and `health:work:apply-halt`; regression tests reject the former grant | Scheduler compromise can still disrupt bounded evaluation work. |
| Partial or broad Auto-Halt Principal | New credential kind requires exactly apply-halt, rollout-read, and rollout-halt; subsets/supersets and other kinds fail | Custody and provider workload identity remain production gates. |
| One-authority application | Typed future authority requires an exact-scope lease plus current unexpired/unrevoked Auto-Halt Principal | P3E5-4B must revalidate both against persisted current work before any transition. |
| Historical-policy reinterpretation | V1 bytes/identity remain unchanged and eligibility is always false; v2 conditionally binds all automatic semantics | Future decoder/version changes require regression evidence. |
| Policy downgrade or cross-scope binding | Current immutable environment-state policy must match tenant/application/environment, ID, version, and digest before v2 schedule creation | Approval governance and calibrated values remain unimplemented. |
| Malformed File/PostgreSQL content | Strict codecs, canonical digest recomputation, versioned atomic File bundle, scope/lineage checks, SQL constraints, and transactional readback | Database/filesystem/operator compromise remains outside application isolation. |
| Implementation mistaken for enablement | Service-created state is always unapproved and production-disabled; no approval/enable API exists | A later unsafe workflow could weaken this unless separately reviewed. |
| Secret/audit leakage | Hash-only credential persistence and bounded metadata; raw credentials and lease tokens are excluded and tested | Caller memory/logging remains an operational responsibility. |

Migration 007 contains policy/state tables only. No new source path enters
`HALT_APPLYING`, invokes P3E-4/P3A, or writes rollout state. Runtime trust,
artifacts, signing, high-water, rollback, and mobile behavior are unchanged.

## P3E5-4B applicability/intent boundary (2026-08-24)

| P3E5-4B threat | Implemented mitigation | Residual risk |
| --- | --- | --- |
| Lease-only or principal-only mutation | Store transition requires a typed exact-scope authority containing both current lease material and the dedicated principal | Combined credential/lease compromise remains harmful within the exact scope |
| Stale policy/schedule/rollout | Exact current records, versions, generations, enablement, target digest, eligible rollout state, and authoritative freshness are reloaded before commit | Schedule, P3E, and rollout stores are not one distributed transaction; P3E-4 must revalidate before any future mutation |
| Manual or unsuitable decision substitution | V2 scheduled idempotency, exact work links, `HALT_NEW_OFFERS`, `PATCH_SAFETY`, `SEALED`, and successor checks fail closed | Unsafe but valid approved thresholds remain a governance risk |
| Duplicate applicability executors | Work-row lock/version CAS plus canonical semantic intent digest converges equal attempts; changed intent conflicts | Duplicate computation/audit records may occur before convergence |
| Crash/lost response | Intent is embedded atomically in the new work version; pre-commit failure leaves no intent and post-commit retry discovers the same intent | File mode remains single-host/single-writer; provider failover is unproven |
| Generic transition bypass | `HALT_APPLYING` work is invalid without a fully bound intent, so the generic executor cannot manufacture the state | Future codecs/transitions require regression review |
| Secret or business-data leakage | Intent and audit contain bounded IDs/digests only; raw lease/principal tokens, observations, user data, stacks, and paths are excluded | Caller process memory and provider logging remain operational concerns |
| Intent mistaken for applied halt | Applicability service has no P3E-4/P3A dependency and creates no rollout revision | P3E5-4C must preserve this separation and revalidate everything |

Runtime trust, artifact/signature validity, state-v4 high-water, rollback, AOT
fallback, and mobile code remain unchanged. This evidence authorizes no
production enablement or readiness claim.

## P3E5-4C application boundary (2026-08-24)

| P3E5-4C threat | Implemented mitigation | Residual risk |
| --- | --- | --- |
| Automatic path bypasses P3E-4/P3A | One adapter delegates to the existing P3E-4 evidence/application core and P3A expected-revision CAS; no rollout writer exists in the adapter | Cross-store state is not one global transaction |
| Stale evidence reaches delivery mutation | Fresh schedule, policy, freshness, P3E, rollout, target, intent, lease, and principal reload precedes the shared core; P3A CAS remains authoritative | A later store change can still race until the CAS; provider HA is unproven |
| Duplicate automatic halt | Exact `scheduled-halt:<workId>` key, immutable application evidence, P3A history linkage, and completion proof converge retries | Recovery/reclaim after lease expiry is deferred |
| Work is marked complete without a halt | Generic completion rejects `HALT_APPLYING`; the schedule store requires bounded application linkage, revision increment, transition reference, and applied result | Malformed future codecs/transitions require regression review |
| Crash/lost response leaves ambiguous state | File atomic replacement, PostgreSQL row/CAS transaction, terminal replay, and failure-seam tests distinguish pre-commit, post-P3A, and post-completion cases | File is single-writer; PostgreSQL tests are fixture-local |
| Credential or lease disclosure | Auto-Halt Principal and lease are revalidated; proof, intent, and audit metadata contain bounded IDs/digests only | Caller/process/provider logs remain operational concerns |
| Automatic application mistaken for production enablement | Test fixtures explicitly say `TEST VECTOR ONLY — NOT PRODUCTION POLICY`; approval and production enablement remain false/absent | Future enablement workflow requires a new security and maintainer review |

P3E5-4C does not alter runtime trust, signed artifacts, high-water, rollback,
AOT fallback, mobile behavior, or store-policy status.

## P3E5-4D recovery/race-hardening boundary (2026-08-24)

| P3E5-4D threat | Implemented mitigation | Residual risk |
| --- | --- | --- |
| Expired lease causes a blind duplicate halt | Evidence-first lookup, deterministic key, exact P3E-4/P3A linkage, and one expired-work reclaim CAS before retry | A recovery worker can remain retryable until a bounded later invocation |
| Generic scheduler steals auto-halt work | `claimDue` excludes `HALT_APPLYING`; only the auto-halt recovery seam can reclaim it | A future scheduler change must preserve this exclusion |
| Old claimant completes after reclaim | Work version, owner, digest, and expiry fence every completion; old-token regression test rejects it | Credential/lease custody remains an operational concern |
| Reclaim inherits a successor or wrong target | Reclaim preserves the immutable intent/key/target and the application adapter revalidates current P3E/P3A evidence | Cross-store reads are not one distributed transaction |
| Malformed or foreign linkage is repaired by guesswork | Duplicate, incomplete, stale, scope-mismatched, and oversized evidence returns a bounded rejection outcome; no repair path exists | Storage/operator compromise remains outside application-level isolation |
| Stale rollout leaves an active retry loop | Fresh lease is fenced to terminal stale work and clears the automatic intent | Manual/operator reconciliation is still required for broader scheduling policy |
| Lost response or restart | File atomic replacement/reopen and PostgreSQL row-lock/CAS tests reload work/application evidence before retry | Provider disconnect/reconnect and HA behavior remain unproven |
| Unbounded recovery resource use | Explicit maximum recovery attempts, application records, and linkage records are required inputs | No fleet-capacity or race-storm claim is made |

Task 66 does not add heartbeat, rollout actions, runtime/mobile behavior,
production enablement, telemetry, or store/legal readiness claims. Audit
append remains secondary to immutable application/work linkage; the Task 67
local PostgreSQL fault vectors are bounded evidence only and do not close
provider-HA review.

## P3E5-4E integration evidence boundary (2026-08-24)

| P3E5-4E threat | Evidence-backed mitigation | Residual risk |
| --- | --- | --- |
| Audit outage before application | Fault-injected audit append fails closed before P3E-4; persisted intent is recovered through the existing bounded path | Audit provider durability and reconnect behavior are not established |
| Audit divergence after P3A | A committed immutable application and halted P3A revision remain authoritative; missing secondary audit evidence is not used to undo the halt | Reconciliation/operator workflow is still required |
| Provider-like reconnect during recovery | PostgreSQL store close/reopen after a lost reclaim response reloads work and converges on one application | Exact disconnect injection at every transaction boundary and provider HA remain unproven |
| Lease too short for bounded path | File timing and explicit test-lease margin are recorded; heartbeat is not introduced | Production latency and lease defaults remain open |
| Recovery race/resource exhaustion | Eight-caller File/PostgreSQL envelopes enforce attempt, evidence, and linkage bounds | Local envelope is not production capacity or fleet fairness evidence |
| Evidence leakage | Audit/recovery assertions and changed-scope scans reject raw credentials, lease tokens, private-key markers, and host-specific secrets | Complete operational log review remains future work |

Task 67 evidence is bundled at
`docs/research/evidence/p3e5-4e-2026-08-24/`; no production, beta, store, or
provider-HA claim follows from it.

## P3E5-5 reconciliation/observability design boundary (2026-08-24)

Task 68 is design-only. The proposed model uses bounded startup and explicit
tenant-scoped reconciliation, not a periodic worker or managed queue.

| P3E5-5 threat | Proposed mitigation | Residual risk |
| --- | --- | --- |
| Reconciler privilege abuse | Exact `health:reconcile`, `health:read`, and `rollout:read` scope; no rollout/signing/artifact authority | A scoped operator can still damage its own operational projection |
| Repair replay or stale repair | Deterministic finding/action IDs, fresh reload, work-version/lease/schedule/rollout CAS | Cross-store races can leave a report-only finding |
| Cross-tenant reconciliation | Scope in principal, queries, storage keys, findings, diagnostics, and audit | Storage/operator compromise remains a deployment risk |
| Projection poisoning | Repair only from exact validated immutable sources; immutable conflicts report-only | A compromised source store remains a system-level risk |
| Metrics-cardinality denial of service | Allowlisted labels, unknown buckets, bounded series and page/history limits | Misconfiguration can reduce visibility |
| Diagnostic leakage | Read-only scoped authorization, opaque IDs, bounded safe fields, non-revealing foreign errors | Authorized operators can view their tenant's operational metadata |
| Alert spoofing | Alerts derive from bounded metrics/findings and have no control authority | False alerts can consume operator attention |
| Audit/reconciliation divergence | Append-only audit, deterministic repair evidence, fail-closed tamper handling | Provider durability/HA remains unproven |

Observability cannot trigger rollout expansion, pause, rollback, resume, or
unhalt. P3E5-5 implementation, production readiness, beta, store, and legal
claims remain open.

## P3E5-5A domain implementation boundary (2026-08-24)

| Threat | Implemented mitigation | Residual risk |
| --- | --- | --- |
| Reconciler privilege abuse | Domain principal is exact application/environment scope with only `health:reconcile`, `health:read`, and `rollout:read`; action metadata rejects rollout mutation | No persistence or endpoint authorization adapter exists until P3E5-5B |
| Repair replay or changed repair body | Finding/action IDs and precondition digests are deterministic; equal canonical bodies are replays and changed bodies are conflicts | Durable conflict records are deferred to P3E5-5B |
| Stale precondition | Precondition binds scope, finding/entity, source digests, target binding, work version, schedule/rollout revision, taxonomy, and action | A future executor must reload and CAS all current state |
| Cross-tenant finding/repair | Scope is part of finding identity, repair identity, cursor, principal, and audit metadata; exact-scope checks fail closed | Entity ownership still requires source-store validation in P3E5-5B |
| Malformed taxonomy or policy | Unknown versions/enums, invalid digests, inconsistent bounds, noncanonical JSON, and oversized bounded values reject with typed format failures | Future persisted codecs must preserve the same rejection rules |
| Immutable evidence poisoning | Immutable source vocabulary is explicit and report-only; no source mutation API is exposed | A compromised source store remains a system-level risk |
| Audit redaction failure | Audit event type has only opaque IDs, typed codes/actions/results, digests through source records, safe error codes, and bounded counts | Caller/provider logs remain outside this domain module |

P3E5-5A adds no rollout, signing, artifact, runtime, P3E-4, or P3A authority.
The implementation is not persistence, production, beta, store, legal, or
provider-readiness evidence.

## Provider deployment design boundary (2026-08-25)

Task 76 extends this threat model for a future provider deployment without
changing the runtime trust root. New provider threats include account or
operator compromise, database/object-store compromise, edge misconfiguration,
image and base-image supply-chain compromise, backup compromise, and secret
misuse. The design controls are:

- customer/local patch signing remains separate from provider administration;
- runtime signature, release, capability, sequence, and high-water checks stay
  authoritative;
- database/object/edge identities are private and least-privileged;
- immutable bytes are digest checked and reconciled;
- image digest, SBOM, vulnerability, and provenance gates precede deployment;
- audit remains append-only and is independently verified;
- database and object backups are encrypted, access-controlled, and restored
  together; and
- provider failure preserves local runtime state or the AOT fallback.

Provider-specific failover, durability, power-loss, independent-app, iOS,
store, privacy, legal, beta, and production gates remain open. No provider
was selected and no provider resource or credential was created. See
`docs/PROVIDER_DEPLOYMENT_DESIGN_REVIEW.md` and Task 76.

## P3E5-5B bounded reconciliation implementation boundary (2026-08-24)

| Threat | Implemented mitigation | Residual risk |
| --- | --- | --- |
| Reconciler privilege abuse | Exact-scope administrator authorization, frozen health/read/rollout-read scopes, typed detector/executor seams, and no rollout/P3E-4 calls | A deliberately supplied executor can still damage its own projection; concrete adapters require a separate review |
| Repair replay or stale repair | Canonical immutable bodies, deterministic repair IDs, precondition digest, optional fresh reload, CAS lifecycle/cursor, and postcondition verification | A real external CAS adapter must still prove its race behavior |
| Cross-tenant reconciliation | Tenant is part of every finding/repair key and every persistence query; foreign scope reads return no record | Source detectors must preserve exact application/environment filtering |
| Projection poisoning | Immutable divergence is report-only; only injected typed actions can mutate; audit request precedes execution | The generic seam is not evidence that a production projection adapter is safe |
| Startup resource exhaustion | Explicit policy records, tenant/global caps, stable cursor/backlog, and no timer/queue | Detector implementations must bound their own authoritative reads |
| Corrupt finding/repair persistence | Canonical File JSON, strict codecs, body digests in PostgreSQL, schema migration, size limits, and fail-closed parsing | Provider/operator filesystem/database compromise remains outside the application boundary |
| Audit divergence | Existing audit chain is verified before a repair request; post-repair audit loss is surfaced without undoing the committed projection | Audit provider durability and reconnect behavior remain readiness gates |

Task 70 adds no metrics, readiness, diagnostics, rollout mutation, P3E-4
application, runtime/mobile change, provider deployment, or production/store
claim. Concrete source detectors and existing CAS repair adapters remain open
P3E5-5B work.

## Provider selection decision boundary (2026-08-25)

Task 77 records a proposed first disposable provider profile: AWS
ECS/Fargate, an active ALB, RDS PostgreSQL Multi-AZ DB cluster, S3,
ACM/Route 53, VPC, task IAM roles, Secrets Manager, ECR, CloudWatch, and AWS
Backup in Mumbai (`ap-south-1`). The selection is not approved for
implementation and does not imply provider, beta, production, store, privacy,
or legal readiness.

| Provider-selection threat | Design control | Residual / unverified risk |
| --- | --- | --- |
| Provider account or operator compromise | Least-privilege workload/operator roles; private data paths; audit and review; no provider role can mint patch signatures or lower runtime high-water | Provider account/IAM incident response, break-glass access, and independent review remain open |
| Database compromise or failover ambiguity | PostgreSQL remains coordination authority; writer endpoint, CAS/idempotency, transaction ambiguity, and session-loss behavior are explicit acceptance tests | Real RDS failover, pool recovery, advisory-lock loss/reacquisition, PITR, and connection limits are not tested |
| Object deletion or rollback evidence loss | Digest-addressed immutable bytes, versioning/delete recovery, least-privilege delete, exact-byte rehash, retention and reconciliation | Durability, lifecycle, accidental-delete recovery, and provider outage behavior require a disposable test |
| Edge routes an unready replica | Active `/readyz`, drain, application fail-closed behavior, and private operator paths | AWS ALB documents fail-open routing when all targets are unhealthy; exact mitigation is untested |
| Image/base-image supply-chain compromise | Pinned digests, SBOM, vulnerability scan, OCI signature, provenance, and pre-deploy verification | A complete enforced pipeline, key custody, revocation, and provider admission test are open |
| Secret leakage or stale rotation | Task/workload identity, startup secret injection, no static keys in images/source, controlled replacement after rotation | Provider log/image/state review and rotation outage evidence remain open |
| Backup compromise or inconsistent restore | Encrypted/access-controlled backups, coupled PostgreSQL/object restore, digest and audit verification | True restore, power-loss, retention, and operator authorization evidence remain open |
| Regional capability or availability mismatch | Mumbai is only a documented initial hypothesis; Hyderabad/GCP/Azure alternatives remain recorded | Quotas, SKU availability, exact region pricing, residency, privacy, and legal review are open |
| Provider tries to become patch authority | Customer/local Ed25519 patch signing and runtime-authoritative signature/release/capability/sequence/high-water checks remain frozen | Provider implementation must preserve the boundary in acceptance tests |

The AWS ALB fail-open caveat is a material design condition, not a passed
security control. Provider deployment cannot be called production-ready until
the acceptance tests prove that an unready or dependency-failed control plane
does not authorize unsafe delivery. Task 77 creates no provider resource,
credential, endpoint, image policy, or secret.

See [`docs/PROVIDER_SELECTION_DECISION_REVIEW.md`](../history/reviews/PROVIDER_SELECTION_DECISION_REVIEW.md),
[`docs/adr/0014-provider-selection.md`](../adr/0014-provider-selection.md),
and the historical `tasks/77-provider-selection-decision-closure.md` record.

## Task 79 local AWS acceptance-preflight boundary (2026-08-25)

Task 79 hardened the disposable image path without changing runtime or patch
authority. The fresh ARM64 candidate is AOT-compiled into a pinned nonroot
distroless runtime; the SDK-based image and its historical vulnerability
findings remain rejected evidence. A fresh SBOM, Trivy report, local test-only
OCI signature, custom provenance attestation, and provider-neutral
fail-closed verifier bind the image digest, Dockerfile, bases, SBOM, and
architecture. The residual OpenSSL QUIC advisory is recorded as
`NOT_REACHABLE_WITH_EVIDENCE` for the current TCP-only listener, not hidden or
treated as a universal false positive.

The local verifier rejects wrong digests, unsigned images, missing or
unclassified CRITICAL/HIGH findings, altered Dockerfile/material bindings,
wrong architecture, and invalid provenance. The ephemeral test key and local
registry were removed after the mechanics run; no provider trust identity or
patch-signing key was created. Provider ECR admission, key custody, rotation,
revocation, and AWS account controls remain unverified.

Two crash-worker restart scenarios pass in isolated repeated campaigns and an
isolated full control-plane suite exits zero; the earlier failure was
classified as process/test-harness contention. The periodic runner remains
disabled because the serving binary has no exact tenant/application/
environment and raw lease-token composition. The hardened ECS health check
uses the compiled health executable, preventing an SDK-at-runtime assumption.

No AWS apply/resource, public endpoint, DNS, provider state, beta, production,
or store/legal claim follows from this local evidence.
