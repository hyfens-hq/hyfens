# Task 236 — Hyfens public repository publication

Status: [x] Completed

## Goal

Complete the final licensing, OSS/commercial-boundary, security, asset, and publication-readiness review for Hyfens, then—only if every required gate passes—create and publish exactly `hyfens-hq/hyfens` as a clean public Apache-2.0 repository on `main`.

## Scope and Non-goals

Scope includes the current checkout's public-source boundary, licensing materials, dependency and asset review, security/publication hygiene, README/self-host/contribution/release readiness, clean initial history, creation of `hyfens-hq/hyfens`, and post-publication verification.

Non-goals: changing, archiving, renaming, transferring, deleting, or changing visibility of `hyfens-hq/backend` or `hyfens-hq/frontend`; creating `v0.1.0`; publishing images or package-manager artifacts; announcing the project; or starting another release phase.

## Owner

Primary coordinator: Codex. Independent review packages: A — OSS/license/dependency; B — public/private architecture boundary; C — security/repository hygiene; D — README/self-host/contribution readiness.

## Dependencies

- Maintainer authorization to publish exactly `hyfens-hq/hyfens` publicly.
- GitHub CLI authentication with permission to create the target repository.
- Existing Apache-2.0, DCO, self-host, CLI, dashboard, control-plane, and release-workflow materials in this checkout.

## Assumptions

- Apache-2.0 remains the default unless a concrete incompatibility is found.
- A conservative trademark policy may be drafted and marked for maintainer/legal review; no custom source-license restrictions will be added.
- The clean public history will contain one initial bootstrap commit unless verification requires a narrowly scoped follow-up correction.
- The existing `backend` and `frontend` repositories are immutable for this task.

## Work Items

- [x] Reserve this task and inspect the checkout, repository state, and public-candidate contents.
- [x] Run independent reviews A–D and collect evidence without publishing or changing GitHub state.
- [x] Reconcile the finite publication gates after asset remediation: all required licensing, provenance, notice, OSS-boundary, and security gates pass.
- [x] Apply the safe hygiene and in-scope source fixes that do not assume asset rights; quarantine generated fixture output and remove generated private signing-key files.
- [x] Perform consolidated targeted validation and final self-review.
- [x] Create `hyfens-hq/hyfens`, add `origin`, create the clean signed initial commit, push `main`, and verify the public repository.
- [x] Verify the target repository is absent, `backend`/`frontend` remain private and unchanged, and no release tag or artifact publication was attempted.

## Validation

Completed checks: dependency/license and asset inventory; pinned Lucide license verification; brand-guideline provenance review; high-confidence secret and sensitive-data scans after generated-key quarantine; explicit staged public-candidate path scan; README/self-host/link and workflow/configuration review; focused Dart/Python/Flutter tests and analysis; dashboard and control-plane image builds; image filesystem scans; Compose config validation; a real macOS arm64 CLI archive inventory; clean-history inspection; and read-only GitHub verification of the published target and protected repositories. Full validation results and the publication SHA are recorded in the final history entry.

## Next Action

Stop this milestone. Do not create `v0.1.0`, publish GHCR images, publish package-manager artifacts, announce launch, or start another phase without separate authorization.

## Blockers

None. The previously unresolved dashboard icon assets and Flutter-template launcher artwork were replaced, the replacement provenance and notices were recorded, and the finite publication gate passed. This is an engineering review, not legal advice.

## Outcome

`HYFENS OSS PUBLICATION — PASS`. The asset, dependency, notice, trademark, DCO, self-host usability, container, CLI archive, and security gates passed. `https://github.com/hyfens-hq/hyfens` was created as a public repository on `main` and pushed with one clean signed initial commit. No `v0.1.0` tag, GHCR image release, package-manager publication, or launch announcement was created.

## References

