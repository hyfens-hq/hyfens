# Task 285 — External recovery acceptance

Status: [*] In Progress

## Goal

Turn the completed managed recovery rehearsal and first-party Cloudflare R2
evidence into an explicit external acceptance packet for durability,
encryption/key custody, data location, retention, and RPO/RTO. Keep the launch
gate fail-closed until the accountable owners approve the remaining choices.

## Scope and Non-goals

Scope:

- capture the current Cloudflare R2 durability, availability, encryption,
  jurisdiction, lock, lifecycle, and access-control facts;
- distinguish technical evidence from provider-contract and legal approval;
- record an evidence-based RPO/RTO decision procedure and owner checklist; and
- update the launch matrix so it reflects the passed managed recovery proof.

Non-goals:

- no Cloudflare dashboard or bucket mutation;
- no credential, key, or customer-data change;
- no selection of a statutory retention period, RPO, RTO, jurisdiction, or
  customer-facing legal wording;
- no client-side encryption implementation or paid-plan upgrade; and
- no claim that provider durability, failover, or legal acceptance is proven by
  the disposable rehearsal.

## Owner

Platform operations, with security, privacy/legal, finance, and product owners
for their respective acceptance decisions.

## Dependencies

- Task 284 managed recovery rehearsal and its sanitized evidence.
- Existing public managed backup wrapper, timers, and protected host
  configuration.
- Cloudflare R2 first-party documentation and the account's actual bucket
  configuration.
- Named operational, security, privacy/legal, and finance approvers.

## Assumptions

- The current managed destination remains the approved Cloudflare R2 bucket
  pair (`hyfens-dev` source to `hyfens-cloud-backups` destination), and
  credentials stay outside the repository.
- The R2 destination is currently protected by the existing policy controls,
  and the sanitized managed-host preflight passes; its jurisdiction, contract
  eligibility, same-account isolation decision, and key-custody posture have
  not yet been recorded as launch evidence.
- A technical recovery rehearsal is directional evidence for the Hyfens
  procedure, not a provider SLA or statutory compliance certificate.

## Work Items

- [x] Research and record first-party R2 facts and their Hyfens implications.
- [x] Update the launch matrix with the completed technical recovery evidence
  and the remaining external gates.
- [x] Confirm the live source/destination bucket wiring through sanitized host
  preflight and read-only Cloudflare dashboard inspection.
- [x] Review the task-owned diff for unsupported guarantees, secret material,
  and stale acceptance language.
- [x] Run scoped documentation validation and record the outcome.
- [ ] Obtain owner decisions or record the exact external evidence still
  required before launch closure.

## Validation

Completed:

- `git diff --check` passed.
- targeted secret-pattern scan over the task-owned documentation returned no
  matches.
- direct review found no unsupported provider/legal guarantees and no stale
  technical-recovery statement in the changed scope.
- referenced repository files exist and the first-party source links are
  recorded.
- sanitized managed-host preflight passed for source/destination bucket scope;
  redacted host inspection confirmed `hyfens-dev` to `hyfens-cloud-backups`.
- read-only Cloudflare dashboard inspection confirmed the destination's
  30-day lifecycle/lock and same-account APAC/default placement; no provider
  setting was changed.

Not run: application/runtime tests, because this package changes only
documentation and task tracking.

## Next Action

Hand the owner decision checklist to the maintainer/security/legal/accounting
owners, then attach the resulting provider configuration and approvals to the
launch record.

## Blockers

The provider-account configuration, same-account isolation choice,
contract/plan eligibility, jurisdiction, key-custody requirement, approved
RPO/RTO, and legal/tax/privacy retention decisions are external inputs and
cannot be closed by repository code alone.

## Outcome

The first-party R2 facts, technical-versus-external boundary, RPO/RTO method,
and current launch-matrix state are recorded. Provider/account configuration,
same-account isolation decision, security key-custody choice, approved RPO/RTO,
and legal/privacy/accounting acceptance remain open. The suspected same-bucket
wiring issue is closed: the sanitized host configuration and preflight show
`hyfens-dev` to `hyfens-cloud-backups`.

## References

- `tasks/284-managed-public-recovery-rehearsal.md`
- `docs/operations/cloud-launch-gate-matrix.md`
- `docs/operations/p2-production-readiness-runbook.md`
- `docs/operations/r2-recovery-acceptance-research.md`
- [Cloudflare R2 data security](https://developers.cloudflare.com/r2/reference/data-security/)
- [Cloudflare R2 durability](https://developers.cloudflare.com/r2/reference/durability/)
- [Cloudflare R2 service level agreement](https://www.cloudflare.com/r2-service-level-agreement/)
- [Cloudflare R2 data location](https://developers.cloudflare.com/r2/reference/data-location/)
- [Cloudflare R2 bucket locks](https://developers.cloudflare.com/r2/buckets/bucket-locks/)
- [Cloudflare R2 SSE-C](https://developers.cloudflare.com/r2/examples/ssec/)

## History

- 2026-09-18: Reserved as the next external recovery-acceptance package after
  Task 284 closed the technical managed restore and tombstone rehearsal.
- 2026-09-18: Added first-party R2 facts, an explicit RPO/RTO acceptance method,
  and the external owner checklist; reconciled the launch matrix with the
  passed managed restore/tombstone evidence.
- 2026-09-18: Completed the documentation review and scoped validation; the
  remaining work is external owner/provider acceptance.
- 2026-09-18: Read-only Cloudflare inspection and sanitized host preflight
  confirmed distinct source/destination buckets, the destination's 30-day
  lifecycle/lock, and same-account APAC/default placement; no provider setting
  was changed.
- 2026-09-18: Opened public review PR #25.
