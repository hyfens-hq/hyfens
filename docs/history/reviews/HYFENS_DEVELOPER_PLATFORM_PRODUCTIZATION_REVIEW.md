# Hyfens Developer Platform Productization Review

Status: FINITE MILESTONE CLOSED

Date: 2026-08-31

Final disposition: `HYFENS DEVELOPER PLATFORM — PASS WITH EXTERNAL GATES`

## Scope

This review covers the bounded productization milestone defined by the
[contract freeze](../../HYFENS_DEVELOPER_PLATFORM_CONTRACT.md). Task creation was
disabled for this milestone; no Task 210 or follow-up microtasks were created.

The implementation makes the intended workflow coherent at the local and
local-Docker level:

```text
hyfens login → profile → hyfens init → release/patch/deploy
```

The existing Hetzner/R2 and Auth v1 evidence remains valid historical evidence.
This milestone did not make unapproved live-domain or production claims.

## Implementation status

- `hyfens` is the canonical executable. The existing `tool` entry point is a
  single delegated compatibility shim that reports `tool is deprecated; use
  hyfens`.
- Profiles store endpoint and scope metadata separately from credentials.
  Credential lookup is bound to the normalized host and API base path, and
  remote plain HTTP is rejected except for explicit loopback development.
- Managed login defaults to `https://api.hyfens.com/p2/`; self-hosted login
  accepts an explicit HTTPS host and persists it as a profile.
- Auth v1 supports the existing password/session compatibility path plus
  browser Authorization Code + PKCE and device-authorization contracts where
  the discovered control plane advertises them. Access JWTs remain 15 minutes;
  server sessions remain revocable with the proven 30-day lifetime.
- The control plane exposes versioned `/.well-known/hyfens` discovery, exact
  configured web-origin checks, authorization approval/token endpoints, and
  device-code endpoints. Auth JWT trust remains separate from patch signing.
- Self-hosted first-owner bootstrap is server-local/stdin-protected and has a
  durable per-scope consumption claim: same-owner retry is idempotent and a
  different owner is rejected.
- `hyfens init` writes safe `hyfens.yaml` metadata and retains exact
  application-identity enforcement. `hyfens patch android|ios` selects the
  requested platform, and `hyfens deploy` can infer one unambiguous local
  release and patch.
- The dashboard has responsive shell, authentication, organization/application
  context, overview, environments, releases, patches, deployments, audit, and
  unavailable-state handling. It uses the existing authoritative overview
  authorization path and does not invent telemetry or unsupported mutations.
- The landing page explains bounded signed Flutter patching, verification,
  deployment, rollback, CLI usage, and the managed/self-hosted distinction
  without unsupported store, zero-risk, arbitrary-Dart, or availability claims.
- README, getting-started, CLI, self-hosted, deployment, and landing examples
  use the public `hyfens` command. Legacy `tool` references are retained only
  where they are compatibility or historical evidence.

## Coordinated workstreams and review

Six bounded workstreams were assigned with disjoint ownership: public CLI,
Auth/session platform, dashboard, landing/brand web, self-hosted/OSS contract,
and docs/distribution/integration. Each result was inspected against the
frozen contract.

The integrated review found and corrected four concrete defects:

1. dashboard overview requests using Auth v1 JWTs were not accepted by the
   overview authorization seam;
2. documented argument-free deploy could fail when one local release/patch was
   unambiguous;
3. platform selectors on `hyfens patch` could be ignored;
4. an explicit automation token could be shadowed by a stored session.

The corrections were covered by focused regression checks. No unresolved
release-blocking defect was evidenced in the final coordinator review.

## Critical workflows reviewed

- canonical/deprecated executable behavior, help, version, and diagnostics;
- managed and self-hosted profile resolution and host isolation;
- PKCE state/S256/redirect/code handling and device-code contract handling;
- auth status/logout, session reuse/refresh, and explicit-token precedence;
- safe project discovery, `hyfens.yaml`, and exact application diagnostics;
- platform-aware release/patch selection and bounded deploy inference;
- discovery, CORS, browser approval, device approval, and dashboard overview
  authorization;
