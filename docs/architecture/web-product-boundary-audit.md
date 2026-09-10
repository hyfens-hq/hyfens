# Hyfens Web Product Boundary Audit

Status: REVIEW REQUIRED — NO MIGRATION AUTHORIZED

Date: 2026-09-04

Decision: `WEB PRODUCT BOUNDARY — CLOUD/OSS FRONTENDS MUST BE RESTRUCTURED`

This is a read-only architecture and product-ownership audit. It does not
authorize code migration, deletion, deployment, DNS changes, commit, or push.

## Executive summary

The public `hyfens` repository should continue to contain a web interface. A
self-hosted Hyfens installation needs a public, distributable Customer/Instance
Workspace for organization, application, environment, delivery-record, team,
credential, audit, and setup workflows. Removing that interface entirely would
violate the self-hosting promise.

The current scope is nevertheless too broad. The OSS `dashboard` is one
dependency-free static bundle containing both:

- the reusable tenant-scoped Customer Workspace; and
- the global Hyfens Platform Console, including cross-tenant organization
  inspection, commercial projections, support operations, staff management,
  and platform operations.

The Platform Console is a Hyfens Cloud/internal product. Authorization guards
make the current implementation safer, but they do not make the private
platform product a correct component of the public self-host distribution. The
current dashboard image physically includes both shells and their client code.

`hyfens-cloud-web` is the intended private Cloud web project, but it is not yet
a migration-ready replacement: its current local source is an early Next.js
marketing/CMS/billing application with no customer workspace or Platform
Console implementation, no commits, and no configured remote. It should become
the destination for Cloud-only web products, but it must first receive an
explicit baseline and shared-contract plan.

The minimum clean target is therefore:

1. Keep the Customer/Instance Workspace, its public contracts, and the
   self-host deployment path in `hyfens`.
2. Move the global Platform Console and Cloud-only commercial/support/staff
   operations into `hyfens-cloud-web`.
3. Keep the hosted Customer Workspace based on the reusable public customer
   core initially, with Cloud-only capabilities composed around it rather than
   maintaining a second copied implementation.
4. Change the OSS `hyfens-dashboard` image and release description to mean
   Customer/Instance Workspace only.

The currently isolated local UI patch must be split by ownership. Its static
deep-route fix and customer select improvements belong with the public
Customer/Instance Workspace. Its Platform Console action controls and copy are
inputs to the later Cloud migration and must not be integrated into the OSS
customer-only image as-is.

## Audit basis and repository state

The public OSS assessment uses `origin/main` at:

```text
78ae59f5a3f1810cc6ad4c8e45c647afd86dcc6b
```

The active checkout is a dirty local worktree at `3b3a2e3`, 22 commits behind
`origin/main`. It contains unrelated and task-owned uncommitted changes, so it
was not treated as the current public baseline and was not cleaned or reset.

The isolated local UI patch is in:

```text
/tmp/hyfens-local-ui.o1aRjY
```

at the `origin/main` base above. The sibling Cloud project is:

```text
/Volumes/970EvoPlus/Development/projects/auvana-ventures/hyfens-cloud-web
```

The audit inspected source, build inputs, deployment files, current product
documentation, and repository metadata. No source migration or deployment was
performed.

## Current repository topology

### Current OSS topology

```text
hyfens-hq/hyfens
├── CLI
├── MCP
├── Flutter runtime/compiler/instrumentation
├── patch and release contracts
├── control plane and auth
├── self-hosted Compose/deployment
└── dashboard                         dependency-free static bundle
    ├── Customer Workspace shell
    └── Platform Console shell         same HTML/JS/CSS artifact
```

The OSS dashboard has explicit logical shells and host/audience routing, but it
is not two build products. `dashboard/index.html` contains the pre-auth,
customer, and platform shell markup. `dashboard/app.js` contains both route
families and both API clients. `dashboard/Dockerfile` copies the entire
application into `ghcr.io/hyfens-hq/hyfens-dashboard`.

### Current Cloud topology

```text
hyfens-cloud-web
└── site/                              Next.js 16 / React 19 application
    ├── marketing pages
    ├── editorial CMS at /dashboard/content
    └── Cloud billing at /dashboard/billing
```

The local Cloud project has no commits, no configured Git remote, and no tracked
files. Its README identifies the public OSS dashboard as the current customer
dashboard and describes this project as marketing, CMS, and future Cloud-only
account/billing/support/hosted-operations ownership. That intent is coherent,
but the implementation is not yet aligned with the desired final ownership.

