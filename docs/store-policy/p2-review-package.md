# P2 store-policy maintainer/legal review package

Status: prepared for review; not approval or legal advice

<!-- markdownlint-disable MD013 -->

## Runtime summary

Hyfens keeps a stock Flutter release and instruments selected ordinary
application Dart functions at build time. A later signed Patch Format v1
artifact contains data/bytecode interpreted by a bounded Dart runtime. The
artifact is bound to the exact application, release, runtime compatibility,
function signatures, capabilities, and monotonic sequence. Ed25519 verification,
resource budgets, atomic activation, rollback, and AOT fallback remain local
runtime decisions. Downloaded artifacts contain no native executable code,
Dart AOT snapshot, DEX/JAR, `.so`, FFI payload, or unrestricted reflection.

The host capability registry is explicit and compiled into the app. A patch can
invoke only capabilities already shipped and declared by the release. The
control plane stores metadata and signed bytes; it does not hold private
signing keys and cannot override runtime verification.

## Engineering classification

| Category | Current classification | Reason |
| --- | --- | --- |
| Plain passive text, existing-content assets, and localization data | LIKELY OTA-SAFE ARCHITECTURALLY | Data-only path using an existing renderer; app-specific content, privacy, commerce, and disclosure checks still apply. |
| Interpreted Dart business logic, widget hierarchy, conditional UI, navigation, pure-Dart dependency behavior | POLICY REVIEW REQUIRED | Behavior changes after review; the interpreter exception is not a general safe harbor. |
| Existing native plugin used in a materially new way, remote font, shader, payment/entitlement behavior | POLICY REVIEW REQUIRED | Technical delivery may be possible, but current public sources do not resolve the review boundary. |
| New capability, permission, entitlement, manifest/Info.plist change, native plugin/library, SDK, DEX/JAR/`.so`, build configuration | STORE RELEASE REQUIRED | Changes the reviewed signed/native/package surface or store configuration. |

## Facts, interpretations, and unknowns

- **FACT:** Apple Guideline 2.5.2, the Apple DPLA, Google Play Device and
  Network Abuse, Deceptive Behavior, SDK, permissions, payments, and dynamic
  code-loading sources impose restrictions relevant to downloaded behavior.
- **INTERPRETATION:** Architecture B reduces native-code and arbitrary-host
  access, but does not by itself establish store acceptance for interpreted
  behavior changes.
- **ASSUMPTION:** A reviewed app purpose, disclosed capability set, and
  passive-data grammar remain stable across patches.
- **UNKNOWN:** Whether either store accepts this exact capability-limited
  custom Dart-subset runtime for the proposed business/UI correction model;
  what material-change threshold applies; and whether remote fonts/shaders or
  specific payment flows receive different treatment.

## Review questions

1. Does the exact signed, capability-limited, non-native interpreter artifact
   fit Apple's DPLA interpreted-code allowance while remaining consistent with
   Guideline 2.5.2?
2. Will Google Play treat the custom Dart-subset bytecode as within the VM/
   interpreter exception without treating behavior changes as an impermissible
   self-update or hidden feature?
3. What evidence and review notes are required for a bug fix, UI correction,
   route decision, pure-Dart dependency behavior, remote font, shader, or
   payment change?
4. How should a store review exercise patched behavior, rollback, capability
   restrictions, and outage-safe AOT fallback?

## Sources

See [Apple policy evidence](apple.md), [Google Play policy evidence](google-play.md),
and the [change matrix](change-matrix.md). These sources were accessed on
2026-08-22 and must be rechecked before any production/store submission.

No store submission is authorized by this package.
