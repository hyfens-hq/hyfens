# Task 263 — Managed Cloud end-to-end acceptance

Status: [-] Blocked

## Goal

Prove the managed Hyfens Cloud customer journey end to end using only public
product surfaces: disposable customer onboarding, public CLI authentication,
real Flutter project binding, release/patch/deploy, physical iPhone delivery,
trusted receipt settlement, Cloud usage projections, bounded Developer-plan
behavior, and cleanup. Keep live billing disabled and classify provider or
deployment gates honestly.

## Scope and Non-goals

Scope:

- verify the deployed managed Cloud service topology and required migrations;
- create one disposable customer through supported signup and account flows;
- use the public v0.1.10 CLI for managed login, project binding, release,
  patch, deployment, status, logout, and bounded MCP smoke;
- use the already-proven private Flutter acceptance application and physical
  iPhone path without modifying its architecture;
- verify one or two meaningful reversible patches, trusted receipt delivery,
  canonical Cloud settlement, projections, restart, rollback, and dedup;
- exercise existing Developer-limit/reset harnesses and any available
  Razorpay TEST upgrade path without real charging;
- verify customer/platform audience isolation, audit evidence, documentation
  clarity, and cleanup; and
- preserve the exact finite acceptance matrix below.

Non-goals:

- reopening Flutter ABI, trusted receipt, Cloud settlement, pricing, or
  payment-orchestration implementation;
- enabling live checkout or live overage collection;
- using manual SQL, operator-only tokens, SSH credentials, server edits, or
  private CLI builds as customer workflow steps;
- modifying Kavach360 to work around Hyfens or provider limitations;
- changing existing stable releases, publishing a new CLI release merely for
  this acceptance, or migrating existing customer organizations;
- requiring Android signing, Play Integrity, App Attest, or Razorpay TEST
  credentials when the deployment-owned environment does not provide them;
- creating additional microtasks; or
- deleting unrelated developer work, credentials, branches, worktrees, or
  dirty checkout changes.

## Owner

Hyfens managed Cloud acceptance coordinator.

## Dependencies

- Public origin/main at or after a4d9ec2, with immutable stable release
  v0.1.10.
- Managed Cloud deployment and its supported customer/auth/API surfaces.
- Existing public trusted-receipt and private Cloud settlement contracts.
- Disposable non-production identity and, if available, Razorpay TEST access.
- Existing physical iPhone acceptance path and untouched Kavach360 project.
- Task 260 release, cleanup, and public/private boundary rules.

## Assumptions

- The current public and private primary checkouts contain unrelated dirty
  developer work and remain untouched.
- Acceptance/test trust remains non-billable and live billing remains off.
- Existing private Cloud test harnesses are evidence for exact threshold and
  concurrency behavior, but do not substitute for customer-facing E2E steps.
- Managed Cloud may be unable to provide a disposable signup identity,
  provider credentials, or a supported deletion/archive path; each is recorded
  as a factual product, deployment, or provider gate rather than bypassed.
- No customer secret is written to project configuration, task records, or
  shell-visible documentation.

## Work Items

- [x] Reserve Task 263 in an isolated public worktree and inspect effective
  repository/deployment instructions.
- [-] Verify managed endpoints, service versions, readiness, migrations, object
  storage, and live-billing flags; endpoint health/readiness/discovery passed,
  but deployed migration/object-storage/commercial billing evidence could not
  be completed because the managed customer deployment is not exposed.
- [-] Create and use one disposable customer through supported product flows.
- [x] Install and verify the public v0.1.10 CLI, managed login, profile, and
  secret-safe credential storage.
- [-] Bind the untouched real Flutter project and verify release/patch/deploy
  metadata through managed Cloud.
- [-] Deliver a meaningful patch to the already-installed physical iPhone
  without reinstall; verify restart, receipt, settlement, usage projections,
  dedup, second-patch behavior, and rollback.
- [x] Run or reconcile the existing Developer-limit/reset, audience-isolation,
  reconciliation, and optional Razorpay TEST checks without real charging.
- [-] Verify logout, revocation, browser/session cleanup, disposable
  organization cleanup/archive, artifact policy, audit chain, MCP smoke, and
  Cloud/self-host documentation.
