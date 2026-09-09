# Hyfens public control-plane development stack

The R2-backed Compose variant is a bounded, single-node development
deployment: one public control-plane process, PostgreSQL metadata, and an
S3-compatible object store. It is not HA, internet-scale, a production
deployment, or a hosted service. It is intended for local integration,
recovery, and controlled development-host tests only.

The repository directory remains `deploy/p2/` for compatibility with the
other local and HA fixtures. The active R2-backed deployment uses explicit
development names:

| Purpose | Canonical name |
| --- | --- |
| Compose file | `docker-compose.public-control-plane-dev.yml` |
| Compose project | `hyfens-public-control-plane-dev` |
| Host deployment target | `/opt/hyfens/public-control-plane-dev` |
| Protected environment | `/etc/hyfens/public-control-plane-dev.env` |
| Fixed deployment wrapper | `/usr/local/sbin/hyfens-public-control-plane-dev-deploy` |

The physical PostgreSQL volume intentionally retains its old
`hyfens-p2-r2-postgres` name during this naming-only migration so the
development database is not replaced with an empty volume.

The current control-plane package has local path dependencies on
`packages/patch_format`, `packages/runtime`, `experiments/instrumentation`,
and `experiments/patch_loading`. All four trees are part of the deployment
input; staging only `packages/control_plane` is an obsolete layout and will
fail during `dart pub get`.

For a development host, stage the reviewed tree and run
`install-public-control-plane-dev-deploy-access.sh` once as root. It installs
only the fixed deployment wrapper and its exact sudo rule; routine deployments
then use the wrapper without a general root shell.

The source staging boundary is explicit and does not include the rest of the
repository:

```sh
rsync -a --delete \
  --exclude '.dart_tool/' --exclude 'build/' --exclude 'coverage/' \
  --exclude '.DS_Store' \
  deploy/p2/ \
  hyfens-server:/home/hyfen/p2-deploy-stage/deploy/p2/
rsync -a --delete \
  --exclude '.dart_tool/' --exclude 'build/' --exclude 'coverage/' \
  --exclude '.DS_Store' \
  packages/control_plane/ \
  hyfens-server:/home/hyfen/p2-deploy-stage/packages/control_plane/
rsync -a --delete \
  --exclude '.dart_tool/' --exclude 'build/' --exclude 'coverage/' \
  --exclude '.DS_Store' \
  packages/patch_format/ \
  hyfens-server:/home/hyfen/p2-deploy-stage/packages/patch_format/
rsync -a --delete \
  --exclude '.dart_tool/' --exclude 'build/' --exclude 'coverage/' \
  --exclude '.DS_Store' \
  packages/runtime/ \
  hyfens-server:/home/hyfen/p2-deploy-stage/packages/runtime/
rsync -a --delete \
  --exclude '.dart_tool/' --exclude 'build/' --exclude 'coverage/' \
  --exclude '.DS_Store' \
  experiments/instrumentation/ \
  hyfens-server:/home/hyfen/p2-deploy-stage/experiments/instrumentation/
rsync -a --delete \
  --exclude '.dart_tool/' --exclude 'build/' --exclude 'coverage/' \
  --exclude '.DS_Store' \
  experiments/patch_loading/ \
  hyfens-server:/home/hyfen/p2-deploy-stage/experiments/patch_loading/
scp LICENSE THIRD_PARTY_NOTICES.md \
  hyfens-server:/home/hyfen/p2-deploy-stage/
```

The fixed wrapper builds the current control-plane source in an isolated
deployment directory before stopping the legacy P2-R2 service. It validates
the protected environment and Compose graph, waits for `/readyz`, and keeps a
previous current release/image for rollback. A failed build or readiness check
restores the prior service when one exists. Use the same wrapper with
`--rollback` to activate the retained previous current release. The old
P2-R2 target remains an additional migration fallback until the first current
release is healthy.

The managed Cloud installation also installs a bounded deletion worker. The
`hyfens-public-control-plane-dev-deletion.timer` invokes the existing
`processPendingDeletions` service method every 15 minutes, with a host lock to
prevent overlapping runs. The worker runs inside the current control-plane
image, uses the same protected environment and database, emits only aggregate
status counts, and is safe to resume after a restart. It is not a second queue
or a replacement for the durable deletion request records.

