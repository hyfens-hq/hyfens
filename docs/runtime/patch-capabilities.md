# Flutter patch capabilities

This page describes the bounded Flutter/Dart patch ABI shipped by the current
public CLI. A patch is an exact, signed update to code already represented by
the installed base release; it is not an asset, native-code, or engine update.
The `hyfens analyze` result is authoritative for one project and release.

## Supported

The following changes are patchable when the declaration signature, receiver
schema, release identity, toolchain, resource snapshot, and native fingerprint
remain unchanged:

- ordinary, explicitly typed top-level and instance method bodies;
- `StatelessWidget` and ordinary `*State<T>` wrapper `build(BuildContext)`
  methods (including framework wrappers such as `ConsumerState<T>`) using the
  canonical unprefixed Flutter material/widgets import;
- bounded widget composition through the immutable host registry: `Text`,
  `Column`, `Row`, `Center`, `SizedBox`, and `ElevatedButton`;
- literal children and conditional widget expressions, plus host-owned
  zero-argument button callbacks within that registry; builder closures remain
  outside the promoted ABI;
- reads from the existing receiver schema, including unqualified reads of
  schema-safe fields/getters, typed `void` methods, ordinary synchronous
  callbacks, and stable-signature async method bodies using bounded
  `Future<T>.value`, `Future<void>.delayed` with `Duration.zero` or a constant
  duration of at most five minutes, registered async capabilities, and
  `WidgetsBinding.instance.endOfFrame`; and
- bounded zero-argument async button callbacks using the same async
  operations, where the host owns the callback and its returned `Future`; and
- Dart-managed business logic, routing decisions, animation calculations, and
  persistence/localization transformations when their resulting ABI stays in
  the supported value set.

`BuildContext` is an opaque host value. A patch may receive it as the normal
`build` parameter, but it cannot serialize it, retain it as patch state, or
perform arbitrary framework dispatch through it. Widget constructors remain
host-owned; the patch carries only a bounded description and host callback.

## P2001 audit

The old `P2001` output grouped compiler exclusions together. The following
audit records the rule families that produced it, the actual limitation and
safety concern, and whether the boundary is an implementation gap or a
deliberate fail-closed limit.

| Rule family | Limitation and safety concern | Classification | Status |
| --- | --- | --- | --- |
| `build(BuildContext)` and `State<T>` builds | The old ABI had no opaque framework parameter or bounded widget result. Passing arbitrary framework objects or dispatching through them would cross host ownership. | `MISSING_ABI_IMPLEMENTATION` | Resolved for canonical Flutter imports, ordinary `*State<T>` wrappers, schema-safe receiver reads, and the immutable widget registry. |
| `void` methods and host callbacks | There was no typed no-value schema or host-owned callback representation. Serializing a live callback would be unsafe. | `MISSING_ABI_IMPLEMENTATION` | Resolved for typed `void` and bounded zero-argument callbacks; callbacks remain non-serializable. |
| Ordinary `Future<T>` bodies | Async Dart needs a resumable interpreter state, while arbitrary async/generator closures need additional closure-state ABI. | `MISSING_ABI_IMPLEMENTATION` / `FUNDAMENTAL_RUNTIME_LIMIT` | Stable-signature async bodies and the bounded host-callback seam are supported; nested async/generator closures remain rejected. |
| Static, accessor, and operator targets | These do not provide the ordinary instance-call/receiver contract used by the patch table. Adding dispatch without a new contract could bypass receiver and rollback checks. | `FUNDAMENTAL_RUNTIME_LIMIT` | Deliberately retained as `NOT_YET_SUPPORTED`. |
| Generic methods/owners and deep type-shape changes | The current manifest does not carry reified generic owner shape, and live field/layout, constructor, superclass, or mixin changes can invalidate existing objects. | `MISSING_ABI_IMPLEMENTATION` / `FUNDAMENTAL_RUNTIME_LIMIT` | Generic/type-shape changes require a new base or remain unsupported. |
| Raw receiver access, receiver writes, and arbitrary receiver dispatch | Guest mutation or framework method dispatch could change live host state outside an atomic, verified receiver schema. | `FUNDAMENTAL_RUNTIME_LIMIT` | Explicit and safe unqualified reads of the existing receiver schema are supported; writes and arbitrary dispatch fail closed. |
| Nested, captured, async, or generator closures | Closure captures and compiler-generated state do not yet have a general stable serialized ABI. | `FUNDAMENTAL_RUNTIME_LIMIT` | Bounded synchronous closures and zero-argument async host callbacks are allowed only at the explicit widget seam; nested/capture-unsafe and generator closures remain closed. |
| Arbitrary widget constructors/framework objects | Flutter objects are host-owned and may contain engine, resource, or native state that cannot cross the patch container. | `NATIVE_BOUNDARY` | Only bounded descriptions for the shipped registry are accepted. |
| FFI, platform channels, reflection, plugins, and native configuration | These depend on native symbols, platform registries, or runtime configuration outside the Dart patch ABI. | `NATIVE_BOUNDARY` | A new base release is required. |
| Flutter SDK Material-icon scan (`F3010`) | Source traversal treated the Flutter SDK's icon catalog/lookup implementation as application evidence, producing an incomplete AST result. | `OVERLY_CONSERVATIVE_RULE` | Fixed by excluding the SDK from source-reference scanning; the built artifact is now authoritative. |
| Missing/ambiguous base artifact manifests (`F3011`) | Source references alone cannot prove tree-shaken glyph/font availability in the installed binary. | `RESOURCE_DEPENDENCY` | The release gate remains fail closed until actual manifest/font evidence is complete. |

