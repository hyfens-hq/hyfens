# Hyfens Live Product Launch Candidate Review

Status: FINITE MILESTONE STOPPED AT LIVE EXTERNAL GATES

Acceptance timestamp: 2026-08-31T05:34:19Z

Final disposition: `HYFENS LIVE PRODUCT — BLOCKED BY EXTERNAL ENVIRONMENT`

## Scope

This is the bounded launch-candidate pass for the frozen developer-platform
contract. Task creation remained off. No Task 210 or other numbered task was
created. The pass covered local source integration, disposable Docker
validation, read-only live probes, and preparation for live web, CLI, and
physical-device acceptance.

The launch candidate is not accepted as live because the required public web
and discovery surfaces are not deployed and the available remote deployment
path is not authenticated.

## Frozen contract

- Public executable: `hyfens`.
- `tool` remains one deprecated compatibility shim.
- Managed API base: `https://api.hyfens.com/p2/`.
- Dashboard: `https://app.hyfens.com`.
- Marketing: `https://hyfens.com`.
- Profiles bind endpoint/API base, identity, and scope metadata; credentials
  are host-bound.
- Human auth uses PKCE/device-code contracts, short-lived access JWTs, and
  revocable server sessions.
- Auth and Patch Format signing trust remain separate.
- Exact application identity checks remain enabled.
- SSH is an infrastructure mechanism, not a developer workflow.

The frozen contract is recorded in
[`HYFENS_DEVELOPER_PLATFORM_CONTRACT.md`](../../HYFENS_DEVELOPER_PLATFORM_CONTRACT.md).

## Coordinated workstreams

### Landing / brand web

The landing source was reviewed at `web/landing/**`. No source change was
justified. Desktop, tablet, and 390px mobile rendering, theme switching,
navigation, anchors, JavaScript syntax, asset loading, accessibility
structure, and source-level reduced-motion guards passed in the worker review.
Mobbin was used for composition inspiration only; no proprietary design was
copied.

Live deployment is not complete.

### Dashboard / browser auth

The dashboard workstream remained within `dashboard/**` and delivered:

- an authoritative Artifacts surface from the existing overview projection;
- correct nested rollout revision rendering;
- the mobile theme-label selector fix;
- removal of a generic token fallback in browser response handling;
- strict loopback-IP validation;
- focused regression assertions.

The dashboard does not invent API-key mutations, telemetry, or runtime
success. Its read-only boundary remains intentional.

### Public CLI / distribution

The CLI review found the canonical `hyfens` runner, deprecated `tool` shim,
managed `/p2/` default, profile host binding, status/doctor/init commands,
and existing auth/discovery implementation. No CLI source change was
justified.

The repository installer is a source-checkout installer requiring Dart. It is
not a published package, signed downloadable artifact, or network installer.
`bash -n scripts/install-hyfens.sh` and its help path passed.

### Managed / self-hosted runtime

The runtime workstream preserved the existing auth, R2, and legacy credential
boundaries and aligned product/API dispatch with a configured `/p2/` base.
The affected control-plane and deployment seams were directly reviewed.

### Physical devices

Device preparation found one Android device visible to ADB Wi-Fi:
`Redmi_Note_10_Lite`, API 36, ARM64. No application was installed or
modified. Final Android/iOS activation was not run because the managed live
path is not stable and the accepted patch bytes are not locally available for
an independent device run. No physical-device pass is claimed.

## Local validation

Only affected or directly supporting scopes were validated:

- Control plane: `dart analyze lib test` passed in
  `packages/control_plane`; focused config, human-auth, extension, and
  overview tests passed (20 tests).
- Flutter integration: `dart analyze lib test` and
  `test/control_plane_delivery_service_test.dart` passed (1 test).
- Dashboard: `python3 -m unittest dashboard.test_serve` passed (10 tests),
  `node --check` passed for both JavaScript files, and Python compilation
  passed.
- Deployment: all three P2 Compose configurations passed `docker compose
  config --quiet` with disposable non-secret values.
- Disposable Docker: the P2 image built and the isolated stack started with
  healthy PostgreSQL, object store, and control plane. Root `/healthz` and
  `/readyz` returned HTTP 200; `/p2/.well-known/hyfens` returned HTTP 200
  with product `hyfens`, API version `v1`, and the advertised auth methods.
  The dedicated containers and volumes were removed after the check.
- CLI: the worker reported Dart analysis passed. A process-level focused run
  was interrupted after 29 passing tests because child processes hung under
  concurrent build activity; no CLI source change was made and no incomplete
  result is treated as a pass.

## Read-only live evidence

At the acceptance timestamp:

