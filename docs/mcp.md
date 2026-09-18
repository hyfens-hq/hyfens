# Hyfens MCP

Hyfens includes a local [MCP](https://modelcontextprotocol.io/) server in the
CLI. It gives a compatible coding agent a bounded, structured interface to
the Hyfens workflow while keeping normal authentication, profile selection,
path validation, and command preconditions in force.

The server is a local stdio process. The client launches `hyfens mcp`; stdout
is reserved for protocol messages and diagnostics go to stderr. It is not a
generic filesystem server or a replacement for the control plane.

## Start the server

Authenticate in a terminal before launching an MCP client:

```bash
hyfens login
hyfens profile current
hyfens mcp
```

For a named self-hosted profile:

```bash
hyfens login --host https://hyfens.example.com --profile acme
hyfens mcp --profile acme
```

The client configuration only needs the process mapping:

```yaml
command: hyfens
args: [mcp]
```

Do not put passwords, JWTs, bearer tokens, session secrets, signing keys, or
private keys in MCP arguments or client configuration. The server reuses the
selected local credential record and does not pass raw credentials to the
agent.

## Tool boundary

The public catalog is reported by `tools/list` for the running CLI. It covers
bounded operations such as:

- reading status, diagnostics, profiles, and release metadata;
- initializing a local project binding;
- creating and verifying supported release and patch artifacts; and
- recording bounded local rollback or reporting unsupported delivery actions.

Read-only tools do not intentionally mutate project files or delivery state.
Mutation tools are explicit and remain subject to the selected profile's
authorization, exact release checks, signature checks, and normal Hyfens
preconditions. MCP does not grant additional permissions or perform an
interactive login.

MCP is not an arbitrary shell, file browser, or credential transport. Project
paths and artifact operations are constrained by the tool schemas and the
same validation used by the CLI.

## Troubleshooting

If the client reports that `hyfens` is unavailable, verify the executable and
run `hyfens mcp --help` outside the client. If authentication fails, run
`hyfens profile list`, `hyfens profile current`, and `hyfens status` in a
terminal first. If the client reports invalid protocol output, ensure that
the client launches exactly `hyfens mcp` and that wrappers do not print to
stdout.

See the [CLI reference](cli.md) and the
[self-hosted deployment guide](../deploy/self-hosted/README.md) for the
surrounding endpoint and authentication rules.
