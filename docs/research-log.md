# Research log

<!-- Evidence links and captured records intentionally disable line length. -->
<!-- markdownlint-disable MD013 -->

## 2026-08-22 — Local experiment environment

**Question:** Can this host execute the planned Android-first and later iOS experiments?

**Investigation:** Queried the OS, CPU, Xcode, Flutter, Dart, Java, Android SDK, connected-device, emulator, and simulator tools.

**Evidence:** See [environment audit](research/environment-audit.md), including the reproduction commands and captured versions.

**Finding:** The host has current Flutter/Dart toolchains and connected Android and iOS physical devices. Android release experimentation is immediately plausible. iOS release signing remains unverified.

**Implication:** Task 06 can target Android first without global configuration changes; an iOS proof should remain an explicit subsequent validation boundary.

**Next action:** Bootstrap the evidence structure, then research competitor and upstream execution models before choosing an experiment mechanism.

## 2026-08-22 — Official mobile-store policy boundary

**Question:** Do current official Apple and Google Play policies establish a safe category for a capability-limited, interpreted Flutter OTA patch?

**Investigation:** Reviewed current official Apple App Review/DPLA material and Google Play/Android policy and security material. Facts and project interpretations are separated in the platform-specific documents.

**Evidence:** [Apple policy](store-policy/apple.md) and [Google Play policy](store-policy/google-play.md).

**Finding:** Google expressly describes a VM/interpreter exception to its off-Play executable-code prohibition, but it also prohibits remotely introduced functionality absent during review. Apple conditionally permits downloaded interpreted code in DPLA §3.3.1(B), while App Review Guideline 2.5.2 broadly prohibits downloaded code that changes functionality. Neither platform provides a project-specific ruling for custom Dart bytecode.

**Implication:** Interpreted, architecture-independent patches and a closed capability registry are stronger starting constraints than native payloads, but they do not establish compliance. iOS code-bearing patches remain `UNKNOWN / REQUIRES REVIEW`; Android eligibility is conditional and behavior-sensitive.

**Next action:** Incorporate these constraints into the architecture matrix and require concrete platform review before any production compliance claim.

## 2026-08-22 — Patch-container choice remains open

**Question:** Do the known requirements already justify CBOR, Protobuf, FlatBuffers, MessagePack, JSON, or a custom format?

**Investigation:** Compared each format's primary specification/documentation against deterministic signing, evolution, bounded validation, Dart tooling, and the still-unknown runtime access pattern.

**Evidence:** [Preliminary patch-container format options](research/patch-format-options.md).

**Finding:** Deterministic CBOR and canonical JSON define signing-friendly encodings. Protobuf supports schema evolution but explicitly does not promise canonical serialization. FlatBuffers' random-access benefits and MessagePack's generic compactness are not yet tied to a measured need. A custom envelope minimizes a prototype but transfers the entire protocol burden to this project.

**Implication:** No production format is selected. Task 06 may use an explicitly experimental, bounded, deterministic encoding, but production selection waits for real instruction/data layouts and measurements.

**Next action:** Use the smallest honest experiment encoding and revisit the decision after runtime requirements are observed rather than imagined.

## 2026-08-22 — Ejenix explicit-view baseline

**Question:** Does Ejenix transparently patch normal existing Flutter screens and arbitrary Dart functions?

**Investigation:** Inspected compiler, bytecode, interpreter, bridge, loader, bundle, delta, CLI, server, deployment, tests, licenses, and specifications at pinned revision `3e40c661b0440a5694fdaebe4ba3eb3c4e9620b4`; ran its Dart and Flutter test suites.

**Evidence:** [Ejenix architecture teardown](competitors/ejenix.md). All eight Dart package suites passed (792 tests) and the Flutter bridge passed 50 tests; no device/store claim was tested.

**Finding:** Ejenix compiles a separate analyzer-AST Dart subset into custom register bytecode and renders it beneath `EjenixPatchView`/`InterpretedView`. Existing application functions are not rewritten or replaced. App/plugin access is finite and capability-bound. Source also reveals gaps hidden by headline claims, including 63 rather than 62 opcodes, non-byte-identical default CLI bundles, unused Flutter-version compatibility metadata, and delta primitives not integrated into the production view.

**Implication:** Architecture A is technically credible for explicit subtrees and offers useful security/rollback evidence, but it fails the preferred transparent existing-app experience. Its implementation is a reference, not code to copy.

**Next action:** Compare its containment and maintenance advantages against automatic source/Kernel instrumentation.

## 2026-08-22 — Flutter AOT interception map

**Question:** Where can a transparent patch dispatcher enter the Flutter release pipeline, and can stock AOT load Dart Kernel at runtime?

**Investigation:** Traced the installed Flutter 3.47/Dart 3.13 revisions and pinned upstream Flutter/Dart sources through CFE, Kernel, AOT/TFA, `gen_snapshot`, VM precompilation, platform artifacts, engine mapping, and isolate creation.

**Evidence:** [Flutter/Dart AOT execution map](research/flutter-aot.md); all 48 external citations were link-checked.

**Finding:** Flutter release builds produce whole-program `app.dill`, run global pruning/type-flow analysis, then use `gen_snapshot` to emit Android ELF or iOS Mach-O native artifacts. Stock precompiled runtimes explicitly reject Kernel loading. Upstream bytecode/dynamic-module support exists behind a disabled build flag, so it is not a stock-Flutter runtime seam. A pre-AOT dispatch transformation can remain no-engine-fork in principle, but no supported third-party pre-TFA Kernel plug-in was found.

**Implication:** Downloaded Kernel/AOT snapshots are rejected as the Phase 0 default. The cheapest proof is source-overlay callee-entry instrumentation; Kernel stays a version-sensitive follow-up unless a clean pre-TFA seam is demonstrated.

**Next action:** Finish the four-architecture comparison, then test source-overlay dispatch on the exact installed toolchain.

## 2026-08-22 — Shorebird toolchain-class architecture

**Question:** How does Shorebird patch normal Flutter code, and which parts require a custom toolchain?

**Investigation:** Inspected pinned public CLI, updater, Flutter, engine, and buildroot repositories plus official Shorebird architecture documentation; separated public implementation from private claims.

**Evidence:** [Shorebird architecture teardown](competitors/shorebird.md); all cited URLs were checked and the document passed whitespace validation.

**Finding:** Android downloads a compressed binary diff, reconstructs a new architecture-specific `libapp.so`, and executes the replacement Dart AOT program natively. iOS links compatible functions back to signed release AOT code and interprets unlinked code, but the modified Dart compiler/linker/interpreter is private. Shorebird's updater, CLI, and several forks are public; the critical iOS runtime and production backend are not a complete open/self-hostable stack.

**Implication:** Shorebird proves transparent developer experience is attainable with coordinated compiler/VM/engine/tooling control. It does not prove that a stock-engine application interpreter can match its semantics, nor does it satisfy this project's full-open-source constraint as a reusable reference.

**Next action:** Treat Architecture D as a proven but high-maintenance fallback if the no-fork experiments cannot meet semantic and UX thresholds.

## 2026-08-22 — E0 transparent dispatch on stock Dart AOT

**Question:** Can an ordinary function be automatically transformed to choose original AOT or a data-driven interpreted implementation without editing developer source or using a special API at call sites?

**Investigation:** Built an analyzer-guided ephemeral source overlay, versioned stable IDs and dense slots, a strict 300-byte experimental JSON patch, a compiler for changed normal Dart control flow, and a bounded nine-opcode interpreter. Compiled baseline and instrumented native executables with Dart 3.13.0 and measured seven process-isolated samples over five million calls.

**Evidence:** [E0 specification](../experiments/instrumentation/SPEC.md), [results](../experiments/instrumentation/RESULTS.md), and 17 passing experiment tests.

**Finding:** Developer fixture bytes remained unchanged; direct calls and a pre-existing tear-off returned 7 before and 19 after patch activation. Median direct baseline was 2.19 ns/call, instrumented-unpatched 3.55 ns/call (+1.36 ns, 1.62×), and interpreted 214.56 ns/call. The unpatched result passed the predeclared ≤10 ns and ≤5× gate. Source, manifest, 850-byte offset map, and patch were deterministic across distinct absolute roots. Repeated AOT executable bytes were not identical, so no binary reproducibility claim is made.

**Implication:** Architecture B's basic stock-AOT dispatch premise is proven for one synchronous top-level `int Function(int, int)`. This does not prove Flutter/device integration, async/UI semantics, broader Dart coverage, memory, startup/load cost, or stack-trace symbolization.

**Next action:** Run E1 in a stock Flutter Android release on the connected physical device, deliver the interpreted patch locally, and activate it without reinstalling.

## 2026-08-22 — E1 physical Android no-reinstall activation

**Question:** Does the narrow E0 mechanism survive a stock Flutter Android release build and execute changed control flow on a physical device without reinstalling the app?

**Investigation:** Built a release APK from an ephemeral instrumented overlay, installed it once on a physical Redmi Note 10 Lite, changed `StatefulWidget` state, delivered a 329-byte local data patch over adb-reversed localhost HTTP, attempted invalid activation, and manually rolled back. Added app-local content-addressed storage, current/previous state, startup fallback, and stored-content digest verification.

**Evidence:** [E1 Android results](../experiments/patch_loading/RESULTS.md), six patch-lifecycle tests, two Flutter widget tests, and the reproducible [device script](../scripts/e1_android_physical.sh).

**Finding:** Baseline quantity 7 produced 630; the interpreted patch changed the bulk branch to produce 525 while quantity 7 remained in widget state. Invalid input was rejected without displacing the active patch, and rollback restored 630. Package install/update timestamps did not change during the sequence. The final digest-binding hardening was validated by unit tests after the physical run; it did not change the exercised valid-patch path.

**Implication:** Architecture B is technically promising for transparent, narrow, capability-free logic updates on stock Flutter Android. It is not evidence for broad Dart support, patching widget methods/hierarchies, async, state libraries, navigation, iOS execution, production signing, crash-loop health, or store acceptance.

**Next action:** Stop Phase 0 implementation, synthesize the evidence, and request maintainer review before any Phase 0B conformance expansion.

## 2026-08-22 — Phase 0B authorized under conditional source instrumentation ADR

**Question:** Which work should begin first after the conditional Phase 0 result?

