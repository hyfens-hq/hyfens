#!/usr/bin/env bash
set -euo pipefail

# Canonical, disposable PostgreSQL + object-store recovery rehearsal. It
# requires HYFENS_ALLOW_RESTORE=1 because it intentionally destroys its own
# unique Compose volumes before restoring the captured backups.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="${HYFENS_DR_COMPOSE_FILE:-$repo_root/deploy/p2/docker-compose.yml}"
tombstone_rehearsal="${HYFENS_DR_TOMBSTONE_REHEARSAL:-0}"
managed_backup_id="${HYFENS_DR_MANAGED_BACKUP_ID:-}"
managed_env_file=/etc/hyfens/public-control-plane-dev.env
managed_aws_image='amazon/aws-cli:2.27.41@sha256:bc6b7bba44ce38f9604ede49c584824af919047ea03fbcc7c7610671fdef95d8'
managed_project=''
default_project=hyfens-p2-dr-${PPID}-$$
if [[ "$tombstone_rehearsal" == 1 ]]; then
  default_project=hyfens-dr-tombstone-${PPID}-$$
fi
if [[ -n "$managed_backup_id" ]]; then
  managed_project="hyfens-dr-managed-$(printf '%s' "$managed_backup_id" | tr '[:upper:]' '[:lower:]')"
  default_project="$managed_project"
fi
project="${HYFENS_DR_PROJECT:-$default_project}"
control_port="${HYFENS_DR_CONTROL_PORT:-18084}"
postgres_port="${HYFENS_DR_POSTGRES_PORT:-55443}"
object_port="${HYFENS_DR_OBJECT_PORT:-59010}"
endpoint="http://127.0.0.1:${control_port}"
work="$(mktemp -d "${TMPDIR:-/tmp}/hyfens-dr.XXXXXX")"
: >"$work/timings.txt"
compose=(docker compose -p "$project" -f "$compose_file")
started=0

if [[ "${HYFENS_ALLOW_RESTORE:-}" != 1 ]]; then
  echo 'Set HYFENS_ALLOW_RESTORE=1 only for this disposable recovery rehearsal.' >&2
  exit 2
fi
if [[ "$tombstone_rehearsal" != 0 && "$tombstone_rehearsal" != 1 ]]; then
  echo 'HYFENS_DR_TOMBSTONE_REHEARSAL must be 0 or 1.' >&2
  exit 2
fi
if [[ "$tombstone_rehearsal" == 1 && "${HYFENS_AUTH_ALLOW_INSECURE_HTTP:-}" != true ]]; then
  echo 'Set HYFENS_AUTH_ALLOW_INSECURE_HTTP=true only for the loopback tombstone rehearsal.' >&2
  exit 2
fi
if [[ "$tombstone_rehearsal" == 1 && -n "${HYFENS_DR_COMPOSE_FILE:-}" ]]; then
  echo 'The tombstone rehearsal uses the repository disposable Compose file and does not accept HYFENS_DR_COMPOSE_FILE.' >&2
  exit 2
fi
if [[ "$tombstone_rehearsal" == 1 && -z "$managed_backup_id" && ! "$project" =~ ^hyfens-dr-tombstone-[A-Za-z0-9_-]+$ ]]; then
  echo 'HYFENS_DR_PROJECT must start with hyfens-dr-tombstone- for the extended rehearsal.' >&2
  exit 2
fi
if [[ -n "$managed_backup_id" && "$tombstone_rehearsal" != 1 ]]; then
  echo 'HYFENS_DR_MANAGED_BACKUP_ID requires HYFENS_DR_TOMBSTONE_REHEARSAL=1.' >&2
  exit 2
fi
if [[ -n "$managed_backup_id" && -n "${HYFENS_DR_COMPOSE_FILE:-}" ]]; then
  echo 'The managed rehearsal uses the repository disposable Compose file and does not accept HYFENS_DR_COMPOSE_FILE.' >&2
  exit 2
fi
if [[ -n "$managed_backup_id" && "$project" != "$managed_project" ]]; then
  echo 'HYFENS_DR_PROJECT must be the lowercase derived managed backup project name.' >&2
  exit 2
fi

cleanup() {
  set +e
  if [[ "$started" == 1 ]]; then
    "${compose[@]}" down -v --remove-orphans >/dev/null 2>&1
  fi
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 2
  }
}
require_command docker
require_command curl
require_command python3
require_command shasum

read_managed_setting() {
  local name="$1" value
  value="$(sed -n "s/^[[:space:]]*$name[[:space:]]*=[[:space:]]*//p" "$managed_env_file" | head -n 1)"
  [[ -n "$value" && "$value" != *[[:space:]]* ]] || {
    echo "managed backup setting is missing or contains whitespace: $name" >&2
    exit 2
  }
  printf '%s' "$value"
}

