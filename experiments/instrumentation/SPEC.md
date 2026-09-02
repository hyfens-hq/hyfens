# E0/E0B bytecode and patch format specification

The Phase 0 formats were experimental version 1. Task 08 introduced patch/runtime
version 2 (E0B) for typed signatures and values. Task 09 introduces version 3 for
bounded instance receivers. Earlier evidence remains in repository history and
`RESULTS.md`. Task 10 introduces version 4 for typed lexical locals, structured
control flow, mutable invocation-local collections, and Set values. Version 4
deliberately fails closed on earlier containers because local schemas are part of
bytecode verification and compatibility validation.
Task 11 introduces version 5 for bounded guest exceptions, fixed handler
metadata, and distinct guest-throw/runtime-fault outcomes. Version 5 is an
intentional fail-closed format break; no v4 handler default is inferred.
Task 12 introduces version 6 for typed `Future<T>` signatures, explicit host
async-capability requirements, fixed await-point metadata, and non-blocking heap
continuations. Version 6 rejects every earlier patch container; async fields are
not inferred for v5 programs.
Task 13 introduces version 7 for semantic declaration identities, strict
release manifests, canonical payload hashes, and monotonic patch sequences.
Version 7 rejects every earlier patch container and release manifest.
Task 14 introduces patch/runtime version 8 and release-manifest version 6 for
application-owned capability contracts. Descriptor metadata is now hashed wire
data, so version 8 rejects earlier containers rather than inferring authority.
Task 16 introduces patch/runtime version 9 and release-manifest version 7 for a
bounded widget-description ABI and immutable application-owned widget factory
contracts. Version 9 does not claim arbitrary Flutter construction.
Task 21 keeps patch/runtime version 9 and advances the release manifest to
version 8. It adds a strict multi-library routing table for explicit pure-Dart
package overlay units; no patch bytecode or runtime instruction changes.

## Identity and dispatch

Stable ID material is the compact JSON encoding of these exact versioned fields:

```text
{"identityVersion":1,"libraryUri":"package:<package>/<library-path>","ownerKind":"library","ownerName":null,"memberKind":"topLevelFunction","memberName":"<name>"}
```

Instance method material is:

```text
{"identityVersion":1,"libraryUri":"package:<package>/<library-path>","ownerKind":"class","ownerName":"<class>","memberKind":"instanceMethod","memberName":"<name>"}
```

The external ID is `sha256:<lowercase hex SHA-256>`. Absolute paths, source
offsets, line numbers, whitespace, body text, and declaration order are excluded.
A base declaration and an override have distinct class-qualified IDs. IDs are
sorted lexically and assigned dense zero-based release slots. Any digest collision
between different materials fails the release transformation.

Whitespace changes, signature changes, and moving a declaration within the same
logical library keep its semantic ID. Signature compatibility is separate: every
manifest and patch carries the complete signature plus its SHA-256 digest, and a
changed signature fails compilation or activation for that stable ID. Changing the
function/class name, owner class, package, or logical library URI changes its ID.
In particular, moving a declaration to a
different logical file intentionally changes identity. Version 7 has no durable
source alias and does not claim magic persistence across arbitrary refactors.

Release manifest version 8 has exactly `manifestVersion`, `appId`, `releaseId`,
`buildFingerprint`, `canonicalLibraryUri`, `logicalLibraryPath`, `libraryUris`,
`functions`, `capabilities`, and `widgetFactories`. `canonicalLibraryUri` and
`logicalLibraryPath` identify the entrypoint. `libraryUris` is a non-empty,
lexically sorted, duplicate-free list containing that entrypoint URI, and each
function identity must route to one URI in the list. Function IDs from all
selected libraries are sorted together before dense global slots are assigned.
`buildFingerprint` is an opaque, non-empty, caller-provided normalized build input;
it is never derived from time, checkout path, or discovery order. Every function
entry has its name, structured identity fields, ID, dense slot, explicit signature and
SHA-256 signature digest, and receiver descriptor. Decode rejects missing or
unknown fields, unsupported owner/member kinds, non-dense/duplicate IDs, a forged
identity hash, root/function-name/receiver-owner routing disagreement, or a
signature digest inconsistent with the signature.

