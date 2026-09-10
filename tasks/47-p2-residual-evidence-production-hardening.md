# Task 47 — P2 residual evidence and production hardening

Status: [x] Completed — bounded residual evidence executed; maintainer review required

## Goal

Execute the remaining independent P2 evidence gates that can be proved in this
workspace, beginning with a signed multi-function Patch Format v1 activation on
the connected physical Android device. Preserve the frozen Architecture B
runtime/trust boundaries and stop with exact evidence labels for every gate that
requires external ownership, unavailable diagnostics, unsafe destructive testing,
or formal review.

## Scope and Non-goals

Scope: validate one signed multi-function artifact through host preflight,
atomic runtime installation, physical Android activation without reinstall,
restart persistence, invalid-artifact rejection, rollback, and runtime-fault
isolation where the existing conformance harness can prove them; assess internal
interpreter attribution; attempt iOS diagnostics/performance only when the
available device/toolchain can produce valid evidence; perform safe tabletop or
disposable checks for signing, public ingress, object durability, HA/DR,
provenance, and audit boundaries; update the P2 evidence and condition records.

Non-goals: changing Architecture B, Patch Format v1, capability v1, state-v4
high-water or rollback authority, AOT fallback, customer/local signing custody,
or runtime trust boundaries; creating an independent customer application;
hosting private production signing keys; destructive power-loss testing without
a safe controlled setup; P3 rollout/telemetry/dashboard/billing/identity,
React Native, store submission, or production deployment.

## Owner

Coordinator. No commit is authorized. Stop at the Task 47 maintainer-review
gate.

## Dependencies

- `tasks/45-p2-final-evidence-gates.md`;
- `tasks/46-p2-external-production-gates.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_TASK47_P2_RESIDUAL_EVIDENCE_PRODUCTION_HARDENING.md`;
- `/Volumes/970EvoPlus/Downloads/signing-key-recovery.md`;
- `/Volumes/970EvoPlus/Downloads/P2_MANAGED_CLOUD_REVIEW.md`;
- `/Volumes/970EvoPlus/Downloads/p2-final-evidence-gates-2026-08-23.md`;
- connected physical Android and iOS devices when available;
- existing E0 batch runtime, Patch Format v1 bridge, conformance fixture, and
  local control-plane evidence.

## Assumptions

- Repository fixtures remain repository-owned evidence and cannot close the
  P1D-07 independent-app gate.
- The connected Android device is reachable over ADB Wi-Fi and may be used for
  a fresh Task 47 release install followed by one-install patch activation.
- The connected iPhone and signing profile may permit the previously validated
  baseline flow, but Developer Disk Image diagnostics and controlled release
  profiling may remain unavailable.
- A test-only disposable signing key may be used for a tabletop ceremony;
  production/customer private-key custody remains outside this task.
- A true physical power-loss exercise is not inferred from force-stop, reboot,
  or process termination.

## Work Items

- [x] Reserve this task and preserve the frozen runtime, format, capability,
  state, rollback, signing, and P1D-07 boundaries.
- [x] Build or compose one signed Patch Format v1 artifact containing at least
  two supported function slots and run host decode, compatibility, signature,
  and atomic-rejection checks.
- [x] Extend only the test evidence harness as needed to activate that artifact
  on physical Android without reinstall, then verify restart persistence,
  invalid-artifact rejection, rollback, and fault isolation.
- [x] Add bounded internal interpreter attribution hooks or document why they
  cannot be added without changing the frozen runtime; measure only supported
  representative workloads and choose exactly one required attribution result.
- [x] Attempt iOS diagnostics/performance and true physical power-loss only when
  the environment supports safe, reproducible evidence; otherwise record the
  exact `ENVIRONMENT_GATED`, `OPEN`, or `NOT_RUN` boundary.
- [x] Exercise a disposable signing ceremony, public-ingress attack checks,
  object durability/retention design, HA/DR and directional RPO/RTO design,
  SBOM/provenance availability, and narrow audit export/signing only where
  safe and in scope; do not claim production readiness from design alone.
- [x] Update the P2 review, final evidence, condition register, signing-key
  recovery, research log, and focused research documents with exact evidence
  labels and separate technical, beta, production, and store-policy decisions.
- [x] Run consolidated affected validation, review the task-owned diff, and
  stop at maintainer review with one Task 47 recommendation; do not start P3.

## Validation

Planned validation scope:

- focused Dart unit/integration tests for multi-function Patch Format v1 bridge,
  E0 batch installation, malformed input, atomic rejection, rollback, and
  signature/compatibility checks;
