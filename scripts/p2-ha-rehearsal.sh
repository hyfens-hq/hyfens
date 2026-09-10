#!/usr/bin/env bash
set -euo pipefail

# Disposable two-instance application HA rehearsal. This is deliberately a
# repository-controlled evidence script, not a production deployment tool.
# It creates and removes only its unique Compose project and named volumes.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="${HYFENS_HA_COMPOSE_FILE:-$repo_root/deploy/p2/docker-compose.ha.yml}"
project="${HYFENS_HA_PROJECT:-hyfens-p2-ha-${PPID}-$$}"
port="${HYFENS_HA_PORT:-18083}"
endpoint="http://127.0.0.1:${port}"
extended="${HYFENS_HA_EXTENDED:-0}"
work="$(mktemp -d "${TMPDIR:-/tmp}/hyfens-ha.XXXXXX")"
: >"$work/timings.txt"
compose=(docker compose -p "$project" -f "$compose_file")
started=0

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

export HYFENS_POSTGRES_PASSWORD="${HYFENS_POSTGRES_PASSWORD:-local-ha-postgres-$(date +%s)}"
export HYFENS_S3_ACCESS_KEY="${HYFENS_S3_ACCESS_KEY:-hyfens-ha}"
export HYFENS_S3_SECRET_KEY="${HYFENS_S3_SECRET_KEY:-local-ha-object-$(date +%s)}"
export HYFENS_S3_BUCKET="${HYFENS_S3_BUCKET:-hyfens-ha-artifacts}"
export HYFENS_HA_PORT="$port"

now_ms() {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

record_timing() {
  local name="$1" start="$2" end="$3"
  printf '%s=%s\n' "$name" "$((end - start))" >>"$work/timings.txt"
}

wait_status() {
  local path="$1" expected="$2" attempts="${3:-60}"
  local status
  for _ in $(seq 1 "$attempts"); do
    status="$(curl -sS -o "$work/last-response" -w '%{http_code}' "$endpoint$path" || true)"
    if [[ "$status" == "$expected" ]]; then return 0; fi
    sleep 1
  done
  echo "timed out waiting for $path status $expected (last=$status)" >&2
  cat "$work/last-response" >&2 || true
  return 1
}

api_json() {
  local method="$1" path="$2" token="$3" body_file="$4" response_file="$5"
  local status
  local args=(-sS -D "$work/headers" -o "$response_file" -w '%{http_code}' -X "$method" "$endpoint$path")
  if [[ -n "$token" ]]; then args+=(-H "Authorization: Bearer $token"); fi
  if [[ "$method" == POST || "$method" == PUT ]]; then
    local idempotency="ha-${method}-$(printf '%s' "$path" | shasum -a 256 | awk '{print $1}')"
    args+=(-H "Idempotency-Key: $idempotency")
  fi
  if [[ "$body_file" != "-" ]]; then
    args+=(-H 'Content-Type: application/json' --data-binary "@$body_file")
  fi
  status="$(curl "${args[@]}")"
  printf '%s' "$status"
}

api_artifact() {
  local path="$1" token="$2" body_file="$3" response_file="$4"
  curl -sS -D "$work/headers" -o "$response_file" -w '%{http_code}' -X PUT "$endpoint$path" \
    -H "Authorization: Bearer $token" \
    -H "Idempotency-Key: ha-artifact-upload" \
    -H 'Content-Type: application/octet-stream' \
    --data-binary "@$body_file"
}

assert_request_id() {
  local operation="$1" request_id
  request_id="$(awk 'tolower($1) == "x-request-id:" {gsub("\\r", "", $2); print $2; exit}' "$work/headers")"
  if [[ -z "$request_id" || ! "$request_id" =~ ^[A-Za-z0-9._:-]{1,128}$ ]]; then
    echo "$operation did not return a bounded X-Request-Id" >&2
    cat "$work/headers" >&2 || true
    exit 1
  fi
  printf 'request_id_%s=%s\n' "$operation" "$request_id"
}

container_status() {
  local service="$1" path="$2" container
  container="$("${compose[@]}" ps -q "$service" 2>/dev/null || true)"
  [[ -n "$container" ]] || return 1
  docker exec "$container" curl -sS -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:18081$path" 2>/dev/null || true
}

wait_container_status() {
  local service="$1" path="$2" expected="$3" attempts="${4:-60}"
  local status='000'
  for _ in $(seq 1 "$attempts"); do
    status="$(container_status "$service" "$path")"
    if [[ "$status" == "$expected" ]]; then return 0; fi
    sleep 1
  done
  echo "timed out waiting for $service$path status $expected (last=$status)" >&2
  return 1
}

fetch_artifact() {
  curl -sS -D "$work/headers" -o "$work/fetched.bin" -w '%{http_code}' \
    -H "Authorization: Bearer $delivery_token" \
    "$endpoint/v1/runtime/artifacts/artifact_ha_1?application_id=$application_id&environment_id=$environment_id"
}

assert_status() {
  local actual="$1" expected="$2" operation="$3"
  case ",$expected," in
    *",$actual,"*) return 0 ;;
  esac
  echo "$operation returned HTTP $actual; expected one of $expected" >&2
  cat "$work/response" >&2 || true
  exit 1
}

