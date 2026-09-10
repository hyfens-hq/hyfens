# Task 93 — local backup/restore reproducibility rerun

Status: [x] Completed — fresh local rerun, strict review, docs validation, and exact cleanup passed

## Goal

Repeat the existing coupled PostgreSQL/object-store recovery rehearsal once
with a new disposable Compose project and new loopback ports. Establish that
the Task 92 evidence flow can be reproduced from a clean local target without
changing the implementation or claiming provider-level behavior.

## Scope and Non-goals

Scope:

- use `scripts/p2-dr-rehearsal.sh` unchanged;
- preflight a new unique disposable Compose project and free loopback ports,
  distinct from Task 92's project and ports;
- run the existing rehearsal with `HYFENS_ALLOW_RESTORE=1` and local-only
  credentials, allowing only its own PostgreSQL/object-store volumes to be
  destroyed and restored;
- record sanitized observed PASS status, source/restored artifact digests,
  combined backup/manifest digest, reconciliation/audit/fetch assertions,
  timing output, and exact cleanup; and
- write the durable evidence record at
  `docs/research/evidence/task93-local-backup-restore-rerun/README.md`.

Non-goals: source, test, dependency, lockfile, schema, migration, Compose, or
script changes; cloud/AWS/provider/account/server deployment; Hetzner or other
hosting claims; provider backup durability, automated failover, approved RPO/RTO,
production/HA/store/legal claims; durable MinIO adoption or replacement
selection; Shorebird runtime/compiler parity; global Docker cleanup; secrets,
tokens, private keys, raw backup contents, or fabricated results.

## Owner

GPT-5.6 Luna Max fast-mode local-Docker evidence worker owns the fresh rerun and
task-owned README. The coordinator owns task integration, strict fact-based
review, cleanup verification, and closure. No commit is authorized.

## Dependencies

- Task 92 is complete with direct local PASS evidence and two independent
  reviewer ACCEPT verdicts.
- Docker Compose, `curl`, `python3`, `dart`, and `shasum` are available locally.
- The existing rehearsal and its backup/restore helpers remain unchanged and
  usable without cloud credentials.
- The task-owned evidence directory does not overlap another active package.

## Assumptions

- The new project name and ports will be preflighted and will not reuse Task
  92's project or ports; only resources with the exact new project label may be
  removed.
- `HYFENS_ALLOW_RESTORE=1` is used only for this disposable target and does not
  authorize removal of unrelated local data.
- Credentials are supplied through task-local environment variables and never
  recorded; only non-secret identifiers and digests are retained.
- This is one quiesced local reproducibility observation, not provider-level
  durability, failover, RPO/RTO, or production evidence.
- No code test is required because no source file is intended to change; no
  unrelated-file tests are run.

## Work Items

- [x] Reserve Task 93 serially after Task 92's two reviewers supplied the same
  fresh-rerun instruction.
- [x] Preflight a new exact disposable project and free loopback ports.
- [x] Run the unchanged rehearsal once and capture sanitized output.
- [x] Verify exact project-scoped cleanup and absence of leftover containers,
  volumes, networks, and selected-port listeners.
- [x] Write the task-owned evidence README without secrets or unsupported
  claims.
- [x] Strictly review the README and result record against the unchanged
  script, Compose contract, direct output, and cleanup checks; fix only
  blocking factual findings within scope. Ampere and Maxwell both returned
  ACCEPT with no findings.
- [x] Record validation, outcome, and the next bounded instruction.

## Validation

Observed validation:

- read-only inspection of the unchanged rehearsal, helper scripts, Compose
  bindings, and task-owned paths;
- exact project/port preflight for project
  `hyfens-task93-dr-coord-20260828` and ports `18694`, `55694`, and `59694`;
- one direct local execution of the unchanged rehearsal with
  `HYFENS_ALLOW_RESTORE=1`, which returned exit code 0 and emitted
  `dr_rehearsal=PASS`, equal source/restored artifact digest
  `sha256:2aaba1e9f807edb65a59c62f834a0d040c60ffc5ad557232a08f0ef45f4ac1d6`,
  combined backup/manifest digest
  `bb7800eda8289bf739ad1fe1ba4f981c9c64177896f5781ae7e6945e97af9def`,
  `data_loss_observed=none_in_quiesced_rehearsal`, and timing output;
