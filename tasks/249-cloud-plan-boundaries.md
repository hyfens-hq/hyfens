# Task 249 — Enforce Cloud plan boundaries

Status: [x] Completed

## Goal

Activate the small, deterministic Cloud plan boundaries that the current
control plane can measure from authoritative records, expose usage and limit
state to Cloud billing, and keep unmetered dimensions out of public claims.

## Scope and Non-goals

Scope:

- extend the existing Cloud plan catalog with typed limits;
- enforce application, per-application environment, and member limits in
  Cloud mode;
- expose authoritative usage and limits through the billing projection;
- return structured plan-limit failures;
- show the effective usage boundary in the existing Cloud billing workspace;
- update the public pricing catalog and generated `/pricing.md` only for
  limits that are now backed by enforcement; and
- document the cost/scale analysis and deferred metering work.

Non-goals:

- storage, bandwidth, patch-install, overage, or retention metering;
- destructive downgrade cleanup;
- a new checkout, subscription, or Enterprise contract engine;
- weakening core release-security capabilities; and
- redesigning the pricing page.

## Owner

Codex

## Dependencies

- Task 248 Cloud plan identity and effective entitlement resolver.
- Existing organization, application, environment, user, and billing records.
- Existing Cloud pricing catalog and billing workspace.

## Assumptions

- The preserved private Cloud catalog is the existing product reference for
  the countable launch baseline: Free 1 application/1 environment per
  application/1 member, Starter 2 environments per application/5 members,
  and Team 10 environments per application/20 members.
- Starter and Team have no application-count cap in this bounded slice; this
  is represented as a plan-level no-cap value, not a promise of infinite
  infrastructure capacity.
- Member creation is currently limited to the human-auth registration and
  bootstrap seams; the admission callback will cover those seams.

## Cost and scale decision matrix

| Metric | Measurable now | Cost driver | Good plan differentiator | Enforcement complexity | Recommendation |
| --- | --- | --- | --- | --- | --- |
| Applications | Yes, authoritative organization records | Product scale and control-plane state | Yes | Low | Enforce now |
| Environments | Yes, authoritative application records | Product scale and operational state | Yes | Low | Enforce per application now |
| Organization members | Yes, active customer memberships | Collaboration and authorization state | Yes | Low at current auth seams | Enforce now |
| Release/patch operations | Records exist, but no approved usage window | Potential delivery/storage cost; frequent safe releases should not be discouraged | Not yet | Medium | Defer |
| Artifact count | Records exist, but count is not a storage-cost proxy | Indirect | Weak alone | Medium | Defer |
| Artifact storage | No trusted organization byte projection | Direct infrastructure cost | Yes | High | Defer to Task 250 |
| Delivery bandwidth | No trusted delivery-byte meter | Direct infrastructure cost | Yes | High | Defer to Task 250 |
| Release history retention | History exists, but plan retention semantics are not defined | Storage/governance cost | Yes | Medium/high and potentially destructive | Defer |
| Audit retention | Deployment policy exists, not a Cloud plan policy | Governance/storage cost | Yes | High and policy-sensitive | Defer |
| Concurrent jobs | No Cloud job scheduler/counter | Infrastructure cost | Possible | High | Defer |
| API usage | No plan-scoped API counter | Infrastructure/abuse signal | Possible | Medium/high | Defer |

## Recommended launch matrix

The following values are the preserved private Cloud commercial baseline and
are now approved for the bounded, countable implementation in this task:

| Dimension | Free | Starter | Team | Enterprise | Status and reason |
| --- | ---: | ---: | ---: | ---: | --- |
| Applications | 1 | No plan cap | No plan cap | Custom | Approved/enforced; establishes the evaluation-to-production boundary without creating a per-release tax |
| Environments per application | 1 | 2 | 10 | Custom | Approved/enforced; maps directly to staged delivery workflows |
| Customer members | 1 | 5 | 20 | Custom | Approved/enforced; marks the collaboration boundary without weakening release integrity |
| Artifact storage | Not measured | Not measured | Not measured | Custom policy | Deferred; no trusted byte accounting |
| Delivery bandwidth | Not measured | Not measured | Not measured | Custom policy | Deferred; no trusted delivery-byte accounting |
| Patch installations | Not measured | Not measured | Not measured | Custom policy | Deferred; no trusted post-install receipt/period model |
| History and audit retention | Not plan-metered | Not plan-metered | Not plan-metered | Custom policy | Deferred; avoid destructive or legally sensitive retention behavior |

All Cloud plans retain core release integrity capabilities. “No plan cap” is a
commercial plan value, not a promise of infinite infrastructure capacity;
platform safety limits remain independent of plan.

## Work Items

- [x] Add typed finite, unlimited, and custom Cloud limit values.
- [x] Add authoritative application, environment, and member usage counts.
- [x] Enforce the countable limits without deleting existing resources.
- [x] Add structured plan-limit errors and focused downgrade tests.
- [x] Expose usage/limits to the Cloud billing workspace.
- [x] Update the public catalog and `/pricing.md` for enforced limits only.
- [x] Document deferred metering and review the combined diff.
- [x] Run affected validation in both repositories.

## Validation

Completed:

- `dart format lib/src/cloud_plans.dart lib/src/billing.dart lib/src/human_auth.dart test/cloud_plan_test.dart` — pass.
- `dart analyze .` from `packages/control_plane` — pass.
- Focused control-plane/auth/billing/HTTP slice — 32 tests passed.
- `npm run typecheck`, `npm run lint`, and `npm run build` from the Cloud `site/` package — pass.
- `git diff --check` in both repositories — pass.
- Full `dart test` — 277 tests completed, 34 environment skips, and 16 pre-existing reconciliation/P3E failures outside this task's touched behavior.

## Next Action

Review the enforced countable baseline with maintainers before activating any
additional usage-metered dimensions.

## Blockers

None known. Storage, bandwidth, patch-install, retention, and overage policy
remain separate product decisions and are intentionally outside this task.

## Outcome

Completed. The control plane now publishes and enforces the preserved baseline
for applications, environments per application, and customer members. Core
release-integrity capabilities remain shared across Cloud plans. Existing
resources survive downgrades, while finite-limit growth returns structured
`PLAN_LIMIT_REACHED` errors. Artifact storage, delivery bandwidth,
patch-install, retention, overage, and monthly usage accounting remain in Task
250.

## References

- `packages/control_plane/lib/src/cloud_plans.dart`
- `packages/control_plane/lib/src/billing.dart`
- `packages/control_plane/lib/src/service.dart`
- `docs/architecture/cloud-plan-entitlements.md`
- `hyfens-cloud-web/site/src/lib/pricing.ts`

## History

- 2026-09-07: Reserved after auditing the active Cloud catalog, control-plane
  resource seams, and the preserved private commercial catalog reference.
- 2026-09-07: Completed the countable commercial baseline, server-side
  admission checks, usage projection, public catalog alignment, and validation.
