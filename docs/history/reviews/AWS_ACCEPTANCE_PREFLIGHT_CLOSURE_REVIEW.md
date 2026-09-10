# Task 79 — AWS acceptance preflight closure review

Date: 2026-08-25
Status: **LOCAL ACCEPTANCE PREFLIGHT — PASS**
AWS identity/apply: **EXTERNAL GATE — NOT RUN**

## 1. Recommendation

Recommendation: **PROCEED TO DISPOSABLE AWS ACCEPTANCE RUN WITH CONDITIONS**

This is a maintainer-review recommendation, not authorization to apply AWS.
The local candidate, trust checks, OpenTofu checks, teardown guards, and
control-plane suite are ready for a separately authorized disposable run.
The periodic-runner acceptance path remains explicitly blocked and must not be
represented as provider evidence.

Conditions:

- supply the approved account, principal, region, CIDR, budget, lifetime,
  ECR boundary, and non-patch OCI signing identity using the operator contract;
- fill and approve the current Mumbai cost worksheet;
- run the complete AWS acceptance matrix and export redacted immutable
  evidence before any beta, production, store, privacy, or legal claim;
- keep periodic reconciliation disabled until its exact-scope and raw
  lease-token host seam is separately reviewed.

## 2. Task 78 blocker baseline

Task 78 remains blocked at its maintainer-review boundary. Its SDK-based final
image had 17 CRITICAL and 81 HIGH findings; OCI signing/provenance and the
full control-plane suite were not clean; no AWS account, identity, ECR, or
provider resource was available. That evidence is preserved and has not been
overwritten. Task 79 closes only the local blockers authorized by its task
instruction.

## 3. Frozen architecture and authority

No Task 79 change weakens Architecture B, Patch Format v1, capability v1,
exact-release binding, state-v4 high-water, signed rollback, fail-closed
runtime verification, AOT fallback, customer/local patch signing, or
runtime-authoritative verification. PostgreSQL remains coordination authority;
immutable digest-addressed bytes, bounded reconciliation, audit-before-repair,
CAS/currentness/postconditions, exact tenant/application/environment
authorization, P3A rollout authority, and P3E-4 authority remain unchanged.
No queue, Redis, distributed scheduler, new repair path, or hosted signing
key custody was introduced.

## 4. Vulnerability triage

The historical scan is retained at
`docs/research/evidence/task78-aws-disposable/local/trivy.json`. Every old
CRITICAL/HIGH package finding is listed in
`docs/research/evidence/task79-preflight/vulnerability-triage.md` with CVE,
package/version, fixed version where available, layer, runtime relevance,
reachability, remediation, and one of the allowed explicit statuses. Old SDK
and build-layer findings are `NOT_PRESENT_IN_RUNTIME_STAGE` for the new final
image. The current OpenSSL advisory is separately classified
`NOT_REACHABLE_WITH_EVIDENCE`; it is not suppressed or called universally
false-positive.

## 5. Image hardening

The Dockerfile now uses a multi-stage build: Dart AOT binaries are compiled in
a pinned Dart 3.13 builder, then copied into a pinned
`gcr.io/distroless/base-debian13:nonroot` runtime. The runtime contains no Dart
SDK, package manager, source tree, compiler, or shell; it runs as
`nonroot:nonroot`. The root filesystem was tested read-only with a bounded
`/tmp` tmpfs. Both the image and ECS task definition use the compiled
`/app/health_check` executable, avoiding an SDK-at-runtime health-check bug.

Builder base:
`dart@sha256:8b6175f6c6b89aaf31ffdace4a22d17715c07f1cf3a772dadb10c658f779e23d`

Runtime base:
`gcr.io/distroless/base-debian13:nonroot@sha256:2d7d29b504e7166f6d0c7655a18ebf5def5b37b029f8c4f8667e434ba774844f`

## 6. Current image digest and runtime check

The exact ARM64 candidate is:

`sha256:68ae7017f9e7b93ff9d81d3944e161d25f89de171dabaac2660a77e4df48cb4b`

It is 16,326,581 bytes locally. After the 30-second start period, Docker
reported `health=healthy`; `/healthz` and `/readyz` returned HTTP 200. The
container was removed after the check. This is local container evidence, not
ECS/ALB evidence.

## 7. SBOM

Syft SPDX JSON was generated from the exact candidate using the pinned local
container tool. Evidence: `local/sbom.spdx.json`. SBOM SHA-256:

