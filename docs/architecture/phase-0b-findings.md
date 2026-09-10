# Phase 0B architecture findings

This is the living architecture evidence record for Tasks 08–25. It does not
replace completed Phase 0 documents and does not select a production design.

## Active direction

Continue the accepted Phase 0B research direction from
[ADR 0001](../adr/0001-continue-source-instrumentation-research.md): stock
Flutter/Dart, ephemeral analyzer-guided source instrumentation, original AOT
fallback, and a bounded interpreted patch branch.

## Invariants

- Developer-owned source remains ordinary Dart/Flutter and is never rewritten in place.
- Every instrumented declaration has an explicit signature and compatibility record.
- Downloaded content cannot reflect over arbitrary AOT objects or invoke raw native APIs.
- Unsupported syntax/types fail compilation or activation explicitly.
- A signed patch is still untrusted input and must pass all structural/resource checks.
- Platform technical feasibility and store-policy classification remain separate.
- No cloud, dashboard, billing, enterprise, React Native, or production deployment work enters Phase 0B.

## Pivot triggers

Stop the affected implementation package and compare source instrumentation,
pre-TFA Kernel transformation, compiler modification, and a Flutter/Dart fork if:

- representative unpatched dispatch overhead or binary growth exceeds its predeclared budget;
- instrumentation changes ordinary Flutter semantics or cannot preserve source diagnostics;
- async needs blocking or fundamentally invasive source/compiler emulation;
- closure support requires unsustainable compiler emulation for useful applications;
- an ordinary `Widget.build` cannot be intercepted transparently and safely;
- declaration identity cannot reject unsafe signature/refactor mismatches;
- a physical iOS release cannot execute the bounded interpreter safely;
- useful patch coverage remains too narrow after the required conformance fixtures; or
- routine Flutter/Dart upgrades repeatedly break the transformer beyond an accepted maintenance budget.

## Evidence ledger

