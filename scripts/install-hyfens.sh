#!/usr/bin/env bash
set -euo pipefail
umask 022

# This installer intentionally has one release source. Keeping the repository
# and transport here fixed makes a curl-piped install auditable and prevents a
# caller from redirecting the installer to an arbitrary artifact host.
readonly REPOSITORY='hyfens-hq/hyfens'
readonly RELEASES_API_URL="https://api.github.com/repos/${REPOSITORY}/releases/latest"
readonly RELEASES_BASE_URL="https://github.com/${REPOSITORY}/releases/download"

requested_version='latest'
prefix=''
prefix_was_set=0
platform=''
architecture=''
version=''
release_tag=''
archive=''
archive_root=''
release_base=''
checksum_tool=''
download_dir=''
install_staging=''
install_root=''
previous_root=''
previous_root_moved=0
new_root_committed=0
hyfens_link_temp=''
tool_link_temp=''
old_hyfens_link_present=0
old_hyfens_link_target=''
old_tool_link_present=0
old_tool_link_target=''

usage() {
  cat <<'EOF'
Usage: install-hyfens.sh [--version latest|v0.1.0] [--prefix PATH]

Install the Hyfens CLI from a GitHub Release on macOS or Linux.

Options:
  --version VERSION  Install latest (default) or an explicit release, such as
                     v0.1.0. A leading v is optional for an explicit version.
  --prefix PATH      Install under PATH instead of the writable standard path.
  -h, --help         Show this help.

The installer downloads only from the fixed hyfens-hq/hyfens GitHub repository,
verifies the selected archive against that release's SHA256SUMS, and does not
modify ~/.hyfens or files in a project checkout.
EOF
}

