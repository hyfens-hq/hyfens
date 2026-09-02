# E1 Android patch loading

This package extends the narrow E0 data-bytecode experiment just far enough to
test an installed stock-Flutter Android release. It is not a production updater.

`E1PatchController` downloads only from `http://localhost` or
`http://127.0.0.1`. It verifies a deterministic Ed25519 envelope against public
keys embedded/configured by the app before decoding, staging, or installing the
exact canonical E0 bytes. It writes immutable content-addressed envelopes and
atomically maintains two checksummed release-bound state copies containing a
pending/healthy current candidate, prior last-known-good, and durable sequence
high-water. Lifecycle methods are serialized. Activation durably records
pending before runtime publication, and the app explicitly calls
`markHealthy()` after exercising it. A pending candidate left across restart is
automatically rolled back to last-known-good/base without lowering high-water.
Missing/corrupt anti-replay state with existing artifacts exposes
`recoveryNeeded` and blocks new activation.

The compiled release may also provide an `E1RuntimeConfiguration` containing
its immutable capability and widget-factory authorities. Every controller-owned
runtime reset reapplies those same objects before any stored patch is installed.
Authority is never inferred from or widened by downloaded bytes.

The offline CLI creates an Ed25519 seed/public-key pair and signs compiled E0
bytes. See [SPEC.md](SPEC.md) for the exact signed message, state transitions,
rollback rules, and additive key-rotation design.

`bin/e1.dart` reuses E0's analyzer-guided overlay and patch compiler with the
Flutter fixture identity. The checked-in `patches/price_patch.dart` is changed
normal Dart source. Its meaningful branches change standard, bulk, and tier-2
pricing. The generated overlay, manifest, source map, and bytecode remain
ephemeral under the fixture's `.dart_tool/e1_overlay/` directory.

Limits are deliberate and important:

- Authenticity is limited to possession of an app-trusted Ed25519 private key.
  SHA-256 remains integrity/content addressing and is never called authenticity.
- Key rotation requires shipping overlapping public-key trust in an app release;
  there is no KMS, hosted signer, online revocation, or trust-policy service.
- The interpreted subset is only two integer arguments, integer return values,
  arithmetic, equality/comparison, branches, and returns. No arbitrary Dart,
  widget hierarchy, async, plugin, FFI, isolate, or platform-channel patching is
  claimed.
- There is no downloaded native code and no unrestricted host capability API.
- Mounted Flutter `State`, controller, element, and scroll continuity is a
  consequence of rebuilding the existing keyed widget tree. E1 does not migrate
  State object layouts or patch arbitrary `StatefulWidget` methods; an app/tree
  restart constructs fresh State and controllers as normal.
- "healthy" means the patch validated, installed, and allowed the app to render;
  crash-loop health confirmation is not implemented.
- One local recovery generation is retained. Delivered rollback requires a
  newly signed higher-sequence artifact; old signed bytes remain stale. Garbage
  collection and multi-generation recovery are outside E1.
- Redirects are disabled, even from the permitted localhost origin.
- Cleartext traffic is enabled in this experimental APK solely for adb-reversed
  localhost delivery. The loader rejects non-local hosts.

Run `scripts/e1_android_physical.sh DEVICE_SERIAL` from the repository root for
the reproducible release/device proof. It installs once and refuses ambiguous or
emulated device targets.

The public support boundary is summarized in the
[Dart and Flutter support matrix](../../docs/dart-support-matrix.md). Raw
device logs/XML are intentionally ephemeral under
`.dart_tool/device-evidence/`.
