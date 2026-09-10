# Phase 0B review

Date: 2026-08-22

Decision boundary: Tasks 08–26

**Device-validation closure:** the previously blocked physical runs were
completed on the current source on 2026-08-22. The Android device was connected
over Wi-Fi and the iPhone was connected over USB and signed with the AUVANA
VENTURES PRIVATE LIMITED team (`CYT7A4VAZ3`). The evidence below supersedes the
earlier pre-provisioning narrative; historical blockers remain in task histories
for auditability.

Recommendation: **PROCEED TO PHASE 1 WITH CONDITIONS**

Phase 0B status: **COMPLETED** for the approved research scope. The bounded
support matrix and the required current-source Android/iOS device gates are
closed; unresolved limitations and conditions below are intentional stopping
criteria, not untested claims.

This review stops Phase 0B. It authorizes no Phase 1 implementation, production
deployment, hosted control plane, or store-compliance claim.

## Physical-device closure

- Android narrow regression: `scripts/e1_android_physical.sh
  192.168.50.135:39083`, current-source run, one Release APK installation,
  pricing/state/invalid-signature/rollback/restart persistence, and unchanged
  package install timestamps passed.
- Android broad run: `scripts/e1_android_cross_feature.sh
  192.168.50.135:39083`, run `android-cross-20260822-6`, passed business,
  capability-mediated async/await, ordinary widget build, Riverpod refresh,
  invalid signature retention, rollback, and two restart groups without
  reinstall. Evidence is under
  `experiments/patch_loading/.dart_tool/android_e1_runs/android-cross-20260822-6/evidence/`.
- iOS narrow baseline: `scripts/e1_ios_physical.sh` with
  `E1_IOS_TRANSPORT=usb`, run `ios-usb-20260822-current`, passed AUVANA-signed
  arm64 Release installation, business patch, invalid signature rejection,
  rollback, two restarts, and persistence. Evidence is under
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_runs/ios-usb-20260822-current/evidence/`.
- iOS broad run: `scripts/e1_ios_cross_feature.sh`, run
  `ios-cross-20260822-1`, passed business, async/await, widget hierarchy,
  Riverpod, invalid signature rejection, rollback, two restarts, and
  persistence with one installation. Evidence is under
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_cross_runs/ios-cross-20260822-1/evidence/`.

These are local physical-device engineering results. USB staging was used for
iOS patch delivery so the test did not depend on a second network transport;
that does not establish production transport or App Store approval.

## 1. What works?

Experimentally verified within the documented boundaries:

- Stock Flutter/Dart builds can use an analyzer-guided ephemeral source overlay
  to add callee-entry dispatch while keeping developer-owned files unchanged and
  preserving the original AOT implementation.
- Explicit typed boundaries support null, bool, int, finite double, String,
  List, Map, and Set in the cases recorded by the
  [support matrix](../../dart-support-matrix.md). Five generalized function signatures,
  nullable values, deterministic encoding, and invalid return rejection passed.
- Selected ordinary instance methods, direct/virtual calls, existing tear-offs,
  inherited dispatch, and an explicit read-only receiver view passed. Raw `this`,
  reflection, arbitrary members, and unrestricted host objects are not exposed.
- Structured `if`/`else`, nested conditions, bounded `switch`, `for`, `while`,
  early return, selected collection operations, catch-all exceptions, `finally`,
  and non-blocking capability-mediated `Future`/`await` passed their focused
  compiler/runtime/integration cases.
- Stable named-declaration identity and exact compatibility metadata survived
  whitespace, declaration movement, and equivalent checkout roots. Renames and
  library moves change identity; signature changes are rejected.
- A frozen, typed, versioned capability registry supports bounded fake HTTP,
  storage, navigation, logging, and clock adapters. Raw platform channels, FFI,
  reflection, and plugin discovery are unavailable to patches.
- Strict Ed25519 E1 verification, release/build/function/capability/sequence
  binding, atomic activation, durable high-water state, pending/healthy/LKG
  recovery, and signed higher-sequence rollback passed focused host tests.
- An ordinary `StatelessWidget.build` was transformed without `PatchView` or an
  annotation and produced changed real Flutter text, conditional hierarchy,
  style, and composition through a finite shipped widget-factory ABI.
- Mounted Element/State, integer state, `TextEditingController`, selection,
  `ScrollController`, and scroll offset survived signed activation, invalid
  rejection, and rollback in Flutter tests.
- Bounded Riverpod, GoRouter, and Cubit/BlocBuilder flows retained their existing
  framework instances, subscriptions, and state while later ordinary actions
  observed patched or rolled-back business logic.
