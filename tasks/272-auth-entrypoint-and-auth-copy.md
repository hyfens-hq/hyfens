# Task 272 - Auth entrypoint and auth copy cleanup

Status: [x] Completed

## Goal

Send public sign-in traffic directly to the managed app and make the app auth
surface concise, understandable, and focused on signing in or creating an
account.

## Scope and Non-goals

Scope:

- remove the redundant public sign-in handoff page from the Cloud web app by
  redirecting `/login` to the managed app;
- point public-site sign-in links directly to the managed app;
- simplify the static dashboard auth page by removing unexplained session
  labels, technical status copy, duplicate form labels, and non-action auth
  marketing copy; and
- preserve the existing sign-in, registration, invitation, discovery, session,
  and post-authentication behavior.

Non-goals:

- changing authentication APIs, token/session storage, or authorization
  behavior;
- changing the dashboard after-auth navigation or product copy;
- changing legal, consent, account-deletion, or password-recovery policy; and
- deploying or changing live DNS/configuration.

## Owner

Codex, with maintainer review before deployment.

## Dependencies

- existing `dashboard/` auth flow and control-plane auth routes;
- sibling `hyfens-cloud-web/apps/web` Next app and its `APP_URL` configuration.

## Assumptions

- `https://app.hyfens.com` is the canonical managed sign-in and account
  creation surface;
- `/login` should remain a compatibility URL that redirects rather than render
  a second sign-in explanation; and
- technical discovery state remains useful to the app internally even when it
  is no longer shown as auth-page copy.

## Work Items

- [x] Rebase the implementation onto a fresh branch from `main` without
  importing unrelated shared-branch history.
- [x] Add the required concise `[Unreleased]` changelog entry for the
  user-visible dashboard change.
- [x] Replace the public `/login` page with a direct redirect and update its
  public-site callers.
- [x] Remove redundant and unclear auth-page copy while retaining actionable
  form labels, help, errors, and state transitions.
- [x] Update auth layout styles for the focused single-panel composition and
  preserve responsive/focus behavior.
- [x] Update focused contract tests and run scoped validation for both web
  surfaces.
- [x] Complete self-review and record the final outcome.

## Validation

Completed:

- `python3 -m unittest dashboard.test_serve` — 33 tests passed;
- `node --test dashboard/test_auth_flow.js` — 4 tests passed;
- `node --check dashboard/app.js` — passed;
- `npm run typecheck:web`, `npm run lint:web`, and `npm run build:web` in
  `hyfens-cloud-web` — all passed;
- source audits found no stale public `/login` callers or removed auth-page
  copy/selectors;
- `CHANGELOG.md` contains the required `[Unreleased]` entry;
- local browser review covered the sign-in and create-account states on the
  fresh `main`-based dashboard branch;
- local `GET /login` returned `307` with `Location: https://app.hyfens.com`;
- `git diff --check` passed in both repositories.

## Next Action

Review and merge the linked PRs, then deploy and verify the versioned
dashboard assets in the managed app.

## Blockers

None.

## Outcome

The public Cloud-web sign-in route now redirects directly to the canonical
managed app, and public sign-in callers use that app URL. The dashboard auth
surface is a centered single panel with concise sign-in, registration, and
invitation copy; the unexplained session labels, discovery callout, and
non-action auth rail are removed without changing auth requests, invitation
handling, or stored-session behavior.

## References

- `dashboard/index.html`
- `dashboard/styles.css`
- `dashboard/app.js`
- sibling `hyfens-cloud-web/apps/web/src/app/login/page.tsx`
- sibling `hyfens-cloud-web/apps/web/src/components/site-header.tsx`
- sibling `hyfens-cloud-web/apps/web/src/components/site-footer.tsx`

## History

- 2026-09-10 - Reserved as the linked dashboard and Cloud-web auth cleanup
  package after auditing the live `/login` handoff and `app.hyfens.com` auth
  surface.
- 2026-09-10 - Implemented the redirect, direct public-site links, focused
  auth layout, concise auth copy, and contract-test updates.
- 2026-09-10 - Rebased the implementation onto `origin/main` while preserving
  the newer dashboard invitation flow and excluding unrelated shared-branch
  changes.
- 2026-09-10 - Revalidated the main-based implementation, completed the
  visual/content self-review, and prepared the atomic repository commit.
- 2026-09-10 - Corrected reviewed auth error mappings so expired sessions,
  invalid credentials, and unavailable control-plane routes remain distinct.
