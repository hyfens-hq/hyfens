# Independent real Flutter application acceptance

Status: [x] Completed

## Goal

Validate the public Hyfens CLI and the bounded local control-plane lifecycle
against one existing, private, unpublished Flutter application using real
application code and physical mobile-device acceptance where the environment
permits.

## Scope and Non-goals

Scope is one finite, sanitized campaign: independent project baseline, public
CLI release and installation, automatic project/flavor discovery, real
target-specific release builds, bounded local patch analysis, physical base
activation, negative-boundary checks, limited MCP smoke, and cleanup of
temporary acceptance authority. Managed Cloud and trusted acceptance receipts
are classified explicitly when their external prerequisites are unavailable.

Non-goals: fixture/conformance applications, desktop acceptance, self-host
parity, store publication, dashboard feature work, asset/font OTA support,
broadening the Flutter widget ABI, billing/MFA-provider/email provider work,
another CLI release, or unrelated Hyfens refactoring. No private Kavach360
source workaround is part of this task.

## Owner

Acceptance coordinator

## Dependencies

- Public Hyfens CLI `0.1.4`, published from `f1049a8` with the reviewed
  identity fix `65ce6c3` already on `origin/main`.
- A managed Hyfens control plane and Customer Workspace, if a disposable
  project-owned identity is available.
- One existing private Flutter application selected from the local workspace.
- Physical Android and iOS devices, an existing non-production dev signing
  identity, and project-owned acceptance access where available.

## Assumptions

- The selected app is an independent real application, not a Hyfens fixture.
- The private project remains outside this public repository and receives no
  committed Hyfens credentials or acceptance secrets.
- Release/patch behavior is evaluated with the stock Flutter toolchain and the
  publicly installed CLI.
- Device, app-capability, managed-Cloud, and runtime-receipt prerequisites may
  leave individual lifecycle gates explicitly classified rather than claimed.

## Work Items

- [x] Establish the independent app choice and clean project baseline.
- [x] Verify `65ce6c3`, publish immutable public `v0.1.4`, and validate the
  public release boundary. The six public archives, inventory, checksums,
  curl installer, help/version surface, and MCP initialize/tool discovery all
  passed. Existing `v0.1.3` was not moved or rewritten. Homebrew and Scoop
  remain independently published at `0.1.3`; the public GitHub/curl channel
  is the selected `0.1.4` acceptance path.
- [x] Re-run public smart discovery against Kavach360 without repeated
  selectors. Melos/Pub Workspace discovery selected the real app, persisted
  the `dev` flavor and nested `lib/src/flavors/dev.dart` entrypoint, and
  resolved the same target-specific dev identity for Android and iOS. Doctor,
  release, and patch target selection use that persisted binding; no legacy
  unflavored fallback remains.
- [x] Build and activate the real dev base on currently usable devices. The
  signed Android dev release and signed iOS dev IPA both carry the resolved
  dev-specific identity. Android was installed and launched once; iOS was
  installed and launched once through the paired-device tooling. CocoaPods
  deployment consistency passed. No base reinstall was performed during the
  later patch attempt.
- [x] Exercise the real app's patch boundary and meaningful-capability
  classification. A temporary, reversible async routing change was restored
  immediately; the public patch command failed closed with `F3010` because
  the real baseline's Material icon evidence is incomplete. `analyze` also
  records the app's expected `P2001` exclusions for widget/BuildContext,
  state, and most async/native-shaped declarations. No string-only UI claim
  or private-app workaround was made.
- [x] Validate restart/base-runtime and negative boundaries where the current
  app supports them. Both physical base launches produced the healthy AOT
  runtime status after restart. Resource snapshot tests cover asset, font, and
  native inputs; unsupported resource/native/engine changes remain
  `NEW_BASE_RELEASE`. Physical patch activation, patched restart persistence,
  physical rollback, and receipt behavior are classified below because no
  safe patch artifact was admitted.
- [x] Inspect the public MCP/local status surface and classify managed
  Customer Workspace evidence. Public MCP discovery and real-project
  status/doctor passed. The local profile remains unauthenticated and no
  disposable managed-Cloud identity was used; managed acceptance is an
  external gate.