| Surface | Evidence | Classification |
| --- | --- | --- |
| `https://hyfens.com/` | HTTP 200, but the body is Hostinger's `Default page` placeholder | External gate |
| `https://app.hyfens.com/` | DNS resolution fails; no `app` record is present in the inspected Hostinger DNS records | External gate |
| `https://api.hyfens.com/p2/healthz` | HTTP 200 | Pass |
| `https://api.hyfens.com/p2/readyz` | HTTP 200 | Pass |
| `https://api.hyfens.com/p2/.well-known/hyfens` | HTTP 404 JSON `NOT_FOUND` from the deployed API | External/deployment gate |

The local source and isolated Docker stack serve the discovery route correctly;
therefore the public 404 is not evidence of a source-level discovery defect.
It is evidence that the deployed remote image/configuration/routing is not at
the locally validated state. No blind remote patch was applied.

The Hetzner console was observed at a login prompt during this pass. No
authenticated deployment session was established, no server configuration was
changed, and no SSH key or secret was installed.

## Live acceptance matrix

| Gate | Result |
| --- | --- |
| `hyfens.com` HTTPS | PASS for transport; FAIL for required landing content |
| Landing responsive | Local PASS; live NOT RUN because the live page is a placeholder |
| `app.hyfens.com` HTTPS | NOT RUN — DNS unresolved |
| `api.hyfens.com` health | PASS |
| `api.hyfens.com` readiness | PASS |
| Browser login | NOT RUN — dashboard domain/discovery unavailable |
| CLI authorization | NOT RUN — live approval surface unavailable |
| Device authorization | NOT RUN — live approval surface unavailable |
| Dashboard core surfaces | Local source PASS; live NOT RUN |
| Public `hyfens` install artifact | NOT PASS — only source installer exists |
| Managed CLI lifecycle | NOT RUN — live discovery/auth surface unavailable |
| Self-hosted CLI lifecycle | Local contract reviewed; live NOT RUN |
| CI/service auth | Existing contract documented; live key issuance not proven |
| Android physical activation | NOT RUN |
| iOS physical activation | NOT RUN |

## Security and architecture review

Local evidence continues to support the frozen invariants:

- PKCE S256/state/redirect/code handling and device-code expiry/single-use
  behavior are covered by focused control-plane/CLI tests.
- JWT issuer/audience/algorithm/session validation and authoritative tenant
  authorization remain in the existing control-plane implementation.
- Auth JWT signing and Patch Format signing remain separate.
- Dashboard browser code does not persist tokens in `localStorage` or
  `sessionStorage`, does not accept token query parameters, and now rejects
  ambiguous loopback hosts and generic token fallbacks.
- Profiles and project configuration contain metadata, not bearer/session
  secrets.
- Exact application, release, patch, sequence, digest, and signature checks
  remain enabled.
- Docker validation used disposable values and a dedicated project; no
  production credential or data was used.

## Durable Hetzner deployment path and P2 refresh — 2026-08-31

- The existing `hyfens-server` SSH profile reaches Hetzner server `131552315`
  (`188.245.62.225`) as the persistent `hyfen` deployment identity. No new
  public key was appended and the existing SSH, password, and firewall policy
  was not changed.
- A root-owned `/usr/local/sbin/hyfens-deploy` wrapper is installed with mode
  `755`. `hyfen` has a matching passwordless sudo rule for that wrapper only;
  the wrapper rejects arguments, reads the protected deployment environment,
  stages only the P2 source directories, validates Compose, and runs the
  existing P2 Compose deployment. The protected environment remains outside
  the repository and unreadable to `hyfen`.
- The reviewed P2 source was staged through the persistent SSH profile and the
  wrapper rebuilt/restarted the control plane. No PostgreSQL volume or R2
  configuration was replaced.
- Post-deployment HTTPS checks passed: `/p2/healthz` returned `200`,
  `/p2/readyz` returned `200`, and `/p2/.well-known/hyfens` returned `200`
  with the expected Hyfens v1 discovery contract and no secret data.
- Hostinger files, DNS records, and the dashboard target were not changed in
  this access-path setup. The remaining public web gates below still apply.

## CMS/web implementation and deployment continuation — 2026-08-31

The website/CMS implementation is a single Next.js application deployed on
Hetzner. It serves the public marketing routes by host, the authenticated
platform dashboard on the app host, and a separate `/cms` editorial workspace
inside the same application/runtime. This keeps the CMS distinct in
navigation and authorization without adding another server or identity store.

The reviewed image was deployed through the fixed-purpose
`hyfens-platform-deploy` wrapper. The server-local target is healthy:

| Probe | Result |
| --- | --- |
| Node runtime `127.0.0.1:18084/` | HTTP 200 |
| Nginx host `app.hyfens.com` `/` | HTTP 200 |
| Nginx host `app.hyfens.com` `/login` | HTTP 200 |
| Nginx host `app.hyfens.com` `/cms` | HTTP 200 |
| Nginx host `app.hyfens.com` `/blog` | HTTP 200 |
| Nginx host `app.hyfens.com` `/news` | HTTP 200 |
| `https://api.hyfens.com/p2/healthz` | HTTP 200 |
| `https://api.hyfens.com/p2/readyz` | HTTP 200 |
| `https://api.hyfens.com/p2/.well-known/hyfens` | HTTP 200 |

The existing demo scope now has the requested seeded identities. Only
non-secret identifiers and profiles are recorded here; the bootstrap command
confirmed that passwords are not persisted:

| Identity | Identifier | Profile |
| --- | --- | --- |
| Existing-scope owner | `usr_7531beef241793263ba94518e0aaa8ec` | `super-admin` |
| Existing-scope editorial admin | `usr_21b15ca10bf9738033ad42f25fd5c453` | `content-admin` |

The scope remains organization
`org70760ae2ff001f83f59af0f1b43cb67e5df1`, application
`app6c9b6afc1fe6e72e6b5945a2708b218c7c0e`, and environment
`env0179b608edaa997d4ebe85887ae029542568`.

The latest public read-only probes show `hyfens.com` serving the existing
Hostinger-hosted Hyfens page, while `app.hyfens.com` remains DNS-unresolved.
No Hostinger upload was performed because no authenticated Hostinger provider
session was available, and the new Next/CMS runtime is intended for Hetzner
rather than a static `public_html` upload. The live `/p2/content` endpoint
currently returns an empty publication, so no live CMS content is claimed
until the protected publication-organization configuration and editorial
entries are established through the supported path.

### Continuation matrix

| Gate | Result |
| --- | --- |
| One Next/Node web deployment shape | PASS |
| Hetzner platform target deployment | PASS |
| Server-local app/CMS route probes | PASS |
| Existing P2 health/readiness/discovery | PASS |
| Existing scope preserved | PASS |
| Super-admin and content-admin bootstrap | PASS |
| Hostinger landing upload | NOT PERFORMED — landing is served by the Hetzner Node edge; `default.php` remains untouched |
| `app.hyfens.com` DNS/TLS/public routing | PASS — public DNS and HTTPS route to Hetzner |
| Public CMS publication | EXTERNAL/CONFIGURATION GATE — endpoint is empty |
| Unit tests | NOT RUN — explicitly excluded by maintainer |

No P2 database, R2 object, credential, or signing configuration was changed
by the web deployment. The persistent `hyfens-server` identity and bounded
deployment wrapper remain the only deployment access path; no new SSH key was
added.

## Public Hetzner edge activation — 2026-08-31

The existing Let’s Encrypt certificate was expanded successfully and now
covers `hyfens.com`, `www.hyfens.com`, `app.hyfens.com`, and `api.hyfens.com`.
The fixed-purpose public-edge wrapper then replaced only the public Nginx site
configuration, preserving the P2 API proxy and rolling back on failed health
checks.

Direct SNI validation against Hetzner `188.245.62.225` passed for the new
certificate. `app.hyfens.com` now resolves to Hetzner and serves `/`, `/login`,
and `/cms` over HTTPS with HTTP 200. The API continues to return HTTP 200 for
health, readiness, and discovery.

The authoritative DNS check still reports no A/AAAA answer for the apex
`hyfens.com`, although the Hostinger UI showed an apex A row. Consequently
`www.hyfens.com` (CNAME to the apex) and the public marketing hostname cannot
yet be accepted. The apex record needs to be saved/published as
`A @ 188.245.62.225`; the existing `www` CNAME, `api` A/AAAA, mail, FTP, and
verification records should remain unchanged.

The public edge package is now installed on Hetzner and no new SSH key was
added. The remaining apex DNS publication is a provider-side gate, not a
source or API defect.

## DNS and public edge follow-up — 2026-08-31

The Hostinger DNS zone now contains the intended records for the Hetzner
edge: `A @ -> 188.245.62.225`, `A app -> 188.245.62.225`, `CNAME www ->
hyfens.com`, and the existing `A/AAAA api` records. The FTP, mail, BIMI, and
verification records were left unchanged.

Authoritative checks through `1.1.1.1` and `8.8.8.8` return
`188.245.62.225` for both `hyfens.com` and `app.hyfens.com`; `www.hyfens.com`
returns the expected apex CNAME. Direct IPv4 HTTPS validation returns HTTP
200 for `hyfens.com`, HTTP 200 for `app.hyfens.com`, and HTTP 301 from
`www.hyfens.com` to the apex. The API health, readiness, and discovery routes
remain HTTP 200.

One immediate default-resolver request on the operator machine briefly
returned a DNS resolution error despite the authoritative/public results;
the resolver then returned the correct A record and `curl -4` returned HTTP
200. This is local negative-cache/propagation behavior, not a DNS-record
mismatch. No further DNS record changes are required.

