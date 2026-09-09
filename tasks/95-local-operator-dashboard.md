# Task 95 — local read-only operator dashboard

Status: [x] Completed — bounded dashboard projection, local UI, strict review, and final local validation passed

## Goal

Provide the smallest locally testable operator dashboard slice for one
organization: a read-only, authenticated overview of existing control-plane
resources and their exact operational state, without making the dashboard a
runtime trust authority.

## Scope and Non-goals

Scope:

- add one narrow read-only control-plane projection/interface for an
  organization overview using existing persisted organization, application,
  environment, release, patch, artifact, rollout, and audit records where
  already available;
- add one authenticated HTTP read route with tenant scoping, bounded output,
  and redaction of credential secrets and artifact bytes;
- add a minimal static local operator UI that consumes the projection and
  clearly labels it as a local single-tenant operator surface;
- reconcile the current productization design wording so it distinguishes this
  local read-only exception from hosted or human/RBAC dashboard scope; and
- add focused tests for the changed control-plane route/projection and a
  deterministic UI/configuration smoke check if needed; and
- document local execution against the existing control-plane process and
  local Docker/Compose path, without adding online hosting.

Non-goals: human sessions, organizations/memberships/RBAC, billing, end-user
app UI, release mutation, rollout mutation, credential issuance/revocation,
private-key management, telemetry claims, scheduler/worker behavior, new
production REST surface, CORS/edge proxy policy, AWS/provider/Hetzner
deployment, physical-device testing, new persistence schema, new dependencies,
or dashboard access to runtime private data or artifact bytes.

## Owner

GPT-5.6 Luna Max fast-mode implementation worker owns the disjoint dashboard
projection, HTTP, UI, focused tests, and local-use documentation. A separate
GPT-5.6 Luna Max fast-mode reviewer owns strict fact-based review. The
coordinator owns task integration, local Docker validation, blocking fixes,
and task closure. No commit is authorized.

## Dependencies

- Existing `ControlPlaneService`, `ControlPlaneHttpServer`, `ControlPlaneStore`,
  domain records, and control-credential authorization.
- Existing local file/PostgreSQL/object-store paths and Compose documentation.
- Product boundaries in `docs/PRODUCTIZATION_DESIGN_REVIEW.md`,
  `docs/architecture/control-plane.md`, and
  `docs/architecture/domain-tenancy.md`.

## Assumptions

- The first operator is represented by an existing scoped control credential;
  this task does not pretend that machine credentials are human RBAC.
- The projection is read-only and server-side tenant scoped; the UI must not
  reimplement release, rollout, or runtime trust policy.
- Existing records are the source of truth. Missing data is shown as missing,
  not inferred as healthy, deployed, or available.
- Local Docker is sufficient for transport and persistence validation.
- Only tests for changed dashboard/control-plane files and their direct
  dependants will be run.

## Work Items

- [x] Reserve Task 95 serially after Task 94.
- [x] Implement the narrow read-only operator projection and route.
- [x] Implement the minimal local dashboard UI and usage documentation.
- [x] Add focused tests for authorization, tenant scoping, redaction, and
  stable empty/populated projections.
- [x] Apply the strict review corrections for same-origin use, loopback-only
  local serving, explicit audit metadata safety, and current documentation.
- [x] Review the combined task-owned changes for authority leakage, scope
  creep, secret exposure, and shallow/pass-through module design.
- [x] Run scoped formatting, analysis, changed-file tests, and local Docker
  validation.
- [x] Record outcome, evidence, and the next bounded instruction.

## Validation

Planned validation:

- format/analyze only changed Dart files;
- run only changed/new control-plane/dashboard tests;
- inspect the UI assets for secret-bearing storage, unsafe mutation controls,
  and unsupported claims;
- run a fresh, exact project-scoped local Docker/Compose check if the task
  changes the control-plane HTTP path; and
- do not run device, cloud, provider, or deployment validation.

## Next Action

Task 95 is complete. Before any dashboard mutation controls are considered,
approve a separate human-session, membership, RBAC, and audit contract. No
dashboard mutation controls are authorized by this task.

## Blockers

None for the bounded local scope. Physical-device, online-hosting, and
independent human-authentication validation remain intentionally deferred.

## Outcome

Completed. The implementation adds the local single-tenant read-only operator
slice. The projection
uses one small `OperatorOverviewProjection.read` interface, existing typed
records, existing control-credential authorization, a fixed maximum of 100
items per collection, deterministic newest-first ordering with ID tie-breaks,
and explicit total/truncation metadata. It reports missing or ambiguous rollout
current revisions instead of inventing health or deployment state. It returns
no credential collection, token/hash material, private keys, runtime bytes, or
mutation authority.

Changed paths:

