# P2 Managed Cloud Foundation Review

<!-- Wide evidence tables intentionally disable the line-length rule. -->
<!-- markdownlint-disable MD013 -->

Date: 2026-08-23
Status: bounded hosted-like foundation — maintainer review required
Evidence labels: `UNIT`, `INTEGRATION`, `END_TO_END_HOSTED_LIKE`,
`BACKUP_RESTORE`, `PHYSICAL IOS`, `PHYSICAL ANDROID`, `LOAD_TEST`,
`HISTORICAL ENVIRONMENT-GATED`

This review records what was actually implemented and executed. It does not
claim production readiness, beta readiness, HA, internet-scale capacity, App
Store approval, Google Play approval, or legal compliance.

## 1. Recommendation

## CONTINUE P2 MANAGED CLOUD FOUNDATION

The hosted-like foundation is technically promising and preserves the frozen
runtime trust model, but the P2 closure gates are not all closed. The
hosted-like Android and iOS device runs passed on the declared fixtures;
coupled database/object recovery, bounded private TLS/certificate rotation,
reconciliation, credential lifecycle, audit export/tamper detection, and
restart-during-mutation drills now have executed evidence. Independent
real-app validation, true power-loss, production key recovery/availability,
public-ingress hardening, performance claims, and store-policy review remain
open. Stop here for maintainer review; do not start P3 automatically.

## 2. Frozen invariants preserved

No P2 change modified Architecture B automatic source instrumentation, Patch
Format v1, capability v1, exact application/release/function/capability
binding, state-v4 trust/high-water admission, signed rollback, fail-closed
recovery, runtime signature authority, AOT fallback, customer/local private
signing-key custody, or the read-only extractable delivery-credential
boundary.

PostgreSQL, object storage, the HTTP service, Docker, and hosted metadata are
untrusted inputs to the runtime. E1 still parses, hashes, verifies,
release-binds, capability-checks, sequence-checks, health-confirms, and rolls
back Patch Format v1 bytes locally.

## 3. What works

| Area | Result | Evidence |
| --- | --- | --- |
| PostgreSQL persistence | PASS | Migration, restart, content-addressing, idempotency, audit, and immutable-race tests against PostgreSQL |
| Migrations | PASS | Version 1 transactional bootstrap, repeatable startup, concurrent-start test, shipped SQL parity test |
| Tenant isolation | PASS | Two PostgreSQL tenants; foreign audit/update access denied/not-found bounded |
| S3-compatible objects | PASS | Fake HTTP adapter and MinIO Signature V4 tests; digest verification and immutable precondition |
| Artifact failures | PASS | Wrong bytes, corruption, missing object, overwrite conflict, object outage, bounded retry/recovery |
| Authentication | PASS | Hashed control/delivery credentials, scopes, revocation, exact app/environment authorization |
| Limits | PASS | JSON/artifact limits, idle timeout, per-client rate limit, bounded configuration validation |
| API semantics | PASS | Immutable Release/Patch/artifact, idempotency, optimistic promotion, exact release binding, update decisions |
| Audit/provenance | BOUNDED PASS | Durable redacted audit records with PostgreSQL hash-link chain; not compliance-grade evidence |
| Readiness/liveness | PASS | `/healthz` liveness; `/readyz` probes migration/database and S3 bucket availability |
| Metrics | BOUNDED PASS | Process-local `/metrics` counts, status classes, update decisions, duration totals/maxima; no runtime telemetry |
| Deployment | PASS | Non-root Dart container, PostgreSQL, MinIO, Compose health dependencies, reverse-proxy example |
| Backup/restore | BOUNDED PASS | Coupled PostgreSQL dump plus object manifest restored identities, promotion, release/patch metadata, idempotency, audit, exact patch bytes, and digest; not an RPO/RTO or HA claim |
| Hosted-like CLI flow | PASS | `tool release → tool patch → tool verify → tool deploy → lookup/fetch` against Compose |
| Physical iOS hosted-like flow | PASS | One installed IPA: base 540, hosted patch 450, restart retained 450 |
| Physical Android hosted-like flow | PASS | One installed arm64 Release APK: base 540, hosted patch 450, restart and control-plane outage retained 450; package install timestamps unchanged |
| Physical Android cross-feature flow | PASS | Business, async, UI, Riverpod, invalid-signature, rollback, stale/replay rejection, restart persistence |
| Private TLS and certificate rotation | BOUNDED PASS | Nginx proxy, valid private CA/leaf, CLI CA trust, old-CA rejection, new-CA deployment, lookup/fetch after rotation |
| Credential lifecycle | BOUNDED PASS | Control/delivery issuance, expiry, revocation, scope separation, and no-secret audit/log behavior |
| Reconciliation and audit export | BOUNDED PASS | Verified/missing/corrupt/orphan classification, READY quarantine, chain verification, tamper detection, retention-limited export |
| Restart during mutation | BOUNDED PASS | Throttled artifact PUT interrupted by control-plane restart; same idempotency key retried successfully |
| Independent real app | NOT RUN | Only the deliberate conformance fixture was available; beta gate remains open |