fail() {
  printf 'install-hyfens: %s\n' "$1" >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

rollback_link() {
  local name="$1"
  local present="$2"
  local target="$3"
  local link_path="$prefix/bin/$name"

  if [[ -L "$link_path" ]]; then
    rm -f "$link_path"
  elif [[ -e "$link_path" ]]; then
    printf 'install-hyfens: unable to roll back non-symlink %s\n' "$link_path" >&2
    return 1
  fi
  if [[ "$present" == 1 ]]; then
    ln -s "$target" "$link_path"
  fi
}

rollback_install() {
  if [[ "$new_root_committed" == 1 ]]; then
    rollback_link hyfens "$old_hyfens_link_present" "$old_hyfens_link_target" || true
    rollback_link tool "$old_tool_link_present" "$old_tool_link_target" || true
    if path_exists "$install_root"; then
      rm -rf "$install_root" || true
    fi
  fi

  if [[ "$previous_root_moved" == 1 ]] &&
    ! path_exists "$install_root" && path_exists "$previous_root"; then
    mv "$previous_root" "$install_root" || true
  fi
}

cleanup() {
  local status=$?
  trap - EXIT
  set +e

  if [[ "$status" != 0 ]]; then
    rollback_install
  fi
  if [[ -n "$hyfens_link_temp" ]] && path_exists "$hyfens_link_temp"; then
    rm -f "$hyfens_link_temp"
  fi
  if [[ -n "$tool_link_temp" ]] && path_exists "$tool_link_temp"; then
    rm -f "$tool_link_temp"
  fi
  if [[ -n "$install_staging" ]] && [[ -d "$install_staging" ]]; then
    rm -rf "$install_staging"
  fi
  if [[ -n "$download_dir" ]] && [[ -d "$download_dir" ]]; then
    rm -rf "$download_dir"
  fi
  exit "$status"
}

normalize_version() {
  local raw="$1"
  local normalized="$raw"
  local version_pattern='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

  if [[ "$normalized" == v* ]]; then
    normalized="${normalized#v}"
  fi
  if [[ ! "$normalized" =~ $version_pattern ]]; then
    fail "unsupported release version: $raw"
  fi
  printf '%s' "$normalized"
}

is_writable_prefix() {
  local candidate="$1"
  local parent

  if path_exists "$candidate" && [[ ! -d "$candidate" ]]; then
    return 1
  fi
  if [[ -d "$candidate" ]]; then
    [[ -w "$candidate" && -x "$candidate" ]]
    return
  fi
  parent="$(dirname "$candidate")"
  [[ -d "$parent" && -w "$parent" && -x "$parent" ]]
}

select_prefix() {
  local home

  if [[ "$prefix_was_set" == 1 ]]; then
    [[ "$prefix" == /* ]] || fail '--prefix must be an absolute path'
    while [[ "$prefix" == */ && "$prefix" != / ]]; do
      prefix="${prefix%/}"
    done
    [[ "$prefix" != / ]] || fail 'refusing to install directly into /'
    return
  fi

  if is_writable_prefix /usr/local; then
    prefix='/usr/local'
    return
  fi

  home="${HOME:-}"
  [[ "$home" == /* && -d "$home" ]] ||
    fail 'HOME must name an existing directory for the user-local fallback'
  prefix="$home/.local"
  if ! is_writable_prefix "$prefix"; then
    fail 'neither /usr/local nor the user-local prefix is writable; use --prefix PATH'
  fi
}

detect_host() {
  local uname_s
  local uname_m

  uname_s="$(uname -s)" || fail 'unable to determine the operating system'
  uname_m="$(uname -m)" || fail 'unable to determine the machine architecture'

  case "$uname_s" in
    Darwin) platform='macos' ;;
    Linux) platform='linux' ;;
    *) fail "unsupported operating system: $uname_s" ;;
  esac

  case "$uname_m" in
    x86_64|amd64) architecture='x64' ;;
    arm64|aarch64) architecture='arm64' ;;
    *) fail "unsupported machine architecture: $uname_m" ;;
  esac
}

curl_options=(
  --fail
  --silent
  --show-error
  --location
  --proto '=https'
  --proto-redir '=https'
  --tlsv1.2
  --retry 3
  --retry-delay 1
  --connect-timeout 15
  --max-time 120
  --user-agent hyfens-installer
)

download() {
  local url="$1"
  local destination="$2"
  curl "${curl_options[@]}" --output "$destination" "$url"
}

resolve_latest() {
  local metadata="$download_dir/latest.json"
  local tag

  download "$RELEASES_API_URL" "$metadata" ||
    fail 'unable to resolve the latest GitHub Release'
  tag="$(awk -F '"' '$2 == "tag_name" { print $4; exit }' "$metadata")"
  [[ -n "$tag" ]] || fail 'GitHub latest-release response did not contain tag_name'
  [[ "$tag" == v* ]] || fail "latest release tag is not a v-prefixed version: $tag"
  version="$(normalize_version "$tag")"
  release_tag="v$version"
}

resolve_requested_version() {
  if [[ "$requested_version" == latest ]]; then
    resolve_latest
  else
    version="$(normalize_version "$requested_version")"
    release_tag="v$version"
  fi
}

sha256_file() {
  local file="$1"
  if [[ "$checksum_tool" == shasum ]]; then
    shasum -a 256 "$file" | awk '{ print $1 }'
  else
    sha256sum "$file" | awk '{ print $1 }'
  fi
}

verify_checksum() {
  local checksum_file="$download_dir/SHA256SUMS"
  local expected
  local actual

  if ! expected="$(awk -v archive="$archive" '
    ($2 == archive || $2 == "*" archive) {
      if (found != "") duplicate = 1
      found = $1
    }
    END {
      if (duplicate || found == "") exit 1
      print found
    }
  ' "$checksum_file")"; then
    fail "SHA256SUMS has no unique checksum for $archive"
  fi
  case "$expected" in
    ''|*[!0-9A-Fa-f]*) fail "invalid checksum for $archive" ;;
  esac
  [[ "${#expected}" == 64 ]] || fail "invalid checksum for $archive"

  actual="$(sha256_file "$download_dir/$archive")"
  expected="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"
  actual="$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')"
  [[ "$actual" == "$expected" ]] ||
    fail "checksum mismatch for $archive"
  printf 'Verified SHA-256 for %s\n' "$archive"
}

validate_archive() {
  local listing
  local type_listing
  local entry
  local normalized
  local entry_type

  if ! listing="$(tar -tzf "$download_dir/$archive")"; then
    fail "unable to read release archive: $archive"
  fi
  [[ -n "$listing" ]] || fail 'release archive is empty'
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    normalized="${entry%/}"
    case "$normalized" in
      "$archive_root"|"$archive_root"/*) ;;
      *) fail "archive contains an unexpected path: $entry" ;;
    esac
    case "$normalized" in
      /*|.|..|./*|../*|*/./*|*/../*|*/..|*[!A-Za-z0-9._/+:-]*)
        fail "archive contains an unsafe path: $entry"
        ;;
    esac
  done <<< "$listing"

  if ! type_listing="$(tar -tvzf "$download_dir/$archive")"; then
    fail "unable to inspect release archive entry types: $archive"
  fi
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    entry_type="${entry:0:1}"
    case "$entry_type" in
      -|d) ;;
      *) fail 'release archive contains a link or special file' ;;
    esac
  done <<< "$type_listing"
}

