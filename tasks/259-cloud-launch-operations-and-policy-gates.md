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
- [-] Document ownership and incident contacts for launch; protected deploy
  access and rollback are now exercised, but named/role-based operational
  ownership remains external.
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
- current control-plane analyzer and focused onboarding, deletion, refund, and
  human-auth tests passed after the managed-worker/notifier changes;
- the complete control-plane test suite was run for PR validation; 27 failures
  remain in pre-existing reconciliation, credential-scope, observation, and
  auto-halt cases outside this task's changed files, while the affected
  focused tests pass;
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
- root rollback rehearsal completed through the installed web wrapper, and the
  current release was redeployed and returned to healthy status;
- the installed bounded deletion timer is enabled and active; its last manual
  service run exited successfully with zero due requests;
- a valid managed control-plane registration request returned the expected
  verification-required response, but the untouched `app.hyfens.com` legacy
  dashboard still renders a stale registration form and reports account
  creation unavailable. This prevents claiming current public onboarding
  acceptance without the separately authorized workspace cutover;
- the deployed Enterprise inquiry notifier uses the existing Keplars seam and
  the latest inquiry is durably recorded with notification status `sent`.
  Delivery to an owned mailbox is not yet proven because the configured
  recipients are not the owned acceptance mailbox.

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
  verification and recovery have been delivered; no-login deletion reached a
  verified request, but full recovery completion and Enterprise inquiry
  notification still need owned-mailbox evidence;
- no managed Enterprise quote/payment acceptance has been executed;
- the deletion worker, authenticated/no-login account deletion, and
  organization deletion have not completed managed acceptance;
- live backup schedule, off-host durability, restore rehearsal, and
  deletion-tombstone resurrection protection are not evidenced;
- role-based owners for email, payments/webhooks, refunds, Enterprise
  inquiries, deletion/object cleanup, and backup/restore are not recorded;
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

Operational follow-up (2026-09-09): the deletion worker/timer and Enterprise
inquiry notification retry/status wiring are deployed through the existing
composition. Focused validation passed, a rollback/current-release rehearsal
completed, and the live API returned a valid verification-required response
for a disposable registration probe. The old `app.hyfens.com` dashboard still
reports account creation unavailable and was intentionally not changed.

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

The deployed composition has the Keplars transport configured. Signup
verification and recovery messages have been delivered to the owned test
mailbox; a fresh no-login deletion verification message was delivered and its
single-use link reached the verified-request state. Full recovery completion,
final account/organization deletion, and Enterprise inquiry mailbox acceptance
remain open. The durable `enterprise_inquiries` inbox and operator workspace
exist, and notifier delivery is retried/idempotently recorded, but a verified
owned notification recipient is not yet configured.

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
| Signup verification | Yes, injected delivery tests | Yes; delivered | N/A | Partial; owned-mailbox flow not re-run after stale onboarding discovery |
| Password recovery | Yes, injected delivery tests | Partial; delivered, completion not run | N/A | No |
| No-login deletion | Yes, token/security tests | Partial; verified request reached | N/A | No; final deletion/email ownership incomplete |
| Free → Starter | Yes, state/provider-contract tests | Yes | Yes, TEST checkout/webhook | No LIVE |
| Starter → Team | Yes, state/provider-contract tests | Yes | Yes, TEST provider confirmation | No LIVE |
| Team → Starter schedule | Yes, scheduling tests | Yes | Yes, TEST schedule/cancel | No LIVE |
| Cancellation | Yes, state/provider-contract tests | Yes | Yes, TEST cycle-end schedule | No LIVE |
| Refund | Yes, reviewed-workflow tests | Yes | Yes, TEST partial refund | No LIVE |
| Enterprise quote/payment | Yes, domain/provider-contract tests | No | No real payment | No |
| Account deletion | Yes, staged-worker tests | Partial; verification/ownership gate | N/A | No |
| Organization deletion | Yes, staged/object-safety tests | No | N/A | No |
| Policy routes | Local current source | Yes; required routes 200 | N/A | Legal approval pending |
| Backup retention | Local/templated evidence | No | N/A | No |

## Task 256B recommendation

`DO_NOT_CUT_OVER`. Customer-workspace production cutover is not justified
until the stale onboarding surface is replaced through the separately
authorized cutover, mailbox ownership is operationally proven, Enterprise and
deletion acceptance completes, backup/restore evidence exists, and policy/tax
and retention decisions are approved.

## References

