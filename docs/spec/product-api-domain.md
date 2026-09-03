# Product API and domain specification

Status: `VERSIONED DESIGN — BOUNDED LOCAL IMPLEMENTATION IN PROGRESS`

This is a versioned REST/domain contract for the control plane and runtime
delivery boundary. It specifies interface behavior and examples; it is not an
OpenAPI document. The current bounded implementation covers the authenticated release/patch/artifact,
promotion, update-check, and artifact-fetch subset in
[`packages/control_plane`](../../packages/control_plane); rollout, telemetry,
hosted identity, and managed service features remain out of scope.

Related vocabulary and tenant invariants are in
[`domain-tenancy.md`](../architecture/domain-tenancy.md). Control-plane versus
runtime authority is in [`control-plane.md`](../architecture/control-plane.md).

## 1. Version and identity boundary

The customer API is versioned at `/v1`. Breaking resource, state, or error
semantics require `/v2`; additive response fields are allowed in a minor
revision and clients must ignore unknown fields. `Accept` may use
`application/vnd.hyfens.v1+json`, but the URL version remains authoritative.

The SaaS API version is independent of Patch Format v1 and runtime
compatibility versions. Adding an Organization label, Environment policy,
Rollout assignment, audit field, or delivery header never changes Patch
Format v1 bytes, canonical sections, digest/signature input, release binding,
capability authority, or state-v4 high-water semantics.

### Resource IDs versus runtime identities

API IDs are opaque, tenant-scoped resource references such as `app_...`,
`rel_...`, and `pat_...`. Resources also carry exact runtime fields:

```text
Application.runtimeApplicationId → Patch Format v1 identity.applicationId
Release.runtimeReleaseId         → Patch Format v1 identity.releaseId
Patch.runtimePatchId             → Patch Format v1 identity.patchId
Patch.sequence                    → Patch Format v1 identity.sequence
PatchArtifact.sha256              → digest of exact artifact bytes
```

The server rejects mismatches and does not translate a Patch from one Release
to another. Package names, dependency versions, display labels, and
Environment IDs are not runtime release identity.

## 2. HTTP envelope and authentication

Every request has or receives a request ID:

```http
X-Request-Id: req_01JEXAMPLE9M4J2P8Y7Q3C6A1B5
```

The caller may supply a bounded, valid ID; otherwise the server generates one.
The response, error body, audit record, asynchronous job, and webhook event
retain the server-visible request ID.

Human and automation APIs use:

```http
Authorization: Bearer <short-lived-session-or-api-token>
```

An ApiToken is shown once, stored only as a hash, scoped to one Organization,
and revocable/expirable. A ServiceAccount token is also one-Organization and
must have explicit project/application/environment scopes. Runtime delivery
uses an application/environment delivery credential or public delivery
identifier with read/observation-only authority; it is never a control-plane
write token and must not be treated as a private secret embedded in the app.

The server establishes one tenant context from the credential and route. A
caller cannot select another Organization by changing `org_...` in a URL.
Cross-tenant IDs have the same not-found shape as unknown IDs.

### Roles and scopes

The initial role vocabulary is:

| Role | Typical authority |
| --- | --- |
| Owner | Organization membership, all product resources, key/policy ownership, and destructive operations |
| Admin | Organization/project/application/environment administration, without implicit private-key access |
| Developer | Read resources and create/register releases/patches in granted non-protected scopes |
| Release Manager | Promote releases, create/start/pause rollouts, and perform permitted rollback commands |
| Security Manager | Signing/trust policy, key rotation/revocation, approval and audit review |
| Viewer | Read-only access to granted resources and diagnostics |
| Billing Admin | Billing metadata only when a billing module exists; no artifact, runtime, or key authority |

Roles expand into least-privilege scopes such as
`release:write`, `patch:write`, `artifact:write`, `rollout:admin`,
`runtime:observe`, `signing:admin`, `audit:read`, and `access:admin`. An
EnvironmentPolicy can require a Release Manager plus Security Manager or a
two-person approval before production promotion. Authorization checks the
operation, resource ancestry, EnvironmentPolicy, and current state; a broad
role does not bypass exact release or runtime constraints.

