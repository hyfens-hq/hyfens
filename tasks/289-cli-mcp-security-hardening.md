# Task 289: CLI and MCP security hardening

Status: [x] Completed

## Goal

Align the public CLI/MCP implementation and documentation with a secure,
explicit transport and local-credential model that does not expose private
Cloud implementation details.

## Scope and Non-goals

Scope is CLI endpoint/TLS validation, local credential storage behavior, MCP
credential/tool boundaries, tests, and public documentation.

Non-goals are private hosted-service implementation and provider configuration,
mobile application code, and certificate pinning by default.

## Owner

Coordinator, with delegated CLI/MCP implementation and review workstreams.

## Dependencies

- Existing Auth v1 bearer/session contract.
- Existing `AuthStorage`, `DiscoveryClient`, and MCP stdio adapter.
- Platform-native credential-store availability on supported release targets.

## Assumptions

- Remote credential-bearing endpoints must remain HTTPS-only; loopback HTTP is
  permitted only for explicit local development.
- MCP remains a local stdio process and must not become a network listener.
- Public source and documentation must not mention private Cloud integrations.

## Work Items

- [x] Resolve the native credential-store documentation/implementation mismatch
  and preserve a permission-locked fallback where a native store is absent.
- [x] Preserve endpoint binding, token redaction, logout/revocation, and file
  permission guarantees.
- [x] Add focused tests for platform storage selection, fallback permissions,
  endpoint isolation, and MCP secret non-disclosure.
- [x] Review the public source boundary for private Cloud identifiers and run
  the affected CLI/MCP validation.

## Validation

Completed validation:

- Scoped `dart analyze` for auth storage and dependent auth/MCP tests — no
  issues found.
- Focused storage/auth/profile tests — 18 tests passed.
- MCP redaction, capability, and stdio-shutdown tests — 3 tests passed.
- `git diff --check` and targeted public-source/private-integration search —
  clean.

The workspace Flutter wrapper could not start because its Puro cache lockfile
is missing; the available Flutter-tools snapshot was used after dependency
resolution. The combined MCP run also exposed one pre-existing toolchain test
limitation (`Isolate.resolvePackageUriSync`) under that snapshot; the affected
MCP security-boundary tests pass independently.

## Next Action

Hand off the reviewed changes. No commit, release packaging, deployment, or
pull request was performed.

## Blockers

None. Native Secret Service and Windows Credential Manager runtime paths were
not executable on the current macOS host; both have permission-locked file
fallbacks and were covered by injectable focused tests.

## Outcome

Implemented native adapters for macOS Keychain (`security`), Linux Secret
Service (`secret-tool`), and Windows Credential Manager (Win32 FFI). The
default `AuthStorage` now prefers those adapters on supported desktop hosts,
falls back securely when unavailable, and keeps endpoint binding and local
logout cleanup. Public CLI/MCP docs now describe the actual behavior.

## References

- `cli/lib/src/auth_storage.dart`
- `cli/lib/src/auth_client.dart`
- `cli/lib/src/mcp/mcp_server.dart`
- `docs/cli.md`
- `docs/mcp.md`

## History

- 2026-09-19: Reserved task 289 after the security review found that the OSS
  documentation claims native OS credential-store preference while the current
  default `AuthStorage` implementation is file-backed.
- 2026-09-19: Added native adapters for macOS Keychain (`security`), Linux
  Secret Service (`secret-tool`), and Windows Credential Manager (Win32 FFI),
  with endpoint-keyed permission-locked file fallback and fail-closed
  permission enforcement. Added focused platform, fallback, endpoint, and
  redaction coverage; updated the CLI/getting-started/MCP docs to describe
  actual best-effort native availability and limitations.
- 2026-09-19: Auth/storage, auth-flow, profile, and selected MCP protocol tests
  passed; scoped analysis passed and the targeted public-source search found no
  private Cloud identifiers. The MCP doctor case remains environment-sensitive
  (`Isolate.resolvePackageUriSync`), and the process-level MCP stdio test did
  not complete under the checkout's stale `darwin-x64` Flutter tester, so the
  final cross-process check remains pending on a working Flutter test runtime.
- 2026-09-19: Removed provider-specific wording from this public task record
  and reran the worktree-aware OSS boundary scan successfully.
