# Task 81 — AWS operator approval and session bootstrap

Status: [-] Blocked — maintainer approval record, AWS CLI session, and cost approval are absent

## Goal

Close the explicit operator, account, identity, cost, and tooling gates needed
before Task 80 may resume. This task must not create or mutate AWS resources.

## Scope and Non-goals

In scope: approval templates, cost-approval template, safe AWS/tool/session
audit, exact-match gate definition, permission-boundary documentation, ECR and
non-patch OCI identity separation, operator CIDR/DNS/evidence decisions, pinned
OpenTofu execution method, and a maintainer review.

Out of scope: AWS identity calls before session confirmation, ECR creation or
push, OpenTofu plan/apply/destroy, ECS, ALB, RDS, S3, IAM mutation, Secrets
Manager, CloudWatch, Backup, Route 53, ACM, quota increases, provider
acceptance, runtime/mobile/compiler changes, and periodic-runner work.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 81 authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK81_AWS_OPERATOR_APPROVAL_SESSION_BOOTSTRAP.md`.
- Task 80 blocked record and review.
- Task 79 local candidate and preflight evidence.
- Explicit maintainer approval values and an AWS CLI v2 session supplied by the
  environment owner.

## Assumptions

- Region remains `ap-south-1` unless the maintainer explicitly changes it.
- Task 79 guardrails remain monthly ≤ USD 250, one run ≤ USD 75, and lifetime
  ≤ 24 hours.
- Candidate image remains
  `sha256:68ae7017f9e7b93ff9d81d3944e161d25f89de171dabaac2660a77e4df48cb4b`.
- Customer/local patch signing, runtime trust keys, and provider OCI identity
  remain separate.

## Work Items

- [x] Read Task 81 authorization and Task 80 blocked evidence.
- [x] Audit AWS CLI, host OpenTofu, and safe credential-environment names.
- [x] Create an unpopulated maintainer approval record.
- [x] Create an unpopulated current-pricing/cost approval record.
- [x] Document the exact identity, principal, region, CIDR, ECR, OCI, DNS,
  evidence, and OpenTofu gates.
- [-] Receive explicit maintainer approvals — no approval values were supplied.
- [-] Verify AWS STS exact match — AWS CLI/session is unavailable.
- [-] Resume Task 80 provider actions — prohibited until every gate passes.

## Validation

Read-only audit completed on 2026-08-25:

- `command -v aws` — no AWS CLI found.
- `command -v tofu` — no host OpenTofu found; Task 79's pinned container path
  remains the documented future option.
- AWS-related environment-name audit — no `AWS_*`,
  `HYFENS_PREFLIGHT_AWS_*`, `HYFENS_DISPOSABLE_*`, or `TF_VAR_*` names found.
- No STS, ECR, OpenTofu, AWS resource, DNS, or teardown call was made.
- New approval/cost templates pass scoped Markdownlint and secret scanning.

## Next Action

The maintainer must complete and approve [`maintainer-approval.md`](../docs/research/evidence/task81-aws-bootstrap/maintainer-approval.md)
and [`cost-approval.md`](../docs/research/evidence/task81-aws-bootstrap/cost-approval.md),
then provide/configure AWS CLI v2 with a short-lived session. Resume with
`aws sts get-caller-identity` and `aws configure get region`; record only safe
identity metadata and compare it exactly to the approved record.

## Blockers

- Account ID, principal/role, operator CIDR, ECR boundary, OCI identity,
  evidence destination, and DNS/ACM decision are unapproved.
- Current Mumbai pricing and cost approval are absent.
- AWS CLI v2 and a matching session are unavailable.

## Outcome

Task 81 created the required approval/session bootstrap artifacts and stopped
before provider action. It did not populate approval fields, install/configure
credentials, or resume Task 80.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK81_AWS_OPERATOR_APPROVAL_SESSION_BOOTSTRAP.md`
- `/Volumes/970EvoPlus/Downloads/DISPOSABLE_AWS_ACCEPTANCE_RUN_REVIEW.md`
- `/Volumes/970EvoPlus/Downloads/80-disposable-aws-acceptance-run.md`
- [`Task 80`](80-disposable-aws-acceptance-run.md)
- [`Task 80 review`](../docs/history/reviews/DISPOSABLE_AWS_ACCEPTANCE_RUN_REVIEW.md)
- [`Task 79 operator contract`](../docs/research/evidence/task79-preflight/aws-operator-inputs.md)
- [`Task 79 cost worksheet`](../docs/research/evidence/task79-preflight/cost-worksheet.md)

## History

- 2026-08-25 — Task 81 reserved; Task 80 remains blocked before provider
  action.
- 2026-08-25 — Created unpopulated maintainer/cost templates and recorded the
  absent AWS CLI/session and approval inputs. No AWS mutation occurred.

## Maintainer-facing approval block

```text
AWS DISPOSABLE ACCEPTANCE APPROVAL

AWS_ACCOUNT_ID:
AWS_PRINCIPAL_ARN_OR_PROFILE:
AWS_REGION: ap-south-1
OPERATOR_CIDR:

MAX_TEST_SPEND_USD: 75
MAX_RESOURCE_LIFETIME_HOURS: 24

ECR_REPOSITORY_BOUNDARY:
OCI_SIGNING_IDENTITY:
EVIDENCE_DESTINATION:

DNS_ACM_DECISION: NOT_USED | DISPOSABLE_DNS_APPROVED
DISPOSABLE_DNS_ZONE_OR_SUBDOMAIN:

MUMBAI_COST_WORKSHEET_APPROVED: YES | NO
APPROVED_BY:
APPROVAL_DATE:

I AUTHORIZE TASK 80 TO RESUME AFTER AWS STS IDENTITY
MATCHES THE VALUES ABOVE: YES | NO
```
