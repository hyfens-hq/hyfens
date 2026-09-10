# Provider selection decision review

<!-- markdownlint-disable MD013 -->

Date: 2026-08-25
Task: `77-provider-selection-decision-closure` (historical task record)
Status: DESIGN-ONLY — MAINTAINER REVIEW REQUIRED

## 1. Recommendation

### Decision

PROCEED TO DISPOSABLE PROVIDER IMPLEMENTATION WITH CONDITIONS

The evidence supports one first disposable profile: AWS ECS/Fargate with an
active Application Load Balancer, RDS PostgreSQL Multi-AZ DB cluster, S3,
ACM/Route 53, VPC, ECS task IAM roles, Secrets Manager, ECR, CloudWatch, and
AWS Backup in Mumbai (`ap-south-1`). This is a recommendation, not provider
implementation approval, a production SLO, a beta approval, or an App Store /
Google Play / legal-compliance claim.

This review is not authorization to provision resources or begin provider
implementation; provider implementation is not authorized until a separate
maintainer decision grants that authority.

The implementation gate stays closed until the provider tests in section 24
prove real failover, transaction ambiguity, advisory-lock/session recovery,
pool recovery, active edge behavior, object recovery, supply chain, TLS,
identity, backup/PITR, and capacity contracts. If any hard condition fails,
return to the provider-neutral design or compare the documented GCP/Azure
alternatives again.

## 2. Frozen boundaries

This decision does not change:

- Architecture B/source instrumentation;
- Patch Format v1 and capability v1;
- exact-release binding, state-v4 monotonic high-water, signed rollback,
  fail-closed verification, and AOT fallback;
- customer/local patch signing and runtime-authoritative verification;
- PostgreSQL as coordination and metadata authority;
- immutable, digest-addressed object bytes as untrusted delivery storage;
- `BoundedReconciliationService` as the only repair path;
- `ReconciliationPeriodicRunner` as orchestration only;
- audit-before-repair, CAS/currentness/postconditions, and exact tenant scope;
- P3A as rollout mutation authority and P3E-4 as automatic-halt authority;
- process-local metrics and read-only diagnostics as non-authoritative.

Provider routing, storage, image signing, workload identity, or backups may
not mint patch signatures, create capabilities, lower a runtime high-water,
rewrite audit history, create a second repair/rollout authority, or make an
invalid patch valid.

## 3. Evidence method and date

Research was performed on 2026-08-25 using current official provider
documentation and official pricing pages only. The detailed retrieval ledger
is [the primary-source research record](../../research/provider-selection-sources.md).
A provider documentation claim
is labelled `DOCUMENTED`; it is not local failover or production evidence.
Every item that depends on account/SKU/region behavior, an outage, a
transaction boundary, or an application invariant is labelled
`PROVIDER TEST REQUIRED`, `UNKNOWN`, or `EXTERNAL CURRENT PRICING REQUIRED`.

The review does not use competitor marketing, provider calculators with
unrecorded inputs, or fabricated all-in totals. Public prices are inputs to an
editable model; taxes, credits, contracts, support, and account-specific
quotas are excluded until an actual disposable account is authorized.

## 4. Candidates and profile shape

| Candidate | Stateless compute | PostgreSQL | Object | Edge/TLS | Primary India hypothesis |
| --- | --- | --- | --- | --- | --- |
| AWS | ECS on Fargate | RDS PostgreSQL Multi-AZ DB cluster | S3 | ALB, ACM, Route 53 | Mumbai `ap-south-1`; Hyderabad `ap-south-2` alternative |
| Google Cloud | Cloud Run | Cloud SQL for PostgreSQL | Cloud Storage | External Application Load Balancer | Mumbai `asia-south1`; Delhi `asia-south2` alternative |
| Microsoft Azure | Azure Container Apps | Azure Database for PostgreSQL Flexible Server | Blob Storage | Container Apps ingress or Front Door | South India candidate; Central India conditional |

The implementation profile is intentionally managed containers plus managed
state. Kubernetes and VM/container services remain portability alternatives,
not first-profile choices.

## 5. Hard-gate matrix

Legend: `DOCUMENTED` means an official source describes the capability;
`PROVIDER TEST REQUIRED` means the implementation must exercise the exact
contract; `UNSUPPORTED` means the cited profile does not satisfy the gate as
specified; `UNKNOWN` means evidence is insufficient.