## 4. Hosted service architecture

```text
customer/CI local signer
        │ exact signed Patch Format v1 bytes
        ▼
tool deploy ── authenticated control API ── PostgreSQL metadata
        │                         └─ immutable release/patch/promotion/audit
        └──────────────────────── S3-compatible digest objects
                                             │
                                             ▼
                         read-only runtime lookup/fetch
                                             │
                                             ▼
                         E1 verification and state-v4 activation
```

`PostgresControlPlaneStore` is behind the existing persistence boundary;
`S3CompatibleArtifactStore` is behind the artifact boundary; the filesystem
adapter remains available. The Compose stack is one control-plane process and
one local database/object store. It is not a production topology.

## 5. PostgreSQL, migrations, and tenant isolation

The adapter stores canonical domain records with separate immutable runtime
IDs, organization ownership, idempotency rows, and an audit-chain table. The
schema is shipped as executable Dart migration statements and
`packages/control_plane/migrations/001_initial.sql`. Startup is transactional,
records schema version 1, is duplicate-safe, and leaves readiness false when
the database cannot be reached. SQL access uses parameterized statements.

Authorization derives organization/application/environment ownership from the
credential and stored resource graph. A caller-supplied organization ID is
never sufficient. Unknown and foreign IDs share the service's not-found or
forbidden boundary. Release/Patch/artifact identities are immutable; same-key
same-body retries are idempotent; same-key different-body and same-sequence
equivocation are rejected; promotion uses an expected environment version.

The current schema is intentionally a bounded generic-record seam, not a
final product schema or a promise of query/index capacity.

## 6. S3-compatible objects and runtime delivery

The adapter uses digest-addressed bucket objects, exact byte upload, content
length, digest re-check, immutable `If-None-Match: *`, bounded connection
retry, and standard AWS Signature V4 when access/secret credentials are
provided. GET does not send an invalid conditional header; a recovered object
store can be used by the same control-plane process after a connection reset.

An object is not useful merely because metadata says READY: missing,
truncated, corrupt, or unavailable bytes fail delivery. The runtime still
independently verifies the fetched Patch Format v1 artifact. Delivery remains
`NO_UPDATE`, `PATCH_AVAILABLE`, `UPDATE_BLOCKED`, or
`STORE_RELEASE_REQUIRED`; the server never lowers high-water or emits
unsigned rollback authority.

## 7. Authentication, limits, audit, logs, metrics, and health

Control credentials are random, scoped, hashed at rest, and revocable.
Delivery credentials are read-only and scoped to an application/environment;
they are not signing authority. P2 does not add password login, SSO, SCIM,
managed KMS/HSM, or interactive hosted login.

Configuration validates positive ports/limits, endpoint schemes, and paired
object credentials. HTTP JSON/artifact bodies, idle time, and per-client
request rate are bounded. Structured errors/logs include a safe request ID,
normalized path, error code, timestamp, and duration; headers, query values,
bodies, tokens, private keys, source paths, and patch bytes are not logged.

