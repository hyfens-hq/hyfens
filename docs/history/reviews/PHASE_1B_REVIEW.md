# Final Phase 1B Review

Status: complete for the bounded Phase 1B scope. Phase 1C has not started.
Architecture B, Patch Format v1, and capability contract v1 remain unchanged.
This report records the final gate-closure evidence from 2026-08-22; the
historical maintainer checkpoint is preserved below unchanged.

## 1. Recommendation

PROCEED TO PHASE 1C WITH CONDITIONS

Conditions for the next maintainer-approved milestone:

- retain support claims at Flutter 3.47.x/Dart 3.13.x until an adjacent SDK
  family is installed and tested in isolation;
- keep delivery local/development-only; no production transport, hosted
  service, or store-compliance claim follows from this report;
- treat the Android path-provider pin and limited startup/memory measurements
  as explicit Phase 1C hardening inputs;
- obtain maintainer approval before starting any Phase 1C work.

No fundamental Architecture B blocker was found.

## 2. Developer workflow

The supported local workflow is:

```bash
dart run cli/bin/tool.dart doctor
dart run cli/bin/tool.dart init
dart run cli/bin/tool.dart keys generate
dart run cli/bin/tool.dart release android
dart run cli/bin/tool.dart release ios

# modify supported ordinary Dart/Flutter source
dart run cli/bin/tool.dart analyze
dart run cli/bin/tool.dart analyze --json
dart run cli/bin/tool.dart patch
dart run cli/bin/tool.dart inspect .tool/patches/<release-id>/000001.patch
dart run cli/bin/tool.dart verify .tool/patches/<release-id>/000001.patch \
  --release <release-id>
```

The optional local device lifecycle is `tool serve --allow-lan` with an
explicit private-network endpoint. Base rollback is:

```bash
dart run cli/bin/tool.dart rollback --release <release-id> --to base
```

No source units, function IDs, slots, bytecode, capability manifests, manual
dispatch calls, PatchView, annotations, or Flutter SDK edits are required.

## 3. `tool init`

`tool init` detects the Flutter project, validates the tested toolchain family,
creates `tool.yaml` and `.tool/`, and reports any project-local integration
change. It does not rewrite source, patch a global SDK, or create a private
key. `tool keys generate` remains explicit. Release transformation occurs in a
temporary overlay; the checked-in fixture source and loopback configuration
were restored after device validation.

## 4. Source discovery

Application Dart, selected local path packages, package configuration, and
native/generated classifications are derived automatically from the project.
Flutter/Dart SDK source, generated/native-boundary source, and unselected
hosted/git dependency source remain excluded or fail closed by policy. Changed
excluded declarations are diagnosed rather than silently omitted.

## 5. Package/build graph

The tool normalizes `pubspec.yaml`, `pubspec.lock`, and
`.dart_tool/package_config.json` into a graph containing package name/version,
source type, logical path, pubspec fingerprint, plugin/native status, and lock
description. Absolute checkout paths are excluded from identity. Local path
packages are overlay-capable; hosted/git source is recorded but is not
automatically accepted as patchable. Generated Dart is conservative and stale
or changed generated units fail closed.

## 6. `tool release`

`tool release android|ios` discovers the graph, creates a non-destructive
overlay, transforms selected source, injects the runtime package graph and
generated bootstrap, computes baseline metadata, and invokes normal Flutter
release commands. The final clean automatic releases were:

| Target | Release | Tool/build evidence |
| --- | --- | --- |
| Android arm64 | `sha256:9fe4b8db7e998f34fde352c7df20ecdb88ccec2fbb02741e88c2a9b64f0dcb06` | Flutter build success, 33,716 ms, 46,778,869-byte APK |
| iOS arm64 development | `sha256:7ebea0f52812d3b1e1acbb56080000ffd4d6d66b686a94af0614bba0366cbc4b` | IPA export success, 48,005 ms, 6,633,476-byte IPA |

The baseline stores release/build/source/function/package/instrumentation
metadata and the native artifact. It does not store source snapshots or
private keys.

## 7. Release identity

Identity is release-, target-, architecture-, tool-, runtime-, Flutter-,
Dart-, configuration-, graph-, source-, and signing-key-bound. It excludes
checkout paths and volatile timestamps. Android and iOS release IDs remain
distinct, and exact toolchain mismatches are rejected. The tool version was
bumped to `0.1.0-phase1b.8` after the storage/overlay changes, so the final
baselines cannot be confused with earlier artifacts.

