# Task 90 — offline signed release-bundle import

Status: [x] Completed — implementation, strict review, focused validation, and local Docker evidence passed

## Goal

Add the smallest provider-neutral offline transport boundary for a Hyfens
release: export one already verified Patch Format v1 artifact with its release
metadata, sign and verify the canonical bundle offline, import it into a local
control plane in quarantine, and explicitly admit it before it can become
eligible for promotion. The boundary must be usable with the existing local
Docker Compose stack and must not require AWS, an account, or a durable MinIO
product commitment.

## Scope and Non-goals

Scope:

- define one versioned canonical JSON bundle envelope containing exactly one
  release, one verified patch, the content-addressed artifact bytes, source
  control-plane identifiers for provenance, and the bundle signature;
- reuse the existing Ed25519 customer signing material and Patch Format v1
  verification rules, with a distinct bundle signing domain; verification and
  import must receive an explicit operator-supplied expected public key/key ID
  and must never treat a key carried only inside the bundle as trusted;
- add authenticated control-plane export, quarantine import, and explicit
  admission operations with tenant/application/environment checks and
  idempotency; destination record IDs must be deterministic for a given
  bundle/destination so interrupted non-transactional writes can resume
  without overwriting records;
- add the matching `tool bundle export`, `tool bundle verify`,
  `tool bundle import`, and `tool bundle admit` commands, keeping bearer
  tokens in memory only;
- add focused tests for the changed bundle, HTTP, and CLI files only; and
- record a local Docker Compose source-to-bundle-to-quarantine-to-admission
  flow, including tamper rejection and a repeated-import/idempotency check.

For cross-instance transfer, the bundle's source control-plane IDs are
provenance only. The authenticated import path supplies the destination
organization/application/environment IDs; the runtime application ID,
runtime release ID, runtime patch ID, sequence, release metadata, artifact
digest, and Patch Format v1 signature remain exact and are revalidated at the
destination. The destination allocates deterministic control-plane record IDs
from the bundle digest and destination binding so interrupted writes can be
retried safely.

Non-goals: changing Patch Format v1 or runtime trust, changing release/patch
promotion semantics, moving or copying private keys, importing tokens,
importing unrelated tenant/audit data, observations, rollback-control
material, trust-root rotation, a general archive format, large/multi-artifact
bundles, cloud/AWS/provider work, production/HA/store/legal claims, durable
MinIO support, Shorebird runtime/compiler parity, new dependencies, or broad
CLI refactoring.

## Owner

GPT-5.6 Luna Max implementation worker owns the disjoint bundle domain,
service/HTTP/CLI implementation, and focused tests. The coordinator owns task
integration, local Docker evidence, combined strict review, and task closure.
No commit is authorized.

## Dependencies

- Existing `ReleaseRecord`, `PatchRecord`, `ArtifactRecord`, and Patch Format
  v1 admission checks.
- Existing Ed25519 local key store and canonical JSON helpers.
- Existing control-plane authentication, tenant scoping, storage, audit, and
  idempotency seams.
- Existing `tool deploy` endpoint/TLS/token conventions.
- Existing `deploy/p2/docker-compose.yml` local PostgreSQL and
  S3-compatible object-store fixture.

## Assumptions

- The user-authorized next recommendation is the offline signed-bundle slice;
  AWS credentials and hosted provider access remain unavailable and are not a
  prerequisite.
- A bundle is an offline transport envelope, not a replacement runtime
  format. The runtime still verifies the inner Patch Format v1 bytes.
- Export may only select a READY patch/artifact and never exposes a private
  key or bearer token. Import verifies the outer envelope and inner artifact
  before writing destination records, but leaves both patch and artifact
  non-READY until explicit admission.
- Admission must re-check the destination tenant/application/environment,
  release/patch binding, stored artifact digest, and signature before changing
  state to READY. The artifact must be made READY before the patch, and
  promotion must require both READY records plus a digest-valid stored object;
  admission must resume a safe partial state. Promotion remains a separate
  existing operation.
- Repeated requests with the same idempotency key and identical canonical
  request body replay the original result; the same key with different input
  is rejected. A conflicting runtime release/patch identity or digest is not
  silently overwritten.
- Existing HTTP size limits remain authoritative; the implementation must
  reject oversized or non-canonical bundles before persistence.
- Admission must retain enough signed payload metadata (without private keys,
  tokens, or unrelated tenant data) to revalidate the outer signature after
  import; the exact signed envelope need not be duplicated in metadata.

## Work Items

- [x] Reserve Task 90 with a disjoint bundle implementation/test boundary.
- [x] Implement the canonical signed bundle model and verification rules,
  including an explicit expected-public-key check.
- [x] Add service and authenticated HTTP export/import/admission operations.
- [x] Add the four focused CLI bundle commands using the existing key/TLS
  conventions.
- [x] Add focused tests for the changed bundle, HTTP, and CLI files only.
- [x] Run scoped formatting/analysis and changed-file tests.
- [x] Run a disposable local Docker Compose flow through export, verify,
  import/quarantine, idempotent retry, tamper rejection, admission, and
  readiness; remove only the disposable project resources.
