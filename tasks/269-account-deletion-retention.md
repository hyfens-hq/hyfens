# Task 269 — Account deletion and retention lifecycle

Status: [-] Blocked — CODE_VERIFIED; managed acceptance and retention gates
remain unresolved

## Goal

Implement a verified, resumable Cloud account/organization deletion lifecycle
that is separate from subscription cancellation and preserves required
security, billing, and audit evidence.

## Scope and Non-goals

In scope:

- authenticated deletion request with strong confirmation;
- neutral no-login email initiation using a purpose-bound, hashed, single-use,
  expiring token;
- ownership-transfer/sole-owner handling;
- explicit account versus organization deletion scope;
- approved grace-period state, cancellation/reconciliation, resumable deletion
  job, and observable retryable failures;
- erase/anonymize/retain/temporary-retain classification for database,
  artifact, audit, billing, and backup records;
- shared content-addressed object safety and Self-hosted separation.

Out of scope:

- a general privacy/GDPR/DPDP management suite;
- universal export, tax, refunds, or legal drafting;
- remote deletion of Self-hosted deployment data;
- destructive retention periods invented without policy approval.

## Owner

Codex, with maintainer/security/legal review.

## Dependencies

- Task 267 retention/deletion audit;
- existing human auth, recovery delivery, artifact retention, object-store, and
  audit primitives;
- Task 259 Privacy/Terms and production communications gates.

## Assumptions

- cancellation stops renewal and retains customer data;
- deletion alone does not create a refund;
- the organization cannot be orphaned by deleting its sole owner;
- backups may require retention until normal rotation unless infrastructure
  proves immediate erasure.

## Work Items

- [-] Obtain approved backup wording and retention policy; the seven-working-day
  deletion grace period is now approved and configured, while backup and legal
  retention values remain a Task 259 decision.
- [x] Add purpose-bound deletion request/token and authenticated confirmation.
- [x] Add ownership-safe account/organization state transitions.
- [x] Implement idempotent, resumable data/object deletion with shared-object
  protection and reconciliation.
- [x] Add data-classification, enumeration, token, race, partial-failure, and
  Self-hosted tests.
- [-] Update approved Privacy/Terms copy through the existing policy process;
  local/customer copy and architecture documentation are updated, while final
  production legal publication remains Task 259.

## Validation

- `dart analyze lib test/deletion_test.dart` — passed.
- `dart test test/deletion_test.dart` — passed, including neutral no-login
  initiation, purpose-bound single-use/expiry, ownership blocking, staged
  account/org processing, shared/exclusive artifact handling, retry batches,
  tombstoning, and unconfigured-policy blocking.
- `dart analyze` (control-plane package) — passed with no issues.
- Dart formatting check for task-touched files — passed with no changes.
- Focused deletion/auth/onboarding/billing set (26 tests) — passed:
  `deletion_test.dart`, `human_auth_test.dart`, `human_auth_http_test.dart`,
  `customer_onboarding_test.dart`, and `customer_billing_test.dart`.
- Full control-plane `dart test` — not clean because 27 unrelated existing
  observation/reconciliation/credential suites fail; deletion tests remain
  green. Database/object-store cases that require unavailable external test
  services remain skipped.
- Cloud web `npm run typecheck` — passed.
- Cloud web `npm run lint` — passed.
- Cloud web `npm run build` — passed; `/account-deletion`,
  `/dashboard/privacy`, and the proxy route build successfully.
- `git diff --check` — passed for tracked changes.
- Final affected-scope validation after formatting — passed: control-plane
  analyzer and the 26 focused tests are green; Cloud web typecheck/lint/build
  are green.

## Next Action

Task 259 must supply the approved backup/evidence-retention and production
deletion-mail/policy-publication decisions. Complete the remaining managed
personal-deletion, shared-object, and backup/tombstone acceptance where the
environment supports it. The configured managed grace period is
`HYFENS_DELETION_GRACE_PERIOD=7d`.

## Blockers

- Backup rotation and deletion wording are infrastructure/policy inputs; the
  current store cannot erase individual records from immutable backups.
- Financial/billing, security/audit, and Enterprise commercial evidence
  retention durations require policy/legal authority.
- Production deletion-email delivery and final Privacy/Terms publication
  remain Task 259 dependencies.
- A managed production-like deletion run was not claimed in this task.