## 8. Patchability analysis

The analyzer emits `PATCHABLE`, `UNSUPPORTED`, `STORE_RELEASE_REQUIRED`,
`NO_EFFECT`, or `UNKNOWN`. It compares changed functions and declarations to
one exact release and fails closed for mixed supported/unsupported behavior;
it never emits a partial patch while an unsafe changed behavior remains.

## 9. `tool patch`

The command resolves the exact baseline, discovers current source, classifies
changes, compiles changed functions, derives function/capability metadata,
encodes Patch Format v1, signs, decodes/verifies, and writes the next sequence
only after successful verification. The physical Android validation generated
a 1,798-byte sequence-1 artifact automatically; the physical iOS validation
generated the same-size sequence-1 artifact for its exact release.

## 10. Diagnostics

Stable `T1xxx`/`T16xx`, `P2xxx`, `N3xxx`, `S4xxx`, `R5xxx`, rollback `R6001`–
`R6007`, and cleanup `C7001`–`C7006` diagnostics are documented. Human output
contains project-relative source locations and actions; `--json` exposes
stable result, release, classification, location, and diagnostic fields.

## 11. Patch Format v1

CLI artifacts conform to the existing canonical Patch Format v1 sections,
bounds, digest/signature boundary, identity rules, function compatibility, and
runtime compatibility checks. The existing non-critical E0 bridge extension
is used by the Phase 1B handoff; no required field, canonical ordering,
semantic rule, or version was changed. Rollback control is a separate signed
canonical lifecycle message and is not a mutation of Patch Format v1.

## 12. Capability contract v1

Generated patches declare the exact release-owned host capabilities they use.
The runtime/compiler seam continues to reject undeclared capabilities, wrong
versions/schemas, forbidden capabilities, and sync/async mismatches. The
ordinary physical fixture patch required zero capabilities. No arbitrary host
reflection or API enumeration was added.

## 13. Signing

Ed25519 key generation, public-key inspection, private/public key pairing,
canonical signing, self-verification, trusted-key matching, and explicit
private-key handling are implemented. The iOS gate used existing local
development material for team `CYT7A4VAZ3`; no certificate/profile was
created, revoked, or changed organization-wide. The private key is absent from
release metadata, patch artifacts, and generated application code.

## 14. Android physical evidence

The durable-storage/rollback run used a Redmi Note 10 Lite, Android 16/API 36,
arm64, serial `192.168.50.135:39083`. Release
`sha256:585df840b3722d865ebde523025deb72b5f3dc1e9878d920dd97bb65d10c6255`
installed once; its APK hash was
`sha256:fdeed799b6c2f5f0d57dd39abb1c1582d6a5ca6afa7b5be5430a4cfc62f63e34`.
The run changed `displayCount` from the baseline result `42` to a patched
result `85` without reinstalling, observed `pendingHealth` then `healthy`,
terminated/restarted the process, and observed the signed patch persist.

`tool rollback --to base` produced a signed control with high-water sequence
1 retained. The app returned to base result `42`, persisted that state across
restart, and did not receive sequence 1 again. Runtime/CLI tests cover wrong
release, invalid signature, corrupt bytes, stale sequence, and wrong
high-water rejection; no unsafe patch was activated.

The earlier validated Android release
`sha256:a68c12eb2f28e6c8654983a0a1dbff88671e7aa6ef7ca7e56babbe684d1f615b`
remains preserved as historical evidence.

## 15. iOS physical evidence

The automatic run used a physical iPhone XR, UDID
`00008020-001528860E03002E`, iOS 18.7.9, Xcode 26.6 Build 17F113, and team
`CYT7A4VAZ3`. The project-local fixture correction replaced stale team
`9BRXC9W8MN`; no organization-wide signing configuration was changed. The
development IPA was installed once using the actual bundle ID
`dev.hyfens.hyfensToolchainApp`.

Release `sha256:f77dd118219e163098c966a1048ed0ccc6c9b087390019de3a86c4eef3e9abe5`
passed automatic `tool release ios`, source discovery, JSON analysis, patch
generation, inspection, and exact-release verification. The 1,798-byte patch
entered `pendingHealth`, reached `healthy`, survived process termination and
restart, then accepted signed base rollback and persisted `BASE` after another
restart. Its IPA was 6,633,441 bytes. The clean reproducibility release is
recorded in section 6. This is device/toolchain evidence only; no App Store
approval or production-signing claim is made.

## 16. Performance

