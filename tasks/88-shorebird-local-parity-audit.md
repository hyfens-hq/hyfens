# Task 88 — Shorebird parity audit and local target selection

Status: [x] Completed — Shorebird parity boundary and local next task accepted

## Goal

Compare the current Hyfens patching and delivery surfaces with Shorebird's
current publicly documented and publicly inspectable capabilities, then select
one smallest, evidence-backed implementation outcome that can be developed and
validated locally with Docker. Do not claim parity where the evidence does not
support it.

## Scope and Non-goals

Scope includes current official Shorebird documentation and public source for
the CLI, updater, engine/framework/build tooling, the existing repository
comparison at `docs/competitors/shorebird.md`, and the local Hyfens surfaces in
`experiments/patch_loading`, `packages/control_plane`, `cli`, and `deploy/p2`.
The output is one cited research record at
`docs/research/evidence/task88-shorebird-local-parity/README.md` containing a
capability matrix, FACT/INFERENCE/UNKNOWN labels, verified local mappings, and
one proposed next implementation task with exact scope and local-Docker
validation.

Non-goals are AWS/provider/account/pricing work, hosted Shorebird access,
production or store-policy claims, durable MinIO adoption or replacement
selection, copying private/proprietary Shorebird components, broad parity
claims, source/test/dependency/Compose changes, and speculative authority or
runtime-boundary changes. Do not run the full test suite. Any implementation
selected by this audit requires its own numbered task and review.

## Owner

Coordinator-owned task record; primary-source research delegated to a
GPT-5.6 Luna Max worker with priority service tier. Strict review and any
implementation delegation remain coordinator-owned.

## Dependencies

- Access to official Shorebird documentation and public repositories.
- The current repository files and existing comparison evidence.
- Local Docker only for a bounded, read-only Compose capability check if the
  comparison needs runtime confirmation; no AWS access is required.

## Assumptions

- Shorebird claims are recorded with source URLs and access date, and public
  source revisions are pinned when practical.
- Local Hyfens behavior is mapped to source paths and existing evidence rather
  than inferred from product intent.
- A proposed next task must have a disjoint file boundary, a concrete outcome,
  and changed-scope/local-Docker validation before it is reserved.

## Work Items

- [x] Inspect the existing Shorebird comparison, numbered task ledger, and
  local patch/control-plane/container surfaces.
- [x] Gather current primary-source Shorebird facts for release/patch build
  semantics, platform execution, update protocol, signing, rollback, and
  toolchain/backend boundaries.
- [x] Map each relevant fact to verified Hyfens behavior, existing evidence,
  or an explicit UNKNOWN without inventing equivalence.
- [x] Write the cited capability matrix and local gap record at the task-owned
  research path without changing source, tests, dependencies, or Compose.
- [x] Recommend exactly one smallest local Docker-testable implementation
  task, or record STOP if no non-speculative task is justified.
- [x] Strictly review the research record, links, labels, scope, and proposed
  task; close this audit only when the next-task recommendation is accepted.

## Validation

Validation is limited to the task-owned Markdown, primary-source link/citation
checks, local path/reference checks, FACT/INFERENCE/UNKNOWN label checks,
secret/scope scans, and read-only `docker compose config` if needed to confirm
the local container boundary. The report records current official Shorebird
facts, maps them to local source/evidence, rejects unsupported full-runtime
parity, and selects one CLI-to-Compose evidence task. The strict GPT-5.6 Luna
Max review returned ACCEPT with no blocking findings; the single factual
overstatement it found was corrected before acceptance. Markdown, reference,
stale-claim, and secret checks passed. No AWS/provider command, hosted account
action, full test suite, unrelated test, code build, source edit, dependency
edit, Compose edit, or durable object-store decision was permitted.

## Next Action

Reserve only the proposed local CLI-to-Compose evidence task. Do not begin
Shorebird engine/Dart SDK fork work from this audit.

## Blockers

None known at reservation time. Missing primary-source support or an inability
to define a safe local Docker-testable outcome is a reason to record UNKNOWN or
STOP, not to fill the gap with assumptions.

## Outcome

The current primary-source comparison is written and strictly accepted. It
identifies full Shorebird runtime parity as a separate, non-localizable
toolchain problem and proposes one bounded local Docker-testable CLI delivery
evidence task.

## References

- `docs/competitors/shorebird.md`
- `experiments/patch_loading/README.md`
- `experiments/patch_loading/SPEC.md`
- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/lib/src/service.dart`
- `cli/lib/src/cli_runner.dart`
- `deploy/p2/docker-compose.yml`
- `tasks/87-local-control-plane-object-store-evidence.md`

## History

- 2026-08-27 — Task 88 reserved after the user set Shorebird as the target
  and required local Docker execution while AWS access is unavailable. The
  package is intentionally an evidence-backed parity audit before any new
  implementation task is selected.
- 2026-08-27 — The delegated Luna Max research worker verified the current
  official Shorebird documentation/public repositories and reported the
  narrow app-level interpreter versus modified engine/toolchain gap, but was
  stopped before writing the report. The coordinator completed the bounded
  cited report from those primary-source results and local source inspection.
  No source, test, dependency, or Compose file was changed; strict review is
  pending.
- 2026-08-27 — Strict GPT-5.6 Luna Max review initially rejected one row that
  overstated E1 evidence as Android/iOS. The coordinator corrected it to
  bounded Android evidence with iOS parity UNKNOWN, reran scoped checks, and
  obtained ACCEPT with no blocking findings. The accepted next instruction is
  to reserve Task 89 for local CLI-to-Compose evidence only.

## Post-completion correction

- 2026-08-27 — Repository-wide evidence reconciliation found that the
  proposed Task 89 CLI-to-Compose run duplicated the already completed
  `docs/research/evidence/p2-hosted-like-2026-08-23.md` and
  `docs/P2_MANAGED_CLOUD_REVIEW.md` evidence. The research README was corrected
  to replace that recommendation with STOP. No Task 89 was reserved; no source,
  test, dependency, or Compose file changed. This correction supersedes only
  the next-task recommendation; the accepted Shorebird parity findings remain.
- 2026-08-27 — Strict follow-up review found stale CLI-to-Compose wording in the
  report and in the completed narrative fields above. The report now labels
  derived conclusions with `INFERENCE`, states that the existing P2 hosted-like
  and Task 87 evidence already cover the local Docker boundary, and removes the
  duplicate-task recommendation. The original completed Status, Work Items, and
  History are preserved; the original Scope, Validation, Next Action, and
  Outcome wording that described a proposed CLI-to-Compose task is superseded
  by the STOP correction. No Task 89 is reserved.
- 2026-08-27 — A fresh strict GPT-5.6 Luna Max review returned ACCEPT with no
  blocking findings. It verified the STOP decision, preserved status, work-item
  checkboxes, and history, and confirmed that P2 plus Task 87 support the local
  Docker boundary. Next instruction: do not reserve Task 89; wait for explicit
  bounded local product/toolchain authorization.