- `hyfens-cloud-web/site/src/components/site-footer.tsx`
- `hyfens-cloud-web/site/src/app/(marketing)/terms/page.tsx`
- `hyfens-cloud-web/site/src/app/(marketing)/privacy/page.tsx`
- `hyfens-cloud-web/site/src/app/(marketing)/refund-policy/page.tsx`
- `hyfens-cloud-web/site/src/lib/public-content.ts`
- `hyfens-cloud-web/deploy/web/README.md`
- `deploy/p2/hyfens-public-control-plane-dev-deletion-worker`
- `deploy/p2/hyfens-public-control-plane-dev-deletion.service`
- `deploy/p2/hyfens-public-control-plane-dev-deletion.timer`
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
- 2026-09-09: Installed the bounded deletion worker/timer and deployed the
  Enterprise inquiry notification retry/status wiring using the existing
  Keplars transport. Re-ran focused validation, completed a safe rollback and
  current-release redeploy, and verified live health/routes. The legacy
  untouched `app.hyfens.com` onboarding surface remains stale; backup/restore,
  Enterprise payment, deletion completion, mailbox ownership, role ownership,
  and legal/tax retention gates remain open. Verdict remains `NOT_READY`.

## Operations ownership registry correction — 2026-09-12

The control plane now includes a bounded managed-Cloud operational ownership
registry. The six current Task 259 operational concerns are initially owned by
`admin@hyfens.com`: `email_delivery`, `payments_webhooks`, `refunds`,
`enterprise_inquiries`, `deletion_object_cleanup`, and `backup_restore`.

Platform operators can list owners with `platform:operations:read`. Add,
update, and remove operations require the separate
`platform:operations:manage` capability, a platform-audience session, an
`Idempotency-Key`, and a non-empty reason. The registry is tenant-independent,
self-hosted-safe (the managed registry endpoint is Cloud-only), and retains
removed rows as history. Each mutation is recorded through the existing
immutable audit chain with actor, role, old/new mailbox, reason, request and
causation/idempotency references, revision, and timestamp. Replaying the same
idempotent mutation does not create a second change or audit event.

This closes the previously missing assignment/evidence mechanism, but it does
not claim that `admin@hyfens.com` is monitored, replace a runbook, or prove
backup/restore. Backup ownership still requires a real managed schedule,
off-host encrypted copy, isolated restore rehearsal, and deletion-tombstone
resurrection evidence. Tax treatment and legally approved financial,
security/audit, Enterprise-commercial, and backup retention decisions remain
open. Task 259 remains `NOT_READY` and Task 256B remains `DO_NOT_CUT_OVER`.

Research used for this boundary is recorded in
`docs/operations/managed-operations-research.md`. In particular, Keplars'
current webhook contract documents `email_id` and optional `reference_id`,
while AWS, Stripe, Postmark, Razorpay, and tax-authority sources reinforce
that provider telemetry, backup/recovery ownership, merchant tax/invoice
responsibility, and application-owned operational evidence remain distinct
responsibilities.

## Deletion lifecycle policy correction — 2026-09-10

Task 269 follow-up now records the approved managed-Cloud grace policy as
seven **working** days. The verification business date is day 1 when it is a
Monday-Friday date not listed in the explicit holiday configuration; day 5 and
day 7 reminders are persisted notification jobs; staged processing becomes
eligible at the start of day 8. The server persists `processingAt` and exposes
the same date to the UI and email. It is not derived from `7 * 24 hours`.

During grace, the existing control-plane authorization boundary rejects normal
tenant mutations and ordinary reads with deletion-pending errors while keeping
status, safe billing status, ownership resolution, privacy/policy, and
cancellation available. Cancellation and worker claiming use compare-and-set;
stale reminders are no-ops. Organization billing remains separate: deletion
stops future renewal through Task 270, creates no refund, and does not silently
reverse an irreversible provider cancellation.

The correction is locally code-verified. It does not close Task 259 managed
acceptance: real mailbox cadence, managed time-seam acceptance, final staged
deletion, backup/restore/tombstone rehearsal, operational ownership, and legal
holiday/backup/financial/security/Enterprise retention decisions remain
external gates. No statutory duration was invented.

The subsequent review correction also verified that pending personal deletion
cannot create a new Cloud organization, self-hosted deployments do not expose
Cloud deletion routes, organization credentials are revoked before staged
cleanup, failed requests remain retryable, and cancellation links are bound to
request generations. These are application-level closures only; they do not
advance the managed acceptance verdict or resolve the external backup, email,
tax, legal, and retention gates.

## Task 269 working-day correction validation — 2026-09-10

The approved deletion grace policy is seven working days, not seven elapsed
calendar days. The implementation persists the server-owned business-calendar
schedule, day-5/day-7 reminder milestones, and day-8 processing timestamp;
server authorization restricts pending accounts and organizations while the
request remains recoverable. Cancellation and worker claim use durable
compare-and-set state transitions, and provider billing cancellation is not
silently reversed.

