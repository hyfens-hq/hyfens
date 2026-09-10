# P2 engineering exit review

Status: `CLOSED — BOUNDED ENGINEERING; EXTERNAL GATES CARRIED FORWARD`

Date: 2026-08-23

<!-- This review contains intentionally wide evidence tables. -->
<!-- markdownlint-disable MD013 -->

## Decision boundary

Task 49 closes the repository-controlled P2 implementation and evidence work
at the boundary already established by Task 48. It does not convert local or
disposable evidence into beta, provider-production, App Store, Google Play, or
legal approval. The [deterministic P2 evidence manifest](../../research/evidence/p2-exit-manifest.json)
indexes the source records and their SHA-256 digests; it is an evidence index,
not a new trust root.

The five readiness decisions remain independent:

```text
P2 ENGINEERING STATUS
→ COMPLETE — BOUNDED

BETA STATUS
→ BLOCKED

REPOSITORY-CONTROLLED PRODUCTION STATUS
→ PASSED — BOUNDED

EXTERNAL/PROVIDER PRODUCTION STATUS
→ BLOCKED

STORE/LEGAL STATUS
→ EXTERNAL REVIEW REQUIRED
```

| Decision | Result | Meaning |
| --- | --- | --- |
| P2 technical implementation | **BOUNDED COMPLETE** | The declared single-node/self-hosted control plane, runtime delivery path, and retained Android+iOS conformance-fixture evidence are complete for their exact scope. |
| Beta readiness | **BLOCKED** | P1D-07 and the claim-specific physical, diagnostic, performance, and durability gates remain open. |
| Repository-controlled production readiness | **PASSED — BOUNDED** | The Task 48 local checklist passed for the repository-owned boundary only. |
| External/provider production readiness | **BLOCKED** | Public edge, provider durability/failover, production custody, monitoring, recovery objectives, and related controls remain unproven. |
| Store-policy/legal readiness | **EXTERNAL REVIEW REQUIRED** | Engineering classifications are not Apple, Google, or legal approval. |

## Exact exit statement

> **P2 ENGINEERING CLOSED — EXTERNAL GATES CARRIED FORWARD**

This is the accepted P2 engineering exit decision. It authorizes no P3
implementation. The next action is maintainer review of this document, the
manifest, and the [P3 Rollout & Observability design](P3_ROLLOUT_OBSERVABILITY_DESIGN.md).

## Final P2 scope

P2 includes the bounded, inspectable path built across Tasks 41–48:

- stock Flutter release integration using Architecture B source
  instrumentation and AOT fallback;
- Patch Format v1 parsing, deterministic encoding, Ed25519 verification,
  exact application/release/function/capability binding, and signed rollback;
- state-v4 durable high-water, pending/healthy/last-known-good recovery, and
  fail-closed startup/activation behavior;
- customer/local patch signing, a read-only delivery credential boundary, and
  a local/self-hosted single-tenant control plane;
- filesystem and PostgreSQL metadata persistence, S3-compatible
  content-addressed artifact storage, authenticated lookup/fetch, immutable
  bytes, idempotent promotion, and redacted audit;
- bounded Docker Compose deployment, configuration and secret contracts,
  backup/restore and reconciliation procedures, disposable HA/DR rehearsals,
  signed off-box audit export, local ingress trust tests, and bounded
  SBOM/provenance evidence;
- the retained physical Android and iOS conformance-fixture sequences and
  the bounded Android performance/async/multi-function evidence explicitly
  named in the phase-1d register.

P2 does not include a rollout service, cohort assignment, telemetry
ingestion, dashboard, billing, enterprise identity, managed KMS/HSM,
multi-region deployment, React Native, store submission, or legal review.

## Frozen implementation and trust invariants

The following are unchanged and remain mandatory for every future phase:

1. Architecture B source instrumentation with normal AOT fallback remains the
   runtime architecture; no Flutter/Dart fork, JIT, or downloaded native code
   was introduced.