**Investigation:** Re-audited the Phase 0 compiler, interpreter, transformer, loader, task history, and maintainer-defined Phase 0B sequencing. Reserved Tasks 08–26 with explicit dependencies, validation boundaries, and pivot triggers.

**Evidence:** [Phase 0B architecture findings](architecture/phase-0b-findings.md), [support matrix](dart-support-matrix.md), and `tasks/08-*.md` through `tasks/26-*.md`.

**Finding:** The current runtime hard-codes two integer arguments, an integer return, integer constants, and nine opcodes. Typed values/signatures are the first dependency for every later receiver, collection, async, capability, compatibility, and UI experiment.

**Implication:** Only Task 08 is active. Later packages remain pending until their dependencies pass or produce an evidence-backed pivot.

**Next action:** Specify and test the explicit typed value/signature boundary before expanding statements or Flutter behavior.

## 2026-08-22 — Task 08 typed values and signatures

**Question:** Can the Phase 0 dispatcher move beyond `int Function(int, int)` without turning the guest/host boundary into unchecked `dynamic`?

**Investigation:** Added explicit recursive schemas, deterministic tagged values, signature-bearing v2 manifests/patches, generalized generated guards, and only the opcodes demanded by five conformance functions. Reviewed malformed input, nullability, canonical maps, return validation, signature binding, and short-circuit semantics.

**Evidence:** [Typed-value research](research/typed-runtime-values.md), [E0B specification](../experiments/instrumentation/SPEC.md), [results](../experiments/instrumentation/RESULTS.md), and 40 passing instrumentation tests including native AOT. Six loader and two Flutter regression tests also passed.

**Finding:** Null, bool, int, finite double, String, List, and String-keyed Map can cross a recursively validated boundary for the five required synchronous top-level functions. Equivalent map insertion orders encode identically; invalid types, non-finite numbers, oversized/nested values, malformed tags, noncanonical maps, signature mismatch, and wrong return paths fail closed. A typed transform patch measured 540 bytes.

**Implication:** Automatic source instrumentation remains viable through the typed-function gate. This does not prove methods, general collection semantics, async, widgets, or physical generalized execution. Expected-signature omission must never be treated as a wildcard, and normal Dart short-circuit behavior must be preserved even in a small subset.

**Next action:** Test ordinary instance methods with generated, explicit receiver-state adapters rather than reflection.

## 2026-08-22 — Task 09 bounded instance receivers

**Question:** Can an ordinary method access necessary instance state in a patch without exposing its Dart object to the interpreter?

**Investigation:** Added class-qualified method discovery/identity, v3 receiver descriptors, same-library generated adapters, typed receiver-read bytecode, class-contained patch compilation, inheritance/override fixtures, and generated-identifier collision handling.

**Evidence:** [Instance-method boundary](research/instance-methods.md), [E0B specification](../experiments/instrumentation/SPEC.md), [results](../experiments/instrumentation/RESULTS.md), and 57 passing instrumentation tests including analyzed/compiled native AOT. Loader and Flutter downstream suites also passed.

**Finding:** Direct, inherited virtual, and tear-off calls to a base method changed from 18.5 to 26.5 under a patch; an override remained 99.0 with a separate ID. Selected explicit public/private field and pure getter reads crossed typed slots. No raw receiver, reflection, arbitrary call, or eager mutation is available. Generated names are deterministically freshened against user identifiers.

**Implication:** Architecture B survives a bounded ordinary-instance-method gate. It does not yet resolve unqualified members, multi-file/private hierarchy, setter transactions, or effectful getters. Those are recorded limitations rather than hidden behavior.

**Next action:** Derive structured control-flow and collection instructions from the required Task 10 conformance cases.

## 2026-08-22 — Task 10 structured control flow and collections

**Question:** Can the small verified stack VM support representative branching,
loops, and bounded collections without turning into a general Dart compiler?

**Investigation:** Added typed lexical locals and definite-initialization joins;
lowered nested conditions, scalar switch, `for`, `while`, and collection `for-in`;
added only the List/Map/Set primitives demanded by conformance tests. Adversarial
review examined fallthrough, host mutation, receiver aliases, insertion order,
malformed values, and loop exhaustion.

**Evidence:** [Control-flow/collection result](research/control-flow-collections.md),
[E0B specification](../experiments/instrumentation/SPEC.md), [results](../experiments/instrumentation/RESULTS.md),
72 passing instrumentation tests including native AOT, six loader tests, and two
focused Flutter widget tests.

**Finding:** A 765-byte patch changed an ordinary native-AOT List transformation
using a C-style loop, indexing, assignment, and add. Host inputs remained unchanged,
aliases were preserved inside the guest invocation, invalid joins/Sets/fallthrough
failed closed, and a global budget stopped an infinite loop. Receiver-origin
mutation is rejected through direct and aliased expressions. Higher-order methods
and closures are explicit diagnostics. Argument mutation is by value and does not
reproduce Dart caller-visible side effects.

**Implication:** Source instrumentation survives this bounded imperative gate, but
the value-copy boundary is a real compatibility limitation and closure feasibility
remains unresolved. No pivot trigger is reached yet.

**Next action:** Define safe guest/AOT exception crossing and `finally` behavior in
Task 11 before adding exception opcodes.

## 2026-08-22 — Task 11 bounded exception semantics

**Question:** Can interpreted `throw`, `catch`, and `finally` preserve ordinary
control transfer while sandbox faults remain uncatchable?

**Investigation:** Derived a version-5 handler table and six control opcodes from
official Dart semantics, then tested nested handlers, pending return/throw
completion, rethrow, malformed metadata, AOT boundary propagation, receiver-thrown
objects, collection access failures, and resource limits. Adversarial review
specifically challenged the host/guest fault classification.

**Evidence:** [Exception runtime research](research/exception-runtime.md),
[E0B specification](../experiments/instrumentation/SPEC.md), [results](../experiments/instrumentation/RESULTS.md),
94 passing instrumentation tests including native AOT, six loader tests, and two
focused Flutter widget tests.

**Finding:** A deterministic 576-byte patch propagated integer `77` to an ordinary
AOT catch with a bounded synthetic trace. Catch-all, nested finally, return/throw
override, and rethrow work for the tested subset. Explicit receiver and predictable
collection failures become bounded guest failures. Malformed bytecode, schema and
stack faults, instruction/collection budgets, `StackOverflowError`, and
`OutOfMemoryError` cannot be caught by guest code. Typed/multiple catches, readable
catch bindings, full Dart stack traces, and general host calls are unsupported.

**Implication:** Structured exception cleanup does not trigger an architecture
pivot. Async resumption must reuse the same three-way outcome and pending-completion
model; inventing a second error channel would be unsafe.

**Next action:** Test whether interpreter frames can suspend and resume across
immediate and delayed Futures without blocking the UI isolate or violating patch
activation/rollback boundaries.

## 2026-08-22 — Task 12 typed async continuations and closure viability

**Question:** Can the source-instrumented runtime preserve typed Dart async
control flow without blocking the isolate or requiring a Dart/Flutter fork?

**Investigation:** Added version-6 typed Future signatures, exact async capability
and await metadata, heap continuations, generated ordinary top-level and instance
guards, saved exception frames/zones/budgets/deadlines, generation pinning, and a
time-bounded closure spike. Adversarial review challenged activation atomicity,
timeout retention, fatal-error classification, and instance-method evidence.

**Evidence:** [Async runtime research and result](research/async-runtime.md),
[E0B specification](../experiments/instrumentation/SPEC.md),
[results](../experiments/instrumentation/RESULTS.md), 122 passing instrumentation
tests, and stock native-AOT top-level and instance fixtures.

**Finding:** Ordinary typed `Future<int>` functions can suspend on immediate and
delayed registered capabilities and resume non-blockingly with zones, handlers,
one total budget, deadlines, and immutable patch generations intact. A top-level
native result changed from 4 to 18 and an instance result from 7 to 28. A bounded
Map-shaped Future result also passed. Failed N+1 activation preserves N, fatal
runtime errors cannot enter guest catches, and timed-out continuations release
their heavy retained state. The two-await patch is 1,022 bytes. Closures, arbitrary
Future calls, and arbitrary class results remain unsupported.

**Implication:** Async does not trigger a pivot, but support is PARTIAL and limited
to explicit typed capabilities. Closure-heavy Flutter/ecosystem code remains a
material architecture condition, and continuation heap memory is not yet measured.

**Next action:** Prove stable declaration identity and a strict compatibility
manifest before formalizing the general host capability registry.

## 2026-08-22 — Task 13 stable identity and compatibility

**Question:** Can patch targets remain deterministic across equivalent builds
while refactors and incompatible artifacts fail closed without source offsets?

**Investigation:** Separated semantic declaration identity from exact signature
compatibility; added structured canonical package/owner/member material,
package-config resolution, strict release-manifest v5, and patch/runtime v7 with
build binding, canonical payload hash, and sequence semantics. Adversarial review
tested manifest forgery, configured path masquerading, noncanonical JSON,
compatibility-table omission, equivocation, and activation atomicity.

**Evidence:** [Function identity research and executed result](research/function-identity.md),
[E0B specification](../experiments/instrumentation/SPEC.md), 139 passing
instrumentation tests including native AOT, six loader tests, and two focused
Flutter widget tests.

**Finding:** Top-level and ordinary instance-method IDs are stable across
whitespace, declaration ordering, and different checkout roots when the same
canonical package URI is resolved. Renames, owner changes, and library moves
change identity; signature changes preserve identity and reject compatibility.
Malformed, forged, stale, equivocal, wrong-release/build, and incompatible
patches reject atomically. Parts and other declaration kinds are unsupported.
The high-water sequence is process-local, and the payload hash is not a
signature.

**Implication:** No stable-identity pivot trigger occurs for the supported
subset. Whole-package/part coverage, production build-fingerprint derivation,
asymmetric signing, and durable replay protection remain explicit conditions.

**Next action:** Formalize the host capability registry before signing and
rollback hardening bind its exact authority set.

## 2026-08-22 — Task 14 frozen host capability authority

**Question:** Can downloaded code use useful compiled services without gaining
reflection, arbitrary native invocation, or mutable runtime authority?

**Investigation:** Replaced the Task 12 test registry with patch/runtime v8 and
a frozen release-owned authority; added canonical versioned contracts, typed
sync/async calls, pinned continuations, stable bounded failures, and fake HTTP,
storage, navigation, logging, and clock adapters. Adversarial review attacked
fallback registration, reconfiguration, descriptor mutation, shipped authority,
error leakage, opcode kinds, and schema boundaries.

