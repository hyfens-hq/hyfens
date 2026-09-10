# ADR 0009 — Make rollout eligibility mutable but telemetry optional and non-authoritative

- Status: Proposed for Task 40 productization design; implementation not authorized
- Date: 2026-08-23
- Decision owners: Maintainers after productization review

## Context

The runtime has a release-owned state-v4 lifecycle. It verifies signed
artifacts, exact release identity, capability v1, monotonic high-water/replay,
health, rollback, and AOT fallback without requiring a network. Productization
needs staged delivery, emergency controls, operational signals, and webhooks,
but telemetry can be missing, delayed, sampled, spoofed, or disabled for
privacy or air-gap reasons.

Treating a dashboard state or a “healthy” event as runtime authority would
couple correctness to connectivity and allow a compromised observation path to
activate code. Treating hardware or advertising identifiers as rollout keys
would also create unnecessary privacy and tenant-linkage risk.

## Decision

1. A rollout is a control-plane eligibility policy for one exact release,
   platform, environment, patch digest/sequence, or separately signed control.
   It can be `INTERNAL`, `CANARY`, `PERCENTAGE`, `COHORT`, `FULL`, `PAUSED`,
   or `EMERGENCY_STOP`.
2. Cohorts use a random app-scoped installation token and deterministic bucket
   assignment. No IMEI, advertising ID, hardware serial, phone number,
   account identity, or precise location is required. The token is separate
   from optional telemetry and may be represented server-side by a keyed
   digest.
3. Product rollout states (`DRAFT`, `READY`, `ACTIVE`, `PAUSED`, and others)
   never replace runtime states (`BASE`, `CANDIDATE`, `CURRENT`, `FAILED`). A
   server can pause/withhold delivery, but only the runtime can mark a
   candidate healthy.
4. Emergency stop is conservative: pause new offers, withhold/revoke a named
   artifact, or deliver an existing separately signed rollback-to-base
   control. A rollback to known-good behavior is a newly signed higher-sequence
   artifact; old bytes are never reopened. High-water is never lowered.
5. Runtime observations are optional. The bounded event set is
   `release_seen`, `patch_offered`, `patch_downloaded`, `patch_verified`,
   `patch_activated`, `patch_healthy`, `patch_rejected`, `runtime_fault`,
   `rollback_applied`, and `base_active`. Events are observations of local
   decisions, not commands or proof of fleet-wide state.
6. New deployments default optional observations off unless the application
   owner/operator opts in. Organizations can disable them, air-gapped systems
   can remain disconnected, and end-user privacy settings can override them.
   Sampling, bounded queues, aggregation, reason codes, short retention,
   deletion, and export are required design controls.
7. Webhooks are signed, timestamped, body-digested, and replay-deduplicated
   notifications. A receiver must re-fetch and authorize current state; a
   webhook cannot authorize a rollout, key change, or rollback.

## Alternatives considered

- **Mandatory telemetry for every runtime check:** Rejected because it breaks
  offline/self-hosted/air-gapped correctness and makes privacy opt-out
  impossible.
- **Device or advertising identifiers for cohorts:** Rejected because they
  are unnecessary for deterministic assignment and increase privacy and
  cross-context tracking risk.
- **Client-reported health as the rollback authority:** Rejected because
  events can be spoofed or absent. At most they recommend a delivery pause;
  signed runtime controls and local state remain authoritative.
- **Server push or an unauthenticated remote kill switch:** Rejected because a
  transport event must not bypass signature, exact release, capability, or
  high-water checks. Polling/fetch remains advisory and fail-safe.
- **Unsigned JSON rollback flag:** Rejected because only the existing separate
  signed rollback control can select base under the runtime contract.

## Consequences

Staged rollout and operational health are available without making a hosted
service a safety dependency. Dashboards must show sample size, sampling rate,
last observation time, offline gaps, and confidence rather than imply exact
installation truth. Pausing delivery may leave already active behavior in
place, so incident response must distinguish pause, artifact revocation,
signed rollback, and store-release-required.

The design requires privacy configuration, keyed cohort handling, event
deduplication, retention/deletion, and incident audit. It does not implement
any of those services or choose a telemetry vendor.

## Phase 1D boundary

Phase 1D validated local toolchain status and bounded runtime evidence, not a
remote telemetry channel. True power-loss testing, direct physical stale-byte
rejection, iOS runtime logs/UI and timings under the unavailable Developer
Disk Image, a fresh Android reducer series, independent customer-app
validation, and the additional async benchmark remain open. The adjacent
Flutter 3.47.1/Dart 3.13.1 path remains `SUPPORTED_WITH_LIMITATIONS`.
Telemetry must not be used to conceal these limitations or to convert fixture
evidence into production claims.

## References

- [Rollouts and privacy-preserving observability](../architecture/rollouts-observability.md)
- [Productization threat model](../security/productization-threat-model.md)
- [Artifact distribution and trust architecture](../architecture/distribution-trust.md)
- [Runtime state machine](../architecture/runtime-state-machine.md)
- [Phase 1D review](../history/reviews/PHASE_1D_REVIEW.md)
