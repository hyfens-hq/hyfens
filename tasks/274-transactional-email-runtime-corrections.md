# Task 274 — Transactional Email Runtime Corrections

Status: `[x] Completed` — Hyfens-owned behavior verified; Keplars telemetry acceptance remains externally blocked

## Goal

Resolve the concrete findings from Task 273 managed notification acceptance: establish the supported Keplars callback-correlation contract, complete the password-reset customer journey, centralize customer-facing date formatting, improve responsive billing summaries, use the canonical Hyfens email mark, and keep internal provider probes separate from customer notifications.

## Scope and Non-goals

Scope is limited to the existing notification implementation and the dedicated Cloud password-reset route. This task does not introduce a second notification system, replace Keplars, alter billing authority, modify `main`, or change `app.hyfens.com`.

## Owner

Hyfens engineering

## Dependencies

- Control-plane branch: `codex/task-273-transactional-notifications`
- Cloud branch: `codex/task-273-billing-ui`
- Task 273 notification implementation and managed acceptance evidence
- Keplars provider documentation and the sanitized live response/callback evidence recorded in Task 273

## Assumptions

- Canonical timestamps are stored in UTC.
- No reliable customer/workspace timezone is currently available to the renderer; customer-facing fallback is therefore UTC and is stated consistently.
- Keplars callback correlation must use a provider-supported identifier or mapping, never recipient/subject/time heuristics.
- Razorpay TEST acceptance remains limited by the sandbox capability already recorded in Task 273.

## Work Items

- [x] Investigate the current Keplars send/callback identifier contract and document the provider blocker.
- [x] Add only provider-supported response-shape handling and exact correlation regression tests.
- [x] Add the dedicated password-reset route and connect the existing recovery-completion API.
- [x] Centralize customer-facing date, date-time, and expiry formatting across notification templates.
- [x] Make shared email summaries responsive for long values and use the canonical Hyfens brand asset.
- [x] Keep internal/provider schema probes explicitly outside customer notification semantics.
- [x] Resolve the Cloud PR conflict and run scoped plus required PR validation.
- [x] Append acceptance evidence and final verdict.

## Validation

- Control-plane notification/provider tests, formatting, analyzer, and relevant package tests.
- Cloud typecheck, lint, and production build.
- Password reset route/API tests and notification render tests.
- Exact documented Keplars response/callback-shape tests, without heuristic correlation.
- `git diff --check` and branch/PR review.
- Focused control-plane notification tests: passed (20 tests).
- Cloud `typecheck:web`, `lint:web`, and `build:web`: passed.
- Cloud provider-package boundary tests: passed (9 tests) after moving the
  legacy commercial orchestration behind an explicit compatibility module and
  preserving the shared provider-package boundary.
- Full control-plane package suite: failed in 27 unrelated credential/reconciliation/P3E tests, with 31 integration tests skipped because external PostgreSQL/S3/process harnesses were not configured; no failure was in the changed notification files.

## Next Action

Wait for Keplars to provide a supported send-response/webhook identifier mapping, then run a small provider-integration follow-up. Do not add a Hyfens heuristic workaround.

## Blockers

`KEPLARS_CALLBACK_CORRELATION_EXTERNAL_BLOCKER`

The live send API returns/stores a `msg_...` identifier while the natural
callback reports a different `email_id`. The documented status lookup using
the `msg_...` value does not resolve it, and no supported metadata echo or
identifier mapping mechanism has been identified. A synthetic callback with a
known Hyfens identifier proves callback processing works; real callback
signature verification works; and the actual email reaches the mailbox.
Natural delivery-state correlation remains externally blocked while Keplars
investigates. This is not classified as a Hyfens application defect.

Hyfens preserves exact-ID correlation. A valid unmatched callback is safely
ignored for business state and recorded as a sanitized
`notification.provider_callback_unmatched` audit event. Provider acceptance
remains `accepted`; it is never promoted to `delivered` without correlated
provider evidence.

## Outcome

Application: `CODE_VERIFIED`

Customer flow: `CUSTOMER_FLOW_VERIFIED` for the Hyfens-owned auth and
notification paths covered by focused tests and the previously recorded
approved-mailbox acceptance. The dedicated reset route, one-time token
consumption, session revocation, password-changed notification seam, and
human-readable responsive rendering are verified. A live mobile-client
mailbox inspection was not available in this local session.

Provider telemetry: `PROVIDER_TELEMETRY_EXTERNAL_BLOCKED`

Razorpay runtime: `RAZORPAY_TEST_ENVIRONMENT_BLOCKED` (unchanged from Task
273; no new provider evidence was fabricated).

Customer email delivery does not depend on a `delivered` callback. Billing,
account, and security operations use authoritative Hyfens state and can send
while a provider delivery remains `accepted`.

## References

- [Task 273 — Transactional Email Notifications](273-transactional-email-notifications.md)
- [Keplars webhook documentation](https://docs.keplars.com/docs/getting-started/webhooks)
- [Keplars send-email documentation](https://docs.keplars.com/docs/getting-started/send-emails)
- [Keplars status documentation](https://docs.keplars.com/docs/getting-started/send-emails)

## History

- 2026-09-09: Created as the scoped follow-up to the Task 273 runtime blocker and email UX findings.
- 2026-09-09: Added documented Keplars response-shape support, exact-ID-only callback tests, shared customer date formatting, reset route/CTA, responsive summaries, canonical email mark, and Cloud conflict resolution. Focused checks passed; full control-plane suite retained unrelated pre-existing failures. Verdict remains `BLOCKED` because a natural Keplars callback still cannot correlate to the live send response.
- 2026-09-09: Final Cloud merge correction committed as `b255aae`; current `apps/web` topology, provider boundary, typecheck, lint, build, and provider tests are clean. Both PRs remain open and unmerged. Natural Keplars callback correlation is still the acceptance blocker.
- 2026-09-10: Keplars confirmed as an external investigation path. Added sanitized audit evidence for valid unmatched callbacks without changing exact-ID behavior or promoting `accepted` to `delivered`; corrected the legacy direct recovery delivery to use the dedicated reset route and hash one-time tokens in provider idempotency keys. Focused notification, onboarding/recovery, deletion, formatting, and Cloud validation remain clean. Merge recommendation is `READY_WITH_DOCUMENTED_EXTERNAL_ACCEPTANCE` while the provider correlation blocker remains open.
- 2026-09-10: Control correction committed as `d67776f` in PR [hyfens#3](https://github.com/hyfens-hq/hyfens/pull/3); Cloud recovery/UI correction committed as `2e14e77` in PR [hyfens-cloud-web#3](https://github.com/hyfens-hq/hyfens-cloud-web/pull/3). Both PRs are open, clean, mergeable, and unmerged.
