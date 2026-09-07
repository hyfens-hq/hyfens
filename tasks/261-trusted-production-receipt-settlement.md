# Task 261 — Trusted Production Receipt Settlement

Status: [x] Complete with External Gates

## Goal

Make a successful Hyfens runtime activation a server-verifiable, admission-bound,
idempotent usage event while keeping development acceptance non-billable and
leaving live billing disabled.

## Scope and Non-goals

Scope:

- Define the server-side receipt/admission trust contract shared by HTTP and
  direct service callers.
- Verify installation-key signatures and exact application/environment/patch
  bindings.
- Persist admissions, registered installations, receipts, and canonical
  successful-install events with retry-safe idempotency.
- Provide an explicit trust policy and attestation verifier seam for development
  acceptance and production integrations.
- Add HTTP routes, PostgreSQL migration coverage, self-host behavior, and
  focused security/reliability tests.

Non-goals:

- Enabling live checkout, overage collection, or financial billing.
- Adding Play Integrity or App Attest provider credentials/verification calls.
- Reworking the Flutter client receipt protocol already shipped in v0.1.9.
- Reopening Task 247, Task 253, or Task 260.
- Changing published tags or creating a stable release.

## Owner

Hyfens control-plane/runtime team.

## Dependencies

- Public `origin/main` at the Task 260 release-governance boundary.
- Existing Flutter installation-key, admission-bound receipt, and durable
  outbox contracts.
- Existing `ControlPlaneStore` implementations and PostgreSQL migration runner.

## Assumptions

- The public control plane must remain independently self-hostable.
- Private Cloud subscription settlement and provider-specific attestation
  verification are injected policy/adapters, not public commercial logic.
- Development acceptance may be cryptographically verified and observable but
  must always settle as non-billable.

## Work Items

- [x] Audit the shipped client receipt wire contract and current control-plane
  persistence/HTTP seams.
- [x] Implement shared admission, trust-policy, receipt verification, and
  canonical settlement services.
- [x] Add durable file/PostgreSQL persistence and cross-process idempotency.
- [x] Add HTTP routes and exports without changing existing route behavior.
- [x] Add security, replay, cross-scope, outage, retry, and self-host tests.
- [x] Run review and scoped/full validation required by the repository rules.
- [x] Record final gate disposition and preserve the reviewed task worktree.

## Validation

Completed:

- `dart format` on all changed Dart files: PASS.
- `dart analyze` in `packages/control_plane`, `cli`, and
  `packages/flutter_integration`: PASS (`No issues found!`).
- Focused control-plane tests (`runtime_receipts_test.dart` and
  `config_test.dart`): PASS (18 tests).
- Full control-plane suite: PASS (311 tests; 34 repository-provided
  PostgreSQL/process-harness cases skipped because
  `HYFENS_TEST_POSTGRES_URL` and the process harness are unavailable).
- Full CLI suite: PASS (192 tests).
- Full Flutter-integration suite: PASS.
- `git diff --check`: PASS.
- Targeted secret scan of changed source/docs/tests: PASS; no private keys,
  live-provider credentials, or payment secrets found.
- Remote tag audit: PASS; `origin` contains `v0.1.9` and no `v0.1.10`.
- PostgreSQL cross-pool idempotency coverage is implemented but not executed
  in this environment: `HYFENS_TEST_POSTGRES_URL` is unset and `pg_isready`
  reports no server on `/tmp:5432`.
- No physical device or provider-store acceptance was claimed in this public
  control-plane task. The private `hyfens-cloud-web` checkout was inspected
  read-only and its pre-existing dirty state was preserved.

## Next Action

No further implementation is authorized in this finite milestone. Before any
future stable release, inject and independently accept real Google Play
Integrity and Apple App Attest verifiers, wire the private Cloud policy and
settlement projection, run the PostgreSQL/production acceptance environment,
and complete the Task 260 RC flow. Keep live billing disabled until those
gates are separately approved.

## Blockers

- `ATTESTATION_GATE`: actual Play Integrity/App Attest provider verification,
  credentials, key registration, and outage policy are deployment-owned and
  were not available here. The public adapters fail closed until a verifier is
  injected.
