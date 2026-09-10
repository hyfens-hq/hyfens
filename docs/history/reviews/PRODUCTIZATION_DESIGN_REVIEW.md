# Productization Design Review

Status: DESIGN ONLY — NO PRODUCTION IMPLEMENTATION

This review integrates the Task 40 design packages after Phase 1D. It is a
maintainer decision artifact, not authorization to build cloud/product
infrastructure.

## 1. Recommendation

~~~text
PROCEED TO PRODUCTIZATION IMPLEMENTATION WITH CONDITIONS
~~~

This is a recommendation for maintainer review only. No implementation phase
has started.

Conditions before implementation:

1. approve an OSI-compatible license and contribution/governance policy;
2. approve the OSS/commercial boundary without putting runtime trust or
   Patch Format v1 behind a hosted service;
3. resolve the P1D-13 production delivery/key-custody contract;
4. preserve every Phase 1D limitation and owner in
   docs/product/phase-1d-conditions.md;
5. complete a P0 implementation-readiness review covering tenant isolation,
   authenticated delivery, artifact immutability, signing/recovery, and
   store-policy/legal boundaries.

The recommendation does not authorize backend services, migrations, REST
servers, CDN integration, dashboards, accounts, billing, KMS integration,
telemetry ingestion, rollout scheduling, enterprise SSO, React Native, or
production deployment.

## 2. Product positioning and competitive requirements

Hyfens is positioned as a Flutter-first, local-first OTA patch platform for
supported ordinary Dart/Flutter source changes. Its credible promise is:

- automatic source discovery and instrumentation;
- no PatchView, per-function annotation, manually supplied source units, or
  rewritten call sites in the supported workflow;
- native AOT fallback for unchanged code;
- bounded interpreted execution for signed supported patches;
- exact release binding, closed capabilities, health confirmation, rollback,
  and retained anti-replay high-water.

The detailed competitor classification is in
docs/product/positioning.md. The essential categories are:

- FIRST CREDIBLE PRODUCT: transparent normal-source workflow around
  Architecture B and an auditable open runtime boundary;
- COMPETITIVE PARITY: local CLI, release/patch workflow, rollback, immutable
  artifacts, hosted/self-host delivery, and basic rollout controls;
- DIFFERENTIATOR: open protocol/runtime/compiler surface, self-hosting, and
  deployment/security transparency;
- FUTURE: managed KMS/HSM, advanced enterprise controls, cross-framework
  abstractions, and deeper fleet operations;
- OUT OF SCOPE: arbitrary-Dart claims, store approval, compliance claims, and
  React Native implementation.

Shorebird and Ejenix research remains evidence-labelled as FACT, INFERENCE, or
UNKNOWN. No competitor internals were copied and no unsupported superiority
claim is made.

## 3. OSS, commercial, and repository boundary

The design recommends a broad open-source core:

- Patch Format v1 and capability v1 specifications/conformance vectors;
- Flutter runtime, verifier, interpreter, generated bootstrap, state-v4
  lifecycle, fallback, rollback, and local status tooling;
- source instrumenter, bounded compiler, source maps, diagnostics, and
  compatibility analysis;
- local CLI, local signing/verification tooling, minimal self-host reference
  path, and protocol/domain documentation.

Managed hosting, managed distribution operations, hosted observations,
availability, collaboration, support, SSO/SCIM, advanced RBAC, private
networking, customer-managed KMS/HSM, on-premises packaging, air-gap support,
custom retention, and SLA commitments are commercial/enterprise candidates.

The open-core proposal is conditional on maintainer/legal approval. The current
LICENSE is a placeholder and grants no distribution permission. No component
classification changes the current license.

Repository options were evaluated:

- one monorepo: preferred initially for protocol/runtime/compiler/CLI
  conformance and coordinated releases;
- two repositories: possible later separation of open runtime and hosted
  service, but creates version/protocol/release friction too early;
- many repositories: deferred until ownership, API stability, and independent
  release cadence justify the cost.

