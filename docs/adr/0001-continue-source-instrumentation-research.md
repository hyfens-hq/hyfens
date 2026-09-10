# ADR 0001 — Continue source-instrumentation research before considering a fork

- Status: Accepted for Phase 0B research; not a production architecture decision
- Date: 2026-08-22
- Decision owners: Maintainers after review

## Context

The project needs transparent updates to ordinary Flutter/Dart code, interpreted
or data-driven downloaded content, Android and iOS support, and a fully open
self-hostable runtime. Phase 0 compared explicit patch views, automatic source
instrumentation, Kernel transformation, and a Flutter/Dart toolchain fork.

E0 and E1 proved one narrow source-instrumented function can dispatch between
bundled AOT and interpreted data on stock Dart/Flutter, including a physical
Android no-reinstall sequence. They did not prove broad language semantics,
multi-file build fidelity, iOS, production security, or store eligibility.

## Decision

If maintainers authorize Phase 0B, continue Architecture B using an
analyzer-guided ephemeral source overlay and callee-entry guards. Keep the guest
runtime capability-limited and derive its instruction set from conformance
cases. Do not fork Flutter/Dart and do not select a production patch container.

Architecture C receives a bounded pre-TFA Kernel spike only if source-overlay
fidelity, build-graph integration, or source mapping fails defined exit criteria.
Architecture A remains an explicit-UX fallback. Architecture D requires separate
maintainer approval after B/C fail explicit thresholds and after accepting its
permanent upstream-maintenance burden.

## Conditions

- The Phase 0B plan must be approved before implementation.
- Every added Dart construct needs compiler, VM, malformed-input, and fallback
  tests; unsupported constructs must fail explicitly.
- A closed, versioned host-capability registry must precede plugin or platform
  access.
- Signing, replay/downgrade defense, and crash-loop health are required before
  any remote or production-shaped delivery.
- Physical iOS execution and Apple policy review remain independent gates.
- Overhead, code size, startup, load, verification, memory, and patch size must
  be measured on representative cases before broad-instrumentation claims.

## Consequences

This direction preserves a stock toolchain and the preferred developer-source
experience while testing the largest known risks cheaply. It also means the
project owns a source transformer, bounded Dart compiler/interpreter, capability
ABI, verifier, and source-map story. Phase 0 evidence cannot be generalized to
arbitrary Dart or production OTA deployment.

## Alternatives considered

- Explicit patch views: feasible and contained, but fails transparent existing-
  application integration.
- Kernel transformation: semantically attractive, but no supported pre-TFA
  third-party seam was found and upstream internals are revision-sensitive.
- Flutter/Dart fork: highest semantic ceiling and a proven architecture class,
  but carries the greatest maintenance and audit burden.

## Evidence

- [Architecture comparison](../architecture/options.md)
- [E0 results](../../experiments/instrumentation/RESULTS.md)
- [E1 Android results](../../experiments/patch_loading/RESULTS.md)
- [Flutter AOT map](../research/flutter-aot.md)
- [Phase 0 initial review](../history/reviews/PHASE_0_INITIAL_REVIEW.md)

## History

- 2026-08-22: Maintainer authorized Phase 0B under this ADR's conditions; Task 08 began without changing the architecture.
