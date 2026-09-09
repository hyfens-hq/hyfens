# Flutter OTA architecture options

Status: Phase 0 comparison updated after E0/E1; no production architecture is selected.

## Decision question

Can a developer keep ordinary Flutter/Dart source and use a workflow close to `tool init`, `tool release`, edit normal code, `tool patch`, while meaningful behavior is delivered as interpreted/data-driven content on Android and iOS without an engine fork?

The evidence base is:

- [Ejenix teardown](../competitors/ejenix.md): source-verified explicit interpreted-subtree baseline.
- [Shorebird teardown](../competitors/shorebird.md): source-verified toolchain/engine architecture, with private critical iOS internals.
- [Flutter AOT map](../research/flutter-aot.md): upstream release pipeline, pruning, stock-AOT limits, and interception points.
- [Instrumentation seams](../research/instrumentation-seams.md): source overlay versus Kernel timing and experiment criteria.
- [Apple](../store-policy/apple.md) and [Google Play](../store-policy/google-play.md) policy research.

“Feasible” below means technically plausible or demonstrated within the stated boundary. It never means store-approved.

## Runtime shapes

### Architecture A — explicit patch views

```text
ordinary AOT app -> explicitly placed PatchView -> custom subset bytecode
                                           -> application interpreter
                                           -> compiled host/widget bindings
```

Ejenix demonstrates this shape in public source. A separately maintained patch compilation unit renders a real Flutter widget subtree beneath `EjenixPatchView`/`InterpretedView`. A finite registry bridges guest calls to compiled Dart/Flutter capabilities.

Advantages:

- small, auditable patch boundary and no engine/compiler fork;
- no per-call dispatch tax in ordinary AOT code outside patch views;
- finite widget/host bindings support least privilege;
- interpreter, verifier, signing, cache, and rollback can be fully open and self-hosted;
- source-backed evidence exists for a broad custom subset and production-shaped failure handling.

Disadvantages:

- fails the preferred existing-app experience: developers replace chosen subtrees and maintain separate patch source;
- cannot transparently replace arbitrary normal functions;
- app state/services/plugins require deliberate host bridges;
- finite Flutter bindings lag framework/API growth;
- patch-local state migration and full-Dart parity become project-owned problems.

Conclusion: viable baseline and fallback, not accepted as the primary direction.

### Architecture B — build-time source instrumentation

```text
developer source (unchanged)
          -> analyzer-guided ephemeral source overlay
          -> callee-entry dispatch guards + release manifest
          -> stock Flutter CFE/TFA/gen_snapshot
          -> normal AOT release + application interpreter

function entry -> dense patch slot empty? -> original AOT body
                                  \-> interpreted patch + capabilities
```

The transformer edits temporary copies, never the developer's files. Instrumenting a function's entry instead of every call site preserves direct/virtual calls and existing tear-offs once they reach that declaration, and limits guards to instrumented declarations. Stable external IDs resolve to dense release-local slots at activation; arguments are boxed only on the patched branch.

Advantages:

- directly targets normal source and a stock Flutter/engine release;
- dispatch exists before CFE/TFA, so both paths can be analyzed and retained;
- can start with selected named app declarations and report all exclusions;
- avoids ownership of unpublished Kernel/front-end internals in the first experiment;
- a single transformed declaration covers more invocation forms than call-site rewriting.

Disadvantages and unknowns:

- analyzer AST is not the compiler's canonical IR; source fidelity and CFE semantic parity must be proven;
- shadow-workspace handling for `part`, generated code, conditional imports, flavors, packages, and assets is unproved;
- constructors, initializers, async/generators, generics, closures/local functions, extension types, and source maps are unresolved;
- every selected entry pays a measured lookup/branch cost in the current hot-leaf case and may affect inlining/code size differently at application scale;
- transparent dispatch does not itself provide Dart execution—the custom compiler/interpreter remains a bounded subset;
- class-shape/layout changes, new native capabilities, and tree-shaken code remain outside the safe boundary.

Phase 0 evidence proved one physical Android path. Phase 0B broadened the same
stock-toolchain mechanism through typed signatures, selected instance state,
structured flow, collections, bounded exceptions and async, finite widget
factories, mounted state, Riverpod, GoRouter, BLoC/Cubit, selected pure-Dart
packages, Ed25519 compatibility envelopes, and durable rollback. These results
remain bounded; closures, broad Flutter/Dart semantics, cross-feature physical
Android, and physical iOS execution are not proved. Task 22 measured the current
hot leaf at 6.0329 ns/call instrumented/unpatched versus 2.0103 ns/call stock
(+4.0226 ns, 3.0010x), passing its predeclared host gate.

