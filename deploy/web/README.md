# Hyfens OSS dashboard deployment

This directory deploys the public OSS dashboard in `dashboard/`. It contains
only the self-hosted dashboard deployment helper.

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

The local Nginx target is a loopback listener on port `18083`. The dashboard
deployment does not modify the database, object store, control-plane images,
or signing keys.

After the one-time root setup, stage only the dashboard tree and run the fixed
wrapper:

```sh
rsync -a --delete \
  --exclude '__pycache__/' \
  --exclude '.DS_Store' \
  dashboard/ \
  hyfens-server:/home/hyfen/hyfens-deploy-stage/dashboard/

ssh hyfens-server 'sudo -n /usr/local/sbin/hyfens-dashboard-deploy'
```

The wrapper accepts no arguments and only installs the fixed dashboard file
allowlist. It cannot run arbitrary root commands.

The fixed wrapper is intentionally limited to the dashboard file allowlist.
Configure the host's web server and deployment permissions separately for
each self-hosted installation.
