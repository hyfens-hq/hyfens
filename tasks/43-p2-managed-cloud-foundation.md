# Task 43 — P2 managed cloud foundation

Status: [x] Completed — bounded P2 foundation; maintainer review required

## Goal

Convert the validated P0/P1 local control plane into a bounded,
production-oriented hosted foundation without weakening Architecture B, Patch
Format v1, capability v1, exact release binding, state-v4 high-water, signed
rollback, fail-closed recovery, runtime signature authority, or customer/local
signing custody.

## Scope and Non-goals

Scope: persistence interfaces; PostgreSQL metadata storage; versioned
migrations; S3-compatible immutable artifact storage; hosted authentication and
delivery; request/rate limits; persistent idempotency/concurrency; durable
redacted audit/provenance; structured service logs and health; Docker/Compose
hosted-like deployment; backup/restore and outage/recovery tests; hosted-like
CLI/runtime E2E; physical Android/iOS regression where the environment permits;
independent real-app validation where available; and the final P2 review.

Non-goals: percentage/cohort rollout; runtime telemetry ingestion; dashboard;
billing; managed KMS/HSM; SSO/SAML/OIDC/SCIM; enterprise packaging; React
Native; store submission; commercial pricing; Kubernetes/Helm without a
separate requirement; changing Patch Format v1/capability v1; weakening
runtime authority; or making hosted connectivity mandatory for runtime
correctness.

## Owner

Coordinator. No commit is authorized. Preserve Task 41/42 evidence and stop at
the P2 maintainer-review gate before P3.

## Dependencies

- `tasks/41-productization-p0-p1-foundation.md`;
- `tasks/42-productization-runtime-delivery-integration.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_P2_MANAGED_CLOUD_FOUNDATION.md`;
- `docs/PRODUCTIZATION_P0_P1_REVIEW.md`;
- `docs/product/phase-1d-conditions.md`;
- existing `packages/control_plane`, CLI, Patch Format v1, runtime, and
  physical Task 42 evidence.

## Assumptions

- Customer/local signing remains the only signing-custody model in P2.
- PostgreSQL and S3-compatible storage are untrusted persistence/delivery
  dependencies; E1 remains the runtime trust root.
- Docker Compose is sufficient for hosted-like evidence; this is not HA or
  internet-scale production evidence.
- P1D-02 is closed only for the declared physical fixtures and P1D-13 is
  satisfied only for the bounded local/self-hosted path.
- P1D-01, P1D-03–P1D-11, and P1D-14–P1D-18 retain their Phase 1D
  dispositions unless new evidence explicitly changes a claim boundary.

## Work Items

- [x] Add a persistence interface and retain filesystem self-host support.
- [x] Add PostgreSQL schema, migrations, adapter, tenant isolation, and
  restart/upgrade tests.
- [x] Add an S3-compatible immutable artifact adapter and corruption/outage
  tests.
- [x] Add hosted configuration, limits, readiness/liveness, structured
  redacted logs, and narrow hosted auth.
- [x] Preserve P0/P1 API semantics, persistent idempotency, concurrency, and
  durable audit/provenance.
- [x] Add Dockerfile, isolated Compose stack, TLS/reverse-proxy boundary, and
  operator runbook.
- [x] Add backup/restore and database/object/service outage evidence.
- [x] Run hosted-like CLI/runtime E2E and record evidence labels without
  calling it production evidence.
- [x] Attempt independent real Flutter app and physical Android/iOS hosted-like
  regressions where available; independent-app validation was unavailable and
  the new Android hosted-like run was environment-gated because its ADB Wi-Fi
  endpoint was closed. No unavailable result was inferred.
- [x] Run consolidated P2 validation and create `docs/P2_MANAGED_CLOUD_REVIEW.md`.
- [x] Stop at maintainer review; do not start P3.

## Validation

Validation executed 2026-08-23: affected Dart formatting and analysis;
control-plane PostgreSQL/MinIO integration tests; CLI; Patch Format; runtime;
compiler/instrumenter; Flutter integration; fixture; and root tests;
PostgreSQL migration/tenant/idempotency/concurrency tests; S3-compatible
immutability/outage tests; Docker/Compose config/build and hosted-like E2E;
backup/restore; health/readiness/metrics; secret/redaction scans; shell and
Python checks; and physical iOS hosted-like regression. The new physical
Android hosted-like regression and independent real-app run were attempted but
remain environment-gated/unavailable; prior Task 42 Android evidence is kept
separate and was not relabelled as P2.

## Next Action

