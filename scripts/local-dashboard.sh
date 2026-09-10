#!/bin/sh

set -eu
set +x
umask 077

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
state_dir=${HYFENS_LOCAL_DASHBOARD_STATE_DIR:-${HOME:?HOME must be set}/.hyfens/local-dashboard}
env_file=$state_dir/compose.env
scope_file=$state_dir/scope
credentials_file=$state_dir/credentials
demo_credentials_file=$state_dir/demo-credentials

compose() {
  docker compose \
    --project-name hyfens-local-dashboard \
    --env-file "$env_file" \
    --file "$repo_dir/deploy/p2/docker-compose.yml" \
    --file "$repo_dir/deploy/p2/docker-compose.dashboard.yml" \
    "$@"
}

random_hex() {
  od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
}

random_base64() {
  openssl rand -base64 32 | tr -d '\n'
}

ensure_state_dir() {
  mkdir -p "$state_dir"
  chmod 700 "$state_dir"
}

ensure_compose_env() {
  [ -f "$env_file" ] && return 0

  temporary=$(mktemp "$state_dir/.compose.env.XXXXXX")
  {
    printf '%s\n' "HYFENS_POSTGRES_PASSWORD=$(random_hex)"
    printf '%s\n' "HYFENS_S3_ACCESS_KEY=local$(random_hex | cut -c1-20)"
    printf '%s\n' "HYFENS_S3_SECRET_KEY=$(random_hex)"
    printf '%s\n' 'HYFENS_S3_BUCKET=hyfens-artifacts'
    printf '%s\n' 'HYFENS_S3_REGION=us-east-1'
    printf '%s\n' 'HYFENS_BIND_ADDRESS=127.0.0.1'
    printf '%s\n' 'HYFENS_POSTGRES_PORT=55433'
    printf '%s\n' 'HYFENS_S3_PORT=59000'
    printf '%s\n' 'HYFENS_CONTROL_PLANE_PORT=18082'
    printf '%s\n' 'HYFENS_DASHBOARD_PORT=18083'
    printf '%s\n' 'HYFENS_DASHBOARD_API_BASE=http://127.0.0.1:18082/'
    printf '%s\n' 'HYFENS_DISCOVERY_PRODUCT=hyfens'
    printf '%s\n' 'HYFENS_DISCOVERY_PRODUCT_VERSION=local'
    printf '%s\n' 'HYFENS_DISCOVERY_API_VERSION=v1'
    printf '%s\n' 'HYFENS_AUTH_ISSUER=http://local.hyfens.test'
    printf '%s\n' 'HYFENS_AUTH_AUDIENCE=hyfens-control'
    printf '%s\n' "HYFENS_AUTH_SIGNING_KEY=$(random_base64)"
    printf '%s\n' 'HYFENS_AUTH_SIGNING_KEY_ID=local-auth-1'
    printf '%s\n' 'HYFENS_AUTH_ACCESS_TTL=15m'
    printf '%s\n' 'HYFENS_AUTH_SESSION_TTL=30d'
    printf '%s\n' 'HYFENS_AUTH_CODE_TTL=1m'
    printf '%s\n' 'HYFENS_AUTH_DEVICE_TTL=10m'
    printf '%s\n' 'HYFENS_AUTH_DEVICE_POLL_INTERVAL=5s'
    printf '%s\n' 'HYFENS_AUTH_DEVICE_MAX_ATTEMPTS=30'
    printf '%s\n' 'HYFENS_AUTH_DEVICE_ATTEMPTS_PER_MINUTE=10'
    printf '%s\n' 'HYFENS_AUTH_ALLOWED_REDIRECT_URIS=[]'
    printf '%s\n' 'HYFENS_AUTH_ALLOW_INSECURE_HTTP=true'
    printf '%s\n' 'HYFENS_AUTH_AUTHORIZATION_ENDPOINT=http://127.0.0.1:18083/cli/authorize/'
    printf '%s\n' 'HYFENS_AUTH_DEVICE_VERIFICATION_URI=http://127.0.0.1:18083/device/'
    printf '%s\n' 'HYFENS_WEB_ORIGINS=http://127.0.0.1:18083,http://localhost:18083,http://127.0.0.1:18084,http://localhost:18084,http://127.0.0.1:18086,http://localhost:18086'
    printf '%s\n' 'HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID='
    printf '%s\n' 'HYFENS_PLATFORM_ADMIN_EMAILS='
  } >"$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$env_file"
}

