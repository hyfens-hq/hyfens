#!/usr/bin/env bash
set -euo pipefail

# Install the CLI from this repository checkout. This is intentionally a
# source-checkout installer until a signed release archive and public hosting
# endpoint exist. It supports macOS/Linux hosts with the Dart SDK installed.

usage() {
  cat <<'EOF'
Usage: install-hyfens.sh [--prefix PATH]

Build and install the Hyfens CLI from this repository checkout.

The default prefix is ~/.local. The installer places:
  PREFIX/bin/hyfens  canonical CLI
  PREFIX/bin/tool     deprecated compatibility shim

This path requires the Dart SDK and is not a network installer. Published
release archives, checksums, and package-manager integration require a future
release process with an external artifact host.
EOF
}

fail() {
  printf 'install-hyfens: %s\n' "$1" >&2
  exit 2
}

if [[ -n "${HOME:-}" ]]; then
  prefix="$HOME/.local"
else
  prefix=''
fi

while (($# > 0)); do
  case "$1" in
    --prefix)
      (($# >= 2)) || fail '--prefix requires a path'
      prefix="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$prefix" ]] || fail 'set HOME or provide --prefix PATH'
[[ "$prefix" == /* ]] || fail '--prefix must be an absolute path'
[[ "$prefix" != '/' ]] || fail 'refusing to install directly into /'

command -v dart >/dev/null 2>&1 || fail 'Dart SDK is required'
command -v install >/dev/null 2>&1 || fail 'install command is required'
command -v mktemp >/dev/null 2>&1 || fail 'mktemp command is required'
command -v find >/dev/null 2>&1 || fail 'find command is required'

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
cli_root="$repo_root/cli"

[[ -f "$cli_root/pubspec.yaml" ]] || fail "CLI package not found: $cli_root"
[[ -f "$cli_root/bin/hyfens.dart" ]] || fail 'canonical entry point is missing'
[[ -f "$cli_root/bin/tool.dart" ]] || fail 'compatibility entry point is missing'
[[ "$prefix" != "$repo_root" ]] || fail 'refusing to install into the repository root'

staging="$(mktemp -d "${TMPDIR:-/tmp}/hyfens-install.XXXXXX")"
cleanup() {
  rm -rf -- "$staging"
}
trap cleanup EXIT

# Enforce the checked-in lockfile when resolving dependencies. This prevents
# an install from silently changing the dependency graph used by the build.
(cd "$cli_root" && dart pub get --enforce-lockfile --no-example)

build_target() {
  local target="$1"
  local output="$2"
  (cd "$cli_root" && dart build cli \
    --target "$target" \
    --output "$output" \
    --verbosity=warning)
}

build_target bin/hyfens.dart "$staging/hyfens"
build_target bin/tool.dart "$staging/tool"

canonical_bundle="$staging/hyfens/bundle"
legacy_bundle="$staging/tool/bundle"
canonical_binary="$canonical_bundle/bin/hyfens"
legacy_binary="$legacy_bundle/bin/tool"

[[ -x "$canonical_binary" ]] || fail 'Dart did not produce bundle/bin/hyfens'
[[ -x "$legacy_binary" ]] || fail 'Dart did not produce bundle/bin/tool'

install -d -m 755 "$prefix/bin"
install -m 755 "$canonical_binary" "$prefix/bin/hyfens"
install -m 755 "$legacy_binary" "$prefix/bin/tool"

native_library_count=0
if [[ -d "$canonical_bundle/lib" ]]; then
  install -d -m 755 "$prefix/lib"
  while IFS= read -r -d '' library; do
    native_library_count=$((native_library_count + 1))
    destination="$prefix/lib/$(basename "$library")"
    if [[ -e "$destination" ]] && ! cmp -s "$library" "$destination"; then
      fail "refusing to overwrite a different native library: $destination"
    fi
    if [[ ! -e "$destination" ]]; then
      install -m 755 "$library" "$destination"
    fi
  done < <(find "$canonical_bundle/lib" -mindepth 1 -maxdepth 1 -type f -print0)
fi

printf 'Installed Hyfens CLI from %s\n' "$repo_root"
printf '  %s\n' "$prefix/bin/hyfens"
printf '  %s (deprecated compatibility shim)\n' "$prefix/bin/tool"
if ((native_library_count > 0)); then
  printf '  native libraries: %d in %s/lib\n' "$native_library_count" "$prefix"
fi
printf 'Add %s/bin to PATH, then run: hyfens --version\n' "$prefix"
