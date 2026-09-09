# P3E5-5F provider-resilience readiness review

Date: 2026-08-25

Scope: provider-neutral, disposable local evidence only

Task: `75-p3e5-5f-provider-resilience-readiness` (historical task record)

## 1. Decision

PROCEED TO PROVIDER DEPLOYMENT DESIGN WITH CONDITIONS

This is a maintainer-review recommendation, not authorization to deploy a
provider, publish a beta, or make a production, SLO, App Store, Google Play,
privacy, or legal claim. The bounded local evidence is sufficient to design a
provider deployment boundary. Provider-specific failover and external
readiness evidence remain open.

## 2. Evidence boundary

Evidence in this review is classified as one of:

- VERIFIED LOCALLY — executed against repository-controlled disposable
  processes, containers, or tests.
- DESIGN ONLY — a documented operator policy that was not executed as a
  provider deployment.
- ENVIRONMENT GATED — a bounded seam or test exists, but the required
  provider/device/tooling was not available.
- EXTERNAL_PROVIDER_EVIDENCE_REQUIRED — a real provider, managed service, or
  external control must supply the evidence.
- NOT_APPLICABLE — the current bounded host or scope intentionally does not
  expose the requested surface.
- NOT_RUN — an explicitly requested scenario was not executed.

No local result is promoted to provider HA, production SLO, or production
readiness.

## 3. What was validated

The extended disposable rehearsal executed:

~~~text
COMPOSE_PROGRESS=quiet HYFENS_HA_EXTENDED=1 HYFENS_HA_PORT=18085 \
  ./scripts/p2-ha-rehearsal.sh
~~~

Run identity:

~~~text
project=hyfens-p2-ha-92092-42226
endpoint=http://127.0.0.1:18085
Docker=29.7.2, server Linux aarch64
~~~

The run built two stateless control-plane containers, one Nginx reverse proxy,
one PostgreSQL container, and one S3-compatible object-store container in a
unique Compose project. The project and its volumes were removed by the
script's exit trap.

The run passed release registration, idempotent retry, signed artifact upload,
promotion, update-check, exact artifact fetch, audit verification, both
directions of instance loss, separate dependency outages, recovery, and a
bounded local load sample. The output was:

~~~text
ha_rehearsal=PASS
evidence=APPLICATION_HA_DISPOSABLE
dependency_model=SHARED_POSTGRES_AND_OBJECT_STORE
extended_evidence=MULTI_INSTANCE_LOCAL,LOAD_BALANCER_LOCAL,OBJECT_STORE_OUTAGE,CAPACITY_BASELINE
readiness_model=INSTANCE_LOCAL_WITH_PASSIVE_PROXY_RETRY
metrics_model=PROCESS_LOCAL_NO_GLOBAL_AGGREGATION
not_proven=database_or_object_store_failover,public_edge_tls,provider_rto_rpo
~~~

This is VERIFIED LOCALLY; the labels in the output are part of the evidence
boundary and are not marketing claims.

## 4. Topology and isolation

The disposable topology contains:

~~~text
client
  |
  v
Nginx proxy :18085       (local passive retry)
  |             |
  v             v
control-plane-1  control-plane-2  (stateless application processes)
       |             |
       +------+------+
              |
      PostgreSQL + S3-compatible object store
~~~

The database is the shared metadata and coordination authority. Object storage
stores immutable, digest-addressed artifact bytes. Neither dependency is a
runtime patch trust authority. The run used a unique Compose project and
volumes, so it did not mutate the long-running local P2 test project.

Process/container and tenant scope are VERIFIED LOCALLY. Provider network, IAM,
managed database, managed object storage, public edge, and multi-zone isolation
require EXTERNAL_PROVIDER_EVIDENCE_REQUIRED.

## 5. Load-balancer states

The extended script exercised all practical local states:

- Both instances healthy: direct and proxied live/ready checks, update-check,
  and fetch passed. `VERIFIED LOCALLY`.
- Instance 1 unavailable: instance 2 stayed live/ready; the proxy served
  update-check and bytes; instance 1 returned. `VERIFIED LOCALLY`.