ensure_demo_platform_config() {
  current=$(read_value HYFENS_PLATFORM_ADMIN_EMAILS "$env_file")
  if [ "$current" = 'admin@auvanaventures.com' ]; then
    unset current
    return 0
  fi

  temporary=$(mktemp "$state_dir/.compose.env.XXXXXX")
  awk -F= '
    $1 == "HYFENS_PLATFORM_ADMIN_EMAILS" {
      print "HYFENS_PLATFORM_ADMIN_EMAILS=admin@auvanaventures.com"
      found=1
      next
    }
    {print}
    END {
      if (!found) print "HYFENS_PLATFORM_ADMIN_EMAILS=admin@auvanaventures.com"
    }
  ' "$env_file" >"$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$env_file"
  unset current
}

read_value() {
  key=$1
  file=$2
  awk -F= -v wanted="$key" '$1 == wanted {sub(/^[^=]*=/, ""); print; exit}' "$file"
}

normalize_compose_env() {
  [ -f "$env_file" ] || return 0

  # Early local versions of this helper wrote seconds as bare integers. Keep
  # their generated secrets and database password, but repair only those
  # non-secret duration fields so an existing local volume remains usable.
  needs_duration_fix=false
  [ "$(read_value HYFENS_AUTH_ACCESS_TTL "$env_file")" = '900' ] && needs_duration_fix=true
  [ "$(read_value HYFENS_AUTH_SESSION_TTL "$env_file")" = '2592000' ] && needs_duration_fix=true
  needs_local_transport=$(read_value HYFENS_AUTH_ALLOW_INSECURE_HTTP "$env_file")
  if [ "$needs_duration_fix" = false ] && [ "$needs_local_transport" = 'true' ]; then
    unset needs_duration_fix needs_local_transport
    return 0
  fi

  temporary=$(mktemp "$state_dir/.compose.env.XXXXXX")
  awk -F= '
    $1 == "HYFENS_AUTH_ACCESS_TTL" && $2 == "900" {print "HYFENS_AUTH_ACCESS_TTL=15m"; next}
    $1 == "HYFENS_AUTH_SESSION_TTL" && $2 == "2592000" {print "HYFENS_AUTH_SESSION_TTL=30d"; next}
    $1 == "HYFENS_AUTH_CODE_TTL" {print "HYFENS_AUTH_CODE_TTL=1m"; next}
    $1 == "HYFENS_AUTH_DEVICE_TTL" {print "HYFENS_AUTH_DEVICE_TTL=10m"; next}
    $1 == "HYFENS_AUTH_DEVICE_POLL_INTERVAL" {print "HYFENS_AUTH_DEVICE_POLL_INTERVAL=5s"; next}
    $1 == "HYFENS_AUTH_ALLOW_INSECURE_HTTP" {print "HYFENS_AUTH_ALLOW_INSECURE_HTTP=true"; found=1; next}
    {print}
    END {if (!found) print "HYFENS_AUTH_ALLOW_INSECURE_HTTP=true"}
  ' "$env_file" >"$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$env_file"
  unset needs_duration_fix needs_local_transport
}

