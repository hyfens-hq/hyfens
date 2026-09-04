# Self-hosted Hyfens release

This Compose package runs the bounded single-node self-hosted surface from
published Hyfens images:

- `hyfens-control-plane` for accounts, organization scope, metadata, auth, and
  release/patch records;
- `hyfens-dashboard` for the Customer/Instance Workspace browser UI;
- PostgreSQL for metadata; and
- MinIO as the bundled S3-compatible artifact store.

It is an operator starting point, not a high-availability or production
readiness claim. Back up PostgreSQL and the object-store volume together,
protect the auth signing seed, and put a TLS reverse proxy in front of the two
loopback-bound application ports.

The public dashboard image is customer/instance scoped. It does not contain
Hyfens's global Platform Console, Cloud commercial operations, staff
administration, global support queue, or managed-fleet operations. Those are
private Cloud surfaces and are not required to run this self-hosted package.

## Install

Requirements: Docker Engine with Compose v2, a DNS name for the dashboard and
API, and a host-level TLS reverse proxy. The release images are published to
GHCR by the tagged GitHub release workflow. Anonymous GHCR pulls are currently
an external package-visibility gate: the published packages may respond with
HTTP 401 until an organization package administrator marks them public. This
is not a Compose configuration problem. Do not put registry credentials in
this repository; until visibility is corrected, use an authorized local
`docker login ghcr.io` or override the image variables with images built or
mirrored under your own control.

From this directory:

```sh
cp .env.example .env
openssl rand -hex 32
openssl rand -base64 32
```

Put fresh values in `.env`, replace both example hostnames with the actual
HTTPS names, and keep the dashboard and API values consistent:

```text
HYFENS_DASHBOARD_API_BASE=https://api.example.com/
HYFENS_WEB_ORIGINS=https://app.example.com
HYFENS_AUTH_AUTHORIZATION_ENDPOINT=https://app.example.com/cli/authorize/
HYFENS_AUTH_DEVICE_VERIFICATION_URI=https://app.example.com/device/
```

Configure the host reverse proxy using
[`nginx.conf.example`](nginx.conf.example). The important boundary is:

```text
https://app.example.com/  →  127.0.0.1:18083  (dashboard)
https://api.example.com/  →  127.0.0.1:18082  (control plane)
```

Do not expose port `18082` directly to the network. The control plane treats a
host-loopback proxy as the local transport boundary and does not trust an
arbitrary `X-Forwarded-Proto` header from another network.

Pull and start the matching version:

```sh
docker compose --env-file .env pull
docker compose --env-file .env up -d
docker compose --env-file .env ps
```

Check the local upstreams before testing the public HTTPS names:

```sh
curl --fail http://127.0.0.1:18082/healthz
curl --fail http://127.0.0.1:18082/readyz
curl --fail http://127.0.0.1:18082/.well-known/hyfens
curl --fail http://127.0.0.1:18083/healthz
```

## Create the first organization and owner

Bootstrap the first scope once. It prints IDs; save those IDs in a protected
operator note, not in the repository:

```sh
docker compose --env-file .env run --rm --no-deps control-plane \
  --bootstrap --bootstrap-only \
  --organization "Acme" \
  --application "com.acme.app" \
  --platform "acme-platform" \
  --environment "production"
```

Create the first owner through the server-local stdin-only seam:

```sh
read -r -s HYFENS_OWNER_PASSWORD
printf '%s\n' "$HYFENS_OWNER_PASSWORD" | \
  docker compose --env-file .env run --rm --no-deps control-plane \
  --bootstrap-owner --password-stdin \
  --organization-id <organization-id> \
  --application-id <application-id> \
  --environment-id <environment-id> \
  --email owner@example.com --profile acme
unset HYFENS_OWNER_PASSWORD
```

The bootstrap password is not stored in the profile, project binding, image,
or Compose file. A repeated request for the same owner is idempotent; a
different owner is rejected after the scope has been claimed.

Public client registration is disabled by default. If this instance should
accept registrations into the one bootstrapped organization, set
`HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID` to the printed organization ID in
`.env`, then recreate only the control plane:

```sh
docker compose --env-file .env up -d --force-recreate control-plane
```

The registration page never lets a caller choose an organization. Use an
invitation or an operator-created membership process when tenant isolation
requires tighter control.

## Connect an account and a Flutter project

An account connects to a control plane through a CLI profile. The browser
dashboard and CLI use the same human account, but the Flutter project binding
is created locally by `hyfens init`:

```sh
hyfens login --host https://api.example.com/ --profile acme
hyfens profile current

cd /path/to/your/flutter-app
hyfens doctor
hyfens init
```

Review the generated `hyfens.yaml`. It contains only the organization,
application, environment, and runtime application identifiers; it does not
contain a password, session, service token, signing seed, or private key.
Then use the normal release workflow:

```sh
hyfens release android
# edit supported ordinary Dart/Flutter code
hyfens patch android
hyfens verify <patch-file>
hyfens deploy
```

Use `ios` for the iOS baseline. A new login is needed only when switching to a
different endpoint or profile. `hyfens profile use acme` selects an existing
non-secret profile; ordinary commands reuse it.

CI should use a scoped, expirable `HYFENS_TOKEN` injected by the CI secret
store. Do not copy a human browser session into CI or commit any credential.

## Upgrade and backup boundary

The image tag is the product version. To upgrade, change `HYFENS_VERSION` in
`.env`, pull, and recreate the stack during a maintenance window:

```sh
docker compose --env-file .env pull
docker compose --env-file .env up -d
```

Back up PostgreSQL and the MinIO data volume before upgrades and test restores
as one set. Pin the database/object-store image variables when operating a
long-lived installation. The Compose package does not provide HA, automatic
TLS, external identity providers, backup scheduling, or zero-downtime
migrations.
