# Task 216: Public onboarding API

Status: [x] Completed

## Goal

Add a safe, durable public API for client account registration and for waitlist/newsletter intake. A new account must be bound to an explicitly configured organization and receive only the bounded client/read capability set; a caller must never choose an organization, role, or scope.

## Scope and Non-goals

Scope:

- Add `POST /v1/public/register` that validates email/password, creates an active client membership in the configured registration organization, and returns the existing session contract so the browser can continue without a second sign-in.
- Add fixed `POST /v1/public/waitlist` and `POST /v1/public/newsletter` routes with durable idempotent persistence in both supported stores.
- Add explicit configuration and local-Docker wiring for the registration organization.
- Preserve the existing auth/session and tenant authorization contracts.

Non-goals:

- Email verification, password reset, invitations, billing, CRM/admin management screens, or email delivery-provider integration.
- Caller-selected organizations, applications, environments, roles, or capabilities.
- Persisting plaintext passwords or logging submitted credentials/PII.

## Owner

Coordinator: Codex. Implementation owner: delegated `gpt-5.6-luna` worker, max reasoning, priority/fast service tier. The worker owns only the backend/API files listed in Work Items.

## Dependencies

- Task 215 dashboard typography/deployment baseline is complete.
- Existing `HumanAuthService`, `ControlPlaneStore`, CORS, transport, and rate-limit seams.
- Task 217 dashboard UI depends on the final route/body/response contract from this task.

## Assumptions

- `HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID` is required to enable active registration; absent configuration fails closed with a clear 503 response.
- The local helper will point this setting at the generated Local Hyfens organization after scope bootstrap and restart only the control-plane service as needed.
- Versioned public routes are required so configured API base paths such as `/p2/` remain routable; legacy root compatibility is not required for these new routes.
- Registration uses the existing minimum 12-character password policy and returns the existing `HumanLoginResult` shape.
- Waitlist and newsletter records are separate collections, keyed by a normalized-email digest for idempotency. The normalized email remains in the record because future delivery/admin workflows need it; no delivery is attempted by this task.

## Work Items

- [x] Add explicit discovery/config parsing and compose/example environment wiring for public registration.
- [x] Implement the client registration service/route with strict request fields, tenant binding, bounded client read scopes, duplicate-email handling, immediate session issuance, and auth/transport/rate-limit protection.
- [x] Implement waitlist and newsletter subscription service/routes with strict fields, normalization, idempotent duplicate behavior, bounded text, and durable persistence.
- [x] Initialize any new file-store collections and preserve PostgreSQL generic-record compatibility.
- [x] Add focused control-plane tests for configuration, registration, tenant/scopes, duplicate handling, intake persistence, and public HTTP behavior.
- [x] Update the local Docker helper and relevant API documentation without changing unrelated deployment services.

## Validation

Planned after implementation and review:

- `dart format` on changed Dart files.
- `dart analyze` for the control-plane package.
- Focused `dart test` for new onboarding tests plus directly affected auth/config/http tests.
- Shell syntax check for `scripts/local-dashboard.sh` and compose config validation.
- Live `curl` checks against the rebuilt local control plane for registration, duplicate registration, waitlist, newsletter, and login/session behavior.

## Next Action

Use the reviewed versioned API contract to complete task 217's dashboard UI, then run the consolidated Docker and live-flow validation.

## Blockers

None currently.

## Outcome

Implemented the server-owned public client registration and durable waitlist/newsletter intake boundary. Local registration is enabled by the generated organization ID written into the private local compose environment; no caller can select tenant, role, or scope.

## References

- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/lib/src/config.dart`
- `packages/control_plane/lib/src/persistence.dart`
- `scripts/local-dashboard.sh`
- `deploy/p2/docker-compose.yml`

Validation evidence:

- `dart analyze` — passed with no issues.
- Focused control-plane tests (`config_test.dart`, `human_auth_test.dart`, `human_auth_http_test.dart`, `public_onboarding_test.dart`) — 19 tests passed.
- `sh -n scripts/local-dashboard.sh` — passed.
- Docker Compose config validation — passed.

## History

- 2026-09-01: Reserved as the backend package for public client registration and waitlist/newsletter intake.
- 2026-09-01: Backend implementation reviewed and focused validation passed; public routes are versioned under `/v1/public/*` and intake body size is bounded.
