# Task 53 — P3E aggregation and conservative halt design

<!-- markdownlint-disable MD013 -->

Status: [x] Completed — design-only gate complete; maintainer review required

## Goal

Design a deterministic, bounded P3E health aggregation and conservative
automatic-halt policy over the completed P3D observation contract. The design
must stop future rollout offers when approved patch-safety evidence is
sufficient, while never becoming runtime trust, changing Patch Format v1,
lowering high-water, or remotely invalidating installed healthy code.

## Scope and Non-goals

Scope: document the P3D input contract; accepted/duplicate/late/quarantined/
rejected/security-rejected inclusion rules; exact aggregate identity;
deduplication and contribution caps; deterministic counters and metric
denominators; minimum sample, window, missing-data, freshness, confidence,
coverage, and small-cohort behavior; conservative decision vocabulary;
automatic-halt and manual override/resume semantics; audit/persistence/API
boundaries; recomputation/retention/deletion; stale/concurrent transition
protection; simulation vectors; calibration; provider and OSS boundaries; and
threats/entry criteria.

Non-goals: implementing aggregation services, tables, migrations, endpoints,
queues, workers, schedulers, automatic halt, automatic expansion, dashboards,
alerts, health-event client uploads, runtime changes, Patch Format/capability
changes, signing/key custody, rollback implementation, provider deployment,
P3F operator expansion, P3G dashboard work, React Native, billing, enterprise
features, store submission, or legal/compliance claims.

## Owner

Coordinator. No commit is authorized. Stop at the P3E maintainer-review gate.

## Dependencies

- supplied `/Volumes/970EvoPlus/Downloads/CODEX_TASK53_P3E_DESIGN_GATE.md`;
- `tasks/50-p3a-rollout-domain-and-eligibility.md`;
- `tasks/52-p3d-health-event-ingestion.md`;
- `docs/P3_ROLLOUT_OBSERVABILITY_DESIGN.md`;
- `docs/P3D_HEALTH_EVENT_REVIEW.md`;
- `packages/control_plane` P3A rollout, P3D observation, audit, and
  PostgreSQL expected-revision CAS boundaries.

## Assumptions

- P3D is complete only for its bounded ingestion scope; no mobile, provider,
  beta, production, store, or legal gate is relabelled.
- P3D `accepted`, `late`, and `quarantined` records are the raw aggregate
  input. Rejected and security-rejected requests remain bounded audit/quality
  evidence and do not become health events.
- P3A `HALTED` remains terminal for a rollout record; resume requires a fresh
  replacement rollout/revision and observation window.
- Server receipt time is authoritative for windows; client time is diagnostic.
- Numeric thresholds, privacy suppression values, retention periods, and
  contribution limits require maintainer approval and empirical calibration.
- The existing P3D PostgreSQL CAS is the distributed transition boundary; the
  File adapter remains single-node only.

## Work Items

- [x] Read the supplied Task 53 design-gate requirements through EOF and
  preserve its design-only stopping point.
- [x] Inspect P3A lifecycle semantics, P3D observation dispositions, event
  vocabulary, audit boundary, and PostgreSQL expected-revision CAS.
- [x] Define event inclusion/exclusion, category mapping, exact aggregate
  identity, event/logical deduplication, late/quarantine, and deterministic
  serialization rules.
- [x] Define counters, numerator/denominator metrics, minimum samples,
  observation windows, missing-data behavior, freshness/coverage flags, and
  small-cohort privacy handling without selecting production thresholds.
- [x] Define decision vocabulary, no-auto-expansion semantics, conservative
  halt behavior, failure classes, runtime-fault/rollback/fallback handling,
  poisoning resistance, contribution limits, and manual override/resume.
- [x] Define two-person control, audit integration, conceptual persistence,
  recomputation/retention/deletion, API boundary, stale evaluation, CAS
  concurrency, scheduling, and versioning.
- [x] Provide deterministic simulation vectors, calibration/independent-app
  dependencies, provider boundary, OSS/commercial boundary, threat model,
  implementation sequence, entry criteria, and unresolved decisions.
- [x] Create `docs/P3E_AGGREGATION_HALT_DESIGN.md` and preserve the frozen
  Architecture B, Patch Format v1, capability v1, high-water, signing,
  runtime-authority, and rollback invariants.
