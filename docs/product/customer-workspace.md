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

The organization selector contains only customer memberships returned for the
authenticated user. It is not a directory of every Hyfens customer. Platform
staff, global infrastructure, other tenants, and platform credentials belong
to the Platform Console and are never substituted into this workspace.

## First Cloud workspace

New managed Cloud customers start at the workspace sign-up surface with a
verified email identity and a chosen workspace name. Verification provisions
one customer-owned organization, creates the owner membership, assigns the
internal Free plan, and returns a customer session. Free assignment is a
server-side onboarding step and does not create a Razorpay subscription.

The first authenticated view offers a direct **Applications** action for an
empty workspace so the owner can register the first Flutter application. The supported CLI login
uses the same customer audience; `hyfens profile current` and
`hyfens profile bind` expose only the non-secret organization, application, and
environment context needed for local commands.

## Current navigation

- **Overview** — organization counts, selected context, recent records, and
  the control-plane/runtime boundary.
- **Applications** — tenant-scoped application identities, with a safe form to
  register a new Android package or iOS bundle identity when the profile has
  `application:write`.
- **Environments** — tenant-scoped environments, with idempotent creation under
  an existing application when the profile has `environment:write`.
- **Releases**, **Patches**, **Artifacts**, and **Deployments** — immutable
  delivery records and bounded promotion state.
- **Audit** — redacted customer audit records for the selected organization.
- **Billing** — effective plan, usage, paid-through state, scheduled changes,
  cancellation, and the separate reviewed-refund entry point.
- **Privacy** — separate personal-account and Cloud-organization deletion
  requests with visible staged-processing status.
- **Settings** — shared session metadata, customer memberships, and service
  credential metadata/issuance/revocation.

## Customer actions

The browser uses real capability-checked control-plane operations for
application creation, environment creation, credential issuance, credential
revocation, and promotion of an already admitted release. Create operations
use idempotency keys and are audited. Credential plaintext is returned once,
shown once in the browser, and never stored in metadata.

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

The current member surface is a safe metadata foundation: it shows customer
memberships and capabilities while excluding platform-audience memberships.
Invitations, role changes, and member deactivation remain out of the UI until
their server contracts can provide validation, authorization, and audit
semantics.

Privacy deletion is separate from billing cancellation. A signed-in customer
can request personal-account deletion after current-password confirmation, or
start the no-login flow at `/account-deletion`, which sends a neutral response
and a purpose-bound verification link. Sole ownership is resolved explicitly;
the system never silently transfers ownership or deletes an organization when
one person removes their account. An organization owner can request staged
tenant deletion from `/dashboard/privacy`; it stops future renewal through the
billing boundary, preserves the paid period, and processes customer-owned
records and artifact bytes in bounded, retryable stages. Required audit,
billing, security, and commercial evidence remains subject to the retention
policy.

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
