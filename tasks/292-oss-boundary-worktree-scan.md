# Task 292: OSS publication boundary scan

Status: [x] Completed

## Goal

Ensure the public repository's boundary check covers the complete publishable
worktree, including untracked non-ignored files, so private deployment markers
cannot be introduced unnoticed before review or release.

## Scope and Non-goals

Scope is the public boundary-check script, its provider/host marker scan, and
the task record describing the validation.

Non-goals are private service changes, history rewriting, repository hosting
administration, and secret rotation.

## Owner

Security coordinator.

## Dependencies

- `rg` is available in the contributor/release environment.
- Git ignore rules continue to exclude generated and local-only artifacts.

## Assumptions

- Files that are non-ignored and visible in the worktree can be included in a
  review or accidentally copied into a public snapshot.
- Generated dependency/build directories are excluded to keep the check focused
  on source and documentation that can enter the repository.

## Work Items

- [x] Replace the tracked-only marker search with a worktree-aware scan.
- [x] Remove private provider names from the public task record.
- [x] Run the boundary check against clean and synthetic violating inputs.
- [x] Review the combined diff and record validation.

## Validation

Executed:

- `scripts/check-oss-boundary.sh` passes on the current worktree.
- A temporary non-ignored file containing a forbidden marker causes failure;
  the temporary file is removed after the check.
- `git diff --check` and targeted public source search pass.

The first implementation exposed and fixed a fail-open command-line flag bug in
the new `rg` invocation; the clean and synthetic checks were rerun afterward.

## Next Action

Hand off the worktree-aware boundary check with the release and review gates
recorded in Tasks 289 and 290.

## Blockers

None known.

## Outcome

The public boundary check now inspects non-ignored tracked and untracked
worktree content for private provider/host markers while excluding generated
dependency/build output. It fails on a synthetic untracked marker.

## References

- `scripts/check-oss-boundary.sh`
- `SECURITY.md`
- Task 289 CLI/MCP security hardening

## History

- 2026-09-19: Reserved task 292 after review found that the boundary marker
  search only inspected Git-tracked content while security task records were
  still untracked in the worktree.
- 2026-09-19: Replaced the tracked-only provider scan with a worktree-aware
  `rg` scan, sanitized the public task record, and verified clean/failing
  synthetic cases. Corrected `rg`'s pattern flag after the first validation
  exposed a fail-open invocation.
- 2026-09-19: Task 300 extended the same worktree boundary to reject private
  repository/deployment path markers in public content.
