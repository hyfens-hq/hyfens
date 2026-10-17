# Task 305 — Publish project handover CLI test release

Status: [*] In Progress

## Goal

Make Task 304's project handover command available as an installable CLI test
release and submit the source through a pull request.

## Scope and Non-goals

Scope: CLI version metadata, release notes, version-sensitive tests, full CLI
validation and a native host archive, a signed-off commit and PR, an annotated
prerelease tag, hosted CLI archive publication, necessary release SDK provisioning fixes, and
downloaded archive checks.

Non-goals: server deployment, modifying server/runtime behavior, stable
upgrade promotion, package-manager repository updates, importing historical
branches, and bypassing the required independent PR approval.

## Owner

Hyfens release maintainer (single workstream).

## Dependencies

- Completed Task 304 on `feat/project-handover-rebind`.
- Existing GitHub CLI release workflow and authenticated repository access.
- Compatible Flutter/Dart SDK and native macOS arm64 build tools.
- GitHub-hosted builders for the other platform archives.

## Assumptions

- The request authorizes committing, pushing, opening a PR, and publishing
  the CLI release needed to test the change.
- Latest stable is `v0.1.10`; `v0.1.11-rc.1` is an opt-in test release.
- Current main is the intentionally sanitized public snapshot, materially
  different from the historical stable tag; restoring removed history or
  silently replacing the stable distribution is outside this requirement.
- Main requires an independent approval. A release candidate can be tagged
  from the feature branch without bypassing main's merge rule.
- The existing tag trigger also starts the image workflow; cancel that run
  because this requirement changes the CLI and needs no server image release.

## Work Items

- [x] Set the CLI package and reported version to `0.1.11-rc.1`, update
  version-dependent checks, and document the handover test release.
- [x] Review the release diff and run the full CLI suite, scoped analysis,
  root repository check, OSS boundary scan, and native host build/smoke check.
- [x] Commit with DCO sign-off, push, and open a PR with exact validation
  evidence and known source-baseline limitations.
- [*] Push the annotated prerelease tag and monitor the CLI workflow through
  publication; keep server image/deployment work outside the release.
- [ ] Verify published assets, checksums, provenance when available, reported
  version, and `init --rebind` help from the downloaded host archive.
- [ ] Record PR/release links, evidence, and remaining independent review.

## Validation

Before publication: `dart format` on changed Dart files, `dart analyze` on
changed CLI source/tests and release scripts, full `dart test --concurrency=2`
from `cli/`, root `dart test`, `scripts/check-oss-boundary.sh`, and
`git diff --check`. Use the existing release builder for a macOS arm64 archive
outside the repository, then smoke check the extracted executables.

After publication: inspect the GitHub workflow outcome, all six archive names
plus checksums/inventory, download the macOS arm64 archive, verify checksums
and GitHub attestations, and execute `--version` and `init --help`.

Local evidence on 2026-10-17:

- Changed-source/test/release-script analysis passed with no issues; scoped
  formatting and `git diff --check` passed.
- Full CLI suite completed: 175 passed, one failure in
  `test/release_overlay_plugin_test.dart`. The failure is `T1603` with Android
  Gradle Plugin 9.1/Kotlin DSL classpath errors (`BaseAppModuleExtension` and
  `KotlinAndroidProjectExtension`). A fresh detached worktree of unchanged
  main `59d232d`, with locked dependencies resolved, reproduces the same
  failure. No unrelated native build fix or skipped assertion was introduced.
- Root repository test passed (1); OSS boundary scan passed.
- Existing release builder produced the macOS arm64 archive, including both
  `hyfens` and the compatibility `tool` executable plus the native dylib.
- Extracted native executable smoke passed: reported `0.1.11-rc.1`, advertised
  `--rebind`, planned a dry-run without writes, rebound a disposable project
  to recipient identifiers, and preserved every file except `hyfens.yaml`.
- Release notes disclose the reproduced native Android baseline failure and
  the difference from historical stable source. Full repository packages and
  unrelated platform matrices were not rerun for this CLI-only release.

## Next Action

Fix the ARM SDK provisioning failure, validate the release-only revision, and
publish `v0.1.11-rc.2` without moving the first tag or bypassing main review.

## Blockers

Independent eligible review is required for main integration. It does not
prevent an explicitly opt-in release candidate from being used for testing.
The reproduced Android native overlay failure remains a separate compatibility
limitation; it is disclosed rather than reported as a passing check.

## Outcome

Pending release preparation and publication.

## References

- `tasks/304-project-handover-rebind.md`
- `docs/cli-distribution.md`
- `.github/workflows/release-cli.yml`
- `.github/workflows/release-checks.yml`
- `CONTRIBUTING.md`

## History

- 2026-10-17: User requested an installable CLI release and deployment only
  if server changes were necessary. Confirmed that this feature changes the
  CLI only, checked the latest published tag and main protection, and selected
  an opt-in prerelease from the feature branch.
- 2026-10-17: Prepared consistent CLI/package version metadata and dynamic
  packaging checks. Completed local validation and native archive smoke;
  reproduced the only full-suite failure on unchanged main and disclosed it.

- 2026-10-17: Pushed signed-off commit `3daa4f2`, opened PR #29, and tagged
  `v0.1.11-rc.1`. Hosted preflight and Linux x64/macOS arm64 builds passed;
  Linux/Windows ARM setup failed because flutter-action has no matching bundled
  Flutter archive. Cancelled the unrelated server image run. Use pinned Flutter
  source bootstrap only on those ARM hosts and issue a new `rc.2` tag.

- 2026-10-17: Reviewed the release-only correction. Workflow YAML parses and
  `git diff --check` passes; scoped Dart analysis reports no issues. The ARM
  bootstrap uses Flutter 3.47.1 pinned at `6655482`, preserves native SDK
  selection, and leaves all other platform setup unchanged. Hosted native
  matrix builds will validate the unavailable local ARM platforms.
- 2026-10-17: All 16 affected packaging/process checks passed for rc.2.
  The first rc.2 test invocation used the root working directory and found no
  matching test files; reran from `cli/` successfully. No behavior changed
  since the full CLI validation recorded above.