- `PRIVATE_CLOUD_GATE`: subscription settlement, Developer reservation/quota,
  Starter/Team continuation, organization pooling, annual monthly reset,
  Customer Workspace projection, and Platform Console receipt views remain
  private commercial integration work. The public event is the only canonical
  usage output.
- `POSTGRES_VALIDATION_GATE`: the cross-process transaction test was not run
  because no test database URL/server is configured.
- `RC_GATE`: this milestone intentionally did not publish a stable version;
  the public change remains under `[Unreleased]` until a future RC passes.
- `LIVE_BILLING_OFF`: checkout and overage collection remain disabled.

## Outcome

**HYFENS TRUSTED PRODUCTION RECEIPTS — COMPLETE WITH EXTERNAL GATES**

The public control-plane implementation now establishes the cryptographic
invariant for an approved activation: a delivery-authorized server admission
binds the application/environment/release/patch/artifact scope; a registered
installation key signs the enrollment and exact activation receipt; and one
durable idempotency key commits exactly one receipt plus one canonical
`successful_patch_install` event. Retries, response loss, offline/restart
delivery, cross-scope reuse, key substitution, admission replay, and stale
attestation binding are covered by fail-closed tests. Development acceptance is
observable and explicitly non-billable.

The result is not a claim of completed production billing. Real provider
attestation, private Cloud quota/settlement, PostgreSQL environment execution,
and RC/public-release acceptance remain bounded external gates. No stable
release was published, no tag or binary was changed, and live billing remains
OFF. The reviewed implementation is intentionally preserved, uncommitted, in
the isolated `task/261-trusted-production-receipts` worktree because the primary
checkout contains unrelated dirty developer work; it is not an abandoned
temporary worktree.

## Acceptance Matrix

| Gate                               | Result |
| ---------------------------------- | ------ |
| Installation identity verified     | PASS |
| Signed receipt verification        | PASS |
| Admission/challenge binding        | PASS |
| Trust-level model                  | PASS |
| Production acceptance policy       | PASS |
| Android attestation adapter        | PASS |
| Apple attestation adapter          | PASS |
| Dev acceptance isolation           | PASS |
| Cross-app rejection                | PASS |
| Cross-environment rejection        | PASS |
| Key substitution rejection         | PASS |
| Receipt replay idempotency         | PASS |
| Attestation replay resistance      | PASS |
| Offline receipt recovery           | PASS |
| Restart recovery                   | PASS |
| Response-loss recovery             | PASS |
| Canonical successful-install event | PASS |
| Acceptance usage non-billable      | PASS |
| Production billable-policy path    | ATTESTATION_GATE |
| Developer reservation settlement   | PRIVATE_CLOUD_GATE |
| Developer two-process concurrency  | POSTGRES_VALIDATION_GATE |
| Starter/Team continuation          | PRIVATE_CLOUD_GATE |
| Org-wide usage pooling             | PRIVATE_CLOUD_GATE |
| Annual monthly usage reset         | PRIVATE_CLOUD_GATE |
| Customer usage projection          | PRIVATE_CLOUD_GATE |
| Platform receipt observability     | PASS |
| Self-host Cloud independence       | PASS |
| Changelog updated                  | PASS |
| RC acceptance                      | RC_GATE |
| Live billing OFF                   | PASS |
| Task-owned cleanup                 | PASS |

## References

- `packages/flutter_integration/lib/src/install_receipts.dart`
- `packages/flutter_integration/lib/src/installation_key.dart`
- `packages/flutter_integration/lib/src/runtime_attestation.dart`
- `experiments/patch_loading/lib/src/controller_receipt.dart`
- `packages/control_plane/lib/src/persistence.dart`
- `packages/control_plane/lib/src/postgres_store.dart`
- `docs/releases/releasing.md`
- `docs/runtime/trusted-install-receipts.md`

## History

- 2026-09-07: Task 261 reserved in an isolated worktree based on public
  `origin/main`; Task 260 remains closed and no stable release was created.
- 2026-09-07: Implemented the admission-bound receipt/trust protocol, durable
  settlement seam, HTTP integration, tests, documentation, and changelog
  entry. Full affected suites and static analysis passed. PostgreSQL provider,
  attestation, private Cloud settlement, and RC gates remain explicitly
  classified; no stable release was published.