- [x] Review the task-owned documents for design-only scope, accidental
  implementation, unsupported production thresholds, runtime-trust weakening,
  and open-gate preservation.
- [x] Run documentation-only validation and stop at maintainer review; do not
  implement P3E, P3F, or P3G.

## Validation

Validation completed on 2026-08-24:

- `markdownlint docs/P3E_AGGREGATION_HALT_DESIGN.md
  tasks/53-p3e-aggregation-and-conservative-halt-design.md` — passed.
- `rg -n '[[:blank:]]+$'` over both task-owned documents — no matches;
  trailing whitespace passed.
- `git diff --no-index --check /dev/null` for each new document — passed.
- `rg -c '^## '` over the design document — 47 required section headings;
  passed.
- Required-topic phrase coverage, frozen-invariant review, and design-only
  boundary scan — passed; only the two task-owned documentation files were
  created and no `packages/`, `experiments/`, `fixtures/`, database, or
  runtime file was modified by this task.
- Repository-path existence checks for the referenced P3A/P3D/design/domain
  files — passed; no Markdown links were present in the new documents.
- Secret-pattern scan over both task-owned documents — passed.
- Deterministic-vector consistency review — passed as a documentation review;
  vectors are specified but intentionally not executed in this design-only
  task.

No Dart, Flutter, control-plane, database, queue, endpoint, scheduler,
physical-device, provider, or runtime tests were run or required. No P3E
implementation was added.

## Next Action

Maintainer reviews `docs/P3E_AGGREGATION_HALT_DESIGN.md` and explicitly chooses
one of the Task 53 decision outcomes. Until approval is recorded, do not begin
P3E-1 implementation, P3F operator expansion, P3G dashboard work, scheduling,
automatic halt, or automatic expansion.

## Blockers

Implementation is intentionally blocked pending explicit maintainer approval
of the P3E entry criteria. The following existing gates also remain binding:

- P1D-01 true power loss;
- P1D-03 iOS diagnostics limitations;
- P1D-04 broad iOS performance;
- P1D-07 independent application;
- P1D-09 interpreter attribution;
- P1D-18 Apple/Google/legal review;
- provider edge/durability/HA/DR/secrets/provenance/monitoring/RPO/RTO;
- beta, production, and store readiness.

These are not relabelled by P3E design.

## Outcome

P3E design is complete for the bounded gate. The design keeps observations
advisory, makes aggregates exact-scope and immutable, separates accepted/late/
quarantined/rejected evidence, caps duplicate and per-installation influence,
requires explicit sample/coverage/freshness evidence, and routes any future
halt through the existing P3A revision/CAS/audit state machine. It prohibits
automatic expansion, runtime rollback, high-water changes, trust weakening,
and store/provider/legal claims.

The recommendation recorded in the design is `AUTHORIZE P3E IMPLEMENTATION
WITH CONDITIONS`; this is not inferred maintainer approval. The actual
authorized state at task completion is `AUTHORIZE P3E DESIGN ONLY — COMPLETE`.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK53_P3E_DESIGN_GATE.md`;
- `/Volumes/970EvoPlus/Downloads/P3D_HEALTH_EVENT_REVIEW.md`;
- `/Volumes/970EvoPlus/Downloads/52-p3d-health-event-ingestion.md`;
- `tasks/50-p3a-rollout-domain-and-eligibility.md`;
- `tasks/52-p3d-health-event-ingestion.md`;
- `docs/P3_ROLLOUT_OBSERVABILITY_DESIGN.md`;
- `docs/P3D_HEALTH_EVENT_REVIEW.md`;
- `packages/control_plane/lib/src/rollout.dart`;
- `packages/control_plane/lib/src/observation.dart`.

## History

- 2026-08-24: Reserved Task 53 as the next monotonic task number after the
  completed Task 52. Confirmed the supplied authorization is design-only and
  preserved all P3A/P3D/runtime trust invariants.
- 2026-08-24: Created the 47-topic P3E aggregation/conservative-halt design,
  including deterministic event handling, metric/threshold boundaries,
  privacy/poisoning resistance, immutable decisions, P3A CAS integration,
  simulation vectors, calibration dependencies, and unresolved decisions.
- 2026-08-24: Completed documentation-only review and validation. No P3E
  implementation, runtime change, schema, endpoint, worker, scheduler,
  dashboard, provider, or mobile test was started. Stopped at maintainer
  review as required.
