# Customer Workspace

Status: AUTHORITATIVE current product guide.

The Customer Workspace is the tenant-scoped Hyfens developer surface. It is
served from `app.hyfens.com` for managed deployments and from the selected
instance origin for self-hosted deployments.

## Audience and scope

Customer owners, administrators, developers, release operators, and audit
users work inside one explicit context:

```text
Organization → Application → Environment
```

“Project” is a useful developer-facing synonym for an Application; it is not
a second domain entity.

The organization selector contains only customer memberships returned for the
authenticated user. It is not a directory of every Hyfens customer. Platform
staff, global infrastructure, other tenants, and platform credentials belong
to the Platform Console and are never substituted into this workspace.

## Current navigation

- **Overview** — real organization counts, selected context, recent records,
  recent audit, and the control-plane/runtime boundary.
- **Applications** — tenant-scoped application identities, with a safe form to
  register a new Android package or iOS bundle identity when the profile has
  `application:write`, update mutable names, and archive an application while
  preserving its history. Android package IDs and iOS bundle identifiers are
  protected once release binding makes them immutable.
- **Environments** — tenant-scoped environments, with idempotent creation under
  an existing application when the profile has `environment:write`, plus
  mutable-name update and archive actions. Archiving preserves history.
- **Releases**, **Patches**, **Artifacts**, and **Deployments** — immutable
  delivery records and bounded promotion state.
- **Audit** — redacted customer audit records for the selected organization.
- **Support** — customer-visible support cases and replies for the selected
  organization.
- **Settings** — shared session metadata, customer memberships and pending
  invitation metadata, and service credential metadata/issuance/revocation.

## Customer actions

The browser uses real capability-checked control-plane operations for
application/environment lifecycle metadata, member invitations and bounded
role/removal actions, credential issuance/revocation, support cases/replies,
and promotion of an already admitted release. Mutations are tenant-scoped and
audited. Create operations use idempotency keys where the underlying contract
requires them.

Member invitations currently create a short-lived, one-time invitation token
and display it once to the authorized administrator. Delivery and redemption
are not claimed until an email/invitation acceptance contract is available;
the token is never stored in plaintext by the control plane.

Release and patch creation remain CLI-driven because they require the local
Flutter source tree and signing boundary:

```bash
hyfens init
hyfens release android
hyfens patch android
hyfens deploy
```

The workspace provides these commands as contextual handoffs rather than
offering browser forms that cannot perform the operation safely. Rollback is
also kept as an explicit CLI/runtime operation until a browser rollback
contract exists; the dashboard does not mutate environment records directly.

## Credentials and members

Customer credentials are scoped control credentials for CLI or CI use. The
workspace displays name, scope, resource binding, expiry, and status, but never
returns token hashes or an existing plaintext token. Use short-lived, least-
privilege credentials and revoke them when a demo or CI integration ends.

The member surface shows customer memberships and capabilities while
excluding platform-audience memberships. Administrators can issue/revoke
pending invitations and perform the bounded role/removal operations exposed by
the server; owner transfer/removal remains protected.

Support cases are organization-scoped. Customers can create a case, see its
status and customer-visible timeline, and reply. Platform-internal notes and
other organizations’ cases are excluded by the server projection.

## Managed and self-hosted behavior

The Customer Workspace is the same product surface for Hyfens Cloud and
self-hosted instances. The selected profile supplies the endpoint and
capabilities. Managed infrastructure, billing, and hosted operations are not
invented in a self-hosted workspace; unavailable capabilities are stated as
such.

See [dashboard separation architecture](../architecture/dashboard-separation.md),
the [CLI guide](../cli.md), and the
[self-hosted deployment guide](../../deploy/self-hosted/README.md) for the
shared contracts.
