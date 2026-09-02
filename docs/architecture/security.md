# Security architecture

Status: Phase 1A implementation baseline; not a production threat-model
replacement.

Patches are untrusted input even when signed. The trust model authenticates an
authorized patch producer; it does not make the program safe. Safety comes
from strict parsing, canonical bytes, exact release binding, closed
capabilities, bytecode verification, and resource budgets.

## Trust boundaries

- the signed artifact is outside the application trust boundary until verified;
- the release baseline and shipped capability authority are application-owned;
- the interpreter can access only typed copied values and explicitly declared
  capability adapters;
- raw reflection, arbitrary host objects, MethodChannel enumeration, FFI,
  native binaries, and filesystem paths are unavailable to guest code;
- local patch delivery is a development transport and is not treated as a
  production authenticated service.

## Required checks

The format/runtime reject malformed UTF-8 or binary data, duplicate sections,
unknown critical sections, incompatible versions, wrong application/release,
unknown functions, signature or capability mismatches, invalid jumps/opcodes,
oversized collections, excessive instructions/call depth, and stale sequence
numbers. Structural decoding and canonical/digest checks happen before
staging or activation; signature verification is the next boundary before the
decoded artifact is trusted. The reference contracts are in
`packages/patch_format` and `packages/runtime`.

## Key lifecycle boundary

Phase 1A keeps signing local and offline. The stable protocol carries a key ID,
algorithm metadata, and signature bytes. Trusted-key configuration, rotation,
retirement, and revocation are release-owned local state. The E1 controller
persists that lifecycle state, its trust generation, exact remembered artifact
identities, executable selection, and patch high-water in one dual-copy
journal. Private keys are never embedded in the application binary. KMS,
hosted custody, accounts, and production delivery are explicit non-goals.
