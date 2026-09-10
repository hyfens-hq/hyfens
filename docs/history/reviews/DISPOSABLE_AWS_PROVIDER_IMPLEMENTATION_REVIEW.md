# Task 78 disposable AWS provider implementation review

Date: 2026-08-25
Status: **LOCAL IMPLEMENTATION COMPLETE — AWS ACCEPTANCE ENVIRONMENT-GATED**
Scope: non-production, disposable AWS profile only

This review stops at maintainer review as required by Task 78. It does not
accept ADR 0014, authorize production/customer traffic, or make beta, App
Store, Google Play, privacy, legal, or production-readiness claims.

## Decision summary

The provider implementation is sufficiently concrete for a separately
authorized disposable AWS acceptance run, but the acceptance gate is not
closed. No AWS account, credential, DNS record, public endpoint, or provider
resource was created by Task 78.

**Recommendation: PROCEED WITH CONDITIONS** — approve a disposable AWS run
only after an operator supplies an approved account identity, current
`ap-south-1` price worksheet, an explicit operator CIDR, a remediation decision
for the rejected image scan, and an approved OCI signing/provenance identity.
Keep all hard provider gates open until the evidence matrix below is actually
executed and teardown is verified.

## Implemented locally

- OpenTofu 1.10.0-compatible layout under `deploy/aws/`, with AWS provider
  `6.61.0` pinned in `.terraform.lock.hcl`.
- Three-AZ VPC module with public ALB subnets, private ECS/RDS subnets, S3
  gateway endpoint, and ECR/Logs/Secrets Manager/STS interface endpoints.
- Explicit operator-CIDR ingress, ALB-to-task security-group ingress, and
  task-to-PostgreSQL security-group ingress. PostgreSQL is not public.
- Two-task Fargate ECS service, ALB `/readyz` target health, 30-second
  container stop timeout, rolling deployment circuit breaker, and AZ spread.
- RDS PostgreSQL Multi-AZ DB cluster resource shape with three AZs, encrypted
  storage, automated backup/PITR retention, and RDS-managed Secrets Manager
  master credentials.
- Private/versioned AES-256 S3 artifact bucket, bounded noncurrent retention,
  TLS-only bucket policy, and task permissions limited to list/get/put under
  the `artifacts/` prefix. Delete and signing authority are not granted to the
  task role.
- ECR repository with immutable tags and task-definition rejection of mutable
  image references; CloudWatch log retention; bounded AWS Backup vault/plan.
- Optional ACM/Route 53 module that remains inactive without explicit domain,
  hosted-zone, and DNS-change inputs. An external validated certificate ARN
  may be supplied independently.
- ECS task-role credential provider for the existing S3 SigV4 adapter. Static
  access/secret keys cannot be combined with task-role mode. Logical digest
  keys remain unchanged while AWS objects are namespaced under `artifacts/`.
- Database component environment variables construct the PostgreSQL URI in
  memory; the password is injected from the RDS-managed secret JSON field.
- Runbooks for exact-digest local image build and explicitly acknowledged
  disposable teardown.

No runtime/mobile/compiler, patch authority, rollout authority, reconciliation
repair path, or signing-key custody boundary was changed.

## Local evidence

| Evidence | Result | Details |
| --- | --- | --- |
| Dart targeted tests | PASS | S3 adapter/task-role/prefix and configuration tests pass |
| Dart analysis | PASS | `dart analyze` in `packages/control_plane` reports no issues |
| Container image build | PASS | ARM64 build from pinned Dart manifest; `dart pub get --enforce-lockfile` |
| Local container `/healthz` | PASS | HTTP 200 |
| Local container `/readyz` | PASS | HTTP 200 with file-store readiness |
| OpenTofu init | PASS | OpenTofu 1.10.0, AWS provider 6.61.0 installed and locked |
| OpenTofu format/validate | PASS | Recursive `fmt -check` and `validate` pass |
| Cost guardrail plan | PASS | Explicit acknowledgement/budget preconditions pass in a targeted plan; false acknowledgement is rejected |
| Full control-plane test suite | **NOT CLEAN** | 238 passed, 34 skipped due missing PostgreSQL/MinIO integration env, 2 existing crash-worker restart cases failed with child exit/no stderr; unrelated to the provider adapter and must be rechecked before release claims. Exit code 1 |

Local supply-chain files are in
`docs/research/evidence/task78-aws-disposable/local/`:

- image digest: `sha256:cc34b5dc4f570d99927e1ac3990c2606278897b84cd5e0b272aba5c4a8bacc0d`;
- base manifest digest:
  `sha256:8b6175f6c6b89aaf31ffdace4a22d17715c07f1cf3a772dadb10c658f779e23d`;
