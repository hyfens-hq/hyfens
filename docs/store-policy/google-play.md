# Google Play policy research for Flutter OTA

Accessed: 2026-08-22

Authority boundary: current, public, first-party Google policy and Android security documentation only.

## Scope and caution

This document evaluates a proposed Flutter OTA runtime that downloads a signed, architecture-independent program and executes it in an interpreter already shipped in the app. It does not evaluate a system that downloads DEX, JAR, native libraries, AOT snapshots, or other native executable code.

This is engineering research, not legal advice or a Google Play approval. Google applies all Developer Program Policies to the app and its remotely supplied behavior. No architecture or change below is declared “Google Play compliant.”

Labels have precise meanings:

- **FACT** — stated by a current official Google source.
- **INTERPRETATION** — this project's reading of those facts for the proposed design.
- **ASSUMPTION** — a working premise that still needs evidence.
- **UNKNOWN** — the official sources reviewed do not answer the question sufficiently.

The change-classification labels are engineering release gates, not compliance findings:

- **LIKELY OTA-SAFE ARCHITECTURALLY** — passive data or content can use behavior already shipped in the reviewed app; all content, privacy, payments, metadata, and app-specific policies still apply.
- **POLICY REVIEW REQUIRED** — do not ship OTA without a documented, change-specific policy assessment; seek written Google guidance when the change executes remotely supplied interpreted code or materially changes behavior.
- **STORE RELEASE REQUIRED** — must ship through a new Google Play app release because it changes the package, native/runtime surface, manifest, SDK, permission, or another build-time boundary.

## Policy facts and implications

### Executable and interpreted code

**FACT G-01.** A Play-distributed app may not modify, replace, or update itself outside Google Play's update mechanism. It also may not download executable code such as DEX, JAR, or `.so` files from outside Google Play. The same policy states an exception for code running in a VM or interpreter that provides indirect access to Android APIs. [Device and Network Abuse, full policy](https://support.google.com/googleplay/android-developer/answer/16559646?hl=en)

