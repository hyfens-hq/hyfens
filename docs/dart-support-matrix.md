# Dart and Flutter patch support matrix

Status values are evidence labels, not roadmap promises:

- `SUPPORTED`: compiler, runtime, invalid-input, integration, and required device evidence passed for the stated boundary.
- `PARTIAL`: some named cases passed; listed gaps remain.
- `UNSUPPORTED`: deliberately rejected with a diagnostic or excluded by design.
- `NOT TESTED`: no experiment supports a claim.
- `BLOCKED`: a recorded technical prerequisite or architecture blocker prevents progress.

The matrix is cumulative. A row advances only from executed evidence; inference
never changes `NOT TESTED` to `SUPPORTED`.

## Values and signatures

| Feature | Status | Verified boundary | Missing evidence |
| --- | --- | --- | --- |
| `int` | PARTIAL | Task 08: generalized required positional arguments/returns, tagged encoding, arithmetic/index use | Broader operations and physical generalized run |
| `null` / nullable types | PARTIAL | Task 08: explicit nullable `String? Function(String?)`, tagged null, rejection for non-nullable boundary | Nullable collections and physical run |
| `bool` | PARTIAL | Task 08: argument/return/constants, comparison and short-circuit AND | Broader operators and physical run |
| `double` | PARTIAL | Task 08: finite exact-tag argument/return/arithmetic; non-finite rejection | Numeric edge matrix and physical run |
| `String` | PARTIAL | Task 08: argument/return/constants, concatenation/interpolation and UTF-8 size bound | Broader methods and physical run |
| `List` | PARTIAL | Task 10: bounded literals, indexing, local assignment/add, insertion-order iteration, contains, alias preservation, and native-AOT returned transformation | Argument mutation is by value; broader APIs, closures, and physical run |
| `Map` | PARTIAL | Task 10: canonical String-keyed wire values plus lookup, local assignment, key contains, insertion-order `keys` iteration, and host isolation | Argument mutation is by value; entries/values/general iteration and physical run |
| `Set` | PARTIAL | Task 10: typed canonical wire value, literals, add, contains, length, insertion-order iteration, malformed/duplicate/size rejection | Removal, broader APIs, nested host signatures, and physical run |
| Positional top-level functions | PARTIAL | Task 08: five required typed synchronous signatures and nullable String path; typed Map patch passed native AOT | Physical generalized Android/iOS and more types |
| Named/optional parameters | UNSUPPORTED | Phase 0 compiler rejects them | Semantics and compatibility model |
| Generics | UNSUPPORTED | Phase 0 transformer/compiler excludes them | Type substitution/runtime representation |

## Language semantics

| Feature | Status | Verified boundary | Missing evidence |
| --- | --- | --- | --- |
| `if` without `else` | PARTIAL | Task 08 preserved Phase 0 branching across generalized verifier | General typed conditions and nesting |
| `if` / `else`, nested conditions | PARTIAL | Task 10: typed nested diamonds with verified stack/local joins | Broader expressions and physical run |
| `switch` | PARTIAL | Task 10: matching non-null scalar literal cases/default with explicit break/return; fallthrough rejected | Patterns, guards, grouped labels, broader control transfer |
| `for` / `while` | PARTIAL | Task 10: declaration-based C-style `for`, `while`, typed collection `for-in`, global instruction budget | General Iterable, expression initializer, labels/continue, physical run |
| Early return | PARTIAL | Task 10: nested control flow, loop/switch returns, verifier-enforced typed returns | Broader constructs and physical run |
| Locals and assignment | PARTIAL | Task 10: explicit typed lexical slots, definite initialization, mutation/final checks, collection index assignment | Inference, late/pattern locals, parameter reassignment |
| Instance methods / `this` | PARTIAL | Task 09: transparent same-unit method entry with no raw `this`; direct/virtual/tear-off native AOT | Unqualified member resolution, multi-file hierarchy, broader methods |
| Fields/getters/setters | PARTIAL | Task 09: explicit `this.field`, private field, and pure getter through typed read slots | Writes rejected; unqualified access and side-effecting/throwing getters unsupported |
| Private/inherited members | PARTIAL | Task 09: same-library private field; base declaration on subclass; distinct override ID/result | Cross-library private, `super` call case, parts/mixins/extensions |
| `throw` / `try` / `catch` / `finally` | PARTIAL | Tasks 11–12: bounded non-null throw, one catch-all, nested finally/return/throw completion, rethrow trace, AOT crossing, receiver/collection/async capability failure translation, and handler preservation across await | Typed/multiple catches, binding reads, full Dart stacks, general host calls, physical run |
| `Future` / `async` / `await` | PARTIAL | Task 12: ordinary top-level and instance `Future<int>` guards, typed immediate/delayed/multiple capability awaits, zones, deadlines, saved handlers, generation pinning, and native AOT | Arbitrary Future calls/objects, class `Result`, concurrency, cancellation, Flutter/device runs, broader async bodies |
| Streams/generators | UNSUPPORTED | Phase 0 excludes generator bodies | No Phase 0B proof planned before async gate |
| Closures and captures | UNSUPPORTED | Task 12: immutable/mutable capture, nested functions, and closure collection APIs fail explicitly; classification `NOT YET SUPPORTED` | A bounded closure environment/call model and representative framework demand |
| Records, enums, mixins, extensions | NOT TESTED | None | Compiler/runtime/identity behavior |
| Isolates | NOT TESTED | None | Runtime and patch-state boundary |
| Platform channels / FFI | UNSUPPORTED | Task 14 rejects raw channels, plugin dispatch, reflection, and FFI; host objects never cross the guest boundary | A reviewed compiled adapter may use native APIs internally, but no real adapter is device-tested |

