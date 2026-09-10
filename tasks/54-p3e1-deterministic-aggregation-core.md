# Task 54 — P3E-1 deterministic aggregation core

<!-- markdownlint-disable MD013 -->

Status: [x] Completed — P3E-1 implementation and validation complete; maintainer review required

## Goal

Implement the first authorized P3E slice: a pure-Dart deterministic aggregation
core plus executable Task 53 simulation/property-style vectors. Convert
already validated P3D observation records into exact-scope, privacy-aware
aggregate evidence without changing rollout state or runtime trust.

## Scope and Non-goals

Scope: typed aggregate identity; immutable server-time window model; P3D event
category mapping; accepted/late/quarantined and external rejected/security-
rejected handling; exact event-ID deduplication; logical installation
contribution caps; deterministic ordering; integer counters and metric pairs;
minimum/sample/coverage/freshness/missing-data states; small-cohort privacy
state; canonical input/policy/quality digests; resource bounds; pure domain
output; malformed-input and executable simulation tests; factual P3E-1 review
and threat-model addenda.

Non-goals: aggregate/evaluation persistence, PostgreSQL/File schema or
migrations, evaluation APIs, rollout transitions, automatic halt/hold,
manual override/resume, schedulers/workers/queues, dashboards, broad operator
tooling, automatic expansion, mobile/runtime changes, Patch Format/capability
changes, signing/key custody, provider deployment, React Native, billing,
enterprise features, store submission, or legal/compliance claims.

## Owner

Coordinator. No commit is authorized. Stop at the P3E-1 maintainer-review gate.

## Dependencies

- supplied `/Volumes/970EvoPlus/Downloads/CODEX_TASK54_P3E1_DETERMINISTIC_AGGREGATION_CORE.md`;
- supplied `/Volumes/970EvoPlus/Downloads/P3E_AGGREGATION_HALT_DESIGN.md`;
- `tasks/53-p3e-aggregation-and-conservative-halt-design.md`;
- `packages/control_plane/lib/src/observation.dart`;
- existing P3A rollout and P3D advisory-observation boundaries.

## Assumptions

- Task 54 authorization is limited to P3E-1; P3E-2/3/4/5 remain prohibited.
- P3D records are already authenticated, scope-validated, bounded, and
  privacy-minimized; P3E-1 does not duplicate HTTP/token validation.
- Rejected/security-rejected requests are represented only through explicitly
  supplied external quality counts and never become health events.
- `AggregateIdentity`, `ObservationWindow`, and `AggregationPolicy` values
  are caller-supplied; no production thresholds or window/privacy defaults are
  selected by this task.
- A sealed primary aggregate excludes late records from primary counters and
  input digest while retaining late context counters.

## Work Items

- [x] Reserve Task 54 and preserve all P3A/P3D/runtime trust invariants.
- [x] Implement exact aggregate identity with canonical UTC serialization,
  equality, version checks, and mixed-scope validation.
- [x] Implement immutable `OPEN`/`CLOSED`/`SEALED` window placement and safe
  duration/cutoff/version validation.
- [x] Implement P3D event-category mapping and disposition inclusion/exclusion.
- [x] Implement event-ID deduplication, mutation tainting, deterministic
  contributor ordering, and one-per-installation logical contribution caps.
- [x] Implement bounded counters, quality/reason counters, integer metric
  pairs, explicit `NOT_EVALUABLE`, sample/coverage/freshness/missing states,
  and small-cohort privacy state.
- [x] Implement canonical input, policy, and external-quality digest binding
  plus explicit record/byte/code/reason resource bounds.
- [x] Add executable simulation, malformed-input, permutation/property-style,
  mixed-scope, late/quarantine, privacy, and resource-bound tests.
- [x] Export the core through `packages/control_plane/lib/control_plane.dart`.
- [x] Add factual P3E design and productization threat-model addenda.
- [x] Run final consolidated validation, update this task/review evidence, and
  stop before P3E-2.

## Validation

Completed validation:

- `dart format packages/control_plane/lib/src/aggregation.dart
  packages/control_plane/lib/control_plane.dart
  packages/control_plane/test/aggregation_test.dart` — passed.
- `cd packages/control_plane && dart analyze --fatal-infos .` — passed.
- `cd packages/control_plane && dart test test/aggregation_test.dart` — 19
  tests passed.
- `cd packages/control_plane && HYFENS_TEST_POSTGRES_URL='postgresql://hyfens:hyfens-p2-db@127.0.0.1:55433/hyfens?sslmode=disable' dart test`
  — 72 tests passed; one MinIO integration skipped because its environment
  variables were not configured.
- `dart analyze .` — passed.
- `dart test` — 1 test passed.
- Markdown lint, local path/link, whitespace, diff, and secret scans —
  passed.
- Frozen-invariant, no-rollout-mutation, and no-P3E-2/3/4/5 boundary review —
  passed.

No physical Android/iOS, provider, persistence, API, scheduler, or runtime
tests are expected or authorized.

## Next Action

Maintainer review of `docs/P3E1_AGGREGATION_CORE_REVIEW.md` and the
recommendation `AUTHORIZE P3E-2 WITH CONDITIONS` is the next action. Do not
begin P3E-2 persistence automatically.

## Blockers

The implementation is not blocked; maintainer review is the required stopping
point after validation. Existing readiness gates remain open: P1D-01 power
loss, P1D-03 iOS diagnostics, P1D-04 iOS performance, P1D-07 independent app,
P1D-09 interpreter attribution, P1D-18 Apple/Google/legal review, provider
production gates, beta readiness, production readiness, and store readiness.

## Outcome

P3E-1 is complete for its authorized bounded scope: a pure-Dart deterministic
aggregate core with executable vectors, canonical digests, explicit quality and
privacy states, and fail-closed resource/input validation. No persistence,
evaluation API, rollout mutation, automatic halt, scheduler, dashboard,
mobile/runtime, or readiness claim was added. Stop at maintainer review; do not
begin P3E-2 automatically.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK54_P3E1_DETERMINISTIC_AGGREGATION_CORE.md`;
- `/Volumes/970EvoPlus/Downloads/P3E_AGGREGATION_HALT_DESIGN.md`;
- `tasks/53-p3e-aggregation-and-conservative-halt-design.md`;
- `docs/P3E_AGGREGATION_HALT_DESIGN.md`;
- `docs/P3_ROLLOUT_OBSERVABILITY_DESIGN.md`;
- `docs/security/productization-threat-model.md`.

## History

- 2026-08-24: Reserved Task 54 after explicit maintainer authorization for
  P3E-1 only. P3E-2/3/4/5 and all runtime/production boundaries remain frozen.
- 2026-08-24: Implemented the storage-agnostic identity/window/policy,
  deterministic aggregation engine, canonical digests, quality/privacy states,
  resource bounds, public export, and executable vectors.
- 2026-08-24: Focused aggregation tests (19), full control-plane tests with
  PostgreSQL (72; one MinIO integration skipped), root analysis/tests, and
  documentation/security/boundary scans passed. Task is complete pending
  maintainer review and the P3E-2 decision.