- Instance 2 unavailable: instance 1 stayed live/ready; the proxy served
  update-check and bytes; instance 2 returned. `VERIFIED LOCALLY`.
- Both unavailable: no healthy backend is expected; no successful service state
  is claimed. `DESIGN ONLY`.

The proxy configuration has static upstreams and passive connection retry. It
does not actively poll /readyz and remove an unhealthy backend. Dynamic
readiness-aware routing is therefore an open deployment-design requirement.

Request-ID checks passed for update-check, artifact fetch, both instance-loss
paths, and a wrong-scope control request. IDs were bounded and the wrong
delivery token was rejected with 401/403. This is VERIFIED LOCALLY for the
application contract, not a public-edge or WAF claim.

## 6. Readiness and liveness

Each control-plane process was probed directly and through the proxy. /livez is
process-local liveness. /readyz performs dependency-aware checks and returned
503 during the isolated PostgreSQL and object-store outages while /healthz
remained a process-liveness response. Recovery returned /readyz to 200 before
the script accepted writes or fetches.

This is VERIFIED LOCALLY. TLS termination, external health-check intervals,
connection draining, and edge retry policy are PROVIDER DEPENDENT.

## 7. Ownership and duplicate work

The existing PostgreSQL advisory ownership pool and bounded reconciliation
runner/store seams from Tasks 73 and 74 were reused; no new repair path was
introduced. Existing two-instance PostgreSQL tests and the local process
harness prove one ownership lease, fencing, handoff after session loss, and
one semantic mutation under contention. The HTTP host remains
disabled-by-default/not wired for the periodic runner, so this review does not
claim that every deployed HTTP process automatically starts reconciliation.

The result is VERIFIED LOCALLY at the existing runner/persistence seam.
Host wiring is NOT_APPLICABLE to this bounded topology and remains an explicit
deployment decision. No duplicate semantic repair was observed in the executed
runner tests.

## 8. PostgreSQL outage and failover

The extended rehearsal stopped only PostgreSQL. /healthz remained available,
/readyz became 503, and readiness recovered after PostgreSQL restarted. The
earlier coupled DR rehearsal destroyed and recreated the disposable Compose
project, restored the PostgreSQL dump, restored object bytes, and verified the
same artifact digest.

The following are not claimed:

- managed PostgreSQL failover;
- multi-zone or multi-region replication;
- synchronous/asynchronous provider RPO;
- automated promotion or DNS/endpoint failover;
- provider backup durability or retention.

Those are ENVIRONMENT GATED / EXTERNAL_PROVIDER_EVIDENCE_REQUIRED.

## 9. Object-store outage, corruption, and reconciliation

The extended rehearsal stopped only the object store. Readiness became 503,
artifact fetch failed with an accepted 500/502/503 response, and the exact
artifact bytes were fetched after recovery. Existing unit coverage verifies
digest validation and immutable writes in S3CompatibleArtifactStore; the File
reconciliation hardening suite verifies missing, corrupt, and orphaned objects
are detected/quarantined without inventing bytes. The MinIO integration test
remains an explicit environment skip when HYFENS_TEST_S3_* is absent.

Local outage and byte-integrity semantics are VERIFIED LOCALLY. Provider
replication, object versioning, cross-region durability, and a real provider
corruption drill are ENVIRONMENT GATED /
EXTERNAL_PROVIDER_EVIDENCE_REQUIRED.

## 10. Backup and restore

HYFENS_ALLOW_RESTORE=1 ./scripts/p2-dr-rehearsal.sh passed in a unique
disposable project. It recorded:

~~~text
dr_rehearsal=PASS
evidence=DISASTER_RECOVERY_DIRECTIONAL
source_artifact_digest=sha256:2aaba1e9f807edb65a59c62f834a0d040c60ffc5ad557232a08f0ef45f4ac1d6
restored_artifact_digest=sha256:2aaba1e9f807edb65a59c62f834a0d040c60ffc5ad557232a08f0ef45f4ac1d6
data_loss_observed=none_in_quiesced_rehearsal
not_proven=provider_backup_durability,automated_failover,approved_RPO_RTO
~~~