Audit records contain event/request/organization/actor/resource/action/result
fields; PostgreSQL serializes each audit-chain link in a transaction. The
closure path
exports the tenant records and chain, verifies sequence/link/body digests, and
detects a tampered record without repairing it. This is a bounded
tamper-evidence foundation with retention-limited export, not
compliance-grade immutable evidence. Credential issuance returns a token only
once, stores only its hash, and supports expiry/revocation; delivery scopes
cannot mutate control-plane state.
`/healthz` is process liveness, `/readyz` checks the migration/database seam
and S3 bucket availability, and `/metrics` is process-local operator
measurement rather than runtime telemetry.

## 8. Backup, restore, and outage evidence

`scripts/p2-postgres-backup.sh` creates a custom-format PostgreSQL dump;
`scripts/p2-postgres-restore.sh` requires `HYFENS_ALLOW_RESTORE=1` and restores
only to an explicit target. The closure rehearsal paired an 11,351-byte dump
with a manifest-backed object backup containing one digest-addressed object.
After destroying and recreating the disposable PostgreSQL/MinIO volumes, a
clean coupled restore preserved organization, application, environment,
release/patch, promotion, idempotency, and audit records; lookup returned
`PATCH_AVAILABLE`; the fetched 2,069-byte object matched the original bytes
and digest; `tool verify`, reconciliation, audit-chain verification, and a
same-key deployment retry all passed. This is bounded restore evidence, not an
RPO/RTO, HA, backup-retention, or disaster-recovery claim.

Observed failure behavior:

- PostgreSQL stopped: `/readyz` returned 503; after restart, 200.
- Object store stopped: `/readyz` returned 503; after restart, 200, and the
  existing control-plane process fetched the exact verified 2,069-byte object.
- Control-plane restart: readiness and promoted lookup recovered.
- A throttled artifact `PUT` was interrupted by a control-plane restart (curl
  broken pipe); readiness recovered and retrying the same idempotency key
  completed successfully without leaving the artifact unavailable.
- Missing/corrupt/orphan reconciliation classified the object safely and
  quarantined affected READY metadata; it never regenerated signed bytes.

Installed runtime state remains independent of these service failures.

## 9. Deployment and TLS boundary

`deploy/p2/docker-compose.yml` is a local hosted-like reference with explicit
healthchecks, named volumes, a non-root control-plane container, and injected
configuration. `deploy/p2/nginx.conf.example` documents TLS termination,
body/time limits, request IDs, and forwarded-header assumptions. A disposable
nginx proxy with a proper private CA/server-leaf pair was executed: health,
readiness, CLI deployment, runtime lookup, and artifact fetch passed; replacing
certificate/CA A with different certificate/CA B caused the old trust file to
fail and the new trust file to pass. The CLI now accepts `--ca-cert` or
`HYFENS_TLS_CA_CERT` for an explicit private CA. This is bounded private-TLS
evidence only; trusted proxy configuration, public ingress, network policy,
image provenance, HA, and operational certificate automation remain
production work.

## 10. Load/SLO evidence

The non-mutating `scripts/p2-load-test.py` sample ran 80 requests at
concurrency 8 against one Mac/Compose stack: 40 update checks and 40 artifact
fetches, all successful.

| Operation | Samples | p50 | p95 | p99 | Errors |
| --- | ---: | ---: | ---: | ---: | ---: |
| Update check | 40 | 84.288 ms | 131.267 ms | 140.372 ms | 0 |
| Artifact fetch | 40 | 67.986 ms | 110.737 ms | 121.522 ms | 0 |

Post-sample snapshots were control plane 218.5 MiB, PostgreSQL 23.0 MiB, and
object store 73.7 MiB. These are one-run local measurements with no declared
SLO, capacity target, or internet-scale implication.

## 11. Physical Android result

The initial attempt was environment-gated because the declared Wi-Fi ADB
endpoint was closed. A follow-up run used the connected physical Redmi Note 10
Lite (`192.168.50.135:38951`, Android 16/API 36) and completed the P2
hosted-like sequence against the LAN-bound Compose control plane:

- one stock arm64 Release APK was installed (`52,066,852` bytes);
- the base receipt was `price=540` and the authenticated, Ed25519-signed
  2,069-byte patch changed it to `price=450` without reinstall;