The repository/governance decision is documented in
docs/architecture/oss-commercial-boundary.md and ADRs 0004–0005.

## 4. Domain and tenancy model

The recommended root tenant is Organization. Users are global identities with
explicit organization memberships; a human being present in two organizations
does not share data between them.

The domain model defines all required entities:

User, Organization, Team, Project, Application, Platform, Environment,
Release, Patch, PatchArtifact, SigningKey, TrustPolicy, Rollout, Cohort,
Installation, RuntimeObservation, Diagnostic, AuditEvent, ApiToken,
ServiceAccount, Webhook, and EnvironmentPolicy.

Control-plane API IDs are opaque and tenant-scoped. Runtime identities remain
separate and exact:

- runtime application ID maps to Patch Format v1 application ID;
- runtime release ID maps to Patch Format v1 release ID;
- runtime patch ID and sequence map to signed patch identity;
- artifact ID is the exact bytes digest.

Every customer-owned object has one organization ownership path. Authorization
must derive tenant context from credentials and resource ownership, never from
a caller-supplied organization ID alone. Cross-tenant reads should use the
same not-found shape as unknown resources.

Tenant isolation covers applications, environments, artifacts, keys, trust
policies, audit events, observations, billing metadata, caches, queues,
webhooks, and exports. Cross-tenant threats and ID enumeration are documented
in docs/architecture/domain-tenancy.md.

## 5. Control-plane architecture

The product topology is:

~~~text
Developer CLI
    ↓
local release/patch compiler
    ↓
signing boundary
    ↓
control plane
    ↓
distribution plane
    ↓
Flutter runtime
~~~

The control plane owns product metadata and administrative intent:

- resource registration and lifecycle;
- release/patch/artifact catalog;
- environment policy and rollout eligibility;
- trust metadata and administrative key intent;
- audit, access, webhooks, and optional observation intake.

It must not execute patch code, decide runtime health, rewrite Patch Format v1,
clear high-water, add capabilities, or select executable state.

The control-plane design is in docs/architecture/control-plane.md.

## 6. Distribution architecture

Artifacts are immutable and content-addressed. Candidate storage options are:

- local filesystem for development;
- object storage plus CDN for managed scale;
- S3-compatible storage for self-hosting;
- private HTTP/CDN for enterprise;
- signed export/import bundles for air-gapped environments.

A CDN, object store, HTTP endpoint, cache, or operator is cryptographically
untrusted. Runtime verification remains mandatory for every artifact. Signed
URLs are transport authorization, not patch trust.

Distribution may return no update, an artifact reference, a rollback-control
reference, or a blocked decision. It may not alter bytes, lower high-water, or
make an incompatible artifact valid.

The full trust and distribution design is in
docs/architecture/distribution-trust.md and ADR 0007.

## 7. Signing, KMS, and trust architecture

Supported design modes are:

- developer-managed local signing;
- organization-managed signing;
- CI signing through short-lived authorization;
- offline/air-gapped signing;
- managed KMS/HSM signing as an optional future service mode.

Provider adapters for AWS KMS, Google Cloud KMS, Azure Key Vault, Vault, or
customer HSMs are design seams only. None is implemented or selected here.

Private signing keys should not cross a hosted control plane unless an
explicit managed-signing mode is selected with its own consent, custody,
approval, audit, recovery, and compromise model.

Trust changes remain release-owned and signed. Rotation, retirement,
revocation, recovery anchors, rollback controls, high-water, and artifact
identity must use the existing controller authority. An unknown key cannot
self-authorize.

ADR 0008 and docs/security/productization-threat-model.md define the proposed
trust model.

## 8. Release, patch, rollout, and runtime state models

Product states are separate from runtime states.

Product release/patch states may include:

~~~text
DRAFT → BUILT → SIGNED → VERIFIED → READY
READY → ROLLOUT_PENDING → ACTIVE → PAUSED → COMPLETED
ACTIVE → SUPERSEDED | REVOKED | ROLLED_BACK | FAILED
~~~

