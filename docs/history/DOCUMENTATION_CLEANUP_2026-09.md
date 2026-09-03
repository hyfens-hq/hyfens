# Documentation cleanup — September 2026

Status: HISTORICAL coordinator record.

This cleanup made current documentation easier to find without deleting
legal, security, licensing, provenance, or decision records. Internal research
and provider-operation evidence remains outside the public documentation tree.

## Inventory and disposition

Before cleanup, the working tree contained 61 Markdown files at the `docs/`
root and 218 files in total. The root contained milestone/review/design
records alongside developer guides. In the working tree those records were
reorganized under `history/`; this public commit retains selected dashboard
and release-boundary records and history indexes. Internal research, generated
evidence, and provider-operation reviews remain outside the public tree.

The current root contains the concise navigation and active guides. Current
product pages were added for the Customer Workspace and Platform Console.
Public ADRs, security, specification, store-policy, and operations documents
were retained where they provide durable technical or governance guidance.
Task files and internal research were not treated as product documentation.

The inventory classification used the following disposition: current guides
and legal/governance files are `AUTHORITATIVE`; ADRs, specifications, research,
security, operations, and store-policy material are `KEEP_REFERENCE`; milestone
and superseded product records are `HISTORICAL`; files whose only purpose was
to record a completed phase remain under history rather than in the current
navigation. No legal, security, licensing, provenance, or contribution file
was classified as disposable.

## Current source of truth

[`docs/README.md`](../README.md) is the entry point. Current behavior is
documented by the CLI, getting-started, self-hosted, architecture, product,
security, specification, and contribution documents linked there. The selected
historical reviews do not override current source or these guides.

## Link and preservation checks

Links were repaired after the moves, and legal/security files remained at
their public locations. No production DNS, repository history, task history,
or source architecture was changed by this cleanup.
