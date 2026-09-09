# Dashboard Separation Audit

Status: [x] Completed

## Goal

Produce a factual, read-only architecture and UX audit of the current Hyfens dashboard, distinguishing the Hyfens Platform Console from the Hyfens Customer Workspace and recommending a bounded separation plan.

## Scope and Non-goals

Scope:

- Inventory the current dashboard routes, shell, navigation, context selectors, frontend API calls, backend handlers, authorization, roles, and CRUD coverage.
- Classify current surfaces by platform, customer, shared, mixed, or unknown audience.
- Identify missing capabilities and recommend future routing, repository, shell, and migration boundaries.
- Create `docs/HYFENS_DASHBOARD_SEPARATION_AUDIT.md`.

Non-goals:

- No dashboard redesign or implementation.
- No backend, API, DNS, repository, authorization, or data-model changes.
- No deletion, rename, migration, or new numbered microtask.

## Owner

Coordinator — dashboard architecture and product-boundary audit

## Dependencies

- Current dashboard source under `dashboard/`.
- Current control-plane source and tests under `packages/control_plane/`.
- Existing public/self-hosted product documentation.
- Current working-tree state, including prior user changes.

## Assumptions

- The audit describes the current checkout as inspected; it does not infer unimplemented product behavior from roadmap language.
- Existing dirty worktree changes are preserved and are evidence only where directly visible in the inspected source.
- The supplied screenshots are supporting UX evidence; no fresh browser capture is required to complete the code audit.

## Work Items

- [x] Inventory dashboard frontend structure, routes, navigation, and shells.
- [x] Map dashboard API calls to control-plane endpoints and authorization.
- [x] Classify roles, audiences, mixed pages, and CRUD capability coverage.
- [x] Reconcile findings into the required separation report.
- [x] Review report evidence and record validation results.

## Validation

- Read-only source inspection with `rg`, `nl`, and `sed` across dashboard and control-plane code.
- Targeted dashboard tests where available, without changing implementation.
- Markdown/report review for all required sections, explicit classifications, and the final disposition.
- Confirm only this task file and the audit report are intentional changes from this task.

## Next Action

Audit complete. Any dashboard separation implementation must be separately authorized and scoped from the recommendations in the report.

## Blockers

None currently.

## Outcome

Created `docs/HYFENS_DASHBOARD_SEPARATION_AUDIT.md` with a factual current-state inventory and recommended separation plan. The current dashboard is one static, read-only customer record inspector with a narrow platform-metrics page embedded in the same shell. Tenant overview reads and platform metrics have separate backend protections, but the UX, route tree, profile/context model, and settings/audit surfaces mix customer and platform responsibilities. No dashboard, backend, DNS, repository, or authorization implementation was performed.

## References

- `dashboard/index.html`
- `dashboard/app.js`
- `dashboard/serve.py`
- `packages/control_plane/lib/`
- `packages/control_plane/test/`
- `docs/architecture/domain-tenancy.md`
- `docs/architecture/control-plane.md`

## History

- 2026-09-03 — Reserved task 242 for the bounded dashboard separation audit; implementation explicitly frozen.
- 2026-09-03 — Completed frontend inventory, backend/API mapping, role/audience and CRUD analysis, mixed-page findings, security review, and the required separation report. Final disposition: `DASHBOARD SEPARATION — CURRENT STATE UNDERSTOOD`.
- 2026-09-03 — Validation: reviewed report headings and required sections; `git diff --no-index --check /dev/null docs/HYFENS_DASHBOARD_SEPARATION_AUDIT.md` returned no whitespace errors; confirmed only the task/report are this audit's intentional outputs while pre-existing dashboard/control-plane changes remain untouched.
