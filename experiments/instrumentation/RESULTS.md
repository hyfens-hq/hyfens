# E0 results

## Task 22 — host performance and selective instrumentation

Task 22 predeclared its protocol before measurement in
`tool/performance/PROTOCOL.md`. On 2026-08-22, the macOS arm64 Apple M4 host ran
Dart 3.13.0 stable AOT executables with 10,000,000 hot-leaf calls per process,
two warm-ups, and 15 process-isolated samples per variant. Variant order was
randomized deterministically by sample round. No sample was discarded and no
protocol reduction was used. After the initial evidence review, the additive
Protocol Amendment 1 was recorded before a schema-v2 replacement run. The
complete sample order, commands, exit statuses, timestamps, outputs, checksums,
environment, and SHA-256 source/artifact inventories are in
`tool/performance/results/task22-host-raw.json`.

The replacement run closes the review's provenance gap: both harnesses protect
their scratch roots, reject competing builds, record process provenance, validate
expected checksums, and hash the relevant harness, fixture, package metadata, and
runtime source inputs. The superseded schema-v1 raw hashes remain in Task 22
history rather than being represented as the corrected evidence.

The inherited hot-leaf acceptance gate **passes**. Instrumented/unpatched dispatch
adds 4.0226 ns/call and is 3.0010x stock, below both predeclared limits of 10
ns/call added and 5x stock.

| Hot-leaf AOT variant | Median | p95 | MAD | Median ns/call |
|---|---:|---:|---:|---:|
| Stock | 20,103 us | 20,354 us | 54 us | 2.0103 |
| Instrumented, unpatched | 60,329 us | 64,865 us | 415 us | 6.0329 |
| Instrumented, unrelated slot active | 64,734 us | 69,576 us | 2,316 us | 6.4734 |
| Patched, interpreted | 5,579,237 us | 5,703,580 us | 21,022 us | 557.9237 |

The active-table microbenchmark measured a tight-loop diagnostic of the current
dense lookup without adding an optimization. Because the slot is loop-invariant
and the AOT optimizer's generated code was not inspected, these figures are not
claimed as a non-elided standalone lookup cost. The loop scaled with iteration
count and retained observable hit/checksum outputs. An in-range miss took 2.3953
ns/iteration median (23,953 us;
p95 24,045 us; MAD 92 us), and a hit took 2.1181 ns/iteration median (21,181
us; p95 23,959 us; MAD 1,992 us). No cached-flag or generation alternative was
implemented safely, so none was measured or adopted. The unrelated-active hot
variant is the end-to-end evidence for the currently important miss case.

Reporting-only process metrics were noisy at this scale. External wall time to
process completion was 23.623 ms median for stock (p95 32.402 ms, MAD
3.112 ms) and 25.126 ms for instrumented/unpatched (p95 41.958 ms, MAD 4.712 ms).
Each executable emits its single JSON output immediately before exit, but the
harness does not independently timestamp that line as a ready marker.
macOS `/usr/bin/time -l` peak RSS was 14,368,768 bytes median stock and 15,073,280
bytes instrumented, a 704,512-byte increase. These are host process launches,
not Flutter first-frame or device measurements, and have no acceptance threshold.

The stock executable was 5,716,288 bytes and the instrumented executable was
6,208,784 bytes: +492,496 bytes (+8.62%). The measurement includes the complete
experimental loader, verifier, interpreter, and two guarded functions, so it does
not isolate guard code size. The hot patch was 795 bytes and the unrelated patch
669 bytes.

E1 signed activation was measured in a separate AOT worker with the same two
warm-ups and 15 randomized, process-isolated samples. The complete raw file is
`tool/performance/results/task22-activation-raw.json`.

| Activation stage | Median | p95 | MAD |
|---|---:|---:|---:|
| Read 1,238-byte envelope | 30 us | 37 us | 1 us |
| Canonical envelope framing | 90 us | 122 us | 3 us |
| Ed25519 verify (including framing) | 3,083 us | 3,163 us | 13 us |
| E0 container decode/compatibility | 259 us | 275 us | 8 us |
| Runtime install (decode plus publish) | 257 us | 283 us | 6 us |
| Full verify and runtime install | 3,309 us | 3,351 us | 15 us |

