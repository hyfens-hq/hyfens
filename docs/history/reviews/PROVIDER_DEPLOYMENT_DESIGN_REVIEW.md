# Provider deployment design review

<!-- markdownlint-disable MD013 -->

Date: 2026-08-25

Status: DESIGN ONLY — MAINTAINER REVIEW REQUIRED

Task: `76-provider-deployment-design` (historical task record)

## 1. Recommendation

CONTINUE PROVIDER DEPLOYMENT DESIGN

The provider-neutral design package is complete enough for review, but no
provider, region, managed service, current price envelope, or implementation
approval is established. The next implementation phase is blocked until a
maintainer selects the provider/deployment profile and accepts the unresolved
external gates.

This recommendation does not authorize provider resources, credentials, DNS,
public endpoints, production or beta deployment, store submission, privacy or
legal approval, or any runtime/control-plane change.

## 2. Authorization and evidence boundary

The authorization in CODEX_PROVIDER_DEPLOYMENT_DESIGN.md permits design only.
Task 75 is the engineering baseline; its local evidence is not repeated here
or promoted to provider HA, production SLO, or production readiness.

Evidence labels used in this document are:

- VERIFIED LOCALLY — repository-controlled tests or disposable containers.
- DESIGN TARGET — proposed requirement, not an achieved measurement.
- INITIAL CAPACITY ASSUMPTION — sizing hypothesis requiring measurement.
- PROVIDER EVIDENCE REQUIRED — a later disposable provider environment must
  prove the contract.
- EXTERNAL CURRENT PRICING REQUIRED — no price is fabricated.
- MAINTAINER DECISION REQUIRED — a design choice is intentionally unresolved.
- OPEN — a readiness, policy, store, privacy, legal, or independent-device
  gate not closable by design alone.
- NOT APPLICABLE — intentionally absent from this phase, not silently passed.
- NOT RUN — explicitly planned but not executed.

No local result is promoted to provider HA, production SLO, or production
readiness.

## 3. Frozen authority boundaries

The following remain unchanged:

- Architecture B/source instrumentation.
- Patch Format v1 and capability v1.
- Exact-release binding, state-v4 monotonic high-water, signed rollback,
  fail-closed verification, and AOT fallback.
- Customer/local patch signing and runtime-authoritative verification.
- PostgreSQL as coordination and metadata authority.
- Immutable, digest-addressed object bytes as untrusted delivery storage.
- BoundedReconciliationService as the only repair path.
- ReconciliationPeriodicRunner as orchestration only.
- Audit-before-repair, CAS/currentness/postconditions, and exact tenant scope.
- P3A as rollout mutation authority and P3E-4 as automatic-halt application
  authority.
- Process-local metrics and read-only diagnostics as non-authoritative.

A provider may route or store a candidate. It may not make an invalid patch
valid, lower a runtime high-water, rewrite audit history, create a capability,
or create a second repair or rollout authority.

## 4. P3E5-5F baseline

The following are VERIFIED LOCALLY and are design inputs rather than new
claims:

- two stateless control-plane instances;
- shared PostgreSQL and S3-compatible object storage;
- passive local reverse proxy;
- instance-local liveness/readiness;
- both instance-loss directions;
- separate database and object-store outage/recovery;
- coupled backup/restore with matching artifact digest;
- audit integrity and exact tenant/auth scope;
- bounded 40-request/concurrency-8 sample;
- local image/source/config digest inventory;
- PostgreSQL advisory ownership and session-loss semantics at the existing
  runner/persistence seam.

The local proxy used passive retry only and the current HTTP host does not wire
the optional periodic runner/diagnostics adapter. A provider design must solve
active readiness-aware routing and must explicitly decide host runner wiring.

## 5. Provider decision matrix

Three viable deployment classes are evaluated without naming or selecting a
provider:

