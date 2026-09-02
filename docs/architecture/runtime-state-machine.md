# E1 runtime state machine

Status: Phase 1C lifecycle hardening; Architecture B remains the runtime
baseline.

The lifecycle controller is the authority for downloaded execution. The
compiled AOT program remains the fallback for every state. Patch bytes never
configure host capabilities, widget factories, or any other authority.

## States

```text
                 verified artifact + durable pending record
 BASE ──────────────────────────────────────────────────────▶ CANDIDATE
  ▲                                                           │
  │                       markHealthy                         │
  │                                                           ▼
  └────────────── fallback / authorized base rollback ◀──── CURRENT
                         runtime recovery
```

`FAILED` is a recovery barrier rather than an executable state. It is selected
when neither durable copy can be trusted, copies disagree in a way that could
hide replay state, or a transition cannot restore its exact prior state. The
controller resets to the AOT baseline in memory and rejects activation until a
future deliberate recovery operation establishes trusted durable state.

| State | Durable meaning | Runtime rule |
| --- | --- | --- |
| `BASE` | `current` and `lastKnownGood` are null. The authenticated high-water is retained. | Run only compiled AOT code. |
| `CANDIDATE` | `current` names a verified immutable artifact, `health=pending`, and `lastKnownGood` is the prior healthy artifact or null for base. | The candidate may run only after its pending record is durable; health must be confirmed explicitly. |
| `CURRENT` | `current` is health-confirmed. `lastKnownGood`, when present, is the prior confirmed artifact. | Re-verify the stored artifact before installation. |
| `FAILED` | Durable authority is unavailable or unsafe to select. | Keep downloaded slots disabled and fail closed. |

The two checksummed files are `state-v3-a.json` and `state-v3-b.json`. Their
generation increases on every state commit. The state-version-4 record also
contains the exact release-bound identity, current health, content digest,
monotonic high-water `(sequence, digest)`, trusted/retired/revoked key state,
trust generation, and the bounded artifact replay ledger. The filenames remain
v3 for storage-path compatibility. `candidateBootAttempts` is `1` only for a
pending candidate and `0` otherwise; it makes the one-attempt boot lease
explicit while remaining compatible with older records that did not contain
the field.

## Invariants

The controller validates these invariants before accepting a durable record or
writing a new one:

1. The release identity is exact, generation and sequence are non-negative,
   and sequence zero has no digest while every positive sequence has a
   lowercase SHA-256 digest.
2. `BASE` has no current or LKG reference. `CANDIDATE` and `CURRENT` have a
   valid content-addressed current reference. Current and LKG are never the
   same reference.
3. A pending candidate has exactly one candidate boot attempt. Startup never
   retries it: it installs the verified LKG or resets to AOT, then commits the
   fallback while retaining high-water. This bounds a candidate crash loop to
   one process attempt.
4. A transition that changes executable selection does not lower high-water.
   Recovery and base rollback may select an older artifact or AOT, but old
   signed bytes remain stale for network activation.
5. At equal high-water, a different digest is equivocation. A lower sequence
   is stale. An equal digest is idempotent only when it is still the durable
   current target; rollback or recovery never reopens an old target.
6. Trust generation equals the signed lifecycle command sequence. Key bytes
   and roles are release-bound, lifecycle transitions are monotonic across
   copies, and a revoked key cannot remain current or last-known-good.
7. Every stored target is an exact remembered artifact identity. The ledger,
   executable selection, and high-water must agree in the same state record;
   cleanup may remove bytes but never removes replay metadata.

## Dual-copy selection and repair

Startup reads and validates both copies before publishing any downloaded code.

- With no files and no patch artifacts, it creates sequence-zero `BASE`.
- One valid copy repairs a missing, malformed, or one-generation-stale peer.
- Two valid copies select the greatest generation only when the generations are
  equal or adjacent, equal generations have identical canonical bytes, and the
  newer copy does not lower or replace the older copy's high-water, trust
  state, or remembered replay identities.
- A predecessor gap, equal-generation disagreement, cross-copy trust
  regression, or cross-copy high-water/replay regression enters `FAILED`. The
  loader does not guess which trust or replay state was intended.
- If both copies are missing or malformed while patch artifacts exist, it
  enters `FAILED`; artifacts cannot reconstruct the high-water.
- Temporary files are never state authority. Artifact files are immutable and
  content-addressed; a damaged artifact is rejected and never silently
  substituted.

State writes use a temporary sibling, flushed write, rename, and readback.
The backup copy is written before the primary copy, so an interrupted commit
leaves either the previous complete generation or a recoverable adjacent
generation. If a transition cannot establish or restore a trusted record, the
runtime is disabled and the controller reports `recoveryNeeded`.

## Activation, health, and recovery

For a verified sequence above high-water, the controller copies the caller
input, verifies the signature and E0/Patch Format bridge, admits the exact
artifact identity to the integrated replay ledger, stages the immutable
artifact, and commits `CANDIDATE` before runtime publication. A failed runtime
publish restores the exact prior record and runtime; if that restoration is
not possible, it enters `FAILED`.

`markHealthy()` is accepted only for the exact pending current. It commits
`CURRENT` and clears the candidate boot lease. It cannot be called for base or
an already healthy current, and a pending candidate cannot be replaced by a
second download.

At startup, a pending candidate is never promoted to healthy. The controller
selects and verifies LKG, or selects AOT when LKG is absent or invalid. A
runtime exception follows the same fallback path. If current is corrupt or
missing, recovery uses LKG/base and retains high-water. The abandoned artifact
may remain as evidence, but its old sequence is not eligible for activation.

## Rollback and anti-replay

Manual or signed developer base rollback resets the interpreted runtime and
commits `BASE` without changing high-water. A signed rollback command is
release-bound, key-verified, and must match the exact durable high-water. It
cannot make an old artifact current. Restoring old behavior therefore requires
a newly signed artifact above the retained high-water.

The lifecycle queue serializes initialization, activation, health, recovery,
rollback, and signed key-lifecycle commands. Runtime resets always reapply the
immutable release-owned authority before a stored patch is installed,
preserving Architecture B's host/guest boundary. Retirement only permits
exact remembered artifacts; revocation removes a selected current/LKG target
in the same trust journal transition while retaining high-water.

## Fault-injection boundary

`E1PatchControllerTestHooks.durableBoundary` is a deterministic test seam for
artifact and state durable points: before/after flush, before/after rename,
and state-copy readback. The older `beforeStateCopyWrite` seam remains
available. These hooks are test-only control points; no production crash or
filesystem durability guarantee is inferred from them. Lifecycle tests use
them to exercise torn writes, trust-command commit/repair, pending fallback,
exact prior-state restoration, and replay-preserving recovery.

## Phase 1D physical evidence note

The coordinator's Phase 1D Android and iOS runs observed the state-v4 model
through automatic release/patch activation, health confirmation, process
restart, signed base rollback, and retained sequence high-water. Android also
provided generated runtime status logs; iOS state-v4 copies were inspected
through the private app-support container because the runtime log/UI channel
was unavailable. These are process/restart observations only; they do not
claim physical power-loss durability.