2. Patch Format v1 and capability v1 remain frozen. P3 metadata is not a Patch
   Format field and cannot broaden the capability registry.
3. The runtime remains authoritative for signature verification, exact
   application/release/function binding, runtime compatibility, capability
   requirements, sequence high-water, health, activation, rollback, and
   fail-closed recovery.
4. Signed bytes are immutable and content-addressed. A database row, rollout
   policy, operator action, cache, dashboard, or server response cannot make
   invalid bytes valid.
5. Customer/local private patch-signing custody remains outside the control
   plane. Delivery credentials are read-only for runtime lookup/fetch and are
   not signing authority.
6. Rollback does not lower high-water. An older byte sequence cannot be
   reactivated merely because a service marks it current.
7. A healthy installed patch remains locally usable during control-plane or
   observation outages. Connectivity is not a runtime correctness authority.

## Frozen P2 baseline

The baseline below records versions and contracts already present in the
repository. It is a snapshot of existing implementation, not a new runtime
release or a claim of support for every future Flutter/Dart version.

| Area | Frozen baseline |
| --- | --- |
| Host/toolchain | macOS arm64; Flutter 3.47.0 stable (framework revision `4cf2416426`, engine revision `5f77625673`); Dart 3.13.0; Xcode 26.6 (17F113); Java 17.0.13. |
| Dart package versions | `hyfens_patch_format`, `hyfens_runtime`, `hyfens_compiler`, `hyfens_instrumenter`, `hyfens_flutter_integration`, `hyfens_control_plane`, and `hyfens_tool` are repository packages at `0.1.0`; root research package is `0.0.0`. |
| Implemented packages/modules | `packages/patch_format`, `packages/runtime`, `packages/compiler`, `packages/instrumenter`, `packages/flutter_integration`, `packages/control_plane`, `cli`, `experiments/instrumentation`, `experiments/patch_loading`, `fixtures/flutter_conformance_app`, `fixtures/flutter_toolchain_app`, `deploy/p2`, and the bounded backup/restore/provenance scripts. |
| Runtime/format | Patch Format v1; runtime compatibility `1`; E0 bridge version `1`; capability versions are explicit in the artifact; parser limits and malformed-input behavior are defined in `packages/patch_format`. |
| Durable state | State-v4 trust journal (compatibility filenames retained); dual checksummed copies, monotonic high-water, pending/healthy/LKG, signed rollback, and fail-closed recovery. |
| Control plane | `hyfens_control_plane` `0.1.0`; filesystem self-hosting plus PostgreSQL metadata adapter; schema migration `001_initial.sql`; S3-compatible immutable artifact adapter; current bounded `/v1` release/patch/artifact/runtime-delivery surface. |
| Database schema | Migration 001 creates `control_plane_schema_migrations`, `control_plane_records`, `control_plane_artifacts`, and `control_plane_audit_chain`; migration application is transaction-scoped and guarded for concurrent startup. |
| Artifact contract | Exact signed Patch Format v1 bytes are stored by SHA-256 digest; metadata references the immutable digest; runtime re-verifies signature, digest, identity, capabilities, compatibility, and high-water. |
| CLI surface | Existing local tool commands include `init`, `status`, `analyze`, `release`, `patch`, `rollback`, `cleanup`, `inspect`, `verify`, `serve`, and bounded `deploy`; no rollout command exists. |
| Deployment reference | `deploy/p2/Dockerfile`, `docker-compose.yml`, `docker-compose.ha.yml`, nginx examples, backup/restore scripts, operations configuration, and runbooks. Compose evidence is disposable/local, not provider HA or internet-scale production. |
| Signing custody | Local/offline Ed25519 private keys; public verification key is trusted by the app/release; the service stores public metadata and exact signed bytes only. Audit-export signing is a separate test/offline boundary. |

## Repository-controlled evidence closed in P2