- [x] Review and remove only Task 263-owned temporary state, then commit and
  push this durable task record without publishing a new public release.

## Validation

Planned affected validation:

- read-only live endpoint and deployment-contract probes;
- supported browser and public CLI customer lifecycle;
- managed Cloud API/dashboard evidence;
- public v0.1.10 CLI command and MCP smoke;
- existing private Cloud settlement, threshold, reset, and isolation harnesses
  where direct customer execution is bounded or unavailable; and
- physical iPhone patch/restart/rollback checks only when the disposable
  managed environment and already-installed base permit them.

Record commands, sanitized results, skipped checks, and reasons in the
outcome. Do not expose credentials, private identifiers, private app source,
provider payloads, or infrastructure secrets.

## Next Action

No further action remains in this finite task. A future managed Cloud
acceptance scope must first provide a supported self-service customer
organization/signup flow and deploy the managed customer workspace to
app.hyfens.com. Do not bypass this gate with bootstrap, SQL, SSH, or operator
credentials.

## Blockers

- The public managed API returns HTTP 503 with
  PUBLIC_REGISTRATION_UNAVAILABLE for POST /v1/public/register. Its source
  contract requires a preconfigured single organization and creates a
  read-only client membership; it does not create a customer organization,
  Developer subscription, application, or environment.
- The live app.hyfens.com surface is the OSS Customer/Instance Workspace. Its
  visible signup is labelled Client access and says it creates a client
  account. The private deployment contract explicitly keeps this edge on the
  OSS target until a separate Cloud customer cutover.
- The deployed API discovery response reports product_version 0.1.0 and only
  the generic control-plane capabilities. Managed commercial pricing and
  platform-commercial routes return HTTP 404. No public deployment evidence
  exposes the reviewed managed customer/commercial service.

This is classified as a product-surface blocker, with a contributing
deployment-cutover gate. No customer, subscription, application, environment,
release, artifact, receipt, or charge was created or modified.

## Outcome

Final disposition: HYFENS MANAGED CLOUD E2E — BLOCKED BY PRODUCT DEFECT

The managed journey could not start at disposable customer signup. A safe
invalid-body probe of the public registration route returned
PUBLIC_REGISTRATION_UNAVAILABLE (HTTP 503), and no credentials were entered
or transmitted. The live customer page confirmed that its available account
creation flow is client access into a server-selected organization, not
managed Cloud customer onboarding. The private deployment README and edge
configuration confirm that app.hyfens.com is intentionally still the OSS
customer target until Cloud customer cutover.

Read-only live evidence on 2026-09-08:

- api.hyfens.com/healthz: HTTP 200; /readyz: HTTP 200; /.well-known/hyfens:
  HTTP 200. Discovery advertised human auth and generic signed-release,
  bounded-patch, verification, rollback, and credential capabilities, but no
  managed customer onboarding capability. It reported product_version 0.1.0.
- app.hyfens.com/healthz: HTTP 200; app root: HTTP 200. Its live DOM exposed
  Create account → Client access → Create a client account.
- platform.hyfens.com root: HTTP 200. Its /healthz path is not exposed by the
  Next.js web surface; this was not treated as an API health failure.
- api.hyfens.com/v1/public/register with an empty JSON object: HTTP 503,
  PUBLIC_REGISTRATION_UNAVAILABLE. No state change occurred.
- api.hyfens.com/v1/public/pricing and
  api.hyfens.com/v1/platform/commercial/catalog: HTTP 404 on the deployed
  public control-plane edge.
- Public distribution: /opt/homebrew/bin/hyfens reports hyfens 0.1.10;
  login, profile, and MCP help were inspected without authenticating or
  mutating the existing profiles.

The existing private PostgreSQL/quota/usage harness evidence remains valid and
was not rerun or relabelled as managed customer E2E evidence. The public and
private primary checkouts, existing CLI profiles, and existing user-owned
changes were preserved. No disposable identity or temporary secret was
created, so there was no credential or organization cleanup action to perform.
Tasks 247, 253, 260, 261, and 262 remain closed.

## History

- 2026-09-08 — Reserved Task 263 in an isolated worktree, probed the live
  managed surfaces, and stopped at the supported disposable-customer signup
  gate. Recorded the blocked disposition without creating customer state or
  modifying the primary checkouts.

