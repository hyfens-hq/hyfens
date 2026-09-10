# Task 41 — Productization P0/P1 foundation

Status: [x] Completed

## Goal

Complete the mandatory productization P0 readiness gates and, only when the
gates are explicitly satisfied without invented maintainer or legal decisions,
implement the smallest local/single-node self-hosted slice: immutable release,
patch, and artifact registration; authenticated update lookup/fetch;
all-or-none promotion; CLI `deploy`; customer/local signing custody; and
basic append-only audit.

## Scope and Non-goals

Scope: P0 gate recording; OSS/commercial and license decision status;
P1D-13 delivery/key-custody contract; single-tenant-compatible domain and
tenant isolation; organization-scoped authentication and minimal scopes;
immutable release/patch/artifact persistence; local artifact storage;
promotion and update eligibility; authenticated delivery; CLI deployment;
idempotency/concurrency; basic audit; local/self-host documentation; security
and end-to-end tests; and the final P0/P1 maintainer review.

Non-goals: selecting a license without maintainer approval; managed KMS/HSM;
hosted cloud; CDN; dashboard; telemetry ingestion; percentage rollout;
cohorts; billing; SSO/SCIM; advanced RBAC; enterprise packaging;
multi-region/HA; production deployment; React Native; store submission; or
changes to Architecture B, Patch Format v1, capability v1, exact release
binding, state-v4 trust/high-water, signed rollback, fail-closed recovery, or
runtime signature authority.

## Owner

Coordinator, with disjoint implementation and security/test packages. No
commit is authorized. Preserve all prior Phase 0/0B/1A/1B/1C/1D evidence and
the Task 40 design package.

## Dependencies

- `/Volumes/970EvoPlus/Downloads/CODEX_PRODUCTIZATION_P0_P1_FOUNDATION.md`;
- `/Volumes/970EvoPlus/Downloads/phase-1d-conditions.md`;
- `/Volumes/970EvoPlus/Downloads/PRODUCTIZATION_DESIGN_REVIEW.md`;
- `docs/PRODUCTIZATION_DESIGN_REVIEW.md`;
- `docs/product/PRODUCTIZATION_PRD.md`;
- `docs/product/phase-1d-conditions.md`;
- `docs/spec/product-api-domain.md`;
- approved productization architecture, security, and ADR documents;
- existing CLI, Patch Format v1, runtime, and fixture implementation.

## Assumptions

- Architecture B, Patch Format v1, capability v1, exact release binding,
  state-v4 trust/high-water, signed rollback, and fail-closed recovery are
  frozen.
- The control plane is cryptographically untrusted and cannot make invalid
  runtime bytes valid.
- The 2026-08-23 maintainer approval record explicitly authorizes Apache-2.0
  OSS-core licensing, the bounded open-core boundary, the P1D-13
  customer/local signing contract, and the Dart `dart:io` single-node stack.
- The approval closed the four implementation gates. Task 42 later closed the
  P1D-02 direct stale-byte gate for the declared physical fixtures; broader
  beta confidence and all other carried Phase 1D conditions remain open.
- The existing development server is not upgraded in place into a product
  service without authenticated persistence and safety tests.
- If a major service framework is required, record the proposed stack and
  stop for maintainer approval before introducing it.
- P1D-01 and P1D-03 through P1D-18 retain their Phase 1D dispositions; this
  task must not silently close or reclassify them.

## P0 Gate Decision Record

Recorded from the explicit maintainer approval record on 2026-08-23. The
historical blocked checkpoint is retained in `History`; the current gate
state below reflects the later approval and authorizes the bounded local
implementation only.