Logical `lib/...` paths canonicalize to `package:<package>/...`; receiver-property
identity uses the same canonical URI. Overlay file builds synchronously discover
the nearest `.dart_tool/package_config.json` using the direct `package_config`
dependency and require a resolved URI to agree with the explicit package/path.
When no package configuration exists, synthetic files may use that explicit
canonical input. If a configuration is found but the input cannot map through its
package URI root (for example `bin/` masquerading as `lib/`), transformation fails.
Raw transformation remains syntax-only: it does not resolve analyzer elements,
parts, or private-library ownership. Part files and part directives are explicitly
unsupported.

The Task 21 package assembler accepts only an explicit list of source units and
resolves each through one supplied package configuration. It writes transformed
copies below ephemeral package roots and derives a package configuration which
remaps those roots while retaining non-overlaid dependencies. SDK inputs cannot
resolve as `package:` units; generated filename patterns, Flutter imports, and
`dart:ffi` imports are rejected. Transitive source discovery/copying and native
Android/Apple replacement are not part of this format.

## Patch container

UTF-8 JSON with exactly these fields: `formatVersion`, `runtimeVersion`, `appId`,
`releaseId`, `buildFingerprint`, `patchSequence`, `functionId`, `slot`, `signature`, `receiver`,
`locals`, `handlers`, `capabilities`, `asyncPoints`, `constants`, `code`,
`widgetFactories`, and `payloadHash`.
Encoding uses recursively key-sorted compact JSON, making identical compiler inputs
byte-identical. Decode requires those exact canonical bytes, rejecting whitespace,
alternate key order, and duplicate-key spellings. `payloadHash` is lowercase
SHA-256 over that exact canonical payload consisting of every field except `payloadHash`;
excluding the hash field avoids a circular definition. The signature is compared
with the instrumented release manifest at activation. A changed parameter or
return schema is rejected before execution.
Activation requires signature and receiver tables whose keys exactly equal the
release function table. Missing, extra, or mismatched compatibility metadata fails
closed; there is no v7 legacy default.
Decode rejects unknown/missing fields, invalid UTF-8/JSON/types, a corrupt payload
hash, a non-positive or stale sequence, files over 64 KiB, more than 256 constants,
more than 2048 code words, wrong app/release/build fingerprint/runtime,
unknown IDs, or slot mismatch. E0 remains unsigned; signing is outside Task 13.
Version 7 permits at most 32 exception handlers, 32 capability requirements, and
64 static await points. Activation is atomic: decode, compatibility, capability,
and verifier checks complete before the slot table is replaced. A rejected N+1
container leaves an already active known-good N program installed. Successful
activation records its positive sequence and payload digest. Equal sequence plus
the same digest is an idempotent no-op; equal sequence plus a different digest is
explicit equivocation and is rejected; lower sequence is stale. This high-water
mark is process-local only. Durable restart high-water, signing, and rollback
persistence are intentionally deferred to Task 15.
Argument-based loading follows the same candidate-first rule: no patch argument,
an unreadable path, or a malformed/incompatible candidate never clears active N.

## Typed schemas and values

Host signatures must use explicit required positional types from this bounded set:
`bool`, `int`, finite `double`, `String`, `List<T>`, `Set<T>`, and
`Map<String, T>`, with
explicit `?` nullability. Task 10's host bridge accepts scalar `T`, plus bounded
List, Set, and String-keyed Map shapes with scalar or supported-value elements.
Top-level `dynamic`, arbitrary
objects, non-String map keys, optional/named parameters, and nested reified generic
host signatures fail during transformation or patch compilation.

`dynamic` is allowed only as a map/list/set value schema and means one recursively
validated E0 value, not an arbitrary Dart object. The runtime value universe is
null, bool, int, finite double, String, List, Set, and String-keyed Map. Every wire value
has an explicit tag so `1` and `1.0` remain distinct. Maps encode as lexically sorted
key/value entry arrays. Sets encode as arrays sorted by their canonical tagged JSON
value. Decoding rejects duplicate values and non-canonical Map/Set order. This wire
canonicalization does not define guest iteration order: runtime Map and Set values
retain normal Dart insertion order, including `Map.keys` and Set `for-in` lowering.

