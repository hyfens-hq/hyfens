# CLI package-manager metadata

These files are templates only. They are not Homebrew, Scoop, or WinGet
publication records, and this repository does not claim that any package
manager publication exists.

After a tagged GitHub Release has been built, replace every `__PLACEHOLDER__`
with values from `artifact-inventory.json`, then submit the generated metadata
through the independently verified package-manager repository and review
process. The release workflow produces x64 and arm64 archives for macOS,
Linux, and Windows. Do not commit release-specific metadata here unless that
destination and ownership have been approved. See
[`docs/cli-distribution.md`](../../docs/cli-distribution.md) for the direct
download and verification flow.

The `tool` executable is included as a deprecated compatibility shim when the
release helper builds it successfully. New installations should invoke
`hyfens`.