| Gate | Decision | Evidence |
| --- | --- | --- |
| License/governance | APPROVED | `docs/decisions/2026-08-23-task-41-maintainer-approval.md`; Apache-2.0 core, maintainer-led governance, DCO, no CLA initially. |
| OSS/commercial boundary | APPROVED | The same approval record authorizes the open-core list and excludes managed/cloud/enterprise capabilities from Task 41. |
| P1D-13 signing/delivery contract | APPROVED FOR IMPLEMENTATION | Customer/local signing custody, public metadata plus exact signed bytes only, read-only delivery credentials, and runtime-authoritative verification. |
| Dart `dart:io` modular single-node stack | APPROVED | Dart `dart:io` HTTP, filesystem metadata, and content-addressed filesystem artifacts; no major framework or managed dependency. |

The four gates are closed for implementation. Work remains bounded to the
local/single-node P0/P1 slice and must stop at maintainer review before P2.

## Work Items

- [x] Reserve Task 41 and preserve the design/runtime boundaries.
- [x] Record P0 license/governance and OSS/commercial decisions without
  inventing maintainer or legal approval.
- [x] Obtain maintainer approval for the bounded P1D-13 delivery and
  customer/local signing-custody contract.
- [x] Implement the bounded P1D-13 delivery and customer/local
  signing-custody contract in the local control-plane package.
- [x] Define the implementation stack and repository layout without adding a
  major framework without approval.
- [x] Implement tenant-safe persistence, authentication, scopes, immutable
  release/patch/artifact registration, local artifact storage, promotion,
  update lookup/fetch, audit, and CLI `deploy` within the approved scope.
- [x] Add required unit, integration, isolation, immutability,
  idempotency/concurrency, delivery, audit, and fixture end-to-end tests.
- [x] Update implementation/runbook, CLI, security, and carried-condition
  documentation with evidence labels.
- [x] Run affected regressions and create the final 21-section P0/P1 review;
  stop before P2 managed cloud.

## Validation

Planned validation: scoped Dart format and fatal analysis; affected CLI,
Patch Format, runtime, compiler, instrumenter, Flutter integration,
patch-loading, and fixture tests; service unit/integration tests; tenant and
token security tests; artifact immutability; release/patch admission;
delivery filtering; idempotency/concurrency; audit redaction; CLI deploy;
service-outage behavior; local links/whitespace/schema checks; and physical
Android stale-byte evidence only if the delivery seam can provide it safely.
Every result will carry an evidence label (`UNIT`, `INTEGRATION`,
`END_TO_END_LOCAL`, `PHYSICAL ANDROID`, `PHYSICAL IOS`, `NOT RUN`, or
`ENVIRONMENT-GATED`).

Original checkpoint validation on 2026-08-23 (preserved historical record):

- `packages/control_plane`: `dart analyze` passed; `dart test` passed (7
  tests; `UNIT`/`INTEGRATION` coverage for auth, tenant boundaries,
  immutability, exact release admission, Ed25519 verification/quarantine,
  promotion, delivery, audit, idempotency, and concurrency).
- `cli`: `dart analyze` passed; full `dart test` passed (38 tests), including
  the registered credential-safe `deploy` command (`UNIT`/`INTEGRATION`).
- Dependent runtime packages: `packages/patch_format` analyzed cleanly and
  passed 12 tests; `packages/runtime` analyzed cleanly and passed 5 tests;
  `experiments/patch_loading` analyzed cleanly and passed 59 tests (2 existing
  skips); and `packages/flutter_integration` analyzed cleanly and passed 8
  tests (`UNIT`/`INTEGRATION`).
- Repository root: `dart analyze` passed; `dart test` passed (1 test).
- Formatter: `dart format --output=none --set-exit-if-changed` passed for the
  affected Dart source and tests.
- Temporary local service plus existing signed Flutter fixture artifact:
  release/patch registration, signature admission, content-addressed storage,
  promotion, authenticated lookup, and byte-for-byte fetch passed
  (`END_TO_END_LOCAL`).
- Physical Android/iOS activation through the new authenticated service API,
  direct stale-byte rejection, and service-outage runtime behavior: `NOT RUN`.

