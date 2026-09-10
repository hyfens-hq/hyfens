# P2 operator runbook (bounded hosted-like foundation)

This runbook covers the single-node Compose fixture only. It is not a high
availability or internet-scale production procedure and does not authorize a
managed service, dashboard, telemetry backend, billing, or P3 work.

## Configuration boundary

Inject `HYFENS_DATABASE_URL`, object-store credentials, host/port, and request
limits through the process environment or a secret-file mechanism supplied by
the deployment platform. Do not commit `.env` files or print these values.
Runtime patch signing keys remain customer/local authority and are registered
on the exact release; the hosted service must not mint or replace them.

## Startup and health

1. Start PostgreSQL and the S3-compatible object store.
2. Ensure the immutable artifact bucket exists and the control-plane identity
   can PUT/GET objects but cannot overwrite an existing digest.
3. Start the control-plane container and wait for `/readyz` (not merely
   `/healthz`).
4. Put TLS termination, trusted-forwarded-header handling, upload/body limits,
   connection timeouts, and request IDs in a maintained reverse proxy. The Dart
   service does not implement custom TLS or trust arbitrary forwarded headers.

`/healthz` is process liveness. `/readyz` performs metadata-store and
object-store bucket probes and returns `503` when either configured dependency
or the migration boundary is unavailable. `/metrics` exposes process-local
aggregate request counts, status classes, update decisions, and duration
totals/maxima; it is operator measurement, not runtime telemetry.

## Backup and restore

Use `scripts/p2-postgres-backup.sh` with a local output path and retain the
result with the object-store backup. Restore only to an explicitly approved
disposable/recovery target with `HYFENS_ALLOW_RESTORE=1`, then verify:

- organization/application/environment identities;
- release and patch metadata and promotion version;
- idempotency records and audit records;
- artifact metadata and object bytes/digests;
- authenticated runtime update-check and artifact fetch.

An object-store backup is independent of PostgreSQL. A missing object must
fail closed as an artifact-corruption/delivery error; it must never become a
new patch or silently fall back to an unverified object.

## Outage/recovery procedure

Stop delivery writes, preserve request IDs and redacted service logs, restore
the failed dependency, verify `/readyz`, and replay only idempotent requests.
The runtime remains on its last known-good local state while the control plane
is unavailable. Do not change release binding, runtime signature authority,
or rollback semantics during recovery.

For a repeatable non-mutating sample, set `HYFENS_LOAD_TOKEN` to a read-only
delivery credential and run `scripts/p2-load-test.py` with one exact
application/environment/release/artifact identity. Record the machine,
container configuration, request count, concurrency, latency percentiles, and
errors. Do not treat one local sample as an SLO or capacity commitment.