- a force-stop/relaunch restored the signed patch and `price=450`;
- stopping the control-plane process did not remove the active patch; the app
  relaunched offline with `price=450`, and readiness recovered after restart;
- the package `firstInstallTime` and `lastUpdateTime` were unchanged after the
  patch, restart, and outage sequence.

The separate direct physical cross-feature run completed all expected stages:
business logic (`540→450`), async (`asyncPrice=481`), UI, Riverpod,
restart persistence, invalid-signature rejection, manual rollback to BASE,
stale/replay rejection after rollback, and rollback persistence after another
restart. Its redacted receipts and install evidence are under
`experiments/patch_loading/.dart_tool/android_e1_runs/android-p2-followup-20260823-r1/evidence/`.

This is physical evidence for the declared conformance fixture, not evidence
for an independent customer application or arbitrary Flutter semantics.

## 12. Physical iOS result

The USB iPhone used the AUVANA VENTURES PRIVATE LIMITED team and a stock arm64
Release IPA. In a fresh base-to-patch sequence, one installation reported
`price=540`; after authenticated hosted-like deployment and a process restart,
the same installation reported `price=450`; a second restart retained 450.
The receipt was copied from the app Documents container with CoreDevice.

Earlier Task 42 iOS physical evidence covers invalid-signature rejection,
signed rollback, direct stale-byte rejection, and outage retention. P1D-03
diagnostic/UI and P1D-04 performance gates remain open.

## 13. Dart/Flutter and developer experience

P2 did not broaden the Phase 0B semantic support matrix. The tested developer
workflow remains ordinary source plus generated build instrumentation:

```text
tool init
tool release android|ios
# edit ordinary Dart/Flutter source
tool patch
tool verify
tool deploy
```

No `PatchView` is required by the conformance fixture. Existing Phase 0B
limitations still apply: bounded supported Dart subset, explicit host
capabilities, unsupported closures/semantics diagnostics, and no claim of
arbitrary Flutter UI or dependency/native-code OTA patching.

## 14. Independent app and Phase 1D mapping

No independent customer application was available. P1D-07 remains an open
blocker before a beta recommendation. The following conditions remain open:

- P1D-01 true physical power-loss;
- P1D-03/04 iOS diagnostics and performance;
- P1D-06 adjacent SDK support;
- P1D-09 performance attribution;
- P1D-10 multi-function physical claims;
- P1D-11 production audit/evidence maturity;
- P1D-14 fully compromised-device limitation;
- P1D-15 production security/key recovery/availability;
- P1D-16 remote observability boundary;
- P1D-17 long soak/thermal/battery claims; and
- P1D-18 Apple/Google policy review.

P1D-02 remains closed only for the declared Task 42/P2 physical fixtures, and
P1D-13 is a bounded local/self-hosted contract pass. Neither is production or
policy approval.

Task 45 narrowed P1D-05 to a closed, declared physical Android reducer
scope and P1D-08 to a closed, bounded async subset. Those dispositions do not
expand either claim to a universal Android SLO, arbitrary async Dart, or
production readiness; the exact evidence boundary is recorded in
`docs/research/p2-final-evidence-gates-2026-08-23.md`.

## 15. Security and store-policy findings

Positive evidence includes tenant authorization, token hashing/revocation,
scope separation, parameterized PostgreSQL access, immutable object conflict,
digest mismatch rejection, standard S3 signing, malformed artifact handling,
rate/body limits, redacted errors, durable idempotency, optimistic promotion,
runtime-independent verification, coupled database/object restore, digest
reconciliation, audit export/hash-chain tamper detection, private TLS with
certificate rotation, and retry after a restart interrupted an artifact
mutation.

Open findings include public/production TLS and proxy review,
operator/image/supply-chain hardening, durable object replication and retention,
signing-key recovery/rotation operations, compliance-grade audit retention and
export, physical power-loss, compromised-device resistance, and independent
application coverage. No managed private-key custody was introduced.
The bounded customer/local recovery procedure is recorded in
`docs/security/signing-key-recovery.md`; loss or compromise of a key still
requires an operator-approved new trust boundary and is not an in-place
rotation of an immutable installed release.

