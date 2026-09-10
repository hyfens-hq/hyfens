# Productization PRD

Status: DESIGN ONLY — NO PRODUCTION IMPLEMENTATION

This PRD translates the validated local Flutter runtime/toolchain into a
maintainer-reviewable product direction. It is not authorization to build
cloud services, hosted delivery, dashboards, accounts, billing, rollout
infrastructure, or other production product infrastructure.

## 1. Product thesis

Hyfens is a Flutter-first OTA patch platform for teams that want ordinary
Dart/Flutter source changes to move through a controlled, signed, reversible
patch lifecycle without adopting a Flutter/Dart fork or rewriting application
call sites.

The validated foundation is:

~~~text
ordinary Flutter/Dart source
        ↓
automatic build-time source instrumentation
        ↓
normal Flutter AOT fallback
        +
bounded patch dispatch
        ↓
signed interpreted patch runtime
~~~

The product promise is narrower than “arbitrary Dart OTA”:

- supported source changes are discovered, analyzed, compiled, signed, and
  bound to an exact release automatically;
- unchanged code remains native AOT;
- patches are capability-limited and cryptographically verified on-device;
- delivery, rollout, and telemetry can influence eligibility and observation,
  but never runtime validity;
- rollback and recovery are fail-closed and retain anti-replay high-water.

## 2. Personas and jobs to be done

| Persona | Job to be done | Required confidence |
| --- | --- | --- |
| Flutter developer | Turn a supported ordinary source edit into a verified patch with clear diagnostics | No bytecode, function IDs, or manifest construction |
| Release engineer | Register immutable releases, build/sign patches, promote safely, and recover from failure | Idempotency, exact release binding, auditability |
| Application owner | Decide which environments and teams may receive a patch | Explicit policy and approval boundaries |
| Security manager | Control signing trust, key rotation, revocation, and production approvals | Private-key separation and append-only audit |
| Self-host operator | Run artifact/control services without depending on Hyfens hosting | Documented storage, backups, upgrades, and air-gap path |
| Enterprise administrator | Apply identity, access, retention, residency, and network policies | Tenant isolation and integration boundaries |
| Maintainer | Keep runtime, protocol, CLI, and hosted layers evolvable without protocol drift | Versioned contracts and evidence-backed compatibility |

## 3. Product scope

### Initial product scope

- Flutter-first local CLI and runtime;
- immutable release and patch registration;
- local/self-hosted control and artifact services;
- signed patch verification and exact-release filtering;
- all-or-none environment promotion;
- developer-local status and bounded optional runtime observations;
- a transparent audit model;
- documented self-hosted deployment and offline artifact movement.

### Later product scope

- managed hosted control/distribution;
- team and organization access;
- staged rollouts and deterministic cohorts;
- optional privacy-preserving health observation;
- enterprise identity, audit export, managed signing, private networking,
  on-premises, and air-gapped operations.

### Explicit non-goals for this design phase

No backend, database migration, REST server, CDN, dashboard, authentication
provider, billing, KMS integration, telemetry ingestion, rollout scheduler,
enterprise SSO, React Native runtime, production deployment, or store
submission is implemented.

## 4. Frozen technical principles

Product layers must not:

- weaken Patch Format v1 or capability v1;
- make a server signature or database record substitute for runtime signature
  verification;
- lower or reset the runtime high-water;
- make a wrong-release artifact valid through metadata rewriting;
- require cloud connectivity for local runtime correctness;
- add arbitrary host reflection, native enumeration, or unbounded host objects;
- claim App Store, Play, GDPR, DPDP, SOC 2, ISO, or other compliance without a
  separate authoritative review.

Product metadata is outside Patch Format v1. Product records reference signed
artifact identities and release IDs; they do not mutate the patch protocol.

## 5. Developer journeys

### Local/self-hosted

1. Developer runs doctor and init.
2. Release build produces an immutable release identity and registers it locally
   or with a selected self-hosted endpoint.
3. Developer edits supported ordinary Dart/Flutter source.
4. Analyze classifies changes; unsupported/native changes fail closed.
5. Patch compiles, signs, verifies, and records an immutable artifact.
6. Deploy promotes the artifact to an environment subject to policy.
7. Runtime checks an untrusted update endpoint, verifies the artifact locally,
   confirms health, and retains AOT fallback.
8. Developer inspects status and can authorize base rollback without reinstall.

### CI

A service account or short-lived CI credential:

- resolves an explicit project/application/environment;
- reuses or verifies an immutable release baseline;
- builds a patch from a pinned toolchain;
- verifies digest/signature locally;
- uploads by content identity;
- uses an idempotency key;
- requests promotion or creates a rollout proposal;
- emits machine-readable results and a request ID.

### Incident recovery

- pause delivery eligibility;
- preserve installed runtime state;
- issue a release-bound signed rollback control or promote a known-good artifact
  above high-water;
- inspect optional observations without treating them as authoritative;
- append audit events;
- never “fix” an incident by deleting high-water or rewriting release identity.

## 6. Product requirements

### Release and patch

