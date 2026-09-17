# Task 264 — Public control-plane development naming

Status: [x] Completed

## Goal

Replace the ambiguous `p2-r2` identity used by the active R2-backed public
control-plane development deployment with explicit development-oriented names.

## Scope and Non-goals

In scope:

- the active R2-backed Compose project and file name;
- the protected environment-file reference;
- the host deployment target and fixed deployment-wrapper name;
- the platform-user bootstrap helper and dashboard deployment handoff;
- active deployment documentation and validation.

Out of scope:

- historical review records and research logs;
- the local, HA, or disposable P2 fixtures;
- Cloud API, Customer Workspace, authentication, billing, or runtime behavior;
- public traffic cutover or a production deployment;
- renaming the existing PostgreSQL volume in this bounded change.

## Owner

Codex, with maintainer review for any root-owned host migration.

## Dependencies

- `deploy/p2/` public control-plane deployment sources;
- the dashboard deployment handoff in `deploy/web/`;
- the existing dev host deployment staging and Docker Compose conventions.

## Assumptions

- the deployment currently called `p2-r2` is the R2-backed public control-plane
  development stack;
- the existing PostgreSQL data volume must remain attached during renaming;
- the current primary checkout contains unrelated developer-owned changes that
  must not be reset, cleaned, or overwritten.

## Work Items

- [x] Audit active and historical `p2-r2` references and identify the safe
  rename boundary.
- [x] Rename active development identifiers and update their consumers.
- [x] Validate Compose, shell scripts, documentation, and reference cleanup.
- [x] Prepare/perform the bounded dev-host migration after maintainer review.

## Validation

Completed on 2026-09-17:

- `sh -n` passed for the changed deployment, worker, bootstrap, and dashboard
  handoff scripts.
- Docker Compose config rendering passed with non-secret placeholder values.
- `git diff --check` passed.
- Active-reference review confirmed the explicit development identifiers are
  used by the current deployment path; remaining `p2-r2` references are the
  wrapper rollback fallback, the preserved PostgreSQL volume, or historical
  records.
- Read-only dev-host checks confirmed the renamed containers are running, the
  protected environment files are `root:root 600`, and the deletion,
  notification, and artifact-retention timers are enabled and active.

## Next Action

Retain the legacy `p2-r2` target and environment as the deployment wrapper's
explicit rollback fallback until a separately approved cleanup removes them.

## Blockers

None. Legacy fallback files are intentionally retained for rollback safety and
are outside this naming-only cleanup.

## Outcome

The active R2-backed public control-plane development deployment now uses the
explicit `public-control-plane-dev` identifiers across Compose, wrappers,
workers, timers, bootstrap, dashboard handoff, and operations documentation.
The host migration is verified live with the renamed control-plane containers,
protected environment, and all three worker timers enabled and active. The
legacy `p2-r2` target, environment, project name, and PostgreSQL volume name
remain only where required for rollback/data continuity.

## References

- `deploy/p2/docker-compose.public-control-plane-dev.yml`;
- `deploy/p2/bootstrap-platform-users.sh`;
- `deploy/web/install-dashboard-deploy-access.sh`;
- `/etc/hyfens/p2-r2.env` and `/opt/hyfens/p2-r2` on the dev host.

## History

- 2026-09-08 — Reserved task 264 after confirming the repository has no
  existing numeric 264 task record; began the bounded naming audit.
- 2026-09-17 — Completed source and host validation. Compose rendering,
  shell syntax, diff checks, and active-reference review passed. The dev host
  is running `hyfens-public-control-plane-dev`; its protected environment and
  deletion, notification, and artifact-retention timers are verified. The
  legacy `p2-r2` target remains as the explicit migration fallback.
