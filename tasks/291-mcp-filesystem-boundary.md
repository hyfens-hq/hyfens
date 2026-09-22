# Task 291 — MCP filesystem boundary

Status: [x] Completed

## Goal

Prevent MCP path arguments from escaping the MCP working directory through
absolute paths, traversal segments, or symlinked parents.

## Scope and Non-goals

Scope:

- public CLI MCP path validation;
- path-schema descriptions; and
- focused protocol regression coverage.

Non-goals:

- no private Cloud code or deployment changes;
- no arbitrary shell/filesystem server;
- no redesign of the CLI toolchain's direct non-MCP path behavior; and
- no credential-storage changes owned by Task 289.

## Owner

Public OSS security coordinator.

## Dependencies

- MCP runs as a local stdio process;
- the MCP working directory is the approved project root; and
- existing toolchain preconditions continue to validate project contents.

## Assumptions

- users can launch MCP from the project root or pass paths relative to it;
- rejecting absolute and traversal paths is an acceptable security boundary;
- symlinked ancestors are rejected before handing a path to the toolchain.

## Work Items

- [x] Reject absolute paths and traversal segments at the MCP boundary.
- [x] Reject symlinked path ancestors and retain bounded/control-character
  validation.
- [x] Add focused protocol regression coverage and update MCP documentation.
- [x] Review and run the affected OSS validation.

## Validation

Executed:

- focused MCP protocol tests for absolute, traversal, and symlinked paths;
- delegated scoped Dart analysis and MCP security-boundary tests passed;
- `git diff --check` passed; and
- the worktree boundary scan passed, including a synthetic untracked-marker
  regression that failed closed as expected.

The local arm64 host could not rerun Dart directly because its configured Puro
launcher is an x86_64 binary; the delegated Dart 3.13 validation covered the
changed CLI/MCP scope. MCP now normalizes only relative paths under the launch
directory, rejects absolute/traversal paths, and rejects symlinked ancestors;
the protocol test covers absolute and traversal escapes.

## Next Action

Hand off the reviewed public MCP boundary with the documented local-runtime
limitation recorded above.

## Blockers

None known.

## Outcome

Implemented and validated in the public OSS worktree. MCP remains a local
stdio adapter with no network listener, no raw credential disclosure, and a
filesystem boundary for all path-bearing tool arguments.

## References

- `cli/lib/src/mcp/mcp_server.dart`
- `cli/test/mcp_protocol_test.dart`
- `docs/mcp.md`
- Carver security review, 2026-09-19

## History

- 2026-09-19: Reserved Task 291 after the read-only security review found
  absolute/traversal/symlink-parent paths accepted by MCP.
- 2026-09-19: Added the relative-path/symlink-component boundary, protocol
  regression coverage, and operator documentation.
- 2026-09-19: Delegated Dart analysis and focused MCP tests passed; local Dart
  rerun was unavailable because the configured Puro binary is x86_64 on the
  arm64 host. Reviewed the combined diff and completed the task.
