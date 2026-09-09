# Disposable AWS provider profile

This directory is the Task 78, non-production AWS implementation for the
provider-neutral Hyfens control plane. It is intentionally bounded to one
disposable environment in `ap-south-1`; it is not a production deployment,
hosted service, beta environment, or store/legal approval.

## Shape

- OpenTofu 1.x with AWS provider `6.61.0`, pinned in the environment lock file.
- Three-AZ VPC: public ALB subnets and private ECS/RDS subnets.
- Two ECS/Fargate control-plane tasks using an exact image digest.
- RDS PostgreSQL Multi-AZ DB cluster with managed master credentials.
- Private, versioned, encrypted S3 artifact bucket and VPC endpoints.
- ECS execution/task IAM roles; the task signs S3 requests with ECS task-role
  credentials and never receives static cloud keys.
- CloudWatch logs, bounded AWS Backup retention, and optional ACM/Route 53
  module that remains inactive unless explicitly enabled.

## Guardrails

Before apply, record current `ap-south-1` price inputs in the Task 78 evidence
directory and set all of these deliberately:

- expected monthly disposable envelope: at most USD 250;
- one test run: at most USD 75;
- resource lifetime: at most 24 hours;
- an explicit operator CIDR (never `0.0.0.0/0`);
- `cost_guardrail_acknowledged = true`.

`allow_destroy` defaults to `false`. Versioned S3 and backup resources require
an explicit `-var allow_destroy=true` during teardown. State is local and
ignored by Git under `environments/disposable/state/`; it must remain inside
the disposable operator boundary and must not be copied into a production
state store.

## Image bootstrap

The image uses a pinned Dart 3.13.0 multi-platform base manifest. Build locally
from the repository root:

```sh
docker build --platform linux/arm64 \
  -f deploy/aws/Dockerfile \
  -t hyfens/task78-control-plane:local .
docker image inspect hyfens/task78-control-plane:local \
  --format '{{index .RepoDigests 0}}'
```

Create the ECR repository with an initial targeted plan, push an image by
digest, then run the full plan with `image_uri` set to the resulting
`...@sha256:<digest>`. A mutable tag is rejected by the task definition.
Generate and verify the SBOM, vulnerability report, OCI signature, and
provenance before the full apply. No patch-signing key is used for image
signing.

## OpenTofu workflow

```sh
cd deploy/aws/environments/disposable
cp terraform.tfvars.example terraform.tfvars
# Edit CIDR, exact image digest, and the current price worksheet result.
docker run --rm -v "$PWD:/workspace" -w /workspace \
  ghcr.io/opentofu/opentofu:1.10.0 init -input=false
docker run --rm -v "$PWD:/workspace" -w /workspace \
  ghcr.io/opentofu/opentofu:1.10.0 validate
docker run --rm -v "$PWD:/workspace" -w /workspace \
  ghcr.io/opentofu/opentofu:1.10.0 plan -out=/workspace/disposable.tfplan
docker run --rm -v "$PWD:/workspace" -w /workspace \
  ghcr.io/opentofu/opentofu:1.10.0 apply /workspace/disposable.tfplan
```

The plan/apply container needs AWS credentials through the approved operator
mechanism. Do not put credentials in `terraform.tfvars`, the image, or Git.
The RDS password is managed by RDS/Secrets Manager. The ECS task receives only
the JSON password field through the execution role and constructs its
PostgreSQL URI in memory.

## Evidence and teardown

Provider acceptance evidence belongs in:
`docs/research/evidence/task78-aws-disposable/`. Record operation IDs, resource
identifiers, timestamps, and redacted command output; never commit secret
values, tokens, state, or unredacted logs. Run the explicit teardown runbook
immediately after evidence capture and verify that the environment is gone.

The hard gates remain open until actual AWS evidence proves ALB readiness and
all-unhealthy fail-closed behavior, RDS writer/pool/advisory-lock recovery,
S3 version/delete recovery, IAM/secret/TLS behavior, PITR/coupled restore,
tenant/network isolation, capacity/soak, cost, and complete teardown.

The ECS variable for periodic reconciliation defaults to `false`. The current
serving binary does not yet compose an exact tenant/application/environment
invocation and raw lease-token provider for the existing runner. Enabling it
before that seam is wired would falsely advertise a repair scheduler, so the
provider profile records this as an open integration gate rather than adding a
second repair path.
