# Historical OSS exposure audit

Status: AUTHORITATIVE — completed 2026-09-04

Decision: `KEEP_HISTORY`

This record audits the period before the public OSS/Cloud web-product split.
It does not retroactively change the Apache-2.0 license, existing clones,
forks, downloaded archives, container pulls, or third-party caches.

## Executive summary

The public repository briefly contained a combined static dashboard. The
Customer/Instance Workspace and the global Platform Console were present in
the same dashboard files from `4da57c8` (`feat(dashboard): complete workspace
and platform MVP`) through the tree at `78ae59f` (`docs(acceptance): record
live auth bootstrap gate`). The first customer-only OSS dashboard commit was
`a721f3f` (`refactor(web): isolate self-host customer workspace`).

The exposure was reachable through public `main` history, but it did not enter
the signed `v0.1.0` or `v0.1.1` release trees. Both release tags predate the
exposure, their GitHub source archives are reachable and clean, and their
uploaded release assets are CLI archives/checksums only. The release-image
workflow also ran only for those two pre-exposure tags.

No high-confidence private key, provider token, cloud credential, database
credential, session secret, or customer-data finding was identified across all
25 reachable commits. A deterministic demo seed contains one non-placeholder
project-owner/company identity; it is not associated with a password, token,
customer record, or private support content.

The current OSS tip and future OSS dashboard artifact are customer-only, and
the private Cloud repository owns the Platform Console. A history rewrite is
therefore not justified by a secret/PII incident and is not worth breaking the
signed history and release provenance for this short-lived, already-replaced
implementation. No force-push, tag mutation, release deletion, or image
deletion is authorized or performed by this audit.

## Current topology

```text
PUBLIC  hyfens-hq/hyfens
  CLI, MCP, runtime/compiler, control plane
  Customer/Instance Workspace
  self-host deployment

PRIVATE  hyfens-cloud-web
  Cloud composition and billing
  Platform Console at platform.hyfens.com
  global commercial/support/staff/operations surfaces
```

The pre-audit public `main` tip was `285275a`. Its `dashboard/` build contains
the customer shell, customer routes, auth/discovery/device surfaces, and the
reviewed customer proxy allow-list. It does not contain Platform Console
renderers or platform navigation. The control plane still retains bounded
`/v1/platform/...` projections as public/shared API contracts; that is a
separate backend-ownership decision and is not evidence that the OSS image
ships the Platform Console.

The private Cloud repository is `hyfens-hq/hyfens-cloud-web`, is private, and
has the baseline commit `6b8794b` followed by the Platform Console boundary
commit `04d09da`.

## Product/route exposure matrix

| Route or feature | Historical public location | Audience | Needed for OSS self-host? | Correct current product |
| --- | --- | --- | --- | --- |
| Overview / organization context | `dashboard/app.js` | Customer | Yes | OSS Customer/Instance Workspace |
| Organizations membership context | `dashboard/app.js` | Customer memberships only | Yes | OSS Customer/Instance Workspace |
| Applications | `dashboard/app.js` | Customer tenant | Yes | OSS customer core; Cloud consumes contract |
| Environments | `dashboard/app.js` | Customer tenant | Yes | OSS customer core; Cloud consumes contract |
| Releases | `dashboard/app.js` | Customer tenant | Yes | OSS customer core; CLI remains source-dependent |
| Patches | `dashboard/app.js` | Customer tenant | Yes | OSS customer core; CLI remains source-dependent |
| Artifacts | `dashboard/app.js` | Customer tenant | Yes | OSS customer core |
| Deployments / promotion | `dashboard/app.js` | Customer tenant | Yes | OSS customer core |
| Members / invitations | `dashboard/app.js` | Customer organization | Yes | OSS customer core |
| Credentials | `dashboard/app.js` | Customer organization | Yes | OSS customer core |
| Customer support contract | `dashboard/app.js` and control plane | Customer organization | Optional but supported | OSS contract; Cloud backoffice extension |
| Customer audit | `dashboard/app.js` | Customer tenant | Yes | OSS customer core |
| Customer settings | `dashboard/app.js` | Customer organization | Yes | OSS customer core |
| Platform Overview | Mixed `dashboard/app.js` | Hyfens staff | No | Private Cloud Platform Console |
| Platform Organizations / Detail | Mixed `dashboard/app.js` | Hyfens staff | No | Private Cloud Platform Console |
| Commercial / revenue | Mixed `dashboard/app.js` | Commercial-authorized staff | No | Private Cloud Platform Console |
| Global Support Queue / internal notes | Mixed `dashboard/app.js` | Support-authorized staff | No | Private Cloud Platform Console |
| Platform Staff | Mixed `dashboard/app.js` | Staff administrators | No | Private Cloud Platform Console |
| Plans / Entitlements | Mixed `dashboard/app.js` | Commercial/platform staff | No | Private Cloud Platform Console |
| Managed Operations | Mixed `dashboard/app.js` | Operations staff | No | Private Cloud Platform Console |
| Platform Audit / Settings | Mixed `dashboard/app.js` | Authorized staff | No | Private Cloud Platform Console |

