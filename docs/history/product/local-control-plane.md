# Local control-plane reference

Status: `TASK 41 COMPLETED — BOUNDED LOCAL ONLY; MAINTAINER REVIEW`

The approved first product slice is a self-hostable, single-node Dart service.
It is deliberately separate from the unauthenticated development `tool serve`
command and does not change the Flutter runtime or Patch Format v1.

## Run locally

From the repository root:

```sh
cd packages/control_plane
dart pub get
dart run bin/control_plane.dart \
  --root .hyfens-control-plane \
  --bootstrap \
  --host 127.0.0.1 \
  --port 18081
```

Bootstrap prints the organization, application, environment, control token,
and read-only delivery token once to the local terminal. The service stores
only credential hashes. Do not put the printed tokens in a repository,
`tool.yaml`, audit metadata, or an application artifact.

The server implements the bounded `/v1` subset:

- authenticated release registration;
- authenticated patch metadata registration;
- exact signed Patch Format v1 artifact upload;
- all-or-none environment promotion with `If-Match`/version checks;
- read-only runtime update lookup;
- read-only immutable artifact fetch;
- content-addressed filesystem bytes and redacted append-only audit.

## Trust boundary

The service stores public signing metadata and exact already-signed bytes. It
never receives or generates private patch-signing keys. The runtime remains
authoritative for format parsing, digest/signature verification, exact release
binding, capabilities, sequence/high-water, health, rollback, and fallback.
Service availability or a service response cannot make invalid bytes valid.

## CLI deploy

`tool deploy` uploads one exact locally verified artifact. It requires an
endpoint, organization/application/environment IDs, and a control token either
as flags or as `HYFENS_*` environment variables. Credentials are used only for
the request and are never written to disk:

```sh
HYFENS_CONTROL_PLANE_URL=http://127.0.0.1:18081 \
HYFENS_CONTROL_TOKEN='(local token)' \
HYFENS_ORGANIZATION_ID=org_... \
HYFENS_APPLICATION_ID=app_... \
HYFENS_ENVIRONMENT_ID=env_... \
dart run cli/bin/tool.dart deploy \
  --release <release-id> \
  --patch .tool/patches/<release-id>/000001.patch
```

The command verifies the patch against the local release before making any
network request, then registers immutable metadata, uploads the exact bytes,
and promotes the environment with an optimistic version precondition.

## Local operator overview

Task 95 adds a bounded, authenticated, read-only organization overview at:

```text
GET /v1/organizations/{organization_id}/overview
```

It uses an existing organization-scoped control credential and requires the
existing `application:read`, `release:read`, `patch:read`, `artifact:read`,
`rollout:read`, and `audit:read` scopes. It returns capped deterministic
metadata for the organization, applications, environments, releases, patches,
artifacts, rollouts, and audit records. It never returns credential tokens or
hashes, private keys, artifact bytes, or runtime health claims. This is a
machine-credential local operator path, not human sessions or RBAC.

The static page and its stdlib-only same-origin local proxy are in
[`dashboard/`](../../../dashboard). Run `python3 dashboard/serve.py --help` for
the exact local options. The proxy forwards only the overview GET route and
does not add CORS, mutation controls, or online hosting behavior.

## Explicit limitations

This is not a managed cloud, CDN, hosted or human/RBAC dashboard, rollout,
telemetry, billing, enterprise, KMS/HSM, SSO/SCIM, or production deployment
implementation. The
P1D-02 direct physical stale-byte gate now has Android and iOS fixture
evidence in the Task 42 follow-up. This remains bounded device evidence, not
a cross-platform beta or store-compliance claim.

## Executed local evidence (historical host checkpoint)