Limits are 16 value/schema nesting levels, 1,024 entries per collection, 4,096
value nodes, 64 KiB UTF-8 per String, and 64 KiB per encoded value/argument envelope.
Bridge conversion deep-validates collections. Each interpreted invocation uses an
identity-memoized deep mutable copy spanning every argument and selected receiver
value. Thus repeated/nested aliases remain aliases inside one invocation, while no
host List, Map, or Set is changed on success or failure. Constants are copied when
loaded. Results are validated and copied back through the declared return schema.
Consequently, mutating an argument collection changes only its by-value guest copy;
the Dart caller does not observe the side effect it would observe from ordinary Dart
mutation. This is a bounded semantic limitation for return-value transformations,
not transparent support for general mutable argument semantics.
Malformed arguments, return values, or runtime faults deactivate the patch and
return a runtime-fault invocation result so the generated guard executes the
original AOT body. An intentional uncaught guest throw is a distinct outcome: it
does not deactivate the patch and the generated guard rethrows it with the bounded
synthetic guest trace.

## Instance receiver capability

For an eligible ordinary instance method, the transformer scans only explicit
`this.<property>` accesses in that method's original body. It resolves explicitly
typed instance fields and getters in the same class or a same-library superclass.
Only those properties become receiver members. Each member has class-qualified
stable ID material, a dense deterministic slot, and a value schema. Unreferenced
members are absent. Cross-library private members, parts, mixins, extensions,
generic owner classes, and unresolved or unsupported property types are excluded.

The generated guard performs its slot lookup first. Only the patched branch
allocates a generated same-library adapter around `this`. That adapter implements
`E0ReceiverCapability`, exposes its descriptor ID, and maps bounded integer slots
to property reads. The interpreter receives the adapter, never the raw object. It
rejects a missing/wrong adapter, descriptor mismatch, invalid bytecode slot, or a
property value that fails the declared schema. There is no reflection, arbitrary
method invocation, or general object bridge.

Before emission, the transformer reserves every identifier token already present
in the source. It then deterministically freshens the runtime import prefix, guard
locals, and adapter class names. This prevents generated declarations such as the
historical `$e0Patch`, `$e0Result`, and `_E0ReceiverAdapter0` names from colliding
with ordinary user declarations. Generated runtime references always use the
freshened import prefix.

Patch source for an instance target is a normal class-contained method and may
read only selected properties with explicit `this.<property>`. Raw `this`, receiver
method calls, and unknown/unselected properties fail compilation. Receiver setter
writes are intentionally rejected: safe support requires staged writes with an
atomic commit after successful interpretation, which Task 09 does not implement.
The compiler conservatively propagates receiver origin through explicitly typed local
aliases, alias chains, reassignment, and parentheses. Mutation through any such alias
is rejected with the same transactional-write diagnostic; reads and iteration remain
allowed. Guest-copy isolation is never presented as successful receiver mutation.
Unqualified field/getter syntax such as `taxRate` is ordinary Dart but is not
selected by this syntax-only experiment; an original unqualified access produces
no receiver slot, and patch compilation reports that explicit `this.taxRate` must
have been selected in the release source.

The demonstrated getter is pure. A Dart getter may perform arbitrary side effects
or throw. If such a getter mutates state and later interpretation fails, executing
the original AOT body as fallback is not transactional and may repeat effects.
Task 09 therefore does not claim safe patching of side-effecting or throwing
getters; resolved semantic classification or transactional receiver operations
would be required before broadening this boundary.
Static, abstract, accessor, operator, generic, generator, and non-block method
targets are rejected or excluded with a diagnostic. Version 6 admits the bounded
async subset specified below.

## Bounded widget-build ABI

Only build-tool-selected classes that syntactically extend `StatelessWidget` and
declare exactly `Widget build(BuildContext)` use the widget ABI. Selection is
transformer metadata (`widgetBuildClasses`), not a source annotation or special
widget. The generated callee-entry guard passes no `BuildContext` argument: the
context and raw `Widget` objects remain host-owned. The guest returns the existing
bounded `Map<String, dynamic>` value schema as a node record with exactly
`factory`, `properties`, and `children` fields.

