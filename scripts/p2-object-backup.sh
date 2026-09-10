#!/usr/bin/env bash
set -euo pipefail

: "${HYFENS_OBJECT_ENDPOINT:?HYFENS_OBJECT_ENDPOINT is required}"
: "${HYFENS_S3_BUCKET:?HYFENS_S3_BUCKET is required}"
: "${HYFENS_S3_ACCESS_KEY:?HYFENS_S3_ACCESS_KEY is required}"
: "${HYFENS_S3_SECRET_KEY:?HYFENS_S3_SECRET_KEY is required}"
: "${HYFENS_S3_DOCKER_NETWORK:?HYFENS_S3_DOCKER_NETWORK is required}"

output="${1:?usage: p2-object-backup.sh backup-directory}"
case "$output" in
  *..*|*'$'*|'')
    echo 'Refusing an unsafe object backup path' >&2
    exit 2
    ;;
esac

mkdir -p "$output/objects"
absolute_output="$(cd "$output" && pwd)"
docker run --rm \
  --network "$HYFENS_S3_DOCKER_NETWORK" \
  -e MC_ENDPOINT="$HYFENS_OBJECT_ENDPOINT" \
  -e MC_ACCESS_KEY="$HYFENS_S3_ACCESS_KEY" \
  -e MC_SECRET_KEY="$HYFENS_S3_SECRET_KEY" \
  -e MC_BUCKET="$HYFENS_S3_BUCKET" \
  -v "$absolute_output:/backup" \
  --entrypoint /bin/sh \
  "${HYFENS_MC_IMAGE:-minio/mc:latest}" \
  -ec '
    mc alias set hyfens "$MC_ENDPOINT" "$MC_ACCESS_KEY" "$MC_SECRET_KEY" --api S3v4 >/dev/null
    mc mirror --overwrite --quiet "hyfens/$MC_BUCKET" /backup/objects
  '

(
  cd "$absolute_output/objects"
  : > ../manifest.sha256
  for object in *; do
    [ -f "$object" ] || continue
    shasum -a 256 "$object" >> ../manifest.sha256
  done
)
echo "object_backup_created=$output"
