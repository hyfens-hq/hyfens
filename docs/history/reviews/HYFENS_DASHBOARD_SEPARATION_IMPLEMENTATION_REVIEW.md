# Hyfens Dashboard Separation Implementation Review

Date: 2026-09-03

Disposition: `HYFENS DASHBOARD SEPARATION — IMPLEMENTED WITH BACKLOG`

## 1. Architecture

The dashboard now has an explicit two-shell model in the existing static
bundle:

```text
Customer Workspace
  customer navigation, membership context, tenant-scoped records,
  customer settings/audit/credentials foundations

Platform Console
  platform navigation, platform audience context, aggregate metrics,
  bounded organization directory/detail, platform-audience audit
```

The implementation reuses shared authentication/session lifecycle, API
transport, error handling, redaction, formatting, design tokens, tables,
filters, drawers, and other UI primitives. It does not introduce a frontend
framework or duplicate the entire dashboard.

The intended managed topology is:

```text
hyfens.com       public website
app.hyfens.com   Customer Workspace
platform.hyfens.com Platform Console
api.hyfens.com   shared control-plane API
```

Local routing supports `/` and `/platform`; platform hosts support the
equivalent platform root routes. DNS and production deployment were not
changed.

## 2. Customer shell

`dashboard/index.html` and `dashboard/app.js` now provide a Customer Workspace
shell with:

- customer-only navigation for Overview, Applications, Environments, Delivery
  records, Audit, and Settings;
- customer membership organization switching, explicitly limited to customer
  profiles/memberships;
- organization/application/environment context controls;
- tenant-scoped existing record views for applications, environments, releases,
  patches, artifacts, deployments, and customer audit;
- customer settings panels for workspace context, safe member metadata, and
  credential metadata/revocation;
- CLI handoff copy for workflows that remain CLI/API-driven.

The customer shell does not expose the platform metrics link or platform
organization directory.

## 3. Platform shell

The separate `platform-sidebar` and platform context bar provide the Platform
Console navigation:

```text
Overview
Organizations
Security & Audit
Operations
Platform Settings
```

Platform Overview and Operations use the existing bounded metrics projection.
Organizations uses the new platform directory projection and links to a
read-focused organization detail page. Platform audit displays only events
explicitly marked for the platform audience; customer audit rows are not
relabelled. Platform Settings is intentionally read-only operator metadata
until a distinct platform configuration contract exists.

The shell has no customer organization membership switcher and no customer
session impersonation flow.

## 4. Shared modules

The following remain shared by design:

- session restore, refresh, expiry, logout, and auth/profile selection;
- `DashboardApi` transport, endpoint normalization, bounded proxy behavior,
  structured errors, and redaction;
- common route transitions, tables, filters, drawers, formatting, design
  tokens, typography, and responsive primitives;
- discovery and capability state used by both shells.
- managed endpoint details are presented as `Hyfens Cloud (managed)` in
  authenticated UI metadata, while self-hosted origins remain identifiable.

Navigation, overview renderers, context bars, settings ownership, audit
ownership, and organization semantics are separate product components rather
than one conditional navigation tree.

## 5. Backend APIs

Added or wired backend capabilities:

| Area | Implementation | Scope |
| --- | --- | --- |
| Platform metrics | Existing `/v1/platform/metrics` retained behind explicit platform authorization | Aggregate, read-only |
| Platform organizations | `PlatformConsoleProjection` plus `/v1/platform/organizations` | Bounded metadata/counts/activity, max 100 results |
| Platform organization detail | `/v1/platform/organizations/{id}` | Safe organization/application/environment metadata and counts |
| Platform audit | `/v1/platform/audit` | Explicit platform-audience events only |
| Customer members | `GET /v1/organizations/{id}/members` | Safe customer-audience member metadata; platform memberships excluded |
| Customer credentials | `GET .../credentials`, existing issue/revoke contracts | Metadata/list/revoke UI foundation; no plaintext persistence |

`CredentialRecord.toMetadataJson()` excludes `tokenHash`; issuance responses
retain one-time plaintext behavior only at the existing API boundary.

No customer application/environment CRUD API was invented. The existing
overview remains the customer read model, while create/update/archive and
browser delivery actions remain CLI/API backlog until their authorization,
validation, and audit contracts are complete.

## 6. Authorization

The control plane now carries an explicit audience:

```text
customer
platform
```

Platform routes require the platform audience and one of the bounded platform
capabilities. Current platform eligibility also preserves the existing
configured platform-admin identity, owner membership, and `super-admin`
compatibility guard. Customer routes default to the customer audience, so a
platform token is not accepted by tenant routes merely because the account is
the same human.

The implemented platform capabilities are:

```text
platform:overview
platform:organizations:read
platform:organizations:inspect
platform:audit:read
platform:operations:read
```

The current Operations view is metrics-backed and therefore uses the existing
`platform:overview` projection/capability. This avoids claiming a separate
operations API before one exists.

Frontend route guards choose a usable shell/profile and provide a fallback;
server-side audience, capability, membership, scope, and tenant checks remain
authoritative.

## 7. Customer MVP coverage

