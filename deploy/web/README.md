# Hyfens OSS dashboard deployment

This directory deploys the public OSS dashboard in `dashboard/`. It contains
no marketing website, CMS, editorial content, or Cloud-only web code.

The dashboard is a dependency-free static client for the Hyfens control plane.
It keeps human session material in memory, renders authoritative read-only
records, and does not invent telemetry or unsupported mutation controls.

## Local development

Start the control plane, then serve the dashboard through its bounded local
proxy:

```sh
python3 dashboard/serve.py \
  --api-origin http://127.0.0.1:18081 \
  --bind 127.0.0.1 \
  --port 8080
```

Open `http://127.0.0.1:8080/`. The proxy forwards only the documented
discovery, human-auth, device-auth, and read-only overview routes.

## Deployment shape

`hyfens-dashboard-deploy` installs the named dashboard files into:

```text
/var/www/hyfens/dashboard
```

The local Nginx target is `app.hyfens.com` on loopback port `18083`. The
dashboard deployment does not modify PostgreSQL, R2, control-plane images,
signing keys, or the marketing site.

After the one-time root setup, stage only the dashboard tree and run the fixed
wrapper:

```sh
rsync -a --delete \
  --exclude '__pycache__/' \
  --exclude '.DS_Store' \
  dashboard/ \
  hyfens-server:/home/hyfen/p2-deploy-stage/dashboard/

ssh hyfens-server 'sudo -n /usr/local/sbin/hyfens-dashboard-deploy'
```

The wrapper accepts no arguments and only installs the fixed dashboard file
allowlist. It cannot run arbitrary root commands.

## One-time host setup

`install-dashboard-deploy-access.sh` is a root-only setup input. It installs
the fixed wrapper, Nginx site, and narrow sudo rule. It does not add SSH keys,
change SSH policy, or grant the deployment user Docker access.

The private Cloud web repository owns the separate marketing/CMS deployment;
those sources and deployment files are intentionally absent from this OSS
directory.
