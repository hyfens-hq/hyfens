# Cloud plan and entitlement boundary

Status: IMPLEMENTED — 2026-09-07

The control plane now separates the Cloud commercial plan from the deployment
model that owns the infrastructure.

## Domain ownership

The current subscription owner is the `Organization` record. Cloud plan state
is persisted in the existing organization-scoped `billing_subscriptions`
collection. The stable Cloud catalog is persisted in
`billing_plan_catalog`:

```text
free < starter < team < enterprise
```

Self-hosted is represented by the control-plane `DeploymentModel`, not by a
Cloud catalog row or provider subscription. The default deployment model is
`self_hosted`; a managed Cloud control plane must explicitly set
`HYFENS_DEPLOYMENT_MODEL=cloud`.

## Provisioning

Cloud initialization backfills organizations that predate the explicit plan
state. Creation through `ControlPlaneService.bootstrap` assigns an internal
Free record after the organization is persisted and before the bootstrap
result is returned. The assignment has a deterministic record ID, is safe to
retry, and does not contact Razorpay.

An active registered provider subscription takes precedence over Free. Paid
rows are never overwritten by the backfill. A legacy active paid row whose
provider plan key cannot yet be mapped to Starter, Team, or Enterprise is
retained as a paid provider state rather than being silently reduced to Free.

## Entitlement resolution

`BillingService.resolveEffectiveEntitlements` is the central resolver used by
the billing projection and Cloud authorization boundary. The HTTP billing
projection exposes:

- `deployment_model`;
- `cloud_plans`, the backend identity catalog;
- `effective_plan`, including billing status and resolution source; and
- `entitlements`, containing core capabilities and only known limits.

All current Cloud plans share the existing signed-release, bounded-patch,
verification, controlled-deployment, and rollback capabilities. The service
authorization path resolves these capabilities server-side before allowing
the mapped control-plane scopes. The active countable boundaries are also
resolved server-side:

| Plan | Applications | Environments per application | Customer members |
| --- | ---: | ---: | ---: |
| Free | 1 | 1 | 1 |
| Starter | No plan cap | 2 | 5 |
| Team | No plan cap | 10 | 20 |
| Enterprise | Custom | Custom | Custom |

`applications`, `environments_per_application`, and `members` are typed as
finite, unlimited, custom, or not configured. Application and environment
creation, plus the human-auth member admission seams, call the same resolver
before creating new records. A finite boundary returns `PLAN_LIMIT_REACHED`
with the resource, current usage, limit, and effective plan. Existing records
are never deleted on downgrade; a workspace can remain over a reduced limit
while further growth is blocked.

These values are the preserved Cloud commercial baseline activated by this
task, not an MAU or bandwidth quota model. Artifact storage and
control-plane-origin delivery bytes are now measured as operational evidence
for Cloud only, but no byte quotas or overage behavior are enforced. Patch
install volume, release/audit retention, monthly billing periods, overage
billing, and provider settlement remain separate commercial decisions and
must not be advertised as unlimited or quota-metered. See
`docs/architecture/cloud-usage-metering.md` for exact meter semantics.

## Billing boundary

Free uses an internal `not_required` billing state. Customer owners can read
their own billing projection and create/cancel server-owned Starter or Team
checkout intents through the separate `billing:manage` capability; operator
plan/subscription mutation remains behind `billing:write`. Starter, Team, and
Enterprise provider-backed transitions resolve against the same organization
only after a signature-checked Razorpay event matches the server-owned
provider plan and amount. Duplicate provider events are durable and
idempotent, while older events cannot regress a newer state. See
`cloud-billing-lifecycle.md` for the transition and cancellation contract.

The repository currently provides the checkout-intent and verified webhook
state seam, not an outbound Razorpay API client or customer payment UI. The
Cloud web repository owns provider checkout presentation and external
provider wiring. A checkout intent therefore never grants paid entitlements
by itself.

This task does not add account signup, byte quotas, overage billing, invoicing,
tax handling, annual billing, retention deletion, patch-install receipts, or
an Enterprise contract-overrides engine. The countable usage projection and
the metered byte evidence remain separate from future commercial policy.
