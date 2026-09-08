# Task 264 — Managed Cloud self-service onboarding

Status: [-] Blocked

## Goal

Build the first-use managed Hyfens Cloud journey so a new developer can create
an account, verify it, become the owner of a Cloud organization with the
published Developer plan, create an application and environment, enter the
managed Customer Workspace, and authenticate the public CLI without staff,
SSH, SQL, operator tokens, or manual credential generation.

## Scope and Non-goals

Scope:

- define an explicit managed Cloud signup contract distinct from legacy
  self-host/client-access registration;
- implement verified account onboarding, organization ownership, automatic
  Developer subscription assignment, first application, and first
  environment creation with idempotent recovery;
- deploy the managed Customer Workspace and customer APIs through the intended
  app.hyfens.com and api.hyfens.com surfaces while keeping Platform Console
  staff-only and preserving the OSS self-host workspace;
- provide the supported browser-to-CLI handoff, organization/application/
  environment selection, and secret-free project binding;
- add focused API, domain, browser, authorization, tenant-isolation, and
  deployment smoke coverage;
- keep live checkout and live overage collection disabled, and keep Developer
  onboarding independent of Razorpay; and
- leave the system ready to rerun Task 263 from its first blocked gate.

Non-goals:

- rerunning Task 263 before all onboarding prerequisites pass;
- reopening Flutter ABI, trusted receipts, Cloud usage settlement, pricing, or
  payment orchestration;
- redefining /v1/public/register if it remains required for self-hosted
  client-access membership;
- converting existing client accounts or UNKNOWN organizations;
- exposing Platform Console to customers or deleting the OSS self-host
  Customer/Instance Workspace;
- enabling live billing, requiring payment details for Developer, or doing
  Razorpay production work;
- using bootstrap, SQL, SSH, operator credentials, maintainer-created
  organizations, manual tokens, frontend mocks, or hardcoded production
  verification bypasses as customer workflow steps; or
- creating additional tasks for signup, application, environment, CLI, or
  deployment substeps.

## Owner

Hyfens managed Cloud product coordinator.

## Dependencies

- Public Hyfens repository at origin/main after Task 263, including stable
  v0.1.10 and the public CLI/auth contracts.
- Private hyfens-cloud-web Cloud API and web workspace implementation.
- Existing commercial catalog, Developer entitlements, receipt settlement,
  tenant authorization, and platform/customer audience boundaries.
- Established deployment topology for api.hyfens.com, app.hyfens.com,
  platform.hyfens.com, and self-hosted OSS surfaces.
- A safe local/staging or managed deployment target for preflight and cutover.

## Assumptions

- The public and private primary checkouts contain unrelated developer changes
  and must remain untouched.
- Developer onboarding is free, uses the current published catalog, and does
  not depend on a payment provider.
- Email delivery may require a controlled local/staging capture transport, but
  production verification cannot be silently bypassed.
- Existing account/client-access semantics and existing customer/platform
  isolation remain compatible and are preserved.
- Managed deployment credentials, DNS/edge access, and transactional email
  provisioning may remain external gates; no secret is committed or copied
  into this task record.

## Work Items

- [x] Reserve Task 264 and inspect public/private repository instructions,
  branches, deployment topology, and current auth/onboarding contracts.
- [x] Define and document the explicit managed Cloud signup and onboarding
  API contract without changing legacy client-access semantics.
- [x] Implement verified identity, account/session, abuse controls, and
  idempotent onboarding transaction.
- [x] Implement organization owner, Developer subscription/version pinning,
  first application, first environment, entitlements, and resume behavior.
- [x] Implement the operational managed Customer Workspace and customer API
  routing while preserving Platform Console and OSS self-host boundaries.
- [x] Implement CLI login/handoff and org/application/environment discovery with
  secret-free project configuration.
- [x] Add focused security, tenant, browser, API, and regression tests and
  documentation.
