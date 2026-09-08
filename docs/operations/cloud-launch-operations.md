# Cloud launch operations

Status: NOT READY — Task 271 deployment recovery, 2026-09-09

This document records the operational boundary for the managed Cloud launch.
It does not authorize `app.hyfens.com` customer-workspace cutover, Razorpay
LIVE activation, production payment, or a change to Cloud pricing/limits.

## Task 271 deployment recovery

The current source boundaries are explicit:

```text
control plane: this repository/packages/control_plane
control-plane deployment: this repository/deploy/p2
control-plane path dependencies: packages/patch_format, packages/runtime,
                                experiments/instrumentation,
                                experiments/patch_loading
private Cloud web: sibling hyfens-cloud-web/site
private-web deployment: sibling hyfens-cloud-web/deploy/web
```

The repository-owned wrappers now build the current source in an isolated
directory before replacing a live target. They validate protected
configuration, Compose, safe file trees, readiness, and the Nginx boundary;
they retain a previous image/release and support `--rollback`. The control
plane previously failed at `dart pub get` because the build context omitted
its local path dependencies; the corrected context now builds successfully.

The reviewed inputs are staged under
`/home/hyfen/p2-deploy-stage/` on the managed host. The installed host
wrappers are still obsolete, and this session has only password-gated sudo;
it cannot install root-owned wrappers or protected environments. A root
operator must run the staged one-time installers:

```sh
sudo /home/hyfen/p2-deploy-stage/platform/install-platform-deploy-access.sh
sudo /home/hyfen/p2-deploy-stage/deploy/p2/install-public-control-plane-dev-deploy-access.sh
```

Protected environments must then be installed through the existing
deployment-owned secret path. A repository `.env`, live-container edit, or
provider/DNS mutation is not an acceptable substitute.

## Launch policy decisions

- Account verification and password recovery are required for public Cloud
  onboarding. Account-deletion verification is a separate, purpose-bound
  email flow.
- Managed Cloud deletion uses a seven-day grace period as the launch default,
  configured as `HYFENS_DELETION_GRACE_PERIOD=7d`. This is a product default,
  not a legal retention conclusion; legal/privacy review must approve the
  customer-facing wording before public launch.
- Cancellation stops renewal at the paid-cycle boundary and retains data.
  Ordinary cancellation/downgrade creates no refund.
- Refunds remain a separate reviewed Razorpay workflow.
- Financial, security/audit, Enterprise-commercial, and backup retention
  durations remain policy-controlled and are not invented here.

## Current evidence

| Boundary | Evidence | Status |
| --- | --- | --- |
| Current control-plane image | `docker build --tag hyfens-public-control-plane:task271 --file deploy/p2/Dockerfile .` passes with the complete local path-dependency graph | CODE VERIFIED |
| Current Cloud web image | Sibling `site/` image build passes and generates all 38 current Next routes, including billing, deletion, pricing, and refund routes | CODE VERIFIED |
| Deployment inputs | Current wrappers and required source trees are staged; installed wrappers still target obsolete layouts | BLOCKED ON ROOT INSTALL |
| Private web build | `npm run typecheck`, `npm run lint`, and `npm run build` pass in the current private-web checkout | CODE VERIFIED |
| Control plane | `/healthz` and `/readyz` on `api.hyfens.com` returned 200 | MANAGED LIVENESS ONLY |
| TLS/DNS | `hyfens.com`, `api.hyfens.com`, and `app.hyfens.com` resolve to the managed host; the certificate covers the required hostnames through 2026-12-02 | VERIFIED |
| Razorpay plans | Task 263 verified TEST USD Starter/Team plans at 4900/19900 minor units | PROVIDER VERIFIED, DEPLOYMENT NOT INSTALLED |
| Private-web billing | Running container has empty Razorpay key/secret, webhook secret, billing bridge, and public billing currency settings; current values are not installed | BLOCKED |
| Control-plane billing | Running `hyfens-p2-r2` control plane has no Cloud billing/provider environment and is not the current managed Cloud composition | BLOCKED |
| Webhook route | `https://hyfens.com/api/billing/webhook` returns 405 to GET, proving method routing only; no signed delivery was accepted | NOT VERIFIED |
| Production policy routes | Latest check: `/terms` 200, `/privacy` 200, `/pricing` 200, `/refund-policy` 404, `/pricing.md` 404, `/account-deletion` 404 | BLOCKED |
| Production API pricing | `/api/pricing` returned 503 `pricing_unavailable` | BLOCKED |
| Production email | SMTP variable names are present on the old web container, but the shipped control-plane binary injects no `HumanAuthMessageDelivery` or `HumanDeletionMessageDelivery` implementation | BLOCKED |
| Enterprise delivery | Durable `enterprise_inquiries` inbox and operator workspace exist; no production notification/ownership evidence | PARTIAL |
| Backup/restore | Local rehearsal is verified; live backup schedule, off-host durability, retention, restore ownership, and deletion/tombstone reconciliation are not verified | BLOCKED |