## Current dashboard route and feature inventory

The following inventory uses `origin/main`, because the active worktree is an
older dirty checkout. “Needed for OSS Self-Host?” means required for a credible
single-installation product, not necessarily required in every self-host
deployment mode.

| Route / feature | Current repo | Audience | Needed for OSS Self-Host? | Correct product |
| --- | --- | --- | --- | --- |
| Login, session, discovery, PKCE/device approval | `hyfens/dashboard` | SHARED | YES | Public customer core; Cloud consumes the same contracts |
| `/` on a customer origin | `hyfens/dashboard` | SELF_HOST_REQUIRED / CLOUD_CUSTOMER | YES | Customer/Instance Workspace |
| `/applications` | `hyfens/dashboard` | SHARED | YES | Customer/Instance Workspace |
| `/environments` | `hyfens/dashboard` | SHARED | YES | Customer/Instance Workspace |
| `/releases` | `hyfens/dashboard` | SHARED | YES | Customer/Instance Workspace; source-dependent creation remains CLI-led |
| `/patches` | `hyfens/dashboard` | SHARED | YES | Customer/Instance Workspace; source-dependent creation remains CLI-led |
| `/artifacts` | `hyfens/dashboard` | SHARED | YES | Customer/Instance Workspace |
| `/deployments` | `hyfens/dashboard` | SHARED | YES | Customer/Instance Workspace |
| Customer promotion and delivery status | `hyfens/dashboard` + control plane | SHARED | YES where supported | Customer/Instance Workspace |
| Customer rollback handoff | `hyfens/dashboard` + CLI/API contract | AMBIGUOUS | YES as an honest CLI/API path | Customer/Instance Workspace; browser action only if the API is safe |
| Customer `/audit` | `hyfens/dashboard` | SHARED | YES | Customer/Instance Workspace, tenant-scoped |
| Customer `/support` | `hyfens/dashboard` | SHARED / AMBIGUOUS | Capability-dependent | Customer support contract; Cloud provider integration is Cloud-specific |
| Customer `/settings` | `hyfens/dashboard` | SHARED | YES for instance/customer settings | Customer/Instance Workspace |
| Members and organization invitations | `hyfens/dashboard` + control plane | SHARED | YES | Customer/Instance Workspace |
| Customer credentials | `hyfens/dashboard` + control plane | SHARED | YES | Customer/Instance Workspace |
| `/platform` or platform-host `/` | `hyfens/dashboard` | PLATFORM_INTERNAL | NO | Cloud Platform Console |
| `/platform/organizations` or `/organizations` on platform host | `hyfens/dashboard` | PLATFORM_INTERNAL | NO | Cloud Platform Console |
| Platform organization detail | `hyfens/dashboard` | PLATFORM_INTERNAL | NO | Cloud Platform Console |
| `/platform/audit` | `hyfens/dashboard` | PLATFORM_INTERNAL | NO | Cloud Platform Console; separate from tenant audit |
| `/platform/operations` | `hyfens/dashboard` | PLATFORM_INTERNAL | NO, except instance health | Cloud Platform Console; self-host gets instance-health projection only |
| `/platform/users` and staff invitations/actions | `hyfens/dashboard` | PLATFORM_INTERNAL | NO as global staff administration | Cloud Platform Console |
| `/platform/entitlements` | `hyfens/dashboard` | PLATFORM_INTERNAL / CLOUD_CUSTOMER | NO as global operator view | Cloud Platform Console; customer plan view may be a bounded Cloud extension |
| `/platform/commercial` | `hyfens/dashboard` | PLATFORM_INTERNAL | NO | Cloud Platform Console |
| `/platform/support` | `hyfens/dashboard` | PLATFORM_INTERNAL | NO as global queue/internal notes | Cloud Platform Console |
| `/platform/settings` | `hyfens/dashboard` | PLATFORM_INTERNAL | NO | Cloud Platform Console; self-host instance configuration remains OSS deployment/operator scope |
| Staff invitation redemption | `hyfens/dashboard` | PLATFORM_INTERNAL | NO | Cloud Platform Console |
| Global platform metrics/projections | `hyfens/dashboard` + control plane | PLATFORM_INTERNAL | NO | Cloud Platform Console |

