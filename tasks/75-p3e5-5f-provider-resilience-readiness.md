# Task 75 — P3E5-5F provider-resilience readiness

Status: [x] Completed

## Goal

Define and validate the provider-neutral operational contracts required before
any real provider deployment is considered, using only disposable local
infrastructure and the existing control-plane authority boundaries.

## Scope and Non-goals

In scope: the existing two-instance Compose topology; shared PostgreSQL and
S3-compatible object storage; reverse-proxy and readiness routing; advisory
ownership across instances; database/object-store outage and recovery;
rolling restart; coupled backup/restore; directional capacity and bounded-soak
measurements where practical; shared audit/diagnostics/metrics semantics;
deployment and migration rollback policy; operator runbook evidence; and
explicit environment/tooling gates.

Out of scope: production-provider deployment or failover, queues, Redis,
distributed schedulers, rollout writers, P3A/P3E-4 mutation, runtime/mobile/
compiler work, beta/production approval, store/privacy/legal work, physical
power-loss, independent application validation, and any new repair path.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 71 bounded reconciliation execution and persistence.
- Task 72 observability/readiness/diagnostic seams.
- Task 73 disabled-by-default periodic runner and PostgreSQL ownership pool.
- Task 74 local process/session-loss resilience evidence.
- Explicit authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_P3E5_5F_PROVIDER_RESILIENCE_READINESS.md`.

## Assumptions

- Existing P2 Compose rehearsals are disposable and provider-neutral; they are
  not provider HA, production SLO, or production-readiness evidence.
- PostgreSQL remains the shared coordination and metadata store; the existing
  advisory lock remains the only periodic ownership mechanism.
- S3-compatible object storage remains an immutable byte store and never a
  runtime trust authority.
- File storage remains single-process/single-writer and is not promoted to a
  multi-instance backend.
- Customer/local patch signing and runtime-authoritative verification remain
  frozen.

## Work Items

- [x] Reserve Task 75 and freeze the provider-neutral-only boundary.
- [x] Revalidate the two-instance Compose, reverse-proxy, readiness, shared
  PostgreSQL/object-store, and tenant-scope topology.
- [x] Exercise all practical instance-availability and rolling-restart paths,
  including advisory ownership handoff and no duplicate semantic repair.
- [x] Exercise dependency outage/recovery, object corruption/missing/orphan
  reconciliation, shared audit integrity, and record diagnostics/metrics as
  host-supported or explicitly `NOT_APPLICABLE`.
- [x] Rehearse coupled backup/restore and document migration/deployment
  rollback policy without destructive schema changes.
- [x] Run bounded capacity/soak measurements where the local environment can
  support them; record hardware, configuration, latency, errors, and limits.
- [x] Record provider failover, SBOM, image provenance, network partition, and
  rolling-upgrade status as verified, not applicable, or environment/tooling
  gated without fabrication.
- [x] Update the provider-neutral operator runbook, 5D/5E factual addenda,
  design/ADR references, and the 5F review; stop at maintainer review.

## Validation

Executed validation and evidence:

- `COMPOSE_PROGRESS=quiet HYFENS_HA_EXTENDED=1 HYFENS_HA_PORT=18085
  ./scripts/p2-ha-rehearsal.sh`: PASS; two instances, both loss directions,
  readiness, dependency outages, exact fetch, audit, request IDs, and 40
  requests at concurrency 8.
- `HYFENS_ALLOW_RESTORE=1 ./scripts/p2-dr-rehearsal.sh`: PASS; directional
  coupled backup/restore and identical source/restored digest.
- `./scripts/p2-provenance-inventory.sh
  hyfens-p2-ha-92092-42226-control-plane-1:latest`: bounded local image
  identity/source/config digests; no attestation or immutable base claim.
- `bash -n scripts/p2-ha-rehearsal.sh`, Python bytecode compilation, and
  Compose config with disposable variables: PASS.
- Root `dart analyze --fatal-infos` and `dart test`: PASS (1 root test).
- Control-plane `dart analyze . --fatal-infos` and format check: PASS (73 files,
  0 changes).
- Control-plane tests excluding the known long crash-process harness:
  263 passed, 1 explicit MinIO/S3 environment skip. The complete command was
  also attempted; its existing process-marker crash harness timed out in the
  loaded local environment and is recorded as a test-harness timing gate.

The runbook, review, 5D/5E/design/ADR addenda, and prohibited-scope boundary
were inspected and updated. Markdownlint, local-link, whitespace, secret,
prohibited-dependency, shell syntax, Python syntax, and Compose-config checks
passed in the final repository pass.

## Next Action

Stop at the maintainer-review gate. Do not begin provider deployment design or
any later P3E5 phase without a new explicit authorization.

## Blockers

No blocker remains within the authorized provider-neutral 5F evidence scope.
The following external/readiness gates remain open and cannot be closed by this
task: provider-specific database/object failover and durability; active
readiness-aware edge routing and public TLS; rolling upgrade; immutable image
provenance/SBOM and vulnerability tooling; bounded soak; physical power loss;
independent application validation; complete iOS/P1D evidence; beta,
production, App Store, Google Play, privacy, and legal review.

## Outcome

Provider-neutral local readiness evidence is complete within the authorized
boundary. The extended HA rehearsal, directional DR rehearsal, validation
commands, timings, capacity sample, and explicit external gates are recorded
in `docs/P3E5_5F_PROVIDER_RESILIENCE_READINESS_REVIEW.md`.

Final recommendation: `PROCEED TO PROVIDER DEPLOYMENT DESIGN WITH CONDITIONS`.
Stop at maintainer review; this task does not authorize provider deployment,
beta, production, store submission, privacy, or legal claims.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_P3E5_5F_PROVIDER_RESILIENCE_READINESS.md`
- `/Volumes/970EvoPlus/Downloads/P3E5_5E_CRASH_LOCK_LOSS_RESILIENCE_REVIEW.md`
- `/Volumes/970EvoPlus/Downloads/74-p3e5-5e-crash-lock-loss-resilience.md`
- `docs/P3E5_5E_CRASH_LOCK_LOSS_RESILIENCE_REVIEW.md`
- `deploy/p2/docker-compose.ha.yml`
- `scripts/p2-ha-rehearsal.sh`
- `scripts/p2-dr-rehearsal.sh`

## History

- 2026-08-25 — Task 75 reserved under explicit P3E5-5F authorization. The
  existing P2 local Compose/backup/provenance helpers are reused; no provider
  deployment, queue, Redis, or production claim is authorized.
- 2026-08-25 — Extended HA rehearsal passed in disposable project
  `hyfens-p2-ha-92092-42226` with both instance-loss directions, separate
  dependency outages, request-ID/auth checks, exact artifact recovery, and
  local capacity baseline. Directional DR and provenance inventory passed with
  bounded claims. Repository validation and the 5F review/addenda were
  completed; external provider and production gates remain open.