Conclusion: most promising Phase 0B research direction, with explicit exit
criteria; not a selected production architecture.

### Architecture C — Kernel/front-end transformation

```text
normal source -> Dart CFE -> resolved Kernel Component
                           -> pre-TFA dispatch pass
                           -> stock global transforms/gen_snapshot
                           -> AOT release + application interpreter
```

Kernel is designed as transformable whole-program IR and contains resolved references, synthetic/lowered constructs, and canonical names. This makes it semantically cleaner than reconstructing source.

Advantages:

- operates closer to the program actually compiled and can avoid text regeneration/import edits;
- whole-program visibility may improve declaration selection, type adapters, and call identity;
- developer source remains unchanged; engine fork is not inherently required;
- compiler-generated/lowered constructs are more explicit than at source level.

Disadvantages and unknowns:

- Kernel/front-end packages are unpublished/unstable and tied to exact Dart revisions;
- Flutter's exposed `ProgramTransformer` runs after AOT global transforms/TFA, too late for a clean general insertion;
- no supported third-party pre-TFA plug-in was found; a custom frontend-server orchestration layer may mirror material upstream code;
- post-TFA edits risk missing pruned helpers and invalidating analysis/metadata assumptions;
- Kernel metadata cannot be assumed to survive into a runtime-readable AOT form;
- the same interpreter semantic limits and dispatch overhead as B still apply.

Conclusion: potentially cleaner destination, gated behind a narrow pre-TFA integration spike if B exposes material semantic/source-map failures.

### Architecture D — Flutter/Dart toolchain fork

```text
normal source -> modified Flutter tool/CFE/Dart compiler/VM/engine
              -> platform-specific release and patch artifacts
              -> modified runtime selects native/interpreted execution
```

Shorebird demonstrates transparent ordinary-Dart patching with coordinated toolchain control. Android reconstructs a new native AOT program from a binary diff. iOS links compatible functions to signed release code and interprets the remaining code, according to public interfaces/docs; the critical Dart implementation is private.

Advantages:

- highest ceiling for Dart semantic coverage and transparent developer experience;
- compiler/VM can assign identity, preserve patch points, and understand optimized code directly;
- no application-level lookup at every ordinary function is required in Shorebird's observed runtime shape;
- Android can execute the replacement AOT program natively.

Disadvantages:

- permanent maintenance across Dart compiler, VM, Flutter engine/tool, buildroot, architectures, and Flutter releases;
- much larger security and correctness audit surface, especially mixed native/interpreted execution;
- iOS strategy is not reproducible from Shorebird's public source because its Dart fork is private;
- native AOT replacement is architecture-specific and carries stronger policy/code-signing concerns;
- self-hosting requires owning build/artifact/update infrastructure and compatibility matrices;
- project governance must sustain urgent upstream merges and release qualification indefinitely.

Conclusion: technically proven architecture class and evidence-based fallback, but selected only if A–C cannot meet explicit thresholds.

## Comparison matrix

