# Artifact distribution and trust architecture

Status: Task 40 design-only proposal. No hosted service, CDN integration,
signing provider, or runtime delivery implementation is authorized by this
document.

This package defines how a signed Patch Format v1 artifact can move from a
developer or CI signing boundary to a Flutter runtime without making a
control plane, CDN, self-hosted server, or offline transfer package a new
runtime trust root.

## Decision summary

- Patch bytes are immutable and content-addressed by the SHA-256 digest of
  the exact bytes that the runtime will verify. A mutable database record or
  URL can point at an artifact; it cannot change the artifact at that digest.
- Release identity, patch sequence, signature metadata, capability table, and
  canonical digest remain governed by Patch Format v1 and the release-owned
  runtime authority. SaaS metadata is kept outside the patch container.
- Distribution is cryptographically untrusted. HTTPS, authentication, signed
  URLs, object-store ACLs, CDN configuration, and an air-gap transfer process
  reduce tampering and disclosure risk but never replace runtime verification.
- The control plane decides eligibility and records operator intent. It may
  withhold an offer or return `STORE_RELEASE_REQUIRED`; it cannot make an
  incompatible, stale, unsigned, or capability-invalid artifact valid.
- A hosted outage, CDN outage, self-host misconfiguration, or offline period
  leaves the installed runtime on its current verified state, last-known-good
  state, or compiled AOT base. Network availability is not a correctness
  dependency.

## Trust and ownership boundaries

```text
developer source / CI
        │ build and analyze
        ▼
release + patch compiler ──▶ signing boundary ──▶ immutable artifact store
                                      │                    │
                                      │                    ├─ CDN / private CDN
                                      │                    ├─ self-hosted HTTP
                                      │                    └─ offline transfer
                                      ▼                    │
                                control plane ── eligibility / rollout metadata
                                      │                    │
                                      └──── runtime lookup and artifact fetch
                                                           ▼
                              Flutter runtime state-v4 controller
                              signature → exact release → capabilities
                              → high-water/replay → candidate/health/fallback
```

| Layer | It may decide or provide | It may not become authoritative for |
| --- | --- | --- |
| Compiler/CLI/CI | Build a release baseline and deterministic patch bytes | Runtime acceptance; a build result is not trusted merely because CI produced it |
| Signing boundary | Authenticate a release-bound artifact or signed control | Semantic safety, store approval, or a lower sequence |
| Control plane | Register metadata, select an eligible rollout, issue a delivery hint, audit operator actions | Signature validity, exact release compatibility, capability authority, high-water, or runtime health |
| Object store/CDN/self-host endpoint | Return bytes and cache them | Artifact identity; a URL, ETag, TLS session, or ACL is not a signature |
| Offline transfer medium | Carry an export/import bundle | Freshness, release binding, or key trust |
| Flutter runtime | Verify, stage, activate, health-confirm, roll back, and fail closed | None; it remains the final authority for downloaded execution |

The runtime's frozen authority is the shipped release and its state-v4
controller. It retains Architecture B's AOT fallback, bounded interpreted
dispatch, exact application/release binding, signed rollback, closed
capability v1 registry, monotonic `(sequence, digest)` high-water, remembered
artifact identities, and fail-closed recovery. No product layer may lower or
reset that high-water, add a capability, or select an old artifact by changing
a server record.

## Canonical artifact and metadata model

The design distinguishes identity fields that are easy to conflate:

| Object | Identity | Mutable? | Runtime significance |
| --- | --- | --- | --- |
| Store release baseline | Exact release ID plus build/runtime compatibility records | No after registration | The required application/release binding for patches |
| Patch artifact | `sha256` of the exact canonical Patch Format v1 bytes | Bytes are never mutable; availability may change | The only downloaded executable input |
| Patch ID | Product-visible identifier inside the signed identity section | No | Diagnostic and operator identity; not a substitute for the byte digest |
| Artifact reference | `sha256/<lowercase-digest>` plus size and media type | A pointer can be copied or withdrawn | Transport locator only; the runtime recomputes the digest |
| Rollout record | Release/patch, environment, cohort policy, and eligibility | Yes, append-only changes | Server-side delivery policy only |
| Signed rollback control | Separate canonical signed control message | Each message is immutable | Runtime may accept it only for its exact release and durable high-water |
| Key-lifecycle command | Separate signed trust transition | Each message is immutable | Runtime state-v4 trust journal decides whether it applies |
| Debug/source-map bundle | Separate, access-controlled, optional artifact | Retention may expire | Diagnostics only; never sent to or trusted by the runtime |

The artifact digest is computed over the exact bytes delivered to the runtime,
including the Patch Format v1 signature section. A digest mismatch, truncated
body, unexpected content type, duplicate/alternate encoding, or failed
canonical/signature check is a hard rejection. A content-addressed key is not
a permission grant and does not make an object safe to parse.

