# Task 303: Branch retention and security integration audit

Status: [*] In Progress

## Goal
Audit remaining branches, preserve needed functionality and data, and integrate reviewed, validated changes through pull requests.

## Scope and Non-goals
Scope: local remaining branches, CLI/MCP and release/security worktree changes, historical equivalence, PR review and safe cleanup. Non-goals: deployments, data migrations, rewriting public history, unrelated features.

## Owner
Coordinator; independent read-only standards and requirements reviewers.

## Dependencies
Current upstream main, available Flutter/Dart toolchain, GitHub review and merge requirements.

## Assumptions
Historical branches must not be merged wholesale across the sanitized public history boundary. Completed task records remain immutable except appended evidence. Unmerged useful work is retained if integration is blocked.

## Work Items
- [x] Archive all local refs and tracked/untracked work before changes.
- [x] Classify retained branches against current source and historical integration evidence.
- [x] Review the complete security diff and fix substantiated regressions.
- [ ] Run required validation, create PR, obtain review, and merge only if safe.
- [ ] Remove redundant branches and report retained blockers.

## Validation
Inspect branch patch equivalence and source behavior; git diff --check; OSS boundary scan; Dart analysis and repository package tests with Flutter for Flutter-dependent packages; release workflow and packaging checks. Full relevant repository validation is required before PR integration. Record toolchain limitations and do not treat failed checks as passes.

## Next Action
Finish branch equivalence and independent reviews, then validate the consolidated changes.

## Outcome
Recovery Git bundles and source archives were verified outside the repository before mutation. Retain the security branch for PR integration. Historical deletion hardening is patch-equivalent to the integrated history. The two historical notification branches were superseded by the later main integration and subsequent approved OSS boundary restoration. The older runtime branch contains unique visual/manual-control work against a pre-restoration tree; merging it wholesale would restore deliberately removed implementation and history. Preserve that work in the recovery bundle rather than republishing it or claiming it is merged.

Independent requirements and standards reviews identified credential-store resurrection after fallback/logout, macOS terminal-password prompting, secret creation before Windows ACL protection, and mandatory optional-bundle configuration. Fixed these with endpoint authority markers, bounded stdin-only Keychain commands, protected empty-file staging, and optional paired bundle trust configuration. Follow-up independent review found no remaining concrete merge blockers in the fixes.

### Validation evidence (2026-09-22)
- All analyzed repository packages and root analysis passed.
- Full CLI suite: 171 passed. Separate focused security cases: 33 passed; an initial command named two nonexistent test files, then the corrected auth/profile selection passed 7 tests. No failed source assertions remain in these checks.
- Dashboard: 30 passed. Root: 1; compiler: 1; instrumenter: 2; patch format: 12; runtime: 5; patch-loading: 59 passed, 2 environment skips.
- Instrumentation: 204 passed initially with three Flutter-launcher failures; all three passed after supplying the correct FLUTTER_ROOT.
- Control plane: 258 passed, 34 external/environment skips, 16 failures. All 16 failures reproduce on unchanged upstream main in an isolated checkout; they are pre-existing reconciliation/applicability failures.
- Flutter integration: 19 passed, one rollback-route 404 failure. The same failure reproduces on unchanged upstream main. Stale generated hook cache was moved to the recovery directory before retry, preserving recovery.
- Isolated temporary Keychain round-trip passed for stdin hex data including quotes, backslashes and Unicode; the test keychain was removed. No real credentials were read or altered.
- OSS boundary, git diff --check, and staged-source Gitleaks scan passed. No release or deployment was performed.
- Windows/Linux native credential APIs were reviewed and injectable boundaries tested; real platform runtimes remain external verification.

## Blockers
Upstream main requires one independent approval and approval by someone other than the last pusher. Only the authenticated maintainer is listed as a collaborator. Do not bypass the review rule. Existing baseline failures are disclosed separately rather than reported as passing.

## References
Tasks 289–302; current security branch; upstream main.

## History
- 2026-09-22: Authorized audit, PR review/integration, and redundant branch cleanup. Recovery copies created before changes; production inspection is read-only.
- 2026-09-22: Completed independent reviews, corrective batch, source secret/boundary scans and full available validation. Verified existing reconciliation and rollback-route failures against unchanged main. PR integration remains subject to the repository review gate.
