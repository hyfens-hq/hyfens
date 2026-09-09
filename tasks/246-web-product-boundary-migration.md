# Web Product Boundary Migration

Status: [*] In Progress

## Goal

Implement the approved web product boundary: retain a complete public
Customer/Instance Workspace and self-host web artifact in `hyfens`, while
establishing `hyfens-cloud-web` as the owner of the global Cloud Platform
Console and Cloud-only web operations. Preserve customer/auth/API contracts
without copying the two products into one public artifact.

## Scope and Non-goals

Scope is one bounded migration package across the public OSS repository and
the sibling private Cloud web project: Cloud repository baseline, customer vs
platform frontend entry points, isolated OSS customer build, Cloud Platform
Console destination, shared contract documentation, release/image boundaries,
and focused validation.

Non-goals: new dashboard features, framework migration of the OSS dashboard,
runtime/CLI/MCP behavior changes, billing-ledger/MFA-provider work, production
DNS or live cutover, v0.1.2, history rewriting, license changes, or changes to
the protected `backend`/`frontend` repositories.

## Owner

Migration/architecture coordinator

## Dependencies

- Approved audit: `docs/architecture/web-product-boundary-audit.md`.
- Public OSS baseline at `origin/main` (`78ae59f5a3f1810cc6ad4c8e45c647afd86dcc6b`).
- Sibling Cloud project at
  `/Volumes/970EvoPlus/Development/projects/auvana-ventures/hyfens-cloud-web`.
- Isolated validated UI patch at `/tmp/hyfens-local-ui.o1aRjY`.
- Explicit private Cloud repository destination; do not guess or publish one.

## Assumptions

- The active OSS checkout remains dirty and is not a safe integration surface;
  implementation uses clean isolated worktrees.
- The public OSS Customer/Instance Workspace remains the customer-core source
  of truth for self-hosting and hosted customer continuity.
- The global Platform Console is Cloud-owned; authorization semantics remain
  fail-closed while implementation ownership changes.
- Existing released `v0.1.1` artifacts remain immutable.

## Work Items

- [ ] Establish and validate a clean private `hyfens-cloud-web` Git baseline
  without guessing a remote or committing secrets/local state.
- [ ] Isolate the OSS dashboard build and image to Customer/Instance Workspace
  plus required auth/discovery/device/CLI surfaces.
- [ ] Split and apply the validated local UI patch by product ownership.
- [ ] Establish the Cloud Platform Console entry point and migrate the bounded
  platform surface without copying the whole OSS application.
- [ ] Document and test shared auth/customer/platform contract boundaries.
- [ ] Preserve self-host Compose and customer-workspace continuity.
- [ ] Run focused OSS/Cloud build, authorization, artifact, and documentation
  validation.
- [ ] Review changes and commit/push only the bounded migration after all
  required gates pass.

## Validation

Planned scoped validation: OSS dashboard JavaScript/Python tests and syntax,
customer-only artifact inspection, self-host Compose/configuration checks,
Cloud typecheck/lint/build and Platform Console checks, auth/audience and
tenant-isolation tests, Markdown links, secret scans, and `git diff --check`.
Production DNS, live deployment, and release tagging are explicitly excluded.

## Next Action

Use clean isolated worktrees, establish the Cloud repository baseline only when
the intended private remote is explicit, then implement and review the customer
artifact and Cloud Platform Console split.

## Blockers

The intended private GitHub remote for `hyfens-cloud-web` is not configured and
the named repository does not currently resolve. Migration can proceed locally
without pushing Cloud changes, but Cloud push/remote creation requires an
explicit valid destination and authorization.

## Outcome

Pending implementation and integrated validation.

## References

- `docs/architecture/web-product-boundary-audit.md`
- `tasks/245-web-product-boundary-audit.md`
- `/Volumes/970EvoPlus/Development/projects/auvana-ventures/hyfens-cloud-web/README.md`
- `/tmp/hyfens-local-ui.o1aRjY`

## History

- 2026-09-04: Reserved task 246 after maintainer approval of the boundary
  audit. No source migration or repository push performed yet.