The database dump, object manifest, restored bytes, audit validity, update
check, and fetch were coupled in the local rehearsal. This is a quiesced
directional recovery result, not a provider RPO/RTO or SLO.

## 11. Directional timing evidence

The extended HA run recorded milliseconds:

| Operation | Duration | Classification |
| --- | ---: | --- |
| Compose build/start | 60,114 | DIRECTIONAL_RPO_RTO local timing |
| both instances ready | 349 | DIRECTIONAL_RPO_RTO local timing |
| release write and retry | 1,587 | local timing |
| update-check and artifact fetch | 948 | local timing |
| instance 1 down and return | 41,716 | local timing |
| instance 2 down and return | 33,643 | local timing |
| PostgreSQL outage and recovery | 3,105 | local timing |
| object outage and recovery | 4,708 | local timing |

The DR rehearsal recorded 16,197 ms Compose start, 2,604 ms backup/manifest,
and 83,695 ms destroy/recreate/restore. These values are directional local
observations only. They are not approved RPO, RTO, latency, availability, or
production SLO numbers.

## 12. Capacity baseline

The extended run executed 40 requests at concurrency 8 against update-check
and artifact-fetch operations:

~~~json
{"concurrency":8,"elapsedMs":1398.0,
 "operations":{
   "artifact-fetch":{"errors":0,"p50Ms":160.968,"p95Ms":356.915,"p99Ms":356.976,"samples":20},
   "update-check":{"errors":0,"p50Ms":352.139,"p95Ms":569.799,"p99Ms":571.588,"samples":20}},
 "requests":40}
~~~

At the sample point, docker stats reported approximately 238.1 MiB and
239.2 MiB per control-plane container. This is a CAPACITY_BASELINE for one
developer workstation and one small request sample. It is not a capacity
limit, autoscaling rule, throughput guarantee, or production SLO.

## 13. Soak

No 60-minute or longer bounded soak was run. BOUNDED_SOAK — NOT_RUN is an
explicit gate. The short load sample must not be described as soak or endurance
evidence.

## 14. Rolling restart, upgrade, and rollback

The extended rehearsal stopped and returned each control-plane instance in
turn, checked direct and proxied readiness, and continued update-check/fetch.
This is VERIFIED LOCALLY for a same-image rolling restart.

An adjacent-version schema migration, production image upgrade, or real
deployment rollback was not executed. Rolling upgrade is NOT_APPLICABLE to the
current no-migration disposable rehearsal. The operator policy for stopping
traffic, preserving coupled snapshots, restoring an approved compatible build,
verifying readiness, reconciling artifacts, and only then reopening traffic is
DESIGN ONLY.

## 15. Network partitions and edge TLS

No production network partition or public edge TLS test was run. Container
stop/restart and dependency disconnects are bounded local failure injections,
not a partition or public ingress test. Network partition, TLS termination,
certificate overlap, client trust, and connection draining are ENVIRONMENT
GATED / EXTERNAL_PROVIDER_EVIDENCE_REQUIRED.

## 16. Audit, diagnostics, and metrics

The HA run verified audit export validity after multi-instance operations and
wrong-scope rejection. Existing Task 72/74 tests verify exact-scope read-only
diagnostics, audit-chain failure behavior, and process-local metrics reset.
The current bin/control_plane.dart host does not supply the optional diagnostics
adapter or wire the periodic runner, so the reconciliation diagnostics route
is not claimed as an HA HTTP endpoint in this review. NOT_APPLICABLE here means
“not supplied by this host”, not “missing as a designed seam”.

Metrics remain process-local and are not fleet-wide aggregates. Durable audit
and persistence evidence remain authoritative; metrics and diagnostics never
start reconciliation, mutate rollout state, or invoke P3A/P3E-4.

## 17. Image provenance and SBOM boundary

The repository helper produced IMAGE_PROVENANCE_BOUNDED for the HA image:

~~~text
image=hyfens-p2-ha-92092-42226-control-plane-1:latest
image_id=sha256:88cf74b2c724916225629fb116384ff6faa7a61d96aea28a02bbe6fc05ff6245
architecture=arm64
source_tree_digest=sha256:06fc86f900b2b95a40d4dd0f1a333a4e6d30d9855846c1f899714f6ec59eae14
dockerfile_digest=sha256:410df68f7f9e691fd4e78046eae29015663200f0e3a68ca764a628cf8af6354c
~~~