**Evidence:** [Host capability research and executed result](research/host-capability-boundary.md),
[E0B specification](../experiments/instrumentation/SPEC.md), 158 passing
instrumentation tests including native AOT, six loader tests, and two focused
Flutter widget tests.

**Finding:** An immutable exact authority set safely mediates the tested
sync/async services. Values are copied and typed; deadlines, output limits,
redacted failures, fatal faults, and side-effect no-fallback rules are distinct.
Raw reflection, channels, FFI, plugins, and host objects are unavailable. The
five domain fixtures are deterministic fakes, not production integrations.
Only detach-only cancellation is implemented, with no generic concurrency or
permission engine.

**Implication:** Capability mediation does not trigger an architecture pivot,
but it cannot make new native authority OTA-patchable. Real adapter, device,
permission, and store-policy evidence remains required.

**Next action:** Bind canonical patch bytes to an asymmetric signature and
durable last-known-good/high-water rollback lifecycle.

## 2026-08-22 — Task 15 asymmetric signing and rollback hardening

**Question:** Can the stock-Flutter loader authenticate exact patch bytes and
recover conservatively across rejection, restart, runtime fault, and rollback
without native cryptographic code or a hosted key service?

**Investigation:** Evaluated maintained Dart Ed25519 packages and selected
`cryptography` 2.9.0's explicit pure-Dart `DartEd25519`. Implemented a strict
canonical, domain-separated E1 envelope and local offline CLI; release-owned
trusted public keys; verification before decode/stage; serialized activation;
content-addressed artifacts; durable high-water sequence; pending/health/LKG
transitions; signed older-target/base selection; and dual checksummed state
copies. Adversarial review drove fixes for input aliasing, redirects, artifact
repair, state consistency, CLI key-file safety, and queue completion semantics.

**Evidence:** [Signing and rollback research/result](research/signing-rollback.md),
25 passing loader tests, 158 passing instrumentation tests during integration,
and two passing focused Flutter widget tests including malformed signed-input
rejection with mounted state preserved.

**Finding:** Exact signed content fails closed before execution; stale,
equivocal, wrong-key, tampered, malformed, incompatible, and corrupt candidates
cannot replace the active runtime. An unconfirmed candidate rolls back on
restart while the authenticated sequence high-water remains. No physical
Android/iOS signature-verification claim has yet been made.

**Implication:** Signing and conservative local rollback do not require a
Flutter/Dart fork or native crypto for the bounded prototype. Production key
custody, protected monotonic state, broader vector/fault injection, health
policy, and physical platform evidence remain conditions.

**Next action:** Test transparent ordinary `Widget.build` interception and a
finite safe widget-construction boundary.

## 2026-08-22 — Task 16 ordinary widget build interception

**Question:** Can a normal app-owned `StatelessWidget.build` return meaningful
patched Flutter UI without a `PatchView`, annotation, raw `BuildContext`, or a
Flutter/Dart fork?

**Investigation:** Specialized the existing callee-entry guard for build-tool-
selected ordinary build methods. Compared direct objects, a generic description,
and pre-registered factories; implemented a frozen program-scoped factory ABI
over bounded node records. Added compiler/runtime/native-AOT/real-Flutter overlay
tests and adversarially reviewed authority, type, bounds, and fallback behavior.

**Evidence:** [Widget research/result](research/widget-patching.md),
[v9 specification](../experiments/instrumentation/SPEC.md), 170 passing
instrumentation tests, four passing Flutter fixture tests, and 25 passing
dependent loader tests.

**Finding:** An ordinary transformed `PricingCard.build` rendered patched text,
an added conditional child, a Column, a font-size change, and a disabled
ElevatedButton in real Flutter tests. Unknown/undeclared factories, malformed or
excessive trees, wrong nested/root types, invalid values, and factory failures
deactivate the slot and use the AOT body. Context, widgets, and callbacks remain
host-owned. The surface is finite and syntax-selected.

**Implication:** The transparent UI pivot trigger does not fire for the bounded
screen, but the result is partial. Signed-controller lifecycle, mounted state,
semantic type resolution, callbacks/keys/context-dependent APIs, broad Flutter,
and real Flutter release/device execution remain conditions.

**Next action:** Prove activation, rebuild, and rollback while an existing
StatefulWidget and its controllers remain mounted.

## 2026-08-22 — Task 17 mounted state preservation

**Question:** Does signed patch activation or rollback replace/corrupt an
existing Flutter State, Element, text controller, or scroll controller?

**Investigation:** Added release-owned runtime configuration across every E1
reset, a deterministic state fixture, and an ephemeral real-Flutter overlay
that executes the actual transformed ordinary pricing guard through signed
activation. Adversarial review fault-injected rollback/recovery state writes,
active continuations, health timing, close behavior, and exact restoration.

**Evidence:** [State preservation research/result](research/state-preservation.md),
29 passing controller tests, seven passing fixture widget tests, and one passing
overlay harness whose generated Flutter lifecycle tests execute the transformed
source.

**Finding:** State/Element identity, integer state, text-controller identity,
text/selection, scroll-controller identity/offset, and lifecycle counts survive
patch-before-construction, mounted activation/rebuild, invalid rejection, and
rollback. Health is confirmed after render. Failed durable transitions restore
the exact verified prior state/runtime or enter fail-closed recoveryNeeded base.

**Implication:** Behavior dispatch can preserve installed AOT-owned state without
a fork. State layout migration and arbitrary stateful method changes remain
unsupported. Tree remount is not process restart; physical release evidence is
pending. Runtime-first recovery also has an explicit in-progress visibility
window during durable writes.

**Next action:** Test Riverpod provider/Notifier logic driving an existing
ConsumerWidget through the same dispatch lifecycle.

## 2026-08-22 — Task 18 Riverpod interoperability

**Question:** Can existing Riverpod state, providers, notifiers, subscriptions,
and a mounted `ConsumerWidget` survive while application-owned business logic
switches between AOT and a signed interpreted patch?

**Investigation:** Added a focused Riverpod 3.4.2 pricing graph with a Notifier
input, synchronous derived Provider, AsyncNotifier result, and ConsumerWidget.
The actual transformed ordinary pricing function was exercised through signed
activation, normal dependency invalidation, invalid rejection, health
confirmation, and rollback. Provider/container/notifier/subscription identity
was asserted throughout, and explicit invalidation was tested separately.

**Evidence:** [Riverpod research/result](research/riverpod-interoperability.md),
eleven passing fixture tests including the focused widget flow, and a passing
transformed real-Flutter overlay test. The resolved Riverpod package Dart trees
were unchanged during that overlay run.

**Finding:** Normal Riverpod dependency changes recompute through the active
patch while retaining framework-owned state and subscriptions. Cached Provider
and AsyncNotifier results do not automatically change merely because a patch is
activated or rolled back; explicit invalidation is available but was not made a
transparent production mechanism. Async cancellation, overlap/retry, generated
providers, and patched ConsumerWidget bodies remain unproved.

**Implication:** The representative Riverpod flow does not require a Riverpod,
Flutter, or Dart fork. A generation-to-reactive-framework invalidation policy is
a developer-experience condition if immediate activation is required.

**Next action:** Test an ordinary GoRouter A/B route decision, reevaluation
semantics, builder boundary, rollback, and native deep-link exclusions.

## 2026-08-22 — Task 19 GoRouter navigation interoperability

**Question:** Can a signed patch change an ordinary app-owned route decision
while an existing GoRouter and mounted route state remain intact?

**Investigation:** Pinned go_router 17.5.0 and generated a real Flutter overlay
that transforms `chooseDestination`, compiles and signs its replacement, and
keeps the route table/builders in installed AOT code. The generated tests cover
ordinary navigation reevaluation, activation/rollback without refresh, a
pre-existing router listener, push/pop, malformed rejection, mounted state, an
unmatched route, and a host-only destination allow-list. Tagged upstream source
was inspected for redirect, refresh, cached builder, and license behavior.

**Evidence:** [Navigation research/result](research/navigation-interoperability.md),
clean focused analysis, and one passing outer instrumentation test that ran two
generated Flutter widget tests through the actual signed transformed path.

**Finding:** The next ordinary navigation selected compiled destination B under
the patch and A after rollback without replacing the router or underlying
mounted state. Activation and rollback did not trigger redirect/listener
reevaluation. Builder closure replacement and patch-driven navigation authority
were not proved; no native deep-link declaration changed.

**Implication:** Installed pure-Dart route decisions remain viable under source
instrumentation. Immediate current-route response needs an app-owned generation
signal, and compiled route/builder/native boundaries remain explicit.

**Next action:** Run the intentionally small BLoC/Cubit interoperability check,
stopping once it adds framework lifecycle evidence beyond Riverpod.

## 2026-08-22 — Task 20 BLoC/Cubit interoperability

**Question:** Can a pre-existing Cubit, stream subscription, provider lookup,
and mounted BlocBuilder retain state while ordinary inputs cross the current
signed patch guard?

**Investigation:** Pinned bloc 9.2.1 and flutter_bloc 9.1.1. Added one
synchronous pricing Cubit whose normal methods call the transformed app-owned
pricing function. The real generated Flutter overlay activated the existing
signed E1 patch, confirmed health, rejected malformed bytes, rolled back, and
counted both external stream emissions and BlocBuilder builds.

**Evidence:** [BLoC research/result](research/bloc-interoperability.md), clean
focused fixture/instrumentation analysis, and a passing outer test whose
generated Flutter suite exercised the transformed and signed path.

**Finding:** The same Cubit/provider/panel and ongoing pre-activation stream
subscription produced exact prices 630, 490, 560, and 720 across base, patch,
rejection, and rollback. Build count advanced 1→2→3→4→5 only for Cubit inputs;
activation, health, rejection, and rollback emitted/rebuilt nothing. Event Bloc,
async/concurrency, persistence, and direct Cubit-method patching remain unproved.

**Implication:** The bounded lifecycle adds no BLoC-specific pivot trigger, but
patch generation is not automatically a framework event. Broader BLoC features
remain outside the evidence.

**Next action:** Prove whether a package-preserving multi-unit overlay can patch
local and hosted pure-Dart dependency code without mutating package sources.

