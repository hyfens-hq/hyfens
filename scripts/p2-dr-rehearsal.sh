#!/usr/bin/env bash
set -euo pipefail

# Canonical, disposable PostgreSQL + object-store recovery rehearsal. It
# requires HYFENS_ALLOW_RESTORE=1 because it intentionally destroys its own
# unique Compose volumes before restoring the captured backups.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="${HYFENS_DR_COMPOSE_FILE:-$repo_root/deploy/p2/docker-compose.yml}"
project="${HYFENS_DR_PROJECT:-hyfens-p2-dr-${PPID}-$$}"
control_port="${HYFENS_DR_CONTROL_PORT:-18084}"
postgres_port="${HYFENS_DR_POSTGRES_PORT:-55443}"
object_port="${HYFENS_DR_OBJECT_PORT:-59010}"
endpoint="http://127.0.0.1:${control_port}"
work="$(mktemp -d "${TMPDIR:-/tmp}/hyfens-dr.XXXXXX")"
: >"$work/timings.txt"
compose=(docker compose -p "$project" -f "$compose_file")
started=0

if [[ "${HYFENS_ALLOW_RESTORE:-}" != 1 ]]; then
  echo 'Set HYFENS_ALLOW_RESTORE=1 only for this disposable recovery rehearsal.' >&2
  exit 2
fi

cleanup() {
  set +e
  if [[ "$started" == 1 ]]; then
    "${compose[@]}" down -v --remove-orphans >/dev/null 2>&1
  fi
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 2
  }
}
require_command docker
require_command curl
require_command python3
require_command dart
require_command shasum

export HYFENS_POSTGRES_PASSWORD="${HYFENS_POSTGRES_PASSWORD:-local-dr-postgres-$(date +%s)}"
export HYFENS_S3_ACCESS_KEY="${HYFENS_S3_ACCESS_KEY:-hyfens-dr}"
export HYFENS_S3_SECRET_KEY="${HYFENS_S3_SECRET_KEY:-local-dr-object-$(date +%s)}"
export HYFENS_S3_BUCKET="${HYFENS_S3_BUCKET:-hyfens-dr-artifacts}"
export HYFENS_CONTROL_PLANE_PORT="$control_port"
export HYFENS_POSTGRES_PORT="$postgres_port"
export HYFENS_S3_PORT="$object_port"
db_url="postgresql://hyfens:${HYFENS_POSTGRES_PASSWORD}@127.0.0.1:${postgres_port}/hyfens?sslmode=disable"
network="$project"_default

now_ms() {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}
record_timing() {
  printf '%s=%s\n' "$1" "$(($3 - $2))" >>"$work/timings.txt"
}
wait_status() {
  local path="$1" expected="$2" attempts="${3:-60}" status
  for _ in $(seq 1 "$attempts"); do
    status="$(curl -sS -o "$work/response" -w '%{http_code}' "$endpoint$path" || true)"
    [[ "$status" == "$expected" ]] && return 0
    sleep 1
  done
  echo "timeout waiting for $path=$expected (last=$status)" >&2
  cat "$work/response" >&2 || true
  return 1
}
wait_service_healthy() {
  local service="$1" id status
  id="$("${compose[@]}" ps -q "$service")"
  for _ in $(seq 1 60); do
    status="$(docker inspect -f '{{.State.Health.Status}}' "$id" 2>/dev/null || true)"
    [[ "$status" == healthy ]] && return 0
    sleep 1
  done
  echo "$service did not become healthy" >&2
  docker inspect "$id" >&2 || true
  return 1
}
api_json() {
  local method="$1" path="$2" token="$3" body="$4" response="$5"
  local args=(-sS -o "$response" -w '%{http_code}' -X "$method" "$endpoint$path")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  if [[ "$method" == POST || "$method" == PUT ]]; then
    args+=(-H "Idempotency-Key: dr-$(printf '%s' "$path" | shasum -a 256 | awk '{print $1}')")
  fi
  if [[ "$body" != - ]]; then
    args+=(-H 'Content-Type: application/json' --data-binary "@$body")
  fi
  curl "${args[@]}"
}
api_artifact() {
  curl -sS -o "$4" -w '%{http_code}' -X PUT "$endpoint$1" \
    -H "Authorization: Bearer $2" -H 'Idempotency-Key: dr-artifact-upload' \
    -H 'Content-Type: application/octet-stream' --data-binary "@$3"
}
assert_status() {
  local actual="$1" expected="$2" operation="$3"
  case ",$expected," in *",$actual,"*) return 0;; esac
  echo "$operation failed with HTTP $actual" >&2
  cat "$work/response" >&2 || true
  exit 1
}
json_value() {
  python3 - "$1" "$2" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
for part in sys.argv[2].split('.'):
    value = value[part]
print(value)
PY
}
assert_json() {
  local actual
  actual="$(json_value "$1" "$2")"
  [[ "$actual" == "$3" ]] || { echo "expected $2=$3, got $actual" >&2; cat "$1" >&2; exit 1; }
}