These evidence labels are closed only for the boundaries stated in the source
reports. They must not be relabelled as provider-production evidence.

| Evidence label | Result and boundary | Source |
| --- | --- | --- |
| Physical Android and iOS delivery | One-install conformance-fixture activation, restart persistence, service-outage retention, signature rejection, signed rollback, stale/replay rejection, and bounded multi-function business/async/widget behavior passed on the declared Redmi Note 10 Lite and USB iPhone. | [Task 42 Android evidence](../../research/evidence/task42-android-control-plane.md), [Task 42 iOS evidence](../../research/evidence/task42-ios-control-plane.md), [Task 47 multi-function report](../../research/p2-multi-function-physical-2026-08-23.md) |
| Android performance reducer | Fifteen process-isolated samples per declared variant on the Redmi Note 10 Lite; closed only for the named reducer and not as a universal SLO or iOS inference. | [P2 final evidence gates](../../research/p2-final-evidence-gates-2026-08-23.md) |
| Bounded async | Capability-mediated `Future<int>` with immediate/delayed completion, two awaits, error/finally, continuation, and budget tests; streams, `async*`, cancellation, closures, and hot-frame claims remain outside the scope. | [P2 async evidence](../../research/evidence/p2-final-async-benchmark-20260823.json), [P2 final evidence gates](../../research/p2-final-evidence-gates-2026-08-23.md) |
| Signed audit export | Separate deterministic Ed25519 off-box envelope; copied-file offline verification; record, sequence, organization, retention, malformed-envelope, invalid-chain, tamper, and wrong-key rejection passed. | [Audit-export research](../../research/p2-audit-export-signing-2026-08-23.md) |
| Local ingress trust boundary | Bearer credentials are authoritative; forwarded, host, and request-ID headers are correlation/metadata only. Duplicate, spoofed, oversized, direct-access, route, tenant, and request-ID cases passed locally. | [Ingress research](../../research/p2-ingress-trust-boundary-2026-08-23.md) |
| Application HA | `APPLICATION_HA_DISPOSABLE`: two stateless instances behind a local proxy with disposable PostgreSQL/MinIO; readiness, idempotent retry, instance loss, rolling restart, dependency outage/recovery, and migration-race repair passed. | [HA/DR research](../../research/p2-application-ha-dr-2026-08-23.md) |
| Directional DR | `DISASTER_RECOVERY_DIRECTIONAL`: exact PostgreSQL/object backup, destroy/recreate, explicit restore, reconciliation, audit verification, and digest-preserving fetch passed in a quiesced disposable rehearsal. Provider durability, automated failover, and approved RPO/RTO remain unproven. | [HA/DR research](../../research/p2-application-ha-dr-2026-08-23.md) |
| SBOM/provenance | Syft 1.51.0 generated a local SPDX 2.3 inventory with 135 packages; source, Dockerfile, and local image digests were recorded. Registry attestation, vulnerability scanning, pinned-base policy, and provider provenance remain open. | [SBOM/provenance research](../../research/p2-sbom-provenance-2026-08-23.md) |
| Attribution | Stage profiler is disabled by default; five samples, one warmup, and 1,000 iterations over six workloads produced `ATTRIBUTION STILL INSUFFICIENT`; no optimization was authorized. | [Attribution research](../../research/p2-interpreter-attribution-2026-08-23.md) |
| CLI signing | Local keygen/sign round-trip is `SLOW BUT CORRECT`; explicit two-minute test timeout was required on this host. No leak or signing defect was reproduced. | [CLI signing research](../../research/p2-cli-signing-timeout-2026-08-23.md) |

The full test totals and command receipts are retained in the historical
`Task 48` validation record.
The final consolidated run passed root `1`, Patch Format `12`, runtime `6`,
compiler `1`, instrumenter `3`, Flutter integration `18`, instrumentation
`207`, patch-loading `59` with `2` explicit environment skips, CLI `39`,
conformance Flutter `18`, and toolchain Flutter `1`, plus affected analysis,
formatting, shell/Python, Compose, Markdown, and secret scans.