### Current navigation

The customer shell currently exposes:

```text
Workspace
  Overview
  Applications
  Environments

Delivery records
  Releases
  Patches
  Artifacts
  Deployments
  Audit
  Support

Account
  Settings
```

This is the correct basis for an OSS Customer/Instance Workspace, subject to
capability-driven self-host behavior.

The platform shell currently exposes:

```text
Platform
  Overview
  Organizations
  Security & audit
  Operations

Administration
  Platform users
  Plans & entitlements
  Commercial
  Support
  Platform settings
```

This is a coherent internal-console navigation, but it does not belong in the
default OSS self-host image. It is not made appropriate for OSS distribution
merely by being hidden from customer navigation.

The platform shell does not use the customer membership switcher as its
directory. That separation should be preserved when the shell is moved.

## `hyfens-cloud-web` current inventory

| Route / feature | Current implementation | Current status | Intended ownership |
| --- | --- | --- | --- |
| `/`, `/product`, `/pricing`, `/security`, `/self-hosted`, `/open-source` | Next.js marketing pages | Implemented local prototype | Cloud/public website |
| `/terms`, `/privacy`, `/blog`, `/news` | Next.js editorial/legal pages | Implemented local prototype | Cloud/public website |
| `/login` | Handoff page linking to `NEXT_PUBLIC_HYFENS_DASHBOARD_URL`, defaulting to `https://app.hyfens.com` | Implemented handoff; no local dashboard auth | Shared entry point, customer auth remains in the dashboard contract |
| `/dashboard` | Redirects to `/dashboard/content` | Implemented alias | Cloud CMS |
| `/dashboard/content` | `PlatformAuthProvider`, CMS sign-in, editorial workspace | Implemented local prototype | Cloud/private CMS |
| `/dashboard/billing` | Owner/billing authority, billing workspace | Implemented local prototype | Cloud billing/customer commercial surface |
| `/cms`, `/cms/billing` | Redirect aliases | Implemented | Cloud compatibility aliases |
| `/api/billing` | Server-side billing operations | Implemented local prototype | Cloud billing |
| `/api/billing/webhook` | Razorpay webhook/HMAC handling | Implemented local prototype | Cloud billing/provider integration |
| Customer Workspace routes | None | MISSING | Reuse public OSS customer core or integrate a versioned public package |
| Global Platform Console routes | None | MISSING | Implement in `hyfens-cloud-web` after baseline/contracts are established |
| Global support/staff/operations | None | MISSING | Cloud/private product |

The Cloud project has a separate Next.js design-token implementation and auth
helper, but it does not yet provide a shared web package or a production-ready
customer/platform application. Its `getOverview` adapter is currently unused.
Both projects call the same broad auth endpoint family (`auth/login`,
`auth/me`, `auth/refresh`, and `auth/logout`), but their clients differ in
audience defaults and token lifecycle. This is auth-contract overlap, not a
reason to copy either client wholesale.

## Product boundary findings

### OSS self-host requirements

The public repository must retain enough web capability for a user who clones
only `hyfens` to operate a self-hosted installation. The required baseline is:

- organization and application/environment context;
- application and environment setup and mutable management;
- releases, patches, artifacts, deployments, promotion, and status records;
- members, invitations, credentials, and tenant audit;
- login, session, discovery, CLI authorization, and device approval;
- self-host bootstrap and operator documentation; and
- instance-health and configuration surfaces only where they are genuinely
  local/self-host concerns.

The self-host deployment guide describes Docker Compose, PostgreSQL, MinIO,
control-plane/dashboard images, first-owner bootstrap, TLS, backups, upgrades,
and recovery. Those are OSS responsibilities. Self-hosting does not imply
global Hyfens staff, Cloud revenue, Cloud support queue, or managed fleet
operations.

### Cloud Customer Workspace

Cloud customers need the same core customer lifecycle as self-host users, plus
Cloud-specific capabilities such as managed onboarding, subscription/plan
visibility, Cloud support, and managed-service information where those
contracts actually exist. The core customer resource model should not be
duplicated merely because the deployment is hosted.

Recommended ownership is a reusable public customer core sourced from OSS,
deployed to `app.hyfens.com`, with Cloud-only composition/extensions owned by
`hyfens-cloud-web`. If the Cloud application eventually needs an independent
build, extract a versioned public customer-core package rather than copying
pages between repositories.