The marketing landing and dashboard are therefore both served by the
Hetzner Node deployment. No files were uploaded to Hostinger `public_html/`,
and Hostinger `default.php` was not modified.

## Brand asset deployment follow-up — 2026-08-31

The deployed web build now uses the exact source mark from
`web/landing/assets/brand-mark.svg` across the marketing, platform, and CMS
surfaces. The local copy is
`web/site/public/brand-mark.svg` with SHA-256
`d56c8511dafaaa32082c2c886f10defb36d2f67d2835885d143bcf5c07ae261b`.

Shared navigation, authentication, platform navigation, article actions, and
CMS actions use the local outline icon set under `web/site/public/icons/`.
The deployed `brand-mark.svg` and `icons/arrow-right.svg` were fetched over
HTTPS and matched their local SHA-256 values exactly.

The bounded `hyfens-platform-deploy` command rebuilt and recreated the web
container, validated Nginx, and reloaded the proxy. Post-deployment probes
returned HTTP 200 for `hyfens.com`, `app.hyfens.com`, `/login`, `/cms`, the
logo/icon assets, and the P2 health, readiness, and discovery routes. The
restricted deployment identity does not have direct Docker-socket read access;
container replacement was confirmed by the fixed wrapper result and the live
route/asset probes.

Affected local validation also passed: TypeScript, ESLint, and the production
Next.js build. No unit tests were added or run.

## Findings by classification

### BLOCKER

No source-level product blocker was demonstrated by the bounded local checks.

### EXTERNAL GATE

- Hostinger `public_html/` remains an intentionally unused alternative
  hosting path; the live landing is served from the Hetzner Node edge.
- The deployed discovery route now passes, but live browser PKCE/device
  approval and dashboard routing remain unproven.
- Live browser PKCE/device approval, live dashboard, managed/self-hosted
  onboarding, CI key issuance, and live domain routing remain unproven.
- Physical-device activation remains gated on a stable live path and matching
  independently verifiable release/patch artifacts. The local candidate APK
  digest is `96e3aa821d6348ba861c13bec9be557327cc51c7bcb3776c17457099069eeb47`,
  while the prior readiness evidence records a different digest for the same
  release; the accepted patch bytes are not present locally. No device claim
  was made.

### BACKLOG

- Publish signed, checksummed cross-platform CLI artifacts and document a
  release channel. Do not invent a download URL before hosting exists.
- Add native OS credential-store adapters and reduce persisted access-token
  material in the protected fallback.
- Add browser-safe API-key inventory/mutation UI only after authoritative
  backend endpoints exist.
- Add bounded CI/CD image deployment automation when an approved release
  pipeline is available.
- Package a tested self-hosted TLS/deployment shape without claiming HA or
  production readiness.
- Optional favicon and runtime reduced-motion emulation evidence.

### ACCEPTED LIMITATION

- P2 remains a local/single-node validation shape, not production HA.
- The dashboard is read-only wherever authoritative safe mutation APIs are
  absent.
- Supported patching remains bounded by the existing Flutter/Dart/runtime and
  exact-application constraints.
- `tool` remains a temporary compatibility shim.

### NO ACTION

- No Task 210 or any numbered follow-up task is warranted.
- No AWS, SSH-based developer authentication, manual database mutation, or
  recursive next-gap audit was started.
- No new test matrix was added solely to increase coverage.

## Final recommendation

`HYFENS LIVE PRODUCT — PASS WITH EXTERNAL GATES`

The brand-correct landing and dashboard are deployed on the Hetzner Node edge,
the apex/app DNS cutover is published, and the API health/readiness/discovery
routes remain green. Remaining browser PKCE/device approval, CMS publication,
CLI distribution, self-hosted onboarding, and physical-device evidence remain
external gates; no unsupported completion claim is made for them.

## OSS / Cloud source boundary correction — 2026-08-31

The source ownership is now explicit and split into two local repositories.
The public Hyfens repository retains the reusable runtime, CLI, self-hosted
control plane, and canonical dependency-free dashboard under `dashboard/`.
The marketing website, CMS, and Cloud-only web deployment inputs were moved to
the sibling private checkout `../hyfens-cloud-web/`:

```text
hyfens.com      → private Cloud marketing/CMS web package
app.hyfens.com  → public OSS dashboard package
api.hyfens.com  → managed control plane
```

The public repository no longer contains `web/site/`, `web/landing/`, or the
private Cloud web deployment package. The private Cloud web package no longer
contains a second dashboard implementation. Its edge configuration routes the
two web hosts separately while preserving the existing API route and data
stores. See `docs/OSS_CLOUD_SOURCE_BOUNDARY.md` for the frozen contract.