- [x] Add the minimum fixed-argument private Cloud API deployment path with a
  loopback-only service boundary, protected configuration checks, migration
  execution, health/readiness verification, and runtime rollback handling.
- [-] Validate staging/preflight and perform managed edge cutover only when the
  target is deployable and the approved deployment path is available. The
  reviewed private branch now contains the deployment path, but the live host
  has not received its one-time privileged installer/configuration; it still
  has no deployed private Cloud API target on port 18192, and the current edge
  still routes app.hyfens.com to the OSS workspace.
- [-] Run the prerequisite onboarding acceptance only; record readiness to
  rerun Task 263, clean task-owned state, and commit/push intentional changes.
  This cannot begin until the live API/workspace and approved verification
  delivery are available.

## Validation

Completed local validation:

- public control-plane `dart analyze` passed; the full public suite passed with
  315 tests and 34 pre-existing PostgreSQL/process-environment skips;
- private Cloud API `dart analyze` passed; the full API suite passed with 67
  tests and 8 environment-dependent PostgreSQL skips;
- private web typecheck, lint, and production build passed, including the
  `/signup`, `/verify-email`, and `/workspace` routes; provider compatibility
  tests passed (9 tests);
- focused signup/verification, retry/idempotency, owner onboarding, legacy
  registration, customer authorization, entitlement, and tenant-boundary
  tests passed;
- final `git diff --check` passed in both isolated worktrees.
- the private deployment Compose model passed `docker compose config --quiet`,
  both fixed deployment scripts passed `sh -n`, and an ephemeral host-layout
  build compiled the Cloud API, migration, seed, and reconciliation binaries
  into the reviewed image successfully;
- repository inspection found no existing approved transactional-email
  provider/adapter or production delivery secret; no provider was invented and
  no capture/bypass transport was enabled.

Live/preflight evidence:

- `https://api.hyfens.com/healthz`, `/readyz`, and `/.well-known/hyfens`
  returned HTTP 200;
- `POST https://api.hyfens.com/v1/cloud/signup` returned HTTP 404
  `NOT_FOUND`, proving the live public control plane is still the pre-Task 264
  deployment;
- `https://app.hyfens.com/`, `/signup`, and `/workspace` returned HTTP 200 but
  served the legacy OSS Customer/Instance Workspace;
- the deployment host currently has control plane 18082, OSS dashboard 18083,
  and private web 18084, but no private Cloud API container/listener on 18192;
- the current live edge still routes app.hyfens.com to 18083. No customer was
  created and Task 263 was not rerun.

Browser visual acceptance was not run; record `VISUAL_GATE` rather than claim
visual browser evidence. The live transactional-email endpoint/token and a
deployable private Cloud API target are external prerequisites; no capture
transport or verification bypass was enabled on the live deployment.

Record commands, results, skipped checks, external gates, and deployment
versions in the outcome. Do not expose credentials, private identifiers,
provider payloads, or infrastructure secrets.

## Next Action

Provision the approved transactional-email endpoint and a protected
deployment target/configuration for the private Cloud API, stage the reviewed
public/private commits through the established deployment path, and validate
both targets before edge cutover. Only then create a disposable customer and
rerun Task 263 from its first blocked gate.

## Blockers

`CLOUD_DEPLOYMENT_GATE`: the reviewed private branch now provides a fixed
Cloud API deployment wrapper and one-time installer, but the live host has no
installed API wrapper, protected Cloud API environment, service, or 18192
listener. The available NOPASSWD deployment allowlist still covers only the
public control plane, private web, and edge, so the new root setup cannot be
completed through the currently available deployment surface. The installed
public edge still points app.hyfens.com at the OSS dashboard.

`IDENTITY_EMAIL_PROVIDER_GATE`: the live public control plane is still the
pre-Task 264 build and no approved production transactional-email endpoint and
secret are available. Enabling signup with a local capture transport or a
browser bypass would violate the production verification contract.

## Outcome