No App Store, Google Play, or equivalent compliance/approval claim is made.
Business/UI behavior within the measured interpreted subset is an engineering
candidate only; native code, manifests, permissions, entitlements,
SDK/dependency changes, and other store-controlled artifacts require a store
release or policy review.

## 16. Beta and production readiness

This is **not beta-ready** because independent-app evidence, power-loss,
multi-function physical evidence, and claim-specific iOS/attribution gates
remain open. The bounded async and declared Android reducer gates are closed
only for their recorded scopes. It is **not
production-ready** because HA/DR, object durability, TLS/ingress, key
recovery/rotation, audit maturity, security operations, and policy review are
not complete. The hosted-like stack is suitable for bounded engineering
validation and maintainer review only.

## 17. Proposed next implementation phase (not authorized here)

After maintainer approval, a narrowly scoped continuation should:

1. validate one independent real Flutter application under a declared matrix;
2. run true physical power-loss and claim-specific iOS/Android performance,
   async, and multi-function campaigns;
3. define production object-retention/replication, signing-key recovery,
   proxy/ingress, image provenance, and audit-retention operations; and
4. update this review before any P3 rollout, cohort, or telemetry work.

The coupled restore, reconciliation, private TLS/certificate rotation,
credential lifecycle, audit export/tamper, outage, and restart-during-mutation
items listed in the earlier continuation have executed evidence and are not
being represented as unresolved tests.

## 18. Consolidated validation record

Passed in the closure batch, with previously recorded physical-device
evidence retained because the closure source changes did not modify the mobile
runtime or release artifacts:

- `dart analyze` and `dart test` for root, Patch Format, compiler, runtime,
  instrumenter, Flutter integration, CLI, and control plane;
- final bounded validation counts were instrumentation 205 tests, root 1,
  conformance Flutter 18, toolchain Flutter 1, Patch Format 12, control plane
  20 with 3 environment skips, CLI 39, and clean analyzers for root,
  instrumentation, control plane, Patch Format, and CLI;
- `flutter test` for `fixtures/flutter_conformance_app`;
- control-plane PostgreSQL and MinIO integration tests with external
  containers;
- Docker Compose config/build, health, readiness, object outage/recovery,
  database outage/recovery, coupled backup/restore, reconciliation, audit
  export/tamper, private TLS/certificate rotation, and restart-during-mutation;
- physical Android hosted-like and direct cross-feature runs on the Wi-Fi
  Redmi Note 10 Lite, including restart, outage retention, invalid-signature,
  rollback, and stale/replay rejection (prior evidence retained; not rerun in
  the closure batch);
- physical iOS hosted-like run on the USB iPhone using the AUVANA VENTURES
  PRIVATE LIMITED signing team (prior evidence retained; not rerun in the
  closure batch);
- Python syntax and bounded load script;
- shell syntax, Markdown lint, redaction/secret scans, and Compose config;
  no private keys or credentials were added to the repository.

One early aggregate CLI test run timed out because stale child control-plane
test processes remained from overlapping timed-out subprocesses. Only those
known test processes were terminated; the full CLI suite and the affected
tests were then rerun in isolation and passed. No unrelated process or
container was changed.

Task 45 additionally repaired the async benchmark package-root setup, reran
the bounded async benchmark, passed its focused 30-test suite, and reran the
Android performance reducer self-check/reduction against the retained
15-sample physical campaign. These changes were limited to benchmark setup
and documentation; no new mobile-runtime physical claim was created.

## 19. Task 45 final evidence-gate disposition

Task 45 completed the bounded final-gate execution and stops here for
maintainer review. The recommendation remains **CONTINUE P2 MANAGED CLOUD
FOUNDATION**; P3, beta approval, production approval, and store-policy
approval are not authorized by this review.

Closed only for their exact declared boundaries:

- P1D-05: 15-sample physical Android dispatch/startup/memory/APK reducer on
  the Redmi Note 10 Lite fixture;