The five-sample host CLI harness on macOS 26.6.2 arm64 reported median/p95
milliseconds of: doctor/discovery 8,887.724/9,807.798; analyze
8,904.064/11,002.767; patch 8,320.103/9,513.282; inspect
6,164.198/6,801.554; verify 6,201.025/6,600.787. The harness also records
metadata-only release timing, source/function counts, and artifact sizes.

The release comparison was:

| Target | Stock | Instrumented | Size growth |
| --- | ---: | ---: | ---: |
| Android APK | 44,103,100 bytes / 33.84 s wall | 46,778,869 bytes / 33.716 s recorded Flutter stage | 6.07% |
| iOS development IPA | 6,197,403 bytes / 43.65 s wall | 6,633,476 bytes / 48.005 s recorded Flutter stage | 7.04% |

Stock was measured after scoped clean/package resolution. Cache and host
conditions were not a controlled laboratory comparison; the size result is
direct for this fixture, while timing is directional. Overlay, transformation,
baseline, and signing sub-timers are not yet exposed.

## 17. Startup and memory

One bounded Android sample from the installed instrumented release in durable
base state reported cold `am start -W` `TotalTime=489 ms` and `WaitTime=498 ms`;
`dumpsys meminfo` reported `TOTAL PSS=78,997 KiB` and `TOTAL RSS=179,984 KiB`.
The iOS run proved lifecycle persistence but did not capture an equivalent RSS
or first-frame counter. These are baseline samples, not stock-vs-instrumented
attribution.

## 18. Developer friction

The normal path is project-local initialization, explicit local key generation,
normal platform signing, and ordinary source edits. Physical local delivery
requires the expected network permission/endpoint and explicit LAN server
opt-in. The iOS fixture needed a stale project-local team correction; a real
project still needs its own normal signing setup. No experiment source units,
manual function metadata, annotations, call-site rewrites, or SDK changes are
needed.

## 19. Unsupported changes

New/removed functions or source units, incompatible signatures, unsupported
Dart/Flutter constructs, changed generated source, arbitrary reflection,
unselected hosted/git source, native implementation/build inputs, and
unclassifiable behavior fail closed or require a normal release. Broader
generated-code and language coverage remain intentionally conservative.

## 20. Native/store-release-required changes

The analyzer classifies Android/iOS manifests, entitlements, plist/project
files, Gradle/Pod inputs, native source, native plugin changes, FFI/binding
changes, and resolved graph changes as `STORE_RELEASE_REQUIRED` where they
affect the release. Existing compiled host capabilities remain callable only
through the closed capability boundary. This is patchability analysis, not
store-compliance validation.

## 21. Security findings and remaining risks

The tool uses bounded non-symlink traversal, normalized paths, immutable
baselines, atomic writes, dual-copy checksummed lifecycle state, exact release
binding, canonical Patch Format v1 verification, Ed25519 signatures, signed
rollback controls, retained high-water, and protected cleanup scopes. The
local server has no authentication, development keys remain an operator
responsibility, and the filesystem/device is not protected against a rooted or
fully compromised attacker. Crash/power-loss fault injection, fuzzing,
resource-budget expansion, key rotation/revocation, adjacent SDK validation,
and controlled iOS performance attribution remain open risks.

There is no unresolved external blocker for the current fixture's Phase 1B
workflow. The prior iOS `T1603` is preserved as historical evidence and was
closed by the bounded project-local signing correction. Adjacent Flutter/Dart
families are `NOT TESTED`, not silently supported.

## 22. Phase 1C proposal

After maintainer approval, Phase 1C should harden only the runtime boundary:

- crash/power-loss fault injection for state copies, staging, activation, and
  rollback;
- resource budgets and error isolation under adversarial signed patches;
- parser/verifier/interpreter/lifecycle fuzzing;
- source-mapped runtime diagnostics;
- key rotation/revocation and recovery-state review;
- controlled physical startup/memory/dispatch measurements;
- adjacent Flutter/Dart compatibility validation in isolated SDK environments.

These are proposals only. Phase 1C was not started.

---

# Historical Phase 1B Review Checkpoint

Status: not complete. This is the maintainer-gate report for the current
Phase 1B implementation; Phase 1C has not started.

## 1. Recommendation

CONTINUE PHASE 1B

The local toolchain is coherent through automatic Android release, analysis,
signed patch generation, local delivery, activation, health confirmation, and
restart persistence. Automatic physical iOS validation is still blocked by the
local Xcode account/provisioning setup. Durable app-support storage and a
developer-facing rollback boundary also remain open.

