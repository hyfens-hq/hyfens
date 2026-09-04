# OSS / Cloud source boundary

Status: AUTHORITATIVE — current repository ownership

Hyfens is an open-source core plus a private managed Cloud product. The
source boundary is intentionally product-oriented: public self-hosting stays
complete, while global Hyfens business and operator tooling is not shipped in
the public dashboard image.

## Public `hyfens` repository

The public repository owns:

- the Flutter runtime, verifier, patch format, compiler, and instrumenter;
- the `hyfens` CLI and compatibility shim;
- the control plane, shared auth/discovery/device contracts, and customer API;
- self-hosted PostgreSQL/object-storage/Compose deployment; and
- the dependency-free Customer/Instance Workspace in `dashboard/`.

The OSS workspace provides the customer lifecycle required by a self-hosted
installation:

```text
organization → application → environment
```

including customer applications, environments, releases, patches, artifacts,
deployments, promotion/status, members/invitations, credentials, support
contract, audit, settings, browser auth, CLI authorization, and device
approval. Source-dependent release/patch operations remain CLI-driven where
the local Flutter project and signing boundary are required.

The published `hyfens-dashboard` image is retained as a compatibility name
for this Customer/Instance Workspace only. The current OSS artifact does not
contain the global Platform Console, commercial UI, Cloud support queue,
internal notes, staff administration, managed-fleet operations, or platform
audit UI.

## Private `hyfens-cloud-web` repository

The private Cloud repository owns:

- Hyfens marketing and CMS;
- Cloud billing and subscription composition;
- Cloud Customer Workspace extensions around the public customer contract;
- the global Platform Console at `platform.hyfens.com`;
- global organizations, commercial projections, entitlements, support
  backoffice, internal notes, staff administration, managed operations, and
  platform audit.

The Cloud repository must not copy the entire OSS customer application. It
should consume compatible auth/API contracts and add Cloud-only composition or
extensions where needed. Platform navigation and business logic remain
Cloud-owned rather than becoming conditional OSS components.

## Shared contracts

The repositories integrate through documented/versioned contracts, not
filesystem-relative imports or a shared database. The reusable boundary
includes:

- human auth, refresh, logout, PKCE, device authorization, and discovery;
- `customer` and `platform` authorization audiences and capability semantics;
- structured API errors, endpoint/profile normalization, and customer API
  models; and
- stable design tokens, formatters, redaction helpers, and small UI
  primitives where reuse is proven.

The control plane currently retains bounded `/v1/platform/...` projections as
public/shared API contracts consumed by the private Cloud Console. Their
continued presence is not evidence that the OSS frontend should ship platform
code. A future Cloud-private backend extraction is a separate migration with
its own compatibility, authorization, and security review.

## Deployment topology

```text
hyfens.com                 → Cloud marketing/CMS
app.hyfens.com             → Cloud Customer Workspace composition
platform.hyfens.com        → Cloud Platform Console
api.hyfens.com             → managed control plane
self-hosted instance       → OSS control plane + OSS Customer/Instance Workspace
```

Self-hosted deployments use their own origin and discovered/configured API
endpoint. They do not require `hyfens-cloud-web`, Cloud credentials, Cloud
billing, global support, or Hyfens staff identities. Local instance health and
operator configuration remain OSS concerns only when they genuinely describe
that installation.

## Licensing and commercial boundary

The public repository is Apache-2.0. Previously published combined artifacts
remain public and immutable; this source split does not rewrite history or
retroactively remove rights. Future private Cloud source is not a substitute
for a complete self-hosted baseline. The managed value is operated
infrastructure, Cloud support, commercial services, and global operations,
not withholding the core customer workflow from OSS.

See [dashboard and web product separation](architecture/dashboard-separation.md),
[Customer Workspace](product/customer-workspace.md), [Platform Console](product/platform-console.md), and the
[approved boundary audit](architecture/web-product-boundary-audit.md).
