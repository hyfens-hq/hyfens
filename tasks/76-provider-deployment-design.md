# Task 76 — provider deployment design

Status: [x] Completed

## Goal

Define the concrete deployment architecture and operational contracts required
for a future disposable provider implementation while preserving the validated
runtime, patch, rollout, reconciliation, audit, CAS, tenant, runner, metrics,
readiness, and trust boundaries.

## Scope and Non-goals

In scope: a provider option matrix; stateless control-plane deployment;
managed PostgreSQL and object-storage contracts; advisory-lock failover
semantics; active `/readyz`-aware edge routing; TLS/DNS/network/IAM/secrets
design; deployment, image, SBOM, vulnerability, migration, rollback, backup,
RPO/RTO, capacity, autoscaling, soak, observability, audit, operator, incident,
cost, privacy, store-policy, and provider-specific validation boundaries.

Out of scope: provider selection approval; provider resources; credentials;
DNS changes; public endpoints; production or beta deployment; provider SDKs;
runtime/mobile/compiler changes; Patch Format/capability/trust changes; queues;
Redis; distributed schedulers; rollout writers; P3A/P3E-4 mutation; managed
patch-signing KMS/HSM; dashboards; store submission; privacy/legal approval.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 75 provider-neutral resilience/readiness evidence.
- Tasks 71–74 bounded reconciliation, observability, periodic runner, and
  crash/lock-loss evidence.
- `docs/adr/0010-self-hosted-deployment.md` staged self-hosting boundary.
- `docs/security/productization-threat-model.md` productization threat model.
- Explicit authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_PROVIDER_DEPLOYMENT_DESIGN.md`.

## Assumptions

- Architecture B, Patch Format v1, capability v1, exact-release binding,
  state-v4 high-water, signed rollback, fail-closed verification, AOT fallback,
  customer/local signing, and runtime-authoritative verification remain frozen.
- PostgreSQL remains the coordination and metadata authority.
- Immutable object bytes remain content-addressed, digest verified, and
  untrusted from the runtime's perspective.
- `BoundedReconciliationService` remains the only repair path and
  `ReconciliationPeriodicRunner` remains orchestration only.
- Provider capabilities and current pricing are not established merely by
  this design document; unresolved items remain maintainer or external gates.

## Work Items

- [x] Create the provider decision matrix and explicit provider decision gate.
- [x] Define stateless compute, PostgreSQL, advisory ownership, object-store,
  edge, TLS, DNS, network, IAM, and secret contracts.
- [x] Define deployment pipeline, immutable image/SBOM/provenance,
  vulnerability, migration, mixed-version, rolling-upgrade, and rollback
  boundaries.
- [x] Define backup/PITR, RPO/RTO targets, provider failover tests, capacity,
  autoscaling, connection-pool, and soak plans.
- [x] Define observability, logging, audit, operator access, incident runbooks,
  cost model, regional/privacy/store boundaries, and implementation entry
  criteria.
- [x] Update the threat model and self-hosted ADR reference; validate the
  documentation package and stop at maintainer review.

## Validation

Executed validation:

- Markdownlint over the review, task, threat-model, and ADR documents: PASS.
- Local-link and whitespace scans: PASS.
- High-confidence secret scan: PASS.
- Prohibited-scope/dependency scan: PASS after review of intentional
  out-of-scope mentions.
- Architecture consistency checks for PostgreSQL, object, readiness, TLS,
  IAM, SBOM, RPO/RTO, rollback, soak, cost, privacy, and provider gates: PASS.
- Existing HA Compose configuration with disposable variables: PASS.
- No deploy/provider tree, provider resource, credential, public endpoint,
  dependency, or runtime/control-plane source implementation was added.

## Next Action

Stop at the maintainer-review gate. Do not begin provider implementation or
select a provider automatically.

## Blockers

No blocker remains inside the authorized documentation scope. Provider,
region, managed-service, edge/TLS, IAM/secrets, current-pricing,
image-supply-chain, and production implementation decisions remain intentionally
unresolved until maintainer approval and provider-specific evidence.

## Outcome

The provider-neutral design package is complete. It recommends
`CONTINUE PROVIDER DEPLOYMENT DESIGN` because provider selection, current
pricing, and provider-specific implementation gates remain unresolved. No
provider resource or implementation was created.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_PROVIDER_DEPLOYMENT_DESIGN.md`
- `/Volumes/970EvoPlus/Downloads/P3E5_5F_PROVIDER_RESILIENCE_READINESS_REVIEW.md`
- `docs/P3E5_5F_PROVIDER_RESILIENCE_READINESS_REVIEW.md`
- [`docs/PROVIDER_DEPLOYMENT_DESIGN_REVIEW.md`](../docs/history/reviews/PROVIDER_DEPLOYMENT_DESIGN_REVIEW.md)
- [`docs/adr/0010-self-hosted-deployment.md`](../docs/adr/0010-self-hosted-deployment.md)
- [`docs/security/productization-threat-model.md`](../docs/security/productization-threat-model.md)
- `deploy/p2/docker-compose.ha.yml`
- `deploy/p2/nginx-ha.conf`

## History

- 2026-08-25 — Task 76 reserved under explicit design-only authorization.
  No provider resource, credential, public endpoint, or implementation work is
  authorized.
- 2026-08-25 — Provider matrix, deployment contracts, failover test plan,
  capacity/cost/soak plans, threat-model and ADR addenda were completed.
  Documentation, link, syntax, secret, and prohibited-scope validation passed.
  Final disposition is `CONTINUE PROVIDER DEPLOYMENT DESIGN`; stop for
  maintainer review.
