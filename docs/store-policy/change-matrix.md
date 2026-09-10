# Store-policy change matrix for Flutter OTA

Accessed: 2026-08-22

Scope: standard Apple App Store distribution for iOS/iPadOS and Google Play distribution for Android. This is a conservative architecture release gate, not legal advice, a compliance certification, or a prediction of an individual review decision. The platform-specific evidence and unresolved questions remain in [apple.md](apple.md) and [google-play.md](google-play.md).

## Classification contract

The matrix uses exactly three outcomes:

- **LIKELY OTA-SAFE ARCHITECTURALLY** — passive data or content can be consumed by already shipped behavior without changing the signed/native app surface. This says only that the architecture has a plausible OTA path; every content, privacy, safety, commerce, metadata, and app-specific rule still applies.
- **STORE RELEASE REQUIRED** — the change crosses a build-time, signed-configuration, native-code, permission, SDK, or host-capability boundary and must be delivered in a newly reviewed store build.
- **POLICY REVIEW REQUIRED** — the architecture could technically deliver the change, but current public policy does not provide a sufficient safe harbor for production OTA. Do not generate or deploy it until the exact mechanism and representative behavior receive platform-specific review.

These are gates, not a continuum. In particular, Google's VM/interpreter exception does not by itself make interpreted Dart business logic, widget construction, navigation, or a pure-Dart dependency change OTA-safe.

## FACT