Task 42 follow-up evidence on 2026-08-23 superseded only the last line at the
original checkpoint: host and local service E2E passed; a generated stock
Flutter iOS arm64 Release installed once on the physical AUVANA-signed iPhone,
authenticated lookup/fetch changed the ordinary pricing receipt 540→450,
restart and service-outage retention passed, and the direct iOS USB run
rejected exact stale sequence-4 bytes after rollback with BASE/high-water 4
preserved. At that original checkpoint the authenticated Android path was
`ENVIRONMENT-GATED` because ADB/mDNS exposed no device. The later Android
transport restoration and completion are recorded in the Task 42 history
entry below; no result is inferred from iOS.

Final closure validation on 2026-08-23:

- `dart format --output=none --set-exit-if-changed` passed for 89 affected
  Dart files (0 changes).
- Root and affected analysis passed. Pure-Dart packages also passed
  `dart analyze --fatal-infos`; the Flutter fixture's fixture-only receipt log
  is explicitly suppressed as `avoid_print`.
- Tests passed serially: `packages/control_plane` 7; `cli` 39;
  `experiments/patch_loading` 59 passed with 2 existing skips;
  `packages/flutter_integration` 17; `packages/compiler` 1;
  `packages/instrumenter` 2; `packages/patch_format` 12;
  `packages/runtime` 5; Flutter fixture 18; repository root 1.
- Shell syntax (`bash -n`) and Python AST syntax checks passed. Markdown link
  and trailing-whitespace checks passed after removing one pre-existing
  trailing-space error in the maintainer approval record.
- Credential/private-material scans passed for release metadata, patch
  artifacts, recorded evidence, audit payloads, runtime diagnostics, and
  documentation. Evidence remains redacted; test-only sentinel values are not
  release credentials.
- `PHYSICAL ANDROID` and `PHYSICAL IOS` Task 42 evidence remains consistent:
  authenticated delivery, restart persistence, service-outage retention,
  rollback, and direct stale-byte rejection passed on the declared fixtures.

Task 41 final current state: the bounded local/single-node P0/P1 slice is
complete and stops for maintainer review. Architecture B, Patch Format v1,
capability v1, exact release binding, state-v4 trust/high-water, signed
rollback, fail-closed recovery, runtime signature authority, and AOT fallback
are unchanged. No P2/cloud work is authorized by this task.

## Next Action

Stop for maintainer review. Task 41 is complete for the bounded local/single-
node P0/P1 scope. Propose—but do not execute—the next phase only after review.

## Blockers

- No blocker remains for the bounded local P0/P1 implementation.
- P1D-02 direct physical stale-byte rejection is closed for both declared
  Android and iOS fixtures. Broader beta confidence still requires the
  remaining durability, performance, and independent-application evidence;
  server-side withholding remains insufficient by itself.
- P1D-13 bounded local/self-hosted physical delivery and runtime evidence is
  satisfied. Hosted/production key custody, rotation/revocation, operations,
  and availability evidence remain open.
- Carried Phase 1D iOS, power-loss, performance, independent-app, and
  store-policy conditions remain unchanged.

These are P0 gates, not reasons to invent decisions or weaken the runtime.

## Outcome