- one physical Android release-mode sequence on the connected device with an
  explicit `MULTI_FUNCTION_PHYSICAL_ANDROID` receipt;
- iOS physical validation only if it produces a new Task 47 semantic result;
- scoped analyzers, shell/Python syntax checks, and the affected Flutter/Dart
  fixture tests;
- documentation and evidence consistency checks; no unrelated full matrix.

Skipped checks will be recorded with reason and exact evidence label rather than
treated as passes.

Validation outcome:

- the batch composer analyzed successfully and the host multi-slot/atomicity
  test passed `3/3`;
- full instrumentation tests passed `207` tests, the conformance fixture passed
  `18` tests, the full patch-loading suite passed `59` tests with `2` explicit
  environment-gated skips, and the focused control-plane closure suite passed
  `8` tests;
- the corrected physical receipt checkers passed both
  `MULTI_FUNCTION_PHYSICAL_ANDROID` and `MULTI_FUNCTION_PHYSICAL_IOS`, including
  business, async, widget, tamper rejection, rollback, and persistence claims
  within the declared fixture scope;
- Dart/Flutter analysis, Dart formatting, Python compilation, and shell syntax
  checks passed for the affected files;
- the disposable local ingress checks and signing/tamper checks passed. The
  CLI key-generation/signing round trip timed out under the harness limit and
  remains environment-gated, not a pass;
- true power-loss, iOS Developer Disk Image diagnostics, controlled iOS
  performance, public-edge ingress, provider durability/retention, HA/DR,
  SBOM/provenance, signed off-box audit export, and independent-app evidence
  were not claimed because their required environment or external ownership was
  unavailable.

## Next Action

Maintainer review of the Task 47 evidence and exact open-gate dispositions.
Do not start P3, beta approval, production deployment, or store submission.

## Blockers

Initially none for the Android batch gate. P1D-07 independent-app evidence,
Developer Disk Image diagnostics, controlled iOS profiling, true physical
power-loss, and external review may remain blockers for their own claims.

## Outcome

Completed the bounded residual evidence sequence. Host preflight and atomic
multi-slot tests passed. The physical Android run
(`MULTI_FUNCTION_PHYSICAL_ANDROID`) passed the three-slot business,
async-compatible, and widget lifecycle with one install, restart persistence,
tampered-candidate rejection, rollback, and rollback persistence. The
physical iOS run (`MULTI_FUNCTION_PHYSICAL_IOS`) passed the business, async,
and widget lifecycle and the same rollback/rejection boundary. A leading-slash USB
staging setup failed closed and was corrected to `Documents/...` without
reinstalling; both attempts are documented.

The attribution decision is `INSUFFICIENT ATTRIBUTION`; no optimization was
made. Disposable signing, wrong-key/tamper rejection, local ingress bounds,
and focused lifecycle/security tests passed. True power loss, iOS diagnostics,
iOS performance, production public ingress, provider durability/retention,
HA/DR, SBOM/provenance, signed off-box audit export, and independent-app
evidence remain explicitly open or environment-gated. The four final
decisions are: P2 technical implementation bounded-complete for the declared
scope; beta blocked; production blocked; store-policy/legal external review
required. Task 47 recommendation: **CONTINUE P2 FOR EXTERNAL EVIDENCE**.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK47_P2_RESIDUAL_EVIDENCE_PRODUCTION_HARDENING.md`;
- `/Volumes/970EvoPlus/Downloads/signing-key-recovery.md`;
- `/Volumes/970EvoPlus/Downloads/P2_MANAGED_CLOUD_REVIEW.md`;
- `/Volumes/970EvoPlus/Downloads/p2-final-evidence-gates-2026-08-23.md`;
- `tasks/45-p2-final-evidence-gates.md`;
- `tasks/46-p2-external-production-gates.md`;
- `experiments/instrumentation/lib/e0_runtime.dart`;
- `packages/runtime/lib/runtime.dart`;
- `experiments/patch_loading/lib/src/controller.dart`.

## History

- 2026-08-23: Reserved Task 47 as the single bounded residual-evidence
  continuation. Frozen architecture and trust boundaries remain unchanged;
  P3 remains prohibited.
- 2026-08-23: Completed host multi-function preflight, physical Android and
  iOS lifecycle evidence, attribution assessment, disposable ingress/signing
  checks, documentation addenda, and consolidated validation. Stopped for
  maintainer review; no P3 work started.
