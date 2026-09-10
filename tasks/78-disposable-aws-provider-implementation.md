# Task 78 — disposable AWS provider implementation

Status: [-] Blocked — approved disposable AWS account/identity and supply-chain identity are unavailable

## Goal

Build and test the smallest non-production AWS profile selected by Task 77,
then capture bounded provider evidence and destroy the disposable resources.
The implementation must fit the existing runtime, delivery, rollout,
reconciliation, audit, CAS, tenant, runner, readiness, and signing
boundaries.

## Scope and Non-goals

In scope: OpenTofu 1.x disposable AWS infrastructure in `ap-south-1`;
two ECS/Fargate control-plane tasks; ALB `/readyz` routing and fail-open
testing; private RDS PostgreSQL Multi-AZ failover/PITR; private/versioned S3;
ECR image digest/SBOM/provenance verification; IAM task/execution roles;
Secrets Manager; CloudWatch; bounded cost guardrails; provider acceptance
tests; evidence; and complete teardown.

Out of scope: production deployment or DNS cutover; customer traffic; beta,
store, privacy, legal, or production approval; runtime/mobile/compiler
changes; new rollout/P3A/P3E-4 behavior; queues; Redis; distributed
schedulers; new repair paths; managed KMS/HSM or hosted patch-signing key
custody; dashboards; percentage rollouts; and unrelated refactors.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 77 provider-selection decision closure.
- Approved disposable profile in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK78_DISPOSABLE_AWS_PROVIDER_IMPLEMENTATION.md`.
- Task 75 provider-resilience/readiness baseline and Tasks 71–74 bounded
  reconciliation/observability/runner/crash evidence.
- Existing `packages/control_plane` and `deploy/p2` deployment seams.
- An AWS account boundary and credentials with explicit disposable-resource
  authorization. The current host audit found neither AWS CLI nor AWS
  credential/config files; provider apply is therefore an environment-gated
  step until credentials are supplied through an approved mechanism.

## Assumptions

- Architecture B, Patch Format v1, capability v1, exact-release binding,
  state-v4 high-water, signed rollback, fail-closed verification, AOT
  fallback, customer/local patch signing, and runtime-authoritative
  verification remain unchanged.
- PostgreSQL remains coordination/metadata authority;
  `BoundedReconciliationService` remains the only repair path; and
  `ReconciliationPeriodicRunner` remains orchestration only.
- The control plane may gain a narrowly scoped AWS ECS task-role credential
  adapter if required to use IAM without static S3 keys. This is provider
  integration only; it must not alter patch/runtime authority or add a new
  repair/rollout path.
- Initial disposable cost guardrails are USD 250 maximum expected monthly
  envelope, USD 75 maximum test-run spend, and a 24-hour maximum resource
  lifetime. Teardown must be run immediately after evidence capture and no
  later than the lifetime limit. These are operator guardrails, not AWS
  billing guarantees.
- A disposable DNS name/certificate may be unavailable. TLS/DNS is then
  `ENVIRONMENT_GATED` and must not be represented as passed.

## Work Items

- [x] Create pinned OpenTofu disposable AWS modules/environment, state and
  destroy safeguards, tags, network rules, cost guardrails, and runbooks.
- [x] Build the control-plane image with a pinned base digest and exact
  digest input; generate SBOM, vulnerability, OCI-signature, and provenance
  evidence or record the missing-tool/provider gate.
- [-] Apply only after credential, region, cost, and preflight gates pass;
  record provider operation/resource IDs in the evidence directory.
- [-] Prove two-task multi-AZ placement, `/readyz` routing, drain/replacement,
  and ALB all-unhealthy application fail-closed behavior.
- [-] Prove real RDS writer failover, pool recreation, advisory-lock
  loss/reacquisition, transaction ambiguity handling, and exactly one
  semantic repair.
- [-] Prove private/versioned S3 access, outage/recovery, delete/version
  recovery, exact-byte digest verification, lifecycle safety, and coupled
  PostgreSQL/PITR/object restore consistency.
- [-] Prove IAM least privilege, secret rotation, TLS/DNS status,
  cross-tenant/operator rejection, network failure recovery, and bounded
  CloudWatch redaction.
- [-] Run capacity baseline and disposable soak where cost/time permits;
  record explicit `PASS`, `NOT_RUN`, or `ENVIRONMENT_GATED` results.
- [-] Export evidence, capture actual cost data where accessible, execute and
  verify complete teardown, and write the final implementation review.
- [x] Stop at maintainer review; do not mark ADR 0014 Accepted or claim
  production/beta/store/legal readiness.

## Validation

Planned scoped validation:

- `tofu fmt -check`, `tofu validate`, reviewed `tofu plan`, and policy/static
  scans for `deploy/aws`.
- `docker build`, exact image digest capture, SBOM, vulnerability scan, OCI
  signature/provenance verification, and pre-deploy rejection tests.
- Root Dart formatting/analyze/tests plus affected control-plane tests,
  including S3/IAM credential-provider, readiness, reconciliation, runner,
  observability, and crash/lock-loss suites.
- Disposable AWS acceptance matrix: ECS/ALB, RDS failover, advisory lock,
  S3 recovery, IAM/secrets, TLS/DNS, PITR, tenant isolation, network outage,
  capacity, soak, cost, and teardown.
- Repository Markdownlint, links, whitespace, secret, prohibited-scope,
  shell/Python syntax, and evidence-manifest validation.

## Next Action

Complete local IaC and image/evidence preflight first. Do not run `tofu apply`
until AWS identity, exact region, cost guardrails, image digest, and required
operator inputs are available and recorded.

## Blockers

- **Environment-gated:** AWS CLI/provider credentials and account boundary are
  absent on the current host; no AWS resource action can be executed yet.
- **Tool-gated:** OpenTofu, Syft, Trivy, Cosign/Notation, and AWS CLI are not
  installed as host binaries. OpenTofu/Syft/Trivy containerized checks are
  available; Cosign/Notation and AWS CLI identity/provider operations remain
  `NOT_RUN` until an approved equivalent and registry/account boundary exist.
- **Architecture seam:** the current S3 adapter accepts static SigV4 keys or
  a fixed authorization header, not ECS task-role metadata credentials. A
  narrowly scoped adapter enhancement is required before an IAM-only ECS task
  can exercise private S3.
- **Runner seam:** the serving binary does not yet compose the existing
  periodic runner with an exact tenant/application/environment invocation and
  a safe raw lease-token provider. The disposable ECS profile therefore keeps
  periodic execution disabled rather than advertising an unsafe scheduler or
  adding a second repair path.

## Outcome

Local implementation is complete enough for maintainer review. OpenTofu
format/init/validate, targeted Dart tests, image build, local health/readiness,
SBOM generation, and vulnerability scanning were executed. The vulnerability
scan rejected the SDK image and OCI signing/provenance were not run. AWS apply,
provider acceptance, and teardown remain environment-gated. No AWS resource,
credential, DNS record, public endpoint, or provider state has been created by
Task 78.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK78_DISPOSABLE_AWS_PROVIDER_IMPLEMENTATION.md`
- `/Volumes/970EvoPlus/Downloads/0014-provider-selection.md`
- `/Volumes/970EvoPlus/Downloads/PROVIDER_SELECTION_DECISION_REVIEW.md`
- [`tasks/77-provider-selection-decision-closure.md`](77-provider-selection-decision-closure.md)
- [`docs/PROVIDER_SELECTION_DECISION_REVIEW.md`](../docs/history/reviews/PROVIDER_SELECTION_DECISION_REVIEW.md)
- [`docs/adr/0014-provider-selection.md`](../docs/adr/0014-provider-selection.md)
- [`deploy/p2/README.md`](../deploy/p2/README.md)