- User publication instruction: Hyfens Public Repository Publication — Licensing, OSS Boundary & GitHub Release.
- `LICENSE`, `README.md`, `CONTRIBUTING.md`, `THIRD_PARTY_NOTICES.md`.
- `deploy/self-hosted/README.md`, `deploy/self-hosted/docker-compose.yml`.
- `.github/workflows/release-images.yml`, `.github/workflows/release-cli.yml`.
- Official Apache-2.0 license text: https://www.apache.org/licenses/LICENSE-2.0.txt
- Official GitHub license detection guidance: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
- Official DCO: https://developercertificate.org/
- Iconsax license terms reviewed for asset redistribution: https://docs.iconsax.io/license-and-terms/license
- Iconsax usage manifesto reviewed for asset redistribution: https://docs.iconsax.io/license-and-terms/usage-manifesto

## History

- 2026-09-02: Reserved task 236 for the bounded public-repository publication milestone; no GitHub repository has been created and no remote publication has occurred.
- 2026-09-02: Delegated A–D reviews completed. A found unresolved Iconsax/IconSax asset redistribution rights and unverified Flutter-template artwork provenance; B confirmed the public core/self-host boundary and implemented focused remote-HTTP transport hardening plus runtime-config test coverage; C found generated fixture signing keys and internal evidence, which were quarantined/excluded; D found public-doc/readiness corrections still needed. No GitHub mutation occurred.
- 2026-09-02: Consolidated validation passed for `python3 -m unittest dashboard.test_serve` (30 tests), `dart test test/control_plane_delivery_test.dart` (all tests), and `dart analyze` in `packages/flutter_integration`. High-confidence secret-file/pattern scan returned no remaining matches in the checkout; the exact generated fixture signing-key files were removed from the quarantined disposable output. The target `hyfens-hq/hyfens` does not exist; `backend` and `frontend` remain private on `main` with no task-side GitHub writes.
- 2026-09-02: Publication stopped at the licensing gate. Maintainer/legal review or asset replacement is required before reopening the publication milestone.
- 2026-09-02: Maintainer requested closure remediation without new task creation: parallel packages A (asset provenance/replacement), B (dependency notices), C (trademark/DCO governance), and D (security/hygiene) were delegated. The coordinator retains the final gate and all GitHub actions.
- 2026-09-02: Closure remediation completed. The unverified dashboard icon set was replaced with 22 pinned Lucide 1.27.0 SVG snapshots under the ISC/MIT notices; Flutter-template launcher artwork was replaced with original Hyfens fixture artwork; the maintainer-provided brand-guideline SVG mark was recorded as project-owned with separate trademark treatment; `docs/ASSET_PROVENANCE.md`, `THIRD_PARTY_NOTICES.md`, and conservative `TRADEMARKS.md` were completed; `CONTRIBUTING.md` retained DCO-only/no-CLA guidance; and the root Apache-2.0 text remained canonical.
- 2026-09-02: Final validation passed: dashboard tests (30), root bootstrap test, control-plane analysis and targeted tests, CLI analysis and targeted tests, Flutter integration analysis/tests, fixture artwork test, instrumentation exception tests, shell syntax, image builds and image filesystem scans, self-host Compose interpolation, dashboard runtime smoke, CLI release version check, and macOS arm64 CLI archive inventory. The staged candidate contained 588 files and passed the scoped path, secret-marker, icon-family, and whitespace scans.
- 2026-09-02: Public image Dockerfiles were adjusted to build from the public root context and copy `LICENSE` plus `THIRD_PARTY_NOTICES.md` into both image filesystems. No protected repository or existing local service was modified.
- 2026-09-02: Created and pushed `https://github.com/hyfens-hq/hyfens` as PUBLIC with default branch `main`; clean signed initial commit `3b3a2e3c0ab9b3ba3934b69b8f9249b328fb25fa` was pushed. GitHub license detection recognized Apache-2.0, README/workflows/self-host files were verified, no release tag was created, and read-only checks confirmed `backend` and `frontend` remained PRIVATE and unchanged.
