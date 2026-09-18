# Patch Format v1

Status: normative Phase 1A protocol specification.

Patch Format v1 is a deterministic binary container for a single bounded
function patch. The format is future-facing public protocol surface; changes
after Phase 1 must use an explicit format version.

## 1. Encoding

All integers are unsigned big-endian unless a section says otherwise. Strings
are strict UTF-8 prefixed by a 32-bit byte length. Lists are prefixed by a
32-bit element count. A patch is a sequence of sections:

```text
magic[8]        = ASCII "HYFENSP1"
formatVersion   u16 = 1
headerFlags     u16 = 0 (reserved; non-zero is rejected)
runtimeVersion  u32
sectionCount    u16
section...      sectionCount records
```

Each section is:

```text
sectionType     u16
sectionFlags    u16 (bit 0 = critical)
payloadLength   u32
payload         payloadLength bytes
```

Known section types are:

| Type | Name | Required | Contents |
| ---: | --- | --- | --- |
| 1 | identity | yes | application ID, release ID, patch ID, sequence, optional UTC timestamp |
| 2 | functions | yes | sorted function IDs, slots, exact signature digests |
| 3 | capabilities | yes | sorted capability IDs, versions, execution/policy/schema records |
| 4 | constants | yes | bounded typed constant/data values |
| 5 | instructions | yes | bounded non-negative instruction words |
| 6 | signature-metadata | yes | algorithm and key ID |
| 7 | payload-digest | yes | SHA-256 digest of canonical unsigned payload sections |
| 8 | signature | yes | algorithm-specific signature bytes |

The canonical section order is ascending type. Each known section occurs once.
Unknown non-critical sections may be skipped by a future reader. Unknown
critical sections are rejected. A reader rejects a format version it does not
implement; runtime compatibility is checked independently against the shipped
runtime version.

## 2. Identity and compatibility

The identity section contains:

- `applicationId`: stable application identifier;
- `releaseId`: immutable release baseline identifier;
- `patchId`: immutable patch identifier;
- `sequence`: positive monotonic activation sequence;
- `createdAtUtc`: optional signed timestamp in milliseconds since Unix epoch.

A patch is valid only for the exact application/release pair. Package names,
dependency versions, and human-readable labels are not release identity. The
release identity input is derived from normalized source/dependency
fingerprints, runtime compatibility, application ID, and an explicit build
target such as `android-arm64-release` or `ios-arm64-release`.

The function table records a stable function ID, dense release slot, and exact
signature digest. A signature digest covers return schema, async marker,
parameter order/names/kinds/defaults, and receiver descriptor.

## 3. Capabilities and payload

The capability table declares every host operation required by the patch. Each
record includes a stable capability ID, positive version, execution kind
(`sync` or `async`), security class, canonical argument schema, and canonical
return schema. The runtime resolves declarations only against the immutable
release-owned authority.

Constants use a bounded tagged value grammar: null, bool, signed int, finite
double, UTF-8 string, list, and string-keyed map. Instructions are opaque to
the container but are bounded and verified by the runtime before execution.

## 4. Digest and signature

The canonical unsigned payload is the exact header and canonical known
sections of types 1–6 plus any sorted unknown non-critical extension sections,
with no digest/signature sections. `payload-digest` is SHA-256 over those
bytes. The signature input is the exact canonical header and those payload
sections plus type 7, with the signature section omitted. Signature metadata
and non-critical extensions are therefore authenticated by the signature. The
final artifact appends the signature section in canonical order.

Phase 1A uses the algorithm label `ed25519` with a 32-byte key ID encoding
policy defined by the signing package; the container does not embed private
keys. Unknown algorithms are rejected by the configured signer/verifier.

## 5. Bounds and rejection

The reference implementation enforces:

- 4 MiB maximum artifact size;
- 32 sections and 1 MiB maximum per section;
- 256-byte maximum identity/key strings;
- 4,096 function/capability/constant entries;
- 65,536 instruction words;
- 16 nesting levels, 1,024 collection entries, and 64 KiB strings;
- exact section lengths, no trailing bytes, no duplicate IDs, sorted canonical
  tables, and no negative or non-finite values.

Malformed lengths are checked before allocation. An unknown critical section,
duplicate section, incompatible version/runtime, non-canonical re-encoding,
digest mismatch, or invalid signature is a hard rejection and cannot alter
the active patch.

## 6. Evolution

Minor additive data can use unknown non-critical sections. Any change to the
meaning, ordering, encoding, bounds, digest/signature boundary, or required
fields requires a new format version. A future reader must not guess at a
critical field. Runtime compatibility is a separate versioned contract and is
never inferred from format version alone.
