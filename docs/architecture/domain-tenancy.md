# Domain and tenancy model

Status: `DESIGN ONLY — NO PRODUCTION IMPLEMENTATION`

This document defines the control-plane vocabulary and the hard tenant
boundary. It does not change the Flutter runtime, Patch Format v1, capability
contract v1, or the controller-owned state-v4 lifecycle.

## 1. Domain boundary

An **Organization** is the customer tenant. Every customer-owned object is
owned by exactly one Organization, directly or through an immutable parent
chain. A **User** is a global identity that may have memberships in multiple
Organizations; being the same human does not make data shared between those
tenants.

The control plane has three different kinds of identity:

1. An API resource ID identifies a control-plane record.
2. A runtime identity is the exact immutable value placed in Patch Format v1
   identity and compatibility records.
3. An artifact digest identifies exact bytes.

These values are stored separately. An API rename, display label, package
name, environment label, or rollout assignment never rewrites a runtime
identity or artifact.

## 2. IDs and identity rules

API resource IDs are opaque, URL-safe, lowercase IDs with a type prefix and a
random, non-sequential payload. The prefix is for diagnostics only; it is not
an authorization decision. An ID by itself is never accepted as proof that a
caller may read or mutate a resource.

| Resource | API ID | Owning scope | Important immutable identity |
| --- | --- | --- | --- |
| User | `usr_...` | Global identity service | Provider subject and canonical user ID |
| Organization | `org_...` | Tenant root | Organization ID |
| Team | `team_...` | Organization | Organization ID and team ID |
| Project | `prj_...` | Organization | Project ID |
| Application | `app_...` | Organization, optionally grouped by Project | `runtimeApplicationId` sent as Patch Format v1 `applicationId` |
| Platform | `plt_...` | Application | Canonical platform/build target, such as `android-arm64-release` |
| Environment | `env_...` | Application | Stable environment key and delivery scope |
| Release | `rel_...` | Application and Platform | `runtimeReleaseId` sent as Patch Format v1 `releaseId` |
| Patch | `pat_...` | Release | `runtimePatchId` sent as Patch Format v1 `patchId`, plus positive sequence |
| PatchArtifact | `art_...` | Patch | Exact lowercase SHA-256 digest of artifact bytes |
| SigningKey | `key_...` | Organization | Protocol key ID, public key bytes, and role set |
| TrustPolicy | `trp_...` | Organization, Application, or Environment | Policy revision and referenced key IDs |
| Rollout | `rol_...` | Environment | Rollout ID and target Patch/rollback command |
| Cohort | `coh_...` | Rollout | Stable selector and assignment version |
| Installation | `ins_...` | Application and Environment | Random app-scoped installation identity |
| RuntimeObservation | `obs_...` | Installation and tenant | Event ID, event time, and observation payload |
| Diagnostic | `diag_...` | Tenant and resource context | Stable diagnostic code and occurrence ID |
| AuditEvent | `aud_...` | Organization | Append-only event ID and sequence/time ordering |
| ApiToken | `tok_...` | One User or ServiceAccount in one Organization | Token ID; secret is shown once and never stored plaintext |
| ServiceAccount | `svc_...` | Organization | Service-account ID and immutable owning Organization |
| Webhook | `wh_...` | Organization | Endpoint ID and subscription revision |
| EnvironmentPolicy | `pol_...` | Environment | Policy revision and effective version |

`runtimeApplicationId`, `runtimeReleaseId`, and `runtimePatchId` are opaque
to the control plane but must be stable and byte-for-byte equal to the values
in the artifact. Existing local values such as reverse-DNS application IDs or
human-readable release IDs remain valid runtime identities; they do not need
to look like API IDs. A control-plane record may expose both forms.

The Patch Format v1 identity and compatibility rules remain normative:

- a patch targets one exact application/release pair;
- release identity is derived from the normalized source/dependency
  fingerprints, runtime compatibility, application ID, and explicit build
  target; package names, dependency versions, and labels are not substitutes;
- `sequence` is positive and monotonic for a release, and the artifact digest
  identifies the exact signed bytes;
- the server rejects a registration whose declared runtime identity,
  capability-authority digest, format/runtime version, or target does not
  match the supplied artifact; it never rewrites the artifact to fit a
  different Release.

## 3. Ownership and relationships

The aggregate shape is:

```text
User ── membership/role ──> Organization
                              ├── Team ── membership ──> User
                              ├── Project ──> Application
                              ├── Application ──> Platform
                              │              └── Environment ──> EnvironmentPolicy
                              │                    ├── Rollout ──> Cohort
                              │                    └── Installation ──> RuntimeObservation
                              ├── Release ──> Patch ──> PatchArtifact
                              ├── SigningKey ──> TrustPolicy
                              ├── ServiceAccount ──> ApiToken
                              ├── Webhook
                              └── AuditEvent / Diagnostic
```

The following rules make the relationships unambiguous:

- An Organization owns Projects, Applications, keys, policies, access
  principals, observations, diagnostics, audit data, and delivery metadata.
