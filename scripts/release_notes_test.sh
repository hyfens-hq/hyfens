#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
extractor="$script_dir/release_notes.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/hyfens-release-notes-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

fixture="$test_dir/CHANGELOG.md"
printf '%s\n' \
  '# Changelog' \
  '' \
  '## [Unreleased]' \
  '' \
  '### Changed' \
  '' \
  '- Future work.' \
  '' \
  '## [1.2.3] - 2026-09-07' \
  '' \
  '### Fixed' \
  '' \
  '- Keep **Markdown** and the following block.' \
  '' \
  '```dart' \
  'final value = true;' \
  '```' \
  '' \
  '## [1.2.4] - 2026-09-08' \
  '' \
  '### Added' \
  '' \
  '- Later release.' > "$fixture"

expected=$'### Fixed\n\n- Keep **Markdown** and the following block.\n\n```dart\nfinal value = true;\n```'
actual="$(bash "$extractor" v1.2.3 "$fixture")"
if [[ "$actual" != "$expected" ]]; then
  echo 'version extraction or Markdown preservation failed' >&2
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
  exit 1
fi

unreleased="$(bash "$extractor" Unreleased "$fixture")"
if [[ "$unreleased" != $'### Changed\n\n- Future work.' ]]; then
  echo '[Unreleased] extraction failed' >&2
  exit 1
fi

if bash "$extractor" 9.9.9 "$fixture" >/dev/null 2>&1; then
  echo 'missing version should fail' >&2
  exit 1
fi

empty="$test_dir/empty.md"
printf '%s\n' '# Changelog' '' '## [1.2.3] - 2026-09-07' '' '## [1.2.4] - 2026-09-08' '' '- Later release.' > "$empty"
if bash "$extractor" 1.2.3 "$empty" >/dev/null 2>&1; then
  echo 'empty release notes should fail' >&2
  exit 1
fi

echo 'release note extraction tests passed'
