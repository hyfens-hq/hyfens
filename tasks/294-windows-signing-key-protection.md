# Task 294: Windows signing-key protection

Status: [x] Completed

## Goal

Protect private signing-key files on Windows with a current-account-only ACL
and fail closed when the ACL cannot be applied or verified.

## Scope and Non-goals

Scope is public CLI private-key generation/read validation, platform ACL
handling, focused tests, and operator documentation.

Non-goals are key rotation policy, remote key management, cryptographic
algorithm changes, and unrelated credential storage.

## Owner

Public CLI security worker.

## Dependencies

- Existing Ed25519 key format and signing flow.
- Windows `icacls`/current-account identity semantics.
- Existing POSIX permission checks.

## Assumptions

- A private key with unverifiable broad access must not be used for signing.
- Public key files do not require private-key ACLs.
- Tests must remain runnable on non-Windows hosts through injected command
  runners where possible.

## Work Items

- [x] Inspect private-key write/read and platform permission boundaries.
- [x] Apply and verify Windows ACL protection on generation and read.
- [x] Add focused generation/read/failure tests and update documentation.
- [x] Review and run affected public validation.

## Validation

Executed:

- `FLUTTER_ROOT=/Users/princeteck/.puro/envs/default/flutter /Users/princeteck/.puro/envs/stable/flutter/bin/flutter test test/signing_test.dart` passed: 6 tests;
- the same explicit-SDK `flutter analyze` passed for the full `cli/` package and for the focused signing files;
- `git diff --check` passed;
- `scripts/check-oss-boundary.sh` was run but was blocked at the time by an
  unrelated concurrent untracked hosted deployment recipe; no unrelated file
  was changed;
- the full CLI test suite was attempted and reported unrelated environment/toolchain failures (`Dart unknown`, `Isolate.resolvePackageUriSync`, and release-packaging timeouts); the Task 294 focused suite passed.

## Next Action

Hand off the task-owned diff for review. A real Windows-host run of `whoami`
and `icacls` remains platform validation outside this macOS worktree.

## Blockers

None known.

## Outcome

Private-key generation now resolves the current Windows account with `whoami`,
resets the file ACL, removes inherited access, grants only that account full
control, and verifies the resulting `icacls` output. Existing Windows private
key reads perform the same identity lookup and reject missing, inherited, or
broad ACLs before parsing key material. Command, identity, ACL, and parser
failures return `S4005`; POSIX generation continues to use `chmod 600`, and the
Ed25519 JSON format is unchanged.

## References

- `cli/lib/src/signing.dart`
- `cli/test/signing_test.dart`
- `docs/cli.md`
- Helmholtz security review, 2026-09-19

## History

- 2026-09-19: Reserved after review found that Windows private signing-key
  files bypass the existing POSIX-only permission restriction.
- 2026-09-19: Added injected Windows ACL application/read validation, focused
  generation/read/failure tests, and CLI signing-key documentation. Scoped
  analyzer and signing tests passed; broader CLI validation was limited by
  unrelated environment failures and the OSS scan by an unrelated concurrent
  untracked hosted path.
- 2026-09-19: Task 297 moved the public image recipe under the public
  self-hosted path; the OSS boundary scan now passes after the combined
  worktree review.
