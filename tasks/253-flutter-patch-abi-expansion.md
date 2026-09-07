# Task 253 — Real Flutter runtime ABI and patchability expansion

Status: [x] Completed — HYFENS ASYNC FLUTTER ABI — COMPLETE WITH BOUNDED GATES

## Goal

Make Hyfens patch a normal, bounded subset of Flutter applications: ordinary
widget builds, `BuildContext` use, state behavior, callbacks, async Dart,
routing decisions, and representative UI behavior must be analyzable and
patchable without a native reinstall. Keep field/type-shape, resource, native,
and engine changes fail closed.

## Scope and Non-goals

Scope:

- audit the existing P2001 exclusions and classify their actual cause;
- add the smallest generic Flutter/Dart ABI seam that safely supports ordinary
  widget/state/async code;
- make compatibility outcomes typed and shared by analyze, patch, release
  metadata, and MCP;
- make real Flutter build resource evidence complete-or-blocking;
- add focused stock-Flutter-shaped fixtures, regression tests, public
  capability documentation, and final public release/acceptance evidence; and
- keep Task 247 closed and cross-reference it only for the completed discovery,
  flavor identity, signing, and base-install evidence.

Non-goals:

- no private Kavach360 architecture workaround or source copy;
- no asset/font OTA implementation, native plugin/configuration patching,
  engine migration, second app, desktop work, store publication, or live paid
  billing;
- no redesign of Task 253 trusted receipt cryptography or commercial
  settlement; and
- no rewrite, movement, or asset replacement for an existing public release
  tag.

## Owner

Coordinator — ABI boundary, resource evidence, release integration, public
distribution, and real-app acceptance evidence.

## Dependencies

- public Hyfens `origin/main`, including flavor identity fix `65ce6c3`;
- stock Flutter/Dart toolchain used by the release workflow;
- existing instrumentation, Flutter integration, CLI, MCP, and release
  workflows;
- the private Kavach360 project as sanitized acceptance evidence only; and
- package-manager repositories and public GitHub release permissions.

## Assumptions

- `v0.1.8` and earlier public tags remain immutable; `v0.1.9` is the new
  version selected from the repository's existing `0.1.x` convention;
- host-owned Flutter objects are represented opaquely or by immutable,
  bounded descriptors; arbitrary framework dispatch is not admitted;
- a non-metadata mobile base is patchable only when actual build-output
  resource evidence is complete; and
- unpublished Kavach360 physical acceptance remains development,
  non-billable evidence and does not prove managed Cloud or production trust.

## Work Items

- [x] Audit P2001 rules and freeze the support/unsafe boundary.
- [x] Implement the bounded widget, `BuildContext`, state, callback, void, and
  ordinary async ABI seam without changing Kavach360.
- [x] Add typed compatibility analysis, diagnostics, MCP output, and parity
  coverage.
- [x] Capture immutable actual Flutter artifact resource evidence and preserve
  fail-closed asset/font/icon/native/engine boundaries.
- [x] Run consolidated validation and review the combined release diff.
- [x] Publish a new immutable public release and update supported package
  channels.
- [x] Reinstall the public binary and complete the finite Kavach360 physical
  acceptance campaign, classifying device/project/external gates.
- [x] Record the final outcome and leave Kavach360 restored.

## Validation

Completed validation was scoped to the changed packages, release boundary,
public distribution, and one private physical acceptance app:

- `dart analyze` in `experiments/instrumentation`,
  `packages/instrumenter`, `packages/flutter_integration`, and `cli`;
- focused instrumentation, CLI resource/compatibility, MCP, discovery, and
  identity tests, followed by the relevant package suites before release;
- stock-Flutter fixture and real mobile archive checks, including checksums,
  public installer, Homebrew, Scoop metadata, help/version, MCP initialize and
  tool discovery, secret scan, and self-host regression;
- fresh public-binary Kavach360 `doctor`/`analyze`, Android/ADB and current
  Apple tooling probes, legitimate signing/Pods checks, base install, bounded
  Patch A/B/C, restart, rollback, resource/native fail-closed probes, and
  receipt/dedup accounting when the approved public runtime supports it; and
