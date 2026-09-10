# Task 03 — Shorebird teardown

Status: [x] Completed

## Goal
Verify Shorebird's public release/patch execution architecture and why it maintains a Flutter distribution/toolchain.

## Scope and Non-goals
Scope: public Shorebird repositories and official documentation, with Android/iOS execution, artifacts, signing, rollback, compatibility, and version tracking. Non-goals: feature marketing or assumptions about closed components.

## Owner
Shorebird research specialist; coordinator retains task-file ownership.

## Dependencies
Task 01 evidence structure.

## Assumptions
Some implementation details may be distributed across several public repositories and docs; unverifiable internals must remain unknown.

## Work Items
- [x] Map public repositories and licenses.
- [x] Trace updater, patch generation, changed/unchanged execution, and platform-specific models.
- [x] Identify Dart, Flutter, engine, and tooling modifications with direct evidence.
- [x] Document artifacts, signing, rollback, compatibility, Flutter tracking, limitations, and unknowns.
- [x] Produce and review `docs/competitors/shorebird.md` with separated fact and inference.

## Validation
Completed pinned-source and official-documentation review. `git diff --check -- docs/competitors/shorebird.md` passed and every unique cited URL returned HTTP below 400. Private Dart/iOS internals and a production-equivalent self-hosted backend remain explicitly unverified.

## Next Action
Use the verified toolchain-fork burden and platform split in Task 05.

## Blockers
None.

## Outcome
Verified transparent ordinary-Dart patching through a coordinated modified toolchain: Android reconstructs a new native AOT artifact; iOS uses a private compiler/linker/interpreter implementation. Public updater/CLI/forks are documented, while critical iOS internals and full self-hosting are not public.

## References
- Public Shorebird GitHub repositories and official documentation, to be enumerated in the deliverable.

## History
- 2026-08-22: Task number reserved before delegation.
- 2026-08-22: Research package assigned; source inspection started.
- 2026-08-22: Completed after pinned-source review and citation/link validation.
