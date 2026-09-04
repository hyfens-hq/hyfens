# Dashboard and web product separation

Status: AUTHORITATIVE — OSS/Cloud ownership frozen; migration in progress

Hyfens has separate web products over compatible identity, control-plane, and
design contracts. Product ownership is a repository and build boundary, not
only a route guard.

## Product topology

```text
hyfens.com
  Cloud marketing, CMS, and public product information

app.hyfens.com
  target Cloud Customer Workspace composition (live edge cutover remains a
  separate deployment)

platform.hyfens.com
  Hyfens Cloud Platform Console

api.hyfens.com
  managed control plane and shared auth/API contracts

self-hosted instance origin
  OSS Customer/Instance Workspace + OSS control plane
```

## Ownership

| Product | Source owner | Audience | Responsibility |
| --- | --- | --- | --- |
| Customer/Instance Workspace | Public `hyfens` repository | Customer organization users and self-host operators | Organization context, applications, environments, delivery records, members, invitations, credentials, customer support contract, audit, settings, discovery, and device authorization |
| Cloud Customer Workspace extensions | Private `hyfens-cloud-web` repository, consuming the public customer contract | Hyfens Cloud customers | Managed-service, plan, billing, and Cloud support extensions around the public customer core |
| Platform Console | Private `hyfens-cloud-web` repository | Authorized Hyfens staff | Global organizations, commercial projections, Cloud support operations, staff, entitlements, managed operations, and platform audit |
| Shared control-plane contracts | Public control plane and documented API contract | CLI, OSS workspace, Cloud web, and authorized platform clients | Identity, sessions, discovery, customer resources, authorization audiences, capabilities, and bounded projections |

The public repository must remain sufficient for a user to run the
Customer/Instance Workspace with a self-hosted control plane, PostgreSQL,
object storage, and the documented deployment path. Self-hosted operators
administer their installation or customer organization; they are not Hyfens
employees and do not receive the global Platform Console.

## OSS build boundary

The public `dashboard/` is a dependency-free static Customer/Instance
Workspace. Its shipped artifact contains the customer shell, customer routes,
browser auth/discovery/device surfaces, and the reviewed customer API proxy
allow-list. It does not contain Platform Console navigation, renderers,
commercial views, global support queues, staff administration, managed
operations, or platform-audit UI/API calls.

The OSS image name `hyfens-dashboard` is retained for compatibility and means
Customer/Instance Workspace only. The static server rejects former platform
route roots instead of serving the customer application for them. This makes
the product boundary physical while retaining explicit negative tests.

Customer routes operate inside:

```text
Organization → Application → Environment
```

The organization selector is built from the authenticated user's customer
memberships. It is never a global organization directory.

## Cloud build boundary

`hyfens-cloud-web` owns the private Next.js Cloud composition and its
Cloud-only product surfaces. The Platform Console has independent route roots
and shell code under that repository; it does not reuse customer membership
switching as a platform directory and does not impersonate customer sessions.

The current local Cloud route roots are:

```text
/platform
/platform/organizations
/platform/organizations/:id
/platform/operations
/platform/support
/platform/commercial
/platform/entitlements
/platform/users
/platform/audit
/platform/settings
```

`/dashboard/platform` is retained as a local/deep-link-compatible route root
while the canonical managed host is `platform.hyfens.com`. Host-level edge
mapping is deployment configuration; it must not reintroduce Platform Console
code into the OSS image.

The Cloud project also retains its existing marketing, CMS, and billing
surfaces. Cloud Customer Workspace extensions must consume the public customer
API/auth contract rather than copying the entire OSS customer lifecycle. The
current live `app.hyfens.com` deployment is not changed by this migration;
customer cutover to a Cloud composition requires a separate staged deployment
acceptance.

## Authentication and authorization

Identity and session lifecycle remain shared. Authorization is explicit:

```text
audience = customer
audience = platform
```

Customer requests require the customer audience, tenant membership, and the
relevant resource capability. Platform requests require the platform audience
and an explicit platform capability. Frontend route guards are presentation
only; server-side authorization and tenant isolation are authoritative.

The public control plane currently retains bounded `/v1/platform/...`
projections as a documented security/API contract consumed by the private
Cloud Console. This migration removes the platform frontend from OSS; it does
not silently remove public backend contracts. A future backend extraction of
Cloud-private commercial, staff, support, or managed-operations services is a
separate change requiring API compatibility and security review.

## Shared code and contracts

Share stable boundaries rather than product shells:

- authentication, refresh, logout, PKCE, device authorization, and discovery;
- API models, structured errors, endpoint/profile normalization, and
  capability semantics;
- design tokens, icons, formatting, redaction, and small UI primitives; and
- customer resource contracts for applications, environments, delivery,
  members, credentials, support, and audit.

Do not share navigation, overview composition, settings, support backoffice,
commercial logic, staff administration, or platform context bars as one
conditional product component. Do not use filesystem-relative imports or a
submodule to couple the repositories. Extract a versioned package only after
repeated reuse proves that it lowers maintenance cost.

## Self-hosted and managed behavior

The OSS workspace uses the discovered/configured instance endpoint and does
not hard-code `app.hyfens.com` or `api.hyfens.com`. Managed Cloud can compose
the same customer concepts at `app.hyfens.com`; self-hosted installations
remain independent of `hyfens-cloud-web`, Cloud credentials, Cloud billing,
and Hyfens staff identities.

Local instance health and storage readiness may remain an OSS operator
concern. Global fleet health, provider infrastructure, revenue, global
support, staff, and platform audit are Cloud-only concerns.

## Migration status

The migration changes future source/build ownership only. The historical
combined OSS artifacts and `v0.1.1` remain immutable. Before a future release
or production cutover, the OSS image must pass a physical artifact scan and a
clean-clone self-host acceptance; the Cloud app must pass its independent
lint/typecheck/build and platform-audience acceptance. No DNS, release tag,
or production deployment is authorized by this document.

See [Customer Workspace](../product/customer-workspace.md), [Platform
Console](../product/platform-console.md), [OSS/Cloud source boundary](../OSS_CLOUD_SOURCE_BOUNDARY.md), and the
[web product boundary audit](web-product-boundary-audit.md).
