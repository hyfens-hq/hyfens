# ADR 0007 — Treat artifact distribution as untrusted and content-addressed

- Status: Proposed for Task 40 productization design; implementation not authorized
- Date: 2026-08-23
- Decision owners: Maintainers after productization review

## Context

The local Architecture B runtime already verifies bounded signed Patch Format
v1 artifacts, exact application/release compatibility, capability v1, sequence
and high-water/replay state, health, rollback, and fail-closed recovery. A
product path adds control-plane metadata and may deliver through object storage,
a CDN, a self-hosted endpoint, or offline media. Those transports can be
misconfigured or compromised and must not silently become a second trust root.

The product also needs immutable retention and deterministic recovery. A mutable
`latest` object, a CDN cache entry, or a server-side “approved” flag cannot
stand in for the exact bytes and runtime checks.

## Decision

1. Store each executable patch as the exact Patch Format v1 bytes addressed by
   `sha256:<lowercase-digest>`. The digest covers the bytes delivered to the
   runtime, including the signature section. Objects are write-once by logical
   address; deletion affects availability and retention only.
2. Keep patch bytes, signed rollback/key-lifecycle controls, release metadata,
   rollout policy, and optional debug/source-map bundles as separate object
   classes. Product metadata is not appended to or used to reinterpret Patch
   Format v1.
3. Treat update lookup, artifact fetch, CDN/self-host responses, signed URLs,
   TLS, object ACLs, and air-gap transfer media as untrusted inputs. The
   runtime recomputes the digest and runs the existing canonical, signature,
   exact-release, capability, resource, high-water, staging, health, and
   fallback checks.
4. Let the control plane select eligibility and return one of
   `NO_UPDATE`, `PATCH_AVAILABLE`, `ROLLBACK_CONTROL`, `UPDATE_BLOCKED`, or
   `STORE_RELEASE_REQUIRED`. It may withhold delivery but cannot make a stale,
   incompatible, unsigned, or capability-invalid artifact valid.
5. Support object storage plus CDN, authenticated/self-hosted endpoints,
   private enterprise distribution, and an air-gap transfer bundle through the
   same digest/fetch abstraction. An air-gap bundle carries an inventory and
   exact bytes; it is not a new patch format and cannot carry private keys.
6. Preserve local correctness during network or hosted outages. Failure means
   no new update and continued use of the last verified state or compiled AOT
   base. A rollback to base is a separate signed control that matches the
   exact durable high-water; restoring old behavior requires a newly signed
   higher-sequence artifact.

## Alternatives considered

- **Mutable versioned URLs or `latest`:** Simple for clients, but cache/store
  substitution and rollback ambiguity make the URL a dangerous identity.
- **Trust the control plane or CDN after TLS/authentication:** Reduces some
  transport risk but turns an availability component into an executable trust
  root and fails under compromise.
- **Provider-specific artifact protocol:** Could optimize a managed offering,
  but would make self-hosting and air-gap support depend on a provider and
  would contaminate the frozen runtime format.
- **Require online runtime authorization:** Provides centralized revocation but
  makes outages and air-gapped operation correctness dependencies. Runtime
  signature/high-water checks are the durable safety boundary instead.

## Consequences

Positive consequences are deterministic bytes, cache-friendly distribution,
offline transfer, simpler incident evidence, and a clear separation between
delivery availability and runtime trust. The control plane can still be
compromised for withholding, targeting, or metadata disclosure, so tenant
authorization, audit, and operational hardening remain necessary.

Costs include immutable storage lifecycle management, digest-aware caches,
explicit transfer/import review, and separate retention for debug material.
Provider adapters, HTTP services, CDN integration, and runtime networking are
future implementation work. This ADR does not claim a particular provider,
SLO, or store-policy outcome.

## Phase 1D boundary

The design retains the Phase 1D gaps: true power-loss durability is not tested;
direct physical stale-byte rejection is not proven beyond delivery-boundary
withholding; iOS logs/UI and timings were unavailable under the missing
Developer Disk Image; no fresh Android reducer, independent customer-app
validation, or additional async benchmark was completed; and the adjacent
Flutter 3.47.1/Dart 3.13.1 path remains `SUPPORTED_WITH_LIMITATIONS`. These are
later implementation/release gates, not reasons to weaken the runtime trust
boundary.

## References

- [Artifact distribution and trust architecture](../architecture/distribution-trust.md)
- [Runtime state machine](../architecture/runtime-state-machine.md)
- [Patch lifecycle](../architecture/patch-lifecycle.md)
- [Patch Format v1](../spec/patch-format-v1.md)
- [Capability Contract v1](../spec/capability-v1.md)
- [Phase 1D review](../history/reviews/PHASE_1D_REVIEW.md)
