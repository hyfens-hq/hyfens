# Task 253 — Authoritative Cloud artifact delivery accounting

Status: [x] Completed

## Goal

Make Cloud artifact delivery accounting explicit across current and future
trusted delivery sources. Preserve origin-byte measurement, distinguish
partial coverage from a complete delivery total, support exact origin range
responses, and establish an artifact-attributed ingestion seam without adding
quotas or billing.

## Scope and Non-goals

Scope:

- inventory the current origin, proxy, object-store, CDN, and edge paths;
- define canonical artifact delivery evidence and source authority;
- preserve durable, idempotent origin accounting and late event timestamps;
- add trusted artifact-anchored ingestion for future delivery adapters;
- expose delivery authority and coverage in the Cloud billing projection;
- prevent delivery observations from trusting caller-supplied organization IDs;
- keep self-hosted outside Cloud commercial accounting; and
- document double-count prevention and reconciliation limits.

Non-goals:

- changing Cloud prices or application/environment/member boundaries;
- introducing bandwidth quotas, overages, invoices, or settlement;
- deploying a CDN, edge, or direct object-store delivery path;
- implementing patch-install or active-device metering; and
- changing the artifact lifecycle or plan-retention policy.

## Owner

Codex

## Dependencies

- Task 250 Cloud usage metering.
- Task 252 artifact lifecycle and retention semantics.
- Existing authenticated artifact delivery endpoint and object-store adapters.
- Cloud billing usage projection and workspace.

## Assumptions

- The only implemented customer-facing delivery path is the control-plane
  origin endpoint `GET /v1/runtime/artifacts/{artifact}`.
- S3-compatible storage is currently an internal artifact-store adapter; no
  signed direct object URL is issued by the control plane.
- The current origin cannot prove exact client socket egress after an
  interrupted response, so that limitation remains visible in authority
  metadata rather than being presented as a complete commercial total.
- Artifact ownership is resolved from server-side artifact metadata.

## Work Items

- [x] Inventory and classify every current delivery path.
- [x] Add explicit delivery authority, coverage, and quota-readiness metadata.
- [x] Add a trusted artifact-attributed delivery observation contract.
- [x] Preserve idempotent source identity and event-time period assignment.
- [x] Add exact single-range origin response accounting.
- [x] Update Cloud API parsing and billing UI wording for partial measurement.
- [x] Document source precedence, double-count prevention, and reconciliation
  limitations.
- [x] Add focused metering, HTTP/range, trust-boundary, and Cloud checks.
- [x] Run the consolidated affected validation batch and review the diff.

## Validation

Completed:

- `dart format` and `dart analyze .` for the changed control-plane code;
- focused usage-metering, HTTP/range, Cloud plan, HTTP, lifecycle, closure,
  release-bundle, S3, reconciliation, and policy-content tests (54 tests
  passed);
- Cloud `npm run typecheck`, `npm run lint`, and `npm run build` for the API/UI
  contract changes; and
- `git diff --check` in both repositories.

## Next Action

Use the measured evidence only after a future delivery-edge integration makes
the configured customer-facing delivery surface complete. Do not activate
bandwidth quotas, overages, or settlement from the current partial meter.

## Blockers

None known. CDN/object-store log ingestion, interrupted-socket byte evidence,
commercial bandwidth quotas, overages, and settlement remain deferred.

## Outcome

Implemented. The control plane now exposes an explicit `authoritative`,
`partial`, or `unavailable` delivery authority state with covered and
uncovered source lists and a quota-eligibility guard. Current origin delivery
remains durably counted with artifact-derived organization ownership,
occurrence-time period assignment, and idempotent source identities. The HTTP
artifact endpoint supports one range response and accounts only the selected
bytes; invalid ranges produce no delivery fact. A trusted, artifact-anchored
observation seam is available for future CDN/object-store/edge adapters without
accepting caller-supplied organization IDs.

Cloud billing retains compatibility fields but now distinguishes measured
origin delivery from a complete customer-bandwidth total. The Cloud workspace
uses precise partial-coverage wording and does not show quotas or progress
bars. Documentation records the current origin-only inventory, client-egress
boundary, source precedence, double-count rule, late events, and delivery
reconciliation limitations. Self-hosted remains outside Cloud commercial
accounting.

No CDN, direct object-store delivery, bandwidth quota, overage, billing
settlement, patch-install meter, or pricing change was added.

## References

- `tasks/250-cloud-usage-metering-follow-up.md`
- `tasks/252-cloud-artifact-lifecycle-retention.md`
- `docs/architecture/cloud-usage-metering.md`
- `docs/architecture/cloud-delivery-accounting.md`
- `docs/architecture/cloud-artifact-lifecycle.md`
- `packages/control_plane/test/artifact_delivery_http_test.dart`
- Linked Cloud web package: `hyfens-cloud-web/tasks/09-delivery-meter-authority.md`

## History

- 2026-09-07: Created after mapping the repository’s current origin-only
  delivery path and identifying the need for explicit partial-authority state.
- 2026-09-07: Implemented authority-aware delivery evidence, trusted artifact
  attribution, single-range origin accounting, Cloud API/UI coverage metadata,
  documentation, and focused validation. CDN/object-store ingestion and
  commercial bandwidth policy remain deferred.