- immutable application/platform/environment/release identities;
- exact tool/runtime/format/capability compatibility;
- deterministic patch analysis and artifact identity;
- signed artifacts and explicit key ownership;
- local inspect/verify before upload;
- idempotent registration and upload;
- rejection of mixed unsupported/native changes;
- clear store-release-required diagnostics.

### Delivery

- versioned update lookup and artifact fetch;
- immutable/content-addressed artifacts;
- cache validators and digest checks;
- offline/base fallback behavior;
- server-side eligibility filtering only;
- runtime-side signature, release, sequence, capability, budget, and health
  authority.

### Operations

- audit for release, patch, signing, rollout, rollback, access, policy, and
  token changes;
- pause and emergency controls;
- retention and deletion policies that preserve trust metadata;
- self-host backup/restore and air-gap import/export procedures;
- health and availability signals distinct from runtime truth.

## 7. Competitive requirement classification

The detailed competitor evidence remains in docs/competitors/shorebird.md and
docs/competitors/ejenix.md. Product claims must use the following classification:

| Capability | Classification | Rationale |
| --- | --- | --- |
| Normal-source automatic discovery/instrumentation without annotations or PatchView | FIRST CREDIBLE PRODUCT | Core validated developer-experience target |
| Exact-release signed Patch Format v1 and closed capability authority | DIFFERENTIATOR | Public, inspectable runtime trust boundary |
| Native AOT fallback with bounded interpreted changed code | FIRST CREDIBLE PRODUCT | Architecture B behavior, with explicit subset limits |
| Local CLI, offline verification, rollback, and self-hostable base | COMPETITIVE PARITY | Required baseline for serious OTA tooling |
| Hosted release/patch registry and immutable artifact delivery | COMPETITIVE PARITY | Expected control/distribution function |
| Staged rollout, cohorts, pause, and emergency controls | COMPETITIVE PARITY | Needed before a credible managed release |
| Open protocol/runtime/compiler and minimal self-host path | DIFFERENTIATOR | Deployment and security transparency |
| Managed KMS/HSM, SSO/RBAC, audit export, private networking | FUTURE / ENTERPRISE | Valuable but not an initial OSS gate |
| Cross-framework control-plane abstractions | FUTURE | Keep domain-neutral; no RN runtime implementation |
| App Store/Play approval or compliance guarantee | OUT OF SCOPE | Requires independent legal/policy evidence |

No superiority claim is inferred from this table. Competitor documents separate
public facts, inferences, and unknowns.

## 8. Packaging and ownership direction

The recommended product modes are:

- Community: open-source runtime, protocol, CLI, compiler/instrumenter,
  verification libraries, local status/rollback tooling, and minimal
  self-hosted development service.
- Managed Cloud: hosted control/distribution operations, managed availability,
  optional observations, team workflow, and support.
- Team/Business: shared environments, approvals, audit retention, and
  operational policy.
- Enterprise: SSO/SCIM, advanced RBAC, residency/retention, private networking,
  customer-managed keys, on-premises, air-gap, and SLA/support.

Pricing is intentionally not defined here.

## 9. Security, privacy, and policy

The hosted/control plane is untrusted from the runtime's perspective. It may
filter, delay, or fail to deliver; it cannot authorize invalid code.

Required design controls include tenant isolation, short-lived credentials,
append-only audit, signed/replay-protected webhooks, artifact immutability,
key separation, secret redaction, optional telemetry, retention/deletion,
self-host hardening guidance, and air-gap import verification.

Downloaded interpreted behavior requires a dedicated Apple/Google policy and
legal review. This PRD makes no store-approval claim.

## 10. Design metrics

Later implementation should measure, without inventing targets prematurely:

- source edit to deployable patch duration;
- patch artifact size and upload time;
- update lookup latency and cache hit rate;
- verification/activation/health success;
- rollback success and time to safe state;
- runtime-fault and rejection rates;
- control-plane/artifact availability;
- self-host setup and upgrade time;
- CLI diagnostic clarity and failure recovery;
- tenant-isolation and security incidents;
- telemetry opt-out and data-retention behavior.

Each metric needs a measurement definition, population, sampling policy, and
failure interpretation before becoming an SLO or launch gate.

## 11. Risks and open decisions

- The supported Dart/Flutter subset may limit the addressable patch surface.
- Interpreted execution is not native-equivalent and must remain outside hot-frame
  assumptions until measured.
- Phase 1D iOS logs/performance and adjacent-SDK full workflow remain limited.
- Independent customer-application validation is still absent.
- Store policy for downloaded interpreted behavior requires authoritative review.
- OSS licensing is currently pending and must be decided before publication.
- Managed signing changes the trust/operator model and must be an explicit mode.
- Tenant and audit data require privacy, residency, retention, and deletion
  decisions.
- A hosted outage must never corrupt installed state.

## 12. Roadmap boundary

The staged roadmap, architecture documents, ADRs, and API/domain specification
are the design source of truth. No stage below authorizes implementation in
this task:

- P0: productization foundations and protocol/domain decisions;
- P1: smallest local/self-hosted control/distribution slice;
- P2: managed hosting;
- P3: rollout and optional observability;
- P4: teams, RBAC, and audit;
- P5: enterprise/on-premises/air-gap;
- P6: framework-expansion research.