json_value() {
  local file="$1" expression="$2"
  python3 - "$file" "$expression" <<'PY'
import base64, json, sys
value = json.load(open(sys.argv[1]))
for part in sys.argv[2].split('.'):
    value = value[part]
print(value)
PY
}

json_assert() {
  local file="$1" expression="$2" expected="$3"
  local actual
  actual="$(json_value "$file" "$expression")"
  [[ "$actual" == "$expected" ]] || {
    echo "JSON assertion failed: $expression=$actual expected $expected" >&2
    cat "$file" >&2
    exit 1
  }
}

echo "ha_project=$project"
echo "ha_endpoint=$endpoint"
start="$(now_ms)"
"${compose[@]}" config >/dev/null
"${compose[@]}" up -d --build >/dev/null
started=1
record_timing compose_up "$start" "$(now_ms)"

start="$(now_ms)"
wait_status /healthz 200
wait_status /readyz 200
record_timing both_ready "$start" "$(now_ms)"

if [[ "$extended" == 1 ]]; then
  wait_container_status control-plane-1 /livez 200
  wait_container_status control-plane-2 /livez 200
  wait_container_status control-plane-1 /readyz 200
  wait_container_status control-plane-2 /readyz 200
fi

"${compose[@]}" run --rm control-plane-1 --bootstrap --bootstrap-only \
  --application ha_fixture_app --platform android-arm64-release \
  --environment development >"$work/bootstrap.txt"
python3 - "$work/bootstrap.txt" "$work/credentials.env" <<'PY'
import shlex, sys
required = {'organization_id', 'application_id', 'environment_id', 'control_token', 'delivery_token'}
values = {}
for line in open(sys.argv[1]):
    if '=' in line:
        key, value = line.rstrip('\n').split('=', 1)
        if key in required: values[key] = value
missing = required - values.keys()
if missing: raise SystemExit(f'missing bootstrap keys: {sorted(missing)}')
with open(sys.argv[2], 'w') as out:
    for key in sorted(values): out.write(f'{key}={shlex.quote(values[key])}\n')
PY
# shellcheck disable=SC1090
source "$work/credentials.env"

(
  cd "$repo_root/experiments/patch_loading"
  dart run bin/ha_make_artifact.dart \
    --public-key-only true \
    --public-key-output "$work/public-key.hex"
)
public_key_b64="$(python3 - "$work/public-key.hex" <<'PY'
import base64, sys
print(base64.b64encode(bytes.fromhex(open(sys.argv[1]).read().strip())).decode())
PY
)"

python3 - "$work/release.json" "$organization_id" "$application_id" "$public_key_b64" <<'PY'
import json, sys
path, org, app, public_key = sys.argv[1:]
digest = 'sha256:' + ('1' * 64)
json.dump({
  'application_id': app,
  'platform_id': 'plt_android',
  'runtime_application_id': 'ha_fixture_app',
  'runtime_release_id': 'release_ha_1',
  'build_target': 'android-arm64-release',
  'runtime_compatibility_version': 1,
  'patch_format_version': 1,
  'build_fingerprint': digest,
  'capability_authority_digest': digest,
  'function_signature_digest': digest,
  'display_version': '0.1.0-ha',
  'signing_public_keys': {'ha-fixture-key': public_key},
}, open(path, 'w'))
PY

start="$(now_ms)"
status="$(api_json POST "/v1/organizations/$organization_id/applications/$application_id/releases" "$control_token" "$work/release.json" "$work/response")"
assert_status "$status" '200,201' register_release
status="$(api_json POST "/v1/organizations/$organization_id/applications/$application_id/releases" "$control_token" "$work/release.json" "$work/response")"
assert_status "$status" '200,201,409' idempotent_release_retry
release_service_id="$(json_value "$work/response" id)"
record_timing release_write_and_retry "$start" "$(now_ms)"