- Selected pure-Dart local dependency code passed native-AOT direct/tear-off
  patching; one hosted `collection` case passed a package-cache-preserving JIT
  experiment.

These results prove a useful research subset. They do not prove arbitrary Dart,
arbitrary Flutter screens, or production readiness.

## 2. What does not work?

- Named/optional parameters, generics, closures and captures, closure-based
  collection transforms, streams/generators, receiver writes, transparent
  caller-visible collection mutation, raw platform channels, and FFI are
  unsupported.
- Records, enums, mixins, extensions, isolates, broader getters/setters,
  constructors/initializers, and many declaration forms are untested.
- Async is limited to typed capability-mediated continuations. It is not general
  Dart `Future` interoperability, cancellation, concurrency, or stream support.
- Widget construction is a finite callback-free factory surface. Raw Flutter
  objects/context, arbitrary constructors/properties, callbacks, keys, themes,
  localization, route builders, and broad StatefulWidget build patching are not
  established.
- Patch activation itself does not invalidate Riverpod caches, reevaluate the
  current GoRouter route, or emit Cubit state. A later ordinary dependency,
  navigation, event, or explicit invalidation observes the changed behavior.
- The overlay is explicit-unit and syntax-led, not a transitive package/build
  graph. Parts, broad generated-code handling, hosted-package AOT, complete
  source maps/diagnostics, and representative multi-package fidelity are open.
- Class/state layout migration, new types removed by tree shaking, new native
  capabilities, plugins, permissions, manifests/plists, entitlements, and native
  libraries cannot be supplied by the current data patch.

## 3. Android

The current-source Android narrow and broad physical sequences passed. The
broad run installed one Release APK on the Wi-Fi device and recorded these
meaningful transitions without reinstall: base price 540; business patch price
450; async patch result 481; widget hierarchy patch observed on a rendered
frame; Riverpod recomputation price 450; invalid signature rejected while the
previous patch remained active; rollback and restart returned to base price 540.
The process groups and unchanged package timestamps are recorded in the run
evidence. Navigation remains covered by the separate GoRouter host/fixture
tests, not by an on-device route assertion in this run.

## 4. iOS

The current reviewed source was signed and installed on the physical USB iPhone
with team `CYT7A4VAZ3`. The Release artifact contained arm64 Runner and AOT App
binaries, no `kernel_blob.bin` or `.dill`, and entitlements bound to
`CYT7A4VAZ3.dev.hyfens.conformance`. The dedicated narrow run and the broad
cross-feature run both executed the signed data interpreter without reinstall.
The broad receipts recorded base 540, business 450, capability-mediated async
481, a rendered UI patch, Riverpod 450, tampered-signature rejection, rollback
to base 540, and persistence after two process restarts. The USB transport is a
laboratory delivery path; it is not a store-policy or production-network claim.
See [iOS feasibility](../../research/ios-feasibility.md).

## 5. Dart compatibility

The [Dart support matrix](../../dart-support-matrix.md) is authoritative. Its result is
predominantly `PARTIAL`, with explicit `UNSUPPORTED` and `NOT TESTED` rows. The
runtime supports a deliberately derived subset, not “Dart compatibility.”

The most important positive gate is that bounded non-blocking async fit the
current architecture without invasive toolchain work. The most important
language risk is closures: they are explicitly rejected and remain necessary
to evaluate because idiomatic Dart/Flutter and higher-order collection APIs use
them extensively.

## 6. Flutter compatibility

The ordinary StatelessWidget build experiment, mounted-state lifecycle,
Riverpod Provider/Notifier/AsyncNotifier plus ConsumerWidget, existing GoRouter
route decisions, and synchronous Cubit/BlocBuilder are credible bounded
interoperability evidence. None required modifying Flutter, Riverpod, GoRouter,
or BLoC.

The evidence does not extend to arbitrary Flutter UI. The factory ABI is finite,
callback-free, and shipped with the release; route destinations/builders remain
compiled; reactive frameworks need an ordinary trigger or a future carefully
scoped generation signal. The Android and iOS physical runs validate only the
declared bounded widget/Riverpod scenarios, not arbitrary Flutter screens.

## 7. Developer experience

For the tested declarations, developer source remains ordinary Dart/Flutter:
there is no `PatchView`, per-function annotation, or manual dispatch call. The
build tool selects source units, creates an ephemeral overlay, and inserts a
callee-entry guard, so existing calls and tear-offs can reach the patched branch.

The target workflow has **not yet been achieved as a production tool**:

```text
tool init
flutter build ...
tool patch
```

There is no finished init/release/patch CLI, automatic semantic diff, transitive
build graph, parts/generated-code solution, production configuration, or
complete source-map/diagnostic story. Patch experiments still use explicit
source units and patch inputs. A Phase 0 relative-import relocation failure and
Task 21's explicit-unit design are concrete evidence of overlay brittleness.

## 8. Runtime overhead

Task 22's corrected schema-v2 macOS arm64 host-AOT benchmark is authoritative:

| Case | Median |
| --- | ---: |
| Stock uninstrumented | 2.0103 ns/call |
| Instrumented, unpatched | 6.0329 ns/call |
| Incremental guard cost | 4.0226 ns/call |
| Instrumented/stock ratio | 3.0010x |
| Unrelated active slot | 6.4734 ns/call |
| Patched/interpreted | 557.9237 ns/call |

The unpatched result passed the predeclared `<=10 ns` and `<=5x` hot-leaf gate.
Signed activation was 3.309 ms median, including 3.083 ms Ed25519 verification.
Reported process completion, RSS (+704,512 bytes), and executable size are host
diagnostics, not Flutter startup/device measurements. Broad declaration counts,
typed/control/instance/async workloads, device startup/memory, and alternative
lookup strategies remain unmeasured. No optimization was accepted without data.

## 9. Patch size

Measured experimental E0 specimens include 540-byte typed, 576-byte exception,
765-byte collections/control-flow, 1,022-byte async, 663/683-byte dependency,
795-byte benchmark, and 867-byte iOS-prepared patches. The 795-byte E0 became a
1,238-byte signed envelope; the 867-byte E0 became 1,349 bytes. Phase 0's old
physical Android patch was 329 bytes.

The instrumented host executable grew by 492,496 bytes (8.62%), including the
whole runtime; no binary-growth acceptance threshold was predeclared. These
small lab patches are not representative production-app size claims. Canonical
JSON E0/E1 remains an experimental versioned format, not a final container
selection.

## 10. Security

Verified host-side controls include strict canonical signed bytes, Ed25519
verify-before-decode, a release-owned trusted-key map, exact app/release/build/
function/signature/capability binding, sequence/replay/equivocation rejection,
typed value validation, bytecode verification and budgets, serialized atomic
activation, dual checksummed durable state, pending/healthy/LKG recovery,
fail-closed base fallback, and signed higher-sequence rollback.

Open security work includes a broader malformed/Wycheproof corpus, production
offline-key custody and revocation,
protected monotonic storage, process-kill fault injection, real crash-loop
health policy, more retained generations, real capability permission checks,
concurrency and abortable cancellation, memory/allocation profiling, and a
production threat model. A signature authenticates an artifact; it does not make
its behavior safe or policy-permitted.

## 11. Store-policy implications

The current official-source [change matrix](../../store-policy/change-matrix.md) uses
three engineering gates:

- Interpreted Dart business fixes, executable UI/text, widget hierarchy,
  navigation, and pure-Dart dependency updates are **POLICY REVIEW REQUIRED**.
- Native code/plugins/SDKs, new host capabilities, manifests/plists,
  permissions, entitlements, and normal compiled dependency changes are
  **STORE RELEASE REQUIRED**.
- Passive text, media/data assets, and localization consumed by fixed existing
  paths may be **LIKELY OTA-SAFE ARCHITECTURALLY**, subject to content, privacy,
  commerce, metadata, and app-specific rules.

Apple's downloaded-code rule and conditional interpreted-code language do not
resolve this runtime. Google's interpreter exception does not override its
self-update, review-transparency, SDK, or behavior rules. No App Store or Google
Play compliance claim is supported; written platform-specific review of the
concrete mechanism remains a production gate.

## 12. Architecture assessment

| Architecture | Phase 0B assessment |
| --- | --- |
| A — explicit patch views | Technically contained and naturally capability-bounded, but fails the preferred transparent existing-app experience. Retain as a deliberate fallback. |
| B — source instrumentation | Best current evidence: stock toolchain, ordinary source, original AOT fallback, bounded async/UI/ecosystem/security, and acceptable measured hot-leaf overhead. Still owns a subset compiler/VM and fragile build overlay. |
| C — Kernel transformation | Semantically cleaner resolved IR, but no supported pre-TFA third-party seam was found and exact-SDK frontend coupling is high. Spike only after a demonstrated source-fidelity failure. |
| D — compiler/Flutter/Dart fork | Highest semantic ceiling and a proven architecture class, but imposes permanent frontend/VM/engine/tooling maintenance. Current evidence does not justify escalation. |