## Flutter and ecosystem

| Feature | Status | Verified boundary | Missing evidence |
| --- | --- | --- | --- |
| Host StatefulWidget state | PARTIAL | Task 17 plus current Android/iOS physical receipt runs: transformed guard + signed E1 preserved the bounded mounted state path through activation/rejection/rollback and restart | State layout migration, arbitrary stateful methods, broader stateful widget release coverage |
| Ordinary `Widget.build` patch | PARTIAL | Task 16 plus current Android/iOS device runs: build-tool-selected ordinary `StatelessWidget.build`, no annotation/PatchView, real Flutter text/hierarchy/style patch through the shipped factory ABI, signed stock Release/AOT on both devices | Stateful builds, callbacks, keys, context/theme/localization, general properties/constructors, broader screens |
| Text/hierarchy/style changes | PARTIAL | Task 16: Text, conditional added child, Column composition, font size, disabled ElevatedButton through exact program-scoped factories | Callbacks, keys, context/theme/localization, general properties/constructors, broader screens |
| Riverpod | PARTIAL | Task 18 plus current Android/iOS broad physical receipts: signed transformed pricing logic drove existing Provider/AsyncNotifier and mounted ConsumerWidget after the declared generation trigger; invalid rejection and rollback preserved identities/state | Activation alone does not invalidate cached values; cancellation/overlap/retry, families/generators, patched ConsumerWidget build, and broader physical coverage |
| BLoC/Cubit | PARTIAL | Task 20: actual signed transformed business function drove an existing synchronous Cubit; pre-existing stream subscription, provider lookup, mounted BlocBuilder, state, and exact emissions/build counts survived rejection and rollback | Event Bloc, transformers/concurrency, BlocListener, async/errors, persistence/replay, Cubit-method patching, and physical release run |
| GoRouter | PARTIAL | Task 19: actual signed transformed A/B redirect among installed routes on ordinary navigation; existing router listener and mounted route/host state survived malformed rejection and rollback | Activation/rollback do not refresh; builder replacement, patch-driven navigation capability, new routes/deep links, and physical release run unproved |
| Pure-Dart dependency | PARTIAL | Task 21: package-preserving explicit units and global slots; local path package direct/tear-off passed native AOT; hosted collection 1.19.1 direct/tear-off passed JIT with unchanged cache source | Transitive export/import graph, parts, broader generated suffixes, hosted-package AOT, whole-package selection, filesystem race hardening, and physical release run |
| Native plugin update | UNSUPPORTED | Native code/capabilities absent from release cannot be added by data patch | Existing compiled adapter use only |

## Platform validation

| Platform | Status | Verified boundary | Missing evidence |
| --- | --- | --- | --- |
| Android arm64 physical release | PARTIAL | Tasks 23 current-source Wi-Fi runs: one Release APK install; signed business, capability-mediated async, widget, Riverpod, invalid-signature retention, rollback, two restart groups, persistence, and unchanged package timestamps passed | Broader Dart/Flutter coverage, device performance, and production transport remain unexecuted |
| iOS arm64 release/profile | PARTIAL | Tasks 24–25 current-source AUVANA-signed USB runs: arm64 Release/AOT install with no kernel/dill, business/async/UI/Riverpod, invalid signature, rollback, two restarts, and persistence passed | Broader iOS semantics, production transport, App Store review, and device performance remain unexecuted |

## Identity and compatibility