The existing private-web deployment was attempted through
`/usr/local/sbin/hyfens-platform-deploy`. It failed before replacing the
running container: the installed root wrapper expects the older
`apps/web`/provider staging layout, while the current source uses `site/`, and
its Docker dependency stage did not produce `/app/node_modules`. The failed
build did not change the live image or routes.

Task 271 corrected the repository-owned wrappers and staged them for the root
installation path. No managed replacement, restart, rollback, protected
configuration install, or live policy deployment was performed in this task.

## Email boundary

The control plane owns secure token generation and persistence through the
injected delivery interfaces. The current executable does not construct a
production transport, configure a sender/link base, or provide retry,
delivery, bounce, or complaint evidence. Therefore the following cannot be
called operational from this host:

- signup verification;
- password recovery;
- deletion verification;
- Enterprise inquiry notification.

The next operator action is to select and configure one approved transactional
email transport through the existing delivery seam, then perform mailbox
acceptance for verification, recovery, and deletion. Enterprise notification
must have a verified owned destination; the durable operator inbox remains the
source of truth and no CRM integration is required.

## Retention and backups

The implemented deletion taxonomy is:

| Data | Treatment |
| --- | --- |
| Profiles, email, credentials, sessions, memberships, applications, environments, usage events, and customer operational content | Erase through staged deletion after the grace boundary |
| Verification/recovery/deletion tokens, artifact bytes, and backups | Temporary retain until expiry, reference-safe cleanup, or backup rotation |
| Release/patch security metadata and deployment/rollback evidence | Anonymize while preserving required verification evidence |
| Audit chain, billing/refund evidence, Enterprise commercial evidence, and security/abuse events | Retain in minimized form as required for security, reconciliation, accounting, dispute, or legal purposes |

The repository's AWS disposable template has seven-day RDS/AWS Backup
retention, thirty-day noncurrent S3-version expiration, and three-day
incomplete-multipart cleanup. Those are disposable-template values, not live
production evidence. The checked host exposes only the system package backup
timer; no managed Cloud customer backup schedule or restore acceptance was
verified. Before public paid launch, the operator must record the real backup
frequency, encryption, destination, rotation, restore owner, RPO/RTO, and how
deletion tombstones prevent a restore from resurrecting a deleted tenant.

## No-secret preflight

Run this only through the protected deployment mechanism; never print values:

```text
Razorpay mode: test
Test key: configured
Starter/Team plans: configured and validated
Currency: USD; amounts: 4900/19900
Webhook secret: configured; endpoint: reachable
Billing bridge: configured; scope: provider only
Control plane: reachable; deployment model: cloud
Customer web: reachable
Transactional/deletion email: operational
Deletion grace: 7d
Backup policy and restore ownership: recorded
```

A passing preflight is necessary but not sufficient for Task 261B. The
acceptance must still use a real Razorpay TEST browser checkout and authentic
signed provider evidence.

## Ownership and incident response

The repository contains procedures but no named production owners. The
maintainer must assign owners for payment/webhook failures, refund failures,
email delivery, deletion worker/object cleanup, Enterprise inquiries, and
backup/restore. Each owner needs an observable signal and a bounded response
path before the corresponding gate is marked operational.

## Remaining gates

1. Install the staged current private-web and Cloud control-plane wrappers
   through the root-managed one-time installers; do not use the old P2-R2
   target for Cloud billing.
2. Install protected Razorpay TEST keys, validated plan IDs, webhook secret,
   and the provider-only bridge pair. Configure a TEST webhook on a managed
   test origin and verify HMAC delivery.
3. Configure/verify transactional email and Enterprise inquiry monitoring.
4. Record the real backup/restore and retention policy, including legal
   evidence durations.
5. Publish legally approved policy content and verify `/terms`, `/privacy`,
   `/refund-policy`, `/pricing`, and `/pricing.md` from the active edge.
6. Run Task 261B, Task 270 provider acceptance, Task 268 TEST refund, Task 266
   Enterprise TEST payment, and Task 269 managed deletion acceptance on
   disposable tenants.

Until these gates pass, the Task 256B recommendation is
`DO_NOT_CUT_OVER`.
