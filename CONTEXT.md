# Hyfens Control-Plane Scheduling Context

This glossary defines the domain language for scheduled health evaluation and
its boundary with rollout eligibility.

## Language

**Evaluation Schedule**:
A tenant-scoped intent to create future health-evaluation work for one rollout.
_Avoid_: Cron job, timer

**Schedule Revision**:
An immutable version of an evaluation schedule's policy, readiness, and
enablement choices.
_Avoid_: Mutable cron configuration

**Schedule Generation**:
The monotonic position of one schedule revision in its immutable history.
_Avoid_: Retry count, rollout revision

**Logical Evaluation Key**:
The complete immutable identity of one scheduled evaluation meaning, including
its rollout revision, window, policies, and schedule generation.
_Avoid_: Job name, source offset

**Scheduled Evaluation Work**:
The durable orchestration record for one logical evaluation key.
_Avoid_: Job, task

**Work Attempt**:
One bounded effort to advance scheduled evaluation work.
_Avoid_: Retry job

**Lease**:
Time-bounded permission for one scheduler principal to advance scheduled
evaluation work.
_Avoid_: Ownership, lock forever

**Scheduler Principal**:
A non-human, tenant/application/environment-scoped identity permitted to claim
and evaluate scheduled work.
_Avoid_: Admin account, signing identity

**Auto-Halt Principal**:
A distinct tenant/application/environment-scoped identity permitted to request
application of eligible scheduled halt evidence.
_Avoid_: Auto-halt-enabled scheduler, admin account

**Automatic Halt**:
Explicitly enabled routing of an existing `HALT_NEW_OFFERS` decision through
the conservative halt boundary to stop future offers.
_Avoid_: Kill switch, rollback

**Automatic-Halt Candidate**:
Scheduled evaluation work with immutable linked halt evidence that may be
considered by the automatic-halt policy but has no mutation authority itself.
_Avoid_: Alert, crash event, raw health signal

**Automatic-Halt Policy**:
An immutable, versioned rule set governing whether current scheduled halt
evidence may be applied automatically.
_Avoid_: Evaluation policy, production default

**Automatic-Halt Environment State**:
An immutable generation binding one exact policy to separate policy-approval
and production-enablement booleans for one tenant/application/environment.
_Avoid_: Mutable feature flag, policy existence

**Automatic-Halt Intent**:
Immutable evidence embedded in a `HALT_APPLYING` scheduled-work version after
all P3E5-4B applicability and two-authority checks pass. It does not mean a
rollout was halted and grants no P3E-4/P3A authority.
_Avoid_: Halt application, rollout revision, remote kill command

**Applicability Transition**:
The fenced `EVALUATED -> HALT_APPLYING` work-only CAS that persists one
canonical automatic-halt intent without invoking P3E-4 or changing delivery
eligibility.
_Avoid_: Automatic halt applied, rollout CAS

**Logical Work Meaning v2**:
Scheduled work identity that additionally binds the automatic-halt policy,
enablement, scheduled source, SEALED readiness, and PATCH_SAFETY reason-class
semantics. V1 is never automatically eligible.
_Avoid_: Reinterpreted v1 work, line-number identity

**Halt Application**:
Immutable evidence of the conservative halt boundary's result for one exact
decision and rollout precondition.
_Avoid_: Rollback command, mutable rollout flag

**Automatic Halt Application**:
P3E5-4C's bounded adapter result: one exact scheduled work item invokes the
existing P3E-4 evidence/application core and existing P3A expected-revision
CAS using `scheduled-halt:<workId>`. It has no direct rollout writer.
_Avoid_: Scheduler-specific rollout mutation, runtime trust change

**Automatic Halt Completion Proof**:
Bounded linkage containing the current fenced lease, intent digest, immutable
health-halt application, and resulting `HALTED` revision. The schedule store
accepts `HALT_APPLYING -> COMPLETED` only after this proof validates.
_Avoid_: Generic executor completion, unverified success flag

**Reconciliation**:
Idempotent comparison of orchestration state with immutable evaluation, halt,
and rollout evidence after retries or interruption.
_Avoid_: Repair by overwrite

**Lease Fencing Token**:
A fresh opaque per-claim secret whose digest, owner, work version, scope, and
expiry must all match before claim-side state can advance.
_Avoid_: Session ID, reusable worker key

**Reclaim**:
Creation of a new attempt and fencing token after the prior lease has expired
and immutable schedule/target bindings have been revalidated.
_Avoid_: Lease renewal, token reuse

**Retry Wait**:
A persisted, bounded pause until an authoritative `notBefore` time following a
classified transient claim-side failure.
_Avoid_: Busy loop, automatic infinite retry

