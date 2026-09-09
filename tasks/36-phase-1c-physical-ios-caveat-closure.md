# Task 36 — Phase 1C physical iOS caveat closure

Status: [x] Completed

## Goal

Close the remaining Phase 1C iOS evidence caveat by repeating the automatic
physical iPhone runtime sequence on the currently connected device, while
preserving the historical Phase 0B/Phase 1B evidence and without changing
Architecture B, Patch Format v1, or capability contract v1.

## Scope and Non-goals

Scope: run the existing automatic signed iOS Release/AOT workflow on the
connected physical iPhone; install the selected release once; observe BASE,
signed patch activation, health confirmation, restart persistence, signed base
rollback, restart after rollback, and one invalid-artifact rejection. Capture
the exact release/IPA/patch/device/tool/signing metadata and evidence labels.

Non-goals: App Store or production-signing claims, cloud/product work, Phase
1D, Flutter/Dart changes, Patch Format v1 changes, capability-v1 changes,
runtime architecture changes, Android work, or rewriting historical iOS task
records.

## Owner

`Bernoulli` (`01a02a13-7a1c-7423-81a7-a1ec917c280c`), a coordinator-assigned
`gpt-5.6-luna` max/fast iOS physical-validation worker, owns only this task
record and ephemeral iOS evidence under the fresh run directory. The
coordinator owns Task 31 integration and `docs/PHASE_1C_REVIEW.md`.

## Dependencies

- `tasks/31-phase-1c-runtime-hardening.md`;
- completed `tasks/24-physical-ios-baseline.md` and
  `tasks/25-ios-expanded-and-policy.md`;
- `scripts/e1_ios_physical.sh`;
- XcodeBuildMCP device workflow;
- connected physical iPhone and existing local AUVANA signing configuration.

## Assumptions

- the shared worktree contains unrelated user changes; do not reset, revert,
  commit, or overwrite them;
- use the existing USB transport and current project-local signing settings;
- install exactly once for this fresh run and do not reinstall during the
  lifecycle sequence;
- preserve prior evidence and label new observations separately;
- no private signing material may be logged or copied into evidence.

## Work Items

- [x] Verify the connected physical iPhone and XcodeBuildMCP device identity.
- [x] Run the existing automatic signed physical iOS workflow with a fresh
  evidence run ID.
- [x] Capture BASE, activation, health, restart persistence, rollback,
  rollback persistence, and invalid-artifact observations.
- [x] Review evidence for exact device/release/patch identity and absence of
  secrets or absolute-path leakage.
- [x] Append results and blockers without rewriting historical iOS evidence.

## Validation

Required validation is the existing `scripts/e1_ios_physical.sh` USB sequence,
run through `xcodebuildmcp` for build/install/launch/stop. Host-only or
historical results must not be relabeled as fresh physical evidence. Run
task-scoped shell/evidence assertions and record every skipped assertion.

### HOST REGRESSION

- Help-first XcodeBuildMCP discovery passed: `xcodebuildmcp --version` reported
  `2.5.2`; `xcodebuildmcp tools` exposed the device build, install, launch, and
  stop tools; the command-specific help exposed session-default profiles. The
  daemon was not running and no project `.xcodebuildmcp` defaults file was
  present, so the script's explicit workspace, scheme, device, signing, and
  transport arguments were used.
- `flutter devices` reported the target iPhone on iOS `18.7.9` and also emitted
  the known unrelated Android mDNS/ADB parse warning (`Unexpected failure
  parsing device information from adb output`). The iPhone check passed, so no
  SDK/configuration workaround was used.
- `xcodebuildmcp device list --output json` matched CoreDevice ID
  `CC5119BA-1DBD-54D2-AD8C-1F15FC5E5B6F`, platform `iOS`, state `connected`, and
  iOS `18.7.9`. `bash -n scripts/e1_ios_physical.sh` passed.
