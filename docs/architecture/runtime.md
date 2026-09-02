# Runtime architecture

Status: Phase 1A implementation baseline.

## Runtime path

An instrumented release keeps the original Dart function body in the normal
Flutter AOT artifact. At the beginning of a selected declaration, generated
source performs a bounded slot lookup. An empty slot executes the original
body. A populated slot validates the invocation against the release manifest,
executes a verified patch program, and returns to the AOT caller.

```text
instrumented Dart entry
        ├── empty slot ───────────────► original AOT body
        └── installed slot ─► verifier-approved interpreter program
                                  └── closed capability authority
```

`experiments/instrumentation/lib/e0_runtime.dart` is the current research and
device-regression implementation of this path. The Phase 1A public capability
and patch-state contracts are in `packages/runtime`; the experiment remains
available for evidence and downstream regression tests until the v1 artifact
handoff is integrated.

## Runtime responsibilities

The runtime owns:

- release-local slot lookup and immutable installed program generations;
- typed value copying at the AOT/interpreter seam;
- bytecode structural, stack, control-flow, capability, and resource checks;
- synchronous and bounded asynchronous invocation;
- capability authority pinning for a pending continuation;
- deterministic failure isolation and AOT fallback policy;
- patch state transitions supplied by the signing/recovery layer.

The runtime does not own source discovery, Flutter SDK files, arbitrary host
reflection, native binaries, or a hosted update service.

## Failure policy

Guest throws remain guest results and may cross the generated guard. Runtime
faults (invalid instructions, resource exhaustion, type mismatches, or stack
failure) disable the affected patch slot and report a bounded diagnostic. A
failed install never replaces the known-good generation. Async continuations
are non-blocking and are disposed on terminal success, guest error, or runtime
fault.

## Stable surface

The intended stable runtime surface is bootstrap/configuration, capability
registration, patch state, invocation diagnostics, and patch activation. The
interpreter classes and instruction implementation remain internal/experimental
until a later API review.
