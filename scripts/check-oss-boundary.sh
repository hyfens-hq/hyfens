#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

status=0

forbidden_paths='(^|/)(deploy/(p2|aws)(/|$)|scripts/p2-|scripts/aws-disposable-|docs/operations(/|$)|docs/product/platform-console\.md$|packages/control_plane/lib/src/platform_|tasks/(4[0-9]|8[0-9]|9[0-9]|2(1[0-9]|2[0-9]|3[0-9]|4[0-9]|5[0-9]|6[0-9]|7[0-9]|8[0-4]))-)'
if rg --files --hidden --glob '!.git/**' --glob '!deploy/aws/**/.terraform/**' |
  grep -E "$forbidden_paths"; then
  echo 'OSS boundary violation: hosted or operator-only path is tracked.' >&2
  status=1
fi

# Build sensitive provider/host fragments without storing a complete internal
# marker in this public check itself.
private_terms='cloud''flare|kepl''ars|razor''pay|[[:alnum:]-]+[.]hyfens[.]com'
if git grep -n -I -i -E "$private_terms" -- ':!scripts/check-oss-boundary.sh'; then
  echo 'OSS boundary violation: private provider or deployment marker found.' >&2
  status=1
fi

exit "$status"
