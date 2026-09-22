# Task 302 — Dashboard edge hardening

Status: [x] Completed

## Goal

Harden the public OSS dashboard container and its static Nginx boundary against
base-image drift and common browser embedding/capability exposure.

## Scope and Non-goals

Scope:

- the dashboard container base image;
- safe static response headers; and
- the self-hosted TLS proxy example's browser-facing headers.

Non-goals:

- no CSP redesign for the existing dashboard and auth flows;
- no production deployment or certificate change; and
- no changes to dashboard API authorization or control-plane behavior.

## Owner

Coordinator: Hyfens engineering.

## Dependencies

- verified Nginx manifest digest; and
- existing dashboard static/auth flow compatibility.

## Assumptions

- the dashboard remains served through a TLS reverse proxy in deployment;
- `SAMEORIGIN` framing is compatible with the dashboard; and
- operators may add a stricter edge policy for their own deployment.

## Work Items

- [x] Reserve the task and inspect the dashboard image and edge defaults.
- [x] Pin the Nginx image and add safe browser headers.
- [x] Review the combined diff and run dashboard/container validation.

## Validation

Completed on 2026-09-19:

- `python3 -m unittest dashboard/test_serve.py` passed all 30 tests;
- the dashboard image built successfully from the pinned Nginx manifest; and
- `git diff --check` and header assertions passed.

## Next Action

Owner review remains before release. Keep the dashboard behind the documented
TLS reverse proxy and review any stricter deployment CSP separately.

## Blockers

None known.

## Outcome

The OSS dashboard image and self-hosted TLS example now carry immutable base
references and bounded browser security headers. No deployment was performed.

## References

- `dashboard/Dockerfile`
- `dashboard/nginx.conf`
- `deploy/self-hosted/nginx.conf.example`

## History

- 2026-09-19: Reserved after the security review found an unpinned dashboard
  Nginx base and incomplete static browser headers.
- 2026-09-19: Pinned Nginx, added framing/capability headers, and passed the
  dashboard test suite and container build.
