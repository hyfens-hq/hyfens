# P3E5-4E integration evidence review

<!-- markdownlint-disable MD013 -->

Date: 2026-08-24

Task: 67 — P3E5-4E integration evidence

This review stops at the Task 67 maintainer gate. It does not authorize
P3E5-5, P3F, P3G, production enablement, beta, App Store, Google Play, legal,
provider-HA, or runtime/mobile work.

## Findings

The Task 66 recovery/race seam remains correct under the executed bounded
integration campaign. File and local PostgreSQL tests preserve evidence-first
recovery, exact `scheduled-halt:<workId>` idempotency, P3E-4/P3A authority,
semantic-attempt preservation, and fail-closed stale/security behavior.

Audit append is secondary evidence. An injected audit failure before P3E-4
blocks that application request; a failure after P3A does not undo the
committed halt and is reconciled from immutable application/work evidence.
Duplicate File replay returns `StorageConflict`, and tampered chain content is
rejected by `verifyAuditChain`.

The campaign found no architectural defect requiring a new authority, a
distributed transaction, a heartbeat, a runtime change, or a rollout semantic
change. The exact PostgreSQL claim and P3A transaction boundaries now have
independent rollback/response-loss vectors, and the narrow single-call
executor-to-halt rehearsal preserves separate evaluation and Auto-Halt
authority.

## Evidence executed

Focused command:

```text
HYFENS_TEST_POSTGRES_URL='<local PostgreSQL fixture URL>' \
  dart test test/p3e_auto_halt_applicability_test.dart --reporter compact
```

Result: **44/44 tests passed** with the local PostgreSQL fixture.

The full serialized control-plane regression also passed with **197 tests
passed and 1 unchanged MinIO/S3 test skipped** because `HYFENS_TEST_S3_*` was
not configured. A parallel full-suite attempt had one environment-contended
timing assertion; the timing vector passed in the focused and serialized
runs, so no threshold was changed.

The suite includes the existing Task 65/66 coverage plus Task 67 tests for:

- audit unavailable before P3E-4;
- audit failure after P3A and completion reconciliation;
- missing/duplicate/tampered audit evidence and redaction;
- eight-way File critical-path timing and contention;
- PostgreSQL close/reopen after lost reclaim response;
- eight independent PostgreSQL recovery callers converging on one halt;
- exact pre/post claim and pre/post P3A PostgreSQL response-fault seams;
- single-call P3E5-3 → P3E5-4 orchestration and authority rejection vectors.

The deterministic evidence bundle and manifest are in
`docs/research/evidence/p3e5-4e-2026-08-24/`.

## Provider-like disconnect matrix

| Boundary | Result | Label |
| --- | --- | --- |
| PostgreSQL store close/reopen before authoritative recovery read | PASS | `FAULT_INJECTED_NETWORK` |
| PostgreSQL lost reclaim response, close, lease expiry, reconnect, recovery | PASS | `FAULT_INJECTED_NETWORK` |
| File intent commit, P3E-4, P3A, completion, and restart fault seams | PASS | `FILE_SINGLE_NODE` |
| PostgreSQL response fault before claim commit | PASS | `POSTGRESQL_LOCAL_TWO_INSTANCE` |
| PostgreSQL response fault after claim commit | PASS | `POSTGRESQL_LOCAL_TWO_INSTANCE` |
| PostgreSQL response fault before P3A transaction commit | PASS | `POSTGRESQL_LOCAL_TWO_INSTANCE` |
| PostgreSQL response fault after P3A transaction commit | PASS | `POSTGRESQL_LOCAL_TWO_INSTANCE` |

The passing PostgreSQL rows are local transactional response-fault and
provider-like reconnect evidence only. They are not provider HA evidence.

## Audit outage/divergence

| Scenario | Result | Existing contract interpretation |
| --- | --- | --- |
| audit unavailable before automatic application request | PASS | mutation-blocking for that request; intent/retry remains bounded |
| audit failure after P3E-4/P3A | PASS | post-commit reconciliation; never undo P3A |
| application exists without expected secondary audit event | PASS | immutable application/work/P3A evidence remains authoritative |
| duplicate File append | PASS | immutable conflict; no overwrite |
| tampered chain body | PASS | chain verification fails closed |