- P1D-08: capability-mediated `Future<int>` async path with two awaits,
  immediate/delayed completion, error/finally and budget tests.

Still open: independent-app validation (P1D-07), true physical power-loss
(P1D-01), iOS diagnostics/performance (P1D-03/04), internal interpreter
attribution (P1D-09), physical multi-function activation (P1D-10), public
ingress/object durability/HA-DR, production signing ceremony and image/SBOM
provenance, production audit maturity, and Apple/Google policy review.

See the [final evidence-gate report](../../research/p2-final-evidence-gates-2026-08-23.md)
and [store-policy review package](../../store-policy/p2-review-package.md) for
commands, evidence labels, and explicit environment-gated results.

## 20. Task 46 external-gate continuation

The external-gates continuation audited the repository for a genuinely
independent maintained Flutter application and found none. The available
`fixtures/flutter_conformance_app`, `fixtures/flutter_toolchain_app`, and
generated `.phase1c-android-bench` copy are repository-owned validation
fixtures and remain excluded from P1D-07. No independent-app workflow or
unsupported-change matrix is therefore claimed.

Per the external-gates stop rule, the continuation stopped at this dependency
instead of creating a substitute app or proceeding with lower-priority
external claims. P1D-07 remains **OPEN / BETA BLOCKER**. No runtime,
compiler, instrumenter, delivery, mobile release, signing, or trust-boundary
change was made. P1D-01, P1D-03/04, P1D-09/10, P1D-11, P1D-15, and P1D-18 retain
their existing open or environment-gated dispositions. Maintainer review is
required before any further P2 external-gate work; P3 remains prohibited.

## 21. Task 47 residual evidence and production-hardening addendum

Task 47 executed the previously open physical multi-function gate and the
orthogonal production-hardening checks without changing the frozen runtime,
Patch Format v1, capability boundary, rollback authority, or signing custody.
Detailed receipts and exact boundaries are in
[`research/p2-multi-function-physical-2026-08-23.md`](../../research/p2-multi-function-physical-2026-08-23.md),
[`research/p2-interpreter-attribution-2026-08-23.md`](../../research/p2-interpreter-attribution-2026-08-23.md),
and [`research/p2-production-hardening-2026-08-23.md`](../../research/p2-production-hardening-2026-08-23.md).

### Current gate disposition

| Gate | Current disposition | Exact boundary |
| --- | --- | --- |
| P1D-01 true physical power loss | **OPEN — ENVIRONMENT-GATED** | No safe OS-level interruption was executed. Process stop/restart is not power-loss evidence. |
| P1D-03 iOS diagnostics | **OPEN — ENVIRONMENT-GATED** | USB iPhone state receipts passed, but the Developer Disk Image/runtime diagnostic stream remains unavailable. |
| P1D-04 iOS performance | **OPEN — NOT RUN** | No controlled stock/instrumented/active-patch iOS performance series was collected. |
| P1D-07 independent application | **OPEN — BETA BLOCKER** | No independent maintained Flutter application was supplied; repository fixtures remain excluded. |
| P1D-09 interpreter attribution | **OPEN — INSUFFICIENT ATTRIBUTION / PRODUCTION BLOCKER** | Host public-layer workload timings ran, but no private interpreter-stage hooks exist; no optimization was made. |
| P1D-10 multi-function physical | **CLOSED — DECLARED ANDROID + IOS SCOPE** | Both devices verified the selected business, async, and widget slots through activation, restart, rejection, rollback, and persistence. The claim is limited to the named fixture/artifact and does not generalize to arbitrary patch counts. |
| P1D-11 audit maturity | **OPEN — SECURITY REVIEW** | Local hash-chain/export/tamper evidence remains bounded; signed off-box export and compliance controls are open. |
| P1D-15 production security/recovery | **OPEN — SECURITY REVIEW** | Disposable signing/tabletop and local ingress checks passed; production ceremony, public edge, durability, HA/DR, and provenance remain open. |
| P1D-18 store policy | **OPEN — EXTERNAL REVIEW REQUIRED** | No Apple/Google approval or legal conclusion is inferred. |