## 3. Domain endpoints

The following are conceptual resource/command endpoints. Command endpoints
are preferred where a state transition has safety consequences; arbitrary
state mutation through a generic `PATCH` is not part of this contract.

| Operation | Method/path | Required scope | Idempotency/concurrency |
| --- | --- | --- | --- |
| Register Application | `POST /v1/organizations/{org}/projects/{project}/applications` | `application:write` | Idempotency-Key |
| Register Release | `POST /v1/organizations/{org}/applications/{app}/releases` | `release:write` | Idempotency-Key; immutable after registration |
| Create Patch | `POST /v1/organizations/{org}/releases/{rel}/patches` | `patch:write` | Idempotency-Key; exact sequence/digest conflict is 409 |
| Upload/attach Artifact | `PUT /v1/organizations/{org}/artifacts/{art}` | `artifact:write` | Digest and `If-None-Match: *` |
| Promote Release | `POST /v1/organizations/{org}/environments/{env}/release-promotions` | `release:promote` | Idempotency-Key; If-Match on Environment |
| Create/operate Rollout | `POST /v1/organizations/{org}/environments/{env}/rollouts`, then `POST .../{rollout}/start`, `/pause`, or `/stop` | `rollout:admin` | Idempotency-Key + If-Match |
| Manage keys/policies | `POST/PUT /v1/organizations/{org}/signing-keys`, `trust-policies`, or `environments/{env}/policy` | `signing:admin`/`policy:admin` | If-Match for updates |
| List/read resources | `GET /v1/organizations/{org}/...` | resource-specific `:read` | Cursor pagination |
| Ingest observations | `POST /v1/runtime/observations:batch` | delivery observation authority | Event-ID deduplication |
| Check for update/control | `POST /v1/runtime/update-check` | delivery read authority | Safe to repeat; cache/ETag |
| Fetch artifact | `GET /v1/runtime/artifacts/{art}` | scoped delivery read | ETag is digest; bytes immutable |

## 4. Register an exact Release

Request:

```http
POST /v1/organizations/org_01JEXAMPLE/applications/app_01JEXAMPLE/releases HTTP/1.1
Authorization: Bearer <release-token>
X-Request-Id: req_01JEXAMPLE9M4J2P8Y7Q3C6A1B5
Idempotency-Key: release-build-2026-08-23-android-1
Content-Type: application/json
```

```json
{
  "platform_id": "plt_01JEXAMPLEANDROID",
  "runtime_application_id": "com.acme.weather",
  "runtime_release_id": "android-arm64-release-2026-08-23-1",
  "build_target": "android-arm64-release",
  "runtime_compatibility_version": 7,
  "patch_format_version": 1,
  "build_fingerprint": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "capability_authority_digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "function_signature_digest": "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  "display_version": "4.2.0",
  "signing_key_ids": ["key_01JEXAMPLEPATCH"]
}
```

The `display_version` is informational. The server validates that the exact
runtime identity and digests are consistent with the signed baseline/artifact;
it does not derive identity from the display version.

Response:

```http
HTTP/1.1 201 Created
Location: /v1/organizations/org_01JEXAMPLE/releases/rel_01JEXAMPLERELEASE
ETag: "release-v3-9f2c"
X-Request-Id: req_01JEXAMPLE9M4J2P8Y7Q3C6A1B5
Content-Type: application/json
```

```json
{
  "id": "rel_01JEXAMPLERELEASE",
  "organization_id": "org_01JEXAMPLE",
  "application_id": "app_01JEXAMPLE",
  "platform_id": "plt_01JEXAMPLEANDROID",
  "runtime_application_id": "com.acme.weather",
  "runtime_release_id": "android-arm64-release-2026-08-23-1",
  "state": "REGISTERED",
  "patch_format_version": 1,
  "runtime_compatibility_version": 7,
  "created_at": "2026-08-23T10:00:00Z",
  "request_id": "req_01JEXAMPLE9M4J2P8Y7Q3C6A1B5"
}
```

