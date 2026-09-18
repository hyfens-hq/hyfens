# Toolchain architecture

Status: Phase 1B implementation baseline.

The toolchain is a local adapter over the Phase 1A deep modules. Its external
interface is the command set; project discovery, graph normalization,
instrumentation planning, patchability analysis, and artifact handling remain
inside `cli/lib/src`.

```text
CLI commands
    ↓
HyfensToolchain
    ├── ProjectDiscovery
    ├── ProjectGraphLoader
    ├── SourceDiscoverer
    ├── InstrumentationPlanner
    ├── ReleaseRecord / ToolStore
    ├── Patchability analysis
    └── KeyStore + PatchFormatV1
```

## Project and graph inputs

The loader reads the root `pubspec.yaml`, `pubspec.lock`, and
`.dart_tool/package_config.json`. It records package name/version/source,
normalized relative path, package URI root, plugin/native presence, and a
canonical graph fingerprint. Absolute checkout paths are excluded from graph
identity material.

Hosted, git, and SDK package source trees are understood by the graph model but
are not scanned by default. Application Dart is selected by default; local path
packages are selected by the initial configuration policy; other dependencies
require explicit package selection.

## Release baseline

`tool release <target>` computes source, graph, configuration, tool/runtime,
Flutter/Dart, target, architecture, and build-mode inputs. The release ID uses
the canonical Patch Format identity function with an explicit target such as
`android-arm64-release`. The baseline stores function IDs/signatures, source
fingerprints, package graph records, source classifications, instrumentation
decisions, and build metadata. It does not store source snapshots or private
keys.

The normal build path copies the project to a temporary overlay, rewrites only
the selected generated copies, copies selected external local packages into an
isolated overlay, patches the overlay package configuration for those roots,
injects the tool-owned runtime package graph, and invokes
`flutter build apk|ipa --release --no-pub`. The original checkout is never
transformed in place. The overlay is deleted after the build; baseline metadata
remains local.

If the project does not already resolve `instrumentation_e0`, the CLI adds the
tool-shipped runtime package only to the temporary overlay package
configuration. It does not edit `pubspec.yaml` or the developer checkout.

For a normal release build, the overlay also imports
`hyfens_flutter_integration` into the existing entrypoint. The generated call
contains only release-owned function/signature/receiver tables, the trusted
public key, and the configured local patch endpoint. It starts the E1 lifecycle
adapter asynchronously, so a missing development server leaves the native AOT
base active. The integration uses a bounded local poll and the E1 durable
state machine; it is not a general Flutter API bridge.

When the normal build produces an APK or IPA, the artifact is copied into the
immutable release directory under `artifacts/` before the temporary build
staging directory is removed. Metadata-only baselines deliberately have no
release binary.

`--metadata-only` intentionally skips Flutter and is used by deterministic CLI
tests. It must not be described as a release build.

## Patch analysis and artifact handoff

The analyzer compares source units and semantic fingerprints against one
release. Changed selected functions must remain in the baseline with identical
signature metadata. New/removed functions, native/build-input changes,
dependency graph changes, changed tool policy, and unsupported declarations
fail closed.

The first toolchain handoff preserves the verified E0 container bytes in a
non-critical Patch Format v1 extension section (type 9, bridge version 1). The
canonical v1 identity/function/capability/constant/instruction/signature
sections are still produced, digested, and signed by `PatchFormatV1`; the
extension is explicitly not an encoding change to v1. The Phase 1B artifact
tests verify structure, digest, signature, exact release binding, and the
bridge payload. The current package runtime does not yet activate this bridge
section; the Phase 1B E1 lifecycle adapter now verifies and activates it through
the bounded E0 batch-install seam.

Source records also retain declaration-level semantic fingerprints. They are
not source snapshots: they allow the analyzer to distinguish a supported
function edit from an unchanged unsupported declaration in the same file and
to fail closed when an unsupported declaration changes.

`tool serve` is a loopback-only development adapter. It serves only
self-verified artifacts for an exact release and returns `NO_UPDATE`,
`PATCH_AVAILABLE`, or `INCOMPATIBLE` from a small local HTTP contract. It is
not a hosted update service.

## Safety properties

- release baselines are immutable once written;
- patch sequence is committed after write and self-verification;
- ambiguous release selection fails;
- unsupported mixed changes cannot produce a partial patch;
- inspection never executes a patch;
- signing material is explicit and separate from release artifacts;
- diagnostic paths are project-relative or logical package URIs.

## Lifecycle controls

The generated bootstrap resolves lifecycle storage below the platform's
private application-support directory and passes that release-scoped directory
to E1. It does not use the host process' system-temp directory. E1 persists
two checksummed state copies with atomic temporary-file/rename updates and
retains the accepted patch high-water across restart and base rollback.

`tool rollback --release <id> --to base` signs a separate canonical rollback
control bound to the exact current high-water. The development server exposes
that control at `/v1/control`; the runtime verifies the embedded trusted key,
application/release identity, and high-water before clearing the active patch.
The control is not a Patch Format v1 extension and does not change the v1
protocol. Prior-patch selection is deliberately not exposed.

`tool cleanup` has only explicitly confirmed `builds` and `patches` scopes.
It refuses symlinks and protected scopes and preserves release baselines,
signing keys, source, rollback journals, sequence state, and evidence.
