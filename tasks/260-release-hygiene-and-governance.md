# Task 260 — Release hygiene and governance

Status: [x] Completed

## Goal

Clean up task-owned release/acceptance state, establish `CHANGELOG.md` as the
curated public release history, backfill factual GitHub Release descriptions,
and make release-candidate, release-note, and post-task cleanup requirements
durable without publishing a new Hyfens version.

## Scope and Non-goals

Scope:

- audit the public `v0.1.0` through `v0.1.9` tags, releases, artifacts,
  checksums, and supported distribution channels;
- preserve immutable tags and released binaries while correcting descriptive
  release metadata where needed;
- create the root changelog and a single release-governance checklist;
- add lightweight changelog/release-note extraction and release-workflow
  validation;
- add the permanent contributor/agent and cleanup rules;
- review and remove only Task 253-owned temporary worktrees and artifacts; and
- record the final bounded gates and clean-state evidence.

Non-goals:

- publishing `v0.1.10`, `v0.2.0`, or any other new product release;
- reopening Task 247 or changing Task 253 runtime/ABI implementation;
- moving tags, replacing artifacts/checksums, or rewriting release commits;
- starting trusted production receipts, Managed Cloud acceptance, Android
  signing, payment, asset/font OTA, desktop, or store work; and
- deleting unrelated developer changes, branches, worktrees, credentials, or
  historical task evidence.

## Owner

Release/governance coordinator

## Dependencies

- Public `origin/main` at the completed Task 253 line (`360fa29`).
- Public GitHub release metadata and release assets for `hyfens-hq/hyfens`.
- Existing CLI release workflow and distribution repositories.
- Repository contribution and documentation conventions.

## Assumptions

- `v0.1.0` through `v0.1.9` are the public stable releases; `v0.1.3_1`
  is not treated as a release unless public tag/release metadata proves it.
- GitHub Release descriptions may be corrected without changing tags, assets,
  checksums, or released source.
- The developer-owned dirty checkout remains outside this task's write scope.
- WinGet, if not publicly available, is an external distribution gate rather
  than a reason to publish a new version.

## Work Items

- [x] Inventory worktrees, branches, task-owned temporary artifacts, public
  tags, releases, assets, package channels, and current workflow behavior.
- [x] Create and validate the curated root `CHANGELOG.md` with a mandatory
  `[Unreleased]` section and factual `v0.1.x` history.
- [x] Add the release checklist, RC policy, pre-1.0 version policy, and
  contributor/agent release-hygiene rules.
- [x] Add tested release-note extraction and release-workflow enforcement
  without creating a competing workflow.
- [x] Backfill inadequate GitHub Release descriptions from the changelog
  without mutating immutable release content.
- [x] Remove only verified Task 253 temporary state, preserve unrelated work,
  review the combined diff, and validate the public-main change.
- [x] Record the final acceptance matrix, cleanup table, outcome, and next
  bounded product gates.

## Validation

Completed:

- `git ls-remote`, `git tag`, `gh release list/view`, and GitHub API asset
  inventory audited all public `v0.1.0` through `v0.1.9` releases. The remote
  tag refs and all 80 asset name/size records matched before and after notes
  backfill.
- `scripts/release_notes_test.sh` passed its existing, missing, empty,
  `[Unreleased]`, and Markdown-preservation cases.
- `bash -n`, `scripts/install-hyfens_test.sh`, `git diff --check`, Ruby YAML
  parsing, changed-Markdown relative-link checks, and the focused secret scan
  passed. `actionlint` was not installed in the environment.
- `cd cli && dart analyze` passed. The focused CLI process, release-packaging,
  and MCP tests passed. The full CLI suite completed with 189 passes and one
  pre-existing `deploy_runtime_e2e_test.dart` control-plane bootstrap timeout;
  no governance test failed.
- Public channel probes reported GitHub/curl, Homebrew, and Scoop at `0.1.9`,
  and the installed external-user binary reported `hyfens 0.1.9`.
- Final remote tag, release description, release-asset, public-main, and
  task-owned-worktree checks passed.

## Next Action

No further action is required in this finite cleanup milestone. Select the
next product gate deliberately; candidate follow-up areas are trusted
production receipt settlement, disposable Managed Cloud acceptance, or
Android project signing. Do not start one automatically from this task.

## Blockers

The public release process retains the external WinGet publication/catalog
gate. The full CLI suite also retains the pre-existing control-plane bootstrap
timeout described under Validation; it is unrelated to this cleanup change.

## Cleanup table