- A User can belong to many Organizations with different roles. A Team is an
  Organization-scoped group used for grants; it does not become the owner of
  an Application or allow a resource to cross Organizations.
- A Project is an organizational grouping. An Application has one Project
  parent at a time, or no Project, but is still owned by the Organization.
  Moving it within the Organization is an audited relationship change.
- An Application owns its Platforms and Environments. A Platform describes a
  target such as `android-arm64-release`; it is not a second tenant.
- A Release is an immutable AOT baseline for one Application and Platform. It
  is registered once and may be enabled or promoted into one or more
  Environments only after the target and TrustPolicy match. Environment
  promotion is a control-plane relationship, not a Patch Format v1 field.
- A Patch belongs to exactly one Release. A runtime PatchArtifact is the exact
  Patch Format v1 byte sequence for that target. Optional debug or source-map
  bundles are separate artifacts and never alter the runtime artifact digest.
- A SigningKey is Organization-owned metadata plus public key material or a
  managed-provider reference. A TrustPolicy selects which keys and approval
  modes may be used for a product operation; it cannot inject a new runtime
  trust anchor.
- A Rollout belongs to one Environment and targets one READY Patch or one
  separately signed rollback-control operation. A Cohort is a named,
  versioned eligibility rule within that Rollout; it is not a list of hardware
  identifiers.
- An Installation is a pseudonymous observation subject, not a user account
  and not a remotely controllable runtime. It belongs to an Application and
  Environment. Runtime observations and Diagnostics are tenant-scoped facts
  derived from it, not runtime authority.
- AuditEvent is append-only and records the actor, tenant, resource, request
  ID, and outcome for security-relevant changes. It is never used as the
  source of truth for runtime activation.
- ApiToken is owned by one User or ServiceAccount and one Organization. A
  ServiceAccount is also owned by one Organization and has explicit resource
  scopes. A Webhook is owned by one Organization and can subscribe only to
  that Organization's events.
- EnvironmentPolicy is the effective policy for an Environment. It may
  require approvals, restrict platforms/keys, set rollout safety thresholds,
  and control optional telemetry; it cannot change runtime capabilities or
  lower a runtime high-water.

## 4. Resource lifecycle

These are product/catalog states. They describe control-plane intent and
administrative history, not what any particular application process is
executing.

| Resource | Product lifecycle |
| --- | --- |
| User | `ACTIVE` → `SUSPENDED` → `DELETED` (membership and audit retention follow policy) |
| Organization | `PROVISIONING` → `ACTIVE` → `SUSPENDED` → `ARCHIVED` |
| Team/Project/Application/Platform/Environment | `ACTIVE` ↔ `PAUSED` → `ARCHIVED`; child resources cannot be created under an archived parent |
| Release | `DRAFT` → `REGISTERED` → `VERIFIED` → `READY` → `DEPRECATED` or `REVOKED`; verification failure is recorded as `FAILED` |
| Patch | `DRAFT` → `BUILT` → `SIGNED` → `VERIFIED` → `READY` → `ROLLOUT_PENDING` → `ACTIVE` → `COMPLETED`, `SUPERSEDED`, `REVOKED`, `ROLLED_BACK`, or `FAILED` |
| PatchArtifact | `UPLOADING` → `AVAILABLE` → `RETIRED`; digest/signature failure moves it to `QUARANTINED` |
| SigningKey | `PENDING` → `ACTIVE` → `RETIRED` or `REVOKED`; retirement permits only exact remembered artifacts where the runtime policy allows it |
| TrustPolicy/EnvironmentPolicy | `DRAFT` → `ACTIVE` → `SUPERSEDED` |
| Rollout | `DRAFT` → `SCHEDULED` → `RUNNING` → `PAUSED`, `COMPLETED`, `CANCELLED`, `EMERGENCY_STOPPED`, or `FAILED` |
| Cohort | `DRAFT` → `ACTIVE` → `RETIRED` |
| Installation | `SEEN` → `STALE` or `REVOKED`; retention may purge its observations without changing runtime behavior |
| RuntimeObservation | `RECEIVED` → `REDACTED` or `EXPIRED`; immutable event data is never corrected in place |
| Diagnostic | `OPEN` → `ACKNOWLEDGED` → `RESOLVED` or `EXPIRED` |
| AuditEvent | Append-only; retention/export may create a tombstone or archival record, never an in-place edit |
| ApiToken/ServiceAccount | `ACTIVE` → `EXPIRED`, `SUSPENDED`, or `REVOKED` |
| Webhook | `PENDING` → `ACTIVE` → `DISABLED` or `FAILED` |

The runtime states are deliberately a different vocabulary. The controller
owns `BASE`, `CANDIDATE`, `CURRENT`, and `FAILED`; `lastKnownGood` is a
remembered healthy reference, and `health=pending|healthy` qualifies a
candidate/current record. `ACTIVE` Patch, `RUNNING` Rollout, or `COMPLETED`
Rollout must never be interpreted as a runtime state.

## 5. Hard tenant isolation

The following are design invariants, not optional deployment settings:

1. Every tenant-bound database row, object-store object, queue message,
   cache entry, audit event, diagnostic, log correlation record, backup, and
   webhook delivery carries an immutable `organization_id`.
