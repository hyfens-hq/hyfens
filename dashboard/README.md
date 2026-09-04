# Hyfens Customer/Instance Workspace

This directory contains the dependency-free customer web surface shipped by
the public Hyfens repository. It is the self-hosted Customer/Instance
Workspace, not the Hyfens Cloud Platform Console. The same customer concepts
can be used by a managed Cloud composition, but the global platform operator
surface is owned by the private `hyfens-cloud-web` project.

The workspace operates inside:

```text
Organization → Application → Environment
```

It provides tenant-scoped applications, environments, delivery records,
members/invitations, credentials, support, audit, settings, and the browser
authorization/device-approval surfaces required by the CLI. Release and patch
creation remain CLI-driven because they depend on the local Flutter source
tree and signing boundary. The browser only calls explicit control-plane
operations for supported metadata and promotion actions.

## Run it locally

Start the control plane first. The default local process listens on
`http://127.0.0.1:18081`:

```sh
cd packages/control_plane
dart run bin/control_plane.dart \
  --root .hyfens-control-plane \
  --bootstrap \
  --host 127.0.0.1 \
  --port 18081
```

For human sign-in, start the control plane with its explicit human-auth
signing configuration and ensure an owner exists. The workspace does not
accept the legacy control credential in the browser.

In a second terminal, from the repository root, serve the page through the
stdlib-only same-origin local proxy:

```sh
python3 dashboard/serve.py \
  --api-origin http://127.0.0.1:18081 \
  --bind 127.0.0.1 \
  --port 8080
```

Open `http://127.0.0.1:8080/`. Customer sections use clean paths such as
`/applications` and `/settings`; deep-link refresh is handled by the static
customer fallback. The proxy forwards only reviewed auth, discovery, CLI
authorization, device-approval, public onboarding, and customer/organization
routes. It is not a generic browser proxy.

The supported browser API surface includes:

```text
GET/POST  Auth v1, OAuth/PKCE, and device authorization routes
GET       /.well-known/hyfens
GET       /v1/organizations/{organization_id}/overview
GET/PATCH /v1/organizations/{organization_id}/applications/{application_id}
POST      /v1/organizations/{organization_id}/applications
POST      /v1/organizations/{organization_id}/applications/{application_id}/archive
POST      /v1/organizations/{organization_id}/applications/{application_id}/environments
PATCH     /v1/organizations/{organization_id}/environments/{environment_id}
POST      /v1/organizations/{organization_id}/environments/{environment_id}/archive
GET/POST  organization members, invitations, credentials, and support cases
POST      /v1/organizations/{organization_id}/ownership-transfer
POST      /v1/organizations/{organization_id}/environments/{environment_id}/release-promotions
GET/POST  public invitation preview and redemption routes
```

Exact method, query, and body validation remains in `dashboard/serve.py` and
the control plane. Customer mutations are tenant-scoped, capability-checked,
validated, idempotent where required, and audited server-side.

The customer organization selector contains only organizations represented by
the authenticated user's customer memberships. It is never a platform-wide
directory. Platform organizations, commercial projections, staff
administration, global support queues, managed operations, and platform audit
are deliberately absent from this source and image.

## Authentication and secrets

The browser uses the control plane's human-session authentication routes. Access
and session tokens are kept in tab-scoped `sessionStorage` for the current
static workspace; they are not persisted in `localStorage`, cookies, or token
URLs. A browser context that cannot provide session storage remains usable only
for the unauthenticated surface. Passwords, bearer credentials, signing keys,
and provider secrets are never written to source, logs, documentation, or image
build inputs.

The CLI approval page is `/cli/authorize/` and the device approval page is
`/device/`. Both use the shared human-auth contract and must be advertised by
the instance discovery response before use. A deployment must explicitly allow
its workspace origin through `HYFENS_WEB_ORIGINS`.

## Container deployment

For the supported PostgreSQL, MinIO, control-plane, and customer workspace
Compose installation, follow the public
[self-hosted deployment guide](../deploy/self-hosted/README.md). The published
`hyfens-dashboard` image contains only this Customer/Instance Workspace and
its shared auth/discovery/device surfaces. It does not contain the Cloud
Platform Console.

## Product boundary

```text
hyfens OSS             → Customer/Instance Workspace + self-host deployment
hyfens-cloud-web       → Cloud composition + Platform Console
platform.hyfens.com    → Cloud Platform Console
api.hyfens.com         → managed control plane
```

Self-hosted installations use their own origin and discovered/configured API
endpoint; they do not require `hyfens-cloud-web`, Cloud credentials, or a
global platform staff identity. See
[`docs/architecture/dashboard-separation.md`](../docs/architecture/dashboard-separation.md)
and [`docs/OSS_CLOUD_SOURCE_BOUNDARY.md`](../docs/OSS_CLOUD_SOURCE_BOUNDARY.md)
for the complete ownership and contract boundary.