## 2026-08-22 — Task 21 pure-Dart dependency patching

**Question:** Can selected ordinary Dart declarations in local and hosted
dependencies be instrumented without changing their package identity or source?

**Investigation:** Added an explicit library-unit transform mode and ephemeral
package overlay. IDs across selected units are sorted into one dense global slot
table, installed once by the transformed entrypoint; manifest v8 binds the
sorted library URI set. Adversarial review added strict ID order, valid global
unit manifests, real-path/output/runtime pinning, and AST-based import exclusion.

**Evidence:** [Function/package identity result](research/function-identity.md),
[format specification](../experiments/instrumentation/SPEC.md), 3/3 focused
tests, 169/169 non-Flutter regressions, and 33/33 patch-loader tests. The local
683-byte patch passed native AOT direct/tear-off calls; the hosted 663-byte
collection patch passed a Dart-process test with the original cache file hash
unchanged. The broader run's one missing Flutter native-assets generated file is
recorded in Task 21 and did not affect these tests.

**Finding:** Explicit selected pure-Dart units can retain canonical package URIs
and share one deterministic runtime table without a compiler fork. The local
path package works under native AOT; the hosted proof is JIT and imports an
internal owned unit directly. No transitive package graph, parts, Flutter/SDK,
FFI/native, or arbitrary generated code is supported.

**Implication:** Dependency patching remains viable as explicit opt-in build
selection, but general package coverage needs a real resolved source graph and
more filesystem hardening. Native dependency updates remain store releases.

**Next action:** Execute the predeclared stock/instrumented/patched performance
matrix and derive a measured selective-instrumentation policy.

## 2026-08-22 — Task 22 performance and selective instrumentation

**Question:** Does every selected guard impose an unacceptable unpatched tax,
and which source categories should enter an overlay by default?

**Investigation:** Predeclared a host-AOT protocol with 10 million calls, two
warmups, 15 isolated samples, deterministic order, raw median/p95/MAD, checksums,
and a <=10 ns/<=5x hot-leaf gate. Independent review required an additive
protocol amendment and replacement schema-v2 runs with build/sample provenance,
complete relevant source hashes, activation locks, and checksum enforcement.
Selective planning was implemented and tested separately.

**Evidence:** [Task 22 result](../experiments/instrumentation/RESULTS.md),
[protocol](../experiments/instrumentation/tool/performance/PROTOCOL.md), raw host
SHA-256 `b1dbb76e…e48a`, raw activation SHA-256 `7e63e784…b6c`, clean analysis,
5/5 selection/package tests, 4/4 signed-patch tests, and 29/29 controller tests.

**Finding:** Stock was 2.0103 ns/call; instrumented-unpatched 6.0329 ns/call,
adding 4.0226 ns at 3.0010x, so both gates pass. An unrelated active slot was
6.4734 ns and interpreted execution 557.9237 ns. The signed 1,238-byte envelope
for a 795-byte patch verified and installed in 3.309 ms median; Ed25519 accounted
for 3.083 ms. The instrumented executable was 492,496 bytes (+8.62%) larger, but
that includes the complete runtime and cannot be attributed to guard count.

**Implication:** Current hot-path evidence does not trigger a pivot or justify a
new lookup optimization. App code is default-selected, pure-Dart dependencies
opt in, and generated/SDK/Flutter/native boundaries stay excluded. Device and
broad semantic performance remain required evidence.

**Next action:** Attempt the required physical Android one-install cross-feature
sequence; if no device is available, record the external blocker and continue to
the independently mandatory physical-iPhone baseline.

## 2026-08-22 — Task 23 physical Android cross-feature validation

**Question:** Do the independently successful business, async, UI, ecosystem,
rejection, rollback, and persistence cases compose in one current physical
Android Release installation?

**Investigation:** Repeated `adb devices -l` and `flutter devices` audits were
performed before a build or install. The predeclared sequence requires a real
device, exactly one install, process restarts, signed patches, and install-time
evidence; an emulator was not substituted.

**Evidence:** `Task 23` records
the absent device and the still-unexecuted assertions. Phase 0's earlier
physical Android result remains in its original evidence files.

**Finding:** No physical Android was connected, so the expanded Phase 0B device
sequence is blocked. This is not a technical failure of the runtime and is not
a successful composition result.

**Implication:** Host/native-AOT and Flutter-test evidence cannot be promoted to
current cross-feature physical-device support. Android composition, restart,
device memory/startup, and current signed activation remain Phase 1 conditions.

**Next action:** Run the unchanged sequence when hardware is available, without
reinstalling between patch stages.

## 2026-08-22 — physical Android rerun

**Question:** Does the prepared narrow E1 physical sequence execute now that the
Android device is connected over Wi-Fi?

**Investigation:** Ran `scripts/e1_android_physical.sh
192.168.50.135:39083`. The script built the transformed Flutter Release APK,
performed exactly one streamed install, used `adb reverse` for local delivery,
and exercised base UI, signed activation, mounted quantity preservation,
invalid-patch retention, rollback, and package timestamp comparison.

**Evidence:** `Task 23` and
`experiments/patch_loading/.dart_tool/device-evidence/` contain the APK size,
signed envelope size, install receipt, UI XML snapshots, E1 status log, and
before/after package timestamps.

**Finding:** The narrow physical E1 sequence passed. The 50,722,656-byte APK was
installed once; the 1,349-byte signed envelope activated, invalid input retained
the good patch, rollback restored base, and package timestamps did not change.

**Implication:** The previous Android hardware blocker is cleared for this
baseline, but this does not prove Task 23's broader async/UI/Riverpod/navigation
and restart composition. Those stages remain pending.

**Next action:** Extend the installed-release fixture and repeat without
reinstalling for the broader cross-feature stages.

## 2026-08-22 — Task 24 physical iOS baseline

**Question:** Can the smallest transformed stock-Flutter scenario build, sign,
install, interpret a signed data patch, reject tampering, roll back, and persist
across restarts on a physical iPhone?

**Investigation:** Added only the missing stock iOS host and a compile-time-gated
evidence runner. The real overlay transformed `calculatePrice`, generated an E0
payload and Ed25519 E1 envelope, and was passed as `FLUTTER_TARGET` to a Release
device build. Signing prerequisites and installed profiles were audited before
installation. A one-install local harness was prepared and independently
reviewed, including first-frame health, signature-tampered rejection, exact
receipt order, and three-process restart assertions.

**Evidence:** [iOS feasibility report](research/ios-feasibility.md),
`Task 24`, five focused tests, and the
recorded build artifacts. The unsigned transformed compile produced arm64
Runner and AOT App binaries with no Kernel/dill asset. The signed attempt failed
with no configured Apple account or matching provisioning profile.

**Finding:** Stock iOS Release/AOT compilation of the instrumented path passes.
Physical signing, installation, launch, interpreted behavior, invalid-signature
handling, rollback, restart, persistence, and executable-memory behavior are
unexecuted because provisioning is unavailable.

**Implication:** There is no compile-time evidence that forces a Flutter/Dart
fork on iOS, but the mandatory physical interpreter gate is still open. The
result makes no App Store compliance claim.

**Next action:** Configure an authorized account and matching profile, then run
the prepared one-install sequence before expanding iOS scenarios.

## 2026-08-22 — physical iOS retry after reported provisioning update

**Question:** Does the connected USB iPhone now accept the signed transformed
Release build and complete the one-install patch/rejection/rollback/restart
sequence?

**Investigation:** Ran `scripts/e1_ios_physical.sh` through XcodeBuildMCP with
the connected physical device and the configured development team. The overlay,
E0/E1 payload generation, and device visibility checks passed before the signed
device build.

**Evidence:** The run's redacted `build.json` records XcodeBuildMCP errors:
`No Account for Team "PMYCABU9X8"` and `No profiles for
'dev.hyfens.conformance' were found`. No install invocation was reached.

**Finding:** iOS physical validation remains blocked at signing. Certificate
material in the keychain alone is insufficient; the matching Apple account and
provisioning profile must be available to Xcode's signing environment.

**Implication:** No iOS runtime, rejection, rollback, restart, persistence, or
executable-memory claim can be made yet.

**Next action:** Add the Apple Developer account in Xcode Settings → Accounts,
install/download a development profile for the exact bundle ID and device, then
rerun the unchanged harness.

## 2026-08-22 — Task 25 expanded iOS and store-policy classification

**Question:** Which representative changes cross store/native boundaries, and
can the successful host scenarios be expanded on the physical iPhone?

**Investigation:** Rechecked current official Apple and Google/Android sources,
separated facts from project interpretation and unknowns, and normalized a
cross-store change matrix to three conservative engineering gates. Physical
expansion was considered only after Task 24's baseline prerequisite.

**Evidence:** [Change matrix](store-policy/change-matrix.md), updated
[Apple](store-policy/apple.md) and [Google Play](store-policy/google-play.md)
research, and `Task 25`. All 28 unique
official-source links in the policy package returned HTTP 200 during validation.

**Finding:** Interpreted Dart business fixes, widget changes, navigation, and
pure-Dart dependency changes remain **POLICY REVIEW REQUIRED** on the
conservative cross-store gate. New native/build metadata, permissions, plugins,
SDKs, and host capabilities are **STORE RELEASE REQUIRED**. Only passive values,
assets, and localization consumed by fixed existing paths are **LIKELY OTA-SAFE
ARCHITECTURALLY**, subject to all app-specific rules. Expanded physical iOS is
blocked by Task 24's provisioning prerequisite.

**Implication:** The capability-limited interpreter improves technical security
but is not a policy safe harbor. Production code-bearing OTA remains gated on
platform-specific review, independently of device feasibility.

**Next action:** Use the matrix as a release-generation deny/review gate, obtain
written platform guidance for the concrete runtime, and rerun the physical iOS
baseline before any expanded iOS scenario.

## 2026-08-22 — Task 26 Phase 0B architecture review

**Question:** Does the accumulated evidence justify continuing stock-Flutter
source instrumentation, or has a pivot/stop trigger fired?

**Investigation:** Audited Tasks 08–25, the semantic support matrix, host/native
AOT and Flutter evidence, security lifecycle, corrected benchmark raw data,
blocked device work, and current policy classification. Compared explicit
views, source instrumentation, pre-TFA Kernel transformation, and a full
compiler/toolchain fork. An independent final review checked the written result
for blocker/high inconsistencies and evidence overreach.