These describe control-plane catalog and delivery intent. They do not replace
runtime BASE, CANDIDATE, PENDING_HEALTH, HEALTHY, LAST_KNOWN_GOOD, FAILED, or
ROLLED_BACK behavior.

Rollout states govern eligibility only. Runtime still performs signature,
exact-release, sequence/high-water, capability, budget, health, and fallback
checks.

The state separation and rollout model are documented in
docs/architecture/control-plane.md and
docs/architecture/rollouts-observability.md.

## 9. Runtime delivery API

The proposed customer/control API is versioned independently from Patch Format
v1. The design uses /v1 REST/domain semantics with opaque API IDs and exact
runtime identity fields.

The bounded runtime lookup contract may carry:

- application/release/platform/runtime identity;
- environment;
- current sequence and high-water digest;
- runtime compatibility;
- privacy-preserving installation pseudonym;
- optional capability/runtime status metadata that cannot authorize code.

Conceptual decisions:

~~~text
NO_UPDATE
PATCH_AVAILABLE
ROLLBACK_CONTROL
UPDATE_BLOCKED
STORE_RELEASE_REQUIRED
~~~

Artifact fetch is immutable and digest-addressed. Responses support cache
validators/ETag, explicit digests, bounded retries/backoff, offline fallback,
timeouts, idempotency, and safe error classes. The server never lowers
high-water.

The human/CI API separately defines authentication, pagination, request IDs,
rate limits, optimistic concurrency, idempotency keys, error envelopes,
authorization, and signed replay-protected webhooks.

Examples and schemas are in docs/spec/product-api-domain.md. This is not an
OpenAPI implementation.

## 10. Developer and CI workflows

Local flow remains:

~~~text
tool doctor
tool init
tool keys generate
tool release android|ios
tool analyze
tool patch
tool inspect <patch>
tool verify <patch> --release <release-id>
tool rollback --to base
tool status
~~~

A later hosted/self-host flow may add:

~~~text
tool login
tool deploy
tool promote
tool rollout pause
tool rollback
~~~

Hosted commands must preserve local build/sign/verify/self-host options.

CI uses organization-scoped service accounts or short-lived tokens with
explicit project/application/environment scopes. The design requires
idempotent release registration, patch upload, promotion, rollback requests,
machine-readable output, request IDs, and no private key logging.

No login service, deploy command, service account, or hosted flow is
implemented by this task.

## 11. Installation identity and privacy

Installation identity should be a random app-scoped pseudonym generated locally,
stored privately, and rotatable. It must not use IMEI, advertising ID, hardware
serial, phone number, contacts, or unrelated identity.

A cohort assignment is derived from an explicit app/environment/rollout
namespace and installation pseudonym. The product must document reset and
reinstall behavior; it must not silently correlate identities across apps or
organizations.

Runtime correctness cannot depend on installation identity or telemetry. A
missing, stale, spoofed, or opt-out identity changes delivery eligibility at
most; it cannot bypass runtime verification.

## 12. Observability and telemetry

Optional observations may include:

- release_seen;
- patch_offered, downloaded, verified, activated, healthy, rejected;
- runtime_fault;
- rollback_applied;
- base_active.

Telemetry is incomplete, delayed, sampled, spoofable, and non-authoritative.
The runtime must never wait for telemetry to activate safely, mark health, or
recover.

Default design requirements:

- opt-out and enterprise disablement;
- minimal payloads and data minimization;
- no source snapshots, private keys, absolute paths, secrets, or patch bytes;
- bounded sampling and retention;
- deletion/export controls;
- separate security/audit events from optional health observations.

The existing tool status command remains developer-local. No unauthenticated
remote introspection is introduced.

## 13. Dashboard information architecture

A later dashboard may contain only operationally useful areas:

- Overview;
- Applications;
- Releases;
- Patches;
- Rollouts;
- Installations/Runtime Health;
- Diagnostics;
- Signing/Keys;
- Audit Log;
- Team/Access;
- Settings.

The dashboard must prioritize exact release identity, rollout state, trust
status, diagnostics, rollback, and audit over vanity analytics. It must never
display telemetry as cryptographic truth or provide an unsafe “force activate”
operation.

At the time of this design review, no dashboard was implemented. Task 95
subsequently adds only a local, read-only, single-tenant operator view.
Hosted dashboard features and human-session/RBAC dashboard access remain
unimplemented.

## 14. Auth, RBAC, approvals, and audit

Human sessions, PATs, service accounts, and short-lived CI credentials are
separate credential classes. Tokens are scoped to one organization and
explicit resources; secrets are shown once, stored hashed where possible, and
revocable/expirable.

Candidate roles:

- Owner;
- Admin;
- Developer;
- Release Manager;
- Security Manager;
- Viewer;
- Billing Admin.

Production environments may require two-person approval, protected
environments, key-change approval, restricted rollback, and signed CI
provenance. These are policy options, not runtime trust replacements.

Audit events are append-only and cover authentication, resource access,
release/patch/signing/deploy/rollout/rollback/key/RBAC/token/policy changes.
Events carry actor, organization, request ID, resource, action, result, time,
and redacted metadata. Retention/export and customer-controlled audit copies
are design responsibilities.

## 15. Self-hosted, on-premises, and air-gapped operation

The proposed progression is:

- L0 local development adapter;
- L1 single-node Docker Compose;
- L2 production containers with external PostgreSQL and S3-compatible object
  storage;
- L3 optional Redis/Valkey, queues, external TLS, backups, and multi-node
  services;
- L4 customer Kubernetes/on-premises;
- L5 air-gapped offline import/export and private distribution.

Self-hosting transfers responsibility for host security, TLS, secrets, storage,
backups, upgrades, monitoring, signing custody, and incident recovery to the
operator. The product must not imply that a Compose file is an HA or
production guarantee.

Air-gap flow:

1. register/verify release offline;
2. build and sign patch with an approved offline key;
3. export immutable artifact and signed metadata;
4. transfer through approved media;
5. import and verify digest/signature/release identity;
6. distribute through private endpoints;
7. export audit/health observations only when policy allows.

No deployment scripts or production container manifests are implemented.

## 16. Scale, SLO, HA, and DR

The scale design uses small/medium/large scenarios with explicit assumptions
for organizations, applications, releases/day, patches/day, installations,
update checks/sec, artifact bandwidth, and observations/sec. It does not
invent capacity targets.

Candidate SLO dimensions are:

- control-plane API availability/latency;
- update lookup availability/latency;
- artifact availability and digest correctness;
- rollout propagation delay;
- dashboard/API availability;
- audit durability;
- backup/restore success;
- RPO/RTO by offering.

Targets require measured workload and offering-specific review.

Failure domains include API, database, object store, cache, queue, CDN, KMS,
identity provider, region, and operator. A hosted outage must leave installed
runtime state and AOT fallback untouched. Recovery must restore metadata and
artifacts without lowering runtime high-water or rewriting signed identities.

See docs/architecture/scale-ha-dr.md.

## 17. Productization security threat model

The extended threat model covers:

- tenant isolation and ID enumeration;
- account/token theft and malicious insiders;
- artifact, control-plane, CDN/object-store, KMS/HSM compromise;
- signing-key compromise and recovery;
- rollout/rollback abuse;
- telemetry spoofing and webhook replay;
- SSRF, supply-chain compromise, and self-host misconfiguration;
- air-gap import tampering;
- audit deletion/repudiation;
- rooted or fully compromised devices.

The final client-side boundary remains runtime signature verification, exact
release binding, capability v1, resource limits, high-water anti-replay,
health confirmation, rollback, and AOT fallback.

Details are in docs/security/productization-threat-model.md.

## 18. Privacy and compliance boundaries

