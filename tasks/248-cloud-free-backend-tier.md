# Task 248 — Cloud Free backend tier

Status: [x] Completed

## Goal

Make Free a real Hyfens Cloud plan by assigning it automatically to Cloud
organizations, resolving plan state server-side, and keeping Self-hosted as a
separate deployment model.

## Scope and Non-goals

Scope:

- add an explicit Cloud versus Self-hosted operating-model boundary;
- seed a stable Cloud plan catalog for Free, Starter, Team, and Enterprise;
- provision and backfill an explicit internal Free assignment for Cloud
  organizations without contacting Razorpay;
- expose effective plan and entitlement state through the existing billing
  projection;
- preserve existing provider-backed paid subscriptions and the existing
  self-hosted workflow; and
- add focused tests and document unresolved commercial limits.

Non-goals:

- a new account or workspace signup flow;
- usage metering, overage billing, invoicing, taxes, or annual billing;
- invented numerical quotas or paid-only feature gates; and
- a pricing-page redesign or React Native implementation.

## Owner

Codex

## Dependencies

- Existing organization bootstrap and organization-scoped billing records.
- The managed Cloud deployment must set `HYFENS_DEPLOYMENT_MODEL=cloud`.

## Assumptions

- Organizations remain the subscription owner in the current control plane.
- The existing generic JSON record store remains the persistence seam for
  plan catalog and subscription assignments.
- Existing self-hosted deployments default to `self_hosted` for compatibility.

## Work Items

- [x] Inspect current plan, subscription, billing, auth, and workspace seams.
- [x] Add operating-model and Cloud-plan catalog types.
- [x] Add idempotent Free assignment, paid-state preservation, and effective
  entitlement resolution.
- [x] Add server-side entitlement boundary and API projection fields.
- [x] Align configuration, documentation, and the Cloud billing contract.
- [x] Add focused provisioning, hierarchy, upgrade, and compatibility tests.
- [x] Review the combined diff and run scoped validation.

## Validation

Completed:

- `dart format` on the changed Dart files — passed.
- `dart analyze packages/control_plane` — passed.
- Focused control-plane tests (`cloud_plan_test.dart`, `config_test.dart`,
  `control_plane_test.dart`, `http_test.dart`, `demo_seed_test.dart`) —
  passed, 28 tests.
- Cloud web `npm run typecheck`, `npm run lint`, and `npm run build` — passed;
  29 routes generated.
- `git diff --check` in both repositories — passed.

The complete control-plane suite was also run once. It remains non-green in
pre-existing reconciliation, platform-metrics, and P3E auto-halt cases, with
database/object-store integration cases skipped because their test services
are not configured. Those failures do not use Cloud deployment mode and did
not reproduce in the focused affected suite.

## Free plan limit decision table

The backend currently exposes no numerical Cloud quotas. This table records
the decision boundary without publishing or enforcing invented values.

| Metric | Metered today? | Cost driver? | Recommended for plan differentiation? | Decision required |
| --- | --- | --- | --- | --- |
| Applications | Countable from organization records; not plan-metered | Product scale | Yes | Approve Free, Starter, and Team limits |
| Environments | Countable from organization records; not plan-metered | Product scale | Yes | Approve limits and downgrade behavior |
| Members | Membership records exist; not plan-metered | Collaboration | Yes | Approve member allowances and governance boundary |
| Artifact storage | No aggregate Cloud meter | Infrastructure | Yes | Choose storage accounting and limits |
| Artifact delivery bandwidth | No usage meter | Infrastructure | Yes | Choose bandwidth accounting and overage policy |
| Release/patch operations | Records exist; no quota meter | Product scale | Maybe | Decide whether operations or applications are the clearer boundary |
| Release history | History exists; no plan retention policy | Product scale | Yes | Approve retention semantics |
| Audit retention | Global deployment retention exists; not plan-specific | Governance/storage | Yes | Approve plan retention and export behavior |

No numeric value is approved by this task. A later metering task must add
authoritative counters and enforcement before the table becomes public
pricing policy.

## Next Action

Ship the backend contract with the managed Cloud deployment configured for
`HYFENS_DEPLOYMENT_MODEL=cloud`; keep self-hosted deployments on the default.

## Blockers

None currently. The repository does not contain a public Cloud account or
workspace-creation flow; the existing server-side organization bootstrap is
the implementation seam for this task.

## Outcome

The control plane now has an explicit `cloud` versus `self_hosted` deployment
model, a persisted Free assignment for managed Cloud organizations, a stable
Cloud catalog, effective entitlement resolution, paid-state preservation, and
an additive billing API projection. The existing Cloud billing workspace
understands internal Free state and does not expose Razorpay actions for it.

No public Cloud account/workspace signup route was added because that service
does not exist in this repository. The managed Cloud account service must call
the existing organization bootstrap seam and set the Cloud deployment mode.

## References

- `packages/control_plane/lib/src/service.dart`
- `packages/control_plane/lib/src/billing.dart`
- `packages/control_plane/lib/src/config.dart`
- `docs/HYFENS_CLOUD_COMMERCIAL_BOUNDARY.md`
- `hyfens-cloud-web/docs/HYFENS_CLOUD_BILLING_V1.md`

## History

- 2026-09-07: Created from the backend Free-plan correction request after
  auditing the current repository state.
- 2026-09-07: Implemented the Cloud deployment boundary, catalog, Free
  assignment/backfill, entitlement resolver, API projection, focused tests,
  and Cloud billing contract alignment. Scoped validation passed; unrelated
  pre-existing full-suite failures remain recorded above.
