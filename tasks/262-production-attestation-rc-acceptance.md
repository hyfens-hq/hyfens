# Task 262 — Production attestation and RC release acceptance

Status: [x] Completed

## Goal

Verify the deployment-owned Google Play Integrity and Apple App Attest
boundaries against the existing admission-bound runtime receipt protocol, then
run the Task 260 release-candidate process and publish at most one immutable
stable public release if the candidate is accepted. Keep development
acceptance non-billable and live billing disabled.

## Scope and Non-goals

Scope:

- re-review the public receipt contract and private provider verifier seams;
- verify exact challenge, application, environment, installation, and release
  binding for Play Integrity and App Attest;
- run deterministic provider, replay, outage, trust-policy, PostgreSQL, and
  private Cloud regressions already present in the reviewed branches;
- re-probe the available physical-device and store/provider environment;
- prepare and accept one release candidate through the Task 260 process;
- publish one stable release only if the RC boundary is satisfied, and verify
  its public distribution channels; and
- record external provider/device gates and clean task-owned state.

Non-goals:

- redesigning the admission-bound receipt protocol or the canonical
  `successful_patch_install` event;
- changing Cloud usage settlement, pricing, quota, payment orchestration, or
  existing commercial projections;
- enabling live checkout or live overage collection;
- weakening production trust for sideloaded/development applications;
- fabricating Play Integrity/App Attest credentials, provider verdicts,
  Android signing, or store acceptance;
- modifying Kavach360 to avoid Hyfens limitations or provider requirements; and
- reopening Tasks 247, 253, or 260 or creating another microtask.

## Owner

Hyfens release and runtime-trust coordinator.

## Dependencies

- Public `origin/main` containing `76d2f82` and `6c6c2d3`.
- Stable public release `v0.1.9` and its immutable artifacts.
- Private Cloud feature branch containing `83e8909` and the reviewed
  deployment-owned attestation verifiers.
- Task 260 release governance, changelog extraction, and RC checklist.
- Deployment-owned Play Integrity credentials/store context and Apple App
  Attest configuration if live provider acceptance is attempted.

## Assumptions

- The public repository exposes provider-neutral runtime interfaces; provider
  credentials and commercial production policy remain deployment-owned.
- Deterministic verifier doubles are valid for contract/security tests only and
  cannot establish production provider acceptance.
- Acceptance/test receipts remain operational telemetry with zero financial
  usage units.
- Android signing, Play distribution, App Attest configuration, and managed
  Cloud credentials may remain external gates.
- The public primary checkout and private Cloud primary checkout contain
  unrelated developer work and must not be reset, cleaned, or overwritten.

## Work Items

- [x] Inspect current public tags, version, release governance, and receipt
  boundary.
- [x] Inspect the private Google Play Integrity and Apple App Attest verifier
  implementations, policy composition, and existing security tests.
- [x] Run the deterministic provider/security, private Cloud, PostgreSQL, and
  self-host acceptance regressions.
- [x] Re-probe provider credentials, physical devices, Kavach360 project
  prerequisites, and store/provider context without reusing stale results.
- [x] Classify provider and device gates without weakening policy or creating
  fake evidence.
- [x] Prepare and run one release candidate using changelog-derived notes.
- [x] Publish and verify one immutable stable public release after RC
  acceptance.
- [x] Update this record with the exact matrix, commits, distributions, and
  cleanup evidence.

## Validation

Planned affected validation:

- public receipt/runtime tests, CLI analysis/tests, release-note tooling,
  archive/inventory checks, MCP/self-host checks, and secret scan;
- private Cloud attestation, receipt, PostgreSQL, commercial, projection, and
  reconciliation suites on the existing feature branch;
- official-provider documentation cross-check against request/nonce binding,
  application identity, replay, and outage handling; and
- physical-device/build probes only where the current environment and
  project-owned configuration permit them.

Record every command, pass/failure, skipped gate, and reason in the outcome
section. Do not claim production provider acceptance from deterministic tests.

## Next Action

No further action remains in this finite task. Any future live Play Integrity,
App Attest, Android signing/store, or deployment-owned production acceptance
requires the appropriate external configuration and a separately approved
scope. Do not reopen this task to add provider credentials or enable billing.

## Blockers

External gates classified at closure:

- Play Integrity production verification: no deployment credentials, Play
  distribution context, or production Kavach360 signing configuration was
  available.
- App Attest production verification: the online iPhone was re-probed, but the
  private app has no App Attest enrollment/configuration for this campaign and
  no deployment provider configuration was available.
- WinGet publication and native Scoop execution remain external platform
  gates.

These gates do not weaken the production policy, do not make acceptance
receipts billable, and do not block the public generic receipt protocol or the
stable RC-qualified release.

## Outcome

Final disposition:

```text
HYFENS PRODUCTION ATTESTATION + RC — COMPLETE WITH EXTERNAL GATES
```

The public generic receipt implementation was already present in `76d2f82`
and the PostgreSQL acceptance record in `6c6c2d3`. The private deployment-owned
provider implementation in `83e8909` was re-reviewed: Play Integrity uses the
official decode endpoint and validates the signed enrollment hash, package,
certificate, version, licensing/device verdicts, freshness, and exact scope;
App Attest validates production attestation/assertions, RP/app identity,
nonce, key binding, and monotonic counters. Deterministic provider/security
tests and the existing Cloud settlement tests passed; no provider credential
or store-context evidence was fabricated.

