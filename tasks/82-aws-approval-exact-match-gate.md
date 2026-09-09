# Task 82 — AWS approval completion and exact-match resume gate

Status: [-] Blocked — maintainer approval, current pricing approval, and an AWS CLI v2 session are absent

## Goal

Complete the explicit AWS approval inputs and perform the read-only exact-match
gate required before Task 80 may resume. This task must stop before provider
mutation.

## Scope and Non-goals

In scope: preserving the maintainer-owned approval boundary, auditing the AWS
CLI/session, recording the exact-match result, checking the static candidate
digest and periodic-runner guard, and documenting the resume decision.

Out of scope: inferring or filling approval values, installing/configuring
credentials, current-price estimation without an approved worksheet, AWS API
resource calls, ECR creation or push, OpenTofu plan/apply/destroy, ECS, ALB,
RDS, S3, IAM, Secrets Manager, CloudWatch, Backup, Route 53, ACM, quota
changes, teardown, and Task 80 execution.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 82 authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK82_AWS_APPROVAL_EXACT_MATCH_GATE.md`.
- Maintainer approval and pricing records under
  `docs/research/evidence/task81-aws-bootstrap/`.
- Task 81 bootstrap review and Task 80 blocked review.
- Task 79 local candidate and preflight evidence.
- An environment-owner-configured AWS CLI v2 short-lived session and explicit
  completed maintainer approval.

## Assumptions

- The Task 79 guardrails remain monthly ≤ USD 250, one run ≤ USD 75, and
  resource lifetime ≤ 24 hours.
- The candidate digest remains
  `sha256:68ae7017f9e7b93ff9d81d3944e161d25f89de171dabaac2660a77e4df48cb4b`
  until a live, approved ECR admission check proves otherwise.
- The pinned container execution path is the documented candidate:
  `ghcr.io/opentofu/opentofu:1.10.0`.
- Customer/local patch signing, runtime trust keys, and a disposable OCI
  identity remain separate.

## Work Items

- [x] Read the Task 82 authorization and supplied maintainer/review records.
- [x] Inspect task numbering, prior Task 79–81 evidence, and static guardrails.
- [x] Audit AWS CLI v2, host OpenTofu, and safe AWS environment-variable names.
- [x] Re-check the configured candidate digest and periodic-runner default.
- [-] Complete maintainer approval — the supplied record is explicitly
  `UNFILLED — NOT APPROVED`.
- [-] Complete current `ap-south-1` pricing and cost approval — the worksheet
  remains unfilled and no current prices were inferred.
- [-] Verify STS account/principal/region exact match — AWS CLI/session is not
  available and approval is absent.
- [-] Mark Task 80 resume-ready — every hard precondition is not satisfied.
- [x] Record provider mutation count as zero and stop at maintainer review.

## Validation

Read-only checks completed on 2026-08-25:

- `command -v aws` — no AWS CLI found; no version or identity call was run.
- `command -v tofu` — no host OpenTofu found; the documented containerized
  OpenTofu 1.10.0 method remains a future approved execution choice.
- AWS-related environment-name audit — no `AWS_*`,
  `HYFENS_PREFLIGHT_AWS_*`, `HYFENS_DISPOSABLE_*`, or `TF_VAR_*` names found.
- The supplied maintainer approval remains unfilled; no values were inferred.
- The current-pricing/cost worksheet remains unfilled; Mumbai prices are
  `PRICE_UNVERIFIED` and no cost approval was claimed.
- Static candidate digest matches the Task 79 expected digest in the checked-in
  preflight configuration and evidence. No live registry admission was run.
- `reconciliation_periodic_enabled` defaults to `false`, and the preflight
  guard requires that value. The periodic runner remains disabled/not tested.
- No STS, ECR, OpenTofu, AWS resource, DNS, quota, or teardown operation was
  attempted. `PROVIDER_MUTATION_COUNT=0`.
- No credential, token, private key, raw state, or secret value was written to
  repository evidence.

## Next Action

The maintainer must complete and approve both
[`maintainer-approval.md`](../docs/research/evidence/task81-aws-bootstrap/maintainer-approval.md)
and [`cost-approval.md`](../docs/research/evidence/task81-aws-bootstrap/cost-approval.md),
then configure AWS CLI v2 with a short-lived session through the approved
environment-owner path. Re-run only `aws sts get-caller-identity` and
`aws configure get region`, compare safe metadata exactly, and return to Task
80 only if every hard gate passes.

## Blockers

- Account ID, principal/profile, operator CIDR, ECR boundary, OCI identity,
  evidence destination, DNS/ACM decision, approver, and approval date are
  absent.
- Current Mumbai pricing and an approved test-cost estimate are absent.
- AWS CLI v2 and a matching short-lived session are unavailable.
- Task 80 provider action remains prohibited by the Task 82 authorization.

## Outcome

Task 82 is blocked at the exact-match resume gate. It preserved the
maintainer-owned approval templates, recorded safe local/session evidence,
confirmed no provider mutation, and did not authorize or begin Task 80.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK82_AWS_APPROVAL_EXACT_MATCH_GATE.md`
- `/Volumes/970EvoPlus/Downloads/maintainer-approval.md`
- `/Volumes/970EvoPlus/Downloads/AWS_OPERATOR_APPROVAL_SESSION_BOOTSTRAP_REVIEW.md`
- [`Task 81`](81-aws-operator-approval-session-bootstrap.md)
- [`Task 81 review`](../docs/history/reviews/AWS_OPERATOR_APPROVAL_SESSION_BOOTSTRAP_REVIEW.md)
- [`Task 82 review`](../docs/history/reviews/AWS_APPROVAL_EXACT_MATCH_GATE_REVIEW.md)
- [`Resume-readiness manifest`](../docs/research/evidence/task81-aws-bootstrap/resume-readiness.md)

## History

- 2026-08-25 — Task 82 reserved and read-only environment/approval audit run.
- 2026-08-25 — Exact-match gate stopped because the maintainer approval,
  pricing approval, AWS CLI v2, and session were absent. No provider action
  occurred.
