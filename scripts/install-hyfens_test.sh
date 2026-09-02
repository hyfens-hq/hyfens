#!/usr/bin/env bash
set -euo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALLER="$SCRIPT_DIR/install-hyfens.sh"
readonly ORIGINAL_PATH="$PATH"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hyfens-installer-test.XXXXXX")"
readonly TEMP_ROOT="$TEST_ROOT/tmp"
readonly MOCK_BIN="$TEST_ROOT/bin"
readonly FIXTURE_ROOT="$TEST_ROOT/fixtures"
readonly VERSION='9.8.7'

trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEMP_ROOT" "$MOCK_BIN" "$FIXTURE_ROOT"

case "$(uname -s)" in
  Darwin) platform='macos' ;;
  Linux) platform='linux' ;;
  *)
    printf 'unsupported test operating system\n' >&2
    exit 1
    ;;
esac
case "$(uname -m)" in
  x86_64|amd64) architecture='x64' ;;
  arm64|aarch64) architecture='arm64' ;;
  *)
    printf 'unsupported test machine architecture\n' >&2
    exit 1
    ;;
esac

archive="hyfens-${VERSION}-${platform}-${architecture}.tar.gz"
archive_root="hyfens-${VERSION}-${platform}-${architecture}"
archive_path="$FIXTURE_ROOT/$archive"

mkdir -p "$FIXTURE_ROOT/$archive_root/bin"
printf '#!/bin/sh\nexit 0\n' > "$FIXTURE_ROOT/$archive_root/bin/hyfens"
printf '#!/bin/sh\nexit 0\n' > "$FIXTURE_ROOT/$archive_root/bin/tool"
chmod 755 "$FIXTURE_ROOT/$archive_root/bin/hyfens" \
  "$FIXTURE_ROOT/$archive_root/bin/tool"
tar -czf "$archive_path" -C "$FIXTURE_ROOT" "$archive_root"

if command -v shasum >/dev/null 2>&1; then
  archive_digest="$(shasum -a 256 "$archive_path" | awk '{ print $1 }')"
else
  archive_digest="$(sha256sum "$archive_path" | awk '{ print $1 }')"
fi
bad_digest='0000000000000000000000000000000000000000000000000000000000000000'

compact_metadata="$FIXTURE_ROOT/compact.json"
pretty_metadata="$FIXTURE_ROOT/pretty.json"
malformed_metadata="$FIXTURE_ROOT/malformed.json"
missing_tag_metadata="$FIXTURE_ROOT/missing-tag.json"
correct_checksums="$FIXTURE_ROOT/SHA256SUMS.correct"
bad_checksums="$FIXTURE_ROOT/SHA256SUMS.bad"

printf '%s\n' \
  '{"url":"https://api.github.com/repos/hyfens-hq/hyfens/releases/1","tag_name":"v9.8.7","assets":[]}' \
  > "$compact_metadata"
cat > "$pretty_metadata" <<'EOF'
{
  "url": "https://api.github.com/repos/hyfens-hq/hyfens/releases/1",
  "tag_name": "v9.8.7",
  "assets": []
}
EOF
printf '%s\n' '{"tag_name":"v9.8.7",' > "$malformed_metadata"
printf '%s\n' '{"name":"v9.8.7","assets":[]}' > "$missing_tag_metadata"
printf '%s\n' \
  "$archive_digest  ${archive}.bak" \
  "$archive_digest  $archive" \
  > "$correct_checksums"
printf '%s\n' "$bad_digest  $archive" > "$bad_checksums"

cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

readonly latest_url='https://api.github.com/repos/hyfens-hq/hyfens/releases/latest'
readonly release_base='https://github.com/hyfens-hq/hyfens/releases/download'

output=''
url="${!#}"
has_https_redirect=0
has_https_protocol=0
has_tls=0
while (($# > 0)); do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    --proto)
      [[ "${2:-}" == '=https' ]] && has_https_protocol=1
      shift 2
      ;;
    --proto-redir)
      [[ "${2:-}" == '=https' ]] && has_https_redirect=1
      shift 2
      ;;
    --tlsv1.2)
      has_tls=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done

printf '%s\n' "$url" >> "${HYFENS_TEST_CURL_LOG:?}"
[[ "$url" == https://* ]] || exit 97
[[ "$has_https_protocol" == 1 && "$has_https_redirect" == 1 && "$has_tls" == 1 ]] ||
  exit 98
[[ -n "$output" ]] || exit 99

expected_archive="hyfens-${HYFENS_TEST_VERSION}-${HYFENS_TEST_PLATFORM}-${HYFENS_TEST_ARCHITECTURE}.tar.gz"
case "$url" in
  "$latest_url")
    [[ "${HYFENS_TEST_REJECT_LATEST:-0}" != 1 ]] || exit 100
    cp "${HYFENS_TEST_METADATA:?}" "$output"
    ;;
  "$release_base/v${HYFENS_TEST_VERSION}/${expected_archive}")
    cp "${HYFENS_TEST_ARCHIVE:?}" "$output"
    ;;
  "$release_base/v${HYFENS_TEST_VERSION}/SHA256SUMS")
    cp "${HYFENS_TEST_CHECKSUMS:?}" "$output"
    ;;
  *)
    exit 101
    ;;
