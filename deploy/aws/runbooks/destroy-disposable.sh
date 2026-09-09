#!/usr/bin/env bash
set -euo pipefail

# This runbook is intentionally fail-closed. It is a destructive operation,
# and the environment/account/evidence checks below must all pass before
# OpenTofu is allowed to contact AWS.

die() {
  printf 'Refusing teardown: %s\n' "$1" >&2
  exit 2
}

[[ "${HYFENS_ALLOW_DISPOSABLE_DESTROY:-}" == "1" ]] || \
  die 'set HYFENS_ALLOW_DISPOSABLE_DESTROY=1 explicitly.'
[[ "${HYFENS_DISPOSABLE_TEARDOWN_ACK:-}" == "I_UNDERSTAND_DISPOSABLE_TEARDOWN" ]] || \
  die 'set HYFENS_DISPOSABLE_TEARDOWN_ACK=I_UNDERSTAND_DISPOSABLE_TEARDOWN.'

expected_environment='hyfens-task78-disposable'
environment_name="${HYFENS_DISPOSABLE_ENVIRONMENT_NAME:-}"
[[ "$environment_name" == "$expected_environment" ]] || \
  die "environment guard requires HYFENS_DISPOSABLE_ENVIRONMENT_NAME=$expected_environment."

expected_region='ap-south-1'
region="${HYFENS_DISPOSABLE_REGION:-}"
[[ "$region" == "$expected_region" ]] || \
  die "region guard requires HYFENS_DISPOSABLE_REGION=$expected_region."

account_id="${HYFENS_DISPOSABLE_ACCOUNT_ID:-}"
[[ "$account_id" =~ ^[0-9]{12}$ ]] || \
  die 'account guard requires a 12-digit HYFENS_DISPOSABLE_ACCOUNT_ID.'

scope_tag='disposable-task78'
[[ "${HYFENS_DISPOSABLE_SCOPE_TAG:-}" == "$scope_tag" ]] || \
  die "resource-tag guard requires HYFENS_DISPOSABLE_SCOPE_TAG=$scope_tag."

evidence_dir="${HYFENS_DISPOSABLE_EVIDENCE_DIR:-}"
[[ -n "$evidence_dir" && -d "$evidence_dir" ]] || \
  die 'evidence-export guard requires an existing HYFENS_DISPOSABLE_EVIDENCE_DIR.'
[[ "${HYFENS_DISPOSABLE_EVIDENCE_EXPORTED:-}" == "1" ]] || \
  die 'set HYFENS_DISPOSABLE_EVIDENCE_EXPORTED=1 after exporting redacted evidence.'
[[ -f "$evidence_dir/teardown-export.complete" ]] || \
  die 'evidence-export guard requires teardown-export.complete in the evidence directory.'

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
state_dir="$repo_root/deploy/aws/environments/disposable"
[[ -d "$state_dir" ]] || die "missing disposable environment directory: $state_dir"

tofu_image="${HYFENS_TOFU_IMAGE:-ghcr.io/opentofu/opentofu:1.10.0}"
tofu() {
  docker run --rm \
    -v "$state_dir:/workspace" \
    -w /workspace \
    "$tofu_image" "$@"
}

[[ -f "$state_dir/state/disposable.tfstate" ]] || \
  die 'no disposable state file found; refusing to destroy an unknown scope.'

# Validate the state without contacting AWS. Every tagged managed resource
# must carry the exact project/environment/scope tags before a destroy is
# considered. Resources without tags are rejected rather than guessed safe.
state_json="$(tofu show -json state/disposable.tfstate)" || \
  die 'unable to read disposable state for the resource-tag guard.'
if ! command -v jq >/dev/null 2>&1; then
  die 'jq is required for the resource-tag guard.'
fi
tag_check="$(printf '%s' "$state_json" | jq -r --arg env "$environment_name" --arg scope "$scope_tag" '
  [.. | objects | select(has("values") and (.values | type == "object") and (.values | has("tags"))) | .values.tags
   | select(type == "object")
   | select(.Project == "hyfens" and .Environment == $env and .ManagedBy == "opentofu" and .Scope == $scope)]
  | length')"
tagged_resources="$(printf '%s' "$state_json" | jq '[.. | objects | select(has("values") and (.values | type == "object") and (.values | has("tags"))) | .values.tags | select(type == "object")] | length')"
[[ "$tagged_resources" != '0' && "$tag_check" == "$tagged_resources" ]] || \
  die 'resource-tag guard failed: state contains an unapproved tag set.'

# Confirm the caller account before the destructive command. The AWS CLI is
# intentionally a host/operator prerequisite; an unpinned fallback image
# must not become part of a destructive trust decision.
command -v aws >/dev/null 2>&1 || die 'AWS CLI is required for the account guard.'
actual_account="$(aws sts get-caller-identity --query Account --output text)" || \
  die 'unable to resolve the authenticated AWS account; no destroy was attempted.'
[[ "$actual_account" == "$account_id" ]] || \
  die "account guard failed: caller account $actual_account does not match the approved account."

tofu destroy -auto-approve \
  -var 'allow_destroy=true' \
  -var "environment_name=$environment_name" \
  -var "aws_region=$region"
printf '%s\n' 'Verify the AWS account has no task78-disposable resources before closing evidence.'