## Historical path inventory

The platform UI was historically mixed into files that also contained the
legitimate OSS customer workspace. Path deletion alone would have removed
customer history, so the source split used a new clean customer-only tip.

| Historical path or group | First commit | Last tree containing Cloud material | Current status | Classification |
| --- | --- | --- | --- | --- |
| `dashboard/app.js` | `3b3a2e3` | `78ae59f` | Customer-only after `a721f3f` | `MIXED` |
| `dashboard/index.html` | `3b3a2e3` | `78ae59f` | Customer-only after `a721f3f` | `MIXED` |
| `dashboard/styles.css` | `3b3a2e3` | `78ae59f` | Customer-only after `a721f3f` | `MIXED` |
| `dashboard/serve.py`, `auth-flow.js`, dashboard tests | `3b3a2e3` | `78ae59f` | Customer proxy/auth tests retained | `MIXED` |
| `dashboard/Dockerfile` and image workflow | `3b3a2e3` | `78ae59f` | Current image copies customer files only | `MIXED_BUILD_INPUT` |
| `packages/control_plane/lib/src/platform_console.dart` | `4da57c8` | Current `main` | Bounded platform projection retained in public control plane | `SHARED_CONTRACT` with Cloud-only implementation history |
| `packages/control_plane/lib/src/platform_metrics.dart` | `4da57c8` | Current `main` | Bounded platform projection retained in public control plane | `SHARED_CONTRACT` with Cloud-only implementation history |
| `packages/control_plane/lib/src/platform_commercial.dart` | `226671c` | Current `main` | Commercial projection remains a separate backend follow-up | `CLOUD_PROPRIETARY_SOURCE` / public contract follow-up |
| `packages/control_plane/lib/src/support.dart` | `226671c` | Current `main` | Customer contract and platform support service are still split by API | `MIXED` |
| `http.dart`, `human_auth.dart`, `service.dart`, `domain.dart`, persistence/store wiring | `4da57c8` changes | Current `main` | Shared auth/customer wiring plus bounded platform routes | `MIXED` / `SHARED_CONTRACT` |
| platform metrics/commercial/support tests | `4da57c8` / `226671c` | Current `main` | Test coverage for retained API contracts | `CLOUD_PROPRIETARY_SOURCE` history; not frontend artifact |
| current/product boundary docs and milestone reviews | `4da57c8` | Current `main` or `docs/history/` | Current truth is separated; reviews are historical | `HISTORICAL_DOC_ONLY` |

The first platform UI commit was `4da57c8`. The last public tree containing
the UI was `78ae59f`; `a721f3f` removed the platform navigation, renderers,
platform API calls, and platform route handling from the OSS dashboard
artifact. The platform backend files were not removed because the migration
explicitly preserved their bounded public/shared API contracts.

## Release and package-surface audit

### Git tags and GitHub Releases

| Surface | Result |
| --- | --- |
| `v0.1.0` | Annotated, signed tag at `4982ab5`; no platform paths or platform markers |
| `v0.1.1` | Annotated, signed tag at `389fc7178b857aeaf9167e69aa5c98b8167c7a43`; no platform paths or platform markers |
| GitHub source archives | HTTP 200 for both tags; generated from the same clean tag trees |
| GitHub release assets | CLI archives for six OS/architecture combinations, checksums, and inventory; no dashboard source upload |
| release-image runs | Successful runs used exactly `4982ab5` and `389fc717`; both predate the Platform Console commit |

The signed release tags are immutable historical provenance. They do not need
rewriting because they do not contain the exposed Platform Console.

### GHCR

Anonymous `docker manifest inspect` requests for
`ghcr.io/hyfens-hq/hyfens-dashboard:0.1.0`, `0.1.1`, `latest`, and `main`
returned HTTP authorization failures. The authenticated GitHub CLI also lacks
the `read:packages` scope, so historical image layers cannot be independently
inspected from this environment. This is an external verification gate, not
evidence that a layer contains Cloud code.

The release workflow is tag-triggered, and the only successful public image
release runs correspond to the two clean pre-exposure tags. The current OSS
Dockerfile copies only customer dashboard files. Future image publication must
continue to use the post-split tree; no historical image is deleted by this
audit.

Homebrew, Scoop, and WinGet templates are CLI-only and contain no dashboard or
Platform Console source. They are not affected by this exposure.

