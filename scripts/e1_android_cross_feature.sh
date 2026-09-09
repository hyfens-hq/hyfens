#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
fixture="$repo_root/fixtures/flutter_conformance_app"
experiment="$repo_root/experiments/patch_loading"
device_id=${1:-${E1_DEVICE_ID:-}}
package_id=dev.hyfens.conformance
run_id=${E1_ANDROID_EVIDENCE_RUN_ID:-"android-cross-$(date -u +%Y%m%dT%H%M%SZ)-$$"}
run_root="$experiment/.dart_tool/android_e1_runs/$run_id"
overlay="$run_root/overlay"
serve_dir="$run_root/serve"
evidence="$run_root/evidence"
port=${E1_ANDROID_EVIDENCE_PORT:-18080}

if [[ -z "$device_id" ]]; then
  echo "usage: $0 DEVICE_SERIAL (required to avoid an ambiguous device target)" >&2
  exit 64
fi
if ! [[ "$run_id" =~ ^[A-Za-z0-9._-]{1,80}$ ]]; then
  echo "invalid evidence run identifier" >&2
  exit 64
fi
if ! [[ "$port" =~ ^[0-9]{1,5}$ ]] || ((port < 1 || port > 65535)); then
  echo "invalid evidence server port" >&2
  exit 64
fi
if ! adb devices | awk 'NR > 1 && $2 == "device" {print $1}' | grep -Fxq "$device_id"; then
  echo "device is not connected: $device_id" >&2
  exit 69
fi
if [[ "$(adb -s "$device_id" shell getprop ro.kernel.qemu | tr -d '\r')" == "1" ]]; then
  echo "E1 requires a physical Android device" >&2
  exit 69
fi
if [[ -e "$run_root" ]]; then
  echo "evidence run already exists; choose a fresh E1_ANDROID_EVIDENCE_RUN_ID" >&2
  exit 73
fi
if ps -axo command | grep -F "$fixture" | grep -E '(flutter|gradle|gen_snapshot)' | grep -v grep >/dev/null; then
  echo "another build process is using the E1 fixture; refusing to compete" >&2
  exit 75
fi

mkdir -p "$overlay" "$serve_dir" "$evidence"
source_hash_before=$(shasum -a 256 "$fixture/lib/main.dart" | awk '{print $1}')
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
  "$serve_dir/business-1.e0.json"
compile_patch "$experiment/patches/async_price_patch.dart" calculateAsyncPrice '' 2 \
  "$serve_dir/async-2.e0.json"
compile_patch "$experiment/patches/pricing_card_patch.dart" build PricingCard 3 \
  "$serve_dir/ui-3.e0.json"
compile_patch "$experiment/patches/price_patch.dart" calculatePrice '' 4 \
  "$serve_dir/business-4.e0.json"

seed_file="$serve_dir/phase0b-rfc8032-test-only.seed.hex"
printf '%s\n' \
  '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60' \
  >"$seed_file"
for name in business-1 async-2 ui-3 business-4; do
  (cd "$experiment" && dart run bin/e1.dart sign \
    "$serve_dir/$name.e0.json" "$seed_file" \
    phase0b-rfc8032-test-only "$serve_dir/$name.e1.signed.json")
done
cp "$serve_dir/business-1.e1.signed.json" "$serve_dir/patch.e1.signed.json"
python3 - "$serve_dir/business-4.e1.signed.json" \
  "$serve_dir/invalid-signature.e1.signed.json" <<'PY'
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

evidence_token=$(python3 -c 'import secrets; print(secrets.token_hex(32))')
python3 "$repo_root/scripts/e1_ios_evidence_server.py" \
  --bind 127.0.0.1 --port "$port" --serve-dir "$serve_dir" \
  --receipts "$evidence/receipts.jsonl" --run-id "$run_id" \
  --token "$evidence_token" \
  >"$evidence/server.log" 2>&1 &
server_pid=$!
cleanup() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  adb -s "$device_id" reverse --remove "tcp:$port" >/dev/null 2>&1 || true
}
trap cleanup EXIT
for _ in {1..20}; do
  if curl --fail --silent "http://127.0.0.1:$port/$evidence_token/health" >/dev/null; then break; fi
  sleep 1
done
curl --fail --silent "http://127.0.0.1:$port/$evidence_token/health" >/dev/null