The product may keep a release manifest and rollout metadata in a database or
object store, but those records are not appended to Patch Format v1. Runtime
metadata needed for acceptance is already covered by the release-bound
artifact, the shipped capability authority, or the existing signed control
protocol. This avoids making a hosted schema part of the frozen patch format.

A conceptual object namespace is:

```text
<opaque-tenant>/<opaque-application>/<release-id>/artifacts/sha256/<digest>
<opaque-tenant>/<opaque-application>/<release-id>/controls/sha256/<digest>
<opaque-tenant>/<opaque-application>/<release-id>/debug/<bundle-id>
```

The namespace is a storage and authorization aid, not a security boundary.
Every object access still checks tenant/application/environment scope where
applicable, and the runtime verifies the bytes independently. Artifact names
must not contain source paths, private keys, user identifiers, or secrets.

## Distribution topologies

All topologies implement the same abstract operations: register an immutable
artifact, look up an eligible update, fetch bytes by digest, fetch a signed
control when one is eligible, and optionally submit observations.

| Topology | Intended use | Benefits | Required trust posture |
| --- | --- | --- | --- |
| Object storage plus CDN | Managed cloud and public OSS distribution | High cacheability and geographic delivery | Cache is an untrusted byte source; use digest-addressed objects, immutable cache headers, TLS, origin access control, and runtime verification |
| Authenticated update endpoint plus object storage | Small deployments or private applications | Lookup authorization and tenant policy stay together | Authentication controls who receives a hint, not whether the artifact is valid; artifact fetch may use a short-lived signed URL |
| Self-hosted HTTP/object storage | Community, on-prem, and private-network deployments | Customer controls data, keys, network, and retention | Secure defaults, customer TLS, scoped service credentials, object immutability, backups, and an explicit operator threat model are required |
| Private enterprise CDN | Restricted networks with existing edge infrastructure | Fits customer egress and locality controls | CDN configuration is customer-controlled and remains untrusted; origin and runtime digest/signature checks still apply |
| Air-gapped transfer | Offline production networks | No runtime-to-cloud dependency | Build and sign outside or inside the gap, export an inventory plus exact bytes, verify at import, record the import, and retain replay/high-water state |

CDN invalidation or object deletion is an availability and distribution action,
not revocation at the runtime. To stop a bad artifact, pause eligibility,
revoke the relevant signing key/artifact through the release-owned trust
process, or deliver an authorized signed rollback control. A cache may serve a
stale response; the runtime must reject stale or revoked material and never
lower high-water.

### Air-gap transfer contract

An air-gap export is a transport bundle, not a new patch format. It contains
an inventory of exact artifact/control digests and sizes, release/application
identities, the intended environment, export timestamp, transfer bundle ID,
and the original signed bytes. The inventory is signed by the selected offline
workflow or accompanied by signatures already required by the artifacts. The
receiving operator verifies:

1. the transfer inventory and expected tenant/application/release scope;
2. every byte's digest, size, and canonical encoding;
3. the normal Patch Format v1 signature, exact release, runtime, function, and
   capability checks at activation;
4. key status, sequence/high-water, and replay metadata before publication;
5. malware/scanning and import audit requirements defined by the customer.

An import must be idempotent. Re-importing the same digest is harmless;
re-importing an old sequence cannot reopen it; an equal sequence with a
different digest is equivocation. The bundle cannot carry a private key or
replace the release-embedded recovery anchor. A disconnected runtime may
continue using its last verified state indefinitely; observations and rollout
decisions are deferred rather than required for execution.

## Runtime delivery API interaction

The following is a conceptual versioned REST/domain interface. It defines the
trust boundary, not a server contract or implementation plan.

### Update lookup

```http
POST /v1/runtime/update-check
Content-Type: application/json
Authorization: Bearer <scoped-runtime-token>
```

```json
{
  "applicationId": "app_opaque",
  "releaseId": "rel_exact",
  "environment": "production",
  "platformTarget": "android-arm64-release",
  "runtimeVersion": 1,
  "current": {"sequence": 2, "digest": "sha256:..."},
  "highWater": {"sequence": 2, "digest": "sha256:..."},
  "installationToken": "random-installation-token-or-null"
}
```

`releaseId` and `highWater` are not hints that the server may rewrite. They
allow the server to avoid offering obviously inapplicable material and to
choose a rollout cohort. The runtime still evaluates its own durable state.
The installation token is optional, random, app-scoped, and pseudonymous; it
is never an IMEI, advertising ID, hardware serial, phone number, account ID,
or a requirement for correctness.

The response has exactly one decision and may contain no executable bytes:

```json
{
  "decision": "PATCH_AVAILABLE",
  "releaseId": "rel_exact",
  "sequence": 3,
  "artifact": {
    "digest": "sha256:...",
    "size": 2069,
    "mediaType": "application/vnd.hyfens.patch.v1",
    "url": "https://distribution.example/sha256/...",
    "etag": "\"sha256:...\""
  },
  "expiresAt": "2026-08-23T12:00:00Z",
  "retryAfterSeconds": 3600
}
```

Supported decisions are:

| Decision | Runtime behavior |
| --- | --- |
| `NO_UPDATE` | Keep the current verified state; a cacheable response may be used until its expiry |
| `PATCH_AVAILABLE` | Fetch by digest, then run the existing bounded verification, exact-release/capability, high-water, staging, health, and fallback path |
| `ROLLBACK_CONTROL` | Fetch the separate canonical signed control; accept only if the runtime's trusted key, release, and exact durable high-water match |
| `UPDATE_BLOCKED` | Do not retry aggressively; retain current/base state and emit an optional bounded reason code |
| `STORE_RELEASE_REQUIRED` | Do not deliver interpreted behavior; require a normal store release and policy review |

### Artifact and control fetch

```http
GET /v1/artifacts/sha256/<lowercase-digest>
If-None-Match: "sha256:<digest>"
```

An `ETag`, `Content-Length`, TLS session, or signed URL only assists transport
and caching. The runtime compares the received bytes with the requested
digest, then applies the existing Patch Format v1 verifier and controller.
`304 Not Modified` means only that a cached byte may be reused; cached bytes
are reverified before staging. Range requests, retries, and decompression must
reconstruct exactly the addressed bytes or fail closed.

```http
GET /v1/runtime/controls/sha256/<control-digest>
```

The control endpoint returns a signed rollback/key-lifecycle control message
whose canonical bytes are independently verified. A server cannot turn an
ordinary JSON field such as `rollback: true` into a runtime authority.

Lookup and fetch are idempotent. Timeouts, offline mode, authentication
failure, `404`, `429`, and `5xx` responses leave the installed state unchanged
and use bounded retry/backoff. A malformed response is treated as no update
plus a diagnostic, not as permission to guess. The server must never answer
with a sequence below the supplied high-water as an actionable update; if it
does, the runtime still rejects it as stale.

## Operational and data boundaries

- Control-plane audit records may be required for operator, key, rollout, and
  policy changes. Runtime observations are optional and do not replace audit.
- Debug/source maps are separate, short-lived, access-controlled material and
  are never part of the runtime fetch path.
- Runtime delivery credentials are scoped to lookup/fetch/observation actions;
  they cannot sign artifacts, alter trust roots, read other tenants, or
  authorize a rollback.
- A managed signing choice, if offered, is explicit. The hosted control plane
  must not receive developer or organization private keys in the default
  local, CI-external, self-hosted, or air-gapped flows.
- No provider integration is implied by naming KMS, HSM, object storage, CDN,
  or signed URLs. Provider adapters, operational credentials, and deployment
  hardening are future implementation work.

## Phase 1D evidence boundary

This design carries the following limitations forward; distribution design is
not evidence that any one limitation has been closed.

| Phase 1D limitation | Package disposition |
| --- | --- |
| True physical power-loss interruption was not tested | **BLOCKER BEFORE PRODUCTION** for a production durability claim; process/restart evidence is not power-loss evidence |
| Direct physical runtime rejection of supplied stale valid bytes was not proven; only delivery-boundary withholding was observed | **BLOCKER BEFORE BETA** for a device-injection safety claim; server withholding cannot substitute for direct runtime evidence |
| iOS runtime logs/UI and performance were unavailable because the Developer Disk Image was unavailable | **BLOCKER BEFORE IOS BETA** for an iOS runtime-observability or performance claim |
| No fresh Phase 1D Android 15-sample reducer series was run | **BLOCKER BEFORE PRODUCTION** for a new Android performance/SLO claim; the Phase 1C baseline remains the authority |
| Flutter 3.47.1/Dart 3.13.1 adjacent-family path is `SUPPORTED_WITH_LIMITATIONS` and full CLI/device isolation is incomplete | **ACCEPTED LIMITATION** for design; support claims require an explicit compatibility gate before release |
| Independent customer-application validation was not run | **BLOCKER BEFORE BETA** for a broad customer compatibility claim |
| The additional async benchmark was not run | **BLOCKER BEFORE BETA** for an async performance claim; bounded async correctness evidence remains narrower |

These dispositions are gates for later implementation and release review, not
claims about the current local prototype. Store-policy review remains a
separate gate: secure delivery, signatures, and runtime correctness do not
establish Apple or Google approval for downloaded interpreted behavior.

## Non-goals

This document does not implement a server, CDN, object-store adapter, runtime
network client, authentication provider, KMS/HSM provider, air-gap importer,
telemetry pipeline, or policy/compliance approval.