| Criterion | A — explicit views | B — source instrumentation | C — Kernel transform | D — toolchain fork |
| --- | --- | --- | --- | --- |
| Arbitrary Dart support | Custom subset only; separate patch unit | Custom subset behind transparent named declarations | Custom subset, potentially compiled from resolved Kernel | Highest ceiling; actual iOS internals unverified publicly |
| Existing-app compatibility | Low: explicit subtree replacement | Potentially high for supported declarations | Potentially high | High for Dart-only compatible changes |
| Developer source modifications | Required integration and separate patch source | None intended; temporary copies transformed | None intended | None for ordinary patchable Dart |
| Engine modifications | None | None intended | None intended, but frontend wrapper likely | Required in demonstrated Shorebird-class design |
| Dart/frontend modifications | None | None; analyzer-guided external tool | No source fork in theory; unstable frontend orchestration | Required |
| Android feasibility | Demonstrated at Flutter-test level by Ejenix; device proof not reproduced here | Narrow physical-device proof: one instrumented top-level function in a stock release APK, locally activated without reinstall | Unproved | Demonstrated architecture: reconstructed native AOT artifact |
| iOS feasibility | Technically platform-neutral interpretation; store status unknown | Technically plausible pure interpretation; policy review-gated | Same runtime policy as B plus tooling risk | Demonstrated product shape; private interpreter/compiler internals |
| Unpatched runtime overhead | None outside patch view | Task 22 hot leaf: +4.0226 ns/call, 3.0010x stock; broader declarations/devices unmeasured | Similar guard unless compiler/VM optimizes specially; unmeasured | No application guard in observed Shorebird model |
| Patched runtime overhead | Interpreter on entire explicit subtree | Interpreter only for entered patched functions | Same application-interpreter cost as B | Android native; iOS depends on link percentage/interpreter |
| Patch size | Custom bytecode; likely compact but must measure | Custom bytecode + metadata; must measure | Similar to B | Android per-ABI binary diff; iOS link/diff artifact |
| Tree shaking | Ordinary app unaffected; capabilities must remain reachable | Guards/helpers visible before TFA; proof required | Ordering is the central integration risk | Toolchain owns reachability/patch semantics |
| Maintainability | Interpreter/subset and bindings | Transformer + interpreter + source-map/build wrapper | Same plus exact-SDK frontend internals | Highest: compiler/VM/engine/tool forks |
| Flutter-version sensitivity | Bindings/subset evolve; stock ABI still matters | Analyzer/language/build-overlay behavior | Very high due unstable Kernel/front-end APIs | Very high across all forked layers |
| Security boundary | Strongest natural containment through explicit subtree/capabilities | Guard expands reach, but patch remains capability-limited | Same runtime boundary as B | Runtime/compiler-level; larger trusted base |
| Store-policy posture | Interpreted/data-driven, but code-bearing changes still review-gated | Interpreted payload avoids native code; Apple/Google behavior rules unresolved | Same payload posture as B | Android native replacement and iOS interpretation need separate analysis; competitor existence is not approval evidence |
| Fully open/self-hostable potential | Yes | Yes | Yes if upstream dependencies are consumable | Possible in principle, but not by copying Shorebird's private/full stack |

## Stable identity and compatibility boundary

For B/C, named declaration identity should be project-defined rather than a serialized Kernel name or source offset. The experiment should hash versioned UTF-8 identity material containing package URI, library URI/path, enclosing declaration, member kind, member name, and private-library identity. Absolute paths are forbidden; collisions fail the release. Signature/type/class-shape information belongs in compatibility metadata so incompatible changes are rejected explicitly.

Initial exclusions are honest compatibility boundaries, not silent limitations:

- constructors/initializers and class-layout changes;
- local/anonymous functions until stable lexical identity is solved;
- external/native/FFI declarations;
- SDK/Flutter/package-cache/generated code unless explicitly supported;
- new plugins, host capabilities, permissions, entitlements, manifests, or native libraries;
- code or types absent from the release and removed by tree shaking.

The release manifest must list instrumented and excluded declarations with reasons. “Most code is patchable” cannot be claimed from a single function proof.

## Host capability model

Downloaded code never receives arbitrary reflection, `dynamic` object traversal, raw platform-channel invocation, FFI symbol lookup, filesystem/process access, or unrestricted network access.

Each release compiles a closed registry whose entries contain at least:

```text
capability ID + capability schema version
argument/result schema
permission/user-intent requirements
resource and cancellation behavior
implementation adapter already compiled in the app
```

Activation resolves every required capability before a patch becomes current. Unknown IDs, incompatible versions, invalid arguments, or missing permission gates reject activation or the affected optional section according to a specified fail-closed rule. Generic escape hatches such as `platform.invoke(name, payload)` are forbidden.

Consequences:

- **Security:** least privilege limits a compromised signing key or malicious patch; each adapter still validates inputs, authorization, output size, timeouts, and data policy.
- **Store policy:** the patch cannot add native code or platform declarations, but precompiled capability availability is not permission to activate hidden/new functionality.
- **Compatibility:** capability semantics are immutable within a major schema version; adding/changing native capabilities is a store release. Release manifests bind exact supported versions.
- **Plugins:** patch code can call only narrow adapters intentionally exposed by the shipped app; raw plugin registries/channels are not guest APIs.

## Security, signing, and rollback requirements

The patch is untrusted even when signed. A signature proves possession of a key, not semantic safety.