esac
EOF
chmod 755 "$MOCK_BIN/curl"

current_metadata=''
current_checksums=''
reject_latest=0
last_status=0
last_output=''
last_prefix=''

run_install() {
  local case_name="$1"
  shift
  last_output="$TEST_ROOT/$case_name.output"
  last_prefix="$TEST_ROOT/$case_name-prefix"
  local curl_log="$TEST_ROOT/$case_name-curl.log"
  mkdir -p "$last_prefix"
  : > "$curl_log"

  set +e
  env \
    PATH="$MOCK_BIN:$ORIGINAL_PATH" \
    TMPDIR="$TEMP_ROOT" \
    HYFENS_TEST_ARCHIVE="$archive_path" \
    HYFENS_TEST_CHECKSUMS="$current_checksums" \
    HYFENS_TEST_CURL_LOG="$curl_log" \
    HYFENS_TEST_METADATA="$current_metadata" \
    HYFENS_TEST_PLATFORM="$platform" \
    HYFENS_TEST_ARCHITECTURE="$architecture" \
    HYFENS_TEST_REJECT_LATEST="$reject_latest" \
    HYFENS_TEST_VERSION="$VERSION" \
    "$INSTALLER" --prefix "$last_prefix" "$@" > "$last_output" 2>&1
  last_status=$?
  set -e
}

show_failure() {
  printf 'case failed: %s\n' "$1" >&2
  sed -n '1,160p' "$last_output" >&2
  exit 1
}

expect_success() {
  local case_name="$1"
  shift
  run_install "$case_name" "$@"
  [[ "$last_status" == 0 ]] || show_failure "$case_name"
}

expect_failure() {
  local case_name="$1"
  local expected_message="$2"
  shift 2
  run_install "$case_name" "$@"
  [[ "$last_status" != 0 ]] || show_failure "$case_name unexpectedly succeeded"
  awk -v expected="$expected_message" 'index($0, expected) { found = 1 } END { exit !found }' \
    "$last_output" || show_failure "$case_name did not report $expected_message"
}

assert_curl_url() {
  local case_name="$1"
  local expected_url="$2"
  local curl_log="$TEST_ROOT/$case_name-curl.log"
  awk -v expected="$expected_url" '$0 == expected { found = 1 } END { exit !found }' \
    "$curl_log" || show_failure "$case_name did not request $expected_url"
}

assert_no_curl_url() {
  local case_name="$1"
  local unexpected_url="$2"
  local curl_log="$TEST_ROOT/$case_name-curl.log"
  if awk -v unexpected="$unexpected_url" '$0 == unexpected { found = 1 } END { exit !found }' \
    "$curl_log"; then
    show_failure "$case_name requested $unexpected_url"
  fi
}

current_checksums="$correct_checksums"
current_metadata="$compact_metadata"
expect_success compact-latest
assert_curl_url compact-latest "https://api.github.com/repos/hyfens-hq/hyfens/releases/latest"
assert_curl_url compact-latest "https://github.com/hyfens-hq/hyfens/releases/download/v${VERSION}/${archive}"
assert_curl_url compact-latest "https://github.com/hyfens-hq/hyfens/releases/download/v${VERSION}/SHA256SUMS"
[[ -L "$last_prefix/bin/hyfens" ]] || show_failure compact-latest
[[ "$(readlink "$last_prefix/bin/hyfens")" == "../opt/hyfens-${VERSION}/bin/hyfens" ]] ||
  show_failure compact-latest

current_metadata="$pretty_metadata"
expect_success pretty-latest

current_metadata="$malformed_metadata"
expect_failure malformed-latest 'latest-release response'

current_metadata="$missing_tag_metadata"
expect_failure missing-tag-latest 'did not contain tag_name'

current_metadata="$pretty_metadata"
current_checksums="$correct_checksums"
reject_latest=1
expect_success explicit-version --version "v$VERSION"
assert_no_curl_url explicit-version "https://api.github.com/repos/hyfens-hq/hyfens/releases/latest"
assert_curl_url explicit-version "https://github.com/hyfens-hq/hyfens/releases/download/v${VERSION}/${archive}"

current_checksums="$bad_checksums"
expect_failure checksum-mismatch 'checksum mismatch' --version "v$VERSION"

printf 'install-hyfens installer tests passed\n'