The signed envelope was 1,238 bytes for the 795-byte patch. Full activation does
not include controller persistence, health-state transitions, or download time.
Runtime install includes a second container decode because the runtime deliberately
does not expose a publish API for a previously decoded program.

Selective instrumentation is now an explicit, auditable planning policy layered
over the existing package overlay. Application package libraries are included by
default; local-path and hosted pure-Dart dependencies require package opt-in;
explicit library exclusions take precedence; generated files are excluded by
default; and unresolved/SDK, Flutter/framework, part, and `dart:ffi` boundaries
cannot be opted in. The plan records a stable reason and hard/soft status for every
candidate. It remains source-unit explicit and does not claim transitive build-graph
discovery. Focused tests cover application default, local and hosted dependency
opt-in, dependency default exclusion, explicit exclusion, generated exclusion,
SDK-like outside-package input, Flutter, native/FFI, excluded entrypoints, and
building only the selected units.

Typed, control/collection, instance, and async native-AOT correctness remain
covered by their existing fixtures and historical results below, but Task 22 did
not rerun them as 15-sample performance matrices. No physical-device work was run.
The historical Task 08 measurements below are unchanged.

## Task 21 — pure-Dart dependency units

Task 21 adds an explicit multi-library overlay seam without changing patch/runtime
v9. Release-manifest v8 records a sorted library URI allowlist, and declarations
from every selected package unit share one deterministic dense slot table installed
by the transformed entrypoint. The derived package configuration points selected
packages at ephemeral transformed copies while retaining the original configuration's
other dependencies.

A checked-in `pure_dep` path package passes native AOT base and patched runs through
both direct and pre-existing tear-off calls. Corrupt and wrong-package artifacts
leave the original body active; compilation rejects wrong library routing and
signature drift. A second integration patches `collection` 1.19.1
`equalsIgnoreAsciiCase` through `package:collection/src/comparators.dart`; its Pub
cache source hash remains unchanged. Reversing input-unit order emits the same
manifest and transformed dependency source.

The experiment remains unit-explicit. Parts, SDK/Flutter/generated/FFI units,
transitive export-graph copying, MethodChannel implementations, and Android/Apple
native binaries are excluded. The focused Task 21 test passes three cases including
native AOT and hosted-package execution. The broader Dart suite reached 174 passing
tests; one Flutter subprocess test failed on a missing pre-existing generated
`NativeAssetsManifest.json` input, outside the Task 21 source/package path.

## Task 14 — application capability registry v8

Task 14 replaces the compiler's hard-coded async fixture lookup with an exact
release-manifest allowlist and an immutable application-owned registry. Patch
format/runtime version 8 and release-manifest version 6 bind stable ID, version,
compiler-only source routing name, argument/result schemas, sync/async execution
kind, detach-only cancellation, resource labels, timeout, output limit, and
side-effect classification. Source names are excluded from runtime equality and
digest. Candidate activation matches one configure-once authority combining the
shipped manifest and host registry; installation accepts no independent allowlist.

The bounded fixture contracts cover logging, clock.now, storage read/write,
navigation.push, and HTTP GET. Their tests use deterministic in-memory handlers;
no real filesystem, network, navigation, platform channel, FFI, reflection, or
plugin API is invoked. Duplicate registration/IDs, undeclared source names,
newly registered but unshipped capabilities, and version/schema/policy mismatch
fail closed. Atomic rejection preserves the known-good program.

