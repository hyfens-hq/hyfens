# Task 251 — Smart Flutter Project Discovery and README Onboarding

Status: [x] Completed

## Goal

Make automatic Flutter project, flavor, entrypoint, and workspace discovery the
default Hyfens CLI experience, with safe ambiguity handling and a simple,
accurate developer README.

## Scope and Non-goals

Scope is the public CLI discovery seam, persisted safe project selection,
focused discovery fixtures/regressions, current CLI help/diagnostics, and the
root README onboarding flow. The existing release/patch lifecycle and public
API contracts remain compatible.

Non-goals: changing Kavach360 source, dashboard work, backend redesign,
private Cloud work, a new Hyfens release tag while the immutable `v0.1.2`
release boundary is unresolved, desktop support, or a second acceptance task.

## Owner

Release/tooling coordinator.

## Dependencies

- Existing `cli/lib/src/project.dart` and `HyfensProjectBinding` contracts.
- Existing flavor-aware release/patch metadata in `toolchain.dart`.
- Public OSS branding assets and current documentation policy.
- Task 247 remains the real-application acceptance record.

## Assumptions

- `--project` remains the single explicit project-directory selector.
- `tool.yaml` remains the legacy instrumentation/build configuration; safe
  discovery selections are stored in `hyfens.yaml`.
- Ambiguous non-interactive invocations fail closed with actionable codes.
- The already-published `v0.1.2` tag is immutable; release publication is
  considered only after the candidate passes and a valid release boundary
  exists.

## Work Items

- [x] Inspect current discovery, configuration, command, fixture, branding,
  and release boundaries.
- [x] Implement one reusable project/workspace/flavor/entrypoint resolution
  model consumed by doctor, init, release, patch, and analyze.
- [x] Add focused fixture coverage for single apps, flavors, custom targets,
  invalid/export-only entrypoints, Melos/Pub workspaces, multi-app selection,
  persisted selection, and release/patch consistency.
- [x] Validate automatic resolution against Kavach360 without modifying its
  source.
- [x] Simplify and validate the root README, including existing logo asset,
  quickstart, flavors, Melos, Cloud/self-host, MCP, and bottom license.
- [x] Run consolidated analysis, tests, build/release rehearsal, secret scan,
  and diff review; keep Task 247 unchanged because no public fixed binary was
  installed and no physical acceptance was resumed.
- [x] Decide whether public release work is possible without mutating `v0.1.2`.

## Validation

Validation completed:

- `dart format` on changed Dart sources: PASS.
- `dart analyze`: PASS.
- Discovery, help, and toolchain regression suites: PASS.
- `dart test --concurrency=1`: PASS, 158 tests.
- Kavach360 read-only `doctor --json`: PASS; detected the `melosAndPubWorkspace`
  workspace, `apps/kavach360`, Android/iOS identities, and the four native
  flavors without reading or changing private source. With no persisted choice,
  the intended `T1304 NEEDS_SELECTION` result was returned rather than guessing.
- Non-interactive ambiguity smoke: PASS; multiple applications fail with
  actionable `T1302`.
- CLI version/archive rehearsal for `0.1.2`: PASS, including packaged binary,
  runtime bundle, help, and checksum generation.
- Installer smoke (`bash scripts/install-hyfens_test.sh`): PASS.
- MCP regression, secret checks, `git diff --check`, and changed-file review:
  PASS.

Physical Task 247 acceptance was not resumed because final evidence must use a
public binary and the required discovery changes are after the immutable
published `v0.1.2` tag.

## Next Action

Review the isolated implementation and publish it only under a new valid
release boundary; then install that public binary before resuming Task 247.

## Blockers

The immutable published `v0.1.2` tag points to `ceb2b410...` and predates this
implementation branch. Publishing the new behavior as
`v0.1.2` would require mutating a release, which is prohibited. No new
`v0.1.3` release was authorized in this task. Consequently public CLI
reinstallation and physical Task 247 acceptance remain bounded follow-up
gates. Kavach360's four-flavor, unpersisted state correctly remains
`NEEDS_SELECTION` until its normal `hyfens init` selection is made; no private
project files were changed.

## Outcome

`HYFENS SMART PROJECT DISCOVERY — COMPLETE WITH BOUNDED GATES`.

Hyfens now shares one discovery model across doctor, init, release, patch,
analyze, and MCP. It detects valid executable entrypoints (including
export-only-main rejection), Android/iOS flavor metadata, custom targets,
Melos/Pub workspaces, multiple applications, project-pinned toolchain hints,
and safe persisted selections. Ambiguity and stale/moved selections fail
closed. The root README is now a short branded developer onboarding path.

## References

- `tasks/247-independent-real-flutter-app-acceptance.md`
- `docs/research/evidence/independent-real-app/2026-09-04-kavach360.md`
- `docs/cli.md`
- `docs/cli/project-discovery.md`
- `README.md`
- `cli/lib/src/project.dart`
- `cli/lib/src/configuration.dart`

## History

- 2026-09-04: Reserved Task 251 and began implementation in isolated
  worktree `/tmp/hyfens-smart-discovery` from `origin/main`.
- 2026-09-04: Completed the discovery, workspace, target-consistency, README,
  archive-rehearsal, and serial-validation batch. Kept the immutable
  `v0.1.2` release unchanged and left Task 247 pending a future public binary.
