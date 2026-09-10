# Phase 1D Maintainer Review

Status: complete for the bounded runtime/integration-readiness milestone.
The project stops here for maintainer review; no Phase 1D+ implementation or
productization work has started.

## Recommendation

~~~
PROCEED TO PRODUCTIZATION DESIGN WITH CONDITIONS
~~~

This recommendation permits a maintainer-reviewed design discussion only. It
does not authorize cloud, hosted delivery, accounts, rollout, telemetry,
dashboard, enterprise, React Native, store-compliance, or other product
infrastructure work.

The decision rule used here is:

- proceed with conditions only when safety/correctness gates are evidenced and
  remaining gaps are explicit, bounded, owned, and non-architectural;
- continue Phase 1D when required evidence is incomplete without a safe bounded
  conclusion;
- pivot only if Architecture B cannot satisfy the frozen requirements without
  violating a protocol or safety invariant;
- stop only if no viable bounded path remains.

## Frozen architecture and protocol boundary

Phase 1D retains:

~~~
ordinary Flutter/Dart source
        ↓
automatic build-time source instrumentation
        ↓
normal Flutter AOT fallback
        +
bounded patch dispatch
        ↓
signed interpreted patch runtime
~~~

Architecture B, exact release binding, Patch Format v1, capability contract
v1, state-v4 trust/high-water authority, signed rollback, and fail-closed
recovery remain unchanged. No Flutter/Dart fork, Kernel transformation,
PatchView, annotation requirement, or manual dispatch path was introduced.

## Evidence register

| Area | Status | Evidence boundary |
| --- | --- | --- |
| Architecture/protocol freeze | PASS | Phase 1C records and unchanged v1 artifacts |
| Automatic Android lifecycle | PASS / PHYSICAL ANDROID | Fresh release, patch, activation, restart, rollback, and rejection run |
| Automatic iOS lifecycle | PASS / PHYSICAL IOS | Fresh LAN release/patch plus app-support state, restart, rollback, and rejection run |
| Durable state recovery | PASS within process/restart scope | Android/iOS state-v4 copies and restart evidence; true power-loss not simulated |
| Malformed-patch corpus | PASS / coordinator-recorded | 20 × 54 = 1,080 bounded cases; captures preserved in research evidence |
| Activation soak | PASS | 15 process-isolated samples, 2 warmups |
| Host workload/profile benchmark | PASS / DIRECTIONAL | Three samples, supported pure-Dart workload models |
| Physical performance regression | PARTIAL | Phase 1C Android baseline preserved; no fresh Phase 1D reducer series; iOS timings not run |
| Adjacent SDK family | SUPPORTED_WITH_LIMITATIONS | Direct 3.47.1/3.13.1 checks pass; full CLI/device path not isolated |
| Representative fixture integration | PASS within fixture scope | Existing Riverpod/BLoC/GoRouter/local-package/native-boundary conformance fixture |
| Local observability | PASS for CLI/toolchain boundary | tool status and JSON inventory; no remote/runtime introspection |
| Consolidated regression | PASS | Root, package, CLI, instrumentation, patch-loading, and formatting/analyzer checks |

## 1. Architecture status

No new evidence exposes a fundamental Architecture B blocker. The fresh
Android and iOS runs both used ordinary source, automatic release
instrumentation, normal AOT fallback, bounded dispatch, and signed interpreted
patches. The runtime continued to reject incompatible or stale candidates and
preserved a recoverable base state.

## 2. State, recovery, and lifecycle semantics

The existing state-v4 controller remains authoritative. Verified candidates
enter pending health, become current only after health confirmation, and a
signed developer rollback selects base AOT without lowering the sequence
high-water. Invalid, malformed, stale, or wrong-release candidates do not
replace current or base state.

Android process restart retained the healthy patch and later retained the
signed rollback-to-base state. iOS state-v4 copies remained identical across
activation, relaunch, rollback, and relaunch after rollback. These are process
termination/restart observations, not physical power-cut guarantees.