The existing async continuation pins its frozen authority and retains its deadline, detachable exactly-once
resume token, bounded host-failure translation, fatal runtime-error preservation,
and no-AOT-rerun rule after a capability starts. Per-capability Future timeouts
and encoded output limits are additionally enforced with stable redacted failures.
A dedicated typed sync opcode supports cheap fake clock/log calls; fatal sync
failures disable the slot and cannot select AOT fallback. Configure/reset reject
during active continuations, and pending installs cannot cross reset lifecycles.
Final adversarial coverage also proves both opcode/kind mismatch directions
reject, application descriptors cannot bypass wire bounds, source-renamed equal
contracts share hash identity, and receiver errors redact custom secret/path/URL
text. Async activation additionally rejects the sync opcode that its executor
does not support, and a wrong post-await receiver value is an uncatchable contract
fault rather than a guest-visible adapter failure.

Consolidated validation on 2026-08-22:

```text
dart format lib bin tool test fixture
dart analyze --fatal-infos
No issues found!

dart test
00:04 +158: All tests passed!
```

## Task 13 — stable identity and compatibility v7

Task 13 advances patch/runtime format to version 7 and the release manifest to
version 5. Function identity now binds structured/versioned canonical `package:`
library URI, top-level or class owner, and member kind/name fields. The exact
signature digest is compatibility metadata, not semantic identity. Whitespace,
signature changes, and declaration movement inside one logical library retain
identity, while signature changes fail compatibility. Function/class rename or movement to another logical
library changes identity; there is deliberately no inferred refactor alias.

The strict patch envelope now includes caller-provided `buildFingerprint`, positive `patchSequence`, and a
deterministic SHA-256 `payloadHash` over recursively canonicalized JSON excluding
the hash field itself. Activation rejects wrong format/runtime/app/release,
unknown or missing fields, unknown functions/slots, signature or receiver
mismatch, incomplete signature/receiver tables, incompatible capabilities,
noncanonical JSON, corrupt hashes, stale sequences, and equal-sequence equivocation.
An exact equal-sequence/payload retry is an idempotent no-op.
Candidate decode, compatibility, capability, bytecode verification, and hash
checks finish before the active slot table changes, and regression coverage proves
that rejection preserves the previously installed program.

Automated tests cover whitespace, declaration reordering, logical file movement,
function/class rename, signature compatibility, canonical path/receiver identity,
package-config resolution across different checkout roots, part rejection, deterministic
release/patch bytes, forged manifest identity and signature digests, digest
collision injection, malformed input, corrupt hashes, unknown fields, wrong
runtime/release/build/signature, idempotent/equivocated/stale sequences,
capability incompatibility, and
atomic N+1 rejection. The full suite includes the existing native AOT top-level,
instance, control-flow, exception, typed-value, and async regressions.
Package-config discovery also rejects a configured `bin/` file presented as a
logical `lib/` input. Argument-based activation preserves and executes active N
after no-argument, unreadable-path, and corrupt-candidate attempts.

Consolidated validation:

```text
dart format lib bin tool test
Formatted 27 files (0 changed)

dart analyze
No issues found!

dart test
+139: All tests passed!
```

## Task 12 typed async continuation and closure spike

Task 12 advances the experimental format/runtime to version 6. The transformer
now recognizes an ordinary explicitly typed `Future<T>` top-level function or
instance method and emits an async guard. The patch compiler lowers only direct
`await` calls to exact pre-registered typed host capabilities. The generated guard
returns the interpreted Future when startup succeeds; a runtime fault after a host
operation begins completes that Future with an error and never reruns the original
AOT body.

The continuation is heap state: immutable program and installation generation,
PC, typed stack and locals, v5 exception frames, invocation zone, total instruction
budget, monotonic deadline, resume counters, and exactly-once state. Immediate
Future completion is scheduled normally rather than resumed inline. Delayed and
never-completing capabilities return control to the event loop; a deadline releases
the retained continuation. One outstanding await is permitted per interpreter turn.

Automated evidence proves:

- immediate, delayed, and two sequential awaits without blocking the isolate;
- `Future<int>` and recursively checked `Future<Map<String, dynamic>>` results;
- the invocation zone before and after each suspension;
- an awaited host error caught by guest catch-all with `finally` executing once;
- an uncaught Future error crossing as bounded `E0HostFailure` metadata;
- wrong result schema becoming an uncatchable `E0RuntimeFault`, disabling the
  current slot, and not selecting AOT fallback after the capability started;