The same installation enables the
`hyfens-public-control-plane-dev-notification.timer`, which invokes the
bounded `--process-notifications` command every minute with a separate host
lock. It drains durable notification deliveries asynchronously using the
protected control-plane environment; it does not run from HTTP or provider
webhook requests.

The control plane is deliberately configured with customer/local signing
authority. PostgreSQL and object storage persist and deliver bytes; they never
verify or authorize runtime patches.

### Managed Cloud billing bridge

The default development stack is self-hosted and leaves Cloud billing
configuration empty. A managed Cloud deployment may opt in with
`HYFENS_DEPLOYMENT_MODEL=cloud` and the protected provider settings below:

```text
HYFENS_BILLING_PROVIDER_TOKEN_HASH
HYFENS_RAZORPAY_STARTER_PLAN_ID
HYFENS_RAZORPAY_TEAM_PLAN_ID
HYFENS_RAZORPAY_WEBHOOK_SECRET
HYFENS_RAZORPAY_CURRENCY=USD
HYFENS_RAZORPAY_STARTER_AMOUNT_MINOR=4900
HYFENS_RAZORPAY_TEAM_AMOUNT_MINOR=19900
HYFENS_DELETION_GRACE_PERIOD=7d
HYFENS_DELETION_BUSINESS_TIMEZONE=UTC
HYFENS_DELETION_HOLIDAYS=
```

`HYFENS_BILLING_PROVIDER_TOKEN_HASH` is the lowercase SHA-256 digest of the
single bearer installed as `HYFENS_BILLING_CONTROL_TOKEN` in the private Cloud
web environment. Keep both values in the deployment secret store; the bearer
is never a customer credential and the digest is never a substitute for
Razorpay signature verification. The control plane resolves the organization
from its own checkout/provider mapping and exposes only the provider bridge
operations to this principal. Do not put provider secrets or the bearer in
this repository, a committed `.env`, or a browser bundle.

For a protected installation, the deployment owner should load the bearer
through the secret manager, compute its SHA-256 digest without printing it,
install the two protected configurations, and restart the intended managed
Cloud services through their fixed wrappers. A no-secret preflight should
report only mode, presence, validated plan metadata, route reachability, and
bridge scope. A default self-hosted operator must not set these values or
expect Cloud billing routes to work.

`HYFENS_DELETION_GRACE_PERIOD` is the managed-Cloud launch policy setting and
must use working-day syntax; the approved launch value is `7d`. The verified
business date is working day 1 when it is Monday-Friday and not a configured
holiday. Day 5 sends a reminder, day 7 sends the final reminder, and the
bounded worker becomes eligible at the start of working day 8. The persisted
`processingAt` value is authoritative; it is not calculated as seven times 24
hours. `HYFENS_DELETION_BUSINESS_TIMEZONE` accepts `UTC`, `Asia/Kolkata`, or a
fixed offset such as `+05:30`. `HYFENS_DELETION_HOLIDAYS` is an optional
comma-separated `YYYY-MM-DD` list. No jurisdiction-specific holidays are
assumed when the list is empty, so the deployment owner/legal reviewer must
approve the calendar used for customer-facing dates. An empty grace value
remains valid for the default self-hosted development stack, where Cloud
deletion is not exposed.

During grace, deletion is recoverable but product mutations are rejected
server-side. Deletion status, privacy/policy information, safe billing status,
ownership resolution, and cancellation remain available. Cancellation is
allowed until the worker atomically claims `processing`; after that point the
request is irreversible. Completion is not recorded until staged active-system
erase/anonymization, retained-evidence writes, credential revocation, object
cleanup, and the organization tombstone are complete. Encrypted backups may
retain data until their normal rotation; the product must not promise instant
erasure from historical backups.

## Human CLI authentication