(cd "$fixture" && flutter build apk --release \
  --target="$overlay/app.dart" \
  --dart-define=E1_ANDROID_EVIDENCE=true \
  --dart-define="E1_ANDROID_EVIDENCE_RUN_ID=$run_id" \
  --dart-define="E1_ANDROID_EVIDENCE_SERVER=http://127.0.0.1:$port" \
  --dart-define="E1_ANDROID_EVIDENCE_TOKEN=$evidence_token") | tee "$evidence/build.log"
apk="$fixture/build/app/outputs/flutter-apk/app-release.apk"
stat -f 'apkBytes=%z' "$apk" | tee "$evidence/sizes.txt"
for name in business-1 async-2 ui-3 business-4 invalid-signature; do
  stat -f "$name.e1.signed.json bytes=%z" "$serve_dir/$name.e1.signed.json" | tee -a "$evidence/sizes.txt"
done

# This is deliberately the only install invocation in the broad sequence.
adb -s "$device_id" install -r "$apk" | tee "$evidence/install.txt"
adb -s "$device_id" shell pm clear "$package_id" >/dev/null
adb -s "$device_id" reverse "tcp:$port" "tcp:$port"

package_times() {
  adb -s "$device_id" shell dumpsys package "$package_id" |
    grep -E 'firstInstallTime|lastUpdateTime' | tr -d '\r'
}
package_times | tee "$evidence/package-times-before.txt"

adb -s "$device_id" shell am force-stop "$package_id"
adb -s "$device_id" shell am start -W -n "$package_id/.MainActivity" |
  tee "$evidence/startup.txt"

wait_for_stage() {
  local expected=$1
  for _ in {1..60}; do
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

wait_for_stage base
wait_for_stage business-patch
wait_for_stage async-patch
wait_for_stage ui-patch
wait_for_stage riverpod-patch
wait_for_stage restart-required-1

adb -s "$device_id" shell am force-stop "$package_id"
adb -s "$device_id" shell am start -W -n "$package_id/.MainActivity" >/dev/null
wait_for_stage riverpod-persisted
wait_for_stage invalid-rejected
wait_for_stage rolled-back
wait_for_stage stale-rejected
wait_for_stage restart-required-2

adb -s "$device_id" shell am force-stop "$package_id"
adb -s "$device_id" shell am start -W -n "$package_id/.MainActivity" >/dev/null
wait_for_stage rollback-persisted
wait_for_stage complete

package_times | tee "$evidence/package-times-after.txt"
if ! diff -u "$evidence/package-times-before.txt" \
  "$evidence/package-times-after.txt" >"$evidence/package-times.diff"; then
  echo "package install/update timestamps changed after the one install" >&2
  exit 70
fi

python3 - "$evidence/receipts.jsonl" "$run_id" <<'PY'
import json
import sys

rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
stages = [row["stage"] for row in rows]
expected_stages = [
    "base", "business-patch", "async-patch", "ui-patch", "riverpod-patch",
    "restart-required-1", "riverpod-persisted", "invalid-rejected",
    "rolled-back", "stale-rejected", "restart-required-2",
    "rollback-persisted", "complete",
]
assert stages == expected_stages, stages
assert all(row["runId"] == sys.argv[2] for row in rows)
assert all(row["appId"] == "dev.hyfens.conformance" for row in rows)
by_stage = {row["stage"]: row for row in rows}
assert by_stage["base"]["price"] == 540 and by_stage["base"]["asyncPrice"] == 540
assert by_stage["business-patch"]["price"] == 450
assert by_stage["async-patch"]["asyncPrice"] == 481
assert by_stage["ui-patch"]["price"] == 540
assert by_stage["ui-patch"]["uiPatched"] is True
assert by_stage["riverpod-patch"]["price"] == 450
assert by_stage["invalid-rejected"]["succeeded"]
assert by_stage["invalid-rejected"]["status"]["phase"] == "rejected"
assert by_stage["rolled-back"]["status"]["mode"] == "base"
assert by_stage["stale-rejected"]["succeeded"]
assert by_stage["stale-rejected"]["status"]["phase"] == "rejected"
assert by_stage["stale-rejected"]["status"]["mode"] == "base"
assert by_stage["stale-rejected"]["highWaterSequence"] == 4
assert by_stage["complete"]["status"]["mode"] == "base"
for group in (
    ("base", "business-patch", "async-patch", "ui-patch", "riverpod-patch", "restart-required-1"),
    ("riverpod-persisted", "invalid-rejected", "rolled-back", "stale-rejected", "restart-required-2"),
    ("rollback-persisted", "complete"),
):
    assert len({by_stage[name]["processId"] for name in group}) == 1, group
assert len({row["processId"] for row in rows}) == 3
PY

echo "E1 physical Android cross-feature proof complete: $evidence"
