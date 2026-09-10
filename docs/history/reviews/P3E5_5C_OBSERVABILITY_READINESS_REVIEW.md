# P3E5-5C bounded observability and readiness review

<!-- markdownlint-disable MD013 -->

Status: implementation complete; maintainer decision required
Date: 2026-08-24
Task: 72

## Recommendation

Recommendation: `PROCEED TO P3E5-5D WITH CONDITIONS`

This recommendation is based only on the bounded Task 72 evidence below. It
is not authorization to start P3E5-5D: a new maintainer decision is required.
The conditions are that the exact-scope host authorization seam remains
mandatory, metrics remain process-local/non-authoritative, bounded diagnostics
remain read-only, all P3E5-5B authority boundaries remain frozen, and the
remaining provider, beta, production, mobile/runtime, store, privacy, and
legal gates remain open.

## Frozen authority model

Task 72 preserves the Task 70/71 authority boundary:

- P3A remains rollout mutation authority;
- P3E-4 remains the automatic-halt application path;
- reconciliation execution remains bounded startup/manual execution only;
- metrics, liveness, readiness, and diagnostics never invoke reconciliation;
- immutable evidence and audit history remain append-only/report-only;
- non-executable action dispositions remain fail-closed;
- diagnostics require a host-supplied exact organization/application/environment
  authorization callback.

## Metrics inventory and cardinality

`ReconciliationObservabilityMetrics` is process-local and reset on restart. It
records bounded taxonomy/status/outcome/execution-mode maps, findings and
repair totals, backlog count and cursor age from the last bounded run, store
errors, audit-invalid signals, schema incompatibility, malformed records, and a
safe last-run summary. Keys are fixed enum names; no tenant, application,
finding, rollout, release, token, or free-form error labels are emitted.

The existing HTTP request metric operation names were normalized to fixed route
templates so resource identifiers are not used as metric keys. `/metrics`
remains the existing JSON process-local contract; no metrics database or
external observability stack was added.

## Liveness

`GET /livez` reports only that the HTTP process is serving. It does not probe
the reconciliation store, audit chain, authoritative stores, or backlog. It is
rate-limit exempt and remains healthy during reconciliation-store outage or
audit invalidity. `/healthz` remains a compatibility alias.

## Readiness

`GET /readyz` combines the existing control-plane readiness check with the
optional reconciliation adapter. The reconciliation check is read/verify-only:
it checks initialized File/PostgreSQL persistence and exact schema version,
optional authoritative-store readiness, and optional audit-chain validity. It
never runs migration, reconciliation, repair, cursor advancement, lifecycle
mutation, or rollout mutation.

Stable failure codes are `RECONCILIATION_STORE_UNAVAILABLE`,
`SCHEMA_INCOMPATIBLE`, `AUDIT_INVALID`, `AUDIT_STORE_UNAVAILABLE`, and
`AUTHORITATIVE_STORE_UNAVAILABLE`. Backlog alone does not make readiness fail.

This is intentionally a narrow serving/readiness policy: a process can be live
while reconciliation persistence is unavailable, and a bounded backlog is
reported through metrics/diagnostics rather than used as an invented readiness
threshold.

## Diagnostics API

When the host wires `ReconciliationObservability`, the existing HTTP server
provides:

- `GET /v1/reconciliation/diagnostics`;
- `GET /v1/reconciliation/findings/<finding-id>`.

Both require exact `organization_id`, `application_id`, and `environment_id`
query parameters and the supplied authorizer. Lists use bounded limits,
stable cursors, fixed taxonomy/status/outcome/report-only/time-window filters,
and no arbitrary query syntax. Detail/list responses include only safe finding
digests, typed taxonomy/action disposition, lifecycle/version, repair-outcome
summary, cursor metadata, and audit validity. Unknown and foreign IDs have the
same external `NOT_FOUND` shape in the HTTP tests.

Task 71 dispositions are visible as `BOUND`, `MODEL_UNREACHABLE`,
`COVERED_BY_EXISTING_OPERATION`, `REPORT_ONLY`, and `NOT_APPLICABLE`. Raw
immutable payloads, credentials, private keys, tokens, connection strings,
SQL, source paths, and unbounded exception text are not returned.

## Malformed and report-only behavior

Malformed persisted reconciliation content is not deserialized into repair
inputs. Diagnostics return the bounded `MALFORMED_RECORD` classification;
existing Task 70/71 malformed-row tests remain fail-closed. Report-only and
not-applicable findings are visible with their explicit disposition and cannot
reach an executor.

## File/PostgreSQL and outage behavior

