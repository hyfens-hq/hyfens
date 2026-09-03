# Hyfens Dashboard Separation Audit

Date: 2026-09-03

Disposition: `DASHBOARD SEPARATION — CURRENT STATE UNDERSTOOD`

## 1. Executive summary

The current dashboard is one dependency-free static application with one authenticated shell and one navigation tree. It presents a tenant-scoped, read-only customer record projection and a separate aggregate platform-metrics page inside that same shell.

The implementation has a meaningful security boundary for the data currently exposed:

- Organization overviews are requested with an explicit organization ID and are authorized by the control plane against the authenticated tenant scope.
- Platform metrics use a separate backend authorization check requiring a configured platform-admin email and an owner membership with the `super-admin` profile.
- The dashboard does not currently expose browser-side write actions.

The product boundary is nevertheless mixed at the UX and application-architecture level:

- A platform operator enters the same dashboard as a customer, with a platform profile added to the customer context model.
- The organization card is a membership switcher, not a platform organization directory.
- Customer resource pages remain in the same navigation and shell when a platform profile is selected.
- `Overview`, `Settings`, `Audit`, the context selectors, and the account surface combine shared identity concerns with customer or platform concerns.
- The platform console has only aggregate metrics; it does not have the organization, support, entitlement, incident, or cross-tenant inspection capabilities expected of an operating console.
- The customer workspace is largely a read-only projection. It lacks dashboard CRUD for organizations, applications, environments, members, credentials, and delivery actions even though several corresponding control-plane APIs exist.

Recommended direction:

```text
hyfens.com
    public website / onboarding

app.hyfens.com or self-hosted instance origin
    Customer Workspace

admin.hyfens.com or platform.hyfens.com
    Hyfens Platform Console

api.hyfens.com or self-hosted control-plane origin
    shared control-plane APIs
```

Keep authentication, API transport, design tokens, primitives, record presentation, and error handling reusable. Split the application shells, navigation, overview projections, organization semantics, authorization audience, and privileged workflows. Do not solve this with one large menu whose entries are merely hidden by role, and do not duplicate the entire frontend.

No dashboard, backend, route, DNS, repository, or authorization code was changed during this audit. The only intentional tracked outputs are this report and its coordinating task record.

## 2. Intended dashboard model

The target product model has four related but distinct surfaces.

| Surface | Audience | Responsibility | Must not become |
| --- | --- | --- | --- |
| Hyfens Platform Console | Hyfens owners, platform administrators, support, operations, security, and commercial operators as authorized | Operate the Hyfens service and inspect platform-wide state | The normal customer product workspace |
| Customer Workspace | Customer owner/admin/developer/release/audit users | Operate one customer organization and its applications, environments, releases, patches, deployments, members, credentials, and audit | A directory of all Hyfens customers or internal infrastructure |
| Public Website | Prospective and existing users before authentication | Marketing, product explanation, pricing, documentation, signup, and login entry points | An authenticated operational console |
| Shared Authentication | Humans and CLI authorization flows | Login, registration, session lifecycle, profile selection, device/PKCE authorization, and logout | A substitute for platform/customer application boundaries |

Managed Cloud and Self-Hosted should use the same Customer Workspace concepts and control-plane contract. The profile or endpoint changes; the customer information architecture should not fork. Self-host-specific instance/operator information should be capability-driven and should not turn a customer page into a global platform page.

## 3. Current frontend architecture

### 3.1 Structure

The dashboard is a single static HTML/CSS/JavaScript application:

- `dashboard/index.html` defines the pre-auth view, authenticated shell, sidebar, context controls, record drawer, and keyboard-shortcut dialog.
- `dashboard/app.js` contains the API client, session state, routing, profile/organization selection, page rendering, filtering, search, and transition behavior in one browser module.
- `dashboard/serve.py` serves static assets and acts as a narrowly allow-listed local development proxy.
- `dashboard/tokens.css`, `dashboard/styles.css`, and `dashboard/auth-flow.css` provide the shared visual system.
- There are no separate Customer Workspace and Platform Console applications, shells, route trees, or frontend packages.

The authenticated DOM has one sidebar brand labelled `hyfens / control plane`, one organization context card, one navigation tree, one context bar, and one page region. The platform link is initially hidden and is made visible when any authenticated profile has `platform: true` (`dashboard/index.html:243-511`; `dashboard/app.js:1309-1321`).

### 3.2 Data-loading model

`DashboardApi` currently exposes only two authenticated dashboard data reads:

```text
GET /v1/organizations/{organizationId}/overview
GET /v1/platform/metrics?profile={profileName}
```

The same API client also handles discovery, login, registration, session refresh/logout, and `/auth/me` (`dashboard/app.js:328-475`). The organization overview is a composite read model containing applications, environments, releases, patches, artifacts, rollouts, and redacted audit data. The page renderers filter that response locally rather than calling separate list/detail endpoints.

The local dashboard proxy forwards authentication, public onboarding, discovery, platform metrics, and the organization overview. It intentionally does not forward arbitrary dashboard mutation/resource routes (`dashboard/serve.py:1-59`, `dashboard/serve.py:143-197`). This explains why the current dashboard is a read-only surface even though the control plane has several write APIs.

### 3.3 Shell and context behavior

The sidebar organization selector is populated by grouping the authenticated user's profiles by organization ID. It does not query or display a directory of all organizations. Each option points to a membership/profile context (`dashboard/index.html:257-275`; `dashboard/app.js:1339-1358`).

The main context bar then exposes Profile, Application, and Environment selects for the selected membership (`dashboard/index.html:474-506`). Platform profile selection clears application/environment selections, but it remains a mode inside the same customer-oriented context model (`dashboard/app.js:1323-1330`).

The platform page is a distinct renderer, but not a distinct product shell. It shows aggregate organization/user/session/application/environment/release/patch/rollout/audit counts and process-local service metrics. Its own copy correctly says that raw tenant records are not returned and that process metrics are not an availability or SLA claim (`dashboard/app.js:1672-1782`).

### 3.4 Evidence from supplied screenshots