## Explicit outcomes

`hyfens analyze` and `hyfens patch` use the same compatibility analyzer and
report one of these outcomes:

- `PATCHABLE` — the patch can be admitted under the existing base contract;
- `PATCHABLE_RESTART_REQUIRED` — ABI-compatible code whose live-object policy
  requires an application restart, without a native reinstall;
- `NEW_BASE_RELEASE` — the installed native/runtime/resource baseline must be
  rebuilt; or
- `NOT_YET_SUPPORTED` — the current interpreter or host ABI does not model the
  construct safely.

The current promoted Flutter paths are method-body and bounded widget/async
changes and do not silently require a restart. `analyze` performs the same
compiler/verifier preflight used by `patch`, so a known unsupported expression
is reported before patch compilation. The restart-required outcome is explicit
in the model so a future live-object-compatible path cannot be mistaken for an
in-place hot swap.

## New base release required

Create a new base release for any of the following:

- adding, removing, or changing fields in an existing receiver/state object;
- changing a constructor shape, generic declaration shape, superclass, mixin,
  or other type hierarchy relied on by live objects;
- adding or changing an asset or font, or referring to a Material icon glyph
  absent from the base artifact;
- changing a native plugin, platform configuration, manifest, bundle setting,
  or platform resource; or
- changing the Flutter/Dart engine or otherwise changing the recorded build
  toolchain.

The resource policy is intentionally conservative for Material icons: source
references already present in the baseline may be reused, while a newly
introduced glyph is not admitted merely because its name is known. The base
artifact must provide complete manifest/font evidence before a non-metadata
mobile release is patchable.

## Not yet supported

The current ABI still rejects static/accessor/operator targets, nested or
capture-unsafe async closures, generator closures, general `Stream`/Future
combinator graphs, arbitrary framework object calls,
FFI/platform-channel/reflection boundaries, and deep type-shape mutation.
Generated Dart is evaluated by its resulting ABI; generator brands are not
special-cased, and a generated unit is not promoted if its declaration shape
crosses an unsupported boundary. A zero-argument async callback is supported
only at the immutable host-owned button boundary described above.

## Resource evidence

The source resource snapshot records declared assets, fonts, native inputs, and
Material icon references. A real mobile base release additionally records
relative paths, sizes, and SHA-256 hashes for the actual Flutter build output's
asset manifest, font manifest, and Material icon font when Material design is
enabled. The evidence is stored without absolute machine paths.

Artifact evidence is `COMPLETE` only when the required files are present. An
absent or ambiguous manifest is a release gate (`F3011`), not permission to
guess that a resource is available. Asset/font bytes remain outside the patch
container, so mutation or addition remains `NEW_BASE_RELEASE`.

## Diagnostics and MCP

The terminal `hyfens analyze` output includes the typed outcome, reason code,
source location, and an actionable explanation. The read-only
`hyfens_analyze` MCP tool returns the same compatibility model and does not
return application source or patch bytecode. Release metadata, patch creation,
and MCP analysis all consume the same CLI analysis path.

For example:

```text
PATCHABLE
  lib/src/widget.dart:42:3
    method body changed

NEW_BASE_RELEASE
  lib/src/state.dart:18:3
    field|CounterState|count
    Why: This patch changes the field layout of an existing live receiver
    state object. Hyfens cannot safely update instances yet; create a new base
    release.
```

## Safety boundary

Patch admission still verifies the exact application identity, flavor,
entrypoint, environment, build fingerprint, function/signature/receiver
tables, immutable host capability registry, resource snapshot, and signed
patch metadata. A construct is rejected closed when those checks cannot prove
that old live objects and native resources remain compatible.
