# Task 91 — local signed-bundle recovery evidence

Status: [x] Completed — fresh local proof rerun, strict review, docs-only validation, and exact cleanup passed

## Goal

Produce one independent, reproducible, non-secret evidence record for the
accepted Task 90 offline signed-bundle boundary using two isolated disposable
local Compose projects. Demonstrate the recovery and rejection paths that are
material to operating the boundary without AWS access.

## Scope and Non-goals

Scope:

- use the existing `deploy/p2/docker-compose.yml` unchanged for separate
  source and destination projects with task-local ports, credentials, volumes,
  and networks;
- bootstrap matching local source/destination application identities, upload
  one verified Patch Format v1 source release, export and offline-sign one
  bundle, and verify the bundle with its externally supplied public key;
- exercise destination quarantine import, idempotent replay, a real request
  conflict where the current contract permits it, tampered-bundle rejection,
  wrong-trust-key rejection, control-plane restart, safe partial/terminal
  recovery, explicit admission, promotion, runtime fetch, and byte/digest
  comparison;
- write only the durable evidence record at
  `docs/research/evidence/task91-local-bundle-recovery/README.md`, including
  exact non-secret commands/results, state transitions, IDs/digests where safe,
  explicit FACT/INFERENCE/UNKNOWN labels when needed, and scoped cleanup; and
- independently review the evidence for factual accuracy and scope.

Non-goals: source, test, dependency, lockfile, schema, migration, Compose, or
runtime changes; AWS/provider/account/server deployment; hosted service,
production/HA/store/legal claims; durable MinIO adoption or replacement
selection; Shorebird runtime/compiler parity; private-key/token capture;
global Docker cleanup; broad test execution; or inventing a conflict/recovery
result when the local contract cannot produce one.

## Owner

GPT-5.6 Luna Max fast-mode evidence worker owns the isolated Docker run and
the task-owned README. The coordinator owns task integration, strict review,
any narrowly authorized follow-up, and cleanup verification. No commit is
authorized.

## Dependencies

- Task 90 implementation and focused validation are accepted.
- Local Docker, `curl`, `jq`, `dart`, `shasum`, and the existing fixture
  signing material are available.
- The existing local Compose control plane, PostgreSQL, and S3-compatible
  object-store fixture are usable without cloud credentials.
- The task-owned README directory does not overlap another active package.

## Assumptions

- Fresh unique Compose project names and host ports will be preflighted before
  starting; only those named resources may be removed.
- Credentials, private keys, bearer tokens, and raw signed bundle contents are
  kept out of command output, the README, and the task record.
- The source and destination use the same runtime application identity so the
  existing cross-instance identity check is exercised rather than bypassed.
- Partial/terminal states may be induced only in disposable local PostgreSQL
  rows after the valid quarantine import; any mutation must be recorded as a
  test fixture operation, not presented as an application API guarantee.
- No code test is required unless a source file changes; unchanged-file tests
  are not run.

## Work Items

- [x] Reserve Task 91 serially after the two independent Task 90 reviewers
  supplied the same local-Docker instruction.
- [x] Preflight unique project names/ports, run the two local Compose stacks,
  and capture sanitized health/readiness evidence.
- [x] Exercise signed export/verify, quarantine import, replay, conflict,
  tamper/wrong-key rejection, restart/partial recovery, admission, promotion,
  fetch, and digest equality.
- [x] Write the task-owned evidence README without secrets or unsupported
  provider/production claims.
- [x] Strictly review the README and all recorded results against command
  output and current source paths; fix factual findings within scope. Both final
  reviewers returned ACCEPT with no findings.
- [x] Verify exact-project Docker cleanup and record commands, skipped checks,
  and any evidence limitation.
- [x] Record the outcome and next bounded instruction.

## Validation

Observed validation:

- read-only preflight of task-local Compose names/ports and current source
  paths;
- existing Compose config, container health/readiness, bounded HTTP/CLI
  operations, PostgreSQL fixture-state checks, fetched-byte hashing, and
  exact-project cleanup;
- Markdown formatting, link/path checks, secret-disclosure scans, and
  consistency checks for all IDs, states, status codes, and digests in the
  task-owned README; and
- no Dart tests, analyzer, build, or unrelated-file test unless source files
  are changed by an explicitly separately reviewed fix.

