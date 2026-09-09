# Task 238 — Local demo seeder and platform metrics

Status: [x] Completed

## Goal

Provide a repeatable local self-hosted demo account for real Hyfens CLI/project
testing and give an explicitly configured platform profile a read-only,
aggregate view of SaaS-level account and delivery metrics.

## Scope and Non-goals

Scope:

- Add an idempotent control-plane demo seed for `Auvana Ventures Private
  Limited` and `admin@auvanaventures.com` as the owner.
- Add a local Docker helper that keeps the demo password outside source
  control and prints only safe retrieval guidance.
- Add a configured platform-admin authorization seam for aggregate metrics.
- Add a bounded platform metrics projection and dashboard view for counts,
  recent activity, active sessions, and process service measurements.
- Add focused tests, local self-host documentation, and Docker/CLI validation.

Non-goals:

- No password, token, signing key, or credential is committed.
- No tenant-scoped overview weakening and no raw cross-tenant records in the
  platform projection.
- No billing, revenue analytics, cohort warehouse, event pipeline, or
  historical time-series system.
- No changes to the Patch Format, runtime authority, or protected repositories.

## Owner

Coordinator

## Dependencies

- Existing `ControlPlaneService`, `HumanAuthService`, PostgreSQL/File stores,
  dashboard, and `scripts/local-dashboard.sh` local Compose stack.
- Local Docker availability for final integration validation.

## Assumptions

- The local demo owner is identified by the configured platform-admin email
  list and the `super-admin` owner profile.
- Platform metrics are read-only derived snapshots, not authoritative state or
  a replacement for durable analytics.
- The existing local Docker volumes may contain the earlier Local Hyfens demo;
  the new seed must coexist with it and remain idempotent.

## Work Items

- [x] Reserve the task and inspect the existing auth, persistence, metrics,
  dashboard, and local Compose seams.
- [x] Implement deterministic Auvana organization/application/environment and
  owner seeding without source-controlled credentials.
- [x] Implement platform-profile authorization and aggregate metrics response.
- [x] Add dashboard presentation and local/self-host documentation.
- [x] Rebuild/reseed the local Docker stack and exercise the CLI path.
- [x] Review the combined task diff, run targeted validation, and record the
  outcome.

## Validation

Completed validation:

- `python3 -m unittest dashboard.test_serve` — 31 tests passed, including the
  protected platform-metrics proxy route and `/platform` shell path.
- `node --check dashboard/app.js` — passed.
- `sh -n scripts/local-dashboard.sh` — passed.
- `docker compose --project-name hyfens-local-dashboard --env-file
  ~/.hyfens/local-dashboard/compose.env -f deploy/p2/docker-compose.yml -f
  deploy/p2/docker-compose.dashboard.yml config --quiet` — passed.
- `dart test test/demo_seed_test.dart test/platform_metrics_test.dart
  test/platform_metrics_http_test.dart` from `packages/control_plane` — all
  tests passed.
- Scoped `dart analyze` for the new source and tests — no issues found.
- `sh scripts/local-dashboard.sh demo` — rebuilt the control plane and
  dashboard, preserved the named PostgreSQL/object-store volumes, and seeded
  the fixed Auvana scope. A second `seed-demo` run also completed successfully.
  All four local services reported healthy.
- Local CLI smoke against `http://127.0.0.1:18082/` — password login as
  `admin@auvanaventures.com`, profile/status resolution, Flutter fixture
  `doctor`, disposable-copy `init --force`, and metadata-only Android release
  all passed. The repository fixture was not modified.
- Local HTTP smoke — dashboard `/healthz`, control-plane `/healthz`, platform
  identity authorization, and aggregate read-only metrics all passed without
  returning the owner email or credential material.
- `git diff --check` — passed.

## Next Action

None; the local Auvana demo and platform metrics surface are implemented and
validated. Use `sh scripts/local-dashboard.sh demo` to rebuild/reseed the local
stack when resetting the demo environment.

## Blockers

None currently.

## Outcome

Completed. The control plane now has an idempotent fixed-scope seed for
`Auvana Ventures Private Limited`, `admin@auvanaventures.com`, and the
`super-admin` owner profile. The password is supplied at seed time and stored
only in the mode-`0600` local demo credential file outside the repository.

Platform access is an explicit configured-email plus owner/super-admin
authorization check. The `/v1/platform/metrics` projection is read-only and
returns aggregate counts, rolling activity, active sessions, and process-local
service signals; it does not return tenant records or secrets. The dashboard
shows the platform view only for an authorized platform profile.

The local Compose dashboard override also had a packaging defect: its build
context did not match `dashboard/Dockerfile`'s repository-root `COPY` paths.
That context was corrected so the source-backed local rebuild succeeds.

## References

- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/demo_seed.dart`
- `packages/control_plane/lib/src/platform_metrics.dart`
- `packages/control_plane/lib/src/operator_overview.dart`
- `packages/control_plane/lib/src/http.dart`
- `scripts/local-dashboard.sh`
- `deploy/p2/docker-compose.yml`
- `deploy/p2/docker-compose.dashboard.yml`
- `dashboard/index.html`
- `dashboard/app.js`
- `packages/control_plane/test/demo_seed_test.dart`
- `packages/control_plane/test/platform_metrics_test.dart`
- `packages/control_plane/test/platform_metrics_http_test.dart`

## History

- 2026-09-03: Reserved task 238 after confirming existing bootstrap is
  interactive/scope-ID based and platform metrics currently stop at
  process-local `/metrics` plus tenant-scoped overview counts.
- 2026-09-03: Implemented the idempotent Auvana demo seed, configured
  platform-admin authorization, aggregate metrics API, dashboard platform
  view, local/self-host documentation, and focused tests. Rebuilt/reseeded the
  local Docker stack and completed CLI/API smoke validation. Corrected the
  source-backed dashboard Compose build context discovered during the rebuild.