On 2026-08-23, a temporary local service was bootstrapped, and the existing
signed Flutter fixture artifact was deployed with `tool deploy`. The service
registered the exact release and patch, verified the Ed25519 signature and
Patch Format v1 identity, stored the artifact by digest, promoted the
environment, returned `PATCH_AVAILABLE` to a scoped delivery request, and
returned 2,069 bytes whose digest and contents matched the local patch file.
The control/delivery tokens and temporary storage path are intentionally not
recorded here. This was the original `END_TO_END_LOCAL` checkpoint; its
physical-runtime limitation is preserved historically below.

## Task 42 runtime-delivery evidence (2026-08-23)

The existing Flutter integration now has a bounded authenticated lookup/fetch
adapter. It sends the application/environment delivery scope, exact runtime
release, platform, runtime/format versions, and current high-water; it fetches
the immutable artifact with the same read-only credential; and it hands exact
bytes to E1. It does not parse Patch Format v1, verify signatures, authorize
capabilities, decide high-water, mark health, or roll back.

`packages/flutter_integration` host tests and the real CLI → local
`packages/control_plane` → E1 test passed for authenticated lookup/fetch,
wrong release/platform responses, truncation/digest/timeout/connection
failures, activation, health, rollback, and service outage retention. The
delivery credential was not present in release metadata or the recorded build
command (the command records `<redacted>`).

A generated stock Flutter iOS Release IPA was built with team `CYT7A4VAZ3`,
installed once on the physical iPhone `00008020-001528860E03002E`, and launched
with XcodeBuildMCP. The ordinary fixture function changed from price `540` to
`450` after the service promoted a signed patch; the receipt remained `450`
after process restart and after the local service process was stopped. The
IPA contained arm64 Runner/App.framework binaries and no JIT artifact. The
runtime delivery URL used the Mac private-LAN address because `iproxy` is a
host-to-device tunnel rather than a reverse device-to-host tunnel; installation
and device control remained USB-based.

The direct iOS USB evidence run
`fixtures/flutter_conformance_app/.dart_tool/e1_ios_cross_runs/ios-task42-usb-20260823-r2/evidence/`
also received the exact old sequence-4 signed bytes after rollback and
recorded `replayAfterRollback`, BASE mode, and high-water `4`; invalid-signature
rejection, rollback, and restart persistence passed in the same run.

The physical Android authenticated sequence was then run on the explicit Wi-Fi
device `192.168.50.135:38657` (Redmi Note 10 Lite, Android 16/API 36). The
generated stock Flutter arm64 Release APK was installed once for the final
sequence; an authenticated 2,069-byte signed patch changed the receipt
`540→450`, survived process restart, and remained active after the local
control-plane process was stopped. Package install timestamps did not change.
The direct Android cross-feature run also passed invalid-signature rejection,
signed rollback, exact stale-byte rejection, and rollback persistence. The
redacted record is `docs/research/evidence/task42-android-control-plane.md`.

## Current bounded P0/P1 state

Task 41 is complete for this local/self-hosted slice. `PHYSICAL ANDROID` and
`PHYSICAL IOS` evidence demonstrates authenticated lookup/fetch, runtime
verification, activation, restart persistence, service-outage retention,
rollback/high-water, and direct stale-byte rejection on the declared fixtures.
P1D-02 is closed for those fixtures; P1D-13 is satisfied for the bounded
local/self-hosted contract. Power-loss, production availability, hosted key
custody/rotation, independent customer applications, performance, and
store-policy review remain open. No P2/cloud work is authorized here.

## P2 managed-cloud foundation boundary

The separately authorized P2 slice adds a PostgreSQL metadata adapter,
S3-compatible immutable object adapter, containerized Compose reference,
readiness/liveness/aggregate metrics, and operator backup/restore scripts.
Those files live under [`packages/control_plane`](../../../packages/control_plane),
[`deploy/p2`](../../../deploy/p2), and [`scripts`](../../../scripts). The
filesystem adapter and local CLI remain supported. P2 hosted-like evidence is
recorded in
[`docs/research/evidence/p2-hosted-like-2026-08-23.md`](../../research/evidence/p2-hosted-like-2026-08-23.md)
and is explicitly not production or store-compliance evidence.