- [x] Revoke temporary credentials/authority and record sanitized evidence.
  Temporary signing properties, Hyfens configuration, and trust keys were
  removed from Kavach360; generated release evidence was moved to recoverable
  temporary storage without exposing keys. Existing unrelated private-app
  changes were preserved.
- [x] Review the acceptance result and close the task with classified gates.

## Validation

Validation completed: `65ce6c3` inspection and focused flavor/discovery/identity
tests; CLI analysis; release-specific CLI tests; resource-boundary tests;
installer tests; archive/inventory/checksum validation; public `v0.1.4` curl
installation; `hyfens --help`, `--version`, `mcp --help`, MCP initialize and
tool discovery; real-project `init`, ordinary `doctor`, `status`, release
selection, and patch selection; Flutter device/ADB and current Apple-device
probes; normal CocoaPods deployment; signed Android/iOS dev release inspection;
single base install/launch per usable device; Android base-runtime log and
restart check; focused secret scan; and `git diff --check`. The release
workflow runs for CLI and images completed successfully. Homebrew/Scoop
metadata was inspected read-only and remains on its independently published
older version.

## Next Action

Finite campaign complete. Do not create another Task 247 or a microtask.
Task 253 continues to own trusted runtime settlement, commercial/payment
acceptance, and any future approved runtime/UI capability work. Managed Cloud
and public acceptance-receipt gates remain classified; live billing stays
disabled.

## Blockers

The following gates are classified, not silently converted into new work:

- `PROJECT CONFIGURATION`: Kavach360's real release baseline reports
  incomplete Material icon evidence (`F3010`), and its widget/state/most
  async declarations are outside the published patchable subset (`P2001`).
  The public CLI therefore refuses a patch before artifact admission. This is
  why meaningful widget/layout/theme/state/animation no-reinstall patches and
  patched rollback/restart could not be honestly claimed.
- `MANAGED_CLOUD_ACCEPTANCE = EXTERNAL_GATE`: no disposable managed identity
  is available without using a production customer or personal commercial
  account. No managed session, customer audit evidence, or live billing was
  used.
- `PUBLIC_RUNTIME_TRUST_RELEASE = PASS`; physical acceptance receipts and
  deduplication remain `PUBLIC_RUNTIME_GATE` because no patch was admitted to
  a device through the published runtime.
- Package-manager distribution is independent: public Homebrew and Scoop
  metadata still point at `0.1.3`; the new immutable GitHub/curl release is
  `0.1.4` and is the binary used for this campaign.

## Outcome

`HYFENS INDEPENDENT REAL APP — PASS WITH BOUNDED GATES`.

Public `v0.1.4` is immutable and contains the already-reviewed
`65ce6c3` identity propagation; old `v0.1.3` remains unchanged. The publicly
installed curl binary automatically discovers Kavach360's Melos/Pub Workspace,
persists the real `dev` flavor and entrypoint, and resolves the correct
flavor-specific Android and iOS identities without repeated flags. Signed dev
base releases were installed and launched once on the currently usable
Android phone and paired iPhone, and the base runtime remained healthy after
restart. The real app's patch attempt and analysis correctly fail closed at
the packaged-font/resource boundary, so no unsafe patch, reinstall, rollback,
or receipt claim is made. Asset/font/native/engine changes remain
`NEW_BASE_RELEASE`. Managed Cloud is an external gate, and physical receipt
deduplication is a public-runtime gate; Task 253 retains commercial/runtime
settlement ownership. Kavach360 source/configuration was restored and all
pre-existing private changes were preserved.

## Acceptance matrix

