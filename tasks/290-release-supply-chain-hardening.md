# Task 290 — Release supply-chain hardening

Status: [x] Completed

## Goal

Harden the public release workflows so published CLI and container artifacts
have verifiable integrity and the workflow cannot silently broaden its token
permissions or ship obvious repository secrets.

## Scope and Non-goals

Scope:

- public `.github/workflows/` release workflows;
- workflow permission boundaries, dependency/action pinning where practical,
  secret scanning, artifact checksums, and release metadata; and
- focused documentation for operators verifying released artifacts.

Non-goals:

- no private Cloud code, credentials, deployment changes, or provider
  dashboard configuration;
- no history rewrite or repository deletion;
- no mandatory signing key that cannot be supplied by the repository owner; and
- no unrelated CLI/MCP credential-storage changes owned by Task 289.

## Owner

Public OSS release-maintenance worker.

## Dependencies

- existing CLI and container release workflows;
- repository security policy; and
- owner approval for any optional signing/provenance secret or GitHub setting.

## Assumptions

- releases must remain usable without a private signing key;
- workflow changes must fail closed for malformed tags or unexpected files; and
- action versions should remain reviewable and pinned where the repository
  convention permits.

## Work Items

- [x] Review the release workflows and identify concrete supply-chain gaps.
- [x] Implement the smallest safe workflow hardening without private secrets.
- [x] Add focused validation/documentation for artifact verification.
- [x] Review the combined diff and run the affected workflow/configuration
  checks.

## Validation

Executed (2026-09-19):

- `actionlint .github/workflows/release-checks.yml
  .github/workflows/release-cli.yml .github/workflows/release-images.yml` with
  checksum-verified Actionlint 1.7.12: passed. Version 1.7.7's only diagnostics
  were its stale catalog for existing runner labels; the current version
  accepts them without suppression.
- Gitleaks 8.24.3 `dir <tracked-source-snapshot> --config .gitleaks.toml
  --redact --no-banner --ignore-gitleaks-allow`: passed. Scanner download SHA256
  verified against the official release manifest. Five reviewed false positives
  are narrowly excluded: four exact Dart type matches and one deliberately
  invalid lease-token fixture, each restricted to its known file(s).
- Synthetic secret-shaped values inserted into disposable copies of both
  exception paths still fail scanning (two findings), including a value with
  an inline `gitleaks:allow` comment. No real secret values were printed.
- `FLUTTER_ROOT=/Users/princeteck/.puro/envs/stable/flutter
  /Users/princeteck/.puro/envs/stable/flutter/bin/cache/dart-sdk/bin/dart test
  test/release_packaging_test.dart` in `cli/`: 11 tests passed. Initial standalone
  Dart invocation exposed the existing Flutter SDK dependency; supplying the
  installed SDK enabled the tests without manifest/lockfile changes.
- Dart 3.13.3 `analyze` and `format --output=none --set-exit-if-changed` on
  `scripts/cli-release/{inventory,release_support}.dart` and
  `cli/test/release_packaging_test.dart`: passed.
- Actual embedded tag-validator execution: 17 cases passed, covering current
  package matching, branch rejection, canonical tags, prereleases, leading
  zeroes, empty identifiers, metadata, and Docker's tag length limit.
- YAML permission/action-pin assertions and `bash -n` for every workflow shell
  step: passed. Every remote action has a full commit pin; every checkout has
  `persist-credentials: false`; write scopes exist only in publishing jobs.
- Task-owned `git diff --check` and combined diff review: passed.

Not run: native cross-platform builds, Docker publication, live OIDC
attestations, or GitHub release creation. These require hosted runners and/or
external writes; this task does not authorize release execution. No unrelated
repository-wide test suite was needed for these bounded workflow/script edits.

Bounded plan: share tag/secret preflight between both release workflows; pin
actions and SDK; isolate CLI assembly from publishing credentials; require the
exact six archives and checksum the inventory; add keyless GitHub CLI
attestations and minimal BuildKit image provenance; document verification.
No private signing secret, private repository work, auth-storage edits, commits,
pushes, or production release runs are in scope.

## Next Action

Owner review of the uncommitted diff. Separately verify hosted native builds
before scheduling a real tagged release. Protect release tags/workflow changes
with repository rules through the owner's normal process; no GitHub settings
were changed.

## Blockers

No source blocker remains for the bounded release hardening. Hosted native
builds, image publication, OIDC attestations, and GitHub release creation
remain external acceptance checks. The checked-in container recipe and
Flutter-aware CLI build environment are now present and guarded by the release
workflows.

## Outcome

Completed the bounded public OSS hardening without stored signing secrets:

- Shared read-only release tag and redacted secret-scan gate.
- Current existing action-major versions pinned to verified upstream commits,
  the native CLI jobs pinned to Flutter 3.47.1 (bundled Dart 3.13.x), local
  validation using Dart 3.13.3, checkout credentials disabled, bounded job
  timeouts, and job-scoped write permissions.
- CLI assembly isolated from release credentials; exact six-target, nonempty,
  regular-file inventory; SHA256 coverage for archives and inventory; checksum
  verification before and after artifact transfer; keyless GitHub provenance
  before publishing; prereleases marked correctly.
- Minimal BuildKit container provenance, source revision labels, immutable
  digest references in run evidence, and pre-login recipe checks.
- Operator guidance for exact checksum selection, GitHub provenance
  verification, image digests, and hosted release acceptance.

Exact changed paths:

- `.github/workflows/release-checks.yml` (new)
- `.github/workflows/release-cli.yml`
- `.github/workflows/release-images.yml`
- `.gitleaks.toml` (new)
- `scripts/cli-release/inventory.dart`
- `scripts/cli-release/release_support.dart`
- `cli/test/release_packaging_test.dart`
- `docs/cli-distribution.md`
- `tasks/290-release-supply-chain-hardening.md`

Other workers' auth-storage, tests, task files, and CLI/MCP documentation were
preserved. No private repository, history rewrite, commit, push, PR, registry,
or production mutation was performed.

## References

- `.github/workflows/release-cli.yml`
- `.github/workflows/release-images.yml`
- `SECURITY.md`
- `docs/cli-distribution.md`
- https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations
- https://docs.docker.com/build/metadata/attestations/slsa-provenance/
- https://github.com/gitleaks/gitleaks/releases/tag/v8.24.3

## History

- 2026-09-19: Reserved Task 290 for the public release supply-chain review.
- 2026-09-19: Implemented and validated bounded source hardening; recorded
  absent container recipe and existing Flutter SDK dependency as separate
  release prerequisites. Left all work uncommitted for owner integration.
- 2026-09-19: Task 297 supplied the public control-plane recipe under the
  self-hosted boundary.
- 2026-09-19: Task 298 added the pinned Flutter-aware native CLI build
  environment; the remaining checks are hosted release acceptance only.