| Feature | Status | Verified boundary | Missing evidence |
| --- | --- | --- | --- |
| Named declaration identity | PARTIAL | Task 13: structured canonical package URI + owner/member identity; stable across whitespace/order/checkout roots; collision and forgery rejection | Parts, mixins/extensions/constructors/accessors, whole-package semantic resolution |
| Signature compatibility | PARTIAL | Task 13: signature changes retain declaration ID and fail exact activation; complete expected signature/receiver tables required | Named/optional/generic/record/alias signatures remain unsupported |
| Release/build binding | PARTIAL | Task 13: exact app release and caller-provided deterministic build fingerprint bound in manifest and patch | Production derivation from normalized toolchain/target/dependencies/build defines |
| Payload authenticity and sequence | PARTIAL | Task 15 plus current Android/iOS physical receipts: strict canonical domain-separated E1 bytes, pure-Dart Ed25519, release-owned trusted keys, verify-before-decode, tamper rejection, durable high-water, stale/equivocation/replay rejection | Protected monotonic anchor, broader malformed-vector corpus, production key custody |
| Host capability authority | PARTIAL | Task 14: frozen shipped authority, canonical typed sync/async contracts, exact activation, bounded/redacted failures, five deterministic fake policy adapters | Real services/platform permissions, concurrency quotas, cooperative/abortable cancellation, device evidence |
| Last-known-good and rollback | PARTIAL | Task 15 plus current Android/iOS receipts: explicit pending/`markHealthy`, restart persistence, invalid-signature retention, rollback to base, and dual checksummed state copies | Process-kill/device fault injection, crash-health policy, more than locally retained ancestry, backup/restore rollback resistance |

## History

- 2026-08-22: Initialized from Phase 0 evidence before Task 08 implementation.
- 2026-08-22: Updated from Task 08's 40-test and native-AOT typed-value evidence; device-dependent rows remain partial.
- 2026-08-22: Added Task 09's 57-test/native-AOT bounded receiver evidence; object/member rows remain partial by design.
- 2026-08-22: Added Task 10's 72-test/native-AOT structured-flow and bounded collection evidence; closures and caller-visible collection mutation remain unsupported/unproved.
- 2026-08-22: Added Task 11's 94-test/native-AOT bounded exception evidence; general Dart exception objects, typed catches, and full stack traces remain unsupported.
- 2026-08-22: Added Task 12's 122-test/native-AOT typed continuation evidence; async is partial and capability-mediated, while closures remain explicitly unsupported.
- 2026-08-22: Added Task 13's 139-test structured identity and strict compatibility evidence; part resolution, authenticity, and durable sequence state remain open.
- 2026-08-22: Added Task 14's 158-test frozen capability-authority evidence; real adapters and broader cancellation/quota enforcement remain unproved.
- 2026-08-22: Added Task 15's 25-test asymmetric signing and durable pending/LKG/high-water evidence; release-mode device verification and protected rollback resistance remain unproved.
- 2026-08-22: Added Task 16's 170-test bounded ordinary StatelessWidget build evidence and transformed real-Flutter overlay; signed lifecycle/device and arbitrary Flutter remain unproved.
- 2026-08-22: Added Task 17's signed transformed-overlay mounted-state evidence; state layout migration, process restart, and physical release behavior remain unproved.
- 2026-08-22: Added Task 18's Riverpod Provider/Notifier/AsyncNotifier and ConsumerWidget evidence; activation-triggered cache invalidation and broader async/provider patterns remain unproved.
- 2026-08-22: Added Task 19's signed transformed GoRouter A/B decision evidence; automatic refresh, builder replacement, patch-driven navigation capability, and native deep-link changes remain unproved or excluded.
- 2026-08-22: Added Task 20's synchronous Cubit/BlocBuilder lifecycle evidence; event Bloc, async/concurrency, persistence, and direct Cubit-method patching remain unproved.
- 2026-08-22: Added Task 21's package-preserving explicit-unit local native-AOT and hosted JIT evidence; this is not yet a transitive dependency build system.
- 2026-08-22: Added Task 22's corrected host-AOT dispatch, activation, size, RSS, and selective-instrumentation evidence; no device performance claim was inferred.
- 2026-08-22: Task 23's expanded physical Android sequence remains blocked because no Android device is connected; Phase 0's earlier narrow device result is preserved separately.
- 2026-08-22: Task 24 advanced iOS only to a transformed unsigned Release/AOT arm64 compile. Signing and every physical runtime scenario remain blocked by unavailable matching provisioning.
- 2026-08-22: Current-source Android narrow and broad physical runs passed on the Wi-Fi device; async/UI/Riverpod/restart/rollback evidence is now recorded.
- 2026-08-22: AUVANA-signed current-source iOS narrow and broad USB runs passed on the physical iPhone; no kernel/dill payload was present in the arm64 Release artifact.

## Phase 1A delta

The historical rows above preserve the Phase 0/0B evidence record. The scoped
Phase 1A implementation adds the following tested boundaries without claiming
general Dart support:

| Feature | Phase 1A status | Verified boundary | Explicit gap |
| --- | --- | --- | --- |
| Named and optional parameters | `SUPPORTED` for the representative subset | Required named, optional named, optional positional, default literals, deterministic declaration-order binding, and exact signature metadata | Generic/function-typed parameters and arbitrary default expressions |
| Closures and captures | `PARTIAL` | Synchronous required-positional closures with bounded scalar/collection captures; direct invocation plus `map`, `where`, `fold`, and `sort` callbacks | Async closure suspension, nested closures, host capability calls from closures, and unrestricted capture |
| Future interoperability | `PARTIAL` | Existing typed async capabilities plus non-blocking `await Future.value(value)` | `Future.wait`, `then`, `catchError`, `timeout`, cancellation, and arbitrary Future objects |
| Stable patch protocol | `SUPPORTED` for Patch Format v1 | Canonical deterministic sections, bounded decoding, digest/signature domains, critical-field rejection, and baseline manifest round-trip | Public compatibility freeze and production key custody remain after Phase 1A review |

Phase 1A deliberately leaves the earlier async-closure exclusions intact: an
unsupported construct is rejected rather than silently lowered.

## Independent real-application acceptance — CLI/runtime 0.1.3

The historical fixture/device evidence above is not independent-application
acceptance. The receipt/resource-boundary changes do not themselves establish
physical acceptance in this campaign. No row below is promoted by a unit test,
host build, native typecheck, or simulated receipt.

`PHYSICALLY_PROVEN` requires an actual no-reinstall run on the
stated platform. `NEW_BASE_RELEASE_REQUIRED` is an intentional packaging
boundary, not an OTA capability. `NOT_YET_PROVEN` means this campaign has
not established support; it does not erase the narrower historical evidence.

| Change type | Android | iOS | Result |
| --- | --- | --- | --- |
| Dart text | Not run | Not run | NOT_YET_PROVEN |
| Widget tree | Not run | Not run | NOT_YET_PROVEN |
| Theme/style | Not run | Not run | NOT_YET_PROVEN |
| State | Not run | Not run | NOT_YET_PROVEN |
| Business logic | Not run | Not run | NOT_YET_PROVEN |
| Async | Not run | Not run | NOT_YET_PROVEN |
| Routing | Not run | Not run | NOT_YET_PROVEN |
| Animation | Not run | Not run | NOT_YET_PROVEN |
| Localization/generated Dart | Not run | Not run | NOT_YET_PROVEN |
| Pure-Dart dependency | Not run | Not run | NOT_YET_PROVEN |
| Existing bundled asset reference | Not run | Not run | NOT_YET_PROVEN |
| Changed asset | Excluded by format | Excluded by format | NEW_BASE_RELEASE_REQUIRED |
| New asset | Excluded by format | Excluded by format | NEW_BASE_RELEASE_REQUIRED |
| Removed asset | Excluded by format | Excluded by format | NEW_BASE_RELEASE_REQUIRED |
| Existing font style | Not run | Not run | NOT_YET_PROVEN |
| Changed font | Excluded by format | Excluded by format | NEW_BASE_RELEASE_REQUIRED |
| New font | Excluded by format | Excluded by format | NEW_BASE_RELEASE_REQUIRED |
| New icon/tree-shaken font glyph | No base-glyph proof | No base-glyph proof | NEW_BASE_RELEASE_REQUIRED |
| Local persistence logic | Not run | Not run | NOT_YET_PROVEN |
| Native plugin | Native binary boundary | Native binary boundary | NEW_BASE_RELEASE_REQUIRED |
| Native configuration | Native binary boundary | Native binary boundary | NEW_BASE_RELEASE_REQUIRED |
| Flutter engine change | Engine identity boundary | Engine identity boundary | NEW_BASE_RELEASE_REQUIRED |

Patch Format v1 has no signed resource payload or atomic code/resource rollback.
CLI 0.1.3 snapshots declared asset/font bytes and native build inputs;
changed, added, removed, unsafe or unreadable inputs fail closed. A new Material
icon reference is conservatively rejected without exact base-glyph evidence.
Unchanged bundled resources remain part of the native base and are not removed
by code rollback. Resource OTA download, activation and garbage collection are
not implemented or advertised. Older release records without the resource and
engine baseline require a new base; missing evidence is never treated as an
empty asset set.

Receipt-bearing activation requires a signed Patch Format v1 patch identity.
Legacy E1 envelopes remain receipt-less. Production attestation requires an
explicit host evidence producer and server verifier; the default self-host
runtime does not enroll in Cloud metering. An unsupported native attestation
provider never silently grants production trust.