`06ebe87b9b27c59fb73fe91d580d75d87be301b82894756e9094ed8ab972ed2d`

The final runtime SBOM contains ten Debian base/runtime packages plus the
SPDX document metadata; build-stage SDK packages are absent.

## 8. Fresh vulnerability result

Trivy 0.56.2 result for the exact candidate:

| Severity | Count |
| --- | ---: |
| CRITICAL | 0 |
| HIGH | 1 |
| MEDIUM | 7 |
| LOW | 7 |
| UNKNOWN | 2 |

The one HIGH is `CVE-2026-14456` in `libssl3t64` with no fixed version in the
report. The current control plane uses Dart TCP HTTP and has no QUIC listener
or QUIC configuration; the triage records the source and the limits of that
evidence. A provider scan and maintainer review are still required.

## 9. OCI signing mechanics

Cosign v2.4.1 was exercised against a local HTTP OCI Registry 3 instance with
a disposable test key clearly labelled non-production. The exact candidate
digest was signed and verified. A wrong digest and an unsigned historical image
were rejected. The key, registry, and private material were removed after the
run. This proves **OCI SIGNING MECHANICS — PASS**, not ECR admission, key
custody, rotation, revocation, or production identity.

## 10. Provenance mechanics

A custom Cosign attestation was verified for the candidate. The predicate binds
the uncommitted source revision marker, Dockerfile digest, control-plane and
patch-format lock digests, OpenTofu lock digest, builder/runtime bases, exact
image digest, SBOM digest, Linux/ARM64 architecture, build timestamp, and a
`NON_PRODUCTION_TEST_ONLY` identity. Altering the Dockerfile caused the
pre-deploy verifier to reject the attestation. No SLSA-level claim is made.

## 11. Pre-deploy verification

`scripts/verify-predeploy-artifact.sh` fails closed on missing/mismatched
digest, invalid SPDX/Trivy data, unclassified CRITICAL/HIGH findings,
unapproved bases, wrong architecture, signature failure, missing attestation,
subject/material/SBOM/Dockerfile mismatch, or non-local misuse of the HTTP
registry option. The exact successful output and rejection tests are recorded
under `local/predeploy-verification.md`.

## 12. Crash-worker diagnosis and fix status

The two previously failing tests are:

- `PROCESS_KILL and CRASH_RESTART converge before and after CAS`;
- `malformed projection fails closed after restart`.

Each was run independently and in three bounded serial repetitions with
captured stdout/stderr and environment metadata. The failure investigation
found a test-helper race: the helper treated the process-exit notification as
authoritative before reading the terminal marker written immediately before
exit. The helper now checks the marker first and drains killed-child stdio
before launching recovery. The isolated crash-resilience file and the final
full serial suite pass after that correction. Classification:
`TEST_HARNESS_RACE / ENVIRONMENT_CONTENTION`; no production timeout or runtime
semantics changed.

## 13. Full control-plane result

The isolated serial full package suite completed with **240 passed, 34
explicit skips, exit code 0** (`dart test --concurrency=1`). The skips are
environment-gated integration cases; no failure was relabelled as a skip. The
campaign logs are under the package-local evidence directory
`packages/control_plane/docs/research/evidence/task79-preflight/crash-worker/`.

Two unconstrained full-suite attempts also exposed an existing timing-test
flakiness: `Task 67 measures bounded File critical path and contention
envelope` observed 3.29s and 5.65s against its 2s assertion while other test
processes were active. The same test passed in isolation (p95 1.94s), and the
serial full suite passed. The preflight therefore serializes test suites; no
production timeout, benchmark threshold, or runtime semantics were changed.

## 14. Periodic-runner host seam

The intended scope is the narrowest supported model: one exact configured
tenant/application/environment per service instance, not unbounded
multi-tenant enumeration. The current binary does not compose that scope or a
raw authoritative lease-token provider. `ControlPlaneHttpServer` only starts
an explicitly injected runner; `bin/control_plane.dart` does not inject one.
The ECS profile therefore keeps `HYFENS_RECONCILIATION_PERIODIC_ENABLED=false`.

Classification: **PERIODIC HOST WIRING — DESIGN BLOCKED**. No token was
fabricated, no request/diagnostic/metrics state was reused, and no second
repair path was added.

## 15. Control-plane versus runner acceptance readiness

| Path | Status | Boundary |
| --- | --- | --- |
| Control-plane AWS acceptance | READY TO TEST | Local image/trust/IaC/test blockers closed; AWS identity and all real provider gates remain external |
| Periodic-runner AWS acceptance | BLOCKED | Exact scope and raw lease-token host seam are not safely composed; runner remains disabled |

