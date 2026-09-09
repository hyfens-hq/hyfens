# Hyfens Cloud commercial boundary

Status: ADOPTED — 2026-08-31

Hyfens uses an open-source core plus a managed Cloud service. The commercial
boundary is operational: customers may run the core themselves, while Cloud
customers pay Hyfens to operate the control-plane and delivery infrastructure
for them.

## What remains in OSS

The public repository remains useful for a complete self-hosted workflow:

- Flutter runtime, verifier, patch format, compiler, and instrumenter;
- `hyfens` CLI and the deprecated `tool` compatibility shim;
- control plane and self-hosted deployment definition;
- client dashboard and browser-auth/discovery surfaces; and
- the documented release, patch, deploy, verify, promote, and rollback
  protocol.

The dashboard is intentionally OSS. It is the reusable client surface for
both self-hosted installations and the hosted product. Cloud access must not
depend on a hidden or privately modified dashboard fork.

## What Cloud customers pay for

Hyfens Cloud packages the operational work around the same product contract:

- hosted control-plane and artifact-delivery infrastructure;
- managed authentication, storage, TLS, upgrades, and routine operations;
- reduced setup and maintenance burden for teams that do not want to operate
  PostgreSQL, R2-compatible storage, ingress, and recovery procedures; and
- Cloud account, billing, support, retention, and service commitments when
  those capabilities and terms are actually implemented and published.

The current repository and single-node deployment evidence prove a bounded
managed shape. They do not yet prove high availability, an SLA, managed
backups, usage billing, or enterprise controls. Those must not be advertised
as live entitlements until separately implemented and validated.

## Packaging direction

| Offering | Value | Status |
| --- | --- | --- |
| OSS / self-hosted | Run the core workflow on infrastructure you operate | Available as source/reference path |
| Hyfens Cloud | Use the workflow without operating the control plane and storage | Backend plan identity is available; public prices and service terms remain Cloud-web policy |
| Enterprise self-hosted | Paid support, operational assistance, and additional controls | Future; do not claim as available |

Self-hosting is not a failed Cloud conversion. It is the adoption and
control path for teams with infrastructure, data-residency, or operational
requirements. Cloud is the convenience and service path.

## Source and implementation rule

The public/private source seam is documented in
[`OSS_CLOUD_SOURCE_BOUNDARY.md`](OSS_CLOUD_SOURCE_BOUNDARY.md):

- public OSS contains the reusable dashboard and self-hosted implementation;
- private Cloud contains marketing, CMS, and Cloud web operations; and
- future Cloud-only account, billing, entitlement, support, or hosted
  operations capabilities must sit behind an explicit control-plane/service
  interface rather than being scattered through the OSS runtime or CLI. The
  current control plane now provides the narrow plan identity and entitlement
  seam required by that interface; Cloud account creation, provider checkout,
  metering, and support operations remain outside this repository.

The current public repository is licensed under Apache 2.0. That license gives
third parties broad rights to use and commercially operate the public code.
This plan therefore does not rely on source secrecy as the business moat. Any
future license change or dual-licensing decision requires a separate legal and
maintainer review before public launch.

## Current plan-state seam

The managed control-plane process opts into `HYFENS_DEPLOYMENT_MODEL=cloud`.
In that mode, organization creation assigns an explicit internal `free`
Cloud plan without contacting Razorpay, and startup backfills the same state
for existing organizations. A registered active provider subscription takes
precedence, so paid workspaces are not downgraded by the Free backfill.

The default is `self_hosted`, which preserves the OSS deployment boundary.
Self-hosted organizations do not receive a Cloud subscription assignment and
do not enter the Cloud hierarchy `free < starter < team < enterprise`.

The existing billing projection exposes the backend Cloud catalog, effective
plan, deployment model, core entitlements, and authoritative usage for the
small countable boundaries. The active baseline is Free: 1 application, 1
environment per application, and 1 member; Starter: no application-count cap,
2 environments per application, and 5 members; Team: no application-count
cap, 10 environments per application, and 20 members; Enterprise: custom.
The Cloud marketing catalog presents those same enforced values. Storage,
bandwidth, patch-install, retention, overage, support, and SLA terms remain
outside the current contract until their measurement and commercial policies
are approved. The control plane remains authoritative for access and resource
admission state.

## Non-goals

This document does not add usage metering, quotas, payment processing,
overages, telemetry, SLA commitments, or enterprise feature gates. The narrow
Free assignment and effective-entitlement seam exists so those additions can
be made later without weakening the OSS workflow or creating a second
dashboard implementation.
