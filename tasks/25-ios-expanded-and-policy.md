# Task 25 — Expanded iOS scenarios and store-policy change matrix

Status: [x] Completed

## Goal
Run successful expanded scenarios on physical iOS where feasible and update conservative Apple/Google change classification from current official sources.

## Scope and Non-goals
Scope: selected async/UI/state/ecosystem scenarios, invalid/rollback/restart, current official policy sources, and `docs/store-policy/change-matrix.md`. Non-goals: legal advice, App Store compliance claim, or native manifest/plugin OTA changes.

## Owner
iOS device and policy research specialists with disjoint files; coordinator integrates.

## Dependencies
Tasks 16–24.

## Assumptions
Android-successful interpreted scenarios may technically transfer to iOS, but each needs physical evidence and separate policy classification.

## Work Items
- [x] Select successful scenarios and predeclare device assertions for the
  current-source USB iPhone run.
- [x] Run physical iOS expansion without reinstall: async, UI, Riverpod,
  invalid-signature rejection, rollback, restart, and persistence passed.
- [x] Research current official Apple/Google sources, with FACT,
  INTERPRETATION, ASSUMPTION, and UNKNOWN kept separate.
- [x] Classify required example changes conservatively using exactly `LIKELY
  OTA-SAFE ARCHITECTURALLY`, `STORE RELEASE REQUIRED`, and `POLICY REVIEW
  REQUIRED`.
- [x] Update the store-policy evidence and validate the owned document structure,
  required category coverage, and official-source links. Policy classification
  remains conservative and is not a compliance claim.

## Validation
Policy package: current official Apple and Google sources accessed 2026-08-22;
document structure checked for FACT/INTERPRETATION/ASSUMPTION/UNKNOWN separation;
matrix checked for the three allowed outcomes and all requested change categories;
official-source URLs checked where reachable. Physical package:
`scripts/e1_ios_cross_feature.sh` run `ios-cross-20260822-1` passed on the
AUVANA-signed USB iPhone without reinstall. Technical results and policy
interpretation remain explicitly separate.

## Next Action
No further Phase 0B iOS expansion work is required. The AUVANA-signed broad USB
run passed; future coverage remains Phase 1 work after maintainer review.

## Blockers
None. The earlier missing-account/profile condition was cleared by configuring
the AUVANA team; the old blocker is retained in history only.

## Outcome
The conservative cross-store policy package is complete. Passive text/assets/
localization have only an architectural OTA-safe classification; interpreted
Dart business fixes, UI hierarchy, navigation, pure-Dart dependency changes,
existing-plugin activation, shaders/fonts, and payment behavior remain policy
review gates. Native/build metadata, permissions, plugins, SDKs, and new host
capabilities require store releases. No compliance claim is made. The physical
expansion passed independently of that policy classification.

## References
- `docs/store-policy/apple.md`
- `docs/store-policy/google-play.md`
- `docs/store-policy/change-matrix.md`
- `tasks/24-physical-ios-baseline.md`
- `scripts/e1_ios_cross_feature.sh`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Completed current official Apple/Google policy research and the
  three-outcome change matrix. Corrected the Google interpreter-exception
  overclassification: interpreted business logic, UI hierarchy, navigation,
  and pure-Dart dependency changes remain policy-review-required.
- 2026-08-22: Marked expanded physical iOS work blocked on Task 24's documented
  signing/provisioning prerequisite; no install or device-runtime evidence was
  inferred from the successful unsigned compile.
- 2026-08-22: AUVANA signing became available. The broad current-source USB run
  `ios-cross-20260822-1` passed async, UI, Riverpod, invalid signature,
  rollback, restart, and persistence without reinstall on the physical iPhone.