if [[ -n "$managed_backup_id" ]]; then
  [[ "$(id -u)" == 0 ]] || {
    echo 'managed backup rehearsal must run as root' >&2
    exit 2
  }
  [[ -f "$managed_env_file" ]] || {
    echo 'managed public backup environment is missing' >&2
    exit 2
  }
  managed_destination_endpoint="$(read_managed_setting HYFENS_PUBLIC_BACKUP_DEST_ENDPOINT)"
  managed_destination_bucket="$(read_managed_setting HYFENS_PUBLIC_BACKUP_DEST_BUCKET)"
  managed_destination_account_id="$(read_managed_setting HYFENS_PUBLIC_BACKUP_DEST_ACCOUNT_ID)"
  managed_destination_access_key="$(read_managed_setting HYFENS_PUBLIC_BACKUP_DEST_ACCESS_KEY_ID)"
  managed_destination_secret_key="$(read_managed_setting HYFENS_PUBLIC_BACKUP_DEST_SECRET_ACCESS_KEY)"
  managed_max_age="$(read_managed_setting HYFENS_PUBLIC_BACKUP_MAX_AGE_SECONDS)"
  [[ "$managed_destination_account_id" =~ ^[a-f0-9]{32}$ ]] || {
    echo 'managed backup destination account ID is invalid' >&2
    exit 2
  }
  [[ "$managed_destination_endpoint" == "https://${managed_destination_account_id}.r2.cloudflarestorage.com" ]] || {
    echo 'managed backup destination endpoint does not match its account' >&2
    exit 2
  }
  [[ "$managed_destination_bucket" == hyfens-cloud-backups ]] || {
    echo 'managed backup destination bucket is not approved' >&2
    exit 2
  }
  [[ "$managed_backup_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || {
    echo 'HYFENS_DR_MANAGED_BACKUP_ID is invalid' >&2
    exit 2
  }
  [[ "$managed_max_age" =~ ^[1-9][0-9]*$ ]] || {
    echo 'managed backup freshness age is invalid' >&2
    exit 2
  }
fi

if [[ "$tombstone_rehearsal" == 1 ]]; then
  # Never inherit operator credentials into the extended fixture. All state
  # is intentionally local to this run and is removed by the project-scoped
  # cleanup trap.
  export HYFENS_POSTGRES_PASSWORD="local-dr-postgres-$(date -u +%s)-$$"
  export HYFENS_S3_ACCESS_KEY=hyfens-dr
  export HYFENS_S3_SECRET_KEY="local-dr-object-$(date -u +%s)-$$"
  export HYFENS_S3_BUCKET=hyfens-dr-artifacts
else
  export HYFENS_POSTGRES_PASSWORD="${HYFENS_POSTGRES_PASSWORD:-local-dr-postgres-$(date +%s)}"
  export HYFENS_S3_ACCESS_KEY="${HYFENS_S3_ACCESS_KEY:-hyfens-dr}"
  export HYFENS_S3_SECRET_KEY="${HYFENS_S3_SECRET_KEY:-local-dr-object-$(date +%s)}"
  export HYFENS_S3_BUCKET="${HYFENS_S3_BUCKET:-hyfens-dr-artifacts}"
fi
export HYFENS_CONTROL_PLANE_PORT="$control_port"
export HYFENS_POSTGRES_PORT="$postgres_port"
export HYFENS_S3_PORT="$object_port"
if [[ "$tombstone_rehearsal" == 1 ]]; then
  # These values are generated or fixed only for this disposable run. They
  # make the real Cloud deletion path available without importing production
  # provider or authentication material into the fixture.
  export HYFENS_DEPLOYMENT_MODEL=cloud
  export HYFENS_DELETION_GRACE_PERIOD=1d
  export HYFENS_DELETION_BUSINESS_TIMEZONE=UTC
  export HYFENS_DELETION_HOLIDAYS=
  export HYFENS_DELETION_TEST_CLOCK=1
  export RAZORPAY_MODE=test
  export HYFENS_BIND_ADDRESS=127.0.0.1
  export HYFENS_AUTH_VERIFY_KEYS=
  export HYFENS_PLATFORM_ADMIN_EMAILS=
  export HYFENS_AUTH_SIGNING_KEY="$(python3 - <<'PY'
import base64
import secrets
print(base64.b64encode(secrets.token_bytes(32)).decode())
PY
)"
  if [[ -n "$("${compose[@]}" ps -aq 2>/dev/null || true)" ]]; then
    echo 'The disposable tombstone Compose project already exists; choose a new HYFENS_DR_PROJECT.' >&2
    exit 2
  fi
fi
if [[ -n "$managed_backup_id" ]]; then
  export HYFENS_CONTROL_PLANE_IMAGE="${HYFENS_CONTROL_PLANE_IMAGE:-hyfens-public-control-plane:current}"
  managed_destination_aws_env="$work/managed-destination-aws.env"
  managed_object_store_aws_env="$work/managed-object-store-aws.env"
  umask 077
  {
    printf 'AWS_ACCESS_KEY_ID=%s\n' "$managed_destination_access_key"
    printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$managed_destination_secret_key"
    printf 'AWS_DEFAULT_REGION=auto\n'
    printf 'AWS_REGION=auto\n'
    printf 'AWS_PAGER=\n'
    printf 'AWS_EC2_METADATA_DISABLED=true\n'
  } >"$managed_destination_aws_env"
  {
    printf 'AWS_ACCESS_KEY_ID=%s\n' "$HYFENS_S3_ACCESS_KEY"
    printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$HYFENS_S3_SECRET_KEY"
    printf 'AWS_DEFAULT_REGION=us-east-1\n'
    printf 'AWS_REGION=us-east-1\n'
    printf 'AWS_PAGER=\n'
    printf 'AWS_EC2_METADATA_DISABLED=true\n'
  } >"$managed_object_store_aws_env"
  chmod 600 "$managed_destination_aws_env" "$managed_object_store_aws_env"
