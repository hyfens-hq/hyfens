# Final Product Readiness Review

Date: 2026-08-30
Review type: final closure of the current workstream
Task-creation mode: **OFF**

## Final recommendation

**READY WITH EXTERNAL GATES**

The bounded local/research product has no evidence of a current release-blocking
defect. It is ready to advance within that boundary. Hosted/provider deployment,
database/object-store integration, and store/legal acceptance remain external
gates; this review does not claim production SaaS or store readiness.

## Decision boundary

This review covers the current local Phase 1B toolchain, local/single-node
control plane, dashboard fixture, and bundled Waypoint demo. It closes
historical `Task 209`, which was the final task in this execution sequence.

No Task 210 or other numbered task was created. Optional assertions, broader
coverage, and non-critical review observations are not being converted into
new tasks.

## Current implementation status

- Task 209 is **Completed**. Its implementation change is limited to the
  bundled Flutter widget test in
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`; it exercises
  the local demo offer, planning form, submission, navigation to Trips, and the
  confirmation message.
- The task received a strict implementation review with no findings.
- The final closure made one safe documentation correction in
  [`README.md`](../../../README.md): the Task 41 local/self-hosted milestone is now
  described as complete rather than “in progress”. No runtime or protocol code
  was changed during closure.
- The repository contains 212 numbered task files: 205 completed, 6 blocked
  AWS-gate records (Tasks 78, 80, 81, 82, 83, and 84), 1 cancelled, and 0
  active. The stated 206 count reconciles to the non-AWS records (205 complete
  plus 1 cancelled); the six AWS records remain separately classified as
  external blockers.
- The repository has no resolvable Git `HEAD`; conclusions therefore use the
  task-owned file, direct source inspection, documented evidence, and recorded
  validation results rather than a fabricated commit comparison.

## Product-level acceptance assessment

The current product boundary is explicit: the CLI and control plane are local
or single-node reference implementations, and the Waypoint application is a
bundled local demo. [`docs/getting-started.md`](../../getting-started.md) and the root
[`README.md`](../../../README.md) do not make production deployment or store-policy
claims.

The following critical workflows were reviewed at product level:

- Waypoint startup in demo mode, typed local JSON loading through AlphaX, home
  loading/error paths, search, saved items, offer dismissal/restoration, the
  planning form, submission, and Trips confirmation.
- Waypoint activity streaming/cancellation, settings/theme/media controls,
  permission-state presentation, responsive navigation, and asset/video
  surfaces through the existing fixture source and test suite.
- Local CLI release, patch, inspect, verify, rollback, cleanup, and the local
  control-plane boundary using the existing task and documentation evidence.
- Organization-scoped operator overview access, credential scope/expiry/revocation
  checks, application/environment scoping, and loopback-only dashboard proxy
  behavior.
- The documented P2 PostgreSQL/S3-compatible shape and AWS provider profile,
  with their explicit non-production and acceptance-gate boundaries.

No evidence showed a required workflow in the current local boundary failing,
data corruption, cross-tenant disclosure, or a broken security invariant.

## Architecture and security invariants reviewed

- The Waypoint UI uses Riverpod state providers over a repository/data-source
  boundary. JSON is decoded into typed domain values; AlphaX data access has
  bounded timeouts and cancellation support.
- Search uses a generation guard for out-of-order results. Activity refresh
  checks cancellation and mounted state. UI submission records the planning
  state before the sheet closes, and the Trips page renders the resulting
  confirmation.
- Control-plane authorization validates token material, revocation, expiry,
  credential kind, scope, organization, application, and environment. The
  operator overview filters tenant-owned records before decoding and bounds
  returned collections.
- The local HTTP adapter does not treat forwarded headers, host, or request ID
  as authorization signals. The dashboard is read-only and keeps the supplied
  credential out of URLs and browser storage.
- Earlier Phase 0B evidence documents signed-bytes verification, binding,
  replay/equivocation rejection, typed-value validation, bounded execution,
  atomic activation, durable high-water/LKG recovery, and fail-closed base
  fallback for the declared runtime support matrix.

These are bounded engineering claims. They are not a claim that arbitrary
Flutter code, a public hosted service, or a store submission is production
ready.

## Validation performed

Validation was limited to the changed feature, its directly affected fixture,
critical local suites, and one repository-level test pass:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart`
  — **PASS**, 1 file unchanged.
- `flutter analyze test/waypoint_app_test.dart` — **PASS**, no issues.
- Task 209 named widget test — **PASS**, `+1`.
- Complete changed `waypoint_app_test.dart` suite — **PASS**, `+71`.
- Complete `fixtures/flutter_conformance_app` Flutter suite — **PASS**, `+119`.
- Root `dart test` — **PASS**, `+1`.

The critical suite results were recorded without hiding failures:

- `cli`: `+52 -1`. The one failure was a 30-second concurrent process-test
  timeout while starting `dart run bin/tool.dart --version`; the same test
  passed in isolation with `+1` in about 7 seconds. This is test-runner/build
  contention evidence, not evidence that the version command is functionally
  wrong.
- `packages/control_plane`: `+233 ~34 -15`. The targeted failing tests use
  fixed fixture times on 2026-08-24 while the current wall clock is
  2026-08-30; production authorization defaults to the wall clock, so expired
  fixture credentials are rejected. The failures identify test-harness clock
  determinism and stale fixture data, not a demonstrated product workflow
  failure.
- The repository's PostgreSQL and S3-compatible integration cases were skipped
  because the required `HYFENS_TEST_POSTGRES_URL` and `HYFENS_TEST_S3_*`
  environments were not configured.