Set the auth variables from a protected deployment secret mechanism when human
CLI login is enabled. `HYFENS_AUTH_SIGNING_KEY` is a base64-encoded, auth-only
Ed25519 seed; it is not a Patch Format signing key. The defaults are a
15-minute access JWT and a 30-day revocable session. The public verification
key is derived from the active seed; `HYFENS_AUTH_VERIFY_KEYS` may contain
additional JSON key IDs and base64 public keys during rotation.

After an existing organization/application/environment has been bootstrapped,
provision its first owner through the supported one-shot command. Supply the
password through stdin; it is not an argument or a repository value:

```sh
printf '%s\n' 'use-a-temporary-local-value' | \
  dart run packages/control_plane/bin/control_plane.dart \
  --bootstrap-owner --password-stdin \
  --organization-id <organization-id> \
  --application-id <application-id> \
  --environment-id <environment-id> \
  --email operator@example.com --profile demo
```

The placeholder above is illustrative only. Do not copy real passwords into
README files, shell history, Compose files, or committed `.env` files. Then
use the canonical `hyfens login`; legacy opaque control/delivery variables
remain available for automation and runtime delivery compatibility.

### Seed the existing demo platform users

For the deployed demo scope, the root-only helper below provisions two
separate human accounts through the existing control-plane bootstrap seams:

- the `owner` membership is the demo **super-admin** and has the existing
  control-plane capabilities;
- the `admin` membership is the **content-admin** and is limited to
  `content:admin`.

It prompts for the scope, email addresses, and passwords. Passwords are read
through hidden stdin, passed only to the running control-plane process, and
are not written to a file or command argument. The helper accepts no options
and must be run as root on the development host after the public control-plane
development service is healthy:

```sh
/opt/hyfens/public-control-plane-dev/deploy/p2/bootstrap-platform-users.sh
```

The default scope values are the existing demo organization, application, and
environment. Review them at the prompt and do not use this helper to create a
second tenant. A repeated request for the same bootstrap claim is idempotent;
a different owner or content-admin for an already consumed claim is rejected
by the control plane.

For a separately hosted browser dashboard, set the non-secret routing values
in the protected deployment configuration:

```sh
HYFENS_API_BASE_PATH=/p2/
HYFENS_AUTH_AUTHORIZATION_ENDPOINT=https://app.hyfens.com/cli/authorize
HYFENS_AUTH_DEVICE_VERIFICATION_URI=https://app.hyfens.com/device
HYFENS_WEB_ORIGINS=https://app.hyfens.com
```

`HYFENS_WEB_ORIGINS` is an exact comma-separated allowlist; wildcard origins
are not accepted. The dashboard pages use the same human-auth authority as the
CLI. The browser approval pages are static assets in `dashboard/`; a self-host
operator must publish them over HTTPS or keep browser auth unavailable and use
    the documented local/server-owned bootstrap boundary.

For local dashboard review, the repository provides a bounded Docker fixture
that starts the local control plane and dashboard together, then seeds local human users through
the supported bootstrap seam:

```sh
sh scripts/local-dashboard.sh up
sh scripts/local-dashboard.sh credentials
open http://127.0.0.1:18083/
```

Generated local passwords and scope IDs live under
`~/.hyfens/local-dashboard/`, outside the repository. `down` does not remove
the named volumes, so local dashboard data is preserved across restarts.

### Seed the Auvana local CLI demo

For repeatable testing with real Flutter demo applications, use the repository
controlled Auvana scope. This command rebuilds the local images, configures
`admin@auvanaventures.com` as the platform profile, and idempotently creates:

- organization: `Auvana Ventures Private Limited`;
- application runtime identity: `com.auvanaventures.demo`; and
- development environment: `development`.

The generated password is stored only in the mode-`0600` file outside the
repository. Retrieve it with the second command; it is not printed by the
seeder or written to Compose/source files:

```sh
sh scripts/local-dashboard.sh demo
sh scripts/local-dashboard.sh demo-credentials
```

Use that password with the normal CLI against the local control plane:

```sh
hyfens login --host http://127.0.0.1:18082 --profile auvana-demo
hyfens status
cd /path/to/a-flutter-demo
hyfens doctor
hyfens init
hyfens release android
hyfens patch android
hyfens deploy
```