## Phase 1D gates: closed or narrowed only

This table preserves the exact claim boundaries. “Closed” is never shorthand
for arbitrary Dart, every app, every device, store approval, or production
readiness.

| Gate | Current status | Preserved boundary |
| --- | --- | --- |
| P1D-01 true physical power loss | **OPEN / ENVIRONMENT-GATED** | No safe OS-level interruption was executed; process stop/restart is not power-loss evidence. |
| P1D-02 direct stale valid bytes | **CLOSED / DECLARED PHYSICAL FIXTURES** | Android and iOS conformance fixtures rejected the supplied stale bytes after rollback and retained BASE/high-water. |
| P1D-03 iOS diagnostics | **OPEN / ENVIRONMENT-GATED** | Developer Disk Image/runtime diagnostic stream remains unavailable for fresh diagnostics claims. |
| P1D-04 iOS performance | **OPEN / NOT RUN** | No controlled stock/instrumented/active-patch iOS performance series exists. |
| P1D-05 Android performance reducer | **CLOSED / DECLARED PHYSICAL ANDROID REDUCER** | Redmi Note 10 Lite / Android 16 / arm64-v8a / Flutter 3.47.0 / Dart 3.13.0, 15 samples per declared variant; no universal SLO or iOS inference. |
| P1D-06 adjacent SDK | **ACCEPTED LIMITATION** | The fully bounded support claim remains Flutter 3.47.0/Dart 3.13.0; adjacent SDK support is not inferred. |
| P1D-07 independent application | **OPEN / BETA BLOCKER** | No independent maintained Flutter application was supplied; repository fixtures do not qualify. |
| P1D-08 async subset | **CLOSED / BOUNDED ASYNC SUBSET** | Capability-mediated `Future<int>` subset only; broad Future/Stream/closure/hot-frame behavior is not claimed. |
| P1D-09 interpreter attribution | **OPEN / PRODUCTION PERFORMANCE LIMITATION** | Public-layer profiling remains insufficient to attribute decode, allocation, dispatch, capability, or interpreter-stage cost; no optimization was made. |
| P1D-10 multi-function physical | **CLOSED / DECLARED ANDROID + IOS FIXTURE SCOPE** | Named business, async, and widget slots passed lifecycle/rejection/rollback/persistence checks; this is not arbitrary patch-count or arbitrary-Dart support. |
| P1D-11 audit maturity | **OPEN / SECURITY REVIEW** | Local chain/export/tamper and signed off-box evidence passed, but compliance-grade retention/access/provenance remains open. |
| P1D-12 duplicate task numbering | **ACCEPTED LIMITATION** | Historical duplicate `tasks/39` numbering is retained for traceability. |
| P1D-13 delivery/key custody | **BOUNDED LOCAL/SELF-HOSTED SATISFIED; PRODUCTION OPEN** | Customer/local signing, read-only delivery, runtime verification, activation, outage retention, rollback, and stale rejection passed for declared fixtures; hosted custody/rotation/revocation remains open. |
| P1D-14 compromised device | **ACCEPTED LIMITATION** | Full device compromise can tamper with local state; fail-closed recovery is not a secrecy guarantee. |
| P1D-15 production security/recovery | **OPEN / PRODUCTION** | Production ceremony, public edge, durability, HA/DR, key recovery, and provenance are not proven. |
| P1D-16 local observability | **ACCEPTED LIMITATION / P3 DESIGN INPUT** | Current observability is local and bounded; future observations must remain optional, privacy-preserving, incomplete, and non-authoritative. |
| P1D-17 broad performance/soak | **ACCEPTED LIMITATION** | No indefinite soak, thermal/battery, broad Future/Stream, or hot-frame suitability claim exists. |
| P1D-18 store/legal | **OPEN / EXTERNAL REVIEW REQUIRED** | The Apple/Google change matrix is engineering research only; no approval or compliance conclusion is inferred. |