- [x] Perform strict fact-based review of the combined task diff and fix all
  blocking findings.
- [x] Record validation evidence, reviewer feedback, outcome, and next
  instruction.

## Validation

Observed validation:

- `dart format packages/control_plane/lib/src/release_bundle.dart
  packages/control_plane/lib/src/domain.dart
  packages/control_plane/lib/src/service.dart packages/control_plane/lib/src/http.dart
  packages/control_plane/lib/control_plane.dart
  packages/control_plane/test/release_bundle_test.dart cli/lib/src/cli_runner.dart
  cli/test/bundle_command_test.dart` — passed; 8 files, 0 changes.
- `(cd packages/control_plane && dart analyze lib)` — no issues.
- `(cd cli && dart analyze lib)` — no issues.
- `(cd packages/control_plane && dart test test/release_bundle_test.dart)` — 3
  tests passed.
- `(cd cli && dart test test/bundle_command_test.dart)` — 1 test passed.
- Disposable local Compose projects `hyfens-task90-final-src` and
  `hyfens-task90-final-dst` both reached healthy control-plane, PostgreSQL,
  and S3-compatible object-store states. The source deploy reached READY.
  The bundle was exported and verified with digest
  `sha256:3b356fc413d5e7e2091b7d0b6263dff9188eb9135530995bf24952b2f6014936`
  and artifact digest
  `sha256:95da0e920ff2566c39b17ef728f498c53e2dea18dfab02314a173e7a9a2acd4e`.
  CLI wrong-key verification failed; direct HTTP tamper and wrong-key imports
  returned `415`/`BUNDLE_INVALID`. Destination import returned
  `QUARANTINED`, the repeated import replayed, and after a database state
  transition to `READY`/`READY` plus a control-plane restart, replay still
  returned `QUARANTINED` while promotion returned `409`/`RELEASE_NOT_READY`.
  Explicit admission returned `ADMITTED`; promotion returned HTTP 200 at
  environment version 1; fetched bytes returned HTTP 200 and matched the
  artifact digest. The two disposable Compose projects and the earlier
  `hyfens-task90-src` fixture were removed with `down -v --remove-orphans`.
- Read-only direct-path review was used because this worktree has no valid Git
  `HEAD` and its files are untracked; no Git diff attribution was assumed.

No full repository test suite, unrelated file test, provider test, runtime
build, or cloud validation is planned unless a task-owned failure proves the
scope insufficient.

## Next Action

Reserve Task 91 for an independent local-Docker recovery evidence pass:
two isolated disposable Compose projects through bootstrap, READY source
upload, export/sign/verify, quarantine import, replay/conflict/tamper/wrong-key
rejection, restart/partial-state recovery, admission, promotion, fetch, digest
comparison, evidence capture, and cleanup. Keep AWS, hosted providers,
runtime/compiler, Shorebird, and durable-MinIO claims out of scope.

## Blockers

None at reservation time. If the existing store or control-plane contract
cannot safely preserve quarantine, exact identity checks, and idempotency
without widening the task, stop and report the concrete blocker rather than
silently weakening those checks.

## Outcome

Implemented the provider-neutral single-artifact offline bundle boundary. The
bundle is externally trust-anchored, canonically encoded, Patch Format v1
validated, quarantined on import, and gated by explicit admission before
promotion. No AWS account or hosted provider was used, and no production
durability claim was made.

## References

- `docs/adr/0010-self-hosted-deployment.md`;
- `docs/architecture/self-hosted-operations.md`;
- `docs/research/evidence/task88-shorebird-local-parity/README.md`;
- `packages/control_plane/lib/src/domain.dart`;
- `packages/control_plane/lib/src/service.dart`;
- `packages/control_plane/lib/src/http.dart`;
- `packages/control_plane/lib/src/audit_export_signing.dart`;
- `cli/lib/src/signing.dart`;
- `cli/lib/src/cli_runner.dart`;
- `deploy/p2/docker-compose.yml`.

## History

- 2026-08-28 — Reserved Task 90 after the user authorized the next
  recommendation. The scope is one signed, single-artifact, provider-neutral
  offline bundle with quarantine and explicit admission. AWS, provider,
  runtime/compiler, Shorebird-parity, and durable-MinIO work remain excluded.
- 2026-08-28 — GPT-5.6 Luna Max implementation worker completed the bundle
  model, service/HTTP boundary, CLI commands, and focused tests in the
  task-owned files. The coordinator ran the changed-scope formatter, analyzers,
  and two focused test files successfully.
- 2026-08-28 — Strict post-fix reviewers Archimedes and Dewey both returned
  `ACCEPT`. They verified external trust anchoring, canonical envelope and
  typed-record checks, stored-signature revalidation, destination metadata
  binding, quarantine/admission/promotion state handling, and the
  QUARANTINED-import plus READY/READY recovery case. Both supplied the same
  bounded Task 91 local-Docker instruction.
- 2026-08-28 — Coordinator completed the disposable two-project Docker flow,
  including restart and terminal recovery checks, then removed only the named
  Compose projects and volumes. No AWS or hosted account was used.
