# Task 24 — Physical iOS signed baseline

Status: [x] Completed

## Goal
Build, sign, install, patch, reject, roll back, and restart the smallest stock-Flutter instrumentation scenario on a physical iPhone without reinstalling.

## Scope and Non-goals
Scope: release/profile configuration, arm64 device, local signed data patch, original/changed behavior, invalid signature, rollback, restart, runtime restrictions, interpreter behavior, and `docs/research/ios-feasibility.md`. Non-goals: App Store submission or compliance claim.

## Owner
iOS device specialist; coordinator reviews evidence.

## Dependencies
Tasks 13–15 and the generalized baseline; can begin before expanded Flutter fixtures when safe.

## Assumptions
The pure-Dart interpreter requires no downloaded executable memory and can run under physical iOS release restrictions.

## Work Items
- [x] Audit signing/device prerequisites without global changes.
- [x] Build and install one stock Flutter Release app signed by the AUVANA team.
- [x] Deliver and activate a local signed baseline patch without reinstall.
- [x] Test invalid signature, rollback, restart, and persistence.
- [x] Record configuration/restrictions/policy implications and validate the
  physical receipts, arm64 artifacts, entitlements, and no-JIT evidence.

## Validation
Executed: focused harness tests; current-source overlay and signed-payload
generation; AUVANA-signed Release device build/install through `xcodebuildmcp`;
arm64/AOT and entitlement inspection; USB staged patch delivery through
`ios-deploy`; receipt assertions for activation, invalid signature, rollback,
restart, and persistence. The current run ID is
`ios-usb-20260822-current`; the exact command used
`E1_XCODE_DEVICE_ID=CC5119BA-1DBD-54D2-AD8C-1F15FC5E5B6F
E1_DEVELOPMENT_TEAM=CYT7A4VAZ3 E1_IOS_TRANSPORT=usb
E1_IOS_EVIDENCE_RUN_ID=ios-usb-20260822-current
scripts/e1_ios_physical.sh 00008020-001528860E03002E`.

## Next Action
No further Phase 0B baseline work is required. The AUVANA team signing and USB
physical sequence passed on the connected iPhone.

## Blockers
None. The historical PMYC signing failure is retained below as an audit record;
the current run used the AUVANA team `CYT7A4VAZ3` and installed successfully.

## Outcome
The current-source stock iOS Release/AOT app was signed and installed once on
the USB iPhone with AUVANA entitlements
`CYT7A4VAZ3.dev.hyfens.conformance`. The narrow run proved base 540 → patched
450, invalid signature rejection with the patch retained, rollback to 540, two
restarts, and persistence. The arm64 app contained no kernel/dill payload. USB
staging is laboratory delivery evidence, not a production transport or policy
approval.

## References
- `docs/store-policy/apple.md`
- `docs/research/ios-feasibility.md`
- `scripts/e1_ios_physical.sh`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 23 was blocked by absent Android hardware. The xcodebuildmcp-cli workflow is available and a physical iPhone (iOS 18.7.9) is visible.
- 2026-08-22: Scaffolded only the missing stock iOS host. Four focused evidence
  tests passed; actual overlay/signing produced one transformed function and a
  1,349-byte signed data envelope.
- 2026-08-22: Signed Release build blocked on absent Xcode account/profile.
  Unsigned transformed Release device compile passed in 36.176 seconds and
  produced arm64 Runner/AOT App binaries with no kernel/dill asset. Physical
  scenarios remain blocked and were not marked passed.
- 2026-08-22: Independent review redacted local device/team/profile identifiers,
  narrowed ATS to local networking, replaced the malformed-input control with a
  signature-tampered envelope, and hardened the prepared run with a per-run
  bearer path, fresh-directory enforcement, and exact receipt/PID sequencing.
- 2026-08-22: Retried the signed physical sequence after the reported
  provisioning update using XcodeBuildMCP and the connected USB iPhone. The
  build failed before installation with the same account/profile diagnostics;
  no physical runtime result was inferred.
- 2026-08-22: Maintainer supplied the AUVANA signing account/profile. The
  current-source USB run `ios-usb-20260822-current` built, installed, activated,
  rejected a tampered signature, rolled back, restarted twice, and verified
  persistence on the physical iPhone. The earlier PMYC failure is historical,
  not the current blocker.
