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
| Hyfens Cloud | Use the workflow without operating the control plane and storage | Managed service direction; public plans not yet announced |
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
  interface rather than being scattered through the OSS runtime or CLI.

The current public repository is licensed under Apache 2.0. That license gives
third parties broad rights to use and commercially operate the public code.
This plan therefore does not rely on source secrecy as the business moat. Any
future license change or dual-licensing decision requires a separate legal and
maintainer review before public launch.

## Non-goals

This document does not add billing, quotas, payment processing, plan
entitlements, telemetry, SLA commitments, or enterprise feature gates. It
freezes the packaging seam so those additions can be made later without
weakening the OSS workflow or creating a second dashboard implementation.
