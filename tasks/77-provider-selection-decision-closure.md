# Task 77 — provider selection decision closure

Status: [x] Completed

## Goal

Close the provider-selection research gate with current official evidence,
an explicit managed-container recommendation, editable cost assumptions, and
provider-specific acceptance conditions, while preserving the existing
runtime, delivery, rollout, reconciliation, audit, and signing boundaries.

## Scope and Non-goals

In scope: compare AWS, Google Cloud, and Microsoft Azure managed-container
profiles; evaluate managed PostgreSQL, object storage, edge/TLS, private
networking, IAM/workload identity, secrets, registry, observability, backup
and PITR, image supply chain, India-region availability, pricing inputs,
RPO/RTO targets, capacity assumptions, and provider acceptance tests; record
one proposed provider profile and one proposed ADR.

Out of scope: provider resources, accounts, credentials, DNS, public
endpoints, infrastructure-as-code, provider SDKs, runtime/mobile/compiler
changes, Patch Format/capability changes, signing-service changes, queues,
Redis, distributed schedulers, rollout/P3A/P3E-4 changes, dashboards,
managed KMS/HSM, store submission, privacy/legal approval, beta approval,
production deployment, and production claims.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 76 provider-neutral deployment design.
- Task 75 provider-resilience/readiness baseline.
- Tasks 71–74 bounded reconciliation, observability, periodic-runner, and
  crash/lock-loss evidence.