**Evidence:** [Phase 0B review](history/reviews/PHASE_0B_REVIEW.md),
[ADR 0002](adr/0002-continue-source-instrumentation-with-phase-1-gates.md),
[architecture ledger](architecture/phase-0b-findings.md), and
[support matrix](dart-support-matrix.md). Targeted instrumentation,
signing/controller, iOS harness, provenance, link, and document-structure checks
passed.

**Finding:** No pivot trigger positively fired. Dispatch, bounded async,
ordinary StatelessWidget build interception, and named-declaration compatibility
passed their bounded gates. Physical iOS runtime, expanded Android composition,
closures/useful coverage, representative source fidelity, binary scaling, and
upgrade cost remain open or blocked rather than passed.

**Implication:** Architecture B remains the best-supported research direction,
but is not a production selection. Device, coverage, build-fidelity,
performance, security, and policy conditions must be satisfied before broader
claims or production-shaped delivery.

**Next action:** **PROCEED TO PHASE 1 WITH CONDITIONS**, subject to maintainer
approval. Stop now; the proposed Phase 1 task list is not authorized or executed.

## 2026-08-22 — current-source physical device closure after AUVANA signing

**Question:** Do the previously blocked Android and iOS gates pass when run on
the connected devices with the correct Apple team, rather than being inferred
from host tests or an unsigned build?

**Investigation:** Re-ran the current-source Android narrow sequence over Wi-Fi,
the broad Android one-install sequence, the dedicated iOS USB baseline, and the
broad iOS USB sequence. The iOS builds used the AUVANA VENTURES PRIVATE LIMITED
team (`CYT7A4VAZ3`) selected in the fixture's Signing & Capabilities settings.
USB staging placed signed data files in the app Documents directory; it did not
require a second network transport.

**Evidence:**

- Android narrow: `scripts/e1_android_physical.sh 192.168.50.135:39083`.
- Android broad: run `android-cross-20260822-6` under
  `experiments/patch_loading/.dart_tool/android_e1_runs/android-cross-20260822-6/evidence/`.
- iOS narrow: run `ios-usb-20260822-current` under
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_runs/`.
- iOS broad: run `ios-cross-20260822-1` under
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_cross_runs/`.

**Finding:** Both platforms executed the bounded signed interpreter without
reinstall. Android and iOS receipts recorded base/business transitions,
capability-mediated async on the broad path, a rendered widget hierarchy change,
Riverpod recomputation, tampered-signature rejection with the last patch kept,
rollback to base, and persistence after two process restarts. The iOS Release
artifacts were arm64 and had no `kernel_blob.bin` or `.dill`; entitlements bind
the AUVANA team to `dev.hyfens.conformance`.

**Implication:** The earlier Phase 0B recommendation was not evidence-backed for
physical iOS or broad Android until these runs. Those gates are now verified for
the declared bounded fixtures. This does not prove arbitrary Dart/Flutter,
production transport, or App Store/Google Play acceptance.

**Next action:** Update the final Phase 0B report/task ledgers with the physical
evidence, then stop and await maintainer review before any Phase 1 work.

## 2026-08-23 — Task 41 approval closure and first local control-plane slice

**Question:** Can the approved productization foundation begin without changing
the runtime trust boundary or introducing a managed-service dependency?

**Investigation:** Applied the explicit maintainer approval record for the
Apache-2.0 OSS core, open-core boundary, customer/local signing custody, and
Dart `dart:io` single-node stack. Implemented `packages/control_plane/` with
filesystem metadata, content-addressed artifacts, hashed credentials, tenant
checks, exact Patch Format v1 admission, promotion, delivery lookup/fetch,
redacted audit, and a versioned HTTP adapter. Added the CLI `deploy` command
which verifies local bytes before upload.

**Evidence:** `packages/control_plane` `dart analyze` passed; seven package
unit/HTTP tests passed, including valid Ed25519 admission, invalid-signature
quarantine, foreign-tenant not-found behavior, delivery-scope rejection,
idempotency, optimistic concurrency, promotion, update lookup, artifact fetch,
and audit persistence. The CLI analyzer and existing regression suite plus the
deploy-command registration test passed. A local service was then started,
`tool deploy` registered/uploaded/promoted an existing signed Flutter artifact,
and authenticated update lookup plus raw artifact fetch returned bytes that
matched the local patch byte-for-byte. No physical device or Flutter runtime
self-host activation was claimed.

**Finding:** A bounded local product seam is implementable in stock Dart without
private signing-key custody or changes to Patch Format v1/runtime authority.
The service is a distribution/policy boundary only; its current evidence is
local unit/HTTP plus one local CLI/artifact end-to-end run, not production,
cloud, physical-device, or beta readiness.

**Implication:** Continue Task 41 P0/P1 foundation work within the approved
scope. Keep P1D-02 direct stale-byte rejection, Flutter self-host E2E, broader
security/concurrency campaigns, and physical device delivery as explicit gates.

**Next action:** Add the local Flutter self-host fixture/deploy evidence if the
existing device seam can be used safely, run consolidated repository checks,
and stop at the Task 41 maintainer-review gate before P2.

## 2026-08-23 — Task 42 authenticated iOS runtime delivery and Android gate

**Question:** Does the stock Flutter generated bootstrap consume the
authenticated `/v1` lookup/fetch contract on a physical device, preserve
verified behavior across restart/outage, and reject exact stale bytes after
rollback?

**Investigation:** Added the bounded read-only delivery adapter, propagated
runtime configuration through the release build as redacted `dart-define`
metadata, and ran host tests plus a real CLI → local control-plane → E1 flow.
Built an arm64 Flutter Release IPA with the AUVANA VENTURES PRIVATE LIMITED
team (`CYT7A4VAZ3`), installed it once on the USB-connected iPhone, and made
the local service reachable on the Mac's private LAN address. Deployed a
signed pricing patch, retrieved the fixture receipt over USB, restarted the
app, stopped the service, and retrieved the receipt again. Separately ran the
existing iOS USB cross-feature fixture with the exact old signed sequence-4
bytes after rollback.

**Evidence:** Generated iOS release `sha256:958583067a135ff60aa3a7cc0838e5788662dd073d630cde3a33c417b28d88a5`; generated patch
size 2,069 bytes; base receipt price 540; patched receipt price 450 before and
after restart/service outage. Direct evidence is under
`fixtures/flutter_conformance_app/.dart_tool/e1_ios_cross_runs/ios-task42-usb-20260823-r2/evidence/`.
Host adapter/service tests, CLI E2E, format/analyze, and fixture tests passed.
`adb devices -l` and `adb mdns services` returned no Android device; known Wi-Fi
endpoints refused connection.

**Finding:** The authenticated adapter can feed exact bytes to the existing
E1 authority on a physical iPhone without a Flutter/Dart fork or a special
patch widget. E1 rejected the supplied stale bytes as `replayAfterRollback`
and retained BASE/high-water 4. The generated bootstrap retained a valid patch
when the service was unavailable. This does not establish Android service-path
evidence, arbitrary Flutter compatibility, transport security, or store
approval.

**Implication:** Task 42's iOS/runtime and P1D-02 evidence is materially
stronger, but Android remains an environment gate. Do not claim the new
cross-platform integration complete or infer Android from iOS.

**Next action:** Run the same authenticated physical sequence on Android after
ADB/Wi-Fi discovery is restored, then stop for maintainer review before any P2
work.

## 2026-08-23 — Task 42 authenticated Android runtime delivery completed

**Question:** Does the generated stock-Flutter Android Release bootstrap
consume the authenticated `/v1` lookup/fetch contract on the physical Wi-Fi
device, preserve a verified patch across restart/outage, and coexist with the
direct stale-byte gate?

**Investigation:** Reconnected the physical Redmi Note 10 Lite as explicit
ADB-Wi-Fi serial `192.168.50.135:38657`. Ran the existing one-install direct
cross-feature script, then built a generated arm64 Release APK with
`tool release android`, changed the ordinary pricing function, generated a
2,069-byte Ed25519-signed patch with `tool patch`, and promoted it through the
authenticated local service with `tool deploy`. The final generated APK was
installed once; logcat supplied a fixture-only receipt because Release APKs
are not debuggable and `run-as` cannot read their app Documents directory.
The app was force-stopped/restarted, then the service process was stopped and
the app was force-stopped/restarted again.

**Evidence:** Direct run
`experiments/patch_loading/.dart_tool/android_e1_runs/android-task42-wifi-20260823-r2/evidence/`
recorded all 13 expected stages. Generated run
`fixtures/flutter_conformance_app/.dart_tool/e1_control_plane_runs/android-task42-wifi-20260823-r1/evidence/`
recorded base receipt `540`, authenticated patch receipt `450`, restart
restoration, outage restoration, unchanged package install timestamps, and
an arm64 Release APK of 52,066,144 bytes. The redacted durable summary is
`docs/research/evidence/task42-android-control-plane.md`.

**Finding:** Stock Flutter Android execution accepted the same generated
authenticated delivery boundary already proven on iOS. Ordinary Dart logic
changed without reinstall; E1 remained authoritative for signature, release,
sequence, health, rollback, and stale-byte rejection. The first retry's
missing receipt was a fixture routing bug (`usbDirectory` selected the USB
sink in Wi-Fi mode), not a runtime or device failure; correcting it and
rerunning produced a complete direct pass.

**Implication:** Task 42's bounded physical runtime-delivery gate is complete
on both declared Android and iOS fixtures. This does not promote the project
to beta/production readiness and does not resolve power-loss, performance,
independent-app, transport-security, or store-policy conditions.

**Next action:** Stop at maintainer review. Do not begin P2/cloud work or
expand the supported runtime semantics from this evidence.

## 2026-08-23 — P2 hosted-like foundation and physical iOS regression

**Question:** Can the bounded local control plane use durable relational
metadata and immutable S3-compatible objects without becoming the runtime
trust authority?

**Investigation:** Added PostgreSQL migrations/adapter, tenant-scoped
idempotent metadata and audit persistence, provider-neutral S3-compatible
storage with standard AWS Signature V4 object request signing, request limits,
revocation, readiness/liveness, process-local metrics, structured redacted
errors, Docker Compose deployment, backup/restore scripts, and a bounded
load sampler. Ran the hosted-like CLI release/patch/deploy path, update lookup,
artifact fetch, database/object/service restarts, object outage, and restore.
Built a stock arm64 iOS Release IPA with the AUVANA team, installed once on
the USB iPhone, observed base `540`, promoted an exact signed patch, restarted
without reinstall, and observed `450` across two restarts.

