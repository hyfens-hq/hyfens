# Self-hosted Hyfens

Status: bounded OSS/self-hosted operator contract with a single-node release
Compose package. This is not a production readiness, HA, backup, security, or
remote-deployment claim.

This is the smallest current self-hosted surface: the existing control-plane
process, PostgreSQL metadata, an S3-compatible artifact store, and the same
`hyfens` CLI profile used for a managed endpoint. There is no forked CLI,
identity provider, or new authorization model.

## Endpoint boundary

The operator-facing API base is HTTPS by default:

```text
https://hyfens.example.com/
```

Remote credential-bearing HTTP is not supported. HTTP is reserved for an
explicit loopback development endpoint such as:

```text
http://127.0.0.1:18082/
```

The control-plane HTTP listener is an upstream, not a public endpoint. A
customer-managed edge must terminate TLS, keep the upstream private, and
forward to a trusted local listener. Do not publish the control-plane port
directly to a network. The existing [P2 nginx example](../deploy/p2/nginx.conf.example)
shows the certificate-secret and timeout boundary; certificates and private
keys are operator inputs and are not part of this repository.

The current control plane deliberately does not treat `Forwarded` or
`X-Forwarded-Proto` as proof of secure transport. A proxy in a separate
Compose network must not be assumed to make credential-bearing requests safe.
The release package therefore binds both application ports to host loopback
and requires a host-level TLS reverse proxy. See the
[single-node release package](../deploy/self-hosted/README.md) and its
[Nginx example](../deploy/self-hosted/nginx.conf.example). The existing
[P2 Compose fixture](../deploy/p2/docker-compose.yml) remains the source-build
validation shape.

## Configuration contract

Configure these values through the operator's protected environment or secret
mechanism. Do not commit a populated `.env` file, token, password, signing
seed, certificate, or private key.

<!-- Wide configuration table disables MD013. -->
<!-- markdownlint-disable MD013 -->

| Concern | Existing control-plane contract |
| --- | --- |
| Metadata | `HYFENS_DATABASE_URL`, or the supported database components. The P2 fixture uses PostgreSQL. |
| Artifacts | `HYFENS_ARTIFACT_ENDPOINT`, `HYFENS_ARTIFACT_BUCKET`, `HYFENS_ARTIFACT_ACCESS_KEY`, `HYFENS_ARTIFACT_SECRET_KEY`, and `HYFENS_ARTIFACT_REGION`. The P2 fixture uses MinIO and AWS Signature V4. |
| Discovery | `HYFENS_API_BASE_PATH` defaults to `/`; `HYFENS_DISCOVERY_PRODUCT`, `HYFENS_DISCOVERY_PRODUCT_VERSION`, and `HYFENS_DISCOVERY_API_VERSION` control the non-secret versioned discovery metadata. The API base path is retained in the CLI profile and runtime delivery URL. |
| Human auth | Set `HYFENS_AUTH_SIGNING_KEY` to a base64-encoded 32-byte auth-only Ed25519 seed. Without it, human auth endpoints are disabled and only opaque credentials remain. |
| Auth identity | `HYFENS_AUTH_ISSUER` and `HYFENS_AUTH_AUDIENCE` default to `hyfens-control-plane` and `hyfens-control` when omitted. The P2 Compose mapping passes these fields, so set them explicitly there. |
| Auth lifetime and bounds | The direct process defaults are a 15-minute access JWT, a 30-day revocable session, a one-minute authorization code, and a ten-minute device code. `HYFENS_AUTH_SIGNING_KEY_ID`, `HYFENS_AUTH_ACCESS_TTL`, `HYFENS_AUTH_SESSION_TTL`, `HYFENS_AUTH_CODE_TTL`, `HYFENS_AUTH_DEVICE_TTL`, `HYFENS_AUTH_DEVICE_POLL_INTERVAL`, `HYFENS_AUTH_DEVICE_MAX_ATTEMPTS`, and `HYFENS_AUTH_DEVICE_ATTEMPTS_PER_MINUTE` are optional bounded overrides. `HYFENS_AUTH_VERIFY_KEYS` is the optional JSON map for retained verification keys during rotation. |
| Browser auth | `HYFENS_AUTH_AUTHORIZATION_ENDPOINT` and `HYFENS_AUTH_DEVICE_VERIFICATION_URI` advertise the separately hosted approval pages. `HYFENS_AUTH_ALLOWED_REDIRECT_URIS` is the exact JSON redirect allowlist for non-loopback HTTPS clients. `HYFENS_WEB_ORIGINS` is the exact browser-origin allowlist. |
| Release images | `deploy/self-hosted/docker-compose.yml` consumes versioned `hyfens-control-plane` and `hyfens-dashboard` images. `HYFENS_VERSION` must match a published release tag; the dashboard API base is injected at container startup. |

<!-- markdownlint-enable MD013 -->

Keep the control plane and artifact store on the same private service network
or use an operator-managed external service. The server owns metadata,
eligibility, authentication, and artifact lookup; the Flutter runtime remains
the authority for artifact signature, exact release, capabilities, sequence,
health, rollback, and fallback.

## Local validation quickstart

This is a disposable loopback check of the existing P2 fixture, not a
self-hosted internet deployment. Run it from the repository root with local
values held outside the repository:

```sh
export HYFENS_POSTGRES_PASSWORD="$(openssl rand -hex 32)"
export HYFENS_S3_ACCESS_KEY="hyfens-local-$(openssl rand -hex 8)"
export HYFENS_S3_SECRET_KEY="$(openssl rand -hex 32)"
export HYFENS_AUTH_SIGNING_KEY="$(openssl rand -base64 32)"
export HYFENS_AUTH_SIGNING_KEY_ID='auth-ed25519-local'
export HYFENS_AUTH_ISSUER='hyfens-local'
export HYFENS_AUTH_AUDIENCE='hyfens-control'
export HYFENS_AUTH_ACCESS_TTL='15m'
export HYFENS_AUTH_SESSION_TTL='30d'
docker compose -f deploy/p2/docker-compose.yml up --build
```

In another terminal, verify process liveness, dependency readiness, and
discovery:

```sh
curl --fail http://127.0.0.1:18082/healthz
curl --fail http://127.0.0.1:18082/readyz
curl --fail http://127.0.0.1:18082/.well-known/hyfens
```

The P2 service initializes PostgreSQL migrations and the MinIO bucket through
the existing Compose dependencies. The supported bootstrap helper creates an
initial organization, application, and environment without manual database
changes:

```sh
docker compose -f deploy/p2/docker-compose.yml exec -T control-plane \
  dart run bin/control_plane.dart --bootstrap --bootstrap-only
```

Record only the printed organization, application, and environment IDs in a
protected operator note. The helper also prints opaque credentials; do not
place those values in this document, shell history, profile metadata, or a
committed file.

## First-owner boundary

After the resources exist, create the first human owner through the existing
server-local one-shot seam. The password is read from stdin, never from a
command argument:

```sh
read -r -s HYFENS_OWNER_PASSWORD
printf '%s\n' "$HYFENS_OWNER_PASSWORD" | \
  docker compose -f deploy/p2/docker-compose.yml exec -T control-plane \
  dart run bin/control_plane.dart \
  --bootstrap-owner --password-stdin \
  --organization-id <organization-id> \
  --application-id <application-id> \
  --environment-id <environment-id> \
  --email operator@example.com --profile acme
unset HYFENS_OWNER_PASSWORD
```

Use the same command against an operator-managed control-plane process when
the resources already exist. The IDs must refer to the same organization,
application, and environment. Restrict access to this server-local operation
and run it once during installation; subsequent users use normal auth flows.
The implementation persists a per-scope bootstrap-consumption claim. Repeating
the same owner request is idempotent, while a different owner is rejected;
this keeps the server-local seam bounded to first-owner initialization.

## Discovery, auth, and profiles

Discovery is unauthenticated, versioned, and non-secret. It is served at
`/.well-known/hyfens` relative to the configured API base. For example,
`HYFENS_API_BASE_PATH=/p2/` serves `/p2/.well-known/hyfens` and all `/p2/v1`
product/runtime routes while retaining the legacy root routes for existing
local callers. Browser and device
login use discovery to validate the product, API version, advertised auth
methods, and advertised endpoint authority before using a self-hosted profile.
The password compatibility path validates the endpoint transport and calls the
existing password-session endpoint directly.

Use the canonical public CLI name and an explicit HTTPS base for a remote
instance:

```sh
hyfens login --host https://hyfens.example.com/ --profile acme
```

That command uses the advertised browser Authorization Code + PKCE flow when
the instance also has a compatible approval surface. For a headless operator,
use the advertised device flow:

```sh
hyfens login --host https://hyfens.example.com/ --profile acme --device
```

The repository includes static browser approval pages at
`dashboard/cli/authorize/` and `dashboard/device/`. A self-hosted operator
must publish them over HTTPS, configure their exact origin in
`HYFENS_WEB_ORIGINS`, and advertise the page URLs through discovery. Where
those pages are not deployed, the existing password-session compatibility path
can be used instead; the CLI prompts for the password and still binds the
resulting session to the endpoint:

```sh
hyfens login \
  --host https://hyfens.example.com/ \
  --profile acme \
  --email operator@example.com
```

For a private test or customer CA, pass the CA explicitly with
`--ca-cert /path/to/trusted-ca.pem` or set `HYFENS_TLS_CA_CERT`. Do not put a
private key in the CLI or control plane.

The profile is non-secret endpoint and scope metadata. Credentials are stored
separately by the CLI. The normal flow after login is:

```sh
hyfens profile current
hyfens profile list
hyfens init
hyfens release android
hyfens patch android
hyfens deploy
hyfens logout
```

Normal commands use the active profile. CI service credentials remain
request-scoped secret inputs; inject them through the CI secret store rather
than writing them to a profile, `hyfens.yaml`, logs, or this repository.

## Deliberate limitations and backlog

- `deploy/self-hosted` is a bounded single-node package. It makes no HA,
  backup/restore, capacity, compliance, public-ingress, or production
  hardening claim.
- The first-owner command is server-local and stdin-protected. Its per-scope
  consumption claim is persisted, a retry for the same owner is idempotent,
  and a different owner is rejected.
- No remote deployment or manual database mutation is required or provided.

## Evidence

This contract is based on the existing [P2 Compose definition](../deploy/p2/docker-compose.yml),
[P2 operator notes](../deploy/p2/README.md), [P2 TLS example](../deploy/p2/nginx.conf.example),
the [control-plane entrypoint](../packages/control_plane/bin/control_plane.dart),
the [control-plane configuration](../packages/control_plane/lib/src/config.dart),
the [HTTP adapter](../packages/control_plane/lib/src/http.dart), and the CLI's
[discovery](../cli/lib/src/discovery.dart), [auth client](../cli/lib/src/auth_client.dart),
and [profile model](../cli/lib/src/profile.dart).