## 5. Register and verify a PatchArtifact

Request:

```http
POST /v1/organizations/org_01JEXAMPLE/releases/rel_01JEXAMPLERELEASE/patches HTTP/1.1
Authorization: Bearer <release-token>
X-Request-Id: req_01JEXAMPLEPATCHREQUEST
Idempotency-Key: patch-android-7
Content-Type: application/json
```

```json
{
  "runtime_patch_id": "android-patch-000007",
  "sequence": 7,
  "artifact": {
    "format": "patch-format-v1",
    "sha256": "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    "size_bytes": 2069,
    "content_type": "application/octet-stream"
  },
  "signature_key_id": "key_01JEXAMPLEPATCH",
  "notes": "Fix weather refresh timeout",
  "source_revision": "git:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
}
```

The response may provide an upload reference for the exact bytes. The upload
is immutable:

```http
PUT /v1/organizations/org_01JEXAMPLE/artifacts/art_01JEXAMPLEPATCH HTTP/1.1
Authorization: Bearer <artifact-token>
If-None-Match: *
Content-Type: application/octet-stream
Digest: sha-256=<base64-of-the-declared-sha256-digest>
```

The control plane can parse and verify the artifact as an admission check,
but the runtime repeats all checks. Verification includes the fixed Patch
Format v1 canonical sections, bounds, digest/signature boundary, Ed25519
signature/key metadata, exact Application/Release/Platform, runtime/format
compatibility, function signatures, and declared capability authority. A
SaaS manifest or HTTP header is never included in the v1 byte sequence.

Registration is idempotent only for the same Release, runtime Patch ID,
sequence, digest, and key metadata. Same sequence with another digest is
`SEQUENCE_EQUIVOCATION`; a lower sequence is `STALE_SEQUENCE`.

## 6. Promote and roll out

Promotion into an Environment changes an audited product pointer; it does
not mutate a Release:

```http
POST /v1/organizations/org_01JEXAMPLE/environments/env_01JEXAMPLEPROD/release-promotions HTTP/1.1
Authorization: Bearer <release-manager-token>
If-Match: "environment-v12-1a2b"
Idempotency-Key: promote-rel-01-to-prod
Content-Type: application/json
```

```json
{
  "release_id": "rel_01JEXAMPLERELEASE",
  "reason": "Store release 4.2.0 is available",
  "approval_ids": ["aud_01JEXAMPLEAPPROVAL"]
}
```

Create a staged rollout:

```http
POST /v1/organizations/org_01JEXAMPLE/environments/env_01JEXAMPLEPROD/rollouts HTTP/1.1
Authorization: Bearer <release-manager-token>
If-Match: "environment-v13-5e6f"
Idempotency-Key: rollout-patch-7-prod
Content-Type: application/json
```

```json
{
  "patch_id": "pat_01JEXAMPLEPATCH",
  "mode": "percentage",
  "target_percent": 10,
  "cohort_id": null,
  "auto_pause": {
    "enabled": true,
    "fault_rate_threshold": 0.02,
    "rejection_rate_threshold": 0.01,
    "minimum_observations": 100
  },
  "reason": "Canary Android refresh fix"
}
```

Starting, pausing, and stopping use explicit commands with an `If-Match`
version. `PAUSED` or `EMERGENCY_STOPPED` only withholds future delivery. It
does not make a signed artifact invalid and does not select an old artifact.

## 7. Runtime update/control lookup

The runtime lookup is deliberately a small, repeatable interface. The
client's reported high-water is advisory to filtering; the runtime controller
remains authoritative.

Request:

```http
POST /v1/runtime/update-check HTTP/1.1
X-Application-Delivery-Id: delivery_app_01JEXAMPLE
X-Request-Id: req_01JEXAMPLEUPDATECHECK
Content-Type: application/json
```

