#!/bin/sh

set -eu

runtime_root=/tmp/hyfens-dashboard
api_base=${HYFENS_API_BASE:-/}

# The image remains immutable/read-only. Copy the static bundle into the
# container's ephemeral web root and write only the non-secret routing value
# there. Base64 keeps the operator-provided URL out of shell/JavaScript source
# interpolation, including quotes and other punctuation.
mkdir -p "$runtime_root"
cp -R /opt/hyfens/dashboard/. "$runtime_root/"
encoded_api_base=$(printf '%s' "$api_base" | base64 | tr -d '\n')
printf '%s\n' \
  "window.__HYFENS_RUNTIME_CONFIG__ = { apiBase: atob('$encoded_api_base') };" \
  >"$runtime_root/runtime-config.js"

exec "$@"