- Tool versions for the run were Flutter `3.47.0`, Dart `3.13.0`, and
  XcodeBuildMCP `2.5.2`.

### PHYSICAL IOS

The fresh run used the exact automatic workflow command:

```sh
E1_XCODE_DEVICE_ID=CC5119BA-1DBD-54D2-AD8C-1F15FC5E5B6F \
E1_DEVELOPMENT_TEAM=CYT7A4VAZ3 E1_IOS_TRANSPORT=usb \
E1_IOS_EVIDENCE_RUN_ID=phase1c-ios-caveat-20260822-1 \
scripts/e1_ios_physical.sh 00008020-001528860E03002E
```

It exited `0`. The evidence is retained under the fresh relative run
directory `fixtures/flutter_conformance_app/.dart_tool/e1_ios_runs/phase1c-ios-caveat-20260822-1/`.
XcodeBuildMCP reported a signed `Release` device build succeeded in
`81,544 ms` with no errors, followed by one successful install to the supplied
CoreDevice ID. The only build diagnostics were the two existing unknown
environment-variable warnings for `SWIFT_DEBUG_INFORMATION_FORMAT` and
`SWIFT_DEBUG_INFORMATION_VERSION`; they did not affect the build or run.

Fresh installed Release artifact identity:

- Bundle ID `dev.hyfens.conformance`; `CFBundleShortVersionString=1.0.0`,
  `CFBundleVersion=1`; platform `iphoneos`; SDK `iphoneos26.5`; minimum iOS
  `15.0`.
- The installed `Runner.app` contained 53 regular files totaling `17,070,371`
  bytes; its sorted relative-file manifest digest was
  `91b7f7f81cb097ad1defee858a05d80685cd1f2cac4188684ae7f73438f5336f`.
- `Runner` was `129,568` bytes with SHA-256
  `50df991e89a8b209cc01b4c44b2fb0fc0268d47502ce3cc00707f93cfab9d9e5`.
  `App.framework/App` was `6,078,352` bytes with SHA-256
  `9e149f4cec011b1807fb30711caa5f6c89598329ec868d81b485243161b18f6c`.
  `file` reported arm64 for both device binaries, and `jit-artifacts.txt` was
  empty (no `kernel_blob.bin` or `.dill`).
- Signed entitlements bound `CYT7A4VAZ3.dev.hyfens.conformance` and team
  `CYT7A4VAZ3`; the physical artifact was a development-signed device app.
  This is not an App Store, production-signing, or production-approval claim.
- The mandated `device build` workflow produced and installed `Runner.app`; it
  did not archive/export an IPA (`ipa_count=0`). IPA archive/export identity
  was therefore not asserted; the installed Release `.app` identity and
  digests above are the applicable artifact evidence for this workflow.

Fresh signed patch identity:

- Envelope: `Ed25519`, envelope version `1`, key ID
  `phase0b-rfc8032-test-only`; signed envelope size `1,369` bytes and
  SHA-256 `27636dfc15f0815c1f890f92ab7c122e9c7d7c51d02c142318ada0d68838fb18`.
- Decoded patch: app ID `dev.hyfens.conformance`, release ID
  `android-e1-release-1`, build fingerprint `conformance-build-1`, format and
  runtime version `9`, patch sequence `1`, decoded payload `881` bytes,
  signature `64` bytes, payload hash
  `7bc47d62b019836a19751f3f6948784192f4b19c130ae6c415b77851b2a28417`, and
  function ID
  `sha256:d5a3b64831b9a76d7d43cc8645ce79415061f59039f12963a272c51a005fe361`.
- The invalid control retained the same payload and envelope size but had a
  different signature and SHA-256
  `667b36e9d20650ac768497d4e65e79f42fb84089529f1c0b93418879e6b787e7`.

Fresh physical receipt sequence (all rows had the fresh run ID, app ID, and
`succeeded=true`):

