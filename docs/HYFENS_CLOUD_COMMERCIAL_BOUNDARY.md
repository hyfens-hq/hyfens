# Hyfens Cloud commercial boundary

Status: AUTHORITATIVE — adopted 2026-09-04

Hyfens combines an Apache-2.0 open-source core with a private managed Cloud
service. Customers may operate the core themselves; Cloud customers pay
Hyfens to operate managed infrastructure and provide Cloud-only services.

## What remains public OSS

The public repository provides a complete self-hosted baseline:

- Flutter runtime, verifier, patch format, compiler, and instrumenter;
- `hyfens` CLI and compatibility shim;
- control plane, shared identity/API contracts, and self-host deployment;
- Customer/Instance Workspace for organization, application, environment,
  delivery, team, credentials, support contract, audit, and settings; and
- documented release, patch, deploy, verify, promote, and rollback protocols.

Self-hosting must not require a private Cloud repository, Cloud credentials,
global staff identity, or managed-service account. The OSS
`hyfens-dashboard` image is the customer/instance web image only.

## What belongs to private Cloud

The private `hyfens-cloud-web` project owns the managed product composition:

- marketing, CMS, and Cloud account onboarding;
- billing, subscriptions, commercial projections, and plan/entitlement
  administration;
- Cloud Customer Workspace extensions for managed-service context;
- the global Platform Console at `platform.hyfens.com`;
- global customer/organization inspection;
- Cloud support queue, staff-only notes, and staff administration; and
- managed fleet/provider operations and platform audit.

These surfaces operate Hyfens's managed business/platform. They are not
required for an ordinary self-hosted installation and are not included in the
public dashboard artifact.

## Shared product contract

Cloud and OSS use compatible identity, session, discovery, customer API, and
authorization contracts. The Cloud Customer Workspace should reuse the public
customer lifecycle through a documented/versioned contract rather than
maintaining a copied implementation. Shared contracts do not make private
commercial or Platform Console code part of OSS.

The control plane currently retains bounded platform projections as a public
API/security contract. If commercial, support, staff, or managed-operation
backend logic is later privatized, that is a separate compatibility and
authorization migration; the frontend source boundary does not silently
remove public APIs.

## Editions

| Offering | Value | Status |
| --- | --- | --- |
| OSS / self-hosted | Run the core workflow on infrastructure you operate | Available as source/reference path |
| Hyfens Cloud | Use the workflow without operating the control plane and storage | Backend plan identity is available; public prices and service terms remain Cloud-web policy |
| Enterprise self-hosted | Paid support, operational assistance, and additional controls | Future; do not claim as available |

Cloud convenience includes hosted control-plane and artifact-delivery
infrastructure, managed authentication/storage/TLS/upgrades, and Cloud support
where those capabilities and terms are actually implemented and published.
The repository does not claim HA, SLA, managed backups, usage billing, or
enterprise controls without separate evidence.

## Licensing

The public OSS repository is licensed under the Apache License 2.0. Previously
published OSS dashboard artifacts remain public and immutable; moving future
Platform Console source to the private Cloud repository does not rewrite
history or retroactively revoke Apache rights. The commercial boundary relies
on managed service and operations, not on making the core customer workflow
unavailable to self-hosters.

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
