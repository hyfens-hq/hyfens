# Production configuration contract (P2)

This is an operator contract for the self-hosted control plane. It contains no
secret values. A value marked `VERIFIED LOCALLY` was exercised by the local
Compose or Dart tests; `DESIGN ONLY` is a required boundary that still needs
operator/provider selection.

## Control-plane process

| Variable | Required when | Meaning | Secret | Status |
| --- | --- | --- | --- | --- |
| `HYFENS_HOST` | always | bind address; loopback is the safe default | no | VERIFIED LOCALLY |
| `HYFENS_PORT` | always | `dart:io` listener port | no | VERIFIED LOCALLY |
| `HYFENS_FILE_ROOT` | file-store mode | local metadata root | no | VERIFIED LOCALLY |
| `HYFENS_DATABASE_URL` | PostgreSQL mode | PostgreSQL connection string | contains credential | VERIFIED LOCALLY |
| `HYFENS_ARTIFACT_ENDPOINT` | external artifact mode | S3-compatible endpoint | no | VERIFIED LOCALLY |
| `HYFENS_ARTIFACT_BUCKET` | external artifact mode | bucket name | no | VERIFIED LOCALLY |
| `HYFENS_ARTIFACT_ACCESS_KEY` | access-key auth | object-store access identity | yes | VERIFIED LOCALLY |
| `HYFENS_ARTIFACT_SECRET_KEY` | access-key auth | object-store secret | yes | VERIFIED LOCALLY |
| `HYFENS_ARTIFACT_AUTHORIZATION` | bearer-compatible object store | authorization header value | yes | VERIFIED LOCALLY |
| `HYFENS_ARTIFACT_REGION` | S3-compatible store | signing region | no | VERIFIED LOCALLY |
| `HYFENS_MAX_JSON_BYTES` | optional | JSON request limit | no | VERIFIED LOCALLY |
| `HYFENS_MAX_ARTIFACT_BYTES` | optional | artifact request limit | no | VERIFIED LOCALLY |
| `HYFENS_RATE_LIMIT_PER_MINUTE` | optional | process-local socket-peer limit | no | VERIFIED LOCALLY |
| `HYFENS_AUDIT_RETENTION_DAYS` | optional | audit export retention filter | no | VERIFIED LOCALLY |
| `HYFENS_AUTH_ISSUER` | human auth enabled | JWT issuer; must match validation configuration | no | VERIFIED LOCALLY |
| `HYFENS_AUTH_AUDIENCE` | human auth enabled | control JWT audience (`hyfens-control` in the demo) | no | VERIFIED LOCALLY |
| `HYFENS_AUTH_SIGNING_KEY` | human auth enabled | base64 auth-only Ed25519 seed | yes | VERIFIED LOCALLY |
| `HYFENS_AUTH_SIGNING_KEY_ID` | human auth enabled | active auth verification key ID | no | VERIFIED LOCALLY |
| `HYFENS_AUTH_VERIFY_KEYS` | key rotation | JSON map of retained key IDs to base64 public keys | no | VERIFIED LOCALLY |
| `HYFENS_AUTH_ACCESS_TTL` | optional | short-lived access JWT lifetime; default `15m` | no | VERIFIED LOCALLY |
| `HYFENS_AUTH_SESSION_TTL` | optional | revocable session lifetime; default `30d` | no | VERIFIED LOCALLY |
| `KEPLARS_API_KEY` | managed transactional email | Keplars API credential | yes | PROVIDER DEPENDENT |
| `KEPLARS_WEBHOOK_SECRET` | managed transactional email callbacks | Keplars HMAC secret | yes | PROVIDER DEPENDENT |
| `HYFENS_EMAIL_FROM` | managed transactional email | approved sender; default `no-reply@hyfens.com` | no | VERIFIED LOCALLY |
| `HYFENS_EMAIL_FROM_NAME` | managed transactional email | sender display name | no | VERIFIED LOCALLY |
| `HYFENS_WEB_ORIGINS` | notification links | comma-separated HTTPS dashboard/marketing origins | no | VERIFIED LOCALLY |
| `HYFENS_NOTIFICATION_PAYLOAD_KEY` | queued verification/recovery/deletion messages | base64-encoded 32-byte AES-GCM key | yes | VERIFIED LOCALLY + PROTECTED CONFIG REQUIRED |

`HYFENS_DATABASE_URL` and the artifact endpoint are mutually composable: the
metadata store and artifact store remain separate authorities. A patch signing
private key is not a control-plane environment variable; the customer/local
signer owns it and supplies only signed bytes plus the trusted public key to the
release process.

