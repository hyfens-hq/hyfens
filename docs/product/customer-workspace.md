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

Member invitations create a short-lived, single-use invitation token. The
configured delivery adapter receives the token in memory; the default local
and self-hosted adapter does not send email. Instead, an authorized
administrator can retrieve the generated invitation link once for a local
demo or a configured delivery provider. The control plane stores only a token
hash and never logs the bearer value.

An invite recipient can open `/invite/<token>`, review the organization and
offered role, then authenticate or create an account and accept the invite.
Acceptance checks recipient identity, expiry, revocation, and single use. It
is idempotent for an already accepted invitation. The accepted membership is
then visible in the organization member list.

Release and patch creation remain CLI-driven because they require the local
Flutter source tree and signing boundary:

```bash
hyfens init
hyfens release android
hyfens patch android
hyfens deploy
```

The workspace provides these commands as contextual handoffs rather than
offering browser forms that cannot perform the operation safely. Promotion of
an already admitted release is available as a server-authorized action. A
browser rollback is not claimed by this contract; rollback remains an
explicit CLI/runtime operation until the server exposes a safe target- and
high-water-aware operation. The dashboard never mutates environment records
directly to simulate rollback.

## Credentials and members

Customer credentials are scoped control credentials for CLI or CI use. The
workspace displays name, scope, resource binding, expiry, and status, but never
returns token hashes or an existing plaintext token. Use short-lived, least-
privilege credentials and revoke them when a demo or CI integration ends.
Credentials are organization-owned: removing a member does not implicitly
revoke credentials that member previously issued or that are used by CI. An
authorized organization operator must rotate or revoke those credentials
explicitly.

The member surface shows customer memberships and capabilities while
excluding platform-audience memberships. Authorized owners/admins can issue,
revoke, and redeem invitations, change a member's capability bundle, and
remove/deactivate a member. Ownership is protected from ordinary role edits:
the current owner must explicitly transfer ownership to another active member,
which is committed as one ownership-transfer operation at the persistence
boundary and makes the target owner and the former owner an admin. PostgreSQL
commits both user records in one transaction; the single-node file store
serializes the bounded operation and atomically replaces each record. The
last-owner invariant is preserved.

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
