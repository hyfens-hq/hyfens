# Task 252 — Cloud artifact lifecycle and retention policy

Status: [x] Completed

## Goal

Make Cloud artifact lifecycle semantics explicit and safe: logical readiness,
quarantine, physical purge, rollback protection, historical evidence, and
reconciliation must remain separate concerns. Preserve Task 250's logical
storage meter and do not introduce plan retention periods or pricing changes.

## Scope and Non-goals

Scope:

- inventory the artifact classes represented by the current control plane;
- make the READY/QUARANTINED/PURGED lifecycle explicit;
- preserve artifact, release, deployment, and audit evidence after byte purge;
- add an idempotent, organization-safe purge seam for invalid quarantined bytes;
- keep Task 250 storage accounting aligned with lifecycle transitions;
- improve reconciliation findings for purged metadata and leftover objects; and
- document the Cloud/self-hosted boundary and future retention decisions.

Non-goals:

- changing Cloud prices or application/environment/member boundaries;
- choosing Free/Starter/Team/Enterprise retention durations;
- deleting READY artifacts or weakening rollback/security guarantees;
- customer-controlled arbitrary artifact deletion;
- billing, overages, physical-storage settlement, or CDN retention policy; and
- changing Self-hosted operator retention behavior.

## Owner

Codex

## Dependencies

- Task 249 Cloud plan boundaries.
- Task 250 Cloud usage metering.
- Existing content-addressed artifact stores and reconciliation.
- Cloud web CMS/content publication boundary.

## Assumptions

- READY artifact bytes remain the authoritative logical Cloud storage gauge.
- Current release/promotion behavior has no source-to-target environment history;
  all READY artifacts are therefore retained for the existing workflow.
- QUARANTINED bytes are unavailable to delivery and are already excluded from
  logical storage; pending quarantined bundle imports protect their bytes until
  explicit admission.
- PURGED removes only the object bytes, not artifact metadata or historical
  release/deployment/audit evidence.
- No approved commercial retention durations exist yet.

## Work Items

- [x] Inventory artifact classes and document their current lifecycle.
- [x] Add explicit lifecycle metadata and conservative retention policy rules.
- [x] Add safe, idempotent physical purge for eligible quarantined artifacts.
- [x] Preserve rollback/import protection and historical evidence.
- [x] Extend reconciliation for purged metadata and leftover objects.
- [x] Add audited CMS-managed policy content and public legal footer links.
- [x] Add focused lifecycle, purge, reconciliation, and policy-content tests.
- [x] Run affected Dart and Cloud validation and review the combined diff.

## Validation

Completed:

- `dart format --output=none` for the changed control-plane files;
- `dart analyze .` from `packages/control_plane`;
- focused artifact lifecycle, policy-content, usage-metering, closure,
  release-bundle, S3, and reconciliation tests (38 tests passed);
- `npm run typecheck`, `npm run lint`, and `npm run build` from the Cloud site;
  the build includes `/terms`, `/privacy`, and `/refund-policy`; and
- `git diff --check` in both repositories.

## Next Action

Monitor future retention/legal decisions separately. No additional lifecycle
implementation is required for the current approved scope.

## Blockers

None known. Commercial retention periods, legal/security holds, edge-cache
retention, and physical-capacity billing remain decisions for later work.

## Outcome

Implemented. READY artifacts remain available and counted; QUARANTINED bytes
are unavailable and purgeable through an idempotent, bounded cleanup seam;
PURGED metadata and audit/history evidence remain. Policy content is now an
audited CMS-managed content kind with stable public legal routes and footer
links.

## References

- `tasks/249-cloud-plan-boundaries.md`
- `tasks/250-cloud-usage-metering-follow-up.md`
- `tasks/251-cloud-plan-matrix-review.md`
- `docs/architecture/cloud-usage-metering.md`
- `docs/architecture/cloud-plan-entitlements.md`
- `docs/architecture/cloud-artifact-lifecycle.md`
- `packages/control_plane/lib/src/artifact_retention.dart`
- `packages/control_plane/test/artifact_lifecycle_test.dart`
- `packages/control_plane/test/content_policy_test.dart`
- Linked Cloud web package: `hyfens-cloud-web/tasks/08-policy-content-and-footer.md`

## History

- 2026-09-07: Created for the lifecycle/retention correctness package. Cloud
  policy links are included as a linked frontend package because legal content
  already uses the audited editorial CMS boundary.
- 2026-09-07: Completed lifecycle metadata, conservative quarantine cleanup,
  reconciliation findings, policy-content support, focused tests, and Cloud
  validation. Commercial retention durations, holds, CDN evidence, and
  physical-storage policy remain deferred.