### Platform Console

The Platform Console operates the Hyfens business/platform, not a customer
organization. Its current concepts include:

- all authorized customer organizations and cross-tenant inspection;
- global platform metrics and operations;
- commercial projections, plans, and entitlements;
- Cloud support queue and platform-only internal notes; and
- Hyfens staff/capability/session administration.

These are Cloud/internal responsibilities. They are not required for an
ordinary self-host installation and should not be part of the public
`hyfens-dashboard` image. A self-host operator may need local instance health
and customer administration, but that is not the global Platform Console.

### Bootstrap and staff terminology

The implementation contains several related but distinct concepts that should
not be collapsed:

| Concept | Current evidence | Correct interpretation |
| --- | --- | --- |
| `--bootstrap` | Creates initial organization/application/environment and machine control/delivery material | Self-host/infrastructure initialization |
| `--bootstrap-owner` | Creates the first human owner for an existing tenant scope | Customer/instance bootstrap owner |
| `--bootstrap-admin` | Creates a content administrator | Editorial/CMS administration |
| Demo `super-admin` | Demo seed can give one identity separate customer and platform memberships | Test convenience, not a general ownership model |
| Platform owner/`super-admin` | Current compatibility gate combines email allowlist, platform audience/membership, owner/profile checks, and capabilities | Global Platform Console access; should be made an explicit Cloud staff model |

The current `HYFENS_PLATFORM_ADMIN_EMAILS` self-host setting and bootstrap/demo
terminology make the distinction easy to misunderstand. This is a contract
and documentation risk to resolve during migration; it is not a reason to
expose Cloud staff administration to self-host customers.

### Support and operations

Customer support case viewing/replying can remain a public customer contract if
the installed deployment provides it. Cloud support queue, assignment,
internal notes, and platform audit are private platform capabilities. A
self-host installation may instead provide local support/contact configuration
or a capability-disabled state. It must not silently point at Hyfens's global
support backoffice.

Likewise, self-host health means the local control plane, database, object
store, and related instance signals. Cloud operations means managed fleet and
provider state. The two must use separate projections even if they share low-
level health primitives.

## OSS image and release boundary

The current `dashboard/Dockerfile` copies `index.html`, `app.js`, auth/device/
CLI pages, styles, icons, and runtime configuration into one Nginx image. The
platform route constants, platform renderers, platform API calls, commercial
view, support view, staff view, and platform settings are therefore physically
present in the public image. Host routing and server-side capabilities prevent
ordinary users from executing unauthorized operations, but this is still one
combined public product artifact.

`.github/workflows/release-images.yml` publishes that image as:

```text
ghcr.io/hyfens-hq/hyfens-dashboard
```

The target meaning should become:

```text
OSS Customer/Instance Workspace only
```

It should retain customer auth/discovery/CLI/device flows and customer domain
features, but exclude global Platform Console navigation, client code, and
Cloud-only commercial/support/staff operations. A self-host-specific instance
health view may remain only if it is explicitly modeled as local instance
administration rather than global platform operations.

This requires a future build/source split before the image contract is changed:

1. extract or isolate a customer-core entry point;
2. keep the public self-host build free of global platform modules;
3. create a Cloud build/route boundary for `platform.hyfens.com`;
4. update the image README, Compose references, release workflow, and docs; and
5. run self-host and Cloud auth/tenant acceptance again.

No image or workflow was modified by this audit.

## Authorization and security boundary

The current control plane has an explicit `platform` authorization audience and
capabilities. Platform endpoints fail closed against ordinary customer
sessions, and platform navigation is separate from customer membership
switching. Those controls are valuable and must be retained.

They do not answer the repository-ownership question. A publicly licensed
bundle can contain code that is inaccessible to most users, but its presence
still makes the global platform implementation public and distributable. The
future split must preserve:

- one identity/authentication system where practical;
- distinct customer and platform audiences;
- explicit Cloud staff capabilities;
- tenant-scoped customer APIs;
- no customer-session impersonation for platform inspection;
- separate customer and platform audit scopes; and
- redaction of credentials, provider secrets, and internal support notes.

The audit also found adjacent contract drift that should be corrected during
the migration, not silently ignored:

- the OSS dashboard README says session material is memory-only while the
  current client uses `sessionStorage`; and
- the root developer contract omits newer platform routes and describes some
  customer mutations as pending even though later source/docs implement them.

