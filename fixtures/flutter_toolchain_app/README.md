# Phase 1B automatic toolchain fixture

This is a deliberately small ordinary Flutter application used to validate
the developer-facing Phase 1B workflow. It contains no manual E1 controller,
per-function annotation, rewritten dispatch call, or PatchView widget.

The fixture is initialized with `tool init`; the release build receives the
runtime bootstrap only in the CLI's temporary instrumented overlay. The
Android physical workflow used an explicit `INTERNET` permission and a
temporary private-network `runtime.update_url` for the local development
server. The checked-in configuration is restored to loopback.

## Local iOS signing

The generated iOS host uses the local development team `CYT7A4VAZ3` for
`dev.hyfens.hyfensToolchainApp`. A device Release build requires the matching
Apple Development identity and an installed device development profile; the
bounded audit used the existing wildcard profile and did not pass
`-allowProvisioningUpdates` or `-allowProvisioningDeviceRegistration`. If the
local signing pair is unavailable, `tool release ios` reports `T1603` and does
not commit a release baseline. This fixture setting is project-local and does
not create, revoke, or change organization-wide signing assets.

See [`docs/getting-started.md`](../../docs/getting-started.md) for the local
workflow and [`docs/research/developer-workflow.md`](../../docs/research/developer-workflow.md)
for the recorded physical evidence.