## Acceptance Matrix

| Gate                                 | Required | Result |
| ------------------------------------ | -------- | ------ |
| Managed services healthy             | PASS     | PASS — API health/readiness/discovery and web roots responded |
| Required migrations deployed         | PASS     | BLOCKED — managed commercial deployment not exposed |
| Live billing OFF                     | PASS     | PASS — no checkout or charge attempted; prior invariant preserved |
| Disposable customer signup           | PASS     | BLOCKED — HTTP 503 PUBLIC_REGISTRATION_UNAVAILABLE |
| Developer subscription               | PASS     | BLOCKED — no disposable organization |
| Application/environment creation     | PASS     | BLOCKED — no disposable organization |
| Customer Workspace isolation         | PASS     | NOT_REACHED — no customer session |
| Platform Console visibility          | PASS     | NOT_REACHED — no disposable organization |
| Public v0.1.10 installed             | PASS     | PASS — Homebrew binary reports 0.1.10 |
| Managed CLI login                    | PASS     | BLOCKED — no disposable account |
| Secret-safe credential storage       | PASS     | NOT_REACHED — no credential created |
| Real app binding                     | PASS     | NOT_REACHED — upstream customer gate |
| Release registration                 | PASS     | NOT_REACHED — upstream customer gate |
| Real patch creation                  | PASS     | NOT_REACHED — upstream customer gate |
| Managed deploy                       | PASS     | NOT_REACHED — upstream customer gate |
| Object storage persistence           | PASS     | NOT_REACHED — upstream customer gate |
| Physical iPhone delivery             | PASS     | NOT_REACHED — upstream customer gate |
| No-reinstall activation              | PASS     | NOT_REACHED — upstream customer gate |
| Restart persistence                  | PASS     | NOT_REACHED — upstream customer gate |
| Trusted receipt                      | PASS     | NOT_REACHED — upstream customer gate |
| Cloud usage settlement               | PASS     | NOT_REACHED — upstream customer gate |
| Receipt dedup                        | PASS     | NOT_REACHED — upstream customer gate |
| Customer usage projection            | PASS     | NOT_REACHED — upstream customer gate |
| Platform usage projection            | PASS     | NOT_REACHED — upstream customer gate |
| Second-patch counting                | PASS     | NOT_REACHED — upstream customer gate |
| Rollback                             | PASS     | NOT_REACHED — upstream customer gate |
| Rollback usage semantics             | PASS     | NOT_REACHED — upstream customer gate |
| Developer limit harness              | PASS     | PASS — existing private PostgreSQL harness evidence |
| Developer no-overage behavior        | PASS     | PASS — existing private commercial harness evidence |
| Usage reset                          | PASS     | PASS — existing private commercial harness evidence |
| Razorpay Starter sandbox             | PASS or EXTERNAL_GATE | EXTERNAL_GATE — no TEST credentials; live billing stayed off |
| Upgrade behavior                     | PASS or PROVIDER_GATE | PROVIDER_GATE — Razorpay TEST unavailable |
| Cross-tenant isolation               | PASS     | PASS — existing tenant-boundary tests; no live second tenant probed |
| Customer/platform audience isolation | PASS     | PASS — existing audience-boundary tests; live customer session not reached |
| CLI logout/revocation                | PASS     | NOT_REACHED — no managed session created |
| Disposable credential cleanup        | PASS     | PASS — no disposable credential created; existing profiles preserved |
| Disposable org cleanup/archive       | PASS     | NOT_REACHED — no disposable organization created |
| Audit chain                          | PASS     | NOT_REACHED — no customer lifecycle event created |
| MCP Cloud smoke                      | PASS     | NOT_REACHED — no managed profile/session |
| Docs Cloud/self-host clarity         | PASS     | PASS — managed/self-host boundaries are documented |
| Task cleanup                         | PASS     | PASS — temporary tab/worktree state reviewed; primary checkouts preserved |

## References

- tasks/260-release-hygiene-and-governance.md
- tasks/262-production-attestation-rc-acceptance.md
- CHANGELOG.md
- docs/releases/releasing.md
- docs/runtime/trusted-install-receipts.md
- docs/product/customer-workspace.md
- docs/product/platform-console.md
- docs/cli.md