## 3. Android physical evidence

Device: Redmi Note 10 Lite, Android 16/API 36, arm64, Wi-Fi ADB serial
192.168.50.135:39545.

- Automatic release:
  sha256:591bc15ade90e089332caee67886a04bffbdd8b0c4ffcdb028e3b3896956b2c7.
- APK: 51,967,840 bytes, SHA-256
  85b7afd2a0a8b30d48ce9eaf600ed43273115d1e1b5f011f04f8b386605aea58.
- Build fingerprint:
  524b68c9500763258dff9ccf19edb4dd39042e202b0fa223af0151d520764573.
- The source change was generated from a normal 90 to 95 multiplier edit.
- Automatic runtime logs showed pendingHealth, then healthy; the physical
  fixture behavior changed from base 540 to patched 665.
- Restart retained the healthy signed patch.
- Signed rollback returned to base, retained high-water sequence 1, and the
  base state persisted after restart.
- A stale valid candidate and malformed candidate did not replace the active
  state because the development server withheld updates at the current
  sequence. This is delivery-boundary evidence, not direct runtime rejection
  of supplied stale bytes.

The fixture contains an archival/manual controller status surface whose text
is not initialized by the generated bootstrap. It is not used as runtime
evidence; generated status logs and the physical result are authoritative.

## 4. iOS physical evidence

Device: physical iPhone 00008020-001528860E03002E, iOS 18.7.9, arm64.

- Automatic release:
  sha256:db8ab7534acf9d50a7bf4c7d0ae03adff4bc847a258aaf2284f56f7c3b9c9d6f.
- Development IPA: 7,198,583 bytes, SHA-256
  2d7d4484289f3eeb554d6dc4fadf86b8966c817338a935b27d04062105ce4e65.
- Build fingerprint:
  74caf12fab09034812f49e20764d8a9b65b2b97cdbbc2594e5aff6d9bade5a9a.
- Signed Patch Format v1 sequence 1 was 2,069 bytes with CLI patch ID
  sha256:e39f966ab8acf1db7b7eac7d138f457a70f43576008f722c4ed8e1171a93a15f.
- App-support state-v4 copies showed a healthy current patch and high-water
  sequence 1 after relaunch.
- Signed rollback produced current=null, health=base, while high-water
  sequence 1 remained after relaunch.
- A later sequence 2 patch became healthy; the development server withheld
  malformed and stale sequence 1 candidates, so the state remained unchanged.
  This is delivery-boundary evidence, not direct runtime rejection of supplied
  stale bytes.

The device tooling could not expose the application runtime log/UI stream
because the Developer Disk Image was unavailable. Therefore this is physical
automatic lifecycle/state evidence, not a claim of iOS semantic UI behavior or
iOS runtime timing.

## 5. Fuzz, soak, and adversarial coverage

The malformed-patch regression loop completed 1,080 bounded cases with
deterministic PASS; its session output is preserved under
docs/research/evidence/phase-1d-2026-08-23. The activation benchmark completed
15 isolated samples
after 2 warmups; full activation median was 3,527 microseconds and p95 was
6,214 microseconds. The scoped regression suite also passed the existing
parser/verifier/runtime and lifecycle tests.

An async benchmark attempt failed at the harness package-root/fixture-URI
boundary and is recorded as NOT RUN, not PASS. No claim is made for a long
power-loss, thermal, battery, or indefinite soak campaign.

## 6. Flutter/Dart compatibility and maintenance cost

The validated family remains Flutter 3.47.0 / Dart 3.13.0 with status
SUPPORTED for the bounded local workflow. Direct isolated Flutter 3.47.1 /
Dart 3.13.1 checks passed for versions, fixture analysis, fatal-info analysis,
and the benchmark self-check.