These are documentation/auth-client alignment issues, not a reason to block
the ownership decision.

## Licensing and commercial implications

The public repository is Apache-2.0. Keeping Platform Console code there means
that code can be used, modified, hosted, and redistributed under Apache-2.0,
subject to the license, attribution, notices, and trademark rules. Moving the
Platform Console out of future OSS releases can establish the intended future
commercial boundary, but it cannot retroactively make already-published source
or binaries private and does not change the existing license.

Apache-2.0 is compatible with the intended business model:

- a complete self-hosted baseline remains public;
- Hyfens Cloud can charge for hosting, support, reliability, upgrades,
  managed storage, commercial services, and Cloud-only operations; and
- private Cloud application/server code can remain private when it is not
  copied into the public distribution.

This does not require a license change. It does require that future OSS images
and archives continue to carry `LICENSE` and `THIRD_PARTY_NOTICES.md`. The
untracked/design-only `docs/architecture/oss-commercial-boundary.md` still
describes the license as a placeholder, which conflicts with the actual
Apache-2.0 license and should be corrected in a later documentation pass.

## Shared-code and duplication analysis

| Concern | Current location(s) | Classification | Boundary recommendation |
| --- | --- | --- | --- |
| Design tokens, typography, colors, primitives | OSS static CSS; Cloud Next CSS | SHARE | Define a small versioned public token/primitive contract; do not share navigation/business logic by copy |
| Auth endpoint contract and audience semantics | OSS control plane/client; Cloud `platform-auth.ts` | SHARE | Share versioned API/auth contract and conformance fixtures; keep clients repository-local until a package is justified |
| API models/transport/error semantics | OSS `DashboardApi`; Cloud CMS/billing clients | SHARE | Share generated or documented public contracts where stable; do not copy whole clients |
| Customer organization/application/environment pages | OSS dashboard | KEEP_IN_OSS | Keep public customer core; Cloud consumes/deploys it and adds capability-driven extensions |
| Customer releases/patches/deployments/audit | OSS dashboard/control plane | KEEP_IN_OSS | Required for self-host; Cloud uses the same contract |
| Customer members/invitations/credentials | OSS dashboard/control plane | KEEP_IN_OSS | Required for self-host; Cloud may add Cloud delivery/provider behavior |
| Platform navigation and overview | OSS dashboard | MOVE_TO_CLOUD_WEB | Rebuild/source-own in Cloud; do not retain in the OSS customer image |
| Platform organization directory/detail | OSS dashboard/control plane | MOVE_TO_CLOUD_WEB | Keep explicit platform projections and Cloud authorization |
| Platform staff, support, commercial, operations | OSS dashboard/control plane | MOVE_TO_CLOUD_WEB | Cloud/private; no self-host global queue or staff model |
| Customer support entry | OSS dashboard/control plane | SPLIT | Public customer contract plus Cloud support provider; self-host capability-driven |
| Audit primitives | OSS control plane; Cloud needs platform events | SPLIT | Customer tenant audit stays public; platform operational audit stays Cloud/private |
| Cloud CMS and editorial UI | Cloud | MOVE_TO_CLOUD_WEB | Already Cloud-owned; never copy into OSS dashboard |
| Cloud billing/Razorpay/webhooks | Cloud | MOVE_TO_CLOUD_WEB | Already Cloud-owned; provider integration and commercial authority remain private |
| Navigation/shells | Both projects | SPLIT | Separate customer and platform shells; share only primitives |

The lowest-maintenance sharing mechanism is a versioned public contract and,
only where repeated UI reuse is proven, a small public customer-core package
or build artifact. A git submodule or unreviewed cross-repository copying is not
recommended. Product boundaries take priority over superficial code reuse.

## Evaluation of repository options

### Option 1 — OSS self-host UI plus separate Cloud frontend

This satisfies the self-host invariant and makes Cloud ownership clear. It is
viable if the Cloud frontend consumes stable public customer contracts and does
not fork customer lifecycle pages unnecessarily. Its main risk is duplicate
Customer Workspace implementations.

### Option 2 — Shared OSS customer app plus private Platform Console

This is the recommended base model. OSS owns the reusable Customer/Instance
Workspace, and `hyfens-cloud-web` owns Cloud-only composition plus the complete
global Platform Console. It minimizes duplication while keeping self-hosting
credible.

### Option 3 — Entire frontend in Cloud

