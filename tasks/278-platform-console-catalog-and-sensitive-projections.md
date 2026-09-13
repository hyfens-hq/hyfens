# Task 278: Platform Console Catalog and Sensitive Projections

Status: [x] Completed

## Goal

Make the managed Platform Console useful and safe for day-to-day administration:
show authoritative Cloud plan definitions instead of duplicated tenant billing
rows, expose the existing governed pricing workspace to authorized operators,
remove unnecessary identifiers from customer-facing tables, and provide an
explicit streamer mode for sensitive values.

## Scope and Non-goals

Scope:

- correct control-plane platform projections for Cloud plans, subscriptions,
  organization names, and deletion status;
- add the minimum platform authorization surface required by the existing
  commercial/catalog UI;
- add audited platform catalog editing for the existing Cloud plan catalogue;
- improve Cloud Platform Console presentation, links, drawers, and streamer
  mode;
- preserve the public pricing/legal approval gate and existing billing state;
- document and test the resulting behavior.

Non-goals:

- no new billing provider or pricing model;
- no bypass of legal approval or public catalog publication controls;
- no change to Razorpay behavior, deletion lifecycle, or app.hyfens.com;
- no direct development on main.

## Owner

Codex, with control-plane and Cloud UI changes reviewed together.

## Dependencies

- Current control-plane main at `f86d840`.
- Current Cloud web main at `7482e94`.
- Existing Platform Console staff governance and commercial catalog seams.
- Existing platform audit chain and idempotency store.

## Assumptions

- `billing_plan_catalog` is the stable four-plan Cloud entitlement catalogue.
- `billing_plans` remains tenant/provider billing metadata and must not be used
  as the global plan catalogue.
- Existing commercial catalog/legal approval remains authoritative for public
  pricing publication.
- Streamer mode is a presentation safeguard, not an authorization boundary.

## Work Items

- [x] Reproduce and document the projection/UI defects from the supplied views.
- [x] Project the authoritative Cloud catalogue and safe human-readable names.
- [x] Add guarded, reasoned, audited plan metadata/status mutation where the
  existing control-plane model permits it.
- [x] Align platform capability names/roles with the existing Cloud console
  commercial and plan-governance UI.
- [x] Remove raw identifiers from default tables and add authorized detail links.
- [x] Add streamer mode and sensitive-value reveal controls.
- [x] Improve platform-console footer/sidebar density and operations context.
- [x] Add or update focused control-plane and Cloud tests.
- [x] Run combined validation, review diffs, commit atomically, and prepare PRs.

## Validation

Completed:

- `dart analyze` for the changed control-plane files: passed;
- focused control-plane projection and HTTP tests: 5 passed;
- Cloud typecheck: passed;
- Cloud lint: passed;
- Cloud production build: passed and generated the platform dynamic routes;
- `git diff --check` in both repositories: passed;
- manual diff review confirmed identifiers remain available for routing/actions
  but are not rendered in default platform tables; technical references are
  collapsed and streamer-protected;
- full control-plane suite was also run once as required for PR preparation.
  It reported 27 unrelated pre-existing failures in credential, observation,
  reconciliation, and P3E tests; no changed-scope test failed.

## Next Action

Review the two branch diffs and merge through the normal PR process. A deployed
browser smoke should verify the authorized platform session after release.

## Blockers

None currently. Public pricing remains subject to its existing legal approval
gate and is intentionally outside this task's bypass scope.

## Outcome

Completed on the task branches. The control plane now returns one stable,
named Cloud row for Free, Starter, Team, and Enterprise, with provider prices
remaining projection evidence. Deleted organizations project as deleted and
subscriptions carry human-readable organization and plan names. Platform
admins and super-admins can edit plan metadata/limits/availability through a
reason-required, idempotent, audited endpoint; customer subscriptions and
provider plans are not mutated. Valid catalog edits now survive subsequent
billing initialization instead of being overwritten by the seed path. Free
remains protected as the automatic onboarding default until onboarding supports
paid-plan selection.

The Cloud console now renders names instead of default raw identifiers,
provides drawer-based staff access and plan editing, positions staff menus
outside the scroll container, removes the duplicate email-heavy sidebar
identity, adds persisted Stream safe mode with per-value reveal controls, and
keeps technical references collapsed. Payment, support, promotion, audit, and
commercial projections also avoid rendering raw IDs in their normal tables.

## References

- Supplied Platform Console screenshots for users, organizations, entitlements,
  operations, audit, and settings.
- `packages/control_plane/lib/src/platform_console.dart`.
- `packages/control_plane/lib/src/human_auth.dart`.
- `apps/web/src/components/platform/PlatformConsole.tsx`.

Implementation branches:

- `fix/platform-console-catalog-projections`
- `fix/platform-console-sensitive-data-ui`

## History

- 2026-09-13: Task reserved on `fix/platform-console-catalog-projections` and
  `fix/platform-console-sensitive-data-ui`; root causes recorded before edits.
- 2026-09-13: Completed authoritative projection, audited plan administration,
  identifier-safe platform UI, and streamer mode; focused validation passed.
