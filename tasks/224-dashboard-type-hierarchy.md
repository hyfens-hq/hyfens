# Task 224: Normalize dashboard type hierarchy

Status: [x] Completed

## Goal

Reduce the heavy visual weight across the dashboard while preserving clear hierarchy for display headings, key values, actions, and identity.

## Scope and Non-goals

Scope:

- Replace the dashboard’s overused intermediate `650` weight with the existing loaded `500` and `600` roles.
- Keep major metric values, branding, and other intentionally prominent identity elements emphasized.
- Update the focused dashboard contract and asset version, then verify the rebuilt local dashboard.

Non-goals:

- No font-family swap, new font dependency, color redesign, layout change, or API behavior change.
- No unrelated cleanup or typography changes outside the dashboard stylesheet and its focused contract.

## Owner

Coordinator.

## Dependencies

- Existing dashboard font tokens in `dashboard/tokens.css`.
- Existing UI/display font role contract in `dashboard/test_serve.py`.
- Canonical local Docker dashboard stack.

## Assumptions

- IBM Plex Sans `400/500/600/700` and Bricolage Grotesque `600/700` are the intended available roles.
- A `500` label/body-support role and a `600` hierarchy role provide enough distinction without changing the visual system.

## Work Items

- [x] Audit the current weight declarations and assign lighter semantic roles.
- [x] Update the stylesheet asset version and focused typography contract.
- [x] Run source validation, rebuild the canonical Docker stack, and verify computed live weights.
- [x] Record the outcome and validation evidence.

## Validation

Completed:

- `python3 -m unittest dashboard.test_serve` — 23 tests passed.
- `node --check dashboard/app.js` — passed.
- Live browser check on `/applications` and `/` — ordinary labels, metadata, table headings, captions, controls, and navigation computed at `500` or `600`; page headings computed at `600`; metric values retained `700`; no ordinary representative selector computed at `650+`.
- Live browser confirmed `styles.css?v=224` is loaded, the authenticated app is visible, and the login view is hidden.
- `sh scripts/local-dashboard.sh up` — rebuilt the canonical stack and reseeded local users successfully.
- `docker ps` — dashboard `18083`, control plane `18082`, Postgres, and object store all healthy.

The first live resource-timing probe was not supported by the page runtime; the loaded stylesheet link and computed styles were verified directly instead.

## Next Action

No further action; the coordinator applied the focused CSS change, redeployed it, and completed validation.

## Blockers

None.

## Outcome

Dashboard typography now uses a calmer semantic hierarchy: ordinary labels and metadata use `500`, headings and semantic primary text use `600`, body copy remains `400`, and only intentionally prominent brand/metric identity remains `700`. The nonstandard `650` role was removed from `dashboard/styles.css`, and implicit `strong`/`b` text is capped at `600` unless a more prominent component explicitly overrides it.

## References

- User feedback that most dashboard content feels too bold and is hard on the eyes.
- `dashboard/styles.css`
- `dashboard/tokens.css`
- `dashboard/test_serve.py`

## History

- 2026-09-01: Reserved task 224 for dashboard typography hierarchy normalization.
- 2026-09-01: Mapped dashboard typography to the existing 400/500/600/700 roles, added the semantic strong baseline, bumped the stylesheet asset to `224`, and updated the focused contract.
- 2026-09-01: Rebuilt Docker and verified the live authenticated dashboard and computed typography hierarchy.
