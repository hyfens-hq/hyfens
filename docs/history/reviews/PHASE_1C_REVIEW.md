# Phase 1C Maintainer Review

Status: final maintainer-review evidence closure; Phase 1C work is complete and
awaiting the maintainer decision.

Architecture B, Patch Format v1, capability contract v1, and the Phase 1B
historical evidence are preserved. Phase 1D and product/cloud work have not
started.

## 1. Recommendation

`PROCEED TO PHASE 1D WITH CONDITIONS`

The host hardening and regression work is complete for this milestone. The
fresh exact-release Android runtime-fault case and Task 35 physical
dispatch/startup/memory/APK measurements are recorded in the final addendum
below. Task 32's controller-owned `state-v4` trust/high-water journal remains
the durable authority. The prior physical Android and iOS evidence remains
valid and is not being rewritten. This recommendation authorizes only a
maintainer-reviewed Phase 1D proposal; it does not start Phase 1D or any
product/cloud work.

## 2. Architecture status

The validated baseline remains:

```text
ordinary Flutter/Dart source
        ↓
automatic build-time source instrumentation
        ↓
normal Flutter AOT fallback
        +
bounded patch dispatch
        ↓
signed interpreted patch runtime
```

Phase 1C changed runtime failure handling, lifecycle validation, diagnostics,
fuzz regressions, and host measurement seams. It did not introduce a Flutter
or Dart fork, Kernel transformation, PatchView, annotations, manual dispatch,
or production networking.

## 3. State-machine hardening

`docs/architecture/runtime-state-machine.md` defines the implementation's
equivalent of `BASE`, `CANDIDATE`, `CURRENT`, and `FAILED`. `FAILED` is a
fail-closed recovery barrier, not an executable patch state. The controller
now validates generation, release binding, health, content digest, and
monotonic high-water across its two checksummed state copies. A pending
candidate has a one-attempt boot lease and is never promoted to healthy merely
because the process restarted.

## 4. Crash/power-loss fault injection

`E1PatchControllerTestHooks.durableBoundary` injects deterministic failures
around artifact/state write, flush, rename, and readback boundaries. The
focused lifecycle suite covers torn writes, missing/malformed peers, stale
copies, rollback write failure, candidate fallback, and unrecoverable state.

This is deterministic I/O-boundary fault injection, not a claim of physical
power-loss testing. OS-level process-kill/power-loss campaigns remain open.

## 5. Recovery invariants

The tests enforce that:

- partially written state is never selected as active;
- a valid peer can repair a missing or malformed copy;
- conflicting generations/high-water values fail closed;
- a candidate failure falls back to last-known-good or AOT;
- high-water never decreases during recovery or base rollback;
- corrupt lifecycle state cannot authorize a patch; and
- an unrecoverable state disables downloaded activation rather than guessing.

## 6. Boot-loop protection

Pending candidates use a persisted one-attempt boot lease. On restart before
health confirmation, the candidate is abandoned and the controller commits a
known-good/base fallback while retaining the high-water. This bounds repeated
candidate startup failure without adding a cloud health service.

## 7. Resource budgets

`E0RuntimeLimits` keeps limits release-owned and prevents a patch from raising
its own limits. The hardened surface covers instruction count, call depth,
closure invocations, capability calls, async resumes/deadline, value-node and
collection/string bounds, and active continuation limits. Exceeded limits
produce bounded runtime failures and disable the affected patched function;
they do not intentionally interrupt the host VM.

## 8. Runtime error isolation

Runtime faults now carry stable `E8xxx` categories for execution, budgets,
capability budgets, invalid opcodes, and source-map failures. The interpreter
rejects malformed execution, disables the affected slot, and leaves the
instrumented AOT guard available. Capability failures remain distinct from
guest throws. Stack overflow and out-of-memory remain fatal host conditions
and are not falsely claimed to be recoverable.

## 9. Source-mapped diagnostics

`E0OffsetMap`, `E0RuntimeSourceMap`, and `E0RuntimeSourceMaps` map a bounded
interpreter PC to function, logical URI, line, and column. Maps reject
absolute/file/http paths, duplicate entries, oversized tables, and malformed
coverage. Diagnostic messages are bounded and omit checkout paths and key
material. The source-map registry is a runtime diagnostics seam; it is not a
new Patch Format v1 required section and does not require source snapshots in
the application.