Current managed evidence remains partial: organization cancellation and staged
completion passed, but final personal-account deletion after ownership
resolution, managed shared-object physical-retention acceptance, backup
restore, and deletion-tombstone reconciliation remain unclaimed.

## Outcome

CODE_VERIFIED. Added a separate account-deletion and organization-deletion
domain with neutral no-login initiation, hashed purpose-bound deletion tokens,
strong authenticated confirmation, sole-owner protection, explicit Cloud
organization tombstones, billing-domain future-renewal stopping, credential and
session revocation, bounded resumable processing, content-addressed shared
object protection, anonymized evidence, and customer privacy/status surfaces.
No synchronous cascade, automatic refund, ownership transfer, Self-hosted
deletion, or arbitrary legal retention duration was introduced. Managed
acceptance and final policy/operational decisions remain external.

## References

- `tasks/267-commercial-lifecycle-refund-retention-deletion.md`
- `tasks/259-cloud-launch-operations-and-policy-gates.md`
- `docs/architecture/cloud-billing-lifecycle.md`
- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/artifact_retention.dart`

## History

- 2026-09-08 — Reserved from Task 267 audit; cancellation and artifact cleanup
  exist, but account/privacy deletion is not implemented.
- 2026-09-09 — Implemented and locally verified the deletion lifecycle. Added
  the public and authenticated privacy surfaces, durable deletion records,
  protected token consumption, ownership/billing safeguards, staged artifact
  cleanup, retention classification, and retryable worker behavior. Marked
  CODE_VERIFIED; retained policy, backup, production-mail, and managed-run
  gates as blockers/follow-up decisions.
- 2026-09-09 — Final affected-scope validation passed. Full package analysis
  passed; the focused deletion/auth/onboarding/billing tests and Cloud web
  typecheck/lint/build passed. The broader package test command still reports
  unrelated pre-existing observation/reconciliation/credential failures, so
  no broader-suite success is claimed.

## Follow-up correction — 2026-09-10

Status remains `CODE_VERIFIED`. The launch policy is now explicit: a verified
request is scheduled for seven working days, not seven elapsed calendar days.
The verification business date is day 1 when it is a configured Monday-Friday
business date; otherwise the next business date is day 1. Day 5 and day 7
reminders are durable notification events, and the existing bounded worker may
begin staged processing at the start of day 8. `processingAt` is persisted and
is the shared authority for the worker, UI, and notifications.

The grace state is recoverable but restricted server-side. Product mutations,
new credentials, checkout, plan changes, deployment operations, and ordinary
tenant reads are rejected with a deletion-pending domain error. Deletion
status, privacy/policy, safe billing status, ownership-resolution data, and
cancellation remain available. Authenticated and no-login cancellation use the
existing strong confirmation or a purpose-bound hashed cancellation token;
opening a link does not mutate state. The worker and cancellation use the
existing durable compare-and-set seam, so cancellation exactly before a worker
claim wins deterministically and stale reminders become no-ops.

The customer API now returns a bounded status projection rather than worker
credential references. Verification and acknowledgement copy include the
server-owned processing date, restriction, billing/refund separation, and a
secure cancellation action. The final completion notification remains after
the existing staged taxonomy/object/tombstone processing, not when processing
merely starts.

Configuration is explicit through `HYFENS_DELETION_GRACE_PERIOD=7d`,
`HYFENS_DELETION_BUSINESS_TIMEZONE` (UTC default; `Asia/Kolkata` and fixed
offsets supported), and optional `HYFENS_DELETION_HOLIDAYS`. The implementation
does not invent jurisdiction-specific holidays or statutory retention periods;
calendar/legal wording, backup rotation, and financial/security/Enterprise
evidence durations remain Task 259 decisions. Backup copies are temporary
retain until normal rotation and are not represented as instantly erased.

Organization deletion cancellation remains available until the worker claims
irreversible processing. If provider renewal cancellation has already been
scheduled, cancellation restores local organization access but retains and
surfaces the provider billing state rather than silently reactivating renewal.
The public cancellation response uses the bounded customer projection and does
not expose credential references or worker internals.

Focused validation on this correction passed: control-plane analyzer,
deletion tests including weekend/holiday scheduling, day-5 reminder
idempotency, cancellation stale-job no-op behavior, staged deletion, and
shared-object safety. Cloud validation remains required after the final UI
projection changes.

## Policy resolution and final affected-scope validation — 2026-09-10

The earlier `POLICY_DECISION_REQUIRED: deletion_grace_period` blocker is
superseded by the approved managed-Cloud policy: deletion uses a seven
working-day grace period, with staged processing eligible at the start of
working day 8. The business calendar remains explicitly configured: Monday
through Friday, a configured business timezone, and only explicitly supplied
holiday dates. No jurisdiction-specific holidays or statutory retention
durations are inferred.

Final affected-scope validation passed on the working-day correction:

- `dart test test/deletion_test.dart test/human_auth_test.dart test/human_auth_http_test.dart test/customer_onboarding_test.dart test/customer_billing_test.dart test/notifications_test.dart` — 52 tests passed.
- `dart analyze .` in `packages/control_plane` — no issues found.
- `dart format --output=none --set-exit-if-changed` for all changed Dart files — passed with no changes.
- Cloud `npm run typecheck:web` — passed.
- Cloud `npm run lint:web` — passed.
- Cloud `npm run build:web` — passed, including the account-deletion and privacy routes.
- `git diff --check` — passed on both task branches.

Managed mailbox, provider, backup/restore, and production-policy acceptance
remain operational Task 259 gates; this correction does not claim those as
completed.

## Review correction — 2026-09-10

The final spec review identified and closed several concrete gaps. Cloud
organization-scoped credentials are revoked at the start of the grace state;
pending personal deletion blocks new organization creation; public deletion
routes are explicitly Cloud-only; failed requests remain eligible for bounded
worker retry; reminder processing re-reads durable state and is serialized with
local cancellation; and cancellation tokens bind to a persisted request
generation so a token from an earlier cancelled request cannot cancel a later
request for the same organization. Staged organization cleanup now deletes
credential records by their token-hash storage key, preserving the existing
retention/evidence model. The Cloud privacy surface shows retained provider
cancellation state without exposing internal references.

Review findings that were refactoring-level smells only (module divergence and
small duplicated UI/auth checks) were intentionally left unchanged to avoid
scope expansion. The repository-required signed-off commit trailer is present
on the final control-plane commit.

## Re-request correction — 2026-09-10

An additional focused audit found that a cancelled request could otherwise
reuse its old processing schedule and notification identity. Resubmitted
requests now increment the persisted generation, recalculate the working-day
schedule from the new verification time, and use generation-scoped
acknowledgement/reminder/cancellation/completion notification identities.
This preserves idempotency without suppressing communication for a new
request. Organization credentials revoked by a pending deletion are restored
only when that request is cancelled, while independently revoked credentials
remain revoked. The regression is covered by the deletion test suite.

## Managed deployment and deletion acceptance evidence — 2026-09-10

The root-authorized current control-plane image was deployed through the
corrected protected wrapper. The image contains the working-day deletion
implementation and the current notification-copy correction; the deployed
`deletion.dart`, `http.dart`, and notification regression-test hashes match the
checked-out control-plane sources. The deletion and notification systemd
timers are enabled and active, and manual worker runs complete successfully.

The managed business calendar is configured as Monday-Friday in UTC with no
implicit holidays. For the completed disposable organization request,
verification occurred on 2026-09-10; the server persisted working day 5 as
2026-09-16, working day 7 as 2026-09-18, and processing eligibility as
2026-09-21 (the start of working day 8). The dates were read from the durable
request projection; no database timestamps or host clock were edited.

### Acceptance A — cancellation during grace

- A disposable customer was created through the public signup and verification
  flow. The sole-owner personal deletion path correctly required ownership
  resolution instead of orphaning the organization.
- Organization deletion was then requested through the authenticated privacy
  surface. The account entered the persisted pending/grace state, retained
  its data, and exposed the deletion-only status/cancellation surface.
- Normal tenant mutations were restricted server-side. Billing status and the
  deletion status/cancellation operation remained available.
- Day-5 and day-7 reminder jobs each produced exactly one notification in the
  managed run. Cancellation was completed through the password-confirmed
  deletion flow, and the cancellation acknowledgement reached the owned test
  mailbox.
- A current-image day-8 replay after cancellation processed zero requests.
  This verifies stale processing/reminder work is a no-op after the durable
  cancellation compare-and-set. No refund record or provider refund was
  created, and provider billing was not falsely reported as restored.

### Acceptance B — staged organization deletion

- A second disposable organization was verified for deletion and allowed to
  reach day 5, day 7, and day 8 through the supported test-clock seam.
- The managed deletion worker processed one due request and reported one
  completed request. The notification worker processed the completion event.
  The owned mailbox contained one deletion-verification, one immediate
  acknowledgement, one day-5 reminder, one day-7 reminder, and one completion
  message for this request. Provider state was recorded as accepted; the
  mailbox receipt is the delivery evidence, and no unsupported provider
  callback correlation is claimed here.
- The organization record reached the explicit deleted state used as the
  Cloud tombstone, with a completion timestamp and no automatic refund. The
  retained billing projection resolved to the internal Free assignment rather
  than leaving a paid entitlement active.
- The worker completed through the existing bounded staged taxonomy and did
  not execute a synchronous database cascade. The completion notification was
  emitted only after the request reached its completed/tombstoned state.

### Acceptance boundaries

The following remain unclaimed as managed evidence: a final personal-account
deletion after ownership resolution, managed shared-object physical-retention
acceptance, backup restore, and deletion-tombstone reconciliation after
restoring an old backup. Shared content-addressed object safety and staged
retry behavior remain covered by the focused control-plane tests. Backup
infrastructure is not proven on the managed host, so backup copies remain a
`TEMPORARY_RETAIN`/operations-policy boundary rather than an assertion of
immediate erasure.

The mailbox run predates the final lifecycle copy correction in one captured
completion message. Current source-level notification tests pass, and the
deployed image hashes match the corrected sources; a fresh mailbox capture of
the corrected completion body is still a follow-up acceptance item. The
correction removes repeated product-name copy while retaining the shared
Hyfens shell branding.

The overall task remains `CODE_VERIFIED`: application behavior is locally
verified and organization deletion has partial managed evidence, but this
task does not claim complete managed deletion, backup/restore, or legal
retention acceptance.

## Post-review safety correction — 2026-09-12

Commit `5d622c8` closes four implementation gaps identified during the task
closure review without changing the deletion model: Cloud-only checks now
cover organization status and cancellation; organization cancellation uses a
retryable `cancellation_pending` state so restoration cannot be reported as
complete before it finishes; `billing_pending` requests are retried by the
durable worker and persist credential-revocation evidence; and deletion
processing uses a durable fifteen-minute compare-and-set lease in both file
and PostgreSQL stores. Active leases are not reclaimed, stale leases are
recoverable, and stale workers cannot overwrite a newer claim.

Added regression coverage for self-hosted rejection, billing recovery,
interrupted cancellation recovery, and concurrent worker claims. The focused
control-plane validation passed 89 tests; `dart analyze`, scoped formatting,
and `git diff --check` also passed. Managed backup/restore, tombstone
reconciliation, personal deletion after ownership resolution, and legal
retention decisions remain Task 259 gates.

Follow-up commit `93248b0` also compare-and-set fences the initial
organization billing-to-grace transition, preventing a concurrent worker from
having its recovered billing or credential evidence overwritten by the
requesting process.

## Managed working-day acceptance revalidation — 2026-09-13

The merged working-day deletion implementation was revalidated against the
managed control-plane composition using the approved Gmail workspace mailbox
(`admin@hyfens.com`) as the owned acceptance mailbox. The business calendar was
the persisted UTC Monday-Friday calendar with no configured holiday list. For
the clean no-cancel run, verification occurred at
`2026-09-12T18:58:53.581707Z`; the durable request projection persisted
working day 5 as `2026-09-18`, working day 7 as `2026-09-22`, and day-8
processing eligibility as `2026-09-23`. The test clock was passed to the
worker; no host clock or database timestamp was edited.

### Acceptance A — cancellation during grace

- A disposable customer was created through public signup and real email
  verification. No-login initiation returned the same neutral acknowledgement
  for known and unknown addresses. The verification link was followed and
  deletion was explicitly confirmed; opening the link alone did not mutate the
  deletion state.
- The organization entered the durable grace state. The privacy/status surface
  remained available while ordinary tenant changes and billing mutations were
  restricted by the server-side deletion boundary. The current billing state
  was still independently readable for safe status purposes.
- The current request generation produced one delivered day-5 reminder and one
  delivered day-7 reminder. Cancellation after day 7 required password and
  explicit `DELETE` confirmation, restored normal local access, and produced
  one cancellation acknowledgement in the owned mailbox.
- Replaying day-5, day-7, and day-8 worker/notifier work after cancellation
  processed zero deletion requests and created no new reminder delivery. No
  refund record/provider refund was created, and provider cancellation was not
  falsely reported as reversed. Previously revoked credentials were not
  implicitly restored.

### Acceptance B — completion after day 8 eligibility

- A separate disposable organization was verified for deletion and allowed to
  pass the persisted day-5 and day-7 milestones without cancellation. The
  mailbox contained exactly one each of the immediate scheduled
  acknowledgement, day-5 reminder, day-7 final reminder, and completion
  acknowledgement for that request, with the corresponding notification
  deliveries reaching `delivered` at one attempt each.
- At the persisted day-8 instant the managed deletion worker reported
  `processed=1 completed=1`; the notification worker then delivered the final
  completion message. The organization projection reached the explicit
  `deleted` tombstone state and a fresh private Cloud login found no active
  customer organization. This is not claimed as a direct authenticated 410
  probe because credentials were revoked before that probe; the source/API
  boundary still maps a valid deleted-organization request to
  `ORGANIZATION_DELETED`/410.
- The retained database evidence included audit, billing, notification,
  deletion-request, idempotency, and organization tombstone records. The
  disposable run created no application/environment/artifact rows, so it is
  not managed evidence for exclusive or shared artifact-byte deletion.
- Completion was emitted after the request reached its completed/tombstoned
  state. The message described active-system completion and retained-evidence
  caveats; it did not claim that backup copies had been erased.

### Managed acceptance boundaries

The worker timers are enabled and active, and the root-managed deployment
configuration remains protected (`root:root`, mode `0600`). The six audited
operational roles are assigned to `admin@hyfens.com`. These facts establish
execution and assignment wiring, not backup readiness or mailbox/runbook
monitoring.

The following remain unclaimed as managed evidence: final personal-account
deletion after ownership transfer, managed shared-object physical-retention
acceptance, a scheduled/off-host encrypted backup, restore-time deletion
tombstone reconciliation, and an isolated object-store purge run. The
database-only restore rehearsal is recorded separately as
`DATABASE_RESTORE_REHEARSAL_PASS`; it is not a managed backup policy or
resurrection-proof result. The test restore container and root-only dumps are
temporary operator rehearsal artifacts.

The working-day implementation remains code-verified with partial managed
acceptance. It does not claim statutory compliance or invent financial,
security/audit, Enterprise, or backup retention durations.

## Evidence publication — 2026-09-13

The revalidation evidence in this append-only update is published on commit
`671ebbd` and pull request `#10`. The task remains blocked at
`CODE_VERIFIED` pending the explicitly listed managed backup/object-store and
policy gates.

