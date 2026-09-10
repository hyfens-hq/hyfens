#!/usr/bin/env bash
set -euo pipefail

: "${HYFENS_DATABASE_URL:?HYFENS_DATABASE_URL is required}"
: "${HYFENS_ALLOW_RESTORE:?set HYFENS_ALLOW_RESTORE=1 after confirming the target is disposable/recovery-approved}"
if [[ "$HYFENS_ALLOW_RESTORE" != 1 ]]; then
  echo 'HYFENS_ALLOW_RESTORE must equal 1' >&2
  exit 2
fi
input="${1:?usage: p2-postgres-restore.sh dump-file}"
case "$input" in
  /*|*..*|*"$"*) echo 'Refusing an unsafe restore path' >&2; exit 2 ;;
esac
pg_restore --dbname="$HYFENS_DATABASE_URL" --clean --if-exists --no-owner "$input"
echo "restore_completed=$input"
