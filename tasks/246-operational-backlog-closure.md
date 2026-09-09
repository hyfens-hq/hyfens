# Operational dashboard backlog closure

Status: [x] Completed

## Goal

Close the highest-value remaining operational gaps in the already-separated
Customer Workspace and Platform Console. Preserve tenant isolation, explicit
platform authorization, real-data-only reporting, and the existing
Organization → Application → Environment domain model.

## Scope and Non-goals

Scope:

- Complete the customer invitation lifecycle, including safe redemption,
  expiry/revocation state, delivery seam, role mutation, and explicit owner
  transfer.
- Preserve and verify the existing application/environment update/archive,
  credential, support, promotion, and customer audit operations.
- Add bounded platform staff administration and session revocation without
  mixing staff with customer members.
- Add a platform MFA enforcement seam that fails closed when enabled while
  leaving provider/enrollment UX explicit if it is not supported by the
  current authentication stack.
- Extend operational projections only with authoritative bounded data; keep
  billing history/revenue unavailable when the current records do not contain
  monetary events.
- Preserve explicit support inspection and internal-note isolation; do not add
  unrestricted impersonation.
- Update current product/architecture documentation and run one browser
  availability/visual check.
- Commit and push the bounded implementation to `origin/main`.

Non-goals:

- No merge of the Customer Workspace and Platform Console.
- No second Project domain; developer-facing “project” remains an Application.
- No enterprise SSO/SCIM, advanced analytics, billing-provider integration,
  notification platform, silent impersonation, or broad infrastructure work.
- No unsafe browser rollback; retain an honest CLI handoff when the existing
  backend contract cannot safely expose rollback.
- No release tag, DNS change, production deployment, or changes to the
  separate `backend` or `frontend` repositories.
- No Task 210, microtasks, or unrelated historical-suite cleanup.

## Owner

Coordinator — domain/API integration, authorization review, dashboard/docs
integration, validation, and public repository handoff.

## Dependencies

- Public `origin/main` at `853fbb87bcc23c86093b66dd08e6a0a8ac231833`.
- Existing separated dashboard and operational MVP contracts from task 245.
- Existing human authentication/session, generic persistence, audit, billing,
  support, and platform projection modules.
- The original development checkout remains unrelated and untouched.

## Assumptions

- Customer mutations remain tenant-scoped and server-authoritative.
- Platform staff membership and capabilities are the authority for Platform
  Console access; customer memberships are never used as a platform directory.
- Invitation delivery has no configured provider in the current repository, so
  the implementation will provide a provider seam and a safe local/admin
  retrieval path rather than logging bearer tokens.
- Existing billing records contain plan/subscription amounts but no complete
  payment/invoice/refund ledger; revenue history will be reported honestly as
  unavailable unless inspection proves otherwise.
- Browser visual acceptance may remain an external environment gate if no
  browser connector is available.

## Current-state READ/CREATE/UPDATE/ARCHIVE/ACTION/MISSING matrix

| Area | READ | CREATE | UPDATE | ARCHIVE | ACTION | Missing/remaining |
| --- | --- | --- | --- | --- | --- | --- |
| Customer applications | yes | yes | yes | yes | no | lifecycle regression only |
| Customer environments | yes | yes | yes | yes | promotion | lifecycle regression only |
| Customer members | yes | invitation foundation | role update | remove/deactivate | no | delivery, redemption, owner transfer |
| Customer credentials | yes (metadata) | issue | no | revoke | revoke | no plaintext re-read |
| Customer delivery | yes | records | no | no | promote | browser rollback safety decision |
| Customer support | yes | case/reply | status via staff | close | reply | no silent impersonation |
| Platform organizations | yes | no | no | no | inspect | existing bounded projection |
| Platform staff | yes | no | no | no | no | staff lifecycle/role/session actions |
| Platform commercial | projection | no | no | no | no | monetary history source unavailable unless proven |
| Platform operations | metrics foundation | no | no | no | inspect | bounded real telemetry expansion |
| Platform support | queue/detail | case/reply | assignment/status | close | internal note | explicit access model documentation |
| MFA | session auth | no | no | no | no | privileged enforcement seam |

## Work Items

