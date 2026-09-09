# Task 262 — Provision Razorpay Test Environment for Hyfens Cloud

Status: [-] Blocked — EXTERNAL_CONFIGURATION_BLOCKED

## Goal

Prepare a protected Razorpay TEST MODE environment for the real Task 261B
browser acceptance without changing billing code, pricing, plan limits, or
production routing.

## Scope and Non-goals

Scope:

- inventory the exact private-web and control-plane configuration required by
  the existing Razorpay adapter;
- verify the protected configuration is present without printing values;
- record the provider-plan, webhook, bridge, origin, and connectivity setup
  needed for Task 261B; and
- update the billing architecture record with the split deployment boundary.

Non-goals:

- adding billing features or a second provider/preflight framework;
- creating provider plans without authorized Razorpay TEST MODE access;
- fabricating provider IDs, webhooks, subscriptions, or billing state;
- changing USD prices, plan limits, tax/refund policy, or production config; and
- cutting over `app.hyfens.com` or activating production Razorpay.

## Owner

Codex

## Dependencies

- Task 261 implementation and its customer billing surface.
- A Razorpay TEST MODE account that supports the approved USD recurring plans.
- Protected managed-web and managed-control-plane deployment access.
- A disposable managed Cloud acceptance target with reachable HTTPS webhook
  routing.

## Assumptions

- Public pricing is USD: Starter `$49/month` and Team `$199/month`.
- The private web route `/api/billing/webhook` is the current external webhook
  boundary; the control plane remains the billing state authority.
- Provider secrets and plan identifiers belong in deployment configuration,
  never source, task records, or browser assets.

## Work Items

- [x] Inspect Task 261 code, configuration examples, deployment wrappers, and
  billing documentation.
- [x] Inspect the official Razorpay MCP index, Remote MCP setup, OAuth, tools,
  and configuration documentation.
- [x] Enumerate the connected MCP tool inventory and classify Razorpay
  capabilities without invoking unrelated provider/deployment mutations.
- [x] Inventory private-web, control-plane, routing, webhook, and bridge
  configuration names without reading or printing secret values.
- [x] Check the current protected environment for required TEST MODE values.
- [x] Record the safe provider/account provisioning checklist and configuration
  split for the maintainer/provider account owner.
- [x] Update the billing architecture documentation with the control-plane
  configuration names and protected deployment boundary.
- [x] Read the supplied local Razorpay TEST credential CSV without printing
  credential values and validate the test-key prefix.
- [x] Verify the supplied key pair against Razorpay TEST API read endpoints.
- [x] Confirm Razorpay Dashboard TEST MODE and inspect the subscription/plan
  surfaces without submitting a provider mutation through the UI.
- [x] Verify Razorpay account support for USD recurring subscriptions — the
  merchant enabled the international-payment capability and the TEST API now
  accepts the approved USD recurring-plan configuration.
- [x] Create and validate TEST MODE Starter and Team provider plans — exact
  monthly USD plans were created/read back successfully; IDs are in the
  protected external plan handoff file.
- [-] Configure test keys, webhook secret, bridge credential, managed targets,
  and webhook reachability.
- [-] Run the provider preflight/connectivity smoke and Task 261B browser
  acceptance.

## Razorpay MCP Capability Matrix

The current Codex session exposes an `mcp__razorpay` server. A bounded,
read-only `fetch_all_payments({count: 1})` call completed successfully,
confirming that the connected MCP can reach Razorpay payment data. The result
was not printed or persisted. No payment, order, link, subscription, plan,
webhook, or other provider mutation was invoked.

