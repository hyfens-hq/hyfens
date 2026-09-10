# Task 240 — Flavor entrypoints and project detach

Status: [x] Completed

## Goal

Make the CLI work predictably with Flutter applications whose Android/iOS
flavors use different Dart entrypoint files, and provide a clearly named,
explicitly confirmed command for removing Hyfens project integration state.

## Scope and Non-goals

Scope:

- Add validated `--flavor` and `--entrypoint` selection for release, analyze,
  and patch workflows.
- Support target/flavor-to-entrypoint mappings in `tool.yaml`.
- Persist the selected entrypoint in release metadata so patch analysis uses the
  same application boundary.
- Pass the selected entrypoint and flavor to the isolated Flutter build.
- Add `hyfens detach` with dry-run and explicit confirmation safeguards.
- Document flavor configuration, the distinction between runtime `rollback`
  and project `detach`, and the fact that detach does not edit Flutter source.
- Add focused regression tests for selection, validation, persistence, and
  detach safety.

Non-goals:

- No change to Patch Format, runtime rollback semantics, auth, control-plane
  APIs, or dashboard behavior.
- No automatic guessing among ambiguous flavor entrypoints.
- No removal of Flutter source, native project files, user configuration, or
  remote releases during `detach`.
- No repository commit, tag, or deployment unless separately requested.

## Owner

Coordinator / CLI toolchain

## Dependencies

- Existing `tool.yaml` v1 configuration and local `.tool` store.
- Existing release/analyze/patch instrumentation pipeline.
- Existing `rollback` and `cleanup` safety contracts.

## Assumptions

- Patchable Dart entrypoints are project-relative files under `lib/`.
- Existing projects without flavor configuration continue to use
  `lib/main.dart`.
- A flavor-specific application ID may be supplied through the
  `application_ids` target/flavor mapping, with `application_id` as the
  fallback; this task does not infer native IDs from arbitrary Gradle/Xcode
  build logic.
- The working tree contains unrelated user changes; only task-owned files and
  directly affected CLI/docs/tests are to be changed.

## Work Items

- [x] Define a single entrypoint-selection and validation seam.
- [x] Add configuration and CLI option support.
- [x] Persist and reuse selection across release/analyze/patch/build.
- [x] Implement safe `hyfens detach` project cleanup.
- [x] Add documentation and focused regression coverage.
- [x] Review and validate the combined task diff.

## Validation

Completed validation:

- `dart format --output=none` on the changed Dart files: PASS.
- `dart analyze` in `cli/`: PASS (`No issues found!`).
- Consolidated CLI, MCP, flavor, detach, configuration, discovery, onboarding,
  and overlay tests: PASS (79 tests).
- Full `dart test --concurrency=1`: PASS (135 tests).
- Release/analyze selection, missing-entrypoint rejection, multi-baseline
  selection, path validation, and detach safety regressions: PASS.
- No destructive commands were run against a user project and no Flutter
  source/native fixture files were changed.

## Next Action

No further action for this bounded task. Use the documented flavor selection
and `hyfens detach` workflows.

## Blockers

None currently.

## Outcome

Implemented and verified. Flavor-specific releases now require an explicit or
configured Dart entrypoint, preserve the native flavor/application identity,
and reuse the recorded selection for analysis and patching. `hyfens detach`
provides dry-run and exact `DETACH` confirmation, refuses ambiguous or unsafe
store contents, retains keys only with `--keep-keys`, and never removes Flutter
source, native files, project dependencies, or remote state. Runtime
`hyfens rollback` remains a separate signed rollback-to-base operation.

## References

- `cli/lib/src/configuration.dart`
- `cli/lib/src/discovery.dart`
- `cli/lib/src/toolchain.dart`
- `cli/lib/src/cli_runner.dart`
- `docs/cli.md`
- User-provided flavor project at `.../kavach360-worktrees/hyfens_test/apps/kavach360`

## History

- 2026-09-03: Reserved task 240 for the bounded flavor-entrypoint and project-detach enhancement.
- 2026-09-03: Implemented target/flavor entrypoint resolution, release identity
  persistence, safe detach, documentation, and regression tests.
- 2026-09-03: Completed static analysis, scoped validation, and the full Dart
  suite with serialized test concurrency.
