# Task 288 — OSS history replacement plan

Status: [*] In Progress

## Goal

Remove previously published private deployment and product markers from the
reachable history of the public repository while preserving a reviewable,
usable OSS snapshot and protecting downstream clones from an uncoordinated
history change.

## Scope and Non-goals

Scope:

- prepare an isolated sanitized-history ref from the approved public snapshot;
- verify every reachable commit in that ref with the repository-boundary scans;
- preserve a recoverable pre-rewrite reference and document clone migration;
  and
- coordinate any remote replacement as an explicit maintainer operation.

Non-goals:

- no changes to the private commercial repository;
- no credential rotation without evidence of an exposed credential;
- no attempt to preserve private implementation history in a public ref; and
- no force-push to the public default branch from this worktree.

## Owner

Coordinator: Hyfens engineering.

## Dependencies

- Task 287's approved sanitized current tree;
- a maintainer decision on replacing the public ref history;
- a protected backup of the current public ref; and
- downstream contributor and release automation coordination.

## Assumptions

- the current public history contains private deployment markers even though
  the approved current tree no longer does;
- no credential-like token or private-key material was found by the initial
  history scan; and
- a fresh-root or otherwise fully sanitized history is safer than attempting
  to preserve file history that contains private product context.

## Work Items

- [x] Scan all reachable refs for private markers and credential-like material.
- [x] Build an isolated sanitized-history ref without changing the working
  branch or remote default branch.
- [x] Scan every commit reachable from the isolated ref.
- [ ] Review the rewritten tree, tags, release automation, and clone migration
  instructions.
- [ ] Obtain maintainer approval and execute any remote replacement separately.

## Validation

Planned:

- the boundary guard and tracked-tree scans pass at the rewritten tip;
- history scans pass for every commit reachable from the candidate ref;
- no private refs, tags, credentials, or provider-specific paths remain;
- the current-tree scoped validation from Task 287 remains green; and
- the original ref is recoverable before any remote mutation.

Candidate validation completed on 2026-09-19:

- isolated root ref: `chore/oss-history-sanitized`;
- candidate root commit: `70d06850e5c0603f1d52cfa9c6ecbf157a8522dc`;
- reachable commit count: `1`;
- current-tree boundary guard: passed;
- reachable-history private-marker scan: passed; and
- hosted-only path inventory: empty.

Recovery references before any remote operation are `origin/main` at
`82f92d66966d369cc27907d6d3b26abf82ca40d5` and the cleanup tip at
`af7859187c8df6ba9d4024a564168586269854a9`.

## Next Action

Create the isolated candidate history and report its exact ref, commit count,
scan results, and recovery procedure for maintainer review.

## Blockers

Remote history replacement is intentionally pending a reviewed recovery and
downstream-clone plan because it invalidates existing commit IDs and local
branches.

## Outcome

History replacement is required by the scan. The candidate is verified, but
no remote history has been rewritten.

## References

- `tasks/287-oss-source-boundary-cleanup.md`
- `scripts/check-oss-boundary.sh`
- public reachable-ref scan performed on 2026-09-19
- isolated candidate `70d06850e5c0603f1d52cfa9c6ecbf157a8522dc`

## History

- 2026-09-19: Reserved after the current-tree cleanup confirmed that a normal
  pull request cannot remove private markers already published in reachable
  history. Candidate history work is isolated from the cleanup branch.
- 2026-09-19: Built and scanned a fresh-root candidate in an isolated clone;
  remote refs remain unchanged pending maintainer recovery-plan approval.
