#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
device_id=${1:-${E1_DEVICE_ID:-}}
package_id=dev.hyfens.conformance
fixture="$repo_root/fixtures/flutter_conformance_app"
experiment="$repo_root/experiments/patch_loading"
overlay="$fixture/.dart_tool/e1_overlay"
evidence="$experiment/.dart_tool/device-evidence"
serve_dir="$experiment/.dart_tool/serve"
port=18080

if [[ -z "$device_id" ]]; then
  echo "usage: $0 DEVICE_SERIAL (required to avoid an ambiguous device target)" >&2
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

mkdir -p "$evidence" "$serve_dir"
source_hash_before=$(shasum -a 256 "$fixture/lib/main.dart" | awk '{print $1}')

(cd "$experiment" && dart pub get)
(cd "$fixture" && flutter pub get)
(cd "$experiment" && dart run bin/e1.dart overlay \
  "$fixture/lib/main.dart" "$overlay")
(cd "$experiment" && dart run bin/e1.dart compile-patch \
  "$experiment/patches/price_patch.dart" "$overlay")
signing_seed="$serve_dir/phase0b-rfc8032-test-only.seed.hex"
signed_patch="$serve_dir/patch.e1.signed.json"
rm -f "$signing_seed" "$signed_patch"
# RFC 8032 test-vector seed. This is public test material, never a production
# signing key. Task 23 replaces it with a locally generated device-run key.
printf '%s\n' \
  '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60' \
  >"$signing_seed"
chmod 600 "$signing_seed"
(cd "$experiment" && dart run bin/e1.dart sign \
  "$overlay/patch.e0.json" "$signing_seed" \
  'phase0b-rfc8032-test-only' "$signed_patch")
cp "$experiment/patches/invalid.e0.json" "$serve_dir/invalid.e0.json"

source_hash_after=$(shasum -a 256 "$fixture/lib/main.dart" | awk '{print $1}')
if [[ "$source_hash_before" != "$source_hash_after" ]]; then
  echo "overlay generation modified checked-in main.dart" >&2
  exit 70
fi

if ps -axo command | grep -F "$fixture" | grep -E '(flutter|gradle|gen_snapshot)' | grep -v grep >/dev/null; then
  echo "another build process is using the E1 fixture; refusing to compete" >&2
  exit 75
fi

(cd "$fixture" && flutter build apk --release \
  --target=.dart_tool/e1_overlay/app.dart) | tee "$evidence/build.log"
apk="$fixture/build/app/outputs/flutter-apk/app-release.apk"
stat -f 'apkBytes=%z' "$apk" | tee "$evidence/sizes.txt"
stat -f 'signedPatchBytes=%z' "$signed_patch" | tee -a "$evidence/sizes.txt"

# This is the script's only install command. All subsequent transitions occur
# through localhost data delivery in the already-installed app.
adb -s "$device_id" install -r "$apk" | tee "$evidence/install.txt"
adb -s "$device_id" shell pm clear "$package_id" >/dev/null
adb -s "$device_id" reverse "tcp:$port" "tcp:$port"

(cd "$serve_dir" && python3 -m http.server "$port" --bind 127.0.0.1) \
  >"$evidence/http.log" 2>&1 &
server_pid=$!
cleanup() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  adb -s "$device_id" reverse --remove "tcp:$port" >/dev/null 2>&1 || true
}
trap cleanup EXIT

package_times() {
  adb -s "$device_id" shell dumpsys package "$package_id" |
    grep -E 'firstInstallTime|lastUpdateTime' | tr -d '\r'
}
package_times | tee "$evidence/package-times-before.txt"

adb -s "$device_id" shell am force-stop "$package_id"
adb -s "$device_id" shell am start -W -n "$package_id/.MainActivity" |
  tee "$evidence/startup.txt"

dump_ui() {
  adb -s "$device_id" shell uiautomator dump /sdcard/hyfens_e1_ui.xml >/dev/null
  adb -s "$device_id" exec-out cat /sdcard/hyfens_e1_ui.xml
}

wait_for_text() {
  local expected=$1
  local attempts=0
  while (( attempts < 30 )); do
    if dump_ui | grep -Fq "$expected"; then return 0; fi
    attempts=$((attempts + 1))
    sleep 1
  done
  echo "timed out waiting for UI text: $expected" >&2
  return 1
}

tap_text() {
  local label=$1
  local xml coords
  xml=$(dump_ui)
  coords=$(E1_XML="$xml" E1_LABEL="$label" python3 -c '
import os, re, sys, xml.etree.ElementTree as ET
root = ET.fromstring(os.environ["E1_XML"])
label = os.environ["E1_LABEL"]
for node in root.iter("node"):
    if node.attrib.get("text") == label or node.attrib.get("content-desc") == label:
        values = [int(v) for v in re.findall(r"\d+", node.attrib["bounds"])]
        print((values[0] + values[2]) // 2, (values[1] + values[3]) // 2)
        sys.exit(0)
sys.exit(1)')
  adb -s "$device_id" shell input tap $coords
}

wait_for_text 'BASE AOT'
wait_for_text 'price: 540'
dump_ui >"$evidence/ui-01-baseline.xml"

tap_text 'Increase quantity'
wait_for_text 'quantity: 7'
tap_text 'Download and activate local patch'
wait_for_text 'PATCH ACTIVE'
wait_for_text 'price: 525'
dump_ui >"$evidence/ui-02-patched-state-preserved.xml"

tap_text 'Attempt invalid patch'
wait_for_text 'status: rejected'
wait_for_text 'price: 525'
dump_ui >"$evidence/ui-03-invalid-retains-good.xml"

tap_text 'Manual rollback'
wait_for_text 'BASE AOT'
wait_for_text 'price: 630'
dump_ui >"$evidence/ui-04-rollback-base.xml"

pid=$(adb -s "$device_id" shell pidof -s "$package_id" | tr -d '\r')
adb -s "$device_id" logcat -d --pid="$pid" | grep -E 'E1_STATUS|E1_PATCH' \
  >"$evidence/app-status.log" || true
adb -s "$device_id" shell dumpsys meminfo "$package_id" \
  >"$evidence/meminfo.txt" || true
package_times | tee "$evidence/package-times-after.txt"
if ! diff -u "$evidence/package-times-before.txt" \
  "$evidence/package-times-after.txt" >"$evidence/package-times.diff"; then
  echo "package install/update timestamps changed after the one install" >&2
  exit 70
fi

echo "E1 physical proof complete: $evidence"
