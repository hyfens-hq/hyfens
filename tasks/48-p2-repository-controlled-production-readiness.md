# Task 48 — P2 repository-controlled production readiness

Status: [x] Completed — bounded repository-controlled checklist closed; maintainer review required

## Goal

Close or narrow the remaining P2 production-readiness gates that this
repository and disposable local environment can actually prove. Keep those
results separate from independent-app, provider, destructive-device,
Apple-tooling, and store/legal gates.

## Scope and Non-goals

Scope: add a disabled-by-default interpreter attribution seam; implement and
verify a separate signed/off-box audit-export envelope; define and test the
local ingress trust boundary; rehearse disposable two-instance application
HA and dependency ambiguity; create one reproducible directional DR rehearsal;
attempt bounded SBOM/provenance generation; publish production configuration,
secret lifecycle, incident, and operator runbook contracts; classify the Task
47 CLI signing timeout; and update the P2 evidence records.

Non-goals: changing Architecture B, Patch Format v1, capability v1, exact
release/function binding, state-v4 high-water or rollback authority, runtime
signature custody, AOT fallback, or installed-runtime independence; adding a
Flutter/Dart fork, Kernel transformation, JIT/native compilation, P3 rollout,
dashboard, telemetry backend, billing, managed KMS/HSM, Kubernetes,
multi-region infrastructure, store submission, or legal approval.

## Owner

Coordinator. No commit is authorized. Stop at maintainer review.

## Dependencies

- `tasks/47-p2-residual-evidence-production-hardening.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_TASK48_P2_REPOSITORY_CONTROLLED_PRODUCTION_READINESS.md`;
- `/Volumes/970EvoPlus/Downloads/p2-production-hardening-2026-08-23.md`;
- `/Volumes/970EvoPlus/Downloads/P2_MANAGED_CLOUD_REVIEW.md`;
- existing control-plane, Patch Format, runtime, backup, Compose, and proxy
  fixtures.

## Assumptions

- Task 47 physical Android/iOS and multi-slot evidence remains valid because
  this task is measurement/operations-focused and does not change runtime
  semantics.
- Disposable local PostgreSQL, MinIO, proxy, and container tooling may be
  used when available; local simulation cannot close provider production
  claims.
- Test-only Ed25519 material may be generated locally for audit exports, but
  it must remain distinct from patch-signing and delivery credentials.
- A missing external tool or provider is recorded as `ENVIRONMENT_GATED`, not
  silently replaced by a stronger claim.

## Work Items

- [x] Add a semantics-neutral, disabled-by-default interpreter stage profiler
  and benchmark supported representative workloads with profiler overhead.
- [x] Choose and record exactly one attribution decision; do not optimize when
  stage attribution remains insufficient.
- [x] Implement deterministic signed audit-export envelopes with offline
  verification and tamper/identity tests; keep audit-export trust separate.
- [x] Define and test forwarded-header, host, request-ID, direct-access, and
  route-exposure behavior at the local ingress boundary.
- [x] Rehearse disposable two-instance application HA, failover, rolling
  restart, idempotent retry, and dependency ambiguity without claiming
  database/object-provider HA.
- [x] Create and execute a canonical directional DR rehearsal using exact
  backup/restore/reconciliation/verification steps and timings.
- [x] Attempt repository-owned SBOM and bounded image provenance generation;
  preserve exact tool/environment limitations.
- [x] Add production configuration and secret-lifecycle contracts, signing
  incident rehearsal, and operator runbook procedures with evidence labels.
- [x] Classify the Task 47 CLI signing timeout without relabelling it as a
  pass, and fix only a demonstrated narrow defect if one exists.
- [x] Update P2 review, condition register, research log, and focused reports
  with five separate readiness decisions; do not start P3.
- [x] Run consolidated affected validation, review the task-owned changes, and
  stop at maintainer review.

## Validation

Planned validation scope:

- attribution unit/benchmark self-checks and profiler-on/off overhead;
- audit-export signing, offline verification, tamper, wrong-key, and chain
  immutability tests;
- ingress forwarded-header and route-contract tests;
- disposable HA integration, dependency ambiguity, and DR rehearsal;
- SBOM/provenance digest verification when tooling permits;
- configuration/runbook/secret scans plus Dart, Flutter, Python, shell, and
  Markdown checks for affected files.

Record exact counts, skips, evidence labels, and external/environment-gated
boundaries. If runtime semantics change, apply Task 48's physical regression
rule before completion.

Validation outcome:

- Stage-2 attribution self-check passed. The final run used macOS arm64/Dart
  3.13.0, five samples, one warmup, and 1,000 iterations over six supported
  workloads; the exact decision was `ATTRIBUTION STILL INSUFFICIENT` and no
  optimization was made.
- Signed audit export focused tests passed `3/3`; local offline copy,
  deterministic bytes, tamper, wrong-key, identity, malformed-envelope, and
  invalid-chain cases are covered.
- Local ingress focused tests passed `4/4`; the full control-plane suite passed
  `27` tests with `3` explicit dependency-environment skips. The final ingress
  run includes duplicate/oversized forwarded values and invalid request IDs.