| Gate | Result |
| --- | --- |
| 65ce6c3 verified | PASS |
| Dev Android identity resolution | PASS |
| Dev iOS identity resolution | PASS |
| Release/patch identity consistency | PASS |
| Next public version selected | PASS |
| Public release validation | PASS |
| New release published | PASS |
| Public CLI installed | PASS |
| Kavach360 automatic discovery | PASS |
| Android device detected | PASS |
| iPhone detected/online | PASS |
| Android signing | PASS |
| iOS CocoaPods consistency | PASS |
| Android base install | PASS |
| iOS base install | PASS |
| Widget/layout patch | PROJECT_GATE |
| Theme/style patch | PROJECT_GATE |
| State/business patch | PROJECT_GATE |
| Async/routing patch | PROJECT_GATE |
| Representative animation/persistence patch | PROJECT_GATE |
| Asset mutation | NEW_BASE_RELEASE |
| New asset | NEW_BASE_RELEASE |
| Changed/new font | NEW_BASE_RELEASE |
| Native plugin/config | NEW_BASE_RELEASE |
| Engine mismatch | NEW_BASE_RELEASE |
| No-reinstall activation | PROJECT_GATE |
| Restart persistence | PROJECT_GATE |
| Rollback | PROJECT_GATE |
| Acceptance receipt | PUBLIC_RUNTIME_GATE |
| Receipt dedup | PUBLIC_RUNTIME_GATE |
| Managed Cloud | EXTERNAL_GATE |
| Kavach360 restored | PASS |

## References

- `docs/architecture/patch-format.md`
- `docs/architecture/dashboard-separation.md`
- `docs/README.md`
- [Public Hyfens CLI v0.1.4](https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.4)
- Hyfens identity fix `65ce6c3` and release metadata commit `f1049a8`
- Public distribution notes in `docs/cli-distribution.md`
- `docs/research/evidence/independent-real-app/2026-09-04-kavach360.md`

## History

- 2026-09-04: Reserved task 247 for the bounded independent real Flutter
  application acceptance campaign. No private application source or secrets
  copied into the Hyfens repository.
- 2026-09-04: Baseline and public CLI/MCP/local disposable-scope checks passed
  where possible. Public `0.1.1` exposed the original flavor-entrypoint defect;
  public `0.1.2` resolved flavor metadata but failed a real release with
  `T1605` because the published standalone archive omitted runtime packages.
  A minimum source fix was validated in a local diagnostic archive and pushed
  as `d7e2296`; no tag was moved or created. Both physical devices now detect,
  but final device acceptance remains blocked until a future public build.
  Temporary project tool state, signing key, and diagnostic IPA were removed;
  sanitized evidence updated.
- 2026-09-05: Task 253 resumed the same app's runtime-acceptance dependency.
  Project prerequisites were rechecked, not inferred from the older gates.
  Android's real `dev` target now builds with the existing non-production
  debug signing identity, and the APK signatures verify. Temporary signing
  properties were removed from the app. Version-preserving `pod install`
  changed only the Flutter podspec checksum in the lockfile; signed iOS
  `Release-dev` builds successfully. Existing unrelated private-app changes
  were preserved. Both physical devices are detected. No install or launch
  occurred, and these ordinary project builds are not Hyfens OTA evidence.
  Task 253 owns the reviewed next immutable CLI/runtime release; public
  `v0.1.2` remains unchanged. Physical patch capability remains pending the
  publicly installed accepted runtime and the no-reinstall campaign.
- 2026-09-05: Task 253 published immutable CLI/runtime v0.1.3 at `7d2c3ba`.
  All six public archive checksums match the release inventory. The public
  curl installation and Homebrew 0.1.3_1 installation both report 0.1.3;
  the latter preserves and tests the complete runtime package tree.
  Public CLI init persists the real app's dev/nested-entrypoint choice;
  subsequent ordinary doctor is READY on both platform resolutions without
  repeated selectors. No app source, global auth or pre-existing tracked
  changes were altered by init. The historical v0.1.2 release-bundle blocker
  is superseded by this new public distribution, not a rewritten tag.
  No Hyfens base has yet been installed and physical capabilities remain
  NOT_YET_PROVEN. Task 253 is preparing disposable non-billable receipt
  acceptance; legitimate app dev login and a private iOS transport route
  remain prerequisites. This does not claim managed-Cloud acceptance.