## History

- 2026-08-25 — Task 78 reserved under disposable AWS implementation
  authorization. Preflight found no AWS CLI, OpenTofu, supply-chain tools,
  AWS credential/config files, or AWS credential environment variables.
- 2026-08-25 — Local implementation scope and blockers recorded. No provider
  resource or external state mutation performed.
- 2026-08-25 — Added IAM-only ECS task-role S3 credentials, logical artifact
  key-prefix support, managed PostgreSQL secret-component configuration,
  pinned OpenTofu modules, local image/SBOM/scan evidence, and a fail-closed
  runner integration note. AWS apply remains environment-gated.
- 2026-08-25 — Validation: OpenTofu 1.10.0 `fmt -check`, `init`, and
  `validate` passed; targeted S3/config tests and `dart analyze` passed;
  final ARM64 image health/readiness checks passed. Full control-plane tests
  reported 238 passed, 34 skipped integration cases, and two existing
  crash-worker restart failures (child exit with no stderr); this remains an
  open validation follow-up. The exit code was 1.
- 2026-08-25 — Final scoped validation reconfirmed Dart formatting, analyzer,
  S3/config tests (11 tests), OpenTofu recursive format/validate, shell syntax,
  and secret-pattern checks. No AWS credentials or provider account boundary
  became available, so the task remains at the maintainer-review gate.
- 2026-08-25 — Task 79 factual addendum: the historical SDK-based image and
  its 17 CRITICAL/81 HIGH findings remain preserved as rejected evidence. A
  fresh ARM64 AOT/distroless candidate was built at
  `sha256:68ae7017f9e7b93ff9d81d3944e161d25f89de171dabaac2660a77e4df48cb4b`
  (0 CRITICAL, 1 HIGH, 7 MEDIUM, 7 LOW, 2 UNKNOWN). The remaining HIGH
  (`CVE-2026-14456`) is explicitly triaged
  `NOT_REACHABLE_WITH_EVIDENCE` for the current TCP-only control-plane path;
  provider admission still requires its own review.
- 2026-08-25 — Task 79 factual addendum: both crash-worker cases passed in
  three isolated repetitions each, and an isolated full control-plane run
  exited zero with 240 passed and 34 explicit skips. The earlier failures
  were classified as test-harness/process contention; no timeout or product
  semantics change was made. Periodic execution remains disabled because the
  exact scope/lease-token host seam is not composed.
- 2026-08-25 — Task 79 factual addendum: local test-only OCI signature,
  provenance attestation, wrong-digest/unsigned rejection, tamper rejection,
  provider-neutral verification, teardown guards, operator/cost contracts,
  and a credential-free preflight script were added. No AWS identity, ECR
  push, apply, resource, DNS, endpoint, or provider state was created.
