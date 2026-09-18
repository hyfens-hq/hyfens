# Rollouts and privacy-preserving observability

Status: Task 40 design-only proposal. No rollout scheduler, telemetry
ingestion, dashboard, webhook worker, or runtime network client is implemented.

This document defines delivery eligibility and optional observations around the
frozen runtime lifecycle. It deliberately does not turn a server's rollout
state or a telemetry event into runtime authority.

## Model and vocabulary

| Term | Meaning | Authority |
| --- | --- | --- |
| Release | An immutable store-installed application/runtime baseline identified by an exact release ID | The shipped release and runtime compatibility records |
| Patch | A release-bound Patch Format v1 artifact with a signed sequence and capability declarations | Runtime verifier and state-v4 controller |
| Rollout | A mutable policy that says which eligible installations may be offered one exact patch/control | Control plane, subject to audit and authorization |
| Cohort | A deterministic or explicitly listed set of pseudonymous installations | Rollout policy; not an identity or security boundary |
| Installation | One app installation with an app-scoped random identifier | Runtime locally; server sees only an optional pseudonymous token |
| Observation | An optional bounded report of a runtime event | Runtime event producer; telemetry store is non-authoritative |
| Diagnostic | A stable reason code and safe metadata for an operator/developer | Runtime/CLI projection; source paths and secrets are excluded |
| Emergency stop | A delivery or signed-control action with an explicitly bounded effect | Control plane plus the existing runtime trust path |

Product rollout states and runtime states are separate. A product rollout may
be `DRAFT`, `READY`, `ROLLOUT_PENDING`, `ACTIVE`, `PAUSED`, `COMPLETED`,
`SUPERSEDED`, `REVOKED`, `ROLLED_BACK`, or `FAILED`. The runtime remains in
`BASE`, `CANDIDATE`, `CURRENT`, or `FAILED` as defined by state-v4. A server
must never label a patch `CURRENT` merely because it is `ACTIVE` in a rollout;
only runtime health confirmation can do that.

## Eligibility and rollout modes

Every offer is evaluated against an exact application, environment, release
ID, platform target, runtime compatibility, patch sequence, and artifact
digest. Rollout precedence is:

```text
store-release-required / signed revocation
        > emergency delivery stop
        > paused rollout
        > environment and release policy
        > internal/canary/cohort/percentage eligibility
        > full rollout
```

The modes are operational policies, not alternative trust models:

| Mode | Eligibility rule | Safe use |
| --- | --- | --- |
| `INTERNAL` | Explicit allowlist of pseudonymous installation tokens or operator test cohort | Developer and release-manager verification before any broad offer |
| `CANARY` | Small fixed cohort plus an observation window | Detect obvious rejection, health, or runtime-fault signals |
| `PERCENTAGE` | Deterministic bucket below a configured threshold | Expand gradually without changing an installation's assignment for the same rollout |
| `COHORT` | A named, audited set or non-sensitive deployment label | Target a team, environment, region, or customer-controlled group without collecting unrelated identity data |
| `FULL` | All otherwise eligible installations in the environment | Final promotion after gates and approvals |
| `PAUSED` | No new offers; existing verified installations continue | Freeze delivery while investigating or waiting for review |
| `EMERGENCY_STOP` | Immediately stop new offers and optionally withhold a named artifact/control | Contain distribution; it does not uninstall or forcibly rewrite runtime state |

The rollout target is one exact patch or one exact signed control. A rollout
cannot select “latest,” substitute a different digest at the same sequence, or
silently move an installation to an older patch. Promotion requires a new
immutable policy revision, optimistic-concurrency check, an audit event, and
the same artifact identity at every stage.

## Privacy-preserving cohorts

The runtime creates a cryptographically random, app-scoped installation token
on first launch and stores it in the app's private storage. It is not derived
from an IMEI, advertising ID, hardware serial, phone number, email, account,
IP address, or unrelated application. Uninstall/reinstall may create a new
token. Cohort assignment is deterministic for the lifetime of a rollout:

```text
bucket = uint64(HMAC-SHA-256(rolloutSalt, opaqueInstallationToken)) % 10_000
eligible when bucket < percentageBasisPoints
```

`rolloutSalt` is rollout metadata, not a signing key. The distribution service
may receive the random token for lookup and persist only a keyed digest or an
equivalent opaque cohort key. The raw token must not enter optional telemetry.
If an environment cannot store even a pseudonymous installation key, the
deployment may use `FULL`, a manually imported cohort, or client-local
assignment; that weakens measurement, not the runtime's cryptographic rules.

