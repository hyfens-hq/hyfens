# Phase 0 initial review

Date: 2026-08-22

Decision boundary: Tasks 00–06 only

Recommendation: **PROCEED WITH CONDITIONS**

This review stops Phase 0. It proposes Phase 0B work but authorizes and executes
none of it.

## Findings

The preferred developer experience is technically plausible in a narrow form
without a Flutter engine or Dart fork. An analyzer-guided build overlay can add
a callee-entry guard to ordinary Dart source, retain the original AOT body, and
dispatch to bounded interpreted data. The developer fixture remains unchanged
and contains no patch widget or per-function patch API.

That statement is deliberately narrower than “normal Flutter apps are
patchable.” Phase 0 supports one synchronous top-level `int Function(int, int)`,
nine derived integer/control-flow opcodes, one single-file overlay, and one
physical Android release. It does not support arbitrary Dart, automatically
patch Flutter widget methods or hierarchy construction, or establish iOS or
store eligibility.

## What has been verified

- The audited host can build with stock Flutter 3.47.0/Dart 3.13.0 and has
  physical Android and iOS devices available. iOS release signing was not tested.
- Ejenix is an explicit interpreted-subtree architecture, not a transparent
  rewriter of existing screens or arbitrary functions.
- Shorebird obtains transparent normal-code patches through coordinated custom
  tooling/runtime work. Android reconstructs native AOT; public iOS interfaces
  describe linking unchanged functions and interpreting changed/unlinked code.
- Stock precompiled Dart rejects Kernel loading. Upstream dynamic-module
  interpreter work is build-flagged and is not a supported stock-Flutter seam.
- An ephemeral source overlay automatically instrumented an ordinary function;
  direct calls and an existing tear-off followed the active implementation.
- E0 source, manifest, offset map, and patch output were deterministic across
  distinct absolute roots. Repeated AOT executable bytes were not identical.
- E0 passed 17 tests. Median over seven compiled-process samples of five million
  calls was 2.19 ns/call direct, 3.55 ns/call instrumented/unpatched, and
  214.56 ns/call interpreted. This is one hot-leaf microbenchmark, not an
  application performance claim.
- A stock Flutter Android release APK ran on a physical device. After its sole
  install, a 329-byte local patch changed a genuine multi-branch pricing result
  from 630 to 525 while preserving quantity 7 in `StatefulWidget` state.
  Invalid input retained the patch; manual rollback restored 630. Captured
  package install/update timestamps did not change during those transitions.
- App-local current/previous state, atomic state replacement, invalid-patch
  rejection, startup fallback, manual rollback, and stored-payload digest
  binding have focused tests.
- Current official policy text does not justify an “App Store compliant” or
  unconditional “Play compliant” claim for custom Dart behavior patches.

See the [environment audit](../../research/environment-audit.md), [research log](../../research-log.md),
[E0 results](../../../experiments/instrumentation/RESULTS.md), and [E1 results](../../../experiments/patch_loading/RESULTS.md).

## Ejenix architecture

At pinned revision `3e40c661b0440a5694fdaebe4ba3eb3c4e9620b4`, Ejenix parses a
separate Dart subset with analyzer ASTs, compiles it to a custom 63-opcode
register bytecode, and executes it in an application-level interpreter. Flutter
widgets and host functions are finite compiled bindings. Patch source is loaded
under `EjenixPatchView`/`InterpretedView`; the host app must explicitly place
that boundary and provide state/capability integration.

Its public code includes CBOR bundles, Ed25519 verification, channels, caching,
rollback-oriented storage, update protocols, and a self-hostable server shape.
It cannot transparently replace existing normal application functions, render
an untouched screen through the interpreter, add arbitrary plugin/native access,
or provide full Dart semantics. Phase 0 reproduced 792 passing Dart-package tests
and 50 Flutter-bridge tests, not a device or store claim.

Full source-backed evidence and the claim table are in the
[Ejenix teardown](../../competitors/ejenix.md).

