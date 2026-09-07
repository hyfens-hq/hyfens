# Trusted runtime install receipts

Hyfens can record that an approved runtime activation completed without
treating a download, update check, or enrollment request as an install. The
server issues an admission, the app installation signs the exact enrollment
and activation receipt with its native P-256 installation key, and the control
plane commits the receipt with one canonical `successful_patch_install` event.

```text
scoped delivery credential
        + server admission/challenge
        + app/environment/release/patch/artifact binding
        + installation-key signature
        + successful activation receipt
        + durable idempotent settlement
```

## Trust modes

Trust is explicit and is not represented by a single client-controlled
boolean:

- `DEVELOPMENT_ACCEPTANCE` verifies the installation key and admission but is
  always non-billable.
- `SIGNED_INSTALLATION` describes key-backed evidence that is not sufficient
  for production billing by itself.
- `ATTESTED_APP` and `ATTESTED_HARDWARE` are returned only by a configured
  provider verifier after it validates platform evidence.
- `PRODUCTION_BILLABLE` is reserved for policy vocabulary; the shipped client
  wire contract reports the attested app/device level together with an
  explicit billable decision.

Play Integrity and App Attest are additive signals. Their provider adapters
receive the exact canonical enrollment bytes and must verify that the provider
nonce/client-data binding covers those bytes. A provider token or assertion by
itself is never a billable event.

## Development acceptance

Self-hosted operators can explicitly enable non-billable acceptance routes in
the stock control-plane binary by listing environment IDs:

```bash
HYFENS_RUNTIME_ACCEPTANCE_ENVIRONMENTS=env_development,env_test
```

The default is disabled. This setting does not configure production
attestation, subscriptions, quotas, overage, or payment collection. A
production deployment must inject a `RuntimeReceiptAcceptancePolicy` and
provider verifier through its approved service boundary.

Delivery credentials created before this endpoint was added do not gain the
`runtime:install` scope retroactively. Reissue the scoped delivery credential
before enabling receipt delivery for an existing environment.

## Settlement and retries

The receipt body binds the application, environment, runtime identity,
release, platform, patch, artifact digest, installation identity, admission,
challenge, and activation deadline. The server independently checks the
promoted release, ready patch, and artifact digest before issuing an
admission. It then verifies the signed receipt and commits the receipt and
canonical event atomically.

The idempotency key is the organization, application, environment,
installation, and patch. A response-loss retry, process restart, or offline
queue retry returns the existing settlement and cannot create a second usage
event. A receipt for another app or environment, a substituted installation
key, a stale admission, or a replayed provider binding fails closed.

The file store provides the existing single-process local semantics. The
PostgreSQL store uses the existing versioned `control_plane_records` table and
an atomic transaction suitable for independent control-plane processes.

Rejected requests retain only bounded diagnostic metadata: operation, error
code, status, request digest, safe IDs, and policy details. Signatures and raw
attestation payloads are never persisted in rejection records.

## Billing boundary

The public control plane emits the canonical event and an explicit
`billable` classification. Development acceptance events have
`financialUsageUnits: 0`. Managed Cloud subscription settlement, plan quotas,
usage projections, customer usage views, and payment-provider behavior remain
outside this self-hosted trust protocol and must apply one shared production
policy before any future billing integration. Live checkout and live overage
collection remain disabled.

Uninstalling an app may remove its platform-protected installation key. In
that case a reinstall is a new Hyfens installation; cross-reinstall dedup is
not claimed by this protocol.

## Current production boundary

The public repository supplies the cryptographic protocol, durable stores,
trust-policy interface, and Android/Apple adapter seams. Actual Google Play
Integrity and Apple App Attest verification credentials and provider calls are
deployment-owned dependencies. Production billability remains disabled until
the private policy and provider integrations are independently accepted.