**Automatic-Halt Recovery**:
Evidence-first reconciliation of one expired `HALT_APPLYING` work item. It
may install one fresh fenced lease for the same semantic attempt, then invoke
the existing P3E-4/P3A application adapter; it never writes rollout state
directly or inherits a successor revision.
_Avoid_: Generic scheduler reclaim, blind retry, repair by guessing

**Recovery Outcome**:
One of the bounded wire outcomes `APPLICATION_FOUND_AND_VALID`,
`APPLICATION_NOT_FOUND_RETRYABLE`, `APPLICATION_STALE`,
`APPLICATION_CONFLICT`, `APPLICATION_CORRUPT`, or `SECURITY_REJECTED`.
_Avoid_: Unbounded retry, success inferred from a missing response

**Semantic Attempt Preservation**:
Automatic-halt reclaim changes the work fence and lease but preserves the
intent's original evaluation/decision/attempt identity. It is not a successor
evaluation attempt and cannot select a successor rollout revision.
_Avoid_: Attempt-number fork, successor inheritance

**P3E5-4E Integration Evidence**:
Bounded, test-vector-only evidence for automatic-halt recovery under local
File/PostgreSQL faults, audit failure, measured lease timing, and contention.
It does not mean provider HA, production capacity, beta readiness, or store
approval.
_Avoid_: Treating a local fault-injection result as a production guarantee

Task 67 exact closure evidence now includes independent pre/post claim and
pre/post P3A PostgreSQL response-fault vectors plus a narrow single-call
P3E5-3 → P3E5-4 rehearsal with separate evaluation and Auto-Halt principals.
This closes the bounded Task 67 engineering evidence only; P3E5-5 remains a
separate maintainer decision.

**P3E5-5 Design Boundary**:
Task 68 is design-only. The proposed reconciliation model is bounded startup
plus explicit tenant-scoped administration, with repairable projections,
recoverable operational state, and report-only immutable divergence. It adds no
rollout authority, runtime trust, periodic worker, queue, dashboard, or
production claim. P3E5-5 implementation remains unauthorized pending review.

**P3E5-5A Domain Boundary (2026-08-24)**:
Task 69 implemented the approved domain-only foundation: typed invocations,
findings, repair attempts, policy bounds, cursor/fairness state, deterministic
canonical identities, stable divergence taxonomy, repairability/severity/action
vocabularies, immutable-source classification, exact-scope reconciliation
principal authority, tenant checks, malformed-input/resource rejection, and
audit-safe fields. It does not execute reconciliation, persist findings,
mutate projections or rollout state, expose observability endpoints, or change
runtime/mobile behavior. P3E5-5B remains a separate maintainer-review gate;
provider, beta, production, store, legal, and privacy gates remain open.

**P3E5-5B Bounded Reconciliation Boundary (2026-08-24)**:
Task 70 added append-only File/PostgreSQL finding and repair-attempt storage,
versioned lifecycle/cursor CAS, bounded startup and exact-scope administrator
execution, detector composition, audit-before-repair, postcondition checks,
report-only immutable divergence, tenant isolation, and malformed-input
rejection. It adds no periodic worker, queue, metrics/readiness/diagnostics,
rollout writer, P3E-4/P3A call, runtime/mobile behavior, or production claim.
Concrete authoritative source detectors and existing projection-CAS repair
adapters remain an explicit continuation of P3E5-5B; the generic seams are not
treated as evidence that those integrations already work.

## Cloud commercial vocabulary

**Cloud Plan**:
A server-resolved Hyfens Cloud service tier. The current stable keys are
`free`, `starter`, `team`, and `enterprise`.
_Avoid_: Self-hosted as a plan, price inferred from a provider row

**Deployment Model**:
The operating ownership boundary for a control plane: `cloud` or
`self_hosted`. It is independent from the Cloud subscription plan.
_Avoid_: Treating Free as the self-hosted edition

**Cloud Plan Assignment**:
The organization-scoped persisted state from which the server resolves the
effective Cloud plan. A new Cloud organization receives an explicit internal
Free assignment without a payment-provider subscription.
_Avoid_: Missing subscription means Free, frontend-only default

**Effective Entitlements**:
The server-authoritative capabilities resolved from deployment model and plan
state. Core release-integrity capabilities are shared across Cloud plans and
self-hosted operation; unresolved commercial limits are not invented here.
_Avoid_: Pricing-page feature metadata as authorization

**Enterprise Quote**:
An operator-issued custom Cloud commercial proposal associated with an
organization. It is a Hyfens commercial record, not a Razorpay Plan or a
public fixed-price SKU.

**Enterprise Quote Version**:
An immutable snapshot of one Enterprise proposal's customer-visible and
internal commercial terms. Issued or accepted terms remain reproducible;
revisions create a new version.

**Enterprise Contract**:
The accepted quote version plus its server-snapshotted commercial terms,
contract status, provider mapping, and typed entitlement overrides. It is the
source used to resolve effective Enterprise access after trusted payment
confirmation.