Each release manifest freezes application-owned factory descriptors by stable ID,
source constructor name, exact typed property descriptors, child arity, and a
canonical SHA-256 contract digest. A patch carries only descriptors it uses.
Activation requires an immutable registry with identical contracts. Materialization
accepts at most 16 factories, 16 properties per node, 32 children per node, depth
6, and 64 total nodes. Unknown factories, unknown or missing properties, wrong
property types, malformed records, contract drift, excessive trees, factory
exceptions, and a materialized root that is not the generated guard's `Widget`
type deactivate that slot and continue into the original AOT body.

The compiler proof implements only `Column(children, mainAxisSize)`,
`Text(String, style: TextStyle(fontSize))`, and
`ElevatedButton(onPressed: null, child)`. Button callbacks remain precompiled host
behavior; guest closures are rejected. Collection spreads/ifs, keys, inherited
theme reads, arbitrary constructors, named constructors, stateful widgets, and
general Flutter properties are outside this experiment. Registered factories are
expected to be pure construction boundaries; transactional rollback of arbitrary
host side effects is not claimed.

## Source offset map

`source-map.json` is deterministic JSON with `offsetMapVersion: 1`. Its units are
UTF-16 code units, matching analyzer/Dart `String` offsets. It records logical
original and overlay URIs, both source lengths, and contiguous generated segments.
Copied segments map linearly to an original range. Inserted segments have a null
original start, a synthetic kind (`runtime-import`, `callee-guard`, or
`runtime-init`), and an original anchor offset. Absolute paths are forbidden.

Decoding rejects unknown/missing fields, invalid types, gaps, overlaps, invalid
lengths/anchors, non-contiguous original coverage, and filesystem URIs. Lookup
rejects out-of-range offsets. E0 verifies source offsets only; it does not prove
that Flutter AOT stack traces retain enough symbolized location data to consume
this map.

## Stack bytecode

Words are non-negative JSON integers. Opcodes and operands are fixed-width:

| Code | Mnemonic | Words | Stack effect | Meaning |
|---:|---|---:|---|---|
| 1 | `loadArgument i` | 2 | `[] -> [T]` | Push signature argument `i`. |
| 2 | `loadConstant i` | 2 | `[] -> [T]` | Push tagged constant `i`. |
| 3 | `addInt` | 1 | `[T,T] -> [T]` | Add matching int/double or concatenate String (legacy mnemonic retained). |
| 4 | `subtractInt` | 1 | `[T,T] -> [T]` | Matching int/double subtraction. |
| 5 | `multiplyInt` | 1 | `[T,T] -> [T]` | Matching int/double multiplication. |
| 6 | `lessThanInt` | 1 | `[T,T] -> [bool]` | Matching numeric less-than. |
| 7 | `equal` | 1 | `[value,value] -> [bool]` | Equality. |
| 8 | `jumpIfFalse pc` | 2 | `[bool] -> []` | Jump to an instruction boundary. |
| 9 | `returnValue` | 1 | `[T] -> []` | Return after signature validation. |
| 10 | `greaterThanOrEqual` | 1 | `[T,T] -> [bool]` | Matching numeric comparison. |
| 11 | `jump pc` | 2 | unchanged | Unconditional jump to an instruction boundary. |
| 12 | `indexValue` | 1 | `[List,int]` or `[Map,String] -> [T]` | Bounded indexing/lookup. |
| 13 | `makeList count` | 2 | `[T…] -> [List<T>]` | Construct a validated list literal. |
| 14 | `makeMap count` | 2 | `[String,T…] -> [Map<String,T>]` | Construct a validated map literal. |
| 15 | `loadReceiver slot` | 2 | `[] -> [T]` | Read one descriptor-selected receiver property through the host adapter and validate it as `T`. |
| 16 | `loadLocal slot` | 2 | `[] -> [T]` | Load a definitely initialized typed lexical slot. |
| 17 | `storeLocal slot` | 2 | `[T] -> []` | Store a schema-compatible value and mark the slot initialized. |
| 18 | `pop` | 1 | `[T] -> []` | Discard an expression result. |
| 19 | `lessThanOrEqual` | 1 | `[T,T] -> [bool]` | Matching numeric comparison. |
| 20 | `greaterThan` | 1 | `[T,T] -> [bool]` | Matching numeric comparison. |
| 21 | `indexSet` | 1 | `[collection,index,T] -> []` | Mutate an invocation-local List element or String-keyed Map entry. |
| 22 | `collectionLength` | 1 | `[collection] -> [int]` | Length of List, Set, Map, or String. |
| 23 | `collectionContains` | 1 | `[collection,T] -> [bool]` | List/Set membership, Map key lookup, or String substring test. |
| 24 | `collectionAdd` | 1 | `[List|Set,T] -> []` | Bounded invocation-local addition. |
| 25 | `makeSet count` | 2 | `[T…] -> [Set<T>]` | Construct a validated Set literal. |
| 26 | `iterationValue` | 1 | `[List|Set,int] -> [T]` | Indexed lowering primitive for bounded for-in loops. |
| 27 | `mapKeys` | 1 | `[Map<String,T>] -> [Set<String>]` | Snapshot keys for the explicitly supported Map.keys iteration path. |
| 28 | `enterTry region` | 2 | unchanged (must be empty) | Push the dense handler region in `try` phase. |
| 29 | `completeTry region` | 2 | unchanged (must be empty) | Complete normal try flow through `finally` or `afterPc`. |
| 30 | `completeCatch region` | 2 | unchanged (must be empty) | Complete catch flow through `finally` or `afterPc`. |
| 31 | `completeFinally region` | 2 | unchanged (must be empty) | Resume the pending normal/return/throw completion. |
| 32 | `throwValue` | 1 | `[non-null E0 value] -> []` | Begin bounded guest exception unwinding. |
| 33 | `rethrowValue` | 1 | unchanged (must be empty) | Re-raise the active catch's original guest throw and trace. |
| 34 | `callAsyncCapability capability,argc` | 3 | `[args…] -> [pending<T>]` | Invoke one exact registered async capability; the opaque pending token is runtime-owned. |
| 35 | `awaitValue point` | 2 | `[pending<T>] -> suspend; [T] on resume` | Save the verified frame and resume only from the declared static point. |
| 36 | `callSyncCapability capability,argc` | 3 | `[args…] -> [T]` | Invoke one exact cheap synchronous capability; I/O and Future results are rejected. |