## Security and privacy scan

All 25 commits reachable from the public mirror were scanned using Git tree
searches and path inspection. Results:

| Class | Result |
| --- | --- |
| A — secret / credential | No high-confidence private keys, AWS/R2 keys, provider tokens, JWT signing keys, database credentials, SSH keys, or session secrets found |
| B — private customer / PII | No confirmed customer records, private support content, phone numbers, or customer credentials found |
| C — Cloud proprietary source | Historical mixed Platform Console frontend and platform service/projection source was public for the exposure window |
| D — obsolete OSS source | The pre-split combined dashboard is reachable in historical commits and is now superseded |
| E — non-sensitive history | Release metadata, deterministic demo fixtures, architecture reviews, and signed authorship metadata |

The tracked environment file is `.env.example` only and contains replacement
placeholders. No secret-like file path other than the CSS token file was found.
Existing clones, forks, GitHub caches, and previously pulled images remain
outside canonical-repository control.

## Rewrite feasibility and decision

The mirror has one branch (`main`), two release tags, no public forks, no open
or closed pull requests, 25 commits, and one commit author identity. This makes
coordination smaller than it would be for a mature project. However, every
reachable commit reports a verified signature status, both release tags are
signed annotated tags, and current docs/tasks contain references to historical
commit IDs.

Surgical rewriting is also not a safe path to a clean customer history: the
platform UI was mixed into the same dashboard blobs as customer code, while
platform backend wiring spans shared HTTP/auth/service files. A rewrite would
require reconstructing historical trees, invalidate post-release commit
signatures and links, require a coordinated force-push, and still could not
remove Apache-2.0 rights or existing copies. There is no A/B incident that
overrides that provenance cost.

Therefore:

```text
KEEP_HISTORY
```

The canonical current tip and future OSS image are sanitized by the existing
source split. Historical combined commits remain clearly superseded, release
provenance remains intact, and no destructive Git or registry operation is
performed. A future request to remove class-C source from non-release history
must be a separate maintainer-approved force-push plan with a fresh mirror,
filter-repo rehearsal, signature/reference impact review, and GitHub cache
remediation plan.

## Migration inventory

| Module | Current public/private state | Target classification | Action |
| --- | --- | --- | --- |
| Customer shell and customer routes | Public `dashboard/` | `KEEP_IN_OSS` | Retain and test as Customer/Instance Workspace |
| Applications, environments, delivery, members, credentials, audit | Public control-plane contract and OSS UI | `KEEP_IN_OSS` / `SHARE` | Cloud consumes compatible contracts; do not copy the lifecycle wholesale |
| Auth, discovery, PKCE/device approval, structured errors | Public shared contract | `SHARE` | Keep protocol/security contract public |
| Platform shell/navigation/renderers | Private Cloud commit `04d09da`; historical public OSS blobs | `MOVE_TO_CLOUD_WEB` | Keep out of future OSS artifact |
| Commercial, global support, internal notes, staff, managed operations, platform audit UI | Private Cloud | `MOVE_TO_CLOUD_WEB` | Keep Cloud-only |
| Platform projections and platform authorization protocol | Public control plane | `SHARED_CONTRACT` / backend follow-up | Do not remove without a separate API migration |
| `hyfens-dashboard` image | Public compatibility name | `KEEP_IN_OSS` | Define and publish it as Customer/Instance Workspace only |
| Cloud marketing/CMS/billing | Private Cloud | `KEEP_CLOUD` | Preserve existing Cloud ownership |
| Historical reviews/tasks | Public history | `KEEP_REFERENCE` | Keep under historical navigation; never treat as current contract |

## Current isolated patch disposition

The uncommitted isolated patch worktree was not modified during this audit.
Its customer portions are already represented by the public `a721f3f` source
split, and its platform role/control styling and protected-owner semantics are
represented by the private Cloud Platform Console baseline `04d09da`. The
temporary `dart:stable` runtime Dockerfile replacement is discarded and must
not be revived. No wholesale patch application is required.

## Required follow-up boundaries

1. Keep the public OSS dashboard image physically customer-only.
2. Treat the retained `/v1/platform/...` backend projections as a separately
   reviewed public-contract or private-service decision; do not infer that
   frontend removal completed backend privatization.
3. Do not rewrite release tags or claim that historical Apache-2.0 source has
   been made private.
4. If GHCR public visibility is needed for self-hosting, inspect and correct
   package permissions separately; this audit does not add credentials or
   delete historical images.

## Final decision

```text
KEEP_HISTORY
```

The current product boundary is correct, the released CLI surfaces were not
affected by the frontend exposure window, no security purge is required, and
preserving signed release/history provenance is the safer bounded outcome.
