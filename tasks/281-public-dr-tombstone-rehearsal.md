# Task 281: Disposable deletion-tombstone recovery rehearsal

Status: [x] Completed — disposable coupled restore and tombstone replay passed; managed/provider acceptance remains external

## Goal

Add a disposable, repeatable rehearsal that proves the public control-plane database/object backup can be restored and that a pre-deletion snapshot can be replayed through the deletion worker with the expected tombstone, access rejection, credential removal, and shared-object safety.

## Scope and Non-goals

Scope:

- Build on the existing local P2 DR rehearsal and its isolated Docker compose project.
- Capture a pre-deletion coupled PostgreSQL/object snapshot, restore it into disposable volumes, and exercise the real HTTP deletion flow and worker.
- Assert the terminal tombstone and the security/data-integrity invariants with sanitized evidence.

Non-goals:

- Running against production, customer data, or live provider credentials.
- Proving Cloudflare/provider durability, cross-region failover, approved RPO/RTO, or legal compliance.
- Changing the production deletion policy or retention duration.

## Owner

Public control-plane engineering

## Dependencies

- Docker, the existing P2 compose stack, and the local-only deletion test clock/provider mode; the control-plane image supplies the Dart runtime for fixture generation.
- Existing control-plane deletion and object-store behavior.

## Assumptions

- The rehearsal is opt-in and requires its existing restore safety flag.
- Test credentials are generated within the disposable run and are never printed.
- Existing shared-object and deletion unit tests remain the lower-level regression guard.

## Work Items

- [x] Map the existing bootstrap/login/deletion APIs and safe test fixtures.
- [x] Add the opt-in disposable coupled snapshot/restore and tombstone replay flow.
- [x] Assert the post-replay tombstone, denied access, absent tenant records and memberships, and preserved shared bytes.
- [x] Add focused validation and operator evidence instructions.

## Validation

Completed: `bash -n scripts/p2-dr-rehearsal.sh`; Compose configuration validation with synthetic local values; focused `deletion_test.dart` and `human_auth_http_test.dart` validation (18 passed); and one full disposable rehearsal with the explicit restore flag. The final run emitted `deletion_tombstone_replay=PASS`, `dr_rehearsal=PASS`, matching source/restored/shared artifact digests, `deleted_tenant_records=0`, and `deleted_customer_memberships=0`. The exact tombstone project, containers, volumes, and network were removed by the cleanup trap. A broader existing control-plane package run was attempted and reported 27 unrelated failures in credential-scope/reconciliation timing tests; no Dart source is changed by this task, so those remain follow-up/pre-existing failures.

## Next Action

Review and merge the PR, then run the same opt-in flow against the approved managed coupled backup destination; do not record local directional evidence as provider durability or RPO/RTO evidence.

## Blockers

The managed/provider-backed coupled recovery exercise remains an external launch gate after this local rehearsal passes.

## Outcome

Implemented on the existing P2 rehearsal path. The final disposable run restored the coupled database/object snapshot, completed the real deletion worker, retained the organization tombstone, denied deleted-tenant access, removed tenant records/memberships, and preserved the shared content-addressed artifact. Provider-backed recovery, approved RPO/RTO, and legal acceptance remain open.

## References

- `scripts/p2-dr-rehearsal.sh`
- `deploy/p2/docker-compose.yml`
- `packages/control_plane/test/deletion_test.dart`
- `tasks/280-cloud-launch-blocker-closure.md`

## History

- 2026-09-17: Reserved task 281 for the disposable public control-plane deletion/tombstone recovery rehearsal.
- 2026-09-17: Added the guarded `HYFENS_DR_TOMBSTONE_REHEARSAL=1` flow, explicit local Cloud/test-clock Compose settings, generated fixture credentials, shared-object reference, post-restore deletion assertions, and operator instructions. Host Dart execution was replaced with the pinned control-plane image's Dart runtime so the rehearsal does not depend on the host SDK wrapper.
- 2026-09-17: Final disposable run passed after accepting the product's existing 403 authorization denial alongside 401/404/410 resource-denial outcomes. No production or provider credentials were used; cleanup removed the exact disposable project resources.
