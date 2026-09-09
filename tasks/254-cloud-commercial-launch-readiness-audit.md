# Task 254 — Cloud commercial launch readiness audit

Status: [x] Completed

## Goal

Audit the unaided Hyfens customer journey from public discovery through Cloud
Free onboarding, Flutter release delivery, usage visibility, paid upgrade,
and self-hosted onboarding. Classify launch findings by severity and produce a
readiness verdict based on repository and live-site evidence.

## Scope and Non-goals

Scope:

- map the public website, Cloud workspace, CLI, control-plane APIs, billing,
  documentation, and deployment paths;
- verify the actual Cloud account, Free provisioning, Flutter release,
  runtime, rollback, usage, and upgrade journey where the current repository
  permits;
- audit legal policy access, operational dependencies, and production domain
  deployment configuration;
- classify findings as P0, P1, P2, or P3; and
- implement only small, unambiguous launch-blocker fixes when safe.

Non-goals:

- another pricing or metering implementation;
- new Cloud signup, billing, email, runtime, or deployment architecture;
- changing plan prices, boundaries, retention, or delivery authority;
- broad security, UX, or documentation rewrites; and
- deploying production infrastructure.

## Owner

Codex

## Dependencies

- Tasks 248–253 and their current repository state.
- Root Hyfens control-plane, CLI, deployment, and documentation surfaces.
- Linked `hyfens-cloud-web` marketing, Cloud workspace, billing, and policy
  surfaces.
- Public Hyfens and app entry points where reachable.

## Assumptions

- Current working-tree changes are user work and were preserved.
- Individual backend primitives do not count as an end-to-end customer journey
  without a reachable public entry point.
- Live checks are evidence of deployed state only; repository behavior remains
  the source for implementation details.
- No production deployment, account creation, checkout, or payment mutation
  was authorized or performed during this audit.

## Work Items

- [x] Map public discovery and CTA destinations.
- [x] Trace account, organization, Free provisioning, workspace, and CLI auth.
- [x] Trace Flutter application, release, patch, verification, promotion,
  deployment, runtime update, rollback, and observability paths.
- [x] Audit billing upgrade, failure, cancellation/downgrade, Enterprise, and
  legal policy surfaces.
- [x] Audit self-hosted onboarding and production deployment topology.
- [x] Classify findings and identify small safe fixes versus follow-up tasks.
- [x] Decide whether an implementation fix is safe within this audit scope.
- [x] Create the launch-readiness matrix and final verdict.
- [x] Run proportionate validation and record evidence.

## Validation

Completed targeted validation:

- `dart test test/human_auth_test.dart test/human_auth_http_test.dart
  test/cloud_plan_test.dart test/http_test.dart` from
  `packages/control_plane`: passed, 20 tests;
- `python3 -m unittest dashboard.test_serve dashboard.test_auth_flow` and
  `node --check dashboard/app.js`: passed;
- `npm run typecheck` and `npm run lint` from
  `hyfens-cloud-web/site`: passed;
- `git diff --check` in both the root and Cloud worktrees: passed; and
- live browser/HTTP checks for `hyfens.com`, `/pricing`,
  `app.hyfens.com`, API discovery, and `/refund-policy`.

The audit did not run a production build again because no Cloud source change
was made; the affected Cloud build was already reported passing by Task 253.
It did not create a live account, submit checkout, mutate payment state, or
deploy production infrastructure.

## Launch-readiness matrix

