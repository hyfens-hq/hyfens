# Task 83 — Maintainer AWS resume authorization

Status: [-] Blocked — maintainer inputs, current cost approval, and an AWS CLI v2 session are absent

## Goal

Obtain and validate the maintainer-owned inputs required to authorize a later
Task 80 disposable AWS acceptance run. This task performs only the read-only
identity/resume gate and must end with zero provider mutation.

## Scope and Non-goals

In scope: preserving the single approval schema, auditing the supplied
maintainer and cost records, checking AWS CLI/session availability, recording
the exact-match/resume decision, and revalidating static candidate, periodic
runner, and teardown guards.

Out of scope: inferring or filling approvals, installing/configuring
credentials, AWS provider calls before explicit approval, current-price
research while the approval stop trigger is active, OpenTofu plan/apply/destroy,
ECR/ECS/ALB/RDS/S3/IAM/Secrets Manager/CloudWatch/Backup/DNS/ACM mutation,
quota changes, teardown, and Task 80 execution.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 83 authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK83_MAINTAINER_AWS_RESUME_AUTHORIZATION.md`.
- The single approval and cost records under
  `docs/research/evidence/task81-aws-bootstrap/`.
- Task 82 exact-match review and Task 80 blocked review.
- Task 79 local candidate and preflight evidence.
- An environment-owner-configured AWS CLI v2 short-lived session and explicit
  completed maintainer approval.

## Assumptions

- The existing guardrails remain ≤ USD 75 per test run, ≤ 24 hours resource
  lifetime, and ≤ USD 250 monthly envelope until explicitly changed by the
  maintainer.
- The candidate digest remains
  `sha256:68ae7017f9e7b93ff9d81d3944e161d25f89de171dabaac2660a77e4df48cb4b`
  until a live approved ECR admission check proves otherwise.
- The documented pinned container method is
  `PINNED_CONTAINER_OPENTOFU_1_10_0` using
  `ghcr.io/opentofu/opentofu:1.10.0`.
- Customer/local patch signing, runtime trust keys, and a disposable OCI
  identity remain separate.

## Work Items

- [x] Read the Task 83 authorization and supplied Task 82/resume records.
- [x] Inspect the repository task/evidence state and prior static guardrails.
- [x] Audit AWS CLI v2, host OpenTofu, and safe AWS environment-variable names.
- [x] Recheck that the candidate digest is unchanged and periodic runner is
  disabled.
- [-] Complete maintainer approval — all maintainer-owned values remain blank.
- [-] Complete current `ap-south-1` pricing and cost approval — the worksheet
  remains unfilled; no price was inferred.
- [-] Verify STS account/principal/region exact match — AWS CLI/session is
  unavailable and no approved target exists.
- [-] Set `TASK80_RESUME_READY=YES` — mandatory gates are not green.
- [x] Record provider mutation count as zero and stop at maintainer review.

## Validation

Read-only checks completed on 2026-08-25 at 10:38:43 UTC:

- `command -v aws` — no AWS CLI found; no version or identity call was run.
- `command -v tofu` — no host OpenTofu found; no plan or provider operation
  was run.
- AWS-related environment-name audit — no `AWS_*`,
  `HYFENS_PREFLIGHT_AWS_*`, `HYFENS_DISPOSABLE_*`, or `TF_VAR_*` names found.
- The supplied and repository maintainer approval records remain explicitly
  `UNFILLED — NOT APPROVED`; no values were populated or inferred.
- The cost worksheet remains unfilled. Current Mumbai pricing is
  `PRICE_UNVERIFIED`; no cost approval was claimed.
- The static candidate digest remains the Task 79 expected digest in checked-in
  configuration/evidence. Live registry admission was not run.
- The ECS module and preflight guard keep `reconciliation_periodic_enabled`
  false; the periodic runner remains blocked/not tested.
- No STS, ECR, OpenTofu, AWS resource, service/quota, DNS, or teardown action
  was attempted. `PROVIDER_MUTATION_COUNT=0`.
- Secret scan found no credential value, token, private key, raw state, or
  patch bytes written to repository evidence.

## Next Action

The maintainer must complete and approve
[`maintainer-approval.md`](../docs/research/evidence/task81-aws-bootstrap/maintainer-approval.md)
and [`cost-approval.md`](../docs/research/evidence/task81-aws-bootstrap/cost-approval.md),
then configure AWS CLI v2 with an approved short-lived session. Only then run
`aws sts get-caller-identity` and `aws configure get region`, compare account,
principal, and region exactly, complete current Mumbai pricing, and revisit the
resume manifest.

## Blockers

- Account, principal/profile, CIDR, budget, lifetime, ECR boundary, OCI
  identity, evidence destination, DNS decision, OpenTofu method approval,
  approver/date, and explicit Task 80 authorization are incomplete.
- Current official Mumbai pricing and cost approval are absent.
- AWS CLI v2 and a matching short-lived session are unavailable.
- Task 80 provider mutation is prohibited by Task 83.

## Outcome

Task 83 remains blocked at maintainer input completion. It preserved the
single approval schema, updated the existing non-secret audit artifacts,
recorded the safe environment recheck, and stopped with
`PROVIDER_MUTATION_COUNT=0`.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK83_MAINTAINER_AWS_RESUME_AUTHORIZATION.md`
- `/Volumes/970EvoPlus/Downloads/resume-readiness.md`
- `/Volumes/970EvoPlus/Downloads/82-aws-approval-exact-match-gate.md`
- [`Task 82`](82-aws-approval-exact-match-gate.md)
- [`Task 82 review`](../docs/history/reviews/AWS_APPROVAL_EXACT_MATCH_GATE_REVIEW.md)
- [`Task 83 review`](../docs/history/reviews/MAINTAINER_AWS_RESUME_AUTHORIZATION_REVIEW.md)
- [`Resume-readiness manifest`](../docs/research/evidence/task81-aws-bootstrap/resume-readiness.md)

## History

- 2026-08-25 — Task 83 reserved; supplied approval/resume records read.
- 2026-08-25 — Safe CLI/session recheck found no AWS CLI, no host OpenTofu,
  and no AWS environment names. Approval remained unfilled; no provider action
  occurred.