The accepted RC was `v0.1.10-rc.2`, published with six native archives,
artifact inventory, SHA256SUMS, curated release notes, and container images.
RC1 remains an immutable failed candidate tag; its CLI workflow failure was the
relative changelog-path defect fixed before RC2. Stable `v0.1.10` was then
published once from public main commit `7871868` and verified through GitHub,
curl, Homebrew, and the remote Scoop manifest. The public Homebrew install
reports `hyfens 0.1.10`; native Scoop execution is not available on this
machine.

The production policy remains fail-closed and deployment-owned. Development
acceptance is explicitly non-billable, `successful_patch_install` remains the
only canonical usage event, and live checkout/overage collection remain off.

## Acceptance Matrix

| Gate                             | Result |
| -------------------------------- | ------ |
| Android verifier implementation  | PASS |
| Apple verifier implementation    | PASS |
| Exact challenge binding          | PASS |
| App identity verification        | PASS |
| Cross-installation rejection     | PASS |
| Cross-app rejection              | PASS |
| Cross-environment rejection      | PASS |
| Attestation replay rejection     | PASS |
| Trust downgrade protection       | PASS |
| Provider outage fail-closed      | PASS |
| Acceptance remains non-billable  | PASS |
| Production billability policy    | PASS |
| Cloud settlement regression      | PASS |
| Developer concurrency regression | PASS |
| Starter/Team regression          | PASS |
| Annual monthly reset regression  | PASS |
| Org pooling regression            | PASS |
| Existing UNKNOWN org unchanged   | PASS |
| CHANGELOG finalized              | PASS |
| Version classified               | PASS |
| RC built                         | PASS |
| RC public tests                  | PASS |
| RC PostgreSQL tests              | PASS |
| RC private Cloud tests           | PASS |
| iOS attestation acceptance       | EXTERNAL_GATE |
| Android attestation acceptance   | EXTERNAL_GATE |
| Release notes generated          | PASS |
| Stable release                   | PASS |
| GitHub/curl                      | PASS |
| Homebrew                         | PASS |
| Scoop                            | NOT_APPLICABLE |
| WinGet                           | EXTERNAL_GATE |
| Live billing OFF                 | PASS |
| Cleanup                          | PASS |

## Validation Evidence

- Public package analysis passed for `cli`, `packages/compiler`,
  `control_plane`, `flutter_integration`, `instrumenter`, `patch_format`, and
  `runtime`. The root aggregate analysis still reports pre-existing fixture
  issues and is not a configured package gate.
- Public CLI tests passed `192/192`; Flutter integration passed `55/55`;
  compiler/instrumenter/patch-format/runtime targeted suites passed; focused
  public PostgreSQL receipt/reconciliation suites passed `17/17` and `15/15`.
  The optional full control-plane PostgreSQL run exposed nine unrelated
  historical P3E5/Task 67 applicability-vector failures; no receipt or
  attestation test failed.
- Private Cloud API passed `78/78`, commercial package passed `70/70`, and
  the real PostgreSQL migration, two-process quota/dedup race,
  response-loss/fresh-store retry, projections, reconciliation, and
  self-host-boundary checks passed. Local PostgreSQL used `sslmode=disable`
  only for the disposable non-TLS test container.
- Fresh environment probes found one online physical iPhone, one Android
  emulator, no physical Android device, no provider credential/configuration,
  no App Attest integration in the untouched private app, and no legitimate
  Kavach360 release signing configuration. Kavach360 was not modified.
- RC2 workflow `34159741898` and container workflow `34159741850` passed. The
  stable CLI workflow `34160411780` and container workflow `34160411768`
  passed. Stable artifact checksums all verified from the downloaded public
  `SHA256SUMS`.
- Public curl installation resolved the stable release and reported
  `hyfens 0.1.10`; Homebrew upgraded from `0.1.9` to `0.1.10` and `brew test`
  passed. Remote Homebrew and Scoop metadata point to the stable artifact
  URLs and verified hashes. WinGet and native Scoop execution were not
  available.
- Live billing configuration remains disabled; no production charge or
  overage collection was attempted.

## References

- `packages/control_plane/lib/src/runtime_receipts.dart`
- `packages/flutter_integration/lib/src/runtime_attestation.dart`
- `docs/runtime/trusted-install-receipts.md`
- `docs/releases/releasing.md`
- `CHANGELOG.md`
- Private Cloud `apps/cloud-api/lib/src/attestation/google_play_integrity.dart`
- Private Cloud `apps/cloud-api/lib/src/attestation/apple_app_attest.dart`
- Google Play Integrity standard requests and verdict documentation
- Apple App Attest server validation documentation

## History

- 2026-09-08 — Reserved task 262 after confirming task 261 is the highest
  public task number. Created this record in an isolated worktree from
  `origin/main`; unrelated primary-checkout changes remain preserved.
- 2026-09-08 — Re-ran provider/security, Cloud, PostgreSQL, package-level
  analysis, and fresh device/provider probes; classified live provider and
  store/signing prerequisites as external gates.
- 2026-09-08 — Published signed RC tags `v0.1.10-rc.1` and `v0.1.10-rc.2`;
  RC2 passed the six-archive CLI/container workflows after correcting the
  workflow’s repository-root changelog path and prerelease metadata handling.
- 2026-09-08 — Published signed stable `v0.1.10`, verified public artifacts,
  curl/Homebrew/Scoop metadata, public install, and live billing-off state.
- 2026-09-08 — Completed the matrix with external provider/WinGet gates and
  prepared task-owned cleanup for closure.