```json
{
  "application_id": "app_01JEXAMPLE",
  "environment_id": "env_01JEXAMPLEPROD",
  "runtime_application_id": "com.acme.weather",
  "platform": "android-arm64-release",
  "runtime_release_id": "android-arm64-release-2026-08-23-1",
  "runtime_compatibility_version": 7,
  "patch_format_version": 1,
  "high_water": {
    "sequence": 6,
    "digest": "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  },
  "installation_id": "install_4d2b1c00-2f1e-4c66-b8af-4d7c1a2e8b90"
}
```

The server verifies the Application/Environment relationship, exact runtime
release and platform, active policy, rollout/cohort eligibility, and
candidate sequence. It returns no lower-sequence Patch:

```json
{
  "decision": "PATCH_AVAILABLE",
  "request_id": "req_01JEXAMPLEUPDATECHECK",
  "runtime_release_id": "android-arm64-release-2026-08-23-1",
  "patch": {
    "runtime_patch_id": "android-patch-000007",
    "sequence": 7,
    "sha256": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    "signature_key_id": "key_01JEXAMPLEPATCH"
  },
  "artifact": {
    "id": "art_01JEXAMPLEPATCH",
    "url": "https://distribution.example.invalid/v1/runtime/artifacts/art_01JEXAMPLEPATCH?expires=1770000000",
    "size_bytes": 2069,
    "expires_at": "2026-08-23T10:10:00Z"
  },
  "cache": {
    "etag": "\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"",
    "max_age_seconds": 60
  }
}
```

Possible decisions:

| Decision | Meaning | Runtime consequence |
| --- | --- | --- |
| `NO_UPDATE` | No eligible candidate above the supplied high-water | Continue current runtime/AOT; retry with backoff |
| `PATCH_AVAILABLE` | One exact candidate is eligible for delivery | Fetch raw bytes and run the complete runtime verifier |
| `ROLLBACK_CONTROL` | A separately signed, release-bound control message is available | Verify signer, release, and exact durable high-water; it can select base only |
| `UPDATE_BLOCKED` | Policy, rollout, key, credential, or observation condition withholds delivery | No runtime change; explain locally without treating block as runtime invalidity |
| `STORE_RELEASE_REQUIRED` | Current exact release/platform cannot accept the product candidate | Ship a normal store release; do not attempt a data Patch |

The response is a delivery hint. `ETag`, URL, cache headers, product state,
and server signature do not replace Patch Format v1 verification. A server
must not return a rollback instruction that names an older Patch as directly
installable; restoring old behavior requires the existing signed base rollback
semantics or a newly signed higher-sequence artifact.

Artifact fetch returns raw immutable bytes:

```http
GET /v1/runtime/artifacts/art_01JEXAMPLEPATCH HTTP/1.1
If-None-Match: "sha256:1111111111111111111111111111111111111111111111111111111111111111"
```

The distribution response may include `ETag`, `Digest`, `Content-Length`,
`Cache-Control: immutable`, and a request ID. A 304 is only a transport/cache
result; the runtime never treats it as proof of validity.

## 8. Observation intake

Observations are optional, bounded, deduplicated facts. They do not drive
runtime correctness:

```http
POST /v1/runtime/observations:batch HTTP/1.1
X-Application-Delivery-Id: delivery_app_01JEXAMPLE
X-Request-Id: req_01JEXAMPLEOBSERVATION
Content-Type: application/json
```

```json
{
  "installation_id": "install_4d2b1c00-2f1e-4c66-b8af-4d7c1a2e8b90",
  "events": [
    {
      "event_id": "evt_01JEXAMPLEHEALTHY",
      "type": "patch_healthy",
      "occurred_at": "2026-08-23T10:04:12Z",
      "runtime_application_id": "com.acme.weather",
      "runtime_release_id": "android-arm64-release-2026-08-23-1",
      "runtime_patch_id": "android-patch-000007",
      "sequence": 7,
      "digest": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
      "diagnostic_code": null,
      "attributes": {}
    }
  ]
}
```