- **Apple:** Guideline 2.5.2 says apps must be self-contained and may not download, install, or execute code that introduces or changes app features or functionality. The DPLA separately permits downloaded interpreted code only within stated limits, and §3.3.1(C) generally bars enabling additional functionality outside Apple distribution without prior written approval or the stated in-app-purchase exception. [App Review Guidelines §2.5.2](https://developer.apple.com/app-store/review/guidelines/#software-requirements), [DPLA §3.3.1(B)–(C)](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
- **Apple:** Hidden, dormant, or undocumented functionality is prohibited; new features, functionality, and product changes must be described specifically and exposed to review. Digital feature unlocking and payment flows are governed independently by Guidelines 2.3.2 and 3.1. [App Review Guidelines §2.3.1(a), §2.3.2, §3.1](https://developer.apple.com/app-store/review/guidelines/)
- **Google Play:** An app may not update itself outside Google Play or download executable DEX, JAR, or native code from elsewhere. The restriction does not apply to code running in a VM or interpreter that provides indirect Android API access, but runtime-loaded interpreted code must not enable potential Play-policy violations. [Device and Network Abuse](https://support.google.com/googleplay/android-developer/answer/16559646?hl=en)
- **Google Play:** Apps must not dynamically download and execute remote code that introduces functionality not present during review, and must not hide remotely activated features. [Deceptive Behavior](https://support.google.com/googleplay/android-developer/answer/17006354?hl=en)
- **Google Play:** The app is responsible for third-party SDK behavior. New permission requests and some sensitive/high-risk permissions are evaluated through release and declaration workflows. Digital in-app purchases must use Google Play's billing system unless an enumerated policy exception or eligible program applies. [SDK Requirements](https://support.google.com/googleplay/android-developer/answer/13323374?hl=en), [Declare permissions](https://support.google.com/googleplay/android-developer/answer/9214102?hl=en), [Payments](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en)

## INTERPRETATION

- The interpreter exception describes an artifact/execution boundary; it is not a blanket approval for every behavioral change expressible in that interpreter.
- Serialization does not determine policy treatment. A widget graph, routing table, shader, or dependency encoded as JSON, CBOR, Protobuf, or custom bytecode can still behave as code.
- “Already compiled” is not equivalent to “already reviewed for this use.” First or materially different remote invocation of a dormant plugin/capability remains review-sensitive even without a binary diff.
- The conservative cross-store gate is the stricter applicable outcome. A platform-specific delivery pipeline may narrow a **STORE RELEASE REQUIRED** row to the affected platform, but may not relax the other platform's policy gate.

## Change matrix

All entries assume standard store distribution and a production OTA channel. “Existing” means present, disclosed, reviewable, permission-correct, and used consistently with the store listing and privacy/data-safety declarations in the currently shipped version.

| Change | Classification | Boundary and reason |
|---|---|---|
| Business-logic bug fix delivered as interpreted Dart/custom bytecode | **POLICY REVIEW REQUIRED** | It avoids native code but changes executed behavior. Apple Guideline 2.5.2 and the interaction between Google's self-update prohibition and interpreter exception remain unresolved for this case. |
| Plain text/content value consumed by an existing renderer | **LIKELY OTA-SAFE ARCHITECTURALLY** | Passive content can use an existing data path. Reclassify if the text changes regulated claims, payment terms, privacy disclosures, age rating, store metadata, or functionality. |
| Text change encoded as executable Dart/bytecode | **POLICY REVIEW REQUIRED** | The user-visible result is text, but the delivered artifact is interpreted behavior rather than passive content. |
| Widget hierarchy, layout logic, or conditional rendering | **POLICY REVIEW REQUIRED** | A declarative or interpreted UI graph can change functionality and reveal dormant behavior; the interpreter exception alone is insufficient. |
| Navigation, route selection, or redirect logic | **POLICY REVIEW REQUIRED** | Navigation can expose unreviewed screens, capabilities, permissions, purchases, or data uses even when every destination is compiled into the app. |
| Pure-Dart dependency code delivered through the interpreter | **POLICY REVIEW REQUIRED** | “Pure Dart” proves only the absence of native code. It does not resolve self-update, downloaded-code, hidden-feature, SDK, privacy, or review-transparency rules. |
| New remote capability or host-bridge operation | **STORE RELEASE REQUIRED** | A real new capability requires a host/runtime/native registry change in the signed build. Precompiling a dormant generic bridge does not create an OTA loophole; activating that dormant surface is at least policy-review-gated. |
| New OS permission or permission purpose/declaration | **STORE RELEASE REQUIRED** | iOS purpose strings/entitlements and Android permissions are signed/bundled configuration; sensitive permissions may also require store declarations or approval. |
| `Info.plist` change | **STORE RELEASE REQUIRED** | It changes the iOS application bundle configuration and may affect permissions, URL schemes, background modes, or platform integration. |
| `AndroidManifest.xml` change | **STORE RELEASE REQUIRED** | It changes installed Android package metadata such as permissions, components, intent filters, services, or SDK declarations. |
| New native plugin, native plugin version, native framework, DEX/JAR, or `.so` | **STORE RELEASE REQUIRED** | It changes compiled/bundled native code or package metadata. Google expressly prohibits off-Play DEX/JAR/native downloads; Apple requires executable/native changes in the reviewed bundle. |
| First or materially different remote use of an existing native plugin | **POLICY REVIEW REQUIRED** | No binary change is required, but the new invocation can expose hidden functionality, new protected-data use, or a materially different reviewed purpose. |
| Passive images, audio, video, or data assets consumed by an existing content path | **LIKELY OTA-SAFE ARCHITECTURALLY** | Both ecosystems support downloaded content/resources, subject to content policy, IP, age rating, size/download UX, privacy, and review transparency. An asset that encodes behavior is not passive. |
| Remote font loaded by an existing renderer | **POLICY REVIEW REQUIRED** | Technically resource data, but current sources do not clearly classify remote font delivery; licensing, parser security, UI impact, and any required bundle declaration remain app-specific. |
| Localization strings/content consumed by an existing localization system | **LIKELY OTA-SAFE ARCHITECTURALLY** | Passive translations fit an existing content path. New flows, functionality, misleading copy, regulated claims, or changed disclosures require policy review; bundled locale configuration requires a store release. |
| Shader source or compiled shader artifact | **POLICY REVIEW REQUIRED** | A shader is a GPU program, not ordinary passive media. The reviewed policies do not give remote shaders a general exception; new engine/bundle integration is a store release. |
| New SDK or SDK version integrated through the normal Flutter/native build | **STORE RELEASE REQUIRED** | It changes AOT/native/bundled code and may change permissions, data collection, disclosures, or package metadata. A remotely interpreted pure-Dart SDK falls under the pure-Dart dependency row instead. |
| Payment, purchase routing, entitlement, price-presentation, or unlock behavior using already shipped APIs | **POLICY REVIEW REQUIRED** | Apple and Google impose detailed, region- and product-specific payment rules independent of artifact type. New billing code, SDKs, entitlements, manifests/plists, or deep-link configuration requires a store release. |

## ASSUMPTION

- Passive assets, plain text, and localization are generated by a non-executable content system whose grammar cannot express control flow, arbitrary host calls, navigation, permissions, payment routing, or code loading.
- The shipped app already authenticates content, constrains parsers and resources, preserves OS permission prompts, and can roll back invalid content.
- The store listing, review notes, privacy policy, Apple privacy disclosures, Google Data safety form, age rating, and payment model accurately describe the remotely variable content.
- A remote artifact contains no native instructions, Dart AOT snapshot, DEX/JAR, `.so`, dynamic library, JIT output, executable-memory payload, or unbounded generic platform bridge.

If any assumption fails, move the change to **POLICY REVIEW REQUIRED** or **STORE RELEASE REQUIRED** according to the boundary crossed.

## UNKNOWN

- Whether Apple will accept this exact capability-limited Dart/custom-bytecode interpreter for a conventional, non-educational app, including corrective changes within its existing purpose.
- Whether Google will treat this exact custom Dart-subset bytecode as within the VM/interpreter exception while also considering it an impermissible self-update.
- The objective threshold at which a bug fix, UI adjustment, navigation change, or content update becomes a new or materially changed feature for either review system.
- Whether either store treats remote font or shader artifacts as passive content, interpreted/executable code, or an app update in the proposed formats.
- Whether an app-specific approval, support response, or accepted review notes would apply to later runtime versions or materially different capabilities; no generalization should be assumed.

## Release-gate procedure

1. Classify the source and build diff, generated patch sections, capability calls, permissions, native dependencies, bundle/package metadata, data practices, disclosures, and payment effects.
2. Reject OTA generation for **STORE RELEASE REQUIRED** changes.
3. Hold **POLICY REVIEW REQUIRED** changes until the exact runtime, artifact, capability list, disclosures, and representative behavior have platform-specific written review evidence.
4. For **LIKELY OTA-SAFE ARCHITECTURALLY** content, still run content-policy, privacy, safety, metadata, payment, licensing, parser-security, signature, compatibility, and rollback checks.
5. Re-check the current official policies before each production release and retain dated review correspondence; an earlier accepted app version is not a universal safe harbor.

## Official source register

All sources were accessed on 2026-08-22.

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
- [Apple Information Property List](https://developer.apple.com/documentation/bundleresources/information-property-list)
- [Apple TN3125: Inside Code Signing — Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
- [Google Play Device and Network Abuse](https://support.google.com/googleplay/android-developer/answer/16559646?hl=en)
- [Google Play Deceptive Behavior](https://support.google.com/googleplay/android-developer/answer/17006354?hl=en)
- [Google Play SDK Requirements](https://support.google.com/googleplay/android-developer/answer/13323374?hl=en)
- [Google Play Declare permissions](https://support.google.com/googleplay/android-developer/answer/9214102?hl=en)
- [Google Play Payments](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en)
- [Android dynamic code loading security guidance](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading)
