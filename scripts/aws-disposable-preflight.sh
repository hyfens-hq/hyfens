#!/usr/bin/env bash
set -euo pipefail

# Credential-free local acceptance preflight by default. The local phase never
# runs `tofu apply`, `tofu destroy`, or an AWS API command. An explicit
# `--aws-identity` phase performs only a caller-account check; it never applies
# or destroys resources. A signed local registry reference may be supplied so
# the same provider-neutral verifier used before deployment can be exercised
# without ECR.

die() {
  printf 'PREFLIGHT FAIL: %s\n' "$1" >&2
  exit 1
}

phase='local'
if [[ "${1:-}" == '--aws-identity' ]]; then
  phase='aws-identity'
  shift
fi
[[ "$#" == '0' ]] || die 'usage: aws-disposable-preflight.sh [--aws-identity]'

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
evidence_root="$repo_root/docs/research/evidence/task79-preflight"
local_evidence="$evidence_root/local"
image_ref="${HYFENS_PREFLIGHT_IMAGE_REF:-hyfens/task79-control-plane@sha256:68ae7017f9e7b93ff9d81d3944e161d25f89de171dabaac2660a77e4df48cb4b}"
expected_digest="${HYFENS_PREFLIGHT_EXPECTED_DIGEST:-sha256:68ae7017f9e7b93ff9d81d3944e161d25f89de171dabaac2660a77e4df48cb4b}"
public_key="${HYFENS_PREFLIGHT_PUBLIC_KEY:-}"
cosign_image="${HYFENS_PREFLIGHT_COSIGN_IMAGE:-ghcr.io/sigstore/cosign/cosign@sha256:b03690aa52bfe94054187142fba24dc54137650682810633901767d8a3e15b31}"
use_local_registry="${HYFENS_PREFLIGHT_LOCAL_HTTP_REGISTRY:-0}"
tofu_image="${HYFENS_PREFLIGHT_TOFU_IMAGE:-ghcr.io/opentofu/opentofu:1.10.0}"

command -v docker >/dev/null 2>&1 || die 'Docker is required.'
command -v jq >/dev/null 2>&1 || die 'jq is required.'
command -v dart >/dev/null 2>&1 || die 'Dart is required for the control-plane suite.'
command -v rg >/dev/null 2>&1 || die 'ripgrep is required for the repository credential scan.'

[[ "$image_ref" =~ @sha256:[0-9a-f]{64}$ ]] || die 'image reference must be digest-addressed.'
[[ "${image_ref##*@}" == "$expected_digest" ]] || die 'image digest does not match the expected candidate.'
[[ -s "$local_evidence/sbom.spdx.json" ]] || die 'fresh SBOM is missing.'
[[ -s "$local_evidence/trivy.json" ]] || die 'fresh vulnerability scan is missing.'
[[ -s "$local_evidence/vulnerability-policy.json" ]] || die 'vulnerability policy is missing.'
[[ -s "$local_evidence/provenance-predicate.json" ]] || die 'provenance predicate is missing.'
[[ -s "$repo_root/deploy/aws/Dockerfile" ]] || die 'hardened Dockerfile is missing.'

image_id="$(docker image inspect "$image_ref" --format '{{.Id}}' 2>/dev/null)" || \
  die "candidate image is not available locally: $image_ref"
image_arch="$(docker image inspect "$image_ref" --format '{{.Architecture}}' 2>/dev/null)" || \
  die 'unable to inspect candidate architecture.'
[[ "$image_id" == "$expected_digest" ]] || die 'local image ID does not equal the expected digest.'
[[ "$image_arch" == 'arm64' ]] || die "candidate architecture is $image_arch, expected arm64."

grep -q 'gcr.io/distroless/base-debian13:nonroot@sha256:' "$repo_root/deploy/aws/Dockerfile" || \
  die 'runtime image is not pinned to the nonroot distroless base.'
grep -q 'USER nonroot:nonroot' "$repo_root/deploy/aws/Dockerfile" || \
  die 'runtime image is not nonroot.'
grep -q 'CMD \["/app/health_check"\]' "$repo_root/deploy/aws/Dockerfile" || \
  die 'image health check is not the compiled executable.'
grep -q 'command     = \["CMD", "/app/health_check"\]' "$repo_root/deploy/aws/modules/ecs/main.tf" || \
  die 'ECS health check still assumes a Dart SDK in the runtime image.'

jq -e '.spdxVersion and (.packages | type == "array")' \
  "$local_evidence/sbom.spdx.json" >/dev/null || die 'SBOM JSON is invalid.'
jq -e '.Results | type == "array"' \
  "$local_evidence/trivy.json" >/dev/null || die 'Trivy JSON is invalid.'
jq -e --arg digest "$expected_digest" '.image_digest == $digest' \
  "$local_evidence/vulnerability-policy.json" >/dev/null || \
  die 'vulnerability policy is not bound to the candidate digest.'

