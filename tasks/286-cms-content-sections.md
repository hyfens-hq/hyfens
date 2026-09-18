# CMS content sections

Status: [*] In Progress

## Goal

Extend the control-plane editorial contract so the Cloud web CMS can manage and publish separate blog, article, press-release, news, and policy records without creating a second identity or storage boundary.

## Scope and Non-goals

Scope:

- Add `article` and `press` to the typed content-kind enum and parsing contract.
- Permit authorised CMS/platform operators to list, create, update, publish, archive, and read published records of those kinds.
- Preserve existing tenant `content:admin` authorization and content-kind immutability.
- Add tests for the new kinds and platform CMS authorization.

Non-goals:

- Rich media or HTML rendering.
- Changing existing content records or legal wording.
- Changing public site routes; those are owned by the private Cloud web repository.

## Owner

Control-plane content service

## Dependencies

- Private Cloud web task 302 for UI and route consumption.
- Existing human-auth platform capability catalogue.

## Assumptions

- `press` is the stable API kind for press releases/newsroom items.
- Managed platform `admin` and protected `super-admin`/owner sessions may manage CMS records through the existing CMS endpoints.
- Existing customer memberships with `content:admin` remain supported.

## Work Items

- [x] Extend content kinds and error contract.
- [x] Add platform CMS capability bridge without widening customer scopes.
- [x] Add focused tests and run the required control-plane validation.
- [*] Open a reviewable pull request.

## Validation

Completed:

- `dart analyze` from `packages/control_plane`: passed.
- Focused `dart test test/content_policy_test.dart test/human_auth_test.dart test/platform_commercial_capability_test.dart`: passed.
- Full `dart test`: 374 passed, 34 skipped, 27 failures outside this package's changed content/CMS surface (credential-scope, reconciliation, and auto-halt suites); no new focused test failed.

## Next Action

Commit, push, and open the reviewable control-plane pull request.

## Blockers

None currently.

## Outcome

Pending.

## References

- `packages/control_plane/lib/src/content.dart`
- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/service.dart`
- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/test/content_policy_test.dart`

## History

- 2026-09-18: Reserved task 286 on `feat/cms-content-sections` after confirming the existing API only accepts blog/news/policy.
- 2026-09-18: Added article/press kinds, platform CMS capability mapping, customer-scope preservation, focused authorization/content tests, and updated the public deployment note for all editorial kinds.
