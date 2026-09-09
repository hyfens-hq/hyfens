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
  acceptance; the live environment has no supported non-root disposable
  identity bootstrap available to the deployment SSH account.
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
- The credential transport boundary was corrected for the TLS-terminating
  private proxy path in commit `f5df75e`; live `/auth/me` now reaches normal
  bearer authentication (`401 UNAUTHORIZED`) and an invalid login reaches
  credential validation (`401 INVALID_CREDENTIALS`) instead of returning
  `INSECURE_TRANSPORT`.
- The focused control-plane ingress test and package analysis pass.

## Next Action

Complete the bounded authenticated browser acceptance with disposable customer
and authorized platform sessions. The canonical platform hostname is
`platform.hyfens.com`; no secondary managed platform hostname is supported.
The managed instance must first provide a supported disposable bootstrap: public
registration is disabled, and the documented platform-user helper is root-only
and seeds the existing scope rather than creating a disposable organization.

## Blockers

- Public discovery reports `public_registration: null`, so the supported public
  registration endpoint cannot create a customer acceptance identity.
- The documented live platform bootstrap helper is root-only; `sudo -n` from
  the configured `hyfen` deployment account reports that a password is
  required. Direct Docker access is also denied for that account.
- No supported non-root API or helper for creating a disposable organization,
  customer identity, and platform identity was available to this acceptance
  run. No real or unknown credentials were used.

## Outcome

Customer Workspace and the canonical Platform Console deployment are live and
API-safe. The TLS-terminated authentication transport defect is fixed and
deployed, but full live-dashboard acceptance remains externally gated by the
missing disposable live identity bootstrap.

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
- 2026-09-04: Diagnosed the TLS-termination transport failure, deployed the
  trusted-private-proxy fix, pushed `f5df75e`, and confirmed normal protected
  API responses. Authentication remains blocked pending supported disposable
  identity bootstrap authority.
