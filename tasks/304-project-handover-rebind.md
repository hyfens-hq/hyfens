# Task 304 — Project handover with recipient credentials

Status: [x] Completed

## Goal

Allow an initialized source project to bind to the recipient organization's
own Hyfens application without resetting release configuration. A transferred
store application keeps its platform application ID and receives a normal
store release with the recipient's runtime delivery configuration.

## Scope and Non-goals

Scope: an explicit `init --rebind` path, dry-run support, exact application
identity guards, a bounded handover guide, and focused regression evidence.

Non-goals: transferring existing Hyfens tenant ownership or release history,
account provisioning/invitations, automatic credential or signing-key transfer,
OTA-only migration of already installed binaries, Cloud UI/API changes, and
Play Console automation.

## Owner

Hyfens CLI maintainer (single workstream).

## Dependencies

- Existing named profiles, project binding, release/patch/deploy commands.
- Recipient organization/application/environment and server-granted access.
- Existing runtime delivery build defines and normal store release process.

## Assumptions

- The recipient uses its own Hyfens application and credentials, as described
  in the request; the transferred store application ID stays the same.
- Local binding metadata selects resources and never grants server access.
- Store delivery configuration changes require a new store binary/version.

## Work Items

- [x] Add explicit rebind of initialized project metadata, preserving
  `tool.yaml`, local artifact state, signing material, and platform identity.
- [x] Document the recipient profile, runtime configuration, store release,
  and subsequent patch/deploy sequence.
- [x] Add focused regression checks for preservation, dry-run/refusal cases,
  and deployment/delivery under recipient credentials with tenant isolation.
- [x] Review the cohesive diff and run the scoped validation below.

## Validation

Validated on 2026-10-17 using Dart 3.13.4:

- `dart format cli/lib/src/cli_runner.dart cli/test/project_handover_test.dart`
  from the repository root: passed; final pass changed no formatting.
- `dart analyze lib/src/cli_runner.dart test/project_handover_test.dart`
  from `cli/`: passed with no issues.
- `dart test test/project_handover_test.dart test/profile_cli_test.dart test/configuration_test.dart`
  from `cli/`: all 13 tests passed.
- `git diff --check`: passed.
- Cohesive source/documentation/test review: only the rebind command path,
  its guide, regression checks, and this task are changed. Normal initialization
  and force behavior retain their existing paths.

The integration check uses disposable local server/project state and
metadata-only baselines. It registers/deploys an original release, keeps the
same Android application ID under a separately provisioned recipient tenant,
rebinds without changing other project files, increments the store version,
creates/deploys the recipient baseline and patch, fetches the exact signed
bytes with recipient delivery credentials, and rejects original-tenant control
and delivery credentials against recipient resources.

Initial validation exposed two incorrect assumptions about existing API
contracts: required diagnostic detail fields and the artifact payload wrapper.
Checked those declarations, corrected both call sites/assertions, and completed
the final scoped pass above. Native store builds, actual store publication,
interactive login, and external account provisioning were not exercised;
these are operator/environment steps outside this source change.

## Next Action

Review branch `feat/project-handover-rebind`. For an actual handover, follow
the CLI guide with provisioned recipient resources and publish the normal
store release with recipient runtime settings.

## Blockers

None.

## Outcome

Implemented `hyfens init --rebind` with dry-run and exact application identity
protection. Only `hyfens.yaml` is replaced; existing tool configuration,
artifacts, signing material, and platform identity remain intact. Incomplete
destination profiles, uninitialized projects, malformed configuration, and
combining rebind with force are refused before project writes. The guide
records the recipient profile/runtime setup and normal store release boundary.

## References

- `cli/lib/src/cli_runner.dart` — initialization and deployment.
- `cli/lib/src/configuration.dart` — safe committed binding.
- `docs/cli.md` — public workflow.

## History

- 2026-10-17: Inspected both clean repositories on `main`; scoped work to
  the public CLI and created `feat/project-handover-rebind` before editing.
- 2026-10-17: Confirmed that force initialization resets `tool.yaml`, while
  deployment uses the selected endpoint-bound profile and server authorization.
- 2026-10-17: Implemented the bounded rebind path and handover guide; reviewed
  the combined scope and passed the 13 focused tests, static analysis,
  formatting, and whitespace validation. No commit, push, or publication.
