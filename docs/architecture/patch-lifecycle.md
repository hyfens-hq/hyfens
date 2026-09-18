# Patch lifecycle

Status: Phase 1A implementation baseline.

```text
Flutter application
       ↓
instrumentation
       ↓
release baseline + manifest
       ↓
source changes
       ↓
patch analyzer/compiler
       ↓
compatibility verifier
       ↓
signer
       ↓
Patch Format v1 artifact
       ↓
runtime verification and staging
       ↓
atomic activation / health / last-known-good
```

Phase 1A implements the protocol and runtime-facing parts of this lifecycle.
Phase 1B adds the local `tool init`, automatic project discovery, release
orchestration, change analysis, and `tool patch` commands. Physical delivery
and runtime activation of CLI-generated artifacts remain explicit validation
work rather than an implicit claim.

## Baseline

A release baseline records the immutable release ID, application ID, runtime
and format compatibility versions, sorted function identity/signature records,
capability authority digest, participating logical packages, instrumentation
selection, and build-graph fingerprint. It does not include source snapshots
or unnecessary secrets. Source snapshots are not required by the current
representative compiler; a later analyzer may request a minimal source cache
only when a changed declaration cannot otherwise be reconstructed safely.

## Patch creation

A patch is generated from normal source changes, matched against one baseline,
and rejected if any changed target is unsupported or any dependency/native
boundary invalidates the baseline. The compiler emits deterministic instructions
and metadata. The protocol digest covers the canonical unsigned payload; the
signature covers the canonical payload plus its digest and signature metadata.

The canonical artifact model and baseline manifest are implemented in
`packages/patch_format`. The public compiler and instrumenter seams are in
`packages/compiler` and `packages/instrumenter`. The Phase 1B CLI wires the
verified E0 container into a non-critical v1 bridge extension while retaining
the normative v1 sections and signing boundary. Runtime activation of that
bridge is not yet claimed.

## Activation and rollback

The runtime verifies size, canonical bytes, digest, signature, release/runtime
compatibility, function signatures, capability authority, sequence, and
resource bounds before staging. Staging uses a temporary artifact and an
atomic activation record. A candidate becomes last-known-good only after the
configured health confirmation. Explicit developer rollback is represented by
a newly signed higher-sequence artifact; an attacker-provided older patch is a
downgrade and is rejected.
