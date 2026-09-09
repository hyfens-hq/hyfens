# P3E5-4D recovery and race-hardening review

<!-- markdownlint-disable MD013 -->

Date: 2026-08-24

Task: 66 — P3E5-4D recovery/race hardening

Scope: expired `HALT_APPLYING` recovery, evidence-first idempotency, lease
fencing, File/PostgreSQL races, restart/lost-response handling, bounded
recovery resources, and fail-closed linkage validation.

This review stops at the Task 66 maintainer gate. It does not authorize
P3E5-4E implementation, production enablement, provider HA, or any runtime or
mobile change.

## Findings

The Task 65 residual was real: generic `claimDue` selected expired
`HALT_APPLYING` work, while the automatic application adapter required the old
lease. A worker that lost a response after P3A could therefore not safely
reacquire the work without either reusing an expired token or introducing a
second mutation route.

Task 66 adds a separate `P3e5AutomaticHaltRecoveryService` and an
auto-halt-only persistence seam. Recovery first reloads the exact work and
immutable application evidence. Only an expired, current-version
`HALT_APPLYING` record with a bound intent can receive a fresh lease. The
recovered lease is consumed by the existing Task 65 adapter; rollout mutation
still goes through P3E-4 and the existing P3A expected-revision CAS.

The reclaim changes the work fence and lease but preserves the original
semantic attempt, intent, evaluation, decision, target binding, and expected
rollout revision. It does not inherit a successor revision. Generic scheduled
claiming excludes `HALT_APPLYING` so it cannot steal or retry this state.

## Implemented behavior

```text
read work + immutable application evidence
                 |
       exact linkage valid?
          /              \
        yes               no
        |                  |
  completed?         malformed/foreign -> reject
        |
   no -> lease expired?
          /          \
        no            yes
        |              |
 retryable       reclaim one fenced lease
                       |
                existing app first
                       |
             Task 65 P3E-4/P3A adapter
                       |
        applied + exact revision -> complete
        stale -> terminal STALE work
        conflict -> bounded retry/reconciliation
```

The public recovery outcome vocabulary is:

| Wire outcome | Meaning |
| --- | --- |
| `APPLICATION_FOUND_AND_VALID` | Exact immutable application and P3E-4/P3A linkage are valid; work is completed or recovered. |
| `APPLICATION_NOT_FOUND_RETRYABLE` | No application is present, but an active claimant or non-terminal condition prevents safe reclaim. |
| `APPLICATION_STALE` | Currentness is no longer eligible; recovery fences the work to terminal `STALE`. |
| `APPLICATION_CONFLICT` | A bounded fence, evidence, storage, or resource conflict prevents a safe decision. |
| `APPLICATION_CORRUPT` | Duplicate, malformed, incomplete, or incompatible application/linkage evidence was found. |
| `SECURITY_REJECTED` | Principal, tenant, scope, or authorization validation failed. |

## Evidence executed

The focused automatic-halt suite passed 30 non-PostgreSQL tests when the
PostgreSQL URL was absent; the four PostgreSQL cases were explicitly skipped.
With the repository PostgreSQL fixture URL configured, the complete focused
file passed 34 tests with no skips.

The cases include:

- expired `HALT_APPLYING` reclaimed and completed once;
- exact application evidence found before any P3E-4 retry;
- active lease returns retryable without mutation;
- generic `claimDue` leaves expired `HALT_APPLYING` untouched;
- stale rollout is fenced to terminal `STALE` with no application;
- malformed linkage fails before reclaim;
- expired Auto-Halt Principal and cross-tenant scope reject before reclaim;
- oversized application evidence hits the explicit record bound;
- old lease/token cannot complete after a new fence;
- File lost reclaim response and File restart recovery;
- two PostgreSQL reclaim claimants converge on one fresh lease;
- two PostgreSQL instances converge on one application after the first
  claimant loses its P3E-4 response;
- existing Task 65 P3E-4/P3A lost-response, completion-fence, stale/manual,
  policy/principal, and application-convergence regressions.

The PostgreSQL command used for the final focused run was:

```text
HYFENS_TEST_POSTGRES_URL='<repository PostgreSQL fixture URL>' \
  dart test test/p3e_auto_halt_applicability_test.dart --reporter compact
```

Result: `+34 All tests passed!`.

## File behavior

File persistence performs an atomic work replacement for the fresh recovery
lease and uses the existing one-process/one-writer guard. A lost response
leaves discoverable work state; reopening the store reloads the expired
`HALT_APPLYING` record and the recovery service continues through the same
application key. The test does not claim multi-process File HA.

## PostgreSQL behavior

PostgreSQL recovery locks the scoped work row, verifies the expected work
version and expired lease, and commits one fresh lease through the existing
CAS projection. Competing claimants produce one winner and one fenced
conflict. A separate two-instance test injects a lost P3E-4 response in the
first service; after lease expiry the second service finds the exact immutable
application and completes the same work without a second halt. These are
fixture-local transactional tests, not provider HA evidence.

## Security and failure handling

- Raw lease tokens are generated for one recovery invocation and are not
  returned in the recovery result or written to audit metadata.
- Work version, lease owner, token digest, exact scope, and expiry are checked
  on reclaim and completion; old tokens fail closed.
- Application evidence is inspected before retry. Duplicate, malformed,
  foreign, stale, successor, or oversized linkage is rejected; no repair or
  guessed ID is attempted.
- Stale currentness clears automatic intent and removes the lease in a fenced
  terminal work transition.
- Explicit limits cover recovery attempts, application records, and rollout
  linkage records. The implementation has no implicit production retry or
  capacity defaults.
- P3E-4 remains the sole health-halt application path and P3A remains the
  sole rollout mutation boundary.

## What is not proven

The following remain deliberately open and are not release-readiness claims:

- provider-level PostgreSQL disconnect/reconnect at each requested boundary;
- injected audit-store outage/divergence behavior;
- a measured resource/race-storm or fleet-capacity envelope;
- heartbeat or lease-duration sufficiency under production latency;
- provider HA, production defaults, production enablement, beta, App Store,
  Google Play, privacy, or legal compliance;
- runtime/mobile behavior, rollout actions, expansion/pause/rollback/resume,
  unhalt, P3E5-4E, or later P3 work.

## Frozen items left unchanged

Architecture B/source instrumentation, Patch Format v1, capability v1,
exact-release binding, state-v4 high-water, signed rollback,
fail-closed verification, runtime-authoritative trust, and customer/local
patch signing remain unchanged. Recovery controls delivery orchestration only;
it never invalidates an already healthy runtime patch.

## Architecture assessment

The evidence supports continuing the existing P3E5/P3A control-plane design:
an auto-halt-specific recovery seam is sufficient for the lease-expiry and
lost-response residual without a generic scheduler rewrite, direct rollout
writer, distributed transaction, or runtime/mobile change. The result does
not establish provider production readiness or remove the separately tracked
external gates.

## Recommendation

`AUTHORIZE P3E5-4E INTEGRATION EVIDENCE WITH CONDITIONS`

Conditions: 4E must remain limited to integration evidence; preserve the
P3E4/P3A sole mutation path, exact linkage, semantic-attempt preservation,
generic-claim exclusion, explicit recovery bounds, and fail-closed outcomes;
close the provider-disconnect, audit-divergence, lease-sufficiency, and
resource-envelope evidence before any production/beta/store/legal claim; and
do not implement rollout actions, runtime/mobile changes, telemetry, or
production enablement as part of this authorization.

## Next action

Request maintainer review of this document and
`tasks/66-p3e5-4d-recovery-race-hardening.md`. Do not begin P3E5-4E or any
later work automatically.
