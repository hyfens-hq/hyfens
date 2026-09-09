# ADR 0014 — proposed first provider profile

Status: Proposed — maintainer approval required

Date: 2026-08-25

## Context

Task 76 defined a provider-neutral deployment contract but intentionally did
not select a provider. Task 77 compared current official AWS, Google Cloud,
and Microsoft Azure documentation and public pricing inputs against the
frozen Architecture B/runtime, Patch Format v1, capability v1, exact-release,
state-v4, signed-rollback, fail-closed, PostgreSQL-coordination,
immutable-object, reconciliation, runner, audit, tenant, and P3A/P3E-4
boundaries.

## Decision proposed

Use the following as the first disposable implementation profile, subject to
maintainer approval and the provider acceptance tests in the selection review:

- stateless control plane: AWS ECS services on Fargate, at least two tasks
  across availability zones;
- active edge: Application Load Balancer with TLS termination, draining, and
  `/readyz` target eligibility, plus an application-level fail-closed check;
- metadata/coordination: Amazon RDS for PostgreSQL Multi-AZ DB cluster with a
  writer endpoint, private VPC access, automated backups, and PITR;
- immutable artifact bytes: private Amazon S3 bucket with versioning,
  least-privilege access, digest-addressed keys, and an approved retention /
  delete-recovery policy;
- certificates and DNS: AWS Certificate Manager and Route 53, subject to
  maintainer ownership and domain approval;
- identity and secrets: ECS task IAM roles and AWS Secrets Manager; no static
  credentials in images or source;
- image supply chain: private Amazon ECR, immutable digest deploys, SBOM,
  vulnerability, OCI signature, provenance, and pre-deploy verification;
- logs/metrics/backups: CloudWatch and AWS Backup, with retention and access
  values selected during implementation.

Initial geography recommendation is Mumbai (`ap-south-1`); Hyderabad
(`ap-south-2`) is the documented alternative. This is a latency/availability
hypothesis, not a residency or legal approval.

## Hard conditions

This proposal does not pass the implementation gate until a disposable
environment proves, at minimum:

1. two-task placement, active readiness routing, graceful drain, and rolling
   replacement;
2. RDS writer failover, connection-pool recreation, ambiguous transaction
   handling, and session-scoped advisory-lock loss/reacquisition with exactly
   one semantic repair;
3. private S3 access, version/delete recovery, exact-byte rehash, and
   lifecycle protection for active artifacts;
4. TLS rotation, private network paths, workload identity, secret injection,
   and no static credential leakage;
5. immutable image digest deployment, SBOM/vulnerability/OCI-signature /
   provenance policy enforcement;
6. backup/PITR restore with metadata and artifact digest consistency;
7. capacity, connection-pool, outage, restart, rolling-upgrade, and soak
   evidence; and
8. no regression of the frozen runtime trust, audit, CAS, tenant, rollout,
   reconciliation, runner, or rollback authorities.

AWS ALB documentation says routing can fail open when all registered targets
are unhealthy. The implementation must therefore test that condition and
retain an application-level fail-closed guard; a nominal target-health check
alone is not accepted as proof of safe delivery.

## Alternatives considered

- **Google Cloud:** Cloud Run, Cloud SQL for PostgreSQL, Cloud Storage,
  external Application Load Balancer, Artifact Registry, Secret Manager, and
  service accounts. Strong managed fit, but readiness probes are Preview,
  min-instance placement is best effort, Cloud Run sends `SIGTERM` and only
  allows 10 seconds before `SIGKILL`, and multi-region health behavior needs
  provider testing.
- **Microsoft Azure:** Azure Container Apps, Azure Database for PostgreSQL
  Flexible Server, Blob Storage, Container Registry, Key Vault, managed
  identities, and Front Door. Strong identity/edge fit, but Central India
  currently marks new zone-redundant PostgreSQL HA deployments temporarily
  blocked; South India requires a separate service/price/HA test.
- **Kubernetes:** rejected for the first disposable profile because it adds
  cluster, ingress, node, upgrade, and policy operations without evidence that
  they improve the current bounded control-plane needs.
- **VM/container service:** retained as a portability fallback for customers
  with existing operations, not the first managed profile.

## Authority and rollback

The provider routes and stores candidate artifacts only. It cannot mint
signatures, create capabilities, lower state-v4 high-water, rewrite audit
history, mutate rollout state, or make an invalid patch valid. Customer/local
Ed25519 patch signing remains separate from image signing and provider IAM.

If a hard condition fails, stop the disposable implementation, preserve the
provider-neutral design, and either revise the AWS profile or return to the
GCP/Azure alternatives. No provider migration or production cutover is
implied by this ADR.

## Non-decisions

This ADR authorizes no infrastructure, account, credential, DNS, endpoint,
IaC, SDK, runtime/mobile/compiler, patch-signing, P3A/P3E-4, dashboard,
managed KMS/HSM, store submission, privacy/legal, beta, or production work.
It remains Proposed until a maintainer explicitly approves it.

## References

- [`docs/PROVIDER_SELECTION_DECISION_REVIEW.md`](../history/reviews/PROVIDER_SELECTION_DECISION_REVIEW.md)
- `tasks/77-provider-selection-decision-closure.md` (historical task record)
- [`docs/PROVIDER_DEPLOYMENT_DESIGN_REVIEW.md`](../history/reviews/PROVIDER_DEPLOYMENT_DESIGN_REVIEW.md)
- [`docs/adr/0010-self-hosted-deployment.md`](0010-self-hosted-deployment.md)