The Android successful run used one install invocation on the physical Redmi
Note 10 Lite and produced a 7,505-byte signed Patch Format v1 artifact. The
iOS run used the AUVANA VENTURES PRIVATE LIMITED automatic-signing team and
one installed arm64 Release app. Both physical runs rejected a tampered
candidate without losing the healthy multi-function behavior and persisted
manual rollback to base across a process restart. The Android receipts assert
business, async, and widget outputs; the corrected iOS receipts now assert
the same three outputs at activation and persistence. The first iOS USB
upload attempt used the wrong path form and failed closed; the path was
corrected to `Documents/...` without reinstalling, and the successful suffix
is recorded separately rather than hiding the setup failure.

### Four separate decisions

- **P2 technical implementation:** bounded-complete for the declared
  single-node/self-hosted scope plus the declared Android+iOS multi-function
  proof.
- **Beta readiness:** blocked. P1D-07 remains an independent-app blocker and
  the remaining claim-specific platform gates are not generalized.
- **Production readiness:** blocked. Public ingress, provider object
  durability/retention, HA/DR, numeric RPO/RTO, internal attribution,
  production signing operations, SBOM/provenance, and audit maturity remain
  open.
- **Store-policy/legal:** external review required. The engineering change
  matrix is not a compliance determination.

### Task 47 recommendation

**`CONTINUE P2 FOR EXTERNAL EVIDENCE`**. Do not start P3, beta approval,
production deployment, or store submission from this addendum.

## 22. Task 48 repository-controlled production-readiness closure

Task 48 is a bounded continuation of this review. Earlier sections and Task
47 dispositions remain historical evidence; this section records the newer
repository-controlled results without relabelling provider or external gates.

### Five separate decisions

| Decision | Current result | Boundary |
| --- | --- | --- |
| P2 technical implementation | **BOUNDED COMPLETE** | Single-node/self-hosted control plane plus the declared Android+iOS conformance fixture. |
| Beta readiness | **BLOCKED** | P1D-07 independent maintained app and claim-specific physical/platform gates remain open. |
| Repository-controlled production readiness | **PASSED — BOUNDED** | Task 48 checklist passed locally: attribution seam, signed off-box audit envelope, ingress trust tests, disposable application HA, directional DR, bounded SBOM/provenance, and operations contracts. P1D-09 remains open because attribution is still insufficient. |
| External/provider production readiness | **BLOCKED** | Public edge, managed PostgreSQL/object durability and failover, off-site backup/retention, approved RPO/RTO, image attestation, production secret/key custody, and operational ownership remain unproven. |
| Store-policy/legal readiness | **EXTERNAL REVIEW REQUIRED** | No Apple/Google approval or legal conclusion is inferred. |

### Repository-owned evidence

- `PERFORMANCE_ATTRIBUTION`: five samples, one warmup, 1,000 iterations over
  pricing, eligibility, collection, state, route, and bounded async workloads;
  profiler-disabled/enabled runs completed, but the decision is
  **`ATTRIBUTION STILL INSUFFICIENT`** and no optimization was made.
- `AUDIT_EXPORT_SIGNED_OFFBOX`: a separate deterministic Ed25519 export was
  verified from a copied file without database access; record, sequence,
  organization, retention, signature, and wrong-key mutations failed safely.
- `INGRESS_TRUST_BOUNDARY_LOCAL`: authorization derives only from bearer
  credentials; forwarded, host, and request-ID headers are correlation or
  metadata only. Local spoof, duplicate, oversized, direct-access, and route
  tests passed.
- `APPLICATION_HA_DISPOSABLE`: two stateless instances shared disposable
  PostgreSQL/MinIO behind a proxy; instance loss, rolling restart, idempotent
  retry, and dependency readiness/recovery passed. A concurrent migration
  race found during rehearsal was fixed with a transaction-scoped advisory
  lock and then retested.
- `DISASTER_RECOVERY_DIRECTIONAL`: exact bytes and digest survived backup,
  destroy/recreate, explicit restore, reconciliation, audit verification, and
  lookup/fetch. The run does not prove provider durability or an approved
  numeric RPO/RTO.
