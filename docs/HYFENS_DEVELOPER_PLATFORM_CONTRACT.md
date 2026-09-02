# Hyfens Developer Platform Contract Freeze

Status: FROZEN FOR ONE PRODUCTIZATION MILESTONE

This document is the shared interface contract for the bounded developer
platform productization work. It records the smallest contract that the
parallel workstreams must implement and test. It does not authorize a hosted
production rollout or change the existing Patch Format, runtime, or trust
model.

## Scope

The milestone makes one developer workflow work against a managed or
self-hosted control plane:

```text
hyfens login → profile → hyfens init → release/patch/deploy
```

The same identity and authorization authority serves the CLI and the web
dashboard. Local Docker is the required validation environment for new server
and web integration. Existing deployment evidence remains historical evidence;
this milestone does not require a remote deployment.

## Non-goals

The milestone does not implement AWS support, physical-device acceptance,
store or legal approval, production HA, a third-party identity platform,
delivery-auth redesign, fleet telemetry, arbitrary-Dart support, billing, or
SSH-based developer authentication. It does not create numbered task files.

## Public CLI

The canonical executable and all new public examples use `hyfens`.

The current `tool` entry point may remain as a compatibility shim only if it
delegates to the same command runner and emits a clear deprecation message:

```text
tool is deprecated; use hyfens
```

There must not be two independent CLIs. Existing internal and historical
fixtures may continue to refer to `tool` where changing them would alter
evidence unrelated to this milestone.

The public command surface for this milestone is:

```text
hyfens login [--host URL] [--profile NAME] [--device]
hyfens logout
hyfens status
hyfens doctor
hyfens profile list|show|use|remove|current
hyfens init
hyfens release android|ios
hyfens patch android|ios
hyfens deploy
hyfens rollback
hyfens inspect
hyfens verify
```

Existing lower-level commands can remain available internally; they are not
required to be part of the polished public help surface.

## Profile model

The profile is the durable non-secret selection for a control plane:

```text
Profile
  → control-plane endpoint
  → authenticated session
  → organization
  → application
  → environment
```

Profile metadata is stored separately from credentials. The minimum fields
are:

```toml
active_profile = "hyfens-cloud"

[profiles.hyfens-cloud]
endpoint = "https://api.hyfens.com/p2/"
managed = true
organization = "org_..."
application = "app_..."
environment = "env_..."

[profiles.acme]
endpoint = "https://hyfens.acme.com/"
managed = false
organization = "org_..."
application = "app_..."
environment = "env_..."
```

The exact on-disk format may follow the existing repository convention, but
it must preserve these semantics. Profiles contain no password, session
secret, JWT, bearer token, signing key, or private key. Normal commands use
the active profile and do not require repeated endpoint arguments.

Credentials are keyed by the normalized endpoint origin and API base path.
A session obtained from one host must never be sent to another host.

## Managed and self-hosted endpoints

The managed product host is `api.hyfens.com`. The currently proven managed
API base is `https://api.hyfens.com/p2/`; the CLI Cloud default uses that exact
base until a different versioned public route is deployed and documented.

Self-hosted login accepts an explicit HTTPS API base or host:

```bash
hyfens login --host https://hyfens.acme.com --profile acme
```

The CLI normalizes the value once, performs compatibility discovery, stores
the resulting endpoint in the profile, and reuses it. Remote plain HTTP is
rejected for credential-bearing flows. HTTP is allowed only for explicit
loopback development (`localhost`, `127.0.0.1`, or `::1`).

## Browser authentication: Authorization Code + PKCE

The preferred human login is a public-client Authorization Code flow with
PKCE:

```text
CLI → browser authorization page → user authentication/approval
    → loopback callback → one-time short-lived code exchange
    → revocable server session → short-lived access JWT
```

The interface requires a cryptographically random `state` checked against the
callback, S256 PKCE, exact redirect URI validation, a single-use code with a
short expiry, and no session or refresh secret in a URL. Browser auth uses the
same user, membership, session, and authorization authority as the existing
control plane. The control-plane discovery document may advertise a separate
HTTPS approval page plus its API authorization endpoint. Browser origins are
an exact, explicit allowlist; wildcard CORS is not part of the contract.

## Device authorization

Headless login is available as:

```bash
hyfens login --device
```

The CLI displays a short-lived user code and a verification URL. The device
authorization record is rate limited, attempt limited, single use, and
expires promptly. Approval happens in the authenticated web application; the
CLI polls without exposing a bearer secret to the user. Expired or consumed
codes cannot create a session.

## Session and credential storage

