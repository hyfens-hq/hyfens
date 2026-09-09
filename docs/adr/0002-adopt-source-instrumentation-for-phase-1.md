# ADR 0002 — Adopt source instrumentation as the Phase 1 baseline

- Status: Accepted for Phase 1A implementation
- Date: 2026-08-22
- Decision owners: Maintainers

## Context

Phase 0B completed the approved research boundary and concluded:

**PROCEED TO PHASE 1 WITH CONDITIONS**

The current evidence validates a bounded Architecture B flow on physical
Android and iOS release builds:

```text
ordinary Flutter/Dart source
        ↓
automatic build-time source instrumentation
        ↓
normal Flutter AOT fallback
        +
bounded patch dispatch
        ↓
signed interpreted patch runtime
```

The evidence does not establish arbitrary Dart or Flutter semantics. It does
establish that the source-instrumentation seam can preserve ordinary developer
source, retain the original AOT implementation, and dispatch selected signed
patches without a Flutter fork, Dart fork, PatchView, per-function annotation,
or manually rewritten call sites.

The prior research ADR, `0002-continue-source-instrumentation-with-phase-1-
gates.md`, remains preserved as a historical Phase 0B recommendation and is
not rewritten by this decision.

## Decision

Adopt Architecture B — automatic build-time source instrumentation with normal
Flutter AOT fallback and bounded signed patch dispatch — as the selected
baseline for Phase 1.

Phase 1A will deepen the existing typed compiler/interpreter, capability
authority, identity/manifest, and signing seams. It will not reconsider the
architecture, start a Kernel/compiler integration, fork Flutter or Dart, or
start Phase 2/cloud/product work without new evidence and maintainer review.

## Conditions

- Support remains an explicit subset of Dart and Flutter, with false negatives
  preferred over unsafe false positives.
- Every patch targets an exact application release and runtime/format
  compatibility record.
- The host surface is a closed, versioned capability authority; patches cannot
  reflect over arbitrary host objects or enumerate native APIs.
- Phase 1A stops for review before Phase 1B toolchain work.
- Physical-device evidence, benchmarks, policy research, and generated
  artifacts from Phase 0/0B remain archival evidence and are not replaced by
  this ADR.

## Consequences

Phase 1 owns a source transformer, bounded language compiler/interpreter,
release baseline manifest, patch protocol, capability ABI, and recovery/trust
contracts. The normal Flutter build remains the AOT fallback. Unsupported
syntax, changed native/build inputs, and incompatible release metadata must
fail clearly and require a store release.

This is the selected Phase 1 architecture, not a permanent prohibition against
future Kernel/compiler integration. A future Kernel or compiler integration
would require new evidence, a bounded comparison, and an explicit maintainer
decision; it is not part of this task.

## Evidence

- [Phase 0B review](../history/reviews/PHASE_0B_REVIEW.md)
- [Phase 0B findings](../architecture/phase-0b-findings.md)
- [Dart support matrix](../dart-support-matrix.md)
- [Instrumentation results](../../experiments/instrumentation/RESULTS.md)
- [Physical iOS feasibility](../research/ios-feasibility.md)
- [Historical Phase 0B ADR](0002-continue-source-instrumentation-with-phase-1-gates.md)

## History

- 2026-08-22: Created for Phase 1A implementation after the maintainer
  supplied the Phase 0B conclusion and required Architecture B baseline.
