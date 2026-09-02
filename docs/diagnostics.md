# Toolchain diagnostics

Status: Phase 1B/1C implementation surface.

The CLI uses stable diagnostic codes so scripts can distinguish project,
patchability, native-boundary, release, and signing failures. Human output is
the default; `--json` preserves the same code and action fields for automation.

## Code families

| Family | Meaning |
| --- | --- |
| `T1xxx` | project, environment, configuration, or build-tool failure |
| `T12xx` | `tool.yaml` or project metadata failure |
| `T13xx` | package graph/package-config failure |
| `T14xx` | source discovery or selection failure |
| `T16xx` | release overlay/build failure |
| `P2xxx` | changed Dart/source patchability failure |
| `N3xxx` | native or store-release-required project input |
| `S4xxx` | signing key or signature failure |
| `R5xxx` | release baseline or artifact compatibility failure |
| `T9999` | unexpected CLI failure; use `--verbose` for the stack trace |

## Current codes

| Code | Summary | Developer action |
| --- | --- | --- |
| `T1001` | Flutter project not found | Run inside a project or pass `--project`. |
| `T1003` | `pubspec.yaml` is not a mapping | Repair the project manifest. |
| `T1004` | Project package name is invalid | Use a valid lowercase Dart package name. |
| `T1005` | Project is not a Flutter application | Add/repair the root `flutter` pubspec section. |
| `T1006` | Release target is unsupported | Use `android` or `ios`. |
| `T1101` | Flutter SDK unavailable for a release build | Use a supported Flutter SDK or explicitly use metadata-only tests. |
| `T1102` | Flutter/Dart toolchain differs from the release | Use the exact recorded toolchain or create a new release. |
| `T1201` | Configuration is not a mapping | Repair `tool.yaml`. |
| `T1202` | Unsupported configuration version | Upgrade the tool configuration deliberately. |
| `T1203` | Configuration field has the wrong type | Repair the named `tool.yaml` field. |
| `T1204` | Configuration list is invalid | Use a YAML list of strings. |
| `T1205` | Configured path escapes the project | Use a project-relative path without traversal. |
| `T1210` | `tool.yaml` already exists | Review it or pass `--force` deliberately. |
| `T1301` | `pubspec.lock` is not a mapping | Repair dependency resolution output. |
| `T1302` | `package_config.json` is malformed | Run the project package resolution, then retry. |
| `T1303` | `package_config.json` contains an invalid entry or URI | Run package resolution and inspect the generated file. |
| `T1401` | Entrypoint is not selected | Keep `lib/main.dart` inside the include policy. |
| `T1602` | Package configuration is missing for overlay build | Run `flutter pub get`, then retry. |
| `T1603` | Instrumented Flutter release build failed | Review normal Flutter output; the source tree was not rewritten. |
| `T1604` | Release artifact disappeared before baseline commit | Retry the release build; the old baseline was preserved. |
| `T1605` | Patch runtime package is unavailable to the tool | Install/use the complete tool distribution and retry. |
| `T1606` | Flutter completed without a release artifact | Resolve signing/export settings; no release baseline was committed. |
| `T1607` | Selected external package cannot be instrumented safely | Use a supported local package path or create a normal release. |
| `P2001` | Some declarations were excluded | Changes in those declarations require a store release. |
| `P2002` | Source unit is outside the patchable subset | Use supported source or perform a store release. |
| `P2003` | Changed source contains unsupported declarations | Remove the unsupported change or perform a store release. |
| `P2004` | Function table changed | New/removed functions require a store release. |
| `P2005` | Tracked source file removed | Create a new store release. |
| `P2006` | New source unit is absent from the baseline | Create a new store release. |
| `P2007` | Function signature is incompatible | Keep exact parameters/defaults/receiver/return metadata or release normally. |
| `P2008` | Changed source has no patchable function body | Treat as unknown and release normally. |
| `P2009` | Changed function is absent from the release | Do not manually add function IDs; create a store release. |
| `P2010` | No patchable changes were found | Do not create an empty patch artifact. |
| `P2011` | Compiled patch requires an undeclared host contract | Add a release-owned capability contract or create a normal release. |
| `N3001` | Native/store-reviewed input changed | Create a normal store release. |
| `N3003` | Resolved package graph changed | Review dependency/plugin changes and create a store release. |
| `N3004` | Toolchain configuration changed | Create a new baseline after changing policy. |
| `N3005` | Native-boundary source changed | Create a normal store release; native implementation changes are not OTA patch content. |
| `S4001` | Signing key missing | Run `hyfens keys generate` or configure an explicit key path. |
| `S4002` | Signing key malformed | Generate a new key pair after preserving the old material. |
| `S4003` | Private and public key paths are identical | Configure distinct key files. |
| `S4004` | Existing signing material would be overwritten | Choose new paths or remove files intentionally. |
| `S4005` | Private key permissions could not be restricted | Fix filesystem permissions before signing. |
| `S4006` | Generated signature failed self-verification | Stop and inspect the toolchain; do not distribute the artifact. |
| `S4007` | Patch key is not trusted | Use the public key paired with the configured private key. |
| `S4008` | Patch signature invalid | Discard the artifact and investigate tampering or key mismatch. |
| `R5001` | Release baseline not found | Run `hyfens release` or pass the exact existing release ID. |
| `R5002` | Release target is ambiguous | Pass `--release <release-id>`. |
| `R5003` | Release ID already has different metadata | Preserve the old baseline; never overwrite it. |
| `R5004` | Patch artifact malformed | Do not execute it; rebuild or discard it. |
| `R5005` | Patch function table incompatible | Target the exact release and signature table. |
| `R5006` | Toolchain version incompatible with the release | Use the recorded tool version or create a new release. |
| `R5007` | Release baseline metadata is malformed | Preserve the evidence and create a new baseline. |
| `R5008` | Patch sequence metadata is malformed | Preserve the patch directory; repair sequence state deliberately. |
| `T1701` | Development server host is not loopback | Use `127.0.0.1`, `localhost`, or another loopback address. |
| `T1702` | Development server port is invalid | Choose a TCP port in the valid range. |
| `T1703` | Development server release is missing | Pass an exact release ID or include it in the request. |
| `T1704` | Development server release is invalid | Create or select a valid local release baseline. |

