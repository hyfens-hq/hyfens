# Task 293: Bundle trust-boundary hardening

Status: [x] Completed

## Goal

Ensure bundle import and admission verify signatures against a control-plane
trust policy rather than a key selected by request headers.

## Scope and Non-goals

Scope is the public control-plane bundle HTTP/service seam, server-owned
trust-policy configuration and production wiring, CLI compatibility, regression
tests, and operator documentation.

Non-goals are private service changes, release redesign, history rewriting,
and weakening existing tenant/idempotency checks.

## Owner

Public control-plane security worker.

## Dependencies

- Existing `ReleaseBundle` verification and release key records.
- A reviewable control-plane trust-policy source/configuration.
- Existing bundle import/admission authorization and audit paths.

## Assumptions

- A caller with bundle mutation capability must not be able to introduce a new
  trust anchor by choosing request headers.
- Source bundle metadata remains provenance, not authority.
- Missing or ambiguous trust policy fails closed before bundle admission.
- Explicit trust arguments remain only on the direct service seam for
  in-process fixtures; HTTP and the production binary use server-owned policy.

## Work Items

- [x] Trace the HTTP/service trust-key flow and choose the smallest compatible
  server-owned policy boundary.
- [x] Resolve trust from server-owned policy, reject caller-selected HTTP keys,
  and wire the production binary to paired environment configuration.
- [x] Remove CLI trust-anchor requirements for remote import/admission while
  retaining a documented compatibility option that is never transmitted.
- [x] Add negative tests for fresh/unregistered key headers, missing/ambiguous
  policy, and positive tests for the configured trust path and config parser.
- [x] Review and run affected public validation.

## Validation

Completed:

- `dart test test/config_test.dart test/release_bundle_test.dart` from
  `packages/control_plane`: passed.
- `dart analyze lib bin test/config_test.dart test/release_bundle_test.dart`
  from `packages/control_plane`: passed.
- `dart analyze lib/src/cli_runner.dart test/bundle_command_test.dart` from
  `cli`: passed.
- The CLI bundle contract test passed through the existing `package:test`
  runner with the arm64 Dart 3.13.1 SDK.
- Scoped Dart formatting and `git diff --check`: passed.
- `scripts/check-oss-boundary.sh`: was blocked at the time by a pre-existing
  concurrent untracked hosted deployment recipe; no hosted deployment file
  was changed for Task 293.

## Next Action

No further implementation action; review the scoped diff and retain the
server-owned environment variables during deployment.

## Blockers

No implementation blocker. The repository OSS-boundary scan was independently
blocked by a concurrent untracked hosted deployment recipe; that historical
condition is now resolved.

## Outcome

HTTP bundle import/admission now resolves exactly one server-owned Ed25519
trust anchor. Missing or ambiguous policy returns a fail-closed 503, request
trust headers are ignored, and direct service fixtures can still inject an
explicit anchor. The production binary reads the paired
`HYFENS_BUNDLE_TRUST_KEY_ID` and `HYFENS_BUNDLE_TRUST_PUBLIC_KEY` variables;
the CLI no longer requires or sends a caller-selected anchor.

## References

- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/lib/src/service.dart`
- `packages/control_plane/lib/src/release_bundle.dart`
- `packages/control_plane/lib/src/config.dart`
- `packages/control_plane/bin/control_plane.dart`
- `cli/lib/src/cli_runner.dart`
- `docs/architecture/control-plane.md`
- `docs/cli.md`
- `README.md`
- Carver/Helmholtz security review, 2026-09-19

## History

- 2026-09-19: Reserved after review found that request headers currently select
  the public key used to verify imported/admitted bundles.
- 2026-09-19: Added a single-key server-owned policy, production environment
  wiring, fail-closed HTTP coverage, CLI compatibility migration, and safe
  operator documentation.
- 2026-09-19: The public image recipe was moved under the self-hosted path and
  the worktree boundary scan now passes; the earlier hosted-path scan note was
  historical only.
