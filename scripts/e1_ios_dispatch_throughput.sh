#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
fixture="$repo_root/fixtures/flutter_conformance_app"
experiment="$repo_root/experiments/patch_loading"
device_udid=${1:-${E1_IOS_DEVICE_UDID:-}}
xcode_device_id=${E1_XCODE_DEVICE_ID:-}
team_id=${E1_DEVELOPMENT_TEAM:-}
run_id=${E1_IOS_DISPATCH_THROUGHPUT_RUN_ID:-"ios-dispatch-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
run_root="$fixture/.dart_tool/e1_ios_dispatch_runs/$run_id"
overlay="$run_root/overlay"
serve_dir="$run_root/serve"
evidence="$run_root/evidence"
derived_data="$run_root/derived-data"
app_id=dev.hyfens.conformance
patch_sequence=${E1_IOS_DISPATCH_THROUGHPUT_PATCH_SEQUENCE:-1}
process_id=""

if [[ -z "$device_udid" || -z "$xcode_device_id" || -z "$team_id" ]]; then
  echo "usage: E1_XCODE_DEVICE_ID=CORE_DEVICE_ID E1_DEVELOPMENT_TEAM=TEAM_ID $0 PHYSICAL_UDID" >&2
  exit 64
fi
if ! [[ "$device_udid" =~ ^[A-Fa-f0-9-]{20,64}$ ]] ||
   ! [[ "$xcode_device_id" =~ ^[A-Fa-f0-9-]{20,64}$ ]] ||
   ! [[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] ||
   ! [[ "$run_id" =~ ^[A-Za-z0-9._-]{1,80}$ ]] ||
   ! [[ "$patch_sequence" =~ ^[1-9][0-9]*$ ]]; then
  echo "invalid device, team, run identifier, or patch sequence" >&2
  exit 64
fi
if ! command -v xcodebuildmcp >/dev/null ||
   ! command -v ios-deploy >/dev/null ||
   ! command -v flutter >/dev/null ||
   ! command -v dart >/dev/null; then
  echo "required Flutter, Dart, xcodebuildmcp, or ios-deploy command is missing" >&2
  exit 69
fi
if ! xcodebuildmcp --help >/dev/null || ! xcodebuildmcp tools >/dev/null; then
  echo "xcodebuildmcp help/tool discovery failed" >&2
  exit 69
fi
if ! flutter devices | grep -F "$device_udid" | grep -Fq ' ios '; then
  echo "physical iOS device is not visible: $device_udid" >&2
  exit 69
fi
if ! xcodebuildmcp device list --output json | grep -Fq "$xcode_device_id"; then
  echo "physical iOS device is not visible to xcodebuildmcp" >&2
  exit 69
fi
if ! ios-deploy --detect -W | grep -Fq "$device_udid"; then
  echo "physical USB device is not visible to ios-deploy: $device_udid" >&2
  exit 69
fi
if [[ -e "$run_root" ]]; then
  echo "evidence run already exists; choose a fresh E1_IOS_DISPATCH_THROUGHPUT_RUN_ID" >&2
  exit 73
fi
if ps -axo command | grep -F "$fixture" | grep -E '(xcodebuild|flutter_tools|gen_snapshot)' | grep -v grep >/dev/null; then
  echo "another build process is using the iOS fixture" >&2
  exit 75
fi

mkdir -p "$overlay" "$serve_dir" "$evidence"
record_exit_status() {
  local status=$?
  trap - EXIT
  if [[ "$status" -ne 0 && -n "$process_id" ]]; then
    xcodebuildmcp device stop --device-id "$xcode_device_id" \
      --process-id "$process_id" --output json \
      >"$evidence/stop-on-failure.json" 2>&1 || true
  fi
  printf 'harnessExitStatus=%s\n' "$status" >>"$evidence/preflight-and-command.txt"
  exit "$status"
}
trap record_exit_status EXIT
{
  printf 'runId=%s\n' "$run_id"
  printf 'deviceUdid=%s\n' "$device_udid"
  printf 'coreDeviceId=%s\n' "$xcode_device_id"
  printf 'developmentTeam=%s\n' "$team_id"
  printf 'transport=usb\n'
  printf 'bundleId=%s\n' "$app_id"
  printf 'workflow=xcodebuildmcp device build/install/launch/stop with ios-deploy USB transfer\n'
  printf 'harnessCommand=bash scripts/e1_ios_dispatch_throughput.sh %s\n' "$device_udid"
} >"$evidence/preflight-and-command.txt"
xcodebuildmcp --help >"$evidence/xcodebuildmcp-help.txt"
xcodebuildmcp tools >"$evidence/xcodebuildmcp-tools.txt"
flutter devices --machine >"$evidence/flutter-devices.json"
xcodebuildmcp device list --output json >"$evidence/xcodebuildmcp-device-list.json"
ios-deploy --detect -W >"$evidence/ios-deploy-detect-usb.txt"

source_sha256=$(shasum -a 256 "$fixture/lib/main.dart" | cut -d ' ' -f 1)
(cd "$experiment" && dart pub get) >"$evidence/patch-loading-pub-get.txt"
(cd "$fixture" && flutter pub get) >"$evidence/fixture-pub-get.txt"
(cd "$experiment" && dart run bin/e1_broad.dart overlay \
  "$fixture/lib/main.dart" "$overlay") | tee "$evidence/overlay.log"

compile_patch() {
  local source_file=$1
  local function_name=$2
  local output_file=$3
  (cd "$experiment" && dart run bin/e1.dart compile-patch \
    "$source_file" "$overlay" "$function_name" - "$patch_sequence")
  cp "$overlay/patch.e0.json" "$output_file"
}
compile_patch \
  "$experiment/patches/price_patch.dart" calculatePrice \
  "$serve_dir/business.e0.json" | tee "$evidence/patch-compile.log"
compile_patch \
  "$experiment/patches/async_price_patch.dart" calculateAsyncPrice \
  "$serve_dir/async.e0.json" | tee -a "$evidence/patch-compile.log"

seed_file="$serve_dir/phase0b-rfc8032-test-only.seed.hex"
printf '%s\n' \
  '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60' \
  >"$seed_file"
(cd "$experiment" && dart run bin/e1_patch_format_batch.dart \
  "$overlay/manifest.json" "$seed_file" \
  phase0b-rfc8032-test-only "$serve_dir/active-patch.v1.patch" \
  "$serve_dir/business.e0.json" "$serve_dir/async.e0.json") \
  | tee "$evidence/patch-format.log"
patch_sha256=$(shasum -a 256 "$serve_dir/active-patch.v1.patch" | cut -d ' ' -f 1)
source_sha256_after=$(shasum -a 256 "$fixture/lib/main.dart" | cut -d ' ' -f 1)
if [[ "$source_sha256" != "$source_sha256_after" ]]; then
  echo "overlay generation modified checked-in main.dart" >&2
  exit 70
fi
{
  printf 'sourceSha256=%s\n' "$source_sha256"
  printf 'patchSha256=%s\n' "$patch_sha256"
  printf 'patchSequence=%s\n' "$patch_sequence"
  stat -f 'patchBytes=%z' "$serve_dir/active-patch.v1.patch"
} >"$evidence/artifact-identity.txt"

encode_define() { printf '%s' "$1" | base64 | tr -d '\n'; }
dart_defines="$(encode_define 'E1_IOS_DISPATCH_THROUGHPUT=true'),$(encode_define "E1_IOS_DISPATCH_THROUGHPUT_RUN_ID=$run_id"),$(encode_define "E1_IOS_DISPATCH_THROUGHPUT_DEVICE_UDID=$device_udid"),$(encode_define "E1_IOS_DISPATCH_THROUGHPUT_CORE_DEVICE_ID=$xcode_device_id"),$(encode_define "E1_IOS_DISPATCH_THROUGHPUT_DEVELOPMENT_TEAM=$team_id"),$(encode_define 'E1_IOS_DISPATCH_THROUGHPUT_BUILD_CONFIGURATION=Release'),$(encode_define 'E1_IOS_DISPATCH_THROUGHPUT_BUILD_TARGET=device'),$(encode_define 'E1_IOS_DISPATCH_THROUGHPUT_TRANSPORT=usb'),$(encode_define "E1_IOS_DISPATCH_THROUGHPUT_SOURCE_SHA256=$source_sha256"),$(encode_define "E1_IOS_DISPATCH_THROUGHPUT_PATCH_SHA256=$patch_sha256"),$(encode_define "E1_IOS_DISPATCH_THROUGHPUT_PATCH_SEQUENCE=$patch_sequence")"

xcodebuildmcp device build \
  --workspace-path "$fixture/ios/Runner.xcworkspace" --scheme Runner \
  --configuration Release --derived-data-path "$derived_data" \
  --extra-args="DEVELOPMENT_TEAM=$team_id" \
  --extra-args=CODE_SIGN_STYLE=Automatic \
  --extra-args=-allowProvisioningUpdates \
  --extra-args=-allowProvisioningDeviceRegistration \
  --extra-args="FLUTTER_TARGET=$overlay/app.dart" \
  --extra-args="DART_DEFINES=$dart_defines" --output json \
  | tee "$evidence/build.json"

app_path=$(xcodebuildmcp device get-app-path \
  --workspace-path "$fixture/ios/Runner.xcworkspace" --scheme Runner \
  --configuration Release --derived-data-path "$derived_data" --output json | \
  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["artifacts"]["appPath"])')
bundle_id=$(xcodebuildmcp device get-app-bundle-id \
  --app-path "$app_path" --output json | \
  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["artifacts"]["bundleId"])')
if [[ "$bundle_id" != "$app_id" ]]; then
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

ios-deploy -W -i "$device_udid" -1 "$bundle_id" -9 \
  >"$evidence/uninstall.txt" 2>&1
date -u +installStartedAtUtc=%Y-%m-%dT%H:%M:%SZ >"$evidence/install.txt"
xcodebuildmcp device install --device-id "$xcode_device_id" \
  --app-path "$app_path" --output json | tee -a "$evidence/install.txt"
date -u +installFinishedAtUtc=%Y-%m-%dT%H:%M:%SZ >>"$evidence/install.txt"

ios_deploy_app() {
  command ios-deploy -W -i "$device_udid" -1 "$bundle_id" "$@"
}
usb_download_root="$evidence/usb-download"
mkdir -p "$usb_download_root"
remote_base="/Documents/hyfens-e1-ios-dispatch-throughput/$run_id"
remote_upload_base="Documents/hyfens-e1-ios-dispatch-throughput/$run_id"
download_remote() {
  local remote_file=$1
  perl -e 'alarm 20; exec @ARGV' -- \
    ios-deploy -W -i "$device_udid" -1 "$bundle_id" \
    -w "$remote_file" -2 "$usb_download_root" \
    >/dev/null 2>&1
}
sync_remote() {
  local remote_file=$1
  local local_file=$2
  download_remote "$remote_file" || true
  local downloaded="$usb_download_root$remote_file"
  if [[ -f "$downloaded" ]]; then
    cp "$downloaded" "$local_file"
    return 0
  fi
  return 1
}
wait_for_remote_file() {
  local remote_file=$1
  local local_file=$2
  local attempts=$3
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if sync_remote "$remote_file" "$local_file"; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for device file: $remote_file" >&2
  return 1
}

xcodebuildmcp device launch --device-id "$xcode_device_id" \
  --bundle-id "$bundle_id" --output json >"$evidence/launch.json"
python3 - "$evidence/launch.json" "$xcode_device_id" "$bundle_id" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["schema"] == "xcodebuildmcp.output.launch-result", payload
assert payload["data"]["summary"]["status"] == "SUCCEEDED", payload
assert payload["data"]["artifacts"]["deviceId"] == sys.argv[2], payload
assert payload["data"]["artifacts"]["bundleId"] == sys.argv[3], payload
process_id = payload["data"]["artifacts"].get("processId")
if not isinstance(process_id, int) or process_id <= 0:
    raise SystemExit("launch response did not contain a positive processId")
print(process_id)
PY
process_id=$(python3 - "$evidence/launch.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
print(payload["data"]["artifacts"]["processId"])
PY
)

ready_file="$evidence/ready.v1.json"
wait_for_remote_file "$remote_base/ready.v1.json" "$ready_file" 180
python3 - "$ready_file" "$run_id" <<'PY'
import json
import sys

marker = json.load(open(sys.argv[1], encoding="utf-8"))
assert marker == {
    "schemaVersion": 1,
    "benchmarkId": "ios-dispatch-throughput",
    "runId": sys.argv[2],
    "patchFileName": "active-patch.v1.patch",
    "reportFileName": "report.v1.json",
}, marker
PY
ios_deploy_app -o "$serve_dir/active-patch.v1.patch" \
  -2 "$remote_upload_base/active-patch.v1.patch" \
  >"$evidence/patch-upload.txt"
ios_deploy_app -l "$remote_base" >"$evidence/remote-directory-list.txt"

report_file="$evidence/report.v1.json"
wait_for_remote_file "$remote_base/report.v1.json" "$report_file" 900
xcodebuildmcp device stop --device-id "$xcode_device_id" \
  --process-id "$process_id" --output json >"$evidence/stop.json"
process_id=""

python3 - "$report_file" "$run_id" "$device_udid" "$xcode_device_id" "$team_id" <<'PY'
import json
import sys

report = json.load(open(sys.argv[1], encoding="utf-8"))
assert report["status"] == "MEASURED", report
identity = report["identity"]
assert identity["runId"] == sys.argv[2], identity
assert identity["deviceUdid"] == sys.argv[3], identity
assert identity["coreDeviceId"] == sys.argv[4], identity
assert identity["developmentTeam"] == sys.argv[5], identity
assert identity["buildConfiguration"] == "Release", identity
assert identity["buildTarget"] == "device", identity
assert identity["transport"] == "usb", identity
assert report["protocol"] == {
    "callCount": 10000000,
    "warmups": 2,
    "timedSamples": 15,
    "timer": "Stopwatch.monotonic",
    "timerBoundary": "repeated dispatch loop only",
    "timerFrequency": report["protocol"]["timerFrequency"],
    "durationUnit": "nanoseconds",
    "percentile": "nearest-rank p95; rank=ceil(0.95*n), one-indexed",
    "checksum": "sum of every returned int modulo 2^31",
}, report["protocol"]
variants = report["variants"]
assert [item["id"] for item in variants] == [
    "stock_direct_callable", "instrumented_unpatched", "active_patch",
], variants
assert all(item["status"] == "MEASURED" for item in variants), variants
assert [item["expectedResult"] for item in variants] == [540, 540, 450], variants
assert all(len(item["warmups"]["checksums"]) == 2 for item in variants), variants
assert all(len(item["samples"]) == 15 for item in variants), variants
assert all(item["statistics"]["count"] == 15 for item in variants), variants
PY

dart run "$repo_root/benchmarks/ios_dispatch_throughput_reducer.dart" \
  --input="$report_file" --output="$evidence/reduced.v1.json" \
  >"$evidence/reducer.txt"
printf 'E1 iOS dispatch-throughput proof complete: %s\n' "$evidence"