Validation rejects unknown/truncated opcodes, invalid argument/constant indices,
jumps that are not instruction boundaries, inconsistent control-flow stack states,
underflow, operand-type errors, invalid local slots, reads not definitely initialized
on every incoming edge, excessive stack depth, and reachable fallthrough.
Execution additionally enforces a 10,000-instruction budget and repeats argument,
operand, collection, and return checks. Loading failures and execution runtime
faults clear the active patch so the original AOT body remains the safe fallback;
intentional guest throws follow the distinct exception outcome specified below.

## Exception regions and failure boundary

Every version-5 handler has exactly these fields: `id`, `tryStart`, `tryEnd`,
`catchStart`, `catchEnd`, `finallyStart`, `finallyEnd`, and `afterPc`. Catch and
finally start/end pairs are jointly null or jointly present. IDs are dense from
zero. Try, catch, and finally use half-open instruction-boundary ranges; their
matching enter/completion opcodes and dense ID operands are mandatory. Regions
must be disjoint or properly nested, never partially overlap. Direct jumps may
not cross a handler-section boundary, which deliberately rejects break/continue
cleanup paths that the current completion model does not encode. Unknown fields,
bad ranges, missing transitions, illegal entry, excessive regions, non-empty
boundary stacks, and rethrow outside a catch fail activation.

An invocation-local handler frame is in `try`, `catch`, or `finally` phase and can
hold one pending normal, return, or throw completion. `finally` is entered at most
once. A return or throw within `finally` discards and replaces its pending
completion before unwinding outer regions. A rethrow retains the original
`E0GuestTrace(functionId, pc)` rather than manufacturing a second source location.

Guest `throw` currently accepts only statically non-null values from the bounded
E0 universe. Catch selection is catch-all only. A catch binding may be declared
and ignored, but reading it is rejected; stack-trace bindings, typed/user-defined
catches, multiple catch clauses, and break/continue crossing a region are not
supported. Full Dart VM stack frames are not claimed.