- No AWS or production hosted-provider acceptance run was performed. A
  separately authorized Hetzner demo deployment was completed after this
  closure review; its evidence is recorded below and does not establish
  production/provider acceptance. No Task 209 code required that acceptance,
  and the repository records it as approval- and environment-gated.
  Prior documented Android and iOS physical-device evidence remains available
  in [`docs/PHASE_0B_REVIEW.md`](PHASE_0B_REVIEW.md); no new device run was
  required for this test-only task.

## Remaining observations and classification

Each remaining observation is assigned exactly one category.

### A. RELEASE BLOCKER

**None found.** There is no reproducible evidence in this closure of a broken
required local workflow, data-integrity failure, tenant/security-boundary
violation, or required acceptance criterion failure.

### B. EXTERNAL / ENVIRONMENT BLOCKER

- Tasks 78, 80, 81, 82, 83, and 84 remain blocked on an approved AWS account or
  identity, current cost/maintainer approvals, and an AWS CLI session. Their
  scope is the disposable AWS/provider acceptance path, not the current local
  product boundary.
- PostgreSQL/S3 integration evidence needs the configured test services and
  credentials. The absent environment caused skips, not an implementation
  failure.
- Public hosting, public TLS/reverse-proxy acceptance, store/legal review, and
  provider acceptance are external gates for a later hosted or store phase.

### C. BACKLOG / HARDENING

- Make control-plane tests derive fixture times from an injected clock or use
  current deterministic dates so the critical suite does not expire its own
  credentials.
- Isolate the CLI process test from concurrent build-hook contention or make its
  timeout behavior deterministic.
- Complete the security/threat-model, key-custody/revocation, protected
  monotonic-storage, crash-loop, capability-permission, cancellation, and
  profiling work identified by the Phase 0B review before any production claim.
- Expand the read-only local dashboard only if the product boundary later
  requires human RBAC, mutation controls, fleet telemetry, or hosted release
  management.

These are backlog items and do not justify a new numbered task in this closure.

### D. ACCEPTED LIMITATION

- The control plane and P2 Compose stack are bounded local/single-node fixtures,
  not HA, internet-scale, or hosted services.
- AWS/S3 compatibility and local object storage do not constitute provider,
  availability, public-ingress, or production-readiness evidence.
- The Waypoint runtime exercises a declared bounded support matrix, not
  arbitrary Flutter semantics.
- The dashboard is intentionally static and read-only; it is not a human
  session/RBAC or release-control product.
- The repository makes no App Store or Google Play policy-compliance claim.
- Network mode in the Waypoint demo requires an explicit base URL; demo mode is
  local and does not silently make network requests.

### E. NO ACTION

- Hypothetical extra assertions, finer-grained test decomposition, optional
  negative cases, and theoretical coverage expansion do not represent product
  defects.
- Historical dated review statements remain historical evidence; they are not
  silently rewritten as current claims.
- No further reviewer loop, metadata-only task, or task-number reservation is
  warranted.

## Explicitly deferred work

The following remains outside this closure and is not represented by new task
files: AWS/provider acceptance, production hosted/public acceptance,
PostgreSQL/S3 repository integration rehearsal, public TLS and operational
acceptance, store/legal review, and the non-blocking test-harness/security
hardening listed above.

## Closure result

- Task 209 is closed as **Completed**.
- The single consolidated product-level audit is complete.
- Findings are classified as release blocker, external/environment blocker,
  backlog/hardening, accepted limitation, or no action.
- Critical validation results and non-green suite evidence are documented.
- No unresolved release-blocking product defect was found.
- Numbered task creation remains **OFF**. The current workstream stops here.

## Final recommendation

**READY WITH EXTERNAL GATES** — continue the local/research product phase, and
resume hosted/provider/store acceptance only when the explicitly external
credentials, services, approvals, and environment evidence are available.

## Post-closure Hetzner demo deployment evidence

This addendum records the separately authorized demo deployment performed on
2026-08-30. It does not reopen the closed task sequence or change the product
readiness recommendation.

- The bounded P2 Compose stack is running on Hetzner server `131552315`
  (`platform`) under `/opt/hyfens/p2-r2`, with PostgreSQL and the control plane
  healthy. The existing deployment under `/opt/hyfens` was preserved.
- Cloudflare R2 bucket `hyfens-dev` is configured through the protected remote
  file `/etc/hyfens/p2-r2.env` (`root:root`, mode `600`). The R2 credential is
  scoped to that bucket with object read/write access; no credential value is
  recorded here or in the repository.
- Existing Nginx now routes `/p2/` on `https://api.hyfens.com` to the
  loopback-only control-plane port. Public `/p2/healthz` and `/p2/readyz`
  returned HTTP 200, and `nginx -t` passed.
- The deployed S3 adapter completed a real R2 `putArtifact` followed by a
  digest-checked `readArtifact`. This left one deterministic, non-sensitive
  deployment-probe object in the development bucket.
- The Hetzner firewall is fully applied to the server with four inbound rules:
  SSH TCP 22 from `206.84.224.111/32`, ICMP from any source, and public TCP 80
  and 443 from any source. External TCP checks reached 80/443 and did not
  accept connections on 5432, 18082, or 9000.
- Backups remain disabled as authorized. AWS is not required for this demo
  deployment; production/provider acceptance remains an external gate.

## Post-closure deployed E2E acceptance pass (2026-08-30 UTC)

Acceptance timestamp: `2026-08-30T11:28:11Z`
Target: `https://api.hyfens.com/p2/`

This was one finite acceptance attempt against the existing Hetzner + Cloudflare
R2 deployment. It did not create a task, reopen Task 209, or change the
deployment configuration.

### Evidence before the required failure

- `/p2/healthz` returned HTTP 200.
- `/p2/readyz` returned HTTP 200.
- The existing CLI exposed the remote deploy target and required scope/release
  options through `tool deploy --help`; no credential or token value was
  printed.
