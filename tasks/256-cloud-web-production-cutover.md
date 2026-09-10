# Task 256 — Cloud web production cutover and catalog synchronization

Status: [*] In Progress

## Goal

Deploy the current private Cloud web surfaces to their intended public
domains so the live marketing, pricing, policy, Cloud, and Platform Console
experiences match the repository and the approved product model.

## Scope and Non-goals

Scope — 256A public marketing/policy cutover:

- deploy the current Cloud marketing/CMS package to `hyfens.com`;
- deploy and verify the Platform Console route;
- publish the current Free/Starter/Team/Enterprise catalog, separate
  Self-hosted model, policy links, favicon, and `/pricing.md`; and
- validate DNS, TLS, health, cache, and rollback behavior.

Scope — 256B customer-workspace cutover, still pending:

- make the `app.hyfens.com` customer-workspace cutover decision and apply it
  only after Task 258 acceptance and explicit authorization.

Non-goals:

- another pricing redesign;
- changing backend plans, prices, or entitlements;
- deploying without the approved OpenShip/server release procedure; and
- changing the OSS self-hosted deployment contract.

## Owner

Codex

## Dependencies

- Tasks 248–254.
- `hyfens-cloud-web/deploy/web/` protected host configuration and deployment
  identity.
- Task 258 managed Flutter runtime acceptance and explicit authorization are
  required for 256B; they are not required for the safe 256A marketing
  deployment.

## Assumptions

- The current live `hyfens.com` still serves the older pricing model.
- The current live `app.hyfens.com` serves the OSS static dashboard target.
- The private Cloud repository is the source for current marketing/CMS and
  Platform Console content.

## Work Items

- [x] Stage and deploy the current Cloud web package through the fixed wrapper
  for 256A.
- [x] Verify `hyfens.com`, `platform.hyfens.com`, and policy routes over HTTPS.
- [x] Verify the live pricing model and `/pricing.md` against the repository.
- [x] Verify the live favicon and footer policy links.
- [ ] Decide and, if approved, perform the separate customer-workspace
  cutover for `app.hyfens.com` (256B; requires Task 258 and explicit
  authorization).
- [x] Capture desktop/mobile smoke evidence and a rollback plan for 256A.

## Validation

Completed for 256A:

- deployment wrapper preflight and health checks;
- live route, title, favicon, pricing, policy, and CTA checks;
- Cloud web typecheck, lint, and production build; and
- post-deploy desktop/mobile browser smoke review, including mobile menu,
  pricing plan selection, Self-hosted positioning, policy readability, and
  console-error checks.

Evidence:

- `npm run typecheck`, `npm run lint`, and production `next build` passed in
  `hyfens-cloud-web/site`;
- the fixed `hyfens-platform-deploy` wrapper completed successfully;
- HTTPS returned 200 for homepage, pricing, `/pricing.md`, Terms, Privacy,
  Refund Policy, favicon, and Platform Console;
- live content assertions matched Free/Starter/Team/Enterprise,
  Self-hosted, Flutter, and planned React Native messaging;
- the pre/post `app.hyfens.com` body hash was identical and the edge still
  routes it to `/var/www/hyfens/dashboard`; and
- a pre-deploy platform source snapshot was captured at
  `/tmp/hyfens-256a-backup.64NsY2/platform-web-before.tar.gz` for rollback.

256A production comparison:

| Surface | Repository | Production | Match |
| --- | --- | --- | --- |
| Homepage | Current | Current | yes |
| Pricing | Free / Starter / Team / Enterprise | Same | yes |
| `/pricing.md` | Current catalog | Current catalog | yes |
| Terms | Current route | HTTPS 200 | yes |
| Privacy | Current route | HTTPS 200 | yes |
| Refund Policy | Current route | HTTPS 200 | yes |
| Footer | Current policy links | Current policy links | yes |
| Self-hosted | Separate operating model | Separate operating model | yes |

Rollback was prepared with the pre-deploy platform source snapshot and the
existing protected wrapper; it was not exercised because post-deploy health
and content checks passed.

## Next Action

Complete 256B only after Task 258 managed Flutter acceptance and explicit
authorization. Until then, retain the current OSS customer target at
`app.hyfens.com`.

## Blockers

256A has no remaining blocker. 256B is intentionally pending Task 258 and
explicit customer-workspace cutover authorization. OpenShip reported no
connected cloud workspace during this run; the repository's fixed protected
SSH/server wrapper was available and used for the approved marketing target.

## Outcome

256A completed. The current private Cloud web package is live on `hyfens.com`
and `platform.hyfens.com`, including the approved Cloud pricing catalog,
separate Self-hosted positioning, `/pricing.md`, Terms, Privacy, Refund Policy,
footer links, and favicon. 256B remains pending; `app.hyfens.com` was not
replaced and remains on the OSS dashboard target until Task 258 acceptance and
explicit authorization.

## References

- `hyfens-cloud-web/deploy/web/README.md`
- `hyfens-cloud-web/deploy/web/hyfens-public-edge.conf`
- `hyfens-cloud-web/site/src/lib/pricing.ts`
- `hyfens-cloud-web/site/src/components/site-footer.tsx`
- `hyfens-cloud-web/site/src/app/pricing.md/route.ts`
- `hyfens-cloud-web/site/src/app/(marketing)/refund-policy/page.tsx`
- `hyfens-cloud-web/deploy/web/hyfens-platform-deploy`
- `tasks/254-cloud-commercial-launch-readiness-audit.md`

## History

- 2026-09-07: Created from the Task 254 P1 production-deployment finding.
- 2026-09-08: Completed 256A through the protected platform wrapper. Verified
  live marketing, pricing, policy, favicon, footer, mobile/desktop smoke, and
  cache behavior. Preserved `app.hyfens.com` on the OSS target; 256B remains
  pending Task 258 and explicit authorization.