The Auvana owner is also the explicitly configured platform profile, so the
dashboard exposes its aggregate `Platform` view after login. The view is
read-only and reports counts, recent activity windows, active sessions, and
process-local service signals; it does not expose records or credentials.

Set `HYFENS_PUBLIC_CONTENT_ORGANIZATION_ID` only when this instance should
publish one organization’s released blog/news records through the unauthenticated
`/content` endpoints. Leaving it empty publishes no CMS records.

## Run

From the repository root, provide local-only credentials through the shell (do
not commit them):

```sh
export HYFENS_POSTGRES_PASSWORD='local-only-change-me'
export HYFENS_S3_ACCESS_KEY='hyfens-local'
export HYFENS_S3_SECRET_KEY='local-only-change-me-too'
docker compose -f deploy/p2/docker-compose.yml up --build
```

By default the service is exposed only on `127.0.0.1:18082`. Physical-device
testing may explicitly set `HYFENS_BIND_ADDRESS` to a private-LAN interface;
that is still a test boundary, not a public deployment. A reverse proxy must
terminate TLS, enforce its own upload/body/timeouts, set request IDs, and
forward only trusted client metadata before any non-local deployment is
considered. Use `/healthz` for liveness, `/readyz` for PostgreSQL/object-store
readiness, and `/metrics` for process-local aggregate operator measurements.

The current S3 adapter implements standard AWS Signature V4 when access and
secret keys are supplied. Bucket creation/policy bootstrap is intentionally an
operator step; no credentials are baked into the image.

## Private TLS evidence

The Dart CLI trusts the platform roots by default. For a self-hosted endpoint
using a private test or customer CA, pass that CA explicitly; the private key
never belongs in the CLI or control plane:

```sh
hyfens deploy --endpoint https://control-plane.example \
  --ca-cert /path/to/trusted-ca.pem \
  --token "$HYFENS_TOKEN" \
  ...
# or set HYFENS_TLS_CA_CERT=/path/to/trusted-ca.pem
```

The CA option is a bounded trust configuration for local/self-hosted testing;
it is not certificate pinning, public-ingress hardening, or a store-policy
determination. Rotate certificates only after testing the new chain with the
operator clients and retaining the previous recovery evidence.

## Coupled backup and restore rehearsal

Database metadata and digest-addressed object bytes are separate stores and
must be backed up and restored together. The scripts require explicit paths,
credentials, and an opt-in restore flag:

```sh
export HYFENS_OBJECT_ENDPOINT='http://object-store:9000/'
export HYFENS_S3_BUCKET='hyfens-artifacts'
export HYFENS_S3_ACCESS_KEY='local-only'
export HYFENS_S3_SECRET_KEY='local-only-change-me'
export HYFENS_S3_DOCKER_NETWORK='hyfens-p2_default'
scripts/p2-object-backup.sh /path/to/backup/objects

export HYFENS_ALLOW_RESTORE=1
scripts/p2-object-restore.sh /path/to/backup/objects
```

Use `scripts/p2-postgres-backup.sh` and
`scripts/p2-postgres-restore.sh` for the matching PostgreSQL dump. A restored
metadata row without matching bytes must remain unavailable or quarantined;
the service never regenerates signed artifacts.

## Disposable two-instance rehearsal

For provider-neutral local evidence only, the repository-controlled HA fixture
can exercise both stateless instances, the shared dependencies, passive proxy
retry, dependency-aware readiness, and a small load sample:

```sh
HYFENS_HA_EXTENDED=1 HYFENS_HA_PORT=18085 \
  scripts/p2-ha-rehearsal.sh
```

The extended fixture is not a production deployment, does not actively remove
backends from the proxy based on `/readyz`, and does not prove provider
failover, public TLS, RPO/RTO, capacity, or SLOs. See
`docs/P3E5_5F_PROVIDER_RESILIENCE_READINESS_REVIEW.md` for the evidence
boundary.

## Stop and cleanup

```sh
docker compose -f deploy/p2/docker-compose.yml down
```

Use `down -v` only for an explicitly disposable test run because it deletes the
named local PostgreSQL and object-store volumes.