- 2026-09-05: Public v0.1.3 completes the actual instrumented Android dev
  APK build and release signature verification. Pre-install comparison finds
  the native dev identity has a suffix that Hyfens init/release omitted. No
  installation occurs. Task 253's bounded candidate regression reproduces the
  mismatch, repairs identity propagation and rejects stale bindings. Against
  the untouched private app, candidate doctor rejects the stale configuration;
  force-init dry run resolves the exact native APK identity without writing.
  This candidate is not public physical evidence and no tag is rewritten.
  Independent read-only baseline audit also finds ten narrow helper entries,
  zero widget factories and zero registered async capabilities. The intended
  workspace UI package is excluded as unknown-source; the normal CLI does not
  connect its lower-level widget ABI. Meaningful UI acceptance requires a
  separate bounded implementation decision within Task 253, not a string-only
  substitute or private-app rewrite. Physical support remains NOT_YET_PROVEN.
- 2026-09-05: Reviewed identity fix `65ce6c3` is on public main; all 181 CLI
  tests, analysis and installer checks pass. No new tag/assets are published.
  Task 253 private evidence is committed as `cc2a635` on the existing private
  feature branch only. Disposable delivery/control credentials and three
  recorded human sessions are revoked, and its services/database stopped.
  Four task-owned app paths move to protected recoverable storage; the built
  APK/signing evidence remains available and tracked private-app diff is
  unchanged. The Android transport disconnected before reverse-route removal
  could be confirmed; latest ADB inventory is empty. No app install, physical
  patch/receipt or rollback is claimed. Live billing remains OFF. Resume only
  after the broader runtime/UI integration boundary is explicitly resolved,
  with a new public binary and fresh scoped acceptance authority.
- 2026-09-07: Read-only recheck confirms Homebrew `hyfens 0.1.3_1` is the
  installed public binary. Its `hyfens init --dry-run --flavor dev` detects
  `com.kavach360.app.dev` but still proposes the legacy unflavored runtime
  binding, reproducing the unreleased identity gate without writing project
  state. Android remains visible through ADB; the iPhone is visible to Flutter
  but offline to Xcode. The only local profile is logged out and points at the
  disposable local control plane; no managed identity was used. No source,
  device, credential, release, tag, or deployment state was changed.
- 2026-09-07: Verified `65ce6c3` on public `origin/main`, prepared release
  metadata in the isolated release worktree, and published immutable public
  `v0.1.4` at `f1049a8`. The CLI and image workflows completed successfully;
  all six public CLI archives match `SHA256SUMS`, and the latest curl installer
  reports `hyfens 0.1.4`. MCP initialize/tool discovery reports server version
  `0.1.4`. The old `v0.1.3` tag and assets were not changed; Homebrew/Scoop
  remain independently published at `0.1.3`.
- 2026-09-07: Public `v0.1.4` init/doctor against the untouched private
  Kavach360 project automatically selected the Melos/Pub Workspace, `dev`
  flavor, nested `lib/src/flavors/dev.dart` entrypoint, and matching
  target-specific dev identities for Android and iOS. The signed Android dev
  release and signed iOS dev IPA were verified; CocoaPods deployment was
  consistent. Fresh probes then found both physical devices available. Each
  dev base was installed and launched once, with no Android reinstall after
  that point; the Android runtime reported healthy base AOT status after
  restart. No device identifiers, signing secrets, or customer credentials
  were recorded.
- 2026-09-07: A temporary, reversible async routing change was restored after
  the public `hyfens patch android` command failed closed with `F3010` for the
  baseline's incomplete Material icon evidence. `hyfens analyze` reports the
  same resource gate and the app's expected `P2001` exclusions for widget,
  state, and most async/native-shaped declarations. Focused resource,
  flavor, and discovery tests passed; no patch artifact, no-reinstall patch,
  rollback, or acceptance receipt was claimed. Asset/font/native/engine
  boundaries remain new-base-release cases. Temporary Hyfens config, trust
  keys, and signing properties were removed from Kavach360; its four
  pre-existing tracked diffs remain unchanged. Final disposition is
  `HYFENS INDEPENDENT REAL APP — PASS WITH BOUNDED GATES`; Task 253 retains
  trusted runtime settlement and commercial acceptance.