- `APPLICATION_HA_DISPOSABLE` passed with both instances ready, idempotent
  write retry, proxy lookup/fetch, one-instance loss, rolling restart,
  PostgreSQL/object outage and recovery, and audit-chain verification. The
  rehearsal found and fixed a concurrent PostgreSQL migration race using a
  transaction-scoped advisory lock. Recorded timings are in the HA/DR report.
- `DISASTER_RECOVERY_DIRECTIONAL` passed locally: exact PostgreSQL/object
  backup, disposable destroy/recreate, explicit restore, reconciliation,
  audit verification, and artifact digest-preserving fetch. The restored
  artifact digest was
  `sha256:2aaba1e9f807edb65a59c62f834a0d040c60ffc5ad557232a08f0ef45f4ac1d6`.
- Containerized Syft `1.51.0` produced a local SPDX `2.3` inventory with 135
  packages. The bounded provenance manifest recorded source, Dockerfile, and
  local image digests; vulnerability scanning, registry attestation, and
  provider provenance remain unavailable/open.
- The CLI signing round-trip is classified `SLOW BUT CORRECT`. Direct keygen
  and sign exited normally; the focused test passed `1/1` in 37.81s and the
  full signing test passed `4/4` in 83.14s after an explicit two-minute
  test-package timeout. No leak or CLI regression was reproduced.
- Consolidated tests passed: root `1`, Patch Format `12`, runtime `6`,
  compiler `1`, instrumenter `3`, Flutter integration `18`, instrumentation
  `207`, patch-loading `59` with `2` explicit CLI-environment skips, CLI `39`,
  conformance Flutter `18`, and toolchain Flutter `1`. Affected analyzers,
  Dart formatting, shell syntax, Python syntax, and Compose config all passed.
- Task 47 physical Android/iOS evidence was retained without rerun because
  the attribution seam is opt-in, disabled on production dispatch, and
  semantics-neutral; the full instrumentation and Flutter integration suites
  passed after the source change.
- Markdownlint passed with the repository's intentional wide-table `MD013`
  exception; private-key markers and credential-pattern scans returned none.

## Next Action

Maintainer review of the bounded repository-controlled closure. Supply the
external/provider evidence listed under Blockers before making beta or
production claims. Do not begin P3.

## Blockers

External gates are intentionally not blockers for repository-owned work but
remain open: P1D-01 physical power loss, P1D-03 iOS diagnostics, P1D-04 iOS
performance, P1D-07 independent app, P1D-18 store/legal review, public
provider/edge infrastructure, production secret management, and approved
SLO/RPO/RTO.

## Outcome

Task 48 closed the repository-controlled checklist to its declared
single-node/self-hosted boundary. The final five decisions are:

1. P2 technical implementation — `BOUNDED COMPLETE` for the declared scope
   and retained Android+iOS fixture evidence.
2. Beta readiness — `BLOCKED` by the independent-app and claim-specific
   platform gates.
3. Repository-controlled production readiness — `PASSED — BOUNDED` for the
   executed Task 48 checklist; P1D-09 itself remains open because attribution
   is still insufficient.
4. External/provider production readiness — `BLOCKED` pending public-edge,
   provider durability/HA/DR, approved SLO/RPO/RTO, image attestation,
   production secret/key custody, and operational evidence.
5. Store-policy/legal readiness — `EXTERNAL REVIEW REQUIRED`.

No P3 functionality, cloud control plane, store submission, Flutter/Dart fork,
JIT, or trust-boundary weakening was introduced. Stop at maintainer review.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK48_P2_REPOSITORY_CONTROLLED_PRODUCTION_READINESS.md`;
- `/Volumes/970EvoPlus/Downloads/p2-production-hardening-2026-08-23.md`;
- `/Volumes/970EvoPlus/Downloads/P2_MANAGED_CLOUD_REVIEW.md`;
- `tasks/47-p2-residual-evidence-production-hardening.md`.
- `docs/research/p2-interpreter-attribution-2026-08-23.md`;
- `docs/research/p2-audit-export-signing-2026-08-23.md`;
- `docs/research/p2-ingress-trust-boundary-2026-08-23.md`;
- `docs/research/p2-application-ha-dr-2026-08-23.md`;
- `docs/research/p2-sbom-provenance-2026-08-23.md`;
- `docs/research/p2-cli-signing-timeout-2026-08-23.md`.

## History

- 2026-08-23: Reserved Task 48 as the single bounded repository-controlled
  production-readiness continuation. Task 47 evidence and frozen invariants
  remain unchanged; P3 remains prohibited.
- 2026-08-23: Added stage attribution, signed/off-box audit export, local
  ingress contract/tests, disposable HA and DR rehearsals, bounded
  SBOM/provenance, configuration/secret/incident/runbook records, and the
  CLI timeout classification. Consolidated validation passed; external and
  provider gates remain open. Stopped for maintainer review.
- 2026-08-23: Self-review tightened the audit envelope to reject unknown
  fields, bind first/last sequence and record-count metadata, and recompute
  the signed chain verification. Focused and full control-plane validation
  passed again.