Stop at the P2 maintainer review. Do not begin P3 or treat this bounded
hosted-like foundation as beta/production evidence.

## Blockers

No blocker remains for the bounded implementation scope. Open claim gates are
explicitly retained: Android P2 needs a reachable ADB Wi-Fi endpoint,
independent-app validation needs an available real app, coupled PostgreSQL /
object-byte backup needs a rehearsal, and production TLS/availability/key
recovery/policy work needs separate approval.

## Outcome

Implemented and validated as a bounded hosted-like foundation. See
`docs/P2_MANAGED_CLOUD_REVIEW.md` and
`docs/research/evidence/p2-hosted-like-2026-08-23.md`. Recommendation:
`CONTINUE P2 MANAGED CLOUD FOUNDATION`; maintainer review is required before
any continuation, and P3 remains out of scope.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_P2_MANAGED_CLOUD_FOUNDATION.md`;
- `/Volumes/970EvoPlus/Downloads/phase-1d-conditions.md`;
- `/Volumes/970EvoPlus/Downloads/PRODUCTIZATION_P0_P1_REVIEW.md`;
- `tasks/41-productization-p0-p1-foundation.md`;
- `tasks/42-productization-runtime-delivery-integration.md`;
- `docs/product/phase-1d-conditions.md`;
- `docs/security/productization-threat-model.md`;
- `docs/product/local-control-plane.md`.

## History

- 2026-08-23: Reserved Task 43 as the next unused task number after the
  completed Task 41/42 bounded local foundation and received authorization to
  begin P2 with conditions. P3 and all explicit non-goals remain prohibited.
- 2026-08-23: Implemented the bounded PostgreSQL/S3 persistence seam,
  authenticated hosted delivery, limits, readiness/liveness, process-local
  operator metrics, redacted structured errors, Docker/Compose deployment,
  backup scripts, outage handling, and operator documentation. Patch Format v1,
  E1 authority, local/customer signing custody, and runtime fail-closed
  boundaries were preserved.
- 2026-08-23: Hosted-like Compose validation passed for migrations, tenant
  isolation, idempotency/concurrency, immutable artifacts, audit linkage,
  readiness, database/object outage and recovery, CLI/runtime deployment,
  PostgreSQL restore, and the bounded load sample (80 requests at concurrency
  8 with zero load errors). Physical iOS passed one installed base-to-patch
  sequence (540 to 450) with restart persistence. The new Android P2 run was
  attempted but was environment-gated because the declared Wi-Fi ADB endpoint
  was closed; no P2 Android result was inferred. Independent real-app
  validation was unavailable.
- 2026-08-23: Consolidated validation passed after the transient CLI native
  asset-cache failure was isolated and rerun: full CLI (39 tests), control
  plane with external PostgreSQL/MinIO (22 tests), Patch Format, compiler,
  runtime, instrumenter, Flutter integration, fixture, root analysis/tests,
  Compose config, Python syntax, shell syntax, and redaction checks. Created
  `docs/P2_MANAGED_CLOUD_REVIEW.md` and stopped at maintainer review.

## Post-completion validation correction (2026-08-23)

The earlier validation note that the new P2 Android hosted-like run was
environment-gated is superseded by a later physical-device run after the ADB
Wi-Fi endpoint became reachable. Using the Redmi Note 10 Lite at
`192.168.50.135:38951` (Android 16/API 36), one stock arm64 Release APK was
installed and exercised against the LAN-bound Compose control plane. The
authenticated signed patch changed the receipt from `540` to `450`, survived
process restart and control-plane outage, and left package install timestamps
unchanged. The separate direct cross-feature harness also passed business,
async, UI, Riverpod, invalid-signature, rollback, stale/replay, restart, and
rollback-persistence stages. Redacted evidence is recorded at
`experiments/patch_loading/.dart_tool/android_e1_runs/android-p2-followup-20260823-r1/evidence/`
and summarized in `docs/research/evidence/p2-hosted-like-2026-08-23.md`.

This correction closes the declared P2 Android device-validation gap for the
conformance fixture only. It does not change the task's maintainer-review stop
point or close independent-app, performance, power-loss, production, or
store-policy gates.

## Post-completion final-gate reference — 2026-08-23

Task 45 revalidated the retained Android performance reducer and repaired the
bounded async benchmark harness without changing runtime or mobile release
semantics. The final-gate disposition is recorded in
`docs/research/p2-final-evidence-gates-2026-08-23.md`; technical P2 remains a
bounded hosted-like implementation and P3 remains prohibited.