**FACT G-02.** Runtime-loaded interpreted languages, whether in the app or third-party code such as an SDK, must not allow potential violations of Google Play policies. [Device and Network Abuse, full policy](https://support.google.com/googleplay/android-developer/answer/16559646?hl=en)

**INTERPRETATION G-03.** A custom, non-native Flutter patch bytecode executed solely by an interpreter may fit the interpreter exception more closely than downloaded Dart AOT snapshots, DEX/JAR, or native libraries. The policy does not name Dart, Flutter, custom bytecode, or this design, so “fits the exception” is not a compliance conclusion.

**INTERPRETATION G-03A.** The interpreter sentence is an exception to the ban on downloading executable-code formats; it is not a general authorization to self-update behavior. The same paragraph separately prohibits an app from modifying, replacing, or updating itself outside Google Play, and the next sentence requires runtime-loaded interpreted code not to enable potential policy violations. Therefore interpreted Dart business logic, UI hierarchy, navigation, and pure-Dart dependency changes remain **POLICY REVIEW REQUIRED**.

**INTERPRETATION G-04.** Downloading an AOT snapshot or any artifact containing native instructions is outside the proposed safe policy boundary even if the artifact has a project-specific extension. Artifact semantics, not its filename, should control classification.

**UNKNOWN G-05.** The reviewed policy does not define how Google distinguishes an allowed interpreted program from a forbidden self-update when that interpreted program changes app behavior. It also does not say whether a custom Dart-subset bytecode receives the same treatment as the examples (JavaScript, Python, and Lua).

### Transparent behavior and app changes

**FACT G-06.** App functionality must be reasonably clear; hidden, dormant, or undocumented features and review-evasion techniques are prohibited. Google's guidance specifically says not to remotely download and execute code that introduces functionality absent during review. [Deceptive Behavior, “Behavior Transparency”](https://support.google.com/googleplay/android-developer/answer/17006354?hl=en&rd=1)

**FACT G-07.** Google instructs developers to alert users and update the store listing when functionality changes. Its examples identify significant changes between versions without an alert and updated listing as violations. [Deceptive Behavior](https://support.google.com/googleplay/android-developer/answer/17006354?hl=en&rd=1)

**FACT G-08.** Additional app resources such as game assets may be downloaded when necessary for use of the app; those resources remain subject to all Play policies, and the app should prompt the user and clearly disclose download size before downloading. [Deceptive Behavior, “Enabling Dishonest Behavior”](https://support.google.com/googleplay/android-developer/answer/17006354?hl=en&rd=1)

**INTERPRETATION G-09.** A remotely activated new feature or changed core purpose is high risk even when represented as interpreted code. An OTA facility must not be used to make review-only behavior differ from ordinary-user behavior or to activate undocumented capabilities.

**INTERPRETATION G-10.** Store-listing accuracy and user notice are independent gates. A change being technically interpretable does not make it suitable for OTA.

**UNKNOWN G-11.** The policy gives no objective threshold for “significantly” changed functionality, nor does it specify whether an ordinary bug fix, layout change, or route adjustment requires a listing update.

### Capability and Android API boundary

**FACT G-12.** Apps may not access devices, networks, APIs, services, or other apps in an unauthorized or disruptive way, circumvent Android sandbox protections, introduce/exploit security vulnerabilities, or use an API contrary to its terms. [Device and Network Abuse](https://support.google.com/googleplay/android-developer/answer/16559646?hl=en)

**FACT G-13.** Third-party SDK behavior is attributed to the app: developers must ensure incorporated SDK code and data practices comply with Play policies. [SDK Requirements](https://support.google.com/googleplay/android-developer/answer/13323374?hl=en)

**INTERPRETATION G-14.** The runtime should expose a closed, versioned capability registry rather than arbitrary reflection, FFI, platform-channel names, filesystem access, process execution, or native symbol lookup. A patch may call only capabilities already compiled into and intentionally registered by the reviewed app.

**INTERPRETATION G-15.** Capability registration is necessary but not sufficient. Each capability must enforce Android permissions, user intent, data-use restrictions, API terms, argument validation, and resource budgets. A generic capability such as `platform.invoke(anyName, anyPayload)` would defeat the boundary.

**ASSUMPTION G-16.** Limiting patches to predeclared capabilities and reviewed functionality materially lowers policy and security risk. This needs threat-model testing and, before production use, direct policy review with Google; it is not stated as a safe harbor by Google.

### Permissions, data, and disclosures

**FACT G-17.** Personal and sensitive data access, collection, use, and sharing must be limited to policy-conforming app/service functionality reasonably expected by users; data must be handled securely, and an Android runtime-permission request must be used where available before access. [SDK Requirements](https://support.google.com/googleplay/android-developer/answer/13323374?hl=en)

**FACT G-18.** Developers must keep a clear and accurate Data safety section for every app, including collection and handling performed by third-party libraries or SDKs. [SDK Requirements](https://support.google.com/googleplay/android-developer/answer/13323374?hl=en)

**FACT G-19.** High-risk or sensitive permissions may require a Permissions Declaration Form and Play approval. Newly requested permissions are evaluated from the uploaded app bundle during the release process. [Declare permissions for your app](https://support.google.com/googleplay/android-developer/answer/9214102?hl=en)

**FACT G-19A.** Android permissions used by an app are declared in its manifest; dangerous permissions on supported Android versions also require a runtime request. Separately, Google Play limits sensitive permissions and APIs to current app features or services promoted in the Play listing, and disallows their use for undisclosed, unimplemented, or disallowed purposes. [Android — Declare app permissions](https://developer.android.com/training/permissions/declaring) · [Google Play — Permissions and APIs that Access Sensitive Information](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en)

**INTERPRETATION G-20.** An OTA patch must not expand data collection or use beyond current Data safety/privacy disclosures. If behavior changes those declarations, the patch is blocked pending updated disclosures and policy review even if it needs no new Android permission.

**INTERPRETATION G-21.** An OTA patch cannot add an Android manifest permission. It also must not repurpose an already-declared sensitive permission for a materially different or undisclosed use.

### Target SDK, manifest, and third-party SDK boundary

**FACT G-21A.** Google defines an app update as a new version submitted for review to replace an existing app, and `targetSdkVersion` is declared in the app manifest. As of this research date, new apps and updates must target Android 15 (API 35); beginning August 31, 2026, ordinary mobile new apps and updates must target Android 16 (API 36). Existing ordinary mobile apps must target API 35 by that date to remain available to new users on newer Android versions. Form-factor thresholds and extension rules differ. [Target API level requirements for Google Play apps](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)

**INTERPRETATION G-21B.** An interpreted OTA payload cannot change the installed package's `targetSdkVersion`, `minSdkVersion`, manifest declarations, package metadata, signing identity, or compiled Android compatibility behavior. Any such change is **STORE RELEASE REQUIRED** and the submitted bundle must meet the target-API rule then in force.

**FACT G-21C.** Developers are responsible for ensuring third-party SDK code and practices do not cause policy violations, including knowing the SDK's permissions and data collection; the obligation applies to third-party libraries' Data safety disclosures as well. [SDK Requirements](https://support.google.com/googleplay/android-developer/answer/13323374?hl=en)

**INTERPRETATION G-21D.** A dependency being “pure Dart” removes some native-artifact concerns but does not resolve self-update, behavior-transparency, user-data, permissions/API, payments, or content-policy concerns. A remotely supplied pure-Dart dependency change is therefore **POLICY REVIEW REQUIRED**, not automatically OTA-safe.

### Payments and monetization

**FACT G-21E.** Play-distributed apps accepting payment for in-app functionality, digital content, goods, subscriptions, or cloud software/services must use Google Play's billing system unless a stated exception or an enrolled eligible-region program applies. Apps generally may not lead users to another payment method through in-app webviews, links, messaging, or user-interface flows outside those exceptions/programs. Pricing and payment requirements must be accurately disclosed. [Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en)

**INTERPRETATION G-21F.** An OTA change must not introduce or reroute a purchase flow, change what paid entitlement unlocks, add a new digital SKU, bypass Play Billing, or alter region-specific alternative-billing behavior without **POLICY REVIEW REQUIRED** and the applicable Play Console/product configuration. If native billing integration, manifest metadata, or compiled SDK changes, a **STORE RELEASE REQUIRED** gate also applies.

**UNKNOWN G-21G.** The general Payments policy does not determine whether a particular product, market, or account qualifies for Sections 3, 8, or 9. That requires product- and region-specific review against the current program terms.

**UNKNOWN G-21H.** The reviewed Payments policy does not expressly classify the patch artifact itself as a digital item. The behavior and entitlement it delivers still must not be used to evade applicable billing requirements.

### Security of remotely loaded behavior

**FACT G-22.** Android's official security guidance says dynamic code loading creates tampering, substitution, data-exfiltration, code-execution, and availability risks; it recommends avoiding it where possible, using trusted storage/sources, and verifying integrity before loading. It also warns that many forms—especially remote loading—violate Play policy. [Android dynamic code loading security guidance](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading)

**FACT G-23.** Google's Malware policy treats harmful dynamic execution as a possible backdoor. Arbitrary code execution without evidence of malicious intent may still be treated as a vulnerability that the developer must patch. [Malware, “A Note on the Backdoor Category”](https://support.google.com/googleplay/android-developer/answer/9888380?hl=en)

**INTERPRETATION G-24.** The patch channel is a security boundary. At minimum it needs cryptographic authenticity and integrity verification, app/version/runtime binding, replay and downgrade protection, fail-closed parsing, atomic activation, rollback, and strict instruction/memory/recursion/time budgets. A signature alone does not make patch behavior safe or policy-conforming.

**INTERPRETATION G-25.** Patch storage should be app-internal, and activation must occur only after verification. Transport should use HTTPS, but transport security is not a substitute for signed artifact verification.

## Initial change classification

No entry involving remotely loaded interpreted behavior is classified compliant or patchable solely because of the interpreter exception. Every OTA candidate remains conditional on all of these gates:

1. The patch contains interpreter data/bytecode only—no DEX, JAR, `.so`, native instructions, AOT snapshot, or dynamically linked native payload.
2. The behavior remains within functionality disclosed to users and available for Play review; it does not create a hidden feature or a new core purpose.
3. It uses only precompiled, registered capabilities and does not expand permissions, sensitive-data practices, or native/plugin surface.
4. The patch is authenticated, version-bound, resource-bounded, staged atomically, and rollback-capable.
5. Content-specific Play policies and applicable user/store-listing disclosures have been reviewed.

| Change | Initial classification | Cautious rationale |
|---|---|---|
| Interpreted Dart business-logic bug fix | **POLICY REVIEW REQUIRED** | The interpreter exception may address artifact format, but Google separately prohibits off-Play self-updates and runtime-loaded interpreted code that permits policy violations. “Bug fix” and “Dart-only” are not official safe harbors. Prove the artifact contains no native/AOT code and assess the behavioral change. |
| UI hierarchy, layout, conditional rendering, or behavioral UI logic | **POLICY REVIEW REQUIRED** | These can materially change app behavior, disclosures, permissions prompts, purchase flows, or reviewed functionality even when represented as interpreted data. Mere text/content corrections may be a narrower technical OTA candidate, but still require content, listing, and behavior review. |
| Navigation or route selection | **POLICY REVIEW REQUIRED** | Route changes can reveal dormant/undocumented screens, bypass consent or billing steps, alter access control, or make reviewer behavior differ. Restricting navigation to precompiled destinations does not itself resolve those concerns. |
| Pure-Dart dependency version change | **POLICY REVIEW REQUIRED** | “Pure Dart” reduces native-code risk only. The dependency can still change runtime behavior, data handling, APIs, payments, or content; the interpreter exception is not a dependency-update safe harbor. |
| Dependency change containing Android/native code, AOT output, manifest merge, resources, or SDK configuration | **STORE RELEASE REQUIRED** | It changes the Play-delivered package or introduces prohibited off-Play executable formats; it may also affect permissions and Data safety disclosures. |
| `AndroidManifest.xml` change | **STORE RELEASE REQUIRED** | The installed manifest is part of the Play-delivered application artifact; the interpreter exception does not provide a mechanism to replace it. |
| `targetSdkVersion`, `minSdkVersion`, package metadata, signing, or Android build configuration | **STORE RELEASE REQUIRED** | These are properties of the submitted Android package. The new bundle must meet the target-API requirement in force at submission. |
| Add or change Android permissions | **STORE RELEASE REQUIRED** | Permission declarations live in the manifest, and sensitive/high-risk permission review is tied to an uploaded app bundle/release. Behavioral reuse of an existing permission for a new purpose is not a workaround. |
| New remote capability or host-bridge operation | **STORE RELEASE REQUIRED** | Adding a real capability changes the shipped host/runtime or native registry. Precompiling a dormant generic bridge does not make later remote activation safe. |
| Native plugin addition or native side of plugin change | **STORE RELEASE REQUIRED** | It changes compiled Android code and potentially the manifest/API/data surface. Off-Play DEX/JAR/`.so` downloads are expressly prohibited. Dart glue alone is not useful unless the required native capability already shipped and was registered. |
| First or materially different OTA use of an existing native plugin | **POLICY REVIEW REQUIRED** | No binary changes, but remote activation can expose hidden functionality or materially different permission, protected-data, API, or billing use. |
| Compiled native library (`.so`, DEX, JAR) | **STORE RELEASE REQUIRED** | Directly within the policy's examples of executable code that may not be downloaded outside Play. |
| New SDK integrated through the normal build | **STORE RELEASE REQUIRED** | It changes compiled/bundled dependencies and can change permissions, manifest entries, data practices, or native behavior. A remotely interpreted pure-Dart SDK remains policy-review-gated under the pure-Dart dependency row. |
| Assets (images, media, non-executable data) | **LIKELY OTA-SAFE ARCHITECTURALLY** | Google contemplates necessary additional resources, subject to all policies and a prompt with download-size disclosure. Review content, necessity, licensing, delivery UX, and parser risk. Do not disguise executable/interpreted behavior as an asset. |
| Fonts | **POLICY REVIEW REQUIRED** | Usually resource data, but still downloaded content with licensing, size-disclosure, parser-security, and app-review considerations. Bundled Android resource-table/font changes require a store release. |
| Localization strings/data | **LIKELY OTA-SAFE ARCHITECTURALLY** | Non-executable copy within existing functionality is narrower than interpreted logic, but it still needs disclosure, purchase-term, regulated-claim, and feature-transparency checks. Bundled resource or manifest locale changes require a store release. |
| Shaders | **POLICY REVIEW REQUIRED** | Official Play sources reviewed do not classify remotely delivered shader source or compiled GPU programs. Format, driver execution, engine integration, security, and whether Google treats the artifact as executable code need specific review. |
| Payment or purchase behavior using already shipped billing APIs | **POLICY REVIEW REQUIRED** | Payments rules apply to the resulting flow regardless of delivery mechanism; the applicable Play Console product/region configuration must also be in place. |
| New billing integration, SDK, or manifest metadata | **STORE RELEASE REQUIRED** | It changes the Play-delivered package; Play Console catalog/configuration may also be required. |

## Architecture constraints derived from policy

The Android prototype should enforce these constraints from its first patch-loading experiment:

- Do not support downloaded DEX, JAR, `.so`, native instructions, Dart AOT snapshots, or FFI payloads.
- Make the patch container identify every section and reject executable/native or unknown section types.
- Keep platform access behind explicit capabilities compiled into the base release; deny unknown capability IDs.
- Bind a patch to app ID, release identity/version, runtime/bytecode version, and an allowed patch sequence; reject cross-app, incompatible, replayed, or downgraded patches.
- Authenticate before parsing executable sections where practical, then structurally validate all bytecode before activation.
- Keep current and previous-known-good patches, use atomic activation, and start safely with no patch if loading fails.
- Apply instruction, allocation, collection-size, stack, recursion, async-work, and wall-time limits.
- Maintain an auditable patch manifest/change classification. A release operator must explicitly attest that no native code, permission change, new capability, undisclosed feature, or data-practice expansion is present.
- Require a documented policy review for every remotely supplied interpreted business-logic, UI hierarchy, navigation, or pure-Dart dependency change; do not infer approval from the interpreter exception.
- Make remotely reachable behavior reproducible for reviewers. Never branch on reviewer detection, geography, device attributes, account identity, or time to hide functionality.
- Include a product gate for user notice, store-listing updates, Data safety/privacy updates, additional-resource download disclosure, payments/billing review, and Play Console configuration where applicable.

## Unresolved questions and required validation

1. **UNKNOWN:** Will Google Play regard this project's custom Dart-subset bytecode as code within the VM/interpreter exception?
2. **UNKNOWN:** How does the interpreter exception interact with the preceding prohibition on modifying/replacing/updating the app when behavior changes after review?
3. **UNKNOWN:** What exact boundary separates a permitted fix or content variation from remotely introduced functionality “not present during app review”?
4. **UNKNOWN:** Does Google require an in-app size prompt for small code-like interpreter patches, given that the explicit size guidance is written for additional resources/assets?
5. **UNKNOWN:** Are shader source and compiled shader artifacts “executable code” for this policy?
6. **UNKNOWN:** Is a patch signing/rollback/capability design sufficient for Google's security expectations, or are additional controls required?
7. **UNKNOWN:** What review materials should be supplied so Google can exercise patched behavior and understand the runtime before public deployment?
8. **UNKNOWN:** Does Google treat any category of behavior-preserving interpreted Dart fix as permissible under both the interpreter exception and the separate self-update prohibition, and if so what evidence and limits apply?
9. **UNKNOWN:** For a particular payment feature and served region, which Payments policy exception or enrolled program (if any) applies?

Before production deployment, seek a written response through official Play Console support or another Google-provided review channel using a concrete artifact description and demonstrable prototype. Record the question, full response, date, app context, and any limitations. A support response should supplement—not replace—ongoing review of the published policies.

## Source register

All sources below are official Google properties and were accessed on 2026-08-22:

- [Google Play — Device and Network Abuse](https://support.google.com/googleplay/android-developer/answer/16559646?hl=en)
- [Google Play — Deceptive Behavior](https://support.google.com/googleplay/android-developer/answer/17006354?hl=en&rd=1)
- [Google Play — SDK Requirements](https://support.google.com/googleplay/android-developer/answer/13323374?hl=en)
- [Google Play — Declare permissions for your app](https://support.google.com/googleplay/android-developer/answer/9214102?hl=en)
- [Google Play — Permissions and APIs that Access Sensitive Information](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en)
- [Google Play — Target API level requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)
- [Google Play — Payments](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en)
- [Google Play — Malware](https://support.google.com/googleplay/android-developer/answer/9888380?hl=en)
- [Android Developers — Dynamic Code Loading security risks](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading)
- [Android Developers — Declare app permissions](https://developer.android.com/training/permissions/declaring)

## Blockers

- No official source reviewed gives a project-specific ruling for custom Dart/Flutter interpreter patches.
- No policy text reviewed defines an objective material-change threshold for OTA behavior changes.
- Production classification therefore remains conditional on experiments, a complete threat model, and direct Google review; this document cannot establish compliance.