- A disposable demo scope was bootstrapped through the supported control-plane
  bootstrap seam:
  - organization: `org70760ae2ff001f83f59af0f1b43cb67e5df1`
  - application: `app6c9b6afc1fe6e72e6b5945a2708b218c7c0e`
  - environment: `env0179b608edaa997d4ebe85887ae029542568` (`e2e`)
- The temporary project completed Dart and Flutter dependency resolution and
  local signing-key generation. The private signing key is not recorded.
- No candidate release ID or patch ID existed before the failure. No release,
  patch, artifact, promotion, or audit mutation for this acceptance candidate
  was submitted to the server.

### Required matrix result

| Gate | Result | Evidence/notes |
| --- | --- | --- |
| Deployment preflight | PASS | Both public health endpoints returned HTTP 200. |
| Demo organization/application/environment | PASS | Dedicated disposable scope created; identifiers recorded above. |
| Release registration | NOT RUN | The local release build failed before registration. |
| Signed patch generation | FAIL | Normal `tool release android` could not produce the required baseline artifact. |
| CLI remote deploy | NOT RUN | No patch was generated. |
| Control-plane admission | NOT RUN | No patch request was submitted. |
| R2 persistence | NOT RUN | No acceptance-candidate artifact was produced or uploaded. |
| Promotion | NOT RUN | No admitted patch existed. |
| Update check | NOT RUN | No release/patch lifecycle reached promotion. |
| Delivery-path artifact fetch | NOT RUN | No update URL/path was returned. |
| Exact artifact SHA-256 | NOT RUN | No acceptance-candidate artifact existed. |
| Artifact verification | NOT RUN | No fetched bytes existed. |
| Idempotent replay | NOT RUN | No eligible lifecycle mutation existed to replay. |
| No duplicate semantic state | NOT RUN | No release/patch/promotion state was created by this attempt. |
| Audit consistency | NOT RUN | The lifecycle stopped before audit-producing operations. |
| Android | NOT_RUN / OPTIONAL | The local release build failed before device acceptance. |
| iOS | NOT_RUN / OPTIONAL | Not attempted after the required gate failed. |

### Required failure record

- Step: normal `tool release android` in the existing supported CLI workflow.
- Expected: an instrumented Flutter Android release artifact suitable for the
  subsequent signed patch and remote deployment flow.
- Actual: the command exited `65` with CLI diagnostic `T1603`.
- Build error: `GeneratedPluginRegistrant.java` referenced
  `dev.flutter.plugins.integration_test.IntegrationTestPlugin`, but that Java
  package was unavailable to `compileReleaseJavaWithJavac`; Gradle then failed
  the release build.
- Read-only post-failure inspection found the corresponding `integration_test`
  package and native Java source present in the installed Flutter 3.47.0 SDK;
  this records the observed build/overlay failure without claiming a narrower
  root cause.
- Authoritative state: the CLI reported that the original source was not
  modified. No remote release, patch, R2 object, promotion, or audit state was
  created for this candidate.
- Cleanup: no deployment cleanup was required. The temporary bootstrap output,
  local private signing key, temporary SSH private key, and temporary console
  access key were removed. The existing Hetzner stack and its prior deployment
  probe object were left unchanged.

Failure classification: **PRODUCT_DEFECT**. The evidence is a concrete failure
of the existing supported normal CLI release path before the remote lifecycle
could begin. This classification records the broken acceptance surface; it does
not assert a narrower root cause than the captured Gradle diagnostic.

### Final disposition for this acceptance pass

**DEPLOYED E2E ACCEPTANCE — BLOCKED BY PRODUCT DEFECT**

The pass stopped at the first required failure. AWS remains deferred, the
dashboard remains out of scope, and task creation remains **OFF**. No Task 210
or follow-up micro-task was created.

## Resumed Hetzner/R2 deployed E2E acceptance — bounded stop (2026-08-30 UTC)

Acceptance resume stop timestamp: `2026-08-30T12:31:13Z`
Target: `https://api.hyfens.com/p2/`
Server: Hetzner `131552315` (`platform`)

This was the authorized continuation from the Android release-build gate. It
did not create a task, modify the deployment configuration, or restart the
completed infrastructure checks.

### Ephemeral SSH evidence

- Read-only pre-change state: target `api.hyfens.com` resolved to
  `188.245.62.225`; SSH listened on TCP 22; `pubkeyauthentication yes`,
  `passwordauthentication no`, and `permitrootlogin without-password` were
  unchanged. The current UFW rules observed before the change allowed TCP 22,
  80, and 443; no firewall rule was added or changed.
- The pre-change `/root/.ssh/authorized_keys` file had one line, mode `600`,
  and SHA-256
  `204581a74b9495920e8a950d6a51f915e90536f882f51ff4f93a504dff1fcf5f`.
- One fresh key was appended with comment
  `hyfens-e2e-acceptance-20260830T122523Z` and fingerprint
  `SHA256:eRQq4XrLRHDoavxV2KrY8KZMx4EP7x2sFwLHhdND7zw`. The comment timestamp
  is the recorded UTC add marker; the console did not emit a separate append
  timestamp.
- Authentication with the ephemeral key succeeded before cleanup
  (`ephemeral_ssh_ok`).
- The exact comment was removed. The matching-entry count became `0`, the file
  returned to one line, mode `600`, and the exact pre-change SHA-256. A fresh
  authentication attempt with the deleted key failed with exit `255` and
  `Permission denied (publickey,keyboard-interactive)`.
- The existing authorized-key content was therefore preserved byte-for-byte;
  an old private key was not available for a separate login test. The local
  ephemeral private/public key files were deleted. Removal timestamp:
  `2026-08-30T12:31:13Z`.

