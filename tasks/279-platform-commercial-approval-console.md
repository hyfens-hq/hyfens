# Task 279: Platform Commercial Approval Console

Status: [x] Completed

## Goal

Expose the existing Cloud commercial catalog legal-approval workflow through
the protected Platform Console so authorized operators can resolve the public
pricing gate without terminal or direct database intervention.

## Scope and Non-goals

Scope:

- expose the existing Cloud commercial capabilities through the control-plane
  platform identity boundary;
- read the private commercial catalog from the existing Cloud API;
- add an audited, explicit legal-approval form to Plans & entitlements;
- preserve expected-etag concurrency, document references, and reviewed actor
  identity from the existing Cloud API contract;
- add focused authorization, API, and dashboard regression coverage.

Non-goals:

- no automatic legal approval or seeded approval reference;
- no pricing, tax, or legal-content decision by the implementation;
- no new commercial/catalog store or notification architecture;
- no change to Razorpay, deletion, billing state, or app.hyfens.com;
- no direct development on main.

## Owner

Codex, with maintainer/legal approval required for the final action.

## Dependencies

- Existing `apps/cloud-api` commercial catalog endpoints and audit trail.
- Existing Platform Console session and capability model.
- Existing `api.hyfens.com` edge route for `/v1/platform/commercial/*`.
- Authorized maintainer/legal reviewer and approved document references.

## Assumptions

- The current effective catalog remains fail-closed until an authorized
  reviewer submits valid terms/privacy references and an approval reference.
- A platform session bearer is valid for both the control-plane and private
  Cloud API routes after the capability catalogue is aligned.
- The dashboard's existing Plans & entitlements page is the appropriate
  operator surface.

## Work Items

- [x] Add Cloud commercial read/legal-review capability constants and role
  grants to the control-plane platform authorization catalogue.
- [x] Add dashboard API methods for the private commercial catalog and legal
  approval endpoints.
- [x] Add an explicit catalog-status and legal-approval panel to Plans &
  entitlements, including validation and no automatic submission.
- [x] Add focused tests and documentation for the operator workflow.
- [x] Run scoped validation, review the combined diff, and prepare the atomic
  pull request; merge/deploy remains separate.

## Validation

Completed:

- `dart analyze` from `packages/control_plane` — no issues;
- `dart test test/platform_commercial_capability_test.dart test/demo_seed_test.dart` — all passed;
- `node --check dashboard/app.js` — passed;
- `python3 -m unittest dashboard.test_serve` — 36 tests passed;
- `node dashboard/test_auth_flow.js` — 4 tests passed;
- `git diff --check` — passed.

## Next Action

Review and merge the pull request, then deploy the control-plane/dashboard
assets through the protected process. The final legal action remains a human
decision in the console.

## Blockers

The final catalog approval remains an authorized legal/policy action and must
not be performed automatically by this task.

## Outcome

The existing private Cloud legal-approval action is now reachable from the
protected Platform Console. Operators can inspect the catalog revision,
terms/privacy references, effective time, and review state, then submit an
explicit approval with the exact etag and document references. Placeholder
legal values are rejected in the UI. No automatic approval or pricing mutation
was added. The current effective catalog remains fail-closed until an
  authorized reviewer completes the form.

## References

- `tasks/257-public-pricing-projection.md`.
- `apps/cloud-api/lib/src/http.dart` commercial catalog routes.
- `packages/cloud-commercial/lib/src/commercial.dart` legal approval model.
- `dashboard/app.js` Platform Console.

## History

- 2026-09-13: Task reserved on `fix/platform-commercial-approval-console`.
- 2026-09-13: Added the control-plane capability bridge, private Cloud API
  client methods, Plans & entitlements governance panel, explicit legal
  approval form, cache-busting asset versions, and focused regression tests.