Cohort assignment is not an authorization boundary. An attacker who changes a
request may obtain an offer, but still faces the runtime signature, exact
release, capability, sequence/high-water, resource, and health checks. An
attacker who suppresses a request causes delay or no update, not execution of
untrusted bytes.

## Emergency controls

Emergency responses must name their effect and keep the runtime invariant:

| Control | Effect | What it cannot do |
| --- | --- | --- |
| Delivery pause | Stops new offers for a rollout/environment | Cannot remove a currently installed patch or lower high-water |
| Artifact withholding/revocation | Stops serving or offering a named artifact; records the incident | Cannot make an already downloaded artifact trusted or erase runtime state |
| Signed rollback to base | Delivers the existing separate signed rollback control; runtime verifies the exact durable high-water and selects AOT base | Cannot select an old patch or reset high-water |
| Rollback to known-good behavior | Publishes a newly signed higher-sequence artifact that restores the intended behavior | Cannot reactivate an old sequence/digest after rollback |
| Store-release-required | Blocks the OTA path for a change that crosses native, capability, permission, package, or policy boundaries | Cannot be bypassed by relabeling the artifact or changing rollout metadata |
| Emergency stop | Combines immediate offer pause with restricted operator access and incident audit | Cannot force arbitrary code, bypass health, or replace runtime trust |

Only explicitly authorized roles may invoke emergency controls. Two-person
approval and a separate rollback/signing authority are enterprise policy
options, not assumed provider features. Automation may recommend or pause a
rollout from observations, but it may not issue a signing/key-lifecycle
command or override runtime rejection.

## Optional runtime observations

Observations are emitted after local runtime decisions and are never required
for verification, activation, health, rollback, AOT fallback, or offline use.
The initial bounded event vocabulary is:

| Event | Meaning |
| --- | --- |
| `release_seen` | The release/runtime started and recognized its exact release identity |
| `patch_offered` | A delivery response offered a named sequence/digest |
| `patch_downloaded` | The addressed bytes were downloaded into a bounded local staging path |
| `patch_verified` | Local digest, canonical, signature, exact-release, capability, and resource checks passed |
| `patch_activated` | The candidate was published after a durable pending record |
| `patch_healthy` | The runtime accepted the exact pending candidate as healthy |
| `patch_rejected` | A candidate/control was rejected with a stable reason class |
| `runtime_fault` | A bounded runtime fault caused function disablement, candidate fallback, or another documented recovery |
| `rollback_applied` | A signed rollback control or runtime recovery selected base/known-good behavior |
| `base_active` | The compiled AOT base is active after initial start or recovery |

`patch_healthy` and `rollback_applied` are observations of local state, not
commands from the server. Missing, delayed, duplicated, or spoofed events may
make the dashboard incomplete but cannot make a patch current.

### Minimal payload

An opted-in event contains a schema version, event ID, coarse occurrence time,
application/environment IDs, platform target, exact release ID, optional patch
sequence/digest, a stable reason code when applicable, and an optional
pseudonymous installation key. It may include a bounded batch count and
sampling rate. It must not include:

- source code, source-map paths, function bodies, user content, request
  payloads, stack traces with arbitrary text, private keys, access tokens, or
  signed artifact bytes;
- IMEI, advertising ID, hardware serial, phone number, email, account ID,
  precise location, contact data, or an unrelated application identifier;
- arbitrary URLs supplied by the runtime or capability arguments/results.

Runtime faults use enumerated reason classes and bounded diagnostic details.
The local `tool status` surface remains developer-local; a hosted dashboard
does not gain unauthenticated remote introspection of the application.

### Opt-out, disablement, sampling, and retention

The default product contract is that runtime observations are off unless the
application owner/operator opts in. Self-hosted and air-gapped deployments
can keep them disabled permanently. A managed deployment must expose an
application/environment switch and honor organization or enterprise
disablement. An end-user privacy setting, where the application offers one,
must override collection of optional runtime events. Rollout eligibility can
still use a separately governed random installation token when needed; it must
not silently turn observations on.

Sampling is configured per event family and deployment, bounded to a value in
`[0, 1]`, and included in the event metadata. A deterministic decision based
on installation key plus event family avoids repeated retries changing the
sample unexpectedly. The runtime may aggregate repeated faults locally and
cap queue size, batch size, event age, and retry count. Sampling is for
measurement only; it must not be used to authorize an update or to hide a
security audit event.

