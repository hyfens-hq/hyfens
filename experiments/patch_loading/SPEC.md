# Signed patch and rollback contract

## Trust and signed bytes

Task 15 uses the explicit pure-Dart `DartEd25519` implementation from
`package:cryptography` 2.9.0. The package is
published by the verified `dint.dev` publisher, supports Dart's target
platforms, includes a pure-Dart Ed25519 implementation, and is Apache-2.0
licensed. The older `ed25519_edwards` candidate was rejected because its latest
release is four years old and its uploader is unverified.

Package evidence: [cryptography 2.9.0 on pub.dev](https://pub.dev/packages/cryptography/versions/2.9.0)
and the [upstream Apache-2.0 repository](https://github.com/dint-dev/cryptography).

The application is built with one or more trusted public keys. Each key is 32
bytes and is selected by a non-secret `keyId`; downloaded material cannot add a
trusted key. Private 32-byte seeds remain offline and are used only by the local
CLI. This experiment does not provide KMS or hosted signing.

Envelope v1 is canonical UTF-8 JSON with exactly these fields:

```json
{"algorithm":"Ed25519","envelopeVersion":1,"keyId":"release-2026-a","patch":"BASE64","signature":"BASE64"}
```

The signed message is the ASCII/UTF-8 domain separator
`hyfens-signed-patch-v1` plus a zero byte, followed by canonical JSON containing
`algorithm`, `envelopeVersion`, `keyId`, and `patch`, with `signature` omitted.
The `patch` value is canonical base64 of the exact E0 v8 bytes. Thus the
signature covers the exact canonical bytecode container and all metadata inside
it, including app, release, build fingerprint, and sequence, without a circular
signature field.

The loader parses only the bounded outer framing and canonical base64 needed to
select a trusted key and verify Ed25519. It verifies the signature before E0
decoding, sequence evaluation, disk staging, or runtime installation. SHA-256
names immutable files and compares equal candidates; it is not authenticity.

## Durable state and transitions

The controller stores one integrated state-v4 journal in two canonical,
checksummed copies, `state-v3-a.json` and `state-v3-b.json` (the filenames are
retained for compatibility). Each copy is atomically written through a sibling
temporary file and rename. Both are bound to `appId` and `releaseId` and store:

- durable high-water sequence and the accepted envelope digest at that sequence;
- a monotonically increasing state generation;
- current signed envelope and its `pending` or `healthy` status;
- the prior confirmed last-known-good reference, where null means base AOT.
- the release-owned trusted/retired/revoked key state and trust generation;
- the exact remembered artifact identities and active artifact digest.

A higher valid sequence copies caller bytes before any await, verifies the
immutable copy, stages/repairs its content-addressed artifact, commits a pending
record to both state copies, and only then publishes it to the runtime. All
initialize, activation, health confirmation, recovery, and rollback operations
run through one asynchronous queue. The application must call `markHealthy()`
after exercising a pending candidate. A lower sequence is stale. At an equal
sequence, the same healthy current digest is idempotent and revalidates/repairs
its artifact; a different digest is equivocation. Invalid signatures, malformed
envelopes, incompatible bytecode, install errors, partial downloads, and failed
state writes restore the prior runtime/state and do not advance high-water.

Startup chooses the newest consistent checksum-valid copy and repairs a missing,
torn, or one-generation-stale peer. Equal-generation disagreement or a larger
predecessor gap is recovery-needed. If both copies are missing/corrupt while
signed artifacts exist, the loader fails safe to base, exposes
`recoveryNeeded`, and blocks new activation rather than resetting replay state.
A fresh empty directory is the only implicit sequence-zero state.

Startup never promotes pending to healthy. It automatically rolls an unconfirmed
candidate back to the verified prior last-known-good or base while retaining
high-water. Stored signatures and E0 compatibility are reverified before every
publication. `recoverFromRuntimeException` provides the same local recovery
path. This local recovery does not make old downloaded bytes eligible again.

Manual `rollback()` resets to trusted base AOT and retains high-water. Restoring
earlier patch behavior through delivery requires recompiling that behavior with
a sequence above high-water and signing the new canonical bytes. An old signed
artifact is never accepted as a network rollback.

Every E1-owned reset clears installed guest code, then reapplies only the
immutable `E1RuntimeConfiguration` supplied by the compiled release. This
includes capability and widget-factory registries when present. Fallback,
recovery, rollback, and restore paths use the same reset operation, so they
cannot silently lose or broaden host authority.

## Key rotation and recovery

An explicit release baseline may contain active authority, patch, rollback, and
offline recovery roles. A signed `add` command establishes an overlap key in
the persisted trust state; higher-sequence artifacts can then use it. A signed
`retire` command rejects new artifacts under the old key while retaining exact
remembered artifacts. A signed `revoke` rejects both new and retained use and
clears a current or last-known-good artifact signed by that key in the same
durable transition. The recovery role can atomically revoke a target and add a
replacement with the target's non-recovery roles.

Key lifecycle state, trust generation, artifact replay metadata, executable
selection, and sequence high-water are committed through the same controller
journal. A rollback clears executable selection without lowering high-water;
cleanup of artifact files does not delete remembered identities. The
historical constructor that accepts only `trustedPublicKeys` creates a
sequence-zero compatibility baseline without an offline recovery anchor; a
release requiring offline recovery supplies `initialTrustState` explicitly.
Patch Format v1 and the capability contract are unchanged.

## Offline CLI

```sh
dart run bin/e1.dart keygen private-seed.hex public-key.hex
dart run bin/e1.dart sign patch.e0.json private-seed.hex release-2026-a patch.e1.signed.json
```

Key generation canonicalizes and distinguishes its paths, refuses overwrite,
creates the seed inside a private mode-0700 temporary directory, checks mode
0600 on the seed, and only then renames it to its destination. Signing requires
distinct canonical patch/seed/output paths, refuses overwrite, checks the patch
size before reading it, writes through a temporary file and rename, and cleans
temporary output on failure. The public key and key ID must be
embedded/configured in the target app.

Patch HTTP delivery disables redirects. The initial URI and its host must be
local adb-reversed HTTP; a localhost redirect is rejected rather than followed.

The loader API takes public material only:

```dart
final trustedKey = E1TrustedPublicKey(
  keyId: 'release-2026-a',
  bytes: embedded32BytePublicKey,
);
final controller = E1PatchController(
  // Release identity, compatibility tables, storage, and URI omitted.
  trustedPublicKeys: {trustedKey.keyId: trustedKey},
);
```

Never embed a private seed in an application. RFC/test keys are suitable only
for tests; a physical local experiment should inject its locally generated
public key into that experiment build and keep its private seed off-device.
