#!/bin/sh
set -eu
set +x

[ "$(id -u)" -eq 0 ] || {
  echo 'public control-plane bootstrap must run as root' >&2
  exit 1
}
[ "$#" -eq 0 ] || {
  echo 'bootstrap-platform-users accepts no arguments' >&2
  exit 2
}

compose_file=/opt/hyfens/public-control-plane-dev/deploy/p2/docker-compose.public-control-plane-dev.yml
env_file=/etc/hyfens/public-control-plane-dev.env

[ -f "$compose_file" ] || {
  echo "public control-plane Compose file is missing: $compose_file" >&2
  exit 1
}
[ -f "$env_file" ] || {
  echo "public control-plane environment file is missing: $env_file" >&2
  exit 1
}
[ "$(stat -c '%U:%G %a' "$env_file")" = 'root:root 600' ] || {
  echo 'public control-plane environment file must be root:root with mode 600' >&2
  exit 1
}

compose() {
  /usr/bin/docker compose \
    --project-name hyfens-public-control-plane-dev \
    --file "$compose_file" \
    --env-file "$env_file" \
    "$@"
}

compose ps --status running --services | grep -qx 'control-plane' || {
  echo 'control-plane is not running; deploy the public control-plane development stack before bootstrapping users' >&2
  exit 1
}

prompt_value() {
  prompt=$1
  default=$2
  printf '%s [%s]: ' "$prompt" "$default" >&2
  IFS= read -r value
  value=${value:-$default}
  case "$value" in
    ''|*[!A-Za-z0-9_.:@-]*)
      echo 'value contains unsupported characters' >&2
      exit 1
      ;;
  esac
  REPLY=$value
}

prompt_email() {
  prompt=$1
  default=$2
  printf '%s [%s]: ' "$prompt" "$default" >&2
  IFS= read -r value
  value=${value:-$default}
  case "$value" in
    ''|*[!A-Za-z0-9_.+%\@-]*|*@*\@*)
      echo 'email contains unsupported characters' >&2
      exit 1
      ;;
  esac
  case "$value" in
    *@*) : ;;
    *) echo 'email must contain @' >&2; exit 1 ;;
  esac
  REPLY=$value
}

prompt_secret() {
  prompt=$1
  printf '%s' "$prompt" >&2
  if [ -t 0 ]; then
    tty_state=$(stty -g)
    stty -echo
    if IFS= read -r secret; then
      stty "$tty_state"
      printf '\n' >&2
    else
      stty "$tty_state"
      printf '\n' >&2
      echo 'password input was not provided' >&2
      exit 1
    fi
  else
    IFS= read -r secret || {
      echo 'password input was not provided' >&2
      exit 1
    }
  fi
  [ "${#secret}" -ge 12 ] || {
    echo 'password must contain at least 12 characters' >&2
    exit 1
  }
  REPLY=$secret
}

bootstrap() {
  mode=$1
  email=$2
  password=$3
  profile=$4
  if [ "$mode" = 'owner' ]; then
    bootstrap_flag=--bootstrap-owner
  else
    bootstrap_flag=--bootstrap-admin
  fi
  printf '%s\n' "$password" | compose exec -T control-plane \
    dart run bin/control_plane.dart "$bootstrap_flag" --password-stdin \
    --organization-id "$organization_id" \
    --application-id "$application_id" \
    --environment-id "$environment_id" \
    --email "$email" \
    --profile "$profile"
}

organization_default=org70760ae2ff001f83f59af0f1b43cb67e5df1
application_default=app6c9b6afc1fe6e72e6b5945a2708b218c7c0e
environment_default=env0179b608edaa997d4ebe85887ae029542568

prompt_value 'Organization ID' "$organization_default"
organization_id=$REPLY
prompt_value 'Application ID' "$application_default"
application_id=$REPLY
prompt_value 'Environment ID' "$environment_default"
environment_id=$REPLY

prompt_email 'Super-admin owner email' 'super-admin@hyfens.local'
owner_email=$REPLY
prompt_email 'Content-admin email' 'admin@hyfens.local'
admin_email=$REPLY
[ "$owner_email" != "$admin_email" ] || {
  echo 'super-admin and content-admin emails must be different' >&2
  exit 1
}

printf '%s\n' >&2
prompt_secret 'Super-admin owner password: '
owner_password=$REPLY
prompt_secret 'Confirm super-admin owner password: '
[ "$REPLY" = "$owner_password" ] || {
  echo 'super-admin passwords do not match' >&2
  exit 1
}

prompt_secret 'Content-admin password: '
admin_password=$REPLY
prompt_secret 'Confirm content-admin password: '
[ "$REPLY" = "$admin_password" ] || {
  echo 'content-admin passwords do not match' >&2
  exit 1
}

printf '%s\n' 'Bootstrapping the existing scope; passwords are not persisted.' >&2
bootstrap owner "$owner_email" "$owner_password" super-admin
unset owner_password
bootstrap admin "$admin_email" "$admin_password" content-admin
unset admin_password
unset REPLY secret value
echo 'super-admin owner and content-admin bootstrap completed' >&2
