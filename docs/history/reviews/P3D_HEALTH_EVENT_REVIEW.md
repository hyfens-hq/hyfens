# P3D health-event ingestion review

Status: `READY FOR MAINTAINER REVIEW`
Date: 2026-08-24
Task: repository `tasks/52-p3d-health-event-ingestion.md` (the supplied P3D
document used number 51, but repository Task 51 is already reserved for the
completed physical-iOS rerun)

<!-- markdownlint-disable MD013 -->

## Scope

P3D was implemented without changing Architecture B, Patch Format v1,
capability v1, state-v4 high-water, runtime signature authority, signed
rollback, AOT fallback, or customer/local signing custody. No mobile runtime
code, dashboard, aggregation, automatic halt, or hosted provider component
was added.

## Verified findings

| Area | Evidence | Result |
| --- | --- | --- |
| Observation schema | `observation.dart`, `observation_test.dart` | Schema v1, bounded vocabulary, deterministic canonical body, scalar safe metadata, platform and identity bounds pass unit/service tests. |
| Token boundary | `CredentialKind.observation`, service and HTTP tests | Short-lived app/environment-scoped token with only `observation:write`; expiry, revocation, cross-tenant use, and control-route use fail closed. |
| Event identity | Service tests and trusted release lookup | Organization/application/environment/release/patch/rollout claims are checked against persisted records; unknown/mismatched identity is rejected. |
| Idempotency | File service tests; PostgreSQL store integration | Same event ID and canonical body is acknowledged as duplicate; mutated reuse returns `EVENT_DUPLICATE_MUTATION` and creates a redacted audit event. |
| Lifecycle safety | Service tests | Impossible `healthy_confirmed`, `activation_succeeded`, `activation_failed`, and `restart_survived` sequences are quarantined and do not influence later decisions. |
| Clock/retention | Service tests | Future-skew and outside-retention events are rejected; late events are marked; deletion changes observation rows only. |
| Limits | Service and HTTP tests | Event/metadata size, per-token/install/type windows, bounded diagnostic codes, and HTTP body limits are enforced. |
| PostgreSQL rollout CAS | `postgres_store_test.dart` against PostgreSQL 17 container | Two independent stores targeting one rollout produced one applied transition and one `StoragePreconditionFailed`; revision, pointer, idempotency, and audit were persisted transactionally. |
| PostgreSQL observations | `postgres_store_test.dart` against PostgreSQL 17 container | Migration v2 applied; duplicate event insert is durable and retention deletion removes the scoped row. |
| Existing behavior | Full `packages/control_plane` suite | All tests passed with PostgreSQL integration configured; MinIO integration remained skipped because its test environment was not configured. |

## Validation commands and results

- `dart analyze --fatal-infos` in `packages/control_plane`: passed.
- `dart test` in `packages/control_plane` with `HYFENS_TEST_POSTGRES_URL`
  pointing at the local PostgreSQL 17 test container: 53 tests passed; one
  MinIO integration test was skipped because `HYFENS_TEST_S3_*` was absent.
- `dart analyze .` at repository root: passed.
- `dart test` at repository root: passed.

No physical Android or iOS rerun is claimed. P3D does not modify the mobile
runtime or application binaries; the earlier physical-device evidence remains
the bounded P2/P1D evidence recorded in the existing review documents.

## Security and privacy boundary

Observation records are advisory data, not runtime truth. The service rejects
raw installation IDs, code, bytes, stacks, paths, tokens, private keys, and
business/user payloads. It stores only a privacy-minimized bucket/cohort,
bounded scalar metadata, stable diagnostic code, trusted release identity, and
server receipt/disposition. Logs use the existing redacted error envelope.

PostgreSQL rollout transitions take a fixed advisory lock before the rollout
row lock, then commit the immutable revision, current pointer, idempotency
record, and audit chain in one transaction. The File adapter exposes the same
seam for single-node self-host tests but does not claim cross-process safety.

## Not implemented by P3D

P3E aggregation, health scoring, metric-poisoning policy, automatic halt or
expansion, P3F operator API expansion, P3G dashboard/alerting, runtime upload
queues, crash analytics, managed KMS/HSM, provider production hardening,
percentage rollouts beyond the existing P3A implementation, and store/legal
review remain outside this slice.

## Remaining risks

- Observation outage behavior is isolated by API design but has no mobile
  client queue/fault-injection campaign because runtime integration is not in
  P3D scope.
- PostgreSQL evidence is against a local container, not a production HA,
  backup, failover, or provider deployment.
- Retention/deletion and safe metadata policy still require deployment-specific
  privacy/legal review; no compliance claim is made.
- Existing independent-app, power-loss, broad iOS performance, provider, and
  Apple/Google gates remain open.

## Recommendation

**PROCEED TO P3E DESIGN** — P3D engineering evidence is sufficient for a
separate maintainer design review. Do not begin P3E implementation until a new
task and explicit authorization are recorded. P3D itself stops here.