### Existing demo scope and local release evidence

The previously bootstrapped disposable scope was inspected and reused:

- organization: `org70760ae2ff001f83f59af0f1b43cb67e5df1`
- application: `app6c9b6afc1fe6e72e6b5945a2708b218c7c0e`
- environment: `env0179b608edaa997d4ebe85887ae029542568` (`e2e`)

The authoritative PostgreSQL read showed one organization, one application,
and one environment for this scope and no release, patch, artifact, or
promotion records. No manual database mutation was made, and no second demo
tenant was created.

The fixed Android release path and ordinary local patch generation both passed:

- `tool release android`: exit `0`; release ID/digest
  `sha256:48440bd56df68163c3cbbb89da356ac955e5872634a30e0ff5002e2d7ecfe56a`;
  artifact size `58971951`; artifact SHA-256
  `29bdfe3cd3e2693cae044d1dcdea8e82ae88efb1e389087a1b57b2abd935c6c5`.
- `tool patch`: patch ID
  `sha256:ba83ce890df2024b20cda77dce51a477bcf40ca8f8e8395e1ecdc3d7c30263a2`,
  release binding above, sequence `1`, size `2069`, signing key ID
  `ed25519-277114f720a5bcfa`, signature `verified`.

### First required lifecycle failure

- Step: release registration through the existing remote CLI/API workflow.
- Expected: authenticate the control credential and register the submitted
  release for the existing demo organization/application/environment.
- Actual: the previously issued control and delivery token values were
  intentionally removed. The database contains only token hashes; no token
  value remained in the container environment, deployment files, logs, or
  shell history. The supported credential-issue endpoint itself requires an
  existing control credential.
- Authoritative state: no release-registration request was submitted; no
  release, patch, artifact, promotion, update, or audit state was created by
  this resumed attempt.
- Creating a new scope with bootstrap would have violated the explicit reuse
  rule while the existing scope was clean, so no replacement tenant or
  unauthenticated database credential shortcut was used.

Failure classification: **EXTERNAL_ENVIRONMENT_FAILURE** — the required
control/delivery credential material is unavailable. The deployment target
itself was verified by HTTPS health/readiness and the authorized ephemeral SSH
authentication.

### Finite acceptance matrix

| Gate | Result | Evidence/notes |
| --- | --- | --- |
| Android release build | PASS | Clean release exited `0`; artifact and digest recorded above. |
| Deployment preflight | PASS | `/p2/healthz` and `/p2/readyz` returned HTTP 200. |
| Demo organization/application/environment | PASS | Existing clean scope inspected and reused. |
| Release registration | BLOCKED | No supported control credential was available. |
| Signed patch generation | PASS | Ordinary signed patch, sequence 1, signature verified. |
| CLI remote deploy | NOT RUN | Stopped at registration. |
| Control-plane admission | NOT RUN | No patch request was submitted. |
| R2 persistence | NOT RUN | No acceptance artifact was uploaded. |
| Promotion | NOT RUN | No admitted patch existed. |
| Update check | NOT RUN | No promoted patch existed. |
| Delivery-path artifact fetch | NOT RUN | No update response/path existed. |
| Exact artifact SHA-256 | NOT RUN | The local artifact hash is recorded; delivery equality was not exercised. |
| Artifact verification | NOT RUN | No delivered bytes existed. |
| Idempotent replay | NOT RUN | No lifecycle mutation was eligible for replay. |
| No duplicate semantic state | NOT RUN | Baseline was empty; post-replay singularity was not exercisable. |
| Audit consistency | NOT RUN | No lifecycle audit sequence was produced. |
| Android | NOT_RUN / OPTIONAL | Device activation was not required after the server gate stopped. |
| iOS | NOT_RUN / OPTIONAL | Not attempted. |

### Final disposition for this acceptance pass

**DEPLOYED E2E ACCEPTANCE — BLOCKED BY EXTERNAL ENVIRONMENT**

The required next input is a supported control credential and its matching
delivery credential for the already bootstrapped demo scope. No Task 210,
follow-up micro-task, next-gap audit, or AWS work was started. The existing
overall readiness recommendation remains **READY WITH EXTERNAL GATES**.

## CLI Auth v1 — bounded operator-authentication correction (2026-08-30 UTC)

### Status

**CLI AUTH V1 — BLOCKED BY EXTERNAL ENVIRONMENT** for deployed acceptance.
The local implementation and focused validation pass; remote deployment and
the resumed Hetzner/R2 lifecycle were not performed in this run.

### Implemented boundary

The control plane now supports the standard human operator flow:

`tool auth login` → revocable server-side session → short-lived EdDSA access
JWT → protected CLI session/profile storage.

The implementation uses email/password login with Argon2id password hashes, a
15-minute access-token lifetime, a 30-day revocable session lifetime, strict
issuer/audience/algorithm/key/session validation, and current database-backed
tenant authorization. Auth JWT signing material is separate from patch-signing
material. Logout revokes the server session and removes local session data.

Existing opaque control and delivery credentials remain supported for bootstrap,
service accounts, legacy automation, and delivery compatibility. The auth
session is endpoint-bound and is never written to the profile metadata file.
The portable fallback uses a `700` directory and `600` credential/config files;
OS credential-store integration remains a documented hardening item.

The existing demo scope is preserved:

- organization: `org70760ae2ff001f83f59af0f1b43cb67e5df1`
- application: `app6c9b6afc1fe6e72e6b5945a2708b218c7c0e`
- environment: `env0179b608edaa997d4ebe85887ae029542568` (`e2e`)

No replacement tenant was created and no database credential bypass was added.

### Local validation

