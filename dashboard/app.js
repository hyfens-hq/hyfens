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

  const PAGE_COPY = {
    overview: {
      title: 'Overview',
      description: 'Authoritative record counts and the selected organization context.',
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
    sidebarBrand: document.querySelector('#sidebar-brand'),
    sidebarScrim: document.querySelector('#sidebar-scrim'),
    sidebarOpen: document.querySelector('#sidebar-open'),
    sidebarClose: document.querySelector('#sidebar-close'),
    workspaceName: document.querySelector('#workspace-name'),
    workspaceKind: document.querySelector('#workspace-kind'),
    organizationContext: document.querySelector('#organization-context'),
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

  const state = {
    api: null,
    endpoint: '',
    discovery: { status: 'checking', endpoint: '' },
    identity: null,
    overview: null,
    overviewError: null,
    loading: false,
    lastFetchedAt: null,
    globalSearchQuery: '',
    collectionControls: createCollectionControls(),
    profileIndex: 0,
    selectedApplication: '',
    selectedEnvironment: '',
    currentView: canonicalizeViewLocation(),
  };

  let sidebarReturnFocus = null;
  let recordSheetReturnFocus = null;
  let shortcutsReturnFocus = null;
  let toastTimer = null;
  let overviewRequestGeneration = 0;
  let activeOverviewController = null;
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
    }

    clear() {
      this.accessToken = null;
      this.sessionToken = null;
      this.accessExpiresAt = null;
      this.sessionExpiresAt = null;
    }

    async discover() {
      return unwrapPayload(await this.request('.well-known/hyfens'));
    }

    async login(email, password) {
      return unwrapPayload(
        await this.request('auth/login', {
          method: 'POST',
          body: { email, password },
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

    async request(path, { method = 'GET', body, requiresAuth = false, retry = true, signal } = {}) {
      if (requiresAuth && !this.accessToken) throw new SessionExpiredError();
      const url = new URL(path.replace(/^\/+/, ''), this.baseUrl);
      const headers = { Accept: 'application/json' };
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
    if (window.location.hostname === 'app.hyfens.com') return 'https://api.hyfens.com/';
    return `${window.location.origin}/`;
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
    const pathValue = window.location.pathname.replace(/^\/+|\/+$/g, '');
    const hashValue = window.location.hash.replace(/^#/, '');
    const value = pathValue || hashValue || 'overview';
    return Object.prototype.hasOwnProperty.call(PAGE_COPY, value) ? value : 'overview';
  }

  function viewPath(view) {
    return view === 'overview' ? '/' : `/${view}`;
  }

  function canonicalizeViewLocation() {
    const view = viewFromLocation();
    const path = viewPath(view);
    if (
      window.location.pathname !== path ||
      window.location.search ||
      window.location.hash
    ) {
      window.history.replaceState({}, '', path);
    }
    return view;
  }

  function navigateToView(view) {
    const nextView = Object.prototype.hasOwnProperty.call(PAGE_COPY, view) ? view : 'overview';
    const path = viewPath(nextView);
    const isCanonical = (
      window.location.pathname === path &&
      !window.location.search &&
      !window.location.hash
    );
    if (!isCanonical) window.history.pushState({}, '', path);
    state.currentView = nextView;
    renderCurrentPage({ transition: true });
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
    wrapper.append(element('strong', '', stringValue(value) ?? 'Not set'));
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

  function selectedProfile() {
    const profiles = profileList();
    return profiles[state.profileIndex] ?? profiles[0] ?? null;
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

  function renderApplicationsPage() {
    if (!state.overview) return unavailablePage('Applications', overviewUnavailableReason());
    const body = state.overview;
    const items = scopedItems('applications');
    return collectionPanel(
      body,
      'applications',
      'Applications',
      'Runtime application identities registered for the selected organization.',
      ['Application', 'Runtime identity', 'Created', 'Exact record'],
      items,
      (item) => tableRow([
        primaryCell(recordId(item)),
        codeValue(pick(item, 'runtimeApplicationId')),
        dateValue(pick(item, 'createdAt')),
        exactRecordDetails(item),
      ]),
      'The control plane returned no application records for this membership scope.',
    );
  }

  function renderEnvironmentsPage() {
    if (!state.overview) return unavailablePage('Environments', overviewUnavailableReason());
    const body = state.overview;
    const items = scopedItems('environments');
    return collectionPanel(
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
    );
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

  function renderDeploymentsPage() {
    if (!state.overview) return unavailablePage('Deployment records', overviewUnavailableReason());
    const body = state.overview;
    const items = scopedItems('rollouts');
    return collectionPanel(
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
    );
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
      metadataItem('Endpoint', state.endpoint, { code: true }),
      metadataItem('Access token expiry', state.api?.accessExpiresAt ? formatDateText(state.api.accessExpiresAt) : 'Not returned'),
      metadataItem('Session expiry', state.api?.sessionExpiresAt ? formatDateText(state.api.sessionExpiresAt) : 'Not returned'),
      metadataItem('Selected role', pick(profile, 'role')),
    );
    sessionPanel.body.append(fields);
    sessionPanel.body.append(element('p', 'settings-note', 'Sign out revokes the shared human session when the control plane responds. Session material is cleared from this tab even if the remote service is unavailable.'));

    const membershipsPanel = makePanel(
      'Memberships',
      'Profiles returned by /auth/me. Application and environment scope is not broadened in the browser.',
      `${profileList().length} returned`,
    );
    const list = element('ul', 'membership-list');
    if (profileList().length === 0) {
      list.append(stateBlock('unavailable', 'Membership unavailable', 'The auth service did not return a membership profile.'));
    } else {
      for (const item of profileList()) {
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

    const apiKeysPanel = makePanel(
      'API keys',
      'Machine authentication is separate from a human browser session.',
      'Unavailable',
    );
    apiKeysPanel.body.append(
      stateBlock(
        'unavailable',
        'API-key management is not available here',
        'The current backend does not expose a browser-safe credential inventory contract. Create and revoke actions are intentionally omitted. No API key is generated by this page.',
      ),
    );

    const stack = element('div', 'settings-grid');
    const left = element('div', 'page-stack');
    left.append(sessionPanel.section, membershipsPanel.section);
    const right = element('div', 'page-stack');
    right.append(apiKeysPanel.section);
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
    const profiles = profileList();
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
      profiles.map((item, index) => ({
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
      const loginPayload = await api.login(email, password);
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
    await loadOverview();
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
    state.profileIndex = 0;
    state.selectedApplication = '';
    state.selectedEnvironment = '';
    state.lastFetchedAt = null;
    resetDashboardInteractionState();
    renderShellIdentity();
    renderContextControls();
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
        organizationId: pick(profile, 'organization_id', 'organizationId'),
        organizationName: pick(profile, 'organization_name', 'organizationName')
          ?? pick(objectValue(pick(profile, 'organization')), 'name'),
        applicationId: pick(profile, 'application_id', 'applicationId'),
        environmentId: pick(profile, 'environment_id', 'environmentId'),
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
    state.api?.clear();
    state.api = null;
    clearStoredSession();
    state.identity = null;
    state.overview = null;
    state.overviewError = null;
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
    nodes.logoutButton.disabled = true;
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
    const globalQuery = normalizeSearchQuery(state.globalSearchQuery);
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
      const active = link.dataset.viewLink === state.currentView;
      if (active) link.setAttribute('aria-current', 'page');
      else link.removeAttribute('aria-current');
    }
    renderGlobalBanner();
    renderLastFetched();
    nodes.refreshButton.disabled = state.loading || !state.api;
    nodes.refreshButton.setAttribute('aria-busy', String(state.loading));
    nodes.pageRegion.setAttribute('aria-busy', state.loading ? 'true' : 'false');
    if (state.loading) {
      replacePageRegion(renderLoadingState(), { transition });
      return;
    }
    if (globalQuery) {
      replacePageRegion(renderGlobalSearchPage(), { transition });
      return;
    }
    const page = {
      overview: renderOverviewPage,
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

  function handleViewLinkClick(event) {
    event.preventDefault();
    clearGlobalSearch({ render: false });
    closeSidebar();
    navigateToView(event.currentTarget.dataset.viewLink);
  }

  function handleIntakeLinkClick(event) {
    event.preventDefault();
    nodes.intakeSection?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function handleLocationChange() {
    state.currentView = canonicalizeViewLocation();
    renderCurrentPage({ transition: true });
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
      if (hasBlockingKeyboardLayer()) return;
      event.preventDefault();
      nodes.globalSearch.focus({ preventScroll: true });
      nodes.globalSearch.select();
      return;
    }

    if (hasBlockingKeyboardLayer() || event.repeat) return;

    if (!event.shiftKey && event.key.toLowerCase() === 'r') {
      if (nodes.refreshButton.disabled) return;
      event.preventDefault();
      void loadOverview({ announce: true });
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
    if (state.overviewError) {
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
    const descendants = nodes.sidebar.querySelectorAll(
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
    if (!nodes.sidebar) return;
    const mobile = isMobileSidebarViewport();
    const open = nodes.appView.dataset.navOpen === 'true';
    const unavailable = mobile && !open;
    if (mobile) nodes.sidebar.setAttribute('aria-hidden', String(!open));
    else nodes.sidebar.removeAttribute('aria-hidden');

    if ('inert' in nodes.sidebar) nodes.sidebar.inert = unavailable;
    setSidebarFallbackUnavailable(unavailable);
    if (unavailable) nodes.sidebar.setAttribute('data-inert-fallback', 'true');
    else nodes.sidebar.removeAttribute('data-inert-fallback');
  }

  function sidebarFocusableElements() {
    return [
      nodes.sidebarBrand,
      nodes.sidebarClose,
      nodes.organizationContext,
      ...nodes.viewLinks,
      nodes.accountMenuTrigger,
      ...nodes.accountMenuItems,
    ]
      .filter((node, index, all) => node && all.indexOf(node) === index)
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
    nodes.sidebarClose.focus();
  }

  function closeSidebar() {
    const wasOpen = nodes.appView.dataset.navOpen === 'true';
    closeAccountMenu();
    nodes.appView.dataset.navOpen = 'false';
    nodes.sidebarScrim.hidden = true;
    nodes.sidebarOpen.setAttribute('aria-expanded', 'false');
    const returnFocus = sidebarReturnFocus;
    sidebarReturnFocus = null;
    if (returnFocus?.isConnected && !nodes.sidebar.contains(returnFocus)) {
      returnFocus.focus({ preventScroll: true });
    } else if (wasOpen && isMobileSidebarViewport() && nodes.sidebar.contains(document.activeElement)) {
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
  nodes.accountMenu?.addEventListener('toggle', handleAccountMenuToggle);
  nodes.accountMenuItems
    .filter((item) => item !== nodes.logoutButton)
    .forEach((item) => item.addEventListener('click', handleAccountMenuAction));
  document.addEventListener('click', handleAccountMenuDocumentClick);
  document.addEventListener('keydown', handleAccountMenuKeydown);
  nodes.refreshButton.addEventListener('click', () => loadOverview({ announce: true }));
  nodes.shortcutsButton?.addEventListener('click', () => openShortcutsDialog(nodes.shortcutsButton));
  nodes.shortcutsDialog?.addEventListener('click', handleShortcutsDialogClick);
  nodes.dashboardSearchForm.addEventListener('submit', handleGlobalSearchSubmit);
  nodes.globalSearch.addEventListener('input', handleGlobalSearchInput);
  nodes.globalSearch.addEventListener('keydown', handleGlobalSearchKeydown);
  nodes.sidebarOpen.addEventListener('click', openSidebar);
  nodes.sidebarClose.addEventListener('click', closeSidebar);
  nodes.sidebarScrim.addEventListener('click', closeSidebar);
  document.addEventListener('keydown', handleSidebarKeydown);
  document.addEventListener('keydown', handleShortcutsDialogKeydown, true);
  document.addEventListener('keydown', handleGlobalShortcut);
  nodes.recordSheet?.addEventListener('click', handleRecordSheetClick);
  nodes.recordSheetClose?.addEventListener('click', () => closeRecordSheet());
  document.addEventListener('keydown', handleRecordSheetKeydown, true);
  nodes.pageRegion.addEventListener('input', handleCollectionInput);
  nodes.pageRegion.addEventListener('change', handleCollectionChange);
  nodes.pageRegion.addEventListener('click', handleSearchResultClick);
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
    await loadOverview();
  });
  nodes.profileContext.addEventListener('change', async () => {
    const nextIndex = Number.parseInt(nodes.profileContext.value, 10);
    if (!Number.isInteger(nextIndex) || nextIndex === state.profileIndex) return;
    state.profileIndex = nextIndex;
    state.selectedApplication = '';
    state.selectedEnvironment = '';
    renderContextControls();
    await loadOverview();
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