File and PostgreSQL persistence expose the same read-only readiness contract.
The focused tests cover File diagnostics/readiness and PostgreSQL readiness,
explicit pool close/recreation, PostgreSQL diagnostics parity, report-only
visibility, cursor metadata, and exact-scope authorization. `/livez` remains
healthy while PostgreSQL/reconciliation persistence is unavailable; readiness
recovers only after explicit store recreation.

The File adapter remains single-process/single-writer and performs a bounded
directory scan; PostgreSQL orders and bounds rows in SQL. Both expose the same
readiness result vocabulary and diagnostic response shape, while their
locking, durability, and provider behavior remain backend-specific.

## Non-mutation evidence

Metrics scrape, diagnostics reads, readiness checks, audit verification, and
the metrics run observer have tests proving no executor call, cursor advance,
finding lifecycle mutation, rollout mutation, P3A call, or P3E-4 call. The
observer is deliberately isolated from the durable reconciliation result and
cannot turn a committed run into a failed mutation response.

The metrics test distinguishes attempts from semantic outcomes: an applied,
replayed, and conflicted result contributes three attempts/outcomes while the
conflict remains a separate fixed-key subtype. The observer is invoked once per
explicit startup/manual run; no startup observer path creates a second
reconciliation execution.

## Prohibited-scope evidence

The changed observability implementation and tests contain no periodic timer,
background worker, queue, Redis integration, rollout writer, P3A/P3E-4 call,
runtime/mobile/compiler import, provider deployment, alert, dashboard, or
metrics database. The existing `dart:io` server is the only HTTP routing layer.
A changed-scope source scan, Markdownlint, local-link, trailing-space, and
high-confidence secret scan all passed.

## Validation

The following commands were run for Task 72; no Task 71 totals are reused:

- `dart analyze . --fatal-infos` in `packages/control_plane` — PASS;
- `HYFENS_TEST_POSTGRES_URL=... dart test` in `packages/control_plane` — PASS,
  **248 tests passed**, one explicit MinIO/S3 environment skip;
- the focused File/PostgreSQL/HTTP observability command — PASS,
  **11 tests passed**;
- `dart analyze --fatal-infos` at repository root — PASS;
- `dart test` at repository root — PASS, **1 test passed**;
- `dart test test/migration_test.dart` — PASS, **1 test passed**;
- Markdownlint over the Task 72 review, design addendum, ADR, and task file —
  PASS;
- repository-relative Markdown links, trailing whitespace, high-confidence
  secret patterns, and changed-scope prohibited-boundary scans — PASS.

Expected environment skips were not relabeled as passes: the only package
skip was the pre-existing MinIO/S3 integration because its `HYFENS_TEST_S3_*`
environment was not configured. No shell/Python source changed, so syntax
validation for those languages was not applicable.

## Residual limitations

- Metrics are process-local, reset on restart, and are not audit evidence.
- Diagnostics authorization is an explicit host integration seam; this task
  does not mint or persist reconciliation credentials.
- Audit readiness is optional unless the host supplies the existing audit store.
- File remains single-process/single-writer; PostgreSQL provider HA and
  production durability are not implied.
- P1D-01, P1D-03, P1D-04, P1D-07, P1D-09, P1D-18, provider-production, beta,
  production, App Store, Google Play, privacy, and legal gates remain open.

## Next-phase boundary

Stop at this maintainer-review gate. Do not begin P3E5-5D/5E, periodic
workers, queues, Redis, alerts, dashboards, provider deployment, runtime/mobile
work, or store/legal work automatically.

## Task 73 factual addendum (2026-08-24)

Task 73 was executed under a separate explicit P3E5-5D authorization. It adds
an explicitly enabled, disabled-by-default periodic runner around the existing
bounded reconciliation service. The runner has bounded interval/jitter/startup
delay/backoff/shutdown configuration, rejects local overlap, shares the
existing process execution boundary when the host wires it, and does not
create a queue, worker backlog, repair path, rollout writer, or control HTTP
endpoint.

PostgreSQL ownership uses a session-scoped advisory lock on a dedicated
ownership pool, preserving bounded callback access to the persistence pool;
File remains one-process/one-writer. Existing CAS, cursor/fairness,
audit-before-repair, postcondition, exact-scope, report-only, and P3A/P3E-4
boundaries remain authoritative. P3E5-5C metrics and read-only diagnostics
include fixed-key periodic counters and runner status when the same runner
instance is supplied.

The detailed Task 73 evidence, validation totals, residual limitations, and
recommendation are in `docs/P3E5_5D_PERIODIC_RUNNER_REVIEW.md`. This factual
addendum does not rewrite the Task 72 recommendation and does not authorize
P3E5-5E or close provider, beta, production, mobile/runtime, store, privacy,
or legal gates.