The successful coordinator proof rerun used the exact fixture
`fixtures/flutter_conformance_app` and fresh projects
`hyfens-task91-proof-src-20260828` and `hyfens-task91-proof-dst-20260828` on
control-plane ports `18691` and `18692`, PostgreSQL ports `55691` and `55692`,
and S3-compatible ports `59691` and `59692`. Preflight found no project
containers and no listeners on those ports. Both stacks passed
`up -d --build --wait`; both `/healthz` and `/readyz` checks returned HTTP 200.
Source deploy returned DEPLOYED; patch and artifact records were READY.
The first export/verify produced bundle digest
`sha256:8c1c2ef6573e9fe8a8f50414525c7846afcca02f95a35a24cf3239985a5c8a30`.
The second valid export used for the idempotency conflict had digest
`sha256:bb69603b85bbd13ea6b27a4eae1c0ffe3b3c0a4e4f2ccffcd46c6728122c6675`.
The artifact digest was
`sha256:95da0e920ff2566c39b17ef728f498c53e2dea18dfab02314a173e7a9a2acd4e`.
Tamper and wrong-trust HTTP imports returned 415/BUNDLE_INVALID. The second
valid bundle with the same import idempotency key returned
409/IDEMPOTENCY_KEY_REUSED. Import returned QUARANTINED and replayed. The
destination import row was
`bnd_1ba979b2b42e1f370a175b255286851c2666bc86c4a39ac1`, with destination
release `rel_bnd_34363664846d1a2e8413e665c982e0b68a9a78b09c5ab03a208a5209`,
patch `pat_bnd_d25662322740b93adf1b061e67f0642b0fcacebe229f2c4fceb39db8`, and
artifact `art_bnd_a7675a78fd66661785049240e7b5d25bfb5e235eb9693b58d05d112d`.
Direct disposable PostgreSQL state changes and two control-plane restarts
exercised artifact-only and READY/READY terminal recovery; both restart
replays remained QUARANTINED and promotion returned 409/RELEASE_NOT_READY.
Admission returned ADMITTED, promotion returned HTTP 200 at version 1, fetch
returned HTTP 200, and the fetched digest matched the signed artifact digest.
Exact label checks after `down -v --remove-orphans` found no containers,
volumes, or networks for either project. No Dart tests or analyzer ran because
only the evidence README and Task 91 record were modified; no application or
source files were changed. The proof run did execute the CLI via `dart run` and
built the two disposable Compose images as part of the evidence flow; no
unrelated-file tests were run.

No AWS, hosted provider, public network, global Docker prune, production
readiness, or durable object-store conclusion is part of validation.

## Next Action

The coordinator completed the sequence and replaced the earlier UNKNOWN record
with directly observed results. Two independent strict reviewers, Linnaeus and
Raman, returned ACCEPT with no findings after checking the current source
contracts, recorded proof, port assignments, recovery ordering, and exact
cleanup.

## Blockers

None known at reservation time. If a required path cannot be exercised without
changing source or using unavailable cloud/provider state, record the exact
limitation and stop rather than fabricating evidence or widening the task.

## Outcome

Completed. The fresh coordinator proof rerun passed the bounded local signed-
bundle recovery flow: source deployment, signed export/verification, quarantine
import/replay/conflict, tamper and wrong-trust rejection, partial and terminal
restart recovery, admission, promotion, runtime fetch, digest equality, and
exact project-scoped Docker cleanup. The final evidence is docs-only; no source,
test, dependency, Compose, AWS, provider, or production changes were made.
The next bounded instruction from both final reviewers is to reserve Task 92
for a local run of the existing `scripts/p2-dr-rehearsal.sh`, recording only
observed backup-manifest digest, restored artifact byte/digest equality,
reconciliation/audit results, and exact cleanup.

## References

- `tasks/90-offline-signed-bundle-import.md`;
- `packages/control_plane/lib/src/release_bundle.dart`;
- `packages/control_plane/lib/src/service.dart`;
- `packages/control_plane/lib/src/http.dart`;
- `cli/lib/src/cli_runner.dart`;
- `deploy/p2/docker-compose.yml`;
- `deploy/p2/README.md`;
- `docs/research/evidence/task87-control-plane-object-store/README.md`;
- `docs/research/evidence/task89-local-rollout-cli/README.md`.

## History

- 2026-08-28 — Reserved Task 91 as the next bounded task after independent
  Archimedes and Dewey reviews both returned ACCEPT for Task 90 and requested
  the same two-project local-Docker recovery evidence pass. AWS, providers,
  runtime/compiler, Shorebird, and durable-MinIO claims remain excluded.
- 2026-08-28 — The first delegated run accurately recorded only healthy
  Compose startup and exact cleanup as PASS; a `cli/` working-directory path
  error prevented the signed-bundle sequence, so all unexecuted rows remained
  UNKNOWN. The worker was resumed with the repository-root/absolute-path
  correction; Task 91 remains in progress and no success claim is made yet.
- 2026-08-28 — A replacement worker was stopped during a fresh stack startup
  before obtaining application results; it cleaned only its exact projects.
  The first coordinator correction attempt stopped before health assertions
  because a zsh `path` loop variable shadowed `PATH`; no application result was
  used and its exact resources were cleaned. Strict review then found that the
  copied destination IDs in the next correction record did not follow the
  current deterministic-ID formula, so that record was superseded rather than
  treated as evidence.
- 2026-08-28 — The coordinator completed a fresh proof rerun from the
  repository root with an absolute Compose path using projects
  `hyfens-task91-proof-src-20260828` and `hyfens-task91-proof-dst-20260828`,
  ports `18691/18692`, `55691/55692`, and `59691/59692`. The run asserted the
  live destination IDs against the current formula, then passed signed
  export/verify, rejection, conflict, partial/terminal restart recovery,
  admission, promotion, fetch, digest, and exact cleanup assertions. The
  README and validation block now record only this proof rerun. Fresh strict
  re-review is pending.
- 2026-08-28 — Linnaeus and Raman independently reviewed the corrected README
  and task record against the current source contracts and both returned ACCEPT
  with no findings. They supplied the same next bounded instruction: reserve
  Task 92 for the existing local `scripts/p2-dr-rehearsal.sh` backup/restore
  rehearsal with a fresh disposable Docker project, recording only observed
  digests, reconciliation/audit results, and exact cleanup.