ensure_scope() {
  [ -f "$scope_file" ] && return 0

  if ! bootstrap_output=$(compose run --rm --no-deps control-plane \
    --bootstrap \
    --bootstrap-only \
    --organization "Local Hyfens" \
    --application "com.hyfens.local" \
    --platform "local-platform" \
    --environment "development"); then
    unset bootstrap_output
    echo 'Local scope bootstrap failed; inspect the control-plane logs.' >&2
    return 1
  fi

  organization_id=$(printf '%s\n' "$bootstrap_output" | awk -F= '$1 == "organization_id" {print $2; exit}')
  application_id=$(printf '%s\n' "$bootstrap_output" | awk -F= '$1 == "application_id" {print $2; exit}')
  environment_id=$(printf '%s\n' "$bootstrap_output" | awk -F= '$1 == "environment_id" {print $2; exit}')
  unset bootstrap_output

  if [ -z "$organization_id" ] || [ -z "$application_id" ] || [ -z "$environment_id" ]; then
    echo 'Local scope bootstrap returned no usable scope IDs.' >&2
    return 1
  fi

  temporary=$(mktemp "$state_dir/.scope.XXXXXX")
  {
    printf '%s\n' "ORGANIZATION_ID=$organization_id"
    printf '%s\n' "APPLICATION_ID=$application_id"
    printf '%s\n' "ENVIRONMENT_ID=$environment_id"
  } >"$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$scope_file"
  unset organization_id application_id environment_id
}

ensure_public_registration() {
  organization_id=$(read_value ORGANIZATION_ID "$scope_file")
  configured_organization_id=$(read_value HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID "$env_file")
  if [ "$configured_organization_id" = "$organization_id" ]; then
    unset organization_id configured_organization_id
    return 0
  fi

  temporary=$(mktemp "$state_dir/.compose.env.XXXXXX")
  awk -F= -v organization_id="$organization_id" '
    $1 == "HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID" {
      print "HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID=" organization_id
      found=1
      next
    }
    {print}
    END {
      if (!found) print "HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID=" organization_id
    }
  ' "$env_file" >"$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$env_file"
  unset organization_id configured_organization_id

  # The first scope bootstrap runs before this value exists. Recreate only
  # control-plane so the running process receives the generated tenant while
  # PostgreSQL/object-store volumes and seeded credentials remain untouched.
  compose up --detach --no-deps --force-recreate control-plane
  wait_for_control_plane
}

ensure_credentials() {
  [ -f "$credentials_file" ] && return 0

  organization_id=$(read_value ORGANIZATION_ID "$scope_file")
  application_id=$(read_value APPLICATION_ID "$scope_file")
  environment_id=$(read_value ENVIRONMENT_ID "$scope_file")
  owner_password=$(random_hex)
  admin_password=$(random_hex)

  temporary=$(mktemp "$state_dir/.credentials.XXXXXX")
  {
    printf '%s\n' "ORGANIZATION_ID=$organization_id"
    printf '%s\n' "APPLICATION_ID=$application_id"
    printf '%s\n' "ENVIRONMENT_ID=$environment_id"
    printf '%s\n' 'OWNER_EMAIL=owner@local.hyfens.test'
    printf '%s\n' "OWNER_PASSWORD=$owner_password"
    printf '%s\n' 'ADMIN_EMAIL=admin@local.hyfens.test'
    printf '%s\n' "ADMIN_PASSWORD=$admin_password"
  } >"$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$credentials_file"
  unset organization_id application_id environment_id owner_password admin_password
}

wait_for_control_plane() {
  api_base=$(read_value HYFENS_DASHBOARD_API_BASE "$env_file")
  attempt=0
  while [ "$attempt" -lt 60 ]; do
    if curl --fail --silent --show-error "${api_base}healthz" >/dev/null 2>&1; then
      unset api_base attempt
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done
  unset api_base attempt
  echo 'Local control plane did not become healthy.' >&2
  return 1
}