- [x] Inspect current contracts and freeze the bounded implementation matrix.
- [x] Complete customer invitation redemption/delivery seam and ownership
  transfer with audit and negative authorization coverage.
- [x] Complete platform staff lifecycle/capability/session administration and
  the privileged MFA enforcement seam.
- [x] Add bounded operational/commercial history projections only where the
  source data is authoritative; document unavailable monetary history.
- [x] Regress existing customer/platform support, lifecycle, credential,
  promotion, and tenant/audience authorization paths.
- [x] Integrate only necessary dashboard forms/views and update authoritative
  documentation.
- [x] Run focused validation, one browser availability check, review the
  combined diff, commit, and push `origin/main`.

## Validation

Planned:

- `dart format --output=none --set-exit-if-changed` on changed Dart files.
- `dart analyze` and focused control-plane tests for invitations, ownership,
  staff capabilities, MFA/session revocation, operations, and support.
- Dashboard JavaScript syntax, Python proxy tests, and focused UI contract
  checks.
- Markdown local-link validation, focused secret scan, and `git diff --check`.
- Browser visual acceptance once, or factual external-environment status.
- Full required validation before commit/push if repository policy requires it;
  unrelated historical reconciliation/P3E failures remain out of scope.

## Next Action

No further action in this bounded milestone. Release tagging, DNS changes,
production deployment, and the explicitly listed backlog remain separate work.

## Blockers

None currently.

## Outcome

Implemented the bounded operational backlog in the isolated public clone.
Customer invitations now have provider-independent delivery, safe preview and
redemption, expiry/revocation, capability-bounded role mutation, and audited
atomic ownership transfer. Application/environment lifecycle, credentials,
support, promotion, and customer audit paths were preserved and regressed.

Platform staff now use explicit `platform_system` memberships and bounded role
capabilities for listing, invitation, role/active-state administration, and
session revocation. Privileged MFA enforcement is available through
`HYFENS_PLATFORM_MFA_REQUIRED`; enrollment, recovery, and an external MFA
provider remain an explicit integration gate. Operations projections report
real bounded durable-record signals and `UNKNOWN` when external probes are not
configured. Commercial projections calculate recurring MRR/ARR only from the
existing authoritative plan records; monetary billing history is explicitly
reported as unavailable because no invoice/payment/refund ledger exists.

Browser rollback remains a CLI handoff because the current backend does not
expose a safe browser target/high-water rollback operation. Silent support
impersonation was not added. The browser connector was checked once and was
unavailable, so visual acceptance remains an external-environment gate.

Validation passed for changed Dart formatting, analysis, the focused
operational/control-plane closure suite (17 tests), dashboard JavaScript
syntax, dashboard proxy tests (35 tests), local Markdown links (99 checked,
zero broken), focused secret scan, and `git diff --check`. Secret-producing
credential/invitation retries are covered by the HTTP suite and fail closed
without replaying plaintext. The historical P3E applicability test was
reproduced against the pre-change commit with the same 11
credential-expiry/security fixture failures and remains pre-existing backlog;
four Postgres cases were skipped because `HYFENS_TEST_POSTGRES_URL` is not
configured.

## References

- `tasks/245-operational-dashboards-customer-management.md`
- `docs/architecture/dashboard-separation.md`
- `docs/product/customer-workspace.md`
- `docs/product/platform-console.md`
- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/service.dart`
- `packages/control_plane/lib/src/http.dart`
- `dashboard/app.js`

## History

- 2026-09-03 — Reserved task 246 from a fresh public clone at
  `853fbb87bcc23c86093b66dd08e6a0a8ac231833`. Confirmed the prior operational
  MVP foundations and recorded the bounded remaining gaps above. No changes
  were made to the original development checkout or the separate repositories.
- 2026-09-03 — Implemented the bounded customer/platform operational closure,
  added focused regression coverage, updated authoritative product and
  architecture docs, and completed the final validation pass. Browser visual
  acceptance was externally gated because no browser connector was available.
- 2026-09-03 — Committed and pushed the bounded implementation to
  `origin/main` as `d402031` (`feat(platform): close operational dashboard
  backlog`). No release tag, DNS change, production deployment, or protected
  repository operation was performed.