echo "dr_project=$project"
echo "dr_endpoint=$endpoint"
start="$(now_ms)"
"${compose[@]}" config >/dev/null
"${compose[@]}" up -d --build >/dev/null
started=1
record_timing compose_up "$start" "$(now_ms)"
wait_status /healthz 200
wait_status /readyz 200
"${compose[@]}" run --rm control-plane --bootstrap --bootstrap-only \
  --application dr_fixture_app --platform android-arm64-release \
  --environment development >"$work/bootstrap.txt"

python3 - "$work/bootstrap.txt" "$work/credentials.env" <<'PY'
import shlex, sys
required = {'organization_id', 'application_id', 'environment_id', 'control_token', 'delivery_token'}
values = {}
for line in open(sys.argv[1]):
    if '=' in line:
        key, value = line.rstrip('\n').split('=', 1)
        if key in required: values[key] = value
if required - values.keys(): raise SystemExit('bootstrap output is incomplete')
with open(sys.argv[2], 'w') as out:
    for key in sorted(values): out.write(f'{key}={shlex.quote(values[key])}\n')
PY
# shellcheck disable=SC1090
source "$work/credentials.env"

(
  cd "$repo_root/experiments/patch_loading"
  dart run bin/ha_make_artifact.dart --public-key-only true --public-key-output "$work/public-key.hex"
)
public_key_b64="$(python3 - "$work/public-key.hex" <<'PY'
import base64, sys
print(base64.b64encode(bytes.fromhex(open(sys.argv[1]).read().strip())).decode())
PY
)"
python3 - "$work/release.json" "$application_id" "$public_key_b64" <<'PY'
import json, sys
path, app, public_key = sys.argv[1:]
digest = 'sha256:' + ('2' * 64)
json.dump({
  'application_id': app,
  'platform_id': 'plt_android',
  'runtime_application_id': 'dr_fixture_app',
  'runtime_release_id': 'release_dr_1',
  'build_target': 'android-arm64-release',
  'runtime_compatibility_version': 1,
  'patch_format_version': 1,
  'build_fingerprint': digest,
  'capability_authority_digest': digest,
  'function_signature_digest': digest,
  'display_version': '0.1.0-dr',
  'signing_public_keys': {'ha-fixture-key': public_key},
}, open(path, 'w'))
PY
status="$(api_json POST "/v1/organizations/$organization_id/applications/$application_id/releases" "$control_token" "$work/release.json" "$work/response")"
assert_status "$status" '200,201' release_register
release_service_id="$(json_value "$work/response" id)"

(
  cd "$repo_root/experiments/patch_loading"
  dart run bin/ha_make_artifact.dart --output "$work/artifact.bin" \
    --application dr_fixture_app --release release_dr_1 --patch patch_dr_1 --sequence 1
)
artifact_digest="sha256:$(shasum -a 256 "$work/artifact.bin" | awk '{print $1}')"
artifact_size="$(wc -c <"$work/artifact.bin" | tr -d ' ')"
python3 - "$work/patch.json" "$artifact_digest" "$artifact_size" <<'PY'
import json, sys
path, digest, size = sys.argv[1:]
json.dump({
  'runtime_patch_id': 'patch_dr_1',
  'sequence': 1,
  'artifact_id': 'artifact_dr_1',
  'sha256': digest,
  'size_bytes': int(size),
  'signature_key_id': 'ha-fixture-key',
}, open(path, 'w'))
PY
status="$(api_json POST "/v1/organizations/$organization_id/releases/$release_service_id/patches" "$control_token" "$work/patch.json" "$work/response")"
assert_status "$status" '200,201' patch_register
status="$(api_artifact "/v1/organizations/$organization_id/artifacts/artifact_dr_1" "$control_token" "$work/artifact.bin" "$work/response")"
assert_status "$status" '200,201' artifact_upload
python3 - "$work/promotion.json" "$release_service_id" <<'PY'
import json, sys
json.dump({'release_id': sys.argv[2], 'expected_version': 0}, open(sys.argv[1], 'w'))
PY
status="$(api_json POST "/v1/organizations/$organization_id/environments/$environment_id/release-promotions" "$control_token" "$work/promotion.json" "$work/response")"
assert_status "$status" '200' promotion