seed_users() {
  wait_for_control_plane
  ensure_scope
  ensure_public_registration
  ensure_credentials

  organization_id=$(read_value ORGANIZATION_ID "$scope_file")
  application_id=$(read_value APPLICATION_ID "$scope_file")
  environment_id=$(read_value ENVIRONMENT_ID "$scope_file")
  owner_email=$(read_value OWNER_EMAIL "$credentials_file")
  owner_password=$(read_value OWNER_PASSWORD "$credentials_file")
  admin_email=$(read_value ADMIN_EMAIL "$credentials_file")
  admin_password=$(read_value ADMIN_PASSWORD "$credentials_file")

  if ! printf '%s\n' "$owner_password" | compose run --rm --no-deps control-plane \
    --bootstrap-owner \
    --password-stdin \
    --organization-id "$organization_id" \
    --application-id "$application_id" \
    --environment-id "$environment_id" \
    --email "$owner_email" \
    --profile super-admin >/dev/null; then
    echo 'Local super-admin bootstrap failed.' >&2
    unset organization_id application_id environment_id owner_email owner_password admin_email admin_password
    return 1
  fi

  if ! printf '%s\n' "$admin_password" | compose run --rm --no-deps control-plane \
    --bootstrap-admin \
    --password-stdin \
    --organization-id "$organization_id" \
    --application-id "$application_id" \
    --environment-id "$environment_id" \
    --email "$admin_email" \
    --profile content-admin >/dev/null; then
    echo 'Local content-admin bootstrap failed.' >&2
    unset organization_id application_id environment_id owner_email owner_password admin_email admin_password
    return 1
  fi

  unset organization_id application_id environment_id owner_email owner_password admin_email admin_password
  echo 'Local dashboard users are ready. Use: sh scripts/local-dashboard.sh credentials'
}

ensure_demo_credentials() {
  [ -f "$demo_credentials_file" ] && return 0

  demo_password=${HYFENS_DEMO_OWNER_PASSWORD:-}
  if [ -z "$demo_password" ]; then
    demo_password=$(random_hex)
  fi
  if [ "${#demo_password}" -lt 12 ]; then
    echo 'HYFENS_DEMO_OWNER_PASSWORD must contain at least 12 characters.' >&2
    unset demo_password
    return 1
  fi

  temporary=$(mktemp "$state_dir/.demo-credentials.XXXXXX")
  {
    printf '%s\n' 'ORGANIZATION_ID=org_auvana_ventures'
    printf '%s\n' 'APPLICATION_ID=app_auvana_demo'
    printf '%s\n' 'ENVIRONMENT_ID=env_auvana_development'
    printf '%s\n' 'OWNER_EMAIL=admin@auvanaventures.com'
    printf '%s\n' "OWNER_PASSWORD=$demo_password"
    printf '%s\n' 'OWNER_PROFILE=super-admin'
  } >"$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$demo_credentials_file"
  unset demo_password
}

seed_demo_user() {
  wait_for_control_plane
  ensure_demo_credentials
  demo_password=$(read_value OWNER_PASSWORD "$demo_credentials_file")
  if [ -z "$demo_password" ]; then
    echo 'The local demo credential file does not contain an owner password.' >&2
    unset demo_password
    return 1
  fi
  if ! printf '%s\n' "$demo_password" | compose run --rm --no-deps control-plane \
    --seed-demo --password-stdin >/dev/null; then
    echo 'Auvana local demo seed failed; inspect the control-plane logs.' >&2
    unset demo_password
    return 1
  fi
  unset demo_password
  echo 'Auvana local demo account is ready. Use: sh scripts/local-dashboard.sh demo-credentials'
}

usage() {
  echo 'Usage: sh scripts/local-dashboard.sh {up|seed|demo|seed-demo|credentials|demo-credentials|status|down}' >&2
  exit 2
}

ensure_state_dir
ensure_compose_env
normalize_compose_env

command_name=${1:-up}
case "$command_name" in
  up)
    compose up --detach --build
    seed_users
    ;;
  seed)
    seed_users
    ;;
  demo)
    ensure_demo_platform_config
    compose up --detach --build --force-recreate
    seed_demo_user
    ;;
  seed-demo)
    ensure_demo_platform_config
    compose up --detach --build --force-recreate
    seed_demo_user
    ;;
  credentials)
    if [ ! -f "$credentials_file" ]; then
      echo 'No local credentials exist yet. Run: sh scripts/local-dashboard.sh up' >&2
      exit 1
    fi
    cat "$credentials_file"
    ;;
  demo-credentials)
    if [ ! -f "$demo_credentials_file" ]; then
      echo 'No Auvana demo credentials exist yet. Run: sh scripts/local-dashboard.sh demo' >&2
      exit 1
    fi
    cat "$demo_credentials_file"
    ;;
  status)
    compose ps
    ;;
  down)
    compose down
    ;;
  *)
    usage
    ;;
esac