- Control-plane auth/config analysis: PASS.
- CLI analysis: PASS.
- Focused control-plane auth/config/HTTP tests: 12 PASS.
- Focused CLI auth, rollout/profile fallback, bundle, and deploy tests: 9 PASS.
- PostgreSQL 17 Docker validation, including conditional refresh/revocation and
  concurrent refresh/logout state handling: 8 PASS.
- Docker Compose config validation for default, R2, and HA definitions: PASS.
- Control-plane Docker image build: PASS.
- `.env.example` contains names only and blank auth values; no secret was
  added to the repository or documentation.

A combined run including the historical P3E applicability file reported
date-dependent failures in unchanged scenarios. Those results are outside
the focused auth correction and are not represented as auth acceptance.

### Remote/deployment evidence

- Existing `https://api.hyfens.com/p2/healthz`: HTTP 200.
- Existing `https://api.hyfens.com/p2/readyz`: HTTP 200.
- No auth image/config was deployed to Hetzner in this run.
- No auth owner was bootstrapped remotely.
- No `tool auth login` or resumed release-registration lifecycle was run against
  the remote environment.

The browser deployment path was unavailable in this execution environment,
and the previous ephemeral SSH key had already been deleted. A fresh,
single-use SSH authorization (or an already-authorized supported deployment
path) is required to deploy the new image and protected auth configuration.
The remote run also needs a temporary owner email/password supplied through a
private session or generated and used privately through the supported
`--bootstrap-owner --password-stdin` seam. No password, signing seed, token,
or other secret is recorded here.

### Findings classification

- **Release blocker:** none demonstrated in the bounded local auth scope.
- **External/environment blocker:** remote deployment access, protected auth
  signing configuration, and one-time remote owner bootstrap input are not
  available in this run.
- **Backlog/hardening:** OS-native CLI credential storage; broader remote HA
  acceptance after deployment; non-critical documentation alignment.
- **Accepted limitation:** delivery continues to use the existing separate
  delivery credential for compatibility; AWS and device/store gates remain
  separate.
- **No action:** no additional numbered task or micro-task is justified.

### Final disposition

**CLI AUTH V1 — BLOCKED BY EXTERNAL ENVIRONMENT**

The local product correction is implemented and reviewed, but the required
deployed proof — `tool auth login` followed by release registration and the
finite Hetzner/R2 acceptance lifecycle — cannot be claimed until the protected
remote deployment path and temporary owner input are available. Task creation
remains **OFF**; no Task 210 was created.

## CLI Auth v1 Hetzner deployment attempt — stopped at access gate (2026-08-30 UTC)

### Failure record

- First required gate: establish the authorized ephemeral deployment path.
- Expected: install one fresh ephemeral public key on Hetzner server `131552315`,
  authenticate with it, and use it only for this bounded deployment run.
- Actual: the browser deployment service returned `Invalid browser service
  environment`; the existing non-ephemeral SSH access attempt to
  `root@api.hyfens.com` was rejected with exit `255` in batch mode.
- Remote state: unchanged. No ephemeral key was generated or installed; no
  auth configuration, image, owner, database state, or deployment container
  was modified.
- Cleanup: no temporary key material was created, so no key cleanup was needed.

Failure classification: **EXTERNAL_ENVIRONMENT_FAILURE**. The product code
and local validation were not exercised remotely because the required access
path was unavailable. The run stopped without attempting a deployment bypass.

Final disposition remains **CLI AUTH V1 — BLOCKED BY EXTERNAL ENVIRONMENT**.

## CLI Auth v1 Hetzner retry — stopped at remote preflight (2026-08-30T17:27Z)

### Failure record

- Target: Hetzner server `131552315` (`api.hyfens.com`), deployment path
  `/opt/hyfens/p2-r2`.
- Fresh ephemeral key comment: `hyfens-cli-auth-e2e-20260830T165959Z`.
- Fingerprint: `SHA256:BoPvCLpQCHrcT+eud3jY2b7l/b8aP+pAWH9l4/h/ZP4`.
- SSH authentication before the remote preflight passed: `id -u` returned
  `0`.
- First required remote preflight failed: `/p2/healthz` returned HTTP `502`
  and `/p2/readyz` returned HTTP `502`.
- Remote container evidence: the control-plane container was `Exited (137)`
  and PostgreSQL was `Exited (0)`, both reported as stopped about an hour
  earlier. The deployment directory was present.
- No Auth v1 configuration, image deployment, owner bootstrap, release,
  patch, R2 artifact, promotion, or other acceptance state was changed.
- SSH cleanup completed. Before cleanup, the real
  `/root/.ssh/authorized_keys` file was `root:root`, mode `600`, with two
  lines and no exact-match line for the temporary comment. Removing lines
  containing the unique temporary comment restored the file to one line;
  after cleanup the comment count was `0`, mode remained `600`, and owner
  remained `root:root`.
- A post-cleanup SSH attempt using the temporary private key was rejected
  with exit `255` (`Permission denied (publickey,keyboard-interactive)`).
- Local ephemeral key files and temporary SSH diagnostic files were deleted
  and verified absent.

Failure classification: **EXTERNAL_ENVIRONMENT_FAILURE**. The required
deployed stack was not healthy at the first remote gate, so the bounded Auth
v1 deployment and Hetzner/R2 lifecycle were not attempted.

Final disposition remains **CLI AUTH V1 — BLOCKED BY EXTERNAL ENVIRONMENT**.
Task creation remains **OFF**; no Task 210, AWS work, or follow-up task was
created.
Resume requires either an available Hetzner console/browser session or another
already-authorized supported deployment path. Once access is available, create
the fresh ephemeral key, provision the protected auth configuration, and run
the finite acceptance continuation. No Task 210 or follow-up task was created.

### Repeat attempt (2026-08-30T14:41:59Z)

