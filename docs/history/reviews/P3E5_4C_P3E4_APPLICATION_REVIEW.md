# P3E5-4C P3E-4 application review

<!-- markdownlint-disable MD013 -->

Status: `IMPLEMENTED AND VALIDATED — READY FOR MAINTAINER REVIEW`

Date: 2026-08-24

Task: `tasks/65-p3e5-4c-p3e4-application.md`

## Decision boundary

Task 65 implements exactly one downstream path:

```text
HALT_APPLYING work
  -> independently reload current bindings
  -> require current lease and exact Auto-Halt Principal
  -> invoke the existing P3E-4 application core
  -> use the existing P3A expected-revision CAS
  -> persist/reuse scheduled-halt:<workId> evidence
  -> verify the exact HALTED revision
  -> fenced HALT_APPLYING -> COMPLETED
```

No scheduler-specific rollout writer, distributed transaction coordinator,
runtime/mobile change, production approval, or production enablement was added.

## What was implemented

`P3e5AutomaticHaltApplicationService` is the only P3E5-4C adapter. Before
calling P3E-4 it reloads the work, intent, schedule/revision, policy and
environment state, application/environment scope, rollout/revision/target,
aggregate/revision, evaluation, decision, freshness, and exact principal and
lease bindings through `P3e5AutomaticHaltApplicabilityService.validateIntent`.

`ControlPlaneService.applyAutomaticHealthHalt` reauthorizes the exact-scope
Auto-Halt Principal and delegates to the existing `applyHealthHalt` core. That
core performs the existing P3E-4 evidence validation and P3A expected-revision
CAS. The automatic path supplies only an in-memory authorized actor; it does
not receive a rollout store or write a rollout row itself.

The deterministic application key is exactly:

```text
scheduled-halt:<workId>
```

The immutable `HealthHaltApplication` and the resulting `HALTED` revision are
verified by decision, evaluation, aggregate revision, rollout, expected and
resulting revisions, target digest, transition reference, idempotency key, and
Auto-Halt Principal identity. A narrow `P3e5AutomaticHaltCompletion` proof is
required before the schedule store can clear the lease and move work to
`COMPLETED`; the generic execution transition cannot manufacture that state.

File completion uses one atomic work replacement. PostgreSQL completion uses a
row-locked transaction and work-version CAS. The File and PostgreSQL stores
also expose test-only before/after-commit failure seams; no production failure
mode is enabled by default.

## Recovery and race evidence

The focused Task 65 suite proves:

| Scenario | Result |
| --- | --- |
| crash before P3E-4 | `HALT_APPLYING` remains retryable; no application exists |
| lost response during P3E-4 / after P3A commit | same scheduled idempotency key finds one application and retries completion |
| lost response after work completion | terminal work and exact P3A evidence are replayed without mutation |
| lease expiry after halt commit | expired lease fails closed; no second halt is created |
| rollout/currentness change before application | P3E-4 is not entered and work remains fenced |
| generic completion bypass | rejected without verified application proof |
| two PostgreSQL application callers | one application, one `HALTED` revision, one completed work item |
| File restart and bounded single-writer behavior | persisted intent survives restart; application completion replay is bounded |

The existing P3E-4 regression suite continues to cover manual halt and manual
expansion races. Task 65 adds the automatic adapter's final currentness gate;
automatic expansion, pause, rollback, resume, and unhalt are not implemented.

## PostgreSQL transaction boundary

The P3E5-4B callback reloads schedule rows through a public store seam. Calling
that callback while holding the PostgreSQL pool connection can deadlock, so the
P3E5-4B PostgreSQL implementation performs the cross-store validator as a
preflight and repeats the schedule/work binding check inside the work-row
transaction. The complete final reload immediately before delivery mutation is
still performed by P3E5-4C and the existing P3E-4/P3A validation/CAS remains
the rollout authority. This is not a claim of one global transaction or
provider high availability.

## Security and policy boundary

