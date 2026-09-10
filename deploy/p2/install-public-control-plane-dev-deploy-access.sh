#!/bin/sh
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

[ "$(id -u)" -eq 0 ] || {
  echo 'run this installer as root' >&2
  exit 1
}
[ "$#" -eq 0 ] || {
  echo 'installer accepts no arguments' >&2
  exit 2
}

stage=/home/hyfen/p2-deploy-stage/deploy/p2
source_wrapper="$stage/hyfens-public-control-plane-dev-deploy"
source_worker="$stage/hyfens-public-control-plane-dev-deletion-worker"
source_service="$stage/hyfens-public-control-plane-dev-deletion.service"
source_timer="$stage/hyfens-public-control-plane-dev-deletion.timer"
source_notification_worker="$stage/hyfens-public-control-plane-dev-notification-worker"
source_notification_service="$stage/hyfens-public-control-plane-dev-notification.service"
source_notification_timer="$stage/hyfens-public-control-plane-dev-notification.timer"
wrapper=/usr/local/sbin/hyfens-public-control-plane-dev-deploy
worker=/usr/local/sbin/hyfens-public-control-plane-dev-deletion-worker
service=/etc/systemd/system/hyfens-public-control-plane-dev-deletion.service
timer=/etc/systemd/system/hyfens-public-control-plane-dev-deletion.timer
notification_worker=/usr/local/sbin/hyfens-public-control-plane-dev-notification-worker
notification_service=/etc/systemd/system/hyfens-public-control-plane-dev-notification.service
notification_timer=/etc/systemd/system/hyfens-public-control-plane-dev-notification.timer
sudoers=/etc/sudoers.d/hyfens-public-control-plane-dev-deploy

[ -d "$stage" ] || {
  echo 'public control-plane development staging directory is missing' >&2
  exit 1
}
[ "$(readlink -f "$stage")" = "$stage" ] || {
  echo 'public control-plane development staging directory must not be a symlink' >&2
  exit 1
}
[ -f "$source_wrapper" ] || {
  echo 'public control-plane development deploy wrapper is missing from staging' >&2
  exit 1
}
[ "$(readlink -f "$source_wrapper")" = "$source_wrapper" ] || {
  echo 'public control-plane development deploy wrapper must not be a symlink' >&2
  exit 1
}
[ -x "$source_wrapper" ] || {
  echo 'public control-plane development deploy wrapper must be executable' >&2
  exit 1
}
for file in \
  "$source_worker" \
  "$source_service" \
  "$source_timer" \
  "$source_notification_worker" \
  "$source_notification_service" \
  "$source_notification_timer"; do
  [ -f "$file" ] || {
    echo "required worker file is missing: $file" >&2
    exit 1
  }
  [ "$(readlink -f "$file")" = "$file" ] || {
    echo "required deletion worker file must not be a symlink: $file" >&2
    exit 1
  }
done
[ -x "$source_worker" ] || {
  echo 'deletion worker must be executable' >&2
  exit 1
}
[ -x "$source_notification_worker" ] || {
  echo 'notification worker must be executable' >&2
  exit 1
}

install -o root -g root -m 0755 "$source_wrapper" "$wrapper"
install -o root -g root -m 0755 "$source_worker" "$worker"
install -o root -g root -m 0644 "$source_service" "$service"
install -o root -g root -m 0644 "$source_timer" "$timer"
install -o root -g root -m 0755 "$source_notification_worker" "$notification_worker"
install -o root -g root -m 0644 "$source_notification_service" "$notification_service"
install -o root -g root -m 0644 "$source_notification_timer" "$notification_timer"

sudoers_tmp=$(mktemp /etc/sudoers.d/.hyfens-public-control-plane-dev-deploy.XXXXXX)
trap 'rm -f "$sudoers_tmp"' EXIT
printf '%s\n' "hyfen ALL=(root) NOPASSWD: $wrapper" > "$sudoers_tmp"
chown root:root "$sudoers_tmp"
chmod 0440 "$sudoers_tmp"
visudo -cf "$sudoers_tmp" >/dev/null
mv -f "$sudoers_tmp" "$sudoers"
trap - EXIT

systemctl daemon-reload
systemctl enable --now hyfens-public-control-plane-dev-deletion.timer >/dev/null
systemctl enable --now hyfens-public-control-plane-dev-notification.timer >/dev/null

echo 'public control-plane development deployment access enabled' >&2