| Journey | Status | Severity | Evidence | Next action |
| --- | --- | --- | --- | --- |
| Marketing → Cloud | Partial/misleading in production | P1 | The repository has Cloud entry links, but the [live homepage](https://hyfens.com/) and [live pricing](https://hyfens.com/pricing) still show the previous Self-hosted/Starter/Team/Enterprise catalog and `$49`-starting copy. | Complete Task 256 web cutover and verify public routes. |
| Account signup | Blocked | P0 | `Create account` at [app.hyfens.com](https://app.hyfens.com/) calls `POST /v1/public/register`; the server requires a fixed `HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID` and creates a read-only client in that existing organization. | Task 255: public account and organization creation. |
| Free provisioning | Blocked through public path | P0 | Free assignment exists in Cloud organization bootstrap/backfill, but there is no public organization/workspace creation route that reaches it. | Task 255: transactional organization creation plus Free assignment. |
| First application | Blocked for a new public user | P0 | Public registration grants only `application:read`, `release:read`, `patch:read`, `artifact:read`, `rollout:read`, and `audit:read`; no `application:write` or customer-owned scope is created. | Task 255: owner scope and first-application onboarding. |
| Flutter integration | Blocked after public entry | P0 | The CLI/docs contain the supported Flutter commands, but `hyfens init` and `deploy` require organization, application, environment, and token scope unavailable from the public path. | Task 255, then Task 258 managed Cloud acceptance. |
| First release | Blocked in unaided Cloud journey | P0 | Local/CLI release creation exists and is tested, but no new Cloud customer can obtain the required write scope and application binding. | Task 258 after public onboarding exists. |
| First patch | Blocked in unaided Cloud journey | P0 | Local patch/sign/upload paths exist; the customer-owned Cloud path is not reachable from public signup. | Task 258 managed Cloud acceptance. |
| Verification | Partial | P0 | Verification capabilities and focused control-plane tests exist, but they are not reachable as part of a new public Cloud tenant workflow. | Validate in Task 258 against a disposable customer organization. |
| Promotion | Partial | P0 | Dashboard/API promotion paths exist for an authorized organization; the public client is read-only and the Cloud CLI requires an application/environment binding. | Task 255 scope provisioning, then Task 258. |
| Deployment | Blocked in public journey | P0 | `DeployCommand` explicitly fails without token, organization, application, and environment; public registration supplies none of the write scope. | Task 255 and Task 258. |
| Runtime update | Not verified | P2 | Runtime/update and artifact paths exist, but repository docs list independent customer-app and physical-device acceptance as open gates; no managed Cloud device run was performed. | Task 258 runtime acceptance. |
| Rollback | Not verified as a managed customer journey | P2 | Signed rollback-to-base/CLI and runtime seams exist; the dashboard describes rollback as an explicit CLI/runtime action, and READY artifact protection remains conservative. | Task 258 must validate the actual customer-visible rollback behavior. |
| Usage visibility | Partial | P2 | Billing APIs and the local `BillingWorkspace` expose countable limits and measured storage/origin delivery, but that UI is a platform/CMS billing surface, not a verified customer workspace route. | Task 257: customer-authorized billing surface. |
| Plan-limit UX | Partial | P2 | Backend emits `PLAN_LIMIT_REACHED`; dashboard error mapping falls back to generic authorization/state messages and does not offer a contextual upgrade action. | Improve during Task 257 or a focused UX task. |
| Free → Starter | Not verified | P1 | Razorpay checkout/webhook primitives and billing state exist, but no customer self-service route or provider test-mode lifecycle was verified. | Task 257: same-organization upgrade and failure/idempotency tests. |
| Starter → Team | Not verified | P1 | Paid plan transition primitives exist, but the same-organization customer flow was not demonstrated. | Task 257. |
| Cancellation/downgrade | Unresolved/not verified | P1 | A cancel-at-cycle-end/provider path exists, but approved downgrade, over-limit, failure, and delayed-webhook behavior was not verified. | Task 257: confirm policy and implement/test transitions. |
| Enterprise contact | Misleading | P1 | The local Enterprise CTA points to `/pricing#plan-enterprise`, an in-page anchor, rather than a verified sales destination. | Task 257: add a real contact path after maintainer approval. |
| Self-hosted onboarding | Documented/reference-ready | P2 | `docs/self-hosted.md` and `deploy/self-hosted/README.md` provide operator bootstrap, Compose, `hyfens login`, `doctor`, `init`, release, patch, and deploy guidance. It is operator-managed, not public Cloud self-service. | Preserve as a separate first-class path; no Cloud billing coupling. |
| Legal policy access | Partial | P1 | Local CMS-managed Terms, Privacy, and Refund Policy routes/footer exist; the [live refund-policy route](https://hyfens.com/refund-policy) returned 404 and the live footer lacks Refund Policy. | Task 256/259: publish and verify policy routes. |
| Production deployment | Partial/not launch-complete | P1 | Deployment wrappers and protected configuration exist; `hyfens.com` is stale, `app.hyfens.com` remains the validated OSS dashboard target, and production secrets/cutover authority are external. | Task 256 staged Cloud web cutover; Task 259 production gates. |

## Verdict

**NOT_READY**

P0 blockers remain. An unaided developer can discover Hyfens, inspect API
discovery, and reach the existing account form, but cannot complete the core
Cloud journey. The public registration route attaches a read-only client to a
server-selected existing organization; it does not create a customer-owned
organization/workspace, assign Free to that new tenant, create an owner scope,
or enable first-application creation. Consequently the developer cannot reach
the first Cloud release/patch/deploy workflow without maintainer-provided
tenant and scope setup.

## Verified customer journey

The furthest verified unaided path is:

1. Discover the live marketing site and pricing, although the live catalog is
   stale relative to the repository.
2. Open `app.hyfens.com` and reach the Login/Create account shell.
3. Obtain API discovery from the managed API.

The path stops at customer-owned onboarding. No live account was submitted,
because doing so would mutate external state and would only create the fixed-
organization read-only client described by the implementation. The repository
does independently demonstrate control-plane plan, auth, artifact, HTTP,
dashboard, CLI, and entitlement primitives; those tests do not constitute a
managed Cloud customer acceptance run.

## Cloud journey findings

### P0 — core journey

- There is no public organization/workspace creation flow.
- The existing public registration flow is fixed-tenant and read-only.
- The resulting identity cannot create an application or environment.
- The CLI cannot bind a new customer project or deploy without organization,
  application, environment, and write-capable token scope.
- Therefore Free provisioning, first release/patch, deployment, and the rest
  of the Cloud workflow are unreachable for an unaided new customer.

### P1 — commercial and production

- Live marketing and pricing have not received the corrected Cloud catalog and
  still visually conflate the old pricing ladder with Self-hosted.
- Live policy access is incomplete: the local Refund Policy route is not
  published at the current public edge.
- Customer self-service upgrade and paid failure handling were not verified;
  the available billing workspace is a protected platform/CMS surface.
- The Enterprise CTA has no verified sales/contact destination.
- Cancellation/downgrade semantics and required account/payment communications
  need maintainer/provider decisions and acceptance evidence.

### P2 — material UX and evidence gaps

- Plan-limit errors are not translated into a clear limit explanation and
  upgrade path in the dashboard.
- Managed Cloud Flutter runtime/device update and rollback behavior has not
  been independently accepted.
- Customer-facing usage visibility is not proven on the actual Cloud workspace
  route, although the API and platform billing surface expose the measurements.

### P3 — post-launch improvements

- Polish CTA copy and add richer first-run guidance once the customer-owned
  onboarding path exists.
- Add routine browser smoke coverage for pricing, policy, favicon, and
  machine-readable pricing after the production cutover.

## Self-hosted journey

Self-hosted is a separate operating model and is not a Cloud subscription
tier. The repository provides a coherent operator-managed path: install the
Compose stack, configure database/object storage/auth, bootstrap the local
owner, then use `hyfens login`, `doctor`, `init`, release, patch, and deploy.
This is suitable as a documented/reference deployment path, but it does not
prove public Cloud self-service and must not be used as a substitute for Free
Cloud onboarding.

## Production architecture

- The root control plane/API is deployed behind the managed API domain and
  exposes discovery and control-plane routes.
- The live `hyfens.com` edge is still serving the older marketing/pricing
  deployment.
- The private Cloud web repository owns the intended marketing/CMS, billing,
  Cloud Customer Workspace composition, and Platform Console, but its README
  explicitly leaves `app.hyfens.com` on the validated OSS customer target
  until a staged Cloud customer cutover.
- Deployment wrappers, TLS/DNS checks, health/readiness checks, and protected
  environment configuration exist, but the cutover requires production
  authority and secrets that were not available or authorized for this audit.

## Small fixes performed

No application or infrastructure source fix was performed. The evidence does
not support a safe one-file patch: public onboarding requires a new
organization/account contract, owner capabilities, retry/isolation behavior,
and CLI/dashboard scope selection. The audit added/updated documentation only:

- this completed Task 254 record; and
- the bounded follow-up task records 255–259.

## Follow-up tasks created

Priority order:

1. Task 255 — Public Cloud self-service onboarding (P0).
2. Task 256 — Cloud web production cutover and catalog synchronization (P1).
3. Task 257 — Customer billing upgrade lifecycle (P1).
4. Task 258 — Managed Cloud Flutter end-to-end acceptance (P0 after Task 255,
   with device/runtime evidence).
5. Task 259 — Cloud launch operations and policy gates (P1/P2, including live
   policy routes, email/recovery decisions, and production dependencies).

## Launch recommendation

Do not launch public Cloud self-service. Complete Task 255 first and prove an
unaided account → organization → Free → first application flow. Then run Task
258 against managed Cloud, complete the staged web/policy cutover in Task 256,
and verify the paid lifecycle in Task 257. The readiness level can move to
`PRIVATE_BETA_READY` only after invited/assisted users can complete the core
workflow; `PUBLIC_BETA_READY` additionally requires unaided Free onboarding
and a working core Cloud flow. `GA_READY` requires the paid lifecycle,
cancellation behavior, production deployment, and operational gates to be
verified as well.

## Next Action

Start Task 255 with an explicit maintainer decision on account verification,
recovery, organization creation, and abuse/rate-limit policy. Do not use the
existing fixed-tenant read-only registration path as public Cloud onboarding.

## Blockers

P0: public customer-owned Cloud onboarding and write-capable Free workspace
provisioning are missing. Provider credentials/test events, email/recovery
policy, production cutover authority, and device infrastructure are external
dependencies for the subsequent P1/P2 tasks.

## Outcome

Completed 2026-09-07. Verdict: `NOT_READY`. The repository has substantial
Cloud plan, entitlement, artifact, CLI, billing, and deployment primitives, but
the public product does not yet connect them into an unaided customer-owned
Cloud journey. No production deployment or external payment/account mutation
was performed.

## References

- `tasks/248-cloud-free-backend-tier.md`
- `tasks/249-cloud-plan-boundaries.md`
- `tasks/250-cloud-usage-metering-follow-up.md`
- `tasks/251-cloud-plan-matrix-review.md`
- `tasks/252-cloud-artifact-lifecycle-retention.md`
- `tasks/253-cloud-delivery-accounting.md`
- `tasks/255-public-cloud-self-service-onboarding.md`
- `tasks/256-cloud-web-production-cutover.md`
- `tasks/257-customer-billing-upgrade-lifecycle.md`
- `tasks/258-managed-cloud-flutter-e2e-acceptance.md`
- `tasks/259-cloud-launch-operations-and-policy-gates.md`
- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/config.dart`
- `packages/control_plane/lib/src/service.dart`
- `packages/control_plane/lib/src/cloud_plans.dart`
- `dashboard/app.js`
- `cli/lib/src/cli_runner.dart`
- `docs/getting-started.md`
- `docs/HYFENS_DEVELOPER_PLATFORM_CONTRACT.md`
- `docs/self-hosted.md`
- `hyfens-cloud-web/site/src/lib/pricing.ts`
- `hyfens-cloud-web/site/src/components/site-footer.tsx`
- `hyfens-cloud-web/site/src/components/cms/BillingWorkspace.tsx`
- `hyfens-cloud-web/deploy/web/README.md`

## History

- 2026-09-07: Created for the end-to-end Cloud commercial launch-readiness
  audit.
- 2026-09-07: Completed source, route, CLI, billing, live-site, policy, and
  deployment audit. Recorded `NOT_READY`, preserved existing implementation,
  and created follow-up tasks 255–259 for verified gaps.