**Evidence:** `packages/control_plane` tests with PostgreSQL and MinIO,
`deploy/p2/docker-compose.yml`, `scripts/p2-postgres-{backup,restore}.sh`,
`scripts/p2-load-test.py`, and
[`docs/research/evidence/p2-hosted-like-2026-08-23.md`](research/evidence/p2-hosted-like-2026-08-23.md).
The bounded load sample used 80 non-mutating requests at concurrency 8:
40 update checks and 40 artifact fetches; all succeeded. The observed
update-check p50/p95/p99 were 84.288/131.267/140.372 ms and artifact-fetch
67.986/110.737/121.522 ms on the disposable single-node Mac/Compose setup.

**Finding:** Hosted persistence and object delivery are replaceable adapters;
the server can return `PATCH_AVAILABLE` or a bounded dependency failure while
E1 still verifies exact bytes, signature, release, capability, high-water, and
health locally. PostgreSQL/object/service recovery and backup/restore were
observed. The physical iOS hosted-like path passed base-to-patch activation and
restart persistence. Android hosted-like physical validation was not run in
this continuation because the declared phone answered ping but exposed no
ADB wireless-debugging port; prior Task 42 Android evidence is not relabeled.

**Implication:** P2 can be reviewed as a bounded hosted-like foundation, not
as production infrastructure or beta readiness. Independent-app validation,
power-loss, performance/async/multi-function campaigns, production audit/key
recovery, TLS/proxy deployment review, and store-policy review remain gates.

**Next action:** Maintainer review of `docs/P2_MANAGED_CLOUD_REVIEW.md` before
any P3 rollout/observability or broader product work.

## 2026-08-23 — P2 hosted-like Android physical validation completed

**Question:** Can the stock arm64 Android Release consume the authenticated
P2 control-plane delivery path on the reachable Wi-Fi device, preserve the
active patch across restart and service outage, and pass the direct runtime
security/cross-feature gates?

**Investigation:** Reconnected the physical Redmi Note 10 Lite as ADB-Wi-Fi
serial `192.168.50.135:38951` (Android 16/API 36). Built a fresh stock Flutter
arm64 Release APK with hosted delivery configuration, installed it once,
promoted a 2,069-byte Ed25519-signed patch through the LAN-bound PostgreSQL /
MinIO Compose control plane, force-stopped and relaunched the app, stopped and
restarted the control-plane process, and then ran the direct cross-feature
harness on the same device.

**Evidence:** Hosted-like log captures recorded base `price=540`, patch
`price=450`, signed-patch restoration after restart, offline retention during
control-plane outage, readiness recovery, and unchanged Android package
install timestamps. The direct evidence directory
`experiments/patch_loading/.dart_tool/android_e1_runs/android-p2-followup-20260823-r1/evidence/`
contains receipts for business (`540→450`), async (`asyncPrice=481`), UI,
Riverpod, invalid-signature rejection, rollback, stale/replay rejection, and
rollback persistence.

**Finding:** The P2 hosted-like Android device gate is PASS for the declared
conformance fixture. A one-install stock-Flutter Android runtime accepted the
same authenticated delivery boundary already proven on iOS; service
availability was not required to retain an already verified patch. E1 rejected
the invalid signature and replayed stale sequence after rollback.

**Implication:** The prior environment-gated Android statement must not be
carried forward as the current result. Android and iOS physical hosted-like
evidence now exists for the declared fixture, while independent-app,
performance, power-loss, production-security, and store-policy gates remain
open.

**Next action:** Stop at the P2 maintainer-review boundary. Do not begin P3 or
infer arbitrary Flutter/customer-app support from this fixture evidence.

## 2026-08-23 — P2 closure-hardening evidence completed

**Question:** Do the P2 persistence, delivery, credential, provenance, and
failure boundaries survive a coupled recovery and transport-hardening pass
without changing the frozen runtime authority?

**Investigation:** Added digest inventory/reconciliation, durable local and
PostgreSQL audit-chain export/verification, credential issuance with expiry and
revocation, explicit private-CA support for CLI deployment, object backup and
restore scripts, and the customer/local signing-key recovery boundary. In a
disposable Compose project, backed up PostgreSQL and MinIO together, destroyed
and recreated both stores, restored them, verified exact bytes and local
signature, reconciled metadata/objects, exported and tamper-checked the audit
chain, and replayed deployment idempotently. Ran a real nginx TLS proxy with a
valid private CA/server leaf, deployed with certificate A, rotated to a
different CA/leaf B, confirmed old-CA rejection and new-CA success, and fetched
the exact artifact after rotation. Stopped/restarted dependencies and
interrupted a throttled artifact PUT during control-plane restart, then retried
with the same idempotency key. Ran the secondary repository-owned fixture and
the consolidated Dart/Flutter tests.

**Evidence:** `tasks/44-p2-closure-hardening.md`,
`docs/research/evidence/p2-hosted-like-2026-08-23.md`,
`docs/security/signing-key-recovery.md`, control-plane closure tests, the
coupled restore digest (`sha256:5283dcce3346864a2ad3f8684afc1250042eb6911564cdde4b04a57173e48e14`),
and the private TLS/rotation command captures. Control-plane external tests
passed 27/27; CLI serial tests passed 39/39; both Flutter fixture suites,
root tests, formatting, analysis, shell syntax, and Python compilation passed.

**Finding:** Coupled metadata/object restore, digest reconciliation, bounded
credential lifecycle, audit export/tamper detection, private TLS/certificate
rotation, outage recovery, and restart-during-mutation retry are verified for
the single-node operator fixture. The service never regenerates or re-signs
artifacts, and E1 remains the runtime authority. The secondary fixture is not
an independent customer application.

**Implication:** The P2 foundation remains suitable for maintainer review and
bounded self-hosted engineering. These results do not close independent-app,
true-power-loss, performance/async/multi-function, production HA/DR,
production signing-key recovery, public-ingress, or store-policy gates.

**Next action:** Maintainer review of `docs/P2_MANAGED_CLOUD_REVIEW.md` and
Task 44. Do not start P3, beta, or production work automatically.

## 2026-08-23 — P2 final evidence gates

**Question:** Which remaining P2 evidence gates can be executed honestly with
the connected Android/iOS devices and current repository evidence, and does
the bounded async benchmark failure indicate a runtime defect?

**Investigation:** Audited the physical Redmi Note 10 Lite over ADB Wi-Fi and
the USB iPhone, searched for an independently maintained Flutter application,
re-ran the retained Android performance reducer, and executed the async
benchmark. The first async run failed because the fixture was outside the
configured package URI root. The benchmark now copies that fixture into an
isolated temporary package root; no transformer or runtime semantic rule was
relaxed. The 10,000-iteration run and focused compiler/native-AOT tests then
passed. Reviewed signing-key recovery, public-ingress/object/HA-DR/image
provenance, audit, iOS diagnostic/performance, and power-loss boundaries.

**Evidence:**
`docs/research/p2-final-evidence-gates-2026-08-23.md`,
`docs/research/evidence/p2-final-async-benchmark-20260823.json`, Task 35's
15-sample physical Android reducer, the retained Task 36/42 iOS evidence,
and `docs/store-policy/p2-review-package.md`.

**Finding:** The async issue was a benchmark harness setup defect, not a
semantic interpreter failure. P1D-05 is closed only for the declared Android
reducer and P1D-08 is closed only for the bounded capability-mediated
`Future<int>` subset. Independent-app, true power-loss, iOS diagnostics and
performance, interpreter attribution, physical multi-function activation,
production operations, and store-policy review remain open.

**Implication:** Technical P2 single-node hosted-like evidence is sufficient
for maintainer review, but beta and production claims remain blocked. P3 must
not start automatically.

**Next action:** Maintainer review of Task 45 and the final evidence report;
authorize a future independent-app/platform-gate task only if desired.

## 2026-08-23 — Task 46 external-gate stop

**Question:** Is a genuinely independent maintained Flutter application
available to exercise the highest-priority remaining beta gate?

**Investigation:** Audited all repository `pubspec.yaml` projects, fixture
roots, generated benchmark copies, and the supplied P2 review context. The
available applications are `fixtures/flutter_conformance_app`,
`fixtures/flutter_toolchain_app`, and a generated `.phase1c-android-bench`
copy; all are repository-owned validation assets.

**Evidence:** Task 46 inventory and the current P2 final-gate report. No
external ownership, source identity, release pipeline, or maintainer-supplied
application was present.

**Finding:** No qualifying `INDEPENDENT_APP` evidence exists. P1D-07 remains
`OPEN / BETA BLOCKER`. The prescribed stop rule was followed; no substitute
fixture, unsupported-change claim, or lower-priority external gate was run.

**Implication:** Technical P2 remains bounded-complete for maintainer review,
but beta and production readiness remain blocked. No runtime, compiler,
instrumenter, signing, delivery, or mobile release artifact changed.

**Next action:** Maintainer must supply or explicitly identify an independent
maintained Flutter application before P1D-07 can be exercised. P3 remains
prohibited.

## 2026-08-23 — Task 47 residual physical and production evidence

**Question:** Can one signed Patch Format v1 artifact activate multiple
already-supported slots on the connected physical Android and iOS fixtures,
and which remaining P2 production gates can be narrowed without changing the
runtime architecture?

**Investigation:** Composed a deterministic 7,505-byte Ed25519-signed v1
artifact containing business, bounded-async, and widget slots. Ran host
decode/bridge round-trip and atomic batch tests. Built and installed the stock
Flutter Release APK once on the Redmi Note 10 Lite over ADB Wi-Fi, then
activated, restarted, rejected a tampered artifact, rolled back, and restarted
again. Built and installed an arm64 Release iOS app once with the AUVANA
VENTURES PRIVATE LIMITED team, staged patch bytes over USB, corrected a
leading-slash `ios-deploy` path after the expected fail-closed setup failure,
and completed the same business/async/UI lifecycle. Ran the bounded host workload
profile and disposable local ingress/signing checks. Reviewed object
durability, HA/DR, SBOM/provenance, audit, power-loss, and iOS diagnostic/
performance boundaries without relabelling design or environment gaps.