`E0PatchRuntime.invoke` returns exactly one of success, uncaught guest throw, or
runtime fault. An uncaught guest throw stays active and crosses the generated AOT
guard through `Error.throwWithStackTrace`. Verifier errors, schema failures,
instruction/stack budgets, and internal invariants are uncatchable runtime faults:
they deactivate the patch and fall back to AOT. A descriptor-selected receiver
read that throws any ordinary non-null Dart object is translated at that explicit
bridge to a bounded `E0HostFailure` and is catchable by guest code. The wrapper
contains only stable boundary/code identifiers, a bounded runtime-kind string, and
a bounded message; the raw thrown object never enters interpreted state.
`E0RuntimeFault`, `StackOverflowError`, and `OutOfMemoryError` are explicitly
re-thrown and are not translated into guest values.

Predictable collection language failures use the same guest-transfer path with
stable boundary/code metadata: List index read/write range failures, iteration
index range failures, and missing String-keyed Map reads. They are catchable and an
uncaught failure does not deactivate the patch. Collection size limits, schema
violations, malformed opcodes, stack faults, and instruction budgets remain
uncatchable runtime faults. For `Map<String, T>` with non-null `T`, a missing key
throws the bounded guest failure because that patch signature cannot represent
Dart's nullable `T?` result. An explicitly nullable `Map<String, T?>` read returns
null for a missing key. This bounded schema rule must not be inferred as complete
Dart Map type-promotion or nullability behavior.

Task 10 assigns local slots deterministically in lexical encounter order (including
compiler-private loop/switch slots), rejects inferred local types, and lowers `if / else`,
nested conditions, scalar constant `switch`, declaration-based C-style `for`, `while`,
early return, and typed `for-in` over List, Set, and `map.keys` to verified jumps. The
single execution instruction budget covers all loop iterations. List/Map indexing and
assignment, length, membership, addition, iteration, and literal construction are the
supported collection surface. Every non-empty switch member must terminate with an
explicit `break` or `return`; the compiler never inserts an implicit break.

There is no general iterator IR. Expression-initialized C-style loops, arbitrary
Iterable values, pattern/destructuring switch cases, and guarded cases fail patch
compilation. `map`, `where`, `fold`, and `forEach` fail with a closure-specific
diagnostic. Closure functions, captures, and nested closure scopes remain
unsupported. Task 11's bounded exception subset is specified above; it is not
arbitrary Dart exception-object support.

## Async continuations and capability boundary

An async function signature is encoded as the ordinary parameter schemas plus
`async: true`; its return schema is the element `T` of `Future<T>`. The supported
element universe is the same bounded host value universe as synchronous calls.
`Future<dynamic>` and arbitrary `Future<Result>` objects are rejected. The proof
includes `Future<int>` and `Future<Map<String, dynamic>>`; the latter still means
recursively validated E0 values, not arbitrary objects.

Every downloaded program declares an exact ordered capability table. Each runtime
entry has a contract version/digest, stable lowercase dotted ID, positive version,
exact argument/result schemas, execution kind, bounded resource labels,
`detachOnly` cancellation, and a policy containing timeout, maximum encoded output bytes, and
side-effect classification (`none`, `idempotent`, or `exactlyOnce`). Source name
exists only in the release-manifest compiler route and is excluded from patch
bytes, equality, and the contract digest.

Release-manifest version 6 contains the app's exact capability allowlist. The
compiler resolves only names in that allowlist. Activation then requires the
patch requirement to match one configure-once `E0CapabilityAuthority` combining
the shipped allowlist and immutable host registry. `installBytes` accepts no
independent capability map. Duplicate IDs,
duplicate source names, missing registrations, or any version/schema/kind/
resource/policy mismatch reject the whole candidate before slot publication.
Registering an additional adapter cannot expand a shipped release's allowlist.
There is no descriptor discovery, reflection, raw platform channel, FFI, native
symbol, plugin invocation, or arbitrary Dart call path.

Application construction enforces the same positive version, 16-argument,
supported-schema, policy-bound, ID/resource grammar, and cancellation rules as
wire decode. The verifier independently requires the async opcode to reference
an `async` descriptor and the sync opcode to reference a `sync` descriptor; a
forged kind/opcode pair rejects before activation. Compiler-only source renames
preserve both equality and hash identity.