| Item | Repository | State | Action | Final State |
| --- | --- | --- | --- | --- |
| Primary checkout | `hyfens` | Dirty with developer/private work | Preserved without reset or clean | Unrelated changes remain intact |
| Task 253 async worktree/branch | `hyfens` | Clean at `360fa29`, already on `origin/main` | Removed worktree and deleted disposable local branch | Cleaned; commits remain public |
| Earlier `v0.1.4` release worktree/branch | `hyfens` | Clean at immutable `f1049a8` | Removed worktree and deleted disposable local branch | Cleaned; tag remains unchanged |
| Stale prunable worktree records | `hyfens` | Paths absent | Pruned metadata only; retained feature branches | Cleaned without branch deletion |
| Task 253 distribution clones | Homebrew/Scoop | Remote-synchronized; only `.DS_Store` untracked | Moved exact clones to Trash | Recoverable and absent from `/private/tmp` |
| Prior Hyfens/Kavach acceptance artifacts | Temporary workspace | Disposable archives, JSON/text evidence, key, and rollback controls | Moved 84 exact named paths to Trash | Recoverable and absent from `/private/tmp` |
| Cleanup worktree | `hyfens` | Task-owned isolated branch | Retained until final push/verification | Clean and ready for removal |

## Release history audit

| Public release | Immutable source | Existing GitHub notes | Changelog/metadata action |
| --- | --- | --- | --- |
| `v0.1.0` | `4982ab5` | Meaningful | Preserved; factual history backfilled |
| `v0.1.1` | `389fc71` | Meaningful | Preserved; factual history backfilled |
| `v0.1.2` | `ceb2b41` | Generic compare link | Replaced description from `CHANGELOG.md` |
| `v0.1.3` | `7d2c3ba` | Meaningful | Preserved; factual history backfilled |
| `v0.1.3_1` | No tag or release | Absent | Not a published version; no tag or note created |
| `v0.1.4` | `f1049a8` | Generic compare link | Replaced description from `CHANGELOG.md` |
| `v0.1.5` | `dc55287` | Generic compare link | Replaced description from `CHANGELOG.md` |
| `v0.1.6` | `ec93350` | Generic compare link | Replaced description from `CHANGELOG.md` |
| `v0.1.7` | `17eb3d8` | Generic compare link | Replaced description from `CHANGELOG.md` |
| `v0.1.8` | `f6280b4` | Generic compare link | Replaced description from `CHANGELOG.md` |
| `v0.1.9` | `97f2615` | Generic compare link | Replaced description from `CHANGELOG.md` |

## Outcome

**HYFENS RELEASE GOVERNANCE — COMPLETE WITH EXTERNAL GATES**

`CHANGELOG.md` is now the curated release-notes authority with a mandatory
`[Unreleased]` section. The existing CLI workflow validates the target
changelog section and publishes its non-empty extracted notes; the image
workflow validates the same release section. A single release guide defines
`PREPARING` → `RC` → `PUBLISHED` → `VERIFIED`, pre-1.0 versioning, immutable
tags, distribution verification, and cleanup. Recent generic GitHub release
descriptions were backfilled without changing tags, source commits, assets, or
checksums. No new version was tagged or published.

The public main branch contains the governance batch. The developer-owned
dirty checkout and unclear-ownership feature branches were preserved. WinGet
remains an external distribution gate; no trusted production receipt,
Managed-Cloud, Android-signing, payment, asset/font OTA, desktop, or store work
was started.

## Acceptance Matrix

| Gate                                    | Required |
| --------------------------------------- | -------- |
| Task 253 task-owned cleanup             | PASS     |
| Temporary worktrees reviewed            | PASS     |
| Committed/unpushed work reviewed        | PASS     |
| Unrelated developer changes preserved   | PASS     |
| Release tags unchanged                  | PASS     |
| Release assets unchanged                | PASS     |
| CHANGELOG.md authoritative              | PASS     |
| `[Unreleased]` section                  | PASS     |
| v0.1.x history audited                  | PASS     |
| Recent release notes backfilled         | PASS     |
| GitHub release descriptions present     | PASS     |
| Release checklist                       | PASS     |
| RC policy                               | PASS     |
| Pre-1.0 version policy                  | PASS     |
| Changelog agent rule                    | PASS     |
| Release-note agent rule                 | PASS     |
| Post-task cleanup rule                  | PASS     |
| Post-release cleanup rule               | PASS     |
| Release workflow changelog check        | PASS     |
| Empty release-note prevention           | PASS     |
| Release-note extraction automation      | PASS     |
| Docs navigation current                 | PASS     |
| Historical docs separated appropriately | PASS     |
| Secret scan                             | PASS     |
| Markdown links                          | PASS     |
| Public main updated                     | PASS     |
| No new tag                              | PASS     |
| Final task-owned worktree clean         | PASS     |

## References

- `CONTRIBUTING.md`
- `.github/workflows/release-cli.yml`
- `scripts/cli-release/`
- `docs/runtime/patch-capabilities.md`
- `CHANGELOG.md`
- `docs/releases/releasing.md`
- `scripts/release_notes.sh` and `scripts/release_notes_test.sh`
- `https://github.com/hyfens-hq/hyfens/releases`
- `tasks/253-flutter-patch-abi-expansion.md` (completed public Task 253 record)

## History

- 2026-09-07 — Reserved task number 260 after inspecting the workspace task
  namespace. Created an isolated worktree from `origin/main`; the primary
  checkout's unrelated dirty changes remain preserved.
- 2026-09-07 — Completed the cleanup, release-history audit, changelog
  backfill, GitHub release-description backfill, governance documentation,
  workflow enforcement, and task-owned temporary-state cleanup. No stable tag
  was created.