fi
db_url="postgresql://hyfens:${HYFENS_POSTGRES_PASSWORD}@127.0.0.1:${postgres_port}/hyfens?sslmode=disable"
network="$project"_default

now_ms() {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}
record_timing() {
  printf '%s=%s\n' "$1" "$(($3 - $2))" >>"$work/timings.txt"
}
wait_status() {
  local path="$1" expected="$2" attempts="${3:-60}" status
  for _ in $(seq 1 "$attempts"); do
    status="$(curl -sS -o "$work/response" -w '%{http_code}' "$endpoint$path" || true)"
    [[ "$status" == "$expected" ]] && return 0
    sleep 1
  done
  echo "timeout waiting for $path=$expected (last=$status)" >&2
  cat "$work/response" >&2 || true
  return 1
}
wait_service_healthy() {
  local service="$1" id status
  id="$("${compose[@]}" ps -q "$service")"
  for _ in $(seq 1 60); do
    status="$(docker inspect -f '{{.State.Health.Status}}' "$id" 2>/dev/null || true)"
    [[ "$status" == healthy ]] && return 0
    sleep 1
  done
  echo "$service did not become healthy" >&2
  docker inspect "$id" >&2 || true
  return 1
}
api_json() {
  local method="$1" path="$2" token="$3" body="$4" response="$5"
  local args=(-sS -o "$response" -w '%{http_code}' -X "$method" "$endpoint$path")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  if [[ "$method" == POST || "$method" == PUT ]]; then
    args+=(-H "Idempotency-Key: dr-$(printf '%s' "$path" | shasum -a 256 | awk '{print $1}')")
  fi
  if [[ "$body" != - ]]; then
    args+=(-H 'Content-Type: application/json' --data-binary "@$body")
  fi
  curl "${args[@]}"
}
api_artifact() {
  curl -sS -o "$4" -w '%{http_code}' -X PUT "$endpoint$1" \
    -H "Authorization: Bearer $2" \
    -H "Idempotency-Key: dr-artifact-$(printf '%s' "$1" | shasum -a 256 | awk '{print $1}')" \
    -H 'Content-Type: application/octet-stream' --data-binary "@$3"
}
assert_status() {
  local actual="$1" expected="$2" operation="$3"
  case ",$expected," in *",$actual,"*) return 0;; esac
  echo "$operation failed with HTTP $actual" >&2
  cat "$work/response" >&2 || true
  exit 1
}
json_value() {
  python3 - "$1" "$2" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
for part in sys.argv[2].split('.'):
    value = value[part]
print(value)
PY
}
assert_json() {
  local actual
  actual="$(json_value "$1" "$2")"
  [[ "$actual" == "$3" ]] || { echo "expected $2=$3, got $actual" >&2; cat "$1" >&2; exit 1; }
}
valid_fixture_id() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || {
    echo 'fixture identifier contains unsupported characters' >&2
    exit 1
  }
}
db_query() {
  "${compose[@]}" exec -T postgres psql \
    -U hyfens -d hyfens -At -v ON_ERROR_STOP=1 -c "$1"
}
dart_fixture() {
  "${compose[@]}" run --rm --no-deps \
    --user 0:0 \
    --volume "$work:/dr-work:rw" \
    --entrypoint dart control-plane \
    run /opt/hyfens/experiments/patch_loading/bin/ha_make_artifact.dart "$@"
}

managed_aws() {
  docker run --rm --network bridge --log-driver none \
    --volume "$work:/backup:rw" \
    --user 0:0 \
    --env-file "$managed_destination_aws_env" \
    --entrypoint /usr/local/bin/aws \
    "$managed_aws_image" "$@" \
    --endpoint-url "$managed_destination_endpoint" --region auto
}

managed_object_store_aws() {
  docker run --rm --network "$network" --log-driver none \
    --volume "$work:/backup:ro" \
    --user 0:0 \
    --env-file "$managed_object_store_aws_env" \
    --entrypoint /usr/local/bin/aws \
    "$managed_aws_image" "$@" \
    --endpoint-url http://object-store:9000/ --region us-east-1
}

