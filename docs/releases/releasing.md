# Hyfens release process

This is the single release-process checklist for the public repository. The
curated user-facing source is [`CHANGELOG.md`](../../CHANGELOG.md); GitHub
Release descriptions are generated from its version section by
[`scripts/release_notes.sh`](../../scripts/release_notes.sh).

## Release states

Use these process states in order:

`PREPARING` → `RC` → `PUBLISHED` → `VERIFIED`

`PUBLISHED` means the immutable tag, release archives, checksums, and release
metadata exist. `VERIFIED` additionally means the supported installation
channels and post-release checks have completed. A tag alone is never a
completed release.

## Version policy

Hyfens uses semantic versions during the pre-1.0 phase:

- `0.x.y` `x` marks a meaningful feature, protocol, or product-capability
  milestone.
- `0.x.y` `y` marks backward-compatible fixes and smaller enhancements within
  that milestone.
- Use `0.1.10`, rather than changing the version format, for the next
  compatible fix in the current `0.1` capability line.
- A meaningful new capability boundary may advance the minor component under
  the same pre-1.0 policy.

Do not choose a next version merely to close a cleanup task. Keep the work in
`[Unreleased]` until an actual product scope is ready.

## Release-candidate flow

For changes affecting a public release surface, validate a candidate before a
stable tag:

1. Select the version and review `[Unreleased]`.
2. Freeze candidate notes and create a compatible prerelease such as
   `0.1.10-rc.1`, or use a candidate artifact identified by commit SHA.
3. Run the relevant unit/integration tests, real-app compatibility checks,
   physical-device checks, archive builds, checksums, installer smoke, MCP
   smoke, self-host regression, and package-manager rehearsal.
4. Resolve candidate defects as `rc.2`, or another candidate, without
   publishing a normal stable version for acceptance debugging.
5. Review the final release notes, migration notes, known limitations, and
   distribution artifacts.
6. Publish one immutable stable release only after the candidate passes.

Stable releases should represent a coherent accepted change set. Urgent
security or data-loss fixes may use an immediate patch release.

## Stable release checklist

- [ ] Version selected and `cli/pubspec.yaml` matches the intended tag.
- [ ] `CHANGELOG.md` `[Unreleased]` reviewed and the release section created.
- [ ] Human-readable release notes prepared from that changelog section.
- [ ] Relevant tests and RC acceptance pass.
- [ ] Native archives build for all supported targets.
- [ ] Checksums and artifact inventory pass.
- [ ] `hyfens --version`, `--help`, and `hyfens mcp --help` pass.
- [ ] MCP initialize/tool discovery and self-host regression pass.
- [ ] Curl installer rehearsal passes.
- [ ] Homebrew rehearsal passes where the tap is available.
- [ ] Scoop artifact/manifest rehearsal passes where the bucket is available.
- [ ] WinGet status is explicitly classified; Microsoft publication remains an
  external gate until it is available.
- [ ] Tag is signed, pushed, and verified remotely.
- [ ] GitHub Release is published with the changelog-derived notes and all
      expected artifacts.
- [ ] Release-note and documentation links are valid.
- [ ] Post-release public install and distribution versions are verified.
- [ ] Temporary release worktrees and artifacts are removed.
- [ ] The task-owned repository state is clean.

The existing `.github/workflows/release-cli.yml` stops before archive
publication when the target version has no changelog section, and creates the
GitHub Release only with a non-empty extracted notes body. The image workflow
performs the same version-section check for stable image tags.

## Release notes and compatibility

Every stable GitHub Release must contain meaningful human-readable notes. The
notes must include, when relevant:

- what is new or fixed;
- compatibility or migration requirements;
- known limitations and external gates; and
- installation or upgrade guidance.

Call out patch-format/runtime-ABI changes, old-base compatibility, CLI flag or
configuration migrations, and self-host upgrade requirements. Do not expose
private application identifiers, endpoints, credentials, signing material, or
commercial implementation details. New or changed assets/fonts, native
plugins/configuration, and engine changes remain new-base boundaries unless a
future release explicitly changes that contract.

Container images have their own workflow. Stable image tags must map to the
matching product release and retain human-readable release context, without
turning nightly image publication into a CLI changelog release.

## Immutable releases

Never move or rewrite a published stable tag, replace its released binaries, or
silently change checksums. Corrected software ships in a new version. GitHub
Release descriptions may be corrected or expanded when the released software,
tag, assets, and checksums remain unchanged.

## Cleanup and closure

Before closing a task, inspect task-created worktrees, branches, generated
artifacts, temporary credentials, device configuration, and Git state. Remove
only task-owned temporary state; preserve unrelated developer work. Resolve or
explicitly record completed changes that are committed but not pushed or
merged.

After every public release, verify the remote tag, release notes, artifacts,
checksums, supported installation channels, and public install. Remove
temporary release artifacts/worktrees, leave the task-owned state clean, and
reset `[Unreleased]` for future work.

## Related documentation

- [CLI installation and distribution](../cli-distribution.md)
- [Patch capabilities](../runtime/patch-capabilities.md)
- [Self-hosted operations](../../deploy/self-hosted/README.md)
