# Phase 1B/1C toolchain and runtime threat model

Status: internal Phase 1C review artifact; not a production security audit.

Phase 1C extends the Phase 1B model around runtime failure safety. The
controller-integrated trust/high-water behavior below is host-tested; entries
still requiring device or OS-level observation remain explicit. This document does not
claim protection against a rooted or fully compromised device and does not
make App Store or Google Play compliance claims.

## Assets

- private Ed25519 signing seed;
- trusted public-key configuration;
- immutable release baseline and function compatibility records;
- source/build-graph fingerprints;
- signed Patch Format v1 artifacts;
- temporary instrumented build workspace.

## Attacker inputs

The tool treats project files, `tool.yaml`, package metadata, generated
artifacts, patch paths, patch bytes, and local filesystem names as potentially
hostile or corrupted. A local attacker may also tamper with a patch or baseline
file after creation.

## Controls implemented in the CLI

- project discovery ascends only from the requested/current directory and does
  not traverse arbitrary filesystem roots;
- source traversal is bounded, sorted, and does not follow symlinks;
- configured paths cannot escape the project root;
- release and patch metadata use canonical JSON and normalized logical paths;
- release directories are immutable after creation;
- temporary release writes use staging and rename;
- instrumented builds run in an ephemeral overlay and do not rewrite source;
- private keys are generated explicitly, kept separate from the public-key
  material, and permission-restricted on supported hosts; an external private
  key path is supported and the checkout-local default emits a warning;
- Patch Format v1 decoding enforces bounds, canonical encoding, digest, exact
  release identity, and signature metadata;
- `tool inspect` decodes metadata only and never executes a patch;
- patch generation rejects unsupported mixed changes instead of silently
  omitting them.
- generated release bootstraps embed only the configured trusted public key and
  release compatibility tables; no private key enters the overlay or artifact;
- the local server verifies the artifact and exact release before serving it;
- the rollback control is a separate canonical, signed message. The runtime
  checks its trusted key, application/release identity, and exact durable
  `(sequence, digest)` high-water before selecting the AOT base;
- rollback clears active guest code but does not lower high-water or make an
  old patch generally replayable;
- lifecycle state uses two checksummed release-bound copies and atomic
  temporary-file/rename writes; malformed or conflicting copies enter a
  recovery-needed barrier;
- runtime state is stored below the private application-support directory,
  with bounded app/release path components and no system-temp fallback;
- cleanup accepts only explicit `builds` or `patches` scopes plus exact release
  confirmation. It rejects protected scopes, symlinks, and untrusted target
  types while retaining keys, baselines, journals, and sequence state;
- the controller-integrated key-lifecycle journal rejects unknown-key
  self-authorization, preserves retained-artifact rules across retirement,
  supports signed add/retire/revoke/recovery transitions, and commits trust
  generation with patch high-water and executable selection;
- LAN binding requires an explicit `--allow-lan` flag and remains a local
  development transport without authentication.

## Known limits

The local tool does not provide a trusted server, transport authentication,
external key rotation/revocation service, filesystem tamper resistance, or cloud key
custody. A signed patch or rollback command can still be issued by whoever
controls the configured development private key; key custody remains a local
operator responsibility. The runtime does not claim protection against a
rooted or fully compromised device. The application-support directory is
private under normal platform sandbox rules, but a local filesystem attacker
may still tamper with or delete it; checksum, dual-copy, release binding, and
recovery barriers make that tampering fail closed rather than silently
selecting arbitrary code. Deterministic lifecycle boundary fault-injection
and malformed-corpus tests exist, but they are not a substitute for OS-level
power-loss testing. Controller key rotation/revocation has focused host tests;
OS-level crash durability and protected key custody remain maintainer gates. The
current E0 bridge
extension is non-critical to Patch Format v1 and is activated only through the
bounded E1 integration adapter.

## Phase 1C threat coverage

| Threat | Current disposition | Required evidence or boundary |
| --- | --- | --- |
| Interrupted lifecycle write or process death | Host fault-boundary tests mitigated; OS-level evidence pending | Deterministic hooks cover flush/rename/readback boundaries; physical power-loss/process-kill campaigns remain a maintainer gate. |
| Corrupt, missing, stale, or conflicting lifecycle copies | Mitigated by checksums, copy selection, and recovery barrier | No arbitrary candidate may be authorized; both-copy corruption remains fail-closed. |
| Repeated candidate startup failure | Bounded host behavior implemented | One-attempt pending-candidate boot lease and fallback tests exist; broader process-cycle/device evidence remains pending. |
| Malformed or adversarial patch bytes | Corpus and bounded seeded regression tests implemented | Parser/verifier/interpreter/lifecycle fuzz campaigns must remain bounded and reproducible. |
| Interpreter infinite loop or resource exhaustion | Partially mitigated by release-owned limits | Instruction, call-depth, closure, capability, async, and value-size limits are enforced; physical/runtime campaign evidence remains pending. |
| Patch runtime error | Partially mitigated | Stable runtime codes, function disable/fallback, and logical source-map seams exist; full device error-isolation evidence remains pending. |
| Source-map information leakage | Mitigated by design; test required | Logical URIs only; absolute checkout paths, secrets, and private key material must not appear in diagnostics. |
| Signing-key compromise or unsafe rotation | Controller-integrated host behavior mitigated; custody out of scope | Release-owned trust transitions, explicit retirement/revocation, bounded offline recovery, and no self-authorizing unknown key share one durable controller authority; KMS/HSM and operator approval are not provided. |
| Replay or downgrade through rollback, cleanup, or recovery | Mitigated in the tested host boundary | High-water, trust generation, and remembered identities remain monotonic across rollback, cleanup, recovery, and dual-copy repair. |
| Malicious local development-server response | Mitigated in baseline | Transport is untrusted; signature, release, sequence, capability, and resource checks remain authoritative. |
| Symlink/path traversal through runtime state | Mitigated in baseline | Private app-support root, bounded components, atomic writes, and no untrusted filename interpolation. |
| Rooted or fully compromised device | Out of scope | No claim of filesystem or key secrecy after host compromise. |

Phase 1C must stop for maintainer review if any remaining control requires
weakening anti-replay, bypassing signature/release checks, mutating Patch
Format v1, opening arbitrary host reflection, or accepting unrecoverable
runtime failure.

## Review triggers

Stop for maintainer review if overlay building requires destructive source
rewrites, if release identity includes machine-specific paths, if a malformed
project can escape configured roots, if unsupported changes can produce a
partial artifact, if durable storage cannot preserve release-bound state, or
if rollback requires lowering the high-water.

## Phase 1D coordinator evidence update — 2026-08-23

The fresh Phase 1D Android run on the Redmi Note 10 Lite and the fresh
automatic iOS run on the paired iPhone exercised signed activation, health
confirmation, restart persistence, signed base rollback, retained high-water,
and delivery-boundary withholding of stale/malformed candidates. These observations strengthen the
physical process/restart boundary for the stated fixture and releases; they
do not replace OS-level power-loss testing, protected key custody, transport
authentication, or rooted-device testing.

The iOS runtime log/UI channel was unavailable because the Developer Disk
Image was not available, so iOS evidence was limited to process liveness and
authenticated app-support state-v4 snapshots. The local status command remains
a bounded toolchain inventory and does not create a remote runtime-control or
telemetry channel. No threat disposition was broadened beyond the controls
listed above, and no Patch Format v1 or capability v1 authority was changed.