Representative codes are documented in [`docs/diagnostics.md`](../../diagnostics.md):
`E8101`, `E8102`, `E8103`, `E8401`, `E8501`, and `E8502`.

## 10. Parser fuzzing

The Patch Format v1 malformed corpus covers empty/truncated data, oversized
lengths, duplicate/unknown-critical sections, invalid canonical order, UTF-8,
timestamp, digest, signature, release, and runtime compatibility failures.
The deterministic parser corpus and bounded seeded mutations passed without
an uncaught process failure.

## 11. Verifier fuzzing

Verifier regressions cover baseline table bounds, duplicate function/capability
IDs, invalid references, jump targets, instruction counts, canonical sections,
and compatibility mismatches. Parser-valid but semantically invalid inputs
are rejected before active state mutation.

## 12. Interpreter fuzzing

The instrumentation corpus exercises malformed and near-valid arithmetic,
branches, loops, container accesses, capability declarations, invalid
opcodes, and explicit budget exhaustion. The 200-test instrumentation suite
passed on the active SDK and the full suite passed in the isolated adjacent
3.47.1/3.13.1 environment.

## 13. Lifecycle fuzzing

Lifecycle regressions cover malformed candidate/health records, both-copy
corruption, predecessor gaps, stale high-water, torn writes, orphan temporary
files, rollback state, and wrong-release state. The patch-loading suite passed
55 tests with one expected environment-gated CLI-artifact skip.

The current fuzzing evidence is deterministic corpus plus bounded seeded
regression, not a long-duration fuzz campaign.

## 14. Capability adversarial tests

Existing capability tests continue to reject undeclared capabilities, wrong
versions/schemas, execution-kind mismatches, forbidden policy classes,
oversized output, excessive calls, malformed async results, arbitrary
reflection, raw channels, FFI, and plugin enumeration. The capability
authority remains release-owned and configure-once.

## 15. Key rotation

`experiments/patch_loading/lib/src/key_lifecycle.dart` provides a bounded
policy model with active, retired, and revoked keys; patch, authority,
rollback, and recovery roles; canonical signed add/retire/recover commands; an
eight-key bound; and a 64-entry artifact ledger. It remains marked
`STANDALONE_SAFE_MODEL`, a standalone test/policy seam, not a runtime trust
authority.

Task 32 integrated trusted/retired/revoked keys, trust generation, release
identity, patch high-water, rollback state, and recovery metadata into
`E1PatchController`'s `state-v4` journal. That controller-owned journal
is the single durable trust/high-water authority; the standalone model must
not become a second authority or durable journal.

## 16. Key revocation

The policy model rejects new artifacts signed by retired keys, permits only
exact remembered artifacts after retirement, rejects all artifacts from
revoked keys, and requires the release-owned recovery anchor for replacement.
Unknown keys cannot self-authorize. Offline recovery is bounded and cannot
delegate another recovery anchor. The controller-owned `state-v4`
journal persists these trust/replay controls atomically with lifecycle state;
no separate runtime trust journal is used.

## 17. Anti-replay and recovery review

Base rollback and candidate recovery retain the monotonic `(sequence, digest)`
high-water. An old patch remains stale after rollback. Equal-sequence
equivocation, wrong release, wrong key, stale control, and replayed rollback
controls are rejected. Cleanup retains sequence, rollback, release, and key
state in the controller-owned `state-v4` journal. The standalone key
ledger exercises the same cross-feature policy as a test/policy seam; it does
not own or compete with the controller journal.

## 18. Android physical hardening evidence

The preserved Phase 1B physical Android evidence remains the authoritative
device record: Redmi Note 10 Lite, Android 16/API 36, arm64, release build;
automatic release/patch activation, health confirmation, restart persistence,
base rollback, and stale-sequence rejection passed. The final durable release
and 1,798-byte sequence-1 patch are recorded in
[`docs/PHASE_1B_REVIEW.md`](PHASE_1B_REVIEW.md) and
[`docs/research/developer-workflow.md`](../../research/developer-workflow.md).

The fresh Phase 1C retry confirmed the device after Wireless debugging was
manually re-enabled. The live target was the mDNS/TLS identity
`adb-ce57506c-N761V5 (2)._adb-tls-connect._tcp`, advertised at
`192.168.50.135:38217`, with Android 16/API 36 and arm64-v8a. The older
`192.168.50.135:39979` transport was stale; this is transport/endpoint churn,
not evidence that the device's Wireless debugging setting was permanently off.