The managed signup contract, verified owner onboarding, idempotent application
and environment setup, entitlement-checked private resource writes, Customer
Workspace handoff, marketing CTA, documentation, focused tests, and a fixed
private Cloud API deployment path are implemented and locally validated in
isolated public/private worktrees. The live product journey remains blocked
before customer creation by the unprovisioned privileged deployment target and
approved verification-email delivery. No live edge cutover, disposable
customer, manual organization, operator token, SQL mutation, or Task 263
rerun was performed.

## References

- tasks/263-managed-cloud-end-to-end-acceptance.md
- tasks/260-release-hygiene-and-governance.md
- docs/product/customer-workspace.md
- docs/product/platform-console.md
- docs/cli.md
- deploy/self-hosted/README.md
- hyfens-cloud-web/deploy/web/README.md
- hyfens-cloud-web/deploy/cloud-api/compose.yaml

## History

- 2026-09-08 — Reserved Task 264 in an isolated public worktree after Task 263
  identified the missing managed self-service customer journey. No primary
  checkout, deployment, customer state, or existing task was modified.
- 2026-09-08 — Implemented and locally validated the explicit Cloud signup,
  verification, owner onboarding, private entitlement-checked resource writes,
  Customer Workspace handoff, marketing Start free path, and deployment
  configuration. Live probes showed the host is still pre-Task 264 with no
  private Cloud API target and no approved production email delivery; recorded
  bounded deployment/email gates and did not rerun Task 263.
- 2026-09-08 — Added the reviewed private Cloud API deployment Compose model,
  fixed no-argument root wrapper, one-time sudo installer, and rollback-aware
  health/migration procedure. Local image build and script validation passed;
  host installation remains blocked by missing protected configuration and the
  unavailable privileged deployment setup. No live cutover or Task 263 rerun.

## Acceptance Matrix

| Gate                                     | Required            |
| ---------------------------------------- | ------------------- |
| Cloud signup contract                    | PASS                |
| Legacy client-access preserved           | PASS                |
| Email verification policy                | PASS                |
| Signup idempotency                       | PASS                |
| Organization creation                    | PASS                |
| Owner membership                         | PASS                |
| Automatic Developer subscription         | PASS                |
| Plan version pinning                     | PASS                |
| Payment-provider-independent free signup | PASS                |
| Application creation                     | PASS                |
| Environment creation                     | PASS                |
| Developer entitlement enforcement        | PASS                |
| Onboarding resume                        | PASS                |
| Customer API auth                        | PASS                |
| Platform/customer audience isolation     | PASS                |
| Tenant isolation                         | PASS                |
| Customer Workspace operational           | PASS (local)        |
| Platform Console unaffected              | NOT CUT OVER        |
| Managed API routes exposed               | CLOUD_DEPLOYMENT_GATE |
| CORS/CSRF review                         | PASS (local)        |
| app.hyfens.com Cloud deployment          | CLOUD_DEPLOYMENT_GATE |
| OSS self-host workspace preserved        | PASS                |
| Marketing Start Free handoff             | PASS (local)        |
| CLI login handoff                        | PASS (local)        |
| CLI org/app/env visibility               | CLOUD_DEPLOYMENT_GATE |
| No secret in project config              | PASS                |
| Cloud/self-host docs                     | PASS                |
| Browser acceptance                       | VISUAL_GATE         |
| Accessibility checks                     | PASS (static)       |
| Live billing OFF                         | PASS                |
| Razorpay not required for Developer      | PASS                |
| Audit events                             | PASS (local)        |
| CHANGELOG/release records                | PASS                |
| Task-owned cleanup                       | PASS                |
| Ready to rerun Task 263                  | CLOUD_DEPLOYMENT_GATE |

Do not expand this matrix after execution begins.

## Final Disposition

HYFENS MANAGED CLOUD ONBOARDING — BLOCKED BY CLOUD DEPLOYMENT
