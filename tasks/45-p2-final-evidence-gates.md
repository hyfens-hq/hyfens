# Task 45 — P2 final evidence gates before P3

Status: [x] Completed — bounded evidence execution; maintainer review required

## Goal

Close or explicitly preserve the remaining P2 beta and production evidence
gates without changing Architecture B, Patch Format v1, capability v1, or
starting P3.

## Scope and Non-goals

Scope: create the final evidence record; attempt independent-app validation
only when a genuinely independent application is available; run the current
Android performance campaign; repair and rerun the bounded async benchmark
only if the failure is harness setup; record interpreter attribution and
multi-function evidence; define production signing-key, ingress, object
durability, HA/DR, image-provenance, audit, and store-policy review
boundaries; assess physical iOS diagnostic/performance and true power-loss
availability; run consolidated validation; and update the condition register
and P2 review with exact evidence labels.

Non-goals: changing Patch Format v1, capability v1, high-water or rollback
authority; broadening async/closure semantics; adding JIT/native code
generation; hosting private signing keys; public production deployment;
independent-app substitution with repository fixtures; P3 rollout,
observability ingestion, dashboard, billing, enterprise identity, React
Native, or store submission.

## Owner

Coordinator. No commit is authorized. Stop at the P2 maintainer-review gate.

## Dependencies

- `tasks/44-p2-closure-hardening.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_P2_FINAL_EVIDENCE_GATES_BEFORE_P3.md`;
- `/Volumes/970EvoPlus/Downloads/signing-key-recovery.md`;
- existing Phase 1D condition register, performance protocol, runtime,
  compiler/instrumenter, CLI, control-plane, and physical-device evidence;
- connected Android Wi-Fi and iOS USB devices where available.

## Assumptions

- The conformance and toolchain fixtures are repository-owned and cannot close
  P1D-07 independent-app evidence.
- Existing physical Android/iOS hosted-like evidence remains valid; it is not
  relabelled as post-runtime-change evidence unless runtime/tool code changes.
- True physical power-loss, iOS Developer Disk Image diagnostics, and an
  independent maintained app may be unavailable in this environment.
- Customer/local signing custody remains the P2 boundary; the control plane
  never receives or reconstructs a private key.

## Work Items

- [x] Reserve one final P2 evidence task and preserve the frozen invariants.
- [x] Inspect available independent-app, device, benchmark, and diagnostic
  environments; do not substitute repository fixtures for an independent app.
- [x] Revalidate the established Android performance reducer against the
  retained physical 15-sample campaign, preserving raw evidence and
  historical protocol boundaries; no new device samples are claimed.
- [x] Attempt the bounded async benchmark and repair only fixture/package-root
  setup because the failure was non-semantic; preserve the semantic scope.
- [x] Record interpreter-stage attribution status and multi-function physical
  evidence status without converting host/encoding evidence into physical
  evidence; both remain open.
- [x] Record the production signing-key decision and explicitly distinguish
  control, delivery, and patch-signing compromise boundaries.
- [x] Add bounded public-ingress, object-durability, HA/DR, image-provenance,
  audit-maturity, and store-policy review dispositions.
- [x] Assess true power-loss and iOS diagnostics/performance; leave gates open
  because the required safe environment or diagnostic/profiling evidence was
  unavailable.
- [x] Run consolidated affected validation and update the condition register
  and P2 review with `UNIT`, `INTEGRATION`, `PHYSICAL_ANDROID`,
  `PHYSICAL_IOS`, `PERFORMANCE_ANDROID`, `NOT_RUN`, or
  `ENVIRONMENT_GATED` labels as applicable.
- [x] Stop at maintainer review; do not execute P3.

## Validation

Executed in this task:

- `dart run tool/async_benchmark.dart 1000` and `dart run
  tool/async_benchmark.dart 10000`: PASS after the package-root-only harness
  repair; the 10,000 run produced `patchBytes=1685`, `asyncPoints=2`,
  `codeWords=24`, and the final rerun measured
  `immediateUsPerInvocation=22.1959` with `delayedTotalUs=50445` (the initial
  run measured 31.4326 and 52986 respectively; a verification rerun measured
  21.8602 and 52428). These host timings are not a device performance claim;
- `dart test --concurrency=1 test/async_v6_test.dart
  test/native_aot_async_v6_test.dart`: PASS, 30 tests;
- consolidated suites: instrumentation 205 tests, root 1, conformance Flutter
  18, toolchain Flutter 1, Patch Format 12, control plane 20 with 3 expected
  environment skips, and CLI 39; affected analyzers reported no issues;
- Android reducer self-check and retained-input re-reduction: PASS with
  `MEASURED_WITH_LIMITATIONS`, 15 samples per dispatch variant;
- device audit: Redmi Note 10 Lite reachable at `192.168.50.135:38951` over
  ADB Wi-Fi; iPhone `00008020-001528860E03002E` visible over USB;
- prior Task 35/36/42 physical Android/iOS and Task 44 control-plane,
  backup/restore, TLS, audit, CLI, fixture, and root evidence retained under
  their original evidence labels because no mobile runtime or release
  artifact changed;
- final evidence, condition-register, P2-review, research-log, signing
  recovery, and store-policy documents updated with exact open boundaries.

Skipped or environment-gated: independent maintained app, true physical
power-loss, iOS Developer Disk Image diagnostics, controlled iOS performance,
internal interpreter attribution, and physical multi-function activation.

## Next Action

Maintainer review of the final evidence and explicit decision on whether a
future independent-app/beta evidence task is authorized. No P3 work is
authorized by this task.

## Blockers

P1D-07 independent real application, P1D-01 true physical power-loss,
iOS diagnostics/performance where Developer Disk Image or release profiling
is unavailable, and any unsupported performance/async/multi-function claim
remain blockers for their corresponding beta or production claims.

## Outcome

Bounded final-gate execution completed. P1D-05 is closed only for the
declared physical Android reducer and P1D-08 is closed only for the tested
capability-mediated `Future<int>` subset. Technical P2 single-node
hosted-like evidence is ready for maintainer review. Independent-app,
power-loss, iOS diagnostics/performance, interpreter attribution,
multi-function physical activation, production operations, and store-policy
gates remain open. Recommendation: `CONTINUE P2 MANAGED CLOUD FOUNDATION`;
P3, beta approval, and production approval are not authorized.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_P2_FINAL_EVIDENCE_GATES_BEFORE_P3.md`;
- `/Volumes/970EvoPlus/Downloads/signing-key-recovery.md`;
- `/Volumes/970EvoPlus/Downloads/P2_MANAGED_CLOUD_REVIEW.md`;
- `/Volumes/970EvoPlus/Downloads/44-p2-closure-hardening.md`;
- `tasks/44-p2-closure-hardening.md`;
- `docs/product/phase-1d-conditions.md`;
- `experiments/instrumentation/tool/performance/PROTOCOL.md`.

## History

- 2026-08-23: Reserved Task 45 as the single final-evidence continuation
  after Task 44. P3 and all explicit non-goals remain prohibited.
- 2026-08-23: Completed the bounded gate execution. Repaired only the async
  benchmark fixture-root setup, revalidated the retained Android reducer,
  recorded device/diagnostic availability, updated the P2 review and condition
  register, and stopped at maintainer review with beta/production/P3 gates
  explicitly open where evidence was unavailable.
- 2026-08-23: Task 46 audited the remaining external-gate dependency and found
  no independent maintained Flutter application. The prescribed stop rule was
  followed without creating substitute evidence or changing Task 45 claims.
- 2026-08-23: Task 49 reconciled the status marker with the completed work
  items and outcome. External/provider and store-policy gates remain open.
