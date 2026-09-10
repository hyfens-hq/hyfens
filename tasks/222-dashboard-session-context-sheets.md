# Task 222: Dashboard session, organization context, and record sheets

Status: [x] Completed

## Goal

Make dashboard session restoration feel stable, make the sidebar organization context a real multi-organization switcher, and open exact records in a bottom modal sheet without shifting table rows.

## Scope and Non-goals

Scope:

- Keep both login and dashboard surfaces hidden behind an explicit session-pending boot state and neutral loading surface until session restoration or discovery has resolved.
- Preserve authenticated sessions across refresh while showing the dashboard only after identity and the first overview request are safely initialized.
- Add organization selection backed by the authenticated identity’s memberships, with a safe fallback label when an organization name is not yet available.
- Keep profile, application, and environment context consistent when the active organization changes and load only the selected organization’s overview.
- Replace inline exact-record expansion with a reusable bottom modal sheet that supports close, Escape, backdrop click, focus restoration, and accessible dialog semantics.
- Avoid repeating the panel’s returned-count caption in the default collection toolbar while retaining status messaging for active filters and truncated responses.
- Continue using clean History API routes and local icon assets.

Non-goals:

- No backend schema, auth protocol, authorization, Python server, Docker, or completed-task changes.
- No exposure of secrets, session tokens, password hashes, or untrusted record HTML.

## Owner

Coordinator, with GPT-5.6-Luna Max fast-mode workers owning the behavior files and the coordinator-owned focused regression contracts.

## Dependencies

- Authenticated `/auth/me` profiles already return organization, application, environment, role, and profile-name fields.
- Existing `sessionStorage` session envelope and `DashboardApi` refresh behavior.
- Task 221 supplies the shared CSS for `session-pending`, the organization selector, and record-sheet classes.
- Existing local icon assets under `dashboard/icons/`.

## Assumptions

- One identity profile represents one selectable organization membership; multiple profiles may belong to one organization.
- Organization names can be taken from the loaded overview; other memberships use a neutral label until selected rather than leaking IDs into the sidebar card.
- The current organization remains the initial selection after sign-in, and selecting another organization resets application/environment filters before loading its authoritative overview.

## Work Items

- [x] Add the session-pending boot marker and prevent login/dashboard surface flicker during async restoration.
- [x] Replace exact-record inline details with a fixed bottom-sheet trigger and accessible close/focus behavior.
- [x] Add and wire a membership-backed organization switcher in the sidebar.
- [x] Preserve profile/application/environment context behavior and clean URL navigation.
- [x] Suppress the redundant default collection-toolbar count while preserving filtered/truncated live status text.
- [x] Run syntax checks and report changed markup/functions plus validation evidence to the coordinator.

## Validation

Completed:

- `node --check dashboard/app.js` — passed.
- `python3 -m unittest dashboard.test_serve` — 23 tests passed.
- Canonical `sh scripts/local-dashboard.sh up` completed successfully; dashboard `18083` and control plane `18082` are healthy.
- Live browser verified session-pending/boot-card state, authenticated refresh settlement, clean History API paths with no query/hash residue, exact-record open/close/Escape/backdrop/focus behavior, unchanged row/panel geometry, no record-content top border, default-toolbar count suppression, and filtered-status retention.
- Live browser verified the organization selector is rendered from membership data, shows `Local Hyfens`, hides the organization ID in the sidebar card, and is correctly disabled for the single-membership local seed.

## Next Action

No further action; the coordinator reviewed the worker changes and completed the consolidated validation pass.

## Blockers

None currently.

## Outcome

Session refresh no longer flashes the login form; a neutral boot surface is shown until authentication settles. The sidebar organization card is now a membership-backed switcher, exact records open in an accessible bottom sheet without row shift, and the default collection toolbar no longer duplicates the panel count.

## References

- User screenshots showing exact-record row expansion, sidebar organization card, and refresh login flicker.
- User-provided dashboard design transcript emphasizing modals for complex context, toasts for transient feedback, and explicit navigation context.
- `dashboard/app.js`
- `dashboard/index.html`
- `docs/adr/0006-tenancy-model.md`

## History

- 2026-09-01: Reserved task 222 after the live repro confirmed inline record growth and source inspection confirmed a static organization card plus initially visible login markup during deferred session restore.
- 2026-09-01: Implemented boot gating, organization membership switching, accessible exact-record sheets, and clean route preservation; focused tests and live browser checks passed.
- 2026-09-01: Added the neutral boot card and follow-up toolbar/sheet refinements from the latest live screenshot; rebuilt and verified the canonical Docker stack.