- Syft SPDX SBOM: `sbom.spdx.json`;
- Trivy `0.56.2` scan: 17 CRITICAL, 81 HIGH, 122 MEDIUM, 125 LOW, 22
  UNKNOWN findings in the Dart SDK image. This is a **deployment rejection**,
  not a claim that all findings are exploitable in the final workload.

OCI signing, registry admission, and provenance verification were not run
because no approved registry/signing identity is available. The local image
is not eligible for ECS deployment on this evidence alone.

## AWS acceptance matrix

| Gate | Result | Required evidence |
| --- | --- | --- |
| AWS account/identity and price worksheet | ENVIRONMENT-GATED | AWS CLI/credentials absent; record account boundary, current prices, budget, and expiry |
| ECR exact digest push/admission | NOT_RUN | Push only after scan remediation and approved OCI signature/provenance verification |
| Two-task AZ placement | NOT_RUN | ECS task IDs, AZs, desired/running counts, task definition digest |
| ALB `/readyz`, drain, replacement | NOT_RUN | Target health and rolling replacement evidence |
| All-targets-unhealthy fail-closed | NOT_RUN | ALB documented fail-open edge plus application-level rejection evidence |
| RDS writer failover/pool recreation | NOT_RUN | Real writer failover, transaction ambiguity, endpoint reconnect, pool recovery |
| Advisory lock loss/reacquisition | NOT_RUN | Session loss, lock handoff, exactly one semantic repair |
| Private/versioned S3 recovery | NOT_RUN | IAM path, delete-marker/version restore, exact-byte digest rehash |
| Secret/TLS rotation | NOT_RUN / ENVIRONMENT-GATED | RDS secret rotation and optional ACM/Route 53 only with explicit domain inputs |
| PITR and coupled restore | NOT_RUN | Restored PostgreSQL metadata plus matching object digest evidence |
| Tenant/network isolation | NOT_RUN | Cross-tenant/operator rejection and SG/VPC endpoint tests |
| Capacity/soak/cost | NOT_RUN | Bounded load, connection pool, outage/restart, runtime and actual cost |
| Teardown | NOT_APPLICABLE | No resources were created; once applied, run and verify `destroy-disposable.sh` |

The existing serving binary also does not safely compose an exact
tenant/application/environment periodic invocation with a raw lease-token
provider. The ECS profile leaves `HYFENS_RECONCILIATION_PERIODIC_ENABLED`
false by default. Enabling a scheduler without that seam would advertise a
repair path that cannot satisfy the existing lease/CAS contract.

## Open blockers

1. Approved AWS credentials/account boundary are absent from this host.
2. Current price inputs and account-level cost data are not captured.
3. The base SDK image scan is rejected and needs a remediation decision.
4. OCI signature/provenance verification and ECR admission are unexecuted.
5. All provider hard gates, including real RDS failover, S3 recovery, ALB
   fail-open behavior, PITR/coupled restore, capacity, and teardown, remain
   unverified.
6. Two existing crash-worker restart tests are not clean in the final full
   local suite; this must be diagnosed before any production-grade claim.
7. Periodic runner host wiring remains an explicit integration follow-up.

## Maintainer review boundary

The implementation may be reviewed and corrected locally. Do not apply AWS,
create DNS, push a public image, mark ADR 0014 Accepted, or claim production
readiness until the maintainer authorizes the gated acceptance run and every
hard condition receives immutable redacted evidence.

## Task 79 factual addendum (2026-08-25)

Task 78's SDK-image result remains historical and rejected. Task 79 produced a
separate AOT/distroless ARM64 candidate at
`sha256:68ae7017f9e7b93ff9d81d3944e161d25f89de171dabaac2660a77e4df48cb4b`.
Its fresh Trivy result is 0 CRITICAL, 1 HIGH, 7 MEDIUM, 7 LOW, and 2 UNKNOWN;
the one HIGH (`CVE-2026-14456`) has an explicit evidence-backed
`NOT_REACHABLE_WITH_EVIDENCE` status for the current TCP-only service and is
not suppressed. Local test-only OCI signing/provenance and fail-closed
verification passed. The ECS health check now invokes the compiled
`/app/health_check` binary present in the hardened runtime image.

The two earlier crash-worker failures were reproduced as isolated passes in
three repetitions each, followed by a full control-plane run with 240 passed,
34 explicit skips, and exit code zero. They are classified as harness/process
contention rather than a proven product defect; no blind timeout change was
made. The periodic runner remains disabled because the serving binary does
not compose exact tenant/application/environment authority and a raw
lease-token provider.

These facts close only local Task 79 preflight work. AWS identity, ECR
admission, provider resources, failover/recovery, cost, teardown, beta,
production, and store/legal gates remain open.
