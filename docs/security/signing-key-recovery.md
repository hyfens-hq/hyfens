# Customer/local signing-key recovery boundary

Status: bounded P2 procedure; not a managed KMS/HSM or production recovery
guarantee

Hyfens keeps patch-signing authority with the customer or local release
operator. The control plane stores release public-key metadata and signed
artifacts, but it must not receive or regenerate private signing keys. The
runtime remains the authority for signature, release, capability, sequence,
and rollback checks.

## Normal custody

1. Generate the Ed25519 key pair on an operator-controlled workstation or
   offline signing host.
2. Keep the private key outside the repository, control-plane database, object
   store, logs, backups, and device application storage.
3. Record the public key and key ID in the immutable release metadata before
   distributing the release.
4. Sign the canonical Patch Format v1 bytes locally, verify them locally, and
   upload only the signed bytes and public metadata.
5. Protect the private key with the operator's existing encrypted backup and
   access-control process. The P2 stack does not implement escrow, managed
   rotation, HSM integration, or automatic recovery.

## Loss of a private key

The private key cannot be reconstructed from a public key, patch, PostgreSQL
backup, object backup, or installed application. If the private key is lost,
the existing immutable release can no longer receive newly signed patches from
that key. Recovery requires an operator-approved new trust boundary, normally
a new store release carrying a replacement public key, followed by a new
release-bound patch sequence. Do not copy a replacement key into the old
release or silently rewrite stored artifacts.

## Suspected compromise

1. Stop issuing patches with the suspected key and preserve the key ID,
   release ID, artifact digests, audit export, and incident timeline.
2. Do not delete evidence or regenerate an artifact with the same identity.
3. Decide whether the immutable release must be withdrawn or replaced. A
   patch-service credential can be revoked, but that does not revoke a public
   key already trusted by an installed immutable runtime.
4. Ship a new store release with a replacement public key and an explicit
   trust transition, or remove the affected release from delivery while the
   replacement is reviewed. The exact transition protocol is a future
   product/security decision and is not implemented by P2.
5. After the new release is installed, rotate delivery/control credentials,
   reconcile metadata and object bytes, and retain the old signed evidence for
   audit.

## Production trust-transition decision

The P2 production position is **Option A: a new store release is required for
signing-key replacement**. A separately designed signed trust-transition
protocol is not implemented or assumed. An immutable installed release cannot
be made to trust a replacement public key by changing hosted metadata.

Keep these compromise classes separate:

- **Control-plane credential:** revoke or expire it server-side and issue a
  replacement scoped credential.
- **Read-only delivery credential:** revoke or expire it server-side; an
  already verified local runtime state remains usable offline.
- **Patch-signing key:** hosted revocation cannot remove a public key embedded
  in an immutable installed release. Use the approved new-store-release
  trust transition and preserve the old incident evidence.

## Backup and restore boundary

PostgreSQL metadata and digest-addressed object bytes are backed up and
restored as coupled inputs. A restored database without its matching object
bytes must remain non-ready for artifact delivery or quarantine the affected
artifact; it must never regenerate or re-sign a patch. Restore tests verify
the byte digest and local signature before delivery is resumed.

## What this procedure does not prove

- availability of a second signing operator or offline escrow;
- production HSM/KMS controls, quorum approval, or key rotation automation;
- revocation of a public key already embedded in an immutable store release;
- App Store or Google Play acceptance of any recovery or update strategy;
- recovery from true physical power loss or a fully compromised device.

These remain production/security gates. See the Phase 1D condition register
and `docs/P2_MANAGED_CLOUD_REVIEW.md` for the current disposition.

## Task 46 reaffirmation (2026-08-23)

The external-gates continuation made no signing or trust-boundary change and
performed no production-key ceremony. Option A remains authoritative: replacing
an immutable release's patch-signing trust requires a new store release.
Control-plane and read-only delivery credential revocation remain server-side
operations; neither can revoke the public key embedded in an installed app.

## Task 47 disposable ceremony evidence (2026-08-23)

No production secret was used. A disposable RFC 8032 Ed25519 seed was used to
exercise the local ceremony and the already embedded release trust boundary:

- deterministic signed Patch Format v1 bytes were generated and verified
  offline;
- a batch artifact carrying three release-owned function slots was accepted
  by host preflight and by both physical fixture runs;
- an artifact with an untrusted key ID was rejected before activation;
- a byte-tampered artifact was rejected by the payload digest check while the
  prior healthy candidate remained active;
- focused lifecycle tests passed authority rotation/recovery, unknown-signer
  rejection, wrong-key/tampered/malformed input handling, high-water/replay
  rules, rollback, and recovery fault isolation.

The offline CLI keygen/sign round-trip test was attempted separately but
exceeded the harness's 30-second subprocess window. It is recorded as
`ENVIRONMENT_GATED`, not as a pass. The Ed25519 vector/envelope tests and
bounded CLI alias/overwrite/oversized-input tests passed. No KMS/HSM, escrow,
second-operator ceremony, or in-place trust replacement was introduced.

This evidence does not change Option A: loss or compromise of the patch
signing key still requires stopping/containing issuance, preserving evidence,
and shipping a new store release with a replacement trusted public key.

## Task 48 CLI timeout classification (2026-08-23)

The offline keygen/sign round-trip was rerun with the test harness boundary
made explicit. Direct key generation and signing exited normally in 10.91s and
9.98s; the focused round-trip passed in 37.81s and the complete signing test
passed 4/4 in 83.14s. The result is classified **`SLOW BUT CORRECT`**: the
earlier 30-second observation was host subprocess-startup variance at the
harness boundary, not a CLI defect or subprocess leak. See
[`../research/p2-cli-signing-timeout-2026-08-23.md`](../research/p2-cli-signing-timeout-2026-08-23.md).

The explicit two-minute test timeout does not change the production signing
boundary. Customer/local private-key custody, recovery, rotation, and
availability remain security/provider gates.