Data categories:

- required: identities, tenancy, release/patch/artifact metadata, access
  policy, signing/trust metadata;
- optional: installation pseudonym, rollout eligibility, runtime observations;
- security/audit: auth, approvals, key and policy changes, audit events;
- billing/support: future commercial records and support case metadata.

The design requires retention, deletion, export, residency, processor/
subprocessor, access, and customer-controlled storage decisions before managed
operation. It does not claim GDPR, DPDP, SOC 2, ISO, or other compliance.

## 19. Store-policy gate

Store policy is independent from runtime correctness and technical signing.

Before any store-facing production claim, conduct a dedicated Apple/Google
legal and policy review of downloaded interpreted behavior, patch scope,
network/update behavior, and each offering's operational claims.

No document or dashboard may say App Store compliant, Play approved, store
approved, or equivalent without authoritative app-specific evidence.

## 20. Flutter-first and React Native future boundary

v1 remains Flutter-first. Control-plane nouns such as Application, Release,
Patch, Artifact, Rollout, Installation, Telemetry, and Signing can remain
framework-neutral where useful.

Flutter source instrumentation, capability schemas, runtime compatibility, and
widget semantics remain Flutter-specific and must not be flattened into a
lowest-common-denominator API.

React Native is a future adapter/runtime research track only. No React Native
runtime, compiler, bridge, or product packaging is designed as an implementation
in this milestone.

## 21. Licensing and governance

The current license placeholder must be replaced only after maintainer/legal
approval. The design recommends a permissive OSS license for the open runtime,
protocol, compiler/instrumenter, CLI, verification libraries, and self-host
reference surface, subject to dependency and research-derived implementation
review.

Governance design includes:

- public roadmap and compatibility policy;
- security reporting and coordinated disclosure;
- release cadence and deprecation policy;
- contribution process;
- DCO versus CLA decision;
- maintainer ownership and release authority;
- third-party notices and independent implementation review.

No license change is made here.

## 22. Product packaging

Candidate offerings, without final pricing:

- Community / OSS self-hosted;
- Managed Cloud;
- Team/Business;
- Enterprise.

Community must retain useful local correctness and self-host capability.
Managed offerings sell operations, availability, collaboration, and support.
Enterprise adds identity, policy, residency, private networking, on-premises,
air-gap, managed/customer KMS/HSM, retention, and SLA options.

Pricing, packaging economics, and commercial plans require separate
authorization.

## 23. Phase 1D limitation disposition

The complete condition register is in docs/product/phase-1d-conditions.md.
The key dispositions are:

| Condition | Disposition |
| --- | --- |
| Physical power-loss not tested | BLOCKER BEFORE BETA |
| Direct stale-byte runtime rejection not physically proven | BLOCKER BEFORE BETA |
| iOS logs/UI unavailable | BLOCKER BEFORE BETA for iOS track |
| iOS performance not run | BLOCKER BEFORE BETA for iOS performance claims |
| Fresh Android 15-sample performance reducer not run | BLOCKER BEFORE BETA for performance claims |
| Adjacent 3.47.1 full CLI/device path not isolated | ACCEPTED LIMITATION |
| Independent application validation absent | BLOCKER BEFORE BETA |
| Additional async benchmark not run | BLOCKER BEFORE BETA for async claims |
| Host stage attribution incomplete | BLOCKER BEFORE PRODUCTION for performance claims |
| Physical multi-function behavior not established | BLOCKER BEFORE BETA for multi-function claims |
| Raw evidence is session evidence | BLOCKER BEFORE PRODUCTION for auditability claims |
| Production server/key-custody contract absent | BLOCKER BEFORE IMPLEMENTATION for hosted path |
| Rooted-device protection absent | ACCEPTED LIMITATION |
| Store-policy classification unresolved | BLOCKER BEFORE PRODUCTION for policy claims |
| Duplicate historical task 39 | ACCEPTED LIMITATION |
| Local observability only | ACCEPTED LIMITATION |
| Long power-loss/thermal/battery/hot-frame campaigns absent | ACCEPTED LIMITATION until marketed |
| Compliance/store approval absent | BLOCKER BEFORE PRODUCTION for such claims |