- one total instruction budget across resumes, a never-Future deadline, retained-
  state cleanup, and stale-resume rejection;
- detachable callback tokens that retain no program, arguments, receiver adapter,
  stack, locals, or handler frames after a never-Future deadline;
- `E0RuntimeFault`, `StackOverflowError`, and `OutOfMemoryError` from synchronous
  capability invocation, Future error completion, or a receiver read during a
  resumed interpreter turn bypassing guest catch, settling the caller Future, and
  disabling the current installed slot;
- instruction-budget exhaustion during a resumed interpreter turn bypassing a guest
  `try`/`catch`, settling the caller Future, and disabling the installed slot;
- atomic rejection of malformed and capability-incompatible N+1 patches while a
  known-good N remains installed and executable;
- replacement/rollback isolation: a pending old program finishes against its pinned
  code while new calls use the newly installed program;
- an ordinary async instance method reading one descriptor-selected receiver field;
- exact rejection of missing/mismatched capability registrations, malformed await
  metadata, unsupported capability calls, and arbitrary `Future<Result>` objects.

The native-AOT fixture is stock Dart AOT using the same source instrumentation seam.
The release source contains ordinary `Future<int> calculateAsync(int) async` code.
The patch performs two awaited host operations and changes the result while a timer
proves that the event loop progressed:

```text
base:             result=4  instanceResult=7  eventLoopTicked=true
top-level patch:  result=18 instanceResult=7  eventLoopTicked=true
instance patch:   result=4  instanceResult=28 eventLoopTicked=true
corrupt fallback: result=4  instanceResult=7  eventLoopTicked=true
```

The instance case is transformed from an ordinary `AsyncService.calculate`
method. Its generated same-library receiver adapter exposes only the selected
`delta` field; the patch awaits the typed host capability and reads that field.
The corrupt patch run proves the unmodified AOT method remains the fallback.

The deterministic two-await v6 patch is **1,022 bytes**, has two async points and
24 code words. `tool/async_benchmark.dart` was compiled with `dart compile exe` on
the Phase 0 macOS arm64 host. Seven process samples of 10,000 sequential invocations
with both capabilities returning `Future.value` measured 6.1074–6.6161 µs per
invocation; the median was **6.1769 µs/invocation**. The matching 20-invocation runs
with one one-millisecond delayed capability measured a median total of **50,533 µs**.
These numbers include Future scheduling and two interpreter suspensions. They are
not a Flutter UI, memory, startup, or physical-device benchmark.

Closure status is **NOT YET SUPPORTED**. The time-bounded spike added compiler
regressions for immutable capture, mutable capture, nested functions, and closure-
based collection APIs. All fail explicitly. No function-value schema, closure
allocation/call opcode, capture environment, shared mutable cell, or tear-off bridge
was added. This is not yet an architectural block, but it remains a material Dart
coverage risk and must be revisited against widget/Riverpod/navigation fixtures.

The validated async surface is intentionally narrow. There is no `async*`, `await
for`, concurrent Future set, `Future.wait`, arbitrary Dart call, stream, timer,
Completer, reflection, plugin call, general cancellation, or serializable Future.
Collection construction/mutation opcodes are rejected in async v6; the Map proof is
a schema-checked host capability pass-through. A Future without any await is also
not patchable in this slice. The capability names are test-only internal adapters;
Task 14 must formalize the application registry before product use.

No async pivot trigger occurred. The non-blocking continuation fit the existing
source-instrumented typed stack VM without a Dart/Flutter fork, preserved handler
and zone behavior, and maintained safe rollback generation pinning. The result is
**PARTIAL** async support, not general Dart async compatibility.

Final consolidated instrumentation validation formatted 38 Dart files with no
remaining changes, reported no analyzer issues under `--fatal-infos`, and passed
**122 tests**, including every native-AOT fixture. The focused async-v6 suite
contains **27 tests**, and the native-AOT async test covers both top-level and
instance-method guards.