(
  cd "$repo_root/experiments/patch_loading"
  dart run bin/ha_make_artifact.dart \
    --output "$work/artifact.bin" \
    --application ha_fixture_app \
    --release release_ha_1 \
    --patch patch_ha_1 \
    --sequence 1
)
artifact_digest="sha256:$(shasum -a 256 "$work/artifact.bin" | awk '{print $1}')"
artifact_size="$(wc -c <"$work/artifact.bin" | tr -d ' ')"
python3 - "$work/patch.json" "$artifact_digest" "$artifact_size" <<'PY'
import json, sys
path, digest, size = sys.argv[1:]
json.dump({
  'runtime_patch_id': 'patch_ha_1',
  'sequence': 1,
  'artifact_id': 'artifact_ha_1',
  'sha256': digest,
  'size_bytes': int(size),
  'signature_key_id': 'ha-fixture-key',
}, open(path, 'w'))
PY
status="$(api_json POST "/v1/organizations/$organization_id/releases/$release_service_id/patches" "$control_token" "$work/patch.json" "$work/response")"
assert_status "$status" '200,201' register_patch
status="$(api_artifact "/v1/organizations/$organization_id/artifacts/artifact_ha_1" "$control_token" "$work/artifact.bin" "$work/response")"
assert_status "$status" '200,201' upload_artifact
python3 - "$work/promotion.json" "$release_service_id" <<'PY'
import json, sys
json.dump({'release_id': sys.argv[2], 'expected_version': 0}, open(sys.argv[1], 'w'))
PY
status="$(api_json POST "/v1/organizations/$organization_id/environments/$environment_id/release-promotions" "$control_token" "$work/promotion.json" "$work/response")"
assert_status "$status" '200' promote_release

start="$(now_ms)"
python3 - "$work/update.json" "$application_id" "$environment_id" <<'PY'
import json, sys
json.dump({
  'application_id': sys.argv[2],
  'environment_id': sys.argv[3],
  'runtime_application_id': 'ha_fixture_app',
  'runtime_release_id': 'release_ha_1',
  'runtime_compatibility_version': 1,
  'patch_format_version': 1,
  'high_water_sequence': 0,
}, open(sys.argv[1], 'w'))
PY
status="$(api_json POST /v1/runtime/update-check "$delivery_token" "$work/update.json" "$work/response")"
assert_status "$status" '200' update_check
assert_request_id update_check
json_assert "$work/response" decision PATCH_AVAILABLE
status="$(fetch_artifact)"
assert_status "$status" '200' fetch_artifact
assert_request_id fetch_artifact
cmp "$work/artifact.bin" "$work/fetched.bin"
record_timing lookup_and_fetch "$start" "$(now_ms)"

if [[ "$extended" == 1 ]]; then
  # A unavailable / B healthy, then A returns.
  start="$(now_ms)"
  "${compose[@]}" stop control-plane-1 >/dev/null
  wait_container_status control-plane-2 /livez 200
  wait_container_status control-plane-2 /readyz 200
  wait_status /healthz 200
  wait_status /readyz 200
  status="$(api_json POST /v1/runtime/update-check "$delivery_token" "$work/update.json" "$work/response")"
  assert_status "$status" '200' lookup_with_instance_1_down
  assert_request_id instance_1_down
  json_assert "$work/response" decision PATCH_AVAILABLE
  status="$(fetch_artifact)"
  assert_status "$status" '200' fetch_with_instance_1_down
  cmp "$work/artifact.bin" "$work/fetched.bin"
  "${compose[@]}" start control-plane-1 >/dev/null
  wait_container_status control-plane-1 /readyz 200
  record_timing instance_1_down_and_return "$start" "$(now_ms)"

  # B unavailable / A healthy, then B returns.
  start="$(now_ms)"
  "${compose[@]}" stop control-plane-2 >/dev/null
  wait_container_status control-plane-1 /livez 200
  wait_container_status control-plane-1 /readyz 200
  wait_status /healthz 200
  wait_status /readyz 200
  status="$(api_json POST /v1/runtime/update-check "$delivery_token" "$work/update.json" "$work/response")"
  assert_status "$status" '200' lookup_with_instance_2_down
  assert_request_id instance_2_down
  json_assert "$work/response" decision PATCH_AVAILABLE
  status="$(fetch_artifact)"
  assert_status "$status" '200' fetch_with_instance_2_down
  cmp "$work/artifact.bin" "$work/fetched.bin"
  "${compose[@]}" start control-plane-2 >/dev/null
  wait_container_status control-plane-2 /readyz 200
  status="$(api_json POST "/v1/organizations/$organization_id/applications/$application_id/releases" "$delivery_token" "$work/release.json" "$work/response")"
  assert_status "$status" '401,403' delivery_scope_rejected
  assert_request_id delivery_scope_rejected
  record_timing instance_2_down_and_return "$start" "$(now_ms)"

  # Separate dependency outages: liveness remains process-local, readiness
  # is dependency-aware, and object bytes cannot be fetched while unavailable.
  start="$(now_ms)"
  "${compose[@]}" stop postgres >/dev/null
  wait_status /healthz 200
  wait_status /readyz 503 10
  "${compose[@]}" start postgres >/dev/null
  wait_status /readyz 200
  record_timing postgres_outage_and_recovery "$start" "$(now_ms)"

  start="$(now_ms)"
  "${compose[@]}" stop object-store >/dev/null
  wait_status /healthz 200
  wait_status /readyz 503 10
  status="$(fetch_artifact)"
  assert_status "$status" '500,502,503' fetch_during_object_outage
  "${compose[@]}" start object-store >/dev/null
  wait_status /readyz 200
  status="$(fetch_artifact)"
  assert_status "$status" '200' fetch_after_object_recovery
  cmp "$work/artifact.bin" "$work/fetched.bin"
  record_timing object_outage_and_recovery "$start" "$(now_ms)"

  load_requests="${HYFENS_HA_LOAD_REQUESTS:-40}"
  load_concurrency="${HYFENS_HA_LOAD_CONCURRENCY:-8}"
  HYFENS_LOAD_TOKEN="$delivery_token" python3 "$repo_root/scripts/p2-load-test.py" \
    --endpoint "$endpoint" \
    --application-id "$application_id" \
    --environment-id "$environment_id" \
    --runtime-application-id ha_fixture_app \
    --runtime-release-id release_ha_1 \
    --artifact-id artifact_ha_1 \
    --requests "$load_requests" \
    --concurrency "$load_concurrency" | tee "$work/load.json"
  echo 'container_stats=' \
    "$(docker stats --no-stream --format '{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}' \
      "$("${compose[@]}" ps -q control-plane-1)" "$("${compose[@]}" ps -q control-plane-2)" \
      | tr '\n' ';')"