Version 8 also has a dedicated typed sync opcode for cheap, non-I/O clock/log
adapters in synchronous programs. Async programs reject that opcode during
verification because the continuation executor does not implement it. Sync
arguments/results/output are validated; fatal failure after handler
entry disables the slot and propagates, preventing AOT rerun after side effects.
The deterministic contract fixtures cover logging, clock.now, storage read/write,
navigation.push, and an HTTP GET abstraction. Tests supply in-memory fake handlers;
the runtime performs no network, filesystem, logging, clock, or navigation action.
Arguments and results cross the existing recursive value codec. Capability timeout
wraps the host Future. Timeout and output overflow become stable `deadlineExceeded`
and `resourceExhausted` guest failures. Other ordinary adapter errors become a
redacted `hostFailure`; runtime type, exception text, paths, URLs, and credentials
do not cross the boundary. Cooperative/abortable cancellation and per-capability
concurrency limits are not implemented and non-`detachOnly` contracts reject.
Ordinary receiver-adapter errors use the same fixed-detail rule
(`receiverFailure`/`boundaryFailure`) and never expose `runtimeType` or
`toString`. Receiver reads are translated only around the host getter itself;
schema conversion occurs outside that catch, so a wrong getter value is an
uncatchable runtime contract fault that disables the slot.

Each await point records a dense ID, await PC, exact next-instruction resume PC,
result schema, and active handler depth. Decode rejects missing/unknown fields,
non-boundary PCs, reused or unused points, unused capability metadata, stack
shapes other than one pending token, and handler-depth disagreement. Every async
program must contain at least one await in this slice. Await nested under another
operand is rejected when it would retain an undeclared stack prefix.

`E0AsyncInterpreter` creates one heap continuation containing the immutable
program object and installation generation, PC, typed operand stack, typed locals,
v5 handler frames and pending completion, invocation zone, remaining total
instruction budget, relative deadline, suspension/resume counters, and an exactly-once
pending/terminal state. One invocation may have only one outstanding Future. The
process limit is 64 active continuations, the default total instruction budget is
10,000, the default maximum resume/suspension count is 32, and the default deadline
is five seconds. These limits are host inputs and are never read from patch bytes.

Capability callbacks and subsequent interpreter turns run in the invocation zone.
Immediate Futures are not resumed inline specially. A delayed or never-completing
Future never blocks the isolate. A capability callback captures only a detachable
resume token. The deadline settles the outer Future, detaches that token, and clears
the program, argument copy, receiver adapter, copy memo, stack entries, local values,
handler frames, and runtime-fault callback from the continuation. Dart Future has no
general cancellation, so the underlying host operation may continue unless a future
capability contract adds cancellation. A later callback observes the detached token,
increments the rejected-resume diagnostic, and cannot recover state or execute code.

An awaited host error becomes bounded, redacted `E0HostFailure` guest data and is dispatched
through the saved catch/finally frames. An uncaught guest error completes the AOT-
visible Future with the bounded payload and synthetic trace. Wrong resumed schemas,
bad continuation shape, instruction/invocation-deadline exhaustion, or an interpreter invariant are
uncatchable runtime faults. Once a capability has started, such a fault completes
the Future with `E0RuntimeFault` and disables that exact currently installed slot;
the original AOT body is never rerun because that could duplicate side effects.
Initialization faults before a capability starts may return null from the generated
guard and select the original AOT body. `E0RuntimeFault`, `StackOverflowError`, and
`OutOfMemoryError` raised synchronously by a capability, delivered by its Future, or
raised during a resumed interpreter turn bypass guest catch frames, settle the outer
Future with the original fatal object, and disable the affected installed slot.

A suspended continuation pins its immutable program. Replacing or rolling back the
slot changes new calls only; an old pending invocation finishes against its old PC,
metadata, and pinned authority. Process restart discards continuations. A generated
installer may stage one local pending candidate before authority configuration;
reset clears it so it cannot cross lifecycle boundaries. Direct activation rejects
missing authority or bindings.

The closure spike remains explicitly negative. Function values, immutable capture
environments, mutable shared capture cells, nested functions, method tear-offs, and
closure APIs such as `map`, `where`, `fold`, and `forEach` have no v6 wire type or
opcode. Compiler regressions reject immutable capture, mutable capture, and nested
scope examples. Status is **NOT YET SUPPORTED**, not architecturally blocked: the
minimum future design still requires a pinned code reference plus typed environment,
and mutable captures require shared heap cells. No unrestricted `dynamic` call was
added to improve apparent coverage.
