# Phase 1C release-owned key lifecycle

Status: `CONTROLLER_INTEGRATED_HOST_MODEL`; no physical-device claim.

The implementation is [`key_lifecycle.dart`](../../experiments/patch_loading/lib/src/key_lifecycle.dart) and its focused tests are [`key_lifecycle_test.dart`](../../experiments/patch_loading/test/key_lifecycle_test.dart). This is a bounded policy model, not a replacement for the current E1 signature, compatibility, capability, or durable patch-state checks.

## Decision and boundary

`E1PatchController` now owns the single recoverable view containing the
release-bound `E1KeyLifecycleState`, `trustGeneration`, patch high-water,
artifact replay ledger, current/LKG selection, health, candidate boot lease,
and state generation. The two checksummed records retain their historical
`state-v3-a.json` and `state-v3-b.json` paths for compatibility, while the
integrated record is state version `4`.

The release baseline is supplied through `initialTrustState` when the release
has an explicit recovery anchor. The historical `trustedPublicKeys` map remains
a compatibility bootstrap: it creates a sequence-zero static baseline when no
explicit lifecycle state is provided, and that baseline deliberately has no
offline recovery anchor. After startup, the persisted lifecycle state and
replay ledger are authoritative; the controller does not maintain a second
mutable trust store. Patch Format v1, capability v1, and the existing
signature/compatibility verification order are unchanged.

## Trust anchors, roles, and states

An initial `E1KeyLifecycleState` is constructed from release-embedded public keys. It requires at least one active patch key, one active lifecycle authority, and one separate active recovery anchor. The model bounds the complete key set to eight records.

| Role | May do | Deliberate restriction |
| --- | --- | --- |
| `patch` | Authenticate newly delivered patch artifacts while active; authenticate exact remembered artifacts after retirement | Never signs lifecycle commands unless it also has `authority` |
| `rollback` | Describe a release-owned rollback-control signer for the eventual coordinator | This model does not alter the current rollback-control path |
| `authority` | Sign add, retire, and revoke commands while active | Cannot add or revoke a recovery anchor; the last active authority/patch path cannot be removed |
| `recovery` | Sign one atomic replacement of a non-recovery key | Installed with the release, cannot be delegated, retired, revoked, or combined with another role |

| State | New artifacts | Exact remembered artifacts |
| --- | --- | --- |
| `active` | Allowed when the key has `patch` | Allowed |
| `retired` | Rejected | Allowed only when the artifact identity is already in the bounded ledger |
| `revoked` | Rejected | Rejected |

Retirement is an overlap mechanism, not a revocation shortcut. A normal rotation adds the replacement key, moves new artifacts to it, and retires the old key. Emergency revocation removes even retained-artifact verification for that key.

## Signed state transitions

`E1KeyLifecycleCommand` is canonical JSON with a 16 KiB bound, version `1`, algorithm `Ed25519`, and the domain separator `hyfens-key-lifecycle-v1\0`. It signs:

- application and release IDs;
- the exact next command sequence (`current + 1`);
- the exact SHA-256 digest of the current lifecycle state;
- the operation and target/new-key fields; and
- the already trusted signer key ID.

The command carries new public bytes only for `add` and `recover`. The bytes are untrusted data until a signature from the current state authorizes the transition. Ordinary transitions require an active `authority` key. `recover` requires the release-embedded recovery anchor and atomically revokes the target while adding a replacement with exactly the target's non-recovery roles. A recovery command cannot create another recovery anchor.

The lifecycle state is canonical JSON with a 32 KiB bound. Its SHA-256 state
digest detects malformed or torn nested state, while the controller's outer
record checksum detects malformed or torn journal records. Neither is a MAC
against a local attacker who can rewrite both state and digest. The controller
commits trust generation, lifecycle state, replay metadata, executable
selection, and patch high-water through the same dual-copy transition; an
unrecoverable pair enters the existing recovery lock.

## Controller-integrated artifact anti-replay ledger

`E1ArtifactReplayLedger` is bounded to 64 remembered artifact identities and is
stored inside the controller's state-version-4 record. An identity contains the
release key ID, positive patch sequence, and lowercase SHA-256 digest of the
exact authenticated envelope/artifact bytes. It enforces:

- lower sequence: `stale`;
- equal sequence and different digest: `equivocation`;
- equal sequence and the active exact digest: `idempotent`;
- equal sequence after base rollback: `replayAfterRollback`;
- retired key not present in the ledger: `keyRetiredForNewArtifact`; and
- revoked key, unknown key, wrong release, or a missing/mismatched retained identity: rejection.

The ledger does not verify an envelope signature. The controller first runs
`E1SignedPatchEnvelope.verify` or the existing Patch Format v1 Ed25519 path,
decodes the E0 program, enforces exact release/build/function/signature/
receiver/capability compatibility, and only then creates
`E1VerifiedArtifactIdentity`. A valid old signature is not sufficient to bypass
a later lifecycle revocation.

## Controller integration invariants

The controller preserves the following order and ownership boundaries:

1. At release construction, provide an explicit `initialTrustState` when
   offline recovery is required. The embedded map and any explicitly supplied
   lifecycle keys must agree on public bytes; downloaded keys never bootstrap
   themselves.
2. On startup, decode and validate both release-bound state copies, including
   trust generation and replay metadata. A malformed pair, predecessor gap,
   trust regression, or high-water regression enters the existing recovery
   barrier; it never reconstructs a trust set or sequence from artifact files.
3. For an incoming envelope, preserve the existing order: bounded framing,
   active lifecycle-key lookup, Ed25519 verification, release/build
   compatibility, E0/Patch Format v1 decoding, and capability validation.
   Only after those checks does the controller admit the exact artifact
   identity into the integrated ledger.
4. Commit the accepted artifact, patch high-water, active target, trust
   generation, lifecycle state, and replay metadata through one dual-copy
   journal transition before publishing executable runtime state.
5. On restart or stored-target selection, reverify bytes and require an exact
   remembered ledger identity. Retirement permits only those recorded bytes;
   revocation rejects both new and retained use. Revoking the selected current
   artifact clears executable selection in the same durable transition while
   retaining high-water and remembered identities.
6. Rotation applies signed `add` and later `retire` commands; emergency
   response applies signed `revoke`; the offline recovery role applies a
   signed replacement command. Rollback remains a separate signed control
   message whose active lifecycle key and exact high-water are checked by the
   same persisted trust state.
7. Cleanup may remove immutable artifact files, but it must not remove the
   integrated state record or its remembered identities. A deleted old
   artifact therefore remains stale/revoked evidence rather than reopening a
   sequence slot.

This host implementation does not claim production key custody, KMS/HSM
support, threshold approval, server authorization, secure rollback of app data,
physical crash durability, or store-policy compliance.

## Validation evidence

The focused suites cover canonical state/command round trips, overlap
rotation, retirement, recovery, role separation, unknown-key
self-authorization, command replay/gaps, dual-copy faults, wrong-release
recovery, cleanup, rollback, and a cross-feature path where a valid
`E1SignedPatchEnvelope` is accepted before rotation, retained after
retirement, rejected as new, and rejected after revocation. Host timing
evidence is in [`phase-1c-performance.md`](../research/phase-1c-performance.md);
this document makes no physical-device observation.