| Gate | AWS ECS/Fargate + RDS/S3 | GCP Cloud Run + Cloud SQL/Storage | Azure Container Apps + Flexible Server/Blob |
| --- | --- | --- | --- |
| Two stateless replicas | DOCUMENTED; ECS service scheduler replaces failed/unhealthy tasks | DOCUMENTED with min instances, but best-effort placement | DOCUMENTED; min replicas and revisions |
| Active `/readyz` routing | PROVIDER TEST REQUIRED; ALB checks can be configured, but all-unhealthy fail-open is documented | PROVIDER TEST REQUIRED; readiness is Preview and service-health behavior has limitations | DOCUMENTED probes; provider test active routing |
| Graceful drain/replacement | DOCUMENTED; ECS rolling percentages and target draining | DOCUMENTED; SIGTERM/10-second contract | DOCUMENTED; SIGTERM/30-second contract |
| Private managed PostgreSQL | DOCUMENTED via VPC/private connectivity options | DOCUMENTED via private IP/network controls | DOCUMENTED via VNet/private access |
| Managed writer failover | DOCUMENTED; RDS Multi-AZ writer/reader failover | DOCUMENTED; regional HA failover | DOCUMENTED; synchronous primary/standby failover |
| Reconnectable writer endpoint | DOCUMENTED; cluster/writer endpoint follows failover | DOCUMENTED conditionally; Enterprise Plus write endpoint behavior needs SKU test | DOCUMENTED; automatic DNS endpoint update |
| Session termination/transaction ambiguity | PROVIDER TEST REQUIRED | PROVIDER TEST REQUIRED | PROVIDER TEST REQUIRED |
| Session-scoped advisory locks | PROVIDER TEST REQUIRED; PostgreSQL semantics are application/provider seam | PROVIDER TEST REQUIRED | PROVIDER TEST REQUIRED |
| PITR/backups | DOCUMENTED; RDS automated backups/PITR | DOCUMENTED; Cloud SQL backup/PITR | DOCUMENTED; 7–35 day backup/PITR range |
| Private least-privilege object access | DOCUMENTED; task IAM + private S3 path | DOCUMENTED; service identity + bucket IAM | DOCUMENTED; managed identity + RBAC |
| Object version/delete recovery | DOCUMENTED; S3 versioning and Object Lock | DOCUMENTED; object versioning and soft delete | DOCUMENTED; versioning, soft delete, immutable storage |
| Immutable digest artifact operation | DOCUMENTED; ECR/ECS digest deployment and S3 digest keys | DOCUMENTED; Cloud Run revisions resolve image tags to digests | DOCUMENTED; ACR/ACA digest deployment; test exact policy |
| TLS lifecycle | DOCUMENTED; ACM-integrated public certificates | DOCUMENTED; load-balancer TLS | DOCUMENTED; Container Apps/Front Door TLS |
| Workload identity | DOCUMENTED; ECS task IAM role | DOCUMENTED; Cloud Run service identity | DOCUMENTED; managed identity |
| Secret injection | DOCUMENTED; Secrets Manager injection at task start | DOCUMENTED; Secret Manager env/file injection | DOCUMENTED; Key Vault references/managed identity |
| Immutable image deployment | DOCUMENTED; deploy by digest, test pre-deploy verification | DOCUMENTED; exact digest revisions, test admission policy | DOCUMENTED; digest/Notation path, test admission policy |
| Rolling replacement | DOCUMENTED; ECS deployment percentages | DOCUMENTED; immutable revisions/traffic migration | DOCUMENTED; revision readiness before traffic |
| Supply-chain scan/SBOM/provenance gate | PROVIDER TEST REQUIRED; ECR scanning plus external SBOM/signing policy | PROVIDER TEST REQUIRED; Artifact Analysis plus signing/provenance policy | PROVIDER TEST REQUIRED; Defender/Notation plus provenance policy |
| Traditional load-balancer health checks for serverless backends | DOCUMENTED for ALB targets | UNSUPPORTED for serverless NEGs; use Cloud Run service health/readiness instead | DOCUMENTED through Container Apps ingress/Front Door probes |
| One India co-located compute + zone-HA PostgreSQL shape | DOCUMENTED in Mumbai/Hyderabad | PROVIDER TEST REQUIRED for selected region/SKU pairing | UNSUPPORTED for new Central India zone-HA PostgreSQL; UNKNOWN for a complete South India co-located shape |
| Full invariant fit | PROVIDER TEST REQUIRED | PROVIDER TEST REQUIRED | PROVIDER TEST REQUIRED; Central India HA caveat |

The matrix deliberately does not convert provider marketing language into a
production guarantee. AWS ALB's all-targets-unhealthy fail-open behavior is a
material edge condition: application readiness and a safe response policy
must be tested in addition to target health.

## 6. PostgreSQL comparison

### AWS RDS PostgreSQL

RDS Multi-AZ DB clusters document one writer and two readers across three
Availability Zones, with a writer/cluster endpoint that follows failover.
Mumbai and Hyderabad document PostgreSQL 13–18 Multi-AZ cluster availability.
Backups and point-in-time restore are documented. The remaining proof is the
real sequence: break the writer session, observe transaction ambiguity,
recreate the pool through the writer endpoint, and prove session advisory-lock
loss and single-owner reacquisition.

