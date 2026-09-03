# Dashboard separation architecture

Status: IMPLEMENTED WITH BACKLOG

This document records the implemented boundary between the Hyfens Customer
Workspace and Hyfens Platform Console. It is the compact architecture
reference for the static dashboard implementation; the product/authorization
contract remains in
[`HYFENS_DEVELOPER_PLATFORM_CONTRACT.md`](../HYFENS_DEVELOPER_PLATFORM_CONTRACT.md).

## Surface ownership

| Surface | Audience | Owns | Must not own |
| --- | --- | --- | --- |
| Public website | Prospective users and public visitors | Marketing, product explanation, pricing, docs, login/signup entry | Authenticated operations |
| Customer Workspace | Customer organization owner/admin/developer/release/audit users | One organization’s applications, environments, releases, patches, deployments, audit, team, credentials, support, and settings | Other tenants, global service health, platform staff operations |
| Platform Console | Authorized Hyfens owners, administrators, support, operations, commercial, and security staff | Platform metrics, commercial projection, bounded organization directory/detail, support queue, platform-audience audit, and operator context | Customer membership switching or customer-session impersonation |
| Shared auth/API/UI | All supported clients | Identity, sessions, CLI authorization, transport, errors, tokens, primitives, formatting | Product-specific navigation or authorization decisions |

Managed Cloud and Self-Hosted use the same Customer Workspace concepts. The
profile selects the endpoint and available capabilities; it does not create a
second customer information architecture. The global Platform Console is not
automatically exposed by a self-hosted customer instance.

## Current implementation topology

The repository intentionally remains a dependency-free static dashboard rather
than migrating frameworks or duplicating the frontend:

```text
dashboard/index.html
  pre-auth surface
  customer shell DOM
  platform shell DOM

dashboard/app.js
  shared session/API state
  route and host selection
  Customer Workspace renderers
  Platform Console renderers

dashboard/serve.py
  static route fallback
  bounded local proxy allow-list

dashboard/tokens.css / styles.css / auth-flow.css
  shared visual system and responsive primitives
```

`CustomerShell` and `PlatformShell` are explicit logical shells in the one
static bundle. They have separate sidebars, context bars, home/overview
renderers, navigation, settings copy, and route guards. They share the
underlying API client, session lifecycle, formatting, errors, tokens, tables,
filters, drawers, and other UI primitives. This is the smallest structural
change that creates a real product boundary without a framework migration.

## Route topology

### Customer Workspace

The managed Customer Workspace is deployed at `app.hyfens.com`; a self-hosted
instance uses its own origin. The current customer routes are:

```text
/                         overview
/applications             applications
/environments             environments
/releases                 releases
/patches                  patches
/artifacts                artifacts
/deployments              deployment records
/audit                    customer audit
/support                  customer support
/settings                 customer/account settings
```

### Platform Console

The recommended managed host is `admin.hyfens.com`. Its DNS A record now points
to the managed edge, but the hostname is not active until its certificate
coverage and control-plane browser-origin allow-list are supplied. Local
development supports the `/platform` route root, while a platform host
supports the equivalent root routes:

```text
/platform                  overview
/platform/organizations    organizations directory
/platform/organizations/:id organization detail
/platform/audit             platform-audience audit
/platform/operations        metrics-backed operations
/platform/users             platform staff metadata
/platform/entitlements      plans and entitlement metadata
/platform/commercial        subscription-derived commercial metrics
/platform/support           tenant-aware support queue and case detail
/platform/settings          platform operator settings
```

On `admin.hyfens.com` or `platform.hyfens.com`, the same platform pages are
addressed as `/`, `/organizations`, `/organizations/:id`, `/audit`,
`/operations`, `/commercial`, `/support`, and `/settings`. The host/path split
is implemented in the static route resolver and local server fallback; managed
`admin.hyfens.com` activation remains an external deployment gate.

## API boundary

Shared authentication and transport remain in the dashboard API client. The
implemented bounded projections are:

| API | Audience | Purpose |
| --- | --- | --- |
| `GET /v1/organizations/{id}/overview` | Customer | Existing tenant-scoped read model for applications, environments, releases, patches, artifacts, rollouts, and redacted customer audit |
| `GET /v1/organizations/{id}/members` | Customer | Safe member metadata for the selected organization; platform-audience memberships are excluded |
| `PATCH /v1/organizations/{id}/members/{user}` | Customer | Capability-checked customer role update |
| `POST /v1/organizations/{id}/members/{user}/remove` | Customer | Audited customer member removal/deactivation |
| `GET /v1/organizations/{id}/invitations` | Customer | Pending invitation metadata without invitation secrets |
| `POST /v1/organizations/{id}/invitations` | Customer | One-time invitation issuance; plaintext token is returned once |
| `POST /v1/organizations/{id}/invitations/{invitation}/revoke` | Customer | Audited invitation revocation |
| `GET /v1/organization-invitations/{token}` | Public invitation | Safe invitation preview without token persistence or account data |
| `POST /v1/organization-invitations/{token}` | Public invitation | Recipient-checked, single-use invitation redemption |
| `POST /v1/organizations/{id}/ownership-transfer` | Customer | Explicit audited owner transfer to an active member |
| `GET /v1/organizations/{id}/credentials` | Customer | Credential metadata without token hashes or plaintext |
| `POST /v1/organizations/{id}/credentials/{credential}/revoke` | Customer | Existing bounded credential revocation action |
| `POST /v1/organizations/{id}/applications` | Customer | Idempotent application identity registration |
| `PATCH /v1/organizations/{id}/applications/{app}` | Customer | Update mutable application metadata |
| `POST /v1/organizations/{id}/applications/{app}/archive` | Customer | Archive an application without deleting history |
| `POST /v1/organizations/{id}/applications/{app}/environments` | Customer | Idempotent environment creation under a tenant application |
| `PATCH /v1/organizations/{id}/environments/{env}` | Customer | Update mutable environment metadata |
| `POST /v1/organizations/{id}/environments/{env}/archive` | Customer | Archive an environment without deleting history |
| `POST /v1/organizations/{id}/credentials` | Customer | One-time plaintext credential issuance; metadata is safe thereafter |
| `POST /v1/organizations/{id}/environments/{env}/release-promotions` | Customer | Preconditioned promotion of an already admitted release |
| `GET /v1/organizations/{id}/support/cases` | Customer | Tenant-scoped support case list |
| `POST /v1/organizations/{id}/support/cases` | Customer | Create an audited support case |
| `GET /v1/organizations/{id}/support/cases/{case}` | Customer | Customer-visible case timeline |
| `POST /v1/organizations/{id}/support/cases/{case}/messages` | Customer | Customer-visible case reply |
| `GET /v1/platform/metrics` | Platform | Existing aggregate platform metrics projection |
| `GET /v1/platform/organizations` | Platform | Bounded organization directory with counts and activity summary |
| `GET /v1/platform/organizations/{id}` | Platform | Read-focused organization, application, environment, and count projection |
| `GET /v1/platform/audit` | Platform | Explicit platform-audience events only |
| `GET /v1/platform/users` | Platform | Safe platform staff identity, role, capability, and access metadata |
| `GET /v1/platform/staff/invitations` | Platform | Pending staff invitation metadata |
| `POST /v1/platform/staff/invitations` | Platform | Single-use staff invitation issuance |
| `PATCH /v1/platform/staff/{user}` | Platform | Explicit staff role and active-state administration |
| `POST /v1/platform/staff/{user}/sessions/revoke` | Platform | Audited platform-session revocation |
| `POST /v1/platform/staff/invitations/{invitation}/revoke` | Platform | Audited staff invitation revocation |
| `GET /v1/platform-staff-invitations/{token}` | Public invitation | Safe staff invitation preview |
| `POST /v1/platform-staff-invitations/{token}` | Public invitation | Single-use staff invitation redemption |
| `GET /v1/platform/entitlements` | Platform | Read-only plan and subscription metadata without provider secrets |
| `GET /v1/platform/commercial` | Platform | Subscription-derived MRR/ARR projection or an explicit unavailable source state |
| `GET /v1/platform/support/cases` | Platform | Bounded cross-tenant support queue |
| `GET /v1/platform/support/cases/{case}` | Platform | Case detail including platform-internal notes |
| `PATCH /v1/platform/support/cases/{case}` | Platform | Audited case status, priority, and active-staff assignment |
| `POST /v1/platform/support/cases/{case}/messages` | Platform | Audited customer-visible reply or internal note |