verify_managed_download() {
  python3 - "$work" "$managed_backup_id" "$managed_max_age" <<'PY'
import datetime as dt
import hashlib
import json
import os
import re
import sys

work, expected_id, max_age_text = sys.argv[1:]
try:
    max_age = int(max_age_text)
    with open(os.path.join(work, 'managed-manifest.json'), encoding='utf-8') as source:
        manifest = json.load(source)
    if (manifest.get('schema_version') != 1 or
        manifest.get('backup_id') != expected_id or
        manifest.get('policy_prefix') != 'operational/' or
        manifest.get('retention_days') != 30 or
        manifest.get('consistency') != 'operator_quiesced_pair_required'):
        raise ValueError('manifest identity')
    created_at = manifest.get('created_at')
    if not isinstance(created_at, str) or not re.fullmatch(
        r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z',
        created_at,
    ):
        raise ValueError('manifest timestamp')
    created = dt.datetime.fromisoformat(created_at[:-1] + '+00:00')
    age = int((dt.datetime.now(dt.timezone.utc) - created).total_seconds())
    if age < 0 or age > max_age:
        raise ValueError('manifest freshness')

    database = manifest.get('database')
    objects = manifest.get('objects')
    expected_database_key = f'operational/public-control-plane/{expected_id}/postgres.dump'
    expected_objects_key = f'operational/public-control-plane/{expected_id}/objects/manifest.json'
    if (not isinstance(database, dict) or database.get('key') != expected_database_key or
        not isinstance(objects, dict) or objects.get('manifest_key') != expected_objects_key):
        raise ValueError('manifest keys')

    def digest(path):
        value = hashlib.sha256()
        with open(path, 'rb') as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b''):
                value.update(chunk)
        return value.hexdigest()

    database_path = os.path.join(work, 'managed-postgres.dump')
    objects_manifest_path = os.path.join(work, 'managed-objects-manifest.json')
    if database.get('sha256') != 'sha256:' + digest(database_path):
        raise ValueError('database checksum')
    if objects.get('manifest_sha256') != 'sha256:' + digest(objects_manifest_path):
        raise ValueError('object manifest checksum')
    if (database.get('size_bytes') != os.path.getsize(database_path) or
        objects.get('manifest_size_bytes') != os.path.getsize(objects_manifest_path)):
        raise ValueError('backup sizes')

    with open(objects_manifest_path, encoding='utf-8') as source:
        object_manifest = json.load(source)
    if (object_manifest.get('schema_version') != 1 or
        not isinstance(object_manifest.get('objects'), list)):
        raise ValueError('object manifest')
    expected = {}
    for item in object_manifest['objects']:
        key = item.get('key')
        sha = item.get('sha256')
        size = item.get('size_bytes')
        if (not isinstance(key, str) or not re.fullmatch(r'[A-Za-z0-9._/-]+', key) or
            key.startswith('../') or key == '..' or
            any(part in ('', '.', '..') for part in key.split('/')) or
            not isinstance(sha, str) or not re.fullmatch(r'sha256:[0-9a-f]{64}', sha) or
            not isinstance(size, int) or size < 0 or key in expected):
            raise ValueError('object manifest entry')
        expected[key] = (sha[7:], size)
    actual = {}
    object_root = os.path.join(work, 'managed-objects')
    for directory, directories, files in os.walk(object_root):
        directories.sort()
        for name in sorted(files):
            path = os.path.join(directory, name)
            if os.path.islink(path) or not os.path.isfile(path):
                raise ValueError('object file')
            key = os.path.relpath(path, object_root).replace(os.sep, '/')
            actual[key] = (digest(path), os.path.getsize(path))
    if actual != expected:
        raise ValueError('object checksum')
    if objects.get('count') != len(expected):
        raise ValueError('object count')
    print('managed_backup_manifest=PASS')
    print(f'managed_backup_age_seconds={age}')
    print(f'managed_restored_object_count={len(expected)}')
except (KeyError, TypeError, ValueError, json.JSONDecodeError, OSError):
    raise SystemExit('managed backup manifest validation failed')
PY
}

restore_managed_pair() {
  local prefix="operational/public-control-plane/$managed_backup_id"
  install -d -m 0700 "$work/managed-objects"
  managed_aws s3 cp "s3://$managed_destination_bucket/$prefix/postgres.dump" \
    /backup/managed-postgres.dump --only-show-errors \
    >"$work/aws.stdout" 2>"$work/aws.stderr" || {
      echo 'managed backup database download failed' >&2
      exit 1
    }
  managed_aws s3 cp "s3://$managed_destination_bucket/$prefix/objects/manifest.json" \
    /backup/managed-objects-manifest.json --only-show-errors \
    >>"$work/aws.stdout" 2>>"$work/aws.stderr" || {
      echo 'managed backup object manifest download failed' >&2
      exit 1
    }
  managed_aws s3 cp "s3://$managed_destination_bucket/$prefix/manifest.json" \
    /backup/managed-manifest.json --only-show-errors \
    >>"$work/aws.stdout" 2>>"$work/aws.stderr" || {
      echo 'managed backup manifest download failed' >&2
      exit 1
    }
  managed_aws s3 sync "s3://$managed_destination_bucket/$prefix/objects/data/" \
    /backup/managed-objects --only-show-errors \
    >>"$work/aws.stdout" 2>>"$work/aws.stderr" || {
      echo 'managed backup object download failed' >&2
      exit 1
    }
  verify_managed_download
  cat "$work/managed-postgres.dump" | "${compose[@]}" exec -T postgres \
    pg_restore --list >/dev/null 2>/dev/null || {
    echo 'managed PostgreSQL dump failed pg_restore validation' >&2
    exit 1
  }
  cat "$work/managed-postgres.dump" | "${compose[@]}" exec -T postgres \
    pg_restore --exit-on-error --clean --if-exists --no-owner \
    -U hyfens -d hyfens >/dev/null 2>"$work/postgres-restore.stderr" || {
      echo 'managed PostgreSQL restore failed' >&2
      exit 1
    }
  managed_object_store_aws s3 sync /backup/managed-objects \
    "s3://$HYFENS_S3_BUCKET" --only-show-errors \
    >"$work/object-restore.stdout" 2>"$work/object-restore.stderr" || {
      echo 'managed object-store restore failed' >&2
      exit 1
    }
  echo 'managed_backup_restore=PASS'
}

