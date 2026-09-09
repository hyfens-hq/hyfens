# Hyfens v0.1.1 release-boundary reconciliation

Status: [x] Completed

## Goal

Reconcile the immutable public `v0.1.1` release with the later `main` history,
verify the published CLI/MCP distribution boundary, and record any remaining
external gates without absorbing later dashboard or CLI work into the release.

## Scope and Non-goals

Scope:

- Compare `389fc7178b857aeaf9167e69aa5c98b8167c7a43` with current public
  `main` and classify post-RC changes by release-artifact impact.
- Verify the existing signed `v0.1.1` tag, GitHub Release, six archives,
  checksums, installers, package-manager metadata, MCP binary behavior, and
  GHCR visibility.
- Update the established historical release review with the boundary finding
  and correct the stale public release-review link if needed.

Non-goals:

- Do not create, move, delete, or force-update `v0.1.1` or `v0.1.0`.
- Do not tag or modify `main` to absorb later CLI, dashboard, control-plane,
  or documentation work.
- Do not change dashboard functionality, DNS, production deployment, or the
  separate `backend` and `frontend` repositories.
- Do not publish WinGet or change GHCR package policy as part of this pass.

## Owner

Coordinator — release-boundary analysis, public artifact verification,
release-history update, and final disposition.

## Dependencies

- Public repository `https://github.com/hyfens-hq/hyfens`.
- Existing signed tag `v0.1.1` and published release artifacts.
- Isolated verification clone at `/tmp/hyfens-operational-closure-8EX008`.

## Assumptions

- The explicitly validated commit is the intended CLI/MCP release boundary.
- Later dashboard/control-plane work remains on `main` and is not part of the
  immutable CLI/MCP release.
- An already-published release may have its explanatory notes corrected, but
  its tag and binary assets are immutable for this review.

## Work Items

- [x] Inspect release history and classify post-RC changes.
- [x] Confirm the signed tag points to the validated release commit.
- [x] Verify public release artifacts, checksums, installers, MCP, package
  metadata, workflows, and GHCR status.
- [x] Update the established release review and correct its public link.
- [x] Record final release disposition and remaining external gates.

## Validation

- `git log`, `git diff`, and tag-object/peeled-commit inspection.
- Public GitHub Release metadata and completed CLI/image workflow runs.
- All six archive SHA-256 checksums and archive inventories.
- Published macOS binary `--version`, help, MCP help, and MCP stdio
  initialize/tools-list/shutdown exchange.
- Default/latest and explicit-version public installer smoke in disposable
  prefixes.
- Public Homebrew formula and Scoop manifest inspection.
- Anonymous GHCR manifest requests.
- Public release-review link status, focused secret/hygiene inspection, and
  `git status`.

## Next Action

No further action in this bounded milestone. Any correction to the immutable
release binary requires a future release; no tag mutation is permitted.

## Blockers

None for reconciling the already-published release. GHCR anonymous visibility,
WinGet publication, and platform binary signing/notarization remain external
gates.

## Outcome

Confirmed that the public signed `v0.1.1` tag already points to the exact
validated commit `389fc7178b857aeaf9167e69aa5c98b8167c7a43`. Current `main`
advanced to `1a4dea95fc7d304139d4f6549decb6fcdace45f8`; its later CLI endpoint
compatibility fix and dashboard/control-plane operational work were not
absorbed into the release boundary. All six public archives and checksums,
the default/latest and pinned installers, published macOS binary help and MCP
protocol, Homebrew formula, Scoop manifest, completed tag workflows, and GHCR
status were verified. The existing release review was updated and its stale
root-level public link was corrected in the release metadata. Final
disposition remains `HYFENS v0.1.1 — RELEASED WITH EXTERNAL GATES`.

## References

- `docs/history/reviews/HYFENS_V0_1_1_RELEASE_REVIEW.md`
- `scripts/install-hyfens.sh`
- `.github/workflows/release-cli.yml`
- `.github/workflows/release-images.yml`
- `packaging/cli/homebrew/hyfens.rb.template`
- `packaging/cli/scoop/hyfens.json.template`
- `packaging/cli/winget/`

## History

- 2026-09-03 — Reserved task 247 after confirming current public `main` is
  ahead of the reviewed CLI/MCP commit and the `v0.1.1` tag already exists.
- 2026-09-03 — Reconciled the immutable tag, verified public release
  distribution, updated the historical release review, and corrected the
  GitHub Release review link. No tag or `v0.1.0` history was modified.