- `SBOM_PROVENANCE` and `IMAGE_PROVENANCE_BOUNDED`: Syft 1.51.0 generated a
  135-package SPDX 2.3 inventory from the local arm64 image; source,
  Dockerfile, and image digests are recorded. No registry attestation,
  vulnerability scan, or floating-base pinning claim is made.
- `SLOW BUT CORRECT`: the CLI keygen/sign round-trip and full signing test
  passed after an explicit two-minute test timeout. The earlier 30-second
  result was host startup variance at the harness boundary, not a CLI defect
  or subprocess leak.

Focused evidence is in `docs/research/p2-*2026-08-23.md`, the production
configuration and runbook under `docs/operations/`, the secret matrix under
`docs/security/`, and `tasks/48-p2-repository-controlled-production-readiness.md`.

### Final recommendation

**`P2 REPOSITORY-CONTROLLED READINESS COMPLETE — EXTERNAL GATES REMAIN`**.
Stop for maintainer review. Do not begin P3, beta approval, production
deployment, or store submission from this record.

## 23. Task 49 formal P2 engineering exit and P3 design gate

Task 49 formalized the repository-controlled closure without adding runtime,
control-plane, mobile, provider, or store evidence. The five independent
decisions remain: P2 technical implementation `BOUNDED COMPLETE`; beta
`BLOCKED`; repository-controlled production `PASSED — BOUNDED`;
external/provider production `BLOCKED`; and store/legal `EXTERNAL REVIEW
REQUIRED`.

The exact exit statement is **`P2 ENGINEERING CLOSED — EXTERNAL GATES CARRIED
FORWARD`**. The frozen baseline and relative-path SHA-256 evidence index are
in [`P2_EXIT_REVIEW.md`](P2_EXIT_REVIEW.md) and
[`research/evidence/p2-exit-manifest.json`](../../research/evidence/p2-exit-manifest.json).
The future Rollout & Observability proposal is design-only in
[`P3_ROLLOUT_OBSERVABILITY_DESIGN.md`](P3_ROLLOUT_OBSERVABILITY_DESIGN.md).

P1D-01, P1D-03, P1D-04, P1D-07, P1D-09, and P1D-18 remain open or externally
gated as recorded in the exit review. P1D-10 remains closed only for the
declared Android+iOS fixture scope. P3 implementation, beta approval,
provider-production approval, and store/legal approval remain unauthorized.
The maintainer must choose one of `HOLD P3 — EXTERNAL GATES FIRST`,
`AUTHORIZE P3 DESIGN ONLY — COMPLETE`, `AUTHORIZE P3 IMPLEMENTATION WITH
CONDITIONS`, `RETURN TO P2`, or `STOP PROJECT`.

## Task 51 iOS gate rerun addendum — 2026-08-23

The unlocked USB iPhone became available after the historical P2 gate tables
were written. Task 51 reran only the previously environment-gated iOS
diagnostic/performance evidence and did not change the P2 engineering closure,
the P3A review gate, or any external/provider/store decision.

| Gate | Current bounded result | Evidence |
| --- | --- | --- |
| P1D-03 | **CLOSED — DECLARED DEVICE/TOOLCHAIN SCOPE** | iPhone XR/iOS 18.7.9; personalized Developer Disk Image mounted; `idevicesyslog` captured Runner and Flutter observations; xcodebuildmcp launch succeeded. |
| P1D-04 | **PARTIAL — STARTUP/CPU PROFILE CLOSED; RESOURCE/THROUGHPUT OPEN** | Physical stock, instrumented-unpatched, and active-patch Release traces and App Launch lifecycle phases collected; binary sizes recorded. No usable Allocations RSS/heap number, thermal/battery/soak, or controlled dispatch-throughput series. |

The complete record is
[`docs/research/ios-gate-rerun-2026-08-23.md`](../../research/ios-gate-rerun-2026-08-23.md).
P1D-01 true power loss, P1D-07 independent application, P1D-09 attribution,
provider production, beta, and Apple/Google/legal review remain open. No store
or production claim is inferred from the physical fixture run.