| Stage | Physical observation | Process ID |
| --- | --- | ---: |
| `base` | Healthy, base AOT active, price `540` | `26240` |
| `patch-active` | Healthy candidate confirmed, patch mode, price `450` | `26240` |
| `restart-required-1` | Healthy patch mode, price `450`; first stop succeeded afterward | `26240` |
| `patch-persisted` | Healthy signed patch active after restart, price `450` | `26314` |
| `invalid-rejected` | Tampered signature rejected; active patch retained at price `450` | `26314` |
| `rolled-back` | Manual rollback to base AOT; high-water retained; price `540` | `26314` |
| `restart-required-2` | Rolled-back base state before second stop, price `540` | `26314` |
| `rollback-persisted` | Healthy base AOT active after second restart, price `540` | `26329` |
| `complete` | Healthy base AOT active, price `540` | `26329` |

The lifecycle had three launch records, two successful stops, and three
distinct process groups. `install.txt` recorded exactly one successful install
from `15:30:02Z` through `15:30:16Z`; the script contains exactly one
`xcodebuildmcp device install` invocation, and no reinstall occurred between
patch activation, invalid rejection, rollback, or either restart. The
device-downloaded USB receipts byte-for-byte matched the retained receipt
file.

Task-scoped evidence assertions passed after the run: receipt order and stage
values, health/rejection/rollback states, process-group boundaries, one-install
and three-launch/two-stop counts, USB receipt parity, Release build identity,
arm64/no-JIT artifact shape, patch identity/signature tamper shape, and app
bundle identity. No private key or secret material was copied into this task
record, and no absolute build path was included in this report.

Skipped assertions are deliberate scope boundaries: App Store compliance,
production approval, arbitrary Dart semantic coverage, power-loss durability,
and an IPA archive/export were not claimed. The raw ephemeral run remains the
source evidence; prior Task 24/25 evidence was not relabeled or rewritten.

## Next Action

Hand the fresh run to the coordinator for Task 31/Phase 1C integration and
wait for coordinator review. Do not start Android work from this task.

## Blockers

None. The Android mDNS/ADB parse warning is recorded as a host regression but
did not block the iPhone check or physical run. IPA archive/export was outside
the mandated device-build workflow and is not a physical-runtime blocker.

## Outcome

Fresh signed USB physical iOS caveat closure completed on the connected iPhone
without reinstall during the lifecycle sequence. The Release/AOT artifact was
arm64-only with no JIT payloads; the signed patch activated and remained
healthy across restart, the invalid signature was rejected without displacing
the active patch, rollback returned to base, and rollback persisted across the
second restart. This is bounded physical-device evidence only and makes no App
Store, production, or general semantic-coverage claim.

## References

- `docs/PHASE_1C_REVIEW.md`
- `docs/PHASE_1B_REVIEW.md`
- `tasks/24-physical-ios-baseline.md`
- `tasks/25-ios-expanded-and-policy.md`
- `scripts/e1_ios_physical.sh`
- `/Volumes/970EvoPlus/Downloads/CODEX_PHASE_1C_DEVICE_GATED_FINAL_CLOSURE.md`

## History

- 2026-08-22: Reserved Task 36 after the connected iPhone made a fresh
  physical Phase 1C caveat run possible. This package is disjoint from the
  serialized Android Tasks 34–35 work.
- 2026-08-22: Assigned to Bernoulli with `gpt-5.6-luna`, maximum reasoning,
  and priority/fast service.
- 2026-08-22: Ran the fresh automatic USB sequence
  `phase1c-ios-caveat-20260822-1` with the AUVANA team on the specified
  physical iPhone. Signed Release/AOT build, one install, base/activation/
  health/restart, invalid rejection, rollback, and rollback persistence all
  passed. Recorded the Android mDNS/ADB parse warning as HOST REGRESSION only;
  no workaround, source change, Android work, or protected-document change
  was made. Task-scoped evidence assertions passed and the run is handed to
  the coordinator for integration.
