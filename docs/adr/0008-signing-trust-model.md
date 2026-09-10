# ADR 0008 — Keep signing custody separate from distribution and preserve release-owned trust

- Status: Proposed for Task 40 productization design; implementation not authorized
- Date: 2026-08-23
- Decision owners: Maintainers after productization review

## Context

Phase 1 uses local Ed25519 signing and embeds trusted public-key material in
the release. The controller-integrated lifecycle persists patch, authority,
rollback, and recovery roles with trust generation, remembered artifact
identities, and patch high-water. It has no production KMS/HSM integration,
hosted custody, threshold approval, or provider authorization.

Product modes need developer, organization, CI, managed KMS/HSM, offline, and
air-gapped choices without allowing a hosted control plane or CDN to invent a
trust root. A signature authenticates the holder of a trusted key; it does not
prove semantic safety, store approval, rollout wisdom, or absence of a
compromised build.

## Decision

### Custody choices

| Choice | Private-key boundary | Suitable first use | Trade-off |
| --- | --- | --- | --- |
| Developer-managed | Local OS-protected or offline workstation; public key is registered with the exact release | OSS/local and small self-hosted workflows | Simple and provider-free; workstation compromise and key backup are the operator's responsibility |
| Organization-managed | Customer-controlled vault/HSM/offline signer; release roles and approvals are organization-owned | Team, enterprise, and on-prem | Stronger separation and audit; requires customer operations and recovery planning |
| CI-triggered | CI submits exact bytes/provenance to a signer; raw key is preferably non-exportable behind a signing API | Repeatable release automation | Short-lived CI credentials and provenance reduce exposure; a compromised pipeline can still request a legitimate signature |
| Managed KMS/HSM | Explicit opt-in provider-neutral adapter invokes a non-exportable, scoped key; control plane never stores key bytes | Managed cloud convenience | Centralized availability and provider risk; requires provider policy, approvals, residency, and recovery review |
| Offline/air-gapped | Offline signer holds the key and signs an export/import inventory or exact artifact bytes | Regulated or disconnected environments | Highest operational friction and strongest network separation; transfer media and operator process remain threats |

KMS/HSM is a custody class, not a provider decision. Future adapters may
target classes such as AWS KMS, Google Cloud KMS, Azure Key Vault, HashiCorp
Vault, or a customer HSM, but no provider is selected, integrated, or implied
by this ADR. The interface must expose only scoped sign/verify/public-key and
key-status operations; provider-specific APIs and credentials remain outside
the product protocol.

Private keys must not traverse the ordinary hosted control plane, appear in a
release/patch/debug artifact, or enter runtime telemetry. A product that offers
managed signing must state that it is an explicit custody choice, display key
scope and approval policy, and document what happens when the provider is
unavailable or compromised.

### Release-owned trust roles

The release embeds a bounded trusted public-key set. Roles remain separate:

- `patch` authenticates new Patch Format v1 artifacts and exact remembered
  artifacts allowed by the lifecycle policy;
- `authority` signs key add/retire/revoke transitions;
- `rollback` signs the separate release-bound rollback control;
- `recovery` is an offline/release-installed anchor that can replace one
  non-recovery key but cannot delegate, retire, revoke, or create another
  recovery anchor.

The exact role names and current state-v4 encoding remain owned by the existing
runtime/key-lifecycle model. Product metadata may describe a key and its
operator, but cannot add a key to runtime trust by itself. Downloaded public
keys are data until a currently trusted lifecycle command authorizes them.

### Rotation, revocation, and compromise

Normal rotation adds a replacement during an overlap window, moves new
artifacts to it, then retires the old key. Retirement rejects new artifacts
but may permit exact remembered artifacts when the runtime policy allows it.
Emergency revocation removes that retained use in the same durable trust
transition. Recovery uses the release-embedded anchor and preserves the
non-recovery role shape.

Every lifecycle command is canonical, signed, release-bound, monotonic in
trust generation, and committed with executable selection, high-water, and
replay metadata. A key compromise response therefore:

1. pauses distribution and records an incident;
2. revokes the affected key or artifact through the trusted lifecycle path;
3. retains high-water and remembered identities rather than deleting evidence;
4. restores behavior only with a newly signed higher-sequence patch or the
   exact authorized signed rollback-to-base control;
5. verifies the result offline/on the target deployment before promotion.

It must never lower high-water, reopen an old sequence, accept an equal-sequence
different digest, or turn a rollout record into a rollback command.

### Approvals and provenance

Two-person production approval, protected environments, security-manager
approval for key changes, CI service accounts, short-lived credentials, and
signed build provenance are policy options. They are recommended for managed
and enterprise modes but are not substituted for runtime verification and are
not implemented here. A provenance record should bind source/build graph,
tool/runtime/format versions, exact artifact digest, signer key ID, and
approvals without placing source snapshots or secrets in the runtime artifact.

## Alternatives considered

- **Hosted platform owns one global private key:** Easy to operate, but creates
  a catastrophic cross-tenant blast radius and undermines self-hosting/offline
  requirements.
- **Upload customer private keys to the control plane by default:** Simplifies
  workflow but creates unnecessary custody and insider exposure. Rejected;
  only an explicit managed-signing product may cross that boundary, and then
  it should use non-exportable key operations.
- **One key for patches, rollback, and lifecycle:** Reduces configuration but
  makes a content-key compromise a trust-management compromise. Rejected in
  favor of role separation.
- **Server-provided public keys or key IDs become trusted immediately:**
  Allows control-plane compromise to replace the root. Rejected; lifecycle
  commands and release-owned state remain authoritative.
- **Per-artifact offline signatures with no lifecycle/replay journal:** Simple
  cryptography but cannot express revocation, recovery, or retained-artifact
  policy safely. Rejected for the product boundary.

## Consequences and open implementation questions

This model supports OSS, self-hosted, managed, and air-gapped custody without
changing Patch Format v1 or capability v1. It imposes key inventory, backup,
rotation, recovery, approval, and incident-response work on each offering.
Provider-specific signing availability, HSM attestation, threshold schemes,
key residency, and customer recovery UX remain design/implementation
questions. No provider integration is implemented or promised.

Before production, validate protected key custody, direct device stale-byte
injection, power-loss recovery, operator separation, and an offline recovery
campaign. The current Phase 1D evidence is process/restart and fixture-level
only where stated; it does not establish those claims.

## References

- [Artifact distribution and trust architecture](../architecture/distribution-trust.md)
- [Productization threat model](../security/productization-threat-model.md)
- [Release-owned key lifecycle](../security/key-lifecycle.md)
- [Security architecture](../architecture/security.md)
- [Patch Format v1](../spec/patch-format-v1.md)
- [Phase 1D review](../history/reviews/PHASE_1D_REVIEW.md)
