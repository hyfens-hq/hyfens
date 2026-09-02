# OSS / Cloud source boundary

Status: FROZEN — implemented as an OSS source boundary with separately
maintained Cloud services.

The public Hyfens repository contains the reusable developer product and the
self-hosted reference path. It does not contain the marketing website or the
editorial CMS.

## Public OSS repository

The OSS repository owns:

- the Flutter runtime, verifier, patch format, compiler, and instrumenter;
- the `hyfens` CLI and its compatibility shim;
- the self-hosted control plane and deployment definition;
- the dependency-free client dashboard in `dashboard/`; and
- the dashboard's browser-auth and discovery surfaces.

The dashboard is read-only wherever the control plane does not expose a safe,
authoritative mutation contract. It is usable against both managed and
self-hosted control planes through the same endpoint/profile model.

## Separately maintained Cloud services

The separately maintained Cloud web surface owns:

- the `hyfens.com` marketing website;
- the editorial CMS and its content-management UI;
- Cloud-only marketing/content integrations; and
- the managed web deployment and edge configuration for those surfaces.

It is not a dependency of the OSS build and must not be copied into an OSS
release or source archive.

## Runtime seam

The OSS dashboard and the private Cloud web surfaces communicate through the
existing control-plane interface. They do not share a database, session store,
CMS implementation, or source tree at runtime. Auth/session authority remains
in the control plane; the dashboard and CMS use the appropriate scoped browser
surface.

The deployment topology is therefore:

```text
hyfens.com         → Cloud marketing web
managed dashboard → OSS dashboard build
api.hyfens.com     → managed control plane
self-hosted        → OSS control plane + OSS dashboard
```

This split keeps one client dashboard implementation available to self-hosted
operators while allowing the hosted marketing and editorial product to evolve
privately.

The commercial packaging rule is documented in
[`HYFENS_CLOUD_COMMERCIAL_BOUNDARY.md`](HYFENS_CLOUD_COMMERCIAL_BOUNDARY.md):
OSS provides the core workflow, while Cloud monetizes managed operation and
service convenience. The private website and CMS are not treated as the
commercial moat, and no unimplemented Cloud entitlement is advertised.
