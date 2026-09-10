# Task 05 — Architecture and policy comparison

Status: [x] Completed

## Goal
Compare explicit patch views, build-time instrumentation, Kernel transformation, and a Flutter/Dart fork without selecting a winner ahead of evidence; establish official store-policy constraints.

## Scope and Non-goals
Scope: `docs/architecture/options.md`, Apple/Google policy notes, capability-model implications, patch-container trade-offs, security/rollback requirements, and initial change classification. Non-goals: final container selection, compliance guarantees, or production implementation.

## Owner
Coordinator with separate Apple, Google Play, and instrumentation-seam research specialists; coordinator retains task-file and architecture-document ownership.

## Dependencies
Tasks 02–04 provide core technical evidence; official Apple/Google policy sources may be researched in parallel.

## Assumptions
Policy text permits an architectural risk assessment but not a definitive approval prediction.

## Work Items
- [x] Research current official Apple policy into `docs/store-policy/apple.md`.
- [x] Research current official Google Play policy into `docs/store-policy/google-play.md`.
- [x] Research source-level versus Kernel-level automatic instrumentation seams into `docs/research/instrumentation-seams.md`.
- [x] Separate FACT, INTERPRETATION, ASSUMPTION, and UNKNOWN; classify representative changes.
- [x] Compare architectures A–D across every requested criterion.
- [x] Document capability registry, security/rollback boundaries, format trade-offs, and maintenance burden without premature selection.
- [x] Review citations, consistency, and unresolved evidence gaps.

## Validation
Verified that policy citations use official Apple/Google sources, the options matrix covers every requested dimension, and architectural conclusions trace to Tasks 02–04 or are labeled inference/unknown. Markdown trailing-whitespace and internal-link checks passed across `docs/` and `tasks/`; research specialists separately link-checked competitor/upstream citations, and primary serialization sources were accessed during the comparison.

## Next Action
Execute Task 06 E0 on the installed Flutter/Dart baseline, then proceed to Android E1 only if E0 passes its exit criteria.

## Blockers
None. Policy approval remains an external production blocker, not a blocker to the research experiment.

## Outcome
Compared A–D without selecting a production winner. Architecture B source-overlay/callee-entry instrumentation is the cheapest next proof; C is gated on B's semantic/source-map failures, A remains the explicit-view fallback, and D requires evidence that no-fork approaches cannot meet defined thresholds.

## References
- `docs/competitors/`
- `docs/research/flutter-aot.md`

## History
- 2026-08-22: Task number reserved before delegation.
- 2026-08-22: Apple and Google Play policy research packages assigned.
- 2026-08-22: Google Play policy document completed from official sources; custom Dart-bytecode treatment and material-change thresholds remain unknown.
- 2026-08-22: Apple policy document completed from official sources; production iOS code OTA remains review-gated because current public provisions do not resolve this mechanism.
- 2026-08-22: Instrumentation seam research completed; source-overlay callee-entry rewriting is the cheapest first proof, while the exposed Kernel transformer is post-TFA and not a clean pre-tree-shaking plug-in.
- 2026-08-22: Completed architecture, policy, capability, security/rollback, and format synthesis after documentation validation.
