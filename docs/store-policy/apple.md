# Apple App Store policy and Flutter OTA updates

Accessed: 2026-08-22

Scope: standard distribution through Apple's App Store for iOS and iPadOS. This document does not analyze alternative marketplaces, enterprise distribution, or jurisdiction-specific entitlements. It is architecture research, not legal advice or an App Review determination.

## Reading labels

- **FACT** — stated by a current, public Apple source.
- **INTERPRETATION** — this project's cautious reading of one or more facts.
- **ASSUMPTION** — a premise that has not yet been verified with Apple or an App Review submission.
- **UNKNOWN** — the public sources do not resolve the question.

The change classifications later in this document are architecture gates, not compliance claims:

- **LIKELY OTA-SAFE ARCHITECTURALLY** — plausibly deliverable as passive data or content through behavior already present in the reviewed app; all content, privacy, commerce, metadata, and app-specific rules still apply.
- **STORE RELEASE REQUIRED** — requires a newly signed build through App Store review because it changes the bundle, native/runtime surface, signed configuration, or another build-time boundary.
- **POLICY REVIEW REQUIRED** — technically may fit the interpreted/data path, but public Apple sources do not establish that the behavioral change may be delivered OTA.

Nothing marked **LIKELY OTA-SAFE ARCHITECTURALLY** is a guarantee of App Review acceptance.

## Executive finding