## Task 11 bounded exception extension

Task 11 advances the experimental format/runtime to version 5. The compiler lowers
ordinary `try`, one catch-all `catch`, `finally`, bounded non-null `throw`, and
`rethrow` into fixed handler metadata plus six explicit control opcodes. Runtime
frames preserve a pending normal, return, or guest-throw completion. Tests prove
finally executes once on normal, caught, uncaught, and return paths; return or throw
inside finally replaces the pending completion; nested rethrow retains the original
synthetic `(functionId, pc)` trace.

The AOT boundary now distinguishes success, uncaught guest throw, and interpreter
runtime fault. Uncaught guest throws do not deactivate the patch. The generated
ordinary-function guard rethrows their bounded payload with `Error.throwWithStackTrace`,
and a stock native-AOT caller catches the changed integer throw and identifies the
synthetic E0 trace. Instruction-budget and other runtime faults remain uncatchable
by guest code, deactivate the patch, and select the original AOT body.

At the existing descriptor-selected receiver boundary, any ordinary Dart-thrown
object is translated to bounded `E0HostFailure` metadata rather than exposed by
reference. Tests cover `StateError` and an arbitrary thrown String. Guest catch-all
control flow handles both; an uncaught host failure crosses as the stable metadata
type. `E0RuntimeFault`, `StackOverflowError`, and `OutOfMemoryError` are explicitly
excluded from translation.

Predictable collection failures are now guest transfers too: List out-of-range
read/write, forged out-of-range iteration, and a missing Map key are caught by guest
catch-all logic. An uncaught List failure keeps the patch installed. Collection-size
budget exhaustion remains an uncatchable runtime fault. Missing Map keys deliberately
throw in the non-null map-value subset; an explicitly nullable value schema returns
null. This does not claim complete Dart Map nullability semantics.

The verifier rejects non-dense IDs, invalid/missing ranges, partial overlap, missing
or misplaced completion opcodes, illegal cross-section jumps, unknown handler
fields, rethrow outside catch, non-empty boundary stacks, and more than 32 regions.
Compilation rejects typed/user-defined catches, multiple catch clauses, catch
stack-trace bindings, reading a catch binding, nullable throws, and break/continue
crossing a handler boundary. These are explicit subset limits, not silent fallback.

Native AOT evidence:

```text
base:          result=6
patched:       error=77 type=int syntheticTrace=true
corrupt patch: result=6
```

The deterministic nested catch/rethrow/finally native fixture patch is **576
bytes**. Consolidated instrumentation validation after Task 11 is 94 passing tests,
including compiler, interpreter, malformed-container, integration, and native-AOT
coverage. No architecture pivot trigger was observed: structured exception cleanup
fit the source-instrumented stack VM without compiler or Flutter forks. Async
exceptions and continuation cleanup remain Task 12 work.

## Task 10 control-flow and collections extension

Task 10 advances the experimental container/runtime to version 4 without changing
the source-instrumentation architecture. Normal typed Dart locals become deterministic
lexical slots recorded in the patch. The verifier propagates both stack schemas and
the set of definitely initialized locals; control-flow joins intersect initialization
sets, so a forged or compiled read initialized on only one branch is rejected.

The compiler now lowers nested `if / else`, scalar constant `switch`, `while`,
declaration-based C-style `for`, early return, and typed `for-in` over List, Set, and
`Map.keys` to verified jumps. The existing global instruction budget remains shared by
the entire invocation and terminates a deliberately infinite compiled loop. Pattern
switches, general Iterable lowering, closures, and higher-order `map`/`where`/`fold`/
`forEach` are rejected explicitly rather than interpreted approximately.

List, Map, and Set evidence covers indexing/lookup, assignment, length, iteration,
contains, literals, and imperative add/transform operations. Set is now a typed schema
and tagged wire value whose deterministic encoding sorts canonical tagged elements;
duplicate, non-canonical, oversized, and malformed values fail closed.