- dashboard route allowlisting, query-secret rejection, and redacted logging;
- responsive landing/dashboard rendering, theme behavior, focus states, and
  reduced-motion behavior;
- disposable Docker Compose build, startup, health/readiness, discovery, and
  cleanup.

## Architecture and security invariants

The following boundaries remain enforced in the reviewed implementation:

- JWT issuer, audience, algorithm, key, expiry, and server-session validity are
  checked; current membership/capability authorization remains authoritative.
- Auth JWT signing, Patch Format signing, and artifact verification trust are
  separate.
- PKCE uses S256, state is checked, redirects are exact, authorization codes
  are short-lived/single-use, and session/refresh secrets are not returned in
  URLs.
- Device codes are short-lived, rate/attempt limited, and single-use.
- Profile credentials are endpoint/API-base bound; remote HTTP credential
  transmission is rejected.
- Project/profile/configuration files contain identifiers and metadata, not
  credentials or signing material.
- Exact application, release, patch, sequence, digest, and signature checks
  remain enabled.
- Dashboard data uses the same identity/authorization authority as the CLI;
  audit data remains read-only and unsupported telemetry/actions are not
  fabricated.
- The first-owner bootstrap claim is persisted, and SSH is not part of normal
  developer authentication.

## Validation performed

Validation was limited to changed and directly affected scopes:

- CLI: `dart analyze lib test` passed; the focused auth/profile/configuration,
  discovery, status, onboarding, rollout, and compatibility tests passed.
  The final focused auth/profile run completed with 35 passing tests. Direct
  `hyfens --version` passed, and the unsupported platform selector returned
  the expected usage failure.
- Control plane: `dart analyze lib test` passed; the final focused config,
  human-auth, HTTP-auth, extension, overview, and bootstrap tests passed with
  27 tests passing.
- Dashboard and web: Python compilation, JavaScript syntax checks, and the
  dashboard server suite passed with 10 tests passing. Static HTTP and
  desktop/mobile rendering checks passed.
- Docker: disposable Compose configuration validation, image build, startup,
  health/readiness, discovery, and explicit volume/container cleanup passed.
  The smoke environment used loopback-only ports and dummy local values; no
  production credentials were used.
- Repository/public-reference review found no stale public command invocation
  requiring `tool`; the remaining `tool` references are intentional
  compatibility/history or filename references.

One broader CLI process test invocation was stopped after child-process launch
contention; it is not treated as product evidence. The focused tests and
direct executable checks above passed, and no source change was required for
that harness condition.

## Acceptance assessment

Local acceptance covers the frozen CLI, auth, profile, discovery, project
binding, dashboard, landing, and Docker contracts. The existing deployed
Hetzner/R2 lifecycle and Auth v1 proof remain established separately.

The following live gates were not claimed by this milestone: browser login on
the public `app.hyfens.com`, a newly deployed product web/API topology,
packaged self-host installation, public binary distribution, and physical
device activation.

## Findings by required classification

### BLOCKER

None evidenced. No required local/Docker product workflow, security boundary,
data-integrity invariant, or affected-target validation failed after the
bounded corrections.

### EXTERNAL GATE

- Public DNS/TLS/routing and live acceptance for `hyfens.com`,
  `app.hyfens.com`, and `api.hyfens.com`.
- Production deployment operations, HA, backup/restore, key custody,
  capacity, monitoring, and incident response.
- AWS/provider compatibility, physical-device activation, store review,
  privacy/terms/legal review, and any required external approvals.

### BACKLOG

- Native macOS Keychain, Windows Credential Manager, and Linux Secret Service
  adapters; the current fallback is protected with `0700`/`0600` permissions.
- Avoiding persisted short-lived access-token material in the compatibility
  fallback where native storage is unavailable.
- Browser-safe API-key inventory/last-used/revoke UI only after authoritative
  list APIs are available; the dashboard does not fake this surface.
