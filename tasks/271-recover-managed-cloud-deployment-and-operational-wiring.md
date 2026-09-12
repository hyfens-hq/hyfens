# Task 271 — Recover Managed Cloud Deployment and Operational Wiring

Status: [-] Blocked — backup/restore, operational ownership, and policy gates
remain unresolved

## Goal

Restore a reproducible deployment path for the current Hyfens Cloud web and
control-plane source layouts, while keeping protected configuration,
health-gated replacement, rollback, and the app.hyfens.com cutover boundary
safe.

## Scope and Non-goals

Scope:

- reconcile repository paths, deployment manifests, and installed host
  wrappers;
- harden the existing web and control-plane deployment wrappers;
- validate current-source Docker/Compose builds before service replacement;
- retain a durable previous release and an explicit rollback path;
- document protected configuration, email, backup, policy, and managed
  acceptance prerequisites; and
- run the strongest safe local, remote, and managed checks available.

Non-goals:

- changing Cloud billing, runtime, rollback, plan, pricing, or entitlement
  architecture;
- changing app.hyfens.com, production DNS, or live Razorpay state;
- inventing a second email, backup, queue, or deployment platform; and
- claiming managed customer acceptance without real managed evidence.

## Owner

Codex

## Dependencies

- Tasks 255–270.
- Current private Cloud web repository and control-plane repository.
- Root-managed deployment access on the managed host.
- Protected provider, email, backup, legal, and accounting configuration.

## Assumptions

- The current private web source is under the sibling repository site/
  directory.
- The current control-plane source is under packages/control_plane with
  deploy/p2 manifests in this repository.
- The existing managed host still has the older P2-R2 deployment as a
  rollback/fallback target.
- Protected files remain root:root with mode 0600.

## Work Items

- [x] Audit current repository topology against installed host wrappers.
- [x] Fix the existing web deployment wrapper for current-source,
  build-before-replace, health-gated deployment, and rollback.
- [x] Fix the existing control-plane deployment wrapper for current-source,
  build-before-replace, health-gated deployment, and rollback.
- [x] Validate protected configuration and document the exact root-level
  installation action without exposing secrets.
- [-] Wire or verify production email, deletion worker, backup/restore,
  webhook, policy routes, and operational ownership.
- [-] Run managed disposable acceptance where all external prerequisites are
  available.
- [x] Reconcile Task 259 and produce the final launch recommendation.

## Validation

Planned:

- shell syntax and static wrapper checks;
- current Compose interpolation and Docker build checks;
- Cloud web typecheck, lint, and production build;
- control-plane analyzer and focused tests;
- protected deployment health/readiness and rollback checks;
- email, backup/restore, webhook, deletion, and provider acceptance checks
  where external configuration permits; and
- git diff --check.

Completed in this task:

- current control-plane Docker build with all local path dependencies;
- current Cloud-web Docker build and route generation;
- control/web Compose interpolation;
- local disposable Cloud-web route smoke;
- control-plane lifecycle-focused tests (63 passed);
- web typecheck, lint, and production build;
- browser-bundle server-secret scan;
- local and staged-wrapper shell syntax; and
- tracked diff checks.

The complete control-plane package test command was also run. It reported 27
pre-existing failures in observation/P3E/reconciliation/credential-issuer
coverage and 34 environment-dependent skips; the Task-271-relevant billing,
refund, Enterprise, deletion, plan, onboarding, artifact, auth, and config
slice passed independently.

## Next Action

Complete the remaining managed acceptance and operations gates: Enterprise TEST
payment, personal-account deletion, managed backup/restore with deletion
resurrection protection, role-based ownership, and legal/tax/evidence-retention
decisions. Keep `app.hyfens.com` and Razorpay LIVE outside this task.

## Blockers

Initial blockers carried from Task 259:

- installed host wrappers target obsolete source layouts;
- this session cannot install root-owned wrappers or protected environment
  values through the available fixed sudo rules;
- current managed control-plane and web provider/email configuration is not
  deployed;
- production email transport, backup/restore ownership, policy publication,
  tax decisions, and named operational owners remain external.

Task-271-specific status:

- current source Docker builds and repository wrappers are no longer blocked;
- root-authorized wrappers and protected Cloud/provider configuration are
  installed; the current composition is healthy and its rollback path was
  exercised;
- policy routes, TEST billing/bridge flows, and the bounded deletion worker
  deployment have managed evidence;
- managed backup/restore and deletion-resurrection protection are not proven,
  and Enterprise payment, complete personal deletion, and role-based failure
  ownership remain open.

## Outcome

`NOT_READY`. Repository deployment recovery and root-authorized installation are
complete, but backup/restore, deletion-resurrection protection, operational
ownership, Enterprise acceptance, and policy gates remain incomplete. Task 259
remains `NOT_READY`; Task 256B remains `DO_NOT_CUT_OVER`.

## References

- sibling hyfens-cloud-web/deploy/web/hyfens-platform-deploy
- sibling hyfens-cloud-web/deploy/web/site/compose.yaml
- deploy/p2/hyfens-public-control-plane-dev-deploy
- deploy/p2/docker-compose.public-control-plane-dev.yml
- docs/operations/cloud-launch-operations.md
- tasks/259-cloud-launch-operations-and-policy-gates.md

## History

- 2026-09-09: Reserved for deployment recovery and operational wiring after
  Task 259 reported NOT_READY.
- 2026-09-09: Corrected current source paths and local control-plane Docker
dependencies; hardened and staged both health-gated wrappers; repository
and lifecycle-focused validation passed. Managed installation remains
blocked on root-owned wrapper/protected configuration access.
- 2026-09-12: Root-authorized installation completed. The current wrappers,
  protected TEST configuration, health/readiness checks, live route smoke,
  provider bridge, and rollback rehearsal passed. The task remains blocked only
  by the separately identified backup/restore, resurrection, ownership,
  Enterprise, and legal/policy acceptance gates.