No limitation is hidden or reclassified as a product guarantee.

## 24. Staged implementation roadmap

The design roadmap is:

- P0 productization foundations: approve license, domain/API contracts,
  trust/distribution boundary, condition owners, threat/privacy/store gates,
  and implementation acceptance criteria.
- P1 minimal single-tenant/self-hosted slice: release registration,
  immutable artifact upload, authenticated lookup, CLI deploy, all-or-none
  environment promotion, runtime verification, and basic audit.
- P2 managed cloud: tenant isolation, hosted storage/control plane,
  credentials, availability/backup/DR, and measured operations.
- P3 staged rollout/observability: deterministic cohorts, pause/stop,
  optional observations, privacy controls, and conservative health policies.
- P4 teams/RBAC/audit: collaboration, approvals, protected environments,
  audit retention/export, and policy administration.
- P5 enterprise/on-prem/air-gap: SSO/SCIM, advanced RBAC, private networking,
  customer-managed signing, on-premises, offline operations, and support/SLA.
- P6 framework-expansion research: only after Flutter evidence, protocol
  stability, security review, and a separate maintainer decision.

Every stage has entry/exit criteria in
docs/architecture/product-roadmap.md. No stage is implemented here.

## 25. Smallest first implementation slice

The proposed first implementation slice is deliberately narrow:

- one organization/tenant;
- one application and explicit platform/environment;
- local or single-node self-host control plane;
- immutable release registration;
- signed Patch Format v1 artifact upload;
- authenticated update lookup and content-addressed fetch;
- all-or-none environment promotion;
- runtime still verifies signature, exact release, capability, sequence, and
  high-water;
- CLI deploy with idempotency;
- basic append-only audit trail;
- no rollout percentages, cohorts, billing, dashboard, organizations beyond
  the single tenant, managed KMS, or hosted telemetry.

Entry criteria:

- P0 contracts approved;
- license and repository boundary approved;
- P1D-13 trust/delivery contract resolved;
- artifact immutability and tenant boundary threat review passed;
- no runtime/protocol weakening.

Exit criteria:

- local/self-host reference workflow is reproducible;
- wrong release, bad signature, stale sequence, and unavailable server fail
  closed;
- runtime state remains recoverable during service failure;
- audit and idempotency behavior is demonstrated;
- no product claim exceeds the Phase 1D support matrix.

This slice is proposed only. It is not implemented.

## 26. Risks and open decisions

Open maintainer decisions:

- final OSS license and DCO/CLA;
- whether open-core is acceptable versus fully open hosted reference code;
- organization-rooted tenancy and API ID policy;
- managed signing opt-in and KMS/HSM responsibility;
- retention/residency/privacy defaults;
- exact P0/P1 condition gates and evidence ownership;
- whether a self-hosted reference server is required before any managed design;
- API protocol versioning and webhook scope;
- legal/store-policy review ownership;
- product metric baselines and SLO targets;
- future framework adapter criteria.

Primary risks:

- broad product claims could outrun the supported Dart/Flutter subset;
- hosted policy could accidentally become a runtime trust root;
- tenant/key/audit isolation could fail without implementation testing;
- managed signing could change the security model;
- self-host operational burden could exceed community capacity;
- store policy could constrain the product independently of technical validity.

The risk response is staged evidence and maintainer gates, not architecture
weakening or unsupported claims.

## Design boundary

This review closes the design-only work package for maintainer review. Its
historical design boundary contains no backend, database, API server, account
system, billing, KMS, telemetry, rollout scheduler, enterprise control plane,
React Native runtime, production deployment, or store submission. Task 95
adds only a local, read-only, single-tenant operator view; hosted and
human-session/RBAC dashboard functionality remains unimplemented.
