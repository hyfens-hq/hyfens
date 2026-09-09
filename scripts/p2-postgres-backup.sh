#!/usr/bin/env bash
set -euo pipefail

: "${HYFENS_DATABASE_URL:?HYFENS_DATABASE_URL is required}"
output="${1:-hyfens-control-plane-$(date -u +%Y%m%dT%H%M%SZ).dump}"
case "$output" in
  /*|*..*|*"$"*) echo 'Refusing an unsafe backup path' >&2; exit 2 ;;
esac
pg_dump "$HYFENS_DATABASE_URL" --format=custom --no-owner --file "$output"
echo "backup_created=$output"