- `packages/control_plane/lib/src/operator_overview.dart`
- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/lib/control_plane.dart`
- `packages/control_plane/test/operator_overview_test.dart`
- `dashboard/index.html`
- `dashboard/app.js`
- `dashboard/styles.css`
- `dashboard/serve.py`
- `dashboard/test_serve.py`
- `dashboard/README.md`
- `docs/product/local-control-plane.md`
- `docs/PRODUCTIZATION_DESIGN_REVIEW.md`

Validation evidence:

- `dart format --output=none --set-exit-if-changed cli/test/onboarding_compatibility_test.dart packages/control_plane/lib/src/operator_overview.dart packages/control_plane/lib/src/http.dart packages/control_plane/lib/control_plane.dart packages/control_plane/test/operator_overview_test.dart` — passed; 0 files changed.
- From `cli/`, `dart analyze test/onboarding_compatibility_test.dart` — passed; `dart test test/onboarding_compatibility_test.dart` — passed, 11 tests; and `dart run bin/tool.dart --help` — passed.
- From `packages/control_plane/`, `dart analyze lib/src/operator_overview.dart lib/src/http.dart lib/control_plane.dart test/operator_overview_test.dart` — passed; `dart test test/operator_overview_test.dart` — passed, 4 tests.
- `python3 -m unittest discover -s dashboard -p 'test_serve.py' -v` — passed, 4 tests. The initial package-form invocation `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest dashboard.test_serve` failed because `dashboard/` is not a Python package; the directory-discovery command is the corrected focused invocation.
- `node --check dashboard/app.js` — passed; static checks confirmed the client has no `localStorage`, `sessionStorage`, or direct API-origin configuration and uses the relative overview fetch. Disposable Python bytecode cache was removed.
- Fresh local Compose project `hyfens-task95-coord-20260828-2` using `deploy/p2/docker-compose.yml` built the current control-plane image, reached health, bootstrapped a local organization/control credential, and passed direct authenticated overview assertions (`readOnly=true`, `runtimeAuthority=client`, exact organization identity, one application, and no credential collection). The local dashboard proxy served the static page, proxied the authenticated overview with `readOnly=true`, and returned HTTP 401 without a bearer credential.
- Exact cleanup for that project passed: no containers, volumes, or network remained under its Compose label, and control-plane, PostgreSQL, object-store, and dashboard ports `18095`, `55695`, `59695`, and `18096` were free.
- No device, AWS, provider, online-hosting, full-repository, or unrelated-file tests were run.

## References

- `docs/PRODUCTIZATION_DESIGN_REVIEW.md`;
- `docs/architecture/control-plane.md`;
- `docs/architecture/domain-tenancy.md`;
- `docs/product/local-control-plane.md`;
- `packages/control_plane/lib/src/http.dart`;
- `packages/control_plane/lib/src/service.dart`;
- `packages/control_plane/lib/src/persistence.dart`;
- `packages/control_plane/lib/src/auth.dart`;
- `deploy/p2/docker-compose.yml`; and
- `tasks/89-local-rollout-operator-cli.md`.

## History

- 2026-08-28 — Reserved after the coordinator confirmed that no dashboard
  implementation exists and that the first useful slice is a read-only,
  single-tenant operator projection over existing control-plane records. Human
  identity, multi-tenancy, mutation controls, hosting, and runtime authority
  remain explicitly outside this task.
- 2026-08-28 — Implemented and validated the bounded projection, HTTP route,
  static page, local same-origin proxy, focused control-plane tests, and local
  Compose evidence. The formal HEAD-based diff workflow was unavailable because
  this repository has no valid Git `HEAD`; the task-owned paths were reviewed
  directly against the Task 95 requirements and repository standards. No
  independent reviewer had yet accepted the result.
- 2026-08-28 — Gauss independently reviewed the task-owned paths and returned
  NOT ACCEPTED with four concrete findings: the UI bypassed its same-origin
  proxy, proxy/API/bind inputs were not loopback constrained, audit redaction
  used a denylist rather than a safe allowlist, and current design/status
  documentation needed reconciliation. The coordinator reopened the task and
  delegated only those corrections.
- 2026-08-28 — Boyle completed the four corrections: the UI now uses the
  same-origin relative route, the local proxy accepts only literal loopback
  origins/binds, audit metadata uses a recursive explicit allowlist with unsafe
  and nested test coverage, and the productization review records the local
  exception without changing the hosted/human/RBAC boundary.
- 2026-08-28 — Gauss re-reviewed the corrected paths and returned ACCEPT with
  no blocking findings. The coordinator corrected the remaining local-control-
  plane wording, ran the consolidated changed-scope validation, completed a
  fresh Compose run under project `hyfens-task95-coord-20260828-2`, verified
  exact cleanup, and closed Task 95. The next bounded instruction is to define
  and approve human sessions, membership/RBAC, and audit before any dashboard
  write controls.
