# Platform Console

Status: AUTHORITATIVE current product guide.

The Platform Console is the privileged operator surface for Hyfens itself. It
is intended for authorized Hyfens owners, administrators, support, operations,
security, and commercial operators where the corresponding capability exists.
The recommended managed host is `admin.hyfens.com`; local development uses
the `/platform` route root.

## Audience and boundary

Platform sessions use an explicit `platform` authorization audience and
server-side platform capabilities. The current compatibility guard also
requires the configured platform-admin identity and an eligible platform
membership. A customer session cannot gain this context by changing a URL or
by belonging to several organizations.

The Platform Console is not a customer workspace with extra menu items. It has
its own navigation and context bar, and it does not use the customer
membership switcher or silently impersonate a customer.

## Current navigation

- **Overview** — aggregate platform metrics plus available commercial and
  support-queue signals.
- **Organizations** — a bounded cross-tenant directory and read-focused
  organization detail projection. It includes metadata, counts, activity,
  subscription summary, open support-case count, applications, and
  environments, not customer secrets.
- **Commercial** — read-only MRR/ARR and subscription metrics derived from
  active control-plane plan/subscription records. When a billing source,
  currency, or payment history is unavailable, the page says so instead of
  fabricating revenue.
- **Support** — tenant-aware case queue and detail view. Authorized staff can
  assign cases to active platform users, change status/priority, and send
  customer-visible replies or explicitly internal notes.
- **Security & audit** — events explicitly recorded for the platform audience;
  customer audit rows are not relabeled as platform events.
- **Operations** — the current metrics-backed operational view. It reports only
  signals the control plane actually provides and uses unavailable/unknown
  states instead of implying production availability.
- **Platform users** — staff identity, status, platform role/capability, and
  access metadata. Customer members and credential material are excluded.
- **Plans & entitlements** — read-only plan and subscription metadata without
  payment/provider secrets.
- **Platform settings** — the current operator access boundary and endpoint
  metadata. Configuration mutation is not claimed until a distinct contract
  exists.

## API and authorization

The console reads bounded `/v1/platform/...` projections. Each route requires
the platform audience and its explicit capability on the control plane. The
frontend guard only controls presentation; it is not an authorization
boundary. Cross-tenant inspection uses a platform projection rather than a
customer token pretending to be a member of the selected organization.

The current capability set is intentionally small:

```text
platform:overview
platform:organizations:read
platform:organizations:inspect
platform:audit:read
platform:operations:read
platform:accounts:read
platform:entitlements:read
platform:commercial:read
platform:support:read
platform:support:write
```

Commercial metrics are sourced from `billing_plans` and
`billing_subscriptions`. They represent active recurring plan amounts only;
the current control plane does not record payment/revenue history, so cash
revenue, churn, expansion, and contraction are not claimed. Multiple
currencies are reported as a source boundary rather than summed together.

Support staff mutations are explicit and audited. Assignment accepts active
platform users only. Customer-visible replies and platform-internal notes use
separate visibility values; internal notes never enter Customer Workspace
responses.

No platform projection returns passwords, sessions, customer credential
plaintext, token hashes, signing keys, database credentials, or provider
secrets.

## Managed-only boundary

The global Platform Console is a managed-platform capability and is not
automatically exposed by ordinary self-hosted customer deployments. A
self-hosted operator may inspect the Customer Workspace on the instance origin
and use the deployment/operator documentation; an instance-admin surface is a
separate future capability, not a disguised global console.

Staff role mutation, billing mutation, incident management,
infrastructure/provider controls, support impersonation, and MFA/network
hardening remain backlog until their explicit contracts are ready. Support
inspection is performed through platform APIs, not customer-session
impersonation.

See [dashboard separation architecture](../architecture/dashboard-separation.md)
for routes and the [security architecture](../architecture/security.md) for
the broader trust boundary.
