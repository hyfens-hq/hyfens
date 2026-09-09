# ADR 0002 — Continue source instrumentation with Phase 1 gates

- Status: Proposed for maintainer acceptance; Phase 1 not authorized
- Date: 2026-08-22
- Decision owners: Maintainers

## Context

Phase 0B tested whether stock-Flutter source instrumentation plus a bounded
interpreter remains credible beyond one integer function. Tasks 08–22 produced
positive bounded evidence for typed signatures, selected instance state,
control flow/collections, exceptions, non-blocking async, identity,
compatibility, capabilities, Ed25519 rollback, ordinary widget build, mounted
state, Riverpod, GoRouter, Cubit, selected dependencies, and host performance.

At the initial review boundary, the expanded physical Android sequence was
blocked by unavailable hardware and account/profile provisioning blocked the
iOS runtime. Those device gates were subsequently closed on the current source
(Android over Wi-Fi; iOS over USB with the AUVANA team). Closures and broad
build-graph/source-fidelity coverage remain unresolved. Store policy still
requires review for code-bearing Dart changes.

## Decision

Recommend **PROCEED TO PHASE 1 WITH CONDITIONS** while retaining Architecture B
as the lead research direction. This is not a production architecture selection
and does not authorize Phase 1 execution.

Do not fork Flutter/Dart or begin a Kernel integration merely to expand scope.
Architecture C receives a bounded spike only after a concrete source-overlay
semantic, diagnostic, or build-graph failure. Architecture D requires a new ADR
and explicit acceptance of permanent toolchain maintenance. Architecture A
remains the explicit-boundary fallback if transparent coverage proves
uneconomic.

## Required gates

- complete signed physical Android composition and physical iOS baseline;
- treat negative iOS runtime evidence as a pivot trigger;
- predeclare closure/useful-coverage and representative build-fidelity exits;
- measure broad/device dispatch, startup, memory, and binary growth;
- complete device security, crash recovery, key lifecycle, and real-capability
  evidence before production-shaped delivery;
- keep policy review independent and prohibit compliance claims.

## Consequences

The project preserves the preferred ordinary-source, stock-toolchain experience
and avoids premature fork maintenance. It continues to own a source transformer,
subset compiler/interpreter, compatibility ABI, capability boundary, verifier,
and recovery system. Unsupported Dart remains explicit, and blocked physical
evidence cannot be inferred from host tests.

## Evidence

- [Phase 0B review](../history/reviews/PHASE_0B_REVIEW.md)
- [Phase 0B findings](../architecture/phase-0b-findings.md)
- [Dart support matrix](../dart-support-matrix.md)
- [Performance results](../../experiments/instrumentation/RESULTS.md)
- [iOS feasibility](../research/ios-feasibility.md)
- [Store-policy change matrix](../store-policy/change-matrix.md)

## Post-decision evidence correction — 2026-08-22

The initial ADR was written while the physical Android composition and iOS
signing gates were still pending. They subsequently passed on the current
source: Android over Wi-Fi, and iOS over USB using AUVANA team `CYT7A4VAZ3`.
The bounded runs verified business, capability-mediated async, ordinary widget
build, Riverpod, signature rejection, rollback, and restart persistence without
reinstall. This closes the Phase 0B device prerequisite but does not widen the
support matrix, establish production transport, or create a store-policy
approval. The Phase 1 recommendation and its conditions remain unchanged.

## History

- 2026-08-22: Created after Phase 0B synthesis; awaiting maintainer review.
