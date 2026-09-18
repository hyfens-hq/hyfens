# Task 52 — P3D health-event ingestion

<!-- markdownlint-disable MD013 -->

Status: [x] Completed — P3D bounded implementation and validation complete; stopped at maintainer-review gate

## Goal

Implement the bounded P3D health-event ingestion contract authorized by the
maintainer: PostgreSQL cross-process rollout-transition safety, authenticated
short-lived observation upload tokens, privacy-minimized versioned patch-safety
events, tenant/application/environment and immutable release/patch/rollout
binding, duplicate-safe persistence, bounded validation/rate limits, retention
and deletion, and observation-outage independence.

## Scope and Non-goals

Scope: add the smallest pure-Dart observation domain and persistence seam;
upgrade PostgreSQL rollout transitions to transactional expected-revision CAS;
add observation credential issuance and the two versioned observation routes;
validate event vocabulary/schema/identity/sequence/clock/metadata/privacy
boundaries; persist and delete observations through File and PostgreSQL
adapters; and record focused security and restart/idempotency evidence.

Non-goals: changing Architecture B, Patch Format v1, capability v1, exact
release/function/capability binding, state-v4 high-water, runtime signature
authority, signed rollback, AOT fallback, customer/local signing custody,
artifact bytes, rollout eligibility semantics, P3E aggregation or automatic
halt, P3F broad CLI/operator API, P3G dashboard, alerting, billing, managed
KMS/HSM, SSO/SCIM, React Native, store submission, provider production, or
legal/compliance claims.

## Owner

Coordinator. No commit is authorized. Stop at the P3D maintainer-review gate.

## Dependencies

- supplied `/Volumes/970EvoPlus/Downloads/CODEX_TASK51_P3D_HEALTH_EVENT_INGESTION.md`;
- `tasks/50-p3a-rollout-domain-and-eligibility.md`;
- `tasks/51-ios-diagnostics-and-performance-rerun.md` (reserved numbering);
- `docs/P3_ROLLOUT_OBSERVABILITY_DESIGN.md`;
- `packages/control_plane` domain, auth, HTTP, service, persistence, and
  PostgreSQL adapter;
- PostgreSQL integration environment when available.

## Assumptions

- The supplied “Task 51” number cannot be reused because the repository already
  contains the completed physical-iOS Task 51; this implementation is tracked
  as Task 52 without changing the supplied authorization or scope.
- Observation records are advisory and never participate in runtime trust,
  rollout eligibility, high-water, activation, rollback, or artifact validity.
- A short-lived observation credential is a new credential kind with only
  `observation:write`; the existing control and delivery credentials remain
  unchanged in authority.
- PostgreSQL is the only distributed rollout-CAS claim; File storage remains a
  bounded local/self-host adapter and does not claim cross-process safety.
- Raw observation retention defaults to a bounded duration and is configurable
  only within safe positive bounds; no compliance/legal-hold workflow is added.

## Work Items

- [x] Reserve Task 52 and freeze P3A/runtime/security boundaries.
- [x] Add PostgreSQL transactional rollout transition with expected-revision
  row locking/CAS, immutable revision, current pointer, idempotency, and audit
  chain committed atomically; preserve local adapter behavior.
- [x] Add the versioned P3D event vocabulary/schema, safe metadata and
  diagnostic-code validators, clock/late-data classification, and impossible
  sequence handling.
- [x] Add short-lived observation token issuance, scope enforcement, revocation
  behavior, and denial on rollout/release/artifact/control routes.
- [x] Add observation persistence, event-id idempotency/mutation rejection,
  retention/deletion, restart recovery, and bounded request/event rate limits.
- [x] Add `/v1/observations/token` and `/v1/observations/events` using existing
  error envelopes and redacted logging; do not add aggregation or dashboards.
- [x] Add focused unit/service/HTTP/PostgreSQL tests for tenant isolation,
  binding, replay, rate/body limits, redaction, outage independence, and CAS.
- [x] Update P3 design, productization threat model, and create the P3D review
  record without rewriting historical P2 evidence.
- [x] Run affected/full validation, review the task-owned diff, and stop at
  P3D maintainer review.

## Validation

Planned commands:

- `dart format` and `dart analyze --fatal-infos` for `packages/control_plane`;
- focused event-schema, token, idempotency, scope, redaction, retention,
  HTTP, and rollout-CAS tests;
- local FileControlPlaneStore restart/idempotency/deletion tests;
- PostgreSQL migration, two-instance CAS, observation persistence, restart,
  and isolation tests when `HYFENS_TEST_POSTGRES_URL` is configured;
- full `cd packages/control_plane && dart test`, root `dart analyze .`, and
  root `dart test`;
- Markdown whitespace/link checks and affected shell/Python checks.

No physical-device rerun is expected because P3D does not modify runtime or
mobile code. Any observation outage test must prove existing patch delivery
and runtime behavior remain independent.

## Next Action

Maintainer review of `docs/P3D_HEALTH_EVENT_REVIEW.md`. Do not begin P3E
aggregation/automatic halt, P3F CLI/operator expansion, P3G dashboard, or any
unrelated product infrastructure until a new task and explicit authorization
are recorded.

## Blockers

The PostgreSQL integration environment may be unavailable. If so, local tests
and static validation may pass, but distributed CAS and PostgreSQL observation
persistence remain explicitly `NOT RUN` rather than inferred. Existing
independent-app, power-loss, broad iOS performance, interpreter-attribution,
provider-production, and store/legal gates remain open and are not relabelled
by P3D.

## Outcome

P3D bounded implementation is complete. PostgreSQL schema v2, cross-process
rollout CAS, observation token/event APIs, duplicate-safe persistence,
identity/sequence/clock/retention/rate validation, redacted security auditing,
and outage-independent delivery behavior are implemented. Focused File/HTTP
tests, PostgreSQL integration tests against the local PostgreSQL 17 container,
the full 53-test control-plane suite, root analysis, and root tests passed. MinIO
integration remained skipped because `HYFENS_TEST_S3_*` was not configured.
No mobile runtime or physical-device claim is made for P3D. P3E/P3F/P3G and
production/store/legal readiness remain out of scope.

## References

- supplied maintainer instruction:
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK51_P3D_HEALTH_EVENT_INGESTION.md`;
- `/Volumes/970EvoPlus/Downloads/50-p3a-rollout-domain-and-eligibility.md`;
- `/Volumes/970EvoPlus/Downloads/P3_ROLLOUT_OBSERVABILITY_DESIGN.md`;
- `tasks/50-p3a-rollout-domain-and-eligibility.md`;
- `docs/security/productization-threat-model.md`.

## History

- 2026-08-23: Reserved Task 52 because the repository already uses Task 51 for
  the completed physical-iOS diagnostics/performance rerun. Accepted the
  supplied authorization for P3D only; P3A and all runtime trust invariants
  remain frozen.
- 2026-08-24: Implemented P3D observation schema, token and event boundaries,
  File/PostgreSQL persistence, transactional rollout CAS, HTTP routes, tests,
  design/threat-model updates, and `docs/P3D_HEALTH_EVENT_REVIEW.md`.
- 2026-08-24: Validated with `dart analyze --fatal-infos`, full control-plane
  tests with PostgreSQL configured (53 passed; MinIO skipped), root analysis,
  and root tests. Stopped at the P3D maintainer-review gate.
