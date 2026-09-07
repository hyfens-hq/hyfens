# Contributing

Hyfens is maintained as an open-source Flutter-first runtime, protocol, and
tooling project. The OSS core is licensed under the [Apache License 2.0](LICENSE).

## Governance and sign-off

The project uses maintainer-led governance and a DCO-only contribution
process. Contributions are accepted under the Apache-2.0 terms. No
Contributor License Agreement (CLA), including a CCLA, is required, requested,
or accepted for contributions to this repository.

Every commit submitted for inclusion must include a `Signed-off-by` trailer
using the contributor's name and email, for example:

```text
Signed-off-by: Your Name <your.email@example.com>
```

Use Git's sign-off option when creating the commit:

```bash
git commit -s -m "Describe the change"
```

The trailer follows the [Developer Certificate of
Origin](https://developercertificate.org/) version 1.1. It attests that the
contributor has the right to submit the work under the applicable project
license and understands that the contribution is public. The DCO sign-off is
not a copyright assignment, relicensing grant, or trademark permission.
Commits without the required trailer may be returned for correction before
review or merge.

Use Hyfens names and logos in accordance with the [trademark
policy](TRADEMARKS.md). The policy is a draft pending maintainer and legal
review.

## Scope

The open-source core must remain independently useful without a hosted
control plane. Runtime signature verification, exact release binding,
capability authority, sequence/high-water checks, rollback, and AOT fallback
are not delegated to a service. Do not add cloud, billing, dashboard,
enterprise, or React Native work to a bounded runtime/tooling task.

Before making a durable change, read `AGENTS.md` when present, create or
update the applicable task record under `tasks/`, preserve existing evidence,
and run the scoped validation described by that task. Do not commit or publish
changes unless the maintainer explicitly asks for it.

## Release and task hygiene

Every user-visible change intended for a public release must add a concise
entry to [`CHANGELOG.md`](CHANGELOG.md) under `[Unreleased]` in the same
change. Release preparation moves those entries into the new version section.
Internal-only refactors, test-only changes, and corrections with no
user-visible effect may omit an entry.

Every stable public release must contain meaningful human-readable GitHub
Release notes derived from its `CHANGELOG.md` section. A tag and artifacts
alone do not complete a release. Use the [release process](docs/releases/releasing.md)
for the RC, immutable-release, distribution, and verification requirements.

Before closing a task, inspect task-created worktrees, branches, generated
artifacts, temporary credentials, device configuration, and Git state. Remove
only task-owned temporary state, preserve unrelated developer work, and
resolve or explicitly record completed changes that are committed but not
pushed or merged.

After publishing a release, verify its remote tag, notes, artifacts, checksums,
supported installation channels, and public install; remove temporary release
state and leave the task-owned repository clean. Published stable tags and
artifacts remain immutable; corrections ship in a new version.