The supplied screenshots corroborate the source inventory:

- The dashboard home and Applications screenshots show the same organization card, context selectors, control-plane breadcrumb, delivery-record navigation, and read-only record presentation.
- The exact-record screenshot shows a drawer-based record surface within the same dashboard shell.
- The login/register screenshots show a shared authentication surface with product positioning content alongside the form.

No fresh route-by-route browser capture was taken in this source audit. The current source and existing dashboard tests provide direct evidence for all routes and state transitions; the supplied screenshots are treated as supporting UX evidence rather than as a substitute for authorization evidence.

## 4. Current route inventory

Status values in this report mean:

- `IMPLEMENTED`: the current frontend surface works for its declared read-only purpose.
- `PARTIAL`: a visible slice exists, but required workflow or scope is incomplete.
- `BACKEND_ONLY`: a relevant control-plane capability exists without a dashboard surface.
- `FRONTEND_ONLY`: a visible concept has no corresponding usable backend capability.
- `MISSING`: no current implementation was found.
- `NOT CURRENT SCOPE`: intentionally outside the current dashboard product surface.

### 4.1 Authenticated dashboard routes

| Route | Page/component | Current navigation | Current apparent audience | Correct target | Primary data/API dependency | Mutation capability | Current authorization guard | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `/` | Overview | Workspace | Customer operator; also reachable from the platform-enabled shell | CUSTOMER | `GET /v1/organizations/{org}/overview` | None in browser | Session gate; backend tenant-scoped overview authorization and read scopes | MIXED / PARTIAL |
| `/platform` | Platform metrics | Workspace, conditionally shown | Platform operator | PLATFORM | `GET /v1/platform/metrics?profile=...` | None in browser | Frontend checks `profile.platform`; backend checks configured email plus owner/`super-admin` membership | IMPLEMENTED, but wrong shell |
| `/applications` | Applications collection | Workspace | Customer developer/operator; platform profile can remain in same shell | CUSTOMER | Organization overview, locally filtered to `applications` | None in browser | Same authenticated tenant-scoped overview read | IMPLEMENTED read-only / PARTIAL workflow |
| `/environments` | Environments collection | Workspace | Customer developer/operator | CUSTOMER | Organization overview, locally filtered to `environments` | None in browser | Same authenticated tenant-scoped overview read | IMPLEMENTED read-only / PARTIAL workflow |
| `/releases` | Releases collection | Delivery records | Customer release operator | CUSTOMER | Organization overview, locally filtered to `releases` | None in browser; CLI/API can register | Same authenticated tenant-scoped overview read | IMPLEMENTED read-only |
| `/patches` | Patches collection | Delivery records | Customer release operator | CUSTOMER | Organization overview, locally filtered to `patches` | None in browser; CLI/API can register/upload/admit | Same authenticated tenant-scoped overview read | IMPLEMENTED read-only |
| `/artifacts` | Artifacts collection | Delivery records | Customer release/operator or auditor | CUSTOMER | Organization overview, locally filtered to `artifacts` | None in browser; API can upload/reconcile | Same authenticated tenant-scoped overview read | IMPLEMENTED read-only |
| `/deployments` | Deployment/rollout records | Delivery records | Customer release/operator or auditor | CUSTOMER | Organization overview, locally filtered to `rollouts` | None in browser; rollout APIs exist | Same authenticated tenant-scoped overview read | IMPLEMENTED read-only / PARTIAL workflow |
| `/audit` | Redacted audit collection | Delivery records | Customer auditor/operator; platform page only has aggregate count | CUSTOMER, plus separate PLATFORM audit later | Organization overview's redacted `audit` projection | None in browser; organization audit export exists in API | Same tenant-scoped overview read; export endpoint separately checks `audit:read` | IMPLEMENTED read-only / SPLIT required |
| `/settings` | Session, memberships, endpoint, unavailable API-key panel | Account | Shared account user plus customer member; not a platform settings console | SHARED + CUSTOMER | `/auth/me` and in-memory/session state | Sign out only; no settings CRUD | Authenticated shell; no per-section audience guard | PARTIAL / MIXED |

The route map is defined centrally in `PAGE_COPY` and `renderCurrentPage` (`dashboard/app.js:15-56`, `dashboard/app.js:3136-3195`). A static route can be opened regardless of whether the profile is a platform profile; the data request and renderer determine whether useful content is shown. This is a presentation guard, not a separate application boundary.

### 4.2 Adjacent shared/public routes

These are not Platform Console or Customer Workspace pages, but they are part of the current dashboard delivery:

| Surface/path | Audience | Current responsibility | Correct classification |
| --- | --- | --- | --- |
| Pre-auth login/register view | Human user | Login and client registration through `auth/login` and `v1/public/register` | SHARED AUTH |
| `/cli/authorize/` | CLI user and browser authorization flow | PKCE-style CLI authorization entry | SHARED AUTH |
| `/device/` and device auth endpoints | CLI/user | Device authorization | SHARED AUTH |
| Public waitlist/newsletter forms | Prospective user | Public intake through `v1/public/waitlist` and `v1/public/newsletter` | PUBLIC WEBSITE / ONBOARDING |
| Authenticated account popover | Human user | Account, privacy, feedback, sign-out affordances | SHARED AUTH + ACCOUNT |

The login right-hand rail is product positioning content, not platform administration. It should eventually be owned by the public website/auth entry experience rather than being interpreted as a third dashboard column.

## 5. Current navigation audit

The current tree is exactly:

```text
Workspace
  Overview
  Applications
  Environments
  Platform                 (conditionally visible)

Delivery records
  Releases
  Patches
  Artifacts
  Deployments
  Audit

Account
  Settings
```