The endpoint may return `accepted`, `duplicate`, or `rejected` counts. It
never changes current/LKG/high-water, marks a candidate healthy, or creates a
trust anchor. `attributes` is an allowlisted, size-bounded map; arbitrary
stack traces, source paths, patch bytes, and secrets are rejected/redacted.

## 9. Errors

Errors use one stable envelope:

```json
{
  "error": {
    "code": "PRECONDITION_FAILED",
    "message": "The resource changed after the caller read it.",
    "retryable": false,
    "field": null,
    "details": {
      "expected_etag": "\"environment-v13-5e6f\""
    }
  },
  "request_id": "req_01JEXAMPLE9M4J2P8Y7Q3C6A1B5"
}
```

Messages are safe for operators and contain no secrets, private paths, raw
patch bytes, or cross-tenant existence information. The core codes are:

| HTTP | Code | Use |
| ---: | --- | --- |
| 400 | `VALIDATION_FAILED`, `INVALID_CURSOR`, `UNSUPPORTED_API_VERSION` | Malformed or unsupported request |
| 401 | `AUTHENTICATION_REQUIRED`, `TOKEN_INVALID`, `TOKEN_EXPIRED` | Missing/invalid credential |
| 403 | `FORBIDDEN_SCOPE`, `POLICY_APPROVAL_REQUIRED`, `ENVIRONMENT_PROTECTED` | Same-tenant caller lacks effective authority |
| 404 | `NOT_FOUND` | Unknown or foreign tenant-scoped resource |
| 409 | `IDEMPOTENCY_KEY_REUSED`, `RESOURCE_CONFLICT`, `SEQUENCE_EQUIVOCATION`, `STALE_SEQUENCE`, `SIGNING_KEY_STATE_CONFLICT` | Valid request conflicts with immutable/state rules |
| 412 | `PRECONDITION_FAILED` | `If-Match`/ETag is stale or missing where required |
| 413 | `ARTIFACT_TOO_LARGE` | Artifact or event exceeds declared bound |
| 415 | `UNSUPPORTED_PATCH_FORMAT` | Artifact is not a supported Patch Format |
| 422 | `EXACT_RELEASE_MISMATCH`, `CAPABILITY_AUTHORITY_MISMATCH`, `SIGNATURE_INVALID`, `ARTIFACT_DIGEST_MISMATCH`, `ROLLOUT_BLOCKED` | Semantically invalid product operation |
| 429 | `RATE_LIMITED` | Caller or tenant exceeded a configured limit |
| 500/503 | `TEMPORARY_UNAVAILABLE`, `DISTRIBUTION_UNAVAILABLE` | Retryable control/distribution failure |

Control-plane admission errors do not replace runtime rejection diagnostics.
For example, a server may report `EXACT_RELEASE_MISMATCH`, while a runtime
that receives the bytes independently must still fail closed with its own
bounded diagnostic.

## 10. Idempotency and optimistic concurrency

Mutating `POST` commands require:

```http
Idempotency-Key: <caller-generated-key>
```

The key is scoped to Organization, principal, route, and a canonical request
body hash. Repeating the same key/body returns the original status and body;
reusing it with a different body returns `409 IDEMPOTENCY_KEY_REUSED`. The
retention window is a deployment policy with a documented minimum of 24 hours
for release, patch, artifact, rollout, and key commands. Event IDs provide
the equivalent deduplication for observations. For secret-producing credential
and invitation commands, a successful replay returns
`409 ONE_TIME_SECRET_UNAVAILABLE`: the operation is not repeated, and the
plaintext secret/bearer link is never persisted or replayed.

Resources expose strong ETags derived from their canonical version. Commands
that can change delivery, trust, policy, or environment state require:

```http
If-Match: "environment-v13-5e6f"
```

Missing/stale ETags fail with 412; semantic conflicts that are not solved by
the ETag fail with 409. There is no last-write-wins update for signing keys,
high-impact EnvironmentPolicy, release promotion, or Rollout operation.

## 11. Pagination and server filtering

Collection endpoints use opaque cursor pagination:

```http
GET /v1/organizations/org_01JEXAMPLE/releases?state=READY&platform_id=plt_01JEXAMPLEANDROID&limit=25
```

```json
{
  "items": [],
  "next_cursor": "cur_v1_opaque_tenant_bound",
  "has_more": true,
  "request_id": "req_01JEXAMPLELIST"
}
```

The default page size is 25 and the maximum is 100. Cursors are opaque,
short-lived or revocable, and bound to tenant, principal authorization,
filter set, and stable sort (`created_at` then ID). An altered or foreign
cursor is `INVALID_CURSOR`. Offset pagination is not used for mutable rollout,
observation, or audit streams.

Filtering uses an allowlist, for example:

```text
state=READY
platform_id=plt_...
environment_id=env_...
runtime_release_id=...
sequence_gte=7
created_after=2026-08-01T00:00:00Z
```

Tenant and authorization predicates are applied before filtering, counting,
sorting, and pagination. The API does not support arbitrary field paths or a
filter that joins through a caller-supplied foreign tenant. A server may
return fewer records because of scope, but never leaks cross-tenant counts,
cursor positions, aggregate health, or existence through filtering.

## 12. Rate limits, retries, and offline behavior

Limits are configured per deployment and exposed on responses:

```http
RateLimit-Limit: 120
RateLimit-Remaining: 0
RateLimit-Reset: 1770000060
Retry-After: 30
```

The initial design profile is 600 read requests/minute per token, 120
mutating requests/minute per Organization, 60 update checks/minute per
Installation, and a separately budgeted Environment aggregate. These are
starting policy values, not measured capacity or an availability claim.

`429` is returned before expensive artifact work and includes a retry hint.
Clients use bounded exponential backoff with jitter; they do not spin on a
failed endpoint. A control-plane outage, rate limit, or telemetry opt-out
does not prevent the application from running its compiled AOT code, current
runtime, or last-known-good recovery path.

## 13. Webhooks

Webhooks are tenant-scoped notifications, not commands. Initial event types
are:

```text
patch.ready
rollout.changed
runtime.fault_threshold
rollback.applied
signing_key.rotated
store_release_required
```

A delivery envelope is JSON with a stable event ID and resource references:

```json
{
  "id": "wh_evt_01JEXAMPLE",
  "type": "rollout.changed",
  "version": "1",
  "occurred_at": "2026-08-23T10:05:00Z",
  "organization_id": "org_01JEXAMPLE",
  "request_id": "req_01JEXAMPLEROLLOUT",
  "data": {
    "rollout_id": "rol_01JEXAMPLEROLLOUT",
    "environment_id": "env_01JEXAMPLEPROD",
    "state": "PAUSED",
    "reason": "runtime_fault_threshold"
  }
}
```

The sender includes:

```http
X-Hyfens-Webhook-Id: wh_evt_01JEXAMPLE
X-Hyfens-Webhook-Timestamp: 1770000300
X-Hyfens-Signature: v1,t=1770000300,sha256=<HMAC-SHA256(timestamp + "\\n" + raw-body)>
```

Receivers reject timestamps outside a bounded replay window and deduplicate
event IDs. The sender retries with exponential backoff and a bounded attempt
count; a dead-letter state is visible in the Webhook resource. Delivery
failure never blocks runtime delivery or marks a Patch unhealthy. Endpoint
URLs are validated against an explicit allowlist, DNS/IP rebinding is checked,
and private/link-local destinations are blocked to reduce SSRF risk.

## 14. API invariants that must remain true

- The control plane never lowers or resets the runtime high-water.
- A server response never makes a wrong-release, wrong-signature, stale, or
  capability-incompatible artifact valid.
- `ROLLBACK_CONTROL` is for a separately signed, release-bound control message
  and exact high-water; it is not an old-Patch selector.
- Environment, rollout, cohort, audit, tenant, and source metadata remain
  outside Patch Format v1 bytes.
- Runtime observations are optional and non-authoritative.
- API major-version evolution cannot silently change the Patch Format v1
  digest/signature boundary or capability v1 contract.