start="$(now_ms)"
(
  cd "$work"
  HYFENS_DATABASE_URL="$db_url" "$repo_root/scripts/p2-postgres-backup.sh" database.dump
  HYFENS_OBJECT_ENDPOINT='http://object-store:9000/' \
  HYFENS_S3_BUCKET="$HYFENS_S3_BUCKET" \
  HYFENS_S3_ACCESS_KEY="$HYFENS_S3_ACCESS_KEY" \
  HYFENS_S3_SECRET_KEY="$HYFENS_S3_SECRET_KEY" \
  HYFENS_S3_DOCKER_NETWORK="$network" \
  "$repo_root/scripts/p2-object-backup.sh" object-backup
)
cp "$work/artifact.bin" "$work/source-artifact.bin"
source_digest="$artifact_digest"
backup_digest="$(shasum -a 256 "$work/database.dump" "$work/object-backup/manifest.sha256" | shasum -a 256 | awk '{print $1}')"
record_timing backup_and_manifest "$start" "$(now_ms)"

"${compose[@]}" down -v --remove-orphans >/dev/null
started=0
start="$(now_ms)"
"${compose[@]}" up -d postgres object-store >/dev/null
started=1
wait_service_healthy postgres
wait_service_healthy object-store
"${compose[@]}" run --rm object-bootstrap >/dev/null
(
  cd "$work"
  HYFENS_ALLOW_RESTORE=1 HYFENS_DATABASE_URL="$db_url" \
    "$repo_root/scripts/p2-postgres-restore.sh" database.dump
  HYFENS_ALLOW_RESTORE=1 HYFENS_OBJECT_ENDPOINT='http://object-store:9000/' \
  HYFENS_S3_BUCKET="$HYFENS_S3_BUCKET" \
  HYFENS_S3_ACCESS_KEY="$HYFENS_S3_ACCESS_KEY" \
  HYFENS_S3_SECRET_KEY="$HYFENS_S3_SECRET_KEY" \
  HYFENS_S3_DOCKER_NETWORK="$network" \
    "$repo_root/scripts/p2-object-restore.sh" object-backup
)
"${compose[@]}" up -d control-plane >/dev/null
wait_status /healthz 200
wait_status /readyz 200
record_timing destroy_recreate_restore "$start" "$(now_ms)"

status="$(api_json POST "/v1/organizations/$organization_id/artifact-reconciliation" "$control_token" - "$work/response")"
assert_status "$status" '200' reconciliation
assert_json "$work/response" deliverable True
status="$(api_json GET "/v1/organizations/$organization_id/audit" "$control_token" - "$work/response")"
assert_status "$status" '200' audit_export
assert_json "$work/response" verification.valid True
status="$(curl -sS -o "$work/fetched.bin" -w '%{http_code}' \
  -H "Authorization: Bearer $delivery_token" \
  "$endpoint/v1/runtime/artifacts/artifact_dr_1?application_id=$application_id&environment_id=$environment_id")"
assert_status "$status" '200' artifact_fetch
restored_digest="sha256:$(shasum -a 256 "$work/fetched.bin" | awk '{print $1}')"
[[ "$restored_digest" == "$source_digest" ]] || { echo 'restored artifact digest mismatch' >&2; exit 1; }

echo 'dr_rehearsal=PASS'
echo 'evidence=DISASTER_RECOVERY_DIRECTIONAL'
echo "source_artifact_digest=$source_digest"
echo "restored_artifact_digest=$restored_digest"
echo "backup_manifest_digest=$backup_digest"
echo 'data_loss_observed=none_in_quiesced_rehearsal'
echo 'manual_actions=confirm_disposable_target,approve_restore,verify_backup_retention,review_provider_RPO_RTO'
echo 'not_proven=provider_backup_durability,automated_failover,approved_RPO_RTO'
cat "$work/timings.txt"