This is not acceptable without a separately public, versioned self-host UI
package or image. A self-host installation must not require access to a
private repository for essential administration. It would also couple OSS
runtime releases to a private web repository.

### Exact same Cloud and self-host Customer Workspace?

Not the entire frontend. The customer domain concepts and core workflows should
be the same and should share contracts/components where that lowers maintenance
cost. The deployment shell, capability discovery, managed billing/support
extensions, and self-host instance capabilities can differ. The global Platform
Console must not be included merely because the customer core is shared.

## Current local patch disposition

The patch was validated in the isolated worktree but has not been committed to
the active repository. Disposition is per patch component:

| Patch component | Disposition | Reason |
| --- | --- | --- |
| `dashboard/index.html` `<base href="/">` deep-route fix | APPLY_TO_OSS | Corrects static Customer/Instance Workspace asset resolution and self-host/deep-route behavior. Cloud can consume the resulting customer build later. |
| Customer member role-select wrapper and related select styling | APPLY_TO_OSS | Customer member management is a public/self-host capability. |
| Generic `supportSelect` primitive/style | SPLIT | Keep the customer primitive in OSS; provide the equivalent platform control in the Cloud shell or a future shared UI package. |
| Platform copy changes replacing misleading “Read-only” wording | APPLY_TO_CLOUD_WEB | These messages belong with the Platform Console migration; do not integrate them into a customer-only OSS image. |
| Platform staff role controls, owner protection, activate/deactivate guidance | APPLY_TO_CLOUD_WEB | Platform staff administration is Cloud/internal. Preserve the semantics when the Cloud Platform Console is established. |
| Platform role-select styling | SPLIT | Reuse the primitive only if a shared package is deliberately established; the feature implementation belongs in Cloud. |
| `dashboard/test_serve.py` assertions for the base/customer behavior | APPLY_TO_OSS | Keep coverage for the public static customer build. Platform-specific assertions follow the Cloud implementation. |
| `dashboard/test_serve.py` assertions for platform action controls | APPLY_TO_CLOUD_WEB | Move with the Platform Console contract, not the customer-only image. |
| Temporary `deploy/p2/Dockerfile` replacement using floating `dart:stable`/runtime execution | DISCARD_AS_SUPERSEDED | It weakens the pinned, reproducible release image and is not a product-boundary fix. |
| Temporary P2 harness/task metadata | APPLY_TO_OSS only as local evidence if needed | It is self-host/local validation material, not Cloud source. Do not migrate it as product code. |

The patch must not be applied wholesale to the current dirty checkout. First
establish the migration baseline and resolve the public customer-build versus
Cloud-platform-build ownership.

## Migration inventory

| Module | Current location | Target location | Classification | Why |
| --- | --- | --- | --- | --- |
| Customer shell and customer routes | `hyfens/dashboard` | OSS customer build; Cloud hosted deployment | KEEP_IN_OSS | Required for self-host; reusable hosted customer product |
| Platform shell/navigation | `hyfens/dashboard` | `hyfens-cloud-web` Platform Console | MOVE_TO_CLOUD_WEB | Global internal audience and product responsibility |
| Customer `DashboardApi` methods | `hyfens/dashboard/app.js` | OSS control plane/client contract; Cloud adapter | SHARE | Same tenant model across deployments |
| Platform `DashboardApi` methods | `hyfens/dashboard/app.js` | Cloud client and private platform API projection | MOVE_TO_CLOUD_WEB | Avoid shipping global platform client in OSS image |
| Customer control-plane APIs | `packages/control_plane` | OSS; Cloud consumes compatible APIs | KEEP_IN_OSS | Core self-host domain and public contract |
| Global platform projections/metrics | OSS control plane | Cloud platform API or explicit private projection | SPLIT | Retain only local instance-health concepts in OSS |
| Customer auth/discovery/device pages | OSS dashboard/control plane | OSS; Cloud-compatible client | KEEP_IN_OSS | Required for CLI/self-host and shared identity contract |
| Platform audience/staff authorization | OSS control plane | Shared contract; Cloud-owned staff implementation | SPLIT | Keep fail-closed semantics; separate durable Cloud staff roles |
| Customer audit | OSS control plane/dashboard | OSS and Cloud customer workspace | KEEP_IN_OSS | Tenant-scoped product capability |
| Platform audit | OSS control plane/dashboard | Cloud Platform Console | MOVE_TO_CLOUD_WEB | Global operational/security scope |
| Customer support contract | OSS control plane/dashboard | OSS bounded customer surface plus Cloud integration | SPLIT | Self-host and Cloud delivery differ |
| Cloud CMS/editorial UI | `hyfens-cloud-web/site` | `hyfens-cloud-web` | MOVE_TO_CLOUD_WEB | Already in the correct Cloud repository; no OSS migration is intended |
| Cloud billing/Razorpay/webhooks | `hyfens-cloud-web/site` | `hyfens-cloud-web` | MOVE_TO_CLOUD_WEB | Already in the correct Cloud repository; provider secrets and commercial authority remain private |
| `hyfens-dashboard` Docker image | OSS `dashboard/Dockerfile` | OSS customer/instance image | REWORK | Remove global Platform Console code from shipped artifact |
| Dashboard release image workflow | OSS `.github/workflows/release-images.yml` | OSS customer image workflow plus Cloud web workflow | SPLIT | Different release/deployment products |
| Self-host Compose/dashboard deployment | OSS `deploy/self-hosted` | OSS | KEEP_IN_OSS | Essential public self-host distribution |
| Cloud marketing/Next deployment | Cloud `deploy/web/site` | `hyfens-cloud-web` | MOVE_TO_CLOUD_WEB | Already correctly scoped under Cloud ownership |

