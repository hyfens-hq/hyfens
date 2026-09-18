#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
fixture="$repo_root/fixtures/flutter_conformance_app"
experiment="$repo_root/experiments/patch_loading"
device_udid=${1:-${E1_IOS_DEVICE_UDID:-}}
xcode_device_id=${E1_XCODE_DEVICE_ID:-}
team_id=${E1_DEVELOPMENT_TEAM:-}
run_id=${E1_IOS_CROSS_RUN_ID:-"ios-cross-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
run_root="$fixture/.dart_tool/e1_ios_cross_runs/$run_id"
overlay="$run_root/overlay"
serve_dir="$run_root/serve"
evidence="$run_root/evidence"
derived_data="$fixture/build/ios_e1_cross_derived"

if [[ -z "$device_udid" || -z "$xcode_device_id" || -z "$team_id" ]]; then
  echo "usage: E1_XCODE_DEVICE_ID=CORE_DEVICE_ID E1_DEVELOPMENT_TEAM=TEAM_ID $0 PHYSICAL_UDID" >&2
  exit 64
fi
if ! [[ "$device_udid" =~ ^[A-Fa-f0-9-]{20,64}$ ]] ||
   ! [[ "$xcode_device_id" =~ ^[A-Fa-f0-9-]{20,64}$ ]] ||
   ! [[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] ||
   ! [[ "$run_id" =~ ^[A-Za-z0-9._-]{1,80}$ ]]; then
  echo "invalid device, team, or run identifier" >&2
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
if [[ -e "$run_root" ]]; then
  echo "evidence run already exists; choose a fresh E1_IOS_CROSS_RUN_ID" >&2
  exit 73
fi
if ps -axo command | grep -F "$fixture" | grep -E '(xcodebuild|flutter_tools|gen_snapshot)' | grep -v grep >/dev/null; then
  echo "another build process is using the iOS fixture" >&2
  exit 75
fi

mkdir -p "$overlay" "$serve_dir" "$evidence"
{
  printf 'runId=%s\n' "$run_id"
  printf 'deviceUdid=%s\n' "$device_udid"
  printf 'coreDeviceId=%s\n' "$xcode_device_id"
  printf 'developmentTeam=%s\n' "$team_id"
  printf 'transport=usb\n'
  printf 'bundleId=dev.hyfens.conformance\n'
  printf 'workflow=xcodebuildmcp device build/install/launch/stop\n'
  printf 'harnessCommand=bash scripts/e1_ios_cross_feature.sh %s\n' "$device_udid"
} >"$evidence/preflight-and-command.txt"
record_exit_status() {
  local status=$?
  trap - EXIT
  printf 'harnessExitStatus=%s\n' "$status" >>"$evidence/preflight-and-command.txt"
  exit "$status"
}
trap record_exit_status EXIT
flutter devices --machine >"$evidence/flutter-devices.json"
xcodebuildmcp device list --output json >"$evidence/xcodebuildmcp-device-list.json"
ios-deploy --detect -W >"$evidence/ios-deploy-detect-usb.txt"
source_hash_before=$(shasum -a 256 "$fixture/lib/main.dart" | cut -d ' ' -f 1)
(cd "$experiment" && dart pub get)
(cd "$fixture" && flutter pub get)
(cd "$experiment" && dart run bin/e1_broad.dart overlay \
  "$fixture/lib/main.dart" "$overlay") | tee "$evidence/overlay.log"

compile_patch() {
  local source=$1 function=$2 class_name=$3 sequence=$4 output=$5
  if [[ -n "$class_name" ]]; then
    (cd "$experiment" && dart run bin/e1.dart compile-patch \
      "$source" "$overlay" "$function" "$class_name" "$sequence")
  else
    (cd "$experiment" && dart run bin/e1.dart compile-patch \
      "$source" "$overlay" "$function" - "$sequence")
  fi
  cp "$overlay/patch.e0.json" "$output"
}
compile_patch "$experiment/patches/price_patch.dart" calculatePrice '' 1 \
  "$serve_dir/business.e0.json"
compile_patch "$experiment/patches/async_price_patch.dart" calculateAsyncPrice '' 1 \
  "$serve_dir/async.e0.json"
compile_patch "$experiment/patches/pricing_card_patch.dart" build PricingCard 1 \
  "$serve_dir/ui.e0.json"

seed_file="$serve_dir/phase0b-rfc8032-test-only.seed.hex"
printf '%s\n' \
  '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60' \
  >"$seed_file"
(cd "$experiment" && dart run bin/e1_patch_format_batch.dart \
  "$overlay/manifest.json" "$seed_file" \
  phase0b-rfc8032-test-only "$serve_dir/multi-1.v1.patch" \
  "$serve_dir/business.e0.json" \
  "$serve_dir/async.e0.json" \
  "$serve_dir/ui.e0.json") | tee "$evidence/patch-build.log"
python3 - "$serve_dir/multi-1.v1.patch" \
  "$serve_dir/multi-invalid.v1.patch" <<'PY'
import pathlib
import sys

source, target = map(pathlib.Path, sys.argv[1:])
artifact = bytearray(source.read_bytes())
if artifact[:8] != b"HYFENSP1":
    raise SystemExit("unexpected Patch Format v1 magic")
section_count = int.from_bytes(artifact[16:18], "big")
offset = 18
for _ in range(section_count):
    if offset + 8 > len(artifact):
        raise SystemExit("truncated Patch Format v1 section header")
    section_type = int.from_bytes(artifact[offset:offset + 2], "big")
    section_length = int.from_bytes(artifact[offset + 4:offset + 8], "big")
    payload_start = offset + 8
    payload_end = payload_start + section_length
    if payload_end > len(artifact):
        raise SystemExit("truncated Patch Format v1 section payload")
    if section_type == 8:
        if section_length < 3:
            raise SystemExit("missing Patch Format v1 signature")
        signature_length = int.from_bytes(
            artifact[payload_start:payload_start + 2], "big"
        )
        if signature_length == 0 or signature_length + 2 != section_length:
            raise SystemExit("invalid Patch Format v1 signature section")
        artifact[payload_start + 2] ^= 1
        break
    offset = payload_end
else:
    raise SystemExit("Patch Format v1 signature section not found")
target.write_bytes(artifact)
PY
stat -f 'multi-1.v1.patch bytes=%z' "$serve_dir/multi-1.v1.patch" \
  | tee "$evidence/artifact-sizes.txt"
stat -f 'multi-invalid.v1.patch bytes=%z' "$serve_dir/multi-invalid.v1.patch" \
  | tee -a "$evidence/artifact-sizes.txt"
shasum -a 256 "$serve_dir/multi-1.v1.patch" \
  "$serve_dir/multi-invalid.v1.patch" | tee "$evidence/artifact-sha256.txt"
source_hash_after=$(shasum -a 256 "$fixture/lib/main.dart" | cut -d ' ' -f 1)
if [[ "$source_hash_before" != "$source_hash_after" ]]; then
  echo "overlay generation modified checked-in main.dart" >&2
  exit 70
fi

encode_define() { printf '%s' "$1" | base64 | tr -d '\n'; }
dart_defines="$(encode_define 'E1_IOS_EVIDENCE=true'),$(encode_define 'E1_IOS_USB_EVIDENCE=true'),$(encode_define 'E1_IOS_MULTI_FUNCTION=true'),$(encode_define "E1_IOS_EVIDENCE_RUN_ID=$run_id")"
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
xcodebuildmcp device install --device-id "$xcode_device_id" \
  --app-path "$app_path" --output json | tee -a "$evidence/install.txt"
date -u +installFinishedAtUtc=%Y-%m-%dT%H:%M:%SZ >>"$evidence/install.txt"

ios_deploy() {
  command ios-deploy -W -i "$device_udid" -1 "$bundle_id" "$@"
}
ios_deploy -D /Documents/hyfens-e1 >/dev/null
ios_deploy -R /Documents/hyfens-e1/receipts.jsonl >/dev/null 2>&1 || true
usb_download_root="$evidence/usb-download"
mkdir -p "$usb_download_root"
stage_usb_patches() {
  ios_deploy -D /Documents/hyfens-e1 >/dev/null
  for name in multi-1.v1.patch multi-invalid.v1.patch; do
    ios_deploy -o "$serve_dir/$name" \
      -2 "Documents/hyfens-e1/$name" >/dev/null
  done
  ios_deploy -l /Documents/hyfens-e1 >"$evidence/usb-staging-list.txt"
}
sync_receipts() {
  perl -e 'alarm 20; exec @ARGV' -- \
    ios-deploy -W -i "$device_udid" -1 "$bundle_id" \
    -w /Documents/hyfens-e1/receipts.jsonl \
    -2 "$usb_download_root" >/dev/null 2>&1 || true
  local downloaded="$usb_download_root/Documents/hyfens-e1/receipts.jsonl"
  if [[ -f "$downloaded" ]]; then cp "$downloaded" "$evidence/receipts.jsonl"; fi
  return 0
}
wait_for_stage() {
  local expected=$1
  for _ in {1..90}; do
    if [[ -f "$evidence/receipts.jsonl" ]] &&
       grep -Fq "\"stage\":\"$expected\"" "$evidence/receipts.jsonl"; then
      return 0
    fi
    sync_receipts
    if [[ -f "$evidence/receipts.jsonl" ]] &&
       grep -Fq "\"stage\":\"$expected\"" "$evidence/receipts.jsonl"; then
      return 0
    fi
    if [[ -f "$evidence/receipts.jsonl" ]] &&
       grep -Fq '"stage":"failure"' "$evidence/receipts.jsonl"; then
      echo "device evidence runner reported failure" >&2
      return 1
    fi
    sleep 1
  done
  echo "timed out waiting for evidence stage: $expected" >&2
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
wait_for_stage multi-base
stage_usb_patches
wait_for_stage multi-function-patch
wait_for_stage restart-required-1
stop_stage_process restart-required-1

xcodebuildmcp device launch --device-id "$xcode_device_id" \
  --bundle-id "$bundle_id" --output json >>"$evidence/launches.jsonl"
wait_for_stage multi-persisted
wait_for_stage multi-invalid-rejected
wait_for_stage multi-rolled-back
wait_for_stage restart-required-2
stop_stage_process restart-required-2

xcodebuildmcp device launch --device-id "$xcode_device_id" \
  --bundle-id "$bundle_id" --output json >>"$evidence/launches.jsonl"
wait_for_stage multi-rollback-persisted
wait_for_stage complete
xcodebuildmcp device launch --device-id "$xcode_device_id" \
  --bundle-id "$bundle_id" --output json >>"$evidence/launches.jsonl"
wait_for_stage multi-complete

python3 - "$evidence/receipts.jsonl" "$run_id" \
  "$evidence/install.txt" "$evidence/architectures.txt" \
  "$evidence/build.json" "$evidence/usb-staging-list.txt" \
  "$xcode_device_id" <<'PY'
import json
import sys

rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
stages = [row["stage"] for row in rows]
expected = [
    "multi-base", "multi-function-patch", "restart-required-1",
    "multi-persisted", "multi-invalid-rejected", "multi-rolled-back",
    "restart-required-2", "multi-rollback-persisted", "complete",
    "multi-complete",
]
assert stages == expected, stages
assert all(row["runId"] == sys.argv[2] for row in rows)
assert all(row["appId"] == "dev.hyfens.conformance" for row in rows)
assert all(row["releaseId"] == "android-e1-release-1" for row in rows)
assert all(row["buildFingerprint"] == "conformance-build-1" for row in rows)
assert all(row["succeeded"] for row in rows)
by_stage = {row["stage"]: row for row in rows}
assert by_stage["multi-base"]["price"] == 540
assert by_stage["multi-base"]["asyncPrice"] == 540
assert by_stage["multi-base"]["uiPatched"] is False
assert by_stage["multi-base"]["status"]["mode"] == "base"
assert by_stage["multi-base"]["highWaterSequence"] == 0
for stage in ("multi-function-patch", "multi-persisted"):
    assert by_stage[stage]["price"] == 450
    assert by_stage[stage]["asyncPrice"] == 481
    assert by_stage[stage]["uiPatched"] is True
    assert by_stage[stage]["status"]["mode"] == "patch"
    assert by_stage[stage]["highWaterSequence"] == 1
assert by_stage["restart-required-1"]["price"] == 450
assert by_stage["restart-required-1"]["asyncPrice"] is None
assert by_stage["restart-required-1"]["status"]["mode"] == "patch"
assert by_stage["restart-required-1"]["highWaterSequence"] == 1
assert by_stage["multi-invalid-rejected"]["price"] == 450
assert by_stage["multi-invalid-rejected"]["asyncPrice"] == 481
assert by_stage["multi-invalid-rejected"]["uiPatched"] is True
assert by_stage["multi-invalid-rejected"]["status"]["phase"] == "rejected"
assert by_stage["multi-invalid-rejected"]["status"]["mode"] == "patch"
assert by_stage["multi-invalid-rejected"]["highWaterSequence"] == 1
for stage in (
    "multi-rolled-back", "multi-rollback-persisted", "complete",
):
    assert by_stage[stage]["price"] == 540
    assert by_stage[stage]["uiPatched"] is False
    assert by_stage[stage]["status"]["mode"] == "base"
    assert by_stage[stage]["highWaterSequence"] == 1
assert by_stage["multi-rolled-back"]["asyncPrice"] == 540
assert by_stage["multi-rollback-persisted"]["asyncPrice"] == 540
assert by_stage["complete"]["asyncPrice"] is None
assert by_stage["restart-required-2"]["price"] == 540
assert by_stage["restart-required-2"]["asyncPrice"] is None
assert by_stage["restart-required-2"]["status"]["mode"] == "base"
assert by_stage["restart-required-2"]["highWaterSequence"] == 1
assert by_stage["multi-rolled-back"]["status"]["phase"] == "rolledBack"
assert by_stage["multi-rollback-persisted"]["status"]["phase"] == "healthy"
assert by_stage["complete"]["status"]["phase"] == "healthy"
assert by_stage["multi-complete"]["price"] == 540
assert by_stage["multi-complete"]["asyncPrice"] == 540
assert by_stage["multi-complete"]["uiPatched"] is False
assert by_stage["multi-complete"]["status"]["mode"] == "base"
assert by_stage["multi-complete"]["status"]["phase"] == "healthy"
assert by_stage["multi-complete"]["highWaterSequence"] == 1
for group in (
    ("multi-base", "multi-function-patch", "restart-required-1"),
    ("multi-persisted", "multi-invalid-rejected", "multi-rolled-back", "restart-required-2"),
    ("multi-rollback-persisted", "complete"),
    ("multi-complete",),
):
    assert len({by_stage[name]["processId"] for name in group}) == 1, group
assert len({row["processId"] for row in rows}) == 4
install_text = open(sys.argv[3], encoding="utf-8").read()
assert install_text.count('"schema": "xcodebuildmcp.output.install-result"') == 1
assert install_text.count('"status": "SUCCEEDED"') == 1
assert sys.argv[7] in install_text
architecture_text = open(sys.argv[4], encoding="utf-8").read()
assert architecture_text.count("arm64") >= 2, architecture_text
build_text = open(sys.argv[5], encoding="utf-8").read()
assert '"status": "SUCCEEDED"' in build_text
assert '"configuration": "Release"' in build_text
assert '"target": "device"' in build_text
staging_text = open(sys.argv[6], encoding="utf-8").read()
assert "multi-1.v1.patch" in staging_text, staging_text
assert "multi-invalid.v1.patch" in staging_text, staging_text
PY
echo "E1 physical iOS cross-feature proof complete: $evidence"
