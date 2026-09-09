# Task 16 — Ordinary Widget build interception

Status: [x] Completed

## Goal
Determine whether an ordinary `StatelessWidget.build` can be transparently patched for meaningful UI changes.

## Scope and Non-goals
Scope: text, conditionals, basic hierarchy, styles/properties, child composition, and comparison of direct objects, intermediate descriptions, and registered widget factories. Non-goals: arbitrary Flutter API coverage or a special patch widget.

## Owner
Flutter/compiler specialist; coordinator integrates.

## Dependencies
Tasks 09–15.

## Assumptions
A finite widget capability/factory ABI may safely bridge interpreted construction while retaining transparent method instrumentation.

## Work Items
- [x] Instrument one ordinary `PricingCard.build` and define receiver/context boundary.
- [x] Compare direct object, description, and factory models with evidence.
- [x] Implement the smallest safe model and required UI changes.
- [x] Add widget, invalid-tree, rollback, and unsupported-widget tests.
- [x] Produce `docs/research/widget-patching.md` and validate.

## Validation
Planned: compiler/runtime/widget tests for text, conditional hierarchy, style/property and child changes; unknown factories/properties/types; mounted rebuild; no PatchView/source annotations; focused release integration. Pivot trigger: transparent build interception or safe construction cannot be achieved without invasive compiler/runtime changes.

## Next Action
Begin Task 17 and integrate the widget authority with activation/reset so a
mounted stateful fixture can rebuild through patch and rollback.

## Blockers
None; Tasks 09–15 are complete.

## Outcome
An ordinary build-tool-selected `PricingCard.build` transparently dispatched to
a v9 interpreted description and immutable program-scoped Flutter factory
registry. Real Flutter tests changed text, conditional hierarchy, style, and
composition and proved malformed/factory-failure AOT fallback and base reset.
The supported surface is intentionally finite and does not include callbacks,
raw context/widgets, arbitrary Flutter, or physical release execution.

## References
- `docs/architecture/options.md`
- `docs/research/widget-patching.md`
- `experiments/instrumentation/SPEC.md`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 15 passed signing/rollback review and downstream validation.
- 2026-08-22: Selected pre-registered factories over a bounded node record; rejected direct object construction and a generic remote-widget language for the experiment.
- 2026-08-22: Initial implementation passed 166 instrumentation and four Flutter tests; adversarial review found a program-allowlist bypass, lazy nested typing, enum/depth/canonicality issues, and insufficient real-Flutter failure/rollback evidence.
- 2026-08-22: Fixed all blocker/high findings and bounded medium findings; independent re-review found no remaining blocker/high. Syntax-only semantic ownership, signed-controller lifecycle, and real Flutter release-AOT remain explicit conditions.
- 2026-08-22: Final format/analysis passed; instrumentation 170/170, Flutter fixture 4/4, and dependent loader 25/25 passed.