The adjacent full CLI attempt did not consume the Puro-selected SDK: the
child process reported 3.47.0. An explicit PATH attempt stopped in an
objective_c build hook with Invalid SDK hash. No physical 3.47.1 claim is
made, and the adjacent family remains SUPPORTED_WITH_LIMITATIONS. Flutter
3.44.9 remains UNSUPPORTED under the existing matrix.

This is a maintenance caveat for child-process SDK selection and package
hooks, not evidence requiring a Flutter or Dart fork.

## 7. Representative application integration

The existing conformance fixture exercises Riverpod, BLoC/Cubit, GoRouter,
async repository behavior, widgets, a local pure-Dart package, generated-code
boundaries, and a native/plugin boundary. The fresh Android and iOS workflows
used the fixture without experiment-only source units or manual dispatch
inputs.

This remains fixture-level evidence. It is not validation on an independent
customer application, and native implementation changes still require a
normal store release.

## 8. Interpreter profiling and optimization decisions

The host benchmark covers pricing, eligibility, collection transformation,
state recomputation, route decisions, and bounded async capability use. For
100 calls, interpreted/direct medians ranged from 11.85× to 203.64× across
the directional workload models. The public-layer profile measured lookup,
direct interpreter entry, and public invocation only.

No optimization was accepted from the noisy three-sample host profile. Decode,
frame/value allocation, budget accounting, capability checks, and source-map
costs have no internal attribution hooks and remain unmeasured. No native-
equivalent performance claim is made.

## 9. Startup and memory

The preserved Phase 1C physical Android baseline remains the authoritative
startup evidence: stock 368 ms, instrumented base 362 ms, and active patch
391 ms in the recorded launch series. No fresh Phase 1D iOS startup or memory
series was run. No fresh Phase 1D Android 15-sample reducer run was completed.

PSS/RSS, first-frame, thermal, battery, and iOS memory claims remain
unmeasured in this milestone. The new APK/IPA hashes are identity evidence,
not stock-versus-instrumented growth comparisons.

## 10. Binary growth

The preserved Android Phase 1C comparison remains 43,382,412-byte stock APK
versus 46,659,212-byte instrumented APK, +3,276,800 bytes / +7.5533%.
The preserved iOS Phase 1B evidence reported approximately +7.04% growth.
The fresh Phase 1D release artifacts were not produced as controlled stock /
instrumented pairs, so no new growth percentage is inferred.

## 11. Patch-size scaling and multi-function semantics

The host Phase 1D benchmark produced deterministic Patch Format v1 bridge
artifacts for 1, 5, 20, and 50 functions: 1,678; 6,474; 24,456; and 60,426
bytes respectively. The 50-function artifact activated through the existing
atomic E0 bridge.

This validates current bridge encoding and scaling only. It does not establish
physical multi-function activation, source-compiler scaling, or controller
multi-function performance.

## 12. Async and resource pressure

The benchmark exercises the existing bounded async capability/await subset.
Runtime budgets and capability-policy tests remain passing, and malformed
inputs continue to fail closed. The attempted additional async benchmark was
not run to completion because its fixture package URI was invalid. No broader
Future/Stream or hot-frame suitability claim is made.

## 13. Local observability

The local CLI now provides bounded tool status and tool status --json
inventory for release/patch state and diagnostics without exposing keys,
patch bytes, absolute paths, URLs, remote introspection, or telemetry. This is
developer-local toolchain observability, not an application runtime bridge or
production monitoring system.

## 14. Diagnostics

Existing stable tool diagnostics, JSON analysis output, exact release
validation, signature verification, and runtime status logging remain intact.
Physical Android logs supplied the strongest runtime evidence. On iOS, the
missing Developer Disk Image prevented equivalent log/UI capture; state-v4
container snapshots were used and labeled accordingly.

## 15. Security and trust findings