Access JWTs remain short-lived at the currently proven 15-minute value.
Server-side sessions remain revocable and use the currently proven 30-day
session lifetime unless a focused security finding requires a change. JWT
authentication keys remain separate from Patch Format signing keys.

The CLI prefers native OS credential storage (macOS Keychain, Windows
Credential Manager, or Linux Secret Service). The portable fallback is:

```text
~/.hyfens/       mode 0700
credentials     mode 0600
```

The current compatibility fallback stores the short-lived access token and
session credential in that protected file; it is excluded from the
repository. Native credential adapters and avoiding persisted access-token
material remain hardening work, not a prerequisite for this milestone.
Profile/configuration files contain metadata only. Logout revokes the server
session and removes local session material.

## Machine authentication

Human browser/device sessions are not the CI contract. CI uses a scoped,
expirable, revocable service/API key exposed through the public environment
variable `HYFENS_TOKEN`. The existing `HYFENS_CONTROL_TOKEN` and
`HYFENS_DELIVERY_TOKEN` paths remain compatibility inputs internally, but new
human documentation does not require them. The interface leaves room for a
future OIDC token exchange without implementing provider-specific OIDC here.

If API-key management is not backed by an authoritative endpoint in the
current control plane, the dashboard must show a read-only unavailable state;
it must not fake create/revoke actions.

## Instance discovery and compatibility

Each compatible control plane exposes:

```text
GET /.well-known/hyfens
```

relative to its configured API base. The response is versioned and non-secret,
and advertises the product, API version, supported auth methods, and product
capabilities. When browser/device pages are deployed, discovery also advertises
their non-secret URLs and the API uses exact configured web origins. The CLI
validates HTTPS policy, parses the response, and emits a clear compatibility
diagnostic before login when the instance is unsupported. Compatibility is
determined by the versioned response, never by hostname.

## Self-hosted first-owner bootstrap

Self-hosted installation has one bounded first-owner seam: a server-local or
environment-provided one-time bootstrap capability creates the initial owner
for an existing installation. A durable per-scope claim consumes the
capability; repeating the same owner request is idempotent, while a different
owner is rejected. Passwords are accepted only through a protected stdin/secret
mechanism, never command arguments or committed configuration.

After bootstrap, the owner and all other users use browser/device login. No
developer workflow depends on SSH, database access, or manual bearer-token
copying.

## Project binding

`hyfens init` detects the Flutter project and platform application identities,
resolves the active profile, and writes a minimal committed `hyfens.yaml`
binding. The file contains only safe organization/application/environment
identifiers as required by the API. It contains no credentials or signing
material. Exact application identity validation remains enabled; `init`
should report a mismatch early rather than weaken the guard.

## Web product boundaries

The topology is:

```text
hyfens.com          static marketing/landing
configured dashboard authenticated dashboard and browser auth
api.hyfens.com      managed control plane
```

The landing site explains only supported capabilities: signed, exact-release,
bounded Flutter patches, controlled deployment, verification, and rollback
where the current implementation proves them. It must not claim App Store or
Google Play approval, zero risk, arbitrary Flutter patching, or production
availability without evidence.

The dashboard uses the same authenticated identity and authoritative APIs as
the CLI. It may display organization/application/environment context, current
release and patch state, deployments, and immutable audit data. It must not
invent telemetry, fleet counts, rollout percentages, or mutation controls
where no backend authority exists. Responsive shell, organization context,
theme, login/logout, releases, patches, deployments, audit, and settings are
in scope; real API-key controls are shown only when supported by the backend.

## Shared security invariants

1. Auth JWT signing material, Patch Format signing material, and artifact
   verification trust remain separate.
2. JWT identity/session claims do not replace authoritative membership,
   capability, tenant, or revocation checks.
3. Exact application, release, patch, sequence, digest, and signature checks
   remain enabled.
4. Credential-bearing remote requests require HTTPS except explicit loopback
   development.
5. Host-bound profile storage prevents cross-host credential leakage.
6. SSH is an infrastructure/operator mechanism, never a developer auth path.
7. Secrets do not appear in URLs, project config, profile metadata, logs,
   committed files, generated evidence, or Docker images.

## Acceptance boundary

The milestone is accepted only after focused local evidence covers:

```text
hyfens command and compatibility shim
managed/self-host profile resolution
PKCE state/code/redirect checks
device-code expiry/single-use/rate limits
secure session storage and host isolation
service-key scope/revocation where implemented
discovery and clear incompatibility errors
safe init binding and exact-identity diagnostics
dashboard critical read workflows
responsive landing/dashboard rendering
local Docker control-plane integration
```

Findings that do not violate these contracts are classified as backlog,
external gate, accepted limitation, or no action in the one consolidated
productization review. They do not create numbered follow-up tasks.
