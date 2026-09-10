# Shorebird architecture teardown

Research date: 2026-08-22

This document describes what can be established from Shorebird's public source and official documentation. It is an architecture teardown, not a policy endorsement or a restatement of product claims.

## Evidence labels

- **FACT** — directly supported by public source or official Shorebird documentation.
- **INFERENCE** — the public evidence supports the conclusion, but the complete implementation is not visible.
- **UNKNOWN** — the public material is insufficient to verify the claim.

Source links to public repositories are pinned to the revisions inspected:

- `shorebirdtech/shorebird`: [`98adec24391bf36ed3599ec8f448d48658bb5e78`](https://github.com/shorebirdtech/shorebird/tree/98adec24391bf36ed3599ec8f448d48658bb5e78)
- `shorebirdtech/updater`: [`1f85c4ab1ee5b540269b9859c75e1bffbb9050c7`](https://github.com/shorebirdtech/updater/tree/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7)
- `shorebirdtech/engine`: [`e4575c7403bd3453d04bfa03e01218e5a0bca0c6`](https://github.com/shorebirdtech/engine/tree/e4575c7403bd3453d04bfa03e01218e5a0bca0c6)
- `shorebirdtech/flutter`: [`91f8bd75076e9c740aa13cf67eb9ec1a093f68f5`](https://github.com/shorebirdtech/flutter/tree/91f8bd75076e9c740aa13cf67eb9ec1a093f68f5)
- `shorebirdtech/buildroot`: [`27a47046c61bc2b68451bc85cdde2a94ee2b24be`](https://github.com/shorebirdtech/buildroot/tree/27a47046c61bc2b68451bc85cdde2a94ee2b24be)

Official documentation is live rather than revision-pinned. Statements derived only from it should be rechecked if Shorebird changes the page.

## Executive finding

**FACT:** Shorebird offers transparent patchability for ordinary Dart application code without requiring special patch widgets. It achieves that by distributing its own Flutter toolchain and shipping a modified engine in the store release. It is not an application-level interpreter added to an otherwise stock Flutter app.

**FACT:** The execution model differs by platform:

- On Android, the patch build produces a new architecture-specific `libapp.so`; the delivered patch is a compressed binary diff against the release `libapp.so`. Once reconstructed, the new Dart AOT artifact runs natively in the modified engine. The diff is a delivery optimization, not function-level interpretation.
- On iOS, Shorebird uses compiler/linker/VM changes. Its linker reuses compatible functions from the signed release AOT program; functions that cannot be linked to release code execute in a Dart interpreter. This design is explicitly motivated by iOS executable-code restrictions.

**FACT:** The updater, CLI, Flutter-engine fork, Flutter-framework fork, and buildroot fork are public. The modified Dart SDK — the component containing the iOS interpreter/compiler work — is private. Consequently, the most differentiating iOS execution mechanism cannot be independently audited or reproduced from the public code.

## Repository and license map

| Component | Public? | Role | License evidence | Assessment |
|---|---:|---|---|---|
| [`shorebirdtech/shorebird`](https://github.com/shorebirdtech/shorebird/tree/98adec24391bf36ed3599ec8f448d48658bb5e78) | Yes | Dart CLI, API protocol models, build orchestration, archive comparison, patch upload and management | Repository contains [MIT](https://github.com/shorebirdtech/shorebird/blob/98adec24391bf36ed3599ec8f448d48658bb5e78/LICENSE-MIT) and [Apache-2.0](https://github.com/shorebirdtech/shorebird/blob/98adec24391bf36ed3599ec8f448d48658bb5e78/LICENSE-APACHE) texts | **FACT:** dual-licensed public tooling. |
| [`shorebirdtech/updater`](https://github.com/shorebirdtech/updater/tree/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7) | Yes | Rust on-device updater, C API, Dart bindings, binary-diff creation tool | Repository contains [MIT](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/LICENSE-MIT) and [Apache-2.0](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/LICENSE-APACHE) texts | **FACT:** dual-licensed updater and patch tooling. |
| [`shorebirdtech/engine`](https://github.com/shorebirdtech/engine/tree/e4575c7403bd3453d04bfa03e01218e5a0bca0c6) | Yes | Flutter engine fork; integrates updater and altered Dart runtime artifacts | [Engine license](https://github.com/shorebirdtech/engine/blob/e4575c7403bd3453d04bfa03e01218e5a0bca0c6/LICENSE) | **FACT:** public BSD-style Flutter engine fork. |
| [`shorebirdtech/flutter`](https://github.com/shorebirdtech/flutter/tree/91f8bd75076e9c740aa13cf67eb9ec1a093f68f5) | Yes | Framework/tool fork; selects Shorebird engine artifacts and bundles Shorebird configuration | [Flutter license](https://github.com/shorebirdtech/flutter/blob/91f8bd75076e9c740aa13cf67eb9ec1a093f68f5/LICENSE) | **FACT:** public BSD-style Flutter fork. |
| [`shorebirdtech/buildroot`](https://github.com/shorebirdtech/buildroot/tree/27a47046c61bc2b68451bc85cdde2a94ee2b24be) | Yes | Engine build configuration; exposes updater symbols and supplies required linkage | [Buildroot license](https://github.com/shorebirdtech/buildroot/blob/27a47046c61bc2b68451bc85cdde2a94ee2b24be/LICENSE) | **FACT:** public BSD-style buildroot fork. |
| Modified Dart SDK | No | iOS interpreter, compiler similarity work, linker/runtime support | Shorebird states the fork is private in [System Architecture](https://docs.shorebird.dev/code-push/system-architecture/#dart-langsdk-the-dart-sdk) | **FACT:** not independently inspectable. |
| Hosted Code Push backend and Console | No complete server repository identified | Release/patch records, artifact storage, update checks, tracks, analytics, auth | Official architecture lists public-cloud infrastructure as a major component and describes Cloud Storage/Cloud Run, but does not link server source: [lifetime and components](https://docs.shorebird.dev/code-push/system-architecture/#lifetime-of-a-shorebird-update) | **UNKNOWN:** the hosted protocol is partly visible in client code, but a production-equivalent self-hostable backend is not publicly supplied. |

The license facts above describe the repositories, not permission to use Shorebird trademarks or private services. An independent implementation should not copy source merely because the license permits reuse; attribution and dependency licenses still require review.

## System diagram

```text
Developer source
      |
      v
Shorebird CLI ---- selects the release's exact Shorebird Flutter revision
      |
      +------------------------- release --------------------------+
      |                                                            |
      v                                                            v
Shorebird Flutter tool --> modified engine + updater --> AAB / IPA / archive
      |                                                            |
      +--> upload release Dart artifacts + release metadata --------+
      |
      +-------------------------- patch ----------------------------+
      |
      v
build current app with matching toolchain
      |
      +--> reject/warn on native or asset differences
      |
      +--> Android: release libapp.so vs new libapp.so
      |                 | binary diff + zstd
      |                 v
      |              per-ABI patch artifact
      |
      +--> iOS: release AOT snapshot + new AOT snapshot
                        | private Dart analysis/linker
                        v
                  linked vmcode / patch artifact
      |
      v
hosted patch-check service --> signed/hash-described artifact URL
      |
      v
embedded updater: check -> download -> verify -> stage -> activate next launch
      |
      +--> Android: reconstruct new AOT artifact; execute it natively
      |
      +--> iOS: unchanged/linkable functions -> release AOT native code
                changed/unlinkable functions -> Dart interpreter
      |
      +--> failed launch -> mark bad -> last known good patch or base release
```

## Release and patch construction

### Release

**FACT:** `shorebird release` wraps the Flutter build process with the Shorebird Flutter distribution and includes the updater in the application. The official architecture says the resulting release binary is uploaded and associated with `app_id` and release version; the store-distributed AAB or IPA is still the artifact delivered to users. See [System Architecture: lifetime](https://docs.shorebird.dev/code-push/system-architecture/#lifetime-of-a-shorebird-update).

**FACT:** Android release artifacts include the AAB and architecture-specific `libapp.so` files. Shorebird's glossary documents these explicitly under [Artifact](https://docs.shorebird.dev/code-push/#artifact). Those uploaded `libapp.so` files are later used as binary-diff bases.

**FACT:** The updater is compiled as a Rust static library and linked into the Flutter engine; it exposes a C API, while `package:shorebird_code_push` provides optional Dart bindings. The updater repository [README](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/README.md#parts) distinguishes the runtime library, patch executable, and optional Dart package. A developer does not need to wrap screens in a Shorebird widget for the engine's default startup check.

### Patch

**FACT:** `shorebird patch` builds the current source using the exact Flutter revision recorded for the target release, downloads release artifacts, creates platform-specific diffs, uploads them, and promotes them to a track. The official command page lists that sequence in [Create a Patch](https://docs.shorebird.dev/code-push/patch/#patching-multiple-platforms-simultaneously).

**FACT:** The CLI checks the built patch archive against the release archive for native and asset changes. Native and asset changes are unsupported by default, although `--allow-native-diffs` and `--allow-asset-diffs` can bypass the warning. Bypass is not evidence that the updater can deliver those changes; the flags are documented as "not recommended" in [patch options](https://docs.shorebird.dev/code-push/patch/#options), and the implementation calls the archive differ before artifact generation in [`patcher.dart`](https://github.com/shorebirdtech/shorebird/blob/98adec24391bf36ed3599ec8f448d48658bb5e78/packages/shorebird_cli/lib/src/commands/patch/patcher.dart).

**FACT:** The patch file generator uses `bidiff` and zstd compression. The implementation is small and directly visible in [`updater/patch/src/lib.rs`](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/patch/src/lib.rs#L1-L24). This binary-diff container is not Dart Kernel bytecode.

### Android execution

**FACT:** The Android patcher builds a new AAB, locates its per-ABI `libapp.so`, downloads the release's corresponding per-ABI artifacts, hashes the new `libapp.so`, and creates a binary diff for each architecture. See [`android_patcher.dart`](https://github.com/shorebirdtech/shorebird/blob/98adec24391bf36ed3599ec8f448d48658bb5e78/packages/shorebird_cli/lib/src/commands/patch/android_patcher.dart#L139-L248).

**FACT:** On device, the updater downloads and inflates the binary diff against the base release. Its documented state machine calls this “apply a bidiff to the current release” and rejects an invalid result: [`updater/library/README.md`](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/library/README.md#L181-L199).

**FACT:** Shorebird describes the reconstructed artifact as a new compiled version of all Dart code run inside the Dart VM, with no interpreter penalty on Android: [System Architecture](https://docs.shorebird.dev/code-push/system-architecture/#how-shorebird-code-push-works) and [Patch Performance](https://docs.shorebird.dev/code-push/patch/#patch-performance).

**Architectural implication:** “Changed code versus unchanged code” is not a runtime dispatch split on Android. The current application Dart program is AOT-compiled as a whole, and the device switches to the reconstructed new program. Binary diffing makes delivery proportional to binary similarity, but the runtime does not look up every function in a patch table.

### iOS execution

**FACT:** Shorebird's official architecture identifies two Dart changes: a compiler mode that makes new output maximally similar to previous output, and a linker that compares previous and new Dart programs at function granularity. It says linkable code executes from the previously signed binary and the remaining code executes in a Dart interpreter: [iOS architecture](https://docs.shorebird.dev/code-push/system-architecture/#how-shorebird-code-push-works).

**FACT:** The public CLI proves that an iOS patch is not merely a normal IPA diff. It builds an additional ELF AOT snapshot, extracts the release snapshot, invokes `aot_tools link`, records a link percentage, and packages either linked `vmcode` or a generated diff. See [`ios_patcher.dart`](https://github.com/shorebirdtech/shorebird/blob/98adec24391bf36ed3599ec8f448d48658bb5e78/packages/shorebird_cli/lib/src/commands/patch/ios_patcher.dart#L101-L267) and the `aot_tools link` wrapper in [`aot_tools.dart`](https://github.com/shorebirdtech/shorebird/blob/98adec24391bf36ed3599ec8f448d48658bb5e78/packages/shorebird_cli/lib/src/executables/aot_tools.dart#L325-L404).

**FACT:** Shorebird exposes `--min-link-percentage` for iOS. Its docs state that unchanged code runs on the CPU while changed or added code runs in the interpreter and can be slower: [iOS patch performance](https://docs.shorebird.dev/code-push/patch/#patch-performance).

**UNKNOWN:** The exact interpreted representation, opcode set, VM semantics, compiler transformations, stable identity scheme, linker correctness rules, and interpreter security boundaries cannot be verified because the modified Dart SDK is private. Public CLI calls into `aot_tools`, but that is an interface to the private implementation, not the implementation itself.

**INFERENCE:** Shorebird's “changed” category is more accurately “not safely linkable to a function in the release program.” A source change can affect more functions than the edited body because compiler output, layout, constants, types, or dependency changes may alter linkability. The public link percentage and compiler-similarity design support this inference; the private linker prevents confirming every rule.

## Toolchain modifications and why a separate distribution is required

| Fork/component | Verified modification or responsibility | Why it matters |
|---|---|---|
| Buildroot | Exposes updater symbols and links dependencies needed by the Rust updater. | Stock engine build rules do not expose the updater C API. |
| Engine | Links the updater into the application engine and supplies hooks for selecting/validating patch artifacts. | A stock store release has no early engine path to replace its AOT program. |
| Flutter framework/tool | Points at Shorebird engine artifacts and bundles `shorebird.yaml` configuration into the app. | Builds must embed app/release/channel/updater configuration and fetch the matching modified engine. |
| Dart SDK | Adds the iOS interpreter, previous-output-aware compilation, linking, and mixed interpreted/native execution support. | These capabilities are absent from upstream Dart AOT and are the core of iOS patch execution. |
| Shorebird CLI | Resolves the release's Flutter revision; orchestrates release/patch builds, artifact comparison, binary diffs, signing, upload, tracks, and rollback commands. | Patch and release compiler outputs must be compatible and the correct base artifacts must be paired. |

The first four modifications are enumerated in Shorebird's [System Architecture: Flutter modifications](https://docs.shorebird.dev/code-push/system-architecture/#flutter-modifications). Public source verifies the CLI, updater, and the three public forks; the Dart modification remains a vendor claim at implementation level.

**FACT:** Shorebird installs a private Flutter copy under its own cache rather than using or overwriting the developer's normal Flutter cache. Its docs explain that Flutter artifact resolution keys off engine versions and that a separate install prevents conflicts: [Installing a forked Flutter](https://docs.shorebird.dev/code-push/system-architecture/#installing-a-forked-flutter).

**FACT:** Patch and release must use matching Dart SDKs and build flags. The public linker wrapper emits explicit errors for different Dart SDK/snapshot versions and build flags, and states that `shorebird patch` builds against the release's Flutter revision: [`aot_tools.dart`](https://github.com/shorebirdtech/shorebird/blob/98adec24391bf36ed3599ec8f448d48658bb5e78/packages/shorebird_cli/lib/src/executables/aot_tools.dart#L126-L140). Official CI docs likewise say the CLI looks up the exact Flutter version used for the release: [Generic CI](https://docs.shorebird.dev/code-push/ci/generic/).

**Conclusion:** Shorebird distributes a toolchain because its patch format and runtime depend on coordinated changes below application source level: compiler/VM behavior, engine linkage and loading, framework artifact selection, and release-patch compiler identity. Merely adding a Dart package to a stock AOT app would not reproduce this architecture.

## Update protocol, caching, activation, and rollback

**FACT:** The embedded updater checks on startup in a background thread. A request is bound to application ID, release version, channel, platform, architecture, and current patch state; a successful response names a patch number, hash, and download URL. The official architecture provides the request/response shape and links to the public network implementation: [Lifetime of an update](https://docs.shorebird.dev/code-push/system-architecture/#lifetime-of-a-shorebird-update) and [`network.rs`](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/library/src/network.rs).

**FACT:** Download and application are staged for a subsequent launch by default. The updater persists state, and the optional `shorebird_code_push` package can request checks/downloads programmatically. The package is optional, so normal apps do not require explicit patch-view integration: [`updater/README.md`](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/README.md#parts) and [Code Push overview](https://docs.shorebird.dev/code-push/#how-does-code-push-work).

**FACT:** The updater maintains launch state for the last successfully booted patch, last attempted patch, and next patch. On failed launch it deletes/rejects the failed target and falls back to the last valid successful patch or the base release. See the [Boot State Machine](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/library/README.md#L130-L168). Recent source uses a more detailed per-patch lifecycle with bad-patch reasons, but preserves that safety model in [`lifecycle.rs`](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/library/src/cache/lifecycle.rs).

**FACT:** Server-driven rollback and client crash-loop recovery are distinct:

- A maintainer can roll a deployed patch back through Shorebird; devices learn the desired patch state on their next update check. See [Roll back a Patch](https://docs.shorebird.dev/code-push/rollback/).
- A patch that fails during boot is locally marked bad and will not be selected again, preventing repeated crash-at-launch loops. See [System Architecture](https://docs.shorebird.dev/code-push/system-architecture/#lifetime-of-a-shorebird-update).

**INFERENCE:** This is atomic at the boot-selection level — a completely staged artifact becomes `next_boot_patch`, while failure selects a prior valid target — but the public material does not establish filesystem-transaction guarantees for every possible power-loss point. The updater contains extensive lifecycle tests; an independent implementation should specify and fault-test its own atomicity rather than inherit the claim.

## Integrity and signing

**FACT:** SHA-256 hashes detect download/diff corruption but Shorebird explicitly says the hash alone is not a security feature. Patch signing is opt-in: [System Architecture](https://docs.shorebird.dev/code-push/system-architecture/#lifetime-of-a-shorebird-update).

**FACT:** The current updater verifies RSA PKCS#1 v1.5 signatures with SHA-256 and permits RSA keys from 2048 through 8192 bits. This is direct source evidence in [`signing.rs`](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/library/src/cache/signing.rs#L25-L63). It is not Ed25519.

**FACT:** A release embeds the public key; the CLI signs the patch hash with the corresponding private key or external signing command. Strict mode recomputes the file hash and verifies at each boot, while install-only mode verifies during installation; if no public key is configured, signature verification is skipped. See [updater verification modes](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/library/README.md#L217-L295).

**INFERENCE:** Rotating the patch-verification public key for already-installed releases is not transparently possible with the documented single embedded key; it normally requires a store release containing a new key. No public evidence establishes a signed key-delegation or multi-key rotation format.

**UNKNOWN:** The public updater shows version/release/patch binding and rollback behavior, but this review did not find a complete, formally specified replay/downgrade threat model. Server authority and monotonically numbered patches reduce accidental downgrade, but must not be treated as cryptographic anti-replay proof.

## Compatibility and patchability boundary

| Change | Shorebird behavior established by evidence |
|---|---|
| Ordinary app Dart code, Flutter widgets, navigation, state logic | **FACT:** patchable without special views; a patch replaces the Dart program. |
| Pure-Dart dependency update | **FACT:** documented as patchable when it changes only Dart code. |
| Kotlin, Java, Swift, Objective-C, plugin native implementation | **FACT:** new store release required; downloaded patch does not replace native application code. |
| Android manifest, iOS plist, permissions, entitlements | **INFERENCE:** these are native/package metadata rather than Dart AOT artifacts, so a store release is required. CLI native-archive diff checks are the enforcement aid, not a patch mechanism. |
| Assets, fonts, asset manifest | **FACT:** asset patching is not supported; new release required. |
| Flutter/Dart SDK version | **FACT:** a patch targets the exact release Flutter revision; changing it independently is incompatible. |
| Target platform/architecture | **FACT:** artifacts and update checks are platform- and architecture-specific. |
| Native FFI library change | **FACT/INFERENCE:** Dart calls may change, but a new/changed compiled library is native code and cannot be delivered by the Dart patch artifact. Existing bundled FFI entry points remain callable if the Dart ABI usage stays compatible. |

Primary sources: [Is my change patchable?](https://docs.shorebird.dev/code-push/#is-my-change-patchable), [Create a Patch checklist](https://docs.shorebird.dev/code-push/patch/#overview), and the public platform archive differ implementations under [`archive_analysis`](https://github.com/shorebirdtech/shorebird/tree/98adec24391bf36ed3599ec8f448d48658bb5e78/packages/shorebird_cli/lib/src/archive_analysis).

## Evidence table

| Claim | Evidence | Source | Verified? |
|---|---|---|---|
| Existing screens do not need a patch wrapper. | Engine performs the startup check; Dart control package is optional; patch replaces application Dart code. | [Overview](https://docs.shorebird.dev/code-push/), [updater parts](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/README.md#parts) | **Yes — FACT** |
| Shorebird uses a modified Flutter engine. | Updater is statically linked into the engine; Shorebird documents engine hooks. | [Updater README](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/README.md), [System Architecture](https://docs.shorebird.dev/code-push/system-architecture/#flutter-modifications) | **Yes — FACT** |
| Shorebird requires a Dart/VM fork for iOS. | Official docs describe compiler, linker and interpreter changes and state the SDK fork is private. | [Dart SDK fork](https://docs.shorebird.dev/code-push/system-architecture/#dart-langsdk-the-dart-sdk) | **Existence verified; implementation unverified** |
| Android patches run native compiled Dart code. | CLI diffs new and release per-ABI `libapp.so`; docs say new compiled Dart runs in the VM without patch performance cost. | [`android_patcher.dart`](https://github.com/shorebirdtech/shorebird/blob/98adec24391bf36ed3599ec8f448d48658bb5e78/packages/shorebird_cli/lib/src/commands/patch/android_patcher.dart#L139-L248), [performance](https://docs.shorebird.dev/code-push/patch/#patch-performance) | **Yes — FACT** |
| iOS unchanged and changed code use different paths. | Public CLI generates link output and percentage; official docs say linked release functions run native and remaining functions are interpreted. | [`ios_patcher.dart`](https://github.com/shorebirdtech/shorebird/blob/98adec24391bf36ed3599ec8f448d48658bb5e78/packages/shorebird_cli/lib/src/commands/patch/ios_patcher.dart#L155-L267), [architecture](https://docs.shorebird.dev/code-push/system-architecture/#how-shorebird-code-push-works) | **Interface verified; internals private** |
| Patch transport uses compressed binary diffs. | Public patch tool invokes `bidiff` then zstd. | [`patch/src/lib.rs`](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/patch/src/lib.rs#L1-L24) | **Yes — FACT** |
| Patch signing is mandatory. | Verification is skipped without an embedded public key. | [Updater verification modes](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/library/README.md#L217-L295) | **No — REJECTED** |
| Patch signing uses RSA/SHA-256. | `ring` verifier is configured for RSA PKCS#1 and SHA-256. | [`signing.rs`](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/library/src/cache/signing.rs#L25-L63) | **Yes — FACT** |
| A failed patch cannot permanently crash-loop the app at startup. | Persistent boot state marks failure and selects last valid patch or base release. | [Boot state machine](https://github.com/shorebirdtech/updater/blob/1f85c4ab1ee5b540269b9859c75e1bffbb9050c7/library/README.md#L130-L168) | **Mechanism verified — FACT** |
| Any Flutter version can patch any release. | CLI resolves the release revision; linker rejects differing SDK/snapshot/build flags. | [`aot_tools.dart`](https://github.com/shorebirdtech/shorebird/blob/98adec24391bf36ed3599ec8f448d48658bb5e78/packages/shorebird_cli/lib/src/executables/aot_tools.dart#L126-L140) | **No — REJECTED** |
| Assets and native code are patched. | Docs explicitly exclude them; CLI only offers warning bypasses, not an updater path. | [Patch checklist/options](https://docs.shorebird.dev/code-push/patch/) | **No — REJECTED** |
| Shorebird is fully open source and self-hostable. | Core iOS Dart fork and hosted backend are not public. | [Components and Dart SDK](https://docs.shorebird.dev/code-push/system-architecture/#shorebird-components-and-source-code) | **No — REJECTED for “fully”; self-hosting UNKNOWN/not supplied** |
| Shorebird's existence proves App Store policy acceptance for any Dart patch. | No source or documentation can establish future review outcomes or classify every change. | This is a policy conclusion, not a technical source claim. | **No — unsupported** |

## Limitations and public-evidence gaps

1. **Private critical runtime.** The iOS Dart compiler, linker, interpreter, and VM changes are the core differentiator and are not public. Their completeness, malformed-patch handling, sandboxing, instruction accounting, and semantic parity cannot be audited here.
2. **No complete self-hostable stack.** Public clients reveal request types and updater behavior, but the artifact service, patch-check service, Console, auth, and operational backend are not published as a production-equivalent deployment.
3. **Toolchain maintenance burden.** Four upstream forks/repositories must track compatible Flutter and Dart revisions. Compiler/VM and engine defects can be version-specific; Shorebird release notes regularly couple support and fixes to particular Flutter versions.
4. **iOS performance variability.** Interpreted code is slower. Link percentage mitigates this but depends on private linker rules and the exact change; performance-sensitive changed functions remain a risk.
5. **Native and asset boundary.** Patches cannot safely alter native plugins, packaging metadata, entitlements, permissions, compiled libraries, or assets. A pure-Dart-looking dependency bump can still cross this boundary.
6. **Signing is opt-in.** Unsigned configurations rely on TLS/service control and a non-security SHA-256 integrity check. That is inadequate as a model for a new security-first runtime.
7. **Key rotation and anti-replay remain underspecified publicly.** A single public key is embedded at release time. A new design should specify multi-key rotation, app/release/runtime binding, expiry, downgrade resistance, and offline behavior explicitly.
8. **Store policy remains a separate question.** Technical similarity to Shorebird is not evidence that a particular patch is acceptable under Apple or Google policy.

## Implications for this project

- Shorebird proves that transparent patching of normal Flutter/Dart source is possible when the compiler, VM, engine, and build pipeline can be modified together.
- It does **not** prove that the same coverage can be achieved with a stock engine, source instrumentation, or a public application-level interpreter.
- Android demonstrates a comparatively simple native-AOT replacement path, but that path is not automatically portable to iOS policy and executable-memory constraints.
- iOS demonstrates a hybrid native/interpreter model, but its feasibility depends on compiler/linker/runtime work hidden in the private Dart fork. It is therefore a design reference, not a reproducible proof for an open-source runtime.
- A no-fork architecture must experimentally prove stable function identity, dispatch insertion, value/closure/async semantics, tree-shaking compatibility, and acceptable unpatched overhead. Shorebird avoids application-call dispatch overhead by intervening below normal Dart source.
- If experiments A–C fail to provide broad semantics and transparent integration, Shorebird is evidence that Architecture D can work — with a substantial permanent upstream-tracking and security-audit burden.

## Remaining questions

- What exact IR and opcode format does the private iOS interpreter consume?
- How does the linker decide equivalence and compatibility for closures, generic instantiations, async state machines, records, mixins, reflection-like dynamic calls, and compiler-generated functions?
- What validation occurs before interpreted code reaches the VM, and what resource limits exist?
- Is there an unpublished supported route to self-host patch checks and artifact storage without Shorebird's cloud?
- What cryptographic binding covers app ID, release version, platform, architecture, patch number, runtime version, and artifact hash, beyond signing the hash string?
- How is verification-key rotation handled for already-installed releases?
- What exact power-loss guarantees apply during download, inflate, metadata update, and next-boot activation?

These questions must remain **UNKNOWN** until answered by public code, an official specification, or independent experiments.
