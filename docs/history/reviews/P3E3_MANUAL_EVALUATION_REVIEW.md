# P3E-3 manual evaluation review

<!-- markdownlint-disable MD013 -->

Status: `READY FOR MAINTAINER REVIEW`
Date: 2026-08-24
Task: `tasks/56-p3e3-manual-evaluation-api.md`

## Decision and scope

Task 55/P3E-2 is accepted for its previously declared bounded scope. Task 56
implements only explicit manual evaluation over one immutable P3E-2 aggregate
revision and a narrow evaluation API. P3E-4, P3E-5, P3F, and P3G were not
started. This document is a recommendation for maintainer review; it does not
authorize the next implementation slice automatically.

## Findings

| Required outcome | Evidence | Result |
| --- | --- | --- |
| Immutable aggregate-only input | `ManualEvaluationRequest` carries references and digests; `ManualP3eEvaluator` loads counters/metrics from `HealthAggregateRecord`; no client counters or raw observations are accepted | PASS |
| Explicit policy and no defaults | `ManualEvaluationPolicy` requires version, digest, sample, coverage, freshness, quality, privacy, and optional test thresholds; no production threshold constants are selected | PASS |
| Deterministic evaluator | Pure `ManualP3eEvaluator`, canonical policy/evaluation-input digest, deterministic reason ordering and IDs | PASS |
| Decision vocabulary and precedence | Only `INSUFFICIENT_DATA`, `CONTINUE`, `HOLD`, `HALT_NEW_OFFERS`, and `MANUAL_REVIEW`; privacy/sample, freshness, quality, observation, delivery, and explicit patch-safety precedence is tested | PASS |
| Evaluation digest binding | `evaluationInputDigest` binds aggregate/revision identity and digest, window, aggregate policy digest, policy versions, threshold-set digest, quality/privacy/freshness/coverage, and recomputability | PASS |
| `HealthEvaluation` persistence | P3E-2 File/PostgreSQL adapters persist immutable versioned evaluation evidence; legacy P3E-2 bodies remain readable, while manual API snapshots require the new digest | PASS |
| `RolloutDecision` evidence persistence | Deterministic decision evidence is stored after evaluation; equal retries acknowledge it and changed bodies conflict | PASS |
| Narrow manual API | Versioned POST, GET, and bounded list routes are implemented; no scheduler, worker, dashboard, or broad operator API was added | PASS |
| Authorization and tenant isolation | `health:evaluate`, `rollout:read`, and `observation:read` are required; tenant-scoped reads, non-revealing foreign errors, and negative tests are present | PASS |
| Stale/corrupt evidence protection | Current rollout revision/target, aggregate lineage, digests, supported versions, and reconciliation are rechecked; stale, missing, malformed, and corrupt evidence fail closed | PASS |
| Idempotency and concurrency | Deterministic IDs, same-body replay, changed-body conflict, restart/reconnect behavior, and two-service PostgreSQL races are tested | PASS |
| Audit integration | Requested, create, replay, conflict, scope-rejection, stale, and evidence-rejection actions use the existing redacted audit path and deterministic audit references | PASS |
| Privacy and quality handling | Privacy suppression, minimum samples/coverage, non-recomputable evidence, quarantine/rejection/late quality limits, and observation/delivery outages have conservative outcomes | PASS |
| Rollout/runtime authority boundary | Evaluation never calls `transitionRollout`; `HALT_NEW_OFFERS` has `resultingTransitionReference: null`; no mobile/runtime/security-trust source changed | PASS |
| P3E-4/P3E-5/P3F/P3G | No halt integration, scheduler, automatic action, dashboard, or subsequent product layer was implemented | NOT STARTED |

## Implemented API

```text
POST /v1/rollouts/{rolloutId}/health/evaluations
GET  /v1/rollouts/{rolloutId}/health/evaluations/{evaluationId}
GET  /v1/rollouts/{rolloutId}/health/evaluations
```

The POST body identifies the organization, application, environment, platform,
rollout revision, aggregate/revision, window, aggregation version, release,
patch, sequence, input/policy digests, and complete explicit policy. It uses
the repository `Idempotency-Key` header. GET/list requests require the
tenant-scoped `organization_id` query parameter, use stable created-at/ID
ordering, and return an opaque cursor. This is a narrow local control-plane
API; no hosted endpoint or deployment claim follows. There is no P3E-3
mutation route: a caller cannot turn an evaluation into a rollout transition,
so mutation attempts are not accepted in this slice and remain a P3E-4 audit/
compare-and-set concern.