- Remote interactive application/environment selection or creation for
  `hyfens init` where safe backend APIs are not yet exposed.
- Published cross-platform binaries/package-manager installation and CI/CD
  image deployment automation.
- Live managed/self-host domain acceptance and a packaged self-host TLS/HA
  distribution path.
- Future OIDC exchanges and delivery-auth modernization.

### ACCEPTED LIMITATION

- The current deliverable is a source-checkout CLI with local-Docker/server
  validation and an operator-managed single-node self-host deployment shape;
  it is not a production hosting commitment.
- Browser/device approval pages are implemented as static web surfaces but
  require separate HTTPS hosting and discovery configuration before live use.
- The dashboard is intentionally read-only for backend capabilities that do
  not expose safe authoritative mutation/list APIs.
- The deprecated `tool` shim remains temporarily for compatibility.
- Supported patching remains bounded by the existing Flutter/Dart/runtime and
  exact-application constraints; arbitrary code, native changes, and store
  acceptance are outside this milestone.

### NO ACTION

- No Task 210 or numbered follow-up task is warranted.
- No AWS work, remote infrastructure mutation, SSH-based developer flow, or
  additional coverage campaign is part of this closure.
- Historical evidence that necessarily uses `tool` does not require rewriting.

## Explicit non-claims and deferred work

This review does not claim production readiness, beta readiness, App Store or
Google Play compliance, enterprise readiness, AWS acceptance, legal/privacy
approval, or managed-cloud availability. Those are separate gates.

Deferred work is limited to the backlog and external gates above. It is not
being converted into numbered tasks or a recursive audit cycle.

## Final recommendation

`HYFENS DEVELOPER PLATFORM — PASS WITH EXTERNAL GATES`

The evidence supports the bounded productization implementation at local and
local-Docker scope, with no remaining material product blocker found in the
integrated review. Live domains, packaged distribution, production operations,
devices, AWS, stores, and legal/privacy approvals remain explicit external
gates.

## CMS and unified web application continuation — 2026-08-31

The website/CMS continuation uses one Next.js application and one Node runtime
on Hetzner. Host-based routing separates the public marketing surface from the
authenticated platform application while keeping the editorial CMS at
`/cms`. This avoids creating a second CMS server or a second identity store.
The CMS uses the existing control-plane content API, and public content is
read-only from the API's explicitly configured publication organization.

The deployed platform target is available on the Hetzner loopback edge at
`127.0.0.1:18085`, with the application runtime on `127.0.0.1:18084`. The
bounded deployment wrapper builds the reviewed image, recreates only the web
service, validates the Nginx configuration, and leaves the P2 data volumes,
R2 configuration, and control-plane state untouched.

The existing demo scope was bootstrapped successfully without persisting
password plaintext:

| Scope | Identifier |
| --- | --- |
| Organization | `org70760ae2ff001f83f59af0f1b43cb67e5df1` |
| Application | `app6c9b6afc1fe6e72e6b5945a2708b218c7c0e` |
| Environment | `env0179b608edaa997d4ebe85887ae029542568` |
| Super-admin owner | `usr_7531beef241793263ba94518e0aaa8ec` (`super-admin`) |
| Content admin | `usr_21b15ca10bf9738033ad42f25fd5c453` (`content-admin`) |

The owner has the existing control-plane authority for release lifecycle
operations; the content-admin profile is bounded to editorial CMS capability.

Scoped validation passed for the web package: TypeScript, ESLint, production
build, Docker image build, Compose configuration, and disposable container
health. Remote loopback host-header probes returned HTTP 200 for `/`,
`/login`, `/cms`, `/blog`, and `/news`. Public API health, readiness, and
discovery remained HTTP 200 after deployment.

The following are not claimed as live completion because they require provider
or DNS access outside the repository: public `app.hyfens.com` DNS/TLS and
edge routing, replacement of the existing Hostinger landing content, and
initial public CMS publication configuration/content. No Hostinger files were
uploaded by this continuation. No unit tests were added or run, as explicitly
requested for this implementation pass.
