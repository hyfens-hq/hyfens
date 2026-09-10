# Task 51 — Physical iOS diagnostics and performance rerun

Status: [x] Completed — bounded iOS diagnostic/startup/profile evidence captured; broad resource and throughput claims remain open

## Goal

Re-open only the previously environment-gated iOS evidence now that the
maintainer has made the unlocked USB iPhone available. Determine whether the
Developer Disk Image/runtime diagnostic channel is usable and, if so, collect a
controlled physical iOS stock/instrumented/active-patch performance series.
Update P1D-03 and P1D-04 only from captured evidence.

## Scope and Non-goals

Scope: audit the connected iPhone and AUVANA signing context; use the existing
`xcodebuildmcp` device workflow and conformance fixture; attempt diagnostic/log
collection; measure comparable stock, instrumented-unpatched, and active-patch
behavior with explicit device/run provenance; preserve raw evidence; and update
the P2/Phase-1D condition records conservatively.

Non-goals: changing Architecture B, Patch Format v1, capability v1, runtime
verification, high-water, signing custody, rollback, P3A, provider deployment,
independent-app evidence, true power-loss, store/legal review, or production
claims. No destructive device operation is authorized.

## Owner

Coordinator. No commit is authorized. Stop after the evidence/gate review.

## Dependencies

- `tasks/50-p3a-rollout-domain-and-eligibility.md`;
- `tasks/47-p2-residual-evidence-production-hardening.md`;
- `tasks/45-p2-final-evidence-gates.md`;
- `docs/product/phase-1d-conditions.md`;
- `docs/P2_MANAGED_CLOUD_REVIEW.md`;
- `docs/research/phase-1d-performance.md`;
- `scripts/e1_ios_physical.sh` and `scripts/e1_ios_cross_feature.sh`;
- unlocked USB iPhone and AUVANA VENTURES PRIVATE LIMITED signing profile.

## Assumptions

- The conformance fixture remains repository-owned evidence and cannot close
  the independent-app gate.
- A successful build/install or app-support receipt does not by itself close
  the diagnostic gate; a real diagnostic channel and reproducible runtime
  observations must be recorded.
- Performance results are device/run-specific and must not be extrapolated to
  all iOS devices or store builds.
- The XcodeBuildMCP workflow is the approved build/install/launch boundary;
  no raw `xcodebuild`, `xcrun`, or `simctl` workflow will be substituted.

## Work Items

- [x] Reserve Task 51 and preserve the P3A/P2 frozen boundaries.
- [x] Audit the unlocked iPhone, CoreDevice identity, signing team, build
  settings, and diagnostic availability.
- [x] Attempt a bounded physical iOS diagnostic/log/UI observation and record
  the exact result or environment gate.
- [x] Run a controlled stock/instrumented-unpatched/active-patch performance
  series where the available physical workflow exposes reliable timings;
  record skipped dimensions rather than inferring them.
- [x] Preserve raw evidence with run IDs, hashes, commands, device/OS, and
  configuration; do not overwrite historical evidence.
- [x] Update P1D-03/P1D-04 and the P2 review/research log only from evidence.
- [x] Run scoped documentation and affected validation, review the task-owned
  changes, and stop at maintainer review.

## Validation

Planned commands include XcodeBuildMCP help/device/build/install/launch
commands, the existing iOS evidence workflow, any bounded profiling command
that is available through the approved tool boundary, and repository checks
for changed documentation/scripts. No App Store, Google Play, production, or
legal-compliance claim may be made by this task.

Executed commands, raw evidence paths, sample counts, diagnostic channel,
skips, and final gate labels are recorded in
`docs/research/ios-gate-rerun-2026-08-23.md`.

Validation results:

- `scripts/e1_ios_physical.sh` completed with exit `0`; the receipt checker
  confirmed all ten stages, three process groups, one install, signed patch
  activation/persistence, invalid-signature rejection, rollback, replay
  rejection, and rollback persistence.
- `xcodebuildmcp device list --output json` reported the named iPhone as
  `connected` and `isAvailable: true`; retained physical Release builds and
  installs returned `SUCCEEDED`.
- `xctrace export --toc` succeeded for the three Time Profiler and three App
  Launch traces. The JSON lifecycle/performance reductions parsed and passed
  consistency assertions.
- `bash -n scripts/e1_ios_physical.sh` and changed-document hygiene checks
  passed. No runtime source or signing configuration was changed.
- The Allocations trace was captured but did not provide a usable numeric
  RSS/heap result; thermal, battery, soak, and hot dispatch-throughput checks
  were intentionally recorded as open rather than inferred.

## Next Action

Stop for maintainer review. If broader iOS performance claims are required,
authorize a separate resource/thermal/battery/soak and controlled
dispatch-throughput campaign; do not begin another P3 slice from this task.

## Blockers

The old environment blocker is cleared for the named iPhone XR/iOS 18.7.9
run: a personalized Developer Disk Image was mounted and `idevicesyslog`
captured Runner and Flutter process observations. P1D-04 remains intentionally
partial because the Allocations trace did not yield usable numeric RSS/heap
data, and no thermal/battery/soak or controlled dispatch-throughput campaign
was run. Independent-app, true-power-loss, provider, and store/legal gates are
outside this task and remain open.

## Outcome

The iOS rerun produced a successful physical Release lifecycle with one app
install, patch activation/persistence, invalid-signature rejection, rollback,
stale/replay rejection, and restart persistence. It also produced bounded
diagnostic, Time Profiler, App Launch, and binary-size evidence for stock,
instrumented-unpatched, and active-patch variants. P1D-03 is closed for the
declared device/toolchain scope. P1D-04 is closed only for the declared
startup/CPU-profile subset; resource, throughput, soak, and broad beta claims
remain open. P2/P3A status and all other external gates are unchanged.

## References

- `docs/product/phase-1d-conditions.md`;
- `docs/P2_MANAGED_CLOUD_REVIEW.md`;
- `docs/research/phase-1d-performance.md`;
- `tasks/47-p2-residual-evidence-production-hardening.md`;
- maintainer instruction that the unlocked iPhone is available (2026-08-23).
- `docs/research/ios-gate-rerun-2026-08-23.md`;
- `fixtures/flutter_conformance_app/.dart_tool/task51-ios-20260823-165433/evidence/`;
- `fixtures/flutter_conformance_app/.dart_tool/e1_ios_runs/task51-ios-20260823-physical/evidence/`.

## History

- 2026-08-23: Reserved after the maintainer made the unlocked USB iPhone
  available to rerun the previously environment-gated iOS diagnostics and
  performance evidence. P3A remains unchanged and later P3 work remains
  stopped.
- 2026-08-23: Completed the physical rerun. Developer Disk Image diagnostics,
  one-install Release lifecycle, tamper/replay rejection, rollback, startup
  lifecycle, Time Profiler, and binary-size evidence passed within the declared
  fixture/device boundary. Recorded P1D-03 as bounded closed and P1D-04 as
  bounded partial; stopped for maintainer review.
