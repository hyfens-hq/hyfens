# Task 300 — OSS private-path content scan

Status: [x] Completed

## Goal

Prevent private Cloud deployment path markers from appearing in public OSS
source or task documentation.

## Scope and Non-goals

Scope:

- the public OSS boundary scanner's content rules; and
- historical task notes that contain private deployment path markers.

Non-goals:

- rewriting Git history;
- deleting repository files or branches; and
- identifying or removing generic public deployment documentation.

## Owner

OSS boundary maintainer.

## Dependencies

- Task 292's worktree-aware boundary scan;
- the public repository's historical task notes; and
- the private/public source boundary decision already recorded by the
  coordinator.

## Assumptions

- private path markers are implementation evidence, not public product
  contracts;
- the scanner itself may contain the detection terms but must be excluded from
  its own content scan; and
- the correction must not alter public control-plane behavior.

## Work Items

- [x] Remove existing private deployment path markers from public task notes.
- [x] Add fail-closed content scanning for private path markers and run it in
  the shared release preflight.
- [x] Run synthetic-marker, boundary, whitespace, and diff validation.

## Validation

Executed on 2026-09-19:

- existing boundary scan: passed;
- synthetic private-marker scan: correctly failed closed, then the disposable
  marker was removed;
- `git diff --check`: passed; and
- actionlint on the shared release preflight and release workflows: passed.

## Next Action

The public boundary now rejects the reviewed private path markers in content;
hand off the boundary diff for review.

## Blockers

None expected.

## Outcome

Historical internal path markers were removed from public task notes, and the
worktree-aware boundary scan now checks both paths and content before release
preflight proceeds.

## References

- `scripts/check-oss-boundary.sh`
- `tasks/292-oss-boundary-worktree-scan.md`
- Tasks 293 and 294 historical validation notes

## History

- 2026-09-19: Reserved after combined review found private hosted deployment
  path markers in two public task notes even though no private source file was
  present.
- 2026-09-19: Sanitized the notes, added the content scan, and verified both a
  clean pass and a disposable synthetic-marker failure.
- 2026-09-19: Added the boundary scan to the shared release preflight so a
  release cannot proceed with a detected public/private boundary marker.
