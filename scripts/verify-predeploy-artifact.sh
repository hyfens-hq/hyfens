#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: verify-predeploy-artifact.sh \
  --image-ref REF@sha256:DIGEST \
  --expected-digest sha256:DIGEST \
  --sbom FILE \
  --scan FILE \
  --triage-policy FILE \
  --public-key FILE \
  --dockerfile FILE \
  --expected-builder-base REF@sha256:DIGEST \
  --expected-runtime-base REF@sha256:DIGEST \
  [--cosign-image IMAGE] [--local-http-registry]

The local HTTP option is permitted only for localhost/host.docker.internal
test registries and skips transparency-log lookup. It cannot be used with a
non-local registry reference.
EOF
  exit 2
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

IMAGE_REF=''
EXPECTED_DIGEST=''
SBOM=''
SCAN=''
TRIAGE_POLICY=''
PUBLIC_KEY=''
DOCKERFILE=''
EXPECTED_BUILDER_BASE=''
EXPECTED_RUNTIME_BASE=''
COSIGN_IMAGE='ghcr.io/sigstore/cosign/cosign@sha256:b03690aa52bfe94054187142fba24dc54137650682810633901767d8a3e15b31'
LOCAL_HTTP_REGISTRY=0

while (($# > 0)); do
  case "$1" in
    --image-ref) IMAGE_REF=${2:-}; shift 2 ;;
    --expected-digest) EXPECTED_DIGEST=${2:-}; shift 2 ;;
    --sbom) SBOM=${2:-}; shift 2 ;;
    --scan) SCAN=${2:-}; shift 2 ;;
    --triage-policy) TRIAGE_POLICY=${2:-}; shift 2 ;;
    --public-key) PUBLIC_KEY=${2:-}; shift 2 ;;
    --dockerfile) DOCKERFILE=${2:-}; shift 2 ;;
    --expected-builder-base) EXPECTED_BUILDER_BASE=${2:-}; shift 2 ;;
    --expected-runtime-base) EXPECTED_RUNTIME_BASE=${2:-}; shift 2 ;;
    --cosign-image) COSIGN_IMAGE=${2:-}; shift 2 ;;
    --local-http-registry) LOCAL_HTTP_REGISTRY=1; shift ;;
    -h|--help) usage ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done

[[ -n "$IMAGE_REF" && -n "$EXPECTED_DIGEST" && -n "$SBOM" && -n "$SCAN" &&
  -n "$TRIAGE_POLICY" && -n "$PUBLIC_KEY" && -n "$DOCKERFILE" &&
  -n "$EXPECTED_BUILDER_BASE" && -n "$EXPECTED_RUNTIME_BASE" ]] || usage

command -v jq >/dev/null || fail 'jq is required'
command -v sha256sum >/dev/null || fail 'sha256sum is required'
command -v docker >/dev/null || fail 'Docker is required for architecture and cosign verification'

