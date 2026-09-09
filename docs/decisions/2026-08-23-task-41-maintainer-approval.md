# Task 41 maintainer approval

**Effective date:** 2026-08-23
**Source record:** `/Volumes/970EvoPlus/Downloads/TASK_41_MAINTAINER_APPROVAL_AND_BLOCKER_CLOSURE.md`

This repository copy records the maintainer authorization that closes the
four Task 41 P0/P1 gates. The source record remains the signed approval
record; this copy makes the decision auditable alongside the task and review
documents.

## Approved decisions

| Gate | Decision |
| --- | --- |
| License and governance | Apache License 2.0 for the OSS core; maintainer-led governance; DCO sign-off; no CLA initially |
| OSS/commercial boundary | Runtime, verifier/interpreter, bootstrap, Patch Format v1, capability v1, instrumenter, compiler, diagnostics, local CLI/signing/verification/status/rollback, minimal self-host reference, and relevant protocol/developer docs remain open source |
| P1D-13 signing and delivery | Customer/local signing custody; private patch-signing keys never enter the service; application/environment delivery credentials are read-only and cannot sign or mutate control-plane state |
| Initial service stack | Modular Dart single-node service using `dart:io`, filesystem metadata persistence, and content-addressed filesystem artifacts |

## Frozen boundaries

The approval does not change Architecture B, Patch Format v1, capability v1,
exact release binding, state-v4 trust/high-water, signed rollback, fail-closed
recovery, runtime signature authority, or AOT fallback. It does not authorize
managed cloud, CDN, telemetry, dashboards, billing, managed KMS/HSM, SSO/SCIM,
advanced RBAC, enterprise packaging, production deployment, store submission,
React Native, or commercial pricing.

## Required implementation boundary

The authorized local slice is limited to tenant-safe domain records,
hashed/scoped control and read-only delivery credentials, immutable release /
patch / artifact registration, content-addressed storage, all-or-none
promotion, authenticated update lookup/fetch, CLI `deploy`, redacted
append-only audit, idempotency/concurrency, and evidence-labeled tests. The
runtime remains authoritative: service admission and delivery can only filter
or withhold bytes and can never make invalid bytes executable.

P1D-02 direct physical stale-byte rejection remains a separate beta evidence
gate. If it is not safely demonstrated, it must remain open in the final
review rather than being inferred from server-side withholding.
