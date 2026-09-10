# P2 production-readiness runbook

Each procedure is labeled by evidence level. `VERIFIED LOCALLY` means the
repository test or disposable rehearsal actually executed it. `DESIGN ONLY`
means the boundary is specified but not a production proof. `PROVIDER
DEPENDENT` requires an operator-selected deployment provider. `EXTERNAL REVIEW
REQUIRED` is not an engineering pass.

## Deploy and start

1. Inject PostgreSQL/object-store credentials from the operator secret store;
   do not put them in Compose files or shell history. (`DESIGN ONLY`)
2. Start the control plane with the exact runtime/format versions selected by
   the release. (`VERIFIED LOCALLY`)
3. Confirm `/healthz` and `/readyz`; readiness must include PostgreSQL and the
   artifact store. (`VERIFIED LOCALLY`)
4. Keep the listener loopback-only unless a TLS proxy and edge policy are in
   place. (`VERIFIED LOCALLY` + `PROVIDER DEPENDENT`)

## Normal release and delivery

1. Verify the patch locally against the exact application release and trusted
   public key.
2. Register the release, patch, and artifact with idempotency keys.
3. Upload bytes; the control plane verifies Patch Format identity, digest, and
   signature before marking the artifact ready.
4. Promote with the expected environment version.
5. Exercise update-check and artifact fetch from a delivery credential.

Steps 1–5 are `VERIFIED LOCALLY` by the control-plane tests and the HA/DR
rehearsals. Public deployment, TLS, and store approval remain external gates.

## Backup, restore, and reconciliation

1. Quiesce writes or record the backup consistency point.
2. Run `scripts/p2-postgres-backup.sh` and `scripts/p2-object-backup.sh` to
   separate destinations; retain the object manifest and database dump digest.
3. Confirm the target is disposable/recovery-approved and set
   `HYFENS_ALLOW_RESTORE=1` only for the restore command.
4. Restore metadata and object bytes together.
5. Run the artifact reconciliation route and require `deliverable: true` with
   no unexpected inventory or digest items.
6. Verify audit-chain validity, exact artifact digest, update-check, and fetch.

The complete local sequence is `VERIFIED LOCALLY` by
`scripts/p2-dr-rehearsal.sh`. Off-host durability, retention, and approved RPO/
RTO are `PROVIDER DEPENDENT`.

## Availability and dependency incidents

* **One control-plane instance lost:** keep the proxy on the remaining healthy
  instance, verify readiness, retry an idempotent control write, then restart
  the lost instance. (`VERIFIED LOCALLY`)
* **Rolling restart:** restart one instance at a time and verify readiness and
  update-check after each. (`VERIFIED LOCALLY`)
* **PostgreSQL/object dependency outage:** expect `/healthz` to remain a
  process liveness signal while `/readyz` returns `503`; do not accept writes
  until readiness returns. (`VERIFIED LOCALLY`)
* **Database/object failover:** no automatic failover is implemented in P2;
  follow the provider's recovery procedure. (`PROVIDER DEPENDENT`)

## Credentials and signing incidents

* Revoke compromised control/delivery/object/database credentials and issue
  replacements; inspect the redacted audit trail. (`VERIFIED LOCALLY` for
  credential semantics; operational revocation is `DESIGN ONLY`.)
* A lost patch-signing key cannot be replaced silently. A new trusted public
  key requires a new store release according to the current trust boundary.
  (`VERIFIED LOCALLY` / `EXTERNAL REVIEW REQUIRED` for policy.)
* A compromised audit-export key affects export authenticity, not runtime patch
  authority. Freeze exports, publish a new audit key ID, and retain the old
  public key for historical verification. (`DESIGN ONLY`.)
* Rotate TLS certificates at the edge with overlap and client verification.
  (`PROVIDER DEPENDENT`.)

## Rollback and safe shutdown

Client runtime rollback/high-water state is authoritative and must not be
rewritten by a control-plane rollback. For a control-plane rollback, stop
traffic, preserve database/object snapshots, restore only an approved
compatible build, verify readiness, reconcile artifacts, and run update-check
before re-opening traffic. (`DESIGN ONLY` for production; the client/runtime
invariant is `VERIFIED LOCALLY`.)

## Evidence retention

Retain command output, timings, compose/config digest, backup manifest, audit
export, and the exact operator decisions. Remove tokens and private material
before sharing evidence. A signed audit export is an offline evidence artifact,
not a production authorization credential.

## Provider-neutral multi-instance rehearsal (P3E5-5F)

The following sequence is a disposable local rehearsal only. It is not a
provider deployment procedure and must not be run against a production
endpoint.

1. Set disposable PostgreSQL and S3-compatible credentials in the shell.
2. Use a unique Compose project and a private local port.
3. Run `HYFENS_HA_EXTENDED=1 ./scripts/p2-ha-rehearsal.sh`.
4. Require both direct instance `/livez` and `/readyz` checks before traffic.
5. Stop each control-plane instance in turn; verify the remaining instance,
   proxy update-check, exact artifact bytes, request IDs, and audit validity.
6. Stop PostgreSQL alone and object storage alone; expect process liveness to
   remain separate from dependency-aware readiness, and reject writes/fetches
   until readiness recovers.
7. Retain the timing and capacity output with the exact image/source digest.
8. Run the coupled backup/restore rehearsal only against an approved
   disposable target with `HYFENS_ALLOW_RESTORE=1`.

P3E5-5F recorded this sequence as `VERIFIED LOCALLY` for the repository
topology. The Nginx fixture uses static upstreams and passive retry; it does
not provide active readiness-aware removal. Provider failover, public TLS,
network partitions, image attestation, provider durability, and RPO/RTO are
`PROVIDER DEPENDENT` or `EXTERNAL REVIEW REQUIRED`. The short load sample is a
`CAPACITY BASELINE`, not a soak or SLO.

The current HTTP host does not wire the optional reconciliation diagnostics
adapter or periodic runner. Do not infer fleet-wide metrics or automatic
repair ownership from this runbook; use the explicit host wiring and the
existing PostgreSQL ownership seam under separate review.