## 2. Developer workflow

The implemented local workflow is:

```bash
dart run cli/bin/tool.dart doctor
dart run cli/bin/tool.dart init
dart run cli/bin/tool.dart keys generate
dart run cli/bin/tool.dart release android
dart run cli/bin/tool.dart release ios

# edit supported ordinary Dart/Flutter source
dart run cli/bin/tool.dart analyze
dart run cli/bin/tool.dart patch
dart run cli/bin/tool.dart inspect .tool/patches/<release-id>/000001.patch
dart run cli/bin/tool.dart verify .tool/patches/<release-id>/000001.patch
```

No source units, function IDs, slots, bytecode, patch headers, or manual
dispatch calls are required.

## 3. `tool init`

`tool init` validates the Flutter/Dart family, creates `tool.yaml` and `.tool/`
metadata, and reports the files it would change. It does not modify the
Flutter SDK, rewrite application source, add annotations, or generate a
private key. `--dry-run` is implemented. A private key is generated only by
the explicit `tool keys generate` command.

## 4. Source discovery

The CLI discovers application `lib/**`, selected local path packages, package
configuration, generated Dart naming patterns, plugin/native boundaries, and
SDK package categories. Flutter/Dart SDK, generated, native-boundary, and
unselected hosted/git dependency source is excluded by default. Every source
unit has a package-qualified logical URI and a diagnostic selection reason.

## 5. Package/build graph

`pubspec.yaml`, `pubspec.lock`, and `.dart_tool/package_config.json` are
normalized into a deterministic graph containing package name, version, source
type, logical root, package URI, pubspec fingerprint, plugin status, native
status, and lock description. Checkout-specific absolute paths are excluded
from graph identity. Path packages can be copied into the temporary build
overlay; hosted and git source is recorded but is not automatically accepted
as patchable.

## 6. `tool release`

`tool release android|ios` discovers the graph, computes source/configuration/
native/toolchain identity, builds a project copy in an ephemeral overlay,
transforms selected source, injects the tool runtime package graph and
generated bootstrap into the existing entrypoint, and invokes normal
`flutter build apk|ipa --release --no-pub`. The checkout remains unchanged.

The baseline stores release metadata, function/signature records, source
fingerprints and declaration fingerprints, package graph, instrumentation
decisions, build metadata, and the built artifact. It does not store source
snapshots or private keys.

## 7. Release identity

Identity includes application, source, dependency graph, configuration, native
inputs, Flutter/Dart versions, tool/runtime/format versions, signing key ID,
update endpoint, target platform, architecture, and build mode. It excludes
checkout paths and volatile timestamps. Tests cover repeated builds, path
normalization, architecture separation, configuration changes, and release
selection. The physical Android generated-bootstrap release was:

```text
sha256:a68c12eb2f28e6c8654983a0a1dbff88671e7aa6ef7ca7e56babbe684d1f615b
```

## 8. Patchability analysis

The analyzer reports `PATCHABLE`, `UNSUPPORTED`, `STORE_RELEASE_REQUIRED`,
`NO_EFFECT`, or `UNKNOWN`. It compares source units and declaration/function
records against one exact release. Mixed supported/unsupported changes fail
closed; supported functions are not emitted as a partial patch when another
changed behavior is unsafe or unknown.

## 9. `tool patch`

`tool patch` selects an exact baseline, discovers current source, analyzes
changes, compiles changed functions through the compiler facade, validates
function/signature/receiver tables, derives required host contracts, encodes
Patch Format v1, signs, decodes, verifies, and only then writes the next local
sequence artifact. The generated Android test patch was 1,798 bytes and had
sequence 1.

## 10. Diagnostics

Stable diagnostic families are implemented for project/toolchain (`T1xxx`),
configuration/graph (`T12xx`/`T13xx`), release/build (`T16xx`), patchability
(`P2xxx`), native boundaries (`N3xxx`), signing (`S4xxx`), and release/artifact
compatibility (`R5xxx`). Human output includes source paths and, for selected
functions, line/column locations. `--json` exposes stable classifications,
release identity, function IDs, locations, diagnostics, and required action.

## 11. Patch Format v1

CLI artifacts use the existing normative Patch Format v1 canonical encoding.
Digest/signature, bounds, duplicate/unknown-critical field rejection,
function-table compatibility, and exact release binding are verified in the
CLI and package conformance tests. The E0 bridge is carried in the existing
non-critical extension section; Patch Format v1 was not semantically or
canonically changed.