The current fixture dependency `path_provider_android 2.3.1` built an automatic
Release APK successfully:

```text
51,869,536 bytes
SHA-256 72fb91d23cc4217e118f5884dcc0f338fb010d5d7c4a0a0261200fddb3617631
```

The APK install returned `Success`, but the live mDNS service disappeared before
launch. Therefore no new BASE, activation, restart, rollback, stale-replay,
invalid-artifact, or physical runtime-failure claim is made. The
`path_provider_android 2.3.1` compatibility question remains unresolved, and
the `2.2.23` fallback was not applied without reproducing the JNI failure.

This retry remains blocked after the bounded Android evidence:

```text
install                             → Success
live mDNS after install             → disappeared
BASE/lifecycle                      → NOT RUN
```

A later coordinator transport probe kept the installed release on the same
ADB serial while `adb_wifi_enabled=1` and `get-state=device` remained stable
across 12 samples. mDNS discovery alternated between empty output and stale/
live advertisements, so the observed failure mode is endpoint/discovery churn,
not a confirmed Wireless debugging shutdown. A bounded local v1 follow-up then
observed v1 polling, signed sequence-4 admission/health, tampered-payload
rejection, signed rollback, and stale-after-rollback rejection. The fixture's
visible result nevertheless remained base `price 540`, so this is supporting
transport/runtime evidence only; it does not close the Android behavior gate.
The exact follow-up record is retained in Task 34 and no Task 35 measurement
was started.

No new Android hardening or performance pass is claimed. The Flutter host also
reported an ADB mDNS serial parsing warning; no global SDK workaround was made.

## 19. iOS physical hardening evidence

The preserved Phase 1B physical iPhone XR evidence records automatic release,
signed activation, health confirmation, restart persistence, rollback, and
stale/rejection behavior. The environment used the existing development team
`CYT7A4VAZ3`, Xcode 26.6 Build 17F113, and the paired iOS 18.7.9 device.

The fresh Task 36 USB run closed the runtime-observation caveat on the connected
physical iPhone. It used iOS 18.7.9, Flutter 3.47.0, Dart 3.13.0,
XcodeBuildMCP 2.5.2, the AUVANA team `CYT7A4VAZ3`, and one signed Release
install through the existing `scripts/e1_ios_physical.sh` workflow. The app
was arm64-only with no kernel/dill JIT payloads.

The receipt sequence was physically observed and passed:

```text
base → patch-active → restart-required-1 → patch-persisted
→ invalid-rejected → rolled-back → restart-required-2
→ rollback-persisted → complete
```

The signed patch reached healthy patched behavior (`price 450`), survived the
first process restart, rejected a tampered signature without displacing the
active patch, rolled back to signed base (`price 540`), and retained base after
the second restart. The run performed exactly one install, three launches, and
two successful stops. Evidence is retained under
`fixtures/flutter_conformance_app/.dart_tool/e1_ios_runs/phase1c-ios-caveat-20260822-1/`.

This is bounded physical lifecycle evidence from the existing E1 USB harness;
its envelope is not being relabeled as a Patch Format v1 artifact. The current
CLI/Patch Format v1 LAN-delivery observation remains separate and is not claimed
as a fresh iOS v1 transport result. No App Store, production-signing, or policy
approval claim is made.

The current device audit also reports the paired iPhone as connected and
available under the same development team. Accordingly, iOS has fresh bounded
physical lifecycle evidence, but the current CLI-generated Patch Format v1 LAN
transport remains a separate unvalidated caveat for this review; the historical
Phase 1B v1 LAN result is preserved and not discarded.

## 20. Dispatch benchmarks

The preserved Phase 0B/Phase 1B host dispatch measurement was:

```text
stock direct:             2.0103 ns
instrumented unpatched:   6.0329 ns
absolute delta:           4.0226 ns
```

No new physical stock/instrumented/patched dispatch measurement was completed
in this checkpoint. The Phase 1C host lifecycle benchmark measured 10,000
post-verification admission checks at median/p95 `1,188/8,629 µs` on
3.47.0/3.13.0 and `1,113/8,545 µs` on 3.47.1/3.13.1; this is not a frame-time
or interpreter-throughput claim.

## 21. Startup measurements

