# Historical OSS exposure audit

Status: [x] Completed

## Goal

Audit the public `hyfens` history and published package surfaces for the
former Cloud-only dashboard implementation, then choose a safe canonical
history action without weakening OSS self-hosting or release provenance.

## Scope and Non-goals

Scope includes reachable Git history, release tags and assets, source archive
equivalents, GHCR observability, package-manager templates, forks/PRs,
history-aware secret/PII indicators, the private Cloud baseline, and one
authoritative architecture report.

Non-goals are feature work, Cloud/backend migration, tag mutation, force-push,
release deletion, image deletion, DNS/deployment changes, and rewriting
history merely to revoke previously granted Apache-2.0 rights.

## Owner

Migration coordinator.

## Dependencies

- Public mirror of `hyfens-hq/hyfens`.
- Current OSS boundary commit `a721f3f` and tip `285275a`.
- Private Cloud baseline `hyfens-hq/hyfens-cloud-web` at `04d09da`.
- Existing release tags `v0.1.0` and `v0.1.1`.

## Assumptions

- The public Customer/Instance Workspace remains required for self-hosting.
- The global Platform Console remains private Cloud product code.
- Existing bounded platform APIs are preserved until separately reviewed.
- A history rewrite requires explicit maintainer approval after rehearsal.

## Work Items

- [x] Inventory all reachable branches, tags, commits, and historical
  dashboard/platform paths.
- [x] Identify first/last public Platform Console trees and first clean
  customer-only tree.
- [x] Inspect exact `v0.1.0` and `v0.1.1` trees and GitHub release assets.
- [x] Audit source-archive equivalents, GHCR reachability, and package-manager
  artifact scope.
- [x] Run redacted high-confidence secret, credential, PII, and infrastructure
  scans without recording sensitive values.
- [x] Assess forks, pull requests, signatures, references, and rewrite cost.
- [x] Choose `KEEP_HISTORY`; do not force-push or mutate release refs.
- [x] Record findings in `docs/architecture/historical-oss-exposure-audit.md`.

## Validation

- Public mirror: 25 reachable commits, one `main` branch, two annotated signed
  release tags, no public forks, and no pull requests.
- Platform UI markers: first `4da57c8`, last containing tree `78ae59f`, first
  customer-only tree `a721f3f`.
- `v0.1.0` and `v0.1.1`: no platform paths/markers; GitHub source archives
  returned HTTP 200; release assets were CLI-only.
- History secret scan: no high-confidence private-key/provider-token/cloud-key
  hits; `.env.example` values are placeholders.
- GHCR: anonymous image inspection returned authorization failures and the
  available GitHub token lacked `read:packages`; recorded as an external
  inspection gate.
- Current docs/build boundary: OSS dashboard files have no platform UI
  markers; current image Dockerfile copies customer files only.
- `git diff --check` and trailing-whitespace checks passed for the
  documentation batch.

## Next Action

No further historical cleanup action. The approved `KEEP_HISTORY` decision is
closed; any unrelated future history proposal would require its own explicit
destructive-operation approval and rehearsal.

## Blockers

GHCR layer contents could not be independently inspected because the package
requires authorization and the available GitHub token lacks `read:packages`.
The release workflow/tag evidence is recorded, but this remains an external
verification gate.

## Outcome

The current OSS/Cloud boundary is clean and the released CLI tags are outside
the historical Platform Console exposure window. No secret/PII purge is
required. `KEEP_HISTORY` preserves signed history and release provenance while
accepting that previously public Apache-2.0 source remains reachable through
historical commits and existing copies.

## References

- `docs/architecture/historical-oss-exposure-audit.md`
- `docs/architecture/web-product-boundary-audit.md`
- `docs/architecture/dashboard-separation.md`
- `docs/OSS_CLOUD_SOURCE_BOUNDARY.md`
- `tasks/249-web-product-boundary-migration.md`
- Private Cloud baseline: `hyfens-hq/hyfens-cloud-web@04d09da`

## History

- 2026-09-04: Reserved as the single bounded historical exposure and
  sanitization task.
- 2026-09-04: Completed read-only history, release, package, fork, signature,
  and redacted security scans; recorded the non-destructive `KEEP_HISTORY`
  decision.