| Capability | Current state | Assessment |
| --- | --- | --- |
| Organization context/switching | Customer profiles only | Implemented |
| Applications | Tenant-scoped read model | Implemented read-only; CRUD backlog |
| Environments | Tenant-scoped read model | Implemented read-only; CRUD backlog |
| Releases/patches | Existing tenant-scoped records | Implemented read-only; CLI/API writes |
| Deployments | Existing rollout records | Implemented read-only; browser action backlog |
| Customer audit | Redacted organization projection | Implemented read-only |
| Credentials | Safe metadata list and revoke action | Implemented foundation |
| Members | Safe member metadata list | Implemented foundation; invitation/role UX backlog |
| Settings | Customer context/member/credential panels | Implemented foundation |

The customer surface remains honest about CLI/API-required actions and does
not add non-functional CRUD controls.

## 8. Platform MVP coverage

| Capability | Current state | Assessment |
| --- | --- | --- |
| Platform Overview | Existing metrics projection in separate shell | Implemented |
| Organizations Directory | Bounded platform list projection | Implemented |
| Organization Detail | Bounded read-focused projection | Implemented |
| Cross-tenant inspection | Explicit platform API, no customer impersonation | Implemented read foundation |
| Platform audit | Separate platform-audience event projection | Implemented read foundation |
| Operations | Metrics-backed read view | Implemented bounded view |
| Platform settings | Operator metadata/capability view | Implemented read-only foundation |
| Accounts/roles, plans, incidents, support sessions | No safe bounded contract yet | Backlog |

## 9. Tests and validation

Focused coverage added or updated for:

- ordinary customer denial of platform metrics, organization projections,
  organization detail, and platform audit;
- rejection of platform-audience tokens on customer overview/member routes;
- bounded platform proxy query forwarding and rejection of unknown query
  parameters;
- local customer/platform route fallback and platform-host route handling;
- explicit customer/platform shell markup and route contract;
- safe credential/member projections and token-hash exclusion.

The consolidated validation scope is:

```text
python3 -m unittest dashboard.test_serve
node --check dashboard/app.js
node --check dashboard/test_auth_flow.js
dart format <task-owned control-plane Dart files>
dart analyze packages/control_plane
dart test packages/control_plane/test/human_auth_test.dart \
  packages/control_plane/test/platform_metrics_http_test.dart \
  packages/control_plane/test/demo_seed_test.dart
git diff --check
```

Browser visual capture was not available in this pass; static route serving,
markup contracts, JavaScript syntax, and the existing supplied screenshots
provide the available visual evidence. No production deployment or DNS
validation was performed. The full control-plane suite was also run because
authorization is shared infrastructure: the focused separation tests passed;
the suite reported 16 unrelated pre-existing reconciliation/P3E applicability
failures and skipped 34 PostgreSQL/S3/process-environment cases. Those
failures were not changed in this milestone.

## 10. Visual evidence

The supplied dashboard screenshots show the prior mixed shell: a customer
organization card/context model alongside platform concepts. The implemented
source now separates those surfaces with independent sidebars and context bars
while retaining the established Hyfens brand tokens, typography, spacing,
border, and motion work. No visual brand redesign was introduced as part of
this architecture milestone.

The local static server has route evidence for:

```text
customer: /, /applications, /settings
platform: /platform, /platform/organizations,
          /platform/organizations/{id}, /platform/audit,
          /platform/operations, /platform/settings
platform host: platform.hyfens.com equivalent routes
```

## 11. Remaining backlog

The following are deliberately not part of this bounded implementation:

- application/environment CRUD and identity lifecycle design;
- browser release/patch/deploy/rollback actions;
- member invitation, role mutation, and deactivation;
- browser credential issuance form;
- full platform staff/account/role administration;
- plans/entitlements, incidents, infrastructure/provider state, and advanced
  platform audit feeds;
- explicit time-limited support sessions and MFA/network hardening;
- DNS and production deployment of `app.hyfens.com` and `platform.hyfens.com`.

These are follow-up product work, not defects in the shell-separation
boundary.

## 12. Acceptance matrix

| Gate | Required | Result |
| --- | --- | --- |
| Customer shell separated | PASS | PASS |
| Platform shell separated | PASS | PASS |
| Shared auth retained | PASS | PASS |
| Shared API transport retained | PASS | PASS |
| Platform audience explicit | PASS | PASS |
| Customer tenant scope | PASS | PASS |
| Platform metrics moved | PASS | PASS |
| Platform Organizations Directory | PASS | PASS |
| Platform Organization Detail | PASS | PASS |
| Customer organization context | PASS | PASS |
| Customer Applications | PASS | PASS (read-only foundation) |
| Customer Environments | PASS | PASS (read-only foundation) |
| Customer Releases/Patches | PASS | PASS (read-only foundation) |
| Customer Deployments | PASS | PASS (read-only foundation) |
| Customer Audit | PASS | PASS |
| Customer credentials | PASS | PASS (metadata/revoke foundation) |
| Customer member foundation | PASS | PASS |
| Settings separated | PASS | PASS (foundations) |
| Customer → platform denial | PASS | PASS |
| Cross-tenant denial | PASS | PASS |
| Browser build/runtime | PASS | PASS (static runtime/syntax evidence; no browser capture) |
| Brand consistency | PASS | PASS |

## 13. Final disposition

`HYFENS DASHBOARD SEPARATION — IMPLEMENTED WITH BACKLOG`

The customer and platform contexts are now genuinely separate shells and
route/audience models over shared infrastructure. The remaining items are
bounded capability backlog, not reasons to merge the shells or weaken the
authorization boundary.
