import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const compose = readFileSync(
  new URL("./docker-compose.public-control-plane-dev.yml", import.meta.url),
  "utf8",
);
const wrapper = readFileSync(
  new URL("./hyfens-public-control-plane-dev-backup", import.meta.url),
  "utf8",
);
const installer = readFileSync(
  new URL("./install-public-control-plane-dev-backup.sh", import.meta.url),
  "utf8",
);
const service = readFileSync(
  new URL("./hyfens-public-control-plane-dev-backup.service", import.meta.url),
  "utf8",
);
const timer = readFileSync(
  new URL("./hyfens-public-control-plane-dev-backup.timer", import.meta.url),
  "utf8",
);
const freshnessService = readFileSync(
  new URL(
    "./hyfens-public-control-plane-dev-backup-freshness.service",
    import.meta.url,
  ),
  "utf8",
);
const freshnessTimer = readFileSync(
  new URL(
    "./hyfens-public-control-plane-dev-backup-freshness.timer",
    import.meta.url,
  ),
  "utf8",
);
const envExample = readFileSync(
  new URL("./.env.example", import.meta.url),
  "utf8",
);

test("backup client is isolated from the long-running control plane", () => {
  assert.match(compose, /cloud-backup:/);
  assert.match(
    compose,
    /amazon\/aws-cli:2\.27\.41@sha256:[0-9a-f]{64}/,
  );
  assert.match(compose, /profiles: \["managed-backup"\]/);
  assert.match(compose, /network_mode: bridge/);
  assert.match(compose, /read_only: true/);
  assert.match(compose, /cap_drop:\s*\n\s*- ALL/);
  const controlPlane = compose.slice(
    compose.indexOf("  control-plane:"),
    compose.indexOf("  cloud-backup:"),
  );
  assert.doesNotMatch(controlPlane, /HYFENS_PUBLIC_BACKUP_SOURCE_SECRET/);
  assert.doesNotMatch(controlPlane, /HYFENS_PUBLIC_BACKUP_DEST_SECRET/);
  const backupService = compose.slice(compose.indexOf("  cloud-backup:"));
  assert.doesNotMatch(backupService, /HYFENS_AUTH_SIGNING_KEY/);
  assert.doesNotMatch(backupService, /HYFENS_R2_SECRET_KEY/);
});

test("wrapper enforces the paired snapshot and verification boundary", () => {
  for (const name of [
    "HYFENS_PUBLIC_BACKUP_SOURCE_ENDPOINT",
    "HYFENS_PUBLIC_BACKUP_SOURCE_BUCKET",
    "HYFENS_PUBLIC_BACKUP_SOURCE_ACCESS_KEY_ID",
    "HYFENS_PUBLIC_BACKUP_SOURCE_SECRET_ACCESS_KEY",
    "HYFENS_PUBLIC_BACKUP_DEST_ENDPOINT",
    "HYFENS_PUBLIC_BACKUP_DEST_BUCKET",
    "HYFENS_PUBLIC_BACKUP_DEST_ACCOUNT_ID",
    "HYFENS_PUBLIC_BACKUP_DEST_ACCESS_KEY_ID",
    "HYFENS_PUBLIC_BACKUP_DEST_SECRET_ACCESS_KEY",
    "HYFENS_PUBLIC_BACKUP_MAX_AGE_SECONDS",
  ]) {
    assert.match(wrapper, new RegExp(name));
    assert.match(envExample, new RegExp(`^${name}=`, "m"));
  }
  assert.match(wrapper, /backup_prefix=operational\/public-control-plane\//);
  assert.match(wrapper, /hyfens-cloud-backups/);
  assert.match(wrapper, /--exclude 'operational\/\*'/);
  assert.match(wrapper, /pg_dump/);
  assert.match(wrapper, /--format=custom/);
  assert.match(wrapper, /pg_restore --list/);
  assert.match(wrapper, /objects-manifest\.json/);
  assert.match(wrapper, /operator_quiesced_pair_required/);
  assert.match(wrapper, /read-back checksum verification/);
  assert.match(wrapper, /check-freshness/);
  assert.match(wrapper, /freshness_min_age_seconds=900/);
  assert.match(wrapper, /freshness_max_age_limit_seconds=2592000/);
  assert.match(
    wrapper,
    /\[ "\$source_access_key" = "\$destination_access_key" \]/,
  );
  assert.match(
    wrapper,
    /\[ "\$destination_endpoint" = "https:\/\/\$\{destination_account_id\}\.r2\.cloudflarestorage\.com" \] \|\| \{/,
  );
  assert.match(wrapper, /flock -w 300 9/);
  assert.match(wrapper, /--network none/);
  assert.match(wrapper, /--profile managed-backup/);
  assert.match(wrapper, /--env-from-file/);
  assert.match(wrapper, /chmod 0600 "\$aws_env_file"/);
  assert.match(wrapper, /--no-TTY/);
  assert.doesNotMatch(wrapper, /HYFENS_ALLOW_RESTORE/);
});

test("installation and timers are root-owned, persistent, and bounded", () => {
  for (const file of [
    "hyfens-public-control-plane-dev-backup",
    "hyfens-public-control-plane-dev-backup.service",
    "hyfens-public-control-plane-dev-backup.timer",
    "hyfens-public-control-plane-dev-backup-freshness.service",
    "hyfens-public-control-plane-dev-backup-freshness.timer",
  ]) {
    assert.match(installer, new RegExp(file.replaceAll(".", "\\.")));
  }
  assert.match(installer, /systemctl enable --now hyfens-public-control-plane-dev-backup\.timer/);
  assert.match(installer, /systemctl enable --now hyfens-public-control-plane-dev-backup-freshness\.timer/);
  assert.match(installer, /root:root 600/);
  assert.match(service, /Type=oneshot/);
  assert.match(service, /User=root/);
  assert.match(service, /TimeoutStartSec=30min/);
  assert.match(timer, /OnCalendar=\*-\*-\* 02:30:00 UTC/);
  assert.match(timer, /Persistent=true/);
  assert.match(timer, /RandomizedDelaySec=15min/);
  assert.match(freshnessService, /Type=oneshot/);
  assert.match(freshnessService, /check-freshness/);
  assert.match(freshnessService, /TimeoutStartSec=10min/);
  assert.match(freshnessTimer, /OnBootSec=20min/);
  assert.match(freshnessTimer, /OnUnitActiveSec=15min/);
  assert.match(freshnessTimer, /Persistent=true/);
});
