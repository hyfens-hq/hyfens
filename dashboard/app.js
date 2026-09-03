(() => {
  'use strict';

  const RESOURCE_KEYS = [
    'applications',
    'environments',
    'releases',
    'patches',
    'artifacts',
    'rollouts',
    'audit',
  ];
  const SESSION_STORAGE_KEY = 'hyfens-dashboard-session';
  const CUSTOMER_AUTHORIZATION_AUDIENCE = 'customer';
  const PLATFORM_AUTHORIZATION_AUDIENCE = 'platform';
  const PLATFORM_VIEWS = new Set([
    'platform',
    'platform-organizations',
    'platform-organization',
    'platform-audit',
    'platform-operations',
    'platform-users',
    'platform-entitlements',
    'platform-settings',
  ]);
  const PLATFORM_HOSTNAMES = new Set(['admin.hyfens.com', 'platform.hyfens.com']);

  const PAGE_COPY = {
    overview: {
      title: 'Overview',
      description: 'Authoritative record counts and the selected organization context.',
    },
    platform: {
      title: 'Platform overview',
      description: 'Operational measurements for the Hyfens platform instance.',
    },
    'platform-organizations': {
      title: 'Organizations',
      description: 'Customer organizations visible to the authorized platform operator.',
    },
    'platform-organization': {
      title: 'Organization detail',
      description: 'Bounded operational metadata for one customer organization.',
    },
    'platform-audit': {
      title: 'Security & audit',
      description: 'Platform-audience administrative and security events only.',
    },
    'platform-operations': {
      title: 'Operations',
      description: 'Control-plane service health and instance-level signals.',
    },
    'platform-users': {
      title: 'Platform users',
      description: 'Hyfens staff identities and explicit platform capabilities.',
    },
    'platform-entitlements': {
      title: 'Plans & entitlements',
      description: 'Read-only commercial and quota metadata for platform operations.',
    },
    'platform-settings': {
      title: 'Platform settings',
      description: 'Platform operator settings and access boundary.',
    },
    applications: {
      title: 'Applications',
      description: 'Runtime application identities returned by the control plane.',
    },
    environments: {
      title: 'Environments',
      description: 'Environment versions and promoted release pointers.',
    },
    releases: {
      title: 'Releases',
      description: 'Exact release identity, compatibility, signing, and build metadata.',
    },
    patches: {
      title: 'Patches',
      description: 'Exact patch sequence, artifact digest, state, and release linkage.',
    },
    artifacts: {
      title: 'Artifacts',
      description: 'Exact artifact digest, size, content type, and patch linkage.',
    },
    deployments: {
      title: 'Deployments',
      description: 'Immutable rollout snapshots. Runtime health is not inferred.',
    },
    audit: {
      title: 'Audit',
      description: 'Redacted organization audit records from the read-only projection.',
    },
    settings: {
      title: 'Settings',
      description: 'Human session, membership scope, endpoint, and account surfaces.',
    },
  };

  const RESOURCE_LABELS = {
    applications: 'Applications',
    environments: 'Environments',
    releases: 'Releases',
    patches: 'Patches',
    artifacts: 'Artifacts',
    rollouts: 'Deployment records',
    audit: 'Audit events',
  };

  const STATUS_FILTER_KEYS = new Set(['patches', 'artifacts', 'rollouts', 'audit']);

  const PUBLIC_INTAKE_COPY = {
    waitlist: {
      heading: 'Join the waitlist',
      description: 'Leave your details and we will share the next opening.',
      submit: 'Join waitlist',
    },
    newsletter: {
      heading: 'Get product updates',
      description: 'Receive occasional updates about the Hyfens developer platform.',
      submit: 'Get updates',
    },
  };

  const COLLECTION_SORT_OPTIONS = [
    { value: 'newest', label: 'Newest first' },
    { value: 'oldest', label: 'Oldest first' },
    { value: 'name-asc', label: 'Name A–Z' },
    { value: 'name-desc', label: 'Name Z–A' },
  ];

  const SAFE_AUDIT_RECORD_KEYS = new Set([
    'id',
    'requestId',
    'organizationId',
    'actorId',
    'action',
    'resourceType',
    'resourceId',
    'result',
    'metadata',
    'createdAt',
  ]);

  // Keep this in step with the control-plane audit projection. Unknown keys
  // are omitted at every depth, so a newly returned secret-shaped field is
  // not accidentally rendered or included in search text.
  const SAFE_AUDIT_METADATA_KEYS = new Set([
    'action',
    'actionDisposition',
    'aggregateId',
    'aggregateRevisionId',
    'aggregationVersion',
    'applicationId',
    'application_id',
    'artifactDigest',
    'artifactId',
    'artifact_id',
    'attempt',
    'attemptCount',
    'attemptNumber',
    'attempt_count',
    'attempt_number',
    'auditReference',
    'authorizedAt',
    'backoffDelaySeconds',
    'backoffState',
    'boundedCount',
    'bundleDigest',
    'bundleImportId',
    'checkedAggregates',
    'checkedCursors',
    'checkedDecisions',
    'checkedEvaluations',
    'checkedHaltApplications',
    'checkedRevisions',
    'code',
    'concurrent',
    'consecutiveFailures',
    'coverageState',
    'currentRolloutRevision',
    'currentVersion',
    'decision',
    'decisionId',
    'decision_id',
    'deletedCount',
    'diagnosticCode',
    'environmentId',
    'environment_id',
    'errorClass',
    'errorCode',
    'evaluationId',
    'evaluationInputDigest',
    'evaluation_id',
    'eventType',
    'expectedRolloutRevision',
    'expiresAt',
    'fromState',
    'freshnessState',
    'idempotent',
    'inventoryAvailable',
    'itemCount',
    'kind',
    'lastErrorCode',
    'lastOutcome',
    'lastRunOutcome',
    'maximumRecords',
    'nextDueAt',
    'outcome',
    'outcomeCount',
    'patchId',
    'patch_id',
    'percentageBasisPoints',
    'platformId',
    'policyDigest',
    'policyId',
    'policyVersion',
    'quarantinedCount',
    'readinessPhase',
    'reasonClass',
    'releaseId',
    'release_id',
    'reportOnly',
    'result',
    'resultingRolloutRevision',
    'retryPolicyVersion',
    'rolloutId',
    'rolloutRevision',
    'rollout_id',
    'scheduleId',
    'scheduleRevisionId',
    'sequence',
    'sha256',
    'sizeBytes',
    'state',
    'status',
    'storageMode',
    'toState',
    'truncated',
    'valid',
    'version',
    'workId',
    'workVersion',
  ]);

  const nodes = {
    loginView: document.querySelector('#login-view'),
    appView: document.querySelector('#app-view'),
    authModeTabs: [...document.querySelectorAll('[data-auth-mode]')],
    loginForm: document.querySelector('#login-form'),
    registerForm: document.querySelector('#register-form'),
    apiBase: document.querySelector('#api-base'),
    email: document.querySelector('#email'),
    password: document.querySelector('#password'),
    loginSubmit: document.querySelector('#login-submit'),
    loginMessage: document.querySelector('#login-message'),
    registerEmail: document.querySelector('#register-email'),
    registerPassword: document.querySelector('#register-password'),
    registerPasswordConfirm: document.querySelector('#register-password-confirm'),
    registerPasswordError: document.querySelector('#register-password-error'),
    registerSubmit: document.querySelector('#register-submit'),
    registerMessage: document.querySelector('#register-message'),
    intakeModeTabs: [...document.querySelectorAll('[data-intake-kind][role="tab"]')],
    intakeForm: document.querySelector('#public-intake-form'),
    intakeEmail: document.querySelector('#intake-email'),
    intakeName: document.querySelector('#intake-name'),
    intakeSource: document.querySelector('#intake-source'),
    intakeKindHeading: document.querySelector('#intake-kind-heading'),
    intakeKindDescription: document.querySelector('#intake-kind-description'),
    intakeSubmit: document.querySelector('#intake-submit'),
    intakeMessage: document.querySelector('#intake-message'),
    intakeSection: document.querySelector('#onboarding-intake'),
    discoveryCallout: document.querySelector('.discovery-callout'),
    discoveryStatus: document.querySelector('#discovery-status'),
    discoveryDetail: document.querySelector('#discovery-detail'),
    sidebar: document.querySelector('#sidebar'),
    platformSidebar: document.querySelector('#platform-sidebar'),
    sidebarBrand: document.querySelector('#sidebar-brand'),
    platformSidebarBrand: document.querySelector('#platform-sidebar-brand'),
    sidebarScrim: document.querySelector('#sidebar-scrim'),
    sidebarOpen: document.querySelector('#sidebar-open'),
    sidebarClose: document.querySelector('#sidebar-close'),
    platformSidebarClose: document.querySelector('#platform-sidebar-close'),
    platformLogoutButton: document.querySelector('#platform-logout-button'),
    workspaceName: document.querySelector('#workspace-name'),
    workspaceKind: document.querySelector('#workspace-kind'),
    organizationContext: document.querySelector('#organization-context'),
    customerContextBar: document.querySelector('#customer-context-bar'),
    platformContextBar: document.querySelector('#platform-context-bar'),
    breadcrumbProduct: document.querySelector('#breadcrumb-product'),
    pageEyebrow: document.querySelector('#page-eyebrow'),
    topbarPage: document.querySelector('#topbar-page'),
    dashboardSearchForm: document.querySelector('#dashboard-search-form'),
    globalSearch: document.querySelector('#global-search'),
    shortcutsButton: document.querySelector('#shortcuts-button'),
    connectionStatus: document.querySelector('#connection-status'),
    themeToggle: document.querySelector('#theme-toggle'),
    themeToggleIcon: document.querySelector('#theme-toggle-icon'),
    themeToggleLabel: document.querySelector('#theme-toggle-label'),
    userInitials: document.querySelector('#user-initials'),
    userName: document.querySelector('#user-name'),
    userEmail: document.querySelector('#user-email'),
    accountMenu: document.querySelector('#account-menu'),
    accountMenuTrigger: document.querySelector('#account-menu-trigger'),
    accountMenuItems: [...document.querySelectorAll('[data-account-action]')],
    logoutButton: document.querySelector('#logout-button'),
    pageTitle: document.querySelector('#page-title'),
    pageDescription: document.querySelector('#page-description'),
    refreshButton: document.querySelector('#refresh-button'),
    profileContext: document.querySelector('#profile-context'),
    applicationContext: document.querySelector('#application-context'),
    environmentContext: document.querySelector('#environment-context'),
    contextScopeNote: document.querySelector('#context-scope-note'),
    contextOrganization: document.querySelector('#context-organization'),
    contextOrganizationId: document.querySelector('#context-organization-id'),
    lastFetched: document.querySelector('#last-fetched'),
    globalBanner: document.querySelector('#global-banner'),
    toastRegion: document.querySelector('#toast-region'),
    pageRegion: document.querySelector('#page-region'),
    recordSheet: document.querySelector('#record-sheet'),
    recordSheetDialog: document.querySelector('.record-sheet-dialog'),
    recordSheetClose: document.querySelector('#record-sheet-close'),
    recordSheetContent: document.querySelector('#record-sheet-content'),
    shortcutsDialog: document.querySelector('#shortcuts-dialog'),
    shortcutsDialogPanel: document.querySelector('.shortcuts-dialog-panel'),
    viewLinks: [...document.querySelectorAll('[data-view-link]')],
  };

  function isPlatformHost() {
    return PLATFORM_HOSTNAMES.has((window.location.hostname || '').toLowerCase());
  }

  function isLocalHost() {
    return new Set(['127.0.0.1', 'localhost', '[::1]', '::1']).has(
      (window.location.hostname || '').toLowerCase(),
    );
  }

  function isPlatformView(view) {
    return PLATFORM_VIEWS.has(view);
  }

  function readRoute() {
    const pathSegments = window.location.pathname
      .replace(/^\/+|\/+$/g, '')
      .split('/')
      .filter(Boolean);
    const hashValue = window.location.hash.replace(/^#/, '').replace(/^\/+/, '');
    const hashSegments = hashValue.split('/').filter(Boolean);
    const segments = pathSegments.length > 0 ? pathSegments : hashSegments;
    const platformPath = segments[0] === 'platform';
    const platformShell = isPlatformHost() || (isLocalHost() && platformPath);
    const routeSegments = platformPath ? segments.slice(1) : segments;
    if (platformShell) {
      if (routeSegments[0] === 'organizations' && routeSegments[1]) {
        return {
          shell: 'platform',
          view: 'platform-organization',
          organizationId: decodeURIComponent(routeSegments[1]),
        };
      }
      const platformRoutes = {
        organizations: 'platform-organizations',
        audit: 'platform-audit',
        operations: 'platform-operations',
        users: 'platform-users',
        entitlements: 'platform-entitlements',
        settings: 'platform-settings',
      };
      return {
        shell: 'platform',
        view: platformRoutes[routeSegments[0]] ?? 'platform',
        organizationId: null,
      };
    }
    const value = segments[0] || 'overview';
    return {
      shell: 'customer',
      view: Object.prototype.hasOwnProperty.call(PAGE_COPY, value) && !isPlatformView(value)
        ? value
        : 'overview',
      organizationId: null,
    };
  }

  const initialRoute = readRoute();
  const state = {
    api: null,
    endpoint: '',
    discovery: { status: 'checking', endpoint: '' },
    identity: null,
    overview: null,
    overviewError: null,
    platformMetrics: null,
    platformMetricsError: null,
    platformMetricsLoading: false,
    platformOrganizations: null,
    platformOrganizationsError: null,
    platformOrganization: null,
    platformOrganizationError: null,
    platformAudit: null,
    platformAuditError: null,
    platformUsers: null,
    platformUsersError: null,
    platformEntitlements: null,
    platformEntitlementsError: null,
    platformDataLoading: false,
    platformDataGeneration: 0,
    organizationMembers: null,
    organizationMembersError: null,
    credentials: null,
    credentialsError: null,
    issuedCredential: null,
    credentialIssueError: null,
    credentialIssueLoading: false,
    actionLoading: null,
    actionError: null,
    customerSettingsLoading: false,
    customerSettingsGeneration: 0,
    shell: initialRoute.shell,
    platformOrganizationId: initialRoute.organizationId,
    loading: false,
    lastFetchedAt: null,
    globalSearchQuery: '',
    collectionControls: createCollectionControls(),
    profileIndex: 0,
    selectedApplication: '',
    selectedEnvironment: '',
    currentView: initialRoute.view,
  };

  let sidebarReturnFocus = null;
  let recordSheetReturnFocus = null;
  let shortcutsReturnFocus = null;
  let toastTimer = null;
  let overviewRequestGeneration = 0;
  let activeOverviewController = null;
  let platformMetricsRequestGeneration = 0;
  let activePlatformMetricsController = null;
  let pageTransitionFrame = null;
  const sidebarTabIndexMemory = new WeakMap();

  class ApiError extends Error {
    constructor(message, { status = 0, code = '', path = '' } = {}) {
      super(message);
      this.name = 'ApiError';
      this.status = status;
      this.code = code;
      this.path = path;
    }
  }

  class SessionExpiredError extends ApiError {
    constructor() {
      super('The human session has expired.', { status: 401 });
      this.name = 'SessionExpiredError';
    }
  }

  class DashboardApi {
    constructor(baseUrl) {
      this.baseUrl = baseUrl;
      this.accessToken = null;
      this.sessionToken = null;
      this.accessExpiresAt = null;
      this.sessionExpiresAt = null;
      this.authorizationAudience = CUSTOMER_AUTHORIZATION_AUDIENCE;
    }

    setSession(payload) {
      const root = unwrapPayload(payload);
      const accessToken = requiredString(root, 'access_token', 'accessToken');
      const sessionToken = requiredString(root, 'session_token', 'sessionToken');
      this.accessToken = accessToken;
      this.sessionToken = sessionToken;
      this.accessExpiresAt = stringValue(root.expires_at ?? root.expiresAt);
      this.sessionExpiresAt = stringValue(
        root.session_expires_at ?? root.sessionExpiresAt,
      );
      const audience = stringValue(
        root.authorization_audience ?? root.authorizationAudience,
      );
      if (
        audience &&
        audience !== CUSTOMER_AUTHORIZATION_AUDIENCE &&
        audience !== PLATFORM_AUTHORIZATION_AUDIENCE
      ) {
        throw new ApiError('The auth response contained an unsupported audience.');
      }
      this.authorizationAudience = audience ?? CUSTOMER_AUTHORIZATION_AUDIENCE;
    }

    clear() {
      this.accessToken = null;
      this.sessionToken = null;
      this.accessExpiresAt = null;
      this.sessionExpiresAt = null;
      this.authorizationAudience = CUSTOMER_AUTHORIZATION_AUDIENCE;
    }

    async discover() {
      return unwrapPayload(await this.request('.well-known/hyfens'));
    }

    async login(email, password, audience = CUSTOMER_AUTHORIZATION_AUDIENCE) {
      return unwrapPayload(
        await this.request('auth/login', {
          method: 'POST',
          body: { email, password, audience },
          retry: false,
        }),
      );
    }

    async register(email, password) {
      return unwrapPayload(
        await this.request('v1/public/register', {
          method: 'POST',
          body: { email, password },
          retry: false,
        }),
      );
    }

    async submitPublicIntake(kind, body) {
      if (!Object.prototype.hasOwnProperty.call(PUBLIC_INTAKE_COPY, kind)) {
        throw new Error('The public intake type is not supported.');
      }
      return unwrapPayload(
        await this.request(`v1/public/${kind}`, {
          method: 'POST',
          body,
          retry: false,
        }),
      );
    }

    async me() {
      return unwrapPayload(await this.request('auth/me', { requiresAuth: true }));
    }

    async refresh({ signal } = {}) {
      if (!this.sessionToken) throw new SessionExpiredError();
      const payload = unwrapPayload(
        await this.request('auth/refresh', {
          method: 'POST',
          body: { session_token: this.sessionToken },
          retry: false,
          signal,
        }),
      );
      const accessToken = requiredString(payload, 'access_token', 'accessToken');
      this.accessToken = accessToken;
      this.accessExpiresAt = stringValue(payload.expires_at ?? payload.expiresAt);
      const audience = stringValue(
        payload.authorization_audience ?? payload.authorizationAudience,
      );
      if (
        audience &&
        audience !== CUSTOMER_AUTHORIZATION_AUDIENCE &&
        audience !== PLATFORM_AUTHORIZATION_AUDIENCE
      ) {
        throw new ApiError('The refresh response contained an unsupported audience.');
      }
      if (audience) this.authorizationAudience = audience;
      persistSession(this);
      return payload;
    }

    async logout() {
      if (!this.sessionToken) return;
      await this.request('auth/logout', {
        method: 'POST',
        body: { session_token: this.sessionToken },
        retry: false,
      });
    }

    async overview(organizationId, { signal } = {}) {
      return unwrapPayload(
        await this.request(
          `v1/organizations/${encodeURIComponent(organizationId)}/overview`,
          { requiresAuth: true, signal },
        ),
      );
    }

    async platformMetrics(profileName, { signal } = {}) {
      const query = profileName
        ? `?profile=${encodeURIComponent(profileName)}`
        : '';
      return unwrapPayload(
        await this.request(`v1/platform/metrics${query}`, {
          requiresAuth: true,
          signal,
        }),
      );
    }

    async platformOrganizations(profileName, query = '', { signal } = {}) {
      const parameters = new URLSearchParams();
      if (profileName) parameters.set('profile', profileName);
      if (query) parameters.set('q', query);
      const suffix = parameters.toString() ? `?${parameters.toString()}` : '';
      return unwrapPayload(
        await this.request(`v1/platform/organizations${suffix}`, {
          requiresAuth: true,
          signal,
        }),
      );
    }

    async platformOrganization(profileName, organizationId, { signal } = {}) {
      const query = profileName ? `?profile=${encodeURIComponent(profileName)}` : '';
      return unwrapPayload(
        await this.request(
          `v1/platform/organizations/${encodeURIComponent(organizationId)}${query}`,
          { requiresAuth: true, signal },
        ),
      );
    }

    async platformAudit(profileName, organizationId = '', { signal } = {}) {
      const parameters = new URLSearchParams();
      if (profileName) parameters.set('profile', profileName);
      if (organizationId) parameters.set('organization_id', organizationId);
      const suffix = parameters.toString() ? `?${parameters.toString()}` : '';
      return unwrapPayload(
        await this.request(`v1/platform/audit${suffix}`, {
          requiresAuth: true,
          signal,
        }),
      );
    }

    async platformUsers(profileName, { signal } = {}) {
      const query = profileName
        ? `?profile=${encodeURIComponent(profileName)}`
        : '';
      return unwrapPayload(
        await this.request(`v1/platform/users${query}`, {
          requiresAuth: true,
          signal,
        }),
      );
    }

    async platformEntitlements(profileName, { signal } = {}) {
      const query = profileName
        ? `?profile=${encodeURIComponent(profileName)}`
        : '';
      return unwrapPayload(
        await this.request(`v1/platform/entitlements${query}`, {
          requiresAuth: true,
          signal,
        }),
      );
    }

    async createApplication(organizationId, body, idempotencyKey) {
      return unwrapPayload(
        await this.request(
          `v1/organizations/${encodeURIComponent(organizationId)}/applications`,
          {
            method: 'POST',
            body,
            requiresAuth: true,
            headers: { 'Idempotency-Key': idempotencyKey },
          },
        ),
      );
    }

    async issueCredential(organizationId, body) {
      return unwrapPayload(
        await this.request(
          `v1/organizations/${encodeURIComponent(organizationId)}/credentials`,
          { method: 'POST', body, requiresAuth: true },
        ),
      );
    }

    async createEnvironment(organizationId, applicationId, body, idempotencyKey) {
      return unwrapPayload(
        await this.request(
          `v1/organizations/${encodeURIComponent(organizationId)}/applications/${encodeURIComponent(applicationId)}/environments`,
          {
            method: 'POST',
            body,
            requiresAuth: true,
            headers: { 'Idempotency-Key': idempotencyKey },
          },
        ),
      );
    }

    async promote(organizationId, environmentId, body, idempotencyKey, expectedVersion) {
      return unwrapPayload(
        await this.request(
          `v1/organizations/${encodeURIComponent(organizationId)}/environments/${encodeURIComponent(environmentId)}/release-promotions`,
          {
            method: 'POST',
            body,
            requiresAuth: true,
            headers: {
              'Idempotency-Key': idempotencyKey,
              'If-Match': `"environment-v${expectedVersion}"`,
            },
          },
        ),
      );
    }

    async organizationMembers(organizationId, { signal } = {}) {
      return unwrapPayload(
        await this.request(
          `v1/organizations/${encodeURIComponent(organizationId)}/members`,
          { requiresAuth: true, signal },
        ),
      );
    }

    async credentials(organizationId, { signal } = {}) {
      return unwrapPayload(
        await this.request(
          `v1/organizations/${encodeURIComponent(organizationId)}/credentials`,
          { requiresAuth: true, signal },
        ),
      );
    }

    async revokeCredential(organizationId, credentialId) {
      return unwrapPayload(
        await this.request(
          `v1/organizations/${encodeURIComponent(organizationId)}/credentials/${encodeURIComponent(credentialId)}/revoke`,
          { method: 'POST', requiresAuth: true, body: {} },
        ),
      );
    }

    async request(path, {
      method = 'GET',
      body,
      requiresAuth = false,
      retry = true,
      signal,
      headers: additionalHeaders = {},
    } = {}) {
      if (requiresAuth && !this.accessToken) throw new SessionExpiredError();
      const url = new URL(path.replace(/^\/+/, ''), this.baseUrl);
      const headers = { Accept: 'application/json', ...additionalHeaders };
      if (body !== undefined) headers['Content-Type'] = 'application/json';
      if (requiresAuth) headers.Authorization = `Bearer ${this.accessToken}`;

      let response;
      try {
        const requestOptions = {
          method,
          headers,
          body: body === undefined ? undefined : JSON.stringify(body),
          cache: 'no-store',
          credentials: 'omit',
          referrerPolicy: 'no-referrer',
        };
        if (signal) requestOptions.signal = signal;
        response = await fetch(url, requestOptions);
      } catch (error) {
        if (isAbortError(error)) throw error;
        throw new ApiError('The control plane could not be reached.', { path });
      }

      const payload = await responsePayload(response, path);
      if (response.status === 401 && requiresAuth && retry && this.sessionToken) {
        try {
          await this.refresh({ signal });
        } catch (error) {
          if (isAbortError(error)) throw error;
          this.clear();
          throw new SessionExpiredError();
        }
        return this.request(path, {
          method,
          body,
          requiresAuth,
          retry: false,
          signal,
          headers: additionalHeaders,
        });
      }
      if (!response.ok) {
        const errorValue = objectValue(payload?.error);
        throw new ApiError('The control plane rejected the request.', {
          status: response.status,
          code: stringValue(errorValue?.code) ?? '',
          path,
        });
      }
      return payload;
    }
  }

  function isAbortError(error) {
    return error?.name === 'AbortError';
  }

  async function responsePayload(response, path) {
    const text = await response.text();
    if (text.length === 0) return {};
    try {
      return JSON.parse(text);
    } catch (error) {
      throw new ApiError('The control plane returned malformed JSON.', {
        status: response.status,
        path,
      });
    }
  }

  function unwrapPayload(payload) {
    const root = objectValue(payload);
    const data = objectValue(root?.data);
    return data ?? root ?? {};
  }

  function requiredString(object, ...keys) {
    for (const key of keys) {
      const value = stringValue(objectValue(object)?.[key]);
      if (value) return value;
    }
    throw new ApiError('The auth response did not include the required session fields.');
  }

  function sessionStorageObject() {
    try {
      return window.sessionStorage;
    } catch (error) {
      return null;
    }
  }

  function clearStoredSession() {
    const storage = sessionStorageObject();
    if (!storage) return;
    try {
      storage.removeItem(SESSION_STORAGE_KEY);
    } catch (error) {
      // Storage can be unavailable in restricted browser contexts.
    }
  }

  function readStoredSession() {
    const storage = sessionStorageObject();
    if (!storage) return null;
    let raw;
    try {
      raw = storage.getItem(SESSION_STORAGE_KEY);
    } catch (error) {
      return null;
    }
    if (!raw) return null;
    try {
      const value = JSON.parse(raw);
      if (!objectValue(value)) throw new Error('Stored session is not an object.');
      return value;
    } catch (error) {
      clearStoredSession();
      return null;
    }
  }

  function persistSession(api) {
    if (!api?.baseUrl || !api.accessToken || !api.sessionToken) return;
    const storage = sessionStorageObject();
    if (!storage) return;
    try {
      storage.setItem(SESSION_STORAGE_KEY, JSON.stringify({
        endpoint: api.baseUrl,
        access_token: api.accessToken,
        session_token: api.sessionToken,
        expires_at: api.accessExpiresAt,
        session_expires_at: api.sessionExpiresAt,
        authorization_audience: api.authorizationAudience,
      }));
    } catch (error) {
      // Keep the authenticated page usable when storage is unavailable.
    }
  }

  function normalizeEndpoint(value) {
    const input = value.trim();
    if (!input) throw new Error('A control-plane endpoint is required.');
    let url;
    try {
      url = new URL(input, window.location.origin);
    } catch (error) {
      throw new Error('The control-plane endpoint is not a valid URL.');
    }
    if (!['http:', 'https:'].includes(url.protocol) || !url.hostname) {
      throw new Error('The control-plane endpoint must use HTTP or HTTPS.');
    }
    if (url.username || url.password || url.search || url.hash) {
      throw new Error('The control-plane endpoint cannot contain credentials or query data.');
    }
    if (url.protocol === 'http:' && !isLoopbackHost(url.hostname)) {
      throw new Error('Remote control-plane endpoints must use HTTPS.');
    }
    if (!url.pathname.endsWith('/')) url.pathname += '/';
    return url.toString();
  }

  function isLoopbackHost(hostname) {
    const host = hostname.toLowerCase().replace(/^\[|\]$/g, '');
    if (host === 'localhost' || host === '::1') return true;
    const octets = host.split('.');
    return octets.length === 4 &&
      octets.every((octet) => /^(?:0|[1-9]\d{0,2})$/.test(octet) && Number(octet) <= 255) &&
      Number(octets[0]) === 127;
  }

  function defaultEndpoint() {
    const configured = document.querySelector('meta[name="hyfens-api-base"]')?.content?.trim();
    const runtimeConfigured = window.__HYFENS_RUNTIME_CONFIG__?.apiBase?.trim();
    if (configured || runtimeConfigured) return configured || runtimeConfigured;
    const hostname = window.location.hostname.toLowerCase();
    if (hostname === 'app.hyfens.com' || PLATFORM_HOSTNAMES.has(hostname)) {
      return 'https://api.hyfens.com/';
    }
    return `${window.location.origin}/`;
  }

  function isManagedControlPlaneEndpoint(endpoint = state.endpoint) {
    try {
      return new URL(endpoint).hostname.toLowerCase() === 'api.hyfens.com';
    } catch {
      return false;
    }
  }

  function displayEndpoint(endpoint = state.endpoint) {
    if (isManagedControlPlaneEndpoint(endpoint)) return 'Hyfens Cloud (managed)';
    return stringValue(endpoint) ?? 'Not configured';
  }

  function configuredEndpoint() {
    const endpoint = normalizeEndpoint(nodes.apiBase.value || defaultEndpoint());
    nodes.apiBase.value = endpoint;
    return endpoint;
  }

  function setTheme(theme) {
    const isLight = theme === 'light';
    document.documentElement.dataset.theme = isLight ? 'light' : 'dark';
    nodes.themeToggle.setAttribute('aria-pressed', String(isLight));
    nodes.themeToggle.setAttribute(
      'aria-label',
      isLight ? 'Switch to dark theme' : 'Switch to light theme',
    );
    if (nodes.themeToggleIcon) {
      nodes.themeToggleIcon.src = isLight ? 'icons/moon_outline.svg' : 'icons/sun_outline.svg';
    }
    nodes.themeToggleLabel.textContent = isLight ? 'Dark' : 'Light';
  }

  function viewFromLocation() {
    return readRoute().view;
  }

  function requestedLoginAudience() {
    return readRoute().shell === 'platform'
      ? PLATFORM_AUTHORIZATION_AUDIENCE
      : CUSTOMER_AUTHORIZATION_AUDIENCE;
  }

  function viewPath(view, organizationId = state.platformOrganizationId) {
    if (isPlatformView(view)) {
      const prefix = isPlatformHost() ? '' : '/platform';
      if (view === 'platform') return prefix || '/';
      if (view === 'platform-organizations') return `${prefix}/organizations`;
      if (view === 'platform-organization') {
        return `${prefix}/organizations/${encodeURIComponent(organizationId || '')}`;
      }
      if (view === 'platform-audit') return `${prefix}/audit`;
      if (view === 'platform-operations') return `${prefix}/operations`;
      if (view === 'platform-users') return `${prefix}/users`;
      if (view === 'platform-entitlements') return `${prefix}/entitlements`;
      if (view === 'platform-settings') return `${prefix}/settings`;
    }
    return view === 'overview' ? '/' : `/${view}`;
  }

  function canonicalizeViewLocation() {
    const route = readRoute();
    const path = viewPath(route.view, route.organizationId);
    if (
      window.location.pathname !== path ||
      window.location.search ||
      window.location.hash
    ) {
      window.history.replaceState({}, '', path);
    }
    return route.view;
  }

  function canEnterView(view) {
    if (!state.api) return true;
    if (isPlatformView(view)) {
      if (state.api.authorizationAudience !== PLATFORM_AUTHORIZATION_AUDIENCE) return false;
      return selectPlatformProfile() && hasPlatformCapability(platformCapabilityForView(view));
    }
    if (state.api.authorizationAudience !== CUSTOMER_AUTHORIZATION_AUDIENCE) return false;
    return selectCustomerProfile();
  }

  function fallbackViewForProfile(view) {
    const platformSession = state.api?.authorizationAudience === PLATFORM_AUTHORIZATION_AUDIENCE;
    if (isPlatformView(view)) {
      if (platformSession && selectPlatformProfile()) return 'platform';
      selectCustomerProfile();
      return 'overview';
    }
    if (!platformSession && selectCustomerProfile()) return 'overview';
    selectPlatformProfile();
    return 'platform';
  }

  function announceViewAccessDenied(view) {
    showToast(
      isPlatformView(view)
        ? 'This Platform Console area is not available to the selected profile.'
        : 'This Customer Workspace is not available to the selected profile.',
      'warning',
    );
  }

  function navigateToView(view, { organizationId = null } = {}) {
    if (state.currentView === 'settings' && view !== 'settings') clearIssuedCredential();
    state.actionLoading = null;
    state.actionError = null;
    let nextView = Object.prototype.hasOwnProperty.call(PAGE_COPY, view)
      ? view
      : state.shell === 'platform'
        ? 'platform'
        : 'overview';
    if (!canEnterView(nextView)) {
      announceViewAccessDenied(nextView);
      nextView = fallbackViewForProfile(nextView);
    }
    if (isPlatformView(nextView) && organizationId) {
      state.platformOrganizationId = organizationId;
    }
    const path = viewPath(nextView, state.platformOrganizationId);
    const isCanonical = (
      window.location.pathname === path &&
      !window.location.search &&
      !window.location.hash
    );
    if (!isCanonical) window.history.pushState({}, '', path);
    state.shell = isPlatformView(nextView) ? 'platform' : 'customer';
    if (isPlatformView(nextView)) {
      selectPlatformProfile();
      invalidateOverviewRequest();
      state.loading = false;
    } else {
      selectCustomerProfile();
      invalidatePlatformMetricsRequest();
      state.platformMetricsLoading = false;
      invalidatePlatformDataRequest();
      state.platformDataLoading = false;
    }
    state.currentView = nextView;
    applyShellMode();
    renderCurrentPage({ transition: true });
    if (state.api) void loadCurrentViewData();
  }

  function createCollectionControls() {
    return Object.fromEntries(
      RESOURCE_KEYS.map((key) => [key, { query: '', status: '', sort: 'newest' }]),
    );
  }

  function normalizeSearchQuery(value) {
    return stringValue(value)?.trim().toLowerCase() ?? '';
  }

  function compareText(left, right) {
    const leftText = normalizeSearchQuery(left);
    const rightText = normalizeSearchQuery(right);
    if (leftText < rightText) return -1;
    if (leftText > rightText) return 1;
    return 0;
  }

  function element(tag, className = '', text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function clearIssuedCredential() {
    state.issuedCredential = null;
    state.credentialIssueError = null;
    state.credentialIssueLoading = false;
  }

  function makeIdempotencyKey(prefix) {
    const randomUuid = typeof globalThis.crypto?.randomUUID === 'function'
      ? globalThis.crypto.randomUUID()
      : `${Date.now()}-${Math.floor(Math.random() * 1000000000)}`;
    return `${prefix}-${randomUuid}`;
  }

  function formField(labelText, control, hint = '') {
    const label = element('label', 'action-form-field');
    label.append(element('span', 'form-label', labelText), control);
    if (hint) label.append(element('span', 'form-hint', hint));
    return label;
  }

  function actionErrorMessage(action) {
    const error = state.actionError;
    if (!error || error.action !== action) return null;
    return element('p', 'action-form-error', error.message);
  }

  function actionSubmitButton(action, label) {
    const button = element('button', 'button button-primary', state.actionLoading === action ? 'Working…' : label);
    button.type = 'submit';
    button.disabled = state.actionLoading !== null;
    button.setAttribute('aria-busy', String(state.actionLoading === action));
    return button;
  }

  function cliHandoff(title, description, commands) {
    const wrapper = element('div', 'cli-handoff');
    wrapper.append(element('strong', '', title), element('p', 'form-hint', description));
    const list = element('ul', 'cli-command-list');
    for (const command of commands) {
      const item = element('li');
      item.append(element('code', 'cli-command', command));
      list.append(item);
    }
    wrapper.append(list);
    return wrapper;
  }

  function selectControl(select) {
    const wrapper = element('span', 'select-control');
    const arrow = element('img', 'select-arrow');
    arrow.src = 'icons/arrow_down_outline.svg';
    arrow.width = 14;
    arrow.height = 14;
    arrow.alt = '';
    arrow.setAttribute('aria-hidden', 'true');
    wrapper.append(select, arrow);
    return wrapper;
  }

  function codeValue(value, className = '') {
    const text = stringValue(value);
    if (!text) return element('span', 'metadata-value muted', 'Not set');
    const node = element('code', className, text);
    node.title = text;
    return node;
  }

  function dateValue(value) {
    const raw = stringValue(value);
    if (!raw) return element('span', 'metadata-value muted', 'Not available');
    const date = new Date(raw);
    const node = element(
      'span',
      '',
      Number.isNaN(date.getTime())
        ? raw
        : new Intl.DateTimeFormat(undefined, {
            dateStyle: 'medium',
            timeStyle: 'short',
            timeZone: 'UTC',
          }).format(date) + ' UTC',
    );
    node.title = raw;
    return node;
  }

  function stringValue(value) {
    if (value === undefined || value === null || value === '') return null;
    return String(value);
  }

  function pick(object, ...keys) {
    const value = objectValue(object);
    if (!value) return undefined;
    for (const key of keys) {
      if (Object.prototype.hasOwnProperty.call(value, key)) return value[key];
    }
    return undefined;
  }

  function objectValue(value) {
    return value && typeof value === 'object' && !Array.isArray(value) ? value : null;
  }

  function arrayValue(value) {
    return Array.isArray(value) ? value : [];
  }

  function countValue(value) {
    return typeof value === 'number' && Number.isFinite(value) ? String(value) : 'Unavailable';
  }

  function formatBytes(value) {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return 'Not available';
    if (value < 1024) return `${value} B`;
    if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KiB`;
    return `${(value / (1024 * 1024)).toFixed(1)} MiB`;
  }

  function formatBasisPoints(value) {
    if (typeof value !== 'number' || !Number.isFinite(value)) return 'Not set';
    return `${(value / 100).toFixed(2)}% (${value} bps)`;
  }

  function statusClass(value) {
    const status = String(value ?? '').toUpperCase();
    if (['READY', 'SUCCESS', 'SUCCEEDED', 'ACTIVE', 'COMPLETED', 'PROMOTED'].includes(status)) {
      return 'status-tag-success';
    }
    if (['FAILED', 'ERROR', 'REJECTED', 'HALTED', 'INVALID'].includes(status)) {
      return 'status-tag-danger';
    }
    if (['MISSING', 'AMBIGUOUS', 'PAUSED', 'PENDING'].includes(status)) {
      return 'status-tag-warning';
    }
    return '';
  }

  function statusTag(value, fallback = 'Not set') {
    const text = stringValue(value) ?? fallback;
    return element('span', `status-tag ${statusClass(text)}`, text);
  }

  function metadataItem(label, value, { code = false } = {}) {
    const wrapper = element('div');
    wrapper.append(element('span', 'metadata-label', label));
    const node = code ? codeValue(value, 'metadata-value') : element('span', 'metadata-value', stringValue(value) ?? 'Not set');
    wrapper.append(node);
    return wrapper;
  }

  function makePanel(title, description = '', caption = '') {
    const section = element('section', 'surface-panel panel-padding');
    const heading = element('div', 'panel-heading');
    const copy = element('div');
    copy.append(element('h2', '', title));
    if (description) copy.append(element('p', '', description));
    heading.append(copy);
    if (caption) heading.append(element('span', 'caption', caption));
    const body = element('div');
    section.append(heading, body);
    return { section, body };
  }

  function stateBlock(kind, title, description) {
    const block = element('div', `${kind}-state`);
    block.append(element('strong', '', title));
    block.append(element('p', '', description));
    return block;
  }

  function exactRecordDetails(record) {
    const trigger = element('button', 'exact-record-trigger', 'View exact record');
    trigger.type = 'button';
    trigger.name = 'exact-record-trigger';
    trigger.setAttribute('aria-haspopup', 'dialog');
    trigger.setAttribute('aria-controls', 'record-sheet');
    trigger.addEventListener('click', () => openRecordSheet(record, trigger));
    return trigger;
  }

  function openRecordSheet(record, trigger = null) {
    if (!nodes.recordSheet || !nodes.recordSheetContent) return;
    recordSheetReturnFocus = trigger?.isConnected
      ? trigger
      : document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    try {
      const serialized = JSON.stringify(record, null, 2);
      nodes.recordSheetContent.textContent = serialized ?? 'Record could not be displayed.';
    } catch (error) {
      nodes.recordSheetContent.textContent = 'Record could not be displayed.';
    }
    nodes.recordSheet.hidden = false;
    document.body?.classList.add('record-sheet-open');
    const focusable = recordSheetFocusableElements();
    (focusable[0] ?? nodes.recordSheetDialog)?.focus({ preventScroll: true });
  }

  function closeRecordSheet({ restoreFocus = true } = {}) {
    if (!nodes.recordSheet) return;
    nodes.recordSheet.hidden = true;
    if (nodes.recordSheetContent) nodes.recordSheetContent.textContent = '';
    document.body?.classList.remove('record-sheet-open');
    const returnFocus = recordSheetReturnFocus;
    recordSheetReturnFocus = null;
    if (
      restoreFocus &&
      returnFocus?.isConnected &&
      !returnFocus.disabled &&
      !returnFocus.closest('[hidden]')
    ) {
      returnFocus.focus({ preventScroll: true });
    }
  }

  function recordSheetFocusableElements() {
    if (!nodes.recordSheetDialog) return [];
    return [...nodes.recordSheetDialog.querySelectorAll(
      'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
    )].filter((node) => {
      const styles = window.getComputedStyle(node);
      return styles.display !== 'none' && styles.visibility !== 'hidden';
    });
  }

  function handleRecordSheetClick(event) {
    if (event.target.closest?.('[data-record-sheet-close]')) closeRecordSheet();
  }

  function handleRecordSheetKeydown(event) {
    if (!nodes.recordSheet || nodes.recordSheet.hidden) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopImmediatePropagation();
      closeRecordSheet();
      return;
    }
    if (event.key !== 'Tab') return;
    const focusable = recordSheetFocusableElements();
    if (focusable.length === 0) {
      event.preventDefault();
      nodes.recordSheetDialog?.focus({ preventScroll: true });
      return;
    }
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (!nodes.recordSheetDialog?.contains(document.activeElement)) {
      event.preventDefault();
      first.focus({ preventScroll: true });
    } else if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus({ preventScroll: true });
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus({ preventScroll: true });
    }
  }

  function shortcutsDialogFocusableElements() {
    if (!nodes.shortcutsDialogPanel) return [];
    return [...nodes.shortcutsDialogPanel.querySelectorAll(
      'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
    )].filter((node) => {
      const styles = window.getComputedStyle(node);
      return styles.display !== 'none' && styles.visibility !== 'hidden';
    });
  }

  function openShortcutsDialog(trigger = null) {
    if (!nodes.shortcutsDialog || !nodes.shortcutsDialog.hidden) return;
    const activeElement = document.activeElement;
    shortcutsReturnFocus = trigger?.isConnected
      ? trigger
      : activeElement instanceof HTMLElement && activeElement !== document.body
        ? activeElement
        : nodes.shortcutsButton;
    nodes.shortcutsDialog.hidden = false;
    nodes.shortcutsButton?.setAttribute('aria-expanded', 'true');
    document.body?.classList.add('shortcuts-dialog-open');
    const focusable = shortcutsDialogFocusableElements();
    (focusable[0] ?? nodes.shortcutsDialogPanel)?.focus({ preventScroll: true });
  }

  function closeShortcutsDialog({ restoreFocus = true } = {}) {
    if (!nodes.shortcutsDialog || nodes.shortcutsDialog.hidden) return;
    nodes.shortcutsDialog.hidden = true;
    nodes.shortcutsButton?.setAttribute('aria-expanded', 'false');
    document.body?.classList.remove('shortcuts-dialog-open');
    const returnFocus = shortcutsReturnFocus;
    shortcutsReturnFocus = null;
    if (
      restoreFocus &&
      returnFocus?.isConnected &&
      !returnFocus.disabled &&
      !returnFocus.closest('[hidden]')
    ) {
      returnFocus.focus({ preventScroll: true });
    }
  }

  function handleShortcutsDialogClick(event) {
    if (event.target.closest?.('[data-shortcuts-close]')) closeShortcutsDialog();
  }

  function handleShortcutsDialogKeydown(event) {
    if (!nodes.shortcutsDialog || nodes.shortcutsDialog.hidden) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopImmediatePropagation();
      closeShortcutsDialog();
      return;
    }
    if (event.key !== 'Tab') return;
    const focusable = shortcutsDialogFocusableElements();
    if (focusable.length === 0) {
      event.preventDefault();
      nodes.shortcutsDialogPanel?.focus({ preventScroll: true });
      return;
    }
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (!nodes.shortcutsDialogPanel?.contains(document.activeElement)) {
      event.preventDefault();
      first.focus({ preventScroll: true });
    } else if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus({ preventScroll: true });
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus({ preventScroll: true });
    }
  }

  function tableCell(content) {
    const cell = element('td');
    if (Array.isArray(content)) cell.append(...content);
    else if (content instanceof Node) cell.append(content);
    else cell.textContent = String(content ?? 'Not set');
    return cell;
  }

  function primaryCell(value, subvalue) {
    const wrapper = element('div');
    if (value instanceof Node) wrapper.append(value);
    else wrapper.append(element('strong', '', stringValue(value) ?? 'Not set'));
    if (subvalue !== undefined) {
      if (subvalue instanceof Node) {
        wrapper.append(subvalue);
      } else {
        const sub = stringValue(subvalue);
        wrapper.append(element('span', 'subvalue', sub ?? 'Not set'));
      }
    }
    return wrapper;
  }

  function recordTable(headers, items, rowFactory) {
    const wrap = element('div', 'data-table-wrap');
    const table = element('table', 'data-table');
    const thead = element('thead');
    const headerRow = element('tr');
    for (const header of headers) headerRow.append(element('th', '', header));
    thead.append(headerRow);
    const tbody = element('tbody');
    for (const item of items) tbody.append(rowFactory(item));
    table.append(thead, tbody);
    wrap.append(table);
    return wrap;
  }

  function tableRow(cells) {
    const row = element('tr');
    for (const content of cells) row.append(tableCell(content));
    return row;
  }

  function collectionNote(body, key, items, result = null) {
    const directTruncated = result?.directTruncated ?? objectValue(body?.truncated)?.[key] === true;
    const dependencyTruncation = result?.dependencyTruncation ?? collectionDependencyTruncation(body, key);
    if (!directTruncated && !dependencyTruncation) return null;
    const loaded = result?.sourceCount ?? items.length;
    const shown = result?.items?.length ?? items.length;
    const returned = result?.returnedCount ?? items.length;
    const suffix = collectionTruncationSuffix(body, key, {
      directTruncated,
      dependencyTruncation,
    });
    const text = loaded === 0
      ? returned > 0
        ? `No records in the selected context were found among the loaded records.${suffix}`
        : `No records were returned in this capped response.${suffix}`
      : shown === loaded
        ? `Showing ${loaded} loaded records.${suffix}`
        : `Showing ${shown} matching records from ${loaded} loaded records.${suffix}`;
    return element('p', 'collection-note', text);
  }

  function collectionHasSelectedContext(key) {
    const appId = state.selectedApplication || profileApplicationId();
    const environmentId = state.selectedEnvironment || profileEnvironmentId();
    if (key === 'applications' || key === 'releases' || key === 'patches' || key === 'artifacts') {
      return Boolean(appId);
    }
    if (key === 'environments' || key === 'rollouts') {
      return Boolean(appId || environmentId);
    }
    return false;
  }

  function collectionDependencyTruncation(body, key) {
    const truncated = objectValue(body?.truncated);
    const dependencies = {
      patches: ['releases'],
      artifacts: ['patches', 'releases'],
    };
    if (!dependencies[key] || !collectionHasSelectedContext(key)) return null;
    return dependencies[key].find((dependency) => truncated?.[dependency] === true) ?? null;
  }

  function collectionTruncationSuffix(body, key, result) {
    const messages = [];
    if (result.directTruncated) {
      const maxItems = pick(body?.limits, 'maxItemsPerCollection');
      messages.push(
        typeof maxItems === 'number'
          ? `The response is capped at ${maxItems} records per collection.`
          : 'The response is capped; more records may be available.',
      );
    }
    if (result.dependencyTruncation) {
      const collectionLabel = RESOURCE_LABELS[key]?.toLowerCase() ?? key;
      const dependencyLabel = RESOURCE_LABELS[result.dependencyTruncation]?.toLowerCase() ?? result.dependencyTruncation;
      messages.push(
        `The selected ${collectionLabel} view depends on truncated ${dependencyLabel}; additional matching ${collectionLabel} cannot be ruled out.`,
      );
    }
    return messages.length > 0 ? ` ${messages.join(' ')}` : '';
  }

  function collectionEmptyState(body, key, title, description, result) {
    const returnedCount = arrayValue(body?.[key]).length;
    if (result?.dependencyTruncation) {
      const collectionLabel = title.toLowerCase();
      const dependencyLabel = RESOURCE_LABELS[result.dependencyTruncation]?.toLowerCase() ?? result.dependencyTruncation;
      return stateBlock(
        'empty',
        `No ${collectionLabel} confirmed in the selected context`,
        `No ${collectionLabel} were matched from the returned dependency records. Because the ${dependencyLabel} response is truncated, additional matching ${collectionLabel} cannot be ruled out.`,
      );
    }
    if (collectionHasSelectedContext(key) && (returnedCount > 0 || result?.directTruncated === true)) {
      const uncertain = result?.directTruncated === true;
      return stateBlock(
        'empty',
        uncertain
          ? `No ${title.toLowerCase()} confirmed in the returned selected context`
          : `No ${title.toLowerCase()} in the selected context`,
        uncertain
          ? `No ${title.toLowerCase()} matched the selected application/environment context among the returned records. The response is capped, so additional matching records may be available.`
          : 'The overview returned records, but none belong to the selected application/environment context. Change the active context to inspect other returned records.',
      );
    }
    return stateBlock('empty', `No ${title.toLowerCase()} returned`, description);
  }

  function collectionPanel(body, key, title, description, headers, items, rowFactory, emptyDescription) {
    const sourceItems = arrayValue(items);
    const result = collectionResult(body, key, sourceItems);
    const caption = result.truncated
      ? `${result.items.length} of ${result.sourceCount} loaded`
      : `${result.items.length} of ${result.sourceCount} returned`;
    const { section, body: panelBody } = makePanel(title, description, caption);
    section.dataset.collectionKey = key;
    panelBody.append(collectionToolbar(key, title, result));
    if (sourceItems.length === 0) {
      panelBody.append(collectionEmptyState(body, key, title, emptyDescription, result));
    } else if (result.items.length === 0) {
      const uncertain = result.truncated;
      const noMatch = stateBlock(
        'empty',
        uncertain
          ? `No loaded ${title.toLowerCase()} match the current filters`
          : `No ${title.toLowerCase()} match the current filters`,
        uncertain
          ? 'No loaded records match the current filters. The response or a required dependency is capped, so additional matching records may be available.'
          : 'Clear or change the search or status controls to show records.',
      );
      noMatch.dataset.state = 'no-match';
      panelBody.append(noMatch);
    } else {
      panelBody.append(recordTable(headers, result.items, rowFactory));
    }
    const note = collectionNote(body, key, sourceItems, result);
    if (note) panelBody.append(note);
    return section;
  }

  function collectionControlsFor(key) {
    if (state.collectionControls[key]) return state.collectionControls[key];
    state.collectionControls[key] = { query: '', status: '', sort: 'newest' };
    return state.collectionControls[key];
  }

  function recordStatusValue(key, record) {
    if (key === 'audit') return pick(record, 'result', 'status', 'state');
    return pick(record, 'state', 'status', 'result');
  }

  function collectionStatuses(key, items) {
    if (!STATUS_FILTER_KEYS.has(key)) return [];
    const values = new Map();
    for (const item of items) {
      const value = stringValue(recordStatusValue(key, item))?.trim();
      if (!value) continue;
      const normalized = normalizeSearchQuery(value);
      if (!values.has(normalized)) values.set(normalized, value);
    }
    return [...values.values()].sort(compareText);
  }

  function collectionResult(body, key, sourceItems) {
    const controls = collectionControlsFor(key);
    const statuses = collectionStatuses(key, sourceItems);
    const selectedStatus = normalizeSearchQuery(controls.status);
    const matchingStatus = statuses.find((value) => normalizeSearchQuery(value) === selectedStatus);
    if (selectedStatus && !matchingStatus) controls.status = '';
    else if (matchingStatus) controls.status = matchingStatus;
    const query = normalizeSearchQuery(controls.query);
    const status = normalizeSearchQuery(controls.status);
    const filtered = sourceItems.filter((item) => {
      const matchesText = !query || recordSearchText(key, item).includes(query);
      const matchesStatus = !status || normalizeSearchQuery(recordStatusValue(key, item)) === status;
      return matchesText && matchesStatus;
    });
    const directTruncated = objectValue(body?.truncated)?.[key] === true;
    const dependencyTruncation = collectionDependencyTruncation(body, key);
    return {
      controls,
      items: sortCollectionItems(filtered, key, controls.sort),
      sourceCount: sourceItems.length,
      returnedCount: arrayValue(body?.[key]).length,
      statuses,
      directTruncated,
      dependencyTruncation,
      truncated: directTruncated || Boolean(dependencyTruncation),
    };
  }

  function collectionToolbar(key, title, result) {
    const controls = result.controls;
    const toolbar = element('div', 'collection-toolbar');
    toolbar.dataset.collectionKey = key;
    toolbar.setAttribute('role', 'search');
    toolbar.setAttribute('aria-label', `${title} collection tools`);

    const searchLabel = element('label');
    searchLabel.append(element('span', 'collection-toolbar-label', 'Search'));
    const search = element('input', 'collection-search');
    search.id = `collection-search-${key}`;
    search.type = 'search';
    search.name = `${key}-search`;
    search.placeholder = `Search ${title.toLowerCase()}`;
    search.autocomplete = 'off';
    search.spellcheck = false;
    search.value = controls.query;
    search.dataset.collectionControl = 'search';
    search.setAttribute('aria-label', `Search ${title.toLowerCase()}`);
    searchLabel.append(search);
    toolbar.append(searchLabel);

    if (STATUS_FILTER_KEYS.has(key)) {
      const filterLabel = element('label');
      filterLabel.append(element('span', 'collection-toolbar-label', 'Status'));
      const filter = element('select', 'collection-filter');
      filter.id = `collection-filter-${key}`;
      filter.name = `${key}-status`;
      filter.dataset.collectionControl = 'status';
      filter.setAttribute('aria-label', `Filter ${title.toLowerCase()} by status`);
      const allStatuses = element('option', '', 'All statuses');
      allStatuses.value = '';
      filter.append(allStatuses);
      for (const value of result.statuses) {
        const option = element('option', '', value);
        option.value = value;
        filter.append(option);
      }
      filter.value = controls.status;
      filter.disabled = result.statuses.length === 0;
      filterLabel.append(selectControl(filter));
      toolbar.append(filterLabel);
    }

    const sortLabel = element('label');
    sortLabel.append(element('span', 'collection-toolbar-label', 'Sort'));
    const sort = element('select', 'collection-sort');
    sort.id = `collection-sort-${key}`;
    sort.name = `${key}-sort`;
    sort.dataset.collectionControl = 'sort';
    sort.setAttribute('aria-label', `Sort ${title.toLowerCase()}`);
    for (const optionData of COLLECTION_SORT_OPTIONS) {
      const option = element('option', '', optionData.label);
      option.value = optionData.value;
      sort.append(option);
    }
    if (!COLLECTION_SORT_OPTIONS.some((option) => option.value === controls.sort)) controls.sort = 'newest';
    sort.value = controls.sort;
    sortLabel.append(selectControl(sort));
    toolbar.append(sortLabel);

    const statusText = collectionStatusText(title, result);
    if (statusText) {
      const status = element('p', 'collection-toolbar-status', statusText);
      status.id = `collection-status-${key}`;
      status.setAttribute('role', 'status');
      status.setAttribute('aria-live', 'polite');
      search.setAttribute('aria-describedby', status.id);
      toolbar.append(status);
    }
    return toolbar;
  }

  function collectionStatusText(title, result) {
    const hasActiveFilter = normalizeSearchQuery(result.controls.query)
      || normalizeSearchQuery(result.controls.status);
    if (!hasActiveFilter && !result.truncated) return null;
    const sourceLabel = result.truncated ? 'loaded' : 'returned';
    let text = `Showing ${result.items.length} of ${result.sourceCount} ${sourceLabel} ${title.toLowerCase()}.`;
    if (hasActiveFilter) {
      text += ' Results are filtered.';
    }
    if (result.truncated) text += ' The response is capped; more records may be available.';
    return text;
  }

  function profileList() {
    return arrayValue(state.identity?.profiles);
  }

  function customerProfileList() {
    return profileList().filter((profile) => !isPlatformProfile(profile));
  }

  function selectedProfile() {
    const profiles = profileList();
    return profiles[state.profileIndex] ?? profiles[0] ?? null;
  }

  function isPlatformProfile(profile = selectedProfile()) {
    return pick(profile, 'platform') === true ||
      pick(profile, 'audience') === 'platform';
  }

  function platformCapabilityForView(view = state.currentView) {
    return {
      platform: 'platform:overview',
      'platform-organizations': 'platform:organizations:read',
      'platform-organization': 'platform:organizations:inspect',
      'platform-audit': 'platform:audit:read',
      // Operations is currently backed by the same bounded metrics projection
      // as the Platform overview. Keep the route contract aligned with the
      // server capability until a distinct operations projection exists.
      'platform-operations': 'platform:overview',
      'platform-users': 'platform:accounts:read',
      'platform-entitlements': 'platform:entitlements:read',
      'platform-settings': 'platform:overview',
    }[view] ?? null;
  }

  function hasPlatformCapability(capability, profile = selectedProfile()) {
    if (!isPlatformProfile(profile)) return false;
    if (!capability) return true;
    return arrayValue(pick(profile, 'platformCapabilities', 'platform_capabilities'))
      .includes(capability);
  }

  function hasCustomerCapability(capability, profile = selectedProfile()) {
    if (isPlatformProfile(profile)) return false;
    if (!capability) return true;
    return arrayValue(pick(profile, 'capabilities')).includes(capability);
  }

  function syncPlatformNavigation() {
    applyShellMode();
  }

  function applyShellMode() {
    const platform = state.shell === 'platform';
    nodes.appView.dataset.shell = platform ? 'platform' : 'customer';
    nodes.sidebar.hidden = platform;
    nodes.platformSidebar.hidden = !platform;
    nodes.customerContextBar.hidden = platform;
    nodes.platformContextBar.hidden = !platform;
    nodes.dashboardSearchForm.hidden = platform;
    nodes.sidebarOpen.setAttribute(
      'aria-controls',
      platform ? 'platform-sidebar' : 'sidebar',
    );
    nodes.breadcrumbProduct.textContent = platform
      ? 'Platform Console'
      : 'Customer Workspace';
    nodes.pageEyebrow.textContent = platform
      ? 'Platform Console'
      : 'Customer Workspace';
    if (platform) closeAccountMenu();
    syncSidebarAccessibility();
  }

  function selectPlatformProfile() {
    const platformIndex = profileList().findIndex((profile) => isPlatformProfile(profile));
    if (platformIndex < 0 || platformIndex === state.profileIndex) return platformIndex >= 0;
    state.profileIndex = platformIndex;
    state.selectedApplication = '';
    state.selectedEnvironment = '';
    renderContextControls();
    return true;
  }

  function selectCustomerProfile() {
    const customerIndex = profileList().findIndex((profile) => !isPlatformProfile(profile));
    if (customerIndex < 0 || customerIndex === state.profileIndex) return customerIndex >= 0;
    state.profileIndex = customerIndex;
    state.selectedApplication = '';
    state.selectedEnvironment = '';
    renderContextControls();
    return true;
  }

  function profileOrganizationName(profile) {
    const organization = objectValue(pick(profile, 'organization'));
    return stringValue(pick(profile, 'organizationName', 'organization_name'))
      ?? stringValue(pick(organization, 'name'));
  }

  function organizationMemberships() {
    const memberships = [];
    const byId = new Map();
    profileList().forEach((profile, profileIndex) => {
      if (isPlatformProfile(profile)) return;
      const organizationId = profileOrganizationId(profile);
      if (!organizationId) return;
      let membership = byId.get(organizationId);
      if (!membership) {
        membership = {
          id: organizationId,
          profileIndex,
          name: profileOrganizationName(profile),
        };
        byId.set(organizationId, membership);
        memberships.push(membership);
      } else if (!membership.name) {
        membership.name = profileOrganizationName(profile);
      }
    });
    return memberships;
  }

  function organizationRecordId(organization) {
    return stringValue(pick(organization, 'id', 'organizationId', 'organization_id'));
  }

  function organizationDisplayName(organizationId, memberships = organizationMemberships()) {
    const overviewOrganization = objectValue(state.overview?.organization);
    const overviewName = stringValue(pick(overviewOrganization, 'name'));
    const overviewId = organizationRecordId(overviewOrganization);
    if (
      overviewName &&
      (!overviewId || !organizationId || overviewId === organizationId)
    ) return overviewName;
    return memberships.find((membership) => membership.id === organizationId)?.name ?? null;
  }

  function organizationOptionLabel(membership, index, activeOrganizationId, memberships) {
    const name = membership.id === activeOrganizationId
      ? organizationDisplayName(activeOrganizationId, memberships)
      : membership.name;
    return name ?? `Organization ${index + 1}`;
  }

  function profileOrganizationId(profile = selectedProfile()) {
    return stringValue(pick(profile, 'organizationId', 'organization_id'));
  }

  function profileApplicationId(profile = selectedProfile()) {
    return stringValue(pick(profile, 'applicationId', 'application_id'));
  }

  function profileEnvironmentId(profile = selectedProfile()) {
    return stringValue(pick(profile, 'environmentId', 'environment_id'));
  }

  function recordId(record) {
    return stringValue(pick(record, 'id'));
  }

  function recordApplicationId(record) {
    return stringValue(pick(record, 'applicationId', 'application_id'));
  }

  function recordEnvironmentId(record) {
    return stringValue(pick(record, 'environmentId', 'environment_id'));
  }

  function scopedItems(key) {
    const body = state.overview;
    if (!body) return [];
    const items = arrayValue(body[key]);
    const appId = state.selectedApplication || profileApplicationId();
    const environmentId = state.selectedEnvironment || profileEnvironmentId();
    if (key === 'applications') {
      return appId ? items.filter((item) => recordId(item) === appId) : items;
    }
    if (key === 'environments') {
      return items.filter((item) => {
        const matchesApp = !appId || recordApplicationId(item) === appId;
        const matchesEnvironment = !environmentId || recordId(item) === environmentId;
        return matchesApp && matchesEnvironment;
      });
    }
    if (key === 'releases') {
      return items.filter((item) => !appId || recordApplicationId(item) === appId);
    }
    if (key === 'patches') {
      if (!appId) return items;
      const releaseIds = new Set(
        arrayValue(body.releases)
          .filter((release) => recordApplicationId(release) === appId)
          .map(recordId),
      );
      return items.filter((item) => releaseIds.has(stringValue(pick(item, 'releaseId', 'release_id'))));
    }
    if (key === 'artifacts') {
      if (!appId) return items;
      const patchIds = new Set(scopedItems('patches').map(recordId));
      return items.filter((item) => patchIds.has(stringValue(pick(item, 'patchId', 'patch_id'))));
    }
    if (key === 'rollouts') {
      return items.filter((item) => {
        const revision = objectValue(item.currentRevision);
        const target = objectValue(revision?.target);
        return (!appId || stringValue(pick(target, 'applicationId', 'application_id')) === appId) &&
          (!environmentId || stringValue(pick(target, 'environmentId', 'environment_id')) === environmentId);
      });
    }
    return items;
  }

  function customerApplications() {
    const appId = profileApplicationId();
    return arrayValue(state.overview?.applications).filter(
      (item) => !appId || recordId(item) === appId,
    );
  }

  function customerEnvironments() {
    const appId = profileApplicationId();
    const environmentId = profileEnvironmentId();
    return arrayValue(state.overview?.environments).filter((item) => (
      (!appId || recordApplicationId(item) === appId) &&
      (!environmentId || recordId(item) === environmentId)
    ));
  }

  function customerReleases() {
    const appId = profileApplicationId();
    return arrayValue(state.overview?.releases).filter(
      (item) => !appId || recordApplicationId(item) === appId,
    );
  }

  function newest(items, limit = 4, key = '') {
    return sortCollectionItems(items, key, 'newest').slice(0, limit);
  }

  function timestamp(record) {
    const value = stringValue(pick(record, 'createdAt', 'created_at'));
    const parsed = value ? Date.parse(value) : 0;
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  function recordSearchText(key, record) {
    const searchable = key === 'audit' ? safeAuditRecord(record) : record;
    let serialized = '';
    try {
      serialized = JSON.stringify(searchable) ?? '';
    } catch (error) {
      serialized = recordId(record) ?? '';
    }
    return `${RESOURCE_LABELS[key] ?? key} ${serialized}`.toLowerCase();
  }

  function collectionSortValue(key, record) {
    const fields = {
      applications: ['runtimeApplicationId', 'id'],
      environments: ['name', 'id'],
      releases: ['displayVersion', 'runtimeReleaseId', 'id'],
      patches: ['runtimePatchId', 'id'],
      artifacts: ['id', 'sha256'],
      rollouts: ['id'],
      audit: ['action', 'resourceType', 'id'],
    }[key] ?? ['id'];
    return fields
      .map((field) => stringValue(pick(record, field)))
      .find(Boolean) ?? '';
  }

  function recordStableKey(key, record) {
    const id = recordId(record);
    if (id) return id;
    return recordSearchText(key, record);
  }

  function sortCollectionItems(items, key, sort) {
    const decorated = items.map((item, index) => ({ item, index }));
    decorated.sort((left, right) => {
      let comparison = 0;
      if (sort === 'newest' || sort === 'oldest') {
        comparison = timestamp(left.item) - timestamp(right.item);
        if (sort === 'newest') comparison *= -1;
      } else {
        comparison = compareText(
          collectionSortValue(key, left.item),
          collectionSortValue(key, right.item),
        );
        if (sort === 'name-desc') comparison *= -1;
      }
      if (comparison !== 0) return comparison;
      comparison = compareText(
        recordStableKey(key, left.item),
        recordStableKey(key, right.item),
      );
      return comparison !== 0 ? comparison : left.index - right.index;
    });
    return decorated.map(({ item }) => item);
  }

  function renderMetricGrid(body) {
    const grid = element('div', 'metric-grid');
    const metrics = [
      ['applications', 'Applications'],
      ['environments', 'Environments'],
      ['releases', 'Releases'],
      ['patches', 'Patches'],
      ['artifacts', 'Artifacts'],
      ['rollouts', 'Rollout records'],
    ];
    for (const [key, label] of metrics) {
      const card = element('div', 'metric-card');
      const count = objectValue(body.counts)?.[key];
      card.append(element('span', 'metric-label', label));
      card.append(element('strong', 'metric-value', countValue(count)));
      card.append(element('span', 'metric-source', 'Organization-wide control-plane count'));
      grid.append(card);
    }
    return grid;
  }

  function renderContextPanel(body) {
    const profile = selectedProfile();
    const organization = objectValue(body.organization);
    const application = selectedApplicationRecord();
    const environment = selectedEnvironmentRecord();
    const { section, body: panelBody } = makePanel(
      'Selected context',
      'Identity and resource context for the active membership scope.',
      stringValue(pick(profile, 'role')) ?? 'Membership',
    );
    const fields = element('div', 'field-grid');
    fields.append(
      metadataItem('Organization', pick(organization, 'name'), { code: false }),
      metadataItem('Organization ID', pick(organization, 'id') ?? profileOrganizationId(), { code: true }),
      metadataItem('Application', pick(application, 'runtimeApplicationId') ?? (state.selectedApplication ? 'Selected application' : 'All applications'), { code: false }),
      metadataItem('Application ID', pick(application, 'id') ?? state.selectedApplication, { code: true }),
      metadataItem('Environment', pick(environment, 'name') ?? (state.selectedEnvironment ? 'Selected environment' : 'All environments'), { code: false }),
      metadataItem('Environment ID', pick(environment, 'id') ?? state.selectedEnvironment, { code: true }),
    );
    panelBody.append(fields);
    return section;
  }

  function renderRuntimeBoundaryPanel() {
    const { section, body: panelBody } = makePanel(
      'Runtime boundary',
      'A clear separation between control-plane records and installed-client authority.',
      'Contract boundary',
    );
    section.classList.add('boundary-panel');
    panelBody.append(
      element(
        'p',
        '',
        'This dashboard does not report client health, fleet activity, or delivery success. Those claims require runtime evidence from the installed client.',
      ),
    );
    const list = element('ul', 'boundary-list');
    list.append(
      boundaryRow('Record source', 'Control plane'),
      boundaryRow('Runtime authority', 'Installed client'),
      boundaryRow('Resource writes', 'None'),
    );
    panelBody.append(list);
    return section;
  }

  function boundaryRow(label, value) {
    const row = element('li');
    row.append(element('span', '', label), element('strong', '', value));
    return row;
  }

  function renderRecentPanel(title, items, type, key) {
    const { section, body: panelBody } = makePanel(
      title,
      `Most recent ${type} records returned by the selected projection.`,
      `${items.length} shown`,
    );
    if (items.length === 0) {
      const truncated = objectValue(state.overview?.truncated)?.[key] === true;
      const dependencyTruncation = collectionDependencyTruncation(state.overview, key);
      panelBody.append(stateBlock(
        'empty',
        truncated || dependencyTruncation
          ? `No ${type} records confirmed in the selected context`
          : `No ${type} records returned`,
        truncated || dependencyTruncation
          ? 'No loaded records were available for this context. The response or a required dependency is capped, so additional records may be available.'
          : 'The control plane returned an empty collection for this context.',
      ));
      return section;
    }
    const grid = element('div', 'record-grid');
    for (const item of items) {
      const card = element('article', 'record-card');
      if (type === 'release') {
        card.append(element('h3', '', pick(item, 'displayVersion') || recordId(item) || 'Release'));
        card.append(element('p', '', `${stringValue(pick(item, 'platformId')) ?? 'Platform not set'} / ${stringValue(pick(item, 'buildTarget')) ?? 'Build target not set'}`));
      } else {
        card.append(element('h3', '', pick(item, 'runtimePatchId') || recordId(item) || 'Patch'));
        card.append(element('p', '', `Sequence ${stringValue(pick(item, 'sequence')) ?? 'not set'} / ${stringValue(pick(item, 'state')) ?? 'state not set'}`));
      }
      const meta = element('div', 'record-meta');
      meta.append(codeValue(recordId(item)));
      meta.append(dateValue(pick(item, 'createdAt')));
      card.append(meta, exactRecordDetails(item));
      grid.append(card);
    }
    panelBody.append(grid);
    return section;
  }

  function renderAuditSummary(body) {
    const items = arrayValue(body.audit);
    const { section, body: panelBody } = makePanel(
      'Audit projection',
      'The overview includes redacted audit records. Cryptographic chain verification is not part of this response.',
      `${items.length} shown`,
    );
    const grid = element('div', 'verification-grid');
    grid.append(
      verificationCard('Record projection', 'Loaded', 'Redacted metadata only'),
      verificationCard('Chain verification', 'Not exposed', 'No validity claim is made'),
    );
    panelBody.append(grid);
    return section;
  }

  function verificationCard(label, value, detail) {
    const card = element('div', 'verification-card');
    card.append(element('span', 'metadata-label', label));
    card.append(element('strong', '', value));
    card.append(element('span', '', detail));
    return card;
  }

  function renderOverviewPage() {
    if (!state.overview) return unavailablePage('Overview data', overviewUnavailableReason());
    const body = state.overview;
    const stack = element('div', 'page-stack');
    stack.append(renderMetricGrid(body));
    const contextGrid = element('div', 'overview-grid');
    contextGrid.append(renderContextPanel(body), renderRuntimeBoundaryPanel());
    stack.append(contextGrid);
    const recentGrid = element('div', 'overview-grid');
    recentGrid.append(
      renderRecentPanel('Recent releases', newest(scopedItems('releases'), 4, 'releases'), 'release', 'releases'),
      renderRecentPanel('Recent patches', newest(scopedItems('patches'), 4, 'patches'), 'patch', 'patches'),
    );
    stack.append(recentGrid, renderAuditSummary(body));
    return stack;
  }

  function renderPlatformMetricGrid(snapshot) {
    const counts = objectValue(snapshot.counts) ?? {};
    const metrics = [
      ['organizations', 'Organizations'],
      ['activeUsers', 'Active users'],
      ['activeSessions', 'Active sessions'],
      ['applications', 'Applications'],
      ['environments', 'Environments'],
      ['releases', 'Releases'],
      ['patches', 'Patches'],
      ['rollouts', 'Rollout records'],
      ['auditEvents', 'Audit events'],
    ];
    const grid = element('div', 'metric-grid platform-metric-grid');
    for (const [key, label] of metrics) {
      const card = element('div', 'metric-card');
      card.append(
        element('span', 'metric-label', label),
        element('strong', 'metric-value', countValue(counts[key])),
        element('span', 'metric-source', 'Aggregate platform snapshot'),
      );
      grid.append(card);
    }
    return grid;
  }

  function renderPlatformActivityPanel(snapshot) {
    const activity = objectValue(snapshot.activity) ?? {};
    const last24h = objectValue(activity.last24h) ?? {};
    const last30d = objectValue(activity.last30d) ?? {};
    const panel = makePanel(
      'Recent platform activity',
      'New control-plane records created in the selected rolling windows. No tenant records are returned here.',
      'Aggregate only',
    );
    const fields = element('div', 'field-grid');
    for (const [key, label] of [
      ['organizations', 'Organizations'],
      ['users', 'Users'],
      ['applications', 'Applications'],
      ['environments', 'Environments'],
      ['releases', 'Releases'],
      ['patches', 'Patches'],
      ['rollouts', 'Rollouts'],
      ['auditEvents', 'Audit events'],
    ]) {
      const value = element('div');
      value.append(
        element('span', 'metadata-label', label),
        element('span', 'metadata-value', `24h ${countValue(last24h[key])} / 30d ${countValue(last30d[key])}`),
      );
      fields.append(value);
    }
    panel.body.append(fields);
    return panel.section;
  }

  function renderPlatformServicePanel(snapshot) {
    const serviceMetrics = objectValue(snapshot.serviceMetrics);
    const requests = objectValue(serviceMetrics?.requests);
    const requestCount = requests?.count;
    const errorCount = requests?.errors;
    const errorRate = typeof requestCount === 'number' && requestCount > 0 && typeof errorCount === 'number'
      ? `${((errorCount / requestCount) * 100).toFixed(2)}%`
      : 'Not available';
    const panel = makePanel(
      'Service health signals',
      'Process-local measurements from this control-plane instance. They are not a fleet availability or SLA claim.',
      'Instance scope',
    );
    const fields = element('div', 'field-grid');
    fields.append(
      metadataItem('Requests', countValue(requestCount)),
      metadataItem('Errors', countValue(errorCount)),
      metadataItem('Error rate', errorRate),
      metadataItem('Max latency', typeof requests?.maxDurationMicros === 'number' ? `${requests.maxDurationMicros} µs` : 'Not available'),
      metadataItem('Total processing time', typeof requests?.totalDurationMicros === 'number' ? `${requests.totalDurationMicros} µs` : 'Not available'),
      metadataItem('Snapshot generated', dateValue(snapshot.generatedAt)),
    );
    panel.body.append(fields);
    return panel.section;
  }

  function renderPlatformPage() {
    const viewTitle = state.currentView === 'platform-operations'
      ? 'Operations'
      : 'Platform overview';
    if (!hasPlatformCapability(platformCapabilityForView())) {
      return unavailablePage(
        viewTitle,
        'This profile is not configured for this Platform Console area.',
      );
    }
    if (!state.platformMetrics) {
      return unavailablePage(viewTitle, platformMetricsUnavailableReason());
    }
    const snapshot = state.platformMetrics;
    const stack = element('div', 'page-stack');
    const intro = makePanel(
      'Platform snapshot',
      'Read-only aggregate measurements across the configured Hyfens control-plane instance. Raw users, credentials, and tenant records are never exposed in this view.',
      'Read only',
    );
    intro.body.append(
      element('p', 'settings-note', 'Use these measurements for operational orientation. Durable analytics, billing, cohort reporting, and SLA reporting require a separate production telemetry system.'),
    );
    stack.append(intro.section, renderPlatformMetricGrid(snapshot));
    const details = element('div', 'overview-grid');
    details.append(
      renderPlatformActivityPanel(snapshot),
      renderPlatformServicePanel(snapshot),
    );
    stack.append(details);
    return stack;
  }

  function platformAccessUnavailable(title) {
    return unavailablePage(
      title,
      'This profile is not authorized for the requested Platform Console projection. The control plane remains the source of truth for this boundary.',
    );
  }

  function renderPlatformOrganizationsPage() {
    if (!hasPlatformCapability('platform:organizations:read')) {
      return platformAccessUnavailable('Organizations');
    }
    const projection = state.platformOrganizations;
    if (!projection) {
      return unavailablePage('Organizations', platformDataUnavailableReason('platform-organizations'));
    }
    const organizations = arrayValue(projection.organizations);
    const panel = makePanel(
      'Customer organizations',
      'Bounded organization metadata for platform operations. Customer secrets and tenant records are not returned by this directory.',
      `${organizations.length} returned`,
    );
    if (organizations.length === 0) {
      panel.body.append(stateBlock(
        'empty',
        'No organizations returned',
        'The platform projection did not return an organization matching the current directory scope.',
      ));
    } else {
      panel.body.append(recordTable(
        ['Organization', 'Status', 'Applications', 'Environments', 'Members', 'Last activity'],
        organizations,
        (organization) => {
          const id = organizationRecordId(organization);
          const name = stringValue(pick(organization, 'name')) ?? id ?? 'Organization';
          const link = element('a', 'global-search-result', name);
          link.href = viewPath('platform-organization', id);
          link.dataset.platformOrganizationId = id ?? '';
          link.setAttribute('aria-label', `Inspect ${name}`);
          return tableRow([
            primaryCell(link, id),
            statusTag(pick(organization, 'status')),
            countValue(pick(organization, 'applicationCount')),
            countValue(pick(organization, 'environmentCount')),
            countValue(pick(organization, 'memberCount')),
            dateValue(pick(organization, 'lastActivityAt')),
          ]);
        },
      ));
    }
    if (pick(projection, 'limits')?.maxOrganizations) {
      panel.body.append(element('p', 'collection-note', 'Directory results are bounded by the platform projection limit.'));
    }
    return panel.section;
  }

  function renderPlatformOrganizationPage() {
    if (!hasPlatformCapability('platform:organizations:inspect')) {
      return platformAccessUnavailable('Organization detail');
    }
    const projection = state.platformOrganization;
    if (!projection) {
      return unavailablePage('Organization detail', platformDataUnavailableReason('platform-organization'));
    }
    const organization = objectValue(projection.organization) ?? {};
    const name = stringValue(pick(organization, 'name')) ?? 'Organization';
    const stack = element('div', 'page-stack');
    const summary = makePanel(
      name,
      'Read-only platform inspection metadata. This view does not impersonate a customer member.',
      stringValue(pick(organization, 'status')) ?? 'Metadata only',
    );
    const fields = element('div', 'field-grid');
    fields.append(
      metadataItem('Organization ID', pick(organization, 'id'), { code: true }),
      metadataItem('Created', formatDateText(pick(organization, 'createdAt'))),
      metadataItem('Last activity', formatDateText(pick(organization, 'lastActivityAt'))),
      metadataItem('Members', countValue(pick(organization, 'memberCount'))),
      metadataItem('Applications', countValue(pick(organization, 'applicationCount'))),
      metadataItem('Environments', countValue(pick(organization, 'environmentCount'))),
    );
    summary.body.append(fields);
    stack.append(summary.section);

    const counts = objectValue(projection.counts) ?? {};
    const metricGrid = element('div', 'metric-grid');
    for (const [key, label] of [
      ['releases', 'Releases'],
      ['patches', 'Patches'],
      ['rollouts', 'Deployments'],
      ['auditEvents', 'Audit events'],
    ]) {
      const card = element('div', 'metric-card');
      card.append(
        element('span', 'metric-label', label),
        element('strong', 'metric-value', countValue(counts[key])),
        element('span', 'metric-source', 'Organization projection'),
      );
      metricGrid.append(card);
    }
    stack.append(metricGrid);

    const applications = arrayValue(projection.applications);
    const environments = arrayValue(projection.environments);
    const resources = element('div', 'overview-grid');
    const applicationsPanel = makePanel('Applications', 'Runtime identities registered to this organization.', `${applications.length} returned`);
    applicationsPanel.body.append(applications.length === 0
      ? stateBlock('empty', 'No applications returned', 'The organization projection contains no application metadata.')
      : recordTable(
        ['Application', 'Runtime identity', 'Created'],
        applications,
        (item) => tableRow([
          primaryCell(recordId(item)),
          codeValue(pick(item, 'runtimeApplicationId')),
          dateValue(pick(item, 'createdAt')),
        ]),
      ));
    const environmentsPanel = makePanel('Environments', 'Environment metadata returned for operational inspection.', `${environments.length} returned`);
    environmentsPanel.body.append(environments.length === 0
      ? stateBlock('empty', 'No environments returned', 'The organization projection contains no environment metadata.')
      : recordTable(
        ['Environment', 'Application', 'Version', 'Promoted release'],
        environments,
        (item) => tableRow([
          primaryCell(pick(item, 'name'), recordId(item)),
          codeValue(pick(item, 'applicationId')),
          stringValue(pick(item, 'version')) ?? 'Not set',
          codeValue(pick(item, 'promotedReleaseId')),
        ]),
      ));
    resources.append(applicationsPanel.section, environmentsPanel.section);
    stack.append(resources);
    return stack;
  }

  function renderPlatformAuditPage() {
    if (!hasPlatformCapability('platform:audit:read')) {
      return platformAccessUnavailable('Security & audit');
    }
    const projection = state.platformAudit;
    if (!projection) {
      return unavailablePage('Security & audit', platformDataUnavailableReason('platform-audit'));
    }
    const events = arrayValue(projection.events);
    const panel = makePanel(
      'Platform audit events',
      'Administrative and security events explicitly recorded for the platform audience. Customer audit rows are not relabeled here.',
      `${events.length} returned`,
    );
    panel.body.append(events.length === 0
      ? stateBlock('empty', 'No platform audit events', stringValue(pick(projection, 'note')) ?? 'No platform-audience events were returned.')
      : recordTable(
        ['Action', 'Organization', 'Resource', 'Result', 'Actor', 'Created', 'Exact record'],
        events,
        (item) => tableRow([
          primaryCell(pick(item, 'action'), pick(item, 'resourceType')),
          codeValue(pick(item, 'organizationId')),
          primaryCell(pick(item, 'resourceType'), pick(item, 'resourceId')),
          statusTag(pick(item, 'result')),
          codeValue(pick(item, 'actorId')),
          dateValue(pick(item, 'createdAt')),
          exactRecordDetails(item),
        ]),
      ));
    return panel.section;
  }

  function renderPlatformUsersPage() {
    if (!hasPlatformCapability('platform:accounts:read')) {
      return platformAccessUnavailable('Platform users');
    }
    const projection = state.platformUsers;
    if (!projection) {
      return unavailablePage('Platform users', platformDataUnavailableReason('platform-users'));
    }
    const users = arrayValue(projection.users);
    const panel = makePanel(
      'Hyfens staff',
      'Platform-audience staff metadata for operator access review. Customer members and credential material are excluded.',
      `${users.length} returned`,
    );
    panel.body.append(users.length === 0
      ? stateBlock('empty', 'No platform staff returned', 'No active platform capability memberships are present in this projection.')
      : recordTable(
        ['Staff', 'Status', 'Platform role / capabilities', 'Platform scopes', 'Created'],
        users,
        (user) => {
          const memberships = arrayValue(pick(user, 'memberships'));
          const capabilities = [...new Set(
            memberships.flatMap((membership) => arrayValue(pick(membership, 'platformCapabilities'))),
          )].sort(compareText);
          const roles = memberships
            .map((membership) => stringValue(pick(membership, 'role')))
            .filter(Boolean)
            .join(', ');
          return tableRow([
            primaryCell(pick(user, 'email'), pick(user, 'id')),
            statusTag(pick(user, 'active') === true ? 'active' : 'inactive'),
            primaryCell(roles || 'Role not set', `${memberships.length} platform membership${memberships.length === 1 ? '' : 's'}`),
            element('span', 'subvalue', capabilities.join(', ') || 'No capabilities'),
            dateValue(pick(user, 'createdAt')),
          ]);
        },
      ));
    return panel.section;
  }

  function formatMinorAmount(value, currency) {
    if (typeof value !== 'number' || !Number.isFinite(value)) return 'Not set';
    const normalizedCurrency = stringValue(currency)?.toUpperCase();
    return normalizedCurrency
      ? `${normalizedCurrency} ${(value / 100).toFixed(2)}`
      : `${(value / 100).toFixed(2)} units`;
  }

  function renderPlatformEntitlementsPage() {
    if (!hasPlatformCapability('platform:entitlements:read')) {
      return platformAccessUnavailable('Plans & entitlements');
    }
    const projection = state.platformEntitlements;
    if (!projection) {
      return unavailablePage('Plans & entitlements', platformDataUnavailableReason('platform-entitlements'));
    }
    const plans = arrayValue(projection.plans);
    const subscriptions = arrayValue(projection.subscriptions);
    const stack = element('div', 'page-stack');
    const plansPanel = makePanel(
      'Plans',
      'Read-only plan metadata. Provider identifiers and payment secrets are not exposed.',
      `${plans.length} returned`,
    );
    plansPanel.body.append(plans.length === 0
      ? stateBlock('empty', 'No plans returned', 'No billing plan records are configured in this control plane.')
      : recordTable(
        ['Plan', 'Organization', 'Price', 'Billing interval', 'Status'],
        plans,
        (plan) => tableRow([
          primaryCell(pick(plan, 'name') || pick(plan, 'key'), pick(plan, 'id')),
          primaryCell(pick(plan, 'organizationName') || 'Platform-wide', pick(plan, 'organizationId')),
          primaryCell(formatMinorAmount(pick(plan, 'amountMinor'), pick(plan, 'currency')), pick(plan, 'currency')),
          primaryCell(pick(plan, 'interval') || pick(plan, 'period') || 'Not set', pick(plan, 'description')),
          statusTag(pick(plan, 'active') === true ? 'active' : 'inactive'),
        ]),
      ));
    const subscriptionsPanel = makePanel(
      'Subscriptions',
      'Read-only organization subscription status and usage counters where configured.',
      `${subscriptions.length} returned`,
    );
    subscriptionsPanel.body.append(subscriptions.length === 0
      ? stateBlock('empty', 'No subscriptions returned', 'No organization subscriptions are configured in this control plane.')
      : recordTable(
        ['Organization', 'Status', 'Plan', 'Usage', 'Current period'],
        subscriptions,
        (subscription) => tableRow([
          primaryCell(pick(subscription, 'organizationName') || 'Organization', pick(subscription, 'organizationId')),
          statusTag(pick(subscription, 'status')),
          codeValue(pick(subscription, 'planId')),
          primaryCell(
            `${countValue(pick(subscription, 'paidCount'))} paid / ${countValue(pick(subscription, 'totalCount'))} total`,
            `${countValue(pick(subscription, 'remainingCount'))} remaining`,
          ),
          primaryCell(dateValue(pick(subscription, 'currentStartAt')), dateValue(pick(subscription, 'currentEndAt'))),
        ]),
      ));
    stack.append(plansPanel.section, subscriptionsPanel.section);
    return stack;
  }

  function renderPlatformSettingsPage() {
    if (!hasPlatformCapability('platform:overview')) {
      return platformAccessUnavailable('Platform settings');
    }
    const profile = selectedProfile();
    const panel = makePanel(
      'Platform access boundary',
      'Operator metadata for this console. Configuration mutations and customer membership management remain outside this read-focused MVP.',
      'Read only',
    );
    const fields = element('div', 'field-grid');
    fields.append(
      metadataItem('Audience', pick(profile, 'audience') ?? 'platform'),
      metadataItem('Profile', pick(profile, 'name')),
      metadataItem('Role', pick(profile, 'role')),
      metadataItem('Control plane', displayEndpoint(), { code: !isManagedControlPlaneEndpoint() }),
      metadataItem('Platform capabilities', arrayValue(pick(profile, 'platformCapabilities', 'platform_capabilities')).join(', ') || 'None'),
      metadataItem('Signed-in identity', pick(state.identity, 'email')),
    );
    panel.body.append(fields);
    panel.body.append(element('p', 'settings-note', 'The Platform Console does not include a customer organization switcher. Open an organization from the bounded directory when an authorized inspection is required.'));
    return panel.section;
  }

  function truncatedCollectionKeys(body = state.overview) {
    const truncated = objectValue(body?.truncated);
    return RESOURCE_KEYS.filter((key) => (
      truncated?.[key] === true || Boolean(collectionDependencyTruncation(body, key))
    ));
  }

  function overviewHasTruncatedCollections(body = state.overview) {
    return truncatedCollectionKeys(body).length > 0;
  }

  function renderGlobalSearchPage() {
    if (!state.overview) return unavailablePage('Search results', overviewUnavailableReason());
    const query = normalizeSearchQuery(state.globalSearchQuery);
    const displayQuery = stringValue(state.globalSearchQuery)?.trim() ?? query;
    const truncated = overviewHasTruncatedCollections();
    const matchesByKey = [];
    let matchCount = 0;
    for (const key of RESOURCE_KEYS) {
      const sourceItems = scopedItems(key);
      const matches = sortCollectionItems(
        sourceItems.filter((item) => recordSearchText(key, item).includes(query)),
        key,
        'newest',
      );
      if (matches.length > 0) {
        matchesByKey.push({ key, items: matches });
        matchCount += matches.length;
      }
    }

    const stack = element('div', 'page-stack');
    const summaryPanel = makePanel(
      'Record search',
      truncated
        ? `Loaded authoritative records matching “${displayQuery}” in the selected context. Some collections are capped.`
        : `Authoritative records returned for the selected context matching “${displayQuery}”.`,
      `${matchCount} match${matchCount === 1 ? '' : 'es'}`,
    );
    if (matchCount === 0) {
      const noMatch = stateBlock(
        'empty',
        'No matching records',
        truncated
          ? 'No loaded records match this search. Some collections are capped, so more matching records may be available.'
          : 'No returned authoritative records match this search. Try an ID, name, state, or action.',
      );
      noMatch.dataset.state = 'no-match';
      noMatch.classList.add('global-search-empty-state');
      summaryPanel.body.append(noMatch);
      stack.append(summaryPanel.section);
      return stack;
    }
    stack.append(summaryPanel.section);

    for (const { key, items } of matchesByKey) {
      const group = makePanel(
        RESOURCE_LABELS[key],
        `Matching ${RESOURCE_LABELS[key].toLowerCase()} in the current context.`,
        `${items.length} match${items.length === 1 ? '' : 'es'}`,
      );
      const grid = element('div', 'record-grid');
      for (const item of items) grid.append(globalSearchRecordCard(key, item));
      group.body.append(grid);
      stack.append(group.section);
    }
    return stack;
  }

  function globalSearchRecordCard(key, item) {
    const card = element('article', 'record-card');
    const heading = element('h3');
    const title = recordSearchTitle(key, item);
    const link = element('a', 'global-search-result', title);
    const view = searchViewForKey(key);
    link.href = viewPath(view);
    link.dataset.searchResultView = view;
    link.setAttribute('aria-label', `Open ${RESOURCE_LABELS[key].toLowerCase()} for ${title}`);
    heading.append(link);
    card.append(heading);

    const subtitle = recordSearchSubtitle(key, item);
    if (subtitle) card.append(element('p', '', subtitle));
    const meta = element('div', 'record-meta');
    const id = recordId(item) ?? stringValue(pick(item, 'resourceId', 'resource_id'));
    if (id) meta.append(codeValue(id));
    if (recordStatusValue(key, item)) meta.append(statusTag(recordStatusValue(key, item)));
    if (pick(item, 'createdAt', 'created_at')) meta.append(dateValue(pick(item, 'createdAt', 'created_at')));
    card.append(meta, exactRecordDetails(key === 'audit' ? safeAuditRecord(item) : item));
    return card;
  }

  function recordSearchTitle(key, record) {
    const fields = {
      applications: ['runtimeApplicationId', 'id'],
      environments: ['name', 'id'],
      releases: ['displayVersion', 'runtimeReleaseId', 'id'],
      patches: ['runtimePatchId', 'id'],
      artifacts: ['id', 'sha256'],
      rollouts: ['id'],
      audit: ['action', 'resourceType', 'id'],
    }[key] ?? ['id'];
    return fields.map((field) => stringValue(pick(record, field))).find(Boolean)
      ?? `${RESOURCE_LABELS[key]} record`;
  }

  function recordSearchSubtitle(key, record) {
    const values = [];
    if (key === 'audit') {
      values.push(stringValue(pick(record, 'resourceType')));
      values.push(stringValue(pick(record, 'resourceId')));
    } else if (key === 'releases') {
      values.push(stringValue(pick(record, 'platformId')));
      values.push(stringValue(pick(record, 'buildTarget')));
    } else if (key === 'environments') {
      values.push(stringValue(pick(record, 'version')));
    } else if (key === 'artifacts') {
      values.push(stringValue(pick(record, 'contentType')));
    }
    return values.filter(Boolean).join(' / ');
  }

  function searchViewForKey(key) {
    return key === 'rollouts' ? 'deployments' : key;
  }

  function renderApplicationCreatePanel() {
    const panel = makePanel(
      'Register an application',
      'Bind one Android package or iOS bundle identity to this customer organization. Create a separate application record when the platform identity differs.',
      hasCustomerCapability('application:write') ? 'Customer action' : 'CLI handoff',
    );
    if (!hasCustomerCapability('application:write')) {
      panel.body.append(cliHandoff(
        'Application registration is not available for this profile.',
        'Use the authenticated CLI profile to initialize the project and register its runtime identity.',
        ['hyfens init', 'hyfens release android --metadata-only'],
      ));
      return panel.section;
    }
    const form = element('form', 'action-form');
    form.dataset.dashboardAction = 'application-create';
    const name = element('input');
    name.type = 'text';
    name.name = 'name';
    name.placeholder = 'Kavach360 Android';
    name.maxLength = 120;
    name.required = true;
    name.autocomplete = 'off';
    const platform = element('select');
    platform.name = 'platform';
    platform.required = true;
    for (const value of ['android', 'ios']) {
      const option = element('option', '', value[0].toUpperCase() + value.slice(1));
      option.value = value;
      platform.append(option);
    }
    const runtimeId = element('input');
    runtimeId.type = 'text';
    runtimeId.name = 'runtime_application_id';
    runtimeId.placeholder = 'com.example.app';
    runtimeId.required = true;
    runtimeId.maxLength = 256;
    runtimeId.autocomplete = 'off';
    const fields = element('div', 'action-form-grid');
    fields.append(
      formField('Application name', name, 'A display name for the workspace.'),
      formField('Platform', platform),
      formField('Package or bundle identity', runtimeId, 'This identity is immutable once a release is registered.'),
    );
    const actions = element('div', 'action-form-actions');
    actions.append(actionSubmitButton('application-create', 'Register application'));
    form.append(fields);
    const error = actionErrorMessage('application-create');
    if (error) form.append(error);
    form.append(actions);
    panel.body.append(form);
    return panel.section;
  }

  function renderApplicationsPage() {
    if (!state.overview) return unavailablePage('Applications', overviewUnavailableReason());
    const body = state.overview;
    const items = scopedItems('applications');
    const stack = element('div', 'page-stack');
    stack.append(
      renderApplicationCreatePanel(),
      collectionPanel(
        body,
        'applications',
        'Applications',
        'Runtime application identities registered for the selected organization.',
        ['Application', 'Runtime identity', 'Platform', 'Created', 'Exact record'],
        items,
        (item) => tableRow([
          primaryCell(pick(item, 'name') || recordId(item), recordId(item)),
          codeValue(pick(item, 'runtimeApplicationId')),
          statusTag(pick(item, 'platform'), 'Not specified'),
          dateValue(pick(item, 'createdAt')),
          exactRecordDetails(item),
        ]),
        'The control plane returned no application records for this membership scope.',
      ),
    );
    return stack;
  }

  function renderEnvironmentCreatePanel() {
    const panel = makePanel(
      'Create an environment',
      'Add a version pointer under an application. Environments start at version zero and are promoted only through an authorized release action.',
      hasCustomerCapability('environment:write') ? 'Customer action' : 'CLI handoff',
    );
    if (!hasCustomerCapability('environment:write')) {
      panel.body.append(cliHandoff(
        'Environment creation is not available for this profile.',
        'Use the CLI project workflow for local setup, then return here to inspect the environment.',
        ['hyfens init', 'hyfens status'],
      ));
      return panel.section;
    }
    const applications = customerApplications();
    if (applications.length === 0) {
      panel.body.append(stateBlock('empty', 'Create an application first', 'An environment must belong to an existing customer application.'));
      return panel.section;
    }
    const form = element('form', 'action-form');
    form.dataset.dashboardAction = 'environment-create';
    const application = element('select');
    application.name = 'application_id';
    application.required = true;
    for (const item of applications) {
      const option = element('option', '', `${pick(item, 'name') || pick(item, 'runtimeApplicationId') || 'Application'} / ${recordId(item)}`);
      option.value = recordId(item) ?? '';
      application.append(option);
    }
    const name = element('input');
    name.type = 'text';
    name.name = 'name';
    name.placeholder = 'staging';
    name.maxLength = 64;
    name.required = true;
    name.autocomplete = 'off';
    const fields = element('div', 'action-form-grid');
    fields.append(
      formField('Application', application),
      formField('Environment name', name, 'Names are unique per application, case-insensitively.'),
    );
    const actions = element('div', 'action-form-actions');
    actions.append(actionSubmitButton('environment-create', 'Create environment'));
    form.append(fields);
    const error = actionErrorMessage('environment-create');
    if (error) form.append(error);
    form.append(actions);
    panel.body.append(form);
    return panel.section;
  }

  function renderEnvironmentsPage() {
    if (!state.overview) return unavailablePage('Environments', overviewUnavailableReason());
    const body = state.overview;
    const items = scopedItems('environments');
    const stack = element('div', 'page-stack');
    stack.append(
      renderEnvironmentCreatePanel(),
      collectionPanel(
        body,
        'environments',
        'Environments',
        'Environment version pointers and promoted release references.',
        ['Environment', 'Application', 'Version', 'Promoted release', 'Created', 'Exact record'],
        items,
        (item) => tableRow([
          primaryCell(pick(item, 'name'), recordId(item)),
          codeValue(pick(item, 'applicationId')),
          stringValue(pick(item, 'version')) ?? 'Not set',
          codeValue(pick(item, 'promotedReleaseId')),
          dateValue(pick(item, 'createdAt')),
          exactRecordDetails(item),
        ]),
        'The control plane returned no environment records for this membership scope.',
      ),
    );
    return stack;
  }

  function renderReleasesPage() {
    if (!state.overview) return unavailablePage('Releases', overviewUnavailableReason());
    const body = state.overview;
    const items = scopedItems('releases');
    return collectionPanel(
      body,
      'releases',
      'Releases',
      'Release records are immutable identities. Values below are rendered from the authoritative response.',
      ['Release', 'Platform / build', 'Runtime release', 'Compatibility', 'Created', 'Exact record'],
      items,
      (item) => tableRow([
        primaryCell(pick(item, 'displayVersion'), recordId(item)),
        primaryCell(pick(item, 'platformId'), pick(item, 'buildTarget')),
        codeValue(pick(item, 'runtimeReleaseId')),
        primaryCell(`Runtime ${stringValue(pick(item, 'runtimeCompatibilityVersion')) ?? 'not set'}`, `Patch format ${stringValue(pick(item, 'patchFormatVersion')) ?? 'not set'}`),
        dateValue(pick(item, 'createdAt')),
        exactRecordDetails(item),
      ]),
      'The control plane returned no release records for this membership scope.',
    );
  }

  function renderPatchesPage() {
    if (!state.overview) return unavailablePage('Patches', overviewUnavailableReason());
    const body = state.overview;
    const items = scopedItems('patches');
    return collectionPanel(
      body,
      'patches',
      'Patches',
      'Patch records retain exact sequence, artifact, digest, and signature references.',
      ['Patch', 'Sequence / state', 'Release', 'Artifact / size', 'SHA-256', 'Created', 'Exact record'],
      items,
      (item) => tableRow([
        primaryCell(pick(item, 'runtimePatchId'), recordId(item)),
        primaryCell(pick(item, 'sequence'), statusTag(pick(item, 'state'))),
        codeValue(pick(item, 'releaseId')),
        primaryCell(pick(item, 'artifactId'), formatBytes(pick(item, 'sizeBytes'))),
        codeValue(pick(item, 'sha256')),
        dateValue(pick(item, 'createdAt')),
        exactRecordDetails(item),
      ]),
      'The control plane returned no patch records for this membership scope.',
    );
  }

  function renderArtifactsPage() {
    if (!state.overview) return unavailablePage('Artifacts', overviewUnavailableReason());
    const body = state.overview;
    const items = scopedItems('artifacts');
    return collectionPanel(
      body,
      'artifacts',
      'Artifacts',
      'Artifact records retain exact patch linkage, digest, size, and content type.',
      ['Artifact', 'Patch', 'SHA-256', 'Size / type', 'State', 'Created', 'Exact record'],
      items,
      (item) => tableRow([
        primaryCell(recordId(item)),
        codeValue(pick(item, 'patchId')),
        codeValue(pick(item, 'sha256')),
        primaryCell(formatBytes(pick(item, 'sizeBytes')), pick(item, 'contentType')),
        statusTag(pick(item, 'state')),
        dateValue(pick(item, 'createdAt')),
        exactRecordDetails(item),
      ]),
      'The control plane returned no artifact records for this membership scope.',
    );
  }

  function renderPromotionPanel() {
    const canPromote = hasCustomerCapability('release:promote');
    const panel = makePanel(
      'Delivery actions',
      'Promotion changes the selected environment pointer only after the control plane verifies a matching ready patch and artifact.',
      canPromote ? 'Explicit confirmation' : 'CLI handoff',
    );
    if (!canPromote) {
      panel.body.append(cliHandoff(
        'Browser promotion is not available for this profile.',
        'Use the CLI for release and patch creation. The same server-side authorization and verification rules apply there.',
        ['hyfens release android', 'hyfens patch android', 'hyfens deploy', 'hyfens rollback --help'],
      ));
      return panel.section;
    }
    const environments = customerEnvironments();
    const releases = customerReleases();
    if (environments.length === 0 || releases.length === 0) {
      panel.body.append(stateBlock(
        'empty',
        environments.length === 0 ? 'Create an environment first' : 'Create a release first',
        'Promotion becomes available after an environment and release exist in this customer context. A verified ready patch is still required by the control plane.',
      ));
      panel.body.append(cliHandoff(
        'Continue from the project directory',
        'Release and patch artifacts are created from the local Flutter source tree.',
        ['hyfens release android', 'hyfens patch android'],
      ));
      return panel.section;
    }
    const form = element('form', 'action-form');
    form.dataset.dashboardAction = 'promotion';
    const environment = element('select');
    environment.name = 'environment_id';
    environment.required = true;
    for (const item of environments) {
      const option = element('option', '', `${pick(item, 'name') || 'Environment'} / ${recordId(item)} / v${pick(item, 'version') ?? 0}`);
      option.value = recordId(item) ?? '';
      option.dataset.environmentVersion = String(pick(item, 'version') ?? 0);
      environment.append(option);
    }
    environment.dataset.promotionEnvironment = 'true';
    const release = element('select');
    release.name = 'release_id';
    release.required = true;
    for (const item of releases) {
      const option = element('option', '', `${pick(item, 'displayVersion') || pick(item, 'runtimeReleaseId') || 'Release'} / ${recordId(item)}`);
      option.value = recordId(item) ?? '';
      release.append(option);
    }
    const expectedVersion = element('input');
    expectedVersion.type = 'number';
    expectedVersion.name = 'expected_version';
    expectedVersion.min = '0';
    expectedVersion.step = '1';
    expectedVersion.value = String(pick(environments[0], 'version') ?? 0);
    expectedVersion.required = true;
    expectedVersion.readOnly = true;
    const fields = element('div', 'action-form-grid');
    fields.append(
      formField('Target environment', environment),
      formField('Release', release, 'The server verifies that a ready patch for this release exists.'),
      formField('Current environment version', expectedVersion, 'Promotion fails closed if this value is stale.'),
    );
    const actions = element('div', 'action-form-actions');
    actions.append(actionSubmitButton('promotion', 'Promote release'));
    const error = actionErrorMessage('promotion');
    form.append(fields);
    if (error) form.append(error);
    form.append(actions);
    panel.body.append(form);
    panel.body.append(cliHandoff(
      'Release and patch creation stays in the CLI',
      'The browser action above promotes an already verified remote artifact. Rollback remains an explicit CLI/runtime operation.',
      ['hyfens release android', 'hyfens patch android', 'hyfens rollback --help'],
    ));
    return panel.section;
  }

  function renderDeploymentsPage() {
    if (!state.overview) return unavailablePage('Deployment records', overviewUnavailableReason());
    const body = state.overview;
    const items = scopedItems('rollouts');
    const stack = element('div', 'page-stack');
    stack.append(
      renderPromotionPanel(),
      collectionPanel(
        body,
        'rollouts',
        'Deployment records',
        'The backend exposes rollout policy records, not a runtime deployment success signal.',
        ['Rollout', 'State', 'Revision', 'Target', 'Policy', 'Exact record'],
        items,
        (item) => {
          const revision = objectValue(item.currentRevision);
          const target = objectValue(revision?.target);
          const policy = objectValue(revision?.policy);
          return tableRow([
            primaryCell(recordId(item), `Created ${formatDateText(pick(item, 'createdAt'))}`),
            statusTag(pick(item, 'state')),
            primaryCell(pick(revision, 'revision'), statusTag(pick(item, 'currentRevisionStatus'))),
            compoundCell([
              ['Environment', pick(target, 'environmentId')],
              ['Release', pick(target, 'releaseId')],
              ['Patch', pick(target, 'patchId')],
            ]),
            policyCell(policy),
            exactRecordDetails(item),
          ]);
        },
        'The control plane returned no rollout records for this membership scope.',
      ),
    );
    return stack;
  }

  function compoundCell(entries) {
    const wrapper = element('div');
    for (const [label, value] of entries) {
      const line = element('span', 'subvalue');
      line.append(element('span', '', `${label}: `), codeValue(value));
      wrapper.append(line);
    }
    return wrapper;
  }

  function policyCell(policy) {
    if (!policy) return element('span', 'metadata-value muted', 'Current revision not available');
    const wrapper = element('div');
    const cohort = stringValue(pick(policy, 'cohortKind')) ?? 'Cohort not set';
    wrapper.append(element('strong', '', cohort));
    if (cohort.toLowerCase() === 'percentage') {
      wrapper.append(element('span', 'subvalue', formatBasisPoints(pick(policy, 'percentageBasisPoints'))));
    } else {
      wrapper.append(element('span', 'subvalue', 'Internal cohort; raw installation hashes are not exposed'));
    }
    return wrapper;
  }

  function renderAuditPage() {
    if (!state.overview) return unavailablePage('Audit records', overviewUnavailableReason());
    const body = state.overview;
    const items = arrayValue(body.audit);
    const stack = element('div', 'page-stack');
    const integrity = makePanel(
      'Audit integrity boundary',
      'The overview projection is redacted and read-only. It does not include the audit-chain verification result.',
      'No mutation controls',
    );
    const grid = element('div', 'verification-grid');
    grid.append(
      verificationCard('Record semantics', 'Immutable source', 'Records are never edited here'),
      verificationCard('Chain status', 'Unavailable', 'No validity claim is made'),
    );
    integrity.body.append(grid);
    stack.append(integrity.section);
    stack.append(
      collectionPanel(
        body,
        'audit',
        'Audit events',
        'Organization-scoped events returned by the safe overview projection.',
        ['Event', 'Action / result', 'Resource', 'Actor', 'Created', 'Metadata'],
        items,
        (item) => tableRow([
          primaryCell(pick(item, 'id'), pick(item, 'requestId')),
          primaryCell(pick(item, 'action'), statusTag(pick(item, 'result'))),
          primaryCell(pick(item, 'resourceType'), pick(item, 'resourceId')),
          codeValue(pick(item, 'actorId')),
          dateValue(pick(item, 'createdAt')),
          exactRecordDetails(safeAuditRecord(item)),
        ]),
        'The control plane returned no audit events for this organization.',
      ),
    );
    return stack;
  }

  function safeAuditRecord(record) {
    return safeAuditValue(record, SAFE_AUDIT_RECORD_KEYS) ?? {};
  }

  function safeAuditValue(value, allowedKeys) {
    if (Array.isArray(value)) return undefined;
    if (objectValue(value)) {
      const result = {};
      for (const [childKey, childValue] of Object.entries(value)) {
        if (!allowedKeys?.has(childKey)) continue;
        const childAllowedKeys = childKey === 'metadata'
          ? SAFE_AUDIT_METADATA_KEYS
          : allowedKeys;
        const safeChild = safeAuditValue(childValue, childAllowedKeys);
        if (safeChild !== undefined) result[childKey] = safeChild;
      }
      return result;
    }
    if (value === null || typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') return value;
    return undefined;
  }

  function renderOrganizationMembersPanel() {
    const members = state.organizationMembers;
    const panel = makePanel(
      'Team members',
      'Members of the selected customer organization. Passwords, sessions, and credential material are never returned.',
      members ? `${members.length} returned` : 'Loading',
    );
    if (!members) {
      panel.body.append(stateBlock('unavailable', 'Member metadata unavailable', customerSettingsUnavailableReason('members')));
      return panel.section;
    }
    if (members.length === 0) {
      panel.body.append(stateBlock('empty', 'No members returned', 'The selected organization has no member metadata in the current projection.'));
      return panel.section;
    }
    panel.body.append(recordTable(
      ['Member', 'Status', 'Role / capabilities', 'Application / environment', 'Joined'],
      members,
      (member) => {
        const membership = objectValue(arrayValue(pick(member, 'memberships'))[0]);
        const capabilities = arrayValue(pick(membership, 'capabilities'))
          .map(stringValue)
          .filter(Boolean);
        const roleDetails = [
          stringValue(pick(membership, 'profileName')) && `Profile ${pick(membership, 'profileName')}`,
          capabilities.length > 0 ? `Capabilities: ${capabilities.join(', ')}` : null,
        ].filter(Boolean).join(' · ');
        return tableRow([
          primaryCell(pick(member, 'email'), pick(member, 'id')),
          statusTag(pick(member, 'active') === true ? 'active' : 'inactive'),
          primaryCell(pick(membership, 'role'), roleDetails || undefined),
          primaryCell(
            pick(membership, 'applicationId') ?? 'All applications',
            pick(membership, 'environmentId') ?? 'All environments',
          ),
          dateValue(pick(member, 'createdAt')),
        ]);
      },
    ));
    panel.body.append(element('p', 'settings-note', 'Member invitations and role changes are not exposed until their server contracts are available. This view is metadata-only.'));
    return panel.section;
  }

  function credentialScopePresets() {
    return [
      {
        value: 'read',
        label: 'Read only',
        scopes: ['application:read', 'release:read', 'patch:read', 'artifact:read', 'rollout:read', 'audit:read'],
      },
      {
        value: 'developer',
        label: 'Developer',
        scopes: ['application:read', 'application:write', 'environment:write', 'release:read', 'release:write', 'patch:read', 'patch:write', 'artifact:read', 'artifact:write', 'rollout:read', 'audit:read'],
      },
      {
        value: 'operator',
        label: 'Release operator',
        scopes: ['application:read', 'environment:write', 'release:read', 'release:write', 'release:promote', 'patch:read', 'patch:write', 'artifact:read', 'artifact:write', 'rollout:read', 'rollout:create', 'rollout:update', 'rollout:promote', 'rollout:halt', 'audit:read'],
      },
    ];
  }

  function renderIssuedCredential() {
    const issued = objectValue(state.issuedCredential);
    const token = stringValue(issued?.token);
    if (!token) return null;
    const wrapper = element('div', 'one-time-secret');
    wrapper.append(
      element('strong', '', 'Credential created — copy it now'),
      element('p', 'form-hint', 'This secret is displayed once and will not be returned by a later request.'),
    );
    const value = element('code', 'secret-value', token);
    value.setAttribute('aria-label', 'New credential secret');
    const copy = element('button', 'button button-secondary', 'Copy credential');
    copy.type = 'button';
    copy.dataset.copyCredential = 'true';
    wrapper.append(value, copy);
    return wrapper;
  }

  function renderCredentialIssueForm() {
    const wrapper = element('div', 'action-form-inset');
    const canIssue = hasCustomerCapability('credential:issue');
    wrapper.append(
      element('h3', '', 'Create credential'),
      element('p', 'form-hint', canIssue
        ? 'Issue a scoped service credential for CLI or CI use. The plaintext secret is shown exactly once.'
        : 'Credential issuance is not available for the selected profile.'),
    );
    if (!canIssue) return wrapper;
    const form = element('form', 'action-form');
    form.dataset.dashboardAction = 'credential-issue';
    const name = element('input');
    name.type = 'text';
    name.name = 'name';
    name.placeholder = 'Kavach360 CI';
    name.maxLength = 120;
    name.required = true;
    name.autocomplete = 'off';
    const preset = element('select');
    preset.name = 'scope_preset';
    preset.required = true;
    for (const item of credentialScopePresets()) {
      const option = element('option', '', item.label);
      option.value = item.value;
      preset.append(option);
    }
    const expiry = element('select');
    expiry.name = 'expiry_days';
    for (const [value, label] of [
      ['0', 'No expiry'],
      ['30', '30 days'],
      ['90', '90 days'],
      ['365', '1 year'],
    ]) {
      const option = element('option', '', label);
      option.value = value;
      expiry.append(option);
    }
    const fields = element('div', 'action-form-grid');
    fields.append(
      formField('Credential name', name),
      formField('Scope', preset),
      formField('Expiration', expiry, 'Short-lived credentials are recommended for CI and demos.'),
    );
    const actions = element('div', 'action-form-actions');
    actions.append(actionSubmitButton('credential-issue', 'Generate credential'));
    const error = actionErrorMessage('credential-issue');
    form.append(fields);
    if (error) form.append(error);
    form.append(actions);
    wrapper.append(form);
    return wrapper;
  }

  function renderCredentialsPanel() {
    const credentials = state.credentials;
    const panel = makePanel(
      'Credentials',
      'Customer service credentials are shown as metadata only. A token is displayed once at issuance and cannot be recovered from this page.',
      credentials ? `${credentials.length} returned` : 'Loading',
    );
    panel.body.append(renderCredentialIssueForm());
    const issued = renderIssuedCredential();
    if (issued) panel.body.append(issued);
    if (!credentials) {
      panel.body.append(stateBlock('unavailable', 'Credential metadata unavailable', customerSettingsUnavailableReason('credentials')));
      return panel.section;
    }
    if (credentials.length === 0) {
      panel.body.append(stateBlock('empty', 'No credentials returned', 'No customer service credentials are currently recorded for this organization.'));
      return panel.section;
    }
    panel.body.append(recordTable(
      ['Credential', 'Kind / scope', 'Application / environment', 'Status', 'Created', 'Action'],
      credentials,
      (credential) => {
        const scopes = arrayValue(pick(credential, 'scopes'));
        const action = pick(credential, 'revoked') === true
          ? statusTag('revoked')
          : !hasCustomerCapability('credential:revoke')
            ? element('span', 'metadata-value muted', 'Not authorized')
          : (() => {
            const button = element('button', 'button button-quiet button-danger', 'Revoke');
            button.type = 'button';
            button.dataset.credentialRevoke = stringValue(pick(credential, 'id')) ?? '';
            return button;
          })();
        return tableRow([
          primaryCell(pick(credential, 'id'), pick(credential, 'kind')),
          element('span', 'subvalue', scopes.length > 0 ? scopes.join(', ') : 'No scopes'),
          primaryCell(
            pick(credential, 'applicationId') ?? 'Organization-wide',
            pick(credential, 'environmentId') ?? 'All environments',
          ),
          pick(credential, 'revoked') === true ? statusTag('revoked') : statusTag('active'),
          dateValue(pick(credential, 'createdAt')),
          action,
        ]);
      },
    ));
    return panel.section;
  }

  function renderSettingsPage() {
    const identity = state.identity;
    const profile = selectedProfile();
    const sessionPanel = makePanel(
      'Human session',
      'Session material is held in tab-scoped storage for refresh restoration; the password is never stored.',
      'Shared auth authority',
    );
    const fields = element('div', 'field-grid');
    fields.append(
      metadataItem('Email', pick(identity, 'email')),
      metadataItem('User ID', pick(identity, 'user_id', 'userId'), { code: true }),
      metadataItem('Control plane', displayEndpoint(), { code: !isManagedControlPlaneEndpoint() }),
      metadataItem('Access token expiry', state.api?.accessExpiresAt ? formatDateText(state.api.accessExpiresAt) : 'Not returned'),
      metadataItem('Session expiry', state.api?.sessionExpiresAt ? formatDateText(state.api.sessionExpiresAt) : 'Not returned'),
      metadataItem('Selected role', pick(profile, 'role')),
    );
    sessionPanel.body.append(fields);
    sessionPanel.body.append(element('p', 'settings-note', 'Sign out revokes the shared human session when the control plane responds. Session material is cleared from this tab even if the remote service is unavailable.'));

    const customerProfiles = customerProfileList();
    const membershipsPanel = makePanel(
      'Your workspaces',
      'Customer memberships returned by /auth/me. Platform operator profiles are intentionally kept out of this workspace context.',
      `${customerProfiles.length} returned`,
    );
    const list = element('ul', 'membership-list');
    if (customerProfiles.length === 0) {
      list.append(stateBlock('unavailable', 'Membership unavailable', 'The auth service did not return a customer workspace membership.'));
    } else {
      for (const item of customerProfiles) {
        const row = element('li');
        const title = element('strong', '', pick(item, 'name') || 'Profile');
        const details = element('span');
        details.append(
          `Role ${stringValue(pick(item, 'role')) ?? 'not set'} / `,
          codeValue(profileOrganizationId(item)),
        );
        const appId = stringValue(pick(item, 'applicationId', 'application_id'));
        const envId = stringValue(pick(item, 'environmentId', 'environment_id'));
        details.append(element('br'));
        details.append(`Application ${appId ?? 'all'} / Environment ${envId ?? 'all'}`);
        row.append(title, details);
        list.append(row);
      }
    }
    membershipsPanel.body.append(list);

    const stack = element('div', 'settings-grid');
    const left = element('div', 'page-stack');
    left.append(sessionPanel.section, membershipsPanel.section);
    const right = element('div', 'page-stack');
    right.append(renderOrganizationMembersPanel(), renderCredentialsPanel());
    stack.append(left, right);
    return stack;
  }

  function unavailablePage(title, reason) {
    const { section, body } = makePanel(title, 'The shell remains available while this backend capability is unresolved.', 'Unavailable');
    body.append(stateBlock('unavailable', `${title} unavailable`, reason));
    return section;
  }

  function overviewUnavailableReason() {
    const error = state.overviewError;
    if (error?.status === 404) return 'The configured control plane does not expose the overview projection for this route.';
    if (error?.status === 401 || error?.status === 403) {
      return 'The current overview projection rejected the human session. This dashboard does not request a legacy control credential, so no resource data is substituted.';
    }
    if (error?.status === 503) return 'The control plane reported that the overview dependency is unavailable.';
    if (error) return 'The control plane did not return a safe read-only overview. Check the endpoint and try again.';
    return 'The dashboard has not received a safe read-only overview from the configured control plane.';
  }

  function platformMetricsUnavailableReason() {
    const error = state.platformMetricsError;
    if (error?.status === 404) return 'The configured control plane does not expose platform metrics.';
    if (error?.status === 401) return 'The human session could not be authenticated for platform metrics.';
    if (error?.status === 403) return 'The selected profile is not authorized for platform-level metrics.';
    if (error?.status === 503) return 'Human authentication or the platform metrics dependency is unavailable.';
    if (error) return 'The control plane did not return a safe platform metrics snapshot. Check the endpoint and try again.';
    return 'The dashboard has not received a platform metrics snapshot yet.';
  }

  function platformDataUnavailableReason(view) {
    const error = view === 'platform-organizations'
      ? state.platformOrganizationsError
      : view === 'platform-organization'
        ? state.platformOrganizationError
        : view === 'platform-audit'
          ? state.platformAuditError
          : view === 'platform-users'
            ? state.platformUsersError
            : state.platformEntitlementsError;
    if (error?.status === 404) return 'The configured control plane does not expose this Platform Console projection.';
    if (error?.status === 401) return 'The human session could not be authenticated for this Platform Console projection.';
    if (error?.status === 403) return 'The selected profile is not authorized for this Platform Console projection.';
    if (error?.status === 503) return 'Human authentication or the platform projection dependency is unavailable.';
    if (error) return 'The control plane did not return a safe Platform Console projection. Check the endpoint and try again.';
    return 'The dashboard has not received this Platform Console projection yet.';
  }

  function customerSettingsUnavailableReason(kind) {
    const error = kind === 'members'
      ? state.organizationMembersError
      : state.credentialsError;
    if (error?.status === 404) return 'The configured control plane does not expose this customer settings projection.';
    if (error?.status === 401) return 'The human session could not be authenticated for this customer settings projection.';
    if (error?.status === 403) return 'The selected organization membership cannot read this customer settings projection.';
    if (error?.status === 503) return 'Human authentication is unavailable on this control plane.';
    if (error) return 'The control plane did not return safe customer settings metadata. Check the endpoint and try again.';
    return 'The dashboard has not received this customer settings projection yet.';
  }

  function formatDateText(value) {
    const raw = stringValue(value);
    if (!raw) return 'Not available';
    const date = new Date(raw);
    if (Number.isNaN(date.getTime())) return raw;
    return `${new Intl.DateTimeFormat(undefined, {
      dateStyle: 'medium',
      timeStyle: 'short',
      timeZone: 'UTC',
    }).format(date)} UTC`;
  }

  function selectedApplicationRecord() {
    const id = state.selectedApplication || profileApplicationId();
    return arrayValue(state.overview?.applications).find((item) => recordId(item) === id) ?? null;
  }

  function selectedEnvironmentRecord() {
    const id = state.selectedEnvironment || profileEnvironmentId();
    return arrayValue(state.overview?.environments).find((item) => recordId(item) === id) ?? null;
  }

  function renderContextControls() {
    const customerProfiles = profileList()
      .map((profile, index) => ({ profile, index }))
      .filter(({ profile }) => !isPlatformProfile(profile));
    const profiles = customerProfiles.map(({ profile }) => profile);
    const profile = selectedProfile();
    const memberships = organizationMemberships();
    const activeOrganizationId = profileOrganizationId(profile);
    if (nodes.organizationContext) {
      populateSelect(
        nodes.organizationContext,
        memberships.map((membership, index) => ({
          value: membership.id,
          label: organizationOptionLabel(membership, index, activeOrganizationId, memberships),
        })),
        activeOrganizationId,
        'No organization memberships returned',
      );
      nodes.organizationContext.disabled = memberships.length <= 1;
    }
    populateSelect(
      nodes.profileContext,
      customerProfiles.map(({ profile: item, index }) => ({
        value: String(index),
        label: `${pick(item, 'name') || 'Profile'} / ${pick(item, 'role') || 'role not set'}`,
      })),
      String(state.profileIndex),
      'No membership returned',
    );

    const appScope = profileApplicationId(profile);
    const environmentScope = profileEnvironmentId(profile);
    const applications = arrayValue(state.overview?.applications).filter((item) => !appScope || recordId(item) === appScope);
    if (appScope && !applications.some((item) => recordId(item) === appScope)) {
      applications.push({ id: appScope, runtimeApplicationId: 'Application scope' });
    }
    const appOptions = applications.map((item) => ({
      value: recordId(item),
      label: `${pick(item, 'runtimeApplicationId') || 'Application'} / ${recordId(item) || 'ID unavailable'}`,
    }));
    if (!appScope && appOptions.length > 0) appOptions.unshift({ value: '', label: 'All applications' });
    const appSelected = appScope || state.selectedApplication;
    populateSelect(nodes.applicationContext, appOptions, appSelected, appScope ? 'Application unavailable' : 'No applications returned');

    const selectedApp = appSelected;
    const environments = arrayValue(state.overview?.environments).filter((item) => {
      const matchesApp = !selectedApp || recordApplicationId(item) === selectedApp;
      const matchesScope = !environmentScope || recordId(item) === environmentScope;
      return matchesApp && matchesScope;
    });
    if (environmentScope && !environments.some((item) => recordId(item) === environmentScope)) {
      environments.push({ id: environmentScope, name: 'Environment scope' });
    }
    const environmentOptions = environments.map((item) => ({
      value: recordId(item),
      label: `${pick(item, 'name') || 'Environment'} / ${recordId(item) || 'ID unavailable'}`,
    }));
    if (!environmentScope && environmentOptions.length > 0) environmentOptions.unshift({ value: '', label: 'All environments' });
    const environmentSelected = environmentScope || state.selectedEnvironment;
    populateSelect(nodes.environmentContext, environmentOptions, environmentSelected, environmentScope ? 'Environment unavailable' : 'No environments returned');

    nodes.profileContext.disabled = profiles.length <= 1;
    nodes.applicationContext.disabled = appOptions.length === 0;
    nodes.environmentContext.disabled = environmentOptions.length === 0;
    nodes.contextScopeNote.textContent = profile
      ? `Role ${pick(profile, 'role') || 'not set'} / ${pick(profile, 'name') || 'profile'}`
      : 'Membership unavailable';

    const organization = objectValue(state.overview?.organization);
    const organizationId = activeOrganizationId ?? organizationRecordId(organization);
    const organizationName = organizationDisplayName(activeOrganizationId, memberships);
    nodes.contextOrganization.textContent = organizationName ?? (organizationId ? 'Organization' : 'Organization context');
    nodes.contextOrganizationId.textContent = organizationId ?? 'Organization ID unavailable';
    nodes.workspaceName.textContent = organizationName ?? 'Organization context';
  }

  function populateSelect(select, options, selected, emptyLabel) {
    select.replaceChildren();
    if (options.length === 0) {
      const option = element('option', '', emptyLabel);
      option.value = '';
      option.disabled = true;
      option.selected = true;
      select.append(option);
      return;
    }
    for (const item of options) {
      const option = element('option', '', item.label);
      option.value = item.value;
      select.append(option);
    }
    if (options.some((item) => item.value === selected)) select.value = selected;
    else select.value = options[0].value;
  }

  function renderShellIdentity() {
    const email = stringValue(pick(state.identity, 'email')) ?? 'Signed-in operator';
    const localPart = email.split('@')[0] || 'Operator';
    const initials = localPart
      .split(/[._-]+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0].toUpperCase())
      .join('') || 'H';
    nodes.userInitials.textContent = initials;
    nodes.userName.textContent = localPart;
    nodes.userEmail.textContent = email;
  }

  function setConnectionStatus(label, status = 'neutral') {
    if (!nodes.connectionStatus) return;
    nodes.connectionStatus.className = `status-pill status-pill-${status}`;
    const labelNode = nodes.connectionStatus.querySelector('span:last-child');
    if (labelNode) labelNode.textContent = label;
  }

  function showToast(message, status = 'neutral') {
    if (!nodes.toastRegion) return;
    if (toastTimer !== null) {
      window.clearTimeout(toastTimer);
      toastTimer = null;
    }
    nodes.toastRegion.replaceChildren();
    if (!message) return;
    const toast = element('div', 'toast', message);
    toast.dataset.state = status;
    nodes.toastRegion.append(toast);
    toastTimer = window.setTimeout(() => {
      if (toast.isConnected) toast.remove();
      toastTimer = null;
    }, 4200);
  }

  function resetDashboardInteractionState() {
    state.globalSearchQuery = '';
    state.collectionControls = createCollectionControls();
    nodes.globalSearch.value = '';
    showToast('');
  }

  function renderLastFetched() {
    nodes.lastFetched.textContent = state.lastFetchedAt
      ? `Updated ${formatDateText(state.lastFetchedAt)}`
      : 'Waiting for first request';
  }

  function renderDiscoveryStatus() {
    const discovery = state.discovery;
    nodes.discoveryCallout.dataset.state = discovery.status === 'available' ? 'success' : discovery.status === 'error' ? 'error' : 'warning';
    if (discovery.status === 'available') {
      nodes.discoveryStatus.textContent = 'Instance discovered';
      nodes.discoveryDetail.textContent = 'Compatibility metadata is available for the configured control plane.';
      return;
    }
    if (discovery.status === 'checking') {
      nodes.discoveryStatus.textContent = 'Checking instance discovery';
      nodes.discoveryDetail.textContent = 'The dashboard checks the configured control plane before sign-in.';
      return;
    }
    if (discovery.status === 'unavailable') {
      nodes.discoveryStatus.textContent = 'Discovery unavailable';
      nodes.discoveryDetail.textContent = 'This instance does not expose /.well-known/hyfens. Sign-in uses only the known auth contract; unadvertised capabilities stay unavailable.';
      return;
    }
    nodes.discoveryStatus.textContent = 'Discovery could not be checked';
    nodes.discoveryDetail.textContent = 'Check the endpoint and network before relying on capability state.';
  }

  async function probeDiscovery(endpoint = null) {
    let base;
    try {
      base = normalizeEndpoint(endpoint ?? nodes.apiBase.value);
    } catch (error) {
      state.discovery = { status: 'error', endpoint: '' };
      renderDiscoveryStatus();
      return state.discovery;
    }
    if (state.discovery.endpoint === base && state.discovery.status !== 'checking') return state.discovery;
    state.discovery = { status: 'checking', endpoint: base };
    renderDiscoveryStatus();
    const probe = new DashboardApi(base);
    try {
      const payload = await probe.discover();
      if (!objectValue(payload)) throw new ApiError('Discovery response is not an object.');
      state.discovery = { status: 'available', endpoint: base, payload };
    } catch (error) {
      state.discovery = {
        status: error instanceof ApiError && error.status === 404 ? 'unavailable' : 'error',
        endpoint: base,
        error,
      };
    }
    renderDiscoveryStatus();
    return state.discovery;
  }

  function activeAuthMode() {
    return nodes.registerForm.getAttribute('aria-hidden') === 'false' ? 'register' : 'login';
  }

  function setAuthFormState(form, inactive) {
    form.setAttribute('aria-hidden', String(inactive));
    if ('inert' in form) form.inert = inactive;
    else if (inactive) form.setAttribute('inert', '');
    else form.removeAttribute('inert');
  }

  function showAuthMode(mode, { focus = true, focusTarget = 'form' } = {}) {
    const nextMode = mode === 'register' ? 'register' : 'login';
    const register = nextMode === 'register';
    setAuthFormState(nodes.loginForm, register);
    setAuthFormState(nodes.registerForm, !register);
    nodes.authModeTabs.forEach((tab) => {
      const active = tab.dataset.authMode === nextMode;
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
    });
    setLoginMessage('', '');
    setRegisterMessage('', '');
    setRegistrationPasswordError('');
    nodes.registerPasswordConfirm.removeAttribute('aria-invalid');
    if (!focus) return;
    if (focusTarget === 'tab') {
      nodes.authModeTabs.find((tab) => tab.dataset.authMode === nextMode)?.focus({ preventScroll: true });
      return;
    }
    const target = register ? nodes.registerEmail : nodes.email;
    target?.focus({ preventScroll: true });
  }

  function handleAuthModeKeydown(event) {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    const tabs = nodes.authModeTabs;
    const currentIndex = Math.max(0, tabs.indexOf(event.currentTarget));
    let nextIndex = currentIndex;
    if (event.key === 'ArrowLeft') nextIndex = (currentIndex - 1 + tabs.length) % tabs.length;
    if (event.key === 'ArrowRight') nextIndex = (currentIndex + 1) % tabs.length;
    if (event.key === 'Home') nextIndex = 0;
    if (event.key === 'End') nextIndex = tabs.length - 1;
    event.preventDefault();
    const nextTab = tabs[nextIndex];
    showAuthMode(nextTab.dataset.authMode, { focusTarget: 'tab' });
  }

  function publicIntakeKind() {
    const kind = nodes.intakeForm?.dataset.intakeKind;
    return Object.prototype.hasOwnProperty.call(PUBLIC_INTAKE_COPY, kind) ? kind : 'waitlist';
  }

  function showIntakeMode(kind, { focus = false } = {}) {
    if (!nodes.intakeForm) return;
    const nextKind = Object.prototype.hasOwnProperty.call(PUBLIC_INTAKE_COPY, kind)
      ? kind
      : 'waitlist';
    const copy = PUBLIC_INTAKE_COPY[nextKind];
    nodes.intakeForm.dataset.intakeKind = nextKind;
    nodes.intakeKindHeading.textContent = copy.heading;
    nodes.intakeKindDescription.textContent = copy.description;
    nodes.intakeSubmit.querySelector('span').textContent = copy.submit;
    nodes.intakeModeTabs.forEach((tab) => {
      const active = tab.dataset.intakeKind === nextKind;
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
    });
    setIntakeMessage('', '');
    if (focus) nodes.intakeEmail?.focus({ preventScroll: true });
  }

  function handleIntakeModeKeydown(event) {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    const tabs = nodes.intakeModeTabs;
    const currentIndex = Math.max(0, tabs.indexOf(event.currentTarget));
    let nextIndex = currentIndex;
    if (event.key === 'ArrowLeft') nextIndex = (currentIndex - 1 + tabs.length) % tabs.length;
    if (event.key === 'ArrowRight') nextIndex = (currentIndex + 1) % tabs.length;
    if (event.key === 'Home') nextIndex = 0;
    if (event.key === 'End') nextIndex = tabs.length - 1;
    event.preventDefault();
    const nextTab = tabs[nextIndex];
    showIntakeMode(nextTab.dataset.intakeKind);
    nextTab.focus({ preventScroll: true });
  }

  async function handleLogin(event) {
    event.preventDefault();
    invalidateOverviewRequest();
    setLoginMessage('Connecting to the control plane...', 'pending');
    nodes.loginSubmit.disabled = true;
    const password = nodes.password.value;
    nodes.password.value = '';
    let endpoint;
    let api = null;
    try {
      endpoint = configuredEndpoint();
      await probeDiscovery(endpoint);
      const email = nodes.email.value.trim();
      if (!email || !password) throw new Error('Email and password are required.');
      api = new DashboardApi(endpoint);
      const loginPayload = await api.login(
        email,
        password,
        requestedLoginAudience(),
      );
      await establishAuthenticatedSession(api, endpoint, loginPayload);
      setLoginMessage('', '');
    } catch (error) {
      discardAuthenticationAttempt(api);
      setLoginMessage(loginErrorMessage(error), 'error');
    } finally {
      nodes.loginSubmit.disabled = false;
      nodes.password.value = '';
    }
  }

  async function handleRegistration(event) {
    event.preventDefault();
    invalidateOverviewRequest();
    setRegisterMessage('Creating your account...', 'pending');
    nodes.registerSubmit.disabled = true;
    const email = nodes.registerEmail.value.trim();
    const password = nodes.registerPassword.value;
    const confirmation = nodes.registerPasswordConfirm.value;
    nodes.registerPasswordConfirm.removeAttribute('aria-invalid');
    setRegistrationPasswordError('');
    let endpoint;
    let api = null;
    try {
      endpoint = configuredEndpoint();
      await probeDiscovery(endpoint);
      if (!email || !password || !confirmation) {
        throw new Error('Email and password are required.');
      }
      if (password !== confirmation) {
        nodes.registerPasswordConfirm.setAttribute('aria-invalid', 'true');
        setRegistrationPasswordError('Passwords do not match.');
        setRegisterMessage('Check the password confirmation and try again.', 'error');
        nodes.registerPasswordConfirm.focus({ preventScroll: true });
        return;
      }
      api = new DashboardApi(endpoint);
      const registrationPayload = await api.register(email, password);
      await establishAuthenticatedSession(api, endpoint, registrationPayload);
      setRegisterMessage('', '');
    } catch (error) {
      discardAuthenticationAttempt(api);
      setRegisterMessage(registrationErrorMessage(error), 'error');
    } finally {
      nodes.registerSubmit.disabled = false;
      nodes.registerPassword.value = '';
      nodes.registerPasswordConfirm.value = '';
    }
  }

  async function handlePublicIntake(event) {
    event.preventDefault();
    const kind = publicIntakeKind();
    const email = nodes.intakeEmail.value.trim();
    const name = nodes.intakeName.value.trim();
    const source = nodes.intakeSource.value.trim();
    const body = { email };
    if (name) body.name = name;
    if (source) body.source = source;
    setIntakeMessage('Sending your request...', 'pending');
    nodes.intakeSubmit.disabled = true;
    nodes.intakeForm.setAttribute('aria-busy', 'true');
    try {
      const endpoint = configuredEndpoint();
      const api = new DashboardApi(endpoint);
      await api.submitPublicIntake(kind, body);
      nodes.intakeForm.reset();
      setIntakeMessage('Thanks, your request was received.', 'success');
    } catch (error) {
      setIntakeMessage(intakeErrorMessage(error), 'error');
    } finally {
      nodes.intakeSubmit.disabled = false;
      nodes.intakeForm.removeAttribute('aria-busy');
    }
  }

  async function establishAuthenticatedSession(api, endpoint, sessionPayload) {
    api.setSession(sessionPayload);
    const identity = await api.me();
    if (!arrayValue(identity.profiles).length) {
      throw new Error('The auth service did not return a workspace membership.');
    }
    persistSession(api);
    installAuthenticatedSession(api, endpoint, identity);
    nodes.loginView.hidden = true;
    nodes.appView.hidden = false;
    syncAccountMenuPlacement();
    renderCurrentPage();
    await loadCurrentViewData();
  }

  function discardAuthenticationAttempt(api) {
    api?.clear();
    state.api?.clear();
    state.api = null;
    clearStoredSession();
  }

  function installAuthenticatedSession(api, endpoint, identity) {
    state.api = api;
    state.endpoint = endpoint;
    state.identity = normalizeIdentity(identity);
    state.overview = null;
    state.overviewError = null;
    state.platformMetrics = null;
    state.platformMetricsError = null;
    state.platformMetricsLoading = false;
    state.platformOrganizations = null;
    state.platformOrganizationsError = null;
    state.platformOrganization = null;
    state.platformOrganizationError = null;
    state.platformAudit = null;
    state.platformAuditError = null;
    state.platformUsers = null;
    state.platformUsersError = null;
    state.platformEntitlements = null;
    state.platformEntitlementsError = null;
    state.platformDataLoading = false;
    invalidatePlatformDataRequest();
    state.organizationMembers = null;
    state.organizationMembersError = null;
    state.credentials = null;
    state.credentialsError = null;
    state.issuedCredential = null;
    state.credentialIssueError = null;
    state.credentialIssueLoading = false;
    state.actionLoading = null;
    state.actionError = null;
    state.customerSettingsLoading = false;
    state.customerSettingsGeneration += 1;
    state.profileIndex = 0;
    state.selectedApplication = '';
    state.selectedEnvironment = '';
    state.lastFetchedAt = null;
    resetDashboardInteractionState();
    const route = readRoute();
    state.platformOrganizationId = route.organizationId;
    state.shell = route.shell;
    state.currentView = route.view;
    if (!canEnterView(state.currentView)) {
      state.currentView = fallbackViewForProfile(state.currentView);
      state.shell = isPlatformView(state.currentView) ? 'platform' : 'customer';
      window.history.replaceState({}, '', viewPath(state.currentView));
    }
    renderShellIdentity();
    renderContextControls();
    applyShellMode();
    syncAccountMenuPlacement();
    setConnectionStatus(state.discovery.status === 'available' ? 'Signed in' : 'Signed in / limited', state.discovery.status === 'available' ? 'success' : 'warning');
  }

  function syncAccountMenuPlacement() {
    if (!nodes.accountMenu || !nodes.accountMenuTrigger || nodes.appView.hidden) return;
    const triggerRect = nodes.accountMenuTrigger.getBoundingClientRect();
    const viewportHeight = document.documentElement.clientHeight || window.innerHeight;
    const spaceAbove = Math.max(0, triggerRect.top);
    const spaceBelow = Math.max(0, viewportHeight - triggerRect.bottom);
    nodes.accountMenu.dataset.placement = spaceAbove >= spaceBelow ? 'top' : 'bottom';

    const viewportWidth = document.documentElement.clientWidth || window.innerWidth;
    const estimatedPopoverWidth = 280;
    nodes.accountMenu.dataset.align = triggerRect.left + estimatedPopoverWidth > viewportWidth - 12 ? 'end' : 'start';
  }

  function closeAccountMenu({ focusTrigger = false } = {}) {
    if (!nodes.accountMenu) return;
    const wasOpen = nodes.accountMenu.open;
    nodes.accountMenu.open = false;
    if (wasOpen && focusTrigger) nodes.accountMenuTrigger?.focus({ preventScroll: true });
  }

  function handleAccountMenuToggle() {
    const open = Boolean(nodes.accountMenu?.open);
    nodes.accountMenuTrigger?.setAttribute('aria-expanded', String(open));
    nodes.accountMenuTrigger?.setAttribute('aria-label', open ? 'Close account menu' : 'Open account menu');
    if (open) syncAccountMenuPlacement();
  }

  function handleAccountMenuAction(event) {
    const action = event.currentTarget.dataset.accountAction;
    if (action === 'sign-out') return;
    closeAccountMenu({ focusTrigger: true });
    if (action === 'my-account') {
      navigateToView('settings');
      return;
    }
    if (action === 'privacy-policy') {
      showToast('Privacy policy is not configured for this local deployment.', 'warning');
      return;
    }
    if (action === 'share-feedback') {
      showToast('Feedback is not configured for this local deployment.', 'warning');
    }
  }

  function handleAccountMenuDocumentClick(event) {
    if (!nodes.accountMenu?.open || nodes.accountMenu.contains(event.target)) return;
    closeAccountMenu();
  }

  function handleAccountMenuKeydown(event) {
    if (event.key !== 'Escape' || !nodes.accountMenu?.open) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    closeAccountMenu({ focusTrigger: true });
  }

  async function restoreSession(storedSession) {
    let api = null;
    try {
      const endpoint = normalizeEndpoint(stringValue(storedSession.endpoint) ?? '');
      nodes.apiBase.value = endpoint;
      await probeDiscovery(endpoint);
      api = new DashboardApi(endpoint);
      await establishAuthenticatedSession(api, endpoint, storedSession);
      return true;
    } catch (error) {
      api?.clear();
      state.api?.clear();
      state.api = null;
      state.identity = null;
      state.overview = null;
      state.overviewError = null;
      state.platformMetrics = null;
      state.platformMetricsError = null;
      state.platformMetricsLoading = false;
      state.platformOrganizations = null;
      state.platformOrganizationsError = null;
      state.platformOrganization = null;
      state.platformOrganizationError = null;
      state.platformAudit = null;
      state.platformAuditError = null;
      state.platformDataLoading = false;
      invalidatePlatformDataRequest();
      state.organizationMembers = null;
      state.organizationMembersError = null;
      state.credentials = null;
      state.credentialsError = null;
      clearIssuedCredential();
      state.actionLoading = null;
      state.actionError = null;
      state.customerSettingsLoading = false;
      state.customerSettingsGeneration += 1;
      state.loading = false;
      state.lastFetchedAt = null;
      resetDashboardInteractionState();
      closeSidebar();
      nodes.appView.hidden = true;
      nodes.loginView.hidden = false;
      showAuthMode('login', { focus: false });
      clearStoredSession();
      setLoginMessage(loginErrorMessage(error), 'error');
      return false;
    }
  }

  function normalizeIdentity(identity) {
    const root = objectValue(identity) ?? {};
    const profiles = arrayValue(root.profiles).map((item) => {
      const profile = objectValue(item) ?? {};
      return {
        name: pick(profile, 'name', 'profileName', 'profile_name'),
        role: pick(profile, 'role'),
        capabilities: arrayValue(pick(profile, 'capabilities')),
        organizationId: pick(profile, 'organization_id', 'organizationId'),
        organizationName: pick(profile, 'organization_name', 'organizationName')
          ?? pick(objectValue(pick(profile, 'organization')), 'name'),
        applicationId: pick(profile, 'application_id', 'applicationId'),
        environmentId: pick(profile, 'environment_id', 'environmentId'),
        platform: pick(profile, 'platform', 'is_platform', 'isPlatform') === true,
        audience: pick(profile, 'audience') || 'customer',
        platformCapabilities: arrayValue(
          pick(profile, 'platform_capabilities', 'platformCapabilities'),
        ),
      };
    }).filter((item) => item.organizationId);
    return {
      user_id: pick(root, 'user_id', 'userId', 'id'),
      email: pick(root, 'email', 'mail'),
      profiles,
    };
  }

  function loginErrorMessage(error) {
    if (error instanceof ApiError && error.status === 401) return 'Email or password is invalid, or the session could not be established.';
    if (error instanceof ApiError && error.status === 404) return 'The configured control plane does not expose the shared auth route.';
    if (error instanceof ApiError && error.status === 503) return 'Human authentication is not configured on this control plane.';
    if (error instanceof Error && error.message.includes('endpoint')) return error.message;
    if (error instanceof Error && error.message.includes('membership')) return error.message;
    return 'Sign-in could not be completed. Check the endpoint and try again.';
  }

  function registrationErrorMessage(error) {
    if (error instanceof ApiError && error.status === 404) return 'Account creation is not available on this control plane.';
    if (error instanceof ApiError && error.status === 503) return 'Account creation is not currently available. Try again later.';
    if (error instanceof Error && error.message.includes('endpoint')) return error.message;
    if (error instanceof Error && error.message.includes('membership')) return error.message;
    return 'Account creation could not be completed. Check your details and try again.';
  }

  function intakeErrorMessage(error) {
    if (error instanceof Error && error.message.includes('endpoint')) return error.message;
    return 'This request could not be submitted right now. Please try again.';
  }

  function setLoginMessage(text, stateName) {
    nodes.loginMessage.textContent = text;
    if (stateName) nodes.loginMessage.dataset.state = stateName;
    else delete nodes.loginMessage.dataset.state;
  }

  function setRegisterMessage(text, stateName) {
    nodes.registerMessage.textContent = text;
    if (stateName) nodes.registerMessage.dataset.state = stateName;
    else delete nodes.registerMessage.dataset.state;
  }

  function setIntakeMessage(text, stateName) {
    nodes.intakeMessage.textContent = text;
    if (stateName) nodes.intakeMessage.dataset.state = stateName;
    else delete nodes.intakeMessage.dataset.state;
  }

  function setRegistrationPasswordError(text) {
    nodes.registerPasswordError.textContent = text;
  }

  function focusVisibleLoginTarget() {
    const candidates = activeAuthMode() === 'register'
      ? [nodes.registerEmail, nodes.registerSubmit]
      : [nodes.email, nodes.loginSubmit];
    const target = candidates.find((node) => {
      if (!node || node.disabled || node.hidden || node.closest('[hidden]')) return false;
      const styles = window.getComputedStyle(node);
      return styles.display !== 'none' && styles.visibility !== 'hidden';
    });
    target?.focus({ preventScroll: true });
  }

  function invalidateOverviewRequest() {
    overviewRequestGeneration += 1;
    activeOverviewController?.abort();
    activeOverviewController = null;
  }

  function invalidatePlatformMetricsRequest() {
    platformMetricsRequestGeneration += 1;
    activePlatformMetricsController?.abort();
    activePlatformMetricsController = null;
  }

  function invalidatePlatformDataRequest() {
    state.platformDataGeneration += 1;
  }

  function platformDataRequestIsCurrent(generation, view) {
    return generation === state.platformDataGeneration &&
      state.api !== null &&
      state.currentView === view &&
      state.shell === 'platform';
  }

  async function loadCurrentViewData({ announce = false } = {}) {
    if (isPlatformView(state.currentView)) {
      if (state.currentView === 'platform' || state.currentView === 'platform-operations') {
        return loadPlatformMetrics({ announce });
      }
      if (state.currentView === 'platform-settings') {
        state.platformDataLoading = false;
        renderCurrentPage();
        return;
      }
      return loadPlatformViewData({ announce });
    }
    if (state.currentView === 'settings') return loadCustomerSettingsData({ announce });
    return loadOverview({ announce });
  }

  async function loadPlatformViewData({ announce = false } = {}) {
    const api = state.api;
    if (!api) {
      invalidatePlatformDataRequest();
      if (announce) showToast('Sign in before refreshing platform data.', 'warning');
      return;
    }
    const view = state.currentView;
    const profile = selectedProfile();
    const generation = state.platformDataGeneration + 1;
    state.platformDataGeneration = generation;
    if (!hasPlatformCapability(platformCapabilityForView(view), profile)) {
      state.platformDataLoading = false;
      state.platformOrganization = null;
      state.platformOrganizations = null;
      state.platformAudit = null;
      state.platformUsers = null;
      state.platformEntitlements = null;
      state.platformOrganizationError = new ApiError(
        'The selected profile is not authorized for the Platform Console.',
        { status: 403 },
      );
      state.platformOrganizationsError = state.platformOrganizationError;
      state.platformAuditError = state.platformOrganizationError;
      state.platformUsersError = state.platformOrganizationError;
      state.platformEntitlementsError = state.platformOrganizationError;
      renderCurrentPage();
      return;
    }
    state.platformDataLoading = true;
    state.platformOrganizationError = null;
    state.platformOrganizationsError = null;
    state.platformAuditError = null;
    state.platformUsersError = null;
    state.platformEntitlementsError = null;
    if (view === 'platform-organizations') state.platformOrganizations = null;
    if (view === 'platform-organization') state.platformOrganization = null;
    if (view === 'platform-audit') state.platformAudit = null;
    if (view === 'platform-users') state.platformUsers = null;
    if (view === 'platform-entitlements') state.platformEntitlements = null;
    renderCurrentPage();
    let loaded = false;
    try {
      const profileName = stringValue(pick(profile, 'name'));
      if (view === 'platform-organizations') {
        const body = await api.platformOrganizations(profileName, '', {});
        if (!platformDataRequestIsCurrent(generation, view)) return;
        state.platformOrganizations = validatePlatformOrganizations(body);
      } else if (view === 'platform-organization') {
        if (!state.platformOrganizationId) throw new ApiError('No organization was selected.');
        const body = await api.platformOrganization(
          profileName,
          state.platformOrganizationId,
          {},
        );
        if (!platformDataRequestIsCurrent(generation, view)) return;
        state.platformOrganization = validatePlatformOrganization(body);
      } else if (view === 'platform-audit') {
        const body = await api.platformAudit(profileName, '', {});
        if (!platformDataRequestIsCurrent(generation, view)) return;
        state.platformAudit = validatePlatformAudit(body);
      } else if (view === 'platform-users') {
        const body = await api.platformUsers(profileName, {});
        if (!platformDataRequestIsCurrent(generation, view)) return;
        state.platformUsers = validatePlatformUsers(body);
      } else if (view === 'platform-entitlements') {
        const body = await api.platformEntitlements(profileName, {});
        if (!platformDataRequestIsCurrent(generation, view)) return;
        state.platformEntitlements = validatePlatformEntitlements(body);
      }
      state.lastFetchedAt = new Date().toISOString();
      loaded = true;
    } catch (error) {
      if (!platformDataRequestIsCurrent(generation, view) || isAbortError(error)) return;
      if (error instanceof SessionExpiredError) {
        await expireSession();
        return;
      }
      if (view === 'platform-organizations') state.platformOrganizationsError = error;
      if (view === 'platform-organization') state.platformOrganizationError = error;
      if (view === 'platform-audit') state.platformAuditError = error;
      if (view === 'platform-users') state.platformUsersError = error;
      if (view === 'platform-entitlements') state.platformEntitlementsError = error;
    } finally {
      if (!platformDataRequestIsCurrent(generation, view)) return;
      state.platformDataLoading = false;
      renderCurrentPage();
      if (announce) {
        showToast(
          loaded ? 'Platform data refreshed.' : 'Platform data could not be refreshed.',
          loaded ? 'success' : 'error',
        );
      }
    }
  }

  function validatePlatformOrganizations(body) {
    const root = unwrapPayload(body);
    if (root.readOnly !== true || root.scope !== 'platform' || !Array.isArray(root.organizations)) {
      throw new ApiError('The control plane did not return the required platform organization projection.');
    }
    return root;
  }

  function validatePlatformOrganization(body) {
    const root = unwrapPayload(body);
    if (root.readOnly !== true || root.scope !== 'platform' || !objectValue(root.organization)) {
      throw new ApiError('The control plane did not return the required organization detail projection.');
    }
    return root;
  }

  function validatePlatformAudit(body) {
    const root = unwrapPayload(body);
    if (root.readOnly !== true || root.scope !== 'platform' || !Array.isArray(root.events)) {
      throw new ApiError('The control plane did not return the required platform audit projection.');
    }
    return root;
  }

  function validatePlatformUsers(body) {
    const root = unwrapPayload(body);
    if (root.readOnly !== true || root.scope !== 'platform' || !Array.isArray(root.users)) {
      throw new ApiError('The control plane did not return the required platform user projection.');
    }
    return root;
  }

  function validatePlatformEntitlements(body) {
    const root = unwrapPayload(body);
    if (
      root.readOnly !== true ||
      root.scope !== 'platform' ||
      !Array.isArray(root.plans) ||
      !Array.isArray(root.subscriptions)
    ) {
      throw new ApiError('The control plane did not return the required entitlement projection.');
    }
    return root;
  }

  function validateOrganizationMembers(body) {
    const root = unwrapPayload(body);
    if (root.readOnly !== true || !Array.isArray(root.members)) {
      throw new ApiError('The control plane did not return safe organization member metadata.');
    }
    return root.members;
  }

  function validateCredentials(body) {
    const root = unwrapPayload(body);
    if (root.readOnly !== true || !Array.isArray(root.credentials)) {
      throw new ApiError('The control plane did not return safe credential metadata.');
    }
    return root.credentials;
  }

  function customerSettingsRequestIsCurrent(generation, api, organizationId) {
    return generation === state.customerSettingsGeneration &&
      state.api === api &&
      state.currentView === 'settings' &&
      state.shell === 'customer' &&
      profileOrganizationId() === organizationId;
  }

  async function loadCustomerSettingsData({ announce = false } = {}) {
    const api = state.api;
    if (!api) {
      if (announce) showToast('Sign in before refreshing customer settings.', 'warning');
      return;
    }
    const organizationId = profileOrganizationId();
    const generation = state.customerSettingsGeneration + 1;
    state.customerSettingsGeneration = generation;
    state.customerSettingsLoading = true;
    state.organizationMembers = null;
    state.organizationMembersError = null;
    state.credentials = null;
    state.credentialsError = null;
    clearIssuedCredential();
    state.actionLoading = null;
    state.actionError = null;
    if (!organizationId) {
      state.customerSettingsLoading = false;
      state.organizationMembersError = new ApiError('Organization membership is unavailable.');
      state.credentialsError = state.organizationMembersError;
      renderCurrentPage();
      return;
    }
    if (announce) showToast('Refreshing organization settings…');
    renderCurrentPage();
    let loaded = false;
    try {
      const [membersBody, credentialsBody] = await Promise.all([
        api.organizationMembers(organizationId),
        api.credentials(organizationId),
      ]);
      if (!customerSettingsRequestIsCurrent(generation, api, organizationId)) return;
      state.organizationMembers = validateOrganizationMembers(membersBody);
      state.credentials = validateCredentials(credentialsBody);
      state.lastFetchedAt = new Date().toISOString();
      loaded = true;
    } catch (error) {
      if (!customerSettingsRequestIsCurrent(generation, api, organizationId)) return;
      if (error instanceof SessionExpiredError) {
        await expireSession();
        return;
      }
      state.organizationMembersError = error;
      state.credentialsError = error;
    } finally {
      if (!customerSettingsRequestIsCurrent(generation, api, organizationId)) return;
      state.customerSettingsLoading = false;
      renderCurrentPage();
      if (announce) {
        showToast(
          loaded ? 'Organization settings refreshed.' : 'Organization settings could not be refreshed.',
          loaded ? 'success' : 'error',
        );
      }
    }
  }

  function beginOverviewRequest(api, profile, organizationId) {
    overviewRequestGeneration += 1;
    activeOverviewController?.abort();
    const controller = typeof AbortController === 'function'
      ? new AbortController()
      : null;
    activeOverviewController = controller;
    return {
      generation: overviewRequestGeneration,
      api,
      identity: state.identity,
      profileIndex: state.profileIndex,
      profile,
      organizationId,
      controller,
    };
  }

  function overviewRequestIsCurrent(request) {
    return request.generation === overviewRequestGeneration &&
      state.api === request.api &&
      state.identity === request.identity &&
      state.profileIndex === request.profileIndex &&
      selectedProfile() === request.profile &&
      profileOrganizationId() === request.organizationId &&
      activeOverviewController === request.controller &&
      (!request.controller || !request.controller.signal.aborted);
  }

  function beginPlatformMetricsRequest(api, profile) {
    platformMetricsRequestGeneration += 1;
    activePlatformMetricsController?.abort();
    const controller = typeof AbortController === 'function'
      ? new AbortController()
      : null;
    activePlatformMetricsController = controller;
    return {
      generation: platformMetricsRequestGeneration,
      api,
      identity: state.identity,
      profileIndex: state.profileIndex,
      profile,
      controller,
    };
  }

  function platformMetricsRequestIsCurrent(request) {
    return request.generation === platformMetricsRequestGeneration &&
      state.api === request.api &&
      state.identity === request.identity &&
      state.profileIndex === request.profileIndex &&
      selectedProfile() === request.profile &&
      activePlatformMetricsController === request.controller &&
      (!request.controller || !request.controller.signal.aborted);
  }

  async function loadPlatformMetrics({ announce = false } = {}) {
    const api = state.api;
    if (!api) {
      invalidatePlatformMetricsRequest();
      if (announce) showToast('Sign in before refreshing platform metrics.', 'warning');
      return;
    }
    const profile = selectedProfile();
    const request = beginPlatformMetricsRequest(api, profile);
    if (!hasPlatformCapability(platformCapabilityForView(), profile)) {
      if (!platformMetricsRequestIsCurrent(request)) return;
      activePlatformMetricsController = null;
      state.platformMetrics = null;
      state.platformMetricsError = new ApiError(
        'The selected profile is not authorized for platform-level metrics.',
        { status: 403 },
      );
      state.platformMetricsLoading = false;
      renderCurrentPage();
      return;
    }
    if (announce) showToast('Refreshing platform metrics…');
    state.platformMetricsLoading = true;
    state.platformMetrics = null;
    state.platformMetricsError = null;
    let loaded = false;
    renderCurrentPage();
    try {
      const profileName = stringValue(pick(profile, 'name'));
      const body = await api.platformMetrics(profileName, {
        signal: request.controller?.signal,
      });
      if (!platformMetricsRequestIsCurrent(request)) return;
      state.platformMetrics = validatePlatformMetrics(body);
      state.lastFetchedAt = new Date().toISOString();
      loaded = true;
    } catch (error) {
      if (!platformMetricsRequestIsCurrent(request) || isAbortError(error)) return;
      if (error instanceof SessionExpiredError) {
        await expireSession();
        return;
      }
      state.platformMetricsError = error;
    } finally {
      if (!platformMetricsRequestIsCurrent(request)) return;
      activePlatformMetricsController = null;
      state.platformMetricsLoading = false;
      renderCurrentPage();
      if (announce) {
        showToast(
          loaded ? 'Platform metrics refreshed.' : 'Platform metrics could not be refreshed.',
          loaded ? 'success' : 'error',
        );
      }
    }
  }

  function validatePlatformMetrics(body) {
    const root = unwrapPayload(body);
    if (root.readOnly !== true || root.scope !== 'platform') {
      throw new ApiError('The control plane did not return the required platform projection.');
    }
    if (!objectValue(root.counts) || !objectValue(root.activity)) {
      throw new ApiError('The platform metrics projection is incomplete.');
    }
    return root;
  }

  function refreshCurrentPageData(options = {}) {
    return loadCurrentViewData(options);
  }

  function refreshAfterContextChange() {
    syncPlatformNavigation();
    if (isPlatformView(state.currentView) && !hasPlatformCapability(platformCapabilityForView())) {
      navigateToView('overview');
    }
    return refreshCurrentPageData();
  }

  async function loadOverview({ announce = false } = {}) {
    const api = state.api;
    if (!api) {
      invalidateOverviewRequest();
      if (announce) showToast('Sign in before refreshing records.', 'warning');
      return;
    }
    const profile = selectedProfile();
    const organizationId = profileOrganizationId(profile);
    const request = beginOverviewRequest(api, profile, organizationId);
    if (!organizationId) {
      if (!overviewRequestIsCurrent(request)) return;
      activeOverviewController = null;
      state.overviewError = new ApiError('Organization membership is unavailable.');
      state.loading = false;
      renderCurrentPage();
      if (announce) showToast('Records could not be refreshed: organization membership is unavailable.', 'error');
      return;
    }
    if (announce) showToast('Refreshing records…');
    state.loading = true;
    state.overview = null;
    state.overviewError = null;
    let loaded = false;
    renderCurrentPage();
    try {
      const body = await api.overview(organizationId, {
        signal: request.controller?.signal,
      });
      if (!overviewRequestIsCurrent(request)) return;
      state.overview = validateOverview(body);
      state.lastFetchedAt = new Date().toISOString();
      loaded = true;
    } catch (error) {
      if (!overviewRequestIsCurrent(request) || isAbortError(error)) return;
      if (error instanceof SessionExpiredError) {
        await expireSession();
        return;
      }
      state.overviewError = error;
    } finally {
      if (!overviewRequestIsCurrent(request)) return;
      activeOverviewController = null;
      state.loading = false;
      renderContextControls();
      renderCurrentPage();
      if (announce) {
        const refreshMessage = loaded && overviewHasTruncatedCollections()
          ? 'Records refreshed; some collections are capped.'
          : loaded
            ? 'Records refreshed.'
            : 'Records could not be refreshed.';
        showToast(
          refreshMessage,
          loaded ? 'success' : 'error',
        );
      }
    }
  }

  function validateOverview(body) {
    const root = unwrapPayload(body);
    if (root.readOnly !== true || root.runtimeAuthority !== 'client') {
      throw new ApiError('The control plane did not return the required read-only projection.');
    }
    for (const key of RESOURCE_KEYS) {
      if (!Array.isArray(root[key])) throw new ApiError(`The overview projection is missing ${key}.`);
    }
    return root;
  }

  async function expireSession() {
    invalidateOverviewRequest();
    invalidatePlatformMetricsRequest();
    state.api?.clear();
    state.api = null;
    clearStoredSession();
    state.identity = null;
    state.overview = null;
    state.overviewError = null;
    state.platformMetrics = null;
    state.platformMetricsError = null;
    state.platformMetricsLoading = false;
    state.platformOrganizations = null;
    state.platformOrganizationsError = null;
    state.platformOrganization = null;
    state.platformOrganizationError = null;
    state.platformAudit = null;
    state.platformAuditError = null;
    state.platformDataLoading = false;
    invalidatePlatformDataRequest();
    state.organizationMembers = null;
    state.organizationMembersError = null;
    state.credentials = null;
    state.credentialsError = null;
    clearIssuedCredential();
    state.actionLoading = null;
    state.actionError = null;
    state.customerSettingsLoading = false;
    state.customerSettingsGeneration += 1;
    state.loading = false;
    state.lastFetchedAt = null;
    resetDashboardInteractionState();
    closeSidebar();
    nodes.appView.hidden = true;
    nodes.loginView.hidden = false;
    showAuthMode('login', { focus: false });
    setConnectionStatus('Signed out', 'neutral');
    setLoginMessage('Your session expired. Sign in again.', 'error');
    focusVisibleLoginTarget();
  }

  async function handleLogout() {
    invalidateOverviewRequest();
    invalidatePlatformMetricsRequest();
    nodes.logoutButton.disabled = true;
    nodes.platformLogoutButton.disabled = true;
    let remoteError = null;
    try {
      await state.api?.logout();
    } catch (error) {
      remoteError = error;
    } finally {
      state.api?.clear();
      state.api = null;
      clearStoredSession();
      state.identity = null;
      state.overview = null;
      state.overviewError = null;
      state.platformMetrics = null;
      state.platformMetricsError = null;
      state.platformMetricsLoading = false;
      state.platformOrganizations = null;
      state.platformOrganizationsError = null;
      state.platformOrganization = null;
      state.platformOrganizationError = null;
      state.platformAudit = null;
      state.platformAuditError = null;
      state.platformDataLoading = false;
      invalidatePlatformDataRequest();
      state.organizationMembers = null;
      state.organizationMembersError = null;
      state.credentials = null;
      state.credentialsError = null;
      clearIssuedCredential();
      state.actionLoading = null;
      state.actionError = null;
      state.customerSettingsLoading = false;
      state.customerSettingsGeneration += 1;
      state.loading = false;
      state.lastFetchedAt = null;
      resetDashboardInteractionState();
      closeSidebar();
      nodes.appView.hidden = true;
      nodes.loginView.hidden = false;
      showAuthMode('login', { focus: false });
      nodes.email.value = '';
      nodes.password.value = '';
      nodes.registerEmail.value = '';
      nodes.registerPassword.value = '';
      nodes.registerPasswordConfirm.value = '';
      setLoginMessage(remoteError ? 'Local session cleared. Remote revocation was not confirmed.' : 'Signed out.', remoteError ? 'error' : 'success');
      setConnectionStatus('Signed out', 'neutral');
      nodes.logoutButton.disabled = false;
      nodes.platformLogoutButton.disabled = false;
      focusVisibleLoginTarget();
    }
  }

  function clearPageTransition() {
    if (pageTransitionFrame !== null) {
      window.cancelAnimationFrame(pageTransitionFrame);
      pageTransitionFrame = null;
    }
    nodes.pageRegion.removeAttribute('data-page-transition');
  }

  function replacePageRegion(content, { transition = false } = {}) {
    clearPageTransition();
    if (transition) nodes.pageRegion.setAttribute('data-page-transition', 'true');
    nodes.pageRegion.replaceChildren(content);
    if (!transition) return;
    pageTransitionFrame = window.requestAnimationFrame(() => {
      pageTransitionFrame = null;
      nodes.pageRegion.removeAttribute('data-page-transition');
    });
  }

  function renderCurrentPage({ focusTarget = null, transition = false } = {}) {
    const globalQuery = state.shell === 'customer'
      ? normalizeSearchQuery(state.globalSearchQuery)
      : '';
    const copy = globalQuery
      ? {
        title: 'Search records',
        description: overviewHasTruncatedCollections()
          ? 'Search the loaded authoritative records returned for the selected context; some collections are capped.'
          : 'Search the authoritative records returned for the selected context.',
      }
      : PAGE_COPY[state.currentView] ?? PAGE_COPY.overview;
    nodes.pageTitle.textContent = copy.title;
    nodes.pageDescription.textContent = copy.description;
    nodes.topbarPage.textContent = copy.title;
    for (const link of nodes.viewLinks) {
      const active = link.dataset.viewLink === state.currentView || (
        state.currentView === 'platform-organization' &&
        link.dataset.viewLink === 'platform-organizations'
      );
      if (active) link.setAttribute('aria-current', 'page');
      else link.removeAttribute('aria-current');
    }
    renderGlobalBanner();
    renderLastFetched();
    const pageLoading = state.loading || state.platformMetricsLoading || state.platformDataLoading || state.customerSettingsLoading;
    nodes.refreshButton.disabled = pageLoading || !state.api || state.currentView === 'platform-settings';
    nodes.refreshButton.setAttribute('aria-busy', String(pageLoading));
    nodes.pageRegion.setAttribute('aria-busy', pageLoading ? 'true' : 'false');
    if (pageLoading) {
      replacePageRegion(renderLoadingState(), { transition });
      return;
    }
    if (globalQuery) {
      replacePageRegion(renderGlobalSearchPage(), { transition });
      return;
    }
    const page = {
      overview: renderOverviewPage,
      platform: renderPlatformPage,
      'platform-organizations': renderPlatformOrganizationsPage,
      'platform-organization': renderPlatformOrganizationPage,
      'platform-audit': renderPlatformAuditPage,
      'platform-operations': renderPlatformPage,
      'platform-users': renderPlatformUsersPage,
      'platform-entitlements': renderPlatformEntitlementsPage,
      'platform-settings': renderPlatformSettingsPage,
      applications: renderApplicationsPage,
      environments: renderEnvironmentsPage,
      releases: renderReleasesPage,
      patches: renderPatchesPage,
      artifacts: renderArtifactsPage,
      deployments: renderDeploymentsPage,
      audit: renderAuditPage,
      settings: renderSettingsPage,
    }[state.currentView] ?? renderOverviewPage;
    replacePageRegion(page(), { transition });
    restoreFocus(focusTarget);
  }

  function restoreFocus(focusTarget) {
    if (!focusTarget || focusTarget.type !== 'collection') return;
    const controlId = {
      search: 'search',
      status: 'filter',
      sort: 'sort',
    }[focusTarget.control];
    if (!controlId) return;
    const target = document.querySelector(
      `#collection-${controlId}-${focusTarget.key}`,
    );
    if (!target || target.disabled) return;
    target.focus({ preventScroll: true });
    if (target.matches('input[type="search"]')) {
      const cursor = target.value.length;
      target.setSelectionRange(cursor, cursor);
    }
  }

  function handleGlobalSearchInput(event) {
    state.globalSearchQuery = event.target.value;
    renderCurrentPage();
  }

  function handleGlobalSearchSubmit(event) {
    event.preventDefault();
    state.globalSearchQuery = nodes.globalSearch.value;
    renderCurrentPage();
    const query = normalizeSearchQuery(state.globalSearchQuery);
    if (!query) {
      showToast('Record search cleared.');
      return;
    }
    if (!state.overview) {
      showToast('Record search is waiting for overview data.', 'warning');
      return;
    }
    const matches = globalSearchMatchCount(query);
    const truncated = overviewHasTruncatedCollections();
    const matchLabel = `${matches} matching ${truncated ? 'loaded ' : 'returned '}record${matches === 1 ? '' : 's'}`;
    showToast(
      matches > 0
        ? `${matchLabel} found${truncated ? '; some collections are capped.' : '.'}`
        : truncated
          ? 'No matching loaded records found; some collections are capped, so more matches may exist.'
          : 'No matching returned records found.',
      matches > 0 ? 'success' : 'warning',
    );
  }

  function handleGlobalSearchKeydown(event) {
    if (event.key !== 'Escape' || !normalizeSearchQuery(nodes.globalSearch.value)) return;
    event.preventDefault();
    clearGlobalSearch({ announce: true });
  }

  function clearGlobalSearch({ render = true, announce = false } = {}) {
    const hadQuery = Boolean(
      normalizeSearchQuery(state.globalSearchQuery) || normalizeSearchQuery(nodes.globalSearch.value),
    );
    state.globalSearchQuery = '';
    nodes.globalSearch.value = '';
    if (render) renderCurrentPage();
    if (announce && hadQuery) showToast('Record search cleared.');
    return hadQuery;
  }

  function globalSearchMatchCount(query) {
    if (!state.overview) return 0;
    const normalized = normalizeSearchQuery(query);
    return RESOURCE_KEYS.reduce(
      (count, key) => count + scopedItems(key).filter(
        (item) => recordSearchText(key, item).includes(normalized),
      ).length,
      0,
    );
  }

  function handleCollectionInput(event) {
    const target = event.target;
    if (!target?.classList?.contains('collection-search')) return;
    const panel = target.closest('[data-collection-key]');
    const key = panel?.dataset.collectionKey;
    if (!RESOURCE_KEYS.includes(key)) return;
    collectionControlsFor(key).query = target.value;
    renderCurrentPage({
      focusTarget: { type: 'collection', key, control: 'search' },
    });
  }

  function handleCollectionChange(event) {
    const target = event.target;
    if (target?.dataset?.promotionEnvironment === 'true') {
      const version = target.selectedOptions?.[0]?.dataset?.environmentVersion;
      const form = target.closest('form[data-dashboard-action="promotion"]');
      const expectedVersion = form?.elements?.namedItem('expected_version');
      if (expectedVersion && version !== undefined) expectedVersion.value = version;
      return;
    }
    const control = target?.dataset?.collectionControl;
    if (!['search', 'status', 'sort'].includes(control)) return;
    const panel = target.closest('[data-collection-key]');
    const key = panel?.dataset.collectionKey;
    if (!RESOURCE_KEYS.includes(key)) return;
    const controls = collectionControlsFor(key);
    if (control === 'search') controls.query = target.value;
    if (control === 'status') controls.status = target.value;
    if (control === 'sort') controls.sort = target.value;
    renderCurrentPage({ focusTarget: { type: 'collection', key, control } });
    if (state.overview) {
      const result = collectionResult(state.overview, key, scopedItems(key));
      const sourceLabel = result.truncated ? 'loaded' : 'returned';
      showToast(
        `${RESOURCE_LABELS[key]}: showing ${result.items.length} of ${result.sourceCount} ${sourceLabel} records.${result.truncated ? ' More records may be available because the response is capped.' : ''}`,
      );
    }
  }

  function handleSearchResultClick(event) {
    const link = event.target.closest?.('[data-search-result-view]');
    if (!link) return;
    const view = link.dataset.searchResultView;
    if (!Object.prototype.hasOwnProperty.call(PAGE_COPY, view)) return;
    event.preventDefault();
    clearGlobalSearch({ render: false });
    navigateToView(view);
  }

  function handlePlatformOrganizationClick(event) {
    const link = event.target.closest?.('[data-platform-organization-id]');
    if (!link) return;
    const organizationId = stringValue(link.dataset.platformOrganizationId);
    if (!organizationId) return;
    event.preventDefault();
    navigateToView('platform-organization', { organizationId });
  }

  function customerActionErrorMessage(action, error) {
    if (error instanceof SessionExpiredError) return 'Your session expired. Sign in again.';
    if (error instanceof ApiError) {
      if (error.status === 401 || error.status === 403) return 'This profile is not authorized for that customer action.';
      if (error.status === 409 || error.status === 412) {
        return action === 'promotion'
          ? 'The environment or release state changed. Refresh and verify that a ready patch is available before trying again.'
          : 'That record already exists or changed. Refresh the workspace and try again.';
      }
      if (error.status === 422) return 'Check the submitted values and try again.';
      if (error.status === 503) return 'The control plane is temporarily unavailable. Try again shortly.';
    }
    return 'The requested customer action could not be completed. Try again.';
  }

  async function refreshAfterCustomerMutation(message) {
    state.actionLoading = null;
    state.actionError = null;
    state.overview = null;
    state.overviewError = null;
    renderCurrentPage();
    await loadOverview();
    showToast(message, 'success');
  }

  async function handleCustomerActionSubmit(event) {
    const form = event.target.closest?.('form[data-dashboard-action]');
    if (!form || !nodes.pageRegion.contains(form)) return;
    event.preventDefault();
    if (state.actionLoading) return;
    const action = form.dataset.dashboardAction;
    const data = new FormData(form);
    const value = (name) => stringValue(data.get(name))?.trim() ?? '';
    const organizationId = profileOrganizationId();
    if (!state.api || !organizationId) {
      state.actionError = { action, message: 'Customer organization context is unavailable.' };
      renderCurrentPage();
      return;
    }
    state.actionLoading = action;
    state.actionError = null;
    renderCurrentPage();
    try {
      if (action === 'application-create') {
        const runtimeApplicationId = value('runtime_application_id');
        const name = value('name');
        const platform = value('platform');
        if (!name || !runtimeApplicationId || !['android', 'ios'].includes(platform)) {
          throw new Error('Application name, platform, and runtime identity are required.');
        }
        await state.api.createApplication(
          organizationId,
          { name, platform, runtime_application_id: runtimeApplicationId },
          makeIdempotencyKey('application-create'),
        );
        await refreshAfterCustomerMutation('Application registered.');
        return;
      }
      if (action === 'environment-create') {
        const applicationId = value('application_id');
        const name = value('name');
        if (!applicationId || !name) throw new Error('Application and environment name are required.');
        await state.api.createEnvironment(
          organizationId,
          applicationId,
          { name },
          makeIdempotencyKey('environment-create'),
        );
        await refreshAfterCustomerMutation('Environment created.');
        return;
      }
      if (action === 'credential-issue') {
        const preset = credentialScopePresets().find((item) => item.value === value('scope_preset'));
        if (!preset || !value('name')) throw new Error('Credential name and scope are required.');
        const expiryDays = Number.parseInt(value('expiry_days') || '0', 10);
        const body = {
          name: value('name'),
          kind: 'control',
          scopes: preset.scopes,
        };
        if (Number.isInteger(expiryDays) && expiryDays > 0) {
          body.expires_at = new Date(Date.now() + expiryDays * 24 * 60 * 60 * 1000).toISOString();
        }
        const response = await state.api.issueCredential(organizationId, body);
        const issued = unwrapPayload(response);
        const token = stringValue(pick(issued, 'token'));
        if (!token) throw new ApiError('The control plane did not return the one-time credential.');
        const metadata = Object.fromEntries(
          Object.entries(issued).filter(([key]) => key !== 'token'),
        );
        state.issuedCredential = { token, metadata };
        state.credentials = [metadata, ...arrayValue(state.credentials)];
        state.actionLoading = null;
        renderCurrentPage();
        showToast('Credential created. Copy the secret now.', 'success');
        return;
      }
      if (action === 'promotion') {
        const environmentId = value('environment_id');
        const releaseId = value('release_id');
        const expectedVersion = Number.parseInt(value('expected_version'), 10);
        if (!environmentId || !releaseId || !Number.isInteger(expectedVersion) || expectedVersion < 0) {
          throw new Error('Environment, release, and current version are required.');
        }
        await state.api.promote(
          organizationId,
          environmentId,
          { release_id: releaseId, expected_version: expectedVersion },
          makeIdempotencyKey('promotion'),
          expectedVersion,
        );
        await refreshAfterCustomerMutation('Release promoted to the environment.');
        return;
      }
      throw new Error('Unsupported customer action.');
    } catch (error) {
      if (error instanceof SessionExpiredError) {
        await expireSession();
        return;
      }
      state.actionError = { action, message: customerActionErrorMessage(action, error) };
    } finally {
      if (state.actionLoading === action) {
        state.actionLoading = null;
        renderCurrentPage();
      }
    }
  }

  async function handleCredentialCopy(event) {
    const button = event.target.closest?.('[data-copy-credential]');
    if (!button) return;
    const token = stringValue(state.issuedCredential?.token);
    if (!token) return;
    event.preventDefault();
    try {
      if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
      await navigator.clipboard.writeText(token);
      showToast('Credential copied. It will not be shown again after leaving this page.', 'success');
    } catch (error) {
      showToast('Clipboard access is unavailable. Copy the credential manually before leaving this page.', 'warning');
    }
  }

  async function handleCustomerSettingsClick(event) {
    if (event.target.closest?.('[data-copy-credential]')) {
      await handleCredentialCopy(event);
      return;
    }
    const button = event.target.closest?.('[data-credential-revoke]');
    if (!button || button.disabled) return;
    const credentialId = stringValue(button.dataset.credentialRevoke);
    const organizationId = profileOrganizationId();
    if (!credentialId || !organizationId || !state.api) return;
    if (!hasCustomerCapability('credential:revoke')) {
      showToast('This profile cannot revoke customer credentials.', 'warning');
      return;
    }
    if (!window.confirm('Revoke this credential? Existing clients using it will stop being authorized.')) return;
    button.disabled = true;
    try {
      await state.api.revokeCredential(organizationId, credentialId);
      showToast('Credential revoked.', 'success');
      await loadCustomerSettingsData();
    } catch (error) {
      if (error instanceof SessionExpiredError) {
        await expireSession();
        return;
      }
      showToast('The credential could not be revoked.', 'error');
      button.disabled = false;
    }
  }

  function handleViewLinkClick(event) {
    event.preventDefault();
    clearGlobalSearch({ render: false });
    closeSidebar();
    const view = event.currentTarget.dataset.viewLink;
    navigateToView(view);
  }

  function handleIntakeLinkClick(event) {
    event.preventDefault();
    nodes.intakeSection?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function handleLocationChange() {
    const route = readRoute();
    state.platformOrganizationId = route.organizationId;
    let nextView = route.view;
    if (state.api && !canEnterView(nextView)) {
      announceViewAccessDenied(nextView);
      nextView = fallbackViewForProfile(nextView);
      window.history.replaceState({}, '', viewPath(nextView));
    } else {
      const path = viewPath(nextView, route.organizationId);
      if (window.location.pathname !== path || window.location.search || window.location.hash) {
        window.history.replaceState({}, '', path);
      }
    }
    state.shell = isPlatformView(nextView) ? 'platform' : 'customer';
    state.currentView = nextView;
    applyShellMode();
    renderCurrentPage({ transition: true });
    if (state.api) void loadCurrentViewData();
  }

  function isEditableKeyboardTarget(target) {
    return Boolean(target?.closest?.('input, textarea, select, [contenteditable="true"]'));
  }

  function hasBlockingKeyboardLayer() {
    return Boolean(
      (nodes.recordSheet && !nodes.recordSheet.hidden) ||
      (nodes.shortcutsDialog && !nodes.shortcutsDialog.hidden) ||
      nodes.accountMenu?.open ||
      nodes.appView.dataset.navOpen === 'true'
    );
  }

  function handleGlobalShortcut(event) {
    if (
      event.defaultPrevented ||
      event.ctrlKey ||
      event.metaKey ||
      event.altKey ||
      nodes.appView.hidden
    ) return;
    if (isEditableKeyboardTarget(event.target)) return;

    if (event.key === '?' && !event.repeat) {
      if (hasBlockingKeyboardLayer()) return;
      event.preventDefault();
      openShortcutsDialog();
      return;
    }

    if (event.key === '/' && !event.shiftKey) {
      if (hasBlockingKeyboardLayer() || state.shell === 'platform') return;
      event.preventDefault();
      nodes.globalSearch.focus({ preventScroll: true });
      nodes.globalSearch.select();
      return;
    }

    if (hasBlockingKeyboardLayer() || event.repeat) return;

    if (!event.shiftKey && event.key.toLowerCase() === 'r') {
      if (nodes.refreshButton.disabled) return;
      event.preventDefault();
      void refreshCurrentPageData({ announce: true });
      return;
    }

    if (!event.shiftKey && event.key.toLowerCase() === 't') {
      event.preventDefault();
      nodes.themeToggle.click();
    }
  }

  function renderLoadingState() {
    const panel = element('section', 'surface-panel panel-padding');
    const skeletons = element('div', 'skeleton-stack');
    skeletons.append(element('div', 'skeleton-line short'), element('div', 'skeleton-line'));
    const cards = element('div', 'metric-grid');
    for (let index = 0; index < 6; index += 1) cards.append(element('div', 'skeleton-card'));
    panel.append(skeletons, cards);
    return panel;
  }

  function renderGlobalBanner() {
    let text = '';
    let status = 'neutral';
    const platformError = state.currentView === 'platform' || state.currentView === 'platform-operations'
      ? state.platformMetricsError
      : state.currentView === 'platform-organizations'
        ? state.platformOrganizationsError
        : state.currentView === 'platform-organization'
          ? state.platformOrganizationError
          : state.currentView === 'platform-audit'
            ? state.platformAuditError
            : state.currentView === 'platform-users'
              ? state.platformUsersError
              : state.currentView === 'platform-entitlements'
                ? state.platformEntitlementsError
            : null;
    if (isPlatformView(state.currentView) && platformError) {
      if (state.currentView === 'platform' || state.currentView === 'platform-operations') {
        text = platformMetricsUnavailableReason();
      } else {
        text = platformDataUnavailableReason(state.currentView);
      }
      status = platformError.status === 401 || platformError.status === 403 ? 'warning' : 'error';
    } else if (state.currentView === 'settings' && (state.organizationMembersError || state.credentialsError)) {
      const error = state.organizationMembersError ?? state.credentialsError;
      text = customerSettingsUnavailableReason(state.organizationMembersError ? 'members' : 'credentials');
      status = error.status === 401 || error.status === 403 ? 'warning' : 'error';
    } else if (state.overviewError) {
      text = overviewUnavailableReason();
      status = state.overviewError.status === 401 || state.overviewError.status === 403 ? 'warning' : 'error';
    } else if (state.discovery.status !== 'available') {
      text = 'Instance discovery is unavailable. Capability claims are limited to routes implemented by the configured backend.';
      status = 'warning';
    }
    if (!text) {
      nodes.globalBanner.hidden = true;
      return;
    }
    nodes.globalBanner.hidden = false;
    nodes.globalBanner.dataset.state = status;
    nodes.globalBanner.textContent = text;
  }

  function isMobileSidebarViewport() {
    if (typeof window.matchMedia === 'function') {
      return window.matchMedia('(max-width: 900px)').matches;
    }
    return window.innerWidth <= 900;
  }

  function setSidebarFallbackUnavailable(unavailable) {
    const sidebar = state.shell === 'platform' ? nodes.platformSidebar : nodes.sidebar;
    const descendants = sidebar.querySelectorAll(
      'a[href], button, input, select, textarea, [tabindex]',
    );
    for (const node of descendants) {
      if (unavailable) {
        if (!sidebarTabIndexMemory.has(node)) {
          sidebarTabIndexMemory.set(node, node.getAttribute('tabindex'));
        }
        node.setAttribute('tabindex', '-1');
      } else if (sidebarTabIndexMemory.has(node)) {
        const previous = sidebarTabIndexMemory.get(node);
        if (previous === null) node.removeAttribute('tabindex');
        else node.setAttribute('tabindex', previous);
        sidebarTabIndexMemory.delete(node);
      }
    }
  }

  function syncSidebarAccessibility() {
    if (!nodes.sidebar || !nodes.platformSidebar) return;
    const mobile = isMobileSidebarViewport();
    const open = nodes.appView.dataset.navOpen === 'true';
    const unavailable = mobile && !open;
    for (const sidebar of [nodes.sidebar, nodes.platformSidebar]) {
      const hidden = sidebar.hidden;
      if (hidden || mobile) sidebar.setAttribute('aria-hidden', String(hidden || !open));
      else sidebar.removeAttribute('aria-hidden');
      const unavailableForSidebar = hidden || unavailable;
      if ('inert' in sidebar) sidebar.inert = unavailableForSidebar;
      if (unavailableForSidebar) sidebar.setAttribute('data-inert-fallback', 'true');
      else sidebar.removeAttribute('data-inert-fallback');
    }
    setSidebarFallbackUnavailable(unavailable);
  }

  function sidebarFocusableElements() {
    const sidebar = state.shell === 'platform' ? nodes.platformSidebar : nodes.sidebar;
    return [...sidebar.querySelectorAll(
      'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
    )]
      .filter((node) => (
        !node.disabled &&
        node.tabIndex >= 0 &&
        (node === nodes.accountMenuTrigger || !node.closest('details:not([open])')) &&
        getComputedStyle(node).display !== 'none' &&
        getComputedStyle(node).visibility !== 'hidden'
      ));
  }

  function openSidebar() {
    sidebarReturnFocus = document.activeElement instanceof HTMLElement
      ? document.activeElement
      : nodes.sidebarOpen;
    nodes.appView.dataset.navOpen = 'true';
    nodes.sidebarScrim.hidden = false;
    nodes.sidebarOpen.setAttribute('aria-expanded', 'true');
    syncSidebarAccessibility();
    (state.shell === 'platform' ? nodes.platformSidebarClose : nodes.sidebarClose).focus();
  }

  function closeSidebar() {
    const wasOpen = nodes.appView.dataset.navOpen === 'true';
    closeAccountMenu();
    nodes.appView.dataset.navOpen = 'false';
    nodes.sidebarScrim.hidden = true;
    nodes.sidebarOpen.setAttribute('aria-expanded', 'false');
    const returnFocus = sidebarReturnFocus;
    sidebarReturnFocus = null;
    const activeSidebar = state.shell === 'platform' ? nodes.platformSidebar : nodes.sidebar;
    if (returnFocus?.isConnected && !activeSidebar.contains(returnFocus)) {
      returnFocus.focus({ preventScroll: true });
    } else if (wasOpen && isMobileSidebarViewport() && activeSidebar.contains(document.activeElement)) {
      nodes.sidebarOpen.focus({ preventScroll: true });
    }
    syncSidebarAccessibility();
  }

  function handleSidebarKeydown(event) {
    if (!isMobileSidebarViewport() || nodes.appView.dataset.navOpen !== 'true') return;
    if (event.key === 'Escape') {
      event.preventDefault();
      if (nodes.accountMenu?.open) closeAccountMenu({ focusTrigger: true });
      else closeSidebar();
      return;
    }
    if (event.key !== 'Tab') return;
    const focusable = sidebarFocusableElements();
    if (focusable.length === 0) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  nodes.authModeTabs.forEach((tab) => {
    tab.addEventListener('click', () => showAuthMode(tab.dataset.authMode));
    tab.addEventListener('keydown', handleAuthModeKeydown);
  });
  nodes.intakeModeTabs.forEach((tab) => {
    tab.addEventListener('click', () => showIntakeMode(tab.dataset.intakeKind, { focus: true }));
    tab.addEventListener('keydown', handleIntakeModeKeydown);
  });
  nodes.loginForm.addEventListener('submit', handleLogin);
  nodes.registerForm.addEventListener('submit', handleRegistration);
  nodes.registerPassword.addEventListener('input', () => {
    nodes.registerPasswordConfirm.removeAttribute('aria-invalid');
    setRegistrationPasswordError('');
  });
  nodes.registerPasswordConfirm.addEventListener('input', () => {
    nodes.registerPasswordConfirm.removeAttribute('aria-invalid');
    setRegistrationPasswordError('');
  });
  nodes.intakeForm?.addEventListener('submit', handlePublicIntake);
  nodes.logoutButton.addEventListener('click', handleLogout);
  nodes.platformLogoutButton.addEventListener('click', handleLogout);
  nodes.accountMenu?.addEventListener('toggle', handleAccountMenuToggle);
  nodes.accountMenuItems
    .filter((item) => item !== nodes.logoutButton)
    .forEach((item) => item.addEventListener('click', handleAccountMenuAction));
  document.addEventListener('click', handleAccountMenuDocumentClick);
  document.addEventListener('keydown', handleAccountMenuKeydown);
  nodes.refreshButton.addEventListener('click', () => refreshCurrentPageData({ announce: true }));
  nodes.shortcutsButton?.addEventListener('click', () => openShortcutsDialog(nodes.shortcutsButton));
  nodes.shortcutsDialog?.addEventListener('click', handleShortcutsDialogClick);
  nodes.dashboardSearchForm.addEventListener('submit', handleGlobalSearchSubmit);
  nodes.globalSearch.addEventListener('input', handleGlobalSearchInput);
  nodes.globalSearch.addEventListener('keydown', handleGlobalSearchKeydown);
  nodes.sidebarOpen.addEventListener('click', openSidebar);
  nodes.sidebarClose.addEventListener('click', closeSidebar);
  nodes.platformSidebarClose.addEventListener('click', closeSidebar);
  nodes.sidebarScrim.addEventListener('click', closeSidebar);
  document.addEventListener('keydown', handleSidebarKeydown);
  document.addEventListener('keydown', handleShortcutsDialogKeydown, true);
  document.addEventListener('keydown', handleGlobalShortcut);
  nodes.recordSheet?.addEventListener('click', handleRecordSheetClick);
  nodes.recordSheetClose?.addEventListener('click', () => closeRecordSheet());
  document.addEventListener('keydown', handleRecordSheetKeydown, true);
  nodes.pageRegion.addEventListener('input', handleCollectionInput);
  nodes.pageRegion.addEventListener('change', handleCollectionChange);
  nodes.pageRegion.addEventListener('submit', handleCustomerActionSubmit);
  nodes.pageRegion.addEventListener('click', handleSearchResultClick);
  nodes.pageRegion.addEventListener('click', handlePlatformOrganizationClick);
  nodes.pageRegion.addEventListener('click', handleCustomerSettingsClick);
  nodes.themeToggle.addEventListener('click', () => {
    setTheme(document.documentElement.dataset.theme === 'light' ? 'dark' : 'light');
  });
  document.querySelector('[data-intake-link]')?.addEventListener('click', handleIntakeLinkClick);
  nodes.viewLinks.forEach((link) => link.addEventListener('click', handleViewLinkClick));
  nodes.organizationContext?.addEventListener('change', async () => {
    const organizationId = stringValue(nodes.organizationContext.value);
    const membership = organizationMemberships().find((item) => item.id === organizationId);
    if (!membership) {
      renderContextControls();
      return;
    }
    state.profileIndex = membership.profileIndex;
    state.selectedApplication = '';
    state.selectedEnvironment = '';
    renderContextControls();
    await refreshAfterContextChange();
  });
  nodes.profileContext.addEventListener('change', async () => {
    const nextIndex = Number.parseInt(nodes.profileContext.value, 10);
    if (!Number.isInteger(nextIndex) || nextIndex === state.profileIndex) return;
    state.profileIndex = nextIndex;
    state.selectedApplication = '';
    state.selectedEnvironment = '';
    renderContextControls();
    await refreshAfterContextChange();
  });
  nodes.applicationContext.addEventListener('change', () => {
    if (!profileApplicationId()) state.selectedApplication = nodes.applicationContext.value;
    state.selectedEnvironment = '';
    renderContextControls();
    renderCurrentPage();
  });
  nodes.environmentContext.addEventListener('change', () => {
    if (!profileEnvironmentId()) state.selectedEnvironment = nodes.environmentContext.value;
    renderContextControls();
    renderCurrentPage();
  });
  window.addEventListener('popstate', handleLocationChange);
  window.addEventListener('hashchange', handleLocationChange);
  window.addEventListener('resize', () => {
    syncSidebarAccessibility();
    syncAccountMenuPlacement();
  });
  window.addEventListener('pagehide', () => {
    invalidateOverviewRequest();
    invalidatePlatformMetricsRequest();
  });

  nodes.apiBase.value = defaultEndpoint();
  showAuthMode('login', { focus: false });
  if (nodes.intakeForm) showIntakeMode('waitlist');
  setTheme('dark');
  handleAccountMenuToggle();
  syncSidebarAccessibility();
  renderDiscoveryStatus();

  async function bootstrapSession() {
    try {
      const storedSession = readStoredSession();
      if (storedSession) {
        const restored = await restoreSession(storedSession);
        if (!restored) await probeDiscovery();
      } else {
        await probeDiscovery();
      }
    } catch (error) {
      state.api?.clear();
      state.api = null;
      state.identity = null;
      state.overview = null;
      state.overviewError = null;
      state.loading = false;
      clearStoredSession();
      nodes.appView.hidden = true;
      nodes.loginView.hidden = false;
      setLoginMessage(loginErrorMessage(error), 'error');
    } finally {
      document.body?.classList.remove('session-pending');
    }
  }

  bootstrapSession();
})();
