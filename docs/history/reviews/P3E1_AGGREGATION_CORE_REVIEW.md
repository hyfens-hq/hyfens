# P3E-1 deterministic aggregation core review

Status: `READY FOR MAINTAINER REVIEW`
Date: 2026-08-24
Task: `tasks/54-p3e1-deterministic-aggregation-core.md`

<!-- markdownlint-disable MD013 -->

## Scope

Task 54 implements only the pure-Dart P3E-1 aggregation core authorized by the
maintainer. It consumes already validated P3D `ObservationRecord` values and
returns an immutable, canonical, JSON-ready `HealthAggregate`. It does not
persist aggregates, expose an evaluation API, mutate rollout state, schedule
work, or implement automatic halt/hold.

## Verified implementation

| Area | Evidence | Result |
| --- | --- | --- |
| Exact aggregate identity | `aggregation.dart`, identity tests | Tenant/application/environment/platform/release/patch/sequence/rollout/revision/window/schema/aggregation version are validated, equality-stable, and canonicalized with UTC times. |
| Window model | `ObservationWindow`, window tests | `OPEN`, `CLOSED`, and `SEALED` are derived only from explicit server time; impossible durations/cutoffs and unknown window versions fail closed. |
| Scope binding | `_validateEventScope`, mixed-scope test | Mixed release, patch, sequence, rollout, revision, platform, or tenant records are rejected before an aggregate is returned. |
| Dispositions | aggregation tests | Accepted records may enter the primary set; late and quarantined records are visible but excluded from health contributions; rejected/security-rejected counts are external quality context only. |
| Event categories | category mapping test | All 15 P3D event types map exactly once to delivery, admission, activation, post-activation health, rollback/fallback, restart survival, or store-bound exclusion. |
| Event IDs | duplicate/mutation tests | Exact retries contribute once; mutated IDs are tainted, excluded, and counted as security/quality context. |
| Installation caps | noisy-installation test | One installation bucket contributes at most once per event type/checkpoint/window; excess valid IDs cannot dominate a rate. |
| Determinism | permutation/canonical serialization tests | Input order does not change aggregate output; ordering is receipt time, event ID, canonical event body. |
| Metrics | healthy/failure/outage tests | Counters and integer numerator/denominator pairs are deterministic; unresolved denominators are explicitly `NOT_EVALUABLE`. |
| Quality/missing states | quarantine/outage/lifecycle tests | Quality counters distinguish duplicate, mutation, late, quarantine reason, rejected/security-rejected, and out-of-window context; missing lifecycle, restart, stale, outage, and quarantine states are explicit. |
| Privacy | small-cohort test | Small cohorts are represented as `SMALL_COHORT_SUPPRESSED`; aggregate serialization contains no installation bucket. |
| Integrity/resource bounds | digest and malformed/limit tests | Input, policy, and external-quality digests are canonical; record, byte, diagnostic-code, and quarantine-reason limits fail closed. |
| Rollout boundary | stale/concurrent-control shape test and source review | The core has no `RolloutAction` call, persistence seam, HTTP route, scheduler, or runtime trust authority. |

## Executable simulation vectors

The focused suite contains 19 tests covering:

```text
healthy complete window
activation failures
runtime faults
delivery outage
observation outage
late records
quarantine reasons
exact duplicates
mutated duplicate IDs
noisy installation buckets
mixed release scope
stale-evaluation input shape
concurrent-control input shape
permutation determinism
not-evaluable denominators
small-cohort suppression
malformed event input
resource bounds
canonical result stability
```

The vectors assert aggregate inputs/results only. No vector performs a rollout
transition or claims `AUTOMATIC_HALT`, `PHYSICAL`, `BETA`, or `PRODUCTION`
evidence.

## Validation

- `dart format packages/control_plane/lib/src/aggregation.dart
  packages/control_plane/lib/control_plane.dart
  packages/control_plane/test/aggregation_test.dart` — passed.
- `cd packages/control_plane && dart analyze --fatal-infos .` — passed.
- `cd packages/control_plane && dart test test/aggregation_test.dart` — 19
  tests passed.
- `cd packages/control_plane && HYFENS_TEST_POSTGRES_URL='postgresql://hyfens:hyfens-p2-db@127.0.0.1:55433/hyfens?sslmode=disable' dart test`
  — 72 tests passed; one MinIO integration was skipped because the MinIO
  environment variables were not configured.
- `dart analyze .` at the repository root — passed.
- `dart test` at the repository root — 1 test passed.
- Markdown lint, local path/link, whitespace, diff, and secret scans — passed.
- Frozen-boundary and no-rollout-mutation review — passed.

No Android/iOS or physical-device validation was run. Task 54 does not modify
mobile/runtime execution semantics.

## Frozen boundaries and non-goals

Architecture B, Patch Format v1, capability v1, exact release/function/
capability binding, state-v4 high-water, runtime signature authority, signed
rollback, AOT fallback, customer/local signing, artifact bytes, P3A state
semantics, and P3D ingestion semantics are unchanged.

P3E-2 immutable persistence, P3E-3 evaluation API, P3E-4 halt integration,
P3E-5 scheduling, P3F operator tooling, P3G dashboard, automatic expansion,
production thresholds, provider deployment, and store/legal review were not
started.

## Known limits and unresolved policy

Production threshold values, denominator calibration, privacy suppression
minimums, late/window policy values, retention/deletion, independent-app
calibration, interpreter attribution, provider production, beta, production,
and store/legal gates remain unresolved. The core requires policy inputs rather
than silently selecting those values. It is an evidence engine, not a health
decision or runtime authority.

## Recommendation

`AUTHORIZE P3E-2 WITH CONDITIONS`

This is a recommendation for maintainer review, not automatic authorization.
Conditions are that P3E-2 preserve the immutable aggregate/policy digests,
keep persistence storage-agnostic at the domain boundary, add restart and
tenant-isolation tests, and leave P3E-3/P3E-4/P3E-5 and all readiness gates
closed until separately reviewed.
