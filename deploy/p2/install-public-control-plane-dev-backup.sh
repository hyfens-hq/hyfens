#!/bin/sh
set -eu

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

[ "$(id -u)" -eq 0 ] || {
  echo 'backup installer must run as root' >&2
  exit 1
}
[ "$#" -eq 0 ] || {
  echo 'backup installer accepts no arguments' >&2
  exit 2
}

stage=/home/hyfen/p2-deploy-stage/deploy/p2
env_file=/etc/hyfens/public-control-plane-dev.env
source_wrapper="$stage/hyfens-public-control-plane-dev-backup"
source_service="$stage/hyfens-public-control-plane-dev-backup.service"
source_timer="$stage/hyfens-public-control-plane-dev-backup.timer"
source_freshness_service="$stage/hyfens-public-control-plane-dev-backup-freshness.service"
source_freshness_timer="$stage/hyfens-public-control-plane-dev-backup-freshness.timer"
wrapper=/usr/local/sbin/hyfens-public-control-plane-dev-backup
service=/etc/systemd/system/hyfens-public-control-plane-dev-backup.service
timer=/etc/systemd/system/hyfens-public-control-plane-dev-backup.timer
freshness_service=/etc/systemd/system/hyfens-public-control-plane-dev-backup-freshness.service
freshness_timer=/etc/systemd/system/hyfens-public-control-plane-dev-backup-freshness.timer

fail() {
  echo "public control-plane backup installation failed: $*" >&2
  exit 1
}

[ -d "$stage" ] || fail 'public control-plane deployment staging directory is missing'
[ "$(readlink -f "$stage")" = "$stage" ] || {
  fail 'public control-plane deployment staging directory must not be a symlink'
}
[ -f "$env_file" ] || fail 'protected public control-plane environment is missing'
[ "$(readlink -f "$env_file")" = "$env_file" ] || {
  fail 'protected public control-plane environment must not be a symlink'
}
[ "$(stat -c '%U:%G %a' "$env_file")" = 'root:root 600' ] || {
  fail 'protected public control-plane environment must be root:root with mode 600'
}

for file in \
  "$source_wrapper" \
  "$source_service" \
  "$source_timer" \
  "$source_freshness_service" \
  "$source_freshness_timer"; do
  [ -f "$file" ] || fail "staged public backup file is missing: $file"
  [ "$(readlink -f "$file")" = "$file" ] || {
    fail "staged public backup file must not be a symlink: $file"
  }
done
[ -x "$source_wrapper" ] || fail 'staged public backup wrapper must be executable'

for name in \
  HYFENS_PUBLIC_BACKUP_SOURCE_ENDPOINT \
  HYFENS_PUBLIC_BACKUP_SOURCE_BUCKET \
  HYFENS_PUBLIC_BACKUP_SOURCE_ACCESS_KEY_ID \
  HYFENS_PUBLIC_BACKUP_SOURCE_SECRET_ACCESS_KEY \
  HYFENS_PUBLIC_BACKUP_DEST_ENDPOINT \
  HYFENS_PUBLIC_BACKUP_DEST_BUCKET \
  HYFENS_PUBLIC_BACKUP_DEST_ACCOUNT_ID \
  HYFENS_PUBLIC_BACKUP_DEST_ACCESS_KEY_ID \
  HYFENS_PUBLIC_BACKUP_DEST_SECRET_ACCESS_KEY \
  HYFENS_PUBLIC_BACKUP_MAX_AGE_SECONDS; do
  grep -Eq "^[[:space:]]*$name[[:space:]]*=[[:space:]]*[^[:space:]]" "$env_file" || {
    fail "protected public control-plane environment is missing $name"
  }
done

max_age=$(sed -n 's/^[[:space:]]*HYFENS_PUBLIC_BACKUP_MAX_AGE_SECONDS[[:space:]]*=[[:space:]]*//p' "$env_file" | head -n 1)
printf '%s\n' "$max_age" | grep -Eq '^[1-9][0-9]*$' || {
  fail 'HYFENS_PUBLIC_BACKUP_MAX_AGE_SECONDS must be a positive integer'
}
[ "$max_age" -ge 900 ] && [ "$max_age" -le 2592000 ] || {
  fail 'HYFENS_PUBLIC_BACKUP_MAX_AGE_SECONDS must be between 900 and 2592000 seconds'
}

install -o root -g root -m 0755 "$source_wrapper" "$wrapper"
install -o root -g root -m 0644 "$source_service" "$service"
install -o root -g root -m 0644 "$source_timer" "$timer"
install -o root -g root -m 0644 "$source_freshness_service" "$freshness_service"
install -o root -g root -m 0644 "$source_freshness_timer" "$freshness_timer"

systemctl daemon-reload
systemctl enable --now hyfens-public-control-plane-dev-backup.timer >/dev/null
systemctl enable --now hyfens-public-control-plane-dev-backup-freshness.timer >/dev/null

echo 'public control-plane managed backup and freshness timers enabled' >&2