echo "dr_project=$project"
echo "dr_endpoint=$endpoint"
start="$(now_ms)"
"${compose[@]}" config >/dev/null
started=1
if [[ -n "$managed_backup_id" ]]; then
  "${compose[@]}" up -d --no-build postgres object-store >/dev/null
else
  "${compose[@]}" up -d --build >/dev/null
fi
record_timing compose_up "$start" "$(now_ms)"
if [[ -n "$managed_backup_id" ]]; then
  wait_service_healthy postgres
  wait_service_healthy object-store
  "${compose[@]}" run --rm object-bootstrap >/dev/null
  managed_restore_start="$(now_ms)"
  restore_managed_pair
  record_timing managed_pair_restore "$managed_restore_start" "$(now_ms)"
  "${compose[@]}" up -d --no-build control-plane >/dev/null
  wait_status /healthz 200
  wait_status /readyz 200
else
  wait_status /healthz 200
  wait_status /readyz 200
fi
"${compose[@]}" run --rm control-plane --bootstrap --bootstrap-only \
  --application dr_fixture_app --platform android-arm64-release \
  --environment development >"$work/bootstrap.txt"

python3 - "$work/bootstrap.txt" "$work/credentials.env" <<'PY'
import shlex, sys
required = {'organization_id', 'application_id', 'environment_id', 'control_token', 'delivery_token'}
values = {}
for line in open(sys.argv[1]):
    if '=' in line:
        key, value = line.rstrip('\n').split('=', 1)
        if key in required: values[key] = value
if required - values.keys(): raise SystemExit('bootstrap output is incomplete')
with open(sys.argv[2], 'w') as out:
    for key in sorted(values): out.write(f'{key}={shlex.quote(values[key])}\n')
PY
# shellcheck disable=SC1090
source "$work/credentials.env"
primary_organization_id="$organization_id"
primary_application_id="$application_id"
primary_environment_id="$environment_id"
primary_control_token="$control_token"
primary_delivery_token="$delivery_token"

if [[ "$tombstone_rehearsal" == 1 ]]; then
  owner_email="dr-owner-${PPID}-$$@example.invalid"
  owner_password="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(24))
PY
)"
  printf '%s\n' "$owner_password" | "${compose[@]}" run --rm control-plane \
    --bootstrap-owner \
    --organization-id "$primary_organization_id" \
    --application-id "$primary_application_id" \
    --environment-id "$primary_environment_id" \
    --email "$owner_email" \
    --password-stdin \
    --profile dr-owner >"$work/owner-bootstrap.txt"

  "${compose[@]}" run --rm control-plane --bootstrap --bootstrap-only \
    --organization 'DR shared-object fixture' \
    --application dr_fixture_app \
    --platform android-arm64-release \
    --environment development >"$work/shared-bootstrap.txt"
  python3 - "$work/shared-bootstrap.txt" "$work/shared-credentials.env" <<'PY'
import shlex, sys
required = {'organization_id', 'application_id', 'environment_id', 'control_token', 'delivery_token'}
values = {}
for line in open(sys.argv[1]):
    if '=' in line:
        key, value = line.rstrip('\n').split('=', 1)
        if key in required: values[key] = value
if required - values.keys(): raise SystemExit('shared bootstrap output is incomplete')
with open(sys.argv[2], 'w') as out:
    for key in sorted(values): out.write(f'{key}={shlex.quote(values[key])}\n')
PY
  # shellcheck disable=SC1090
  source "$work/shared-credentials.env"
  shared_organization_id="$organization_id"
  shared_application_id="$application_id"
  shared_environment_id="$environment_id"
  shared_control_token="$control_token"
  shared_delivery_token="$delivery_token"
  organization_id="$primary_organization_id"
  application_id="$primary_application_id"
  environment_id="$primary_environment_id"
  control_token="$primary_control_token"
  delivery_token="$primary_delivery_token"
fi
for fixture_id in "$organization_id" "$application_id" "$environment_id"; do
  valid_fixture_id "$fixture_id"
done
if [[ "$tombstone_rehearsal" == 1 ]]; then
  for fixture_id in "$shared_organization_id" "$shared_application_id" "$shared_environment_id"; do
    valid_fixture_id "$fixture_id"
  done
fi