## 12. Capability contract v1

The compiler/runtime seam carries release-owned capability and receiver tables.
The CLI rejects compiled patches that require undeclared capabilities or widget
factories. The generated ordinary-function patch declared zero capabilities;
capability schema/policy enforcement remains inherited from the Phase 1A
contract and tests.

## 13. Signing

Local Ed25519 key generation, public-key inspection, canonical signing,
self-verification, trusted-key matching, and private-key overwrite/permission
guards are implemented. `tool init` never generates a key. The checkout-local
default private-key path is ignored but warns; an explicit external path is
supported. Private key bytes are not placed in release metadata, patches, or
generated application bootstrap code.

## 14. Android

The clean ordinary Flutter fixture built an automatic release APK on Flutter
3.47.0/Dart 3.13.0 in 28,777 ms; the APK was approximately 44 MiB. It was
installed once on the physical arm64 Android device. An ordinary source edit
from `displayCount(value) => value` to `value + 42` generated a signed Patch
Format v1 artifact, which the generated bootstrap received from the local
development server, activated, health-confirmed, and retained after process
restart. The fixture used an explicit Android `INTERNET` permission and a
temporary private-LAN endpoint for delivery; these were recorded integration
inputs, not hidden source mutations.

## 15. iOS

The generated-bootstrap iOS release reached the Xcode archive stage but did
not export an IPA. Xcode reported no account for team `9BRXC9W8MN` and no
provisioning profile for `dev.hyfens.hyfensToolchainApp`; the CLI returned
`T1603` and committed no incomplete baseline. Earlier Phase 0B physical iOS
evidence remains preserved, but it used the research fixture and is not claimed
as automatic Phase 1B toolchain evidence.

## 16. Performance

The current evidence records Android overlay release time and generated patch
size. CLI test coverage exercises deterministic analysis, compilation,
encoding, signing, and verification, but a repeatable Phase 1B Android/iOS
analysis-time, patch-time, startup, memory, and binary-growth report has not
yet been completed. Phase 0 dispatch/interpreter benchmarks remain preserved.

## 17. Developer friction

The normal integration surface is `tool init` plus explicit local key
generation and ordinary Flutter release signing. No per-function annotations,
rewritten call sites, PatchView, or SDK changes are required. Device delivery
currently requires normal network permission/configuration and either ADB
reverse or an explicitly reviewed private-LAN endpoint. The generated runtime
state currently uses system-temp storage, which is a known hardening gap.

## 18. Unsupported changes

New/removed source units or functions, incompatible signatures, unsupported
Dart declarations, unsupported widget/host constructs, changed generated
units, unselected hosted/git dependencies, arbitrary reflection, raw native
boundaries, and changes that cannot be classified are rejected or require a
normal release. The policy prefers false negatives to unsafe partial patches.

## 19. Native/store-release-required changes

The native snapshot covers Android, iOS, desktop platform inputs, manifests,
Gradle/Pod files, entitlements, plist/project files, native source, and native
package implementation files. Changes to these inputs, resolved package graph,
tool policy, or Flutter/Dart toolchain are reported as
`STORE_RELEASE_REQUIRED`; this is patchability analysis, not store-compliance
validation.

## 20. Security findings

The tool uses bounded non-symlink traversal, normalized logical paths, atomic
metadata writes, immutable release directories, exact release checks,
canonical Patch Format v1 verification, Ed25519 signing, explicit LAN opt-in,
and fail-closed mixed-change handling. The local server has no authentication,
the filesystem is not trusted against a local attacker, and system-temp
lifecycle state is not yet durable app-support state.

## 21. Remaining risks

- automatic physical iOS release/activation is unvalidated until local signing
  credentials and provisioning are available;
- runtime lifecycle state needs platform app-support storage and a focused
  crash/power-loss review;
- user-facing rollback/cleanup semantics need to be exposed without weakening
  anti-replay/high-water rules;
- hosted/git dependency source availability and broader generated-source
  policy remain conservative;
- performance and Flutter-version coverage are still narrow.

No evidence has exposed a fundamental Architecture B blocker.

## 22. Phase 1C proposal

After the remaining Phase 1B gates and maintainer approval, Phase 1C should
focus only on runtime hardening: durable crash-safe storage, atomic activation
fault injection, resource-budget enforcement, malformed-input fuzzing,
source-map/error isolation, and formal key/replay recovery tests. This proposal
is not execution of Phase 1C.