Sources: [RDS Multi-AZ concepts](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/multi-az-db-clusters-concepts.html),
[RDS Multi-AZ regions](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RDS_Fea_Regions_DB-eng.Feature.MultiAZDBClusters.html),
[RDS connection management](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/multi-az-db-clusters-concepts-connection-management.html),
[RDS PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html),
[RDS backup and restore](https://docs.aws.amazon.com/AmazonRDS/latest/gettingstartedguide/managing-backup-restore.html).

### Google Cloud SQL for PostgreSQL

Cloud SQL regional HA documents a primary and standby in two zones, synchronous
replication before commit, automatic failover, and a shared static IP. The
documented expected unavailability is approximately 60 seconds. Cloud SQL
disaster recovery and write-endpoint behavior vary by edition; the selected
SKU and connection behavior therefore require an account-level test.

Sources: [Cloud SQL HA](https://docs.cloud.google.com/sql/docs/postgres/high-availability),
[Cloud SQL disaster recovery](https://docs.cloud.google.com/sql/docs/postgres/intro-to-cloud-sql-disaster-recovery),
[Cloud SQL PITR](https://docs.cloud.google.com/sql/docs/postgres/backup-recovery/pitr),
[Cloud SQL pricing](https://cloud.google.com/sql/pricing).

### Azure Database for PostgreSQL Flexible Server

Flexible Server documents synchronous primary/standby HA, automatic failover,
and endpoint DNS update. Automatic backups and PITR are documented, with a
7–35 day retention range and a WAL RPO of up to approximately five minutes.
Central India currently marks new zone-redundant HA deployments temporarily
blocked in the service availability table; South India is the conditional
India alternative. The exact service SKU, zone behavior, and pool recovery
must be tested before selecting Azure.

Sources: [Flexible Server HA](https://learn.microsoft.com/en-us/azure/postgresql/high-availability/concepts-high-availability),
[Flexible Server limits](https://learn.microsoft.com/en-us/azure/postgresql/configure-maintain/concepts-limits),
[backup and restore](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-backup-restore),
[service availability](https://learn.microsoft.com/en-us/azure/postgresql/overview).

### PostgreSQL gate interpretation

All three providers document a plausible writer failover, but none of those
documents proves this application's transaction and advisory-lock contract.
The implementation must treat a lost session as having lost ownership, treat
an ambiguous commit as unknown until the existing idempotency/CAS path resolves
it, and never assume that an HTTP response proves a database commit.

## 7. Object storage comparison

| Requirement | AWS S3 | Google Cloud Storage | Azure Blob Storage |
| --- | --- | --- | --- |
| Versioning | S3 Versioning retains variants; delete creates a marker | Object Versioning preserves deleted/overwritten versions | Blob versioning preserves prior versions |
| Delete recovery | Copy prior version/remove marker; Object Lock is WORM | Soft delete plus versioning | Soft delete plus versioning; immutable storage for WORM |
| Private IAM path | ECS task IAM role and bucket policy | Service account/service identity and bucket IAM | Managed identity/RBAC and storage firewall/private endpoint |
| Digest-addressed bytes | Application key policy | Application key policy | Application key policy |
| Provider evidence needed | Durability, lifecycle, accidental-delete recovery, exact-byte rehash | Same | Same |

Sources: [S3 versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html),
[S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html),
[Cloud Storage versioning](https://docs.cloud.google.com/storage/docs/object-versioning),
[Azure versioning/soft delete](https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-vs-versioning-options),
[Azure immutable storage](https://learn.microsoft.com/en-us/azure/storage/blobs/immutable-storage-overview).

Versioning, soft delete, and WORM are controls, not permission to change the
runtime trust model. Active artifact lifecycle policies must be tested against
rollback and high-water retention.

## 8. Edge, TLS, and private networking

The first profile uses an ALB in public subnets and ECS tasks, RDS, S3, ECR,
and Secrets Manager through private network paths. ACM manages integrated
public certificates and Route 53 supplies DNS only after a separately approved
domain change. ECS tasks use task IAM roles rather than static cloud keys.

The edge must:

- terminate TLS and propagate bounded request IDs;
- admit only replicas with active `/readyz` success;
- drain a replica before replacement;
- preserve the runtime lookup/fetch contract and operator authorization;
- fail closed at the application boundary when dependencies are unavailable;
- prove behavior when every target is unhealthy, because ALB documentation
  describes fail-open routing in that condition.

Sources: [ALB target health](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html),
[ECS service scheduler](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_services.html),
[ECS deployment](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-ecs.html),
[ACM pricing/certificate boundary](https://aws.amazon.com/certificate-manager/pricing/),
[Route 53 pricing](https://aws.amazon.com/route53/pricing/),
[ECS task IAM roles](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html),
[ECS Secrets Manager injection](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/secrets-envvar-secrets-manager.html).

GCP documents external load balancing with Cloud Run, internal-and-load-
balancing ingress, TLS termination, and a two-region requirement for some
service-health failover behavior. Azure Container Apps documents ingress,
TLS termination, internal/external modes, and traffic splitting. These are
credible alternatives, but each needs its own active-readiness and private
path test. For Cloud Run specifically, the startup probe must encode startup
readiness before traffic is admitted, session affinity must be disabled so an
unready instance cannot retain traffic, and the fixed 10-second
`SIGTERM`-to-`SIGKILL` window must fit request drain, runner release, pool
closure, and bounded telemetry flush. These conditions are not transferable
from the AWS profile.

Sources: [Cloud Run ingress](https://docs.cloud.google.com/run/docs/securing/ingress),
[Cloud Run service health](https://docs.cloud.google.com/run/docs/configuring/configure-service-health),
[Cloud Run security](https://docs.cloud.google.com/run/docs/securing/security),
[Azure Container Apps ingress](https://learn.microsoft.com/en-us/Azure/container-apps/ingress-overview),
[Azure ingress environment](https://learn.microsoft.com/en-us/azure/container-apps/ingress-environment-configuration).

## 9. Region comparison

AWS documents three Availability Zones for both Mumbai (`ap-south-1`) and
Hyderabad (`ap-south-2`), and Fargate plus RDS PostgreSQL Multi-AZ cluster
support in both. Mumbai is the first hypothesis because it is a standard,
non-opt-in region in the cited AWS region list; this is not a residency or
legal decision.

GCP documents Cloud Run Mumbai (`asia-south1`) and Delhi (`asia-south2`), but
Cloud SQL exact edition/SKU and the desired HA behavior still require a
provider account check.

Azure documents Central India, South India, and India South Central. Central
India PostgreSQL zone-redundant HA is currently shown as temporarily blocked
for new deployments; South India is the fallback test region. This caveat
prevents an unconditional Azure India selection.

Sources: [AWS regions/AZs](https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions.html),
[ECS Fargate regions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate-Regions.html),
[Azure region list](https://learn.microsoft.com/en-us/azure/reliability/regions-list),
[Azure region pairs](https://learn.microsoft.com/en-us/azure/reliability/regions-paired).

## 10. Workload assumptions

These are editable hypotheses, not observed production demand:

| Input | DEV / disposable | EARLY BETA | SMALL PRODUCTION HYPOTHESIS |
| --- | ---: | ---: | ---: |
| Organizations | 1 | 5 | 20 |
| Applications | 2 | 10 | 50 |
| Releases/month | 4 | 20 | 100 |
| Patches/month | 12 | 100 | 500 |
| Update checks/day | 100 | 5,000 | 50,000 |
| Artifact fetches/day | 20 | 1,000 | 10,000 |
| Average artifact | 0.5 MiB | 0.5 MiB | 2 MiB |
| Retained artifact bytes | 1 GiB | 20 GiB | 200 GiB |
| Audit/log volume/month | 0.1 GiB | 5 GiB | 50 GiB |
| Backup retention hypothesis | 7 days | 14 days | 35 days |

Derived monthly request and egress quantities:

| Scenario | Checks/month | Fetches/month | Approx. artifact egress/month |
| --- | ---: | ---: | ---: |
| DEV | 3,000 | 600 | 0.293 GiB |
| EARLY BETA | 150,000 | 30,000 | 14.648 GiB |
| SMALL PRODUCTION HYPOTHESIS | 1,500,000 | 300,000 | 585.938 GiB |

## 11. Pricing appendix and editable model

Current public pricing is region/SKU/usage dependent. The review records the
official pricing pages, but intentionally does not fabricate an all-in USD
total. The implementation worksheet must enter the chosen region, task CPU
and memory, DB class/storage/HA, object bytes/operations, edge forwarding and
data processing, egress, logs, backups, support, taxes, and credits.

### Published inputs

- AWS Fargate charges requested vCPU, memory, OS/architecture, storage, and
  task runtime; see [Fargate pricing](https://aws.amazon.com/fargate/pricing/).
- AWS RDS pricing varies with DB instance/deployment/region and separately
  charges storage, backup, and transfer; see [RDS PostgreSQL pricing](https://aws.amazon.com/rds/postgresql/pricing/).
- S3 charges storage, requests, retrieval, transfer, replication, and
  management; see [S3 pricing](https://aws.amazon.com/s3/pricing/).
- Cloud Run publishes Mumbai Tier-1 compute/request rates; see [Cloud Run pricing](https://cloud.google.com/run/pricing).
- Cloud Storage publishes Mumbai Standard storage and operation rates; see [Cloud Storage pricing](https://cloud.google.com/storage/pricing).
- Cloud Load Balancing publishes forwarding-rule and data-processing rates;
  see [Cloud Load Balancing pricing](https://cloud.google.com/load-balancing/pricing).
- Artifact Registry publishes storage pricing; see [Artifact Registry pricing](https://cloud.google.com/artifact-registry/pricing).
- Azure publishes dynamic Container Apps, Flexible Server, Blob Storage,
  and Front Door regional price pages; see [Container Apps pricing](https://azure.microsoft.com/en-us/pricing/details/container-apps/),
  [Flexible Server pricing](https://azure.microsoft.com/en-us/pricing/details/postgresql/flexible-server/),
  [Blob pricing](https://azure.microsoft.com/en-us/pricing/details/storage/blobs/),
  and [Front Door pricing](https://azure.microsoft.com/en-us/pricing/details/frontdoor/).

### Resource quantities for the first AWS worksheet

| Resource quantity | DEV / disposable | EARLY BETA | SMALL PRODUCTION HYPOTHESIS |
| --- | ---: | ---: | ---: |
| Fargate replicas | 2 | 2 | 2 (scale ceiling 6 for first test) |
| vCPU per replica | 0.25 | 0.5 | 1 |
| GiB per replica | 0.5 | 1 | 2 |
| vCPU-hours/month at 730h | 365 | 730 | 1,460 |
| GiB-hours/month at 730h | 730 | 1,460 | 2,920 |
| RDS allocated storage hypothesis | 10 GiB | 20 GiB | 100 GiB |
| S3 retained bytes | 1 GiB | 20 GiB | 200 GiB |
| Monthly egress hypothesis | 0.293 GiB | 14.648 GiB | 585.938 GiB |
| Monthly logs | 0.1 GiB | 5 GiB | 50 GiB |

The quantities are not a quotation. They are the minimum reproducible inputs
for a later disposable account. The AWS implementation must record the
actual calculator/export result and timestamp before a cost gate is closed.

## 12. Cost scenarios

The three scenarios are complete as quantity models and incomplete as provider
quotes by design:

- **DEV/disposable:** two 0.25-vCPU/0.5-GiB replicas, one HA PostgreSQL
  floor, 10 GiB database, 1 GiB object, 0.293 GiB egress, one edge, and
  0.1 GiB logs per month. This validates the smallest two-replica contract;
  a single-replica cheaper mode is not the target architecture.
- **EARLY BETA:** two 0.5-vCPU/1-GiB replicas, 20 GiB database, 20 GiB
  object, 14.648 GiB egress, and 5 GiB logs. It is a capacity hypothesis,
  not beta authorization.
- **SMALL PRODUCTION HYPOTHESIS:** two 1-vCPU/2-GiB replicas, 100 GiB
  database, 200 GiB object, 585.938 GiB egress, and 50 GiB logs. It is a
  sizing envelope, not a production SLO.

For a transparent published component example only, two always-on Cloud Run
instances at 1 vCPU and 0.5 GiB for 730 hours yield approximately 1,460
vCPU-hours and 730 GiB-hours. Applying the published instance-based Mumbai
rates gives approximately `$94.61` vCPU plus `$5.26` memory before free tier,
commitments, requests, networking, Cloud SQL, storage, logs, or taxes. This
is not a Cloud Run stack total and is not compared directly with an AWS or
Azure quote.

## 13. Sensitivity checks

| Change | Primary effect | Required recheck |
| --- | --- | --- |
| 10x update checks | Compute/request/log volume; DB read pool pressure | Request pricing, CPU/concurrency, DB connections, readiness latency |
| 10x artifact fetches | Object GETs and egress; possible edge transfer | S3/Storage/Blob request and egress price, bandwidth, throttling |
| 10x logs | Log ingest/storage and operator cost | Retention, sampling, sensitive-field redaction, budget |
| 2x database size | Storage/backup; possible instance-tier change | DB max connections, IOPS, PITR restore time, failover budget |
| 2x replicas | Compute and connection pool | Advisory election, pool ceiling, edge distribution |

No sensitivity result is a performance or cost guarantee. It identifies which
inputs must be recalculated when workload assumptions change.

## 14. Weighted scorecard

Weights were fixed before scoring and total 100: architecture fit 15,
operational simplicity 12, PostgreSQL/failover 15, object durability 10,
edge/TLS/networking 10, security/IAM 10, supply chain 8, regional availability
8, cost predictability 5, portability 4, maintenance burden 3. Scores are
0–5 evidence-weighted design judgments, not provider test results.

| Criterion | Weight | AWS | GCP | Azure |
| --- | ---: | ---: | ---: | ---: |
| Architecture fit | 15 | 5.0 | 4.5 | 4.2 |
| Operational simplicity | 12 | 4.5 | 4.5 | 4.3 |
| PostgreSQL/failover | 15 | 4.5 | 4.5 | 4.0 |
| Object durability | 10 | 5.0 | 4.5 | 4.5 |
| Edge/TLS/networking | 10 | 4.0 | 4.0 | 4.5 |
| Security/IAM | 10 | 5.0 | 4.5 | 4.5 |
| Supply chain | 8 | 4.5 | 4.5 | 4.5 |
| Regional availability | 8 | 4.5 | 4.0 | 3.0 |
| Cost predictability | 5 | 3.5 | 4.0 | 4.0 |
| Portability | 4 | 3.0 | 3.5 | 3.5 |
| Maintenance burden | 3 | 4.5 | 4.5 | 4.2 |
| **Weighted result / 100** | **100** | **451.5 / 100 = 4.515** | **434.5 / 100 = 4.345** | **416.2 / 100 = 4.162** |

The result selects AWS only as the first disposable hypothesis. Hard-gate
failures override the score: AWS still needs edge/failover tests, GCP needs
readiness/placement and SKU tests, and Azure's Central India HA condition
prevents an unconditional India profile.

## 15. Selected profile

The proposed first profile is:

~~~text
private operator/CI
        |
        v
Route 53 + ACM + active ALB (/readyz, TLS, drain)
        |
        +---------------------+
        |                     |
ECS/Fargate task A      ECS/Fargate task B
        |                     |
        +----------+----------+
                   |
      private RDS PostgreSQL writer endpoint
                   |
          private versioned S3 bucket

ECR -> digest/SBOM/signature/provenance gate -> ECS deployment
Secrets Manager + task IAM roles; CloudWatch + AWS Backup
~~~

No component in the proposed profile becomes a new patch/runtime authority.

## 16. Provider and region recommendation

Recommend AWS Mumbai (`ap-south-1`) for the first disposable implementation,
with Hyderabad (`ap-south-2`) as the first alternative test. The recommendation
is based on the documented three-AZ/Fargate/RDS-Multi-AZ combination and broad
regional availability, not a promise of latency, residency, price, or
compliance. A maintainer may select another profile after reviewing the same
matrix and tests.

## 17. IAM and secrets

The control plane should use one task role with the minimum required S3,
Secrets Manager, CloudWatch, and database-network permissions. The task role
must not sign patches, alter rollout state outside existing authorization, or
write provider control-plane resources. Secret values are injected at startup;
rotation must trigger controlled task replacement because AWS documents that
already-running tasks do not receive a rotated injected value automatically.

Customer/local Ed25519 patch signing remains offline and separate. Image
signatures are a deployment supply-chain control, not patch authorization.

## 18. IaC comparison and recommendation

| Approach | Strength | Trade-off |
| --- | --- | --- |
| OpenTofu/Terraform | Reviewable plan/apply, broad provider coverage, reusable modules, state workflows | State backend/locking and provider version management remain operational responsibilities |
| Provider-native (CloudFormation/Bicep/declarative service configs) | Best native feature coverage and first-party drift semantics | Lowest portability; separate language/tooling per provider |
| Pulumi | Typed general-purpose language and provider abstraction | State/toolchain/runtime dependency and review surface are larger |

Recommend **OpenTofu 1.x** for a future disposable implementation, with an
encrypted remote state backend, locking, pinned providers/modules, reviewable
plans, and no secrets in state unless explicitly encrypted and scoped. This is
a proposed tooling choice only; no IaC files or providers are added in Task
77. Provider-native templates remain acceptable where OpenTofu lacks a tested
feature, but any exception needs an ADR update.

## 19. Image and artifact supply chain

The future deployment path is:

~~~text
source + lockfiles
  -> pinned base-image digest
  -> build
  -> SPDX/CycloneDX SBOM
  -> vulnerability scan
  -> OCI image digest
  -> Cosign/Notation signature + provenance
  -> private registry
  -> pre-deploy verify digest, SBOM, provenance, policy
  -> deploy exact digest
~~~

AWS ECR documents basic and enhanced scanning; GCP Artifact Registry
documents vulnerability analysis and immutable tag options; Azure documents
Notation OCI signing and warns that Docker Content Trust cannot be enabled on
new registries after 2026-05-31. The implementation must still choose one
verification policy and test rejection before rollout. Patch signing remains
the customer/local Ed25519 path.

Sources: [ECR image scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html),
[Artifact Registry repositories](https://cloud.google.com/artifact-registry/docs/repositories/create-repos),
[Azure OCI signing](https://learn.microsoft.com/en-us/azure/container-registry/overview-sign-verify-artifacts),
[Azure DCT deprecation](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-content-trust).

## 20. Runner and diagnostics model

Recommend **every eligible replica includes the runner, with PostgreSQL
session-scoped advisory-lock election**. This preserves the current seam:
failover destroys the old ownership session; a healthy replica reacquires on a
later bounded cadence. The runner remains orchestration only and calls only
`BoundedReconciliationService`; it never owns repair, CAS, audit, rollout, or
halt semantics.

Diagnostics remain private/internal and authenticated with exact tenant,
application, and environment scope. They are read-only and cannot start a
repair, halt, rollout, signing, artifact, or credential operation.

## 21. Endpoint exposure inventory

| Endpoint | Exposure | Rationale |
| --- | --- | --- |
| Runtime lookup/fetch | PUBLIC, with app-scoped authentication/authorization as applicable | Mobile clients need delivery access; artifact bytes remain verified by runtime |
| Control/operator API | PRIVATE or AUTHENTICATED_OPERATOR | No unauthenticated control mutation |
| `/livez` | INTERNAL_LB_ONLY | Process liveness, not dependency readiness |
| `/readyz` | INTERNAL_LB_ONLY | Active edge eligibility; no public dependency detail |
| `/metrics` | PRIVATE / INTERNAL_LB_ONLY | Low-cardinality operational data only |
| Diagnostics | AUTHENTICATED_OPERATOR through private path | Exact-scope, bounded, read-only |

The exact external edge and authentication gateway remain implementation
choices subject to Task 77 conditions; no endpoint is created here.

## 22. RPO/RTO targets

| Boundary | Design target | Status |
| --- | --- | --- |
| Artifact bytes | RPO 0 for acknowledged immutable bytes | ACCEPT as design target; object/provider test required |
| PostgreSQL metadata/audit | RPO 5–15 minutes | ACCEPT as design target; backup/PITR restore required |
| Control plane | RTO 30–60 minutes | ACCEPT as target, not an SLO |
| Delivery after healthy replacement | Within health/drain budget | ACCEPT as target; edge/replacement test required |

These targets do not close the existing power-loss, provider, independent-app,
iOS, store, privacy, legal, beta, or production gates.

## 23. Capacity, pool, and autoscaling hypothesis

First disposable test: two Fargate tasks across two AZs, each 0.25 vCPU and
0.5 GiB for DEV; max six tasks for the first scale experiment. A later small-
production hypothesis uses two 1-vCPU/2-GiB tasks. Scale signals are CPU,
memory, request concurrency, latency, and readiness—not rollout or
reconciliation outcomes. Initial cooldown hypothesis is 60 seconds up and
300 seconds down, subject to measurement.

Connection pool budget must be explicit:

~~~text
max replicas * (HTTP pool + one runner ownership connection)
  + migration reserve
<= provider/database connection limit with >=25% headroom
~~~

The exact RDS instance connection limit, transaction pool size, and latency
budget are provider-test inputs, not assumptions to hard-code now.

## 24. Provider acceptance tests (not executed)

The following are the minimum disposable implementation tests. Each must keep
deployment/image/config digests, timestamps, logs, metrics, audit IDs, and
provider operation IDs as evidence:

1. Start two replicas; prove active `/readyz` routing and no sticky sessions.
2. Kill each replica during requests; prove drain, replacement, and no lost
   committed semantic mutation.
3. Force RDS writer failover; capture broken-session behavior, transaction
   ambiguity, pool recreation, writer endpoint recovery, advisory-lock loss,
   and one-owner reacquisition.
4. Run concurrent reconciliation callers around failover; prove one semantic
   repair through existing CAS/idempotency and no stuck owner.
5. Deny S3 access and restore it; prove readiness/fail-closed delivery and
   exact-byte rehash on recovery.
6. Delete an object/version and recover it; prove active artifact retention
   and rollback evidence survive.
7. Rotate TLS and secrets; prove old material is not used after controlled
   replacement and no secret appears in logs/images/state.
8. Reject an unsigned, wrong-digest, untrusted, unsigned-image, or missing-
   provenance deployment before traffic.
9. Exercise the all-targets-unhealthy ALB case; prove the application does not
   deliver an invalid/unready control-plane response.
10. Perform a rolling N/N+1 deployment and rollback by exact image digest.
11. Restore PostgreSQL to a PITR point and restore matching object bytes; prove
    audit, artifact, and currentness checks remain consistent.
12. Attempt cross-tenant/operator access; prove non-revealing rejection.
13. Partition dependencies, restart the host, and repeat the bounded runner /
    diagnostics readiness sequence.

No test above was run in Task 77. “Documented” in the matrix is not a test
result.

## 25. Soak and capacity plan (not executed)

After acceptance tests pass, run a 60–120 minute disposable soak with two or
more replicas, normal update checks/fetches, operator/control traffic,
readiness probes, audit writes, PostgreSQL pool use, object reads, runner
cadence, and one controlled dependency outage. Repeat at baseline, 2x, 5x,
and 10x request envelopes. Retain deployment/image/config digests, latency
percentiles, pool saturation, readiness transitions, failover timestamps,
audit-chain verification, object digests, and cost counters. This is not a
production load test or a beta approval.

## 26. Threat-model changes

Task 77 adds a factual provider-selection addendum to
`docs/security/productization-threat-model.md`. It records account/IAM,
database/object, edge fail-open, image/base-image, backup, secret, and region
availability threats; preserves customer/local signing and runtime authority;
and leaves provider failover, durability, power-loss, independent-app, iOS,
store, privacy, legal, beta, and production gates open.

## 27. Proposed ADRs

[`docs/adr/0014-provider-selection.md`](../../adr/0014-provider-selection.md) is
`Proposed — maintainer approval required`. It selects the AWS-first profile
only as a disposable hypothesis, lists GCP/Azure alternatives, states hard
conditions and rollback, and authorizes no provider implementation.

## 28. Remaining external gates

The following remain open and cannot be relabelled as satisfied by Task 77:

- independent real-app validation;
- true power-loss and crash/restart evidence;
- complete iOS diagnostics/performance and physical-device evidence;
- deeper interpreter-stage performance attribution;
- provider failover, readiness, object, supply-chain, cost, and soak evidence;
- provider-production and operational ownership readiness;
- Apple/Google store-policy review and legal/privacy review;
- beta and production approval.

## 29. Next recommendation

**PROCEED TO DISPOSABLE PROVIDER IMPLEMENTATION WITH CONDITIONS** is the
single recommendation for maintainer review. It does not authorize Task 78 or
any provider implementation automatically. The next authorized package, if
approved, should create the smallest disposable AWS profile, execute section
24 in a non-production account, record actual pricing, and stop again for
review before beta, production, store, privacy, or legal claims.

## Source register

The primary sources below are intentionally linked in the sections where they
support a claim. This register makes the research boundary auditable.

- [Detailed primary-source retrieval ledger](../../research/provider-selection-sources.md)
  (all observations dated 2026-08-25).

### AWS

- [Fargate pricing](https://aws.amazon.com/fargate/pricing/)
- [ECS pricing](https://aws.amazon.com/ecs/pricing/)
- [RDS PostgreSQL pricing](https://aws.amazon.com/rds/postgresql/pricing/)
- [RDS Multi-AZ regions](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RDS_Fea_Regions_DB-eng.Feature.MultiAZDBClusters.html)
- [RDS Multi-AZ concepts](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/multi-az-db-clusters-concepts.html)
- [RDS connection management](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/multi-az-db-clusters-concepts-connection-management.html)
- [RDS backup and restore](https://docs.aws.amazon.com/AmazonRDS/latest/gettingstartedguide/managing-backup-restore.html)
- [AWS regions](https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions.html)
- [Fargate regions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate-Regions.html)
- [ECS services](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_services.html)
- [ECS rolling deployment](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-ecs.html)
- [ALB target health](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html)
- [S3 versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)
- [S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
- [S3 pricing](https://aws.amazon.com/s3/pricing/)
- [ACM pricing](https://aws.amazon.com/certificate-manager/pricing/)
- [Route 53 pricing](https://aws.amazon.com/route53/pricing/)
- [ECR scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html)
- [ECS task IAM roles](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html)
- [ECS Secrets Manager injection](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/secrets-envvar-secrets-manager.html)

### Google Cloud

- [Cloud Run pricing](https://cloud.google.com/run/pricing)
- [Cloud Run min instances](https://docs.cloud.google.com/run/docs/configuring/min-instances)
- [Cloud Run health checks](https://docs.cloud.google.com/run/docs/configuring/healthchecks)
- [Cloud Run service health](https://docs.cloud.google.com/run/docs/configuring/configure-service-health)
- [Cloud Run container contract](https://docs.cloud.google.com/run/docs/container-contract)
- [Cloud Run ingress](https://docs.cloud.google.com/run/docs/securing/ingress)
- [Cloud Run deployment](https://docs.cloud.google.com/run/docs/deploying)
- [Cloud Run service identity](https://docs.cloud.google.com/run/docs/configuring/services/service-identity)
- [Cloud Run secrets](https://docs.cloud.google.com/run/docs/configuring/services/secrets)
- [Cloud SQL HA](https://docs.cloud.google.com/sql/docs/postgres/high-availability)
- [Cloud SQL disaster recovery](https://docs.cloud.google.com/sql/docs/postgres/intro-to-cloud-sql-disaster-recovery)
- [Cloud SQL PITR](https://docs.cloud.google.com/sql/docs/postgres/backup-recovery/pitr)
- [Cloud SQL pricing](https://cloud.google.com/sql/pricing)
- [Cloud Storage versioning](https://docs.cloud.google.com/storage/docs/object-versioning)
- [Cloud Storage pricing](https://cloud.google.com/storage/pricing)
- [Cloud Load Balancing pricing](https://cloud.google.com/load-balancing/pricing)
- [Artifact Registry pricing](https://cloud.google.com/artifact-registry/pricing)
- [Artifact Registry repositories](https://cloud.google.com/artifact-registry/docs/repositories/create-repos)

### Microsoft Azure

- [Container Apps health probes](https://learn.microsoft.com/en-us/azure/container-apps/health-probes)
- [Container Apps lifecycle](https://learn.microsoft.com/en-us/azure/container-apps/application-lifecycle-management)
- [Container Apps revisions](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Container Apps ingress](https://learn.microsoft.com/en-us/Azure/container-apps/ingress-overview)
- [Container Apps private endpoints/DNS](https://learn.microsoft.com/en-us/azure/container-apps/private-endpoints-with-dns)
- [Container Apps managed identity](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
- [Container Apps Key Vault secrets](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)
- [Container Apps managed-identity image pull](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull)
- [Container Apps pricing](https://azure.microsoft.com/en-us/pricing/details/container-apps/)
- [PostgreSQL Flexible Server HA](https://learn.microsoft.com/en-us/azure/postgresql/high-availability/concepts-high-availability)
- [PostgreSQL service availability](https://learn.microsoft.com/en-us/azure/postgresql/overview)
- [PostgreSQL backup and restore](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-backup-restore)
- [PostgreSQL pricing](https://azure.microsoft.com/en-us/pricing/details/postgresql/flexible-server/)
- [Blob versioning and soft delete](https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-vs-versioning-options)
- [Blob immutable storage](https://learn.microsoft.com/en-us/azure/storage/blobs/immutable-storage-overview)
- [Blob pricing](https://azure.microsoft.com/en-us/pricing/details/storage/blobs/)
- [ACR OCI signing](https://learn.microsoft.com/en-us/azure/container-registry/overview-sign-verify-artifacts)
- [ACR content-trust deprecation](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-content-trust)
- [Front Door pricing](https://azure.microsoft.com/en-us/pricing/details/frontdoor/)