dart_fixture --public-key-only true --public-key-output /dr-work/public-key.hex
public_key_b64="$(python3 - "$work/public-key.hex" <<'PY'
import base64, sys
print(base64.b64encode(bytes.fromhex(open(sys.argv[1]).read().strip())).decode())
PY
)"
python3 - "$work/release.json" "$application_id" "$public_key_b64" <<'PY'
import json, sys
path, app, public_key = sys.argv[1:]
digest = 'sha256:' + ('2' * 64)
json.dump({
  'application_id': app,
  'platform_id': 'plt_android',
  'runtime_application_id': 'dr_fixture_app',
  'runtime_release_id': 'release_dr_1',
  'build_target': 'android-arm64-release',
  'runtime_compatibility_version': 1,
  'patch_format_version': 1,
  'build_fingerprint': digest,
  'capability_authority_digest': digest,
  'function_signature_digest': digest,
  'display_version': '0.1.0-dr',
  'signing_public_keys': {'ha-fixture-key': public_key},
}, open(path, 'w'))
PY
status="$(api_json POST "/v1/organizations/$organization_id/applications/$application_id/releases" "$control_token" "$work/release.json" "$work/response")"
assert_status "$status" '200,201' release_register
release_service_id="$(json_value "$work/response" id)"

dart_fixture --output /dr-work/artifact.bin \
  --application dr_fixture_app --release release_dr_1 --patch patch_dr_1 --sequence 1
artifact_digest="sha256:$(shasum -a 256 "$work/artifact.bin" | awk '{print $1}')"
artifact_size="$(wc -c <"$work/artifact.bin" | tr -d ' ')"
python3 - "$work/patch.json" "$artifact_digest" "$artifact_size" <<'PY'
import json, sys
path, digest, size = sys.argv[1:]
json.dump({
  'runtime_patch_id': 'patch_dr_1',
  'sequence': 1,
  'artifact_id': 'artifact_dr_1',
  'sha256': digest,
  'size_bytes': int(size),
  'signature_key_id': 'ha-fixture-key',
}, open(path, 'w'))
PY
status="$(api_json POST "/v1/organizations/$organization_id/releases/$release_service_id/patches" "$control_token" "$work/patch.json" "$work/response")"
assert_status "$status" '200,201' patch_register
status="$(api_artifact "/v1/organizations/$organization_id/artifacts/artifact_dr_1" "$control_token" "$work/artifact.bin" "$work/response")"
assert_status "$status" '200,201' artifact_upload
python3 - "$work/promotion.json" "$release_service_id" <<'PY'
import json, sys
json.dump({'release_id': sys.argv[2], 'expected_version': 0}, open(sys.argv[1], 'w'))
PY
status="$(api_json POST "/v1/organizations/$organization_id/environments/$environment_id/release-promotions" "$control_token" "$work/promotion.json" "$work/response")"
assert_status "$status" '200' promotion

if [[ "$tombstone_rehearsal" == 1 ]]; then
  python3 - "$work/shared-release.json" "$shared_application_id" "$public_key_b64" <<'PY'
import json, sys
path, app, public_key = sys.argv[1:]
digest = 'sha256:' + ('3' * 64)
json.dump({
  'application_id': app,
  'platform_id': 'plt_android',
  'runtime_application_id': 'dr_fixture_app',
  'runtime_release_id': 'release_dr_1',
  'build_target': 'android-arm64-release',
  'runtime_compatibility_version': 1,
  'patch_format_version': 1,
  'build_fingerprint': digest,
  'capability_authority_digest': digest,
  'function_signature_digest': digest,
  'display_version': '0.1.0-dr-shared',
  'signing_public_keys': {'ha-fixture-key': public_key},
}, open(path, 'w'))
PY
  status="$(api_json POST "/v1/organizations/$shared_organization_id/applications/$shared_application_id/releases" "$shared_control_token" "$work/shared-release.json" "$work/response")"
  assert_status "$status" '200,201' shared_release_register
  shared_release_service_id="$(json_value "$work/response" id)"
  python3 - "$work/shared-patch.json" "$artifact_digest" "$artifact_size" <<'PY'
import json, sys
path, digest, size = sys.argv[1:]
json.dump({
  'runtime_patch_id': 'patch_dr_1',
  'sequence': 1,
  'artifact_id': 'artifact_shared_2',
  'sha256': digest,
  'size_bytes': int(size),
  'signature_key_id': 'ha-fixture-key',
}, open(path, 'w'))
PY
  status="$(api_json POST "/v1/organizations/$shared_organization_id/releases/$shared_release_service_id/patches" "$shared_control_token" "$work/shared-patch.json" "$work/response")"
  assert_status "$status" '200,201' shared_patch_register
  status="$(api_artifact "/v1/organizations/$shared_organization_id/artifacts/artifact_shared_2" "$shared_control_token" "$work/artifact.bin" "$work/response")"
  assert_status "$status" '200,201' shared_artifact_upload
  python3 - "$work/shared-promotion.json" "$shared_release_service_id" <<'PY'