extract_and_validate() {
  local extraction_dir="$download_dir/extracted"
  local extracted_root="$extraction_dir/$archive_root"
  local link_path

  mkdir -p "$extraction_dir"
  validate_archive
  tar -xzf "$download_dir/$archive" -C "$extraction_dir" ||
    fail "unable to extract release archive: $archive"

  [[ -d "$extracted_root" && ! -L "$extracted_root" ]] ||
    fail 'release archive does not contain its expected root directory'
  [[ -f "$extracted_root/bin/hyfens" && ! -L "$extracted_root/bin/hyfens" &&
    -x "$extracted_root/bin/hyfens" ]] ||
    fail 'release archive does not contain an executable bin/hyfens'
  [[ -f "$extracted_root/bin/tool" && ! -L "$extracted_root/bin/tool" &&
    -x "$extracted_root/bin/tool" ]] ||
    fail 'release archive does not contain an executable bin/tool'
  if path_exists "$extracted_root/lib" &&
    [[ ! -d "$extracted_root/lib" || -L "$extracted_root/lib" ]]; then
    fail 'release archive contains an invalid lib directory'
  fi
  link_path="$(find "$extracted_root" -type l -print -quit)"
  [[ -z "$link_path" ]] || fail 'release archive contains a symbolic link'
  printf '%s\n' "$extracted_root"
}

check_link_slot() {
  local name="$1"
  local link_path="$prefix/bin/$name"
  local target

  if path_exists "$link_path"; then
    [[ -L "$link_path" ]] ||
      fail "refusing to overwrite existing non-symlink: $link_path"
    target="$(readlink "$link_path")" || fail "unable to inspect $link_path"
    [[ -n "$target" ]] || fail "existing symlink has no target: $link_path"
    if [[ "$name" == hyfens ]]; then
      old_hyfens_link_present=1
      old_hyfens_link_target="$target"
    else
      old_tool_link_present=1
      old_tool_link_target="$target"
    fi
  fi
}

update_link() {
  local name="$1"
  local link_path="$prefix/bin/$name"
  local link_target="../opt/hyfens-${version}/bin/$name"
  local temporary

  temporary="$(mktemp "$prefix/bin/.hyfens-${name}.XXXXXX")"
  rm -f "$temporary"
  if [[ "$name" == hyfens ]]; then
    hyfens_link_temp="$temporary"
  else
    tool_link_temp="$temporary"
  fi
  ln -s "$link_target" "$temporary" ||
    fail "unable to create the $name launcher"
  mv "$temporary" "$link_path" ||
    fail "unable to activate the $name launcher"
  if [[ "$name" == hyfens ]]; then
    hyfens_link_temp=''
  else
    tool_link_temp=''
  fi
}

