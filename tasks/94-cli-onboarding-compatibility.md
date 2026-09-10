# Task 94 — CLI onboarding and compatibility matrix

Status: [x] Completed — compatibility coverage, documentation, strict review, and focused validation passed

## Goal

Make the existing `hyfens_tool` CLI's support boundary clear and evidence
backed for new and existing Flutter projects, without creating a second CLI or
claiming unsupported Flutter/configuration compatibility.

## Scope and Non-goals

Scope:

- add focused project fixtures/tests for a fresh Flutter-shaped project and
  existing project layouts already supported by `ProjectDiscovery`;
- cover Android Groovy, Android Kotlin DSL, and iOS bundle identifier
  discovery where the repository already has parsers;
- cover absent `tool.yaml`, valid v1 configuration, malformed configuration,
  and unsupported future configuration versions;
- cover the declared Flutter/Dart toolchain status boundary;
- align `docs/cli.md` with commands registered by the current CLI and explain
  the local repository invocation and current distribution limitation; and
- record exact changed-file validation and the next bounded adoption step.

Non-goals: a new CLI implementation, arbitrary old Flutter-version support,
configuration migration for a format that does not exist in this repository,
global package publishing, dependency restructuring, physical-device testing,
AWS/provider/Hetzner deployment, dashboard work, runtime/compiler changes,
durable MinIO support, or broad repository test execution.

## Owner

GPT-5.6 Luna Max fast-mode implementation worker owns the CLI source/test and
documentation package. A separate GPT-5.6 Luna Max fast-mode reviewer owns
strict fact-based review. The coordinator owns task integration, any blocking
fixes, final scoped validation, and task closure. No commit is authorized.

## Dependencies

- Existing `cli/lib/src/project.dart`, `configuration.dart`, and
  `toolchain.dart` behavior.
- Existing CLI tests and `fixtures/flutter_toolchain_app`.
- Repository Dart SDK and current local package dependencies.

## Assumptions

- Existing-project support means a Flutter application with a valid
  `pubspec.yaml`, not every historical Flutter project or build system.
- The only supported configuration schema is v1; a future version must remain
  an explicit rejection until a real migration contract is approved.
- Only tests for changed CLI files and directly affected documentation checks
  will be run.
- Device and online-hosting validation remain separate follow-up tasks.

## Work Items

- [x] Reserve Task 94 serially after Task 93.
- [x] Add focused compatibility fixtures/tests within the existing CLI seam.
- [x] Align CLI documentation with the registered command surface and support
  limits.
- [x] Review the combined task-owned changes for factual scope, compatibility,
  secret handling, and unnecessary abstraction.
- [x] Run scoped formatting, analysis, and only changed-file tests.
- [x] Record outcome, evidence, and the next bounded instruction.

## Validation

Observed validation:

- `dart format test/onboarding_compatibility_test.dart` from `cli/` — passed;
- `dart analyze test/onboarding_compatibility_test.dart` from `cli/` — passed
  with no issues;
- `dart test test/onboarding_compatibility_test.dart` from `cli/` — passed,
  11 tests;
- `dart run bin/tool.dart --help` from `cli/` — passed and matched the
  documented top-level command surface;
- documentation compatibility scan and targeted secret scan — passed with no
  matches; and
- no physical-device, cloud, deployment, or unrelated repository tests were
  run.

## Next Action

Task 94 is complete. The next bounded instruction is the Task 95 local
read-only operator dashboard package; keep device, cloud, and deployment work
separate.

## Blockers

None known at reservation time.

## Outcome

Completed. The existing CLI now has focused evidence for fresh and existing
Flutter-shaped projects, Android Groovy/Kotlin DSL and iOS identifier
discovery, absent/valid/malformed/future `tool.yaml` cases, parse and version
classifier branches, command registration, and the local distribution
boundary. `docs/cli.md` matches the registered commands and accurately
distinguishes `tool init`, normal release-build enforcement, and the
non-compatibility `--metadata-only` path. No CLI source, dependency, device,
hosting, or deployment behavior changed.

## References

- `docs/cli.md`;
- `cli/lib/src/project.dart`;
- `cli/lib/src/configuration.dart`;
- `cli/lib/src/toolchain.dart`;
- `cli/lib/src/cli_runner.dart`;
- `cli/test/project_discovery_test.dart`;
- `cli/test/configuration_test.dart`;
- `cli/test/toolchain_test.dart`;
- `fixtures/flutter_toolchain_app`; and
- `tasks/93-local-backup-restore-reproducibility.md`.

## History

- 2026-08-28 — Reserved after the coordinator confirmed that the CLI already
  exists, supports a bounded existing-project path, and needs compatibility
  evidence and documentation rather than a replacement implementation.
- 2026-08-28 — Fermat added the focused compatibility test and aligned
  `docs/cli.md`. Plato's first strict review identified two factual blockers:
  the metadata-only release wording and the missing available-but-unparseable
  classifier branch. Fermat applied only those corrections.
- 2026-08-28 — Plato re-reviewed the corrected paths and returned ACCEPT with
  no new findings. The worker's focused formatting, analysis, 11-test run,
  command-help check, documentation scan, and secret scan passed. The
  coordinator closed Task 94.