The image still uses floating references (dart:stable, postgres:17-alpine,
minio/minio:latest, minio/mc:latest). No registry signature, immutable base
digest, vulnerability scan, signed attestation, or production SBOM publication
is claimed. The local inventory is VERIFIED LOCALLY as a bounded identity
record; immutable supply-chain evidence is EXTERNAL_PROVIDER_EVIDENCE_REQUIRED
or tooling gated.

## 18. Test and validation results

The consolidated repository validation produced:

- dart analyze --fatal-infos at the root: pass, no issues;
- root dart test: 1 pass;
- dart analyze . --fatal-infos in packages/control_plane: pass;
- dart format --output=none --set-exit-if-changed lib test: 73 files, 0
  changes;
- control-plane tests excluding the known long external crash-process file:
  263 passed, 1 explicit MinIO/S3 skip;
- Compose configuration with disposable required variables: pass;
- bash -n scripts/p2-ha-rehearsal.sh: pass;
- python3 -m py_compile scripts/p2-load-test.py: pass;
- extended HA rehearsal: pass;
- directional DR rehearsal: pass;
- local image provenance inventory: pass with bounded claims.

The full control-plane command including
reconciliation_crash_resilience_test.dart was attempted. That existing
process-marker harness timed out waiting for RESTART_COMPLETE_SUCCESS under the
loaded local environment; the remaining tests continued to pass until the run
was stopped after a second long-running crash scenario. This is recorded as an
environment/test-harness timing gate, not silently converted to pass. Task 74
already contains the completed 5E crash/lock-loss evidence and remains the
authoritative bounded result for that path.

## 19. Prohibited-scope check

The 5F change set adds only the extended disposable rehearsal, Task 75, this
review, factual addenda, and operator-runbook evidence. It adds no queue,
Redis, provider SDK, distributed scheduler, dashboard, alerting service,
rollout writer, P3E-4 mutation, runtime/mobile/compiler code, beta/production
configuration, or store/privacy/legal claim. This boundary is VERIFIED LOCALLY
by targeted repository inspection.

## 20. Open gates

The following remain open and must not be relabeled by this review:

- provider-specific PostgreSQL/object-store failover and durability;
- active readiness-aware edge routing, TLS, certificate rotation, and WAF;
- rolling upgrade with a real adjacent compatible release and migration policy;
- production image pinning, signed provenance, vulnerability/SBOM pipeline;
- bounded soak and representative capacity limits;
- physical power-loss behavior;
- independent real-application validation;
- complete iOS diagnostics/performance and other P1D readiness gates;
- beta, production, App Store, Google Play, privacy, and legal review.

## 21. Conditions for the next design slice

Any provider deployment design must preserve:

1. Architecture B/source instrumentation and the frozen runtime/patch/capability
   authority boundaries;
2. exact-release binding, state-v4 high-water, signed rollback, and fail-closed
   verification;
3. PostgreSQL as the sole coordination authority unless a separately reviewed
   replacement is proved equivalent;
4. immutable object bytes and digest verification;
5. BoundedReconciliationService as the only repair path;
6. tenant authorization, audit/CAS/currentness/postconditions, and no
   rollout-writer or health-event authority expansion;
7. an explicit active readiness/routing model, provider RPO/RTO evidence, and a
   real rollback/upgrade plan before any production claim.

## 22. Maintainer review gate

This document is the stopping point for P3E5-5F. It does not authorize the
next implementation slice automatically. A maintainer must review the local
evidence and explicitly authorize any provider deployment design or later
phase.

## 23. Final disposition

PROCEED TO PROVIDER DEPLOYMENT DESIGN WITH CONDITIONS

Technical conclusion: the existing stateless control plane, shared metadata,
immutable object-store, readiness, audit, and bounded ownership seams survive
the exercised local multi-instance and dependency-failure paths.

Readiness conclusion: no provider, production, beta, store, privacy, or legal
claim is authorized. The next design must close the external gates above with
independent evidence before release claims are considered.
