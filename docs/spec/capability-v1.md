# Capability Contract v1

Status: Phase 1A implementation specification.

Capabilities are the only host operations available to a patch. A capability
is a release-owned contract, not a reflective name lookup.

## Contract

Each capability contains:

- a stable dotted ID such as `http.get` or `flutter.widget.text`;
- a positive contract version;
- canonical argument and return schemas;
- execution kind: `sync` or `async`;
- security class: `pure`, `ui`, `network`, `storage`, `navigation`, `device`,
  `sensitive`, or `nativeBoundary`;
- a sorted permission label list.

`PatchCapabilityEntry` in `packages/patch_format` is the wire contract.
`CapabilityAuthority` in `packages/runtime` is the immutable release-owned
registry and policy boundary.

## Activation and invocation

The patch declares every required capability. Runtime activation rejects a
missing ID, version/schema mismatch, duplicate declaration, forbidden class,
or denied ID. Invocation copies arguments, applies the registered validator,
enforces byte limits, invokes the fixed adapter, and validates the result.
Synchronous contracts may not return a Future. Asynchronous contracts return a
bounded Future and retain the authority selected for that invocation.

The registry never enumerates arbitrary host APIs. Adding or changing a native
boundary requires a new store release; a data patch cannot add native code or
an unshipped adapter.

## Evolution

Changing a schema, execution kind, classification, or permission set is an
incompatible contract. Publish a new capability version and keep the old
adapter only while the release supports it. Runtime compatibility is separate
from Patch Format version compatibility.
