# Task 87 — Local control-plane to object-store evidence

Status: [x] Completed — Local Compose container path accepted

## Goal

Prove the missing local container path: the Dockerized control plane writes and
reads one digest-addressed artifact through the internal `object-store` service
name. Record the result as local evidence without making a provider, production,
or MinIO-support claim.

## Scope and Non-goals

Scope is limited to the existing `deploy/p2/docker-compose.yml`, its
PostgreSQL, object-store, object-bootstrap, and control-plane services, the
existing HTTP control-plane contract, the existing fixture artifact generator
at `experiments/patch_loading/bin/ha_make_artifact.dart`, and the evidence
record at `docs/research/evidence/task87-control-plane-object-store/README.md`.

Non-goals are source changes, test changes, dependency changes, Compose changes,
AWS/provider/account/pricing work, public networking, durable MinIO adoption or
replacement selection, production/readiness claims, unrelated Docker resources,
and global Docker pruning. Do not modify completed task files. Do not run a Dart
test or test file; this task validates the container-to-container application
path with bounded HTTP requests and disposable fixture bytes.

## Owner

Coordinator-owned task record; execution delegated to a GPT-5.6 Luna Max worker
with priority service tier. Strict review remains coordinator-owned.

## Dependencies

- Local Docker, `curl`, `dart`, `python3`, and `shasum` are available.
- The existing Compose definition and control-plane image build are usable.
- The existing fixture generator can create a temporary signed artifact and
  public key without modifying tracked files.

## Assumptions

- A unique Compose project named `hyfens-task87-container-s3` and task-local
  host ports `18087`, `55487`, and `59087` are available after a read-only
  preflight.
- Placeholder credentials are supplied only to task-local processes and are
  never written to tracked files or evidence.
- Internal service traffic uses `http://object-store:9000/`; host health and
  control-plane requests use the task-local loopback control port.
- Existing application registration, patch registration, artifact upload,
  promotion, and runtime artifact fetch endpoints are the source of truth for
  this evidence run.

## Work Items

- [x] Preflight the unique Compose project and task-local ports without
  stopping or removing unrelated resources.
- [x] Start the disposable PostgreSQL/object-store/bootstrap/control-plane
  stack using the existing Compose definition.
- [x] Use the existing control-plane HTTP flow to register one temporary
  release and patch, upload one signed artifact, promote it, and fetch it back
  through the control-plane service.
- [x] Compare the fetched bytes and digest with the generated artifact, record
  health, HTTP outcomes, and scoped cleanup in the evidence README without
  recording credentials or private keys.
- [x] Strictly review the task-owned evidence, confirm no source/test/dependency
  or Compose file changed, run only Markdown/link/whitespace validation, and
  close the task if all evidence is internally consistent.

## Validation

Validation is limited to the task-owned Markdown files and the disposable
application flow: Compose config, service health/readiness, the existing
fixture generator command, bounded HTTP registration/upload/promotion/fetch,
byte/digest comparison, scoped Compose cleanup, Markdown formatting, local
relative links, trailing whitespace, secret-disclosure scan, and task-scope
inspection. The execution completed with HTTP 201 release registration, HTTP
201 patch registration, HTTP 200 artifact upload, HTTP 200 promotion, HTTP 200
artifact fetch, identical bytes and digest, healthy PostgreSQL/object-store/
control-plane services, bootstrap exit code 0, and successful exact-project
cleanup. The strict GPT-5.6 Luna Max review returned ACCEPT with no blocking
findings. Markdown, reference, whitespace, secret, and task-scope checks
passed. No Dart test, analyzer, build, AWS/provider command, credential
inspection, pricing command, public-network operation, or global Docker cleanup
was run.

## Next Action

No further action remains in this task. Any next task must have an explicit,
bounded scope; AWS/provider/production/durable-MinIO work remains deferred.

## Blockers

No blockers remain. Transient host-tooling and fixture-input failures were
resolved within the bounded run and are recorded in History.

## Outcome

The local Dockerized control-plane to internal object-store path passed. The
evidence record was written, validated, and accepted by strict review. The
checkout has no Git `HEAD` and presents repository files as untracked, so
historical diff attribution is not independently verifiable; this does not
block the local runtime evidence.

## References

- `deploy/p2/docker-compose.yml`
- `deploy/p2/Dockerfile`
- `deploy/p2/README.md`
- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/lib/src/service.dart`
- `packages/control_plane/bin/control_plane.dart`
- `experiments/patch_loading/bin/ha_make_artifact.dart`
- `scripts/p2-dr-rehearsal.sh`
- `docs/product/local-control-plane.md`
- `tasks/86-local-minio-integration-evidence.md`

## History

- 2026-08-27 — Task 87 reserved after strict review confirmed that Task 86
  covered host Dart to object-store traffic, while the Dockerized control-plane
  to internal object-store path remained unexercised. No source or test edits
  are authorized.
- 2026-08-27 — Two delegated GPT-5.6 Luna Max worker attempts did not produce
  an execution result. The coordinator then ran the same bounded scope. Two
  early attempts stopped before application writes because this host lacked
  `seq` and `sleep`; each exact task Compose project was cleaned up. A valid
  fixture attempt was first rejected with HTTP 400 `INVALID_REQUEST` for an
  invalid temporary platform ID and was cleaned up. The final run used the
  repository fixture platform ID and passed all application, byte/digest,
  health, and cleanup checks. No source, test, dependency, or Compose file
  changed.
- 2026-08-27 — Strict GPT-5.6 Luna Max review returned ACCEPT with no blocking
  findings. It verified the Compose/source wiring, recorded HTTP sequence,
  artifact digest, health, cleanup, scope boundaries, and secret redaction.
  It noted only that the checkout has no Git `HEAD`, so historical diff
  attribution cannot be independently verified. Next instruction: reserve the
  next task only after an explicit bounded scope is identified, keeping AWS,
  provider, production, and durable-MinIO claims deferred.