install_release() {
  local extracted_root="$1"
  local staged_root

  mkdir -p "$prefix/bin" "$prefix/opt"
  check_link_slot hyfens
  check_link_slot tool

  install_staging="$(mktemp -d "$prefix/opt/.hyfens-install.XXXXXX")"
  cp -R "$extracted_root" "$install_staging/" ||
    fail 'unable to stage the verified release'
  staged_root="$install_staging/$archive_root"
  [[ -d "$staged_root" && ! -L "$staged_root" ]] ||
    fail 'staged release root is missing'

  install_root="$prefix/opt/hyfens-$version"
  if path_exists "$install_root"; then
    [[ -d "$install_root" || -L "$install_root" ]] ||
      fail "existing install path is not a directory: $install_root"
    previous_root="$prefix/opt/.hyfens-$version.previous.$$"
    path_exists "$previous_root" &&
      fail "temporary rollback path already exists: $previous_root"
    mv "$install_root" "$previous_root" ||
      fail "unable to replace the existing release: $install_root"
    previous_root_moved=1
  fi
  mv "$staged_root" "$install_root" ||
    fail "unable to activate the verified release: $install_root"
  new_root_committed=1

  update_link hyfens
  update_link tool

  if [[ "$previous_root_moved" == 1 ]]; then
    rm -rf "$previous_root"
    previous_root_moved=0
  fi
}

while (($# > 0)); do
  case "$1" in
    --version)
      (($# >= 2)) || fail '--version requires a value'
      requested_version="$2"
      shift 2
      ;;
    --version=*)
      requested_version="${1#*=}"
      shift
      ;;
    --prefix)
      (($# >= 2)) || fail '--prefix requires a path'
      prefix="$2"
      prefix_was_set=1
      shift 2
      ;;
    --prefix=*)
      prefix="${1#*=}"
      prefix_was_set=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      (($# == 0)) || fail 'unexpected positional arguments'
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

trap cleanup EXIT

require_command awk
require_command chmod
require_command cp
require_command curl
require_command find
require_command ln
require_command mkdir
require_command mktemp
require_command mv
require_command readlink
require_command rm
require_command tar
require_command tr
require_command uname
if command -v shasum >/dev/null 2>&1; then
  checksum_tool='shasum'
elif command -v sha256sum >/dev/null 2>&1; then
  checksum_tool='sha256sum'
else
  fail 'required command is missing: shasum or sha256sum'
fi

detect_host
select_prefix
download_dir="$(mktemp -d "${TMPDIR:-/tmp}/hyfens-install.XXXXXX")"
resolve_requested_version
archive="hyfens-${version}-${platform}-${architecture}.tar.gz"
archive_root="hyfens-${version}-${platform}-${architecture}"
release_base="${RELEASES_BASE_URL}/${release_tag}"

printf 'Downloading Hyfens CLI %s for %s/%s\n' "$version" "$platform" "$architecture"
download "$release_base/$archive" "$download_dir/$archive" ||
  fail "unable to download release archive: $archive"
download "$release_base/SHA256SUMS" "$download_dir/SHA256SUMS" ||
  fail 'unable to download release checksums: SHA256SUMS'
verify_checksum
extracted_root="$(extract_and_validate)"
install_release "$extracted_root"

printf 'Installed Hyfens CLI %s under %s\n' "$version" "$prefix"
printf '  %s\n' "$prefix/bin/hyfens"
printf '  %s (deprecated compatibility shim)\n' "$prefix/bin/tool"
printf '\nPATH guidance:\n'
printf '  export PATH=%q:$PATH\n' "$prefix/bin"
printf 'Then run: hyfens --version\n'