The authorized deployment-path retry returned the same browser-service error
(`Invalid browser service environment`). No new SSH key was generated or
installed, and no remote state changed. The run remains stopped at the access
gate with the same **EXTERNAL_ENVIRONMENT_FAILURE** classification.

## CLI Auth v1 Hetzner continuation — ephemeral SSH access stopped (2026-08-30T16:54Z)

### Failure record

- Target: Hetzner server `131552315` (`api.hyfens.com`), deployment path
  `/opt/hyfens/p2-r2`.
- Ephemeral key comment: `hyfens-cli-auth-e2e-20260830T144741Z`.
- Fingerprint: `SHA256:mzFFBZDHe0vFYFkPkY9B2nK/N6vCGvb2nsS5D/QQbsc`.
- The Hetzner console was used for the authorized key-installation attempt.
  Authentication with the corresponding temporary key never succeeded:
  `ssh` returned exit `255` with `Permission denied (publickey,keyboard-interactive)`.
- No remote Auth v1 deployment, owner bootstrap, release registration, patch
  admission, R2 lifecycle, or promotion was performed.
- The exact temporary comment was checked in the real
  `/root/.ssh/authorized_keys` file and returned count `0` after cleanup.
  The file was observed as `root:root`, mode `600`, with one remaining line;
  no key contents were recorded.
- A post-cleanup SSH attempt with the temporary key was rejected with the same
  public-key authentication failure.
- Local ephemeral private/public key files were deleted and verified absent at
  `2026-08-30T16:54:21Z`.

Failure classification: **EXTERNAL_ENVIRONMENT_FAILURE**. The required
ephemeral SSH deployment path could not be established, so the finite remote
acceptance sequence remains unrun. No Task 210, follow-up task, AWS work, or
next-gap audit was created.

Final disposition remains **CLI AUTH V1 — BLOCKED BY EXTERNAL ENVIRONMENT**.

## Hetzner P2 recovery and bounded Auth v1 continuation — 2026-08-30

### Recovery result

- Target: Hetzner server `131552315` (`api.hyfens.com`), deployment path
  `/opt/hyfens/p2-r2`, public endpoint `https://api.hyfens.com/p2/`.
- Acceptance evidence timestamp: `2026-08-30T17:54:43Z`.
- Ephemeral SSH access passed using comment
  `hyfens-stack-recovery-20260830T173354Z` and fingerprint
  `SHA256:fcHKrTdakcG3fYo5WdSERTLrInSILp7MAEqAqeOolVw`.
- Pre-restart container evidence was captured. PostgreSQL exited with code `0`,
  `OOMKilled=false`; the control plane exited with code `137`,
  `OOMKilled=false`. Both had `RestartCount=0`.
- Host and Docker journal evidence confirms a host restart and orderly Docker
  shutdown. Docker force-killed the control-plane container after its ten-second
  shutdown timeout. Kernel evidence contained no OOM-killer event.
- Root-cause classification: **CONFIRMED — HOST_RESTART**. This was an
  environment stop, not evidence of an application OOM defect.
- Existing PostgreSQL volume
  `hyfens-p2-r2_hyfens-p2-r2-postgres` remained present. No volume deletion,
  `down -v`, prune, or database reinitialization was performed.
- Protected R2 configuration remained present at `/etc/hyfens/p2-r2.env`,
  owned by `root:root`, mode `600`; only required variable names were inspected.
- PostgreSQL was restarted from the existing Compose definition and became
  healthy. The existing control plane was then restarted and became healthy.
- Local control-plane health and readiness returned `200`; public
  `/p2/healthz` and `/p2/readyz` also returned `200`.
- Read-only scope evidence preserved the existing organization,
  application, and environment:
  `org70760ae2ff001f83f59af0f1b43cb67e5df1`,
  `app6c9b6afc1fe6e72e6b5945a2708b218c7c0e`, and
  `env0179b608edaa997d4ebe85887ae029542568`. Before Auth deployment, release,
  patch, and artifact candidate counts were zero.

Recovery disposition: **HETZNER DEMO STACK — RECOVERED**.

### Bounded Auth v1 continuation

- The reviewed Auth v1 control-plane source and Compose configuration were
  deployed to the existing stack. Auth configuration was stored in the existing
  protected environment file; the file remained `root:root`, mode `600`.
- The Auth v1 signing key used a separate auth key identity. Non-secret key ID:
  `auth-ed25519-hetzner-20260830`. Private signing material was not recorded.
  The configured issuer was `hyfens-control-plane`, control audience was
  `hyfens-control`, access-token TTL was `15m`, and session TTL was `30d`.
- Supported owner bootstrap succeeded for the existing demo scope. The created
  non-secret owner identity was `usr_24124fa4e295a51d975b26ab985ebecb` with
  email `hyfens-e2e-owner@invalid.example`.
- `tool auth login` succeeded against the deployed endpoint with
  `HYFENS_CONTROL_TOKEN` and `HYFENS_DELIVERY_TOKEN` removed from the process
  environment. Auth status reported the expected user and scope. No password,
  session credential, or JWT was recorded.
- CLI profile/session storage was created with restrictive local permissions;
  profile metadata contained the expected scope and no token fields.
- Unauthenticated `/auth/me` returned `401`. After the bounded lifecycle stop,
  `tool auth logout` succeeded, local session storage was removed, and the
  server recorded the session as revoked. The human owner was not deleted.

Auth disposition: **CLI AUTH V1 — DEPLOYED PASS** for the bounded remote
deployment, login, status, and logout/revocation checks.

### Finite E2E continuation result

- The previously recorded release and patch files were not available in the
  current checkout. A fresh `tool release android` therefore produced release
  `sha256:328310ffe5d3f8b930c7f24a980e53e28f39f628082cfa7a85b0fd547de61332`.
  Its artifact was `58,971,951` bytes with SHA-256
  `57c40a0c8a0d05ad305e5935c017f86cc655213aa776138c03d1897ae7f50625`.
  The clean release build succeeded.
