# Hyfens Web Product Boundary Audit

Status: APPROVED — migration authorized

Decision: `WEB PRODUCT BOUNDARY — CLOUD/OSS FRONTENDS MUST BE RESTRUCTURED`

This is the durable decision record for the web product ownership boundary.
The detailed implementation evidence is retained in the historical review
records; current product truth is maintained in the linked architecture and
product guides.

## Decision

The public `hyfens` repository must retain a complete, distributable
Customer/Instance Workspace because a self-hosted installation cannot depend
on a private repository for organization, application, environment, delivery,
credential, audit, and setup workflows.

The global Hyfens Platform Console must not remain in the public OSS dashboard
artifact. It operates the managed Hyfens business and platform: cross-tenant
organizations, commercial projections, Cloud support operations, staff,
managed operations, entitlements, and platform audit. Those capabilities are
owned by the private `hyfens-cloud-web` project at `platform.hyfens.com`.

Authorization guards are necessary but are not a sufficient product or
licensing boundary. The OSS image must physically contain customer/instance
web code only.

## Current ownership target

```text
hyfens-hq/hyfens — public Apache-2.0 repository
  CLI, MCP, runtime/compiler, control plane, shared customer contracts,
  self-host deployment, Customer/Instance Workspace

hyfens-cloud-web — private Cloud repository
  marketing/CMS, Cloud billing, Cloud Customer Workspace extensions,
  Platform Console, global support, staff, commercial, managed operations
```

Shared identity, discovery, device authorization, customer API contracts,
explicit `customer`/`platform` audiences, capabilities, structured errors,
and design primitives remain reusable contracts. Sharing a contract does not
make the Platform Console an OSS product.

## Findings that drive the decision

- The former OSS dashboard was one static HTML/JavaScript/CSS artifact that
  bundled both Customer Workspace and Platform Console shells, routes, API
  calls, and platform-specific renderers.
- The OSS `hyfens-dashboard` image therefore physically distributed global
  platform UI even when route and API guards denied ordinary customers.
- The Cloud project initially contained a Next.js marketing/CMS/billing
  application but no Customer Workspace or Platform Console. It is now the
  destination for the private Platform Console baseline without overwriting
  those existing surfaces.
- Self-hosting requires the public customer surface and its compatible
  control-plane contracts, but does not require Hyfens revenue, employee
  administration, global support, or managed-fleet operations.
- The existing control plane still owns several bounded platform projections
  as public/shared contracts for now. Removing a frontend does not by itself
  authorize deleting those APIs; any backend privatization is a separate
  compatibility and security decision.

## Required future state

The OSS dashboard image named `hyfens-dashboard` means Customer/Instance
Workspace only. It must support a clean public self-host deployment without
`hyfens-cloud-web`, Cloud credentials, or global staff identities.

The Cloud project owns the Platform Console and composes Cloud-only customer
capabilities around the public customer lifecycle rather than maintaining a
second copied implementation of applications, environments, delivery,
members, credentials, support, or audit.

The canonical managed hosts are:

```text
app.hyfens.com       Cloud Customer Workspace
platform.hyfens.com  Cloud Platform Console
api.hyfens.com       managed control plane
```

Self-hosted deployments use their own customer/API origins and discovery
configuration. The former alternate managed platform hostname is retired and
must not be reintroduced; `platform.hyfens.com` is canonical.

## Local patch disposition

The isolated UI patch is split by ownership:

| Patch area | Destination | Disposition |
| --- | --- | --- |
| Static deep-route base fix | OSS Customer/Instance Workspace | Apply |
| Customer member role-select wrapper/alignment | OSS Customer/Instance Workspace | Apply |
| Platform staff role controls and protected-owner copy | Cloud Platform Console | Carry into Cloud implementation |
| Platform action/select styling and assertions | Cloud Platform Console | Recreate/adapt |
| Temporary `dart:stable` runtime Dockerfile replacement | Neither | Discard |

## Migration guardrails

1. Establish the Cloud repository baseline and intended private remote.
2. Keep the OSS customer source and self-host Compose independently usable.
3. Remove platform UI/API modules from future OSS dashboard artifacts; do not
   solve this with host detection or hidden menu items.
4. Preserve shared auth/customer API compatibility and server-side audience,
   capability, and tenant isolation checks.
5. Validate both repositories locally before any Cloud deployment or DNS
   change.

The approved migration is bounded source ownership work. It does not authorize
a new release, production cutover, DNS changes, history rewriting, or removal
of the OSS Customer/Instance Workspace.
