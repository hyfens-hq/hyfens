# Web Product Boundary Audit

Status: [x] Completed

## Goal

Determine the correct repository and deployment ownership for the OSS
dashboard, Cloud Customer Workspace, and Hyfens Platform Console before the
uncommitted dashboard patch is integrated.

## Scope and Non-goals

Scope is a read-only comparison of this OSS repository, the sibling
`hyfens-cloud-web` project, the shipped dashboard image/build inputs, current
documentation, and the isolated local dashboard patch. The durable output is
`docs/architecture/web-product-boundary-audit.md`.

Non-goals: migrating or deleting code, changing dashboard behavior, changing
DNS or deployment, committing/pushing the isolated patch, or modifying the
separate Cloud project.

## Owner

Release/architecture coordinator

## Dependencies

- Public OSS checkout at `/Volumes/970EvoPlus/Development/projects/auvana-ventures/hyfens`.
- Sibling project at `/Volumes/970EvoPlus/Development/projects/auvana-ventures/hyfens-cloud-web`.
- Isolated local patch worktree at `/tmp/hyfens-local-ui.o1aRjY`.

## Assumptions

- The current active OSS checkout is intentionally dirty; all pre-existing
  changes remain untouched.
- `origin/main` is the reviewed reference for the current two-shell dashboard
  implementation; the audit does not make it the working tree state.
- Repository ownership and product-boundary decisions require maintainer
  review before implementation.

## Work Items

- [x] Inspect OSS dashboard, control-plane boundaries, self-host package, and image/release inputs.
- [x] Inspect `hyfens-cloud-web` routes, auth/API clients, billing, deployment, and repository maturity.
- [x] Compare product ownership, shared-code options, licensing, and the isolated local patch.
- [x] Write the bounded architecture boundary report.
- [x] Obtain maintainer review before any migration or patch integration.

## Validation

Read-only source inspection with `git`, `rg`, and `sed` across both projects.
The final report will be checked with `git diff --check` and local Markdown-link
validation where applicable. No runtime deployment or browser acceptance is
part of this audit.

## Next Action

The maintainer approved the report recommendation. Continue in task 246 for
the bounded migration; do not treat this audit approval as authorization for
release or production cutover.

## Blockers

None for producing the audit. Migration is intentionally gated on maintainer
review.

## Outcome

Read-only audit completed and approved. The evidence supports
`WEB PRODUCT BOUNDARY — CLOUD/OSS FRONTENDS MUST BE RESTRUCTURED`:
retain the public Customer/Instance Workspace and self-host deployment in
OSS, and move the global Platform Console plus Cloud-only web operations into
`hyfens-cloud-web` after a clean Cloud baseline is established. The report
classifies the current dashboard modules and the isolated UI patch. Maintainer
review is complete; migration is tracked separately in task 246.

## References

- `docs/architecture/web-product-boundary-audit.md`
- `docs/OSS_CLOUD_SOURCE_BOUNDARY.md`
- `docs/HYFENS_CLOUD_COMMERCIAL_BOUNDARY.md`
- `/Volumes/970EvoPlus/Development/projects/auvana-ventures/hyfens-cloud-web/README.md`
- `/tmp/hyfens-local-ui.o1aRjY/tasks/249-local-platform-console-action-clarity.md`

## History

- 2026-09-04: Reserved task 245 for the bounded OSS/Cloud dashboard ownership audit; no migration or patch integration authorized.
- 2026-09-04: Completed repository, image, release, Cloud-web, licensing, and
  isolated-patch inspection; wrote
  `docs/architecture/web-product-boundary-audit.md`. No migration, deletion,
  commit, push, or deployment performed.
- 2026-09-04: Maintainer approved the boundary decision and authorized the
  bounded migration tracked by task 246.
