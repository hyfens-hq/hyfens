# Task 92 — local coupled backup/restore rehearsal

Status: [x] Completed — local rehearsal, strict review, docs validation, and exact cleanup passed

## Goal

Run the repository's existing coupled PostgreSQL/object-store disaster-recovery
rehearsal locally and record only directly observed, non-secret recovery
evidence. Confirm that a quiesced artifact survives the disposable backup,
restore, reconciliation, and runtime-fetch path with matching bytes and digest.

## Scope and Non-goals

Scope:

- use the existing `scripts/p2-dr-rehearsal.sh` without modifying it;
- preflight a fresh disposable Compose project and free loopback ports;
- run the script with `HYFENS_ALLOW_RESTORE=1` and task-local credentials so its
  own uniquely named PostgreSQL/object-store volumes can be destroyed and
  restored;
- capture sanitized observed output for PASS status, source/restored artifact
  digests, backup-manifest digest, reconciliation/audit results, timing output,
  and exact project-scoped cleanup; and
- write the durable evidence record at
  `docs/research/evidence/task92-local-backup-restore/README.md`.

Non-goals: source, test, dependency, lockfile, schema, migration, Compose, or
script changes; cloud/AWS/provider/account/server deployment; Hetzner or other
hosting claims; provider backup durability, automated failover, approved RPO/RTO,
production/HA/store/legal claims; durable MinIO adoption or replacement
selection; Shorebird runtime/compiler parity; global Docker cleanup; secrets,
tokens, private keys, raw backup contents, or fabricated recovery results.

## Owner

GPT-5.6 Luna Max fast-mode local-Docker evidence worker owns the disposable
rehearsal and task-owned README. The coordinator owns task integration, strict
fact-based review, cleanup verification, and closure. No commit is authorized.

## Dependencies

- Task 91 is accepted with two independent final-reviewer ACCEPT verdicts.
- Docker Compose, `curl`, `python3`, `dart`, and `shasum` are available locally.
- `scripts/p2-dr-rehearsal.sh`, its PostgreSQL/object-store backup and restore
  helpers, `deploy/p2/docker-compose.yml`, and the local fixture generator are
  present and usable without cloud credentials.
- The task-owned evidence directory is not shared with another active package.

## Assumptions

- A fresh unique Compose project name and free loopback ports will be
  preflighted before startup; only resources carrying that exact project label
  may be removed.
- `HYFENS_ALLOW_RESTORE=1` is used only for this disposable rehearsal, as
  required by the existing restore script; no unrelated local data is a target.
- Credentials are generated or supplied through task-local environment
  variables and are omitted from output and the evidence record.
- The rehearsal's quiesced no-data-loss result is directional local evidence,
  not a provider-level durability or RPO/RTO claim.
- No code test is required because no source file is intended to change; no
  unrelated-file tests are run.

## Work Items

- [x] Reserve Task 92 serially after both Task 91 final reviewers returned
  ACCEPT and supplied the same local backup/restore instruction.
- [x] Preflight the exact disposable project and free loopback ports.
- [x] Run the existing coupled backup/restore rehearsal with the explicit
  restore guard and capture sanitized output.
- [x] Verify exact project-scoped Docker cleanup and absence of leftover
  containers, volumes, and networks.
- [x] Write the task-owned evidence README with FACT/INFERENCE/UNKNOWN labels
  where needed and no secrets or unsupported claims.
- [x] Strictly review the README and recorded results against the script,
  Compose contract, command output, and cleanup checks; fix only blocking
  factual findings within scope. Poincare and Carver both returned ACCEPT after
  the stale project-reference correction.
- [x] Record validation, outcome, and the next bounded instruction.

## Validation

Observed validation:

- read-only inspection of the existing rehearsal, backup/restore helpers,
  Compose port bindings, and task-owned paths;
- exact-project/port preflight for project `hyfens-task92-dr-coord-20260828`
  and ports `18693`, `55693`, and `59693`;
- one direct local execution of the unchanged rehearsal with
  `HYFENS_ALLOW_RESTORE=1`, which returned exit code 0 and emitted
  `dr_rehearsal=PASS`, source/restored digest
  `sha256:2aaba1e9f807edb65a59c62f834a0d040c60ffc5ad557232a08f0ef45f4ac1d6`,
  combined backup/manifest digest
  `729794d60048bcb2cbee808ba26a63e8e5f813d785fd35a291b82abe1c0c33c2`,
  `data_loss_observed=none_in_quiesced_rehearsal`, and timing output;
