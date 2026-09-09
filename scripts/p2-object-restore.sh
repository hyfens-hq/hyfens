#!/usr/bin/env bash
set -euo pipefail

: "${HYFENS_ALLOW_RESTORE:?set HYFENS_ALLOW_RESTORE=1 after confirming the target is disposable/recovery-approved}"
if [[ "$HYFENS_ALLOW_RESTORE" != 1 ]]; then
  echo 'HYFENS_ALLOW_RESTORE must equal 1' >&2
  exit 2
fi
: "${HYFENS_OBJECT_ENDPOINT:?HYFENS_OBJECT_ENDPOINT is required}"
: "${HYFENS_S3_BUCKET:?HYFENS_S3_BUCKET is required}"
: "${HYFENS_S3_ACCESS_KEY:?HYFENS_S3_ACCESS_KEY is required}"
: "${HYFENS_S3_SECRET_KEY:?HYFENS_S3_SECRET_KEY is required}"
: "${HYFENS_S3_DOCKER_NETWORK:?HYFENS_S3_DOCKER_NETWORK is required}"

input="${1:?usage: p2-object-restore.sh backup-directory}"
case "$input" in
  *..*|*'$'*|'')
    echo 'Refusing an unsafe object restore path' >&2
    exit 2
    ;;
esac
if [ ! -d "$input/objects" ]; then
  echo 'Object backup must contain an objects directory' >&2
  exit 2
fi

absolute_input="$(cd "$input" && pwd)"
docker run --rm \
  --network "$HYFENS_S3_DOCKER_NETWORK" \
  -e MC_ENDPOINT="$HYFENS_OBJECT_ENDPOINT" \
  -e MC_ACCESS_KEY="$HYFENS_S3_ACCESS_KEY" \
  -e MC_SECRET_KEY="$HYFENS_S3_SECRET_KEY" \
  -e MC_BUCKET="$HYFENS_S3_BUCKET" \
  -v "$absolute_input:/backup:ro" \
  --entrypoint /bin/sh \
  "${HYFENS_MC_IMAGE:-minio/mc:latest}" \
  -ec '
    mc alias set hyfens "$MC_ENDPOINT" "$MC_ACCESS_KEY" "$MC_SECRET_KEY" --api S3v4 >/dev/null
    mc mirror --overwrite --quiet /backup/objects "hyfens/$MC_BUCKET"
  '
echo "object_restore_completed=$input"
