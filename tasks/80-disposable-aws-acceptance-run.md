# Task 80 — Disposable AWS acceptance run

Status: [-] Blocked — explicit AWS operator, identity, and cost approvals are absent

## Goal

Execute one bounded disposable AWS acceptance run for the approved ARM64
control-plane candidate, capture redacted provider evidence, and destroy every
Task-80 resource before stopping at maintainer review.

## Scope and Non-goals

In scope after the hard preconditions are approved: AWS identity verification,
current Mumbai pricing, local preflight rerun, ECR admission, OpenTofu plan and
apply, ECS/Fargate, ALB, RDS failover, S3, IAM/secrets, recovery, bounded
capacity/soak, evidence export, teardown, and post-destroy inventory.

Out of scope: production deployment or traffic, DNS cutover, beta approval,
App Store/Google Play submission, privacy/legal approval, runtime/mobile/
compiler changes, new rollout authority, queues, Redis, distributed
schedulers, managed patch-signing KMS/HSM, hosted patch-signing private-key
custody, and periodic-runner provider acceptance.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 80 authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK80_DISPOSABLE_AWS_ACCEPTANCE_RUN.md`.
- Task 79 local preflight and hardened image evidence.
- Explicit maintainer-approved AWS account ID and principal/role.
- Approved operator CIDR, spend/lifetime guardrails, ECR boundary, non-patch
  OCI identity, evidence destination, and optional DNS/ACM inputs.
- A configured AWS CLI session that matches the approved account and region.

## Assumptions

- Region remains `ap-south-1`.
- Environment remains `hyfens-task78-disposable` with scope tag
  `disposable-task78`.
- Monthly envelope is at most USD 250, one run is at most USD 75, and resource
  lifetime is at most 24 hours unless explicitly changed by the maintainer.
- The approved candidate remains
  `sha256:68ae7017f9e7b93ff9d81d3944e161d25f89de171dabaac2660a77e4df48cb4b`.
- Customer/local patch signing remains separate from provider image signing.

## Work Items

- [x] Read the Task 80 authorization and current Task 79 review.
- [x] Inspect the repository operator-input and Mumbai cost contracts.
- [x] Audit the local AWS CLI, credential environment, and OpenTofu
  availability without exposing secret values.
- [-] Verify the approved AWS account, principal, active region, and credential
  expiry — blocked because no approved identity or AWS CLI session is present.
- [-] Fill and approve current Mumbai pricing — blocked because the worksheet
  remains a template and no approval record is present.
- [-] Run AWS identity, ECR, OpenTofu plan/apply, provider acceptance, and
  teardown — blocked by the hard preconditions; no AWS action was attempted.
- [x] Record the blocker and exact inputs required before resumption.

## Validation

Completed read-only checks:

- `command -v aws` — no AWS CLI found.
- AWS-related environment-name audit — no `AWS_*`,
  `HYFENS_PREFLIGHT_AWS_*`, `HYFENS_DISPOSABLE_*`, or `TF_VAR_*` names found.
- `command -v tofu` — no host OpenTofu found.
- Operator-input contract — `CONTRACT ONLY — values intentionally unfilled`.
- Cost worksheet — `TEMPLATE — current regional prices not entered`.
- No AWS STS, ECR, `tofu plan`, `tofu apply`, resource, DNS, or teardown call
  was made.

## Next Action

Provide an explicit maintainer approval record containing every hard
precondition listed in `docs/research/evidence/task80-aws-acceptance/
precondition-audit.md`, configure the approved AWS CLI session, and resume
Task 80 from identity verification. Do not infer approval from ambient
variables.

## Blockers

- No approved AWS account ID or principal/role.
- No AWS CLI or verified credential session in the workspace.
- No explicit operator CIDR.
- No approved non-patch OCI signing identity/ECR boundary.
- No approved evidence destination.
- Mumbai cost worksheet is unfilled and unapproved.

## Outcome

Task 80 did not begin provider acceptance. It is safely blocked before any
AWS mutation. Task 79 local evidence remains historical local evidence only;
it is not relabelled as provider acceptance.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK80_DISPOSABLE_AWS_ACCEPTANCE_RUN.md`
- `/Volumes/970EvoPlus/Downloads/AWS_ACCEPTANCE_PREFLIGHT_CLOSURE_REVIEW.md`
- [`Task 79`](79-aws-acceptance-preflight-closure.md)
- [`Task 79 review`](../docs/history/reviews/AWS_ACCEPTANCE_PREFLIGHT_CLOSURE_REVIEW.md)
- [`Operator-input contract`](../docs/research/evidence/task79-preflight/aws-operator-inputs.md)
- [`Cost worksheet`](../docs/research/evidence/task79-preflight/cost-worksheet.md)

## History

- 2026-08-25 — Task 80 reserved and hard-precondition audit performed.
- 2026-08-25 — Marked blocked before AWS identity, plan, apply, ECR, or
  provider resource action because explicit account/principal/cost approvals
  and required tooling/session are absent.