Proposed initial retention defaults are policy defaults, not compliance claims:

| Data | Default | Boundary |
| --- | --- | --- |
| Raw runtime observations | 30 days | Delete or aggregate at expiry; configurable shorter by tenant/environment |
| Aggregated rollout health | 13 months | Keep only dimensions needed for trend and release comparison; configurable by customer |
| Installation/cohort key material | While active, then 30 days after last observation | Keyed/pseudonymous; delete with the observation relationship |
| Security/control-plane audit | 1 year minimum product default, customer-configurable upward | Append-only access-controlled record with secret redaction; longer retention is an enterprise policy decision |
| Debug/source-map bundles | Short-lived release policy, default 30 days | Separate access and deletion from runtime observations |

Self-hosted operators own the retention configuration and deletion/export
process. Managed systems must document residency, processors/subprocessors,
access, deletion, and export boundaries before enabling collection. Designing
these controls does not claim GDPR, DPDP, SOC 2, ISO, or any other compliance.

## Safety automation

Optional automation can pause a rollout after conservative thresholds for
rejection, health-confirmation failure, runtime faults, or rollback signals.
The policy must require a minimum observation count, identify the sample rate,
and account for offline clients and duplicate/spoofed events. A single noisy
event cannot silently roll back every installation. The safe automatic action
is delivery pause plus an audit/alert; a signed rollback or key revocation
requires an explicitly authorized human/CI signing workflow.

Telemetry is an incomplete and potentially adversarial measurement channel:
the server must label confidence, never infer absence of faults from absence
of events, and never treat an observation as proof that a patch was accepted
by every client.

## Signed, replay-protected webhooks

Webhooks notify external systems of `patch_ready`, rollout changes,
fault-threshold recommendations, signed rollback application, key rotation,
and `store_release_required`. They are notifications, not trust decisions.

The sender signs a canonical envelope containing a version, event type,
event ID, delivery ID, key ID, Unix timestamp, body digest, and canonical
body. A conceptual signature input is:

```text
hyfens-webhook-v1\0<timestamp>\0<event-id>\0<body-digest>\0<body>
```

The receiver verifies the HTTPS peer as appropriate for its deployment,
signature/key ID, timestamp tolerance, body digest, and event schema before
processing. It stores the event/delivery ID with a bounded expiry and treats a
duplicate delivery as an idempotent acknowledgement. A different body for an
already-seen event ID is an equivocation and is rejected. Key rotation uses an
overlap window and an authenticated key registry; no provider or webhook
secret is implemented by this design.

Retries use bounded exponential backoff and preserve the same event/delivery
identity. Receivers must fetch current state through an authenticated API and
recheck authorization/optimistic version before acting; a webhook payload
cannot authorize a rollout, rollback, or key change. Endpoint registration
must also apply SSRF/egress controls described in the productization threat
model.

## Store-policy separation

Runtime correctness and rollout safety do not establish Apple App Store or
Google Play approval. Downloaded interpreted Dart behavior, UI/navigation
changes, pure-Dart dependency changes, permissions/data-use changes, billing,
or hidden functionality require a change-specific policy review using the
existing store-policy research. Native code, AOT output, manifests,
entitlements, permissions, plugin/native SDK changes, and other build-time
surface changes remain `STORE_RELEASE_REQUIRED`. No dashboard, rollout mode,
signature, or telemetry claim may be advertised as “App Store compliant,”
“Play approved,” or equivalent without authoritative, app-specific evidence.

## Phase 1D evidence boundary

The rollout/observation design does not close Phase 1D gaps: true power-loss
durability remains untested; direct physical stale-byte rejection was not
proven beyond delivery-boundary withholding; iOS logs/UI and timings were
environment-gated by the missing Developer Disk Image; no fresh Android
15-sample reducer was run; the adjacent Flutter 3.47.1/Dart 3.13.1 path is
`SUPPORTED_WITH_LIMITATIONS`; independent customer-app validation was not
run; and the additional async benchmark was not run. These are respectively
gates for production durability, beta device-injection safety, iOS beta
observability/performance claims, new Android performance claims, broad SDK
support claims, customer beta compatibility, and async performance claims.
Local developer status remains the only validated observability surface in
Phase 1D; this document proposes a future optional outbound observation model
without claiming it exists.

## Non-goals

No scheduler, telemetry database, dashboard, webhook sender, authentication
provider, remote introspection bridge, client network implementation, or
runtime behavior change is part of this design.
