# Hyfens developer dashboard

This directory contains the dependency-free dashboard shell for a configured
Hyfens dashboard host. The browser uses the control plane's human-session
authentication routes and keeps the access and session tokens only in live
memory. It does not use `localStorage`, `sessionStorage`, cookies, or token
URLs.

The dashboard is intentionally read-only. It renders the safe overview
projection when the configured control plane provides it. Releases, patches,
deployment records, and audit records are never synthesized from counts or
client-side guesses. Unsupported backend capabilities are shown as
unavailable.

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

For human sign-in, the control plane must also be started with its explicit
human-auth signing configuration and an owner must exist. The dashboard does
not accept the legacy control credential in the browser.

In a second terminal, from the repository root, serve the page through the
stdlib-only same-origin local proxy:

```sh
python3 dashboard/serve.py \
  --api-origin http://127.0.0.1:18081 \
  --bind 127.0.0.1 \
  --port 8080
```

Open `http://127.0.0.1:8080/`. Dashboard sections use clean paths such as
`/applications` and `/settings`; legacy hash fragments and temporary query
parameters are removed when the page loads. The proxy forwards only these
known routes:

```text
GET  /.well-known/hyfens
GET  /auth/authorize?{validated OAuth request}
POST /auth/login
POST /auth/refresh
POST /auth/logout
POST /auth/authorize
POST /auth/token
POST /auth/device/code
POST /auth/device/token
POST /auth/device/approve
GET  /auth/me
POST /v1/public/register
POST /v1/public/waitlist
POST /v1/public/newsletter
GET  /v1/organizations/{organization_id}/overview
```

Public registration accepts exactly `{"email":"...","password":"..."}`
and returns the same immediate `HumanLoginResult` JSON as password login. It
is enabled only when `HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID` names an
existing server-side organization; the caller cannot select an organization,
role, or capability. The waitlist and newsletter routes accept `email` plus
optional bounded `name` and `source` fields and return
`{"status":"accepted"}` for both new and duplicate submissions.

The CLI approval page is `/cli/authorize/` and the device approval page is
`/device/`. Both keep password and session material in memory, call the
shared human-auth routes, and never put a session credential in a URL. The
control plane must allow the dashboard origin through its explicit
`HYFENS_WEB_ORIGINS` setting when the page is hosted on a different origin.

The dashboard does not fall back to a machine credential or request the
current audit export because that response is not a browser-safe redacted
projection. Audit records are rendered only when they arrive through the safe
overview response.

## Container deployment

For the supported PostgreSQL, MinIO, control-plane, and dashboard Compose
installation, follow the public [self-hosted deployment guide](../deploy/self-hosted/README.md).
The dashboard image receives its API base at container startup through
`HYFENS_API_BASE`; it never bakes an endpoint or credential into the image.

## Backend boundaries

The dashboard can display organization, application, environment, release,
patch, rollout, artifact, and redacted audit records only when they are
returned by the authoritative read-only overview projection. It does not
claim runtime health, fleet telemetry, rollout success, invitations, or API
key management. The settings page marks API-key management unavailable until
the control plane advertises a browser-safe credential inventory contract.
