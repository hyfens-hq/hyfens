#!/usr/bin/env bash
set -euo pipefail

# Produce a bounded, repository-controlled provenance inventory. This is not a
# replacement for a registry attestation or an SBOM service.

image="${1:-}"
if [[ -z "$image" ]]; then
  echo "usage: p2-provenance-inventory.sh IMAGE_REF" >&2
  exit 2
fi
command -v docker >/dev/null 2>&1 || { echo 'docker is required' >&2; exit 2; }
command -v shasum >/dev/null 2>&1 || { echo 'shasum is required' >&2; exit 2; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dockerfile="$repo_root/deploy/p2/Dockerfile"
source_digest="$(
  {
    find "$repo_root/packages/control_plane" "$repo_root/packages/patch_format" \
      "$repo_root/deploy/p2" -type f \
      ! -path '*/.dart_tool/*' ! -name '*.lock' -print |
      LC_ALL=C sort |
      while IFS= read -r file; do
        printf '%s  ' "${file#"$repo_root/"}"
        shasum -a 256 "$file" | awk '{print $1}'
      done
  } | shasum -a 256 | awk '{print $1}'
)"
image_json="$(docker image inspect "$image" | python3 -c '
import json, sys
v=json.load(sys.stdin)[0]
print(json.dumps({
  "id": v.get("Id"),
  "created": v.get("Created"),
  "architecture": v.get("Architecture"),
  "os": v.get("Os"),
  "repoDigests": v.get("RepoDigests", []),
}, sort_keys=True))
')"
dockerfile_digest="$(shasum -a 256 "$dockerfile" | awk '{print $1}')"
python3 - "$image" "$source_digest" "$dockerfile_digest" "$image_json" <<'PY'
import json, sys
image, source, dockerfile, image_json = sys.argv[1:]
print(json.dumps({
  "schemaVersion": 1,
  "evidence": "IMAGE_PROVENANCE_BOUNDED",
  "imageRef": image,
  "image": json.loads(image_json),
  "sourceTreeDigest": "sha256:" + source,
  "dockerfileDigest": "sha256:" + dockerfile,
  "baseReferences": [
    "dart:stable (deploy/p2/Dockerfile)",
    "postgres:17-alpine (deploy/p2/docker-compose.yml)",
    "minio/minio:latest (deploy/p2/docker-compose.yml)",
    "minio/mc:latest (deploy/p2/docker-compose.yml)",
  ],
  "claims": [
    "local image identity and source/config digests are recorded",
    "base image references are recorded as tags only",
    "no registry signature, remote immutable digest, or build attestation is asserted",
  ],
}, sort_keys=True, indent=2))
PY