For modules already in `hyfens-cloud-web`, `MOVE_TO_CLOUD_WEB` means “formalize
and preserve Cloud ownership”; it does not imply physically moving files that
are already in the target repository. The inventory uses the requested action
vocabulary throughout.

## Recommended target architecture

```text
hyfens-hq/hyfens  (public Apache-2.0 OSS)
├── CLI + MCP
├── runtime/compiler/instrumentation
├── patch/release/control-plane contracts
├── customer auth/discovery/device contracts
├── self-host Compose and deployment
└── Customer/Instance Workspace
    ├── organizations in the current tenant context
    ├── applications and environments
    ├── releases, patches, artifacts, deployments, audit
    ├── members, invitations, credentials
    └── local/self-host capability-driven settings/health

hyfens-cloud-web  (private Cloud web product)
├── marketing and editorial CMS
├── Cloud login/onboarding composition
├── Cloud Customer Workspace extensions
│   ├── managed-service context
│   ├── Cloud billing/plan views
│   └── Cloud support/provider integrations
└── Platform Console at platform.hyfens.com
    ├── all authorized organizations
    ├── commercial/subscriptions/entitlements
    ├── Cloud support queue/internal notes
    ├── staff/capabilities/session administration
    ├── managed operations
    └── platform audit

Shared boundary
├── versioned Auth v1/audience/capability contract
├── versioned customer/control-plane API contract
├── generated or reviewed API models where stable
└── small public UI/token package only when proven necessary
```

Deployment target:

```text
hyfens.com              → Cloud marketing/public website
app.hyfens.com          → hosted Customer Workspace based on public customer core
platform.hyfens.com    → private Cloud Platform Console
api.hyfens.com          → managed control plane
self-host.example.com   → OSS control plane + OSS Customer/Instance Workspace
```

Self-host deployments should not automatically expose `platform.hyfens.com`
semantics or global Cloud staff operations. A future self-host operator UI, if
needed, should be a capability-driven Instance Console within the OSS customer
product and should never be called the global Platform Console.

## Recommended migration sequence

This is a plan only; it was not executed.

1. Freeze the product/repository ownership decision in maintainer-reviewed
   architecture documentation.
2. Establish a clean baseline for `hyfens-cloud-web` (repository ownership,
   remote, CI, deployment authority, and auth/API contract version).
3. Define the OSS customer-build entry point and the Cloud Platform Console
   entry point without changing public API semantics.
4. Move/reimplement the Platform Console shell, client methods, and global
   projections in `hyfens-cloud-web`; keep explicit platform audience and
   capabilities.
5. Reconcile the Cloud Customer Workspace with the OSS customer core. Prefer a
   versioned public package or deployable artifact over copied pages.
6. Remove Platform Console modules from the OSS dashboard image and update the
   Dockerfile, Compose documentation, image README, and release workflow.
7. Split support/audit/operations projections so customer, self-host instance,
   and Cloud platform scopes are explicit.