- successful health/readiness, reconciliation, audit, and runtime-fetch
  assertions, including `deliverable=True` and `verification.valid=True`;
- exact label-scoped cleanup checks for no containers, volumes, or networks and
  listener checks for all selected ports; and
- Markdown/path/secret-scan consistency checks for the evidence README and task
  record.

No Dart analyzer, unit test, unrelated-file test, source build outside the
existing rehearsal, cloud/provider validation, or full repository suite is
planned because this package makes no source changes.

## Next Action

Task 93 is complete. Ampere and Maxwell independently accepted the evidence
README and task record with no findings. Any further evidence must be a
separately scoped disposable local run with a fresh project and ports; no
additional rerun is part of this task.

## Blockers

None known at reservation time. If local Docker or a required command is
unavailable, stop after exact cleanup of any task-owned resources and record the
concrete blocker without widening the task.

## Outcome

Completed. The unchanged `scripts/p2-dr-rehearsal.sh` ran directly from the
repository root with fresh project `hyfens-task93-dr-coord-20260828`, control,
PostgreSQL, and object-store ports `18694`, `55694`, and `59694`, and
`HYFENS_ALLOW_RESTORE=1`. It returned exit code 0 and `dr_rehearsal=PASS`.
The source and restored artifact digests matched at
`sha256:2aaba1e9f807edb65a59c62f834a0d040c60ffc5ad557232a08f0ef45f4ac1d6`;
the emitted combined backup/manifest digest was
`bb7800eda8289bf739ad1fe1ba4f981c9c64177896f5781ae7e6945e97af9def`.
Health/readiness, reconciliation, audit, and runtime-fetch assertions passed;
exact project-scoped cleanup found zero containers, volumes, and networks and
all selected ports were free. The final docs validation passed with balanced
Markdown fences, no secret-pattern match, and matching project/digest values.
Only the task record and evidence README changed; no source, test, dependency,
Compose, or script changes were made. Ampere and Maxwell independently
returned ACCEPT with no findings.

## References

- `scripts/p2-dr-rehearsal.sh`;
- `scripts/p2-postgres-backup.sh`;
- `scripts/p2-postgres-restore.sh`;
- `scripts/p2-object-backup.sh`;
- `scripts/p2-object-restore.sh`;
- `deploy/p2/docker-compose.yml`;
- `deploy/p2/README.md`;
- `tasks/92-local-backup-restore-rehearsal.md`.

## History

- 2026-08-28 — Reserved Task 93 after Poincare and Carver independently
  accepted Task 92 and supplied the same next bounded instruction: if
  reproducibility work continues, run a fresh disposable local project with new
  ports using the same existing rehearsal and evidence boundary. AWS, providers,
  production durability, RPO/RTO, Shorebird, and durable-MinIO claims remain
  excluded.
- 2026-08-28 — The delegated Carson assignment did not return a completion
  report or produce an accepted evidence result after repeated status prompts.
  The coordinator stopped that assignment; no unreturned result will be used,
  and the coordinator is proceeding with one fresh direct run under the same
  bounded scope.
- 2026-08-28 — The coordinator preflighted fresh project
  `hyfens-task93-dr-coord-20260828` on control, PostgreSQL, and object-store
  ports `18694`, `55694`, and `59694`, then ran the unchanged rehearsal directly
  from the repository root. It returned exit code 0, passed backup, destructive
  disposable restore, reconciliation, audit, fetch, and digest assertions, and
  emitted equal source/restored digest
  `sha256:2aaba1e9f807edb65a59c62f834a0d040c60ffc5ad557232a08f0ef45f4ac1d6`
  plus combined backup/manifest digest
  `bb7800eda8289bf739ad1fe1ba4f981c9c64177896f5781ae7e6945e97af9def`.
  Exact project cleanup passed; strict review is pending.
- 2026-08-28 — Ampere and Maxwell independently reviewed the evidence README,
  task record, unchanged rehearsal, direct output, restore ordering, cleanup,
  redaction, and evidence limits. Both returned ACCEPT with no findings. They
  instructed the coordinator to close Task 93 and require a separately scoped
  fresh project/port run for any future evidence.
