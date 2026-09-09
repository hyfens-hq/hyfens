# Waypoint local API fixture

This directory contains a small, deterministic HTTP server for the AlphaX
Waypoint reference app's explicit network mode. It is local test infrastructure
only: it has no authentication, secrets, persistence, external calls, or AWS
dependency.

## Start with Docker

From the repository root:

```sh
cd fixtures/waypoint_api
docker compose -p hyfens-task99-waypoint-fixture up --build -d
docker compose -p hyfens-task99-waypoint-fixture ps
curl --fail http://127.0.0.1:8080/api/probe
curl --fail http://127.0.0.1:8080/api/home
curl --fail --get --data-urlencode 'q=Kyoto' http://127.0.0.1:8080/api/search
curl --fail http://127.0.0.1:8080/api/trips/kyoto
curl --fail http://127.0.0.1:8080/api/activity
```

Stop and remove only this fixture's container and locally built image with:

```sh
docker compose -p hyfens-task99-waypoint-fixture down --rmi local --volumes --remove-orphans
```

The compose healthcheck calls `/api/probe`. A healthy response is
`{"ok":true}`. The server binds `0.0.0.0` inside the container and Docker
publishes port `8080` on the host.

If the default host port is already in use, choose another disposable host
port while the container continues to listen on `8080`:

```sh
WAYPOINT_FIXTURE_PORT=18080 docker compose -p hyfens-task99-waypoint-fixture up --build -d
curl --fail http://127.0.0.1:18080/api/probe
```

## Routes

The response fields match the verified AlphaX Waypoint reference app models.
The fixture currently contains the `kyoto` and `lisbon` trip IDs.

| Method | Route | Response |
| --- | --- | --- |
| GET | `/api/home` | Object with decoder-compatible `trips`, `places`, `activities`, `actions`, and active `banner` |
| GET | `/api/search?q=<text>` | Object with a filtered `places` array; an empty query returns all places |
| GET | `/api/trips/<id>` | One full trip object for `kyoto` or `lisbon`; unknown IDs return HTTP 404 |
| GET | `/api/activity` | Deterministic line-delimited activity objects (`application/x-ndjson`) |
| GET | `/api/probe` | `{"ok":true}` |

Search matches the query case-insensitively against each place's name,
category, location, or country. Responses are read-only JSON and are stable
between runs. CORS is open only because this is an isolated local fixture; it
is not a production CORS or authentication policy.

The home response uses the current Flutter decoder's preferred fields for
destination, trip, activity, banner, and action models. It keeps the older
aliases used by the search fixture where they are harmless, so the response
also exercises the decoder's compatibility paths without returning placeholder
values for required display fields.

The fixture deliberately does not implement itinerary file downloads or
document uploads. Those are separate AlphaX reference-app surfaces and are
outside this minimal local-network task.

## Waypoint network mode

For a desktop app running on the same host, use:

```sh
flutter run \
  --dart-define=WAYPOINT_MODE=network \
  --dart-define=WAYPOINT_BASE_URL=http://127.0.0.1:8080/
```

For a physical iPhone or Android device, `127.0.0.1` means the device itself,
not the development computer. Use the computer's LAN IPv4 address instead,
for example `http://192.168.1.20:8080/`, keep the device and computer on a
reachable network, and allow the port through the host firewall. A USB cable
or Android Wi-Fi debugging connection does not by itself provide an HTTP
tunnel to this fixture. The app's iOS ATS and Android cleartext-network
configuration may also need to allow this local HTTP URL; those platform
changes are outside this fixture directory.

This server is HTTP-only. Use HTTPS and an intentional security design for any
shared or hosted environment; do not treat this fixture as production hosting.
