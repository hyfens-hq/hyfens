# Task 295: CLI fallback secret duplication

Status: [x] Completed

## Goal

Prevent native credential-store fallback from leaving redundant plaintext
session copies while preserving safe endpoint binding and logout cleanup.

## Scope and Non-goals

Scope is public CLI `AuthStorage` fallback behavior, migration compatibility,
focused tests, and documentation.

Non-goals are cryptographic session redesign, server token lifetime changes,
native credential-store implementation, and unrelated CLI commands.

## Owner

Public CLI security worker.

## Dependencies

- Task 289 native credential-store adapters and endpoint-keyed catalog.
- Existing legacy `session.json` migration behavior.
- Logout and profile-removal semantics.

## Assumptions

- Native-store failure must be observable through the existing fallback path.
- At most one permission-locked fallback file may contain a live session.
- Existing users must not silently lose the ability to migrate legacy sessions.

## Work Items

- [x] Trace native failure, fallback, migration, and logout paths.
- [x] Remove redundant live-session copies or make any compatibility projection
  non-secret and explicit.
- [x] Add regression tests proving endpoint isolation and complete cleanup.
- [x] Review and run affected focused validation.

## Validation

Completed:

- Focused auth-storage tests for native failure, fallback, migration, endpoint
  isolation, and logout: 8 tests passed with
  `FLUTTER_ROOT=/Users/princeteck/.puro/envs/stable/flutter
  /Users/princeteck/.puro/envs/stable/flutter/bin/cache/dart-sdk/bin/dart
  /Users/princeteck/.puro/shared/flutter_tools/9584c6713b324636289d067944a46fd6b49df14b/flutter_tools.snapshot
  test test/auth_storage_test.dart`. The normal `dart` wrapper could not start
  because its x86_64 Puro binary is incompatible with this arm64 host.
- Scoped analyzer: `/Users/princeteck/.puro/envs/default/flutter/bin/cache/dart-sdk/bin/dart
  analyze lib/src/auth_storage.dart test/auth_storage_test.dart` — no issues
  found.
- Formatting check: `/Users/princeteck/.puro/envs/default/flutter/bin/cache/dart-sdk/bin/dart
  format lib/src/auth_storage.dart test/auth_storage_test.dart` — clean.
- `git diff --check` for the Task 295 files — clean.
- `sh scripts/check-oss-boundary.sh` — clean.

The full CLI package test command could not load because the concurrently
edited `cli/lib/src/signing.dart` is currently missing `_runSigningProcess`,
`_currentWindowsPrincipal`, and `_verifyWindowsAcl`. That unrelated Task 294
compile failure was left untouched.

## Next Action

Hand off the reviewed Task 295 changes. No commit, push, deployment, or pull
request was performed.

## Blockers

None known.

## Outcome

Native-store failure is now sticky for the storage instance: endpoint-bound
sessions go to the endpoint-keyed permission-locked `credentials` file only,
and a matching legacy `session.json` projection is removed after the keyed
write succeeds. Existing legacy sessions remain readable only for their bound
endpoint, endpoint-omitted calls without a known profile retain the old
compatibility write, and targeted/all-session logout cleanup remains intact.

## References

- `cli/lib/src/auth_storage.dart`
- `cli/test/auth_storage_test.dart`
- `docs/cli.md`
- Task 289 CLI/MCP security hardening
- Helmholtz security review, 2026-09-19

## History

- 2026-09-19: Reserved after review found that native-store failure writes
  live session secrets to both endpoint-keyed credentials and legacy session
  projection files.
- 2026-09-19: Kept endpoint-bound fallback writes single-copy after native
  failure, added matching legacy cleanup and endpoint-omitted fallback
  coverage, and completed focused validation. Broader package loading remains
  blocked by the unrelated concurrent signing edit recorded above.