## Compose/operator wrapper variables

These variables are consumed by `deploy/p2/docker-compose.yml` or the
disposable HA/DR scripts rather than by `ControlPlaneConfig` directly:

| Variable | Purpose | Status |
| --- | --- | --- |
| `HYFENS_POSTGRES_PASSWORD` | local Compose PostgreSQL bootstrap password | VERIFIED LOCALLY |
| `HYFENS_S3_ACCESS_KEY` / `HYFENS_S3_SECRET_KEY` | local Compose object-store credentials | VERIFIED LOCALLY |
| `HYFENS_S3_BUCKET` / `HYFENS_S3_REGION` | local object-store identity | VERIFIED LOCALLY |
| `HYFENS_BIND_ADDRESS` and component port variables | bind test services to loopback or an explicitly scoped LAN | VERIFIED LOCALLY |
| `HYFENS_HA_*`, `HYFENS_DR_*` | disposable rehearsal project/ports | VERIFIED LOCALLY |

These defaults are suitable only for a disposable local rehearsal. They are not
production secrets or public-ingress configuration.

## Audit export and operations configuration

The audit-export signer is intentionally outside the control-plane process and
does not share the Patch Format signing key. An operator must select these
values in an offline signing environment:

| Setting | Meaning | Secret | Status |
| --- | --- | --- | --- |
| audit-export key ID | public-key identity carried in the signed envelope | no | DESIGN ONLY |
| audit-export private-key input | local/offline Ed25519 seed or signer handle | yes | DESIGN ONLY |
| audit-export public-key trust file | key used by an independent verifier | no | DESIGN ONLY |
| audit-export output directory | separate evidence destination | no | DESIGN ONLY |

The control plane only produces the tenant-scoped export data; it never
receives or stores the private audit-export key.

| Setting | Meaning | Status |
| --- | --- | --- |
| backup destination | operator-selected PostgreSQL dump and object-manifest/byte destinations | PROVIDER DEPENDENT |
| `HYFENS_ALLOW_RESTORE=1` | explicit restore opt-in for a named recovery target | VERIFIED LOCALLY |
| log level | operator-selected process logging threshold; redaction remains mandatory | DESIGN ONLY |
| metrics exposure | `/metrics` remains loopback/operator-only unless an edge policy is supplied | VERIFIED LOCALLY + EXTERNAL REVIEW REQUIRED |

## External boundary contract

An operator-selected reverse proxy must terminate TLS, enforce edge
authentication/rate limiting, cap request/body/timeouts, restrict the upstream
to the control-plane listener, and forward correlation headers according to the
local ingress policy. The Dart adapter intentionally ignores forwarded headers
for authorization. Certificate issuance, private-key storage, renewal,
revocation, and public DNS are `PROVIDER DEPENDENT` / `EXTERNAL REVIEW
REQUIRED`.

## Startup and compatibility invariants

Before accepting traffic, verify:

1. the configured runtime and Patch Format versions are the versions supported
   by the built control plane;
2. PostgreSQL migrations complete under the startup advisory lock;
3. the artifact endpoint and bucket are reachable;
4. `/healthz` is live and `/readyz` is ready;
5. no secret appears in health output, metrics, structured error logs, or
   committed configuration.

The configuration contract does not authorize a hosted control plane,
multi-region failover, a cloud KMS, or a public SaaS endpoint.

Human CLI login is an additive control-plane capability. Provision the first
owner for an existing scope with the supported `--bootstrap-owner
--password-stdin` command, then use `hyfens login`. Passwords, session
credentials, access JWTs, and private auth signing seeds remain outside the
repository. The existing opaque control/delivery credentials remain supported
for bootstrap, service accounts, automation, and delivery compatibility.

## Notification worker

Managed Cloud invokes the bounded notification dispatcher separately from the
HTTP process:

```text
dart run bin/control_plane.dart --process-notifications
```

The worker requires `KEPLARS_API_KEY`. Queueing verification, recovery, or
deletion messages additionally requires `HYFENS_NOTIFICATION_PAYLOAD_KEY`; the
HTTP process then stores encrypted payloads and the worker decrypts them only
in memory immediately before rendering. Provider callbacks, when enabled, are
posted to `POST /v1/notifications/webhooks/keplars` with the raw-body HMAC in
`X-Keplars-Signature` and `KEPLARS_WEBHOOK_SECRET`.

For a local provider-free template preview, use:

```text
dart run bin/control_plane.dart --preview-notification billing.payment.failed
```

Preview mode renders deterministic HTML and plain text and does not initialize
the database or send an email.