| Option | Compute and state | Complexity | Availability/failover | Edge/TLS/network | Cost/scaling | Lock-in/maintenance |
| --- | --- | --- | --- | --- | --- | --- |
| A — managed container platform plus managed PostgreSQL and object storage | Managed stateless replicas plus external writer database and immutable object store | Lowest after setup; provider owns most host operations | Must prove multi-zone placement, managed DB writer failover, object durability, and pool recovery | Strong candidate for managed checks, certificates, and private links; provider-specific | Per-instance/request plus database, storage, edge, transfer, logs, backups; autoscaling may exist | Moderate API/identity coupling; lower host maintenance |
| B — Kubernetes/container orchestration plus managed PostgreSQL and object storage | Deployment/Service/Ingress with external stateful services | Highest; cluster, ingress, upgrades, policies, and node lifecycle are operator work | Strong control when operated well; cluster and ingress add failure domains | Flexible probes, ingress, private networking, certificate controllers; more components to secure | Cluster/node floor plus state, edge, and SRE labor | Highest Kubernetes maintenance burden; portable abstraction |
| C — VM/container service plus managed PostgreSQL and object storage | Two or more managed or customer-managed VM/container instances plus external state | Medium; OS/container patching and edge remain operator work | Requires active health-checking edge and instance replacement; DB/object failover remains external | Flexible private networks and edge choices; certificate automation must be selected | VM floor plus state, edge, transfer, logs, backups; coarse autoscaling | Lower platform API lock-in; higher patching burden |

Matrix conclusions:

1. Option A is the leading shape for a first disposable provider
   implementation because it minimizes undifferentiated host operations.
2. Option B is justified only when customer cluster control, private
   networking, or policy requirements outweigh the operational cost.
3. Option C is a credible low-lock-in fallback for customers that already
   operate VMs and a load balancer.
4. No row proves provider-specific advisory-lock behavior, object durability,
   current pricing, or regional availability.

PROVIDER DECISION — MAINTAINER DECISION REQUIRED.

## 6. Concrete provider selection rule

A provider can be selected only after maintainers confirm:

- managed services exist in the selected region;
- database writer failover and session/advisory-lock semantics fit the runner;
- object storage supports immutable/versioned/digest recovery;
- edge routing actively uses dependency-aware readiness;
- IAM, private networking, secrets, backups, PITR, and audit access are
  supportable;
- image/SBOM/provenance verification can gate deployment;
- an initial cost envelope is accepted using dated current pricing;
- no trust or authority invariant is compromised.

Until then, PROVIDER DECISION — MAINTAINER DECISION REQUIRED remains recorded.

## 7. Proposed target architecture

~~~text
developer/CI
    |
    | authenticated operator/delivery traffic
    v
active edge/load balancer
    |  /readyz health eligibility, TLS, request IDs, draining
    +-----------------------+
    |                       |
    v                       v
control-plane replica A  control-plane replica B
    |                       |
    +-----------+-----------+
                |
        private managed PostgreSQL
        (metadata, audit, CAS, advisory ownership)
                |
        private immutable object storage
        (digest-addressed artifact bytes)
~~~

Application replicas are stateless with respect to durable product state. The
edge is responsible for connection draining and active backend eligibility.
PostgreSQL is the coordination authority. Object storage is an immutable byte
store and never the runtime trust root.

## 8. Stateless control-plane contract

The future deployment must provide:

- at least two replicas across the provider's smallest supported failure
  domain;
- no durable application state on the container filesystem;
- shared PostgreSQL and shared immutable object storage;
- active routing eligibility based on /readyz, not only /livez;
- /livez for process liveness and /readyz for dependency/schema readiness;
- graceful shutdown that stops admission, drains connections, stops the
  optional runner within its bounded shutdown budget, and closes pools;
- rolling replacement one replica at a time;
- bounded request-ID propagation and generation;
- unchanged authorization, delivery/control scopes, tenant checks, and audit
  semantics;
- no sticky sessions.

The current Dockerfile uses a floating dart:stable base and the local host does
not yet wire the periodic runner. Those are implementation-phase gates.

## 9. Managed PostgreSQL contract

The selected service must document or demonstrate:

- single-writer HA mode and the writer endpoint clients use;
- endpoint behavior during promotion and DNS/connection changes;
- TLS/private network access and certificate rotation;
- pool recreation after broken connections;
- transaction behavior for committed, rolled-back, and ambiguous outcomes;
- session-scoped advisory locks that disappear when the owning session dies;
- backup schedule, PITR, retention, encryption, and restore authorization;
- maintenance windows and version support;
- migration prechecks and mixed-version compatibility;
- provider limits for connections, transactions, storage, and failover;
- monitoring and operator access without public database exposure.

The application must treat an ambiguous commit as a bounded failure and retry
only through existing idempotency/CAS/currentness semantics. It must never
assume that an HTTP response proves a database commit.

## 10. Advisory ownership across database failover

Required sequence:

~~~text
writer failover
    -> old connection/session fails
    -> advisory ownership disappears with the old session
    -> runner records bounded store/ownership failure
    -> readiness remains not-ready until the dependency is usable
    -> pool recreates against the writer endpoint
    -> normal cadence attempts a fresh advisory lock
    -> CAS/idempotency prevents duplicate semantic repair