The control-plane acceptance matrix may exercise bounded manual/test paths
without claiming periodic-runner behavior.

## 16. OpenTofu validation

Containerized OpenTofu 1.10.0 passed recursive `fmt -check`,
`init -backend=false`, and `validate` against the local modules and lockfile.
No apply or destroy was run. A safe placeholder plan remains an operator
follow-up when a separate authorization permits it; no AWS identity was
needed for the checks recorded here.

## 17. Teardown safety

The runbook now requires all of: explicit destroy acknowledgement, exact
environment name, exact `ap-south-1` region, a 12-digit approved account ID,
the exact disposable scope tag, a redacted evidence-export directory and
sentinel, readable disposable state, matching state tags, and an authenticated
STS account match through the host AWS CLI. Missing state, tags, evidence,
`jq`, AWS CLI, or identity fails before `tofu destroy`; no unpinned CLI
fallback image is used. S3/ECR deletion controls remain false by default.

The disposable RDS profile intentionally has
`deletion_protection=false`/`skip_final_snapshot=true`; this is documented as
a teardown trade-off and is not production-retention evidence. Backup/PITR,
secret recovery, provider deletion, and actual teardown remain untested.

## 18. Operator-input contract

`aws-operator-inputs.md` specifies the account, principal, region, operator
CIDR, environment/scope tags, budget/lifetime, ECR boundary, non-patch OCI
identity, optional DNS/ACM inputs, and evidence destination. It contains no
secret values. `iam-preflight.md` defines separate provisioning, execution,
task, failover/restore, backup, and teardown permissions and records the
resource-scoped `rds:FailoverDBCluster` operation without executing it.

## 19. Cost guardrails

The existing guardrails remain unchanged: monthly envelope ≤ USD 250, one
test-run budget ≤ USD 75, and resource lifetime ≤ 24 hours. The cost worksheet
is a template only; it includes Fargate, RDS, S3, ALB, ECR, Secrets Manager,
CloudWatch, Backup, VPC endpoints/NAT if applicable, data transfer, and
Route53/ACM. No Mumbai price was fabricated and no cost acknowledgement was
made for AWS.

## 20. Evidence skeleton

The requested AWS files (`preflight.md`, `plan.md`, `supply-chain.md`,
`ecs-alb.md`, `rds-failover.md`, `s3-recovery.md`, `iam-secrets.md`,
`backup-pitr.md`, `tenant-network.md`, `capacity-soak.md`, `cost.md`, and
`teardown.md`) all say `Status: NOT_RUN` with the reason that AWS acceptance
is unauthorized/environment-unavailable. They contain no fabricated provider
results.

## 21. Local preflight command

`scripts/aws-disposable-preflight.sh` is credential-free by default. It checks
the exact candidate digest/ARM64 image, fresh SBOM/scan/policy, hardened
health-check assumptions, operator/evidence contracts, periodic-disabled
state, no local `terraform.tfvars`, OpenTofu format/init/validate, the
provider-neutral verifier, and the full control-plane suite. It exits nonzero
when the public key/signature inputs are absent. An explicit
`--aws-identity` phase is available later for account/region verification only
and still never applies or destroys resources.

The complete local invocation passed with the disposable registry/key;
evidence is `local/preflight-run.md`. The key and registry were removed.

## 22. Remaining AWS identity/environment gates

Still **NOT RUN / EXTERNAL GATE**: approved AWS account and principal,
current prices and quotas, ECR push/admission, ECS two-task/AZ/ALB behavior,
all-targets-unhealthy fail-closed behavior, real RDS failover/pool/advisory
lock recovery, S3 version/delete/outage recovery, IAM/secret rotation,
TLS/DNS, PITR/coupled restore, tenant/network isolation, capacity/soak,
actual cost, and complete teardown. Provider signing identity, key custody,
revocation, privacy/legal review, beta, production, and store approval also
remain open.

No AWS resource, credential, public endpoint, DNS record, ECR repository,
provider state, or production image was created by Task 79.

## 23. Next recommendation

Stop at maintainer review. **PROCEED TO DISPOSABLE AWS ACCEPTANCE RUN WITH
CONDITIONS** only after the operator contract and current cost inputs are
approved. Treat the periodic-runner path as blocked and keep all product,
beta, production, store, privacy, and legal claims closed until independent
evidence exists.