Task 15 selected Ed25519 for the experimental E1 envelope because it has a
standardized algorithm and fixed-size keys/signatures
([RFC 8032](https://www.rfc-editor.org/rfc/rfc8032.html)). The implementation
pins `cryptography` 2.9.0 and explicitly uses `DartEd25519`; known-answer,
determinism, tamper, wrong-key, and local rotation tests pass. This is an
experimental protocol choice, not a production key-custody or cryptographic
assurance decision; physical mobile verification and a broader adversarial
corpus remain open.

A production envelope must bind, inside the signed bytes:

- format, bytecode, and runtime versions;
- application/package identity and release identity;
- patch ID, monotonic sequence/generation, creation/expiry policy, and target channel;
- required capability versions and content hash/section hashes;
- signing key ID and algorithm.

Key rotation requires multiple trusted key IDs or a release-compiled root delegating to signed, constrained patch keys. Revocation/expiry and lost-key recovery must be specified before production; accepting an arbitrary server-provided key is forbidden. Monotonic sequence and release binding reject replay, cross-app use, and downgrade. Operator rollback must be compatible with anti-downgrade—for example, a newly signed higher-sequence patch whose payload/reference selects a known-good version, not silent acceptance of an older generation.

Before activation, validation must bound input length, nesting, constants, functions, instructions, indices, jumps, stack/frame sizes, recursion, allocations, collection sizes, async work, and wall/instruction time. Every opcode requires a specification, encoding, interpreter case, semantic test, and malformed-input tests. Host calls need independent time/cancellation/resource limits because interpreter instruction accounting cannot preempt arbitrary host work.

Minimum lifecycle:

```text
download -> verify signature/hash/bindings -> decode and structural verify
         -> stage durably -> activate atomically for next launch
         -> mark launch pending -> healthy signal
         -> current known-good
              or failed/timeout -> quarantine -> previous known-good/base
```

Initial prototypes must at least preserve current and previous known-good patch, reject invalid patches, support manual rollback, and start with the bundled AOT path when patch loading fails.

## Patch format

No container is selected. [The format comparison](../research/patch-format-options.md) covers canonical JSON, deterministic CBOR, Protobuf, FlatBuffers, MessagePack, and a purpose-built experimental envelope. Actual bytecode/metadata layout, access pattern, malformed-input tests, Dart library quality, and benchmarks are decision prerequisites.

## Store-release boundary

Platform policy findings are architecture constraints, not approvals:

- Android's current policy expressly names a VM/interpreter exception but still prohibits policy-violating or review-absent behavior. Custom Dart bytecode has no project-specific ruling.
- Apple's DPLA conditionally permits interpreted code while App Review Guideline 2.5.2 broadly prohibits downloaded code that changes functionality. Public text does not resolve normal Flutter bug-fix OTA.

Therefore Dart logic/UI/navigation patches remain conditional on classification and review; iOS code-bearing categories are `UNKNOWN / REQUIRES REVIEW`. Manifests/plists, permissions, entitlements, native plugins/libraries, and compiled bundle changes are store releases. Assets/fonts/shaders have separate format/content/review questions and are not smuggled through a code container.

## Experiment order and decision thresholds

1. **B/E0, stock Dart AOT:** analyzer-guided ephemeral overlay instruments one normal function at callee entry. Prove unchanged developer source, deterministic IDs/output, fallback, direct call and tear-off dispatch, malformed-patch safety, compiled-mode baseline/unpatched/patched measurements, and source mapping.
2. **B/E1, stock Flutter Android:** instrument ordinary logic and at least one normal Flutter method, install release on the physical Android device, deliver interpreted data locally, activate without reinstall, and capture behavior/overhead. Do not generalize unsupported Dart categories.
3. **C spike only on evidence:** if B fails because of source semantics/mapping rather than the interpreter model, attempt one pre-TFA Kernel guard with a custom frontend starter and measure owned upstream code.
4. **A pivot condition:** if transparent guards are unsafe or overhead/coverage is unacceptable but explicit interpreted surfaces remain valuable, present A as a deliberate UX compromise.
5. **D escalation condition:** consider a fork only when B/C fail explicit semantics/performance/compatibility thresholds and maintainers accept a funded, permanent upstream-tracking program.

Tasks 08–25 expanded the E0/E1 source-instrumentation evidence without firing a
proved pivot trigger. Architecture B remains a conditional research direction,
not a production selection. Physical Android and iOS bounded composition now
pass on the connected devices; production selection still waits for multi-file/
source-map fidelity, broader declaration and Dart semantics, bounded
capabilities, signed-container hardening, policy review, and representative
performance evidence.
