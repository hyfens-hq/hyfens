# Hyfens v0.1.1

Hyfens v0.1.1 is a CLI distribution hotfix. It contains no runtime,
Patch Format, control-plane, or patch-semantics changes.

## Fixes

- Fixed the default curl installer when resolving the latest stable GitHub
  Release from compact API JSON.
- Fixed Windows ZIP archives so their roots preserve the complete semantic
  version and platform suffix, for example
  `hyfens-0.1.1-windows-x64/`.
- Kept direct-download and package-manager metadata aligned with the archive
  naming contract.

## Release status

This note is prepared on `main` before the `v0.1.1` tag is authorized. Do not
use a `v0.1.1` download URL until the tag and GitHub Release exist.
