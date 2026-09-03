# Dashboard MVP Completion + Documentation Cleanup

Status: [x] Completed

## Goal

Complete the highest-value supported Customer Workspace and Platform Console
MVP gaps without changing their separation, then make the current repository
documentation easy to navigate by consolidating current guidance and moving
or removing superseded milestone noise based on evidence.

## Scope and Non-goals

Scope:

- Complete safe customer application/environment lifecycle foundations where
  existing domain and authorization contracts support them.
- Complete customer member and credential issuance foundations with tenant,
  capability, expiry, one-time-secret, and audit protections.
- Add safe browser deployment/rollback actions only where existing backend
  contracts already support the operation; otherwise retain honest CLI
  handoffs.
- Improve customer CLI onboarding and real-data overview content.
- Add bounded platform users/roles, organization commercial metadata,
  plans/entitlements visibility, operations status, and platform audit views
  only where supported by real backend data.
- Preserve shared authentication/API/UI infrastructure and explicit customer
  and platform authorization audiences.
- Inventory and rationalize `docs/`, create an authoritative `docs/README.md`,
  repair links, and move or remove historical/superseded documentation using
  evidence-based classification.
- Run focused authorization, lifecycle, dashboard, browser (if available),
  and documentation validation and record the result in the task file.

Non-goals:

- No collapse or redesign of Customer Workspace and Platform Console.
- No DNS changes, production deployment, framework migration, or new
  enterprise phase.
- No support impersonation, SSO/SCIM, advanced billing, rollout engine,
  telemetry, or speculative RBAC.
- No browser source upload or fake release/patch creation; source-dependent
  workflows remain CLI-driven.
- No deletion of legal/security/licensing/provenance documentation.
- No blind deletion of historical evidence, task records, ADRs, or research.
- No destructive Git operations, unrelated cleanup, Task 210, or microtasks.

## Owner

Coordinator — dashboard MVP integration and documentation governance

## Dependencies

- `docs/HYFENS_DASHBOARD_SEPARATION_IMPLEMENTATION_REVIEW.md`
- `docs/architecture/dashboard-separation.md`
- Existing dashboard under `dashboard/`
- Existing control-plane HTTP/auth/service modules under
  `packages/control_plane/`
- Existing dashboard, control-plane, CLI, and documentation tests
- Repository-local `CONTEXT.md` domain vocabulary

## Assumptions

- `app.hyfens.com` remains the Customer Workspace concept.
- `admin.hyfens.com` remains the managed Platform Console concept.
- Self-hosted instances use the same customer product model with capability-
  driven differences.
- Backend authorization and audit are authoritative for every new mutation.
- Existing unrelated dirty worktree changes belong to the user and must be
  preserved.
- Documentation history may be retained under clearly labeled history or
  research paths when it has durable evidence value.

## Work Items

- [x] Freeze the bounded MVP gap list and inventory current dashboard/API/docs
  state.
- [x] Implement the highest-value supported Customer Workspace foundations.
- [x] Implement the highest-value supported Platform Console foundations.
- [x] Add or preserve honest CLI handoffs for source-dependent lifecycle work
  and implement only safe existing browser actions.
- [x] Add focused authorization, tenant-isolation, lifecycle, credential,
  dashboard, and responsive/browser tests.
- [x] Classify, consolidate, archive, remove, and relink documentation with a
  concise authoritative index.
- [x] Review the combined diff, run consolidated validation, and record the
  final outcome and backlog.

## Validation

- PASS — `dart format --output=none --set-exit-if-changed` on all changed
  control-plane Dart sources/tests.
- PASS — `dart analyze` in `packages/control_plane`.
- PASS — focused control-plane tests (`control_plane_test.dart`,
  `platform_metrics_http_test.dart`, and `human_auth_test.dart`): 16 tests.
- PASS — `python3 -m unittest dashboard/test_serve.py`: 34 tests.
- PASS — `node --check dashboard/app.js` and `dashboard/auth-flow.js`.
- PASS — `git diff --check`.
- PASS — local Markdown-link scan: 397 Markdown files checked, zero broken
  local links.
- PASS — focused high-confidence secret-pattern scan: 1,029 files scanned,
  zero matching files; legal/security/provenance files preserved.
- ENVIRONMENT GATE — browser visual capture was attempted, but no browser
  connector was available in this session. Route/proxy and syntax validation
  passed; no production routing was changed.
- NOT RUN — unrelated full historical Dart suites; prior known reconciliation
  and P3E failures are outside this milestone and no changed contract made
  them direct blockers.

## Next Action

No further implementation is part of this milestone. Future work may address
the explicitly documented backlog: application/environment update/archive,
member invitations and role mutation, browser rollback, full platform staff
administration, richer operational signals, and browser visual acceptance when
the environment provides a browser connector.

## Blockers

None for the bounded implementation. Browser visual validation remains an
environment gate only; it does not invalidate the route, authorization, API,
or documentation acceptance completed here.

## Outcome

HYFENS DASHBOARD MVP + DOCS CLEANUP — COMPLETE WITH BACKLOG

Customer Workspace now has real tenant-scoped application and environment
creation, credential issuance/revocation handling with one-time plaintext,
and a safe promotion action. Source-dependent release/patch creation and
rollback remain honest CLI handoffs. Platform Console now has bounded platform
users, organization directory/detail, plans/entitlements, operations, and
platform-audience audit views. Customer and platform shells, navigation,
audiences, and API projections remain separate while authentication, transport,
tokens, formatting, and UI primitives remain shared.

Documentation was consolidated into an authoritative `docs/README.md`, current
customer/platform product guides, and a clearly labeled history area. Forty-
seven root milestone/review/design records and five superseded product records
were moved out of the current documentation paths; legal, security,
licensing, provenance, ADR, research, specification, operations, and task
records were preserved. Local Markdown links are clean.

## References

- `docs/HYFENS_DASHBOARD_SEPARATION_IMPLEMENTATION_REVIEW.md`
- `docs/architecture/dashboard-separation.md`
- `dashboard/index.html`
- `dashboard/app.js`
- `dashboard/serve.py`
- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/service.dart`
- `CONTEXT.md`

## History

- 2026-09-03 — Reserved task 244 for the bounded dashboard MVP completion and documentation cleanup milestone. Preserved the implemented customer/platform separation and excluded Task 210/microtasks.
- 2026-09-03 — Completed the bounded customer/platform MVP foundations, focused validation, and evidence-based documentation cleanup. Recorded the remaining safe backlog and browser environment gate; no commit, push, DNS change, or production deployment was performed.
