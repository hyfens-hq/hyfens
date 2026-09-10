#!/usr/bin/env bash
set -euo pipefail

image_tag="${HYFENS_IMAGE_TAG:-hyfens/task78-control-plane:local}"
platform="${HYFENS_IMAGE_PLATFORM:-linux/arm64}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

docker build --platform "$platform" -f "$repo_root/deploy/aws/Dockerfile" \
  -t "$image_tag" "$repo_root"
digest="$(docker image inspect "$image_tag" --format '{{index .RepoDigests 0}}')"
printf 'image=%s\n' "$digest"
printf 'base_digest=sha256:8b6175f6c6b89aaf31ffdace4a22d17715c07f1cf3a772dadb10c658f779e23d\n'
printf '%s\n' 'Generate SBOM/scan/signature/provenance evidence before ECR push.'