import json, sys
json.dump({'release_id': sys.argv[2], 'expected_version': 0}, open(sys.argv[1], 'w'))
PY
  status="$(api_json POST "/v1/organizations/$shared_organization_id/environments/$shared_environment_id/release-promotions" "$shared_control_token" "$work/shared-promotion.json" "$work/response")"
  assert_status "$status" '200' shared_promotion
fi

cp "$work/artifact.bin" "$work/source-artifact.bin"
source_digest="$artifact_digest"
if [[ -n "$managed_backup_id" ]]; then
  backup_digest="$(shasum -a 256 \
    "$work/managed-manifest.json" "$work/managed-objects-manifest.json" \
    | shasum -a 256 | awk '{print $1}')"
else
  start="$(now_ms)"
  (
    cd "$work"
    HYFENS_DATABASE_URL="$db_url" "$repo_root/scripts/p2-postgres-backup.sh" database.dump
    HYFENS_OBJECT_ENDPOINT='http://object-store:9000/' \
    HYFENS_S3_BUCKET="$HYFENS_S3_BUCKET" \
    HYFENS_S3_ACCESS_KEY="$HYFENS_S3_ACCESS_KEY" \
    HYFENS_S3_SECRET_KEY="$HYFENS_S3_SECRET_KEY" \
    HYFENS_S3_DOCKER_NETWORK="$network" \
    "$repo_root/scripts/p2-object-backup.sh" object-backup
  )
  backup_digest="$(shasum -a 256 "$work/database.dump" "$work/object-backup/manifest.sha256" | shasum -a 256 | awk '{print $1}')"
  record_timing backup_and_manifest "$start" "$(now_ms)"

  "${compose[@]}" down -v --remove-orphans >/dev/null
  started=0
  start="$(now_ms)"
  "${compose[@]}" up -d postgres object-store >/dev/null
  started=1
  wait_service_healthy postgres
  wait_service_healthy object-store
  "${compose[@]}" run --rm object-bootstrap >/dev/null
  (
    cd "$work"
    HYFENS_ALLOW_RESTORE=1 HYFENS_DATABASE_URL="$db_url" \
      "$repo_root/scripts/p2-postgres-restore.sh" database.dump
    HYFENS_ALLOW_RESTORE=1 HYFENS_OBJECT_ENDPOINT='http://object-store:9000/' \
    HYFENS_S3_BUCKET="$HYFENS_S3_BUCKET" \
    HYFENS_S3_ACCESS_KEY="$HYFENS_S3_ACCESS_KEY" \
    HYFENS_S3_SECRET_KEY="$HYFENS_S3_SECRET_KEY" \
    HYFENS_S3_DOCKER_NETWORK="$network" \
      "$repo_root/scripts/p2-object-restore.sh" object-backup
  )
  "${compose[@]}" up -d control-plane >/dev/null
  wait_status /healthz 200
  wait_status /readyz 200
  record_timing destroy_recreate_restore "$start" "$(now_ms)"
fi

status="$(api_json POST "/v1/organizations/$organization_id/artifact-reconciliation" "$control_token" - "$work/response")"
assert_status "$status" '200' reconciliation
assert_json "$work/response" deliverable True
status="$(api_json GET "/v1/organizations/$organization_id/audit" "$control_token" - "$work/response")"
assert_status "$status" '200' audit_export
assert_json "$work/response" verification.valid True
status="$(curl -sS -o "$work/fetched.bin" -w '%{http_code}' \
  -H "Authorization: Bearer $delivery_token" \
  "$endpoint/v1/runtime/artifacts/artifact_dr_1?application_id=$application_id&environment_id=$environment_id")"
assert_status "$status" '200' artifact_fetch
restored_digest="sha256:$(shasum -a 256 "$work/fetched.bin" | awk '{print $1}')"
[[ "$restored_digest" == "$source_digest" ]] || { echo 'restored artifact digest mismatch' >&2; exit 1; }

if [[ "$tombstone_rehearsal" == 1 ]]; then
  python3 - "$work/login.json" "$owner_email" "$owner_password" <<'PY'
import json, sys
path, email, password = sys.argv[1:]
json.dump({'email': email, 'password': password, 'audience': 'customer'}, open(path, 'w'))
PY
  status="$(api_json POST /auth/login '' "$work/login.json" "$work/response")"
  assert_status "$status" '200' owner_login
  assert_json "$work/response" authorization_audience customer
  customer_access_token="$(json_value "$work/response" access_token)"

  python3 - "$work/deletion.json" "$owner_password" <<'PY'
import json, sys
json.dump({'confirmation': 'DELETE', 'password': sys.argv[2]}, open(sys.argv[1], 'w'))
PY
  status="$(api_json POST "/v1/organizations/$organization_id/deletion" "$customer_access_token" "$work/deletion.json" "$work/response")"
  assert_status "$status" '202' organization_deletion_request
  assert_json "$work/response" status grace_period
  requested_at="$(json_value "$work/response" requestedAt)"
  processing_at="$(python3 - "$requested_at" <<'PY'
import datetime as dt, sys
value = dt.datetime.fromisoformat(sys.argv[1].replace('Z', '+00:00'))
if value.tzinfo is None:
    raise SystemExit('deletion request timestamp is not UTC')
