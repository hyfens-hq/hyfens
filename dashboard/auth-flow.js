(() => {
  'use strict';

  const MANAGED_DASHBOARD_HOSTNAMES = new Set(['app.hyfens.com']);

  function isLoopback(hostname) {
    return hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '[::1]' || hostname === '::1';
  }

  function normalizeApiBase(value) {
    const uri = new URL(value);
    if (uri.username || uri.password || uri.search || uri.hash || !uri.host) {
      throw new Error('The control-plane API base must not contain credentials, query parameters, or fragments.');
    }
    if (uri.protocol !== 'https:' && !(uri.protocol === 'http:' && isLoopback(uri.hostname))) {
      throw new Error('Remote control-plane connections require HTTPS.');
    }
    return uri.toString().endsWith('/') ? uri.toString() : `${uri.toString()}/`;
  }

  function apiBase() {
    const configured = document.querySelector('meta[name="hyfens-api-base"]')?.content.trim();
    if (configured) return normalizeApiBase(configured);
    const runtime = window.__HYFENS_RUNTIME_CONFIG__?.apiBase?.trim();
    if (runtime) return normalizeApiBase(runtime);
    if (MANAGED_DASHBOARD_HOSTNAMES.has(window.location.hostname.toLowerCase())) {
      return normalizeApiBase('https://api.hyfens.com/');
    }
    return normalizeApiBase(`${window.location.origin}/`);
  }

  function displayApiBase() {
    return new URL(apiBase()).hostname.toLowerCase() === 'api.hyfens.com'
      ? 'Hyfens Cloud (managed)'
      : apiBase();
  }

  async function request(path, options = {}) {
    const headers = { Accept: 'application/json', ...(options.headers || {}) };
    const response = await fetch(new URL(path.replace(/^\//, ''), apiBase()), {
      ...options,
      headers,
      credentials: 'omit',
    });
    let data = {};
    try { data = await response.json(); } catch (_) { data = {}; }
    if (!response.ok) {
      const code = data?.error?.code || data?.error || `HTTP ${response.status}`;
      throw new Error(`The control plane rejected this request (${code}).`);
    }
    return data;
  }

  function jsonOptions(body, accessToken) {
    return {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
      },
      body: JSON.stringify(body),
    };
  }

  function setMessage(node, message, state) {
    node.textContent = message;
    if (state) node.dataset.state = state;
    else delete node.dataset.state;
  }

  window.HyfensAuthFlow = Object.freeze({ apiBase, displayApiBase, jsonOptions, request, setMessage });
})();