2. Parent IDs are checked transitively. An `Environment` cannot be attached
   to an Application from another Organization; a Patch cannot be attached
   to a Release from another Organization; and a token cannot select a
   different tenant by changing a path parameter.
3. Authorization is evaluated after authentication and before data access,
   with the Organization, role/scope, resource ancestry, environment policy,
   and requested operation all in the decision. A resource ID never bypasses
   this check.
4. Customer APIs do not expose cross-tenant reads or writes. A valid caller
   asking for an inaccessible ID receives the same not-found shape as an
   unknown ID, preventing an existence oracle. A same-tenant insufficient
   scope is `403 FORBIDDEN_SCOPE`.
5. Object storage uses a tenant-scoped logical namespace and content
   digests. Signed artifact URLs are audience-, environment-, artifact-, and
   expiry-bound. CDN/cache keys include the tenant delivery context; a cache
   hit must not turn one tenant's manifest or policy into another tenant's
   response.
6. Background workers, webhook dispatch, exports, and telemetry aggregation
   carry tenant context as required input. A missing or conflicting tenant
   context fails closed; workers never infer it from a display name or a
   global resource ID.
7. Private signing keys do not become shared tenant data. Developer-managed
   keys stay outside the hosted control plane; managed keys are isolated by
   provider key reference and explicit Organization authorization. Public key
   metadata is still tenant-scoped.
8. Audit, support, backups, and analytics obey the same boundary. A separate,
   time-bound operator plane may perform break-glass access only with an
   explicit reason, least privilege, expiry, and an immutable audit event; it
   is not available to customer tokens.
9. Cross-Organization transfer is export/import, not reassignment. Import
   creates new tenant-owned records and revalidates exact artifacts and
   signing trust; it never copies a token, installation identity, webhook
   secret, or live rollout authorization.

## 6. Cross-tenant threat register

| Threat | Required control |
| --- | --- |
| Broken object-level authorization / IDOR | Tenant-scoped repository interfaces, ancestry checks, deny-by-default scopes, and 404 masking for foreign IDs |
| Confused deputy through a ServiceAccount or job | One-Organization credentials, explicit project/application/environment scopes, and tenant context signed into queued work |
| SQL/filter omission | Mandatory tenant predicate at the data-access seam, authorization before pagination/counting, and tests for every list/read path |
| Shared cache or CDN key collision | Tenant/environment/application/platform in cache identity; private manifests never cached as public; immutable artifact URLs are audience-bound |
| Artifact path or signed-URL substitution | Digest-addressed bytes, tenant-scoped object ownership, exact Release/Patch metadata checks, short expiry, and runtime re-verification |
| Key metadata or private-key leakage | Public-only registration by default, provider isolation for managed signing, redaction in logs/audit, and no private key in API responses |
| Rollout/cohort leakage or manipulation | App-scoped random installation IDs, deterministic server assignment, no IMEI/advertising ID/serial/phone number, and no client-controlled cohort override |
| Spoofed or replayed telemetry | Per-installation event IDs, bounded payloads, optional authentication, deduplication, sampling, and treating observations as non-authoritative |
| Webhook replay, cross-tenant delivery, or SSRF | Tenant-bound subscriptions, signed timestamped envelopes, replay window/deduplication, destination validation, and retry isolation |
| Malicious insider/support access | Separate operator plane, reason/expiry/two-person policy where required, append-only audit, and no silent tenant switching |
| Backup/export mixing tenants | Tenant manifests, encrypted scoped backups, restore-time ancestry checks, and export/import validation |
| Tenant metadata in runtime bytes | Keep environment, rollout, cohort, labels, policy, and audit metadata outside Patch Format v1; bind only through separate delivery metadata |

## 7. Privacy-preserving installation identity

An Installation ID is generated once by the application from a platform
cryptographic random source and is scoped to one Application. It is not a
device ID and must not be derived from IMEI, advertising ID, hardware serial,
phone number, account email, or another unrelated identifier. The client may
send the opaque ID to the delivery endpoint; the server derives cohort
assignment from a versioned hash of the app-scoped ID, rollout ID, and app
scope. A tenant may rotate or delete the installation record without
changing runtime correctness.

Observations contain the minimum needed to describe a bounded event: event
type, event ID, installation ID or an equivalent tenant-scoped pseudonym,
platform, exact runtime/release/patch identity when known, sequence and
digest when known, stable diagnostic code, timestamps, and bounded redacted
attributes. They do not contain patch bytes, private keys, source snapshots,
absolute checkout paths, or arbitrary runtime introspection.

## 8. Boundary with the runtime

The control plane can decide that a tenant is eligible to receive an artifact,
but it cannot make the artifact executable. The runtime still performs bounded
decoding, canonical/digest verification, Ed25519 signature verification,
exact application/release/runtime compatibility, function signature checks,
closed capability-authority checks, resource checks, monotonic sequence and
state-v4 replay/high-water checks, health confirmation, rollback, and fail-
closed recovery. Product metadata is advisory to delivery; it is not a new
runtime trust store.