[[ "$EXPECTED_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || fail 'expected digest is not a SHA-256 digest'
[[ "$IMAGE_REF" =~ @sha256:[0-9a-f]{64}$ ]] || fail 'image reference must be digest-addressed'
IMAGE_DIGEST=${IMAGE_REF##*@}
[[ "$IMAGE_DIGEST" == "$EXPECTED_DIGEST" ]] || fail 'image reference digest does not match expected digest'

if ((LOCAL_HTTP_REGISTRY)); then
  IMAGE_HOST=${IMAGE_REF%%/*}
  case "$IMAGE_HOST" in
    localhost:*|127.0.0.1:*|host.docker.internal:*) ;;
    *) fail '--local-http-registry is restricted to a local registry host' ;;
  esac
fi

COSIGN_REF="$IMAGE_REF"
if ((LOCAL_HTTP_REGISTRY)); then
  case "$IMAGE_REF" in
    localhost:*) COSIGN_REF="host.docker.internal:${IMAGE_REF#localhost:}" ;;
    127.0.0.1:*) COSIGN_REF="host.docker.internal:${IMAGE_REF#127.0.0.1:}" ;;
  esac
fi

[[ -s "$SBOM" ]] || fail "SBOM is missing: $SBOM"
[[ -s "$SCAN" ]] || fail "vulnerability scan is missing: $SCAN"
[[ -s "$TRIAGE_POLICY" ]] || fail "triage policy is missing: $TRIAGE_POLICY"
[[ -s "$PUBLIC_KEY" ]] || fail "public key is missing: $PUBLIC_KEY"
[[ -s "$DOCKERFILE" ]] || fail "Dockerfile is missing: $DOCKERFILE"

jq -e '.spdxVersion and (.packages | type == "array")' "$SBOM" >/dev/null ||
  fail 'SBOM is not valid SPDX JSON'
jq -e '.Results | type == "array"' "$SCAN" >/dev/null ||
  fail 'scan output is not valid Trivy JSON'

POLICY_DIGEST=$(jq -r '.image_digest // empty' "$TRIAGE_POLICY")
[[ "$POLICY_DIGEST" == "$EXPECTED_DIGEST" ]] ||
  fail 'triage policy is not bound to the expected image digest'

CRITICAL_HIGH=$(jq -c '.Results[]?.Vulnerabilities[]? |
  select(.Severity == "CRITICAL" or .Severity == "HIGH") |
  {id: .VulnerabilityID, severity: .Severity}' "$SCAN")
while IFS= read -r finding; do
  [[ -n "$finding" ]] || continue
  FINDING_ID=$(jq -r '.id' <<<"$finding")
  FINDING_SEVERITY=$(jq -r '.severity' <<<"$finding")
  FINDING_STATUS=$(jq -r --arg id "$FINDING_ID" '.findings[$id].status // empty' "$TRIAGE_POLICY")
  case "$FINDING_STATUS" in
    FIX_AVAILABLE|UPSTREAM_NO_FIX|NOT_PRESENT_IN_RUNTIME_STAGE|NOT_REACHABLE_WITH_EVIDENCE|FALSE_POSITIVE_WITH_EVIDENCE|REQUIRES_BASE_IMAGE_CHANGE|REQUIRES_DEPENDENCY_CHANGE|MAINTAINER_RISK_DECISION_REQUIRED) ;;
    *) fail "unclassified $FINDING_SEVERITY finding: $FINDING_ID" ;;
  esac
  jq -e --arg id "$FINDING_ID" --arg status "$FINDING_STATUS" \
    '.findings[$id].evidence != null and (.findings[$id].status == $status)' \
    "$TRIAGE_POLICY" >/dev/null || fail "missing evidence for $FINDING_ID"
done <<<"$CRITICAL_HIGH"

SCAN_COUNTS=$(jq -r '[.Results[]?.Vulnerabilities[]?] |
  "critical=\([map(select(.Severity == "CRITICAL")) | length]) " +
  "high=\([map(select(.Severity == "HIGH")) | length]) " +
  "medium=\([map(select(.Severity == "MEDIUM")) | length]) " +
  "low=\([map(select(.Severity == "LOW")) | length]) " +
  "unknown=\([map(select(.Severity == "UNKNOWN")) | length])"' "$SCAN")

BUILDER_BASE=$(sed -nE 's/^FROM (dart@sha256:[0-9a-f]{64}) AS build$/\1/p' "$DOCKERFILE")
RUNTIME_BASE=$(sed -nE 's/^FROM (gcr.io\/distroless\/base-debian13:nonroot@sha256:[0-9a-f]{64}) AS runtime$/\1/p' "$DOCKERFILE")
[[ "$BUILDER_BASE" == "$EXPECTED_BUILDER_BASE" ]] || fail 'builder base digest is not pinned as expected'
[[ "$RUNTIME_BASE" == "$EXPECTED_RUNTIME_BASE" ]] || fail 'runtime base digest is not pinned as expected'

ARCH_OUTPUT=$(docker buildx imagetools inspect "$IMAGE_REF" 2>/dev/null) ||
  fail 'could not inspect image architecture'
grep -q 'Platform:[[:space:]]*linux/arm64' <<<"$ARCH_OUTPUT" ||
  fail 'candidate image is not explicitly linux/arm64'

PUBLIC_KEY_DIR=$(cd "$(dirname "$PUBLIC_KEY")" && pwd)
PUBLIC_KEY_NAME=$(basename "$PUBLIC_KEY")
COSIGN_TMP=$(mktemp -d /tmp/hyfens-predeploy.XXXXXX)
trap 'rm -f "$COSIGN_TMP/verify.json" "$COSIGN_TMP/attestation.json" "$COSIGN_TMP/payload.json" "$COSIGN_TMP/predicate.json"; rmdir "$COSIGN_TMP" 2>/dev/null || true' EXIT

cosign_run() {
  local subcommand=$1
  shift
  local local_flags=()
  if ((LOCAL_HTTP_REGISTRY)); then
    local_flags+=(--allow-http-registry --allow-insecure-registry --insecure-ignore-tlog)
  fi
  if command -v cosign >/dev/null; then
    cosign "$subcommand" "${local_flags[@]}" "$@"
  else
    docker run --rm --add-host=host.docker.internal:host-gateway \
      -v "$PUBLIC_KEY_DIR:/work:ro" -w /work "$COSIGN_IMAGE" \
      "$subcommand" "${local_flags[@]}" "$@"
  fi
}

cosign_run verify --key "/work/$PUBLIC_KEY_NAME" "$COSIGN_REF" >"$COSIGN_TMP/verify.json" ||
  fail 'OCI signature verification failed'
cosign_run verify-attestation --key "/work/$PUBLIC_KEY_NAME" --type custom "$COSIGN_REF" >"$COSIGN_TMP/attestation.json" ||
  fail 'provenance attestation verification failed'

jq -e '.payload and (.signatures | length > 0)' "$COSIGN_TMP/attestation.json" >/dev/null ||
  fail 'attestation output has no signed payload'
jq -r '.payload' "$COSIGN_TMP/attestation.json" | base64 -d >"$COSIGN_TMP/payload.json" ||
  fail 'attestation payload is not base64 JSON'
jq -e --arg digest "$EXPECTED_DIGEST" \
  '.subject[0].digest.sha256 == ($digest | sub("^sha256:"; ""))' \
  "$COSIGN_TMP/payload.json" >/dev/null || fail 'attestation subject digest mismatch'
jq -r '.predicate.Data' "$COSIGN_TMP/payload.json" >"$COSIGN_TMP/predicate.json"
jq -e . "$COSIGN_TMP/predicate.json" >/dev/null || fail 'provenance predicate is not JSON'

DOCKERFILE_DIGEST=$(sha256sum "$DOCKERFILE" | awk '{print $1}')
SBOM_DIGEST=$(sha256sum "$SBOM" | awk '{print $1}')
jq -e --arg dockerfile "$DOCKERFILE_DIGEST" --arg sbom "$SBOM_DIGEST" \
  --arg digest "${EXPECTED_DIGEST#sha256:}" \
  '.buildDefinition.dockerfileSha256 == $dockerfile and
   ([.materials[]?.digest.sha256] | index($dockerfile)) != null and
   ([.materials[]?.digest.sha256] | index($sbom)) != null and
   ([.subject[]?.digest.sha256] | index($digest)) != null and
   .metadata.architecture == "linux/arm64"' \
  "$COSIGN_TMP/predicate.json" >/dev/null || fail 'provenance bindings do not match current inputs'

printf 'PASS: digest=%s architecture=linux/arm64 %s signature=valid provenance=valid\n' "$EXPECTED_DIGEST" "$SCAN_COUNTS"