~~~

The old ownership session is never trusted after connection loss. A restart or
normal cadence may reacquire only through PostgreSQL. No Redis lock, queue,
external leader election, or second repair authority is introduced.

Provider implementation evidence must show one semantic mutation, no stuck
ownership, and no duplicate repair across a real writer failover.

## 11. Object-storage contract

The provider object store must support:

- digest-addressed immutable keys and immutable admission;
- exact-byte rehash on read;
- object versioning or an equivalent delete-recovery mechanism;
- replication/durability scope documented by the provider;
- retention and deletion protection;
- recovery from accidental deletion and metadata/object mismatch;
- lifecycle rules that do not expire active artifacts;
- server-side encryption and private endpoint/IAM access;
- authorized fetch through the control plane or a tightly scoped path.

The runtime still verifies Patch Format v1, signature, release, capability,
sequence, and resource limits. Object metadata never authorizes execution.

## 12. Object durability policy

The implementation phase must select values for:

| Control | Design requirement | Current status |
| --- | --- | --- |
| Durability class | Provider-documented durability for acknowledged bytes | PROVIDER EVIDENCE REQUIRED |
| Replication scope | Selected failure domain; multi-region only if justified | MAINTAINER DECISION REQUIRED |
| Versioning | Enabled or equivalent immutable recovery | DESIGN TARGET |
| Retention | Active releases and rollback evidence retained for approved period | MAINTAINER DECISION REQUIRED |
| Delete protection | Least-privilege deletes, approval, and recovery window | DESIGN TARGET |
| Reconciliation | Digest inventory and quarantine on mismatch | VERIFIED LOCALLY at adapter/seam |
| Encryption | Provider-managed encryption plus access-controlled keys | PROVIDER EVIDENCE REQUIRED |

No provider default is accepted silently.

## 13. Active edge/load-balancer design

The provider edge must actively use /readyz for backend eligibility.

Initial design assumptions, not approved SLOs:

- health-check path: GET /readyz;
- interval: 5 seconds;
- failure threshold: 2 consecutive failures;
- success threshold: 2 consecutive successes;
- connection drain: 30 seconds or provider minimum;
- connect timeout: 5 seconds;
- read timeout: 30 seconds;
- request-body limit: at least the current 4 MiB fixture limit;
- retries: only safe/idempotent requests by default; do not replay arbitrary
  control mutations without an idempotency key;
- a backend is removed before new traffic and restored only after readiness
  recovery.

These values are DESIGN TARGETS and require provider testing and maintainer
approval. /livez alone is insufficient for routing. The edge must preserve
request IDs and not expose internal backend addresses.

## 14. Public TLS

The future edge design must specify:

- certificate issuance and account ownership;
- automated renewal and overlap/rotation;
- TLS 1.2 minimum and a maintainer-approved cipher policy;
- HTTP/2 or HTTP/3 only if operationally justified;
- client trust and hostname verification;
- edge-to-origin TLS or a private authenticated link;
- HSTS only after domain ownership and rollback are understood;
- certificate expiry monitoring and emergency replacement.

No public TLS is implemented or claimed in this phase.

## 15. DNS and cutover

The implementation design must later define:

- public hostname and certificate SAN;
- edge/load-balancer target;
- TTL and resolver caching assumptions;
- initial cutover and rollback steps;
- certificate dependency;
- regional/failover implications.

No DNS record, domain, certificate, or public endpoint is created here.

## 16. Network architecture

Proposed least-exposure layout:

- public edge is the only internet-facing surface;
- replicas live on a private service network;
- PostgreSQL accepts traffic only from control-plane and approved
  migration/backup identities;
- object storage uses a private endpoint where available;
- egress is limited to required object, database, registry, time, and
  observability endpoints;
- migrations and backup/restore use a separate short-lived operator path;
- operator access uses a private administrative channel, never a public DB port.

Exact network controls are PROVIDER EVIDENCE REQUIRED.

## 17. IAM and service identity

Define separate least-privilege identities for:

| Identity | Allowed actions | Forbidden actions |
| --- | --- | --- |
| Control-plane service | Metadata/audit DB; immutable object access under service scope | IAM administration, signing, arbitrary database/bucket administration |
| Deployment automation | Pull approved image; replace replicas; read readiness | Patch signing, trust reset, arbitrary data mutation |
| Backup/restore operator | Encrypted backup and approved restore | Rollout or signing-trust mutation |
| Migration operator | Reviewed schema migrations through private path | Public admin access or patch signing |
| Object-store service | Artifact bucket operations under exact policy | Cross-tenant bucket administration |
| Observability reader | Health, logs, metrics | Mutation, secrets, artifact bytes, private keys |
| Security/audit operator | Verify/export application audit | Rewrite/delete application audit |

One broad administrator credential is prohibited.

## 18. Secrets

Provider injection must cover database credentials, object-store credentials,
control-plane bootstrap material, and edge/TLS material where the provider
does not manage it. Secrets must be injected at runtime, scoped by
service/environment, rotatable, and redacted from logs and audit bodies.

Private patch-signing keys remain customer/local or CI/customer-controlled and
outside the control-plane service. They are not stored in provider secret
storage in this phase.

## 19. Patch-signing trust boundary

The provider may store public signing metadata and signed artifacts. It must
not hold or mint customer signing authority as part of this design.

~~~text
customer/offline/approved CI signer
    -> signed Patch Format v1 bytes
    -> control plane verifies and stores public metadata
    -> provider delivers immutable bytes
    -> runtime independently verifies signature/release/capability/high-water
~~~

Provider account, database, object-store, edge, or image compromise must not
forge a valid patch without the separate signing authority. Container signing
and patch signing are different trust domains.

## 20. Deployment pipeline

The future provider pipeline is:

~~~text
source revision
  -> tests and static analysis
  -> container build
  -> SBOM generation
  -> vulnerability scan
  -> immutable image digest
  -> provenance/attestation and signature
  -> migration precheck
  -> deployment plan
  -> readiness
  -> authenticated smoke test
  -> one-at-a-time replacement
  -> post-deploy audit/evidence
  -> rollback if gates fail
~~~

No production credentials, provider deployment, or live pipeline is added.

## 21. Immutable image references

Every deployable reference must be immutable:

- application image by registry digest;
- base image by digest;
- self-managed test database/object images by digest;
- lockfiles and source revision recorded with the image;
- architecture-specific manifests resolved and recorded;
- deployment rejects mutable tags in release configuration.

The 5F image used floating references and is therefore only bounded local
provenance, not production supply-chain evidence.

## 22. SBOM design

The future pipeline should generate an SPDX or CycloneDX document at image
build time and bind it to the image digest, source revision, Dockerfile digest,
dependency lockfiles, build identity, and timestamp.

Retain the SBOM and verification record with release evidence. Verify that the
SBOM describes the exact image digest before deployment. Tool selection and
retention are MAINTAINER DECISION REQUIRED; no SBOM pipeline is implemented.

## 23. Vulnerability scanning

Recommended design gate:

- scan application image and Dart/native dependencies before deployment;
- block on a maintainer-approved severity policy;
- record exceptions with owner, rationale, expiry, and compensating control;
- rescan on base-image/dependency changes and on a scheduled cadence;
- retain scanner version, database date, image digest, and result.

Severity thresholds are recommendations, not an approved policy. No scanner
result or production security claim is created here.

## 24. Image signing and provenance

The desired OCI provenance record contains image digest, source revision,
Dockerfile digest, SBOM digest, build identity, isolated-build metadata, and
signature/attestation verification.

An OCI signing/attestation tool or provider-native equivalent may be selected
later. It must not be confused with Ed25519 patch signing. Tool selection is
MAINTAINER DECISION REQUIRED.

## 25. Migration strategy

The current PostgreSQL schema is versioned in the Dart control-plane migration
path (schema version 8 in source). A provider deployment must use
expand/contract discipline:

1. preflight a compatible backup and schema/version;
2. apply additive/compatible expansion through one reviewed migration operator;
3. deploy an application that works with schema N and N+1;
4. backfill separately and boundedly if needed;
5. remove old contracts only in a later reviewed migration.

Readiness must fail closed on an incompatible schema; ordinary HTTP replicas
must not silently run a migration.

## 26. Mixed-version deployment

During version N/N+1 overlap, require shared schema/API compatibility,
idempotency and CAS compatibility, audit format compatibility, periodic
ownership-key compatibility, identical Patch Format/capability authority, and
unchanged tenant authorization. No new repair or rollout authority may appear.

If compatibility cannot be proven, use a drained maintenance window with an
approved rollback/restore plan.

## 27. Rolling upgrade

Provider implementation must replace one replica at a time:

1. deploy the new immutable image;
2. wait for /readyz and version/schema compatibility;
3. drain the old replica;
4. smoke-test update-check, exact fetch, auth scope, and audit;
5. repeat for remaining replicas;
6. verify runner ownership and no duplicate semantic repair;
7. retain the old digest until the evidence window closes.

A failed readiness, smoke, migration, or ownership check stops the rollout. No
real rolling upgrade was run in this design phase.

## 28. Application rollback

Application-image rollback is allowed only when the schema is backward
compatible, object identities and signed bytes are unchanged, audit history is
append-only, and CAS/currentness semantics remain compatible.

Rollback must not lower runtime high-water, delete artifacts, rewrite audit, or
rewind reconciliation state.

## 29. Database rollback boundary

A database migration is not assumed reversible. If a migration is irreversible,
rollback means restoring a compatible application image against the newer
schema, or using an approved backup/restore process after traffic is stopped.
No automatic schema downgrade is designed.

## 30. Backup and PITR

Provider implementation must define encrypted database snapshots and
continuous WAL/PITR where available, retention/deletion controls, object
versioning/retention and digest manifests, audit retention/export, separate
restore approval, coupled database/object restore, and verification of schema,
audit chain, artifact digest, update-check, and exact fetch.

A metadata-only restore is unsafe. Provider backup durability and PITR are
PROVIDER EVIDENCE REQUIRED.

## 31. RPO/RTO design targets

These are proposals, not claims:

| Data/service | Initial design target | Status |
| --- | --- | --- |
| Acknowledged artifact bytes | RPO 0 within the selected immutable/versioned object policy | DESIGN TARGET — MAINTAINER APPROVAL REQUIRED |
| PostgreSQL metadata/audit | RPO 5–15 minutes using configured PITR/backup policy | DESIGN TARGET — MAINTAINER APPROVAL REQUIRED |
| Control-plane service | RTO 30–60 minutes for provider failover/restore | DESIGN TARGET — MAINTAINER APPROVAL REQUIRED |
| Artifact delivery after edge/replica failure | RTO within selected provider health/drain budget | DESIGN TARGET — PROVIDER EVIDENCE REQUIRED |

5F timings are directional local observations only. These targets are not SLOs
and must not be advertised without provider evidence and approval.

## 32. Provider failover test plan

The later implementation phase must execute:

| Scenario | Injection | Expected result | Evidence |
| --- | --- | --- | --- |
| Replica loss | terminate one replica | edge removes it after readiness failures; other serves | provider health/drain receipt |
| Backend recovery | restore replica | readiness succeeds before traffic returns | health transition/smoke |
| DB writer failover | disposable provider failover | old session dies; readiness fails boundedly; pool reconnects | session/advisory/CAS |
| Object transient outage | deny/interrupt object access | no invalid artifact; exact bytes after recovery | digest/error evidence |
| Edge failure | provider-supported edge/target failure | documented degraded behavior and rollback | edge/DNS evidence |
| Certificate rotation | staged overlap | clients retain trust; no expired cert | certificate timeline |
| Network partition | isolate service/dependency path | fail closed; no duplicate repair | readiness/audit evidence |
| Upgrade regression | adjacent image | stop/rollback without schema/audit rewind | deployment/audit evidence |

Do not execute this matrix without separate provider implementation authorization.

## 33. Provider-specific PostgreSQL validation

Before any production claim, a disposable provider test must prove real managed
writer failover, connection interruption/pool recreation, session-scoped
advisory-lock release, fresh ownership acquisition, one semantic repair, no
stuck ownership, readiness recovery, and unchanged tenant/audit/CAS/currentness/
postcondition behavior.

Local pg_terminate_backend evidence is seam evidence, not provider failover
evidence.

## 34. Provider-specific object validation

Require later evidence for versioning and accidental-delete recovery,
replication/failure-domain behavior, transient outage and retry,
access-control denial, byte/digest integrity, metadata/object mismatch,
retention/lifecycle behavior, and approved backup/export restore.

No production claim is permitted before these checks.

## 35. Capacity assumptions

The 5F local sample is not extrapolated. Initial provider sizing hypotheses:

| Component | Initial hypothesis | Status |
| --- | --- | --- |
| Control plane | 2 replicas, 1 vCPU and 512 MiB each as a starting test size | INITIAL CAPACITY ASSUMPTION |
| PostgreSQL | managed tier for measured test load plus migration/backup headroom | INITIAL CAPACITY ASSUMPTION |
| Object store | immutable storage above release workload request/transfer needs | INITIAL CAPACITY ASSUMPTION |
| Edge | active checks, bounded body/timeouts, connection draining | DESIGN TARGET |
| Load model | repeat 5F mix, then representative release/update/observation traffic | PROVIDER EVIDENCE REQUIRED |

These are starting hypotheses only. No capacity limit or SLO is claimed.

## 36. Autoscaling

Safe scale signals may include request concurrency, CPU, memory, and validated
request latency. Scaling must not be driven directly by rollout findings,
health-event outcomes, or reconciliation decisions.

Periodic ownership remains PostgreSQL-coordinated regardless of replica count.
Autoscaling policy and cooldowns are PROVIDER EVIDENCE REQUIRED.

## 37. Connection-pool budget

Each replica must have an explicit budget for ordinary HTTP work, one dedicated
periodic ownership session/pool, and bounded migration/admin activity outside
ordinary traffic. Total possible connections across the maximum replica count
must remain below the managed DB limit with failover headroom.

Pool values are MAINTAINER DECISION REQUIRED and must not be left at provider
defaults without measurement.

## 38. Soak plan

Because 5F did not run a 60-minute soak, the provider plan must specify at
least 60 minutes, two or more replicas, update-check/artifact/control/readiness/
audit request mix, configured periodic work if enabled, database/object
activity, backup interaction, CPU/memory/connection/latency/error/readiness/
ownership monitoring, stop thresholds, and retained evidence.

Soak is NOT RUN and is not required for design closure.

## 39. Observability

Provider implementation should collect operational signals for structured
service logs, request/error/latency metrics, /livez and /readyz, database
pool/reconnect/failover state, object errors/digest mismatches, periodic
ownership/outcomes, audit verification, deployment/image revisions, backups,
and certificate events.

No runtime fleet telemetry is added by this design.

## 40. Metrics aggregation boundary

Task 72/73 metrics are process-local. A future provider may export them to an
external aggregation backend, but aggregation remains observational. It cannot
authorize a patch, mutate rollout state, invoke repair/P3E-4, lower high-water,
or make missing metrics proof of health.

Aggregation is a future implementation decision.

## 41. Logging

Structured logs should include bounded request ID, instance identity,
deployment revision, normalized operation, safe error code, timestamp, and
duration. Redaction excludes authorization headers, tokens, private keys,
patch bytes, request bodies, SQL values, and tenant secrets.

Retention, access, export, and deletion are provider/product policy gates.

## 42. Audit

The durable application audit chain remains authoritative. Provider design must
cover encrypted database/off-box backup, append-only retention/access controls,
chain verification after restore/failover, signed export and evidence
retention, redaction without rewriting history, and operator-access audit.

Provider logs may diagnose an incident but cannot replace application audit.

## 43. Operator access

Define temporary, least-privileged access for image deployment/rollback,
migrations, database diagnostics, backup/restore, audit verification/export,
incident response, and certificate/secret rotation. Administrative functions
remain private. No public admin endpoint is designed.

## 44. Incident runbook outlines

### Control-plane outage

Confirm edge/readiness state, preserve runtime delivery semantics, drain or
replace unhealthy replicas, verify exact update-check/fetch, and retain audit
and deployment evidence.

### Database failover

Treat old sessions and advisory ownership as lost, wait for writer readiness,
recreate pools, verify /readyz, prove fresh ownership and one semantic repair,
then resume normal traffic.

### Object-store outage

Keep metadata and runtime verification authoritative, fail closed on missing
bytes, do not regenerate artifacts, restore access, reconcile digests, and
verify exact fetch.

### Credential compromise

Revoke the scoped identity, preserve audit, rotate through an approved secret
process, and verify tenant/scope boundaries. Do not rotate patch trust
implicitly.

### Deployment regression

Stop replacement, retain failing image evidence, restore the last compatible
image only if schema compatibility holds, re-run readiness/smoke, and never
rewrite audit/reconciliation state.

### Audit tamper

Stop the affected evidence path, fail closed on chain verification, preserve
original bytes, and use a separately reviewed export/recovery procedure. Do not
repair by rewriting history.

### Signing-key compromise

Follow existing customer/local signing-key recovery and store-release trust
replacement. Provider control does not authorize a hosted trust reset.

## 45. Cost model

No current provider prices are asserted. Pricing basis is 2026-08-25 and is
EXTERNAL CURRENT PRICING REQUIRED.

