#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
fixture="$repo_root/fixtures/flutter_conformance_app"
experiment="$repo_root/experiments/patch_loading"
device_udid=${1:-${E1_IOS_DEVICE_UDID:-}}
xcode_device_id=${E1_XCODE_DEVICE_ID:-}
team_id=${E1_DEVELOPMENT_TEAM:-}
transport=${E1_IOS_TRANSPORT:-lan}
host_ipv4=${E1_IOS_EVIDENCE_HOST:-}
port=${E1_IOS_EVIDENCE_PORT:-18080}
run_id=${E1_IOS_EVIDENCE_RUN_ID:-"ios-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
run_root="$fixture/.dart_tool/e1_ios_runs/$run_id"
overlay="$run_root/overlay"
serve_dir="$run_root/serve"
evidence="$run_root/evidence"
derived_data="$fixture/build/ios_e1_physical_derived"

if [[ -z "$device_udid" || -z "$xcode_device_id" || -z "$team_id" ]]; then
  echo "usage: E1_XCODE_DEVICE_ID=CORE_DEVICE_ID E1_DEVELOPMENT_TEAM=TEAM_ID [E1_IOS_TRANSPORT=lan|usb] $0 PHYSICAL_UDID" >&2
  exit 64
fi
if ! [[ "$device_udid" =~ ^[A-Fa-f0-9-]{20,64}$ ]] ||
   ! [[ "$xcode_device_id" =~ ^[A-Fa-f0-9-]{20,64}$ ]] ||
   ! [[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] ||
   ! [[ "$run_id" =~ ^[A-Za-z0-9._-]{1,80}$ ]]; then
  echo "invalid device, team, or run identifier" >&2
  exit 64
fi
if [[ "$transport" != lan && "$transport" != usb ]]; then
  echo "E1_IOS_TRANSPORT must be lan or usb" >&2
  exit 64
fi
if ! [[ "$port" =~ ^[0-9]{1,5}$ ]] || ((port < 1 || port > 65535)); then
  echo "invalid evidence server port" >&2
  exit 64
fi
if ! flutter devices | grep -F "$device_udid" | grep -Fq ' ios '; then
  echo "physical iOS device is not visible: $device_udid" >&2
  exit 69
fi
if ! xcodebuildmcp device list --output json | grep -Fq "$xcode_device_id"; then
  echo "physical iOS device is not visible to xcodebuildmcp" >&2
  exit 69
fi
if ps -axo command | grep -F "$fixture" | \
    grep -E '(xcodebuild|flutter_tools|gen_snapshot)' | grep -v grep >/dev/null; then
  echo "another build process is using the iOS fixture" >&2
  exit 75
fi

if [[ "$transport" == lan ]]; then
  if [[ -z "$host_ipv4" ]]; then
    default_interface=$(route -n get default | awk '/interface:/{print $2; exit}')
    host_ipv4=$(ipconfig getifaddr "$default_interface")
  fi
  if ! python3 -c '
import ipaddress, sys
address = ipaddress.ip_address(sys.argv[1])
networks = tuple(map(ipaddress.ip_network,
    ("10.0.0.0/8", "127.0.0.0/8", "169.254.0.0/16",
     "172.16.0.0/12", "192.168.0.0/16")))
assert address.version == 4 and any(address in network for network in networks)
  ' "$host_ipv4" 2>/dev/null; then
    echo "evidence host must be a local/private IPv4 address" >&2
    exit 64
  fi
fi
if [[ -e "$run_root" ]]; then
  echo "evidence run already exists; choose a fresh E1_IOS_EVIDENCE_RUN_ID" >&2
  exit 73
fi
server_url="http://$host_ipv4:$port"
evidence_token=$(python3 -c 'import secrets; print(secrets.token_hex(32))')
umask 077
mkdir -p "$overlay" "$serve_dir" "$evidence"
source_hash_before=$(shasum -a 256 "$fixture/lib/main.dart" | awk '{print $1}')
(cd "$experiment" && dart pub get)
(cd "$fixture" && flutter pub get)
(cd "$experiment" && dart run bin/e1.dart overlay \
  "$fixture/lib/main.dart" "$overlay")
(cd "$experiment" && dart run bin/e1.dart compile-patch \
  "$experiment/patches/price_patch.dart" "$overlay")

seed_file="$serve_dir/phase0b-rfc8032-test-only.seed.hex"
signed_patch="$serve_dir/patch.e1.signed.json"
printf '%s\n' \
  '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60' \
  >"$seed_file"
(cd "$experiment" && dart run bin/e1.dart sign \
  "$overlay/patch.e0.json" "$seed_file" \
  phase0b-rfc8032-test-only "$signed_patch")
python3 - "$signed_patch" "$serve_dir/invalid-signature.e1.signed.json" <<'PY'
import base64
import json
import pathlib
import sys

source, target = map(pathlib.Path, sys.argv[1:])
envelope = json.loads(source.read_text(encoding="utf-8"))
signature = bytearray(base64.b64decode(envelope["signature"], validate=True))
signature[0] ^= 1
envelope["signature"] = base64.b64encode(signature).decode("ascii")
target.write_text(
    json.dumps(envelope, sort_keys=True, separators=(",", ":")),
    encoding="utf-8",
)
PY
source_hash_after=$(shasum -a 256 "$fixture/lib/main.dart" | awk '{print $1}')
if [[ "$source_hash_before" != "$source_hash_after" ]]; then
  echo "overlay generation modified checked-in main.dart" >&2
  exit 70
fi

server_pid=""
if [[ "$transport" == lan ]]; then
  python3 "$repo_root/scripts/e1_ios_evidence_server.py" \
    --bind 0.0.0.0 --port "$port" --serve-dir "$serve_dir" \
    --receipts "$evidence/receipts.jsonl" --run-id "$run_id" \
    --token "$evidence_token" \
    >"$evidence/server.log" 2>&1 &
  server_pid=$!
fi
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
if [[ "$transport" == lan ]]; then
  for _ in {1..20}; do
    if curl --fail --silent "$server_url/$evidence_token/health" >/dev/null; then break; fi
    sleep 1
  done
  curl --fail --silent "$server_url/$evidence_token/health" >/dev/null
fi

encode_define() { printf '%s' "$1" | base64 | tr -d '\n'; }
if [[ "$transport" == usb ]]; then
  dart_defines="$(encode_define 'E1_IOS_EVIDENCE=true'),$(encode_define 'E1_IOS_USB_EVIDENCE=true'),$(encode_define "E1_IOS_EVIDENCE_RUN_ID=$run_id")"
else
  dart_defines="$(encode_define 'E1_IOS_EVIDENCE=true'),$(encode_define "E1_IOS_EVIDENCE_RUN_ID=$run_id"),$(encode_define "E1_IOS_EVIDENCE_SERVER=$server_url"),$(encode_define "E1_IOS_EVIDENCE_TOKEN=$evidence_token")"
fi
xcodebuildmcp device show-build-settings \
  --workspace-path "$fixture/ios/Runner.xcworkspace" --scheme Runner \
  --output json >"$evidence/build-settings.json"
xcodebuildmcp device build \
  --workspace-path "$fixture/ios/Runner.xcworkspace" --scheme Runner \
  --configuration Release --derived-data-path "$derived_data" \
  --extra-args="DEVELOPMENT_TEAM=$team_id" \
  --extra-args=CODE_SIGN_STYLE=Automatic \
  --extra-args=-allowProvisioningUpdates \
  --extra-args=-allowProvisioningDeviceRegistration \
  --extra-args="FLUTTER_TARGET=$overlay/app.dart" \
  --extra-args="DART_DEFINES=$dart_defines" --output json | \
  tee "$evidence/build.json"

app_path=$(xcodebuildmcp device get-app-path \
  --workspace-path "$fixture/ios/Runner.xcworkspace" --scheme Runner \
  --configuration Release --derived-data-path "$derived_data" --output json | \
  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["artifacts"]["appPath"])')
bundle_id=$(xcodebuildmcp device get-app-bundle-id \
  --app-path "$app_path" --output json | \
  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["artifacts"]["bundleId"])')
if [[ "$bundle_id" != dev.hyfens.conformance ]]; then
  echo "unexpected bundle ID: $bundle_id" >&2
  exit 70
fi
file "$app_path/Runner" "$app_path/Frameworks/App.framework/App" \
  >"$evidence/architectures.txt"
find "$app_path" -type f \( -name kernel_blob.bin -o -name '*.dill' \) \
  >"$evidence/jit-artifacts.txt"
codesign -d --entitlements :- "$app_path" \
  >"$evidence/entitlements.plist" 2>"$evidence/codesign-summary.txt"
shasum -a 256 "$app_path/Runner" "$app_path/Frameworks/App.framework/App" \
  >"$evidence/binary-sha256.txt"
date -u +installStartedAtUtc=%Y-%m-%dT%H:%M:%SZ >"$evidence/install.txt"
# This is deliberately the only install invocation in the script.
xcodebuildmcp device install --device-id "$xcode_device_id" \
  --app-path "$app_path" --output json | tee -a "$evidence/install.txt"
date -u +installFinishedAtUtc=%Y-%m-%dT%H:%M:%SZ >>"$evidence/install.txt"

if [[ "$transport" == usb ]]; then
  ios_deploy() {
    command ios-deploy -i "$device_udid" -1 "$bundle_id" "$@"
  }
  ios_deploy -D /Documents/hyfens-e1 >/dev/null
  usb_download_root="$evidence/usb-download"
  mkdir -p "$usb_download_root"
  stage_usb_patches() {
    ios_deploy -o "$signed_patch" \
      -2 /Documents/hyfens-e1/patch.e1.signed.json >/dev/null
    ios_deploy -o "$serve_dir/invalid-signature.e1.signed.json" \
      -2 /Documents/hyfens-e1/invalid-signature.e1.signed.json >/dev/null
  }
  sync_receipts() {
    ios_deploy -w /Documents/hyfens-e1/receipts.jsonl \
      -2 "$usb_download_root" >/dev/null 2>&1 || return 0
    local downloaded="$usb_download_root/Documents/hyfens-e1/receipts.jsonl"
    if [[ -f "$downloaded" ]]; then
      cp "$downloaded" "$evidence/receipts.jsonl"
    fi
  }
else
  sync_receipts() { :; }
fi

wait_for_stage() {
  local stage=$1
  for _ in {1..60}; do
    sync_receipts
    if [[ -f "$evidence/receipts.jsonl" ]] &&
       grep -Fq "\"stage\":\"$stage\"" "$evidence/receipts.jsonl"; then
      return 0
    fi
    if [[ -f "$evidence/receipts.jsonl" ]] &&
       grep -Fq '"stage":"failure"' "$evidence/receipts.jsonl"; then
      echo "device evidence runner reported failure" >&2
      return 1
    fi
    sleep 1
  done
  echo "timed out waiting for evidence stage: $stage" >&2
  return 1
}

stop_stage_process() {
  local stage=$1 process_id
  process_id=$(python3 -c '
import json, sys
rows = [json.loads(line) for line in open(sys.argv[2], encoding="utf-8")]
print([row for row in rows if row.get("stage") == sys.argv[1]][-1]["processId"])
' "$stage" "$evidence/receipts.jsonl")
  xcodebuildmcp device stop --device-id "$xcode_device_id" \
    --process-id "$process_id" --output json >>"$evidence/restarts.jsonl"
}

xcodebuildmcp device launch --device-id "$xcode_device_id" \
  --bundle-id "$bundle_id" --output json >>"$evidence/launches.jsonl"
wait_for_stage base
if [[ "$transport" == usb ]]; then
  stage_usb_patches
fi
wait_for_stage restart-required-1
stop_stage_process restart-required-1

xcodebuildmcp device launch --device-id "$xcode_device_id" \
  --bundle-id "$bundle_id" --output json >>"$evidence/launches.jsonl"
wait_for_stage stale-rejected
wait_for_stage restart-required-2
stop_stage_process restart-required-2

xcodebuildmcp device launch --device-id "$xcode_device_id" \
  --bundle-id "$bundle_id" --output json >>"$evidence/launches.jsonl"
wait_for_stage complete

python3 -c '
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
stages = [row["stage"] for row in rows]
assert stages == ["base", "patch-active", "restart-required-1",
 "patch-persisted", "invalid-rejected", "rolled-back", "stale-rejected",
 "restart-required-2", "rollback-persisted", "complete"], stages
expected = {"base": ("base", 540), "patch-active": ("patch", 450),
 "patch-persisted": ("patch", 450), "invalid-rejected": ("patch", 450),
 "rolled-back": ("base", 540), "stale-rejected": ("base", 540),
 "rollback-persisted": ("base", 540)}
by_stage = {row["stage"]: row for row in rows}
assert all(row["runId"] == sys.argv[2] for row in rows)
assert all(row["appId"] == "dev.hyfens.conformance" for row in rows)
for stage, (mode, price) in expected.items():
    row = by_stage[stage]
    assert row["succeeded"] and row["status"]["mode"] == mode
    assert row["price"] == price
process_groups = [
    ("base", "patch-active", "restart-required-1"),
    ("patch-persisted", "invalid-rejected", "rolled-back", "stale-rejected", "restart-required-2"),
    ("rollback-persisted", "complete"),
]
pids = []
for group in process_groups:
    group_pids = {by_stage[name]["processId"] for name in group}
    assert len(group_pids) == 1, (group, group_pids)
    pids.extend(group_pids)
assert len(set(pids)) == 3, pids
' "$evidence/receipts.jsonl" "$run_id"
echo "E1 physical iOS proof complete: $evidence"