8. Resolve bootstrap-owner versus Cloud staff terminology and replace the
   email/profile compatibility gate with a durable Cloud staff capability
   contract when that work is authorized.
9. Run focused auth, tenant-isolation, self-host image, Cloud customer, and
   Platform Console acceptance before any live deployment or DNS change.

## Documentation corrections required later

The following current statements need reconciliation after the ownership
decision is approved:

- `README.md`, `dashboard/README.md`, and `docs/OSS_CLOUD_SOURCE_BOUNDARY.md`
  currently describe the public dashboard as containing the complete two-shell
  model. They should describe the public Customer/Instance Workspace and the
  separate Cloud Platform Console.
- `docs/HYFENS_CLOUD_COMMERCIAL_BOUNDARY.md` currently treats the reusable
  dashboard broadly as an OSS surface. It should distinguish customer core from
  Cloud-only platform operations.
- `docs/architecture/dashboard-separation.md` correctly distinguishes
  audiences, but its statement that the global Platform Console is not
  automatically exposed in self-hosting is weaker than the desired build
  boundary: the future image should not contain that global code by default.
- `docs/architecture/oss-commercial-boundary.md` is marked design-only and has
  stale license wording. It must not be treated as authoritative over the
  actual Apache-2.0 license.
- `deploy/self-hosted` and `HYFENS_PLATFORM_ADMIN_EMAILS` documentation must
  distinguish local instance administration from Hyfens Cloud staff access.

These changes are intentionally not made in this audit.

## Required decision answers

1. **Should any dashboard remain in `hyfens` OSS?**  Yes: the
   Customer/Instance Workspace and the auth/discovery/device/CLI web surfaces
   required to operate a self-hosted installation.
2. **What exact functionality belongs in the OSS dashboard?**  Tenant-scoped
   organization context, applications, environments, releases, patches,
   artifacts, deployments, promotion/status, audit, members/invitations,
   credentials, settings, setup, and capability-driven local instance health.
3. **Should Platform Console move entirely to `hyfens-cloud-web`?**  Yes for
   the global Cloud Platform Console, including organizations, commercial,
   global support, staff, managed operations, and platform audit. Public
   history cannot be made private retroactively, but future source/image scope
   should move.
4. **Where should Hyfens Cloud Customer Workspace live?**  Its reusable core
   should remain sourced from the public OSS customer product initially and be
   deployed at `app.hyfens.com`; Cloud-only billing/support/managed-service
   extensions belong in `hyfens-cloud-web`.
5. **Should Cloud Customer Workspace reuse OSS customer components?**  Yes,
   through a versioned public customer-core package or artifact once the
   boundary is stable. Do not maintain an untracked copy or duplicate the
   entire dashboard.
6. **What should `hyfens-dashboard` contain?**  The public
   Customer/Instance Workspace only, plus its auth/discovery/CLI/device
   surfaces and legally required notices. It should not contain global
   Platform Console, commercial, Cloud support-backoffice, or staff code.
7. **What happens to the validated local patch?**  Split it: apply the base
   deep-route and customer select fixes to the OSS customer build; carry the
   Platform Console wording/action/role-control pieces into the Cloud
   migration; discard the weak temporary Dockerfile replacement as a release
   input.
8. **What migration is necessary before further dashboard development?**
   Establish a clean Cloud repository baseline, freeze shared auth/API
   contracts, isolate customer and platform build entry points, move the global
   Platform Console to Cloud, reduce the OSS image, then revalidate both
   deployments. Do not add more dashboard features before this boundary is
   approved.

## Non-goals and stop condition

This audit does not:

- migrate or delete dashboard code;
- commit or push the isolated patch;
- modify `hyfens-cloud-web`;
- change Docker, Compose, DNS, TLS, or production deployments;
- change CLI, MCP, runtime, patch, or release behavior; or
- create a new dashboard implementation phase.

Task 245 remains in progress only because maintainer review is required. The
isolated patch remains uncommitted and the current dirty worktree remains
untouched.

## Final disposition

```text
WEB PRODUCT BOUNDARY — CLOUD/OSS FRONTENDS MUST BE RESTRUCTURED
```

The evidence is sufficient to make the ownership decision. The current
architecture is not correct as a release boundary, but the correct response is
not to remove the OSS dashboard. Retain the public self-host customer core and
move the global Cloud Platform Console and Cloud-only web operations into the
private Cloud product before further dashboard implementation or deployment.
