#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 VERSION [CHANGELOG]" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 64
fi

version="${1#v}"
changelog="${2:-CHANGELOG.md}"

if [[ ! -f "$changelog" ]]; then
  echo "Changelog not found: $changelog" >&2
  exit 66
fi

header="## [$version]"
notes="$({
  awk -v header="$header" '
    index($0, header) == 1 &&
        (length($0) == length(header) || substr($0, length(header) + 1, 3) == " - ") {
      found = 1
      next
    }
    found && /^## \[/ { exit }
    found { print }
    END {
      if (!found) exit 2
    }
  ' "$changelog"
} | sed -e '/./,$!d')" || {
  echo "No changelog section found for [$version]." >&2
  exit 65
}

if [[ -z "${notes//[[:space:]]/}" ]]; then
  echo "Changelog section [$version] is empty." >&2
  exit 65
fi

printf '%s\n' "$notes"
