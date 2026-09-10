# ADR 0012 — Gate automatic halt through existing P3E-4/P3A authority

Status: Accepted through P3E5-4B intent; P3E-4/P3A mutation remains unauthorized

Date: 2026-08-24

## Context

P3E5-3 can produce immutable scheduled `HALT_NEW_OFFERS` evidence but
deliberately stops at `EVALUATED`. P3E-4 already validates exact P3E evidence
and is the only health path allowed to invoke the P3A expected-revision CAS.
Automatic application introduces availability mutation authority into a
non-human workflow and must not turn the evaluator, scheduler, or health signal
into runtime trust.

Granting `rollout:halt` directly to the evaluation scheduler would make one
worker credential sufficient to claim work, create decisions, and mutate
rollout eligibility. Creating a scheduler-specific rollout writer would
duplicate P3E-4 validation and P3A concurrency semantics.

## Decision proposed

1. Automatic halt is scheduling policy over immutable evidence, not runtime
   trust, patch validity, rollback, or artifact authority.
2. Only scheduled, sealed, current `HALT_NEW_OFFERS` evidence with
   `PATCH_SAFETY` reason class and an approved, exact versioned policy may be an
   automatic candidate.
3. The evaluation scheduler remains unable to halt. A separate exact-scope
   Auto-Halt Principal supplies the narrow apply-halt and rollout read/halt
   authority.
4. Application requires two independent authorities: the current fenced P3E5
   work lease and the Auto-Halt Principal. Either alone is insufficient.
5. The only downstream mutation route is the existing P3E-4 evidence
   validation/application core followed by the existing P3A expected-revision
   CAS. No direct rollout state or revision write is permitted.
6. Automatic halt is disabled by default and remains distinct from policy
   approval and production enablement.
7. The automated action is one-way: it may stop future offers only. It never
   expands, pauses from `HOLD`, rolls back, resumes, or unhalts.
8. Duplicate/crash recovery uses `scheduled-halt:<workId>`, immutable P3E-4
   application evidence, P3A history, fencing, and bounded reconciliation; no
   two-phase commit or heartbeat is required initially.

## Consequences

Compromise of the evaluator credential alone cannot halt, and compromise of
the auto-halt credential alone cannot select or advance work. A combined
in-scope compromise or unsafe approved threshold can still cause availability
harm, so credential custody, policy calibration, two-person production
approval, audit, and revocation remain necessary.

Future implementation must introduce a narrow exact-scope authorization
adapter to the shared P3E-4 core and a versioned automatic-halt policy binding.
Historical logical-key v1 work cannot be reinterpreted as automatically
eligible. Cross-store completion remains at-least-once and reconcilable rather
than globally transactional.

This ADR authorizes no code, migration, automatic worker, policy value,
production enablement, or readiness claim.

## Alternatives considered

- **Give the evaluation scheduler `rollout:halt`:** rejected because one
  credential would span evidence production and mutation.
- **Use the broad bootstrap/control credential:** rejected because its tenant
  and administrative blast radius is inappropriate for automation.
- **Create a scheduler-specific rollout writer:** rejected because it would
  duplicate or bypass P3E-4 evidence validation and P3A CAS.
- **Require a human action for every halt:** retained as the manual P3E-4 path,
  but insufficient as the only future option when maintainers explicitly
  approve bounded automation.
- **Automatic rollback or expansion:** rejected because both cross the frozen
  one-directional delivery-eligibility boundary.

## Reference

See [P3E5-4 gated automatic halt design](../history/reviews/P3E5_4_AUTOMATIC_HALT_DESIGN.md).

## P3E5-4A implementation note (2026-08-24)

Task 63 implements decisions 2–4 and 6 at the policy/identity boundary only:
a strict policy model, immutable default-off approval/enablement state, a
separate exact-scope Auto-Halt Principal, structural lease-plus-principal
authority, logical work meaning v2, and historical-v1 ineligibility.