The four P0/P1 gates are explicitly approved and the repository license and
governance record are applied. The bounded local/single-node control-plane
foundation, authenticated runtime delivery, physical Android/iOS evidence,
and consolidated regression are complete. Task 41 stops at maintainer review;
P2 managed cloud remains unexecuted and prohibited until separately approved.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_PRODUCTIZATION_P0_P1_FOUNDATION.md`;
- `/Volumes/970EvoPlus/Downloads/phase-1d-conditions.md`;
- `/Volumes/970EvoPlus/Downloads/PRODUCTIZATION_DESIGN_REVIEW.md`;
- `docs/PRODUCTIZATION_DESIGN_REVIEW.md`;
- `docs/product/phase-1d-conditions.md`;
- `docs/spec/product-api-domain.md`;
- `docs/security/productization-threat-model.md`;
- `docs/architecture/control-plane.md`;
- `docs/architecture/self-hosted-operations.md`;
- `tasks/40-productization-design.md`;
- `packages/control_plane/`;
- `docs/product/local-control-plane.md`;
- `docs/decisions/2026-08-23-task-41-maintainer-approval.md`;
- `/Volumes/970EvoPlus/Downloads/TASK_41_MAINTAINER_APPROVAL_AND_BLOCKER_CLOSURE.md`;
- `tasks/42-productization-runtime-delivery-integration.md`;
- `docs/research/evidence/task42-android-control-plane.md`;
- `docs/research/evidence/task42-ios-control-plane.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_TASK41_FINAL_P0_P1_CLOSURE.md`;

## History

- 2026-08-23: Task 41 reserved as the next unused task number for the
  productization P0/P1 foundation after the Task 40 design review.
- 2026-08-23: Initial repository audit found the license/governance,
  OSS/commercial, and P1D-13 ownership decisions unresolved. The existing
  `cli serve` remains development-only and no product implementation was
  started while those gates are recorded.
- 2026-08-23: Completed the 21-section P0 readiness review. The task is
  blocked pending explicit maintainer/legal decisions; no service, schema,
  authentication, deployment, cloud, or product infrastructure was added.
- 2026-08-23: Re-audited the supplied approval/resume instruction. Its
  recommended choices were not treated as approvals; all four P0 gates were
  recorded explicitly as `MAINTAINER DECISION REQUIRED`, so implementation
  remains blocked.
- 2026-08-23: Received the explicit maintainer approval record. The four
  gates are now `APPROVED`/`APPROVED FOR IMPLEMENTATION`; the historical
  blocked checkpoint is preserved and the bounded local implementation is
  resumed. P2/cloud work remains prohibited.
- 2026-08-23: Added the Apache-2.0 governance record and the first
  `packages/control_plane` local service slice. Scoped package unit/HTTP
  tests passed for signing, exact identity, tenant boundaries, credentials,
  persistence, promotion, delivery, audit, idempotency, and concurrency.
- 2026-08-23: Ran one `END_TO_END_LOCAL` CLI deployment against a temporary
  local service using an existing signed Flutter artifact. Registration,
  admission, content-addressed storage, promotion, authenticated lookup, and
  byte-for-byte fetch passed. No physical Flutter runtime activation through
  the new service API was claimed; P1D-02 remains open.
- 2026-08-23: Consolidated validation passed: the control-plane package
  analyzed cleanly and passed 7 tests, the full CLI analyzed cleanly and
  passed 38 tests, the repository analyzed cleanly and passed its bootstrap
  test, and affected Dart formatting reported no changes. Security and review
  documents now distinguish this local evidence from physical/runtime and
  production gates; Task 41 remains in progress and P2/cloud work remains
  prohibited.
- 2026-08-23: Task 42 added the authenticated Flutter delivery adapter,
  redacted runtime build defines, host/service integration tests, and a
  generated physical iOS service-path run. The previous `NOT RUN` statement is
  retained as historical evidence; the new iOS observations are recorded as
  bounded `PHYSICAL IOS` evidence and Android remains environment-gated.
- 2026-08-23: Task 42's Android transport was restored. The explicit Wi-Fi
  device passed both the direct stale-byte/cross-feature sequence and the
  generated authenticated `tool release android` → `tool patch` → `tool deploy`
  path, including restart and service-outage retention. The historical
  environment-gated statement above is preserved; current bounded Android and
  iOS evidence is recorded in Task 42 and its redacted platform evidence
  records. P2/cloud work remains prohibited.
- 2026-08-23: Final Task 41 closure reconciled the current P0/P1 state with
  Task 42. Authenticated Android and iOS delivery, restart persistence,
  service-outage retention, rollback/high-water, and direct stale-byte
  rejection are recorded as bounded physical evidence; P1D-02 is closed for
  the declared fixtures and P1D-13 is satisfied for the bounded local/
  self-hosted path. The consolidated regression passed and Task 41 is now
  `Completed`; remaining Phase 1D conditions and the P2 boundary are
  preserved.
