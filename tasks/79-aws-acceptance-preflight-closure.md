# Task 79 — AWS acceptance preflight closure

Status: [x] Completed

## Goal

Close every AWS acceptance blocker that can be closed locally, then stop at
maintainer review with a truthful `LOCAL ACCEPTANCE PREFLIGHT` result and an
explicit external AWS identity/apply gate.

## Scope and Non-goals

In scope: runtime-image hardening and vulnerability triage; local SBOM,
signature, provenance, and fail-closed pre-deploy mechanics; crash-worker
restart diagnosis; periodic-runner host-scope classification; OpenTofu and
teardown safety review; operator-input, cost, and AWS-evidence contracts; a
credential-free local preflight command; targeted and full local validation;
and factual Task 78/security/research-log addenda.

Out of scope: `tofu apply`; AWS resource creation; ECR push; DNS/ACM; public
endpoints; production or beta approval; store/privacy/legal approval; runtime,
mobile, compiler, Patch Format, capability, rollout, reconciliation repair,
queue, Redis, distributed scheduler, managed signing custody, or hosted
patch-signing key changes.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 78 disposable AWS implementation and its local evidence.
- Task 79 authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK79_AWS_ACCEPTANCE_PREFLIGHT_CLOSURE.md`.
- Existing Architecture B, runtime trust, control-plane, reconciliation,
  tenant, runner, and security boundaries.
- Local Docker/Dart/OpenTofu-equivalent tooling; AWS identity remains an
  external gate and is not required for local preflight.

## Assumptions

- The previous Task 78 image digest remains historical evidence and will not
  be overwritten if a remediation rebuild is produced.
- Any test-only OCI key is disposable, clearly non-production, never
  committed, and never reused for patch signing.
- A missing exact periodic scope or lease-token provider remains a design
  blocker; the runner will stay disabled rather than fabricate authority.
- The USD 250 monthly envelope, USD 75 test-run cap, and 24-hour lifetime
  guardrails remain unchanged.

## Work Items

- [x] Inspect the old image SBOM/Trivy findings and produce per-CRITICAL/HIGH
  vulnerability triage with evidence-backed statuses.
- [x] Harden the runtime image where justified, rebuild ARM64, and record a
  fresh digest, SBOM, and vulnerability result without deleting historical
  evidence.
- [x] Validate disposable local OCI signing and verification mechanics,
  provenance binding/verification, and a fail-closed provider-neutral
  pre-deploy verifier.
- [x] Reproduce and classify both crash-worker restart failures; fix only a
  proven defect and require the full control-plane suite to exit zero.
- [x] Classify the periodic-runner scope/token seam and keep it disabled if
  the existing architecture cannot safely provide exact authority.
- [x] Validate OpenTofu no-apply checks and teardown guards; review resource
  retention/deletion safety.
- [x] Create operator-input, cost-worksheet, AWS-evidence skeleton, and local
  preflight contracts.
- [x] Run consolidated local validation and update Task 78, security threat
  model, and research log with factual addenda.
- [x] Write the Task 79 review and stop at maintainer review without AWS apply.

## Validation

Planned validation includes scoped Dart formatting/analyze/tests; crash-worker
reproduction and bounded repetition; full control-plane and root suites where
available; exact ARM64 image build, SBOM, Trivy, OCI signing/provenance and
pre-deploy rejection tests; OpenTofu format/init/validate and safe no-apply
plan checks; teardown script syntax/guards; secret/prohibited-scope/link/
whitespace/shell checks; and local preflight execution.

## Next Action

Maintainer review of `docs/AWS_ACCEPTANCE_PREFLIGHT_CLOSURE_REVIEW.md`. If
approved separately, execute the bounded disposable AWS acceptance matrix with
the operator-input and cost contracts. Never infer AWS readiness from this
local task or enable the periodic runner without its exact-scope/lease seam.

## Blockers

No local blocker remains. The external AWS account, credentials, registry, and
provider signing identity are intentionally unavailable and remain an external
gate outside this authorization; they prevent provider acceptance execution,
not local Task 79 completion.

## Outcome

`LOCAL ACCEPTANCE PREFLIGHT — PASS`. The historical SDK-image rejection is
preserved; the fresh AOT/distroless ARM64 candidate, SBOM, Trivy triage, local
OCI signature/provenance mechanics, fail-closed verifier, crash-worker
diagnosis, isolated full control-plane suite, OpenTofu checks, teardown
guards, operator/cost contracts, and evidence skeletons are complete. The
control-plane AWS acceptance path is ready to test; periodic-runner AWS
acceptance is explicitly blocked by the missing exact scope/raw lease-token
host seam and remains disabled. AWS identity, apply, ECR, resources, provider
acceptance, beta, production, and store/legal gates remain external/not run.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK79_AWS_ACCEPTANCE_PREFLIGHT_CLOSURE.md`
- `/Volumes/970EvoPlus/Downloads/DISPOSABLE_AWS_PROVIDER_IMPLEMENTATION_REVIEW.md`
- `/Volumes/970EvoPlus/Downloads/78-disposable-aws-provider-implementation.md`
- [`tasks/78-disposable-aws-provider-implementation.md`](78-disposable-aws-provider-implementation.md)
- [`docs/DISPOSABLE_AWS_PROVIDER_IMPLEMENTATION_REVIEW.md`](../docs/history/reviews/DISPOSABLE_AWS_PROVIDER_IMPLEMENTATION_REVIEW.md)
- [`docs/security/productization-threat-model.md`](../docs/security/productization-threat-model.md)

## History

- 2026-08-25 — Task 79 reserved under local-only acceptance-preflight
  authorization. No AWS identity or resource action is authorized.
- 2026-08-25 — Closed local Task 79 work: fresh candidate digest
  `sha256:68ae7017f9e7b93ff9d81d3944e161d25f89de171dabaac2660a77e4df48cb4b`,
  SBOM/scan/triage, AOT/distroless hardening, local signature/provenance,
  fail-closed verifier, and the compiled ECS health-check correction.
- 2026-08-25 — Crash-worker cases passed in three isolated repetitions each;
  the isolated full control-plane suite exited zero with 240 passed and 34
  explicit skips. The failure diagnosis found a marker-vs-exit ordering race
  in the test helper; terminal-marker checking now precedes exit handling and
  killed-child stdio is drained before relaunch. No production timeout or
  runtime semantics changed.
- 2026-08-25 — Periodic host wiring was explicitly classified
  `PERIODIC HOST WIRING — DESIGN BLOCKED`; the disposable profile remains
  disabled. OpenTofu/teardown safety, operator/IAM/cost contracts, AWS
  evidence skeletons, and `scripts/aws-disposable-preflight.sh` completed.
- 2026-08-25 — Consolidated validation passed root and control-plane analysis,
  root tests, shell syntax, scoped Markdownlint (excluding existing line-
  length policy), secret scans, OpenTofu checks, local trust verification, and
  the serial full local suite. The preflight uses `--concurrency=1` because
  unconstrained runs intermittently exceeded the existing Task 67 timing
  assertion under test-process contention; no runtime threshold was changed.
  No AWS apply/resource action occurred.
- 2026-08-25 — Final credential-free `scripts/aws-disposable-preflight.sh`
  invocation passed with an ephemeral local registry/test key, exact digest,
  signature/provenance verification, OpenTofu checks, and 240 passed/34
  skipped control-plane tests. The registry and key were removed immediately
  after validation.
- 2026-08-25 — Final post-fix validation repeated root/package analysis,
  root tests, the serial control-plane suite, shell syntax, credential scan,
  and scoped Markdownlint; all passed. No temporary registry or private key
  remains.