**Evidence:**
[`p2-multi-function-physical-2026-08-23.md`](research/p2-multi-function-physical-2026-08-23.md),
[`p2-interpreter-attribution-2026-08-23.md`](research/p2-interpreter-attribution-2026-08-23.md),
[`p2-production-hardening-2026-08-23.md`](research/p2-production-hardening-2026-08-23.md),
Task 47 host/atomicity tests, Android run
`android-multi-20260823T125124Z-61061`, and authoritative async-aware iOS run
`ios-multi-task47-async-20260823T132423Z-10665`.

**Finding:** Android and iOS now prove the declared three-slot
multi-function lifecycle with one install per run and three process groups;
both receipt surfaces assert business, async, and widget outputs at activation
and persistence (marker/final rows omit the optional async field). The host
profile is directional and private-stage attribution is insufficient; no
optimization was justified. Local ingress and disposable signing checks passed, while
public ingress, provider durability/retention, HA/DR, provenance, signed
off-box audit export, true power loss, iOS diagnostics/performance, and
independent-app evidence remain open.

**Implication:** P1D-10 is closed only for the declared Android+iOS
three-slot conformance scope; it is not a general arbitrary-patch claim.
P1D-09 remains an `INSUFFICIENT ATTRIBUTION` production gate, and
beta/production/store-policy decisions remain blocked despite bounded P2
technical completion.

**Next action:** Stop at Task 47 maintainer review with recommendation
`CONTINUE P2 FOR EXTERNAL EVIDENCE`; do not begin P3 or claim store approval.

## 2026-08-23 — Task 48 repository-controlled production-readiness closure

**Question:** Which remaining P2 production-readiness gates can the repository
and disposable local environment close without changing the runtime trust
model or claiming provider/external evidence?

**Investigation:** Added an opt-in, disabled-by-default interpreter profile
sink and ran five-sample attribution workloads; implemented and tested a
separate Ed25519 audit-export envelope with offline verification; defined the
application ingress trust policy and spoof tests; rehearsed two stateless
control-plane instances with shared disposable dependencies; executed a
canonical backup/destroy/recreate/restore/reconcile DR run; generated a local
SPDX inventory and bounded image provenance manifest; published configuration,
secret, incident, and operator runbooks; and isolated the CLI keygen/sign
timeout with direct timings.

**Evidence:** `docs/research/p2-interpreter-attribution-2026-08-23.md`,
`p2-audit-export-signing-2026-08-23.md`, `p2-ingress-trust-boundary-2026-08-23.md`,
`p2-application-ha-dr-2026-08-23.md`, `p2-sbom-provenance-2026-08-23.md`,
`p2-cli-signing-timeout-2026-08-23.md`, and the Task 48 task record.

**Finding:** Repository-controlled readiness is complete only to the bounded
local/self-hosted boundary. Attribution remains **`ATTRIBUTION STILL
INSUFFICIENT`** because device/AOT/Flutter-frame/heap/healthy-source-map costs
remain unmeasured. The signed audit export, local ingress, disposable
application HA, directional DR, local SBOM/provenance, and operations contracts
have executed evidence. The CLI is **`SLOW BUT CORRECT`**; its previous
30-second result was a harness-window timeout, not a CLI failure.

**Implication:** The concurrent HA rehearsal exposed a real concurrent
PostgreSQL migration race, which was fixed with a transaction-scoped advisory
lock and covered by the rehearsal. Local Compose evidence does not close
managed database/object failover, public ingress, provider durability,
approved RPO/RTO, independent-app beta validation, true power loss, iOS DDI or
performance, image attestation, or Apple/Google/legal review.

Self-review also found that an audit envelope must reject unknown fields and
must bind its sequence/count metadata and recomputed chain verification. Those
checks were added before the final control-plane validation; the focused audit
tests and full control-plane suite then passed.

**Next action:** Maintainer review of the Task 48 bounded closure. Keep beta
and external/provider production blocked; do not start P3.

## 2026-08-23 — Task 49 P2 exit and P3 design gate

**Question:** Can the repository-controlled P2 implementation be formally
closed while preserving all external/provider gates, and can a future rollout
and observation phase be designed without weakening runtime trust?

**Investigation:** Reconciled the completed Task 41–48 records and status
markers, froze the package/toolchain/control-plane/schema/deployment baseline,
indexed the evidence with relative paths and SHA-256 digests, and wrote a
separate P2 exit review. Designed immutable rollout revisions, deterministic
app-install cohorts, percentage semantics, pause/halt and rollback
distinctions, privacy-minimized health events, operator/audit boundaries,
tenant isolation, outage behavior, threat mitigations, and future sequencing.
No runtime, control-plane, mobile, or provider implementation changed.

**Evidence:** `docs/P2_EXIT_REVIEW.md`,
`docs/research/evidence/p2-exit-manifest.json`,
`docs/P3_ROLLOUT_OBSERVABILITY_DESIGN.md`, and `tasks/49-p2-exit-p3-design.md`.

**Finding:** P2 engineering is **`CLOSED — BOUNDED`** and the exact exit
statement is **`P2 ENGINEERING CLOSED — EXTERNAL GATES CARRIED FORWARD`**.
Beta remains blocked, repository-controlled production evidence is passed only
within its bounded scope, provider production remains blocked, and store/legal
status requires external review. P3 is design-only and cannot change Patch
Format v1, capability v1, high-water, signing, rollback, or runtime authority.

**Implication:** The project can stop extending P2 for unavailable external
evidence, but no beta, production, or store approval follows from this exit.
P3A implementation requires explicit maintainer approval of the state machine,
cohort algorithm, event/privacy model, retention, and OSS/commercial boundary.

**Next action:** Maintainer chooses one of `HOLD P3 — EXTERNAL GATES FIRST`,
`AUTHORIZE P3 DESIGN ONLY — COMPLETE`, `AUTHORIZE P3 IMPLEMENTATION WITH
CONDITIONS`, `RETURN TO P2`, or `STOP PROJECT`. Do not implement P3 before that
decision.

## 2026-08-23 — Task 50 P3A rollout domain and eligibility

**Question:** Can the first rollout slice add immutable delivery policy,
deterministic cohorts, and tenant-scoped operator controls without changing
Patch Format v1, runtime verification, high-water, signing, or rollback?

**Investigation:** Added a pure-Dart rollout domain with strict target/policy/
revision decoding, an explicit lifecycle state machine, immutable revision
history, deterministic percentage and internal cohort evaluation, and a
filesystem-backed service integration. Added least-privilege rollout control
scopes, tenant/application/environment/release/patch/artifact checks, audit
events, stale-revision/idempotency handling, and rollout-aware update lookup.
The evaluator uses `BigInt` for the unsigned 64-bit bucket because Dart's
platform `int` bit operations are signed at that width. Draft/ready rollouts
withhold offers; active cohorts alone can receive a candidate; pause/halt
withhold future offers without changing runtime trust state.

**Evidence:** `packages/control_plane/lib/src/rollout.dart`, the rollout
methods in `packages/control_plane/lib/src/service.dart`,
`packages/control_plane/test/rollout_test.dart`,
`packages/control_plane/test/rollout_service_test.dart`, and the Task 50
validation record.

**Finding:** The P3A delivery-policy boundary is implementable in the existing
control plane without a runtime or Patch Format change. Immutable revisions,
optimistic concurrency, deterministic cohort monotonicity, internal-to-canary
promotion, tenant isolation, malformed-record fail-closed behavior, audit
coverage, and update eligibility all pass the focused and full package tests.
This is control-plane evidence only; it is not health ingestion, automatic
halt, dashboard, provider production, mobile, store, or legal evidence.

The generic store contract has no cross-process compare-and-swap primitive, so
the concurrency evidence is limited to expected-revision checks serialized by
one service instance. Distributed rollout-write locking remains unverified.

**Implication:** Rollout policy can advise artifact delivery while the runtime
remains authoritative for signature, exact-release, capability, compatibility,
high-water, activation, and rollback checks. The P3A boundary is ready for
maintainer review, but later P3 slices remain prohibited until separately
authorized.

**Next action:** Stop at the P3A maintainer-review gate. Keep P1D/provider/
store/legal readiness gates open and do not begin health-event ingestion,
automated halt, dashboard, or other P3 work.

## 2026-08-23 — Task 51 physical iOS diagnostics and performance rerun

**Question:** Can the previously environment-gated iOS diagnostic and
performance evidence be rerun now that the unlocked USB iPhone is available?

**Investigation:** Audited the physical iPhone XR and AUVANA VENTURES PRIVATE
LIMITED signing context; built and installed stock and automatically
instrumented Release variants through XcodeBuildMCP; ran the existing one-
install iOS lifecycle with signed patch activation, restart persistence,
invalid-signature rejection, rollback, stale/replay rejection, and rollback
persistence; captured `idevicesyslog`, Xcode App Launch, and Time Profiler
traces; attempted Allocations; preserved raw receipts, traces, hashes, and
machine-readable reductions.

**Evidence:** Device iOS 18.7.9 (`22H355`), arm64e iPhone XR; CoreDevice ID
`CC5119BA-1DBD-54D2-AD8C-1F15FC5E5B6F`; USB UDID
`00008020-001528860E03002E`; team `CYT7A4VAZ3`; bundle
`dev.hyfens.conformance`. `idevicesyslog` recorded a mounted personalized
Developer Disk Image and Runner/Flutter process lines. The complete evidence
record is `docs/research/ios-gate-rerun-2026-08-23.md`.

**Finding:** P1D-03 is closed for the declared device/toolchain scope. P1D-04
has bounded physical startup/CPU-profile evidence for stock,
instrumented-unpatched, and active-patch variants, plus binary-size results,
but remains partial for resource and throughput claims because Allocations did
not produce usable numeric RSS/heap data and no thermal/battery/soak or hot
dispatch campaign was run.

**Implication:** The old “iOS unavailable/NOT RUN” condition is no longer
accurate for this device/run, but the evidence must not be generalized to all
iOS devices, production builds, store approval, or universal performance.
P1D-01, P1D-07, P1D-09, provider, beta, and store/legal gates remain open.

**Next action:** Stop at the Task 51 maintainer-review gate. If broader iOS
performance claims are required, authorize a separate multi-sample resource,
thermal/battery, soak, and controlled dispatch-throughput campaign; do not
silently relabel the bounded run.

