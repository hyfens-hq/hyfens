# Task 253 — Real Flutter runtime ABI and patchability expansion

Status: [*] In Progress

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

- `v0.1.4` and earlier public tags remain immutable; the next release is a new
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
- [ ] Publish a new immutable public release and update supported package
  channels.
- [ ] Reinstall the public binary and complete the finite Kavach360 physical
  acceptance campaign, classifying device/project/external gates.
- [ ] Record the final outcome and leave Kavach360 restored.

## Validation

Planned and required commands are scoped to the changed packages and release
boundary:

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

## Next Action

Publish the validated `0.1.9` candidate as one new immutable public release,
install that public binary, complete the iPhone Patch B/restart/rollback
evidence, classify the Android/receipt/managed-Cloud gates, and restore the
private acceptance app.

## Blockers

At creation, public runtime release and final physical acceptance are pending.
Managed Cloud identity is an external gate and must not be substituted with a
production or personal commercial account. Android/iOS project and device
status must be re-probed after the public release.

## Outcome

The bounded ABI/resource implementation, candidate Kavach360 acceptance, and
consolidated repository validation are complete. Public release,
public-binary Kavach360 acceptance, and final device/external-gate
classification remain in progress.

## Acceptance Matrix

| Gate                             | Required |
| -------------------------------- | -------- |
| P2001 rules audited              | PASS |
| Widget build support             | PASS |
| BuildContext support             | PASS |
| Stateful method behavior         | PASS |
| Callback/closure support         | PASS |
| Async/Future support             | PASS |
| Routing callback support         | PASS |
| Animation representative support | PASS |
| Field-layout unsafe change       | NEW_BASE_RELEASE |
| Resource evidence completeness   | PASS |
| Existing Material-icon reference | PASS |
| New icon glyph absent from base  | NEW_BASE_RELEASE |
| Existing asset reference         | PASS |
| Asset mutation                   | NEW_BASE_RELEASE |
| New asset                        | NEW_BASE_RELEASE |
| Font mutation/new font           | NEW_BASE_RELEASE |
| Native plugin/config             | NEW_BASE_RELEASE |
| Engine mismatch                  | NEW_BASE_RELEASE |
| Compatibility analyzer           | PASS |
| Analyze/patch parity             | PASS |
| MCP compatibility output         | PASS |
| Kavach360 Patch A                | PENDING |
| Kavach360 Patch B                | PENDING |
| Kavach360 Patch C                | PENDING |
| Android no-reinstall             | PENDING |
| iOS no-reinstall                 | PENDING |
| Restart persistence              | PENDING |
| Rollback                         | PENDING |
| Physical acceptance receipt      | PENDING |
| Receipt dedup                    | PENDING |
| Public runtime release           | PENDING |
| Public CLI reinstall             | PENDING |
| Capability docs                  | PASS |

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
