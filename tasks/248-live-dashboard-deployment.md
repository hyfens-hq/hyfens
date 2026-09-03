# Live dashboard deployment and browser acceptance

Status: [-] Blocked

## Goal

Deploy the existing Customer Workspace and Platform Console boundaries to the
managed dashboard hosts, verify the live edge/API behavior, and record any
external acceptance gates without changing dashboard product scope.

## Scope and Non-goals

Scope is the managed static dashboard deployment, public edge routing, HTTPS
and API-origin checks, bounded browser acceptance, and current documentation
accuracy. This does not include dashboard feature work, backend/frontend
repository changes, DNS-provider administration, release tags, or a new
release.

## Owner

Release/deployment coordinator.

## Dependencies

- Existing `hyfens-server` SSH deployment identity and root-approved deploy
  helpers.
- DNS and certificate administration for `hyfens.com`.
- Managed control-plane origin allow-list configuration.
- Browser session credentials for authenticated Customer Workspace and
  Platform Console acceptance.

## Assumptions

- The public repository `main` dashboard bundle is the intended current
  dashboard source.
- Customer and Platform shells remain one static artifact with host-based
  product boundaries.
- No protected `backend` or `frontend` repository is changed.

## Work Items

- [x] Inspect the public dashboard bundle and established host deployment
  helpers.
- [x] Deploy the current dashboard files to the protected host target.
- [x] Activate `app.hyfens.com` through the existing public edge mechanism.
- [x] Verify app HTTPS, assets, API health/readiness/discovery, and available
  unauthenticated browser behavior.
- [-] Activate `admin.hyfens.com` after certificate and API-origin gates are
  supplied; its DNS A record now resolves to the managed edge.
- [-] Complete authenticated Customer Workspace and Platform Console browser
  acceptance; no authenticated disposable browser session is available and the
  Platform Console hostname is not active.
- [x] Re-run the live API regression after the Customer Workspace edge change.

## Validation

Completed checks include:

- `https://api.hyfens.com/p2/healthz`, `readyz`, and discovery: `200`.
- `https://app.hyfens.com/`: valid certificate and `200`.
- Customer app static assets, SVG icon MIME types, and runtime config: pass.
- Customer app CORS preflight: pass.
- Browser console: no errors/warnings; desktop and 390px mobile screenshots
  captured; no horizontal overflow.
- `https://admin.hyfens.com`: DNS resolves to `188.245.62.225`, but the
  current edge certificate excludes the hostname and the route is not yet
  configured for the Platform Console.
- Platform-origin CORS preflight: `403 ORIGIN_NOT_ALLOWED`.

## Next Action

Add `admin.hyfens.com` to the managed edge certificate and the control-plane
browser-origin allow-list, configure the separate static Platform Console edge
route, then repeat the bounded authenticated browser acceptance.

## Blockers

- The current Let's Encrypt certificate covers `api.hyfens.com`,
  `app.hyfens.com`, `hyfens.com`, and `www.hyfens.com`, but not
  `admin.hyfens.com`.
- The control plane returns `ORIGIN_NOT_ALLOWED` for
  `Origin: https://admin.hyfens.com`.
- No authenticated disposable browser session is available in the browser
  connector.

## Outcome

Customer Workspace deployment is live and API-safe. Full live-dashboard
acceptance is blocked by the missing Platform Console certificate/edge/CORS
configuration and by unavailable authenticated browser test credentials.

## References

- `docs/architecture/dashboard-separation.md`
- `docs/product/customer-workspace.md`
- `docs/product/platform-console.md`
- `dashboard/`
- `/usr/local/sbin/hyfens-dashboard-deploy` on `hyfens-server`
- `/usr/local/sbin/hyfens-public-edge-deploy` on `hyfens-server`

## History

- 2026-09-03: Created for the bounded live-dashboard deployment and browser
  acceptance work.
- 2026-09-03: Deployed the Customer Workspace edge and recorded the Platform
  Console deployment prerequisites as external blockers.