File/PostgreSQL persistence and migration 007 retain immutable tenant-scoped
policy/state evidence. No code uses the authority to enter `HALT_APPLYING`,
invoke P3E-4/P3A, or mutate rollout eligibility. Decisions 5 and 8 remain
future P3E5-4B through P3E5-4E implementation work requiring separate
authorization.

## P3E5-4B implementation note (2026-08-24)

Task 64 implements the applicability half of decisions 2–4 and 6–8. A narrow
service revalidates current v2 scheduled, sealed, patch-safety halt evidence,
explicit approval/test enablement, target/rollout/policy/freshness, the fenced
lease, and the exact Auto-Halt Principal. It atomically advances only the
scheduled-work projection from `EVALUATED` to `HALT_APPLYING` with canonical,
bounded intent evidence embedded in the new work version.

The implementation deliberately has no P3E-4 application or P3A transition
dependency and creates no rollout revision. Therefore decision 5's downstream
mutation route and the completion/recovery portion of decision 8 remain future
P3E5-4C and later work requiring separate authorization.

## P3E5-4C implementation note (2026-08-24)

Task 65 implements decision 5's bounded application route. A committed
`HALT_APPLYING` work item is independently revalidated, then enters the
existing P3E-4 evidence/application core through an exact-scope Auto-Halt
Principal. P3E-4 performs the existing P3A expected-revision CAS; no
scheduler-specific rollout writer or distributed transaction was introduced.

The deterministic key `scheduled-halt:<workId>` and immutable
`HealthHaltApplication`/`HALTED` revision linkage are verified before a
separate completion proof allows `HALT_APPLYING -> COMPLETED`. File and
PostgreSQL failure/recovery and two-instance convergence tests pass. Lease
expiry after a committed halt fails closed and remains a recovery/reclaim
concern for separately authorized P3E5-4D work.

Production approval and enablement remain absent and disabled by default; this
implementation note does not change the ADR's rejection of expansion, pause,
rollback, resume, or unhalt.

## P3E5-4D recovery/race-hardening implementation note (2026-08-24)

Task 66 closes the specific lease-expiry ambiguity without changing the ADR's
authority model. Recovery searches immutable application evidence first, then
uses an auto-halt-only expired-work reclaim CAS. The new lease remains bound to
the existing intent and semantic attempt; it cannot select a successor
revision or call a rollout writer. Generic scheduler claiming excludes
`HALT_APPLYING` so only the recovery service can perform this operation.

The recovered lease is consumed by the Task 65 adapter and existing P3E-4/P3A
expected-revision CAS. File and PostgreSQL tests show one fenced winner,
evidence-first idempotency, stale/malformed/foreign rejection, restart and
lost-response recovery, and old-token completion rejection. Stale currentness
is terminally fenced in the schedule projection with no rollout write.

Explicit recovery bounds are mandatory inputs. No heartbeat, generic recovery
redesign, provider HA, rollout action, runtime/mobile change, production
default, or P3E5-4E behavior is authorized by this note. Remaining untested
provider-disconnect, audit-failure, and resource-storm evidence stays a
maintainer-review condition.

## P3E5-4E integration evidence note (2026-08-24)

Task 67 executed bounded File and local PostgreSQL integration evidence without
changing this ADR's authority model. The evidence covers audit outage and
divergence, measured test-only lease timing, close/reopen recovery, one-winner
application races, File restart, tenant/security boundaries, and explicit
resource limits. P3E-4 remains the only health-halt application path and P3A
remains the only rollout mutation authority.

The campaign does not establish provider HA or production capacity. Exact
PostgreSQL pre/post claim and P3A response-fault vectors and a narrow
single-call executor-to-halt rehearsal pass while preserving separate
evaluation and Auto-Halt authority. The deterministic bundle is
`docs/research/evidence/p3e5-4e-2026-08-24/`; P3E5-5 remains unauthorized.
