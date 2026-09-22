# Task 296: Container release attestation

Status: [x] Completed

## Goal

Make published container digests independently verifiable against the
repository workflow that built them, in addition to BuildKit provenance.

## Scope and Non-goals

Scope is the public container release workflow, digest attestation, and
operator verification guidance.

Non-goals are restoring absent public build recipes, signing-key management,
registry policy administration, or changing the container contents.

## Owner

Public release-security coordinator.

## Dependencies

- GitHub OIDC and artifact-attestation permissions.
- Registry support for workflow-bound attestations.
- Existing immutable image digest capture.

## Assumptions

- Stable and prerelease images are promoted by immutable digest, not only a
  mutable tag.
- The release workflow may use keyless repository-bound attestation.
- The existing pre-login recipe check remains fail-closed.

## Work Items

- [x] Confirm the current image provenance and digest handoff.
- [x] Add verifiable workflow-bound attestations for each pushed digest.
- [x] Document verification against the exact digest.
- [x] Review and run workflow/configuration validation.

## Validation

Executed:

- workflow syntax/action-pin/permission checks passed through the delegated
  release review;
- digest extraction and attestation inputs are bound to the pushed image
  metadata outputs; and
- `git diff --check` plus the OSS boundary scan passed.

Hosted registry publication and OIDC verification remain external checks.

## Next Action

Hand off the workflow; hosted registry publication and OIDC verification remain
external release acceptance steps.

## Blockers

No source blocker remains. Hosted registry publication and OIDC verification
are external release-acceptance checks.

## Outcome

The container workflow now emits repository/workflow-bound OIDC attestations
for both immutable image digests, with `id-token`, `attestations`, and registry
write permissions scoped to the publishing job.

## References

- `.github/workflows/release-images.yml`
- `docs/cli-distribution.md`
- Task 290 release supply-chain hardening
- Helmholtz security review, 2026-09-19

## History

- 2026-09-19: Reserved after review found that the image workflow records
  provenance and digests but does not publish a directly verifiable
  repository/workflow-bound image attestation.
- 2026-09-19: Added pinned `actions/attest@v4` steps for both pushed digests,
  normalized registry image names, retained exact digest extraction, updated
  operator guidance, and completed local workflow/diff/boundary review.