- The first required continuation step needing a patch then stopped with
  `P2010: No patchable changes were found; working tree contains no changed
  supported function body.` The previously recorded 2,069-byte patch was not
  locally available, and no compatible patch input was fabricated.
- No release registration, remote patch admission, R2 artifact persistence,
  promotion, update check, delivery fetch, artifact verification, idempotency
  replay, or acceptance audit state was created by this continuation. The
  authoritative candidate counts remained zero.
- E2E stop classification: **OPERATOR_INPUT_ERROR** — the available local
  acceptance input contained no changed supported Dart function body and the
  previously recorded patch artifact was unavailable. This does not demonstrate
  a product defect or deployment defect.

The deployed E2E acceptance remains incomplete and is not reported as a pass.

### SSH cleanup

- The exact ephemeral key entry was removed after the bounded work. The
  `authorized_keys` file remained owned by `root:root`, mode `600`; the matching
  key count changed from `1` to `0`.
- The post-removal authentication attempt using the ephemeral key was rejected.
  Local ephemeral key files and temporary Auth v1 inputs were deleted and
  verified absent.
- No private key, owner password, JWT signing material, control token, delivery
  token, R2 secret, or database password was recorded.

### Final bounded disposition

- **HETZNER DEMO STACK — RECOVERED**
- **CLI AUTH V1 — DEPLOYED PASS** (bounded remote Auth v1 checks)
- **DEPLOYED E2E ACCEPTANCE — NOT COMPLETED; STOPPED BEFORE RELEASE REGISTRATION**

No Task 210, follow-up microtask, AWS work, or next-gap audit was created.
The broader product remains **READY WITH EXTERNAL GATES**; the finite deployed
E2E lifecycle still requires a valid patchable acceptance input before it can be
resumed.

## Deliberate patchable input continuation — 2026-08-30

### Local preparation

- The existing fixture function `calculatePrice(int quantity, int tier)` was
  selected as the single supported patch target. Its base behavior for
  `calculatePrice(6, 1)` was `540`.
- The clean base release was reused after local integrity verification:
  release ID `sha256:328310ffe5d3f8b930c7f24a980e53e28f39f628082cfa7a85b0fd547de61332`,
  artifact size `58,971,951` bytes, artifact SHA-256
  `57c40a0c8a0d05ad305e5935c017f86cc655213aa776138c03d1897ae7f50625`.
- Exactly one fixture-only body change was made for acceptance,
  `return quantity * 90` to `return quantity * 75`, producing the intended
  patched behavior `450`. No compiler, runtime, or patchability rule was
  changed.
- `tool patch` completed successfully. The generated patch ID was
  `sha256:ddadf1690c84729545a1e8a2be708e2fb9dd68440205e058b267ace6b8ac6ec6`,
  sequence `1`, size `2,069` bytes, artifact SHA-256
  `fbe44afd10b150ee67fc4fbd072dd0dd0d9dfa339628443c7fe359a6a8311e99`,
  signing key ID `ed25519-8aa2e7a111444605`, and signature verification
  passed. The existing verifier also returned `VERIFIED`.
- The deliberate source change was restored to `return quantity * 90` after
  the remote attempt; the acceptance-only input is not left in the fixture.

### Remote continuation result

- Target: `https://api.hyfens.com/p2/`, existing demo scope, and recovered
  Hetzner stack. Local and public health/readiness preflight remained passing.
- A supported owner bootstrap was performed on the existing scope. The first
  generated owner was not used because its temporary password was discarded
  before login; a second supported bootstrap created owner
  `usr_137fb980d7b4effb3a7988eca0b71000` for the login attempt. No password or
  bearer value was recorded. The previously created first owner was
  `usr_f76102f02c036a81a68eb700e2087263`.
- `tool auth login` passed against the deployed endpoint using the second
  owner, with `HYFENS_CONTROL_TOKEN` and `HYFENS_DELIVERY_TOKEN` explicitly
  unset. The resolved profile matched the existing organization,
  application, and environment.
- Local patch verification passed, but the normal `tool deploy` path stopped at
  release registration with the control-plane response
  `EXACT_APPLICATION_MISMATCH`.
- Concrete identity evidence: the local release declares runtime application
  `dev.hyfens.conformance`; the preserved remote application is bound to
  `com.hyfens.acceptance.e2e`. This is a supplied fixture/scope mismatch, not
  evidence of a control-plane or R2 failure.
- After the failed request, authoritative candidate counts were unchanged:
  release `0`, patch `0`, artifact `0`, and release idempotency record `0`.
  No promotion, update check, delivery fetch, or artifact lifecycle state was
  created.

E2E stop classification: **OPERATOR_INPUT_ERROR** — the selected local
fixture and existing remote application do not share the same runtime
application identity. The finite acceptance sequence stopped at release
registration as required; no later gate was attempted.

### Ephemeral SSH cleanup

- Temporary key comment: `hyfens-e2e-patch-20260830T181600Z`.
- Fingerprint: `SHA256:26EzdWOnUrnBc6YOL7XF5ymhjBkJ0D0mCcCEu+vxk8U`.
- The key comment carries the generated UTC timestamp; the exact console
  append time was not separately captured and is not inferred here.
- Before removal, `/root/.ssh/authorized_keys` was observed as `root:root`,
  mode `600`, two lines, with one matching temporary comment. After removal it
  was `root:root`, mode `600`, one line, with SHA-256
  `204581a74ba945920e8a950d6a51f915e90536f882f51ff4f93a504dff1fcf5f` and no
  matching comment.