## Rollback and cleanup codes

| Code | Summary | Developer action |
| --- | --- | --- |
| `R6001` | Rollback target is unsupported | Use the trusted `base` target; prior-patch selection is not exposed. |
| `R6002` | Rollback journal is invalid | Preserve the release directory and repair state deliberately. |
| `R6003` | Rollback high-water is unavailable | Do not reset sequence state; inspect the release evidence. |
| `R6004` | Rollback high-water regressed | Preserve the journal and use a higher sequence after review. |
| `R6005` | Trusted store-installed base is unavailable | Use a non-metadata release with its immutable artifact present. |
| `R6006` | Rollback state commit failed | Preserve the prior state and resolve the filesystem error. |
| `R6007` | Release requires a normal release before rollback | Target a complete store release, not a metadata-only baseline. |
| `C7001` | Cleanup scope is unsupported | Use `builds` or `patches`. |
| `C7002` | Exact cleanup confirmation is missing | Repeat the exact release ID with `--confirm`. |
| `C7003` | Cleanup target is invalid | Pass one exact existing release ID. |
| `C7004` | Cleanup scope is protected | Keys, source, releases, and evidence are never broad-cleaned. |
| `C7005` | Patch cleanup requires explicit base rollback | Run the signed base rollback first. |
| `C7006` | Cleanup failed | Preserve remaining artifacts and resolve the filesystem error. |

## Phase 1C runtime diagnostics

The interpreter and runtime-hardening surfaces use the `E8xxx` family. These
codes are runtime-local diagnostics; they do not alter Patch Format v1 or the
capability contract.

| Code | Summary | Runtime action |
| --- | --- | --- |
| `E8101` | Interpreter instruction/resource budget exceeded | Disable the failing patched function and use its AOT fallback. |
| `E8102` | Capability-call budget exceeded | Reject the invocation and preserve the active lifecycle state. |
| `E8103` | Closure invocation budget exceeded | Reject the invocation and use the AOT fallback. |
| `E8401` | Source-map lookup failed or metadata is malformed | Report the function/release context without exposing absolute paths; never block execution recovery. |
| `E8501` | Patch execution failure | Isolate the failing invocation/function according to runtime policy. |
| `E8502` | Invalid interpreter opcode | Reject/disable the affected patch; do not execute unknown instructions. |

Runtime messages are bounded and redact path, URL, and credential values.
Source locations accept only logical `package:` or `e0-overlay:` URIs, never
checkout paths, and diagnostics do not include private key material.

`STORE_RELEASE_REQUIRED` is a patchability classification, not an App Store or
Google Play compliance claim.

## Phase 1D local status

`hyfens status` and `hyfens status --json` provide a bounded, read-only projection
of the local developer toolchain. The status command reports project identity
as bounded labels, the existing toolchain version/status snapshot, and counts
of immediate tool-owned release/patch directories and recognized patch files.
It does not parse release/source records, read patch bytes, inspect key
contents, print URLs or filesystem paths, or contact a running application or
server.

The JSON result has `schemaVersion: 1` and keeps application-runtime status
explicitly separate from the local runtime-package check:

| Field | Meaning |
| --- | --- |
| `environment.runtimeStatus` | Whether the local runtime package is available to the CLI/toolchain. |
| `runtime.status` | `NOT_CONNECTED`; the CLI does not introspect application lifecycle state. |
| `runtime.scope` | `LOCAL_TOOL_ONLY`; this is not a remote or device status channel. |
| `store.scanTruncated` | The bounded inventory limit was reached; counts are lower bounds for that scan. |

Status diagnostics use the following additional codes:

| Code | Summary | Developer action |
| --- | --- | --- |
| `T1801` | Local tool metadata is not initialized | Run `hyfens init` before release or patch operations. |
| `T1802` | Local tool metadata store is incomplete | Preserve existing evidence and inspect the local `.tool` store deliberately. |
| `T1803` | Local status inventory was bounded | Use an exact release or patch inspection command for one target. |

`READY` means the configuration and required local tool directories were
present and the bounded scan completed. `NOT_INITIALIZED` means configuration
or the local store has not been created. `WARNING` means configuration/store
inspection was incomplete or the bounded scan could not count every entry.
Neither result claims that an application has a healthy active patch; runtime
health and controller lifecycle state remain application-owned surfaces.