## Shorebird architecture

Shorebird's public CLI drives its own Flutter distribution. Public updater,
Flutter, engine, and buildroot repositories expose the architecture boundary,
while critical Dart fork/compiler/interpreter internals—especially the iOS
implementation—are not fully public.

On Android, a patch is a compressed binary diff used to reconstruct a new
architecture-specific `libapp.so`; changed and unchanged Dart execute as the
replacement native AOT program. On iOS, public interfaces and documentation
describe a release containing linkable AOT functions, with compatible unchanged
functions reused and changed/unlinked functions interpreted. Release/patch
compatibility therefore depends on coordinated compiler, VM/engine, Flutter
tooling, and exact-version tracking. The updater handles staged artifacts,
hashing, launch state, and fallback; signing is optional RSA/SHA-256 in the
examined public implementation. The examined public repositories do not form a
complete open production backend plus critical iOS runtime.

This proves that a Shorebird-class fork can reach the desired developer
experience. It does not prove that this project needs a fork or can reproduce
Shorebird's private internals. See the [Shorebird teardown](../../competitors/shorebird.md).

## Candidate architecture

The most promising research direction is Architecture B:

```text
normal source (unchanged)
  -> analyzer-guided ephemeral build overlay
  -> callee-entry guards + stable external IDs/dense release slots
  -> stock Flutter AOT release
  -> original AOT when no patch / bounded interpreter when patched
  -> closed, versioned host-capability registry
```

It wins the next experiment slot because it already crossed stock native AOT
and physical Android at low unpatched cost, not because its production
feasibility is proven. Architecture C is a conditional escape hatch if source
fidelity or mapping fails: test one pre-TFA Kernel transformation and quantify
the upstream code/version surface. Architecture A remains a conscious explicit-
view fallback. Architecture D is deferred unless B/C fail stated thresholds and
maintainers accept permanent toolchain-fork ownership.

No production patch format has been selected. Phase 0's strict JSON is an
experimental 300–329 byte envelope. The [format comparison](../../research/patch-format-options.md)
keeps canonical JSON, deterministic CBOR, schema formats, and a purpose-built
container open until instruction/data layout and access measurements exist.

## Experiments

### E0 — stock Dart AOT

The transformer identifies one strictly typed top-level function, creates a
temporary rewritten source file, retains an extracted original body, and guards
entry through a release-local dense slot. A changed normal Dart function compiles
to only the operations required by the test cases: argument/constant loads,
integer arithmetic/comparison, conditional jump, and return. The verifier bounds
container size, functions, constants, instructions, stack, argument indices,
jumps, and execution budget.

Result: pass for the bounded hypothesis. Developer source was unchanged,
patched/unpatched behavior and tear-offs worked, malformed input failed safely,
artifacts except the native executable were deterministic, and the predeclared
unpatched overhead gate passed.

### E1 — stock Flutter Android release

The fixture uses an ordinary multi-branch `calculatePrice` function from a normal
`StatefulWidget`. One central bootstrap seam initializes patch storage/runtime;
there is no `PatchView` and no per-function annotation/API in app source. A local
HTTP endpoint reachable only through adb reverse delivered the experimental
payload.

Result: pass for meaningful Android logic and simple state preservation without
reinstall. It did not modify the widget hierarchy itself, exercise Riverpod or
BLoC, compile async/await, alter navigation, exercise collection opcodes, or run
on iOS. A first build exposed and fixed a relative-import relocation problem,
which is evidence that real multi-file overlay fidelity is a primary risk.

The physical run preceded a final stored-file digest-binding hardening. Six
loader regression tests validate the final code, including valid substituted
payloads under current and previous content-addressed names. The hardening did
not change the valid activation path used on device; this distinction is kept in
the evidence instead of presenting a second device run that did not occur.

## Risks

### Technical