- successful HTTP 200 health/readiness, reconciliation, audit, and artifact
  fetch assertions, including `deliverable=True` and `verification.valid=True`;
- exact label-scoped checks after the script's cleanup for no remaining
  containers, volumes, or networks; and
- Markdown/path/secret-scan consistency checks for the task-owned evidence and
  task record.

No Dart analyzer, unit test, unrelated-file test, source build outside the
existing rehearsal, cloud/provider validation, or full repository suite is
planned because this package makes no source or test changes.

## Next Action

Task 92 is complete. Both final reviewers accepted the corrected evidence with
no findings. Their next bounded instruction is a fresh disposable local rerun
with new project/ports and the same evidence boundary if reproducibility work
continues. Reserve the next task only for that local rerun; do not modify
source, tests, dependencies, Compose, or the rehearsal script.

## Blockers

None known at reservation time. If Docker, a required local command, or the
existing script prevents the run, record the exact observed blocker and clean
only the task's resources; do not broaden the task or invent a result.

## Outcome

Completed. The unchanged `scripts/p2-dr-rehearsal.sh` ran locally from the
repository root with project `hyfens-task92-dr-coord-20260828`, control,
PostgreSQL, and object-store ports `18693`, `55693`, and `59693`, and
`HYFENS_ALLOW_RESTORE=1`. It returned exit code 0 and `dr_rehearsal=PASS`.
The source and restored artifact digests matched at
`sha256:2aaba1e9f807edb65a59c62f834a0d040c60ffc5ad557232a08f0ef45f4ac1d6`;
the emitted combined backup/manifest digest was
`729794d60048bcb2cbee808ba26a63e8e5f813d785fd35a291b82abe1c0c33c2`.
Health/readiness, reconciliation, audit, and runtime-fetch assertions passed;
exact project-scoped cleanup found zero containers, volumes, and networks and
all selected ports were free. Only the task record and evidence README changed;
no source, test, dependency, Compose, or script changes were made. Poincare and
Carver independently returned ACCEPT after the documentation correction.
The next instruction is a fresh local rerun with new project/ports only if
continued reproducibility evidence is required.

## References

- `scripts/p2-dr-rehearsal.sh`;
- `scripts/p2-postgres-backup.sh`;
- `scripts/p2-postgres-restore.sh`;
- `scripts/p2-object-backup.sh`;
- `scripts/p2-object-restore.sh`;
- `deploy/p2/docker-compose.yml`;
- `deploy/p2/README.md`;
- `tasks/91-local-bundle-recovery-evidence.md`.

## History

- 2026-08-28 — Reserved Task 92 after Linnaeus and Raman independently
  accepted Task 91 and supplied the same smallest next instruction: run the
  existing local `scripts/p2-dr-rehearsal.sh` with a fresh disposable Docker
  project, record observed backup/restore evidence, and make no source or
  provider changes. AWS, hosted providers, production durability, RPO/RTO,
  Shorebird, and durable-MinIO claims remain excluded.
- 2026-08-28 — The initial Sagan assignment remained non-responsive through
  repeated status checks and did not return a completion report. A replacement
  Franklin assignment was also stopped after it returned no usable report. The
  coordinator did not accept either unreturned result as evidence and completed
  the same bounded run directly with a fresh preflighted project.
- 2026-08-28 — The coordinator ran the unchanged rehearsal directly from the
  repository root using project `hyfens-task92-dr-coord-20260828` with control,
  PostgreSQL, and object-store ports `18693`, `55693`, and `59693`. The run
  returned exit code 0 and passed backup, destructive disposable restore,
  reconciliation, audit, fetch, and digest assertions. It emitted equal source
  and restored artifact digest
  `sha256:2aaba1e9f807edb65a59c62f834a0d040c60ffc5ad557232a08f0ef45f4ac1d6`,
  combined backup/manifest digest
  `729794d60048bcb2cbee808ba26a63e8e5f813d785fd35a291b82abe1c0c33c2`, and
  exact project cleanup passed. The README was updated to use only this direct
  proof output; strict review is pending.
- 2026-08-28 — Poincare and Carver independently found and then accepted the
  correction of three stale project-name references in the evidence README.
  Their final re-reviews returned ACCEPT with no findings and supplied the same
  bounded next instruction: if continuing, use a fresh disposable local
  project/port set for a reproducibility rerun with the same evidence boundary.