## Pending billing-surface correction — 2026-09-13

The managed review found that the private billing page could briefly show
upgrade, downgrade, cancellation, and Enterprise mutation controls while the
server-side deletion boundary correctly rejected those operations. Cloud PR
`#11` (`fix/deletion-pending-billing-ui`, commit `d91ae85`) now reads the
existing account/organization deletion projections, hides those controls while
deletion is restricted, and fails closed while status is unavailable. It keeps
authoritative billing status and the separate reviewed-refund path visible.
The PR is validated but not yet deployed; no deletion-safety bypass was found.

## Coordinator blocker reconciliation — 2026-09-13

The managed deletion timers and root-protected environment are active. The
working-day grace, cancellation CAS, reminder idempotency, organization
tombstone, billing/refund separation, and disposable mailbox acceptance remain
as recorded above.

Two concrete implementation gaps remain under bounded review. Personal-account
deletion currently resolves a verified identity before confirming customer
membership, and final credential collection only recognizes `credential.issue`
although the service emits additional credential issuance audit actions. The
final account path also revokes credential rows rather than erasing their
token-hash keyed records where the existing deletion store can safely do so.
These are being corrected with focused tests; no ownership-transfer API or new
workflow engine is being introduced.

The host has not yet proven a scheduled/off-host encrypted backup, an object
store purge/reconciliation run, or replay of deletion tombstones after an old
backup restore. The isolated database restore remains
`DATABASE_RESTORE_REHEARSAL_PASS` only. The additional backend service's data
scope is not included in the current deletion/backup acceptance boundary.

The previously identified sole-owner transfer flow and atomic concurrent owner
coordination remain product/governance gaps rather than silently passing
acceptance. Task 269 remains `CODE_VERIFIED` with managed acceptance and
retention gates open; no claim of statutory compliance or backup erasure is
made.
