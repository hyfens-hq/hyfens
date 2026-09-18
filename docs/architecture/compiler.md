# Compiler architecture

Status: Phase 1A implementation baseline.

The compiler is a source-subset compiler, not a Dart compiler replacement. It
parses a patch source unit with the Dart analyzer, resolves the declaration
against a release manifest, lowers supported expressions/statements into a
small typed instruction set, and runs the same structural verifier used by the
runtime before producing an artifact.

```text
patch source
   ↓ analyzer parse + declaration/signature match
typed subset lowering
   ↓ deterministic constants, metadata, instructions
bytecode verifier
   ├── preserved E0 research container (regression/device evidence)
   └── Phase 1 canonical model in packages/patch_format
```

The current lowering implementation is in
`experiments/instrumentation/lib/src/compiler.dart`, with the public Phase 1A
facade in `packages/compiler/lib/compiler.dart`. Its verified subset includes
typed scalar/collection values, structured control flow, bounded exceptions,
capability-mediated async, bounded synchronous closures, and named/optional
parameter metadata. Unsupported syntax is rejected with a stable diagnostic
rather than omitted from a patch.

`packages/patch_format` is the canonical Patch Format v1 model, serializer,
digest/signature boundary, and baseline-manifest implementation. The facade
still hands the verified E0 container to the research integration tests. The
Phase 1B CLI places those canonical E0 container bytes in a non-critical v1
bridge extension while producing the required v1 identity, function,
capability, constant, instruction, digest, and signature sections. The current
runtime package does not yet activate the bridge extension; this is an explicit
toolchain/runtime handoff limitation, not a mutation of Patch Format v1.

## Signature matching

Function identity is semantic and release-owned. Signature compatibility is a
separate exact record containing return schema, async marker, parameter order,
parameter names, parameter kind, default values, and receiver descriptor.
Whitespace and checkout-root changes do not change identity. A rename,
library move, signature change, or incompatible default changes the target and
cannot activate against the old release.

## Closure model

Representative closures lower to nested verified programs. Captured values are
copied into an explicit bounded environment at closure creation. A closure may
capture supported scalar/collection values and the selected receiver view; it
cannot capture a raw host object, reflection handle, channel, FFI pointer, or
unbounded dynamic value. The first supported higher-order operations are
`map`, `where`, `fold`, `sort`, and direct invocation in the documented subset.

## Async model

Async functions retain an explicit continuation state. Phase 1A expands the
accepted Future inputs and operations only where the compiler can retain a
bounded, non-blocking continuation: the existing declared async capabilities
and `await Future.value(value)`. General Dart Future/Stream semantics,
`then`/`catchError` graphs, isolate scheduling, and cancellation remain
diagnostic boundaries until separately proven.