## External/provider production gates

The following remain blocked or require external review. Local Compose/HA/DR
simulations are retained as bounded evidence and are not substitutes.

| Gate | Status | What is still required |
| --- | --- | --- |
| Public edge and DNS | **OPEN** | Real public ingress, DNS, TLS lifecycle, firewall/security groups, DDoS/WAF policy, and ownership evidence. |
| Database/object durability | **OPEN** | Managed/external PostgreSQL HA, object versioning/replication/durability, retention, failover, and restore evidence. |
| Backup/DR objectives | **OPEN** | Off-site scheduled backups, zone/region failure behavior, approved numeric RPO/RTO, and an accountable operator. |
| Production credentials and secrets | **OPEN** | Production secret manager, credential rotation/revocation, delivery boundary, key-recovery ceremony, and access audit. |
| Image/software provenance | **OPEN** | Registry attestation, vulnerability scanning, pinned base policy, release provenance, and deployment admission policy. |
| Monitoring/on-call | **OPEN** | Production monitoring, alert ownership, incident response, service objectives, and tested halt/recovery procedures. |
| Audit/compliance operations | **OPEN** | Durable access control, retention/deletion, off-box export custody, review process, and any customer/legal requirements. |

## Beta, store, and legal blockers

Beta cannot be declared while P1D-07 and the corresponding platform,
durability, and claim-specific gates remain open. The P3 design cannot waive
those gates. Apple/Google policy text and the repository's [change matrix](../../store-policy/change-matrix.md)
do not establish project-specific approval; policy/legal review remains an
external prerequisite before any store or compliance statement.

## Repository limitations accepted at P2 exit

- The conformance and toolchain fixtures are repository-owned and are not
  customer-app evidence.
- The runtime supports a declared bounded subset; unsupported language,
  platform, native-plugin, and store-release changes remain outside the claim.
- P1D-09 attribution is insufficient, so no interpreter-performance budget,
  scale claim, or optimization is published.
- Local/disposable HA and DR demonstrate application behavior and procedure,
  not provider durability, automated failover, or numeric recovery objectives.
- Observation, rollout, and product analytics do not exist in the P2
  implementation; P3 below is design only.

## Reproducibility and validation record

The baseline can be reconstructed from the repository files and evidence
listed in [research/evidence/p2-exit-manifest.json](../../research/evidence/p2-exit-manifest.json).
The manifest intentionally contains relative paths and SHA-256 digests only;
it contains no private key, token, credential, or absolute workstation path.

Task 49 changed documentation and task-status metadata only. No runtime,
compiler, instrumenter, Patch Format, control-plane behavior, mobile release,
provider deployment, or store artifact changed. Consequently, no physical
device rerun is represented as new evidence here. The validation commands for
this closure are document lint, link/path, JSON, boundary, whitespace, and
secret scans; the exact results are appended to Task 49.

## Maintainer decision options

The maintainer must choose one explicit next state:

- `HOLD P3 — EXTERNAL GATES FIRST`
- `AUTHORIZE P3 DESIGN ONLY — COMPLETE`
- `AUTHORIZE P3 IMPLEMENTATION WITH CONDITIONS`
- `RETURN TO P2`
- `STOP PROJECT`

This review recommends no option on the maintainer's behalf. The engineering
exit is complete, and implementation authority for P3 remains absent.

## References

- `Task 49` transition record;
- `Task 48` closure;
- [P2 managed-cloud review](P2_MANAGED_CLOUD_REVIEW.md);
- [Phase 1D conditions](../product/phase-1d-conditions.md);
- [P3 Rollout & Observability design](P3_ROLLOUT_OBSERVABILITY_DESIGN.md);
- [P2 evidence manifest](../../research/evidence/p2-exit-manifest.json).
