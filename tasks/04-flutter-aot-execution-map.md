# Task 04 — Flutter AOT execution map

Status: [x] Completed

## Goal
Trace Dart/Flutter source through Kernel, transformations, AOT snapshots/native instructions, the Dart VM, and Flutter engine, and identify evidence-backed interception points.

## Scope and Non-goals
Scope: upstream Dart/Flutter source and official docs; language/runtime constraints listed in the Phase 0 brief. Non-goals: assuming feasibility or maintaining a fork.

## Owner
Upstream Dart/Flutter research specialist; coordinator retains task-file ownership.

## Dependencies
Task 01 evidence structure.

## Assumptions
Upstream source and tool invocations can establish the release pipeline even where prose documentation is incomplete.

## Work Items
- [x] Trace frontend, Kernel, transforms/tree shaking, `gen_snapshot`, snapshots/instructions, VM, engine, and app startup.
- [x] Evaluate analyzer/source, frontend/Kernel, AOT/VM, engine, and explicit runtime interception points.
- [x] Research dynamic invocation, interpreter availability, and the listed Dart constructs/platform boundaries.
- [x] Produce and review `docs/research/flutter-aot.md` with diagrams, citations, and unknowns.

## Validation
Completed pinned-source review across the installed Flutter 3.47/Dart 3.13 baseline and a newer upstream snapshot. All 48 external citations resolved HTTP 200; markdownlint passed with line-length disabled for pinned URLs/tables. Revision provenance was corrected and re-reviewed.

## Next Action
Use the verified pipeline and seam constraints to finish Task 05 and pin Task 06 to the installed toolchain.

## Blockers
None.

## Outcome
Mapped the release pipeline and interception points. Stock AOT rejects Kernel loading; dynamic modules/interpreter code is disabled by default; source/Kernel build-time dispatch remains experimentally plausible without an engine fork, subject to pruning, stable-ID, semantics, and performance proof.

## References
- Upstream `dart-lang/sdk` and `flutter/flutter`/engine sources and official Dart/Flutter documentation.

## History
- 2026-08-22: Task number reserved before delegation.
- 2026-08-22: Research package assigned; upstream inspection started.
- 2026-08-22: Completed after citation validation and a revision-provenance correction distinguishing installed stable from upstream research snapshots.
