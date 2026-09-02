# Hyfens v0.1.1

Hyfens v0.1.1 is an early public CLI release. It contains no runtime, Patch
Format, control-plane, or patch-semantics changes.

## Fixes

- Fixed the default curl installer when resolving the latest stable GitHub
  Release from compact API JSON.
- Fixed Windows ZIP archives so their roots preserve the complete semantic
  version and platform suffix, for example
  `hyfens-0.1.1-windows-x64/`.
- Kept direct-download and package-manager metadata aligned with the archive
  naming contract.
- Added a complete, discoverable CLI help surface with `--help`, `-h`, `help`,
  command-level usage, and version output.
- Added a built-in stdio MCP server for compatible AI coding agents. It reuses
  the CLI's local services, host-bound profiles, authentication, verification,
  and authorization boundaries.

## Release status

This note is prepared on `main` before the `v0.1.1` tag is authorized. Do not
use a `v0.1.1` download URL until the tag and GitHub Release exist. MCP does
not grant permissions beyond the authenticated profile and does not provide
arbitrary autonomous production deployment.