| Current entry | Current classification | Finding |
| --- | --- | --- |
| Overview | MIXED shell / CUSTOMER data | The record projection is organization-scoped, but the same page is the home of a shell that can switch into platform mode. |
| Applications | CUSTOMER | Correctly reads selected-organization application records; it is not a platform application directory. |
| Environments | CUSTOMER | Correctly reads selected-organization environment records; it is not an all-tenant environment view. |
| Platform | PLATFORM | Correct concept, but it is a conditional page in the customer shell and currently contains only aggregate metrics. |
| Releases | CUSTOMER | Customer record view; creation remains CLI/API-driven. |
| Patches | CUSTOMER | Customer record view; creation/admission remains CLI/API-driven. |
| Artifacts | CUSTOMER | Customer record view; artifact operations remain API/CLI-driven. |
| Deployments | CUSTOMER | Customer rollout-record view; not a platform deployment operations console and not runtime health. |
| Audit | CUSTOMER | Redacted organization audit projection; platform operational audit is absent. |
| Settings | SHARED / MIXED | Combines human session details, membership profiles, endpoint information, and an unavailable customer API-key section. |
| Organization card/switcher | CUSTOMER membership context | It switches among organizations where the user has profiles. It is not a Platform Organizations Directory and should not be used to imply that it is one. |
| “Read-only surface” footer | CUSTOMER/implementation constraint | It accurately describes the current browser boundary, but it makes the entire shell feel like an operator inspection console rather than a future customer workspace. |

The central problem is not that every current page contains cross-tenant data. The problem is that two distinct nouns—“customer organization context” and “platform operator context”—are represented by the same shell, selectors, route namespace, and visual hierarchy.

## 6. Role and audience model

### 6.1 Current platform access

There is no formal platform-role type in the inspected human-auth model. Platform status is derived from:

```text
configured platform-admin email
AND
owner membership
AND
profileName == "super-admin"
```

The `/v1/platform/metrics` handler separately calls `authorizePlatformMetrics`; ordinary tenant control scopes alone do not authorize platform aggregate metrics (`packages/control_plane/lib/src/human_auth.dart:1933-1971`, `2263-2288`). The frontend receives `platform: true` in profile metadata and uses it to show the Platform navigation item (`packages/control_plane/lib/src/human_auth.dart:689-730`; `dashboard/app.js:1309-1321`).

Current factual platform role coverage:

| Audience/role | Evidence | Current capability |
| --- | --- | --- |
| Platform owner / super-admin | Configured email plus owner/`super-admin` profile | Platform aggregate metrics and ordinary scopes attached to that membership; no separate console. |
| Platform admin | No distinct formal role found | MISSING as a distinct platform authorization model. |
| Support employee | No distinct role found | MISSING. |
| Operations employee | No distinct role found | MISSING. |
| Security/incident operator | No distinct role found | MISSING. |
| Finance/commercial operator | No distinct role found | MISSING. |

The demo seeder confirms the current convention: it creates `Auvana Ventures Private Limited`, `admin@auvanaventures.com`, an owner membership, and a `super-admin` profile with all current `controlScopes` (`packages/control_plane/lib/src/demo_seed.dart:6-13`, `96-104`, `151-168`). This is useful for local demos but is not a general platform-employee role model.

### 6.2 Current customer roles

| Customer role/profile | Evidence | Current capability |
| --- | --- | --- |
| `owner` | `bootstrapOwner` creates owner with `controlScopes` | Broad control-plane authority for the selected organization scope; dashboard still exposes only reads. |
| `admin` / `content-admin` profile | `bootstrapAdmin` creates `admin` with `contentAdminScope` | Content administration only; not a general customer administrator for release, rollout, credential, or delivery operations. |
| `client` | Public registration creates a `client` membership with `publicClientReadScopes` | Read-only customer profile. |
| Developer, release manager, viewer/auditor | No dedicated roles found | MISSING as explicit customer roles/capability bundles. |

The backend does carry capability sets on memberships, and the control plane authorizes operations against scopes. The frontend mostly uses profile availability and does not build a complete role-aware customer navigation or action model.

### 6.3 Shared identity

Human login, registration, session refresh/logout, `/auth/me`, CLI authorization, and device authorization are shared infrastructure. A user can have multiple memberships/profiles, and the dashboard groups those profiles into an organization switcher. This is a reasonable shared identity foundation; it should not be duplicated when the shells are separated.

## 7. Backend/API capability map

The following table maps the current control-plane surface to the intended dashboard audiences. “Customer permission” and “Platform permission” describe the current authorization shape, not a recommendation for future privileged access.

