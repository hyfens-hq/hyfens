# Operational Platform + Customer Management MVP

Status: [*] In Progress

## Goal

Make the separated Customer Workspace and Platform Console operationally useful
with real customer lifecycle management, bounded support cases, and
authorization-scoped commercial/operational projections. Preserve the existing
Organization → Application → Environment domain hierarchy and use real data
only.

## Scope and Non-goals

Scope:

- Add safe customer application/environment update and archive operations.
- Add customer member invitation, role/capability update, and removal
  foundations without exposing platform staff memberships.
- Add tenant-scoped customer support cases and customer-visible replies.
- Add platform support queue, explicit internal notes, assignment/status
  controls, and audit-backed staff actions.
- Add an authorization-scoped commercial projection from the existing billing
  plans/subscriptions source; report unavailable or multi-currency data
  honestly.
- Extend platform organization summaries and dashboard views with real
  support/commercial information.
- Preserve shared auth/API/UI infrastructure, MCP behavior, Patch Format,
  runtime, release semantics, self-hosting, and existing route boundaries.
- Update authoritative product/architecture documentation and the domain
  glossary.

Non-goals:

- No second Project domain; “project” remains a developer-facing synonym for
  Application.
- No support impersonation, enterprise SSO/SCIM, billing-provider integration,
  invoice/payment ledger, advanced analytics, notification platform, or new
  MCP tools.
- No fake revenue, fake health, browser source upload, or browser compilation.
- No framework migration, DNS/production deployment, release tag, package
  publication, Task 210, microtasks, or unrelated cleanup.
- No changes to the separate `backend` or `frontend` repositories.

## Owner

Coordinator — domain/API integration, dashboard integration, validation, and
public repository handoff.

## Dependencies

- Existing dashboard separation on `origin/main`.
- `packages/control_plane` generic persistence, human-session authorization,
  billing projections, audit chain, and HTTP adapter.
- Current dependency-free dashboard bundle and local proxy.
- Repository `AGENTS.md` instructions and existing task history through 244.

## Assumptions

- Customer authorization remains tenant-scoped and server-authoritative.
- Platform routes require the platform audience plus explicit capabilities.
- Existing plans/subscriptions are the only current commercial source; no
  historical monetary ledger is assumed.
- Invitations are a bounded pending-invite foundation; email delivery is not
  invented where no delivery provider exists.
- Archived applications/environments remain recoverable records so historical
  release/deployment evidence is preserved.
- The original development checkout contains unrelated user changes and is
  not modified or staged.

## Work Items

- [x] Record the current READ/CREATE/UPDATE/ARCHIVE/ACTION/MISSING matrix and
  freeze domain/authorization boundaries.
- [x] Implement customer lifecycle, membership, support, and commercial
  service/API contracts with audit and negative authorization coverage.
- [x] Integrate Customer Workspace operational views and mutations.
- [x] Integrate Platform Console commercial, support, organization, and
  operations views.
- [x] Update authoritative documentation and domain vocabulary.
- [x] Review the combined diff and run the relevant validation suite.
- [*] Commit and push the bounded milestone to `origin/main` without a
  release/tag change.

## Validation

Planned:

- Scoped Dart format/analyze and focused control-plane tests for new domain,
  persistence, HTTP, support, commercial, audit, and authorization behavior.
- Dashboard JavaScript syntax/tests and local proxy route tests.
- Markdown local-link validation, secret scan, and `git diff --check`.
- One browser availability check; visual validation is an environment gate if
  no browser connector is available.
- Post-push verification that local HEAD equals `origin/main` and protected
  repositories remain untouched.

## Next Action

Commit and push the reviewed bounded milestone to `origin/main`. No release
tag, production deployment, DNS change, or work in the separate `backend` and
`frontend` repositories is authorized by this task.

## Blockers

None currently.

## Outcome

Implemented the operational MVP on top of the existing separated dashboard:

- Customer application/environment update and archive lifecycle with history
  preservation and tenant checks.
- Customer member role/removal foundations and one-time pending invitations
  backed by hash-only token persistence.
- Customer support cases/replies with customer-only message visibility.
- Platform support queue/detail/actions with explicit staff assignment,
  customer-visible replies, internal notes, and platform-audience audit.
- Read-only commercial projection from active billing plan/subscription
  records, with explicit unavailable and multi-currency states instead of
  fabricated revenue.
- Customer and Platform Console views, navigation, local proxy allow-list
  routes, and current product documentation.

Remaining bounded backlog is intentional: invitation delivery/redemption,
owner transfer, full staff-role administration, browser rollback, billing
provider/payment history, advanced telemetry, support impersonation, and MFA.

## References

- `docs/architecture/dashboard-separation.md`
- `docs/product/customer-workspace.md`
- `docs/product/platform-console.md`
- `packages/control_plane/lib/src/domain.dart`
- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/service.dart`
- `packages/control_plane/lib/src/http.dart`
- `dashboard/app.js`

## History

- 2026-09-03 — Reserved task 245 from the clean public `origin/main` worktree.
  Confirmed the current customer/platform READ/CREATE/ACTION foundations and
  the bounded gaps for operational support, commercial projection, lifecycle
  mutation, and customer membership management.
- 2026-09-03 — Implemented the bounded backend contracts, dashboard surfaces,
  proxy routes, tests, and authoritative documentation. Focused Dart and
  dashboard validation passed; full Dart suite still contains 16 unrelated
  pre-existing reconciliation/P3E failures. Browser visual acceptance is an
  external environment gate because no browser was available.