No pivot trigger positively fired. The bounded dispatch, async, ordinary
`Widget.build`, named-declaration compatibility, Android physical, and iOS
physical gates passed. Binary growth, representative source fidelity, closures,
broader Flutter coverage, and repeated Flutter/Dart upgrade cost remain open or
unevaluable. Continue Architecture B only while these conditions are tested
explicitly.

## 13. Recommendation

**PROCEED TO PHASE 1 WITH CONDITIONS**

This means continue evidence-driven Architecture B research; it does not select
a production architecture. Conditions:

1. Treat the completed Android and iOS device sequences as entry evidence, not
   as proof of general platform compatibility. Treat an interpreter/runtime
   restriction in new device cases as a pivot trigger.
2. Establish explicit closure/useful-coverage thresholds and pivot if the
   supported subset remains impractical for representative applications.
3. Prove representative multi-package, parts, generated-code, diagnostics,
   source-map, flavor, and upgrade fidelity before broad instrumentation claims.
4. Predeclare and meet device startup/memory, broad-dispatch, binary-growth, and
   patch-size budgets.
5. Close device crypto, process-kill/crash recovery, key lifecycle, real
   capability, permission, cancellation, and memory/resource gaps before remote
   production-shaped delivery.
6. Keep platform-policy review independent and block production code-bearing
   OTA until written guidance exists for the concrete runtime and app behavior.

## 14. Phase 1 proposal — not authorized or executed

1. **Representative build graph.** Add one intentionally adversarial multi-package
   Flutter app with parts, conditional imports, generated exclusions, flavors,
   diagnostics, source maps, and reproducible manifests.
2. **Closure viability gate.** Implement only a bounded immutable capture/call
   model if predeclared real fixtures justify it; otherwise quantify coverage
   loss and compare B/C/D.
3. **Selection and scale.** Instrument a representative declaration count,
   measure binary growth and device overhead, and test include/exclude behavior
   without creating a broad configuration product.
4. **Runtime hardening.** Add allocation/recursion/async concurrency budgets,
   fuzz/malformed corpora, process-kill fault injection, protected sequence
   strategy, key rotation/revocation design, and real narrow host adapters.
5. **Reactive generation signal.** Prototype one framework-neutral, opt-in
   generation notification and prove it can refresh intended consumers without
   recreating unrelated Riverpod/BLoC/navigation state.
6. **Policy review package.** Prepare reproducible artifact descriptions,
   capability inventories, representative diffs, and questions for Apple and
   Google. Do not submit or claim approval without maintainer authorization.
7. **Architecture checkpoint.** Re-audit all pivot triggers and choose whether to
   continue source instrumentation, spike pre-TFA Kernel, accept explicit views,
   or propose a separately approved fork program.

Phase 1 implementation must wait for maintainer review.

## Task 42 follow-up boundary (2026-08-23)

The Phase 0B decision above remains the dated 2026-08-22 result based on the
physical Android/iOS evidence listed there. It must not be read as evidence
that the later authenticated product-service runtime path was already tested.
Task 42 supplied that missing service-path evidence on iOS: a generated stock
Flutter arm64 Release installed once, fetched a signed patch through the
read-only adapter, changed the ordinary pricing receipt 540→450, survived
restart, and remained usable after service outage. The same iOS USB evidence
set physically rejected exact stale sequence-4 bytes after rollback while
retaining BASE/high-water.

The corresponding authenticated Android run was attempted but is
`ENVIRONMENT-GATED` for this checkpoint: `adb devices -l` and `adb mdns
services` returned no device and known Wi-Fi endpoints refused connection.
Therefore no current Task 42 or new cross-platform service-path completion
claim is made from inference; Android must be rerun when the device transport
is available. No P2 or production work is authorized by this follow-up.

### Task 42 Android completion correction (2026-08-23)

The preceding paragraph is the historical environment-gated checkpoint, not
the final Task 42 result. After the Android device returned on ADB Wi-Fi, the
direct cross-feature run and the generated authenticated Android service path
both passed. The final stock arm64 Release APK installed once for its
sequence; a 2,069-byte signed patch changed the ordinary receipt `540→450`,
survived restart and service outage, and left package install timestamps
unchanged. Direct invalid-signature, rollback, stale-byte, and rollback-
persistence stages also passed. See
`docs/research/evidence/task42-android-control-plane.md` and the completed
Task 42 record. This adds evidence; it does not alter the historical Phase
0B recommendation or authorize Phase 1/P2 implementation.