The fresh runs preserved signed activation, exact release binding, closed
capability authority, high-water anti-replay, signed developer rollback, and
fail-closed malformed/wrong-release behavior. Cleanup and rollback did not
lower the high-water sequence. Fresh physical stale-byte runtime rejection is
not claimed; the Android/iOS fresh runs observed delivery-boundary withholding
and unchanged state.

The threat model remains bounded: local filesystem tampering, rooted/fully
compromised devices, compromised signing keys, production transport, and
post-compromise trust recovery are not claimed to be solved by this local
milestone.

## 16. Patch Format v1 and capability v1

CLI-generated Android and iOS artifacts remained Patch Format v1, with
canonical encoding, digest/signature verification, exact release identity,
sequence metadata, and required capability declarations. No required section,
digest/signature boundary, or semantic rule was changed.

Capability v1 remains closed: undeclared, wrong-version, wrong-schema,
forbidden, or sync/async-mismatched capabilities remain rejected. No arbitrary
host reflection or native enumeration was added.

## 17. Developer workflow and friction

The validated workflow is:

~~~
tool doctor
tool init
tool keys generate
tool release android
tool release ios
# edit supported ordinary Dart/Flutter source
tool analyze
tool analyze --json
tool patch
tool inspect <patch>
tool verify <patch> --release <release-id>
tool rollback --to base
tool status
~~~

The normal path requires no source-unit files, function IDs, slots, bytecode,
manual manifests, annotations, rewritten call sites, PatchView, or Flutter SDK
modification. Remaining friction is physical-device setup, iOS developer
signing/Developer Disk Image availability, conservative unsupported-change
diagnostics, and adjacent-SDK isolation.

## 18. Consolidated validation

The final scoped suites passed sequentially with dart test -j 1 for root,
CLI, compiler, instrumenter, Patch Format, runtime, Flutter integration,
instrumentation, and patch-loading. Reported totals were 1, 37, 1, 2, 12, 5,
8, 204, and 59 tests respectively; patch-loading retained 2 skips. Formatting,
fatal-info analysis, benchmark self-checks, malformed corpus, and activation
soak also passed. The async harness/package-root attempt is the recorded
NOT RUN exception.

## 19. Remaining limitations and unresolved external gates

- True power-loss interruption was not simulated.
- No fresh Phase 1D Android dispatch/startup/memory reducer series was closed.
- Fresh physical stale-byte runtime rejection was not directly exercised;
  only delivery-boundary withholding and unchanged state were observed.
- iOS runtime logs/UI and iOS performance timings were unavailable in this
  environment.
- Full CLI/release/device validation on adjacent 3.47.1 was not isolated.
- Host interpreter stage attribution is incomplete.
- Evidence is fixture-level, not independent real-application validation.
- Raw coordinator captures are preserved, but they are session evidence rather
  than an immutable release/CI evidence service.
- The duplicate historical tasks/39 numbering is preserved and documented; it
  is not silently renumbered.

None of these findings currently demonstrates a fundamental Architecture B,
Patch Format v1, or capability v1 blocker. They are conditions on subsequent
claims, not permission to weaken safety boundaries.

## 20. Productization readiness assessment

The runtime/toolchain is credible enough to justify a maintainer-reviewed
productization design discussion, but not a production deployment claim. Any
next design review must retain local-first, signed, exact-release, closed-
capability, high-water, and fail-closed assumptions; define how device
observability and transport trust would be addressed; and require a new
security/privacy review before implementation.

No hosted service, backend, dashboard, rollout system, account model, or
commercial infrastructure was built or authorized by this review.

## 21. Proposed next phase

If maintainers accept the recommendation, the next phase may define bounded
productization requirements and threat-model decisions only. Before any
implementation, maintainers should resolve the adjacent-SDK CLI isolation
policy, decide the required iOS diagnostic/performance evidence, and decide
whether true power-loss testing is a release gate. The next phase must not
silently change Architecture B, Patch Format v1, capability v1, or the runtime
trust/high-water model.

This document is the Phase 1D stop point. No next phase has been started.
