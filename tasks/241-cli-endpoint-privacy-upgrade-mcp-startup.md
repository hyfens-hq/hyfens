# Task 241 — CLI endpoint privacy, upgrade, and MCP startup

Status: [x] Completed

## Goal

Remove intentional exposure of the managed Hyfens Cloud API URL from public CLI
help/output and documentation, add a secure self-update command for installed
CLI binaries, and make `hyfens mcp` visibly announce that its stdio server is
running without contaminating MCP protocol output.

## Scope and Non-goals

Scope:

- Audit and replace user-facing managed endpoint examples and display strings.
- Preserve the internal managed Cloud endpoint and all self-hosted endpoint
  configuration behavior.
- Add `hyfens upgrade` for latest stable release installation using the public
  release archive/checksum contract.
- Register the existing built-in MCP server as `hyfens mcp` and write a clear
  startup message to stderr only.
- Add focused regression tests and update directly affected CLI documentation.

Non-goals:

- No change to the control-plane API path, auth protocol, release format, or
  package-manager publication.
- No dashboard, runtime, Patch Format, or self-hosting architecture changes.
- No arbitrary remote script execution, raw credential output, or endpoint
  redaction of user-supplied self-hosted URLs.
- No tag, release, deployment, or repository commit unless separately
  requested.

## Owner

Coordinator / CLI toolchain

## Dependencies

- Existing `ControlPlaneProfile` and authenticated profile storage.
- Existing GitHub Release archive and `SHA256SUMS` contract.
- Existing `HyfensMcpServer` stdio adapter and `dart_mcp` dependency.
- Dart `dart:io` networking and process/file primitives available to native
  CLI releases.

## Assumptions

- The managed Cloud endpoint remains an internal implementation default and is
  represented to users as `Hyfens Cloud (managed)`.
- Self-hosted endpoint URLs remain visible where users need to confirm or
  configure their own server.
- `hyfens upgrade` is intended for a compiled release binary; source-tree
  `dart run` invocations receive an actionable message rather than replacing a
  Dart executable.
- The current dirty worktree contains unrelated user changes; only files
  directly required by this task will be edited.

## Work Items

- [x] Audit endpoint references and define safe display boundaries.
- [x] Implement endpoint-safe CLI output and documentation updates.
- [x] Implement and register `hyfens upgrade` with checksum verification.
- [x] Register MCP command and add stderr startup feedback.
- [x] Add focused tests and review the combined task diff.
- [x] Run scoped and required full validation.

## Validation

Planned:

- Focused CLI endpoint, help, upgrade, and MCP protocol tests.
- `dart format` on task-owned Dart changes.
- `dart analyze` in `cli/`.
- Full serialized CLI test suite because this changes public CLI contracts.

Completed:

- `dart format` on task-owned Dart changes — PASS.
- `dart analyze` in `cli/` — PASS (`No issues found!`).
- Focused endpoint/help/upgrade/MCP/onboarding tests — PASS (77 tests).
- Full serialized CLI suite, `dart test --concurrency=1` — PASS (147 tests).
- Supported native bundle smoke, `dart build cli -t bin/hyfens.dart` — PASS;
  bundled `hyfens --version`, `--help`, and `mcp --help` passed.
- `git diff --check` on task-owned tracked files — PASS.
- Endpoint audit — PASS for active CLI help/output and active documentation.
  The exact managed URL remains only in internal routing/persistence code,
  dashboard routing, tests, and historical readiness evidence; self-hosted
  endpoint display remains intentionally visible.
- Direct `dart compile exe` smoke — not applicable: Dart rejects this CLI's
  existing `objective_c` build hook for that command and directs callers to
  `dart build cli`, which passed above.

## Next Action

No further action in this task. The maintainer may review and commit the
task-scoped changes when ready.

## Blockers

None currently.

## Outcome

Completed. Managed Cloud endpoint selection and persistence remain exact for
network routing and host-bound credential lookup, while CLI/MCP profile,
status, login, help, and diagnostic projections use `Hyfens Cloud (managed)`.
Self-hosted URLs remain visible where operators need to identify their server.

Added `hyfens upgrade` with latest-stable and explicit-version modes, SHA-256
verification, safe archive validation/extraction, atomic activation for the
managed installer layout, direct-binary replacement, and source-tree refusal.
It does not modify profiles, credentials, project files, or shell startup files.

Registered `hyfens mcp` over stdio with active/named profile support and a
startup message on stderr; stdout remains reserved for MCP protocol traffic.
Updated help, endpoint/privacy documentation, MCP documentation, and focused
regression coverage.

## References

- `cli/lib/src/cli_runner.dart`
- `cli/lib/src/profile.dart`
- `cli/lib/src/mcp/mcp_server.dart`
- `scripts/install-hyfens.sh`
- `scripts/cli-release/release_support.dart`
- `docs/cli.md`
- `README.md`
- `cli/lib/src/upgrade.dart`
- `cli/test/upgrade_test.dart`
- `cli/test/cli_help_test.dart`
- `cli/test/mcp_protocol_test.dart`
- `cli/test/cli_process_test.dart`

## History

- 2026-09-03: Reserved task 241 for endpoint privacy, in-CLI upgrade, and MCP
  stdio startup feedback.
- 2026-09-03: Completed endpoint-safe output, checksum-verified upgrade,
  registered MCP command startup feedback, documentation, focused tests, full
  serialized suite, and supported native bundle validation.