else
  start="$(now_ms)"
  "${compose[@]}" stop control-plane-1 >/dev/null
  wait_status /healthz 200
  wait_status /readyz 200
  status="$(api_json POST "/v1/organizations/$organization_id/applications/$application_id/releases" "$control_token" "$work/release.json" "$work/response")"
  assert_status "$status" '200,201,409' retry_after_instance_loss
  status="$(api_json POST /v1/runtime/update-check "$delivery_token" "$work/update.json" "$work/response")"
  assert_status "$status" '200' lookup_after_instance_loss
  json_assert "$work/response" decision PATCH_AVAILABLE
  record_timing instance_loss_and_retry "$start" "$(now_ms)"

  start="$(now_ms)"
  "${compose[@]}" start control-plane-1 >/dev/null
  wait_status /readyz 200
  "${compose[@]}" restart control-plane-2 >/dev/null
  wait_status /readyz 200
  status="$(api_json POST /v1/runtime/update-check "$delivery_token" "$work/update.json" "$work/response")"
  assert_status "$status" '200' rolling_restart_lookup
  json_assert "$work/response" decision PATCH_AVAILABLE
  record_timing rolling_restart "$start" "$(now_ms)"

  start="$(now_ms)"
  "${compose[@]}" stop postgres object-store >/dev/null
  wait_status /healthz 200
  if wait_status /readyz 503 10; then
    echo 'dependency_outage_readyz=503'
  else
    echo 'dependency_outage_readyz=NOT_OBSERVED' >&2
    exit 1
  fi
  "${compose[@]}" start postgres object-store >/dev/null
  wait_status /readyz 200
  record_timing dependency_outage_and_recovery "$start" "$(now_ms)"
fi

status="$(api_json GET "/v1/organizations/$organization_id/audit" "$control_token" - "$work/response")"
assert_status "$status" '200' audit_export
json_assert "$work/response" verification.valid True

echo 'ha_rehearsal=PASS'
echo 'evidence=APPLICATION_HA_DISPOSABLE'
echo 'dependency_model=SHARED_POSTGRES_AND_OBJECT_STORE'
if [[ "$extended" == 1 ]]; then
  echo 'extended_evidence=MULTI_INSTANCE_LOCAL,LOAD_BALANCER_LOCAL,OBJECT_STORE_OUTAGE,CAPACITY_BASELINE'
  echo 'readiness_model=INSTANCE_LOCAL_WITH_PASSIVE_PROXY_RETRY'
  echo 'metrics_model=PROCESS_LOCAL_NO_GLOBAL_AGGREGATION'
fi
echo 'not_proven=database_or_object_store_failover,public_edge_tls,provider_rto_rpo'
cat "$work/timings.txt"
