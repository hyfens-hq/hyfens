# ADR 0006: Organization-rooted hard tenancy

- Status: Proposed for maintainer review
- Date: 2026-08-23
- Decision scope: Productization control-plane domain and API design only

## Context

The productization design needs one domain model that works for local
self-hosting, managed hosting, teams, staged delivery, audit, and optional
runtime observations. The existing runtime is release-bound and app-owned;
it is not a multi-tenant authority. A product tenant must therefore isolate
catalog metadata, artifacts, signing metadata, rollout policy, observations,
diagnostics, access credentials, webhooks, and audit data without changing
Patch Format v1, capability v1, or the controller-owned state-v4 trust/high-
water model.

Several relationships are naturally shared inside a customer: users belong to
multiple teams, teams work on projects, projects group applications, and one
application has multiple platforms and environments. Treating each of those
objects as a tenant would make normal organization workflows either duplicate
data or require unsafe cross-tenant exceptions.

## Decision

Use **Organization as the hard customer tenant root**.

1. A User is a global principal with an explicit membership and role in each
   Organization. A credential is active in one Organization at a time and
   cannot select another tenant by changing an ID.
2. Teams are Organization-scoped groups for access grants. Projects are
   Organization-scoped groupings. Applications, Platforms, Environments,
   Releases, Patches, PatchArtifacts, SigningKeys, TrustPolicies, Rollouts,
   Cohorts, Installations, RuntimeObservations, Diagnostics, AuditEvents,
   ApiTokens, ServiceAccounts, Webhooks, and EnvironmentPolicies are all
   Organization-owned directly or through a parent chain.
3. Every tenant-bound record and asynchronous operation carries an immutable
   `organization_id`. Parent ancestry is validated on every write and read;
   an opaque resource ID is never sufficient authorization.
4. Customer API access is tenant-scoped and deny-by-default. An inaccessible
   foreign ID has the same not-found response as an unknown ID. A separate,
   explicitly audited operator plane is required for any break-glass support
   access and is not part of customer tokens.
5. Cross-Organization movement is export/import. Import creates new
   tenant-owned relationships and revalidates exact release identity,
   artifact digest, signing policy, and approvals. It does not transfer
   active tokens, webhook secrets, installation IDs, or rollout authority.
6. The API resource ID and the immutable runtime identity are separate fields.
   The exact `applicationId`, `releaseId`, `patchId`, sequence, artifact
   digest, signature, and capability authority remain unchanged across
   environment promotion or tenant metadata changes.

## Tenant isolation invariants

The implementation, when separately authorized, must enforce these invariants
at the data-access and adapter seams:

- tenant predicate and authorization happen before filtering, counting,
  sorting, pagination, cache lookup, object retrieval, or webhook dispatch;
- relational rows, object-store paths, signed URLs, cache keys, queue jobs,
  logs, exports, backups, and analytics carry tenant context;
- private signing keys are never customer API data by default; managed signing
  is an explicit provider boundary with isolated key references;
- installation identity is a random, Application-scoped pseudonym and never
  an IMEI, advertising ID, hardware serial, phone number, or account email;
- observations and diagnostics are bounded, redact secrets/source paths, and
  are evidence rather than runtime authority; and
- no control-plane state can lower runtime high-water, grant a capability,
  replace runtime signature verification, or directly select an old Patch.

## Alternatives considered

### Project as tenant

Rejected. A customer with several projects would need duplicated users,
credentials, key metadata, audit retention, and cross-project administration.
It also makes an Organization-wide security manager or audit export an unsafe
cross-tenant exception.

### Application as tenant

Rejected as the hard boundary. It is useful as a resource authorization scope,
but teams, keys, audit, and user memberships commonly span several
applications inside one customer. Application-level isolation remains a
secondary scope within the Organization.

### User-owned resources with sharing links

Rejected. Resource sharing links create ambient authority, make revocation and
audit harder, and invite confused-deputy behavior. Explicit Organization
membership and Team/application/environment grants are more reviewable.

### Global artifact and key catalogs

Rejected for customer data. Content-addressed storage may use physical
deduplication as an implementation optimization, but the logical artifact
namespace, access check, key metadata, audit record, and delivery manifest
remain tenant-scoped. A global mutable key catalog would permit trust-policy
confusion and metadata leakage.

### Cross-tenant promotion by reference

Rejected. A Release/Patch may be exported and revalidated into another
Organization, but a foreign tenant's live rollout, environment policy, token,
installation, or webhook cannot be referenced directly.

## Consequences

Positive consequences:

- one clear isolation root across the API, data stores, queues, and operations;
- explicit and auditable sharing inside a customer through Teams and roles;
- consistent resource paths and cursor/rate-limit scope;
- self-hosted single-tenant deployments are a constrained instance of the
  same model rather than a separate protocol; and
- runtime identity stays independent of SaaS tenancy and Environment labels.

Costs and trade-offs:

- every repository and asynchronous adapter must carry tenant context;
- export/import is more work than a shared global resource reference;
- support, analytics, backup, and cache systems need tenant-aware designs;
- a User working in two Organizations must select an explicit active tenant;
  there is no implicit cross-tenant dashboard view; and
- tenant-scoped IDs, signed cursors, and webhook envelopes require careful
  migration/version handling.

## Non-goals

This ADR does not implement authentication, database schemas, row-level
security, object storage, billing, KMS/HSM integration, runtime telemetry, a
REST server, or a dashboard. It does not claim that a control plane can make
an incompatible artifact valid, lower state-v4 high-water, alter capability
v1, or change Patch Format v1.

## Review and acceptance criteria

Before implementation, maintainers should require design/tests that prove:

1. foreign Organization IDs cannot be read or mutated through any resource,
   list, cursor, cache, queue, artifact, webhook, or export path;
2. parent ancestry mismatches fail closed and do not create partial records;
3. support/break-glass access is separate, time-bound, least-privilege, and
   audited;
4. exact runtime identity, signature, capability, and high-water rules remain
   unchanged through tenant/environment promotion; and
5. observations, rate limits, retries, and webhook failures cannot change
   runtime correctness or installed state.

## References

- [`domain-tenancy.md`](../architecture/domain-tenancy.md)
- [`control-plane.md`](../architecture/control-plane.md)
- [`product-api-domain.md`](../spec/product-api-domain.md)
- [`patch-format-v1.md`](../spec/patch-format-v1.md)
- [`capability-v1.md`](../spec/capability-v1.md)
- [`runtime-state-machine.md`](../architecture/runtime-state-machine.md)
- [`security.md`](../architecture/security.md)

## History

- 2026-08-23: Proposed as the productization tenancy decision; no
  implementation authorized.
