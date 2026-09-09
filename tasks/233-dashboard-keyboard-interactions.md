# Dashboard keyboard interactions and shortcuts

Status: [x] Completed

## Goal

Add predictable, discoverable keyboard interactions to the authenticated dashboard without hijacking text-entry controls.

## Scope and Non-goals

Scope:

- Add a keyboard-shortcuts help dialog and a visible entry point in the dashboard shell.
- Support `/` for search focus, `r` for refresh, `t` for theme toggle, and Escape for active transient layers.
- Preserve and document existing native control, tab-list, focus-trap, and menu keyboard behavior.
- Keep keyboard focus contained in the shortcuts dialog and restore focus when it closes.

Non-goals:

- No route, API, authentication, data, or persistence changes.
- No new dependencies or replacement of native select, button, link, or form interactions.
- No keyboard shortcuts while the user is typing in an editable control or while another blocking layer owns focus.

## Owner

Coordinator / dashboard UI implementation

## Dependencies

- Existing dashboard shell in `dashboard/index.html`, `dashboard/app.js`, and `dashboard/styles.css`.
- Existing source-contract tests in `dashboard/test_serve.py`.

## Assumptions

- The current dashboard shell is the only surface that should receive global shortcuts.
- Existing native browser keyboard semantics are sufficient for ordinary controls.
- The existing toast and focus styles are the appropriate feedback primitives.

## Work Items

- [x] Add shortcuts trigger, dialog markup, and ARIA metadata.
- [x] Add guarded global shortcuts and dialog focus management.
- [x] Style the dialog and shortcut key rows consistently with the low-border dashboard system.
- [x] Add focused source-contract coverage, update asset versions, and validate the local deployment.

## Validation

- `node --check dashboard/app.js` — passed.
- `python3 -m unittest dashboard.test_serve` — 29 tests passed.
- `sh scripts/local-dashboard.sh up` — rebuilt and restarted the local dashboard successfully.
- Served `http://127.0.0.1:18083/` — returned 200 with `styles.css?v=234` and `app.js?v=229` plus the shortcuts markup.
- Live browser smoke test — `?`, Escape/focus restoration, Tab/Shift+Tab containment, `/`, editable-field guard, `t`, and `r` all behaved as expected; no browser warnings or errors.

## Next Action

Hand off the rebuilt local dashboard. No further action is required for this bounded keyboard interaction package.

## Blockers

None.

## Outcome

Implemented and validated. The authenticated dashboard now exposes a shortcuts help dialog and supports guarded `/`, `r`, `t`, and Escape interactions while preserving native control behavior.

## References

- User request: integrate keyboard base interactions and shortcuts in the dashboard.
- Existing dashboard keyboard handlers for auth tabs, intake tabs, record drawer, account menu, sidebar, and global search.
- Local dashboard smoke target: `http://127.0.0.1:18083/`.

## History

- 2026-09-02: Reserved task 233 and defined the bounded keyboard interaction scope.
- 2026-09-02: Implemented the shortcuts dialog, guarded global shortcuts, focus management, styles, and source-contract coverage; rebuilt and smoke-tested the local dashboard.