future = value.astimezone(dt.timezone.utc) + dt.timedelta(days=14)
print(future.isoformat().replace('+00:00', 'Z'))
PY
)"
  "${compose[@]}" run --rm control-plane \
    --process-deletions --process-deletions-at "$processing_at" \
    >"$work/deletion-worker.txt"
  grep -Eq 'deletion_worker_processed=[1-9][0-9]* .*completed=[1-9][0-9]*' \
    "$work/deletion-worker.txt" || {
    echo 'deletion worker did not complete the disposable organization request' >&2
    cat "$work/deletion-worker.txt" >&2
    exit 1
  }

  status="$(curl -sS -o "$work/deleted-artifact-response" -w '%{http_code}' \
    -H "Authorization: Bearer $delivery_token" \
    "$endpoint/v1/runtime/artifacts/artifact_dr_1?application_id=$application_id&environment_id=$environment_id" || true)"
  [[ "$status" == 401 || "$status" == 404 || "$status" == 410 ]] || {
    echo "deleted tenant artifact access returned HTTP $status" >&2
    exit 1
  }
  status="$(api_json GET "/v1/organizations/$organization_id/deletion" "$customer_access_token" - "$work/response")"
  # The deleted identity is reloaded before authorization. Depending on
  # whether the inactive-user or missing-membership guard runs first, the
  # stable contract is a denial, not a particular resource-disclosure code.
  assert_status "$status" '401,403,404,410' deleted_customer_access

  tombstone_state="$(db_query "SELECT body->>'deletionState' FROM control_plane_records WHERE collection = 'organizations' AND record_id = '$organization_id';" | tr -d '[:space:]')"
  [[ "$tombstone_state" == deleted ]] || {
    echo "organization tombstone state was not deleted: $tombstone_state" >&2
    exit 1
  }
  deletion_status="$(db_query "SELECT body->>'status' FROM control_plane_records WHERE collection = 'organization_deletion_requests' AND body->>'organizationId' = '$organization_id';" | tr -d '[:space:]')"
  [[ "$deletion_status" == completed ]] || {
    echo "organization deletion request was not completed: $deletion_status" >&2
    exit 1
  }
  tenant_records="$(db_query "SELECT count(*) FROM control_plane_records WHERE organization_id = '$organization_id' AND collection IN ('applications', 'environments', 'releases', 'patches', 'artifacts', 'rollouts', 'rollout_revisions', 'bundle_imports', 'environment_runtime_states', 'cloud_usage_events', 'credentials');" | tr -d '[:space:]')"
  [[ "$tenant_records" == 0 ]] || {
    echo "deleted organization retained $tenant_records tenant records" >&2
    exit 1
  }
  memberships="$(db_query "SELECT count(*) FROM control_plane_records WHERE collection = 'users' AND body->'memberships' @> '[{\"organizationId\":\"$organization_id\"}]'::jsonb;" | tr -d '[:space:]')"
  [[ "$memberships" == 0 ]] || {
    echo "deleted organization retained $memberships customer memberships" >&2
    exit 1
  }
  shared_records="$(db_query "SELECT count(*) FROM control_plane_records WHERE organization_id = '$shared_organization_id' AND collection = 'artifacts';" | tr -d '[:space:]')"
  [[ "$shared_records" == 1 ]] || {
    echo "shared fixture artifact metadata count was $shared_records" >&2
    exit 1
  }
  status="$(curl -sS -o "$work/shared-fetched.bin" -w '%{http_code}' \
    -H "Authorization: Bearer $shared_delivery_token" \
    "$endpoint/v1/runtime/artifacts/artifact_shared_2?application_id=$shared_application_id&environment_id=$shared_environment_id")"
  assert_status "$status" '200' shared_artifact_fetch
  shared_digest="sha256:$(shasum -a 256 "$work/shared-fetched.bin" | awk '{print $1}')"
  [[ "$shared_digest" == "$source_digest" ]] || {
    echo 'shared artifact bytes were not preserved after deletion replay' >&2
    exit 1
  }
  echo 'deletion_tombstone_replay=PASS'
  echo "deleted_organization_id=$organization_id"
  echo "tombstone_state=$tombstone_state"
  echo "deleted_tenant_records=$tenant_records"
  echo "deleted_customer_memberships=$memberships"
  echo "shared_artifact_digest=$shared_digest"
fi

echo 'dr_rehearsal=PASS'
echo 'evidence=DISASTER_RECOVERY_DIRECTIONAL'
echo "source_artifact_digest=$source_digest"
echo "restored_artifact_digest=$restored_digest"
echo "backup_manifest_digest=$backup_digest"
echo 'data_loss_observed=none_in_quiesced_rehearsal'
if [[ "$tombstone_rehearsal" == 1 ]]; then
  echo 'manual_actions=confirm_disposable_target,approve_restore,review_provider_RPO_RTO,run_managed_coupled_tombstone_replay'
else
  echo 'manual_actions=confirm_disposable_target,approve_restore,verify_backup_retention,review_provider_RPO_RTO'
fi
echo 'not_proven=provider_backup_durability,automated_failover,approved_RPO_RTO'
cat "$work/timings.txt"