| Area | Backend API exists | Customer permission | Platform permission | Frontend surface | Correct dashboard | Gap/status |
| --- | --- | --- | --- | --- | --- | --- |
| Organizations | Bootstrap/persistence and organization-scoped overview exist; no organization directory CRUD route found | Selected memberships can read their own organization overview | No global organization list/detail API found | Organization name and membership switcher only | Customer for current org; Platform for all-org directory | PARTIAL customer; MISSING platform directory |
| Users/members | Global user records, login, registration, and membership persistence exist; member-management routes not found | `/auth/me` exposes the current user's profile metadata only | No platform user administration surface found | Settings membership/profile list | Customer + Platform as separate areas | PARTIAL/backend foundation; management MISSING |
| Applications | Application records appear in overview; release/bundle routes are nested under application IDs; no application CRUD route found | Overview scopes authorize selected organization reads | No cross-tenant inspection API found | Applications page | Customer; separate bounded platform inspection later | PARTIAL customer; MISSING platform directory |
| Environments | Environment records appear in overview; promotion route exists; no environment CRUD route found | Organization-scoped read and promotion authority where credential has scope | No cross-tenant environment view found | Environments page | Customer | PARTIAL |
| Releases | Nested release registration, bundle export/import/admission, and overview reads exist | `release:read`/`release:write` and related scopes are available to authorized control credentials | Only aggregate count through platform metrics | Releases page, read-only | Customer; platform support projection later | PARTIAL |
| Patches | Nested patch registration, artifact upload, admission, and overview reads exist | `patch:read`/`patch:write` and related scopes are available | Only aggregate count through platform metrics | Patches page, read-only | Customer; platform support projection later | PARTIAL |
| Promotions/rollouts | Promotion route and rollout create/read/transition/health/evaluation routes exist | Rollout scopes are tenant-bound | No platform rollout operations UI/API found beyond counts | Deployments page, read-only | Customer delivery; platform inspection later | PARTIAL |
| Rollback | Rollout actions and runtime/rollout state concepts exist; no dedicated dashboard rollback endpoint/screen named in the inspected dispatch | Existing action authority is scope/tenant-bound | No platform rollback console found | No dedicated rollback action | Customer explicit action; platform support action later if authorized | MISSING as dashboard workflow; backend semantics PARTIAL |
| Audit | Organization audit export exists and verifies/filter scopes; overview includes redacted audit | `audit:read` organization scope | Platform aggregate audit count only | Audit page, redacted read-only projection | Customer audit; Platform operational/security audit separately | PARTIAL |
| API/service credentials | Issue and revoke routes exist; discovery advertises credential management | `credential:issue`/`credential:revoke` are available to authorized organization credentials | No separate platform credential-management UI/API found | Settings explicitly marks API-key management unavailable | Customer service-key/CI area; platform credentials separate | BACKEND_ONLY customer; MISSING platform |
| Auth sessions | Login, refresh, logout, `/auth/me`, PKCE/CLI, and device flows exist | Shared human session/profile model | Platform metric gate is separate from ordinary control scopes | Login/register/settings/account menu | Shared auth; separate platform audience later | IMPLEMENTED shared; boundary partial |
| Plans/subscriptions/billing | Organization-scoped billing read/write/plan/subscription/event routes exist | Current routes are organization-scoped and require billing scopes; no customer UI | No platform-wide commercial operations API/UI found | No billing page | Customer billing and Platform commercial operations should be distinct | BACKEND_ONLY |
| Platform metrics | Aggregate platform projection and process service metrics exist | Ordinary tenant owners are denied | Configured platform-admin/super-admin only | `/platform` page | Platform | IMPLEMENTED narrow slice |
| Reconciliation/observations/health | Reconciliation diagnostics, observations, rollout health, evaluation, and scheduling routes exist | Some delivery/health reads may belong to customer operations where explicitly scoped | Instance/platform operations are platform/operator concerns | No dashboard pages | Split by scope; platform first for instance operations | BACKEND_ONLY |
| CMS/content | Public content and authenticated CMS/content admin handlers exist | Content admin capability is narrow and not equivalent to customer admin | Likely internal content/platform surface | No dashboard page | Separate internal/platform or public content surface | BACKEND_ONLY / NOT CUSTOMER MVP |

Relevant dispatch is visible in `packages/control_plane/lib/src/http.dart:391-680`; overview, platform metrics, audit, billing, and credential handlers are at `packages/control_plane/lib/src/http.dart:1423-1665`. The tenant overview projection itself filters persisted records by organization and returns a read-only shape (`packages/control_plane/lib/src/operator_overview.dart:80-170`, `229-295`).

### 7.1 CRUD capability audit

| Entity | LIST | VIEW | CREATE | UPDATE | DELETE/deactivate | Special actions | Current conclusion |
| --- | --- | --- | --- | --- | --- | --- |
| Organization | Membership-derived options only | Current organization in overview | Bootstrap/service only | No dashboard/API route found | No route found | Switch membership context | Customer context is partial; platform directory is missing |
| Members/users | Current user's profiles only | Current identity/profile metadata | Registration/bootstrap only | No member-management route | No route found | Invite/role/deactivate absent | Backend identity foundation, no workspace member management |
| Applications | Yes through composite overview | Yes through record view/drawer | No dashboard/API CRUD route found | No route found | No route found | Release linkage | Customer read-only only |
| Environments | Yes through composite overview | Yes through record view | No dashboard/API CRUD route found | No route found | No route found | Release promotion API exists, no UI | Customer read-only plus backend promotion |
| Releases | Yes through overview | Yes through exact record | CLI/API registration | Immutable record; no UI update | No route found | Bundle export/import/admission | Customer inspect path works; dashboard authoring absent |
| Patches | Yes through overview | Yes through exact record | CLI/API registration | Immutable record; no UI update | No route found | Upload/admit/verify semantics outside dashboard | Customer inspect path works; dashboard authoring absent |
| Rollouts/deployments | Yes through overview | Yes through exact record | Backend route exists | Transition/actions backend route exists | No generic delete route found | Health/evaluate/promote/halt/rollback-related actions | Dashboard action surface missing |
| Audit | Redacted overview projection; export API separately | Yes, redacted | System-generated | No | No | Export and chain verification backend-side | Customer read-only partial; platform audit absent |
| Service/API credentials | No browser list | No browser detail | Backend issue route | No general update | Backend revoke route | One-time token issuance | Customer management backend-only; no platform surface |
| Billing | No dashboard list | Backend organization snapshot | Backend plan/subscription/event routes | Backend plan activation route | No dashboard route | Subscription/event recording | Both customer and platform UI absent |

## 8. Platform Console current coverage

| Capability | Current status | Evidence/current limitation |
| --- | --- | --- |
| Aggregate platform overview | IMPLEMENTED | `/platform` renders counts and rolling activity from `PlatformMetricsProjection`. |
| Process-local service health signals | PARTIAL | The same page renders request/error/latency metrics, but explicitly disclaims fleet availability and SLA meaning. `/healthz`, `/readyz`, and `/metrics` are backend/instance endpoints, not a console workflow. |
| All organizations/customer directory | MISSING | No global list/detail API or frontend route. The current organization selector only knows the signed-in user's memberships. |
| Organization/customer detail | PARTIAL | A platform user may have a tenant membership and view that tenant overview, but this is not a privileged support/customer detail model. |
| Applications/environments across customers | MISSING | Only aggregate counts are available to the platform page. |
| Platform-wide release/patch inspection | MISSING | Only aggregate counts; no bounded cross-tenant support projection. |
| Incident/service operations | MISSING | No incident, status, alert, or operational runbook surface. |
| Storage/provider/deployment state | BACKEND_ONLY / MISSING UI | Control-plane configuration and service metrics exist, but no platform console view or action surface was found. |
| Platform operational/security audit | MISSING | Customer audit is tenant-scoped; platform page only exposes aggregate audit counts. |
| Accounts/platform users/roles | MISSING | No platform user directory or role-management model found. |
| Plans, entitlements, quotas, commercial status | BACKEND_ONLY / MISSING UI | Organization-scoped billing routes exist; no platform commercial console. |
| Credential/revocation operations | BACKEND_ONLY / MISSING UI | Credential issue/revoke is organization-scoped and service-layer/API-driven; platform-specific credential operations are not modeled separately. |
| Safe support access | MISSING | No explicit support session, delegated inspection, or audited impersonation model. This should not be emulated by silently switching to a customer profile. |