The preserved Android sample recorded `TotalTime 489 ms` for a cold launch of
the instrumented release. No controlled Phase 1C stock versus instrumented
versus active-patch first-frame measurement was obtained. The lifecycle host
benchmark's startup restore/signature-apply stage was median/p95 `5,792/6,437
µs` on 3.47.0 and `5,778/6,473 µs` on 3.47.1; Flutter engine startup is not
included.

## 22. Memory measurements

The preserved Android process sample recorded `78,997 KiB` PSS and `179,984
KiB` RSS. These are not a controlled delta. The Phase 1C host benchmark
reported noisy whole-process RSS snapshots of `254,246,912` bytes and
`254,033,920` bytes on the two SDK runs; those values are not attributed to
the lifecycle model. New physical memory evidence remains open.

## 23. Binary growth

The Phase 1B stock-versus-instrumented fixture comparison remains the measured
baseline: approximately `+6.07%` Android and `+7.04%` iOS. Phase 1C did not
claim a new growth percentage because no controlled post-hardening binary
comparison was completed. No evidence currently indicates a material
regression beyond that baseline.

## 24. Path-provider pin finding

The `path_provider_android 2.2.23` pin remains. The newer JNI-backed path
previously reproduced a release bootstrap crash before the engine JNI bridge;
the pinned implementation passed the physical Android workflow. The pin was
not removed without a new physical Android validation. iOS uses the private
Foundation application-support implementation.

## 25. Adjacent Flutter/Dart compatibility

| Flutter / Dart | Status | Evidence |
| --- | --- | --- |
| 3.47.0 / 3.13.0 | `SUPPORTED` | Active SDK, doctor, fixture analysis, Phase 1B release/device evidence, current CLI/runtime validation. |
| 3.47.1 / 3.13.1 | `SUPPORTED_WITH_LIMITATIONS` | Isolated Puro environment; fixture analysis, 200-test instrumentation suite, key lifecycle tests, and host benchmark passed. No adjacent physical release/device run. |
| 3.44.9 / 3.12.2 | `UNSUPPORTED` | Installed only for inspection; below the repository's Dart 3.13 constraint and not tested for Phase 1C. |
| Other versions | `NOT_TESTED` or fail-closed unsupported | No evidence used to broaden support. |

Analyzer/parser, language-version, package-config, and generated-source drift
remain maintenance risks for Architecture B.

## 26. Patch Format v1 conformance

Patch Format v1 is unchanged. CLI-generated artifacts continue to pass
canonical ordering, bounds, digest, signature, exact release, runtime, and
function-table checks. Malformed corpus tests passed. No source-map, lifecycle,
or key-lifecycle requirement caused a protocol mutation or v2 proposal.

## 27. Capability v1 conformance

Capability contract v1 is unchanged and closed. Generated artifacts declare
only release-owned capabilities, and runtime policy rejects undeclared,
wrong-version, wrong-schema, forbidden, and execution-kind-mismatched calls.

## 28. Threat-model findings

The threat model now covers durable-state corruption, torn writes, replay and
rollback abuse, key compromise/rotation, malformed artifacts, budget abuse,
source-map leakage, symlink/path traversal, cleanup, local server responses,
and rooted-device limits. Controls are fail-closed where implemented. A
rooted/fully compromised device, local private-key compromise, and production
transport/authentication remain out of scope.

## 29. Remaining risks

- Boundary fault injection is deterministic host testing, not physical power
  loss or filesystem durability proof.
- The first fresh Android retry is blocked after install because the live mDNS
  service disappeared before launch; a later bounded serial/v1 follow-up
  diagnosed discovery churn but did not show changed visible behavior, so no
  2.3.1 lifecycle closure is claimed.
- Fresh iOS physical lifecycle evidence now passes through the bounded E1 USB
  harness; current CLI/Patch Format v1 LAN delivery remains separately
  unvalidated on iOS.
- New physical dispatch, first-frame, memory, and post-hardening binary
  attribution measurements remain open.
- The adjacent SDK family has limited evidence only; full release/device
  support is not claimed.
- No long-duration fuzz campaign has been run; the required deterministic and
  bounded seeded regression corpus is the current evidence.

## 30. Next-phase proposal

Do not start Phase 1D yet. Continue only the remaining Phase 1C closure work:

1. complete Android physical hardening and Task 35 controlled runtime
   measurements when the device is available;
2. rerun the consolidated review and ask the maintainer to choose whether the
   Phase 1C gate is closed.

No cloud, hosted product, rollout, dashboard, account, enterprise, React
Native, Flutter-fork, Dart-fork, or Kernel work is proposed or authorized by
this report.

## Validation record

The consolidated checks executed for this checkpoint were:

```text
dart format --output=none --set-exit-if-changed cli packages experiments benchmarks test
dart analyze --fatal-infos                 # root and all package/experiment boundaries
dart test -j 1                             # root, CLI, packages, instrumentation, patch_loading
puro --env=phase1c-3471 dart test -j 1     # full instrumentation suite
puro --env=phase1c-3471 flutter analyze --no-pub  # fixture
Markdown relative-link check
trailing-whitespace check
bash -n scripts/*.sh
Python syntax check for scripts/e1_ios_evidence_server.py
```

Results: all executed checks passed; the patch-loading suite retained one
expected skip because `HYFENS_CLI_PATCH`, `HYFENS_CLI_RELEASE`, and
`HYFENS_CLI_PUBLIC_KEY` were not supplied. The fresh iOS physical Task 36
receipt assertions passed. The Android retry built and installed the current
2.3.1 release but stopped when live mDNS disappeared before launch; no Android
lifecycle or measurement claim was made. No Phase 1D work was started.

## Reconciliation history

- 2026-08-22: Reconciled current-state wording with completed Tasks 32 and 33.
  The controller-owned `state-v4` trust/high-water journal is integrated
  and authoritative; the standalone key-lifecycle model remains a test/policy
  seam. The recommendation remains `CONTINUE PHASE 1C`, with only the Android
  physical lifecycle and Task 35 measurement gates left open.

## Android behavioral gate closure — 2026-08-22

The fresh automatic Android workflow was subsequently completed on the
physical Wi-Fi ADB target without changing Architecture B, Patch Format v1, or
capability v1:

```text
device:       Redmi Note 10 Lite / curtana
Android:      16 / SDK 36 / arm64-v8a
serial:       adb-ce57506c-N761V5 (2)._adb-tls-connect._tcp
release:      sha256:f574b76233a18268441011262a7bde7b414ef38e27ca231054e3c95625405359
APK:          51,951,456 bytes; SHA-256 24ec7c24875b7e2ce5f9c97020986a48bad812193f0c03d4d89b8666734fc594
patch:        sha256:e2829df698c9a185e948b12a5fb732664cf59cdd8953385a3663e6845f2c8c92
patch:        2,069 bytes; SHA-256 0c8270441ffe9b270745f9ac2f7c341e34d8d29fc57436fd6304ae8f431d1a32
```

Physical observations were: BASE `price: 540`; generated-controller
`pendingHealth → healthy`; normal button invocation of the patched function
with visible `price: 651`; restart persistence of the patched result; signed
base rollback with sequence/high-water `1` retained; restart persistence of
BASE behavior; HTTP 404 `NO_UPDATE` at the delivery boundary for stale
sequence 1 after rollback; and payload-digest rejection of a physically
delivered corrupted artifact while BASE remained active. The stale valid bytes
were not delivered into the controller, and invalid replacement retention
while a healthy patch remained active was not tested. The fresh app was
installed once for this sequence and was not reinstalled or data-cleared
between lifecycle stages.

This closes the Android automatic behavioral/lifecycle gate. The bounded
physical valid-runtime-error case and Task 35 dispatch/startup/memory/APK
measurements remain open. The local corrupt-response server was a temporary
development test only; it is not production transport evidence. The prior iOS
USB harness evidence remains valid but is not relabeled as current automatic
CLI/Patch Format v1 LAN evidence.

The recommendation remains `CONTINUE PHASE 1C`; no Phase 1D or product work is
started by this addendum.

## Android behavioral-application follow-up — 2026-08-22

The remaining Android issue was narrowed on the host before any physical
closure claim. The visible fixture path is
`runApp → PriceScreenState.build → calculatePrice(6, 1) → Text('price: 540')`.
The automatic generated integration and the archival manual E1 bootstrap had
been creating separate controllers over static/global E0 runtime state. A
second controller could reset the installed slot while the first controller
still reported `PATCH` and healthy. Health also does not invoke the business
function, and the generated controller did not drive the archival screen's
manual status listener.

Task 37 added a process-local E1 runtime lease, generated-start single-flight,
and automatic-fixture suppression of the archival manual initialization. The
focused regression preserved a changed host result (`450`) and rejected the
conflicting controller before it could clear the slot. A fresh automatic
release/patch/inspect/verify host run passed for release
`sha256:c9283534fe98c41d1318fcb88752bfccf1c2652cae67c8d2c82e3cad64ec3e94`.

Historical pre-closure checkpoint. This follow-up is not physical Android
evidence. That checkpoint had no ADB
device or mDNS service, so post-fix install, patched visible behavior, restart
persistence, rollback, stale-patch rejection, and runtime-error isolation
remain open. Task 35 remains blocked. The Phase 1C recommendation stays
`CONTINUE PHASE 1C`; no Phase 1D or product work is authorized.

After additional bootstrap-marker and failed-initialization cleanup
hardening, a fresh host release
`sha256:f574b76233a18268441011262a7bde7b414ef38e27ca231054e3c95625405359`
also built successfully (40 functions, 24 source units), and its 2,069-byte
Patch Format v1 artifact verified against the exact release. This remains
host/build evidence only; the physical Android gate and Task 35 remain open.

## Final evidence closure — 2026-08-23

This addendum is the current state of the Phase 1C review. Earlier sections
are preserved historical checkpoints and are not silently reclassified.

### Recommendation

`PROCEED TO PHASE 1D WITH CONDITIONS`

The Phase 1C hardening gates are complete under the bounded scope. The
recommendation is a maintainer decision gate only: no Phase 1D implementation,
cloud, hosted delivery, dashboard, rollout, account, enterprise, or other
product work was started.

### Architecture and protocol status

Architecture B is unchanged. Patch Format v1 and capability contract v1 are
unchanged and conformant. The controller-owned `state-v4` journal remains the
single durable trust/high-water authority. The Task 37 process-local runtime
lease, generated-start single-flight, and archival-manual-bootstrap suppression
remain the bounded fix for the mixed-controller E0 reset defect.

### Android physical evidence

The exact-release runtime-fault run used Redmi Note 10 Lite / Android 16 /
SDK 36 / arm64-v8a over direct Wi-Fi ADB `192.168.50.135:39545`:

```text
release:       sha256:86bfc9c4ef76813ba68b8627b02d5e34938d5f11e57b79930bdf0d6f2c127809
APK:           51,967,840 bytes; SHA-256 7f34e8844f120a9a906a33ccb8e9d6db5829e02b1f554136f61fba3b92a94d7
patch:         sha256:0abb984083033cecb0257211178b78a42369635d9f5891b1f2adf8dc57f47221
patch bytes:   2,061; SHA-256 8c85a035e1ed27e9dfca5c2c06ac225406c197b920898a6fdf922c4ba55d9336
sequence:      1; function calculatePrice; slot 37
```

The valid signed patch passed exact-release admission and faulted only when
invoked. The physical log reported `E8101` instruction-budget exhaustion at
`package:conformance/main.dart`, PC 41. The process remained alive, the
failing slot was disabled, and the AOT fallback produced `quantity: 7`,
`price: 630`. No absolute path, temporary path, private key, credential URL,
or unbounded guest data was emitted. Line/column was not present in this
physical record. The host exact-artifact regression
`experiments/patch_loading/test/cli_runtime_fault_test.dart` also passed.

The earlier Android automatic lifecycle remains the accepted BASE → signed
activation/health → visible `540 → 651` → restart persistence → signed base
rollback/high-water retention → rollback persistence → stale delivery-boundary
`NO_UPDATE` → corrupt `P1041` rejection sequence. Direct stale-valid-byte
delivery after rollback and invalid replacement retention while a healthy patch
is active remain explicitly untested physically.

### Task 35 Android performance evidence

Task 35 used fixture `phase1c-android-bench`, package
`dev.hyfens.androidbench`, Flutter 3.47.0 / Dart 3.13.0, Release mode, the
exact release `sha256:102ed130cdd1d23d03e235230dd7993486da2b0fa4598e243d80d9e2adcf90b4`,
and a 1,858-byte signed sequence-1 patch. Each dispatch variant used
10,000,000 iterations, two warmups, and 15 timed process-isolated samples;
checksums were independently validated. The normalized capture and reduced
report are preserved in
[`phase-1c-android-2026-08-23`](../../research/evidence/phase-1c-android-2026-08-23).

| Measurement | Stock | Instrumented BASE | Active patch |
| --- | ---: | ---: | ---: |
| dispatch median | 17.205 ns/call | 20.2034 ns/call | 1,216.6529 ns/call |
| dispatch p95 | 24.9255 ns/call | 28.536 ns/call | 1,242.1573 ns/call |
| `am start -W` TotalTime median | 368 ms | 362 ms | 391 ms |
| ready PSS median | 72,755 KiB | 85,719 KiB | 77,992 KiB |
| postDispatch PSS median | 79,259 KiB | 92,230 KiB | 87,302 KiB |

The unpatched instrumentation delta was +2.9984 ns/call / +17.4275% median
versus direct AOT. The interpreted hot-loop median was 70.715× direct and
60.220× unpatched; this is not a native-equivalent or application-level
latency claim. Active-patch launch completion was +23 ms / +6.25% versus stock
in this sample. Android `am start -W` did not expose `ThisTime`, so no exact
first-frame claim is made. Memory is whole-process `dumpsys meminfo` PSS/RSS,
not interpreter-only attribution.

Comparable APKs were:

```text
stock:        43,382,412 bytes; SHA-256 4ae8791cc4ed67810ede045d1b6e19bf271cd39bfafd1b15eb7bf3c1d6e2f41d
instrumented: 46,659,212 bytes; SHA-256 bfa25f0daf7ea184dc14b6e9cd54932ac44105e426e485881f559e2978854250
growth:       +3,276,800 bytes / +7.5533% (DERIVED)
patch:        1,858 bytes; SHA-256 45af9ed4c6414c7a4278c6cd0c5304bed7238894c2abf9735225c6d927f083c8
```

This is a same-fixture/toolchain/mode/ABI result, close to the earlier
directional baseline. No universal size threshold is claimed.

### iOS physical evidence and boundary

The accepted physical iOS E1 USB lifecycle remains PASS: one signed Release
install on iOS 18.7.9 / arm64 using Xcode 26.6, team `CYT7A4VAZ3`, activation,
health, restart persistence, invalid-signature rejection, signed rollback, and
rollback persistence. Fresh automatic CLI/Patch Format v1 LAN physical iOS
delivery remains `NOT CLAIMED`; no App Store or production-signing claim is
made. No iOS performance result is inferred from Android.

### Compatibility and security

Flutter 3.47.0 / Dart 3.13.0 remains `SUPPORTED`. Flutter 3.47.1 / Dart 3.13.1
remains `SUPPORTED_WITH_LIMITATIONS` from the isolated analyzer,
instrumentation, fixture, and host evidence; no adjacent physical-device
claim is made. Older 3.44.9 / Dart 3.12.2 remains `UNSUPPORTED` under the
current Dart constraint. Other versions remain `NOT_TESTED`/fail-closed.

The deterministic malformed parser/verifier/interpreter/lifecycle corpus,
resource-budget, source-map, capability-adversarial, key-lifecycle,
anti-replay, rollback, cleanup, and fault-injection suites passed. This is not
a long-duration fuzz or physical power-loss campaign. Durable state, replay,
rollback, path traversal, cleanup, local transport, and rooted-device limits
remain documented in the threat model. A compromised private key, rooted or
fully compromised device, and production transport/authentication remain out
of scope.

### Consolidated validation

Executed for this closure:

```text
dart format --output=none --set-exit-if-changed <affected Dart scope>  PASS
dart analyze --fatal-infos benchmarks packages/flutter_integration \
  experiments/instrumentation experiments/patch_loading                 PASS
root tests                                                               1 passed
CLI tests                                                                32 passed
compiler / instrumenter / patch_format / runtime                         1 / 2 / 12 / 5 passed
Flutter integration tests                                                8 passed
instrumentation suite                                                    204 passed
patch-loading suite                                                      59 passed, 2 skipped
exact CLI-generated runtime-fault regression                             1 passed
Android reducer self-check and measured reduction                        PASS
```

The two patch-loading skips are the existing environment-gated cases; no
failure was hidden. Adjacent SDK evidence is preserved from the bounded
3.47.1/3.13.1 run. No global Flutter/Dart installation or source tree was
modified.

### Remaining conditions and Phase 1D proposal

The maintainer should require, before any broader claim, that Phase 1D remain
runtime/integration work only and preserve Architecture B, Patch Format v1,
capability v1, exact release binding, bounded capabilities, fail-closed
recovery, and no product infrastructure. The following remain explicit
limitations: fresh automatic CLI/Patch Format v1 LAN iOS delivery, physical
power-loss testing, long-duration fuzz campaigns, direct stale-valid-byte
physical delivery after rollback, healthy-patch replacement retention, and
full adjacent-SDK physical matrices. No Phase 1D work is executed by this
review.