for required in \
  "$evidence_root/periodic-runner.md" \
  "$evidence_root/opentofu-safety.md" \
  "$evidence_root/aws-operator-inputs.md" \
  "$evidence_root/iam-preflight.md" \
  "$evidence_root/cost-worksheet.md" \
  "$evidence_root/preflight.md" \
  "$evidence_root/plan.md" \
  "$evidence_root/supply-chain.md" \
  "$evidence_root/ecs-alb.md" \
  "$evidence_root/rds-failover.md" \
  "$evidence_root/s3-recovery.md" \
  "$evidence_root/iam-secrets.md" \
  "$evidence_root/backup-pitr.md" \
  "$evidence_root/tenant-network.md" \
  "$evidence_root/capacity-soak.md" \
  "$evidence_root/cost.md" \
  "$evidence_root/teardown.md"; do
  [[ -s "$required" ]] || die "required evidence contract is missing: $required"
done
grep -q 'Status: BLOCKED' "$evidence_root/periodic-runner.md" || \
  die 'periodic runner classification is not explicit.'
grep -A8 'variable "reconciliation_periodic_enabled"' \
  "$repo_root/deploy/aws/modules/ecs/variables.tf" | grep -q 'default = false' || \
  die 'periodic runner is not disabled in the disposable profile.'
[[ ! -e "$repo_root/deploy/aws/environments/disposable/terraform.tfvars" ]] || \
  die 'local terraform.tfvars must not be present in the repository workspace.'
if rg -n --hidden \
  --glob '!.git/**' --glob '!.dart_tool/**' --glob '!**/.terraform/**' \
  --glob '!*.lock' \
  '(AKIA[0-9A-Z]{16}|-----BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY-----|aws_secret_access_key[[:space:]]*=)' \
  "$repo_root" >/dev/null; then
  die 'repository credential scan found a possible AWS key or private key marker.'
fi

docker run --rm -v "$repo_root:/workspace" -w /workspace "$tofu_image" \
  fmt -check -recursive /workspace/deploy/aws >/dev/null || die 'OpenTofu format check failed.'

docker run --rm -v "$repo_root:/workspace" \
  -w /workspace/deploy/aws/environments/disposable "$tofu_image" \
  init -backend=false -input=false >/dev/null || die 'OpenTofu local init failed.'
docker run --rm -v "$repo_root:/workspace" \
  -w /workspace/deploy/aws/environments/disposable "$tofu_image" \
  validate >/dev/null || die 'OpenTofu validation failed.'

if [[ -z "$public_key" ]]; then
  die 'HYFENS_PREFLIGHT_PUBLIC_KEY is required; the local preflight must verify a real test signature.'
fi
[[ -s "$public_key" ]] || die "public key is missing: $public_key"
verifier_args=(
  --image-ref "$image_ref"
  --expected-digest "$expected_digest"
  --sbom "$local_evidence/sbom.spdx.json"
  --scan "$local_evidence/trivy.json"
  --triage-policy "$local_evidence/vulnerability-policy.json"
  --public-key "$public_key"
  --dockerfile "$repo_root/deploy/aws/Dockerfile"
  --expected-builder-base 'dart@sha256:8b6175f6c6b89aaf31ffdace4a22d17715c07f1cf3a772dadb10c658f779e23d'
  --expected-runtime-base 'gcr.io/distroless/base-debian13:nonroot@sha256:2d7d29b504e7166f6d0c7655a18ebf5def5b37b029f8c4f8667e434ba774844f'
  --cosign-image "$cosign_image"
)
if [[ "$use_local_registry" == '1' ]]; then
  verifier_args+=(--local-http-registry)
fi
"$repo_root/scripts/verify-predeploy-artifact.sh" "${verifier_args[@]}" || \
  die 'provider-neutral pre-deploy verifier rejected the candidate.'

printf '%s\n' 'Running isolated control-plane suite (no AWS credentials or services).' >&2
# The bounded File contention benchmark is intentionally sensitive to host
# load. Run all suites serially so the preflight result is reproducible rather
# than allowing unrelated test-process contention to change its timing.
(cd "$repo_root/packages/control_plane" && dart test --concurrency=1 --reporter compact) || \
  die 'full control-plane suite failed.'

printf 'PREFLIGHT PASS: local candidate, OpenTofu validation, trust verification, and control-plane suite are clean.\n'
if [[ "$phase" == 'aws-identity' ]]; then
  approved_account="${HYFENS_PREFLIGHT_AWS_ACCOUNT_ID:-}"
  approved_region="${HYFENS_PREFLIGHT_AWS_REGION:-}"
  [[ "$approved_account" =~ ^[0-9]{12}$ ]] || \
    die '--aws-identity requires HYFENS_PREFLIGHT_AWS_ACCOUNT_ID (12 digits).'
  [[ "$approved_region" == 'ap-south-1' ]] || \
    die '--aws-identity requires HYFENS_PREFLIGHT_AWS_REGION=ap-south-1.'
  command -v aws >/dev/null 2>&1 || \
    die 'AWS CLI is required for --aws-identity; local phase needs no AWS CLI.'
  actual_account="$(aws sts get-caller-identity --query Account --output text)" || \
    die 'AWS identity lookup failed; no apply was attempted.'
  [[ "$actual_account" == "$approved_account" ]] || \
    die "AWS account mismatch: caller=$actual_account expected=$approved_account."
  printf 'AWS IDENTITY PASS: account=%s region=%s (no apply).\n' "$actual_account" "$approved_region"
else
  printf 'AWS status: NOT RUN (identity/apply/ECR/resources remain external gates).\n'
fi