The local proxy forwards only these reviewed platform/customer metadata routes
and their bounded query parameters. It does not become a generic browser
proxy.

## Authorization boundary

The control plane now distinguishes two authorization audiences:

```text
customer
platform
```

Customer routes use the customer audience by default and continue to enforce
organization membership and resource scopes server-side. Platform routes
require the platform audience and an explicit capability. The current
platform capability set is intentionally small:

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
platform:staff:manage
platform:sessions:revoke
```

The metrics-backed Operations page currently uses the existing
`platform:overview` projection/capability because there is not yet a distinct
operations data contract. The separate `platform:operations:read` capability
remains available for a future distinct projection and is not used to imply
functionality that does not exist.

Legacy platform profile eligibility still requires the configured platform-
admin identity, owner membership, and `super-admin` profile. Explicit staff
memberships instead use the `platform_system` organization and a bounded role
capability bundle. In both cases the platform audience and requested
capability are checked server-side; an email address or profile name alone is
not sufficient. When `HYFENS_PLATFORM_MFA_REQUIRED=true`, a verified MFA
session state is also required. Enrollment/provider integration is an explicit
deployment boundary, not a claim of built-in MFA delivery.

Frontend guards select the correct shell and provide useful fallbacks, but
they are not the security boundary. Backend negative tests cover ordinary
customer denial of platform projections and rejection of platform-audience
tokens on customer routes.

## Context rules

- Customer organization switching is based only on organizations represented
  by the authenticated user’s customer memberships.
- Customer member projections include only customer-audience memberships, even
  when the same human account also has a separate Platform Console membership.
- The Platform Console has no customer membership switcher. Its Organizations
  page calls the platform projection and represents organizations visible to
  the authorized platform operator.
- Customer pages read the selected organization context and never use the
  platform directory as a substitute for membership.
- Platform organization detail is bounded and read-focused; it does not
  impersonate a customer session.
- Self-hosted customer sessions use the same customer shell and API contract.
- Managed endpoint internals are represented in authenticated UI metadata as
  `Hyfens Cloud (managed)`; self-hosted endpoints remain visible so operators
  can identify the active instance.

## Intentional coverage limits

This milestone establishes the separation and the highest-value safe MVP
foundations; it does not pretend that every future workflow exists. The
following remain backlog until their backend contracts are ready:

- browser-side release and patch creation, because they require the local
  Flutter source tree;
- browser-side rollback and any deployment action beyond promotion of an
  already admitted release;
- invitation email delivery provider configuration and time-limited support
  sessions;
- entitlement mutation, incidents, and infrastructure/provider state;
- MFA enrollment/recovery/provider integration and additional managed Platform
  Console access hardening;
- browser-side rollback until a server operation exposes the required target
  and high-water semantics.

The implemented customer actions are idempotent where they create records,
tenant-scoped, capability-gated, audited, and rendered as honest forms. The
promotion form only calls the existing preconditioned server operation. Source-
dependent release/patch creation and unsupported rollback remain explicit
CLI handoffs, not fake buttons or direct persistence mutations.

## Deployment boundary

The current managed edge serves the Customer Workspace bundle from
`app.hyfens.com` and keeps the shared API at `api.hyfens.com`. The Platform
Console remains a separate product surface and is not exposed through the
customer host. Its DNS A record is present, but activating
`admin.hyfens.com` still requires a certificate containing that hostname, an
explicit API browser-origin allow-list entry, and the separate static edge
route. Neither surface is automatically made available in ordinary
self-hosted deployments beyond the documented Customer Workspace.
