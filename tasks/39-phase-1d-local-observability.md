# Task 39 — Phase 1D local observability

Status: [x] Completed

## Goal

Provide a bounded local developer status/diagnostics projection for runtime
integration readiness without adding a protocol, remote introspection, or
changing Patch Format v1, capability v1, or controller lifecycle semantics.

## Scope and Non-goals

Scope: audit the existing CLI, local tool store, environment, and diagnostics
seams; add the smallest safe `tool status` and `tool status --json` surface if
those seams are sufficient; add focused tests; update the diagnostics contract
and a focused Phase 1D observability research note.

Non-goals: Patch Format v1, capability v1, controller state-v4 semantics,
physical-device workflows, hosted/cloud services, telemetry, remote or
unauthenticated app-runtime introspection, source/guest-data export, key
inspection, absolute-path output, `docs/PHASE_1D_REVIEW.md`, and Task 38.

## Owner

Phase 1D local observability/diagnostics worker.

## Dependencies

- Existing local CLI under `cli/`;
- existing stable diagnostics under `cli/lib/src/diagnostics.dart`;
- existing tool store and environment snapshot seams;
- frozen Phase 1D boundaries recorded in `tasks/38-phase-1d-runtime-integration-readiness.md`.

## Assumptions

- A status command may report only local project metadata, bounded artifact
  inventory, and the existing local toolchain snapshot.
- Application runtime state remains unavailable to the CLI unless an existing
  authenticated local seam already exposes it; no new seam is authorized here.
- Status output must contain no keys, secrets, absolute paths, URLs, release or
  patch contents, source records, or unbounded guest data.
- The shared worktree is user-owned and already uncommitted; no unrelated file
  may be reverted and no commit will be created.

## Work Items

- [x] Audit the current CLI/runtime status and diagnostics seams.
- [x] Implement the bounded local status projection and command registration.
- [x] Add focused CLI/status tests for human/JSON-safe output and bounded scans.
- [x] Update `docs/diagnostics.md` and the focused research note.
- [x] Review the task-owned diff and run scoped format, analyze, and tests.

## Validation

Completed targeted checks:

- `dart format cli/lib/src/cli_runner.dart cli/lib/src/diagnostics.dart cli/lib/src/toolchain.dart cli/test/status_test.dart`;
- `dart analyze cli`;
- `dart test cli/test/status_test.dart cli/test/cli_process_test.dart`.

Results: formatting passed with zero changes; `dart analyze cli` passed with no
issues; the correctly scoped CLI tests passed (`6` tests). An initial test
attempt from the repository root failed because the CLI package could not be
resolved; that command-context error was corrected by rerunning from `cli/`.

## Next Action

No further action for Task 39. The local status surface is complete and ready
for coordinator integration into the Phase 1D review.

## Blockers

None.

## Outcome

Completed. `tool status` and `tool status --json` provide a bounded local-only
projection of project/toolchain state and artifact counts without exposing
application runtime state, keys, URLs, absolute paths, source records, patch
bytes, or arbitrary filesystem errors. Inventory scans are capped and explicit
when truncated.

## References

- `docs/diagnostics.md`
- `docs/architecture/toolchain.md`
- `docs/architecture/runtime.md`
- `tasks/38-phase-1d-runtime-integration-readiness.md`

## History

- 2026-08-23: Task 39 reserved after the local CLI/runtime seam audit. The
  existing CLI can support a local artifact/toolchain status projection, but
  no app-runtime status bridge will be added in this package.
- 2026-08-23: Added the local-only `tool status`/`--json` projection, bounded
  inventory, path-free diagnostics, focused tests, and observability notes.
  Formatting and `dart analyze cli` passed. The correctly scoped CLI test run
  exposed the two blockers recorded above; status remains In Progress.
- 2026-08-23: Coordinator corrected nested release metadata counting and made
  the subprocess test resolve the CLI script from either package or repository
  working directory. Formatting, analysis, and six focused CLI tests passed;
  Task 39 completed.
