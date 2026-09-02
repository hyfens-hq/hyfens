# Phase 1B rollback and cleanup boundary

Status: Phase 1B implementation boundary; local and experimental.

Rollback is a lifecycle control operation. It does not change Patch Format v1,
carry code, add capabilities, or lower the runtime's patch high-water.

## Runtime lifecycle

The E1 controller persists a release-bound state record in the application
support directory. The implementation uses two checksummed state copies and
atomic temporary-file/rename writes. The externally useful states are:

| State | Meaning | Transition |
| --- | --- | --- |
| `BASE` | The store-installed AOT code is active and no patch is current. | Initial state, failed candidate recovery, or authorized base rollback. |
| `CANDIDATE` | A signed, release-compatible patch has been staged, installed, and is awaiting `markHealthy`. | A verified patch is committed with `health=pending`; it cannot be replaced before health confirmation. |
| `CURRENT` | The signed patch is active and health-confirmed. | `markHealthy` commits the candidate as healthy. |
| `LAST_KNOWN_GOOD` | The prior healthy patch retained while a newer candidate is pending. | It is restored if startup or runtime recovery rejects the candidate. |
| `FAILED` | Durable state or recovery could not be trusted. | Activation and further changes are locked until deliberate recovery. |

The internal record stores `current`, `health`, `lastKnownGood`, generation, and
the accepted patch high-water `(sequence, digest)`. A candidate becomes
current in the durable record before runtime publication, but remains
`pending` until health confirmation. On restart, an unconfirmed candidate is
restored to last-known-good or to the AOT base. The high-water is retained in
both cases.

## Authorized base rollback

The developer-facing command is:

```bash
tool rollback --release <release-id> --to base
```

The CLI requires a non-metadata release whose immutable store artifact remains
under `.tool/releases/<release-id>/artifacts/`. It reads the current high-water,
creates a separate canonical, signed rollback-control JSON message, commits a
checksummed host journal, and writes the control message atomically. The
private key is used only by the CLI; the application release contains the
trusted public key.

The control message is served by the development-only `/v1/control` endpoint.
The runtime accepts it only when all of the following match:

- command version and canonical encoding;
- trusted Ed25519 key ID and signature;
- application ID and release ID;
- the exact durable high-water sequence and patch digest.

After verification, E1 resets the interpreted runtime, clears current and
last-known-good patch selection, commits `BASE`, and retains the high-water.
The physical Android and iOS workflows both demonstrated activation, restart,
signed base rollback, and restart after rollback.

The control message is deliberately separate from Patch Format v1. Patch
Format v1's canonical encoding, digest/signature boundary, fields, and
semantics are unchanged. Selecting an older patch is not exposed: doing so
would require a new authenticated higher-sequence control/artifact protocol.
An old patch file therefore remains stale evidence and cannot be replayed
after rollback.

This is an explicitly authorized developer operation, not an attacker-provided
downgrade path. A malformed, wrong-release, wrong-key, stale-high-water, or
replayed control is rejected and leaves the current state unchanged.

## Cleanup

Cleanup requires a narrow scope, one exact release ID, and repetition of that
ID as confirmation:

```bash
tool cleanup --scope builds  --release <release-id> --confirm <release-id>
tool cleanup --scope patches --release <release-id> --confirm <release-id>
```

`builds` removes only the exact temporary `.tool/.builds/<release-id>`
directory. `patches` is available only after an explicit base rollback and
removes only numbered patch files and the matching rollback-control file in
that exact release directory. It retains `sequence.json`, both rollback
journals, the immutable release directory, keys, source, and evidence, so
future patch numbering and replay protection continue above the same
high-water.

The controller's content-addressed patch files follow the same rule: removing
an old artifact does not remove its remembered `(keyId, sequence, digest)`
identity from the integrated state journal. Trust state, trust generation,
current/LKG selection, and patch high-water are never cleanup targets.

The following scopes are rejected: `all`, `evidence`, `keys`, `releases`, and
`source`. Cleanup never follows symlinks. Missing or mismatched confirmation,
malformed release state, a missing trusted AOT artifact, and unsafe filesystem
targets fail closed with stable `R6001`–`R6007` or `C7001`–`C7006` diagnostics.

The host boundary does not claim OS-level crash/power-loss durability or expose
prior-patch selection. Controller tests cover deterministic state-copy faults,
signed key rotation/revocation, and anti-replay after cleanup and base
rollback.

## Phase 1C review addendum

Phase 1C adds deterministic controller boundary hooks and integrates the
release-owned key-lifecycle policy into the same `E1PatchController` journal as
high-water and executable selection. Signed add/retire/revoke/recovery
transitions, dual-copy repair, cleanup retention, and stale replay are covered
by host tests. Patch Format v1, the rollback-control encoding, and the
capability contract remain unchanged. OS-level power-loss testing and
prior-patch selection remain outside the current validated boundary.