**FACT:** App Review Guideline 2.5.2 says an app must be self-contained and may not download, install, or execute code that introduces or changes its features or functionality. Its express exception concerns narrowly defined educational programming apps. [App Review Guidelines §2.5.2](https://developer.apple.com/app-store/review/guidelines/#software-requirements)

**FACT:** The Apple Developer Program License Agreement (DPLA) §3.3.1(B) separately says executable code generally may not be downloaded or installed, but permits downloaded interpreted code only when it stays consistent with the app's intended and advertised primary purpose, does not bypass operating-system security, and does not create an app storefront. [Apple Developer Program License Agreement §3.3.1(B)](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)

**FACT:** DPLA §3.3.1(C) says that, absent Apple's prior written approval or a specified in-app-purchase exception, features or functionality may not be provided, unlocked, or enabled through distribution mechanisms other than the App Store, Custom App Distribution, or TestFlight. [Apple Developer Program License Agreement §3.3.1(C)](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)

**INTERPRETATION:** An interpreter avoids downloading native machine code, but that fact alone does not make general-purpose Flutter OTA acceptable. A patch that changes Dart behavior can still be “code” and can change functionality under Guideline 2.5.2. It may also fall within the DPLA's conditional allowance for interpreted code. The public texts do not explain how Apple reconciles those provisions for bug-fix OTA systems.

**UNKNOWN:** Whether Apple would accept a disclosed, signed, capability-limited Flutter interpreter used only for fixes and changes within an app's already-reviewed purpose. No current official source reviewed here grants a general Flutter, Dart, or bug-fix OTA exception.

Therefore the project must not advertise Apple App Store compliance. For iOS, code-bearing patch categories remain **POLICY REVIEW REQUIRED** until the exact runtime, patch format, capability boundary, disclosure, and representative changes have been evaluated with Apple.

## Evidence table

| Label | Proposition | Architecture implication | Official source |
|---|---|---|---|
| **FACT** | Apps must be self-contained and cannot download, install, or execute code that introduces or changes app features or functionality. | A patch VM is not exempt merely because its bytecode is architecture-independent. | [App Review Guidelines §2.5.2](https://developer.apple.com/app-store/review/guidelines/#software-requirements) |
| **FACT** | Downloaded interpreted code is conditionally allowed by the DPLA if it remains consistent with the app's intended and advertised purpose, preserves OS security, and does not create an app storefront. | Patch capabilities must be bounded by the reviewed app purpose and must not bypass signing or sandbox controls. | [DPLA §3.3.1(B)](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) |
| **FACT** | Additional features or functionality generally cannot be provided through a mechanism outside App Store, Custom App Distribution, or TestFlight without prior written Apple approval. | New capabilities and feature unlocks should be treated as store releases. | [DPLA §3.3.1(C)](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) |
| **FACT** | Apps may use only documented APIs in their prescribed manner. | The runtime and every compiled host capability must use public APIs. | [App Review Guidelines §2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements), [DPLA §3.3.1(A)](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) |
| **FACT** | New features, functionality, and product changes must be specifically disclosed in review notes and available to review; app metadata must reflect the core experience. | A hidden patch path or undisclosed capability registry creates independent review risk. | [App Review Guidelines §2.3 and §2.3.1(a)](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) |
| **FACT** | Apps must implement security measures for user information, and harmful code or files are grounds for rejection. | Signing is necessary but insufficient; malformed and malicious patches need containment and resource limits. | [App Review Guidelines §1.6](https://developer.apple.com/app-store/review/guidelines/#safety), [§2.5.3](https://developer.apple.com/app-store/review/guidelines/#software-requirements) |
| **FACT** | Developers must not interfere with Apple security, signing, verification, authentication, or system integrity. | The design must not depend on writable native executable memory, signature bypass, sandbox escape, or private APIs. | [DPLA §3.2(5)](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) |
| **FACT** | Guideline 4.7 permits specifically listed non-bundled software categories, including HTML5/JavaScript mini apps and plug-ins, subject to additional restrictions. | This is a special distribution model, not evidence of a blanket exception for in-place Dart application patches. | [App Review Guidelines §4.7–4.7.5](https://developer.apple.com/app-store/review/guidelines/#mini-apps-mini-games-streaming-games-chatbots-plug-ins-and-game-emulators) |
| **FACT** | Under §4.7, native platform APIs may not be extended or exposed to the offered software without prior Apple permission; sharing permissions requires per-instance consent. | A host capability registry helps security, but unrestricted plugin/native API bridging would be high risk. | [App Review Guidelines §4.7.2–4.7.3](https://developer.apple.com/app-store/review/guidelines/#mini-apps-mini-games-streaming-games-chatbots-plug-ins-and-game-emulators) |
| **FACT** | Apple-hosted background assets are separate from an app build, but asset packs are submitted for distribution and are covered by App Review. | Apple provides a reviewed content-delivery path; it does not establish permission to ship executable or interpreted Dart patches as “assets.” | [Background assets](https://developer.apple.com/documentation/appstoreconnectapi/background-assets), [App Review submission overview](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review) |
| **FACT** | App versions select a build for submission; Apple separately identifies Apple-hosted assets as content managed outside a build. | Bundle, executable, framework, and signed-configuration changes belong in a new store build unless Apple documents another reviewed path. | [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds), [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/) |
| **FACT** | Apple documents App Review submissions, including an expedited-review request for critical bug fixes, as its supported path for app bug-fix updates. | The existence of an expedited store path weakens any assumption that urgency creates an unwritten OTA exception. | [App Review — expedited reviews and bug-fix submissions](https://developer.apple.com/app-store/review/) |

## Downloaded interpreted and data-driven content

### Interpreted Dart or custom bytecode

**FACT:** The DPLA distinguishes downloaded executable code from downloaded interpreted code. It does not define Dart Kernel, a custom bytecode container, or a Flutter widget description format by name. [DPLA §3.3.1(B)](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)

**INTERPRETATION:** A bytecode program executed by a VM compiled into the app is likely “interpreted code” in the ordinary technical sense. Calling the same bytes “data,” serializing them as JSON/CBOR/Protobuf, or signing them does not determine their policy classification; behavior and use matter more than container encoding.

**ASSUMPTION:** Pure interpretation with no JIT, native dynamic loading, or executable-memory generation is materially safer than downloading native instructions. This assumption addresses platform security and the DPLA's executable-code restriction, but it does not resolve Guideline 2.5.2.

**UNKNOWN:** Whether Apple distinguishes corrective behavior changes from feature or functionality changes for purposes of Guideline 2.5.2.

### Data-driven content

**FACT:** Apple documents mechanisms that download asset content separately from an app build. Apple-hosted asset packs are submitted for App Store distribution, while the Background Assets framework can schedule downloads from a developer server or CDN. [Overview of Apple-hosted asset packs](https://developer.apple.com/help/app-store-connect/manage-asset-packs/overview-of-apple-hosted-asset-packs/)

**INTERPRETATION:** Ordinary remote content consumed by fixed, reviewed application behavior—such as catalog records, editorial copy, server-driven values, or images—is a stronger candidate than general Dart bytecode. Content must still remain consistent with the reviewed app, its metadata, age rating, privacy disclosures, intellectual-property rights, and other applicable guidelines.

**UNKNOWN:** Where Apple would draw the line between content/configuration and an executable UI or logic description. A declarative widget tree with conditionals, navigation, host calls, and expressions may function as interpreted code even if encoded as data.

## Capability registry implications

An explicit registry such as `http.get`, `storage.read`, `navigation.push`, and bounded UI constructors is desirable, but it is not by itself a policy authorization.

**INTERPRETATION:** A least-privilege registry supports the DPLA requirement not to bypass OS security and limits the effect of untrusted patches. The iOS runtime should expose only capabilities already compiled into and exercised by the reviewed app, validate all arguments and results, preserve system permission checks, and deny unknown capability identifiers.

**INTERPRETATION:** Adding a new registry entry to a shipped build is a store-release event. Activating a dormant, undisclosed entry remotely may be viewed as hidden or newly enabled functionality under Guideline 2.3.1(a) and DPLA §3.3.1(C).

**UNKNOWN:** If the runtime is treated as software distribution under Guideline 4.7, §4.7.2 may require prior Apple permission before native platform APIs or technologies are exposed to patches. Guideline 4.7 names specific hosted-software categories and does not say that generic OTA patch systems fall within it. [App Review Guidelines §4.7](https://developer.apple.com/app-store/review/guidelines/#mini-apps-mini-games-streaming-games-chatbots-plug-ins-and-game-emulators)

## Security and review expectations

**FACT:** Apple requires appropriate protection of user information and prohibits harmful code or files. It also requires apps to respect permission settings and clearly describe data access. [App Review Guidelines §1.6](https://developer.apple.com/app-store/review/guidelines/#safety), [§5.1.1](https://developer.apple.com/app-store/review/guidelines/#privacy)

**INTERPRETATION:** The iOS patch design should, at minimum:

- verify the patch signature and app/runtime/version binding before parsing executable payloads;
- reject rollback, replay, malformed encodings, invalid indices, invalid jumps, and unknown capabilities;
- impose instruction, recursion, stack, allocation, download-size, and wall-clock limits;
- activate atomically and fail closed to a known-good bundled or previously verified state;
- prevent patch code from altering the patch verifier, trust store, sandbox, system permission flow, or native loader;
- keep an auditable patch manifest and kill switch;
- make the patch mechanism, its reachable capabilities, and representative behavior visible to App Review.

**ASSUMPTION:** Cryptographic signatures and rollback controls will be required for a production-safe system. Apple’s sources reviewed here do not say that developer-managed signatures convert an otherwise prohibited code update into a permitted one.

## Initial change classification

These results apply only to App Store policy risk. They do not assert that the proposed compiler/runtime can technically implement each change.

| Change | Initial classification | Rationale |
|---|---|---|
| Interpreted Dart business-logic bug fix | **POLICY REVIEW REQUIRED** | It may remain within the advertised purpose and fit the DPLA interpreted-code condition, but it changes executed behavior and may fall under Guideline 2.5.2. |
| Plain text consumed by an existing content/localization path | **LIKELY OTA-SAFE ARCHITECTURALLY** | It is closer to passive content than downloaded code, provided it does not alter functionality or make metadata, rating, privacy, regulated, or commerce disclosures inaccurate. |
| Dart code that changes UI text | **POLICY REVIEW REQUIRED** | When the text change is encoded as executable Dart/bytecode rather than passive content, the unresolved downloaded-code rules apply. |
| Widget hierarchy, layout, or conditional rendering | **POLICY REVIEW REQUIRED** | A meaningful executable UI description may be interpreted code or changed functionality even when encoded declaratively. |
| Navigation or route-selection change | **POLICY REVIEW REQUIRED** | Navigation can expose features, permissions, purchases, or content that was not reviewed. A simple redirect is not expressly exempted. |
| Pure-Dart package/dependency delivered as interpreted code | **POLICY REVIEW REQUIRED** | Pure Dart avoids a native binary change, but it still changes remotely executed behavior; dependency provenance does not create an Apple exception. |
| Package/dependency change compiled into the app | **STORE RELEASE REQUIRED** | The normal Flutter dependency path alters AOT code, bundled resources, or reachable build output. |
| New remote/native capability | **STORE RELEASE REQUIRED** | Adding a capability requires changing the shipped host/runtime or native surface. Remotely enabling a dormant capability is instead policy-review-gated as potentially hidden or additional functionality under Guideline 2.3.1(a) and DPLA §3.3.1(C). |
| `Info.plist` change | **STORE RELEASE REQUIRED** | Apple defines `Info.plist` as configuration contained in the application bundle. A changed bundle belongs in a new build. [Information Property List](https://developer.apple.com/documentation/bundleresources/information-property-list) |
| New or changed permission purpose string or entitlement | **STORE RELEASE REQUIRED** | Purpose strings are bundle configuration; entitlements are claimed in the app code signature and authorized by its provisioning profile. [TN3125: Inside Code Signing — Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles) |
| New permission-dependent behavior using an already declared purpose | **POLICY REVIEW REQUIRED** | It can constitute new functionality or materially change privacy behavior even though the OS prompt and purpose string already exist. |
| New native plugin, native plugin version, or native framework | **STORE RELEASE REQUIRED** | It changes compiled/bundled native code and may change platform capabilities, APIs, privacy declarations, or entitlements. |
| First or materially different OTA use of an already shipped native plugin | **POLICY REVIEW REQUIRED** | No binary changes, but remote activation can expose undocumented functionality or materially different data/permission use. |
| New SDK | **STORE RELEASE REQUIRED** | Normal SDK integration changes compiled code or bundled dependencies; Apple also makes the developer responsible for third-party SDK behavior. [App Review Guidelines, introduction](https://developer.apple.com/app-store/review/guidelines/) |
| Images/audio/video or other passive assets | **LIKELY OTA-SAFE ARCHITECTURALLY** | A fixed reviewed app may download content, but the content must remain within the reviewed experience and satisfy metadata, rating, privacy, safety, and IP rules. Apple-hosted asset packs themselves undergo review. |
| Remote fonts loaded by an existing content path | **POLICY REVIEW REQUIRED** | Fonts are resources, but the reviewed sources do not clearly classify remote font delivery; licensing, parser risk, and UI effects remain app-specific. A bundle declaration or bundled-font change requires a store release. |
| Localization strings/content consumed by an existing system | **LIKELY OTA-SAFE ARCHITECTURALLY** | Translating existing reviewed content is closer to data than code; new flows, functionality, regulated claims, or materially different metadata require policy review. |
| Shader source or compiled shader artifact | **POLICY REVIEW REQUIRED** | Shaders are GPU programs and can materially change rendering. The reviewed Apple sources provide no general OTA shader exception; any required engine/bundle integration is a store release. |
| Payment behavior using already shipped payment APIs | **POLICY REVIEW REQUIRED** | Payment routing, unlocking, price presentation, and purchase UX are independently constrained by Guidelines 3.1 and 2.3.2. New StoreKit code, entitlements, or bundle configuration requires a store release. [App Review Guidelines §3.1](https://developer.apple.com/app-store/review/guidelines/#business) |

## Store-release boundary

The platform should force **STORE RELEASE REQUIRED** when a change modifies or requires any of the following:

- native machine code, dynamic libraries, frameworks, or Flutter engine artifacts;
- the signed application bundle, `Info.plist`, entitlements, provisioning, privacy manifests, or required-use-reason declarations;
- a native plugin or a new host capability;
- a new OS permission or materially different use of protected data;
- an app purpose, business model, core experience, age rating, or privacy posture not represented in the reviewed version;
- a hidden, dormant, or undocumented feature;
- a mechanism that bypasses system security, signing, sandboxing, or review.

**INTERPRETATION:** The OTA tool should classify uncertain changes conservatively and refuse iOS patch generation unless the app owner explicitly acknowledges the review category. A server allowlist cannot override restrictions embedded in the signed release's compatibility manifest.

## Required validation before production use

1. Submit a minimal App Store/TestFlight review specimen that fully discloses the interpreter, patch source, signature system, capability registry, and representative Dart bug-fix/UI/navigation patches.
2. Ask Apple Developer Technical Support or App Review for written clarification that refers to the concrete mechanism, not to OTA in the abstract.
3. Have qualified counsel review the then-current English DPLA accepted by the distributing account. Apple states that the accepted English agreement is binding and most current. [Agreements and Guidelines](https://developer.apple.com/support/terms/)
4. Record review correspondence and conditions as evidence tied to the exact runtime version. Approval of one app/version must not be generalized into a platform-wide compliance claim.
5. Re-check Apple policy before each release because the guidelines and agreements change.

## Unknowns and blockers

- **UNKNOWN:** Apple's operative distinction, if any, between a bug fix and a functionality change under Guideline 2.5.2.
- **UNKNOWN:** Whether custom Dart bytecode interpreted by an embedded VM is acceptable for a conventional, non-educational app under the combination of Guideline 2.5.2 and DPLA §3.3.1(B).
- **UNKNOWN:** Whether a capability-limited patch runtime is evaluated under Guideline 4.7, and whether prior permission under §4.7.2 would be required.
- **UNKNOWN:** Whether remotely supplied widget graphs, routing tables with expressions, shaders, and fonts are treated as content, interpreted code, or changed functionality in a particular app.
- **BLOCKER:** Public Apple sources cannot produce an app-specific review decision. Production iOS code OTA remains blocked on a concrete implementation, full disclosure, and Apple review/clarification.
- **PROCESS NOTE:** The research skill requested a background research agent, but all collaboration slots were occupied. The primary-source investigation was completed directly instead; this did not limit access to the cited public sources.

## Official sources

All sources were accessed on 2026-08-22.

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
- [Agreements and Guidelines for Apple Developers](https://developer.apple.com/support/terms/)
- [Overview of Apple-hosted asset packs](https://developer.apple.com/help/app-store-connect/manage-asset-packs/overview-of-apple-hosted-asset-packs/)
- [Background assets](https://developer.apple.com/documentation/appstoreconnectapi/background-assets)
- [Overview of submitting for review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review)
- [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [App Review — expedited reviews and bug-fix submissions](https://developer.apple.com/app-store/review/)
- [Information Property List](https://developer.apple.com/documentation/bundleresources/information-property-list)
- [TN3125: Inside Code Signing — Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