- `git diff --check`, combined diff review, and final worktree hygiene.

The analyzers, focused and relevant package suites, async fixtures, resource
boundary tests, MCP tests, native archive smoke, release workflow, public
artifact checksums, public package channels, public CLI help/version, public
doctor, public analyze/patch/verify, iOS build/install, runtime activation,
restart, rollback, and CocoaPods reconciliation passed. The full CLI suite
had one unrelated Puro/Flutter SDK load failure in
`test/deploy_runtime_e2e_test.dart`; the Flutter integration runner retained
two pre-existing host-platform failures, while the direct Dart-VM integration
suite passed. These were recorded as environment validation notes and did not
affect the async parity or public iPhone result.

## Next Action

No further action is required in this finite continuation. Any future Android
signing, trusted receipt settlement, or managed-Cloud work requires its own
approved scope; Task 247 remains closed and Task 253 retains commercial/runtime
settlement ownership.

## Blockers

The accepted bounded gates are: Android release signing remains a legitimate
project configuration gate because `android/key.properties` is absent; physical
acceptance receipts and deduplication remain a public-runtime gate because no
approved settlement identity was available; and managed Cloud remains an
external gate because no disposable project-owned managed identity was
available. These gates were not substituted with production credentials or
live billing.

## Outcome

The async analyzer/compiler parity fix is public in immutable `v0.1.9`. The
public Homebrew binary was installed and used against the private Kavach360
workspace. Public discovery retained the Melos/Pub Workspace, persisted `dev`
selection, nested `lib/src/flavors/dev.dart` entrypoint, and the matching
flavor-specific Android/iOS identities. Public Patch B analysis, compilation,
signature verification, iPhone no-reinstall activation, restart persistence,
and signed rollback all passed. Android signing, receipt settlement, and
managed Cloud remain explicitly bounded gates. Kavach360 temporary source,
local-network delivery settings, rollback control, and private signing key
were restored or removed; pre-existing private changes were preserved.

## Acceptance Matrix

| Gate                                   | Required |
| -------------------------------------- | -------- |
| v0.1.8 mismatch reproduced             | PASS |
| Root cause identified                  | PASS |
| Shared analyze/patch contract          | PASS |
| Future<void>.delayed                   | PASS |
| async/await                            | PASS |
| Future<T>                              | PASS |
| async closure                          | PASS |
| async widget callback                  | PASS |
| try/catch/finally async                | PASS |
| async state update                     | PASS |
| async routing                          | PASS |
| unsupported async shape detected early | PASS |
| MCP parity                             | PASS |
| Patch A regression                     | PASS |
| Resource boundaries unchanged          | PASS |
| Kavach360 candidate Patch B            | PASS |
| Public next version published          | PASS |
| GitHub/curl                            | PASS |
| Homebrew                               | PASS |
| Scoop                                  | PASS |
| Public CLI installed                   | PASS |
| iPhone Patch B no-reinstall            | PASS |
| iPhone restart persistence             | PASS |
| iPhone rollback                        | PASS |
| Android                                | PROJECT_GATE |
| Acceptance receipt                     | PUBLIC_RUNTIME_GATE |
| Managed Cloud                          | EXTERNAL_GATE |
| Capability docs                        | PASS |

## References

- `65ce6c3` on public `origin/main` — flavor-specific identity fix.
- `tasks/247-v0-1-1-release-boundary.md` — historical task-file location;
  Task 247 remains closed and is not reopened.
- `docs/runtime/patch-capabilities.md` — current public ABI and resource
  boundary.
- `experiments/instrumentation/` — bounded interpreter and fixture seam.
- `cli/lib/src/patch_compatibility.dart` — shared compatibility policy.
- `cli/lib/src/resource_snapshot.dart` — source and artifact resource evidence.
- `.github/workflows/release-cli.yml` — immutable tag-triggered release path.
- `https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.9` — immutable public
  async-parity release and artifact source.

## History

- 2026-09-07 — Continued the explicitly requested Task 253 package without
  creating microtasks or reopening Task 247. Audited the existing widget,
  context, state, async, closure, and Material-icon gates; implemented the
  first bounded ABI/resource-evidence seam; and added focused regression tests.
