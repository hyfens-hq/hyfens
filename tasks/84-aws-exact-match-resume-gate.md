# Task 84 — AWS exact-match resume gate

Status: [-] Blocked — Phase A approvals incomplete; local OpenTofu
artifact guard is not green

## Goal

Determine whether Task 80 may resume using the existing approval schemas and a
strict read-only gate. This task must stop before AWS identity queries when
either approval record is incomplete and must preserve zero provider mutation.

## Scope and Non-goals

In scope: reading the Task 83 source-of-truth records, checking approval and
cost completeness, revalidating local digest/periodic-runner/teardown guards,
recording the blocked resume decision, and updating the non-secret session and
resume evidence.

Out of scope: populating maintainer fields, reconciling decisions, current
pricing research while Phase A is blocked, AWS CLI/session installation or
configuration, STS/region queries, service/quota queries, OpenTofu
plan/apply/destroy, ECR/ECS/ALB/RDS/S3/IAM/Secrets Manager/CloudWatch/Backup/
DNS/ACM mutation, quota changes, teardown, and Task 80 execution.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 84 authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK84_AWS_EXACT_MATCH_RESUME_GATE.md`.
- Task 83 approval/resume records supplied at
  `/Volumes/970EvoPlus/Downloads/MAINTAINER_AWS_RESUME_AUTHORIZATION_REVIEW.md`
  and `/Volumes/970EvoPlus/Downloads/83-maintainer-aws-resume-authorization.md`.
- Existing records under `docs/research/evidence/task81-aws-bootstrap/`.
- Task 79 static candidate and teardown evidence.

## Assumptions

- The existing guardrails remain ≤ USD 75 per run, ≤ 24 hours resource
  lifetime, and ≤ USD 250 monthly envelope until explicitly changed and
  approved by the maintainer.
- The candidate digest remains
  `sha256:68ae7017f9e7b93ff9d81d3944e161d25f89de171dabaac2660a77e4df48cb4b`.
- The candidate OpenTofu method remains
  `PINNED_CONTAINER_OPENTOFU_1_10_0`.
- `PERIODIC_RUNNER_DISABLED=YES` remains required.

## Work Items

- [x] Read Task 84 and the supplied Task 83 source-of-truth records.
- [x] Confirm Phase A approval and cost completeness status.
- [x] Revalidate static candidate digest, periodic-runner, teardown, and
  provider-artifact guards without contacting AWS.
- [-] Run AWS CLI/session checks — prohibited because Phase A approvals remain
  incomplete.
- [-] Run STS account/principal/region exact match — not reached.
- [-] Complete current Mumbai pricing — prohibited while the approval stop
  trigger is active.
- [-] Set `TASK80_RESUME_READY=YES` — mandatory gates remain red.
- [x] Record `TASK80_RESUME_READY=NO` and `PROVIDER_MUTATION_COUNT=0`.

## Validation

Read-only checks completed on 2026-08-25:

- The maintainer approval remains `UNFILLED — NOT APPROVED` with required
  account, principal, CIDR, budget, ECR, OCI, evidence, DNS, method, approver,
  date, and Task 80 authorization fields absent.
- The cost worksheet remains `UNFILLED — NOT APPROVED`; no current Mumbai
  pricing was researched because Task 84 requires stopping at Phase A.
- The Task 83 session audit remains the latest safe AWS CLI/session evidence;
  Task 84 did not run STS, region, service, quota, or pricing queries.
- The candidate digest matches the static Task 79 references.
- `reconciliation_periodic_enabled` remains false and the periodic-runner
  evidence remains blocked/not tested.
- Teardown guard source still contains account, region, environment, scope,
  evidence, and explicit-destroy safeguards; the declared disposable state
  path and plan outputs are absent from the current scoped workspace. Local
  OpenTofu init metadata is recorded in the current recheck below.
- No credential, token, private key, or patch bytes were written to evidence;
  local OpenTofu metadata is recorded in the current recheck below.
- The recorded `PROVIDER_MUTATION_COUNT=0` is an audit assertion, not
  independent proof of metadata provenance.

Task 84 recheck completed on 2026-08-27 at 07:49:07 UTC:

The timestamp is recorded audit metadata and does not independently establish
local OpenTofu metadata provenance.

- The maintainer approval and cost worksheet remain `UNFILLED — NOT APPROVED`.
- Phase A therefore stopped before Phase B `aws --version`/approved-session
  verification, STS, configured-region, service, quota, and current-pricing
  queries. A local `command -v aws` availability probe returned **not found**;
  it did not verify an approved session. No credentials were inspected or
  configured.
- The candidate digest remains the exact static Task 79 digest, and the
  periodic-runner source/evidence guards remain disabled and blocked.
- Teardown source guards remain present: explicit account, region, environment,
  scope-tag, evidence-sentinel, destroy acknowledgement, and
  `allow_destroy=false` defaults.
- The provider-artifact/state absence guard is **NOT GREEN** because the two
  scanned artifact paths exist. The recheck recorded these three local
  OpenTofu metadata paths as present at the recheck, with provenance unverified:
  `deploy/aws/environments/disposable/.terraform.lock.hcl`,
  `deploy/aws/environments/disposable/.terraform/terraform.tfstate` (serial 1,
  zero resources), and
  `deploy/aws/environments/disposable/.terraform/modules/modules.json`. No
  `state/disposable.tfstate`, plan, `terraform.tfvars`, credential, secret, or
  provider output was found in the scoped check. The available evidence does
  not independently establish whether the metadata was created, modified, or
  deleted by the recheck.
- The scoped secret scan found no credential values, tokens, private-key
  markers, or patch bytes. The recorded `PROVIDER_MUTATION_COUNT=0` is an
  audit assertion, not independent proof of the metadata's provenance.

Coordinator-run validation record for the 2026-08-27 recheck:

These are local command exit/result summaries, not independent proof of AWS
state, metadata provenance, or the recorded timestamp.

- `markdownlint` over the four Task 84 evidence files: exit 0, **PASS**.
- Local relative-link checker over the same four files: exit 0, **PASS**.
- `rg` trailing-whitespace scan over the same four files: no matches, **PASS**.
- `bash -n` over the referenced guard scripts: exit 0, **PASS**.
- Static assertions over the Task 79 digest references, periodic-runner
  source/evidence, teardown source, and `allow_destroy` defaults: exit 0,
  **PASS**.
- Approval/cost completeness check over `maintainer-approval.md` and
  `cost-approval.md`: **BLOCKED_UNFILLED**; both records remain
  `UNFILLED — NOT APPROVED`.
- Secret scan over the scoped workspace, excluding `.git`, `.dart_tool`,
  `.terraform`, lock files, and JSON evidence: no matches, **PASS**.
- Artifact inventory using the `find` state/plan/tfvars pattern returned exactly
  these two paths, so provider-artifact absence is **NOT_GREEN**:
  `.terraform.lock.hcl` and `.terraform/terraform.tfstate`. A separate local
  metadata check found `.terraform/modules/modules.json`; `jq` reported serial
  1 and zero resources in the state metadata.

## Next Action

The maintainer must complete and approve the existing maintainer and cost
records. Only after both are green may the environment owner provide/configure
an approved short-lived AWS CLI v2 session. Then run only the required CLI
version, STS identity, and configured-region checks, compare exact values, and
revisit the resume manifest. The local OpenTofu metadata present at the recheck
must also be reviewed for provenance and disposition before a later gate can be
green; no cleanup is authorized by this task.

## Blockers

- Phase A approval record is incomplete.
- Current cost approval and pricing evidence are absent.
- AWS CLI/session and exact-match checks are intentionally not reached.
- Provider-artifact/state absence is not green because the two scanned artifact
  paths exist; three local OpenTofu metadata paths were present at recheck with
  provenance unverified.
- Task 80 remains paused and provider mutation is prohibited.

## Outcome

Task 84 remains blocked at Phase A. It preserved the approval schemas, updated
the non-secret session/resume evidence, revalidated the digest, periodic-runner,
and teardown guards, and recorded local OpenTofu metadata as present at the
recheck with provenance unverified. It stopped with
`TASK80_RESUME_READY=NO` and the recorded audit assertion
`PROVIDER_MUTATION_COUNT=0`.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK84_AWS_EXACT_MATCH_RESUME_GATE.md`
- `/Volumes/970EvoPlus/Downloads/MAINTAINER_AWS_RESUME_AUTHORIZATION_REVIEW.md`
- `/Volumes/970EvoPlus/Downloads/83-maintainer-aws-resume-authorization.md`
- [`Task 83`](83-maintainer-aws-resume-authorization.md)
- [`Task 83 review`](../docs/history/reviews/MAINTAINER_AWS_RESUME_AUTHORIZATION_REVIEW.md)
- [`Task 84 review`](../docs/history/reviews/AWS_EXACT_MATCH_RESUME_GATE_REVIEW.md)
- [`Resume-readiness manifest`](../docs/research/evidence/task81-aws-bootstrap/resume-readiness.md)

## History

- 2026-08-25 — Task 84 reserved and Phase A records read.
- 2026-08-25 — Approval stop trigger remained active; no AWS query or provider
  mutation was performed.
- 2026-08-27 — Rechecked the Phase A records and static guards. Approvals
  remain unfilled; the recheck record reports no AWS/provider action. Local
  OpenTofu metadata was recorded as present at the recheck with provenance
  unverified, making the artifact-absence guard a blocker.
