# Web product boundary migration

Status: [x] Completed

## Goal

Align public OSS and private Cloud web ownership without removing the
Customer/Instance Workspace from OSS or weakening the shared auth/API
contracts.

## Scope and Non-goals

Scope is the customer-only OSS dashboard artifact, the private Cloud Platform
Console baseline, ownership documentation, focused tests, and local build
validation. The migration does not include production DNS, live deployment,
release tags, a framework migration in OSS, backend removal, or changes to the
protected `backend` or `frontend` repositories.

## Owner

Migration coordinator.

## Dependencies

- Approved `docs/architecture/web-product-boundary-audit.md` decision.
- Public OSS `origin/main` baseline.
- Local `hyfens-cloud-web` project and its existing marketing/CMS/billing app.
- Shared control-plane authentication, audience, and customer API contracts.

## Assumptions

- `hyfens-dashboard` remains the backward-compatible OSS image name and now
  represents the Customer/Instance Workspace only.
- `platform.hyfens.com` is the canonical global Platform Console host.
- Cloud product code remains private; the intended private GitHub repository
  must be created or supplied explicitly before a Cloud push.
- Existing public platform API/security contracts remain in the OSS control
  plane until a separately reviewed backend boundary migration.

## Work Items

- [x] Isolate the OSS dashboard HTML, JavaScript, proxy, stylesheet, and
  routing artifact to the Customer/Instance Workspace.
- [x] Preserve customer auth, discovery, device authorization, organization
  context, delivery records, members, credentials, support, audit, and
  settings in the OSS surface.
- [x] Establish the Cloud web Git baseline without overwriting its
  marketing/CMS/billing implementation.
- [x] Add a separate Cloud Platform Console route tree and explicit platform
  audience client boundary.
- [x] Split the isolated UI patch by ownership: customer deep-route/control
  fixes remain OSS; platform staff/control fixes remain Cloud-owned.
- [x] Update authoritative OSS and Cloud documentation and task traceability.
- [x] Run consolidated OSS and Cloud validation, inspect the OSS artifact, and
  review both repository diffs.
- [x] Commit the OSS boundary changes and Cloud changes coherently.
- [x] Push OSS to `origin/main` and push Cloud only after its intended private
  remote is established.

## Validation

Planned focused validation:

- OSS dashboard Node syntax and JavaScript tests;
- OSS dashboard Python proxy tests;
- OSS Dart analysis/tests for the unchanged control-plane contract;
- OSS dashboard container/build and self-host Compose configuration;
- Cloud lint, typecheck, and Next.js build;
- OSS artifact scan for platform UI/API markers and secrets;
- Markdown local-link and `git diff --check` validation.

## Next Action

No migration action remains. Future Cloud Customer Workspace composition and
any private backend extraction are separate, explicitly scoped changes.

## Blockers

None. The authorized private repository was established at
`https://github.com/hyfens-hq/hyfens-cloud-web`.

## Outcome

The OSS dashboard now ships only the Customer/Instance Workspace and rejects
platform route roots. The private Cloud repository owns the independent
Platform Console route tree, explicit platform audience client, and Cloud
deployment documentation. Shared auth/API contracts remain compatible; the
live customer edge was not cut over.

## References

- `docs/architecture/web-product-boundary-audit.md`
- `docs/architecture/dashboard-separation.md`
- `docs/OSS_CLOUD_SOURCE_BOUNDARY.md`
- `docs/HYFENS_CLOUD_COMMERCIAL_BOUNDARY.md`
- `/Volumes/970EvoPlus/Development/projects/auvana-ventures/hyfens-cloud-web`

## History

- 2026-09-04: Reserved as the single bounded migration task after maintainer
  approval of the OSS/Cloud web product boundary.
- 2026-09-04: Isolated the public dashboard artifact to customer routes and
  established the private Cloud Platform Console route/auth baseline.
- 2026-09-04: Passed consolidated Dart, dashboard, Cloud lint/typecheck/build,
  local route, OSS image-boundary, Compose, link, and diff validation. Created
  the authorized private Cloud remote and recorded both repositories' commits
  and push state in the final coordinator handoff.
- 2026-09-04: OSS boundary commit `a721f3fb7f1a639e94f5d205e0ad0bffc96bace9`
  was pushed to `hyfens-hq/hyfens` `main`; Cloud Platform Console commit
  `04d09daa69937ffe43917de369381611dbec34aa` was pushed to the private
  `hyfens-hq/hyfens-cloud-web` `main`.