| Cost category | Option A | Option B | Option C |
| --- | --- | --- | --- |
| Compute | managed container units/requests | cluster control plane + nodes + replicas | VM/container instances |
| PostgreSQL | managed HA tier + storage/I/O/backup | managed HA tier + storage/I/O/backup | managed HA tier + storage/I/O/backup |
| Object storage | capacity + requests + transfer + retention | same | same |
| Edge/TLS | load balancer, requests, certificates, transfer | ingress/load balancer/certificates/transfer | load balancer/certificates/transfer |
| Observability | logs/metrics/traces retention | cluster/service observability | VM/service observability |
| Registry/SBOM | registry storage and scans | registry storage and scans | registry storage and scans |
| Operations | provider platform labor | cluster/SRE labor | VM/OS/edge labor |
| Backup/restore | database/PITR/object retention | database/PITR/object retention | database/PITR/object retention |
| Minimum floor | provider quote required | provider quote required | provider quote required |

Monthly formula:

~~~text
compute + database + object_storage + edge + transfer + logs/metrics
+ registry/scans + backups + operator labor
~~~

A maintainer must choose provider, region, replica floor, data/transfer
assumptions, retention, and support tier before a price is meaningful. No
option is cost-approved.

## 46. Regional strategy

The proposed initial strategy is one region with replicas across the
provider's smallest supported independent failure domain. Selection must
consider user geography/latency, data location/residency, service availability,
cost/transfer, operator timezone, maintenance windows, and recovery export.

Region selection is MAINTAINER DECISION REQUIRED. Active-active multi-region is
not justified by current evidence.

## 47. Multi-region boundary

If later considered, separately decide artifact distribution, API/edge
failover, database consistency/writer authority, audit ordering, periodic
ownership, and backup/export recovery. No multi-region implementation is
authorized.

## 48. Privacy and data inventory

| Store/surface | Data categories | Required review |
| --- | --- | --- |
| PostgreSQL | tenant/application/environment IDs, release/patch metadata, rollout/audit records, scoped actor IDs | retention, access, residency, deletion/export |
| Object storage | signed Patch Format v1 bytes, manifests, digests, optional debug/provenance bundles | retention, encryption, deletion/recovery |
| Logs/metrics | request IDs, safe codes, instance/revision, timing, dependency errors | redaction, retention, access, transfer |
| Audit/backups | append-only evidence and database/object snapshots | encryption, off-box location, retention, restore access |
| Runtime observations | optional bounded lifecycle/health events if separately enabled | separate product/privacy decision |

No residency, GDPR, CCPA, HIPAA, or other legal/compliance claim is made.
PRIVACY/LEGAL REVIEW REQUIRED.

## 49. Store-policy boundary

Provider deployment does not change Apple/Google policy classification for
downloaded interpreted behavior, Flutter UI, native code, permissions,
entitlements, assets, or SDKs. Store-policy review remains separate and open.
No App Store or Google Play approval claim is authorized.

## 50. Independent-app, power-loss, and iOS gates

The following remain OPEN:

- independent real-application validation;
- physical power-loss campaigns;
- complete iOS diagnostics/performance and other P1D evidence;
- beta and production readiness.

Provider design cannot close these gates.

## 51. No credentials or live resources

This task creates no provider account, IAM principal, database, bucket,
certificate, DNS record, public endpoint, secret, or live infrastructure. No
AWS/GCP/Azure credential or real database password may enter repository files.

## 52. Infrastructure-as-code decision

IaC is deferred until a provider and region are selected. Candidate classes for
a later review are Terraform/OpenTofu, provider-native IaC, or Pulumi. The
implementation phase must choose one and define state locking, secret handling,
review, plan/apply separation, drift detection, and destroy safeguards.

IAC TOOL — DEFER UNTIL PROVIDER DECISION.

## 53. Future deployment artifact layout

Proposed only; do not create it in this design phase:

~~~text
deploy/provider/
  README.md
  environments/
  modules/
  policies/
  runbooks/
  evidence/
~~~

The future layout must contain templates only after a provider decision. It must
not contain real credentials or live configuration.

## 54. ADR status

No new provider-selection ADR is accepted because no provider has been
selected. Existing ADR 0010 remains the staged self-hosting boundary. Its
Task 76 factual addendum links this design and records that provider
selection, IaC, managed-service, and current-pricing decisions remain proposed.

A future provider-selection ADR must be marked PROPOSED until maintainer
approval and must link provider-specific evidence.

