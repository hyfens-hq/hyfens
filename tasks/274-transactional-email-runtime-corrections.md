# Task 274 — Transactional Email Runtime Corrections

Status: `[-] Blocked`

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
- Full control-plane package suite: failed in 27 unrelated credential/reconciliation/P3E tests, with 31 integration tests skipped because external PostgreSQL/S3/process harnesses were not configured; no failure was in the changed notification files.

## Next Action

Implement the smallest corrections, validate both branches, and re-run the managed acceptance that is possible without inventing provider evidence.

## Blockers

The real Task 273 callback used a provider `email_id` that did not match the `msg_...` identifier returned by the live send response. Official Keplars documentation found so far documents a nested `data.id` send response and `email_id` callback field, but no metadata echo or mapping mechanism. This remains a blocker until a supported live correlation mechanism is confirmed. The implementation deliberately leaves the delivery at `accepted` rather than guessing from recipient, subject, timestamp, or message order.

## Outcome

Code and focused acceptance are complete, but the required natural Keplars callback acceptance remains blocked by the unresolved provider identifier mapping. The dedicated reset journey is locally rendered and build-verified; managed mailbox/mobile acceptance remains external.

## References

- [Task 273 — Transactional Email Notifications](273-transactional-email-notifications.md)
- [Keplars webhook documentation](https://docs.keplars.com/docs/getting-started/webhooks)
- [Keplars send-email documentation](https://docs.keplars.com/docs/getting-started/send-emails)
- [Keplars status documentation](https://docs.keplars.com/docs/getting-started/send-emails)

## History

- 2026-09-09: Created as the scoped follow-up to the Task 273 runtime blocker and email UX findings.
- 2026-09-09: Added documented Keplars response-shape support, exact-ID-only callback tests, shared customer date formatting, reset route/CTA, responsive summaries, canonical email mark, and Cloud conflict resolution. Focused checks passed; full control-plane suite retained unrelated pre-existing failures. Verdict remains `BLOCKED` because a natural Keplars callback still cannot correlate to the live send response.