The current platform page is therefore a useful internal aggregate read, not a Platform Console. It should be moved into a separate platform shell and expanded only through explicit platform APIs and capabilities.

## 9. Customer Workspace current coverage

| Capability | Current status | Evidence/current limitation |
| --- | --- | --- |
| Organization overview | PARTIAL | Overview page reads the selected organization projection and displays counts/context, but there is no customer organization settings or lifecycle management. |
| Organization switching | PARTIAL | Switches among authenticated memberships; it does not support customer organization creation, invitations, or a directory workflow. |
| Applications | PARTIAL | Read/list/detail presentation exists through the composite overview; create/update/archive and application onboarding are absent. |
| Application identities | PARTIAL | Runtime application identity is displayed in records; separate Android/iOS identity configuration is not a dashboard workflow. |
| Environments | PARTIAL | Read/list/detail presentation exists; create/update/archive and richer environment configuration are absent. |
| Releases | IMPLEMENTED read-only | Exact release records and metadata are visible; authoring remains CLI/API-driven. |
| Patches | IMPLEMENTED read-only | Exact patch records and metadata are visible; authoring/admission remains CLI/API-driven. |
| Deployments/promotions | PARTIAL | Rollout records and promoted pointers are visible; deployment action and runtime success are intentionally not claimed. |
| Rollback | MISSING dashboard workflow | No explicit customer rollback action or screen was found, even though rollout/runtime state contains related concepts. |
| Audit | IMPLEMENTED read-only | Redacted organization audit summary/list is visible; export and deeper verification remain backend-side. |
| Members/invitations/roles | MISSING | Settings lists the current user's memberships/profiles, not organization members or invitations. |
| Service/API keys and CI credentials | BACKEND_ONLY | Issue/revoke APIs exist, but the dashboard explicitly presents management as unavailable. |
| CLI/project onboarding | PARTIAL / docs-only | The dashboard can show identity/context, but does not provide a complete customer onboarding/setup workflow. |
| Profile setup | PARTIAL | Profiles are selected and displayed; there is no full customer profile management experience. |
| Self-hosted instance information | MISSING | Endpoint is part of session context, but instance capabilities/operator information are not a dedicated customer view. |
| Usage/limits | MISSING | No customer usage/quota projection found. |
| Subscription/plan | BACKEND_ONLY | Billing APIs exist; no customer billing/plan page. |

The Customer Workspace is best described as an authenticated, organization-scoped record inspector intended to complement the CLI. It is not yet a complete customer operating workspace.

## 10. Mixed-page findings

### 10.1 Shared shell and platform mode

**Page/surface:** authenticated application shell and navigation.

**Platform concern:** aggregate platform metrics and the concept of a platform operator.

**Customer concern:** organization membership, application/environment context, delivery records, and customer account settings.

**Why this is problematic:** the platform operator and customer are asked to understand the same sidebar, breadcrumb, context bar, and organization card, even though they are acting on different scopes. A conditional Platform link does not create a separate product boundary.

**Recommended destination:** split into Platform Console and Customer Workspace shells, sharing primitives and session infrastructure.

### 10.2 Organization card and switcher

**Page/surface:** sidebar `Organization` card and `Switch organization` select.

**Platform concern:** a platform operator needs an all-customer directory, search, support visibility, and explicit privileged scope.

**Customer concern:** a customer user needs to select one of their own organization memberships.

**Why this is problematic:** the same component can be read as “all organizations” even though it is only profile-derived membership switching. A platform operator with one configured demo membership cannot use it to operate all customer tenants.

**Recommended destination:** keep a customer membership switcher in Customer Workspace; replace the platform version with a Platform Organizations Directory and explicit organization inspection route.

### 10.3 Overview/platform metrics

**Page/surface:** `/` and `/platform`.

**Platform concern:** global organization/user/session/application/environment/release/patch/rollout/audit orientation.

**Customer concern:** one selected organization's current records and runtime-boundary explanation.

**Why this is problematic:** both are called overview-like dashboard experiences and are reached through the same shell/profile model, but their aggregates and authority differ.

**Recommended destination:** Customer Overview under `app`; Platform Overview under `admin`/`platform` with separate platform read models.

### 10.4 Resource pages under platform profile

**Page/surface:** Applications, Environments, Releases, Patches, Artifacts, Deployments, Audit.

**Platform concern:** support/operations may need cross-tenant inspection.

**Customer concern:** the same page labels represent the selected customer's records.

**Why this is problematic:** the route name does not communicate whether the operator is viewing a tenant projection or a platform support projection. The backend currently only provides the tenant projection, so platform inspection is not actually implemented.

**Recommended destination:** keep these pages in Customer Workspace; add explicitly named, bounded platform inspection pages only when their APIs and permissions exist.

### 10.5 Settings

**Page/surface:** `/settings`.

**Mixed concerns:** shared human session, profile/membership metadata, endpoint display, and a placeholder for customer API keys.

**Why this is problematic:** account settings, organization settings, application/environment settings, platform settings, and credential management have different owners and risk levels.

**Recommended destination:** split into shared Account, Customer Organization Settings, Customer Credentials, and Platform Settings/Operations. Keep the session/logout controls shared.

### 10.6 Audit

**Page/surface:** `/audit` plus aggregate platform audit count.

**Platform concern:** internal security, operational, and platform-wide event investigation.