- Analyzer AST/source rewriting can diverge from CFE semantics and must handle
  parts, generated code, conditional imports, packages, source maps, stack
  traces, flavors, and incremental build behavior.
- Declaration identity is unproved for members, private libraries, moves,
  closures, overload-like shapes, and generated declarations.
- The interpreter lacks fields, objects, closures, generics, records, enums,
  mixins, extensions, async/await, streams, isolates, platform channels, and FFI.
- Tree shaking, inlining, code-size growth, and broad guard overhead may differ
  materially from the single leaf benchmark.
- Class layout, constructors/initializers, new code removed from the base release,
  dependency/native changes, and state migration may be fundamentally bounded.

### Policy

- Apple public agreements/guidelines leave code-bearing behavior changes
  unresolved; iOS remains `UNKNOWN / REQUIRES REVIEW`.
- Google names a VM/interpreter exception but separately restricts remotely
  introduced behavior. Eligibility is conditional, not guaranteed.
- Manifests/plists, permissions, entitlements, and native plugins/libraries are
  store-release changes. Assets, fonts, localization, and shaders need separate
  classification and review.

### Security and reliability

- E0/E1 patches are unsigned. There is no production key lifecycle, replay or
  downgrade defense, expiry, release/channel sequencing, or compromised-key plan.
- The VM budget is minimal; allocation, recursion, async work, host-call time,
  cancellation, memory, and adversarial fuzzing remain open.
- E1 has startup fallback and manual rollback but no launch-pending health signal,
  crash-loop detection, quarantine, or automatic known-good promotion.
- A closed capability registry reduces authority but each adapter becomes trusted
  code with independent input, resource, permission, and policy obligations.

### Maintenance and licensing

- Analyzer/language/build internals track Dart and Flutter releases even without
  a fork. Kernel or dynamic-module work would increase version sensitivity.
- A toolchain fork would require sustained compiler/VM/engine/tool/buildroot
  tracking and release qualification.
- Competitor code is evidence only. No implementation was copied; any future
  reuse requires license review and attribution/notice handling.

## Unknowns

- Can the overlay preserve CFE semantics and diagnostics across a representative
  multi-package Flutter application?
- Which declarations can be instrumented safely, and can stable identity survive
  refactors without unsafe accidental retargeting?
- Can a derived interpreter support enough real Dart/Flutter behavior while
  failing unsupported constructs clearly and remaining auditable?
- Can patched widget construction, ValueNotifier, Riverpod, BLoC, async/await,
  exceptions, navigation, collections, closures, generics, and records pass a
  physical-device conformance matrix?
- How should interpreted values safely cross to existing AOT objects without
  arbitrary dynamic invocation or reflection?
- Does the base release retain every helper/type/capability needed by a future
  compatible patch after tree shaking?
- What are representative startup, memory, load, verification, code-size, and
  broad-dispatch costs on Android and iOS?
- Can the same model build, sign, install, activate, and recover on physical iOS?
- What written platform-review evidence is needed for each patch classification?
- Which deterministic container and Ed25519 implementation meet portability,
  licensing, key-rotation, and malformed-input requirements?
- When, if ever, is upstream `DART_DYNAMIC_MODULES` mature and integrable enough
  to replace project-owned language interpretation without a fork?

## Recommendation

**PROCEED WITH CONDITIONS**

Continue only after maintainer approval of Phase 0B, and only as evidence-driven
Architecture B research. The conditions are:

1. Preserve the stock toolchain and ephemeral-source boundary until a measured
   source-fidelity failure justifies the bounded Kernel spike.
2. Complete Android language/UI/state/async/navigation/collection conformance
   before describing the runtime as useful for normal applications.
3. Establish a closed capability ABI, signed/versioned container, replay and
   downgrade defense, resource limits, fuzzing, and crash-loop rollback before
   any remote production-shaped test.
4. Run an independently gated physical iOS proof and seek platform-policy review;
   do not infer compliance from technical success or competitor existence.
