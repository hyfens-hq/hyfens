# Task 239 — Docker Auth Runtime Routing

Status: [x] Completed

## Goal

Make the Docker-served CLI authorization page send authentication requests to the configured control-plane API instead of the dashboard's static HTTP port, eliminating the local OAuth callback page's HTTP 405 failure.

## Scope and Non-goals

Scope:

- Resolve the injected dashboard runtime API base in the shared browser auth helper.
- Add a focused regression test for auth request URL selection.
- Rebuild and smoke-test the local Docker dashboard/auth flow.

Non-goals:

- No auth protocol or control-plane API changes.
- No dashboard redesign or unrelated routing changes.
- No changes to the protected `backend` or `frontend` repositories.

## Owner

Coordinator

## Dependencies

- `dashboard/runtime-config.js` injection from the local dashboard container.
- Control-plane API listening on the configured local API address.

## Assumptions

- An explicitly configured `<meta name="hyfens-api-base">` remains the highest-priority browser override.
- The container-injected `window.__HYFENS_RUNTIME_CONFIG__.apiBase` is the correct API base when the meta tag is empty.
- Same-origin fallback remains necessary for static/development deployments without runtime configuration.

## Work Items

- [x] Inspect the authorization page, runtime configuration, static dashboard server, and control-plane routes.
- [x] Add a regression test that fails when auth requests target the dashboard origin.
- [x] Update the auth helper to honor the injected runtime API base.
- [x] Rebuild the local Docker dashboard and validate the browser-auth request seam.
- [x] Review the scoped diff and record validation evidence.

## Validation

Completed:

- Regression was red before the implementation (`:18083/auth/login`) and green after it.
- `node --test dashboard/test_auth_flow.js` — 3 passed.
- `node --check dashboard/auth-flow.js` — passed.
- `python3 -m unittest dashboard.test_serve` — 31 passed.
- `sh -n scripts/local-dashboard.sh` and `git diff --check` — passed.
- `sh scripts/local-dashboard.sh demo` — rebuilt both images, recreated the stack, reseeded the local demo account, and completed successfully.
- `sh scripts/local-dashboard.sh status` — control plane, dashboard, PostgreSQL, and object store healthy.
- Served `runtime-config.js` points to `http://127.0.0.1:18082/`.
- Served `auth-flow.js` executed against a browser-like harness and targeted `http://127.0.0.1:18082/auth/login`.
- Disposable control-plane authorization request — HTTP 200.

## Next Action

Use the rebuilt local dashboard at `http://127.0.0.1:18083/`; the CLI authorization page now keeps its static page on `:18083` and sends auth API calls to the control plane on `:18082`.

## Blockers

None.

## Outcome

The shared browser auth helper now honors `window.__HYFENS_RUNTIME_CONFIG__.apiBase` after an explicit meta-tag override. The local Docker OAuth page no longer posts to the static dashboard server, removing the HTTP 405 failure.

## References

- `dashboard/auth-flow.js`
- `dashboard/cli/authorize/index.html`
- `dashboard/device/index.html`
- `dashboard/docker-entrypoint.sh`
- `dashboard/nginx.conf`
- `dashboard/test_auth_flow.js`

## History

- 2026-09-03 — Reserved task 239 after confirming Docker auth POSTs were being sent to the static dashboard origin and rejected with HTTP 405.
- 2026-09-03 — Added a browser-network regression, fixed runtime API-base selection, rebuilt the local Docker stack, and verified the deployed auth helper plus dashboard test suite.
