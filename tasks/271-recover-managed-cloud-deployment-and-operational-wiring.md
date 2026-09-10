# Task 271 — Recover Managed Cloud Deployment and Operational Wiring

Status: [-] Blocked — root-managed installation and protected operational
configuration remain external prerequisites

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
- [-] Validate protected configuration and document the exact root-level
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

The repository-owned wrappers and current source trees are corrected, validated,
and staged. The next action is for a root operator to install the staged
wrappers, install protected configuration through the deployment secret
mechanism, and run the no-secret preflight. Do not mutate production routing
or provider state until that preflight passes.

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
- the managed host still has the obsolete installed wrappers;
- protected Cloud/provider configuration is still missing from the running
  composition;
- no managed deployment, webhook delivery, email acceptance, backup restore,
  deletion worker, or provider/customer acceptance could be executed safely.

## Outcome

`NOT_READY`. Repository deployment recovery is complete and staged, but the
managed operational target cannot be replaced from this session because the
required root installation/protected-secret action is unavailable. Task 259
therefore remains `NOT_READY`; Task 256B remains `DO_NOT_CUT_OVER`.

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