- Cleanup verification was recorded at `2026-08-30T19:14:23Z`.
- A new SSH attempt using the temporary key was rejected with exit `255`.
  The local ephemeral private/public key and known-host files were deleted and
  verified absent.
- `tool auth logout` returned `LOGGED_OUT`; a subsequent `auth status` returned
  `NOT_LOGGED_IN`. Temporary owner-password files were deleted. No secret
  material was recorded.

### Disposition

- **CLI AUTH V1 — DEPLOYED PASS** remains valid for the bounded Auth v1
  deployment/login/logout evidence already recorded.
- **DEPLOYED E2E ACCEPTANCE — NOT COMPLETED; STOPPED AT RELEASE REGISTRATION**.
- No Task 210, follow-up task, AWS work, or next-gap audit was created. The
  existing remote scope was preserved; resumption requires a matching fixture
  and application runtime identity.

## Matching application identity acceptance — 2026-08-30

Acceptance UTC timestamp: `2026-08-30T20:11:41Z`

### Local input and identity

- The canonical conformance fixture was not renamed or modified. A disposable
  acceptance copy used `com.hyfens.acceptance.e2e`, matching the existing
  remote application runtime identity.
- Identity assertion: local acceptance application ID
  `com.hyfens.acceptance.e2e` = remote application runtime ID
  `com.hyfens.acceptance.e2e` — **MATCH**.
- Clean base Android release: release ID
  `sha256:98c75c3549b5ea52ced74b630ccac96188dbadaa769fce1ed264bcbfdf034830`;
  artifact size `58,971,955` bytes; artifact SHA-256
  `f5d71c69db107a985b94d693c427330ffd32dd598d8bf39317c0a20dec501e9c`.
- One fixture-only supported function-body change changed
  `calculatePrice(6, 1)` from `540` to `450`. The signed patch was generated
  and independently verified: patch ID
  `sha256:62a8b6e6dbe1832dde6088238a6c7de43bbb9e4f929fb988f279f514d527bb45`,
  sequence `1`, size `2,076` bytes, artifact SHA-256
  `sha256:3022193809baeadbb08e092f19148ad97dee84fc4ed11dfdefd54f0048e80b5d`,
  signing key ID `ed25519-8aa2e7a111444605`, signature **VERIFIED**.

### Deployed lifecycle

- Existing demo scope was reused: organization
  `org70760ae2ff001f83f59af0f1b43cb67e5df1`, application
  `app6c9b6afc1fe6e72e6b5945a2708b218c7c0e`, environment
  `env0179b608edaa997d4ebe85887ae029542568`.
- Authenticated CLI session was used with `HYFENS_CONTROL_TOKEN` and
  `HYFENS_DELIVERY_TOKEN` unset. Release registration, control-plane
  admission, artifact upload, and promotion completed through `tool deploy`:
  service release `rel9ba1c6264d5fe20333e2392ed004d9261965`, service patch
  `pat0396480823001181144d99cf2e1d07d11678`, artifact
  `art_3022193809baeadbb08e092f`, environment version `1`.
- R2 persistence independently passed through the deployed S3-compatible
  adapter for bucket `hyfens-dev`, object key
  `3022193809baeadbb08e092f19148ad97dee84fc4ed11dfdefd54f0048e80b5d`, size
  `2,076` bytes, and the expected SHA-256.
- The delivery credential was issued through the authenticated control-plane
  operation for the existing application/environment scope and revoked after
  the run. Its plaintext was not recorded.
- Delivery update-check returned `PATCH_AVAILABLE` for sequence `1` and the
  expected release, patch, and artifact identities. The delivery-path fetch
  returned HTTP `200`, size `2,076` bytes, and SHA-256 equal to the locally
  generated artifact.
- The existing verifier returned `VERIFIED` for the fetched bytes, including
  digest, signature, release binding, patch identity, and sequence checks.
- Replaying the exact same `tool deploy` request returned the same service
  release, patch, artifact, and environment version. Authoritative PostgreSQL
  counts were exactly one matching release, patch, artifact, and promoted
  environment; four matching lifecycle idempotency records were present.
- Audit export reported a valid chain with `5` entries. The candidate lifecycle
  contributed the expected four semantic records (`release.register`,
  `patch.register`, `artifact.upload`, `release.promote`); the idempotent
  replay did not create contradictory semantic state.

### Restoration and cleanup

- The disposable acceptance copy was removed after artifact capture. The
  canonical fixture remains unchanged at the base behavior.
- Auth session/profile files were removed by `tool auth logout`; automation
  token environment variables were unset.
- Ephemeral SSH key comment `hyfens-cli-auth-e2e-20260830T193842Z`, fingerprint
  `SHA256:DaASBgBniqfxJWirgwAWDDRrpGEEGETKAFsovmvzKCE`, was removed. The
  server-side `authorized_keys` file returned to the prior observed SHA-256
  `204581a74ba945920e8a950d6a51f915e90536f882f51ff4f93a504dff1fcf5f`,
  `root:root`, mode `600`, one line, and zero matching ephemeral entries.
  Authentication using the removed key was rejected. Local key files and
  temporary delivery/evidence files were deleted.

### Final disposition

- **CLI AUTH V1 — DEPLOYED PASS**
- **DEPLOYED E2E ACCEPTANCE — PASS WITH OPTIONAL DEVICE GATES NOT RUN**

The finite acceptance evidence now proves matching application identity, clean
base release, signed patch admission, R2 persistence, promotion, update
discovery, delivery-path fetch, independent verification, idempotent replay,
singular authoritative state, and audit consistency. The broader product
recommendation remains **READY WITH EXTERNAL GATES** for AWS, production HA,
store, privacy, and legal gates. No Task 210 or follow-up microtask was
created.