## Trust, security, and privacy impact

P3E-3 adds an advisory evidence seam, not a new runtime trust root. Patch
signatures, Patch Format v1, capability v1, exact release/function/capability
binding, state-v4 high-water, signed rollback, fail-closed recovery, AOT
fallback, artifact immutability, and P3A/P3D semantics remain unchanged.
Downloaded patch bytes, raw observations, installation identities, client
counters, and arbitrary native capabilities cannot enter this evaluator.

The policy is caller-supplied and versioned, so an authorized operator can
choose an unsafe test vector; production calibration, approval, and policy
governance remain open. File persistence remains single-node. The evaluator and
control-plane audit write are separate adapters, so cross-store atomicity and
off-box durability are not claimed. Privacy suppression prevents detailed
health inference in the API response, but aggregate differencing, retention,
deletion, and legal obligations remain deployment-specific.

## Evidence labels

The evidence produced by this task is labelled:

```text
UNIT
MANUAL_EVALUATION
API_AUTHORIZATION
TENANT_ISOLATION
IDEMPOTENCY
CONCURRENCY
STALE_INPUT
MALFORMED_EVIDENCE
PRIVACY
ENVIRONMENT_GATED
```

No result is labelled `PHYSICAL`, `BETA`, or `PRODUCTION`. PostgreSQL evidence
is environment-gated; MinIO remains skipped when its environment is absent.

## Validation evidence

The consolidated validation performed for Task 56 produced the following
results:

- `dart format` over changed control-plane source and tests — passed;
- `cd packages/control_plane && dart analyze --fatal-infos .` — passed;
- focused evaluator/API tests without PostgreSQL — 11 passed, one
  environment-gated PostgreSQL test skipped;
- focused evaluator/API tests with the configured PostgreSQL URL — 12 passed,
  including two-service concurrency;
- the configured PostgreSQL URL with the full control-plane suite — 91 passed,
  one MinIO integration skipped because `HYFENS_TEST_S3_*` was not configured;
- `cd packages/control_plane && dart test test/migration_test.dart` — 1 test
  passed;
- `dart analyze .` — passed;
- `dart test` — 1 test passed;
- Markdown lint, local-link, trailing-whitespace, secret/private-material,
  and prohibited-implementation boundary scans — passed.

The PostgreSQL URL used for environment-gated validation is local disposable
test infrastructure only:

```text
postgresql://hyfens:hyfens-p2-db@127.0.0.1:55433/hyfens?sslmode=disable
```

No provider, external production, mobile, or store test is implied.

## Known limitations and readiness gates

P3E-3 does not provide automatic halt, rollout mutation, percentage expansion,
scheduling, background evaluation, dashboarding, alerts, production threshold
sets, provider operation, or runtime/mobile changes. Evaluation is strict to the
current rollout revision for POST; historical evidence is not a transition
candidate. No legal, App Store, Google Play, beta, production, availability,
privacy-compliance, or customer-readiness claim is authorized.

The following gates remain open and are not relabelled by P3E-3:

- P1D-01 true power-loss validation;
- P1D-03 iOS diagnostics limitations;
- P1D-04 broad iOS performance evidence;
- P1D-07 independent real-application validation;
- P1D-09 interpreter-stage attribution;
- P1D-18 Apple/Google/legal review;
- provider-production, beta, production, and store-readiness gates.

## Recommendation

`AUTHORIZE P3E-4 WITH CONDITIONS`

Conditions for any separately approved P3E-4 work are:

1. Keep all frozen runtime, signing, high-water, Patch Format, capability,
   artifact, P3A, P3D, P3E-1, and P3E-2 invariants unchanged.
2. Treat P3E-3 decisions as immutable advisory evidence until a separately
   reviewed compare-and-set transition boundary exists; do not reinterpret
   this task as automatic halt or rollback authority.
3. Do not add scheduler/worker, automatic expansion, dashboard, production
   threshold defaults, raw installation data, mobile/runtime changes, provider
   deployment, or store/legal claims in the next slice.
4. Re-run the focused and full validation suites after any P3E-4 changes and
   preserve the open readiness gates above.

P3E-4 must not begin automatically from this report. Maintainer approval is
required before implementation continues.
