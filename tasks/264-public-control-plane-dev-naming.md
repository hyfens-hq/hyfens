# Task 264 — Public control-plane development naming

Status: [*] In Progress

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
- [*] Rename active development identifiers and update their consumers.
- [ ] Validate Compose, shell scripts, documentation, and reference cleanup.
- [ ] Prepare/perform the bounded dev-host migration after maintainer review.

## Validation

Planned checks:

- `git diff --check` for the task-owned changes;
- `sh -n` for changed shell scripts;
- Docker Compose config rendering with non-secret test values;
- active-reference search proving old names remain only where intentionally
  historical or compatibility-preserving;
- read-only dev-host checks after any approved migration.

## Next Action

Complete the source rename and validation, then present the exact bounded host
migration if the dev deployment is to adopt the new names.

## Blockers

None for source changes. Host migration requires maintainer-approved root
actions if the protected environment, `/opt/hyfens`, or `/usr/local/sbin` must
be changed.

## Outcome

Pending.

## References

- `deploy/p2/docker-compose.r2.yml` (renamed by this task);
- `deploy/p2/bootstrap-platform-users.sh`;
- `deploy/web/install-dashboard-deploy-access.sh`;
- `/etc/hyfens/p2-r2.env` and `/opt/hyfens/p2-r2` on the dev host.

## History

- 2026-09-08 — Reserved task 264 after confirming the repository has no
  existing numeric 264 task record; began the bounded naming audit.