Collection mutation is isolated at the host boundary. One identity memo spans all
arguments and selected receiver values in an invocation, preserving repeated and
nested guest aliases. Local loads retain the same guest object. Both successful and
faulting mutation tests leave the original host collection unchanged; return values
are revalidated and copied. This resolves the mutable-alias question for the bounded
value universe without exposing arbitrary host objects.

Argument collection mutation is therefore by-value guest behavior: it can build a
transformed return value, but it does not reproduce ordinary Dart caller-visible side
effects. Task 10 classifies that difference as a bounded semantic limitation, not
transparent general mutation support.

Coordinator regressions additionally prove that mutation directly rooted in a
receiver property (`this.items.add(...)` or `this.items[index] = ...`) is rejected
with the transactional receiver-write diagnostic, even though guest copies would
protect the host object. Receiver origin is also propagated conservatively through
local alias chains, parentheses, and reassignment; mutation through those aliases is
rejected while reads and iteration remain available. Switch members that could fall
through are rejected rather than given an implicit break; explicit `break` and
`return` paths execute normally.
Map-key and Set iteration retain Dart insertion order (`bac` and `312` in the
fixtures), while canonical sorting remains a wire-encoding property only.

The native AOT fixture instruments an ordinary `List<int> revise(List<int>)`, compiles
the stock transformed source with `dart compile exe`, and applies a v4 patch containing
a C-style loop, index reads/writes, local alias, and `add`. Its output proves both the
changed return and unchanged input:

```text
base:    input=[2,3] result=[2,3]
patched: input=[2,3] result=[4,6,7]
```

The deterministic v4 control/collection fixture patch is **765 bytes**. It includes
the recursive function signature, two explicit local schemas, four tagged constants,
and 46 bytecode words; it is not directly comparable to the earlier integer-only or
literal-only patches.

Task 10 remains intentionally imperative and synchronous. It does not establish
closure, exception, async, general Dart collection API, or Flutter compatibility.
There was no architecture pivot trigger in this package: structured flow remained a
small verified-bytecode extension, and collection isolation preserved host safety and
guest alias identity.

Consolidated Task 10 validation:

```text
cd experiments/instrumentation
dart analyze
No issues found!

dart test
+72: All tests passed!

cd ../patch_loading
dart analyze && dart test
No issues found; +6: All tests passed!

cd ../../fixtures/flutter_conformance_app
flutter analyze && flutter test test/conformance_widget_test.dart
No issues found; +2: All tests passed!
```

## Task 09 instance-method extension

Task 09 keeps the existing callee-entry guard and proves a narrow transparent
ordinary instance-method path without reflection or a raw-object bridge. The
release manifest and version-3 patch container carry a receiver descriptor. It
contains only explicitly referenced `this.<property>` reads from the selected
original method, with stable member IDs, deterministic dense slots, and typed E0
schemas. A generated same-library adapter is constructed only after the patched
slot branch is taken.

The `PricingService` fixture proves typed reads of a field, a getter, and a private
same-library field. Native AOT execution proves direct calls, an inherited base
declaration invoked on a subclass instance, and a method tear-off all change under
the base patch. A distinct override retains its AOT result and has a distinct
class-qualified function ID. No source call-site rewrite or special patchable base
class is required.

The native fixture deliberately declares the former generated identifiers
`$e0Patch`, `$e0Result`, `_E0ReceiverAdapter0`, and `e0_runtime`. The transformer
deterministically freshens its import prefix, guard locals, and adapter class name;
the transformed program resolves, compiles to AOT, and retains the expected base
and patched dispatch results.

The compiler accepts a normal class-contained method with explicit selected
property reads. Tests reject raw `this`, receiver method invocation, an unselected
property, malformed adapter values, wrong adapter identity, forged descriptors,
and invalid receiver bytecode slots. Static, abstract, accessor, operator, generic,
async/generator, and generic-owner targets are rejected or excluded. Setter writes
remain unsupported: eager host mutation could survive a later interpreter fault,
so safe support requires staged writes and atomic commit semantics.

