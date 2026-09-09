# Task 259 — Cloud launch operations and policy gates

Status: [-] Blocked — launch verdict `NOT_READY`

## Goal

Close the production operational, policy, and account-lifecycle gates that
must be explicit before public Cloud launch.

## Scope and Non-goals

Scope:

- decide whether account verification, password recovery, and transactional
  security emails are required;
- configure and verify only the required production email/provider paths;
- publish the CMS-managed Terms, Privacy, and Refund Policy routes on the live
  marketing surface;
- verify TLS, DNS, object storage, database, monitoring, backups, and provider
  readiness for the advertised Cloud journey; and
- record launch-owner evidence for each dependency without storing secrets.

Non-goals:

- creating a general email platform;
- changing legal policy text without legal/maintainer review;
- adding compliance certifications or SLA claims; and
- changing Cloud plans or pricing.

## Owner

Codex

## Dependencies

- Tasks 255–258.
- Existing policy CMS and deployment wrappers.
- Maintainer/legal decision on required customer communications.

## Assumptions

- Policy content is CMS-managed and auditable in the repository, but the live
  public edge currently does not expose every current policy route.
- Provider, email, and production infrastructure credentials remain external
  deployment secrets.

## Work Items

- [x] Decide and document account verification, recovery, and security-email
  requirements.
- [x] Verify live Terms, Privacy, and Refund Policy links from the relevant
  marketing and payment surfaces.
- [x] Run provider/database/object-store/TLS/backup/monitoring readiness
  checks without exposing secrets.
- [-] Document ownership, rollback, and incident contacts for launch; named
  operational owners and protected deployment access remain external.
- [x] Add only focused operational checks or policy-link tests required by the
  decisions.

## Validation

Completed:

- live HTTPS route and policy smoke checks;
- deployment/provider readiness checklist;
- focused policy/CMS authorization and audit tests; and
- a signed launch-evidence review.

Validation evidence:

- private Cloud web `npm run typecheck`, `npm run lint`, and `npm run build`:
  passed;
- control-plane dart analyze: passed;
- focused control-plane tests for billing-provider bridge, customer billing,
  Enterprise billing, refunds, deletion, configuration, and content policy:
  all passed;
- public control-plane Compose interpolation with non-secret placeholders:
  passed;
- private-web production static output provider-secret scan: passed;
- root and private-web git diff checks: passed;
- the repository-wide Dart format check reports one pre-existing staged
  packages/control_plane/lib/src/platform_metrics.dart file outside this
  task; Task 259 changed no Dart source;
- control-plane focused auth/onboarding/billing/refund/deletion/Enterprise
  tests and analyzer: passed in the Task 267–270 evidence set;
- live HTTPS checks from 2026-09-09: `/terms` 200, `/privacy` 200,
  `/pricing` 200, `/refund-policy` 404, `/pricing.md` 404,
  `/account-deletion` 404, and `/api/billing/webhook` 405 to GET;
- live `/api/pricing`: 503 `pricing_unavailable`;
- `api.hyfens.com/healthz` and `/readyz`: 200;
- TLS certificate SAN covers `hyfens.com`, `www.hyfens.com`,
  `api.hyfens.com`, `app.hyfens.com`, and `platform.hyfens.com`, with the
  observed certificate expiring 2026-12-02;
- private-web deployment attempt through the installed root wrapper stopped
  at image build and did not replace the running container;
- no Razorpay provider mutation, payment, webhook replay, deletion, restore,
  or production customer-workspace cutover was performed.

## Next Action

Install the current private-web and Cloud control-plane builds through the
matching root-managed wrappers, configure the protected TEST provider/email
values, assign operational owners, publish legally approved policy records,
and then rerun the managed acceptance matrix. Task 256B remains separately
authorized.

## Blockers

Current blockers:

- the host has deployment drift: the installed platform wrapper targets the
  older `apps/web` layout and the running control plane is `hyfens-p2-r2`, not
  the current Cloud billing composition;
- protected env files are `root:root` mode `0600` and cannot be inspected or
  installed through this session's available fixed deployment path;
- running web billing settings have empty Razorpay key/secret, webhook,
  public-currency, and bridge values; the running control plane has no Cloud
  billing/provider settings;
- no production implementation is wired for the control plane's injected
  verification, recovery, or deletion message-delivery interfaces; SMTP
  variable names on the old web container are not mailbox evidence;
- no managed Enterprise notification/monitoring acceptance exists;
- live `/refund-policy`, `/pricing.md`, and pricing API are not available;
- final Terms/Privacy content is explicitly draft and requires legal review;
- live backup frequency, encryption, off-host retention, restore ownership,
  RPO/RTO, and deletion-tombstone recovery are not evidenced;
- named incident owners for payment, email, deletion/object cleanup,
  Enterprise inquiries, and backup/restore are not recorded.

## Outcome

`NOT_READY`. Code-level lifecycle work is available and the live host has
healthy HTTPS/TLS/control-plane liveness, but the managed Cloud composition is
not operationally configured or acceptance-tested. The failed private-web
build did not alter the live image. No live payment, provider webhook,
customer deletion, refund, Enterprise payment, or production customer-
workspace cutover was claimed.

