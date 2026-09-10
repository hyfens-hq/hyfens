# Task 44 — P2 closure hardening and beta-gate evidence

Status: [x] Completed — bounded execution complete; maintainer review required

## Goal

Close or explicitly preserve the remaining P2 foundation and beta-evidence
gates after the hosted-like Android and iOS conformance-fixture paths passed.
Preserve the runtime as the authority and stop before P3.

## Scope and Non-goals

Scope: reconcile the P2 record; exercise coupled PostgreSQL/object recovery;
add safe digest reconciliation; run disposable TLS/reverse-proxy and
certificate-rotation evidence; exercise credential rotation/revocation;
document customer/local signing recovery; run combined outage/restart and audit
provenance checks; attempt a secondary-app and claim-specific evidence where the
environment permits; rerun physical regression after any delivery changes; and
publish the final P2 review.

Non-goals: changing Architecture B, Patch Format v1, capability v1, exact
application/release/function binding, state-v4 high-water, rollback authority,
customer/local signing custody, or runtime verification; independent customer
app claims when no such app is available; true power-loss unless safely
reproducible; production HA/DR, public-ingress hardening, managed KMS/HSM,
runtime telemetry, dashboards, rollout/cohort features, billing, enterprise
identity, React Native, or store submission.

## Owner

Coordinator. No commit is authorized. Stop at the P2 maintainer-review gate.

## Dependencies

- `tasks/43-p2-managed-cloud-foundation.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_P2_CLOSURE_HARDENING_AND_BETA_GATES.md`;
- `packages/control_plane`, `cli`, Patch Format v1, runtime, and existing
  physical Android/iOS evidence;
- disposable Docker Compose PostgreSQL/MinIO service and available local
  certificate tooling;
- physical Android Wi-Fi and iOS USB fixtures where still connected.

## Assumptions

- PostgreSQL, object storage, HTTP/TLS delivery, and hosted metadata remain
  untrusted runtime inputs.
- Customer/local private signing keys remain outside the service.
- Docker Compose evidence is bounded single-node evidence, not HA/DR or an
  internet-scale capacity result.
- No independent customer application is currently available; P1D-07 remains
  open unless a genuinely independent application is supplied and passes its
  declared matrix.

## Work Items

- [x] Reconcile Task 43, the P2 review, hosted-like evidence, and the Phase 1D
  register with the completed Android physical result.
- [x] Execute coupled PostgreSQL plus object-byte backup/restore and digest
  preservation evidence.
- [x] Add and test safe object/metadata digest reconciliation without signed
  artifact regeneration.
- [x] Execute actual private TLS reverse-proxy traffic and certificate
  rotation evidence.
- [x] Exercise control/delivery credential rotation, expiry, revocation, and
  write-authority separation.
- [x] Document customer/local signing-key recovery boundaries; production
  escrow/KMS/revocation remains explicitly open.
- [x] Run combined outage/recovery and restart-during-mutation drills.
- [x] Extend audit export/retention/hash-chain verification and tamper tests.
- [x] Attempt secondary-app evidence without relabelling repository fixtures
  as independent customer evidence; the available secondary fixture is
  repository-owned, so P1D-07 remains open.
- [x] Assess physical Android/iOS delivery regression applicability after
  delivery hardening changes. No mobile runtime or release artifact changed;
  existing physical evidence is retained and no new post-hardening device
  claim is asserted.
- [x] Record claim-specific Android/iOS, async, interpreter, and multi-function
  evidence only when exact campaigns execute; preserve open gates otherwise.
- [x] Run consolidated validation and update the final P2 review; stop before
  P3.

## Validation

Executed validation:

- `dart format` on the control-plane and CLI changed files: PASS.
- `dart analyze packages/control_plane` and `dart analyze cli`: PASS.
- `dart test` in `packages/control_plane` with external PostgreSQL/MinIO
  containers: 27 tests PASS, 0 failed.
- `dart test --concurrency=1` in `cli`: 39 tests PASS. An earlier parallel
  run timed out in subprocess-heavy tests; the serial run is the authoritative
  result.
- root `dart test`, `flutter test` for both repository fixtures, shell syntax,
  and Python compilation: PASS.
- disposable coupled PostgreSQL/object backup, volume destruction/recreation,
  restore, exact digest/cmp, `tool verify`, reconciliation, audit export,
  idempotent retry, dependency outage/recovery, and restart-during-mutation:
  PASS.
- disposable nginx private TLS health/readiness, CLI deploy with CA A,
  certificate/CA rotation to B, old-CA rejection, CLI deploy with CA B,
  authenticated lookup, and exact artifact fetch: PASS.
- Android/iOS physical evidence remains the previously recorded hosted-like
  and cross-feature conformance-fixture PASS. No mobile runtime or release
  artifact changed in this closure batch, so no new post-hardening physical
  claim is asserted.

Not executed and intentionally still open: independent customer app, true
power-loss, performance/async/multi-function campaigns, production TLS/HA/DR,
managed signing-key recovery, and Apple/Google policy review.

## Next Action

Task 45 is the single final-evidence continuation authorized by the supplied
maintainer instruction. Review its gate disposition together with this
bounded closure evidence. Do not start P3 or treat either task as
beta/production approval.

## Blockers

Independent customer-app validation, true physical power-loss, platform
diagnostic/performance campaigns, public TLS/HA, production key recovery, and
Apple/Google policy review may remain open if their required environment or
authority is unavailable.

## Outcome

Bounded closure work completed. Coupled restore, reconciliation, private TLS
and certificate rotation, credential lifecycle, audit export/tamper, outage,
and restart-during-mutation evidence passed. Independent customer-app,
true-power-loss, production availability/key recovery, performance, and policy
gates remain open. Recommendation: `CONTINUE P2 MANAGED CLOUD FOUNDATION`;
maintainer review is required and P3 remains prohibited.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_P2_CLOSURE_HARDENING_AND_BETA_GATES.md`;
- `/Volumes/970EvoPlus/Downloads/43-p2-managed-cloud-foundation.md`;
- `tasks/43-p2-managed-cloud-foundation.md`;
- `docs/P2_MANAGED_CLOUD_REVIEW.md`;
- `docs/research/evidence/p2-hosted-like-2026-08-23.md`;
- `docs/security/signing-key-recovery.md`;
- `docs/product/phase-1d-conditions.md`.

## History

- 2026-08-23: Reserved Task 44 as the single bounded P2 continuation after
  the supplied closure-hardening instruction. P3 and all explicit non-goals
  remain prohibited.
- 2026-08-23: Completed coupled backup/restore, reconciliation, private
  TLS/certificate rotation, credential lifecycle, audit export/tamper,
  outage, restart-during-mutation, secondary-fixture, and consolidated
  validation evidence. Preserved open beta/production gates and stopped for
  maintainer review.
- 2026-08-23: Task 45 was reserved for the final independent-app, platform,
  performance, async, power-loss, production-operations, and store-policy
  evidence gates. This task's bounded closure results remain unchanged.
- 2026-08-23: Task 49 reconciled the status marker with the completed work
  items and outcome. External/provider and store-policy gates remain open.