No new audit authority or 2PC protocol was introduced.

## Lease timing and heartbeat

Final File samples, in microseconds, were:

```text
254572, 199846, 239219, 221277, 275379, 247991, 251585, 263780
```

| Metric | Result |
| --- | ---: |
| min | 199,846 µs |
| median | 251,585 µs |
| p95 | 275,379 µs |
| max | 275,379 µs |
| explicit test lease | 2,000,000 µs |
| measured max margin | 1,724,621 µs |

Decision:

```text
HEARTBEAT NOT REQUIRED FOR BOUNDED CURRENT PATH
```

This is not a production lease recommendation. Provider latency and failure
distributions remain unproven.

## Resource/race envelope

The explicit PostgreSQL envelope used one tenant, one expired
`HALT_APPLYING` work item, eight independent callers, maximum recovery
attempts 5, application/linkage bounds 8/8, and a two-second test lease. The
campaign elapsed 6,093,865 µs including store initialization, produced one
immutable application, and left one completed work item. Five callers returned
`APPLICATION_FOUND_AND_VALID`; three returned bounded
`APPLICATION_NOT_FOUND_RETRYABLE`. No unbounded scan, retry, or connection
leak was observed after stores closed. This is not a production capacity
claim.

## Two-instance and cross-store rehearsal

Verified:

```text
instance A loses reclaim response
→ PostgreSQL schedule store closes
→ instance B reloads authoritative work
→ lease expires
→ exact immutable application is found
→ one HALTED revision
→ one COMPLETED work item
```

File restart/recovery, P3E evidence persistence, HealthHaltApplication, P3A
CAS, and secondary audit partial-success cases also pass. The explicit
single-call coordinator rehearses all five evaluator decisions while keeping
the executor and Auto-Halt Principal separate; only `HALT_NEW_OFFERS` reaches
P3E-4/P3A and creates one HALTED revision/application.

## Security, tenant, and boundary evidence

- Cross-tenant recovery and wrong Auto-Halt Principal are rejected before
  reclaim.
- Generic `claimDue` cannot claim expired `HALT_APPLYING` work.
- Old work-version/token fences reject completion after reclaim.
- Raw credentials and lease tokens are absent from tested audit/evidence
  output.
- Patch/runtime/signing/high-water/AOT and store-policy boundaries are
  unchanged.

## What is not proven

- provider PostgreSQL HA or production disconnect/reconnect;
- production lease defaults or latency distributions;
- production capacity, CPU/memory, or fleet fairness;
- scheduler-loop behavior, queueing, or background execution beyond the
  single-call rehearsal;
- beta, production, App Store, Google Play, privacy, or legal readiness;
- P3E5-5, P3F, P3G, rollout actions, runtime/mobile changes, or telemetry.

## Frozen invariants

Architecture B, Patch Format v1, capability v1, exact release/environment/
patch/function binding, state-v4 high-water, runtime signature authority,
signed rollback, AOT fallback, customer/local signing custody, P3D/P3E
semantics, P3E-4 sole halt application, and P3A sole rollout mutation remain
unchanged.

## Architecture assessment

The evidence supports continuing the existing source-instrumentation and
control-plane architecture. Task 67 required no new mutation authority,
heartbeat, distributed transaction, or runtime change. Provider HA, production
capacity, and readiness review remain separate gates; none is evidence that a
Flutter/Dart fork is required.

## Recommendation

`CLOSE P3E5-4 IMPLEMENTATION — PROCEED TO P3E5-5 DESIGN`

The exact Task 67 closure rows pass. This recommendation is a maintainer
review gate, not authorization to implement P3E5-5. Preserve P3E-4/P3A sole
mutation, exact linkage, bounded recovery, and fail-closed outcomes. Do not
begin P3E5-5, P3F, P3G, production enablement, or provider deployment until a
separate maintainer decision authorizes it.

## Next action

Request maintainer review of this document and
`tasks/67-p3e5-4e-integration-evidence.md`. Stop here after recording the
bounded closure; do not begin P3E5-5 automatically.
