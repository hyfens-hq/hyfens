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
- [x] Activate the canonical `platform.hyfens.com` Platform Console host after
  supplying certificate and API-origin gates; its DNS A record resolves to the
  managed edge.
- [-] Complete authenticated Customer Workspace and Platform Console browser
  acceptance; no authenticated disposable browser session is available.
- [x] Re-run the live API regression after the Customer Workspace edge change.

## Validation

Completed checks include:

- `https://api.hyfens.com/p2/healthz`, `readyz`, and discovery: `200`.
- `https://app.hyfens.com/`: valid certificate and `200`.
- Customer app static assets, SVG icon MIME types, and runtime config: pass.
- Customer app CORS preflight: pass.
- Browser console: no errors/warnings; desktop and 390px mobile screenshots
  captured; no horizontal overflow.
- `https://platform.hyfens.com`: DNS resolves to `188.245.62.225`, the edge
  route and certificate are active, and the dashboard returns `200`.
- Platform-origin CORS preflight: `204` with
  `access-control-allow-origin: https://platform.hyfens.com`.
- API health, readiness, discovery, HTTPS redirects, static assets, and
  customer-origin CORS regression remain passing.

## Next Action

Complete the bounded authenticated browser acceptance with disposable customer
and authorized platform sessions. The canonical platform hostname is
`platform.hyfens.com`; no secondary managed platform hostname is supported.

## Blockers

- No authenticated disposable browser session is available in the browser
  connector, so authenticated customer/platform flows and cross-audience
  denial remain unproven.

## Outcome

Customer Workspace and the canonical Platform Console deployment are live and
API-safe. Full live-dashboard acceptance remains externally gated by the lack
of authenticated disposable browser test sessions.

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
- 2026-09-04: Activated `platform.hyfens.com`; certificate, edge routing, API
  CORS, health/readiness/discovery, and static asset checks passed. Reconciled
  the remaining authenticated-browser and legacy-alias gates.