## 2026-08-24 — Task 70 P3E5-5B bounded reconciliation

**Question:** Can findings and typed repair attempts be persisted and
processed in bounded File/PostgreSQL invocations without adding a worker,
second rollout writer, or immutable-evidence repair path?

**Investigation:** Added canonical append-only finding/repair persistence,
versioned lifecycle/cursor CAS, hashed tenant-separated File storage with a
single-writer guard, PostgreSQL migration 008, bounded startup/manual service
execution, composite detector composition, audit-before-repair, precondition
reload, postcondition verification, report-only handling, and deterministic
replay. Ran focused File and PostgreSQL tests plus the full control-plane
suite against the existing local PostgreSQL fixture.

**Evidence:** `packages/control_plane/lib/src/reconciliation_persistence.dart`,
`packages/control_plane/test/reconciliation_persistence_test.dart`, migration
008, `docs/P3E5_5B_BOUNDED_RECONCILIATION_REVIEW.md`, and the Task 70 review
addenda. Focused reconciliation tests passed (13 with one explicit PostgreSQL
skip without configuration; 14 with PostgreSQL enabled), the audit-chain
tamper case passed, PostgreSQL two-instance replay/reconnect passed, and the
full control-plane suite passed (222 tests, one explicit MinIO/S3 environment
skip).

**Finding:** The bounded persistence/orchestration core is viable and keeps
P3A/P3E-4/runtime/mobile authority unchanged. The generic detector and typed
executor seams are safe boundaries, but concrete schedule/P3E source readers
and real existing projection-CAS adapters were not inferred or claimed.

**Implication:** Continue P3E5-5B only to wire and race-test those concrete
integrations. Do not authorize P3E5-5C metrics/readiness/diagnostics, a worker,
queue, dashboard, provider deployment, or production/store/legal claims from
this evidence.

**Next action:** Maintainer review of the P3E5-5B boundary; keep the concrete
detector/CAS integration work explicitly pending.

## 2026-08-25 — Provider selection decision closure

**Question:** Which managed-container profile can host the existing
provider-neutral control plane without changing runtime, patch, rollout,
reconciliation, audit, or signing authority?

**Investigation:** Compared current official AWS, Google Cloud, and Microsoft
Azure documentation for stateless replicas, active readiness, graceful
replacement, managed PostgreSQL failover/PITR, object versioning/recovery,
private networking, workload identity, secret injection, image digest and
supply-chain controls, India-region availability, and public pricing inputs.
Defined editable DEV, EARLY BETA, and SMALL PRODUCTION HYPOTHESIS quantities,
sensitivity checks, a weighted rubric, provider acceptance tests, RPO/RTO
targets, capacity/pool hypotheses, endpoint exposure, and a runner model.

**Evidence:** [provider selection decision review](history/reviews/PROVIDER_SELECTION_DECISION_REVIEW.md),
[proposed provider ADR](adr/0014-provider-selection.md),
`Task 77`, and the linked
official provider sources in the review.

**Finding:** AWS ECS/Fargate + ALB + RDS PostgreSQL Multi-AZ + S3 is the
strongest first disposable profile under the predeclared rubric, with Mumbai
(`ap-south-1`) as the initial geography hypothesis. AWS ALB's documented
all-targets-unhealthy fail-open behavior is a material condition. GCP remains
a viable alternative but has Preview/best-effort readiness conditions. Azure
remains viable but Central India PostgreSQL zone-redundant HA is currently
blocked for new deployments; South India requires separate validation.

**Implication:** Provider implementation can be proposed but not claimed as
approved, production-ready, beta-ready, or store/legal compliant. Real
provider failover, advisory-lock/session, pool, edge, object, supply-chain,
backup/PITR, cost, and soak tests remain mandatory.

**Next action:** Stop at maintainer review. If approved, execute only the
smallest disposable AWS profile and acceptance matrix, then review evidence
again before any beta or production work.

## 2026-08-25 — Task 79 AWS acceptance preflight closure

**Question:** Which AWS acceptance gates can be closed without an AWS account,
and does the disposable image/control-plane path remain safe to hand to a
separately authorized provider run?

**Investigation:** Preserved the historical SDK-image scan, built a pinned
AOT/distroless ARM64 candidate, generated a fresh SPDX SBOM and Trivy report,
triaged every historical CRITICAL/HIGH package finding, exercised disposable
local OCI signing/provenance and wrong-input rejection, and added a
provider-neutral fail-closed verifier. Reproduced the two crash-worker cases
serially, repeated each three times, ran the isolated full control-plane
suite, inspected the periodic-runner composition, hardened the ECS health
check for the SDK-free runtime, reviewed OpenTofu retention/teardown safety,
and added operator, IAM, cost, and AWS evidence contracts.

**Evidence:** Task 79 local evidence is under
`docs/research/evidence/task79-preflight/`; the candidate digest is
`sha256:68ae7017f9e7b93ff9d81d3944e161d25f89de171dabaac2660a77e4df48cb4b`.
The fresh scan is 0 CRITICAL/1 HIGH/7 MEDIUM/7 LOW/2 UNKNOWN. The full
control-plane suite exited zero with 240 passed and 34 explicit skips using
serial test-suite execution. The crash-worker diagnosis additionally found
and fixed a marker-vs-exit race in the test helper (marker-first observation
plus killed-child stdio draining); no production runtime semantics changed.
The preflight command is
`scripts/aws-disposable-preflight.sh`; it never applies or destroys AWS
resources.

**Finding:** Local supply-chain and runtime preflight is viable. The one HIGH
is explicitly triaged `NOT_REACHABLE_WITH_EVIDENCE` for the current TCP-only
service. The earlier crash failures were a test-harness marker/exit race
exposed by process contention, not a reproduced product defect. The periodic runner
cannot be enabled safely because the serving binary does not compose exact
scope and lease-token authority. Unconstrained full-suite attempts also
exposed an existing Task 67 timing assertion flake under process contention;
the benchmark passed in isolation and the serial full suite passed. No
production threshold or runtime behavior was changed.

**Implication:** Local acceptance preflight can be marked PASS only for the
declared candidate and test environment. AWS account identity, ECR admission,
provider failover/recovery, cost, teardown, beta, production, and store/legal
claims remain open.

**Next action:** Stop at Task 79 maintainer review. If separately authorized,
run the bounded disposable AWS acceptance matrix with the operator-input and
cost contracts; do not treat this local evidence as provider readiness.

## 2026-08-25 — Task 80 disposable AWS acceptance precondition audit

**Question:** Can the authorized disposable AWS acceptance matrix begin safely
in the current workspace?

**Investigation:** Read the Task 80 authorization, inspected the Task 79
operator-input and cost contracts, audited AWS CLI/OpenTofu availability and
credential-environment names without printing secret values, and checked for
an approved account, principal, CIDR, ECR/OCI identity, evidence destination,
and current Mumbai price approval.

**Evidence:** The AWS CLI and host OpenTofu were unavailable; no AWS-related
credential or region environment names were present; the operator contract
remains `CONTRACT ONLY — values intentionally unfilled`; and the cost
worksheet remains `TEMPLATE — current regional prices not entered`. No STS,
ECR, OpenTofu, AWS resource, DNS, or teardown action was attempted.

**Finding:** Task 80 is blocked before provider action. Task 79 local evidence
must remain local evidence and cannot substitute for explicit AWS approval or
provider identity.

**Implication:** Do not infer account, principal, spend, or network scope from
ambient configuration. Resume only after the maintainer supplies the complete
operator/account/cost approval record and a matching AWS CLI session.

**Next action:** Re-run the Task 80 identity gate, current Mumbai pricing
approval, and Task 79 local preflight, then continue the disposable matrix only
if every hard precondition passes.

## 2026-08-25 — Task 81 AWS operator approval and session bootstrap

**Question:** Can the external account, operator, cost, and session gates for
Task 80 be closed without guessing or mutating AWS?

**Investigation:** Read the Task 81 bootstrap instruction and Task 80 blocked
review, audited AWS CLI/OpenTofu availability and safe credential-environment
names, and created unpopulated maintainer approval, current-pricing/cost
approval, and session-audit artifacts.

**Evidence:** No AWS CLI or host OpenTofu executable was present; no AWS
credential/region environment names were present; no account ID, principal,
CIDR, ECR boundary, OCI identity, evidence destination, DNS decision, or
current Mumbai price approval was supplied. No STS, ECR, OpenTofu, AWS
resource, DNS, or teardown operation was attempted.

**Finding:** Task 81 remains blocked by explicit maintainer approval and the
missing AWS CLI/session. The approval templates are intentionally unfilled;
Task 80 cannot resume from conditional authorization alone.

**Implication:** Credentials must be supplied through an approved short-lived
session and compared exactly to the maintainer record. No credential value may
enter repository evidence, state, logs, or scripts.

**Next action:** Obtain the completed approval/cost records and configure AWS
CLI v2, then perform only the safe STS/region exact-match gate before resuming
Task 80.

## 2026-08-25 — Task 82 AWS approval exact-match gate

**Question:** Can the maintainer approval, current Mumbai cost approval, and
AWS identity exact-match gates be closed without provider mutation?

**Investigation:** Read the Task 82 authorization and supplied approval/review,
audited the repository task/evidence state, checked AWS CLI/OpenTofu
availability and safe environment-variable names, rechecked the static
candidate digest and periodic-runner guard, and recorded a resume-readiness
manifest.

**Evidence:** The supplied maintainer approval remains explicitly
`UNFILLED — NOT APPROVED`; `command -v aws` and `command -v tofu` found no host
executables; no AWS-related environment-variable names were present; and no
STS, ECR, OpenTofu, provider, quota, DNS, or teardown operation was attempted.
The candidate digest matches the historical Task 79 configuration statically,
and the periodic runner remains disabled by default.

**Finding:** The exact-match gate is blocked. Account/principal/CIDR/ECR/OCI/
evidence/DNS approval, current Mumbai pricing, cost approval, and a matching
short-lived AWS CLI session are absent. No value may be inferred from prior
conditional authorization or ambient configuration.

**Implication:** Task 80 remains paused. Task 82 records no AWS acceptance,
beta, production, store, privacy, or legal-compliance claim.

**Next action:** The maintainer must complete and approve the two approval
records and configure an approved short-lived AWS CLI v2 session. Then rerun
only the exact STS/region checks and resume Task 80 only if every hard gate
passes.