- `docs/adr/0010-self-hosted-deployment.md`.
- `docs/security/productization-threat-model.md`.
- Explicit authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK77_PROVIDER_SELECTION_DECISION_CLOSURE.md`.

## Assumptions

- Architecture B/source instrumentation, Patch Format v1, capability v1,
  exact-release binding, state-v4 high-water, signed rollback, fail-closed
  verification, AOT fallback, customer/local signing, and runtime-authoritative
  verification remain frozen.
- PostgreSQL remains the coordination and metadata authority; immutable object
  bytes remain digest-addressed and untrusted from the runtime's perspective.
- `BoundedReconciliationService` remains the only repair path and
  `ReconciliationPeriodicRunner` remains orchestration only.
- India is the initial deployment geography hypothesis, not a customer,
  privacy, data-residency, or legal decision.
- Provider documentation establishes capability claims only. Failover,
  transaction ambiguity, advisory-lock/session recovery, edge fail-closed
  behavior, cost, and production readiness require later provider tests.

## Work Items

- [x] Research current official AWS, Google Cloud, and Microsoft Azure
  managed-container, PostgreSQL, object, edge/TLS, identity, registry,
  backup, supply-chain, region, and pricing documentation.
- [x] Build a documented hard-gate matrix with `DOCUMENTED`,
  `PROVIDER TEST REQUIRED`, `UNSUPPORTED`, and `UNKNOWN` classifications.
- [x] Compare PostgreSQL failover/session/advisory-lock behavior, object
  versioning/recovery, readiness-aware edge routing, private networking,
  identity/secrets, image digest deployment, and supply-chain controls.
- [x] Define DEV, EARLY BETA, and SMALL PRODUCTION HYPOTHESIS workload
  scenarios with editable cost inputs and 10x/2x sensitivity checks.
- [x] Apply the predeclared weighted rubric and recommend exactly one first
  managed-container profile without treating the score as provider evidence.
- [x] Define the runner model, endpoint exposure, RPO/RTO targets, capacity
  and pool hypotheses, acceptance tests, and a later soak plan.
- [x] Add a factual provider-selection threat-model addendum and create a
  proposed provider-selection ADR.
- [x] Validate documentation links, whitespace, secret/prohibited-scope
  boundaries, source completeness, pricing completeness, and frozen
  architecture invariants.
- [x] Stop at maintainer review; do not implement or provision the selected
  profile.

## Validation

Executed validation:

- Official-source URL host allowlist, local-link review, and retrieval-date
  capture: PASS. A live fetch smoke check was PARTIAL for dynamic pricing
  pages; those pages were not used for fabricated numeric totals.
- Provider matrix, hard-gate, PostgreSQL, object, edge/TLS, region, pricing,
  cost-scenario, scorecard, security, supply-chain, RPO/RTO, capacity,
  acceptance-test, and open-gate completeness review: PASS.
- Markdownlint, local-link, whitespace, high-confidence secret, and
  prohibited-scope scans over Task 77 documents: PASS.
- Architecture/frozen-boundary, ADR status, no-resource/no-credential, and
  no-new-dependency checks: PASS.
- No provider API, credential, account, DNS, public endpoint, IaC apply,
  runtime/mobile/compiler, P3A, or P3E-5 source change was made.

Commands and scoped outcomes:

- `markdownlint docs/PROVIDER_SELECTION_DECISION_REVIEW.md
  docs/research/provider-selection-sources.md docs/adr/0014-provider-selection.md
  docs/adr/README.md docs/security/productization-threat-model.md
  docs/research-log.md tasks/77-provider-selection-decision-closure.md` — PASS.
- A Python relative-link checker over the seven changed documentation/task
  files — PASS; no missing local links.
- `rg` trailing-whitespace/tab and high-confidence private-key/secret-marker
  scans over the changed scope — PASS.
- A Python source-completeness check for the 29 review sections, provider
  names, evidence classifications, final recommendation, and explicit
  non-authorization boundary — PASS.
- Weighted-score arithmetic check — PASS (`451.5`, `434.5`, `416.2`).
- Provider URLs were restricted to official AWS, Google Cloud, and Microsoft
  Azure hosts. Dynamic pricing pages that timed out in one local HTTP pass
  were not used for fabricated numeric totals; the detailed source ledger
  records every such meter as `UNVERIFIED` where applicable.
- Dart/Flutter tests were not run because this task changed only research,
  task, ADR, and threat-model documentation and explicitly forbids runtime or
  provider implementation.

## Next Action

Stop at the maintainer-review gate. If and only if the maintainer approves
the proposed profile and conditions, create a separately authorized,
disposable provider implementation task. Re-run current pricing and execute
the provider acceptance tests before any beta or production claim.

## Blockers

The documentation decision is complete. Implementation remains blocked by
maintainer approval and external provider evidence for real PostgreSQL
failover/transaction ambiguity/pool recovery/advisory-lock behavior, active
readiness edge fail-closed behavior, object recovery/durability, supply-chain
verification, TLS/network/IAM/secrets, cost, capacity, soak, and the existing
independent-app, power-loss, iOS, provider-production, store, privacy, and
legal gates.

## Outcome

Current evidence supports the recommendation
`PROCEED TO DISPOSABLE PROVIDER IMPLEMENTATION WITH CONDITIONS` with AWS
ECS/Fargate, an active ALB, RDS PostgreSQL Multi-AZ DB cluster, S3, ACM/
Route 53, VPC, ECS task IAM roles, Secrets Manager, ECR, CloudWatch, and
AWS Backup in Mumbai (`ap-south-1`) as the first disposable profile. This is
a proposed selection, not an approval or production-readiness claim. GCP
Cloud Run/Cloud SQL/Cloud Storage and Azure Container Apps/Azure Database for
PostgreSQL/Blob Storage remain documented alternatives subject to their own
provider tests and current pricing.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK77_PROVIDER_SELECTION_DECISION_CLOSURE.md`
- `/Volumes/970EvoPlus/Downloads/76-provider-deployment-design.md`
- `/Volumes/970EvoPlus/Downloads/PROVIDER_DEPLOYMENT_DESIGN_REVIEW.md`
- [`docs/PROVIDER_SELECTION_DECISION_REVIEW.md`](../docs/history/reviews/PROVIDER_SELECTION_DECISION_REVIEW.md)
- [`docs/adr/0014-provider-selection.md`](../docs/adr/0014-provider-selection.md)
- [`docs/security/productization-threat-model.md`](../docs/security/productization-threat-model.md)
- AWS, Google Cloud, and Microsoft Azure official sources linked in the
  decision review.

## History

- 2026-08-25 — Task 77 reserved under explicit decision-closure
  authorization. Research was limited to official provider documentation and
  current public pricing pages; no provider resource or credential was used.
- 2026-08-25 — Provider matrix, hard gates, cost scenarios, weighted score,
  proposed AWS-first profile, threat-model addendum, and proposed ADR were
  completed. Validation passed. Final recommendation is
  `PROCEED TO DISPOSABLE PROVIDER IMPLEMENTATION WITH CONDITIONS`; stop for
  maintainer review.
