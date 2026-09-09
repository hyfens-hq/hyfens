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
- post-deployment live HTTPS checks from 2026-09-09: `/`, `/pricing`,
  `/pricing.md`, `/terms`, `/privacy`, `/refund-policy`,
  `/account-deletion`, and `/api/pricing` all returned 200; the webhook GET
  returned the expected 405 and an unsigned webhook POST returned 401;
- `api.hyfens.com/healthz` and `/readyz`: 200;
- TLS certificate SAN covers `hyfens.com`, `www.hyfens.com`,
  `api.hyfens.com`, `app.hyfens.com`, and `platform.hyfens.com`, with the
  observed certificate expiring 2026-12-02;
- corrected root-installed deployment wrapper built and restarted the current
  Cloud web composition successfully;
- root-managed protected environments retain `root:root` and mode `0600`,
  with status-only validation of TEST provider/bridge configuration;
- real TEST browser/provider checkout, signed webhook activation, scheduled
  plan change, cycle-end cancellation, and reviewed partial refund were
  performed; no live payment, deletion, restore, or production
  customer-workspace cutover was performed.

## Next Action

Complete the remaining managed acceptance and operations gates: recovery and
deletion email, Enterprise TEST payment, deletion-worker execution,
backup/restore and deletion-tombstone recovery, rollback rehearsal, and
role-based operational ownership. Resolve tax and evidence-retention policy
with the appropriate legal/accounting owner. Task 256B remains separately
authorized.

## Blockers

Current blockers:

- full managed transactional-email acceptance is incomplete: signup
  verification has been delivered, but recovery, no-login deletion, and
  Enterprise inquiry notification still need mailbox evidence;
- no managed Enterprise quote/payment acceptance has been executed;
- the deletion worker, authenticated/no-login account deletion, and
  organization deletion have not completed managed acceptance;
- live backup schedule, off-host durability, restore rehearsal, and
  deletion-tombstone resurrection protection are not evidenced;
- rollback rehearsal and role-based owners for email, payments/webhooks,
  refunds, Enterprise inquiries, deletion/object cleanup, and backup/restore
  are not recorded;
- tax treatment and legally approved financial, security/audit, and Enterprise
  commercial evidence-retention durations remain unresolved;
- `app.hyfens.com` customer-workspace cutover remains separately unauthorized.

## Outcome

Initial audit outcome: `NOT_READY`. Code-level lifecycle work was available
while the live host still had healthy HTTPS/TLS/control-plane liveness but an
unconfigured managed Cloud composition. The failed private-web build did not
alter the live image; the subsequent root-authorized deployment and managed
acceptance evidence are recorded below.

Post-deployment managed acceptance update (2026-09-09): root-authorized
wrappers and protected TEST configuration are installed; the current web and
control-plane builds are healthy; the required live policy/customer routes
return 200; TEST Free → Starter and Starter → Team browser/provider flows,
Team → Starter scheduling/Keep Team cancellation, cycle-end cancellation, and
a reviewed partial refund completed with real Razorpay TEST evidence. The
launch verdict remains `NOT_READY` because the blockers above are still
unproven.

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

The deployed composition has the Keplars transport configured and signup
verification has been delivered to a disposable managed customer. Recovery,
no-login deletion verification, and Enterprise inquiry notification still lack
complete mailbox acceptance. The durable `enterprise_inquiries` inbox and
operator workspace exist; notification ownership is not yet recorded.

## Razorpay TEST deployment

Task 263 provider evidence remains: the TEST USD Starter/Team plans were
created and validated at 4900/19900 minor units. Root-authorized protected
deployment now supplies the TEST credentials, plan configuration, webhook
secret, and provider bridge. Real TEST Free → Starter, Starter → Team,
Team → Starter scheduling/Keep Team cancellation, cycle-end cancellation, and
reviewed partial-refund evidence completed. Enterprise TEST payment remains
unexecuted.

## Live policy and route evidence

The canonical HTTPS checks currently return:

| Route | Status | Finding |
| --- | ---: | --- |
| `/terms` | 200 | Current deployed route; legal approval remains a separate gate |
| `/privacy` | 200 | Current deployed route; legal approval remains a separate gate |
| `/refund-policy` | 200 | Current deployed route |
| `/pricing` | 200 | USD catalog deployed |
| `/pricing.md` | 200 | Current deployed route |
| `/api/pricing` | 200 | Current catalog response |
| `/account-deletion` | 200 | Current deployed route |

The corrected root-installed wrapper now builds the current `site/` source
layout. `api.hyfens.com/healthz` and `/readyz` return 200; the POST-only
webhook route returns the expected 405 to GET and 401 to an unsigned POST.
The deployed policy pages still require legal/maintainer review for final
wording; no live payment activation was performed.

## Managed acceptance matrix

| Workflow | Code verified | Managed verified | Provider verified | Production operational |
| --- | --- | --- | --- | --- |
| Signup verification | Yes, injected delivery tests | Partial; delivered | N/A | Partial |
| Password recovery | Yes, injected delivery tests | No | N/A | No |
| No-login deletion | Yes, token/security tests | No | N/A | No |
| Free → Starter | Yes, state/provider-contract tests | Yes | Yes, TEST checkout/webhook | No LIVE |
| Starter → Team | Yes, state/provider-contract tests | Yes | Yes, TEST provider confirmation | No LIVE |
| Team → Starter schedule | Yes, scheduling tests | Yes | Yes, TEST schedule/cancel | No LIVE |
| Cancellation | Yes, state/provider-contract tests | Yes | Yes, TEST cycle-end schedule | No LIVE |
| Refund | Yes, reviewed-workflow tests | Yes | Yes, TEST partial refund | No LIVE |
| Enterprise quote/payment | Yes, domain/provider-contract tests | No | No real payment | No |
| Account deletion | Yes, staged-worker tests | No | N/A | No |
| Organization deletion | Yes, staged/object-safety tests | No | N/A | No |
| Policy routes | Local current source | Yes; required routes 200 | N/A | Legal approval pending |
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
- 2026-09-09: Root-authorized deployment recovery completed. Corrected wrappers,
  protected TEST configuration, the current web/control-plane composition,
  live policy routes, and the billing provider bridge are operational. Real
  TEST billing, scheduled-change, cancellation, and reviewed-refund evidence
  was appended; Enterprise, deletion, backup/restore, rollback, full email,
  ownership, tax, and evidence-retention gates remain open. Verdict remains
  `NOT_READY`; `app.hyfens.com` was not changed.