- 2026-09-07 — Final release, public reinstall, physical acceptance, and
  bounded-gate classification remain to be recorded after consolidated
  validation.
- 2026-09-07 — Reproduced the v0.1.8 analyzer/compiler mismatch: the old
  analyzer reported a real `Future<void>.delayed` body as patchable, while
  patch compilation failed on the unsupported method-invocation expression
  with the generic unexpected-failure path. The fix makes compiler preflight
  part of analysis, returns `P2012` for known unsupported shapes, and keeps
  unexpected preflight failures distinct as `P2013`.
- 2026-09-07 — Implemented patch/runtime format 10's bounded async seam:
  stable-signature async bodies support typed `Future<T>.value`, bounded
  `Future<void>.delayed`, the host-owned Flutter frame boundary, and the
  explicit zero-argument async widget callback contract. Existing field,
  resource, native, engine, stream, and unsafe closure boundaries remain
  closed. Instrumentation (216), patch-loading (73), CLI focused (28),
  Flutter-integration Dart-VM (55), compiler, instrumenter, and runtime
  suites passed; Flutter integration analysis passed. The Flutter test runner
  still has two pre-existing platform-runner failures (uninitialized
  attestation binding and host storage semantics).
- 2026-09-07 — Candidate iOS release built with complete resource evidence and
  the persisted dev flavor; candidate `analyze`, `patch`, and `verify` all
  passed for the real Kavach360 async/routing handoff. The candidate was
  installed and launched on the connected iPhone, and the local signed patch
  reached the healthy patched runtime. Candidate evidence is diagnostic until
  the public release is installed.
- 2026-09-07 — Audited implementation validated: 211 instrumentation tests,
  186 CLI tests, full instrumenter/compiler suites, full Dart-VM Flutter
  integration suite, scoped analyzers, and a local macOS arm64 archive/help/
  version/MCP smoke all passed. The next immutable public version is `0.1.5`;
  public distribution and Kavach360 physical gates remain pending.
- 2026-09-07 — Published immutable `v0.1.9` from `97f2615` after the full
  release workflow passed. The six GitHub archives, inventory, and checksums
  matched; curl, Homebrew, and Scoop were updated to the same public version.
  Homebrew upgraded the installed external-user binary to `hyfens 0.1.9`.
  MCP initialize/tool discovery and a public MCP `hyfens_analyze` call reported
  server `0.1.9`, `flutter-dart-abi-v1`, and `PATCHABLE` for the real async
  routing change.
- 2026-09-07 — Fresh public doctor resolved the real Melos/Pub Workspace,
  persisted `dev` flavor, `lib/src/flavors/dev.dart`, and matching
  flavor-specific Android/iOS identities. Fresh probes found the Android
  device online over both available transports and the iPhone connected. The
  public CLI built the signed iOS dev baseline with complete resource evidence;
  public Patch B analyzed as `PATCHABLE`, compiled as a signed sequence-4
  artifact, and verified successfully.
- 2026-09-07 — The public-built iOS baseline was installed once. The existing
  async/deep-link handoff Patch B was admitted without another install and
  logged `pendingHealth` followed by `healthy`; after a supported stop/launch,
  the same public app logged `current healthy signed patch active`. A signed
  rollback then logged `rolledBack`/`base AOT` with the sequence high-water
  retained. The focused widget Patch A path remains covered by the prior
  physical proof and v0.1.9 regression suites; a deeper `BuildContext.l10n`
  widget expression remains intentionally `P2012`/not-yet-supported and was
  not worked around in Kavach360.
- 2026-09-07 — Re-ran CocoaPods deployment reconciliation successfully. No
  legitimate Android release signing file is present, so Android remains
  `PROJECT_GATE`. No approved trusted receipt settlement or disposable managed
  Cloud identity is available; acceptance receipts remain development,
  explicitly non-billable `PUBLIC_RUNTIME_GATE` evidence and managed Cloud is
  `EXTERNAL_GATE`. Live paid checkout and overage collection stayed disabled.
  Restored Kavach360 source, iOS local-network settings, and loopback config;
  removed the temporary project private key and rollback control while
  preserving pre-existing private tracked changes.