**Customer concern:** an organization's redacted activity history.

**Why this is problematic:** the same “Audit” noun hides two scopes and two actor models.

**Recommended destination:** Customer Audit and Platform Security/Operations Audit as separate routes and APIs.

### 10.7 Authentication and product rail

**Page/surface:** login/register view with product positioning rail.

**Finding:** this is shared authentication and pre-auth product communication, not a dashboard audience mix. It should remain shared infrastructure while marketing content is kept conceptually separate from authenticated operations.

## 11. Shared-component findings

### 11.1 Components that should remain shared

These are legitimate technical/design-system reuse points:

- session bootstrap, refresh, logout, login, registration, PKCE/device authorization adapters;
- API transport, request IDs, typed/structured error handling, retry/session-expiry behavior;
- design tokens, typography, color, spacing, focus states, motion primitives, and accessibility utilities;
- buttons, inputs, selects, tables, filters, search, pagination, empty states, status markers, drawers, and dialogs;
- date/time/identifier formatting and redaction helpers;
- record-detail presentation primitives, provided the data scope is supplied by the owning application;
- capability-aware action controls that consume an explicit authorization model rather than inventing one in the component.

### 11.2 Components that should not be shared as one conditional product component

- Platform navigation and Customer Workspace navigation;
- Platform Overview and Customer Organization Overview;
- Platform Organizations Directory and Customer Organization Membership Switcher;
- platform service/incident/support operations and customer delivery records;
- platform-wide audit/security views and customer organization audit;
- platform commercial/entitlement administration and customer billing/settings;
- support access/impersonation controls and ordinary customer account controls.

Sharing these as one component would preserve the current conceptual ambiguity even if the implementation becomes more modular.

## 12. Security and authorization findings

### 12.1 Positive current controls

- The dashboard has a session-pending gate and restores the authenticated session before showing the app shell (`dashboard/index.html:19-25`; `dashboard/app.js:3627-3655`).
- Authenticated API calls use bearer access tokens and can refresh the session on 401 (`dashboard/app.js:444-475`).
- The overview endpoint is explicitly organization-scoped, and the operator overview projection checks actor/organization ownership and filters records by tenant (`packages/control_plane/lib/src/http.dart:544-547`; `packages/control_plane/lib/src/operator_overview.dart:60-170`).
- Platform metrics are not authorized merely by ordinary tenant control scopes; the backend requires a configured platform identity and matching `super-admin` profile (`packages/control_plane/lib/src/human_auth.dart:1938-1971`).
- The local proxy allow-list does not forward arbitrary origin paths, reducing the browser dashboard's ability to act as a generic control-plane proxy (`dashboard/serve.py:43-59`).
- The current browser surface deliberately omits data mutations, which limits the immediate blast radius of the mixed shell.

### 12.2 Separation findings and risks to address before implementation

1. **Frontend platform detection is not an authorization boundary.** `profile.platform` controls navigation visibility and rendering, but the real protection is only on the platform metrics endpoint. Future platform routes must have backend audience/capability enforcement.

2. **There is no explicit platform audience/role model.** Platform status is derived from email configuration, owner role, and the `super-admin` profile name. That is a narrow gate for metrics, not a durable model for support, operations, security, or finance roles.

3. **The platform profile remains tenant-shaped.** It carries an organization ID and can participate in the same organization/profile selectors. This makes “platform context” and “customer context” easy to confuse and does not provide safe cross-tenant support semantics.

4. **Customer role capabilities are not reflected in a complete route/action model.** The backend has capability sets, but the dashboard has one mostly read-only route tree. Future customer mutations must be checked server-side and represented with explicit capabilities; hiding a button is insufficient.

5. **Audit scopes are not separated in the UI.** Customer audit is tenant-scoped; platform security/operations audit does not currently have a corresponding projection.

6. **Support access is absent, which is safer than implicit impersonation but incomplete for a managed service.** Any future support access must be explicit, time-limited, least-privileged, separately audited, and never implemented as the primary pattern of pretending to be a customer.

7. **Documentation drift exists.** `docs/architecture/domain-tenancy.md` is marked design-only, and older local-control-plane documentation describes a smaller read-only boundary than the current control-plane source. The separation implementation should first establish a current audience/authorization contract and then align docs.

No immediate critical cross-tenant exposure was found in the inspected current dashboard path. The current concerns are architectural ambiguity, missing capabilities, and future authorization risk if write features are added to the existing shell without a boundary.

## 13. Missing Platform Console capabilities

### Required for a platform-operations MVP

1. Separate platform authentication audience, route namespace, shell, and navigation.
2. Platform overview with instance/service health state that distinguishes process-local signals from fleet/availability claims.
3. Organizations directory with search, customer detail, lifecycle status, and explicit tenant scope selection.
4. Bounded cross-tenant application/environment/release/patch inspection APIs and views, with least-privilege support capabilities.
5. Platform users/roles and account status view, without exposing customer credentials.
6. Platform operational/security audit view with actor, tenant, action, and support-access evidence.
7. Plans, entitlements, quotas, subscription status, and commercial operator visibility where the managed product requires it.
8. Service/provider/storage/deployment state appropriate to Hyfens Cloud operations.
9. Incident/status/support tooling or an explicit link to the system that owns those operations.

### Later

- time-boxed audited support sessions;
- advanced usage/analytics and cohort reporting;
- managed backup/restore and multi-region operations;
- enterprise governance, SSO/SCIM, compliance exports, and managed key custody;
- advanced alerting and customer-success tooling.

### Not needed in the Platform Console MVP

- customer application authoring as the primary workflow;
- customer release/patch creation on behalf of operators;
- generic filesystem or arbitrary tenant data browsing;
- public marketing/content editing unless a separate CMS is intentionally owned by the platform organization.

## 14. Missing Customer Workspace capabilities

### Required for a customer MVP

