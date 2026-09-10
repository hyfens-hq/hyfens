# Task 251 — Review the Cloud launch plan matrix

Status: [x] Completed

## Goal

Review the enforced application, environment, and member boundaries against
the implemented Hyfens workflow and current cost/scale evidence before any
additional usage metering is built.

## Scope and Non-goals

Scope:

- inspect the actual release, promotion, deployment, and rollback workflow;
- review Free's one-environment evaluation boundary;
- review the absence of Starter and Team application-count caps;
- compare the candidate launch matrix with the active matrix; and
- record whether a small matrix change is justified.

Non-goals:

- changing prices or redesigning pricing UI;
- starting Task 250 or implementing storage/bandwidth metering;
- adding security-based plan gates;
- changing downgrade behavior; and
- inventing new commercial quotas without supporting evidence.

## Owner

Codex

## Dependencies

- Task 249 Cloud plan-boundary implementation.
- Existing control-plane application, environment, release, artifact, and
  billing behavior.
- Existing Cloud pricing catalog and generated `/pricing.md`.

## Assumptions

- The current promotion contract promotes an admitted release into a target
  environment. It does not accept a source environment or implement a
  source-to-target environment transition.
- `ApplicationRecord` is identity and metadata; release, patch, artifact, and
  delivery usage are separate records and remain unmetered by plan.
- Android and iOS runtime identities are separate application records, so a
  finite application count must not accidentally make one Flutter product
  consume an arbitrary commercial allowance.

## Current vs reviewed launch matrix

| Plan | Applications | Environments/app | Members |
| --- | ---: | ---: | ---: |
| Free | 1 | 1 | 1 |
| Starter | No plan cap | 2 | 5 |
| Team | No plan cap | 10 | 20 |
| Enterprise | Custom | Custom | Custom |

Decision: keep the current matrix for launch.

The candidate `Free: 2 environments`, `Starter: 3–5 environments and 3
applications`, and `Team: 10–20 applications` values are not adopted. The
repository does not provide evidence that those numbers are required or that
they map to a current cost boundary.

## Free workflow analysis

One environment is sufficient for the implemented core evaluation path:

1. register an application and release;
2. create and verify a signed patch artifact;
3. promote the admitted release into the selected environment;
4. deliver/update against that application/environment scope; and
5. observe the record and use the signed runtime rollback-to-base path.

The service's `promote` operation accepts one target `environment_id`, checks
the release belongs to the same application and has a verified ready patch,
then updates that environment's promoted release pointer. It does not require
or model a source environment. Two environments would add a second delivery
target and let a customer promote the same release into another isolated
environment, but that is an additional deployment topology, not a prerequisite
for experiencing the current release workflow.

Free with one environment therefore remains useful without promising staged
environment governance that is not implemented. Starter's second environment
is a concrete production boundary; a future product decision can raise Free to
two if source/target promotion, environment protection, or staged approval
becomes part of the supported evaluation path.

## Application-cap analysis

An application currently stores an opaque ID, organization ID, runtime package
or bundle identity, optional name/platform, and creation time. Creating the
identity does not allocate artifact bytes, release history, delivery bandwidth,
or a per-application worker. Those downstream records remain the meaningful
deferred cost dimensions.

The current no-plan-cap value therefore remains defensible for launch:

- it avoids an arbitrary 3/10 boundary while storage and delivery usage are
  not measured;
- it avoids mispricing a single Flutter product whose Android and iOS bundle
  identities are separate application records;
- Starter and Team already have concrete differences through environments and
  members; and
- platform request/body/artifact safety limits remain independent of the
  commercial application value.

There is still a control-plane abuse risk if an authenticated customer creates
large numbers of empty application identities. The current process-local
request rate limit and artifact/body bounds reduce request abuse but are not a
durable per-organization resource policy. That should be addressed by a
measured resource/abuse policy or a future approved application cap, not by
choosing arbitrary public values in this review.

