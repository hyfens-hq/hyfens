# Hyfens MCP

Hyfens MCP is the local [MCP](https://modelcontextprotocol.io/) server built
into the Hyfens CLI. It gives an MCP-compatible coding agent a
bounded, structured interface to the Hyfens developer workflow while keeping
authentication, profile selection, host isolation, and Hyfens' normal
preconditions in force.

The v0.1.1 integration is a local stdio process. It is not a hosted MCP
endpoint, a generic filesystem server, or a replacement for the Hyfens control
plane. The client starts the CLI and communicates with it over stdin/stdout;
diagnostic output belongs on stderr.

## Current v0.1.1 boundary

The v0.1.1 MCP surface is intentionally small:

- local stdio launched by `hyfens mcp`;
- server identity `hyfens`, version `0.1.1`;
- the bounded tool catalog in [Tool catalog](#tool-catalog);
- reuse of an existing Hyfens profile and local session;
- structured JSON results and errors, with no terminal formatting in protocol
  output; and
- project paths and artifact operations constrained by the tool schemas and
  Hyfens validation.

This page does not promise an HTTP or streamable-HTTP transport, a remote
hosted MCP server, arbitrary file access, raw credential access, autonomous
login, arbitrary Dart patching, or fleet/HA operations. Those are future work
only when an implementation and its public contract exist. The runtime
`tools/list` response is authoritative for the exact schemas and for whether a
particular build exposes a tool.

## Prerequisites

Before adding Hyfens to an MCP client:

1. Install a v0.1.1 Hyfens CLI and make `hyfens` available on `PATH`. A source
   checkout can use the wrapper described in the [CLI reference](cli.md).
2. Use an MCP-compatible client that can launch a local stdio subprocess.
3. Authenticate the profile in a terminal with `hyfens login`.
4. For project tools, run from a Hyfens-supported Flutter project or provide a
   valid project path where the tool schema permits it. `hyfens doctor` is a
   useful preflight check.

The MCP client does not perform an interactive login. Complete login before
starting the client, and keep the client configuration limited to the command,
arguments, and non-secret profile choice.

## Authenticate and select a profile

For the managed control plane, log in once outside the MCP client:

```bash
hyfens login
hyfens profile current
hyfens status
```

For a self-hosted control plane, bind a named profile to its endpoint:

```bash
hyfens login --host https://hyfens.example.com --profile acme
hyfens profile current
```

`hyfens login` uses the configured browser flow when available. Use
`hyfens login --device` for a headless environment, or the `--email`
compatibility flow when the deployment requires it. See the [CLI
reference](cli.md) for the available login options.

The profile name selects the endpoint and organization/application/environment
metadata used by the MCP process. A client can choose a profile by passing
`--profile NAME` to `hyfens mcp`:

```bash
hyfens mcp --profile acme
```

Do not pass a password, JWT, bearer token, session secret, signing key, or
other raw credential as a tool argument or client setting. Profiles contain
non-secret metadata; session material is kept in Hyfens' credential storage.
`HYFENS_TOKEN` is for separately managed CI/service authentication and should
not be copied into an MCP client configuration.

## Start Hyfens MCP over stdio

The command below starts the v0.1.1 MCP stdio server and waits for protocol
messages:

```bash
hyfens mcp
```

With a named profile:

```bash
hyfens mcp --profile acme
```

The process is intended to be launched by the client for the duration of the
session. Do not pipe shell output, prompts, or other text into its stdout:
stdout is reserved for MCP messages and diagnostics go to stderr. A manual
launch may appear idle until a client sends an MCP request; that is expected.

### Generic client process mapping

Use this transport-neutral mapping in the client configuration mechanism of
your choice:

```yaml
command: hyfens
args: [mcp]
```

For a named profile, the equivalent argument list is:

```yaml
command: hyfens
args: [mcp, --profile, acme]
```

These snippets describe the process command and arguments; they are not a
client-specific configuration file. Client products use different schemas and
locations, so follow the selected client's official documentation for where
to enter this mapping. This page intentionally does not guess Codex, Claude,
VS Code, or another product's proprietary syntax.

## Tool catalog

The v0.1.1 core catalog has these exact public names. Tool descriptions mark
each operation as read-only or mutation, and the server returns structured
results rather than terminal output.

- `hyfens_status` — Read-only. Reports bounded local toolchain and artifact
  state; it does not query profile, application-runtime, or control-plane
  state.
- `hyfens_doctor` — Read-only. Checks supported Flutter/Dart and project
  prerequisites.
- `hyfens_profile_list` — Read-only. Lists profile metadata without credential
  material.
- `hyfens_profile_current` — Read-only. Reports the active profile and
  non-secret endpoint/scope metadata.
- `hyfens_profile_get` — Read-only. Reads selected/active profile metadata
  without credential material.
- `hyfens_project_init` — Mutation. Initializes or updates the bounded local
  Hyfens project binding.
- `hyfens_release_create` — Mutation. Creates a supported release
  baseline/artifact locally.
- `hyfens_release_inspect` — Read-only. Inspects one local release baseline.
- `hyfens_patch_create` — Mutation. Analyzes/builds a supported patch artifact
  locally.
- `hyfens_patch_verify` — Read-only. Verifies supported patch metadata,
  signature, and exact release binding.
- `hyfens_patch_inspect` — Read-only. Inspects one local patch artifact.
- `hyfens_deploy` — Mutation. Uploads/registers/promotes a selected artifact
  through the authenticated control plane.
- `hyfens_rollback` — Mutation. Records a bounded rollback to the trusted
  local base artifact while preserving sequence evidence.
- `hyfens_control_plane_discovery` — Read-only. Discovers advertised
  capabilities for the selected host-bound profile without sending credentials.

The available arguments, project-path rules, and result fields are those
returned by `tools/list` for the running binary. Internal CLI commands and
APIs are not automatically MCP tools.

### Read-only and mutation behavior

Read-only tools may read the local project, profile metadata, artifact
metadata, or authorized control-plane state needed for their checks, but they
do not intentionally write project files, publish artifacts, change rollout
state, or alter profiles.

Mutation tools are explicit operations. `hyfens_project_init`, release
creation, and patch creation affect local project or artifact state;
`hyfens_deploy` can affect remote control-plane state; `hyfens_rollback`
changes local trusted-store state only.
Creation and deployment are separate calls, so an agent can inspect or verify
before asking for a deployment. The MCP server does not send an interactive
confirmation prompt over protocol stdin; use the MCP client's approval policy
for mutations and review the structured result.

All operations remain subject to the selected profile's authorization, the
project and artifact checks, exact release/signature requirements, and the
control plane's normal preconditions. An MCP tool does not grant additional
permissions.

## Security and isolation

Hyfens MCP inherits the security boundary of the CLI process and selected
profile:

- **Profile isolation.** A profile chooses endpoint and
  organization/application/environment metadata. The process uses that
  selection rather than accepting credentials supplied by the agent.
- **Host isolation.** Credential records are bound to a normalized endpoint
  origin and API base path. A session for one host is not sent to another.
  Credential-bearing remote requests require HTTPS; HTTP is allowed only for
  an explicit loopback development endpoint such as `127.0.0.1`.
- **No raw credentials.** Profile display and MCP results omit passwords,
  JWTs, bearer tokens, session secrets, signing keys, and similar private
  material. Do not put them in tool arguments, environment settings, or
  client logs.
- **Project isolation.** Project operations use the bounded paths accepted by
  their schemas and Hyfens validation. MCP is not an arbitrary file browser or
  shell.
- **Protocol isolation.** stdout carries only the MCP protocol. Logs and
  troubleshooting output belong on stderr so they cannot corrupt the client
  session.

For self-hosting, protect the control-plane endpoint and its TLS boundary as
described in the
[self-hosted deployment guide](../deploy/self-hosted/README.md).
Loopback HTTP is a development exception, not a way to expose a control plane
to a network.

## Self-hosted usage

There is no separate MCP server to deploy in the control plane. The local CLI
connects to the selected managed or self-hosted endpoint using the same
profile and session model:

```bash
hyfens login --host https://hyfens.example.com --profile acme
hyfens mcp --profile acme
```

For a local single-node development control plane, an explicit loopback host
may be used where supported:

```bash
hyfens login --host http://127.0.0.1:18082 --profile local
hyfens mcp --profile local
```

Keep the profile name in the generic client mapping if the client should
always use that endpoint. Do not copy a managed-cloud session into a
self-hosted profile or the reverse; log in to each endpoint explicitly.

## Troubleshooting

### `hyfens` is not found

Install the v0.1.1 CLI or put the CLI wrapper from the [CLI reference](cli.md)
on `PATH`. Confirm the executable outside the client with:

```bash
hyfens --version
hyfens mcp --help
```

### `mcp` is an unknown command

The client is launching an older or different `hyfens` binary. Check the
resolved path and version, then install or build the v0.1.1 CLI that includes
the MCP surface. Do not substitute a different binary in the client mapping
without checking its version and profile configuration.

### The server has no profile or authentication fails

Log in outside the client, then check the selected profile:

```bash
hyfens profile list
hyfens profile current
hyfens status
```

If the endpoint is self-hosted, log in with the exact `--host` and profile
named in the client arguments. Host mismatches and authorization failures are
not fixed by copying a token into the client.

### The client disconnects or reports invalid MCP output

Inspect the process' stderr and verify that the client launches exactly
`hyfens` with `mcp` in its argument list. Remove shell wrappers that print
startup banners, prompts, or debug text to stdout. Check that the client is
using a v0.1.1 binary and that no other process is consuming the same stdio
stream.

### A project tool rejects the path or project

Check the path and prerequisites with `hyfens doctor`. Use the documented
project initialization flow if the project has not been bound yet. A tool's
schema and error result determine whether `project_path` is accepted; MCP
does not broaden Hyfens' project or filesystem boundary.

### A mutation fails or its result is uncertain

Read the structured error code, message, and actionable hint. Verify the
selected profile, exact release/patch binding, signature, permissions, and
preconditions before retrying. Treat deploy and rollback as remote mutations;
do not blindly repeat them when the network result is unknown.

## Future work

Additional transports, client-specific setup pages, prompts/resources,
broader bounded control-plane reads, and additional tool names may be added
later. They are not part of the v0.1.1 contract described here. A future
catalog change should be reflected in the implementation's `tools/list`
response and in this document together; internal CLI commands alone do not
make a public MCP capability.

For the underlying command and authentication behavior, see the [CLI
reference](cli.md), [Getting started](getting-started.md), and [developer
platform contract](HYFENS_DEVELOPER_PLATFORM_CONTRACT.md).
