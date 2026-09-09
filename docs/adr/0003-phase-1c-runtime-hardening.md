# ADR 0003: Phase 1C runtime hardening

- Status: Accepted for implementation
- Date: 2026-08-22
- Decision scope: Phase 1C runtime-hardening milestone

## Decision

Phase 1C retains Architecture B as the Phase 1 baseline:

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

The milestone will harden the existing runtime and local toolchain around
failure safety, adversarial inputs, diagnostics, recovery, trust/key
lifecycle, performance evidence, and bounded Flutter/Dart version resilience.
It does not increase product scope or redesign the source-instrumentation
architecture.

## Invariants retained

- Patch Format v1 remains normative and unchanged, including its canonical
  encoding, digest/signature boundary, identity semantics, and bounds.
- Capability contract v1 remains closed and release-owned; no arbitrary host
  reflection, native enumeration, or unrestricted host-object access is added.
- Exact application/release/runtime compatibility and signed activation remain
  mandatory.
- Native AOT remains the fallback for unpatched code.
- Anti-replay high-water protection remains monotonic across rollback,
  recovery, cleanup, and key lifecycle changes.
- Durable private app-support storage remains the only runtime lifecycle store;
  recovery may conservatively select base or last-known-good.

## Scope

Phase 1C will formalize lifecycle states and invariants, inject deterministic
I/O/process failures, harden candidate/current/last-known-good recovery and
boot-loop behavior, enforce interpreter resource budgets, isolate runtime
errors, provide source-mapped diagnostics, fuzz parsers/verifiers/interpreter
and lifecycle metadata, test capability abuse, and define bounded key
rotation/revocation/recovery. It will also record physical runtime
measurements and adjacent SDK compatibility evidence.

## Explicit non-goals

No hosted backend, production transport, CDN, dashboard, accounts,
organizations, billing, rollout system, enterprise features, React Native,
store-compliance certification, Flutter/Dart fork, Kernel transformation, or
Phase 1D work is part of this decision.

## Pivot triggers

The implementation must stop for maintainer review if evidence shows that:

- base/last-known-good cannot be recovered after interrupted transitions;
- anti-replay must be weakened for rollback or recovery;
- key rotation requires unsafe trust bootstrap;
- parser/verifier/runtime fuzzing exposes systemic unsafety;
- resource limits are structurally bypassable;
- patch failures repeatedly crash the host process;
- source mapping requires an incompatible Patch Format v1 change;
- adjacent SDK drift makes source instrumentation unsustainable;
- physical platform behavior diverges materially; or
- acceptable runtime overhead requires an architecture or SDK fork.

## Consequence

Phase 1C may add internal runtime state/diagnostic/test seams and authenticated
non-critical metadata only where the existing v1 protocol permits it. A
required protocol change is not to be hidden in hardening work: it requires a
separate explicit format-version decision and maintainer review. At the end
of Phase 1C, work stops at `docs/PHASE_1C_REVIEW.md`; Phase 1D is not started
automatically.