1. Explicit Customer Workspace shell with organization/application/environment context.
2. Customer organization overview and organization settings.
3. Organization creation/join/invitation and member list.
4. Customer role/capability management for owner/admin/developer/release/audit needs, based on backend authorization.
5. Application creation and detail/onboarding, including Android package and iOS bundle identity configuration where supported.
6. Environment creation/configuration and development/staging/production lifecycle.
7. Clear CLI/profile onboarding from the workspace, including copyable safe commands and self-hosted endpoint awareness.
8. Release, patch, verification, promotion/deployment, and explicit rollback workflows, or an honest dashboard-to-CLI handoff for operations not yet supported in the browser.
9. Service/API-key inventory, scoped issuance, one-time display, and revocation for customer CI/service use.
10. Customer audit log with appropriate redaction, filtering, and export/verification affordances.
11. Capability/plan/limit presentation that explains which actions are available in Cloud versus Self-Hosted.

### Later

- teams/projects and richer application grouping;
- rollout cohorts, staged promotion, and advanced deployment controls;
- customer usage analytics and webhooks/integrations;
- customer billing self-service;
- advanced runtime/observability views where the evidence contract supports them.

### Not needed in the Customer Workspace MVP

- all-customer organization directory;
- platform employee/user administration;
- platform-wide incidents and internal provider configuration;
- unrestricted support impersonation;
- internal CMS and platform commercial operations.

## 15. Recommended domain, routing, and repository topology

### 15.1 Domain/routing recommendation

Recommended conceptual topology:

```text
hyfens.com
  Public Website: marketing, pricing, docs, signup/login entry

app.hyfens.com
  Customer Workspace: one customer's organization context

admin.hyfens.com  (or platform.hyfens.com; naming to be finalized later)
  Platform Console: Hyfens internal operations

api.hyfens.com
  Shared managed control-plane API
```

For Self-Hosted, the deployed instance origin should serve the Customer Workspace and API according to the documented profile/endpoint contract. A self-host operator-only surface can be capability-driven and separately labelled; it should not make the customer workspace a global platform console.

The platform hostname should not be treated as a public customer CTA by default. It should have a stronger access policy later—at minimum a separate audience/capability claim and platform-specific authentication checks, with MFA/network controls considered for production operations.

No DNS or routing changes are recommended or made by this audit.

### 15.2 Application/repository recommendation

Current:

```text
one static dashboard app
one app.js state/rendering module
shared CSS/tokens
```

Minimum clean target without immediate duplication:

```text
dashboard/
  shared/
    auth/
    api/
    ui/
    formatting/
  customer/
    shell/
    routes/
    pages/
  platform/
    shell/
    routes/
    pages/
```

If the frontend later moves to a build-capable workspace, the equivalent long-term topology is:

```text
apps/
  customer-dashboard/
  platform-console/

packages/
  ui/
  auth/
  api/
  domain-types/
```

The current dependency-free app can first establish logical modules and two route/shell entry points before a repository-level framework migration. Do not duplicate all CSS, auth, API, table, drawer, or formatting code.

## 16. Migration classification

| Current area | Classification | Recommended treatment |
| --- | --- | --- |
| Auth/session/CLI/device authorization | REUSE | Keep shared; add explicit audience/profile semantics where required. |
| API transport/error/session refresh | REUSE | Share the transport, but create separate customer/platform API service boundaries and typed projections. |
| Design tokens and primitive UI | REUSE | Keep shared and preserve the current visual system. |
| Authenticated app shell/sidebar | SPLIT | Create separate Customer and Platform shells; retain shared layout primitives. |
| Organization card/switcher | MOVE + REWRITE | Keep membership switching in Customer Workspace; replace platform use with an organization directory. |
| Context bar | SPLIT | Customer keeps organization/application/environment context; Platform gets platform scope and explicit tenant inspection context. |
| Customer Overview | MOVE | Keep organization-scoped record overview in Customer Workspace. |
| Platform metrics page | MOVE | Move to Platform Console and rename/reframe as platform overview/operations. |
| Applications/environments/resource collections | MOVE | Customer pages move as read-only baseline; add separate platform inspection only with new APIs. |
| Platform cross-tenant inspection | NEW | Add bounded platform projections and capabilities; do not reuse customer overview as implicit support access. |
| Releases/patches/deployments | MOVE + EXPAND | Customer owns lifecycle; add explicit action/handoff states and rollback workflow. |
| Audit | SPLIT | Customer audit remains tenant-scoped; add platform security/operations audit projection. |
| Settings | SPLIT | Shared account, customer organization/settings/credentials, and platform settings become separate destinations. |
| API-key UI | MOVE + NEW UI | Customer credential management consumes existing issue/revoke APIs; platform credentials remain separate and should not be exposed here. |
| Search/filter/table/drawer primitives | REUSE | Keep generic primitives; page data and scope belong to each dashboard. |
| Backend tenant overview projection | REUSE | Keep as the customer read model; do not broaden it for platform use. |
| Backend platform metrics projection | MOVE/REUSE | Keep as a Platform Console read model; extend only behind platform authorization. |
| Human role/profile model | REWRITE | Evolve from email/profile-name derivation to explicit platform audience/capabilities while preserving existing customer profiles. |
| Public auth/product rail | REUSE + SEPARATE PRESENTATION | Keep auth infrastructure shared; keep public marketing content separate from authenticated shells. |
| CMS/content handlers | NOT CURRENT DASHBOARD SCOPE | Treat as separate public/platform content administration rather than adding it to Customer Workspace. |

No current area needs to be deleted as part of the audit. Existing customer read models and shared UI are useful foundations.

## 17. Recommended implementation order

This is a sequence for a future implementation phase, not work performed here.