Only explicit original `this.property` syntax contributes receiver slots.
Unqualified ordinary Dart access such as `taxRate` is not inferred by the
syntax-only transformer; tests show that it creates no slot and that both an
unqualified patch reference and a newly explicit but unselected `this.taxRate`
reference fail compilation.

The demonstrated boundary is same-library, synchronous, block-bodied ordinary
methods with the Task 08 signature/value subset and read-only field/getter
capabilities. Cross-library private access, parts, mixins, extensions, writes,
arbitrary method calls, and raw object access are not supported. This result does
not yet establish broader inheritance transformations or Dart object semantics.
The proven getter is pure. Getters can throw or perform side effects; if a getter
mutates state before a later interpreted fault, AOT fallback can repeat effects and
is not transactional. Side-effecting or throwing getters are therefore outside
the demonstrated safe boundary alongside receiver writes.

Native AOT fixture output:

```text
base:    direct=18.5 virtual=18.5 tearOff=18.5 override=99.0
patched: direct=26.5 virtual=26.5 tearOff=26.5 override=99.0
```

Consolidated Task 09 validation:

```text
cd experiments/instrumentation
dart analyze
No issues found!

dart test
+57: All tests passed!

cd ../patch_loading
dart analyze && dart test
No issues found; +6: All tests passed!

cd ../../fixtures/flutter_conformance_app
flutter analyze && flutter test test/conformance_widget_test.dart
No issues found; +2: All tests passed!
```

## Task 08 typed-runtime extension

Task 08 advances the experimental container/runtime to version 2. The release
manifest now records explicit parameter and return schemas; the patch repeats the
signature, and activation rejects a mismatch. The supported host value boundary is
null, bool, int, finite double, String, typed List, and String-keyed typed Map.
Values are recursively validated, bounded, copied, and deterministically encoded.

Compiler/runtime conformance fixtures cover:

- `String greet(String name)` including String interpolation;
- `bool isEligible(int age, bool verified)`;
- `double calculate(double amount, double rate)`;
- `Map<String, dynamic> transform(Map<String, dynamic> input)`;
- `List<int> filterValues(List<int> values)`;
- an explicit nullable `String? Function(String?)` path.

The Task 08 compiler adds only the expression opcodes needed by those cases:
matching numeric/String operations, boolean comparison/AND, indexing, and literal
List/Map construction. Arbitrary objects, top-level dynamic signatures, optional or
named parameters, calls, mutation, closures, and async remain rejected with an
unsupported-feature diagnostic. Full collection semantics are not claimed.

Automated evidence includes deterministic map/argument/container bytes, distinct
int/double tags, schema and return mismatch rejection, malformed value tags,
non-canonical maps, unsupported object values, non-String map keys, non-finite
doubles, depth/collection limits, safe malformed-argument fallback, transformed
source parsing, and a native AOT process test that changes `transform` without
changing the other generalized functions.

Coordinator review added two fail-closed regressions: omitted signature metadata is
bound to the legacy two-int contract rather than accepted as a wildcard, and `&&`
now uses true short-circuit jumps. A forged String-return patch for a legacy int slot
is rejected during activation, while a false left operand skips an intentionally
out-of-range List access on the right.

The version-2 `transform` patch fixture is **540 bytes**. This is not directly
comparable to the 300-byte Phase 0 integer patch: v2 includes the recursive
function signature and four explicitly tagged constants. Consolidated validation:

```text
dart analyze
No issues found!

dart test
00:03 +40: All tests passed!
```

Downstream compatibility checks also passed without changes to those consumers:

```text
cd ../patch_loading && dart analyze && dart test
No issues found; +6: All tests passed!

cd ../../fixtures/flutter_conformance_app
flutter analyze && flutter test test/conformance_widget_test.dart
No issues found; +2: All tests passed!
```

The Phase 0 measurements below remain historical and are not rewritten.

Date: 2026-08-22

Host: macOS arm64

SDK: Dart 3.13.0 stable

Command: `dart run tool/benchmark.dart 5000000`

