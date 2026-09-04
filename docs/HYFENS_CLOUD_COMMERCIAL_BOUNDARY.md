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
| OSS / self-hosted | Run the core workflow on infrastructure you operate | Available as public source and deployment reference |
| Hyfens Cloud | Use the workflow without operating the control plane and storage | Managed service direction; only implemented capabilities are advertised |
| Enterprise self-hosted | Paid support, operational assistance, and additional controls | Future; not a current entitlement |

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

See [OSS/Cloud source boundary](OSS_CLOUD_SOURCE_BOUNDARY.md) and [dashboard and web product separation](architecture/dashboard-separation.md).