1. **Freeze the domain and audience contract.** Define Platform, Customer, Shared Auth, and Public Website nouns; define the customer scope `Organization → Application → Environment` and the platform scope separately.
2. **Define authorization and projection contracts.** Establish explicit platform audience/capability claims, customer roles/capabilities, tenant scope rules, and separate platform/customer read models before adding dashboard writes.
3. **Freeze route and host topology.** Choose the platform hostname, customer hostname/instance behavior, and shared API contract without changing DNS in the boundary-definition step.
4. **Split shells and navigation.** Create two entry points that share UI primitives and auth but have independent navigation, route guards, page copy, and context models.
5. **Move the existing customer read surface.** Move Overview, Applications, Environments, Releases, Patches, Artifacts, Deployments, and Customer Audit into Customer Workspace with the current tenant-scoped overview projection.
6. **Move the current platform metrics surface.** Put aggregate metrics and instance signals in Platform Console, with an explicit platform guard and no customer organization selector.
7. **Add platform MVP read capabilities.** Implement organizations/customer detail, bounded cross-tenant inspection, platform audit/security, role/account status, and operational state only as backend contracts justify them.
8. **Complete Customer Workspace MVP workflows.** Add organization/member/application/environment onboarding, scoped credentials, CLI setup, and explicit release/patch/deploy/rollback or CLI handoff flows.
9. **Split settings and audit fully.** Separate account, organization, credentials, platform operations, customer audit, and platform security audit.
10. **Run managed/self-hosted acceptance.** Verify the same customer concepts against Cloud and Self-Hosted profiles, and ensure platform-only information never appears in customer context.

## 18. Explicit non-goals of this audit

- No dashboard redesign or styling changes.
- No frontend route or shell implementation.
- No backend/API, authorization, role, schema, or migration changes.
- No DNS, hostname, deployment, Docker, or repository topology changes.
- No organization/member/application/environment CRUD implementation.
- No support impersonation implementation.
- No new platform metrics, incident system, billing system, or enterprise capability implementation.
- No deletion, rename, archive, or rewrite of the current dashboard.
- No new task numbering beyond the single coordinating task required by repository instructions.

## 19. Current-state summary table

| Area | Current Audience | Correct Audience | Current Status | Action |
| --- | --- | --- | --- | --- |
| Organization membership switcher | Customer memberships, visually ambiguous for platform | Customer | Partial | KEEP in Customer; REPLACE platform use with directory |
| Organizations directory | None | Platform | Missing | NEW |
| Current organization overview | Customer records inside mixed shell | Customer | Implemented read-only / Partial workflow | MOVE/KEEP |
| Platform metrics | Platform owner/super-admin | Platform | Implemented narrow read-only | MOVE |
| Applications | Customer selected organization | Customer | Implemented read-only | MOVE/EXPAND |
| Environments | Customer selected application | Customer | Implemented read-only | MOVE/EXPAND |
| Releases | Customer release operator/auditor | Customer | Implemented read-only; backend/CLI writes | MOVE/EXPAND |
| Patches | Customer release operator/auditor | Customer | Implemented read-only; backend/CLI writes | MOVE/EXPAND |
| Artifacts | Customer operator/auditor | Customer | Implemented read-only | MOVE |
| Deployments/rollouts | Customer operator/auditor | Customer | Implemented read-only; backend actions | MOVE/EXPAND |
| Rollback | No dashboard audience currently | Customer, with separate platform support later | Missing dashboard workflow | NEW |
| Customer audit | Customer organization | Customer | Implemented redacted read-only | KEEP/EXPAND |
| Platform audit/security | No UI; aggregate count only | Platform | Missing | NEW |
| Members/profiles | Current user's memberships only | Customer member management; platform users separately | Partial/backend foundation | SPLIT/NEW |
| API/service keys | No browser management | Customer | Backend-only | MOVE/ADD |
| Billing/plans | No dashboard UI | Customer billing + Platform commercial operations | Backend-only | SPLIT/NEW |
| Account/session settings | Shared human user | Shared Auth/Account | Partial | REUSE/SPLIT |
| Platform service/provider state | Backend/instance signals only | Platform | Backend-only | NEW platform projection |

## 20. Final disposition

`DASHBOARD SEPARATION — CURRENT STATE UNDERSTOOD`

The current implementation is sufficiently evidenced to proceed to a separately approved implementation phase. The key conclusion is:

```text
Current dashboard:
  one static customer record inspector
  plus a narrow platform metrics page
  inside one mixed shell

Target:
  separate Platform Console and Customer Workspace shells
  shared auth, API transport, UI primitives, and design system
  explicit platform/customer authorization and read models
```

The audit found no demonstrated critical cross-tenant exposure in the currently inspected read paths. It did find a material product/UX separation defect and several missing backend/frontend capabilities that must be addressed before the dashboard can be treated as two complete products.

### Evidence index

- Dashboard shell, navigation, context selectors, and record surface: `dashboard/index.html:243-593`
- Dashboard page map and API adapter: `dashboard/app.js:15-56`, `dashboard/app.js:328-475`
- Routing and platform-profile behavior: `dashboard/app.js:642-685`, `dashboard/app.js:1309-1358`, `dashboard/app.js:3136-3195`
- Overview/platform/resource/settings renderers: `dashboard/app.js:1655-1782`, `dashboard/app.js:1900-2215`, `dashboard/app.js:2240-2335`
- Session bootstrap: `dashboard/app.js:2632-2677`, `dashboard/app.js:3627-3655`
- Local proxy allow-list and read-only boundary: `dashboard/serve.py:1-59`, `dashboard/serve.py:143-197`; `dashboard/README.md:1-13`, `43-99`
- Control-plane route dispatch: `packages/control_plane/lib/src/http.dart:391-680`
- Overview, platform metrics, audit, credentials, and billing handlers: `packages/control_plane/lib/src/http.dart:1423-1665`
- Tenant overview projection: `packages/control_plane/lib/src/operator_overview.dart:8-25`, `80-170`, `229-295`
- Platform aggregate projection: `packages/control_plane/lib/src/platform_metrics.dart:1-92`
- Human memberships, profiles, registration, and platform authorization: `packages/control_plane/lib/src/human_auth.dart:476-564`, `689-730`, `963-1265`, `1933-1971`, `2263-2288`
- Demo platform profile convention: `packages/control_plane/lib/src/demo_seed.dart:6-13`, `96-104`, `151-168`
- Intended tenancy/ownership reference, marked design-only: `docs/architecture/domain-tenancy.md:9-15`, `35-58`, `172-190`