## Member analysis

`Free: 1`, `Starter: 5`, and `Team: 20` remains the clearest collaboration
ladder supported by the current admission and usage model. No change is
justified.

## Upgrade rationale

- Free → Starter: move from one evaluation application, one target
  environment, and one member to a serious small production workspace with a
  second environment and five members. Core release integrity is unchanged.
- Starter → Team: move from an individual/small-team boundary to an
  organization-scale boundary with up to twenty members and ten environments
  per application. Applications remain uncapped because application identity
  is not yet the measured cost driver.

## Cost and risk decision

| Candidate change | Decision | Reason |
| --- | --- | --- |
| Free environments `1 → 2` | Keep current; defer increase | One target environment exercises the implemented core path. Two adds isolation/multi-target evaluation but is not required by the current promotion contract. |
| Starter applications `No cap → 3` | Keep current; defer finite cap | The proposed value is not tied to measured cost and can penalize Android/iOS identity pairs. |
| Team applications `No cap → 10–20` | Keep current; defer finite cap | Team already monetizes organization scale through members and environments; the application value can be revisited with usage evidence. |
| Starter environments `2 → 3–5` | Keep current | Two is a clear increment over Free and is supported by current environment admission. |
| Team environments `10` | Keep current | Provides a meaningful organizational-scale boundary without weakening security. |
| Members `1/5/20` | Keep current | Matches the intended collaboration ladder and current enforcement. |

## Work Items

- [x] Inspect current plan catalog, usage projection, enforcement, and tests.
- [x] Inspect actual environment/promotion/deployment/rollback behavior.
- [x] Evaluate application record cost, abuse risk, and platform identity shape.
- [x] Compare the candidate matrix with the active matrix.
- [x] Decide whether a production matrix change is justified.
- [x] Run focused plan-boundary tests and affected Cloud checks.
- [x] Review this task-owned diff and record validation results.

## Validation

Completed:

- `dart test test/cloud_plan_test.dart` from `packages/control_plane` — 11
  tests passed.
- `npm run typecheck` from `hyfens-cloud-web/site` — pass.
- `npm run lint` from `hyfens-cloud-web/site` — pass.
- Read-only review of the current control-plane promotion, environment,
  application, rate-limit, and artifact-boundary implementations — complete.
- No production code, plan catalog, pricing catalog, or `/pricing.md` changes
  were required.

## Next Action

Keep the current matrix for launch. Revisit Free's environment allowance only
if source-to-target promotion, environment protection, or staged approval is
implemented as part of the supported evaluation path. Revisit application caps
after measured usage/abuse evidence exists. Do not start Task 250 as part of
this review.

## Blockers

None known.

## Outcome

Completed. The current matrix remains the strongest launch choice supported by
repository evidence. One environment exercises the complete implemented core
workflow because promotion targets an environment rather than moving from a
source environment. Starter and Team application records are low-cost identity
metadata; finite 3/10 caps would be arbitrary before release/artifact usage is
measured and could penalize Android/iOS identity pairs. Existing environment
and member boundaries provide the current production and collaboration ladder.
No production implementation or public pricing values changed.

## References

- `packages/control_plane/lib/src/cloud_plans.dart`
- `packages/control_plane/lib/src/billing.dart`
- `packages/control_plane/lib/src/service.dart`
- `docs/product/customer-workspace.md`
- `docs/spec/product-api-domain.md`
- `docs/architecture/control-plane.md`
- `hyfens-cloud-web/site/src/lib/pricing.ts`
- `tasks/249-cloud-plan-boundaries.md`
- `tasks/250-cloud-usage-metering-follow-up.md`

## History

- 2026-09-07: Created after reviewing the active matrix and implemented
  release/environment contracts.
- 2026-09-07: Completed focused tests and Cloud checks; kept the active matrix
  and deferred any candidate changes pending stronger workflow or usage
  evidence.
