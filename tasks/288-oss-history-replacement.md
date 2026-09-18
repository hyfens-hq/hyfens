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
- no assumption that rewriting only the default branch removes old public
  branches, tags, pull-request refs, or already-cloned objects.

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
- candidate root commit: `6755c3dd5d30d558d1a5fc0db7bafb43f728a0fa`;
- reachable commit count: `1`;
- candidate was built from the final cleanup source tree before this task file
  recorded its own candidate hash; no source or deployment files differ;
- current-tree boundary guard: passed;
- reachable-history private-marker scan: passed; and
- hosted-only path inventory: empty.

Recovery references before any remote operation are `origin/main` at
`c5be072ce986e4c4c6852486d35cd344ef76934a` and the cleanup tip at
`df26eda8e42b29b4e9e432a21e2036ba796b65bb`.

## Next Action

Create the isolated candidate history and report its exact ref, commit count,
scan results, and recovery procedure for maintainer review.

The remote operation must inventory every public branch and tag, freeze writes,
replace or remove old refs, and account for pull-request refs and provider-side
object retention. A new clean branch alone does not remove the old history.

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
- 2026-09-19: Merged the current `main` tip into the cleanup branch to resolve
  the review conflict while retaining the sanitized public tree; updated the
  recovery references and kept remote history unchanged.
- 2026-09-19: Rebuilt the isolated candidate after the recovery-reference
  documentation update; candidate root is `6755c3dd5d30d558d1a5fc0db7bafb43f728a0fa`
  and matches the final cleanup tree.