| Task | Finding | Architecture implication | Status |
| --- | --- | --- | --- |
| Phase 0 E0/E1 | One synchronous top-level integer function dispatched on stock AOT and physical Android with low measured leaf lookup cost. | Architecture B merits bounded expansion; general feasibility remains unproved. | VERIFIED (narrow) |
| 08 — typed values | Explicit recursive schemas and canonical bounded values supported all five required functions; 540-byte typed patch; native AOT and downstream compatibility passed. Review fixed signature-wildcard and eager-AND faults. | Architecture B survives generalized typed function dispatch without `dynamic` host exposure; collection/control-flow breadth remains gated. | VERIFIED (bounded) |
| 09 — instance methods | Same-unit direct/virtual/tear-off method dispatch and selected explicit read-only receiver properties passed native AOT. Generated-name collisions were fixed. Writes, unqualified members, cross-library resolution, and effectful getters remain unsupported. | A finite same-library receiver adapter avoids reflection/raw objects and keeps Architecture B viable, but general object semantics require resolved build analysis and transactional mutation design. | VERIFIED (bounded) |
| 10 — control flow/collections | Version-4 typed locals, verified joins/jumps, bounded loops, and List/Map/Set operations passed native AOT. Review rejected implicit fallthrough and receiver-origin mutation. Argument collection mutation remains by-value rather than caller-visible. | Structured lowering still fits the small VM, but transparent Dart reference mutation and closures remain material coverage risks. | VERIFIED (bounded) |
| 11 — exceptions | Version-5 handler metadata and pending completions passed catch/finally/rethrow, AOT crossing, malformed input, and host/collection failure tests. Runtime faults remain uncatchable. | Structured exceptions fit the VM, but only catch-all bounded values and synthetic traces are proven; async error resumption remains the critical next gate. | VERIFIED (bounded) |
| 12 — async/closures | Version-6 typed continuations passed immediate/delayed/multiple awaits, saved exception state, zones, deadlines, fatal-fault handling, atomic activation, rollback generation pinning, and ordinary top-level/instance native-AOT guards. The patch was 1,022 bytes. Closures remain explicitly unsupported. | Non-blocking capability-mediated async fits Architecture B without a fork, but it is partial rather than general Dart async. Closure-heavy idiomatic code and unmeasured continuation memory remain material conditions for the UI/ecosystem gates. | VERIFIED (bounded) |
| 13 — identity/compatibility | Structured semantic IDs resolved through package configuration are stable across whitespace, declaration movement, and checkout roots; renames/library moves change ID, while signature changes retain ID and fail exact compatibility. Strict manifests bind release/build/function/contracts/capabilities/hash/sequence and reject atomically. | Stable identity is viable for the supported named-declaration subset. Parts and more declaration kinds remain unsupported; payload hash is not authenticity, and sequence state is not durable until Task 15. | VERIFIED (bounded) |
| 14 — capability authority | A frozen release-owned authority, exact canonical contracts, typed sync/async calls, bounded failures, and five deterministic fake adapters passed 158 tests. Mutable fallback, raw host calls, channels, FFI, and plugin discovery are absent. | A closed capability bridge can preserve stock-AOT safety without reflection. Real adapters, concurrency quotas, non-detach cancellation, OS permissions, and store review remain conditions. | VERIFIED (bounded) |
| 15 — signing/rollback | Exact canonical E1 bytes are authenticated with pure-Dart Ed25519 before E0 decode/stage. A release-owned trust map, durable high-water sequence, pending/health/LKG state, signed older-target selection, dual checksummed state copies, and fail-closed recovery passed 25 loader tests plus downstream compiler/runtime and Flutter checks. | Authenticity and conservative local recovery fit the stock-Flutter design without native code. Production key custody, protected monotonic state, broader cryptographic corpus, process-kill injection, and physical Android/iOS verification remain conditions. | VERIFIED (bounded) |
| 16 — ordinary widget build | A build-tool-selected ordinary `StatelessWidget.build` produced patched real Flutter text, conditional hierarchy, style, and composition through a frozen program-scoped factory registry. Malformed/failing construction fell back to AOT; 170 instrumentation and four Flutter fixture tests passed after allowlist hardening. | Transparent callee-entry interception survives the first UI gate without raw context/widgets or a fork. The factory ABI is finite, syntax-selected, callback-free, and not yet integrated with signed controller lifecycle or real Flutter release-AOT/device execution. | VERIFIED (bounded) |
| 17 — mounted state | The actual transformed ordinary pricing guard activated through signed E1 before construction and while mounted. State, Element, integer value, text controller/text/selection, scroll controller/offset, and lifecycle counts survived activation, rejection, and rollback; tree remount created fresh objects. | Installed AOT-owned state can remain intact when only dispatched behavior changes. State layout migration is unsupported; rollback/recovery has a documented in-progress visibility window, and process/device restart remains unproved. | VERIFIED (bounded) |
| 18 — Riverpod | A signed transformed pricing function drove existing Provider and AsyncNotifier graphs after ordinary dependency invalidation. ProviderContainer, Notifier/AsyncNotifier, subscriptions, state, and mounted ConsumerWidget survived activation, rejection, and rollback. Activation alone did not invalidate cached values. | Riverpod needs no fork for the tested flow, but transparent immediate recomputation requires an explicit generation/invalidation integration that preserves unrelated provider state. | VERIFIED (bounded) |
| 19 — GoRouter | A signed transformed ordinary A/B decision redirected the existing GoRouter among compiled destinations on later navigation. Router listener and mounted route/host state survived activation, malformed rejection, push/pop, and rollback. Activation/rollback emitted no reevaluation; builder replacement was not proved. | Pure-Dart installed-route decisions fit the guard, but immediate reevaluation needs an app-owned signal and neither new routes nor builder closures/native deep links follow from this result. | VERIFIED (bounded) |
| 20 — BLoC/Cubit | One existing Cubit, pre-existing stream subscription, provider lookup, mounted panel, and BlocBuilder remained intact through signed activation, health confirmation, malformed rejection, and rollback. Lifecycle operations emitted/rebuilt nothing; later normal inputs produced patched then base results. | Framework-agnostic callee-entry dispatch interoperates with the bounded Cubit lifecycle without modifying BLoC. Immediate recomputation still needs an application event/generation signal; event Bloc and async/concurrency remain unproved. | VERIFIED (bounded) |
| 21 — pure-Dart dependencies | A package-preserving explicit-unit overlay assigned one global deterministic slot table and retained canonical package URIs. A local path package passed native-AOT direct/tear-off base, patch, corrupt, and wrong-package runs; hosted collection 1.19.1 passed a JIT direct/tear-off proof without cache mutation. Review hardened sorted manifests, global per-unit views, symlink/output/runtime pinning, and AST import exclusions. | Selected pure-Dart dependency source is viable without a fork, but this is not a transitive package/build graph. Parts, broader generated suffixes, Flutter/SDK/FFI/native code, filesystem race hardening, and hosted AOT remain conditions. | VERIFIED (bounded) |
| 22 — performance/selection | Corrected schema-v2 host-AOT evidence measured stock 2.0103 ns/call and instrumented-unpatched 6.0329 ns/call: +4.0226 ns and 3.0010x, passing the predeclared <=10 ns and <=5x gate. Unrelated-active was 6.4734 ns and interpreted 557.9237 ns. Signed activation median was 3.309 ms, dominated by 3.083 ms Ed25519 verification. Selective planning made app-default/dependency-opt-in/generated/SDK/Flutter/native boundaries explicit. | The bounded hot-call overhead does not trigger a pivot. Binary growth was +8.62% including the whole runtime; broad declaration scaling, device startup/memory, typed/control/instance/async performance, and alternative lookup strategies remain unmeasured conditions. | VERIFIED (host/bounded) |
| 23 — expanded Android device run | Current-source narrow and broad physical Wi-Fi runs installed one Release APK and passed business, capability-mediated async, ordinary widget build, Riverpod recomputation, invalid-signature retention, rollback, two restart groups, persistence, and unchanged package timestamps. Navigation remains represented by the separate GoRouter fixture tests rather than an on-device route assertion. | The bounded cross-feature subset composes on stock Android without reinstall; broader Dart/Flutter coverage and device performance remain open. | VERIFIED (bounded physical) |
| 24 — physical iOS baseline | Current-source AUVANA-signed Release/AOT builds installed on the USB iPhone. Arm64 Runner/App artifacts had no kernel/dill payload; entitlements bind `CYT7A4VAZ3.dev.hyfens.conformance`; the narrow run passed business activation, invalid signature rejection, rollback, two restarts, and persistence. | The bounded interpreter executes on physical stock iOS without a fork. USB staging proves local transport only, and this is not an App Store policy result. | VERIFIED (bounded physical) |
| 25 — expanded iOS and policy | The AUVANA-signed broad USB run passed async, UI hierarchy, Riverpod recomputation, invalid signature rejection, rollback, two restarts, and persistence without reinstall. The official-source cross-store matrix remains conservative: interpreted Dart logic/UI/navigation/dependencies require policy review; native/build/permission/new-capability changes require a store release; only bounded passive-content paths are architecturally likely OTA-safe. | Technical interpretability is not store authorization, and no category may be marketed as compliant from this research or competitor existence. | VERIFIED (physical bounded) / Policy VERIFIED |

## Final comparison

Task 26's [Phase 0B review](../history/reviews/PHASE_0B_REVIEW.md) compares the four architecture
classes using this ledger, the support matrix, device evidence, security/policy
results, and measurements. It recommends continuing Architecture B research
with explicit device, coverage, build-fidelity, performance, security, and
policy conditions; it does not select a production architecture.

Device closure evidence is recorded in the Phase 0B review and the run roots
under `fixtures/flutter_conformance_app/.dart_tool/`. The USB patch staging path
is laboratory transport evidence only; it does not establish production
delivery, App Store approval, or Google Play approval.
