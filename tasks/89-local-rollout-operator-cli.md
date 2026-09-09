# Task 89 — local rollout operator CLI boundary

Status: [x] Completed — local operator boundary validated and strictly accepted

## Goal

Expose the existing Hyfens rollout state machine through a small authenticated
HTTP and CLI boundary so local operators can create, inspect, and explicitly
transition a staged rollout against the existing Dockerized control plane.
This is the smallest local operator slice relevant to Shorebird's documented
track/promotion workflow; it does not claim Shorebird runtime parity.

## Scope and Non-goals

Scope:

- add the missing control-plane routes for rollout create, read, and explicit
  state transition using the existing `ControlPlaneService` methods and
  `RolloutSpec`/`RolloutAction` models;
- add `tool rollout create`, `tool rollout inspect`, and
  `tool rollout transition` commands that call those routes with bearer-token,
  tenant-scope, idempotency, expected-revision, and optional private-CA
  handling consistent with the existing deploy command;
- add focused tests for the changed HTTP and CLI behavior only; and
- record one local Docker Compose evidence run showing create, inspect, a
  staged transition, and rejection of a stale expected revision.

Non-goals: changing rollout states, cohort hashing, eligibility, service
authorization, runtime trust, Patch Format v1, artifact bytes, release or
environment promotion behavior, health ingestion, scheduled evaluation,
automatic halt, dashboard, percentage expansion policy, public/hosted service,
AWS/provider/account work, production/store/legal claims, durable MinIO
support, new dependencies, or broad CLI refactoring.

## Owner

GPT-5.6 Luna Max implementation worker owns the disjoint code/test package;
the coordinator owns task integration, local Docker evidence, and strict
review. No commit is authorized.

## Dependencies

- Existing P3A rollout domain and service in `packages/control_plane`.
- Existing control-plane HTTP authentication, idempotency, and JSON patterns.
- Existing CLI `deploy` HTTP helper and TLS-CA handling.
- Existing local Compose stack in `deploy/p2/docker-compose.yml`.
- Existing P2 hosted-like and Task 87 local object-store evidence.

## Assumptions

- The user’s `proceed` authorizes this smallest previously identified local
  operator-surface scope; it does not authorize unrelated P3 or provider work.
- Existing service methods remain the only rollout mutation and authorization
  authority; HTTP and CLI layers only validate transport input and delegate.
- The rollout API uses explicit organization scope, idempotency keys, and
  expected current revision; no last-write-wins or implicit percentage policy
  is introduced.
- Local Docker is sufficient to validate transport, persistence, and state
  transition behavior; this is not cloud availability or runtime evidence.

## Work Items

- [x] Reserve Task 89 with a disjoint source/test/documentation boundary.
- [x] Add the minimal rollout HTTP routes without changing domain/service rules.
- [x] Add the minimal `tool rollout` create/inspect/transition commands.
- [x] Add focused tests for the changed HTTP and CLI files only.
- [x] Run scoped formatting and analysis for the changed Dart packages.
- [x] Run the changed-scope tests and a local Docker Compose end-to-end check.
- [x] Review the combined diff for authorization, idempotency, stale-revision,
  secret-handling, and unsupported-parity claims; fix blocking findings.
- [x] Record validation, strict reviewer feedback, outcome, and next instruction.

## Validation

Planned validation scope:

- `dart format` on changed Dart files;
- `dart analyze` for `packages/control_plane` and `cli`;
- only the new/changed focused HTTP and CLI test files, per the user’s
  changed-file test rule; and
- local `docker compose` using `deploy/p2/docker-compose.yml` to exercise the
  new CLI/API against PostgreSQL and the existing S3-compatible object-store
  container. No AWS or hosted account is used.

The final record must include exact commands, HTTP statuses/results, the
stale-revision rejection, and cleanup outcome. No full repository test suite
is planned unless a changed dependency or review finding requires it.

Observed validation:

- `dart format cli/lib/src/cli_runner.dart cli/test/rollout_command_test.dart packages/control_plane/lib/src/http.dart packages/control_plane/test/rollout_http_test.dart` exited 0 with no formatting changes.
- `dart analyze cli` and `dart analyze packages/control_plane` each exited 0 with no issues.
- `dart test test/rollout_command_test.dart` from `cli/` exited 0 with 2
  tests passed; `dart test test/rollout_http_test.dart` from
  `packages/control_plane/` exited 0 with 2 tests passed.
- The isolated Compose project `hyfens-task89-rollout-cli` built and ran the
  existing PostgreSQL, S3-compatible object store, and control plane. The
  local CLI deployment returned `DEPLOYED`; rollout create/inspect returned
  `DRAFT` revision 1; `ready` returned `READY` revision 2; final inspect
  matched; stale expected revision returned `PRECONDITION_FAILED` with CLI
  exit 65; `/healthz` and `/readyz` returned HTTP 200; and the project
  containers, volumes, and network were removed with `down -v
  --remove-orphans`. Full non-secret details are in the linked evidence
  record.

## Next Action

Task 89 is complete. The next bounded instruction from the strict reviewer is
to rerun only the existing changed-file tests and local Compose flow; do not
expand into AWS, provider, runtime/compiler, or MinIO work.

## Blockers

None at reservation time. If the existing service/API contract cannot support
the bounded routes without changing authority or rollout semantics, stop and
record the exact blocker rather than widening the task.

## Outcome

Completed. The existing rollout service is now reachable through authenticated
HTTP create/read/action routes and the three-command local CLI boundary. The
changed HTTP and CLI tests passed, the local Compose flow passed deploy,
rollout create/inspect, READY transition, stale-revision rejection, readiness,
and cleanup, and the independent strict reviewer returned `ACCEPT` with no
findings or required fixes. This remains a local operator boundary only; it
does not claim Shorebird runtime/compiler parity, AWS/provider capability,
hosted-service behavior, or durable MinIO support.

## References

- `docs/research/evidence/task88-shorebird-local-parity/README.md`;
- `docs/P3_ROLLOUT_OBSERVABILITY_DESIGN.md`;
- `packages/control_plane/lib/src/rollout.dart`;
- `packages/control_plane/lib/src/service.dart`;
- `packages/control_plane/lib/src/http.dart`;
- `cli/lib/src/cli_runner.dart`;
- `deploy/p2/docker-compose.yml`;
- `docs/research/evidence/p2-hosted-like-2026-08-23.md`;
- `docs/research/evidence/task87-control-plane-object-store/README.md`.

## History

- 2026-08-28 — Reserved Task 89 after the user said `proceed` following the
  Shorebird parity STOP. The selected scope is the missing local operator CLI
  and HTTP boundary over the already implemented rollout service. No rollout
  semantics, runtime, provider, AWS, or durable MinIO work is authorized.
- 2026-08-28 — Implemented the bounded HTTP and CLI boundary and added only
  focused HTTP/CLI tests. Combined self-review corrected the CLI fixture to
  use the existing internal-cohort contract: zero percentage basis points and
  64-character installation hashes.
- 2026-08-28 — Scoped formatting and analysis passed; the focused HTTP test
  passed 2 tests and the focused CLI test passed 2 tests. The first disposable
  Docker attempt correctly exposed `EXACT_APPLICATION_MISMATCH`; after
  matching the bootstrap application identity to the copied release metadata,
  the fresh-volume Compose run passed deploy, rollout create/inspect, READY
  transition, stale-revision rejection, readiness, and cleanup. See the
  linked evidence record for exact non-secret results.
- 2026-08-28 — Independent strict Luna Max review returned `ACCEPT` with no
  findings and no required fix. Its next instruction is to rerun only the
  existing changed-file tests and local Compose flow, without AWS, provider,
  runtime/compiler, or MinIO expansion.
- 2026-08-28 — The reviewer-instruction rerun completed: the validation-only
  worker independently passed both changed-file tests (2 tests each), and the
  coordinator completed a fresh local Compose run with deploy, rollout
  create/inspect, READY transition, stale-revision rejection, and cleanup all
  passing. See the evidence record for the non-secret result fields.