The automatic path requires both the current exact-scope fenced lease and the
separate Auto-Halt Principal. Raw tokens and lease material do not enter intent
or audit metadata. Completion rejects mismatched intent digest, decision,
evaluation, rollout revision, transition reference, idempotency key, or
application identity. Existing malformed evidence, tenant-isolation,
credential-kind, and audit-redaction tests remain green.

Test fixtures that set approval and enablement are labelled
`TEST VECTOR ONLY — NOT PRODUCTION POLICY`. Repository defaults remain
unapproved and production-disabled. No store-readiness, beta, production, or
Apple/Google compliance claim follows from this plumbing.

## Validation evidence

- Scoped `dart format`: PASS for the changed control-plane implementation and
  test files.
- `dart analyze --fatal-infos` in `packages/control_plane`: PASS, no issues.
- Focused `p3e_auto_halt_applicability_test.dart` with the configured
  PostgreSQL fixture: PASS, 20 tests.
- Full control-plane suite with
  `HYFENS_TEST_POSTGRES_URL=postgresql://...@127.0.0.1:55433/hyfens?sslmode=disable`:
  PASS, 173 tests; 1 unchanged MinIO test skipped because
  `HYFENS_TEST_S3_*` was not configured.
- Root `dart analyze --fatal-infos`: PASS, no issues; root `dart test`: PASS,
  1 test.
- Markdownlint for the Task 65 review/task and factual addenda: PASS; trailing
  whitespace and high-confidence secret scans: PASS.
- Prohibited-boundary scan: the application adapter contains no direct
  `transitionRollout`, `RolloutAction.halt`, `commitRolloutTransition`, or
  rollout-store write path; PASS.

## Completion matrix

| Requirement | Status |
| --- | --- |
| HALT_APPLYING-only input | PASS |
| v2 scheduled-only / SEALED / PATCH_SAFETY gates | PASS |
| current policy, state, freshness, and all evidence bindings | PASS |
| current fenced lease and exact Auto-Halt Principal | PASS |
| deterministic `scheduled-halt:<workId>` idempotency | PASS |
| existing P3E-4 core and P3A expected-revision CAS | PASS |
| no direct rollout writer or P3A bypass | PASS |
| one immutable `HealthHaltApplication` | PASS |
| one exact `HALTED` rollout revision | PASS |
| future-offer suppression through existing P3A semantics | PASS (existing regression evidence) |
| fenced `HALT_APPLYING -> COMPLETED` | PASS |
| crash/lost-response and lease-fencing recovery | PASS for bounded File/PG fixtures |
| manual race safety | PASS through existing P3E-4 races plus automatic stale gate |
| tenant isolation and audit redaction | PASS |
| automatic expansion, HOLD->pause, rollback, resume, unhalt | NOT IMPLEMENTED |
| production approval or enablement | NOT GRANTED |
| P3E5-4D/4E and later phases | NOT STARTED |
| runtime/mobile trust invariants | UNCHANGED |

## Residual risks and open gates

- File persistence remains single-process/single-writer/single-host-clock.
- PostgreSQL tests demonstrate fixture-local transactional convergence, not
  provider HA, failover, or power-loss durability.
- Cross-store state is not a global transaction; P3E-4/P3A currentness and CAS
  remain the final delivery-eligibility authority.
- Lease expiry after a committed P3A halt fails closed and leaves
  `HALT_APPLYING` for a later recovery/reclaim slice; it does not silently
  complete without a current fence.
- P1D-01, P1D-03, P1D-04, P1D-07, P1D-09, P1D-18, provider-production, beta,
  production, and store-readiness gates remain open and unchanged.

## Recommendation

`AUTHORIZE P3E5-4D RECOVERY/RACE HARDENING WITH CONDITIONS`

Conditions: retain the existing P3E-4/P3A mutation boundary, exact-release and
runtime trust invariants, customer/local signing custody, default-off policy,
and fail-closed lease behavior. P3E5-4D must be separately authorized and
should address the remaining recovery/reclaim and manual-race matrix. Do not
begin P3E5-4D, P3E5-4E, production enablement, or provider deployment from this
review.
