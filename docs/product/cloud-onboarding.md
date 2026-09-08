# Managed Cloud onboarding

Status: managed Cloud onboarding contract and developer handoff.

Hyfens Cloud has a distinct first-use journey from the self-hosted
Customer/Instance Workspace. A new managed customer starts at
[`app.hyfens.com/signup`](https://app.hyfens.com/signup), verifies the account,
and becomes the owner of a new Cloud organization. The Customer Workspace
then provisions the first application and development environment from the
published Cloud entitlements and provides the CLI handoff.

## First-use flow

```text
Start free
→ create account
→ verify email
→ Cloud organization owner
→ Developer subscription
→ first application
→ first development environment
→ CLI login and project binding
```

The supported developer handoff is:

```bash
brew install hyfens
hyfens login
cd your_flutter_project
hyfens doctor
hyfens init
```

Use the current public installer when Homebrew is not available. The CLI
profile and `hyfens.yaml` contain endpoint and project-scope metadata only;
passwords, sessions, bearer tokens, and private signing keys stay out of
project configuration.

## Managed Cloud and self-hosted access are separate

Managed Cloud signup creates a new customer organization and its first owner.
It does not require payment details for the free Developer plan, and it does
not require SSH, a server token, SQL, or a staff-created organization.

The legacy `POST /v1/public/register` contract remains the self-hosted or
preconfigured client-access flow: it joins an existing selected organization
with the limited public-client capability set. It is not a managed Cloud
organization-creation route. Self-hosted deployments continue to use the OSS
Customer/Instance Workspace and their explicitly configured control-plane
endpoint.

## Cloud workspace boundary

The managed deployment uses:

```text
hyfens.com          → marketing
app.hyfens.com      → managed Cloud Customer Workspace
platform.hyfens.com → private staff Platform Console
api.hyfens.com      → managed API edge
```

The OSS Customer/Instance Workspace remains available for self-hosted
deployments. Customer sessions do not grant Platform Console access, and
platform staff membership is not created as a side effect of customer signup.

Application and environment creation is idempotent and entitlement-checked.
If onboarding is interrupted, return to the Customer Workspace to resume; do
not create a second organization or use an operator-only recovery path.

## Verification delivery

Managed signup is deliberately fail-closed when its verification delivery
configuration is absent or unavailable. A deployment may use a controlled
capture transport for local or staging acceptance, but production must send a
real verification message and must never bypass verification in the browser.

The verification link is short-lived and contains no session credential. A
retry of the same verification request is safe and does not create a second
organization, owner, or onboarding record; the control plane stores only a
token hash.

See the [Customer Workspace guide](customer-workspace.md), [CLI guide](../cli.md),
and [self-hosted deployment guide](../../deploy/self-hosted/README.md) for the
shared product boundaries.