Seven process-isolated samples were recorded after one warm-up per variant. Timing
is the in-process `Stopwatch` duration around five million calls; medians are used.

| Variant | Median | Approx. ns/call | Relative to baseline |
|---|---:|---:|---:|
| Stock AOT baseline | 10,942 µs | 2.19 | 1.00× |
| Instrumented, unpatched | 17,748 µs | 3.55 | 1.62× |
| Patched, interpreted | 1,072,813 µs | 214.56 | 98.05× |

The unpatched guard added approximately **1.36 ns/call**, satisfying the E1 gate
of no more than 10 ns/call and no more than 5× the direct baseline. The generated
guard performs a dense-slot lookup and null branch before any patched invocation;
the runtime allocation counter remained zero for an unpatched lookup in tests.

The baseline executable was 5,716,304 bytes; the instrumented executable was
5,831,216 bytes (+114,912 bytes, +2.01%). The deterministic patch was 300 bytes.
The original fixture SHA-256 was
`fc12e4c272c27659155c5adcf370053753a329143e417800b5d55114e476982d`.

Native execution results:

```text
baseline:               direct=7  tearoff=7
instrumented-unpatched: direct=7  tearoff=7
patched-interpreted:    direct=19 tearoff=19
```

## Task 16 bounded widget-build result

Patch/runtime v9 and release-manifest v7 add a build-tool-selected ordinary
`StatelessWidget.build` guard. The guest returns a bounded node record; an
immutable application registry materializes only exact, program-declared
factory contracts. `BuildContext`, raw Widgets, reflection, and guest callbacks
do not cross the value boundary.

The demonstrated factories are `Text`, `Column`, `TextStyle.fontSize`, and an
`ElevatedButton` with a disabled host callback. An ephemeral overlay transforms
the checked-in Flutter `PricingCard`, compiles its patch, and runs a real Flutter
widget test. Patched text, a conditional added child, hierarchy, and style are
visible while base text is absent. Real Flutter tests also cover factory throws,
wrong nested results, AOT fallback, and active-to-base reset/rebuild. A separate
native-AOT fixture uses stand-in widget classes; no real Flutter release-AOT or
device result is claimed.

Adversarial review found and fixed a factory-authority bypass. Each program's
declared factories are now its execution allowlist at install and recursive
materialization. Tests also reject invalid contracts/values, unknown properties,
wrong child/root types, empty names, excessive trees, noncanonical manifest
paths, and common syntax shadows. The six-edge widget depth is tested through
the general E0 value budget.

Consolidated validation:

```text
cd experiments/instrumentation
dart format --output=none --set-exit-if-changed lib test fixture
Formatted 44 files (0 changed)
dart analyze
No issues found!
dart test
+170: All tests passed!

cd ../../fixtures/flutter_conformance_app
flutter analyze
No issues found!
flutter test
+4: All tests passed!

cd ../../experiments/patch_loading
dart analyze
No issues found!
dart test
+25: All tests passed!
```

The compiler remains syntax-guided rather than semantically resolved. It does
not cover all possible top-level shadows, and source-map URI normalization has a
documented follow-up. The signed E1 controller does not yet preserve/reconfigure
the widget registry across resets, so downloaded device UI activation remains
unproved.

## Caveats

- This is a microbenchmark of one synchronous top-level hot leaf, not Flutter,
  widget builds, startup, patch verification, memory, or a physical device.
- Patch loading and JSON validation happen before the timed loop; verification and
  load latency are not measured here.
- `Stopwatch` does not measure allocations. The zero-unpatched-allocation result is
  structural (no argument collection exists before the null branch) plus a runtime
  counter test, not a heap-profiler measurement.
- The roughly 115 KiB binary increase includes the whole experimental JSON loader,
  validator, and interpreter and is not attributable solely to the guard.
- The interpreter supports only the opcodes derived from this one changed function.
  The patched-path result is measure-only and is not an acceptance threshold.
- Results are one host/run. Compiler optimization and device behavior can differ;
  E1 must remeasure a stock Flutter Android release on physical hardware.
