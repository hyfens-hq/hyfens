# Task 221: Dashboard visual rhythm and record-sheet styling

Status: [x] Completed

## Goal

Correct the repeated dashboard spacing, hierarchy, and control-state issues shown in the Applications view and the related record pages, while providing the visual layer for a stable exact-record bottom sheet.

## Scope and Non-goals

Scope:

- Audit and correct shared dashboard card, panel, page-heading, collection-toolbar, input, select, table, and session-boot spacing across all record pages.
- Align the control-plane eyebrow and update timestamp on a shared baseline.
- Remove the inline exact-record divider treatment and style the fixed bottom-sheet overlay, backdrop, dialog, and responsive states.
- Style the organization switcher state in the sidebar without exposing an unnecessary organization ID in the card.
- Preserve the existing dark/light token system, local icon assets, typography roles, clean routes, and read-only product boundary.

Non-goals:

- No changes to dashboard behavior, identity data, API contracts, routing, or server code.
- No new UI dependency, icon family, animation library, or unrelated redesign.
- No changes to completed task files or unrelated worktree changes.

## Owner

GPT-5.6-Luna Max, fast mode worker. The worker owns `dashboard/styles.css` only. Coordinator reviews and integrates the result.

## Dependencies

- Task 222 supplies the stable markup/classes for the session boot state, organization selector, and exact-record bottom sheet.
- Existing tokens in `dashboard/tokens.css` and local assets under `dashboard/icons/`.
- Existing shared renderers and collection pages in `dashboard/app.js`.

## Assumptions

- Existing CSS custom properties remain the source of truth for color, radius, and motion.
- Hairline borders use the project’s established `0.5px` treatment, without stacked focus outlines or duplicate borders.
- The dashboard is a dense, read-only B2B control plane, so spacing should be calm and scannable rather than decorative.

## Work Items

- [x] Audit repeated layout and control selectors against the live Applications and other record-page states.
- [x] Fix shared card/panel padding, toolbar label-to-field spacing, control gutters, and responsive wrapping.
- [x] Align heading metadata and remove the inline exact-record top rule.
- [x] Add responsive bottom-sheet, backdrop, focus, and reduced-motion styling for the behavior package.
- [x] Review the combined CSS diff and report changed selectors plus validation evidence to the coordinator.

## Validation

Completed:

- `python3 -m unittest dashboard.test_serve` — 23 tests passed.
- `node --check dashboard/app.js` — passed.
- Live browser checks confirmed the shared toolbar uses `12px` gap and padding, the field label gap is `7px`, the heading metadata uses a baseline, and exact-record opening leaves table/panel geometry unchanged.
- Live browser check confirmed the final desktop sheet is `1600px` wide at a `2560px` viewport; responsive `100%`/`88dvh` rules remain in place for narrow viewports.
- Normal and focus control checks confirmed a single hairline focus treatment; exact-record content has no top border; reduced-motion rules remove sheet movement.

## Next Action

No further action; the coordinator reviewed the combined CSS and completed the consolidated validation pass.

## Blockers

None currently.

## Outcome

The shared dashboard visual system now uses consistent panel/toolbar rhythm, aligned heading metadata, hairline control states, an opaque bottom-sheet treatment, and a neutral session-boot surface. The redundant inline exact-record divider was removed without changing the read-only record contract.

## References

- User screenshots for Applications spacing, exact-record expansion, organization context, and heading alignment.
- User-provided dashboard design transcript emphasizing simple cards, clear grouping, nonblocking overlays, and informative empty/error states.
- `dashboard/styles.css`
- `dashboard/tokens.css`

## History

- 2026-09-01: Reserved task 221 after the live repro confirmed uneven toolbar gutters, heading metadata misalignment, and inline exact-record row growth.
- 2026-09-01: Implemented and reviewed shared panel, toolbar, heading, control, session-boot, and bottom-sheet styling; verified the result in the canonical local Docker dashboard.
- 2026-09-01: Widened the desktop bottom sheet and strengthened its scrim after the follow-up live screenshot showed the initial sheet reading as a narrow floating card.