The official documentation was inspected from the [Razorpay MCP index](https://razorpay-881012b3.mintlify.site/llms.txt),
[Remote MCP setup](https://razorpay-881012b3.mintlify.app/docs/mcp-server/remote),
[OAuth guide](https://razorpay-881012b3.mintlify.app/docs/mcp-server/oauth),
[tools reference](https://razorpay-881012b3.mintlify.app/docs/mcp-server/tools-reference),
and [configuration guide](https://razorpay-881012b3.mintlify.app/docs/mcp-server/configuration).
The published tool reference and the connected tool inventory include
payment/order/link/refund/QR/settlement/payout tools and checkout helpers, but
no plan listing/creation, subscription listing/creation/cancellation, customer,
or webhook-management tools. The OAuth example exposes a `read_only` scope.
Therefore the connected MCP can provide limited provider read evidence, but it
cannot provision or inspect the subscription environment required by this
task, independently of the missing Hyfens deployment secrets.

The Razorpay REST API, authenticated with the supplied TEST key pair, returned
HTTP 200 for payment, plan-list, and subscription-list reads. Before account
enablement the plan list was empty and USD creation was rejected. After the
merchant enabled International Payments, the same API created exactly two
approved monthly USD plans and read both back successfully: Starter `4900`
minor units and Team `19900` minor units. The connected Razorpay MCP remains
read-only for plan/subscription/webhook operations; it was used only for a
bounded connectivity read. No subscription or payment was created.

| Capability | MCP available | Read | Write | Suitable for Task 262 |
| --- | --- | --- | --- | --- |
| Account/test-mode inspection | No dedicated tool; payment read confirms connectivity only | Partial | No | No |
| Plan listing | No connected tool; not in published tool list | No | No | No |
| Plan creation | No connected tool; not in published tool list | No | No | No |
| Subscription listing | No connected tool; not in published tool list | No | No | No |
| Subscription creation | No connected tool; not in published tool list | No | No | No |
| Subscription cancellation | No connected tool; not in published tool list | No | No | No |
| Customer inspection | No connected tool | No | No | No |
| Webhook inspection/configuration | No connected tool; not in published tool list | No | No | No |
| Payment inspection | Yes: `fetch_all_payments` | Yes | No | No; not the subscription path |
| Provider event inspection | No connected tool | No | No | No |

## Validation

- Safe environment inspection reported all required provider/bridge values as
  missing; no values were printed.
- The supplied CSV was read locally with one credential row; both required
  fields were present and the key ID matched the `rzp_test_` format. Values
  were never printed, persisted, or added to repository configuration.
- The supplied pair authenticated successfully against Razorpay TEST API
  payment, plan-list, and subscription-list reads (HTTP 200).
- Razorpay TEST plan listing returned zero plans. The approved Starter USD plan
  creation request returned HTTP 400; no plan ID was returned or stored. The
  Dashboard showed TEST MODE and an INR-only plan creation currency, confirming
  the provider currency block without creating an INR substitute.
- Official Razorpay MCP index and relevant Remote MCP documentation were
  retrieved successfully. The connected `mcp__razorpay` inventory exposes
  payment/order/link/QR/refund/settlement/payout tools and checkout helpers,
  but no plan, subscription, or webhook operations required by this task.
- A bounded `fetch_all_payments({count: 1})` read completed successfully. Its
  provider response was discarded without logging payment data or identifiers;
  it proves MCP connectivity only, not TEST MODE, USD support, or subscription
  capability.
- `dart analyze lib/src/billing.dart lib/src/http.dart test/config_test.dart
  test/customer_billing_test.dart` passed.
- `dart test test/config_test.dart test/customer_billing_test.dart` passed:
  17 tests.
- Final `dart test test/config_test.dart` passed: 11 tests.
- Cloud web lint, typecheck, and production build passed in the prior Task 261
  validation baseline; no Cloud web source was changed by this blocked audit.
- `git diff --check` passed in both repositories after the task-record and
  documentation updates.
- The existing Cloud web static bundle scan found no server-only billing
  secrets.

## Next Action

The deployment owner must now provision the protected Hyfens TEST inputs listed
below, then rerun this task's no-secret preflight and continue with Task 261B.
Do not send credentials through chat or commit them.

## Blockers

The provider-side currency blocker is resolved. The remaining blocker is the
protected managed deployment: the running private web lacks the TEST mode,
Razorpay key pair, webhook secret, public currency, and billing bridge token;
the running control plane lacks the provider plan IDs, webhook secret, USD
currency, and approved amounts. The current deployment user cannot read or
write the root-owned protected environment files. No provider subscription,
customer billing state, production configuration, or DNS state was mutated.

There is also a concrete bridge-authorization compatibility gap to resolve
before a multi-tenant browser acceptance: `HYFENS_BILLING_CONTROL_TOKEN` is
sent to organization-scoped `billing:write` routes, while the existing control
credential authorizer requires the credential's organization to equal the URL
organization. One static token therefore cannot safely register provider
events for arbitrary Cloud customer organizations. A tenant-specific token is
not an acceptable shared Cloud deployment solution, and no bridge workaround
was introduced.

## Configuration Matrix

| Setting | Required | Present | Source / validation |
| --- | --- | --- | --- |
| `RAZORPAY_MODE` | Yes, private web | TEST confirmed by key/API; missing in running container | Must be `test`; key must use `rzp_test_` prefix |
| `RAZORPAY_KEY_ID` | Yes, private web | Local CSV available; missing in running container | Razorpay TEST MODE public key; browser exposure remains adapter-controlled |
| `RAZORPAY_KEY_SECRET` | Yes, private web | Local CSV available; missing in running container | Protected server-only secret |
| `RAZORPAY_WEBHOOK_SECRET` | Yes, private webhook | Missing | Verifies raw-body HMAC at `/api/billing/webhook` |
| `HYFENS_RAZORPAY_STARTER_PLAN_ID` | Yes, control plane | Plan created/validated; missing in running container | TEST MODE monthly USD `$49` plan |
| `HYFENS_RAZORPAY_TEAM_PLAN_ID` | Yes, control plane | Plan created/validated; missing in running container | TEST MODE monthly USD `$199` plan |
| `HYFENS_RAZORPAY_WEBHOOK_SECRET` | Yes, control-plane provider config | Missing | Required by control-plane billing configuration/direct webhook path |
| `HYFENS_RAZORPAY_CURRENCY` | Yes, control plane | Validated in external plan handoff; missing in running container | Must be uppercase `USD` |
| `HYFENS_RAZORPAY_STARTER_AMOUNT_MINOR` | Yes, control plane | Validated in external plan handoff; missing in running container | Must match approved USD minor-unit amount: `4900` |
| `HYFENS_RAZORPAY_TEAM_AMOUNT_MINOR` | Yes, control plane | Validated in external plan handoff; missing in running container | Must match approved USD minor-unit amount: `19900` |
| `HYFENS_BILLING_CONTROL_TOKEN` | Yes, private web bridge | Missing in running container | Least-privilege server-only bridge credential |
| `HYFENS_BILLING_API_BASE` | Yes, private web | Configured in running container | Managed control-plane base URL |
| `NEXT_PUBLIC_HYFENS_API_BASE` | Yes, Cloud web routing | Configured in running container | Managed control-plane API base used by customer auth/session contracts |
| `NEXT_PUBLIC_HYFENS_DASHBOARD_URL` | Routing/UI link | Configured in running container | No separate Razorpay return URL is consumed by the current adapter |
| HTTPS webhook URL | Yes | Route exists; provider registration/unverified signature delivery pending | Current deployed endpoint is `https://hyfens.com/api/billing/webhook` |

The private deployment wrapper documents `/etc/hyfens/platform-web.env` as a
root-owned, mode-`0600` protected environment file. The managed control-plane
secret-store target is not exposed by this workspace and must be supplied by
the deployment owner; do not invent a local substitute.

## Safe Provisioning Checklist

1. In the Razorpay dashboard, switch explicitly to TEST MODE and verify the
   account can create monthly recurring subscription plans in USD. If USD is
   unavailable, stop with `PROVIDER_CURRENCY_BLOCKED`; do not create INR plans
   or change Hyfens prices.
2. Create or validate only the monthly TEST MODE Starter and Team plans at USD
   `$49` and `$199`. Verify mode, currency, amount, interval, and period in the
   provider dashboard/API. Keep the resulting provider identifiers out of
   source and general documentation.
3. Store the test key pair, private webhook secret, bridge credential, exact
   `USD` setting, and private-web routing values in the protected web deployment
   environment. Store the control-plane plan IDs, amounts, currency, and
   provider webhook secret in the managed control-plane protected environment.
4. Configure the Razorpay TEST MODE webhook to the HTTPS private-web endpoint,
   preserving the raw body and signature header. Configure only the provider
   subscription status events required by the parser/state machine; verify the
   exact event names in the test account rather than subscribing to arbitrary
   events.
5. Deploy/restart the managed web and control-plane services through their
   existing protected procedures. A safe preflight must report only status,
   mode, validated plan metadata, currency, route reachability, and bridge
   availability; it must never print secrets.
6. Run connectivity checks in order: Cloud web to control plane, billing
   server to Razorpay TEST API, and Razorpay webhook delivery to the HTTPS
   endpoint. A webhook ping is connectivity evidence only, not payment
   acceptance.
7. Rerun Task 261B with a new customer-owned Free organization. Preserve
   redacted provider evidence and cancel disposable TEST MODE subscriptions
   after acceptance where appropriate.

## Outcome

Razorpay TEST MODE now accepts the approved USD recurring plans after the
merchant enabled International Payments. The provider portion of this task is
complete; the task remains blocked only on protected Hyfens deployment
configuration and webhook/bridge setup. No INR substitute, fake plan,
subscription, or Hyfens billing state was introduced.

## References

- `tasks/261-razorpay-checkout-customer-billing-acceptance.md`
- `docs/architecture/cloud-billing-lifecycle.md`
- `hyfens-cloud-web/docs/HYFENS_CLOUD_BILLING_V1.md`
- `hyfens-cloud-web/deploy/web/README.md`
- `hyfens-cloud-web/deploy/web/hyfens-platform-deploy`
- `hyfens-cloud-web/site/src/lib/billing-server.ts`
- `packages/control_plane/lib/src/billing.dart`

## History

- 2026-09-08: Created from the Task 261 external provider-configuration gap.
- 2026-09-08: Audited the split configuration names and protected deployment
  boundary. All provider/account inputs were absent from the current session;
  no provider mutation was attempted. Focused billing tests and analyzer passed.
- 2026-09-08: Added the protected provisioning matrix/checklist and clarified
  the control-plane deployment boundary in the billing architecture document.
  Final config tests, diff checks, and the static bundle secret scan passed;
  the task remains externally blocked.
- 2026-09-08: Inspected the official Razorpay MCP documentation and the actual
  connected MCP inventory. At that time no Razorpay MCP server was connected;
  the published Remote MCP tool set also did not expose the required
  plan/subscription/webhook operations. No provider mutation was attempted.
- 2026-09-08: Razorpay MCP became available. Confirmed the connected payment
  read capability with one bounded `fetch_all_payments({count: 1})` call. The
  MCP still lacks the required plan/subscription/webhook operations and does
  not establish TEST MODE or USD plan capability; no provider mutation was
  attempted.
- 2026-09-08: Read the supplied local TEST credential CSV without printing
  values. Razorpay TEST API authentication succeeded; plan and subscription
  reads returned HTTP 200 with zero plans. An authorized USD Starter plan
  creation request was rejected with HTTP 400, and the open TEST Dashboard
  showed an INR-only plan form. No provider plan was created; Task 262 is now
  blocked specifically as `PROVIDER_CURRENCY_BLOCKED`.
- 2026-09-08: Task 263 confirmed the structured provider rejection and the
  account-level `Account Access Limited` state. Razorpay website/app review and
  International Payments/Subscriptions enablement are required before Task
  262 can resume; no account request or pricing workaround was submitted.

- 2026-09-08: Reviewed the provider-registration path and confirmed the
  shared `HYFENS_BILLING_CONTROL_TOKEN` is submitted to organization-scoped
  `billing:write` routes, whose current credential authorization requires an
  exact organization match. This prevents one safe static bridge credential
  from serving arbitrary Cloud tenants. No tenant-specific token or auth
  bypass was used; the issue remains a blocker for Task 261B.
- 2026-09-08: The merchant reported International Payments was enabled. The
  supplied TEST key pair authenticated successfully; exactly two monthly USD
  plans were created and read back with the approved amounts (`4900` and
  `19900` minor units). Their IDs were stored in the protected external plan
  handoff file. No subscription or payment was created.
- 2026-09-08: After the merchant reported that the website was verified, one
  bounded real TEST API recheck still rejected the approved USD Starter plan
  with HTTP 400 `BAD_REQUEST_ERROR` (`currency: Currency provided is not
  supported`). No plan was created and Team was not attempted. Website review
  is therefore no longer the evidenced gap; International Payments/USD
  recurring-Subscriptions capability remains unavailable.
- 2026-09-08: Read-only managed deployment check found the private web and
  control plane healthy, but the private web's effective runtime configuration
  is missing Razorpay mode/key/secret, webhook secret, billing bridge token, and
  public billing currency; the control plane is missing all required
  `HYFENS_RAZORPAY_*` plan, webhook, currency, and amount settings. The protected
  host env files exist as `root:root` mode `0600` but are not readable or
  writable by the current deployment user. The live billing page returns 200
  and the POST-only webhook route exists at `/api/billing/webhook`; no provider
  plan or webhook state was changed. These are follow-on deployment blockers
  after Razorpay account enablement.
- 2026-09-08: Task 263 confirmed the structured provider rejection and the
  account-level `Account Access Limited` state. Razorpay website/app review and
  International Payments/Subscriptions enablement are required before Task
  262 can resume; no account request or pricing workaround was submitted.

## Post-Task-265 correction

The earlier configuration notes describing one shared
`HYFENS_BILLING_CONTROL_TOKEN` as an organization-scoped `billing:write`
credential are superseded by Task 265. The private web bearer is now intended
only for the dedicated provider bridge. The managed control plane stores its
lowercase SHA-256 digest as `HYFENS_BILLING_PROVIDER_TOKEN_HASH` and exposes
provider-only link, sync, and signed-webhook routes. Those routes derive the
organization from the server-owned checkout/provider mapping; they do not trust
an organization identifier from the browser or Razorpay payload. Customer
billing routes remain `billing:manage` and tenant-bound.

Task 262 remains blocked because the protected web environment and managed
control-plane secret store are not installable by the current deployment user.
The bridge code is locally verified, but no protected bearer/hash, webhook
secret, or plan IDs were installed and no Task 261B provider acceptance was
performed.
