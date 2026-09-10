#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || {
  echo 'run this installer as root' >&2
  exit 1
}
[ "$#" -eq 0 ] || {
  echo 'installer accepts no arguments' >&2
  exit 2
}

stage=/home/hyfen/p2-deploy-stage/web
source_wrapper="$stage/hyfens-dashboard-deploy"
source_nginx="$stage/hyfens-dashboard-local.conf"
env_file=/etc/hyfens/public-control-plane-dev.env
wrapper=/usr/local/sbin/hyfens-dashboard-deploy
nginx_site=/etc/nginx/sites-available/hyfens-dashboard-local.conf
nginx_link=/etc/nginx/sites-enabled/hyfens-dashboard-local.conf
sudoers=/etc/sudoers.d/hyfens-dashboard-deploy

[ -d "$stage" ] || {
  echo 'dashboard deployment setup staging directory is missing' >&2
  exit 1
}
[ "$(readlink -f "$stage")" = "$stage" ] || {
  echo 'dashboard deployment setup staging directory must not be a symlink' >&2
  exit 1
}
[ -f "$source_wrapper" ] || {
  echo 'dashboard deploy wrapper is missing from staging' >&2
  exit 1
}
[ "$(readlink -f "$source_wrapper")" = "$source_wrapper" ] || {
  echo 'dashboard deploy wrapper must not be a symlink' >&2
  exit 1
}
[ -f "$source_nginx" ] || {
  echo 'dashboard nginx configuration is missing from staging' >&2
  exit 1
}
[ "$(readlink -f "$source_nginx")" = "$source_nginx" ] || {
  echo 'dashboard nginx configuration must not be a symlink' >&2
  exit 1
}
[ -f "$env_file" ] || {
  echo 'protected public control-plane development environment is missing' >&2
  exit 1
}
[ "$(stat -c '%U:%G %a' "$env_file")" = 'root:root 600' ] || {
  echo 'public control-plane development environment ownership or mode is unsafe' >&2
  exit 1
}

install -o root -g root -m 0755 "$source_wrapper" "$wrapper"
install -o root -g root -m 0644 "$source_nginx" "$nginx_site"

printf '%s\n' 'hyfen ALL=(root) NOPASSWD: /usr/local/sbin/hyfens-dashboard-deploy' > "$sudoers"
chown root:root "$sudoers"
chmod 440 "$sudoers"
visudo -cf "$sudoers" >/dev/null

if [ -e "$nginx_link" ] || [ -L "$nginx_link" ]; then
  [ "$(readlink -f "$nginx_link")" = "$nginx_site" ] || {
    echo 'existing dashboard nginx link has an unexpected target' >&2
    exit 1
  }
else
  ln -s "$nginx_site" "$nginx_link"
fi

tmp=''
trap 'if [ -n "${tmp:-}" ] && [ -e "$tmp" ]; then rm -f "$tmp"; fi' EXIT

set_env_value() {
  name=$1
  value=$2
  current=$(awk -F= -v name="$name" '$1 == name { sub(/^[^=]*=/, ""); print; exit }' "$env_file")
  if [ "$name" = 'HYFENS_WEB_ORIGINS' ] && [ -n "$current" ]; then
    case ",$current," in
      *",$value,"*) value=$current ;;
      *) value="$current,$value" ;;
    esac
  fi
  tmp=$(mktemp /etc/hyfens/public-control-plane-dev.env.XXXXXX)
  awk -v name="$name" -v value="$value" '
    BEGIN { updated = 0 }
    $1 == name || $0 ~ "^[[:space:]]*" name "[[:space:]]*=" {
      if (!updated) {
        print name "=" value
        updated = 1
      }
      next
    }
    { print }
    END {
      if (!updated) print name "=" value
    }
  ' "$env_file" > "$tmp"
  chown root:root "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$env_file"
  tmp=''
}

set_env_value HYFENS_AUTH_AUTHORIZATION_ENDPOINT 'https://app.hyfens.com/cli/authorize'
set_env_value HYFENS_AUTH_DEVICE_VERIFICATION_URI 'https://app.hyfens.com/device'
set_env_value HYFENS_WEB_ORIGINS 'https://app.hyfens.com'

/usr/sbin/nginx -t
/usr/bin/systemctl reload nginx
[ -x /usr/local/sbin/hyfens-public-control-plane-dev-deploy ] || {
  echo 'public control-plane development deploy wrapper is missing' >&2
  exit 1
}
/usr/local/sbin/hyfens-public-control-plane-dev-deploy >/dev/null

rm -f "$stage/hyfens-dashboard-deploy" "$stage/hyfens-dashboard-local.conf" "$stage/install-dashboard-deploy-access.sh"
rmdir "$stage" 2>/dev/null || true
echo 'hyfens dashboard deployment access enabled'