5. Re-measure overhead and artifact size on representative instrumented apps.
   Pivot to selective boundaries if broad guards exceed approved budgets.
6. Escalate to a Flutter/Dart fork only through a new ADR backed by failed B/C
   exit criteria and an explicit long-term maintenance commitment.

## Proposed Phase 0B task list — not authorized or executed

1. **Overlay/build-graph fidelity.** Support a small multi-file fixture with
   imports, parts, generated code exclusion, local packages, conditional imports,
   flavors, diagnostics, source maps, and stack traces. Exit: checked-in bytes
   unchanged, release build reproducible at metadata level, and diagnostics map
   to original sources.
2. **Declaration coverage and stable identity.** Add named instance/static
   methods, getters/setters, and explicitly classify constructors, initializers,
   local/anonymous functions, closures, private members, moves, and renames.
   Exit: collision-safe manifests and incompatible changes rejected.
3. **Derived VM conformance core.** Add only operations demanded by tests for
   null/bool/int/double/String/List/Map/Set, locals, fields through safe adapters,
   calls, iteration, and higher-order cases. Every opcode requires a specification,
   deterministic encoding, implementation, semantic tests, and malformed cases.
4. **Flutter UI boundary.** Prove changed text, widget hierarchy, layout, and
   conditional rendering from ordinary source using a finite versioned widget
   capability layer. Define identity/state-retention rules; prohibit raw
   reflection and arbitrary widget/plugin construction.
5. **Async and errors.** Derive support for `Future`, `await`, exceptions,
   cancellation, and multiple branches, then evaluate streams separately. Add
   instruction, wall-time, pending-work, and host-call budgets.
6. **State and navigation matrix.** Run physical Android cases for ValueNotifier,
   Riverpod, BLoC where practical, route selection, push/pop behavior, and rollback
   while state is live. Record unsupported patterns without shims disguised as
   transparency.
7. **Capability registry.** Specify IDs, schemas, version negotiation, permission
   gates, resource limits, cancellation, audit logging, and release binding.
   Demonstrate narrow HTTP, storage, and navigation adapters already compiled in
   the app; reject unknown capabilities atomically.
8. **Signed patch-container prototype.** Select only after requirements from
   Tasks 3–7. Compare candidate libraries/licenses, implement deterministic signed
   bytes, Ed25519 known-answer tests, hash verification, key IDs/rotation,
   app/release/runtime/channel binding, sequence/replay/downgrade rules, and
   incompatible-version rejection.
9. **Health, rollback, and adversarial validation.** Add stage/activate/launch-
   pending/healthy/quarantine states, crash-loop rollback, corrupted-state recovery,
   fuzzing, invalid jumps/indices, stack/recursion/allocation limits, and atomic
   durability tests.
10. **Representative benchmarks.** Automate direct AOT, instrumented-unpatched,
    and interpreted workloads plus startup, patch load, signature verification,
    memory, code size, and patch size on physical Android. Predeclare broad versus
    selective instrumentation budgets before measuring.
11. **Physical iOS and policy gate.** Build and install a locally signed stock-
    Flutter release, deliver the same data-driven categories locally, test startup
    recovery, measure performance, and prepare a precise architecture/change-
    classification specimen for platform review. Technical success and policy
    acceptability remain separate outputs.
12. **Conditional Kernel/dynamic-module spike.** Execute only if Tasks 1–2 expose
    a source-level blocker. Insert one pre-TFA guard, document all mirrored
    upstream code and version coupling, and separately assess upstream dynamic
    modules. Stop if this silently becomes a Dart fork.
13. **Phase 0B decision review.** Reconcile conformance, security, performance,
    policy, and maintenance evidence. Choose continue B, move to C, accept explicit
    A, propose D with a maintenance plan, or stop. Do not build a server/dashboard
    before this review authorizes the runtime architecture.

No Phase 0B task file, package, server, dashboard, or runtime expansion has been
created as part of this review.