**Provider Billing State**:
Razorpay Plan/Subscription identifiers and lifecycle evidence used to collect
payment for a Hyfens contract. Provider state does not define Hyfens price,
term, organization, or entitlements.

**Enterprise Entitlement Override**:
A typed contract-specific value for an existing Cloud countable dimension,
such as applications, environments per application, or members. It is
resolved centrally on top of the Enterprise base plan; it is not an arbitrary
JSON permission blob.

**Provider Mapping**:
A server-owned link from a provider subscription to one accepted Enterprise
contract. Provider event processing derives the organization through this
mapping rather than trusting tenant identifiers supplied by a browser or
provider payload.
_Avoid_: Provider Plan as contract, customer-selected Enterprise price,
unbounded "everything unlimited" entitlements

## Dashboard product context

**Customer Workspace**:
The authenticated customer surface for one customer's Organization, its
Applications, Environments, delivery records, members, credentials, and
organization audit. It never represents all Hyfens customers or internal
platform operations.

**Platform Console**:
The authenticated Hyfens-operator surface for platform-wide organizations,
service operations, support/security evidence, accounts, and commercial
operations where authorized. It is not a customer workspace with extra menu
items.

**Customer Organization**:
The tenant root a customer owns or belongs to. Customer navigation and
authorization remain inside the Organization → Application → Environment
scope.

**Membership Switcher**:
A Customer Workspace control that selects among Organizations for which the
current human identity has an authorized membership. It is not a directory of
all customer Organizations.

**Platform Organization Directory**:
A Platform Console view of customer Organizations visible to an authorized
platform operator. It uses explicit platform authority and must not be built
from customer membership switching.

**Shared Authentication**:
The common identity and session lifecycle used by customer users, platform
operators, the CLI, and device authorization. Shared identity does not make
customer and platform authorization interchangeable.

**Authorization Audience**:
The product context in which an authenticated identity is acting. Customer
audience access is tenant-scoped; Platform audience access is platform-scoped
and separately authorized.

**Delivery Observation**:
Trusted evidence that a named artifact payload was transferred by one delivery
source, with byte quantity, occurrence time, and source identity. A delivery
observation is not a signed URL issuance or a patch-install receipt.
_Avoid_: Request count, origin fetch, device installation

**Delivery Meter Authority**:
The completeness of trusted delivery-byte evidence for the configured customer
delivery surface: `authoritative`, `partial`, or `unavailable`. Authority does
not itself approve a commercial quota or overage policy.
_Avoid_: Treating one origin counter as a universal bandwidth total

**Customer Delivery Egress**:
Artifact payload bytes transferred toward the consuming client. Traffic from a
CDN to its origin is infrastructure transfer unless the configured accounting
boundary explicitly makes it customer egress.
_Avoid_: Counting CDN client egress and origin fetch bytes together

**Account Deletion Request**:
A verified, purpose-bound privacy request for removing or deidentifying one
human Cloud identity. It does not delete organizations the identity merely
belongs to, and it cannot complete while the identity is a sole owner without
ownership resolution.

**Organization Deletion Request**:
An owner-authorized Cloud tenant deletion request that stops future renewal,
waits for the configured policy boundary, and then processes customer-owned
data in resumable stages. It is separate from cancellation, downgrade, and
refund.

**Retention Classification**:
The deletion treatment assigned to each data class: `erase`, `anonymize`,
`retain`, or `temporary_retain`. The classification preserves required audit,
billing, Enterprise, security, and shared-object evidence without inventing
legal retention durations.

**Notification Event**:
A provider-neutral, versioned Hyfens communication consequence emitted after
an authoritative domain action. It contains normalized recipients, safe
correlation/provider references, and either non-sensitive variables or an
encrypted sensitive payload. It is not a Razorpay webhook name.

**Notification Delivery**:
The durable per-recipient attempt projection for a Notification Event. It
tracks normalized delivery state, retry attempts, provider message reference,
and recipient digest without storing unnecessary message or credential data.

**Notification Provider Adapter**:
The narrow interface that renders a Hyfens Notification Event and submits it
to a selected transport such as Keplars. Provider responses are normalized and
must not become the source of truth for billing, entitlement, or account state.

**Deletion Grace Period**:
A verified account or organization deletion request remains recoverable and
restricted during the configured working-day window. Verification schedules
deletion; it does not erase data. Cancellation is available until the worker
atomically claims irreversible processing.

**Business Deletion Schedule**:
The persisted working-day schedule derived from the configured business
timezone, Monday-Friday rule, and explicit holiday list. It contains the day-5
and day-7 reminder boundaries and the day-8 `processingAt` authority shared by
the worker, customer UI, and deletion notifications.