## Policy decisions and retention boundary

- Managed Cloud deletion launch default: seven days via the protected
  `HYFENS_DELETION_GRACE_PERIOD=7d` setting. The current Compose template now
  forwards this existing setting; it remains unset for default self-hosted
  development. Customer-facing wording still requires legal/privacy approval.
- Cancellation and downgrade retain paid access/data through the paid-cycle
  boundary and create no ordinary refund. Refunds remain a separate reviewed
  workflow.
- Profiles, credentials, sessions, memberships, applications, environments,
  usage events, and customer operational content are staged for erase;
  tokens/artifact bytes/backups are temporary-retain; security/release
  metadata is anonymized; audit, billing/refund, Enterprise-commercial, and
  security/abuse evidence is retained in minimized form.
- Financial, security/audit, Enterprise-commercial, and backup durations are
  still `LEGAL_POLICY_REQUIRED`; no unsupported duration was invented.
- The repository's AWS disposable template documents seven-day RDS/AWS
  Backup retention, 30-day noncurrent S3 versions, and three-day incomplete
  multipart cleanup. These are not live-production evidence. The checked host
  exposed only the OS package backup timer.

## Email and Enterprise operations

The control plane has secure token/delivery interfaces and test fakes, but its
shipped executable injects no production transport. Signup verification,
recovery, deletion verification, and Enterprise notification therefore remain
unverified. The durable `enterprise_inquiries` inbox and operator workspace
exist; no notification destination or owner is proven.

## Razorpay TEST deployment

Task 263 provider evidence remains: the TEST USD Starter/Team plans were
created and validated at 4900/19900 minor units. This task found no protected
deployment of those plans. The running private web reports empty provider and
bridge values, and the running control plane reports no Cloud billing
configuration. No real checkout, signed webhook, refund, scheduled downgrade,
or Enterprise TEST payment was performed.

## Live policy and route evidence

The canonical HTTPS checks currently return:

| Route | Status | Finding |
| --- | ---: | --- |
| `/terms` | 200 | Draft/legal-review content |
| `/privacy` | 200 | Draft/legal-review content |
| `/refund-policy` | 404 | Missing on active deployment |
| `/pricing` | 200 | Active content is not the current local catalog evidence |
| `/pricing.md` | 404 | Missing on active deployment |
| `/api/pricing` | 503 | `pricing_unavailable` |
| `/account-deletion` | 404 | Current deletion page not deployed |

The current private-web build contains the missing routes, but the installed
host wrapper expects a different older source layout and its attempted build
failed before replacement. The local refund fallback is marked `draft` so an
unapproved generic page is not represented as final policy.

## Managed acceptance matrix

| Workflow | Code verified | Managed verified | Provider verified | Production operational |
| --- | --- | --- | --- | --- |
| Signup verification | Yes, injected delivery tests | No | N/A | No |
| Password recovery | Yes, injected delivery tests | No | N/A | No |
| No-login deletion | Yes, token/security tests | No | N/A | No |
| Free → Starter | Yes, state/provider-contract tests | No | TEST plans only | No |
| Starter → Team | Yes, state/provider-contract tests | No | TEST plans only | No |
| Team → Starter schedule | Yes, scheduling tests | No | No real schedule | No |
| Cancellation | Yes, state/provider-contract tests | No | No real cancellation | No |
| Refund | Yes, reviewed-workflow tests | No | No real refund | No |
| Enterprise quote/payment | Yes, domain/provider-contract tests | No | No real payment | No |
| Account deletion | Yes, staged-worker tests | No | N/A | No |
| Organization deletion | Yes, staged/object-safety tests | No | N/A | No |
| Policy routes | Local current source | No; 404s above | N/A | No |
| Backup retention | Local/templated evidence | No | N/A | No |

## Task 256B recommendation

`DO_NOT_CUT_OVER`. Customer-workspace production cutover is not justified
until protected Cloud deployment, transactional email, approved policy
publication, backup/restore ownership, and managed disposable acceptance are
complete.

## References

- `hyfens-cloud-web/site/src/components/site-footer.tsx`
- `hyfens-cloud-web/site/src/app/(marketing)/terms/page.tsx`
- `hyfens-cloud-web/site/src/app/(marketing)/privacy/page.tsx`
- `hyfens-cloud-web/site/src/app/(marketing)/refund-policy/page.tsx`
- `hyfens-cloud-web/site/src/lib/public-content.ts`
- `hyfens-cloud-web/deploy/web/README.md`
- `tasks/254-cloud-commercial-launch-readiness-audit.md`

## History

- 2026-09-09: Consolidated final validation passed for the affected web,
  control-plane, Compose, bundle-scan, and diff-check surfaces; no protected
  deployment or managed acceptance was claimed.
- 2026-09-07: Created from the Task 254 P1/P2 policy and production-operations
  findings.
- 2026-09-09: Completed the live/deployment/policy/retention audit, selected
  the managed seven-day deletion default, wired the setting through the
  managed development Compose template, and recorded `NOT_READY` evidence.