## 55. Threat-model update

Provider deployment adds threats from provider account compromise, service
credential compromise, managed database/object-store compromise, edge
misconfiguration, image/supply-chain compromise, backup compromise, and
operator compromise. Controls are:

- runtime signature/release/capability/high-water checks remain authoritative;
- customer/local signing is separate from provider administration;
- DB/object/edge identities are least-privileged and private;
- immutable bytes are digest checked and reconciled;
- image digest/SBOM/provenance gates precede deployment;
- audit is append-only and independently verified;
- backups are encrypted, access-controlled, and restored together;
- operator actions are temporary, scoped, and audited;
- provider failure preserves local runtime state or AOT fallback.

Residual provider-specific failover, compromised-provider, power-loss, and
store/privacy/legal risks remain open. The update is recorded in
docs/security/productization-threat-model.md.

## 56. Provider implementation entry criteria

Provider implementation remains blocked until maintainers explicitly decide:

- provider and region;
- compute profile and replica floor;
- managed PostgreSQL service/failover mode;
- object-store durability/versioning/retention;
- edge/load-balancer and active readiness behavior;
- TLS/certificate ownership;
- network topology;
- IAM and secret mechanism;
- backup/PITR and restore procedure;
- deployment pipeline and image provenance;
- migration/mixed-version/rollback strategy;
- observability and audit export;
- initial cost envelope and operator ownership.

All unresolved mandatory decisions are blockers, not assumptions.

## 57. Design-package validation

The package must pass Markdownlint, local-link and whitespace scans,
high-confidence secret scan, prohibited-scope/dependency scan, JSON/YAML/example
syntax checks, architecture consistency/frozen-boundary review, ADR link checks,
and inspection for provider resources, credentials, endpoints, or source
changes.

No runtime/control-plane code implementation is required.

## 58. Prohibited-scope evidence

The authorized change set contains only Task 76, this review, threat-model/ADR
factual addenda, and documentation validation. It adds none of:

- provider SDK dependencies;
- provider credentials or resources;
- DNS/public endpoints;
- queue, Redis, or distributed scheduler;
- rollout writer or P3A/P3E-4 mutation;
- runtime/mobile/compiler changes;
- beta/production/store/privacy/legal claims.

## 59. Completion matrix

| Area | Design status |
| --- | --- |
| Provider option matrix | PASS |
| Provider selection | MAINTAINER DECISION REQUIRED |
| Stateless compute | PASS as design |
| Managed PostgreSQL | PASS as contract; provider evidence required |
| Advisory-lock failover | PASS as contract; provider evidence required |
| Object storage/durability | PASS as contract; provider evidence required |
| Active readiness edge | PASS as design target; provider evidence required |
| TLS/DNS/network/IAM/secrets | PASS as design; implementation/provider evidence required |
| Pipeline/image/SBOM/provenance | PASS as design; not implemented |
| Migration/rolling/rollback | PASS as design; adjacent release evidence required |
| Backup/PITR | PASS as design; provider restore evidence required |
| RPO/RTO | PASS as proposed targets; maintainer approval required |
| Failover test plan | PASS |
| Capacity/autoscaling/pool | PASS as assumptions; measurements required |
| Soak | PASS as plan; NOT RUN |
| Observability/logging/audit | PASS as design; aggregation not implemented |
| Operator/incident runbooks | PASS as outlines |
| Cost model | PASS as formula; current pricing required |
| Privacy/store/external gates | OPEN |
| Prohibited scope | PASS |
| Documentation validation | PASS when commands below pass |

## 60. Open gates carried forward

Design does not close:

- provider-specific PostgreSQL failover;
- provider-specific object durability/replication;
- active readiness-aware edge routing;
- public edge TLS/certificate lifecycle;
- real adjacent rolling upgrade;
- migration rollback/compatibility;
- immutable image/base pinning;
- SBOM and vulnerability pipeline;
- image signing/provenance;
- bounded soak;
- representative capacity limits;
- physical power loss;
- independent real-app validation;
- complete iOS/P1D evidence;
- beta and production readiness;
- App Store/Google Play review;
- privacy/legal review.

## 61. Final disposition

CONTINUE PROVIDER DEPLOYMENT DESIGN

The documentation defines a viable provider-neutral target and preserves the
existing authority model, but unresolved provider, region, managed-service,
pricing, supply-chain, and external readiness decisions block implementation.
Stop here for maintainer review. Do not create provider resources or begin a
provider implementation phase automatically.