The affected control-plane tests, analyzer, formatting check, Cloud web
typecheck/lint/build, and `git diff --check` passed. This is code-level
validation only. Task 259 remains `NOT_READY` for managed mailbox cadence,
managed deletion completion, backup/restore/tombstone evidence, operational
ownership, and unresolved legal/tax/evidence-retention decisions.

## Managed deletion and deployment follow-up — 2026-09-10

Root-authorized deployment is now operational for the current composition:

- the corrected control-plane wrapper built and deployed the current source
  layout; `/healthz` and `/readyz` remain 200;
- the corrected public-edge configuration was installed and the exact pricing
  upstream was repaired without changing the `app.hyfens.com` target;
- the protected environments remain root-owned with mode 0600, and status-only
  checks confirm the TEST Razorpay, billing bridge, Keplars, notification,
  SMTP, and `HYFENS_DELETION_GRACE_PERIOD=7d` settings are present;
- the deletion and notification timers are enabled and active, with successful
  manual runs and zero due work after the cancelled-request replay.

The live route smoke after deployment returned 200 for `/`, `/pricing`,
`/pricing.md`, `/terms`, `/privacy`, `/refund-policy`, `/account-deletion`,
and `/api/pricing`. The webhook endpoint returned the expected 405 to GET.
`api.hyfens.com/healthz` and `/readyz` returned 200. `app.hyfens.com` was not
cut over or otherwise intentionally modified.

### Managed deletion evidence

The working-day managed run used the explicit UTC Monday-Friday calendar with
no implicit holiday list. A disposable organization verified on 2026-09-10
persisted day 5 as 2026-09-16, day 7 as 2026-09-18, and day 8 processing as
2026-09-21. No database timestamps or host clock were edited.

Acceptance A completed the cancellation path: pending organization deletion
remained restricted and recoverable, day-5/day-7 notifications were each
generated once, password-confirmed cancellation restored normal local access,
and the current-image day-8 replay processed zero requests. It created no
refund and did not pretend an irreversible provider cancellation had been
reversed.

Acceptance B completed the managed organization-deletion path for a separate
disposable organization. The worker processed one due request and completed
it through the staged deletion/tombstone state; the notification worker then
processed the completion event. The owned mailbox contained one verification,
one immediate acknowledgement, one day-5 reminder, one day-7 reminder, and
one completion message. Provider notification records are `accepted`; mailbox
receipt is the delivery evidence, and no unverified provider callback delivery
state is claimed. The completed organization has the explicit deleted state
used as the Cloud tombstone and no refund record.

These runs do not close managed personal-account deletion after ownership
resolution, managed shared-object physical-retention acceptance, or backup
restore/tombstone reconciliation. The shared-object and retry invariants
remain code-tested. The current lifecycle email source and deployed image
contain the final reduced-brand-copy correction; one earlier captured
completion email predates that correction and is not used as visual evidence
for the corrected body.

### Current launch blockers

Task 259 remains `NOT_READY` because the managed host still has no proven
Hyfens database backup/off-host encrypted rotation or isolated restore
rehearsal, and deletion resurrection protection after restoring an old backup
has not been evidenced. Role-based operational ownership is not recorded.
Tax handling and legally approved financial, security/audit, Enterprise
commercial, and backup wording/retention decisions remain open. The live
policy pages require legal/maintainer approval, and `/api/pricing` currently
exposes the public free catalog as `developer` while the approved customer
language calls it `Free`; this naming/content discrepancy remains a policy
review item rather than an unapproved silent rewrite.

The managed acceptance matrix is therefore updated as follows: organization
deletion is partially managed-verified, account deletion remains partial,
backup retention remains unverified, and the deployed/test billing and route
evidence do not constitute LIVE or public-cutover approval. Task 256B remains
`DO_NOT_CUT_OVER`.

### Managed acceptance delta matrix

This append-only delta supersedes the older pre-deployment rows above without
rewriting their historical evidence:

| Workflow | Current managed state | Current operational state |
| --- | --- | --- |
| Organization deletion | Partial: cancellation and staged completion runs passed | No backup/resurrection proof; no public launch |
| Account deletion | Partial: no-login/ownership gates covered; final personal deletion not run | Email/cadence and ownership operations still incomplete |
| Deletion worker | Verified for bounded managed cancellation replay and completion | Timer active; retry/failure ownership not assigned |
| Deletion notifications | Mailbox receipt observed once for verification, acknowledgement, day 5, day 7, and completion | Provider delivery telemetry remains subject to the external Keplars correlation blocker |
| Backup/restore | Not verified | No proven managed backup, off-host rotation, isolated restore, or resurrection rehearsal |
| Policy/catalog | Routes deployed and reachable | Legal approval pending; public free-plan naming is `developer` in `/api/pricing` vs approved `Free` copy |
